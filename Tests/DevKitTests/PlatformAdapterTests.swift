import XCTest
import Foundation
import DevKitCore

final class GitRepositoryLocatorTests: XCTestCase {
    func test_topLevel_ofASubfolderIsTheRepositoryRoot() throws {
        let (sut, directory) = try makeSUT()
        try run("git", ["init", "-q", directory.path])
        let sub = directory.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let root = try sut.topLevel(of: sub)

        XCTAssertEqual(root.path, realPath(directory), "git reports the real path of the top level, not the subfolder")
    }

    func test_topLevel_outsideARepositoryThrowsNotInRepository() throws {
        let (sut, directory) = try makeSUT()

        XCTAssertThrowsError(try sut.topLevel(of: directory), "a plain folder has no top level") { error in
            XCTAssertEqual(error as? DevKitError, .notInRepository(directory: directory.path), "the error names the directory")
        }
    }

    // MARK: - Helpers

    private func makeSUT() throws -> (GitRepositoryLocator, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (GitRepositoryLocator(), directory)
    }

    /// `resolvingSymlinksInPath` keeps `/var` for `/private/var`; git reports the real path.
    private func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) \(arguments) ran")
    }
}

final class FileManagerDirectoryInspectorTests: XCTestCase {
    func test_isDirectory_isTrueOnlyForAnExistingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil), "the file exists")
        let sut = FileManagerDirectoryInspector()

        XCTAssertTrue(sut.isDirectory(at: directory), "an existing directory")
        XCTAssertFalse(sut.isDirectory(at: file), "a file is not a directory")
        XCTAssertFalse(sut.isDirectory(at: directory.appendingPathComponent("missing")), "a missing path is not a directory")
    }
}

final class FileHandleOutputTests: XCTestCase {
    func test_writeOutAndWriteError_gotoTheirOwnStreams() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("out")
        let errURL = directory.appendingPathComponent("err")
        for url in [outURL, errURL] {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil), "the capture file exists")
        }
        let sut = FileHandleOutput(standardOutput: try FileHandle(forWritingTo: outURL), standardError: try FileHandle(forWritingTo: errURL))

        sut.writeOut("result\n")
        sut.writeError("problem\n")

        XCTAssertEqual(try String(contentsOf: outURL, encoding: .utf8), "result\n", "standard output got the result only")
        XCTAssertEqual(try String(contentsOf: errURL, encoding: .utf8), "problem\n", "standard error got the problem only")
    }
}
