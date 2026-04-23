import Foundation
import FSKit
import os.log

/// FSKit volume implementation for a 9P-backed hierarchy.
///
/// This is intentionally minimal: it returns a root item and implements the required
/// FSVolume.Operations surface with stubs that you progressively map onto 9P RPCs.
final class Mac9PVolume: FSVolume, FSVolume.Operations {
    private static let log = Logger(subsystem: "mac9p.fskit", category: "volume")

    final class Item: FSItem {
        let identifier: UInt64
        init(identifier: UInt64) { self.identifier = identifier; super.init() }
    }

    let client: NinePClient
    let mountURL: URL
    let rootItem: Item

    init(client: NinePClient, mountURL: URL) throws {
        self.client = client
        self.mountURL = mountURL
        self.rootItem = Item(identifier: 1)
        super.init()
    }

    // MARK: - Required FSVolume.Operations

    public func mount(options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        // TODO: attach and establish a root fid; populate root item attrs.
        reply(nil)
    }

    public func unmount(options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        // TODO: clunk open fids and disconnect.
        reply(nil)
    }

    public func synchronize(flags: FSSyncFlags, replyHandler reply: @escaping ((any Error)?) -> Void) {
        // 9P has no direct equivalent of fsync for the whole volume; treat as no-op.
        reply(nil)
    }

    // MARK: - Lookup / attributes (stubs)

    public func lookupItem(named name: FSFileName,
                           in directory: FSItem,
                           replyHandler reply: @escaping (FSItem?, (any Error)?) -> Void) {
        // TODO: Twalk + Tstat (or getattr equivalents)
        _ = name
        _ = directory
        reply(nil, POSIXError(.ENOTSUP))
    }

    public func getAttributes(of item: FSItem,
                              requested: FSItemAttributeRequest,
                              replyHandler reply: @escaping (FSItemAttributes?, (any Error)?) -> Void) {
        // TODO: Tstat (or dot extension equivalents) and map to FSItemAttributes
        _ = item
        _ = requested
        reply(nil, POSIXError(.ENOTSUP))
    }

    // MARK: - Directory enumeration (stub)

    public func enumerateDirectory(_ directory: FSItem,
                                   startingAt cookie: FSDirectoryCookie?,
                                   verifier: FSDirectoryVerifier?,
                                   requestedAttributes: FSItemAttributeRequest,
                                   replyHandler reply: @escaping (FSDirectoryEnumerationResult?, (any Error)?) -> Void) {
        // TODO: Read directory via Tread and decode stat entries; provide cookies.
        _ = directory
        _ = cookie
        _ = verifier
        _ = requestedAttributes
        reply(nil, POSIXError(.ENOTSUP))
    }
}

