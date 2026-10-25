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

| ASCII art:
| ****   ****   *****   ***   *****   ***
| *   *  *   *  *      *   *    *    *   *
| *   *  *   *  *      *        *    *
| ****   ****   ***    *        *     ***
| * *    * *    *      *        *        *
| *  *   *  *   *      *   *    *    *   *
| *   *  *   *  *****   ***     *     ***
|
| procedures for operating on RoundRects.
|
| .PROC StdRRect,4
| .REF CheckPic,DPutPicByte,PutPicVerb,PutPicLong,PutPicRect
| .REF PutOval,PushVerb,DrawArc
| ---------------------------------------------------------------
|
| PROCEDURE StdRRect(verb: GrafVerb; r: Rect; ovWd,ovHt: INTEGER);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|   VERB +0x10 byte, RECT +0xC long, OVWD +0x8 word, OVHT +0xA word
|
| Called during boot.
STDRRECT:
    LINK	A6,#0x0                                | NO LOCALS
    MOVEM.L	D7/A3-A4,-(A7)                      | SAVE REGS
    MOVE.B	0x10(A6),D7                          | GET VERB
    JSR	CHECKPIC(PC)                            | SET UP A4,A3 AND CHECK PICSAVE
    BLE.B	STDRRECT_NOTPIC                       | BRANCH IF NOT PICSAVE
    MOVE.B	D7,-(A7)                             | PUSH VERB
    JSR	PUTPICVERB(PC)                          | PUT ADDIONAL PARAMS TO THEPIC
|
| CHECK FOR NEW OVAL SIZE
|
    MOVEA.L	0x5C(A3),A0                         | GET PICSAVE HANDLE
    MOVEA.L	(A0),A0                             | DE-REFERENCE PICSAVE
    MOVE.L	0x8(A6),D0                           | GET OVWD AND OVHT
    CMP.L	0x52(A0),D0                           | SAME AS CURRENT OVAL SIZE ?
    BEQ.B	OVALOK                                | YES, CONTINUE
    MOVE.L	D0,0x52(A0)                          | NO, UPDATE STATE VARIABLE
    MOVE.L	D0,-(A7)                             | PUSH OVSIZE FOR PutPicLong CALL
    MOVEQ.L	#0xB,D0                             | SET OPCODE TO PICOVSIZE
    JSR	DPUTPICBYTE(PC)                         | PUT OVSIZE OPCODE
    JSR	PUTPICLONG(PC)                          | PUT NEW OVAL SIZE DATA
OVALOK:
    MOVEQ.L	#0x40,D0                            | PUT RRECT NOUN IN HI NIBBLE
    ADD.W	D7,D0                                 | PUT VERB IN LO NIBBLE
    MOVE.B	D0,-(A7)                             | PUSH OPCODE
    MOVE.L	0xC(A6),-(A7)                        | PUSH ADDR OF RECT
    JSR	PUTPICRECT(PC)                          | PUT OPCODE AND RECTANGLE
STDRRECT_NOTPIC:
    MOVE.L	0xC(A6),-(A7)                        | PUSH ADDR OF RECT
    CLR.B	-(A7)                                 | PUSH HOLLOW = FALSE
    TST.B	D7                                    | IS VERB FRAME ?
    BNE.B	STDRRECT_DOIT                         | NO, CONTINUE
    TST.L	0x60(A3)                              | YES, IS RGNSAVE TRUE ?
    BEQ.B	STDRRECT_NOTRGN                       | NO, CONTINUE
    MOVE.L	0xC(A6),-(A7)                        | YES, PUSH ADDR OF RECT
    MOVE.L	0x8(A6),-(A7)                        | PUSH OVWD, OVHT
    MOVE.L	-0x94(A4),-(A7)                      | PUSH RGNBUF
    PEA.L	-0x96(A4)                             | PUSH VAR RGNINDEX
    PEA.L	-0x98(A4)                             | PUSH VAR RGNMAX
    JSR	PUTOVAL(PC)                             | ADD AN OVAL TO THERGN
STDRRECT_NOTRGN:
    MOVE.B	#0x1,(A7)                            | NOTRGN: REPLACE, PUSH HOLLOW = TRUE
STDRRECT_DOIT:
    MOVE.L	0x8(A6),-(A7)                        | PUSH OVWD,OVHT
    JSR	PUSHVERB(PC)                            | PUSH MODE AND PATTERN
    CLR.W	-(A7)                                 | PUSH STARTANGLE = 0
    MOVE.W	#0x168,-(A7)                         | PUSH ARCANGLE = 360
| DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng);
    JSR	DRAWARC(PC)                             | CALL DRAWARC
    MOVEM.L	(A7)+,D7/A3-A4                      | RESTORE REGS
    UNLK	A6                                     | UNLINK STACK FRAME
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    ADDA.W	#0xA,A7                              | STRIP 10 BYTES OF PARAMETERS
    JMP	(A0)                                    | RETURN TO CALLER
| .PROC FrameRoundRect,3
| .DEF CallRRect,PaintRoundRect,EraseRoundRect
| .DEF InvertRoundRect,FillRoundRect
| .REF StdRRect
| --------------------------------------------------------
|
| PROCEDURE FrameRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
| Called during boot.
FRAMEROUNDRECT:
    MOVEQ.L	#0x0,D0                             | VERB = FRAME
    BRA.B	CALLRRECT                             | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE PaintRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
PAINTROUNDRECT:
    MOVEQ.L	#0x1,D0                             | VERB = PAINT
    BRA.B	CALLRRECT                             | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE EraseRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
| Called during boot.
ERASEROUNDRECT:
    MOVEQ.L	#0x2,D0                             | VERB = ERASE
    BRA.B	CALLRRECT                             | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE InvertRoundRect(* r: Rect; ovWd,ovHt: INTEGER *);
|
| Called during boot.
INVERTROUNDRECT:
    MOVEQ.L	#0x3,D0                             | VERB = INVERT
    BRA.B	CALLRRECT                             | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE FillRoundRect(r: Rect; ovWd,ovHt: INTEGER; pat: Pattern);
|
| Called during boot.
FILLROUNDRECT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVEA.L	(A7)+,A1                            | POP ADDR OF PATTERN
    MOVE.L	A0,-(A7)                             | PUT RETURN ADDR BACK
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    LEA.L	0x28(A0),A0                           | POINT TO FILLPAT
    MOVE.L	(A1)+,(A0)+                          | COPY PAT INTO FILLPAT
    MOVE.L	(A1)+,(A0)+                          | ALL EIGHT BYTES
    MOVEQ.L	#0x4,D0                             | VERB = FILL
    NOP                                         | SHARE COMMON CODE (FALLTHROUGH)
| ---------------------------------------------------------------
|
| PROCEDURE CallRRect(r: Rect; ovWd,ovHt: INTEGER);
|
| code shared by FrameRoundRect, PaintRoundRect, EraseRoundRect,
| InvertRoundRect, and FillRoundRect.
| enter with verb in D0.
|
| Called during boot.
CALLRRECT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVE.L	(A7)+,D1                             | POP ovWd and ovHt
    MOVEA.L	(A7)+,A1                            | POP ADDR OF RECT
    MOVE.B	D0,-(A7)                             | PUSH VERB
    MOVE.L	A1,-(A7)                             | PUSH ADDR OF RECT
    MOVE.L	D1,-(A7)                             | PUSH ovWd and ovHt
    MOVE.L	A0,-(A7)                             | RESTORE RETURN ADDR
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    MOVE.L	0x68(A0),D0                          | IS GRAFPROCS NIL ?
    MOVEA.L	(0x10BC).W,A0                       | _StdRRect (rRectProc)
    BEQ.B	CALLRRECT_USESTD                      | YES, USE STD PROC
    MOVEA.L	D0,A0                               | SET UP GRAFPROCS POINTER
    MOVEA.L	0xC(A0),A0                          | NO, GET PROC PTR
CALLRRECT_USESTD:
    JMP	(A0)                                    | USESTD: GO TO IT
