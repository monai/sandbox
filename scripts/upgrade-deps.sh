#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
dockerfile="$repo_root/Dockerfile"

if [[ ! -f "$dockerfile" ]]; then
    echo "Dockerfile not found: $dockerfile" >&2
    exit 1
fi

latest_uv=$(curl -fsSL https://api.github.com/repos/astral-sh/uv/releases/latest | jq -r '.tag_name')
latest_claude=$(npm view @anthropic-ai/claude-code version)
latest_codex=$(npm view @openai/codex version)
latest_pi=$(npm view @earendil-works/pi-coding-agent version)

for value in "$latest_uv" "$latest_claude" "$latest_codex" "$latest_pi"; do
    if [[ -z "$value" ]]; then
        echo "Failed to determine a latest dependency version" >&2
        exit 1
    fi
done

declare -A labels=(
    [UV_VERSION]="uv"
    [CLAUDE_CODE_VERSION]="Claude Code"
    [CODEX_VERSION]="Codex"
    [PI_CODING_AGENT_VERSION]="pi-coding-agent"
)
changed=()

update_arg() {
    local arg=$1
    local new_version=$2
    local current_version

    current_version=$(grep -E "^ARG ${arg}=" "$dockerfile" | head -n1 | cut -d= -f2-)

    if [[ -z "$current_version" ]]; then
        echo "Could not find ARG ${arg} in $dockerfile" >&2
        exit 1
    fi

    if [[ "$current_version" == "$new_version" ]]; then
        echo "${arg}: already at ${current_version}"
        return
    fi

    sed -i "s/^ARG ${arg}=.*/ARG ${arg}=${new_version}/" "$dockerfile"
    changed+=("${arg}:${current_version}:${new_version}")
    echo "${arg}: ${current_version} -> ${new_version}"
}

update_arg UV_VERSION "$latest_uv"
update_arg CLAUDE_CODE_VERSION "$latest_claude"
update_arg CODEX_VERSION "$latest_codex"
update_arg PI_CODING_AGENT_VERSION "$latest_pi"

if (( ${#changed[@]} == 0 )); then
    echo "No dependency updates needed."
    exit 0
fi

names=()
for entry in "${changed[@]}"; do
    arg=${entry%%:*}
    names+=("${labels[$arg]}")
done

git -C "$repo_root" add Dockerfile
git -C "$repo_root" commit -m "Bump dependencies" -m "$(printf '%s\n' "${names[@]}")"
