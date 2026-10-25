# Macintosh ROM Source Tree

This repository contains a fully commented,
buildable 68000 assembly source tree for seven classic-era Macintosh
ROMs. The same source tree assembles into bit-identical copies of
each ROM via `--defsym ROM_TARGET={1..7}`.

## Legal disclaimer

This is a pure hobby project. No copyright infringements or similar is intended.  
Please inform the author about possible legal issues before turning to a lawyer.

## Build

Toolchain on Debian / Ubuntu:

    sudo apt install binutils-m68k-linux-gnu

(on Arch Linux: `m68k-elf-binutils`; the Makefile auto-detects either
`m68k-linux-gnu-` or `m68k-elf-` tools, override with `make CROSS=...`).

Build all seven ROM variants and verify each one:

    make

No original ROM images are needed. Every build is checked against
fingerprints of the original ROMs that are hardcoded in the Makefile:
the image size, the ROM's own checksum signature in its first four bytes
(both the stored value and the checksum recomputed over the image), the
ROM version word at offset 8, and the MD5 of the whole image; for the
two SE ROMs also the checksums of the two 128 KB ROM chips that the ROM
stores at offsets $30 and $34.

If you have the original ROM images, the build additionally compares
each one byte-for-byte against them. They are looked up under the path
given by the `ROM_REF_DIR` Makefile variable (default
`../macroms/Mac_ROMs/68k`, using the file names of the macintoshrepository.org
ROM collection); override on the command line if needed:

    make ROM_REF_DIR=/path/to/Mac_ROMs/68k

A successful run reports `SUCCESS: ALL SEVEN ROMS BIT-IDENTICAL`.

The reference ROMs are available here: https://www.macintoshrepository.org/7038-all-macintosh-roms-68k-ppc-

## ROM maps

`maps/` holds a map of every label of each ROM, generated from the
assembled source (`make rommap` regenerates them in `build/`):

    maps/rom-<target>.lst      the layout of Apple's MPW ROM maps
                               (MacPlusROM.lst, MacSEROM.lst; "ROM.List")
    maps/rom-<target>.lst.txt  "name 0xOFFSET l" lines, the format of
                               joevt/68k-mac-rom-maps (for Ghidra's
                               ImportSymbolsScript.py)

The Mac Plus labels follow Apple's MacPlusROM.lst (MPW 3.5 GM): every
entry of that map is matched by the generated Plus maps, either by name
or, where Apple lists a trap-table placeholder (Trap0_xx / Trap1_xxx),
an unimplemented trap slot or a 15-character truncation, through the
ROM's own trap dispatch table. The SE labels follow Apple's
MacSEROM.lst, a link map of the SE ROM: every entry is matched by both
SE maps, by name, as another of Apple's names for the same address
(module names such as TURBOFS are noted in comments in the source) or,
for CONTROL and STATUS, which cannot be assembler labels, through the
trap dispatch table. There is no Apple map for the 64K ROM of the
Macintosh 128K/512K; there, every trap entry point that the Plus also
implements carries the Plus name.

Per-target builds:

    make mac_128k      # 1984-01, 64 KB,  $28BA61CE
    make mac_512k      # 1984-10, 64 KB,  $28BA4E50
    make mac_plus_v1   # 1986-01, 128 KB, $4D1EEEE1
    make mac_plus_v2   # 1986-03, 128 KB, $4D1EEAE1  (branch-fix)
    make mac_plus_v3   # 1986-03, 128 KB, $4D1F8172  (SCSI patch)
    make mac_se        # 1987-03, 256 KB, $B2E362A8
    make mac_se_fdhd   # 1989-08, 256 KB, $B306E171

## Layout

    rom_original.s         Master include for Mac 128K / 512K
    rom_plus.s             Master include for Mac Plus (all variants)
    rom_se.s               Master include for Mac SE and Mac SE FDHD
    original/              Mac 128K / 512K source tree
    plus/                  Mac Plus source tree
    se/                    Mac SE / SE FDHD source tree
    include/               Assembler equates (traps, low-mem, hw regs)
    maps/                  ROM maps of all seven ROMs (see above)
    tools/verify_rom.sh    ROM verifier (size, checksum, version, MD5, cmp)
    tools/rom_map.sh       ROM map generator (make rommap)
    Makefile               Self-contained build pipeline

`include/` files:

    rom_target.inc         ROM target selector (MAC_128K..MAC_SE_FDHD)
    traps.inc              287 A-line trap macros
    traps_se.inc           37 SE-era A-line trap macros
    lowmem.inc             386 low-memory globals
    lowmem_se.inc          SE overrides + 28 SE-era new symbols
    hwregs.inc             Hardware registers (VIA, SCC, IWM, SCSI)
    sysequ.inc             System equates (IOParam, queues, events)
    fsequ.inc              File system equates (VCB, FCB)
    toolequ.inc            Toolbox equates (Window, Control, Menu, TE)
    sonyequ.inc            Sony disk-driver equates
    private.inc            Private system equates (memory mgr internals)
    macros.inc             Helper macros (UNLINK, etc.)

## ROM variants and checksums

| Target       | Date    | Size   | Checksum  | MD5                              | Notes                  |
|--------------|---------|--------|-----------|----------------------------------|------------------------|
| mac_128k     | 1984-01 | 64 KB  | 28BA61CE  | 1d7f52d2d490524954f6afce083d9593 | Original Mac           |
| mac_512k     | 1984-10 | 64 KB  | 28BA4E50  | db7e6d3205a2b48023fba5aa867ac6d6 | "Fat Mac"              |
| mac_plus_v1  | 1986-01 | 128 KB | 4D1EEEE1  | 4d8d1e81fa606f57c7ed7188b8b5f410 | First Plus             |
| mac_plus_v2  | 1986-03 | 128 KB | 4D1EEAE1  | 16b516e13918a439cf9031ec24353610 | Branch-condition fixes |
| mac_plus_v3  | 1986-03 | 128 KB | 4D1F8172  | 8a41e0754ffd1bb00d8183875c55164c | SCSI patch (default)   |
| mac_se       | 1987-03 | 256 KB | B2E362A8  | 9fb38bdcc0d53d9d380897ee53dc1322 | SE (800K drives)       |
| mac_se_fdhd  | 1989-08 | 256 KB | B306E171  | 886444d7abc1185112391b8656c7e448 | SE w/ SuperDrive       |

The 128 K and 512 K Macs differ at only 6 sites totaling 57 bytes; all
are wrapped in `.if ROM_TARGET == MAC_128K / .else / .endif`.

The three Plus variants differ at 6 sites totaling 33 bytes (v1->v3) or
31 bytes (v2->v3); all are wrapped in `.if ROM_TARGET == MAC_PLUS_V<x>`.

The 1987 Mac SE and the 1989 SE FDHD share the `se/` tree; they
differ at 5 sites (checksum, the two per-chip checksums, a RAM-test
hook, the .Sony driver and the developer-initials/patch tail), wrapped
in `.if ROM_TARGET == MAC_SE`.

## Source-tree organization

Each file holds one subsystem as Apple's own sources divide the ROM:
one module of Apple's link map of the SE ROM (MacSEROM.lst) or one
System 7.1 source file (the 1983 QuickDraw files keep their names),
with the same file name in all three trees. Each `.s` file begins with
a banner that names its routines and its Apple source. ROM byte order
is fixed, so a subsystem that a ROM links in two places has two files.

`original/` (1984 ROM, 68 files): `boot/`, `hw/`, `os/`,
`drivers/` (the 64K ROM's built-in drivers; it has no resource fork),
`toolbox/` (with `quickdraw/`)

`plus/` (1986 ROM, 90 files): `boot/`, `debugger/`, `hw/`, `os/`,
`toolbox/` (with `quickdraw/`), `resources/` (the ROM resource fork),
`extra/`

`se/` (1987 SE and 1989 SE FDHD ROMs, 102 files): the same
directories as `plus/`, with the Apple Desktop Bus Manager
(`os/adb_mgr.s`), both `.Sony` drivers (`resources/res_drvr_sony.s` for
the SE, `resources/res_drvr_sony_fdhd.s` for the SE FDHD), `.XPP`,
CDEF 0/1, MBDF 0, WDEF 1 and the hidden team photos (`res_tcsl.s`,
`res_bbmc.s`)

## Acknowledgements

This repo builds on the massive amount of the work of others,
last but not least by the team at Apple Computer Inc.,
who designed and implemented the Macintosh ROM.

A list of information sources that went into this project is provided below.
It is likely incomplete - please open an issue if you find that a given
resource missing.

* Inside Macintosh I-V
* https://www.gryphel.com/c/minivmac/index.html
* https://www.gryphel.com/c/minivmac/extras/fdisasm/c/index.html
* https://www.gryphel.com/c/minivmac/extras/fdisasm/c/roms.html
* https://www.gryphel.com/c/minivmac/appc/index.html
* https://web.archive.org/web/20230717141356/https://macgui.com/news/article.php?t=523
* https://web.archive.org/web/20230717144604/https://macgui.com/news/article.php?t=514
* https://web.archive.org/web/20230717142244/https://macgui.com/news/article.php?t=502
* https://web.archive.org/web/20230717150821/https://macgui.com/news/article.php?t=499
* https://web.archive.org/web/20231106024332/https://macgui.com/news/article.php?t=493
* https://web.archive.org/web/20230717142458/https://macgui.com/news/article.php?t=488
* https://web.archive.org/web/20230717142324/https://macgui.com/news/article.php?t=483
* https://web.archive.org/web/20230717141349/https://macgui.com/news/article.php?t=480
* https://web.archive.org/web/20230717142557/https://macgui.com/news/article.php?t=443
* https://web.archive.org/web/20230717142259/https://macgui.com/news/article.php?t=336
* https://web.archive.org/web/20230717141429/https://macgui.com/news/showcat.php?id=8
* https://www.bigmessowires.com/category/plustoo/
* https://www.pauladamsmith.com/blog/2025/09/classic-mac-patterns.html
* https://paulsmith.github.io/classic-mac-patterns/
* https://www.folklore.org/0-index.html
* https://axio.ms//projects/2024/06/16/MicroMac.html
* https://computerhistory.org/blog/macpaint-and-quickdraw-source-code/
* https://www.macintoshrepository.org/545-macintosh-programmer-s-workshop-mpw-3-x
