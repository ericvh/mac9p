# FSKit packaging (Xcode) — Mac9P

This repo’s FSKit implementation lives in two layers:

- **Core logic (testable, CI)**: `fskit-core/` (`Mac9PCore` Swift package)
- **FSKit extension glue (Xcode target)**: `fskit/` (FSKit `UnaryFileSystemExtension` + `FSVolume`)

## Create an Xcode app + File System Extension target

1. In Xcode, create a new project (any minimal macOS app is fine; SwiftUI is OK).
2. Add a new target: **File System Extension** (Unary flow).
3. Copy the sources from `fskit/` into the extension target:
   - `Mac9PFileSystemExtension.swift`
   - `Mac9PUnaryFileSystem.swift`
   - `Mac9PVolume.swift`
4. Add the Swift package dependency:
   - File → Add Package Dependencies…
   - Add local package: `fskit-core/`
   - Link the extension target against **`Mac9PCore`**

## Entitlements and Info.plist

In the extension target:

- Add entitlement: `com.apple.developer.fskit.fsmodule`
- Ensure your `Info.plist` includes FSKit module attributes, especially:
  - `EXAppExtensionAttributes` → `FSShortName` = `mac9p`

## Enable the extension

After building the app once:

Settings → General → Login Items & Extensions → (scroll) **File System Extensions** → enable your `mac9p` extension.

## Mount

Create a mountpoint and mount a 9P server:

```bash
mkdir -p /tmp/mac9p
mount -t mac9p "9p://host.example:564/?vers=9P2000" /tmp/mac9p
```

## Current scope / limitations

- `fskit-core` now includes an async, multiplexed 9P client and tests.
- The FSKit `Mac9PVolume` glue is still incomplete: it connects/attaches but does not yet implement
  `lookup/getattr/readdir/read` using FSKit APIs (these vary across FSKit versions and require careful mapping).

