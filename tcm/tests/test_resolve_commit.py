import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "resolve-commit.sh"
SHA = "de7c9d26fe9cd5c975a25bf5ffa3955174c3b8e6"


class ResolveCommitTests(unittest.TestCase):
    def resolve(self, direct, history):
        with tempfile.TemporaryDirectory() as directory:
            gh = Path(directory) / "gh"
            gh.write_text('''#!/bin/bash
if [[ "$2" == *"?sha=bleeding-edge&per_page=100" ]]; then
    printf '%s' "$TEST_HISTORY"
elif [[ -n "$TEST_DIRECT" ]]; then
    printf '%s' "$TEST_DIRECT"
else
    exit 1
fi
''')
            gh.chmod(0o755)
            return subprocess.run(
                ["bash", str(SCRIPT), "ValveSoftware/Proton", "de7c9d"],
                env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"],
                     "TEST_DIRECT": direct, "TEST_HISTORY": history},
                text=True, capture_output=True,
            )

    def test_direct_lookup(self):
        result = self.resolve(SHA, "")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), SHA)

    def test_unresolved_abbreviation_uses_full_commit_from_history(self):
        result = self.resolve("", SHA)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), SHA)

    def test_missing_ambiguous_and_wrong_revisions_are_rejected(self):
        for history in ("", SHA + "\n" + "de7c9d" + "0" * 34, "0" * 40):
            with self.subTest(history=history):
                result = self.resolve("", history)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Cannot uniquely resolve", result.stderr)
