| -----------------------------------------------------------
|
|
|     ****   ****   *****   ***   *****   ***
|     *   *  *   *  *      *   *    *    *   *
|     *   *  *   *  *      *        *    *
|     ****   ****   ***    *        *     ***
|     * *    * *    *      *        *        *
|     *  *   *  *   *      *   *    *    *   *
|     *   *  *   *  *****   ***     *     ***
|
|
|  procedures for operating on RoundRects.

StdRRect:
        LINK    A6,#0x0                         | set up stack frame, reserve 0x0 locals
        MOVEM.L D7/A3-A4,-(SP)                  | save scratch regs to stack
        MOVE.B  16(A6),D7                       | D7 := maskRgn
        JSR     CheckPic(PC)                    | call CheckPic
        BLE.W   STDRRECT_NOTPIC                 | if signed <= -> STDRRECT_NOTPIC
        MOVE.B  D7,-(SP)                        | push D7
        JSR     PutPicVerb(PC)                  | call PutPicVerb
        MOVE.L  0x5C(A3),A0                     | A0 := 0x5C(A3)
        MOVE.L  (A0),A0                         | A0 := (A0)
        MOVE.L  8(A6),D0                        | D0 := pat
        CMP.L   0x4C(A0),D0                     | compare D0 with 0x4C(A0)
        BEQ.B   OVALOK                          | if zero -> OVALOK
        MOVE.L  D0,0x4C(A0)                     | 0x4C(A0) := D0
        MOVE.L  D0,-(SP)                        | push D0
        MOVE.B  #0xB,-(SP)                      | push #0xB
        JSR     PutPicByte(PC)                  | call PutPicByte
        JSR     PutPicLong(PC)                  | call PutPicLong
OVALOK:
        MOVEQ.L #0x40,D0                        | D0 := #0x40
        ADD     D7,D0                           | D0 += D7
        MOVE.B  D0,-(SP)                        | push D0
        MOVE.L  12(A6),-(SP)                    | -(SP) := mode
        JSR     PutPicRect(PC)                  | call PutPicRect
STDRRECT_NOTPIC:
        MOVE.L  12(A6),-(SP)                    | -(SP) := mode
        TST.B   D7                              | test D7
        BNE.B   STDRRECT_NOTFRM                 | if non-zero -> STDRRECT_NOTFRM
        TST.L   0x60(A3)                        | test 0x60(A3)
        BEQ.B   STDRRECT_NOTRGN                 | if zero -> STDRRECT_NOTRGN
        MOVE.L  12(A6),-(SP)                    | -(SP) := mode
        MOVE.L  8(A6),-(SP)                     | -(SP) := pat
        MOVE.L  -0x94(A4),-(SP)                 | push -0x94(A4)
        PEA.L     -0x96(A4)                     | push effective addr -0x96(A4)
        PEA.L     -0x98(A4)                     | push effective addr -0x98(A4)
        JSR     PutOval(PC)                     | call PutOval
STDRRECT_NOTRGN:
        MOVE.B  #0x1,-(SP)                      | push #0x1
        BRA.B   STDRRECT_DOIT                   | jump to STDRRECT_DOIT
STDRRECT_NOTFRM:
        CLR.B   -(SP)                           | push zero word
STDRRECT_DOIT:
        MOVE.L  8(A6),-(SP)                     | -(SP) := pat
        JSR     PushVerb(PC)                    | pc-relative jsr (was raw .short pair)
        CLR     -(SP)                           | push zero word
        MOVE    #0x168,-(SP)                    | push #0x168
        JSR     DrawArc(PC)                     | call DrawArc
        MOVEM.L (SP)+,D7/A3-A4                  | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0xA,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS

| ---------------------------------------------------------------
| PROCEDURE CallRRect(r: Rect; ovWd,ovHt: INTEGER);
| code shared by FrameRoundRect, PaintRoundRect, EraseRoundRect,
| InverRoundRect, and FillRoundRect.
| enter with verb in D0.
| Called during boot.
CallRRect:
        MOVE.L  (SP)+,A0                        | pop return address into A0
        MOVE.L  (SP)+,D1                        | pop D1
        MOVE.L  (SP)+,A1                        | pop A1
        MOVE.B  D0,-(SP)                        | push D0
        MOVE.L  A1,-(SP)                        | push A1
        MOVE.L  D1,-(SP)                        | push D1
        MOVE.L  A0,-(SP)                        | push A0
        MOVE.L  (A5),A0                         | A0 := (A5)
        MOVE.L  (A0),A0                         | A0 := (A0)
        MOVE.L  0x68(A0),D0                     | D0 := 0x68(A0)
        LEA     StdRRect(PC),A0                 | A0 = &StdRRect(PC)
        BEQ.B   CALLRRECT_CONT                  | if zero -> CALLRRECT_CONT
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  12(A0),A0                       | A0 := 12(A0)
CALLRRECT_CONT:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE FrameRoundRect(r: Rect; ovWd, ovHt: INTEGER);
FrameRoundRect:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE PaintRoundRect(r: Rect; ovWd, ovHt: INTEGER);
PaintRoundRect:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE EraseRoundRect(r: Rect; ovWd, ovHt: INTEGER);
EraseRoundRect:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
|
| _InverRoundRect ($A8B3): invert the pixels inside a rounded-corner rectangle
| Pascal: PROCEDURE InvertRoundRect(r: Rect; ovalWidth, ovalHeight: INTEGER);
| CallRRect with verb invert (3): calls the port's rRectProc (StdRRect if
| grafProcs is nil).
| Apple source name: InvertRoundRect (1983 RRects.a; MacSEROM.lst:
| INVERTROUNDRECT)
|
InverRoundRect:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE FillRoundRect(r: Rect; ovWd, ovHt: INTEGER; pat: Pattern);
FillRoundRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallRRect(PC)                   | SHARE COMMON CODE
