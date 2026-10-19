/// How a script of the resource folder is started.
public enum Interpreter: Sendable, Equatable {
    /// `/bin/bash <path> <arguments>`. The file mode does not matter.
    case bash
    /// `python3 -B <path> <arguments>`.
    case python
}

/// A command the user can name: `devkit <name> [arguments]`.
public struct Command: Sendable, Equatable {
    /// The word after `devkit`.
    public let name: String
    /// The script, relative to the resource folder.
    public let scriptPath: String
    /// One line for the help text.
    public let summary: String

    public init(name: String, scriptPath: String, summary: String) {
        self.name = name
        self.scriptPath = scriptPath
        self.summary = summary
    }

    /// Chosen by the extension of the script: `.py` runs through Python, anything else through Bash.
    public var interpreter: Interpreter {
        scriptPath.hasSuffix(".py") ? .python : .bash
    }
}

/// The commands `devkit` knows. A name that is not in the table is never turned into a path.
public struct CommandTable: Sendable, Equatable {
    public let commands: [Command]

    public init(commands: [Command]) {
        self.commands = commands
    }

    /// The command with this exact name, or nil.
    public func command(named name: String) -> Command? {
        commands.first { $0.name == name }
    }

    /// The commands of this release.
    public static let standard = CommandTable(commands: [
        Command(
            name: "prepare-simulator",
            scriptPath: "Scripts/prepare-simulator.sh",
            summary: "Boot a simulator for a device type and OS version and print its UDID"
        ),
    ])
}
