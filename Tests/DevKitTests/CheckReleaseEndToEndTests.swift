import XCTest
import Foundation

final class CheckReleaseEndToEndTests: XCTestCase {
    // MARK: - The self-test

    /// The `ok` lines of `--self-test`: the decisions of the script in scratch repositories. Change it with a case.
    static let selfTestCaseCount = 109

    func test_selfTest_runsEveryDecisionOfTheScriptInScratchRepositories() throws {
        let sut = try makeSUT(conf: nil, release: nil)

        let result = try sut.run(["--self-test"])

        let ok = result.standardOutput.split(separator: "\n").filter { $0.hasPrefix("check-release: self-test ok ") }.count
        XCTAssertEqual(result.status, 0, "every case holds: \(result.standardError.prefix(600))")
        XCTAssertEqual(ok, Self.selfTestCaseCount, "every case was reported: \(result.standardOutput.suffix(300))")
        XCTAssertTrue(
            result.standardOutput.contains("check-release: self-test: \(Self.selfTestCaseCount) cases of the decisions of this " +
                "script, all ok."),
            "the summary line counts the same cases: \(result.standardOutput.suffix(200))"
        )
        XCTAssertFalse(result.standardError.contains("FAIL"), "no case failed")
    }

    func test_selfTest_withAnArgument_isStatusTwoWithTheUsageOfTheCommand() throws {
        let sut = try makeSUT(conf: nil, release: nil)

        let result = try sut.run(["--self-test", "1.1.0"])

        XCTAssertEqual(result.status, 2, "a caller mistake")
        XCTAssertTrue(result.standardError.contains("usage: devkit check-release --self-test"),
            "the message names the command: \(result.standardError)")
    }

    // MARK: - The decisions, with the real check-api --since on baselines committed at the tags

    func test_aReleaseThatAgreesWithTheChangelog_passes() throws {
        let sut = try makeSUT()

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 0, "nothing is wrong: \(result.standardError)")
        XCTAssertEqual(
            result.standardOutput,
            "check-release: the changelog agrees on 1.1.0, released 2026-10-03; the pod stays at 1.1.0.\n",
            "the one summary line"
        )
    }

    func test_aRemovedLine_failsUnderTheSameMajorAndPassesUnderANewOne() throws {
        let same = try makeSUT(release: Release(baselineNow: .removed))
        let next = try makeSUT(release: Release(version: "2.0.0", baselineNow: .removed))

        let first = try same.run(["1.1.0"])
        let second = try next.run(["2.0.0"])

        XCTAssertEqual(first.status, 1, "a removed line needs a new major version")
        XCTAssertTrue(first.standardError.contains("needs a new major version"), "the reason is named: \(first.standardError)")
        XCTAssertTrue(first.standardError.contains("devkit check-api --since 1.0.0"),
            "the command that lists the lines is the one of devkit: \(first.standardError)")
        XCTAssertEqual(second.status, 0, "a new major version allows it: \(second.standardError)")
    }

    func test_anAddedLine_passesWithTheReminder() throws {
        let sut = try makeSUT(release: Release(baselineNow: .added))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 0, "lines that were only added pass: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.contains("lines were added to the interface since 1.0.0"),
            "the reminder is printed: \(result.standardOutput)")
        XCTAssertFalse(result.standardOutput.contains("::warning::"), "no annotation outside GitHub Actions")
    }

    func test_anAddedLine_isAlsoAWarningAnnotationUnderGitHubActions() throws {
        let sut = try makeSUT(release: Release(baselineNow: .added))

        let result = try sut.run(["1.1.0"], adding: ["GITHUB_ACTIONS": "true"])

        XCTAssertEqual(result.status, 0, "still a pass: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.contains("::warning::check-release: lines were added to the interface"),
            "the annotation: \(result.standardOutput)")
    }

    func test_aBreakingHeading_failsUnderTheSameMajorAndPassesUnderANewOne() throws {
        let same = try makeSUT(release: Release(subsection: "### Breaking changes"))
        let next = try makeSUT(release: Release(version: "2.0.0", subsection: "### Breaking changes"))

        let first = try same.run(["1.1.0"])
        let second = try next.run(["2.0.0"])

        XCTAssertEqual(first.status, 1, "a declared change of behaviour needs a new major version")
        XCTAssertTrue(first.standardError.contains("'### Breaking changes' subsection"),
            "the heading is named: \(first.standardError)")
        XCTAssertEqual(second.status, 0, "a new major version allows it: \(second.standardError)")
    }

    func test_aHeadingThatSaysThereAreNoBreakingChanges_passes() throws {
        let sut = try makeSUT(release: Release(subsection: "### No breaking changes"))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 0, "the word is not the first of the heading: \(result.standardError)")
    }

    func test_aTagOfThePreviousReleaseThatIsGone_isStatusTwo() throws {
        let sut = try makeSUT()
        try sut.git(["tag", "-d", "1.0.0"])

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 2, "the comparison could not be made")
        XCTAssertTrue(result.standardError.contains("is not in this repository"), "the reason is named: \(result.standardError)")
    }

    func test_aPreviousReleaseThatHoldsNoBaseline_isNotCompared() throws {
        let sut = try makeSUT(release: Release(baselineAtPrevious: nil))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 0, "nothing to compare with is not a problem: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.contains("holds no baseline"), "the script says so: \(result.standardOutput)")
    }

    func test_aVersionThatIsNotThreeGroupsOfDigits_isStatusTwoWithTheUsageOfTheCommand() throws {
        let sut = try makeSUT()

        let result = try sut.run(["1.1"])

        XCTAssertEqual(result.status, 2, "a caller mistake")
        XCTAssertTrue(result.standardError.contains("usage: devkit check-release [--notes] <version>"),
            "the message names the command: \(result.standardError)")
        XCTAssertFalse(result.standardError.contains("Scripts/check-release.sh"), "no path of a script the caller cannot run")
    }

    // MARK: - The notes

    func test_notes_printTheSectionOfTheVersionAndNeedNoDevkitConf() throws {
        let sut = try makeSUT(conf: nil)

        let result = try sut.run(["--notes", "1.1.0"])

        XCTAssertEqual(result.status, 0, "the notes are read from the changelog alone: \(result.standardError)")
        XCTAssertEqual(result.standardOutput, "- a change\n", "the section without its heading and its blank lines")
    }

    func test_notes_ofAVersionWithoutNotes_areStatusOne() throws {
        let sut = try makeSUT(conf: nil)

        let result = try sut.run(["--notes", "9.9.9"])

        XCTAssertEqual(result.status, 1, "no notes under that heading")
        XCTAssertTrue(result.standardError.contains("has no notes under a heading for 9.9.9"),
            "the version is named: \(result.standardError)")
    }

    func test_notes_withoutAChangelog_areStatusTwo() throws {
        let sut = try makeSUT(conf: nil)
        try FileManager.default.removeItem(at: sut.repository.appendingPathComponent("CHANGELOG.md"))

        let result = try sut.run(["--notes", "1.1.0"])

        XCTAssertEqual(result.status, 2, "a file that is not there says nothing about the release")
        XCTAssertTrue(result.standardError.contains("CHANGELOG.md does not exist"), "the file is named: \(result.standardError)")
    }

    // MARK: - The pod is frozen

    func test_aPodspecAtAnotherVersion_isNotReady() throws {
        let sut = try makeSUT(release: Release(podspec: "1.0.0"))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 1, "the pod stays at the frozen version")
        XCTAssertTrue(result.standardError.contains("the pod is frozen at 1.1.0"),
            "the frozen version of devkit.conf is named: \(result.standardError)")
    }

    func test_theFrozenVersionIsTheOneOfDevkitConf() throws {
        let sut = try makeSUT(conf: Self.conf(frozen: "3.4.5"), release: Release(podspec: "3.4.5"))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 0, "a podspec at the version of devkit.conf is frozen: \(result.standardError)")
        XCTAssertTrue(result.standardOutput.contains("the pod stays at 3.4.5"), "the summary names it: \(result.standardOutput)")
    }

    func test_aPodspecNamedByDevkitConf_isTheOneThatIsRead() throws {
        let sut = try makeSUT(conf: Self.conf(extra: "PODSPEC=\"Other.podspec\"\n"),
            release: Release(podspecName: "Other.podspec"))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 0, "the file of PODSPEC is read: \(result.standardError)")
    }

    func test_aPodspecThatIsNotThere_isStatusTwo() throws {
        let sut = try makeSUT()
        try FileManager.default.removeItem(at: sut.repository.appendingPathComponent("Lib.podspec"))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 2, "a file that is not there is not a release that is not ready")
        XCTAssertTrue(result.standardError.contains("the podspec Lib.podspec does not exist; PODSPEC in devkit.conf names it"),
            "devkit.conf names it: \(result.standardError)")
    }

    func test_missingSettings_areStatusTwoNamingTheKey() throws {
        let withoutFrozen = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=\"Lib\"\n")
        let withoutModule = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nFROZEN_POD_VERSION=\"1.1.0\"\n")
        let withoutConf = try makeSUT(conf: nil)

        let first = try withoutFrozen.run(["1.1.0"])
        let second = try withoutModule.run(["1.1.0"])
        let third = try withoutConf.run(["1.1.0"])

        XCTAssertEqual(first.status, 2, "FROZEN_POD_VERSION is required")
        XCTAssertTrue(first.standardError.contains("FROZEN_POD_VERSION"), "the key is named: \(first.standardError)")
        XCTAssertEqual(second.status, 2, "without PODSPEC the podspec is named after MODULE")
        XCTAssertTrue(second.standardError.contains("devkit.conf must set MODULE or PODSPEC"),
            "the keys are named: \(second.standardError)")
        XCTAssertEqual(third.status, 2, "a check that reads the settings needs the file")
        XCTAssertTrue(third.standardError.contains("devkit.conf"), "the file is named: \(third.standardError)")
    }

    // MARK: - The path model

    func test_withoutDevkit_theScriptRefusesToGuessTheRepository() throws {
        let sut = try makeSUT()

        let result = try sut.fixture.capture("/bin/bash", [sut.resources.appendingPathComponent("Scripts/check-release.sh").path,
            "1.1.0"], in: sut.repository)

        XCTAssertEqual(result.status, 2, "no DEVKIT_REPO_ROOT, no run")
        XCTAssertTrue(result.standardError.contains("run it as 'devkit check-release'"),
            "the message names the command: \(result.standardError)")
    }

    func test_scriptsCopiedOutOfAnyRepository_stillCheckTheRepositoryTheyAreGiven() throws {
        let sut = try makeSUT(release: Release(baselineNow: .removed))
        let moved = sut.fixture.directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.copyItem(at: sut.resources, to: moved)
        var environment = sut.fixture.shimmedEnvironment()
        let root = EndToEndFixture.realPath(sut.repository)
        environment["DEVKIT_REPO_ROOT"] = root
        environment["DEVKIT_RESOURCES"] = moved.path
        environment["DEVKIT_CONF"] = root + "/devkit.conf"
        environment["DEVKIT_WORK"] = root + "/.build/devkit"

        let result = try sut.fixture.capture("/bin/bash", [moved.appendingPathComponent("Scripts/check-release.sh").path,
            "1.1.0"], in: sut.repository, environment: environment)

        XCTAssertEqual(result.status, 1,
            "a script that looked at its own location would not find the repository, its changelog or its check-api: " +
            "\(result.standardError)")
        XCTAssertTrue(result.standardError.contains("needs a new major version"),
            "the comparison ran in the repository it was given: \(result.standardError)")
    }

    func test_aCallerWhoExportsDevkitResources_cannotChooseAnotherCheckApi() throws {
        let sut = try makeSUT(release: Release(baselineNow: .removed))
        let impostor = sut.fixture.directory.appendingPathComponent("impostor", isDirectory: true)
        try FileManager.default.copyItem(at: sut.resources, to: impostor)
        let stub = impostor.appendingPathComponent("Scripts/check-api.sh")
        try "#!/bin/bash\necho stub\nexit 0\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        let result = try sut.run(["1.1.0"], adding: ["DEVKIT_RESOURCES": impostor.path])

        XCTAssertEqual(result.status, 1,
            "the check-api of devkit saw the removed line, not the stub that says all is well: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("needs a new major version"),
            "the real comparison ran: \(result.standardError)")
    }

    // MARK: - SECURITY.md covers the release

    func test_security_aRowForTheReleaseBesideTheOlderOne_passes() throws {
        let sut = try makeSUT(release: Release(
            version: "1.2.0", previous: "1.1.0", security: Self.securityTable("1.1.x | yes", "1.2.x | yes", "earlier | no")))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 0, "1.2.x is a supported row: \(result.standardError)")
    }

    func test_security_everyFormOfTheVersionCell_coversTheRelease() throws {
        for cell in ["1.2.x", "1.2.*", "1.x", "1.*", "1.2.X"] {
            let sut = try makeSUT(release: Release(
                version: "1.2.0", previous: "1.1.0", security: Self.securityTable("\(cell) | Yes", "earlier | no")))

            let result = try sut.run(["1.2.0"])

            XCTAssertEqual(result.status, 0, "'\(cell)' covers 1.2.0: \(result.standardError)")
        }
    }

    func test_security_aTableWithoutARowForTheRelease_isStatusOneNamingTheRowToAdd() throws {
        let sut = try makeSUT(release: Release(
            version: "1.2.0", previous: "1.1.0", security: Self.securityTable("1.1.x | yes", "earlier | no")))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 1, "1.1.x does not cover 1.2.0")
        XCTAssertTrue(result.standardError.contains("SECURITY.md has no row for 1.2.x"),
            "the problem names the line that is missing: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("| 1.2.x | yes |"), "and the row to add: \(result.standardError)")
    }

    func test_security_aRowForTheReleaseThatSaysNo_isStatusOne() throws {
        let sut = try makeSUT(release: Release(
            version: "1.2.0", previous: "1.1.0", security: Self.securityTable("1.2.x | no", "1.1.x | yes")))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 1, "a covering row that says no is not support")
        XCTAssertTrue(result.standardError.contains("SECURITY.md lists 1.2.x as not supported"),
            "the problem says so: \(result.standardError)")
    }

    func test_security_anOlderRowThatStillSaysYes_isNoProblem() throws {
        let sut = try makeSUT(release: Release(
            version: "1.2.0", previous: "1.1.0", security: Self.securityTable("1.2.x | yes", "1.0.x | yes")))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 0, "the rule is about the release being covered: \(result.standardError)")
    }

    func test_security_aFileWithoutATable_isStatusTwo() throws {
        let sut = try makeSUT(release: Release(security: "# Security policy\n\nWrite to us about a vulnerability.\n"))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 2, "a file that cannot be read is never a pass")
        XCTAssertTrue(result.standardError.contains("SECURITY.md has no supported-versions table that check-release can read"),
            "the message says what is missing: \(result.standardError)")
    }

    func test_security_aTableOfOtherColumns_isStatusTwo() throws {
        let sut = try makeSUT(release: Release(security: "| Name | Contact |\n|---|---|\n| a | b |\n"))

        let result = try sut.run(["1.1.0"])

        XCTAssertEqual(result.status, 2, "a table with no version and no yes/no cell is not the table that is read")
    }

    func test_security_aProblemIsListedWithTheOthers() throws {
        let sut = try makeSUT(release: Release(
            version: "1.2.0", previous: "1.1.0", podspec: "1.0.9", security: Self.securityTable("1.1.x | yes")))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 1, "two problems")
        XCTAssertTrue(result.standardError.contains("the podspec names version '1.0.9'"),
            "the podspec problem is reported: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("SECURITY.md has no row for 1.2.x"),
            "and the SECURITY.md problem in the same run: \(result.standardError)")
    }

    // MARK: - The link lines of the changelog

    private static let site = "https://example.invalid/Lib"

    func test_links_aChangelogWithoutLinkLines_passes() throws {
        let sut = try makeSUT(release: Release(version: "1.2.0", previous: "1.1.0"))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 0, "a changelog without link references is not asked for them: \(result.standardError)")
    }

    func test_links_theLinesOfTheReleaseAndOfUnreleased_pass() throws {
        let tail = "\n[Unreleased]: \(Self.site)/compare/1.2.0...HEAD\n[1.2.0]: \(Self.site)/compare/1.1.0...1.2.0\n" +
            "[1.1.0]: \(Self.site)/tree/1.1.0\n"
        let sut = try makeSUT(release: Release(version: "1.2.0", previous: "1.1.0", changelogTail: tail))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 0, "the footer says the release: \(result.standardError)")
    }

    func test_links_aFooterThatStillStopsAtThePreviousRelease_failsOnBothLines() throws {
        let tail = "\n[Unreleased]: \(Self.site)/compare/1.1.0...HEAD\n[1.1.0]: \(Self.site)/compare/1.0.0...1.1.0\n"
        let sut = try makeSUT(release: Release(version: "1.2.0", previous: "1.1.0", changelogTail: tail))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 1, "the footer of a release that was not updated")
        XCTAssertTrue(result.standardError.contains("has no '[1.2.0]:' line"),
            "the missing line of the release is named: \(result.standardError)")
        XCTAssertTrue(result.standardError.contains("[Unreleased] link"),
            "and the link of Unreleased that compares from the old release: \(result.standardError)")
    }

    func test_links_anUnreleasedLinkThatIsNotACompareFromTheRelease_isAProblem() throws {
        for target in ["compare/1.1.0...HEAD", "compare/1.2.0..HEAD", "compare/1.2.0...main", "tree/1.2.0"] {
            let tail = "\n[Unreleased]: \(Self.site)/\(target)\n[1.2.0]: \(Self.site)/compare/1.1.0...1.2.0\n"
            let sut = try makeSUT(release: Release(version: "1.2.0", previous: "1.1.0", changelogTail: tail))

            let result = try sut.run(["1.2.0"])

            XCTAssertEqual(result.status, 1, "'\(target)' is not a compare from 1.2.0 to HEAD")
            XCTAssertTrue(result.standardError.contains("\(Self.site)/\(target)"),
                "the link found is quoted: \(result.standardError)")
        }
    }

    func test_links_anUnreleasedLinkThatIsOnlyTheRange_isAProblem() throws {
        let tail = "\n[Unreleased]: 1.2.0...HEAD\n[1.2.0]: \(Self.site)/compare/1.1.0...1.2.0\n"
        let sut = try makeSUT(release: Release(version: "1.2.0", previous: "1.1.0", changelogTail: tail))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 1, "a range that is no part of a compare link is not a link to compare")
    }

    func test_links_noUnreleasedLine_isNoProblemWhenThereIsNoUnreleasedHeading() throws {
        let tail = "\n[1.2.0]: \(Self.site)/compare/1.1.0...1.2.0\n[1.1.0]: \(Self.site)/tree/1.1.0\n"
        let sut = try makeSUT(release: Release(version: "1.2.0", previous: "1.1.0", changelogTail: tail))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 0, "a changelog with no Unreleased section needs no link for it: \(result.standardError)")
    }

    func test_links_anUnreleasedHeadingWithoutItsLine_isAProblem() throws {
        let tail = "\n## [Unreleased]\n\n- later\n\n[1.2.0]: \(Self.site)/compare/1.1.0...1.2.0\n"
        let sut = try makeSUT(release: Release(version: "1.2.0", previous: "1.1.0", changelogTail: tail))

        let result = try sut.run(["1.2.0"])

        XCTAssertEqual(result.status, 1, "the heading would render as plain text")
        XCTAssertTrue(result.standardError.contains("no '[Unreleased]:' link line"),
            "the missing line is named: \(result.standardError)")
    }

    // MARK: - Helpers

    enum Baseline {
        case keep, added, removed

        var text: String {
            switch self {
            case .keep: "public struct First {\n  public func keep()\n}\n"
            case .added: "public struct First {\n  public func keep()\n  public func more()\n}\n"
            case .removed: "public struct First {\n}\n"
            }
        }
    }

    /// What the scratch repository holds: the release before this one with its baseline at its tag, then the commit being
    /// released.
    struct Release {
        var version = "1.1.0"
        var previous = "1.0.0"
        var baselineAtPrevious: Baseline? = .keep
        var baselineNow: Baseline = .keep
        var subsection = ""
        var podspec = "1.1.0"
        var podspecName = "Lib.podspec"
        /// The text of SECURITY.md, or nil for a repository that has none.
        var security: String?
        /// Lines appended to CHANGELOG.md after the last section, such as link references.
        var changelogTail = ""
    }

    /// A SECURITY.md whose table holds the given rows under the usual header.
    static func securityTable(_ rows: String...) -> String {
        "# Security policy\n\n## Supported versions\n\nSecurity fixes are made for the latest release.\n\n" +
            "| Version | Supported |\n|---|---|\n" + rows.map { "| \($0) |\n" }.joined() +
            "\n## Reporting a vulnerability\n\nWrite to us.\n"
    }

    static func conf(frozen: String = "1.1.0", extra: String = "") -> String {
        "DEVKIT_CONF_VERSION=1\nMODULE=\"Lib\"\nFROZEN_POD_VERSION=\"\(frozen)\"\n" + extra
    }

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let resources: URL

        func run(_ arguments: [String], adding extra: [String: String] = [:]) throws -> Captured {
            try fixture.capture(devkit.path, ["check-release"] + arguments, in: repository,
                environment: fixture.shimmedEnvironment(adding: extra))
        }

        func write(_ path: String, _ text: String) throws {
            let url = repository.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        func git(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) throws {
            let result = try fixture.capture(
                "/usr/bin/env",
                [
                    "git", "-c", "init.defaultBranch=main", "-c", "user.name=probe", "-c", "user.email=probe@example.invalid",
                    "-c", "commit.gpgsign=false", "-c", "tag.gpgSign=false", "-c", "core.hooksPath=/dev/null"
                ] + arguments,
                in: repository
            )
            XCTAssertEqual(result.status, 0, "git \(arguments) works: \(result.standardError)", file: file, line: line)
        }
    }

    private func makeSUT(conf: String? = CheckReleaseEndToEndTests.conf(), release: Release? = Release()) throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sut = SUT(
            fixture: fixture,
            repository: try fixture.makeRepository(),
            devkit: EndToEndFixture.devkitURL(for: Self.self),
            resources: EndToEndFixture.resourceFolder(for: Self.self)
        )
        if let conf { try sut.write("devkit.conf", conf) }
        guard let release else { return sut }
        try sut.write("README", "base\n")
        try sut.git(["add", "README"])
        try sut.git(["commit", "-q", "-m", "base"])
        if let baseline = release.baselineAtPrevious {
            try sut.write("Fixtures/API/public-interface.txt", baseline.text)
            try sut.git(["add", "-f", "Fixtures/API/public-interface.txt"])
        } else {
            try sut.write("earlier", "earlier\n")
            try sut.git(["add", "earlier"])
        }
        try sut.git(["commit", "-q", "-m", "the previous release"])
        try sut.git(["tag", release.previous])
        let breaking = release.subsection.isEmpty ? "" : "\(release.subsection)\n\n- a behaviour changed\n\n"
        try sut.write(
            "CHANGELOG.md",
            "## [\(release.version)] - 2026-10-03\n\n\(breaking)- a change\n\n## [\(release.previous)] - 2025-10-11\n\n- " +
                "earlier\n" + release.changelogTail
        )
        try sut.write(release.podspecName, "Pod::Spec.new do |s|\n  s.version = '\(release.podspec)'\nend\n")
        try sut.write("Fixtures/API/public-interface.txt", release.baselineNow.text)
        try sut.git(["add", "-f", "CHANGELOG.md", release.podspecName, "Fixtures/API/public-interface.txt"])
        if let security = release.security {
            try sut.write("SECURITY.md", security)
            try sut.git(["add", "SECURITY.md"])
        }
        try sut.git(["commit", "-q", "-m", "the release"])
        return sut
    }
}
