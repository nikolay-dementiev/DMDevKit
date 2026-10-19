import XCTest
import Foundation

final class CheckLintToolEndToEndTests: XCTestCase {
    func test_theHelperHoldsItsFourBehaviours_throughDevkit() throws {
        let sut = try makeSUT()

        let result = try sut.run(["check-lint-tool"])

        XCTAssertEqual(result.status, 0, "the four behaviours hold: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.contains("the tool stays whole while another run unpacks"), "behaviour 1a: \(result.standardOutput)")
        XCTAssertTrue(result.standardOutput.contains("the new tool replaces the old one by a rename"), "behaviour 1b: \(result.standardOutput)")
        XCTAssertTrue(result.standardOutput.contains("two first-time runs at once both succeed"), "behaviour 2: \(result.standardOutput)")
        XCTAssertTrue(result.standardOutput.contains("a wrong checksum is removed and never unpacked"), "behaviour 3: \(result.standardOutput)")
        XCTAssertTrue(result.standardOutput.contains("a failed download and a failed unpack leave nothing behind"), "behaviour 4: \(result.standardOutput)")
        XCTAssertTrue(result.standardOutput.hasSuffix("check-lint-tool: the 4 behaviours of swiftlint-tool.sh hold.\n"), "the closing line: \(result.standardOutput)")
    }

    func test_anUnpackThatWritesIntoTheToolInPlace_failsTheCheck() throws {
        let sut = try makeSUT()
        let moved = try sut.movedResources { helper in
            helper.replacingOccurrences(of: "mv -f \"$stage/swiftlint\" \"$tools/swiftlint\"", with: "cp \"$stage/swiftlint\" \"$tools/swiftlint\"")
        }

        let result = try sut.runMoved(moved)

        XCTAssertEqual(result.status, 1, "the old helper that wrote in place does not pass")
        XCTAssertTrue(result.standardError.contains("check-lint-tool: FAIL"), "a failure is named: \(result.standardError)")
    }

    func test_aChecksumThatIsNotCheckedBeforeTheUnpack_failsTheCheck() throws {
        let sut = try makeSUT()
        let moved = try sut.movedResources { helper in
            helper.replacingOccurrences(of: "if [ \"$actual\" != \"$expected\" ]; then", with: "if false; then")
        }

        let result = try sut.runMoved(moved)

        XCTAssertEqual(result.status, 1, "a wrong archive reaching the unpack is behaviour 3")
        XCTAssertTrue(result.standardError.contains("a wrong checksum"), "behaviour 3 is the one named: \(result.standardError)")
    }

    func test_aFailedDownloadThatLeavesItsPartFile_failsTheCheck() throws {
        let sut = try makeSUT()
        let moved = try sut.movedResources { helper in
            helper.replacingOccurrences(of: "            rm -f \"$part\"\n", with: "")
        }

        let result = try sut.runMoved(moved)

        XCTAssertEqual(result.status, 1, "a refused download that leaves files behind is behaviour 4")
        XCTAssertTrue(result.standardError.contains("refused download left files behind"), "behaviour 4 is the one named: \(result.standardError)")
    }

    func test_withoutDevkit_theScriptRefusesToGuessTheRepository() throws {
        let sut = try makeSUT()

        let result = try sut.fixture.capture("/bin/bash", [sut.resources.appendingPathComponent("Scripts/check-lint-tool.sh").path], in: sut.repository)

        XCTAssertEqual(result.status, 2, "no DEVKIT_RESOURCES, no run")
        XCTAssertTrue(result.standardError.contains("run it as 'devkit check-lint-tool'"), "the message names the command")
    }

    func test_scriptsCopiedOutOfAnyRepository_stillPass() throws {
        let sut = try makeSUT()
        let moved = try sut.movedResources(mutates: false) { $0 }

        let result = try sut.runMoved(moved)

        XCTAssertEqual(result.status, 0, "a script that looked at its own location would not find the helper: \(result.standardError)")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL

        func run(_ arguments: [String]) throws -> Captured {
            try fixture.capture(devkit.path, arguments, in: repository)
        }

        /// A copy of the scripts outside any repository; `change` edits the helper to make the mutant.
        func movedResources(mutates: Bool = true, change: (String) -> String) throws -> URL {
            let moved = fixture.directory.appendingPathComponent("moved", isDirectory: true)
            try FileManager.default.copyItem(at: resources, to: moved)
            let helper = moved.appendingPathComponent("Scripts/lib/swiftlint-tool.sh")
            let original = try String(contentsOf: helper, encoding: .utf8)
            let changed = change(original)
            if mutates && changed == original {
                XCTFail("the mutation matched nothing in the helper, so the test would prove nothing")
            }
            try changed.write(to: helper, atomically: true, encoding: .utf8)
            return moved
        }

        func runMoved(_ moved: URL) throws -> Captured {
            var environment = ProcessInfo.processInfo.environment
            environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(repository)
            environment["DEVKIT_RESOURCES"] = moved.path
            return try fixture.capture("/bin/bash", [moved.appendingPathComponent("Scripts/check-lint-tool.sh").path], in: repository, environment: environment)
        }
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return SUT(
            fixture: fixture,
            repository: try fixture.makeRepository(),
            devkit: EndToEndFixture.devkitURL(for: Self.self),
            resources: EndToEndFixture.resourceFolder(for: Self.self)
        )
    }
}
