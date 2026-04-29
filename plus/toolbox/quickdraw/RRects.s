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
|

| .PROC StdRRect,4
| .REF CheckPic,DPutPicByte,PutPicVerb,PutPicLong,PutPicRect
| .REF PutOval,PushVerb,DrawArc
| ---------------------------------------------------------------
|
| PROCEDURE StdRRect(verb: GrafVerb; r: Rect; ovWd,ovHt: INTEGER);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| Called during boot.
StdRRect:
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set VERB, PARAMSIZE+8-2                        | GRAFVERB
.set RECT, VERB-4                               | LONG, ADDR OF RECT
.set OVWD, RECT-2                               | WORD
.set OVHT, OVWD-2                               | WORD

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.B  0x10(A6),D7                     | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.B   STDRRECT_NOTPIC                 | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC

|
| CHECK FOR NEW OVAL SIZE
|
        MOVE.L  PICSAVE(A3),A0                  | GET PICSAVE HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE PICSAVE
        MOVE.L  0x8(A6),D0                      | GET OVWD AND OVHT
        CMP.L   PICOVSIZE(A0),D0                | SAME AS CURRENT OVAL SIZE ?
        BEQ.B   OVALOK                          | YES, CONTINUE
        MOVE.L  D0,PICOVSIZE(A0)                | NO, UPDATE STATE VARIABLE
        MOVE.L  D0,-(SP)                        | PUSH OVSIZE FOR PutPicLong CALL
        MOVEQ.L #0xB,D0                         | SET OPCODE TO PICOVSIZE
        JSR     DPutPicByte(PC)                 | PUT OVSIZE OPCODE
        JSR     PutPicLong(PC)                  | PUT NEW OVAL SIZE DATA
OVALOK:
        MOVEQ.L #0x40,D0                        | PUT RRECT NOUN IN HI NIBBLE
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | PUSH OPCODE
        MOVE.L  0xC(A6),-(SP)                   | PUSH ADDR OF RECT
        JSR     PutPicRect(PC)                  | PUT OPCODE AND RECTANGLE
STDRRECT_NOTPIC:
        MOVE.L  0xC(A6),-(SP)                   | PUSH ADDR OF RECT
        CLR.B   -(SP)                           | PUSH HOLLOW = FALSE
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDRRECT_DOIT                   | NO, CONTINUE
        TST.L   RGNSAVE(A3)                     | YES, IS RGNSAVE TRUE ?
        BEQ.B   STDRRECT_NOTRGN                 | NO, CONTINUE
        MOVE.L  0xC(A6),-(SP)                   | YES, PUSH ADDR OF RECT
        MOVE.L  0x8(A6),-(SP)                   | PUSH OVWD, OVHT
        MOVE.L  RGNBUF(A4),-(SP)                | PUSH RGNBUF
        PEA.L   RGNINDEX(A4)                    | PUSH VAR RGNINDEX
        PEA.L   RGNMAX(A4)                      | PUSH VAR RGNMAX
        JSR     PutOval(PC)                     | ADD AN OVAL TO THERGN
STDRRECT_NOTRGN:
        MOVE.B  #1,(SP)                         | NOTRGN: REPLACE, PUSH HOLLOW = TRUE
STDRRECT_DOIT:
        MOVE.L  0x8(A6),-(SP)                   | PUSH OVWD,OVHT
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        CLR     -(SP)                           | PUSH STARTANGLE = 0
        MOVE    #360,-(SP)                      | PUSH ARCANGLE = 360

| DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng);
        JSR     DrawArc(PC)                     | CALL DRAWARC
        MOVEM.L (SP)+,D7/A3-A4                  | RESTORE REGS
        UNLK    A6                              | UNLINK STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xA,SP                         | STRIP 10 BYTES OF PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC FrameRoundRect,3
| .DEF CallRRect,PaintRoundRect,EraseRoundRect
| .DEF InvertRoundRect,FillRoundRect
| .REF StdRRect
| --------------------------------------------------------
|
| PROCEDURE FrameRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
| Called during boot.
FrameRoundRect:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        BRA.B   CallRRect                       | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE PaintRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
PaintRoundRect:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        BRA.B   CallRRect                       | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE EraseRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
| Called during boot.
EraseRoundRect:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        BRA.B   CallRRect                       | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE InvertRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
| Called during boot.
InvertRoundRect:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        BRA.B   CallRRect                       | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE FillRoundRect(r: Rect; ovWd,ovHt: INTEGER; pat: Pattern);
|
| Called during boot.
FillRoundRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | POINT TO LISAGRAF GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L   FILLPAT(A0),A0                  | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        NOP                                     | SHARE COMMON CODE (FALLTHROUGH)

| ---------------------------------------------------------------
|
| PROCEDURE CallRRect(r: Rect; ovWd,ovHt: INTEGER);
|
| code shared by FrameRoundRect, PaintRoundRect, EraseRoundRect,
| InvertRoundRect, and FillRoundRect.
| enter with verb in D0.
|
| Called during boot.
CallRRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | POP ovWd and ovHt
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT
        MOVE.L  D1,-(SP)                        | PUSH ovWd and ovHt
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO LISAGRAF GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xEBC).w,A0                    | _StdRRect (rRectProc)
        BEQ.B   CALLRRECT_USESTD                | YES, USE STD PROC
        MOVE.L  D0,A0                           | SET UP GRAFPROCS POINTER
        MOVE.L  RRECTPROC(A0),A0                | NO, GET PROC PTR
CALLRRECT_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT


