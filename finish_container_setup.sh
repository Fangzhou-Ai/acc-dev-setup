#!/usr/bin/env bash
# Finish setup steps after container is running (HF_HOME, PATH, tool verify).
set -euo pipefail

CONTAINER_NAME="${1:?container name required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HF_HOME_OVERRIDE="${HF_HOME:-}"
# shellcheck source=rocm_stack.env
source "${SCRIPT_DIR}/rocm_stack.env"
if [[ -n "${HF_HOME_OVERRIDE}" ]]; then
  HF_HOME="${HF_HOME_OVERRIDE}"
fi

echo "==> Dev container metadata (default workspace ${HOME_DIR:-/shared/amdgpu/home/fai_qle})..."
WORKSPACE="${HOME_DIR:-/shared/amdgpu/home/fai_qle}"
podman exec "${CONTAINER_NAME}" mkdir -p "${WORKSPACE}/.devcontainer"
podman cp "${SCRIPT_DIR}/container.devcontainer.json" \
  "${CONTAINER_NAME}:${WORKSPACE}/.devcontainer/devcontainer.json"

echo "==> HF_HOME=${HF_HOME} in ${CONTAINER_NAME}..."
podman exec "${CONTAINER_NAME}" bash -c \
  "mkdir -p '${HF_HOME}'; printf '%s\n' 'export HF_HOME=${HF_HOME}' > /etc/profile.d/hf_home.sh"

for u in "" vscode; do
  if [[ -z "$u" ]]; then
    podman exec "${CONTAINER_NAME}" bash -c \
      "grep -qF 'HF_HOME=${HF_HOME}' ~/.bashrc 2>/dev/null || echo 'export HF_HOME=${HF_HOME}' >> ~/.bashrc; \
       grep -q '.local/bin' ~/.bashrc || echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc; \
       grep -q bashrc ~/.bash_profile 2>/dev/null || echo '[ -f ~/.bashrc ] && . ~/.bashrc' >> ~/.bash_profile" || true
  else
    podman exec -u "${u}" "${CONTAINER_NAME}" bash -c \
      "grep -qF 'HF_HOME=${HF_HOME}' ~/.bashrc 2>/dev/null || echo 'export HF_HOME=${HF_HOME}' >> ~/.bashrc; \
       grep -q '.local/bin' ~/.bashrc || echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc; \
       grep -q bashrc ~/.bash_profile 2>/dev/null || echo '[ -f ~/.bashrc ] && . ~/.bashrc' >> ~/.bash_profile" || true
  fi
done

echo "==> Codex (if missing, latest)..."
podman exec "${CONTAINER_NAME}" bash -c 'command -v codex >/dev/null 2>&1 && codex --version | head -1 || {
  ARCH=$(uname -m)
  CODEX_ASSET=codex-x86_64-unknown-linux-musl.tar.gz
  [[ "$ARCH" == aarch64 || "$ARCH" == arm64 ]] && CODEX_ASSET=codex-aarch64-unknown-linux-musl.tar.gz
  # Resolve the latest release tag (follow the /releases/latest redirect)
  CODEX_TAG=$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/openai/codex/releases/latest | sed "s#.*/tag/##")
  [[ -z "$CODEX_TAG" ]] && { echo "ERROR: could not resolve latest codex tag" >&2; exit 1; }
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/openai/codex/releases/download/${CODEX_TAG}/${CODEX_ASSET}" -o "$tmp/codex.tar.gz"
  tar -xzf "$tmp/codex.tar.gz" -C "$tmp"
  install -m 755 "$(find "$tmp" -maxdepth 1 -type f -name "codex-*" | head -1)" /usr/local/bin/codex
  codex --version | head -1
}'

echo "==> Verify mounts + tools..."
podman exec "${CONTAINER_NAME}" bash -lc "
echo HF_HOME=\$HF_HOME
test -d '${HF_HOME}' && echo 'HF mount: OK'
mount | grep -E '/data|amd_int/models|amdgpu/home/fai_qle' || true
export PATH=\"/root/.local/bin:/usr/local/bin:\$PATH\"
command -v agent >/dev/null && agent --version 2>&1 | head -1 | sed 's/^/agent: /' || echo 'agent: MISSING'
command -v claude >/dev/null && claude --version 2>&1 | head -1 | sed 's/^/claude: /' || echo 'claude: MISSING'
command -v codex >/dev/null && codex --version 2>&1 | head -1 | sed 's/^/codex: /' || echo 'codex: MISSING'
command -v tmux >/dev/null && tmux -V | sed 's/^/tmux: /' || echo 'tmux: MISSING'
rocminfo 2>/dev/null | grep -c 'Device Type:.*GPU' | sed 's/^/gpus: /'
"
