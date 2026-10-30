#!/usr/bin/env python3
"""Read-only Switch 2 NSO survey: report module flags and AArch64 instructions.

This tool does not execute or modify the input. It deliberately reports observations
rather than inferring Horizon ABI compatibility from an NSO header.
"""
import argparse
import json
import re
import struct
import sys
from pathlib import Path

import capstone
import nso


PAC = ("pac", "aut", "xpac")
PAC_BRANCH = ("braa", "brab", "blraa", "blrab", "retaa", "retab")
LSE = ("cas", "casa", "casal", "casl", "swp", "ldadd", "ldclr", "ldeor", "ldset",
       "ldsmax", "ldsmin", "ldumax", "ldumin")
SYSREGS = ("tpidr_el0", "tpidrro_el0", "tpidr2_el0", "cntpct_el0",
           "cntvct_el0", "cntfrq_el0", "cntvoff_el2")


def dynamic_symbols(raw: bytes, module) -> dict:
    """Read the NSO dynstr/dynsym extents, which are relative to .rodata."""
    dynstr_off, dynstr_size, dynsym_off, dynsym_size = struct.unpack_from("<IIII", raw, 0x90)
    ro_base, ro_size = module.segments[1]
    if not dynstr_size and not dynsym_size:
        return {"available": False, "reason": "NSO header has no dynamic symbol extents"}
    if dynstr_off > ro_size or dynstr_size > ro_size - dynstr_off:
        return {"available": False, "reason": "dynamic string table exceeds .rodata bounds"}
    if dynsym_off > ro_size or dynsym_size > ro_size - dynsym_off:
        return {"available": False, "reason": "dynamic symbol table exceeds .rodata bounds"}
    if dynsym_size % 24:
        return {"available": False, "reason": "dynamic symbol table size is not a multiple of Elf64_Sym"}
    image = module.image
    strings = image[ro_base + dynstr_off:ro_base + dynstr_off + dynstr_size]
    imports, exports = [], []
    binding_names = {0: "local", 1: "global", 2: "weak", 10: "gnu_unique"}
    type_names = {0: "notype", 1: "object", 2: "function", 3: "section", 4: "file", 5: "common", 6: "tls", 10: "ifunc"}
    for offset in range(ro_base + dynsym_off, ro_base + dynsym_off + dynsym_size, 24):
        name_offset, info, other, shndx, value, size = struct.unpack_from("<IBBHQQ", image, offset)
        if name_offset >= len(strings):
            continue
        end = strings.find(0, name_offset)
        if end < 0:
            continue
        name = bytes(strings[name_offset:end]).decode("utf-8", errors="replace")
        if not name:
            continue
        item = {
            "name": name,
            "binding": binding_names.get(info >> 4, f"bind_{info >> 4}"),
            "type": type_names.get(info & 0x0f, f"type_{info & 0x0f}"),
            "value": f"0x{value:x}",
            "size": size,
            "visibility": other & 0x03,
        }
        (imports if shndx == 0 else exports).append(item)
    return {
        "available": True,
        "dynamic_string_bytes": dynstr_size,
        "dynamic_symbol_count": dynsym_size // 24,
        "undefined_imports": imports[:512],
        "defined_symbols": exports[:512],
        "undefined_import_count": len(imports),
        "defined_symbol_count": len(exports),
        "truncated": len(imports) > 512 or len(exports) > 512,
    }


def survey(path: Path) -> dict:
    raw = path.read_bytes()
    if raw[:4] != b"NSO0":
        raise nso.Error(f"{path}: Switch 2 survey currently expects an NSO0 module")
    if len(raw) < 0x100:
        raise nso.Error(f"{path}: truncated NSO0 header")
    flags = struct.unpack_from("<I", raw, 0x0C)[0]
    module = nso.load(raw, str(path))
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    md.skipdata = True

    text_size = module.segments[0][1]
    text = memoryview(module.image)[:text_size]
    counts = {"pac_auth": 0, "pac_branch": 0, "bti": 0, "svc": 0, "lse_atomic": 0}
    samples = {"pac_auth": [], "pac_branch": [], "bti": [], "svc": [], "system_registers": []}
    sysregs = {}
    svc_numbers = {}

    for insn in md.disasm(bytes(text), 0):
        mnemonic = insn.mnemonic.lower()
        operands = insn.op_str.lower()
        item = {"offset": f"0x{insn.address:x}", "instruction": f"{mnemonic} {insn.op_str}".strip()}

        if mnemonic.startswith(PAC):
            counts["pac_auth"] += 1
            if len(samples["pac_auth"]) < 32:
                samples["pac_auth"].append(item)
        if mnemonic in PAC_BRANCH:
            counts["pac_branch"] += 1
            if len(samples["pac_branch"]) < 32:
                samples["pac_branch"].append(item)
        if mnemonic == "bti":
            counts["bti"] += 1
            if len(samples["bti"]) < 32:
                samples["bti"].append(item)
        if mnemonic == "svc":
            counts["svc"] += 1
            match = re.search(r"#(?:0x([0-9a-f]+)|([0-9]+))", operands)
            number = int(match.group(1), 16) if match and match.group(1) else int(match.group(2)) if match else -1
            key = f"0x{number:x}" if number >= 0 else "unknown"
            svc_numbers[key] = svc_numbers.get(key, 0) + 1
            if len(samples["svc"]) < 64:
                samples["svc"].append(item)
        if mnemonic.startswith(LSE):
            counts["lse_atomic"] += 1
        if mnemonic in ("mrs", "msr"):
            for register in SYSREGS:
                if register in operands:
                    sysregs[register] = sysregs.get(register, 0) + 1
                    if len(samples["system_registers"]) < 64:
                        samples["system_registers"].append(item)
                    break

    segments = []
    for index, name in enumerate(("text", "rodata", "data")):
        file_offset, memory_offset, size = struct.unpack_from("<III", raw, 0x10 + index * 0x10)
        stored_size = struct.unpack_from("<I", raw, 0x60 + index * 4)[0]
        compressed = bool(flags & (1 << index))
        segments.append({
            "name": name,
            "file_offset": f"0x{file_offset:x}",
            "memory_offset": f"0x{memory_offset:x}",
            "memory_size": size,
            "stored_size": stored_size if compressed else size,
            "compressed": compressed,
            "sha256_checked": bool(flags & (1 << (index + 3))),
        })

    return {
        "file": path.name,
        "format": "NSO0",
        "module_id": module.build_id.hex(),
        "flags": f"0x{flags:08x}",
        "flag_details": {
            "text_compressed": bool(flags & 0x01),
            "rodata_compressed": bool(flags & 0x02),
            "data_compressed": bool(flags & 0x04),
            "text_hash_checked": bool(flags & 0x08),
            "rodata_hash_checked": bool(flags & 0x10),
            "data_hash_checked": bool(flags & 0x20),
            "execute_only_text": bool(flags & 0x40),
            "zbic_compression": bool(flags & 0x80),
        },
        "segments": segments,
        "dynamic_symbols": dynamic_symbols(raw, module),
        "bss_size": module.bss,
        "aarch64_text_scan": {
            "decoded_text_bytes": text_size,
            "instruction_counts": counts,
            "svc_numbers": svc_numbers,
            "system_register_accesses": sysregs,
            "samples": samples,
            "notes": [
                "Disassembly is static and may skip data or embedded tables in executable sections.",
                "Instruction counts are evidence for follow-up ABI work, not proof that the host supports every instruction.",
                "PAC, BTI, execute-only memory and SVC handling require explicit Switch 2 compatibility work.",
            ],
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module", type=Path, help="self-built or otherwise authorized Switch 2 NSO module")
    parser.add_argument("-o", "--output", type=Path, help="write JSON report here (default: stdout)")
    args = parser.parse_args()
    try:
        report = survey(args.module)
    except (OSError, nso.Error) as exc:
        print(f"[RED] {exc}", file=sys.stderr)
        return 1
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
