#!/bin/sh
set -eu

# Railway mounts the volume root-owned with a lost+found directory, so everything
# lives in subdirectories, created here and handed to the unprivileged user.
mkdir -p "${HOME}" "${NPM_CONFIG_PREFIX:-/data/npm-global}"

# useradd ran with -M, so the shell skeleton was never copied. Seed it once, on a
# genuinely empty home, so interactive shells behave normally.
if [ ! -e "${HOME}/.bashrc" ]; then
    cp -a /etc/skel/. "${HOME}/" 2>/dev/null || true
fi

chown -R orca:orca "${HOME}" "${NPM_CONFIG_PREFIX:-/data/npm-global}"

# Orca advertises the address clients dial in its pairing payload, and it takes that
# address verbatim. A bare hostname yields `ws://host:<port>`, which Railway's edge —
# TLS on 443 only — can never serve. The `wss://` form drops the port and uses TLS,
# which is the one shape that works here.
if [ -z "${ORCA_PAIRING_ADDRESS:-}" ]; then
    if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
        ORCA_PAIRING_ADDRESS="wss://${RAILWAY_PUBLIC_DOMAIN}"
    else
        echo "FATAL: no RAILWAY_PUBLIC_DOMAIN and no ORCA_PAIRING_ADDRESS." >&2
        echo "  Attach a public domain to this service, or set ORCA_PAIRING_ADDRESS" >&2
        echo "  to the wss:// URL clients should dial." >&2
        exit 1
    fi
fi

echo "orca: serving on :${PORT:-8080}, advertising ${ORCA_PAIRING_ADDRESS}"
echo "orca: the pairing URL below is the credential for this runtime — treat it like a password."

# xvfb-run supplies the virtual display Electron needs even with no window open.
exec gosu orca xvfb-run -a orca-ide serve \
    --port "${PORT:-8080}" \
    --pairing-address "${ORCA_PAIRING_ADDRESS}" \
    "$@"
