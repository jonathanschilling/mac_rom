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
|

| .PROC StdLine,1
| .REF CheckPic,PutPicVerb,PutPicByte,PutPicLong,DoLine
| ---------------------------------------------------------------
|
| PROCEDURE StdLine(newPt: Point);
|
| Called during boot.
StdLine:
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set NEWPT, PARAMSIZE+8-4                       | LONG, POINT

        LINK    A6,#0                           | NO LOCAL VARS
        MOVEM.L D5-D7/A3-A4,-(SP)               | SAVE REGS
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.B   STDLINE_NOTPIC                  | BRANCH IF NOT PICSAVE
        CLR.B   -(SP)                           | PUSH VERB (FRAME)
        JSR     PutPicVerb(PC)                  | CHECK pnSize, pnMode, pnPat

| --------------------------------------------------------
|
| PUT ONE OF FOUR LINE OPCODES BASED ON NEWPT AND DH,DV.
|
| line 20, pnLoc(pt), newPt(pt)
| line from 21, newPt(pt)
| short line 22, pnLoc(pt), dh,dv(-128..127)
| short line from 23, dh,dv(-128..127)
|
        MOVEQ.L #0x20,D7                        | INIT OPCODE TO $20

| --------------------------------------------------------
|
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  PNLOC(A3),D0                    | GET CURRENT PNLOC
        CMP.L   PICPNLOC(A4),D0                 | IS LINE FROM LAST ENDPOINT ?
        BNE.B   STDLINE_NO                      | NO, CONTINUE
        ADDQ.W  #0x1,D7                         | YES, SET BIT ZERO
STDLINE_NO:
        MOVE    0xA(A6),D6                      | GET NEWPT.H
        SUB     D0,D6                           | CALC DH = NEWPT.H - PNLOC.H
        MOVE    D6,D0                           | COPY DH
        EXT     D0                              | SIGN EXTEND TO WORD
        CMP     D6,D0                           | IS DH -128..127 ?
        BNE.B   PUTOP                           | NO, CONTINUE
        MOVE    0x8(A6),D5                      | GET NEWPT.V
        SUB     PNLOC(A3),D5                    | CALC DV = NEWPT.V - PNLOC.V
        MOVE    D5,D0                           | COPY DV
        EXT     D0                              | SIGN EXTEND TO WORD
        CMP     D5,D0                           | IS DV -128..127 ?
        BNE.B   PUTOP                           | NO, CONTINUE
        ADDQ.W  #0x2,D7                         | YES, SET BIT ONE IN OPCODE
PUTOP:
        MOVE.B  D7,-(SP)                        | PUSH OPCODE
        JSR     PutPicByte(PC)                  | PUT ONE OF 4 LINE OPCODES
        ROR     #1,D7                           | DO WE NEED STARTPT ? (BIT 0)
        BCS.B   STDLINE_STARTOK                 | NO, CONTINUE
        MOVE.L  PNLOC(A3),-(SP)                 | YES, PUSH STARTPT = PNLOC
        JSR     PutPicLong(PC)                  | YES, PUT STARTPT = PNLOC
STDLINE_STARTOK:
        ROR     #1,D7                           | STARTOK: IS LINE SHORT ? (BIT 1)
        BCS.B   DHDV                            | YES, PUT DH,DV
        MOVE.L  0x8(A6),-(SP)                   | NO, PUT LONG NEWPT
        JSR     PutPicLong(PC)                  | PUT NEWPT TO THEPIC
        BRA.B   UPDATE                          | AND CONTINUE

| ----------------------------------------------------------
|
| DHDV
|
DHDV:
        MOVE.B  D6,-(SP)                        | PUSH DH (-128..127)
        JSR     PutPicByte(PC)                  | PUT TO THEPIC
        MOVE.B  D5,-(SP)                        | PUSH DV (-128..127)
        JSR     PutPicByte(PC)                  | PUT TO THEPIC
UPDATE:
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  0x8(A6),PICPNLOC(A4)            | UPDATE PICTURE SAVING STATE
STDLINE_NOTPIC:
        MOVE.L  0x8(A6),-(SP)                   | PUSH NEWPT
        JSR     DoLine(PC)                      | DoLine(newPt);
        MOVEM.L (SP)+,D5-D7/A3-A4               | RESTORE REGS
        UNLK    A6                              | UNLINK PARAMSIZE
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | RETURN

| .PROC LineTo,2
| .REF StdLine
| ----------------------------------------------------------
|
| PROCEDURE LineTo(h,v: INTEGER);
|
| Called during boot.
LineTo:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xE40).w,A0                    | _StdLine (lineProc)
        BEQ.B   LINETO_USESTD                   | YES, USE STD PROC
        MOVE.L  D0,A0                           | PUT GRAFPROCS IN A0
        MOVE.L  LINEPROC(A0),A0                 | NO, GET PROC PTR
LINETO_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| .PROC Line,2
| .REF LineTo
| ----------------------------------------------------------
|
| PROCEDURE Line(dh,dv: INTEGER);
|
Line:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE    0x32(A0),D0                     | GET CURRENT PENLOC.H
        ADD     D0,0x6(SP)                      | ADD TO DH
        MOVE    0x30(A0),D0                     | GET CURRENT PENLOC.V
        ADD     D0,0x4(SP)                      | ADD TO DV
        JMP     LineTo(PC)                      | LineTo(pnLoc.h+dh,pnLoc.v+dv);

| .PROC MoveTo
| ----------------------------------------------------------
|
| PROCEDURE MoveTo(h,v: INTEGER);
|
| Called during boot.
MoveTo:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | POINT TO CURRENT GRAFPORT
        MOVE.L  (SP)+,PNLOC(A1)                 | COPY POINT INTO PNLOC
        JMP     (A0)                            | RETURN

| .PROC MQVE,2
| .DEF Moov
| ----------------------------------------------------------
|
| PROCEDURE Move(dh,dv: INTEGER);
|
| Called during boot.
Move:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D0                        | POP DV
        MOVE    (SP)+,D1                        | POP DH
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | GET CURRENT GRAFPORT
        ADD     D0,0x30(A1)                     | ADD DV TO PNLOC.V
        ADD     D1,0x32(A1)                     | ADD DH TO PNLOC.H
        JMP     (A0)                            | RETURN

| .PROC DoLine,1
| .REF DrawLine,PutLine,SetSize
| ----------------------------------------------------------
|
| PROCEDURE DoLine(newPt: Point);
|
| { called by StdLine and StdPoly frame }
|
| Called during boot.
DoLine:
        MOVEM.L D6-D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | POINT TO CURRENT GRAFPORT
        MOVE.L  0x14(SP),D7                     | GET NEWPT
        MOVE.L  PNLOC(A3),D6                    | OLDPT := THEPORT^.PNLOC

|
| CHECK IF WE ARE SAVING FOR A POLYGON
|
        TST.L   POLYSAVE(A3)                    | ARE WE SAVING FOR A POLYGON ?
        BEQ.B   NOTPOLY                         | NO, CONTINUE
        MOVE.L  THEPOLY(A4),A1                  | YES, GET POLYHANDLE
        MOVE.L  (A1),A0                         | DE-REFERENCE IT
        MOVE    (A0),D0                         | GET CURRENT POLYSIZE
        CMPI    #0xA,D0                         | IS THIS THE FIRST POINT ?
        BNE.B   DOLINE_NO                       | NO, CONTINUE
        MOVE.L  D6,0x0(A0,D0.W)                 | YES, INSTALL FIRST := OLDPT
        ADDQ.W  #0x4,D0                         | BUMP INDEX
DOLINE_NO:
        MOVE.L  D7,0x0(A0,D0.W)                 | INSTALL NEWPT AT END
        ADDQ.W  #0x4,D0                         | BUMP INDEX
        MOVE    D0,(A0)                         | UPDATE INDEX
        CMP     POLYMAX(A4),D0                  | TIME TO MAKE BIGGER ?
        BLT.B   SIZEOK                          | NO, CONTINUE
        ADDI    #0x100,-0xA4(A4)                | YES, GROW IN CHUNKS
        MOVE.L  A1,-(SP)                        | PUSH POLYHANDLE
        MOVE    POLYMAX(A4),-(SP)               | PUSH NEW SIZE
        JSR     SetHSize(PC)                    | MAKE THEPOLY BIGGER
SIZEOK:
        BRA.B   DOLINE_NOTRGN                   | DONT SAVE FOR RGN TOO

|
| IF NOT POLY, THEN CHECK FOR RGNSAVE.
| IF RGNSAVE THEN PutLine(oldPt,newPt,rgnBuf,rgnIndex,rgnMax);
|
| Called during boot.
NOTPOLY:
        TST.L   RGNSAVE(A3)                     | ARE WE SAVING FOR A REGION ?
        BEQ.B   DOLINE_NOTRGN                   | NO, SKIP REGION SAVE
        MOVE.L  D6,-(SP)                        | PUSH OLDPT
        MOVE.L  D7,-(SP)                        | PUSH NEWPT
        MOVE.L  RGNBUF(A4),-(SP)                | PUSH RGNBUF
        PEA.L   RGNINDEX(A4)                    | PUSH VAR RGNINDEX
        PEA.L   RGNMAX(A4)                      | PUSH VAR RGNMAX
        JSR     PutLine(PC)                     | ADD INVERSION PTS TO RGNBUF
DOLINE_NOTRGN:
        MOVE.L  D6,-(SP)                        | NOTRGN: PUSH OLDPT
        MOVE.L  D7,-(SP)                        | PUSH NEWPT
        JSR     DrawLine(PC)                    | DRAW THE LINE
        MOVE.L  D7,PNLOC(A3)                    | UPDATE THEPORT^.PNLOC
        MOVEM.L (SP)+,D6-D7/A3-A4               | RESTORE REGS
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| .PROC HidePen,0
| .DEF ShowPen
| ----------------------------------------------------------
|
| PROCEDURE HidePen;
|
| Called during boot.
HidePen:
        MOVEQ   #-1,D0                          | SET FLAG TO DECREMENT
        BRA.B   SHOWPEN_CONT                    | AND SHARE CODE

| ----------------------------------------------------------
|
| PROCEDURE ShowPen;
|
| Called during boot.
ShowPen:
        MOVEQ   #1,D0                           | SET FLAG TO INCREMENT
SHOWPEN_CONT:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        ADD     D0,PNVIS(A0)                    | INCREMENT/DECREMENT PNVIS
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| _PmBackColor ($A898)
|
| Called during boot.
GetPenState:
        MOVEQ   #1,D0                           | SET A FLAG
        BRA.B   SETPENSTATE_CONT                | AND SHARE CODE

| .PROC GetPenState,1
| .DEF SetPenState
| ----------------------------------------------------------
|
| PROCEDURE GetPenState(VAR pnState: PenState);
| PROCEDURE SetPenState(pnState: PenState);
|
| Called during boot.
SetPenState:
        CLR     D0                              | CLEAR FLAG AND SHARE
SETPENSTATE_CONT:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L   PNLOC(A0),A0                    | POINT TO PNLOC
        MOVE.L  0x4(SP),A1                      | POINT TO VAR PNSTATE
        TST     D0                              | is this SET penstate ?
        BNE.B   NOTSET                          | NO, CONTINUE
        EXG     A0,A1                           | YES, SWAP SRC AND DST
NOTSET:
        MOVE.L  (A0)+,(A1)+                     | COPY PNLOC FROM THEPORT
        MOVE.L  (A0)+,(A1)+                     | COPY PNSIZE FROM THEPORT
        MOVE    (A0)+,(A1)+                     | COPY PNMODE FROM THEPORT
        MOVE.L  (A0)+,(A1)+                     | COPY PNPAT FROM THEPORT
        MOVE.L  (A0)+,(A1)+                     | ALL 8 BYTES
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| .PROC GetPen,1
| ----------------------------------------------------------
|
| PROCEDURE GetPen(VAR pt: Point);
| { inquire the current pen location }
|
| Called during boot.
GetPen:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  0x4(SP),A1                      | POINT TO VAR PT
        MOVE.L  PNLOC(A0),(A1)                  | GET PNLOC FROM THEPORT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| SetPenState
| .PROC PenSize,2
| ----------------------------------------------------------
|
| PROCEDURE PenSize(width,height: INTEGER);
| { set the pen width and height }
|
| Called during boot.
PenSize:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  0x4(SP),PNSIZE(A0)              | SET PEN WIDTH AND HEIGHT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| .PROC PenMode,1
| .REF PortWord
| ----------------------------------------------------------
|
| PROCEDURE PenMode(mode: INTEGER);
| { set the transfer mode for line drawing }
| Called during boot.
PenMode:
        MOVEQ.L #0x38,D0                        | PUT PORT OFFSET IN D0
        JMP     L_mPortWord(PC)                 | INSTALL PARAM INTO THEPORT

| .PROC PenPat,1
| ----------------------------------------------------------
|
| PROCEDURE PenPat(pat: Pattern);
| { set the pattern for line drawing }
|
| Called during boot.
PenPat:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L   PNPAT(A0),A0                    | POINT TO PNPAT
        MOVE.L  0x4(SP),A1                      | POINT TO INPUT PATTERN
        MOVE.L  (A1)+,(A0)+                     | COPY PATTERN INTO THEPORT
        MOVE.L  (A1)+,(A0)+                     | ALL 8 BYTES
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| .PROC PenNormal,0
| ----------------------------------------------------------
|
| PROCEDURE PenNormal;
| { restore all line drawing parameters to normal }
|
| Called during boot.
PenNormal:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  #0x10001,PNSIZE(A0)             | PEN SIZE:=1,1
        MOVE    #8,PNMODE(A0)                   | PENMODE:=PATTERN COPY
        MOVEQ   #-1,D0                          | SET D0 TO BLACK PATTERN
        MOVE.L  D0,PNPAT(A0)                    | PNPAT:=BLACK
        MOVE.L  D0,0x3E(A0)                     | PNPAT+4:=BLACK
        RTS                                     | AND RETURN



