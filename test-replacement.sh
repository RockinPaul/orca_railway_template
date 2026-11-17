#!/bin/sh
# Real-image regression: cross-container exclusion, SIGTERM and volume replacement.
# Build first: docker build --platform linux/amd64 -t orca-railway:check .
# Run: sh test-replacement.sh orca-railway:check
# Keeps only its named test resources and private logs for inspection.
set -eu
umask 077
image="${1:-orca-railway:check}"
logs="$(mktemp -d)"
for name in orca-wrapper-test-first orca-wrapper-test-second orca-wrapper-test-replacement; do
    if docker container inspect "$name" >/dev/null 2>&1; then
        echo "Refusing to reuse existing test container $name" >&2
        exit 1
    fi
done
if docker volume inspect orca-wrapper-test-data >/dev/null 2>&1; then
    echo 'Refusing to reuse existing test volume orca-wrapper-test-data' >&2
    exit 1
fi
docker volume create orca-wrapper-test-data >/dev/null
start() {
    docker run -d --platform linux/amd64 --name "$1" \
        -e RAILWAY_PUBLIC_DOMAIN=orca-rehearsal.example \
        -v orca-wrapper-test-data:/data "$image" >/dev/null
}
ready() {
    i=0
    until docker exec "$1" curl -fsS http://127.0.0.1:8080/web-index.html >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge 90 ]; then
            docker logs "$1" > "$logs/$1.log" 2>&1
            echo "Readiness failed; private logs: $logs" >&2
            exit 1
        fi
        sleep 1
    done
}
start orca-wrapper-test-first
ready orca-wrapper-test-first
start orca-wrapper-test-second
i=0
while [ "$(docker inspect -f '{{.State.Running}}' orca-wrapper-test-second)" = true ]; do
    i=$((i + 1))
    if [ "$i" -ge 15 ]; then echo 'Second owner was not refused' >&2; exit 1; fi
    sleep 1
done
test "$(docker inspect -f '{{.State.ExitCode}}' orca-wrapper-test-second)" = 75
test "$(docker inspect -f '{{.State.Running}}' orca-wrapper-test-first)" = true
docker stop -t 30 orca-wrapper-test-first >/dev/null
test "$(docker inspect -f '{{.State.ExitCode}}' orca-wrapper-test-first)" = 0
docker run --rm --platform linux/amd64 --entrypoint sh \
    -v orca-wrapper-test-data:/data:ro "$image" \
    -ec 'test ! -e /data/home/.config/orca/orcad.lock'
start orca-wrapper-test-replacement
ready orca-wrapper-test-replacement
docker logs orca-wrapper-test-first > "$logs/first.log" 2>&1
docker logs orca-wrapper-test-replacement > "$logs/replacement.log" 2>&1
echo "PASS: second owner refused75; stop exited0 and released lock; replacement serves. Private logs: $logs"
echo 'Retained test resources: orca-wrapper-test-{first,second,replacement}, orca-wrapper-test-data'
