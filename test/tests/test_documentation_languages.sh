#!/usr/bin/env bash
# =============================================================================
# test_documentation_languages.sh — documentation localization checks
# =============================================================================
# Verifies the multi-language README system stays consistent:
#   * README.md exists and every registered language file exists
#   * no duplicate language codes or paths in the registry
#   * registry codes are valid BCP 47 identifiers (no vn/cn/jp/kr)
#   * every README carries the same language selector as the registry
#   * selector only links to registered, existing translations
#   * no broken relative links or image references in any README
#   * translations keep every non-comment command from the English README
#   * translations keep every technical identifier / environment variable
#   * heading structure (## sections, ### subsections) stays in sync
#   * code-fence counts stay in sync
#   * SOURCE-REVISION markers are present; stale translations are flagged
#
# Safe on macOS: read-only against the repo (no git, no network required).
# =============================================================================
TEST_NAME="documentation-languages"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

ensure_executable

REGISTRY_FILE="${KIT_ROOT}/docs/languages.env"
GENERATOR="${KIT_ROOT}/docs/lang-selector.sh"
ALL_READMES=("README.md" "README.vi.md" "README.zh-CN.md")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# fail <message> — record a hard failure
fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  ✘ $1"
    record_failure "documentation_languages" "$1"
}

# warn <message> — informational only, never fails the suite
warn() {
    echo "  ⚠ $1"
}

# strip_comments <file> — print non-comment code lines from all code fences
strip_comments() {
    awk '
        /^```/ { in_fence = !in_fence; next }
        in_fence {
            line = $0
            sub(/^[ \t]+/, "", line)      # leading whitespace
            sub(/[ \t]+#.*$/, "", line)   # trailing comment
            sub(/[ \t]+$/, "", line)      # trailing whitespace
            if (line != "" && line !~ /^#/) print line
        }
    ' "$1"
}

# marker_of <file> — print the SOURCE-REVISION value (or empty)
marker_of() {
    grep -oE 'SOURCE-REVISION: [0-9]+' "$1" 2>/dev/null | head -1 | grep -oE '[0-9]+$' || true
}

# source_revision <file> — content id of a README, excluding its own marker
source_revision() {
    grep -v 'SOURCE-REVISION:' "$1" 2>/dev/null | cksum | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# 1. Registry file + language files exist
# ---------------------------------------------------------------------------
echo "── registry and language files ──"
if [[ -f "${REGISTRY_FILE}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ registry exists: docs/languages.env"
else
    fail "missing registry: docs/languages.env"
    report_results
    exit 1
fi

# shellcheck source=../docs/languages.env
source "${REGISTRY_FILE}"

if [[ ! -f "${KIT_ROOT}/README.md" ]]; then
    fail "missing required file: README.md"
fi

declare -a codes=() paths=()
for entry in "${LANGUAGE_REGISTRY[@]}"; do
    IFS='|' read -r code name native flag path status direction <<< "${entry}"
    [[ -n "${code}" ]] || continue
    codes+=("${code}")
    paths+=("${path}")

    # file must exist
    if [[ -f "${KIT_ROOT}/${path}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${code} → ${path} exists"
    else
        fail "${code} registered but file missing: ${path}"
    fi

    # status must be known
    case "${status}" in
        complete|partial|outdated|in-progress)
            PASS_COUNT=$((PASS_COUNT + 1)) ;;
        *)
            fail "${code} has unknown status: '${status}'" ;;
    esac

    # direction must be known
    case "${direction}" in
        ltr|rtl)
            PASS_COUNT=$((PASS_COUNT + 1)) ;;
        *)
            fail "${code} has unknown direction: '${direction}'" ;;
    esac

    # BCP 47 — no legacy identifiers
    case "${code}" in
        vn|cn|jp|kr)
            fail "${code} is not a valid BCP 47 identifier (use vi, zh-CN, ja, ko)" ;;
        *)
            PASS_COUNT=$((PASS_COUNT + 1)) ;;
    esac
done

# duplicate codes
dup_code="$(printf '%s\n' "${codes[@]}" | sort | uniq -d | tr '\n' ' ')"
if [[ -z "${dup_code}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ no duplicate language codes"
else
    fail "duplicate language codes: ${dup_code}"
fi

# duplicate paths
dup_path="$(printf '%s\n' "${paths[@]}" | sort | uniq -d | tr '\n' ' ')"
if [[ -z "${dup_path}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ no duplicate language paths"
else
    fail "duplicate language paths: ${dup_path}"
fi

# ---------------------------------------------------------------------------
# 2. Language selector — identical in every README and matches the registry
# ---------------------------------------------------------------------------
echo "── language selector ──"
if [[ ! -x "${GENERATOR}" ]] && [[ ! -f "${GENERATOR}" ]]; then
    fail "missing selector generator: docs/lang-selector.sh"
fi

expected_line="$(bash "${GENERATOR}" --line)"
expected_hrefs="$(echo "${expected_line}" | grep -oE 'href="[^"]+"' | sed 's/href="//; s/"$//')"

for f in "${ALL_READMES[@]}"; do
    [[ -f "${KIT_ROOT}/${f}" ]] || continue
    actual_line="$(grep -h 'href="README' "${KIT_ROOT}/${f}" | head -1)"
    if [[ -n "${actual_line}" ]] && [[ "${actual_line}" == "${expected_line}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${f} selector matches registry"
    else
        fail "${f} selector out of sync — run: bash docs/lang-selector.sh and update the READMEs"
    fi
done

# every selector href must resolve to a real file
for href in ${expected_hrefs}; do
    if [[ -f "${KIT_ROOT}/${href}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "selector links to missing file: ${href}"
    fi
done

# ---------------------------------------------------------------------------
# 3. Relative links + image references resolve
# ---------------------------------------------------------------------------
echo "── link validation ──"
for f in "${ALL_READMES[@]}"; do
    [[ -f "${KIT_ROOT}/${f}" ]] || continue
    # markdown links (skip http(s) and in-page anchors)
    while IFS= read -r target; do
        [[ -n "${target}" ]] || continue
        case "${target}" in
            http*|"#"*) continue ;;
        esac
        if [[ -e "${KIT_ROOT}/${target}" ]]; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            fail "${f}: broken relative link → ${target}"
        fi
    done < <(grep -oE '\]\([^)]*\)' "${KIT_ROOT}/${f}" | sed 's/^](//; s/)$//' | sort -u)
    # image src (skip http)
    while IFS= read -r src; do
        [[ -n "${src}" ]] || continue
        case "${src}" in
            http*) continue ;;
        esac
        if [[ -e "${KIT_ROOT}/${src}" ]]; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            fail "${f}: broken image reference → ${src}"
        fi
    done < <(grep -oE 'src="[^"]+"' "${KIT_ROOT}/${f}" | sed 's/src="//; s/"$//' | sort -u)
done

# ---------------------------------------------------------------------------
# 4. Structural sync — headings, code fences, commands, identifiers
# ---------------------------------------------------------------------------
echo "── translation consistency ──"
EN_README="${KIT_ROOT}/README.md"

en_h2="$(grep -c '^## ' "${EN_README}" || true)"
en_h3="$(grep -c '^### ' "${EN_README}" || true)"
en_fences="$(grep -c '^```' "${EN_README}" || true)"

# technical identifiers / env vars that must never be translated
en_idents="$(grep -oE '[A-Z][A-Z0-9_]*_[A-Z0-9_]+' "${EN_README}" | sort -u)"

REQUIRED_TERMS=(
    "GPU" "VRAM" "CUDA" "NVIDIA" "Docker" "llama.cpp" "Ollama" "vLLM"
    "PyTorch" "Hugging Face" "OpenAI" "API" "SSH" "Linux" "Windows"
    "macOS" "GPU_IDS" "GPU_MODE" "CUDA_VISIBLE_DEVICES" "NVIDIA_VISIBLE_DEVICES"
    "bootstrap.sh" "model-run" "gpu-status" "gpu-test" "ai-start" "model-download"
)

# commands from the English README that translations must keep
en_commands="$(mktemp "${TEST_TMP}/en-cmds.XXXXXX")"
strip_comments "${EN_README}" | sort -u > "${en_commands}"

# expected source revision of the English README (marker line excluded)
expected_rev="$(source_revision "${EN_README}")"

for t in "${ALL_READMES[@]:1}"; do
    T_FILE="${KIT_ROOT}/${t}"
    [[ -f "${T_FILE}" ]] || continue
    echo "  ── ${t} ──"

    # 4a. headings + fences
    t_h2="$(grep -c '^## ' "${T_FILE}" || true)"
    if [[ "${t_h2}" -eq "${en_h2}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "${t}: ${t_h2} sections vs ${en_h2} in English — a section may be missing (add the translation, then update SOURCE-REVISION)"
    fi

    t_h3="$(grep -c '^### ' "${T_FILE}" || true)"
    if [[ "${t_h3}" -eq "${en_h3}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        warn "${t}: ${t_h3} subsections vs ${en_h3} in English — review whether a subsection is missing"
    fi

    t_fences="$(grep -c '^```' "${T_FILE}" || true)"
    if [[ "${t_fences}" -eq "${en_fences}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "${t}: ${t_fences} code fences vs ${en_fences} in English — a code block may be missing"
    fi

    # 4b. every non-comment English command must survive in the translation
    t_commands="$(mktemp "${TEST_TMP}/t-cmds.XXXXXX")"
    strip_comments "${T_FILE}" | sort -u > "${t_commands}"
    cmd_missing=0
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        if ! grep -Fqx "${line}" "${t_commands}"; then
            cmd_missing=$((cmd_missing + 1))
            [[ "${cmd_missing}" -le 5 ]] && warn "${t}: missing command '${line}'"
        fi
    done < "${en_commands}"
    if [[ "${cmd_missing}" -eq 0 ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${t}: all commands preserved"
    else
        fail "${t}: ${cmd_missing} command(s) missing from translation"
    fi
    rm -f "${t_commands}"

    # 4c. technical identifiers / environment variables preserved
    ident_missing=0
    while IFS= read -r ident; do
        [[ -n "${ident}" ]] || continue
        if ! grep -Fq "${ident}" "${T_FILE}"; then
            ident_missing=$((ident_missing + 1))
            [[ "${ident_missing}" -le 5 ]] && warn "${t}: missing identifier '${ident}'"
        fi
    done <<< "${en_idents}"
    if [[ "${ident_missing}" -eq 0 ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "${t}: ${ident_missing} technical identifier(s) missing (e.g. environment variables)"
    fi

    # 4d. required technical terms preserved
    term_missing=0
    for term in "${REQUIRED_TERMS[@]}"; do
        if ! grep -Fq "${term}" "${T_FILE}"; then
            term_missing=$((term_missing + 1))
            warn "${t}: missing required term '${term}'"
        fi
    done
    if [[ "${term_missing}" -eq 0 ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "${t}: ${term_missing} required technical term(s) missing"
    fi

    # 4e. SOURCE-REVISION marker present; stale detection is a warning
    marker="$(marker_of "${T_FILE}")"
    if [[ -z "${marker}" ]]; then
        fail "${t}: missing SOURCE-REVISION marker — add <!-- SOURCE-REVISION: ${expected_rev} -->"
    elif [[ "${marker}" == "${expected_rev}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${t}: translation is current"
    else
        warn "${t}: translation may be outdated (source revision ${expected_rev}, marker ${marker}) — review and update SOURCE-REVISION"
    fi
done

# English README itself must carry a current marker
en_marker="$(marker_of "${EN_README}")"
if [[ -z "${en_marker}" ]]; then
    fail "README.md: missing SOURCE-REVISION marker"
elif [[ "${en_marker}" == "${expected_rev}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ README.md source revision is current"
else
    warn "README.md: SOURCE-REVISION marker is stale (expected ${expected_rev}, found ${en_marker})"
fi

rm -f "${en_commands}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
report_results
