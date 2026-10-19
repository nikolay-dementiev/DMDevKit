import Foundation

/// What to start: an executable, its arguments and the variables added to the inherited environment.
public struct RunPlan: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(executable: String, arguments: [String], environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

/// How the child ended.
public enum ChildOutcome: Sendable, Equatable {
    case exited(Int32)
    case signaled(Int32)
}

/// The child's end plus the signal `devkit` forwarded to it, if any.
public struct LaunchResult: Sendable, Equatable {
    public let outcome: ChildOutcome
    public let forwardedSignal: Int32?

    public init(outcome: ChildOutcome, forwardedSignal: Int32?) {
        self.outcome = outcome
        self.forwardedSignal = forwardedSignal
    }
}

/// Starts a child that shares standard input, output, error and the working directory, and waits for it.
public protocol ProcessLauncher {
    func run(_ plan: RunPlan) throws -> LaunchResult
}

/// Finds the git top level that contains a directory.
public protocol RepositoryLocator {
    func topLevel(of directory: URL) throws -> URL
}

/// Tells whether a directory exists.
public protocol DirectoryInspector {
    func isDirectory(at url: URL) -> Bool
}

/// The two output streams of `devkit` itself. A child writes to the real streams, not through this.
public protocol TextOutput {
    func writeOut(_ text: String)
    func writeError(_ text: String)
}
