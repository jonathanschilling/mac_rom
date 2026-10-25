| --> QUICKGLUE.TEXT
|
| QuickDraw's interface to the rest of the system (1983 QuickGlue.a):
| NewHandle (NewHandle_Inline, with the system error 25 on failure),
| SetHSize, DisposeHandle (KILLPICTURE_BODY, also the _KillPicture entry),
| LockHandle/UnlockHandle (HLock_Inline, HUNLOCK_POP_RTS), the cursor and
| screen J-vector trampolines (PUSH_JShowCursor ... PUSH_JScrnSize: the
| LCursor.s traps call or jump to them) and the FMSwapFont glue. In the
| 64K ROM this file is linked between Pictures and the Font Manager.

| NewHandle_Inline -- aLLOCATE PTBUF.
| Called by: OpenPicture, OpenPoly, NewRgn, OpenRgn, INSETRGN_NOTRECT (and 4 more)
NewHandle_Inline:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.L  (SP)+,A1                        | pop return jump address
        MOVE    (SP)+,D0                        | pop requested size into D0
        _NewHandle                              | allocate handle of size D0
        BNE.B   MEMFULL_SYSERR                  | if non-zero -> MEMFULL_SYSERR
        MOVE.L  A0,(SP)                         | (SP) := A0
        JMP     (A1)                            | jump via A1
MEMFULL_SYSERR:
        MOVEQ.L #0x19,D0                        | D0 = dsMemFullErr (25)
        _SysError                               | system error (halt)
        _Debugger                               | (unreachable) drop to debugger

| SetHSize -- mAKE THE BUFFER BIGGER.
| Called by: DOLINE_CONT, DVPOS_OK, PutRect, PUTPT, EMPTY (and 9 more)
SetHSize:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.L  (SP)+,A1                        | pop return jump address
        MOVE    (SP)+,D0                        | pop new size into D0
        MOVE.L  (SP)+,A0                        | pop handle into A0
        _SetHandleSize                          | resize handle A0 to D0 bytes
        BNE.B   MEMFULL_SYSERR                  | if non-zero -> MEMFULL_SYSERR
        JMP     (A1)                            | jump via A1
| ----------------------------------------------------------
| .PROC KillPicture
|
| KILLPICTURE_BODY - dispose a handle passed on the stack (KillPicture's body)
| PROCEDURE KillPicture(myPicture: PicHandle);  { 1983 Pictures.a }
| Entry: 4(SP) = handle. Pops the return address (A1) and the handle (A0),
| calls _DisposHandle and returns through A1. Clobbers D0/A0/A1.
| The _KillPicture trap entry ($A8F5) jumps here; DisposRgn, CloseRgn,
| InsetRgn, DoRgnOp, MapRgn, ClosePicture and PicItem call it to dispose
| their temporary handles.
| Called by: DisposRgn, CloseRgn, INSETRGN_FINISH, JDONE_NO_2, MAPRGN_LOOP_2 (and 4 more)
KILLPICTURE_BODY:
        MOVE.L  (SP)+,A1                        | pop return addr
        MOVE.L  (SP)+,A0                        | pop handle
        _DisposeHandle                          | DISCARD THE HANDLE
        JMP     (A1)                            | and return
HLock_Inline:
        MOVE.L  4(SP),A0                        | A0 := 4(SP)
        BSET    #0x7,(A0)                       | set bit #0x7 of (A0)
        MOVE.L  (SP)+,(SP)                      | pop (SP)
        RTS                                     | return from HLock_Inline

| ----------------------------------------------------------
| HUNLOCK_POP_RTS -- tail of _HUnlock trap; clears bit 7 of master flag
| then strips param and RTS. Reached via fall-through from _HUnlock body.
HUNLOCK_POP_RTS:
        MOVE.L  4(SP),A0                        | A0 = handle param
        BCLR    #0x7,(A0)                       | clear lock bit in master ptr flag
        MOVE.L  (SP)+,(SP)                      | strip handle param
        RTS                                     | return from HUNLOCK_POP_RTS

| ----------------------------------------------------------
| J-vector trampolines. Each pushes one of the system graphic jump
| vectors in low memory and RTSes into it, so a JSR or JMP to one of
| them calls the routine the vector points to (by default the cursor
| and screen routines in hw/interrupts.s). Used by the LCursor trap
| entries (quickdraw/LCursor.s: InitCursor ... ObscureCursor) and by
| InitGraf (screen address and size); none of them is a trap entry.
PUSH_JShowCursor:                               | target of ShowCursor
        MOVE.L  (JShowCursor).w,-(SP)           | get lo mem vector
        RTS                                     | and call it
PUSH_JHideCursor:                               | target of HideCursor
        MOVE.L  (GrafBegin_JHideCursor).w,-(SP) | get lo mem vector
        RTS                                     | and call it
PUSH_JSetCrsr:                                  | called by SetCursor
        MOVE.L  (JSetCrsr).w,-(SP)              | get lo mem vector
        RTS                                     | and call it
PUSH_JInitCrsr:                                 | target of InitCursor
        MOVE.L  (JInitCrsr).w,-(SP)             | get lo mem vector
        RTS                                     | and call it
PUSH_JCrsrObscure:                              | target of ObscureCursor
        MOVE.L  (JCrsrObscure).w,-(SP)          | get lo mem vector
        RTS                                     | and call it
PUSH_JShieldCursor:                             | called by ShieldCursor
        MOVE.L  (JShieldCursor).w,-(SP)         | get lo mem vector
        RTS                                     | and call it
PUSH_JScrnAddr:                                 | called by InitGraf
        MOVE.L  (JScrnAddr).w,-(SP)             | push screen-address proc vector
        RTS                                     | and call it
PUSH_JScrnSize:                                 | called by InitGraf
        MOVE.L  (JScrnSize).w,-(SP)             | push screen-size proc vector
        RTS                                     | and call it

| _FMSwapFont ($A901): vectored through JSwapFont. Classic
| installs SwapFont into JSwapFont during InitFonts; Plus
| installs SwapFont. Same overall mechanism.
FMSwapFont:
        MOVE.L  (JSwapFont).w,-(SP)             | vectored through JSwapFont
        RTS                                     | jump to SwapFont implementation

