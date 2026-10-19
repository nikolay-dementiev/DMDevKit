import XCTest
import Foundation

final class SwiftLintHelperEndToEndTests: XCTestCase {
    func test_fetch_unpacksTheToolFromTheArchiveAndPrintsItsPath() throws {
        let sut = try makeSUT()
        try RealSwiftLint.seed(into: sut.repository)

        let result = try sut.run(["swiftlint-fetch", RealSwiftLint.version])

        let tool = EndToEndFixture.realPath(sut.repository) + "/.build/tools/swiftlint-\(RealSwiftLint.version)/swiftlint"
        XCTAssertEqual(result.status, 0, "the archive is in the table and its checksum holds: \(result.standardError)")
        XCTAssertEqual(result.standardOutput, tool + "\n", "standard output is the path of the tool and nothing else")
        let version = try sut.fixture.capture(tool, ["version"])
        XCTAssertEqual(version.standardOutput, RealSwiftLint.version + "\n", "the unpacked tool is the pinned SwiftLint")
    }

    func test_fetch_ofAVersionNotInTheTableIsStatusTwoAndNeverDownloads() throws {
        let sut = try makeSUT()

        let result = try sut.run(["swiftlint-fetch", "0.65.0"])

        XCTAssertEqual(result.status, 2, "a version without a checksum is a configuration error")
        XCTAssertTrue(result.standardError.contains("no checksum for SwiftLint 0.65.0"), "the message names the version")
        XCTAssertTrue(result.standardError.contains("update DMDevKit"), "the message says what to do")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.curlLog.path), "nothing was downloaded")
    }

    func test_fetch_removesAnArchiveWithAWrongChecksumAndNeverUnpacksIt() throws {
        let sut = try makeSUT()
        let folder = sut.repository.appendingPathComponent(".build/tools/swiftlint-\(RealSwiftLint.version)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not the archive".utf8).write(to: folder.appendingPathComponent("portable_swiftlint.zip"))

        let result = try sut.run(["swiftlint-fetch", RealSwiftLint.version])

        XCTAssertEqual(result.status, 2, "a wrong archive is status 2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("portable_swiftlint.zip").path), "the archive was removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.unzipLog.path), "it never reached the unpack")
    }

    func test_fetch_cannotBeWeakenedByAFunctionInTheCallersEnvironment() throws {
        let sut = try makeSUT()
        let folder = sut.repository.appendingPathComponent(".build/tools/swiftlint-\(RealSwiftLint.version)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tampered = folder.appendingPathComponent("portable_swiftlint.zip")
        try Data("not the archive".utf8).write(to: tampered)
        let checksum = try sut.fixture.capture("/bin/bash", ["-c", "shasum -a 256 '\(tampered.path)' | cut -d ' ' -f 1"]).standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Bash imports a function from a variable of this name; the helper must define its own table over it.
        let result = try sut.run(["swiftlint-fetch", RealSwiftLint.version], adding: ["BASH_FUNC_swiftlint_checksum%%": "() { echo \(checksum); }"])

        XCTAssertEqual(result.status, 2, "the checksum of the table wins over the caller's function")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.unzipLog.path), "the tampered archive never reached the unpack")
    }

    func test_fetch_withoutAnArchiveDownloadsTheReleaseOverHttpsWithTheShim() throws {
        let sut = try makeSUT()
        let real = try RealSwiftLint.archive()

        let result = try sut.run(["swiftlint-fetch", RealSwiftLint.version], shimmedCurlDelivering: real)

        XCTAssertEqual(result.status, 0, "the downloaded archive passes the checksum: \(result.standardError)")
        let call = try String(contentsOf: sut.curlLog, encoding: .utf8)
        XCTAssertTrue(
            call.contains("https://github.com/realm/SwiftLint/releases/download/\(RealSwiftLint.version)/portable_swiftlint.zip"),
            "the release of that version: \(call)"
        )
        XCTAssertTrue(call.contains("--proto =https"), "https only: \(call)")
    }

    func test_fetch_needsExactlyOneVersion() throws {
        let sut = try makeSUT()

        XCTAssertEqual(try sut.run(["swiftlint-fetch"]).status, 2, "no version")
        XCTAssertEqual(try sut.run(["swiftlint-fetch", "1.0"]).status, 2, "not three groups of digits")
        XCTAssertEqual(try sut.run(["swiftlint-fetch", "0.65.1", "extra"]).status, 2, "a second argument")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        var curlLog: URL { fixture.directory.appendingPathComponent("curl.log") }
        var unzipLog: URL { fixture.directory.appendingPathComponent("unzip.log") }

        func run(_ arguments: [String], adding: [String: String] = [:], shimmedCurlDelivering archive: URL? = nil) throws -> Captured {
            try fixture.writeShim(named: "curl", body: """
            echo "$*" >> '\(curlLog.path)'
            \(archive.map { "while [ $# -gt 0 ]; do case \"$1\" in --output) out=\"$2\" ;; esac; shift; done; cp '\($0.path)' \"$out\"" } ?? "exit 22")
            """)
            try fixture.writeShim(named: "unzip", body: "echo \"$*\" >> '\(unzipLog.path)'\nexec /usr/bin/unzip \"$@\"\n")
            return try fixture.capture(devkit.path, arguments, in: repository, environment: fixture.shimmedEnvironment(adding: adding))
        }
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let devkit = EndToEndFixture.devkitURL(for: Self.self)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: devkit.path), "the built devkit is at \(devkit.path)")
        return SUT(fixture: fixture, repository: try fixture.makeRepository(), devkit: devkit)
    }
}
