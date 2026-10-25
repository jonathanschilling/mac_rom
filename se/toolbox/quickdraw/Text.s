| ---------------------------------------------------------
|
|
|     *****  *****  *   *  *****
|       *    *      *   *    *
|       *    *       * *     *
|       *    ***      *      *
|       *    *       * *     *
|       *    *      *   *    *
|       *    *****  *   *    *
|
|
|  Routines for measuring and drawing Text.

| .PROC StdText,4
| .REF CheckPic,DPutPicByte,PutPicData,PutPicWord,PutPicLong
| .REF DrText
| --------------------------------------------------------------------------
|
| PROCEDURE StdText(count: INTEGER; textAddr: Ptr; numer,denom: Point);
|
| The standard QuickDraw text-output procedure.  When picSave is non-nil
| this records text-state opcodes and a TextRun opcode into the picture;
| otherwise it tail-calls DrText.  Long runs (>255 chars) loop here in
| 255-byte chunks because picture text opcodes carry an 8-bit count.
|
| Called during boot.
STDTEXT:
.set PARAMSIZE, 14                              | TOTAL BYTES OF PARAMS
.set COUNT, PARAMSIZE+8-2                       | WORD
.set TEXTADDR, COUNT-4                          | LONG
.set NUMER, TEXTADDR-4                          | POINT
.set DENOM, NUMER-4                             | POINT
.set TXLOC, -4                                  | POINT
.set VARSIZE, TXLOC                             | TOTAL LOCALS
    LINK	A6,#-0x4                               | ALLOCATE STACK FRAME
    MOVEM.L	D5-D7/A3-A4,-(A7)                   | SAVE REGS
TXTLOOP:
    MOVE.W	0x14(A6),D6                          | GET CHARACTER COUNT
    BLE.W	STDTEXT_GOHOME                        | QUIT IF COUNT <= 0
    CMPI.W	#0xFF,D6                             | is count > 255 ?
    BLE.B	COUNTOK                               | no, continue
    MOVE.W	#0xFF,D6                             | yes, pin at 255
COUNTOK:
    JSR	CHECKPIC(PC)                            | SET UP A4,A3 AND CHECK PICSAVE
    BLE.W	STDTEXT_NOTPIC                        | no pic, branch to draw text
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
|
| CHECK TXFONT
|
    MOVE.W	0x44(A3),D7                          | GET THEPORT^.TXFONT
    CMP.W	0x18(A4),D7                           | HAS IT CHANGED ?
    BEQ.B	FONTOK                                | NO, CONTINUE
    MOVEQ.L	#0x3,D0                             | YES, PUSH TXFONT PARAM OPCODE
    JSR	DPUTPICBYTE(PC)                         | PUT OPCODE
    MOVE.W	D7,-(A7)                             | push txFont to save in pic
    JSR	PUTPICWORD(PC)                          | PUT TXFONT PARAM
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
    MOVE.W	D7,0x18(A4)                          | UPDATE CURRENT STATE
|
| CHECK TXFACE
|
FONTOK:
    MOVE.B	0x46(A3),D7                          | GET THEPORT^.TXFACE
    CMP.B	0x1A(A4),D7                           | HAS IT CHANGED ?
    BEQ.B	FACEOK                                | NO, CONTINUE
    MOVEQ.L	#0x4,D0                             | YES, PUSH TXFACE PARAM OPCODE
    JSR	DPUTPICBYTE(PC)                         | PUT OPCODE
    MOVE.B	D7,D0                                | copy txFace for pic
    JSR	DPUTPICBYTE(PC)                         | PUT TXFACE PARAM
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
    MOVE.B	D7,0x1A(A4)                          | UPDATE CURRENT STATE
|
| CHECK TXMODE
|
FACEOK:
    MOVE.W	0x48(A3),D7                          | GET THEPORT^.TXMODE
    CMP.W	0x1C(A4),D7                           | HAS IT CHANGED ?
    BEQ.B	STDTEXT_MODEOK                        | NO, CONTINUE
    MOVEQ.L	#0x5,D0                             | YES, PUSH TXMODE PARAM OPCODE
    JSR	DPUTPICBYTE(PC)                         | PUT OPCODE
    MOVE.W	D7,-(A7)                             | push txMode to save in pic
    JSR	PUTPICWORD(PC)                          | PUT TXMODE PARAM
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
    MOVE.W	D7,0x1C(A4)                          | UPDATE CURRENT STATE
|
| CHECK TXSIZE
|
STDTEXT_MODEOK:
    MOVE.W	0x4A(A3),D7                          | MODEOK: GET THEPORT^.TXSIZE
    CMP.W	0x1E(A4),D7                           | HAS IT CHANGED ?
    BEQ.B	STDTEXT_SIZEOK                        | NO, CONTINUE
    MOVEQ.L	#0xD,D0                             | YES, PUSH TXSIZE PARAM OPCODE
    BSR.B	STDTEXT_NOTSAME_NO_2                  | PUT OPCODE
    MOVE.W	D7,-(A7)                             | push txSize param
    JSR	PUTPICWORD(PC)                          | PUT TXSIZE PARAM
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
    MOVE.W	D7,0x1E(A4)                          | UPDATE CURRENT STATE
|
| CHECK SPEXTRA
|
STDTEXT_SIZEOK:
    MOVE.L	0x4C(A3),D7                          | SIZEOK: GET THEPORT^.SPEXTRA
    CMP.L	0x20(A4),D7                           | HAS IT CHANGED ?
    BEQ.B	SPOK                                  | NO, CONTINUE
    MOVEQ.L	#0x6,D0                             | YES, PUSH SPEXTRA PARAM OPCODE
    BSR.B	STDTEXT_NOTSAME_NO_2                  | PUT OPCODE
    MOVE.L	D7,-(A7)                             | push spExtra param
    BSR.B	STDTEXT_NOTSAME_CONT                  | PUT SPEXTRA PARAM
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
    MOVE.L	D7,0x20(A4)                          | UPDATE CURRENT STATE
|
| CHECK NUMER, DENOM
|
SPOK:
    MOVE.L	0xC(A6),D7                           | GET NUMER
    MOVE.L	0x8(A6),D5                           | GET DENOM
    CMP.L	0x24(A4),D7                           | HAS IT CHANGED ?
    BNE.B	STDTEXT_NOTSAME                       | YES, RECORD CHANGE
    CMP.L	0x28(A4),D5                           | HAS IT CHANGED ?
    BEQ.B	STDTEXT_NOTSAME_NO                    | NO, CONTINUE
STDTEXT_NOTSAME:
    MOVEQ.L	#0x10,D0                            | YES, PUSH TXRATIO OPCODE
    BSR.B	STDTEXT_NOTSAME_NO_2                  | PUT OPCODE
    MOVE.L	D7,-(A7)                             | push numer param
    BSR.B	STDTEXT_NOTSAME_CONT                  | PUT NUMER
    MOVE.L	D5,-(A7)                             | push denom param
    BSR.B	STDTEXT_NOTSAME_CONT                  | PUT DENOM
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
    MOVE.L	D7,0x24(A4)                          | UPDATE CURRENT STATE
    MOVE.L	D5,0x28(A4)                          | UPDATE CURRENT STATE
| NUMEROK

| -------------------------------------------------------------
|
| USE DH AND DV TO CHOOSE ONE OF FOUR TEXT OPCODES.
|
STDTEXT_NOTSAME_NO:
    MOVE.L	0x30(A3),D5                          | GET CURRENT PNLOC
    SUB.L	0x2C(A4),D5                           | CALC DV.DH
    MOVE.L	D5,D0                                | COPY DV.DH
    ANDI.L	#0xFF00FF00,D0                       | ARE DH AND DV BOTH 0..255 ?
    BEQ.B	SHORT                                 | YES, USE SHORT FORM
    MOVEQ.L	#0x28,D0                            | NO, PUT LONGTEXT OPCODE
    BSR.B	STDTEXT_NOTSAME_NO_2                  | NO, PUT LONGTEXT OPCODE
    MOVE.L	0x30(A3),-(A7)                       | push pnLoc 4 bytes
    BSR.B	STDTEXT_NOTSAME_CONT                  | PUT PNLOC 4 BYTES
    BRA.B	TEXT2                                 | AND CONTINUE
| STDTEXT_NOTSAME_NO_2 -- pUT OPCODE.
| JDPutPicByte
| Called by: STDTEXT_DHDV, STDTEXT_MODEOK, STDTEXT_SIZEOK, STDTEXT_NOTSAME, STDTEXT_NOTSAME_NO (and 4 more)
STDTEXT_NOTSAME_NO_2:
    JMP	DPUTPICBYTE(PC)                         | go to DPutPicByte
| ----------------------------------------------------------
|
| STDTEXT_NOTSAME_CONT
|
STDTEXT_NOTSAME_CONT:
    JMP	PUTPICLONG(PC)                          | go to PutPicLong
| ----------------------------------------------------------
|
| SHORT
|
SHORT:
    MOVE.L	D5,D0                                | YES, COPY DV.DH
    ANDI.L	#0xFF0000,D0                         | IS DV = 0 ?
    BNE.B	DV                                    | NO, CONTINUE
    MOVEQ.L	#0x29,D0                            | YES, PUT DHTEXT OPCODE
    BSR.B	STDTEXT_NOTSAME_NO_2                  | YES, PUT DHTEXT OPCODE
    BRA.B	STDTEXT_SHARE2                        | SHARE COMMON CODE
| ----------------------------------------------------------
|
| DV
|
DV:
    TST.B	D5                                    | IS DH = 0 ?
    BNE.B	STDTEXT_DHDV                          | NO, CONTINUE
    MOVEQ.L	#0x2A,D0                            | YES, PUT DVTEXT OPCODE
    BSR.B	STDTEXT_NOTSAME_NO_2                  | YES, PUT DVTEXT OPCODE
    BRA.B	SHARE1                                | SHARE COMMON CODE
| ----------------------------------------------------------
|
| STDTEXT_DHDV
|
STDTEXT_DHDV:
    MOVEQ.L	#0x2B,D0                            | PUT DHDVTEXT OPCODE
    BSR.B	STDTEXT_NOTSAME_NO_2                  | PUT DHDVTEXT OPCODE
    MOVE.B	D5,D0                                | PUT DH 0..255 TO PIC
    BSR.B	STDTEXT_NOTSAME_NO_2                  | PUT DH 0..255 TO PIC
SHARE1:
    SWAP.W	D5                                   | PUT DV IN LO WORD
STDTEXT_SHARE2:
    MOVE.B	D5,D0                                | SHARE2
    BSR.B	STDTEXT_NOTSAME_NO_2                  | PUT DH OR DV 0..255 TO PIC
TEXT2:
    MOVE.B	D6,D0                                | PUT COUNT BYTE TO PIC
    BSR.B	STDTEXT_NOTSAME_NO_2                  | PUT COUNT BYTE TO PIC
    MOVE.L	0x10(A6),-(A7)                       | PUSH ADDR OF TEXT
    MOVE.W	D6,-(A7)                             | PUSH COUNT
    JSR	PUTPICDATA(PC)                          | PUT TEXT DATA
    MOVEA.L	0x5C(A3),A4                         | GET PICSAVE HANDLE
    MOVEA.L	(A4),A4                             | DE-REFERENCE PICSAVE
    MOVE.L	0x30(A3),0x2C(A4)                    | UPDATE PICTXLOC STATE
|
| DrText(count,textAddr,numer,denom);
|
| Called during boot.
STDTEXT_NOTPIC:
    MOVE.W	D6,-(A7)                             | NOTPIC: PUSH COUNT
    MOVE.L	0x10(A6),-(A7)                       | PUSH TEXTADDR
    MOVE.L	0xC(A6),-(A7)                        | PUSH NUMER
    MOVE.L	0x8(A6),-(A7)                        | PUSH DENOM
    JSR	DRTEXT(PC)                              | DRAW THE TEXT
    SUB.W	D6,0x14(A6)                           | was count > 255 ?
    BLE.B	STDTEXT_GOHOME                        | no, quit
    MOVEA.L	0x10(A6),A0                         | yes, get old textaddr
    ADDA.W	D6,A0                                | offset for characters done
    MOVE.L	A0,0x10(A6)                          | update textAddr
    BRA.W	TXTLOOP                               | and loop for more
| ----------------------------------------------------------
|
| STDTEXT_GOHOME
|
| Called during boot.
STDTEXT_GOHOME:
    MOVEM.L	(A7)+,D5-D7/A3-A4                   | GOHOME: RESTORE REGS
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    ADDA.W	#0xE,A7                              | strip params
    JMP	(A0)                                    | tail-call return from STDTEXT_GOHOME via A0
| .PROC CallText,2
| .REF STDTEXT
| ---------------------------------------------------------------
|
| PROCEDURE CallText(count: INTEGER; textAddr: Ptr);
|
| Called during boot.
CALLTEXT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVE.L	#0x10001,-(A7)                       | PUSH NUMER = (1,1)
    MOVE.L	(A7),-(A7)                           | PUSH DENOM = (1,1)
    MOVE.L	A0,-(A7)                             | RESTORE RETURN ADDR
    MOVEA.L	(A5),A0                             | POINT TO QuickDraw GLOBALS
    MOVEA.L	(A0),A0                             | POINT TO THEPORT
    MOVE.L	0x68(A0),D0                          | IS GRAFPROCS NIL ?
    MOVEA.L	(0x1008).W,A0                       | _StdText (textProc)
    BEQ.B	CALLTEXT_USESTD                       | YES, USE STD PROC
    MOVEA.L	D0,A0                               | NO, GET PROC PTR
    MOVEA.L	(A0),A0                             | GET TEXTPROC
CALLTEXT_USESTD:
    JMP	(A0)                                    | USESTD: GO TO IT
| JPutPicLong
| .PROC TextFace,1
| .DEF DrawChar,CharWidth
| .REF CallText,TextWidth
| -------------------------------------------------------
|
| PROCEDURE TextFace(face: Style);
|
| Called during boot.
TEXTFACE:
    MOVEA.L	(A5),A0                             | POINT TO QuickDraw GLOBALS
    MOVEA.L	(A0),A0                             | POINT TO THEPORT
    MOVE.B	0x5(A7),0x46(A0)                     | INSTALL TXFACE
    BRA.B	CHARWIDTH_SHARE                       | STRIP PARAM AND RETURN
| ----------------------------------------------------
|
| PROCEDURE DrawChar(ch: CHAR);
|
| Called during boot.
DRAWCHAR:
    MOVE.W	#0x1,-(A7)                           | PUSH COUNT=1
    PEA.L	0x7(A7)                               | PUSH TEXTADDR
    JSR	CALLTEXT(PC)                            | CALL TEXT ROUTINE
    BRA.B	CHARWIDTH_SHARE                       | STRIP PARAM AND RETURN
| ---------------------------------------------
|
| FUNCTION CharWidth(ch: CHAR): INTEGER;
|
| Called during boot.
CHARWIDTH:
    CLR.W	-(A7)                                 | ROOM FOR FCN RESULT
    MOVE.L	A7,-(A7)                             | PUSH TEXTBUF
    MOVE.L	#0x10007,-(A7)                       | PUSH OFFSET = 7 & COUNT = 1
    JSR	TEXTWIDTH(PC)                           | CALL TEXTWIDTH
    MOVE.W	(A7)+,0x6(A7)                        | MOVE UP RESULT
CHARWIDTH_SHARE:
    MOVEA.L	(A7)+,A0                            | SHARE: POP RETURN ADDR
    ADDQ.W	#0x2,A7                              | STRIP CHAR PARAM
    JMP	(A0)                                    | AND RETURN
| .PROC TextFont,1
| .DEF TextSize
| .DEF TextMode
| .REF PortWord
| -------------------------------------------------------
|
| PROCEDURE TextFont(font: INTEGER);
|
| Called during boot.
TEXTFONT:
    MOVEQ.L	#0x44,D0                            | PUT PORT OFFSET IN D0
    BRA.B	TEXTSIZE_SHARE                        | SHARE COMMON CODE
| -------------------------------------------------------
|
| PROCEDURE TextMode(mode: INTEGER);
|
TEXTMODE:
    MOVEQ.L	#0x48,D0                            | PUT PORT OFFSET IN D0
    BRA.B	TEXTSIZE_SHARE                        | SHARE COMMON CODE
| -------------------------------------------------------
|
| PROCEDURE TextSize(mode: INTEGER);
|
| Called during boot.
TEXTSIZE:
    MOVEQ.L	#0x4A,D0                            | PUT PORT OFFSET IN D0
TEXTSIZE_SHARE:
    JMP	PORTWORD(PC)                            | INSTALL PARAM INTO THEPORT
| .PROC SpaceExtra,1
| .DEF DrawString,DrawText
| .REF CallText
| -------------------------------------------------------
|
| PROCEDURE SpaceExtra(extra: LongInt);
|
SPACEEXTRA:
    MOVEA.L	(A5),A0                             | POINT TO QuickDraw GLOBALS
    MOVEA.L	(A0),A0                             | POINT TO THEPORT
    MOVE.L	0x4(A7),0x4C(A0)                     | INSTALL FIXED POINT SPEXTRA
    BRA.B	DRAWTEXT_SHARE                        | STRIP PARAM AND RETURN
| ----------------------------------------------------
|
| PROCEDURE DrawString(s: Str255);
|
| Called during boot.
DRAWSTRING:
    MOVEA.L	0x4(A7),A0                          | POINT TO STRING
    CLR.W	D0                                    | GET READY FOR BYTE
    MOVE.B	(A0)+,D0                             | GET STRING LENGTH
    MOVE.W	D0,-(A7)                             | PUSH COUNT
    MOVE.L	A0,-(A7)                             | PUSH TEXTADDR
    JSR	CALLTEXT(PC)                            | CALL TEXT ROUTINE
    BRA.B	DRAWTEXT_SHARE                        | STRIP PARAM AND RETURN
| ----------------------------------------------------
|
| PROCEDURE DrawText(textBuf: WordPtr; start,count: INTEGER);
|
| Called during boot.
DRAWTEXT:
    MOVEA.L	0x8(A7),A0                          | POINT TO TEXTBUF
    ADDA.W	0x6(A7),A0                           | ADD STARTING OFFSET
    MOVE.W	0x4(A7),-(A7)                        | PUSH COUNT
    MOVE.L	A0,-(A7)                             | PUSH TEXTADDR
    JSR	CALLTEXT(PC)                            | CALL TEXT ROUTINE
    MOVE.L	(A7)+,(A7)                           | STRIP PARAMS
DRAWTEXT_SHARE:
    MOVE.L	(A7)+,(A7)                           | SHARE: STRIP PARAMS
    RTS                                         | AND RETURN
| .FUNC StringWidth,1
| .REF TextWidth
| ---------------------------------------------
|
| FUNCTION StringWidth(s: Str255): INTEGER;
|
| Called during boot (6,954 times in 30s trace).
STRINGWIDTH:
    MOVEA.L	(A7)+,A1                            | POP RETURN ADDR
    MOVEA.L	(A7)+,A0                            | POP ADDR OF STRING
    CLR.W	D0                                    | GET READY FOR BYTE
    MOVE.B	(A0)+,D0                             | GET UNSIGNED BYTE
    MOVE.L	A0,-(A7)                             | PUSH TEXTADDR
    CLR.W	-(A7)                                 | FIRSTBYTE := 0
    MOVE.W	D0,-(A7)                             | PUSH BYTECOUNT
    MOVE.L	A1,-(A7)                             | PUT BACK RETURN ADDR
|
| FALL THRU INTO TEXTWIDTH
|
| .FUNC TextWidth,3
| .REF StdTxMeas
| ------------------------------------------
|
| FUNCTION TEXTWIDTH(TEXTBUF: WordPtr; firstbyte,byteCount: INTEGER): INTEGER;
|
| Called during boot (6,985 times in 30s trace).
TEXTWIDTH:
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set RESULT, PARAMSIZE+8                        | FUNCTION RESULT
.set TEXTBUF, RESULT-4                          | LONG
.set FIRSTBYTE, TEXTBUF-2                       | WORD
.set BYTECOUNT, FIRSTBYTE-2                     | WORD
.set INFO, -8                                   | 4 WORDS
.set NUMER, INFO-4                              | POINT
.set DENOM, NUMER-4                             | POINT
.set VARSIZE, DENOM                             | TOTAL BYTES OF LOCALS
    LINK	A6,#-0x10                              | ALLOCATE STACK FRAME
    CLR.W	0x10(A6)                              | INIT RESULT TO 0
    CLR.W	-(A7)                                 | MAKE ROOM FOR FCN CALL BELOW
    MOVE.W	0x8(A6),-(A7)                        | PUSH BYTE COUNT
    BLE.B	TEXTWIDTH_DONE_EXIT                   | QUIT IF COUNT <= 0
| UNLK TAKES CARE OF SP
    MOVEA.L	0xC(A6),A0                          | GET ADDR OF BUFFER
    ADDA.W	0xA(A6),A0                           | ADD STARTING INDEX
    MOVE.L	A0,-(A7)                             | PUSH TEXTADDR
    MOVE.L	#0x10001,D0                          | get 1,1 for numer and denom
    MOVE.L	D0,-0xC(A6)                          | NUMER := (1,1)
    MOVE.L	D0,-0x10(A6)                         | DENOM := (1,1)
    PEA.L	-0xC(A6)                              | PUSH VAR NUMER
    PEA.L	-0x10(A6)                             | PUSH VAR DENOM
    PEA.L	-0x8(A6)                              | PUSH VAR INFO
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    MOVE.L	0x68(A0),D0                          | IS GRAFPROCS NIL ?
    MOVEA.L	(0x11B4).W,A0                       | _StdTxMeas (txMeasProc)
    BEQ.B	STD                                   | YES, USE STDTXMEAS
    MOVEA.L	D0,A0                               | NO, GET GRAFPROCS
    MOVEA.L	0x28(A0),A0                         | GET TXMEAS CAPTURE PROC
STD:
    JSR	(A0)                                    | CALL IT
    MOVE.W	(A7)+,D1                             | NOTSTD: POP UNSCALED WIDTH
    MOVE.W	-0xA(A6),D0                          | get numer
    MOVE.W	-0xE(A6),D2                          | get denom
    CMP.W	D2,D0                                 | is numer same as denom ?
    BEQ.B	TEXTWIDTH_DONE                        | yes, skip muldiv
    MULU.W	D0,D1                                | MUL BY NUMER
    DIVU.W	D2,D1                                | DIV BY DENOM
TEXTWIDTH_DONE:
    MOVE.W	D1,0x10(A6)                          | RETURN SCALED WIDTH
TEXTWIDTH_DONE_EXIT:
    UNLK	A6                                     | RESTORE STACK POINTER
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    ADDQ.W	#0x8,A7                              | STRIP PARAMS
    JMP	(A0)                                    | RETURN TO CALLER
| .FUNC StdTxMeas,5
| ------------------------------------------
|
| FUNCTION StdTxMeas(count: INTEGER; textAddr: Ptr;
|                    VAR numer,denom: Point;
|                    VAR info: FontInfo): INTEGER;
|
| Measure some text, returning unscaled values plus updated scale factor.
| Fills info record with unscaled ascent, descent, widMax, and leading,
| and returns unscaled integer width as the function value.
|
| Also leaves unscaled fixed point width in QD global 'fixTxWid'
| and stashes FMOutPtr in QD global 'fontPtr' for DrawText.
|
| Called during boot (37,171 times in 30s trace).
STDTXMEAS:
.set PARAMSIZE, 18                              | TOTAL BYTES OF PARAMS
.set RESULT, PARAMSIZE+8                        | FCN RESULT IS A WORD
.set COUNT, RESULT-2                            | WORD
.set TEXTADDR, COUNT-4                          | LONG
.set NUMER, TEXTADDR-4                          | LONG, VAR ADDR
.set DENOM, NUMER-4                             | LONG, VAR ADDR
.set INFO, DENOM-4                              | LONG, ADDR OF FONTINFO
.set INREC, -16                                 | FMInput record
.set VARSIZE, INREC                             | TOTAL SIZE OF LOCAL VARS
    LINK	A6,#-0x10                              | ALLOCATE LOCALS
    MOVE.L	A4,-(A7)                             | SAVE REG
    MOVEA.L	(A5),A4                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A4),A0                             | GET CURRENT GRAFPORT
    LEA.L	-0x10(A6),A1                          | POINT TO FMINPUT RECORD
    MOVE.W	0x44(A0),(A1)+                       | GET TXFONT FROM THEPORT
    MOVE.W	0x4A(A0),(A1)+                       | GET TXSIZE FROM THEPORT
    MOVE.B	0x46(A0),(A1)+                       | GET TXFACE FROM THEPORT
    ST.B	(A1)+                                  | ALWAYS SET NEEDBITS TRUE
    MOVE.W	(A0),(A1)+                           | GET DEVICE FROM THEPORT
    MOVEA.L	0x10(A6),A0                         | POINT TO NUMER
    MOVE.L	(A0),(A1)+                           | INSTALL INPUT NUMER
    MOVEA.L	0xC(A6),A0                          | POINT TO DENOM
    MOVE.L	(A0),(A1)+                           | INSTALL INPUT DENOM
    CLR.L	-(A7)                                 | ROOM FOR FCN RESULT
    PEA.L	-0x10(A6)                             | PUSH INPUT RECORD
    MOVEA.L	(JSwapFont).W,A0                    | get address of _SwapFont
    JSR	(A0)                                    | CALL FMSWAPFONT
    MOVEA.L	(A7)+,A1                            | POP FMOUTPUT POINTER
    MOVE.L	A1,-0xB0(A4)                         | STASH FMOUTPTR FOR LATER (FONTPTR)
    MOVEA.L	0x8(A6),A0                          | POINT TO VAR INFO RECORD
    CLR.L	(A0)                                  | INIT TO (0,0,0,0)
    CLR.L	0x4(A0)                               | ALL 4 WORDS
    MOVE.B	0xD(A1),0x1(A0)                      | FILL IN UNSIGNED ASCENT
    MOVE.B	0xE(A1),0x3(A0)                      | FILL IN UNSIGNED DESCENT
    MOVE.B	0xF(A1),0x5(A0)                      | FILL IN UNSIGNED WIDMAX
    MOVE.B	0x10(A1),D0                          | GET SIGNED LEADING
    EXT.W	D0                                    | SIGN EXTEND TO WORD
    MOVE.W	D0,0x6(A0)                           | FILL IN LEADING
|
| UPDATE NUMER AND DENOM
|
    MOVEA.L	0x10(A6),A0                         | GET VAR ADDR
    MOVE.L	0x12(A1),(A0)                        | UPDATE NUMER
    MOVEA.L	0xC(A6),A0                          | GET VAR ADDR
    MOVE.L	0x16(A1),(A0)                        | UPDATE DENOM
    MOVEA.L	0x14(A6),A0                         | POINT TO CHARACTERS
    MOVEA.L	(WidthPtr).W,A1                     | POINT TO WIDTH TABLE
    MOVEQ.L	#0x0,D1                             | INIT WIDTH TO 0.0
    MOVE.W	0x18(A6),D2                          | GET CHARACTER COUNT
    BRA.B	STDTXMEAS_MORE                        | GO TO LOOP START
| ----------------------------------------------------------
|
| STDTXMEAS_NEXTCH
|
| Called during boot (62,735 times in 30s trace).
STDTXMEAS_NEXTCH:
    CLR.W	D0                                    | NEXTCH: GET READY FOR BYTE
    MOVE.B	(A0)+,D0                             | GET A CHARACTER
    LSL.W	#0x2,D0                               | QUAD FOR TABLE OFFSET
    ADD.L	0x0(A1,D0.W),D1                       | ADD FIXED POINT WIDTH
STDTXMEAS_MORE:
    DBF.W	D2,STDTXMEAS_NEXTCH                   | LOOP FOR ALL CHARS
    MOVE.L	D1,-0xAC(A4)                         | STASH FIXED POINT WIDTH (FIXTXWID)
    SWAP.W	D1                                   | GET HI WORD = INTEGER PORTION
    MOVE.W	D1,0x1A(A6)                          | UPDATE FUNCTION RESULT
    MOVEA.L	(A7)+,A4                            | RESTORE REG
    UNLK	A6                                     | RESTORE STACK POINTER
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    ADDA.W	#0x12,A7                             | STRIP PARAMS
    JMP	(A0)                                    | RETURN TO CALLER
| .PROC MeasureText
| --------------------------------------------------------------------
|
| PROCEDURE MeasureText(count: INTEGER; textAddr,charLocs: Ptr);
|
| Measure some text, returning (scaled) screen widths in charLocs.
| Charlocs points to an array of count+1 integers.
|
| The SE FDHD version takes the custom-grafProc fast path if the port has
| a non-nil grafProcs and the txMeasProc has been overridden -- it calls
| the grafProcs txMeasProc once per character via TextWidth, accumulating
| screen positions as it goes.  Otherwise it falls through to the inline
| FMSwapFont path: walk the width table, then optionally rescale each
| stored width by numer.h/denom.h.
|
| PARAMSIZE .EQU 10
| COUNT .EQU PARAMSIZE+8-2 ;WORD
| TEXTADDR .EQU COUNT-4 ;LONG, Ptr to ASCII
| CHARLOCS .EQU TEXTADDR-4 ;LONG, Ptr to output array
MEASURETEXT:
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set COUNT, PARAMSIZE+8-2                       | WORD
.set TEXTADDR, COUNT-4                          | LONG, Ptr to ASCII
.set CHARLOCS, TEXTADDR-4                       | LONG, Ptr to output array
.set INREC, -16                                 | FMInput record
.set VARSIZE, INREC                             | TOTAL SIZE OF LOCAL VARS
    LINK	A6,#-0x10                              | ALLOCATE LOCALS
    MOVEM.L	D3-D6/A2-A4,-(A7)                   | SAVE REGS
    MOVEA.L	0xC(A6),A2                          | POINT TO TEXTADDR
    MOVEA.L	0x8(A6),A3                          | POINT TO CHARLOCS
    MOVE.W	0x10(A6),D3                          | GET CHARACTER COUNT
    MOVEQ.L	#0x0,D4                             | CURRENT BYTE OFFSET = 0
    MOVEA.L	(A5),A4                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A4),A0                             | GET CURRENT GRAFPORT
    MOVE.L	0x68(A0),D0                          | GRAFPROCS NIL ?
    BEQ.B	MEASURETEXT_USESTD                    | YES, USE STD INLINE PATH
    MOVEA.L	D0,A1                               | NO, GRAB GRAFPROCS PTR
    MOVE.L	0x28(A1),D0                          | GET TXMEASPROC
    CMP.L	(0x11B4).W,D0                         | == _StdTxMeas ?
    BEQ.B	MEASURETEXT_USESTD                    | YES, USE STD INLINE PATH
    MOVEQ.L	#0x0,D6                             | LAST WIDTH = 0
    MOVEQ.L	#0x0,D5                             | RUNNING X = 0
    SUBQ.W	#0x2,A7                              | RESERVE FCN RESULT WORD
MEASURETEXT_CUSTOM_LOOP:
    MOVE.L	A2,-(A7)                             | PUSH TEXTADDR
    CLR.W	-(A7)                                 | FIRSTBYTE := 0
    MOVE.W	D4,-(A7)                             | PUSH PARTIAL COUNT
    JSR	TEXTWIDTH(PC)                           | call grafProcs.txMeasProc via TEXTWIDTH
    MOVE.W	(A7),D0                              | get width back
    CMP.W	D6,D0                                 | did width go down ?
    BGE.B	MEASURETEXT_CUSTOM_STORE              | no, store as-is
    ADD.W	D6,D5                                 | yes, advance baseline (line wrap)
MEASURETEXT_CUSTOM_STORE:
    ADD.W	D5,D0                                 | offset by accumulated baseline
    MOVE.W	D0,(A3)+                             | store charLocs[i]
    MOVE.W	(A7),D6                              | remember last width
    ADDQ.W	#0x1,D4                              | next character
    CMP.W	D3,D4                                 | done count chars ?
    BLE.B	MEASURETEXT_CUSTOM_LOOP               | no, loop
    ADDQ.W	#0x2,A7                              | release fcn result word
    BRA.B	NEXTCH2_SKIP                          | jump to common exit
| -- USESTD: inline FMSwapFont + width-table walk -----------------
MEASURETEXT_USESTD:
    LEA.L	-0x10(A6),A1                          | POINT TO FMINPUT RECORD
    MOVE.W	0x44(A0),(A1)+                       | GET TXFONT FROM THEPORT
    MOVE.W	0x4A(A0),(A1)+                       | GET TXSIZE FROM THEPORT
    MOVE.B	0x46(A0),(A1)+                       | GET TXFACE FROM THEPORT
    ST.B	(A1)+                                  | ALWAYS SET NEEDBITS TRUE
    MOVE.W	(A0),(A1)+                           | GET DEVICE FROM THEPORT
    MOVE.L	#0x10001,(A1)+                       | INSTALL INPUT NUMER = 1,1
    MOVE.L	#0x10001,(A1)+                       | INSTALL INPUT DENOM = 1,1
    CLR.L	-(A7)                                 | ROOM FOR FCN RESULT
    PEA.L	-0x10(A6)                             | PUSH INPUT RECORD
    MOVEA.L	(JSwapFont).W,A0                    | get address of _SwapFont
    JSR	(A0)                                    | CALL FMSWAPFONT
    MOVEA.L	(WidthPtr).W,A1                     | POINT TO WIDTH TABLE
MEASURETEXT_NEXTCH:
    SWAP.W	D4                                   | NEXTCH: GET HI WORD OF WIDTH
    MOVE.W	D4,(A3)+                             | STORE IN CHARLOCS
    SWAP.W	D4                                   | RETURN WIDTH TO FIXED POINT
    CLR.W	D0                                    | GET READY FOR BYTE
    MOVE.B	(A2)+,D0                             | GET A CHARACTER
    LSL.W	#0x2,D0                               | QUAD FOR TABLE OFFSET
    ADD.L	0x0(A1,D0.W),D4                       | ADD FIXED POINT WIDTH
    DBF.W	D3,MEASURETEXT_NEXTCH                 | LOOP FOR COUNT+1 CHARLOCS
    MOVEA.L	(A7)+,A0                            | POP FMOUTPUT POINTER
    MOVE.W	0x14(A0),D3                          | GET NUMER.H
    MOVE.W	0x18(A0),D4                          | GET DENOM.H
    CMP.W	D3,D4                                 | IS NUMER.H = DENOM.H ?
    BEQ.B	NEXTCH2_SKIP                          | YES, SKIP SCALING
    MOVEA.L	0x8(A6),A2                          | NO, POINT TO CHARLOCS
    MOVE.W	0x10(A6),D2                          | GET CHARACTER COUNT
NEXTCH2:
    MOVE.W	(A2),D0                              | GET CHARLOC
    MULU.W	D3,D0                                | MUL BY NUMER
    DIVU.W	D4,D0                                | DIV BY DENOM
    MOVE.W	D0,(A2)+                             | UPDATE CHARLOC
    DBF.W	D2,NEXTCH2                            | LOOP FOR COUNT+1 CHARLOCS
NEXTCH2_SKIP:
    MOVEM.L	(A7)+,D3-D6/A2-A4                   | RESTORE REGS
    UNLK	A6                                     | RESTORE STACK POINTER
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    ADDA.W	#0xA,A7                              | STRIP PARAMS
    JMP	(A0)                                    | RETURN TO CALLER
| .PROC GetFontInfo,1
| .REF StdTxMeas
| ------------------------------------------
|
| PROCEDURE GetFontInfo(VAR info: FontInfo);
|
| Calls StdTxMeas thru capture proc, then adjusts and scales the result.
|
| 13 MAY 85, changed so that all 4 values round UP in the case of scaling.
|
| Called during boot (30,141 times in 30s trace).
GETFONTINFO:
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set INFO, PARAMSIZE+8-4                        | LONG, ADDR OF INFO
.set NUMER, -4                                  | POINT
.set DENOM, NUMER-4                             | POINT
.set VARSIZE, DENOM                             | TOTAL LOCALS
    LINK	A6,#-0x8                               | ALLOCATE LOCALS
    MOVE.L	#0x10001,-0x4(A6)                    | NUMER := (1,1)
    MOVE.L	#0x10001,-0x8(A6)                    | DENOM := (1,1)
    CLR.L	-(A7)                                 | ROOM FOR FCN, COUNT = 0
    CLR.L	-(A7)                                 | TEXTADDR := NIL
    PEA.L	-0x4(A6)                              | PUSH VAR NUMER
    PEA.L	-0x8(A6)                              | PUSH VAR DENOM
    MOVE.L	0x8(A6),-(A7)                        | PUSH VAR INFO
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    MOVE.L	0x68(A0),D0                          | IS GRAFPROCS NIL ?
    MOVEA.L	(0x11B4).W,A0                       | _StdTxMeas (txMeasProc)
    BEQ.B	GETFONTINFO_USESTD                    | YES, USE STD PROC
    MOVEA.L	D0,A0                               | NO, GET GRAFPROCS
    MOVEA.L	0x28(A0),A0                         | NO, GET TXMEAS CAPTURE PROC
GETFONTINFO_USESTD:
    JSR	(A0)                                    | USESTD: CALL IT
    TST.W	(A7)+                                 | DISCARD WIDTH FCN RSLT
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
|
| ADJUST WIDMAX FOR EXTRA
|
    MOVEA.L	-0xB0(A0),A0                        | GET FMOUTPUT RECORD (FONTPTR)
    MOVEA.L	0x8(A6),A1                          | POINT TO RESULT INFO
    MOVE.B	0xC(A0),D0                           | GET SIGNED EXTRA
    EXT.W	D0                                    | EXTEND TO WORD
    ADD.W	D0,0x4(A1)                            | ADD TO WIDMAX
|
| ADJUST ASCENT & DESCENT FOR SHADOW
|
    CLR.W	D0                                    | GET READY FOR BYTE
    MOVE.B	0xB(A0),D0                           | GET SHADOW COUNT
    BEQ.B	GETFONTINFO_USESTD_SKIP               | SKIP IF ZERO
    ADDQ.W	#0x1,(A1)                            | ADJUST ASCENT
    ADD.W	D0,0x2(A1)                            | ADJUST DESCENT
| NOTSHAD
|
| SCALE RESULT IF NUMER <> DENOM
|
| Called during boot (30,141 times in 30s trace).
GETFONTINFO_USESTD_SKIP:
    MOVE.L	-0x4(A6),D0                          | GET NUMER
    CMP.L	-0x8(A6),D0                           | IS NUMER SAME AS DENOM ?
    BEQ.B	GETFONTINFO_USESTD_SKIP_2             | YES, SKIP SCALING
    BSR.B	SCALE                                 | SCALE ASCENT
    BSR.B	SCALE                                 | SCALE DESCENT
    MOVE.W	(A1),D0                              | GET MAXWID
    MULU.W	-0x2(A6),D0                          | SCALE MAXWID
    MOVE.W	-0x6(A6),D1                          | get denom
    LSR.W	#0x1,D1                               | calc denom div 2
    EXT.L	D1                                    | extend to long
    ADD.L	D1,D0                                 | add denom-1 to round up
    DIVU.W	-0x6(A6),D0                          | divide by denom
    MOVE.W	D0,(A1)+                             | UPDATE MAXWID
    BSR.B	SCALE                                 | SCALE LEADING
GETFONTINFO_USESTD_SKIP_2:
    UNLK	A6                                     | RESTORE STACK POINTER
    MOVE.L	(A7)+,(A7)                           | STRIP PARAMS
    RTS                                         | AND RETURN
| SCALE -- sCALE ASCENT.
| ----------------------------------------------------------
|
| SCALE: scale (A1) by NUMER/DENOM, rounding up; advance A1 by 2.
|
SCALE:
    MOVE.W	(A1),D0                              | GET IT
    MULU.W	-0x4(A6),D0                          | SCALE IT
    MOVE.W	-0x8(A6),D1                          | get denom
    LSR.W	#0x1,D1                               | calc denom div 2
    EXT.L	D1                                    | extend to long
    ADD.L	D1,D0                                 | add denom-1 to round up
    DIVU.W	-0x8(A6),D0                          | divide by denom
    MOVE.W	D0,(A1)+                             | UPDATE IT
    RTS                                         | AND RETURN
