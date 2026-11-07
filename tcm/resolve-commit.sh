#!/usr/bin/env bash
set -euo pipefail

repository=${1:?Missing repository}
revision=${2:?Missing revision}
[[ "$revision" =~ ^[0-9a-f]{6,40}$ ]]
if ! sha=$(gh api "repos/$repository/commits/$revision" --jq .sha 2>/dev/null); then
    # shortcut: search the latest 100 bleeding-edge commits; expand for older ambiguous revisions.
    sha=$(gh api "repos/$repository/commits?sha=bleeding-edge&per_page=100" \
        --jq ".[] | select(.sha | startswith(\"$revision\")) | .sha")
fi
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ || "$sha" != "$revision"* ]]; then
    printf 'Cannot uniquely resolve %s revision %s\n' "$repository" "$revision" >&2
    exit 1
fi
printf '%s\n' "$sha"
