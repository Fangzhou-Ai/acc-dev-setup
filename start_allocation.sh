#!/usr/bin/env bash
# Allocate a MI355 node and run full container setup on it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=rocm_stack.env
source "${SCRIPT_DIR}/rocm_stack.env"
TIME="${TIME:-08:00:00}"
JOB_NAME="${JOB_NAME:-vllm-dev-setup}"

RESERVATIONS=(
  "mi355-gpu-34_gpu-39_gpu-40_gpu-49_gpu-50_gpu-51_gpu-55_gpu-56_reservation"
  "mi355-gpu-41_gpu-42_gpu-43_gpu-44_gpu-45_gpu-46_gpu-47_gpu-48_reservation"
)

# Reuse existing job if present
EXISTING="$(squeue -u "$(whoami)" -n "${JOB_NAME}" -h -o "%i %N" 2>/dev/null | head -1 || true)"
if [[ -n "${EXISTING}" ]]; then
  JOBID="${EXISTING%% *}"
  NODE="${EXISTING#* }"
  echo "==> Reusing existing job ${JOBID} on ${NODE}"
else
  JOBID=""
  for RES in "${RESERVATIONS[@]}"; do
    echo "==> Trying reservation: ${RES}"
    if OUT="$(salloc --reservation="${RES}" --exclusive --account=wrh --mem=0 \
      -N1 --time="${TIME}" -J "${JOB_NAME}" --no-shell 2>&1)"; then
      echo "${OUT}"
      JOBID="$(squeue -u "$(whoami)" -n "${JOB_NAME}" -h -o "%i" | head -1)"
      NODE="$(squeue -j "${JOBID}" -h -o "%N" | head -1)"
      break
    else
      echo "${OUT}" >&2
    fi
  done
  if [[ -z "${JOBID}" ]]; then
    echo "ERROR: could not allocate a node with any reservation." >&2
    exit 1
  fi
  echo "==> Allocated job ${JOBID} on ${NODE}"
  sleep 2
fi

echo "==> Running setup on ${NODE} (job ${JOBID})..."
srun --jobid="${JOBID}" --overlap bash "${SCRIPT_DIR}/setup_on_node.sh"

# Update connection_info.txt
CONN="${SCRIPT_DIR}/connection_info.txt"
{
  echo "# Auto-updated: $(date -Iseconds)"
  echo "SLURM_JOB_ID=${JOBID}"
  echo "SLURM_JOB_NAME=${JOB_NAME}"
  echo "NODE=${NODE}"
  echo "CONTAINER=vllm-dev"
  echo "CONTAINER_PORT=8080:8000"
  echo "ROCM_VERSION=${ROCM_VERSION}"
  echo "ROCM_MODULE=${ROCM_MODULE}"
  echo "IMAGE=${VLLM_IMAGE}"
  echo ""
  echo "# SSH config (Windows): C:\\Users\\fai\\.ssh\\config"
  echo "Host ${NODE}"
  echo "    HostName ${NODE}"
  echo "    User fai_qle"
  echo "    IdentityFile C:\\Users\\fai\\.ssh\\id_ed25519"
  echo "    ProxyJump amd-login"
  echo "    ServerAliveInterval 60"
  echo ""
  echo "# VS Code: Remote-SSH -> ${NODE} -> Dev Containers: Attach -> vllm-dev (user: root, folder: ${HOME_DIR})"
  echo "# Release: scancel ${JOBID}"
} > "${CONN}"

echo ""
echo "==> Done. Connection details: ${CONN}"
cat "${CONN}"
