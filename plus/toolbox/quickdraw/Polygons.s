| --------------------------------------------------------------
|
|
|     ****    ***   *    *   *   ***    ***   *   *   ***
|     *   *  *   *  *     * *   *   *  *   *  *   *  *   *
|     *   *  *   *  *      *    *      *   *  **  *  *
|     ****   *   *  *      *    *  **  *   *  * * *   ***
|     *      *   *  *      *    *   *  *   *  *  **      *
|     *      *   *  *      *    *   *  *   *  *   *  *   *
|     *       ***   *****  *     ***    ***   *   *   ***
|

| .PROC StdPoly,2
| .REF CheckPic,PutPicVerb,DPutPicByte,PutPicRgn
| .REF PushVerb,FrPoly,RSect,DrawPoly
| ---------------------------------------------------------------
|
| PROCEDURE StdPoly(verb: GrafVerb; poly: PolyHandle);
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 6
| VERB .EQU PARAMSIZE+8-2 ;GRAFVERB
| POLY .EQU VERB-4 ;LONG, PolyHandle
StdPoly:
        LINK    A6,#-0x8                        | ALLOCATE LOCALS

| MINRECT .EQU -8 ;RECT
| VARSIZE .EQU MINRECT ;TOTAL BYTES OF LOCALS

| --------------------------------------------------------------
.set PARAMSIZE, 6                               | TOTAL BYTES OF PARAMS
.set VERB, PARAMSIZE+8-2                        | GRAFVERB
.set POLY, VERB-4                               | LONG, PolyHandle

.set MINRECT, -8                                | RECT
.set VARSIZE, MINRECT                           | TOTAL BYTES OF LOCALS

        MOVEM.L D5-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.B  0xC(A6),D7                      | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.B   STDPOLY_NOTPIC                  | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVEQ.L #0x70,D0                        | PUT POLYNOUN IN HI NIBBLE
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        JSR     DPutPicByte(PC)                 | PUT OPCODE TO THEPIC
        MOVE.L  0x8(A6),-(SP)                   | PUSH POLYHANDLE
        JSR     PutPicRgn(PC)                   | TREAT SAME AS A REGION
STDPOLY_NOTPIC:
        MOVE.L  0x8(A6),A2                      | GET POLYHANDLE
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDPOLY_NOTFR                   | NO, CONTINUE
        MOVE.L  A2,-(SP)                        | PUSH POLYHANDLE
        JSR     FrPoly(PC)                      | FrPoly(poly);
        BRA.B   STDPOLY_GOHOME                  | AND QUIT

| ----------------------------------------------------------
|
| STDPOLY_NOTFR
|
STDPOLY_NOTFR:
        MOVE.L  (A2),A0                         | NOTFR: DE-REFERANCE POLYHANDLE
        PEA.L   POLYBBOX(A0)                    | PUSH POLYBBOX
        MOVE.L  VISRGN(A3),A0                   | GET VISRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE HANDLE
        PEA.L   RGNBBOX(A0)                     | PUSH VISRGN BBOX
        MOVE.L  CLIPRGN(A3),A0                  | GET CLIPRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE HANDLE
        PEA.L   RGNBBOX(A0)                     | PUSH CLIPRGN BBOX
        MOVE    #3,-(SP)                        | PUSH NRECTS = 3
        PEA.L   -0x8(A6)                        | PUT RESULT IN MINRECT
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ.B   STDPOLY_GOHOME                  | QUIT IF NO INTERSECT
        MOVE.L  A2,-(SP)                        | PUSH POLYHANDLE
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        JSR     DrawPoly(PC)                    | DrawPoly(poly,mode,pat);
STDPOLY_GOHOME:
        MOVEM.L (SP)+,D5-D7/A2-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | RESTORE A6
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x6,SP                         | STRIP PARAMS
        JMP     (A0)                            | AND RETURN

| .PROC FramePoly,1
| .DEF CallPoly,PaintPoly,ErasePoly,InvertPoly,FillPoly
| .REF StdPoly
| -----------------------------------------------------
|
| PROCEDURE FramePoly(* poly: PolyHandle *);
|
FramePoly:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        BRA.B   CallPoly                        | SHARE COMMON CODE

| -----------------------------------------------------
|
| PROCEDURE PaintPoly(* poly: PolyHandle *);
|
PaintPoly:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        BRA.B   CallPoly                        | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE ErasePoly(* poly: PolyHandle *);
|
ErasePoly:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        BRA.B   CallPoly                        | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE InvertPoly(* poly: PolyHandle *);
|
InvertPoly:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        BRA.B   CallPoly                        | SHARE COMMON CODE

| --------------------------------------------------------
|
| PROCEDURE FillPoly(* poly: PolyHandle; pat: Pattern *);
|
FillPoly:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | GET GLOBAL PTR
        MOVE.L  (A0),A0                         | GET THEPORT
        LEA.L   FILLPAT(A0),A0                  | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        NOP                                     | ALIGNMENT PADDING

| ---------------------------------------------------------------
|
| PROCEDURE CallPoly(poly: PolyHandle);
|
| code shared by FramePoly, PaintPoly, ErasePoly, InvertPoly, and FillPoly.
| enter with verb in D0.
|
CallPoly:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP POLY
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH POLY
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | GET GLOBAL PTR
        MOVE.L  (A0),A0                         | GET THEPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xF14).w,A0                    | _StdPoly (polyProc)
        BEQ.B   CALLPOLY_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | PUT PROC PTR IN A0
        MOVE.L  POLYPROC(A0),A0                 | NO, GET PROC PTR
CALLPOLY_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| .FUNC OpenPoly,0
| .REF HidePen,NewHandle
| ---------------------------------------------------------------
|
| FUNCTION OpenPoly: PolyHandle;
|
| STARTSIZE .EQU 138 ;ENOUGH FOR 32 POINTS
OpenPoly:
.set STARTSIZE, 138                             | ENOUGH FOR 32 POINTS

        JSR     HidePen(PC)                     | TURN OFF DRAWING
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #0x8A,-(SP)                     | PUSH STARTSIZE = 138
        JSR     FASTSLABMODE_CONT(PC)           | ALLOCATE NEWHANDLE
        MOVE.L  (SP)+,A1                        | POP RESULTING HANDLE
        MOVE.L  A1,0x4(SP)                      | PUT HANDLE IN FCN RESULT
        MOVE.L  (A5),A0                         | GET GLOBAL PTR
        MOVE.L  A1,THEPOLY(A0)                  | REMEMBER HANDLE IN THEPOLY
        MOVE    #0x8A,-0xA4(A0)                 | POLYMAX := 138
        MOVE.L  (A0),A0                         | GET THEPORT
        MOVEQ   #1,D0                           | SET D0 TO 1 (TRUE)
        MOVE.L  D0,POLYSAVE(A0)                 | POLYSAVE := TRUE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        MOVE    #10,(A1)+                       | INSTALL POLYSIZE = 10
        CLR.L   (A1)+                           | ZERO OUT POLYBBOX
        CLR.L   (A1)+                           | FINISH ZEROING POLYBBOX
        RTS                                     | AND RETURN

| .PROC ClosePoly,0
| .REF SetSize,ShowPen
| ---------------------------------------------------------------
|
| PROCEDURE ClosePoly;
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
ClosePoly:
        MOVEM.L D3-D7/A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | GET GLOBAL PTR
        MOVE.L  (A4),A0                         | GET THEPORT
        CLR.L   POLYSAVE(A0)                    | POLYSAVE := FALSE
        MOVE.L  THEPOLY(A4),A4                  | GET THEPOLY HANDLE
        MOVE.L  (A4),A0                         | DE-REFERENCE THEPOLY
        MOVE    (A0)+,D7                        | GET POLYSIZE
        CLR.L   (A0)+                           | ZERO OUT POLYBBOX
        CLR.L   (A0)+                           | FINISH ZEROING POLYBBOX
        MOVE    D7,D6                           | NPOINTS = POLYSIZE
        SUBI    #0xA,D6                         | NPOINTS = POLYSIZE - 10
        LSR     #2,D6                           | NPOINTS = (SIZE-10) DIV 4
        BEQ.B   EMPTY                           | QUIT IF NO POINTS

| -----------------------------------------------------
|
| SCAN FOR BOUNDING BOX OF POLYGON
|
        MOVE    (A0)+,D1                        | TOP := FIRST POINT VERT
        MOVE    D1,D2                           | BOTTOM := FIRST POINT VERT
        MOVE    (A0)+,D3                        | LEFT := FIRST POINT HORIZ
        MOVE    D3,D4                           | RIGHT := FIRST POINT HORIZ
        SUBQ.W  #0x1,D6                         | PREPARE FOR DBF
        BRA.B   RIGHTOK                         | GO TO LOOP START

| ----------------------------------------------------------
|
| CLOSEPOLY_NEXTPT
|
CLOSEPOLY_NEXTPT:
        MOVE    (A0)+,D0                        | NEXTPT: GET VERT COORD
        CMP     D1,D0                           | IS VERT < BBOX TOP ?
        BGE.B   CLOSEPOLY_TOPOK                 | NO, CONTINUE
        MOVE    D0,D1                           | YES, UPDATE BBOX TOP
CLOSEPOLY_TOPOK:
        CMP     D2,D0                           | TOPOK: IS VERT > BBOX BOTTOM ?
        BLE.B   CLOSEPOLY_BOTOK                 | NO, CONTINUE
        MOVE    D0,D2                           | YES, UPDATE BBOX BOTTOM
CLOSEPOLY_BOTOK:
        MOVE    (A0)+,D0                        | BOTOK: GET HORIZ COORD
        CMP     D3,D0                           | IS HORIZ < BBOX LEFT ?
        BGE.B   CLOSEPOLY_LEFTOK                | NO, CONTINUE
        MOVE    D0,D3                           | YES, UPDATE BBOX LEFT
CLOSEPOLY_LEFTOK:
        CMP     D4,D0                           | LEFTOK: IS HORIZ > BBOX RIGHT ?
        BLE.B   RIGHTOK                         | NO, CONTINUE
        MOVE    D0,D4                           | YES, UPDATE BBOX RIGHT
RIGHTOK:
        DBF     D6,CLOSEPOLY_NEXTPT             | LOOP ALL POINTS
        MOVE.L  (A4),A0                         | DE-REFERENCE THEPOLY
        LEA.L   POLYBBOX(A0),A0                 | POINT TO POLYBBOX
        MOVE    D1,(A0)+                        | INSTALL BBOX TOP
        MOVE    D3,(A0)+                        | INSTALL BBOX LEFT
        MOVE    D2,(A0)+                        | INSTALL BBOX BOTTOM
        MOVE    D4,(A0)+                        | INSTALL BBOX RIGHT

| --------------------------------------------------------
|
| TRIM THEPOLY TO FINAL SIZE, SHOW PEN AND QUIT
|
EMPTY:
        MOVE.L  A4,-(SP)                        | PUSH THEPOLY HANDLE
        MOVE    D7,-(SP)                        | PUSH BYTECOUNT = POLYSIZE
        JSR     SetHSize(PC)                    | TRIM TO MINIMUM SIZE
        JSR     ShowPen(PC)                     | RESTORE PNVIS
        MOVEM.L (SP)+,D3-D7/A4                  | RESTORE REGS
        RTS                                     | AND RETURN

| .PROC KillPoly
| ---------------------------------------------------
|
| PROCEDURE KillPoly(poly: PolyHandle);
|
KillPoly:
        MOVE.L  (SP)+,A1                        | pop return addr
        MOVE.L  (SP)+,A0                        | pop handle
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;discard it
        JMP     (A1)                            | and return

| .PROC OffsetPoly
| ---------------------------------------------------
|
| PROCEDURE OffsetPoly(poly: PolyHandle; dh,dv: INTEGER);
|
OffsetPoly:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        MOVE    (SP)+,D0                        | POP DV
        MOVE    (SP)+,D1                        | POP DH
        MOVE.L  (SP)+,A1                        | POP POLYHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE POLYHANDLE
        MOVE    (A1)+,D2                        | GET POLYSIZE
        SUBQ.W  #0x2,D2                         | # POINTS = POLYSIZE - 2
        LSR     #2,D2                           | # POINTS = (SIZE-2) DIV 4
        SUBQ.W  #0x1,D2                         | PREPARE FOR DBF
OFFSETPOLY_NEXTPT:
        ADD     D0,(A1)+                        | NEXTPT: OFFSET VERT COORD
        ADD     D1,(A1)+                        | OFFSET HORIZ COORD
        DBF     D2,OFFSETPOLY_NEXTPT            | LOOP FOR ALL POINTS
        JMP     (A0)                            | AND RETURN

| .PROC MapPoly,3
| .REF MapPt,MapRect
| -------------------------------------------------------------
|
| PROCEDURE MapPoly(poly: PolyHandle; fromRect,toRect: Rect);
|
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 12
| POLY .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| FROMRECT .EQU POLY-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
MapPoly:
.set PARAMSIZE, 12                              | TOTAL BYTES OF PARAMS
.set POLY, PARAMSIZE+8-4                        | LONG, RGNHANDLE
.set FROMRECT, POLY-4                           | LONG, ADDR OF RECT
.set TORECT, FROMRECT-4                         | LONG, ADDR OF RECT

        LINK    A6,#0                           | ALLOCATE STACK FRAME
        MOVEM.L D7/A2-A4,-(SP)                  | SAVE REGS

|
| QUIT FAST IF FROMRECT = TORECT
|
        MOVE.L  0xC(A6),A2                      | POINT TO FROMRECT
        MOVE.L  0x8(A6),A3                      | POINT TO TORECT

        MOVE.L  (A2),D0                         | GET TOPLEFT OF FROMRECT
        CMP.L   (A3),D0                         | IS TOPLEFT SAME ?
        BNE.B   MAPPOLY_NOTSAME                 | NO, CONTINUE
        MOVE.L  0x4(A2),D0                      | GET BOTRIGHT OF FROMRECT
        CMP.L   0x4(A3),D0                      | YES, IS BOTRIGHT SAME TOO ?
        BEQ.B   MAPPOLY_DONE                    | IF SO, JUST QUIT
MAPPOLY_NOTSAME:
        MOVE.L  0x10(A6),A4                     | GET POLYHANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE POLYHANDLE
        PEA.L   POLYBBOX(A4)                    | PUSH ADDR OF BBOX
        MOVE.L  A2,-(SP)                        | PUSH FROMRECT
        MOVE.L  A3,-(SP)                        | PUSH TORECT
        JSR     MapRect(PC)                     | MAP POLYBBOX
        MOVEQ   #10,D0                          | SIZEOF POLY HEADER
        MOVE    (A4),D7                         | GET POLYSIZE
        SUB     D0,D7                           | POLYSIZE - 10
        LSR     #2,D7                           | NPOINTS = (POLYSIZE-10) DIV 4
        ADD     D0,A4                           | POINT TO FIRST POINT
        BRA.B   MAPPOLY_START                   | GO TO LOOP START

| ----------------------------------------------------------
|
| MAPPOLY_NEXTPT
|
MAPPOLY_NEXTPT:
        MOVE.L  A4,-(SP)                        | NEXTPT: PUSH ADDR OF POINT
        MOVE.L  A2,-(SP)                        | PUSH FROMRECT
        MOVE.L  A3,-(SP)                        | PUSH TORECT
        JSR     MapPt(PC)                       | MAP THIS POINT
        ADDQ.W  #0x4,A4                         | BUMP POINTER TO NEXT POINT
MAPPOLY_START:
        DBF     D7,MAPPOLY_NEXTPT               | LOOP ALL POINTS IN POLY
MAPPOLY_DONE:
        MOVEM.L (SP)+,D7/A2-A4                  | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE A6
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA    #0xC,SP                         | STRIP PARAMS
        JMP     (A0)                            | AND RETURN

| .PROC FrPoly,1
| .REF MoveTo,DoLine
| --------------------------------------------------------
|
| PROCEDURE FrPoly(poly: PolyHandle);
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 4
| POLY .EQU PARAMSIZE+8-4 ;LONG, POLYHANDLE
FrPoly:
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set POLY, PARAMSIZE+8-4                        | LONG, POLYHANDLE

        LINK    A6,#0                           | ALLOCATE STACK FRAME
        MOVEM.L D6-D7/A4,-(SP)                  | SAVE REGS
        MOVE.L  0x8(A6),A4                      | GET POLYHANDLE
        MOVE.L  (A4),A0                         | DE-REFERENCE IT
        MOVE    (A0),D7                         | GET POLYSIZE
        SUBI    #0xA,D7                         | POLYSIZE - 10
        LSR     #2,D7                           | NPOINTS = (SIZE-10) DIV 4
        BEQ.B   FRPOLY_DONE                     | QUIT IF EMPTY POLYGON
        MOVE.L  0xA(A0),-(SP)                   | PUSH FIRST POINT
        JSR     MoveTo(PC)                      | MOVETO(FIRST POINT)
        MOVEQ.L #0xE,D6                         | START AT SECOND POINT (OFFSET 14)
        SUBQ.W  #0x1,D7                         | PREPARE FOR DBF
        BRA.B   FRPOLY_START                    | GOT TO LOOP START

| ----------------------------------------------------------
|
| FRPOLY_NEXTPT
|
FRPOLY_NEXTPT:
        MOVE.L  (A4),A0                         | NEXTPT: DE-REFERENCE POLYHANDLE
        MOVE.L  0x0(A0,D6.W),-(SP)              | PUSH NEXT POINT
        ADDQ.W  #0x4,D6                         | BUMP OFFSET BY 4 BYTES
        JSR     DoLine(PC)                      | DOLINE(PT)
FRPOLY_START:
        DBF     D7,FRPOLY_NEXTPT                | LOOP FOR ALL POINTS
FRPOLY_DONE:
        MOVEM.L (SP)+,D6-D7/A4                  | DONE: RESTORE REGS
        UNLK    A6                              | RESTORE A6
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM AND ADJUST RETURN ADDR
        RTS                                     | AND RETURN

| .PROC DrawPoly,3
| .REF OpenRgn,FrPoly,DoLine,NewRgn,CloseRgn,DrawRgn
| --------------------------------------------------------
|
| PROCEDURE DrawPoly(poly: PolyHandle; mode: INTEGER; VAR pat: Pattern);
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 10
| POLY .EQU PARAMSIZE+8-4 ;LONG, POLYHANDLE
| MODE .EQU POLY-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
DrawPoly:
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set POLY, PARAMSIZE+8-4                        | LONG, POLYHANDLE
.set MODE, POLY-2                               | WORD
.set PAT, MODE-4                                | LONG, ADDR OF PATTERN

        LINK    A6,#0                           | NO LOCAL VARS
        MOVE.L  A4,-(SP)                        | SAVE REG
        MOVE.L  (A5),A0                         | GET GLOBAL PTR
        MOVE.L  (A0),A0                         | GET THEPORT
        TST     PNVIS(A0)                       | IS PNVIS NEG ?
        BMI.B   DRAWPOLY_DONE                   | YES, QUIT
        JSR     OpenRgn(PC)                     | OpenRgn
        MOVE.L  0xE(A6),-(SP)                   | PUSH POLYHANDLE
        JSR     FrPoly(PC)                      | FrPoly(poly);
        MOVE.L  0xE(A6),A0                      | GET POLYHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVE.L  0xA(A0),-(SP)                   | PUSH FIRST POINT
        JSR     DoLine(PC)                      | MAKE SURE IT CLOSES
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE TEMPRGN
        MOVE.L  (SP),A4                         | PUT TEMPRGN IN A4
        JSR     CloseRgn(PC)                    | CLOSERGN(TEMPRGN)
        MOVE.L  A4,-(SP)                        | PUSH TEMPRGN
        MOVE    0xC(A6),-(SP)                   | PUSH MODE
        MOVE.L  0x8(A6),-(SP)                   | PUSH ADDR OF PATTERN
        JSR     DrawRgn(PC)                     | DrawRgn(tempRgn,mode,pat);
        MOVE.L  A4,A0                           | get tempRgn
        _DisposeHandle                          | DISCARD IT

| _DisposHandle ;DISCARD IT
DRAWPOLY_DONE:
        MOVEM.L (SP)+,A4                        | DONE: RESTORE REG
        UNLK    A6                              | RESTORE A6
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA    #0xA,SP                         | STRIP PARAMS
        JMP     (A0)                            | AND RETURN


