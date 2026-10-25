| Boot-time I/O setup: SCC reset, jump-table setup, driver install
|
| Called from the startup code in vectors.s, after the memory test and
| the hardware setup, before the managers are initialized.
|
| Contents, in ROM order:
| DT_SCC_INIT_DATA   - SCC register/value pairs for both channels
| InitSCC            - reset both SCC channels and stream the register table
| SCC_WRITE_REGS/LOOP - register write with settling delay
| JmpTblInit / L_mJmpTbl2 - expand a ROM-relative offset table into
|                      absolute jump vectors (JFetch/JStash/JIODone)
| DRVR_INSTALL_TABLE - JMP table to the ROM drivers (.Sound, .Sony,
|                      .AIn, .AOut, .BIn, .BOut)
| InitIOMgr          - allocate the 32-slot unit table, then _DrvrInstall
|                      and _Status for each of the six ROM drivers, and
|                      _Open for .Sound and .Sony (units 3 and 4; the
|                      serial drivers stay closed until a program opens them)
| The Mac Plus has the same code at the start of its boot_install.s.
|
| References: Inside Macintosh II, Ch 6 (Device Manager, driver install).

| DT_SCC_INIT_DATA - SCC initialization register data ($059A, 32 bytes)
| Written sequentially to SCC write control register as (reg#,value)
| pairs. Each byte pair: first selects the WR register, second is the
| value to latch. Reset sequence for both channels.

| DT_SCC_INIT_DATA - SCC initialization register data (17 bytes per channel)
| Written sequentially to SCC write control register to reset and
| configure each channel. Values are SCC register address/data pairs.
DT_SCC_INIT_DATA:
| SCC init data: 16 (register, value) byte pairs written sequentially
| to the SCC write-control register to reset + configure both channels.
        .byte   0x09, 0x40                      | WR9 = 0x40: reset channel B
        .byte   0x04, 0x4C                      | WR4 = 0x4C: x16 clock, 1 stop, odd parity
        .byte   0x02, 0x00                      | WR2 = 0x00: interrupt vector base
        .byte   0x03, 0xC0                      | WR3 = 0xC0: Rx 8-bit/char, disabled
        .byte   0x0F, 0x08                      | WR15 = 0x08: DCD ext/status IE
        .byte   0x00, 0x10                      | WR0 = 0x10: reset ext/status
        .byte   0x00, 0x10                      | WR0 = 0x10: second reset (per spec)
        .byte   0x01, 0x01                      | WR1 = 0x01: Ext/Status IE
        .byte   0x09, 0x80                      | WR9 = 0x80: reset channel A
        .byte   0x04, 0x4C                      | WR4 = 0x4C: ch A timing (same as B)
        .byte   0x03, 0xC0                      | WR3 = 0xC0: ch A Rx 8-bit, disabled
        .byte   0x0F, 0x08                      | WR15 = 0x08: DCD ext/status IE
        .byte   0x00, 0x10                      | WR0 = 0x10: reset ext/status
        .byte   0x00, 0x10                      | WR0 = 0x10: second reset
        .byte   0x01, 0x01                      | WR1 = 0x01: Ext/Status IE
        .byte   0x09, 0x0A                      | WR9 = 0x0A: master IE, no-vector, RTS
| InitSCC - SCC reset and write-register init (drives the SCC_INIT_DATA above)
InitSCC:
        MOVE.L  #0xBFFFF9,A0                    | absolute-long addressing
        MOVE.L  #0x9FFFF8,A1                    | absolute-long addressing
        MOVE.L  A0,(SCCWr).w                    | Store SCC write base in low-mem
        MOVE.L  A1,(SCCRd).w                    | Store SCC read base in low-mem
        LEA     DT_SCC_INIT_DATA(PC),A2         | A2 = SCC init register data
| ----------------------------------------------------------
| InitSCC (continuation) -- this is the latter half of InitSCC; the
| prologue (MOVE.L of SCC_WrCtlB/SCC_RdCtlB, storing into SCCWr/SCCRd,
| and LEA of DT_SCC_INIT_DATA) lives at the tail of vectors.s
| (classic packaged the data table and its driver together at the end
| of vectors.s and the stream-writer here). Entered with A0 = SCC
| channel-B write control, A1 = SCC channel-B read control, A2 =
| DT_SCC_INIT_DATA. Drives two passes of SCC_WRITE_LOOP (one per
| channel).

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
| DRVR_INSTALL_TABLE -- 5-entry device-manager jump table (file I/O dispatch)
| Each word here is a ROM-relative offset that JmpTblInit expands into
| an absolute JMP target. These vectors are called via JFetch/JStash/
| JIODone (from low-memory) during driver I/O.
DRVR_INSTALL_TABLE:
        JMP     DRVR_Sound(PC)                  | .Sound DRVR header (install target)
        JMP     DRVR_Sony(PC)                   | .Sony DRVR header (install target)
        JMP     Driver_AIn(PC)                  | JMP into .AIn DRVR header area @ $2552
        JMP     Driver_AOut(PC)                 | JMP into .AOut DRVR header area @ $256A
        JMP     Driver_BIn(PC)                  | JMP into .BIn DRVR header area @ $2582
        JMP     Driver_BOut(PC)                 | JMP into .BOut DRVR header area @ $259A

| ----------------------------------------------------------
| InitIOMgr -- allocate Unit Table and install .Sony/.Sound drivers
| Classic 1984 version: smaller unit table (32 entries, not Plus's 48)
| and no SCSI reset. Loops over the 6-entry descriptor array at A2
| (DRVR_INSTALL_TABLE: .Sound, .Sony, .AIn, .AOut, .BIn, .BOut = units
| 3-8) to issue _DrvrInstall + _Status for each ROM driver, and _Open
| for units 3 and 4 only.
InitIOMgr:
        MOVEQ.L #0x20,D0                        | D0 = 32 (Unit Table entries)
        MOVE    D0,(UnitTableEntryCount).w      | Store unit table entry count
        ASL.L   #0x2,D0                         | D0 = 32 * 4 = 128 bytes
        _NewPtrSysClear                         | Allocate cleared block for Unit Table
        MOVE.L  A0,(UTableBase).w               | Store Unit Table base address
        LEA     DRVR_INSTALL_TABLE(PC),A2       | A2 = driver-descriptor array base
        MOVEQ.L #0x5,D1                         | D1 = 5: six drivers (DBRA count)
        MOVEQ.L #0x3,D7                         | D7 = unit number, from 3 (.Sound)
INITIOMGR_LOOP:                                 | driver-install loop top
        ADDQ.W  #0x2,A2                         | Skip leading word of descriptor
        MOVE.L  A2,A1                           | A1 = descriptor pointer (mutable copy)
        MOVEQ.L #0x0,D0                         | clear D0 high half
        MOVE    (A2)+,D0                        | D0 = offset to this driver's entry
        ADDA.L  D0,A1                           | A1 = absolute driver-entry address
        MOVE    D7,D0                           | D0 = unit-number index
        NOT     D0                              | D0 = ~D0 (invert: refNum = -(unit+1))
        SUBA.W  #0x32,SP                        | Allocate IOParam block (50 bytes) on stack
        MOVE    D0,ioRefNum(SP)                 | set refNum in IOParam
        _DrvrInstall                            | install driver into Unit Table
        MOVE    #0x1,csCode(SP)                 | csCode = 1 (GetDrvStatus)
        MOVE.L  SP,A0                           | A0 = IOParam block
        _Status                                 | query driver status (wakes the driver)
        MOVEA.L csParam(A0),A3                  | A3 = DCE handle (returned by _Status csCode=1 in csParam)
        MOVEA.L (A3),A3                         | A3 = deref'd DCE ptr
        MOVE.L  A1,(A3)+                        | install driver entry pointer
        CLR     (A3)                            | zero next descriptor word
        MOVE.B  (A1),(A3)                       | copy driver-flags byte into queue entry
        CMPI    #0x5,D7                         | unit >= 5 (serial driver)?
        BCC.B   INITIOMGR_NEXT                  | yes: install only, do not open
        LEA.L     18(A1),A1                     | A1 = driver's name-Pstring field (offset +18)
        MOVE.L  A1,ioFileName(SP)               | set ioFileName in IOParam block
        CLR.B   ioPermssn(SP)                   | ioPermssn = 0 (default permission)
        MOVE.L  SP,A0                           | A0 = IOParam block
        _Open                                   | open driver by Pascal name at A1
INITIOMGR_NEXT:
        ADDA.W  #0x32,SP                        | tear down 50-byte IOParam on stack
        ADDQ.W  #0x1,D7                         | advance to next unit number
        DBRA    D1,INITIOMGR_LOOP               | loop through driver descriptors
        RTS                                     | return from InitIOMgr (all ROM drivers installed)
