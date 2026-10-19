import DevKitCore
import Foundation

// The composition root: the only place that names concrete types.
// SwiftPM puts the scripts in <package>_<target>.bundle/Resources next to the executable. The generated Bundle.module accessor traps when that
// bundle is missing, so the folder is looked up here and CommandLineRunner can say what is missing. On macOS Bundle.resourceURL
// already points into the copied folder, on other systems it does not, so the path is built from the bundle folder.
let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "devkit")
let resourceFolder = executableURL.resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .appendingPathComponent("DMDevKit_devkit.bundle/Resources", isDirectory: true)
let runner = CommandLineRunner(
    table: .standard,
    version: DevKitVersion.current,
    resourceFolder: resourceFolder,
    workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
    launcher: FoundationProcessLauncher(),
    repositoryLocator: GitRepositoryLocator(),
    directoryInspector: FileManagerDirectoryInspector(),
    output: FileHandleOutput()
)
exit(runner.run(arguments: Array(CommandLine.arguments.dropFirst())))
