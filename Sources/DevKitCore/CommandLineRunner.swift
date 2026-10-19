import Foundation

/// Turns the arguments after `devkit` into the start of a script and an exit status.
public struct CommandLineRunner {
    private let table: CommandTable
    private let version: String
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
            guard table.command(named: first) != nil else {
                output.writeError("devkit: unknown command '\(first)'\n\(usage())")
                return 2
            }
            output.writeError("devkit: '\(first)' cannot run yet\n")
            return 2
        }
    }

    private func usage() -> String {
        let width = table.commands.map(\.name.count).max() ?? 0
        let lines = table.commands.map { "  \($0.name.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.summary)\n" }
        return "Usage: devkit <command> [arguments]\n       devkit --help | --version\n\nCommands:\n" + lines.joined()
    }
}
