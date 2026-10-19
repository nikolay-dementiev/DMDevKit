import XCTest
import Foundation

/// `count-tests` runs in a scratch repository whose test files are tracked by git, with an `xcrun` shim that answers
/// `xcresulttool get test-results summary` from canned JSON.
final class CountTestsEndToEndTests: XCTestCase {
    static let threeTests = "final class A: XCTestCase {\n    func test_one() {}\n    func test_two() throws {}\n}\nfinal class B: XCTestCase {\n    func test_three() async {}\n}\n"

    // MARK: - The decision

    func test_everyTestMethodRanAndPassed_isStatusZero() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 3))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 0, "the count agrees: \(result.standardError)")
        XCTAssertEqual(result.standardOutput, "count-tests: all 3 tests ran and passed.\n", "the one summary line")
    }

    func test_aLostTestClass_isStatusOneWithTheCounts() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 1, passed: 1))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 1, "fewer tests ran than the files hold")
        XCTAssertTrue(result.standardError.contains("Expected 3 tests"), "the expected count is named: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("totalTestCount") && result.standardError.contains("passedTests"), "the counts of the bundle are printed: \(result.standardError)")
    }

    func test_aSkippedTest_isStatusOne() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 2, skipped: 1))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 1, "a test that skips itself is not a test that ran")
    }

    func test_aFailedTest_isStatusOne() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 2, failed: 1))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 1, "a failed test fails the count")
    }

    func test_moreTestsInTheBundleThanInTheFiles_isStatusOne() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 4, passed: 4))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 1, "the bundle is not the one of these files")
    }

    func test_aTotalThatIsNotThePassedCount_isStatusOne() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 4, passed: 3))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 1, "a test that neither passed nor failed nor skipped is not accepted")
    }

    func test_noTestMethodInTheFiles_isStatusOneEvenWhenTheBundleIsEmptyToo() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": "let value = 1\n"], summary: Summary(total: 0, passed: 0))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 1, "zero tests is never a pass")
        XCTAssertTrue(result.standardError.contains("Expected 0 tests"), "the expected count is named: \(result.standardError)")
    }

    func test_aGlobThatMatchesNoFile_isStatusOne() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 3))

        let result = try sut.run(["Fake.xcresult", "Elsewhere/*.swift"])

        XCTAssertEqual(result.status, 1, "a glob that finds nothing counts nothing")
    }

    // MARK: - What counts as a test method

    func test_attributesModifiersAndTrailingTextAreCounted() throws {
        let text = """
        final class A: XCTestCase {
            @available(iOS 18, *) func test_a() {}
            @MainActor
            public func testB() async throws {
            override func testC() // a comment
            nonisolated func testD()
            final func test_e()  {   }
        }

        """
        let sut = try makeSUT(files: ["Tests/A.swift": text], summary: Summary(total: 5, passed: 5))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 0, "five methods are counted, the attribute line alone is not: \(result.standardError)")
    }

    func test_helpersAndTestsWithArgumentsAreNotCounted() throws {
        let text = "final class A: XCTestCase {\n    func test_one() {}\n    private func helper() {}\n    func testing(value: Int) {}\n    func makeSUT() -> Int { 1 }\n}\n"
        let sut = try makeSUT(files: ["Tests/A.swift": text], summary: Summary(total: 1, passed: 1))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 0, "only the one test method is counted: \(result.standardError)")
    }

    func test_severalGlobs_areAddedUp() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests, "Examples/Tests/B.swift": "final class B: XCTestCase {\n    func test_x() {}\n}\n"], summary: Summary(total: 4, passed: 4))

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift", "Examples/Tests/*.swift"])

        XCTAssertEqual(result.status, 0, "three and one: \(result.standardError)")
    }

    // MARK: - The check could not be made (status 2)

    func test_aFailingXcresulttool_isStatusTwo() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 3))
        try sut.fixture.writeShim(named: "xcrun", body: "echo 'xcresulttool: no such bundle' >&2\nexit 1\n")

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 2, "a bundle that cannot be read is not a count that disagrees")
        XCTAssertTrue(result.standardError.contains("xcresulttool"), "the tool is named: \(result.standardError)")
    }

    func test_aSummaryThatIsNotJson_isStatusTwo() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 3))
        try "this is not json".write(to: sut.fixture.directory.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 2, "an unreadable summary is no measurement")
    }

    func test_aGitGrepThatFails_isStatusTwoNotAnExpectedCountOfZero() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 0, passed: 0))
        try sut.fixture.writeShim(named: "git", body: "for argument in \"$@\"; do\n    if [ \"$argument\" = grep ]; then echo 'fatal: grep is out of order' >&2; exit 128; fi\ndone\nexec /usr/bin/git \"$@\"\n")

        let result = try sut.run(["Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(result.status, 2, "a search that failed counted nothing, and nothing must not agree with an empty bundle")
        XCTAssertTrue(result.standardError.contains("grep is out of order"), "git's words are shown: \(result.standardError)")
    }

    func test_withoutTheBundleAndAGlob_isStatusTwoWithTheUsage() throws {
        let sut = try makeSUT(files: [:], summary: Summary(total: 0, passed: 0))

        let none = try sut.run([])
        let noGlob = try sut.run(["Fake.xcresult"])

        XCTAssertEqual(none.status, 2, "no arguments")
        XCTAssertTrue(none.standardError.contains("usage: devkit count-tests [--label <text>] <xcresult> <glob>..."), "the usage names the command: \(none.standardError)")
        XCTAssertEqual(noGlob.status, 2, "a bundle without a glob")
    }

    func test_label_namesTheCountInEveryMessage() throws {
        let passing = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 3))
        let failing = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 1, passed: 1))

        let ok = try passing.run(["--label", "watchOS", "Fake.xcresult", "Tests/*.swift"])
        let bad = try failing.run(["--label", "watchOS", "Fake.xcresult", "Tests/*.swift"])

        XCTAssertEqual(ok.standardOutput, "watchOS: all 3 tests ran and passed.\n", "the label leads the line")
        XCTAssertTrue(bad.standardError.contains("watchOS: Expected 3 tests"), "and the failure: \(bad.standardError)")
    }

    func test_withoutDevkit_theScriptRefusesToGuessTheRepository() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 3))

        let result = try sut.fixture.capture("/bin/bash", [sut.resources.appendingPathComponent("Scripts/count-tests.sh").path, "Fake.xcresult", "Tests/*.swift"], in: sut.repository, environment: sut.fixture.shimmedEnvironment())

        XCTAssertEqual(result.status, 2, "no DEVKIT_REPO_ROOT, no run")
        XCTAssertTrue(result.standardError.contains("run it as 'devkit count-tests'"), "the message names the command: \(result.standardError)")
    }

    // MARK: - Functions of the caller

    func test_anExportedGitFunction_isNotRunByAScriptStartedByHand_andIsRunWithoutTheClearingLine() throws {
        let sut = try makeSUT(files: ["Tests/A.swift": Self.threeTests], summary: Summary(total: 3, passed: 3))
        let marker = sut.fixture.directory.appendingPathComponent("git.ran")
        let functions = ["BASH_FUNC_git%%": "() { echo ran >> '\(marker.path)'; /usr/bin/git \"$@\"; }"]
        let root = EndToEndFixture.realPath(sut.repository)
        let line = "while IFS= read -r FUNCTION; do unset -f \"$FUNCTION\"; done < <(compgen -A function)"
        let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: sut.resources, to: moved)
        let mutated = moved.appendingPathComponent("Scripts/count-tests.sh")
        let original = try String(contentsOf: mutated, encoding: .utf8)
        XCTAssertTrue(original.contains(line), "the clearing line is in the script")
        var environment = sut.fixture.shimmedEnvironment(adding: functions)
        environment["DEVKIT_REPO_ROOT"] = root
        environment["DEVKIT_RESOURCES"] = sut.resources.path
        environment["DEVKIT_WORK"] = root + "/.build/devkit"

        _ = try sut.fixture.capture("/bin/bash", [sut.resources.appendingPathComponent("Scripts/count-tests.sh").path, "Fake.xcresult", "Tests/*.swift"], in: sut.repository, environment: environment)
        let ranWithTheLine = FileManager.default.fileExists(atPath: marker.path)
        try original.replacingOccurrences(of: line, with: ":").write(to: mutated, atomically: true, encoding: .utf8)
        _ = try sut.fixture.capture("/bin/bash", [mutated.path, "Fake.xcresult", "Tests/*.swift"], in: sut.repository, environment: environment)

        XCTAssertFalse(ranWithTheLine, "the caller's git function is cleared before it can run")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "positive control: without the line the function does run, so the check above can fail")
    }

    // MARK: - Helpers

    struct Summary {
        var total: Int
        var passed: Int
        var failed = 0
        var skipped = 0
        var json: String { "{\"totalTestCount\":\(total),\"passedTests\":\(passed),\"failedTests\":\(failed),\"skippedTests\":\(skipped)}" }
    }

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL

        func run(_ arguments: [String]) throws -> Captured {
            try fixture.capture(devkit.path, ["count-tests"] + arguments, in: repository, environment: fixture.shimmedEnvironment())
        }
    }

    private func makeSUT(files: [String: String], summary: Summary) throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = try fixture.makeRepository()
        for (path, text) in files {
            let url = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        if !files.isEmpty {
            let added = try fixture.capture("/usr/bin/env", ["git", "add", "-A"], in: repository)
            XCTAssertEqual(added.status, 0, "the test files are tracked: \(added.standardError)")
        }
        try summary.json.write(to: directory.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        try fixture.writeShim(named: "xcrun", body: "cat '\(directory.path)/summary.json'\n")
        return SUT(fixture: fixture, repository: repository, devkit: EndToEndFixture.devkitURL(for: Self.self), resources: EndToEndFixture.resourceFolder(for: Self.self))
    }
}
