| 68000 Exception Handling, _Debugger Trap, and Built-in ROM Debugger (MicroBug)
|
| This file covers the full system-error / exception-handler chain:
| 1. SysErrInit - boot-time install of exception vectors 2-63
| 2. GenExcps - 68000 exception vector dispatch table (BSR.B entries)
| 3. ToDeepShit - fatal-exception entry point (panic path)
| 4. Debugger - the _Debugger trap handler (calls external MacsBug)
| 5. IconDispatch/SysErr2 - runtime entry: saves registers, decides debugger-vs-DS
| 6. DSErrorHandler - built-in DS alert (Sad Mac icon + error text + buttons)
| 7. MicroBug - the built-in minimal ROM debugger (hex expression parser)
|
| The exception code at the top of this file is installed during boot
| (by SysErrInit, called from BOOT_MEMTEST_RET in vectors.s). The remaining
| routines run at runtime in response to 68000 exceptions, _SysError, or
| the _Debugger trap.
|
| Save area layout (from TN1136):
| 0x3FFC80 D0-D7 (8 x 4 bytes)
| 0x3FFCA0 A0-A7 (8 x 4 bytes)
| 0x3FFCBC SP at exception time
| 0x3FFCC0 PC at exception time (MacsBugPC)
| 0x3FFCC4 SR at exception time (MacsBugSR)
|
| MicroBug variables:
| 0x3FFCF6 expression negate flag
| 0x3FFCF8 dot address ("." in expressions)
| 0x3FFCFC DM continuation address
| 0x3FFCD4 serial port selection (1=modem, 2=printer)
| 0x3FFCDA saved A-line trap vector
| 0x3FFCDE trap watch range low
| 0x3FFCE0 trap watch range high
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
| Debugger - ROM debugger entry point (called via _Debugger trap or NMI)
|
| Saves all registers to SERegs, checks if an external debugger is installed
| via MacJmp, and dispatches to it. If no debugger, returns error code -8.
| Stack frame on entry: return address, trap word, parameter size word.
Debugger:
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

| ----------------------------------------------------------
|
| IconDispatch - system error/debugger entry point
|
| Entered from _SysError trap, exception vectors, or _Debugger.
| D0 contains the error code (dsErrCode) on entry.
IconDispatch:
        MOVEM.L D0-D7/A0-A7,(0x3FFC80).l        | save all regs to SEVarBase

        MOVE    SR,(0x3FFCC4).l                 | save SR to MacsBugSR
        MOVE.L  (SP)+,(0x3FFCC0).l              | save return addr to MacsBugPC
        TST.B   (CPUFlag).w                     | 68000 or 68020+?
        BEQ.B   SysErr2                         | 68000: no format word on stack
        CLR     -(SP)                           | 68020+: push dummy format word
SysErr2:
        TST.B   (MacJmp).w                      | bit 7: debugger already active?
        BMI.B   DBG_SKIP_SP_SAVE                | skip SP save if re-entering
        MOVE.L  A7,(0x3FFCBC).l                 | save SP at exception time
DBG_SKIP_SP_SAVE:
        BSet    #0x7,(MacJmp).w                 | mark debugger as active
        MOVE    D0,(DSErrCode).w                | store error code for display
        BSR     DebugProlog                     | check for installed debugger
        BPL.B   ICDISP_NO_DEBUGGER              | N=0: no debugger or DS handler
        BNE.B   DBG_CALL_HANDLER                | N=1,Z=0: debugger found in A1
ICDISP_NO_DEBUGGER:
        CMPI    #0xD,D0                         | error 13 = "MicroBug entry"?
        BNE.B   DBG_USE_DS_HANDLER              | no - use DS error handler
        MOVEQ.L #0x0,D0                         | clear error code for MicroBug
        BRA.B   DBG_CALL_HANDLER                | enter debugger handler in A1

| ----------------------------------------------------------
|
| DBG_USE_DS_HANDLER - default: use built-in DS error handler
|
DBG_USE_DS_HANDLER:
        LEA.L   DSErrorHandler(PC),A1           | point A1 to ROM DS handler
DBG_CALL_HANDLER:
        JSR     (A1)                            | call debugger or DS handler
        TST     D0                              | handler returns 0 = resume
        BNE.B   DBG_USE_DS_HANDLER              | nonzero = re-enter DS handler
        BCLR    #0x7,(MacJmp).w                 | clear debugger-active flag
        MOVEM.L (0x3FFC80).l,D0-D7/A0-A7        | restore all regs from save area

        MOVE.L  (0x3FFCC0).l,-(SP)              | push saved PC for RTE
        MOVE    (0x3FFCC4).l,-(SP)              | push saved SR for RTE
        RTE                                     | return from exception
| ----------------------------------------------------------
|
| AllocFakeRgns - set up fake visRgn/clipRgn for DS GrafPort
|
| The DS error handler creates a minimal GrafPort on the stack.
| A6 points to the port; offsets +0x18/+0x1C are visRgn/clipRgn
| handles. This allocates fake region data in the port's local
| storage area at offset +0x6C, pointing both regions at a
| rectangular region covering the entire screen stored at Scratch20.
AllocFakeRgns:
        LEA.L   0x18(A6),A1                     | A1 = &port.visRgn handle slot
        LEA.L   0x6C(A6),A0                     | A0 = local storage for fake handles
        MOVE.L  A0,(A1)+                        | visRgn handle -> local storage[0]
        ADDQ.W  #0x4,A0                         | advance to next handle slot
        MOVE.L  A0,(A1)+                        | clipRgn handle -> local storage[1]
        LEA.L   (Scratch20).w,A1                | A1 = Scratch20 (region data buffer)
        MOVE.L  A1,(A0)                         | clipRgn handle -> Scratch20
        SUBQ.W  #0x4,A0                         | back to visRgn handle
        MOVE.L  A1,(A0)                         | visRgn handle -> Scratch20
| ----------------------------------------------------------
|
| INSTALL_INF_RGN - install infinite bounding region into Scratch20
|
| Copies 10-byte region struct (size=10, bbox=0x8001..0x7FFF)
| to Scratch20. Both visRgn and clipRgn point here.
INSTALL_INF_RGN:
        LEA.L   (Scratch20).w,A1                | destination: Scratch20 low-mem
        LEA.L   INF_RGN_TEMPLATE(PC),A0         | source: infinite region template
        MOVEQ.L #0xA,D0                         | 10 bytes = region header size
        _BlockMove                              | copy region data to Scratch20
        RTS                                     | return from region allocation

| ----------------------------------------------------------
|
| INF_RGN_TEMPLATE - infinite region template (10 bytes)
|
| Region: size=10, rgnBBox=(-32767,-32767,32767,32767)
INF_RGN_TEMPLATE:
  .byte 0x00,0x0A,0x80,0x01,0x80,0x01
  .byte 0x7F,0xFF,0x7F,0xFF

| ----------------------------------------------------------
|
| SysBeep - _SysBeep trap handler
|
| Plays the system alert sound if available, or flashes the
| menu bar if sound is busy or volume is zero.
SysBeep:
        MOVEM.L D0-D7/A1-A6,-(SP)               | save working regs
        TST.B   (SoundActive).w                 | sound driver currently in use?
        BNE.B   SYSBEEP_FLASH                   | yes - fall through to visual flash
        TST.B   (SdVolume).w                    | speaker volume = 0?
        BNE.B   SYSBEEP_AUDIBLE                 | nonzero - play audible beep
SYSBEEP_FLASH:
        TST.B   (WWExist).w                     | Window Manager initialized?
        BNE.B   SYSBEEP_EPILOG                  | no - skip flash, just return
        CLR.L   -(SP)                           | push 0 (flash menu bar)
        _FlashMenuBar                           | invert menu bar
        SUBA.L  A0,A0                           | A0 = 0
        ADDQ.W  #0x8,A0                         | A0 = 8 ticks delay
        _Delay                                  | wait ~133ms
        _FlashMenuBar                           | restore menu bar
        BRA.B   SYSBEEP_EPILOG                  | done

| ----------------------------------------------------------
|
| SYSBEEP_AUDIBLE - audible beep via BootBeep square wave
|
SYSBEEP_AUDIBLE:
        MOVE    0x3C(SP),D3                     | D3 = saved SR from stack frame
        LEA.L   SYSBEEP_EPILOG(PC),A6           | A6 = return address after beep
        BRA     BootBeep                        | play square wave beep

| ----------------------------------------------------------
|
| SYSBEEP_EPILOG - SysBeep epilogue, pops duration param and returns
|
SYSBEEP_EPILOG:
        MOVEM.L (SP)+,D0-D7/A1-A6               | restore working regs
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x2,SP                         | discard duration parameter (word)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| COPY_ALERT_RECT - copy DSAlertRect and offset to GrafPort origin
|
| Copies the 8-byte alert rectangle to Scratch20_2, clears
| the high bit (used as "rect initialized" flag), then offsets
| the rect by the GrafPort's portBits.bounds.topLeft.
COPY_ALERT_RECT:
        LEA.L   (DSAlertRect).w,A0              | source: DS alert rectangle
        LEA.L   (Scratch20_2).w,A1              | dest: scratch area
        MOVEQ.L #0x8,D0                         | 8 bytes = Rect struct
        _BlockMove                              | copy alert rect to scratch
        MOVE.L  A1,-(SP)                        | push rect ptr for OffsetRect
        BCLR    #0x7,(A1)                       | clear "initialized" flag bit
        MOVE.L  (A5),A0                         | A5 = QD globals; dereference
        MOVE.L  (A0),A0                         | dereference handle to GrafPort
        MOVE.L  0x8(A0),-(SP)                   | push portBits.bounds.topLeft
        _OffsetRect                             | offset rect to port coords
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DSErrorHandler - system error alert display
|
| Creates a temporary GrafPort on the stack, initializes
| QuickDraw, and displays the system error dialog using the
| alert table pointed to by DSAlertTab. If no alert table
| is installed, falls through to CritErr for a minimal display.
DSErrorHandler:
        MOVE    #0x2000,SR                      | enter supervisor, enable interrupts
        MOVE    (CurMap).w,-(SP)                | save current resource map
        MOVE    (SysMap).w,(CurMap).w           | switch to system resource map
        LEA.L   -0x4(SP),A5                     | A5 = QD globals ptr (above stack)
        SUBA    #0x15A,SP                       | allocate stack frame for GrafPort
        MOVE.L  A7,A6                           | A6 = base of temp GrafPort
        PEA.L   -0x4(A5)                        | push ptr for InitGraf thePort
        MOVE.B  (QDExist).w,D3                  | save QDExist state
        _InitGraf                               | init QuickDraw globals
        MOVE.B  D3,(QDExist).w                  | restore QDExist (may not be ready)
        BSR     AllocFakeRgns                   | set up fake visRgn/clipRgn
        MOVE.L  A6,-(SP)                        | push GrafPort ptr
        _InitPort                               | init the temporary port
        MOVE    (DSErrCode).w,-(SP)             | push error code for display
        MOVE.L  (DSAlertTab).w,D7               | D7 = ptr to system error alert table
        BNE.B   DSERR_DISPATCH                  | table exists - use it
        MOVE    (SP)+,D1                        | pop error code into D1
        MOVE    #0xF,A4                         | A4 = 15 (button flags for CritErr)
        SUBA.L  A3,A3                           | A3 = nil (no alert text)
        BRA     CritErr                         | show minimal "sorry" error box

| ----------------------------------------------------------
|
| DSERR_DISPATCH - dispatch on error code using alert table
|
DSERR_DISPATCH:
        MOVE    (SP),D0                         | peek at error code
        BMI.B   DSERR_SETUP_RECT                | negative = don't draw custom proc
        CMPI    #0xD,D0                         | error 13 = MicroBug entry?
        BEQ     MICROBUG_ENTRY                  | yes - enter MicroBug command loop
        BSR     CALL_DS_DRAWPROC                | call DSDrawProc if installed
DSERR_SETUP_RECT:
        BSR.B   COPY_ALERT_RECT                 | copy and offset alert rect
        MOVE    (SP)+,D0                        | pop error code
        BSR.B   LOOKUP_ALERT_ID                 | look up error code in alert table
        BNE.B   DSERR_DRAW_ALERT                | found - A0 points to alert def
        MOVE.L  D7,A0                           | not found - use default alert
        ADDQ.L  #0x6,A0                         | skip table header (count + first ID)
DSERR_DRAW_ALERT:
        MOVE.L  A0,A3                           | A3 = ptr to alert definition fields
        BSR.B   DRAW_ALERT_TEXT                 | draw first text string
        BSR.B   DRAW_ALERT_TEXT                 | draw second text string
        MOVE    (A3)+,D0                        | icon resource ID
        BEQ.B   DSERR_SKIP_ICON                 | 0 = no icon
        BSR.B   LOOKUP_ALERT_ID                 | look up icon ID in table
        BEQ.B   DSERR_SKIP_ICON                 | not found - skip icon
        PEA.L   0x8(A0)                         | push icon rect ptr (after icon data)
        MOVE.L  A0,-(SP)                        | push icon data ptr
        PEA.L   0x4(SP)                         | push dest rect on stack
        _PlotIcon                               | draw the alert icon
        ADDQ.W  #0x4,SP                         | pop extra rect ptr
DSERR_SKIP_ICON:
        MOVE    (A3)+,D0                        | procedure resource ID
        BEQ.B   DSERR_SKIP_PROC                 | 0 = no custom procedure
        BSR.B   LOOKUP_ALERT_ID                 | look up procedure in table
        BEQ.B   DSERR_SKIP_PROC                 | not found - skip
        JSR     (A0)                            | call custom alert procedure
DSERR_SKIP_PROC:
        MOVE    (A3)+,D0                        | button definition ID
        BEQ.B   DSERR_RESUME                    | 0 = no buttons, auto-resume
        TST.L   (ResumeProc).w                  | resume procedure installed?
        BEQ.B   DSERR_SHOW_BTNS                 | no - use button count as-is
        ADDQ.W  #0x1,D0                         | yes - add Resume button option
DSERR_SHOW_BTNS:
        BSR     SHOW_ALERT_BTNS                 | display buttons and wait for click
        BNE.B   DSERR_BTN_CLICKED               | button clicked - handle choice
DSERR_RESUME:
        BSR     INSTALL_INF_RGN                 | restore region data to Scratch20
        ADDA    #0x15A,SP                       | deallocate temp GrafPort frame
        MOVE    (SP)+,(CurMap).w                | restore resource map
        MOVEQ.L #0x0,D0                         | return 0 = resume execution
        RTS                                     | return to system error dispatcher

| ----------------------------------------------------------
|
| DSERR_BTN_CLICKED - button was clicked, clean up and return via button handler
|
DSERR_BTN_CLICKED:
        MOVE.L  A0,-(SP)                        | push button handler address
        BSR     INSTALL_INF_RGN                 | restore region data to Scratch20
        RTS                                     | jump to button handler via pushed addr

| ----------------------------------------------------------
|
| LOOKUP_ALERT_ID - look up ID in DS alert table
|
| Searches the alert table (pointed to by D7) for entry
| matching D0. Returns Z=0 and A0=entry data if found,
| Z=1 and A0=0 if not found.
| Called by: DSERR_SETUP_RECT, DSERR_DRAW_ALERT, DSERR_SKIP_ICON, DRAW_ALERT_TEXT, SHOW_ALERT_BTNS (and 2 more)
LOOKUP_ALERT_ID:
        MOVE.L  D7,A0                           | A0 = alert table base
        MOVE    (A0)+,D1                        | D1 = entry count
        BRA.B   LOOKUP_NEXT                     | enter loop

| ----------------------------------------------------------
|
| LOOKUP_LOOP - alert table search loop
|
LOOKUP_LOOP:
        CMP     (A0)+,D0                        | compare ID with table entry
        BEQ.B   LOOKUP_FOUND                    | match - return this entry
        ADDA    (A0)+,A0                        | skip entry data (offset to next)
LOOKUP_NEXT:
        DBF     D1,LOOKUP_LOOP                  | loop through all entries
        MOVEQ.L #0x0,D0                         | not found: D0=0, Z=1
        SUBA.L  A0,A0                           | A0 = nil
        RTS                                     | return with Z flag set (not found)

| ----------------------------------------------------------
|
| LOOKUP_FOUND - alert table entry found
|
LOOKUP_FOUND:
        MOVEQ.L #-0x1,D0                        | found: D0=-1, Z=0
        ADDQ.W  #0x2,A0                         | skip past offset word to entry data
        RTS                                     | return with Z flag clear (found)

