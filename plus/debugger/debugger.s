| 68000 exception handling and the _Debugger trap
|
| Apple source: the system error code (System 7.1: StartErr.a; MacSEROM.lst
| modules SYSERRINIT, DEBUGGER, TODEEPSHIT, GENEXCPS). In ROM order:
| 1. SysErrInit - boot-time install of exception vectors 2-63
| 2. Debugger - the _Debugger trap handler (enters an installed debugger)
| 3. ToDeepShit - fatal-exception entry: system error with the exception
|    number as error code
| 4. GenExcps - 68000 exception vector dispatch table (BSR.B entries; the
|    return address tells which exception occurred)
| The _SysError trap and the built-in system error alert follow in
| os/sys_error.s, the MicroBug ROM debugger in microbug.s.
|
| SysErrInit runs during startup (called from BOOT_MEMTEST_RET in
| vectors.s); the rest runs in response to 68000 exceptions or the
| _Debugger trap.
|
| Save area layout (from TN1136):
| 0x3FFC80 D0-D7 (8 x 4 bytes)
| 0x3FFCA0 A0-A7 (8 x 4 bytes)
| 0x3FFCBC SP at exception time
| 0x3FFCC0 PC at exception time (MacsBugPC)
| 0x3FFCC4 SR at exception time (MacsBugSR)
|
| References:
| Technical Note TN1136: MicroBug, The ROM Debugger
| Inside Macintosh II Ch 12: System Error Handler

| SysErrInit - initialize 68000 exception vector table and register save area
|
| Fills vectors 2-63 in the 68000 vector table (0x0008-0x00FF) with
| handlers that route to ToDeepShit for system error display.
| Vectors 2-11 (bus error..line 1010) get unique GenExcps entries (BSR offset
| encodes exception number). Vectors 12-24 share a common unassigned handler.
| Vectors 25-31 point to IRQexception (autovector interrupts 1-7).
| Vectors 32-63 share the unassigned handler (TRAP instructions).
|
| return address in A6
| Called during boot.
SysErrInit:
        SUBA.L  A0,A0                           | A0 = 0x000000
        ADDQ.L  #0x8,A0                         | A0 = 0x000008 (vector 2: bus error)
        LEA.L   GenExcps(PC),A1                 | A1 = first exception handler (bus error BSR)
        MOVEQ.L #0x9,D0                         | D0 = 9: vectors 2-11 (10 unique exception handlers)
| Install vectors 2-11: each GenExcps entry is 2 bytes apart (BSR.B ToDeepShit)
| so the BSR offset encodes which exception triggered the error.
VECLOOP_UNIQUE:
        MOVE.L  A1,(A0)+                        | store handler address in vector slot
        ADDQ.L  #0x2,A1                         | advance to next GenExcps entry (+2 bytes)
        DBF     D0,VECLOOP_UNIQUE               | loop for vectors 2-11
        MOVEQ.L #0xC,D0                         | D0 = 12: vectors 12-24 (13 unassigned vectors)
| Install vectors 12-24: all point to same unassigned exception handler
VECLOOP_UNASSIGNED:
        MOVE.L  A1,(A0)+                        | store common handler for unassigned exception
        DBF     D0,VECLOOP_UNASSIGNED           | loop for vectors 12-24
        LEA.L   IRQexception(PC),A2             | A2 = autovector interrupt handler
        MOVEQ.L #0x6,D0                         | D0 = 6: vectors 25-31 (7 autovector IRQs)
| Install vectors 25-31: autovector interrupts (levels 1-7)
VECLOOP_IRQ:
        MOVE.L  A2,(A0)+                        | store IRQ handler in autovector slot
        DBF     D0,VECLOOP_IRQ                  | loop for vectors 25-31
        MOVEQ.L #0x1F,D0                        | D0 = 31: vectors 32-63 (32 TRAP/reserved vectors)
| Install vectors 32-63: TRAP instructions + reserved vectors
VECLOOP_TRAP:
        MOVE.L  A1,(A0)+                        | store common handler for TRAP vectors
        DBF     D0,VECLOOP_TRAP                 | loop for vectors 32-63
        LEA.L   (0x3FFC80).l,A0                 | A0 = SERegs (register save area at top of RAM)
        MOVEQ.L #0x1F,D0                        | D0 = 31: clear 32 longwords (128 bytes)
| Zero the register save area used by system error handler
CLEAR_SEREGS:
        CLR.L   (A0)+                           | clear one longword of save area
        DBF     D0,CLEAR_SEREGS                 | loop for all 128 bytes
        LEA.L   SERIAL_DBG_ENTRY(PC),A0         | A0 = default MacJmp target (normal boot path)
        MOVE.L  A0,(MacJmp).w                   | MacJmp = default exception resume address
        BSET    #0x5,(MacJmp).w                 | set bit 5: debugger-not-installed flag
        JMP     (A6)                            | return to boot code

| ----------------------------------------------------------
|
| P_Debugger - ROM debugger entry point (called via _Debugger trap or NMI)
| (MacSEROM.lst names this code DEBUGGER; MacPlusROM.lst lists Debugger at
| the unimplemented-trap handler, where that name is a label, so this
| routine is P_Debugger)
|
| Saves all registers to SERegs, checks if an external debugger is installed
| via MacJmp, and dispatches to it. If no debugger, returns error code -8.
| Stack frame on entry: return address, trap word, parameter size word.
P_Debugger:
        MOVEM.L D0-D7/A0-A7,(0x3FFC80).l        | save all registers to SERegs save area

        BSET    #0x7,(MacJmp).w                 | set bit 7: debugger-active flag
        LINK    A6,#0x0                         | create stack frame for parameter access
        LEA.L   0x8(A6),A0                      | A0 = past return addr to trap parameters
        MOVE    (A0)+,D0                        | D0 = trap word (identifies which trap called)
        MOVE    (A0)+,(0x3FFCCA).l              | save parameter size to SERegs+0x4A
        BSR.B   DebugProlog                     | get debugger address from MacJmp into A1
        BLE.B   DBG_NO_DEBUGGER                 | no debugger installed: skip to error return
        BSET    #0xF,D0                         | set bit 15 of trap word (debugger-call flag)
        JSR     (A1)                            | call external debugger
        BRA.B   DBG_CLEANUP                     | debugger returned: restore and exit

| ----------------------------------------------------------
|
| DBG_NO_DEBUGGER - no debugger installed, return error
DBG_NO_DEBUGGER:
        MOVEQ.L #-0x8,D0                        | D0 = -8: dsNoPatch (no debugger installed)
DBG_CLEANUP:
        UNLK    A6                              | remove stack frame
        MOVEM.L (0x3FFC80).l,D0-D7/A0-A7        | restore all registers from SERegs

        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDA    (0x3FFCCA).l,SP                 | remove trap parameters from stack
        ADDQ.L  #0x4,SP                         | remove trap word + param size (4 bytes)
        BCLR    #0x7,(MacJmp).w                 | clear debugger-active flag
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| DebugProlog - extract debugger address and status from MacJmp
|
| MacJmp is a 32-bit value where the low 24 bits are the debugger entry
| address and the high byte holds flags (bit 7=active, bit 6=installed,
| bit 5=not-installed). Shifts flag byte left to set condition codes:
| Z=1 if no debugger, N=1 if debugger active.
| Returns: A1 = debugger entry address, CC set from flag byte.
| Called during boot.
DebugProlog:
        MOVE.L  (MacJmp).w,D2                   | D2 = MacJmp (flags + 24-bit address)
        AND.L   (Lo3Bytes).w,D2                 | mask off flag byte, keep 24-bit address
        MOVE.L  D2,A1                           | A1 = debugger entry point
        MOVE.B  (MacJmp).w,D3                   | D3 = MacJmp flag byte
        ADD.B   D3,D3                           | shift left: bit 6 -> N flag, sets CC
        RTS                                     | return with condition codes from flag byte

| ----------------------------------------------------------
|
| ToDeepShit - fatal exception handler entry point
|
| Called via BSR from GenExcps entries. The BSR return address on the stack
| encodes which exception occurred (offset from GenExcps base / 2 = error ID).
| Saves registers if not already saved (debugger-active check via MacJmp bit 7),
| then extracts the 68000 exception stack frame and falls through to SysErr2.
|
| On 68000 (CPUFlag=0), bus/address errors (IDs 0-2) push an extended frame
| with additional access address and instruction register fields.
ToDeepShit:
        MOVE    #0x2700,SR                      | supervisor mode, mask all interrupts
        TST.B   (MacJmp).w                      | check bit 7: debugger already active?
        BMI.B   EXCPT_REGS_SAVED                | yes: registers already saved, skip save
        MOVEM.L D0-D7/A0-A7,(0x3FFC80).l        | save all registers to SERegs

EXCPT_REGS_SAVED:
        LEA.L   GenExcps(PC),A0                 | A0 = base of exception handler table
        MOVE.L  (SP)+,D0                        | D0 = BSR return address (within GenExcps)
        SUB.L   A0,D0                           | D0 = byte offset from GenExcps base
        LSR     #0x1,D0                         | D0 = exception ID (each BSR is 2 bytes)
        TST.B   (CPUFlag).w                     | 68000 (0) or 68020+ (nonzero)?
        BNE.B   EXCPT_STD_FRAME                 | 68020+: no extended bus error frame
        CMPI    #0x2,D0                         | exception ID <= 2 (bus error, address error)?
        BGT.B   EXCPT_STD_FRAME                 | no: standard 6-byte exception frame
        MOVE.L  (SP)+,(0x3FFCCC).l              | save access address from extended frame
        MOVE.L  (SP)+,(0x3FFCD0).l              | save instruction register + bus cycle info
EXCPT_STD_FRAME:
        TST.B   (MacJmp).w                      | debugger already active?
        BMI.B   EXCPT_DISCARD_FRAME             | yes: don't save SR/PC (already corrupted)
        MOVE    (SP)+,(0x3FFCC4).l              | save exception SR to SERegs+0x44
        MOVE.L  (SP)+,(0x3FFCC0).l              | save exception PC to SERegs+0x40
        BRA.B   EXCPT_TO_SYSERR                 | proceed to system error display

| ----------------------------------------------------------
|
| EXCPT_DISCARD_FRAME - debugger was active when exception occurred, discard frame
EXCPT_DISCARD_FRAME:
        ADDQ.L  #0x6,SP                         | discard 6-byte exception frame (SR + PC)
EXCPT_TO_SYSERR:
        BRA.B   SysErr2                         | display system error with exception ID in D0

| ----------------------------------------------------------
|
| GenExcps - exception vector dispatch table
|
| Each entry is a 2-byte BSR.B to ToDeepShit. The BSR pushes a return
| address that encodes the exception number (offset / 2 from GenExcps).
| Vector 2=bus error (ID 0), vector 3=address error (ID 1), etc.
GenExcps:
        BSR.B   ToDeepShit                      | vector 2: bus error (ID 0)
EXCPT_ADDR_ERR:
        BSR.B   ToDeepShit                      | vector 3: address error (ID 1)
EXCPT_ILLEGAL_INST:
        BSR.B   ToDeepShit                      | vector 4: illegal instruction (ID 2)
EXCPT_ZERO_DIVIDE:
        BSR.B   ToDeepShit                      | vector 5: zero divide (ID 3)
EXCPT_CHK:
        BSR.B   ToDeepShit                      | vector 6: CHK instruction (ID 4)
EXCPT_TRAPV:
        BSR.B   ToDeepShit                      | vector 7: TRAPV instruction (ID 5)
EXCPT_PRIVILEGE:
        BSR.B   ToDeepShit                      | vector 8: privilege violation (ID 6)
EXCPT_TRACE:
        BSR.B   ToDeepShit                      | vector 9: trace (ID 7)
EXCPT_LINE_1010:
        BSR.B   ToDeepShit                      | vector 10: line 1010 emulator (ID 8)
EXCPT_LINE_1111:
        BSR.B   ToDeepShit                      | vector 11: line 1111 emulator (ID 9)
EXCPT_UNASSIGNED:
        BSR.B   ToDeepShit                      | vectors 12-24: unassigned (ID 10)
EXCPT_SHARED:
        BSR.B   ToDeepShit                      | (shared handler for remaining exceptions)
IRQexception:
        BSR.B   ToDeepShit                      | vectors 25-31: unexpected autovector IRQ

