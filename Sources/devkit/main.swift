import DevKitCore
import Foundation

// The composition root: the only place that names concrete types.
// bundleURL plus Resources: on macOS Bundle.resourceURL already points into the copied folder, on other systems it does not.
let resourceFolder = Bundle.module.bundleURL.appendingPathComponent("Resources", isDirectory: true)
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
