#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/e2e-readonly.sh --url "9p://HOST:564/?vers=9P2000" [--mountpoint /tmp/mac9p] [--file PATH]

What it does:
  - Generates the FSKit Xcode project (requires xcodegen)
  - Builds the macOS app + FSKit extension
  - Prompts you to enable the extension (one-time manual step)
  - Mounts the URL using: mount -t mac9p URL MOUNTPOINT
  - Runs basic readonly checks: ls, stat, optional cat
  - Unmounts

Notes:
  - Enabling the extension can’t be automated; the script pauses until you confirm.
  - This is a readonly MVP; writes are expected to fail with ENOTSUP.
EOF
}

URL=""
MOUNTPOINT="/tmp/mac9p"
READ_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2;;
    --mountpoint) MOUNTPOINT="${2:-}"; shift 2;;
    --file) READ_FILE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "--url is required" >&2
  usage
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DIR="$ROOT_DIR/fskit-xcode"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found (install Xcode)." >&2
  exit 1
fi

echo "### Generating Xcode project"
pushd "$XCODE_DIR" >/dev/null
./generate.sh

echo "### Building FSKit app + extension"
set +e
xcodebuild -project Mac9PFSKit.xcodeproj -scheme Mac9PFSKitApp -configuration Debug build
XC=$?
set -e
if [[ $XC -ne 0 ]]; then
  echo "xcodebuild failed. Open the project to inspect signing/entitlements:" >&2
  echo "  open \"$XCODE_DIR/Mac9PFSKit.xcodeproj\"" >&2
  exit $XC
fi
popd >/dev/null

cat <<'EOF'
### One-time manual step (required)
Enable the file system extension:
  Settings → General → Login Items & Extensions → File System Extensions → enable "Mac9PFSKit"

Then press Enter to continue.
EOF
read -r

echo "### Mounting"
mkdir -p "$MOUNTPOINT"

cleanup() {
  echo "### Unmounting"
  umount "$MOUNTPOINT" 2>/dev/null || true
}
trap cleanup EXIT

mount -t mac9p "$URL" "$MOUNTPOINT"

echo "### Basic checks"
ls -la "$MOUNTPOINT"
stat "$MOUNTPOINT" >/dev/null || true

if [[ -n "$READ_FILE" ]]; then
  echo "### Reading: $READ_FILE"
  cat "$MOUNTPOINT/$READ_FILE" | head -n 50
fi

echo "### OK"

