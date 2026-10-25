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

| ASCII art:
|  ***   *   *    *    *      ***
| *   *  *   *   * *   *     *   *
| *   *  *   *  *   *  *     *
| *   *  *   *  *   *  *      ***
| *   *  *   *  *****  *         *
| *   *   * *   *   *  *     *   *
|  ***     *    *   *  *****  ***
|
| .PROC StdOval,2
| .REF CheckPic,PutPicVerb,PutPicRect
| .REF PutOval,PushVerb,DrawArc
| ---------------------------------------------------------------
|
| PROCEDURE StdOval(verb: GrafVerb; r: Rect);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|   VERB +0xC byte (GrafVerb), RECT +0x8 long (addr-of-rect)
|   OVWD -2 word, OVHT -4 word (locals)
|
STDOVAL:
    LINK        A6,#-0x4                        | ALLOCATE STACK FRAME
    MOVEM.L     D7/A3-A4,-(A7)                  | SAVE REGS
    MOVE.B      0xC(A6),D7                      | GET VERB
    JSR         CHECKPIC(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
    BLE.B       STDOVAL_NOTPIC                  | BRANCH IF NOT PICSAVE
    MOVE.B      D7,-(A7)                        | PUSH VERB
    JSR         PUTPICVERB(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
    MOVEQ.L     #0x50,D0                        | PUT OVALNOUN IN HI NIBBLE
    ADD.W       D7,D0                           | PUT VERB IN LO NIBBLE
    MOVE.B      D0,-(A7)                        | PUSH OPCODE
    MOVE.L      0x8(A6),-(A7)                   | PUSH ADDR OF RECT
    JSR         PUTPICRECT(PC)                  | PUT OPCODE AND RECTANGLE
STDOVAL_NOTPIC:
    MOVEA.L     0x8(A6),A0                      | POINT TO RECT
    MOVE.W      0x6(A0),D0                      | GET RECT.RIGHT
    SUB.W       0x2(A0),D0                      | SUBTRACT RECT.LEFT TO GET WIDTH
    MOVE.W      D0,-0x2(A6)                     | OVWD := R.RIGHT - R.LEFT
    MOVE.W      0x4(A0),D0                      | GET RECT.BOTTOM
    SUB.W       (A0),D0                         | SUBTRACT RECT.TOP TO GET HEIGHT
    MOVE.W      D0,-0x4(A6)                     | OVHT := R.BOTTOM - R.TOP
    MOVE.L      A0,-(A7)                        | PUSH ADDR OF RECT
    TST.B       D7                              | IS VERB FRAME ?
    BNE.B       NOTFR                           | NO, CONTINUE
    TST.L       0x60(A3)                        | YES, IS RGNSAVE TRUE ?
    BEQ.B       STDOVAL_NOTRGN                  | NO, CONTINUE
    MOVE.L      A0,-(A7)                        | YES, PUSH ADDR OF RECT
    MOVE.L      -0x4(A6),-(A7)                  | PUSH OVWD, OVHT
    MOVE.L      -0x94(A4),-(A7)                 | PUSH RGNBUF
    PEA.L       -0x96(A4)                       | PUSH VAR RGNINDEX
    PEA.L       -0x98(A4)                       | PUSH VAR RGNMAX
    JSR         PUTOVAL(PC)                     | ADD AN OVAL TO THERGN
STDOVAL_NOTRGN:
    MOVE.B      #0x1,-(A7)                      | NOTRGN: PUSH HOLLOW = TRUE
    BRA.B       STDOVAL_DOIT                    | SHARE COMMON CODE
| ----------------------------------------------------------
|
| NOTFR
|
NOTFR:
    CLR.B       -(A7)                           | PUSH HOLLOW = FALSE
STDOVAL_DOIT:
    MOVE.L      -0x4(A6),-(A7)                  | PUSH OVWD,OVHT
    JSR         PUSHVERB(PC)                    | PUSH MODE AND PATTERN
    CLR.W       -(A7)                           | PUSH STARTANGLE = 0
    MOVE.W      #0x168,-(A7)                    | PUSH ARCANGLE = 360
| DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng);
    JSR         DRAWARC(PC)                     | DO THE ACTUAL DRAWING
    MOVEM.L     (A7)+,D7/A3-A4                  | RESTORE REGS
    UNLK        A6                              | DESTROY STACK FRAME
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDRESS
    ADDQ.W      #0x6,A7                         | STRIP PARAMS
    JMP         (A0)                            | RETURN TO CALLER
| .PROC FrameOval,1
| .DEF CallOval,PaintOval,EraseOval,InvertOval,FillOval
| .REF StdOval
| -----------------------------------------------------
|
| PROCEDURE FrameOval(* r: Rect *);
|
FRAMEOVAL:
    MOVEQ.L     #0x0,D0                         | VERB = FRAME
    BRA.B       CALLOVAL                        | SHARE COMMON CODE
| -----------------------------------------------------
|
| PROCEDURE PaintOval(* r: Rect *);
|
PAINTOVAL:
    MOVEQ.L     #0x1,D0                         | VERB = PAINT
    BRA.B       CALLOVAL                        | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE EraseOval(* r: Rect *);
|
ERASEOVAL:
    MOVEQ.L     #0x2,D0                         | VERB = ERASE
    BRA.B       CALLOVAL                        | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE InvertOval(* r: Rect *);
|
INVERTOVAL:
    MOVEQ.L     #0x3,D0                         | VERB = INVERT
    BRA.B       CALLOVAL                        | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE FillOval(* r: Rect; pat: Pattern *);
|
FILLOVAL:
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDR
    MOVEA.L     (A7)+,A1                        | POP ADDR OF PATTERN
    MOVE.L      A0,-(A7)                        | PUT RETURN ADDR BACK
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    LEA.L       0x28(A0),A0                     | POINT TO FILLPAT
    MOVE.L      (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
    MOVE.L      (A1)+,(A0)+                     | ALL EIGHT BYTES
    MOVEQ.L     #0x4,D0                         | VERB = FILL
    NOP                                         | PADDING FOR FALLTHROUGH
| ---------------------------------------------------------------
|
| PROCEDURE CallOval(r: Rect);
|
| code shared by FrameOval, PaintOval, EraseOval, InvertOval, and FillOval.
| enter with verb in D0.
|
CALLOVAL:
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDR
    MOVEA.L     (A7)+,A1                        | POP ADDR OF RECT
    MOVE.B      D0,-(A7)                        | PUSH VERB
    MOVE.L      A1,-(A7)                        | PUSH ADDR OF RECT
    MOVE.L      A0,-(A7)                        | RESTORE RETURN ADDR
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    MOVE.L      0x68(A0),D0                     | IS GRAFPROCS NIL ?
    MOVEA.L     (0x10D8).W,A0                   | _StdOval (ovalProc)
    BEQ.B       CALLOVAL_USESTD                 | YES, USE STD PROC
    MOVEA.L     D0,A0                           | PUT PROC PTR IN A0
    MOVEA.L     0x10(A0),A0                     | NO, GET PROC PTR
CALLOVAL_USESTD:
    JMP         (A0)                            | USESTD: GO TO IT
