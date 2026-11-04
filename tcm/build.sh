#!/usr/bin/env bash
set -euo pipefail

# Build only the changed PE DLLs; all other files come from Valve's matching depot.
base=$(realpath "${1:?Usage: build.sh VALVE_PROTON_DIRECTORY OUTPUT_DIRECTORY}")
output=$(realpath -m "${2:?Missing output directory}")
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
[[ -f "$base/proton" && -f "$base/version" && ! -e "$output" ]]
read -r proton_short wine_short < <(python3 "$root/tcm/metadata.py" revisions "$base/version")
proton_sha=$(gh api "repos/ValveSoftware/Proton/commits/$proton_short" --jq .sha)
wine_sha=$(gh api "repos/ValveSoftware/wine/commits/$wine_short" --jq .sha)
# Valve builds components independently; the embedded Wine revision is authoritative.
mkdir -p "$output/wine" "$output/obj" "$output/release"
gh api "repos/ValveSoftware/Proton/contents/Makefile.in?ref=$proton_sha" --jq .content | base64 -d > "$output/Proton-Makefile.in"
sdk=$(sed -n 's/^[[:space:]]*STEAMRT_IMAGE ?= \(.*\/x86_64:.*\)$/\1/p' "$output/Proton-Makefile.in")
[[ "$sdk" == registry.gitlab.steamos.cloud/proton/* && "$sdk" != *$'\n'* ]]
curl -fL --retry 3 "https://codeload.github.com/ValveSoftware/wine/tar.gz/$wine_sha" | tar -xz --strip-components=1 -C "$output/wine"
git -C "$output/wine" apply --check "$root/tcm/patches/0001-motorfest-ack.patch"
git -C "$output/wine" apply "$root/tcm/patches/0001-motorfest-ack.patch"
cp "$root/tcm/patches/0001-motorfest-ack.patch" "$output/"
docker pull "$sdk"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e CCACHE_DISABLE=1 -v "$output:/work" -w /work/wine "$sdk" bash -euc '
    tools/make_requests
    tools/make_specfiles
    dlls/winevulkan/make_vulkan
    autoreconf -fi
    cd /work/obj
    /work/wine/configure --enable-win64 --enable-archs=i386,x86_64 --with-mingw=gcc --disable-tests --without-x
    make -j"$(nproc)" dlls/ws2_32/i386-windows/ws2_32.dll dlls/ws2_32/x86_64-windows/ws2_32.dll
    for arch in i386 x86_64; do
        "${arch/i386/i686}-w64-mingw32-strip" "dlls/ws2_32/$arch-windows/ws2_32.dll"
    done
'
stage="$output/Proton-Experimental-TCM"
cp -a "$base" "$stage"
rm -rf -- "$stage/steamapps"
for arch in i386 x86_64; do
    dll="$output/obj/dlls/ws2_32/$arch-windows/ws2_32.dll"
    test -s "$dll"
    strings "$dll" | grep -F 'HACK: control record after a query, holding its ack.' >/dev/null
    target=$(find "$stage/files" -path "*/$arch-windows/ws2_32.dll")
    [[ -n "$target" && "$target" != *$'\n'* ]] || { echo "Missing or ambiguous $arch DLL" >&2; exit 1; }
    cp "$dll" "$target"
done
printf '%s-tcm\n' "$(cat "$base/version")" > "$stage/version"
cat > "$stage/compatibilitytool.vdf" <<'VDF'
"compatibilitytools"
{
  "compat_tools"
  {
    "proton_experimental_tcm"
    {
      "install_path" "."
      "display_name" "Proton Experimental TCM"
      "from_oslist" "windows"
      "to_oslist" "linux"
    }
  }
}
VDF
printf 'Valve Proton: %s\nValve Wine: %s\nTCM patch: %s\nSDK: %s\nSDK digest: %s\nBase version: %s\n' \
    "$proton_sha" "$wine_sha" 9e4b92d214581348e5f6e27e1679e8dbaddb6d53 "$sdk" \
    "$(docker image inspect "$sdk" --format '{{index .RepoDigests 0}}')" "$(cat "$base/version")" > "$stage/TCM-BUILD.txt"
cp "$root/tcm/install.sh" "$stage/install-tcm.sh"
cp "$root/tcm/metadata.py" "$stage/tcm-metadata.py"
cp "$base/steamapps/appmanifest_1493710.acf" "$stage/TCM-STEAM-MANIFEST.acf"
cp "$root/tcm/README.md" "$stage/README-TCM.md"
cp "$stage/TCM-BUILD.txt" "$output/release/"
tar -I 'zstd -T0 -6' -cf "$output/release/Proton-Experimental-TCM.tar.zst" -C "$output" Proton-Experimental-TCM
# Ship the matching patched LGPL Wine source with every binary release.
tar -I 'zstd -T0 -6' -cf "$output/release/wine-tcm-source.tar.zst" -C "$output" wine 0001-motorfest-ack.patch Proton-Makefile.in
(cd "$output/release" && sha256sum ./*.tar.zst > SHA256SUMS)
