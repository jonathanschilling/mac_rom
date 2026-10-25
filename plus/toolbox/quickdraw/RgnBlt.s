| ------------------------------------------------------------------
|
| --> RGNBLT.TEXT
|
| Low level block transfer clipped to an arbitrary region.
|

| .PROC RgnBlt,9
| .REF BitBlt,RSect,ShieldCursor,ShowCursor
| .REF SeekRgn,PatExpand,ColorMap,InitRgn,TrimRect
| --------------------------------------------------------------
|
| PROCEDURE RgnBlt(srcBits,dstBits: BitMap;
| srcRect,dstRect: Rect;
| mode: INTEGER; pat: Pattern;
| rgnA,rgnB,rgnC: RgnHandle);
|
| TRANSFERS A RECTANGULAR BLOCK OF BITS CLIPPED TO THE DESTINATION
| BITMAP'S BOUNDS AND TO THE INTERSECTION OF THREE REGIONS.
| MODE SPECIFIES THE TRANSFER MODE AND WHETHER THE SOURCE SHOULD COME
| FROM THE SOURCE BITMAP OR FROM A REPEATING PATTERN.
|
| COPYRIGHT APPLE COMPUTER INC.
| DESIGNED AND WRITTEN BY BILL ATKINSON
|
| THIS CODE IS POSITION INDEPENDENT, RE-ENTRANT, AND READ-ONLY.
| CLOBBERS ONLY A0.
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
RgnBlt:
        LINK    A6,#-0xCC                       | ALLOCATE LOCAL VARIABLES
        MOVEM.L D0-D7/A2-A5,-(SP)               | SAVE REGS

        MOVE.L  A7,-0x94(A6)                    | REMEMBER STACK FOR LATER
        MOVE.L  A5,-0xB8(A6)                    | REMEMBER GLOBAL PTR
        MOVE    0x18(A6),-(SP)                  | YES, PUSH INPUT MODE
        MOVE.L  0x14(A6),-(SP)                  | PUSH ADDR OF INPUT PATTERN

| ----------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
.set PARAMSIZE, 34                              | SIZE OF PARAMETERS
.set SRCBITS, PARAMSIZE+8-4                     | LONG, ADDR OF BITMAP
.set DSTBITS, SRCBITS-4                         | LONG, ADDR OF BITMAP
.set SRCRECT, DSTBITS-4                         | LONG, ADDR OF RECT
.set DSTRECT, SRCRECT-4                         | LONG, ADDR OF RECT
.set MODE, DSTRECT-2                            | WORD
.set PAT, MODE-4                                | LONG, ADDR OF PATTERN
.set RGNA, PAT-4                                | LONG, RGNHANDLE
.set RGNB, RGNA-4                               | LONG, RGNHANDLE
.set RGNC, RGNB-4                               | LONG, RGNHANDLE

| -------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set EXPAT, -64                                 | 16 LONGS
.set MINRECT, EXPAT-8                           | RECT
.set STATEA, MINRECT-RGNREC                     | RGN STATE RECORD
.set STATEB, STATEA-RGNREC                      | RGN STATE RECORD
.set STATEC, STATEB-RGNREC                      | RGN STATE RECORD
.set SAVESTK, STATEC-4                          | LONG
.set RECTFLAG, SAVESTK-2                        | WORD
.set MASKBUF, RECTFLAG-4                        | LONG
.set BUFLEFT, MASKBUF-2                         | WORD
.set BUFSIZE, BUFLEFT-2                         | WORD
.set SRCADDR, BUFSIZE-4                         | LONG
.set DSTADDR, SRCADDR-4                         | LONG
.set SRCROW, DSTADDR-4                          | LONG
.set DSTROW, SRCROW-4                           | LONG
.set VERT, DSTROW-2                             | WORD
.set MODECASE, VERT-4                           | LONG
.set SAVEA5, MODECASE-4                         | LONG
.set FIRSTV, SAVEA5-2                           | WORD
.set LASTV, FIRSTV-2                            | WORD
.set VBUMP, LASTV-2                             | WORD, MUST BE ABOVE HBUMP
.set HBUMP, VBUMP-2                             | WORD
.set SRCRECT2, HBUMP-8                          | RECT
.set MASKADDR, SRCRECT2-4                       | LONG
.set VARSIZE, MASKADDR                          | SIZE OF LOCAL VARIABLES

| ----------------------------------------------------------------
|
| ADJUST MODE AND PATTERN IF COLOR FILTERING.
|
        JSR     ColorMap(PC)                    | ALTER BY THECOLOR, THEFILTER
        MOVE.L  (SP)+,0x14(A6)                  | GET (ALTERED) PATTERN
        MOVE    (SP)+,0x18(A6)                  | GET (ALTERED) MODE

| ------------------------------------------------------
|
| GET THREE REGION HANDLES AND DE-REFERENCE THEM.
|
        MOVE.L  0x10(A6),A1                     | GET RGNHANDLE

| ------------------------------------------------------
|
        MOVE.L  (A1),A1                         | DE-REFERENCE IT
        MOVE.L  0xC(A6),A2                      | GET RGNHANDLE
        MOVE.L  (A2),A2                         | DE-REFERENCE IT
        MOVE.L  0x8(A6),A3                      | GET RGNHANDLE
        MOVE.L  (A3),A3                         | DE-REFERENCE IT

| -------------------------------------------------------------------
|
| CALC MINRECT, THE INTERSECTION OF DSTRECT, DSTBITS.BOUNDS,
| AND 3 REGION BOUNDING BOXES. QUIT IF THE INTERSECTION IS EMPTY.
|
        MOVE.L  0x1A(A6),-(SP)                  | PUSH DSTRECT
        MOVE.L  0x22(A6),A4                     | A4 POINTS TO DSTBITS

| -------------------------------------------------------------------
|
        PEA.L   BOUNDS(A4)                      | PUSH DSTBITS.BOUNDS
        PEA.L   RGNBBOX(A1)                     | PUSH RGNA BBOX
        PEA.L   RGNBBOX(A2)                     | PUSH RGNB BBOX
        PEA.L   RGNBBOX(A3)                     | PUSH RGNC BBOX
        MOVE    #5,-(SP)                        | PUSH NRECTS=5
        PEA.L   -0x48(A6)                       | PUSH WHERE TO PUT RESULT
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ     RGNBLT_GOHOME                   | QUIT IF EMPTY

| ----------------------------------------------------
|
| HIDE THE CURSOR IF IT INTERSECTS MINRECT
|
        PEA.L   -0x48(A6)                       | PUSH SHIELD RECT
        MOVE.L  0x6(A4),-(SP)                   | PUSH DELTA TO CONVERT TO GLOBAL

| ----------------------------------------------------
|
        JSR     ShieldCursor(PC)                | REMOVE CURSOR IF INTERSECT
        CMPI    #0xA,(A1)                       | IS RGNA RECTANGULAR ?

| ----------------------------------------------------
|
| ARE ALL THREE REGIONS RECTANGULAR ?
|
        BNE.B   OKRECT_NO                       | NO, CONTINUE
        CMPI    #0xA,(A3)                       | IS RGNC RECTANGULAR ?
        BNE.B   OKRECT_NO                       | NO, CONTINUE
        CMPI    #0xA,(A2)                       | IS RGNB RECTANGULAR ?
        BEQ.B   OKRECT                          | NO, CONTINUE

|
| If only rgnB (visRgn) is non-rectangular, then check if
| its intersection with minrect would be rectangular.
| IF TrimRect(rgnB,minRect) then take the fast way.
|
        MOVE.L  0xC(A6),-(SP)                   | push rgnHandle
        PEA.L   -0x48(A6)                       | push addr of minRect

        JSR     TrimRect(PC)                    | call trimRect
        BLT     RGNBLT_DONE                     | quit if intersection empty
        BGT.B   OKRECT_NO                       | continue if non-rectangular

| --------------------------------------------------------------
|
| SINCE ALL THREE REGIONS ARE RECTANGULAR, WE WILL USE BITBLT.
| FIRST CLIP SRCRECT TO MATCH MINRECT. (COPY SRCRECT SINCE IT'S NOT VAR)
|
| Called during boot.
OKRECT:
        MOVE.L  0x1E(A6),A2                     | POINT TO SRC RECT
        LEA.L   -0xC8(A6),A0                    | POINT TO LOCAL COPY OF SRCRECT
        MOVE.L  0x1A(A6),A3                     | POINT TO DSTRECT
        MOVE    -0x48(A6),D0                    | GET MINRECT TOP
        SUB     (A3),D0                         | CONVERT FROM DST COORDS
        ADD     (A2),D0                         | TO SRC COORDS
        MOVE    D0,(A0)                         | PUT CLIPPED SRC TOP INTO COPY
        MOVE    -0x46(A6),D0                    | GET MINRECT LEFT

| --------------------------------------------------------------
|
| SINCE ALL THREE REGIONS ARE RECTANGULAR, WE WILL USE BITBLT.
| FIRST CLIP SRCRECT TO MATCH MINRECT. (COPY SRCRECT SINCE IT'S NOT VAR)
|
        SUB     LEFT(A3),D0                     | CONVERT FROM DST COORDS
        ADD     LEFT(A2),D0                     | TO SRC COORDS
        MOVE    D0,LEFT(A0)                     | PUT CLIPPED SRC LEFT INTO COPY

| ----------------------------------------------------
|
| PUSH PARAMETERS AND CALL BITBLT
|
        MOVE.L  0x26(A6),-(SP)                  | PUSH SRCBITS

| ----------------------------------------------------
|
        MOVE.L  A4,-(SP)                        | PUSH DSTBITS
        MOVE.L  A0,-(SP)                        | PUSH SRCRECT COPY
        PEA.L   -0x48(A6)                       | PUSH DST = MINRECT
        MOVE    0x18(A6),-(SP)                  | PUSH MODE
        MOVE.L  0x14(A6),-(SP)                  | PUSH PATTERN
        JSR     BitBlt(PC)                      | CALL BITBLT
        BRA     RGNBLT_DONE                     | RESTORE CURSOR AND QUIT

| ----------------------------------------------------------
|
| OKRECT_NO
|
| Called during boot.
OKRECT_NO:
        MOVE    -0x46(A6),D1                    | GET MINRECT LEFT
        SUB     0x8(A4),D1                      | CONVERT TO GLOBAL COORDS
        ANDI    #-0x10,D1                       | TRUNC TO MULT OF 16
        ADD     0x8(A4),D1                      | CONVERT BACK TO LOCAL

| -----------------------------------
|
| CALC BUFLEFT AND BUFSIZE
|
        MOVE    D1,-0x9C(A6)                    | SAVE AS BUFLEFT
        MOVE    -0x42(A6),D0                    | GET MINRECT RIGHT

| -----------------------------------
|
        SUB     D1,D0                           | CALC WIDTH IN DOTS
        LSR     #5,D0                           | DIV BY 32 FOR LONGS
        MOVE    D0,-0x9E(A6)                    | BUFSIZE = # LONGS -1

| -----------------------------------------------------------------------
|
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK.
|
| Called during boot.
RGNBLT_CLRMASK:
        CLR.L   -(SP)                           | CLRMASK: ALLOCATE AND CLEAR
        DBF     D0,RGNBLT_CLRMASK               | LOOP TILL DONE
        MOVE.L  A7,-0x9A(A6)                    | |REMEMBER WHERE MASKBUF IS

| -------------------------------------------------------------------
|
| INIT STATE RECORDS VERT0 AND VERT1 IN CASE RECTANGULAR
|
        MOVE    #32767,D0                       | SETUP MAX VERT POS
        MOVE    D0,-0x50(A6)                    | INIT RGNA NEXT VERTICAL
        MOVE    D0,-0x68(A6)                    | INIT RGNB NEXT VERTICAL
        MOVE    D0,-0x80(A6)                    | INIT RGNC NEXT VERTICAL

| -------------------------------------------------------------------
|
        NEG     D0                              | SETUP MIN VERT POS
        MOVE    D0,-0x52(A6)                    | INIT RGNA CURRENT VERTICAL
        MOVE    D0,-0x6A(A6)                    | INIT RGNB CURRENT VERTICAL
        MOVE    D0,-0x82(A6)                    | INIT RGNC CURRENT VERTICAL

| ----------------------------------------------------------------------
|
| ALLOCATE BUFFERS AND INIT STATE RECORDS FOR EACH NON-RECT REGION
|
        CLR     D5                              | INIT ALL RGNS RECT
        MOVE.L  0x10(A6),A0                     | GET RGNHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMPI    #0xA,(A0)                       | IS RGNA RECTANGULAR ?
        BEQ.B   RGNBLT_CLRMASK_SKIP             | YES, SKIP IT
        ADDQ.W  #0x2,D5                         | NO, SET UP FLAG
        LEA.L   -0x60(A6),A1                    | POINT TO STATE RECORD A
        BSR.B   RGNBLT_CLRMASK_CONT             | INIT STATE, ALLOC BUFFER

| ARECT
| Called during boot.
RGNBLT_CLRMASK_SKIP:
        MOVE.L  0xC(A6),A0                      | GET RGNHANDLE

| ARECT
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMPI    #0xA,(A0)                       | IS RGNB RECTANGULAR ?
        BEQ.B   RGNBLT_CLRMASK_SKIP_2           | YES, SKIP IT
        ADDQ.W  #0x4,D5                         | NO, BUMP FLAG
        LEA.L   -0x78(A6),A1                    | POINT TO STATE RECORD B
        BSR.B   RGNBLT_CLRMASK_CONT             | INIT STATE, ALLOC BUFFER

| BRECT
| Called during boot.
RGNBLT_CLRMASK_SKIP_2:
        MOVE.L  0x8(A6),A0                      | GET RGNHANDLE

| BRECT
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMPI    #0xA,(A0)                       | IS RGNC RECTANGULAR ?
        BEQ.B   RGNBLT_CLRMASK_EXIT             | YES, SKIP IT
        ADDQ.W  #0x8,D5                         | NO, BUMP FLAG
        LEA.L   -0x90(A6),A1                    | POINT TO STATE RECORD C
        PEA.L   RGNBLT_CLRMASK_EXIT(PC)         | PUSH FAKE RETURN ADDR
| RGNBLT_CLRMASK_CONT -- iNIT STATE, ALLOC BUFFER.
RGNBLT_CLRMASK_CONT:
        MOVE    -0x46(A6),D0                    | GET MINH
        MOVE    -0x42(A6),D1                    | GET MAXH
        MOVE    -0x9C(A6),D2                    | GET BUFLEFT
        JMP     InitRgn(PC)                     | INIT STATE, ALLOC BUFFER

| CRECT

| ---------------------------------------------------------------------
|
| IF ONLY ONE REGION IS NON-RECTANGULAR, PLAY IT BACK DIRECTLY
| INTO THE MASK BUFFER.
|
| Called during boot.
RGNBLT_CLRMASK_EXIT:
        MOVE.L  -0x9A(A6),D7                    | GET MASK BUFFER ADDRESS
        MOVE    D5,-0x96(A6)                    | SAVE NON-RECT FLAG
        CMPI    #0x2,D5                         | IS RGNA THE ONLY NON-RECT ?

| CRECT

| ---------------------------------------------------------------------
|
| IF ONLY ONE REGION IS NON-RECTANGULAR, PLAY IT BACK DIRECTLY
| INTO THE MASK BUFFER.
|
        BNE.B   RGNBLT_CLRMASK_NO               | NO, CONTINUE
        MOVE.L  D7,-0x58(A6)                    | YES, PLAY DIRECTLY INTO MASK
        BRA.B   RGNBLT_CLRMASK_SKIP_3           | SKIP TO COK

| ----------------------------------------------------------
|
| RGNBLT_CLRMASK_NO
|
| Called during boot.
RGNBLT_CLRMASK_NO:
        CMPI    #0x4,D5                         | IS RGNB THE ONLY NON-RECT ?
        BNE.B   RGNBLT_CLRMASK_NO_2             | NO, CONTINUE
        MOVE.L  D7,-0x70(A6)                    | YES, PLAY DIRECTLY INTO MASK
        BRA.B   RGNBLT_CLRMASK_SKIP_3           | SKIP TO COK

| ----------------------------------------------------------
|
| RGNBLT_CLRMASK_NO_2
|
| Called during boot.
RGNBLT_CLRMASK_NO_2:
        CMPI    #0x8,D5                         | IS RGNC THE ONLY NON-RECT ?
        BNE.B   RGNBLT_CLRMASK_SKIP_3           | NO, CONTINUE
        MOVE.L  D7,-0x88(A6)                    | YES, PLAY DIRECTLY INTO MASK
RGNBLT_CLRMASK_SKIP_3:
        MOVE    -0x48(A6),-0xBA(A6)             | FIRSTV:=MINRECT TOP
        MOVE    -0x44(A6),-0xBC(A6)             | LASTV:=MINRECT BOTTOM

| COK

| ----------------------------------------------------------
|
| ASSUME WE WILL BE DRAWING DOWNWARD AND TO RIGHT.
|
        MOVE.L  #0x40001,-0xC0(A6)              | HBUMP:=4 BYTES, VBUMP:=1 SCAN


| ----------------------------------------------------------
|
        MOVE    ROWBYTES(A4),D0                 | GET DST ROWBYTES
        EXT.L   D0                              | EXTEND TO LONG
        MOVE.L  D0,-0xAE(A6)                    | DSTROW:=+ROWBYTES
        MOVE.L  D7,-0xCC(A6)                    | MASKADDR:=MASKBUF

| ---------------------------------------
|
| SET UP INVERT FLAG IN D7 TO REFLECT MODE BIT 2
|
        CLR.L   D7                              | SAY NOT INVERTED
        MOVE    0x18(A6),D2                     | GET TRANSFER MODE
        BMI     RGNBLT_DONE                     | QUIT IF MODE NEGATIVE
        BCLR    #2,D2                           | TEST AND CLR INVERT BIT
        BEQ.B   RGNBLT_CLRMASK_SKIP_4           | SKIP IF NOT INVERTED
        NOT.L   D7                              | INVERTED; D7 GETS ALL 1'S
RGNBLT_CLRMASK_SKIP_4:
        ANDI    #0xF,D2                         | TREAT MODE MOD 16

| --------------------------------------------------
|
| CALCULATE CASE JUMP FOR DIFFERENT TRANSFER MODES
|
        MOVEQ   #3,D0                           | PREPARE TO GET BOTTOM 2 BITS
        AND     D2,D0                           | GET BOTTOM 2 BITS OF MODE
        ADD     D0,D2                           | MODIFY MODE FOR INDEX
        LEA.L   ABCDONE_MODE_TBL(PC),A0         | POINT TO MODE TABLE
        ADDA    0x0(A0,D2.W),A0                 | GET CASE JUMP ADDRESS
        MOVE.L  A0,-0xB4(A6)                    | SAVE FOR LATER
        BTST    #3,D2                           | WILL PATTERN BE USED ?
        BEQ.B   USESRC                          | NO, USE SOURCE INSTEAD
        MOVE    0x8(A4),D2                      | GET GLOBAL-LOCAL OFFSET

| ------------------------------------------------------------------
|
| PATTERN WILL BE USED. EXPAND 8 BYTE PATTERN TO 16 LONGS
|
        MOVE.L  0x14(A6),A0                     | POINT TO BYTE WIDE PATTERN
        LEA.L   -0x40(A6),A1                    | POINT TO EXPANDED PATTERN

| ------------------------------------------------------------------
|
        JSR     PatExpand(PC)                   | EXPAND 8 BYTES TO 16 LONGS

| -------------------------------------------------
|
| SET UP (VERT * 4) MOD 64 AS PATTERN SELECTOR
|
        MOVEQ.L #0xF,D7                         | TREAT COORD MOD 16
        AND     -0x48(A6),D7                    | GET TOP VERT COORD

| -------------------------------------------------
|
        LSL     #2,D7                           | QUAD FOR 4 BYTE PATTERNS
        MOVE.L  -0x40(A6,D7.W),D6               | GET FIRST PATTERN DATA
        BRA     RGNBLT_GETDST                   | SKIP OVER SRC STUFF

| --------------------------------------------------------------
|
| SRC WILL BE USED. CHECK FOR OVERLAP AND CHOOSE DIRECTION SO
| THAT SRC WONT GET CLOBBERED BEFORE IT IS USED.
|
| Called during boot.
USESRC:
        MOVE.L  0x1A(A6),A1                     | POINT TO DSTRECT
        MOVE.L  0x1E(A6),A2                     | POINT TO SRCRECT
        MOVE.L  0x26(A6),A3                     | POINT TO SRCBITS

| --------------------------------------------------------------
|
| SRC WILL BE USED. CHECK FOR OVERLAP AND CHOOSE DIRECTION SO
| THAT SRC WONT GET CLOBBERED BEFORE IT IS USED.
|
        MOVE    ROWBYTES(A3),D0                 | GET SRC ROWBYTES
        EXT.L   D0                              | EXTEND TO LONG
        MOVE.L  D0,-0xAA(A6)                    | SRCROW:=+ROWBYTES
        MOVE.L  (A3),D0                         | GET SRC BASEADDR
        CMP.L   (A4),D0                         | ARE SRC AND DST SAME BITMAP ?
        BNE.B   RGNBLT_SRCOK                    | NO, DON'T WORRY ABOUT OVERLAP
        MOVE    (A1),D0                         | GET DST TOP
        SUB     0x6(A4),D0                      | CONVERT TO GLOBAL
        MOVE    (A2),D1                         | GET SRC TOP
        SUB     0x6(A3),D1                      | CONVERT TO GLOBAL
        SUB     D1,D0                           | CALC DV:=DSTTOP-SRCTOP
        BLT.B   RGNBLT_SRCOK                    | EVERYTHING FINE IF SCROLLING UP
        BGT.B   RGNBLT_UPSIDE                   | UPSIDE DOWN IF SCROLLING DOWN

| ------------------------------------------------------------
|
| DV=0. IF DH > 0 THEN WE MUST TRANSFER BACKWARDS FROM RIGHT.
|
        MOVE    LEFT(A1),D0                     | GET DST LEFT
        SUB     0x8(A4),D0                      | CONVERT TO GLOBAL
        MOVE    LEFT(A2),D1                     | GET SRC LEFT
        SUB     0x8(A3),D1                      | CONVERT TO GLOBAL
        SUB     D1,D0                           | DH := DSTLEFT-SRCLEFT
        BLE.B   RGNBLT_SRCOK                    | IF DH <= 0, WE'RE FINE
        NEG     -0xC0(A6)                       | ELSE BUMP TOWARD LEFT
        BRA.B   RGNBLT_SRCOK                    | CONTINUE

| ------------------------------------------------------------
|
| DV IS POSITIVE, WE MUST TRANSFER UPSIDE-DOWN FROM BOTTOM.
|
RGNBLT_UPSIDE:
        NEG     -0xBE(A6)                       | VBUMP:=-1, BUMP UPWARD
        NEG.L   -0xAA(A6)                       | SRCROW:=-SRC ROWBYTES
        NEG.L   -0xAE(A6)                       | DSTROW:=-DST ROWBYTES
        MOVE    -0x44(A6),-0xBA(A6)             | FIRSTV:=BOTTOM-1
        SUBQ.W  #0x1,-0xBA(A6)                  | FIRSTV:=BOTTOM-1
        MOVE    -0x48(A6),-0xBC(A6)             | LASTV:=TOP-1
        SUBQ.W  #0x1,-0xBC(A6)                  | LASTV:=TOP-1

| ----------------------------------------------
|
| CALC SHIFTCNT
|

| ------------------------------------------------------------
|
| DV IS POSITIVE, WE MUST TRANSFER UPSIDE-DOWN FROM BOTTOM.
| Called during boot.
RGNBLT_SRCOK:
        MOVE    LEFT(A1),D6                     | SRCOK: GET DST LEFT LOCAL COORDS
        SUB     0x8(A4),D6                      | CONVERT TO GLOBAL
        MOVE    LEFT(A2),D1                     | GET SRC LEFT LOCAL COORDS
        SUB     0x8(A3),D1                      | CONVERT TO GLOBAL
        SUB     D1,D6                           | CALC DELTA HORIZ GLOBAL
        ANDI    #0xF,D6                         | MOD 16 FOR SHIFTCNT

| ------------------------------------
|
| CALC STARTING SRCADDR
|
        MOVE    -0xBA(A6),D0                    | GET FIRST DST VERTICAL
        SUB     (A1),D0                         | SUBTRACT DSTRECT TOP
        ADD     (A2),D0                         | ADD SRCRECT TOP
        SUB     0x6(A3),D0                      | CONVERT SRCV TO GLOBAL

| ------------------------------------
|
        MULU    ROWBYTES(A3),D0                 | MULT BY SRC ROWBYTES
        MOVE.L  (A3),A0                         | GET START OF BITMAP
        ADD.L   D0,A0                           | ADD OFFSET TO BASEADDR
        MOVE    -0x46(A6),D0                    | GET DST LEFT
        SUB     LEFT(A1),D0                     | CONVERT FROM DST COORDS
        ADD     LEFT(A2),D0                     | TO SRC COORDS
        SUB     0x8(A3),D0                      | CONVERT TO GLOBAL SRC
        ADD     D6,D0                           | ADD SHIFTCNT
        LSR     #4,D0                           | CONVERT DOTS TO WORDS
        ADD     D0,D0                           | DOUBLE FOR BYTES
        ADD     D0,A0                           | ADD HORIZ OFFSET
        MOVE.L  A0,-0xA2(A6)                    | SAVE AS SRCADDR

| ------------------------------------
|
| CALC STARTING DSTADDR
|
| Called during boot.
RGNBLT_GETDST:
        MOVE    -0xBA(A6),D0                    | GET FIRST DST VERT
        SUB     0x6(A4),D0                      | CONVERT TO GLOBAL

| ------------------------------------
|
| CALC STARTING DSTADDR
|
        MULU    ROWBYTES(A4),D0                 | MULT BY ROWBYTES
        MOVE.L  (A4),A0                         | GET START OF BITMAP
        ADD.L   D0,A0                           | ADD VERTICAL OFFSET
        MOVE    -0x46(A6),D0                    | GET DST LEFT
        SUB     0x8(A4),D0                      | CONVERT TO GLOBAL
        LSR     #4,D0                           | CONVERT DOTS TO WORDS
        ADD     D0,D0                           | DOUBLE FOR BYTES
        ADD     D0,A0                           | ADD HORIZ OFFSET
        MOVE.L  A0,-0xA6(A6)                    | SAVE AS DSTADDR

| ------------------------------------------------------------------------
|
| ADJUST SRCADDR,DSTADDR,MASKADDR IF WE ARE BUMPING BACKWARDS FROM RIGHT
|
        TST     -0xC0(A6)                       | BUMPING BACKWARD ?

| ------------------------------------------------------------------------
|
        BPL.B   RGNBLT_GETDST_NO                | NO, CONTINUE
        MOVE    -0x9E(A6),D0                    | GET BUFFER SIZE
        ASL     #2,D0                           | QUAD FOR # BYTES
        EXT.L   D0                              | CLEAR HI WORD
        ADD.L   D0,-0xA6(A6)                    | ADJUST DSTADDR
        ADD.L   D0,-0xA2(A6)                    | ADJUST SRCADDR
        ADD.L   D0,-0xCC(A6)                    | ADJUST MASKADDR

| HBUMPOK
| Called during boot.
RGNBLT_GETDST_NO:
        MOVE    -0xBA(A6),-0xB0(A6)             | INIT CURRENT VERTICAL

| -------------------------------------------------------
|
| MAKE MASK BUFFER CURRENT FOR THIS VERTICAL.
| THEN SET UP AND DRAW CURRENT SCANLINE.
|
| HBUMPOK
| Called during boot (1,767 times in 30s trace).
RGNBLT_NXTMASK:
        JSR     RGNBLT_GOHOME_CONT(PC)          | MAKE MASK BUFFER CURRENT
        MOVE.L  -0xA2(A6),A3                    | INIT SRCPTR
        MOVE.L  -0xA6(A6),A5                    | INIT DSTPTR FOR ROW
        MOVE.L  -0xCC(A6),A4                    | INIT MASKPTR FOR ROW
        MOVE    -0x9E(A6),D2                    | INIT COUNT OF LONGS
        MOVE.L  -0xB4(A6),A2                    | GET MODE CASE JUMP
        JMP     (A2)                            | TAKE MODE JUMP

| ----------------------------------------------------------
|
| RGNBLT_NXTMASK_NEXT
|
| Called during boot.
RGNBLT_NXTMASK_NEXT:
        MOVE.L  -0xAA(A6),D0                    | GET SRC ROWBYTES
        ADD.L   D0,-0xA2(A6)                    | BUMP SRC TO NEXT ROW
        BRA.B   BUMPV                           | CONTINUE WITH NEXT ROW

| ----------------------------------------------------------
|
| RGNBLT_NXTMASK_NEXT_2
|
| Called during boot (1,687 times in 30s trace).
RGNBLT_NXTMASK_NEXT_2:
        ADDQ.W  #0x4,D7                         | BUMP PATTERN SELECTOR
        ANDI    #0x3F,D7                        | MOD 64 FOR 16 LONG REPEAT
        MOVE.L  -0x40(A6,D7.W),D6               | GET PATTERN FOR NEXT ROW

| -----------------------------------------------------
|
| BUMP DESTINATION VERTICALLY AND LOOP FOR ALL ROWS
|
| Called during boot (1,767 times in 30s trace).
BUMPV:
        MOVE.L  -0xAE(A6),D0                    | GET DST ROWBYTES
        ADD.L   D0,-0xA6(A6)                    | BUMP DST TO NEXT ROW
        MOVE    -0xB0(A6),D0                    | GET CURRENT VERT
        ADD     -0xBE(A6),D0                    | BUMP UP OR DOWN A SCAN LINE
        MOVE    D0,-0xB0(A6)                    | UPDATE CURRENT VERT
        CMP     -0xBC(A6),D0                    | ARE WE AT THE LAST SCAN LINE ?

| -----------------------------------------------------
|
| BUMP DESTINATION VERTICALLY AND LOOP FOR ALL ROWS
|
        BNE.B   RGNBLT_NXTMASK                  | NO, LOOP FOR ALL SCAN LINES

| -----------------------------------------------------------------
|
| ENTIRE RGNBLT COMPLETE. RESTORE REGS AND STACK AND GO HOME.
|
| Called during boot.
RGNBLT_DONE:
        MOVE.L  -0xB8(A6),A5                    | GET GLOBAL POINTER

| -----------------------------------------------------------------
|
| ENTIRE RGNBLT COMPLETE. RESTORE REGS AND STACK AND GO HOME.
|
        JSR     ShowCursor(PC)                  | RESTORE CURSOR
RGNBLT_GOHOME:
        MOVE.L  -0x94(A6),SP                    | STRIP VARIABLE SIZED BUFFER
        MOVEM.L (SP)+,D0-D7/A2-A5               | RESTORE REGISTERS
        UNLK    A6                              | FREE LOCAL VARIABLES
        MOVE.L  (SP)+,A0                        | GET RETURN ADDRESS
        ADDA    #0x22,SP                        | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| -----------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE MASK BUFFER TO CURRENT VERTICAL COORD.
|
| Called during boot (1,767 times in 30s trace).
RGNBLT_GOHOME_CONT:
        MOVE    -0xB0(A6),D0                    | GET CURRENT VERT COORD
        MOVE    -0x96(A6),D1                    | GET RECTFLAG = 0,2,4
        MOVE    RGNBLT_GOHOME_CONT_2(PC,D1.W),D1 | GET OFFSET FROM TABLE
        JMP     RGNBLT_GOHOME_CONT_2(PC,D1.W)   | TAKE CASE JUMP

| ----------------------------------------------------------
|
| RGNBLT_GOHOME_CONT_2 - indexed branch table for RgnBlt region masking modes
|
RGNBLT_GOHOME_CONT_2:
  .byte 0x00,0x9A,0x00,0x10,0x00,0x16           | RECTJMP TABLE PART 1
  .byte 0x00,0x2A,0x00,0x1C,0x00,0x4A           | RECTJMP TABLE PART 2
  .byte 0x00,0x6A,0x00,0x9C                     | RECTJMP TABLE PART 3

| --------------------------------------------------------------------
|
| ONLY REGION A IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
| Called during boot (1,172 times in 30s trace).
RGNBLT_GOHOME_CONT_3:
        LEA.L   -0x60(A6),A1                    | POINT TO STATE RECORD A

| -----------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE MASK BUFFER TO CURRENT VERTICAL COORD.
|

| --------------------------------------------------------------------
|
        BRA.B   JMPSEEK                         | JUMP TO SEEKRGN

| --------------------------------------------------------------------
|
| ONLY REGION B IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
| Called during boot.
RGNBLT_GOHOME_CONT_4:
        LEA.L   -0x78(A6),A1                    | POINT TO STATE RECORD B

| --------------------------------------------------------------------
|
        BRA.B   JMPSEEK                         | JUMP TO SEEKRGN

| --------------------------------------------------------------------
|
| ONLY REGION C IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
RGNBLT_GOHOME_CONT_5:
        LEA.L   -0x90(A6),A1                    | POINT TO STATE RECORD C
JMPSEEK:
        MOVE.L  -0x9A(A6),SCANBUF(A1)           | PLAY DIRECTLY INTO MASKBUF

| --------------------------------------------------------------------
|
| ONLY REGION C IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
        JMP     SeekRgn(PC)                     | CALL SEEKRGN

| -------------------------------------------------------------------
|
| REGIONS A AND B ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
JMPSEEK_CONT:
        LEA.L   -0x60(A6),A1                    | POINT TO STATE RECORD A

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNA
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x78(A6),A1                    | POINT TO STATE RECORD B
        JSR     SeekRgn(PC)                     | UPDATE RGNB
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   BCLOOP_DONE                     | NO, WE'RE DONE
        MOVE.L  -0x58(A6),A0                    | GET RGNA MASK
        MOVE.L  -0x70(A6),A1                    | GET RGNB MASK
        BRA.B   CPY2BUF                         | GO FORM INTERSECTION

| -------------------------------------------------------------------
|
| REGIONS A AND C ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
| Called during boot.
JMPSEEK_CONT_2:
        LEA.L   -0x60(A6),A1                    | POINT TO STATE RECORD A

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNA
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x90(A6),A1                    | POINT TO STATE RECORD C
        JSR     SeekRgn(PC)                     | UPDATE RGNC
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   BCLOOP_DONE                     | NO, WE'RE DONE
        MOVE.L  -0x58(A6),A0                    | GET RGNA MASK
        MOVE.L  -0x88(A6),A1                    | GET RGNC MASK
        BRA.B   CPY2BUF                         | GO FORM INTERSECTION

| -------------------------------------------------------------------
|
| REGIONS B AND C ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
JMPSEEK_CONT_3:
        LEA.L   -0x78(A6),A1                    | POINT TO STATE RECORD B

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNB
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x90(A6),A1                    | POINT TO STATE RECORD C
        JSR     SeekRgn(PC)                     | UPDATE RGNC
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   BCLOOP_DONE                     | NO, WE'RE DONE
        MOVE.L  -0x70(A6),A0                    | GET RGNB MASK
        MOVE.L  -0x88(A6),A1                    | GET RGNC MASK
CPY2BUF:
        MOVE.L  -0x9A(A6),A2                    | GET MASK BUFFER ADDR
        MOVE    -0x9E(A6),D1                    | GET BUFFER SIZE
BCLOOP:
        MOVE.L  (A0)+,D0                        | GET MASK WORD
        AND.L   (A1)+,D0                        | AND WITH OTHER MASK
        MOVE.L  D0,(A2)+                        | SAVE TO MASK BUFFER
        DBF     D1,BCLOOP                       | LOOP FOR ALL WORDS
BCLOOP_DONE:
        RTS                                     | SEEKOK: ALL 3 ARE RECT, DO NOTHING

| -------------------------------------------------------------------
|
| REGIONS A, B AND C ARE ALL NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
BCLOOP_CONT:
        LEA.L   -0x60(A6),A1                    | POINT TO STATE RECORD A

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNA
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x78(A6),A1                    | POINT TO STATE RECORD B
        JSR     SeekRgn(PC)                     | UPDATE RGNB
        OR      D1,(SP)                         | REMEMBER IF RGN CHANGED
        LEA.L   -0x90(A6),A1                    | POINT TO STATE RECORD C
        JSR     SeekRgn(PC)                     | UPDATE RGNC
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   ABCDONE                         | NO, WE'RE DONE
        MOVE.L  -0x58(A6),A0                    | GET RGNA MASK
        MOVE.L  -0x70(A6),A1                    | GET RGNB MASK
        MOVE.L  -0x88(A6),A2                    | GET RGNC MASK
        MOVE.L  -0x9A(A6),A3                    | GET MASK BUFFER ADDR
        MOVE    -0x9E(A6),D1                    | GET BUFFER SIZE
ABCLOOP:
        MOVE.L  (A0)+,D0                        | GET MASK WORD A
        AND.L   (A1)+,D0                        | AND WITH MASK WORD B
        AND.L   (A2)+,D0                        | AND WITH MASK WORD C
        MOVE.L  D0,(A3)+                        | SAVE TO MASK BUFFER
        DBF     D1,ABCLOOP                      | LOOP FOR ALL WORDS
ABCDONE:
        RTS                                     | return from ABCDONE

| ----------------------------------------------------------
|
| ABCDONE_MODE_TBL - indexed branch table for RgnBlt transfer modes
|
ABCDONE_MODE_TBL:
  .byte 0x00,0x10,0x00,0x40,0x00,0x68           | MODETAB TABLE PART 1
  .byte 0x00,0x90,0x00,0xBA,0x00,0xD0           | MODETAB TABLE PART 2
  .byte 0x00,0xDE,0x00,0xEC                     | MODETAB TABLE PART 3
ABCDONE_LOOP:
        MOVE.L  -0x2(A3),D0                     | GET SRC FROM BITMAP

| ---------------------------------------------------------------;
| ;
| INTERFACE TO EACH OF THE RGNBLT SCANLINE LOOPS: ;
| REGISTERS: A0: D0: ;
| A1: D1: ;
| A2: D2: LONGCNT ;
| A3: SRCPTR D3: ;
| A4: MASKPTR D4: ;
| A5: DSTPTR D5: ;
| A6: D6: SHIFTCNT OR PATTERN ;
| A7: D7: INVERT OR PAT-SEL ;
| ---------------------------------------------------------------;

| -------------------------------------------------------
|
| MODE 0 OR 4: SRC --> DST
|
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA    -0xC0(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        MOVE.L  (A4),D1                         | GET MASK
        ADDA    -0xC0(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        AND.L   D1,D0                           | MASK SRC
        NOT.L   D1                              | FORM NOTMASK
        AND.L   (A5),D1                         | GET DST DATA
        OR.L    D1,D0                           | MERGE WITH SRC DATA
        MOVE.L  D0,(A5)                         | PUT RESULT IN DST
        ADDA    -0xC0(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBF     D2,ABCDONE_LOOP                 | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT             | GO FOR NEXT ROW

| ----------------------------------------------------------
|
| ABCDONE_LOOP_2
|
ABCDONE_LOOP_2:
        MOVE.L  -0x2(A3),D0                     | GET SRC FROM BITMAP

| -------------------------------------------------------
|
| MODE 1 OR 5: SRC OR DST --> DST
|
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA    -0xC0(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A4),D0                         | AND WITH MASK
        ADDA    -0xC0(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        OR.L    D0,(A5)                         | OR RESULT INTO DST
        ADDA    -0xC0(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBF     D2,ABCDONE_LOOP_2               | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT             | LOOP FOR NEXT ROW

| ----------------------------------------------------------
|
| ABCDONE_LOOP_3
|
| Called during boot.
ABCDONE_LOOP_3:
        MOVE.L  -0x2(A3),D0                     | GET SRC FROM BITMAP

| -------------------------------------------------------
|
| MODE 2 OR 6: SRC XOR DST --> DST
|
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA    -0xC0(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A4),D0                         | AND WITH MASK
        ADDA    -0xC0(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        EOR.L   D0,(A5)                         | XOR RESULT INTO DST
        ADDA    -0xC0(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBF     D2,ABCDONE_LOOP_3               | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT             | LOOP FOR NEXT ROW

| ----------------------------------------------------------
|
| ABCDONE_LOOP_4
|
| Called during boot.
ABCDONE_LOOP_4:
        MOVE.L  -0x2(A3),D0                     | GET SRC FROM BITMAP

| -------------------------------------------------------
|
| MODE 3 OR 7: SRC BIC DST --> DST
|
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA    -0xC0(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A4),D0                         | AND WITH MASK
        ADDA    -0xC0(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        NOT.L   D0                              | INVERT FOR BIC
        AND.L   D0,(A5)                         | BIC RESULT INTO DST
        ADDA    -0xC0(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBF     D2,ABCDONE_LOOP_4               | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT             | LOOP FOR NEXT ROW

| -------------------------------------------------------
|
| MODE 8 OR 12: PATTERN --> DST (FILLING AREAS, DRAWING LINES)
|
| Called during boot (15,986 times in 30s trace).
ABCDONE_LOOP_5:
        MOVE.L  D6,D0                           | MASK8: GET PATTERN DATA
        MOVE.L  (A4)+,D1                        | GET MASK
        AND.L   D1,D0                           | MASK PATTERN DATA
        NOT.L   D1                              | MAKE NOTMASK
        AND.L   (A5),D1                         | GET DST DATA
        OR.L    D1,D0                           | MERGE WITH PAT DATA
        MOVE.L  D0,(A5)+                        | PUT RESULT TO DST
        DBF     D2,ABCDONE_LOOP_5               | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW

| -------------------------------------------------------
|
| MODE 9 OR 13: PATTERN OR DST --> DST
|
ABCDONE_LOOP_6:
        MOVE.L  D6,D0                           | MASK9: GET PATTERN DATA
        AND.L   (A4)+,D0                        | MASK PATTERN DATA
        OR.L    D0,(A5)+                        | OR RESULT INTO DST
        DBF     D2,ABCDONE_LOOP_6               | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW

| -------------------------------------------------------
|
| MODE 10 OR 14: PATTERN XOR DST --> DST (INVERTING AREAS, XOR LINES)
|
| Called during boot.
ABCDONE_LOOP_7:
        MOVE.L  D6,D0                           | MASK10: GET PATTERN DATA
        AND.L   (A4)+,D0                        | MASK PATTERN DATA
        EOR.L   D0,(A5)+                        | XOR RESULT INTO DST
        DBF     D2,ABCDONE_LOOP_7               | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW

| -------------------------------------------------------
|
| MODE 11 OR 15: PATTERN BIC DST --> DST
|
ABCDONE_LOOP_8:
        MOVE.L  D6,D0                           | MASK11: GET PATTERN DATA
        AND.L   (A4)+,D0                        | MASK PATTERN DATA
        NOT.L   D0                              | INVERT FOR BIC
        AND.L   D0,(A5)+                        | BIC RESULT INTO DST
        DBF     D2,ABCDONE_LOOP_8               | LOOP ALL LONGS THIS ROW
        BRA     RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW


