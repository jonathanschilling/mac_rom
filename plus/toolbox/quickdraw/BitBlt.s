| ---------------------------------------------------------------
|
| --> BITBLT.TEXT
|
| Low-level bit boundary block transfer.
|

| .PROC BITBLT,7
| .REF LEFTMASK,RIGHTMASK,PATEXPAND
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
|
| MODES: 0 SRC --> DST
| 1 SRC OR DST --> DST
| 2 SRC XOR DST --> DST
| 3 SRC BIC DST --> DST
|
| 4 (NOT SRC) --> DST
| 5 (NOT SRC) OR DST --> DST
| 6 (NOT SRC) XOR DST --> DST
| 7 (NOT SRC) BIC DST --> DST
|
| 8 PATTERN --> DST
| 9 PATTERN OR DST --> DST
| 10 PATTERN XOR DST --> DST
| 11 PATTERN BIC DST --> DST
|
| 12 (NOT PATTERN) --> DST
| 13 (NOT PATTERN) OR DST --> DST
| 14 (NOT PATTERN) XOR DST --> DST
| 15 (NOT PATTERN) BIC DST --> DST
|
| Called during boot.
BitBlt:
        LINK    A6,#-0x52                       | ALLOCATE LOCAL VARIABLES

| ----------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
.set PARAMSIZE, 22                              | SIZE OF PARAMETERS
.set SRCBITS, PARAMSIZE+8-4                     | LONG, ADDR OF BITMAP
.set DSTBITS, SRCBITS-4                         | LONG, ADDR OF BITMAP
.set SRCRECT, DSTBITS-4                         | LONG, ADDR OF RECT
.set DSTRECT, SRCRECT-4                         | LONG, ADDR OF RECT
.set MODE, DSTRECT-2                            | WORD
.set PAT, MODE-4                                | LONG, ADDR OF PATTERN

| ----------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set EXPAT, -64                                 | 16 LONGS
.set SRCV, EXPAT-2                              | WORD
.set DSTV, SRCV-2                               | WORD
.set SRCROW, DSTV-2                             | WORD
.set DSTROW, SRCROW-2                           | WORD
.set SRCBUMP, DSTROW-2                          | WORD
.set HEIGHT, srcBump-2                          | WORD
.set WORDCNT, HEIGHT-2                          | WORD
.set SAVEA5, WORDCNT-4                          | LONG
.set VARSIZE, SAVEA5                            | SIZE OF LOCAL VARIABLES

| -------------------------------------------------------------------
|
| ENTER HERE. CALLER TAKES CARE OF CURSOR.
|
        MOVEM.L D3-D7/A2-A5,-(SP)               | SAVE REGS
        MOVE.L  A5,-0x52(A6)                    | SAVE GLOBAL POINTER

| ----------------------------------------------------------------------
|
| GET PARAMETER POINTERS IN REGISTERS
|
        MOVE.L  0x12(A6),A2                     | A2 POINTS TO SRCRECT
        MOVE.L  0xE(A6),A3                      | A3 POINTS TO DSTRECT
        MOVE.L  0x1A(A6),A4                     | A4 POINTS TO SRCBITS
        MOVE.L  0x16(A6),A5                     | A5 POINTS TO DSTBITS

| -------------------------------------------------------------
|
| CALC HEIGHT OF DSTRECT. QUIT IF HEIGHT <= 0
|

| ----------------------------------------------------------------------
|
        MOVE    BOTTOM(A3),D0                   | GET BOTTOM
        SUB     (A3),D0                         | CALC HEIGHT
        BLE     GOHOME                          | QUIT IF HEIGHT <= 0
        MOVE    D0,-0x4C(A6)                    | SAVE FOR LATER

| --------------------------------------------------------------
|
| SET UP FOR TOP TO BOTTOM, LEFT TO RIGHT
| GET SRC AND DST TOP AND ROWBYTES
|
        MOVEQ   #2,D3                           | BUMP:=2 (TRANSFER LEFT TO RIGHT)
        MOVE    (A2),D0                         | GET SRC TOP
        SUB     0x6(A4),D0                      | CONVERT SRC TOP TO GLOBAL
        MOVE    D0,-0x42(A6)                    | SAVE FOR LATER
        MOVE    (A3),D0                         | GET DST TOP
        SUB     0x6(A5),D0                      | CONVERT DST TOP TO GLOBAL
        MOVE    D0,-0x44(A6)                    | SAVE FOR LATER
        MOVE    ROWBYTES(A4),-0x46(A6)          | SRCROW:=SRCBITS.ROWBYTES
        MOVE    ROWBYTES(A5),-0x48(A6)          | DSTROW:=DSTBITS.ROWBYTES

| --------------------------------------------------------------------
|
| SET UP INVERT FLAG, IN CASE SRC OR PATTERN WILL BE INVERTED
|
        CLR     D7                              | SAY NOT INVERTED
        MOVE    0xC(A6),D0                      | GET TRANSFER MODE
        BTST    #2,D0                           | IS MODE AN INV. ONE ?
        BEQ.B   MODEOK                          | NOT INVERTED, CONTINUE
        NOT     D7                              | INVERTED, PUT -1 IN INVERT REG
MODEOK:
        BTST    #3,D0                           | WILL WE USE PATTERN ?
        BEQ.B   DIREC                           | NO, DON'T BOTHER TO SET UP
        MOVE    0x8(A5),D2                      | GET DST LEFT FOR PATTERN ALIGN

| ------------------------------------------------------------
|
| PATTERN WILL BE USED. EXPAND 8 BYTE PATTERN TO 16 LONGS.
|
        MOVE.L  0x8(A6),A0                      | POINT TO BYTE WIDE PATTERN
        LEA.L   -0x40(A6),A1                    | POINT TO EXPANDED PATTERN
        MOVE.L  -0x52(A6),A5                    | GET GLOBAL POINTER

| ------------------------------------------------------------
|
        JSR     PatExpand(PC)                   | EXPAND 8 BYTES TO 16 LONGS
        MOVE.L  0x16(A6),A5                     | RESTORE A5 TO DSTBITS

| ------------------------------------------------------------
|
| SET UP (VERT * 4) MOD 64 AS PATTERN SELECTOR
|
        MOVEQ.L #0xF,D7                         | TREAT COORD MOD 16
        AND     (A3),D7                         | TREAT COORD MOD 16

| ------------------------------------------------------------
|
        LSL     #2,D7                           | QUAD FOR LONG PATTERNS
        MOVE.L  -0x40(A6,D7.W),D6               | LOAD PATTERN ROW
        BRA.B   NOTSRC                          | NOT USING SRC, SKIP OVER

| ----------------------------------------------------------
|
| DIREC
|
| Called during boot.
DIREC:
        MOVE.L  (A4),D0                         | GET SRC BASEADDR
        CMP.L   (A5),D0                         | COMPARE SRC AND DST BASEADDR

| -----------------------------------------------------------
|
| SOURCE WILL BE USED, SO SET UP VERT AND HORIZ DIRECTIONS
| SUCH THAT SRC WON'T GET CLOBBERED TILL AFTER IT HAS BEEN USED
|
        BNE.B   GETSRC                          | NO, DONT WORRY ABOUT OVERLAP
        MOVE    -0x42(A6),D0                    | GET SRCV
        CMP     -0x44(A6),D0                    | IS SRCV > DSTV ?
        BGT.B   GETSRC                          | YES, CONTINUE WITH TOP TO BOTTOM
        BLT.B   UPSIDE                          | NO, DO UPSIDE DOWN
        MOVE    LEFT(A2),D0                     | SAME VERT, CHOOSE HORIZ DIRECTION
        SUB     0x8(A4),D0                      | CONVERT SRC LEFT TO GLOBAL
        MOVE    LEFT(A3),D1                     | GET DST LEFT
        SUB     0x8(A5),D1                      | CONVERT DST LEFT TO GLOBAL
        CMP     D1,D0                           | IS SRCLEFT < DSTLEFT ?
        BGE.B   GETSRC                          | NO, DO LEFT TO RIGHT
        NEG     D3                              | YES, BUMP:=-2 (RIGHT TO LEFT)
        BRA.B   GETSRC                          | CONTINUE

| ----------------------------------------------------------
|
| DO UPSIDE DOWN TO AVOID CLOBBERING SRC
|
UPSIDE:
        MOVE    -0x4C(A6),D0                    | GET HEIGHT
        SUBQ.W  #0x1,D0                         | CALC HEIGHT-1
        ADD     D0,-0x42(A6)                    | SRCVERT:=SRCV+HEIGHT-1
        ADD     D0,-0x44(A6)                    | DSTVERT:=DSTV+HEIGHT-1
        NEG     -0x46(A6)                       | SRCROW:=-SRCROW
        NEG     -0x48(A6)                       | DSTROW:=-DSTROW

| -----------------------------------------------------
|
| SET UP SHIFTCNT IN D6 (RELATIVE SHIFT BETWEEN SRC & DST)
|

| ----------------------------------------------------------
|
| DO UPSIDE DOWN TO AVOID CLOBBERING SRC
| Called during boot.
GETSRC:
        MOVE    LEFT(A3),D6                     | GET DST LEFT
        SUB     0x8(A5),D6                      | CONVERT DST RIGHT TO GLOBAL
        MOVE    LEFT(A2),D1                     | GET SRC LEFT
        SUB     0x8(A4),D1                      | CONVERT SRC LEFT TO GLOBAL
        SUB     D1,D6                           | CALC DELTA HORIZ
        ANDI    #0xF,D6                         | CALC DST RIGHT MOD 16

| ------------------------------------------------------------
|
| SET UP SRCLEFT IN A4, ADDR OF LEFTMOST SRC WORD
| (GOODBYE SRCBITS PTR)
|
        MOVE    -0x42(A6),D0                    | GET FIRST SRC VERT

| ------------------------------------------------------------
|
        MULU    ROWBYTES(A4),D0                 | CALC SRC ROWBYTES * FIRST SRC VERT
        MOVE.L  (A4),A4                         | LOAD SRC BASEADDR
        ADD.L   D0,A4                           | ADD TO BITMAP START
        ADD     D6,D1                           | CALC SRCH+SHIFTCNT
        ASR     #3,D1                           | CONVERT BITS TO BYTE OFFSET
        ANDI    #-0x2,D1                        | MASK FOR WORD ALIGNMENT
        ADD     D1,A4                           | LEAVE SRCLEFT IN A4

| ------------------------------------------------------------
|
| SET UP DSTLEFT IN A5, ADDR OF LEFTMOST DST WORD
| (GOODBYE DSTBITS PTR)
|
| Called during boot.
NOTSRC:
        MOVE    LEFT(A3),D1                     | GET DST LEFT
        SUB     0x8(A5),D1                      | CONVERT DST LEFT TO GLOBAL
        MOVE    -0x44(A6),D0                    | GET FIRST DST VERT
        MULU    ROWBYTES(A5),D0                 | CALC DSTROW * FIRST DST VERT
        MOVE.L  (A5),A5                         | LOAD DST BASEADDR
        ADD.L   D0,A5                           | ADD DSTV*DSTROW
        MOVE    D1,D0                           | COPY DSTLEFT GLOBAL
        ASR     #4,D1                           | CONVERT FROM DOTS TO WORDS
        ADD     D1,D1                           | DOUBLE FOR BYTES
        ADD     D1,A5                           | LEAVE DSTLEFT IN A5

| -------------------------------------
|
| SET UP LEFTMASK IN D4
| (GOODBYE SRCRECT PTR)
|
        MOVE    D0,D1                           | SAVE DSTH
        JSR     LeftMask(PC)                    | GET LEFTMASK
        MOVE    D0,D4                           | PUT IN D4
        ANDI    #0xF,D1                         | CALC DST LEFT MOD 16

| -------------------------------------
|
| SET UP RIGHTMASK IN D5
| (GOODBYE DSTRECT PTR)
|
        MOVE    RIGHT(A3),D0                    | GET DST RIGHT
        SUB     LEFT(A3),D0                     | CALC WIDTH
        BLE     GOHOME                          | QUIT IF WIDTH <= 0
        ADD     D1,D0                           | CALC (DSTH MOD 16) + WIDTH
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        JSR     RightMask(PC)                   | GET RIGHT MASK
        MOVE    D0,D5                           | SAVE RIGHTMASK IN D5

| ------------------------------------------------
|
| CALC TOTAL NUMBER OF DST WORDS-1
|
        ASR     #4,D1                           | CALC ((DSTH MOD 16)+WIDTH) DIV 16
        MOVE    D1,-0x4E(A6)                    | SAVE AS WORDCNT
        MOVE    D1,D2                           | set up for below

|
| Set up srcBump and dstBump, assuming bumping to the right
|
        ADD     D1,D1                           | calc 2*wordCount
        MOVE    D1,D0                           | make a copy
        ADDQ.W  #0x2,D0                         | ROUND UP WORD COUNT

| --------------------------------------------------------------------------
|
| IF DRAWING BACKWARDS FROM RIGHT, then adjust dstBump,
| ADJUST SRCADDR,DSTADDR TO FIRST WORD,
| AND SWAP LEFT AND RIGHT MASKS FOR FIRSTMASK AND LASTMASK.
|
        MOVE    D3,A0                           | put hBump (+-2) into A0
        TST     D3                              | ARE WE STARTING ON THE LEFT ?
        BPL.B   DIROK                           | YES, CONTINUE
        NEG     D0                              | calc -1 * bytesNeeded
        ADD     D1,A5                           | ADJUST DSTADDR TO RIGHTMOST
        ADD     D1,A4                           | ADJUST SRCADDR TO RIGHTMOST
        EXG     D4,D5                           | FIRSTMASK=RIGHT,LASTMASK=LEFT
DIROK:
        MOVE    -0x46(A6),-0x4A(A6)             | COPY SRCROW TO CURSRCROW
        SUB     D0,-0x4A(A6)                    | srcBump := srcRow +- bytesBumped
        MOVE    -0x48(A6),A3                    | LOAD DSTROW
        SUB     D0,A3                           | dstBump := dstRow +- bytesBumped

| ----------------------------------------------
|
| SET UP MODE CASE JUMP IN A1
|
        MOVE    0xC(A6),D0                      | GET TRANSFER MODE

| ----------------------------------------------
|
        BNE.B   DIROK_NO                        | BR IF NOT MODE 0
        TST     D6                              | IS SHIFTCNT 0 ?
        BNE.B   DIROK_NO                        | NO, CONTINUE
        TST     -0x4E(A6)                       | IS WORDCNT > 0 ?
        BLE.B   DIROK_NO                        | NO, CONTINUE
        LEA.L   SETUP0(PC),A1                   | USE FAST COPY.
        TST     D3                              | ARE WE BUMPING LEFT TO RIGHT ?
        BPL.B   NEXTROW                         | YES, ALL SET
        LEA.L   LEFT0(PC),A1                    | NO, USE BACKWARDS LOOP
        BRA.B   NEXTROW                         | GO TO NEXT ROW

| ----------------------------------------------------------
|
| DIROK_NO
|
| Called during boot.
DIROK_NO:
        ANDI    #0xB,D0                         | FILTER MODE BITS
        MOVE    D0,D1                           | MAKE A COPY
        ANDI    #0x3,D0                         | MASK MODE TO 0-3
        ADD     D0,D1                           | MAKE MODIFIED MODE * 2 FOR INDEX
        TST     D2                              | IS DST ALL IN ONE WORD ?
        BNE.B   DOMAIN                          | NO, USE FIRST JUMP TABLE
        ADDI    #0x10,D1                        | CALC BRANCH OFFSET BASE
DOMAIN:
        LEA.L   MODETAB(PC),A1                  | GET ADDRESS OF MODE TABLE
        ADDA    0x0(A1,D1.W),A1                 | CALC DISPATCH ADDRESS

| ---------------------------------------------------------
|
| OUTER LOOP: DO EACH SCAN LINE AND COME BACK TO NXTSRC OR NXTPAT.
| SOME MODES OPTIMIZE AND DO WHOLE OUTER LOOP AND COME BACK TO GOHOME.
|
| Called during boot.
NEXTROW:
        MOVE    -0x4C(A6),D3                    | get height
        SUBQ.W  #0x1,D3                         | DECREMENT ROW COUNTER

| ---------------------------------------------------------
|
| OUTER LOOP: DO EACH SCAN LINE AND COME BACK TO NXTSRC OR NXTPAT.
| SOME MODES OPTIMIZE AND DO WHOLE OUTER LOOP AND COME BACK TO GOHOME.
|
| Called during boot (8,945 times in 30s trace).
ROWLOOP:
        MOVE    D4,D1                           | MASK:=FIRSTMASK
        MOVE    -0x4E(A6),D2                    | GET WORDCOUNT
        JMP     (A1)                            | DO THIS ROW AND COME BACK

| ----------------------------------------------------------
|
| NXTSRC
|
| Called during boot (1,458 times in 30s trace).
NXTSRC:
        ADDA    -0x4A(A6),A4                    | bump srcPtr to next row
        ADD     A3,A5                           | BUMP DSTADDR TO NEXT ROW
        DBF     D3,ROWLOOP                      | loop for all srcRows
        BRA.B   GOHOME                          | then quit

| ----------------------------------------------------------
|
| NXTSRC_NEXT
|
| Called during boot (7,476 times in 30s trace).
NXTSRC_NEXT:
        ADDQ.W  #0x4,D7                         | BUMP PATTERN ROW INDEX
        ANDI    #0x3F,D7                        | WRAP PATTERN ROW INDEX MOD 64
        MOVE.L  -0x40(A6,D7.W),D6               | LOAD PATTERN ROW
        ADD     A3,A5                           | BUMP DSTADDR TO NEXT ROW
        DBF     D3,ROWLOOP                      | loop for all srcRows

| then quit
| Called during boot.
GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A5               | RESTORE REGS
        UNLK    A6                              | TEAR DOWN STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0x16,SP                        | POP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| ----------------------------------------------------------
|
| MODETAB
|
MODETAB:
  .byte 0x00,0x78,0x00,0xF8,0x01,0x16           | MODES 0-2: SRCCOPY,SRCOR,SRCXOR
  .byte 0x01,0x34,0x01,0x76,0x02,0x16           | MODES 3-5: SRCBIC,NOTSRCCOPY,NOTSRCOR
  .byte 0x02,0x28,0x02,0xAC,0x00,0x76           | MODES 6-8: NOTSRCXOR,NOTSRCBIC,PATCOPY
  .byte 0x00,0xF6,0x01,0x14,0x01,0x32           | MODES 9-11: PATOR,PATXOR,PATBIC
  .byte 0x01,0x52,0x02,0x14,0x02,0x44           | MODES 12-14: NOTPATCOPY,NOTPATOR,NOTPATXOR
  .byte 0x02,0xAA                               | MODE 15: NOTPATBIC

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
|
| OPTIMIZE RIGHT HORIZONTAL SCROLL IF NO SHIFT.
| ONLY IF MODE 0, BUMPING RIGHT TO LEFT, WORDCNT > 0, AND NO SHIFT.
|
LEFT0:
        MOVE    (A4),D0                         | GET SRC FROM BITMAP
        ADD     A0,A4                           | BUMP LEFT
        AND     D1,D0                           | MASK FIRST WORD
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DATA FROM DST
        OR      D1,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)                         | PUT RESULT TO DST
        ADD     A0,A5                           | BUMP LEFT
        MOVEQ   #-1,D1                          | FLUSH MASK FOR END0
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BEQ.B   END0                            | BR IF NO UNMASKED WORDS
        SUB     A0,A4                           | GET READY FOR PRE-DECREMENT
        SUB     A0,A5                           | GET READY FOR PRE-DECREMENT
        LSR     #1,D2                           | HALVE WORDCOUNT FOR LONGCOUNT
        BCC.B   LONE0                           | BR IF EVEN # WORDS LEFT
        MOVE    -(A4),-(A5)                     | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BRA.B   LMORE0                          | SEE IF ANY LONGS LEFT TO DO

| ----------------------------------------------------------
|
| LTWO0
|
LTWO0:
        MOVE.L  -(A4),-(A5)                     | MOVE A LONG WORD
LONE0:
        MOVE.L  -(A4),-(A5)                     | MOVE ANOTHER LONG
        SUBQ.W  #0x2,D2                         | ADJUST FOR REMAINING WORDS
LMORE0:
        BGT.B   LTWO0                           | YES, AT LEAST 2 LONGS LEFT
        BEQ.B   LONE0                           | YES, FINISH UP LAST LONG
        ADD     A0,A4                           | RETURN TO NORMAL AFTER PRE-DECREMENT
        ADD     A0,A5                           | RETURN TO NORMAL AFTER PRE-DECREMENT
        BRA.B   END0                            | DO LAST WORD WITH MASK

| ------------------------------------------------------------
|
| OPTIMIZE VERTICAL AND LEFT HORIZONTAL SCROLL IF SHIFT = 0.
| ONLY IF MODE 0, BUMPING LEFT TO RIGHT, WORDCNT > 0, AND NO SHIFT.
|
SETUP0:
        LEA.L   FAST0(PC),A1                    | only do setup once
        LEA.L   COPYBIG(PC),A2                  | point to big copy
        BRA     CALCLP                          | share loop calc

| ----------------------------------------------------------
|
| FAST0
|
FAST0:
        MOVE    (A4)+,D0                        | GET SRC FROM BITMAP
        AND     D1,D0                           | MASK FIRST WORD
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)+                        | PUT RESULT TO DST
        MOVEQ   #-1,D1                          | FLUSH MASK FOR END0
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BEQ.B   END0                            | BR IF NO UNMASKED WORDS
        JSR     (A2)                            | call unwound copy loop
        MOVEQ   #-1,D2                          | force finish up below

| -------------------------------------------------------
|
| MODE 0 OR 4: SRC --> DST
|
| Called during boot.
END0:
        AND     D5,D1                           | MASK:=MASK AND LASTMASK
MAIN0:
        MOVE.L  -0x2(A4),D0                     | LOAD 32 BITS OF SRC
        ADD     A0,A4                           | BUMP SRCPTR LEFT OR RIGHT
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        NOT     D1                              | FORM NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)                         | PUT RESULT TO DST
        ADD     A0,A5                           | BUMP DSTPTR LEFT OR RIGHT
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   MAIN0                           | BR IF UNMASKED WORDS LEFT
        BEQ.B   END0                            | DO LAST WORD WITH LASTMASK
        BRA     NXTSRC                          | LOOP BACK FOR MORE

| ----------------------------------------------------------
|
| Call copybig with wordcount in D2 (clobbered)
|
COPYBIG:
        BCLR    #0,D2                           | is wordcount even ?
        BEQ.B   COPYBIG_LOOP                    | IF NO LONGS LEFT BRANCH
        MOVE    (A4)+,(A5)+                     | COPY WORD FROM SRC TO DST
COPYBIG_LOOP:
        SUBI    #0x20,D2                        | DECREMENT 32 BYTES COUNTER
        BLE.B   COPYBIG_DONE                    | IF DONE WITH BLOCK BRANCH
        BSR.B   COPY32                          | else copy 32 words
        BRA.B   COPYBIG_LOOP                    | CONTINUE LOOP

| ----------------------------------------------------------
|
| COPYBIG_DONE
|
COPYBIG_DONE:
        NEG     D2                              | COMPUTE JUMP OFFSET
        JMP     COPY32(PC,D2.W)                 | DISPATCH UNROLLED COPY LOOP

| COPY32 -- else copy 32 words.
| ----------------------------------------------------------
|
| COPY32
|
COPY32:
        MOVE.L  (A4)+,(A5)+                     | TABLE TO COPY 0..32 WORDS
        MOVE.L  (A4)+,(A5)+                     | wordCount = 30
        MOVE.L  (A4)+,(A5)+                     | wordCount = 28
        MOVE.L  (A4)+,(A5)+                     | wordCount = 26
        MOVE.L  (A4)+,(A5)+                     | wordCount = 24
        MOVE.L  (A4)+,(A5)+                     | wordCount = 22
        MOVE.L  (A4)+,(A5)+                     | wordCount = 20
        MOVE.L  (A4)+,(A5)+                     | wordCount = 18
        MOVE.L  (A4)+,(A5)+                     | wordCount = 16
        MOVE.L  (A4)+,(A5)+                     | wordCount = 14
        MOVE.L  (A4)+,(A5)+                     | wordCount = 12
        MOVE.L  (A4)+,(A5)+                     | wordCount = 10
        MOVE.L  (A4)+,(A5)+                     | wordCount = 8
        MOVE.L  (A4)+,(A5)+                     | wordCount = 6
        MOVE.L  (A4)+,(A5)+                     | wordCount = 4
        MOVE.L  (A4)+,(A5)+                     | wordCount = 2
COPY0:
        RTS                                     | wordCount = 0

| ----------------------------------------------------------
|
| COPY31
|
COPY31:
        MOVE.L  (A4)+,(A5)+                     | TABLE TO COPY 1..31 WORDS
        MOVE.L  (A4)+,(A5)+                     | wordCount = 29
        MOVE.L  (A4)+,(A5)+                     | wordCount = 27
        MOVE.L  (A4)+,(A5)+                     | wordCount = 25
        MOVE.L  (A4)+,(A5)+                     | wordCount = 23
        MOVE.L  (A4)+,(A5)+                     | wordCount = 21
        MOVE.L  (A4)+,(A5)+                     | wordCount = 19
        MOVE.L  (A4)+,(A5)+                     | wordCount = 17
        MOVE.L  (A4)+,(A5)+                     | wordCount = 15
        MOVE.L  (A4)+,(A5)+                     | wordCount = 13
        MOVE.L  (A4)+,(A5)+                     | wordCount = 11
        MOVE.L  (A4)+,(A5)+                     | wordCount = 9
        MOVE.L  (A4)+,(A5)+                     | wordCount = 7
        MOVE.L  (A4)+,(A5)+                     | wordCount = 5
        MOVE.L  (A4)+,(A5)+                     | wordCount = 3
        MOVE    (A4)+,(A5)+                     | COPY WORD FROM SRC TO DST
        RTS                                     | return from COPY31


| -------------------------------------------------------
|
| MODE 1 OR 5: SRC OR DST --> DST
|
| Called during boot.
END1:
        AND     D5,D1                           | MASK:=MASK AND LASTMASK
END1_LOOP:
        MOVE.L  -0x2(A4),D0                     | LOAD 32 BITS OF SRC
        ADD     A0,A4                           | BUMP SRCPTR LEFT OR RIGHT
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        OR      D0,(A5)                         | OR SRC INTO DST
        ADD     A0,A5                           | BUMP DSTPTR LEFT OR RIGHT
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   END1_LOOP                       | LOOP TILL LAST WORD
        BEQ.B   END1                            | DO LAST WORD WITH LASTMASK
        BRA     NXTSRC                          | LOOP BACK FOR NEXT ROW

| -------------------------------------------------------
|
| MODE 2 OR 6: SRC XOR DST --> DST
|
| Called during boot.
END2:
        AND     D5,D1                           | MASK:=MASK AND LASTMASK
END2_LOOP:
        MOVE.L  -0x2(A4),D0                     | LOAD 32 BITS OF SRC
        ADD     A0,A4                           | BUMP SRCPTR LEFT OR RIGHT
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        EOR     D0,(A5)                         | XOR SRC INTO DST
        ADD     A0,A5                           | BUMP DSTPTR LEFT OR RIGHT
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   END2_LOOP                       | LOOP TILL LAST WORD
        BEQ.B   END2                            | DO LAST WORD WITH LASTMASK
        BRA     NXTSRC                          | LOOP BACK FOR NEXT ROW

| -------------------------------------------------------
|
| MODE 3 OR 7: SRC BIC DST --> DST
|
| Called during boot.
END3:
        AND     D5,D1                           | MASK:=MASK AND LASTMASK
END3_LOOP:
        MOVE.L  -0x2(A4),D0                     | LOAD 32 BITS OF SRC
        ADD     A0,A4                           | BUMP SRCPTR LEFT OR RIGHT
        LSR.L   D6,D0                           | ALIGN TO DST
        EOR     D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND     D1,D0                           | MASK SRC
        NOT     D0                              | INVERT SRC
        AND     D0,(A5)                         | BIT CLEAR SRC INTO DST
        ADD     A0,A5                           | BUMP DSTPTR LEFT OR RIGHT
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   END3_LOOP                       | LOOP TILL LAST WORD
        BEQ.B   END3                            | DO LAST WORD WITH LASTMASK
        BRA     NXTSRC                          | LOOP BACK FOR NEXT ROW

| -----------------------------------------------------------
|
| OPTIMIZE MODE 8 OR 12 IF DST FITS IN ONE WORD (VERT LINES ETC)
|
| Called during boot.
WORD8:
        AND     D5,D1                           | COMBINE LEFT AND RIGHT MASKS
        MOVE    D1,D5                           | COPY COMBINED MASK
        NOT     D5                              | FORM NOTMASK
WORD8A:
        AND     D1,D6                           | MASK EXTRA PATTERN TO ZEROS
        MOVE    (A5),D0                         | GET DST DATA
        AND     D5,D0                           | AND WITH NOTMASK
        OR      D6,D0                           | MERGE WITH SRC DATA
        MOVE    D0,(A5)+                        | PUT RESULT TO DST
        ADD     A3,A5                           | BUMP DSTPTR TO NEXT ROW
        ADDQ.W  #0x4,D7                         | BUMP PATTERN ROW INDEX
        ANDI    #0x3F,D7                        | WRAP PATTERN ROW INDEX MOD 64
        MOVE    -0x40(A6,D7.W),D6               | LOAD NEXT PATTERN ROW
        DBF     D3,WORD8A                       | LOOP ALL ROWS
        BRA     GOHOME                          | QUIT

| -------------------------------------------------------
|
| MODE 8 OR 12: PATTERN --> DST (FILLING AREAS, DRAWING LINES)
|
| Called during boot.
WORD8A_CONT:
        LEA.L   WORD8A_CONT_4(PC),A1            | only do setup once
        LEA.L   FILLBIG(PC),A2                  | point to big fill
CALCLP:
        CMPI    #0x20,D2                        | CHECK IF BLOCK >= 32 WORDS
        BGT.B   WORD8A_CONT_3                   | BRANCH IF LARGE BLOCK
        ADDA    #0x39,A2                        | OFFSET IN COPY LOOP
        BTST    #0,D2                           | will wordcount-1 be even ?
        BNE.B   WORD8A_CONT_2                   | CONTINUE COPY
        ADDA    #0x21,A2                        | ADJUST LOOP POINTER
WORD8A_CONT_2:
        SUBA    D2,A2                           | CALC UNROLLED ENTRY POINT
WORD8A_CONT_3:
        JMP     (A1)                            | ENTER UNROLLED LOOP

| ----------------------------------------------------------
|
| WORD8A_CONT_4
|
| Called during boot (1,444 times in 30s trace).
WORD8A_CONT_4:
        MOVE    D6,D0                           | FAST8: GET PATTERN DATA
        AND     D1,D0                           | MASK FIRST WORD
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D0                           | MERGE WITH PAT DATA
        MOVE    D0,(A5)+                        | PUT RESULT TO DST
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BEQ.B   END8                            | BR IF NO UNMASKED WORDS
        JSR     (A2)                            | call unwound loop
END8:
        MOVE    D5,D1                           | MASK:= RIGHTMASK
        AND     D1,D6                           | MASK PATTERN
        NOT     D1                              | MAKE NOTMASK
        AND     (A5),D1                         | GET DST DATA
        OR      D1,D6                           | MERGE WITH PAT DATA
        MOVE    D6,(A5)+                        | PUT RESULT TO DST
        BRA     NXTSRC_NEXT                     | LOOP BACK FOR NEXT ROW

| ----------------------------------------------------------
|
| Call fillbig with wordcount in D2 (clobbered)
|
FILLBIG:
        BCLR    #0,D2                           | is wordcount even ?
        BEQ.B   FILLBIG_LOOP                    | IF NO LONGS LEFT BRANCH
        MOVE    D6,(A5)+                        | FILL WORD TO DST
FILLBIG_LOOP:
        SUBI    #0x20,D2                        | DECREMENT 32 BYTES COUNTER
        BLE.B   FILLBIG_DONE                    | IF DONE WITH BLOCK BRANCH
        BSR.B   FILL32                          | elsae fill 32 words
        BRA.B   FILLBIG_LOOP                    | CONTINUE LOOP

| ----------------------------------------------------------
|
| FILLBIG_DONE
|
FILLBIG_DONE:
        NEG     D2                              | COMPUTE JUMP OFFSET
        JMP     FILL32(PC,D2.W)                 | DISPATCH UNROLLED FILL LOOP

| ----------------------------------------------------------
|
| FILL32
|
| Called during boot.
FILL32:
        MOVE.L  D6,(A5)+                        | TABLE TO FILL 0..32 WORDS
        MOVE.L  D6,(A5)+                        | wordCount = 30
        MOVE.L  D6,(A5)+                        | wordCount = 28
        MOVE.L  D6,(A5)+                        | wordCount = 26
        MOVE.L  D6,(A5)+                        | wordCount = 24
        MOVE.L  D6,(A5)+                        | wordCount = 22
        MOVE.L  D6,(A5)+                        | wordCount = 20
        MOVE.L  D6,(A5)+                        | wordCount = 18
        MOVE.L  D6,(A5)+                        | wordCount = 16
        MOVE.L  D6,(A5)+                        | wordCount = 14
        MOVE.L  D6,(A5)+                        | wordCount = 12
        MOVE.L  D6,(A5)+                        | wordCount = 10
        MOVE.L  D6,(A5)+                        | wordCount = 8
        MOVE.L  D6,(A5)+                        | wordCount = 6
        MOVE.L  D6,(A5)+                        | wordCount = 4
        MOVE.L  D6,(A5)+                        | wordCount = 2
        RTS                                     | wordCount = 0

| ----------------------------------------------------------
|
| FILL31
|
| Called during boot.
FILL31:
        MOVE.L  D6,(A5)+                        | TABLE TO FILL 1..31 WORDS
        MOVE.L  D6,(A5)+                        | wordCount = 29
        MOVE.L  D6,(A5)+                        | wordCount = 27
        MOVE.L  D6,(A5)+                        | wordCount = 25
        MOVE.L  D6,(A5)+                        | wordCount = 23
        MOVE.L  D6,(A5)+                        | wordCount = 21
        MOVE.L  D6,(A5)+                        | wordCount = 19
        MOVE.L  D6,(A5)+                        | wordCount = 17
        MOVE.L  D6,(A5)+                        | wordCount = 15
        MOVE.L  D6,(A5)+                        | wordCount = 13
        MOVE.L  D6,(A5)+                        | wordCount = 11
        MOVE.L  D6,(A5)+                        | wordCount = 9
        MOVE.L  D6,(A5)+                        | wordCount = 7
        MOVE.L  D6,(A5)+                        | wordCount = 5
        MOVE.L  D6,(A5)+                        | wordCount = 3
        MOVE    D6,(A5)+                        | FILL WORD TO DST
        RTS                                     | return from FILL31


| -------------------------------------------------------
|
| MODE 9 OR 13: PATTERN OR DST --> DST
|
FILL31_CONT:
        AND     D5,D1                           | END9: MASK:=MASK AND LASTMASK
MAIN9:
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     D1,D0                           | MASK PATTERN
        OR      D0,(A5)+                        | OR PATTERN INTO DST
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   MAIN9                           | LOOP TILL LAST WORD
        BEQ.B   FILL31_CONT                     | DO LAST WORD WITH LASTMASK
        BRA     NXTSRC_NEXT                     | LOOP BACK FOR NEXT ROW

| -------------------------------------------------------
|
| MODE 10 OR 14: PATTERN XOR DST --> DST (INVERTING AREAS, XOR LINES)
|
| Called during boot.
MAIN9_CONT:
        LEA.L   MAIN9_CONT_2(PC),A1             | only do setup once
        LEA.L   XORBIG(PC),A2                   | point to big fill
        BRA     CALCLP                          | share loop calc

| ----------------------------------------------------------
|
| MAIN9_CONT_2
|
| Called during boot (1,516 times in 30s trace).
MAIN9_CONT_2:
        MOVE    D6,D0                           | FAST10: GET PATTERN DATA
        AND     D1,D0                           | MASK FIRST WORD
        EOR     D0,(A5)+                        | XOR PATTERN INTO DST
        MOVEQ   #-1,D1                          | FLUSH MASK FOR END10
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BEQ.B   MAIN9_NO                        | BR IF NO UNMASKED WORDS
        JSR     (A2)                            | call unwound loop
        MOVEQ   #-1,D2                          | force finish up below
MAIN9_NO:
        AND     D5,D1                           | END10: MASK:=MASK AND LASTMASK
        AND     D1,D6                           | MASK PATTERN
        EOR     D6,(A5)+                        | XOR PATTERN DATA INTO DST
        BRA     NXTSRC_NEXT                     | LOOP BACK FOR NEXT ROW

| ----------------------------------------------------------
|
| Call XORbig with wordcount in D2 (clobbered)
|
XORBIG:
        BCLR    #0,D2                           | is wordcount even ?
        BEQ.B   XORBIG_LOOP                     | IF NO LONGS LEFT BRANCH
        EOR     D6,(A5)+                        | XOR WORD TO DST
XORBIG_LOOP:
        SUBI    #0x20,D2                        | DECREMENT 32 BYTES COUNTER
        BLE.B   XORBIG_DONE                     | IF DONE WITH BLOCK BRANCH
        BSR.B   XOR32                           | else XOR 32 words
        BRA.B   XORBIG_LOOP                     | CONTINUE LOOP

| ----------------------------------------------------------
|
| XORBIG_DONE
|
XORBIG_DONE:
        NEG     D2                              | COMPUTE JUMP OFFSET
        JMP     XOR32(PC,D2.W)                  | DISPATCH UNROLLED XOR LOOP

| ----------------------------------------------------------
|
| XOR32
|
| Called during boot.
XOR32:
        EOR.L   D6,(A5)+                        | TABLE TO XOR 0..32 WORDS
        EOR.L   D6,(A5)+                        | wordCount = 30
        EOR.L   D6,(A5)+                        | wordCount = 28
        EOR.L   D6,(A5)+                        | wordCount = 26
        EOR.L   D6,(A5)+                        | wordCount = 24
        EOR.L   D6,(A5)+                        | wordCount = 22
        EOR.L   D6,(A5)+                        | wordCount = 20
        EOR.L   D6,(A5)+                        | wordCount = 18
        EOR.L   D6,(A5)+                        | wordCount = 16
        EOR.L   D6,(A5)+                        | wordCount = 14
        EOR.L   D6,(A5)+                        | wordCount = 12
        EOR.L   D6,(A5)+                        | wordCount = 10
        EOR.L   D6,(A5)+                        | wordCount = 8
        EOR.L   D6,(A5)+                        | wordCount = 6
        EOR.L   D6,(A5)+                        | wordCount = 4
        EOR.L   D6,(A5)+                        | wordCount = 2
        RTS                                     | wordCount = 0

| ----------------------------------------------------------
|
| XOR31
|
| Called during boot.
XOR31:
        EOR.L   D6,(A5)+                        | TABLE TO XOR 1..31 WORDS
        EOR.L   D6,(A5)+                        | wordCount = 29
        EOR.L   D6,(A5)+                        | wordCount = 27
        EOR.L   D6,(A5)+                        | wordCount = 25
        EOR.L   D6,(A5)+                        | wordCount = 23
        EOR.L   D6,(A5)+                        | wordCount = 21
        EOR.L   D6,(A5)+                        | wordCount = 19
        EOR.L   D6,(A5)+                        | wordCount = 17
        EOR.L   D6,(A5)+                        | wordCount = 15
        EOR.L   D6,(A5)+                        | wordCount = 13
        EOR.L   D6,(A5)+                        | wordCount = 11
        EOR.L   D6,(A5)+                        | wordCount = 9
        EOR.L   D6,(A5)+                        | wordCount = 7
        EOR.L   D6,(A5)+                        | wordCount = 5
        EOR.L   D6,(A5)+                        | wordCount = 3
        EOR     D6,(A5)+                        | XOR WORD TO DST
        RTS                                     | return from XOR31


| -------------------------------------------------------
|
| MODE 11 OR 15: PATTERN BIC DST --> DST
|
| Called during boot.
XOR31_CONT:
        AND     D5,D1                           | END11: MASK:=MASK AND LASTMASK
MAIN11:
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     D1,D0                           | MASK PATTERN
        NOT     D0                              | INVERT PATTERN
        AND     D0,(A5)+                        | BIC PATTERN INTO DST
        MOVEQ   #-1,D1                          | FLUSH MASK
        SUBQ.W  #0x1,D2                         | DECREMENT LONG WORD COUNTER
        BGT.B   MAIN11                          | LOOP TILL LAST WORD
        BEQ.B   XOR31_CONT                      | DO LAST WITH LASTMASK
        BRA     NXTSRC_NEXT                     | LOOP BACK FOR NEXT ROW

| QuickDraw copyright notice embedded by Bill Atkinson in BitBlt.
| Unreachable code (after BRA above); serves as a hidden ROM signature.
  .ascii "(c) Apple Computer Inc., 1983-1985"   | COPYRIGHT STRING IN ROM


