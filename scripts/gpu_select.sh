#!/usr/bin/env bash
# =============================================================================
# gpu_select.sh — GPU selection, fit analysis, and runtime-specific
#                 multi-GPU configuration helpers.
# =============================================================================
# Source this file from bin commands. It builds on scripts/detect_gpu.sh.
#
# Design principles (do not break these):
#   * Default is SINGLE GPU. Multi-GPU is only enabled when the user explicitly
#     asks for it (--gpus/--gpu/--auto) or via explicit GPU_MODE/GPU_IDS config.
#   * Existing CUDA_VISIBLE_DEVICES is respected: when set, indices are logical
#     positions within that list and we never widen the visible set.
#   * Aggregate VRAM is the SUM of separate GPUs, never a pooled single GPU.
#
# IMPORTANT: all mg_* functions that need detection state call
# mg_ensure_detection FIRST in the CURRENT shell (never inside a command
# substitution), so GPU_* variables propagate to the caller.
# =============================================================================

GPU_SELECT_LIB_LOADED=1
export GPU_SELECT_LIB_LOADED

# =============================================================================
# mg_ensure_detection — make sure GPU detection has run (current shell)
# =============================================================================
mg_ensure_detection() {
    if [[ -z "${HAS_NVIDIA_GPU:-}" ]]; then
        local here
        here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        # shellcheck source=scripts/detect_gpu.sh
        source "${here}/detect_gpu.sh"
        run_gpu_detection
    fi
}

# =============================================================================
# mg_allowed_ids — logical GPU ids we may use, ONE PER LINE.
# CUDA_VISIBLE_DEVICES (integers only) restricts the set; UUID entries are
# left alone (we do not remap them, and multi-GPU selection is skipped).
# =============================================================================
mg_allowed_ids() {
    local cvd="${CUDA_VISIBLE_DEVICES:-}"
    if [[ -n "${cvd}" ]]; then
        if echo "${cvd}" | grep -qE '^[0-9]+(,[0-9]+)*$'; then
            echo "${cvd}" | tr ',' '\n' | tr -d ' '
        else
            echo ""   # non-integer CVD: unknown mapping, do not manage GPUs
        fi
    else
        local i
        for (( i=0; i<GPU_COUNT; i++ )); do
            echo "${i}"
        done
    fi
}

# =============================================================================
# mg_parse_gpu_spec <spec> — validate a GPU selection.
#   "all" | "0" | "0,1" | "0 1"  → sets MG_SELECTED (space-separated) and
#                                   MG_SEL_COUNT. Returns 1 on any invalid id.
# The selection is always a subset of the allowed ids.
# =============================================================================
mg_parse_gpu_spec() {
    local spec="$1"
    mg_ensure_detection

    local allowed_str
    allowed_str="$(mg_allowed_ids | tr '\n' ' ' | sed 's/ *$//')"

    MG_SELECTED=""
    MG_SEL_COUNT=0

    # Empty allowed list = we cannot map GPU ids (e.g. UUID-based CVD)
    if [[ -z "${allowed_str}" ]]; then
        echo "ERROR: Cannot map GPU indices (CUDA_VISIBLE_DEVICES is not a simple index list: '${CUDA_VISIBLE_DEVICES:-}')." >&2
        return 1
    fi

    local ids="" id
    case "${spec}" in
        all)
            ids="${allowed_str}"
            ;;
        *)
            local raw
            raw="$(echo "${spec}" | tr ',' ' ' | tr -s ' ' '\n')"
            for id in ${raw}; do
                case "${id}" in
                    ''|*[!0-9]*)
                        echo "ERROR: Invalid GPU id '${id}' (expected e.g. 0, 1 or 0,1 or all)." >&2
                        return 1
                        ;;
                esac
                if ! echo "${allowed_str}" | tr ' ' '\n' | grep -qx "${id}"; then
                    echo "ERROR: GPU ${id} is not available (visible GPUs: $(echo "${allowed_str}" | tr ' ' ','))." >&2
                    return 1
                fi
                ids="${ids:+${ids} }${id}"
            done
            if [[ -z "${ids}" ]]; then
                echo "ERROR: Empty GPU selection." >&2
                return 1
            fi
            ;;
    esac

    # Dedupe, preserving first-seen order
    local seen=" " unique="" u
    for u in ${ids}; do
        case "${seen}" in
            *" ${u} "*) continue ;;
        esac
        unique="${unique:+${unique} }${u}"
        seen="${seen}${u} "
    done

    MG_SELECTED="${unique}"
    MG_SEL_COUNT="$(echo "${MG_SELECTED}" | wc -w | tr -d ' ')"
    return 0
}

# =============================================================================
# mg_needed_mb <model_gb> — rough VRAM needed for a model, with ~15% headroom
# for weights overflow, KV cache and CUDA context.
# =============================================================================
mg_needed_mb() {
    awk -v g="$1" 'BEGIN { printf "%.0f", (g * 1.15) * 1024 }'
}

# =============================================================================
# mg_max_single_vram_mb — largest single-GPU VRAM in MB
# =============================================================================
mg_max_single_vram_mb() {
    echo "${GPU_VRAMS_MB_LIST}" | tr '|' '\n' | sort -n | tail -1
}

# =============================================================================
# mg_pick_best_single — echo the id of the GPU with the most VRAM (lowest id wins ties)
# =============================================================================
mg_pick_best_single() {
    local best=0 best_vram=-1 i v
    for (( i=0; i<GPU_COUNT; i++ )); do
        v="$(gpu_vram_gb_at "${i}")"
        if [[ "${v}" -gt "${best_vram}" ]]; then
            best_vram="${v}"; best="${i}"
        fi
    done
    echo "${best}"
}

# =============================================================================
# Logical vs physical indices: when CUDA_VISIBLE_DEVICES restricts the visible
# set, selection ids are LOGICAL positions inside that list. These helpers
# translate between logical selection ids and physical detection indices so
# per-GPU lookups always hit the right hardware.
# =============================================================================

# mg_phys_at <logical-id> — physical detection index for a logical selection id
mg_phys_at() {
    local logical="$1"
    local cvd="${CUDA_VISIBLE_DEVICES:-}"
    if [[ -n "${cvd}" ]] && echo "${cvd}" | grep -qE '^[0-9]+(,[0-9]+)*$'; then
        echo "${cvd}" | cut -d',' -f"$(( logical + 1 ))"
    else
        echo "${logical}"
    fi
}

# mg_logical_of_phys <physical-id> — logical id, or empty when not visible
mg_logical_of_phys() {
    local phys="$1" cvd="${CUDA_VISIBLE_DEVICES:-}"
    if [[ -n "${cvd}" ]] && echo "${cvd}" | grep -qE '^[0-9]+(,[0-9]+)*$'; then
        local i=0 p
        IFS=',' read -r -a _cvd_list <<< "${cvd}"
        for p in "${_cvd_list[@]}"; do
            if [[ "${p}" == "${phys}" ]]; then echo "${i}"; return 0; fi
            i=$(( i + 1 ))
        done
    else
        echo "${phys}"
    fi
}

# mg_vram_of / mg_name_of / mg_cc_of / mg_uuid_of — per-LOGICAL-id lookups
mg_vram_of() { gpu_vram_gb_at "$(mg_phys_at "$1")"; }
mg_name_of() { gpu_name_at   "$(mg_phys_at "$1")"; }
mg_cc_of()   { gpu_cc_at     "$(mg_phys_at "$1")"; }
mg_uuid_of() { gpu_uuid_at   "$(mg_phys_at "$1")"; }

# mg_allowed_aggregate_mb — aggregate VRAM (MB) of the ALLOWED (visible) GPUs
mg_allowed_aggregate_mb() {
    local s=0 id
    for id in $(mg_allowed_ids); do
        s=$(( s + $(mg_vram_of "${id}") * 1024 ))
    done
    echo "${s}"
}

# =============================================================================
# mg_busy_gpu_ids — echo indices (one per line) of GPUs with running compute
# processes, mapped from compute-app UUIDs to PHYSICAL detection indices.
# Read-only: safe inside command substitution (never assigns GPU_* state).
# =============================================================================
mg_busy_gpu_ids() {
    command -v nvidia-smi >/dev/null 2>&1 || return 0
    local app_uuids
    app_uuids="$(nvidia-smi --query-compute-apps=gpu_uuid --format=csv,noheader 2>/dev/null \
        | cut -d',' -f1 | tr -d ' ' | sort -u || true)"
    [[ -z "${app_uuids}" ]] && return 0
    local i u
    for (( i=0; i<GPU_COUNT; i++ )); do
        u="$(gpu_uuid_at "${i}")"
        [[ -z "${u}" ]] && continue
        if echo "${app_uuids}" | grep -qxF "${u}"; then
            echo "${i}"
        fi
    done
    return 0
}

# mg_sort_ids <ids> — echo the ids sorted numerically, space-separated
mg_sort_ids() { echo "$1" | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed 's/ *$//'; }

# =============================================================================
# mg_auto_select <model_gb|-> — INTELLIGENT automatic GPU selection.
#
# Principles (do not break):
#   * Never blindly consume every GPU. Prefer the SMALLEST set of identical
#     high-VRAM GPUs that fits the estimated requirement.
#   * GPUs already running compute workloads are excluded when possible
#     (respect other tenants: another LLM, ComfyUI, embeddings, training...).
#   * Every decision is explained via MG_AUTO_REASON; exclusions are recorded
#     in MG_AUTO_EXCLUDED as "id=reason" pairs joined by '|'.
#
# Sets: MG_SELECTED, MG_SEL_COUNT, MG_AUTO_REASON, MG_AUTO_EXCLUDED.
# =============================================================================
mg_auto_select() {
    local model_gb="${1:-}"
    local allowed best busy cand id

    mg_ensure_detection
    MG_AUTO_EXCLUDED=""

    allowed="$(mg_allowed_ids | tr '\n' ' ' | sed 's/ *$//')"

    if [[ -z "${allowed}" ]]; then
        # UUID-based CUDA_VISIBLE_DEVICES: indices cannot be mapped — leave alone.
        MG_SELECTED=""
        MG_SEL_COUNT=0
        MG_AUTO_REASON="CUDA_VISIBLE_DEVICES is not a plain index list — leaving GPU selection to the backend."
        return 0
    fi

    # --- Respect existing workloads: drop busy GPUs when alternatives exist ---
    busy="$(mg_busy_gpu_ids | tr '\n' ' ' | sed 's/ *$//')"
    local busy_logical="" bl
    for bl in ${busy}; do
        bl="$(mg_logical_of_phys "${bl}")"
        [[ -n "${bl}" ]] && busy_logical="${busy_logical:+${busy_logical} }${bl}"
    done
    busy="${busy_logical}"
    cand=""
    for id in ${allowed}; do
        if echo " ${busy} " | grep -q " ${id} "; then
            MG_AUTO_EXCLUDED="${MG_AUTO_EXCLUDED:+${MG_AUTO_EXCLUDED}|}${id}=in use by another workload"
        else
            cand="${cand:+${cand} }${id}"
        fi
    done
    if [[ -z "${cand}" ]]; then
        cand="${allowed}"   # every GPU busy — fall back to the allowed set
    fi

    # Best candidate = most VRAM (lowest index wins ties)
    local best_cand="" best_vram=-1 v
    for id in ${cand}; do
        v="$(mg_vram_of "${id}")"
        if [[ "${v}" -gt "${best_vram}" ]]; then best_vram="${v}"; best_cand="${id}"; fi
    done

    # --- Unknown model size: safety default = one GPU ---
    if [[ -z "${model_gb}" || "${model_gb}" == "-" ]]; then
        MG_SELECTED="${best_cand}"
        MG_SEL_COUNT=1
        MG_AUTO_REASON="Model size unknown — using the largest free GPU (safety default). Pass --size-gb for automatic multi-GPU."
        return 0
    fi

    local total_needed
    total_needed="$(mg_needed_mb "${model_gb}")"

    # Candidates ordered by VRAM desc, ties by index asc
    local sorted="" order="" pair
    for id in ${cand}; do
        pair="$(mg_vram_of "${id}") ${id}"
        sorted="${sorted}${pair}"$'\n'
    done
    while IFS=' ' read -r _v id; do
        [[ -n "${id}" ]] && order="${order:+${order} }${id}"
    done < <(echo "${sorted}" | sort -k1,1nr -k2,2n)

    # --- Pass 1: fits in one GPU → single GPU, everything else excluded ---
    local best_mb=$(( $(mg_vram_of "${best_cand}") * 1024 ))
    if [[ "${total_needed}" -le "${best_mb}" ]]; then
        MG_SELECTED="${best_cand}"
        MG_SEL_COUNT=1
        MG_AUTO_REASON="Model fits in one GPU — using the largest free GPU only."
        for id in ${cand}; do
            [[ "${id}" == "${MG_SELECTED}" ]] && continue
            MG_AUTO_EXCLUDED="${MG_AUTO_EXCLUDED:+${MG_AUTO_EXCLUDED}|}${id}=not needed — the model fits on GPU ${MG_SELECTED}"
        done
        return 0
    fi

    # --- Pass 2: smallest homogeneous group that fits (identical GPUs) ---
    local all_keys="" uk key
    for id in ${cand}; do
        key="$(mg_name_of "${id}")|$(mg_cc_of "${id}")|$(mg_vram_of "${id}")"
        case $'\n'"${all_keys}" in
            *$'\n'"${key}"$'\n'*) ;;
            *) all_keys="${all_keys}${key}"$'\n' ;;
        esac
    done

    local sel="" sel_member_vram=0 sel_count=99 fit_found="no"
    while IFS= read -r uk; do
        [[ -z "${uk}" ]] && continue
        local sum=0 acc="" mid
        for mid in ${order}; do
            [[ "$(mg_name_of "${mid}")|$(mg_cc_of "${mid}")|$(mg_vram_of "${mid}")" == "${uk}" ]] || continue
            acc="${acc:+${acc} }${mid}"
            sum=$(( sum + $(mg_vram_of "${mid}") * 1024 ))
            if [[ "${sum}" -ge "${total_needed}" ]]; then break; fi
        done
        if [[ "${sum}" -ge "${total_needed}" ]]; then
            local nmem mvram
            nmem="$(echo "${acc}" | wc -w | tr -d ' ')"
            mvram="$(mg_vram_of "${acc%% *}")"
            if [[ "${fit_found}" == "no" ]] || [[ "${mvram}" -gt "${sel_member_vram}" ]] \
               || { [[ "${mvram}" -eq "${sel_member_vram}" ]] && [[ "${nmem}" -lt "${sel_count}" ]]; }; then
                sel="${acc}"; sel_member_vram="${mvram}"; sel_count="${nmem}"; fit_found="yes"
            fi
        fi
    done <<< "${all_keys}"

    if [[ "${fit_found}" == "yes" ]]; then
        MG_SELECTED="$(mg_sort_ids "${sel}")"
        MG_SEL_COUNT="$(echo "${MG_SELECTED}" | wc -w | tr -d ' ')"
        MG_AUTO_REASON="Using ${MG_SEL_COUNT} identical $(mg_name_of "${MG_SELECTED%% *}") GPU(s) — the smallest homogeneous set that fits the estimated requirement."
        for id in ${cand}; do
            case " ${MG_SELECTED} " in *" ${id} "*) continue ;; esac
            MG_AUTO_EXCLUDED="${MG_AUTO_EXCLUDED:+${MG_AUTO_EXCLUDED}|}${id}=not needed — the model fits on the selected GPUs"
        done
        return 0
    fi

    # --- Pass 3: mixed accumulation (VRAM-desc) when no homogeneous group fits ---
    local sum=0 acc="" mid
    for mid in ${order}; do
        acc="${acc:+${acc} }${mid}"
        sum=$(( sum + $(mg_vram_of "${mid}") * 1024 ))
        if [[ "${sum}" -ge "${total_needed}" ]]; then break; fi
    done
    if [[ "${sum}" -ge "${total_needed}" ]]; then
        MG_SELECTED="$(mg_sort_ids "${acc}")"
        MG_SEL_COUNT="$(echo "${MG_SELECTED}" | wc -w | tr -d ' ')"
        MG_AUTO_REASON="No single GPU model fits and no identical group covers it — using a mixed GPU set (aggregate VRAM, NOT pooled)."
        for id in ${cand}; do
            case " ${MG_SELECTED} " in *" ${id} "*) continue ;; esac
            MG_AUTO_EXCLUDED="${MG_AUTO_EXCLUDED:+${MG_AUTO_EXCLUDED}|}${id}=not needed — the model fits on the selected GPUs"
        done
        return 0
    fi

    # --- Pass 4: honest fallback with a loud warning (no silent failure) ---
    MG_SELECTED="${best_cand}"
    MG_SEL_COUNT=1
    MG_AUTO_REASON="WARNING: the model may not fit even in the aggregate VRAM of the free GPUs — using the largest single GPU. Reduce model size/quantization or free up GPUs."
    return 0
}

# =============================================================================
# mg_auto_report <model_gb|-> — human-readable explanation of mg_auto_select
# (the "why" for the user: detected GPUs, requirement, choice, exclusions).
# =============================================================================
mg_auto_report() {
    local model_gb="${1:-}"
    local id pair reason
    echo "GPU system:"
    echo "  ${GPU_COUNT} GPU(s) detected"
    for (( id=0; id<GPU_COUNT; id++ )); do
        echo "  GPU ${id}: $(mg_name_of "${id}") — $(mg_vram_of "${id}")GB"
    done
    if [[ -n "${model_gb}" && "${model_gb}" != "-" ]]; then
        echo "Model estimated requirement: ~${model_gb} GB (ESTIMATE — includes headroom; not a guarantee)"
    fi
    echo "Recommended configuration: $(mg_select_summary)"
    echo "Reason: ${MG_AUTO_REASON}"
    for id in ${MG_SELECTED}; do
        echo "GPU ${id}: enabled"
    done
    if [[ -n "${MG_AUTO_EXCLUDED}" ]]; then
        IFS='|' read -r -a _excl_pairs <<< "${MG_AUTO_EXCLUDED}"
        local p
        for p in "${_excl_pairs[@]+${_excl_pairs[@]}}"; do
            [[ -z "${p}" ]] && continue
            echo "GPU ${p%%=*}: excluded — ${p#*=}"
        done
    fi
}

# =============================================================================
# mg_hetero_verdict <backend> — evaluate heterogeneous (mixed-GPU) sharding
# for a backend. Sets MGH_STATE (SUPPORTED | PARTIAL | CAUTION | UNSUPPORTED |
# UNKNOWN) and MGH_REASON. States reflect each backend's documented behavior;
# capabilities not verified on real hardware are never upgraded to SUPPORTED
# blindly — see the README capability matrix.
# =============================================================================
mg_hetero_verdict() {
    local backend="$1"
    MGH_STATE="UNKNOWN"; MGH_REASON=""
    case "${backend}" in
        llamacpp)
            MGH_STATE="SUPPORTED"
            MGH_REASON="Layer/tensor splitting works across different NVIDIA GPUs; weight the split with --tensor-split (VRAM-proportional weights recommended). The slowest GPU limits overall speed."
            ;;
        ollama)
            MGH_STATE="PARTIAL"
            MGH_REASON="Ollama splits models across visible GPUs automatically but offers no manual split control; allocation on heterogeneous GPUs is automatic."
            ;;
        vllm)
            MGH_STATE="CAUTION"
            MGH_REASON="Tensor parallelism expects identical GPUs; heterogeneous TP is not officially supported. Prefer llama.cpp sharding or workload distribution. NEEDS VERIFICATION on real hardware."
            ;;
        pytorch)
            MGH_STATE="SUPPORTED"
            MGH_REASON="CUDA_VISIBLE_DEVICES selects which GPUs PyTorch sees; the multi-GPU strategy is model-specific."
            ;;
        docker)
            MGH_STATE="SUPPORTED"
            MGH_REASON="NVIDIA Container Toolkit exposes all or selected GPUs to containers; the backend inside decides sharding."
            ;;
        *)
            MGH_STATE="UNKNOWN"
            MGH_REASON="Backend '${backend}' is not covered by the capability matrix."
            ;;
    esac
    echo "${MGH_STATE}"
}

# =============================================================================
# mg_recommend_split [ids] — echo --tensor-split weights proportional to each
# GPU's VRAM (llama.cpp accepts arbitrary proportions). Uses MG_SELECTED when
# no ids are given. Example: 24GB + 8GB → "24,8" (≈ 75%/25%).
# =============================================================================
mg_recommend_split() {
    local ids="${1:-${MG_SELECTED:-}}" out="" sep="" id
    for id in ${ids}; do
        out="${out}${sep}$(mg_vram_of "${id}")"
        sep="," 
    done
    echo "${out}"
}

# =============================================================================
# mg_resolve_auto — backward-compatible entry point (delegates to mg_auto_select).
# =============================================================================
mg_resolve_auto() {
    mg_auto_select "$@"
}

# =============================================================================
# mg_model_fit <model_gb> — print fit analysis for single vs multi GPU.
# Sets FIT_SINGLE_OK (yes/no), FIT_MULTI_OK (yes/no), FIT_VERDICT
# (single | multi | none). ALWAYS returns 0 — read FIT_VERDICT, do not
# rely on the exit code (errexit-safe by design).
# =============================================================================
mg_model_fit() {
    local model_gb="$1"
    local needed single_mb

    mg_ensure_detection
    needed="$(mg_needed_mb "${model_gb}")"
    single_mb="$(mg_max_single_vram_mb)"
    single_gb="$(awk -v mb="${single_mb}" 'BEGIN {printf "%.0f", mb/1024}')"

    FIT_SINGLE_OK="no"; FIT_MULTI_OK="no"; FIT_VERDICT="none"

    echo "  Model size:            ~${model_gb} GB (needs ~$(( needed / 1024 )) GB with headroom)"
    echo "  Largest single GPU:    ${single_gb} GB"
    echo "  Aggregate VRAM:        ${GPU_TOTAL_VRAM_GB} GB across ${GPU_COUNT} GPU(s) — NOT one pooled GPU"

    if [[ "${needed}" -le "${single_mb}" ]]; then
        FIT_SINGLE_OK="yes"
        echo "  Single GPU:            [OK] fits comfortably"
    else
        echo "  Single GPU:            [NO] does not fit comfortably"
    fi

    if [[ "${GPU_COUNT}" -gt 1 ]]; then
        if [[ "${needed}" -le "${GPU_TOTAL_VRAM_MB}" ]]; then
            FIT_MULTI_OK="yes"
            echo "  Multi-GPU:             [OK] potentially fits with a sharding-capable backend"
        else
            echo "  Multi-GPU:             [NO] does not fit even in aggregate VRAM"
        fi
    else
        echo "  Multi-GPU:             n/a (only one GPU present)"
    fi

    if [[ "${FIT_SINGLE_OK}" == "yes" ]]; then
        FIT_VERDICT="single"
    elif [[ "${FIT_MULTI_OK}" == "yes" ]]; then
        FIT_VERDICT="multi"
        echo ""
        echo "  Note: aggregate VRAM is only usable if the backend supports sharding/"
        echo "  offloading (llama.cpp layer split, vLLM tensor parallelism). The"
        echo "  runtime — not this tool — decides how memory is actually used."
    else
        FIT_VERDICT="none"
    fi
    return 0
}

# =============================================================================
# mg_select_summary — human-readable summary of MG_SELECTED
# =============================================================================
mg_select_summary() {
    local out="" sep="" id
    for id in ${MG_SELECTED}; do
        out="${out}${sep}GPU ${id} ($(mg_name_of "${id}"), $(mg_vram_of "${id}")GB)"
        sep=", "
    done
    echo "${out}"
}

# =============================================================================
# Runtime-specific helpers
# =============================================================================

# mg_vllm_tp_flag <count> — vLLM tensor parallelism flag (only when >1 GPU)
mg_vllm_tp_flag() {
    [[ "$1" -gt 1 ]] && echo "--tensor-parallel-size $1"
}

# mg_has_tp_arg <args...> — detect an existing tensor-parallel-size argument
mg_has_tp_arg() {
    local prev=""
    local a
    for a in "$@"; do
        if [[ "${a}" == "--tensor-parallel-size" || "${a}" == "-tp" || "${prev}" == "--tensor-parallel-size" || "${prev}" == "-tp" ]]; then
            return 0
        fi
        prev="${a}"
    done
    return 1
}

# mg_cvd_value — CUDA_VISIBLE_DEVICES value for MG_SELECTED (comma-separated)
mg_cvd_value() {
    echo "${MG_SELECTED}" | tr ' ' ','
}
