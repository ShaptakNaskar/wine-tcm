#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
target="$test_dir/steamapps/common/Proton - Experimental"
mkdir -p "$test_dir/package" "$target" "$test_dir/bin"
for command in pgrep fuser; do
    printf '#!/bin/sh\nexit 1\n' > "$test_dir/bin/$command"
    chmod +x "$test_dir/bin/$command"
done
export PATH="$test_dir/bin:$PATH"
printf '#!/bin/sh\nexit 0\n' > "$test_dir/package/proton"
chmod +x "$test_dir/package/proton"
cp "$test_dir/package/proton" "$target/proton"
echo original > "$target/version"
echo custom-settings > "$target/user_settings.py"
echo patched > "$test_dir/package/version"
echo source-revisions > "$test_dir/package/TCM-BUILD.txt"
echo custom-tool > "$test_dir/package/compatibilitytool.vdf"
echo manifest > "$test_dir/package/toolmanifest.vdf"
for arch in i386 x86_64; do
    mkdir -p "$test_dir/package/files/lib/wine/$arch-windows"
    echo DLL > "$test_dir/package/files/lib/wine/$arch-windows/ws2_32.dll"
done
cp "$root/tcm/metadata.py" "$test_dir/package/tcm-metadata.py"
python3 - "$test_dir" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
common = '"LastUpdated" "123" "SizeOnDisk" "456" "InstalledDepots" {} "StateFlags" "4" "StagingSize" "0" "UpdateResult" "0" "UserConfig" {} "MountedConfig" {}'
(root / 'steamapps/appmanifest_1493710.acf').write_text('"AppState" { "appid" "1493710" "buildid" "1" "LastOwner" "7656119" ' + common + '}')
(root / 'package/TCM-STEAM-MANIFEST.acf').write_text('"AppState" { "appid" "1493710" "buildid" "2" ' + common + '}')
PY
bash "$root/tcm/install.sh" "$test_dir/package" "$target"
[[ $(cat "$target/version") == patched ]]
[[ $(cat "$target/user_settings.py") == custom-settings ]]
[[ ! -e "$target/compatibilitytool.vdf" ]]
backups=("$target.backup-"*/)
[[ ${#backups[@]} == 1 && $(cat "${backups[0]}/version") == original ]]
python3 - "$test_dir/steamapps/appmanifest_1493710.acf" "$root/tcm" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from metadata import read_vdf
from pathlib import Path
state = read_vdf(Path(sys.argv[1]).read_text())["AppState"]
assert state["buildid"] == "2" and state["LastOwner"] == "7656119"
PY
rm "$test_dir/package/TCM-BUILD.txt"
if bash "$root/tcm/install.sh" "$test_dir/package" "$target"; then
    echo 'Installer accepted an invalid package' >&2
    exit 1
fi
[[ $(cat "$target/version") == patched ]]
echo 'Installer checks passed.'
