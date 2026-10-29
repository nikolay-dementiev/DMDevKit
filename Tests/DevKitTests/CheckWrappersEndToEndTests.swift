import XCTest
import Foundation

/// `check-wrappers` copies the listed wrappers into a scratch repository, puts a recording `swift` first on the PATH and checks
/// that each wrapper forwards faithfully. The wrappers here are the real ones of the libraries, so that the clean set is what
/// the command has to accept.
final class CheckWrappersEndToEndTests: XCTestCase {
    static let stems = ["lint", "check-lint-contract", "check-lint-tool", "prepare-simulator"]
    static let fileNames = stems.map { "\($0).sh" }

    // MARK: - The clean set

    func test_theFourRealWrappers_areStatusZeroWithAnOkLineForEach() throws {
        let sut = try makeSUT()

        let result = try sut.run(["check-wrappers"])

        XCTAssertEqual(result.status, 0, "faithful wrappers pass: \(result.standardError)")
        for stem in Self.stems {
            let line = "check-wrappers: ok   \(stem).sh forwards its arguments, directory, status and streams\n"
            XCTAssertTrue(result.standardOutput.contains(line), "'\(stem).sh' has its ok line: \(result.standardOutput)")
        }
        XCTAssertTrue(result.standardOutput.hasSuffix("check-wrappers: the 4 scripts forward to devkit as they should.\n"),
            "the last line counts the scripts: \(result.standardOutput)")
        XCTAssertEqual(result.standardError, "", "nothing on standard error")
    }

    func test_aFolderGivenOnTheCommandLine_isCheckedInsteadOfScripts() throws {
        let sut = try makeSUT(folder: "Other")

        let result = try sut.run(["check-wrappers", "Other"])

        XCTAssertEqual(result.status, 0, "a relative folder is taken from the working directory: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.contains("the 4 scripts forward"), "the four were checked: \(result.standardOutput)")
    }

    func test_aLibraryWithOneWrapper_passesAndSaysSo() throws {
        let sut = try makeSUT(listed: ["lint.sh"], present: ["lint.sh"])

        let result = try sut.run(["check-wrappers"])

        XCTAssertEqual(result.status, 0, "only the listed files are checked: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.hasSuffix("check-wrappers: the 1 script forwards to devkit as it should.\n"),
            "one script, singular: \(result.standardOutput)")
    }

    // MARK: - What cannot be checked

    func test_noWrappersSetting_isStatusTwoAndSaysWhatToList() throws {
        let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\n")

        let result = try sut.run(["check-wrappers"])

        XCTAssertEqual(result.status, 2, "no list, no pass: a pass must mean that named files were checked")
        XCTAssertTrue(
            result.standardError.contains("devkit.conf sets no WRAPPERS; list the scripts that forward to devkit"),
            "the message says what to set: \(result.standardError)"
        )
        XCTAssertEqual(result.standardOutput, "", "nothing was checked")
    }

    func test_anEntryThatIsNotAShellScript_isStatusTwoWithTheReason() throws {
        let sut = try makeSUT(listed: ["lint.sh", "export-coverage.py"], present: ["lint.sh"])

        let result = try sut.run(["check-wrappers"])

        XCTAssertEqual(result.status, 2, "only .sh wrappers are supported")
        XCTAssertTrue(result.standardError.contains("export-coverage.py"), "the entry is named: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("must end in .sh"), "the reason is given: \(result.standardError)")
    }

    func test_anEntryThatNamesNoDevkitCommand_isStatusTwo() throws {
        let sut = try makeSUT(listed: ["lint.sh", "lnit.sh"], present: ["lint.sh", "lnit.sh"])

        let result = try sut.run(["check-wrappers"])

        XCTAssertEqual(result.status, 2, "a typo must not pass")
        XCTAssertTrue(result.standardError.contains("devkit has no command 'lnit'"),
            "the command is named: \(result.standardError)")
    }

    func test_aListedWrapperThatIsNotInTheFolder_isStatusTwo() throws {
        let sut = try makeSUT(present: ["lint.sh", "check-lint-contract.sh", "check-lint-tool.sh"])

        let result = try sut.run(["check-wrappers"])

        XCTAssertEqual(result.status, 2, "a missing wrapper is not a pass")
        XCTAssertTrue(result.standardError.contains("prepare-simulator.sh does not exist"),
            "the file is named: \(result.standardError)")
    }

    func test_twoArguments_areAUsageErrorBeforeAnyCheck() throws {
        let sut = try makeSUT()

        let result = try sut.run(["check-wrappers", "Scripts", "More"])

        XCTAssertEqual(result.status, 2, "one folder at most")
        XCTAssertTrue(result.standardError.contains("usage: devkit check-wrappers [<folder>]"),
            "the usage line: \(result.standardError)")
        XCTAssertEqual(result.standardOutput, "", "nothing was checked")
    }

    // MARK: - A wrapper that does not forward faithfully, one property at a time

    func test_aWrapperThatDoesNotKeepTheArgumentsApart_failsTheForwardingCheck() throws {
        let sut = try makeSUT(overrides: ["lint.sh": try mutant(of: "lint", replacing: "\"$@\"", with: "$*")])

        let result = try sut.run(["check-wrappers"])

        assertOnlyLintFails(result, message: "lint.sh started in another directory: expected the call")
    }

    func test_aWrapperThatStaysInTheDirectoryItWasStartedIn_failsTheForwardingCheck() throws {
        let sut = try makeSUT(overrides: ["lint.sh": try mutant(of: "lint", replacing: "cd \"$ROOT\" || exit 70\n", with: "")])

        let result = try sut.run(["check-wrappers"])

        assertOnlyLintFails(result, message: "lint.sh started in another directory: expected the call")
    }

    func test_aWrapperThatNamesAnotherCommand_failsTheForwardingCheck() throws {
        let sut = try makeSUT(overrides: ["lint.sh": try mutant(of: "lint", replacing: "devkit lint", with: "devkit lnit")])

        let result = try sut.run(["check-wrappers"])

        assertOnlyLintFails(result, message: "lint.sh started in another directory: expected the call")
    }

    func test_aWrapperThatAddsAnArgumentWhenGivenNone_failsTheNoArgumentCheck() throws {
        let sut = try makeSUT(overrides: ["lint.sh": try mutant(of: "lint", replacing: "\"$@\"", with: "\"${@:-extra}\"")])

        let result = try sut.run(["check-wrappers"])

        assertOnlyLintFails(result, message: "lint.sh started from its own folder with no argument: expected the call")
    }

    func test_aWrapperThatPrintsALineOfItsOwn_failsTheStreamsCheck() throws {
        let printing = try mutant(of: "lint", replacing: "exec swift", with: "echo hello\nexec swift")
        let sut = try makeSUT(overrides: ["lint.sh": printing])

        let result = try sut.run(["check-wrappers"])

        assertOnlyLintFails(result, message: "lint.sh printed [hello\nout from the shim] on standard output")
    }

    func test_aWrapperThatEndsWithAnotherStatus_failsTheStatusCheck() throws {
        let sut = try makeSUT(overrides: ["lint.sh": try mutant(of: "lint", replacing: "exec swift", with: "swift")
            + "exit 0\n"])

        let result = try sut.run(["check-wrappers"])

        assertOnlyLintFails(result, message: "lint.sh ended with status 0 where the shim ended with 1")
    }

    func test_aWrapperThatDoesNotExec_failsOnlyTheExecCheck() throws {
        let sut = try makeSUT(overrides: ["lint.sh": try mutant(of: "lint", replacing: "exec swift", with: "swift")])

        let result = try sut.run(["check-wrappers"])

        assertOnlyLintFails(result, message: "lint.sh did not exec swift")
        XCTAssertFalse(result.standardError.contains("ended with status"),
            "the status still passes through, so only the exec check reports it: \(result.standardError)")
    }

    // MARK: - Helpers

    private func mutant(of stem: String, replacing original: String, with replacement: String) throws -> String {
        let clean = Self.wrapper(for: stem)
        let changed = clean.replacingOccurrences(of: original, with: replacement)
        XCTAssertNotEqual(changed, clean, "'\(original)' is in the wrapper of \(stem), so the mutant differs from it")
        return changed
    }

    private func assertOnlyLintFails(_ result: Captured, message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.status, 1, "one property does not hold: \(result.standardError)", file: file, line: line)
        XCTAssertTrue(result.standardError.contains("check-wrappers: FAIL \(message)"),
            "the failure says which property: \(result.standardError)", file: file, line: line)
        XCTAssertFalse(result.standardOutput.contains("ok   lint.sh"), "the mutant has no ok line", file: file, line: line)
        XCTAssertTrue(result.standardOutput.contains("ok   prepare-simulator.sh"),
            "the other wrappers are still checked and pass: \(result.standardOutput)", file: file, line: line)
        XCTAssertTrue(result.standardError.hasSuffix(" failures in 16 checks of 4 scripts\n"),
            "the summary counts four checks of each of the four scripts: \(result.standardError)", file: file, line: line)
    }

    static func wrapper(for stem: String) -> String {
        """
        #!/bin/bash
        #
        # Kept at this path for its callers; `devkit \(stem)` does the work. The script goes to the repository root first,
        # because devkit takes the repository from the working directory.

        ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        cd "$ROOT" || exit 70
        exec swift run --quiet --package-path Tools devkit \(stem) "$@"

        """
    }

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL

        func run(_ arguments: [String]) throws -> Captured {
            try fixture.capture(devkit.path, arguments, in: repository)
        }
    }

    /// - Parameters:
    ///   - listed: what `WRAPPERS` holds; all four by default.
    ///   - present: the wrapper files that exist in the folder; all that are listed by default. A file gets the wrapper
    ///     of its stem.
    ///   - overrides: the text of a wrapper, by file name, where a test wants a wrapper that is not the real one.
    ///   - conf: the whole `devkit.conf` when the test needs a different one.
    ///   - folder: the folder of the wrappers, relative to the repository.
    private func makeSUT(
        listed: [String] = CheckWrappersEndToEndTests.fileNames,
        present: [String]? = nil,
        overrides: [String: String] = [:],
        conf: String? = nil,
        folder: String = "Scripts"
    ) throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = try fixture.makeRepository()
        let scripts = repository.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        for name in present ?? listed {
            let file = scripts.appendingPathComponent(name)
            try (overrides[name] ?? Self.wrapper(for: String(name.dropLast(3))))
                .write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let setting = "WRAPPERS=(\(listed.joined(separator: " ")))"
        try (conf ?? "DEVKIT_CONF_VERSION=1\n\(setting)\n")
            .write(to: repository.appendingPathComponent("devkit.conf"), atomically: true, encoding: .utf8)
        return SUT(fixture: fixture, repository: repository, devkit: EndToEndFixture.devkitURL(for: Self.self))
    }
}
