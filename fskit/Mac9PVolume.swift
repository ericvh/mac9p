import Foundation
import FSKit
import os.log
import Mac9PCore

/// FSKit volume implementation for a 9P-backed hierarchy.
///
/// This is intentionally minimal: it returns a root item and implements the required
/// FSVolume.Operations surface with stubs that you progressively map onto 9P RPCs.
final class Mac9PVolume: FSVolume, FSVolume.Operations, FSVolume.ReadWriteOperations {
    private static let log = Logger(subsystem: "mac9p.fskit", category: "volume")

    final class Item: FSItem {
        let itemID: FSItem.Identifier
        let parentID: FSItem.Identifier
        var fid: UInt32
        let isDirectory: Bool
        var name: String

        init(itemID: FSItem.Identifier,
             parentID: FSItem.Identifier,
             fid: UInt32,
             isDirectory: Bool,
             name: String) {
            self.itemID = itemID
            self.parentID = parentID
            self.fid = fid
            self.isDirectory = isDirectory
            self.name = name
            super.init()
        }
    }

    let config: NinePClient.Config
    private let client: NinePAsyncClient
    let mountURL: URL
    let rootItem: Item

    private struct FidEntry {
        var fid: UInt32
        var refCount: Int
        var parentID: FSItem.Identifier
        var isDirectory: Bool
        var name: String
    }
    private let fidTableLock = NSLock()
    private var fidTable: [FSItem.Identifier: FidEntry] = [:]

    private struct DirSnapshot {
        var generation: UInt32
        var entries: [NineP.Stat]
    }
    private var nextDirGeneration: UInt32 = 1
    private var dirSnapshots: [FSItem.Identifier: DirSnapshot] = [:]

    // Minimal helper: NSLock convenience
    // (kept private to avoid leaking dependencies into other files)
    private func withLock<T>(_ lock: NSLock, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Supported capabilities

    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let c = FSVolume.SupportedCapabilities()
        c.supportsPersistentObjectIDs = false
        c.supports64BitObjectIDs = true
        c.supportsHardLinks = false
        c.supportsSymbolicLinks = false
        c.supportsJournal = false
        c.supportsActiveJournal = false
        c.supportsSparseFiles = false
        c.supportsFastStatFS = false
        c.supports2TBFiles = true
        c.supportsHiddenFiles = true
        c.doesNotSupportSettingFilePermissions = true
        c.doesNotSupportRootTimes = true
        return c
    }

    // Request mount options (best-effort) — at minimum, keep the mount read-only.
    // FSKit reads this after `mount` completes; changing it later has no effect.
    var requestedMountOptions: FSVolume.MountOptions = .readOnly

    // MARK: - Volume statistics

    var volumeStatistics: FSStatFSResult {
        // 9P doesn't reliably expose volume sizes; report minimal safe defaults.
        let s = FSStatFSResult(fileSystemTypeName: "mac9p")
        s.blockSize = 4096
        // Leave totals/free as zero (unknown).
        return s
    }

    init(config: NinePClient.Config, mountURL: URL) throws {
        self.config = config
        self.client = NinePAsyncClient(config: config)
        self.mountURL = mountURL
        // Root fid is allocated during mount/attach. Use a placeholder fid until then.
        self.rootItem = Item(
            itemID: .rootDirectory,
            parentID: .parentOfRoot,
            fid: 0,
            isDirectory: true,
            name: "."
        )
        super.init()
    }

    // MARK: - Required FSVolume.Operations

    // FSVolume.PathConfOperations
    var maximumLinkCount: Int32 { -1 }
    var maximumNameLength: Int32 { 255 }
    var restrictsOwnershipChanges: Bool { true }
    var truncatesLongNames: Bool { false }
    var maximumFileSize: Int64 { -1 }
    var maximumFileSizeInBits: Int32 { -1 }
    var maximumXattrSize: Int64 { -1 }
    var maximumXattrSizeInBits: Int32 { -1 }

    public func activate(options: FSTaskOptions, replyHandler reply: @escaping @Sendable ((any Error)?) -> Void) {
        // No-op for now.
        reply(nil)
    }

    public func deactivate(options: FSDeactivateOptions, replyHandler reply: @escaping @Sendable ((any Error)?) -> Void) {
        Task { await client.disconnect(); reply(nil) }
    }

    public func mount(options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        Task {
            do {
                try await client.connectAndNegotiate()
                try await client.attach()
                let rootFid = try await client.root()
                // Patch in the real root fid (we keep the instance stable for FSKit).
                self.rootItem.name = "."
                self.rootItem.fid = rootFid
                withLock(fidTableLock) {
                    fidTable[.rootDirectory] = FidEntry(fid: rootFid, refCount: 1, parentID: .parentOfRoot, isDirectory: true, name: ".")
                }
                reply(nil)
            } catch {
                Self.log.error("mount failed: \(String(describing: error), privacy: .public)")
                reply(error)
            }
        }
    }

    public func unmount(replyHandler reply: @escaping @Sendable ((any Error)?) -> Void) {
        Task {
            await client.disconnect()
            withLock(fidTableLock) {
                fidTable.removeAll()
                dirSnapshots.removeAll()
            }
            reply(nil)
        }
    }

    public func synchronize(flags: FSSyncFlags, replyHandler reply: @escaping ((any Error)?) -> Void) {
        // 9P has no direct equivalent of fsync for the whole volume; treat as no-op.
        reply(nil)
    }

    public func reclaimItem(_ item: FSItem, replyHandler reply: @escaping @Sendable ((any Error)?) -> Void) {
        guard let it = item as? Item else { return reply(nil) }
        // Reference-counted fid reclamation: only clunk+release when last reference goes away.
        var shouldFree = false
        withLock(fidTableLock) {
            guard var entry = fidTable[it.itemID] else { return }
            entry.refCount -= 1
            if entry.refCount <= 0 {
                fidTable[it.itemID] = nil
                shouldFree = true
            } else {
                fidTable[it.itemID] = entry
            }
        }
        if shouldFree {
            Task {
                do {
                    if it.fid != 0 {
                        try await client.clunk(fid: it.fid)
                        await client.releaseFid(it.fid)
                    }
                    reply(nil)
                } catch {
                    reply(error)
                }
            }
            return
        }
        return reply(nil)
    }

    // MARK: - Mutating operations (readonly MVP => ENOTSUP)

    public func createItem(named name: FSFileName,
                           type: FSItem.ItemType,
                           inDirectory directory: FSItem,
                           attributes: FSItem.SetAttributesRequest,
                           replyHandler reply: @escaping @Sendable (FSItem?, FSFileName?, (any Error)?) -> Void) {
        _ = name; _ = type; _ = directory; _ = attributes
        reply(nil, nil, POSIXError(.ENOTSUP))
    }

    public func removeItem(_ item: FSItem,
                           named name: FSFileName,
                           fromDirectory directory: FSItem,
                           replyHandler reply: @escaping @Sendable ((any Error)?) -> Void) {
        _ = item; _ = name; _ = directory
        reply(POSIXError(.ENOTSUP))
    }

    public func renameItem(_ item: FSItem,
                           inDirectory oldDirectory: FSItem,
                           named oldName: FSFileName,
                           to newName: FSFileName,
                           inDirectory newDirectory: FSItem,
                           overItem: FSItem?,
                           replyHandler reply: @escaping @Sendable (FSFileName?, (any Error)?) -> Void) {
        _ = item; _ = oldDirectory; _ = oldName; _ = newName; _ = newDirectory; _ = overItem
        reply(nil, POSIXError(.ENOTSUP))
    }

    public func setAttributes(_ newAttributes: FSItem.SetAttributesRequest,
                              on item: FSItem,
                              replyHandler reply: @escaping @Sendable (FSItem.SetAttributesRequest?, (any Error)?) -> Void) {
        _ = newAttributes; _ = item
        reply(nil, POSIXError(.ENOTSUP))
    }

    public func createLink(to item: FSItem,
                           named name: FSFileName,
                           inDirectory directory: FSItem,
                           replyHandler reply: @escaping @Sendable (FSItem?, FSFileName?, (any Error)?) -> Void) {
        _ = item; _ = name; _ = directory
        reply(nil, nil, POSIXError(.ENOTSUP))
    }

    public func createSymbolicLink(named name: FSFileName,
                                   inDirectory directory: FSItem,
                                   attributes: FSItem.SetAttributesRequest,
                                   linkContents: FSFileName,
                                   replyHandler reply: @escaping @Sendable (FSItem?, FSFileName?, (any Error)?) -> Void) {
        _ = name; _ = directory; _ = attributes; _ = linkContents
        reply(nil, nil, POSIXError(.ENOTSUP))
    }

    public func readSymbolicLink(_ item: FSItem,
                                 replyHandler reply: @escaping @Sendable (FSFileName?, (any Error)?) -> Void) {
        _ = item
        reply(nil, POSIXError(.ENOTSUP))
    }

    // MARK: - Lookup / attributes

    public func lookupItem(named name: FSFileName,
                           inDirectory directory: FSItem,
                           replyHandler reply: @escaping @Sendable (FSItem?, FSFileName?, (any Error)?) -> Void) {
        guard let dir = directory as? Item else { return reply(nil, nil, POSIXError(.EINVAL)) }
        let n = name.string.isEmpty ? String(data: name.data, encoding: .utf8) : name.string
        guard let childName = n, !childName.isEmpty else { return reply(nil, nil, POSIXError(.EINVAL)) }

        Task {
            do {
                // First: if we already have a live fid for this inode, reuse it and bump refcount.
                // To get inode (qid.path) we need one walk; once resolved we can reuse thereafter.
                let tempFid = await client.allocateFid()
                let qids = try await client.walk(from: dir.fid, newfid: tempFid, names: [childName])
                guard let q = qids.last else {
                    await client.releaseFid(tempFid)
                    return reply(nil, nil, POSIXError(.ENOENT))
                }

                let childID = FSItem.Identifier(rawValue: q.path)
                let isDir = (q.type & 0x80) != 0

                let existing: FidEntry? = withLock(fidTableLock) {
                    if var e = fidTable[childID] {
                        e.refCount += 1
                        fidTable[childID] = e
                        return e
                    }
                    return nil
                }

                if let existing {
                    // Clunk the temp fid we used only for resolution, then release it.
                    try await client.clunk(fid: tempFid)
                    await client.releaseFid(tempFid)

                    let item = Item(itemID: childID, parentID: dir.itemID, fid: existing.fid, isDirectory: existing.isDirectory, name: existing.name)
                    return reply(item, FSFileName(string: existing.name), nil)
                } else {
                    withLock(fidTableLock) {
                        fidTable[childID] = FidEntry(fid: tempFid, refCount: 1, parentID: dir.itemID, isDirectory: isDir, name: childName)
                    }

                    let item = Item(itemID: childID, parentID: dir.itemID, fid: tempFid, isDirectory: isDir, name: childName)
                    return reply(item, FSFileName(string: childName), nil)
                }
            } catch {
                reply(nil, nil, error)
            }
        }
    }

    public func getAttributes(_ desiredAttributes: FSItem.GetAttributesRequest,
                              of item: FSItem,
                              replyHandler reply: @escaping @Sendable (FSItem.Attributes?, (any Error)?) -> Void) {
        guard let it = item as? Item else { return reply(nil, POSIXError(.EINVAL)) }
        Task {
            do {
                let st = try await client.stat(fid: it.fid)
                let attrs = makeAttributes(item: it, stat: st)
                // Best-effort: only populate commonly wanted attrs.
                _ = desiredAttributes
                reply(attrs, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    // MARK: - Directory enumeration

    public func enumerateDirectory(_ directory: FSItem,
                                   startingAt cookie: FSDirectoryCookie,
                                   verifier: FSDirectoryVerifier,
                                   attributes: FSItem.GetAttributesRequest?,
                                   packer: FSDirectoryEntryPacker,
                                   replyHandler reply: @escaping @Sendable (FSDirectoryVerifier, (any Error)?) -> Void) {
        guard let dir = directory as? Item else { return reply(verifier, POSIXError(.EINVAL)) }

        Task {
            do {
                // Cookie encoding: upper 32 bits = generation, lower 32 bits = start index.
                // A new generation is created whenever enumeration restarts from .initial.
                func decodeCookie(_ c: FSDirectoryCookie) -> (gen: UInt32, idx: Int) {
                    if c == .initial { return (0, 0) }
                    let raw = c.rawValue
                    let gen = UInt32(raw >> 32)
                    let idx = Int(UInt32(truncatingIfNeeded: raw))
                    return (gen, idx)
                }
                func encodeCookie(gen: UInt32, idx: Int) -> FSDirectoryCookie {
                    let raw = (UInt64(gen) << 32) | UInt64(UInt32(idx))
                    return FSDirectoryCookie(raw)
                }

                // FSKit tip: if attributes == nil, include "." and ".."
                var index = 0
                if attributes == nil && cookie == .initial {
                    let dot = FSFileName(string: ".")
                    _ = packer.packEntry(
                        name: dot,
                        itemType: .directory,
                        itemID: dir.itemID,
                        nextCookie: FSDirectoryCookie(0),
                        attributes: nil
                    )

                    let dotdot = FSFileName(string: "..")
                    _ = packer.packEntry(
                        name: dotdot,
                        itemType: .directory,
                        itemID: dir.parentID,
                        nextCookie: FSDirectoryCookie(0),
                        attributes: nil
                    )
                }

                let decoded = decodeCookie(cookie)

                // Build or reuse a snapshot:
                // - On initial: always fetch fresh from server to avoid stale synthetic views.
                // - On continuation: use cached snapshot by generation to make cookies stable.
                let snapshot: DirSnapshot = {
                    if cookie == .initial {
                        return DirSnapshot(generation: 0, entries: [])
                    }
                    let snap = withLock(fidTableLock) { dirSnapshots[dir.itemID] }
                    return snap ?? DirSnapshot(generation: 0, entries: [])
                }()

                let active: DirSnapshot
                if cookie == .initial || snapshot.generation == 0 {
                    let fresh = try await client.readDir(fid: dir.fid)
                    let gen: UInt32 = withLock(fidTableLock) {
                        let g = nextDirGeneration
                        nextDirGeneration &+= 1
                        dirSnapshots[dir.itemID] = DirSnapshot(generation: g, entries: fresh)
                        return g
                    }
                    active = DirSnapshot(generation: gen, entries: fresh)
                } else {
                    // Continuation must match generation
                    guard decoded.gen == snapshot.generation else {
                        return reply(verifier, FSError.invalidDirectoryCookie)
                    }
                    active = snapshot
                }

                let startIndex = decoded.idx
                guard startIndex <= active.entries.count else {
                    return reply(FSDirectoryVerifier(UInt64(active.generation)), FSError.invalidDirectoryCookie)
                }

                for i in startIndex..<active.entries.count {
                    let st = active.entries[i]
                    let itemType: FSItem.ItemType = ((st.qid.type & 0x80) != 0) ? .directory : .file
                    let itemID = FSItem.Identifier(rawValue: st.qid.path)
                    let next = encodeCookie(gen: active.generation, idx: i + 1)

                    let attrs = attributes != nil ? makeAttributesFromStatForEnumeration(itemID: itemID, parentID: dir.itemID, stat: st) : nil
                    let ok = packer.packEntry(
                        name: FSFileName(string: st.name),
                        itemType: itemType,
                        itemID: itemID,
                        nextCookie: next,
                        attributes: attrs
                    )
                    if !ok { break }
                    index = i
                }

                // Verifier is the snapshot generation. This changes every time enumeration
                // restarts from .initial (fresh fetch).
                _ = index
                reply(FSDirectoryVerifier(UInt64(active.generation)), nil)
            } catch {
                reply(verifier, error)
            }
        }
    }

    // MARK: - ReadWriteOperations (read-only)

    public func read(from item: FSItem,
                     at offset: off_t,
                     length: Int,
                     into buffer: FSMutableFileDataBuffer,
                     replyHandler reply: @escaping @Sendable (Int, (any Error)?) -> Void) {
        guard let it = item as? Item, !it.isDirectory else { return reply(0, POSIXError(.EINVAL)) }
        Task {
            do {
                let data = try await client.read(fid: it.fid, offset: UInt64(offset), count: UInt32(length))
                let n = data.count
                buffer.withUnsafeMutableBytes { raw in
                    _ = data.copyBytes(to: raw.bindMemory(to: UInt8.self))
                }
                reply(n, nil)
            } catch {
                reply(0, error)
            }
        }
    }

    // MARK: - Helpers

    private func makeAttributes(item: Item, stat: NineP.Stat) -> FSItem.Attributes {
        let a = FSItem.Attributes()
        a.fileID = item.itemID
        a.parentID = item.parentID
        a.type = item.isDirectory ? .directory : .file
        a.mode = stat.mode
        a.linkCount = 1
        a.size = stat.length
        a.allocSize = stat.length
        a.accessTime = timespec(tv_sec: Int(stat.atime), tv_nsec: 0)
        a.modifyTime = timespec(tv_sec: Int(stat.mtime), tv_nsec: 0)
        // Without dotu we don't have uid/gid numbers reliably; use 0 for MVP.
        a.uid = 0
        a.gid = 0
        return a
    }

    private func makeAttributesFromStatForEnumeration(itemID: FSItem.Identifier,
                                                      parentID: FSItem.Identifier,
                                                      stat: NineP.Stat) -> FSItem.Attributes {
        let a = FSItem.Attributes()
        a.fileID = itemID
        a.parentID = parentID
        a.type = ((stat.qid.type & 0x80) != 0) ? .directory : .file
        a.mode = stat.mode
        a.linkCount = 1
        a.size = stat.length
        a.allocSize = stat.length
        a.accessTime = timespec(tv_sec: Int(stat.atime), tv_nsec: 0)
        a.modifyTime = timespec(tv_sec: Int(stat.mtime), tv_nsec: 0)
        a.uid = 0
        a.gid = 0
        return a
    }

    // no longer needed: fid lifecycle is managed via allocate/release + fidTable
}

