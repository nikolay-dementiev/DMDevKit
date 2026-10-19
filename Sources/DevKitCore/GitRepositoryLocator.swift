import Foundation

/// Asks git for the top level of the repository that contains a directory.
public struct GitRepositoryLocator: RepositoryLocator {
    public init() {}

    public func topLevel(of directory: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw DevKitError.cannotStart(executable: "git", reason: error.localizedDescription)
        }
        // Read before waiting: a full pipe would block git.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !path.isEmpty else {
            throw DevKitError.notInRepository(directory: directory.path)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
