#!/usr/bin/env bash
# =============================================================================
# test_localization.sh — regression tests for the two v1.4.0 field bugs
# =============================================================================
# BUG #1 (UNICODE ESCAPES): the language selector echoed literal
#   \U0001F1EC\U0001F1E7 English / \U0001F1FB\U0001F1F3 Ti\u1ebfng Vi\u1ec7t
# because plain `echo` does not expand \u escapes. The menu must render real
# UTF-8 (Tiếng Việt / 中文) or the [EN]/[VI]/[ZH] fallback, and must never
# print \U0001F / \u1 sequences.
#
# BUG #2 (PARTIAL LOCALIZATION): selecting Vietnamese saved the preference but
# setup.sh printed every stage in English. bootstrap.sh must export
# GPU_KIT_LANG, setup.sh must initialize i18n before any user-facing output,
# and the [n/15] stage lines must resolve through tr().
#
# Also covers: emoji-capability detection with ASCII fallback, invalid
# GPU_KIT_LANG handling, and UTF-8 safety of the catalogs under different
# locale environments.
# =============================================================================

TEST_NAME="localization"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

KIT_SCRIPTS="${KIT_ROOT}/scripts"
I18N_SH="${KIT_SCRIPTS}/i18n.sh"
BOOTSTRAP="${KIT_ROOT}/bootstrap.sh"
SETUP_SH="${KIT_ROOT}/setup.sh"

# =============================================================================
# 1. LANGUAGE_SELECTOR_UNICODE — no literal escape sequences anywhere
# =============================================================================

hits="$(grep -rn 'U0001F\|\\u1ebf\|\\u1ec7' "${KIT_ROOT}/bootstrap.sh" \
    "${KIT_ROOT}/setup.sh" "${KIT_ROOT}/scripts" 2>/dev/null | grep -v '^\s*#' || true)"
if [[ -z "${hits}" ]]; then
    assert_eq "clean" "clean" "no literal \\U0001F / \\u1ebf escapes in installer code"
else
    assert_eq "clean" "${hits}" "no literal \\U0001F / \\u1ebf escapes in installer code"
fi

# The selector must render real UTF-8 names and ASCII fallbacks.
menu="$(bash -c "
    set -u
    source '${I18N_SH}'
    use_emoji=0
    i18n_terminal_supports_emoji && use_emoji=1
    i=1
    while IFS= read -r code; do
        case \"\${code}\" in
            en)    flag='🇬🇧'; label='English';    tag='EN' ;;
            vi)    flag='🇻🇳'; label='Tiếng Việt'; tag='VI' ;;
            zh-CN) flag='🇨🇳'; label='中文';        tag='ZH' ;;
            *)     flag='';  label=\"\${code}\";     tag=\"\${code}\" ;;
        esac
        if [[ -n \"\${flag}\" ]] && [[ \"\${use_emoji}\" == '1' ]]; then
            echo \"\${i}) \${flag} \${label}\"
        else
            echo \"\${i}) [\${tag}] \${label}\"
        fi
        i=\$((i + 1))
    done < <(i18n_supported_languages)
" 2>&1)"

assert_contains "${menu}" "Tiếng Việt" "VIETNAMESE_RENDERING: menu shows Tiếng Việt"
assert_contains "${menu}" "中文" "CHINESE_RENDERING: menu shows 中文"
assert_contains "${menu}" "English" "ENGLISH_RENDERING: menu shows English"
if [[ "${menu}" == *'\'* ]]; then
    assert_eq "no-escapes" "escapes: ${menu}" "menu output has no backslash escapes"
else
    assert_eq "no-escapes" "no-escapes" "menu output has no backslash escapes"
fi

# Fallback mode: [EN]/[VI]/[ZH] tags, still real UTF-8 labels.
fallback="$(GPU_KIT_EMOJI=0 bash -c "
    set -u
    source '${I18N_SH}'
    use_emoji=0
    i18n_terminal_supports_emoji && use_emoji=1
    echo \"emoji=\${use_emoji}\"
    i=1
    while IFS= read -r code; do
        tag=''
        case \"\${code}\" in
            en)    tag='EN' ;;
            vi)    tag='VI' ;;
            zh-CN) tag='ZH' ;;
        esac
        echo \"\${i}) [\${tag}]\"
        i=\$((i + 1))
    done < <(i18n_supported_languages)
" 2>&1)"
assert_contains "${fallback}" "emoji=0" "GPU_KIT_EMOJI=0 disables emoji detection"
assert_contains "${fallback}" "1) [EN]" "fallback shows [EN]"
assert_contains "${fallback}" "2) [VI]" "fallback shows [VI]"
assert_contains "${fallback}" "3) [ZH]" "fallback shows [ZH]"

# Emoji override forces the flags on.
forced="$(GPU_KIT_EMOJI=1 bash -c "
    set -u
    source '${I18N_SH}'
    i18n_terminal_supports_emoji && echo on || echo off
" 2>&1)"
assert_contains "${forced}" "on" "GPU_KIT_EMOJI=1 forces emoji on"

# =============================================================================
# 2. VIETNAMESE / CHINESE / ENGLISH rendering through tr()
# =============================================================================

for lang in en vi zh-CN; do
    out="$(bash -c "
        set -u
        source '${I18N_SH}'
        i18n_init '${lang}'
        echo \"\$(tr STAGE_PRIVILEGES)\"
        echo \"\$(tr STAGE_GPU)\"
        echo \"\$(tr CONFIRM_INSTALL_LIST)\"
        echo \"\$(tr ERR_SETUP_FAILED)\"
    " 2>&1)"
    status=$?
    assert_eq "0" "${status}" "${lang}: catalog strings render"
    if [[ "${out}" == *'\'* ]]; then
        assert_eq "clean" "escapes: ${out}" "${lang}: no escape artifacts in output"
    else
        assert_eq "clean" "clean" "${lang}: no escape artifacts in output"
    fi
done

vi_out="$(bash -c "
    set -u
    source '${I18N_SH}'
    i18n_init vi
    tr STAGE_GPU
" 2>&1)"
assert_contains "${vi_out}" "Phát hiện GPU" "vi: STAGE_GPU is Vietnamese"

zh_out="$(bash -c "
    set -u
    source '${I18N_SH}'
    i18n_init zh-CN
    tr STAGE_GPU
" 2>&1)"
assert_contains "${zh_out}" "检测 GPU" "zh-CN: STAGE_GPU is Chinese"

en_out="$(bash -c "
    set -u
    source '${I18N_SH}'
    i18n_init en
    tr STAGE_GPU
" 2>&1)"
assert_contains "${en_out}" "Detecting GPU" "en: STAGE_GPU is English"

# =============================================================================
# 3. FULL INSTALLER LOCALIZATION — bootstrap exports the language and
#    setup.sh initializes i18n before any output (BUG #2 regression)
# =============================================================================

grep -q 'export GPU_KIT_LANG=' "${BOOTSTRAP}" \
    && assert_eq "0" "0" "bootstrap.sh exports GPU_KIT_LANG for setup.sh" \
    || assert_eq "0" "1" "bootstrap.sh exports GPU_KIT_LANG for setup.sh"

grep -q 'source "${SCRIPT_DIR}/scripts/i18n.sh"' "${SETUP_SH}" \
    && assert_eq "0" "0" "setup.sh sources i18n.sh" \
    || assert_eq "0" "1" "setup.sh sources i18n.sh"

grep -q 'i18n_init' "${SETUP_SH}" \
    && assert_eq "0" "0" "setup.sh calls i18n_init" \
    || assert_eq "0" "1" "setup.sh calls i18n_init"

# Every [n/15] stage header must resolve through tr().
unlocalized="$(grep -nE '\[[0-9]+/15\] [A-Z][a-z]' "${SETUP_SH}" | grep -v 'tr ' || true)"
if [[ -z "${unlocalized}" ]]; then
    assert_eq "clean" "clean" "all [n/15] stage headers use tr()"
else
    assert_eq "clean" "${unlocalized}" "all [n/15] stage headers use tr()"
fi

# GPU_KIT_LANG must drive catalog resolution (i18n_init precedence #2).
out="$(GPU_KIT_LANG=vi bash -c "
    set -u
    source '${I18N_SH}'
    i18n_init
    i18n_lang
" 2>&1)"
assert_contains "${out}" "vi" "GPU_KIT_LANG=vi initializes Vietnamese"

out="$(GPU_KIT_LANG=zh-CN bash -c "
    set -u
    source '${I18N_SH}'
    i18n_init
    i18n_lang
" 2>&1)"
assert_contains "${out}" "zh-CN" "GPU_KIT_LANG=zh-CN initializes Chinese"

# Invalid language falls back to English safely.
out="$(GPU_KIT_LANG=xx bash -c "
    set -u
    source '${I18N_SH}'
    i18n_init 2>/dev/null
    i18n_lang
" 2>&1)"
assert_contains "${out}" "en" "GPU_KIT_LANG=xx falls back to en"

# =============================================================================
# 4. STORAGE warnings resolve through tr() in all languages
# =============================================================================

for lang in en vi zh-CN; do
    out="$(bash -c "
        set -u
        source '${I18N_SH}'
        i18n_init '${lang}'
        tr STORAGE_WARN_PERSISTENCE_UNKNOWN
    " 2>&1)"
    if [[ "${lang}" == "en" ]]; then
        assert_contains "${out}" "PERSISTENCE UNKNOWN" "en: storage warning present"
    elif [[ "${lang}" == "vi" ]]; then
        assert_contains "${out}" "KHÔNG XÁC ĐỊNH ĐỘ BỀN LƯU TRỮ" "vi: storage warning is Vietnamese"
    else
        assert_contains "${out}" "存储持久性未知" "zh-CN: storage warning is Chinese"
    fi
done

# =============================================================================
# 5. UTF-8 safety — catalogs render correctly under different locales
# =============================================================================

for loc in en_US.UTF-8 vi_VN.UTF-8 zh_CN.UTF-8 C; do
    out="$(LANG="${loc}" LC_ALL="${loc}" bash -c "
        set -u
        source '${I18N_SH}'
        i18n_init vi
        tr SELECT_LANGUAGE_PROMPT >/dev/null
        tr STAGE_GPU
    " 2>&1)"
    status=$?
    assert_eq "0" "${status}" "locale ${loc}: Vietnamese strings load without error"
    if [[ "${loc}" == "C" ]]; then
        # Under the C locale bash still passes bytes through untouched.
        assert_contains "${out}" "GPU" "locale ${loc}: bytes pass through"
    fi
done

report_results
