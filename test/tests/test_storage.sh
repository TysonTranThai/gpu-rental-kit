#!/usr/bin/env bash
# =============================================================================
# test_storage.sh — persistence classification logic
# =============================================================================
# Tests classify_persistence (pure logic) plus a Mac-safe detect_storage run.
# =============================================================================
TEST_NAME="storage"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

# --- container: local storage dies on container deletion, survives restart ---
result="$(capture scripts/setup_storage.sh \
    'PERSISTENT_MOUNTS=(); IS_DOCKER=yes; IS_VM=no; classify_persistence; \
     echo "${STORAGE_CLASSIFICATION}|${STORAGE_CONFIDENCE}|${STORAGE_STATE}|${STORAGE_SURVIVES_RESTART}|${STORAGE_SURVIVES_DELETE}|${STORAGE_SURVIVES_RENTAL_END}"')"
assert_eq "TEMPORARY|high|container|yes|no|no" "${result}" "container state matrix"

# --- VM: same shape, labeled vm ---
result="$(capture scripts/setup_storage.sh \
    'PERSISTENT_MOUNTS=(); IS_DOCKER=no; IS_VM=yes; classify_persistence; \
     echo "${STORAGE_CLASSIFICATION}|${STORAGE_STATE}|${STORAGE_SURVIVES_RESTART}|${STORAGE_SURVIVES_DELETE}"')"
assert_eq "TEMPORARY|vm|yes|no" "${result}" "vm state matrix"

# --- unknown environment: conservative advisory ---
result="$(capture scripts/setup_storage.sh \
    'PERSISTENT_MOUNTS=(); IS_DOCKER=no; IS_VM=no; classify_persistence; \
     echo "${STORAGE_CLASSIFICATION}|${STORAGE_STATE}|${STORAGE_ADVISORY}"')"
assert_contains "${result}" "TEMPORARY|unknown" "unknown env → TEMPORARY"
assert_contains "${result}" "DO NOT RELY ON LOCAL STORAGE" "unknown env → persistence warning"

# --- persistent mounts found → PERSISTENT/UNKNOWN with low confidence ---
result="$(capture scripts/setup_storage.sh \
    'PERSISTENT_MOUNTS=(/mnt/data); IS_DOCKER=no; IS_VM=no; classify_persistence; \
     echo "${STORAGE_CLASSIFICATION}|${STORAGE_CONFIDENCE}"')"
assert_eq "PERSISTENT/UNKNOWN|low" "${result}" "candidate mount → PERSISTENT/UNKNOWN low confidence"

# --- advisory for unverified persistent mounts keeps the warning ---
result="$(capture scripts/setup_storage.sh \
    'PERSISTENT_MOUNTS=(/data); IS_DOCKER=no; IS_VM=yes; classify_persistence; \
     echo "${STORAGE_ADVISORY}"')"
assert_contains "${result}" "DO NOT RELY ON LOCAL STORAGE" "persistent-unknown advisory"

# --- detect_storage runs safely on macOS (no /proc, no /mnt, no crash) ---
result="$(capture scripts/setup_storage.sh \
    'IS_DOCKER=no; IS_VM=no; detect_storage >/dev/null 2>&1; \
     echo "${STORAGE_CLASSIFICATION}|${STORAGE_CONFIDENCE}"')"
assert_contains "${result}" "TEMPORARY|high" "detect_storage Mac-safe default classification"

# --- detect_storage survives a mounts fixture (root-only) ---
result="$(KIT_MOUNTS_FILE="${TEST_ROOT}/mocks/mounts/root_only.txt" capture scripts/setup_storage.sh \
    'IS_DOCKER=no; IS_VM=no; detect_storage >/dev/null 2>&1; \
     echo "${STORAGE_CLASSIFICATION}|${STORAGE_CONFIDENCE}"')"
assert_contains "${result}" "TEMPORARY|high" "root-only mounts fixture → TEMPORARY"

report_results
