import Foundation
import os

/// Asks git for the top level of the repository that contains a directory.
public struct GitRepositoryLocator: RepositoryLocator {
    private let command: [String]
    private let scratchDirectory: URL

    /// - Parameters:
    ///   - command: the program and its leading arguments that run git. The default finds `git` on the `PATH`.
    ///   - scratchDirectory: where the file that holds the standard error of git lives while git runs.
    public init(command: [String] = ["/usr/bin/env", "git"], scratchDirectory: URL = FileManager.default.temporaryDirectory) {
        self.command = command
        self.scratchDirectory = scratchDirectory
    }

    /// The git top level of `directory`, as the real path git prints.
    ///
    /// The `GIT_*` variables that point git at another repository are removed from the child's environment: the answer is about
    /// `directory`, whatever a hook or a CI step exported.
    /// - Throws: `DevKitError.notInRepository` when git says there is no repository or prints a path that is not UTF-8, with
    ///   the first line git wrote on its standard error; `DevKitError.cannotStart` when git cannot run.
    public func topLevel(of directory: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst()) + ["-C", directory.path, "rev-parse", "--show-toplevel"]
        process.environment = ProcessInfo.processInfo.environment.filter { !Self.redirectingVariables.contains($0.key) }
        let pipe = Pipe()
        process.standardOutput = pipe
        // Standard error goes to a file, not a second pipe: two pipes read one after the other can block each other when git
        // fills the one that is not being read, and a file cannot fill up on git.
        let errorFile = scratchDirectory.appendingPathComponent("devkit-git-\(UUID().uuidString).err")
        defer { Self.remove(errorFile) }
        process.standardError = Self.openForWriting(errorFile) ?? FileHandle.nullDevice
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
            throw DevKitError.notInRepository(directory: directory.path, gitMessage: Self.firstLine(ofFile: errorFile))
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static let logger = Logger(subsystem: "DMDevKit", category: "git")

    // Without the file the lookup still runs: the message just has no line of git's.
    private static func openForWriting(_ file: URL) -> FileHandle? {
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
            logger.error("cannot create \(file.path, privacy: .public) for the standard error of git")
            return nil
        }
        do {
            return try FileHandle(forWritingTo: file)
        } catch {
            logger.error("cannot open \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // The first line that is not blank, cut to a length a message can carry; nil when git wrote nothing or the file is gone.
    private static func firstLine(ofFile file: URL) -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            logger.error("cannot read \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let text = String(decoding: data.prefix(4096), as: UTF8.self)
        // Control characters (colour escapes, bells) would act on the terminal that prints the message.
        let line = text.split(whereSeparator: \.isNewline)
            .map { String($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init)) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.map { String($0.prefix(300)) }
    }

    private static func remove(_ file: URL) {
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            // A file that was never made is no error; one that cannot be removed is only a leftover in the temporary folder.
            if FileManager.default.fileExists(atPath: file.path) {
                logger.error("cannot remove \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static let redirectingVariables: Set<String> = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR", "GIT_PREFIX"
    ]
}
