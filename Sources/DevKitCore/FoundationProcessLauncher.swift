import Foundation

/// Starts the child with `Process`. The child shares the streams given here and the working directory of `devkit`.
public struct FoundationProcessLauncher: ProcessLauncher {
    private let standardInput: FileHandle
    private let standardOutput: FileHandle
    private let standardError: FileHandle

    /// The defaults are the real streams of `devkit`: nothing is captured, nothing is merged.
    public init(
        standardInput: FileHandle = .standardInput,
        standardOutput: FileHandle = .standardOutput,
        standardError: FileHandle = .standardError
    ) {
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func run(_ plan: RunPlan) throws -> LaunchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executable)
        process.arguments = plan.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(plan.environment) { _, added in added }
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        do {
            try process.run()
        } catch {
            throw DevKitError.cannotStart(executable: plan.executable, reason: error.localizedDescription)
        }
        process.waitUntilExit()
        let outcome: ChildOutcome = process.terminationReason == .uncaughtSignal
            ? .signaled(process.terminationStatus)
            : .exited(process.terminationStatus)
        return LaunchResult(outcome: outcome, forwardedSignal: nil)
    }
}
