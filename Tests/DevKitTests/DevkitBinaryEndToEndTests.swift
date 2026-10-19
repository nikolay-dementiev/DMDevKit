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
        XCTAssertEqual(result.standardOutput, "0.0.0-development\n", "the version of a development build")
    }

    func test_pathAsCommand_isRejected() throws {
        let sut = try makeSUT()
        let script = EndToEndFixture.resourceFolder(for: Self.self).appendingPathComponent("Scripts/prepare-simulator.sh")

        for name in [script.path, "Scripts/prepare-simulator.sh", "../prepare-simulator"] {
            let result = try sut.fixture.capture(sut.devkit.path, [name], in: sut.repository)

            XCTAssertEqual(result.status, 2, "'\(name)' is not a command")
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

        _ = try sut.fixture.capture(sut.devkit.path, ["prepare-simulator", "iPhone 15", "17.5"], in: sub, environment: sut.fixture.shimmedEnvironment())

        let root = EndToEndFixture.realPath(sut.repository)
        let lines = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, root, "the git top level, not the subfolder")
        XCTAssertEqual(lines.dropFirst().first.map { URL(fileURLWithPath: $0).standardized.path }, EndToEndFixture.resourceFolder(for: Self.self).standardized.path, "the resource folder of the binary")
        XCTAssertEqual(lines.dropFirst(2).first, root + "/devkit.conf", "the configuration file is at the root")
        XCTAssertEqual(lines.dropFirst(3).first, root + "/.build/devkit", "the work folder is under the build folder")
    }

    func test_outsideARepository_exitsTwoAndNamesTheDirectory() throws {
        let sut = try makeSUT()
        let plain = sut.fixture.directory.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        let result = try sut.fixture.capture(sut.devkit.path, ["prepare-simulator", "iPhone 15", "17.5"], in: plain)

        XCTAssertEqual(result.status, 2, "no repository, no command")
        XCTAssertTrue(result.standardError.contains("is not inside a git repository"), "the message says what is wrong")
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
        return SUT(fixture: fixture, repository: try fixture.makeRepository(), devkit: EndToEndFixture.devkitURL(for: Self.self))
    }
}
