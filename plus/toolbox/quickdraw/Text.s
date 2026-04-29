|---------------------------------------------------------
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
|

| .PROC StdText,4
| .REF CheckPic,DPutPicByte,PutPicData,PutPicWord,PutPicLong
| .REF DrText
| --------------------------------------------------------------------------
|
| PROCEDURE StdText(count: INTEGER; textAddr: Ptr; numer,denom: Point);
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| Called during boot.
StdText:
        LINK    A6,#-0x4                        | ALLOCATE STACK FRAME
| -------------------------------------------
|
| KERNED STRIKE FONT FORMAT OFFSETS:
|
| FORMAT .EQU 0 ;WORD
| MINCHAR .EQU 2 ;WORD
| MAXCHAR .EQU 4 ;WORD
| MAXWD .EQU 6 ;WORD
| FBBOX .EQU 8 ;WORD
| FBBOY .EQU 10 ;WORD
| FBBDX .EQU 12 ;WORD
| FBBDY .EQU 14 ;WORD
| LENGTH .EQU 16 ;WORD
| ASCENT .EQU 18 ;WORD
| DESCENT .EQU 20 ;WORD
| XOFFSET .EQU 22 ;WORD
| RASTER .EQU 24 ;WORD
.set PARAMSIZE, 14                              | TOTAL BYTES OF PARAMS
.set COUNT, PARAMSIZE+8-2                       | WORD
.set TEXTADDR, COUNT-4                          | LONG
.set NUMER, TEXTADDR-4                          | POINT
.set DENOM, NUMER-4                             | POINT

.set TXLOC, -4                                  | POINT
.set VARSIZE, TXLOC                             | TOTAL LOCALS

        MOVEM.L D5-D7/A3-A4,-(SP)               | SAVE REGS
TXTLOOP:
        MOVE    0x14(A6),D6                     | GET CHARACTER COUNT
        BLE     STDTEXT_GOHOME                  | QUIT IF COUNT <= 0
        CMPI    #0xFF,D6                        | is count > 255 ?
        BLE.B   COUNTOK                         | no, continue
        MOVE    #255,D6                         | yes, pin at 255
COUNTOK:
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE     STDTEXT_NOTPIC                  | no pic, branch to draw text
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE

|
| CHECK TXFONT
|
        MOVE    TXFONT(A3),D7                   | GET THEPORT^.TXFONT
        CMP     PICTXFONT(A4),D7                | HAS IT CHANGED ?
        BEQ.B   FONTOK                          | NO, CONTINUE
        MOVEQ   #3,D0                           | YES, PUSH TXFONT PARAM OPCODE
        JSR     DPutPicByte(PC)                 | PUT OPCODE
        MOVE    D7,-(SP)                        | push txFont to save in pic
        JSR     PutPicWord(PC)                  | PUT TXFONT PARAM
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE    D7,PICTXFONT(A4)                | UPDATE CURRENT STATE

|
| CHECK TXFACE
|
FONTOK:
        MOVE.B  TXFACE(A3),D7                   | GET THEPORT^.TXFACE
        CMP.B   PICTXFACE(A4),D7                | HAS IT CHANGED ?
        BEQ.B   FACEOK                          | NO, CONTINUE
        MOVEQ   #4,D0                           | YES, PUSH TXFACE PARAM OPCODE
        JSR     DPutPicByte(PC)                 | PUT OPCODE
        MOVE.B  D7,D0                           | copy txFace for pic
        JSR     DPutPicByte(PC)                 | PUT TXFACE PARAM
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.B  D7,PICTXFACE(A4)                | UPDATE CURRENT STATE

|
| CHECK TXMODE
|
FACEOK:
        MOVE    TXMODE(A3),D7                   | GET THEPORT^.TXMODE
        CMP     PICTXMODE(A4),D7                | HAS IT CHANGED ?
        BEQ.B   STDTEXT_MODEOK                  | NO, CONTINUE
        MOVEQ   #5,D0                           | YES, PUSH TXMODE PARAM OPCODE
        JSR     DPutPicByte(PC)                 | PUT OPCODE
        MOVE    D7,-(SP)                        | push txMode to save in pic
        JSR     PutPicWord(PC)                  | PUT TXMODE PARAM
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE    D7,PICTXMODE(A4)                | UPDATE CURRENT STATE

|
| CHECK TXSIZE
|
STDTEXT_MODEOK:
        MOVE    TXSIZE(A3),D7                   | MODEOK: GET THEPORT^.TXSIZE
        CMP     PICTXSIZE(A4),D7                | HAS IT CHANGED ?
        BEQ.B   STDTEXT_SIZEOK                  | NO, CONTINUE
        MOVEQ.L #0xD,D0                         | YES, PUSH TXSIZE PARAM OPCODE
        BSR.B   STDTEXT_NOTSAME_NO_2            | PUT OPCODE
        MOVE    D7,-(SP)                        | push txSize param
        JSR     PutPicWord(PC)                  | PUT TXSIZE PARAM
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE    D7,PICTXSIZE(A4)                | UPDATE CURRENT STATE

|
| CHECK SPEXTRA
|
STDTEXT_SIZEOK:
        MOVE.L  SPEXTRA(A3),D7                  | SIZEOK: GET THEPORT^.SPEXTRA
        CMP.L   PICSPEXTRA(A4),D7               | HAS IT CHANGED ?
        BEQ.B   SPOK                            | NO, CONTINUE
        MOVEQ   #6,D0                           | YES, PUSH SPEXTRA PARAM OPCODE
        BSR.B   STDTEXT_NOTSAME_NO_2            | PUT OPCODE
        MOVE.L  D7,-(SP)                        | push spExtra param
        BSR.B   STDTEXT_NOTSAME_CONT            | PUT SPEXTRA PARAM
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D7,PICSPEXTRA(A4)               | UPDATE CURRENT STATE

|
| CHECK NUMER, DENOM
|
SPOK:
        MOVE.L  0xC(A6),D7                      | GET NUMER
        MOVE.L  0x8(A6),D5                      | GET DENOM

|
| CHECK NUMER, DENOM
|
        CMP.L   PICTXNUMER(A4),D7               | HAS IT CHANGED ?
        BNE.B   STDTEXT_NOTSAME                 | YES, RECORD CHANGE
        CMP.L   PICTXDENOM(A4),D5               | HAS IT CHANGED ?
        BEQ.B   STDTEXT_NOTSAME_NO              | NO, CONTINUE
STDTEXT_NOTSAME:
        MOVEQ.L #0x10,D0                        | YES, PUSH TXRATIO OPCODE
        BSR.B   STDTEXT_NOTSAME_NO_2            | PUT OPCODE
        MOVE.L  D7,-(SP)                        | push numer param
        BSR.B   STDTEXT_NOTSAME_CONT            | PUT NUMER
        MOVE.L  D5,-(SP)                        | push denom param
        BSR.B   STDTEXT_NOTSAME_CONT            | PUT DENOM
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D7,PICTXNUMER(A4)               | UPDATE CURRENT STATE
        MOVE.L  D5,PICTXDENOM(A4)               | UPDATE CURRENT STATE

| NUMEROK

| -------------------------------------------------------------
|
| USE DH AND DV TO CHOOSE ONE OF FOUR TEXT OPCODES.
|
STDTEXT_NOTSAME_NO:
        MOVE.L  PNLOC(A3),D5                    | GET CURRENT PNLOC
        SUB.L   PICTXLOC(A4),D5                 | CALC DV.DH
        MOVE.L  D5,D0                           | COPY DV.DH
        ANDI.L  #0xFF00FF00,D0                  | ARE DH AND DV BOTH 0..255 ?
        BEQ.B   SHORT                           | YES, USE SHORT FORM
        MOVEQ.L #0x28,D0                        | NO, PUT LONGTEXT OPCODE
        BSR.B   STDTEXT_NOTSAME_NO_2            | NO, PUT LONGTEXT OPCODE
        MOVE.L  PNLOC(A3),-(SP)                 | push pnLoc 4 bytes
        BSR.B   STDTEXT_NOTSAME_CONT            | PUT PNLOC 4 BYTES
        BRA.B   TEXT2                           | AND CONTINUE

| STDTEXT_NOTSAME_NO_2 -- pUT OPCODE.
| JDPutPicByte
STDTEXT_NOTSAME_NO_2:
        JMP     DPutPicByte(PC)                 | go to DPutPicByte

| ----------------------------------------------------------
|
| STDTEXT_NOTSAME_CONT
|
STDTEXT_NOTSAME_CONT:
        JMP     PutPicLong(PC)                  | go to PutPicLong

| ----------------------------------------------------------
|
| SHORT
|
SHORT:
        MOVE.L  D5,D0                           | YES, COPY DV.DH
        ANDI.L  #0xFF0000,D0                    | IS DV = 0 ?
        BNE.B   DV                              | NO, CONTINUE
        MOVEQ.L #0x29,D0                        | YES, PUT DHTEXT OPCODE
        BSR.B   STDTEXT_NOTSAME_NO_2            | YES, PUT DHTEXT OPCODE
        BRA.B   STDTEXT_SHARE2                  | SHARE COMMON CODE

| ----------------------------------------------------------
|
| DV
|
DV:
        TST.B   D5                              | IS DH = 0 ?
        BNE.B   STDTEXT_DHDV                    | NO, CONTINUE
        MOVEQ.L #0x2A,D0                        | YES, PUT DVTEXT OPCODE
        BSR.B   STDTEXT_NOTSAME_NO_2            | YES, PUT DVTEXT OPCODE
        BRA.B   SHARE1                          | SHARE COMMON CODE

| ----------------------------------------------------------
|
| STDTEXT_DHDV
|
STDTEXT_DHDV:
        MOVEQ.L #0x2B,D0                        | PUT DHDVTEXT OPCODE
        BSR.B   STDTEXT_NOTSAME_NO_2            | PUT DHDVTEXT OPCODE
        MOVE.B  D5,D0                           | PUT DH 0..255 TO PIC
        BSR.B   STDTEXT_NOTSAME_NO_2            | PUT DH 0..255 TO PIC
SHARE1:
        SWAP    D5                              | PUT DV IN LO WORD
STDTEXT_SHARE2:
        MOVE.B  D5,D0                           | SHARE2
        BSR.B   STDTEXT_NOTSAME_NO_2            | PUT DH OR DV 0..255 TO PIC
TEXT2:
        MOVE.B  D6,D0                           | PUT COUNT BYTE TO PIC
        BSR.B   STDTEXT_NOTSAME_NO_2            | PUT COUNT BYTE TO PIC
        MOVE.L  0x10(A6),-(SP)                  | PUSH ADDR OF TEXT
        MOVE    D6,-(SP)                        | PUSH COUNT
        JSR     PutPicData(PC)                  | PUT TEXT DATA
        MOVE.L  PICSAVE(A3),A4                  | GET PICSAVE HANDLE
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  PNLOC(A3),PICTXLOC(A4)          | UPDATE PICTXLOC STATE

|
| DrText(count,textAddr,numer,denom);
|
| Called during boot.
STDTEXT_NOTPIC:
        MOVE    D6,-(SP)                        | NOTPIC: PUSH COUNT
        MOVE.L  0x10(A6),-(SP)                  | PUSH TEXTADDR
        MOVE.L  0xC(A6),-(SP)                   | PUSH NUMER
        MOVE.L  0x8(A6),-(SP)                   | PUSH DENOM
        JSR     DrText(PC)                      | DRAW THE TEXT
        SUB     D6,0x14(A6)                     | was count > 255 ?
        BLE.B   STDTEXT_GOHOME                  | no, quit
        MOVE.L  0x10(A6),A0                     | yes, get old textaddr
        ADD     D6,A0                           | offset for characters done
        MOVE.L  A0,0x10(A6)                     | update textAddr
        BRA     TXTLOOP                         | and loop for more

| ----------------------------------------------------------
|
| STDTEXT_GOHOME
|
| Called during boot.
STDTEXT_GOHOME:
        MOVEM.L (SP)+,D5-D7/A3-A4               | GOHOME: RESTORE REGS
        UNLK    A6                              | release stack frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA    #0xE,SP                         | strip params
        JMP     (A0)                            | return to caller

| .PROC CallText,2
| .REF STDTEXT
| ---------------------------------------------------------------
|
| PROCEDURE CallText(count: INTEGER; textAddr: Ptr);
|
| Called during boot.
CallText:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  #0x10001,-(SP)                  | PUSH NUMER = (1,1)
        MOVE.L  (SP),-(SP)                      | PUSH DENOM = (1,1)
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QuickDraw GLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xE08).w,A0                    | _StdText (textProc)
        BEQ.B   CALLTEXT_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | NO, GET PROC PTR
        MOVE.L  (A0),A0                         | GET TEXTPROC
CALLTEXT_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| JPutPicLong
| .PROC TextFace,1
| .DEF DrawChar,CharWidth
| .REF CallText,TextWidth
| -------------------------------------------------------
|
| PROCEDURE TextFace(face: Style);
|
| Called during boot.
TextFace:
        MOVE.L  (A5),A0                         | POINT TO QuickDraw GLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE.B  0x5(SP),TXFACE(A0)              | INSTALL TXFACE
        BRA.B   CHARWIDTH_SHARE                 | STRIP PARAM AND RETURN

| ----------------------------------------------------
|
| PROCEDURE DrawChar(ch: CHAR);
|
| Called during boot.
DrawChar:
        MOVE    #1,-(SP)                        | PUSH COUNT=1
        PEA.L   0x7(SP)                         | PUSH TEXTADDR
        JSR     CallText(PC)                    | CALL TEXT ROUTINE
        BRA.B   CHARWIDTH_SHARE                 | STRIP PARAM AND RETURN

| ---------------------------------------------
|
| FUNCTION CharWidth(ch: CHAR): INTEGER;
|
| Called during boot.
CharWidth:
        CLR     -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  SP,-(SP)                        | PUSH TEXTBUF
        MOVE.L  #0x10007,-(SP)                  | PUSH OFFSET = 7 & COUNT = 1
        JSR     TextWidth(PC)                   | CALL TEXTWIDTH
        MOVE    (SP)+,0x6(SP)                   | MOVE UP RESULT
CHARWIDTH_SHARE:
        MOVE.L  (SP)+,A0                        | SHARE: POP RETURN ADDR
        ADDQ.W  #0x2,SP                         | STRIP CHAR PARAM
        JMP     (A0)                            | AND RETURN

| .PROC TextFont,1
| .DEF TextSize
| .DEF TextMode
| .REF PortWord
| -------------------------------------------------------
|
| PROCEDURE TextFont(font: INTEGER);
|
| Called during boot.
TextFont:
        MOVEQ.L #0x44,D0                        | PUT PORT OFFSET IN D0
        BRA.B   TEXTSIZE_SHARE                  | SHARE COMMON CODE

| -------------------------------------------------------
|
| PROCEDURE TextMode(mode: INTEGER);
|
TextMode:
        MOVEQ.L #0x48,D0                        | PUT PORT OFFSET IN D0
        BRA.B   TEXTSIZE_SHARE                  | SHARE COMMON CODE

| -------------------------------------------------------
|
| PROCEDURE TextSize(mode: INTEGER);
|
| Called during boot.
TextSize:
        MOVEQ.L #0x4A,D0                        | PUT PORT OFFSET IN D0
TEXTSIZE_SHARE:
        JMP     L_mPortWord(PC)                 | INSTALL PARAM INTO THEPORT

| .PROC SpaceExtra,1
| .DEF DrawString,DrawText
| .REF CallText
| -------------------------------------------------------
|
| PROCEDURE SpaceExtra(extra: LongInt);
|
SpaceExtra:
        MOVE.L  (A5),A0                         | POINT TO QuickDraw GLOBALS
        MOVE.L  (A0),A0                         | POINT TO THEPORT
        MOVE.L  0x4(SP),SPEXTRA(A0)             | INSTALL FIXED POINT SPEXTRA
        BRA.B   DRAWTEXT_SHARE                  | STRIP PARAM AND RETURN

| ----------------------------------------------------
|
| PROCEDURE DrawString(s: Str255);
|
| Called during boot.
DrawString:
        MOVE.L  0x4(SP),A0                      | POINT TO STRING

| ----------------------------------------------------
|
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  (A0)+,D0                        | GET STRING LENGTH
        MOVE    D0,-(SP)                        | PUSH COUNT
        MOVE.L  A0,-(SP)                        | PUSH TEXTADDR
        JSR     CallText(PC)                    | CALL TEXT ROUTINE
        BRA.B   DRAWTEXT_SHARE                  | STRIP PARAM AND RETURN

| ----------------------------------------------------
|
| PROCEDURE DrawText(textBuf: WordPtr; start,count: INTEGER);
|
| Called during boot.
DrawText:
        MOVE.L  0x8(SP),A0                      | POINT TO TEXTBUF
        ADDA    0x6(SP),A0                      | ADD STARTING OFFSET
        MOVE    0x4(SP),-(SP)                   | PUSH COUNT

| ----------------------------------------------------
|
        MOVE.L  A0,-(SP)                        | PUSH TEXTADDR
        JSR     CallText(PC)                    | CALL TEXT ROUTINE
        MOVE.L  (SP)+,(SP)                      | STRIP PARAMS
DRAWTEXT_SHARE:
        MOVE.L  (SP)+,(SP)                      | SHARE: STRIP PARAMS
        RTS                                     | AND RETURN

| .FUNC StringWidth,1
| .REF TextWidth
| ---------------------------------------------
|
| FUNCTION StringWidth(s: Str255): INTEGER;
|
| Called during boot (6,954 times in 30s trace).
StringWidth:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE.L  (SP)+,A0                        | POP ADDR OF STRING
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  (A0)+,D0                        | GET UNSIGNED BYTE
        MOVE.L  A0,-(SP)                        | PUSH TEXTADDR
        CLR     -(SP)                           | FIRSTBYTE := 0
        MOVE    D0,-(SP)                        | PUSH BYTECOUNT
        MOVE.L  A1,-(SP)                        | PUT BACK RETURN ADDR

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
TextWidth:
        LINK    A6,#-0x10                       | ALLOCATE STACK FRAME
        CLR     0x10(A6)                        | INIT RESULT TO 0
.set PARAMSIZE, 8                               | TOTAL BYTES OF PARAMS
.set RESULT, PARAMSIZE+8                        | FUNCTION RESULT
.set TEXTBUF, RESULT-4                          | LONG
.set FIRSTBYTE, TEXTBUF-2                       | WORD
.set BYTECOUNT, FIRSTBYTE-2                     | WORD

.set INFO, -8                                   | 4 WORDS
.set NUMER, INFO-4                              | POINT
.set DENOM, NUMER-4                             | POINT
.set VARSIZE, DENOM                             | TOTAL BYTES OF LOCALS

        CLR     -(SP)                           | MAKE ROOM FOR FCN CALL BELOW
        MOVE    0x8(A6),-(SP)                   | PUSH BYTE COUNT
        BLE.B   TEXTWIDTH_DONE_EXIT             | QUIT IF COUNT <= 0

| UNLK TAKES CARE OF SP
        MOVE.L  0xC(A6),A0                      | GET ADDR OF BUFFER
        ADDA    0xA(A6),A0                      | ADD STARTING INDEX
        MOVE.L  A0,-(SP)                        | PUSH TEXTADDR
        MOVE.L  #0x10001,D0                     | get 1,1 for numer and denom
        MOVE.L  D0,-0xC(A6)                     | NUMER := (1,1)
        MOVE.L  D0,-0x10(A6)                    | DENOM := (1,1)
        PEA.L   -0xC(A6)                        | PUSH VAR NUMER
        PEA.L   -0x10(A6)                       | PUSH VAR DENOM
        PEA.L   -0x8(A6)                        | PUSH VAR INFO
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xFB4).w,A0                    | _StdTxMeas (txMeasProc)
        BEQ.B   STD                             | YES, USE STDTXMEAS
        MOVE.L  D0,A0                           | NO, GET GRAFPROCS
        MOVE.L  TXMEASPROC(A0),A0               | GET TXMEAS CAPTURE PROC
STD:
        JSR     (A0)                            | CALL IT
        MOVE    (SP)+,D1                        | NOTSTD: POP UNSCALED WIDTH
        MOVE    -0xA(A6),D0                     | get numer
        MOVE    -0xE(A6),D2                     | get denom
        CMP     D2,D0                           | is numer same as denom ?
        BEQ.B   TEXTWIDTH_DONE                  | yes, skip muldiv
        MULU    D0,D1                           | MUL BY NUMER
        DIVU    D2,D1                           | DIV BY DENOM
TEXTWIDTH_DONE:
        MOVE    D1,0x10(A6)                     | RETURN SCALED WIDTH
TEXTWIDTH_DONE_EXIT:
        UNLK    A6                              | RESTORE STACK POINTER
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x8,SP                         | STRIP PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .FUNC StdTxMeas,5
| ------------------------------------------
|
| FUNCTION StdTxMeas(count: INTEGER; textAddr: Ptr;
| VAR numer,denom: Point;
| VAR info: FontInfo): INTEGER;
|
| Measure some text, returning unscaled values plus updated scale factor.
| Fills info record with unscaled ascent, descent, widMax, and leading,
| and returns unscaled integer width as the function value.
|
| Also leaves unscaled fixed point width in QD global 'fixTxWid'
| and stashes FMOutPtr in QD global 'fontPtr' for DrawText.
|
| Called during boot (37,171 times in 30s trace).
StdTxMeas:
        LINK    A6,#-0x10                       | ALLOCATE LOCALS
.set PARAMSIZE, 18                              | TOTAL BYTES OF PARAMS
.set RESULT, PARAMSIZE+8                        | FCN RESULT IS A WORD
.set COUNT, RESULT-2                            | WORD
.set TEXTADDR, COUNT-4                          | LONG
.set NUMER, TEXTADDR-4                          | LONG, VAR ADDR
.set DENOM, NUMER-4                             | LONG, VAR ADDR
.set INFO, DENOM-4                              | LONG, ADDR OF FONTINFO

.set INREC, -16                                 | FMInput record
.set VARSIZE, INREC                             | TOTAL SIZE OF LOCAL VARS

        MOVE.L  A4,-(SP)                        | SAVE REG
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A0                         | GET CURRENT GRAFPORT
        LEA.L   -0x10(A6),A1                    | POINT TO FMINPUT RECORD
        MOVE    TXFONT(A0),(A1)+                | GET TXFONT FROM THEPORT
        MOVE    TXSIZE(A0),(A1)+                | GET TXSIZE FROM THEPORT
        MOVE.B  TXFACE(A0),(A1)+                | GET TXFACE FROM THEPORT
        ST      (A1)+                           | ALWAYS SET NEEDBITS TRUE
        MOVE    (A0),(A1)+                      | GET DEVICE FROM THEPORT
        MOVE.L  0x10(A6),A0                     | POINT TO NUMER
        MOVE.L  (A0),(A1)+                      | INSTALL INPUT NUMER
        MOVE.L  0xC(A6),A0                      | POINT TO DENOM
        MOVE.L  (A0),(A1)+                      | INSTALL INPUT DENOM
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        PEA.L   -0x10(A6)                       | PUSH INPUT RECORD
        MOVE.L  (JSwapFont).w,A0                | get address of _SwapFont
        JSR     (A0)                            | CALL FMSWAPFONT

| _SwapFont ;CALL FMSWAPFONT
        MOVE.L  (SP)+,A1                        | POP FMOUTPUT POINTER
        MOVE.L  A1,FONTPTR(A4)                  | STASH FMOUTPTR FOR LATER
        MOVE.L  0x8(A6),A0                      | POINT TO VAR INFO RECORD
        CLR.L   (A0)                            | INIT TO (0,0,0,0)
        CLR.L   0x4(A0)                         | ALL 4 WORDS
        MOVE.B  0xD(A1),0x1(A0)                 | FILL IN UNSIGNED ASCENT
        MOVE.B  0xE(A1),0x3(A0)                 | FILL IN UNSIGNED DESCENT
        MOVE.B  0xF(A1),0x5(A0)                 | FILL IN UNSIGNED WIDMAX
        MOVE.B  0x10(A1),D0                     | GET SIGNED LEADING
        EXT     D0                              | SIGN EXTEND TO WORD
        MOVE    D0,0x6(A0)                      | FILL IN LEADING

|
| UPDATE NUMER AND DENOM
|
        MOVE.L  0x10(A6),A0                     | GET VAR ADDR
        MOVE.L  0x12(A1),(A0)                   | UPDATE NUMER
        MOVE.L  0xC(A6),A0                      | GET VAR ADDR
        MOVE.L  0x16(A1),(A0)                   | UPDATE DENOM
        MOVE.L  0x14(A6),A0                     | POINT TO CHARACTERS

        MOVE.L  (WidthPtr).w,A1                 | POINT TO WIDTH TABLE
        CLR.L   D1                              | INIT WIDTH TO 0.0
        MOVE    0x18(A6),D2                     | GET CHARACTER COUNT
        BRA.B   STDTXMEAS_MORE                  | GO TO LOOP START

| ----------------------------------------------------------
|
| STDTXMEAS_NEXTCH
|
| Called during boot (62,735 times in 30s trace).
STDTXMEAS_NEXTCH:
        CLR     D0                              | NEXTCH: GET READY FOR BYTE
        MOVE.B  (A0)+,D0                        | GET A CHARACTER
        LSL     #2,D0                           | QUAD FOR TABLE OFFSET
        ADD.L   0x0(A1,D0.W),D1                 | ADD FIXED POINT WIDTH
STDTXMEAS_MORE:
        DBF     D2,STDTXMEAS_NEXTCH             | LOOP FOR ALL CHARS
        MOVE.L  D1,FIXTXWID(A4)                 | STASH FIXED POINT WIDTH
        SWAP    D1                              | GET HI WORD = INTEGER PORTION
        MOVE    D1,0x1A(A6)                     | UPDATE FUNCTION RESULT
        MOVE.L  (SP)+,A4                        | RESTORE REG
        UNLK    A6                              | RESTORE STACK POINTER
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA    #0x12,SP                        | STRIP PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| .PROC MeasureText
| --------------------------------------------------------------------
|
| PROCEDURE MeasureText(count: INTEGER; textAddr,charLocs: Ptr);
|
| Measure some text, returning (scaled) screen widths in charlocs.
|
| Charlocs points to an array of count+1 integers.
|
| PARAMSIZE .EQU 10
| COUNT .EQU PARAMSIZE+8-2 ;WORD
| TEXTADDR .EQU COUNT-4 ;LONG, Ptr to ASCII
| CHARLOCS .EQU TEXTADDR-4 ;LONG, Ptr to output array
MeasureText:
        LINK    A6,#-0x10                       | ALLOCATE LOCALS

| INREC .EQU -16 ;FMInput record
| VARSIZE .EQU INREC
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set COUNT, PARAMSIZE+8-2                       | WORD
.set TEXTADDR, COUNT-4                          | LONG, Ptr to ASCII
.set CHARLOCS, TEXTADDR-4                       | LONG, Ptr to output array

.set INREC, -16                                 | FMInput record
.set VARSIZE, INREC                             | TOTAL SIZE OF LOCAL VARS

        MOVEM.L D3-D4/A2,-(SP)                  | SAVE REGS
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT

|
| Call swapfont to set up width table and return numer,denom:
|
        LEA.L   -0x10(A6),A1                    | POINT TO FMINPUT RECORD

        MOVE    TXFONT(A0),(A1)+                | GET TXFONT FROM THEPORT
        MOVE    TXSIZE(A0),(A1)+                | GET TXSIZE FROM THEPORT
        MOVE.B  TXFACE(A0),(A1)+                | GET TXFACE FROM THEPORT
        ST      (A1)+                           | ALWAYS SET NEEDBITS TRUE
        MOVE    (A0),(A1)+                      | GET DEVICE FROM THEPORT
        MOVE.L  #0x10001,(A1)+                  | INSTALL INPUT NUMER = 1,1
        MOVE.L  #0x10001,(A1)+                  | INSTALL INPUT DENOM = 1,1
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        PEA.L   -0x10(A6)                       | PUSH INPUT RECORD
        MOVE.L  (JSwapFont).w,A0                | get address of _SwapFont
        JSR     (A0)                            | CALL FMSWAPFONT

| _SwapFont ;CALL FMSWAPFONT
        MOVE.L  (SP)+,A0                        | POP FMOUTPUT POINTER
        MOVE    0x14(A0),D3                     | GET NUMER.H
        MOVE    0x18(A0),D4                     | GET DENOM.H

|
| Step thru characters, adding up unscaled widths and storing in charLocs:
|
        MOVE.L  0xC(A6),A0                      | POINT TO CHARACTERS

        MOVE.L  (WidthPtr).w,A1                 | POINT TO WIDTH TABLE
        MOVE.L  0x8(A6),A2                      | POINT TO CHARLOCS
        CLR.L   D1                              | INIT WIDTH TO 0.0
        MOVE    0x10(A6),D2                     | GET CHARACTER COUNT
MEASURETEXT_NEXTCH:
        SWAP    D1                              | NEXTCH: GET HI WORD OF WIDTH
        MOVE    D1,(A2)+                        | STORE IN CHARLOCS
        SWAP    D1                              | RETURN WIDTH TO FIXED POINT
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  (A0)+,D0                        | GET A CHARACTER
        LSL     #2,D0                           | QUAD FOR TABLE OFFSET
        ADD.L   0x0(A1,D0.W),D1                 | ADD FIXED POINT WIDTH
        DBF     D2,MEASURETEXT_NEXTCH           | LOOP FOR COUNT+1 CHARLOCS

|
| if font is horizontally stretched, scale all widths accordingly
|
        CMP     D3,D4                           | IS NUMER.H = DENOM.H ?
        BEQ.B   NEXTCH2_SKIP                    | YES, SKIP SCALING
        MOVE.L  0x8(A6),A2                      | NO, POINT TO CHARLOCS
        MOVE    0x10(A6),D2                     | GET CHARACTER COUNT
NEXTCH2:
        MOVE    (A2),D0                         | GET CHARLOC
        MULU    D3,D0                           | MUL BY NUMER
        DIVU    D4,D0                           | DIV BY DENOM
        MOVE    D0,(A2)+                        | UPDATE CHARLOC
        DBF     D2,NEXTCH2                      | LOOP FOR COUNT+1 CHARLOCS
NEXTCH2_SKIP:
        MOVEM.L (SP)+,D3-D4/A2                  | RESTORE REGS
        UNLK    A6                              | RESTORE STACK POINTER
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA    #0xA,SP                         | STRIP PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| --------------------------------------------------------------------
|
| FUNCTION FMSwapFont(inRec: FMInput): FMOutPtr;
|
| FMSwapFont is the only contact between QuickDraw and the Font Manager.
| It swaps in the requested font and returns a pointer to an output record
| telling how to use the font. FMSwapFont is called from StdTxMeas
| in response to DrawChar, DrawString, DrawText, CharWidth, StringWidth,
| TextWidth, and GetFontInfo.
|
| IF fontHandle returns as Nil (can't find the font), then:
| 1. The output record will be undefined except for errNum and fontHandle.
| 2. DrawString will neither draw the text nor bump the pen.
| 3. StringWidth will return 0.
| 4. GetFontInfo will return 0,0,0,0.
|
|
| FMInput = PACKED RECORD
| family: INTEGER; { i.e. Century }
| size: INTEGER; { i.e. 12 point }
| face: Style; { i.e. [bold,underlined] }
| needBits: BOOLEAN; { do we need the bitmaps ? }
| device: INTEGER; { i.e. 0 for screen }
| numer: Point; { current drawing scale }
| denom: Point; { current drawing scale }
| END;
| FMOutPtr = ^FMOutPut;
| FMOutput = PACKED RECORD
| errNum: INTEGER; { not used }
| fontHandle: Handle; { handle to font }
| bold: Byte; { how much to smear horiz }
| italic: Byte; { how much to shear }
| ulOffset: Byte; { pixels below baseline }
| ulShadow: Byte; { how big is the halo }
| ulThick: Byte; { how thick is the underline }
| shadow: Byte; { 0,1,2,or 3 only }
| extra: SignedByte; { extra white dots each char }
| ascent: Byte; { ascent measure for font }
| descent: Byte; { descent measure for font }
| widMax: Byte; { width of widest char }
| leading: SignedByte; { leading between lines }
| unused: Byte;
| numer: Point; { use this modified scale to }
| denom: Point; { draw or measure text with }
| --------------------------------------------------------------------------

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
GetFontInfo:
        LINK    A6,#-0x8                        | ALLOCATE LOCALS
        MOVE.L  #0x10001,-0x4(A6)               | NUMER := (1,1)
        MOVE.L  #0x10001,-0x8(A6)               | DENOM := (1,1)
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set INFO, PARAMSIZE+8-4                        | LONG, ADDR OF INFO

.set NUMER, -4                                  | POINT
.set DENOM, NUMER-4                             | POINT
.set VARSIZE, DENOM                             | TOTAL LOCALS

        CLR.L   -(SP)                           | ROOM FOR FCN, COUNT = 0
        CLR.L   -(SP)                           | TEXTADDR := NIL
        PEA.L   -0x4(A6)                        | PUSH VAR NUMER
        PEA.L   -0x8(A6)                        | PUSH VAR DENOM
        MOVE.L  0x8(A6),-(SP)                   | PUSH VAR INFO
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xFB4).w,A0                    | _StdTxMeas (txMeasProc)
        BEQ.B   GETFONTINFO_USESTD              | YES, USE STD PROC
        MOVE.L  D0,A0                           | NO, GET GRAFPROCS
        MOVE.L  TXMEASPROC(A0),A0               | NO, GET TXMEAS CAPTURE PROC
GETFONTINFO_USESTD:
        JSR     (A0)                            | USESTD: CALL IT
        TST     (SP)+                           | DISCARD WIDTH FCN RSLT
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS

|
| ADJUST WIDMAX FOR EXTRA
|
        MOVE.L  FONTPTR(A0),A0                  | GET FMOUTPUT RECORD
        MOVE.L  0x8(A6),A1                      | POINT TO RESULT INFO
        MOVE.B  0xC(A0),D0                      | GET SIGNED EXTRA
        EXT     D0                              | EXTEND TO WORD
        ADD     D0,0x4(A1)                      | ADD TO WIDMAX

|
| ADJUST ASCENT & DESCENT FOR SHADOW
|
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  0xB(A0),D0                      | GET SHADOW COUNT
        BEQ.B   GETFONTINFO_USESTD_SKIP         | SKIP IF ZERO
        ADDQ.W  #0x1,(A1)                       | ADJUST ASCENT
        ADD     D0,0x2(A1)                      | ADJUST DESCENT

| NOTSHAD

|
| SCALE RESULT IF NUMER <> DENOM
|
| Called during boot (30,141 times in 30s trace).
GETFONTINFO_USESTD_SKIP:
        MOVE.L  -0x4(A6),D0                     | GET NUMER
        CMP.L   -0x8(A6),D0                     | IS NUMER SAME AS DENOM ?

| NOTSHAD

|
| SCALE RESULT IF NUMER <> DENOM
|
        BEQ.B   GETFONTINFO_USESTD_SKIP_2       | YES, SKIP SCALING
        BSR.B   SCALE                           | SCALE ASCENT
        BSR.B   SCALE                           | SCALE DESCENT
        MOVE    (A1),D0                         | GET MAXWID
        MULU    -0x2(A6),D0                     | SCALE MAXWID
        MOVE    -0x6(A6),D1                     | get denom
        LSR     #0x1,D1                         | calc denom div 2
        EXT.L   D1                              | extend to long
        ADD.L   D1,D0                           | add denom-1 to round up
        DIVU    -0x6(A6),D0                     | divide by denom
        MOVE    D0,(A1)+                        | UPDATE MAXWID
        BSR.B   SCALE                           | SCALE LEADING
GETFONTINFO_USESTD_SKIP_2:
        UNLK    A6                              | RESTORE STACK POINTER
        MOVE.L  (SP)+,(SP)                      | STRIP PARAMS
        RTS                                     | AND RETURN

| SCALE -- sCALE ASCENT.
| ----------------------------------------------------------
|
| SCALE
|
SCALE:
        MOVE    (A1),D0                         | GET IT
        MULU    -0x4(A6),D0                     | SCALE IT
        MOVE    -0x8(A6),D1                     | get denom
        LSR     #0x1,D1                         | calc denom div 2
        EXT.L   D1                              | extend to long
        ADD.L   D1,D0                           | add denom-1 to round up
        DIVU    -0x8(A6),D0                     | divide by denom
        MOVE    D0,(A1)+                        | UPDATE IT
        RTS                                     | AND RETURN



