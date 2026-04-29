| Boot-time I/O Manager Install (SCC reset, jump-table setup, driver install)
|
| Reached from vectors.s:InitIOMgr-caller during the boot sequence, after
| memory test and hardware setup but before the full OS is initialized.
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
|
| Mirrors the layout of src/original/boot/boot_install.s from the 128K/512K
| ROM (which holds the smaller, classic-era variant of the same routines).
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
