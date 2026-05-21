# MI355X dev container setup

Canonical instructions. Automated scripts implement the same steps plus optional extras.

## Quick start (automated — preferred)

From this folder, on the cluster login node:

```bash
./start_allocation.sh
```

Or ask the agent in this folder — it will offer to run the same workflow.

Writes connection details to `connection_info.txt` (node name, job ID, SSH snippet).

Release when done: `scancel <JOBID>`

---

## 1. Reserve a MI355X node

```bash
salloc --reservation=mi355-gpu-34_gpu-39_gpu-40_gpu-49_gpu-50_gpu-51_gpu-55_gpu-56_reservation --exclusive --account=wrh --mem=0
```

**OR**

```bash
salloc --reservation=mi355-gpu-41_gpu-42_gpu-43_gpu-44_gpu-45_gpu-46_gpu-47_gpu-48_reservation --exclusive --account=wrh --mem=0
```

Automated scripts add: `-N1 --time=08:00:00 -J vllm-dev-setup --no-shell`

Run all `podman` commands on the **allocated compute node** (e.g. `mi355-gpu-40`), not the SLURM controller.

### ROCm version (latest stable)

| Layer | Version | Notes |
|-------|---------|-------|
| **ROCm (stable)** | **7.2.3** | AMD [latest stable release](https://github.com/ROCm/ROCm/releases/latest) (May 2026); official MI355X support |
| Host module | `rocm/7.2.3` | `module load` on compute nodes |
| Container image | `rocm/vllm-dev:rocm7.2.3_torch2.11_v0.21.0_20260519` | Matches host ROCm user-space |

Pinned in [`rocm_stack.env`](./rocm_stack.env). **Avoid** `rocm/7.13.x` and `rocm7.13` image tags — those are preview/nightly builds on this cluster.

### Load ROCm (required before GPU checks)

On the compute node:

```bash
source /shared/amdgpu/home/fai_qle/prepare_env/load_rocm_env.sh
rocminfo | head -10    # should report ROCk driver loaded
```

Automated scripts call `load_rocm_env.sh` automatically.

---

## 2. Podman pull AMD vLLM image

```bash
source prepare_env/rocm_stack.env   # sets VLLM_IMAGE
podman pull "docker://${VLLM_IMAGE}"
```

Use your own image tag here if you update the stack.

---

## 3. Podman create container (port forwarding)

Use the image ID from `podman images` (example: `9564a9f428e0`):

```bash
podman run -d \
    --name vllm-dev \
    --ipc=host \
    --privileged \
    --cap-add=CAP_SYS_ADMIN \
    --device=/dev/kfd \
    --device=/dev/dri \
    --device=/dev/mem \
    --group-add render \
    --cap-add=SYS_PTRACE \
    --security-opt seccomp=unconfined \
    -v /sys:/sys:ro \
    -v /data:/data \
    -v /shared/data/amd_int/models:/shared/data/amd_int/models \
    -e HF_HOME=/shared/data/amd_int/models \
    -p 8080:8000 \
    9564a9f428e0 \
    sleep infinity
```

`-v /sys:/sys:ro` lets `rocminfo` / `rocm-smi` inside the container read KFD GPU topology (without it you get `ROCk module is NOT loaded`).

Always mount `/data` (local scratch) and `/shared/data/amd_int/models` with `HF_HOME=/shared/data/amd_int/models` (shared NFS — reuse weights across nodes/jobs). `setup_container.sh` / `setup_on_node.sh` do this automatically.

`setup_on_node.sh` resolves the image ID automatically.

### Verify GPUs inside the container

```bash
podman exec vllm-dev rocminfo | grep -E "Agent|Device Type|gfx"
podman exec vllm-dev rocm-smi
```

Expect multiple `gfx950` GPU agents on MI355 nodes.

---

## 4. SSH config on your PC (Windows)

Edit `C:\Users\fai\.ssh\config`:

```sshconfig
Host amd-login
    HostName aac16.amd.com
    User fai_qle
    IdentityFile C:\Users\fai\.ssh\id_ed25519
    ServerAliveInterval 60

# Use your allocated node hostname (example: mi355-gpu-40)
Host mi355-gpu-40
    HostName mi355-gpu-40
    User fai_qle
    IdentityFile C:\Users\fai\.ssh\id_ed25519
    ProxyJump amd-login
    ServerAliveInterval 60
```

Test in PowerShell: `ssh mi355-gpu-40`

---

## 5. Fake `docker` → `podman` (for VS Code Dev Containers)

On the **compute node** (after `ssh <your-node>`):

```bash
mkdir -p /shared/amdgpu/home/fai_qle/bin
cat > /shared/amdgpu/home/fai_qle/bin/docker <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/podman "$@"
EOF
chmod +x /shared/amdgpu/home/fai_qle/bin/docker
```

Point VS Code at the shim:

```bash
mkdir -p /shared/amdgpu/home/fai_qle/.vscode-server/data/Machine
cat > /shared/amdgpu/home/fai_qle/.vscode-server/data/Machine/settings.json <<'EOF'
{
  "dev.containers.dockerPath": "/shared/amdgpu/home/fai_qle/bin/docker",
  "docker.dockerPath": "/shared/amdgpu/home/fai_qle/bin/docker"
}
EOF
```

---

## 6. Connect from local VS Code

1. Install **Remote - SSH** and **Dev Containers** extensions.
2. **Remote-SSH: Connect to Host...** → your node (e.g. `mi355-gpu-40`).
3. **Dev Containers: Attach to Running Container...** → `vllm-dev`.
4. Remote user: **`root`** — workspace opens at **`/root`** (put your own files there).

`.devcontainer/devcontainer.json` in this folder sets `workspaceFolder` to `/root`.

---

## 7. Extras (automated setup only — next container create)

`setup_on_node.sh` also installs inside the container:

| Tool | Command | Notes |
|------|---------|--------|
| Oh My Bash | — | `root` shell |
| Cursor Agent | `agent` | `~/.local/bin` |
| Claude Code | `claude` | run once to log in |
| OpenAI Codex | `codex` | `/usr/local/bin`; run once to log in |
| tmux | `tmux` | apt package |

Script: `install_container_tools.sh` (tmux, Claude + Codex).

---

## Scripts in this folder

| Script | Purpose |
|--------|---------|
| `start_allocation.sh` | `salloc` + `setup_on_node.sh` + update `connection_info.txt` |
| `setup_on_node.sh` | Container + shim + extras (needs existing allocation) |
| `rocm_stack.env` | Pinned ROCm 7.2.3 + vLLM image tag (single source of truth) |
| `load_rocm_env.sh` | `module load rocm/7.2.3` + amdgpu/KFD checks |
| `install_container_tools.sh` | tmux + Claude Code + Codex |

## Teardown

```bash
scancel <JOBID>
podman rm -f vllm-dev   # on the compute node, if needed
```
