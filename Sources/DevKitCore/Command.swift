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

    /// - Parameters:
    ///   - name: the word after `devkit`.
    ///   - scriptPath: the script, relative to the resource folder.
    ///   - summary: one line for the help text.
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
    /// In the order the help text lists them.
    public let commands: [Command]

    /// - Parameter commands: the commands of the table; names are expected to be unique, the first one wins.
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
        Command(
            name: "check-api",
            scriptPath: "Scripts/check-api.sh",
            summary: "Compare the public interface of the library with its committed baseline; --update, --since <ref>, " +
                "--self-test"
        ),
        Command(
            name: "export-coverage",
            scriptPath: "Scripts/export-coverage.py",
            summary: "Export the line coverage of a library target from an Xcode result bundle to LCOV: <xcresult> <target> " +
                "<output>"
        ),
        Command(
            name: "count-tests",
            scriptPath: "Scripts/count-tests.sh",
            summary: "Check that every test method of some test files ran and passed in a result bundle: [--label <text>] " +
                "<xcresult> <glob>..."
        ),
        Command(
            name: "check-release",
            scriptPath: "Scripts/check-release.sh",
            summary: "Check a release version against the changelog, the frozen podspec and the interface since the previous " +
                "release; --notes <version>, --self-test"
        ),
        Command(
            name: "check-lint-tool",
            scriptPath: "Scripts/check-lint-tool.sh",
            summary: "Prove that the SwiftLint helper stays whole when two runs overlap, with a fake archive and no network"
        ),
        Command(
            name: "check-lint-contract",
            scriptPath: "Scripts/check-lint-contract.sh",
            summary: "Prove that the lint rules of the repository fire where the fixtures of Fixtures/Lint expect"
        ),
        Command(
            name: "lint",
            scriptPath: "Scripts/lint.sh",
            summary: "Lint the repository with the SwiftLint its .swiftlint.yml pins; --analyze <log> adds the analyzer rules"
        ),
        Command(
            name: "swiftlint-fetch",
            scriptPath: "Scripts/swiftlint-fetch.sh",
            summary: "Fetch a SwiftLint version into .build/tools, checked against the checksum table, and print its path"
        )
    ])
}
