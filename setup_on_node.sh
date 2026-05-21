#!/usr/bin/env bash
# Run ON the allocated compute node (via srun or after ssh).
# Wrapper around setup_container.sh (default: vllm-dev on port 8080).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export IMAGE="${IMAGE:-}"
export CONTAINER_NAME="${CONTAINER_NAME:-vllm-dev}"
export PORT_MAP="${PORT_MAP:-8080:8000}"

"${SCRIPT_DIR}/setup_container.sh"

# Persist module load for interactive SSH on this node (idempotent).
HOME_DIR="${HOME_DIR:-/shared/amdgpu/home/fai_qle}"
# shellcheck source=rocm_stack.env
source "${SCRIPT_DIR}/rocm_stack.env"
BASHRC_SNIPPET="${HOME_DIR}/.bashrc.d/mi355-rocm.sh"
mkdir -p "${HOME_DIR}/.bashrc.d"
cat > "${BASHRC_SNIPPET}" <<EOF
# MI355 ROCm — auto-added by prepare_env setup ($(date -Iseconds))
case "\$(hostname)" in
  mi355-gpu-*)
    if command -v module >/dev/null 2>&1; then
      module load ${ROCM_MODULE} 2>/dev/null || true
    fi
    ;;
esac
EOF
grep -qF 'mi355-rocm.sh' "${HOME_DIR}/.bashrc" 2>/dev/null || \
  echo '[ -f ~/.bashrc.d/mi355-rocm.sh ] && . ~/.bashrc.d/mi355-rocm.sh' >> "${HOME_DIR}/.bashrc"

echo "==> Container status:"
podman ps --filter "name=${CONTAINER_NAME}"

echo ""
echo "SUCCESS on $(hostname)"
echo "NODE=$(hostname)"
echo "CONTAINER=${CONTAINER_NAME}"
echo "JOB_READY=1"
