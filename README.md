# Orca on Railway

A Remote [Orca](https://github.com/stablyai/orca) Server — the agent development environment,
running headless on Railway so your worktrees, terminals and agent sessions live on a machine that
stays awake. Pair your desktop, browser or phone to it.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/orca)

## Service

| Service | Base | Public | Role |
|---|---|---|---|
| `orca` | `debian:13-slim` + `orca-ide` 1.4.203 | **yes** | The runtime server, with `/data` as its home. |

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
| `ELECTRON_DISABLE_SANDBOX` | `1` | Baked. Required; see below. |

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

That said, **upstream scopes Remote Orca Servers to private networks**: the feature is marked beta,
and the documentation says to keep the server and client "on a private network path you control,
such as the same Tailscale tailnet or LAN". A Railway domain is public. The token holds the door,
but you are running this further out than upstream intends.

Agents in this workspace run commands, so the blast radius is a shell.

## What persists

`/data/home` is the server's home directory, so projects, worktrees, `.orca` state, agent
configuration and the pairing token all survive redeploys. `/data/npm-global` keeps globally
installed npm packages.

**Sessions do not persist.** A redeploy replaces the container, which ends running terminals and
agent sessions. Files on the volume are untouched.

## Why it is shaped this way

- **Orca is an Electron app, and "headless" means no window, not no display.** `xvfb` is one of its
  own declared dependencies, and `xvfb-run` also needs `xauth`, which is only a *recommends* — with
  `--no-install-recommends` every launch dies with `xvfb-run: error: xauth command not found`.
- **`libasound2` is required but not declared.** Without it the binary fails at load with
  `error while loading shared libraries: libasound.so.2`.
- **`ELECTRON_DISABLE_SANDBOX=1` and a non-root user are both required.** Electron refuses to run as
  root without `--no-sandbox`, and Orca's CLI rejects unknown flags so that switch cannot be passed
  through. As a non-root user, Chromium's namespace sandbox needs `CLONE_NEWUSER`, which Railway's
  seccomp profile denies. Disabling the sandbox is what makes it run; the container is then the
  isolation boundary.
- **The pairing address must be a `wss://` URL.** Orca advertises whatever you give it verbatim: a
  bare hostname produces `ws://host:8080`, which Railway's edge — TLS on 443 only — can never serve.
  The `wss://` form drops the port and uses TLS.

## Upgrading Orca

Bump `ORCA_VERSION` in the `Dockerfile` **and** the matching `ORCA_SHA256_*` digests, then push.
Upstream releases every day or two, and all releases are marked stable.

## Licences

Orca is [MIT](https://github.com/stablyai/orca/blob/main/LICENSE). The glue in this repository is
MIT as well.
