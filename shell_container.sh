#!/usr/bin/env bash
# Open an interactive shell in vllm-dev on the allocated MI355 compute node.
#
# Do NOT use `podman attach` — PID 1 is `sleep infinity` and attach will hang forever.
# Use `podman exec -it` instead (this script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="${CONTAINER_NAME:-vllm-dev}"
JOB_NAME="${JOB_NAME:-vllm-dev-setup}"
HOME_DIR="${HOME_DIR:-/shared/amdgpu/home/fai_qle}"

read -r JOBID NODE < <(squeue -u "$(whoami)" -n "${JOB_NAME}" -h -o "%i %N" 2>/dev/null | head -1 || true)
if [[ -z "${JOBID}" ]]; then
  if [[ -f "${SCRIPT_DIR}/connection_info.txt" ]]; then
    # shellcheck source=/dev/null
    JOBID="$(grep -E '^SLURM_JOB_ID=' "${SCRIPT_DIR}/connection_info.txt" | cut -d= -f2)"
    NODE="$(grep -E '^NODE=' "${SCRIPT_DIR}/connection_info.txt" | cut -d= -f2)"
  fi
fi
if [[ -z "${JOBID}" || -z "${NODE}" ]]; then
  echo "ERROR: no running ${JOB_NAME} job. Run ./start_allocation.sh first." >&2
  exit 1
fi

echo "==> Job ${JOBID} on ${NODE} — shell in ${CONTAINER_NAME} (Ctrl-D to exit)"
exec srun --jobid="${JOBID}" --nodelist="${NODE}" --overlap --pty \
  podman exec -it -w "${HOME_DIR}" "${CONTAINER_NAME}" bash
