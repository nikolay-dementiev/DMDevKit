# Changelog

All notable changes to DMDevKit are written here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.5.0] - 2026-10-31

The fifth release. It closes the gaps that the move of the three libraries to 0.4.0 found: the release check reads the records a release has to
update, the wrapper check finds a script it was not told about, and two messages say what happened.

### Changed

These make three checks stricter, so a library that pins this version has to fix what they find the next time it runs them: a row of
`SECURITY.md` for the release, link lines in its changelog if it uses them, and every script that runs devkit in `WRAPPERS`.

- `check-release` reads `SECURITY.md` when the repository has one. Its table of supported versions needs a row for the major and the
  minor of the release (`| 1.2.x | yes |`; `M.m.x`, `M.m.*`, `M.x` and `M.*` in any letter case), else the release is not ready; a
  covering row that says `no` is not ready either, and a file with no table of that shape is status 2. A repository without a
  `SECURITY.md` is not asked. Rows of older lines that still say `yes` are not a problem.
- `check-release` reads the link lines of the changelog when it has any (`[1.2.0]: <url>`). The line of the release has to be there, and
  an `[Unreleased]` line, if there is one, has to compare from the release (`.../compare/<version>...HEAD`); a `## [Unreleased]`
  heading with no such line is a problem too. A changelog without link lines is not asked for any. Both checks run when a library
  runs `check-release` on its tag, not on its pull requests.
- `check-wrappers` fails on a `*.sh` file of the folder that `WRAPPERS` does not list and that runs devkit: a line that is not a
  comment with the word `devkit` and the name of one of its commands. The message names the file. A line that only spells those
  words, in an `echo` for instance, is taken for a run: list the script, or reword the line.
- When git cannot find the repository, `devkit` quotes the first line git wrote (the "dubious ownership" refusal, for instance)
  where it used to say only that the folder is not inside a git repository. The status is still 64.

### Fixed

- `check-api` leaves string literals alone when it reads module selectors. A default argument that changes from `"a::b"` to `"a.b"` is
  now seen as a change. Interpolations, literals inside them, raw literals and escaped quotes are read; a literal that does not end on
  its line stays as it is to the end of that line.

## [0.4.0] - 2026-10-30

The fourth release. It has the check of the wrapper scripts, so that the three libraries can drop their copies of `check-wrappers.sh`.

### Added

- The command `check-wrappers [<folder>]`, taken from the three libraries, where one script is kept as three byte-equal copies. It checks the files that the new `devkit.conf` setting `WRAPPERS` lists (an array of file names; not set is status 2). Beyond the five properties of the copies it closes the gaps they had: the checks run in a scratch repository whose path holds a space (a wrapper that does not quote the root, or its own path, fails), `DEVELOPER_DIR` must reach `swift` as the caller had it, set or not set, standard input must arrive byte for byte, and the first line of a wrapper must be `#!/bin/bash`.
- The setting `WRAPPERS` of `devkit.conf` (an array, schema version 1). A `devkit` older than this one refuses a `devkit.conf` that sets it, so a library adds it together with the pin of the release that has this command.

## [0.3.0] - 2026-10-28

The third release. It has every command that the three libraries still keep as a copy, so that they can move their remaining scripts to it, and it
runs on Swift 6.4.

### Added

- The command `check-release` (`<version>`, `--notes <version>`, `--self-test`), taken from DMVariableBlurView. It reads `FROZEN_POD_VERSION` and `MODULE` or `PODSPEC` from `devkit.conf` (`--notes` reads none), and compares the interface with the previous release through `check-api --since`.
- The commands `export-coverage` (taken from the libraries, where the three copies are the same; the source root is the repository `devkit` gives) and `count-tests` (one reader of the test count for the inline steps of the three libraries' workflows, with the wide pattern for test methods). The check of the exporter is part of the tests of DMDevKit.

### Changed

- DMDevKit lints its own sources and tests (`.swiftlint.yml`, CI job `lint`, with the analyzer rules). Long lines were wrapped and the wrapped declarations aligned; `GitRepositoryLocator` now refuses git output that is not UTF-8 (`notInRepository`) instead of decoding it with replacement characters.
- `devkit` no longer passes `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS`, `PS4` or an exported function (`BASH_FUNC_*`) of its own environment to a script. An exported `compgen` could defeat the line with which a script clears the functions it inherits.

### Fixed

- `check-api` reads the module selectors that the interface printer of Swift 6.4 writes (`Swift::UInt`, `Type.Module::member`) as the dotted spelling of the baselines, so an unchanged interface is no longer reported as changed on Swift 6.4. The baselines stay as they are.
- `devkit lint --analyze` without the path of a log prints `usage: devkit lint --analyze <xcodebuild log>` and exits with status 2, as the usage errors of the other commands do; it used to end with status 1 and a message of bash.

## [0.2.0] - 2026-10-27

The second release. It is made so that the DMAction pilot can pin a version that runs on Swift 6.4.

### Added

- The command `check-api` (compare, `--update`, `--since <ref>`, `--self-test`), taken from DMVariableBlurView with its normalizer cases. It reads `MODULE`, `SOURCE_DIR`, `SWIFT_FLAGS`, `LIBRARY_EVOLUTION`, `DEPENDENCIES` and `PREPARE` from `devkit.conf` and writes its work files to `.build/devkit/check-api`.

### Fixed

- `devkit` finds its scripts when the build was made by the Swift Build system, the default of Swift 6.4, which puts them in `DMDevKit_devkit.bundle/Contents/Resources/Resources`. Before, it exited with status 70 and "the resource folder ... is missing".

## [0.1.0] - 2026-10-19

The first release. It is made for the pilot in DMAction, which pins this exact version; the scripts that the libraries still keep
as copies come in later releases.

### Added

- The `devkit` command line tool: `devkit <command> [arguments]` runs a script from a fixed table, passes arguments,
  exit codes, standard output and standard error through unchanged, and forwards SIGINT and SIGTERM to the script.
- The path model: scripts get `DEVKIT_REPO_ROOT`, `DEVKIT_RESOURCES`, `DEVKIT_CONF` and `DEVKIT_WORK` as explicit paths.
- `devkit.conf`, schema version 1, and the loader that scripts source.
- Exit statuses of `devkit` itself: 64 for a mistake of the caller and 70 for a failure of `devkit`, so that 1 and 2 stay the scripts' own (see the README).
- The commands `lint`, `check-lint-contract`, `check-lint-tool` and `swiftlint-fetch`, with the SwiftLint helper and a table of the checksum of each SwiftLint version DMDevKit knows (0.65.1). The scripts take the repository, the helper and the settings from the paths `devkit` gives, never from their own location.
- The command `prepare-simulator`.
- CI on the newest Xcode and on the Swift 6.0 floor, with shellcheck and actionlint. Both lint tools are installed from
  Homebrew and are not pinned to a version; the log prints the version that ran.
