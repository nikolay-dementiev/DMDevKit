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
            guard case DevKitError.notInRepository(let named, let gitMessage) = error else {
                return XCTFail("expected notInRepository, got \(error)")
            }
            XCTAssertEqual(named, directory.path, "the error names the directory")
            XCTAssertEqual(gitMessage?.isEmpty, false,
                "and keeps what git said, whatever language it said it in: \(String(describing: gitMessage))")
        }
    }

    func test_topLevel_whenGitRefusesWithAReason_keepsTheFirstLineGitWrote() throws {
        let (_, directory) = try makeSUT()
        let sut = try fakeGit(in: directory,
            body: "printf '\\n  \\nfatal: detected dubious ownership\\nhint: second line\\n' >&2\nexit 128\n")

        XCTAssertThrowsError(try sut.topLevel(of: directory), "git refused") { error in
            XCTAssertEqual(error as? DevKitError,
                .notInRepository(directory: directory.path, gitMessage: "fatal: detected dubious ownership"),
                "the first line that is not blank, and only that one")
        }
    }

    func test_topLevel_whenGitWritesNothingOnStandardError_hasNoGitMessage() throws {
        let (_, directory) = try makeSUT()
        let sut = try fakeGit(in: directory, body: "exit 128\n")

        XCTAssertThrowsError(try sut.topLevel(of: directory), "git refused without a word") { error in
            XCTAssertEqual(error as? DevKitError, .notInRepository(directory: directory.path, gitMessage: nil),
                "nothing to quote")
        }
    }

    func test_topLevel_afterAnAnswerOrARefusal_leavesNothingInTheScratchFolder() throws {
        let (_, directory) = try makeSUT()
        let scratch = directory.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let refusing = try fakeGit(in: directory, body: "echo 'fatal: no' >&2\nexit 128\n", scratch: scratch)
        let answering = try fakeGit(in: directory,
            body: "echo 'noise' >&2\nprintf '%s\\n' '\(directory.path)'\n", scratch: scratch)

        XCTAssertThrowsError(try refusing.topLevel(of: directory), "git refused")
        _ = try answering.topLevel(of: directory)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [],
            "the file that held git's standard error is removed, in both cases")
    }

    func test_topLevel_whenGitWritesALongLine_cutsTheMessage() throws {
        let (_, directory) = try makeSUT()
        let sut = try fakeGit(in: directory, body: "head -c 1000 /dev/zero | tr '\\0' y >&2\nexit 128\n")

        XCTAssertThrowsError(try sut.topLevel(of: directory), "git refused") { error in
            guard case DevKitError.notInRepository(_, let gitMessage) = error else {
                return XCTFail("expected notInRepository, got \(error)")
            }
            XCTAssertEqual(gitMessage?.count, 300, "a message carries at most 300 characters of git's line")
        }
    }

    func test_topLevel_whenGitWritesControlCharacters_theMessageHasNone() throws {
        let (_, directory) = try makeSUT()
        let sut = try fakeGit(in: directory, body: "printf 'fatal: \\033[31mred\\033[0m\\tbell\\007 end\\n' >&2\nexit 128\n")

        XCTAssertThrowsError(try sut.topLevel(of: directory), "git refused") { error in
            guard case DevKitError.notInRepository(_, let gitMessage) = error else {
                return XCTFail("expected notInRepository, got \(error)")
            }
            let hasControl = gitMessage?.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            XCTAssertEqual(hasControl, false,
                "no escape or control character reaches the terminal: \(String(describing: gitMessage))")
            XCTAssertTrue(gitMessage?.contains("fatal:") == true && gitMessage?.contains("end") == true,
                "the words stay: \(String(describing: gitMessage))")
        }
    }

    func test_missingGit_isCannotStartNotNotInRepository() throws {
        let (_, directory) = try makeSUT()
        let sut = GitRepositoryLocator(command: ["/usr/bin/env", "devkit-no-such-git-tool"])

        XCTAssertThrowsError(try sut.topLevel(of: directory), "a missing tool is not a missing repository") { error in
            guard case DevKitError.cannotStart(let executable, _) = error else {
                return XCTFail("expected cannotStart, got \(error)")
            }
            XCTAssertEqual(executable, "devkit-no-such-git-tool", "the error names the tool that is missing")
        }
    }

    func test_topLevel_whenGitPrintsBytesThatAreNoUtf8_throwsNotInRepository() throws {
        let (_, directory) = try makeSUT()
        let script = directory.appendingPathComponent("fake-git.sh")
        try "printf '/tmp/\\377\\376\\n'\n".write(to: script, atomically: true, encoding: .utf8)
        let sut = GitRepositoryLocator(command: ["/bin/bash", script.path])

        XCTAssertThrowsError(try sut.topLevel(of: directory), "a path that cannot be read is not a path") { error in
            XCTAssertEqual(error as? DevKitError, .notInRepository(directory: directory.path, gitMessage: nil),
                "the error names the directory, and git said nothing")
        }
    }

    func test_gitEnvironmentOfTheCaller_doesNotRedirectTheLookup() throws {
        let (sut, first) = try makeSUT()
        let (_, second) = try makeSUT()
        try run("git", ["init", "-q", first.path])
        try run("git", ["init", "-q", second.path])
        setenv("GIT_DIR", second.appendingPathComponent(".git").path, 1)
        setenv("GIT_WORK_TREE", second.path, 1)
        addTeardownBlock {
            unsetenv("GIT_DIR")
            unsetenv("GIT_WORK_TREE")
        }

        let root = try sut.topLevel(of: first)

        XCTAssertEqual(root.path, realPath(first), "the repository of the working directory, not the one GIT_DIR names")
    }

    // MARK: - Helpers

    /// A locator whose git is a script with the given body, kept in `directory`.
    private func fakeGit(in directory: URL, body: String, scratch: URL? = nil) throws -> GitRepositoryLocator {
        let script = directory.appendingPathComponent("fake-git-\(UUID().uuidString).sh")
        try body.write(to: script, atomically: true, encoding: .utf8)
        guard let scratch else { return GitRepositoryLocator(command: ["/bin/bash", script.path]) }
        return GitRepositoryLocator(command: ["/bin/bash", script.path], scratchDirectory: scratch)
    }

    private func makeSUT() throws -> (GitRepositoryLocator, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-git-\(UUID().uuidString)",
            isDirectory: true)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-dir-\(UUID().uuidString)",
            isDirectory: true)
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
    func test_writeToAClosedHandle_doesNotCrashTheHost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-closed-\(UUID().uuidString)",
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("closed")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil), "the file exists")
        let handle = try FileHandle(forWritingTo: url)
        try handle.close()
        let sut = FileHandleOutput(standardOutput: handle, standardError: handle)

        sut.writeOut("lost\n")
        sut.writeError("lost\n")

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "", "nothing was written, and nothing raised an exception")
    }

    func test_writeOutAndWriteError_gotoTheirOwnStreams() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devkit-out-\(UUID().uuidString)",
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("out")
        let errURL = directory.appendingPathComponent("err")
        for url in [outURL, errURL] {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil), "the capture file exists")
        }
        let sut = FileHandleOutput(standardOutput: try FileHandle(forWritingTo: outURL),
            standardError: try FileHandle(forWritingTo: errURL))

        sut.writeOut("result\n")
        sut.writeError("problem\n")

        XCTAssertEqual(try String(contentsOf: outURL, encoding: .utf8), "result\n", "standard output got the result only")
        XCTAssertEqual(try String(contentsOf: errURL, encoding: .utf8), "problem\n", "standard error got the problem only")
    }
}
