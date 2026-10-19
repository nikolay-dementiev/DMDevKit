import XCTest
import Foundation

/// Every command that sources the SwiftLint helper clears the shell functions it inherits before anything runs, so that a
/// function in the caller's environment cannot stand in for `shasum` or another tool the checksum check relies on.
final class FunctionClearingEndToEndTests: XCTestCase {
    /// `tool` is a program the command surely runs: the function of that name must never run.
    private struct Command {
        let name: String
        let arguments: [String]
        let tool: String

        init(_ name: String, _ arguments: [String], _ tool: String) {
            self.name = name
            self.arguments = arguments
            self.tool = tool
        }
    }

    private static let commands: [Command] = [
        Command("lint", ["lint"], "shasum"),
        Command("check-lint-contract", ["check-lint-contract"], "shasum"),
        Command("check-lint-tool", ["check-lint-tool"], "shasum"),
        Command("swiftlint-fetch", ["swiftlint-fetch", RealSwiftLint.version], "shasum"),
        Command("check-api", ["check-api", "--self-test"], "git"),
        Command("check-release", ["check-release", "--notes", "1.1.0"], "awk")
    ]
    private static let clearingLine = "while IFS= read -r FUNCTION; do unset -f \"$FUNCTION\"; done < <(compgen -A function)"

    func test_anExportedFunctionOfATool_isNeverRunByAnyCommandThatNeedsOne() throws {
        for command in Self.commands {
            let sut = try makeSUT(tool: command.tool)

            let result = try sut.fixture.capture(sut.devkit.path, command.arguments, in: sut.repository,
                environment: sut.environment)

            XCTAssertEqual(result.status, 0, "'\(command.name)' works on a clean scratch repository: \(result.standardError)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: sut.marker.path),
                "'\(command.name)' ran a \(command.tool) function from the caller's environment")
        }
    }

    func test_exportedFunctionOfATool_isRunByACopyOfEachScriptWithoutTheClearingLine() throws {
        for command in Self.commands {
            let sut = try makeSUT(tool: command.tool)
            let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
            try FileManager.default.copyItem(at: sut.resources, to: moved)
            let script = moved.appendingPathComponent("Scripts/\(command.name).sh")
            let original = try String(contentsOf: script, encoding: .utf8)
            let changed = original.replacingOccurrences(of: Self.clearingLine, with: ":")
            XCTAssertNotEqual(changed, original, "'\(command.name).sh' has the clearing line that this control removes")
            try changed.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            var environment = sut.environment
            environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(sut.repository)
            environment["DEVKIT_RESOURCES"] = moved.path
            environment["DEVKIT_CONF"] = EndToEndFixture.realPath(sut.repository) + "/devkit.conf"
            environment["DEVKIT_WORK"] = EndToEndFixture.realPath(sut.repository) + "/.build/devkit"

            _ = try sut.fixture.capture("/bin/bash", [script.path] + Array(command.arguments.dropFirst()), in: sut.repository,
                environment: environment)

            XCTAssertTrue(FileManager.default.fileExists(atPath: sut.marker.path),
                "positive control: without the line '\(command.name)' does run the caller's \(command.tool), so the test above " +
                "can fail")
        }
    }

    /// The clearing line asks `compgen` for the functions to remove, so an exported `compgen` that lists none defeats it. The
    /// launcher does not hand exported functions to the scripts at all; this is why it matters.
    func test_exportedCompgenFunction_doesNotLetAToolFunctionRunThroughDevkit() throws {
        for command in Self.commands {
            let sut = try makeSUT(tool: command.tool, alsoFunctions: ["compgen": "() { :; }"])

            _ = try sut.fixture.capture(sut.devkit.path, command.arguments, in: sut.repository, environment: sut.environment)

            XCTAssertFalse(FileManager.default.fileExists(atPath: sut.marker.path),
                "'\(command.name)' ran a \(command.tool) function although the caller exported a compgen that lists none")
        }
    }

    func test_exportedCompgenFunction_defeatsTheClearingLineOfAScriptThatDevkitDidNotStart() throws {
        let sut = try makeSUT(tool: "shasum", alsoFunctions: ["compgen": "() { :; }"])
        var environment = sut.environment
        let root = EndToEndFixture.realPath(sut.repository)
        environment["DEVKIT_REPO_ROOT"] = root
        environment["DEVKIT_RESOURCES"] = sut.resources.path
        environment["DEVKIT_CONF"] = root + "/devkit.conf"
        environment["DEVKIT_WORK"] = root + "/.build/devkit"

        _ = try sut.fixture.capture("/bin/bash", [sut.resources.appendingPathComponent("Scripts/check-lint-tool.sh").path],
            in: sut.repository, environment: environment)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sut.marker.path),
            "positive control: started by hand, the script runs the caller's shasum, so the test above can fail")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL
        let environment: [String: String]
        var marker: URL { fixture.directory.appendingPathComponent("tool.ran") }
    }

    private func makeSUT(tool: String, alsoFunctions: [String: String] = [:]) throws -> SUT {
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
        try "## [1.1.0] - 2026-10-03\n\n- a change\n".write(to: repository.appendingPathComponent("CHANGELOG.md"),
            atomically: true, encoding: .utf8)
        try LintContractEndToEndTests.config.write(to: repository.appendingPathComponent(".swiftlint.yml"), atomically: true,
            encoding: .utf8)
        try LintContractEndToEndTests.conf().write(to: repository.appendingPathComponent("devkit.conf"), atomically: true,
            encoding: .utf8)
        try RealSwiftLint.seed(into: repository)
        let marker = directory.appendingPathComponent("tool.ran")
        // The function records that it ran and then calls the real tool, so a run that does use it still succeeds.
        var exported = ["BASH_FUNC_\(tool)%%": "() { echo ran >> '\(marker.path)'; /usr/bin/\(tool) \"$@\"; }"]
        for (name, body) in alsoFunctions { exported["BASH_FUNC_\(name)%%"] = body }
        let environment = fixture.shimmedEnvironment(adding: exported)
        return SUT(
            fixture: fixture,
            repository: repository,
            devkit: EndToEndFixture.devkitURL(for: Self.self),
            resources: EndToEndFixture.resourceFolder(for: Self.self),
            environment: environment
        )
    }
}
