import Foundation

/// Finds the folder that holds the scripts, next to the executable.
///
/// The build system decides the layout of `DMDevKit_devkit.bundle`: the native build system of SwiftPM copies the resource
/// folder into the bundle, and the Swift Build system (the default of Swift 6.4) wraps the bundle in the macOS layout.
public struct ResourceFolderLocator {
    /// The folders to try, relative to the folder of the executable, in order.
    private static let candidates = [
        "DMDevKit_devkit.bundle/Resources",
        "DMDevKit_devkit.bundle/Contents/Resources/Resources"
    ]

    private let directoryInspector: any DirectoryInspector

    /// - Parameter directoryInspector: tells which candidate exists.
    public init(directoryInspector: any DirectoryInspector) {
        self.directoryInspector = directoryInspector
    }

    /// The first candidate that is a directory, or the first candidate when none is, so that the message about a missing folder
    /// names the folder a plain build makes.
    /// - Parameter executable: the path of `devkit`; a symbolic link is followed to the folder of the real file.
    public func folder(besideExecutable executable: URL) -> URL {
        let directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        let folders = Self.candidates.map { directory.appendingPathComponent($0, isDirectory: true) }
        return folders.first { directoryInspector.isDirectory(at: $0) } ?? folders[0]
    }
}
