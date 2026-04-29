# Macintosh ROM Source Tree

This repository contains a fully commented,
buildable 68000 assembly source tree for five classic-era Macintosh
ROMs. The same source tree assembles into bit-identical copies of
each ROM via `--defsym ROM_TARGET={1..5}`.

## Legal disclaimer

This is a pure hobby project. No copyright infringements or similar is intended.  
Please inform the author about possible legal issues before turning to a lawyer.

## Build

Toolchain on Debian / Ubuntu:

    sudo apt install binutils-m68k-linux-gnu

Build all five ROM variants and verify each against its reference binary:

    make

The `make` step expects the reference binaries under the path given
by the `ROM_REF_DIR` Makefile variable (default `../macroms/Mac_ROMs/68k`).
Override on the command line if needed:

    make ROM_REF_DIR=/path/to/Mac_ROMs/68k

A successful run reports `SUCCESS: ALL FIVE ROMS BIT-IDENTICAL`.

You get these reference ROMs from here: https://www.macintoshrepository.org/7038-all-macintosh-roms-68k-ppc-

Per-target builds:

    make mac_128k      # 1984-01, 64 KB,  $28BA61CE
    make mac_512k      # 1984-10, 64 KB,  $28BA4E50
    make mac_plus_v1   # 1986-01, 128 KB, $4D1EEEE1
    make mac_plus_v2   # 1986-03, 128 KB, $4D1EEAE1  (branch-fix)
    make mac_plus_v3   # 1986-03, 128 KB, $4D1F8172  (SCSI patch)

## Layout

    rom_original.s         Master include for Mac 128K / 512K
    rom_plus.s             Master include for Mac Plus (all variants)
    original/              Mac 128K / 512K source tree (5 subsystems)
    plus/                  Mac Plus source tree (8 subsystems)
    include/               Assembler equates (traps, low-mem, hw regs)
    Makefile               Self-contained build pipeline

`include/` files:

    rom_target.inc         ROM target selector (MAC_128K..MAC_PLUS_V3)
    traps.inc              287 A-line trap macros
    lowmem.inc             386 low-memory globals
    hwregs.inc             Hardware registers (VIA, SCC, IWM, SCSI)
    sysequ.inc             System equates (IOParam, queues, events)
    fsequ.inc              File system equates (VCB, FCB)
    toolequ.inc            Toolbox equates (Window, Control, Menu, TE)
    sonyequ.inc            Sony disk-driver equates
    private.inc            Private system equates (memory mgr internals)
    macros.inc             Helper macros (UNLINK, etc.)

## ROM variants and checksums

| Target       | Date    | Size   | Checksum  | Notes                  |
|--------------|---------|--------|-----------|------------------------|
| mac_128k     | 1984-01 | 64 KB  | 28BA61CE  | Original Mac           |
| mac_512k     | 1984-10 | 64 KB  | 28BA4E50  | "Fat Mac"              |
| mac_plus_v1  | 1986-01 | 128 KB | 4D1EEEE1  | First Plus             |
| mac_plus_v2  | 1986-03 | 128 KB | 4D1EEAE1  | Branch-condition fixes |
| mac_plus_v3  | 1986-03 | 128 KB | 4D1F8172  | SCSI patch (default)   |

The 128 K and 512 K Macs differ at only 6 sites totaling 57 bytes; all
are wrapped in `.if ROM_TARGET == MAC_128K / .else / .endif`.

The three Plus variants differ at 6 sites totaling 33 bytes (v1->v3) or
31 bytes (v2->v3); all are wrapped in `.if ROM_TARGET == MAC_PLUS_V<x>`.

## Source-tree organization

`original/` (1984 ROM, ~38 files in 5 subsystems):
- `boot/`, `os/`, `hw/`, `resources/`, `toolbox/`

`plus/` (1986 ROM, ~82 files in 8 subsystems):
- `boot/`, `debugger/`, `extra/`, `hw/`, `os/`, `resources/`, `toolbox/`
  (with `quickdraw/` sub-folder)

Each `.s` file begins with a banner describing its routines and any
ROM-mandated cross-subsystem leakage. ROM byte order is fixed; the
file-boundary placement reflects subsystem grouping where possible.

## Acknowledgements

This repo builds on the massive amount of the work of others,
last but not least by the team at Apple Computer Inc.,
who designed and implemented the Macintosh ROM.

A list of information sources that went into this project is provided below.
It is likely incomplete - please open an issue if you find that a given
resource missing.

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
