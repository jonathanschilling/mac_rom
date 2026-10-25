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

| .PROC StdRgn,2
| .REF CheckPic,PutPicVerb,DPutPicByte,PutPicRgn
| .REF PutRgn,FrRgn,PushVerb,DrawRgn
| ---------------------------------------------------------------
|
| PROCEDURE StdRgn(verb: GrafVerb; rgn: RgnHandle);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| Called during boot.
|
StdPoly:
        LINK    A6,#-0x8                        | link frame, 8 bytes locals (TEMPRECT)
        MOVEM.L D5-D7/A2-A4,-(SP)               | save D5-D7,A2-A4
        MOVE.B  12(A6),D7                       | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.W   STDPOLY_NOTPIC                  | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | push verb byte
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVEQ.L #0x70,D0                        | polyNoun in hi nibble (0x70)
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | PUSH OPCODE
        JSR     PutPicByte(PC)                  | record opcode byte to picture
        MOVE.L  8(A6),-(SP)                     | POP RETURN ADDRESS
        JSR     PutPicRgn(PC)                   | PUT OPCODE AND RECTANGLE
STDPOLY_NOTPIC:
        MOVE.L  8(A6),A2                        | jump via A0
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDPOLY_NOTFR                   | NO, CONTINUE
        MOVE.L  A2,-(SP)                        | push poly handle
        JSR     FrPoly(PC)                      | ADD AN OVAL TO THERGN
        BRA.B   STDRGN_GOHOME                   | done, exit via shared epilog

| ----------------------------------------------------------
| STDPOLY_NOTFR
STDPOLY_NOTFR:
        MOVE.L  (A2),A0                         | A0 := poly ptr
        PEA.L     2(A0)                         | push polyBBox addr
        MOVE.L  24(A3),A0                       | A0 := visRgn handle
        MOVE.L  (A0),A0                         | A0 := visRgn ptr
        PEA.L     2(A0)                         | push visRgn bbox addr
        MOVE.L  28(A3),A0                       | GET PICSAVE HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE PICSAVE
        PEA.L     2(A0)                         | push clipRgn bbox addr
        MOVE    #0x3,-(SP)                      | push nRects = 3
        PEA.L     -8(A6)                        | push addr of TEMPRECT (dst)
        JSR     RSect(PC)                       | PUT OPCODE AND RECTANGLE
        BEQ.B   STDRGN_GOHOME                   | NO, CONTINUE
        MOVE.L  A2,-(SP)                        | push poly handle
        JSR     PushVerb(PC)                    | pc-relative jsr (was raw .short pair)
        JSR     DrawPoly(PC)                    | draw the polygon
STDRGN_GOHOME:
        MOVEM.L (SP)+,D5-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | RTS
| Called by: FramePoly, PaintPoly, ErasePoly, InvertPoly, FillPoly
CallPoly:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVE.L  (SP)+,A1                        | pop poly handle
        MOVE.B  D0,-(SP)                        | push verb byte
        MOVE.L  A1,-(SP)                        | push poly handle
        MOVE.L  A0,-(SP)                        | restore return addr
        MOVE.L  (A5),A0                         | A0 := QD globals
        MOVE.L  (A0),A0                         | A0 := thePort
        MOVE.L  0x68(A0),D0                     | D0 := grafProcs
        LEA     StdPoly(PC),A0                  | default proc = StdPoly
        BEQ.B   CALLPOLY_USESTD                 | grafProcs NIL? use default
        MOVE.L  D0,A0                           | A0 := grafProcs ptr
        MOVE.L  24(A0),A0                       | A0 := polyProc field
CALLPOLY_USESTD:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE FramePoly(poly: PolyHandle).
FramePoly:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallPoly(PC)                    | SHARE COMMON CODE

| PROCEDURE PaintPoly(poly: PolyHandle).
PaintPoly:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallPoly(PC)                    | SHARE COMMON CODE

| PROCEDURE ErasePoly(poly: PolyHandle).
ErasePoly:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallPoly(PC)                    | SHARE COMMON CODE

| PROCEDURE InvertPoly(poly: PolyHandle).
InvertPoly:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallPoly(PC)                    | SHARE COMMON CODE

| PROCEDURE FillPoly(poly: PolyHandle; pat: Pattern).
FillPoly:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallPoly(PC)                    | SHARE COMMON CODE

| ----------------------------------------------------------
| FUNCTION OpenPoly: PolyHandle;
| Allocate a new polygon and start recording. Plus equivalent:
| Polygons.s 165. STARTSIZE = 138 bytes (32 points header).
OpenPoly:
        JSR     HidePen(PC)                     | TURN OFF DRAWING
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #0x8A,-(SP)                     | PUSH STARTSIZE = 138
        JSR     NewHandle_Inline(PC)            | NewHandle(138)
        MOVE.L  (SP)+,A1                        | POP RESULTING HANDLE
        MOVE.L  A1,4(SP)                        | install in FCN result
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  A1,-0xA2(A0)                    | THEPOLY := handle
        MOVE    #0x8A,-0xA4(A0)                 | POLYMAX := 138
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  #0x1,0x64(A0)                   | POLYSAVE := TRUE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        MOVE    #0xA,(A1)+                      | POLYSIZE := 10
        CLR.L   (A1)+                           | ZERO POLYBBOX
        CLR.L   (A1)+                           | FINISH ZEROING
        RTS                                     | return from OpenPoly

| ---------------------------------------------------------------
| PROCEDURE ClosePoly; { finish a polygon: compute bbox, trim }
ClosePoly:
        MOVEM.L D3-D7/A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A0                         | GET CURRENT GRAFPORT
        CLR.L   0x64(A0)                        | POLYSAVE := FALSE
        MOVE.L  -0xA2(A4),A4                    | GET THEPOLY HANDLE
        MOVE.L  (A4),A0                         | DE-REFERENCE THEPOLY
        MOVE    (A0)+,D7                        | GET POLYSIZE
        CLR.L   (A0)+                           | ZERO OUT POLYBBOX
        CLR.L   (A0)+                           | FINISH ZEROING POLYBBOX
        MOVE    D7,D6                           | NPOINTS = POLYSIZE
        SUBI    #0xA,D6                         | NPOINTS = POLYSIZE - 10
        LSR     #0x2,D6                         | NPOINTS = (SIZE-10) DIV 4
        BEQ.B   EMPTY                           | QUIT IF NO POINTS
        MOVE    (A0)+,D1                        | TOP := FIRST POINT VERT
        MOVE    D1,D2                           | BOTTOM := FIRST POINT VERT
        MOVE    (A0)+,D3                        | LEFT := FIRST POINT HORIZ
        MOVE    D3,D4                           | RIGHT := FIRST POINT HORIZ
        SUBQ.W  #0x1,D6                         | PREPARE FOR DBF
        BRA.B   RIGHTOK                         | GO TO LOOP START
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
        DBRA    D6,CLOSEPOLY_NEXTPT             | LOOP ALL POINTS
        MOVE.L  (A4),A0                         | A0 := poly ptr
        LEA.L     2(A0),A0                      | skip past polySize
        MOVE    D1,(A0)+                        | polyBBox.top := D1
        MOVE    D3,(A0)+                        | polyBBox.left := D3
        MOVE    D2,(A0)+                        | polyBBox.bottom := D2
        MOVE    D4,(A0)+                        | polyBBox.right := D4
| --------------------------------------------------------
| TRIM THEPOLY TO FINAL SIZE, SHOW PEN AND QUIT
EMPTY:
        MOVE.L  A4,-(SP)                        | push poly handle
        MOVE    D7,-(SP)                        | push final polySize
        JSR     SetHSize(PC)                    | trim poly handle to final size
        JSR     ShowPen(PC)                     | restore drawing pen
        MOVEM.L (SP)+,D3-D7/A4                  | restore registers
        RTS                                     | return from EMPTY
| ----------------------------------------------------------
|
| _KillPoly ($A8CD): dispose of a polygon
| Pascal: PROCEDURE KillPoly(poly: PolyHandle);
| Tail-jumps to DisposRgn, which disposes the handle (_DisposHandle).
|
KillPoly:
        JMP     DisposRgn(PC)                   | DisposRgn(poly): _DisposHandle and return
| ----------------------------------------------------------
|
| _OffSetPoly ($A8CE): move a polygon by (dh, dv)
| Pascal: PROCEDURE OffsetPoly(poly: PolyHandle; dh, dv: INTEGER);
| Adds dv/dh to all (polySize-2) DIV 4 points that follow polySize,
| i.e. to the two corners of polyBBox as well as to the polygon points.
|
OffsetPoly:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        MOVE    (SP)+,D0                        | POP DV
        MOVE    (SP)+,D1                        | POP DH
        MOVE.L  (SP)+,A1                        | pop poly handle
        MOVE.L  (A1),A1                         | dereference poly handle
        MOVE    (A1)+,D2                        | get polySize, advance ptr
        SUBQ.W  #0x2,D2                         | polySize - 2 = bytes of bbox + points
        LSR     #0x2,D2                         | # POINTS = (SIZE-2) DIV 4, INCL BBOX
        SUBQ.W  #0x1,D2                         | adjust for DBRA
OFFSETPOLY_NEXTPT:                              | NEXTPT: loop over all points
        ADD     D0,(A1)+                        | OFFSET VERT COORD BY DV
        ADD     D1,(A1)+                        | OFFSET HORIZ COORD BY DH
        DBRA    D2,OFFSETPOLY_NEXTPT            | loop all polygon points
        JMP     (A0)                            | RTS

| RTS ;AND RETURN
| .PROC MapPoly,3
| .REF MapPt,MapRect
| -------------------------------------------------------------
| PROCEDURE MapPoly(poly: PolyHandle; fromRect,toRect: Rect);
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 12
| POLY .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| FROMRECT .EQU POLY-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
MapPoly:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D7/A2-A4,-(SP)                  | save D7,A2-A4
        MOVE.L  12(A6),A2                       | A2 := fromRect ptr
        MOVE.L  8(A6),A3                        | A3 := toRect ptr
        MOVE.L  (A2),D0                         | get fromRect.topLeft
        CMP.L   (A3),D0                         | same as toRect.topLeft?
        BNE.B   MAPPOLY_CONT                    | no, full mapping needed
        MOVE.L  4(A2),D0                        | PUSH NEXT POINT
        CMP.L   4(A3),D0                        | same botRight too?
        BEQ.B   MAPPOLY_NEXTPT_CONT_2           | identity map, skip work
MAPPOLY_CONT:
        MOVE.L  16(A6),A4                       | A4 := poly handle
        MOVE.L  (A4),A4                         | A4 := poly ptr
        PEA.L     2(A4)                         | push polyBBox addr
        MOVE.L  A2,-(SP)                        | push fromRect
        MOVE.L  A3,-(SP)                        | STRIP PARAM AND ADJUST RETURN ADDR
        JSR     MapRect(PC)                     | map polyBBox from->to
        MOVE    (A4),D7                         | get polySize
        SUBI    #0xA,D7                         | subtract header bytes (10)
        LSR     #0x2,D7                         | (size-10)/4 = nPoints
        ADDA.W  #0xA,A4                         | skip past polySize+bbox
        BRA.B   MAPPOLY_NEXTPT_CONT             | enter loop test

| ----------------------------------------------------------
| MAPPOLY_NEXTPT
MAPPOLY_NEXTPT:
        MOVE.L  A4,-(SP)                        | push addr of point
        MOVE.L  A2,-(SP)                        | push fromRect
        MOVE.L  A3,-(SP)                        | push toRect
        JSR     MapPt(PC)                       | map this polygon vertex
        ADDQ.W  #0x4,A4                         | advance to next point
MAPPOLY_NEXTPT_CONT:
        DBRA    D7,MAPPOLY_NEXTPT               | loop all polygon vertices
MAPPOLY_NEXTPT_CONT_2:
        MOVEM.L (SP)+,D7/A2-A4                  | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS

| .PROC FrPoly,1
| .REF MoveTo,DoLine
| --------------------------------------------------------
| PROCEDURE FrPoly(poly: PolyHandle);
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 4
| POLY .EQU PARAMSIZE+8-4 ;LONG, POLYHANDLE
FrPoly:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D6-D7/A4,-(SP)                  | save D6,D7,A4
        MOVE.L  8(A6),A4                        | A4 := poly handle
        MOVE.L  (A4),A0                         | A0 := poly ptr
        MOVE    (A0),D7                         | restore A3
        SUBI    #0xA,D7                         | subtract header bytes (10)
        LSR     #0x2,D7                         | nPoints = (size-10)/4
        BEQ.B   FRPOLY_CONT_2                   | no points, exit
        MOVE.L  10(A0),-(SP)                    | push first point (TopLeft)
        JSR     MoveTo(PC)                      | jump via A0
        MOVEQ.L #0xE,D6                         | D6 := 14 (offset of 2nd point)
        SUBQ.W  #0x1,D7                         | adjust nPoints for DBRA
        BRA.B   FRPOLY_CONT                     | enter loop test
FRPOLY_LOOP:
        MOVE.L  (A4),A0                         | A0 := poly ptr (relocatable)
        MOVE.L  0(A0,D6.W),-(SP)                | push next polygon point
        ADDQ.W  #0x4,D6                         | advance offset to next point
        JSR     DoLine(PC)                      | draw line to that point
FRPOLY_CONT:
        DBRA    D7,FRPOLY_LOOP                  | loop nPoints-1 times
FRPOLY_CONT_2:
        MOVEM.L (SP)+,D6-D7/A4                  | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | overwrite param with return addr
        RTS                                     | return from FRPOLY_CONT_2

| .PROC DrawPoly,3
| .REF OpenRgn,FrPoly,DoLine,NewRgn,CloseRgn,DrawRgn
| --------------------------------------------------------
| PROCEDURE DrawPoly(poly: PolyHandle; mode: INTEGER; VAR pat: Pattern);
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 10
| POLY .EQU PARAMSIZE+8-4 ;LONG, POLYHANDLE
| MODE .EQU POLY-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
DrawPoly:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVE.L  A4,-(SP)                        | save A4
        MOVE.L  (A5),A0                         | A0 := QD globals
        MOVE.L  (A0),A0                         | A0 := thePort
        TST     0x42(A0)                        | is pnVis < 0?
        BMI.B   DRAWPOLY_CONT                   | yes, pen hidden, exit
        JSR     OpenRgn(PC)                     | start new region build
        MOVE.L  14(A6),-(SP)                    | POP RETURN ADDR
        JSR     FrPoly(PC)                      | stroke poly into region
        MOVE.L  14(A6),A0                       | A0 := poly handle
        MOVE.L  (A0),A0                         | jump via A0
        MOVE.L  10(A0),-(SP)                    | push first poly point
        JSR     DoLine(PC)                      | close poly with final segment
        CLR.L   -(SP)                           | room for NewRgn result
        JSR     NewRgn(PC)                      | allocate temp region
        MOVE.L  (SP),A4                         | A4 := temp region handle
        JSR     CloseRgn(PC)                    | finish region (sort+pack)
        MOVE.L  A4,-(SP)                        | push temp region
        MOVE    12(A6),-(SP)                    | push mode
        MOVE.L  8(A6),-(SP)                     | push pat
        JSR     DrawRgn(PC)                     | draw region with mode/pat
        MOVE.L  A4,-(SP)                        | push temp region for dispose
        JSR     DisposRgn(PC)                   | dispose the temp region
DRAWPOLY_CONT:
        MOVEM.L (SP)+,A4                        | restore A4
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS
