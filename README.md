# sandbox

Debian `trixie-slim` coding-agent container.

## Build

Images: `base` (core tools, root, no agents) → `slim` (agent user, agents, tmux, vim) → `full` (chromium, compilers, debug tools).

```sh
docker buildx bake            # all
docker buildx bake slim   # one
```

## Run

```sh
docker run --rm -it -v "$PWD:/workspace" sandbox:slim
```

```sh
docker run --rm -it -e TERM_PROGRAM=$TERM_PROGRAM -v agent-home:/home/agent -v "$PWD:/workspace" sandbox:slim
```

## Rex over SSH

Mount an existing file readable by `agent` with one SSH public key per line.
Each key grants access to `agent`, which has passwordless sudo.

```sh
docker run --rm -it -p 127.0.0.1:2222:22 \
  -v "$HOME/.ssh/id_ed25519.pub:/run/sandbox/authorized_keys:ro" sandbox:slim
# In another terminal
rex -S ssh://agent@127.0.0.1:2222 ls
```

For a VM, use its address and SSH port (default 22). Preserve
`/etc/ssh/ssh_host_ed25519_key` to keep the same host identity across launches.
