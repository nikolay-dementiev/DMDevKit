#!/bin/bash
#
# Proves that the scripts of a library which forward to DMDevKit forward faithfully. It needs no network
# and no DMDevKit: `swift` is a shim that records how it was called, and `xcrun` and `curl` are
# shims that fail, so a script that does its own work instead of forwarding cannot reach the
# simulator or the network.
#
#   devkit check-wrappers [<folder with the wrappers>]
#
# The folder is Scripts/ of the repository unless one is given. The wrappers are the files that
# WRAPPERS lists in devkit.conf, such as WRAPPERS=(lint.sh prepare-simulator.sh): file names relative
# to the folder, each the name of a devkit command and then ".sh". The list is the contract; a
# library that sets none gets status 2, so that a pass always means that named files were checked.
# Each wrapper, copied into a scratch repository that has a Tools/ folder, is checked for these:
#
# 1. The shim is called once, as `run --quiet --package-path Tools devkit <command> <arguments>`,
#    from the root of the repository, even when the script is started in another directory. The
#    arguments reach it as they were given: plain, with a space, with a newline, empty, a star, a
#    dash, with quotes.
# 2. Started with no argument and from its own folder, it passes none, and finds the root.
# 3. The status of the shim is the status of the script: 0, 1, 2, 64, 70 and 130.
# 4. Standard output and standard error are the shim's, byte for byte, with nothing added, whatever
#    the status. The script that prints a simulator's UDID depends on this.
# 5. The script ends in an exec: the process that was started is the process of the shim, so a
#    signal sent to the script reaches devkit.
# 6. DEVELOPER_DIR, the Xcode a job selects, reaches swift as the caller had it: set to a value, and
#    not set at all. A wrapper that unsets it, or sets a default of its own, fails.
# 7. Standard input reaches swift byte for byte, bytes that are not text included. A wrapper that
#    reads it from /dev/null fails.
# 8. The first line is exactly #!/bin/bash. A text check on purpose: on macOS /bin/sh is bash in POSIX
#    mode and runs a wrapper that finds its own folder with a variable only bash has, which dash does
#    not, so running the wrapper alone would pass a #!/bin/sh wrapper that breaks on a Linux runner.
#    #!/usr/bin/env bash is
#    refused too: a wrapper must not depend on the bash that the PATH of the caller finds.
#
# All of it is checked in a scratch repository whose path holds a space, so that a wrapper which
# does not quote the root it changes to, or the path of its own folder, fails.
#
# A *.sh file of the folder that is not listed fails when a line that is not a comment runs devkit: the word
# devkit, blanks, and the name of one of its commands, such as `devkit lint`. The message names the file.
# A line that only spells those words, an echo for instance, is taken for a run: list the script, or reword it.
#
# Exit codes: 0 all hold, 1 one does not, 2 wrong usage, a setting that is missing or wrong, or a
# wrapper missing from the folder.

set -euo pipefail

# Functions imported from the caller's environment could replace a tool this script trusts (cp, cmp):
# only the functions it defines itself count.
while IFS= read -r FUNCTION; do unset -f "$FUNCTION"; done < <(compgen -A function)

if [ -z "${DEVKIT_REPO_ROOT:-}" ] || [ -z "${DEVKIT_RESOURCES:-}" ] || [ -z "${DEVKIT_CONF:-}" ]; then
    echo "check-wrappers: run it as 'devkit check-wrappers'" >&2
    exit 2
fi
if [ "$#" -gt 1 ]; then
    echo "usage: devkit check-wrappers [<folder>]" >&2
    exit 2
fi
FOLDER="${1:-$DEVKIT_REPO_ROOT/Scripts}"
case "$FOLDER" in
    /*) ;;
    *) FOLDER="$PWD/$FOLDER" ;;
esac

# shellcheck source=SCRIPTDIR/lib/devkit-conf.sh
. "$DEVKIT_RESOURCES/Scripts/lib/devkit-conf.sh"
devkit_conf_load || exit 2
if [ "${#WRAPPERS[@]}" -eq 0 ]; then
    echo "check-wrappers: devkit.conf sets no WRAPPERS; list the scripts that forward to devkit" >&2
    exit 2
fi
FILES=("${WRAPPERS[@]}")
STEMS=()
for FILE in "${FILES[@]}"; do
    case "$FILE" in
        */* | .sh)
            echo "check-wrappers: WRAPPERS entry '$FILE' must be a file name of the folder, ending in .sh" >&2
            exit 2
            ;;
        *.sh) ;;
        *)
            echo "check-wrappers: WRAPPERS entry '$FILE' must end in .sh; only shell wrappers are checked" >&2
            exit 2
            ;;
    esac
    STEM="${FILE%.sh}"
    if [ ! -f "$DEVKIT_RESOURCES/Scripts/$STEM.sh" ] && [ ! -f "$DEVKIT_RESOURCES/Scripts/$STEM.py" ]; then
        echo "check-wrappers: WRAPPERS entry '$FILE': devkit has no command '$STEM'" >&2
        exit 2
    fi
    if [ ! -f "$FOLDER/$FILE" ]; then
        echo "check-wrappers: $FOLDER/$FILE does not exist" >&2
        exit 2
    fi
    STEMS+=("$STEM")
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-wrappers.XXXXXX")" || {
    echo "check-wrappers: cannot make a scratch folder in ${TMPDIR:-/tmp}" >&2
    exit 2
}
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {  # The EXIT trap below calls it. skipcq: SH-2329
    rm -rf "$WORK"
}
trap cleanup EXIT
# The runs below change directory before they open their files, so the folder must not depend on where they start.
WORK="$(cd "$WORK" && pwd -P)"

FAILURES=0
CHECKS=0
fail() {  # <message>
    FAILURES=$((FAILURES + 1))
    echo "check-wrappers: FAIL $1" >&2
}

REPO_DIR="$WORK/a repo with spaces"
mkdir "$WORK/bin" "$REPO_DIR" "$REPO_DIR/Scripts" "$REPO_DIR/Tools" "$WORK/elsewhere" || {
    echo "check-wrappers: cannot make the scratch repository in $WORK" >&2
    exit 2
}
for FILE in "${FILES[@]}"; do
    cp -p "$FOLDER/$FILE" "$REPO_DIR/Scripts/$FILE" || {
        echo "check-wrappers: cannot copy $FILE into the scratch repository" >&2
        exit 2
    }
done
REPO="$(cd "$REPO_DIR" && pwd -P)"

# The shim writes one record for each call: CALL, the physical working directory and every
# argument, each ended by a NUL byte, so that an argument with a space or a newline stays one. It
# also writes its process id, which equals the one that run() started only if the script exec'd it.
cat > "$WORK/bin/swift" <<'SHIM'
#!/bin/bash
{
    printf 'CALL\0%s\0' "$(pwd -P)"
    for ARGUMENT in "$@"; do
        printf '%s\0' "$ARGUMENT"
    done
} >> "$SHIM_LOG"
printf '%s' "$$" > "$SHIM_PID"
if [ -n "${DEVELOPER_DIR+x}" ]; then printf 'set:%s' "$DEVELOPER_DIR"; else printf 'unset'; fi > "$SHIM_DEVELOPER_DIR"
cat > "$SHIM_STDIN"
echo "out from the shim"
echo "err from the shim" >&2
exit "${SHIM_STATUS:-0}"
SHIM
printf '#!/bin/sh\nexit 99\n' > "$WORK/bin/xcrun"
printf '#!/bin/sh\nexit 99\n' > "$WORK/bin/curl"
chmod 755 "$WORK/bin/swift" "$WORK/bin/xcrun" "$WORK/bin/curl"

STATUS=0
# The Xcode a job selects for the build. A wrapper must leave it as it found it, set to this value or
# not set at all; $CALLER_DEVELOPER_DIR is what run() gives the script, "unset" for no value.
DEVELOPER_DIR_SENTINEL="/check-wrappers/xcode-sentinel"
CALLER_DEVELOPER_DIR="$DEVELOPER_DIR_SENTINEL"
# run <path of the script> <directory to start it in> <status the shim ends with> [arguments...]
# Leaves the record of the shim in $WORK/log, the streams in $WORK/stdout and $WORK/stderr, the
# DEVELOPER_DIR it saw in $WORK/shim.developer-dir, and the status of the script in $STATUS. A small
# launcher writes its process id and then execs the script, so that $WORK/launcher.pid can be
# compared with the id the shim wrote to $WORK/shim.pid.
run() {
    local script="$1" directory="$2" shim_status="$3"
    shift 3
    : > "$WORK/log"
    rm -f "$WORK/launcher.pid" "$WORK/shim.pid" "$WORK/shim.developer-dir" "$WORK/shim.stdin"
    STATUS=0
    (cd "$directory" &&
        if [ "$CALLER_DEVELOPER_DIR" = unset ]; then unset DEVELOPER_DIR; else export DEVELOPER_DIR="$CALLER_DEVELOPER_DIR"; fi &&
        PATH="$WORK/bin:$PATH" SHIM_LOG="$WORK/log" SHIM_PID="$WORK/shim.pid" \
        SHIM_DEVELOPER_DIR="$WORK/shim.developer-dir" SHIM_STDIN="$WORK/shim.stdin" SHIM_STATUS="$shim_status" \
        LAUNCHER_PID="$WORK/launcher.pid" \
        sh -c 'echo $$ > "$LAUNCHER_PID"; exec "$@"' sh "$script" "$@" \
        < "$WORK/stdin.bytes" > "$WORK/stdout" 2> "$WORK/stderr") || STATUS=$?
}

# expect <command> [arguments...]: the one record that a faithful script leaves, in $WORK/expected.
expect() {
    {
        printf 'CALL\0'
        printf '%s\0' "$REPO" run --quiet --package-path Tools devkit "$@"
    } > "$WORK/expected"
}

# Shows a record on one line, for a message.
show() {
    tr '\0' ' ' < "$1"
}

printf 'in\0put\nno final newline' > "$WORK/stdin.bytes"
printf 'out from the shim\n' > "$WORK/expected.out"
printf 'err from the shim\n' > "$WORK/expected.err"
NEWLINE_ARGUMENT=$'two\nlines'

for STEM in "${STEMS[@]}"; do
    SCRIPT="$REPO_DIR/Scripts/$STEM.sh"
    BEFORE=$FAILURES

    CHECKS=$((CHECKS + 1))
    run "$SCRIPT" "$WORK/elsewhere" 0 plain "two words" "$NEWLINE_ARGUMENT" "" '*' -x 'say "hi"' "it's"
    expect "$STEM" plain "two words" "$NEWLINE_ARGUMENT" "" '*' -x 'say "hi"' "it's"
    if [ "$STATUS" -ne 0 ] || ! cmp -s "$WORK/log" "$WORK/expected"; then
        fail "$STEM.sh started in another directory: expected the call [$(show "$WORK/expected")], got [$(show "$WORK/log")], status $STATUS"
    fi
    if ! cmp -s "$WORK/stdout" "$WORK/expected.out" || ! cmp -s "$WORK/stderr" "$WORK/expected.err"; then
        fail "$STEM.sh started with arguments printed [$(cat "$WORK/stdout")] on standard output and [$(cat "$WORK/stderr")] on standard error, not the output of the shim alone"
    fi

    CHECKS=$((CHECKS + 1))
    run "./$STEM.sh" "$REPO_DIR/Scripts" 0
    expect "$STEM"
    if [ "$STATUS" -ne 0 ] || ! cmp -s "$WORK/log" "$WORK/expected"; then
        fail "$STEM.sh started from its own folder with no argument: expected the call [$(show "$WORK/expected")], got [$(show "$WORK/log")], status $STATUS"
    fi

    CHECKS=$((CHECKS + 1))
    for WANTED in 0 1 2 64 70 130; do
        run "$SCRIPT" "$WORK/elsewhere" "$WANTED"
        if [ "$STATUS" -ne "$WANTED" ]; then
            fail "$STEM.sh ended with status $STATUS where the shim ended with $WANTED"
        fi
        if ! cmp -s "$WORK/stdout" "$WORK/expected.out"; then
            fail "$STEM.sh printed [$(cat "$WORK/stdout")] on standard output when the shim ended with $WANTED, not the output of the shim alone"
        fi
        if ! cmp -s "$WORK/stderr" "$WORK/expected.err"; then
            fail "$STEM.sh printed [$(cat "$WORK/stderr")] on standard error when the shim ended with $WANTED, not the output of the shim alone"
        fi
    done

    CHECKS=$((CHECKS + 1))
    run "$SCRIPT" "$WORK/elsewhere" 0
    if [ "$(cat "$WORK/launcher.pid" 2> /dev/null)" != "$(cat "$WORK/shim.pid" 2> /dev/null)" ] ||
        [ ! -s "$WORK/shim.pid" ]; then
        fail "$STEM.sh did not exec swift: process $(cat "$WORK/launcher.pid" 2> /dev/null) started it and process $(cat "$WORK/shim.pid" 2> /dev/null) ran swift"
    fi

    CHECKS=$((CHECKS + 1))
    for CALLER_DEVELOPER_DIR in "$DEVELOPER_DIR_SENTINEL" unset; do
        run "$SCRIPT" "$WORK/elsewhere" 0
        if [ "$CALLER_DEVELOPER_DIR" = unset ]; then WANTED="unset"; else WANTED="set:$CALLER_DEVELOPER_DIR"; fi
        SEEN="$(cat "$WORK/shim.developer-dir" 2> /dev/null || true)"
        if [ "$SEEN" != "$WANTED" ]; then
            fail "$STEM.sh changed DEVELOPER_DIR: the caller had [$WANTED] and swift saw [$SEEN]"
        fi
    done
    CALLER_DEVELOPER_DIR="$DEVELOPER_DIR_SENTINEL"

    CHECKS=$((CHECKS + 1))
    IFS= read -r FIRST_LINE < "$SCRIPT" || true
    if [ "$FIRST_LINE" != "#!/bin/bash" ]; then
        fail "$STEM.sh starts with [$FIRST_LINE], not [#!/bin/bash]"
    fi

    CHECKS=$((CHECKS + 1))
    run "$SCRIPT" "$WORK/elsewhere" 0
    if ! cmp -s "$WORK/shim.stdin" "$WORK/stdin.bytes"; then
        GOT="$({ wc -c < "$WORK/shim.stdin"; } 2> /dev/null | tr -d ' ' || true)"
        fail "$STEM.sh did not pass standard input to swift: the caller sent $(wc -c < "$WORK/stdin.bytes" | tr -d ' ') bytes and swift read ${GOT:-0}"
    fi

    if [ "$FAILURES" -eq "$BEFORE" ]; then
        echo "check-wrappers: ok   $STEM.sh forwards its arguments, directory, status and streams"
    fi
done

# A script of the folder that runs devkit and is not listed is not guarded by any of the checks above. It is
# found by its text: a line that is not a comment with the word devkit, then blanks, then the name of a command
# of the bundle, as `swift run ... devkit lint` and `"$ROOT/.build/debug/devkit" count-tests` read. Only the
# *.sh files of the folder itself are looked at. A line that only spells such words, an echo for instance,
# is taken for a run: list the script, which then has to forward faithfully, or reword the line.
COMMAND_NAMES=()
for COMMAND_FILE in "$DEVKIT_RESOURCES"/Scripts/*.sh "$DEVKIT_RESOURCES"/Scripts/*.py; do
    [ -f "$COMMAND_FILE" ] || continue
    COMMAND_NAME="${COMMAND_FILE##*/}"
    COMMAND_NAMES+=("${COMMAND_NAME%.*}")
done
COMMAND_PATTERN="$(IFS='|'; echo "${COMMAND_NAMES[*]}")"
for SCRIPT_PATH in "$FOLDER"/*.sh; do
    [ -f "$SCRIPT_PATH" ] || continue
    SCRIPT_NAME="${SCRIPT_PATH##*/}"
    LISTED=0
    for FILE in "${FILES[@]}"; do
        if [ "$FILE" = "$SCRIPT_NAME" ]; then LISTED=1; fi
    done
    [ "$LISTED" -eq 0 ] || continue
    CHECKS=$((CHECKS + 1))
    RUNS="$(LC_ALL=C sed -n -E -e '/^[[:space:]]*#/d' \
        -e "s/^(.*[^[:alnum:]_-])?devkit['\"]?[[:space:]]+($COMMAND_PATTERN)([^[:alnum:]_-].*)?\$/\\2/p" "$SCRIPT_PATH" | sed -n '1p')"
    if [ -n "$RUNS" ]; then
        fail "$SCRIPT_NAME runs 'devkit $RUNS' and is not in WRAPPERS: list it in devkit.conf, or stop it from running devkit"
    fi
done

if [ "$FAILURES" -gt 0 ]; then
    echo "check-wrappers: $FAILURES failures in $CHECKS checks of ${#STEMS[@]} scripts" >&2
    exit 1
fi
if [ "${#STEMS[@]}" -eq 1 ]; then
    echo "check-wrappers: the 1 script forwards to devkit as it should."
else
    echo "check-wrappers: the ${#STEMS[@]} scripts forward to devkit as they should."
fi
