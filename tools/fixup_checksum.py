#!/usr/bin/env python3
"""
Recompute and patch the Macintosh ROM checksum.

The checksum at offset 0 is computed as:
  sum of all 16-bit words from offset 4 to end of ROM, modulo 2^32
(same algorithm for the 64 KB 128K/512K, 128 KB Plus and 256 KB SE ROMs)

256 KB (Mac SE) images also carry per-chip checksums at $30 and $34: the
byte sums of the even (high-byte chip) and odd (low-byte chip) addresses,
with the checksum at $0 and these two longs taken as zero. They are patched
first, since the checksum at offset 0 covers them.

This tool reads a ROM binary, recomputes the checksums, and patches them.
Use after modifying the ROM source (e.g. its resources) to produce a valid
ROM image.

Usage:
  python3 tools/fixup_checksum.py build/rom.bin
  python3 tools/fixup_checksum.py build/rom.bin --verify   # just verify, don't patch
"""

import struct
import sys
import os

ROM_SIZES = (0x10000, 0x20000, 0x40000)


def compute_checksum(data):
    """Compute Mac ROM checksum: sum of 16-bit words from offset 4."""
    total = 0
    for i in range(4, len(data), 2):
        word = (data[i] << 8) | data[i + 1]
        total = (total + word) & 0xFFFFFFFF
    return total


def compute_chip_checksums(data):
    """SE per-chip checksums: byte sums of the even and odd addresses,
    without offsets 0-3 and $30-$37."""
    even = odd = 0
    for i, b in enumerate(data):
        if i <= 3 or 0x30 <= i <= 0x37:
            continue
        if i % 2 == 0:
            even += b
        else:
            odd += b
    return even & 0xFFFFFFFF, odd & 0xFFFFFFFF


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <rom.bin> [--verify]")
        sys.exit(1)

    rom_path = sys.argv[1]
    verify_only = '--verify' in sys.argv

    with open(rom_path, 'rb') as f:
        data = bytearray(f.read())

    if len(data) not in ROM_SIZES:
        print(f"Error: ROM is {len(data)} bytes, expected one of "
              f"{', '.join(str(n) for n in ROM_SIZES)}")
        sys.exit(1)

    chips_ok = True
    if len(data) == 0x40000:
        chips = compute_chip_checksums(data)
        stored_chips = struct.unpack('>II', data[0x30:0x38])
        print(f"Chip checksums:    stored ${stored_chips[0]:08X} ${stored_chips[1]:08X}, "
              f"computed ${chips[0]:08X} ${chips[1]:08X}")
        chips_ok = stored_chips == chips
        if not chips_ok and not verify_only:
            struct.pack_into('>II', data, 0x30, *chips)
            print("Patched the chip checksums")

    stored = struct.unpack('>I', data[0:4])[0]
    computed = compute_checksum(data)

    print(f"Stored checksum:   ${stored:08X}")
    print(f"Computed checksum: ${computed:08X}")

    if stored == computed and chips_ok:
        print("Checksum is VALID")
        return

    if verify_only:
        print("Checksum MISMATCH")
        sys.exit(1)

    # Patch the checksum
    struct.pack_into('>I', data, 0, computed)
    with open(rom_path, 'wb') as f:
        f.write(data)
    print(f"Patched checksum to ${computed:08X}")


if __name__ == '__main__':
    main()
