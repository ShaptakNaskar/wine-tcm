import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from metadata import build_id, revisions, read_vdf, write_vdf, sync_manifest


class MetadataTests(unittest.TestCase):
    def test_channels_and_log_noise(self):
        text = '''Steam login output
"1493710"
{
 "depots" { "branches" {
 "public" { "buildid" "123" "description" "Regular" }
 "bleeding-edge" { "buildid" "456" }
 } }
}
Steam quit output'''
        self.assertEqual(build_id(text, "public"), "123")
        self.assertEqual(build_id(text, "bleeding-edge"), "456")
        with self.assertRaises(KeyError):
            build_id(text, "missing")
        with self.assertRaises(ValueError):
            build_id("Login Failure", "public")

    def test_revisions(self):
        self.assertEqual(revisions("1793370357 experimental-bleeding-edge-11.0-460838-20261030-p5b1cb2-w674d3c-d21fda8-v4522cc-x86_64\n"), ("5b1cb2", "674d3c"))
        self.assertEqual(revisions("123 experimental-11.0-20261101-pabcdef-w012345-d987654-x86_64\n"), ("abcdef", "012345"))
        with self.assertRaises(ValueError):
            revisions("unknown version")

    def test_manifest_preserves_owner_and_preferences(self):
        original = {"AppState": {"appid": "1493710", "buildid": "1", "LastOwner": "7656119", "AutoUpdateBehavior": "0"}}
        latest = {"AppState": {"appid": "1493710", "buildid": "2", "LastOwner": "0", "LastUpdated": "123", "SizeOnDisk": "456", "InstalledDepots": {"1493711": {"manifest": "987"}}, "StateFlags": "4", "StagingSize": "0", "UpdateResult": "0", "UserConfig": {"BetaKey": "bleeding-edge"}, "MountedConfig": {"BetaKey": "bleeding-edge"}}}
        result = read_vdf(sync_manifest(write_vdf(original), write_vdf(latest)))["AppState"]
        self.assertEqual(result["buildid"], "2")
        self.assertEqual(result["InstalledDepots"], latest["AppState"]["InstalledDepots"])
        self.assertEqual(result["LastOwner"], "7656119")
        self.assertEqual(result["AutoUpdateBehavior"], "0")
        escaped = {"root": {"path": 'C:\\test\\"quoted"', "brace": "{"}}
        self.assertEqual(read_vdf(write_vdf(escaped)), escaped)


if __name__ == "__main__":
    unittest.main()
