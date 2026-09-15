# Deploy and Host Orca on Railway

[Orca](https://github.com/stablyai/orca) is an agent development environment: worktrees, terminals
and long-running coding-agent sessions in one workspace. This template deploys a **Remote Orca
Server** — Orca 1.4.203 running headless on Railway — so that workspace lives on a machine that
stays awake, and you pair your desktop, browser or phone to it.

## About Hosting Orca

Orca is an Electron desktop application, and upstream ships desktop packages rather than a container
image. This template installs the published Debian package, verified against a pinned digest, and
runs its documented `orca serve` mode. Running Electron headless on a platform container takes four
things that are easy to get wrong: a virtual display, one shared library the package does not
declare, a non-root user, and a disabled Chromium sandbox — all of them are handled in the image.

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
- Nothing else. No database, no external service, no account to register.

### Deployment Dependencies

- [Orca](https://github.com/stablyai/orca) — the upstream project (MIT).
- [Orca documentation](https://www.onorca.dev/docs/ways-to-run) — including Remote Orca Servers.
- [Template repository](https://github.com/RockinPaul/orca_railway_template) (MIT).

### Implementation Details

One service builds from this template's repository:

- **orca** — `debian:13-slim` with `orca-ide` 1.4.203 installed from the upstream `.deb`, checked
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
encrypted channel, with a bad token closing the connection. Note that upstream marks Remote Orca
Servers **beta** and scopes them to a private network path such as a tailnet or LAN; a Railway
domain is public, so this runs the feature further out than upstream intends.

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
