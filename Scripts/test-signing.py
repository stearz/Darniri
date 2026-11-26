#!/usr/bin/env python3
"""Exercise signing policy with stubs; never access real identities or run the app."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SHA = "A" * 40
OTHER_SHA = "B" * 40
NAME = "Developer ID Application: Test Developer (ABCDE12345)"


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("DARNIRI_")}
        self.env.update(PATH=str(self.path) + os.pathsep + self.env["PATH"],
                        SIGN_TEST_LOG=str(self.path / "commands.jsonl"),
                        SIGN_TEST_IDENTITIES=f'  1) {SHA} "{NAME}"\n')
        for command in ["security", "codesign", "xcrun", "spctl", "ditto"]:
            stub = self.path / command
            stub.write_text("#!/usr/bin/env python3\n" + '''import json, os, pathlib, sys
with open(os.environ["SIGN_TEST_LOG"], "a") as log:
    log.write(json.dumps([pathlib.Path(sys.argv[0]).name] + sys.argv[1:]) + "\\n")
if pathlib.Path(sys.argv[0]).name == "security":
    print(os.environ.get("SIGN_TEST_IDENTITIES", ""))
if pathlib.Path(sys.argv[0]).name == "codesign" and "--verify" in sys.argv:
    sys.exit(int(os.environ.get("SIGN_TEST_VERIFY_EXIT", "0")))
''')
            stub.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run([str(ROOT / "Scripts" / name), *args], env=self.env,
                              text=True, capture_output=True, check=False)

    def commands(self, name):
        log = self.path / "commands.jsonl"
        if not log.exists():
            return []
        return [entry for line in log.read_text().splitlines()
                if (entry := json.loads(line))[0] == name]

    def test_missing_identity_fails_without_signing(self):
        self.env["SIGN_TEST_IDENTITIES"] = "0 valid identities found"
        result = self.run_script("sign-app.sh", "App.app")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No ad-hoc fallback", result.stderr)
        self.assertEqual(self.commands("codesign"), [])

    def test_ambiguous_identities_require_selection(self):
        self.env["SIGN_TEST_IDENTITIES"] += f'  2) {OTHER_SHA} "Developer ID Application: Other (OTHER12345)"\n'
        self.assertNotEqual(self.run_script("sign-app.sh", "--check").returncode, 0)
        self.env["DARNIRI_TEAM_ID"] = "ABCDE12345"
        self.assertEqual(self.run_script("sign-app.sh", "--check").returncode, 0)
        self.assertEqual(self.commands("codesign"), [])

    def test_signing_uses_stable_identifier_and_verifies_team(self):
        self.env["DARNIRI_TEAM_ID"] = "ABCDE12345"
        result = self.run_script("sign-app.sh", "App with spaces.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands("codesign")
        self.assertEqual(commands[0][commands[0].index("--sign") + 1], SHA)
        self.assertIn("io.github.stearz.darniri", commands[0])
        self.assertIn("runtime", commands[0])
        self.assertIn("--timestamp", commands[0])
        self.assertEqual(commands[0][-1], "App with spaces.app")
        self.assertTrue(commands[-1][-2].startswith("=identifier "))
        self.assertIn('certificate leaf[subject.OU] = "ABCDE12345"', commands[-1][-2])

    def test_other_signing_channel_is_rejected(self):
        self.env["SIGN_TEST_IDENTITIES"] = f'1) {SHA} "Apple Development: Test (ABCDE12345)"'
        self.assertNotEqual(self.run_script("sign-app.sh", "--check").returncode, 0)

    def test_verification_failure_is_fatal(self):
        self.env["SIGN_TEST_VERIFY_EXIT"] = "1"
        self.assertNotEqual(self.run_script("sign-app.sh", "App.app").returncode, 0)

    def test_adhoc_requires_explicit_opt_in(self):
        self.env["DARNIRI_SIGNING_MODE"] = "adhoc"
        result = self.run_script("sign-app.sh", "App.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = self.commands("codesign")[0]
        self.assertEqual(command[command.index("--sign") + 1], "-")
        self.assertNotIn("--timestamp", command)

    def test_notarization_staples_and_assesses(self):
        self.env["DARNIRI_NOTARIZE_PROFILE"] = "test-profile"
        result = self.run_script("notarize-app.sh", "App.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.commands("codesign")[0][-2].startswith("=anchor "))
        commands = self.commands("xcrun")
        self.assertEqual(commands[0][1:3], ["notarytool", "submit"])
        self.assertIn("--wait", commands[0])
        self.assertEqual(commands[1], ["xcrun", "stapler", "staple", "App.app"])
        self.assertEqual(commands[2], ["xcrun", "stapler", "validate", "App.app"])
        self.assertEqual(len(self.commands("spctl")), 1)

    def test_notarization_refuses_invalid_signature(self):
        self.env["DARNIRI_NOTARIZE_PROFILE"] = "test-profile"
        self.env["SIGN_TEST_VERIFY_EXIT"] = "1"
        self.assertNotEqual(self.run_script("notarize-app.sh", "App.app").returncode, 0)
        self.assertEqual(self.commands("xcrun"), [])


if __name__ == "__main__":
    unittest.main()
