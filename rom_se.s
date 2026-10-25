| ===========================================================================
| Macintosh SE ROM master file (256 KB) -- builds both SE ROMs:
|
|   ROM_TARGET=6  MAC_SE       1987-03  $B2E362A8  MD5 9fb38bdcc0d53d9d380897ee53dc1322
|   ROM_TARGET=7  MAC_SE_FDHD  1989-08  $B306E171  MD5 886444d7abc1185112391b8656c7e448
|
| Reset PC 0x0040002A. The SE FDHD ROM is the 1987 SE ROM with the
| SuperDrive (SWIM) .Sony driver; the two images differ at five sites,
| each wrapped in an `.if ROM_TARGET == MAC_SE` block: the ROM checksum
| and the per-chip checksums (boot/vectors.s), the RAM-test call
| (boot/memtest.s), the .Sony driver (resources/res_drvr_sony_fdhd.s
| for the FDHD, resources/res_drvr_sony.s for the SE) and
| the tail after the last resource (extra/rom_tail.s).
|
| Assembles with (the Makefile does this per target):
|   m68k-linux-gnu-as -m68000 --register-prefix-optional -Iinclude \
|       --defsym ROM_TARGET=7 -o rom.o src/se/rom_se.s
|
| Source provenance:
|   - macsefdhd_documented_source/.../source/macsefdhd_documented.s
|     (byte-authoritative reconstruction of the SE FDHD ROM, the Phase 0
|     seed of this file)
|   - Macintosh SE FDHD ROM.txt FDisasm Motorola listing
|   - MacSEROM.lst (MPW GM 3.5 link map of the SE ROM): label names
|   - Mac OS 7.1 sources (Drivers/Sony etc.) and the Mac Plus tree
| ===========================================================================

  .include "rom_target.inc"
  .include "traps.inc"
| Phase-2: SE-era A-line trap macros not in Plus's traps.inc (ADB stack,
| _StripAddress, expanded Memory Mgr handle-state ops, _InternalWait,
| _KeyTranslate, _UnpackBits, _OpenRFPerm, etc.).
  .include "traps_se.inc"
  .include "lowmem.inc"
  .include "hwregs.inc"
  .include "sysequ.inc"
  .include "fsequ.inc"
  .include "toolequ.inc"
  .include "sonyequ.inc"
  .include "private.inc"
| Phase-2: SE FDHD-specific low-memory globals and overrides. Comes
| AFTER private.inc / lowmem.inc so its `.set` directives can redefine
| addresses that differ between Plus and SE (e.g. ToolTable: 0x0C00 ->
| 0x0E00) and add SE-era new symbols (ADB, MicroFloppy, MacroMaker, ...).
  .include "lowmem_se.inc"
  .include "macros.inc"

  .org 0x0                                      | ROM base address


  .include "se/boot/vectors.s"
  .include "se/boot/boot_install.s"
  .include "se/boot/boot_load.s"
  .include "se/boot/boot_search.s"
  .include "se/boot/sad_mac.s"
  .include "se/debugger/debugger.s"
  .include "se/os/sys_error.s"
  .include "se/debugger/microbug.s"
  .include "se/boot/memtest.s"
  .include "se/os/queue.s"
  .include "se/hw/interrupts.s"
  .include "se/os/vbl_mgr.s"
  .include "se/os/trap_dispatch.s"
  .include "se/os/device_mgr.s"
  .include "se/os/adb_mgr.s"
  .include "se/os/event_mgr.s"
  .include "se/os/scsi_boot.s"
  .include "se/os/file_mgr_queue.s"
  .include "se/os/file_mgr_vol.s"
  .include "se/os/file_mgr_dir.s"
  .include "se/os/file_mgr_io.s"
  .include "se/os/file_mgr_alloc.s"
  .include "se/os/file_mgr_catalog.s"
  .include "se/os/file_mgr_btree.s"
  .include "se/os/file_mgr_cache.s"
  .include "se/os/segment_loader.s"
  .include "se/os/os_utilities.s"
  .include "se/hw/rtc.s"
  .include "se/os/memory_mgr.s"
  .include "se/toolbox/toolbox_event.s"
  .include "se/toolbox/window_mgr.s"
  .include "se/toolbox/menu_mgr.s"
  .include "se/toolbox/control_mgr.s"
  .include "se/toolbox/resource_mgr.s"
  .include "se/toolbox/dialog_mgr.s"
  .include "se/toolbox/toolbox_utils.s"
  .include "se/toolbox/fixmath.s"
  .include "se/toolbox/desk_mgr.s"
  .include "se/toolbox/get_mgr.s"
  .include "se/toolbox/textedit.s"
  .include "se/toolbox/scrap_mgr.s"
  .include "se/toolbox/print_glue.s"
  .include "se/toolbox/quickdraw/LCursor.s"
  .include "se/toolbox/quickdraw/Util.s"
  .include "se/toolbox/quickdraw/GrafAsm.s"
  .include "se/toolbox/quickdraw/Text.s"
  .include "se/toolbox/quickdraw/DrawText.s"
  .include "se/toolbox/quickdraw/Lines.s"
  .include "se/toolbox/quickdraw/DrawLine.s"
  .include "se/toolbox/quickdraw/PutLine.s"
  .include "se/toolbox/quickdraw/Rects.s"
  .include "se/toolbox/quickdraw/BitBlt.s"
  .include "se/toolbox/quickdraw/RgnBlt.s"
  .include "se/toolbox/quickdraw/RRects.s"
  .include "se/toolbox/quickdraw/Ovals.s"
  .include "se/toolbox/quickdraw/PutOval.s"
  .include "se/toolbox/quickdraw/Arcs.s"
  .include "se/toolbox/quickdraw/DrawArc.s"
  .include "se/toolbox/quickdraw/Angles.s"
  .include "se/toolbox/quickdraw/Polygons.s"
  .include "se/toolbox/quickdraw/Regions.s"
  .include "se/toolbox/quickdraw/SeekRgn.s"
  .include "se/toolbox/quickdraw/RgnOp.s"
  .include "se/toolbox/quickdraw/SortPoints.s"
  .include "se/toolbox/quickdraw/PutRgn.s"
  .include "se/toolbox/quickdraw/PackRgn.s"
  .include "se/toolbox/quickdraw/Bitmaps.s"
  .include "se/toolbox/quickdraw/Stretch.s"
  .include "se/toolbox/quickdraw/Pictures.s"
  .include "se/toolbox/quickdraw/CrsrCore.s"
  .include "se/toolbox/font_mgr.s"
  .include "se/toolbox/package_mgr.s"
  .include "se/os/date_utils.s"
  .include "se/os/scsi_mgr.s"
  .include "se/os/time_mgr.s"
  .include "se/os/dispatch_table.s"
  .include "se/resources/res_map.s"
  .include "se/resources/res_pack_5.s"
  .include "se/resources/res_pack_4.s"
  .include "se/resources/res_pack_7.s"
  .include "se/resources/res_tcsl.s"
  .include "se/resources/res_bbmc.s"
  .include "se/resources/res_serd.s"
  .include "se/resources/res_drvr_atp.s"
  .include "se/resources/res_drvr_mpp.s"
  .include "se/resources/res_drvr_sony_fdhd.s"
  .include "se/resources/res_drvr_sony.s"
  .include "se/resources/res_drvr_sound.s"
  .include "se/resources/res_drvr_xpp.s"
  .include "se/resources/res_cdef_0.s"
  .include "se/resources/res_cdef_1.s"
  .include "se/resources/res_kchr.s"
  .include "se/resources/res_kmap.s"
  .include "se/resources/res_mbdf.s"
  .include "se/resources/res_mdef.s"
  .include "se/resources/res_wdef_1.s"
  .include "se/resources/res_wdef_0.s"
  .include "se/resources/res_curs.s"
  .include "se/resources/res_font_chicago.s"
  .include "se/resources/res_font_geneva.s"
  .include "se/resources/res_font_monaco.s"
  .include "se/extra/rom_tail.s"
