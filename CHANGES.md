# Changes

## Unreleased

- Modernized top-level build to use `xcrun` SDK discovery and a modern default deployment target.
- Added mount-time 9P version negotiation support for:
  - `9P2000`
  - `9P2000.u`
  - `9P2000.L`
  including a new `vers=`/`version=` mount option and `dotl` flag.
- Updated `load_9p` to prefer `kmutil` on modern macOS, with fallback to `kextload`.
- Added initial **FSKit (File System Extension)** scaffolding under `fskit/` as the start of a kext-less rewrite.

