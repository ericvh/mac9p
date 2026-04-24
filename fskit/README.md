# FSKit-based Mac9P (Path A)

This directory is a **starter skeleton** for rebuilding Mac9P as an **FSKit File System Extension** (user-space filesystem) instead of a kernel extension.

FSKit is the Apple-supported mechanism for third‑party filesystems on current macOS. Unlike the original Mac9P design, this approach:

- Runs in **user space** (no kext).
- Uses the system `mount(8)` integration through FSKit module metadata.
- Requires a **full rewrite** of the VFS layer as FSKit `FSVolume` operations.

## Status

- **Implemented here**: project/target skeleton code, URL parsing, and a 9P client “shim” interface you can fill in.
- **Not implemented yet**: full FS semantics, caching, credential/auth flows, and the complete 9P mapping.

## What you build in Xcode

Create an app with a **File System Extension** target (Unary FS flow) and drop these sources into it:

- `Mac9PFileSystemExtension.swift` (extension entrypoint)
- `Mac9PUnaryFileSystem.swift` (FSUnaryFileSystem + load/unload resource)
- `Mac9PVolume.swift` (FSVolume implementation; currently minimal/read-only scaffolding)
- `NinePClient.swift` (9P socket client interface + version negotiation stub)

Also set:

- `Info.plist`: set `FSShortName` to `mac9p` so you can mount using `-t mac9p`.
- Entitlements: include `com.apple.developer.fskit.fsmodule`.
- Network entitlements/sandbox as required for outbound TCP.

## Mount usage

After enabling the extension in **Settings → General → Login Items & Extensions → File System Extensions**, mount a 9P server URL:

```bash
mkdir -p /tmp/mac9p
mount -t mac9p "9p://9p.io:564/?vers=9P2000" /tmp/mac9p
```

Supported `vers` strings:

- `9P2000`
- `9P2000.u`
- `9P2000.L`

If `vers` is omitted, the implementation should prefer `9P2000.L`, then `9P2000.u`, then `9P2000`.

## Architectural mapping (high level)

- **FSResource**: use `FSGenericURLResource` for `9p://...` resources.
- **FSUnaryFileSystemOperations.loadResource**: parse URL, create a `NinePClient`, negotiate version, attach, and return a `Mac9PVolume`.
- **FSVolume.Operations**: translate operations to 9P RPCs:
  - lookup / getattr → `Twalk` + `Tstat` (or dot extensions if negotiated)
  - readdir → `Tread` on a directory fid and decode `stat` entries
  - read/write → `Tread` / `Twrite`
  - create/remove/rename → `Tcreate` / `Tremove` / (rename mapping depends on extension support)

## Next steps (recommended incremental plan)

1. **Readonly MVP**: lookup, getattr, readdir, read, open/close.
2. **Write support**: create, write, truncate, remove.
3. **dotu/dotl semantics**: map uid/gid/mode bits and symlink support as the negotiated version allows.
4. **Caching & perf**: attribute caching, directory entry caching, readahead, and operation coalescing.

