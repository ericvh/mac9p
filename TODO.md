# TODO

## FSKit rewrite (Path A)

- Implement a real 9P client in user space (socket + codec): **DONE (in `fskit-core/`)**
  - Tversion/Rversion negotiation with fallback among `9P2000.L`, `9P2000.u`, `9P2000`: **DONE**
  - attach/noauth flow: **DONE**
  - async tag-multiplexed client for concurrency: **DONE**
  - robust error mapping to `POSIXError`: **PARTIAL**
- Implement readonly MVP in `Mac9PVolume`:
  - `mount`/`unmount` lifecycle with core client: **DONE (connect+attach+disconnect)**
  - `lookupItem`, `getAttributes`: **DONE (initial)**
  - `enumerateDirectory`: **DONE (snapshot-based cookies)**
  - `read` (implement `FSVolume.ReadWriteOperations.read(...)`): **DONE (readonly)**
  - fid lifecycle (refcount + clunk + reuse without collisions): **DONE (FSKit layer + fskit-core pool + tests)**
  - `volumeStatistics`, `supportedVolumeCapabilities`, `requestedMountOptions`: **DONE (minimal)**
- Add write support (phase 2):
  - create/remove, write, truncate, rename
- Semantics by negotiated version:
  - `9P2000`: baseline stat fields only
  - `9P2000.u`: uid/gid/mode, symlinks, devices, etc.
  - `9P2000.L`: decide whether to implement Linux extensions (e.g. `Tlopen`, `Tgetattr`) or negotiate `9P2000.L` only when compatible
- Caching/performance:
  - attribute caching and timeout policy
  - directory enumeration caching / cookie handling
  - readahead for sequential reads
- Packaging:
  - Xcode project with app + filesystem extension target: **TODO**
  - entitlements, sandbox/network permissions: **TODO**
  - mount syntax documentation and example launchd helpers if needed: **PARTIAL (`fskit/SETUP_XCODE.md`)**

## Legacy kext path (if still needed)

- Verify kext builds against a matching KDK and document the exact KDK/Xcode/macOS version pairing.
- Remove deprecated CoreFoundation URL escaping calls in `plugin/plugin.c` (optional cleanup).