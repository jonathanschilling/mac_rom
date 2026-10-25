| Boot-time I/O and manager setup (SCC reset, jump-table setup, driver install, GNEFilter, system zone)
|
| Corresponds to the end of Apple's StartInit.a (the SE link map's
| INITSCC ... INITMEMMGR). Reached from the startup sequence in vectors.s
| after the memory test and hardware setup.
|
| Contents:
| DT_SCC_INIT_DATA - SCC channel-init register table (17 bytes per channel)
| InitSCC - reset both SCC channels, stream register writes
| SCC_WRITE_REGS/LOOP- register write with settling delay
| JmpTblInit / L_mJmpTbl2 - expand ROM-relative offset table into absolute
| jump vectors (JFetch/JStash/JIODone)
| DT_SONY_NAME / DT_SOUND_NAME - Pascal-string driver names
| InitIOMgr - allocate 48-slot Unit Table, _Open .Sony + .Sound,
| issue SCSI reset (v1/v2 inline vs v3 patch jump),
| load and run the 'SERD' serial-driver resource.
| P_mGNEFilter - the GetNextEvent filter (JGNEFilter: alarm flash in the
| menu bar)
| DT_INITZONE_PARAMS / INIT_SYS_ZONE / REINIT_SYS_ZONE - system heap
| (SysZone) initialization
|
| The 128K/512K ROM has the SCC, jump-table and driver part in its
| boot_install.s too.
|
| Called once during boot, never again.
| References: Inside Macintosh II, Ch 6 (Device Manager, driver install).

| DT_SCC_INIT_DATA - SCC initialization register data (17 bytes per channel)
| Written sequentially to SCC write control register to reset and
| configure each channel. Values are SCC register address/data pairs.
DT_SCC_INIT_DATA:
  .byte 0x09,0x40,0x04,0x4C,0x02,0x00           | WR9=0x40 (reset ch B), WR4=0x4C (x16,1stop)
  .byte 0x03,0xC0,0x0F,0x08,0x00,0x10           | WR3=0xC0 (Rx 8bit), WR15=0x08 (DCD IE)
  .byte 0x00,0x10,0x01,0x01,0x09,0x80           | WR0=reset ext, WR0=reset ext, WR1=0x01, WR9=0x80
  .byte 0x04,0x4C,0x03,0xC0,0x0F,0x08           | WR4=0x4C (ch A), WR3=0xC0, WR15=0x08
  .byte 0x00,0x10,0x00,0x10,0x01,0x01           | WR0=reset ext, WR0=reset ext, WR1=0x01
  .byte 0x09,0x0A                               | WR9=0x0A (MIE+NV, master int enable)

| === InitSCC - reset and configure the Zilog 8530 SCC ===
| Writes 17 register bytes from DT_SCC_INIT_DATA to each channel (B then A).
| Configures: async mode, 8-bit data, 1 stop bit, no parity,
| external/status interrupts enabled (for mouse DCD tracking).
InitSCC:
        MOVE.L  #SCC_WrCtlB,A0                  | A0 = SCC write channel B
        MOVE.L  #SCC_RdCtlB,A1                  | A1 = SCC read channel B
        MOVE.L  A0,(SCCWr).w                    | Store SCC write base in low-mem
        MOVE.L  A1,(SCCRd).w                    | Store SCC read base in low-mem
        LEA.L   DT_SCC_INIT_DATA(PC),A2         | A2 = SCC init register data
        MOVEQ.L #0x10,D1                        | 17 bytes to write (channel B)
        BSR.B   SCC_WRITE_REGS                  | Write DT_SCC_INIT_DATA data to channel B
        ADDQ.L  #0x2,A0                         | Advance to channel A write
        ADDQ.L  #0x2,A1                         | Advance to channel A read
        MOVEQ.L #0x10,D1                        | 17 bytes again (channel A)
| SCC_WRITE_REGS - write D1+1 bytes from (A2) to SCC write register (A0)
| Includes delay loops (MOVE.L (SP),(SP)) for SCC register settling time.
SCC_WRITE_REGS:
        MOVE.B  (A1),D2                         | Dummy read to reset SCC register pointer
        BRA.B   SCC_WRITE_ENTER                 | Enter loop
| SCC_WRITE_LOOP - SCC register write loop with settling delay
| Called during boot.
SCC_WRITE_LOOP:
        MOVE.L  (SP),(SP)                       | stall 1 (bus-settling no-op)
        MOVE.L  (SP),(SP)                       | stall 2 (SCC needs ~500ns idle)
        MOVE.B  (A2)+,(A0)                      | write next (reg#/value) byte to SCC
| SCC register write loop
SCC_WRITE_ENTER:
        DBF     D1,SCC_WRITE_LOOP               | Loop for all register bytes
        RTS                                     | Return from SCC_WRITE_REGS (SCC register write)

| === JmpTblInit - convert PC-relative offset table to absolute addresses ===
| A0 = source table (word offsets relative to table start)
| A1 = destination (longword addresses to fill)
| D1 = number of entries - 1
| Called during boot.
JmpTblInit:
        MOVE.L  A0,D0                           | D0 = table base address
| Offset-to-address conversion loop
L_mJmpTbl2:
        MOVEQ.L #0x0,D2                         | Clear D2 high word
        MOVE    (A0)+,D2                        | D2 = word offset from table base
        ADD.L   D0,D2                           | D2 = absolute address (base + offset)
        MOVE.L  D2,(A1)+                        | Store absolute address in dest table
        DBF     D1,L_mJmpTbl2                   | Loop for all entries
        RTS                                     | Return from JmpTblInit

| ----------------------------------------------------------
|
| DT_SONY_NAME - Pascal string ".Sony" - Sony disk driver name
|
DT_SONY_NAME:
  .byte 0x05                                    | Pascal string length
  .ascii ".Sony"                                | floppy disk driver name

| Pascal string: ".Sound" driver name
DT_SOUND_NAME:
  .byte 0x06                                    | Pascal string length
  .ascii ".Sound "                              | sound driver name (padded to even)

| Allocate Unit Table, open .Sony/.Sound, load SERD
InitIOMgr:
        MOVEQ.L #0x30,D0                        | D0 = 48 (unit table entries)
        MOVE    D0,(UnitTableEntryCount).w      | Store unit table entry count
        ASL.L   #0x2,D0                         | D0 = 48 * 4 = 192 bytes for Unit Table
| Allocate and store the Unit Table (device driver table).
        _NewPtrSysClear                         | Allocate cleared block for Unit Table
        MOVE.L  A0,(UTableBase).w               | Store Unit Table base address
| Open the two essential ROM drivers using parameter block on stack.
        SUBA    #0x32,SP                        | Allocate IOParam block (50 bytes) on stack
        MOVE.L  A7,A0                           | A0 = IOParam block
        CLR.B   ioPermssn(A0)                   | Permission = 0 (default)
| Open the .Sony disk driver (DRVR 4)
        LEA.L   DT_SONY_NAME(PC),A1             | A1 -> Pascal string "\x05.Sony"
        MOVE.L  A1,ioFileName(A0)               | Set driver name in param block
        _Open                                   | Open .Sony disk driver
| Open the .Sound driver (DRVR 3)
        LEA.L   DT_SOUND_NAME(PC),A1            | A1 -> Pascal string "\x06.Sound "
        MOVE.L  A1,ioFileName(A0)               | Set driver name in param block
        _Open                                   | Open .Sound driver
        ADDA    #0x32,SP                        | Free IOParam block from stack
| --- ROM-variant difference @ $08AC ---
| v1/v2: inline SCSI reset here (CLR SCSIDrvrs; BSR.W CheckSCSI) -- 8 bytes.
| v3: the same 8 bytes became a JSR into the extra-area SCSI patch,
| which performs the CLR, dispatches _SCSIReset, and then JMPs to
| CheckSCSI (see src/extra/extra.s: EXTRA_CONT).
| Reason: v3 factored the SCSI reset out of InitIOMgr into the 16-byte
| subroutine at ROM $1FFC0 so the reset can be invoked from
| multiple sites (it replaces another inline copy inside
| CheckSCSI -- see file_mgr_cache.s).
.if ROM_TARGET < MAC_PLUS_V3
        CLR.W   (SCSIDrvrs).w                   | Plus v1/v2: clear SCSI driver count
        JSR     CheckSCSI(PC)                   | Plus v1/v2: probe SCSI bus inline
.else
        JSR     (0x41FFC0).l                    | Plus v3: SCSI patch entry (extra.s: EXTRA_CONT)
        NOP                                     | Plus v3: pad to 8 bytes
.endif
| Load and execute the serial driver resource ('SERD' 0)
| This installs the .AIn/.AOut/.BIn/.BOut serial port drivers.
        SUBQ.W  #0x4,SP                         | Make room for Handle result
        MOVE.L  #0x53455244,-(SP)               | Push resource type 'SERD'
        CLR     -(SP)                           | Push resource ID 0
        MOVE    #-0x1,(ROMMapInsert).w          | Force search ROM resource map
        _GetResource                            | Load SERD 0 resource
        MOVE.L  (SP)+,D0                        | D0 = handle (or nil)
        BEQ.B   INIT_IOMGR_DONE                 | Not found: skip serial driver init
        MOVE.L  D0,A0                           | A0 = handle
        MOVE.L  (A0),A0                         | A0 = dereference -> code ptr
        JSR     (A0)                            | Execute SERD init (installs 4 serial drivers)
| Return from InitIOMgr
INIT_IOMGR_DONE:
        RTS                                     | Return from InitIOMgr
| ----------------------------------------------------------
|
| P_m GNE Filter
|
| Called during boot (3,695 times in 30s trace).
P_mGNEFilter:
        LEA.L   (AlarmState).w,A1               | A1 = AlarmState low-memory address
        BSET    #0x5,(A1)                       | Set 'GNE filter ran' bit
        BNE.B   GNE_FILTER_DONE                 | Already set: skip alarm check
        MOVEQ.L #0x3,D0                         | D0 = alarm mask (bits 0-1)
        AND.B   (A1),D0                         | Check if alarm is armed/active
        BNE.B   GNE_FILTER_DONE                 | Alarm not ready: skip
        TST.B   (WWExist).w                     | Window Manager initialized?
        BNE.B   GNE_FILTER_DONE                 | Not yet: skip alarm display
        MOVE.L  (MenuList).w,D0                 | D0 = MenuList handle
        BEQ.B   GNE_FILTER_DONE                 | No menus: skip alarm display
        MOVE.L  D0,A0                           | A0 = deref MenuList handle
        MOVE.L  (A0),A0                         | A0 = deref again (master ptr)
        TST     (A0)                            | Any menus in menu bar?
        BLE.B   GNE_FILTER_DONE                 | No menus: skip
        MOVE.L  0x6(A0),A0                      | A0 = first menu handle
        MOVE.L  (A0),A0                         | A0 = deref menu handle
        CMPI    #0x114,0xE(A0)                  | Apple menu width = 0x114 (276 pixels)?
        BNE.B   GNE_FILTER_DONE                 | Wrong width: skip alarm flash
        MOVE.L  #0x10011,-(SP)                  | Push shield rect top-left (1,17)
        MOVE.L  #0x13001E,-(SP)                 | Push shield rect bot-right (19,30)
| Flash the Apple menu bar area (alarm indicator) by XORing scanlines.
| A1 = AlarmState low-memory address (set by caller).
        MOVE.L  (JShieldCursor).w,A0            | Shield cursor from drawing
        JSR     (A0)                            | Call JShieldCursor
        MOVE.L  (ScrnBase).w,A0                 | A0 = screen base
        MOVE    (ScreenRow).w,D0                | D0 = 64 (bytes per scanline)
        MOVE.L  #0x7FFC,D1                      | XOR mask: flip bits 2-14 of first long
        MOVEQ.L #0x11,D2                        | 18 scanlines (menu bar height)
| XOR Apple menu area (alarm flash)
ALARM_FLASH_LOOP:
        ADDA    D0,A0                           | Advance to next scanline
        EOR.L   D1,(A0)                         | XOR first 4 bytes (Apple logo area)
        DBF     D2,ALARM_FLASH_LOOP             | Loop 18 scanlines
        MOVE.L  (JShowCursor).w,A0              | Restore cursor
        JSR     (A0)                            | Call JShowCursor
        BCHG    #0x7,(A1)                       | Toggle alarm flash state
        BCLR    #0x6,(A1)                       | Clear "alarm triggered" bit
        BEQ.B   GNE_FILTER_DONE                 | Not triggered: return quietly
        MOVE    #0x8,-(SP)                      | Push duration = 8
        _SysBeep                                | Sound the alarm beep
| Return from GNEFilter
GNE_FILTER_DONE:
        RTS                                     | Return from GNEFilter

| DT_INITZONE_PARAMS - InitZone parameter block (28 bytes)
| Configures the initial system heap zone: start, limit, grow proc, master count.
| Fields: Lo3Bytes mask, startPtr, limitPtr, cMoreMasters, pGrowZone, etc.
DT_INITZONE_PARAMS:
  .byte 0x00,0xFF,0xFF,0xFF,0x00,0x00           | Lo3Bytes mask (0x00FFFFFF), startPtr hi
  .byte 0x04,0x00,0x00,0x00,0x20,0x00           | startPtr=0x0400, limitPtr hi=0x0000, lo=0x2000
  .byte 0x00,0x00,0x00,0x00,0x14,0x00           | cMoreMasters=0, pGrowZone=0, cbMasters=20
  .byte 0x00,0x00,0x4E,0x00,0x00,0x20           | reserved, flags=0x4E00, heap ID=0x0020
  .byte 0x00,0x00,0x00,0x00                     | reserved (28 bytes total)

| INIT_SYS_ZONE - initialize system heap zone from DT_INITZONE_PARAMS parameters
| Copies DT_INITZONE_PARAMS data to low-memory zone config area, then calls _InitZone.
INIT_SYS_ZONE:
        LEA.L   DT_INITZONE_PARAMS(PC),A0       | A0 = InitZone parameter template
        LEA.L   (Lo3Bytes).w,A1                 | A1 = destination (low-mem config area)
        MOVEQ.L #0x6,D0                         | Copy 7 words (14 bytes)
| Copy InitZone parameter words
COPY_ZONE_PARAMS:
        MOVE    (A0)+,(A1)+                     | Copy parameter word
        DBF     D0,COPY_ZONE_PARAMS             | Copy next parameter word
        _InitZone                               | Create the system heap zone
        MOVE.L  (TheZone).w,(SysZone).w         | SysZone = newly created system zone
        RTS                                     | Return from INIT_SYS_ZONE (zone init)

| REINIT_SYS_ZONE - alternate zone init entry (used during warm restart)
REINIT_SYS_ZONE:
        _InitZone                               | Re-create system heap zone
        MOVE.L  (TheZone).w,(SysZone).w         | Update SysZone pointer
        RTS                                     | Return from REINIT_SYS_ZONE (zone re-init)

