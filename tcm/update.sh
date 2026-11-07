#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(realpath -m "${1:-$HOME/.steam/root/compatibilitytools.d}")
target="$tools_dir/Proton-Experimental-TCM-fix"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/proton-tcm"
mkdir -p "$cache"
exec 9>"$cache/update.lock"
flock -n 9 || exit 0
if pgrep -u "$(id -u)" -x steam >/dev/null || fuser "$target/files/bin/wine" "$target/files/bin/wineserver" 2>/dev/null; then
    echo 'Steam or the custom tool is running; retrying at the next scheduled check.'
    exit 0
fi
tag=$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
    https://api.github.com/repos/ShaptakNaskar/wine-tcm/releases/latest \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
[[ "$tag" =~ ^tcm-[a-zA-Z0-9._-]+$ ]] || { echo 'Invalid release tag' >&2; exit 1; }
if [[ -f "$target/.tcm-release" && $(cat "$target/.tcm-release") == "$tag" ]]; then
    echo "Already up to date: $tag"
    exit 0
fi
work=$(mktemp -d "$cache/update-XXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 1' HUP INT TERM
for asset in Proton-Experimental-TCM-fix.tar.zst SHA256SUMS; do
    curl -fL --retry 3 --connect-timeout 15 --max-time 900 \
        "https://github.com/ShaptakNaskar/wine-tcm/releases/download/$tag/$asset" -o "$work/$asset"
done
(cd "$work" && sha256sum -c SHA256SUMS --ignore-missing)
tar --zstd --no-same-owner --no-same-permissions -xf "$work/Proton-Experimental-TCM-fix.tar.zst" -C "$work"
if [[ -d "$target" ]]; then touch "$target/.tcm-auto-backup"; fi
bash "$root/install.sh" "$work/Proton-Experimental-TCM-fix" "$tools_dir"
printf '%s\n' "$tag" > "$target/.tcm-release"
# Keep one automatically created rollback build; manual backups are retained.
shopt -s nullglob
backups=("$(dirname "$tools_dir")"/proton-tcm-backups/Proton-Experimental-TCM-fix-*/.tcm-auto-backup)
for ((i=0; i+1<${#backups[@]}; i++)); do
    previous=${backups[i]%/*}
    if [[ ! -L "$previous" && -f "$previous/TCM-BUILD.txt" ]]; then rm -rf -- "$previous"; fi
done
echo "Updated Proton Experimental TCM fix to $tag"
