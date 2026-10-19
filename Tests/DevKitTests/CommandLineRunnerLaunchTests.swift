import XCTest
import Foundation
import DevKitCore

final class CommandLineRunnerLaunchTests: XCTestCase {
    func test_bashCommand_launchesBinBashWithTheScriptAndTheArgumentsUnchanged() {
        let (sut, doubles) = makeSUT()
        let arguments = ["plain", "two words", "", "*", "$HOME", "line1\nline2", "quote'd \"x\""]

        _ = sut.run(arguments: ["alpha"] + arguments)

        XCTAssertEqual(doubles.launcher.plans.first?.executable, "/bin/bash", "the mode of the script file must not matter")
        XCTAssertEqual(
            doubles.launcher.plans.first?.arguments,
            ["/resources/Scripts/alpha.sh"] + arguments,
            "the script path first, then every argument as given"
        )
    }

    func test_pythonCommand_launchesPython3WithoutBytecode() {
        let (sut, doubles) = makeSUT()

        _ = sut.run(arguments: ["report", "3", "a b"])

        XCTAssertEqual(doubles.launcher.plans.first?.executable, "/usr/bin/env", "python3 is found on the PATH")
        XCTAssertEqual(
            doubles.launcher.plans.first?.arguments,
            ["python3", "-B", "/resources/Scripts/report.py", "3", "a b"],
            "-B keeps bytecode out of the resource folder"
        )
    }

    func test_launch_exportsTheFourVariablesOfThePathModel() {
        let (sut, doubles) = makeSUT()

        _ = sut.run(arguments: ["alpha"])

        XCTAssertEqual(
            doubles.launcher.plans.first?.environment,
            [
                "DEVKIT_REPO_ROOT": "/repo",
                "DEVKIT_RESOURCES": "/resources",
                "DEVKIT_CONF": "/repo/devkit.conf",
                "DEVKIT_WORK": "/repo/.build/devkit"
            ],
            "root, resources, configuration file and work folder, as explicit paths"
        )
        XCTAssertEqual(doubles.locator.askedDirectories.map(\.path), ["/repo/sub"],
            "the root is looked up from the working directory")
    }

    func test_exitStatus_isTheChildsExitCode() {
        for code: Int32 in [0, 1, 2, 7] {
            let (sut, doubles) = makeSUT()
            doubles.launcher.result = LaunchResult(outcome: .exited(code), forwardedSignal: nil)

            XCTAssertEqual(sut.run(arguments: ["alpha"]), code, "exit \(code) passes through")
        }
    }

    func test_childEndedBySignal_exitsWith128PlusTheSignal() {
        let (sut, doubles) = makeSUT()
        doubles.launcher.result = LaunchResult(outcome: .signaled(15), forwardedSignal: nil)

        XCTAssertEqual(sut.run(arguments: ["alpha"]), 143, "SIGTERM is 15")
    }

    func test_forwardedSignal_decidesTheExitStatusWhateverTheChildReturned() {
        let (sut, doubles) = makeSUT()
        doubles.launcher.result = LaunchResult(outcome: .exited(0), forwardedSignal: 2)

        XCTAssertEqual(sut.run(arguments: ["alpha"]), 130, "devkit exits 128+n for the signal n it forwarded")
    }

    func test_missingResourceFolder_isAClearErrorAndNothingStarts() {
        let (sut, doubles) = makeSUT(resourceFolderExists: false)

        let status = sut.run(arguments: ["alpha"])

        XCTAssertEqual(status, 70, "a broken installation is EX_SOFTWARE, not a status of a script")
        XCTAssertTrue(
            doubles.output.standardError.contains("the resource folder /resources is missing"),
            "the message names the folder"
        )
        XCTAssertTrue(doubles.launcher.plans.isEmpty, "nothing was started")
    }

    func test_outsideARepository_exitsSixtyFourAndNothingStarts() {
        let (sut, doubles) = makeSUT()
        doubles.locator.result = .failure(DevKitError.notInRepository(directory: "/repo/sub"))

        let status = sut.run(arguments: ["alpha"])

        XCTAssertEqual(status, 64, "a working directory outside a repository is a mistake of the caller (EX_USAGE)")
        XCTAssertTrue(doubles.output.standardError.contains("/repo/sub is not inside a git repository"),
            "the message names the directory")
        XCTAssertTrue(doubles.launcher.plans.isEmpty, "nothing was started")
    }

    func test_launcherFailure_isReportedAndExitsSeventy() {
        let (sut, doubles) = makeSUT()
        doubles.launcher.error = DevKitError.cannotStart(executable: "/bin/bash", reason: "no such file")

        let status = sut.run(arguments: ["alpha"])

        XCTAssertEqual(status, 70, "a script that could not start is EX_SOFTWARE")
        XCTAssertTrue(doubles.output.standardError.contains("cannot start /bin/bash: no such file"),
            "the message names the executable and the reason")
    }

    func test_anyOtherFailureOfDevkit_exitsSeventy() {
        struct Foreign: Error {}
        let (sut, doubles) = makeSUT()
        doubles.locator.result = .failure(Foreign())

        let status = sut.run(arguments: ["alpha"])

        XCTAssertEqual(status, 70, "an error devkit does not know is EX_SOFTWARE")
        XCTAssertTrue(doubles.launcher.plans.isEmpty, "nothing was started")
    }

    // MARK: - Helpers

    struct Doubles {
        let output = SpyOutput()
        let launcher = SpyLauncher()
        let locator = StubRepositoryLocator()
    }

    private func makeSUT(resourceFolderExists: Bool = true) -> (sut: CommandLineRunner, doubles: Doubles) {
        let doubles = Doubles()
        let sut = CommandLineRunner(
            table: CommandTable(commands: [
                Command(name: "alpha", scriptPath: "Scripts/alpha.sh", summary: "Do the alpha work"),
                Command(name: "report", scriptPath: "Scripts/report.py", summary: "Report")
            ]),
            version: "0.1.2-test",
            resourceFolder: URL(fileURLWithPath: "/resources", isDirectory: true),
            workingDirectory: URL(fileURLWithPath: "/repo/sub", isDirectory: true),
            launcher: doubles.launcher,
            repositoryLocator: doubles.locator,
            directoryInspector: StubDirectoryInspector(exists: resourceFolderExists),
            output: doubles.output
        )
        return (sut, doubles)
    }
}
