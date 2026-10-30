import XCTest
import Foundation

final class DevkitBinaryEndToEndTests: XCTestCase {
    func test_help_listsPrepareSimulatorOnStandardOutput() throws {
        let sut = try makeSUT()

        let result = try sut.fixture.capture(sut.devkit.path, ["--help"], in: sut.repository)

        XCTAssertEqual(result.status, 0, "--help is not an error")
        XCTAssertTrue(result.standardOutput.contains("prepare-simulator"), "the command is listed")
        XCTAssertEqual(result.standardError, "", "nothing on standard error")
    }

    func test_version_printsOneLine() throws {
        let sut = try makeSUT()

        let result = try sut.fixture.capture(sut.devkit.path, ["--version"], in: sut.repository)

        XCTAssertEqual(result.status, 0, "--version is not an error")
        XCTAssertEqual(result.standardOutput, "0.4.0\n", "the version of the release that has check-wrappers")
    }

    func test_pathAsCommand_isRejected() throws {
        let sut = try makeSUT()
        let script = EndToEndFixture.resourceFolder(for: Self.self).appendingPathComponent("Scripts/prepare-simulator.sh")

        for name in [script.path, "Scripts/prepare-simulator.sh", "../prepare-simulator"] {
            let result = try sut.fixture.capture(sut.devkit.path, [name], in: sut.repository)

            XCTAssertEqual(result.status, 64, "'\(name)' is not a command")
            XCTAssertTrue(result.standardError.contains("unknown command"), "the message says so")
        }
    }

    func test_scriptsGetTheFourPathsOfTheModel_fromASubfolderOfTheRepository() throws {
        let sut = try makeSUT()
        let record = sut.fixture.directory.appendingPathComponent("env-record")
        try sut.fixture.writeShim(named: "xcrun", body: """
        printf '%s\\n' "$DEVKIT_REPO_ROOT" "$DEVKIT_RESOURCES" "$DEVKIT_CONF" "$DEVKIT_WORK" > '\(record.path)'
        exit 64
        """)
        let sub = sut.repository.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        _ = try sut.fixture.capture(sut.devkit.path, ["prepare-simulator", "iPhone 15", "17.5"], in: sub,
            environment: sut.fixture.shimmedEnvironment())

        let root = EndToEndFixture.realPath(sut.repository)
        let lines = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, root, "the git top level, not the subfolder")
        XCTAssertEqual(lines.dropFirst().first.map { URL(fileURLWithPath: $0).standardized.path },
            EndToEndFixture.resourceFolder(for: Self.self).standardized.path, "the resource folder of the binary")
        XCTAssertEqual(lines.dropFirst(2).first, root + "/devkit.conf", "the configuration file is at the root")
        XCTAssertEqual(lines.dropFirst(3).first, root + "/.build/devkit", "the work folder is under the build folder")
    }

    func test_outsideARepository_exitsSixtyFourAndNamesTheDirectory() throws {
        let sut = try makeSUT()
        let plain = sut.fixture.directory.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        let result = try sut.fixture.capture(sut.devkit.path, ["prepare-simulator", "iPhone 15", "17.5"], in: plain)

        XCTAssertEqual(result.status, 64, "no repository, no command (EX_USAGE)")
        XCTAssertTrue(result.standardError.contains("is not inside a git repository"), "the message says what is wrong")
    }

    func test_whenGitSaysWhyItFails_theMessageKeepsGitsOwnLine() throws {
        let sut = try makeSUT()
        let plain = sut.fixture.directory.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try sut.fixture.writeShim(
            named: "git",
            body: "echo \"fatal: detected dubious ownership in repository at '/x'\" >&2\nexit 128\n"
        )

        let result = try sut.fixture.capture(sut.devkit.path, ["check-release"], in: plain,
            environment: sut.fixture.shimmedEnvironment())

        XCTAssertEqual(result.status, 64, "the status of a lookup that failed stays the one of a mistake of the caller")
        XCTAssertTrue(result.standardError.contains("is not inside a git repository"),
            "the old words stay: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("detected dubious ownership in repository at '/x'"),
            "and git's own line is there to read: \(result.standardError)")
    }

    func test_aGitThatWritesAGreatDealToStandardErrorBeforeItAnswers_doesNotHangTheLookup() throws {
        let sut = try makeSUT()
        let root = EndToEndFixture.realPath(sut.repository)
        try sut.fixture.writeShim(
            named: "git",
            body: "head -c 204800 /dev/zero | tr '\\0' x >&2\necho >&2\nprintf '%s\\n' '\(root)'\n"
        )

        let result = try sut.fixture.capture(sut.devkit.path, ["check-release"], in: sut.repository,
            environment: sut.fixture.shimmedEnvironment(), timeout: 30)

        XCTAssertEqual(result.status, 2, "the lookup ended and the command ran: \(result.standardError.suffix(200))")
        XCTAssertTrue(result.standardError.contains("usage: devkit check-release"),
            "check-release answered with its usage line: \(result.standardError.suffix(200))")
    }

    func test_binaryCopiedAwayFromItsResources_reportsTheMissingFolderInsteadOfCrashing() throws {
        let sut = try makeSUT()
        let lonely = sut.fixture.directory.appendingPathComponent("lonely", isDirectory: true)
        try FileManager.default.createDirectory(at: lonely, withIntermediateDirectories: true)
        let copy = lonely.appendingPathComponent("devkit")
        try FileManager.default.copyItem(at: sut.devkit, to: copy)

        let help = try sut.fixture.capture(copy.path, ["--help"], in: sut.repository)
        let command = try sut.fixture.capture(copy.path, ["prepare-simulator", "iPhone 15", "17.5"], in: sut.repository)

        XCTAssertEqual(help.status, 0, "--help needs no resources")
        XCTAssertEqual(command.status, 70, "a command without its scripts is a broken installation (EX_SOFTWARE)")
        XCTAssertTrue(command.standardError.contains("the resource folder"), "the message says what is missing")
        XCTAssertTrue(command.standardError.contains(lonely.path), "the message names where devkit looked")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let devkit = EndToEndFixture.devkitURL(for: Self.self)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: devkit.path),
            "the built devkit is at \(devkit.path); build the product before the tests")
        return SUT(fixture: fixture, repository: try fixture.makeRepository(), devkit: devkit)
    }
}
