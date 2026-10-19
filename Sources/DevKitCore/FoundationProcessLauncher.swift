import Foundation
import os

/// Starts the child with `Process`. The child shares the streams given here and the working directory of `devkit`.
public struct FoundationProcessLauncher: ProcessLauncher {
    private let standardInput: FileHandle
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private let forwardedSignals: [Int32]

    /// The defaults are the real streams of `devkit` and the two signals a terminal or a CI runner sends: nothing is captured, nothing is merged.
    ///
    /// A signal in `forwardedSignals` that arrives while the child runs is sent on to the child, and `devkit` does not die of it.
    public init(
        standardInput: FileHandle = .standardInput,
        standardOutput: FileHandle = .standardOutput,
        standardError: FileHandle = .standardError,
        forwardedSignals: [Int32] = [SIGINT, SIGTERM]
    ) {
        self.forwardedSignals = forwardedSignals
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
        // Ignored before the child starts, so that a signal in the gap between start and handler does not kill devkit.
        let previous = forwardedSignals.map { signal($0, SIG_IGN) }
        do {
            try process.run()
        } catch {
            zip(forwardedSignals, previous).forEach { signal($0, $1 ?? SIG_DFL) }
            throw DevKitError.cannotStart(executable: plan.executable, reason: error.localizedDescription)
        }
        let forwarded = OSAllocatedUnfairLock<Int32?>(initialState: nil)
        let guards = installForwarding(to: process.processIdentifier, previous: previous, recordingIn: forwarded)
        process.waitUntilExit()
        removeForwarding(guards)
        let outcome: ChildOutcome = process.terminationReason == .uncaughtSignal
            ? .signaled(process.terminationStatus)
            : .exited(process.terminationStatus)
        return LaunchResult(outcome: outcome, forwardedSignal: forwarded.withLock { $0 })
    }

    private struct SignalGuard {
        let signalNumber: Int32
        let source: any DispatchSourceSignal
        let previous: (@convention(c) (Int32) -> Void)?
    }

    /// Sends each signal to the child instead of acting on it. Only the pid crosses to the handler.
    private func installForwarding(
        to pid: pid_t,
        previous: [(@convention(c) (Int32) -> Void)?],
        recordingIn forwarded: OSAllocatedUnfairLock<Int32?>
    ) -> [SignalGuard] {
        zip(forwardedSignals, previous).map { number, previous in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                forwarded.withLock { $0 = number }
                kill(pid, number)
            }
            source.resume()
            return SignalGuard(signalNumber: number, source: source, previous: previous)
        }
    }

    private func removeForwarding(_ guards: [SignalGuard]) {
        for item in guards {
            item.source.cancel()
            signal(item.signalNumber, item.previous ?? SIG_DFL)
        }
    }
}
