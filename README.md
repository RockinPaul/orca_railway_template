# Orca on Railway

A Remote [Orca](https://github.com/stablyai/orca) Server — the agent development environment,
running headless on Railway so your worktrees, terminals and agent sessions live on a machine that
stays awake. Pair your desktop, browser or phone to it.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/orca)

## Service

| Service | Base | Public | Role |
|---|---|---|---|
| `orca` | `debian:13-slim` + `orca-ide` 1.4.261 | **yes** | The runtime server, with `/data` as its home. |

One service, no gateway: Orca serves plain HTTP and WebSocket on a port it takes from the
environment, which is what Railway's edge expects. Upstream publishes desktop packages rather than a
server image — the Dockerfiles in its repository are CI harnesses for testing headless pairing — so
this installs the published `.deb` and runs its documented `orca serve` mode.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `ORCA_PAIRING_ADDRESS` | `wss://$RAILWAY_PUBLIC_DOMAIN` | The address clients dial, derived at boot. Override only for a custom domain. |
| `PORT` | `8080` | Baked into the image. |
| `HOME` | `/data/home` | Baked. Orca's state — `.orca`, `.config`, `.local` — on the volume. |
| `NPM_CONFIG_PREFIX` | `/data/npm-global` | Baked. `npm i -g` survives redeploys. |
| `ELECTRON_DISABLE_SANDBOX` | `1` | Packaged Electron compatibility setting; standard Linux `serve` uses plain-Node `orcad`, not a Chromium window. |

The template asks for nothing. There is no password to set: Orca mints a pairing token on first
boot and prints the pairing URL to the deploy log.

## First run

1. Open the `orca` service's **deploy logs** and find the two lines near the end:

   ```
   Web client URL: https://YOUR-DOMAIN/web-index.html#pairing=orca%3A%2F%2Fpair%3Fcode%3D...
   Pairing URL:    orca://pair?code=...
   ```

2. Open the **Web client URL** in a browser, or paste the **Pairing URL** into Orca desktop under
   *Settings → Remote Orca Servers → Add Server*.
3. Install and authenticate the agents you want **from a shell on this service**, because the remote
   client disables *Add account*:

   ```
   orca account add --agent claude
   orca account add --agent codex
   orca skills install --skill orca-cli --skill orchestration
   ```

**The pairing URL is the credential.** Anyone who has it controls this runtime. It is stable across
redeploys because it lives on the volume, so treat it like a password and do not paste it anywhere
public.

## Security

Orca is fail-closed, which is the main reason this was worth building. Verified directly against the
running server:

- The WebSocket upgrade succeeds for anyone, then the client must present its device token **inside**
  the encrypted channel (`e2ee_hello` → `e2ee_ready` → `e2ee_auth`). The anonymous key exchange is
  necessary — you need the channel before you can send the secret.
- A connection that presents a bogus token is closed with **`4001 Unauthorized`**, measured, not
  assumed.

Remote Orca Servers is **beta**. A private LAN or tailnet reduces exposure; this template uses a
public Railway endpoint and its configured pairing address, with the encrypted device credential
as the access boundary.

Agents in this workspace run commands, so the blast radius is a shell.

Version 1.4.261 checks the TCP peer's source address before HTTP/WebSocket parsing.
The template's custom `wss://$RAILWAY_PUBLIC_DOMAIN` advertisement already opts into public
sources, so no blanket `--allow-public` flag is added. `Origin` and `X-Forwarded-For` are not the
TCP peer; `--refuse-public` is therefore not a login gate behind a reverse proxy. A real isolated
public-classified peer outside the server's interface prefix was admitted with the old pairing
credential; a bogus credential closed with 4001. The `--refuse-public` control rejected that peer
before HTTP and logged its actual address.

## What persists

`/data/home` is the server's home directory, so projects, worktrees, `.orca` state, agent
configuration and the pairing token all survive redeploys. `/data/npm-global` keeps globally
installed npm packages.

**Sessions do not persist.** A redeploy replaces the container, which ends running terminals and
agent sessions. Files on the volume are untouched.

## Why it is shaped this way

- **Linux `serve` runs plain-Node `orcad` without a virtual display.** The package still includes
  desktop libraries, but inserting `xvfb-run` between Tini and the foreground CLI can strand the
  daemon's lock during container shutdown. The wrapper now execs the CLI directly; its signal
  handler waits for daemon teardown. Actual `docker stop` exited 0 and removed the upstream lock,
  then a replacement container served the same profile without hand-signalling or lock deletion.
- **`libasound2` is required but not declared.** Without it the binary fails at load with
  `error while loading shared libraries: libasound.so.2`.
- **One runtime owns the volume.** A nonblocking kernel `flock --no-fork` holds
  `/data/home/.orca-railway.lock` while preserving direct signal delivery. A second updated
  container sharing the profile is refused with exit 75, including across PID namespaces where
  upstream's PID/machine-id inspection alone was insufficient. The lock releases with the process;
  its empty file can remain. Do not unlink it, share the profile with an unguarded old wrapper, or
  run multiple replicas. No machine-id persistence or automatic foreign-lock deletion is used.
- **The pairing address must be a `wss://` URL.** Orca advertises whatever you give it verbatim: a
  bare hostname produces `ws://host:8080`, which Railway's edge — TLS on 443 only — can never serve.
  The `wss://` form drops the port and uses TLS.

## Upgrading Orca

### First upgrade from the old wrapper

**Do not merge first when production tracks `main`: the merge can deploy immediately.** Coordinate
a maintenance window and retain the original immutable deployment image plus a consistent backup
of the **whole `/data` volume**, not only one SQLite file. The new wrapper cannot retroactively
fix shutdown of the old container.

1. Read the service's effective restart policy and active instances from Railway's control plane;
   do not infer them from `railway.json`. With `ON_FAILURE`, the rehearsed clean exit 0 stays stopped.
   With `ALWAYS` or an external supervisor, establish an approved maintenance hold first. Confirm
   no replacement starts during backup. This procedure does not disable deployment automation.
2. While still in the **old** container, stop active work and use its existing Node executable to
   verify and gracefully signal the recorded daemon. For the template's default profile, the
   following was rehearsed; it aborts on a foreign identity, reused PID or unexpected process:

   ```bash
   node <<'NODE'
   const fs = require('fs'), assert = require('assert/strict');
   const owner = JSON.parse(fs.readFileSync('/data/home/.config/orca/orcad.lock', 'utf8'));
   assert.equal(owner.machineIdentity, fs.readFileSync('/etc/machine-id', 'utf8').trim());
   assert.equal(owner.bootId, fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim());
   const cmd = fs.readFileSync('/proc/' + owner.pid + '/cmdline', 'utf8');
   assert(cmd.includes('orcad-server.js'));
   const stat = fs.readFileSync('/proc/' + owner.pid + '/stat', 'utf8');
   const ticks = stat.slice(stat.lastIndexOf(')') + 2).trim().split(/\s+/)[19];
   assert.equal(String(owner.linuxStartTicks), ticks);
   console.log('Stopping verified Orca daemon PID ' + owner.pid);
   process.kill(owner.pid, 'SIGTERM');
   NODE
   ```

3. Observe clean exit **and removal of `orcad.lock` before taking the prepared backup**, and verify
   the service stays stopped; then take/validate the full-volume backup. Never delete a foreign lock or use
   `--force` as a migration step. Upstream's reclaim command also refuses a different machine-id;
   if graceful preparation cannot be confirmed, stop the rollout and investigate the owner.
4. Only after that checkpoint deploy the approved new image, using the same exclusive volume and
   pairing identity. Verify paired access, first/final paginated chat history, queued/empty chats,
   files/settings and new writes. Restore the approved restart policy if maintenance changed it.
   Future replacements using this wrapper use normal platform stop; the direct CLI waits for lock
   release. Local `ON_FAILURE` preparation, an explicit `ALWAYS` maintenance hold, and normal new
   wrapper stop/replacement were tested separately. No live Railway rollout was performed.

### Chat-store conversion and rollback

Upstream creates `agent-session-domain.db` beside retained `agent-session-journal.db`, imports
through its own atomic conversion path, and loads history on demand. Keep both files and the rest
of the home. A Linux/amd64 old→new rehearsal preserved 100 synthetic turns / 300 journal items
across three real RPC pages, including the first and final content, plus empty/queued-only chats,
the queued draft, file/settings identities and the exact original pairing credential.

**Image-only downgrade is not a complete rollback.** The old image reads the retained legacy
journal, so target-only chats are invisible. Continuing an old chat after downgrade and returning
to the new version intentionally preserves it as a **second chat** rather than merging histories.
In the rehearsal the original 300-item chat remained, and the continued 303-item variant retained
turn 101. Old-version queue-reopen tombstones also changed a queued-only chat's source revision,
producing a recovered queue variant. Repeated target starts retained the same seven record IDs
and four source receipts without further inflation; this is not a promise of deduplication after
arbitrary old-version writes.

For rollback, stop the sole runtime cleanly, restore the untouched pre-upgrade **whole-volume**
backup and original immutable image, then verify pairing/history/files before resuming writes.
This was tested on a separate copy: backup hashes matched before startup, the original 300 items,
queued/empty chats, files/settings and pairing returned, and real file writes still worked.
Post-backup changes are not in that backup; preserve them separately before deciding to restore.

Transcript fixtures were written through the exact old production persistence APIs; real old/new
packages performed startup/import and paginated paired reads. No paid agent round-trip, provider
account re-authentication, browser interaction or live Railway deployment is claimed. Both release
package hashes were verified for amd64/arm64; runtime rehearsals used Linux/amd64.

The durable wrapper regression is `sh test-replacement.sh IMAGE` after building this Dockerfile.
It checks cross-container exclusion, normal stop/lock release and replacement using a fresh test
volume; it refuses existing test names and retains its named resources/private logs for inspection.

## Licences

Orca is [MIT](https://github.com/stablyai/orca/blob/main/LICENSE). The glue in this repository is
MIT as well.
