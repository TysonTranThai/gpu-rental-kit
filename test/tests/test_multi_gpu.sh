#!/usr/bin/env bash
# =============================================================================
# test_multi_gpu.sh — Multi-GPU feature tests (mock GPU environment only).
# =============================================================================
# Covers: all-GPU detection, per-GPU details, aggregate VRAM, topology
# parsing (PCIe/NVLink/SYS), multi-GPU profiles, mixed-GPU warnings,
# selection (--gpus), auto mode, fit analysis, single-GPU regression,
# runtime flag injection, and gpu-status/gpu-list output. Extended:
# configuration classification (homogeneous/heterogeneous/mixed-architecture),
# per-GPU UUID+architecture inventory, intelligent auto-selection with busy-GPU
# exclusion and reasons, per-backend heterogeneous verdicts, VRAM-proportional
# split recommendation, CUDA_VISIBLE_DEVICES logical/physical mapping,
# gpu-status --expect usage verification, model-run --gpu-mode + env config,
# ai-start GPU delegation, and gpu-test --bench SKIP path.
# No real GPU is required or used: everything runs against test/mocks.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOCKS_BIN="${SCRIPT_DIR}/test/mocks/bin"
MOCKS_DIR="${SCRIPT_DIR}/test/mocks"

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${actual}" == *"${expected}"* ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  [FAIL] ${desc}"
        echo "    expected to contain: ${expected}"
        echo "    actual:              ${actual}"
    fi
}

check_exit() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  [FAIL] ${desc}: expected exit ${expected}, got ${actual}"
    fi
}

check_absent() {
    local desc="$1" unwanted="$2" actual="$3"
    if [[ "${actual}" != *"${unwanted}"* ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  [FAIL] ${desc}"
        echo "    expected NOT to contain: ${unwanted}"
    fi
}

# run_in_mock <profile> <topo-file|-> <script...> — run a snippet with mocks
run_in_mock() {
    local profile="$1" topo="$2"
    shift 2
    PATH="${MOCKS_BIN}:${PATH}" \
    MOCK_GPU_PROFILE="${profile}" \
    MOCK_TOPO_FILE="$([[ "${topo}" == "-" ]] && echo "" || echo "${MOCKS_DIR}/topo/${topo}")" \
        bash -c "$*"
}

echo "── detect_gpu.sh: multi-GPU detection ──"

out="$(run_in_mock rtx3090x2 pcie2.txt '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "COUNT=${GPU_COUNT}"
    echo "NAMES=${GPU_NAMES_LIST}"
    echo "VRAMS=${GPU_VRAMS_GB_LIST}"
    echo "TOTAL=${GPU_TOTAL_VRAM_GB}"
    echo "PROFILE=${GPU_MULTI_PROFILE}"
    echo "MIXED=${GPU_MIXED_WARNING}"
')"
check "2 GPUs detected" "COUNT=2" "${out}"
check "both named RTX 3090" "NAMES=NVIDIA GeForce RTX 3090|NVIDIA GeForce RTX 3090" "${out}"
check "per-GPU VRAM 24|24" "VRAMS=24|24" "${out}"
check "aggregate 48 GB" "TOTAL=48" "${out}"
check "profile multi-gpu-small" "PROFILE=multi-gpu-small" "${out}"
check "not mixed" "MIXED=no" "${out}"

out="$(run_in_mock mixed3090_4090 - '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "PROFILE=${GPU_MULTI_PROFILE}"
    echo "MIXED=${GPU_MIXED_WARNING}"
    echo "CC=${GPU_COMPUTE_CAPS_LIST}"
')"
check "mixed profile detected" "PROFILE=multi-gpu-mixed" "${out}"
check "mixed warning set" "MIXED=yes" "${out}"
check "per-GPU compute caps" "CC=8.6|8.9" "${out}"

out="$(run_in_mock rtx3090x4 - '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "COUNT=${GPU_COUNT}"
    echo "PROFILE=${GPU_MULTI_PROFILE}"
    echo "TOTAL_GB=${GPU_TOTAL_VRAM_GB}"
')"
check "4 GPUs detected" "COUNT=4" "${out}"
check "4x profile is large (>=64GB)" "PROFILE=multi-gpu-large" "${out}"
check "aggregate 96 GB" "TOTAL_GB=96" "${out}"

out="$(run_in_mock rtx3090_t4 - '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "PROFILE=${GPU_MULTI_PROFILE}"
    echo "MIXED=${GPU_MIXED_WARNING}"
    echo "TOTAL=${GPU_TOTAL_VRAM_GB}"
')"
check "24+16GB mixed profile" "PROFILE=multi-gpu-mixed" "${out}"
check "24+16GB mixed warning" "MIXED=yes" "${out}"
check "24+16GB aggregate 40" "TOTAL=40" "${out}"

echo "── detect_gpu.sh: single-GPU regression ──"

out="$(run_in_mock rtx4090 - '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "COUNT=${GPU_COUNT}"
    echo "PROFILE=${GPU_MULTI_PROFILE}"
    echo "NAME=${GPU_NAME}"
    echo "VRAM=${GPU_VRAM_GB}"
')"
check "single GPU count" "COUNT=1" "${out}"
check "single profile stays single" "PROFILE=single" "${out}"
check "legacy GPU_NAME kept" "NAME=NVIDIA GeForce RTX 4090" "${out}"
check "legacy VRAM kept" "VRAM=24" "${out}"

echo "── topology ──"

out="$(run_in_mock rtx3090x2 nvlink2.txt '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "LINK=$(gpu_link_type 0 1)"
    echo "REVERSE=$(gpu_link_type 1 0)"
')"
check "NVLink parsed" "LINK=NVLink" "${out}"
check "link lookup symmetric" "REVERSE=NVLink" "${out}"

out="$(run_in_mock rtx3090x2 pcie2.txt '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "LINK=$(gpu_link_type 0 1)"
')"
check "PCIe parsed" "LINK=PCIe" "${out}"

out="$(run_in_mock rtx3090x4 quad_sys.txt '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "A=$(gpu_link_type 0 1)"
    echo "B=$(gpu_link_type 0 2)"
    echo "N2=$(gpu_numa_at 2)"
    echo "N0=$(gpu_numa_at 0)"
')"
check "4-GPU matrix upper triangle" "A=PCIe" "${out}"
check "4-GPU second pair" "B=PCIe" "${out}"
check "NUMA parsed when reported" "N2=0" "${out}"
check "NUMA N/A stays honest" "N0=N/A" "${out}"

echo "── gpu_select.sh: selection and auto ──"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_parse_gpu_spec all; echo "ALL=${MG_SELECTED}:${MG_SEL_COUNT}"
    mg_parse_gpu_spec 0,1; echo "PAIR=${MG_SELECTED}:${MG_SEL_COUNT}"
    mg_parse_gpu_spec 1;   echo "ONE=${MG_SELECTED}:${MG_SEL_COUNT}"
')"
check "all -> both GPUs" "ALL=0 1:2" "${out}"
check "0,1 -> both GPUs" "PAIR=0 1:2" "${out}"
check "single id selection" "ONE=1:1" "${out}"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_parse_gpu_spec 5 2>&1 || echo "REJECTED=$?"
')"
check "invalid id rejected" "REJECTED=1" "${out}"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_resolve_auto 20;  echo "A=${MG_SELECTED}"
    mg_resolve_auto 40;  echo "B=${MG_SELECTED}:${MG_SEL_COUNT}"
    mg_resolve_auto 200; echo "C=${MG_SELECTED}"
    mg_resolve_auto -;   echo "D=${MG_SELECTED}"
')"
check "auto: 20GB fits one GPU" "A=0" "${out}"
check "auto: 40GB uses all GPUs" "B=0 1:2" "${out}"
check "auto: 200GB safety fallback" "C=0" "${out}"
check "auto: unknown size = single" "D=0" "${out}"

out="$(run_in_mock rtx4090 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_resolve_auto 40; echo "S=${MG_SELECTED}"
')"
check "single GPU: auto stays single" "S=0" "${out}"

echo "── gpu_select.sh: fit analysis ──"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_model_fit 40; echo "V=${FIT_VERDICT}"
')"
check "fit 40GB: single NO" "Single GPU:            [NO]" "${out}"
check "fit 40GB: multi OK" "Multi-GPU:             [OK]" "${out}"
check "fit 40GB: aggregate caveat shown" "NOT one pooled GPU" "${out}"
check "fit 40GB: verdict multi" "V=multi" "${out}"

out="$(run_in_mock rtx4090 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_model_fit 40 >/dev/null 2>&1; echo "V=${FIT_VERDICT}"
')"
check "fit 40GB on 1 GPU: verdict none" "V=none" "${out}"

echo "── runtime flag injection (model-run with stub servers) ──"

STUB="$(mktemp -d)"
mkdir -p "${STUB}/bin"
printf '#!/bin/bash\necho "VLLM-ARGS: $*"\n' > "${STUB}/bin/vllm-serve"
printf '#!/bin/bash\necho "LLAMACPP-ARGS: $*"\n' > "${STUB}/bin/llamacpp-serve"
chmod +x "${STUB}/bin/vllm-serve" "${STUB}/bin/llamacpp-serve"

out="$(run_in_mock rtx3090x2 - '
    export PATH="'"${MOCKS_BIN}"':$PATH" AI_HOME="'"${STUB}"'"
    bash "'"${SCRIPT_DIR}"'/bin/model-run" Qwen/Qwen-40B --backend vllm --gpus auto --size-gb 40 2>/dev/null
')"
check "vllm auto: tensor-parallel injected" "--tensor-parallel-size 2" "${out}"

out="$(run_in_mock rtx3090x2 - '
    export PATH="'"${MOCKS_BIN}"':$PATH" AI_HOME="'"${STUB}"'"
    bash "'"${SCRIPT_DIR}"'/bin/model-run" Qwen/Qwen-40B --backend vllm --gpus all --tensor-parallel-size 1 2>/dev/null
')"
check "vllm: user tp flag respected (no double inject)" "--tensor-parallel-size 1" "${out}"

out="$(run_in_mock rtx3090x2 - '
    export PATH="'"${MOCKS_BIN}"':$PATH" AI_HOME="'"${STUB}"'"
    bash "'"${SCRIPT_DIR}"'/bin/model-run" Qwen/Qwen-40B --backend vllm --gpu 0 2>/dev/null
')"
check "workload mode: no tp injection" "VLLM-ARGS: Qwen/Qwen-40B" "${out}"

out="$(run_in_mock rtx3090x2 - '
    export PATH="'"${MOCKS_BIN}"':$PATH" AI_HOME="'"${STUB}"'"
    bash "'"${SCRIPT_DIR}"'/bin/model-run" m --gpu 0 --gpus all 2>&1 || true
')"
check "--gpu + --gpus conflict rejected" "mutually exclusive" "${out}"

rm -rf "${STUB}"

echo "── gpu-list / gpu-topology output ──"

out="$(run_in_mock rtx3090x2 nvlink2.txt '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-list"
')"
check "gpu-list shows count" "GPUS: 2" "${out}"
check "gpu-list aggregate labeled" "AGGREGATE VRAM: 48 GB" "${out}"
check "gpu-list no-pooling note" "NOT one pooled GPU" "${out}"
check "gpu-list shows NVLink" "NVLink" "${out}"

out="$(run_in_mock rtx4090 - '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-list"
')"
check "single GPU list: plain VRAM label" "TOTAL VRAM: 24 GB" "${out}"

out="$(run_in_mock rtx3090x2 - '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-topology"
')"
check "topology: no NVLink claim over PCIe" "No NVLink detected" "${out}"

out="$(run_in_mock rtx3090x2 nvlink2.txt '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-topology"
')"
check "topology: NVLink reported" "NVLink detected" "${out}"
check "topology: honest perf note" "does NOT guarantee 2 GPUs = 2x speed" "${out}"

out="$(run_in_mock rtx3090x4 quad_sys.txt '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-topology"
')"
check "topology: NUMA section when reported" "NUMA affinity:" "${out}"
check "topology: NUMA node value" "GPU 2: NUMA node 0" "${out}"

echo "── gpu-status multi-GPU block ──"

out="$(run_in_mock rtx3090x2 - '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-status" 2>/dev/null || true
')"
check "status: MULTI-GPU mode" "MULTI-GPU" "${out}"
check "status: aggregate labeled" "AGGREGATE VRAM:" "${out}"

out="$(run_in_mock rtx4090 - '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-status" 2>/dev/null || true
')"
check "single status: SINGLE-GPU mode" "SINGLE-GPU" "${out}"

echo "── Windows client twins ──"

for ps1cmd in gpu-list gpu-topology; do
    if [[ -f "${SCRIPT_DIR}/bin/${ps1cmd}.ps1" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  [FAIL] bin/${ps1cmd}.ps1 missing"
    fi
done
out="$(cat "${SCRIPT_DIR}/bin/gpu-list.ps1" 2>/dev/null || echo "")"
check "gpu-list.ps1 honestly labeled REMOTE" "REMOTE" "${out}"
out="$(cat "${SCRIPT_DIR}/bin/gpu-topology.ps1" 2>/dev/null || echo "")"
check "gpu-topology.ps1 uses remote lib" "Invoke-GrkRemoteCommand" "${out}"
out="$( { grep -rn "mg_verify_selection" "${SCRIPT_DIR}/scripts/" 2>/dev/null || true; } | wc -l | tr -d ' ')"
check "no dead verify helper left" "0" "${out}"

echo "── gpu-test --multi on mock (no PyTorch: SKIP paths) ──"

out="$(run_in_mock rtx3090x2 - '
    bash "'"${SCRIPT_DIR}"'/bin/gpu-test" --multi 2>&1 || true
')"
check "multi test: detection block present" "Checking multi-GPU detection" "${out}"

echo "── GPU classification (single / homogeneous / heterogeneous / mixed-architecture) ──"

classify() {
    run_in_mock "$1" - '
        source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
        echo "TYPE=${GPU_CONFIG_TYPE}"
    '
}
check "2x identical -> homogeneous" "TYPE=homogeneous" "$(classify rtx3090x2)"
check "3x identical -> homogeneous" "TYPE=homogeneous" "$(classify rtx3090x3)"
check "3090+3060 same arch -> heterogeneous" "TYPE=heterogeneous" "$(classify mixed3090_3060)"
check "3090+4090 Ampere+Ada -> mixed-architecture" "TYPE=mixed-architecture" "$(classify mixed3090_4090)"
check "5090+3090+3050 -> mixed-architecture" "TYPE=mixed-architecture" "$(classify mix5090_3090_3050)"
check "1 GPU -> single" "TYPE=single" "$(classify rtx4090)"

echo "── GPU inventory (UUID / architecture per GPU) ──"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "U0=$(gpu_uuid_at 0)"
    echo "U1=$(gpu_uuid_at 1)"
    echo "A0=$(gpu_arch_at 0)"
    echo "A1=$(gpu_arch_at 1)"
')"
check "GPU 0 UUID present" "U0=GPU-00000000" "${out}"
check "GPU 1 UUID distinct" "U1=GPU-00000001" "${out}"
check "GPU 0 arch Ampere" "A0=Ampere" "${out}"
check "GPU 1 arch Ampere" "A1=Ampere" "${out}"

out="$(run_in_mock mix5090_3090_3050 - '
    source "'"${SCRIPT_DIR}"'/scripts/detect_gpu.sh"; run_gpu_detection
    echo "A0=$(gpu_arch_at 0) A1=$(gpu_arch_at 1) A2=$(gpu_arch_at 2)"
')"
check "mixed archs: Blackwell + Ampere + Ampere" "A0=Blackwell A1=Ampere A2=Ampere" "${out}"

echo "── intelligent auto-selection (exclusions + reasons) ──"

# Flagship scenario from the spec: 2x RTX 3090 + RTX 3050, ~40GB model.
# The two 3090s cover it; the 3050 is explicitly excluded WITH a reason.
out="$(run_in_mock rtx3090x2 - '
    export MOCK_EXTRA_GPU_COUNT=3
    export MOCK_NAME_2="NVIDIA GeForce RTX 3050"
    export MOCK_MEM_TOTAL_2="8192 MiB" MOCK_MEM_USED_2="500 MiB" MOCK_MEM_FREE_2="7692 MiB"
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_auto_select 40
    echo "SEL=${MG_SELECTED}:${MG_SEL_COUNT}"
    echo "EXCL=${MG_AUTO_EXCLUDED}"
')"
check "40GB on 2x3090+3050: selects 0 1" "SEL=0 1:2" "${out}"
check "3050 excluded with reason" "2=not needed" "${out}"

out="$(run_in_mock rtx3090x2 - '
    export MOCK_COMPUTE_APPS_OVERRIDE="GPU-00000000-0000-0000-0000-000000000000, 500 MiB"
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_auto_select 20
    echo "SEL=${MG_SELECTED}"
')"
check "busy GPU 0 avoided when GPU 1 suffices" "SEL=1" "${out}"

out="$(run_in_mock mix5090_3090_3050 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_auto_select 40 >/dev/null
    echo "SEL=${MG_SELECTED}:${MG_SEL_COUNT}"
')"
check "mixed 3-GPU: 5090+3090 beat adding the 3050" "SEL=0 1:2" "${out}"

out="$(run_in_mock mix5090_3090_3050 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_auto_select 40 >/dev/null
    mg_auto_report 40
')"
check "auto report explains the decision" "Reason:" "${out}"
check "auto report lists exclusions" "excluded" "${out}"
check "auto report marks estimate" "ESTIMATE" "${out}"

echo "── heterogeneous backend verdicts + split recommendation ──"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    echo "llamacpp=$(mg_hetero_verdict llamacpp)"
    echo "ollama=$(mg_hetero_verdict ollama)"
    echo "vllm=$(mg_hetero_verdict vllm)"
    echo "pytorch=$(mg_hetero_verdict pytorch)"
    echo "docker=$(mg_hetero_verdict docker)"
')"
check "llama.cpp: heterogeneous SUPPORTED" "llamacpp=SUPPORTED" "${out}"
check "ollama: heterogeneous PARTIAL" "ollama=PARTIAL" "${out}"
check "vllm: heterogeneous CAUTION" "vllm=CAUTION" "${out}"
check "pytorch: SUPPORTED via CVD" "pytorch=SUPPORTED" "${out}"
check "docker: SUPPORTED via toolkit" "docker=SUPPORTED" "${out}"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_hetero_verdict llamacpp >/dev/null
    echo "R=${MGH_REASON}"
')"
check "verdict includes a real explanation" "R=Layer" "${out}"

out="$(run_in_mock mixed3090_3060 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_parse_gpu_spec all
    echo "SPLIT=$(mg_recommend_split)"
')"
check "VRAM-proportional split 24+12" "SPLIT=24,12" "${out}"

out="$(run_in_mock rtx3090x2 - '
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    mg_parse_gpu_spec all
    echo "SPLIT=$(mg_recommend_split)"
')"
check "equal split for identical GPUs" "SPLIT=24,24" "${out}"

echo "── CUDA_VISIBLE_DEVICES mapping (logical vs physical) ──"

out="$(run_in_mock rtx3090x2 - '
    export CUDA_VISIBLE_DEVICES=1
    source "'"${SCRIPT_DIR}"'/scripts/gpu_select.sh"
    echo "ALLOWED=$(mg_allowed_ids | tr "\n" ",")"
    echo "LOGICAL=$(mg_logical_of_phys 1)"
')"
check "CVD=1 restricts the visible set" "ALLOWED=1," "${out}"
check "phys 1 becomes logical 0" "LOGICAL=0" "${out}"

echo "── gpu-status --expect (requested vs actual usage) ──"

out="$(run_in_mock rtx3090x2 - '
    export MOCK_COMPUTE_APPS_OVERRIDE=$'"'"'GPU-00000000-0000-0000-0000-000000000000, 500 MiB\nGPU-00000001-0000-0000-0000-000000000000, 900 MiB'"'"'
    bash "'"${SCRIPT_DIR}"'/bin/gpu-status" --expect 0,1 2>/dev/null || true
')"
check "verification block shown" "GPU USAGE VERIFICATION:" "${out}"
check "requested echoed" "REQUESTED GPUs:   0,1" "${out}"
check "both GPUs active" "ACTIVE GPUs:      0,1" "${out}"
check "GPU 0 verified with memory" "GPU 0: OK" "${out}"
check "GPU 1 verified with memory" "GPU 1: OK" "${out}"

out="$(run_in_mock rtx3090x2 - '
    export MOCK_COMPUTE_APPS_OVERRIDE="GPU-00000000-0000-0000-0000-000000000000, 500 MiB"
    bash "'"${SCRIPT_DIR}"'/bin/gpu-status" --expect 0,1 2>/dev/null || true
')"
check "idle GPU 1 raises WARN" "GPU 1: requested but no compute memory allocated" "${out}"

echo "── model-run: env config and gpu-mode collapse ──"

STUB2="$(mktemp -d)"
mkdir -p "${STUB2}/bin"
printf '#!/bin/bash\necho "VLLM-ARGS: $* CVD=${CUDA_VISIBLE_DEVICES:-unset}"\n' > "${STUB2}/bin/vllm-serve"
chmod +x "${STUB2}/bin/vllm-serve"

out="$(run_in_mock rtx3090x2 - '
    export AI_HOME="'"${STUB2}"'" GPU_MODE=auto GPU_IDS=0,1
    bash "'"${SCRIPT_DIR}"'/bin/model-run" M40 --backend vllm --size-gb 40 2>/dev/null
')"
check "env config: auto shards across GPU_IDS" "--tensor-parallel-size 2" "${out}"
check "env config: CVD covers both GPUs" "CVD=0,1" "${out}"

out="$(run_in_mock rtx3090x2 - '
    export AI_HOME="'"${STUB2}"'"
    bash "'"${SCRIPT_DIR}"'/bin/model-run" M --backend vllm --gpu-mode workload --gpus 0,1 --size-gb 7 2>/dev/null
')"
check "workload mode collapses to one GPU" "CVD=0" "${out}"
if [[ "${out}" == *"tensor-parallel-size"* ]]; then
    FAIL=$((FAIL + 1)); echo "  [FAIL] workload mode must NOT inject tensor parallelism"
else
    PASS=$((PASS + 1))
fi

rm -rf "${STUB2}"

echo "── ai-start GPU flag delegation ──"

out="$(run_in_mock rtx3090x2 - '
    bash "'"${SCRIPT_DIR}"'/bin/ai-start" vllm M --fit --size-gb 40 2>/dev/null || true
')"
check "ai-start delegates to model-run" "Delegating to model-run" "${out}"
check "delegated fit analysis runs" "Single GPU:" "${out}"

echo "── gpu-test --bench (no PyTorch: honest SKIP) ──"

out="$(run_in_mock rtx4090 - '
    export AI_HOME=/nonexistent-grk-test
    bash "'"${SCRIPT_DIR}"'/bin/gpu-test" --bench 2>&1 || true
')"
check "bench skips without PyTorch" "benchmark needs PyTorch" "${out}"
out="$(run_in_mock rtx4090 - 'bash "'"${SCRIPT_DIR}"'/bin/gpu-test" 2>&1 || true')"
check_absent "bench not run by default" "Benchmark (optional)" "${out}"

echo ""
echo "════════════════════════════════════════"
echo "  MULTI-GPU TESTS: ${PASS} passed, ${FAIL} failed"
echo "════════════════════════════════════════"
[[ "${FAIL}" -eq 0 ]]
