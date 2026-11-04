# Proton Experimental TCM

Current Valve Proton Experimental with PhialsBasement's [Motorfest workaround](https://github.com/PhialsBasement/wine-tcm/commit/9e4b92d214581348e5f6e27e1679e8dbaddb6d53) for [Proton issue 9119](https://github.com/ValveSoftware/Proton/issues/9119).
The patch only activates for Steam game ID `2698940`. It changes the timing of a UDP acknowledgement on port 4000 to work around the game's dropped report fragments on high latency connections. It does not disable BattlEye.

## Releases and updates

[Download the latest release](https://github.com/ShaptakNaskar/wine-tcm/releases/latest). Check `SHA256SUMS` before extracting:

```sh
sha256sum -c SHA256SUMS
tar --zstd -xf Proton-Experimental-TCM.tar.zst
```

The GitHub Actions workflow checks Steam's actual Proton Experimental build ID every 15 minutes and publishes a release when it changes. It also builds on automation/patch changes and supports manual runs. It currently tracks the `bleeding-edge` Steam beta, matching the original workaround and this machine's channel. Set repository variable `PROTON_CHANNEL` to `public` to track regular Experimental instead. Each tag includes the channel, Steam build ID and automation revision.

GitHub may delay scheduled jobs, and disables schedules in inactive public repositories after 60 days. Re-enable the workflow from Actions if that happens. Upstream patch conflicts or an unrecognized version fail the build without publishing a partial release. Scheduled runs retry on the next interval. A release is published only after the complete upload succeeds.

## Replace Steam's Proton Experimental

Close Steam and games using Experimental, then:

```sh
bash Proton-Experimental-TCM/install-tcm.sh Proton-Experimental-TCM
```

The installer replaces `~/.steam/root/steamapps/common/Proton - Experimental` and preserves `user_settings.py`. Pass your installation directory as a second argument for another Steam library. It updates Steam's manifest to the downloaded Valve base while retaining your account and update preferences, and keeps timestamped backups of both the directory and manifest. Steam's **Proton Experimental** selection stays in place. It does not change any game prefixes or saves. With Steam closed, move the patched directory aside, rename the backup to `Proton - Experimental`, and copy the accompanying `.acf` backup over `steamapps/appmanifest_1493710.acf` to roll back.

Steam updates and file verification can overwrite the patch. Download and install a new release afterward. CI publishes releases; it does not automatically modify your PC.

For a separate selectable tool instead, extract the directory into `~/.steam/root/compatibilitytools.d/`, restart Steam and choose **Proton Experimental TCM** for Motorfest.

## How the build works

1. Download Valve's unmodified Linux x86_64 Proton Experimental depot anonymously using SteamCMD.
2. Resolve the exact Proton and Wine revisions embedded in its `version` file. Valve builds the components independently, so the embedded Wine revision takes precedence over the main source commit's submodule pointer.
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
