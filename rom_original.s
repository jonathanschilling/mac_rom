| Macintosh 128K / 512K ROM master file (64 KB, 1984)
| Entry point for both mac_128k and mac_512k builds. Selects between
| the two variants via the ROM_TARGET preprocessor flag:
| --defsym ROM_TARGET=1 -> MAC_128K (1984-01, checksum $28BA61CE)
| --defsym ROM_TARGET=2 -> MAC_512K (1984-10, checksum $28BA4E50)
| All 57 bytes that differ between 128K and 512K live inline in the
| subsystem files via `.if ROM_TARGET == MAC_128K / .else / .endif`
| blocks:
| $0002 boot/vectors.s ROM checksum low word
| $1CA6 resources/res_drvr_sony.s Sony sector-retry branch
| $1D8A resources/res_drvr_sony.s IWM valid-bits mask (31 -> 63)
| $1D9C resources/res_drvr_sony.s BEQ.B displacement shift
| $1DA2 resources/res_drvr_sony.s extra mask reload + shifted consts
| $5040 hw/rtc.s IPL mask 1 -> 3
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
  .include "original/hw/queue.s"
  .include "original/hw/interrupts.s"
  .include "original/os/device_mgr.s"
  .include "original/resources/res_drvr_sony.s"
  .include "original/resources/res_drvr_scc.s"
  .include "original/os/memory_mgr.s"
  .include "original/resources/res_drvr_sound.s"
  .include "original/os/file_mgr.s"
  .include "original/os/file_mgr_io.s"
  .include "original/toolbox/segment_loader.s"
  .include "original/toolbox/os_utilities.s"
  .include "original/hw/rtc.s"
  .include "original/os/dispatch_override.s"
  .include "original/toolbox/quickdraw/Util.s"
  .include "original/toolbox/quickdraw/GrafAsm.s"
  .include "original/toolbox/quickdraw/Text.s"
  .include "original/toolbox/quickdraw/DrawText.s"
  .include "original/toolbox/quickdraw/DrawLine.s"
  .include "original/toolbox/quickdraw/Rects.s"
  .include "original/toolbox/quickdraw/BitBlt.s"
  .include "original/toolbox/quickdraw/RgnBlt.s"
  .include "original/toolbox/quickdraw/DrawArc.s"
  .include "original/toolbox/quickdraw/Regions.s"
  .include "original/toolbox/quickdraw/Bitmaps.s"
  .include "original/toolbox/quickdraw/Stretch.s"
  .include "original/toolbox/quickdraw/Pictures.s"
  .include "original/toolbox/font_mgr.s"
  .include "original/toolbox/toolbox_event.s"
  .include "original/toolbox/window_mgr.s"
  .include "original/toolbox/menu_mgr.s"
  .include "original/toolbox/control_mgr.s"
  .include "original/toolbox/resource_mgr.s"
  .include "original/toolbox/dialog_mgr.s"
  .include "original/toolbox/textedit.s"
  .include "original/toolbox/package_mgr.s"
