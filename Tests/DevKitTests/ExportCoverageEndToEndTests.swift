import XCTest
import Foundation

/// `export-coverage` runs against an `xcrun` shim that answers the two `xccov view` calls from canned JSON, so no result bundle
/// is needed.
final class ExportCoverageEndToEndTests: XCTestCase {
    static let expectedLcov = "TN:\nSF:Sources/Lib/A.swift\nDA:2,0\nDA:3,9\nLF:2\nLH:1\nend_of_record\n"

    func test_export_writesTheLcovOfTheLibraryFilesOnly() throws {
        let sut = try makeSUT()

        let result = try sut.run(["Fake.xcresult", "Lib", sut.output.path])

        XCTAssertEqual(result.status, 0, "the export succeeds: \(result.standardError)")
        XCTAssertEqual(try String(contentsOf: sut.output, encoding: .utf8), Self.expectedLcov,
            "uncovered lines kept, duplicate lines merged by the larger count, tests and other targets left out")
        XCTAssertEqual(result.standardOutput, "export-coverage: wrote \(sut.output.path) (1 files)\n", "one summary line")
    }

    func test_export_fromASubfolder_usesTheRepositoryRootAsTheSourceRoot() throws {
        let sut = try makeSUT()
        let folder = sut.repository.appendingPathComponent("Sources/Lib", isDirectory: true)

        let result = try sut.fixture.capture(sut.devkit.path, ["export-coverage", "Fake.xcresult", "Lib", sut.output.path],
            in: folder, environment: sut.fixture.shimmedEnvironment())

        XCTAssertEqual(result.status, 0, "the root is the git top level: \(result.standardError)")
        XCTAssertEqual(try String(contentsOf: sut.output, encoding: .utf8), Self.expectedLcov,
            "paths are relative to the repository, not to the folder")
    }

    func test_export_ofATargetThatIsNotInTheReport_isStatusOneAndWritesNothing() throws {
        let sut = try makeSUT()

        let result = try sut.run(["Fake.xcresult", "Other", sut.output.path])

        XCTAssertEqual(result.status, 1, "an empty report is not coverage")
        XCTAssertTrue(result.standardError.contains("export-coverage: No executable library files found for Other"),
            "the target is named: \(result.standardError)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.output.path), "no file is written")
    }

    func test_export_whenXccovFails_isStatusOneAndWritesNothing() throws {
        let sut = try makeSUT()
        try sut.fixture.writeShim(named: "xcrun", body: "echo 'xccov: no coverage' >&2\nexit 1\n")

        let result = try sut.run(["Fake.xcresult", "Lib", sut.output.path])

        XCTAssertEqual(result.status, 1, "a failing xccov is not treated as coverage")
        XCTAssertTrue(result.standardError.contains("xccov: no coverage"),
            "the failure of xccov is reported: \(result.standardError)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.output.path), "no file is written")
    }

    func test_withoutDevkit_theScriptRefusesToGuessTheRepository() throws {
        let sut = try makeSUT()

        let script = sut.resources.appendingPathComponent("Scripts/export-coverage.py").path

        let result = try sut.fixture.capture(
            "/usr/bin/env",
            ["python3", "-B", script, "Fake.xcresult", "Lib", sut.output.path],
            in: sut.repository
        )

        XCTAssertEqual(result.status, 2, "no DEVKIT_REPO_ROOT, no run")
        XCTAssertTrue(result.standardError.contains("run it as 'devkit export-coverage'"),
            "the message names the command: \(result.standardError)")
    }

    func test_scriptCopiedOutOfAnyRepository_stillExportsTheRepositoryItIsGiven() throws {
        let sut = try makeSUT()
        let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: sut.resources, to: moved)
        var environment = sut.fixture.shimmedEnvironment()
        environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(sut.repository)

        let script = moved.appendingPathComponent("Scripts/export-coverage.py").path

        let result = try sut.fixture.capture(
            "/usr/bin/env",
            ["python3", "-B", script, "Fake.xcresult", "Lib", sut.output.path],
            in: sut.repository,
            environment: environment
        )

        XCTAssertEqual(result.status, 0,
            "a script that looked at its own location would not find the repository: \(result.standardError)")
        XCTAssertEqual(try String(contentsOf: sut.output, encoding: .utf8), Self.expectedLcov, "the repository it was given")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL
        var output: URL { fixture.directory.appendingPathComponent("out/lcov.info") }

        func run(_ arguments: [String]) throws -> Captured {
            try fixture.capture(devkit.path, ["export-coverage"] + arguments, in: repository,
                environment: fixture.shimmedEnvironment())
        }
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = try fixture.makeRepository()
        let root = EndToEndFixture.realPath(repository)
        for path in ["Sources/Lib/A.swift", "Sources/LibExtra/B.swift", "Tests/T.swift"] {
            let url = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "let x = 1\n".write(to: url, atomically: true, encoding: .utf8)
        }
        let report = """
        {"targets":[
          {"name":"Lib.framework","files":[
            {"path":"\(root)/Sources/Lib/A.swift","executableLines":2},
            {"path":"\(root)/Sources/LibExtra/B.swift","executableLines":1},
            {"path":"\(root)/Tests/T.swift","executableLines":1}]},
          {"name":"LibTests","files":[{"path":"\(root)/Sources/Lib/Injected.swift","executableLines":1}]}]}
        """
        let archive = """
        {"image":[
          {"line":1,"isExecutable":false},
          {"line":2,"isExecutable":true,"executionCount":0},
          {"line":3,"isExecutable":true,"executionCount":0},
          {"line":3,"isExecutable":true,"executionCount":9}]}
        """
        try report.write(to: directory.appendingPathComponent("report.json"), atomically: true, encoding: .utf8)
        try archive.write(to: directory.appendingPathComponent("archive.json"), atomically: true, encoding: .utf8)
        try fixture.writeShim(named: "xcrun", body: """
        case "$*" in
            *--archive*) cat '\(directory.path)/archive.json' ;;
            *--report*) cat '\(directory.path)/report.json' ;;
            *) exit 1 ;;
        esac

        """)
        return SUT(fixture: fixture, repository: repository, devkit: EndToEndFixture.devkitURL(for: Self.self),
            resources: EndToEndFixture.resourceFolder(for: Self.self))
    }
}

/// The check of the exporter that the libraries kept next to it (`Tests/Python/test-export-coverage.py`) runs here, against the
/// exporter of the resource folder; each mutant of the exporter must turn it red.
final class ExportCoverageCheckTests: XCTestCase {
    func test_theCheckOfTheExporter_passes() throws {
        let sut = try makeSUT()

        let result = try sut.runCheck(exporter: sut.exporter)

        XCTAssertEqual(result.status, 0, "the six checks hold: \(result.standardError.suffix(400))")
        XCTAssertTrue(result.standardError.contains("Ran 6 tests"), "all six ran: \(result.standardError.suffix(200))")
    }

    func test_keepingTheSmallerCountOfADuplicateLine_failsTheCheck() throws {
        try assertCheckFails("lines[line] = max(lines.get(line, 0), count)", "lines[line] = min(lines.get(line, 0), count)",
            failing: "test_preserves_uncovered_lines_and_merges_duplicate_image_lines")
    }

    func test_acceptingANegativeCount_failsTheCheck() throws {
        try assertCheckFails("if line <= 0 or count < 0:", "if line <= 0:", failing: "test_invalid_counts_fail")
    }

    func test_keepingFilesOutsideTheSourceRoot_failsTheCheck() throws {
        try assertCheckFails("if source_root in path.parents and file", "if file",
            failing: "test_filters_tests_dependencies_and_other_targets")
    }

    func test_acceptingAFileWithoutArchiveLines_failsTheCheck() throws {
        try assertCheckFails("        if not lines:\n", "        if False:\n", failing: "test_missing_archive_lines_fails")
    }

    func test_exportingAnotherTargetOfTheReport_failsTheCheck() throws {
        try assertCheckFails("if entry[\"name\"].split(\".\")[0] != target:", "if False:",
            failing: "test_filters_tests_dependencies_and_other_targets")
    }

    func test_acceptingAnEmptyReport_failsTheCheck() throws {
        try assertCheckFails("    if not paths:\n", "    if False:\n",
            failing: "test_missing_target_fails_instead_of_producing_empty_report")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let exporter: URL
        let check: URL

        func runCheck(exporter: URL) throws -> Captured {
            var environment = EndToEndFixture.cleanEnvironment
            environment["EXPORT_COVERAGE_SCRIPT"] = exporter.path
            return try fixture.capture("/usr/bin/env", ["python3", "-B", check.path], environment: environment)
        }
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let exporter = EndToEndFixture.resourceFolder(for: Self.self).appendingPathComponent("Scripts/export-coverage.py")
        return SUT(fixture: fixture, exporter: exporter,
            check: root.appendingPathComponent("Tests/Python/test-export-coverage.py"))
    }

    private func assertCheckFails(
        _ old: String,
        _ new: String,
        failing: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let sut = try makeSUT()
        let original = try String(contentsOf: sut.exporter, encoding: .utf8)
        guard original.components(separatedBy: old).count - 1 == 1 else {
            XCTFail("the text to mutate is in the exporter exactly once", file: file, line: line)
            return
        }
        let mutant = sut.fixture.directory.appendingPathComponent("export-coverage.py")
        try original.replacingOccurrences(of: old, with: new).write(to: mutant, atomically: true, encoding: .utf8)

        let result = try sut.runCheck(exporter: mutant)

        XCTAssertNotEqual(result.status, 0, "the check of the mutated exporter fails", file: file, line: line)
        XCTAssertTrue(result.standardError.contains("FAIL: \(failing)") || result.standardError.contains("ERROR: \(failing)"),
            "the check that names this behaviour is the one that fails: " +
            "\(result.standardError.suffix(400))", file: file, line: line)
    }
}
