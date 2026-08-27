#!/usr/bin/env bash
# =============================================================================
# test_syntax.sh — every .sh script and bin command must pass bash -n
# =============================================================================
TEST_NAME="syntax"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

echo "  Bash: ${BASH_VERSION}"
echo ""

# All *.sh files
while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    if bash -n "${file}" 2>/dev/null; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ syntax error in ${file#${KIT_ROOT}/}"
    fi
done < <(find "${KIT_ROOT}" -type f -name '*.sh' | sort)

# All bin commands (no .sh extension)
while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    if head -1 "${file}" | grep -q '^#!.*bash' && ! bash -n "${file}" 2>/dev/null; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ syntax error in ${file#${KIT_ROOT}/}"
    else
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
done < <(find "${KIT_ROOT}/bin" -type f 2>/dev/null | sort)

# Mock binaries must also be valid bash
while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    if bash -n "${file}" 2>/dev/null; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ syntax error in ${file#${KIT_ROOT}/}"
    fi
done < <(find "${TEST_ROOT}/mocks/bin" -type f 2>/dev/null | sort)

report_results
