| -----------------------------------------------------------
|
|
|      ***   *   *    *    *      ***
|     *   *  *   *   * *   *     *   *
|     *   *  *   *  *   *  *     *
|     *   *  *   *  *   *  *      ***
|     *   *  *   *  *****  *         *
|     *   *   * *   *   *  *     *   *
|      ***     *    *   *  *****  ***

StdOval:
        LINK    A6,#-0x4                        | set up stack frame, reserve -0x4 locals
        MOVEM.L D7/A3-A4,-(SP)                  | save scratch regs to stack
        MOVE.B  12(A6),D7                       | D7 := mode
        JSR     CheckPic(PC)                    | call CheckPic
        BLE.W   STDOVAL_NOTPIC                  | if signed <= -> STDOVAL_NOTPIC
        MOVE.B  D7,-(SP)                        | push D7
        JSR     PutPicVerb(PC)                  | call PutPicVerb
        MOVEQ.L #0x50,D0                        | D0 := #0x50
        ADD     D7,D0                           | D0 += D7
        MOVE.B  D0,-(SP)                        | push D0
        MOVE.L  8(A6),-(SP)                     | -(SP) := pat
        JSR     PutPicRect(PC)                  | call PutPicRect
STDOVAL_NOTPIC:
        MOVE.L  8(A6),A0                        | A0 := pat
        MOVE    6(A0),D0                        | D0 := 6(A0)
        SUB     2(A0),D0                        | D0 -= 2(A0)
        MOVE    D0,-2(A6)                       | -2(A6) := D0
        MOVE    4(A0),D0                        | D0 := 4(A0)
        SUB     (A0),D0                         | D0 -= (A0)
        MOVE    D0,-4(A6)                       | -4(A6) := D0
        MOVE.L  A0,-(SP)                        | push A0
        TST.B   D7                              | test D7
        BNE.B   NOTFR                           | if non-zero -> NOTFR
        TST.L   0x60(A3)                        | test 0x60(A3)
        BEQ.B   STDOVAL_NOTRGN                  | if zero -> STDOVAL_NOTRGN
        MOVE.L  A0,-(SP)                        | push A0
        MOVE.L  -4(A6),-(SP)                    | push -4(A6)
        MOVE.L  -0x94(A4),-(SP)                 | push -0x94(A4)
        PEA.L     -0x96(A4)                     | push effective addr -0x96(A4)
        PEA.L     -0x98(A4)                     | push effective addr -0x98(A4)
        JSR     PutOval(PC)                     | call PutOval
STDOVAL_NOTRGN:
        MOVE.B  #0x1,-(SP)                      | push #0x1
        BRA.B   STDOVAL_DOIT                    | LOOP BACK FOR NEXT ROW
NOTFR:
        CLR.B   -(SP)                           | push zero word
STDOVAL_DOIT:
        MOVE.L  -4(A6),-(SP)                    | push -4(A6)
        JSR     PushVerb(PC)                    | pc-relative jsr (was raw .short pair)
        CLR     -(SP)                           | push zero word
        MOVE    #0x168,-(SP)                    | push #0x168
        JSR     DrawArc(PC)                     | call DrawArc
        MOVEM.L (SP)+,D7/A3-A4                  | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDQ.W  #0x6,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| CallOval -- verb-dispatch helper used by Frame/Paint/Erase/Invert/
| FillOval. Pops verb in D0, looks up ovalProc via QDProcs or
| falls back to StdOval.
CallOval:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  0x68(A0),D0                     | IS GRAFPROCS NIL ?
        LEA     StdOval(PC),A0                  | _StdOval (ovalProc)
        BEQ.B   CALLOVAL_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | NO, GET PROC PTR
        MOVE.L  16(A0),A0                       | GET ovalProc
CALLOVAL_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| ----------------------------------------------------------
| PROCEDURE FrameOval(r: Rect).
FrameOval:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE PaintOval(r: Rect).
PaintOval:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE EraseOval(r: Rect).
EraseOval:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE InvertOval(r: Rect).
InvertOval:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE FillOval(r: Rect; pat: Pattern).
FillOval:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallOval(PC)                    | SHARE COMMON CODE

