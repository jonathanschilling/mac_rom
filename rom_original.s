| Macintosh 128K / 512K ROM master file (64 KB, 1984)
| Entry point for both mac_128k and mac_512k builds. Selects between
| the two variants via the ROM_TARGET preprocessor flag:
| --defsym ROM_TARGET=1 -> MAC_128K (1984-01, checksum $28BA61CE)
| --defsym ROM_TARGET=2 -> MAC_512K (1984-10, checksum $28BA4E50)
| All 57 bytes that differ between 128K and 512K live inline in the
| subsystem files via `.if ROM_TARGET == MAC_128K / .else / .endif`
| blocks:
| $0002 boot/vectors.s ROM checksum low word
| $1CA6 drivers/sony.s Seek after recalibrating: BNE.B vs BRA.B
| $1D8A drivers/sony.s Recal's IWM-ready test: mask $1F vs $3F
| $1D9C drivers/sony.s BEQ.B displacement (512K code 2 bytes longer)
| $1DA2 drivers/sony.s Recal: D1 reload, at most 82 vs 80 steps
| $5040 hw/rtc.s IPL mask 1 -> 3 (in ClkRW)
| Assembles with:
| m68k-linux-gnu-as -m68000 --register-prefix-optional -Iinclude \
| --defsym ROM_TARGET=<1|2> \
| -o rom.o src/original/rom_original.s

  .include "rom_target.inc"
  .include "traps.inc"
  .include "lowmem.inc"
  .include "hwregs.inc"
  .include "sysequ.inc"
  .include "fsequ.inc"
  .include "toolequ.inc"
  .include "sonyequ.inc"
  .include "private.inc"
  .include "macros.inc"

  .org 0x0                                      | ROM base address

| === Boot + low-level OS ===
  .include "original/boot/vectors.s"
  .include "original/boot/boot_install.s"
  .include "original/boot/memtest.s"
  .include "original/boot/sad_mac.s"
  .include "original/os/sys_error.s"
  .include "original/os/queue.s"
  .include "original/hw/interrupts.s"
  .include "original/os/vbl_mgr.s"
  .include "original/toolbox/quickdraw/CrsrCore.s"
  .include "original/os/trap_dispatch.s"
  .include "original/os/device_mgr.s"
  .include "original/os/keyboard.s"
  .include "original/drivers/sony.s"
  .include "original/drivers/serial.s"
  .include "original/os/memory_mgr.s"
  .include "original/drivers/sound.s"
  .include "original/os/event_mgr.s"
  .include "original/os/file_mgr_queue.s"
  .include "original/os/file_mgr_vol.s"
  .include "original/os/file_mgr_dir.s"
  .include "original/os/file_mgr_io.s"
  .include "original/os/segment_loader.s"
  .include "original/os/os_utilities.s"
  .include "original/hw/rtc.s"
  .include "original/os/dispatch_table.s"
  .include "original/toolbox/quickdraw/LCursor.s"
  .include "original/toolbox/quickdraw/Util.s"
  .include "original/toolbox/fixmath.s"
  .include "original/toolbox/quickdraw/GrafAsm.s"
  .include "original/toolbox/quickdraw/Text.s"
  .include "original/toolbox/quickdraw/DrawText.s"
  .include "original/toolbox/quickdraw/Lines.s"
  .include "original/toolbox/quickdraw/DrawLine.s"
  .include "original/toolbox/quickdraw/PutLine.s"
  .include "original/toolbox/quickdraw/Rects.s"
  .include "original/toolbox/quickdraw/BitBlt.s"
  .include "original/toolbox/quickdraw/RgnBlt.s"
  .include "original/toolbox/quickdraw/RRects.s"
  .include "original/toolbox/quickdraw/Ovals.s"
  .include "original/toolbox/quickdraw/PutOval.s"
  .include "original/toolbox/quickdraw/Arcs.s"
  .include "original/toolbox/quickdraw/DrawArc.s"
  .include "original/toolbox/quickdraw/Angles.s"
  .include "original/toolbox/quickdraw/Polygons.s"
  .include "original/toolbox/quickdraw/Regions.s"
  .include "original/toolbox/quickdraw/SeekRgn.s"
  .include "original/toolbox/quickdraw/RgnOp.s"
  .include "original/toolbox/quickdraw/SortPoints.s"
  .include "original/toolbox/quickdraw/PackRgn.s"
  .include "original/toolbox/quickdraw/PutRgn.s"
  .include "original/toolbox/quickdraw/Bitmaps.s"
  .include "original/toolbox/quickdraw/Stretch.s"
  .include "original/toolbox/quickdraw/Pictures.s"
  .include "original/toolbox/quickdraw/QuickGlue.s"
  .include "original/toolbox/font_mgr.s"
  .include "original/toolbox/toolbox_event.s"
  .include "original/toolbox/window_mgr.s"
  .include "original/toolbox/menu_mgr.s"
  .include "original/toolbox/control_mgr.s"
  .include "original/toolbox/resource_mgr.s"
  .include "original/toolbox/dialog_mgr.s"
  .include "original/toolbox/toolbox_utils.s"
  .include "original/toolbox/desk_mgr.s"
  .include "original/toolbox/get_mgr.s"
  .include "original/toolbox/textedit.s"
  .include "original/toolbox/scrap_mgr.s"
  .include "original/toolbox/package_mgr.s"
  .include "original/os/date_utils.s"
