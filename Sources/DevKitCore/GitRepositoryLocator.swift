import Foundation

/// Asks git for the top level of the repository that contains a directory.
public struct GitRepositoryLocator: RepositoryLocator {
    private let command: [String]

    /// - Parameter command: the program and its leading arguments that run git. The default finds `git` on the `PATH`.
    public init(command: [String] = ["/usr/bin/env", "git"]) {
        self.command = command
    }

    /// The git top level of `directory`, as the real path git prints.
    ///
    /// The `GIT_*` variables that point git at another repository are removed from the child's environment: the answer is about
    /// `directory`, whatever a hook or a CI step exported.
    /// - Throws: `DevKitError.notInRepository` when git says there is no repository or prints a path that is not UTF-8,
    ///   `DevKitError.cannotStart` when git cannot run.
    public func topLevel(of directory: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst()) + ["-C", directory.path, "rev-parse", "--show-toplevel"]
        process.environment = ProcessInfo.processInfo.environment.filter { !Self.redirectingVariables.contains($0.key) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw DevKitError.cannotStart(executable: command[0], reason: error.localizedDescription)
        }
        // Read before waiting: a full pipe would block git.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // 126 and 127 are the shell's "cannot execute" and "not found": the tool did not run, so nothing is known about the
        // repository.
        if process.terminationStatus == 126 || process.terminationStatus == 127 {
            throw DevKitError.cannotStart(executable: command.last ?? command[0],
                reason: "the program was not found or cannot run")
        }
        // Bytes that are no UTF-8 would decode to replacement characters and name a folder that does not exist.
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0, !path.isEmpty else {
            throw DevKitError.notInRepository(directory: directory.path)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static let redirectingVariables: Set<String> = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR", "GIT_PREFIX"
    ]
}
