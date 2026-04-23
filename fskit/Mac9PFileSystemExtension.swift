import FSKit

/// FSKit entrypoint.
///
/// In Xcode, this file lives in the File System Extension target and the target's
/// Info.plist must declare the FSKit module attributes (including FSShortName).
final class Mac9PFileSystemExtension: NSObject, UnaryFileSystemExtension {
    var fileSystem: FSUnaryFileSystem { Mac9PUnaryFileSystem() }
}

