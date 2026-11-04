#!/usr/bin/env bash
set -euo pipefail

source_dir=$(realpath "${1:-$(dirname -- "$0")}")
tools_dir=$(realpath -m "${2:-$HOME/.steam/root/compatibilitytools.d}")
target="$tools_dir/Proton-Experimental-TCM-fix"
[[ "$source_dir" != "$target" && -f "$source_dir/TCM-BUILD.txt" && -x "$source_dir/proton" ]]
for file in version toolmanifest.vdf compatibilitytool.vdf files/lib/wine/i386-windows/ws2_32.dll files/lib/wine/x86_64-windows/ws2_32.dll; do
    [[ -s "$source_dir/$file" ]] || { echo "Incomplete package: $file" >&2; exit 1; }
done
if pgrep -u "$(id -u)" -x steam >/dev/null || fuser "$target/files/bin/wine" "$target/files/bin/wineserver" 2>/dev/null; then
    echo 'Close Steam and games using Proton Experimental TCM fix before installing.' >&2
    exit 1
fi
[[ ! -e "$target" || ( -d "$target" && -f "$target/TCM-BUILD.txt" ) ]]
mkdir -p "$tools_dir"
staging=$(mktemp -d "$tools_dir/.proton-tcm-XXXXXX")
backup=""
cleanup() {
    if [[ -n "$backup" && -d "$backup" && ! -e "$target" ]]; then mv -- "$backup" "$target"; fi
    rm -rf -- "$staging"
}
trap cleanup EXIT
cp -a "$source_dir/." "$staging/"
if [[ -f "$target/user_settings.py" ]]; then cp -a "$target/user_settings.py" "$staging/"; fi
if [[ -e "$target" ]]; then
    backup="$(dirname "$tools_dir")/proton-tcm-backups/Proton-Experimental-TCM-fix-$(date +%Y%m%d-%H%M%S)"
    [[ ! -e "$backup" ]]
    mkdir -p "$(dirname "$backup")"
    mv -- "$target" "$backup"
fi
mv -- "$staging" "$target"
printf 'Installed: %s\n' "$target"
if [[ -n "$backup" ]]; then printf 'Previous custom build: %s\n' "$backup"; fi
printf 'Restart Steam and select "Proton Experimental TCM fix" in the game compatibility settings.\n'
