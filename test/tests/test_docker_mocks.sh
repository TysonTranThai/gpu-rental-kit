#!/usr/bin/env bash
# =============================================================================
# test_docker_mocks.sh — Docker detection + GPU passthrough verification
# =============================================================================
# Uses a mock `docker` binary. Only tests the read-only detection paths
# (detect_docker, verify_docker_gpu). The install path
# (install_nvidia_container_toolkit) touches the real system (apt, curl,
# sudo) and is only ever exercised on a Linux GPU machine — never here.
# =============================================================================
TEST_NAME="docker_mocks"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

# --- Docker installed and running ---
result="$(setup_mock_docker_env yes no; capture scripts/setup_docker.sh \
    'detect_docker >/dev/null 2>&1; echo "${HAS_DOCKER}"')"
assert_eq "yes" "${result}" "docker present → HAS_DOCKER=yes"

# --- Docker daemon not reachable ---
result="$(setup_mock_docker_env no no; capture scripts/setup_docker.sh \
    'detect_docker >/dev/null 2>&1; echo "${HAS_DOCKER}"')"
assert_eq "no" "${result}" "docker daemon down → HAS_DOCKER=no"

# --- verify_docker_gpu: passthrough working ---
result="$(setup_mock_docker_env yes yes; capture scripts/setup_docker.sh \
    'HAS_DOCKER=yes; verify_docker_gpu >/dev/null 2>&1; echo "${DOCKER_GPU_OK}"')"
assert_eq "yes" "${result}" "docker GPU passthrough OK → DOCKER_GPU_OK=yes"

# --- verify_docker_gpu: passthrough broken ---
result="$(setup_mock_docker_env yes no; capture scripts/setup_docker.sh \
    'HAS_DOCKER=yes; verify_docker_gpu >/dev/null 2>&1; echo "${DOCKER_GPU_OK}"')"
assert_eq "no" "${result}" "docker GPU passthrough broken → DOCKER_GPU_OK=no"

# --- no docker at all (binary missing) ---
result="$(PATH="/usr/bin:/bin" capture scripts/setup_docker.sh \
    'detect_docker >/dev/null 2>&1; echo "${HAS_DOCKER}"')"
assert_eq "no" "${result}" "docker missing → HAS_DOCKER=no"

report_results
