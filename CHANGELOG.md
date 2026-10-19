# Changelog

All notable changes to DMDevKit are written here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
