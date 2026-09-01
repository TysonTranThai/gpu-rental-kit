#!/usr/bin/env bash
# =============================================================================
# i18n.sh — centralized installer localization loader
# =============================================================================
# Sourced by bootstrap.sh / setup.sh / router scripts. Provides:
#   i18n_init [preferred-lang...] — resolve + load a language catalog
#   tr KEY [args...]              — translate a key with $1..$9 interpolation
#   i18n_lang                     — echo the active language code
#   i18n_save_language LANG       — persist choice to $AI_CONFIG_DIR/language.conf
#   i18n_saved_language           — echo saved language (empty if none)
#   i18n_supported_languages      — echo codes from the registry (one per line)
#
# Language resolution order (first wins):
#   1. explicit argument(s) to i18n_init (e.g. from --lang)
#   2. GPU_KIT_LANG environment variable
#   3. saved preference ($AI_CONFIG_DIR/language.conf)
#   4. "en"
#
# Invalid/unknown values fall back to "en" with a warning on stderr.
# Supported languages come from config/i18n/languages.conf (one code per line,
# '#' comments allowed) so adding a language never requires editing this file.
# =============================================================================
# Source guard
if [[ -z "${_GPU_RENTAL_KIT_I18N_LOADED:-}" ]]; then
_GPU_RENTAL_KIT_I18N_LOADED="1"

I18N_DIR="${I18N_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/i18n}"
I18N_LANG="en"
export I18N_LANG

# -----------------------------------------------------------------------------
# i18n_supported_languages — list codes from the registry
# -----------------------------------------------------------------------------
i18n_supported_languages() {
    local conf="${I18N_DIR}/languages.conf"
    if [[ -f "${conf}" ]]; then
        # NOTE: never pipe through `tr` here — i18n.sh defines a shell function
        # named `tr` which shadows /usr/bin/tr, and the pipeline would recurse
        # into the function (the original I18N_K_-d crash). Use sed instead.
        sed 's/[[:space:]]//g' "${conf}" 2>/dev/null | grep -vE '^($|#)'
    else
        echo "en"
    fi
}
# -----------------------------------------------------------------------------
# i18n_lang — echo the active language code
# -----------------------------------------------------------------------------
i18n_lang() {
    echo "${I18N_LANG}"
}

# -----------------------------------------------------------------------------
# i18n_terminal_supports_emoji — 0 when flag emoji are likely to render
#
# Heuristic (never fails the installer — fallback is ASCII tags):
#   1. Explicit override: GPU_KIT_EMOJI=1 forces on, GPU_KIT_EMOJI=0 forces off.
#   2. TERM=dumb / unset, or NO_COLOR set → off.
#   3. CI environments (CI/TF_BUILD/AGENT_NAME set) → off.
#   4. Non-interactive stdout (not a TTY) → off (piped output mangles emoji).
#   5. Otherwise assume a modern UTF-8 terminal → on.
# -----------------------------------------------------------------------------
i18n_terminal_supports_emoji() {
    case "${GPU_KIT_EMOJI:-}" in
        1|true|yes) return 0 ;;
        0|false|no) return 1 ;;
    esac
    [[ -n "${NO_COLOR:-}" ]] && return 1
    case "${TERM:-}" in
        ""|dumb) return 1 ;;
    esac
    [[ -n "${CI:-}" || -n "${TF_BUILD:-}" || -n "${AGENT_NAME:-}" ]] && return 1
    [[ -t 1 ]] || return 1
    return 0
}

# -----------------------------------------------------------------------------
# i18n_is_supported LANG — 0 if supported
# -----------------------------------------------------------------------------
i18n_is_supported() {
    local lang="$1" code
    [[ -z "${lang}" ]] && return 1
    while IFS= read -r code; do
        [[ "${code}" == "${lang}" ]] && return 0
    done < <(i18n_supported_languages)
    return 1
}

# -----------------------------------------------------------------------------
# i18n_saved_language — echo saved preference or empty
# -----------------------------------------------------------------------------
i18n_saved_language() {
    local conf="${AI_CONFIG_DIR:-${HOME}/ai/config}/language.conf"
    if [[ -f "${conf}" ]]; then
        local saved
        saved="$(head -1 "${conf}" 2>/dev/null | sed 's/[[:space:]]//g' || true)"
        echo "${saved}"
    fi
}

# -----------------------------------------------------------------------------
# i18n_save_language LANG — persist preference (never overwrites with garbage)
# -----------------------------------------------------------------------------
i18n_save_language() {
    local lang="$1"
    i18n_is_supported "${lang}" || return 1
    local conf_dir="${AI_CONFIG_DIR:-${HOME}/ai/config}"
    mkdir -p "${conf_dir}" 2>/dev/null || true
    printf '%s\n' "${lang}" > "${conf_dir}/language.conf" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# i18n_init [preferred-lang...] — resolve and load
# -----------------------------------------------------------------------------
i18n_init() {
    local candidate chosen=""
    # 1. explicit arguments
    for candidate in "$@"; do
        if i18n_is_supported "${candidate}"; then
            chosen="${candidate}"
            break
        fi
    done
    # 2. environment
    if [[ -z "${chosen}" && -n "${GPU_KIT_LANG:-}" ]]; then
        if i18n_is_supported "${GPU_KIT_LANG}"; then
            chosen="${GPU_KIT_LANG}"
        else
            echo "i18n: unknown GPU_KIT_LANG '${GPU_KIT_LANG}' — falling back" >&2
        fi
    fi
    # 3. saved preference
    if [[ -z "${chosen}" ]]; then
        local saved
        saved="$(i18n_saved_language)"
        if i18n_is_supported "${saved}"; then
            chosen="${saved}"
        fi
    fi
    # 4. fallback
    [[ -z "${chosen}" ]] && chosen="en"
    i18n_load_catalog "${chosen}"
}

# -----------------------------------------------------------------------------
# tr KEY [args...] — translate with $1..$9 interpolation
# Falls back to the key itself when a translation is missing (never "undefined").
# Keys are stored in I18N_K_<KEY> scalar variables (bash-3.2 compatible, no
# associative arrays) so the same loader works on macOS dev machines.
# -----------------------------------------------------------------------------
tr() {
    local key="$1"
    shift
    # Seguridad: la clave debe ser un identificador Bash valido. Si el caller
    # pasa datos de usuario (p.ej. "-d", "4", "abc") como key, NO se construye
    # un nombre de variable invalido como I18N_K_-d (causaba el crash
    # "invalid variable name" en el selector de idioma).
    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "${key}"
        return 0
    fi
    local var="I18N_K_${key}"
    local value="${!var:-}"
    if [[ -z "${value}" ]]; then
        # Missing key: try the English catalog, else echo the key itself.
        if [[ "${I18N_LANG}" != "en" && -f "${I18N_DIR}/en.env" ]]; then
            local en_val
            en_val="$(i18n_parse_key "${key}" "${I18N_DIR}/en.env")"
            [[ -n "${en_val}" ]] && value="${en_val}"
        fi
    fi
    [[ -z "${value}" ]] && { echo "${key}"; return 0; }
    local i
    for i in 1 2 3 4 5 6 7 8 9; do
        local arg=""
        eval "arg=\${${i}:-}"
        value="${value//\$${i}/${arg}}"
    done
    printf '%s\n' "${value}"
}

# i18n_parse_key KEY FILE — extract one key's value without sourcing the file
i18n_parse_key() {
    local key="$1" file="$2" line k v
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != *=* ]] && continue
        k="${line%%=*}"
        k="${k//[[:space:]]/}"
        [[ "${k}" != "${key}" ]] && continue
        v="${line#*=}"
        if [[ "${v}" == \"*\" && "${v}" == *\" ]]; then
            v="${v#\"}"; v="${v%\"}"
        elif [[ "${v}" == \'*\' ]]; then
            v="${v#\'}"; v="${v%\'}"
        fi
        printf '%s' "${v}"
        return 0
    done < "${file}"
    return 1
}

# i18n_load_catalog LANG — parse KEY="VALUE" pairs into I18N_K_* scalars.
# Catalog files are data-only (no code execution): values are read with a
# strict regex, never eval'd, so a hostile catalog cannot run commands.
i18n_load_catalog() {
    local lang="$1"
    local file="${I18N_DIR}/${lang}.env"
    if [[ ! -f "${file}" ]]; then
        file="${I18N_DIR}/en.env"
        lang="en"
    fi
    local line key val
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
        [[ "${line}" != *=* ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        key="${key//[[:space:]]/}"
        [[ -z "${key}" ]] && continue
        [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && continue
        # Strip one pair of surrounding quotes
        if [[ "${val}" == \"*\" && "${val}" == *\" ]]; then
            val="${val#\"}"; val="${val%\"}"
        elif [[ "${val}" == \'*\' ]]; then
            val="${val#\'}"; val="${val%\'}"
        fi
        val="${val//\\$/$}"
        printf -v "I18N_K_${key}" '%s' "${val}"
    done < "${file}"
    I18N_LANG="${lang}"
    export I18N_LANG
}

fi # _GPU_RENTAL_KIT_I18N_LOADED
