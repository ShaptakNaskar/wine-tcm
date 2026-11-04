#!/usr/bin/env bash
set -euo pipefail

source_dir=$(realpath "${1:-$(dirname -- "$0")}")
target=$(realpath -m "${2:-$HOME/.steam/root/steamapps/common/Proton - Experimental}")
[[ "$source_dir" != "$target" && -f "$source_dir/TCM-BUILD.txt" && -x "$source_dir/proton" ]]
[[ -f "$target/version" && -x "$target/proton" && "$(basename "$target")" == 'Proton - Experimental' ]]
for file in version toolmanifest.vdf files/lib/wine/i386-windows/ws2_32.dll files/lib/wine/x86_64-windows/ws2_32.dll TCM-STEAM-MANIFEST.acf tcm-metadata.py; do
    [[ -s "$source_dir/$file" ]] || { echo "Incomplete package: $file" >&2; exit 1; }
done
manifest="$(dirname "$(dirname "$target")")/appmanifest_1493710.acf"
[[ -f "$manifest" ]]
if pgrep -u "$(id -u)" -x steam >/dev/null || fuser "$target/files/bin/wine" "$target/files/bin/wineserver" 2>/dev/null; then
    echo 'Close Steam and games using Proton Experimental before installing.' >&2
    exit 1
fi
backup="$target.backup-$(date +%Y%m%d-%H%M%S)"
[[ ! -e "$backup" ]]
staging=$(mktemp -d "$(dirname "$target")/.proton-tcm-XXXXXX")
manifest_staging=$(mktemp "$manifest.tcm-XXXXXX")
manifest_backup="$backup.acf"
committed=false
cleanup() {
    if [[ "$committed" == false && -d "$backup" ]]; then
        if [[ -e "$target" ]]; then mv -- "$target" "$staging"; fi
        mv -- "$backup" "$target"
        cp -a -- "$manifest_backup" "$manifest"
    fi
    rm -rf -- "$staging"
    rm -f -- "$manifest_staging"
}
trap cleanup EXIT
cp -a "$source_dir/." "$staging/"
if [[ -f "$target/user_settings.py" ]]; then
    cp -a "$target/user_settings.py" "$staging/"
fi
# A Steam-managed installation keeps its existing Experimental entry.
rm -f -- "$staging/compatibilitytool.vdf"
python3 "$source_dir/tcm-metadata.py" sync-manifest "$manifest" "$source_dir/TCM-STEAM-MANIFEST.acf" > "$manifest_staging"
cp -a -- "$manifest" "$manifest_backup"
mv -- "$target" "$backup"
mv -- "$staging" "$target"
mv -- "$manifest_staging" "$manifest"
committed=true
printf 'Installed: %s\nBackup: %s\nSteam manifest backup: %s\n' "$target" "$backup" "$manifest_backup"
printf 'Rollback with Steam closed: move the installed directory aside, rename the backup to the original path, and restore the manifest backup.\n'
printf 'Steam updates or Verify files can replace this patch; rerun this installer after updating.\n'
