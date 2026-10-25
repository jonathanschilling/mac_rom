| A-line trap dispatcher -- EMT1010, _GetTrapAddress, _SetTrapAddress
|
| Apple source: Dispatch.a (MacSEROM.lst module DSPATCH). The 68000 Line
| 1010 Emulator exception handler dispatches A-line instructions ($Axxx)
| to the trap handlers through the RAM dispatch table DispatchTab ($0400,
| 512 word entries shared by OS and Toolbox traps in the 64K ROM: entry
| = handler offset / 2, with bit 15 set for a RAM address), which startup
| fills from os/dispatch_table.s. GetTrapAddress and SetTrapAddress read
| and write that table.
|
| References: Inside Macintosh Vol II, Ch 13: The Trap Dispatcher

| ----------------------------------------------------------
| EMT1010_TrapDispatch -- 68000 Line 1010 Emulator (A-trap dispatcher)
| Installed as the line-1010 exception vector ($28). Every A-line
| instruction ($Axxx) traps here. The 68000 frame is SR (word) +
| PC (long). The trap word $Axxx is fetched from the saved PC; we
| then split into OS-trap path (D2 < $A800) and Toolbox path
| (D2 >= $A800). For Toolbox traps, bit 10 = "auto-pop" (caller
| pre-popped its own return address; we collapse the stack).
| Layout matches Plus's src/plus/os/trap_dispatch.s but classic
| has no 68020 frame-fixup (Mac 128K/512K never shipped with
| anything but a 68000).
EMT1010_TrapDispatch:                           | A-trap dispatch entry
        SUBQ.L  #0x2,SP                         | reserve a stack slot for handler addr
        MOVEM.L D1-D2/A2,-(SP)                  | save dispatcher's working regs
        MOVE.L  16(SP),A2                       | A2 = saved PC from exception frame
        MOVE    (A2)+,D2                        | D2 = trap word ($Axxx); advance PC
        MOVE.L  A2,16(SP)                       | store updated return PC back to frame
        MOVE    D2,D1                           | D1 = copy of trap word (for OS handler)
        CMPI    #-0x5800,D2                     | test bit 11: $A800 unsigned (-0x5800 sign)
        BCS.B   TRAP_OS_PATH                    | bit 11 = 0: OS trap (-> $1064)
        BSR.B   TRAP_RESOLVE_HANDLER            | Toolbox: resolve handler addr
        MOVE.L  D2,12(SP)                       | store handler addr in reserved slot
        CMPI    #-0x5400,D1                     | test bit 10: $AC00 unsigned (auto-pop)
        MOVEM.L (SP)+,D1-D2/A2                  | restore work regs
        BCS.B   TRAP_TBOX_DISPATCH              | bit 10 = 0: normal Toolbox dispatch
        MOVE.L  (SP)+,(SP)                      | auto-pop: discard glue retaddr
TRAP_TBOX_DISPATCH:
        RTS                                     | jump to handler via stack slot
| ----------------------------------------------------------
| TRAP_RESOLVE_HANDLER -- convert 9-bit trap index in D2 to absolute
| handler address. Looks up DispatchTab[D2*2], unpacks the compressed
| ROM-relative or RAM-relative offset, returns absolute addr in D2.
TRAP_RESOLVE_HANDLER:
        ANDI    #0x1FF,D2                       | mask to 9-bit trap number
        EXT.L    D2                             | sign-extend to 32 bits
        ADD     D2,D2                           | *2 (word index into DispatchTab)
        LEA.L     (DispatchTab).w,A2            | A2 = dispatch table base
        MOVE    0(A2,D2.W),D2                   | D2 = packed offset entry
        ADD     D2,D2                           | shift LSB to carry: 0=ROM, 1=RAM
        BCS.B   TRAP_RESOLVE_RAM                | RAM-resident handler -> rebase
        ADD.L   (ROMBase).w,D2                  | ROM handler: D2 = ROMBase + offset
        RTS                                     | return with absolute ROM handler in D2
TRAP_RESOLVE_RAM:
        ADD.L   (RAMBase).w,D2                  | RAM handler: D2 = RAMBase + offset
        RTS                                     | return with absolute RAM handler in D2

| ----------------------------------------------------------
| TRAP_OS_PATH -- OS trap (low 256 entries of dispatch table).
| Bit 8 of trap word: 0 = save+restore A0 across handler call,
| 1 = handler returns result in A0 (no save).
TRAP_OS_PATH:
        BCLR    #0x8,D2                         | test+clear bit 8 (save-A0 flag)
        BNE.B   TRAP_OS_NOSAVEREG               | bit 8 was set: don't save A0
        BSR.B   TRAP_RESOLVE_HANDLER            | resolve OS handler addr
        MOVE.L  D2,A2                           | A2 = handler entry
        MOVEM.L A0-A1,-(SP)                     | save A0+A1 (A0 will be restored)
        JSR     (A2)                            | call OS handler
        MOVEM.L (SP)+,A0-A1                     | restore A0+A1 (A0 preserved)
TRAP_OS_RETURN:                                 | shared epilogue
        MOVEM.L (SP)+,D1-D2/A2                  | restore dispatcher work regs
        ADDQ.W  #0x4,SP                         | discard the reserved handler-addr slot
        TST     D0                              | set CCR from handler's result code
        RTS                                     | return past the trap word
TRAP_OS_NOSAVEREG:                              | bit 8 = 1 path (A0 = result)
        BSR.B   TRAP_RESOLVE_HANDLER            | resolve handler addr
        MOVE.L  D2,A2                           | A2 = handler entry
        MOVE.L  A1,-(SP)                        | save A1 only (A0 carries result back)
        JSR     (A2)                            | call OS handler
        MOVE.L  (SP)+,A1                        | restore A1
        BRA.B   TRAP_OS_RETURN                  | rejoin common epilogue
| ----------------------------------------------------------
| GetTrapAddress -- returns dispatch handler addr for trap word in D0.
| Used by patches to chain into the original implementation. Calls
| TRAP_RESOLVE_HANDLER and returns the resolved address in A0.
GetTrapAddress:
        MOVE.L  A2,-(SP)                        | save A2
        MOVE    D0,D2                           | D2 = trap word from caller
        BSR.B   TRAP_RESOLVE_HANDLER            | resolve to absolute addr
        MOVE.L  D2,A0                           | A0 = resolved handler
        MOVE.L  (SP)+,A2                        | restore A2
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | return from GetTrapAddress (A0 = handler)
| ----------------------------------------------------------
| _SetTrapAddress ($A047): install a trap handler in the dispatch table
| Pascal: PROCEDURE SetTrapAddress(trapAddr: LONGINT; trapNum: INTEGER);
| Entry: A0 = trapAddr, D0.W = trapNum (low 9 bits used: OS and Toolbox
|        traps share the 512-entry DispatchTab at $400)
| Exit:  D0 = noErr
| Each entry is 16 bits: (trapAddr - ROMBase) / 2 for addresses at or
| above ROMBase, else (trapAddr - RAMBase) / 2 with bit 15 set, so a
| handler must lie within 64K of ROMBase or RAMBase.
SetTrapAddress:
        MOVE.L  A0,D1                           | D1 = handler address
        CMP.L   (ROMBase).w,D1                  | address >= ROMBase?
        BLT.B   INSTDISP_RamPath                | no: use RAM-base offset
        SUB.L   (ROMBase).w,D1                  | yes: D1 = offset from ROMBase
INSTDISP_Store:
        ROR     #0x1,D1                         | shift bit 0 to MSB (ROM=0, RAM=1)
        ANDI    #0x1FF,D0                       | D0 = trap idx in low 9 bits
        ADD     D0,D0                           | D0 *= 2 (word index into DispatchTab)
        LEA.L   (DispatchTab).w,A0              | A0 = dispatch table base
        MOVE    D1,0(A0,D0.W)                   | DispatchTab[D0] = offset tag
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | return from SetTrapAddress (D0 = noErr)
INSTDISP_RamPath:
        SUB.L   (RAMBase).w,D1                  | D1 = offset from RAMBase
        ADDQ.W  #0x1,D1                         | +1 so ROR gives MSB=1 (RAM tag)
        BRA.B   INSTDISP_Store                  | back to shared store path
