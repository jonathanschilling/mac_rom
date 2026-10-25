| ------------------------------------------------------------------
|
| --> LCURSOR.TEXT
|
| Links to MacIntosh Cursor routines.
|
| System Graphic Jump Vectors:
|
| Long pointers to system routine entry points.
|
| ------------------------------------------------------------------
| QuickDraw cursor traps (ROM $533A-$53B3), from the 1983 LCursor.a:
| InitCursor, SetCursor, HideCursor, ShowCursor, ShieldCursor and
| ObscureCursor. They massage the Pascal parameters and pass control
| to the low-level cursor code (CrsrCore, hw/interrupts.s) through the
| system graphic jump vectors in low memory (JInitCrsr, JSetCrsr,
| JHideCursor, JShowCursor, JShieldCursor, JCrsrObscure). Where the
| 1983 source loads the vector itself, these ROM versions call or jump
| to the PUSH_Jxxx trampolines in toolbox/font_mgr.s (MOVE.L Jxxx,-(SP)
| followed by RTS).
|
| References:
| 1983 QuickDraw source LCursor.a
| Inside Macintosh Vol I, Ch 6: QuickDraw, "Cursor Handling"

| .PROC InitCursor,0
| .REF SetCursor
| ----------------------------------------------------------
|
| PROCEDURE InitCursor;
|
| _InitCursor ($A850): install the standard arrow cursor
| (QuickDraw global arrow) and make it visible (cursor level 0).
InitCursor:
        MOVEA.L (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        PEA.L   -0x6C(A0)                       | PUSH ADDR OF ARROW
        JSR     SetCursor(PC)                   | INSTALL ARROW CURSOR
        JMP     PUSH_JInitCrsr(PC)              | and call the JInitCrsr vector

| .PROC SetCursor,1
| ---------------------------------------------------
|
| PROCEDURE SetCursor(crsr: Cursor);
|
| _SetCursor ($A851): make crsr the current cursor; JSetCrsr gets
| the hot spot, the height (16), and pointers to data and mask.
SetCursor:
        MOVEA.L 4(SP),A0                        | Point to Cursor
        MOVE    0x42(A0),-(SP)                  | push hotSpot.h ...
        MOVE    0x40(A0),-(SP)                  | ... and hotSpot.v (PUSH HOTX & HOTY)
        MOVE    #0x10,-(SP)                     | HEIGHT:=16
        PEA.L     (A0)                          | PUSH ADDR OF DATA
        PEA.L     0x20(A0)                      | PUSH ADDR OF MASK
        JSR     PUSH_JSetCrsr(PC)               | call the JSetCrsr vector
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | and return

| .PROC HideCursor,0
| ---------------------------------------------------------
|
| PROCEDURE HideCursor;
|
| ALL REGS PRESERVED.
|
| _HideCursor ($A852)
HideCursor:
        JMP     PUSH_JHideCursor(PC)            | call the JHideCursor vector

| .PROC ShowCursor,0
| ---------------------------------------------------------
|
| PROCEDURE ShowCursor;
|
| ALL REGS PRESERVED.
|
| _ShowCursor ($A853)
ShowCursor:
        JMP     PUSH_JShowCursor(PC)            | call the JShowCursor vector

| .PROC ShieldCursor,2
| ---------------------------------------------------------
|
| PROCEDURE ShieldCursor(shieldRect: Rect; offset: Point);
|
| ALL REGS PRESERVED.
|
| _ShieldCursor ($A855): hide the cursor if it intersects shieldRect;
| converts shieldRect to global coordinates (subtracting offset) and
| passes left, top, right, bottom to the JShieldCursor vector.
| Called by: STDTEXT_FAST_X, VOK2_NO, OKRECT, SOLID, STDBITS_NOTPIC_EXIT (and 2 more)
ShieldCursor:
        LINK    A6,#0x0                         | frame for the parameters
        MOVEM.L D0-D2/A0-A1,-(SP)               | SAVE REGS
        MOVE.L  12(A6),A0                       | POINT TO SHIELDRECT
        MOVE    2(A0),D0                        | D0 = left
        SUB.W    10(FP),D0                      | LEFT - OFFSET.H
        MOVE    D0,-(SP)                        | PUSH GLOBAL LEFT
        MOVE    (A0),D0                         | D0 = top
        SUB     8(A6),D0                        | TOP - OFFSET.V
        MOVE    D0,-(SP)                        | PUSH GLOBAL TOP
        MOVE    6(A0),D0                        | D0 = right
        SUB     10(A6),D0                       | RIGHT - OFFSET.H
        MOVE    D0,-(SP)                        | PUSH GLOBAL RIGHT
        MOVE    4(A0),D0                        | D0 = bottom
        SUB     8(A6),D0                        | BOTTOM - OFFSET.V
        MOVE    D0,-(SP)                        | PUSH GLOBAL BOTTOM
        JSR     PUSH_JShieldCursor(PC)          | call the JShieldCursor vector
        MOVEM.L (SP)+,D0-D2/A0-A1               | RESTORE REGS
        UNLK    A6                              | release the frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x8,SP                         | STRIP 8 BYTES
        JMP     (A0)                            | AND RETURN

| .PROC ObscureCursor,0
| ---------------------------------------------------------
|
| PROCEDURE ObscureCursor;
|
| Hide the cursor image until the next time the mouse moves.
|
| _ObscureCursor ($A856)
ObscureCursor:
        JMP     PUSH_JCrsrObscure(PC)           | call the JCrsrObscure vector
