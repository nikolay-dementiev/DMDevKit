import XCTest
import Foundation

final class LintContractEndToEndTests: XCTestCase {
    // MARK: - What the contract proves

    func test_aRepositoryWhoseRulesFireWhereTheFixturesExpect_passes() throws {
        let sut = try makeSUT()

        let result = try sut.run()

        XCTAssertEqual(result.status, 0, "every rule fires where expected and nowhere else: \(result.standardError)")
        XCTAssertEqual(
            result.standardOutput,
            "check-lint-contract: the 2 rules fire on 2 expected lines of 3 fixtures and on no other line.\n",
            "the summary counts rules, expected lines and fixtures"
        )
    }

    func test_aRuleThatStoppedFiring_failsTheContract() throws {
        let sut = try makeSUT(config: Self.config.replacingOccurrences(of: "fatalError", with: "fatalErrorX"))

        let result = try sut.run()

        XCTAssertEqual(result.status, 1, "a line that expects a diagnostic got none")
        XCTAssertTrue(result.standardError.contains("termination.txt:2: expected no_process_termination, got no diagnostic"), "the line is named: \(result.standardError)")
    }

    func test_aDiagnosticOnALineThatExpectsNone_failsTheContract() throws {
        var files = Self.files
        files["Fixtures/Lint/termination.txt"] = "let value = 1\nfatalError(\"x\") // expect: no_process_termination\nfatalError(\"y\")\n"
        let sut = try makeSUT(files: files)

        let result = try sut.run()

        XCTAssertEqual(result.status, 1, "a line without an expectation must give none of the rules")
        XCTAssertTrue(result.standardError.contains("termination.txt:3: expected no diagnostic, got no_process_termination"), "the line is named: \(result.standardError)")
    }

    func test_aRuleThatReachesAnOutsideFixture_failsTheContract() throws {
        let sut = try makeSUT(config: Self.config.replacingOccurrences(of: ".*/Sources/Lib/.*\\\\.swift", with: ".*/Sources/.*\\\\.swift"))

        let result = try sut.run()

        XCTAssertEqual(result.status, 1, "a rule that is too wide reaches a fixture outside the library")
        XCTAssertTrue(result.standardError.contains("Outside/Sources/Other/Thing.txt"), "the Outside fixture is named: \(result.standardError)")
    }

    func test_aSubfolderFixtureIsLintedInTheSameSubfolderOfTheSourceDirectory() throws {
        let sut = try makeSUT(config: Self.config.replacingOccurrences(of: ".*/Sources/Lib/Domain/.*\\\\.swift", with: ".*/Sources/Lib/Other/.*\\\\.swift"))

        let result = try sut.run()

        XCTAssertEqual(result.status, 1, "the Domain fixture no longer sits where the rule applies")
        XCTAssertTrue(result.standardError.contains("Domain/imports.txt:2: expected domain_imports, got no diagnostic"), "the Domain fixture is the one named: \(result.standardError)")
    }

    // MARK: - Guards: the check could not be made

    func test_noFixture_isStatusTwo() throws {
        let sut = try makeSUT(files: ["Sources/Lib/Keep.swift": "let kept = 1\n"])

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "nothing to prove")
        XCTAssertTrue(result.standardError.contains("no fixture found in Fixtures/Lint"), "the folder is named: \(result.standardError)")
    }

    func test_aRuleNoFixtureExpects_isStatusTwo() throws {
        let sut = try makeSUT(conf: Self.conf(rules: "domain_imports no_process_termination ghost_rule"))

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "a rule that nothing proves")
        XCTAssertTrue(result.standardError.contains("no fixture expects the rule 'ghost_rule'"), "the rule is named: \(result.standardError)")
    }

    func test_aFixtureExpectingAnUnknownRule_isStatusTwo() throws {
        var files = Self.files
        files["Fixtures/Lint/termination.txt"] = "let value = 1\nfatalError(\"x\") // expect: no_process_termination other_rule\n"
        let sut = try makeSUT(files: files)

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "an expectation the contract does not cover")
        XCTAssertTrue(result.standardError.contains("expects 'other_rule', which is not a rule of the contract"), "the rule is named: \(result.standardError)")
    }

    func test_aFixtureNameTheContractCannotCarry_isStatusTwo() throws {
        var files = Self.files
        files["Fixtures/Lint/odd$name.txt"] = "let value = 1\n"
        let sut = try makeSUT(files: files)

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "a character outside letters, digits and . _ - / and spaces")
        XCTAssertTrue(result.standardError.contains("odd$name.txt has a character in its name"), "the file is named: \(result.standardError)")
    }

    func test_anOutsideFixtureThatExpectsADiagnostic_isStatusTwo() throws {
        var files = Self.files
        files["Fixtures/Lint/Outside/Sources/Other/Thing.txt"] = "fatalError(\"x\") // expect: no_process_termination\n"
        let sut = try makeSUT(files: files)

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "a fixture outside the library expects nothing")
        XCTAssertTrue(result.standardError.contains("a fixture under Outside expects none"), "the message says so: \(result.standardError)")
    }

    func test_aSourceDirectoryThatDoesNotExist_isStatusTwo() throws {
        let sut = try makeSUT(conf: Self.conf(sourceDirectory: "Sources/Missing"))

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "the include patterns of the rules name it")
        XCTAssertTrue(result.standardError.contains("Sources/Missing does not exist"), "the folder is named: \(result.standardError)")
    }

    func test_swiftlintThatLintsFewerFilesThanThereAreFixtures_isStatusTwo() throws {
        let sut = try makeSUT(config: Self.config + "excluded:\n  - Sources/Lib/Domain\n")

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "a run that lints no file reports no violation, and every rule would look quiet")
        XCTAssertTrue(result.standardError.contains("SwiftLint linted 2 files, and there are 3 fixtures"), "both counts are named: \(result.standardError)")
    }

    // MARK: - The configuration

    func test_missingSourceDirectoryOrRules_areStatusTwoNamingTheKey() throws {
        let withoutSource = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nRULES=\"domain_imports\"\n")
        let emptyRules = try makeSUT(conf: Self.conf(rules: ""))

        let first = try withoutSource.run()
        let second = try emptyRules.run()

        XCTAssertEqual(first.status, 2, "SOURCE_DIR is required")
        XCTAssertTrue(first.standardError.contains("SOURCE_DIR"), "the key is named: \(first.standardError)")
        XCTAssertEqual(second.status, 2, "an empty RULES is an error, not a contract that proves nothing")
        XCTAssertTrue(second.standardError.contains("RULES"), "the key is named: \(second.standardError)")
    }

    func test_fixtureDirectory_canBeSet() throws {
        var moved = Dictionary(uniqueKeysWithValues: Self.files.map { ($0.key.replacingOccurrences(of: "Fixtures/Lint", with: "Fx"), $0.value) })
        moved["Sources/Lib/Keep.swift"] = "let kept = 1\n"
        let sut = try makeSUT(files: moved, conf: Self.conf(extra: "FIXTURE_DIR=\"Fx/\"\n"))

        let result = try sut.run()

        XCTAssertEqual(result.status, 0, "the fixtures of FIXTURE_DIR are read: \(result.standardError)")
    }

    func test_withoutADevkitConf_isStatusTwo() throws {
        let sut = try makeSUT(conf: nil)

        let result = try sut.run()

        XCTAssertEqual(result.status, 2, "the loader refuses a missing file")
        XCTAssertTrue(result.standardError.contains("devkit.conf"), "the file is named: \(result.standardError)")
    }

    func test_withoutDevkit_theScriptRefusesToGuessTheRepository() throws {
        let sut = try makeSUT()
        let script = sut.resources.appendingPathComponent("Scripts/check-lint-contract.sh")

        let result = try sut.fixture.capture("/bin/bash", [script.path], in: sut.repository)

        XCTAssertEqual(result.status, 2, "no DEVKIT_REPO_ROOT, no run")
        XCTAssertTrue(result.standardError.contains("run it as 'devkit check-lint-contract'"), "the message names the command")
    }

    func test_scriptsCopiedOutOfAnyRepository_stillCheckTheRepositoryTheyAreGiven() throws {
        let sut = try makeSUT()
        let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: sut.resources, to: moved)
        var environment = sut.fixture.shimmedEnvironment()
        environment["DEVKIT_REPO_ROOT"] = EndToEndFixture.realPath(sut.repository)
        environment["DEVKIT_RESOURCES"] = moved.path
        environment["DEVKIT_CONF"] = EndToEndFixture.realPath(sut.repository) + "/devkit.conf"

        let result = try sut.fixture.capture("/bin/bash", [moved.appendingPathComponent("Scripts/check-lint-contract.sh").path], in: sut.repository, environment: environment)

        XCTAssertEqual(result.status, 0, "a script that looked at its own location would not find the repository: \(result.standardError)")
    }

    // MARK: - Helpers

    /// A miniature of a library: one rule that applies in `Sources/Lib/Domain` and one in all of `Sources/Lib`.
    static let config = """
    swiftlint_version: \(RealSwiftLint.version)
    included:
      - Sources
    custom_rules:
      domain_imports:
        name: "Domain imports"
        included: ".*/Sources/Lib/Domain/.*\\\\.swift"
        regex: '^import\\s+(?!Foundation\\b)\\w+'
        match_kinds: [keyword, identifier]
        message: "Foundation only."
        severity: error
      no_process_termination:
        name: "No process termination"
        included: ".*/Sources/Lib/.*\\\\.swift"
        regex: '\\bfatalError\\s*\\('
        match_kinds: [identifier]
        message: "A library never terminates its host."
        severity: error

    """

    static let files: [String: String] = [
        "Fixtures/Lint/Domain/imports.txt": "import Foundation\nimport UIKit // expect: domain_imports\n",
        "Fixtures/Lint/termination.txt": "let value = 1\nfatalError(\"x\") // expect: no_process_termination\n",
        "Fixtures/Lint/Outside/Sources/Other/Thing.txt": "fatalError(\"outside\")\n",
        "Sources/Lib/Keep.swift": "let kept = 1\n",
    ]

    static func conf(sourceDirectory: String = "Sources/Lib", rules: String = "domain_imports no_process_termination", extra: String = "") -> String {
        "DEVKIT_CONF_VERSION=1\nSOURCE_DIR=\"\(sourceDirectory)\"\nRULES=\"\(rules)\"\n" + extra
    }

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL

        func run() throws -> Captured {
            try fixture.capture(devkit.path, ["check-lint-contract"], in: repository, environment: fixture.shimmedEnvironment())
        }
    }

    private func makeSUT(files: [String: String] = LintContractEndToEndTests.files, config: String = LintContractEndToEndTests.config, conf: String? = LintContractEndToEndTests.conf()) throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = try fixture.makeRepository()
        try config.write(to: repository.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        if let conf { try conf.write(to: repository.appendingPathComponent("devkit.conf"), atomically: true, encoding: .utf8) }
        for (path, text) in files {
            let url = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try RealSwiftLint.seed(into: repository)
        return SUT(fixture: fixture, repository: repository, devkit: EndToEndFixture.devkitURL(for: Self.self), resources: EndToEndFixture.resourceFolder(for: Self.self))
    }
}
