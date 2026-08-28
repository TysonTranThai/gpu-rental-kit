#!/usr/bin/env bash
# =============================================================================
# lang-selector.sh — generate the README language selector row
# =============================================================================
# Reads docs/languages.env and prints the GitHub language-selector block that
# belongs at the top of every README.*.md.
#
# Usage:
#   bash docs/lang-selector.sh            # print the selector block
#   bash docs/lang-selector.sh --line     # print only the selector line
#
# Only languages with status "complete" or "partial" are shown, so the
# selector never links to translations that do not exist yet.
# =============================================================================
set -Eeuo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../docs/languages.env
source "${KIT_ROOT}/docs/languages.env"

MODE="${1:-block}"

selector_line=""
first="yes"
for entry in "${LANGUAGE_REGISTRY[@]}"; do
    IFS='|' read -r code name native flag path status direction <<< "${entry}"
    [[ -n "${code}" ]] || continue
    case "${status}" in
        complete|partial) ;;
        *) continue ;;  # outdated/in-progress translations stay hidden
    esac
    if [[ "${first}" == "yes" ]]; then
        selector_line="  ${flag} <a href=\"${path}\">${native}</a>"
        first="no"
    else
        selector_line="${selector_line} &nbsp;|&nbsp; ${flag} <a href=\"${path}\">${native}</a>"
    fi
done

if [[ -z "${selector_line}" ]]; then
    echo "lang-selector: no complete/partial languages registered" >&2
    exit 1
fi

case "${MODE}" in
    --line)
        echo "${selector_line}"
        ;;
    *)
        echo "<p align=\"center\">"
        echo "${selector_line}"
        echo "</p>"
        ;;
esac
