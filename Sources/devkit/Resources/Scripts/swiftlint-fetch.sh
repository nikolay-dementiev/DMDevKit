#!/bin/bash
#
# Fetches the SwiftLint of one version into .build/tools of the repository and prints the path of the tool.
#
#   devkit swiftlint-fetch <version>      such as 0.65.1
#
# The archive is checked against the checksum table of DMDevKit before it is unpacked. A version that is not
# in the table is status 2. Exit codes: 0 the tool is there, 2 wrong usage or a version without a checksum;
# a failing download or unpack ends the script with its own status.

set -euo pipefail

# Functions imported from the caller's environment could replace a tool this script trusts (shasum, cut, unzip, mv):
# only the functions it defines itself count.
while IFS= read -r FUNCTION; do unset -f "$FUNCTION"; done < <(compgen -A function)

if [ -z "${DEVKIT_REPO_ROOT:-}" ] || [ -z "${DEVKIT_RESOURCES:-}" ]; then
    echo "swiftlint-fetch: run it as 'devkit swiftlint-fetch <version>'" >&2
    exit 2
fi
# shellcheck source=SCRIPTDIR/lib/swiftlint-tool.sh
. "$DEVKIT_RESOURCES/Scripts/lib/swiftlint-tool.sh"

if [ "$#" -ne 1 ] || ! valid_version "$1"; then
    echo "usage: devkit swiftlint-fetch <version>, such as 0.65.1" >&2
    exit 2
fi
swiftlint_fetch "$DEVKIT_REPO_ROOT" "$1" swiftlint-fetch
