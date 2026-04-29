| --------------------------------------------------------------
|
| --> DRAWTEXT.TEXT
|
| QuickDraw Character Generator
|
| Completely reworked 29 Apr 85 by Bill Atkinson to get 50% speed up.
| Takes advantage of optional height table at end of font.
|

| .PROC DrText,4
| .REF RightMask,MaskTab,RSect,ShieldCursor,ShowCursor
| .REF StdTxMeas,RectInRgn,MapRect,StretchBits,TrimRect
| ------------------------------------------------------------
|
| PROCEDURE DrText(count: INTEGER; textAddr: Ptr; numer,denom: Point);
|
| DRAWS CHARACTERS INTO THE CURRENT PORT'S BITMAP.
| THE FONT AND ATTRIBUTES ARE GIVEN IN THE CURRENT PORT'S CHARSTYLE.
|
| Note: classic's DrawText.s starts with tail-end fragments of the
| DrText routine itself (DRTEXT_NOTFAST_NO et al.). The real DrText
| entry exists but isn't labeled in classic -- FDisasm didn't
| identify it.
| Called during boot.

| .FUNC DrText,1
| .REF GetPicData,ScalePt,MapPt,MapRect,MapRgn,MapPoly
| .REF NewRgn,CopyRgn,SectRgn,UnpackBits
| .REF StdText,StdLine,StdRect,StdRRect,StdOval
| .REF StdArc,StdPoly,StdRgn,StdBits,StdComment
| ------------------------------------------------------------------
| FUNCTION DrText(VAR playState: PicPlayRec): BOOLEAN;
| Draws one picture item, updating playState and thePort.
| Returns FALSE when an endPic opCode is encountered.
| The only state modified other than thePort and playState is patAlign.
DrText:
        LINK    A6,#-0xAC                       | set up stack frame
        MOVEM.L D0-D7/A1-A4,-(SP)               | save regs
        MOVE.L  SP,-4(A6)                       | saveStk = SP
        MOVE.L  (A5),A4                         | A4 = QD globals
        MOVE.L  (A4),A3                         | A3 = thePort
        CLR     -(SP)                           | room for fcn result
        MOVE    20(A6),-(SP)                    | push count
        BLE.W   NOSHAD_EXIT                     | count<=0 -> exit
        MOVE.L  16(A6),-(SP)                    | push textAddr
        PEA.L     12(A6)                        | push @numer
        PEA.L     8(A6)                         | push @denom
        PEA.L     -0xA8(A6)                     | push @info record
        JSR     StdTxMeas(PC)                   | measure text width
        MOVE    (SP)+,D1                        | D1 = unscaled width
        MOVE.L  -0xB0(A4),A4                    | A4 = FMOutput record
        TST.L   2(A4)                           | fontHandle nil?
        BEQ.W   NOSHAD_EXIT                     | no font -> exit
        MOVE    D1,-6(A6)                       | textRect.right = pen.h + width
        MOVE.L  0x30(A3),-0x6A(A6)              | save penLoc into local
        MULU    14(A6),D1                       | D1 = D1 *u 14(A6)
        DIVU    10(A6),D1                       | D1 = D1 /u 10(A6)
        ADD     D1,0x32(A3)                     | 0x32(A3) += D1
        TST     0x42(A3)                        | test pnVis
        BLT.W   NOSHAD_EXIT                     | pen hidden -> exit
        MOVE.L  2(A4),A2                        | A2 = font handle
        MOVE.L  (A2),A2                         | A2 = font record
        MOVE    -0x6A(A6),D0                    | D0 = pen.v
        SUB     18(A2),D0                       | subtract ascent
        MOVE    D0,-12(A6)                      | textRect.top = pen.v - ascent
        ADD     14(A2),D0                       | + height (rectH)
        MOVE    D0,-8(A6)                       | textRect.bottom
        MOVE    -0x68(A6),D0                    | D0 = pen.h
        MOVE    D0,-10(A6)                      | textRect.left = pen.h
        ADDI    #0x20,D0                        | add 32-pixel slop
        ADD     D0,-6(A6)                       | -6(A6) += D0
        MOVE.L  -12(A6),-20(A6)                 | copy bounds to extra rect
        MOVE.L  -8(A6),-16(A6)                  | copy bounds to extra rect
        MOVE.L  0x54(A3),D0                     | D0 = bkColor
        NOT.L   D0                              | invert it
        AND.L   0x50(A3),D0                     | AND with fgColor
        MOVE    0x58(A3),D1                     | D1 = colrBit
        BTST    D1,D0                           | test bit D1 of D0
        SNE     -0x66(A6)                       | fastFlag = plane normal
        MOVE.L  12(A6),D0                       | D0 = numer
        CMP.L   8(A6),D0                        | stretching?
        SNE     -0x78(A6)                       | stretch flag
        BEQ.B   PICITEM_CONT                    | not stretching -> skip
        CLR.B   -0x66(A6)                       | clear fastFlag (no fast w/stretch)
        MOVE.L  -0x6A(A6),D0                    | set up toRect.topLeft = pen
        MOVE.L  D0,-0x88(A6)                    | toRect.topLeft
        ADD     14(A6),D0                       | + numer.h
        MOVE    D0,-0x82(A6)                    | toRect.right
        SWAP    D0                              | get .v
        ADD     12(A6),D0                       | + numer.v
        MOVE    D0,-0x84(A6)                    | toRect.bottom
        MOVE.L  -0x6A(A6),D0                    | set up fromRect.topLeft
        MOVE.L  D0,-0x80(A6)                    | fromRect.topLeft
        ADD     10(A6),D0                       | + denom.h
        MOVE    D0,-0x7A(A6)                    | fromRect.right
        SWAP    D0                              | get .v
        ADD     8(A6),D0                        | + denom.v
        MOVE    D0,-0x7C(A6)                    | fromRect.bottom
        PEA.L     -20(A6)                       | push @textR2
        PEA.L     -0x80(A6)                     | push @fromRect
        PEA.L     -0x88(A6)                     | push @toRect
        JSR     MapRect(PC)                     | map textR2 from->to
PICITEM_CONT:
        PEA.L     -20(A6)                       | push @textR2 (mapped)
        PEA.L     8(A3)                         | push @portBits.bounds
        MOVE.L  28(A3),A0                       | A0 = clipRgn handle
        MOVE.L  (A0),A0                         | A0 = clipRgn record
        PEA.L     2(A0)                         | push clipRgn bbox
        MOVE.L  24(A3),A0                       | A0 = visRgn handle
        MOVE.L  (A0),A0                         | A0 = visRgn record
        PEA.L     2(A0)                         | push visRgn bbox
        MOVE    #0x4,-(SP)                      | push nRects = 4
        PEA.L     -28(A6)                       | push @minRect
        JSR     RSect(PC)                       | compute intersection
        BEQ.W   NOSHAD_EXIT                     | empty -> exit
        LEA.L     26(A2),A0                     | A0 = font bitmap base
        MOVE.L  A0,-0x62(A6)                    | srcAddr = font bitmap
        MOVE    24(A2),D1                       | D1 = words per row
        ADD     D1,D1                           | *2 = bytes per row
        MOVE    D1,-0x64(A6)                    | srcRow = bytes/row
        MOVE    14(A2),-0x34(A6)                | height for later
        TST.B   -0x66(A6)                       | fastFlag set?
        BEQ.W   DRTEXT_NOTFAST                  | not fast -> slow path
        TST     6(A4)                           | bold/italic set?
        BNE.W   DRTEXT_NOTFAST                  | yes -> not fast
        TST     10(A4)                          | ULThick or shadow?
        BNE.W   DRTEXT_NOTFAST                  | yes -> not fast
        CMPI    #0x1,0x48(A3)                   | txMode == srcOr?
        BNE.B   DRTEXT_NOTFAST                  | no -> not fast
        MOVE.L  28(A3),A0                       | A0 = clipRgn handle
        MOVE.L  (A0),A0                         | A0 = clipRgn record
        CMPI    #0xA,(A0)                       | rectangular (size==10)?
        BNE.B   DRTEXT_NOTFAST                  | no -> not fast
        MOVE.L  24(A3),A0                       | A0 = visRgn handle
        MOVE.L  (A0),A0                         | A0 = visRgn record
        CMPI    #0xA,(A0)                       | visRgn rectangular?
        BEQ.B   STDTEXT_FAST_Y                  | yes -> take fast path
        CLR.B   -(SP)                           | room for boolean result
        MOVE.L  24(A3),-(SP)                    | push visRgn handle
        PEA.L     -28(A6)                       | push @minRect
        JSR     RectInRgn(PC)                   | visRgn intersect minRect rect?
        TST.B   (SP)+                           | boolean result
        BEQ.B   DRTEXT_NOTFAST                  | non-rect -> slow path
STDTEXT_FAST_Y:
        MOVE    -28(A6),D0                      | D0 = minRect.top
        SUB     -12(A6),D0                      | dy = top - textRect.top
        BLE.B   STDTEXT_FAST_X                  | dy<=0 -> skip
        MULU    D1,D0                           | rows clipped * srcRow
        ADD.L   D0,-0x62(A6)                    | -0x62(A6) += D0
STDTEXT_FAST_X:
        MOVE    -24(A6),D0                      | D0 = minRect.bottom
        SUB     -28(A6),D0                      | visible height
        BLE.W   NOSHAD_EXIT                     | zero height -> exit
        MOVE    D0,-0x34(A6)                    | height = visible rows
        MOVE    -28(A6),D0                      | D0 = minRect.top
        SUB     8(A3),D0                        | - portBits.top
        MULU    6(A3),D0                        | D0 = D0 *u 6(A3)
        ADD.L   2(A3),D0                        | + portBits.baseAddr
        MOVE.L  D0,-0x24(A6)                    | dstAddr = baseAddr + offset
        MOVE    6(A3),-0x28(A6)                 | dstRow = portBits.rowBytes
        MOVE    10(A3),-0x2A(A6)                | dstLeft = portBits.left
        PEA.L     -28(A6)                       | push @minRect
        MOVE.L  8(A3),-(SP)                     | REMEMBER WHERE BUFFER ENDS
        JSR     DrawControls(PC)                | dispatch fast text rendering
        BRA.B   CLRLOOP_CONT                    | done -> exit
| Slow case: Setup for an off-screen buffer.
| Calc bufLeft: (word-align to avoid shift)
| Called during boot.
DRTEXT_NOTFAST:
        CLR.B   -0x66(A6)                       | CLEAR ONE LONG OF BUFFER
        MOVE    -10(A6),D0                      | D0 = textRect.left
        SUB     10(A3),D0                       | - portBits.left
        ANDI    #-0x10,D0                       | word-align (clear 4 LSBs)
        SUBI    #0x20,D0                        | subtract 32 (slop)
        ADD     10(A3),D0                       | restore portBits.left bias
        MOVE    D0,-0x2A(A6)                    | bufLeft
        MOVE    -6(A6),D1                       | D1 = textRect.right
        SUB     D0,D1                           | width = right - bufLeft
        LSR     #0x5,D1                         | /32 -> long count
        ADDQ.W  #0x2,D1                         | +2 longs slop
        MOVE    -0x34(A6),D3                    | height
        MULU    D1,D3                           | bufSize = longs * height
        MOVE    D3,-0x26(A6)                    | D1 = transaction ID from packet
        LSL     #0x2,D1                         | *4 -> bytes per row
        MOVE    D1,-0x28(A6)                    | bufRow
| ----------------------------------------------------------
| DRTEXT_NOTFAST_NO
| Called during boot.
DRTEXT_NOTFAST_NO:
        SUBQ.W  #0x1,D3                         | ADJUST BUFSIZE FOR DBF LOOP
| Allocate and clear an off-screen buffer
        CLR.L   -(SP)                           | PAD BUFFER WITH AN EXTRA ZERO
        MOVE.L  A7,-0x20(A6)                    | REMEMBER WHERE BUFFER ENDS
CLRLOOP:
        CLR.L   -(SP)                           | CLEAR ONE LONG OF BUFFER
        DBF     D3,CLRLOOP                      | ALLOCATE AND CLEAR BUFFER
        MOVE.L  A7,-0x24(A6)                    | REMEMBER START OF BUFFER
        CLR.L   -(SP)                           | PAD BUFFER WITH AN EXTRA ZERO
CLRLOOP_CONT:
        LEA.L     26(A2),A1                     | A1 = font location table base
        MOVE    14(A2),D0                       | GET HEIGHT OF FONT BITMAP
        MULU    -0x64(A6),D0                    | D0 = D0 *u -0x64(A6)
        ADDA.L  D0,A1                           | A1 -> end of strike body
        MOVE    16(A2),D0                       | HOW MANY WORDS IN STRIKE BODY
        ADD     D0,D0                           | *2 = bytes
        LEA.L   0x10(A2,D0.W),A0                | A0 = &entry in A2's indexed table
        MOVE.L  A0,-0xAC(A6)                    | save widTab pointer
        MOVE    #0x20,D0                        | test space char
        CMP     4(A2),D0                        | space > maxChar?
        BLE.B   CLRLOOP_CONT_3                  | in range -> lookup
CLRLOOP_CONT_2:
        MOVE    4(A2),D0                        | GET MAXCHAR
        ADDQ.W  #0x1,D0                         | maxChar+1 = missing slot
CLRLOOP_CONT_3:
        SUB     2(A2),D0                        | index = char - minChar
        BLT.B   CLRLOOP_CONT_2                  | below firstChar -> missing
        ADD     D0,D0                           | INDEX := 2*(ASCII-MINCHAR)
        MOVE.L  -0xAC(A6),A0                    | POINT TO WIDTH TABLE
        MOVE    0(A0,D0.W),D5                   | D5 = width entry
        CMPI    #-0x1,D5                        | sentinel (no width)?
        BEQ.B   CLRLOOP_CONT_2                  | NO, CONTINUE
        ANDI    #0xFF,D5                        | keep low byte (intWidth)
        ADD.B   12(A4),D5                       | + extra width byte
        SWAP    D5                              | move width to high word
        CLR     D5                              | low word = 0 (Fixed)
        MOVE.L  (A5),A0                         | A0 = QD globals
        ADD.L   -0xAC(A0),D5                    | + FixTxWid bias
        MOVE.L  D5,-0x9C(A6)                    | spWidth (Fixed space-width)
        MOVE    -0x68(A6),D0                    | D0 = pen.h
        ADD     8(A2),D0                        | + font.kernMax
        MOVE    D0,-0xA0(A6)                    | charLoc.h
        MOVE    #-0x8000,-0x9E(A6)              | charLoc.frac = -0.5 (rounding)
        SUBQ.W  #0x1,-0x34(A6)                  | height-- for DBF
CLRLOOP_CONT_4:
        MOVE.L  16(A6),A0                       | A0 = textAddr
        MOVE.B  (A0)+,D0                        | fetch next char
        MOVE.L  A0,16(A6)                       | SAVE FOR LATER
        CMPI.B  #0x20,D0                        | is char a space?
        BNE.B   CLRLOOP_CONT_5                  | not space -> normal path
        MOVE.L  -0x9C(A6),D1                    | D1 = spWidth
        ADD.L   D1,-0xA0(A6)                    | -0xA0(A6) += D1
        BRA.W   CHARDONE                        | GO TO LOOP START
CLRLOOP_CONT_5:
        ANDI    #0xFF,D0                        | zero-extend char to word
        CMP     4(A2),D0                        | char > maxChar?
        BLE.B   CLRLOOP_CONT_7                  | QUIT IF CHARCOUNT <= 0
CLRLOOP_CONT_6:
        MOVE    4(A2),D0                        | use missing-char index
        ADDQ.W  #0x1,D0                         | missing = maxChar+1
CLRLOOP_CONT_7:
        SUB     2(A2),D0                        | index = char - minChar
        BLT.B   CLRLOOP_CONT_6                  | below firstChar -> missing
        ADD     D0,D0                           | index *= 2 (word table)
        MOVE.L  -0xAC(A6),A0                    | A0 = widTab
        MOVE    0(A0,D0.W),D5                   | D5 = width entry
        CMPI    #-0x1,D5                        | sentinel (no width)?
        BEQ.B   CLRLOOP_CONT_6                  | YES, HANDLE IT
        MOVE    0(A1,D0.W),D1                   | D1 = locTab[index] (srcLeft)
        MOVE    2(A1,D0.W),D2                   | D2 = locTab[index+1] (srcRight)
        SUB     D1,D2                           | CALC WIDTH OF BITS
        BLE.W   ADVANCE_CHARLOC                 | SKIP CHARBLT IF WIDTH <= 0
        MOVE    D5,D3                           | D3 = width entry
        LSR     #0x8,D3                         | shift down kerning byte
        ADD     -0xA0(A6),D3                    | + charLoc.h = dstLeft
        ADD     D3,D2                           | DSTRIGHT := DSTLEFT + WIDTH
        TST.B   -0x66(A6)                       | fastFlag set?
        BEQ.B   CLRLOOP_CONT_9                  | no, continue
        CMP     -26(A6),D2                      | dstRight < minRect.left?
        BLE.W   ADVANCE_CHARLOC                 | fully clipped left -> skip
        CMP     -22(A6),D3                      | dstLeft >= minRect.right?
        BGE.W   FORCE_STRDONE                   | NO, CONTINUE
        CMP     -22(A6),D2                      | dstRight > minRect.right?
        BLE.B   CLRLOOP_CONT_8                  | YES, SKIP THIS CHAR
        MOVE    -22(A6),D2                      | clip dstRight = minRect.right
CLRLOOP_CONT_8:
        CMP     -26(A6),D3                      | dstLeft >= minRect.left?
        BGE.B   CLRLOOP_CONT_9                  | in range -> blit
        MOVE    -26(A6),D0                      | D0 = minRect.left
        SUB     D3,D0                           | DISCARD:=MINRECT.LEFT-DSTLEFT
        ADD     D0,D1                           | SRCLEFT:=SRCLEFT+DISCARD
        ADD     D0,D3                           | DSTLEFT:=DSTLEFT+DISCARD
CLRLOOP_CONT_9:
        SUB     -0x2A(A6),D3                    | dstLeft -= bufLeft
        SUB     -0x2A(A6),D2                    | dstRight -= bufLeft
        MOVEM.L D5/A1-A5,-(SP)                  | save regs across blit
        MOVE    D3,D5                           | COPY DSTLEFT
        SUB     D1,D5                           | SUB SRC LEFT
        ANDI    #0xF,D5                         | shiftCnt = (dst-src) mod 16
        MOVE.L  -0x62(A6),A4                    | A4 = srcAddr (font row)
        ADD     D5,D1                           | CALC SRCLEFT+SHIFTCNT
        ASR     #0x4,D1                         | /16 -> word offset
        ADD     D1,D1                           | DOUBLE FOR BYTES
        SUBQ.W  #0x2,D1                         | back up one word for bias
        ADDA.W  D1,A4                           | LEAVE SRCPTR IN A4
        MOVE.L  -0x24(A6),A5                    | A5 = bufStart (dstAddr base)
        MOVE    D3,D1                           | GET A COPY OF DSTLEFT
        MOVE    D1,D0                           | D0 = dstLeft for BitMask
        ASR     #0x4,D1                         | /16 -> word offset
        ADDA.W  D1,A5                           | ADD TO DSTPTR
        ADDA.W  D1,A5                           | TWICE FOR BYTES
        JSR     BitMask(PC)                     | compute leftMask
        MOVE    D0,D3                           | D3 = leftMask
        MOVE    D2,D6                           | copy dstRight
        MOVE    D6,D0                           | D0 = dstRight for LeftMask
        JSR     LeftMask(PC)                    | compute rightMask
        MOVE    D0,D4                           | D4 = rightMask
        MOVE    -0x64(A6),A2                    | A2 = font srcRow
        MOVE    -0x28(A6),A3                    | A3 = buffer dstRow
        MOVE    -0x34(A6),D7                    | D7 = row count
        ASR     #0x4,D6                         | dstRight /= 16
        SUB     D1,D6                           | CALC TOTAL NUMBER OF WORDS-1
        BEQ.B   WORD1                           | BR IF DST ALL IN ONE WORD
        SUBQ.W  #0x1,D6                         | --wordCnt
        BEQ.B   LONG1                           | BR IF DST ALL IN ONE LONG
        ADDQ.W  #0x1,D7                         | +1 row for first iter
        BRA.B   WIDE1                           | DST WIDER THAN ONE LONG
| Slow loop only taken in wierd cases where dst wider than a long.
MAIN1:
        MOVE.L  (A4),D0                         | GET SRC FROM BITMAP
        ADDQ.W  #0x2,A4                         | BUMP SRCPTR TO NEXT WORD
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D1,D0                           | MASK EXTRA TO ZEROS
        OR      D0,(A5)+                        | OR SRC INTO DST
        MOVEQ.L #-0x1,D1                        | FLUSH MASK
        DBRA    D2,MAIN1                        | LOOP TILL LAST WORD
        MOVE.L  (A4),D0                         | GET SRC FROM BITMAP
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D4,D0                           | MASK WITH RIGHTMASK
        OR      D0,(A5)                         | OR SRC INTO DST
        MOVE.L  -0x72(A6),A4                    | RESTORE SRCPTR TO LEFT
        ADDA.W  A2,A4                           | BUMP TO NEXT ROW
        MOVE.L  -0x76(A6),A5                    | RESTORE DSTPTR TO LEFT
        ADDA.W  A3,A5                           | BUMP DST TO NEXT ROW
WIDE1:
        MOVE.L  A4,-0x72(A6)                    | POINT TO START OF BUFFER
        MOVE.L  A5,-0x76(A6)                    | HOW MANY LONGS IN BUF
        MOVE    D3,D1                           | MASK:=LEFTMASK
        MOVE    D6,D2                           | GET WORDCOUNT
        DBRA    D7,MAIN1                        | LOOP ALL ROWS
        BRA.W    CHAR_BLT_DONE                  | QUIT IF CHARCOUNT <= 0
LONG1:
        SUBQ.W   #0x2,A3                        | adjust dstRow for one-long form
| Optimize if dst fits in one long. (30% of normal characters do)
| Called during boot.
LONG1A:
        MOVE.L  (A4),D0                         | GET SRC DATA
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D3,D0                           | MASK EXTRA WITH LEFTMASK
        OR      D0,(A5)+                        | OR RESULT INTO DST
        MOVE.L  2(A4),D0                        | GET SECOND WORD OF SRC
        LSR.L   D5,D0                           | ALIGN IT
        AND     D4,D0                           | MASK EXTRA WITH RIGHTMASK
        OR      D0,(A5)                         | OR RESULT INTO DST
        ADDA.W  A2,A4                           | BUMP SRCPTR TO NEXT ROW
        ADDA.W  A3,A5                           | BUMP DSTPTR TO NEXT ROW
        DBRA    D7,LONG1A                       | LOOP ALL ROWS
        BRA.W   CHAR_BLT_DONE                   | QUIT IF CHARCOUNT <= 0
WORD1:
        AND     D4,D3                           | COMBINE LEFT AND RIGHT MASKS
WORD1B:
        MOVE.L  (A4),D0                         | GET SRC DATA
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D3,D0                           | MASK EXTRA TO ZEROS
        OR      D0,(A5)                         | OR RESULT INTO DST
        ADDA.W  A2,A4                           | BUMP SRCPTR TO NEXT ROW
        ADDA.W  A3,A5                           | BUMP DSTPTR TO NEXT ROW
        DBRA    D7,WORD1B                       | LOOP ALL ROWS
CHAR_BLT_DONE:
        MOVEM.L (SP)+,D5/A1-A5                  | restore regs after blit
ADVANCE_CHARLOC:
        ANDI.W   #0xFF,D5                       | keep low byte (intWidth)
        ADD.B   12(A4),D5                       | + extra width byte
        ADD     D5,-0xA0(A6)                    | -0xA0(A6) += D5
CHARDONE:
        SUBQ.W  #0x1,20(A6)                     | decrement char count
        BGT.W   CLRLOOP_CONT_4                  | LOOP IF MORE CHARS LEFT
        MOVE    -0xA0(A6),D7                    | D7 = final charLoc.h
        SUB     8(A2),D7                        | - kernMax = pen.h after string
        TST.B   -0x66(A6)                       | fastFlag set?
        BEQ.B   CKBOLD                          | slow path -> styling
        JSR     FMQD_ShowCursor(PC)             | YES, RESTORE CURSOR
        BRA.W   NOSHAD_EXIT                     | fast path done -> exit
FORCE_STRDONE:
        CLR     20(A6)                          | zero count to abort loop
        BRA.B   ADVANCE_CHARLOC                 | AND QUIT
CKBOLD:
        CLR     D2                              | GET READY FOR BYTE
        MOVE.B  6(A4),D2                        | GET NUMBER OF OVERSTRIKES
        BRA.B   NXTBOLD                         | BOLD BUFFER IF ANY
BOLDIT:
        MOVE.L  -0x24(A6),A0                    | A0 = bufStart
        MOVE    -0x26(A6),D1                    | D1 = bufSize-1
        SUB     D0,D0                           | CLEAR X-BIT
BOLDLP:
        MOVE.L  (A0),D0                         | GET ONE LONG
        ROXR.L  #0x1,D0                         | ROTATE RIGHT WITH EXTEND
        OR.L    D0,(A0)+                        | OR BACK INTO BUFFER
        DBF     D1,BOLDLP                       | LOOP ENTIRE BUFFER
NXTBOLD:
        DBRA    D2,BOLDIT                       | LOOP FOR EACH OVERSTRIKE
        CLR     D2                              | GET READY FOR BYTE
        MOVE.B  7(A4),D2                        | DO WE NEED ITALIC ?
        BEQ.B   CHECKUL                         | NO, CONTINUE
        MOVE.L  -0x20(A6),A1                    | DSTPTR:=END OF BUFFER
        MOVE    -0x28(A6),D3                    | GET BUFFER ROWBYTES
        SUBA.W  D3,A1                           | BACK UP DSTPTR TO END OF 2ND ROW
        LSR     #0x1,D3                         | WORDCNT:=ROWBYTES DIV 2
        SUBQ.W  #0x1,D3                         | ADJUST BUFSIZE FOR DBF LOOP
        MOVE    -0x34(A6),D6                    | INIT ROW COUNTER
        CLR     D4                              | INIT OFFSET

| ----------------------------------------------------------
| NXTROW
NXTROW:
        ADD     D2,D4                           | OFFSET:=OFFSET+ITALIC
        MOVE    D4,D0                           | COPY OFFSET
        LSR     #0x4,D0                         | DELTA := OFFSET SCALED BY 16
        MOVEQ.L #0xF,D5                         | GET A 4-BIT MASK
        AND     D0,D5                           | SHIFTCNT:=DELTA MOD 16
        LSR     #0x4,D0                         | DELWORD:=DELTA DIV 16
        MOVE.L  A1,A0                           | SRCPTR:=DSTPTR
        SUBQ.W  #0x4,A0                         | BACK UP TWO WORDS
        SUB     D0,A0                           | SUBTRACT DELWORD
        SUB     D0,A0                           | TWICE BECAUSE WORDS
        MOVE    D3,D1                           | INIT LOOP TO WORDCNT
NXTWORD:
        MOVE.L  (A0),D0                         | GET A LONG OF SRC
        SUBQ.W  #0x2,A0                         | BACK UP SRC PTR ONE WORD
        LSR.L   D5,D0                           | SHIFT SRC TO ALIGN WITH DST
        MOVE    D0,-(A1)                        | STORE IN DST AND BUMP DSTPTR
        DBF     D1,NXTWORD                      | LOOP ALL WORDS THIS ROW
        DBF      D6,NXTROW                      | LOOP FOR ALL ROWS IN BUFFER
| Underline characters in buffer if necessary.
| Use characters in buffer to hide parts of the underline.
| Called during boot.
CHECKUL:
        TST.B   10(A4)                          | IS ULTHICK ZERO ?
        BEQ.W   NOTUL                           | YES, CONTINUE
        MOVE.L  -0x24(A6),A0                    | POINT TO BUFFER START
        MOVE    -0x28(A6),D1                    | GET BYTES PER ROW OF BUFFER
        MOVE    18(A2),D0                       | GET ASCENT
        MOVE    20(A2),D2                       | GET DESCENT
        MULU    D1,D0                           | ascent * rowBytes (offset)
        ADDA.L  D0,A0                           | POINT TO BASELINE ROW
        MOVE.L  A0,A1                           | SET BASELINE+1 PTR
        MOVE.L  A0,A2                           | SET BASELINE+2 PTR
        ADDA.W  D1,A1                           | POINT TO BASELINE+1
        CMPI    #0x2,D2                         | IS DESCENT LESS THAN 2?
        BLT.B   NOTUL                           | NO, SKIP UNDERLINE
        BEQ.B   ONLY2                           | ONLY USE 2 IF DESCENT=2
        ADDA.W  D1,A2                           | ADD ROWBYTES TO A2
        ADDA.W  D1,A2                           | POINT TO BASELINE+2
ONLY2:
        SUB     D1,SP                           | ALLOCATE TEMP SCANBUF
        MOVE.L  A3,-(SP)                        | SAVE GRAFPORT
        LEA.L   0x4(SP),A3                      | POINT TO START OF TEMP
        LSR     #0x2,D1                         | CONVERT BYTES TO LONGS
        SUBQ.W  #0x1,D1                         | ADJUST LONG COUNT FOR DBF
        MOVE    D1,D2                           | COPY LOOP COUNT
        SUB     D0,D0                           | CLEAR X-BIT
UL1:
        MOVE.L  (A0)+,D0                        | GET FROM BASELINE
        OR.L    (A1)+,D0                        | OR WITH BASELINE+1
        OR.L    (A2)+,D0                        | OR WITH BASELINE+2
        MOVE.L  D0,(A3)                         | PUT RESULT TO TEMP
        ROXR.L  #0x1,D0                         | SHIFT WITH CARRY
        OR.L    D0,(A3)+                        | OR INTO TEMP
        DBF     D1,UL1                          | LOOP ALL LONGS IN ROW
        MOVE.L  A1,A0                           | COPY END PTR
        SUB     D0,D0                           | CLEAR X-BIT
UL2:
        MOVE.L  -(A3),D0                        | COPY FROM BUF1 TO NEW BUF2
        ROXL.L  #0x1,D0                         | rotate left through X
        OR.L    (A3),D0                         | OR WITH TEMP
        NOT.L   D0                              | INVERT
        OR.L    D0,-(A1)                        | -(A1) |= D0
        DBRA    D2,UL2                          | LOOP ALL LONGS IN ROW
        MOVE.L  (SP)+,A3                        | RESTORE GRAFPORT
        MOVE    -0x28(A6),D0                    | D0 = bufRow
        LSL     #0x3,D0                         | *8 = pixel width of buffer
        ADD     -0x2A(A6),D0                    | + bufLeft
        SUB     D7,D0                           | CLEAR X-BIT
        SUBQ.W  #0x1,D0                         | -1 for DBRA
        LSR     #0x4,D0                         | /16 -> word count
        BRA.B   CLEAR_CKDDB_LOOP_DBF            | GO TO LOOP START

| Clear checked disk block table
CLEAR_CKDDB_LOOP:
        CLR     -(A0)                           | ERASE SOME UNDERLINE
CLEAR_CKDDB_LOOP_DBF:
        DBRA    D0,CLEAR_CKDDB_LOOP             | LOOP ALL FULL WORDS
        MOVE    D7,D0                           | SET SRC PTR TO END OF BUF2
        SUB     10(A3),D0                       | D0 = pen.h - portBits.left
        JSR     LeftMask(PC)                    | COMPUTE A MASK
        AND     D0,-(A0)                        | -(A0) &= D0
NOTUL:
        MOVE    #0xA,-0x5A(A6)                  | SAVE TO FAKEPTR
        MOVE.L  8(A3),-0x58(A6)                 | GET PORTBITS+BOUNDS+TOP
        MOVE.L  12(A3),-0x54(A6)                | SET FAKERGN BOTTOM/RIGHT BOUNDS
        LEA.L     -0x5A(A6),A0                  | GET ADDR OF FAKERGN
        MOVE.L  A0,-0x5E(A6)                    | POINT FAKE MASTERPTR TO IT
        LEA.L     -0x42(A6),A0                  | POINT TO SRCBITS
        MOVE.L  -0x24(A6),(A0)+                 | SET UP BASEADDR
        MOVE    -0x28(A6),(A0)+                 | SET UP ROWBYTES
        MOVE    -12(A6),(A0)+                   | SET UP BOUNDS TOP
        MOVE    -0x2A(A6),(A0)+                 | SET UP BOUNDS LEFT
        MOVE.L  -8(A6),(A0)+                    | SET UP BOUNDS BOTTOM AND RIGHT
        LEA.L     2(A3),A2                      | POINT TO PORTBITS
        LEA.L     -0x50(A6),A0                  | POINT TO DSTBITS
        MOVE.L  (A2)+,(A0)+                     | COPY BASEADDR
        MOVE    (A2)+,(A0)+                     | COPY ROWBYTES
        MOVE.L  (A2)+,(A0)+                     | COPY BOUNDS.TOPLEFT
        MOVE.L  (A2)+,(A0)+                     | COPY BOUNDS.BOTRIGHT
        CLR     D3                              | GET READY FOR BYTE
        MOVE.B  11(A4),D3                       | GET SHADOW COUNT
        BEQ.W   NOSHAD                          | SKIP IF NO SHADOWING
        MOVE    -0x28(A6),D0                    | GET 4 * NUMBER OF LONGS PER ROW
        SUBQ.W  #0x1,D0                         | ADJUST LONG COUNT FOR DBF
        CLR.L   -(SP)                           | ALLOW ONE LONG OF SLOP
        MOVE.L  SP,-0x32(A6)                    | REMEMBER END OF BUF2
CLR2:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR A LONG
        DBF     D0,CLR2                         | CLEAR 4 SCANLINES WORTH
        MOVE    -0x26(A6),D0                    | GET NUMBER OF LONGS IN BUF1
        SUBQ.W  #0x1,D0                         | ADJUST LONG COUNT FOR DBF
        MOVE.L  -0x20(A6),A0                    | POINT TO END OF BUF1
COPYLP:
        MOVE.L  -(A0),-(SP)                     | COPY FROM BUF1 TO NEW BUF2
        DBF     D0,COPYLP                       | COPY ALL OF BUF1
        MOVE.L  A7,-0x2E(A6)                    | REMEMBER START OF BUF2
        CLR.L   -(SP)                           | ALLOW ONE LONG OF SLOP
        ANDI    #0x3,D3                         | LIMIT SHADOW OFFSET TO 3
| Bold buf2 across to the right enough for shadow.
        MOVE    D3,D2                           | INIT BOLD COUNTER
COPYLP_LOOP:
        MOVE.L  -0x2E(A6),A0                    | A0 = buf2 start
        MOVE    -0x26(A6),D1                    | D1 = bufSize-1 longs
        SUB     D0,D0                           | CLEAR X-BIT
ACROSS2:
        MOVE.L  (A0),D0                         | GET A LONG FROM BUF2
        ROXR.L  #0x1,D0                         | rotate right through X
        OR.L    D0,(A0)+                        | OR IT BACK INTO BUFFER
        DBRA    D1,ACROSS2                      | LOOP FOR ALL LONGS
        DBRA    D2,COPYLP_LOOP                  | BOLD RIGHT 2,3, OR 4 TIMES
        MOVE.L  -0x2E(A6),A2                    | GET LIMIT POINTER
DOWN1:
        MOVE.L  -0x32(A6),A1                    | DSTPTR:=END OF BUF2
| Bold BUF2 down enough for shadow.
        MOVE.L  A1,A0                           | SET SRC PTR TO END OF BUF2
        SUBA    -0x3E(A6),A0                    | SUBTRACT ROWBYTES TO POINT TO LINE ABOVE
DOWN2:
        MOVE.L  -(A0),D0                        | GET A LONG FROM LINE ABOVE
        OR.L    D0,-(A1)                        | -(A1) |= D0
        CMPA.L  A2,A0                           | reached buf2 start?
        BGT.B   DOWN2                           | loop until at start
        DBRA    D3,DOWN1                        | BOLD DOWN 2,3, OR 4 TIMES
        MOVE.L  A2,-0x42(A6)                    | srcBits.baseAddr = buf2
        ADDQ.W  #0x4,-0x38(A6)                  | -0x38(A6) += 0x4
        MOVE.L  -12(A6),-0x90(A6)               | srcRect.topLeft = textRect.topLeft
        MOVE.L  -8(A6),-0x8C(A6)                | srcRect.botRight = textRect.botRight
        ADDQ.W  #0x4,-0x8C(A6)                  | -0x8C(A6) += 0x4
        MOVE.L  -0x90(A6),-0x98(A6)             | dstRect.topLeft = srcRect.topLeft
        MOVE.L  -0x8C(A6),-0x94(A6)             | dstRect.botRight = srcRect.botRight
        SUBQ.W  #0x1,-0x98(A6)                  | dstRect.top -= 1 (shadow)
        SUBQ.W  #0x1,-0x96(A6)                  | dstRect.left -= 1 (shadow)
        SUBQ.W  #0x1,-0x94(A6)                  | dstRect.bottom -= 1 (shadow)
        SUBQ.W  #0x1,-0x92(A6)                  | dstRect.right -= 1 (shadow)
        TST.B   -0x78(A6)                       | stretching?
        BEQ.B   DOWN2_NOMAP                     | no -> skip MapRect
        PEA.L     -0x98(A6)                     | push @dstRect
        PEA.L     -0x80(A6)                     | push @fromRect
        PEA.L     -0x88(A6)                     | push @toRect
        JSR     MapRect(PC)                     | THEN MAPPED FOR SCALING
DOWN2_NOMAP:
        PEA.L     -0x42(A6)                     | PUSH SRCBITS
        PEA.L     -0x50(A6)                     | PUSH DSTBITS
        PEA.L     -0x90(A6)                     | PUSH SRCRECT
        PEA.L     -0x98(A6)                     | PUSH DSTRECT
        MOVEQ.L #0x3,D0                         | mask = 3 (modes 0..3)
        AND     0x48(A3),D0                     | GET TEXTMODE MOD 7
        MOVE    D0,-(SP)                        | PUSH SHADOW MODE
        MOVE.L  28(A3),-(SP)                    | PUSH CLIPRGN HANDLE
        MOVE.L  24(A3),-(SP)                    | PUSH VISRGN HANDLE
        PEA.L     -0x5E(A6)                     | PUSH FAKE HANDLE
        JSR     StretchBits(PC)                 | TRANSFER BUFFER TO SCREEN
        MOVE.L  -0x24(A6),-0x42(A6)             | GET BUFSTART
        SUBQ.W  #0x4,-0x38(A6)                  | RESTORE SRCBITS BOUNDS BOTTOM
NOSHAD:
        PEA.L     -0x42(A6)                     | PUSH SRCBITS
        PEA.L     -0x50(A6)                     | PUSH DSTBITS
        PEA.L     -12(A6)                       | PUSH SRCRECT = TEXTRECT
        PEA.L     -20(A6)                       | PUSH DSTRECT = TEXTR2
        MOVE    0x48(A3),D0                     | PUSH TEXTMODE
        TST.B   11(A4)                          | ARE WE USING SHADOW ?
        BEQ.B   DOWN2_REGULAR                   | NO, CONTINUE
        NEG     D0                              | invert mode for shadow pass
DOWN2_REGULAR:
        ANDI    #0x3,D0                         | mask mode to 0..3
        MOVE    D0,-(SP)                        | push transfer mode
        MOVE.L  28(A3),-(SP)                    | PUSH DV (-128..127)
        MOVE.L  24(A3),-(SP)                    | PUSH VISRGN HANDLE
        PEA.L     -0x5E(A6)                     | push @fakeMaster (rectRgn)
        JSR     StretchBits(PC)                 | TRANSFER BUFFER TO SCREEN
NOSHAD_EXIT:
        MOVE.L  -0x4(A6),SP                     | STRIP BUFFER
        MOVEM.L (SP)+,D0-D7/A1-A4               | RESTORE REGS
        UNLK    A6                              | TEAR DOWN STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xE,SP                         | POP 14 BYTES OF PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER
