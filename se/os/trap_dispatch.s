| A-line trap dispatcher -- ATRAP68020/68010, EMT1010, _SetTrapAddress, _GetTrapAddress
|
| Apple source: Dispatch.a (MacSEROM.lst module DSPATCH). Dispatches
| A-line instructions ($Axxx) to the OS or Toolbox trap handlers through
| the RAM dispatch tables that startup fills from os/dispatch_table.s:
| - OS traps ($A000-$A0FF): 256 entries at DispatchTab ($0400)
| - Toolbox traps ($A800-$A9FF): 512 entries at ToolTable ($0E00)
| Entries for the 68020 (ATRAP68020, which also flushes the instruction
| cache), the 68010 (ATRAP68010) and the 68000 (EMT1010) adjust the
| exception frame. Trap word: bit 11 = Toolbox; OS bit 8 = do not
| preserve A0; Toolbox bit 10 = auto-pop. _SetTrapAddress ($A047) and
| _GetTrapAddress ($A146) read and write the tables.
|
| References: Inside Macintosh Vol II, Ch 13 (The Trap Dispatcher)

| ATRAP68020 - A-line trap dispatcher (_Unimplemented handler shim)
|
| Adjusts stack frame and dispatches to the actual trap handler.
DSPATCH:                                        | Apple source module (MacSEROM.lst)
ATRAP68020:
    MOVE.L      0x2(A7),0x4(A7)                 | shift return address up (make room)
    MOVEM.L     D1-D2/A2,-(A7)                  | save work registers
| 68020+ cache flush: MOVEC CACR,D1 / BSET #3 / MOVEC D1,CACR
| Raw bytes because m68000 assembler cannot encode MOVEC.
    .byte 0x4E,0x7A,0x10,0x02                   | MOVEC CACR,D1 (read cache control)
    BSET        #0x3,D1                         | set bit 3: clear instruction cache
    .byte 0x4E,0x7B,0x10,0x02                   | MOVEC D1,CACR (flush I-cache)
    BRA.B       TRAP_DECODE                     | continue to common dispatch
| ATRAP68010 - A-line trap entry for 68010+ (different stack frame)
ATRAP68010:
    MOVE.L      0x2(A7),0x4(A7)                 | shift return addr (68010 frame format)
    BRA.B       TRAP_COMMON                     | join common path
| EMT1010 - 1010 emulator trap entry (F-line)
EMT1010:
    SUBQ.L      #0x2,A7                         | adjust stack for format difference
TRAP_COMMON:
    MOVEM.L     D1-D2/A2,-(A7)                  | save work registers
| Common A-line dispatch: fetch trap word, decode OS vs Toolbox
TRAP_DECODE:
    MOVEA.L     0x10(A7),A2                     | A2 = PC at trap instruction
    MOVE.W      (A2)+,D2                        | D2 = trap word, advance past it
    MOVE.L      A2,0x10(A7)                     | update return PC (skip trap word)
    MOVE.W      D2,D1                           | D1 = save full trap word for flags
    ANDI.W      #0x1FF,D2                       | D2 = trap number (bits 0-8)
    CMPI.W      #0xA800,D1                      | Toolbox trap? (bit 11 set = >= 0xA800)
    BCS.B       TRAP_OS_PATH                    | bit 11 clear: OS trap
| Toolbox trap dispatch: look up in ToolTable
    LEA.L       (ToolTable).W,A2                | A2 = Toolbox dispatch table
    LSL.W       #0x2,D2                         | D2 *= 4 (longword index)
    MOVE.L      0x0(A2,D2.W),0xC(A7)            | push handler addr onto stack frame
    CMPI.W      #0xAC00,D1                      | auto-pop trap? (bit 10 set)
    MOVEM.L     (A7)+,D1-D2/A2                  | restore work registers
    BCS.B       TRAP_TBOX_DISPATCH              | no auto-pop: dispatch via RTS
    MOVE.L      (A7)+,(A7)                      | auto-pop: remove extra frame entry
TRAP_TBOX_DISPATCH:
    RTS                                         | dispatch to Toolbox trap handler
| TRAP_OS_PATH - OS trap dispatch
|
| OS trap word bit 8: 0 = save/restore A0-A1, 1 = A0 returns result.
| Bits 0-7 = OS dispatch table index (256 entries).
TRAP_OS_PATH:
    LEA.L       (DispatchTab).W,A2              | A2 = OS dispatch table
    BCLR        #0x8,D2                         | bit 8 set? (result in A0)
    BNE.B       TRAP_OS_NOSAVEREG               | yes: don't save A0
    LSL.W       #0x2,D2                         | D2 *= 4 (longword index)
    MOVEA.L     0x0(A2,D2.W),A2                 | A2 = handler address
    MOVEM.L     A0-A1,-(A7)                     | save A0-A1 (will restore after)
    JSR         (A2)                            | call OS trap handler
    MOVEM.L     (A7)+,A0-A1                     | restore A0-A1
TRAP_OS_RETURN:
    MOVEM.L     (A7)+,D1-D2/A2                  | restore work registers
    ADDQ.W      #0x4,A7                         | pop saved frame entry
    TST.W       D0                              | set CCR from result (D0)
    RTS                                         | return from TRAP_OS_RETURN
| TRAP_OS_NOSAVEREG - OS trap bit 8 set (A0 returns result)
|
| Only A1 saved; A0 passes through to return handle/pointer.
TRAP_OS_NOSAVEREG:
    LSL.W       #0x2,D2                         | D2 *= 4 (longword index)
    MOVEA.L     0x0(A2,D2.W),A2                 | A2 = handler address
    MOVE.L      A1,-(A7)                        | save A1 only
    JSR         (A2)                            | call OS trap handler
    MOVEA.L     (A7)+,A1                        | restore A1 (A0 = result)
    BRA.B       TRAP_OS_RETURN                  | return with result in A0
| SETTRAPADDRESS - _SetTrapAddress trap handler
|
| Sets the dispatch table entry for trap D0 to address A0.
| D1 bit 9: new-style (explicit OS/Toolbox select)
| D1 bit 10: 1 = Toolbox table, 0 = OS table
| Entry: D0 = trap number, A0 = new handler address
SETTRAPADDRESS:
    BTST        #0x9,D1                         | new-style call? (bit 9)
    BEQ.B       SET_TRAP_OLD                    | no: auto-detect OS vs Toolbox
    ANDI.W      #0x1FF,D0                       | D0 = 9-bit trap number
    LEA.L       (ToolTable).W,A1                | default: Toolbox table
    BTST        #0xA,D1                         | explicitly Toolbox? (bit 10)
    BNE.B       SET_TRAP_STORE                  | yes: use ToolTable
    ANDI.W      #0xFF,D0                        | OS: mask to 8-bit index
    LEA.L       (DispatchTab).W,A1              | use OS dispatch table
SET_TRAP_STORE:
    LSL.W       #0x2,D0                         | D0 *= 4 (longword index)
    MOVE.L      A0,0x0(A1,D0.W)                 | store handler address in table
    MOVEQ.L     #0x0,D0                         | D0 = noErr
    RTS                                         | return from SetTrapAddress
| Old-style SetTrapAddress: auto-detect OS vs Toolbox
SET_TRAP_OLD:
    BSR.B       DETECT_TRAP_TABLE               | detect which table to use
    BRA.B       SET_TRAP_STORE                  | store handler
| DETECT_TRAP_TABLE - auto-detect OS vs Toolbox table for a trap number
|
| Traps 0x00-0x4F and 0x54 and 0x57 are OS traps (DispatchTab).
| All others default to Toolbox (ToolTable).
| Entry: D0 = trap number (will be masked to 9 bits)
| Exit: A1 = correct dispatch table, D0 = masked trap number
DETECT_TRAP_TABLE:
    ANDI.W      #0x1FF,D0                       | mask to 9-bit number
    LEA.L       (ToolTable).W,A1                | default: Toolbox table
    CMPI.W      #0x57,D0                        | above HFS trap range?
    BHI.B       DETECT_DONE                     | yes: Toolbox
    BEQ.B       DETECT_OS_TABLE                 | 0x57: OS (_HFSDispatch)
    CMPI.W      #0x4F,D0                        | in base OS range? (0x00-0x4F)
    BLS.B       DETECT_OS_TABLE                 | yes: OS table
    CMPI.W      #0x54,D0                        | 0x54? (high OS trap)
    BNE.B       DETECT_DONE                     | no: Toolbox
DETECT_OS_TABLE:
    LEA.L       (DispatchTab).W,A1              | use OS dispatch table
DETECT_DONE:
    RTS                                         | return with A1 = table
| GET_TRAP_OLD - old-style GetTrapAddress (auto-detect table)
GET_TRAP_OLD:
    BSR.B       DETECT_TRAP_TABLE               | detect OS vs Toolbox table
    BRA.B       GET_TRAP_READ                   | read and return address
| GETTRAPADDRESS - _GetTrapAddress trap handler
|
| Returns the dispatch table entry for trap D0 in A0.
| D1 bit 9: new-style, D1 bit 10: 1 = Toolbox, 0 = OS
| Entry: D0 = trap number
| Exit: A0 = handler address
GETTRAPADDRESS:
    BTST        #0x9,D1                         | new-style call? (bit 9)
    BEQ.B       GET_TRAP_OLD                    | no: auto-detect table
    ANDI.W      #0x1FF,D0                       | D0 = 9-bit trap number
    LEA.L       (ToolTable).W,A1                | default: Toolbox table
    BTST        #0xA,D1                         | explicitly Toolbox? (bit 10)
    BNE.B       GET_TRAP_READ                   | yes: read from ToolTable
    ANDI.W      #0xFF,D0                        | OS: mask to 8-bit index
    LEA.L       (DispatchTab).W,A1              | use OS dispatch table
GET_TRAP_READ:
    LSL.W       #0x2,D0                         | D0 *= 4 (longword index)
    MOVEA.L     0x0(A1,D0.W),A0                 | A0 = handler address from table
    MOVEQ.L     #0x0,D0                         | D0 = noErr
    RTS                                         | return from GetTrapAddress
