import Foundation

/// Answers from the file system.
public struct FileManagerDirectoryInspector: DirectoryInspector {
    public init() {}

    public func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
