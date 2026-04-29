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
|


| .PROC StdOval,2
| .REF CheckPic,PutPicVerb,PutPicRect
| .REF PutOval,PushVerb,DrawArc
| ---------------------------------------------------------------
|
| PROCEDURE StdOval(verb: GrafVerb; r: Rect);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| PARAMSIZE .EQU 6
| VERB .EQU PARAMSIZE+8-2 ;GRAFVERB
| RECT .EQU VERB-4 ;LONG, ADDR OF RECT
StdOval:
        LINK    A6,#-0x4                        | ALLOCATE STACK FRAME

| OVWD .EQU -2 ;WORD
| OVHT .EQU OVWD-2 ;WORD
| VARSIZE .EQU OVHT ;TOTAL BYTES OF LOCALS

| -----------------------------------------------------------
.set PARAMSIZE, 6                               | TOTAL BYTES OF PARAMS
.set VERB, PARAMSIZE+8-2                        | GRAFVERB
.set RECT, VERB-4                               | LONG, ADDR OF RECT

.set OVWD, -2                                   | WORD
.set OVHT, OVWD-2                               | WORD
.set VARSIZE, OVHT                              | TOTAL BYTES OF LOCALS

        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.B  0xC(A6),D7                      | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.B   STDOVAL_NOTPIC                  | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVEQ.L #0x50,D0                        | PUT OVALNOUN IN HI NIBBLE
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | PUSH OPCODE
        MOVE.L  0x8(A6),-(SP)                   | PUSH ADDR OF RECT
        JSR     PutPicRect(PC)                  | PUT OPCODE AND RECTANGLE
STDOVAL_NOTPIC:
        MOVE.L  0x8(A6),A0                      | POINT TO RECT
        MOVE    RIGHT(A0),D0                    | GET RECT.RIGHT
        SUB     LEFT(A0),D0                     | SUBTRACT RECT.LEFT TO GET WIDTH
        MOVE    D0,-0x2(A6)                     | OVWD := R.RIGHT - R.LEFT
        MOVE    BOTTOM(A0),D0                   | GET RECT.BOTTOM
        SUB     (A0),D0                         | SUBTRACT RECT.TOP TO GET HEIGHT
        MOVE    D0,-0x4(A6)                     | OVHT := R.BOTTOM - R.TOP
        MOVE.L  A0,-(SP)                        | PUSH ADDR OF RECT
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   NOTFR                           | NO, CONTINUE
        TST.L   RGNSAVE(A3)                     | YES, IS RGNSAVE TRUE ?
        BEQ.B   STDOVAL_NOTRGN                  | NO, CONTINUE
        MOVE.L  A0,-(SP)                        | YES, PUSH ADDR OF RECT
        MOVE.L  -0x4(A6),-(SP)                  | PUSH OVWD, OVHT
        MOVE.L  RGNBUF(A4),-(SP)                | PUSH RGNBUF
        PEA.L   RGNINDEX(A4)                    | PUSH VAR RGNINDEX
        PEA.L   RGNMAX(A4)                      | PUSH VAR RGNMAX
        JSR     PutOval(PC)                     | ADD AN OVAL TO THERGN
STDOVAL_NOTRGN:
        MOVE.B  #1,-(SP)                        | NOTRGN: PUSH HOLLOW = TRUE
        BRA.B   STDOVAL_DOIT                    | SHARE COMMON CODE

| ----------------------------------------------------------
|
| NOTFR
|
NOTFR:
        CLR.B   -(SP)                           | PUSH HOLLOW = FALSE
STDOVAL_DOIT:
        MOVE.L  -0x4(A6),-(SP)                  | PUSH OVWD,OVHT
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        CLR     -(SP)                           | PUSH STARTANGLE = 0
        MOVE    #360,-(SP)                      | PUSH ARCANGLE = 360

| DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng);
        JSR     DrawArc(PC)                     | DO THE ACTUAL DRAWING
        MOVEM.L (SP)+,D7/A3-A4                  | RESTORE REGS
        UNLK    A6                              | DESTROY STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x6,SP                         | STRIP PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC FrameOval,1
| .DEF CallOval,PaintOval,EraseOval,InvertOval,FillOval
| .REF StdOval
| -----------------------------------------------------
|
| PROCEDURE FrameOval(* r: Rect *);
|
FrameOval:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        BRA.B   CallOval                        | SHARE COMMON CODE

| -----------------------------------------------------
|
| PROCEDURE PaintOval(* r: Rect *);
|
PaintOval:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        BRA.B   CallOval                        | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE EraseOval(* r: Rect *);
|
EraseOval:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        BRA.B   CallOval                        | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE InvertOval(* r: Rect *);
|
InvertOval:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        BRA.B   CallOval                        | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE FillOval(* r: Rect; pat: Pattern *);
|
FillOval:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | POINT TO LISAGRAF GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L   FILLPAT(A0),A0                  | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        NOP                                     | PADDING FOR FALLTHROUGH

| ---------------------------------------------------------------
|
| PROCEDURE CallOval(r: Rect);
|
| code shared by FrameOval, PaintOval, EraseOval, InvertOval, and FillOval.
| enter with verb in D0.
|
CallOval:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO LISAGRAF GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xED8).w,A0                    | _StdOval (ovalProc)
        BEQ.B   CALLOVAL_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | PUT PROC PTR IN A0
        MOVE.L  OVALPROC(A0),A0                 | NO, GET PROC PTR
CALLOVAL_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT


