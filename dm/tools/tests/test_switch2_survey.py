"""Switch 2 NSO static survey tests using synthetic, non-proprietary ARM64 bytes."""
from pathlib import Path
import hashlib
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "dm/tools"))
import switch2_survey


def make_nso():
    text = struct.pack("<IIII", 0xD503233F, 0xD503245F, 0xD4001001, 0xD65F03C0)  # paciasp; bti c; svc #0x80; ret
    ro = b"read-only test!!"
    data = b"writable test!!!"
    header = bytearray(0x100)
    header[:4] = b"NSO0"
    header[0x40:0x60] = bytes(range(32))
    flags = 0x40 | 0x38  # execute-only text + all three segment hashes
    struct.pack_into("<I", header, 0x0C, flags)
    segments = [(0x100, 0x0000, text), (0x110, 0x1000, ro), (0x120, 0x2000, data)]
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

    def test_rejects_non_nso(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "not-an-nso.bin"
            path.write_bytes(bytes(256))
            with self.assertRaises(Exception):
                switch2_survey.survey(path)


if __name__ == "__main__":
    unittest.main()
