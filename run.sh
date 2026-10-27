#!/usr/bin/env bash
set -euo pipefail

RUNS="${1:-5}"

IMG=ghcr.io/userver-framework/ubuntu-22.04-userver
DIGEST=sha256:fca9c8ac7e97b4e2b042d822facbb152aec10a9d4e09c0862e44c50640f3f303

LIMITS=(--cpus=4 --cpuset-cpus=0-3 --memory=8g --memory-swap=8g)
HERE="$(cd "$(dirname "$0")" && pwd)"

if command -v cygpath; then
  HERE="$(cygpath -m "$HERE")"
  export MSYS_NO_PATHCONV=1
fi

docker run --rm "${LIMITS[@]}" -v "$HERE:/work" -w /work "$IMG@$DIGEST" bash /work/scripts/inside.sh "$RUNS"
