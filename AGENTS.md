# Agent instructions — prepare_env

**Canonical reference:** [`example_setup.md`](./example_setup.md) — follow it for salloc, podman, docker shim, and VS Code attach. Scripts automate those steps.

## Session start

**Ask the user immediately:**

> Do you want to set up a MI355 GPU node and `vllm-dev` container now?

Do not run `salloc`, `podman`, or setup scripts until they answer.

| Answer | Action |
|--------|--------|
| **Yes** | Run `start_allocation.sh` or the workflow in `.cursor/rules/mi355-container-setup.mdc` |
| **No** | Continue with whatever they asked |

## User-specified image (one-off)

If the user explicitly provides an image (address, tag, or ID), use that image for this run only — pass `IMAGE=...` (and optional `CONTAINER_NAME`, `PORT_MAP`) when calling `setup_on_node.sh`. **Do not** update `rocm_stack.env` or other repo files.

After the container is created, **always report the container name** to the user.

## What “setup” means

1. `salloc` an exclusive MI355 node (1-week job `vllm-dev-setup`)
2. On that node: pull default `vllm/vllm-openai-rocm:nightly`, start `vllm-dev` with GPU devices (unless user overrode `IMAGE` / `CONTAINER_NAME` above)
3. Install oh-my-bash, Cursor Agent, **Claude Code** (`claude`), **Codex** (`codex`), **tmux** in the container; copy host `~/.ssh` into the container for private `git clone`
4. Configure podman-as-docker shim for VS Code Dev Containers
5. Write `connection_info.txt` with node name and job ID

## User connects from local VS Code

1. Remote-SSH → `mi355-gpu-XX` (see `connection_info.txt`)
2. Dev Containers → Attach to Running Container → `vllm-dev` → user `root` (workspace `/shared/amdgpu/home/fai_qle`)

## Scripts

- `start_allocation.sh` — allocate + setup (preferred)
- `setup_on_node.sh` — setup only (when job already exists)
- `example_setup.md` — **canonical** manual + automated workflow reference

## Teardown

```bash
scancel <JOBID>
```
