import XCTest
import Foundation
import os
import DevKitCore

final class FoundationProcessLauncherTests: XCTestCase {
    func test_arguments_reachTheScriptUnchanged() throws {
        let sut = try makeSUT()
        let arguments = ["plain", "two words", "", "*", "$HOME", "line1\nline2", "quote'd \"x\""]
        let script = try makeScript("echo \"argc=$#\"; for a in \"$@\"; do printf '[%s]\\n' \"$a\"; done")

        _ = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script] + arguments, environment: [:]))

        XCTAssertEqual(
            try sut.standardOutput(),
            "argc=7\n[plain]\n[two words]\n[]\n[*]\n[$HOME]\n[line1\nline2]\n[quote'd \"x\"]\n",
            "seven arguments, none split, merged, expanded or dropped"
        )
    }

    func test_exitCode_isReportedAsExited() throws {
        for code: Int32 in [0, 1, 2, 7] {
            let sut = try makeSUT()
            let script = try makeScript("exit \(code)")

            let result = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script], environment: [:]))

            XCTAssertEqual(result, LaunchResult(outcome: .exited(code), forwardedSignal: nil), "exit \(code) is not changed")
        }
    }

    func test_childKilledBySignal_isReportedAsSignaled() throws {
        let sut = try makeSUT()
        let script = try makeScript("kill -TERM $$; sleep 5")

        let result = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script], environment: [:]))

        XCTAssertEqual(result, LaunchResult(outcome: .signaled(15), forwardedSignal: nil),
            "SIGTERM ended the child, devkit forwarded nothing")
    }

    func test_standardOutputAndStandardError_stayApart() throws {
        let sut = try makeSUT()
        let script = try makeScript("echo progress >&2; echo A1B2; echo more >&2")

        _ = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script], environment: [:]))

        XCTAssertEqual(try sut.standardOutput(), "A1B2\n", "standard output holds the result line only")
        XCTAssertEqual(try sut.standardError(), "progress\nmore\n", "progress stays on standard error")
    }

    func test_scriptWithoutExecuteBit_runsThroughBash() throws {
        let sut = try makeSUT()
        let script = try makeScript("echo ran", mode: 0o644)

        let result = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script], environment: [:]))

        XCTAssertEqual(result.outcome, .exited(0), "bash reads the file, the mode does not matter")
        XCTAssertEqual(try sut.standardOutput(), "ran\n", "the script ran")
    }

    func test_pythonWithDashB_writesNoBytecode() throws {
        let sut = try makeSUT()
        let script = try makeScript("import sys\nprint(sys.dont_write_bytecode)", name: "emit.py")

        let result = try sut.launcher.run(RunPlan(executable: "/usr/bin/env", arguments: ["python3", "-B", script],
            environment: [:]))

        XCTAssertEqual(result.outcome, .exited(0), "python3 ran the script")
        XCTAssertEqual(try sut.standardOutput(), "True\n", "-B reached python3")
    }

    func test_environment_isAddedToTheInheritedOne() throws {
        let sut = try makeSUT()
        let script = try makeScript("echo \"$DEVKIT_PROBE\"; test -n \"$PATH\" && echo inherited")

        _ = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script], environment: ["DEVKIT_PROBE": "added"]))

        XCTAssertEqual(try sut.standardOutput(), "added\ninherited\n", "the added variable and the inherited PATH are both there")
    }

    func test_inheritedShellStartupHooks_areNotPassedToTheChild() throws {
        let sut = try makeSUT()
        let hooks = ["BASH_ENV": "/nonexistent/startup", "ENV": "/nonexistent/startup", "BASH_FUNC_shasum%%": "() { echo fake; }",
            "DEVKIT_TEST_KEPT": "kept",
                     "SHELLOPTS": "xtrace", "BASHOPTS": "extdebug", "PS4": "$(touch /nonexistent/x)"]
        let previous = hooks.keys.reduce(into: [String: String]()) { $0[$1] = ProcessInfo.processInfo.environment[$1] }
        for (name, value) in hooks { setenv(name, value, 1) }
        addTeardownBlock {
            for name in hooks.keys {
                if let old = previous[name] { setenv(name, old, 1) } else { unsetenv(name) }
            }
        }

        _ = try sut.launcher.run(RunPlan(executable: "/usr/bin/env", arguments: [], environment: [:]))

        let names = try sut.standardOutput().split(separator: "\n").compactMap { $0.split(separator: "=",
            maxSplits: 1).first.map(String.init) }
        XCTAssertFalse(names.contains("BASH_ENV"), "a file bash would run at start is not inherited: \(names)")
        XCTAssertFalse(names.contains("ENV"), "the startup file of other shells is not inherited: \(names)")
        XCTAssertFalse(names.contains { $0.hasPrefix("BASH_FUNC_") }, "an exported function is not inherited: \(names)")
        XCTAssertFalse(names.contains("SHELLOPTS") || names.contains("BASHOPTS") || names.contains("PS4"),
            "options that make bash trace or expand a prompt are not inherited: \(names)")
        XCTAssertTrue(names.contains("DEVKIT_TEST_KEPT"), "an ordinary variable still is: \(names)")
        XCTAssertTrue(names.contains("PATH"), "so is the PATH: \(names)")
    }

    func test_environmentOfThePlan_isNeverFiltered() throws {
        let sut = try makeSUT()
        let script = try makeScript("echo \"${BASH_ENV-unset}\"")

        _ = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: ["--noprofile", script],
            environment: ["BASH_ENV": "/nonexistent/from-the-plan"]))

        let printed = try sut.standardOutput()
        XCTAssertTrue(printed.hasPrefix("/nonexistent/from-the-plan"), "what devkit itself adds reaches the child: \(printed)")
    }

    func test_workingDirectory_isTheCallers() throws {
        let sut = try makeSUT()
        let script = try makeScript("pwd -P")

        _ = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script], environment: [:]))

        // realpath keeps /private on macOS, as `pwd -P` does; resolvingSymlinksInPath drops it.
        let expected = EndToEndFixture.realPath(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        XCTAssertEqual(try sut.standardOutput(), expected + "\n", "the child does not change directory")
    }

    func test_standardInput_isPassedThrough() throws {
        let sut = try makeSUT(standardInput: "from stdin\n")
        let script = try makeScript("cat")

        _ = try sut.launcher.run(RunPlan(executable: "/bin/bash", arguments: [script], environment: [:]))

        XCTAssertEqual(try sut.standardOutput(), "from stdin\n", "the child reads the input of devkit")
    }

    func test_executableThatDoesNotExist_throwsCannotStart() throws {
        let sut = try makeSUT()

        XCTAssertThrowsError(
            try sut.launcher.run(RunPlan(executable: "/nonexistent/interpreter", arguments: [], environment: [:])),
            "a missing interpreter is an error, not an exit code"
        ) { error in
            guard case DevKitError.cannotStart(let executable, _) = error else {
                return XCTFail("expected cannotStart, got \(error)")
            }
            XCTAssertEqual(executable, "/nonexistent/interpreter", "the error names the executable")
        }
    }

    // MARK: - Helpers

    struct SUT {
        let launcher: FoundationProcessLauncher
        let outputURL: URL
        let errorURL: URL

        func standardOutput() throws -> String { try String(contentsOf: outputURL, encoding: .utf8) }
        func standardError() throws -> String { try String(contentsOf: errorURL, encoding: .utf8) }
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("devkit-launcher-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func makeSUT(standardInput: String = "") throws -> SUT {
        let inputURL = directory.appendingPathComponent("stdin-\(UUID().uuidString)")
        let outputURL = directory.appendingPathComponent("stdout-\(UUID().uuidString)")
        let errorURL = directory.appendingPathComponent("stderr-\(UUID().uuidString)")
        try standardInput.write(to: inputURL, atomically: true, encoding: .utf8)
        for url in [outputURL, errorURL] {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil), "the capture file exists")
        }
        let launcher = FoundationProcessLauncher(
            standardInput: try FileHandle(forReadingFrom: inputURL),
            standardOutput: try FileHandle(forWritingTo: outputURL),
            standardError: try FileHandle(forWritingTo: errorURL)
        )
        return SUT(launcher: launcher, outputURL: outputURL, errorURL: errorURL)
    }

    private func makeScript(_ body: String, name: String = "script.sh", mode: Int = 0o644) throws -> String {
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url.path
    }
}

final class FoundationProcessLauncherSignalTests: XCTestCase {
    private var previousDisposition: (@convention(c) (Int32) -> Void)?

    // SIGUSR1 is ignored by the test process for the whole test, so that a signal sent outside the launcher's window cannot end
    // the runner.
    override func setUp() {
        previousDisposition = signal(SIGUSR1, SIG_IGN)
    }

    override func tearDown() {
        signal(SIGUSR1, previousDisposition ?? SIG_DFL)
    }

    func test_signalReceivedWhileTheChildRuns_isForwardedAndReported() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-signal-\(UUID().uuidString)",
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let ready = directory.appendingPathComponent("ready")
        let marker = directory.appendingPathComponent("marker")
        let script = directory.appendingPathComponent("trap.sh")
        // The child answers SIGUSR1 with a marker and exit 0; without the signal it waits ten seconds and exits 5.
        try """
        trap 'echo got > "$MARKER"; exit 0' USR1
        echo ready > "$READY"
        for i in $(seq 1 100); do sleep 0.1; done
        exit 5
        """.write(to: script, atomically: true, encoding: .utf8)
        let sut = FoundationProcessLauncher(forwardedSignals: [SIGUSR1])
        let finished = OSAllocatedUnfairLock(initialState: false)
        // Sends the signal again and again while the launcher runs: the first ones may come before it is armed.
        DispatchQueue.global().async {
            while !finished.withLock({ $0 }) && !FileManager.default.fileExists(atPath: marker.path) {
                if FileManager.default.fileExists(atPath: ready.path) { kill(getpid(), SIGUSR1) }
                usleep(50_000)
            }
        }
        defer { finished.withLock { $0 = true } }

        let result = try sut.run(RunPlan(
            executable: "/bin/bash",
            arguments: [script.path],
            environment: ["READY": ready.path, "MARKER": marker.path]
        ))

        XCTAssertEqual(result, LaunchResult(outcome: .exited(0), forwardedSignal: SIGUSR1),
            "the child saw the signal and the launcher says which one it forwarded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "the child's trap ran")
    }
}
