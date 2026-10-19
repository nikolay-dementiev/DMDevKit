import XCTest
import CryptoKit
import Foundation

struct Captured: Equatable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

/// Runs the built `devkit` and scripts in scratch folders, with captured streams.
final class EndToEndFixture {
    let directory: URL
    let shimDirectory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-e2e-\(UUID().uuidString)", isDirectory: true)
        shimDirectory = directory.appendingPathComponent("shims", isDirectory: true)
        try FileManager.default.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
    }

    /// The built binary: SwiftPM puts the executable next to the test bundle.
    static func devkitURL(for testCase: AnyClass) -> URL {
        Bundle(for: testCase).bundleURL.deletingLastPathComponent().appendingPathComponent("devkit")
    }

    /// The copy of the scripts the binary runs.
    static func resourceFolder(for testCase: AnyClass) -> URL {
        Bundle(for: testCase).bundleURL.deletingLastPathComponent().appendingPathComponent("DMDevKit_devkit.bundle/Resources", isDirectory: true)
    }

    func makeRepository(named name: String = "repo") throws -> URL {
        let repository = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try capture("/usr/bin/env", ["git", "init", "-q", repository.path])
        return repository
    }

    func writeShim(named name: String, body: String) throws {
        let url = shimDirectory.appendingPathComponent(name)
        try ("#!/bin/bash\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Environment with the shim folder first on the PATH.
    func shimmedEnvironment(adding extra: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = shimDirectory.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        return environment.merging(extra) { _, added in added }
    }

    func capture(_ executable: String, _ arguments: [String], in workingDirectory: URL? = nil, environment: [String: String]? = nil) throws -> Captured {
        let outputURL = directory.appendingPathComponent("out-\(UUID().uuidString)")
        let errorURL = directory.appendingPathComponent("err-\(UUID().uuidString)")
        for url in [outputURL, errorURL] { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = try FileHandle(forWritingTo: outputURL)
        process.standardError = try FileHandle(forWritingTo: errorURL)
        try process.run()
        process.waitUntilExit()
        return Captured(
            status: process.terminationStatus,
            standardOutput: try String(contentsOf: outputURL, encoding: .utf8),
            standardError: try String(contentsOf: errorURL, encoding: .utf8)
        )
    }

    /// The real path, the way git prints it (`/var` is `/private/var`).
    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The object id git gives a file: SHA-1 of `blob <size>\0` and the bytes.
    static func gitBlobHash(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// The real SwiftLint archive that the tests unpack through the helper, so that its checksum is checked in every test.
enum RealSwiftLint {
    static let version = "0.65.1"
    static let fetchCommand = "swift run devkit swiftlint-fetch \(version)"

    /// DMDevKit's own copy, put there by the helper (`swiftlint-fetch`). Absent: the test fails and names the command.
    static func archive(file: StaticString = #filePath) throws -> URL {
        let root = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let archive = root.appendingPathComponent(".build/tools/swiftlint-\(version)/portable_swiftlint.zip")
        guard FileManager.default.fileExists(atPath: archive.path) else {
            XCTFail("SwiftLint \(version) is not in \(archive.path); fetch it with: \(fetchCommand)")
            throw CocoaError(.fileNoSuchFile)
        }
        return archive
    }

    /// Copies the archive into `<repository>/.build/tools/swiftlint-<version>/`; the helper checks it and unpacks the tool.
    static func seed(into repository: URL) throws {
        let folder = repository.appendingPathComponent(".build/tools/swiftlint-\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try archive(), to: folder.appendingPathComponent("portable_swiftlint.zip"))
    }
}
