#!/usr/bin/env bash
# Copy SSH credentials from the host (login/compute node) into a running container
# so git clone over SSH works without generating new keys.
#
# Usage: copy_ssh_to_container.sh <container_name>
# Env:   SSH_SOURCE_DIR — host .ssh directory (default: $HOME_DIR/.ssh or $HOME/.ssh)
set -euo pipefail

CONTAINER_NAME="${1:?container name required}"
HOME_DIR="${HOME_DIR:-/shared/amdgpu/home/fai_qle}"

if [[ -n "${SSH_SOURCE_DIR:-}" ]]; then
  SOURCE_SSH="${SSH_SOURCE_DIR}"
elif [[ -d "${HOME_DIR}/.ssh" ]]; then
  SOURCE_SSH="${HOME_DIR}/.ssh"
elif [[ -d "${HOME}/.ssh" ]]; then
  SOURCE_SSH="${HOME}/.ssh"
else
  echo "==> SSH: skip (no .ssh found under ${HOME_DIR} or \$HOME on $(hostname))"
  exit 0
fi

if [[ ! -d "${SOURCE_SSH}" ]]; then
  echo "==> SSH: skip (${SOURCE_SSH} is not a directory)"
  exit 0
fi

echo "==> SSH: copy ${SOURCE_SSH} from $(hostname) into ${CONTAINER_NAME} (root + vscode)..."

podman exec "${CONTAINER_NAME}" rm -rf /tmp/host-ssh-copy
podman exec "${CONTAINER_NAME}" mkdir -p /tmp/host-ssh-copy
podman cp "${SOURCE_SSH}/." "${CONTAINER_NAME}:/tmp/host-ssh-copy/"

podman exec "${CONTAINER_NAME}" bash -c '
set -euo pipefail

install_ssh_for_user() {
  local user="$1"
  local home="$2"
  local dest="${home}/.ssh"

  rm -rf "${dest}"
  mkdir -p "${dest}"
  cp -a /tmp/host-ssh-copy/. "${dest}/"

  # Drop agent sockets and other non-file artifacts.
  find "${dest}" -type s -delete 2>/dev/null || true
  find "${dest}" \( -name "agent*" -o -name "*.sock" \) -delete 2>/dev/null || true

  chmod 700 "${dest}"
  find "${dest}" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} + 2>/dev/null || true
  find "${dest}" -type f \( -name "config" -o -name "known_hosts" -o -name "known_hosts.*" -o -name "authorized_keys" \) \
    -exec chmod 600 {} + 2>/dev/null || true
  find "${dest}" -type f -name "*.pub" -exec chmod 644 {} + 2>/dev/null || true

  if [[ -n "${user}" ]]; then
    chown -R "${user}:${user}" "${dest}"
  fi
}

install_ssh_for_user "" /root
if id vscode &>/dev/null; then
  install_ssh_for_user vscode /home/vscode
fi

rm -rf /tmp/host-ssh-copy
'

podman exec "${CONTAINER_NAME}" bash -c '
shopt -s nullglob
keys=(/root/.ssh/id_*)
has_key=0
for k in "${keys[@]}"; do
  [[ "${k}" == *.pub ]] && continue
  has_key=1
  break
done
if (( has_key )); then
  echo "    SSH keys installed under /root/.ssh"
else
  echo "    SSH: copied .ssh but no private id_* key found (git over SSH may still need a key)"
fi
'
