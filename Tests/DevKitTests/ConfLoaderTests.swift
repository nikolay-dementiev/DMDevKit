import XCTest
import Foundation

final class ConfLoaderTests: XCTestCase {
    func test_minimalConf_loadsAndMissingArraysAreEmpty() throws {
        let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=\"Foo\"\n")

        let result = try sut.run("echo \"$MODULE\"; echo \"${#SWIFT_FLAGS[@]} ${#DEPENDENCIES[@]} ${#PREPARE[@]}\"")

        XCTAssertEqual(result.status, 0, "a valid file loads")
        XCTAssertEqual(result.standardOutput, "Foo\n0 0 0\n",
            "the scalar is set, the three arrays are empty and safe under set -u")
    }

    func test_arrays_keepTheirElementsIncludingBlanksAndBars() throws {
        let sut = try makeSUT(conf: """
        DEVKIT_CONF_VERSION=1
        SWIFT_FLAGS=(-swift-version 6 "a b")
        DEPENDENCIES=("DMAction|.build/checkouts/DMAction/Sources|-swift-version 6")
        PREPARE=(swift package resolve)
        """)

        let result = try sut.run("printf '[%s]' \"${SWIFT_FLAGS[@]}\"; echo; printf '[%s]' \"${DEPENDENCIES[@]}\"; echo; echo " +
            "${#PREPARE[@]}")

        XCTAssertEqual(
            result.standardOutput,
            "[-swift-version][6][a b]\n[DMAction|.build/checkouts/DMAction/Sources|-swift-version 6]\n3\n",
            "elements are not split, joined or dropped"
        )
    }

    func test_wrappers_isAnArrayThatKeepsItsElements_andIsEmptyWhenNotSet() throws {
        let set = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nWRAPPERS=(lint.sh \"b c.sh\")\n")
        let unset = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\n")

        XCTAssertEqual(try set.run("printf '[%s]' \"${WRAPPERS[@]}\"").standardOutput, "[lint.sh][b c.sh]",
            "WRAPPERS is a setting of schema version 1 and its elements are not split")
        XCTAssertEqual(try unset.run("echo ${#WRAPPERS[@]}").standardOutput, "0\n", "not set is empty, and safe under set -u")
    }

    func test_wrappersGivenAScalar_isRejected() throws {
        let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nWRAPPERS=lint.sh\n")

        let result = try sut.run("echo loaded")

        XCTAssertEqual(result.status, 2, "WRAPPERS is an array")
        XCTAssertTrue(result.standardError.contains("WRAPPERS must be an array"), "the message names it: \(result.standardError)")
    }

    func test_unknownName_isRejectedAndNamed() throws {
        let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=Foo\nLIBRARY_DIR=Sources/Foo\n")

        let result = try sut.run("echo loaded")

        XCTAssertEqual(result.status, 2, "a name outside the schema is an error")
        XCTAssertTrue(result.standardError.contains("'LIBRARY_DIR'"), "the message names the setting")
        XCTAssertEqual(result.standardOutput, "", "the script did not go on")
    }

    func test_missingVersion_isRejected() throws {
        let sut = try makeSUT(conf: "MODULE=Foo\n")

        let result = try sut.run("echo loaded")

        XCTAssertEqual(result.status, 2, "no DEVKIT_CONF_VERSION, no load")
        XCTAssertTrue(result.standardError.contains("DEVKIT_CONF_VERSION=1"), "the message says what to set")
    }

    func test_wrongVersion_isRejected() throws {
        for version in ["2", "0", "one", ""] {
            let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=\"\(version)\"\n")

            let result = try sut.run("echo loaded")

            XCTAssertEqual(result.status, 2, "version '\(version)' is not 1")
            XCTAssertEqual(result.standardOutput, "", "nothing runs after a rejected version")
        }
    }

    func test_missingFile_isRejected() throws {
        let sut = try makeSUT(conf: nil)

        let result = try sut.run("echo loaded")

        XCTAssertEqual(result.status, 2, "no devkit.conf, no load")
        XCTAssertTrue(result.standardError.contains("devkit.conf"), "the message names the file")
    }

    func test_scalarGivenAnArrayAndArrayGivenAScalar_areRejected() throws {
        for line in ["MODULE=(a b)", "SWIFT_FLAGS=\"-x\""] {
            let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\n\(line)\n")

            let result = try sut.run("echo loaded")

            XCTAssertEqual(result.status, 2, "'\(line)' has the wrong kind")
            XCTAssertEqual(result.standardOutput, "", "nothing runs after the rejection")
        }
    }

    func test_podspec_defaultsFromModuleAndTheRepositoryRoot_andAnOverrideIsHonoured() throws {
        let defaulted = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=Foo\n")
        let overridden = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=Foo\nPODSPEC=Specs/Foo.podspec\n")

        XCTAssertEqual(try defaulted.run("echo \"$PODSPEC\"").standardOutput, defaulted.root.path + "/Foo.podspec\n",
            "root plus module")
        XCTAssertEqual(try overridden.run("echo \"$PODSPEC\"").standardOutput, overridden.root.path + "/Specs/Foo.podspec\n",
            "a relative override is relative to the root")
    }

    func test_valuesLeftInTheEnvironment_doNotLeakIntoTheSettings() throws {
        let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\n", environment: ["MODULE": "FromTheEnvironment", "SWIFT_FLAGS": "x"])

        let result = try sut.run("echo \"[${MODULE-unset}]\"")

        XCTAssertEqual(result.standardOutput, "[unset]\n", "only the file decides what a setting is")
    }

    func test_callerWithAnotherIFS_getsTheSameResult() throws {
        let valid = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=Foo\n", prelude: "IFS=$'\\n\\t'")
        let unknown = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nBOGUS=1\n", prelude: "IFS=$'\\n\\t'")

        XCTAssertEqual(try valid.run("echo \"$MODULE\"").standardOutput, "Foo\n", "a hardened IFS does not break the loader")
        XCTAssertEqual(try unknown.run("echo loaded").status, 2, "unknown names are still found")
    }

    func test_confThatSetsADevkitPath_isRejected() throws {
        for line in ["DEVKIT_REPO_ROOT=/elsewhere", "DEVKIT_CONF=/elsewhere/devkit.conf", "DEVKIT_WORK=/elsewhere",
            "DEVKIT_RESOURCES=/elsewhere"] {
            let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\n\(line)\n", environment: ["DEVKIT_WORK": "/work",
                "DEVKIT_RESOURCES": "/resources"])

            let result = try sut.run("echo loaded")

            XCTAssertEqual(result.status, 2, "'\(line)' changes a path that devkit gave")
            XCTAssertTrue(result.standardError.contains(line.split(separator: "=")[0]), "the message names the variable")
        }
    }

    func test_podspecDefault_withoutARepositoryRoot_isRejected() throws {
        let sut = try makeSUT(conf: "DEVKIT_CONF_VERSION=1\nMODULE=Foo\n", environment: ["DEVKIT_REPO_ROOT": ""])

        let result = try sut.run("echo \"$PODSPEC\"")

        XCTAssertEqual(result.status, 2, "a podspec path needs the root")
        XCTAssertTrue(result.standardError.contains("DEVKIT_REPO_ROOT"), "the message names the missing variable")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let root: URL
        let loader: URL
        let environment: [String: String]
        var prelude = ""

        func run(_ body: String) throws -> Captured {
            let script = "set -euo pipefail\n" + prelude + "\n. \"$LOADER\"\ndevkit_conf_load\n" + body + "\n"
            return try fixture.capture("/bin/bash", ["-c", script], in: root, environment: environment)
        }
    }

    private func makeSUT(conf: String?, environment: [String: String] = [:], prelude: String = "") throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = try fixture.makeRepository()
        if let conf { try conf.write(to: root.appendingPathComponent("devkit.conf"), atomically: true, encoding: .utf8) }
        let loader = EndToEndFixture.resourceFolder(for: Self.self).appendingPathComponent("Scripts/lib/devkit-conf.sh")
        let realRoot = URL(fileURLWithPath: EndToEndFixture.realPath(root), isDirectory: true)
        var base = ProcessInfo.processInfo.environment
        base["LOADER"] = loader.path
        base["DEVKIT_REPO_ROOT"] = realRoot.path
        base["DEVKIT_CONF"] = realRoot.appendingPathComponent("devkit.conf").path
        return SUT(fixture: fixture, root: realRoot, loader: loader, environment: base.merging(environment) { _, added in added },
            prelude: prelude)
    }
}
