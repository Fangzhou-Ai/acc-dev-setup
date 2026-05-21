#!/usr/bin/env bash
# Load ROCm user-space and verify AMDGPU kernel driver on MI355 compute nodes.
# Source from setup scripts or interactively: source load_rocm_env.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=rocm_stack.env
source "${SCRIPT_DIR}/rocm_stack.env"

if ! command -v module >/dev/null 2>&1; then
  # Modules may already be initialized via /etc/profile.d
  if [[ -f /etc/profile.d/modules.sh ]]; then
    # shellcheck source=/dev/null
    source /etc/profile.d/modules.sh
  elif [[ -f /usr/share/modules/init/bash ]]; then
    # shellcheck source=/dev/null
    source /usr/share/modules/init/bash
  fi
fi

if command -v module >/dev/null 2>&1; then
  if ! module is-loaded "${ROCM_MODULE}" 2>/dev/null; then
    echo "==> Loading environment module: ${ROCM_MODULE}"
    module load "${ROCM_MODULE}"
  else
    echo "==> ROCm module already loaded: ${ROCM_MODULE}"
  fi
else
  echo "WARNING: 'module' command not found; ROCm tools may be missing from PATH." >&2
fi

echo "==> Kernel driver check (amdgpu + KFD)"
if ! lsmod | grep -q '^amdgpu '; then
  echo "WARNING: amdgpu kernel module is not loaded." >&2
else
  echo "    amdgpu loaded ($(cat /sys/module/amdgpu/version 2>/dev/null || echo unknown))"
fi

if [[ ! -e /dev/kfd ]]; then
  echo "ERROR: /dev/kfd missing — GPU compute stack not available." >&2
  exit 1
fi
echo "    /dev/kfd present ($(ls -l /dev/kfd))"

if ! ls /dev/dri/renderD* >/dev/null 2>&1; then
  echo "WARNING: no /dev/dri/renderD* devices found." >&2
else
  echo "    $(ls /dev/dri/renderD* 2>/dev/null | wc -l) render nodes under /dev/dri"
fi

if command -v rocminfo >/dev/null 2>&1; then
  if rocminfo 2>&1 | grep -q 'ROCk module is NOT loaded'; then
    echo "WARNING: rocminfo reports ROCk is NOT loaded (check amdgpu driver / permissions)." >&2
  else
    echo "    rocminfo: ROCk driver detected"
  fi
fi
