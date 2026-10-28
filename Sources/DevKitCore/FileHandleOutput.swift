import Foundation
import os

/// Writes `devkit`'s own text to two file handles, standard output and standard error by default.
public struct FileHandleOutput: TextOutput {
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private static let logger = Logger(subsystem: "DMDevKit", category: "output")

    /// - Parameters:
    ///   - standardOutput: where `writeOut` writes.
    ///   - standardError: where `writeError` writes.
    public init(standardOutput: FileHandle = .standardOutput, standardError: FileHandle = .standardError) {
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// Writes to standard output. A closed handle or a broken pipe loses the text: it is logged, and `devkit` goes on to its exit
    /// status.
    public func writeOut(_ text: String) {
        write(text, to: standardOutput, name: "standard output")
    }

    /// Writes to standard error. A closed handle or a broken pipe loses the text: it is logged, and `devkit` goes on to its exit
    /// status.
    public func writeError(_ text: String) {
        write(text, to: standardError, name: "standard error")
    }

    // `write(_: Data)` raises an Objective-C exception that Swift cannot catch; the throwing form can fail without taking the
    // host down.
    private func write(_ text: String, to handle: FileHandle, name: String) {
        do {
            try handle.write(contentsOf: Data(text.utf8))
        } catch {
            Self.logger.error("cannot write to \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
