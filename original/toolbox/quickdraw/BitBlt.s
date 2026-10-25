| ---------------------------------------------------------------
|
| --> BITBLT.TEXT
|
| Low-level bit boundary block transfer.
|

| ---------------------------------------------------------------
| --> BITBLT.TEXT
| Low-level bit boundary block transfer.
| .PROC BITBLT,7
| .REF LEFTMASK,RIGHTMASK,PatExpand
| --------------------------------------------------------------
| PROCEDURE BitBlt(srcBits,dstBits: BitMap;
| srcRect,dstRect: Rect;
| mode: INTEGER; pat: Pattern);
| TRANSFERS A RECTANGULAR BLOCK OF BITS WITH NO CLIPPING AT ALL.
| MODE SPECIFIES THE COMBINATION MODE AND WHETHER THE SOURCE SHOULD COME
| FROM THE SOURCE BITMAP OR FROM A REPEATING PATTERN.
| COPYRIGHT APPLE COMPUTER INC.
| WRITTEN BY BILL ATKINSON
| POSITION INDEPENDENT AND RE-ENTRANT, CLOBBERS ONLY A0.
| MODES: 0 SRC --> DST
| 1 SRC OR DST --> DST
| 2 SRC XOR DST --> DST
| 3 SRC BIC DST --> DST
| 4 (NOT SRC) --> DST
| 5 (NOT SRC) OR DST --> DST
| 6 (NOT SRC) XOR DST --> DST
| 7 (NOT SRC) BIC DST --> DST
| 8 PATTERN --> DST
| 9 PATTERN OR DST --> DST
| 10 PATTERN XOR DST --> DST
| 11 PATTERN BIC DST --> DST
| 12 (NOT PATTERN) --> DST
| 13 (NOT PATTERN) OR DST --> DST
| 14 (NOT PATTERN) XOR DST --> DST
| 15 (NOT PATTERN) BIC DST --> DST
| Called during boot.
BitBlt:
        LINK    A6,#-0x58                       | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | save scratch registers
        MOVE.L  A5,-0x58(A6)                    | save QD globals ptr in local
        MOVE.L  18(A6),A2                       | GET SRCV
        MOVE.L  14(A6),A3                       | GET HEIGHT
        MOVE.L  26(A6),A4                       | A4 = srcBits ptr
        MOVE.L  22(A6),A5                       | A5 = dstBits ptr
        MOVE    4(A3),D0                        | D0 = dstRect.bottom
        SUB     (A3),D0                         | D0 = height (bottom - top)
        BLE.W   GOHOME                          | height <= 0 -> nothing to draw
        MOVE    D0,-0x52(A6)                    | save height in local
        MOVEQ.L #0x2,D3                         | bump = +2 (left-to-right)
        MOVE    (A2),D0                         | D0 = srcRect.top
        SUB     6(A4),D0                        | convert srcTop to global coords
        MOVE    D0,-0x42(A6)                    | srcV = srcTop (global)
        MOVE    (A3),D0                         | D0 = dstRect.top
        SUB     6(A5),D0                        | convert dstTop to global coords
        MOVE    D0,-0x44(A6)                    | dstV = dstTop (global)
        MOVE    4(A4),-0x46(A6)                 | srcRow = srcBits.rowBytes
        MOVE    4(A5),-0x48(A6)                 | dstRow = dstBits.rowBytes
        CLR     D7                              | invertReg = 0 (not inverted)
        MOVE    12(A6),D0                       | D0 = transfer mode
        BTST    #0x2,D0                         | inverted-source mode bit?
        BEQ.B   MODEOK                          | not inverted -> continue
        NOT     D7                              | invertReg = -1 (inverted)
MODEOK:
        BTST    #0x3,D0                         | pattern mode bit?
        BEQ.B   DIREC                           | no -> direct src copy
        MOVE    8(A5),D2                        | D2 = dstLeft for pattern align
        MOVE.L  8(A6),A0                        | A0 = pattern parameter
        LEA.L     -0x40(A6),A1                  | A1 = expanded pattern slot (16 longs)
        MOVE.L  -0x58(A6),A5                    | A5 = QD globals (PatExpand needs it)
        JSR     PatExpand(PC)                   | expand 8-byte pattern -> 16 longs
        MOVE.L  22(A6),A5                       | restore A5 = dstBits
        MOVEQ.L #0xF,D7                         | treat coord mod 16
        AND     (A3),D7                         | D7 = dstTop & 15
        LSL     #0x2,D7                         | quad for longword indexing
        MOVE.L  -0x40(A6,D7.W),D6               | D6 = pattern word from expanded table
        BRA.B   GETSRC_CONT                     | skip src setup -> GETSRC_CONT

| ----------------------------------------------------------
| DIREC
| Called during boot.
DIREC:
        MOVE.L  (A4),D0                         | D0 = src baseAddr
        CMP.L   (A5),D0                         | same as dst baseAddr?
        BNE.B   GETSRC                          | different bitmaps -> no overlap risk
        MOVE    -0x42(A6),D0                    | D0 = srcV
        CMP     -0x44(A6),D0                    | srcV vs dstV
        BGT.B   GETSRC                          | srcV > dstV -> top-to-bottom OK
        BLT.B   UPSIDE                          | srcV < dstV -> upside-down copy
        MOVE    2(A2),D0                        | same V, get srcLeft
        SUB     8(A4),D0                        | convert srcLeft to global
        MOVE    2(A3),D1                        | get dstLeft
        SUB     8(A5),D1                        | convert dstLeft to global
        CMP     D1,D0                           | srcLeft vs dstLeft
        BGE.B   GETSRC                          | srcLeft >= dstLeft -> left-to-right
        NEG     D3                              | bump = -2 (right-to-left)
        BRA.B   GETSRC                          | -> begin transfer
UPSIDE:
        MOVE    -0x52(A6),D0                    | D0 = height
        SUBQ.W  #0x1,D0                         | height - 1
        ADD     D0,-0x42(A6)                    | -0x42(A6) += D0
        ADD     D0,-0x44(A6)                    | -0x44(A6) += D0
        NEG     -0x46(A6)                       | -0x46(A6) = --0x46(A6)
        NEG     -0x48(A6)                       | -0x48(A6) = --0x48(A6)
| .PROC BITBLT,7
| .REF LEFTMASK,RIGHTMASK,PatExpand
| --------------------------------------------------------------
|
| PROCEDURE BitBlt(srcBits,dstBits: BitMap;
| srcRect,dstRect: Rect;
| mode: INTEGER; pat: Pattern);
|
| TRANSFERS A RECTANGULAR BLOCK OF BITS WITH NO CLIPPING AT ALL.
| MODE SPECIFIES THE COMBINATION MODE AND WHETHER THE SOURCE SHOULD COME
| FROM THE SOURCE BITMAP OR FROM A REPEATING PATTERN.
|
| COPYRIGHT APPLE COMPUTER INC.
| WRITTEN BY BILL ATKINSON
|
| POSITION INDEPENDENT AND RE-ENTRANT, CLOBBERS ONLY A0.
| MODES: 0 SRC --> DST
| 1 SRC OR DST --> DST
| 2 SRC XOR DST --> DST
| 3 SRC BIC DST --> DST
| 4 (NOT SRC) --> DST
| 5 (NOT SRC) OR DST --> DST
| 6 (NOT SRC) XOR DST --> DST
| 7 (NOT SRC) BIC DST --> DST
| 8 PATTERN --> DST
| 9 PATTERN OR DST --> DST
| 10 PATTERN XOR DST --> DST
| 11 PATTERN BIC DST --> DST
| 12 (NOT PATTERN) --> DST
| 13 (NOT PATTERN) OR DST --> DST
| 14 (NOT PATTERN) XOR DST --> DST
| 15 (NOT PATTERN) BIC DST --> DST
| Called during boot.

| -----------------------------------------------------
| SET UP SHIFTCNT IN D6 (RELATIVE SHIFT BETWEEN SRC & DST)
| ----------------------------------------------------------
| DO UPSIDE DOWN TO AVOID CLOBBERING SRC
| Called during boot.
GETSRC:
        MOVE    2(A3),D6                        | GET DST LEFT
        SUB     8(A5),D6                        | CONVERT DST RIGHT TO GLOBAL
        MOVE    2(A2),D1                        | GET SRC LEFT
        SUB     8(A4),D1                        | CONVERT SRC LEFT TO GLOBAL
        SUB     D1,D6                           | CALC DELTA HORIZ
        ANDI    #0xF,D6                         | CALC DST RIGHT MOD 16
        MOVE    -0x42(A6),D0                    | GET FIRST SRC VERT
        MULU    4(A4),D0                        | D0 = D0 *u 4(A4)
        MOVE.L  (A4),A4                         | LOAD SRC BASEADDR
        ADDA.L  D0,A4                           | ADD TO BITMAP START
        ADD     D6,D1                           | CALC SRCH+SHIFTCNT
        ASR     #0x3,D1                         | convert bits to byte offset
        ANDI    #-0x2,D1                        | MASK FOR WORD ALIGNMENT
        ADDA.W  D1,A4                           | LEAVE SRCLEFT IN A4
        MOVE.L   A4,-76(FP)                     | saveSrc := A4
GETSRC_CONT:
        MOVE    2(A3),D1                        | GET DST LEFT
        SUB     8(A5),D1                        | D1 -= 8(A5)
        MOVE    -0x44(A6),D0                    | D0 := dstV
        MULU    4(A5),D0                        | D0 = D0 *u 4(A5)
        MOVE.L  (A5),A5                         | A5 := (A5)
        ADDA.L  D0,A5                           | A5 += D0
        MOVE    D1,D0                           | MASK:=FIRSTMASK
        ASR     #0x4,D1                         | convert dots to word offset
        ADD     D1,D1                           | DOUBLE FOR BYTES
        ADDA.W  D1,A5                           | jump via A1
        MOVE.L  A5,-0x50(A6)                    | dstAddr := A5
        MOVE    D0,D1                           | SAVE DSTH
        JSR     BitMask(PC)                     | GET LEFTMASK
        MOVE    D0,D4                           | PUT IN D4
        ANDI    #0xF,D1                         | mask D1 with #0xF
        MOVE    6(A3),D0                        | GET DST RIGHT
        SUB     2(A3),D0                        | CALC WIDTH
        BLE.W   GOHOME                          | QUIT IF WIDTH <= 0
        ADD     D1,D0                           | CALC (DSTH MOD 16) + WIDTH
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        JSR     LeftMask(PC)                    | GET RIGHT MASK
        MOVE    D0,D5                           | SAVE RIGHTMASK IN D5
        ASR     #0x4,D1                         | convert dots to word offset
        MOVE    D1,-0x54(A6)                    | save wordCnt
        TST     D3                              | ARE WE STARTING ON THE LEFT ?
        BPL.B   DIROK                           | YES, CONTINUE
        ADD     D1,D1                           | D1 += D1
        ADDA.W  D1,A4                           | A4 += D1
        MOVE.L  A4,-0x4C(A6)                    | saveSrc := A4
        ADDA.W  D1,A5                           | ADJUST DSTADDR TO RIGHTMOST
        MOVE.L  A5,-0x50(A6)                    | jump via A0
        EXG     D4,D5                           | FIRSTMASK=RIGHT,LASTMASK=LEFT
| ----------------------------------------------------------
| DIROK
| DIROK: determine effective font size
| Returns D0 = font size: from FMInput.size, SysFontSize, or FMDefaultSize
| Called during boot.
DIROK:
        MOVE    12(A6),D0                       | GET TRANSFER MODE
        BNE.B   DIROK_NO                        | BR IF NOT MODE 0
        TST     D6                              | IS SHIFTCNT 0 ?
        BNE.B   DIROK_NO                        | NO, CONTINUE
        TST     -0x54(A6)                       | test wordCnt
        BLE.B   DIROK_NO                        | NO, CONTINUE
        LEA     END8(PC),A1                     | USE FAST COPY.
        TST     D3                              | ARE WE BUMPING LEFT TO RIGHT ?
        BPL.B   ROWLOOP                         | YES, ALL SET
        LEA     LEFT0(PC),A1                    | NO, USE BACKWARDS LOOP
        BRA.B   ROWLOOP                         | jump to ROWLOOP
DIROK_NO:
        ANDI    #0xB,D0                         | FILTER MODE BITS
        MOVE    D0,D1                           | MAKE A COPY
        ANDI    #0x3,D0                         | MASK MODE TO 0-3
        ADD     D0,D1                           | MAKE MODIFIED MODE * 2 FOR INDEX
        TST     -0x54(A6)                       | test wordCnt
        BNE.B   DOMAIN                          | count != 0 -> skip adjust
        ADDI    #0x10,D1                        | add mode-offset for count=0 path
DOMAIN:
        LEA     MODETAB(PC),A1                  | A1 = mode-handler LEA table @ $750E
        .short  0xD2F1, 0x1000                  | ADD.W 0(A1,D1.W),D1 -- GNU as emits $D271
| instead of indexed; kept as raw bytes
ROWLOOP:
        MOVE    D4,D1                           | MASK:=FIRSTMASK
        MOVE    -0x54(A6),D2                    | load wordCnt
        JMP     (A1)                            | jump via A1
NXTSRC:
        MOVE.L  -0x4C(A6),A4                    | A4 := saveSrc
        ADDA.W  -0x46(A6),A4                    | A4 += -0x46(A6)
        MOVE.L  A4,-0x4C(A6)                    | saveSrc := A4
        BRA.B   ROWBOTTOM                       | then quit
NXTSRC_NEXT:
        ADDQ.W  #0x4,D7                         | bump pattern-row index
        ANDI    #0x3F,D7                        | wrap pattern-row index mod 64
        MOVE.L  -0x40(A6,D7.W),D6               | D6 = pattern word from expanded table
ROWBOTTOM:
        MOVE.L  -0x50(A6),A5                    | A5 := dstAddr
        ADDA.W  -0x48(A6),A5                    | A5 += -0x48(A6)
        MOVE.L  A5,-0x50(A6)                    | MOVE A LONG WORD
        SUBQ.W  #0x1,-0x52(A6)                  | wordCnt -= #0x1
        BNE.B   ROWLOOP                         | if non-zero -> ROWLOOP
GOHOME:
        MOVEM.L (SP)+,D0-D7/A1-A5               | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0x16,SP                        | pop parameter bytes from stack
        JMP     (A0)                            | RTS

MODETAB:                                        | mode-handler offset table
        .short  0x007C, 0x00A0                  | word 0/1
        .short  0x00BE, 0x00DC                  | word 2/3
        .short  0x0126, 0x015E                  | word 4/5
        .short  0x0170, 0x019C                  | word 6/7
        .short  0x007A                          | word 8
        .short  0x009E, 0x00BC                  | word 9/10
        .short  0x00DA, 0x00FA                  | word 11/12
        .short  0x015C, 0x0190                  | word 13/14
        .short  0x019A                          | word 15

| ---------------------------------------------------------------;
| ;
| INTERFACE TO EACH BITBLT SCANLINE LOOP: ;
| REGISTERS: A0: hBump (+-2) D0: scratch ;
| A1: MODE CASE JUMP D1: FIRSTMASK ;
| A2: used for loop jmp D2: WORDCNT ;
| A3: dstBump D3: height-1 ;
| A4: SRCPTR D4: FIRSTMASK ;
| A5: DSTPTR D5: LASTMASK ;
| A6: LOCALS D6: SHIFTCNT OR PATTERN ;
| A7: STACK PTR D7: INVERT OR PAT-SEL ;
| ---------------------------------------------------------------;

| ------------------------------------------------------------
| OPTIMIZE RIGHT HORIZONTAL SCROLL IF NO SHIFT.
| ONLY IF MODE 0, BUMPING RIGHT TO LEFT, WORDCNT > 0, AND NO SHIFT.
LEFT0:
        MOVE    (A4),D0                         | GET SRC FROM BITMAP
        ADDA.W  D3,A4                           | bump srcPtr by hBump (+-2)
        AND     D1,D0                           | MASK FIRST WORD
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DATA FROM DST
        OR      D1,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)                         | PUT RESULT TO DST
        ADDA.W  D3,A5                           | bump dstPtr by hBump (+-2)
        MOVEQ.L #-0x1,D1                        | FLUSH MASK FOR END0
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BEQ.B   END0                            | BR IF NO UNMASKED WORDS
        SUBA.W  D3,A4                           | rewind srcPtr for pre-decrement
        SUBA.W  D3,A5                           | rewind dstPtr for pre-decrement
        LSR     #0x1,D2                         | HALVE WORDCOUNT FOR LONGCOUNT
        BCC.B   LONE0                           | BR IF EVEN # WORDS LEFT
        MOVE    -(A4),-(A5)                     | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BRA.B   LMORE0                          | SEE IF ANY LONGS LEFT TO DO
LTWO0:
        MOVE.L   -(A4),-(A5)                    | MOVE A LONG WORD
LONE0:
        MOVE.L   -(A4),-(A5)                    | MOVE ANOTHER LONG
        SUBQ.W   #0x2,D2                        | decrement long-word count by 2
LMORE0:
        BGT.B   LTWO0                           | YES, AT LEAST 2 LONGS LEFT
        BEQ.B   LONE0                           | YES, FINISH UP LAST LONG
        ADDA.W  D3,A4                           | bump srcPtr by hBump (+-2)
        ADDA.W  D3,A5                           | bump dstPtr by hBump (+-2)
        BRA.B   END0                            | share loop calc
END8:
        MOVE    (A4)+,D0                        | GET SRC FROM BITMAP
        AND     D1,D0                           | MASK FIRST WORD
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)+                        | PUT RESULT TO DST
        MOVEQ.L #-0x1,D1                        | FLUSH MASK FOR END0
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BEQ.B   END0                            | if zero -> END0
        LSR     #0x1,D2                         | halve word count for long-word loop
        BCC.B   END8_CONT_2                     | if no carry -> END8_CONT_2
        MOVE    (A4)+,(A5)+                     | copy word src->dst, advance both
        SUBQ.W  #0x1,D2                         | decrement word count
        BRA.B   END8_CONT_3                     | jump to END8_CONT_3
END8_CONT:
        MOVE.L  (A4)+,(A5)+                     | copy long src->dst, advance both
END8_CONT_2:
        MOVE.L  (A4)+,(A5)+                     | copy long src->dst, advance both
        SUBQ.W  #0x2,D2                         | decrement long-word count by 2
END8_CONT_3:
        BGT.B   END8_CONT                       | if signed > -> END8_CONT
        BEQ.B   END8_CONT_2                     | BR IF NO UNMASKED WORDS
END0:
        AND     D5,D1                           | MASK:=MASK AND LASTMASK
MAIN0:
        MOVE.L  -2(A4),D0                       | LOAD 32 BITS OF SRC
        ADDA.W  D3,A4                           | bump srcPtr by hBump (+-2)
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        NOT     D1                              | FORM NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)                         | PUT RESULT TO DST
        ADDA.W  D3,A5                           | bump dstPtr by hBump (+-2)
        MOVEQ.L #-0x1,D1                        | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   MAIN0                           | BR IF UNMASKED WORDS LEFT
        BEQ.B   END0                            | DO LAST WORD WITH LASTMASK
        BRA.W   NXTSRC                          | LOOP BACK FOR MORE
END1:
        AND.W    D5,D1                          | mask := mask AND lastMask
END1_LOOP:
        MOVE.L  -2(A4),D0                       | LOAD 32 BITS OF SRC
        ADDA.W  D3,A4                           | bump srcPtr by hBump (+-2)
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        OR      D0,(A5)                         | OR SRC INTO DST
        ADDA.W  D3,A5                           | bump dstPtr by hBump (+-2)
        MOVEQ.L #-0x1,D1                        | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   END1_LOOP                       | LOOP TILL LAST WORD
        BEQ.B   END1                            | DO LAST WORD WITH LASTMASK
        BRA.W   NXTSRC                          | LOOP BACK FOR NEXT ROW
END2:
        AND.W    D5,D1                          | mask := mask AND lastMask
END2_LOOP:
        MOVE.L  -2(A4),D0                       | LOAD 32 BITS OF SRC
        ADDA.W  D3,A4                           | bump srcPtr by hBump (+-2)
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        EOR     D0,(A5)                         | XOR SRC INTO DST
        ADDA.W  D3,A5                           | bump dstPtr by hBump (+-2)
        MOVEQ.L #-0x1,D1                        | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   END2_LOOP                       | LOOP TILL LAST WORD
        BEQ.B   END2                            | DO LAST WORD WITH LASTMASK
        BRA.W   NXTSRC                          | LOOP BACK FOR NEXT ROW
END3:
        AND.W    D5,D1                          | mask := mask AND lastMask
END3_LOOP:
        MOVE.L  -2(A4),D0                       | LOAD 32 BITS OF SRC
        ADDA.W  D3,A4                           | bump srcPtr by hBump (+-2)
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        NOT     D0                              | INVERT SRC
        AND     D0,(A5)                         | BIT CLEAR SRC INTO DST
        ADDA.W  D3,A5                           | bump dstPtr by hBump (+-2)
        MOVEQ.L #-0x1,D1                        | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   END3_LOOP                       | LOOP TILL LAST WORD
        BEQ.B   END3                            | DO LAST WORD WITH LASTMASK
        BRA.W   NXTSRC                          | LOOP BACK FOR NEXT ROW

| -----------------------------------------------------------
| OPTIMIZE MODE 8 OR 12 IF DST FITS IN ONE WORD (VERT LINES ETC)
| Called during boot.
WORD8:
        AND     D5,D1                           | COMBINE LEFT AND RIGHT MASKS
        MOVE    D1,D5                           | COPY COMBINED MASK
        NOT     D5                              | FORM NOTMASK
        MOVE    -0x48(A6),D3                    | D3 := dstRow
        MOVE    -0x52(A6),D2                    | load wordCnt
WORD8A:
        AND     D1,D6                           | MASK EXTRA PATTERN TO ZEROS
        MOVE    (A5),D0                         | GET DST DATA
        AND     D5,D0                           | AND WITH NOTMASK
        OR      D6,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)                         | (A5) := D0
        ADDA.W  D3,A5                           | bump dstPtr by hBump (+-2)
        ADDQ.W  #0x4,D7                         | BUMP PATTERN ROW INDEX
        ANDI    #0x3F,D7                        | WRAP PATTERN ROW INDEX MOD 64
        MOVE    -0x40(A6,D7.W),D6               | LOAD NEXT PATTERN ROW
        SUBQ.W  #0x1,D2                         | decrement word count
        BNE.B   WORD8A                          | if non-zero -> WORD8A
        BRA.W   GOHOME                          | jump to GOHOME
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     D1,D0                           | MASK FIRST WORD
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D0                           | MERGE WITH PAT DATA
        MOVE    D0,(A5)+                        | PUT RESULT TO DST
        MOVEQ.L #-0x1,D1                        | flush mask to all-ones
        SUBQ.W  #0x1,D2                         | decrement word count
        BEQ.B   WORD8_CONT_4                    | if zero -> WORD8_CONT_4
        LSR     #0x1,D2                         | halve word count for long-word loop
        BCC.B   WORD8_CONT_2                    | if no carry -> WORD8_CONT_2
        MOVE    D6,(A5)+                        | store pattern word to dst, advance
        SUBQ.W  #0x1,D2                         | decrement word count
        BRA.B   WORD8_CONT_3                    | jump to WORD8_CONT_3
WORD8_CONT:
        MOVE.L  D6,(A5)+                        | store pattern word to dst, advance
WORD8_CONT_2:
        MOVE.L  D6,(A5)+                        | store pattern word to dst, advance
        SUBQ.W  #0x2,D2                         | decrement long-word count by 2
WORD8_CONT_3:
        BGT.B   WORD8_CONT                      | if signed > -> WORD8_CONT
        BEQ.B   WORD8_CONT_2                    | BR IF NO UNMASKED WORDS
WORD8_CONT_4:
        AND     D5,D1                           | mask := mask AND lastMask
        AND     D1,D6                           | MASK PATTERN
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D6                           | MERGE WITH PAT DATA
        MOVE    D6,(A5)+                        | PUT RESULT TO DST
        BRA.W   NXTSRC_NEXT                     | LOOP BACK FOR NEXT ROW
WORD8_CONT_5:
        AND     D5,D1                           | MASK:=MASK AND LASTMASK
MAIN9:
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     D1,D0                           | MASK PATTERN
        OR      D0,(A5)+                        | OR PATTERN INTO DST
        MOVEQ.L #-0x1,D1                        | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   MAIN9                           | LOOP TILL LAST WORD
        BEQ.B   WORD8_CONT_5                    | DO LAST WORD WITH LASTMASK
        BRA.W   NXTSRC_NEXT                     | LOOP BACK FOR NEXT ROW
        MOVE    D6,D0                           | FAST10: GET PATTERN DATA
        AND     D1,D0                           | MASK FIRST WORD
        EOR     D0,(A5)+                        | XOR PATTERN INTO DST
        MOVEQ.L #-0x1,D1                        | FLUSH MASK FOR END10
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BEQ.B   MAIN9_CONT_6                    | BR IF NO UNMASKED WORDS
        LSR     #0x1,D2                         | halve word count for long-word loop
        BCC.B   MAIN9_CONT_4                    | if no carry -> MAIN9_CONT_4
        EOR     D6,(A5)+                        | XOR PATTERN DATA INTO DST
        SUBQ.W  #0x1,D2                         | decrement word count
        BRA.B   MAIN9_CONT_5                    | LOOP BACK FOR NEXT ROW
MAIN9_CONT_3:
        EOR.L   D6,(A5)+                        | TABLE TO XOR 0..32 WORDS
MAIN9_CONT_4:
        EOR.L   D6,(A5)+                        | wordCount = 30
        SUBQ.W  #0x2,D2                         | decrement long-word count by 2
MAIN9_CONT_5:
        BGT.B   MAIN9_CONT_3                    | if signed > -> MAIN9_CONT_3
        BEQ.B   MAIN9_CONT_4                    | if zero -> MAIN9_CONT_4
MAIN9_CONT_6:
        AND     D5,D1                           | END10: MASK:=MASK AND LASTMASK
        AND     D1,D6                           | MASK PATTERN
        EOR     D6,(A5)+                        | (A5)+ ^= D6
        BRA.W   NXTSRC_NEXT                     | LOOP BACK FOR NEXT ROW
END11:
        AND.W    D5,D1                          | mask := mask AND lastMask
MAIN11:
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     D1,D0                           | MASK PATTERN
        NOT     D0                              | INVERT PATTERN
        AND     D0,(A5)+                        | BIC PATTERN INTO DST
        MOVEQ.L #-0x1,D1                        | flush mask to all-ones
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   MAIN11                          | LOOP TILL LAST WORD
        BEQ.B   END11                           | if zero -> END11
        BRA.W   NXTSRC_NEXT                     | jump to NXTSRC_NEXT

| 34-byte embedded copyright string (BitBlt inner loop boundary).
COPYRIGHT_QD:
        .ascii  "CopyRight 1983 Apple Computer Inc."
