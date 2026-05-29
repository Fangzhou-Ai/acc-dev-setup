#!/usr/bin/env bash
# Install CLI tools inside the default vllm-dev container (vllm-openai-rocm:nightly).
# Run via: podman exec vllm-dev bash -s < install_container_tools.sh
set -euo pipefail

echo "==> tmux..."
if ! command -v tmux >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq tmux ncurses-term
else
  echo "    tmux already installed: $(tmux -V)"
fi

echo "==> Claude Code..."
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
else
  echo "    claude already installed: $(claude --version 2>/dev/null || true)"
fi

echo "==> OpenAI Codex CLI..."
if ! command -v codex >/dev/null 2>&1; then
  ARCH="$(uname -m)"
  case "${ARCH}" in
    x86_64) CODEX_ASSET="codex-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64|arm64) CODEX_ASSET="codex-aarch64-unknown-linux-musl.tar.gz" ;;
    *) echo "ERROR: unsupported arch for Codex: ${ARCH}" >&2; exit 1 ;;
  esac
  # Resolve the latest release tag (follow the /releases/latest redirect)
  CODEX_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/openai/codex/releases/latest | sed 's#.*/tag/##')"
  [[ -z "${CODEX_TAG}" ]] && { echo "ERROR: could not resolve latest codex tag" >&2; exit 1; }
  CODEX_URL="https://github.com/openai/codex/releases/download/${CODEX_TAG}/${CODEX_ASSET}"
  tmpdir="$(mktemp -d)"
  curl -fsSL "${CODEX_URL}" -o "${tmpdir}/codex.tar.gz"
  tar -xzf "${tmpdir}/codex.tar.gz" -C "${tmpdir}"
  bin="$(find "${tmpdir}" -maxdepth 1 -type f -name 'codex-*' | head -1)"
  install -m 755 "${bin}" /usr/local/bin/codex
  rm -rf "${tmpdir}"
else
  echo "    codex already installed: $(codex --version 2>/dev/null || true)"
fi

# Ensure ~/.local/bin on PATH (claude, cursor agent)
if ! grep -q '\.local/bin' ~/.bashrc 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi
if [[ ! -f ~/.bash_profile ]] || ! grep -q bashrc ~/.bash_profile 2>/dev/null; then
  echo '[ -f ~/.bashrc ] && . ~/.bashrc' >> ~/.bash_profile
fi

echo "==> Verified:"
command -v tmux && tmux -V || echo "    tmux: not in PATH"
command -v claude && claude --version 2>/dev/null | head -1 || echo "    claude: not in PATH"
command -v codex && codex --version 2>/dev/null | head -1 || echo "    codex: not in PATH"
