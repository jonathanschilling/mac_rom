| ---------------------------------------------------------------
|
| --> BITBLT.TEXT
|
| Low-level bit boundary block transfer.

| .PROC BITBLT,7
| .REF LEFTMASK,RIGHTMASK,PATEXPAND
| --------------------------------------------------------------
|
| PROCEDURE BitBlt(srcBits,dstBits: BitMap;
|                  srcRect,dstRect: Rect;
|                  mode: INTEGER; pat: Pattern);
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
| MODES:  0 SRC --> DST          8 PATTERN --> DST
|         1 SRC OR DST --> DST   9 PATTERN OR DST --> DST
|         2 SRC XOR DST --> DST  10 PATTERN XOR DST --> DST
|         3 SRC BIC DST --> DST  11 PATTERN BIC DST --> DST
|         4 (NOT SRC) --> DST    12 (NOT PATTERN) --> DST
|         5 (NOT SRC) OR --> DST 13 (NOT PATTERN) OR --> DST
|         6 (NOT SRC) XOR        14 (NOT PATTERN) XOR
|         7 (NOT SRC) BIC        15 (NOT PATTERN) BIC
|
| Called during boot.
BITBLT:
    LINK	A6,#-0x52                              | ALLOCATE LOCAL VARIABLES
| ENTER HERE. CALLER TAKES CARE OF CURSOR.
    MOVEM.L	D3-D7/A2-A5,-(A7)                   | SAVE REGS
    MOVE.L	A5,-0x52(A6)                         | SAVE GLOBAL POINTER
| ----------------------------------------------------------------------
|
| GET PARAMETER POINTERS IN REGISTERS
|
    MOVEA.L	0x12(A6),A2                         | A2 POINTS TO SRCRECT
    MOVEA.L	0xE(A6),A3                          | A3 POINTS TO DSTRECT
    MOVEA.L	0x1A(A6),A4                         | A4 POINTS TO SRCBITS
    MOVEA.L	0x16(A6),A5                         | A5 POINTS TO DSTBITS
| -------------------------------------------------------------
|
| CALC HEIGHT OF DSTRECT. QUIT IF HEIGHT <= 0
|
    MOVE.W	0x4(A3),D0                           | GET BOTTOM
    SUB.W	(A3),D0                               | CALC HEIGHT
    BLE.W	GOHOME                                | QUIT IF HEIGHT <= 0
    MOVE.W	D0,-0x4C(A6)                         | SAVE FOR LATER
| --------------------------------------------------------------
|
| SET UP FOR TOP TO BOTTOM, LEFT TO RIGHT
| GET SRC AND DST TOP AND ROWBYTES
|
    MOVEQ.L	#0x2,D3                             | BUMP:=2 (TRANSFER LEFT TO RIGHT)
    MOVE.W	(A2),D0                              | GET SRC TOP
    SUB.W	0x6(A4),D0                            | CONVERT SRC TOP TO GLOBAL
    MOVE.W	D0,-0x42(A6)                         | SAVE FOR LATER
    MOVE.W	(A3),D0                              | GET DST TOP
    SUB.W	0x6(A5),D0                            | CONVERT DST TOP TO GLOBAL
    MOVE.W	D0,-0x44(A6)                         | SAVE FOR LATER
    MOVE.W	0x4(A4),-0x46(A6)                    | SRCROW:=SRCBITS.ROWBYTES
    MOVE.W	0x4(A5),-0x48(A6)                    | DSTROW:=DSTBITS.ROWBYTES
| --------------------------------------------------------------------
|
| SET UP INVERT FLAG, IN CASE SRC OR PATTERN WILL BE INVERTED
|
    CLR.W	D7                                    | SAY NOT INVERTED
    MOVE.W	0xC(A6),D0                           | GET TRANSFER MODE
    BTST	#0x2,D0                                | IS MODE AN INV. ONE ?
    BEQ.B	MODEOK                                | NOT INVERTED, CONTINUE
    NOT.W	D7                                    | INVERTED, PUT -1 IN INVERT REG
MODEOK:
    BTST	#0x3,D0                                | WILL WE USE PATTERN ?
    BEQ.B	DIREC                                 | NO, DON'T BOTHER TO SET UP
    MOVE.W	0x8(A5),D2                           | GET DST LEFT FOR PATTERN ALIGN
| ------------------------------------------------------------
|
| PATTERN WILL BE USED. EXPAND 8 BYTE PATTERN TO 16 LONGS.
|
    MOVEA.L	0x8(A6),A0                          | POINT TO BYTE WIDE PATTERN
    LEA.L	-0x40(A6),A1                          | POINT TO EXPANDED PATTERN
    MOVEA.L	-0x52(A6),A5                        | GET GLOBAL POINTER
    JSR	PATEXPAND(PC)                           | EXPAND 8 BYTES TO 16 LONGS
    MOVEA.L	0x16(A6),A5                         | RESTORE A5 TO DSTBITS
| ------------------------------------------------------------
|
| SET UP (VERT * 4) MOD 64 AS PATTERN SELECTOR
|
    MOVEQ.L	#0xF,D7                             | TREAT COORD MOD 16
    AND.W	(A3),D7                               | TREAT COORD MOD 16
    LSL.W	#0x2,D7                               | QUAD FOR LONG PATTERNS
    MOVE.L	-0x40(A6,D7.W),D6                    | LOAD PATTERN ROW
    BRA.B	NOTSRC                                | NOT USING SRC, SKIP OVER
| ----------------------------------------------------------
|
| DIREC: SOURCE WILL BE USED, SO SET UP VERT AND HORIZ DIRECTIONS
|        SUCH THAT SRC WON'T GET CLOBBERED TILL AFTER IT HAS BEEN USED.
|
| Called during boot.
DIREC:
    MOVE.L	(A4),D0                              | GET SRC BASEADDR
    CMP.L	(A5),D0                               | COMPARE SRC AND DST BASEADDR
    BNE.B	GETSRC                                | NO, DON'T WORRY ABOUT OVERLAP
    MOVE.W	-0x42(A6),D0                         | GET SRCV
    CMP.W	-0x44(A6),D0                          | IS SRCV > DSTV ?
    BGT.B	GETSRC                                | YES, CONTINUE WITH TOP TO BOTTOM
    BLT.B	UPSIDE                                | NO, GO UPSIDE DOWN
    MOVE.W	0x2(A2),D0                           | GET SRC LEFT
    SUB.W	0x8(A4),D0                            | CONVERT TO GLOBAL
    MOVE.W	0x2(A3),D1                           | GET DST LEFT
    SUB.W	0x8(A5),D1                            | CONVERT TO GLOBAL
    CMP.W	D1,D0                                 | IS SRCH >= DSTH ?
    BGE.B	GETSRC                                | YES, CONTINUE LEFT-TO-RIGHT
    NEG.W	D3                                    | NO, REVERSE BUMP TO RIGHT-TO-LEFT
    BRA.B	GETSRC                                | AND CONTINUE
| ----------------------------------------------------------
|
| DO UPSIDE DOWN TO AVOID CLOBBERING SRC
|
UPSIDE:
    MOVE.W	-0x4C(A6),D0                         | GET HEIGHT
    SUBQ.W	#0x1,D0                              | ADJUST FOR INDEX
    ADD.W	D0,-0x42(A6)                          | BUMP SRCV TO BOTTOM
    ADD.W	D0,-0x44(A6)                          | BUMP DSTV TO BOTTOM
    NEG.W	-0x46(A6)                             | NEGATE SRCROW (UP-PASS)
    NEG.W	-0x48(A6)                             | NEGATE DSTROW (UP-PASS)
| -----------------------------------------------------
|
| SET UP SHIFTCNT IN D6 (RELATIVE SHIFT BETWEEN SRC & DST)
|
| Called during boot.
GETSRC:
    MOVE.W	0x2(A3),D6                           | GET DSTLEFT
    SUB.W	0x8(A5),D6                            | CONVERT TO GLOBAL
    MOVE.W	0x2(A2),D1                           | GET SRCLEFT
    SUB.W	0x8(A4),D1                            | CONVERT TO GLOBAL
    SUB.W	D1,D6                                 | CALC SHIFTCNT MOD 16 = (DSTH-SRCH)
    ANDI.W	#0xF,D6                              | MASK TO 4 BITS
    MOVE.W	-0x42(A6),D0                         | GET SRCV
    MULU.W	0x4(A4),D0                           | TIMES SRCROW = TOP-OF-ROW OFFSET
    MOVEA.L	(A4),A4                             | A4 := SRC BASEADDR
    ADDA.L	D0,A4                                | + ROW OFFSET
    ADD.W	D6,D1                                 | ADD SHIFTCNT TO SRCH
    ASR.W	#0x3,D1                               | DIV BY 8 FOR BYTE OFFSET
    ANDI.W	#0xFFFE,D1                           | TRUNCATE TO WORD BOUNDARY
    ADDA.W	D1,A4                                | + HORIZ BYTE OFFSET
| ------------------------------------------------------------
|
| SET UP DSTLEFT IN A5, ADDR OF LEFTMOST DST WORD
| (GOODBYE DSTBITS PTR)
|
| Called during boot.
NOTSRC:
    MOVE.W	0x2(A3),D1                           | GET DST LEFT
    SUB.W	0x8(A5),D1                            | CONVERT DST LEFT TO GLOBAL
    MOVE.W	-0x44(A6),D0                         | GET FIRST DST VERT
    MULU.W	0x4(A5),D0                           | CALC DSTROW * FIRST DST VERT
    MOVEA.L	(A5),A5                             | LOAD DST BASEADDR
    ADDA.L	D0,A5                                | ADD DSTV*DSTROW
    MOVE.W	D1,D0                                | COPY DSTLEFT GLOBAL
    ASR.W	#0x4,D1                               | CONVERT FROM DOTS TO WORDS
    ADD.W	D1,D1                                 | DOUBLE FOR BYTES
    ADDA.W	D1,A5                                | LEAVE DSTLEFT IN A5
| -------------------------------------
|
| SET UP LEFTMASK IN D4
|
    MOVE.W	D0,D1                                | SAVE DSTH
    JSR	LEFTMASK(PC)                            | GET LEFTMASK
    MOVE.W	D0,D4                                | PUT IN D4
    ANDI.W	#0xF,D1                              | CALC DST LEFT MOD 16
| -------------------------------------
|
| SET UP RIGHTMASK IN D5
|
    MOVE.W	0x6(A3),D0                           | GET DST RIGHT
    SUB.W	0x2(A3),D0                            | CALC WIDTH
    BLE.W	GOHOME                                | QUIT IF WIDTH <= 0
    ADD.W	D1,D0                                 | CALC (DSTH MOD 16) + WIDTH
    MOVE.W	D0,D1                                | MAKE AN EXTRA COPY
    JSR	RIGHTMASK(PC)                           | GET RIGHT MASK
    MOVE.W	D0,D5                                | SAVE RIGHTMASK IN D5
| ------------------------------------------------
|
| CALC TOTAL NUMBER OF DST WORDS-1
|
    ASR.W	#0x4,D1                               | CALC ((DSTH MOD 16)+WIDTH) DIV 16
    MOVE.W	D1,-0x4E(A6)                         | SAVE AS WORDCNT
    MOVE.W	D1,D2                                | set up for below
|
| Set up srcBump and dstBump, assuming bumping to the right
|
    ADD.W	D1,D1                                 | calc 2*wordCount
    MOVE.W	D1,D0                                | make a copy
    ADDQ.W	#0x2,D0                              | ROUND UP WORD COUNT
| --------------------------------------------------------------------------
|
| IF DRAWING BACKWARDS FROM RIGHT, then adjust dstBump,
| ADJUST SRCADDR,DSTADDR TO FIRST WORD,
| AND SWAP LEFT AND RIGHT MASKS FOR FIRSTMASK AND LASTMASK.
|
    MOVEA.W	D3,A0                               | put hBump (+-2) into A0
    TST.W	D3                                    | ARE WE STARTING ON THE LEFT ?
    BPL.B	DIROK                                 | YES, CONTINUE
    NEG.W	D0                                    | calc -1 * bytesNeeded
    ADDA.W	D1,A5                                | ADJUST DSTADDR TO RIGHTMOST
    ADDA.W	D1,A4                                | ADJUST SRCADDR TO RIGHTMOST
    EXG	D4,D5                                   | FIRSTMASK=RIGHT,LASTMASK=LEFT
DIROK:
    MOVE.W	-0x46(A6),-0x4A(A6)                  | COPY SRCROW TO CURSRCROW
    SUB.W	D0,-0x4A(A6)                          | srcBump := srcRow +- bytesBumped
    MOVEA.W	-0x48(A6),A3                        | LOAD DSTROW
    SUBA.W	D0,A3                                | dstBump := dstRow +- bytesBumped
| ----------------------------------------------
|
| SET UP MODE CASE JUMP IN A1
|
    MOVE.W	0xC(A6),D0                           | GET TRANSFER MODE
    BNE.B	DIROK_NO                              | BR IF NOT MODE 0
    TST.W	D6                                    | IS SHIFTCNT 0 ?
    BNE.B	DIROK_NO                              | NO, CONTINUE
    TST.W	-0x4E(A6)                             | IS WORDCNT > 0 ?
    BLE.B	DIROK_NO                              | NO, CONTINUE
    LEA.L	SETUP0(PC),A1                         | USE FAST COPY.
    TST.W	D3                                    | ARE WE BUMPING LEFT TO RIGHT ?
    BPL.B	NEXTROW                               | YES, ALL SET
    LEA.L	LEFT0(PC),A1                          | NO, USE BACKWARDS LOOP
    BRA.B	NEXTROW                               | GO TO NEXT ROW
| ----------------------------------------------------------
|
| DIROK_NO
|
| Called during boot.
DIROK_NO:
    ANDI.W	#0xB,D0                              | FILTER MODE BITS
    MOVE.W	D0,D1                                | MAKE A COPY
    ANDI.W	#0x3,D0                              | MASK MODE TO 0-3
    ADD.W	D0,D1                                 | MAKE MODIFIED MODE * 2 FOR INDEX
    TST.W	D2                                    | IS DST ALL IN ONE WORD ?
    BNE.B	DOMAIN                                | NO, USE FIRST JUMP TABLE
    ADDI.W	#0x10,D1                             | CALC BRANCH OFFSET BASE
DOMAIN:
    LEA.L	MODETAB(PC),A1                        | GET ADDRESS OF MODE TABLE
    ADDA.W	0x0(A1,D1.W),A1                      | CALC DISPATCH ADDRESS
| ---------------------------------------------------------
|
| OUTER LOOP: DO EACH SCAN LINE AND COME BACK TO NXTSRC OR NXTPAT.
| SOME MODES OPTIMIZE AND DO WHOLE OUTER LOOP AND COME BACK TO GOHOME.
|
| Called during boot.
NEXTROW:
    MOVE.W	-0x4C(A6),D3                         | get height
    SUBQ.W	#0x1,D3                              | DECREMENT ROW COUNTER
| Called during boot (8,945 times in 30s trace).
ROWLOOP:
    MOVE.W	D4,D1                                | MASK:=FIRSTMASK
    MOVE.W	-0x4E(A6),D2                         | GET WORDCOUNT
    JMP	(A1)                                    | DO THIS ROW AND COME BACK
| ----------------------------------------------------------
|
| NXTSRC
|
| Called during boot (1,458 times in 30s trace).
NXTSRC:
    ADDA.W	-0x4A(A6),A4                         | bump srcPtr to next row
    ADDA.W	A3,A5                                | BUMP DSTADDR TO NEXT ROW
    DBF.W	D3,ROWLOOP                            | loop for all srcRows
    BRA.B	GOHOME                                | then quit
| ----------------------------------------------------------
|
| NXTSRC_NEXT
|
| Called during boot (7,476 times in 30s trace).
NXTSRC_NEXT:
    ADDQ.W	#0x4,D7                              | BUMP PATTERN ROW INDEX
    ANDI.W	#0x3F,D7                             | WRAP PATTERN ROW INDEX MOD 64
    MOVE.L	-0x40(A6,D7.W),D6                    | LOAD PATTERN ROW
    ADDA.W	A3,A5                                | BUMP DSTADDR TO NEXT ROW
    DBF.W	D3,ROWLOOP                            | loop for all srcRows
| then quit
| Called during boot.
GOHOME:
    MOVEM.L	(A7)+,D3-D7/A2-A5                   | RESTORE REGS
    UNLK	A6                                     | TEAR DOWN STACK FRAME
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    ADDA.W	#0x16,A7                             | POP PARAMETERS
    JMP	(A0)                                    | RETURN TO CALLER
| ----------------------------------------------------------
|
| MODETAB: 32-byte word offset table indexed by (mode mod 4)*2 plus
| a +0x10 bias when DST spans more than one word.  Entries point at
| BitBlt scanline routines.  The table's structure matches the
| 16-mode dispatch, with optimized variants for each pattern and bit
| operation (SRCCOPY, SRCOR, SRCXOR, SRCBIC, NOTSRC*, PATCOPY,
| PATOR, PATXOR, PATBIC, NOTPAT*).
|
MODETAB:
    .long	0x007800F8                            | MODES 0,1: SRCCOPY,SRCOR
    .long	0x01160134                            | MODES 2,3: SRCXOR,SRCBIC
    .long	0x01760216                            | MODES 4,5: NOTSRCCOPY,NOTSRCOR
    .long	0x022802AC                            | MODES 6,7: NOTSRCXOR,NOTSRCBIC
    .long	0x007600F6                            | MODES 8,9: PATCOPY,PATOR
    .long	0x01140132                            | MODES 10,11: PATXOR,PATBIC
    .long	0x01520214                            | MODES 12,13: NOTPATCOPY,NOTPATOR
    .long	0x024402AA                            | MODES 14,15: NOTPATXOR,NOTPATBIC
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
    MOVE.W	(A4),D0                              | GET SRC FROM BITMAP
    ADDA.W	A0,A4                                | BUMP LEFT
    AND.W	D1,D0                                 | MASK FIRST WORD
    NOT.W	D1                                    | MAKE NOTMASK
    AND.W	(A5),D1                               | GET DATA FROM DST
    OR.W	D1,D0                                  | MERGE WITH SRC DATA
    MOVE.W	D0,(A5)                              | PUT RESULT TO DST
    ADDA.W	A0,A5                                | BUMP LEFT
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK FOR END0
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BEQ.B	END0                                  | BR IF NO UNMASKED WORDS
    SUBA.W	A0,A4                                | GET READY FOR PRE-DECREMENT
    SUBA.W	A0,A5                                | GET READY FOR PRE-DECREMENT
    LSR.W	#0x1,D2                               | HALVE WORDCOUNT FOR LONGCOUNT
    BCC.B	LONE0                                 | BR IF EVEN # WORDS LEFT
    MOVE.W	-(A4),-(A5)                          | ELSE MAKE EVEN BY DOING A WORD
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BRA.B	LMORE0                                | SEE IF ANY LONGS LEFT TO DO
| ----------------------------------------------------------
|
| LTWO0
|
LTWO0:
    MOVE.L	-(A4),-(A5)                          | MOVE A LONG WORD
LONE0:
    MOVE.L	-(A4),-(A5)                          | MOVE ANOTHER LONG
    SUBQ.W	#0x2,D2                              | ADJUST FOR REMAINING WORDS
LMORE0:
    BGT.B	LTWO0                                 | YES, AT LEAST 2 LONGS LEFT
    BEQ.B	LONE0                                 | YES, FINISH UP LAST LONG
    ADDA.W	A0,A4                                | RETURN TO NORMAL AFTER PRE-DECREMENT
    ADDA.W	A0,A5                                | RETURN TO NORMAL AFTER PRE-DECREMENT
    BRA.B	END0                                  | DO LAST WORD WITH MASK
| ------------------------------------------------------------
|
| OPTIMIZE VERTICAL AND LEFT HORIZONTAL SCROLL IF SHIFT = 0.
| ONLY IF MODE 0, BUMPING LEFT TO RIGHT, WORDCNT > 0, AND NO SHIFT.
|
SETUP0:
    LEA.L	FAST0(PC),A1                          | only do setup once
    LEA.L	COPYBIG(PC),A2                        | point to big copy
    BRA.W	CALCLP                                | share loop calc
| ----------------------------------------------------------
|
| FAST0
|
FAST0:
    MOVE.W	(A4)+,D0                             | GET SRC FROM BITMAP
    AND.W	D1,D0                                 | MASK FIRST WORD
    NOT.W	D1                                    | MAKE NOTMASK
    AND.W	(A5),D1                               | GET DST DATA
    OR.W	D1,D0                                  | MERGE WITH SRC DATA
    MOVE.W	D0,(A5)+                             | PUT RESULT TO DST
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK FOR END0
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BEQ.B	END0                                  | BR IF NO UNMASKED WORDS
    JSR	(A2)                                    | call unwound copy loop
    MOVEQ.L	#-0x1,D2                            | force finish up below
| -------------------------------------------------------
|
| MODE 0 OR 4: SRC --> DST
|
| Called during boot.
END0:
    AND.W	D5,D1                                 | MASK:=MASK AND LASTMASK
MAIN0:
    MOVE.L	-0x2(A4),D0                          | LOAD 32 BITS OF SRC
    ADDA.W	A0,A4                                | BUMP SRCPTR LEFT OR RIGHT
    LSR.L	D6,D0                                 | ALIGN TO DST
    EOR.W	D7,D0                                 | INVERT SRC IF MODE BIT 2 SET
    AND.W	D1,D0                                 | MASK SRC
    NOT.W	D1                                    | FORM NOTMASK
    AND.W	(A5),D1                               | GET DST DATA
    OR.W	D1,D0                                  | MERGE WITH SRC DATA
    MOVE.W	D0,(A5)                              | PUT RESULT TO DST
    ADDA.W	A0,A5                                | BUMP DSTPTR LEFT OR RIGHT
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BGT.B	MAIN0                                 | BR IF UNMASKED WORDS LEFT
    BEQ.B	END0                                  | DO LAST WORD WITH LASTMASK
    BRA.W	NXTSRC                                | LOOP BACK FOR MORE
| ----------------------------------------------------------
|
| Call copybig with wordcount in D2 (clobbered)
|
COPYBIG:
    BCLR	#0x0,D2                                | is wordcount even ?
    BEQ.B	COPYBIG_LOOP                          | IF NO LONGS LEFT BRANCH
    MOVE.W	(A4)+,(A5)+                          | COPY WORD FROM SRC TO DST
COPYBIG_LOOP:
    SUBI.W	#0x20,D2                             | DECREMENT 32 BYTES COUNTER
    BLE.B	COPYBIG_DONE                          | IF DONE WITH BLOCK BRANCH
    BSR.B	COPY32                                | else copy 32 words
    BRA.B	COPYBIG_LOOP                          | CONTINUE LOOP
| ----------------------------------------------------------
|
| COPYBIG_DONE
|
COPYBIG_DONE:
    NEG.W	D2                                    | COMPUTE JUMP OFFSET
    JMP	COPY32(PC,D2.W)                         | DISPATCH UNROLLED COPY LOOP
| ----------------------------------------------------------
|
| COPY32: 16-long unrolled copy table.  Entry point copies all 32
| words; entering at later addresses copies fewer (the "Duff's device"
| pattern, dispatched by COPYBIG_DONE via PC-relative jump).
|
| The follow-on COPY31 (after the first RTS) is a parallel table for
| odd word counts - it copies an extra word at the end via MOVE.W
| instead of MOVE.L for byte-aligned correctness.
|
COPY32:
    MOVE.L	(A4)+,(A5)+                          | TABLE TO COPY 0..32 WORDS
    MOVE.L	(A4)+,(A5)+                          | wordCount = 30
    MOVE.L	(A4)+,(A5)+                          | wordCount = 28
    MOVE.L	(A4)+,(A5)+                          | wordCount = 26
    MOVE.L	(A4)+,(A5)+                          | wordCount = 24
    MOVE.L	(A4)+,(A5)+                          | wordCount = 22
    MOVE.L	(A4)+,(A5)+                          | wordCount = 20
    MOVE.L	(A4)+,(A5)+                          | wordCount = 18
    MOVE.L	(A4)+,(A5)+                          | wordCount = 16
    MOVE.L	(A4)+,(A5)+                          | wordCount = 14
    MOVE.L	(A4)+,(A5)+                          | wordCount = 12
    MOVE.L	(A4)+,(A5)+                          | wordCount = 10
    MOVE.L	(A4)+,(A5)+                          | wordCount = 8
    MOVE.L	(A4)+,(A5)+                          | wordCount = 6
    MOVE.L	(A4)+,(A5)+                          | wordCount = 4
    MOVE.L	(A4)+,(A5)+                          | wordCount = 2
| COPY0:
    RTS                                         | wordCount = 0
| COPY31: 1..31 word odd-count table
    MOVE.L	(A4)+,(A5)+                          | TABLE TO COPY 1..31 WORDS
    MOVE.L	(A4)+,(A5)+                          | wordCount = 29
    MOVE.L	(A4)+,(A5)+                          | wordCount = 27
    MOVE.L	(A4)+,(A5)+                          | wordCount = 25
    MOVE.L	(A4)+,(A5)+                          | wordCount = 23
    MOVE.L	(A4)+,(A5)+                          | wordCount = 21
    MOVE.L	(A4)+,(A5)+                          | wordCount = 19
    MOVE.L	(A4)+,(A5)+                          | wordCount = 17
    MOVE.L	(A4)+,(A5)+                          | wordCount = 15
    MOVE.L	(A4)+,(A5)+                          | wordCount = 13
    MOVE.L	(A4)+,(A5)+                          | wordCount = 11
    MOVE.L	(A4)+,(A5)+                          | wordCount = 9
    MOVE.L	(A4)+,(A5)+                          | wordCount = 7
    MOVE.L	(A4)+,(A5)+                          | wordCount = 5
    MOVE.L	(A4)+,(A5)+                          | wordCount = 3
    MOVE.W	(A4)+,(A5)+                          | COPY WORD FROM SRC TO DST
    RTS                                         | AND RETURN
| -------------------------------------------------------
|
| MODE 1 OR 5: SRC OR DST --> DST
|
| Called during boot.
END1:
    AND.W	D5,D1                                 | MASK:=MASK AND LASTMASK
END1_LOOP:
    MOVE.L	-0x2(A4),D0                          | LOAD 32 BITS OF SRC
    ADDA.W	A0,A4                                | BUMP SRCPTR LEFT OR RIGHT
    LSR.L	D6,D0                                 | ALIGN TO DST
    EOR.W	D7,D0                                 | INVERT SRC IF MODE BIT 2 SET
    AND.W	D1,D0                                 | MASK SRC
    OR.W	D0,(A5)                                | OR SRC INTO DST
    ADDA.W	A0,A5                                | BUMP DSTPTR LEFT OR RIGHT
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BGT.B	END1_LOOP                             | LOOP TILL LAST WORD
    BEQ.B	END1                                  | DO LAST WORD WITH LASTMASK
    BRA.W	NXTSRC                                | LOOP BACK FOR NEXT ROW
| -------------------------------------------------------
|
| MODE 2 OR 6: SRC XOR DST --> DST
|
| Called during boot.
END2:
    AND.W	D5,D1                                 | MASK:=MASK AND LASTMASK
END2_LOOP:
    MOVE.L	-0x2(A4),D0                          | LOAD 32 BITS OF SRC
    ADDA.W	A0,A4                                | BUMP SRCPTR LEFT OR RIGHT
    LSR.L	D6,D0                                 | ALIGN TO DST
    EOR.W	D7,D0                                 | INVERT SRC IF MODE BIT 2 SET
    AND.W	D1,D0                                 | MASK SRC
    EOR.W	D0,(A5)                               | XOR SRC INTO DST
    ADDA.W	A0,A5                                | BUMP DSTPTR LEFT OR RIGHT
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BGT.B	END2_LOOP                             | LOOP TILL LAST WORD
    BEQ.B	END2                                  | DO LAST WORD WITH LASTMASK
    BRA.W	NXTSRC                                | LOOP BACK FOR NEXT ROW
| -------------------------------------------------------
|
| MODE 3 OR 7: SRC BIC DST --> DST
|
| Called during boot.
END3:
    AND.W	D5,D1                                 | MASK:=MASK AND LASTMASK
END3_LOOP:
    MOVE.L	-0x2(A4),D0                          | LOAD 32 BITS OF SRC
    ADDA.W	A0,A4                                | BUMP SRCPTR LEFT OR RIGHT
    LSR.L	D6,D0                                 | ALIGN TO DST
    EOR.W	D7,D0                                 | INVERT SRC IF MODE BIT 2 SET
    AND.W	D1,D0                                 | MASK SRC
    NOT.W	D0                                    | invert: 0 where SRC was 1
    AND.W	D0,(A5)                               | AND notSrc into DST (= BIC)
    ADDA.W	A0,A5                                | BUMP DSTPTR LEFT OR RIGHT
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BGT.B	END3_LOOP                             | LOOP TILL LAST WORD
    BEQ.B	END3                                  | DO LAST WORD WITH LASTMASK
    BRA.W	NXTSRC                                | LOOP BACK FOR NEXT ROW
| -----------------------------------------------------------
|
| OPTIMIZE MODE 8 OR 12 IF DST FITS IN ONE WORD (VERT LINES ETC)
|
| Called during boot.
WORD8:
    AND.W	D5,D1                                 | COMBINE LEFT AND RIGHT MASKS
    MOVE.W	D1,D5                                | COPY COMBINED MASK
    NOT.W	D5                                    | FORM NOTMASK
WORD8A:
    AND.W	D1,D6                                 | MASK EXTRA PATTERN TO ZEROS
    MOVE.W	(A5),D0                              | GET DST DATA
    AND.W	D5,D0                                 | AND WITH NOTMASK
    OR.W	D6,D0                                  | MERGE WITH SRC DATA
    MOVE.W	D0,(A5)+                             | PUT RESULT TO DST
    ADDA.W	A3,A5                                | BUMP DSTPTR TO NEXT ROW
    ADDQ.W	#0x4,D7                              | BUMP PATTERN ROW INDEX
    ANDI.W	#0x3F,D7                             | WRAP PATTERN ROW INDEX MOD 64
    MOVE.W	-0x40(A6,D7.W),D6                    | LOAD NEXT PATTERN ROW
    DBF.W	D3,WORD8A                             | LOOP ALL ROWS
    BRA.W	GOHOME                                | QUIT
| -------------------------------------------------------
|
| MODE 8 OR 12: PATTERN --> DST (FILLING AREAS, DRAWING LINES)
|
| Called during boot.
WORD8A_CONT:
    LEA.L	WORD8A_CONT_4(PC),A1                  | only do setup once
    LEA.L	FILLBIG(PC),A2                        | point to big fill
CALCLP:
    CMPI.W	#0x20,D2                             | CHECK IF BLOCK >= 32 WORDS
    BGT.B	WORD8A_CONT_3                         | BRANCH IF LARGE BLOCK
    ADDA.W	#0x39,A2                             | OFFSET IN COPY LOOP
    BTST	#0x0,D2                                | will wordcount-1 be even ?
    BNE.B	WORD8A_CONT_2                         | CONTINUE COPY
    ADDA.W	#0x21,A2                             | ADJUST LOOP POINTER
WORD8A_CONT_2:
    SUBA.W	D2,A2                                | CALC UNROLLED ENTRY POINT
WORD8A_CONT_3:
    JMP	(A1)                                    | ENTER UNROLLED LOOP
| ----------------------------------------------------------
|
| WORD8A_CONT_4
|
| Called during boot (1,444 times in 30s trace).
WORD8A_CONT_4:
    MOVE.W	D6,D0                                | FAST8: GET PATTERN DATA
    AND.W	D1,D0                                 | MASK FIRST WORD
    NOT.W	D1                                    | MAKE NOTMASK
    AND.W	(A5),D1                               | GET DST DATA
    OR.W	D1,D0                                  | MERGE WITH PAT DATA
    MOVE.W	D0,(A5)+                             | PUT RESULT TO DST
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BEQ.B	END8                                  | BR IF NO UNMASKED WORDS
    JSR	(A2)                                    | call unwound loop
END8:
    MOVE.W	D5,D1                                | MASK:= RIGHTMASK
    AND.W	D1,D6                                 | MASK PATTERN
    NOT.W	D1                                    | MAKE NOTMASK
    AND.W	(A5),D1                               | GET DST DATA
    OR.W	D1,D6                                  | MERGE WITH PAT DATA
    MOVE.W	D6,(A5)+                             | PUT RESULT TO DST
    BRA.W	NXTSRC_NEXT                           | LOOP BACK FOR NEXT ROW
| ----------------------------------------------------------
|
| Call fillbig with wordcount in D2 (clobbered)
|
FILLBIG:
    BCLR	#0x0,D2                                | is wordcount even ?
    BEQ.B	FILLBIG_LOOP                          | IF NO LONGS LEFT BRANCH
    MOVE.W	D6,(A5)+                             | FILL WORD TO DST
FILLBIG_LOOP:
    SUBI.W	#0x20,D2                             | DECREMENT 32 BYTES COUNTER
    BLE.B	FILLBIG_DONE                          | IF DONE WITH BLOCK BRANCH
    BSR.B	FILL32                                | else fill 32 words
    BRA.B	FILLBIG_LOOP                          | CONTINUE LOOP
| ----------------------------------------------------------
|
| FILLBIG_DONE
|
FILLBIG_DONE:
    NEG.W	D2                                    | COMPUTE JUMP OFFSET
    JMP	FILL32(PC,D2.W)                         | DISPATCH UNROLLED FILL LOOP
| ----------------------------------------------------------
|
| FILL32: 16-long unrolled fill table.  Adjacent FILL31 entry handles
| odd word counts.  PC-relative entry from FILLBIG_DONE selects the
| right starting offset to fill exactly D2 longs (or longs+word).
|
FILL32:
    MOVE.L	D6,(A5)+                             | TABLE TO FILL 0..32 WORDS
    MOVE.L	D6,(A5)+                             | wordCount = 30
    MOVE.L	D6,(A5)+                             | wordCount = 28
    MOVE.L	D6,(A5)+                             | wordCount = 26
    MOVE.L	D6,(A5)+                             | wordCount = 24
    MOVE.L	D6,(A5)+                             | wordCount = 22
    MOVE.L	D6,(A5)+                             | wordCount = 20
    MOVE.L	D6,(A5)+                             | wordCount = 18
    MOVE.L	D6,(A5)+                             | wordCount = 16
    MOVE.L	D6,(A5)+                             | wordCount = 14
    MOVE.L	D6,(A5)+                             | wordCount = 12
    MOVE.L	D6,(A5)+                             | wordCount = 10
    MOVE.L	D6,(A5)+                             | wordCount = 8
    MOVE.L	D6,(A5)+                             | wordCount = 6
    MOVE.L	D6,(A5)+                             | wordCount = 4
    MOVE.L	D6,(A5)+                             | wordCount = 2
    RTS                                         | wordCount = 0
| FILL31: 1..31 word odd-count table
    MOVE.L	D6,(A5)+                             | TABLE TO FILL 1..31 WORDS
    MOVE.L	D6,(A5)+                             | wordCount = 29
    MOVE.L	D6,(A5)+                             | wordCount = 27
    MOVE.L	D6,(A5)+                             | wordCount = 25
    MOVE.L	D6,(A5)+                             | wordCount = 23
    MOVE.L	D6,(A5)+                             | wordCount = 21
    MOVE.L	D6,(A5)+                             | wordCount = 19
    MOVE.L	D6,(A5)+                             | wordCount = 17
    MOVE.L	D6,(A5)+                             | wordCount = 15
    MOVE.L	D6,(A5)+                             | wordCount = 13
    MOVE.L	D6,(A5)+                             | wordCount = 11
    MOVE.L	D6,(A5)+                             | wordCount = 9
    MOVE.L	D6,(A5)+                             | wordCount = 7
    MOVE.L	D6,(A5)+                             | wordCount = 5
    MOVE.L	D6,(A5)+                             | wordCount = 3
    MOVE.W	D6,(A5)+                             | FILL WORD TO DST
    RTS                                         | AND RETURN
| -------------------------------------------------------
|
| MODE 9 OR 13: PATTERN OR DST --> DST
|
FILL31_CONT:
    AND.W	D5,D1                                 | END9: MASK:=MASK AND LASTMASK
MAIN9:
    MOVE.W	D6,D0                                | GET PATTERN DATA
    AND.W	D1,D0                                 | MASK PATTERN
    OR.W	D0,(A5)+                               | OR PATTERN INTO DST
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BGT.B	MAIN9                                 | LOOP TILL LAST WORD
    BEQ.B	FILL31_CONT                           | DO LAST WORD WITH LASTMASK
    BRA.W	NXTSRC_NEXT                           | LOOP BACK FOR NEXT ROW
| -------------------------------------------------------
|
| MODE 10 OR 14: PATTERN XOR DST --> DST (INVERTING AREAS, XOR LINES)
|
| Called during boot.
MAIN9_CONT:
    LEA.L	MAIN9_CONT_2(PC),A1                   | only do setup once
    LEA.L	XORBIG(PC),A2                         | point to big fill
    BRA.W	CALCLP                                | share loop calc
| ----------------------------------------------------------
|
| MAIN9_CONT_2
|
| Called during boot (1,516 times in 30s trace).
MAIN9_CONT_2:
    MOVE.W	D6,D0                                | FAST10: GET PATTERN DATA
    AND.W	D1,D0                                 | MASK FIRST WORD
    EOR.W	D0,(A5)+                              | XOR PATTERN INTO DST
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK FOR END10
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BEQ.B	MAIN9_NO                              | BR IF NO UNMASKED WORDS
    JSR	(A2)                                    | call unwound loop
    MOVEQ.L	#-0x1,D2                            | force finish up below
MAIN9_NO:
    AND.W	D5,D1                                 | END10: MASK:=MASK AND LASTMASK
    AND.W	D1,D6                                 | MASK PATTERN
    EOR.W	D6,(A5)+                              | XOR PATTERN DATA INTO DST
    BRA.W	NXTSRC_NEXT                           | LOOP BACK FOR NEXT ROW
| ----------------------------------------------------------
|
| Call XORbig with wordcount in D2 (clobbered)
|
XORBIG:
    BCLR	#0x0,D2                                | is wordcount even ?
    BEQ.B	XORBIG_LOOP                           | IF NO LONGS LEFT BRANCH
    EOR.W	D6,(A5)+                              | XOR WORD TO DST
XORBIG_LOOP:
    SUBI.W	#0x20,D2                             | DECREMENT 32 BYTES COUNTER
    BLE.B	XORBIG_DONE                           | IF DONE WITH BLOCK BRANCH
    BSR.B	XOR32                                 | else XOR 32 words
    BRA.B	XORBIG_LOOP                           | CONTINUE LOOP
| ----------------------------------------------------------
|
| XORBIG_DONE
|
XORBIG_DONE:
    NEG.W	D2                                    | COMPUTE JUMP OFFSET
    JMP	XOR32(PC,D2.W)                          | DISPATCH UNROLLED XOR LOOP
| ----------------------------------------------------------
|
| XOR32: 16-long unrolled XOR table (with adjacent XOR31 odd-count entry).
|
XOR32:
    EOR.L	D6,(A5)+                              | TABLE TO XOR 0..32 WORDS
    EOR.L	D6,(A5)+                              | wordCount = 30
    EOR.L	D6,(A5)+                              | wordCount = 28
    EOR.L	D6,(A5)+                              | wordCount = 26
    EOR.L	D6,(A5)+                              | wordCount = 24
    EOR.L	D6,(A5)+                              | wordCount = 22
    EOR.L	D6,(A5)+                              | wordCount = 20
    EOR.L	D6,(A5)+                              | wordCount = 18
    EOR.L	D6,(A5)+                              | wordCount = 16
    EOR.L	D6,(A5)+                              | wordCount = 14
    EOR.L	D6,(A5)+                              | wordCount = 12
    EOR.L	D6,(A5)+                              | wordCount = 10
    EOR.L	D6,(A5)+                              | wordCount = 8
    EOR.L	D6,(A5)+                              | wordCount = 6
    EOR.L	D6,(A5)+                              | wordCount = 4
    EOR.L	D6,(A5)+                              | wordCount = 2
    RTS                                         | wordCount = 0
| XOR31: 1..31 word odd-count table
    EOR.L	D6,(A5)+                              | TABLE TO XOR 1..31 WORDS
    EOR.L	D6,(A5)+                              | wordCount = 29
    EOR.L	D6,(A5)+                              | wordCount = 27
    EOR.L	D6,(A5)+                              | wordCount = 25
    EOR.L	D6,(A5)+                              | wordCount = 23
    EOR.L	D6,(A5)+                              | wordCount = 21
    EOR.L	D6,(A5)+                              | wordCount = 19
    EOR.L	D6,(A5)+                              | wordCount = 17
    EOR.L	D6,(A5)+                              | wordCount = 15
    EOR.L	D6,(A5)+                              | wordCount = 13
    EOR.L	D6,(A5)+                              | wordCount = 11
    EOR.L	D6,(A5)+                              | wordCount = 9
    EOR.L	D6,(A5)+                              | wordCount = 7
    EOR.L	D6,(A5)+                              | wordCount = 5
    EOR.L	D6,(A5)+                              | wordCount = 3
    EOR.W	D6,(A5)+                              | XOR WORD TO DST
    RTS                                         | AND RETURN
| -------------------------------------------------------
|
| MODE 11 OR 15: PATTERN BIC DST --> DST
|
| Called during boot.
XOR31_CONT:
    AND.W	D5,D1                                 | END11: MASK:=MASK AND LASTMASK
MAIN11:
    MOVE.W	D6,D0                                | GET PATTERN DATA
    AND.W	D1,D0                                 | MASK PATTERN
    NOT.W	D0                                    | INVERT PATTERN
    AND.W	D0,(A5)+                              | BIC PATTERN INTO DST
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK
    SUBQ.W	#0x1,D2                              | DECREMENT LONG WORD COUNTER
    BGT.B	MAIN11                                | LOOP TILL LAST WORD
    BEQ.B	XOR31_CONT                            | DO LAST WITH LASTMASK
    BRA.W	NXTSRC_NEXT                           | LOOP BACK FOR NEXT ROW
| QuickDraw copyright notice embedded by Bill Atkinson in BitBlt.
| Unreachable code (after BRA above); serves as a hidden ROM signature.
| Bytes spell out: "(c) Apple Computer Inc., 1983-1985"
    .long	0x28632920
    .long	0x4170706C
    .long	0x6520436F
    .long	0x6D707574
    .long	0x65722049
    .long	0x6E632E2C
    .long	0x20313938
    .long	0x332D3139
    .short	0x3835
