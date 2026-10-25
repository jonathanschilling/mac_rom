| -----------------------------------------------------------------
|
|
|     *      ***   *   *  *****   ***
|     *       *    *   *  *      *   *
|     *       *    **  *  *      *
|     *       *    * * *  ***     ***
|     *       *    *  **  *          *
|     *       *    *   *  *      *   *
|     *****  ***   *   *  *****   ***
|
|
|
|  Line Drawing Rountines

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
        RTS                                     | return from STDLINE_NOTPIC
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
| ----------------------------------------------------------
|
| _Line ($A892): draw a line relative to the current pen location
| Pascal: PROCEDURE Line(dh, dv: INTEGER);
| Entry: 4(SP) = dv, 6(SP) = dh
| Adds pnLoc to the parameters in place and tail-jumps to LineTo, i.e.
| LineTo(pnLoc.h+dh, pnLoc.v+dv).
|
Line:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE    0x32(A0),D0                     | D0 = pnLoc.h
        ADD     D0,6(SP)                        | dh := pnLoc.h + dh
        MOVE    0x30(A0),D0                     | D0 = pnLoc.v
        ADD     D0,4(SP)                        | dv := pnLoc.v + dv
        JMP     LineTo(PC)                      | LineTo(pnLoc.h+dh, pnLoc.v+dv)
MoveTo:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVE.L  (A5),A1                         | A1 = QD globals
        MOVE.L  (A1),A1                         | A1 = thePort
        MOVE.L  (SP)+,0x30(A1)                  | thePort.pn := newPt
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _Move ($A894): move the pen location by (dh, dv) without drawing
| Pascal: PROCEDURE Move(dh, dv: INTEGER);
| The 1983 Lines.a names the entry Moov (.PROC MQVE / .DEF Moov); MPW
| Traps.a defines both _Moov and _Move as $A894.
|
Move:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVE    (SP)+,D0                        | POP DV
        MOVE    (SP)+,D1                        | POP DH
        MOVE.L  (A5),A1                         | A1 = QD globals
        MOVE.L  (A1),A1                         | A1 = thePort
        ADD     D0,0x30(A1)                     | pnLoc.v += dv
        ADD     D1,0x32(A1)                     | pnLoc.h += dh
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
        RTS                                     | return from DOLINE_NOTRGN
HidePen:
        MOVE.L  (A5),A0                         | STRIP 4 BYTES
        MOVE.L  (A0),A0                         | A0 = thePort
        SUBQ.W  #0x1,0x42(A0)                   | pnVis-- (hide if <0)
        RTS                                     | return from HidePen
ShowPen:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        ADDQ.W  #0x1,0x42(A0)                   | 0x42(A0) += 0x1
        RTS                                     | return from ShowPen

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
        RTS                                     | return from NOTSET
| -------------------------------------------------------------
| PROCEDURE GetPen(VAR pt: Point); { inquire current pen location }
GetPen:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  4(SP),A1                        | POINT TO VAR PT
        MOVE.L  0x30(A0),(A1)                   | GET PNLOC FROM THEPORT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | return from GetPen
| -------------------------------------------------------------
| PROCEDURE PenSize(width,height: INTEGER);
PenSize:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  4(SP),0x34(A0)                  | SET PEN WIDTH AND HEIGHT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | return from PenSize
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
        RTS                                     | return from PenPat
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
        RTS                                     | return from PenNormal

