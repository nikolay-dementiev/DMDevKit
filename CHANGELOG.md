# Changelog

All notable changes to DMDevKit are written here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- The `devkit` command line tool: `devkit <command> [arguments]` runs a script from a fixed table, passes arguments,
  exit codes, standard output and standard error through unchanged, and forwards SIGINT and SIGTERM to the script.
- The path model: scripts get `DEVKIT_REPO_ROOT`, `DEVKIT_RESOURCES`, `DEVKIT_CONF` and `DEVKIT_WORK` as explicit paths.
- `devkit.conf`, schema version 1, and the loader that scripts source.
- The command `prepare-simulator`.
- CI on the newest Xcode and on the Swift 6.0 floor, with shellcheck and actionlint. Both lint tools are installed from
  Homebrew and are not pinned to a version; the log prints the version that ran.
