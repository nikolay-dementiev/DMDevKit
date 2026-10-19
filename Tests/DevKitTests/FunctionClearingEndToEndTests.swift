import XCTest
import Foundation

/// Every command that sources the SwiftLint helper clears the shell functions it inherits before anything runs, so that a function
/// in the caller's environment cannot stand in for `shasum` or another tool the checksum check relies on.
final class FunctionClearingEndToEndTests: XCTestCase {
    private static let commands: [(name: String, arguments: [String])] = [
        ("lint", ["lint"]),
        ("check-lint-contract", ["check-lint-contract"]),
        ("check-lint-tool", ["check-lint-tool"]),
        ("swiftlint-fetch", ["swiftlint-fetch", RealSwiftLint.version]),
    ]
    private static let clearingLine = "while IFS= read -r FUNCTION; do unset -f \"$FUNCTION\"; done < <(compgen -A function)"

    func test_anExportedShasum_isNeverRunByAnyCommandThatSourcesTheHelper() throws {
        for command in Self.commands {
            let sut = try makeSUT()

            let result = try sut.fixture.capture(sut.devkit.path, command.arguments, in: sut.repository, environment: sut.environment)

            XCTAssertEqual(result.status, 0, "'\(command.name)' works on a clean scratch repository: \(result.standardError)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: sut.marker.path), "'\(command.name)' ran a shasum function from the caller's environment")
        }
    }

    func test_exportedShasum_isRunByACopyOfEachScriptWithoutTheClearingLine() throws {
        for command in Self.commands {
            let sut = try makeSUT()
            let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
            try FileManager.default.copyItem(at: sut.resources, to: moved)
            let script = moved.appendingPathComponent("Scripts/\(command.name).sh")
            let original = try String(contentsOf: script, encoding: .utf8)
            let changed = original.replacingOccurrences(of: Self.clearingLine, with: ":")
            XCTAssertNotEqual(changed, original, "'\(command.name).sh' has the clearing line that this control removes")
            try changed.write(to: script, atomically: true, encoding: .utf8)
            var environment = sut.environment
            environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(sut.repository)
            environment["DEVKIT_RESOURCES"] = moved.path
            environment["DEVKIT_CONF"] = EndToEndFixture.realPath(sut.repository) + "/devkit.conf"

            _ = try sut.fixture.capture("/bin/bash", [script.path] + Array(command.arguments.dropFirst()), in: sut.repository, environment: environment)

            XCTAssertTrue(FileManager.default.fileExists(atPath: sut.marker.path), "positive control: without the line '\(command.name)' does run the caller's shasum, so the test above can fail")
        }
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL
        let environment: [String: String]
        var marker: URL { fixture.directory.appendingPathComponent("shasum.ran") }
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = try fixture.makeRepository()
        var files = LintContractEndToEndTests.files
        files["Sources/A.swift"] = "let value = 1\n"
        for (path, text) in files {
            let url = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try LintContractEndToEndTests.config.write(to: repository.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        try LintContractEndToEndTests.conf().write(to: repository.appendingPathComponent("devkit.conf"), atomically: true, encoding: .utf8)
        try RealSwiftLint.seed(into: repository)
        let marker = directory.appendingPathComponent("shasum.ran")
        // The function records that it ran and then calls the real tool, so a run that does use it still succeeds.
        let environment = fixture.shimmedEnvironment(adding: ["BASH_FUNC_shasum%%": "() { echo ran >> '\(marker.path)'; /usr/bin/shasum \"$@\"; }"])
        return SUT(
            fixture: fixture,
            repository: repository,
            devkit: EndToEndFixture.devkitURL(for: Self.self),
            resources: EndToEndFixture.resourceFolder(for: Self.self),
            environment: environment
        )
    }
}
