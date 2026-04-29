|-----------------------------------------------------------
|
|
|     ****   *****   ***   ***   ***   *   *   ***
|     *   *  *      *   *   *   *   *  *   *  *   *
|     *   *  *      *       *   *   *  **  *  *
|     ****   ***    *  **   *   *   *  * * *   ***
|     * *    *      *   *   *   *   *  *  **      *
|     *  *   *      *   *   *   *   *  *   *  *   *
|     *   *  *****   ***   ***   ***   *   *   ***
|
|
|
|  QuickDraw Routines to operate on Regions.
|

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
| PROCEDURE FramePoly(poly: PolyHandle); Plus equivalent: Polygons.s.
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
        RTS                                     | return

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
        RTS                                     | return to caller
        JMP     NEWRGN_CONT(PC)                 | dispose handle (DisposHandle tail)
        MOVE.L  (SP)+,A0                        | OffsetPoly: pop return addr
        MOVE    (SP)+,D0                        | pop dh
        MOVE    (SP)+,D1                        | pop dv
        MOVE.L  (SP)+,A1                        | pop poly handle
        MOVE.L  (A1),A1                         | dereference poly handle
        MOVE    (A1)+,D2                        | get polySize, advance ptr
        SUBQ.W  #0x2,D2                         | skip header word from count
        LSR     #0x2,D2                         | (size-2)/4 = number of points
        SUBQ.W  #0x1,D2                         | adjust for DBRA
OFFSETPOLY_NEXTPT:                              | jump via A0
        ADD     D0,(A1)+                        | (A1)+ += D0
        ADD     D1,(A1)+                        | (A1)+ += D1
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
        RTS                                     | return to caller

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
        JSR     NEWRGN_CONT(PC)                 | dispose the temp region
DRAWPOLY_CONT:
        MOVEM.L (SP)+,A4                        | restore A4
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS
StdRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D6-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.B  12(A6),D7                       | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.W   STDRGN_NOTPIC                   | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVE    #0x80,D0                        | rgnNoun in hi nibble (0x80)
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | push opcode byte
        JSR     PutPicByte(PC)                  | PUT OPCODE TO THEPIC
        MOVE.L  8(A6),-(SP)                     | PUSH RGNHANDLE
        JSR     PutPicRgn(PC)                   | PUT REGION TO THEPIC
STDRGN_NOTPIC:
        MOVE.L  8(A6),-(SP)                     | PUSH RGNHANDLE
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDRGN_NOTPIC_NO_2              | NO, CONTINUE
        TST.L   0x60(A3)                        | YES, IS RGNSAVE TRUE ?
        BEQ.B   STDRGN_NOTPIC_NO                | NO, CONTINUE
        MOVE.L  8(A6),-(SP)                     | YES, PUSH RGNHANDLE
        MOVE.L  -0x94(A4),-(SP)                 | PUSH RGNBUF
        PEA.L     -0x96(A4)                     | PUSH VAR RGNINDEX
        PEA.L     -0x98(A4)                     | PUSH VAR RGNMAX
        JSR     PutRgn(PC)                      | ADD INVERSION PTS TO THERGN
STDRGN_NOTPIC_NO:
        JSR     FrRgn(PC)                       | FrRgn(rgn,pnMode,pnPat)
        BRA.B   STDRGN_NOTPIC_CONT              | skip non-frame DrawRgn
STDRGN_NOTPIC_NO_2:
        JSR     DrawRgn(PC)                     | DrawRgn(rgn,mode,pat);
STDRGN_NOTPIC_CONT:
        MOVEM.L (SP)+,D6-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | RTS
| Called by: FrameRgn, PaintRgn, EraseRgn, InvertRgn, FillRgn
CallRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP RGN
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH RGN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | A0 := QD globals
        MOVE.L  (A0),A0                         | A0 := thePort
        MOVE.L  0x68(A0),D0                     | D0 := grafProcs
        LEA     StdRgn(PC),A0                   | default proc = StdRgn
        BEQ.B   CALLRGN_USESTD                  | YES, USE STD PROC
        MOVE.L  D0,A0                           | A0 := grafProcs ptr
        MOVE.L  28(A0),A0                       | NO, GET PROC PTR
CALLRGN_USESTD:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE FrameRgn(rgn: RgnHandle).
FrameRgn:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| PROCEDURE PaintRgn(rgn: RgnHandle).
PaintRgn:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| PROCEDURE EraseRgn(rgn: RgnHandle).
EraseRgn:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| PROCEDURE InvertRgn(rgn: RgnHandle).
InvertRgn:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| PROCEDURE FillRgn(rgn: RgnHandle; pat: Pattern).
FillRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallRgn(PC)                     | SHARE COMMON CODE

| .PROC DrawRgn,3
| .REF RgnBlt
| --------------------------------------------------------
| PROCEDURE DrawRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
| A6 OFFSETS OF PARAMS AFTER LINK:
| PARAMSIZE .EQU 10
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| MODE .EQU RGN-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
| Called during boot.
DrawRgn:
        LINK    A6,#0x0                         | ESTABLISH STACK FRAME
        MOVE.L  (A5),A0                         | POINT TO GRAFGLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        TST     0x42(A0)                        | IS PNVIS NEG ?
        BMI.B   DRAWRGN_EXIT_2                  | YES, QUIT
        PEA.L     2(A0)                         | PUSH SRCBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L     8(A0)                         | PUSH PORTBITS+BOUNDS (SRCRECT)
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  8(A6),-(SP)                     | PUSH PAT
        MOVE.L  28(A0),-(SP)                    | PUSH CLIPRGN
        MOVE.L  24(A0),-(SP)                    | PUSH VISRGN
        MOVE.L  14(A6),-(SP)                    | PUSH RGN
        JSR     RgnBlt(PC)                      | CALL RGNBLT
DRAWRGN_EXIT_2:                                 | jump via A0
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS

| .PROC FrRgn,3
| .REF FrRect,NewRgn,CopyRgn,InsetRgn,DiffRgn,DrawRgn
| --------------------------------------------------------
| PROCEDURE FrRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
| A6 OFFSETS OF PARAMS AFTER LINK:
| PARAMSIZE .EQU 10
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| MODE .EQU RGN-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PATTERN
| Called during boot.
FrRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | A4 := QD globals
        MOVE.L  (A4),A3                         | A3 := thePort
        TST     0x42(A3)                        | is pnVis < 0?
        BMI.W   FRRGN_CONT                      | YES, QUIT
        MOVE.L  14(A6),A0                       | GET RGNHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMPI    #0xA,(A0)                       | is rgn rectangular (size==10)?
        BNE.B   FRRGN_NOTRECT                   | NO, CONTINUE
        PEA.L     2(A0)                         | YES, PUSH ADDR OF BBOX
        JSR     FrRect(PC)                      | jump via A0
        BRA.B   FRRGN_CONT                      | AND QUIT
FRRGN_NOTRECT:
        CLR.L   -(SP)                           | NOTRECT: MAKE ROOM FOR FCN RESULT
        JSR     NewRgn(PC)                      | ALLOCATE TEMPRGN
        MOVE.L  (SP)+,D7                        | PUT TEMPRGN IN D7
        MOVE.L  14(A6),-(SP)                    | PUSH RGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        JSR     CopyRgn(PC)                     | COPY RGN INTO TEMPRGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE.L  0x34(A3),-(SP)                  | PUSH PNSIZE
        JSR     InsetRgn(PC)                    | InsetRgn(tempRgn,pnSize);
        MOVE.L  14(A6),-(SP)                    | PUSH RGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        JSR     DiffRgn(PC)                     | DiffRgn(rgn,tempRgn,tempRgn);
        MOVE.L  D7,-(SP)                        | PUSH TEMPRGN
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  8(A6),-(SP)                     | PUSH PAT
        JSR     DrawRgn(PC)                     | DrawRgn(tempRgn,mode,pat);
        MOVE.L  D7,-(SP)                        | push tempRgn for dispose
        JSR     NEWRGN_CONT(PC)                 | DrawRgn(tempRgn,mode,pat);
FRRGN_CONT:
        MOVEM.L (SP)+,D7/A3-A4                  | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS

| .FUNC NewRgn,0
| .REF NewHandle
| ---------------------------------------------------
| FUNCTION NewRgn;
| Allocate a new region and set it to the empty region.
| Called during boot (4,158 times in 30s trace).
NewRgn:
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #0xA,-(SP)                      | PUSH BYTECOUNT=10
        JSR     NewHandle_Inline(PC)            | ALLOCATE A RELOCATABLE OBJECT
        MOVE.L  (SP)+,A0                        | POP RESULTING HANDLE
        MOVEM.L (SP)+,D3/A2                     | RESTORE REGS
        MOVE.L  A0,4(SP)                        | STORE INTO NEWRGN RESULT
        MOVE.L  (A0),A0                         | DE-REFERENCE HANDLE
        MOVE    #0xA,(A0)+                      | INSTALL RGNSIZE=10
        CLR.L   (A0)+                           | INSTALL RGNBBOX=(0,0,0,0)
        CLR.L   (A0)+                           | CLEAR RGNBBOX BOTTOM,RIGHT
        RTS                                     | RETURN TO CALLER
| Called by: ClosePort, NOTPORT_NO, MORE, EMPTY, DrawPoly (and 2 more)
NEWRGN_CONT:
        MOVE.L  (SP)+,A0                        | pop handle to dispose
        MOVE.L  (SP)+,A1                        | pop return addr
        MOVEM.L D3/A0/A2,-(SP)                  | save state for KillPicture
        MOVE.L  A1,-(SP)                        | push return addr (KillPicture pops)
        JSR     KillPicture(PC)                 | dispose handle (DisposHandle tail)
        MOVEM.L (SP)+,D3/A0/A2                  | restore state
        JMP     (A0)                            | RTS

| OpenRgn -- binary search within node.
| ----------------------------------------------------------
| Search Node
OpenRgn:
        MOVEM.L D3/A2-A4,-(SP)                  | DONE: RESTORE REGS
        MOVE.L  (A5),A4                         | A4 := QD globals
        MOVE.L  (A4),A0                         | STRIP PARAMETERS
        MOVE.L  #0x1,0x60(A0)                   | rgnSave := TRUE
        CLR     -0x96(A4)                       | rgnIndex := 0
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    #0x100,-(SP)                    | push byteCount = 256
        MOVE    (SP),-0x98(A4)                  | rgnMax := 256
        JSR     NewHandle_Inline(PC)            | allocate rgnBuf (256 bytes)
        MOVE.L  (SP)+,-0x94(A4)                 | rgnBuf := new handle
        JSR     HidePen(PC)                     | suppress drawing while building
        MOVEM.L (SP)+,D3/A2-A4                  | RESTORE REGS
        RTS                                     | AND RETURN

| .PROC CloseRgn,1
| .REF ShowPen,SortPoints,CullPoints,PackRgn
| ---------------------------------------------------
| PROCEDURE CloseRgn(* dstRgn: RgnHandle *);
| Sort array of inversion points and pack into region.
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 4 ;TOTAL BYTES OF PARAMETERS
| DSTRGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| PTCOUNT .EQU -2 ;WORD
| VARSIZE .EQU PTCOUNT ;SIZE OF LOCAL VARS
| Called during boot.
CloseRgn:
        LINK    A6,#-0x2                        | ESTABLISH STACK FRAME
        MOVEM.L D3/A2-A4,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO GRAFGLOBALS
        MOVE.L  (A4),A0                         | POINT TO THEPORT
        TST.L   0x60(A0)                        | IS RGNSAVE TRUE ?
        BEQ.B   CLOSERGN_EXIT                   | NO, NOTHING TO CLOSE
        CLR.L   0x60(A0)                        | YES, RGNSAVE := FALSE
        JSR     ShowPen(PC)                     | UNDO THE HIDEPEN FROM OPENRGN
        MOVE    -0x96(A4),D0                    | GET CURRENT RGNINDEX
        LSR     #0x2,D0                         | DIV BY 4
        MOVE    D0,-2(A6)                       | FOR PTCOUNT
        MOVE.L  -0x94(A4),A3                    | GET RGNBUF HANDLE
        MOVE.L  (A3),-(SP)                      | PUSH BUF POINTER
        MOVE    D0,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | QUICKSORT IN VH ORDER
        MOVE.L  (A3),-(SP)                      | PUSH BUF POINTER
        PEA.L     -2(A6)                        | PUSH VAR PTCOUNT
        JSR     CullPoints(PC)                  | CANCEL DUPLICATE PAIRS
        MOVE.L  A3,-(SP)                        | PUSH RGNBUF HANDLE
        MOVE    -2(A6),-(SP)                    | PUSH (UPDATED) PTCOUNT
        MOVE.L  8(A6),-(SP)                     | PUSH DSTRGN
        JSR     PackRgn(PC)                     | PACK POINTS INTO DSTRGN
        MOVE.L  A3,-(SP)                        | push rgnBuf handle
        JSR      KillPicture(PC)                | PACK POINTS INTO DSTRGN
CLOSERGN_EXIT:
        MOVEM.L  (SP)+,D3/A2-A4                 | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | RESTORE RETURN ADDR
        RTS                                     | return to caller

| .PROC CopyRgn,1
| .REF SetSize
| ---------------------------------------------------
| PROCEDURE CopyRgn(* srcRgn,dstRgn: RgnHandle *);
| PARAMSIZE .EQU 8
| SRCRGN .EQU PARAMSIZE+8-4 ;RGNHANDLE
| DSTRGN .EQU SRCRGN-4 ;RGNHANDLE
| Called during boot (9,298 times in 30s trace).
CopyRgn:
        LINK    A6,#0x0                         | ESTABLISH STACK FRAME
        MOVE.L  12(A6),A0                       | GET SRCRGN HANDLE
        MOVE.L  8(A6),A1                        | GET DSTRGN HANDLE
        CMPA.L  A0,A1                           | same handle (no-op copy)?
        BEQ.B   COPYRGN_EXIT                    | YES, QUIT
        MOVE.L  (A0),A0                         | DE-REFERENCE SRCRGN HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE DSTRGN HANDLE
        MOVE    (A0),D0                         | GET SRCRGN SIZE
        CMP     (A1),D0                         | IS DSTRGN SIZE SAME AS SRCRGN SIZE?
        BEQ.B   COPYRGN_OK                      | YES, CONTINUE
        MOVEM.L D0/D3/A2,-(SP)                  | SAVE REGS AND BYTECOUNT
        MOVE.L  8(A6),-(SP)                     | PUSH DSTRGN HANDLE
        MOVE    D0,-(SP)                        | PUSH NEWSIZE=SRC SIZE
        JSR     SetHSize(PC)                    | CHANGE SIZE OF DST
        MOVEM.L (SP)+,D0/D3/A2                  | RESTORE REGS AND BYTECOUNT
        MOVE.L  12(A6),A0                       | GET SRCRGN HANDLE
        MOVE.L  8(A6),A1                        | GET DSTRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE SRCRGN HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE DSTRGN HANDLE
COPYRGN_OK:
        LSR     #0x2,D0                         | LONGCOUNT := BYTECOUNT DIV 4
        BCC.B   COPYRGN_OK_2                    | WAS THERE AN ODD WORD ?
        MOVE    (A0)+,(A1)+                     | YES, DO IT TO MAKE EVEN
        BRA.B   COPYRGN_OK_2                    | AND CONTINUE
COPYRGN_LOOP:
        MOVE.L  (A0)+,(A1)+                     | PUSH RIGHT,BOTTOM
COPYRGN_OK_2:
        DBRA    D0,COPYRGN_LOOP                 | LOOP FOR ALL LONGS
COPYRGN_EXIT:
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS

| .PROC SetEmptyRgn,1
| .REF SetRectRgn
| ---------------------------------------------------
| PROCEDURE SetEmptyRgn(rgn: RgnHandle);
| Called during boot.
SetEmptyRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        CLR.L   -(SP)                           | PUSH LEFT, TOP
        CLR.L   -(SP)                           | PUSH RIGHT,BOTTOM
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        JMP     SetRectRgn(PC)                  | DOUBLE UP ON CODE
SetRectRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        MOVE.L  16(A6),A0                       | GET RGN HANDLE
        MOVE.L  (A0),A1                         | DE-REFERENCE HANDLE
        CMPI    #0xA,(A1)                       | IS HORIZ END MARKER?
        BEQ.B   SETRECTRGN_OK                   | YES, CONTINUE
        MOVE.L  A0,-(SP)                        | PUSH RGNHANDLE
        MOVE    #0xA,-(SP)                      | push newSize = 10 (rect rgn)
        JSR     SetHSize(PC)                    | CHANGE SIZE OF REGION
        MOVE.L  16(A6),A0                       | GET RGN HANDLE
        MOVE.L  (A0),A1                         | DE-REFERENCE HANDLE
        MOVE    #0xA,(A1)                       | install rgnSize := 10
SETRECTRGN_OK:
        MOVE.L  12(A6),2(A1)                    | SET TOPLEFT
        MOVE.L  8(A6),6(A1)                     | SET BOTRIGHT
        MOVE    4(A1),D0                        | GET LEFT
        CMP     8(A1),D0                        | COMPARE TO RIGHT
        BGE.B   SETRECTRGN_EMPTY                | YES, SET TO EMPTY
        MOVE    2(A1),D0                        | GET TOP
        CMP     6(A1),D0                        | COMPARE TO BOTTOM
        BLT.B   SETRECTRGN_DONE                 | YES, CONTINUE
SETRECTRGN_EMPTY:
        CLR.L   2(A1)                           | rgnBBox topLeft := (0,0)
        CLR.L   6(A1)                           | rgnBBox botRight := (0,0)
SETRECTRGN_DONE:
        MOVEM.L (SP)+,D3/A2                     | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS
RectRgn:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.L  (A1)+,-(SP)                     | PUSH LEFT,TOP
        MOVE.L  (A1)+,-(SP)                     | PUSH RIGHT,BOTTOM
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        JMP     SetRectRgn(PC)                  | DOUBLE UP ON CODE

| .PROC OffsetRgn
| ---------------------------------------------------------
| PROCEDURE OffsetRgn(rgn: RgnHandle; dh,dv: INTEGER);
| Called during boot.
OffsetRgn:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | POP DV
        MOVE    (SP)+,D0                        | POP DH
        MOVE.L  (SP)+,A0                        | POP RGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        ADDQ.W  #0x2,A0                         | SKIP REGION SIZE
        ADD     D1,(A0)+                        | ADD DV TO TOP
        ADD     D0,(A0)+                        | ADD DH TO LEFT
        ADD     D1,(A0)+                        | ADD DV TO BOTTOM
        ADD     D0,(A0)+                        | ADD DH TO RIGHT
        CMPI    #0xA,-10(A0)                    | IS REGION RECTANGULAR?
        BEQ.B   OFFSETRGN_NXTHOR_DONE           | IF SO, WE'RE ALL DONE
OFFSETRGN_LOOP:
        ADD.W    D1,(A0)+                       | offset vert coord by dv
OFFSETRGN_NXTHOR:
        ADD     D0,(A0)+                        | NXTHOR: OFFSET LEFT COORD DH
        ADD     D0,(A0)+                        | OFFSET RIGHT COORD DH
        CMPI    #0x7FFF,(A0)                    | IS HORIZ END MARKER?
        BNE.B   OFFSETRGN_NXTHOR                | NO, LOOP
        ADDQ.W  #0x2,A0                         | SKIP REGION SIZE
        CMPI    #0x7FFF,(A0)                    | IS HORIZ END MARKER?
        BNE.B   OFFSETRGN_LOOP                  | NO, LOOP FOR MORE
OFFSETRGN_NXTHOR_DONE:
        JMP     (A1)                            | RETURN
InsetRgn:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  8(A6),D6                        | D6 := dv:dh as long
        BEQ.W   SWAP2_CONT                      | QUIT IF BOTH ARE ZERO
        MOVE.L  12(A6),A4                       | GET RGNHANDLE
        MOVE.L  (A4),A3                         | DE-REFERENCE IT
        MOVE    (A3)+,D7                        | GET RGNSIZE
        CMPI    #0xA,D7                         | is rgn rectangular?
        BNE.B   INSETRGN_NOTRECT                | NO, CONTINUE
        MOVE.L  A3,-(SP)                        | PUSH ADDR OF RGNBBOX
        MOVE.L  D6,-(SP)                        | PUSH DH AND DV
        JSR     InsetRect(PC)                   | InsetRect(rgn^^.rgnbbox,dh,dv);
        MOVE    2(A3),D0                        | GET BBOX LEFT
        CMP     6(A3),D0                        | IS LEFT >= RIGHT ?
        BGE.B   INSETRGN_EMPTY                  | YES, RETURN EMPTY RGN
        MOVE    (A3),D0                         | get bbox.top
        CMP     4(A3),D0                        | IS TOP >= BOTTOM ?
        BLT.W   SWAP2_CONT                      | NO, CONTINUE
INSETRGN_EMPTY:
        CLR.L   (A3)+                           | SET RGNBBOX TO (0,0,0,0) TO
        CLR.L   (A3)+                           | RETURN EMPTY REGION
        BRA.W   SWAP2_CONT                      | jump via A0
INSETRGN_NOTRECT:
        ADD     D7,D7                           | NOTRECT: TRY BYTES NEEDED = RGNSIZE*2
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    D7,-(SP)                        | PUSH BYTESNEEDED
        JSR     NewHandle_Inline(PC)            | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | PUT PTBUF HANDLE IN A3
        BSR.B   HINSET                          | INSET HORIZ AND FLIP
        SWAP    D6                              | GET DV INSTEAD OF DH
        BSR.B   HINSET                          | INSET VERTICAL AND FLIP BACK
        BRA.W   INSETRGN_FINISH                 | tail-merge with shared finish code

| --------------------------------------------------------------------------
| LOCAL ROUTINE TO INSET HORIZONTALLY, SWAP H AND V COORDS, AND RE-SORT
| RgnOp(rgn,rgn,bufHandle,maxBytes,op,dh,TRUE);
HINSET:
        CLR     -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  A4,-(SP)                        | PUSH RGNA = USER RGN
        MOVE.L  A4,-(SP)                        | PUSG RGNB = USER RGN ALSO
        MOVE.L  A3,-(SP)                        | PUSH BUFHANDLE
        MOVE    D7,-(SP)                        | PUSH MAXBYTES
        MOVE    #0x8,-(SP)                      | PUSH OP = INSET
        MOVE    D6,-(SP)                        | PUSH DH
        ST      -(SP)                           | PUSH OKGROW = TRUE
        JSR     RgnOp(PC)                       | PERFORM REGION OPERATION
        MOVE    (SP)+,D5                        | POP PTCOUNT RESULT
        MOVE.L  (A3),A0                         | DE-REFERENCE PTBUF HANDLE
        MOVE    D5,D1                           | COPY PTCOUNT
        BRA.B   SWAP2                           | GO TO LOOP START

| ----------------------------------------------------------
| SWAPLP
SWAPLP:
        MOVE.L  (A0),D0                         | GET A POINT
        SWAP    D0                              | SWAP ITS COORDINATES
        MOVE.L  D0,(A0)+                        | PUT IT BACK INTO ARRAY
SWAP2:
        DBRA    D1,SWAPLP                       | LOOP FOR ALL POINTS
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D5,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | RE-SORT INTO VH ORDER
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    D5,-(SP)                        | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH RGN HANDLE
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,rgn);
        RTS                                     | RETURN TO LOCAL CALLER

INSETRGN_FINISH:                                | InsetRgn shared tail
        MOVE.L  A3,-(SP)                        | push ptBuf handle for dispose
        JSR     KillPicture(PC)                 | dispose ptBuf handle
SWAP2_CONT:
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP RGNHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        PEA.L     2(A1)                         | PUSH RGNBBOX
        MOVE.L  A0,-(SP)                        | PUSH RETURN ADDR
        JMP     EmptyRect(PC)                   | USE EMPTYRECT CODE

| .FUNC EqualRgn,2
| -------------------------------------------------------
| FUNCTION EqualRgn(rgnA,rgnB: RgnHandle): BOOLEAN;
| RETURNS TRUE IF RGNA AND RGNB DESCRIBE THE SAME AREA
| Called during boot (10,214 times in 30s trace).
EqualRgn:
        MOVE.L  4(SP),A0                        | GET RGNA HANDLE
        MOVE.L  8(SP),A1                        | GET RGNB HANDLE
        CMPA.L  A0,A1                           | same handle (trivially equal)?
        BEQ.B   EQUALRGN_LOOP2_OK               | YES, THE REGIONS ARE THE SAME
        MOVE.L  (A0),A0                         | DE-REFERENCE RGN A
        MOVE.L  (A1),A1                         | DE-REFERENCE RGN B
        MOVE    (A0),D0                         | GET RGNSIZE A
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        LSR     #0x2,D1                         | DIV BY 4 FOR LONG COUNT
        SUBQ.W  #0x1,D1                         | ADJUST FOR DBF
EQUALRGN_LOOP:
        CMPM.L  (A0)+,(A1)+                     | COMPARE A LONG
        DBNE    D1,EQUALRGN_LOOP                | LOOK TILL DIFFERENT OR COUNT
        BNE.B   EQUALRGN_LOOP2_CONT             | DIFFERENT --> FALSE
        ANDI    #0x3,D0                         | GET REMAINING BYTES
        BEQ.B   EQUALRGN_LOOP2_OK               | IF NO MORE, WE MADE IT
EQUALRGN_LOOP2:
        CMPM.B  (A0)+,(A1)+                     | COMPARE A BYTE
        BNE.B   EQUALRGN_LOOP2_CONT             | BR IF DIFFERENT
        SUBQ.W  #0x1,D0                         | decrement byte counter
        BNE.B   EQUALRGN_LOOP2                  | LOOP LAST 1..3 BYTES
EQUALRGN_LOOP2_OK:
        MOVE.B  #0x1,12(SP)                     | return TRUE in fcn result
        BRA.B   EQUALRGN_DONE                   | skip false branch
EQUALRGN_LOOP2_CONT:
        CLR.B   12(SP)                          | return FALSE in fcn result
EQUALRGN_DONE:
        MOVE.L  (SP)+,A0                        | PUSH DSTRGN
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| PROCEDURE SectRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
SectRgn:
        MOVEQ.L #0x0,D0                         | op = 0 (intersect)
        JMP     DoRgnOp(PC)                     | dispatch to common
| PROCEDURE UnionRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
UnionRgn:
        MOVEQ.L #0x4,D0                         | op = 4 (union)
        JMP     DoRgnOp(PC)                     | dispatch to common
| PROCEDURE DiffRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
DiffRgn:
        MOVEQ.L #0x2,D0                         | op = 2 (A - B)
        JMP     DoRgnOp(PC)                     | dispatch to common
| PROCEDURE XorRgn(srcRgnA, srcRgnB, dstRgn: RgnHandle);
XorRgn:
        MOVEQ.L #0x6,D0                         | op = 6 (xor)
        JMP     DoRgnOp(PC)                     | dispatch to common

| ---------------------------------------------------------
| PROCEDURE DoRgnOp(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| Computes the Intersection, Difference, Union, or Xor of two regions.
| enter with op in D0.
| op = 0: SectScan
| 2: DIFF A-B
| 4: UNION
| 6: XOR
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 12
| RGNA .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| RGNB .EQU RGNA-4 ;LONG, RGNHANDLE
| DSTRGN .EQU RGNB-4 ;LONG, RGNHANDLE
| TEMPRECT .EQU -8 ;RECT
| VARSIZE .EQU TEMPRECT ;TOTAL LOCALS
| Called during boot (10,214 times in 30s trace).
DoRgnOp:
        LINK    A6,#-0x8                        | link frame, 8 bytes locals (TEMPRECT)
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS
        MOVE    D0,D5                           | GET LEFT
        MOVE.L  16(A6),A2                       | GET RGNA
        MOVE.L  12(A6),A3                       | GET RGNB
        MOVE.L  8(A6),A4                        | GET RGNA LEFT
        CLR.B   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE.L  A2,-(SP)                        | PUSH RGNA
        MOVE.L  A3,-(SP)                        | YES, GET RGNB INSTEAD
        JSR     EqualRgn(PC)                    | CALL EQUALRGN
        TST.B   (SP)+                           | ARE THEY THE SAME ?
        BEQ.B   XORRGN_NOTSAME                  | NO, CONTINUE
        ANDI    #0x2,D5                         | test bit 1 of op (XOR/UNION = 0)
        BNE.B   XORRGN_ZERO                     | NO, ZERO OUT DSTRGN
XORRGN_COPY:
        MOVE.L  A2,-(SP)                        | PUSH RGNA
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     CopyRgn(PC)                     | COPY RGNA INTO DSTRGN
        BRA.W   JDONE_DONE                      | AND QUIT
XORRGN_ZERO:
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     SetEmptyRgn(PC)                 | SET IT TO EMPTY
        BRA.W   JDONE_DONE                      | AND QUIT
XORRGN_NOTSAME:
        MOVE.L  (A2),A0                         | DE-REFERENCE RGNA
        MOVE.L  (A3),A1                         | DE-REFERENCE RGNB
        CMPI    #0x2,D5                         | is op > 2 (UNION/XOR)?
        BGT.B   UNIXOR                          | NO, ITS UNION OR XOR
        BLT.B   BBOXES                          | NO, IT'S SECT
        MOVE    4(A1),D0                        | op == DIFF: get rgnB.left
        CMP     8(A1),D0                        | rgnB empty (left >= right)?
        BGE.B   XORRGN_COPY                     | YES, COPY RGNA INTO DST
| IF op = SectScan OR DIFF, THEN INTERSECT THE BOUNDING BOXES.
| Called during boot (10,188 times in 30s trace).
BBOXES:
        PEA.L     2(A0)                         | PUSH RGNA^^.RGNBBOX
        PEA.L     2(A1)                         | PUSH RGNB^^.RGNBBOX
        MOVE    #0x2,-(SP)                      | PUSH NRECTS = 2
        PEA.L     -8(A6)                        | PUSH DST = TEMPRECT
        JSR     RSect(PC)                       | CALC INTERSECTION
        BNE.B   BBOXES_EMPTY                    | BR IF RESULT NOT EMPTY
        TST     D5                              | IS OP = SectScan ?
        BEQ.B   XORRGN_ZERO                     | YES, RETURN EMPTY
        BRA.B   XORRGN_COPY                     | NO, COPY SRCA INTO DSTRGN
BBOXES_EMPTY:                                   | jump via A0
        MOVE.L  (A2),A0                         | DE-REFERENCE RGNA
        MOVE.L  (A3),A1                         | DE-REFERENCE RGNB
        TST     D5                              | IS OP = SECT ?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        CMPI    #0xA,(A0)                       | is rgnA rectangular?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        CMPI    #0xA,(A1)                       | is rgnB rectangular?
        BNE.B   JDONE_NO_2                      | NO, CONTINUE
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        PEA.L     -8(A6)                        | push addr of TEMPRECT
        JSR     RectRgn(PC)                     | RectRgn(dstRgn,tempRect);
        BRA.W   JDONE_DONE                      | done with two-rect Sect
UNIXOR:
        MOVE    4(A1),D0                        | GET LEFT
        CMP     8(A1),D0                        | COMPARE TO RIGHT
        BGE.B   XORRGN_COPY                     | YES, COPY RGNA INTO DST
        MOVE    4(A0),D0                        | GET RGNA LEFT
        CMP     8(A0),D0                        | COMPARE TO RGNA RIGHT
        BLT.B   JDONE_NO_2                      | NO, CONTINUE
        MOVE.L  A3,A2                           | YES, GET RGNB INSTEAD
        BRA.W   XORRGN_COPY                     | COPY RGNB INTO DST

| ----------------------------------------------------------
| JDONE_NO_2
| Called during boot (7,414 times in 30s trace).
JDONE_NO_2:
        MOVE    (A0),D4                         | GET RGNA SIZE
        ADD     (A1),D4                         | ADD RGNB SIZE
        ADD     D4,D4                           | TRY DOUBLE FOR BYTECOUNT
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    D4,-(SP)                        | PUSH BYTECOUNT
        JSR     NewHandle_Inline(PC)            | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | GET PTBUF HANDLE IN A3
        CLR     -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE.L  16(A6),-(SP)                    | PUSH RGNA
        MOVE.L  12(A6),-(SP)                    | PUSH RGNB
        MOVE.L  A3,-(SP)                        | PUSH BUFHANDLE
        MOVE    D4,-(SP)                        | PUSH MAXBYTES
        MOVE    D5,-(SP)                        | PUSH OP
        CLR     -(SP)                           | PUSH DH=0
        ST      -(SP)                           | PUSH OKGROW = TRUE
        JSR     RgnOp(PC)                       | PERFORM REGION OPERATION
        MOVE    (SP)+,D6                        | GET PTCOUNT
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    D6,-(SP)                        | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH DSTRGN
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,dstRgn);
        MOVE.L  A3,-(SP)                        | push ptBuf handle for dispose
        JSR      KillPicture(PC)                | PackRgn(ptBuf,ptCount,dstRgn);
JDONE_DONE:                                     | jump via A0
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PtInRgn -- _PtInRgn ($A8E8). Plus Regions.s 976.
| Tests if a point is inside a region. Uses bbox check first,
| then walks the inversion-point list for non-rectangular regions.
PtInRgn:
        LINK    A6,#0x0                         | ENTRY: NO LOCAL VARS
        MOVE.L  D3,-(SP)                        | SAVE REG
        MOVE    14(A6),D1                       | GET PT.H
        MOVE    12(A6),D2                       | GET PT.V
        CLR     D3                              | INIT INSIDE:=FALSE
        MOVE.L  8(A6),A0                        | GET RGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMP     4(A0),D1                        | IS PT.H < BBOX LEFT?
        BLT.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     8(A0),D1                        | IS PT.H >= BBOX RIGHT?
        BGE.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     2(A0),D2                        | IS PT.V < BBOX TOP?
        BLT.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMP     6(A0),D2                        | IS PT.V >= BBOX BOTTOM?
        BGE.B   NEXTHOR_EXIT                    | YES, RETURN FALSE
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR?
        BNE.B   PTINRGN_NO                      | NO, CONTINUE
        NOT     D3                              | YES, RETURN TRUE
        BRA.B   NEXTHOR_EXIT                    | GO TO DONE
PTINRGN_NO:
        LEA.L     10(A0),A0                     | POINT TO FIRST VERT COORD
PTINRGN_NEXT:
        CMP     (A0)+,D2                        | IS NEXT VERT > PT.V ?
        BLT.B   NEXTHOR_EXIT                    | YES, QUIT
NEXTHOR:
        MOVE    (A0)+,D0                        | GET HORIZ COORD
        CMPI    #0x7FFF,D0                      | IS HORIZ END MARKER?
        BEQ.B   PTINRGN_NEXT                    | YES, GET NEXT VERT COORD
        CMP     D1,D0                           | IS HORIZ <= PT.H ?
        BGT.B   NEXTHOR                         | NO, IGNORE THIS POINT
        NOT     D3                              | YES, TOGGLE INSIDE
        BRA.B   NEXTHOR                         | AND GO FOR MORE POINTS

| ----------------------------------------------------------
| NEXTHOR_EXIT
| Called during boot (4,005 times in 30s trace).
NEXTHOR_EXIT:
        NEG.B   D3                              | DONE: BOOLEAN RESULT IS 0 OR 1
        MOVE.B  D3,0x10(A6)                     | RETURN BOOLEAN FCN RESULT
        MOVE.L  (SP)+,D3                        | RESTORE REG
        UNLK    A6                              | RELEASE STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER
        LINK    A6,#-0x24                       | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGISTERS
        MOVE.L  SP,-12(A6)                      | SAVESTK := SP for buffer cleanup
        CLR.B   16(A6)                          | INIT BOOLEAN RESULT TO FALSE
        MOVE.L  8(A6),A1                        | GET REGION HANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE IT
        MOVE.L  12(A6),-(SP)                    | PUSH POINTER TO RECT
        PEA.L     2(A1)                         | PUSH POINTER TO RGN BBOX
        MOVE    #0x2,-(SP)                      | push nRects = 2
        PEA.L     -8(A6)                        | push addr of MINRECT (dst)
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ.W   TRUE_EXIT                       | QUIT IF NO INTERSECTION
        CMPI    #0xA,(A1)                       | is rgn rectangular?
        BEQ.W   TRUE                            | YES, RETURN TRUE
        MOVE.L  A1,A0                           | GET RGNPTR IN A0
        LEA.L     -0x24(A6),A1                  | A1 := state record addr
        MOVE    -6(A6),D0                       | D0 := minH (minRect.left)
        MOVE    -2(A6),D1                       | D1 := maxH (minRect.right)
        MOVE    D0,D2                           | BUFLEFT:=MINH
        JSR     InitRgn(PC)                     | INIT RECORD, ALLOCATE BUFFER
        MOVE    20(A1),D5                       | GET BUFSIZE= # LONGS -1
        LSR     #0x5,D5                         | div by 32 bits per long
        MOVE    -8(A6),D0                       | D0 := minRect.top (start vert)
        JSR     SeekRgn(PC)                     | SEEK THE REGION TO MINRECT TOP
        MOVE    -4(A6),D6                       | D6 := minRect.bottom (limit vert)
TESTBUF:
        MOVE.L  8(A1),A0                        | POP RETURN ADDR
        MOVE    D5,D0                           | INIT LOOP COUNT TO BUFSIZE
NXTLONG:                                        | jump via A0
        TST.L   (A0)+                           | IS SCAN BUF NON-ZERO ?
        DBNE    D0,NXTLONG                      | TEST LONGS TILL NON ZERO OR END
        BNE.B   TRUE                            | WE FOUND A NON-ZERO, RETURN TRUE
        MOVE    16(A1),D0                       | GET NEXT VERTICAL IN RGN
        CMP     D0,D6                           | IS NEXT RGN VERT BEYOND BOTTOM ?
        BLE.B   TRUE_EXIT                       | YES, RETURN FALSE
        JSR     SeekRgn(PC)                     | NO, SEEK TO NEXT VERT CHANGE
        BRA.B   TESTBUF                         | AND SEE IF IT IS NON-ZERO
TRUE:
        ADDQ.B  #0x1,16(A6)                     | 16(A6) += 0x1
TRUE_EXIT:
        MOVE.L  -12(A6),SP                      | restore SP from SAVESTK (free buf)
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
RectInRgn:
        LINK    A6,#-0x2A                       | set up stack frame
        MOVEM.L D0-D7/A1-A4,-(SP)               | save D0-D7,A1-A4
        CLR.B   16(A6)                          | boolean fcn result := FALSE
        LEA.L     -24(A6),A0                    | A0 := local rectRgn body
        MOVE.L  A0,-28(A6)                      | save body ptr
        LEA.L     -0x26(A6),A1                  | A1 := local rectRgn handle slot
        MOVE.L  A1,-0x2A(A6)                    | save handle slot ptr
        MOVE    #0xA,(A1)+                      | rectRgn.size := 10 (rect)
        MOVE.L  8(A6),A0                        | POINT TO DSTRECT
        MOVE.L  (A0)+,(A1)+                     | COPY DSTRECT TOPLEFT
        MOVE.L  (A0)+,(A1)+                     | COPY DSTRECT BOTRIGHT
        CLR     -(SP)                           | room for RgnOp result
        MOVE.L  12(A6),-(SP)                    | PUSH RGN
        PEA.L     -0x2A(A6)                     | push pseudo-handle of rectRgn
        PEA.L     -28(A6)                       | push ptBuf handle slot
        MOVE    #0x18,-(SP)                     | push maxBytes = 24
        CLR.L   -(SP)                           | PUSH OP = SECT, DH = 0
        CLR.B   -(SP)                           | PUSH OKGROW = FALSE
        JSR     RgnOp(PC)                       | RgnOp(rgn,rectRgn,buf,64,op,dh,FALSE);
        MOVE.L  8(A6),A0                        | POINT TO DSTRECT
        CMPI    #0x4,(SP)+                      | ptCount: > 4 = non-rect intersection
        BGT.B   RECTINRGN_RETURN                | yes, return false (non-rect)
        BLT.B   RECTINRGN_CLR                   | < 4: empty
        MOVE.L  -24(A6),(A0)+                   | copy intersection topLeft to dst
        MOVE.L  -12(A6),(A0)+                   | copy intersection botRight to dst
        BRA.B   RECTINRGN_SET                   | set true result
RECTINRGN_CLR:
        CLR.L   (A0)+                           | dstRect topLeft := (0,0)
        CLR.L   (A0)+                           | dstRect botRight := (0,0)
RECTINRGN_SET:
        ADDQ.B  #0x1,16(A6)                     | 16(A6) += 0x1
RECTINRGN_RETURN:
        MOVEM.L (SP)+,D0-D7/A1-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR INTO A0
        ADDQ.W  #0x8,SP                         | ADVANCE TO NEXT POINT
        JMP     (A0)                            | RTS

| .PROC MapRgn,3
| .REF MapRect,NewHandle,PutRgn,MapPt
| .REF SortPoints,CullPoints,PackRgn
| -------------------------------------------------------------
| PROCEDURE MapRgn(rgn: RgnHandle; fromRect,toRect: Rect);
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 12
| RGN .EQU PARAMSIZE+8-4 ;LONG, RGNHANDLE
| FROMRECT .EQU RGN-4 ;LONG, ADDR OF RECT
| TORECT .EQU FROMRECT-4 ;LONG, ADDR OF RECT
MapRgn:
        LINK    A6,#-0x6                        | ESTABLISH STACK FRAME
        MOVEM.L D3/D6-D7/A2-A4,-(SP)            | SAVE REGS
        MOVE.L  12(A6),A0                       | POINT TO FROMRECT
        MOVE.L  8(A6),A1                        | POINT TO TORECT
        CMPM.L  (A0)+,(A1)+                     | IS TOPLEFT SAME ?
        BNE.B   MAPRGN_NO                       | NO, CONTINUE
        CMPM.L  (A0)+,(A1)+                     | YES, IS BOTRIGHT SAME TOO ?
        BEQ.W   PLUS_5_CONT                     | jump via A0
| SPECIAL CASE RECTANGULAR RGN
MAPRGN_NO:
        MOVE.L  16(A6),A4                       | GET RGNHANDLE
        MOVE.L  (A4),A0                         | DE-REFERENCE RGN
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR?
        BNE.B   MAPRGN_NO_2                     | NO, CONTINUE
        PEA.L     2(A0)                         | YES, PUSH RGNBBOX
        MOVE.L  12(A6),-(SP)                    | PUSH FROMRECT
        MOVE.L  8(A6),-(SP)                     | PUSH TO RECT
        JSR     MapRect(PC)                     | MapRect(rgn^^.rgnBBox,from,to);
        BRA.B   PLUS_5_CONT                     | rect rgn done, exit
MAPRGN_NO_2:
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    #0x100,-(SP)                    | push byteCount = 256
        JSR     NewHandle_Inline(PC)            | ALLOCATE PTBUF
        MOVE.L  (SP)+,A3                        | GET PTBUF HANDLE IN A3
        CLR     -2(A6)                          | local index := 0
        MOVE    #0x100,-4(A6)                   | local size := 256
        MOVE.L  A4,-(SP)                        | PUSH RGN
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        PEA.L     -2(A6)                        | push var index addr
        PEA.L     -4(A6)                        | push var size addr
        JSR     PutRgn(PC)                      | UNPACK RGN INTO INVERSION PTS
        MOVE    -2(A6),D7                       | get final index (bytes used)
        LSR     #0x2,D7                         | ptCount := index / 4
        MOVE    D7,D6                           | COPY PTCOUNT FOR LOOP COUNT
        MOVE.L  (A3),A2                         | DE-REFERENCE PTBUF HANDLE
        BRA.B   MAPRGN_LOOP_2                   | GO TO LOOP START
MAPRGN_LOOP:
        MOVE.L  A2,-(SP)                        | LOOP: PUSH ADDR OF AN INV PT
        MOVE.L  12(A6),-(SP)                    | PUSH FROMRECT
        MOVE.L  8(A6),-(SP)                     | PUSH TORECT
        JSR     MapPt(PC)                       | MAP THIS POINT
        ADDQ.L  #0x4,A2                         | ADVANCE TO NEXT POINT
MAPRGN_LOOP_2:
        DBRA    D6,MAPRGN_LOOP                  | LOOP ALL INVERSION POINTS
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D7,-(SP)                        | PUSH PTCOUNT
        JSR     SortPoints(PC)                  | SortPoints(ptBuf^,ptCount)
        MOVE.L  (A3),-(SP)                      | PUSH PTBUF PTR
        MOVE    D7,-6(A6)                       | PUT PTCOUNT IN MEMORY
        PEA.L     -6(A6)                        | PUSH VAR PTCOUNT
        JSR     CullPoints(PC)                  | CullPoints(ptBuf^,ptCount)
        MOVE.L  A3,-(SP)                        | PUSH PTBUF HANDLE
        MOVE    -6(A6),-(SP)                    | PUSH PTCOUNT
        MOVE.L  A4,-(SP)                        | PUSH RGN
        JSR     PackRgn(PC)                     | PackRgn(ptBuf,ptCount,rgn);
        MOVE.L  A3,-(SP)                        | push ptBuf handle for dispose
        JSR     KillPicture(PC)                 | PackRgn(ptBuf,ptCount,rgn);
PLUS_5_CONT:
        MOVEM.L (SP)+,D3/D6-D7/A2-A4            | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS

| ------------------------------------------------------------------
| --> SEEKRGN.TEXT
| Routines to play back a region into a scanline buffer.
| .PROC INITRGN,0
| ------------------------------------------------------
| INPUTS: A0: RGNPTR
| A1: STATE RECORD
| D0: MINH
| D1: MAXH
| D2: BUFLEFT
| OUTPUTS: ALL FIELDS OF STATE RECORD,
| SCANBUF ALLOCATED ON STACK
| CLOBBERS: D0,D1,A0
| Called during boot.
InitRgn:
        MOVE    D0,18(A1)                       | INSTALL MINH
        MOVE    D1,20(A1)                       | SAVE VERT
        MOVE    D2,22(A1)                       | INSTALL LEFTH
        MOVE.L  A0,(A1)                         | state.rgnPtr := A0
        MOVE    #-0x7FFF,14(A1)                 | state.thisV := -32767 (init)
        MOVE    2(A0),16(A1)                    | state.nextV := rgn first vert
        LEA.L     10(A0),A0                     | POINT TO FIRST DATA
        MOVE.L  A0,4(A1)                        | INIT DATAPTR
        MOVE.L  (SP)+,A0                        | NEXTHOR: GET LEFT COORD
        SUB     D2,D1                           | CALC BUFFER WIDTH IN DOTS
        LSR     #0x5,D1                         | div by 32 dots-per-long - 1
        MOVE    D1,12(A1)                       | GET RIGHT COORD
INITRGN_CLRLOOP:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR BUFFER
        DBRA    D1,INITRGN_CLRLOOP              | loop until full scanbuf
        MOVE.L  SP,8(A1)                        | REMEMBER BUFFER START
        JMP     (A0)                            | RTS

| ----------------------------------------------------
| RETURN QUICKLY IF SCANBUF IS ALREADY CURRENT.

| .PROC SEEKRGN,0
| .REF MaskTab
| ------------------------------------------------------------------
| SeekRgn(rgnState,vert);
| ROUTINE TO PLAY BACK A REGION FORWARD OR BACKWARD UNTIL ITS SCAN
| BUFFER CONTAINS THE BITMAP FOR THE GIVEN VERTICAL COORDINATE.
| INPUTS: A1 POINTS TO A REGION STATE RECORD
| DO CONTAINS THE DESIRED VERTICAL COORD
| OUTPUTS: UPDATES THISV, NEXTV, DATAPTR, AND SCANBUF^ OF STATE RECORD
| D1-->1 IF CHANGE, 0 IF NO CHANGE. (Z-FLAG SET IF NO CHANGE)
| CLOBBERS: A0,D1.
| Called during boot (1,767 times in 30s trace).
SeekRgn:
        CMP     16(A1),D0                       | IS DESIRED VERT >= NEXTV ?
        BGE.B   SEEKRGN_CLRLP_CONT              | YES, BUMP DOWNWARD
        CMP     14(A1),D0                       | IS DESIRED VERT < CURRENT VERT ?
        BLT.B   SEEKRGN_CONT                    | backward seek: rewind
        CLR     D1                              | ELSE REPORT NO CHANGES
        RTS                                     | AND RETURN
SEEKRGN_CONT:
        MOVE.L  8(A1),A0                        | POINT TO SCANBUF
        MOVE    12(A1),D1                       | GET BUFFER SIZE
SEEKRGN_CLRLP:
        CLR.L   (A0)+                           | CLEAR A LONG
        DBRA    D1,SEEKRGN_CLRLP                | LOOP ENTIRE SCANBUF
        MOVE.L  (A1),A0                         | A0 := state.rgnPtr (rewind)
        MOVE    2(A0),16(A1)                    | state.nextV := rgn first vert
        MOVE    #-0x7FFF,14(A1)                 | state.thisV := -32767
        LEA.L     10(A0),A0                     | POINT TO START OF REGION DATA
        MOVE.L  A0,4(A1)                        | RESET DATAPTR
        CMP     16(A1),D0                       | IS DESIRED VERT >= NEXTV ?
        BLT.W   SEEKRGN_DONE                    | NO, QUIT
SEEKRGN_CLRLP_CONT:
        MOVEM.L D0-D6/A2-A3,-(SP)               | SAVE REGS
        MOVE    D0,D2                           | SAVE VERT
        MOVE.L  4(A1),A2                        | POINT TO VERT COORD
SEEKRGN_CLRLP_CONT_2:
        MOVE    (A2)+,14(A1)                    | UPDATE CURRENT VERT
| -------------------------------------------------
| GET LEFT AND RIGHT HORIZ COORDS
| AND TRIM AGAINST MINH AND MAXH
| Called during boot.
SEEKRGN_NEXTHOR:
        MOVE    (A2)+,D3                        | GET LEFT COORD
        CMPI    #0x7FFF,D3                      | is left horiz end marker (32767)?
        BEQ.B   DONE1                           | YES, QUIT
        MOVE    (A2)+,D4                        | GET RIGHT COORD
        CMP     18(A1),D4                       | IS RIGHT <= MINH ?
        BLE.B   SEEKRGN_NEXTHOR                 | YES, IGNORE ON LEFT
        CMP     20(A1),D3                       | IS LEFT >= MAXH ?
        BGE.B   SEEKRGN_NEXTHOR                 | YES, IGNORE ON RIGHT
        CMP     18(A1),D3                       | IS LEFT < MINH ?
        BGE.B   SEEKRGN_NEXTHOR_CONT            | NO, CONTINUE
        MOVE    18(A1),D3                       | YES, TRIM LEFT
SEEKRGN_NEXTHOR_CONT:
        CMP     20(A1),D4                       | IS RIGHT > MAXH ?
        BLE.B   SEEKRGN_NEXTHOR_CONT_2          | NO, CONTINUE
        MOVE    20(A1),D4                       | YES, TRIM RIGHT
SEEKRGN_NEXTHOR_CONT_2:
        SUB     22(A1),D3                       | MAKE COORDS REL TO BUFFER
        SUB     22(A1),D4                       | right relative to BUFLEFT
        MOVE    D3,D0                           | D0 := left for BitMask
        JSR     BitMask(PC)                     | compute right-pixel mask
        MOVE    D0,D5                           | D5 := left mask result
        MOVE    D4,D0                           | D0 := right for LeftMask
        JSR     LeftMask(PC)                    | compute left-pixel mask
        MOVE    D0,D6                           | D6 := right mask result
        LSR     #0x4,D3                         | left horiz / 16 (word index)
        MOVE.L  8(A1),A3                        | COPY BUFSTART
        ADDA.W  D3,A3                           | advance bufPtr by word index
        ADDA.W  D3,A3                           | INIT BUFPTR TO LEFTWORD
        LSR     #0x4,D4                         | right horiz / 16 (word index)
        SUB     D3,D4                           | WORDCOUNT:=RIGHTWORD-LEFTWORD
        BGT.B   NOTIN1                          | BR IF NOT ALL IN ONE
        AND     D5,D6                           | COMBINE LEFT AND RIGHT MASKS
        EOR     D6,(A3)                         | XOR COMBINATION INTO BUFFER
        BRA.B   SEEKRGN_NEXTHOR                 | GO FOR MORE DH'S THIS SCAN
NOTIN1:
        EOR     D5,(A3)+                        | XOR LEFTMASK INTO BUFFER
        BRA.B   INVLONG_CONT                    | SEE IF ANY FULL WORDS
INVLONG:
        NOT.L   (A3)+                           | (A3)+ = ~(A3)+
INVLONG_CONT:
        SUBQ.W  #0x2,D4                         | decrement word count by 2 (long)
        BGT.B   INVLONG                         | YES, AT LEAST 2
        BLT.B   ENDWORD                         | NO, FINISH UP LAST WITH MASK
        NOT     (A3)+                           | (A3)+ = ~(A3)+
ENDWORD:
        EOR     D6,(A3)                         | XOR RIGHTMASK INTO BUFFER
        BRA.B   SEEKRGN_NEXTHOR                 | GO FOR MORE DH'S THIS SCAN
DONE1:
        MOVE.L  A2,4(A1)                        | GET NEXT VERT IN A
        MOVE    (A2),16(A1)                     | UPDATE NEXT VERT
        CMP     16(A1),D2                       | IS DESIRED VERT >= NEXTV ?
        BGE.B   SEEKRGN_CLRLP_CONT_2            | YES, BUMP DOWN SOME MORE
        MOVEM.L (SP)+,D0-D6/A2-A3               | RESTORE REGS
SEEKRGN_DONE:
        MOVE    #0x1,D1                         | return D1=1 (changes happened)
        RTS                                     | AND RETURN
RgnOp:
        LINK.W   FP,#-562                       | link frame, 562 bytes locals
        MOVEM.L  D3-D7/A2-A4,-(SP)              | save D3-D7,A2-A4
        LEA.L     -0x22E(A6),A2                 | A2 := scan working area
        LEA.L     24(A6),A0                     | A0 := arg slot for rgnA handle
        BSR.W   EXPAND                          | expand rgnA scanlines into buf
        MOVE.L  A0,A3                           | A3 := PTRA (rgnA scan ptr)
        LEA.L     20(A6),A0                     | A0 := arg slot for rgnB handle
        BSR.W   EXPAND                          | expand rgnB scanlines into buf
        MOVE.L  A0,A4                           | POINT TO SCANA
        LEA     SectScan(PC),A0                 | default op proc = SectScan
        MOVE    12(A6),D0                       | POINT TO TEMPSCAN
        BEQ.B   CASEOK                          | op==0 (Sect), use SectScan
        LEA     DiffScan(PC),A0                 | op proc = DiffScan
        SUBQ.W  #0x2,D0                         | op -= 2 (test op==2)
        BEQ.B   CASEOK                          | op==2 (Diff), use DiffScan
        LEA     UnionScan(PC),A0                | op proc = UnionScan
        SUBQ.W  #0x2,D0                         | op -= 2 (test op==4)
        BEQ.B   CASEOK                          | op==4 (Union), use UnionScan
        LEA     XORSCAN_TRAMP(PC),A0            | op proc = XorScan
        SUBQ.W  #0x2,D0                         | op -= 2 (test op==6)
        BEQ.B   CASEOK                          | op==6 (Xor), use XorScan
        LEA     InsetScan(PC),A0                | op == 8 (Inset), use InsetScan
CASEOK:
        MOVE.L  A0,-0x232(A6)                   | POINT TO DST POINT BUFFER
        MOVE.L  16(A6),A0                       | GET BUFLIMIT
        MOVE.L  (A0),A0                         | GET VERT COORD IN HI WORD
        MOVE.L  A0,-0x1FE(A6)                   | save BUFLIMIT (rgnA buffer top)
        ANDI    #-0x8,14(A6)                    | 14(A6) &= -0x8
        ADDA.W  14(A6),A0                       | A0 += rounded maxBytes
        MOVE.L  A0,-0x202(A6)                   | insert horiz coordinate into low word of D0
        LEA.L     -0x64(A6),A0                  | A0 := SCANA addr
        MOVE.L  A0,D4                           | D4 := SCANA ptr
        MOVE    #0x7FFF,(A0)                    | SCANA[0] := 32767 (sentinel)
        LEA.L     -0xC8(A6),A0                  | A0 := SCANB addr
        MOVE.L  A0,D5                           | D5 := SCANB ptr
        MOVE    #0x7FFF,(A0)                    | SCANB[0] := 32767 (sentinel)
        LEA.L     -0x12C(A6),A0                 | A0 := SCANC addr (output)
        MOVE.L  A0,D6                           | D6 := SCANC ptr
        MOVE    #0x7FFF,(A0)                    | SCANC[0] := 32767 (sentinel)
        LEA.L     -0x190(A6),A0                 | A0 := TEMPSCAN addr
        MOVE.L  A0,D7                           | D7 := TEMPSCAN ptr
        MOVE    (A3)+,-0x1F6(A6)                | NEXTA := next vert from PTRA
        MOVE    (A4)+,-0x1F8(A6)                | NEXTB := next vert from PTRB
        CMPI    #0x8,12(A6)                     | is op == INSET (8)?
        BNE.B   RGNOP_NXTVERT                   | no, continue normally
        MOVE    #0x7FFF,-0x1F8(A6)              | INSET op: NEXTB := 32767 (ignore B)
RGNOP_NXTVERT:
        MOVE    -0x1F6(A6),D0                   | get NEXTA
        CMP     -0x1F8(A6),D0                   | compare to NEXTB
        BEQ.B   BOTH                            | same vert: update both
        BGT.B   UPDATEB                         | MORE THAN 4, NOT RECTANGULAR
        BSR.W   UPDATEA                         | NEXTA earlier: update A only
        BRA.B   CALC                            | INSTALL RGNSIZE AND BBOX AND QUIT
BOTH:
        CMPI    #0x7FFF,D0                      | both at 32767 sentinel?
        BEQ.W   RGNOP_DONE                      | yes, regions exhausted
        BSR.W   UPDATEA                         | update A scan
UPDATEB:
        BSR.W   UPDATEA_CONT                    | update B scan

| ---------------------------------------------------------
| CALCULATE SectScan, DIFF, UNION, XOR, OR INSET INTO SCANC
| Called during boot (63,457 times in 30s trace).
CALC:
        MOVE.L  D4,A0                           | A0 := SCANA ptr
        MOVE.L  D5,A1                           | A1 := SCANB ptr
        MOVE.L  D7,A2                           | A2 := TEMPSCAN ptr (output)
        MOVE    10(A6),D2                       | D2 := dh
        PEA.L   CALC_CONT(PC)                   | push CALC_CONT as return addr
        MOVE.L  -0x232(A6),-(SP)                | push selected op proc
        RTS                                     | dispatch to op proc (returns to CALC_CONT)
CALC_CONT:
        MOVE.L  D7,A0                           | A0 := TEMPSCAN ptr
        MOVE.L  D6,A1                           | A1 := SCANC (final output)
        LEA.L     -0x1F4(A6),A2                 | A2 := working buffer
        JSR     XORSCAN_TRAMP(PC)               | merge TEMPSCAN into SCANC via XOR
        EXG     D7,D6                           | swap TEMPSCAN/SCANC ptrs
        LEA.L     -0x1F4(A6),A0                 | A0 := merged scanline buffer
        MOVE.L  -0x1FE(A6),A1                   | A1 := dst PTR for region pack
        MOVE.L  -0x202(A6),A2                   | A2 := dst limit (BUFLIMIT)
        MOVE.L  -0x1FA(A6),D0                   | D0 := current vert
        BRA.B   CALC_CONT_3                     | LOOP FOR MORE
CALC_CONT_2:
        MOVE    (A0)+,D0                        | get next horiz from merged scan
        MOVE.L  D0,(A1)+                        | emit (vert,horiz) to dst pt
        MOVE    (A0)+,D0                        | GET FIRST VERT COORD
        MOVE.L  D0,(A1)+                        | emit (vert,horiz) to dst pt
CALC_CONT_3:
        CMPA.L  A2,A1                           | dst ptr past limit?
        BCS.W   OUTTEST_NO                      | no, continue copying
        TST.B   8(A6)                           | is okGrow flag set?
        BEQ.W   RGNOP_SAVE                      | YES, CONTINUE
        MOVE.L  A0,D1                           | save A0 across SetHSize
        MOVE.L  24(A6),A0                       | A0 := PTRA save slot
        SUBA.L  (A0),A3                         | A3 := offset (PTRA - bufStart)
        MOVE.L  20(A6),A0                       | A0 := PTRB save slot
        SUBA.L  (A0),A4                         | A4 := offset (PTRB - bufStart)
        MOVE.L  16(A6),A0                       | VERT := NEXTA
        SUBA.L  (A0),A1                         | A1 := offset (dst ptr - bufStart)
        SUBA.L  (A0),A2                         | A2 := offset (limit - bufStart)
        ADDA.W  #0x100,A2                       | grow buffer by 256 bytes
        MOVEM.L D0-A2,-(SP)                     | save D0-A2 across SetHSize
        MOVE.L  A0,-(SP)                        | BUMP PTRA TO END OF SCAN
        MOVE    A2,-(SP)                        | NEXTA := NEXT VERT
        JSR     SetHSize(PC)                    | grow ptBuf to new size
        MOVEM.L (SP)+,D0-A2                     | restore D0-A2
        MOVE.L  24(A6),A0                       | A0 := PTRA save slot
        ADDA.L  (A0),A3                         | A3 := PTRA + new bufStart
        MOVE.L  20(A6),A0                       | SRCA := PTRA
        ADDA.L  (A0),A4                         | A4 := PTRB + new bufStart
        MOVE.L  16(A6),A0                       | DSTC := TEMPSCAN
        ADDA.L  (A0),A1                         | A1 := dst ptr + new bufStart
        ADDA.L  (A0),A2                         | A2 := new buffer limit
        MOVE.L  A2,-0x202(A6)                   | NEXTA := NEXT VERT
        MOVEA.L  D1,A0                          | restore A0 from D1
OUTTEST_NO:
        CMPI    #0x7FFF,(A0)                    | is current entry sentinel (32767)?
        BNE.B   CALC_CONT_2                     | NO, CONTINUE
        MOVE.L  A1,-0x1FE(A6)                   | save dst ptr (BUFLIMIT)
        BRA.W   RGNOP_NXTVERT                   | UPDATE INDEX AND QUIT
| ----------------------------------------------------------
| UPDATEA
| Called during boot (30,111 times in 30s trace).
UPDATEA:
        MOVE    -0x1F6(A6),-0x1FA(A6)           | VERT := NEXTA
        MOVE.L  A3,A0                           | SRCA := PTRA
        MOVE.L  D4,A1                           | GET NEXT A
        MOVE.L  D7,A2                           | GET NEXT B
        JSR     XORSCAN_TRAMP(PC)               | XORSCAN(PTRA,SCANA,TEMPSCAN)
        MOVE.L  A0,A3                           | BUMP PTRA TO END OF SCAN
        MOVE    (A3)+,-0x1F6(A6)                | NEXTA := NEXT VERT
        EXG     D4,D7                           | SWAP SCANA AND TEMPSCAN
        RTS                                     | RETURN TO LOCAL CALLER
UPDATEA_CONT:
        MOVE    -0x1F8(A6),-0x1FA(A6)           | GET NEXT B
        MOVE.L  A4,A0                           | SRCA := PTRB
        MOVE.L  D5,A1                           | ALESS: PUT A TO DST
        MOVE.L  D7,A2                           | GET NEXT A
        JSR     XORSCAN_TRAMP(PC)               | XORSCAN(PTRB,SCANB,TEMPSCAN)
        MOVE.L  A0,A4                           | BUMP PTRB TO END OF SCAN
        MOVE    (A4)+,-0x1F8(A6)                | NEXTB := NEXT VERT
        EXG     D7,D5                           | SWAP SCANB AND TEMPSCAN
        RTS                                     | RETURN TO LOCAL CALLER
EXPAND:
        MOVE.L  (A0),A1                         | GET RGNHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        CMPI    #0xA,(A1)                       | IS REGION RECTANGULAR ?
        BNE.B   EXPAND_DONE                     | NO, DON'T EXPAND IT
        MOVE.L  A2,(A0)                         | POINT HANDLE TO FAKE MASTER
        LEA.L     -6(A2),A0                     | POINT 10 BYTES BEFORE DATA
        MOVE.L  A0,(A2)+                        | FILL IN FAKE MASTER
        MOVE.L  2(A1),(A2)+                     | PUT TOP V AND LEFT H
        MOVE    8(A1),(A2)+                     | PUT RIGHT HORIZ
        MOVE    #0x7FFF,(A2)+                   | PUT HORIZ TERMINATOR
        MOVE    6(A1),(A2)+                     | PUT BOTTOM VERT
        MOVE    4(A1),(A2)+                     | PUT LEFT HORIZ
        MOVE    8(A1),(A2)+                     | PUT RIGHT HORIZ
        MOVE    #0x7FFF,(A2)+                   | PUT HORIZ TERMINATOR
        MOVE    #0x7FFF,(A2)+                   | PUT VERT TERMINATOR
        MOVE.L  A0,A1                           | PUT FAKE RGNPTR IN A1
EXPAND_DONE:
        LEA.L     10(A1),A0                     | OFFSET TO FIRST REGION DATA
        RTS                                     | AND RETURN
RGNOP_SAVE:
        MOVE.L  A1,-0x1FE(A6)                   | ABORT: UPDATE BUFPTR
RGNOP_DONE:
        MOVE.L  -0x1FE(A6),D0                   | GET BUFPTR
        MOVE.L  16(A6),A0                       | SHARE: GET NEXTA
        SUB.L   (A0),D0                         | BYTES USED = BUFPTR - BUFSTART
        LSR     #0x2,D0                         | DIV BY 4 FOR NPOINTS
        MOVE    D0,28(A6)                       | RETURN NPOINTS in RESULT
        MOVEM.L (SP)+,D3-D7/A2-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0x14,SP                        | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
XORSCAN_TRAMP:
        BRA.B   XorScan                         | trampoline to XorScan
EQUAL:
        CMPI    #0x7FFF,D0                      | ALL DONE ?
        BEQ.B   OUTOK2_EXIT                     | YES, QUIT
XorScan:
        MOVE    (A0)+,D0                        | GET NEW NEXTB
        MOVE    (A1)+,D1                        | GET NEXT B
INSETSCAN_NEXT:
        CMP     D1,D0                           | WHICH IS LESS, A OR B ?
        BEQ.B   EQUAL                           | SKIP IF NOT TRUE
        BLT.B   INSETSCAN_ALESS                 | A IS LESS
        MOVE    D1,(A2)+                        | BLESS: PUT B TO DST
        MOVE    (A1)+,D1                        | GET NEW NEXTA
        BRA.B   INSETSCAN_NEXT                  | LOOP FOR MORE
INSETSCAN_ALESS:
        MOVE    D0,(A2)+                        | ALESS: PUT A TO DST
        MOVE    (A0)+,D0                        | GET NEXT A
        BRA.B   INSETSCAN_NEXT                  | LOOP FOR MORE
OUTOK2_EXIT:
        MOVE    #0x7FFF,(A2)+                   | PUT NEXTB
        RTS                                     | return from XorScan/InsetScan

| .PROC SectScan,3
| .DEF DiffScan,UnionScan
| ---------------------------------------------------------
| PROCEDURE SectScan(srcA,srcB,dstC: ScanPtr);
| Calculate the intersection, difference, or union of two inversion scans.
| Each input scan is a sorted array of integers terminated by 32767.
| The output scan contains the inversion coordinates for the result.
| INPUTS: A0 SRCA
| A1 SRCB
| A2 DSTC
| CLOBBERS D0-D3, A0-A2
| Called during boot (26,410 times in 30s trace).
SectScan:
        CLR     D2                              | RESET ASTATE OFF
        CLR     D3                              | RESET BSTATE OFF
        BRA.B   SECTSCAN_SHARE                  | SHARE CODE
DiffScan:
        CLR     D2                              | RESET ASTATE OFF
        BRA.B   UNION2                          | SHARE CODE
UnionScan:
        MOVEQ.L #-0x1,D2                        | SET ASTATE ON
UNION2:
        MOVEQ.L #-0x1,D3                        | SET BSTATE ON
SECTSCAN_SHARE:
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A1)+,D1                        | GET RIGHT COORD
NEXT:
        CMP     D1,D0                           | IS NEXTA < NEXT B ?
        BLT.B   ALESS                           | YES, BRANCH
        BGT.B   BLESS                           | BR IF NEXTB IS LESS
        CMPI    #0x7FFF,D0                      | ARE WE AT THE END ?
        BEQ.B   SKIP2_EXIT                      | YES, QUIT
        CMP     D3,D2                           | ARE ASTATE AND BSTATE SAME ?
        BNE.B   SKIP0                           | NO, SKIP
        MOVE    D0,(A2)+                        | YES, PUT CHANGE
SKIP0:
        MOVE    (A0)+,D0                        | GET RIGHT COORD
        NOT     D2                              | TOGGLE ASTATE
        MOVE    (A1)+,D1                        | GET NEW NEXTB
        NOT     D3                              | TOGGLE BSTATE
        BRA.B   NEXT                            | LOOP FOR MORE
ALESS:
        TST     D3                              | TEST BSTATE
        BEQ.B   SKIP1                           | SKIP IF NOT TRUE
        MOVE    D0,(A2)+                        | PUT NEXTA
SKIP1:
        MOVE    (A0)+,D0                        | PUT RIGHT COORD
        NOT     D2                              | AND TOGGLE ASTATE
        BRA.B   NEXT                            | LOOP FOR MORE
BLESS:
        TST     D2                              | TEST ASTATE
        BEQ.B   SKIP2                           | SKIP IF NOT TRUE
        MOVE    D1,(A2)+                        | PUT NEXTB
SKIP2:
        MOVE    (A1)+,D1                        | GET NEW NEXTB
        NOT     D3                              | AND TOGGLE BSTATE
        BRA.B   NEXT                            | LOOP FOR MORE
SKIP2_EXIT:
        MOVE    #0x7FFF,(A2)+                   | PUT END MARKER INTO DST
        RTS                                     | return from SectScan/DiffScan/UnionScan

| ----------------------------------------------------------
| _FSDispatch ($A060) - HFS File Manager trap dispatcher
| D0.W = HFS selector (0-17). Validates range, then jumps
| through HFS_DISPATCH_TABLE relative offset table to the appropriate handler.
| Selectors: 0=MountVol, 1=OpenWD, 2=CloseWD, 3=CatMove,
| 4=DirCreate, 5=GetWDInfo, 6=GetFCBInfo, 7=GetCatInfo,
| 8=SetCatInfo, 9=SetVolInfo, 10=LockRng, 11=UnlockRng,
| 12=CreateFileIDRef, 13=DeleteFileIDRef, 14=ResolveFileIDRef,
| 15=ExchangeFiles, 16-17=reserved.
| On invalid selector: returns paramErr (-50) via FSQUEUE_DONE.
InsetScan:
        TST     D2                              | IS DH NEG ?
        BLT.B   OUTSET                          | YES, OUTSET
INSET:
        CMPI    #0x7FFF,(A0)                    | CHECK FOR TERMINATOR
        BEQ.B   OUTLOOP_CONT_2                  | QUIT WHEN FOUND
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A0)+,D1                        | GET RIGHT COORD
        ADD     D2,D0                           | ADD DH TO LEFT
        SUB     D2,D1                           | SUB DH FROM RIGHT
        CMP     D1,D0                           | IS LEFT >= RIGHT ?
        BGE.B   INSET                           | YES, SKIP BOTH (collapsed pair)
        MOVE    D0,(A2)+                        | PUT LEFT COORD TO DST
        MOVE    D1,(A2)+                        | PUT RIGHT COORD TO DST
        BRA.B   INSET                           | LOOP ENTIRE SCAN
OUTSET:
        MOVEA.W #0x8001,A1                      | A1 = sentinel (prev right = INT_MIN)
        BRA.B   OUTLOOP_CHECK_END               | -> end-of-row check
OUTLOOP:
        MOVE    (A0)+,D0                        | GET LEFT COORD
        MOVE    (A0)+,D1                        | GET RIGHT COORD
        ADD     D2,D0                           | ADD DH TO LEFT
        SUB     D2,D1                           | SUB DH FROM RIGHT
        CMP     A1,D0                           | IS LEFT <= OLDRIGHT ?
        BGT.B   OUTLOOP_NO                      | NO, CONTINUE
        SUBQ.W  #0x2,A2                         | OVER-WRITE PREVIOUS RIGHT
        BRA.B   OUTLOOP_CONT                    | AND CONTINUE
OUTLOOP_NO:
        MOVE    D0,(A2)+                        | OUTOK: PUT LEFT COORD
OUTLOOP_CONT:
        MOVE    D1,(A2)+                        | OUTOK2: PUT RIGHT COORD
        MOVE    D1,A1                           | OLDRIGHT := RIGHT
OUTLOOP_CHECK_END:
        CMPI    #0x7FFF,(A0)                    | START: CHECK FOR TERMINATOR
        BNE.B   OUTLOOP                         | AND LOOP ENTIRE SCAN
OUTLOOP_CONT_2:
        MOVE    #0x7FFF,(A2)+                   | COPY JPTR^ TO IPTR^
        RTS                                     | return from InsetScan/OutSet
SortPoints:
        LINK    A6,#0x0                         | NO LOCAL VARIABLES
        MOVEM.L D3-D4/A2-A4,-(SP)               | SAVE REGS
        MOVE.L  10(A6),A3                       | LEFTPTR:=START OF PT ARRAY
        MOVE    A3,D3                           | capture LO bits of LEFTPTR
        ANDI    #0x3,D3                         | SET UP LOBITS FOR SORT
        CLR.L   D0                              | clear hi word for unsigned ext
        MOVE    8(A6),D0                        | RIGHTOK: RIGHTPTR := JPTR
        BLE.W   SORTPOINTS_RIGHTOK_CONT         | DO NOTHING IF NO POINTS
        LSL.L   #0x2,D0                         | QUAD PTCOUNT FOR BYTES
        MOVE.L  A3,A4                           | A4 := DSTSTART
        ADDA.L  D0,A4                           | ADD TO DSTSTART
        SUBQ.W  #0x4,A4                         | RIGHTPTR:=DSTEND-4
        MOVE.L  SP,D4                           | REMEMBER STACK MARKER
        MOVEM.L A3-A4,-(SP)                     | PUSH LEFTPTR AND RIGHTPTR
SORTPOINTS_LOOP:
        MOVEM.L (SP)+,A3-A4                     | POPNXT: POP LEFTPTR AND RIGHTPTR
SPLIT:
        MOVE.L  A3,A1                           | jump via A0
        MOVE.L  A4,A2                           | JPTR := RIGHTPTR
        MOVE.L  A3,D0                           | ADD LEFTPTR
        ADD.L   A4,D0                           | AND RIGHTPTR
        ROXR.L  #0x1,D0                         | THEN DIVIDE BY 2 FOR MIDPTR
        ANDI    #-0x4,D0                        | TRUNC TO MULTIPLE OF 4 BYTES
        OR      D3,D0                           | OR IN LOBITS FOR POINT BOUNDARY
        MOVE.L  D0,A0                           | GET MIDPTR INTO A-REG
        MOVE    2(A0),D1                        | GET MIDPT.H
        MOVE    (A0),D2                         | AND MIDPT.V
SPLIT_RETRY:
        BRA.B   SPLIT_LOOP                      | jump to compare
SPLIT_NEXT:
        ADDQ.W  #0x4,A1                         | ONE: BUMP IPTR TO RIGHT
SPLIT_LOOP:
        CMP     (A1),D2                         | TWO: IS MIDPT.V > IPTR^.V ?
        BGT.B   SPLIT_NEXT                      | D2 > (A1): advance
        BLT.B   THREE                           | D2 < (A1): go to A2 scan
        CMP     2(A1),D1                        | IF SAME VERT, LOOK AT HORIZ
        BGT.B   SPLIT_NEXT                      | D1 > 2(A1): advance
THREE:
        BRA.B   SPLIT_LOOP_2                    | jump to compare
FOUR:
        SUBQ.W  #0x4,A2                         | FOUR: BUMP JPTR TO LEFT
SPLIT_LOOP_2:
        CMP     (A2),D2                         | FIVE: IS MIDPT.V < JPTR^.V ?
        BLT.B   FOUR                            | D2 < (A2): back up
        BGT.B   SPLIT_DONE_2                    | D2 > (A2): done
        CMP     2(A2),D1                        | IF SAME VERT, LOOK AT HORIZ
        BLT.B   FOUR                            | D1 < 2(A2): back up
SPLIT_DONE_2:
        CMPA.L  A2,A1                           | SIX: IS IPTR > JPTR ?
        BGT.B   SORTPOINTS_NOSWAP               | YES, ALL DONE
        MOVE.L  (A1),D0                         | NO, COPY TO DST
        MOVE.L  (A2),(A1)                       | SWAP POINTS step 2
        MOVE.L  D0,(A2)                         | SWAP POINTS step 3
        ADDQ.W  #0x4,A1                         | BUMP IPTR TO RIGHT
        SUBQ.W  #0x4,A2                         | BUMP JPTR TO LEFT
SORTPOINTS_NOSWAP:
        CMPA.L  A2,A1                           | NOSWAP: IS IPTR > JPTR ?
        BLS.B   SPLIT_RETRY                     | branch if <= (unsigned)
        CMPA.L  A4,A1                           | IS IPTR < RIGHTPTR ?
        BCC.W   SORTPOINTS_RIGHTOK              | YES, CONTINUE
        MOVEM.L A1/A4,-(SP)                     | NO, PUSH IPTR,RIGHTPTR
SORTPOINTS_RIGHTOK:
        MOVE.L  A2,A4                           | RIGHTPTR := JPTR
        CMPA.L  A4,A3                           | IS LEFTPTR >= RIGHTPTR ?
        BCS.B   SPLIT                           | NO, PARTITION AGAIN
        CMPA.L  D4,SP                           | IS STACK EMPTY YET ?
        BNE.B   SORTPOINTS_LOOP                 | NO, LOOP FOR MORE
SORTPOINTS_RIGHTOK_CONT:                        | jump via A0
        MOVEM.L (SP)+,D3-D4/A2-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDQ.W  #0x6,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS

| .PROC CullPoints,2
| -------------------------------------------------------------
| PROCEDURE CullPoints(ptBuf: PointsPtr; VAR ptCount: INTEGER);
| CANCEL ANY DUPLICATE PAIRS OF POINTS IN AN ARRAY OF POINTS.
| A6 OFFSETS OF PARAMETERS AFTER LINK:
| PARAMSIZE .EQU 8
| PTBUF .EQU PARAMSIZE+8-4 ;LONG
| PTCOUNT .EQU PTBUF-4 ;LONG, VAR
| Called during boot.
CullPoints:
        LINK    A6,#0x0                         | NO LOCAL VARIABLES
        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS
        MOVE.L  8(A6),A0                        | GET VAR ADDR OF PTCOUNT
        MOVE    (A0),D0                         | GET PTCOUNT
        BLE.W   CULLPOINTS_GOHOME               | DO NOTHING IF NO POINTS
        MOVE.L  12(A6),A1                       | SRCPTR:=START PTR
        MOVE.L  A1,A3                           | COPY START
        EXT.L    D0                             | CLEAR HI WORD
        LSL.L   #0x2,D0                         | QUAD PTCOUNT FOR BYTES
        ADDA.L  D0,A3                           | ADD TO START
        SUBQ.W  #0x4,A3                         | LAST POINT IS AT END-4
        MOVE.L  A1,D5                           | SAVE START FOR LATER
        MOVE.L  A1,A2                           | YES, MINH:=PT.H
        BRA.B   CULLPOINTS_WHILE1               | LOOP FOR MORE
DELETE:
        ADDQ.W  #0x4,A1                         | SKIP OVER BOTH SRC POINTS
        BRA.B   CULLPOINTS_WHILE1               | GO TO LOOP START
CULLPOINTS_MORE1:
        MOVE.L  (A1)+,D0                        | YES, MAXH:=PT.H
        CMP.L   (A1),D0                         | IS IT SAME AS NEXT ?
        BEQ.B   DELETE                          | YES, DELETE BOTH
        MOVE.L  D0,(A2)+                        | NO, COPY TO DST
CULLPOINTS_WHILE1:
        CMPA.L  A3,A1                           | IS SRCPTR < LASTPTR ?
        BLT.B   CULLPOINTS_MORE1                | YES, GO FOR MORE
        BGT.B   CULLPOINTS_DONE                 | past end, exit loop
        MOVE.L  (A1)+,(A2)+                     | FINISH UP LAST POINT
CULLPOINTS_DONE:
        MOVE.L  A2,D0                           | GET DST PTR
        SUB.L   D5,D0                           | SUBTRACT START PTR
        LSR     #0x2,D0                         | DIV BY 4 FOR PTCOUNT
        MOVE.L  8(A6),A0                        | GET VAR ADDR
        MOVE    D0,(A0)                         | UPDATE PTCOUNT
CULLPOINTS_GOHOME:
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDQ.W  #0x8,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
PackRgn:
        LINK    A6,#-0x8                        | allocate 8-byte BBOX local
        MOVEM.L D0-D7/A1-A4,-(SP)               | SAVE REGS
        MOVE.L  14(A6),A4                       | get pt-buffer ptr
        MOVE.L  8(A6),A3                        | get rgnHandle
        MOVE    12(A6),D6                       | D6 := nPoints
        MOVE.L  (A3),A1                         | dereference rgnHandle
        MOVE    (A1),D5                         | D5 := old rgnSize
        MOVE.L  (A4),A0                         | A0 := scan-line ptr
        MOVE    #0xA,D7                         | rgnSize header = 10
        CLR.L   -8(A6)                          | clear BBOX top/left
        CLR.L   -4(A6)                          | clear BBOX bottom/right
        CMPI    #0x4,D6                         | test nPoints vs 4 (rect)
        BGT.B   PACKRGN_NO                      | more than rect: scan all points
        BLT.W   PACKRGN_DONE                    | fewer than 4: empty region
        MOVE.L  (A0),-8(A6)                     | BBOX TopLeft from scan
        MOVE.L  12(A0),-4(A6)                   | BBOX BotRight from scan
        BRA.W   PACKRGN_DONE                    | rect-only path done
PACKRGN_NO:
        MOVE    (A0),-8(A6)                     | BBOX top := first point V
        MOVE    2(A0),D1                        | D1 := initial MIN H
        MOVE    D1,D2                           | D2 := initial MAX H
        MOVE    D6,D3                           | D3 := loop counter (nPoints)
PACKRGN_LOOP:
        SUBQ.W  #0x1,D3                         | decrement counter
        BLT.B   ENDSCAN                         | done when negative
        MOVE.L  (A0)+,D0                        | get point (V,H)
        CMP     D1,D0                           | V < MIN H so far?
        BGE.B   PACKRGN_NO_2                    | no -> check max
        MOVE    D0,D1                           | yes, MIN := V
        BRA.B   PACKRGN_LOOP                    | next point
PACKRGN_NO_2:                                   | jump via A0
        CMP     D2,D0                           | V > MAX H so far?
        BLE.B   PACKRGN_LOOP                    | no, next point
        MOVE    D0,D2                           | yes, MAX := V
        BRA.B   PACKRGN_LOOP                    | next point
ENDSCAN:
        MOVE    D1,-6(A6)                       | BBOX LEFT:=MINH
        MOVE    D2,-2(A6)                       | BBOX RIGHT:=MAXH
        MOVE    -4(A0),-4(A6)                   | BBOX BOTTOM:=LAST POINT.V
        MOVEQ.L #0x3,D5                         | base size: rgnSize+bbox(8)+terminator
        ADD     D6,D5                           | add nPoints
        LSL     #0x2,D5                         | x4 (each point = 4 bytes)
        MOVE.L  A3,-(SP)                        | push rgnHandle
        MOVE    D5,-(SP)                        | push new size
        JSR     SetHSize(PC)                    | grow region handle to D5 bytes
        MOVE.L  (A4),A0                         | re-derefence point buffer
        MOVE.L  (A3),A1                         | re-dereference rgnHandle
        ADDA.W  #0xA,A1                         | skip past 10-byte header
        SUBQ.W  #0x1,D6                         | DBcc loop count = nPoints-1
        MOVE    (A0)+,D0                        | get first vert
        BRA.B   PACKRGN_START                   | jump to first store
NEXTPT:
        CMP     (A0)+,D0                        | same vertical as previous?
        BEQ.B   VSAME                           | yes, just emit horizontal
        MOVE    #0x7FFF,(A1)+                   | end-of-row terminator
        MOVE    -2(A0),D0                       | reload V into D0
PACKRGN_START:
        MOVE    D0,(A1)+                        | emit vertical coord
VSAME:
        MOVE    (A0)+,(A1)+                     | copy horizontal to packed rgn
        DBRA    D6,NEXTPT                       | loop for each point
        MOVE    #0x7FFF,(A1)+                   | end-of-row terminator
        MOVE    #0x7FFF,(A1)+                   | end-of-region terminator
        MOVE.L  (A3),A0                         | re-dereference rgnHandle
        SUBA.L   A0,A1                          | compute final size
        MOVE.W   A1,D7                          | D7 := actual rgnSize

| --------------------------------------------------------
| INSTALL RGNSIZE AND RGNBBOX.
| Called during boot (7,415 times in 30s trace).
PACKRGN_DONE:
        MOVE.L  (A3),A0                         | NXTVERT: GET VERT AND HORIZ COORDS
        MOVE    D7,(A0)+                        | PUT LEFT POINT TO DST
        MOVE.L  -8(A6),(A0)+                    | GET HORIZ COORD
        MOVE.L  -4(A6),(A0)+                    | PUT RIGHT POINT TO DST
        CMP     D7,D5                           | did size change vs original?
        BEQ.B   PACKRGN_SIZEOK                  | no, skip resize
        MOVE.L  A3,-(SP)                        | push rgnHandle
        MOVE    D7,-(SP)                        | push final size
        JSR     SetHSize(PC)                    | shrink to actual size
PACKRGN_SIZEOK:
        MOVEM.L (SP)+,D0-D7/A1-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0xA,SP                         | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS

| ------------------------------------------------
| A6 OFFSETS OF PARAMETERS AFTER LINK:
| .PROC PUTRGN,4
| .REF SETSIZE
| ----------------------------------------------------------------
| PROCEDURE PutRgn(Rgn: RgnHandle; bufHandle: Handle; VAR index,size: INTEGER);
| Expands a region out to an array of inversion points.
PutRgn:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVEM.L D7/A2-A4,-(SP)                  | SAVE REGS
        MOVE.L  16(A6),A4                       | A4 := bufHandle
        MOVE.L  20(A6),A3                       | A3 := rgnHandle
        MOVE.L  12(A6),A2                       | A2 := VAR index
        MOVE.L  (A3),A0                         | dereference rgnHandle
        MOVE    (A0),D7                         | D7 := rgnSize
        ADD     D7,D7                           | estimate buf bytes (rgnSize x2)
        ADD     (A2),D7                         | add current index
        MOVE.L  8(A6),A1                        | A1 := VAR size
        CMP     (A1),D7                         | does buffer fit?
        BLE.B   NOGROW                          | yes, skip grow
        ADDI    #0x100,D7                       | grow by 256 bytes
        MOVE    D7,(A1)                         | update VAR size
        MOVE.L  A4,-(SP)                        | push bufHandle
        MOVE    D7,-(SP)                        | YES, TRIM BOUNDS.BOTTOM
        JSR     SetHSize(PC)                    | grow point buffer
        MOVE.L  (A3),A0                         | re-deref rgnHandle
        MOVE.L  12(A6),A2                       | reload VAR index
NOGROW:
        MOVE.L  (A4),A1                         | DE-REFERENCE BUFHANDLE
        ADDA.W  (A2),A1                         | A1 += index
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR ?
        BNE.B   PUTRGN_NOTRECT                  | NO, EXPAND IT
        ADDQ.W  #0x2,A0                         | skip rgnSize header
        MOVE.L  (A0)+,(A1)+                     | copy bbox top/left
        MOVE.L  (A0)+,(A1)+                     | copy bbox bottom/right
        BRA.B   PUTRGN_DONE                     | rect path done
PUTRGN_NOTRECT:
        LEA      10(A0),A0                      | skip past 10-byte header
PUTRGN_NXTVERT:
        MOVE.L   (A0)+,D7                       | get vertical coord (long)
NXTHOR:
        MOVE.L  D7,(A1)+                        | emit V to point buffer
        MOVE    (A0)+,D7                        | get next horizontal
        MOVE.L  D7,(A1)+                        | emit H to point buffer
        MOVE    (A0)+,D7                        | get next horizontal
        CMPI    #0x7FFF,D7                      | end-of-row terminator?
        BNE.B   NXTHOR                          | no, more horizontals
        CMPI    #0x7FFF,(A0)                    | end-of-region terminator?
        BNE.B   PUTRGN_NXTVERT                  | no, next scan line
PUTRGN_DONE:
        SUBA.L  (A4),A1                         | compute new index
        MOVE    A1,(A2)                         | update VAR index
        MOVEM.L (SP)+,D7/A2-A4                  | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return PC
        ADDA.W  #0x10,SP                        | strip PARAMSIZE bytes
        JMP     (A0)                            | RTS
