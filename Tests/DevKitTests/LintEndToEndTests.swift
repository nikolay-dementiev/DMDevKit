import XCTest
import Foundation

final class LintEndToEndTests: XCTestCase {
    func test_cleanTree_printsTheSummaryAndExitsZero() throws {
        let sut = try makeSUT()

        let result = try sut.run(["lint"])

        XCTAssertEqual(result.status, 0, "no violation: \(result.standardError)")
        XCTAssertEqual(result.standardOutput, "lint: no violations (SwiftLint 0.65.1) in 1 files.\n", "the summary names the version and the file count")
        XCTAssertEqual(result.standardError, "", "nothing on standard error")
    }

    func test_unknownOption_isAUsageErrorBeforeAnyFetch() throws {
        let sut = try makeSUT(seed: false)

        let result = try sut.run(["lint", "--bogus"])

        XCTAssertEqual(result.status, 2, "a mistyped option would otherwise lint without the analyzer and pass")
        XCTAssertTrue(result.standardError.contains("usage: devkit lint [--analyze <xcodebuild log>]"), "the usage names the command")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.curlLog.path), "nothing was fetched")
    }

    func test_swiftlintVersionThatIsNotThreeGroupsOfDigits_isStatusTwo() throws {
        for version in ["0.65", "0.65.1.1", "v0.65.1", "", "0.65.x"] {
            let sut = try makeSUT(config: "swiftlint_version: \(version)\nincluded:\n  - Sources\n", seed: false)

            let result = try sut.run(["lint"])

            XCTAssertEqual(result.status, 2, "'\(version)' is not a version")
            XCTAssertTrue(
                result.standardError.contains("lint: .swiftlint.yml must pin swiftlint_version to a version such as 0.65.1, not '\(version)'"),
                "the message names the value: \(result.standardError)"
            )
        }
    }

    func test_versionMissingFromTheChecksumTable_isStatusTwoAndNothingIsDownloaded() throws {
        let sut = try makeSUT(config: "swiftlint_version: 0.64.0\nincluded:\n  - Sources\n", seed: false)

        let result = try sut.run(["lint"])

        XCTAssertEqual(result.status, 2, "DMDevKit has no checksum for it")
        XCTAssertTrue(result.standardError.contains("lint: DMDevKit has no checksum for SwiftLint 0.64.0"), "the message says whose table lacks it")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.curlLog.path), "nothing was downloaded")
    }

    func test_includedFolderThatDoesNotExist_isStatusTwo() throws {
        let sut = try makeSUT(config: "swiftlint_version: 0.65.1\nincluded:\n  - Gone\n", seed: false)

        let result = try sut.run(["lint"])

        XCTAssertEqual(result.status, 2, "a missing folder would drop out of the lint without a word")
        XCTAssertTrue(result.standardError.contains("lint: .swiftlint.yml includes Gone, which does not exist"), "the message names the folder")
    }

    func test_includedFolderWithoutSwiftFiles_passesSwiftLintsOwnStatusThrough() throws {
        let sut = try makeSUT(files: [:])

        let result = try sut.run(["lint"])

        XCTAssertEqual(result.status, 1, "SwiftLint's own status for 'No lintable files found'")
        XCTAssertTrue(result.standardError.contains("No lintable files found"), "its message is shown: \(result.standardError)")
        XCTAssertEqual(result.standardOutput, "", "no summary on failure")
    }

    func test_violation_failsWithTheToolsStatusAndShowsTheReportWithoutProgressLines() throws {
        let sut = try makeSUT(files: ["Sources/A.swift": "let maybe: Int? = 1\nlet forced = maybe!\n"])

        let result = try sut.run(["lint"])

        XCTAssertEqual(result.status, 2, "--strict makes a violation fatal: SwiftLint's status 2 passes through")
        XCTAssertTrue(result.standardError.contains("force_unwrapping"), "the report names the rule: \(result.standardError)")
        XCTAssertFalse(result.standardError.contains("Linting '"), "the per-file progress lines are filtered out")
        XCTAssertEqual(result.standardOutput, "", "no summary on failure")
    }

    func test_analyzeWithoutALog_isStatusOneNamingTheMissingArgument() throws {
        let sut = try makeSUT()

        let result = try sut.run(["lint", "--analyze"])

        XCTAssertEqual(result.status, 1, "bash's error for a missing ${2:?} ends the command substitution")
        XCTAssertTrue(result.standardError.contains("give the path of an xcodebuild log"), "the message says what is missing")
    }

    func test_analyzeWithAnUnreadableLog_passesSwiftLintsStatusThrough() throws {
        let sut = try makeSUT()

        let result = try sut.run(["lint", "--analyze", "nolog.log"])

        XCTAssertEqual(result.status, 1, "SwiftLint's own status")
        XCTAssertTrue(result.standardError.contains("Could not read compiler log"), "its message is shown: \(result.standardError)")
    }

    func test_analyzeWithALogThatHasNoCompilerInvocation_isStatusTwo() throws {
        let sut = try makeSUT(files: ["Sources/A.swift": "let value = 1\n", "build.log": "no compiler call here\n"])

        let result = try sut.run(["lint", "--analyze", "build.log"])

        XCTAssertEqual(result.status, 2, "the analyzer read no file, and SwiftLint alone would still exit 0")
        XCTAssertTrue(result.standardError.contains("lint: the analyzer read no Swift file"), "the message says why: \(result.standardError)")
    }

    func test_withoutDevkit_theScriptRefusesToGuessTheRepository() throws {
        let sut = try makeSUT(seed: false)
        let script = sut.resources.appendingPathComponent("Scripts/lint.sh")

        let result = try sut.fixture.capture("/bin/bash", [script.path], in: sut.repository)

        XCTAssertEqual(result.status, 2, "no DEVKIT_REPO_ROOT, no run")
        XCTAssertTrue(result.standardError.contains("run it as 'devkit lint'"), "the message names the command")
    }

    func test_scriptsCopiedOutOfAnyRepository_stillLintTheRepositoryTheyAreGiven() throws {
        let sut = try makeSUT()
        let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: sut.resources, to: moved)
        var environment = sut.fixture.shimmedEnvironment()
        environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(sut.repository)
        environment["DEVKIT_RESOURCES"] = moved.path

        let result = try sut.fixture.capture("/bin/bash", [moved.appendingPathComponent("Scripts/lint.sh").path], in: sut.repository, environment: environment)

        XCTAssertEqual(result.status, 0, "a script that looked at its own location would not find the repository: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.contains("in 1 files"), "it linted the repository it was given")
    }

    func test_noResourceScriptDerivesAPathFromItsOwnLocation() throws {
        let sut = try makeSUT(seed: false)

        let result = try sut.fixture.capture("/usr/bin/grep", ["-rn", "BASH_SOURCE", sut.resources.appendingPathComponent("Scripts").path])

        XCTAssertEqual(result.status, 1, "grep finds nothing: \(result.standardOutput)")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL
        var curlLog: URL { fixture.directory.appendingPathComponent("curl.log") }

        func run(_ arguments: [String]) throws -> Captured {
            try fixture.writeShim(named: "curl", body: "echo \"$*\" >> '\(curlLog.path)'\nexit 22\n")
            return try fixture.capture(devkit.path, arguments, in: repository, environment: fixture.shimmedEnvironment())
        }
    }

    private func makeSUT(
        config: String = "swiftlint_version: 0.65.1\nopt_in_rules:\n  - force_unwrapping\nincluded:\n  - Sources\n",
        files: [String: String] = ["Sources/A.swift": "let value = 1\n"],
        seed: Bool = true
    ) throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = try fixture.makeRepository()
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try config.write(to: repository.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        for (path, text) in files {
            try text.write(to: repository.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        if seed { try RealSwiftLint.seed(into: repository) }
        return SUT(
            fixture: fixture,
            repository: repository,
            devkit: EndToEndFixture.devkitURL(for: Self.self),
            resources: EndToEndFixture.resourceFolder(for: Self.self)
        )
    }
}
