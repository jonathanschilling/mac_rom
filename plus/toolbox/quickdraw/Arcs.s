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
|

| .PROC StdArc,4
| .REF CheckPic,PutPicVerb,PutPicWord,PutPicRect
| .REF PushVerb,DrawArc
| ---------------------------------------------------------------
|
| PROCEDURE StdArc(verb: GrafVerb; r: Rect; startAngle,arcAngle: INTEGER);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
StdArc:
        LINK    A6,#-0x4                        | ALLOCATE STACK FRAME

.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set VERB, PARAMSIZE+8-2                        | GRAFVERB
.set RECT, VERB-4                               | LONG, ADDR OF RECT
.set STARTANG, RECT-2                           | WORD
.set ARCANG, STARTANG-2                         | WORD

.set OVWD, -2                                   | WORD
.set OVHT, OVWD-2                               | WORD
.set VARSIZE, OVHT                              | TOTAL BYTES OF LOCALS

        MOVEM.L D4/D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.B  0x10(A6),D7                     | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.B   NOTPIC                          | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVEQ.L #0x60,D0                        | PUT ARCNOUN IN HI NIBBLE
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | PUSH OPCODE
        MOVE.L  0xC(A6),-(SP)                   | PUSH ADDR OF RECT
        JSR     PutPicRect(PC)                  | PUT OPCODE AND RECTANGLE
        MOVE    0xA(A6),-(SP)                   | PUSH STARTANGLE
        JSR     PutPicWord(PC)                  | PUT STARTANGLE
        MOVE    0x8(A6),-(SP)                   | PUSH ARCANGLE
        JSR     PutPicWord(PC)                  | PUT ARCANGLE
NOTPIC:
        MOVE.L  0xC(A6),A0                      | POINT TO RECT
        MOVE    RIGHT(A0),D0                    | GET RIGHT COORDINATE
        SUB     LEFT(A0),D0                     | SUBTRACT LEFT TO GET WIDTH
        MOVE    D0,-0x2(A6)                     | OVWD := R.RIGHT - R.LEFT
        MOVE    BOTTOM(A0),D0                   | GET BOTTOM COORDINATE
        SUB     (A0),D0                         | SUBTRACT TOP TO GET HEIGHT
        MOVE    D0,-0x4(A6)                     | OVHT := R.BOTTOM - R.TOP
        MOVE.L  A0,-(SP)                        | PUSH ADDR OF RECT
        CLR.B   -(SP)                           | PUSH HOLLOW = FALSE
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   DOIT                            | NO, CONTINUE

|
| Currently, FrameArc does not put inversion points to theRgn.
| If this changes, add test and call to PutArc here.
|
        MOVE.B  #1,(SP)                         | REPLACE, PUSH HOLLOW = TRUE
DOIT:
        MOVE.L  -0x4(A6),-(SP)                  | PUSH OVWD,OVHT
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        MOVE    0xA(A6),-(SP)                   | PUSH STARTANGLE
        MOVE    0x8(A6),-(SP)                   | PUSH ARCANGLE

| DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng);
        JSR     DrawArc(PC)                     | DRAW THE ARC
        MOVEM.L (SP)+,D4/D7/A3-A4               | RESTORE REGS
        UNLK    A6                              | DESTROY STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xA,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC FrameArc,3
| .DEF CallArc,PaintArc,EraseArc,InvertArc,FillArc
| .REF STDARC
| -----------------------------------------------------
|
| PROCEDURE FrameArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
FrameArc:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        BRA.B   CallArc                         | SHARE COMMON CODE

| -----------------------------------------------------
|
| PROCEDURE PaintArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
PaintArc:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        BRA.B   CallArc                         | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE EraseArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
EraseArc:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        BRA.B   CallArc                         | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE InvertArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
InvertArc:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        BRA.B   CallArc                         | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE FillArc(* r: Rect; startAngle,arcAngle: INTEGER; pat: Pattern *);
|
FillArc:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L   FILLPAT(A0),A0                  | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        NOP                                     | FALL THROUGH TO CALLARC

| ---------------------------------------------------------------
|
| PROCEDURE CallArc(r: Rect; startAngle,arcAngle: INTEGER);
|
| code shared by FrameArc, PaintArc, EraseArc, InvertArc, and FillArc.
| enter with verb in D0.
|
CallArc:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | POP BOTH ANGLES
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT
        MOVE.L  D1,-(SP)                        | PUSH BOTH ANGLES
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xEF4).w,A0                    | _StdArc (arcProc)
        BEQ.B   USESTD                          | YES, USE STD PROC
        MOVE.L  D0,A0                           | POINT TO QDPROCS RECORD
        MOVE.L  ARCPROC(A0),A0                  | NO, GET PROC PTR
USESTD:
        JMP     (A0)                            | GO TO IT


