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
| `lint [--analyze <xcodebuild log>]` | Lints the repository with the SwiftLint version pinned in `.swiftlint.yml`, which must be a version in the checksum table of DMDevKit (else status 2); a warning fails the run. `--analyze` also runs the analyzer rules on the compiler invocations of the log of a build whose DerivedData is still on disk. |
| `check-lint-contract` | Proves that the lint rules of the repository fire where the fixtures in `Fixtures/Lint` expect them and nowhere else. Needs `SOURCE_DIR` and `RULES` in `devkit.conf`; `FIXTURE_DIR` defaults to `Fixtures/Lint`. Needs `python3`. |
| `check-api [--update \| --since <ref> \| --self-test]` | Compares the public interface of the library with the committed baseline `Fixtures/API/public-interface.txt`; `--update` rewrites the baseline, `--since <ref>` lists the lines the baseline lost, changed or gained since a git ref without a compiler, `--self-test` runs the normalizer cases that DMDevKit carries. Needs `MODULE` and `SOURCE_DIR` in `devkit.conf` (and `SWIFT_FLAGS`, `LIBRARY_EVOLUTION`, `DEPENDENCIES`, `PREPARE` as the library needs them); `LIBRARY_EVOLUTION` is `no` unless it says `yes`. Compiles with the iOS simulator SDK through `xcrun`. Exit statuses: 0 the same, 1 different, 2 could not run; with `--since` also 3 (lines only added) and 4 (the ref holds no baseline). Work files are in `.build/devkit/check-api`. |
| `check-release [--notes] <version> \| --self-test` | Checks a release version before a tag is pushed: the newest heading of `CHANGELOG.md` is `## [<version>] - <date>` with a real date, the podspec names `FROZEN_POD_VERSION`, the heading below it names the highest release tag below the version that the commit reaches, and a release that removed or changed a line of the interface since that tag (`check-api --since`) or declares breaking changes in its notes raises the major version. Lines that were only added pass with a reminder to review them. `--notes <version>` prints the section of the changelog and reads no `devkit.conf`; `--self-test` runs the decisions of the script in scratch repositories. Needs `FROZEN_POD_VERSION` and `MODULE` (or `PODSPEC`, relative to the repository root) in `devkit.conf`, `git` and `python3`. A `Scripts/check-api-digester.sh` of the repository, if there is one, is also asked about breaks. Exit statuses: 0 ready, 1 not ready, 2 usage or a comparison that could not be made. |
| `export-coverage <xcresult> <target> <output>` | Exports the line coverage of the library target from an Xcode result bundle to LCOV (`xccov`), for the files under `Sources/<target>` of the repository. Run with `python3`. Exit 0 written, 1 the export failed (no executable file, a bad count, `xccov` failed; nothing is written), 2 not run through `devkit`. |
| `count-tests [--label <text>] <xcresult> <glob>...` | Checks that every test method of the files the globs name (git pathspecs, tracked files) ran and passed in the result bundle: `totalTestCount` and `passedTests` equal the number of methods, `failedTests` and `skippedTests` are 0, and the number is not 0. Needs `git`, `python3` and `xcrun`. Exit 0 agree, 1 the counts disagree, 2 the check could not be made (the search or `xcresulttool` failed, unreadable summary, wrong usage). A job whose tests may skip by design keeps its own reader. |
| `check-wrappers [<folder>]` | Proves that the scripts a library keeps at their old paths, which only forward to a `devkit` command, forward faithfully. The wrappers are the files that `WRAPPERS` lists in `devkit.conf` (names relative to the folder, which is `Scripts/` of the repository unless one is given; each the name of a command and `.sh`); no list is status 2, so a pass always means that named files were checked. Each wrapper runs in a scratch repository whose path holds a space, with a `swift` that records its call, and must: call `run --quiet --package-path Tools devkit <command> <arguments>` once from the repository root, whatever directory it was started in, with the arguments as given and none added; pass the status, standard output and standard error of `swift` through unchanged; end in `exec`; leave `DEVELOPER_DIR` as the caller had it, set or not set; pass standard input on byte for byte; and start with `#!/bin/bash`. Only `.sh` wrappers are checked. Exit statuses: 0 all hold, 1 one does not, 2 usage, a setting that is missing or wrong, or a wrapper missing from the folder. |
| `check-lint-tool` | Proves, with a fake archive and no network, that the SwiftLint helper stays whole when two runs overlap and removes an archive with a wrong checksum. |
| `swiftlint-fetch <version>` | Fetches a SwiftLint version into `.build/tools` of the repository, checked against the checksum table of DMDevKit, and prints the path of the tool. A version that is not in the table is status 2. |

The SwiftLint commands need `curl` (only for the first fetch of a version), `unzip` and `shasum`. Every script clears the shell functions it inherits before it runs, and `devkit` does not pass `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS`, `PS4` or an exported function (`BASH_FUNC_*`) to a script at all, so these cannot make bash run the caller's code or replace `shasum`, `unzip`, `git` or another tool before the script starts. The caller is trusted otherwise: `PATH`, the other variables (`GIT_*` among them), and the repository and its `devkit.conf`, are the caller's to choose.

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

Release 0.3.0 has the commands `prepare-simulator`, `lint`, `check-lint-contract`, `check-lint-tool`, `swiftlint-fetch`, `check-api`, `check-release`,
`export-coverage` and `count-tests`, which is every script that the three libraries still keep as a copy except `coverage-gate.sh`, and it runs on Swift 6.4
(0.1.0 did not: it could not find its scripts there; since 0.2.0 it does, and since 0.3.0 `check-api` reads the module selectors that Swift 6.4 prints).
`coverage-gate.sh` is not a command: the three libraries keep three different versions of it. The CI installs `shellcheck` and `actionlint` from
Homebrew at whatever version Homebrew has;
the version is printed in the log and is not pinned.

DMDevKit lints itself with its own `lint` command and the rules in `.swiftlint.yml` (the rules the three libraries share, without their layer rules). The CI job `lint` runs `devkit lint` and `devkit lint --analyze` on the log of `swift build --build-tests -v`; both must report no violation.
