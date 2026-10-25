| ------------------------------------------------------------------
|
| --> STRETCH.TEXT
|

| .PROC StretchBits,8
| .REF RgnBlt,RSect,ShieldCursor,ShowCursor
| .REF InitRgn,SeekRgn,SetupStretch,ColorMap,XorSlab
| --------------------------------------------------------------
|
| PROCEDURE StretchBits(srcBits,dstBits: BitMap;
| srcRect,dstRect: Rect;
| mode: INTEGER
| rgnA,rgnB,rgnC: RgnHandle);
|
| Transfer a rectangle of bits from srcBits to dstBits,
| stretching or compressing according to srcRect and dstRect.
| The transfer is clipped to the intersection of rgnA, rgnB, and rgnC.
|
|
| Restrictions:
|
| transfer mode 0..7 only.
| if numer <> denom, then src and dst bitmaps do not overlap.
| COPYRIGHT APPLE COMPUTER INC.
| DESIGNED AND WRITTEN BY BILL ATKINSON
| Called during boot.
StretchBits:
        LINK    A6,#-0x9A                       | LINK AND ALLOCATE LOCAL VARS

| ----------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
.set PARAMSIZE, 30                              | TOTAL BYTES OF PARAMETERS
.set SRCBITS, PARAMSIZE+8-4                     | LONG, ADDR OF BITMAP
.set DSTBITS, SRCBITS-4                         | LONG, ADDR OF BITMAP
.set SRCRECT, DSTBITS-4                         | LONG, ADDR OF RECT
.set DSTRECT, SRCRECT-4                         | LONG, ADDR OF RECT
.set MODE, DSTRECT-2                            | WORD
.set RGNA, MODE-4                               | RGNHANDLE
.set RGNB, RGNA-4                               | RGNHANDLE
.set RGNC, RGNB-4                               | RGNHANDLE

| -------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set NUMER, -4                                  | POINT
.set DENOM, NUMER-4                             | POINT
.set VERROR, DENOM-4                            | INTEGER
.set MINRECT, VERROR-8                          | RECT
.set SRCBUF, MINRECT-4                          | LONG
.set DSTBUF, SRCBUF-4                           | LONG
.set SRCLONGS, DSTBUF-2                         | WORD
.set DSTLONGS, SRCLONGS-2                       | WORD
.set STATEA, DSTLONGS-RGNREC                    | RGN STATE RECORD
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
.set SRCLIMIT, DSTROW-4                         | LONG
.set VERT, SRCLIMIT-2                           | WORD
.set MODECASE, VERT-4                           | LONG
.set PAT, MODECASE-4                            | LONG, ADDR OF PAT
.set RATIOCASE, PAT-4                           | LONG
.set FRACTION, RATIOCASE-2                      | WORD
.set VARSIZE, FRACTION                          | SIZE OF LOCAL VARIABLES

        MOVEM.L D0-D7/A1-A4,-(SP)               | SAVE REGS
        MOVE.L  A7,-0x6C(A6)                    | REMEMBER STACK FOR LATER

| ----------------------------------------------------------------
|
| CALC NUMER AND DENOM BASED ON DSTRECT AND SRCRECT.
| IF NUMER = DENOM THEN JUST CALL RGNBLT.
|
        MOVE.L  0x16(A6),A0                     | POINT TO DSTRECT

| ----------------------------------------------------------------
|
        MOVE    BOTTOM(A0),D0                   | GET DST BOTTOM
        SUB     (A0),D0                         | CALC DST HEIGHT
        SWAP    D0                              | PUT IN HI WORD
        MOVE    RIGHT(A0),D0                    | GET DST RIGHT
        SUB     LEFT(A0),D0                     | CALC DST WIDTH
        MOVE.L  0x1A(A6),A0                     | POINT TO SRCRECT
        MOVE    BOTTOM(A0),D1                   | GET SRC BOTTOM
        SUB     (A0),D1                         | CALC SRC HEIGHT
        SWAP    D1                              | PUT IN HI WORD
        MOVE    RIGHT(A0),D1                    | GET SRC RIGHT
        SUB     LEFT(A0),D1                     | CALC SRC WIDTH
        CMP.L   D0,D1                           | ARE BOTH RECTS SAME SIZE
  .short 0x662C                                 | BNE.B STRETCH

XRGNBLT:
        MOVE.L  0x22(A6),-(SP)                  | PUSH SRCBITS
        MOVE.L  0x1E(A6),-(SP)                  | PUSH DSTBITS
        MOVE.L  0x1A(A6),-(SP)                  | PUSH SRCRECT
        MOVE.L  0x16(A6),-(SP)                  | PUSH DSTRECT
        MOVE    0x14(A6),-(SP)                  | PUSH MODE
        MOVE.L  -0x94(A6),-(SP)                 | PAT ONLY USED FROM BELOW
        MOVE.L  0x10(A6),-(SP)                  | PUSH RGNA
        MOVE.L  0xC(A6),-(SP)                   | PUSH RGNB
        MOVE.L  0x8(A6),-(SP)                   | PUSH RGNC
        JSR     RgnBlt(PC)                      | CALL RGNBLT
        BRA     STRETCHBITS_GOHOME              | AND QUIT

| ----------------------------------------------------------
|
| STRETCH
|
| Called during boot.
STRETCH:
        MOVE.L  D0,-0x4(A6)                     | NUMER := DST SIZE
        MOVE.L  D1,-0x8(A6)                     | DENOM := SRC SIZE
        JSR     SetUpStretch(PC)                | CALC CASEJUMP AND HORIZ FRACT
        MOVE.L  A0,-0x98(A6)                    | SAVE CASE JUMP FOR LATER
        MOVE    D0,-0x9A(A6)                    | SAVE FRACTION FOR LATER

| ----------------------------------------------------------------
|
| ADJUST MODE AND PATTERN FOR COLOR SEPARATION.
|
        MOVE    0x14(A6),-(SP)                  | PUSH INPUT MODE
        MOVE.L  -0x94(A6),-(SP)                 | PUSH ADDR OF DUMMY PATTERN

| ----------------------------------------------------------------
|
        JSR     ColorMap(PC)                    | ALTER FOR COLOR SEPARATION
        MOVE.L  (SP)+,-0x94(A6)                 | GET (ALTERED) PATTERN
        MOVE    (SP)+,D2                        | GET (ALTERED) MODE
        MOVE    D2,D3                           | COPY MODE
        ROR     #4,D3                           | IS PATTERN BIT SET ?
        BCS.B   XRGNBLT                         | YES, USE RGNBLT TO DO PAT
        MOVE    D2,0x14(A6)                     | NO, UPDATE (ALTERED) MODE

| -------------------------------------------------------------------
|
| CALC MINRECT = INTERSECTION OF DSTRECT, DSTBITS.BOUNDS, AND THREE
| REGION BOUNDING BOXES. QUIT IF THE INTERSECTION IS EMPTY.
|
        MOVE.L  0x1E(A6),A3                     | POINT TO DST BITMAP
        MOVE.L  0x16(A6),-(SP)                  | PUSH ADDR OF DSTRECT

| -------------------------------------------------------------------
|
        PEA.L   BOUNDS(A3)                      | PUSH ADDR OF DSTBITS.BOUNDS
        MOVE.L  0x10(A6),A0                     | GET RGNHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        PEA.L   RGNBBOX(A0)                     | PUSH RGN BBOX
        MOVE.L  0xC(A6),A0                      | GET RGNHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        PEA.L   RGNBBOX(A0)                     | PUSH RGN BBOX
        MOVE.L  0x8(A6),A0                      | GET RGNHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        PEA.L   RGNBBOX(A0)                     | PUSH RGN BBOX
        MOVE    #5,-(SP)                        | PUSH NRECTS
        PEA.L   -0x14(A6)                       | PUSH WHERE TO PUT RESULT
        JSR     RSect(PC)                       | INTERSECT ALL RECTS
        BEQ     STRETCHBITS_GOHOME              | QUIT IF RESULT IS EMPTY

| ----------------------------------------------------
|
| HIDE THE CURSOR IF IT INTERSECTS MINRECT
|
        PEA.L   -0x14(A6)                       | PUSH SHIELD RECT
        MOVE.L  0x6(A3),-(SP)                   | PUSH DSTBITS.BOUNDS.TOP AND LEFT

| ----------------------------------------------------
|
        JSR     ShieldCursor(PC)                | REMOVE CURSOR IF INTERSECT
        MOVE    -0x6(A6),D0                     | GET DST WIDTH
        SUBQ.W  #0x1,D0                         | MINUS ONE FOR DBRA

| -----------------------------------------------------------------------
|
| ALLOCATE AND CLEAR SRCBUF TO HOLD SRCWIDTH.
|
        LSR     #5,D0                           | AND DIV BY 32 FOR LONGS
        MOVE    D0,-0x1E(A6)                    | SAVE FOR LATER
        CLR.L   -(SP)                           | CLEAR A LONG OF SLOP AT RIGHT
CLRSRC:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR A LONG
        DBF     D0,CLRSRC                       | LOOP ENTIRE BUFFER
        MOVE.L  A7,-0x18(A6)                    | |REMEMBER WHERE SRCBUF IS
        MOVE    -0x2(A6),D0                     | GET SRC WIDTH
        SUBQ.W  #0x1,D0                         | MINUS ONE FOR DBRA

| -----------------------------------------------------------------------
|
| ALLOCATE AND CLEAR DSTBUF TO HOLD DSTWIDTH.
|
        LSR     #5,D0                           | AND DIV BY 32 FOR LONGS
        MOVE    D0,-0x20(A6)                    | SAVE FOR LATER
        CLR.L   -(SP)                           | CLEAR A LONG OF SLOP AT RIGHT
        CLR.L   -(SP)                           | CLEAR ANOTHER LONG OF SLOP
CLRDST:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR A LONG
        DBF     D0,CLRDST                       | LOOP ENTIRE BUFFER
        MOVE.L  A7,-0x1C(A6)                    | |REMEMBER WHERE DSTBUF IS

| --------------------------------------------------------
|
| CALC BUFLEFT AND BUFSIZE FOR RGN SCANLINE BUFFERS
|
        MOVE.L  0x16(A6),A0                     | POINT TO DSTRECT

| --------------------------------------------------------
|
        MOVE    LEFT(A0),D1                     | GET DSTRECT LEFT
        SUB     BOUNDS+LEFT(A3),D1              | CONVERT TO GLOBAL COORDS (DSTBITS.BOUNDS.LEFT)
        ANDI    #-0x10,D1                       | TRUNCATE TO MULTIPLE OF 16
        ADD     BOUNDS+LEFT(A3),D1              | CONVERT BACK TO LOCAL
        MOVE    D1,-0x74(A6)                    | SAVE AS BUFLEFT
        MOVE    -0xE(A6),D0                     | GET DSTRECT RIGHT
        SUB     D1,D0                           | CALC WIDTH IN DOTS
        LSR     #5,D0                           | DIV BY 32 FOR LONGS
        MOVE    D0,-0x76(A6)                    | BUFSIZE = # LONGS -1

| -----------------------------------------------------------------------
|
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK.
|
| Called during boot.
STRETCHBITS_CLRMASK:
        CLR.L   -(SP)                           | CLRMASK: ALLOCATE AND CLEAR
        DBF     D0,STRETCHBITS_CLRMASK          | LOOP TILL DONE
        MOVE.L  A7,-0x72(A6)                    | |REMEMBER WHERE MASKBUF IS

| -------------------------------------------------------------------
|
| INIT STATE RECORDS VERT0 AND VERT1 IN CASE RECTANGULAR
|
        MOVE    #32767,D0                       | GET MAX INT
        MOVE    D0,-0x28(A6)                    | INIT A STATE RIGHT
        MOVE    D0,-0x40(A6)                    | INIT B STATE RIGHT
        MOVE    D0,-0x58(A6)                    | INIT C STATE RIGHT

| -------------------------------------------------------------------
|
        NEG     D0                              | GET MIN INT
        MOVE    D0,-0x2A(A6)                    | INIT A STATE LEFT
        MOVE    D0,-0x42(A6)                    | INIT B STATE LEFT
        MOVE    D0,-0x5A(A6)                    | INIT C STATE LEFT

| ----------------------------------------------------------------------
|
| ALLOCATE BUFFERS AND INIT STATE RECORDS FOR EACH NON-RECT REGION
|
        MOVEQ   #10,D7                          | RGN SIZE IF RECTANGULAR
        CLR     D5                              | INIT ALL RGNS RECT
        MOVE.L  0x10(A6),A0                     | GET RGNHANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMP     (A0),D7                         | IS RGNA RECTANGULAR ?
        BEQ.B   STRETCHBITS_CLRMASK_SKIP        | YES, SKIP IT
        ADDQ.W  #0x2,D5                         | SET RGNA FLAG
        LEA.L   -0x38(A6),A1                    | POINT TO STATE RECORD A
        BSR.B   STRETCHBITS_CLRMASK_CONT        | INIT STATE, ALLOC BUFFER

| ARECT
| Called during boot.
STRETCHBITS_CLRMASK_SKIP:
        MOVE.L  0xC(A6),A0                      | GET RGNHANDLE

| ARECT
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMP     (A0),D7                         | IS RGNB RECTANGULAR ?
        BEQ.B   STRETCHBITS_CLRMASK_SKIP_2      | YES, SKIP IT
        ADDQ.W  #0x4,D5                         | SET RGNB FLAG
        LEA.L   -0x50(A6),A1                    | POINT TO STATE RECORD B
        BSR.B   STRETCHBITS_CLRMASK_CONT        | INIT STATE, ALLOC BUFFER

| BRECT
| Called during boot.
STRETCHBITS_CLRMASK_SKIP_2:
        MOVE.L  0x8(A6),A0                      | GET RGNHANDLE

| BRECT
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        CMP     (A0),D7                         | IS RGNC RECTANGULAR ?
        BEQ.B   STRETCHBITS_CLRMASK_EXIT        | YES, SKIP IT
        ADDQ.W  #0x8,D5                         | SET RGNC FLAG
        LEA.L   -0x68(A6),A1                    | POINT TO STATE RECORD C
        PEA.L   STRETCHBITS_CLRMASK_EXIT(PC)    | PUSH FAKE RETURN ADDR
| STRETCHBITS_CLRMASK_CONT -- iNIT STATE, ALLOC BUFFER.
STRETCHBITS_CLRMASK_CONT:
        MOVE    -0x12(A6),D0                    | GET MINRECT LEFT
        MOVE    -0xE(A6),D1                     | GET MINRECT RIGHT
        MOVE    -0x74(A6),D2                    | GET BUFLEFT
        JMP     InitRgn(PC)                     | INIT STATE, ALLOC BUFFER

| ----------------------------------------------------------
|
| STRETCHBITS_CLRMASK_EXIT
|
| Called during boot.
STRETCHBITS_CLRMASK_EXIT:
        MOVE    D5,-0x6E(A6)                    | SAVE RECTFLAG

| CRECT

| --------------------------------------------------------------------
|
| IF ALL REGIONS ARE RECTANGULAR, THEN DRAW MINRECT INTO MASK BUFFER
|
        BNE.B   STRETCHBITS_CLRMASK_NO          | NO, CONTNUE
        MOVE.L  -0x72(A6),A0                    | YES, POINT TO MASK BUFFER
        MOVE    -0x12(A6),D3                    | GET MINRECT LEFT
        SUB     -0x74(A6),D3                    | MAKE IT BUFFER RELATIVE
        MOVE    -0xE(A6),D4                     | GET MINRECT RIGHT
        SUB     -0x74(A6),D4                    | MAKE IT BUFFER RELATIVE
        JSR     XorSlab(PC)                     | AND XOR BETWEEN THEM

| NOTRECT

| ------------------------------------------------------
|
| SET UP INVERT FLAG IN D7 TO REFLECT MODE BIT 2
|
| Called during boot.
STRETCHBITS_CLRMASK_NO:
        CLR.L   D7                              | SAY NOT INVERTED
        MOVE    0x14(A6),D2                     | GET TRANSFER MODE
        BMI     STRETCHBITS_DONE                | QUIT IF MODE NEGATIVE
        BCLR    #2,D2                           | TEST AND CLR INVERT BIT
        BEQ.B   STRETCHBITS_CLRMASK_SKIP_3      | SKIP IF NOT INVERTED
        NOT.L   D7                              | INVERTED; D7 GETS ALL 1'S
STRETCHBITS_CLRMASK_SKIP_3:
        CMPI    #0x7,D2                         | IS MODE > 7 ?

| --------------------------------------------------
|
| CALCULATE CASE JUMP FOR DIFFERENT TRANSFER MODES
|
        BGT     STRETCHBITS_DONE                | YES, QUIT
        LEA.L   STRETCHBITS_ABCDONE_MODE_TBL(PC),A0 | POINT TO MODE TABLE
        MOVE.B  0x0(A0,D2.W),D2                 | GET TABLE ENTRY
        SUB     D2,A0                           | COMPUTE ADDRESS
        MOVE.L  A0,-0x90(A6)                    | SAVE FOR LATER

| ------------------------------------------------
|
| SET UP SRCROW, SRCLIMIT, SRCSHIFT, AND SRCADDR
|
        MOVE.L  0x22(A6),A2                     | POINT TO SRCBITS

| ------------------------------------------------
|
        MOVE    ROWBYTES(A2),D0                 | GET SRC ROWBYTES
        EXT.L   D0                              | AND EXTEND TO LONG
        MOVE.L  D0,-0x82(A6)                    | SRCROW := SRC ROWBYTES
        MOVE    0xA(A2),D1                      | GET SRC BOTTOM
        SUB     0x6(A2),D1                      | CALC SRC HEIGHT
        MULU    D0,D1                           | MULT BY SRC ROWBYTES
        ADD.L   (A2),D1                         | ADD SRCBASE
        ADDQ.L  #0x2,D1                         | PLUS TWO BYTE SLOP
        MOVE.L  D1,-0x8A(A6)                    | SAVE RESULT AS SRCLIMIT
        MOVE.L  0x1A(A6),A0                     | POINT TO SRCRECT
        MOVE    LEFT(A0),D1                     | GET SRCRECT LEFT
        SUB     0x8(A2),D1                      | SUBTRACT SRC LEFT
        MOVE    D1,D5                           | MAKE A COPY
        NEG     D5                              | NEGATE IT AND
        ANDI    #0xF,D5                         | TREAT MOD 16 FOR SHIFTCNT
        MOVE    (A0),D0                         | GET SRCRECT TOP
        SUB     0x6(A2),D0                      | SUBTRACT SRC TOP
        MULU    ROWBYTES(A2),D0                 | MULT BY SRC ROWBYTES
        MOVE.L  (A2),A0                         | GET SRCBASE
        ADD.L   D0,A0                           | ADD VERTICAL OFFSET
        ADD     D5,D1                           | ADJUST SRCLEFT FOR SRCSHIFT
        ASR     #4,D1                           | CONVERT DOTS TO WORDS
        ADD     D1,A0                           | ADD HORIZONTAL OFFSET
        ADD     D1,A0                           | TWICE FOR BYTES
        MOVE.L  A0,-0x7A(A6)                    | SAVE AS SRCADDR

| ----------------------------------------------------
|
| CALC STARTING DSTROW, DSTSHIFT, AND DSTADDR
|
        MOVE    ROWBYTES(A3),D0                 | GET DST ROWBYTES
        EXT.L   D0                              | EXTEND TO LONG
        MOVE.L  D0,-0x86(A6)                    | DSTROW := DST ROWBYTES
        MOVE.L  0x16(A6),A0                     | POINT TO DSTRECT
        MOVE    (A0),-0x8C(A6)                  | CURRENT VERT := DSTRECT TOP
        MOVE    LEFT(A0),D1                     | GET DSTRECT LEFT
        SUB     0x8(A3),D1                      | SUBTRACT DST LEFT
        MOVEQ.L #0xF,D6                         | MOD 16 MASK
        AND     D1,D6                           | TREAT MOD 16 FOR SHIFTCNT
        MOVE    -0x14(A6),D0                    | GET MINRECT TOP
        SUB     0x6(A3),D0                      | SUBTRACT DST TOP
        MULU    ROWBYTES(A3),D0                 | MULT BY DST ROWBYTES
        MOVE.L  (A3),A0                         | GET DSTBASE
        ADD.L   D0,A0                           | ADD VERTICAL OFFSET
        ASR     #4,D1                           | CONVERT DOTS TO WORDS
        ADD     D1,A0                           | ADD HORIZ OFFSET
        ADD     D1,A0                           | TWICE FOR BYTES
        MOVE.L  A0,-0x7E(A6)                    | SAVE AS DSTADDR
        MOVE    -0x8(A6),D0                     | GET DENOM.V

| -----------------------------------------------------
|
| INIT ERROR TERM FOR DDA
|
        LSR     #1,D0                           | DIVIDE BY 2
        NEG     D0                              | NEGATE FOR INITIAL ERROR
        MOVE    D0,-0xC(A6)                     | VERROR := -DENOM.V/2

| -----------------------------------------------------
|
| GET FIRST SCANLINE OF SRC INTO SRCBUF
|
| Called during boot.
NEXTSRC:
        MOVE.L  -0x7A(A6),A0                    | POINT TO SRC BITMAP
        CMPA.L  -0x8A(A6),A0                    | IS IT EXHAUSTED ?
        BCC     STRETCHBITS_DONE                | QUIT IF EXHAUSTED
        MOVE.L  -0x18(A6),A1                    | POINT TO SRCBUF
        MOVE    -0x1E(A6),D1                    | GET COUNT OF LONGS
NEXTSRC_LOOP:
        MOVE.L  -0x2(A0),D0                     | GET FIRST LONG OF SRC

| -----------------------------------------------------
|
| GET FIRST SCANLINE OF SRC INTO SRCBUF
|
        LSR.L   D5,D0                           | ALIGN TO SRCBUF
        MOVE    D0,(A1)+                        | PUT A WORD TO SRCBUF
        MOVE.L  (A0)+,D0                        | GET A SECOND LONG
        LSR.L   D5,D0                           | ALIGN TO SRCBUF
        MOVE    D0,(A1)+                        | PUT A WORD TO SRCBUF
        DBF     D1,NEXTSRC_LOOP                 | LOOP FOR ALL LONGS
        MOVE.L  -0x82(A6),D2                    | GET SRC ROWBYTES
        ADD.L   D2,-0x7A(A6)                    | BUMP SRC TO NEXT ROW
        MOVE    -0x4(A6),D0                     | GET NUMER.V
        ADD     D0,-0xC(A6)                     | VERROR := VERROR + NUMER.V
        BGT.B   SRCLOOP_EXIT                    | SKIP IF VERROR > 0

| -----------------------------------------------------
|
| WHILE (VERROR < 0) DO MERGE OTHER SCANLINES INTO SRCBUF.
|
| Called during boot.
SRCLOOP:
        MOVE.L  -0x7A(A6),A0                    | POINT TO SRC BITMAP
        CMPA.L  -0x8A(A6),A0                    | IS IT EXHAUSTED ?
        BCC.B   SRCLOOP_EXIT                    | QUIT IF EXHAUSTED
        MOVE.L  -0x18(A6),A1                    | POINT TO SRCBUF
        MOVE    -0x1E(A6),D1                    | GET COUNT OF LONGS
SRCLOOP_LOOP:
        MOVE.L  -0x2(A0),D0                     | GET NEXT LONG OF SRC

| -----------------------------------------------------
|
| WHILE (VERROR < 0) DO MERGE OTHER SCANLINES INTO SRCBUF.
|
        LSR.L   D5,D0                           | ALIGN TO SRCBUF
        OR      D0,(A1)+                        | OR A WORD TO SRCBUF
        MOVE.L  (A0)+,D0                        | GET A SECOND LONG
        LSR.L   D5,D0                           | ALIGN TO SRCBUF
        OR      D0,(A1)+                        | OR A WORD TO SRCBUF
        DBF     D1,SRCLOOP_LOOP                 | LOOP FOR ALL LONGS
        ADD.L   D2,-0x7A(A6)                    | BUMP SRC TO NEXT ROW
        MOVE    -0x4(A6),D0                     | GET NUMER.V
        ADD     D0,-0xC(A6)                     | VERROR := VERROR + NUMER.V
        BLE.B   SRCLOOP                         | LOOP WHILE VERROR <= 0

| SRCOK

| ----------------------------------------------------------
|
| HORIZONTALLY STRETCH SRCBUF INTO DSTBUF
|
| Called during boot.
SRCLOOP_EXIT:
        MOVE.L  -0x18(A6),A0                    | POINT TO SRCBUF
        MOVE.L  -0x1C(A6),A1                    | POINT TO DSTBUF
        MOVE    -0x20(A6),D0                    | GET DSTLONGS

| SRCOK

| ----------------------------------------------------------
|
| HORIZONTALLY STRETCH SRCBUF INTO DSTBUF
|
        LSL     #2,D0                           | QUAD FOR BYTE OFFSET
        LEA.L   0x4(A1,D0.W),A2                 | POINT TO DSTLIMIT
        MOVE    -0x9A(A6),D4                    | GET HORIZONTAL FRACTION
        MOVE.L  -0x98(A6),A3                    | GET CASE JUMP
        JSR     (A3)                            | AND CALL STRETCHROW

| -------------------------------------------------------
|
| TRANSFER ONE OR MORE COPIES OF DSTBUF INTO DSTBITS
|
| Called during boot.
STRETCHBITS_NXTMASK:
        MOVE    -0x8C(A6),D0                    | GET CURRENT VERT COORD
        CMP     -0x14(A6),D0                    | IS VERT < MINRECT TOP ?

| -------------------------------------------------------
|
| TRANSFER ONE OR MORE COPIES OF DSTBUF INTO DSTBITS
|
        BLT.B   NEXTDST_SKIP                    | YES, DON'T DRAW
        BSR     STRETCHBITS_GOHOME_CONT         | MAKE MASK BUFFER CURRENT
        MOVE.L  -0x1C(A6),A3                    | INIT SRCPTR
        MOVE.L  -0x7E(A6),A4                    | INIT DSTPTR FOR ROW
        MOVE.L  -0x72(A6),A2                    | INIT MASKPTR FOR ROW
        MOVE    -0x76(A6),D2                    | INIT COUNT OF LONGS
        MOVE.L  -0x90(A6),A0                    | GET MODE CASE JUMP
        JMP     (A0)                            | TAKE MODE JUMP

| ----------------------------------------------------------
|
| NEXTDST
|
| Called during boot.
NEXTDST:
        MOVE.L  -0x86(A6),D0                    | GET DST ROWBYTES
        ADD.L   D0,-0x7E(A6)                    | BUMP DST TO NEXT ROW
NEXTDST_SKIP:
        ADDQ.W  #0x1,-0x8C(A6)                  | CURRENT VERT := CURRENT VERT + 1
        MOVE    -0x8C(A6),D0                    | GET VERT
        CMP     -0x10(A6),D0                    | IS VERT >= MINRECT BOTTOM ?
        BEQ.B   STRETCHBITS_DONE                | YES, QUIT
        MOVE    -0x8(A6),D0                     | GET DENOM.V
        SUB     D0,-0xC(A6)                     | VERROR := VERROR - DENOM.V
        BGE.B   STRETCHBITS_NXTMASK             | IF VERROR >= 0 THEN DRAW MORE
        BRA     NEXTSRC                         | ELSE GET NEXT SRC

| -----------------------------------------------------------------
|
| ENTIRE STRETCHBITS COMPLETE. RESTORE REGS AND STACK AND GO HOME.
|
| Called during boot.
STRETCHBITS_DONE:
        JSR     ShowCursor(PC)                  | RESTORE CURSOR
STRETCHBITS_GOHOME:
        MOVE.L  -0x6C(A6),SP                    | STRIP VARIABLE SIZED BUFFER
        MOVEM.L (SP)+,D0-D7/A1-A4               | RESTORE REGISTERS
        UNLK    A6                              | UNLINK
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA    #0x1E,SP                        | STRIP PARAMS
        JMP     (A0)                            | RETURN TO CALLER

| -----------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE MASK BUFFER TO CURRENT VERTICAL COORD.
|
| Called during boot.
STRETCHBITS_GOHOME_CONT:
        MOVE    -0x8C(A6),D0                    | GET CURRENT VERT COORD
        MOVE    -0x6E(A6),D1                    | GET RECTFLAG = 0,2,4
        MOVE    STRETCHBITS_GOHOME_CONT_2(PC,D1.W),D1 | GET OFFSET
        JMP     STRETCHBITS_GOHOME_CONT_2(PC,D1.W) | TAKE DISPATCH

| ----------------------------------------------------------
|
| STRETCHBITS_GOHOME_CONT_2 - indexed branch table for StretchBits region masking modes
|
STRETCHBITS_GOHOME_CONT_2:
  .byte 0x00,0x9A,0x00,0x10,0x00,0x16           | BOTH RECT, A ONLY, MASK+A
  .byte 0x00,0x2A,0x00,0x1C,0x00,0x4A           | B ONLY, MASK+B, A+B
  .byte 0x00,0x6A,0x00,0x9C                     | MASK+A+B, ALL FOUR

| --------------------------------------------------------------------
|
| ONLY REGION A IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
STRETCHBITS_GOHOME_CONT_3:
        LEA.L   -0x38(A6),A1                    | POINT TO RGNA STATE

| -----------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE MASK BUFFER TO CURRENT VERTICAL COORD.
|

| --------------------------------------------------------------------
|
        BRA.B   STRETCHBITS_JMPSEEK             | UPDATE AND USE AS MASK

| --------------------------------------------------------------------
|
| ONLY REGION B IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
| Called during boot.
STRETCHBITS_GOHOME_CONT_4:
        LEA.L   -0x50(A6),A1                    | POINT TO RGNB STATE

| --------------------------------------------------------------------
|
        BRA.B   STRETCHBITS_JMPSEEK             | UPDATE AND USE AS MASK

| --------------------------------------------------------------------
|
| ONLY REGION C IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
STRETCHBITS_GOHOME_CONT_5:
        LEA.L   -0x68(A6),A1                    | POINT TO RGNC STATE
STRETCHBITS_JMPSEEK:
        MOVE.L  -0x72(A6),SCANBUF(A1)           | PLAY DIRECTLY INTO MASKBUF

| --------------------------------------------------------------------
|
| ONLY REGION C IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
        JMP     SeekRgn(PC)                     | UPDATE AND RETURN

| -------------------------------------------------------------------
|
| REGIONS A AND B ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
STRETCHBITS_JMPSEEK_CONT:
        LEA.L   -0x38(A6),A1                    | POINT TO RGNA STATE

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNA
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x50(A6),A1                    | POINT TO RGNB STATE
        JSR     SeekRgn(PC)                     | UPDATE RGNB
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   STRETCHBITS_BCLOOP_DONE         | NO, WE'RE DONE
        MOVE.L  -0x30(A6),A0                    | GET RGNA SCANBUF
        MOVE.L  -0x48(A6),A1                    | GET RGNB SCANBUF
        BRA.B   STRETCHBITS_CPY2BUF             | DO THE INTERSECTION

| -------------------------------------------------------------------
|
| REGIONS A AND C ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
STRETCHBITS_JMPSEEK_CONT_2:
        LEA.L   -0x38(A6),A1                    | POINT TO RGNA STATE

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNA
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x68(A6),A1                    | POINT TO RGNC STATE
        JSR     SeekRgn(PC)                     | UPDATE RGNC
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   STRETCHBITS_BCLOOP_DONE         | NO, WE'RE DONE
        MOVE.L  -0x30(A6),A0                    | GET RGNA SCANBUF
        MOVE.L  -0x60(A6),A1                    | GET RGNC SCANBUF
        BRA.B   STRETCHBITS_CPY2BUF             | DO THE INTERSECTION

| -------------------------------------------------------------------
|
| REGIONS B AND C ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
STRETCHBITS_JMPSEEK_CONT_3:
        LEA.L   -0x50(A6),A1                    | POINT TO RGNB STATE

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNB
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x68(A6),A1                    | POINT TO RGNC STATE
        JSR     SeekRgn(PC)                     | UPDATE RGNC
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   STRETCHBITS_BCLOOP_DONE         | NO, WE'RE DONE
        MOVE.L  -0x48(A6),A0                    | GET RGNB SCANBUF
        MOVE.L  -0x60(A6),A1                    | GET RGNC SCANBUF
STRETCHBITS_CPY2BUF:
        MOVE.L  -0x72(A6),A2                    | POINT TO COMPOSITE MASKBUF
        MOVE    -0x76(A6),D1                    | GET LONGCNT - 1
STRETCHBITS_BCLOOP:
        MOVE.L  (A0)+,D0                        | BCLOOP
        AND.L   (A1)+,D0                        | INTERSECT TWO SCANLINES
        MOVE.L  D0,(A2)+                        | PUT TO COMPOSITE SCANBUF
        DBF     D1,STRETCHBITS_BCLOOP           | LOOP ALL LONGS
STRETCHBITS_BCLOOP_DONE:
        RTS                                     | SEEKOK: ALL 3 ARE RECT, DO NOTHING

| -------------------------------------------------------------------
|
| REGIONS A, B AND C ARE ALL NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
STRETCHBITS_BCLOOP_CONT:
        LEA.L   -0x38(A6),A1                    | POINT TO RGNA STATE

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | UPDATE RGNA
        MOVE    D1,-(SP)                        | REMEMBER IF RGN CHANGED
        LEA.L   -0x50(A6),A1                    | POINT TO RGNB STATE
        JSR     SeekRgn(PC)                     | UPDATE RGNB
        OR      D1,(SP)                         | REMEMBER IF RGN CHANGED
        LEA.L   -0x68(A6),A1                    | POINT TO RGNC STATE
        JSR     SeekRgn(PC)                     | UPDATE RGNC
        OR      (SP)+,D1                        | HAS EITHER RGN CHANGED ?
        BEQ.B   STRETCHBITS_ABCDONE             | NO, WE'RE DONE
        MOVE.L  -0x30(A6),A0                    | GET RGNA SCANBUF
        MOVE.L  -0x48(A6),A1                    | GET RGNB SCANBUF
        MOVE.L  -0x60(A6),A2                    | GET RGNC SCANBUF
        MOVE.L  -0x72(A6),A3                    | POINT TO MASKBUF
        MOVE    -0x76(A6),D1                    | GET LONGCNT - 1
STRETCHBITS_ABCLOOP:
        MOVE.L  (A0)+,D0                        | ABCLOOP
        AND.L   (A1)+,D0                        | INTERSECT SECOND SCANLINE
        AND.L   (A2)+,D0                        | INTERSECT THIRD SCANLINE
        MOVE.L  D0,(A3)+                        | PUT TO COMPOSITE SCANBUF
        DBF     D1,STRETCHBITS_ABCLOOP          | LOOP ALL LONGS
STRETCHBITS_ABCDONE:
        RTS                                     | ABCDONE

| ----------------------------------------------------------
|
| STRETCHBITS_ABCDONE_LOOP
|
| Called during boot.
STRETCHBITS_ABCDONE_LOOP:
        MOVE.L  -0x2(A3),D0                     | FETCH NEXT DST WORD

| ---------------------------------------------------------------;
| ;
| INTERFACE TO EACH OF THE STRETCHBITS SCANLINE LOOPS: ;
| REGISTERS: A0: D0: ;
| A1: D1: ;
| A2: MASKPTR D2: LONGCNT ;
| A3: SRCPTR D3: ;
| A2: DSTPTR D4: ;
| A4: D5: SRCSHIFT ;
| A6: D6: DSTSHIFT ;
| A7: D7: INVERT ;
| ---------------------------------------------------------------;

| -------------------------------------------------------
|
| MODE 0 OR 4: SRC --> DST
|
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
        DBF     D2,STRETCHBITS_ABCDONE_LOOP     | LOOP ALL LONGS THIS ROW
        BRA     NEXTDST                         | GO FOR NEXT ROW

| ----------------------------------------------------------
|
| STRETCHBITS_ABCDONE_LOOP_2
|
STRETCHBITS_ABCDONE_LOOP_2:
        MOVE.L  -0x2(A3),D0                     | FETCH NEXT DST WORD

| -------------------------------------------------------
|
| MODE 1 OR 5: SRC OR DST --> DST
|
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3)+,D1                        | GET SRC FROM BITMAP
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A2)+,D0                        | AND WITH MASK
        OR.L    D0,(A4)+                        | OR RESULT INTO DST
        DBF     D2,STRETCHBITS_ABCDONE_LOOP_2   | LOOP ALL LONGS THIS ROW
        BRA     NEXTDST                         | LOOP FOR NEXT ROW

| ----------------------------------------------------------
|
| STRETCHBITS_ABCDONE_LOOP_3
|
STRETCHBITS_ABCDONE_LOOP_3:
        MOVE.L  -0x2(A3),D0                     | FETCH NEXT DST WORD

| -------------------------------------------------------
|
| MODE 2 OR 6: SRC XOR DST --> DST
|
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3)+,D1                        | GET SRC FROM BITMAP
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A2)+,D0                        | AND WITH MASK
        EOR.L   D0,(A4)+                        | XOR RESULT INTO DST
        DBF     D2,STRETCHBITS_ABCDONE_LOOP_3   | LOOP ALL LONGS THIS ROW
        BRA     NEXTDST                         | LOOP FOR NEXT ROW

| ----------------------------------------------------------
|
| STRETCHBITS_ABCDONE_LOOP_4
|
STRETCHBITS_ABCDONE_LOOP_4:
        MOVE.L  -0x2(A3),D0                     | FETCH NEXT DST WORD

| -------------------------------------------------------
|
| MODE 3 OR 7: SRC BIC DST --> DST
|
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3)+,D1                        | GET SRC FROM BITMAP
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A2)+,D0                        | AND WITH MASK
        NOT.L   D0                              | INVERT FOR BIC
        AND.L   D0,(A4)+                        | BIC RESULT INTO DST
        DBF     D2,STRETCHBITS_ABCDONE_LOOP_4   | LOOP ALL LONGS THIS ROW
        BRA     NEXTDST                         | LOOP FOR NEXT ROW

| .PROC SetupStretch
| --------------------------------------------------------------
|
| Routine to setup case jump for StretchRow,
| based on horiz numer and denom.
|
| Call SetupStretch with numer in D0, denom in D1.
| Returns case jump in A0, fraction in D0.
|
| Call resulting case jump with:
|
| A0: srcPtr
| A1: dstPtr
| A2: dstLimit
| D4: fraction
|
| clobbers D0-D3,A0-A1
|
STRETCHBITS_ABCDONE_MODE_TBL:
  .byte 0x7A,0x56,0x3A,0x1E                     | STRETCH CASE OFFSETS: 1X,2X,3X,4X
| SetUpStretch -- cALC CASEJUMP AND HORIZ FRACT.
SetUpStretch:
        LEA.L   WHITE2_ERR(PC),A0               | POINT TO ABORT
        TST      D0                             | IS NUMER <= 0 ?
        BLE     FOUND                           | YES, POINT TO ABORT
        TST      D1                             | IS DENOM <= 0 ?
        BLE     FOUND                           | YES, POINT TO ABORT
        LEA.L   SHRNKING_LOOP(PC),A0            | POINT TO FAST COPY
        CMP      D1,D0                          | IS NUMER = DENOM ?
        BEQ     FOUND                           | YES, USE FAST COPY
        BLT.B   SHRNKING                        | NO, BRANCH IF SHRINKING

|
| We will be stretching. Calc fract = denom/numer and check for fast.
|
STRCHING:
        MOVE    D0,D3                           | MAKE A COPY OF NUMER
        MOVE     D1,D4                          | MAKE A COPY OF DENOM
        CLR.L    -(SP)                          | ROOM FOR FCN RESULT
        MOVE     D1,-(SP)                       | PUSH DENOM
        MOVE     D0,-(SP)                       | PUSH NUMER
        _FixRatio                               | CALL FIXRATIO, < 1.0
        MOVE.L   (SP)+,D0                       | POP RESULT
        LEA.L   QRTR2_LOOP_2(PC),A0             | CHECK FOR FAST RATIOS
        CMPI    #-0x8000,D0                     | HALF RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   TRIPLE_LOOP(PC),A0              | CHECK FOR QUADRUPLE
        CMPI    #0x4000,D0                      | QUADRUPLE RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   SIX_LOOP(PC),A0                 | CHECK FOR OCTUPLE
        CMPI    #0x2000,D0                      | OCTUPLE RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   EIGHT_CONT_2(PC),A0             | CHECK FOR HEXADECUPLE
        CMPI    #0x1000,D0                      | HEXADECUPLE RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   QRTR2_LOOP(PC),A0               | CHECK FOR 1.5 RATIO
        CMPI    #-0x5556,D0                     | 1.5 RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   TRIPLE(PC),A0                   | CHECK FOR TRIPLE
        CMPI    #0x5555,D0                      | TRIPLE RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   QUAD_LOOP(PC),A0                | CHECK FOR SEXTUPLE
        CMPI    #0x2AAA,D0                      | SEXTUPLE RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH

|
| check for any multiple of 8:
|
        EXT.L    D3                             | CLEAR HI WORD OF NUMER
        DIVU     D4,D3                          | CALC NUMER DIV DENOM
        MOVE     D3,D1                          | SAVE QUOTIENT
        ANDI.L  #0xFFFF0007,D3                  | IS IT A MULTIPLE OF 8 ?
        BNE.B   NOMATCH                         | NO, USE GENERAL STRETCH
        MOVE     D1,D0                          | YES RETURN QUOTIENT IN D0
        LEA.L   BLACK16_CONT(PC),A0             | POINT TO FAST ROUTINE
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| NOMATCH
|
NOMATCH:
        LEA.L   WHITE1_CONT(PC),A0              | POINT TO SLOW GENERAL CODE
FOUND:
        RTS                                     | RETURN WITH CASE JUMP IN A0

|
| We will be shrinking. Calc fract = numer/denom and check for fast.
|
| Called during boot.
SHRNKING:
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE     D0,-(SP)                       | PUSH NUMER
        MOVE     D1,-(SP)                       | PUSH DENOM
        _FixRatio                               | CALL FIXRATIO, < 1.0
        MOVE.L   (SP)+,D0                       | POP RESULT
        LEA.L   HALF(PC),A0                     | CHECK FOR FAST RATIOS
        CMPI    #-0x8000,D0                     | HALF RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   HALF2_CONT(PC),A0               | CHECK FOR QUARTER
        CMPI    #0x4000,D0                      | QUARTER RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   THREE4(PC),A0                   | CHECK FOR 3/4
        CMPI    #-0x4000,D0                     | 3/4 RATIO ?
        BEQ.B   FOUND                           | YES, BRANCH
        LEA.L   EIGHTS3_CONT(PC),A0             | GENERAL SHRINK ROUTINE
        BRA.B   FOUND                           | DONE

| -----------------------------------------------
|
| NUMERATOR = DENOMINATOR, JUST COPY LONGS
|
SHRNKING_LOOP:
        MOVE.L  (A0)+,(A1)+                     | COPY ONE LONG
        MOVE.L  (A0)+,(A1)+                     | COPY ANOTHER LONG
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   SHRNKING_LOOP                   | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ---------------------------------------------------
|
| SHRINK TO THREE QUARTERS.
|
THREE4:
        MOVEQ   #3,D3                           | MASK FOR HI 2 BITS
        ROR.L   #2,D3                           | IE. $C0000000
        CLR.L   -(SP)                           | ALLOCATE A LONG OF TEMP
THREE4A:
        MOVE.L  (A0)+,D0                        | GET A LONG OF SRC
        MOVEQ   #7,D2                           | INIT COUNT OF 24 DST BITS
THREE4B:
        ADD.L   D0,D0                           | GET 1 BIT OF SRC
        ADDX.L  D1,D1                           | PUT 1 BIT TO DST
        ADD.L   D3,D0                           | PUT HI 2 BITS INTO CARRY
        ADDX.L  D1,D1                           | SHIFT INTO DST
        LSL.L   #3,D0                           | SHIFT LEFT 3 BITS
        ADDX.L  D1,D1                           | PUT CARRY BIT INTO DST
        DBF     D2,THREE4B                      | LOOP 8 TIMES
        MOVE.L  D1,(SP)                         | STASH 3 DST BYTES IN TEMP
        MOVE.B  0x1(SP),(A1)+                   | PUT FIRST BYTE TO DST
        MOVE.B  0x2(SP),(A1)+                   | PUT SECOND BYTE TO DST
        MOVE.B  0x3(SP),(A1)+                   | PUT THIRD BYTE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   THREE4A                         | LOOP UNTIL DSTLIMIT
        ADDQ.W  #0x4,SP                         | CLEANUP TEMP STORAGE
        RTS                                     | AND QUIT

| ---------------------------------------------------
|
| SHRINK TO ONE HALF.
|
HALF:
        MOVEQ   #3,D3                           | MASK FOR HI 2 BITS
        ROR.L   #2,D3                           | IE. $C0000000
HALF1:
        MOVE.L  (A0)+,D0                        | GET A LONG OF SRC
        MOVEQ   #7,D2                           | INIT COUNT OF 16 DST BITS
HALF2:
        ADD.L   D3,D0                           | PUT OR OF HI BITS INTO CARRY
        ADDX    D1,D1                           | SHIFT BIT INTO DST
        LSL.L   #2,D0                           | SHIFT LEFT 2 BITS
        ADD.L   D3,D0                           | PUT OR OF HI BITS INTO CARRY
        ADDX.L  D1,D1                           | SHIFT BIT INTO DST
        LSL.L   #2,D0                           | SHIFT LEFT 2 BITS
        DBF     D2,HALF2                        | LOOP 8 TIMES
        MOVE    D1,(A1)+                        | THEN PUT A WORD TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   HALF1                           | LOOP UNTIL DSTLIMIT
        RTS                                     | YES, QUIT

| ---------------------------------------------------
|
| SHRINK TO ONE QUARTER.
|
HALF2_CONT:
        MOVE.L  #0xF0000000,D3                  | MASK FOR HI 4 BITS

| ---------------------------------------------------
|
QRTR1:
        MOVE.L  (A0)+,D0                        | GET A LONG OF SRC
        MOVEQ   #7,D2                           | INIT COUNT OF 8 DST BITS
QRTR2:
        ADD.L   D3,D0                           | PUT OR OF HI BITS INTO CARRY
        ADDX.L  D1,D1                           | SHIFT BIT INTO DST
        LSL.L   #4,D0                           | SHIFT LEFT 4 BITS
        DBF     D2,QRTR2                        | LOOP 8 TIMES
        MOVE.B  D1,(A1)+                        | THEN PUT A BYTE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   QRTR1                           | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| QRTR2_LOOP
|
QRTR2_LOOP:
        MOVE.B  (A0)+,D0                        | GET FIRST BYTE FROM SRC

| RTS ;YES, QUIT

| -----------------------------------------------
|
| STRETCH TO 1.5 TIMES AS WIDE
|
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        LSR.B   #4,D1                           | GET HI NIBBLE
        MOVE.B  QRTR2_CONT(PC,D1.W),D2          | EXPAND TO 6 BITS
        LSL.L   #6,D2                           | SHIFT OVER 6
        ANDI    #0xF,D0                         | GET LO NIBBLE
        MOVE.B  QRTR2_CONT(PC,D0.W),D2          | EXPAND TO 6 BITS
        LSL.L   #6,D2                           | SHIFT OVER 6
        MOVE.B  (A0)+,D0                        | GET SECOND BYTE FROM SRC
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        LSR.B   #4,D1                           | GET HI NIBBLE
        MOVE.B  QRTR2_CONT(PC,D1.W),D2          | EXPAND TO 6 BITS
        LSL.L   #6,D2                           | SHIFT OVER 6
        ANDI    #0xF,D0                         | GET LO NIBBLE
        MOVE.B  QRTR2_CONT(PC,D0.W),D2          | EXPAND TO 6 BITS
        LSR.L   #2,D2                           | RIGHT JUSTIFY
        SWAP    D2                              | FLIP WORDS
        MOVE.B  D2,(A1)+                        | PUT FIRST BYTE TO DST
        SWAP    D2                              | FLIP BACK AGAIN
        MOVE    D2,D1                           | MOVE FOR SECOND BYTE
        ROR     #8,D1                           | ROTATE TO GET SECOND BYTE
        MOVE.B  D1,(A1)+                        | PUT SECOND BYTE TO DST
        MOVE.B  D2,(A1)+                        | PUT THIRD BYTE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   QRTR2_LOOP                      | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| QRTR2_CONT - indexed branch table for stretch source sampling
|
QRTR2_CONT:
  .byte 0x00,0x0C,0x10,0x1C,0x60,0x6C           | HALF: 4-BIT SAMPLE TABLE LO
  .byte 0x70,0x7C,0x80,0x8C,0x90,0x9C           | HALF: 4-BIT SAMPLE TABLE MID
  .byte 0xE0,0xEC,0xF0,0xFC                     | HALF: 4-BIT SAMPLE TABLE HI

| RTS ;ALL DONE

| .BYTE $60,$6C,$70,$7C
| .BYTE $80,$8C,$90,$9C
| .BYTE $E0,$EC,$F0,$FC

| -----------------------------------------------
|
| DOUBLE USING TABLE LOOKUP
|
QRTR2_LOOP_2:
        MOVE.B  (A0)+,D0                        | DOUBLE: GET A BYTE FROM SRC
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        LSR.B   #4,D1                           | GET HI NIBBLE
        MOVE.B  QRTR2_CONT_2(PC,D1.W),(A1)+     | DOUBLE TO DST
        ANDI    #0xF,D0                         | GET LO NIBBLE
        MOVE.B  QRTR2_CONT_2(PC,D0.W),(A1)+     | DOUBLE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   QRTR2_LOOP_2                    | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| QRTR2_CONT_2 - indexed branch table for stretch 3/4 sampling
|
QRTR2_CONT_2:
  .byte 0x00,0x03,0x0C,0x0F,0x30,0x33           | DOUBLE: 4-BIT EXPAND TABLE LO
  .byte 0x3C,0x3F,0xC0,0xC3,0xCC,0xCF           | DOUBLE: 4-BIT EXPAND TABLE MID
  .byte 0xF0,0xF3,0xFC,0xFF                     | DOUBLE: 4-BIT EXPAND TABLE HI

| RTS ;ALL DONE

| .BYTE $30,$33,$3C,$3F
| .BYTE $C0,$C3,$CC,$CF
| .BYTE $F0,$F3,$FC,$FF

| -----------------------------------------------
|
| TRIPLE USING TABLE LOOKUP
|
TRIPLE:
        MOVE.B  (A0)+,D0                        | GET A BYTE FROM SRC
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        MOVE    D0,D2                           | MAKE A THIRD COPY
        LSR.B   #5,D2                           | GET 3 HI BITS
        MOVE.B  TRIPLE_CONT(PC,D2.W),(A1)+      | TRIPLE TO DST
        LSR.B   #2,D1                           | SHIFT DOWN
        ANDI    #0xF,D1                         | GET LO NIBBLE
        MOVE.B  TRIPLE_CONT_2(PC,D1.W),(A1)+    | TRIPLE TO DST
        ANDI    #0x7,D0                         | GET 3 LO BITS
        MOVE.B  TRIPLE_CONT_3(PC,D0.W),(A1)+    | TRIPLE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   TRIPLE                          | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| TRIPLE_CONT - indexed branch table for stretch half sampling
|
TRIPLE_CONT:
  .byte 0x00,0x03,0x1C,0x1F,0xE0,0xE3           | TRIPLE HI: 3-BIT EXPAND LO
  .byte 0xFC,0xFF                               | TRIPLE HI: 3-BIT EXPAND HI

TRIPLE_CONT_2:
  .byte 0x00,0x01,0x0E,0x0F,0x70,0x71           | TRIPLE MID: 4-BIT EXPAND LO
  .byte 0x7E,0x7F,0x80,0x81,0x8E,0x8F           | TRIPLE MID: 4-BIT EXPAND MID
  .byte 0xF0,0xF1,0xFE,0xFF                     | TRIPLE MID: 4-BIT EXPAND HI

TRIPLE_CONT_3:
  .byte 0x00,0x07,0x38,0x3F,0xC0,0xC7           | TRIPLE LO: 3-BIT EXPAND LO
  .byte 0xF8,0xFF                               | TRIPLE LO: 3-BIT EXPAND HI

| RTS ;ALL DONE
TRIPLE_LOOP:

| .BYTE $E0,$E3,$FC,$FF
| .BYTE $70,$71,$7E,$7F
| .BYTE $80,$81,$8E,$8F
| .BYTE $F0,$F1,$FE,$FF
| .BYTE $C0,$C7,$F8,$FF

| -----------------------------------------------
|
| QUADRUPLE USING TABLE LOOKUP
|
QUAD:
        MOVE.B  (A0)+,D0                        | GET A BYTE FROM SRC
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        ANDI    #0xF0,D1                        | MASK HI NIBBLE
        LSR     #3,D1                           | SHIFT FOR TABLE INDEX
        MOVE    QUAD_CONT(PC,D1.W),(A1)+        | QUADRUPLE TO DST
        ANDI    #0xF,D0                         | MASK LO NIBBLE
        ADD     D0,D0                           | DOUBLE FOR TABLE INDEX
        MOVE    QUAD_CONT(PC,D0.W),(A1)+        | QUADRUPLE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   TRIPLE_LOOP                     | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| QUAD_CONT - indexed branch table for stretch double expansion
|
QUAD_CONT:
  .byte 0x00,0x00,0x00,0x0F,0x00,0xF0           | QUAD: 4-BIT EXPAND WORDS 0-2
  .byte 0x00,0xFF,0x0F,0x00,0x0F,0x0F           | QUAD: 4-BIT EXPAND WORDS 3-5
  .byte 0x0F,0xF0,0x0F,0xFF,0xF0,0x00           | QUAD: 4-BIT EXPAND WORDS 6-8
  .byte 0xF0,0x0F,0xF0,0xF0,0xF0,0xFF           | QUAD: 4-BIT EXPAND WORDS 9-11
  .byte 0xFF,0x00,0xFF,0x0F,0xFF,0xF0           | QUAD: 4-BIT EXPAND WORDS 12-14
  .byte 0xFF,0xFF                               | QUAD: 4-BIT EXPAND WORD 15

QUAD_LOOP:
| RTS ;ALL DONE

| -----------------------------------------------
|
| STRETCH BY SIX USING TABLE LOOKUP
|
SIX:
        MOVE.B  (A0)+,D0                        | GET A BYTE FROM SRC
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        ANDI    #0xE0,D1                        | MASK HI 3 BITS
        LSR.B   #4,D1                           | SHIFT FOR TABLE INDEX
        MOVE    SIX_CONT(PC,D1.W),(A1)+         | SEXTUPLE TO DST
        MOVE    D0,D1                           | GET SRC BYTE AGAIN
        ANDI    #0x3C,D1                        | MASK MID 4 BITS
        LSR.B   #1,D1                           | SHIFT FOR TABLE INDEX
        MOVE    SIX_CONT_2(PC,D1.W),(A1)+       | SEXTUPLE TO DST
        MOVE    D0,D1                           | GET SRC BYTE AGAIN
        ANDI    #0x7,D1                         | MASK LO 3 BITS
        ADD     D1,D1                           | DOUBLE FOR TABLE INDEX
        MOVE    SIX_CONT_3(PC,D1.W),(A1)+       | SEXTUPLE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   QUAD_LOOP                       | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| SIX_CONT - indexed branch table for stretch triple expansion
|
SIX_CONT:
  .byte 0x00,0x00,0x00,0x0F,0x03,0xF0           | TRIPLE HI NIBBLE EXPAND LO
  .byte 0x03,0xFF,0xFC,0x00,0xFC,0x0F           | TRIPLE HI NIBBLE EXPAND MID
  .byte 0xFF,0xF0,0xFF,0xFF                     | TRIPLE HI NIBBLE EXPAND HI

SIX_CONT_2:
  .byte 0x00,0x00,0x00,0x03,0x00,0xFC           | TRIPLE MID: 4-BIT WORDS 0-2
  .byte 0x00,0xFF,0x3F,0x00,0x3F,0x03           | TRIPLE MID: 4-BIT WORDS 3-5
  .byte 0x3F,0xFC,0x3F,0xFF,0xC0,0x00           | TRIPLE MID: 4-BIT WORDS 6-8
  .byte 0xC0,0x03,0xC0,0xFC,0xC0,0xFF           | TRIPLE MID: 4-BIT WORDS 9-11
  .byte 0xFF,0x00,0xFF,0x03,0xFF,0xFC           | TRIPLE MID: 4-BIT WORDS 12-14
  .byte 0xFF,0xFF                               | TRIPLE MID: 4-BIT WORD 15

SIX_CONT_3:
  .byte 0x00,0x00,0x00,0x3F,0x0F,0xC0           | TRIPLE LO NIBBLE EXPAND LO
  .byte 0x0F,0xFF,0xF0,0x00,0xF0,0x3F           | TRIPLE LO NIBBLE EXPAND MID
  .byte 0xFF,0xC0,0xFF,0xFF                     | TRIPLE LO NIBBLE EXPAND HI

SIX_LOOP:
| RTS ;ALL DONE

| -----------------------------------------------
|
| SCALE UP BY EIGHT USING TABLE LOOKUP
|
EIGHT:
        MOVE.B  (A0)+,D0                        | GET A BYTE OF SRC
        MOVE    D0,D1                           | MAKE AN EXTRA COPY
        ANDI    #0xF0,D1                        | MASK HI NIBBLE
        LSR     #2,D1                           | SHIFT FOR TABLE INDEX
        MOVE.L  EIGHT_CONT(PC,D1.W),(A1)+       | OCTUPLE TO DST
        ANDI    #0xF,D0                         | MASK LO NIBBLE
        LSL     #2,D0                           | SHIFT FOR TABLE INDEX
        MOVE.L  EIGHT_CONT(PC,D0.W),(A1)+       | OCTUPLE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   SIX_LOOP                        | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| EIGHT_CONT - indexed branch table for stretch pixel replication
|
EIGHT_CONT:
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | OCTUPLE: 4-BIT LONGS 0-1
  .byte 0x00,0xFF,0x00,0x00,0xFF,0x00           | OCTUPLE: 4-BIT LONGS 1-2
  .byte 0x00,0x00,0xFF,0xFF,0x00,0xFF           | OCTUPLE: 4-BIT LONGS 3-4
  .byte 0x00,0x00,0x00,0xFF,0x00,0xFF           | OCTUPLE: 4-BIT LONGS 4-5
  .byte 0x00,0xFF,0xFF,0x00,0x00,0xFF           | OCTUPLE: 4-BIT LONGS 5-7
  .byte 0xFF,0xFF,0xFF,0x00,0x00,0x00           | OCTUPLE: 4-BIT LONGS 7-8
  .byte 0xFF,0x00,0x00,0xFF,0xFF,0x00           | OCTUPLE: 4-BIT LONGS 8-9
  .byte 0xFF,0x00,0xFF,0x00,0xFF,0xFF           | OCTUPLE: 4-BIT LONGS 10-11
  .byte 0xFF,0xFF,0x00,0x00,0xFF,0xFF           | OCTUPLE: 4-BIT LONGS 12-13
  .byte 0x00,0xFF,0xFF,0xFF,0xFF,0x00           | OCTUPLE: 4-BIT LONGS 13-14
  .byte 0xFF,0xFF,0xFF,0xFF                     | OCTUPLE: 4-BIT LONG 15

EIGHT_CONT_2:
| RTS ;ALL DONE

| -------------------------------------------------
|
| SCALE UP BY 16
|
SIXTEEN:
        MOVEQ   #-1,D1                          | GET SOME BLACK
        MOVE    #-0x8000,D0                     | INIT SRC MASK
SIXTENA:
        ADD     D0,D0                           | GET ONE BIT OF SRC
        BCC.B   WHITE16                         | BR IF WHITE
        BNE.B   BLACK16                         | BR IF BLACK
        MOVE    (A0)+,D0                        | ELSE GET NEXT SRC WORD
        ADDX    D0,D0                           | SHIFT SRC BIT OUT, 1 BIT IN
        BCS.B   BLACK16                         | BR IF BLACK
WHITE16:
        CLR.W   (A1)+                           | PUT A WORD OF WHITE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   SIXTENA                         | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| BLACK16
|
BLACK16:
        MOVE    D1,(A1)+                        | PUT A WORD OF BLACK TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        BCS.B   SIXTENA                         | LOOP UNTIL DSTLIMIT
        RTS                                     | ALL DONE

| ----------------------------------------------------------
|
| BLACK16_CONT
|
BLACK16_CONT:

| -----------------------------------------------
|
| SCALE UP BY ANY MULTIPLE OF 8 GREATER THAN 2
|
EIGHTS:
        LSR     #3,D4                           | DIVIDE SCALE FACTOR BY 8
        SUBQ.W  #0x1,D4                         | MINUS ONE FOR DBRA
        MOVE    #-0x8000,D0                     | INIT SRC MASK
EIGHTS1:
        ADD     D0,D0                           | GET ONE SRC BIT IN CARRY
        BNE.B   EIGHTS2                         | TIME FOR NEW SRC ?
        MOVE    (A0)+,D0                        | YES, GET NEXT SRC LONG
        ADDX    D0,D0                           | SHIFT SRC BIT OUT, 1 BIT IN
EIGHTS2:
        SCS     D1                              | SET OR CLR A BYTE
        MOVE    D4,D2                           | INIT LOOP COUNT
EIGHTS3:
        MOVE.B  D1,(A1)+                        | PUT ONE BYTE TO DST
        CMP.L   A2,A1                           | IS DSTPTR >= DSTLIMIT ?
        DBHI    D2,EIGHTS3                      | LOOP TILL SCALE OR DST FULL
        BLS.B   EIGHTS1                         | MORE SRC IF DST NOT FULL
        BRA.B   WHITE2_ERR                      | THEN QUIT

| ----------------------------------------------------------
|
| EIGHTS3_CONT
|
EIGHTS3_CONT:

| ------------------------------------------------------------------
|
| DO FULL RATIO SCALING, SHRINKING ONE BIT AT A TIME
|
| Called during boot.
SHRINK:
        CLR     D1                              | INIT DST WORD
        MOVE    #-0x8000,D0                     | INIT SRC MASK
        MOVE    D0,D2                           | INIT MASK
        MOVE    D4,D3                           | COPY RATIO
        LSR     #1,D3                           | INIT ERR TO RATIO/2
NXTSRC1:
        ADD     D0,D0                           | GET SRC BIT
        BCC.B   WHITE1                          | BRANCH IF WHITE
        BNE.B   NXTSRC1_CONT                    | BRANCH IF BLACK
        MOVE    (A0)+,D0                        | ELSE GET NEW SRC WORD
        ADDX    D0,D0                           | GET SRC BIT
        BCC.B   WHITE1                          | AND CONTINUE
NXTSRC1_CONT:
        OR      D2,D1                           | BLACK1: SET A BIT IN DST
WHITE1:
        ADD     D4,D3                           | TIME FOR NEXT DSTBIT ?
        BCC.B   NXTSRC1                         | NO, LOOP MORE SRC
        ROR     #1,D2                           | YES, ROTATE MASK
        BCC.B   NXTSRC1                         | LOOP IF DST WORD OK
        MOVE    D1,(A1)+                        | ELSE WRITE WORD TO DST
        CLR     D1                              | RESET DST WORD
        CMP.L   A2,A1                           | DSTPTR >= DSTLIMIT ?
        BCS.B   NXTSRC1                         | LOOP UNTIL DSTLIMIT
        RTS                                     | YES, QUIT

| ----------------------------------------------------------
|
| WHITE1_CONT
|
WHITE1_CONT:

| ------------------------------------------------------------------
|
| DO FULL RATIO SCALING, STRETCHING ONE BIT AT A TIME
|
        CLR     D1                              | STRETCH: INIT DST WORD
        MOVE    #-0x8000,D0                     | INIT SRC MASK
        MOVE    D0,D2                           | INIT MASK
        MOVE    D4,D3                           | COPY RATIO
        LSR     #1,D3                           | INIT ERR TO RATIO/2
NXTSRC2:
        ADD     D0,D0                           | GET SRC BIT
        BCC.B   WHITE2                          | BRANCH IF WHITE
        BNE.B   BLACKOK_CONT                    | BRANCH IF BLACK
        MOVE    (A0)+,D0                        | ELSE GET NEW SRC WORD
        ADDX    D0,D0                           | GET SRC BIT
        BCC.B   WHITE2                          | CONTINUE WITH WHITE
        BRA.B   BLACKOK_CONT                    | CONTINUE WITH BLACK

| ----------------------------------------------------------
|
| BLACKOK
|
BLACKOK:
        ADD     D4,D3                           | TIME FOR NEXT SRC BIT ?
        BCS.B   NXTSRC2                         | YES, LOOP FOR SRC
BLACKOK_CONT:
        OR      D2,D1                           | BLACK2: SET A BIT OF DST
        ROR     #1,D2                           | ROTATE MASK
        BCC.B   BLACKOK                         | LOOP IF DST WORD OK
        MOVE    D1,(A1)+                        | ELSE WRITE WORD TO DST
        CLR     D1                              | RESET DST WORD
        CMP.L   A2,A1                           | DSTPTR >= DSTLIMIT ?
        BCS.B   BLACKOK                         | LOOP UNTIL DSTLIMIT
        RTS                                     | YES, QUIT

| ----------------------------------------------------------
|
| WHITEOK
|
WHITEOK:
        ADD     D4,D3                           | TIME FOR NEXT SRC BIT ?
        BCS.B   NXTSRC2                         | YES, LOOP FOR SRC
WHITE2:
        ROR     #1,D2                           | ROTATE MASK
        BCC.B   WHITEOK                         | LOOP IF DST WORD OK
        MOVE    D1,(A1)+                        | ELSE WRITE WORD TO DST
        CLR     D1                              | RESET DST WORD
        CMP.L   A2,A1                           | DSTPTR >= DSTLIMIT ?
        BCS.B   WHITEOK                         | LOOP UNTIL DSTLIMIT
WHITE2_ERR:
        RTS                                     | DONE


