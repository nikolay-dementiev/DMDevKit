# shellcheck shell=bash
#
# Loads the settings of a repository. Scripts source this file; it is not run on its own.
#
#   devkit_conf_load     reads $DEVKIT_CONF into the shell of the caller
#
# devkit.conf is shell code that runs with the rights of the caller: review a change to it like any
# other code. Schema version 1 has these names, and no other:
#
#   DEVKIT_CONF_VERSION    must be 1
#   single values          MODULE SOURCE_DIR RULES FIXTURE_DIR LIBRARY_EVOLUTION PODSPEC FROZEN_POD_VERSION
#   arrays                 SWIFT_FLAGS DEPENDENCIES PREPARE
#
# A name the file does not set is unset, an array it does not set is empty, and a value in the
# environment is never a setting. PODSPEC defaults to $DEVKIT_REPO_ROOT/$MODULE.podspec; a relative
# PODSPEC is relative to $DEVKIT_REPO_ROOT. Status 2 and a line on standard error when the file is
# missing, has no DEVKIT_CONF_VERSION=1, sets another name, or sets a name with the wrong kind.

_DEVKIT_CONF_SCALARS="MODULE SOURCE_DIR RULES FIXTURE_DIR LIBRARY_EVOLUTION PODSPEC FROZEN_POD_VERSION"
_DEVKIT_CONF_ARRAYS="SWIFT_FLAGS DEPENDENCIES PREPARE"
# Names of the function below and the shell's own, which a snapshot of the variables can differ in.
_DEVKIT_CONF_INTERNAL=" conf name before after kind root0 res0 conf0 work0 _ OLDPWD PIPESTATUS LINENO RANDOM SECONDS BASH_COMMAND BASH_LINENO BASH_SOURCE FUNCNAME "

devkit_conf_load() {
    # The loops below split on blanks whatever the caller set IFS to.
    local IFS=$' \t\n'
    local conf="${DEVKIT_CONF:-}" name="" before="" after="" kind="" root0="${DEVKIT_REPO_ROOT-}" res0="${DEVKIT_RESOURCES-}" conf0="${DEVKIT_CONF-}" work0="${DEVKIT_WORK-}"
    if [ -z "$conf" ]; then
        echo "devkit-conf: DEVKIT_CONF is not set; run the script through devkit" >&2
        return 2
    fi
    if [ ! -r "$conf" ]; then
        echo "devkit-conf: $conf is missing or not readable" >&2
        return 2
    fi
    for name in $_DEVKIT_CONF_SCALARS $_DEVKIT_CONF_ARRAYS DEVKIT_CONF_VERSION; do
        unset "$name"
    done
    before=" $(compgen -v | tr '\n' ' ') "
    # shellcheck source=/dev/null
    if ! . "$conf"; then
        echo "devkit-conf: $conf failed to load" >&2
        return 2
    fi
    # The paths of the model are devkit's to give: a file that changes one of them would send the next script elsewhere.
    for name in DEVKIT_REPO_ROOT:"$root0" DEVKIT_RESOURCES:"$res0" DEVKIT_CONF:"$conf0" DEVKIT_WORK:"$work0"; do
        if [ "$(eval "printf '%s' \"\${${name%%:*}-}\"")" != "${name#*:}" ]; then
            echo "devkit-conf: $conf must not set ${name%%:*}; devkit gives the scripts that path" >&2
            return 2
        fi
    done
    if [ "${DEVKIT_CONF_VERSION-}" != "1" ]; then
        echo "devkit-conf: $conf must set DEVKIT_CONF_VERSION=1 (found '${DEVKIT_CONF_VERSION-}')" >&2
        return 2
    fi
    after=" $(compgen -v | tr '\n' ' ') "
    for name in $after; do
        case "$before" in *" $name "*) continue ;; esac
        case "$_DEVKIT_CONF_INTERNAL" in *" $name "*) continue ;; esac
        case " DEVKIT_CONF_VERSION $_DEVKIT_CONF_SCALARS $_DEVKIT_CONF_ARRAYS " in
            *" $name "*) ;;
            *)
                echo "devkit-conf: $conf sets '$name', which is not a setting of schema version 1" >&2
                return 2
                ;;
        esac
    done
    for name in DEVKIT_CONF_VERSION $_DEVKIT_CONF_SCALARS; do
        kind="$(declare -p "$name" 2>/dev/null || true)"
        case "$kind" in
            "declare -a "*)
                echo "devkit-conf: $name must be a single value, not an array" >&2
                return 2
                ;;
        esac
    done
    for name in $_DEVKIT_CONF_ARRAYS; do
        kind="$(declare -p "$name" 2>/dev/null || true)"
        case "$kind" in
            "declare -a "*) ;;
            "") eval "$name=()" ;;
            *)
                echo "devkit-conf: $name must be an array, as in $name=(a b)" >&2
                return 2
                ;;
        esac
    done
    _devkit_conf_resolve_podspec
}

_devkit_conf_resolve_podspec() {
    if [ -z "${PODSPEC-}" ]; then
        [ -n "${MODULE-}" ] || return 0
    fi
    case "${PODSPEC-}" in
        /*) return 0 ;;
    esac
    if [ -z "${DEVKIT_REPO_ROOT-}" ]; then
        echo "devkit-conf: DEVKIT_REPO_ROOT is not set, so PODSPEC cannot be resolved" >&2
        return 2
    fi
    PODSPEC="$DEVKIT_REPO_ROOT/${PODSPEC:-$MODULE.podspec}"
}
