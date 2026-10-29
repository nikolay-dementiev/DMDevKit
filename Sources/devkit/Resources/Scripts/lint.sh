#!/bin/bash
#
# Lints the repository with the SwiftLint version pinned in .swiftlint.yml.
#
#   devkit lint                         lint; a warning fails the run
#   devkit lint --analyze <build log>   also run the analyzer rules, which need the
#                                       compiler invocations of an xcodebuild log, from
#                                       a build whose DerivedData is still on disk
#
# The tool is fetched once into .build/tools and checked against the pinned checksum
# before it is unpacked. Nothing is installed or upgraded on the machine.

set -euo pipefail

# Functions imported from the caller's environment could replace a tool this script trusts (shasum, cut, unzip, mv):
# only the functions it defines itself count.
while IFS= read -r FUNCTION; do unset -f "$FUNCTION"; done < <(compgen -A function)

if [ -z "${DEVKIT_REPO_ROOT:-}" ] || [ -z "${DEVKIT_RESOURCES:-}" ]; then
    echo "lint: run it as 'devkit lint'" >&2
    exit 2
fi

# A mistyped option would otherwise lint without the analyzer and still pass.
case "${1:-}" in
    "") ;;
    --analyze)
        if [ -z "${2:-}" ]; then
            echo "usage: devkit lint --analyze <xcodebuild log>" >&2
            exit 2
        fi
        ;;
    *)
        echo "usage: devkit lint [--analyze <xcodebuild log>]" >&2
        exit 2
        ;;
esac

ROOT="$DEVKIT_REPO_ROOT"
# shellcheck source=SCRIPTDIR/lib/swiftlint-tool.sh
. "$DEVKIT_RESOURCES/Scripts/lib/swiftlint-tool.sh"
VERSION="$(swiftlint_version "$ROOT" lint)"

# A folder of `included` that does not exist drops out of the lint without a word.
while IFS= read -r FOLDER; do
    if [ ! -d "$ROOT/$FOLDER" ]; then
        echo "lint: .swiftlint.yml includes $FOLDER, which does not exist" >&2
        exit 2
    fi
done < <(awk '/^included:/ { inside = 1; next } inside && /^  - / { sub(/^  - /, ""); print; next } inside { exit }' \
    "$ROOT/.swiftlint.yml")

SWIFTLINT="$(swiftlint_fetch "$ROOT" "$VERSION" lint)"

cd "$ROOT"
# Not --quiet: the summary names how many files were linted.
STATUS=0
REPORT="$("$SWIFTLINT" lint --strict 2>&1)" || STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    printf '%s\n' "$REPORT" | grep -vE "^Linting '" >&2
    exit "$STATUS"
fi
LINTED="$(printf '%s\n' "$REPORT" | sed -n 's/^Done linting!.* in \([0-9][0-9]*\) files*\.$/\1/p')"
if [ -z "$LINTED" ] || [ "$LINTED" -eq 0 ]; then
    printf '%s\n' "$REPORT" >&2
    echo "lint: SwiftLint linted no file" >&2
    exit 2
fi

ANALYZED=""
if [ "${1:-}" = "--analyze" ]; then
    # Not --quiet: the summary names how many files were analyzed. A log without compiler
    # invocations, or one whose file lists left with their DerivedData, gets no file analyzed
    # and SwiftLint still exits 0.
    STATUS=0
    REPORT="$("$SWIFTLINT" analyze --strict --compiler-log-path "$2" 2>&1)" \
        || STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        printf '%s\n' "$REPORT" >&2
        exit "$STATUS"
    fi
    FILES="$(printf '%s\n' "$REPORT" | sed -n 's/^Done analyzing!.* in \([0-9][0-9]*\) files*\.$/\1/p')"
    if [ -z "$FILES" ] || [ "$FILES" -eq 0 ]; then
        printf '%s\n' "$REPORT" >&2
        echo "lint: the analyzer read no Swift file. It needs the log of a build whose DerivedData is still on disk." >&2
        exit 2
    fi
    ANALYZED=", the analyzer read $FILES files"
fi

echo "lint: no violations (SwiftLint $("$SWIFTLINT" version)) in $LINTED files$ANALYZED."
