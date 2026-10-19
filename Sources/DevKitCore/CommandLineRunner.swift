import Foundation

/// Turns the arguments after `devkit` into the start of a script and an exit status.
public struct CommandLineRunner {
    private let table: CommandTable
    private let version: String
    private let resourceFolder: URL
    private let workingDirectory: URL
    private let launcher: any ProcessLauncher
    private let repositoryLocator: any RepositoryLocator
    private let directoryInspector: any DirectoryInspector
    private let output: any TextOutput

    public init(
        table: CommandTable,
        version: String,
        resourceFolder: URL,
        workingDirectory: URL,
        launcher: any ProcessLauncher,
        repositoryLocator: any RepositoryLocator,
        directoryInspector: any DirectoryInspector,
        output: any TextOutput
    ) {
        self.table = table
        self.version = version
        self.resourceFolder = resourceFolder
        self.workingDirectory = workingDirectory
        self.launcher = launcher
        self.repositoryLocator = repositoryLocator
        self.directoryInspector = directoryInspector
        self.output = output
    }

    /// Runs one invocation and returns the exit status of `devkit`.
    public func run(arguments: [String]) -> Int32 {
        guard let first = arguments.first else {
            output.writeError(usage())
            return 2
        }
        switch first {
        case "--help":
            output.writeOut(usage())
            return 0
        case "--version":
            output.writeOut("\(version)\n")
            return 0
        default:
            guard let command = table.command(named: first) else {
                output.writeError("devkit: unknown command '\(first)'\n\(usage())")
                return 2
            }
            return launch(command, arguments: Array(arguments.dropFirst()))
        }
    }

    private func launch(_ command: Command, arguments: [String]) -> Int32 {
        do {
            guard directoryInspector.isDirectory(at: resourceFolder) else {
                throw DevKitError.missingResourceFolder(path: resourceFolder.path)
            }
            let root = try repositoryLocator.topLevel(of: workingDirectory)
            let plan = makePlan(for: command, arguments: arguments, root: root)
            return ExitMapping.status(for: try launcher.run(plan))
        } catch let error as DevKitError {
            output.writeError("devkit: \(error.message)\n")
            return 2
        } catch {
            output.writeError("devkit: \(error.localizedDescription)\n")
            return 2
        }
    }

    private func makePlan(for command: Command, arguments: [String], root: URL) -> RunPlan {
        let script = resourceFolder.appendingPathComponent(command.scriptPath).path
        let environment = [
            DevKitEnvironment.repositoryRoot: root.path,
            DevKitEnvironment.resources: resourceFolder.path,
            DevKitEnvironment.configuration: root.appendingPathComponent("devkit.conf").path,
            DevKitEnvironment.work: root.appendingPathComponent(".build/devkit", isDirectory: true).path,
        ]
        switch command.interpreter {
        case .bash:
            return RunPlan(executable: "/bin/bash", arguments: [script] + arguments, environment: environment)
        case .python:
            return RunPlan(executable: "/usr/bin/env", arguments: ["python3", "-B", script] + arguments, environment: environment)
        }
    }

    private func usage() -> String {
        let width = table.commands.map(\.name.count).max() ?? 0
        let lines = table.commands.map { "  \($0.name.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.summary)\n" }
        return "Usage: devkit <command> [arguments]\n       devkit --help | --version\n\nCommands:\n" + lines.joined()
    }
}
