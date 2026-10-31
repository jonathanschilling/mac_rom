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

| ASCII art:
| *       *  ****   *   *  *****
| *       *    *    **  *  *
| *       *    *    * * *  *****
| *       *    *    *  **  *
| *****   *  ****   *   *  *****
|
| Line Drawing Routines
|
| .PROC StdLine,1
| .REF CheckPic,PutPicVerb,PutPicByte,PutPicLong,DoLine
| ---------------------------------------------------------------
|
| PROCEDURE StdLine(newPt: Point);
|
| Called during boot.
STDLINE:
    LINK        A6,#0x0                         | NO LOCAL VARS
    MOVEM.L     D5-D7/A3-A4,-(A7)               | SAVE REGS
    JSR         CHECKPIC(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
    BLE.B       STDLINE_NOTPIC                  | BRANCH IF NOT PICSAVE
    CLR.B       -(A7)                           | PUSH VERB (FRAME)
    JSR         PUTPICVERB(PC)                  | CHECK pnSize, pnMode, pnPat
| --------------------------------------------------------
|
| PUT ONE OF FOUR LINE OPCODES BASED ON NEWPT AND DH,DV.
|
| line 20, pnLoc(pt), newPt(pt)
| line from 21, newPt(pt)
| short line 22, pnLoc(pt), dh,dv(-128..127)
| short line from 23, dh,dv(-128..127)
|
    MOVEQ.L     #0x20,D7                        | INIT OPCODE TO $20
    MOVEA.L     0x5C(A3),A4                     | GET PICSAVE HANDLE
    MOVEA.L     (A4),A4                         | DE-REFERENCE PICSAVE
    MOVE.L      0x30(A3),D0                     | GET CURRENT PNLOC
    CMP.L       0x30(A4),D0                     | IS LINE FROM LAST ENDPOINT ?
    BNE.B       STDLINE_NO                      | NO, CONTINUE
    ADDQ.W      #0x1,D7                         | YES, SET BIT ZERO
STDLINE_NO:
    MOVE.W      0xA(A6),D6                      | GET NEWPT.H
    SUB.W       D0,D6                           | CALC DH = NEWPT.H - PNLOC.H
    MOVE.W      D6,D0                           | COPY DH
    EXT.W       D0                              | SIGN EXTEND TO WORD
    CMP.W       D6,D0                           | IS DH -128..127 ?
    BNE.B       PUTOP                           | NO, CONTINUE
    MOVE.W      0x8(A6),D5                      | GET NEWPT.V
    SUB.W       0x30(A3),D5                     | CALC DV = NEWPT.V - PNLOC.V
    MOVE.W      D5,D0                           | COPY DV
    EXT.W       D0                              | SIGN EXTEND TO WORD
    CMP.W       D5,D0                           | IS DV -128..127 ?
    BNE.B       PUTOP                           | NO, CONTINUE
    ADDQ.W      #0x2,D7                         | YES, SET BIT ONE IN OPCODE
PUTOP:
    MOVE.B      D7,-(A7)                        | PUSH OPCODE
    JSR         PUTPICBYTE(PC)                  | PUT ONE OF 4 LINE OPCODES
    ROR.W       #0x1,D7                         | DO WE NEED STARTPT ? (BIT 0)
    BCS.B       STDLINE_STARTOK                 | NO, CONTINUE
    MOVE.L      0x30(A3),-(A7)                  | YES, PUSH STARTPT = PNLOC
    JSR         PUTPICLONG(PC)                  | YES, PUT STARTPT = PNLOC
STDLINE_STARTOK:
    ROR.W       #0x1,D7                         | STARTOK: IS LINE SHORT ? (BIT 1)
    BCS.B       DHDV                            | YES, PUT DH,DV
    MOVE.L      0x8(A6),-(A7)                   | NO, PUT LONG NEWPT
    JSR         PUTPICLONG(PC)                  | PUT NEWPT TO THEPIC
    BRA.B       UPDATE                          | AND CONTINUE
| ----------------------------------------------------------
|
| DHDV
|
DHDV:
    MOVE.B      D6,-(A7)                        | PUSH DH (-128..127)
    JSR         PUTPICBYTE(PC)                  | PUT TO THEPIC
    MOVE.B      D5,-(A7)                        | PUSH DV (-128..127)
    JSR         PUTPICBYTE(PC)                  | PUT TO THEPIC
UPDATE:
    MOVEA.L     0x5C(A3),A4                     | GET PICSAVE HANDLE
    MOVEA.L     (A4),A4                         | DE-REFERENCE PICSAVE
    MOVE.L      0x8(A6),0x30(A4)                | UPDATE PICTURE SAVING STATE
STDLINE_NOTPIC:
    MOVE.L      0x8(A6),-(A7)                   | PUSH NEWPT
    JSR         DOLINE(PC)                      | DoLine(newPt);
    MOVEM.L     (A7)+,D5-D7/A3-A4               | RESTORE REGS
    UNLK        A6                              | UNLINK PARAMSIZE
    MOVE.L      (A7)+,(A7)                      | STRIP PARAM
    RTS                                         | AND RETURN
| .PROC LineTo,2
| .REF StdLine
| ----------------------------------------------------------
|
| PROCEDURE LineTo(h,v: INTEGER);
|
| Called during boot.
LINETO:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    MOVE.L      0x68(A0),D0                     | IS GRAFPROCS NIL ?
    MOVEA.L     (0x1040).W,A0                   | _StdLine (lineProc)
    BEQ.B       LINETO_USESTD                   | YES, USE STD PROC
    MOVEA.L     D0,A0                           | PUT GRAFPROCS IN A0
    MOVEA.L     0x4(A0),A0                      | NO, GET PROC PTR
LINETO_USESTD:
    JMP         (A0)                            | USESTD: GO TO IT
| .PROC Line,2
| .REF LineTo
| ----------------------------------------------------------
|
| PROCEDURE Line(dh,dv: INTEGER);
|
LINE:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    MOVE.W      0x32(A0),D0                     | GET CURRENT PENLOC.H
    ADD.W       D0,0x6(A7)                      | ADD TO DH
    MOVE.W      0x30(A0),D0                     | GET CURRENT PENLOC.V
    ADD.W       D0,0x4(A7)                      | ADD TO DV
    JMP         LINETO(PC)                      | LineTo(pnLoc.h+dh,pnLoc.v+dv);
| .PROC MoveTo
| ----------------------------------------------------------
|
| PROCEDURE MoveTo(h,v: INTEGER);
|
| Called during boot.
MOVETO:
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDR
    MOVEA.L     (A5),A1                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A1),A1                         | POINT TO CURRENT GRAFPORT
    MOVE.L      (A7)+,0x30(A1)                  | COPY POINT INTO PNLOC
    JMP         (A0)                            | RETURN
| .PROC MQVE,2
| .DEF Moov
| ----------------------------------------------------------
|
| PROCEDURE Move(dh,dv: INTEGER);
|
| Called during boot.
MOVE:                                           | Apple source module (MacSEROM.lst)
MOOV:
    MOVEA.L     (A7)+,A0                        | POP RETURN ADDR
    MOVE.W      (A7)+,D0                        | POP DV
    MOVE.W      (A7)+,D1                        | POP DH
    MOVEA.L     (A5),A1                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A1),A1                         | GET CURRENT GRAFPORT
    ADD.W       D0,0x30(A1)                     | ADD DV TO PNLOC.V
    ADD.W       D1,0x32(A1)                     | ADD DH TO PNLOC.H
    JMP         (A0)                            | RETURN
| .PROC DoLine,1
| .REF DrawLine,PutLine,SetSize
| ----------------------------------------------------------
|
| PROCEDURE DoLine(newPt: Point);
|
| { called by StdLine and StdPoly frame }
|
| Called during boot.
DOLINE:
    MOVEM.L     D6-D7/A3-A4,-(A7)               | SAVE REGS
    MOVEA.L     (A5),A4                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A4),A3                         | POINT TO CURRENT GRAFPORT
    MOVE.L      0x14(A7),D7                     | GET NEWPT
    MOVE.L      0x30(A3),D6                     | OLDPT := THEPORT^.PNLOC
|
| CHECK IF WE ARE SAVING FOR A POLYGON
|
    TST.L       0x64(A3)                        | ARE WE SAVING FOR A POLYGON ?
    BEQ.B       NOTPOLY                         | NO, CONTINUE
    MOVEA.L     -0xA2(A4),A1                    | YES, GET POLYHANDLE
    MOVEA.L     (A1),A0                         | DE-REFERENCE IT
    MOVE.W      (A0),D0                         | GET CURRENT POLYSIZE
    CMPI.W      #0xA,D0                         | IS THIS THE FIRST POINT ?
    BNE.B       DOLINE_NO                       | NO, CONTINUE
    MOVE.L      D6,0x0(A0,D0.W)                 | YES, INSTALL FIRST := OLDPT
    ADDQ.W      #0x4,D0                         | BUMP INDEX
DOLINE_NO:
    MOVE.L      D7,0x0(A0,D0.W)                 | INSTALL NEWPT AT END
    ADDQ.W      #0x4,D0                         | BUMP INDEX
    MOVE.W      D0,(A0)                         | UPDATE INDEX
    CMP.W       -0xA4(A4),D0                    | TIME TO MAKE BIGGER ?
    BLT.B       SIZEOK                          | NO, CONTINUE
    ADDI.W      #0x100,-0xA4(A4)                | YES, GROW IN CHUNKS
    MOVE.L      A1,-(A7)                        | PUSH POLYHANDLE
    MOVE.W      -0xA4(A4),-(A7)                 | PUSH NEW SIZE
    JSR         SETHSIZE(PC)                    | MAKE THEPOLY BIGGER
SIZEOK:
    BRA.B       DOLINE_NOTRGN                   | DONT SAVE FOR RGN TOO
|
| IF NOT POLY, THEN CHECK FOR RGNSAVE.
| IF RGNSAVE THEN PutLine(oldPt,newPt,rgnBuf,rgnIndex,rgnMax);
|
| Called during boot.
NOTPOLY:
    TST.L       0x60(A3)                        | ARE WE SAVING FOR A REGION ?
    BEQ.B       DOLINE_NOTRGN                   | NO, SKIP REGION SAVE
    MOVE.L      D6,-(A7)                        | PUSH OLDPT
    MOVE.L      D7,-(A7)                        | PUSH NEWPT
    MOVE.L      -0x94(A4),-(A7)                 | PUSH RGNBUF
    PEA.L       -0x96(A4)                       | PUSH VAR RGNINDEX
    PEA.L       -0x98(A4)                       | PUSH VAR RGNMAX
    JSR         PUTLINE(PC)                     | ADD INVERSION PTS TO RGNBUF
DOLINE_NOTRGN:
    MOVE.L      D6,-(A7)                        | NOTRGN: PUSH OLDPT
    MOVE.L      D7,-(A7)                        | PUSH NEWPT
    JSR         DRAWLINE(PC)                    | DRAW THE LINE
    MOVE.L      D7,0x30(A3)                     | UPDATE THEPORT^.PNLOC
    MOVEM.L     (A7)+,D6-D7/A3-A4               | RESTORE REGS
    MOVE.L      (A7)+,(A7)                      | STRIP PARAM
    RTS                                         | AND RETURN
| .PROC HidePen,0
| .DEF ShowPen
| ----------------------------------------------------------
|
| PROCEDURE HidePen;
|
| Called during boot.
HIDEPEN:
    MOVEQ.L     #-0x1,D0                        | SET FLAG TO DECREMENT
    BRA.B       SHOWPEN_CONT                    | AND SHARE CODE
| ----------------------------------------------------------
|
| PROCEDURE ShowPen;
|
| Called during boot.
SHOWPEN:
    MOVEQ.L     #0x1,D0                         | SET FLAG TO INCREMENT
SHOWPEN_CONT:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    ADD.W       D0,0x42(A0)                     | INCREMENT/DECREMENT PNVIS
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| _PmBackColor ($A898)
|
| Called during boot.
GETPENSTATE:
    MOVEQ.L     #0x1,D0                         | SET A FLAG
    BRA.B       SETPENSTATE_CONT                | AND SHARE CODE
| .PROC GetPenState,1
| .DEF SetPenState
| ----------------------------------------------------------
|
| PROCEDURE GetPenState(VAR pnState: PenState);
| PROCEDURE SetPenState(pnState: PenState);
|
| Called during boot.
SETPENSTATE:
    CLR.W       D0                              | CLEAR FLAG AND SHARE
SETPENSTATE_CONT:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    LEA.L       0x30(A0),A0                     | POINT TO PNLOC
    MOVEA.L     0x4(A7),A1                      | POINT TO VAR PNSTATE
    TST.W       D0                              | is this SET penstate ?
    BNE.B       NOTSET                          | NO, CONTINUE
    EXG         A0,A1                           | YES, SWAP SRC AND DST
NOTSET:
    MOVE.L      (A0)+,(A1)+                     | COPY PNLOC FROM THEPORT
    MOVE.L      (A0)+,(A1)+                     | COPY PNSIZE FROM THEPORT
    MOVE.W      (A0)+,(A1)+                     | COPY PNMODE FROM THEPORT
    MOVE.L      (A0)+,(A1)+                     | COPY PNPAT FROM THEPORT
    MOVE.L      (A0)+,(A1)+                     | ALL 8 BYTES
    MOVE.L      (A7)+,(A7)                      | STRIP 4 BYTES
    RTS                                         | AND RETURN
| .PROC GetPen,1
| ----------------------------------------------------------
|
| PROCEDURE GetPen(VAR pt: Point);
| { inquire the current pen location }
|
| Called during boot.
GETPEN:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    MOVEA.L     0x4(A7),A1                      | POINT TO VAR PT
    MOVE.L      0x30(A0),(A1)                   | GET PNLOC FROM THEPORT
    MOVE.L      (A7)+,(A7)                      | STRIP 4 BYTES
    RTS                                         | AND RETURN
| .PROC PenSize,2
| ----------------------------------------------------------
|
| PROCEDURE PenSize(width,height: INTEGER);
| { set the pen width and height }
|
| Called during boot.
PENSIZE:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    MOVE.L      0x4(A7),0x34(A0)                | SET PEN WIDTH AND HEIGHT
    MOVE.L      (A7)+,(A7)                      | STRIP 4 BYTES
    RTS                                         | AND RETURN
| .PROC PenMode,1
| .REF PortWord
| ----------------------------------------------------------
|
| PROCEDURE PenMode(mode: INTEGER);
| { set the transfer mode for line drawing }
| Called during boot.
PENMODE:
    MOVEQ.L     #0x38,D0                        | PUT PORT OFFSET IN D0
    JMP         PORTWORD(PC)                    | INSTALL PARAM INTO THEPORT
| .PROC PenPat,1
| ----------------------------------------------------------
|
| PROCEDURE PenPat(pat: Pattern);
| { set the pen pattern }
|
PENPAT:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    LEA.L       0x3A(A0),A0                     | POINT TO PNPAT
    MOVEA.L     0x4(A7),A1                      | POINT TO PATTERN
    MOVE.L      (A1)+,(A0)+                     | COPY 4 BYTES
    MOVE.L      (A1)+,(A0)+                     | COPY 4 BYTES
    MOVE.L      (A7)+,(A7)                      | STRIP 4 BYTES
    RTS                                         | AND RETURN
| .PROC PenNormal,0
| ----------------------------------------------------------
|
| PROCEDURE PenNormal;
| { reset the pen to its standard 1x1 black pattern }
|
PENNORMAL:
    MOVEA.L     (A5),A0                         | POINT TO QUICKDRAW GLOBALS
    MOVEA.L     (A0),A0                         | GET CURRENT GRAFPORT
    MOVE.L      #0x10001,0x34(A0)               | PNSIZE := (1,1)
    MOVE.W      #0x8,0x38(A0)                   | PNMODE := patCopy
    MOVEQ.L     #-0x1,D0                        | GET ALL ONES
    MOVE.L      D0,0x3A(A0)                     | PNPAT := black
    MOVE.L      D0,0x3E(A0)                     | SECOND HALF OF BLACK
    RTS                                         | AND RETURN
