#!/usr/bin/env bash
# =============================================================================
# test_i18n_selector.sh — language selector regression (I18N_K_-d crash)
# =============================================================================
# Field regression (v1.4.0 report): on a real Ubuntu 22.04 root container the
# language selector crashed with
#
#     /root/gpu-rental-kit/scripts/i18n.sh: line 127: I18N_K_-d: invalid variable name
#
# and rendered "Choice [1-0]" instead of "Choice [1-3]".
#
# Root cause: i18n_supported_languages() piped `grep | tr -d ' \r'`, but
# scripts/i18n.sh defines a shell function named `tr` that SHADOWS /usr/bin/tr.
# Inside the function the pipeline called the function with $1="-d", and tr()
# built the dynamic variable name I18N_K_-d — invalid because of the '-'.
#
# This test proves:
#   - the selector menu renders 1..3 with all three language codes
#   - choice 1/2/3 resolves to en/vi/zh-CN respectively
#   - malformed input (0, 4, abc, empty, '-') cannot become a variable name
#   - tr() with a non-identifier key echoes the key (never builds I18N_K_-d)
#   - i18n_supported_languages() strips CR/space (no tr-shadowing dependency)
# =============================================================================

TEST_NAME="i18n_selector"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

KIT_SCRIPTS="${KIT_ROOT}/scripts"
I18N_SH="${KIT_SCRIPTS}/i18n.sh"

# =============================================================================
# 1. tr() with an unsafe key must echo the key, never build I18N_K_-d
# =============================================================================

out="$(bash -c "
    set -u
    source '${I18N_SH}'
    tr '-d' 2>&1
" 2>&1; echo "rc=$?")"
assert_contains "${out}" "rc=0" "tr '-d' exits 0 (no invalid-variable-name crash)"
assert_contains "${out}" "-d" "tr '-d' echoes the raw key"
if [[ "${out}" == *"invalid variable name"* ]]; then
    assert_eq "clean" "crash" "tr '-d' must not crash"
else
    assert_eq "clean" "clean" "tr '-d' must not crash"
fi

# Prove the hostile form directly: the exact field failure must be impossible.
for bad in '-d' '0' '4' 'abc' '' '-n' 'x y' '--help' 'a=b'; do
    out="$(bash -c "
        set -u
        source '${I18N_SH}'
        tr -- '${bad}' 2>&1
    " 2>&1)"
    status=$?
    assert_eq "0" "${status}" "tr with hostile key '${bad}' exits 0"
    if [[ "${out}" == *"invalid variable name"* ]]; then
        assert_eq "no-crash" "crash: ${out}" "hostile key '${bad}' never crashes"
    else
        assert_eq "no-crash" "no-crash" "hostile key '${bad}' never crashes"
    fi
done

# =============================================================================
# 2. Registry + catalog loading (the engine behind the selector)
# =============================================================================

langs="$(bash -c "
    set -u
    source '${I18N_SH}'
    i18n_supported_languages 2>&1 | paste -sd' ' -
" 2>&1)"
assert_contains "${langs}" "en" "registry lists en"
assert_contains "${langs}" "vi" "registry lists vi"
assert_contains "${langs}" "zh-CN" "registry lists zh-CN"

for lang in en vi zh-CN; do
    out="$(bash -c "
        set -u
        source '${I18N_SH}'
        i18n_init '${lang}' 2>&1
        echo \"lang=\$(i18n_lang)\"
        echo \"title=\$(tr INSTALLER_TITLE)\"
    " 2>&1)"
    status=$?
    assert_eq "0" "${status}" "${lang}: i18n_init exits 0"
    assert_contains "${out}" "lang=${lang}" "${lang}: catalog loaded"
    if [[ "${out}" == *"invalid variable name"* ]]; then
        assert_eq "no-crash" "crash: ${out}" "${lang}: no variable-name errors"
    else
        assert_eq "no-crash" "no-crash" "${lang}: no variable-name errors"
    fi
done

# The three selector entries must resolve through i18n_init
for pair in "1 en" "2 vi" "3 zh-CN"; do
    choice="${pair%% *}"
    lang="${pair#* }"
    out="$(bash -c "
        set -u
        source '${I18N_SH}'
        codes=()
        while IFS= read -r code; do
            codes+=(\"\${code}\")
        done < <(i18n_supported_languages)
        # Same numeric-range mapping the selector uses in bootstrap.sh
        sel=''
        if [[ '${choice}' =~ ^[0-9]+\$ ]] && [[ '${choice}' -ge 1 ]] && [[ '${choice}' -le \${#codes[@]} ]]; then
            sel=\"\${codes[\$(( ${choice} - 1 ))]}\"
        fi
        i18n_load_catalog \"\${sel}\"
        echo \"\$(i18n_lang)\"
    " 2>&1)"
    assert_eq "${lang}" "${out}" "choice ${choice} resolves to ${lang}"
done

# =============================================================================
# 3. Selector menu rendering (choice prompt shows the real range 1-3)
# =============================================================================

menu="$(bash -c "
    set -u
    source '${I18N_SH}'
    i=1
    while IFS= read -r code; do
        case \"\${code}\" in
            en)    echo \"  \${i}) English\" ;;
            vi)    echo \"  \${i}) Tiếng Việt\" ;;
            zh-CN) echo \"  \${i}) 中文\" ;;
            *)     echo \"  \${i}) \${code}\" ;;
        esac
        i=\$((i + 1))
    done < <(i18n_supported_languages)
    printf 'Choice [1-%d]: ' \$((i - 1))
" 2>&1)"
assert_contains "${menu}" "Choice [1-3]" "menu prompt shows 1-3 (not 1-0)"
assert_contains "${menu}" "1) English"   "menu entry 1 is English"
assert_contains "${menu}" "2) Tiếng Việt" "menu entry 2 is Vietnamese"
assert_contains "${menu}" "3) 中文"       "menu entry 3 is Chinese"

# =============================================================================
# 4. Invalid-choice retry loop (mirrors bootstrap.sh selector loop)
# =============================================================================

for bad in 0 4 abc '' '-' '1 2' '$PATH'; do
    out="$(printf '%s\n1\n' "${bad}" | bash -c "
        set -u
        source '${I18N_SH}'
        codes=()
        while IFS= read -r code; do
            codes+=(\"\${code}\")
        done < <(i18n_supported_languages)
        lang_count=\${#codes[@]}
        SELECTED_LANG=''
        while [[ -z \"\${SELECTED_LANG}\" ]]; do
            read -r lang_choice || lang_choice=''
            if [[ \"\${lang_choice}\" =~ ^[0-9]+\$ ]] && [[ \"\${lang_choice}\" -ge 1 ]] && [[ \"\${lang_choice}\" -le \"\${lang_count}\" ]]; then
                SELECTED_LANG=\"\${codes[\$((lang_choice - 1))]}\"
            fi
        done
        echo \"resolved=\${SELECTED_LANG}\"
    " 2>&1)"
    status=$?
    assert_eq "0" "${status}" "invalid input '${bad}' then '1' exits 0"
    assert_contains "${out}" "resolved=en" "invalid '${bad}' re-prompts, then resolves en"
    if [[ "${out}" == *"invalid variable name"* || "${out}" == *"unbound variable"* ]]; then
        assert_eq "no-crash" "crash: ${out}" "invalid '${bad}' never crashes"
    else
        assert_eq "no-crash" "no-crash" "invalid '${bad}' never crashes"
    fi
done

# Out-of-range input keeps looping until valid; '9' then '3' resolves zh-CN
out="$(printf '9\n3\n' | bash -c "
    set -u
    source '${I18N_SH}'
    codes=()
    while IFS= read -r code; do
        codes+=(\"\${code}\")
    done < <(i18n_supported_languages)
    lang_count=\${#codes[@]}
    SELECTED_LANG=''
    while [[ -z \"\${SELECTED_LANG}\" ]]; do
        read -r lang_choice || lang_choice=''
        if [[ \"\${lang_choice}\" =~ ^[0-9]+\$ ]] && [[ \"\${lang_choice}\" -ge 1 ]] && [[ \"\${lang_choice}\" -le \"\${lang_count}\" ]]; then
            SELECTED_LANG=\"\${codes[\$((lang_choice - 1))]}\"
        fi
    done
    echo \"\${SELECTED_LANG}\"
" 2>&1)"
assert_contains "${out}" "zh-CN" "out-of-range input keeps looping (no crash)"

# =============================================================================
# 5. No I18N_K_-d anywhere in the codebase (the bug must never regenerate)
# =============================================================================

hits="$(grep -rn "I18N_K_-" "${KIT_ROOT}" --include='*.sh' --include='*.env' 2>/dev/null | grep -v 'test_' | grep -vE '^[^:]+:[0-9]+: *#' || true)"
if [[ -z "${hits}" ]]; then
    assert_eq "clean" "clean" "no I18N_K_-d pattern in source"
else
    assert_eq "clean" "${hits}" "no I18N_K_-d pattern in source"
fi

# =============================================================================
# 6. bootstrap.sh --lang wiring (non-interactive path)
# =============================================================================

grep -q '\-\-lang)' "${KIT_ROOT}/bootstrap.sh" \
    && assert_eq "0" "0" "bootstrap.sh parses --lang" \
    || assert_eq "0" "1" "bootstrap.sh parses --lang"# =============================================================================

report_results