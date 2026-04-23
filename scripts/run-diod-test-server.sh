#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run-diod-test-server.sh --root /path/to/export [--listen 127.0.0.1:5640] [--pidfile /tmp/diod.pid]

Build/run notes:
  - Requires a working C toolchain (Xcode CLT).
  - This script builds diod from source in a temp directory if diod isn't found on PATH.

This is intended for automated end-to-end tests of the user-space 9P client (fskit-core).
EOF
}

ROOT=""
LISTEN="127.0.0.1:5640"
PIDFILE="/tmp/mac9p-diod.pid"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2;;
    --listen) LISTEN="${2:-}"; shift 2;;
    --pidfile) PIDFILE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$ROOT" ]]; then
  echo "--root is required" >&2
  usage
  exit 2
fi

if [[ ! -d "$ROOT" ]]; then
  echo "root does not exist: $ROOT" >&2
  exit 2
fi

if ! command -v diod >/dev/null 2>&1; then
  echo "diod not found on PATH; building from source..."
  TMP="$(mktemp -d "/tmp/mac9p-diod.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  git clone --depth 1 https://github.com/chaos/diod.git "$TMP/diod"
  pushd "$TMP/diod" >/dev/null
  ./autogen.sh
  ./configure --disable-diodmount --disable-config --disable-auth --disable-multiuser
  make -j"$(sysctl -n hw.ncpu)"
  DIOD_BIN="$TMP/diod/diod/diod"
  popd >/dev/null
else
  DIOD_BIN="$(command -v diod)"
fi

echo "Starting diod: $DIOD_BIN"
echo "  listen: $LISTEN"
echo "  export: $ROOT"

rm -f "$PIDFILE"
("$DIOD_BIN" --listen="$LISTEN" --no-auth --export="$ROOT" >/tmp/mac9p-diod.log 2>&1) &
PID=$!
echo "$PID" > "$PIDFILE"

echo "diod pid=$PID (log: /tmp/mac9p-diod.log)"
echo "To stop: kill $PID"

