# Mac9P FSKit Xcode project (generated)

This folder contains an **XcodeGen** spec to generate a runnable macOS app + **FSKit File System Extension** target wired to:

- FSKit glue code in `../fskit/`
- Core 9P client in `../fskit-core/` (SwiftPM package `Mac9PCore`)

## Prereqs

- Xcode (macOS that supports FSKit)
- XcodeGen (recommended): `brew install xcodegen`

## Generate the Xcode project

From the repo root:

```bash
cd fskit-xcode
./generate.sh
open Mac9PFSKit.xcodeproj
```

## Build + enable the extension

1. Build + Run the **Mac9PFSKitApp** target once (it’s a minimal app; the extension does the work).
2. Enable the extension:
   - Settings → General → Login Items & Extensions
   - File System Extensions → enable **Mac9PFSKit**

## Mount a server

```bash
mkdir -p /tmp/mac9p
mount -t mac9p "9p://YOUR_SERVER:564/?vers=9P2000" /tmp/mac9p
ls /tmp/mac9p
```

## Notes

- This is a **readonly MVP**. Mutating operations return `ENOTSUP`.
- Directory enumeration is snapshot-based for stable cookies but fetches a fresh listing on each new enumeration (`cookie.initial`).

