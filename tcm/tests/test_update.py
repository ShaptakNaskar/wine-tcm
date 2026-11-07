import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "update.sh"
ASSET = "Proton-Experimental-TCM-fix.tar.zst"
TAG = "tcm-bleeding-edge-12345678-abcdef01"


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.tools = self.directory / "steam/compatibilitytools.d"
        self.target = self.tools / "Proton-Experimental-TCM-fix"
        self.package = self.directory / "package/Proton-Experimental-TCM-fix"
        self.package.mkdir(parents=True)
        for name, content in {"proton": "#!/bin/sh\nexit 0\n", "version": "new", "TCM-BUILD.txt": "build revisions", "compatibilitytool.vdf": "custom tool", "toolmanifest.vdf": "runtime"}.items():
            (self.package / name).write_text(content)
        (self.package / "proton").chmod(0o755)
        for arch in ("i386", "x86_64"):
            dll = self.package / f"files/lib/wine/{arch}-windows/ws2_32.dll"
            dll.parent.mkdir(parents=True)
            dll.write_bytes(b"DLL")
        shutil.copytree(self.package, self.target)
        (self.target / "version").write_text("old")
        (self.target / "user_settings.py").write_text("custom settings")
        (self.target / ".tcm-release").write_text("old-release")
        subprocess.run(["tar", "--zstd", "-cf", str(self.directory / ASSET), "-C", str(self.package.parent), self.package.name], check=True)
        digest = hashlib.sha256((self.directory / ASSET).read_bytes()).hexdigest()
        (self.directory / "SHA256SUMS").write_text(f"{digest}  ./{ASSET}\n")
        binaries = self.directory / "bin"
        binaries.mkdir()
        (binaries / "curl").write_text('''#!/usr/bin/env python3
import json,os,shutil,sys
from pathlib import Path
root = Path(os.environ["TEST_DIRECTORY"])
with (root / "requests").open("a") as log:
    log.write(" ".join(sys.argv[1:]) + "\\n")
if "-o" in sys.argv:
    destination = Path(sys.argv[sys.argv.index("-o") + 1])
    shutil.copyfile(root / destination.name, destination)
else:
    print(json.dumps({"tag_name": os.environ["TEST_TAG"]}))
''')
        (binaries / "pgrep").write_text('#!/bin/sh\nexit "${TEST_BUSY:-1}"\n')
        (binaries / "fuser").write_text("#!/bin/sh\nexit 1\n")
        for binary in binaries.iterdir():
            binary.chmod(0o755)
        self.environment = {**os.environ, "PATH": str(binaries) + os.pathsep + os.environ["PATH"], "XDG_CACHE_HOME": str(self.directory / "cache"), "TEST_DIRECTORY": str(self.directory), "TEST_TAG": TAG}

    def update(self):
        return subprocess.run(["bash", str(SCRIPT), str(self.tools)], env=self.environment, text=True, capture_output=True)

    def test_update_skip_repeat_and_keep_only_latest_automatic_backup(self):
        backup_root = self.tools.parent / "proton-tcm-backups"
        for stamp, automatic in (("20000101-000000", True), ("20000102-000000", True), ("19990101-000000", False)):
            backup = backup_root / f"Proton-Experimental-TCM-fix-{stamp}"
            backup.mkdir(parents=True)
            (backup / "TCM-BUILD.txt").write_text("older build")
            if automatic:
                (backup / ".tcm-auto-backup").touch()
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / "version").read_text(), "new")
        self.assertEqual((self.target / ".tcm-release").read_text().strip(), TAG)
        self.assertEqual((self.target / "user_settings.py").read_text(), "custom settings")
        self.assertEqual(len(list(backup_root.glob("*/.tcm-auto-backup"))), 1)
        self.assertTrue((backup_root / "Proton-Experimental-TCM-fix-19990101-000000").exists())
        downloads = (self.directory / "requests").read_text().count(" -o ")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Already up to date", result.stdout)
        self.assertEqual((self.directory / "requests").read_text().count(" -o "), downloads)

    def test_bad_checksum_keeps_existing_installation(self):
        (self.directory / "SHA256SUMS").write_text("0" * 64 + f"  ./{ASSET}\n")
        result = self.update()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / "version").read_text(), "old")
        self.assertEqual((self.target / ".tcm-release").read_text(), "old-release")

    def test_busy_steam_defers_without_downloading(self):
        self.environment["TEST_BUSY"] = "0"
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("retrying", result.stdout)
        self.assertFalse((self.directory / "requests").exists())
        self.assertEqual((self.target / "version").read_text(), "old")

    def test_checksum_for_another_file_does_not_authorize_installation(self):
        (self.directory / "SHA256SUMS").write_text("0" * 64 + "  /unrelated-file\n")
        result = self.update()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / "version").read_text(), "old")

    def test_invalid_tag_is_rejected(self):
        self.environment["TEST_TAG"] = "../../invalid"
        result = self.update()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid release tag", result.stderr)
        self.assertNotIn(" -o ", (self.directory / "requests").read_text())
