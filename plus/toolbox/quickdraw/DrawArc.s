| -----------------------------------------------------------
|
| --> DRAWARC.TEXT
|
| Routine to draw solid or hollow Ovals, RoundRects or Arcs.
|

| ------------------------------------------------------
|
| OFFSETS IN AN OVAL STATE RECORD:
|

| .PROC DrawArc,8
| .REF InitOval,BumpOval,SlopeFromAngle
| .REF RSect,ShieldCursor,ShowCursor,TrimRect
| .REF InitRgn,SeekRgn,PatExpand,ColorMap
| .REF XorSlab,DrawSlab,SlabMode,FastSlabMode,MaskTab
| ----------------------------------------------------------------
|
| PROCEDURE DrawArc(dstRect: Rect;
| hollow: BOOLEAN;
| ovalWidth,ovalHeight,mode: INTEGER;
| pat: Pattern;
| startAngle,arcAngle: INTEGER);
|
| Called during boot.
DrawArc:
        LINK    A6,#-0x142                      | ALLOCATE LOCAL VARS

| OVALTOP .EQU 0 ;INTEGER
| OVALBOT .EQU OVALTOP+2 ;INTEGER
| OVALY .EQU OVALBOT+2 ;INTEGER
| RSQYSQ .EQU OVALY+2 ;LONGINT
| SQUARE .EQU RSQYSQ+4 ;64 BIT LONGFIX
| ODDNUM .EQU SQUARE+8 ;64 BIT LONGFIX
| ODDBUMP .EQU ODDNUM+8 ;64 BIT LONGFIX
| LEFTEDGE .EQU ODDBUMP+8 ;32 BIT FIXED POINT
| RIGHTEDGE .EQU LEFTEDGE+4 ;32 BIT FIXED POINT
| ONEHALF .EQU RIGHTEDGE+4 ;32 BIT FIXED POINT
| OVALSIZE .EQU ONEHALF+4 ;SIZE OF AN OVALREC
| ------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
.set PARAMSIZE, 20                              | TOTAL SIZE OF PARAMETERS
.set DSTRECT, PARAMSIZE+8-4                     | ADDR OF RECT
.set HOLLOW, DSTRECT-2                          | BOOLEAN
.set OVALWIDTH, HOLLOW-2                        | INTEGER
.set OVALHEIGHT, OVALWIDTH-2                    | INTEGER
.set MODE, OVALHEIGHT-2                         | INTEGER
.set PAT, MODE-4                                | LONG, ADDR OF PATTERN
.set STARTANGLE, PAT-2                          | INTEGER
.set ARCANGLE, STARTANGLE-2                     | INTEGER

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
.set MODECASE, BUFSIZE-4                        | LONG
.set DSTLEFT, MODECASE-4                        | LONG
.set SAVEA5, DSTLEFT-4                          | LONG
.set PORT, SAVEA5-4                             | LONG
.set FASTFLAG, PORT-2                           | BYTE
.set TEMPRECT, FASTFLAG-8                       | RECT
.set INNEROVAL, TEMPRECT-OVALSIZE               | OVAL RECORD
.set OUTEROVAL, INNEROVAL-OVALSIZE              | OVAL RECORD
.set SKIPTOP, OUTEROVAL-2                       | WORD
.set SKIPBOT, SKIPTOP-2                         | WORD
.set ARCFLAG, SKIPBOT-1                         | BYTE FLAG
.set SKIPFLAG, ARCFLAG-1                        | BYTE FLAG
.set STOPANGLE, SKIPFLAG-2                      | INTEGER
.set MIDVERT, STOPANGLE-2                       | INTEGER
.set MIDHORIZ, MIDVERT-2                        | INTEGER
.set WIDTH, MIDHORIZ-2                          | INTEGER
.set HEIGHT, WIDTH-2                            | INTEGER
.set SLOPE1, HEIGHT-4                           | LONG, FIXED POINT
.set SLOPE2, SLOPE1-4                           | LONG, FIXED POINT
.set LINE1, SLOPE2-4                            | LONG, FIXED POINT
.set LINE2, LINE1-4                             | LONG, FIXED POINT
.set FLAG1, LINE2-2                             | WORD
.set FLAG2, FLAG1-2                             | WORD
.set OUTERLEFT, FLAG2-2                         | WORD
.set OUTERRIGHT, OUTERLEFT-2                    | WORD
.set INNERLEFT, OUTERRIGHT-2                    | WORD
.set INNERRIGHT, INNERLEFT-2                    | WORD
.set PATINDEX, INNERRIGHT-2                     | WORD
.set VARSIZE, PATINDEX                          | SIZE OF LOCAL VARIABLES

        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS
        MOVE.L  A7,-0x94(A6)                    | REMEMBER STACK FOR LATER
        MOVE.L  A5,-0xAA(A6)                    | REMEMBER GLOBAL PTR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A3                         | GET CURRENT GRAFPORT
        TST     PNVIS(A3)                       | IS PNVIS NEG ?
        BLT     DRAWARC_GOHOME                  | YES, QUIT
        MOVE.L  A3,-0xAE(A6)                    | SAVE CURRENT GRAFPORT

| -------------------------------------------------------
|
| QUIT IF MODE NOT IN 8..15
|
        MOVEQ   #-8,D0                          | MASK TO KILL BOTTOM 3 BITS
        AND     0x10(A6),D0                     | GET ALL BUT 3 BITS OF MODE
        CMPI    #0x8,D0                         | IS PEN MODE 8..15 ?
        BNE     DRAWARC_GOHOME                  | NO, QUIT

| ----------------------------------------------------------------
|
| ADJUST MODE AND PATTERN IF COLOR FILTERING.
|
        TST     COLRBIT(A3)                     | IS COLORBIT = 0 ?
        BMI.B   NOCOLOR                         | YES, DON'T MAP
        MOVE    0x10(A6),-(SP)                  | PUSH INPUT MODE
        MOVE.L  0xC(A6),-(SP)                   | PUSH ADDR OF INPUT PATTERN
        JSR     ColorMap(PC)                    | ALTER BY THECOLOR, THEFILTER
        MOVE.L  (SP)+,0xC(A6)                   | GET (ALTERED) PATTERN
        MOVE    (SP)+,0x10(A6)                  | GET (ALTERED) MODE
NOCOLOR:
        MOVE.L  A3,A5                           | PUT GRAFPORT IN A5

| ---------------------------------------------------------
|
| GET CLIPRGN AND VISRGN HANDLES AND DE-REFERENCE THEM
|
        MOVE.L  CLIPRGN(A5),A2                  | GET CLIPRGN HANDLE
        MOVE.L  (A2),A2                         | GET CLIPRGN POINTER
        MOVE.L  VISRGN(A5),A3                   | GET VISRGN HANDLE
        MOVE.L  (A3),A3                         | GET VISRGN POINTER

| -----------------------------------------------------------------------
|
| CALC MINRECT, THE INTERSECTION OF DSTRECT, BITMAP BOUNDS,
| CLIPRGN BBOX, AND VISRGN BBOX. QUIT IF NO INTERSECTION.
|
        MOVE.L  0x18(A6),-(SP)                  | PUSH DSTRECT
        PEA.L   0x8(A5)                         | PUSH BITMAP BOUNDS

| -----------------------------------------------------------------------
|
        PEA.L   RGNBBOX(A2)                     | PUSH CLIPRGN BBOX
        PEA.L   RGNBBOX(A3)                     | PUSH VISRGN BBOX
        MOVE    #4,-(SP)                        | PUSH NRECTS=4
        PEA.L   -0x48(A6)                       | PUSH DST ADDR
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ     DRAWARC_GOHOME                  | QUIT IF NO INTERSECT

|
| CHECK FOR BOTH VISRGN AND CLIPRGN RECTANGULAR
|
        CLR.B   -0xB0(A6)                       | FASTFLAG := FALSE
        CMPI    #0xA,(A2)                       | IS CLIPRGN RECTANGULAR ?

        BNE.B   YESFLAG_NO                      | NO, CONTINUE
        CMPI    #0xA,(A3)                       | IS VISRGN RECTANGULAR ?
        BEQ.B   CKPAT                           | YES, CONTINUE

|
| If only visRgn is non-rectangular, then check if
| its intersection with minrect would be rectangular.
| IF TrimRect(visRgn,minRect) then treat as rectangular.
|
        MOVE.L  VISRGN(A5),-(SP)                | push rgnHandle
        PEA.L   -0x48(A6)                       | push addr of minRect
        JSR     TrimRect(PC)                    | call trimRect
        BLT     DRAWARC_GOHOME                  | quit if intersection empty
        BGT.B   YESFLAG_NO                      | continue if non-rectangular

|
| CHECK FOR BLACK OR WHITE PATTERN
|
| Called during boot.
CKPAT:
        MOVE.L  0xC(A6),A0                      | POINT TO PATTERN

|
| CHECK FOR BLACK OR WHITE PATTERN
|
        MOVE.L  (A0)+,D0                        | GET 1ST HALF OF PATTERN
        CMP.L   (A0)+,D0                        | IS IT SAME AS 2ND HALF ?
        BNE.B   YESFLAG_NO                      | NO, CONTINUE
        NOT.L   D0                              | IS PATTERN BLACK ?
        BEQ.B   YESFLAG                         | YES, WE MADE IT
        NOT.L   D0                              | IS PATTERN WHITE ?
        BNE.B   YESFLAG_NO                      | NO, CONTINUE
        EORI    #0x4,0x10(A6)                   | YES, ALTER MODE AS IF BLACK
YESFLAG:
        ST.B    -0xB0(A6)                       | REMEMBER RECT CLIPPED AND BLACK

|
| fast case: map mode into black,xor,white, or do-nothing
|
        MOVEQ   #7,D0                           | GET 3 BIT MASK
        AND     0x10(A6),D0                     | GET 3 BITS OF MODE
        MOVE.B  YESFLAG_CONT(PC,D0.W),D0        | MAP TO BLACK,XOR,WHITE,NOP
        BMI     DRAWARC_GOHOME                  | QUIT IF DO-NOTHING MODE
        MOVE    D0,0x10(A6)                     | UPDATE MODE
        BRA.B   YESFLAG_NO                      | AND CONTINUE

| ----------------------------------------------------------
|
| YESFLAG_CONT - indexed branch table for DrawArc region scan modes
|
YESFLAG_CONT:
  .byte 0x00,0x00,0x01,0x02,0x02,0xFF           | BLACK,BLACK,XOR,WHITE,WHITE,NOP
  .byte 0xFF,0xFF                               | NOP,NOP

| FLAGOK
| Called during boot.
YESFLAG_NO:
        CLR.B   -0x11A(A6)                      | INIT TO NOT SKIPPING

| --------------------------------------------------
|
| ADJUST IF ARCANGLE NEGATIVE, QUIT IF ARC = 0
| NOTE WHETHER FULL CIRCLE OR ARC
|
        MOVE    0x8(A6),D0                      | GET ARC ANGLE

| FLAGOK

| --------------------------------------------------
|
        BEQ     DRAWARC_GOHOME                  | QUIT IF ARC ANGLE = 0
        BPL.B   POSANG                          | IS ANGLE NEG ?
        ADD     D0,0xA(A6)                      | YES, ADJUST START ANGLE
        NEG     D0                              | AND MAKE ARC ANGLE POSITIVE
        MOVE    D0,0x8(A6)                      | UPDATE INPUT PARAM
POSANG:
        CMPI    #0x168,D0                       | IS ARC ANGLE >= 360 ?
        SLT.B   -0x119(A6)                      | REMEMBER FOR LATER
        BGE     NOTARC                          | NO, SKIP SETUP

| ---------------------------------------------------------------
|
| IF ARCANGLE < 360 THEN SET UP ARC STUFF
|
| TREAT STARTANGLE MOD 360
|
        MOVE    0xA(A6),D0                      | GET STARTANGLE

| ---------------------------------------------------------------
|
        EXT.L   D0                              | SIGN EXTEND FOR DIVIDE
        DIVS    #360,D0                         | TREAT STARTANGLE MOD 360
        SWAP    D0                              | GET THE REMAINDER
        TST     D0                              | WAS IT NEGATIVE ?
        BPL.B   STARTOK                         | NO, CONTINUE
        ADDI    #0x168,D0                       | YES, ADD 360 TO MAKE POSITIVE
STARTOK:
        MOVE    D0,0xA(A6)                      | REPLACE INPUT PARAM
        ADD     0x8(A6),D0                      | CALC STOPANGLE
        CMPI    #0x168,D0                       | IS STOPANGLE >= 360 ?
        BLT.B   STOPOK                          | NO, CONTINUE
        SUBI    #0x168,D0                       | YES, WRAP AROUND MOD 360
STOPOK:
        MOVE    D0,-0x11C(A6)                   | SAVE STOPANGLE FOR LATER
        MOVE.L  0x18(A6),A0                     | POINT TO DSTRECT
        MOVE    (A0),D0                         | GET DSTTOP
        ADD     BOTTOM(A0),D0                   | ADD DSTBOTTOM
        ASR     #1,D0                           | DIVIDE BY 2
        MOVE    D0,-0x11E(A6)                   | MID VERT := (DSTBOT+DSTTOP)/2
        MOVE    LEFT(A0),D0                     | GET DSTLEFT
        ADD     RIGHT(A0),D0                    | ADD DSTRIGHT
        ASR     #1,D0                           | DIVIDE BY 2
        MOVE    D0,-0x120(A6)                   | MID HORIZ := (DSTLEFT+DSTRIGHT)/2
        MOVE    RIGHT(A0),D0                    | GET DSTRIGHT
        SUB     LEFT(A0),D0                     | SUBTRACT DSTLEFT
        MOVE    D0,-0x122(A6)                   | WIDTH := DSTRIGHT - DSTLEFT
        MOVE    BOTTOM(A0),D0                   | GET DSTBOTTOM
        SUB     (A0),D0                         | SUBTRACT DSTTOP
        MOVE    D0,-0x124(A6)                   | HEIGHT := DSTBOTTOM -DSTTOP
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    -0x122(A6),-(SP)                | PUSH WIDTH
        MOVE    -0x124(A6),-(SP)                | PUSH HEIGHT
        _FixRatio                               | CALC ASPECT RATIO
        MOVE.L  (SP)+,D7                        | SAVE RESULT IN D7

| --------------------------------------------
|
| CALC SLOPE1 FROM STARTANGLE
|
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    0xA(A6),-(SP)                   | PUSH STARTANG
        JSR     SlopeFromAngle(PC)              | CALC SLOPE1
        MOVE.L  (SP)+,D0                        | POP SLOPE1
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D0,-(SP)                        | PUSH SLOPE1
        MOVE.L  D7,-(SP)                        | PUSH ASPECT RATIO
        _FixMul                                 | scale slope1
        MOVE.L  (SP)+,-0x128(A6)                | SAVE RESULT FOR LATER

| --------------------------------------------
|
| CALC SLOPE2 FROM STOPANGLE
|
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    -0x11C(A6),-(SP)                | PUSH STOPANGLE
        JSR     SlopeFromAngle(PC)              | CALC SLOPE2
        MOVE.L  (SP)+,D0                        | POP SLOPE2
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D0,-(SP)                        | PUSH SLOPE
        MOVE.L  D7,-(SP)                        | PUSH ASPECT RATIO
        _FixMul                                 | SCALE SLOPE2
        MOVE.L  (SP)+,-0x12C(A6)                | SAVE RESULT FOR LATER

| ---------------------------------------------------------
|
| CALC HORIZ COORDS OF LINE1 AND LINE2 AT TOP OF DSTRECT
|
        MOVE    -0x120(A6),D6                   | GET MIDHORIZ

| ---------------------------------------------------------
|
        SWAP    D6                              | PUT MIDHORIZ IN HI WORD
        CLR.W   D6                              | CALC MIDHORIZ*64K
        MOVE    -0x124(A6),D7                   | GET HEIGHT
        LSR     #1,D7                           | CALC HEIGHT DIV 2
        MOVE    -0x126(A6),D0                   | GET SLOPE1 LO WORD
        MULU    D7,D0                           | CALC LO PARTIAL PRODUCT
        MOVE.L  D0,-0x130(A6)                   | ACCUMULATE IT
        MOVE    -0x128(A6),D0                   | GET SLOPE1 HI WORD
        MULS    D7,D0                           | CALC HI PARTIAL PRODUCT
        ADD     D0,-0x130(A6)                   | ADD HI PRODUCT TO ACCUMULATOR
        MOVE.L  D6,D0                           | COPY MIDHORIZ*64K
        SUB.L   -0x130(A6),D0                   | CALC MIDH*64K-SLOPE*(HT DIV 2)
        MOVE.L  D0,-0x130(A6)                   | STORE AS LINE1 HORIZ AT TOP
        MOVE    -0x12A(A6),D0                   | GET SLOPE2 LO WORD
        MULU    D7,D0                           | CALC LO PARTIAL PRODUCT
        MOVE.L  D0,-0x134(A6)                   | ACCUMULATE IT
        MOVE    -0x12C(A6),D0                   | GET SLOPE2 HI WORD
        MULS    D7,D0                           | CALC HI PARTIAL PRODUCT
        ADD     D0,-0x134(A6)                   | ADD HI PRODUCT TO ACCUMULATOR
        SUB.L   -0x134(A6),D6                   | CALC MIDH*64K-SLOPE*(HT DIV 2)
        MOVE.L  D6,-0x134(A6)                   | STORE AS LINE2 HORIZ AT TOP

| ----------------------------------------------------------
|
| SET UP FLAG1 AND FLAG2 TO TELL WHICH HALF EACH LINE IS ACTIVE IN:
| CODE IS: NEG = ACTIVE IN TOP, POS = ACTIVE IN BOTTOM, 0 = HORIZONTAL
|
        MOVE    0xA(A6),D0                      | GET STARTANGLE
        CMPI    #0xB4,D0                        | IS STARTANGLE >= 180 ?
        BGE.B   STOPOK_OK                       | YES, USE 270 BASE
        SUBI    #0x5A,D0                        | FLAG1 := STARTANGLE - 90
        BRA.B   STOPOK_CONT                     | CONTINUE

| ----------------------------------------------------------
|
| STOPOK_OK
|
STOPOK_OK:
        SUBI    #0x10E,D0                       | SUBTRACT 270

| ----------------------------------------------------------
|
| SET UP FLAG1 AND FLAG2 TO TELL WHICH HALF EACH LINE IS ACTIVE IN:
| CODE IS: NEG = ACTIVE IN TOP, POS = ACTIVE IN BOTTOM, 0 = HORIZONTAL
|
        NEG     D0                              | FLAG1 := 270-STARTANGLE
STOPOK_CONT:
        MOVE    D0,-0x136(A6)                   | SAVE FLAG1
        MOVE    -0x11C(A6),D0                   | GET STOPANGLE
        CMPI    #0xB4,D0                        | IS STOPANGLE >= 180 ?
        BGE.B   STOPOK_OK_2                     | YES, USE 270 BASE
        SUBI    #0x5A,D0                        | FLAG2 := STOPANGLE - 90
        BRA.B   STOPOK_CONT_2                   | CONTINUE

| ----------------------------------------------------------
|
| STOPOK_OK_2
|
STOPOK_OK_2:
        SUBI    #0x10E,D0                       | SUBTRACT 270
        NEG     D0                              | FLAG2 := 270-STOPANGLE
STOPOK_CONT_2:
        MOVE    D0,-0x138(A6)                   | SAVE FLAG2

|
| SET UP SKIPFLAG TO SKIP OVER UNUSED ARC PORTIONS
|
        MOVE    0x8(A6),D0                      | GET ARCANGLE
        CMPI    #0xB4,D0                        | IS ARCANGLE > 180 ?

        BGT.B   NOTARC                          | SKIP IF ANGLE > 180
        BLT.B   ACUTE                           | DEAL WITH ACUTE ANGLE
        CMPI    #0x5A,0xA(A6)                   | IS STARTANGLE = 90 ?
        SEQ.B   -0x11A(A6)                      | SO SKIP IF START=90
        BRA.B   NOTARC                          | CONTINUE TO OVAL INIT

| ----------------------------------------------------------
|
| ACUTE
|
ACUTE:
        MOVE    -0x136(A6),D0                   | GET FLAG1
        OR      -0x138(A6),D0                   | OR WITH FLAG2
        SPL.B   -0x11A(A6)                      | SKIP:=FLAG1 AND FLAG2 BOTH >= 0

| OBTUSE

| NOTARC

| ---------------------------------------------------------------
|
| INIT OUTER OVAL STATE RECORD
|
| Called during boot.
NOTARC:
        MOVE.L  0x18(A6),A0                     | POINT TO DSTRECT
        LEA.L   -0x114(A6),A1                   | POINT TO OUTER OVAL RECORD
        MOVE    0x12(A6),D1                     | GET OVALHEIGHT
        MOVE    0x14(A6),D2                     | GET OVALWIDTH

| OBTUSE

| NOTARC

| ---------------------------------------------------------------
|
| INIT OUTER OVAL STATE RECORD
|
        JSR     InitOval(PC)                    | INITIALIZE OUTER OVAL RECORD
        MOVE    0x12(A6),D0                     | GET OVALHEIGHT
        ASR     #1,D0                           | CALC OVAL HEIGHT DIV 2
        ADD     -0x114(A6),D0                   | ADD OUTER OVAL TOP
        MOVE    D0,-0x116(A6)                   | SAVE SKIPTOP
        MOVE.L  0x18(A6),A0                     | POINT TO DSTRECT
        ADD     BOTTOM(A0),D0                   | ADD BOTTOM
        SUB     (A0),D0                         | SUBTRACT TOP
        SUB     0x12(A6),D0                     | SUBTRACT OVALHEIGHT
        MOVE    D0,-0x118(A6)                   | SAVE SKIPBOT
        MOVE    #0x7FFF,-0xE6(A6)               | INIT INNER OVAL TOP TO MAX

| ---------------------------------------------------
|
| IF THIS IS A HOLLOW OVAL, THEN CALC DSTRECT INSET BY PENSIZE,
| AND INIT INNEROVAL. (IF INNEROVAL EMPTY, SWITCH TO SOLID).
|
        TST.B   0x16(A6)                        | IS HOLLOWFLAG TRUE ?

| ---------------------------------------------------
|
        BEQ.B   SOLID                           | NO, SKIP INNER OVAL
        MOVE.L  0x18(A6),A0                     | POINT TO DSTRECT
        MOVEM   (A0),D0-D3                      | GET TOP,LEFT,BOTTOM,RIGHT
        MOVE.L  PNSIZE(A5),D4                   | GET THEPORT^.PNSIZE
        ADD     D4,D1                           | LEFT := DSTLEFT + PENWIDTH
        SUB     D4,D3                           | RIGHT := DSTRIGHT - PENWIDTH
        CMP     D3,D1                           | IS LEFT >= TOP ?
        BGE.B   SOLID                           | YES, EMPTY RECT
        SWAP    D4                              | GET PNSIZE.V
        ADD     D4,D0                           | TOP := DSTTOP + PENHEIGHT
        SUB     D4,D2                           | BOTTOM := DSTBOTTOM - PENHEIGHT
        CMP     D2,D0                           | IS TOP >= BOTTOM ?
        BGE.B   SOLID                           | YES, EMPTY RECT
        MOVEM   D0-D3,-0xB8(A6)                 | SAVE INSET RECT IN TEMPRECT
        LEA.L   -0xB8(A6),A0                    | POINT TO DSTRECT INSET BY PENSIZE
        LEA.L   -0xE6(A6),A1                    | POINT TO INNER OVAL RECORD
        MOVE    0x12(A6),D1                     | GET OUTER OVALHEIGHT
        SUB     D4,D1                           | INNER HEIGHT:=OUTER-2*PENHEIGHT
        SUB     D4,D1                           | SUBTRACT 2ND PENHEIGHT
        MOVE    0x14(A6),D2                     | GET OUTER OVALWIDTH
        SWAP    D4                              | GET PEN WIDTH
        SUB     D4,D2                           | INNER WIDTH:=OUTER-2*PENWIDTH
        SUB     D4,D2                           | SUBTRACT 2ND PENWIDTH
        JSR     InitOval(PC)                    | INITIALIZE INNER OVAL RECORD

| SOLID

| ----------------------------------------------------------------
|
| HIDE CURSOR IF CURSOR INTERSECTS MINRECT.
|
| Called during boot.
SOLID:
        PEA.L   -0x48(A6)                       | PUSH SHIELDRECT PARAMETER
        MOVE.L  0x8(A5),-(SP)                   | PUSH PORTBITS.BOUNDS.TOPLEFT
        MOVE.L  -0xAA(A6),A5                    | GET GLOBAL PTR

| SOLID

| ----------------------------------------------------------------
|
| HIDE CURSOR IF CURSOR INTERSECTS MINRECT.
|
        JSR     ShieldCursor(PC)                | HIDE CURSOR IF IT INTERSECTS
        MOVE.L  -0xAE(A6),A5                    | RESTORE GRAFPORT IN A5
        MOVE    -0x46(A6),D2                    | GET MINRECT LEFT
        SUB     0xA(A5),D2                      | SUBTRACT PORTBITS.BOUNDS.LEFT
        ANDI    #-0x10,D2                       | ROUND DOWN TO MULT OF 16
        ADD     0xA(A5),D2                      | ADD BACK BOUNDS.LEFT

| ------------------------------------
|
| CALC BUFLEFT
|
        MOVE    D2,-0x9C(A6)                    | SAVE AS BUFLEFT

|
| IF FASTFLAG, THEN SKIP REGION SETUP
|
        TST.B   -0xB0(A6)                       | RECT CLIPPED AND BLACK ?

| ------------------------------------
|
        BNE     CLRMASK_SKIP                    | YES, DON'T WASTE TIME WITH SETUP
        MOVE    -0x42(A6),D0                    | GET MINRECT RIGHT

|
| CALC BUFSIZE
|
        SUB     D2,D0                           | CALC MAXH-BUFLEFT
        LSR     #5,D0                           | DIV BY 32 FOR LONGS
        MOVE    D0,-0x9E(A6)                    | BUFSIZE = # LONGS - 1

| -------------------------------------------------------------------------
|
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK
|
| Called during boot.
CLRMASK:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR ONE LONG
        DBF     D0,CLRMASK                      | LOOP TILL DONE
        MOVE.L  A7,-0x9A(A6)                    | REMEMBER WHERE MASKBUF IS

| -------------------------------------------------------------------------
|
| INIT STATE RECORDS AND ALLOCATE BUFFERS FOR EACH NON-RECTANGULAR REGION
|
        CLR     D5                              | INIT BOTH ARE RECT
        MOVE    #-0x7FFF,-0x52(A6)              | STATEA NEXTV := -32767
        MOVE    #0x7FFF,-0x50(A6)               | STATEA ENDV := 32767
        CMPI    #0xA,(A2)                       | IS CLIPRGN RECTANGULAR ?
        BEQ.B   CLRMASK_OK                      | YES, CONTINUE
        ADDQ.W  #0x2,D5                         | FLAG CLIPRGN NON-RECT
        MOVE.L  A2,A0                           | POINT TO CLIPRGN
        LEA.L   -0x60(A6),A1                    | POINT TO STATE RECORD A
        BSR.B   CLRMASK_CONT                    | INIT STATE, ALLOC BUFFER
CLRMASK_OK:
        MOVE    #-0x7FFF,-0x6A(A6)              | STATEB NEXTV := -32767
        MOVE    #0x7FFF,-0x68(A6)               | STATEB ENDV := 32767
        CMPI    #0xA,(A3)                       | IS VISRGN RECTANGULAR ?

| ARECT
        BEQ.B   CLRMASK_EXIT                    | YES, CONTINUE
        ADDQ.W  #0x4,D5                         | FLAG VISRGN NON-RECT
        MOVE.L  A3,A0                           | POINT TO VISRGN
        LEA.L   -0x78(A6),A1                    | POINT TO STATE RECORD B
        PEA.L   CLRMASK_EXIT(PC)                | PUSH FAKE RETURN ADDR
| CLRMASK_CONT -- iNIT STATE, ALLOC BUFFER.
CLRMASK_CONT:
        MOVE    -0x46(A6),D0                    | GET MINRECT LEFT
        MOVE    -0x42(A6),D1                    | GET MINRECT RIGHT
        MOVE    -0x9C(A6),D2                    | GET BUFLEFT
        JMP     InitRgn(PC)                     | INIT STATE, ALLOC BUFFER

| ----------------------------------------------------------
|
| CLRMASK_EXIT
|
| Called during boot.
CLRMASK_EXIT:
        MOVE    D5,-0x96(A6)                    | SAVE RECTFLAG

| BRECT

| --------------------------------------------------------------------
|
| IF BOTH REGIONS ARE RECTANGULAR, THEN DRAW MINRECT INTO MASK BUFFER
|
        BNE.B   CLRMASK_SKIP                    | NO, CONTNUE
        MOVE.L  -0x9A(A6),A0                    | YES, POINT TO MASK BUFFER
        MOVE    -0x46(A6),D3                    | GET MINRECT LEFT
        SUB     -0x9C(A6),D3                    | MAKE IT BUFFER RELATIVE
        MOVE    -0x42(A6),D4                    | GET MINRECT RIGHT
        SUB     -0x9C(A6),D4                    | MAKE IT BUFFER RELATIVE
        JSR     XorSlab(PC)                     | AND XOR BETWEEN THEM
CLRMASK_SKIP:
        MOVE    -0x48(A6),D1                    | GET MINRECT TOP
        SUB     0x8(A5),D1                      | SUBTRACT BOUNDS.TOP
        MULU    0x6(A5),D1                      | MULT BY ROWBYTES
        ADD.L   0x2(A5),D1                      | ADD BASEADDR
        SUB     0xA(A5),D2                      | SUBTRACT BOUNDS.LEFT

| NOTRECT

| SKIPSETUP

| ------------------------------------
|
| CALC STARTING DSTLEFT
|
        LSR     #3,D2                           | CALC BUFLEFT DIV 8
        EXT.L   D2                              | CLR HI WORD
        ADD.L   D2,D1                           | ADD HORIZ BYTE OFFSET
        MOVE.L  D1,-0xA6(A6)                    | SAVE AS DSTLEFT

| ----------------------------------------------------
|
| MAKE ALL HORIZONTAL COORDINATES RELATIVE TO BUFFER
|
        MOVE    -0x9C(A6),D1                    | GET BUFLEFT
        SUB     D1,-0x46(A6)                    | MINRECT.LEFT -= BUFLEFT
        SUB     D1,-0x42(A6)                    | MINRECT.RIGHT -= BUFLEFT
        SUB     D1,-0xF2(A6)                    | OUTER LEFTEDGE -= BUFLEFT
        SUB     D1,-0xEE(A6)                    | OUTER RIGHTEDGE -= BUFLEFT
        SUB     D1,-0xC4(A6)                    | INNER LEFTEDGE -= BUFLEFT
        SUB     D1,-0xC0(A6)                    | INNER RIGHTEDGE -= BUFLEFT
        SUB     D1,-0x130(A6)                   | LINE1 -= BUFLEFT
        SUB     D1,-0x134(A6)                   | LINE2 -= BUFLEFT

| ---------------------------------------------------
|
| SET UP CASE JUMP BASED ON MODE AND FASTFLAG
|
        MOVE    0x10(A6),D2                     | GET (ALTERED) PEN MODE
        TST.B   -0xB0(A6)                       | Rect clipoped and black ?
        BEQ.B   CLRMASK_NO                      | NO, USE NORMAL SLAB MODE

| ----------------------------------------------------
|

| ---------------------------------------------------
|
        JSR     FastSlabMode(PC)                | yes, get fast modeCase in A4
        MOVE.L  A4,-0xA2(A6)                    | SAVE FOR LATER
        CLR     -0x142(A6)                      | MAKE UNUSED PATINDEX EVEN
        BRA     GOFORIT                         | SKIP PATTERN STUFF

| ----------------------------------------------------------
|
| CLRMASK_NO
|
| Called during boot.
CLRMASK_NO:
        JSR     SlabMode(PC)                    | GET NORMAL MODECASE IN A4
        MOVE.L  A4,-0xA2(A6)                    | SAVE FOR LATER

| ------------------------------------------------------------------
|
| EXPAND 8 BYTE PATTERN TO 16 LONGS AND INIT PATTERN SELECTOR
|
        CLR.L   D7                              | SAY NOT INVERTED
        MOVE    0x10(A6),D2                     | GET MODE
        BCLR    #2,D2                           | TEST AND CLR INVERT BIT
        BEQ.B   CLRMASK_SKIP_2                  | SKIP IF NOT INVERTED
        NOT.L   D7                              | INVERTED; D7 GETS ALL 1'S
CLRMASK_SKIP_2:
        MOVE    0xA(A5),D2                      | GET PORTBITS.BOUNDS.LEFT
        MOVE.L  0xC(A6),A0                      | POINT TO BYTE WIDE PATTERN
        LEA.L   -0x40(A6),A1                    | POINT TO EXPANDED PATTERN
        MOVE.L  -0xAA(A6),A5                    | GET GLOBAL PTR
        JSR     PatExpand(PC)                   | EXPAND 8 BYTE PATTERN TO 16 LONGS
        MOVE.L  -0xAE(A6),A5                    | RESTORE GRAFPORT IN A5
        MOVEQ.L #0xF,D0                         | TREAT COORD MOD 16
        AND     -0x48(A6),D0                    | MINRECT.TOP MOD 16
        LSL     #2,D0                           | QUAD FOR 4 BYTE PATTERNS
        MOVE    D0,-0x142(A6)                   | SET UP PATTERN INDEX
GOFORIT:
        MOVE    -0x114(A6),D7                   | GET OUTER OVAL TOP AS VERT

| ------------------------------------------------------------
|
| BUMP OVAL STATE RECORDS UNLESS VERT IS BETWEEN SKIPTOP AND SKIPBOT
|
| Called during boot.
DRAWARC_NEXTROW:
        CMP     -0x116(A6),D7                   | IS VERT < SKIPTOP ?

| ------------------------------------------------------------
|
| BUMP OVAL STATE RECORDS UNLESS VERT IS BETWEEN SKIPTOP AND SKIPBOT
|
        BLT.B   YESBUMP                         | YES, OK TO BUMP OVALS
        CMP     -0x118(A6),D7                   | IS VERT >= SKIPBOT ?
        BLT.B   NOBUMP                          | NO, SKIP BUMPING
YESBUMP:
        MOVE    D7,-(SP)                        | STASH CURRENT VERT
        MOVE    D7,D0                           | COPY CURRENT VERTICAL
        LEA.L   -0x114(A6),A3                   | POINT TO OUTER OVAL STATE RECORD
        JSR     BumpOval(PC)                    | BUMP IT TO NEXT SCANLINE
        MOVE    (SP),D0                         | COPY CURRENT VERT
        LEA.L   -0xE6(A6),A3                    | POINT TO INNER OVAL STATE RECORD
        JSR     BumpOval(PC)                    | BUMP IT TO NEXT SCANLINE
        MOVE    (SP)+,D7                        | RECOVER SAVED CURRENT VERT

| --------------------------------------------------
|
| ADJUST ARC STUFF AS WE CROSS THE MIDDLE VERTICALLY
|
| Called during boot.
NOBUMP:
        CMP     -0x11E(A6),D7                   | IS CURRENT VERT = MIDVERT ?

| --------------------------------------------------
|
| ADJUST ARC STUFF AS WE CROSS THE MIDDLE VERTICALLY
|
        BNE.B   ACUTE1_SKIP_2                   | NO, CONTINUE
        TST.B   -0x119(A6)                      | ARE WE DOING AN ARC ?
        BEQ.B   ACUTE1_SKIP_2                   | NO, SKIP
        NEG     -0x136(A6)                      | YES, INVERT FLAGS AS WE CROSS
        NEG     -0x138(A6)                      | INVERT FLAG2

|
| RE-CALCULATE SKIPFLAG, AND QUIT IF IT BECOMES TRUE
|
        CLR.B   -0x11A(A6)                      | RESET SKIPFLAG
        MOVE    0x8(A6),D0                      | GET ARCANGLE
        CMPI    #0xB4,D0                        | IS ARCANGLE > 180 ?

        BGT.B   ACUTE1_SKIP                     | SKIP IF ANGLE > 180
        BLT.B   ACUTE1                          | DEAL WITH ACUTE ANGLE
        CMPI    #0x10E,0xA(A6)                  | IS STARTANGLE = 270 ?
        BNE.B   ACUTE1_SKIP                     | NO, CONTINUE
        BRA     DRAWARC_DONE                    | YES, WE'RE ALL DONE

| ----------------------------------------------------------
|
| ACUTE1
|
ACUTE1:
        MOVE    -0x136(A6),D0                   | GET FLAG1
        OR      -0x138(A6),D0                   | OR WITH FLAG2
        BPL     DRAWARC_DONE                    | QUIT IF BOTH FLAG1 AND FLAG2>=0

| OBTUSE1

|
| NOW SWAP THE ROLES OF LINE1 AND LINE2 AS THEY CROSS THE MIDDLE
|
ACUTE1_SKIP:
        MOVE    -0x136(A6),D0                   | SWAP FLAG1 AND FLAG2
        MOVE    -0x138(A6),-0x136(A6)           | FLAG1 := OLD FLAG2
        MOVE    D0,-0x138(A6)                   | FLAG2 := OLD FLAG1
        MOVE.L  -0x130(A6),D0                   | SWAP LINE1 AND LINE2
        MOVE.L  -0x134(A6),-0x130(A6)           | LINE1 := OLD LINE2
        MOVE.L  D0,-0x134(A6)                   | LINE2 := OLD LINE1
        MOVE.L  -0x128(A6),D0                   | SWAP SLOPE1 AND SLOPE2
        MOVE.L  -0x12C(A6),-0x128(A6)           | SLOPE1 := OLD SLOPE2
        MOVE.L  D0,-0x12C(A6)                   | SLOPE2 := OLD SLOPE1
ACUTE1_SKIP_2:
        CMP     -0x48(A6),D7                    | IS VERT < MINRECT.TOP ?

| OBTUSE1

|
| NOW SWAP THE ROLES OF LINE1 AND LINE2 AS THEY CROSS THE MIDDLE
|
        BLT     NODRAW                          | YES, DON'T DRAW
        TST.B   -0x11A(A6)                      | ARE WE SKIPPING ?
        BNE     DOSLAB_SKIP                     | YES, SKIP

| ------------------------------------------------
|
| SEEK MASK TO THE CURRENT VERTICAL, AND
| BRANCH BASED ON SOLID OR HOLLOW OVAL OR ARC.
|
        TST.B   -0xB0(A6)                       | RECT CLIPPED AND BLACK ?

| ------------------------------------------------
|
        BNE.B   NOMASK                          | YES, DON'T BOTHER WITH MASK
        BSR     DRAWARC_GOHOME_CONT             | MAKE MASKBUF CURRENT
NOMASK:
        TST.B   -0x119(A6)                      | ARE WE DOING AN ARC ?
        BNE.B   NOMASK_OK                       | YES, GO TO IT
        CMP     -0xE6(A6),D7                    | IS VERT < INNER OVAL TOP ?
        BLT     SOVAL                           | NO, TREAT AS SOLID OVAL
        CMP     -0xE4(A6),D7                    | IS VERT >= INNER OVAL BOT ?
        BGE     SOVAL                           | NO, TREAT AS SOLID OVAL
        BRA     HOVAL                           | YES, PROCESS HOLLOW OVAL

| ----------------------------------------------------------
|
| NOMASK_OK
|
NOMASK_OK:
        MOVE    -0xF2(A6),D1                    | D1 := OUTER LEFTEDGE

| ----------------------------------------------
|
| SOLID OR HOLLOW ARC: CALC OUTERLEFT AND OUTERRIGHT
|
        TST     -0x136(A6)                      | IS LINE1 ACTIVE ?
        BPL.B   NOMASK_SKIP                     | NO, SKIP LINE1 CLIP
        CMP     -0x130(A6),D1                   | IS LEFTEDGE < LINE1 ?
        BGE.B   NOMASK_SKIP                     | NO, KEEP LEFTEDGE
        MOVE    -0x130(A6),D1                   | YES, CLIP TO LINE1
NOMASK_SKIP:
        MOVE    D1,-0x13A(A6)                   | SAVE OUTERLEFT
        MOVE    -0xEE(A6),D2                    | D2 := OUTER RIGHTEDGE
        TST     -0x138(A6)                      | IS LINE2 ACTIVE ?
        BPL.B   NOMASK_SKIP_2                   | NO, SKIP LINE2 CLIP
        CMP     -0x134(A6),D2                   | IS RIGHTEDGE > LINE2 ?
        BLE.B   NOMASK_SKIP_2                   | NO, KEEP RIGHTEDGE
        MOVE    -0x134(A6),D2                   | YES, CLIP TO LINE2
NOMASK_SKIP_2:
        MOVE    D2,-0x13C(A6)                   | SAVE OUTERRIGHT
        CMP     -0xE6(A6),D7                    | IS VERT < INNER OVAL TOP ?

| ----------------------------------------------
|
| SOLID OR HOLLOW ARC: CALC OUTERLEFT AND OUTERRIGHT
|
        BLT     SARC                            | NO, PROCESS SOLID ARC
        CMP     -0xE4(A6),D7                    | IS VERT >= INNER OVAL BOT ?
        BGE     SARC                            | NO, PROCESS SOLID ARC
        MOVE    -0xC4(A6),D0                    | GET INNER LEFTEDGE

| --------------------------------------------------
|
| HOLLOW ARC: CALC INNERLEFT AND INNERRIGHT
|
        TST     -0x138(A6)                      | IS LINE2 ACTIVE ?
        BPL.B   NOMASK_SKIP_3                   | NO, SKIP LINE2 CLIP
        CMP     -0x134(A6),D0                   | IS LEFTEDGE > LINE2 ?
        BLE.B   NOMASK_SKIP_3                   | NO, KEEP LEFTEDGE
        MOVE    -0x134(A6),D0                   | YES, CLIP TO LINE2
NOMASK_SKIP_3:
        MOVE    D0,-0x13E(A6)                   | SAVE INNERLEFT
        MOVE    -0xC0(A6),D0                    | GET INNER RIGHTEDGE
        TST     -0x136(A6)                      | IS LINE1 ACTIVE ?
        BPL.B   NOMASK_SKIP_4                   | NO, SKIP LINE1 CLIP
        CMP     -0x130(A6),D0                   | IS RIGHTEDGE < LINE1 ?
        BGE.B   NOMASK_SKIP_4                   | NO, KEEP RIGHTEDGE
        MOVE    -0x130(A6),D0                   | YES, CLIP TO LINE1
NOMASK_SKIP_4:
        MOVE    D0,-0x140(A6)                   | SAVE INNERRIGHT

| --------------------------------------------------
|
| IF OUTERLEFT < OUTERRIGHT THEN PAINT TWO SLABS
|

| HOLLOW ARC: CALC INNERLEFT AND INNERRIGHT
        CMP     D2,D1                           | IS OUTERLEFT < OUTERRIGHT ?
        BGE.B   NOMASK_NO                       | NO, TRY OBTUSE CASE
        MOVE    -0x13E(A6),D2                   | D2 := INNERLEFT
        BSR.B   ONESLAB                         | DRAW LEFT SLAB
        MOVE    -0x140(A6),D1                   | D1 := INNERRIGHT
        MOVE    -0x13C(A6),D2                   | D2 := OUTERRIGHT
        BRA     DOSLAB                          | DRAW RIGHT SLAB

|
| ELSE IF BOTH LINES ACTIVE AND ANGLE > 180 THEN PAINT TWO OR THREE SLABS
|
NOMASK_NO:
        MOVE    -0x136(A6),D0                   | GET FLAG1
        AND     -0x138(A6),D0                   | ARE BOTH LINES ACTIVE ?

|
| ELSE IF BOTH LINES ACTIVE AND ANGLE > 180 THEN PAINT TWO OR THREE SLABS
|
        BPL     DOSLAB_SKIP                     | NO, CONTINUE
        CMPI    #0xB4,0x8(A6)                   | IS ARCANGLE > 180 ?
        BLE     DOSLAB_SKIP                     | NO, CONTINUE
        CMP     -0x13E(A6),D2                   | IS INNERLEFT=OUTERRIGHT?
        BNE.B   NOMASK_NO_2                     | NO, CONTINUE
        MOVE    -0xC4(A6),D2                    | USE INNER LEFTEDGE INSTEAD
        BRA.B   NOMASK_CONT                     | DRAW MERGED SLAB

| ----------------------------------------------------------
|
| NOMASK_NO_2
|
NOMASK_NO_2:
        MOVE    -0x13A(A6),D0                   | GET OUTERLEFT
        CMP     -0x140(A6),D0                   | IS INNERRIGHT=OUTERLEFT ?
        BNE.B   NOMASK_NO_3                     | NO, CONTINUE
        MOVE    -0xC0(A6),D1                    | USE INNER RIGHTEDGE INSTEAD
        MOVE    -0x13C(A6),D2                   | D2 := OUTERRIGHT

| NOT3
NOMASK_CONT:
        BSR.B   ONESLAB                         | DRAW MERGED SLAB
NOMASK_NO_3:
        MOVE    -0xF2(A6),D1                    | D1 := OUTER LEFTEDGE

| NOT3
        MOVE    -0x13E(A6),D2                   | D2 := INNERLEFT
        BSR.B   ONESLAB                         | DRAW LEFT SLAB
        MOVE    -0x140(A6),D1                   | D1 := INNERRIGHT
        MOVE    -0xEE(A6),D2                    | D2 := OUTER RIGHTEDGE
        BRA.B   DOSLAB                          | DRAW RIGHT SLAB

| ---------------------------------------------------------
|
| LOCAL PROCEDURE TO SET UP AND DRAW ONE SLAB
|
| Called during boot (1,086 times in 30s trace).
ONESLAB:
        MOVEQ.L #0x3F,D6                        | GET WRAP-AROUND MASK
        AND     -0x142(A6),D6                   | GET PATINDEX MOD 64
        MOVE.L  -0x40(A6,D6.W),D6               | GET EXPANDED PATTERN LONG

| ---------------------------------------------------------
|
        LEA.L   DT_mMaskTab(PC),A0              | POINT TO MASK TABLE
        MOVE.L  -0xA6(A6),A1                    | INIT DSTPTR TO LEFT
        MOVE.L  -0x9A(A6),A2                    | INIT MASKPTR TO LEFT
        LEA.L   -0x48(A6),A3                    | POINT TO MINRECT
        MOVE.L  -0xA2(A6),A4                    | GET MODE CASE JUMP
        JMP     DrawSlab(PC)                    | DRAW ONE HORIZONTAL SLAB

| ----------------------------------------------------
|
| SOLID ARC: IF OUTERLEFT < OUTERRIGHT THEN PAINT ONE SLAB
|
SARC:
        CMP     D2,D1                           | IS OUTERLEFT < OUTERRIGHT ?
        BLT.B   DOSLAB                          | YES, DO ONE SLAB BETWEEN THEM

|
| ELSE IF BOTH LINES ACTIVE AND ANGLE > 180 THEN PAINT TWO SLABS
|
        MOVE    -0x136(A6),D0                   | GET FLAG1
        AND     -0x138(A6),D0                   | ARE BOTH LINES ACTIVE ?

        BPL.B   DOSLAB_SKIP                     | NO, CONTINUE
        CMPI    #0xB4,0x8(A6)                   | IS ARCANGLE > 180 ?
        BLE.B   DOSLAB_SKIP                     | NO, CONTINUE
        MOVE    -0xF2(A6),D1                    | D1 := OUTER LEFTEDGE
        BSR.B   ONESLAB                         | DRAW LEFT SLAB
        MOVE    -0x13A(A6),D1                   | D1 := OUTERLEFT (LINE1 CLIPPED)
        MOVE    -0xEE(A6),D2                    | D2 := OUTER RIGHTEDGE
        BRA.B   DOSLAB                          | DRAW RIGHT SLAB

| ----------------------------------------------------------
|
| HOVAL
|
| Called during boot.
HOVAL:
        MOVE    -0xF2(A6),D1                    | D1 := OUTER LEFTEDGE
        MOVE    -0xC4(A6),D2                    | D2 := INNER LEFTEDGE

| --------------------------------------------------
|
| HOLLOW OVAL: DRAW TWO SLABS BETWEEN OUTER AND INNER OVALS
|
        BSR.B   ONESLAB                         | DRAW HORIZ SLAB BETWEEN THEM
        MOVE    -0xC0(A6),D1                    | D1 := INNER RIGHTEDGE
        MOVE    -0xEE(A6),D2                    | D2 := OUTER RIGHTEDGE
        BSR.B   ONESLAB                         | DRAW HORIZ SLAB BETWEEN THEM
        BRA.B   DOSLAB_SKIP                     | SKIP TO NEXT ROW

| ----------------------------------------------------------
|
| SOVAL
|
| Called during boot.
SOVAL:
        MOVE    -0xF2(A6),D1                    | D1 := OUTER LEFTEDGE
        MOVE    -0xEE(A6),D2                    | D2 := OUTER RIGHTEDGE

| ----------------------------------------------------
|
| SOLID OVAL: DRAW ONE SLAB BETWEEN LEFT AND RIGHT EDGES OF OUTER OVAL
|
| Called during boot.
DOSLAB:
        BSR.B   ONESLAB                         | DRAW HORIZ SLAB BETWEEN THEM
DOSLAB_SKIP:
        ADDQ.W  #0x4,-0x142(A6)                 | BUMP PATINDEX BY 4
        MOVE    0x6(A5),D0                      | GET ROWBYTES

| -------------------------------------------------------------------
|
| BUMP DESTINATION VERTICALLY AND LOOP FOR ALL SCAN LINES
|
        EXT.L   D0                              | MAKE IT LONG
        ADD.L   D0,-0xA6(A6)                    | BUMP DST TO NEXT ROW
NODRAW:
        MOVE.L  -0x128(A6),D0                   | BUMP LINE1 AND LINE2
        ADD.L   D0,-0x130(A6)                   | BUMP LINE1 BY SLOPE1
        MOVE.L  -0x12C(A6),D0                   | GET SLOPE2
        ADD.L   D0,-0x134(A6)                   | BUMP LINE2 BY SLOPE2
        ADDQ.W  #0x1,D7                         | BUMP VERT TO NEXT SCANLINE
        CMP     -0x44(A6),D7                    | IS VERT < MINRECT.BOTTOM ?
        BLT     DRAWARC_NEXTROW                 | NO, LOOP FOR MORE
DRAWARC_DONE:
        MOVE.L  -0xAA(A6),A5                    | GET GLOBAL PTR
        JSR     ShowCursor(PC)                  | RESTORE CURSOR
DRAWARC_GOHOME:
        MOVE.L  -0x94(A6),SP                    | STRIP BUFFER
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | RELEASE LOCAL VARS
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0x14,SP                        | STRIP PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER

| -----------------------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE THE MASK BUFFER
| BASED ON WHICH REGIONS ARE RECTANGULAR
|
| Called during boot.
DRAWARC_GOHOME_CONT:
        MOVE    D7,D0                           | SEEKMASK: GET CURRENT VERT COORD
        MOVE    -0x96(A6),D1                    | GET RECTFLAG = 0,2,4
        MOVE    DRAWARC_GOHOME_CONT_2(PC,D1.W),D1 | GET BRANCH OFFSET
        JMP     DRAWARC_GOHOME_CONT_2(PC,D1.W)  | DISPATCH ON RECTFLAG

| ----------------------------------------------------------
|
| DRAWARC_GOHOME_CONT_2 - indexed branch table for DrawArc region masking modes
|
DRAWARC_GOHOME_CONT_2:
  .byte 0x00,0x16,0x00,0x08,0x00,0x18           | OFFSETS: BOTH RECT, A ONLY, B ONLY
  .byte 0x00,0x1E                               | OFFSET: BOTH NON-RECT

|
| ONLY REGION A IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
DRAWARC_GOHOME_CONT_3:
        LEA.L   -0x60(A6),A1                    | POINT TO STATEA

| JSRSEEK - call SeekRgn(StateA), store buffer pointer as scan mask
JSRSEEK:
        JSR     SeekRgn(PC)                     | SEEK REGION TO CURRENT VERT
        MOVE.L  SCANBUF(A1),-0x9A(A6)           | USE REGION BUF AS MASK
JSRSEEK_CONT:
        RTS                                     | IGNORE

|
| ONLY REGION B IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
JSRSEEK_CONT_2:
        LEA.L   -0x78(A6),A1                    | POINT TO STATEB

        BRA.B   JSRSEEK                         | SEEK AND USE AS MASK

|
| REGIONS A AND B ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
JSRSEEK_CONT_3:
        LEA.L   -0x60(A6),A1                    | POINT TO STATEA

        JSR     SeekRgn(PC)                     | SEEK CLIPRGN TO CURRENT VERT
        LEA.L   -0x78(A6),A1                    | POINT TO STATEB
        JSR     SeekRgn(PC)                     | SEEK VISRGN TO CURRENT VERT
        MOVE.L  -0x58(A6),A0                    | GET STATEA SCANBUF PTR
        MOVE.L  -0x70(A6),A1                    | GET STATEB SCANBUF PTR
        MOVE.L  -0x9A(A6),A2                    | GET MASKBUF PTR
        MOVE    -0x9E(A6),D1                    | GET BUFSIZE (LOOP COUNT)
ABLOOP:
        MOVE.L  (A0)+,D0                        | GET NEXT CLIPRGN LONG
        AND.L   (A1)+,D0                        | INTERSECT WITH VISRGN
        MOVE.L  D0,(A2)+                        | STORE IN MASKBUF
        DBF     D1,ABLOOP                       | LOOP FOR ALL LONGS
        RTS                                     | RETURN

| .PROC INITOVAL,4
| ------------------------------------------------------------
|
| PROCEDURE InitOval(dstRect: Rect; VAR oval: OvalRec;
| ovalWidth,ovalHeight: INTEGER);
|
| initialize an oval state record to fit the given rectangle.
|
| INPUTS: A0: dstRect
| A1: ovalRec
| D1: ovalHeight
| D2: ovalWidth
|
| CLOBBERS D0,D1,D2
|
| Called during boot.
InitOval:
        MOVE    (A0),(A1)                       | INIT OVAL TOP TO DSTRECT TOP
        MOVE    BOTTOM(A0),0x2(A1)              | INIT OVAL BOTTOM

| -----------------------------------------------------------
|
| INIT OVAL TOP AND BOTTOM TO DSTRECT TOP AND BOTTOM
        TST     D2                              | IS OVALWIDTH NEGATIVE ?
        BPL.B   OK1                             | NO, CONTINUE
        CLR     D2                              | YES, PIN IT TO 0
OK1:
        TST     D1                              | IS OVALHEIGHT NEGATIVE ?
        BPL.B   OK1_NO                          | NO, CONTINUE
        CLR     D1                              | YES, PIN IT TO 0

| OK2

| CHECK OVALWIDTH AND OVALHEIGHT, TRIM IF BIGGER THAN DSTRECT
| Called during boot.
OK1_NO:
        MOVE    RIGHT(A0),D0                    | GET DSTRECT RIGHT
        SUB     LEFT(A0),D0                     | CALC DSTRECT WIDTH
        CMP     D0,D2                           | IS OVALWIDTH > DSTWIDTH ?
        BLE.B   INITOVAL_OK3                    | NO,CONTINUE
        MOVE    D0,D2                           | YES, OVALWIDTH:= DSTWIDTH
INITOVAL_OK3:
        MOVE    BOTTOM(A0),D0                   | OK3
        SUB     (A0),D0                         | CALC DSTRECT HEIGHT
        CMP     D0,D1                           | IS OVALHEIGHT > DSTHEIGHT ?
        BLE.B   INITOVAL_OK3_NO                 | NO,CONTINUE
        MOVE    D0,D1                           | YES, OVALHEIGHT:= DSTHEIGHT
INITOVAL_OK3_NO:
        MOVE    0x6(A0),0x26(A1)                | RIGHTEDGE.HI := DSTRIGHT
        CLR     0x28(A1)                        | RIGHTEDGE.LO := 0
        MOVE    0x2(A0),0x22(A1)                | LEFTEDGE.HI := DSTLEFT
        CLR     0x24(A1)                        | LEFTEDGE.LO := 0

| OK4
| SET UP OVAL LEFT EDGE AND OVAL RIGHT EDGE, FIXED POINT NUMBERS
        MOVE    D2,D0                           | GET OVAL WIDTH
        SWAP    D0                              | PUT IN HI WORD
        CLR     D0                              | CLEAR LO WORD FOR FIXED POINT
        LSR.L   #1,D0                           | CALC OVAL WIDTH DIV 2
        ADD.L   D0,0x22(A1)                     | ADD OVALWD/2 TO LEFTEDGE
        SUB.L   D0,0x26(A1)                     | SUBTRACT OVALWD/2 FROM LEFTEDGE
        MOVE.L  #0x8000,D0                      | GET FIXED POINT 1/2
        MOVE.L  D0,0x2A(A1)                     | SAVE IN OVAL STATE RECORD
        ADD.L   D0,0x26(A1)                     | BIAS RIGHT EDGE +1/2

| INIT OVALY TO -OVALHEIGHT + 1 (SCALED BY 2, BIASED 1/2 SCANLINE)
        MOVEQ   #1,D0                           | START WITH 1
        SUB     D1,D0                           | CALC 1 - OVALHEIGHT
        MOVE    D0,0x4(A1)                      | OVALY:=1-HEIGHT

| INIT RSQYSQ TO 2*OVALHEIGHT-1
        MOVE    D1,D0                           | GET HEIGHT
        EXT.L   D0                              | CLEAR OUT HI WORD
        ADD.L   D0,D0                           | CALC 2*HEIGHT
        SUBQ.L  #0x1,D0                         | SUBTRACT 1
        MOVE.L  D0,0x6(A1)                      | RSQYSQ:=2*HEIGHT-1

| INIT SQUARE TO 0.0
        CLR.L   0xA(A1)                         | SQUARE:=0
        CLR.L   0xE(A1)                         | SQUARE LO := 0

| ODDNUM:= 1 TIMES ASPECT RATIO SQUARED
        CLR.L   -(SP)                           | GET READY FOR FUNCTION RESULT
        MOVE    D1,-(SP)                        | PUSH NUMERATOR=HEIGHT
        MOVE    D2,-(SP)                        | PUSH DENOMINATOR=WIDTH
        _FixRatio                               | CALC FIXED POINT HEIGHT/WIDTH
        MOVE.L  (SP),-(SP)                      | DUPLICATE RESULT
        PEA.L   0x12(A1)                        | PUSH ADDR FOR RESULT
        _LongMul                                | CALC 64BIT (HEIGHT/WIDTH) SQUARED
        MOVE.L  0x16(A1),D0                     | GET ODDNUM LO LONG

| _LongMul ;CALC 64BIT (HEIGHT/WIDTH) SQUARED

| ODDBUMP:= 2 TIMES ASPECT RATIO SQUARED
        ADD.L   D0,D0                           | DOUBLE IT
        MOVE.L  D0,0x1E(A1)                     | STORE AS ODDBUMP LO
        MOVE.L  0x12(A1),D0                     | GET ODDNUM HI LONG
        ADDX.L  D0,D0                           | DOUBLE HI LONG WITH CARRY
        MOVE.L  D0,0x1A(A1)                     | STORE AS ODDBUMP HI
        RTS                                     | RETURN FROM INITOVAL

| -------------------------------------------------------
|
| ONLY BUMP IF VERT IS BETWEEN OVALTOP AND OVALBOT

| .PROC BUMPOVAL,2
| ------------------------------------------------------------
|
| LOCAL PROCEDURE BumpOval(VAR oval: OvalRec; vert: INTEGER);
|
| bump an oval state record to the next scanline down.
|
| INPUTS: A3 POINTS TO OVAL STATE RECORD
| D0 CONTAINS CURRENT VERT
|
| CLOBBERS D0-D7,A0-A3
|
| Called during boot.
BumpOval:
        CMP     (A3)+,D0                        | IS VERT < OVAL TOP ?
        BLT.B   BUMPOVAL_GOHOME                 | YES, IGNORE
        CMP     (A3)+,D0                        | IS VERT >= OVAL BOTTOM ?
        BGE.B   BUMPOVAL_GOHOME                 | YES, IGNORE
        MOVE    (A3),D0                         | GET OVALY
        ADDQ.W  #0x2,(A3)+                      | OVALY += 2; ADVANCE PTR
        MOVEM.L (A3),D1-D7/A0-A2                | GET REST OF THE OVAL RECORD
        BRA.B   WHILE1                          | GO TO LOOP START

| ------------------------------------------
|
| register usage:
|
| D0: vert
| D1: RSQYSQ
| D2,D3: SQUARE
| D4,D5: ODDNUM
| D6,D7: ODDBUMP
| A0: LEFTEDGE
| A1: RIGHTEDGE
| A2: #$00008000
| A3: modified oval ptr
|

| -----------------------------------------------
|
| WHILE SQUARE < RSQYSQ DO MAKE OVAL BIGGER
| Called during boot.
BUMPOVAL_MORE1:
        ADD.L   A2,A1                           | MORE1: RIGHTEDGE := RIGHTEDGE + 1/2
        SUB.L   A2,A0                           | LEFTEDGE := LEFTEDGE - 1/2
        ADD.L   D5,D3                           | SQUARE := SQUARE + ODDNUM
        ADDX.L  D4,D2                           | ALL 64 BITS OF IT
        ADD.L   D7,D5                           | ODDNUM := ODDNUM + ODDBUMP
        ADDX.L  D6,D4                           | ALL 64 BITS OF IT
WHILE1:
        CMP.L   D1,D2                           | IS SQUARE < RSQYSQ ?
        BLT.B   BUMPOVAL_MORE1                  | YES, LOOP
        BRA.B   WHILE2                          | NO, GO TO NEXT LOOP START

| -----------------------------------------------
|
| WHILE SQUARE > RSQYSQ DO MAKE OVAL SMALLER
|
| Called during boot.
BUMPOVAL_MORE2:
        SUB.L   A2,A1                           | MORE2: RIGHTEDGE := RIGHTEDGE - 1/2
        ADD.L   A2,A0                           | LEFTEDGE := LEFTEDGE + 1/2
        SUB.L   D7,D5                           | ODDNUM := ODDNUM - ODDBUMP
        SUBX.L  D6,D4                           | ALL 64 BITS OF IT
        SUB.L   D5,D3                           | SQUARE := SQUARE + ODDNUM
        SUBX.L  D4,D2                           | ALL 64 BITS OF IT
WHILE2:
        CMP.L   D1,D2                           | IS SQUARE > RSQYSQ ?
        BGT.B   BUMPOVAL_MORE2                  | YES, LOOP
        ADDQ.W  #0x1,D0                         | OVALY + 1
        EXT.L   D0                              | SIGN EXTEND TO A LONG
        ASL.L   #2,D0                           | CALC 4*(OVALY+1)
        SUB.L   D0,D1                           | RSQYSQ := RSQYSQ-4*(OVALY+1)
        MOVEM.L D1-D7/A0-A2,(A3)                | UPDATE OVAL RECORD
BUMPOVAL_GOHOME:
        RTS                                     | GOHOME


