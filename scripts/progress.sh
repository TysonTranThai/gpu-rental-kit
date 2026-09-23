#!/usr/bin/env bash
# =============================================================================
# progress.sh — one-line "% complete" bar under each setup stage header
# =============================================================================
# Sourced by setup.sh (AFTER i18n.sh). Renders a compact bar so the user can
# see how much of the 15-stage install is left, with elapsed time:
#
#     [######--------------]  33% (1m 15s)
#
# Design notes:
#   - Output is language-neutral ("33%" reads the same in every catalog), so
#     it never goes through i18n tr() — it cannot regress the tr-shadow fix.
#   - Plain ASCII "[#---]" when stdout is NOT a TTY (piped/teed runs, CI logs,
#     log files) or TERM=dumb / NO_COLOR — keeps output greppable.
#   - Unicode blocks (████░░░░) + color only on an interactive terminal.
#   - Elapsed time is shown when setup.sh exports PROGRESS_START_EPOCH; an
#     unset/invalid clock or a backwards time step (NTP) simply renders no
#     suffix — the bar can never crash or show nonsense.
#   - stdout only; the per-stage log lines still land in the setup log file.
# =============================================================================
if [[ -z "${_GPU_RENTAL_KIT_PROGRESS_LOADED:-}" ]]; then
_GPU_RENTAL_KIT_PROGRESS_LOADED="1"

# Total number of setup stages (setup.sh's N/15 numbering).
PROGRESS_TOTAL="${PROGRESS_TOTAL:-15}"
export PROGRESS_TOTAL

# -----------------------------------------------------------------------------
# progress_tty_ok — 0 when the unicode/color bar is safe to draw
# (mirrors the i18n_terminal_supports_emoji heuristics; plain output otherwise)
# -----------------------------------------------------------------------------
progress_tty_ok() {
    [[ -t 1 ]] || return 1
    case "${TERM:-}" in
        ""|dumb) return 1 ;;
    esac
    [[ -n "${NO_COLOR:-}" ]] && return 1
    return 0
}

# -----------------------------------------------------------------------------
# progress_format_elapsed — "4m 15s" / "1h 02m 03s" / "" (no suffix)
# Empty when PROGRESS_START_EPOCH is unset/invalid or the clock went backwards
# (e.g. NTP stepped it) — the bar just renders without a suffix then.
# -----------------------------------------------------------------------------
progress_format_elapsed() {
    [[ "${PROGRESS_START_EPOCH:-}" =~ ^[0-9]+$ ]] || return 0
    local now
    now="$(date +%s)"
    [[ "${now}" =~ ^[0-9]+$ ]] || return 0
    local elapsed=$(( now - PROGRESS_START_EPOCH ))
    [[ "${elapsed}" -ge 0 ]] || return 0
    local h=$(( elapsed / 3600 )) m=$(( (elapsed % 3600) / 60 )) s=$(( elapsed % 60 ))
    if [[ "${h}" -gt 0 ]]; then
        printf '%dh %02dm %02ds' "${h}" "${m}" "${s}"
    elif [[ "${m}" -gt 0 ]]; then
        printf '%dm %02ds' "${m}" "${s}"
    fi
}

# -----------------------------------------------------------------------------
# show_progress DONE TOTAL — render "  [####------]  40% (1m 15s)"
# DONE stages completed so far; TOTAL total stages. Malformed or out-of-range
# values are sanitized (never crashes under set -Eeuo pipefail).
# -----------------------------------------------------------------------------
show_progress() {
    local done_n="${1:-0}"
    local total="${2:-${PROGRESS_TOTAL}}"

    # Sanitize: only non-negative integers survive; leading zeros normalized
    # with 10# so "08" doesn't hit bash's octal arithmetic.
    [[ "${done_n}" =~ ^[0-9]+$ ]] || done_n=0
    [[ "${total}" =~ ^[0-9]+$ ]] || total="${PROGRESS_TOTAL}"
    done_n=$((10#${done_n}))
    total=$((10#${total}))
    [[ "${total}" -ge 1 ]] || total=1
    [[ "${done_n}" -le "${total}" ]] || done_n="${total}"

    local pct=$(( done_n * 100 / total ))
    local width=24
    local fill=$(( done_n * width / total ))
    local empty=$(( width - fill ))

    local bar="" i elapsed=""
    elapsed="$(progress_format_elapsed)"
    if progress_tty_ok; then
        for (( i = 0; i < fill; i++ )); do bar+="█"; done
        for (( i = 0; i < empty; i++ )); do bar+="░"; done
        printf '  %s[%s]%s %3d%%%s\n' "${C_CYAN:-}" "${bar}" "${C_RESET:-}" "${pct}" "${elapsed:+ (${elapsed})}"
    else
        for (( i = 0; i < fill; i++ )); do bar+="#"; done
        for (( i = 0; i < empty; i++ )); do bar+="-"; done
        printf '  [%s] %3d%%%s\n' "${bar}" "${pct}" "${elapsed:+ (${elapsed})}"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# finish_progress — final 100% line once all stages have run
# -----------------------------------------------------------------------------
finish_progress() {
    show_progress "${PROGRESS_TOTAL}" "${PROGRESS_TOTAL}"
}

fi # _GPU_RENTAL_KIT_PROGRESS_LOADED
