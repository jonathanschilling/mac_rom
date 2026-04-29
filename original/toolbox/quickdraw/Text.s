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
| Note: classic's Text.s starts with tail-end fragments of other text
| routines (STDTEXT_NOTSAME et al., DrText-time continuations). The real
| StdText entry code exists in the file but isn't labeled as such in
| classic -- inlined by FDisasm. TextWidth IS labeled (line ~167).
| Called during boot.

StdText:
        LINK    A6,#-0x4                        | allocate stack frame
        MOVEM.L D5-D7/A3-A4,-(SP)               | save regs
        MOVE    20(A6),D6                       | D6 = character count
        BLE.W   STDTEXT_NOTPIC_RESTORE          | D6 <= 0 -> skip pic emit, restore regs
        JSR     CheckPic(PC)                    | set up A4,A3 / check picSave
        BLE.W   STDTEXT_NOTPIC                  | no pic open -> draw text
        MOVE.L  0x5C(A3),A4                     | get picSave handle
        MOVE.L  (A4),A4                         | dereference picSave
        MOVE    0x44(A3),D7                     | GET NUMER
        CMP     18(A4),D7                       | txFont changed?
        BEQ.B   FONTOK                          | same -> skip
        MOVE.B  #0x3,-(SP)                      | push txFont opcode
        JSR     PutPicByte(PC)                  | emit opcode to picture
        MOVE    D7,-(SP)                        | push txFont param
        JSR     PutPicWord(PC)                  | emit txFont word
        MOVE.L  0x5C(A3),A4                     | re-fetch picSave handle
        MOVE.L  (A4),A4                         | dereference picSave
        MOVE    D7,18(A4)                       | cache picTxFont
FONTOK:
        MOVE.B  0x46(A3),D7                     | get thePort^.txFace
        CMP.B   0x14(A4),D7                     | pnVis matches cached?
        BEQ.B   FACEOK                          | yes -> skip pic emit
        MOVE.B  #0x4,-(SP)                      | push txFace opcode
        JSR     PutPicByte(PC)                  | emit opcode to picture
        MOVE.B  D7,-(SP)                        | push txFace param
        JSR      PutPicByte(PC)                 | emit txFace byte
        MOVEA.L  92(A3),A4                      | re-fetch picSave handle
        MOVE.L  (A4),A4                         | dereference picSave
        MOVE.B  D7,20(A4)                       | cache picTxFace
FACEOK:
        MOVE    0x48(A3),D7                     | get thePort^.txMode
        CMP     22(A4),D7                       | txMode changed?
        BEQ.B   STDTEXT_MODEOK                  | same -> skip
        MOVE.B  #0x5,-(SP)                      | push txMode opcode
        JSR     PutPicByte(PC)                  | emit opcode to picture
        MOVE    D7,-(SP)                        | push txMode param
        JSR     PutPicWord(PC)                  | emit txMode word
        MOVE.L  0x5C(A3),A4                     | re-fetch picSave handle
        MOVE.L  (A4),A4                         | dereference picSave
        MOVE    D7,22(A4)                       | cache picTxMode
STDTEXT_MODEOK:
        MOVE    0x4A(A3),D7                     | get thePort^.txSize
        CMP     24(A4),D7                       | txSize changed?
        BEQ.B   STDTEXT_SIZEOK                  | same -> skip
        MOVE.B  #0xD,-(SP)                      | push txSize opcode
        JSR     PutPicByte(PC)                  | emit opcode to picture
        MOVE    D7,-(SP)                        | push txSize param
        JSR     PutPicWord(PC)                  | emit txSize word
        MOVE.L  0x5C(A3),A4                     | re-fetch picSave handle
        MOVE.L  (A4),A4                         | dereference picSave
        MOVE    D7,24(A4)                       | cache picTxSize
STDTEXT_SIZEOK:
        MOVE.L  0x4C(A3),D7                     | get thePort^.spExtra
        CMP.L   26(A4),D7                       | spExtra changed?
        BEQ.B   SPOK                            | same -> skip
        MOVE.B  #0x6,-(SP)                      | push spExtra opcode
        JSR     PutPicByte(PC)                  | emit opcode to picture
        MOVE.L  D7,-(SP)                        | push spExtra param (long)
        JSR     PutPicLong(PC)                  | emit spExtra long
        MOVE.L  0x5C(A3),A4                     | re-fetch picSave handle
        MOVE.L  (A4),A4                         | dereference picSave
        MOVE.L  D7,26(A4)                       | cache picSpExtra
| CHECK NUMER, DENOM
SPOK:
        MOVE.L  12(A6),D7                       | D7 = numer (point)
        MOVE.L  8(A6),D5                        | D5 = denom (point)
        CMP.L   30(A4),D7                       | picTxNumer changed?
        BNE.B   STDTEXT_NOTSAME                 | yes -> emit txRatio
        CMP.L   0x22(A4),D5                     | picTxDenom changed?
        BEQ.B   STDTEXT_NOTSAME_NO              | both same -> skip
STDTEXT_NOTSAME:
        MOVE.B  #0x10,-(SP)                     | push txRatio opcode ($10)
        JSR     PutPicByte(PC)                  | SET UP A4,A3 AND CHECK PICSAVE
        MOVE.L  D7,-(SP)                        | push numer param
        JSR     PutPicLong(PC)                  | PUT OPCODE
        MOVE.L  D5,-(SP)                        | push denom param
        JSR     PutPicLong(PC)                  | PUT TXFONT PARAM
        MOVE.L  0x5C(A3),A4                     | re-fetch picSave handle
        MOVE.L  (A4),A4                         | DE-REFERENCE PICSAVE
        MOVE.L  D7,30(A4)                       | POP RETURN ADDR
        MOVE.L  D5,0x22(A4)                     | cache picTxDenom
STDTEXT_NOTSAME_NO:
        MOVE.L  0x30(A3),D5                     | jump via A0
        SUB.L   0x26(A4),D5                     | compute dv/dh = pnLoc - picTxLoc
        MOVE.L  D5,D0                           | test dv/dh range
        ANDI.L  #0xFF00FF00,D0                  | mask high bytes of DV/DH
        BEQ.B   SHORT                           | no DV offset -> try short form
        MOVE.B  #0x28,-(SP)                     | opcode $28 = long-dx/dy picture op
        JSR     PutPicByte(PC)                  | PUT OPCODE
        MOVE.L  0x30(A3),-(SP)                  | push 32-bit dx/dy
        JSR     PutPicLong(PC)                  | PUT TXSIZE PARAM
        BRA.B   TEXT2                           | -> emit txRatio + font, skip short forms
SHORT:
        MOVE.L  D5,D0                           | YES, COPY DV.DH
        ANDI.L  #0x00FF0000,D0                  | IS DV = 0 ?
        BNE.B   DV                              | NO, CONTINUE
        MOVE.B  #0x29,-(SP)                     | push dhText opcode ($29)
        JSR     PutPicByte(PC)                  | emit opcode
        BRA.B   STDTEXT_SHARE2                  | SHARE COMMON CODE
DV:
        TST.B   D5                              | IS DH = 0 ?
        BNE.B   STDTEXT_DHDV                    | NO, CONTINUE
        MOVE.B  #0x2A,-(SP)                     | push dvText opcode ($2A)
        JSR     PutPicByte(PC)                  | emit opcode
        BRA.B   SHARE1                          | SHARE COMMON CODE
STDTEXT_DHDV:
        MOVE.B  #0x2B,-(SP)                     | push dhdvText opcode ($2B)
        JSR     PutPicByte(PC)                  | emit opcode
        MOVE.B  D5,-(SP)                        | push dh byte
        JSR     PutPicByte(PC)                  | emit dh byte
SHARE1:
        SWAP    D5                              | PUT DV IN LO WORD
STDTEXT_SHARE2:
        MOVE.B  D5,-(SP)                        | push dh/dv byte
        JSR     PutPicByte(PC)                  | emit dh/dv
TEXT2:                                          | @ $5D60 (common tail after long/short forms)
        MOVE.B  D6,-(SP)                        | push char count
        JSR     PutPicByte(PC)                  | emit count byte
        MOVE.L  16(A6),-(SP)                    | PUSH ADDR OF TEXT
        MOVE    D6,-(SP)                        | PUSH COUNT
        JSR     PutPicData(PC)                  | emit picture-comment prefix
        MOVEA.L 0x5C(A3),A4                     | A4 = picture handle
        MOVEA.L (A4),A4                         | A4 = dereferenced picture ptr
        MOVE.L  0x30(A3),0x26(A4)               | copy pnLoc into picture header
| DrText(count,textAddr,numer,denom);
| Called during boot.
STDTEXT_NOTPIC:
        MOVE    D6,-(SP)                        | PUSH COUNT
        MOVE.L  16(A6),-(SP)                    | PUSH TEXTADDR
        MOVE.L  12(A6),-(SP)                    | PUSH NUMER
        MOVE.L  8(A6),-(SP)                     | POINT TO QUICKDRAW GLOBALS
        JSR     DrText(PC)                      | DRAW THE TEXT
STDTEXT_NOTPIC_RESTORE:                         | @ $5D8E (error-skip target)
        MOVEM.L (SP)+,D5-D7/A3-A4               | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xE,SP                         | strip 14 bytes of params
        JMP     (A0)                            | RTS

| .PROC CallText,2
| .REF STDTEXT
| ---------------------------------------------------------------
| PROCEDURE CallText(count: INTEGER; textAddr: Ptr);
| Called during boot.
CallText:                                       | jump via A0
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  #0x00010001,-(SP)               | push numer = (1,1)
        MOVE.L  (SP),-(SP)                      | PUSH DENOM = (1,1)
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  0x68(A0),D0                     | D0 = grafProcs ptr
        LEA     StdText(PC),A0                  | default = StdText
        BEQ.B   CALLTEXT_CONT                   | YES, USE STD PROC
        MOVE.L  D0,A0                           | A0 = grafProcs
        MOVE.L  (A0),A0                         | dispatch through textProc
CALLTEXT_CONT:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE TextFont(font: INTEGER); install txFont (offset $44).
TextFont:
        MOVEQ.L #0x44,D0                        | port offset = TXFONT
        JMP     L_mPortWord(PC)                 | install word

| PROCEDURE TextFace(face: Style); install txFace byte (offset $46).
TextFace:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.B  5(SP),0x46(A0)                  | install txFace byte
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x2,SP                         | strip param
        JMP     (A0)                            | return

| PROCEDURE TextMode(mode: INTEGER); install txMode (offset $48).
TextMode:
        MOVEQ.L #0x48,D0                        | port offset = TXMODE
        JMP     L_mPortWord(PC)                 | install word

| PROCEDURE TextSize(size: INTEGER); install txSize (offset $4A).
TextSize:
        MOVEQ.L #0x4A,D0                        | port offset = TXSIZE
        JMP     L_mPortWord(PC)                 | install word

| PROCEDURE SpaceExtra(extra: Fixed); install spExtra (offset $4C).
SpaceExtra:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  4(SP),0x4C(A0)                  | install spExtra long
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| PROCEDURE DrawChar(ch: Char); push count=1 + textAddr -> CallText.
DrawChar:
        MOVE    #0x1,-(SP)                      | PUSH COUNT=1
        PEA.L     7(SP)                         | PUSH TEXTADDR
        JSR     CallText(PC)                    | CALL TEXT ROUTINE
        MOVEA.L  (SP)+,A0                       | pop return addr
        ADDQ.W   #0x2,SP                        | strip param
        JMP      (A0)                           | return

| PROCEDURE DrawString(s: Str255).
DrawString:
        MOVE.L  4(SP),A0                        | POINT TO STRING
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  (A0)+,D0                        | GET STRING LENGTH
        MOVE    D0,-(SP)                        | PUSH COUNT
        MOVE.L  A0,-(SP)                        | PUSH TEXTADDR
        JSR     CallText(PC)                    | CALL TEXT ROUTINE
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| PROCEDURE DrawText(textBuf: Ptr; firstByte, byteCount: INTEGER);
DrawText:
        MOVE.L  8(SP),A0                        | textBuf
        ADDA.W  6(SP),A0                        | + firstByte
        MOVE    4(SP),D0                        | byteCount
        MOVE    D0,-(SP)                        | PUSH COUNT
        MOVE.L  A0,-(SP)                        | PUSH TEXTADDR
        JSR     CallText(PC)                    | CALL TEXT ROUTINE
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS

| FUNCTION CharWidth(ch: Char): INTEGER. | call subroutine via A0 | call subroutine via A0
CharWidth:
        CLR     -(SP)                           | space for FCN result
        MOVE.L  SP,-(SP)                        | textAddr = SP
        MOVE    #0x7,-(SP)                      | first = 7 (after ret addr)
        MOVE    #0x1,-(SP)                      | count = 1
        JSR     TextWidth(PC)                   | call TextWidth(1, &ch, 0, 1)
        MOVE    (SP)+,6(SP)                     | move result to caller's slot
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x2,SP                         | strip param
        JMP     (A0)                            | RTS
| .FUNC StringWidth,1
| .REF TextWidth
| ---------------------------------------------
| FUNCTION StringWidth(s: Str255): INTEGER;
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
        JMP     TextWidth(PC)                   | fall through to TextWidth
| FALL THRU INTO TEXTWIDTH
| .FUNC TextWidth,3
| .REF StdTxMeas
| ------------------------------------------
| FUNCTION TEXTWIDTH(TEXTBUF: WordPtr; firstbyte,byteCount: INTEGER): INTEGER;
| Called during boot (6,985 times in 30s trace).
TextWidth:
        LINK    A6,#-0x10                       | allocate 16-byte frame
        CLR     16(A6)                          | INIT RESULT TO 0
        CLR     -(SP)                           | MAKE ROOM FOR FCN CALL BELOW
        MOVE    8(A6),-(SP)                     | PUSH BYTE COUNT
        BLE.B   TEXTWIDTH_CONT_2                | QUIT IF COUNT <= 0
        MOVE.L  12(A6),A0                       | GET ADDR OF BUFFER
        ADDA.W  10(A6),A0                       | ADD STARTING INDEX
        MOVE.L  A0,-(SP)                        | PUSH TEXTADDR
        MOVE.L  #0x10001,-12(A6)                | NUMER := (1,1)
        MOVE.L  #0x10001,-16(A6)                | DENOM := (1,1)
        PEA.L     -12(A6)                       | push @numer
        PEA.L     -16(A6)                       | push @denom
        PEA.L     -8(A6)                        | push @info record
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  0x68(A0),D0                     | D0 = grafProcs ptr
        BNE.B   TEXTWIDTH_NO                    | custom proc -> use it
        JSR     StdTxMeas(PC)                   | default = StdTxMeas
        BRA.B   TEXTWIDTH_CONT                  | skip custom dispatch
TEXTWIDTH_NO:
        MOVE.L  D0,A0                           | NO, GET GRAFPROCS
        MOVE.L  0x28(A0),A0                     | A0 = txMeasProc
        JSR     (A0)                            | call subroutine via A0
TEXTWIDTH_CONT:
        MOVE    (SP)+,D1                        | POP UNSCALED WIDTH
        MULU    -10(A6),D1                      | D1 = D1 *u -10(A6)
        DIVU    -14(A6),D1                      | D1 = D1 /u -14(A6)
        MOVE    D1,16(A6)                       | RETURN SCALED WIDTH
TEXTWIDTH_CONT_2:
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
StdTxMeas:
        LINK    A6,#-0x14                       | allocate 20-byte frame
        MOVEM.L D3-D7/A2-A4,-(SP)               | save regs
        CLR     26(A6)                          | init width result to 0
        MOVE.L  (A5),A4                         | A4 = QD globals
        MOVE.L  (A4),A3                         | A3 = thePort
        MOVE.L  0x4C(A3),-0xAC(A4)              | stash spExtra into FixTxWid
        LEA.L     -16(A6),A1                    | A1 = local FontInput record
        MOVE    0x44(A3),(A1)+                  | input.family = txFont
        MOVE    0x4A(A3),(A1)+                  | input.size = txSize
        MOVE.B  0x46(A3),(A1)+                  | input.face = txFace
        TST     0x42(A3)                        | test pnVis (negative = invis)
        SPL     (A1)+                           | input.needBits = pnVis>=0
        MOVE    (A3),(A1)+                      | input.device = port.device
        MOVE.L  16(A6),A0                       | POINT TO NUMER
        MOVE.L  (A0),(A1)+                      | INSTALL INPUT NUMER
        MOVE.L  12(A6),A0                       | POINT TO DENOM
        MOVE.L  (A0),(A1)+                      | INSTALL INPUT DENOM
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        PEA.L     -16(A6)                       | push FontInput addr
        JSR     SWAP_FONT_TRAMP(PC)             | FMSwapFont -> get FMOutput
        MOVE.L  (SP),-0xB0(A4)                  | cache FMOutput in fontPtr
        MOVE.L  (SP)+,A4                        | A4 = FMOutput record
        MOVE.L  8(A6),A0                        | POINT TO VAR INFO RECORD
        CLR.L   (A0)                            | INIT TO (0,0,0,0)
        CLR.L   4(A0)                           | ALL 4 WORDS
        TST.L   2(A4)                           | fontHandle nil?
        BEQ.W   TEXTWIDTH_RETURN                | no font -> exit
        MOVE.B  13(A4),1(A0)                    | ascent byte
        MOVE.B  14(A4),3(A0)                    | descent byte
        MOVE.B  15(A4),5(A0)                    | widMax byte
        MOVE.B  16(A4),D0                       | leading byte
        EXT.W    D0                             | SIGN EXTEND TO WORD
        MOVE    D0,6(A0)                        | leading word
        MOVE.L  16(A6),A0                       | GET VAR ADDR
        MOVE.L  18(A4),(A0)                     | index = lower
        MOVE.L  12(A6),A0                       | GET VAR ADDR
        MOVE.L  22(A4),(A0)                     | denom = FMOutput.denom
        MOVE.L  0x4C(A3),D5                     | D5 = spExtra
        BEQ.B   TEXTWIDTH_BODY                  | spExtra==0 -> skip scale
        CLR.L   -(SP)                           | room for FixRatio result
        CLR.L   -(SP)                           | push 0 (numer hi)
        CLR.L   -(SP)                           | push 0 (denom hi)
        MOVE    -6(A6),-(SP)                    | push numer.h
        MOVE    -2(A6),-(SP)                    | push denom.h
        JSR     FixRatio(PC)                    | compute Hscale = numer/denom
        CLR.L   -(SP)                           | room for second FixRatio
        MOVE    24(A4),-(SP)                    | push out.numer
        MOVE    20(A4),-(SP)                    | push out.denom
        JSR     FixRatio(PC)                    | compute fontScale ratio
        JSR     FixMul(PC)                      | combined scale = Hscale * fontScale
        MOVE.L  D5,-(SP)                        | push spExtra
        JSR     FixMul(PC)                      | extra space = scale * spExtra
        MOVE.L  (SP)+,D5                        | D5 = scaled extra
        MOVE.L  (A5),A0                         | POP RETURN ADDR
        MOVE.L  D5,-0xAC(A0)                    | cache scaled FixTxWid
TEXTWIDTH_BODY:
        MOVE    24(A6),D2                       | jump via A0
        BLE.B   TEXTWIDTH_RETURN                | count <= 0 -> exit
        MOVE.L  2(A4),A2                        | A2 = font handle
        MOVE.L  (A2),A2                         | A2 = font record
        MOVE.B  12(A4),D1                       | D1 = extra width byte
        EXT.W    D1                             | sign-extend extra to word
        TST.L   D5                              | any per-space extra?
        BNE.B   TEXTWIDTH_PER_CHAR              | yes -> per-char path
        MOVE    (A2),D0                         | D0 = font format word
        ANDI    #0x2000,D0                      | fixed-width font flag?
        BEQ.B   TEXTWIDTH_PER_CHAR              | no -> per-char path
        ADD     6(A2),D1                        | + maxWidth (uniform width)
        MULS    D2,D1                           | total = uniform * count
        BRA.W   TEXTWIDTH_DONE                  | GO TO LOOP START
TEXTWIDTH_PER_CHAR:
        CLR.L   -20(A6)                         | zero space accumulator
        MOVE.L  20(A6),A0                       | A0 = textBuf
        MULS    D2,D1                           | baseline extra * count
        MOVE.L  A2,A1                           | A1 = font record base
        ADDA.W  16(A2),A1                       | call subroutine via A0
        ADDA.W  16(A2),A1                       | A1 -> widthTable
        MOVE    2(A2),D3                        | D3 = firstChar
        MOVE    4(A2),D4                        | D4 = lastChar
        CLR     D0                              | GET READY FOR BYTE
        BRA.B   TEXTWIDTH_LOOP_TEST             | enter loop via test
TEXTWIDTH_LOOP:
        MOVE.B  (A0)+,D0                        | GET A CHARACTER
        CMPI.B  #0x20,D0                        | is char a space?
        BNE.B   TEXTWIDTH_NOTSPACE              | not space -> skip
        ADD.L   D5,-20(A6)                      | -20(A6) += D5
TEXTWIDTH_NOTSPACE:
        CMP     D4,D0                           | char > lastChar?
        BLE.B   TEXTWIDTH_LOOKUP                | in range -> lookup
TEXTWIDTH_USEMISSING:
        MOVE    D4,D0                           | use missing-char slot
        ADDQ.W  #0x1,D0                         | missing char = lastChar+1
TEXTWIDTH_LOOKUP:
        SUB     D3,D0                           | index = char - firstChar
        BLT.B   TEXTWIDTH_USEMISSING            | below firstChar -> missing
        ADD     D0,D0                           | index *= 2 (word table)
        MOVE    0x10(A1,D0.W),D0                | D0 = WidthTable entry for this char
        CMPI    #-0x1,D0                        | sentinel (-1 = no width)?
        BEQ.B   TEXTWIDTH_USEMISSING            | yes -> skip this character
        ANDI    #0xFF,D0                        | keep only low byte (integer part)
        ADD     D0,D1                           | accumulate width into D1
TEXTWIDTH_LOOP_TEST:
        DBRA    D2,TEXTWIDTH_LOOP               | LOOP FOR ALL CHARS
        ADD     -20(A6),D1                      | add accumulated space-extras
TEXTWIDTH_DONE:
        MOVE    D1,26(A6)                       | UPDATE FUNCTION RESULT
TEXTWIDTH_RETURN:
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | STRIP PARAMS
        ADDA.W  #0x12,SP                        | strip 18 bytes of params
        JMP     (A0)                            | RTS
SWAP_FONT_TRAMP:
        JMP     FMSwapFont(PC)                  | forward to FMSwapFont
        LINK    A6,#-0x8                        | ALLOCATE LOCALS
        MOVE.L  #0x10001,-4(A6)                 | NUMER := (1,1)
        MOVE.L  #0x10001,-8(A6)                 | DENOM := (1,1)
        CLR.L   -(SP)                           | ROOM FOR FCN, COUNT = 0
        CLR.L   -(SP)                           | TEXTADDR := NIL
        PEA.L     -4(A6)                        | PUSH VAR NUMER
        PEA.L     -8(A6)                        | PUSH VAR DENOM
        MOVE.L  8(A6),-(SP)                     | PUSH VAR INFO
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  0x68(A0),D0                     | IS GRAFPROCS NIL ?
        LEA     StdTxMeas(PC),A0                | default = StdTxMeas
        BEQ.B   GETFONTINFO_USESTD              | YES, USE STD PROC
        MOVE.L  D0,A0                           | A0 = grafProcs
        MOVE.L  0x28(A0),A0                     | A0 = txMeasProc
GETFONTINFO_USESTD:
        JSR     (A0)                            | call subroutine via A0
        TST     (SP)+                           | DISCARD WIDTH FCN RSLT
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  -0xB0(A0),A0                    | GET FMOUTPUT RECORD
        MOVE.L  8(A6),A1                        | POINT TO RESULT INFO
        MOVE.B  12(A0),D0                       | GET SIGNED EXTRA
        EXT.W    D0                             | EXTEND TO WORD
        ADD     D0,4(A1)                        | ADD TO WIDMAX
        CLR     D0                              | GET READY FOR BYTE
        MOVE.B  11(A0),D0                       | GET SHADOW COUNT
        BEQ.B   GETFONTINFO_USESTD_SKIP_3       | SKIP IF ZERO
        ADDQ.W  #0x1,(A1)                       | ADJUST ASCENT
        ADD     D0,2(A1)                        | ADJUST DESCENT
GETFONTINFO_USESTD_SKIP_3:
        MOVE.L  -4(A6),D0                       | D0 = numer.h
        CMP.L   -8(A6),D0                       | numer == denom?
        BEQ.B   GETFONTINFO_USESTD_CONT         | YES, SKIP SCALING
        MOVE    (A1),D0                         | get ascent
        MULU    -4(A6),D0                       | D0 = D0 *u -4(A6)
        DIVU    -8(A6),D0                       | D0 = D0 /u -8(A6)
        MOVE    D0,(A1)+                        | scaled ascent
        MOVE    (A1),D0                         | get descent
        MULU    -4(A6),D0                       | D0 = D0 *u -4(A6)
        DIVU    -8(A6),D0                       | D0 = D0 /u -8(A6)
        MOVE    D0,(A1)+                        | scaled descent
        MOVE    (A1),D0                         | GET MAXWID
        MULU    -2(A6),D0                       | D0 = D0 *u -2(A6)
        DIVU    -6(A6),D0                       | D0 = D0 /u -6(A6)
        MOVE    D0,(A1)+                        | UPDATE MAXWID
        MOVE    (A1),D0                         | GET IT
        MULU    -4(A6),D0                       | D0 = D0 *u -4(A6)
        DIVU    -8(A6),D0                       | D0 = D0 /u -8(A6)
        MOVE    D0,(A1)+                        | UPDATE IT
GETFONTINFO_USESTD_CONT:
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return
