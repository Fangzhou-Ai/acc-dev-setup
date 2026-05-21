# MI355X container setup (Podman + VS Code + Oh My Bash)

**Canonical instructions:** [example_setup.md](./example_setup.md) (manual steps + how automation maps to them).

**Agents in this folder:** see [AGENTS.md](./AGENTS.md) — you will be asked on each new session whether to allocate a GPU node and create the `vllm-dev` container.

**One command (allocate + setup):**

```bash
./start_allocation.sh
```

Active allocation details (node, job ID, image) are written to [connection_info.txt](./connection_info.txt) after `./start_allocation.sh`.

```bash
# On your allocated node (after ssh):
podman ps --filter name=vllm-dev
/shared/amdgpu/home/fai_qle/bin/docker ps   # same, for VS Code
```

## 1. Reserve a GPU node

```bash
salloc --reservation=mi355-gpu-34_gpu-39_gpu-40_gpu-49_gpu-50_gpu-51_gpu-55_gpu-56_reservation --exclusive --account=wrh --mem=0
# OR
salloc --reservation=mi355-gpu-41_gpu-42_gpu-43_gpu-44_gpu-45_gpu-46_gpu-47_gpu-48_reservation --exclusive --account=wrh --mem=0
```

Run all podman commands **on the allocated compute node** (e.g. `mi355-gpu-40`), not the SLURM controller.

## 2. Create / refresh the container

```bash
cd /shared/amdgpu/home/fai_qle/prepare_env
./setup_container.sh
```

Or manually follow `example_setup.md` (pull image, `podman run`, fake `docker` shim).

`setup_container.sh` copies your cluster `~/.ssh` into the container (`/root` and `vscode`) for private `git clone`. To refresh an existing container: `./copy_ssh_to_container.sh vllm-dev`.

## 3. Connect with VS Code on your PC (Windows)

### SSH config — add to `C:\Users\fai\.ssh\config`

```sshconfig
Host amd-login
    HostName aac16.amd.com
    User fai_qle
    IdentityFile C:\Users\fai\.ssh\id_ed25519
    ServerAliveInterval 60

Host mi355-gpu-39
    HostName mi355-gpu-39
    User fai_qle
    IdentityFile C:\Users\fai\.ssh\id_ed25519
    ProxyJump amd-login
    ServerAliveInterval 60
```

Test in PowerShell: `ssh mi355-gpu-39`

### VS Code extensions (local)

- **Remote - SSH** (`ms-vscode-remote.remote-ssh`)
- **Dev Containers** (`ms-vscode-remote.remote-containers`)

### Attach to the running container

1. VS Code → **Remote-SSH: Connect to Host...** → your node (see `connection_info.txt`)
2. **Command Palette** → **Dev Containers: Attach to Running Container...** → **`vllm-dev`**
3. Remote user: **`root`**

VS Code opens **`/root`** in the container. Put your own files there. (The image also has vLLM at `/app/vllm` if you need it — ignore that unless you want it.)

Machine settings on the node already point VS Code at the podman shim:

`/shared/amdgpu/home/fai_qle/bin/docker` → `podman`

If Dev Containers cannot find Docker, set in VS Code settings (Remote window):

```json
"dev.containers.dockerPath": "/shared/amdgpu/home/fai_qle/bin/docker"
```

## 4. What is installed inside the container

| Component | Users | Notes |
|-----------|-------|-------|
| Oh My Bash | `root` | `ohmybash/oh-my-bash` |
| Cursor Agent CLI | `root` | `agent` in `~/.local/bin` |
| Claude Code | `root` | `claude` — run once to log in |
| OpenAI Codex | system | `codex` in `/usr/local/bin` — run once to log in |
| tmux | system | `tmux` via apt |
| Host ROCm module | 7.2.3 | See [`rocm_stack.env`](./rocm_stack.env) |
| vLLM container image | — | `vllm/vllm-openai-rocm:nightly` (container name `vllm-dev`) |

Port `8080` on the host maps to `8000` in the container (vLLM API default).

## 5. Useful commands

```bash
# Shell in container
podman exec -it -u vscode vllm-dev bash -l

# Cursor Agent
podman exec -u vscode vllm-dev bash -l -c 'agent --version'

# Stop / remove
podman stop vllm-dev
podman rm vllm-dev
```
