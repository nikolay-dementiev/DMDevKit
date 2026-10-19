import Foundation

/// What to start: an executable, its arguments and the variables added to the inherited environment.
public struct RunPlan: Sendable, Equatable {
    /// The program to start, as a path.
    public let executable: String
    /// Its arguments, one element each, never split or joined.
    public let arguments: [String]
    /// Variables added to the environment that `devkit` itself runs in; an added name replaces an inherited one.
    public let environment: [String: String]

    /// - Parameters:
    ///   - executable: the program to start, as a path.
    ///   - arguments: its arguments.
    ///   - environment: variables added to the inherited environment.
    public init(executable: String, arguments: [String], environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

/// How the child ended.
public enum ChildOutcome: Sendable, Equatable {
    /// The child ended by itself with this exit code.
    case exited(Int32)
    /// A signal with this number ended the child.
    case signaled(Int32)
}

/// The child's end plus the signal `devkit` forwarded to it, if any.
public struct LaunchResult: Sendable, Equatable {
    /// How the child ended.
    public let outcome: ChildOutcome
    /// The number of the last signal `devkit` sent on to the child, or nil.
    public let forwardedSignal: Int32?

    /// - Parameters:
    ///   - outcome: how the child ended.
    ///   - forwardedSignal: the last signal `devkit` forwarded, if any.
    public init(outcome: ChildOutcome, forwardedSignal: Int32?) {
        self.outcome = outcome
        self.forwardedSignal = forwardedSignal
    }
}

/// Starts a child that shares standard input, output, error and the working directory, and waits for it.
public protocol ProcessLauncher {
    /// Starts the plan, waits for the child and says how it ended.
    /// - Throws: `DevKitError.cannotStart` when the program cannot start.
    func run(_ plan: RunPlan) throws -> LaunchResult
}

/// Finds the git top level that contains a directory.
public protocol RepositoryLocator {
    /// The git top level that contains `directory`.
    /// - Throws: `DevKitError.notInRepository` when there is none.
    func topLevel(of directory: URL) throws -> URL
}

/// Tells whether a directory exists.
public protocol DirectoryInspector {
    /// True when `url` is an existing directory.
    func isDirectory(at url: URL) -> Bool
}

/// The two output streams of `devkit` itself. A child writes to the real streams, not through this.
public protocol TextOutput {
    /// Writes to the result stream.
    func writeOut(_ text: String)
    /// Writes to the diagnostic stream.
    func writeError(_ text: String)
}
