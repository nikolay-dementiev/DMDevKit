# DMDevKit

DMDevKit is the shared development and CI tooling of DMAction, DMVariableBlurView and DMUnLoader.
It is not a library for apps. Each of those repositories uses it through a nested `Tools/Package.swift`, so their root manifests
and the dependencies of their consumers stay unchanged. The tooling is a command line tool, `devkit`, that runs the shared scripts
against the repository it is started in.

<p align="center">
  <img src="./Documentation/DMDevKit-main.svg?raw=true" alt="DMDevKit: shared development and CI tooling. Three panels: CLI with a terminal, Scripts with stacked documents, and Simulator with a phone and power button. Shared tools for the DM libraries, built as a Swift CLI for macOS." style="max-height: 400px; aspect-ratio: 1536/1024; object-fit: scale-down;">
</p>

## Commands

Run from inside a repository that has a nested `Tools/Package.swift` depending on DMDevKit:

```
swift run --package-path Tools devkit <command> [arguments]
swift run --package-path Tools devkit --help
```

| Command | What it does |
|---|---|
| `prepare-simulator <device type name> <version> [iOS\|watchOS]` | Boots a simulator for the device type and OS version and prints its UDID on standard output; progress goes to standard error. |

A command reads the settings of the repository from `devkit.conf` at the repository root (schema version 1) and gets the
paths it needs from `DEVKIT_REPO_ROOT`, `DEVKIT_RESOURCES`, `DEVKIT_CONF` and `DEVKIT_WORK`.

## Exit statuses

| Status | Meaning |
|---|---|
| 0 | The script succeeded, or `--help` or `--version` ran. |
| the script's own | Any status the script exits with. The libraries' scripts use 1 for findings and 2 for usage and configuration errors, so `devkit` leaves both to them. |
| 128 + n | A signal ended the script, or `devkit` forwarded the signal n (SIGINT is 130, SIGTERM is 143). |
| 64 | A mistake of the caller, and no script ran: no command, an unknown command, or a working directory outside a git repository. |
| 70 | `devkit` itself failed, and no script ran: the folder with the scripts is missing, git or the interpreter cannot start, or any other error of `devkit`. |

## Status

In development, no release. The CI installs `shellcheck` and `actionlint` from Homebrew at whatever version Homebrew has;
the version is printed in the log and is not pinned.
