#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
tools_dir="$test_dir/compatibilitytools.d"
target="$tools_dir/Proton-Experimental-TCM-fix"
official="$test_dir/steamapps/common/Proton - Experimental"
mkdir -p "$test_dir/package" "$official" "$test_dir/bin"
for command in pgrep fuser; do
    printf '#!/bin/sh\nexit 1\n' > "$test_dir/bin/$command"
    chmod +x "$test_dir/bin/$command"
done
export PATH="$test_dir/bin:$PATH"
printf '#!/bin/sh\nexit 0\n' > "$test_dir/package/proton"
chmod +x "$test_dir/package/proton"
echo original > "$official/version"
echo official-manifest > "$test_dir/steamapps/appmanifest_1493710.acf"
echo patched > "$test_dir/package/version"
echo source-revisions > "$test_dir/package/TCM-BUILD.txt"
echo custom-tool > "$test_dir/package/compatibilitytool.vdf"
echo manifest > "$test_dir/package/toolmanifest.vdf"
for arch in i386 x86_64; do
    mkdir -p "$test_dir/package/files/lib/wine/$arch-windows"
    echo DLL > "$test_dir/package/files/lib/wine/$arch-windows/ws2_32.dll"
done
bash "$root/tcm/install.sh" "$test_dir/package" "$tools_dir"
[[ $(cat "$target/version") == patched ]]
[[ $(cat "$target/compatibilitytool.vdf") == custom-tool ]]
echo custom-settings > "$target/user_settings.py"
echo updated > "$test_dir/package/version"
bash "$root/tcm/install.sh" "$test_dir/package" "$tools_dir"
[[ $(cat "$target/version") == updated ]]
[[ $(cat "$target/user_settings.py") == custom-settings ]]
backups=("$test_dir/proton-tcm-backups/"*/)
[[ ${#backups[@]} == 1 && $(cat "${backups[0]}/version") == patched ]]
[[ $(cat "$official/version") == original ]]
[[ $(cat "$test_dir/steamapps/appmanifest_1493710.acf") == official-manifest ]]
rm "$test_dir/package/TCM-BUILD.txt"
if bash "$root/tcm/install.sh" "$test_dir/package" "$tools_dir"; then
    echo 'Installer accepted an invalid package' >&2
    exit 1
fi
[[ $(cat "$target/version") == updated ]]
echo 'Installer checks passed.'
