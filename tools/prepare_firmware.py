"""Validate a raw 2 MiB Nokia 3310 flash dump and make an FPGA flash payload."""
import argparse
import hashlib
import json
from pathlib import Path

KNOWN = {
    "649de05ed88205a080693b918cd1295ac691dff1": "3310 NHM-5 v5.79 (PPM N)",
    "0e80b5f1698909c9850be770c1289566582aa77a": "3310 NHM-5 v6.07 (PPM C)",
    "9051623c7864410ce1f68d3b854ce578bd251711": "3310 NHM-5 v6.39 (PPM W, MCU+PPM)",
}


def prepare(source, output, eeprom=None):
    data = source.read_bytes()
    if len(data) not in (0x1d0000, 0x200000):
        raise ValueError("Expected a raw MCU+PPM or full flash dump, not a service container")
    if len(data) == 0x1d0000 and not eeprom:
        raise ValueError("MCU+PPM dump needs an explicit --eeprom partition")
    original_sha1 = hashlib.sha1(data).hexdigest()
    if original_sha1 not in KNOWN and b"NHM-5" not in data:
        raise ValueError("Dump is neither a known 3310 image nor marked NHM-5")
    if eeprom:
        ee = eeprom.read_bytes()
        if len(ee) != 0x30000:
            raise ValueError("EEPROM/PM partition must be exactly 0x30000 bytes")
        data = data[:0x1d0000] + ee
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    manifest = {
        "source": str(source), "source_sha1": original_sha1,
        "model": KNOWN.get(original_sha1, "NHM-5, unrecognized build"),
        "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        "phone_base": "0x00200000", "entry": "0x00200040",
        "board_spi_offset": "0x00200000",
        "eeprom_override": str(eeprom) if eeprom else None,
        "status": "validated image; boot verification is recorded separately in docs/STATUS.md",
        "reference": "https://github.com/mamedev/mame/blob/master/src/mame/nokia/nokia_3310.cpp",
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    p.add_argument("--output", type=Path, default=Path("firmware/nokia3310.bin"))
    p.add_argument("--eeprom", type=Path)
    a = p.parse_args()
    try:
        print(json.dumps(prepare(a.source, a.output, a.eeprom), indent=2))
    except (ValueError, OSError) as e:
        p.exit(1, str(e) + "\n")
