import XCTest
import Foundation

/// The self-test of `check-api` is the oracle for the normalizer and the classifier of `--since`. Each test here changes one
/// behaviour in a copy of the script and expects the self-test of that copy to fail in the case that names that behaviour, so the
/// self-test is shown to be able to fail. A control with a comment-only change shows that the copy runs like the original.
final class CheckApiSelfTestMutantsEndToEndTests: XCTestCase {
    func test_swappingTheStatusOfRemovedAndAddedLines_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "return 1 if removed else 3 if added else 0", "return 3 if removed else 1 if added else 0",
            "a removed line is status 1 and an added line is status 3", failingCase: "delta-member-added"
        )
    }

    func test_usingTheDifferenceAloneAsTheStatus_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "return 1 if removed else 3 if added else 0", "return 1 if removed or added else 0",
            "an added line is not a breaking change", failingCase: "delta-member-added"
        )
    }

    func test_droppingTheRemovedLines_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "removed, added = difference(old, new), difference(new, old)", "removed, added = [], difference(new, old)",
            "a removed line must be reported", failingCase: "delta-member-removed"
        )
    }

    func test_forgettingTheDeclarationAContextBelongsTo_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "        context = tuple(stack)\n", "        context = ()\n",
            "the same line in two types is two lines", failingCase: "delta-removal-hidden-by-a-later-block"
        )
    }

    func test_notSortingTheTopLevelBlocks_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "print(\"\\n\".join(sorted(blocks)))", "print(\"\\n\".join(blocks))",
            "moving a type to another file must not look like an API change", failingCase: "conditional-declarations-reordered.same"
        )
    }

    func test_countingAPackageDeclarationAsApi_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "HIDDEN = {\"private\", \"fileprivate\", \"internal\", \"package\"}", "HIDDEN = {\"private\", \"fileprivate\", \"internal\"}",
            "a package declaration is not public API", failingCase: "directive-inside-a-hidden-block.same"
        )
    }

    func test_acceptingALineSeparatorInTheInterface_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "    if found:\n        sys.exit(\"check-api: line \"", "    if False:\n        sys.exit(\"check-api: line \"",
            "U+2028 would hide a line from the reader", failingCase: "comment-line-with-a-line-separator.error"
        )
    }

    func test_aRefWithoutABaselineThatIsNotStatusFour_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "        exit 4\n", "        exit 2\n",
            "a ref without a baseline is status 4", failingCase: "since-ref-without-a-baseline"
        )
    }

    /// The control: a copy that differs from the script only by a comment passes, so a mutant fails because of its mutation.
    func test_aCopyChangedOnlyByAComment_stillPassesTheSelfTest() throws {
        let sut = try makeSUT()
        let original = try String(contentsOf: sut.script, encoding: .utf8)
        try sut.rewrite(original.replacingOccurrences(of: "set -euo pipefail\n", with: "set -euo pipefail\n# a comment that changes nothing\n"))

        let result = try sut.runSelfTest()

        XCTAssertEqual(result.status, 0, "the copy passes the self-test: \(result.standardError.prefix(300))")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let moved: URL
        var script: URL { moved.appendingPathComponent("Scripts/check-api.sh") }

        /// An atomic write may drop the execute bit, and the self-test runs the script itself for its scenarios of --since.
        func rewrite(_ text: String) throws {
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }

        func runSelfTest() throws -> Captured {
            var environment = fixture.shimmedEnvironment()
            environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(repository)
            environment["DEVKIT_RESOURCES"] = moved.path
            environment["DEVKIT_WORK"] = EndToEndFixture.realPath(repository) + "/.build/devkit"
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
            result.standardError.contains("check-api: FAIL \(failingCase)"),
            "the case that names this behaviour is the one that fails (\(behaviour)): \(result.standardError.prefix(300))",
            file: file,
            line: line
        )
    }
}
