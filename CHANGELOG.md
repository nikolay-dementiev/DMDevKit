# Changelog

All notable changes to DMDevKit are written here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- The command `check-release` (`<version>`, `--notes <version>`, `--self-test`), taken from DMVariableBlurView. It reads `FROZEN_POD_VERSION` and `MODULE` or `PODSPEC` from `devkit.conf` (`--notes` reads none), and compares the interface with the previous release through `check-api --since`.
- The commands `export-coverage` (taken from the libraries, where the three copies are the same; the source root is the repository `devkit` gives) and `count-tests` (one reader of the test count for the inline steps of the three libraries' workflows, with the wide pattern for test methods). The check of the exporter is part of the tests of DMDevKit.

### Changed

- `devkit` no longer passes `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS`, `PS4` or an exported function (`BASH_FUNC_*`) of its own environment to a script. An exported `compgen` could defeat the line with which a script clears the functions it inherits.

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
