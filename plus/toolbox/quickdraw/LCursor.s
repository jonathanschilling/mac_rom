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

| .PROC InitCursor,0
| .REF SetCursor
| ----------------------------------------------------------
|
| PROCEDURE InitCursor;
|
| Called during boot.
InitCursor:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS

| GRAFBEGIN .EQU $800 ;GRAF GLOBAL AREA
| JHIDECURSOR .EQU GRAFBEGIN
| JSHOWCURSOR .EQU JHIDECURSOR+4
| JSHIELDCURSOR .EQU JSHOWCURSOR+4
| JSCRNADDR .EQU JSHIELDCURSOR+4 ;not used (see _GetScrnBits)
| JSCRNSIZE .EQU JSCRNADDR+4 ;not used (see _GetScrnBits)
| JINITCRSR .EQU JSCRNSIZE+4
| JSETCRSR .EQU JINITCRSR+4
| JCRSROBSCURE .EQU JSETCRSR+4
        PEA.L   ARROW(A0)                       | PUSH ADDR OF ARROW
        JSR     SetCursor(PC)                   | INSTALL ARROW CURSOR
        MOVE.L  (JInitCrsr).w,A0                | get lo mem pointer
        JMP     (A0)                            | and call it

| .PROC SetCursor,1
| ---------------------------------------------------
|
| PROCEDURE SetCursor(crsr: Cursor);
|
| Called during boot (3,700 times in 30s trace).
SetCursor:
        MOVE.L  0x4(SP),A0                      | Point to Cursor
        MOVE.L  0x40(A0),-(SP)                  | PUSH HOTX & HOTY
        MOVE    #16,-(SP)                       | HEIGHT:=16
        PEA.L   (A0)                            | PUSH ADDR OF DATA
        PEA.L   MASK(A0)                        | PUSH ADDR OF MASK
        MOVE.L  (JSetCrsr).w,A0                 | get lo mem vector
        JSR     (A0)                            | call vector
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | and return

| .PROC HideCursor
| ---------------------------------------------------------
|
| PROCEDURE HideCursor;
|
| ALL REGS PRESERVED.
|
| Called during boot.
HideCursor:
        MOVE.L  (GrafBegin_JHideCursor).w,-(SP) | get lo mem vector
        RTS                                     | and call it

| .PROC ShowCursor
| ---------------------------------------------------------
|
| PROCEDURE ShowCursor;
|
| ALL REGS PRESERVED.
|
| Called during boot.
ShowCursor:
        MOVE.L  (JShowCursor).w,-(SP)           | get lo mem vector
        RTS                                     | and call it

| .PROC ShieldCursor
| ---------------------------------------------------------
|
| PROCEDURE ShieldCursor(shieldRect: Rect; offset: Point);
|
| ALL REGS PRESERVED.
|
| Called during boot.
ShieldCursor:
        MOVEM.L D0-D3/A0-A1,-(SP)               | SAVE REGS
        MOVE.L  0x20(SP),A0                     | POINT TO SHIELDRECT
        MOVEM   (A0)+,D0-D3                     | GET TOP ... RIGHT
        LEA.L   0x1C(SP),A1                     | POINT TO OFFSET PARAM
        SUB     (A1),D0                         | TOP - OFFSET.V
        SUB     (A1)+,D2                        | BOTTOM - OFFSET.V
        SUB     (A1),D1                         | LEFT - OFFSET.H
        SUB     (A1),D3                         | RIGHT - OFFSET.H
        MOVE    D1,-(SP)                        | PUSH GLOBAL LEFT
        MOVE    D0,-(SP)                        | PUSH GLOBAL TOP
        MOVE    D3,-(SP)                        | PUSH GLOBAL RIGHT
        MOVE    D2,-(SP)                        | PUSH GLOBAL BOTTOM
        MOVE.L  (JShieldCursor).w,A0            | get lo mem vector
        JSR     (A0)                            | and call it
        MOVEM.L (SP)+,D0-D3/A0-A1               | RESTORE REGS
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        MOVE.L  (SP)+,(SP)                      | STRIP 8 BYTES
        RTS                                     | AND RETURN

| .PROC ObscureCursor
| ---------------------------------------------------------
|
| PROCEDURE ObscureCursor;
|
| Hide the cursor image until the next time the mouse moves.
|
ObscureCursor:
        MOVE.L  (JCrsrObscure).w,A0             | get lo mem vector
        JMP     (A0)                            | and call it


