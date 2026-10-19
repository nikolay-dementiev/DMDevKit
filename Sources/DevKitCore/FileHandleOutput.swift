import Foundation

/// Writes `devkit`'s own text to two file handles, standard output and standard error by default.
public struct FileHandleOutput: TextOutput {
    private let standardOutput: FileHandle
    private let standardError: FileHandle

    public init(standardOutput: FileHandle = .standardOutput, standardError: FileHandle = .standardError) {
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func writeOut(_ text: String) {
        standardOutput.write(Data(text.utf8))
    }

    public func writeError(_ text: String) {
        standardError.write(Data(text.utf8))
    }
}
