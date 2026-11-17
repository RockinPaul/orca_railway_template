# Orca — agent development environment (https://github.com/stablyai/orca)
#
# Upstream ships desktop packages, not container images, and no Dockerfile. This
# installs the published .deb and runs its headless plain-Node `orca serve` mode.
FROM debian:13-slim

ARG ORCA_VERSION=1.4.261
ARG ORCA_SHA256_AMD64=86755b4c6e7e25d2ef4aadd5d2508bf52520d15f8ef45fa99e74cec7431e5c1c
ARG ORCA_SHA256_ARM64=d1462086cb0aef7fade8983011642ae38adc08ebe54dc54d8f5d4a03b0b342bc
ARG TARGETARCH

# The .deb still pulls the GTK/X stack: Orca's package includes its desktop app,
# although Linux serve now uses orcad without a display. libasound2 is NOT declared
# but is required by the packaged executable: without it the binary dies
# with "error while loading shared libraries: libasound.so.2".
#
# git is needed for repo worktrees; node and npm are here so the coding agents people
# run inside Orca (Claude Code, Codex, Gemini CLI, OpenCode) can be installed at all.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    case "${TARGETARCH}" in \
        amd64) arch_pkg="amd64"; sha="${ORCA_SHA256_AMD64}" ;; \
        arm64) arch_pkg="arm64"; sha="${ORCA_SHA256_ARM64}" ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gosu tini; \
    curl -fsSL -o /tmp/orca.deb \
        "https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}/orca-ide_${ORCA_VERSION}_${arch_pkg}.deb"; \
    echo "${sha}  /tmp/orca.deb" | sha256sum -c -; \
    apt-get install -y --no-install-recommends /tmp/orca.deb; \
    apt-get install -y --no-install-recommends libasound2t64 git openssh-client nodejs npm; \
    rm -f /tmp/orca.deb; \
    rm -rf /var/lib/apt/lists/*; \
    orca-ide --version

# Orca runs as a non-root user; standard Linux serve uses plain-Node orcad.
# The home directory must be /data/home in /etc/passwd, not just in ENV: gosu (like
# su) resets HOME from the passwd entry for the target user, so an inherited
# HOME=/data/home is silently overridden and Orca writes its state — including the
# pairing identity — into the image layer, which every redeploy throws away.
# -M because /data is a mount point that does not exist at build time; the
# entrypoint creates and chowns it.
RUN useradd -u 1000 -d /data/home -M -s /bin/bash orca

ENV PORT=8080 \
    HOME=/data/home \
    ORCA_STATE_DIR=/data/home \
    NPM_CONFIG_PREFIX=/data/npm-global \
    ELECTRON_DISABLE_SANDBOX=1 \
    PATH=/data/npm-global/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

WORKDIR /data/home
EXPOSE 8080

COPY --chmod=755 entrypoint.sh /usr/local/bin/railway-entrypoint
# tini signals the foreground CLI, which waits for orcad to release its instance lock.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/railway-entrypoint"]
