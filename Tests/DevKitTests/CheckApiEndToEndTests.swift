import XCTest
import Foundation

final class CheckApiEndToEndTests: XCTestCase {
    // MARK: - The self-test

    /// The `ok` lines of `--self-test`: the cases of the normalizer folder and the scenarios of `--since`. Change it with a case.
    static let selfTestCaseCount = 104

    func test_selfTest_runsTheNormalizerCasesOfTheResourcesInARepositoryWithoutFixtures() throws {
        let sut = try makeSUT(conf: nil, files: [:], requiresSdk: false)

        let result = try sut.run(["--self-test"])

        let ok = result.standardOutput.split(separator: "\n").filter { $0.hasPrefix("check-api: ok ") }.count
        XCTAssertEqual(result.status, 0, "every case holds: \(result.standardError)")
        XCTAssertEqual(ok, Self.selfTestCaseCount,
            "the normalizer cases and the scenarios of --since, all reported: \(result.standardOutput.suffix(300))")
        XCTAssertFalse(result.standardOutput.contains("FAIL"), "no case failed")
        XCTAssertFalse(result.standardError.contains("FAIL"), "no case failed")
    }

    // MARK: - Compare, update, since on a package the test builds

    func test_update_writesTheBaselineAndCompareMatchesIt() throws {
        let sut = try makeSUT()

        let update = try sut.run(["--update"])
        let compare = try sut.run([])

        XCTAssertEqual(update.status, 0, "the baseline is written: \(update.standardError)")
        XCTAssertTrue(update.standardOutput.contains("baseline updated: Fixtures/API/public-interface.txt"),
            "the message names the file: \(update.standardOutput)")
        let baseline = try String(contentsOf: sut.baseline, encoding: .utf8)
        XCTAssertTrue(baseline.contains("public struct Box"), "the public interface is in it: \(baseline)")
        XCTAssertFalse(baseline.contains("hidden"), "a private member is not API")
        XCTAssertEqual(compare.status, 0, "the interface matches: \(compare.standardError)")
        XCTAssertEqual(compare.standardOutput, "check-api: the public interface matches the baseline.\n", "the one summary line")
    }

    func test_aRenamedPublicFunction_failsWithTheRemovedAndTheAddedLine() throws {
        let sut = try makeSUT()
        _ = try sut.run(["--update"])
        try sut.replaceInSource("renameMe", with: "renamedAgain")

        let result = try sut.run([])

        XCTAssertEqual(result.status, 1, "a different interface")
        XCTAssertTrue(result.standardError.contains("the public interface differs from the baseline"),
            "the heading: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("-  public func renameMe()"), "the removed line: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("+  public func renamedAgain()"), "the added line: \(result.standardError)")
    }

    func test_anAddedPublicFunction_failsWithAnAddedLineOnly() throws {
        let sut = try makeSUT()
        _ = try sut.run(["--update"])
        try sut.replaceInSource("public func keep() {}", with: "public func keep() {}\n    public func more() {}")

        let result = try sut.run([])

        XCTAssertEqual(result.status, 1, "any difference fails")
        XCTAssertTrue(result.standardError.contains("+  public func more()"), "the added line: \(result.standardError)")
        XCTAssertFalse(result.standardError.contains("-  public"), "nothing was removed: \(result.standardError)")
    }

    func test_aRenamedPrivateFunctionAndAMovedType_leaveTheInterfaceUnchanged() throws {
        let sut = try makeSUT()
        _ = try sut.run(["--update"])
        try sut.replaceInSource("private func hidden() {}", with: "private func renamedPrivately() {}")
        try sut.replaceInSource("public enum Mode { case a, b }", with: "")
        try sut.write("Sources/Fix/Other.swift", "public enum Mode { case a, b }\n")

        let result = try sut.run([])

        XCTAssertEqual(result.status, 0,
            "private members are not API and the order of the files does not matter: \(result.standardError)")
    }

    func test_since_classifiesTheDeltaAgainstAGitRef() throws {
        let sut = try makeSUT()
        _ = try sut.run(["--update"])
        try sut.git(["add", "-f", "Fixtures"])
        try sut.git(["commit", "-q", "-m", "baseline"])
        try sut.git(["tag", "recorded"])

        XCTAssertEqual(try sut.run(["--since", "recorded"]).status, 0, "nothing changed since the tag")

        try sut.replaceInSource("public func keep() {}", with: "public func keep() {}\n    public func more() {}")
        _ = try sut.run(["--update"])
        XCTAssertEqual(try sut.run(["--since", "recorded"]).status, 3, "lines were only added")

        try sut.replaceInSource("public func renameMe() {}", with: "")
        _ = try sut.run(["--update"])
        XCTAssertEqual(try sut.run(["--since", "recorded"]).status, 1, "a line was removed")

        XCTAssertEqual(try sut.run(["--since", "no-such-ref"]).status, 2, "an unknown ref could not be compared")
    }

    func test_since_aRefThatHoldsNoBaseline_isStatusFour() throws {
        let sut = try makeSUT()
        try sut.git(["commit", "-q", "--allow-empty", "-m", "no baseline"])
        try sut.git(["tag", "bare"])
        _ = try sut.run(["--update"])

        let result = try sut.run(["--since", "bare"])

        XCTAssertEqual(result.status, 4, "the interface of that ref was not recorded: \(result.standardError)")
    }

    // MARK: - Library evolution

    func test_libraryEvolution_isOnlyEnabledByTheValueYes() throws {
        struct Case {
            let setting: String
            let enabled: Bool
            let why: String
        }
        let cases = [
            Case(setting: "", enabled: false, why: "a missing key means no"),
            Case(setting: "LIBRARY_EVOLUTION=\"no\"\n", enabled: false, why: "no"),
            Case(setting: "LIBRARY_EVOLUTION=\"Yes\"\n", enabled: false, why: "any spelling but yes means no"),
            Case(setting: "LIBRARY_EVOLUTION=\"true\"\n", enabled: false, why: "any value but yes means no"),
            Case(setting: "LIBRARY_EVOLUTION=\"yes\"\n", enabled: true, why: "yes")
        ]
        for item in cases {
            let sut = try makeSUT(
                conf: "DEVKIT_CONF_VERSION=1\nMODULE=\"Fix\"\nSOURCE_DIR=\"Sources/Fix\"\nSWIFT_FLAGS=(-swift-version 6)\n" +
                    item.setting
            )
            let record = sut.fixture.directory.appendingPathComponent("swiftc-arguments")
            // Records every call of xcrun and then runs the real one, so the compile still happens.
            try sut.fixture.writeShim(named: "xcrun", body: "echo \"$*\" >> '\(record.path)'\nexec /usr/bin/xcrun \"$@\"\n")

            let result = try sut.run(["--update"])

            XCTAssertEqual(result.status, 0, "the module compiles (\(item.why)): \(result.standardError)")
            let emission = try String(contentsOf: record,
                encoding: .utf8).split(separator: "\n").first { $0.contains("-emit-module-interface-path") }
            XCTAssertNotNil(emission, "the call that emits the interface was recorded (\(item.why))")
            XCTAssertEqual(
                emission?.contains("-enable-library-evolution"),
                item.enabled,
                "library evolution is \(item.enabled ? "on" : "off") when \(item.why): \(emission ?? "no call")"
            )
        }
    }

    // MARK: - Dependencies and preparation

    func test_dependenciesAreCompiledFirstAndPrepareRunsBeforeEverything() throws {
        let sut = try makeSUT(
            conf: Self.conf(extra: """
            DEPENDENCIES=("Dep|Sources/Dep|-swift-version 6")
            PREPARE=(touch prepared.marker)

            """),
            files: Self.files.merging([
                "Sources/Dep/Dep.swift": "public struct Part { public init() {} }\n",
                "Sources/Fix/Uses.swift": "import Dep\npublic func use(_ part: Part) {}\n"
            ]) { _, new in new }
        )

        let update = try sut.run(["--update"])

        XCTAssertEqual(update.status, 0, "the dependency compiles first and the module imports it: \(update.standardError)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sut.repository.appendingPathComponent("prepared.marker").path),
            "PREPARE ran at the repository root")
        XCTAssertTrue(try String(contentsOf: sut.baseline, encoding: .utf8).contains("public func use"),
            "the module that uses the dependency is in the baseline")
    }

    // MARK: - The check could not be made (status 2)

    func test_aDependencyThatDoesNotCompile_isStatusTwo() throws {
        let sut = try makeSUT(
            conf: Self.conf(extra: "DEPENDENCIES=(\"Dep|Sources/Dep|-swift-version 6\")\n"),
            files: Self.files.merging(["Sources/Dep/Dep.swift": "this is not swift\n"]) { _, new in new }
        )

        let result = try sut.run(["--update"])

        XCTAssertEqual(result.status, 2, "a dependency that does not compile is not a different interface")
        XCTAssertTrue(result.standardError.contains("the dependency Dep does not compile"),
            "the dependency is named: \(result.standardError)")
    }

    func test_aFailingPrepare_isStatusTwo() throws {
        let sut = try makeSUT(conf: Self.conf(extra: "PREPARE=(false)\n"))

        let result = try sut.run(["--update"])

        XCTAssertEqual(result.status, 2, "the preparation failed")
        XCTAssertTrue(result.standardError.contains("the preparation (false) failed"),
            "the command is named: \(result.standardError)")
    }

    func test_noSwiftSource_isStatusTwo() throws {
        let sut = try makeSUT(files: ["Sources/Other/Other.swift": "public struct Other {}\n"])

        let result = try sut.run(["--update"])

        XCTAssertEqual(result.status, 2, "an empty source list must not read as a different interface")
        XCTAssertTrue(result.standardError.contains("no Swift source in Sources/Fix"),
            "the folder is named: \(result.standardError)")
    }

    func test_aModuleWithoutPublicDeclarations_isStatusTwo() throws {
        let sut = try makeSUT(files: ["Sources/Fix/Fix.swift": "struct Internal {}\n"])

        let result = try sut.run(["--update"])

        XCTAssertEqual(result.status, 2, "an empty interface is neither saved nor compared")
        XCTAssertTrue(result.standardError.contains("the public interface is empty"),
            "the reason is named: \(result.standardError)")
    }

    func test_compareWithoutABaseline_isStatusTwo() throws {
        let sut = try makeSUT()

        let result = try sut.run([])

        XCTAssertEqual(result.status, 2, "nothing to compare with")
        XCTAssertTrue(result.standardError.contains("no baseline at Fixtures/API/public-interface.txt. Run with --update"),
            "the way out is named: \(result.standardError)")
    }

    func test_anSdkThatCannotBeLocated_isStatusTwo() throws {
        let sut = try makeSUT(requiresSdk: false)
        try sut.fixture.writeShim(named: "xcrun", body: "exit 1\n")

        let result = try sut.run(["--update"])

        XCTAssertEqual(result.status, 2, "a missing SDK is not a different interface")
        XCTAssertTrue(result.standardError.contains("the iOS simulator SDK cannot be located"),
            "the reason is named: \(result.standardError)")
    }

    func test_missingModuleOrSourceDirectory_areStatusTwoNamingTheKey() throws {
        let withoutModule = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nSOURCE_DIR=\"Sources/Fix\"\n", requiresSdk: false)
        let withoutSource = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=\"Fix\"\n", requiresSdk: false)

        let first = try withoutModule.run(["--update"])
        let second = try withoutSource.run(["--update"])

        XCTAssertEqual(first.status, 2, "MODULE is required")
        XCTAssertTrue(first.standardError.contains("MODULE"), "the key is named: \(first.standardError)")
        XCTAssertEqual(second.status, 2, "SOURCE_DIR is required")
        XCTAssertTrue(second.standardError.contains("SOURCE_DIR"), "the key is named: \(second.standardError)")
    }

    // MARK: - The path model

    func test_withoutDevkit_theScriptRefusesToGuessTheRepository() throws {
        let sut = try makeSUT(requiresSdk: false)

        let result = try sut.fixture.capture("/bin/bash", [sut.resources.appendingPathComponent("Scripts/check-api.sh").path,
            "--self-test"], in: sut.repository)

        XCTAssertEqual(result.status, 2, "no DEVKIT_REPO_ROOT, no run")
        XCTAssertTrue(result.standardError.contains("run it as 'devkit check-api'"), "the message names the command")
    }

    func test_scriptsCopiedOutOfAnyRepository_stillCheckTheRepositoryTheyAreGiven() throws {
        let sut = try makeSUT()
        let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: sut.resources, to: moved)
        var environment = sut.fixture.shimmedEnvironment()
        environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(sut.repository)
        environment["DEVKIT_RESOURCES"] = moved.path
        environment["DEVKIT_CONF"] = EndToEndFixture.realPath(sut.repository) + "/devkit.conf"
        environment["DEVKIT_WORK"] = EndToEndFixture.realPath(sut.repository) + "/.build/devkit"

        let result = try sut.fixture.capture("/bin/bash", [moved.appendingPathComponent("Scripts/check-api.sh").path, "--update"],
            in: sut.repository, environment: environment)

        XCTAssertEqual(result.status, 0,
            "a script that looked at its own location would not find the repository: \(result.standardError)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sut.baseline.path), "the baseline is in the repository it was given")
    }

    func test_theWorkFolderIsUnderTheDevkitWorkFolder() throws {
        let sut = try makeSUT()

        _ = try sut.run(["--update"])

        let work = sut.repository.appendingPathComponent(".build/devkit/check-api", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: work.appendingPathComponent("Fix.swiftinterface").path),
            "the emitted interface is in DEVKIT_WORK/check-api")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.repository.appendingPathComponent(".build/check-api").path),
            "nothing is written to the old place")
    }

    // MARK: - Helpers

    static let files: [String: String] = [
        "Sources/Fix/Fix.swift": """
        public struct Box {
            public init() {}
            public func keep() {}
            public func renameMe() {}
            private func hidden() {}
        }
        public enum Mode { case a, b }

        """
    ]

    static func conf(extra: String = "") -> String {
        "DEVKIT_CONF_VERSION=1\nMODULE=\"Fix\"\nSOURCE_DIR=\"Sources/Fix\"\nSWIFT_FLAGS=(-swift-version " +
            "6)\nLIBRARY_EVOLUTION=\"yes\"\n" + extra
    }

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL
        var baseline: URL { repository.appendingPathComponent("Fixtures/API/public-interface.txt") }

        func run(_ arguments: [String]) throws -> Captured {
            try fixture.capture(devkit.path, ["check-api"] + arguments, in: repository, environment: fixture.shimmedEnvironment())
        }

        func write(_ path: String, _ text: String) throws {
            let url = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        func replaceInSource(
            _ old: String,
            with new: String,
            in path: String = "Sources/Fix/Fix.swift",
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let url = repository.appendingPathComponent(path)
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains(old) else {
                XCTFail("'\(old)' is in \(path), so the edit changes something", file: file, line: line)
                throw CocoaError(.fileWriteUnknown)
            }
            try text.replacingOccurrences(of: old, with: new).write(to: url, atomically: true, encoding: .utf8)
        }

        func git(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) throws {
            let result = try fixture.capture(
                "/usr/bin/env",
                [
                    "git", "-c", "user.name=probe", "-c", "user.email=probe@example.invalid",
                    "-c", "commit.gpgsign=false", "-c", "tag.gpgSign=false", "-c", "core.hooksPath=/dev/null"
                ] + arguments,
                in: repository
            )
            XCTAssertEqual(result.status, 0, "git \(arguments) works: \(result.standardError)", file: file, line: line)
        }
    }

    struct MissingSdk: Error, CustomStringConvertible {
        let detail: String
        var description: String { "the tests that compile need the iOS simulator SDK (xcrun --sdk iphonesimulator " +
            "--show-sdk-path): \(detail)" }
    }

    private func makeSUT(
        conf: String? = CheckApiEndToEndTests.conf(),
        files: [String: String] = CheckApiEndToEndTests.files,
        requiresSdk: Bool = true
    ) throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        if requiresSdk {
            let sdk = try fixture.capture("/usr/bin/xcrun", ["--sdk", "iphonesimulator", "--show-sdk-path"])
            guard sdk.status == 0 else { throw MissingSdk(detail: sdk.standardError) }
        }
        let repository = try fixture.makeRepository()
        let sut = SUT(
            fixture: fixture,
            repository: repository,
            devkit: EndToEndFixture.devkitURL(for: Self.self),
            resources: EndToEndFixture.resourceFolder(for: Self.self)
        )
        if let conf { try sut.write("devkit.conf", conf) }
        for (path, text) in files { try sut.write(path, text) }
        return sut
    }
}
