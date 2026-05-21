#!/usr/bin/env bash
# Create a dev container with ROCm GPU access + Oh My Bash, Cursor, Claude, Codex, tmux.
# Run ON the allocated compute node (via srun or after ssh).
#
# Examples:
#   IMAGE=docker.io/vllm/vllm-openai-rocm:nightly-... CONTAINER_NAME=vllm-openai-rocm PORT_MAP=8081:8000 ./setup_container.sh
#   ./setup_container.sh   # defaults from rocm_stack.env (vllm-dev)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=rocm_stack.env
source "${SCRIPT_DIR}/rocm_stack.env"

IMAGE="${IMAGE:-${VLLM_IMAGE}}"
CONTAINER_NAME="${CONTAINER_NAME:-vllm-dev}"
PORT_MAP="${PORT_MAP:-8080:8000}"
HOME_DIR="${HOME_DIR:-/shared/amdgpu/home/fai_qle}"

# vllm-openai* images use `vllm` as entrypoint; override for sleep infinity / exec setup.
VLLM_OPENAI_ENTRYPOINT=()
if [[ "${IMAGE}" == *vllm-openai* ]] || [[ "${IMAGE}" == *vllm/vllm-openai* ]]; then
  VLLM_OPENAI_ENTRYPOINT=(--entrypoint /bin/bash)
  CONTAINER_CMD=(-c "sleep infinity")
else
  CONTAINER_CMD=(sleep infinity)
fi

# shellcheck source=load_rocm_env.sh
source "${SCRIPT_DIR}/load_rocm_env.sh"

echo "==> Node: $(hostname)"
echo "==> Image: ${IMAGE}"
echo "==> Container: ${CONTAINER_NAME} (${PORT_MAP})"
echo "==> Mounts: ${DATA_MOUNT} (scratch), ${HF_HOME_MOUNT} (HF_HOME)"

mkdir -p "${HF_HOME}" 2>/dev/null || true

echo "==> Pulling image (skip if cached)..."
podman pull "docker://${IMAGE}" || true

IMAGE_ID="$(podman images -q "${IMAGE}" | head -1)"
if [[ -z "${IMAGE_ID}" ]]; then
  IMAGE_ID="$(podman images --format '{{.ID}}' --filter reference='*/vllm/vllm-openai-rocm' | head -1)"
fi
if [[ -z "${IMAGE_ID}" ]]; then
  echo "ERROR: image not found: ${IMAGE}" >&2
  exit 1
fi
echo "==> Image ID: ${IMAGE_ID}"

if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
  podman rm -f "${CONTAINER_NAME}"
fi

echo "==> Starting container ${CONTAINER_NAME}..."
podman run -d \
  --name "${CONTAINER_NAME}" \
  "${VLLM_OPENAI_ENTRYPOINT[@]}" \
  --ipc=host \
  --privileged \
  --cap-add=CAP_SYS_ADMIN \
  --device=/dev/kfd \
  --device=/dev/dri \
  --device=/dev/mem \
  --group-add render \
  --group-add video \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -v /sys:/sys:ro \
  -v "${DATA_MOUNT}:${DATA_MOUNT}" \
  -v "${HF_HOME_MOUNT}:${HF_HOME_MOUNT}" \
  -e "HF_HOME=${HF_HOME}" \
  -p "${PORT_MAP}" \
  "${IMAGE_ID}" \
  "${CONTAINER_CMD[@]}"

echo "==> Base packages..."
podman exec "${CONTAINER_NAME}" bash -c \
  'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq git curl wget sudo unzip openssh-client ca-certificates tmux 2>&1 | tail -3'

echo "==> vscode user..."
podman exec "${CONTAINER_NAME}" bash -c \
  'useradd -m -s /bin/bash -u 1000 vscode 2>/dev/null || true; echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode; chmod 440 /etc/sudoers.d/vscode; usermod -aG render vscode 2>/dev/null || true'

HOME_DIR="${HOME_DIR}" "${SCRIPT_DIR}/copy_ssh_to_container.sh" "${CONTAINER_NAME}"

echo "==> Oh My Bash (root + vscode)..."
OMB_INSTALL='bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended'
podman exec "${CONTAINER_NAME}" bash -c "${OMB_INSTALL}"
podman exec -u vscode "${CONTAINER_NAME}" bash -c "${OMB_INSTALL}"

echo "==> Cursor Agent CLI..."
podman exec "${CONTAINER_NAME}" bash -c 'curl -fsSL https://cursor.com/install | bash' || true

echo "==> Claude Code..."
podman exec "${CONTAINER_NAME}" bash -c \
  'if command -v claude >/dev/null 2>&1; then claude --version | head -1; else curl -fsSL https://claude.ai/install.sh | bash; fi'

echo "==> Codex CLI..."
podman exec "${CONTAINER_NAME}" bash -c 'command -v codex >/dev/null 2>&1 && codex --version | head -1 || {
  ARCH=$(uname -m)
  CODEX_ASSET=codex-x86_64-unknown-linux-musl.tar.gz
  [[ "$ARCH" == aarch64 || "$ARCH" == arm64 ]] && CODEX_ASSET=codex-aarch64-unknown-linux-musl.tar.gz
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/openai/codex/releases/download/rust-v0.132.0/${CODEX_ASSET}" -o "$tmp/codex.tar.gz"
  tar -xzf "$tmp/codex.tar.gz" -C "$tmp"
  install -m 755 "$(find "$tmp" -maxdepth 1 -type f -name "codex-*" | head -1)" /usr/local/bin/codex
  codex --version | head -1
}'

"${SCRIPT_DIR}/finish_container_setup.sh" "${CONTAINER_NAME}"

echo "==> Podman-as-docker shim + VS Code Machine settings..."
mkdir -p "${HOME_DIR}/bin"
cat > "${HOME_DIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/podman "$@"
EOF
chmod +x "${HOME_DIR}/bin/docker"

mkdir -p "${HOME_DIR}/.vscode-server/data/Machine"
cat > "${HOME_DIR}/.vscode-server/data/Machine/settings.json" <<EOF
{
  "dev.containers.dockerPath": "${HOME_DIR}/bin/docker",
  "docker.dockerPath": "${HOME_DIR}/bin/docker"
}
EOF

mkdir -p "${HOME_DIR}/.cursor-server/data/Machine"
cp "${HOME_DIR}/.vscode-server/data/Machine/settings.json" \
  "${HOME_DIR}/.cursor-server/data/Machine/settings.json"

echo "==> ROCm GPU check (container)..."
GPU_COUNT="$(podman exec "${CONTAINER_NAME}" bash -c \
  'rocminfo 2>/dev/null | grep -c "Device Type:.*GPU" || echo 0')"
if [[ "${GPU_COUNT}" -eq 0 ]]; then
  echo "ERROR: container rocminfo found no GPU agents." >&2
  podman exec "${CONTAINER_NAME}" bash -c 'rocminfo 2>&1 | head -15' || true
  exit 1
fi
echo "    ${GPU_COUNT} GPU agent(s) visible in container"
command -v vllm >/dev/null && podman exec "${CONTAINER_NAME}" bash -c 'vllm --version 2>&1 | head -1 | sed "s/^/vllm: /"' || true

echo "==> Container status:"
podman ps --filter "name=${CONTAINER_NAME}"

echo ""
echo "SUCCESS on $(hostname)"
echo "NODE=$(hostname)"
echo "CONTAINER=${CONTAINER_NAME}"
echo "IMAGE=${IMAGE}"
echo "PORT=${PORT_MAP}"
