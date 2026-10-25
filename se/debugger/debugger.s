| 68000 exception handling and the _Debugger trap
|
| Apple source: StartErr.a (MacSEROM.lst modules SYSERRINIT, DEBUGGER,
| TODEEPSHIT, GENEXCPS). In ROM order:
| 1. SysErrInit - boot-time install of exception vectors 2-63
| 2. Debugger - the _Debugger trap handler (enters an installed debugger)
| 3. ToDeepShit - fatal-exception entry: system error with the exception
|    number as error code
| 4. GenExcps - 68000 exception vector dispatch table (BSR.B entries; the
|    return address tells which exception occurred)
| The _SysError trap and the built-in system error alert follow in
| os/sys_error.s, the MicroBug ROM debugger in microbug.s.
|
| SysErrInit runs during startup; the rest runs in response to 68000
| exceptions or the _Debugger trap. DEBUGPROLOG gets the debugger
| address and status; IRQEXCEPTION handles unexpected autovector
| interrupts.
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

| SYSERRINIT - boot-time exception vector initialization
|
| Fills 68000 vectors 2-63 with exception handlers that route to
| ToDeepShit for system error display. Clears SERegs save area.
| Vectors 2-11: unique GenExcps BSR entries (encodes exception ID)
| Vectors 12-24: common unassigned exception handler
| Vectors 25-31: IRQexception (autovector interrupts 1-7)
| Vectors 32-63: common unassigned handler (TRAP instructions)
| Return address in A6.
SYSERRINIT:
    SUBA.L	A0,A0                                | A0 = 0x000000
    ADDQ.L	#0x8,A0                              | A0 = 0x000008 (vector 2: bus error)
    LEA.L	GENEXCPS(PC),A1                       | A1 = first exception handler
    MOVEQ.L	#0x9,D0                             | 10 unique exception vectors (2-11)
| Install vectors 2-11: each GenExcps entry is 2 bytes apart (BSR.B ToDeepShit)
| so the BSR offset encodes which exception triggered the error.
VECLOOP_UNIQUE:
    MOVE.L	A1,(A0)+                             | store handler in vector slot
    ADDQ.L	#0x2,A1                              | advance to next GenExcps entry
    DBF.W	D0,VECLOOP_UNIQUE                     | loop for vectors 2-11
    MOVEQ.L	#0xC,D0                             | 13 unassigned vectors (12-24)
| Install vectors 12-24: all point to same unassigned handler
VECLOOP_UNASSIGNED:
    MOVE.L	A1,(A0)+                             | store common handler
    DBF.W	D0,VECLOOP_UNASSIGNED                 | loop for vectors 12-24
    LEA.L	IRQEXCEPTION(PC),A2                   | A2 = autovector interrupt handler
    MOVEQ.L	#0x6,D0                             | 7 autovector IRQs (25-31)
| Install vectors 25-31: autovector interrupts (levels 1-7)
VECLOOP_IRQ:
    MOVE.L	A2,(A0)+                             | store IRQ handler
    DBF.W	D0,VECLOOP_IRQ                        | loop for vectors 25-31
    MOVEQ.L	#0x1F,D0                            | 32 TRAP/reserved vectors (32-63)
| Install vectors 32-63: TRAP instructions + reserved vectors
VECLOOP_TRAP:
    MOVE.L	A1,(A0)+                             | store common handler
    DBF.W	D0,VECLOOP_TRAP                       | loop for vectors 32-63
| Zero the register save area (SERegs at $3FFC80, 128 bytes)
    LEA.L	(0x3FFC80).L,A0                       | A0 = SERegs save area
    MOVEQ.L	#0x1F,D0                            | 32 longwords (128 bytes)
CLEAR_SEREGS:
    CLR.L	(A0)+                                 | clear one longword
    DBF.W	D0,CLEAR_SEREGS                       | loop for all 128 bytes
    CLR.L	(MacJmp).W                            | MacJmp = 0 (no debugger installed)
    JMP	(A6)                                    | return to boot code via A6
| ----------------------------------------------------------
| DEBUGGER - ROM debugger entry point (called via _Debugger trap)
| Saves all registers to SERegs, checks if external debugger
| (MacsBug) is installed via MacJmp, dispatches to it.
| If no debugger, returns error code -8 (dsNoPatch).
| Stack: return address, trap word, parameter size word.
DEBUGGER:
    MOVEM.L	D0-D7/A0-A7,(0x3FFC80).L            | save all registers to SERegs
    BSET	#0x7,(MacJmp)                          | set bit 7: debugger-active flag
    LINK	A6,#0x0                                | create stack frame
    LEA.L	0x8(A6),A0                            | A0 = past return addr to parameters
    MOVE.W	(A0)+,D0                             | D0 = trap word
    MOVE.W	(A0)+,(0x3FFCCA).L                   | save parameter size to SERegs+$4A
    BSR.B	DEBUGPROLOG                           | get debugger addr from MacJmp -> A1
    BLE.B	DBG_NO_DEBUGGER                       | no debugger: return error
    BSET	#0xF,D0                                | set bit 15 (debugger-call flag)
    JSR	(A1)                                    | call external debugger
    BRA.B	DBG_CLEANUP                           | debugger returned: clean up
| ----------------------------------------------------------
| DBG_NO_DEBUGGER - no debugger installed, return error
DBG_NO_DEBUGGER:
    MOVEQ.L	#-0x8,D0                            | D0 = -8 (dsNoPatch)
DBG_CLEANUP:
    UNLK	A6                                     | remove stack frame
    MOVEM.L	(0x3FFC80).L,D0-D7/A0-A7            | restore all registers from SERegs
    MOVEA.L	(A7)+,A0                            | A0 = return address
    ADDA.W	(0x3FFCCA).L,A7                      | remove trap parameters
    ADDQ.L	#0x4,A7                              | remove trap word + size (4 bytes)
    BCLR	#0x7,(MacJmp)                          | clear debugger-active flag
    JMP	(A0)                                    | tail-call return from DBG_CLEANUP via A0
| ----------------------------------------------------------
| DEBUGPROLOG - extract debugger address and status from MacJmp
| MacJmp low 24 bits = debugger address, high byte = flags.
| Returns A1 = debugger entry, CC from flag byte (Z=none, N=active).
DEBUGPROLOG:
    MOVE.L	(MacJmp).W,D2                        | D2 = MacJmp (flags + address)
    AND.L	(Lo3Bytes).W,D2                       | mask to 24-bit address
    MOVEA.L	D2,A1                               | A1 = debugger entry point
    MOVE.B	(MacJmp).W,D3                        | D3 = flag byte
    ADD.B	D3,D3                                 | shift left: sets N from bit 6
    RTS                                         | return from DEBUGPROLOG
| ----------------------------------------------------------
| TODEEPSHIT - fatal exception handler entry point
| Called via BSR from GenExcps entries. The BSR return address
| encodes which exception occurred (offset from GenExcps / 2).
| Saves registers, extracts exception frame, falls to SysErr2.
| On 68000, bus/address errors push extended frame (+8 bytes).
| Called by: EXCPT_UNASSIGNED, GENEXCPS, EXCPT_ADDR_ERR, EXCPT_ILLEGAL, EXCPT_ZERO_DIV (and 7 more)
TODEEPSHIT:
    MOVE.W	#0x2700,SR                           | supervisor mode, mask all interrupts
    TST.B	(MacJmp).W                            | debugger already active (bit 7)?
    BMI.B	EXCPT_REGS_SAVED                      | yes: regs already saved
    MOVEM.L	D0-D7/A0-A7,(0x3FFC80).L            | save all registers to SERegs
EXCPT_REGS_SAVED:
    LEA.L	GENEXCPS(PC),A0                       | A0 = GenExcps base
    MOVE.L	(A7)+,D0                             | D0 = BSR return addr
    SUB.L	A0,D0                                 | D0 = byte offset from GenExcps
    LSR.W	#0x1,D0                               | D0 = exception ID (2 bytes/entry)
    TST.B	(CPUFlag).W                           | 68000 or 68020+?
    BNE.B	EXCPT_STD_FRAME                       | 68020+: standard frame only
    CMPI.W	#0x2,D0                              | exception ID <= 2 (bus/address)?
    BGT.B	EXCPT_STD_FRAME                       | no: standard 6-byte frame
    MOVE.L	(A7)+,(0x3FFCCC).L                   | save access address (extended frame)
    MOVE.L	(A7)+,(0x3FFCD0).L                   | save instruction reg + bus cycle
EXCPT_STD_FRAME:
    TST.B	(MacJmp).W                            | debugger already active?
    BMI.B	EXCPT_DISCARD_FRAME                   | yes: don't save SR/PC
    MOVE.W	(A7)+,(0x3FFCC4).L                   | save exception SR to MacsBugSR
    MOVE.L	(A7)+,(0x3FFCC0).L                   | save exception PC to MacsBugPC
    BRA.B	EXCPT_TO_SYSERR                       | proceed to system error
| ----------------------------------------------------------
| EXCPT_DISCARD_FRAME - debugger was active, discard exception frame
EXCPT_DISCARD_FRAME:
    ADDQ.L	#0x6,A7                              | discard 6-byte exception frame
EXCPT_TO_SYSERR:
    BRA.B	SYSERR2                               | display system error (D0 = ID)
| ----------------------------------------------------------
| GENEXCPS - exception vector dispatch table (2-byte BSR entries)
| Each BSR pushes a return address that encodes the exception ID.
GENEXCPS:
    BSR.B	TODEEPSHIT                            | vector 2: bus error (ID 0)
EXCPT_ADDR_ERR:
    BSR.B	TODEEPSHIT                            | vector 3: address error (ID 1)
EXCPT_ILLEGAL:
    BSR.B	TODEEPSHIT                            | vector 4: illegal instruction (ID 2)
EXCPT_ZERO_DIV:
    BSR.B	TODEEPSHIT                            | vector 5: zero divide (ID 3)
EXCPT_CHK:
    BSR.B	TODEEPSHIT                            | vector 6: CHK instruction (ID 4)
EXCPT_TRAPV:
    BSR.B	TODEEPSHIT                            | vector 7: TRAPV (ID 5)
EXCPT_PRIVILEGE:
    BSR.B	TODEEPSHIT                            | vector 8: privilege violation (ID 6)
EXCPT_TRACE:
    BSR.B	TODEEPSHIT                            | vector 9: trace (ID 7)
EXCPT_LINE_1010:
    BSR.B	TODEEPSHIT                            | vector 10: line 1010 emulator (ID 8)
EXCPT_LINE_1111:
    BSR.B	TODEEPSHIT                            | vector 11: line 1111 emulator (ID 9)
EXCPT_UNASSIGNED:
    BSR.B	TODEEPSHIT                            | vectors 12-24: unassigned (ID 10)
    BSR.B	TODEEPSHIT                            | (extra entry for chained vectors)
| ----------------------------------------------------------
| IRQEXCEPTION - autovector interrupt exception (fatal: shouldn't happen)
IRQEXCEPTION:
    BSR.B	TODEEPSHIT                            | unexpected IRQ -> system error
