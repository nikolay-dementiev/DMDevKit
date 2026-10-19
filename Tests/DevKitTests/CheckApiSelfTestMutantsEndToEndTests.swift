import XCTest
import Foundation

/// The self-test of `check-api` is the oracle for the normalizer and the classifier of `--since`. Each test here changes one
/// behaviour in a copy of the script and expects the self-test of that copy to fail, so the self-test is shown to be able to fail.
final class CheckApiSelfTestMutantsEndToEndTests: XCTestCase {
    func test_swappingTheStatusOfRemovedAndAddedLines_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "return 1 if removed else 3 if added else 0", "return 3 if removed else 1 if added else 0",
            "a removed line is status 1 and an added line is status 3"
        )
    }

    func test_usingTheDifferenceAloneAsTheStatus_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "return 1 if removed else 3 if added else 0", "return 1 if removed or added else 0",
            "an added line is not a breaking change"
        )
    }

    func test_droppingTheRemovedLines_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "removed, added = difference(old, new), difference(new, old)", "removed, added = [], difference(new, old)",
            "a removed line must be reported"
        )
    }

    func test_forgettingTheDeclarationAContextBelongsTo_failsTheSelfTest() throws {
        try assertSelfTestFails("        context = tuple(stack)\n", "        context = ()\n", "the same line in two types is two lines")
    }

    func test_notSortingTheTopLevelBlocks_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "print(\"\\n\".join(sorted(blocks)))", "print(\"\\n\".join(blocks))",
            "moving a type to another file must not look like an API change"
        )
    }

    func test_countingAPackageDeclarationAsApi_failsTheSelfTest() throws {
        try assertSelfTestFails(
            "HIDDEN = {\"private\", \"fileprivate\", \"internal\", \"package\"}", "HIDDEN = {\"private\", \"fileprivate\", \"internal\"}",
            "a package declaration is not public API"
        )
    }

    func test_acceptingALineSeparatorInTheInterface_failsTheSelfTest() throws {
        try assertSelfTestFails("    if found:\n        sys.exit(\"check-api: line \"", "    if False:\n        sys.exit(\"check-api: line \"", "U+2028 would hide a line from the reader")
    }

    func test_aRefWithoutABaselineThatIsNotStatusFour_failsTheSelfTest() throws {
        try assertSelfTestFails("        exit 4\n", "        exit 2\n", "a ref without a baseline is status 4")
    }

    // MARK: - Helpers

    private func assertSelfTestFails(_ old: String, _ new: String, _ behaviour: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = try fixture.makeRepository()
        let moved = fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: EndToEndFixture.resourceFolder(for: Self.self), to: moved)
        let script = moved.appendingPathComponent("Scripts/check-api.sh")
        let original = try String(contentsOf: script, encoding: .utf8)
        XCTAssertEqual(original.components(separatedBy: old).count - 1, 1, "the text to mutate is in the script exactly once", file: file, line: line)
        try original.replacingOccurrences(of: old, with: new).write(to: script, atomically: true, encoding: .utf8)
        var environment = fixture.shimmedEnvironment()
        environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(repository)
        environment["DEVKIT_RESOURCES"] = moved.path
        environment["DEVKIT_WORK"] = EndToEndFixture.realPath(repository) + "/.build/devkit"

        let result = try fixture.capture("/bin/bash", [script.path, "--self-test"], in: repository, environment: environment)

        XCTAssertEqual(result.status, 1, "\(behaviour): the self-test of the mutated copy fails", file: file, line: line)
        XCTAssertTrue(result.standardError.contains("check-api: FAIL"), "a case is named as failing (\(behaviour)): \(result.standardError.prefix(300))", file: file, line: line)
    }
}
