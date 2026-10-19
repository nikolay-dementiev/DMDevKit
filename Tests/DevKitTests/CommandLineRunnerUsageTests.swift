import XCTest
import Foundation
import DevKitCore

final class CommandLineRunnerUsageTests: XCTestCase {
    func test_help_listsEveryCommandOnStandardOutputAndExitsZero() {
        let (sut, doubles) = makeSUT()

        let status = sut.run(arguments: ["--help"])

        XCTAssertEqual(status, 0, "--help is not an error")
        XCTAssertTrue(doubles.output.standardOutput.contains("alpha"), "the command name is listed on standard output")
        XCTAssertTrue(doubles.output.standardOutput.contains("Do the alpha work"), "the summary is listed with it")
        XCTAssertEqual(doubles.output.standardError, "", "--help writes nothing on standard error")
    }

    func test_noArguments_printsUsageOnStandardErrorAndExitsSixtyFour() {
        let (sut, doubles) = makeSUT()

        let status = sut.run(arguments: [])

        XCTAssertEqual(status, 64, "a missing command is a mistake of the caller (EX_USAGE); 1 and 2 belong to the scripts")
        XCTAssertTrue(doubles.output.standardError.contains("alpha"), "the usage text on standard error lists the commands")
        XCTAssertEqual(doubles.output.standardOutput, "", "a usage error writes nothing on standard output")
    }

    func test_version_printsTheVersionLineAndExitsZero() {
        let (sut, doubles) = makeSUT()

        let status = sut.run(arguments: ["--version"])

        XCTAssertEqual(status, 0, "--version is not an error")
        XCTAssertEqual(doubles.output.standardOutput, "0.1.2-test\n", "exactly one line, the version")
    }

    func test_unknownCommand_namesItListsTheCommandsAndExitsSixtyFour() {
        let (sut, doubles) = makeSUT()

        let status = sut.run(arguments: ["nope"])

        XCTAssertEqual(status, 64, "an unknown command is a mistake of the caller (EX_USAGE)")
        XCTAssertTrue(doubles.output.standardError.contains("unknown command 'nope'"), "the message names the command")
        XCTAssertTrue(doubles.output.standardError.contains("alpha"), "the message lists the commands")
        XCTAssertTrue(doubles.launcher.plans.isEmpty, "nothing was started")
    }

    func test_pathLikeNames_areRejectedAndNothingIsStarted() {
        for name in ["../alpha", "Scripts/alpha.sh", "/bin/ls", "alpha.sh", "", "-alpha"] {
            let (sut, doubles) = makeSUT()

            let status = sut.run(arguments: [name])

            XCTAssertEqual(status, 64, "'\(name)' is not in the command table")
            XCTAssertTrue(doubles.launcher.plans.isEmpty, "'\(name)' must not reach the launcher")
        }
    }

    func test_helpAndVersionAndUsage_doNotLookForARepository() {
        for arguments in [["--help"], ["--version"], []] {
            let (sut, doubles) = makeSUT()

            _ = sut.run(arguments: arguments)

            XCTAssertTrue(doubles.locator.askedDirectories.isEmpty, "\(arguments) needs no repository")
        }
    }

    // MARK: - Helpers

    struct Doubles {
        let output = SpyOutput()
        let launcher = SpyLauncher()
        let locator = StubRepositoryLocator()
    }

    private func makeSUT() -> (sut: CommandLineRunner, doubles: Doubles) {
        let doubles = Doubles()
        let sut = CommandLineRunner(
            table: CommandTable(commands: [
                Command(name: "alpha", scriptPath: "Scripts/alpha.sh", summary: "Do the alpha work"),
            ]),
            version: "0.1.2-test",
            resourceFolder: URL(fileURLWithPath: "/resources", isDirectory: true),
            workingDirectory: URL(fileURLWithPath: "/repo/sub", isDirectory: true),
            launcher: doubles.launcher,
            repositoryLocator: doubles.locator,
            directoryInspector: StubDirectoryInspector(),
            output: doubles.output
        )
        return (sut, doubles)
    }
}

final class CommandTableTests: XCTestCase {
    func test_standardTable_mapsPrepareSimulatorToItsScript() {
        let command = CommandTable.standard.command(named: "prepare-simulator")

        XCTAssertEqual(command?.scriptPath, "Scripts/prepare-simulator.sh", "the first command runs the simulator script")
        XCTAssertEqual(command?.interpreter, .bash, "a .sh script runs through bash")
    }

    func test_pythonScripts_runThroughPython() {
        let command = Command(name: "report", scriptPath: "Scripts/report.py", summary: "Report")

        XCTAssertEqual(command.interpreter, .python, "a .py script runs through python3")
    }

    func test_lookup_ofAnUnknownNameIsNil() {
        XCTAssertNil(CommandTable.standard.command(named: "no-such-command"), "no free names")
    }
}
