# Deploy and Host Orca on Railway

[Orca](https://github.com/stablyai/orca) is an agent development environment: worktrees, terminals
and long-running coding-agent sessions in one workspace. This template deploys a **Remote Orca
Server** — Orca 1.4.261 running headless on Railway — so that workspace lives on a machine that
stays awake, and you pair your desktop, browser or phone to it.

## About Hosting Orca

Orca is an Electron desktop application, and upstream ships desktop packages rather than a container
image. This template installs the published Debian package, verified against a pinned digest, and
runs Linux's plain-Node `orcad` through the foreground `orca serve` CLI. No virtual display sits
between Tini and the CLI: normal stop reaches the daemon's graceful teardown and lock release.
The image supplies the packaged executable's missing shared library and runs as a non-root user.
A nonblocking kernel lock prevents two updated containers from owning the profile at once without
changing machine identity or deleting an upstream lock.

There is nothing to fill in before deploying. Orca mints a pairing identity on first boot and prints
the pairing URL to the deploy log, and a volume keeps that identity — along with your repositories,
agent accounts and configuration — across redeploys.

## Common Use Cases

- Keep a coding agent working on a long task in a workspace you can check on from anywhere.
- Drive worktrees, terminals and agent sessions from a tablet or phone, with the work running on a
  machine that does not sleep or close its lid.
- Give a project a persistent development environment separate from your laptop.

## Dependencies for Orca Hosting

- A volume for the workspace, which the template creates.
- A **Hobby plan or better** for actual agent sessions. The server idles at about 0.2 GB of RAM, and
  a coding agent spawned inside a session needs more than the Free plan's 0.5 GB per service leaves.
  Free and Trial volumes are also capped at 0.5 GB, below the 5 GB this template asks for.
- Nothing else. No database, no external service, no account to register.

### Deployment Dependencies

- [Orca](https://github.com/stablyai/orca) — the upstream project (MIT).
- [Orca documentation](https://www.onorca.dev/docs/ways-to-run) — including Remote Orca Servers.
- [Template repository](https://github.com/RockinPaul/orca_railway_template) (MIT).

### Implementation Details

One service builds from this template's repository:

- **orca** — `debian:13-slim` with `orca-ide` 1.4.261 installed from the upstream `.deb`, checked
  against a pinned SHA-256 for each architecture. It serves HTTP and WebSocket on port 8080, answers
  the platform health check on `/`, and mounts a volume at `/data`.

The service's home directory is on that volume, set in `/etc/passwd` rather than only in the
environment, because the entrypoint drops privileges and that resets `HOME` from the passwd entry.
This is what makes the pairing identity stable: without it every redeploy mints a new one and the
URL you saved stops working.

The address clients dial is derived at boot as `wss://$RAILWAY_PUBLIC_DOMAIN`. Orca advertises
whatever address it is given verbatim, and a bare hostname produces a `ws://host:8080` URL that
Railway's edge — TLS on 443 only — cannot serve.

**First run:** open the service's deploy logs and find the `Web client URL` and `Pairing URL` lines.
Open the web client in a browser, or paste the pairing URL into Orca desktop under *Settings →
Remote Orca Servers → Add Server*. Install the agents you want from a shell on the service
(`orca account add --agent claude`), because the remote client disables *Add account*.

**The pairing URL is the credential for this deployment.** Anyone who has it controls the workspace,
and agents in it run shell commands, so treat it like a password. The transport is fail-closed: the
WebSocket upgrade is anonymous by necessity, and the device token is then presented inside an
encrypted channel, with a bad token closing the connection. Remote Orca Servers is **beta**;
a private tailnet or LAN reduces exposure, while this template uses a public Railway endpoint
with the device credential as its access boundary.

The `wss://` pairing host accepts public connections in this release; no `--allow-public` flag is
needed, and pairing is still required.

**Existing deployments need preparation before the first upgrade.** If production tracks `main`,
merging may trigger deployment before a backup can be taken. Check the effective restart policy,
establish a maintenance hold where needed, gracefully stop the verified daemon in the **old**
container, and validate a lock-free whole-volume backup plus the original image before proceeding.
Do not automatically delete foreign locks or assume this wrapper fixes the old container's shutdown.
Follow the [first-upgrade and rollback runbook](https://github.com/RockinPaul/orca_railway_template/blob/main/README.md#first-upgrade-from-the-old-wrapper).

On first start, upstream converts the legacy chat journal into a separate database; chats,
pairing, files and settings carry over. Downgrading only the image afterwards hides chats created
after the upgrade, so roll back by restoring the pre-upgrade backup together with the old image.

Two limits are worth knowing. Running sessions end when the service redeploys, because a redeploy
replaces the container — files on the volume survive, terminals and agent sessions do not. And
upstream releases every day or two, so the pinned version moves quickly; the template repository
documents how to bump it.

## Why Deploy Orca on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Orca on Railway, you are one step closer to supporting a complete full-stack
application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
