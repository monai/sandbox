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
latest_rex=$(curl -fsSL https://blob.superlogical.com/api/releases/rex/preview)
latest_rex_commit=$(jq -er '.commit | select(type == "string") | select(test("^[0-9a-f]{40}$"))' <<< "$latest_rex")
latest_rex_sha256=$(jq -er '
    [.artifacts[] | select(.filename == "rex-linux-arm64.tar.gz")]
    | select(length == 1)
    | .[0].sha256
    | select(type == "string")
    | select(test("^[0-9a-f]{64}$"))
' <<< "$latest_rex")

for value in "$latest_uv" "$latest_claude" "$latest_codex" "$latest_pi" "$latest_rex_commit" "$latest_rex_sha256"; do
    if [[ -z "$value" ]]; then
        echo "Failed to determine a latest dependency version" >&2
        exit 1
    fi
done

changed=()

update_arg() {
    local arg=$1
    local label=$2
    local new_version=$3
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

    local tmp
    tmp=$(mktemp)
    sed "s/^ARG ${arg}=.*/ARG ${arg}=${new_version}/" "$dockerfile" > "$tmp"
    cp "$tmp" "$dockerfile"
    rm -f "$tmp"
    changed+=("${label}:${current_version}:${new_version}")
    echo "${arg}: ${current_version} -> ${new_version}"
}

update_arg UV_VERSION "uv" "$latest_uv"
update_arg CLAUDE_CODE_VERSION "Claude Code" "$latest_claude"
update_arg CODEX_VERSION "Codex" "$latest_codex"
update_arg PI_CODING_AGENT_VERSION "pi-coding-agent" "$latest_pi"
update_arg REX_COMMIT "Rex" "$latest_rex_commit"
update_arg REX_SHA256 "Rex checksum" "$latest_rex_sha256"

if (( ${#changed[@]} == 0 )); then
    echo "No dependency updates needed."
    exit 0
fi

names=()
for entry in "${changed[@]}"; do
    names+=("${entry%%:*}")
done

git -C "$repo_root" add Dockerfile
git -C "$repo_root" commit -m "Bump dependencies" -m "$(printf '%s\n' "${names[@]}")"
