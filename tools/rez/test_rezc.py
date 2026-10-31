#!/usr/bin/env python3
"""Tests of tools/rez/rezc.py (run: python3 tools/rez/test_rezc.py, or
`make rez-test`).

  * resource statements, data, read and include, and the resource-fork
    writer/reader round trip;
  * Apple's own ROMFonts.r (System 7.1 sources, if present) compiles to the
    cursors and Geneva/Monaco fonts of the SE ROM, byte for byte;
  * the ROM back end: a small ROM with assembled ('asm') and Rez-compiled
    ('rez') resources, one of odd length, is assembled with the macros of
    include/romrsrc.inc (if the m68k binutils are installed) and read back:
    order, names, attributes, sizes, padding, relative handles, the map's
    copy of the resource header; and a resource out of order stops the
    assembly.
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import rezc  # noqa: E402

ROMFONTS = os.path.join(REPO, 'Mac_OS_7.1_Source_Code', 'System 7.1 Source Code',
                        'Resources', 'ROMFonts.r')
SE_ROM = os.path.join(REPO, 'build', 'rom-mac_se.bin')


def tool(name):
    for prefix in ('m68k-linux-gnu-', 'm68k-elf-'):
        if shutil.which(prefix + name):
            return prefix + name
    return None


def compile_sources(texts, files=None, lenient=False, include_dirs=()):
    """Compiles Rez sources (name -> text) in a scratch directory; returns
    the Compiler and the directory (removed at exit)."""
    tmp = tempfile.mkdtemp(prefix='rezc-test-')
    for name, data in (files or {}).items():
        with open(os.path.join(tmp, name), 'wb') as fp:
            fp.write(data)
    c = rezc.Compiler(include_dirs=include_dirs, lenient=lenient)
    for tf in rezc.TYPES_FILES:
        c.compile_file(tf)
    c.resources.clear()
    c.order.clear()
    for name, text in texts.items():
        path = os.path.join(tmp, name)
        with open(path, 'w') as fp:
            fp.write(text)
        c.compile_file(path)
    return c, tmp


class LanguageTest(unittest.TestCase):
    def test_statements_and_fork_roundtrip(self):
        src = r'''
#define kName "two"
resource 'STR ' (128, kName, sysHeap, purgeable) { "hello" };
data 'abcd' (1) { $"0102 0304" "xy" };
read 'blob' (-5, "file", locked) "blob.bin";
resource 'CURS' (7) {
	$"0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 FFFF",
	$"FFFF 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000",
	{8, 8}
};
'''
        c, tmp = compile_sources({'t.r': src}, files={'blob.bin': b'\x00\x01\x02'})
        r = c.resources[(b'STR ', 128)]
        self.assertEqual(r.data, b'\x05hello')
        self.assertEqual(r.name, b'two')
        self.assertEqual(r.attrs, 0x40 | 0x20)
        self.assertEqual(c.resources[(b'abcd', 1)].data, b'\x01\x02\x03\x04xy')
        self.assertEqual(c.resources[(b'blob', -5)].data, b'\x00\x01\x02')
        self.assertEqual(len(c.resources[(b'CURS', 7)].data), 68)
        fork = rezc.write_resource_fork([c.resources[k] for k in c.order])
        back = {(r.restype, r.resid): r for r in rezc.read_resource_fork(fork)}
        self.assertEqual(set(back), set(c.resources))
        for k, r in c.resources.items():
            self.assertEqual((back[k].data, back[k].name, back[k].attrs),
                             (r.data, r.name, r.attrs))
        # include statement: resources of the fork just written
        with open(os.path.join(tmp, 'f.rsrc'), 'wb') as fp:
            fp.write(fork)
        c2, _ = compile_sources({'u.r': 'include "%s" \'abcd\';\n' % os.path.join(tmp, 'f.rsrc')})
        self.assertEqual(list(c2.resources), [(b'abcd', 1)])

    def test_mac_roman_cr_and_continuation(self):
        text = '#define A \\\r\t3\rdata \'ab  \' (A, "caf\x8e") { $"00" };\r'
        tmp = tempfile.mkdtemp(prefix='rezc-test-')
        path = os.path.join(tmp, 'mr.r')
        with open(path, 'wb') as fp:
            fp.write(text.encode('latin-1'))
        c = rezc.Compiler()
        c.compile_file(path)
        r = c.resources[(b'ab  ', 3)]
        self.assertEqual(r.name, b'caf\x8e')      # Mac Roman e-acute kept as is


@unittest.skipUnless(os.path.isfile(ROMFONTS) and os.path.isfile(SE_ROM),
                     'needs the System 7.1 sources and build/rom-mac_se.bin')
class AppleRomFontsTest(unittest.TestCase):
    def test_romfonts_matches_se_rom(self):
        stub = tempfile.mkdtemp(prefix='rezc-test-')
        open(os.path.join(stub, 'SysTypes.r'), 'w').close()
        c = rezc.Compiler(include_dirs=[stub], lenient=True)
        for tf in rezc.TYPES_FILES:
            c.compile_file(tf)
        c.resources.clear()
        c.compile_file(ROMFONTS)
        with open(SE_ROM, 'rb') as fp:
            rom, _ = rezc.read_rom_resource_fork(fp.read())
        se = {(r.restype, r.resid): r.data for r in rom}
        for key in [(b'CURS', 1), (b'CURS', 2), (b'CURS', 3), (b'CURS', 4),
                    (b'FONT', 393), (b'FONT', 396), (b'FONT', 521)]:
            self.assertEqual(c.resources[key].data, se[key], key)


ROM_R = r'''
#include "RomTypes.r"
resource 'rrhd' (0) {
	0x54, 0xCC1C, 2, mapReadOnly, "BASEOFROM",
	{ 'DRVR', 9 }
};
resource 'rrsc' (1) {
	{
		asm { 'DRVR', 2, sysHeap+locked+protected, ".Print", "DRVR_2" };
		rez { 'TEST', 5, "TEST_5" };
		asm { 'DRVR', 9, sysHeap+locked+protected, ".MPP", "DRVR_9" };
		asm { 'ODD ', 1, sysHeap, "", "ODD_1" }
	}
};
data 'TEST' (5, "five", sysHeap, purgeable) { $"0102 0304 05" };
'''

ROM_S = r'''
    .text
BASEOFROM:
    .long   0
    .fill   0x16, 1, 0xFF
    .long   ROM_RESOURCE_AREA_START - BASEOFROM
    .include "romrsrc.inc"
    .include "test_rsrc.inc"
ROM_RESOURCE_AREA_START:
    ROM_RESOURCE_AREA
    ROM_RESOURCE_MAP
    ROM_RESOURCE DRVR_2
    .byte   1, 2, 3, 4
    ROM_RESOURCE_END DRVR_2
    ROM_RESOURCE_REZ TEST_5
    ROM_RESOURCE DRVR_9
    MOVEQ   #0, D0
    RTS
    ROM_RESOURCE_END DRVR_9
    ROM_RESOURCE ODD_1
    .byte   7, 7, 7
    ROM_RESOURCE_END ODD_1
'''


@unittest.skipUnless(tool('as') and tool('objcopy'), 'needs the m68k binutils')
class RomBackendTest(unittest.TestCase):
    def build(self, asm_text):
        c, tmp = compile_sources({'RomResources.r': ROM_R})
        inc = os.path.join(tmp, 'test_rsrc.inc')
        with open(inc, 'w') as fp:
            fp.write(rezc.generate_rom_asm(c, [os.path.join(tmp, 'RomResources.r')],
                                           'test_rsrc.inc'))
        src = os.path.join(tmp, 'rom.s')
        with open(src, 'w') as fp:
            fp.write(asm_text)
        obj, binf = os.path.join(tmp, 'rom.o'), os.path.join(tmp, 'rom.bin')
        p = subprocess.run([tool('as'), '-m68000', '--register-prefix-optional',
                            '-I' + os.path.join(REPO, 'include'), '-I' + tmp,
                            '-o', obj, src], capture_output=True, text=True)
        if p.returncode:
            return None, p.stderr
        subprocess.run([tool('objcopy'), '-O', 'binary', obj, binf], check=True)
        with open(binf, 'rb') as fp:
            return fp.read(), ''

    def test_rom_layout(self):
        rom, err = self.build(ROM_S)
        self.assertIsNotNone(rom, err)
        res, info = rezc.read_rom_resource_fork(rom)
        got = [(r.restype, r.resid, r.name, r.attrs) for r in res]
        # map order: types in the order of their first resource, ROM order within
        self.assertEqual(got, [(b'DRVR', 2, b'.Print', 0x58), (b'DRVR', 9, b'.MPP', 0x58),
                               (b'TEST', 5, b'five', 0x60), (b'ODD ', 1, None, 0x40)])
        rom_order = sorted(res, key=lambda r: r.rom[0])
        self.assertEqual([(r.restype, r.resid) for r in rom_order],
                         [(b'DRVR', 2), (b'TEST', 5), (b'DRVR', 9), (b'ODD ', 1)])
        self.assertEqual([r.rom[2] for r in rom_order], [0x54, 0x58, 0x5C, 0x60])
        self.assertTrue(all(r.rom[1] == 0xC0 for r in res))
        by = {(r.restype, r.resid): r for r in res}
        self.assertEqual(by[(b'DRVR', 2)].data, b'\x01\x02\x03\x04')
        self.assertEqual(by[(b'TEST', 5)].data, b'\x01\x02\x03\x04\x05\x00')  # padded
        self.assertEqual(by[(b'ODD ', 1)].data, b'\x07\x07\x07\x00')           # padded
        # resources follow each other without gaps
        for a, b in zip(rom_order, rom_order[1:]):
            self.assertEqual(a.rom[0] + 8 + len(a.data), b.rom[0])
        # header copy: data length counts each resource's logical size + 4
        datalen = 4 * 4 + 4 + 5 + 4 + 3
        self.assertEqual(info['header'], [0x100, 0x100 + datalen, datalen, info['map_size']])
        self.assertEqual((info['count'], info['next_map'], info['file_ref'], info['map_attrs']),
                         (4, 0xCC1C, 2, 0x8000))
        # the name list starts with the names of the 'rrhd' order
        m = info['area'] + 4
        nl = m + int.from_bytes(rom[m + 26:m + 28], 'big')
        self.assertEqual(rom[nl:nl + 5], b'\x04.MPP')

    def test_out_of_order(self):
        swapped = ROM_S.replace('    ROM_RESOURCE_REZ TEST_5\n', '').replace(
            '    ROM_RESOURCE ODD_1\n', '    ROM_RESOURCE_REZ TEST_5\n    ROM_RESOURCE ODD_1\n')
        rom, err = self.build(swapped)
        self.assertIsNone(rom)
        self.assertIn('not in the place that RomResources.r gives it', err)


if __name__ == '__main__':
    unittest.main(verbosity=2)
