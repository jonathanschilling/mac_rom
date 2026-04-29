| A-Line Trap Dispatcher and Device Manager Core
|
| The 68000 Line 1010 Emulator: dispatches A-line exceptions ($Axxx)
| to OS or Toolbox trap handlers via RAM-resident dispatch tables.
| - OS traps ($A000-$A0FF): 256 entries at DispatchTab ($0400)
| - Toolbox traps ($A800-$ABFF): 1024 entries at ToolDispTable ($0C00)
|
| Trap word encoding (Inside Mac II, ch.8):
| Bit 11: 0=OS trap, 1=Toolbox trap
| OS: bits 8=save/restore A0, bits 0-7=trap number (256 entries)
| Toolbox: bit 10=auto-pop, bits 0-9=trap number (1024 entries)
|
| Also contains Device Manager dispatch (Fetch/Stash/IODone) and
| _GetTrapAddress/$A146, _SetTrapAddress/$A047 implementations.

| 68020+ A-line entry: 68020 pushes format/vector word after SR+PC
ATrap68020:
        MOVE.L  0x2(SP),0x4(SP)                 | shift PC down over format/vector word
        BRA.B   TRAP_COMMON                     | join common dispatcher path

| ----------------------------------------------------------
|
| EMT1010 - 68000 Line 1010 Emulator (trap dispatcher)
|
| 68000 A-line exception pushes SR (word) + PC (long) onto stack.
| This is the main entry point for all A-line trap dispatch.
EMT1010_TrapDispatch:
        SUBQ.L  #0x2,SP                         | make room: align stack to match 68020 frame
TRAP_COMMON:
        MOVEM.L D1-D2/A2,-(SP)                  | save working registers
        MOVE.L  0x10(SP),A2                     | A2 = PC from exception frame (points to trap word)
        MOVE    (A2)+,D2                        | D2 = trap word; advance PC past it
        MOVE.L  A2,0x10(SP)                     | store updated PC as return address
        MOVE    D2,D1                           | D1 = copy of trap word (passed to OS routines)
        ANDI    #0x1FF,D2                       | D2 = trap number (bits 0-8 masked for Toolbox range)
        CMPI    #-0x5800,D1                     | test bit 11: $A800 unsigned = $FFFF-$5800+1; BCS if OS
        BCS.B   TRAP_OS_PATH                    | branch if OS trap (bit 11 = 0)
        LEA.L   (ToolDispTable).w,A2            | A2 = base of Toolbox dispatch table ($0C00)
        LSL     #0x2,D2                         | D2 = trap number * 4 (long-word index)
        MOVE.L  0x0(A2,D2.W),0xC(SP)            | store handler address below saved regs on stack
        CMPI    #-0x5400,D1                     | test bit 10 (auto-pop): $AC00 unsigned = $FFFF-$5400+1
        MOVEM.L (SP)+,D1-D2/A2                  | restore working registers
        BCS.B   TRAP_TBOX_DISPATCH              | branch if auto-pop bit clear (normal Toolbox call)
        MOVE.L  (SP)+,(SP)                      | auto-pop: discard glue return address from stack
TRAP_TBOX_DISPATCH:
        RTS                                     | dispatch to Toolbox routine via address on stack

| ----------------------------------------------------------
|
| OS trap dispatch path
|
| OS trap word: bit 8 = 1 means do NOT save/restore A0 (result in A0).
| D2 has 9-bit trap number; bit 8 is the save-A0 flag, bits 0-7 = index.
TRAP_OS_PATH:
        LEA.L   (DispatchTab).w,A2              | A2 = base of OS dispatch table ($0400)
        BCLR    #0x8,D2                         | test+clear bit 8: save A0? (0=yes, was-1=no)
        BNE.B   TRAP_OS_NOSAVEREG               | branch if bit 8 was set (don't save A0)
        LSL     #0x2,D2                         | D2 = trap number * 4 (long-word index)
        MOVE.L  0x0(A2,D2.W),A2                 | A2 = handler address from OS dispatch table
        MOVEM.L A0-A1,-(SP)                     | save A0-A1 (will restore A0 on return)
        JSR     (A2)                            | call the OS trap handler
        MOVEM.L (SP)+,A0-A1                     | restore A0-A1 (A0 preserved for caller)
TRAP_OS_RETURN:
        MOVEM.L (SP)+,D1-D2/A2                  | restore dispatcher's saved registers
        ADDQ.W  #0x4,SP                         | discard the extra stack slot from SUBQ.L #2
        TST     D0                              | set condition codes from result code in D0
        RTS                                     | return to instruction after the trap word

| ----------------------------------------------------------
|
| OS trap dispatch - bit 8 set (A0 returns a result)
|
| Only A1 is saved/restored; A0 passes through to return result.
TRAP_OS_NOSAVEREG:
        LSL     #0x2,D2                         | D2 = trap number * 4 (long-word index)
        MOVE.L  0x0(A2,D2.W),A2                 | A2 = handler address from OS dispatch table
        MOVE.L  A1,-(SP)                        | save A1 only (A0 will carry result back)
        JSR     (A2)                            | call the OS trap handler
        MOVE.L  (SP)+,A1                        | restore A1
        BRA.B   TRAP_OS_RETURN                  | rejoin common OS return path

| ----------------------------------------------------------
|
| _SetTrapAddress ($A047) - NSetTrapAddress
|
| On entry: A0 = new handler address, D0 = trap word, D1 = trap word
| Bit 9 of D1: 1 = "new" interface (bit 10 selects OS vs Toolbox)
| 0 = "old" interface (auto-detect via DETECT_TRAP_TABLE)
| Bit 10 of D1: 1 = Toolbox trap, 0 = OS trap (new interface only)
SetTrapAddress:
        BTST    #0x9,D1                         | test "new" bit (NSetTrapAddress vs SetTrapAddress)
        BEQ.B   SET_TRAP_OLD                    | branch to old-style auto-detect path
        ANDI    #0x1FF,D0                       | mask to 9-bit Toolbox trap number (bits 0-8)
        LEA.L   (ToolDispTable).w,A1            | assume Toolbox table
        BTST    #0xA,D1                         | test OS/Toolbox selector bit
        BNE.B   SET_TRAP_STORE                  | branch if Toolbox (bit 10 = 1)
        ANDI    #0xFF,D0                        | OS trap: mask to 8-bit trap number (bits 0-7)
        LEA.L   (DispatchTab).w,A1              | use OS dispatch table
SET_TRAP_STORE:
        LSL     #0x2,D0                         | trap number * 4 = table offset
        MOVE.L  A0,0x0(A1,D0.W)                 | store new handler address into dispatch table
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | return from _SetTrapAddress

| ----------------------------------------------------------
|
| Old-style SetTrapAddress (bit 9 = 0)
|
| Auto-detects OS vs Toolbox via DETECT_TRAP_TABLE heuristic, then stores address.
SET_TRAP_OLD:
        BSR.B   DETECT_TRAP_TABLE               | auto-detect table: sets A1 to OS or Toolbox table
        BRA.B   SET_TRAP_STORE                  | store address using detected table

| ----------------------------------------------------------
|
| DETECT_TRAP_TABLE - Old-style OS/Toolbox auto-detect
|
| Pre-System 7 trap API: without the "new" bit, the system must
| guess whether a trap number belongs to the OS or Toolbox table.
| Traps $50-$53 and $55-$56 are Toolbox; $54 and $57 map to OS.
| All others <= $4F map to OS; > $57 map to Toolbox.
| Returns A1 = pointer to correct dispatch table.
DETECT_TRAP_TABLE:
        ANDI    #0x1FF,D0                       | mask to 9-bit trap number
        LEA.L   (ToolDispTable).w,A1            | assume Toolbox table
        CMPI    #0x57,D0                        | compare against _SetApplBase ($A057)
        BHI.B   DETECT_DONE                     | > $57: definitely Toolbox, done
        BEQ.B   DETECT_OS_TABLE                 | = $57: _SetApplBase is an OS trap
        CMPI    #0x4F,D0                        | compare against _RDrvrInstall ($A04F)
        BLS.B   DETECT_OS_TABLE                 | <= $4F: OS trap range
        CMPI    #0x54,D0                        | $50-$53 are Toolbox, $54 is OS
        BNE.B   DETECT_DONE                     | $50-$53, $55-$56: Toolbox table
DETECT_OS_TABLE:
        LEA.L   (DispatchTab).w,A1              | use OS dispatch table
DETECT_DONE:
        RTS                                     | return with A1 pointing to correct table

| ----------------------------------------------------------
|
| Old-style GetTrapAddress (bit 9 = 0)
|
| Auto-detects OS vs Toolbox via DETECT_TRAP_TABLE, then reads address.
GET_TRAP_OLD:
        BSR.B   DETECT_TRAP_TABLE               | auto-detect table: sets A1 to OS or Toolbox table
        BRA.B   GET_TRAP_READ                   | read address from detected table

| ----------------------------------------------------------
|
| _GetTrapAddress ($A146) - NGetTrapAddress
|
| On entry: D0 = trap word, D1 = trap word
| On exit: A0 = handler address from dispatch table
| Bit 9 of D1: 1 = "new" interface (bit 10 selects OS vs Toolbox)
| 0 = "old" interface (auto-detect via DETECT_TRAP_TABLE)
GetTrapAddress:
        BTST    #0x9,D1                         | test "new" bit (NGetTrapAddress vs GetTrapAddress)
        BEQ.B   GET_TRAP_OLD                    | branch to old-style auto-detect path
        ANDI    #0x1FF,D0                       | mask to 9-bit Toolbox trap number
        LEA.L   (ToolDispTable).w,A1            | assume Toolbox table
        BTST    #0xA,D1                         | test OS/Toolbox selector bit
        BNE.B   GET_TRAP_READ                   | branch if Toolbox (bit 10 = 1)
        ANDI    #0xFF,D0                        | OS trap: mask to 8-bit trap number
        LEA.L   (DispatchTab).w,A1              | use OS dispatch table
GET_TRAP_READ:
        LSL     #0x2,D0                         | trap number * 4 = table offset
        MOVE.L  0x0(A1,D0.W),A0                 | A0 = handler address from dispatch table
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | return from _GetTrapAddress
