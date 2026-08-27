#!/usr/bin/env bash
# =============================================================================
# test_shellcheck.sh — run shellcheck at error severity when available
# =============================================================================
# Note: the shellcheck tool is optional. If it is not installed, this test
# reports SKIP and passes. When it is installed, any error-severity finding
# fails the test.
# =============================================================================
TEST_NAME="shellcheck"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

if ! command -v shellcheck &>/dev/null; then
    echo "  SKIP — shellcheck not installed (brew install shellcheck)"
    PASS_COUNT=1
    report_results
    exit 0
fi

echo "  shellcheck: $(shellcheck --version | head -1)"
echo ""

declare -a targets=()
while IFS= read -r file; do
    targets+=("${file}")
done < <(find "${KIT_ROOT}" -type f -name '*.sh' | sort)
while IFS= read -r file; do
    targets+=("${file}")
done < <(find "${KIT_ROOT}/bin" -type f 2>/dev/null | sort)

for file in "${targets[@]}"; do
    if ! head -1 "${file}" | grep -q '^#!.*bash'; then
        continue
    fi
    # Only error severity is a hard failure; style warnings are advisory.
    if shellcheck -x -S error "${file}" >/dev/null 2>&1; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ shellcheck (errors) in ${file#${KIT_ROOT}/}:"
        shellcheck -x -S error "${file}" 2>&1 | sed 's/^/      /'
    fi
done

report_results
