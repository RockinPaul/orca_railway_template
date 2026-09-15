# Orca — agent development environment (https://github.com/stablyai/orca)
#
# Upstream ships desktop packages, not container images, and no Dockerfile. This
# installs the published .deb and runs its documented headless mode, `orca serve`.
FROM debian:13-slim

ARG ORCA_VERSION=1.4.203
ARG ORCA_SHA256_AMD64=7515eb6126364089cc3094ab65125c478ae897ed972e2d5f3d1d2f70d5b87e3b
ARG ORCA_SHA256_ARM64=17140fea62d872337eab56c551a77d420eecdfc1b1fba740db6c3669e0753f1a
ARG TARGETARCH

# The .deb pulls the whole GTK/X stack (~280 packages): Orca is an Electron app, and
# "headless" here means no window, not no display — xvfb is one of its own declared
# dependencies. libasound2 is NOT declared but is required: without it the binary dies
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
    # xauth: xvfb-run needs it and it is only a *recommends* of the xvfb chain, so
    # --no-install-recommends drops it and every launch dies with
    # "xvfb-run: error: xauth command not found".
    apt-get install -y --no-install-recommends libasound2t64 xauth git openssh-client nodejs npm; \
    rm -f /tmp/orca.deb; \
    rm -rf /var/lib/apt/lists/*; \
    orca-ide --version

# Orca runs as a non-root user. Electron refuses to start as root without --no-sandbox,
# and the CLI rejects unknown flags so that switch cannot be passed through; a non-root
# user is the supported path. ELECTRON_DISABLE_SANDBOX is still required because
# Chromium's namespace sandbox needs CLONE_NEWUSER, which Railway's seccomp profile
# denies — the container itself is the isolation boundary here.
RUN useradd -m -u 1000 -s /bin/bash orca

ENV PORT=8080 \
    HOME=/data/home \
    ORCA_STATE_DIR=/data/home \
    NPM_CONFIG_PREFIX=/data/npm-global \
    ELECTRON_DISABLE_SANDBOX=1 \
    PATH=/data/npm-global/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

WORKDIR /data/home
EXPOSE 8080

COPY --chmod=755 entrypoint.sh /usr/local/bin/railway-entrypoint
# tini reaps Xvfb and the Electron/Chromium process tree.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/railway-entrypoint"]
