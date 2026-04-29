| ------------------------------------------------------------------
|
| --> STRETCH.TEXT
|

| .PROC StretchBits,8
| .REF RgnBlt,RSect,ShieldCursor,ShowCursor
| .REF InitRgn,SeekRgn,SetupStretch,ColorMap,XorSlab
| --------------------------------------------------------------
| PROCEDURE StretchBits(srcBits,dstBits: BitMap;
| srcRect,dstRect: Rect;
| mode: INTEGER
| rgnA,rgnB,rgnC: RgnHandle);
| Transfer a rectangle of bits from srcBits to dstBits,
| stretching or compressing according to srcRect and dstRect.
| The transfer is clipped to the intersection of rgnA, rgnB, and rgnC.
| Restrictions:
| transfer mode 0..7 only.
| if numer <> denom, then src and dst bitmaps do not overlap.
| COPYRIGHT APPLE COMPUTER INC.
| DESIGNED AND WRITTEN BY BILL ATKINSON
| Called during boot.
|
StretchBits:
        LINK    A6,#-0x94                       | set up stack frame
        MOVEM.L D0-D7/A1-A4,-(SP)               | SAVE REGS
        MOVE.L  SP,-0x6C(A6)                    | REMEMBER SAVESTK
        MOVE.L  22(A6),A0                       | point to dstRect
        MOVE    4(A0),D0                        | dstRect.bottom
        SUB     (A0),D0                         | dstHeight := bot - top
        SWAP    D0                              | move dstHeight to hi word
        MOVE    6(A0),D0                        | dstRect.right
        SUB     2(A0),D0                        | dstWidth := right - left
        MOVE.L  26(A6),A0                       | point to srcRect
        MOVE    4(A0),D1                        | srcRect.bottom
        SUB     (A0),D1                         | srcHeight := bot - top
        SWAP    D1                              | move srcHeight to hi word
        MOVE    6(A0),D1                        | srcRect.right
        SUB     2(A0),D1                        | srcWidth := right - left
        CMP.L   D0,D1                           | same size? (no stretch)
        BNE.B   STRETCHBITS_CONT                | NO, CONTINUE
XRGNBLT:
        MOVE.L  0x22(A6),-(SP)                  | PUSH SRCBITS
        MOVE.L  30(A6),-(SP)                    | PUSH DSTBITS
        MOVE.L  26(A6),-(SP)                    | PUSH SRCRECT
        MOVE.L  22(A6),-(SP)                    | PUSH DSTRECT
        MOVE    20(A6),-(SP)                    | PUSH MODE
        MOVE.L  -0x94(A6),-(SP)                 | PAT ONLY USED FROM BELOW
        MOVE.L  16(A6),-(SP)                    | PUSH RGNA
        MOVE.L  12(A6),-(SP)                    | PUSH RGNB
        MOVE.L  8(A6),-(SP)                     | PUSH RGNC
        JSR     RgnBlt(PC)                      | CALL RGNBLT
        JMP     STRETCHBITS_GOHOME(PC)          | skip stretch path
STRETCHBITS_CONT:
        MOVE    20(A6),-(SP)                    | push MODE
        MOVE.L  -0x94(A6),-(SP)                 | push PAT addr
        JSR     ColorMap(PC)                    | XORSCAN(PTRB,SCANB,TEMPSCAN)
        MOVE.L  (SP)+,-0x94(A6)                 | pop new PAT
        MOVE    (SP)+,D2                        | pop new mode
        MOVE    D2,D3                           | copy mode for test
        ANDI    #0x8,D3                         | test bit 3 (PATCOPY mask)
        BNE.B   XRGNBLT                         | if PATCOPY use XRGNBLT
        MOVE    D2,20(A6)                       | update mode in frame
        MOVE.L  D0,-4(A6)                       | save dst dimensions
        MOVE.L  D1,-8(A6)                       | save src dimensions
        MOVE.L  30(A6),A3                       | A3 := dstBits
        MOVE.L  22(A6),-(SP)                    | PUSH CASE JUMP
        PEA.L     6(A3)                         | push dstBits.bounds
        MOVE.L  16(A6),A0                       | POINT TO OUTPUT SCAN
        MOVE.L  (A0),A0                         | dereference rgnC
        PEA.L     2(A0)                         | push rgnC bbox
        MOVE.L  12(A6),A0                       | GET RGNA MASTER
        MOVE.L  (A0),A0                         | dereference rgnA
        PEA.L     2(A0)                         | push rgnA bbox
        MOVE.L  8(A6),A0                        | GET RGNB MASTER
        MOVE.L  (A0),A0                         | dereference rgnB
        PEA.L     2(A0)                         | push rgnB bbox
        MOVE    #0x5,-(SP)                      | push nRects = 5
        PEA.L     -20(A6)                       | push dst rect addr
        JSR     RSect(PC)                       | intersect 5 rects
        BEQ.W   STRETCHBITS_GOHOME              | quit if intersection empty
        PEA.L     -20(A6)                       | push intersection rect
STRETCHBITS_CONT_2:
        MOVE.L  6(A3),-(SP)                     | push dstBits.bounds.topLeft
        JSR     DrawControls(PC)                | GROW POINT BUFFER
        MOVE.L  22(A6),A0                       | GET RGNA MASTER
        MOVE    6(A0),D0                        | dstRect.right
        SUB     2(A0),D0                        | dstWidth
        MOVE    D0,-2(A6)                       | save dstWidth local
        MOVE    4(A0),D0                        | dstRect.bottom
        SUB     (A0),D0                         | dstHeight
        MOVE    D0,-4(A6)                       | save dstHeight local
        MOVE.L  26(A6),A0                       | GET RGNB MASTER
        MOVE    6(A0),D0                        | srcRect.right
        SUB     2(A0),D0                        | srcWidth
        MOVE    D0,-6(A6)                       | save srcWidth local
        MOVE    4(A0),D0                        | srcRect.bottom
        SUB     (A0),D0                         | srcHeight
        MOVE    D0,-8(A6)                       | save srcHeight local
        MOVE    -6(A6),D0                       | get srcWidth
        SUBQ.W  #0x1,D0                         | srcWidth - 1
        LSR     #0x5,D0                         | /32 -> longwords
        MOVE    D0,-30(A6)                      | save src buf longword count
        CLR.L   -(SP)                           | reserve src buffer space
CLRSRC:
        CLR.L   -(SP)                           | zero next src long
        DBRA    D0,CLRSRC                       | loop for srcWidth/32 longs
        MOVE.L  SP,-24(A6)                      | SAVE SRCBUF PTR
        MOVE    -2(A6),D0                       | get dstWidth
        SUBQ.W  #0x1,D0                         | dstWidth - 1
        LSR     #0x5,D0                         | /32 -> longwords
        MOVE    D0,-0x20(A6)                    | save dst buf longword count
        CLR.L   -(SP)                           | zero pad longword
        CLR.L   -(SP)                           | zero pad longword
CLRDST:
        CLR.L   -(SP)                           | zero next dst long
        DBRA    D0,CLRDST                       | loop for dstWidth/32 longs
        MOVE.L  SP,-28(A6)                      | SAVE DSTBUF PTR
        MOVE.L  22(A6),A0                       | GET BUFHANDLE
        MOVE    2(A0),D1                        | dstRect.left
        SUB     8(A3),D1                        | local-relative left
        ANDI    #-0x10,D1                       | align to word boundary
        ADD     8(A3),D1                        | restore frame origin
        MOVE    D1,-0x74(A6)                    | save bufLeft
        MOVE    -14(A6),D0                      | get dstHeight
        SUB     D1,D0                           | dstHeight - bufLeft
        LSR     #0x5,D0                         | /32 -> longwords
        MOVE    D0,-0x76(A6)                    | save mask buf longword count
CLRDST_LOOP:
        CLR.L   -(SP)                           | zero next mask long
        DBRA    D0,CLRDST_LOOP                  | loop for mask longs
        MOVE.L  SP,-0x72(A6)                    | SAVE MASKBUF PTR
        MOVE    #-0x7FFF,-0x2A(A6)              | init STATEA.thisV = -inf
        MOVE    #-0x7FFF,-0x42(A6)              | init STATEB.thisV = -inf
        MOVE    #-0x7FFF,-0x5A(A6)              | init STATEC.thisV = -inf
        MOVE    #0x7FFF,-0x28(A6)               | init STATEA.nextV = +inf
        MOVE    #0x7FFF,-0x40(A6)               | init STATEB.nextV = +inf
        MOVE    #0x7FFF,-0x58(A6)               | init STATEC.nextV = +inf
        CLR     -0x6E(A6)                       | clear rgnFlags
        MOVE.L  16(A6),A0                       | GET BUFHANDLE
        MOVE.L  (A0),A0                         | dereference rgnA
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR ?
        BEQ.B   CLRDST_CONT                     | YES, QUIT
        ADDQ.W  #0x2,-0x6E(A6)                  | -0x6E(A6) += 0x2
        LEA.L     -0x38(A6),A1                  | A1 := STATEA addr
        MOVE    -18(A6),D0                      | D0 := minH
        MOVE    -14(A6),D1                      | D1 := maxH
        MOVE    -0x74(A6),D2                    | D2 := bufLeft
        JSR     InitRgn(PC)                     | INIT STATEA, ALLOC BUFFER
CLRDST_CONT:
        MOVE.L  12(A6),A0                       | get rgnB handle
        MOVE.L  (A0),A0                         | dereference rgnB
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR ?
        BEQ.B   CLRDST_CONT_2                   | SKIP IF NOT TRUE
        ADDQ.W  #0x4,-0x6E(A6)                  | -0x6E(A6) += 0x4
        LEA.L     -0x50(A6),A1                  | A1 := STATEB addr
        MOVE    -18(A6),D0                      | D0 := minH
        MOVE    -14(A6),D1                      | D1 := maxH
        MOVE    -0x74(A6),D2                    | D2 := bufLeft
        JSR     InitRgn(PC)                     | INIT STATEB, ALLOC BUFFER
CLRDST_CONT_2:
        MOVE.L  8(A6),A0                        | get rgnC handle
        MOVE.L  (A0),A0                         | dereference rgnC
        CMPI    #0xA,(A0)                       | IS REGION RECTANGULAR ?
        BEQ.B   CLRDST_CONT_3                   | SKIP IF NOT TRUE
        ADDQ.W  #0x8,-0x6E(A6)                  | -0x6E(A6) += 0x8
        LEA.L     -0x68(A6),A1                  | A1 := STATEC addr
        MOVE    -18(A6),D0                      | D0 := minH
        MOVE    -14(A6),D1                      | D1 := maxH
        MOVE    -0x74(A6),D2                    | D2 := bufLeft
        JSR     InitRgn(PC)                     | INIT STATEC, ALLOC BUFFER
CLRDST_CONT_3:
        TST     -0x6E(A6)                       | any non-rect regions?
        BNE.B   CLRDST_NO                       | AND LOOP ENTIRE SCAN
        MOVE.L  -0x72(A6),A0                    | A0 := mask buffer
        MOVE    -18(A6),D3                      | D3 := minH
        SUB     -0x74(A6),D3                    | make buffer relative
        MOVE    -14(A6),D4                      | D4 := maxH
        SUB     -0x74(A6),D4                    | make buffer relative
        JSR     XorSlab(PC)                     | draw rect mask scanline
CLRDST_NO:
        CLR.L   D7                              | clear xor mask
        MOVE    20(A6),D2                       | get MODE
        BMI.W   STRETCHBITS_DONE                | negative mode: quit
        BCLR    #0x2,D2                         | test/clear srcXor bit
        BEQ.B   CLRDST_CONT_4                   | YES, QUIT
        NOT.L   D7                              | xorMask := -1
CLRDST_CONT_4:
        CMPI    #0x7,D2                         | mode > 7?
        BGT.W   STRETCHBITS_DONE                | YES, BUMP SOME MORE
        MOVE    D2,D0                           | copy mode
        ANDI    #0x3,D0                         | extract low 2 bits
        ADD     D0,D2                           | index = mode*2 + flags
        LEA     STRETCH_RGN_TBL(PC),A0          | A0 := STRETCH_RGN_TBL
        ADDA.W  0(A0,D2.W),A0                   | D2.W),A0 += 0(A0
        MOVE.L  A0,-0x90(A6)                    | save mode-specific row proc
        MOVE.L  0x22(A6),A2                     | A2 := dstBits ptr
        MOVE    4(A2),D0                        | dstBits.rowBytes
        EXT.L    D0                             | extend rowBytes to long
        MOVE.L  D0,-0x82(A6)                    | save dstRow
        MOVE    10(A2),D1                       | dstBits.bounds.bottom
        SUB     6(A2),D1                        | vert offset := bot - top
        MULU    D0,D1                           | x rowBytes
        ADD.L   (A2),D1                         | add baseAddr
        ADDQ.L  #0x2,D1                         | skip 2 bytes
        MOVE.L  D1,-0x8A(A6)                    | save dstLimit
        MOVE.L  26(A6),A0                       | GET VAR ADDR OF PTCOUNT
        MOVE    2(A0),D1                        | dstRect.left
        SUB     8(A2),D1                        | convert to global
        MOVE    D1,D5                           | copy delta horiz
        NEG     D5                              | negate
        ANDI    #0xF,D5                         | mod 16 for srcShift
        MOVE    (A0),D0                         | GET PTCOUNT
        SUB     6(A2),D0                        | rect top - bounds top
        MULU    4(A2),D0                        | D0 = D0 *u 4(A2)
        MOVE.L  (A2),A0                         | dstBits.baseAddr
        ADDA.L  D0,A0                           | add vertical offset
        ADD     D5,D1                           | + srcShift
        ASR     #0x4,D1                         | /16 (dots->words)
        ADDA.W  D1,A0                           | x2 (words->bytes) part 1
        ADDA.W  D1,A0                           | x2 (words->bytes) part 2
        MOVE.L  A0,-0x7A(A6)                    | save dstAddr
        MOVE    4(A3),D0                        | srcBits.rowBytes
        EXT.L    D0                             | extend rowBytes to long
        MOVE.L  D0,-0x86(A6)                    | save srcRow
        MOVE.L  22(A6),A0                       | A0 := dstRect addr
        MOVE    (A0),-0x8C(A6)                  | save current vertical
        MOVE    2(A0),D1                        | dstRect.left
        SUB     8(A3),D1                        | srcBits.bounds.left adjust
        MOVEQ.L #0xF,D6                         | mask = 0xF
        AND     D1,D6                           | srcShift := delta mod 16
        MOVE    -20(A6),D0                      | get clip top
        SUB     6(A3),D0                        | srcBits.bounds.top adjust
        MULU    4(A3),D0                        | D0 = D0 *u 4(A3)
        MOVE.L  (A3),A0                         | srcBits.baseAddr
        ADDA.L  D0,A0                           | add vertical offset
        ASR     #0x4,D1                         | /16 (dots->words)
        ADDA.W  D1,A0                           | x2 (words->bytes) part 1
        ADDA.W  D1,A0                           | x2 (words->bytes) part 2
        MOVE.L  A0,-0x7E(A6)                    | save srcAddr
        MOVE    -8(A6),D0                       | get srcHeight
        LSR     #0x1,D0                         | /2
        NEG     D0                              | vError init = -srcHeight/2
        MOVE    D0,-12(A6)                      | save vertical error
| -----------------------------------------------------
| GET FIRST SCANLINE OF SRC INTO SRCBUF
| Called during boot.
NEXTSRC:
        MOVE.L  -0x7A(A6),A0                    | GET DST ROWBYTES
        CMPA.L  -0x8A(A6),A0                    | dstAddr < dstLimit?
        BCC.W   STRETCHBITS_DONE                | past limit, finish
        MOVE.L  -24(A6),A1                      | A1 := srcBuf ptr
        MOVE    -30(A6),D1                      | D1 := srcBuf longwords - 1
NEXTSRC_LOOP:
        MOVE.L  -2(A0),D0                       | grab 32-bit word at offset
        LSR.L   D5,D0                           | shift to align src
        MOVE    D0,(A1)+                        | store low word
        MOVE.L  (A0)+,D0                        | grab next 32 bits
        LSR.L   D5,D0                           | shift to align
        MOVE    D0,(A1)+                        | store low word
        DBRA    D1,NEXTSRC_LOOP                 | loop for srcBuf width
        MOVE.L  -0x82(A6),D2                    | D2 := dstRow
        ADD.L   D2,-0x7A(A6)                    | -0x7A(A6) += D2
        MOVE    -4(A6),D0                       | get dstHeight
        ADD     D0,-12(A6)                      | -12(A6) += D0
        BGT.B   SRCLOOP_EXIT                    | vError went positive: emit row
SRCLOOP:
        MOVE.L  -0x7A(A6),A0                    | reload dstAddr
        CMPA.L  -0x8A(A6),A0                    | dstAddr < dstLimit?
        BCC.W   SRCLOOP_EXIT                    | past limit, finish
        MOVE.L  -24(A6),A1                      | A1 := srcBuf ptr
        MOVE    -30(A6),D1                      | D1 := srcBuf longwords - 1
SRCLOOP_LOOP:
        MOVE.L  -2(A0),D0                       | grab 32-bit word
        LSR.L   D5,D0                           | shift to align src
        OR      D0,(A1)+                        | OR into srcBuf (compress)
        MOVE.L  (A0)+,D0                        | grab next 32 bits
        LSR.L   D5,D0                           | shift to align
        OR      D0,(A1)+                        | OR into srcBuf (compress)
        DBRA    D1,SRCLOOP_LOOP                 | loop for srcBuf width
        ADD.L   D2,-0x7A(A6)                    | -0x7A(A6) += D2
        MOVE    -4(A6),D0                       | get dstHeight
        ADD     D0,-12(A6)                      | -12(A6) += D0
        BLE.B   SRCLOOP                         | DO NOTHING IF NO POINTS
SRCLOOP_EXIT:
        MOVE.L  -24(A6),-(SP)                   | push srcBuf
        MOVE.L  -28(A6),-(SP)                   | push dstBuf
        MOVE    -0x20(A6),-(SP)                 | STRIP BUFFER
        MOVE    -2(A6),-(SP)                    | push dstWidth
        MOVE    -6(A6),-(SP)                    | push srcWidth
        JSR     STRETCH_ROW(PC)                 | stretch one scan row
STRETCHBITS_NXTMASK:
        MOVE    -0x8C(A6),D0                    | get current vertical
        CMP     -20(A6),D0                      | jump via A0
        BLT.B   NEXTDST_SKIP                    | < clip top: just bump
        JSR     STRETCHBITS_GOHOME_CONT(PC)     | advance regions to V
        MOVE.L  -28(A6),A3                      | A3 := dstBuf ptr
        MOVE.L  -0x7E(A6),A4                    | A4 := dstAddr (real bitmap)
        MOVE.L  -0x72(A6),A2                    | A2 := mask buffer
        MOVE    -0x76(A6),D2                    | D2 := mask longwords-1
        MOVE.L  -0x90(A6),A0                    | A0 := mode-specific row proc
        JMP     (A0)                            | RTS
NEXTDST:
        MOVE.L  -0x86(A6),D0                    | get dst rowBytes
        ADD.L   D0,-0x7E(A6)                    | -0x7E(A6) += D0
NEXTDST_SKIP:
        ADDQ.W  #0x1,-0x8C(A6)                  | CURRENT VERT := CURRENT VERT + 1
        MOVE    -0x8C(A6),D0                    | GET VERT
        CMP     -16(A6),D0                      | IS VERT >= MINRECT BOTTOM ?
        BEQ.B   STRETCHBITS_DONE                | YES, QUIT
        MOVE    -8(A6),D0                       | GET DENOM.V
        SUB     D0,-12(A6)                      | -12(A6) -= D0
        BGE.B   STRETCHBITS_NXTMASK             | IF VERROR >= 0 THEN DRAW MORE
        BRA.W   NEXTSRC                         | GO TO LOOP START
STRETCHBITS_DONE:
        JSR     FMQD_ShowCursor(PC)             | CALL RGNBLT
STRETCHBITS_GOHOME:
        MOVE.L  -0x6C(A6),SP                    | SP := saveSP
        MOVEM.L (SP)+,D0-D7/A1-A4               | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0x1E,SP                        | pop parameter bytes from stack
        JMP     (A0)                            | RTS
STRETCHBITS_GOHOME_CONT:
        MOVE    -0x6E(A6),D0                    | D0 = handler index
        .short  0x303B, 0x0006                  | MOVE.W STRETCHBITS_GOHOME_CONT_2(PC,D0.W),D0
        .short  0x4EFB, 0x0002                  | JMP STRETCHBITS_GOHOME_CONT_2(PC,D0.W)
STRETCHBITS_GOHOME_CONT_2:                      | 8-entry jump-offset table
        .short  0x0010                          | mode 0
        .short  0x0012                          | mode 1
        .short  0x0026                          | mode 2
        .short  0x004E                          | mode 3
        .short  0x003A                          | mode 4
        .short  0x0084                          | mode 5
        .short  0x00BA                          | mode 6
        .short  0x00F0                          | mode 7
        RTS                                     | return to caller
        MOVE    -0x8C(A6),D0                    | D0 := rgnBufLen
        LEA.L     -0x38(A6),A1                  | A1 = &rgnA
        MOVE.L  -0x72(A6),8(A1)                 | 8(A1) := scanLineBuf
        JSR     SeekRgn(PC)                     | CALC CASEJUMP AND HORIZ FRACT
        RTS                                     | return to caller
        MOVE    -0x8C(A6),D0                    | D0 := rgnBufLen
        LEA.L     -0x50(A6),A1                  | A1 = &rgnB
        MOVE.L  -0x72(A6),8(A1)                 | 8(A1) := scanLineBuf
        JSR     SeekRgn(PC)                     | ALTER FOR COLOR SEPARATION
        RTS                                     | return to caller
        MOVE    -0x8C(A6),D0                    | D0 := rgnBufLen
        LEA.L     -0x68(A6),A1                  | A1 = &rgnC
        MOVE.L  -0x72(A6),8(A1)                 | 8(A1) := scanLineBuf
        JSR     SeekRgn(PC)                     | INTERSECT ALL RECTS
        RTS                                     | return to caller
        MOVE    -0x8C(A6),D0                    | D0 := rgnBufLen
        LEA.L     -0x38(A6),A1                  | A1 = &rgnA
        JSR     SeekRgn(PC)                     | REMOVE CURSOR IF INTERSECT
        MOVE    D1,-(SP)                        | push D1
        LEA.L     -0x50(A6),A1                  | A1 = &rgnB
        JSR     SeekRgn(PC)                     | AND XOR BETWEEN THEM
        OR      (SP)+,D1                        | D1 := D1 OR (SP)+
        BEQ.B   RGN_AND_AB_DONE                 | SKIP IF NOT INVERTED
        MOVE.L  -0x30(A6),A0                    | A0 := rgnBufA_ptr
        MOVE.L  -0x48(A6),A1                    | A1 := rgnBufB_ptr
        MOVE.L  -0x72(A6),A2                    | A2 := scanLineBuf
        MOVE    -0x76(A6),D1                    | D1 := wordCnt
RGN_AND_AB:
        MOVE.L  (A0)+,D0                        | GET A SECOND LONG
        AND.L   (A1)+,D0                        | D0 := D0 AND (A1)+
        MOVE.L  D0,(A2)+                        | (A2)+ := D0
        DBRA    D1,RGN_AND_AB                   | LOOP FOR ALL LONGS
RGN_AND_AB_DONE:
        RTS                                     | return to caller
        MOVE    -0x8C(A6),D0                    | D0 := rgnBufLen
        LEA.L     -0x38(A6),A1                  | A1 = &rgnA
        JSR     SeekRgn(PC)                     | advance region to current scan row
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L     -0x68(A6),A1                  | A1 = &rgnC
        JSR     SeekRgn(PC)                     | advance region to current scan row
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   RGN_AND_AC_DONE                 | NO, WE'RE DONE
        MOVE.L  -0x30(A6),A0                    | A0 := rgnBufA_ptr
        MOVE.L  -0x60(A6),A1                    | A1 := rgnBufC_ptr
        MOVE.L  -0x72(A6),A2                    | A2 := scanLineBuf
        MOVE    -0x76(A6),D1                    | D1 := wordCnt
RGN_AND_AC:
        MOVE.L  (A0)+,D0                        | D0 := (A0)+
        AND.L   (A1)+,D0                        | D0 := D0 AND (A1)+
        MOVE.L  D0,(A2)+                        | (A2)+ := D0
        DBRA    D1,RGN_AND_AC                   | loop D1 -> RGN_AND_AC
RGN_AND_AC_DONE:
        RTS                                     | return to caller
        MOVE    -0x8C(A6),D0                    | D0 := rgnBufLen
        LEA.L     -0x50(A6),A1                  | A1 = &rgnB
        JSR     SeekRgn(PC)                     | advance region to current scan row
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L     -0x68(A6),A1                  | A1 = &rgnC
        JSR     SeekRgn(PC)                     | advance region to current scan row
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   RGN_AND_BC_DONE                 | NO, WE'RE DONE
        MOVE.L  -0x48(A6),A0                    | A0 := rgnBufB_ptr
        MOVE.L  -0x60(A6),A1                    | A1 := rgnBufC_ptr
        MOVEA.L  -114(FP),A2                    | A2 := scanLineBuf
        MOVE.W   -118(FP),D1                    | D1 := wordCnt
RGN_AND_BC:
        MOVE.L   (A0)+,D0                       | D0 := (A0)+
        AND.L   (A1)+,D0                        | D0 := D0 AND (A1)+
        MOVE.L  D0,(A2)+                        | (A2)+ := D0
        DBRA    D1,RGN_AND_BC                   | loop D1 -> RGN_AND_BC
RGN_AND_BC_DONE:
        RTS                                     | ALL 3 ARE RECT, DO NOTHING
        MOVE    -0x8C(A6),D0                    | D0 := rgnBufLen
        LEA.L     -0x38(A6),A1                  | A1 = &rgnA
        JSR     SeekRgn(PC)                     | advance region to current scan row
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L     -0x50(A6),A1                  | A1 = &rgnB
        JSR     SeekRgn(PC)                     | advance region to current scan row
        OR      D1,(SP)                         | (SP) |= D1
        LEA.L     -0x68(A6),A1                  | A1 = &rgnC
        JSR     SeekRgn(PC)                     | advance region to current scan row
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   RGN_AND_ABC_DONE                | NO, WE'RE DONE
        MOVE.L  -0x30(A6),A0                    | A0 := rgnBufA_ptr
        MOVE.L  -0x48(A6),A1                    | A1 := rgnBufB_ptr
        MOVE.L  -0x60(A6),A2                    | A2 := rgnBufC_ptr
        MOVE.L  -0x72(A6),A3                    | A3 := scanLineBuf
        MOVE    -0x76(A6),D1                    | D1 := wordCnt
RGN_AND_ABC:
        MOVE.L  (A0)+,D0                        | D0 := (A0)+
        AND.L   (A1)+,D0                        | D0 := D0 AND (A1)+
        AND.L   (A2)+,D0                        | D0 := D0 AND (A2)+
        MOVE.L  D0,(A3)+                        | (A3)+ := D0
        DBRA    D1,RGN_AND_ABC                  | loop D1 -> RGN_AND_ABC
RGN_AND_ABC_DONE:
        RTS                                     | return to caller
STRETCH_RGN_TBL:                                | 4-entry word-offset jump table
        .short  0x0008                          | entry 0 -> handler @ $A32E (fall-through)
        .short  0x002C                          | entry 1 -> handler @ $A352
        .short  0x0048                          | entry 2 -> handler @ $A36E
        .short  0x0064                          | entry 3 -> handler @ $A38A

| ----------------------------------------------------------
| STRETCHBLT_NEXT_COPY
| Called during boot.
STRETCHBLT_NEXT_COPY:
        MOVE.L  -2(A3),D0                       | FETCH NEXT DST WORD
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3)+,D1                        | GET SRC FROM BITMAP AND BUMP RIGHT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        MOVE.L  (A2)+,D1                        | GET MASK
        AND.L   D1,D0                           | MASK SRC
        NOT.L   D1                              | FORM NOTMASK
        AND.L   (A4),D1                         | GET DST DATA
        OR.L    D1,D0                           | MERGE WITH SRC DATA
        MOVE.L  D0,(A4)+                        | PUT RESULT IN DST
        DBRA    D2,STRETCHBLT_NEXT_COPY         | LOOP ALL LONGS THIS ROW
        BRA.W   NEXTDST                         | GO FOR NEXT ROW
STRETCHBLT_NEXT_OR:
        MOVE.L  -2(A3),D0                       | FETCH NEXT DST WORD
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3)+,D1                        | GET SRC FROM BITMAP
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A2)+,D0                        | AND WITH MASK
        OR.L    D0,(A4)+                        | OR RESULT INTO DST
        DBRA    D2,STRETCHBLT_NEXT_OR           | LOOP ALL LONGS THIS ROW
        BRA.W   NEXTDST                         | LOOP FOR NEXT ROW
STRETCHBLT_NEXT_XOR:
        MOVE.L  -2(A3),D0                       | FETCH NEXT DST WORD
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3)+,D1                        | GET SRC FROM BITMAP
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A2)+,D0                        | AND WITH MASK
        EOR.L   D0,(A4)+                        | XOR RESULT INTO DST
        DBRA    D2,STRETCHBLT_NEXT_XOR          | LOOP ALL LONGS THIS ROW
        BRA.W   NEXTDST                         | LOOP FOR NEXT ROW

| ----------------------------------------------------------
| STRETCHBLT_NEXT_BIC
STRETCHBLT_NEXT_BIC:
        MOVE.L  -2(A3),D0                       | FETCH NEXT DST WORD
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3)+,D1                        | GET SRC FROM BITMAP
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A2)+,D0                        | AND WITH MASK
        NOT.L   D0                              | INVERT FOR BIC
        AND.L   D0,(A4)+                        | BIC RESULT INTO DST
        DBRA    D2,STRETCHBLT_NEXT_BIC          | LOOP ALL LONGS THIS ROW
        BRA.W   NEXTDST                         | LOOP FOR NEXT ROW
XorSlab:
        MOVE    D3,D0                           | D0 := D3
        JSR     BitMask(PC)                     | call BitMask
        MOVE    D0,D5                           | D5 := D0
        MOVE    D4,D0                           | D0 := D4
        JSR     LeftMask(PC)                    | call LeftMask
        MOVE    D0,D6                           | D6 := D0
        ASR     #0x4,D3                         | D3 >>= 4 (arith)
        ADDA.W  D3,A0                           | A0 += D3
        ADDA.W  D3,A0                           | A0 += D3
        ASR     #0x4,D4                         | D4 >>= 4 (arith)
        SUB     D3,D4                           | D4 -= D3
        BGT.B   XORSLAB_NOTIN1                  | if signed > -> XORSLAB_NOTIN1
        AND     D5,D6                           | D6 := D6 AND D5
        EOR     D6,(A0)                         | (A0) ^= D6
        RTS                                     | return to caller
XORSLAB_NOTIN1:
        EOR     D5,(A0)+                        | (A0)+ ^= D5
        BRA.B   XORSLAB_INVLONG_CONT            | LOOP FOR NEXT ROW
XORSLAB_INVLONG:
        NOT.L   (A0)+                           | (A0)+ = ~(A0)+
XORSLAB_INVLONG_CONT:
        SUBQ.W  #0x2,D4                         | D4 -= #0x2
        BGT.B   XORSLAB_INVLONG                 | if signed > -> XORSLAB_INVLONG
        BLT.B   XORSLAB_ENDWORD                 | NO, BRANCH IF SHRINKING
        NOT     (A0)+                           | (A0)+ = ~(A0)+
XORSLAB_ENDWORD:
        EOR     D6,(A0)                         | (A0) ^= D6
        RTS                                     | return to caller
STRETCH_ROW:
        LINK    A6,#0x0                         | set up stack frame, reserve 0x0 locals
        MOVEM.L D0-D7/A1-A4,-(SP)               | save scratch regs to stack
        MOVE    10(A6),D3                       | D3 := 10(A6)
        BEQ.W   STRETCH_ROW_EXIT                | if zero -> STRETCH_ROW_EXIT
        MOVE    8(A6),D4                        | D4 := rgnC
        BEQ.W   STRETCH_ROW_EXIT                | if zero -> STRETCH_ROW_EXIT
        MOVE.L  18(A6),A0                       | A0 := 18(A6)
        MOVE.L  14(A6),A1                       | A1 := 14(A6)
        MOVE    12(A6),D0                       | D0 := rgnB
        ADDQ.W  #0x1,D0                         | D0 += #0x1
        LSL     #0x2,D0                         | D0 <<= 2
        MOVE.L  A1,A3                           | A3 := A1
        ADDA.W  D0,A3                           | A3 += D0
        MOVE    D3,D0                           | D0 := D3
        SUB     D4,D0                           | D0 -= D4
        BNE.B   STRETCH_SCALE                   | NO, USE GENERAL STRETCH
| -----------------------------------------------
| NUMERATOR = DENOMINATOR, JUST COPY LONGS
STRETCH_COPY:
        MOVE.L  (A0)+,(A1)+                     | COPY ONE LONG
        MOVE.L  (A0)+,(A1)+                     | COPY ANOTHER LONG
        CMPA.L  A3,A1                           | compare A1 with A3
        BCS.B   STRETCH_COPY                    | LOOP UNTIL DSTLIMIT
        BRA.W   STRETCH_ROW_EXIT                | jump to STRETCH_ROW_EXIT
STRETCH_SCALE:
        BGT.W   STRETCH_GROW                    | if signed > -> STRETCH_GROW
        ADD     D3,D0                           | D0 += D3
        ADD     D3,D0                           | D0 += D3
        BEQ.B   STRETCH_SHRINK_INIT             | if zero -> STRETCH_SHRINK_INIT
        BRA.W   STRETCH_GENGROW                 | jump to STRETCH_GENGROW
STRETCH_SHRINK_INIT:
        MOVE.L  #0xE0000000,D7                  | D7 := #0xE0000000
STRETCH_SHRINK_NEXT:
        MOVE.B  (A0)+,D0                        | GET SECOND BYTE FROM SRC
        LSL.L   #0x8,D0                         | D0 <<= 8
        MOVE.B  (A0)+,D0                        | GET A BYTE FROM SRC
        LSL.L   #0x8,D0                         | D0 <<= 8
        MOVE.B  (A0)+,D0                        | GET A BYTE FROM SRC
        LSL.L   #0x8,D0                         | D0 <<= 8
        MOVEQ.L #0x7,D2                         | D2 := #0x7
STRETCH_SHRINK_INNER:
        ADD.L   D7,D0                           | D0 += D7
        ADDX.W  D1,D1                           | D1 += D1 (with X bit)
        LSL.L   #0x3,D0                         | D0 <<= 3
        DBRA    D2,STRETCH_SHRINK_INNER         | loop D2 -> STRETCH_SHRINK_INNER
        MOVE.B  D1,(A1)+                        | (A1)+ := D1
        CMPA.L  A3,A1                           | compare A1 with A3
        BCS.B   STRETCH_SHRINK_NEXT             | if carry -> STRETCH_SHRINK_NEXT
        BRA.W   STRETCH_ROW_EXIT                | jump to STRETCH_ROW_EXIT
STRETCH_GROW:
        SUB     D4,D0                           | D0 -= D4
        BEQ.W   QRTR2_LOOP_2                    | if zero -> QRTR2_LOOP_2
        BRA.W   STRETCH_GENGROW                 | jump to STRETCH_GENGROW

| -----------------------------------------------
| DOUBLE USING TABLE LOOKUP
QRTR2_LOOP_2:
        MOVE.B  (A0)+,D0                        | DOUBLE: GET A BYTE FROM SRC
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        LSR.B   #0x4,D1                         | GET HI NIBBLE
        MOVE.B  NIBBLE_DOUBLE_TBL(PC,D1.W),(A1)+ | DOUBLE HI NIBBLE TO DST
        ANDI    #0xF,D0                         | GET LO NIBBLE
        MOVE.B  NIBBLE_DOUBLE_TBL(PC,D0.W),(A1)+ | DOUBLE LO NIBBLE TO DST
        CMPA.L  A3,A1                           | jump via A0
        BCS.B   QRTR2_LOOP_2                    | LOOP UNTIL DSTLIMIT
        BRA.W   STRETCH_ROW_EXIT                | jump to STRETCH_ROW_EXIT
NIBBLE_DOUBLE_TBL:                              | 16 bytes
        .byte   0x00, 0x03, 0x0C, 0x0F          | 0..3 doubled
        .byte   0x30, 0x33, 0x3C, 0x3F          | 4..7 doubled
        .byte   0xC0, 0xC3, 0xCC, 0xCF          | 8..11 doubled
        .byte   0xF0, 0xF3, 0xFC, 0xFF          | 12..15 doubled
| STRETCH_GENGROW - generate row-grow lookup for stretch-blit upscale
STRETCH_GENGROW:
        MOVE.L  #0x80000000,D0                  | D0 := #0x80000000
        MOVEQ.L #0x1,D1                         | D1 := #0x1
        MOVE    D4,D2                           | D2 := D4
        LSR     #0x1,D2                         | D2 >>= 1 (logical)
        NEG     D2                              | negate D2
STRETCH_GENGROW_2:
        ADD.L   D0,D0                           | D0 += D0
        BCC.B   STRETCH_GENGROW_3               | BR IF WHITE
        BNE.B   STRETCH_GENGROW_NO              | BR IF BLACK
        MOVE.L  (A0)+,D0                        | D0 := (A0)+
        ADDX.L  D0,D0                           | D0 += D0 (with X bit)
        BCS.B   STRETCH_GENGROW_NO              | BR IF BLACK
STRETCH_GENGROW_3:
        ADD     D3,D2                           | D2 += D3
        BLT.B   STRETCH_GENGROW_2               | if signed < -> STRETCH_GENGROW_2
        CLR     D5                              | clear D5
        BRA.B   STRETCH_GENGROW_5               | THEN QUIT
STRETCH_GENGROW_4:
        ADD.L   D0,D0                           | D0 += D0
        BNE.B   STRETCH_GENGROW_NO              | BRANCH IF BLACK
        MOVE.L  (A0)+,D0                        | D0 := (A0)+
        ADDX.L  D0,D0                           | D0 += D0 (with X bit)
STRETCH_GENGROW_NO:
        ADD     D3,D2                           | D2 += D3
        BLT.B   STRETCH_GENGROW_4               | if signed < -> STRETCH_GENGROW_4
        MOVEQ.L #0x1,D5                         | D5 := #0x1
STRETCH_GENGROW_5:
        ADD.L   D1,D1                           | D1 += D1
        BCC.B   STRETCH_GENGROW_6               | AND CONTINUE
        ADD     D5,D1                           | D1 += D5
        MOVE.L  D1,(A1)+                        | (A1)+ := D1
        CMPA.L  A3,A1                           | compare A1 with A3
        BCC.W   STRETCH_ROW_EXIT                | NO, LOOP MORE SRC
        MOVEQ.L #0x1,D1                         | D1 := #0x1
        BRA.B   STRETCH_GENGROW_7               | jump to STRETCH_GENGROW_7
STRETCH_GENGROW_6:
        ADD     D5,D1                           | D1 += D5
STRETCH_GENGROW_7:
        SUB     D4,D2                           | D2 -= D4
        BGT.B   STRETCH_GENGROW_5               | if signed > -> STRETCH_GENGROW_5
        BRA.B   STRETCH_GENGROW_2               | jump to STRETCH_GENGROW_2
STRETCH_ROW_EXIT:
        MOVEM.L (SP)+,D0-D7/A1-A4               | jump via A0
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0xE,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS
