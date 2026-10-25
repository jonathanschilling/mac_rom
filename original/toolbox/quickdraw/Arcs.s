| -----------------------------------------------------------
|
|
|       *    *****    ***    ***
|      * *   *    *  *   *  *   *
|     *   *  *    *  *      *
|     *   *  *****   *       ***
|     *****  *  *    *          *
|     *   *  *   *   *   *  *   *
|     *   *  *    *   ***    ***
|
| Procedures for drawing Arcs:

| .PROC StdArc,4
| .REF CheckPic, PutPicVerb, PutPicWord, PutPicRect
| .REF PushVerb, DrawArc
| ----------------------------------------------------------
| PROCEDURE StdArc(verb: GrafVerb; r: Rect;
| startAngle, arcAngle: INTEGER);
|
| Standard QuickDraw arc bottleneck. Pushed-args layout:
| 16(A6) = verb (byte), 12(A6) = rectPtr,
| 10(A6) = startAngle, 8(A6) = arcAngle.
| Called during boot.
StdArc:
        LINK    A6,#-0x4                        | ALLOCATE STACK FRAME
        MOVEM.L D4/D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.B  16(A6),D7                       | GET VERB
        JSR     CheckPic(PC)                    | CheckPic -- sets up A3,A4
        BLE.W   STDARC_NOTPIC                   | branch if not picSave
        MOVE.B  D7,-(SP)                        | push verb for picture record
        JSR     PutPicVerb(PC)                  | record verb in current picture
        MOVEQ.L #0x60,D0                        | SET DEVICE TO 0
        ADD     D7,D0                           | put verb into low nibble (arc opcode)
        MOVE.B  D0,-(SP)                        | push opcode byte
        MOVE.L  12(A6),-(SP)                    | push addr of dst rect
        JSR     PutPicRect(PC)                  | record opcode + rect to picture
        MOVE    10(A6),-(SP)                    | push startAngle
        JSR     PutPicWord(PC)                  | record startAngle to picture
        MOVE    8(A6),-(SP)                     | push arcAngle
        JSR     PutPicWord(PC)                  | record arcAngle to picture
STDARC_NOTPIC:
        MOVE.L  12(A6),A0                       | A0 := dst rect ptr
        MOVE    6(A0),D0                        | get rect.right
        SUB     2(A0),D0                        | ovWd := rect.right - rect.left
        MOVE    D0,-2(A6)                       | save ovWd local
        MOVE    4(A0),D0                        | get rect.bottom
        SUB     (A0),D0                         | ovHt := rect.bottom - rect.top
        MOVE    D0,-4(A6)                       | save ovHt local
        MOVE.L  A0,-(SP)                        | push addr of rect (DrawArc arg)
        TST.B   D7                              | is verb FRAME (= 0)?
        BNE.B   STDARC_NOTFR                    | no, push hollow=FALSE
        MOVE.B  #0x1,-(SP)                      | yes, push hollow=TRUE
        BRA.B   DOIT                            | skip past hollow=FALSE branch
STDARC_NOTFR:
        CLR.B   -(SP)                           | push hollow=FALSE for non-frame verbs
DOIT:
        MOVE.L  -4(A6),-(SP)                    | push ovHt + ovWd as long
        JSR     PushVerb(PC)                    | pc-relative jsr (was raw .short pair)
        MOVE    10(A6),-(SP)                    | push startAngle to DrawArc
        MOVE    8(A6),-(SP)                     | push arcAngle to DrawArc
        JSR     DrawArc(PC)                     | DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng)
        MOVEM.L (SP)+,D4/D7/A3-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS
| Called by: FrameArc, PaintArc, EraseArc, InvertArc, FillArc
CallArc:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVE.L  (SP)+,D1                        | pop both angles as long
        MOVE.L  (SP)+,A1                        | pop addr of rect
        MOVE.B  D0,-(SP)                        | push verb byte
        MOVE.L  A1,-(SP)                        | push addr of rect
        MOVE.L  D1,-(SP)                        | push both angles
        MOVE.L  A0,-(SP)                        | restore return address
        MOVE.L  (A5),A0                         | A0 := QuickDraw globals
        MOVE.L  (A0),A0                         | A0 := thePort
        MOVE.L  0x68(A0),D0                     | D0 := grafProcs (NIL means use Std)
        LEA     StdArc(PC),A0                   | A0 := StdArc as default
        BEQ.B   CALLARC_USESTD                  | grafProcs NIL? use std proc
        MOVE.L  D0,A0                           | A0 := grafProcs ptr
        MOVE.L  20(A0),A0                       | A0 := arcProc field
CALLARC_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| ----------------------------------------------------------
| PROCEDURE FrameArc(* r: Rect; startAngle, arcAngle: INTEGER *);
FrameArc:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE PaintArc(* r: Rect; startAngle, arcAngle: INTEGER *);
PaintArc:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE EraseArc(* r: Rect; startAngle, arcAngle: INTEGER *);
EraseArc:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE InvertArc(* r: Rect; startAngle, arcAngle: INTEGER *);
InvertArc:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE FillArc(* r: Rect; startAngle, arcAngle: INTEGER;
| pat: Pattern *);
FillArc:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT (FILLPAT@$28)
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallArc(PC)                     | SHARE COMMON CODE

