# Proton Experimental TCM fix

Current Valve Proton Experimental with PhialsBasement's [Motorfest workaround](https://github.com/PhialsBasement/wine-tcm/commit/9e4b92d214581348e5f6e27e1679e8dbaddb6d53) for [Proton issue 9119](https://github.com/ValveSoftware/Proton/issues/9119).
The patch only activates for Steam game ID `2698940`. It changes the timing of a UDP acknowledgement on port 4000 to work around the game's dropped report fragments on high latency connections. It does not disable BattlEye.

## Releases and updates

[Download the latest release](https://github.com/ShaptakNaskar/wine-tcm/releases/latest). Check `SHA256SUMS` before extracting:

```sh
sha256sum -c SHA256SUMS
tar --zstd -xf Proton-Experimental-TCM-fix.tar.zst
```

The GitHub Actions workflow checks Steam's actual Proton Experimental build ID every 15 minutes and publishes a release when it changes. It also builds on automation/patch changes and supports manual runs. It currently tracks the `bleeding-edge` Steam beta, matching the original workaround and this machine's channel. Set repository variable `PROTON_CHANNEL` to `public` to track regular Experimental instead. Each tag includes the channel, Steam build ID and automation revision.

GitHub may delay scheduled jobs, and disables schedules in inactive public repositories after 60 days. Re-enable the workflow from Actions if that happens. Upstream patch conflicts or an unrecognized version fail the build without publishing a partial release. Scheduled runs retry on the next interval. A release is published only after the complete upload succeeds.

## Install the separate Steam compatibility tool

Close Steam and games using the custom tool, then:

```sh
bash Proton-Experimental-TCM-fix/install-tcm.sh Proton-Experimental-TCM-fix
```

The installer creates `~/.steam/root/compatibilitytools.d/Proton-Experimental-TCM-fix`. Restart Steam, open the game's **Properties > Compatibility**, and choose **Proton Experimental TCM fix**. Valve's regular Proton Experimental installation remains separate, and its Steam updates cannot overwrite this custom tool. Pass another Steam client's `compatibilitytools.d` directory as a second argument if needed.

To update the custom tool, download a new release and rerun the installer. It preserves `user_settings.py` and moves the previous custom build to `~/.steam/root/proton-tcm-backups/`, outside Steam's tool discovery directory. To roll back, close Steam, move the current custom directory aside, and move a backup into its place. To uninstall, remove its directory from `compatibilitytools.d` and select another compatibility tool for the game.

The installer leaves Steam's official app manifests and game prefixes alone.

## Automatic local updates

ProtonPlus 0.6.8 uses a built-in provider catalog rather than accepting arbitrary repository URLs. This repository includes a user-level updater for the separate TCM tool. From a checkout of this repository:

```sh
mkdir -p ~/.local/lib/proton-tcm ~/.config/systemd/user
cp tcm/update.sh tcm/install.sh ~/.local/lib/proton-tcm/
cp tcm/proton-tcm-update.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now proton-tcm-update.timer
systemctl --user start proton-tcm-update.service
```

The timer checks the latest published release daily and catches up after login. It downloads only a new release tag, verifies its SHA-256 checksum, and reuses the installer. If Steam or this tool is running, it defers the update until a later check; it never closes Steam or interrupts a game. The Steam entry remains **Proton Experimental TCM fix**.

One automatically created previous build is retained in `~/.steam/root/proton-tcm-backups/`; older automatic backups are removed to prevent disk growth. Existing manual backups are retained. Check activity with `journalctl --user -u proton-tcm-update.service` and the next check with `systemctl --user list-timers proton-tcm-update.timer`. Disable automatic checks with `systemctl --user disable --now proton-tcm-update.timer`.

The updater requires curl, Python 3, GNU tar, zstd, util-linux (`flock`), psmisc (`fuser`), and systemd user services. It uses public GitHub endpoints and needs no token. Updating these local helper scripts themselves requires copying them again from the repository.

## How the build works

1. Download Valve's unmodified Linux x86_64 Proton Experimental depot anonymously using SteamCMD.
2. Resolve the exact Proton and Wine revisions embedded in its `version` file. If GitHub cannot resolve an abbreviated hash, search the latest 100 bleeding-edge commits for a unique full hash; missing or ambiguous matches fail the build. Valve builds the components independently, so the embedded Wine revision takes precedence over the main source commit's submodule pointer.
3. Apply the original, pinned patch. Build only the 32-bit and 64-bit `ws2_32.dll` with the SDK named by that exact Proton revision. The Unix networking library and all other components remain Valve's binaries.
4. Check both DLLs for the workaround, package the complete tool, and publish SHA-256 checksums, build provenance and matching patched Wine sources. Existing files from other Proton versions are never used to make a release.

This avoids a full Proton rebuild. It supports x86_64 Linux, including 32-bit Windows games. It deliberately fails if Valve changes its version format, source layout or SDK naming; update the scripts then. Build success does not establish that Motorfest's online session works on every machine.

To build locally (requires Docker, authenticated `gh`, Python 3, Git, curl, tar and zstd):

```sh
python3 -m unittest discover -s tcm/tests
# VALVE_PROTON must be an unmodified, fully downloaded Valve build.
bash tcm/build.sh "$VALVE_PROTON" /absolute/path/to/new-build-directory
```

`TCM-BUILD.txt` records the exact source revisions, SDK image/digest and Valve version. Each release includes the patched Wine source and original patch under their original licenses. Valve's other component sources are available from the Proton repository; the version string also identifies the separately built DXVK and vkd3d-proton revisions. Wine's original README remains at the repository root; this fork's automation lives in `tcm/` and `.github/workflows/`.
