| -----------------------------------------------------------------
|
| --> DRAWLINE.TEXT
|

StdLine:
        LINK    A6,#0x0                         | no locals
        MOVEM.L D5-D7/A3-A4,-(SP)               | save regs
        JSR     CheckPic(PC)                    | set up A4,A3 / check picSave
        BLE.W   STDLINE_NOTPIC                  | no pic open -> just draw
        CLR.B   -(SP)                           | verb byte = 0 (line)
        JSR     PutPicVerb(PC)                  | emit picture verb
        MOVEQ.L #0x20,D7                        | base opcode = $20 (LINE)
        MOVE.L  0x5C(A3),A4                     | A4 = picSave handle
        MOVE.L  (A4),A4                         | A4 = picSave record
        MOVE.L  0x30(A3),D0                     | D0 = pen.loc
        CMP.L   0x2A(A4),D0                     | same as picStart?
        BNE.B   STDLINE_NO                      | no -> emit absolute startPt
        ADDQ.W   #0x1,D7                        | set bit 0 -> short form
STDLINE_NO:
        MOVE    10(A6),D6                       | D6 = newPt.h
        SUB     D0,D6                           | dh = newPt.h - pen.h
        MOVE    D6,D0                           | test dh range
        EXT.W    D0                             | sign-extend low byte
        CMP     D6,D0                           | dh fits in byte?
        BNE.B   PUTOP                           | no -> use long form
        MOVE    8(A6),D5                        | D5 = newPt.v
        SUB     0x30(A3),D5                     | dv = newPt.v - pen.v
        MOVE    D5,D0                           | test dv range
        EXT.W    D0                             | jump via A0
        CMP     D5,D0                           | dv fits in byte?
        BNE.B   PUTOP                           | no -> use long form
        ADDQ.W  #0x2,D7                         | set bit 1 -> short form
PUTOP:
        MOVE.B  D7,-(SP)                        | push opcode
        JSR     PutPicByte(PC)                  | emit opcode
        BTST    #0x0,D7                         | short startPt?
        BNE.B   STDLINE_STARTOK                 | yes -> skip startPt emit
        MOVE.L  0x30(A3),-(SP)                  | push pen.loc as startPt
        JSR     PutPicLong(PC)                  | emit startPt long
STDLINE_STARTOK:
        BTST    #0x1,D7                         | short newPt?
        BNE.B   DHDV                            | yes -> emit dh/dv bytes
        MOVE.L  8(A6),-(SP)                     | push newPt long
        JSR     PutPicLong(PC)                  | emit newPt long
        BRA.B   STDLINE_UPDATE                  | skip dh/dv path
DHDV:
        MOVE.B  D6,-(SP)                        | push dh
        JSR     PutPicByte(PC)                  | emit dh byte
        MOVE.B  D5,-(SP)                        | push dv
        JSR     PutPicByte(PC)                  | emit dv byte
STDLINE_UPDATE:
        MOVE.L  0x5C(A3),A4                     | re-fetch picSave handle
        MOVE.L  (A4),A4                         | dereference picSave
        MOVE.L  8(A6),0x2A(A4)                  | picStart := newPt
STDLINE_NOTPIC:
        MOVE.L  8(A6),-(SP)                     | push newPt
        JSR     DoLine(PC)                      | draw the line
        MOVEM.L (SP)+,D5-D7/A3-A4               | restore regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return
LineTo:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  0x68(A0),D0                     | D0 = grafProcs ptr
        LEA     StdLine(PC),A0                  | default = StdLine
        BEQ.B   LINETO_USESTD                   | no grafProcs -> use std
        MOVE.L  D0,A0                           | A0 = grafProcs
        MOVE.L  4(A0),A0                        | A0 = lineProc
LINETO_USESTD:
        JMP     (A0)                            | RTS
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE    0x32(A0),D0                     | D0 = pen.h
        ADD     D0,6(SP)                        | 6(SP) += D0
        MOVE    0x30(A0),D0                     | D0 = pen.v
        ADD     D0,4(SP)                        | 4(SP) += D0
        JMP     LineTo(PC)                      | fall through to LineTo
MoveTo:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVE.L  (A5),A1                         | NOTRGN: PUSH OLDPT
        MOVE.L  (A1),A1                         | PUSH NEWPT
        MOVE.L  (SP)+,0x30(A1)                  | thePort.pn := newPt
        JMP     (A0)                            | RTS
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVE    (SP)+,D0                        | STRIP PARAM
        MOVE    (SP)+,D1                        | D1 = dh
        MOVE.L  (A5),A1                         | A1 = QD globals
        MOVE.L  (A1),A1                         | A1 = thePort
        ADD     D0,0x30(A1)                     | 0x30(A1) += D0
        ADD     D1,0x32(A1)                     | 0x32(A1) += D1
        JMP     (A0)                            | RTS

| .PROC DoLine,1
| .REF DrawLine,PutLine,SetSize
| ----------------------------------------------------------
| PROCEDURE DoLine(newPt: Point);
| { called by StdLine and StdPoly frame }
| Called during boot.
DoLine:
        MOVEM.L D6-D7/A3-A4,-(SP)               | save regs
        MOVE.L  (A5),A4                         | A4 = QD globals
        MOVE.L  (A4),A3                         | A3 = thePort
        MOVE.L  20(SP),D7                       | D7 = newPt
        MOVE.L  0x30(A3),D6                     | D6 = oldPt = pen.loc
        TST.L   0x64(A3)                        | polySave nil?
        BEQ.B   NOTPOLY                         | no poly -> NOTPOLY
        MOVE.L  -0xA2(A4),A1                    | A1 = thePoly handle
        MOVE.L  (A1),A0                         | A0 = poly record
        MOVE    (A0),D0                         | D0 = polySize index
        CMPI    #0xA,D0                         | first point of poly?
        BNE.B   DOLINE_CONT                     | no -> just append newPt
        MOVE.L  D6,0(A0,D0.W)                   | install oldPt (start)
        ADDQ.W  #0x4,D0                         | advance index
DOLINE_CONT:
        MOVE.L  D7,0(A0,D0.W)                   | INSTALL NEWPT AT END
        ADDQ.W  #0x4,D0                         | BUMP INDEX
        MOVE    D0,(A0)                         | UPDATE INDEX
        CMP     -0xA4(A4),D0                    | TIME TO MAKE BIGGER ?
        BLT.B   SIZEOK                          | NO, CONTINUE
        ADDI    #0x100,-0xA4(A4)                | YES, GROW IN CHUNKS
        MOVE.L  A1,-(SP)                        | PUSH POLYHANDLE
        MOVE    -0xA4(A4),-(SP)                 | PUSH NEW SIZE
        JSR     SetHSize(PC)                    | MAKE THEPOLY BIGGER
SIZEOK:
        BRA.B   DOLINE_NOTRGN                   | skip rgn save (poly mode)
NOTPOLY:
        TST.L   0x60(A3)                        | ARE WE SAVING FOR A REGION ?
        BEQ.B   DOLINE_NOTRGN                   | NO, SKIP REGION SAVE
        MOVE.L  D6,-(SP)                        | PUSH OLDPT
        MOVE.L  D7,-(SP)                        | PUSH NEWPT
        MOVE.L  -0x94(A4),-(SP)                 | PUSH RGNBUF
        PEA.L     -0x96(A4)                     | PUSH VAR RGNINDEX
        PEA.L     -0x98(A4)                     | PUSH VAR RGNMAX
        JSR     PutLine(PC)                     | record line for region build
DOLINE_NOTRGN:
        MOVE.L  D6,-(SP)                        | PUSH OLDPT (P1)
        MOVE.L  D7,-(SP)                        | PUSH NEWPT (P2)
        JSR     DrawLine(PC)                    | DrawLine(P1, P2)
        MOVE.L  D7,0x30(A3)                     | COPY PNSIZE FROM THEPORT
        MOVEM.L (SP)+,D6-D7/A3-A4               | restore regs
        MOVE.L  (SP)+,(SP)                      | COPY PNPAT FROM THEPORT
        RTS                                     | return
HidePen:
        MOVE.L  (A5),A0                         | STRIP 4 BYTES
        MOVE.L  (A0),A0                         | A0 = thePort
        SUBQ.W  #0x1,0x42(A0)                   | pnVis-- (hide if <0)
        RTS                                     | return
ShowPen:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        ADDQ.W  #0x1,0x42(A0)                   | 0x42(A0) += 0x1
        RTS                                     | return

| -------------------------------------------------------------
| PROCEDURE GetPenState(VAR pnState: PenState);
| PROCEDURE SetPenState(pnState: PenState);
| Shared body in next file as SETPENSTATE_CONT; D0 selects copy direction.
GetPenState:
        MOVEQ.L #0x1,D0                         | flag = 1: copy theport^.pn -> pnState
        BRA.B   SETPENSTATE_CONT                | share body
SetPenState:
        CLR     D0                              | flag = 0: copy pnState -> theport^.pn

| .PROC DrawLine
| .REF RgnBlt,RSect,ShieldCursor,ShowCursor,TrimRect
| .REF InitRgn,SeekRgn,PatExpand,ColorMap
| .REF XorSlab,DrawSlab,SlabMode,FastSlabMode,MaskTab
| ----------------------------------------------------------------
|
| PROCEDURE DRAWLINE(P1,P2: POINT);
|
| DRAWS A LINE CLIPPED TO CURRENT PORT'S CLIPRGN AND VISRGN
| P1 AND P2 ARE GIVEN IN LOCAL COORDINATES OF THEPORT.
| ------------------------------------------------
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| Note: classic's DrawLine.s starts with tail-end fragments of line
| drawing code. Called during boot.

SETPENSTATE_CONT:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        LEA.L     0x30(A0),A0                   | A0 = thePort.pn fields
        MOVE.L  4(SP),A1                        | A1 = pnState VAR addr
        TST     D0                              | direction flag (1=Get, 0=Set)
        BNE.B   NOTSET                          | get -> A0=src, A1=dst
        EXG     A0,A1                           | set -> A0=pnState src, A1=port dst
NOTSET:
        MOVE.L  (A0)+,(A1)+                     | copy pnLoc
        MOVE.L  (A0)+,(A1)+                     | copy pnSize
        MOVE    (A0)+,(A1)+                     | copy pnMode
        MOVE.L  (A0)+,(A1)+                     | copy pnPat first long
        MOVE.L  (A0)+,(A1)+                     | copy pnPat second long
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return
| -------------------------------------------------------------
| PROCEDURE GetPen(VAR pt: Point); { inquire current pen location }
GetPen:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  4(SP),A1                        | POINT TO VAR PT
        MOVE.L  0x30(A0),(A1)                   | GET PNLOC FROM THEPORT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | return
| -------------------------------------------------------------
| PROCEDURE PenSize(width,height: INTEGER);
PenSize:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  4(SP),0x34(A0)                  | SET PEN WIDTH AND HEIGHT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | return
| -------------------------------------------------------------
| PROCEDURE PenMode(mode: INTEGER);
PenMode:
        MOVEQ.L #0x38,D0                        | PUT PORT OFFSET IN D0
        JMP     L_mPortWord(PC)                 | INSTALL PARAM INTO THEPORT
| -------------------------------------------------------------
| PROCEDURE PenPat(pat: Pattern);
PenPat:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x3A(A0),A0                   | POINT TO PNPAT
        MOVE.L  4(SP),A1                        | POINT TO INPUT PATTERN
        MOVE.L  (A1)+,(A0)+                     | COPY PATTERN INTO THEPORT
        MOVE.L  (A1)+,(A0)+                     | ALL 8 BYTES
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | return
| -------------------------------------------------------------
| PROCEDURE PenNormal; { restore line drawing parameters to normal }
PenNormal:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  #0x00010001,0x34(A0)            | GrafPort.pnSize = (1,1)
        MOVE    #0x8,0x38(A0)                   | GrafPort.pnMode = 8 (patCopy)
        MOVEQ.L #-0x1,D0                        | PNPAT := black
        MOVE.L  D0,0x3A(A0)                     | first long
        MOVE.L  D0,0x3E(A0)                     | second long
        RTS                                     | return

| -----------------------------------------------------------
| --> DRAWLINE.TEXT (continued)
| DrawLine -- main line-drawing routine.
| ------------------------------------------------------
| .PROC DrawLine
| .REF RgnBlt,RSect,ShieldCursor,ShowCursor,TrimRect
| .REF InitRgn,SeekRgn,PatExpand,ColorMap
| .REF XorSlab,DrawSlab,SlabMode,FastSlabMode,MaskTab
| ----------------------------------------------------------------
| PROCEDURE DrawLine(p1, p2: Point);
|
| Draws a line clipped to current port's clipRgn and visRgn.
| P1 and P2 are given in local coordinates of thePort.
| Called during boot.
DrawLine:
        LINK    A6,#-0xC0                       | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS
        MOVE.L  SP,-0x74(A6)                    | saveStk
        MOVE.L  A5,-0xB6(A6)                    | save QD globals ptr
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A3                         | A3 = thePort
        TST     0x42(A3)                        | test pnVis
        BLT.W   DRAWLINE_GOHOME                 | YES, QUIT
        MOVE.L  A3,-0xBA(A6)                    | save grafPtr
        MOVEQ.L #-0x8,D0                        | mask = ~7
        AND     0x38(A3),D0                     | isolate pnMode high bits
        CMPI    #0x8,D0                         | in mode group 8..15?
        BNE.W   DRAWLINE_GOHOME                 | NO, QUIT
        MOVE    0x38(A3),-(SP)                  | push pnMode
        PEA.L     0x3A(A3)                      | push @pnPat
        JSR     ColorMap(PC)                    | CHECK AGAINST THECOLOR, THEFILTER
        MOVE.L  (SP)+,-0xC0(A6)                 | save filtered pat ptr
        MOVE    (SP)+,-0xBC(A6)                 | save filtered mode
        MOVE.L  A3,A5                           | PUT GRAFPTR IN A5
        MOVE.L  28(A5),A2                       | GET CLIPRGN HANDLE
        MOVE.L  (A2),A2                         | GET CLIPRGN POINTER
        MOVE.L  24(A5),A3                       | GET VISRGN HANDLE
        MOVE.L  (A3),A3                         | GET VISRGN POINTER
        MOVE    12(A6),D1                       | D1 = p1.v
        MOVE    14(A6),D2                       | D2 = p1.h
        MOVE    8(A6),D3                        | D3 = p2.v
        MOVE    10(A6),D4                       | D4 = p2.h
        CMP     D3,D1                           | IS V1 > V2 ?
        BLE.B   DRAWLINE_NOPEN                  | NO, CONTINUE
        EXG     D1,D3                           | YES, SWAP VERT
DRAWLINE_NOPEN:
        CMP     D4,D2                           | IS H1 > H2 ?
        BLE.B   VOK2_NO                         | NO, CONTINUE
        EXG     D2,D4                           | NO SWAP HORIZ
VOK2_NO:
        ADD     0x36(A5),D4                     | + pnSize.h (right edge)
        ADD     0x34(A5),D3                     | + pnSize.v (bottom edge)
        MOVE    D1,-0x7C(A6)                    | lineRect.top
        MOVE    D2,-0x7A(A6)                    | lineRect.left
        MOVE    D3,-0x78(A6)                    | lineRect.bottom
        MOVE    D4,-0x76(A6)                    | lineRect.right
        PEA.L     -0x7C(A6)                     | push @lineRect
        PEA.L     8(A5)                         | push @portBits.bounds
        PEA.L     2(A2)                         | PUSH CLIPRGN BBOX
        PEA.L     2(A3)                         | PUSH VISRGN BBOX
        MOVE    #0x4,-(SP)                      | push nRects = 4
        PEA.L     -0x84(A6)                     | push @minRect
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ.W   DRAWLINE_GOHOME                 | QUIT IF NO INTERSECT
        PEA.L     -0x84(A6)                     | push @minRect
        MOVE.L  8(A5),-(SP)                     | push rgnHandle
        MOVE.L  -0xB6(A6),A5                    | restore A5 = QD globals
        JSR     DrawControls(PC)                | call trimRect
        MOVE.L  -0xBA(A6),A5                    | restore A5 = grafPtr
        MOVE    12(A6),D1                       | D1 = p1.v
        MOVE    14(A6),D2                       | D2 = p1.h
        MOVE    8(A6),D3                        | D3 = p2.v
        MOVE    10(A6),D4                       | D4 = p2.h
        CMP     D2,D4                           | H1=H2 ?
        BEQ.B   DRAWLINE_HVCHECK                | YES, DO VERTICAL LINE
        CMP     D1,D3                           | NO, IS V2 > V1 ?
        BGT.B   SLANTED                         | YES, DRAW SLANTED LINE
        BLT.B   VSWAP                           | SWAP POINTS AND DRAW SLANTED
DRAWLINE_HVCHECK:
        CMPI.L  #0x00010001,0x34(A5)            | GrafPort.pnSize == (1,1)?
        BNE.B   DRAWLINE_USERGN                 | thick pen -> use rgnBlt
        MOVE.L  -0xC0(A6),A0                    | A0 = filtered pat
        MOVE.L  (A0)+,D0                        | D0 = pat first long
        BEQ.B   DRAWLINE_PATOK                  | NO, CONTINUE
        CMPI.L  #-0x1,D0                        | all-ones?
        BNE.B   DRAWLINE_USERGN                 | neither white/black -> rgnBlt
DRAWLINE_PATOK:
        CMP.L   (A0)+,D0                        | both halves equal?
        BNE.B   DRAWLINE_USERGN                 | no -> rgnBlt
        CMPI    #0xA,(A2)                       | clipRgn rectangular?
        BNE.B   DRAWLINE_USERGN                 | no -> rgnBlt
        CMPI    #0xA,(A3)                       | visRgn rectangular?
        BEQ.W   DRAWLINE_ABLOOP_CONT            | YES, DO IT FAST !
DRAWLINE_USERGN:
        PEA.L     2(A5)                         | PUSH SRCBITS = DSTBITS
        PEA.L     2(A5)                         | PUSH PATTERN
        PEA.L     -0x84(A6)                     | push srcRect = minRect
        PEA.L     -0x84(A6)                     | push dstRect = minRect
        MOVE    0x38(A5),-(SP)                  | push pnMode
        PEA.L     0x3A(A5)                      | push @pnPat
        MOVE.L  28(A5),-(SP)                    | PUSH CLIPRGN HANDLE
        MOVE.L  24(A5),-(SP)                    | PUSH VISRGN HANDLE
        MOVE    #0xA,-0x86(A6)                  | fakeRgn.size = 10 (rect)
        LEA.L     -0x86(A6),A0                  | A0 = fakeRgn ptr
        MOVE.L  A0,-0x8A(A6)                    | fakeMaster -> fakeRgn
        PEA.L     -0x8A(A6)                     | push @fakeMaster (handle)
        MOVE.L  -0xB6(A6),A5                    | restore A5 = QD globals
        JSR     RgnBlt(PC)                      | DRAW THE HORIZ OR VERT LINE
        BRA.W   DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT
VSWAP:
        EXG     D1,D3                           | SORT POINTS BY VERTICAL
        EXG     D2,D4                           | SWAP HORIZ TO MATCH
SLANTED:
        MOVE    D3,D0                           | COPY LINE BOTTOM
        ADD     0x34(A5),D0                     | ADD PEN HEIGHT
        CMP     2(A2),D0                        | IS BOTTOM < CLIPRGN TOP?
        BLE.W   DRAWLINE_DONE                   | YES, RESTORE CURSOR AND QUIT
        CMP     6(A2),D1                        | IS TOP >= CLIPRGN BOTTOM?
        BGE.W   DRAWLINE_DONE                   | YES, RESTORE CURSOR AND QUIT
        MOVE    D2,-0x90(A6)                    | INIT LEFT EDGE INTEGER
        MOVE    #-0x8000,-0x8E(A6)              | INIT LEFT EDGE FRACTION
        MOVE.L  -0x90(A6),-0x94(A6)             | RIGHTEDGE:=LEFTEDGE
        MOVE    0x36(A5),D0                     | GET PEN WIDTH
        BLE.W   DRAWLINE_DONE                   | QUIT IF PENWIDTH <= 0
        ADD     D0,-0x94(A6)                    | ADD PEN WIDTH TO RIGHT EDGE
        MOVE    0x34(A5),D6                     | GET PEN HEIGHT
        BLE.W   DRAWLINE_DONE                   | QUIT IF PEN HEIGHT <= 0
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    D4,-(SP)                        | PUSH BOTTOM HORIZ
        SUB     D2,(SP)                         | CALC DH
        MOVE    D3,-(SP)                        | PUSH BOTTOM VERT
        SUB     D1,(SP)                         | CALC DV
        JSR     FixRatio(PC)                    | compute slope = dh/dv
        MOVE.L  (SP)+,D7                        | POP RESULT
        MOVE.L  D7,-0x98(A6)                    | save slope
        CLR.L   -(SP)                           | PUSH ROOM FOR FCN RESULT
        CLR     -(SP)                           | push 0 (numer hi)
        MOVE    D6,-(SP)                        | push pen height
        MOVE.L  D7,-(SP)                        | PUSH SLOPE
        JSR     FixMul(PC)                      | adjust = penHeight * slope
        MOVE.L  (SP)+,D6                        | POP ANSWER INTO D6
        MOVE.L  D7,D0                           | COPY SLOPE
        ASR.L   #0x1,D0                         | slope/2 (centering bias)
        ADD.L   D0,-0x90(A6)                    | -0x90(A6) += D0
        ADD.L   D0,-0x94(A6)                    | -0x94(A6) += D0
        TST.L   D7                              | IS SLOPE NEGATIVE ?
        BMI.B   NEGSLOPE                        | YES, CONTINUE
        SUB.L   D6,-0x90(A6)                    | -0x90(A6) -= D6
        CMPI.L  #0x00010000,D7                  | slope >= 1.0?
        BGE.B   DRAWLINE_PSLOPE_HI              | yes -> skip fractional add
        ADD.L    D7,-144(FP)                    | shallow slope: bump leftEdge
        BRA.B   NEGSLOPE_LOOP                   | CONTINUE
DRAWLINE_PSLOPE_HI:
        SUBQ.W  #0x1,-0x94(A6)                  | steep slope: shrink rightEdge
        BRA.B   NEGSLOPE_LOOP                   | CONTINUE

| ----------------------------------------------------
| SLOPE IS NEGATIVE
NEGSLOPE:
        SUB.L   D6,-0x94(A6)                    | SUBTRACT ADJUST FROM RIGHTEDGE
        CMPI.L  #0xFFFF0000,D7                  | IS SLOPE <= -1.0?
        BLT.B   NEGSLOPE_FLIP                   | NO, CONTINUE
        ADD.L   D7,-0x94(A6)                    | ADD SLOPE TO RIGHTEDGE
        BRA.B   NEGSLOPE_LOOP                   | CONTINUE
NEGSLOPE_FLIP:
        ADDQ.W  #0x1,-0x90(A6)                  | -0x90(A6) += 0x1
NEGSLOPE_LOOP:
        MOVE    -0x84(A6),D1                    | D1 = minRect.top
        MOVE    -0x82(A6),D2                    | D2 = minRect.left
        MOVE    -0x80(A6),D3                    | D3 = minRect.bottom
        MOVE    -0x7E(A6),D4                    | D4 = minRect.right
        CMP     -0x7C(A6),D1                    | line clipped at top?
        BEQ.B   NEGSLOPE_OK                     | NO, CONTINUE
        MOVE    D1,D0                           | D0 = minRect.top
        SUB     -0x7C(A6),D0                    | discard rows = top - lineRect.top
        MOVE.L  D7,D5                           | GET 32 BIT SLOPE
        SWAP    D5                              | GET HI WORD OF SLOPE
        MULS    D0,D5                           | MULT TIMES DISCARD
        SWAP    D5                              | PUT RESULT IN HI WORD
        CLR     D5                              | zero low word
        MOVE.L  D7,D6                           | GET NEW COPY OF SLOPE
        MULU    D0,D6                           | MULT LO WORD TIMES DISCARD
        ADD.L   D6,D5                           | CALC 32BIT SLOPE*DISCARD
        ADD.L   D5,-0x90(A6)                    | -0x90(A6) += D5
        ADD.L   D5,-0x94(A6)                    | -0x94(A6) += D5
NEGSLOPE_OK:
        MOVE    #-0x7FFF,-10(A6)                | maskRect.top = -32767
        MOVE    #-0x7FFF,-0x22(A6)              | maskRect.left = -32767
        MOVE    #0x7FFF,-8(A6)                  | maskRect.bottom = +32767
        MOVE    #0x7FFF,-0x20(A6)               | maskRect.right = +32767
        MOVE    -0x82(A6),D2                    | D2 = minRect.left
        SUB     10(A5),D2                       | - portBits.left
        ANDI    #-0x10,D2                       | word-align (clear 4 LSBs)
        ADD     10(A5),D2                       | restore portBits.left bias
        MOVE    D2,-0xA6(A6)                    | bufLeft (word-aligned)
        MOVE    -0x7E(A6),D0                    | D0 = minRect.right
        SUB     D2,D0                           | CALC MAXH-BUFLEFT
        LSR     #0x5,D0                         | /32 -> long count
        MOVE    D0,-0xA8(A6)                    | maskLongs
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK
DRAWLINE_CLRMASK:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR ONE LONG
        DBRA    D0,DRAWLINE_CLRMASK             | LOOP TILL DONE
        MOVE.L  SP,-0xA4(A6)                    | maskBase = SP
        CLR     -0x8C(A6)                       | rgnFlags = 0
        CMPI    #0xA,(A2)                       | clipRgn rectangular?
        BEQ.B   DRAWLINE_INITRGN1               | YES, CONTINUE
        ADDQ.W  #0x2,-0x8C(A6)                  | -0x8C(A6) += 0x2
        MOVE.L  A2,A0                           | POINT TO CLIPRGN
        LEA.L     -24(A6),A1                    | A1 = maskRect ptr
        MOVE    -0x82(A6),D0                    | D0 = minRect.left
        MOVE    -0x7E(A6),D1                    | D1 = minRect.right
        MOVE    -0xA6(A6),D2                    | D2 = bufLeft
        JSR     InitRgn(PC)                     | build clipRgn scan tables
DRAWLINE_INITRGN1:
        CMPI    #0xA,(A3)                       | visRgn rectangular?
        BEQ.B   DRAWLINE_INITRGN2               | YES, CONTINUE
        ADDQ.W  #0x4,-0x8C(A6)                  | -0x8C(A6) += 0x4
        MOVE.L  A3,A0                           | POINT TO VISRGN
        LEA.L     -0x30(A6),A1                  | A1 = scanRecB ptr
        MOVE    -0x82(A6),D0                    | D0 = minRect.left
        MOVE    -0x7E(A6),D1                    | D1 = minRect.right
        MOVE    -0xA6(A6),D2                    | D2 = bufLeft
        JSR     InitRgn(PC)                     | build visRgn scan tables
DRAWLINE_INITRGN2:
        TST     -0x8C(A6)                       | rgnFlags == 0 (both rect)?
        BNE.B   DRAWLINE_PIXADDR                | NO, CONTNUE
        MOVE.L  -0xA4(A6),A0                    | A0 = mask buffer
        MOVE    -0x82(A6),D3                    | D3 = minRect.left
        SUB     -0xA6(A6),D3                    | left offset within buf
        MOVE    -0x7E(A6),D4                    | D4 = minRect.right
        SUB     -0xA6(A6),D4                    | right offset within buf
        JSR     XorSlab(PC)                     | AND XOR BETWEEN THEM
DRAWLINE_PIXADDR:
        MOVE    -0x84(A6),D1                    | GET GLOBAL PTR
        SUB     8(A5),D1                        | - portBits.top
        MULU    6(A5),D1                        | D1 = D1 *u 6(A5)
        ADD.L   2(A5),D1                        | + portBits.baseAddr
        SUB     10(A5),D2                       | - portBits.left
        LSR     #0x3,D2                         | /8 -> byte offset
        EXT.L    D2                             | CLR HI WORD
        ADD.L   D2,D1                           | ADD HORIZ BYTE OFFSET
        MOVE.L  D1,-0xAC(A6)                    | dstPtr (pixel base)
        CLR.L   D7                              | jump via A0
        MOVE    -0xBC(A6),D2                    | D2 = filtered pnMode
        BCLR    #0x2,D2                         | test/clear bit 2 (xor flag)
        BEQ.B   DRAWLINE_SLAB_MODE              | NO, CONTINUE
        NOT.L   D7                              | invert pat for xor
DRAWLINE_SLAB_MODE:
        JSR     SlabMode(PC)                    | Get fast case jump in A4
        MOVE.L  A0,-0xB2(A6)                    | save slab handler ptr
        MOVE    10(A5),D2                       | D2 = portBits.left
        MOVE.L  -0xC0(A6),A0                    | A0 = filtered pat
        LEA.L     -0x70(A6),A1                  | A1 = expanded pat buffer
        MOVE.L  -0xB6(A6),A5                    | A5 = QD globals (PatExpand)
        JSR     PatExpand(PC)                   | DRAW ONE SLAB IN PENMODE
        MOVE.L  -0xBA(A6),A5                    | restore A5 = grafPtr
        MOVEQ.L #0xF,D7                         | mask = 15 (16-row pat)
        AND     -0x84(A6),D7                    | topRow mod 16
        LSL     #0x2,D7                         | *4 -> long offset
        MOVE.L  -0x70(A6,D7.W),D6               | D6 = pattern word from expanded table
        MOVE    -0xA6(A6),D1                    | D1 = bufLeft
        SUB     D1,-0x90(A6)                    | -0x90(A6) -= D1
        SUB     D1,-0x94(A6)                    | -0x94(A6) -= D1
        SUB     D1,-0x82(A6)                    | -0x82(A6) -= D1
        SUB     D1,-0x7E(A6)                    | -0x7E(A6) -= D1
        MOVE    -0x84(A6),-0xAE(A6)             | rowIndex = top
DRAWLINE_ROW_LOOP:
        JSR     DRAWLINE_ROWLOOP(PC)            | GET DrawSlab CASE JUMP IN A4
        MOVE    -0x90(A6),D1                    | D1 = leftEdge
        MOVE    -0x94(A6),D2                    | D2 = rightEdge
        MOVE.L  -0xB2(A6),A0                    | A0 = slab handler
        MOVE.L  -0xAC(A6),A1                    | A1 = dstPtr
        MOVE.L  -0xA4(A6),A2                    | A2 = maskBuf
        LEA.L     -0x84(A6),A3                  | A3 = minRect ptr
        JSR     DrawSlab(PC)                    | EXPAND 8 BYTES TO 16 LONGS
        ADDQ.W  #0x4,D7                         | advance pat row offset
        ANDI    #0x3F,D7                        | wrap mod 64 (16 rows * 4)
        MOVE.L  -0x70(A6,D7.W),D6               | D6 = pattern word from expanded table
        MOVE    6(A5),D0                        | ABLOOP
        EXT.L    D0                             | sign-extend rowBytes to long
        ADD.L   D0,-0xAC(A6)                    | -0xAC(A6) += D0
        MOVE.L  -0x98(A6),D0                    | D0 = slope
        ADD.L   D0,-0x90(A6)                    | -0x90(A6) += D0
        ADD.L   D0,-0x94(A6)                    | -0x94(A6) += D0
        ADDQ.W  #0x1,-0xAE(A6)                  | -0xAE(A6) += 0x1
        MOVE    -0xAE(A6),D0                    | D0 = current row
        CMP     -0x80(A6),D0                    | reached minRect.bottom?
        BLT.B   DRAWLINE_ROW_LOOP               | NO, LOOP ALL SCAN LINES
| Called by: DRAWLINE_USERGN, DRAWLINE_ABLOOP_CONT_5, HTOGL_END, HSET_END, VCLR (and 2 more)
DRAWLINE_DONE:
        MOVE.L  -0xB6(A6),A5                    | restore A5 = QD globals
        JSR     FMQD_ShowCursor(PC)             | RESTORE CURSOR
DRAWLINE_GOHOME:
        MOVE.L  -0x74(A6),SP                    | STRIP BUFFER
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | RELEASE LOCAL VARIABLES
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR INTO A0
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | JUMP THRU A0 TO RETURN

| ---------------------------------------------------------
| OUTER LOOP: DO EACH SCAN LINE AND COME BACK TO NXTSRC OR NXTPAT.
| SOME MODES OPTIMIZE AND DO WHOLE OUTER LOOP AND COME BACK TO GOHOME.
| Called during boot (8,945 times in 30s trace).
DRAWLINE_ROWLOOP:
        MOVE    -0x8C(A6),D0                    | D0 = transfer-mode index
| Raw bytes: MOVE.W PC@(6,D0.W),D0 + JMP PC@(2,D0.W); dispatches to
| one of the mode-specific row handlers via a 2-byte offset table.
        .short  0x303B, 0x0006                  | MOVE.W DRAWLINE_ROWLOOP_CONT(PC,D0.W),D0
        .short  0x4EFB, 0x0002                  | JMP DRAWLINE_ROWLOOP_CONT(PC,D0.W)
DRAWLINE_ROWLOOP_CONT:                          | jump-offset table (4 entries)
        .short  0x0008                          | mode 0: handler at PC+8
        .short  0x000A                          | mode 2: handler at PC+10
        ORI.B   #0x32,(A6)+                     | (A6)+ |= 0x32
        RTS                                     | mode 0: no rgn -> done
        MOVE    -0xAE(A6),D0                    | mode 1: clip-only seek
        LEA.L     -24(A6),A1                    | A1 = clipRgn scanRec
        JSR     SeekRgn(PC)                     | advance rgn to current row
        MOVE.L  8(A1),-0xA4(A6)                 | maskBuf = scanRec mask
        RTS                                     | done
        MOVE    -0xAE(A6),D0                    | mode 2: vis-only seek
        LEA.L     -0x30(A6),A1                  | A1 = visRgn scanRec
        JSR     SeekRgn(PC)                     | advance rgn to current row
        MOVE.L  8(A1),-0xA4(A6)                 | maskBuf = scanRec mask
        RTS                                     | done
        MOVE    -0xAE(A6),D0                    | mode 3: clip + vis seek
        LEA.L     -24(A6),A1                    | POINT TO STATE RECORD A
        JSR     SeekRgn(PC)                     | SEEK REGION TO CURRENT VERT
        LEA.L     -0x30(A6),A1                  | POINT TO STATE RECORD B
        JSR     SeekRgn(PC)                     | SEEK REGION TO CURRENT VERT
        MOVE.L  -16(A6),A0                      | GET REGION A SCAN BUFFER
        MOVE.L  -0x28(A6),A1                    | GET REGION B SCAN BUFFER
        MOVE.L  -0xA4(A6),A2                    | GET COMPOSITE MASK BUFFER
        MOVE    -0xA8(A6),D1                    | GET MASK BUFFER SIZE IN LONGS
DRAWLINE_ABLOOP:
        MOVE.L  (A0)+,D0                        | ABLOOP
        AND.L   (A1)+,D0                        | INTERSECT A AND B
        MOVE.L  D0,(A2)+                        | STORE IN COMPOSITE MASK
        DBF     D1,DRAWLINE_ABLOOP              | LOOP FOR ALL LONGS IN SCANLINE
        RTS                                     | RETURN
DRAWLINE_ABLOOP_CONT:
        MOVE    -0xBC(A6),D5                    | D5 = filtered pnMode
        TST     D0                              | test pat-fill flag
        BNE.B   DRAWLINE_ABLOOP_NO              | set -> use mode as-is
        EORI    #0x4,D5                         | XOR immediate: #0x4,D5
DRAWLINE_ABLOOP_NO:
        CMPI    #0xC,D5                         | mode > 11 (notErase)?
        BGT.W   DRAWLINE_DONE                   | invalid -> skip
        CMP     D1,D3                           | IS LINE HORIZONTAL ?
        BNE.W   HSET_LOOP_END_2                 | NO, MUST BE VERTICAL
        BSR.W   VSET_NEXT                       | GET DSTPTR,ROWBYTES,HGLOBAL
        JSR     BitMask(PC)                     | leftMask for line start
        MOVE    D0,D6                           | D6 = leftMask
        MOVE    -0x7E(A6),D2                    | D2 = minRect.right
        SUB     10(A5),D2                       | - portBits.left
        MOVE    D2,D0                           | MAKE A COPY OF RIGHT
        JSR     LeftMask(PC)                    | rightMask for line end
        MOVE    D0,D3                           | D3 = rightMask
        LSR     #0x4,D2                         | /16 -> word offset
        CMPI    #0xA,D5                         | mode < 10 (black)?
        BLT.B   HSET                            | BR IF BLACK
        BEQ.B   HTOGL                           | BR IF XOR
        NOT     D6                              | MAKE NOT LEFTMASK
        NOT     D3                              | MAKE NOT RIGHTMASK
        SUB     D1,D2                           | CALC WORDCOUNT
        BEQ.B   DRAWLINE_ABLOOP_CONT_5          | BR IF ALL IN ONE WORD
        AND     D6,(A4)+                        | DO LEFT WORD WITH MASK
        CLR.L   D6                              | FLUSH LEFTMASK FOR END
        SUBQ.W  #0x1,D2                         | --wordCnt
        BEQ.B   DRAWLINE_ABLOOP_CONT_5          | BR IF NO UNMASKED WORDS
        LSR     #0x1,D2                         | /2 -> longCnt
        BCC.B   DRAWLINE_ABLOOP_CONT_3          | BR IF EVEN # WORDS LEFT
        MOVE    D6,(A4)+                        | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | count one fewer
        BRA.B   DRAWLINE_ABLOOP_CONT_4          | SEE IF ANY LONGS LEFT TO DO
DRAWLINE_ABLOOP_CONT_2:
        MOVE.L  D6,(A4)+                        | FILL A LONG WITH BLACK
DRAWLINE_ABLOOP_CONT_3:
        MOVE.L  D6,(A4)+                        | FILL ANOTHER LONG
        SUBQ.W  #0x2,D2                         | DECREMENT LONGCOUNT
DRAWLINE_ABLOOP_CONT_4:
        BGT.B   DRAWLINE_ABLOOP_CONT_2          | YES, AT LEAST TWO LONGS
        BEQ.B   DRAWLINE_ABLOOP_CONT_3          | YES, FINISH UP LAST LONG
DRAWLINE_ABLOOP_CONT_5:
        OR      D3,D6                           | COMBINE LEFT AND RIGHT MASK
        AND     D6,(A4)                         | DRAW LINE
        BRA.W   DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| --------------------------------------------------
| DRAW AN XOR HORIZONTAL LINE
HTOGL:
        SUB     D1,D2                           | CALC WORDCOUNT
        BEQ.B   HTOGL_END                       | BR IF ALL IN ONE WORD
        EOR     D6,(A4)+                        | DO LEFT WORD WITH MASK
        MOVEQ.L #-0x1,D6                        | FLUSH LEFTMASK FOR END
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BEQ.B   HTOGL_END                       | BR IF NO UNMASKED WORDS
        LSR     #0x1,D2                         | HALVE WORDCOUNT FOR LONGCOUNT
        BCC.B   HTOGL_DBL_LONG                  | BR IF EVEN # WORDS LEFT
        EOR     D6,(A4)+                        | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BRA.B   HTOGL_LOOP_END                  | SEE IF ANY LONGS LEFT TO DO
HTOGL_NEXT_LONG:
        NOT.L   (A4)+                           | (A4)+ = ~(A4)+
HTOGL_DBL_LONG:
        NOT.L   (A4)+                           | (A4)+ = ~(A4)+
        SUBQ.W  #0x2,D2                         | count two fewer longs
HTOGL_LOOP_END:
        BGT.B   HTOGL_NEXT_LONG                 | YES, AT LEAST TWO LONGS
        BEQ.B   HTOGL_DBL_LONG                  | YES, FINISH UP LAST LONG
HTOGL_END:
        AND     D3,D6                           | COMBINE LEFT AND RIGHT MASK
        EOR     D6,(A4)                         | DRAW LINE
        BRA.W   DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| --------------------------------------------
| DRAW A BLACK HORIZONTAL LINE
| Called during boot.
HSET:
        SUB     D1,D2                           | CALC WORDCOUNT
        BEQ.B   HSET_END                        | BR IF ALL IN ONE WORD
        OR      D6,(A4)+                        | DO LEFT WORD WITH MASK
        MOVEQ.L #-0x1,D6                        | FLUSH LEFTMASK FOR END
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BEQ.B   HSET_END                        | BR IF NO UNMASKED WORDS
        LSR     #0x1,D2                         | HALVE WORDCOUNT FOR LONGCOUNT
        BCC.B   HSET_DBL_LONG                   | BR IF EVEN # WORDS LEFT
        MOVE    D6,(A4)+                        | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BRA.B   HSET_LOOP_END                   | SEE IF ANY LONGS LEFT TO DO
HSET_NEXT_LONG:
        MOVE.L  D6,(A4)+                        | FILL A LONG WITH BLACK
HSET_DBL_LONG:
        MOVE.L  D6,(A4)+                        | FILL ANOTHER LONG
        SUBQ.W  #0x2,D2                         | count two fewer longs
HSET_LOOP_END:
        BGT.B   HSET_NEXT_LONG                  | YES, AT LEAST TWO LONGS
        BEQ.B   HSET_DBL_LONG                   | YES, FINISH UP LAST LONG
HSET_END:
        AND     D3,D6                           | COMBINE LEFT AND RIGHT MASK
        OR      D6,(A4)                         | DRAW LINE
        BRA.W   DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT
HSET_LOOP_END_2:
        CMP     D2,D4                           | dh > 0?
        BSR.W   VSET_NEXT                       | GET DSTPTR,ROWBYTES,HGLOBAL
        JSR     LEFTMASK_CONT(PC)               | compute single-bit mask
        MOVE    -0x80(A6),D1                    | D1 = minRect.bottom
        SUB     -0x84(A6),D1                    | height = bot - top
        SUBQ.W  #0x1,D1                         | -1 for DBRA
        CMPI    #0xA,D5                         | mode < 10 (black)?
        BLT.B   VSET                            | BR IF BLACK
        BEQ.B    VTOGL                          | BR IF XOR
        NOT.W    D0                             | invert mask for clear
VCLR:
        AND     D0,(A4)                         | CLEAR ONE DOT
        ADDA.W  D7,A4                           | BUMP TO NEXT ROW
        DBRA    D1,VCLR                         | LOOP ALL DOTS
        BRA.W   DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| ----------------------------------------------------------
| VTOGL
VTOGL:
        EOR     D0,(A4)                         | TOGGLE ONE DOT
        ADDA.W  D7,A4                           | BUMP TO NEXT ROW
        DBRA    D1,VTOGL                        | LOOP ALL DOTS
        BRA.W   DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT
VSET:
        OR      D0,(A4)                         | SET ONE DOT
        ADDA.W  D7,A4                           | BUMP TO NEXT ROW
        DBRA    D1,VSET                         | LOOP ALL DOTS
        BRA.W   DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT
VSET_NEXT:
        MOVE    -0x84(A6),D1                    | D1 = minRect.top
        MOVE    -0x82(A6),D2                    | D2 = minRect.left
        MOVE.L  2(A5),A4                        | GET BITMAP BASE ADDRESS
        MOVE    D1,D0                           | D0 = top for offset calc
        SUB     8(A5),D0                        | - portBits.top
        MOVE    6(A5),D7                        | D7 = rowBytes
        MULU    D7,D0                           | MULT TOP BY ROWBYTES
        ADDA.L  D0,A4                           | A4 += vert byte offset
        MOVE    D2,D0                           | D0 = left for offset calc
        SUB     10(A5),D0                       | - portBits.left
        MOVE    D0,D1                           | MAKE A COPY
        LSR     #0x4,D1                         | /16 -> word index
        ADDA.W  D1,A4                           | ADD TO RUNNING TOTAL
        ADDA.W  D1,A4                           | TWICE FOR BYTES
        RTS                                     | return
PutLine:
        LINK.W   FP,#-4                         | local for length
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS, 8*4 ==> 32
        MOVE    26(A6),D2                       | D2 = newPt.h
        MOVE    22(A6),D4                       | D4 = oldPt.h
        CMP     D2,D4                           | IS THIS A VERTICAL LINE ?
        BEQ.W   PUTLINE_GOHOME                  | YES, IGNORE IT
        MOVE    D2,D0                           | GET H1
        SUB     D4,D0                           | SUBTRACT H2
        BPL.W   VSET_LOOP_END                   | BR IF DH POS
        NEG     D0                              | ELSE TAKE ABSOLUTE VALUE
VSET_LOOP_END:
        MOVE    24(A6),D1                       | D1 = newPt.v
        SUB     20(A6),D1                       | dv = newPt.v - oldPt.v
        BPL.W   VSET_CONT_3                     | BR IF DV POS
        NEG     D1                              | ELSE TAKE ABSOLUTE VALUE
VSET_CONT_3:
        CMP     D1,D0                           | IS DH <= DV ?
        BLE.B   DVPOS_OK                        | YES, CONTINUE
        MOVE    D1,D0                           | NO, PUT MIN(DH,DV) INTO D0

DVPOS_OK:
        ADDQ.W  #0x1,D0                         | add 1 to min(dh,dv) for endpoints
        LSL     #0x3,D0                         | times 8 for bytesNeeded
        MOVE.L  16(A6),A3                       | A3 = destination point buffer handle
        MOVE.L  12(A6),A4                       | A4 = ptr to buffer index variable
        ADD     (A4),D0                         | newSize = index + bytesNeeded
        MOVE.L  8(A6),A0                        | A0 = ptr to bufMax
        CMP     (A0),D0                         | need to grow dstBuf?
        BLE.B   DVPOS_NO                        | no -> continue
        ADDI    #0x200,D0                       | expand by 512-byte chunks
        MOVE    D0,(A0)                         | update bufMax
        MOVE.L  A3,-(SP)                        | push dstBuf handle for SetHSize
        MOVE    D0,-(SP)                        | push new bufMax
        JSR     SetHSize(PC)                    | grow the buffer
        MOVE    26(A6),D2                       | restore pt1.h clobbered by SetHSize
DVPOS_NO:
        MOVE.L  (A3),A3                         | DE-REFERENCE DSTHANDLE
        ADDA.W  (A4),A3                         | add index for current buf ptr
        MOVE    24(A6),D1                       | D1 = pt1.v
        MOVE    20(A6),D3                       | D3 = pt2.v
        CMP     D1,D3                           | horizontal line?
        BNE.B   PUTLINE_SLANTED                 | no -> handle slope
        MOVE    D1,(A3)+                        | put V1 vert coord
        MOVE    D2,(A3)+                        | put H1 horiz coord
        MOVE    D3,(A3)+                        | put V2 vert coord
        MOVE    D4,(A3)+                        | put H2 horiz coord
        BRA.W   NOCHNG_EXIT                     | done -> update index
PUTLINE_SLANTED:
        BGT.B   NOSWAP                          | already in vertical order -> skip
        EXG     D1,D3                           | sort points by vertical
        EXG     D2,D4                           | jump via A0
NOSWAP:
        MOVE    D1,D6                           | init V to topV
        CLR.L   -(SP)                           | reserve FixRatio result slot
        MOVE    D4,-(SP)                        | push botH
        SUB     D2,(SP)                         | (SP) -= D2
        MOVE    D3,-(SP)                        | push botV
        SUB     D1,(SP)                         | (SP) -= D1
        JSR     FixRatio(PC)                    | compute fixed-point slope
        MOVE.L  (SP)+,D7                        | D7 = slope (16.16 fixed)
        MOVE    D2,-4(A6)                       | local horiz.int = topH
        MOVE    #-0x8000,-2(A6)                 | local horiz.frac = 0.5
        MOVE.L  D7,D0                           | D0 = copy of slope
        ASR.L   #0x1,D0                         | D0 = slope / 2
        ADD.L   D0,-4(A6)                       | -4(A6) += D0
        TST.L   D7                              | slope sign?
        BMI.B   NOSWAP_OK                       | slope < 0 -> handle negative
        CMPI.L  #0x00010000,D7                  | D7 >= +65536?
        BGE.B   NOSWAP_NO                       | yes -> overflow: skip half
        ADD.L   D7,-4(A6)                       | no -> add D7 for small deltas
        BRA.B   NOSWAP_NO                       | skip neg-slope handling
NOSWAP_OK:
        CMPI.L  #0xFFFF0000,D7                  | D7 <= -65536?
        BGE.B   NOSWAP_NO                       | no -> skip rounding
        ADDQ.W  #0x1,-4(A6)                     | yes -> round up (towards zero)
NOSWAP_NO:
        MOVE    D2,D5                           | oldH = topH
LOOP:
        CMP     -4(A6),D5                       | oldH == new horiz.int?
        BEQ.B   NOCHNG                          | yes -> no slab to emit
        MOVE    D6,(A3)+                        | put vert coord (slab top)
        MOVE    D5,(A3)+                        | put oldH
        MOVE    -4(A6),D5                       | oldH = new horiz.int
        MOVE    D6,(A3)+                        | put vert coord (slab bot)
        MOVE    D5,(A3)+                        | put new horiz coord
NOCHNG:
        ADDQ.W  #0x1,D6                         | advance vert to next scanline
        ADD.L   D7,-4(A6)                       | -4(A6) += D7
        CMP     D6,D3                           | reached bottom?
        BNE.B   LOOP                            | no -> next slab
        CMP     D4,D5                           | oldH == botH (no last slab)?
        BEQ.B   NOCHNG_EXIT                     | yes -> done
        MOVE    D6,(A3)+                        | emit final slab vert
        MOVE    D5,(A3)+                        | emit final slab oldH
        MOVE    D6,(A3)+                        | emit final slab vert
        MOVE    D4,(A3)+                        | emit final slab botH
NOCHNG_EXIT:
        MOVE.L  16(A6),A0                       | A0 = dst handle
        SUBA.L  (A0),A3                         | A3 = bytes added (index delta)
        MOVE    A3,(A4)                         | update index
PUTLINE_GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | jump via A0
        ADDA.W  #0x14,SP                        | pop 20 bytes of params
        JMP     (A0)                            | RTS
