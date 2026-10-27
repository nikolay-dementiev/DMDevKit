import Foundation
import os

/// Starts the child with `Process`. The child shares the streams given here and the working directory of `devkit`.
///
/// Signals: each one in `forwardedSignals` that arrives while the child runs is sent on to the child, and `devkit` does not die of it.
/// Only the child itself is signalled, not the processes it started. On a terminal the process group also gets Ctrl-C directly,
/// so a child on the terminal's foreground group sees SIGINT twice.
public struct FoundationProcessLauncher: ProcessLauncher {
    private let standardInput: FileHandle
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private let forwardedSignals: [Int32]

    /// The defaults are the real streams of `devkit` and the two signals a terminal or a CI runner sends: nothing is captured, nothing is merged.
    ///
    /// - Parameters:
    ///   - standardInput: the child's input.
    ///   - standardOutput: the child's output.
    ///   - standardError: the child's error stream.
    ///   - forwardedSignals: the signals that are sent to the child instead of acting on `devkit`.
    public init(
        standardInput: FileHandle = .standardInput,
        standardOutput: FileHandle = .standardOutput,
        standardError: FileHandle = .standardError,
        forwardedSignals: [Int32] = [SIGINT, SIGTERM]
    ) {
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.forwardedSignals = forwardedSignals
    }

    /// Starts the child, waits for it, and says how it ended and which signal was forwarded to it.
    ///
    /// The signals are taken over before the child starts: one that arrives earlier is kept and sent as soon as the child has a pid.
    /// One that arrives after the child ended is dropped. The child must not inherit the ignored dispositions; Foundation's `Process`
    /// resets them on start, and the end-to-end signal tests would fail if it did not.
    /// - Throws: `DevKitError.cannotStart` when the executable cannot be started.
    public func run(_ plan: RunPlan) throws -> LaunchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executable)
        process.arguments = plan.arguments
        process.environment = Self.inheritedEnvironment().merging(plan.environment) { _, added in added }
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        let state = OSAllocatedUnfairLock(initialState: ForwardingState())
        let guards = takeOverSignals(into: state)
        do {
            try process.run()
        } catch {
            giveBackSignals(guards)
            throw DevKitError.cannotStart(executable: plan.executable, reason: error.localizedDescription)
        }
        state.withLock { $0.start(pid: process.processIdentifier) }
        process.waitUntilExit()
        let forwarded = state.withLock { $0.finish() }
        giveBackSignals(guards)
        let outcome: ChildOutcome = process.terminationReason == .uncaughtSignal
            ? .signaled(process.terminationStatus)
            : .exited(process.terminationStatus)
        return LaunchResult(outcome: outcome, forwardedSignal: forwarded)
    }

    private static let droppedNames: Set<String> = ["BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "PS4"]

    /// The environment of `devkit` without what makes a shell run the caller's code before the first line of a script: `BASH_ENV` and
    /// `ENV` name a file it reads at start, `SHELLOPTS`, `BASHOPTS` and `PS4` switch on tracing that expands a prompt, and a `BASH_FUNC_*`
    /// variable is an exported function, which could stand in for a tool or for the `compgen` with which a script clears the functions
    /// it inherits. What the plan adds is never filtered.
    private static func inheritedEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { name, _ in
            !(Self.droppedNames.contains(name) || name.hasPrefix("BASH_FUNC_"))
        }
    }

    /// What the signal handlers and `run` share. Only the pid, the flag and the number cross threads, under a lock.
    private struct ForwardingState: Sendable {
        var pid: pid_t?
        var finished = false
        var forwarded: Int32?

        mutating func receive(_ number: Int32) {
            guard !finished else { return }
            forwarded = number
            if let pid { kill(pid, number) }
        }

        mutating func start(pid: pid_t) {
            self.pid = pid
            if let forwarded { kill(pid, forwarded) }
        }

        mutating func finish() -> Int32? {
            finished = true
            return forwarded
        }
    }

    private struct SignalGuard {
        let signalNumber: Int32
        let source: any DispatchSourceSignal
        let previous: (@convention(c) (Int32) -> Void)?
    }

    private func takeOverSignals(into state: OSAllocatedUnfairLock<ForwardingState>) -> [SignalGuard] {
        forwardedSignals.map { number in
            let previous = signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { state.withLock { $0.receive(number) } }
            source.resume()
            return SignalGuard(signalNumber: number, source: source, previous: previous)
        }
    }

    private func giveBackSignals(_ guards: [SignalGuard]) {
        for item in guards {
            item.source.cancel()
            signal(item.signalNumber, item.previous ?? SIG_DFL)
        }
    }
}
