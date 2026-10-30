"""Switch 2 NSO static survey tests using synthetic, non-proprietary ARM64 bytes."""
from pathlib import Path
import hashlib
import os
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "dm/tools"))
import switch2_survey


def make_nso(flags=0x40 | 0x38):
    text = struct.pack("<IIII", 0xD503233F, 0xD503245F, 0xD4001001, 0xD65F03C0)  # paciasp; bti c; svc #0x80; ret
    ro = bytearray(0x1000)
    import_one = b"nn::os::CreateThread"
    import_two = b"nn::vi::OpenDisplay"
    strings = bytes([0]) + import_one + bytes([0]) + import_two + bytes([0])
    ro[0x100:0x100 + len(strings)] = strings
    name_one = 1
    name_two = 1 + len(import_one) + 1
    struct.pack_into("<IBBHQQ", ro, 0x200 + 24, name_one, 0x12, 0, 0, 0, 0)
    struct.pack_into("<IBBHQQ", ro, 0x200 + 48, name_two, 0x12, 0, 0, 0, 0)
    data = b"writable test!!!"
    header = bytearray(0x100)
    header[:4] = b"NSO0"
    header[0x40:0x60] = bytes(range(32))
    struct.pack_into("<I", header, 0x0C, flags)
    struct.pack_into("<IIII", header, 0x90, 0x100, len(strings), 0x200, 72)
    segments = [(0x100, 0x0000, text), (0x110, 0x1000, bytes(ro)), (0x1110, 0x2000, data)]
    body = bytearray()
    for i, (file_offset, memory_offset, payload) in enumerate(segments):
        struct.pack_into("<III", header, 0x10 + i * 0x10, file_offset, memory_offset, len(payload))
        struct.pack_into("<I", header, 0x60 + i * 4, len(payload))
        header[0xA0 + i * 0x20:0xC0 + i * 0x20] = hashlib.sha256(payload).digest()
        body.extend(payload)
    return bytes(header + body)


class Switch2SurveyTests(unittest.TestCase):
    def test_detects_xom_pac_bti_and_svc(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "synthetic-main.nso"
            path.write_bytes(make_nso())
            report = switch2_survey.survey(path)
        self.assertTrue(report["flag_details"]["execute_only_text"])
        self.assertEqual(report["aarch64_text_scan"]["instruction_counts"]["pac_auth"], 1)
        self.assertEqual(report["aarch64_text_scan"]["instruction_counts"]["bti"], 1)
        self.assertEqual(report["aarch64_text_scan"]["instruction_counts"]["svc"], 1)
        self.assertEqual(report["aarch64_text_scan"]["svc_numbers"], {"0x80": 1})
        self.assertEqual(
            [item["name"] for item in report["dynamic_symbols"]["undefined_imports"]],
            ["nn::os::CreateThread", "nn::vi::OpenDisplay"],
        )

    def test_rejects_non_nso(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "not-an-nso.bin"
            path.write_bytes(bytes(256))
            with self.assertRaises(Exception):
                switch2_survey.survey(path)

    def test_switch2_target_does_not_use_switch1_rewriter(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "main.nso"
            path.write_bytes(make_nso(flags=0x38))
            env = dict(os.environ, DM_TARGET="switch2")
            result = subprocess.run(
                [sys.executable, "dm/tools/patch_nso.py", str(path), tmp, "main"],
                cwd=ROOT, env=env, capture_output=True, text=True
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Switch 2 native rewriting is not enabled yet", result.stderr)

    def test_xom_module_is_refused_by_switch1_rewriter(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "xom-main.nso"
            path.write_bytes(make_nso())
            env = dict(os.environ)
            env.pop("DM_TARGET", None)
            result = subprocess.run(
                [sys.executable, "dm/tools/patch_nso.py", str(path), tmp, "main"],
                cwd=ROOT, env=env, capture_output=True, text=True
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("execute-only text (XOM)", result.stderr)


if __name__ == "__main__":
    unittest.main()
