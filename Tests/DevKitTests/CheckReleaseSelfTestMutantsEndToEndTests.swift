import XCTest
import Foundation

/// The self-test of `check-release` is the oracle for the decisions of the script. Each test here changes one decision in a copy
/// of the script and expects the self-test of that copy to fail in the case that names that decision, so the self-test is shown
/// to be able to fail. A control with a comment-only change shows that the copy runs like the original.
final class CheckReleaseSelfTestMutantsEndToEndTests: XCTestCase {
    func test_reportingAReleaseAsNotReadyWhenNoProblemWasFound_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "if [ \"${#PROBLEMS[@]}\" -gt 0 ]; then\n    report_problems\n    if [ \"$COULD_NOT_COMPARE\" -eq 1 ]; then",
            "if [ \"${#PROBLEMS[@]}\" -ge 0 ]; then\n    report_problems\n    if [ \"$COULD_NOT_COMPARE\" -eq 1 ]; then",
            "a release with no problem is ready", failingCase: "an additive release passes with the reminder"
        )
    }

    func test_believingThatEveryPreviousReleaseIsAnAncestor_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "merge-base --is-ancestor \"refs/tags/$PREVIOUS^{commit}\" HEAD || ANCESTOR_STATUS=$?",
            "merge-base --is-ancestor \"refs/tags/$PREVIOUS^{commit}\" HEAD || true",
            "a previous release on a side branch is not an ancestor", failingCase: "the previous release on a side branch is " +
                "not an ancestor"
        )
    }

    func test_believingTheDigesterOnAnyLine_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "'^(check-api-digester: )?[0-9]+ breaking changes? detected in '",
            "'breaking changes? detected in '",
            "the digester is believed on a line that reports a break at its start only", failingCase: "a break line in the " +
                "middle of a line is not a break"
        )
    }

    func test_matchingTheBreakingHeadingLiterally_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "'^ {0,3}(#{1,6}|\\*\\*|__)[^[:alnum:]]*breaking([^[:alnum:]]|$)'",
            "'^### Breaking changes$'",
            "a breaking heading is read at any level and with anything after the word", failingCase: "a breaking subsection " +
                "with blanks after it still fails"
        )
    }

    /// The control: a copy that differs from the script only by a comment passes, so a mutant fails because of its mutation.
    func test_aCopyChangedOnlyByAComment_stillPassesTheSelfTest() throws {
        let sut = try makeSUT()
        let original = try String(contentsOf: sut.script, encoding: .utf8)
        try sut.rewrite(original.replacingOccurrences(of: "set -euo pipefail\n",
            with: "set -euo pipefail\n# a comment that changes nothing\n"))

        let result = try sut.runSelfTest()

        XCTAssertEqual(result.status, 0, "the copy passes the self-test: \(result.standardError.prefix(300))")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let moved: URL
        var script: URL { moved.appendingPathComponent("Scripts/check-release.sh") }

        /// An atomic write may drop the execute bit, and the self-test copies the script for its scenarios.
        func rewrite(_ text: String) throws {
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }

        func runSelfTest() throws -> Captured {
            var environment = fixture.shimmedEnvironment()
            let root = EndToEndFixture.realPath(repository)
            environment["DEVKIT_REPO_ROOT"] = root
            environment["DEVKIT_RESOURCES"] = moved.path
            environment["DEVKIT_CONF"] = root + "/devkit.conf"
            environment["DEVKIT_WORK"] = root + "/.build/devkit"
            return try fixture.capture("/bin/bash", [script.path, "--self-test"], in: repository, environment: environment)
        }
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let moved = fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: EndToEndFixture.resourceFolder(for: Self.self), to: moved)
        return SUT(fixture: fixture, repository: try fixture.makeRepository(), moved: moved)
    }

    private func assertSelfTestFails(
        _ old: String,
        _ new: String,
        _ behaviour: String,
        failingCase: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let sut = try makeSUT()
        let original = try String(contentsOf: sut.script, encoding: .utf8)
        guard original.components(separatedBy: old).count - 1 == 1 else {
            XCTFail("the text to mutate is in the script exactly once (\(behaviour))", file: file, line: line)
            return
        }
        try sut.rewrite(original.replacingOccurrences(of: old, with: new))

        let result = try sut.runSelfTest()

        XCTAssertEqual(result.status, 1, "\(behaviour): the self-test of the mutated copy fails", file: file, line: line)
        XCTAssertTrue(
            result.standardError.contains("check-release: self-test FAIL \(failingCase):"),
            "the case that names this behaviour is the one that fails (\(behaviour)): \(result.standardError.prefix(300))",
            file: file,
            line: line
        )
    }
}
