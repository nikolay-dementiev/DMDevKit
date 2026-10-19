# DMDevKit

DMDevKit is the shared development and CI tooling of DMAction, DMVariableBlurView and DMUnLoader.
It is not a library for apps. Each of those repositories uses it through a nested `Tools/Package.swift`, so their root manifests
and the dependencies of their consumers stay unchanged. The tooling is a command line tool, `devkit`, that runs the shared scripts
against the repository it is started in.

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

## Status

In development, no release. The CI installs `shellcheck` and `actionlint` from Homebrew at whatever version Homebrew has;
the version is printed in the log and is not pinned.
