import Foundation

/// Answers from the file system.
public struct FileManagerDirectoryInspector: DirectoryInspector {
    /// Creates an inspector that asks the file system.
    public init() {}

    /// True when `url` is an existing directory; a file or a missing path is false.
    public func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
