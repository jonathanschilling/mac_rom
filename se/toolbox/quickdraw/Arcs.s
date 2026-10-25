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

| ASCII art:
|     *    *****    ***    ***
|    * *   *    *  *   *  *   *
|   *   *  *    *  *      *
|   *   *  *****   *       ***
|   *****  *  *    *          *
|   *   *  *   *   *   *  *   *
|   *   *  *    *   ***    ***
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
|   VERB +0x10 byte, RECT +0xC long, STARTANG +0xA word, ARCANG +0x8 word
|   OVWD -2 word, OVHT -4 word (locals)
|
STDARC:
    LINK        A6,#-0x4                        | ALLOCATE STACK FRAME
    MOVEM.L     D4/D7/A3-A4,-(A7)               | SAVE REGS
    MOVE.B      0x10(A6),D7                     | GET VERB
    JSR         CHECKPIC(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
    BLE.B       NOTPIC                          | BRANCH IF NOT PICSAVE
    MOVE.B      D7,-(A7)                        | PUSH VERB
    JSR         PUTPICVERB(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
    MOVEQ.L     #0x60,D0                        | PUT ARCNOUN IN HI NIBBLE
    ADD.W       D7,D0                           | PUT VERB IN LO NIBBLE
    MOVE.B      D0,-(A7)                        | PUSH OPCODE
    MOVE.L      0xC(A6),-(A7)                   | PUSH ADDR OF RECT
    JSR         PUTPICRECT(PC)                  | PUT OPCODE AND RECTANGLE
    MOVE.W      0xA(A6),-(A7)                   | PUSH STARTANGLE
    JSR         PUTPICWORD(PC)                  | PUT STARTANGLE
    MOVE.W      0x8(A6),-(A7)                   | PUSH ARCANGLE
    JSR         PUTPICWORD(PC)                  | PUT ARCANGLE
NOTPIC:
    MOVEA.L     0xC(A6),A0                      | POINT TO RECT
    MOVE.W      0x6(A0),D0                      | GET RIGHT COORDINATE
    SUB.W       0x2(A0),D0                      | SUBTRACT LEFT TO GET WIDTH
    MOVE.W      D0,-0x2(A6)                     | OVWD := R.RIGHT - R.LEFT
    MOVE.W      0x4(A0),D0                      | GET BOTTOM COORDINATE
    SUB.W       (A0),D0                         | SUBTRACT TOP TO GET HEIGHT
    MOVE.W      D0,-0x4(A6)                     | OVHT := R.BOTTOM - R.TOP
    MOVE.L      A0,-(A7)                        | PUSH ADDR OF RECT
    CLR.B       -(A7)                           | PUSH HOLLOW = FALSE
    TST.B       D7                              | IS VERB FRAME ?
    BNE.B       DOIT                            | NO, CONTINUE
|
| Currently, FrameArc does not put inversion points to theRgn.
| If this changes, add test and call to PutArc here.
|
    MOVE.B      #0x1,(A7)                       | REPLACE, PUSH HOLLOW = TRUE
DOIT:
    MOVE.L      -0x4(A6),-(A7)                  | PUSH OVWD,OVHT
    JSR         PUSHVERB(PC)                    | PUSH MODE AND PATTERN
    MOVE.W      0xA(A6),-(A7)                   | PUSH STARTANGLE
    MOVE.W      0x8(A6),-(A7)                   | PUSH ARCANGLE
| DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng);
    JSR         DRAWARC(PC)                     | DRAW THE ARC
    MOVEM.L     (A7)+,D4/D7/A3-A4               | RESTORE REGS
    UNLK        A6                              | DESTROY STACK FRAME
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDRESS
    ADDA.W      #0xA,A7                         | STRIP PARAMETERS
    JMP         (A0)                            | RETURN TO CALLER
| .PROC FrameArc,3
| .DEF CallArc,PaintArc,EraseArc,InvertArc,FillArc
| .REF STDARC
| -----------------------------------------------------
|
| PROCEDURE FrameArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
FRAMEARC:
    MOVEQ.L     #0x0,D0                         | VERB = FRAME
    BRA.B       CALLARC                         | SHARE COMMON CODE
| -----------------------------------------------------
|
| PROCEDURE PaintArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
PAINTARC:
    MOVEQ.L     #0x1,D0                         | VERB = PAINT
    BRA.B       CALLARC                         | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE EraseArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
ERASEARC:
    MOVEQ.L     #0x2,D0                         | VERB = ERASE
    BRA.B       CALLARC                         | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE InvertArc(* r: Rect; startAngle,arcAngle: INTEGER *);
|
INVERTARC:
    MOVEQ.L     #0x3,D0                         | VERB = INVERT
    BRA.B       CALLARC                         | SHARE COMMON CODE
| --------------------------------------------------------
|
| PROCEDURE FillArc(* r: Rect; startAngle,arcAngle: INTEGER; pat: Pattern *);
|
FILLARC:
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDR
    MOVEA.L     (A7)+,A1                        | POP ADDR OF PATTERN
    MOVE.L      A0,-(A7)                        | PUT RETURN ADDR BACK
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    LEA.L       0x28(A0),A0                     | POINT TO FILLPAT
    MOVE.L      (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
    MOVE.L      (A1)+,(A0)+                     | ALL EIGHT BYTES
    MOVEQ.L     #0x4,D0                         | VERB = FILL
    NOP                                         | FALL THROUGH TO CALLARC
| ---------------------------------------------------------------
|
| PROCEDURE CallArc(r: Rect; startAngle,arcAngle: INTEGER);
|
| code shared by FrameArc, PaintArc, EraseArc, InvertArc, and FillArc.
| enter with verb in D0.
|
CALLARC:
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDR
    MOVE.L      (A7)+,D1                        | POP BOTH ANGLES
    MOVEA.L     (A7)+,A1                        | POP ADDR OF RECT
    MOVE.B      D0,-(A7)                        | PUSH VERB
    MOVE.L      A1,-(A7)                        | PUSH ADDR OF RECT
    MOVE.L      D1,-(A7)                        | PUSH BOTH ANGLES
    MOVE.L      A0,-(A7)                        | PUSH RETURN ADDR
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    MOVE.L      0x68(A0),D0                     | IS GRAFPROCS NIL ?
    MOVEA.L     (0x10F4).W,A0                   | _StdArc (arcProc)
    BEQ.B       USESTD                          | YES, USE STD PROC
    MOVEA.L     D0,A0                           | POINT TO QDPROCS RECORD
    MOVEA.L     0x14(A0),A0                     | NO, GET PROC PTR
USESTD:
    JMP         (A0)                            | GO TO IT
