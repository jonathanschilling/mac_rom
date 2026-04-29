| -----------------------------------------------------------------
|
| --> DRAWLINE.TEXT
|

| .PROC DrawLine
| .REF RgnBlt,RSect,ShieldCursor,ShowCursor,TrimRect
| .REF InitRgn,SeekRgn,PatExpand,ColorMap
| .REF XorSlab,DrawSlab,SlabMode,FastSlabMode,MaskTab
| ----------------------------------------------------------------
|
| PROCEDURE DRAWLINE(P1,P2: POINT);
|
| DRAWS A LINE CLIPPED TO CURRENT PORT'S CLIPRGN AND VISRGN
|
| P1 AND P2 ARE GIVEN IN LOCAL COORDINATES OF THEPORT.
| ------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| Called during boot.
DrawLine:
        LINK    A6,#-0xD0                       | ALLOCATE LOCAL VARIABLES

.set PARAMSIZE, 8                               | SIZE OF PARAMETERS
.set P1, PARAMSIZE+8-4                          | POINT

| .set P2, P1-4 ;POINT

| -------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set EXPAT, -64                                 | 16 LONGS
.set LINERECT, EXPAT-8                          | RECT
.set MINRECT, LINERECT-8                        | RECT
.set STATEA, MINRECT-RGNREC                     | RGN STATE RECORD
.set STATEB, STATEA-RGNREC                      | RGN STATE RECORD
.set STATEC, STATEB-RGNREC                      | RGN STATE RECORD
.set SAVESTK, STATEC-4                          | LONG
.set RECTFLAG, SAVESTK-2                        | WORD
.set MASKBUF, RECTFLAG-4                        | LONG
.set BUFLEFT, MASKBUF-2                         | WORD
.set BUFSIZE, BUFLEFT-2                         | WORD
.set VERT, BUFSIZE-2                            | WORD
.set MODECASE, VERT-4                           | LONG
.set PAT, MODECASE-4                            | LONG, ADDR OF PAT
.set LEFTEDGE, PAT-4                            | LONG, FIXED POINT
.set RIGHTEDGE, LEFTEDGE-4                      | LONG, FIXED POINT
.set SLOPE, RIGHTEDGE-4                         | LONG, FIXED POINT
.set DSTLEFT, SLOPE-4                           | LONG
.set SAVEA5, DSTLEFT-4                          | LONG
.set PORT, SAVEA5-4                             | LONG
.set MODE, PORT-2                               | WORD
.set FASTFLAG, MODE-2                           | BYTE
.set BIGRGN, FASTFLAG-4                         | LONG, RgnHandle
.set VARSIZE, BIGRGN                            | SIZE OF LOCAL VARIABLES

        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS
        MOVE.L  A7,-0x9C(A6)                    | REMEMBER STACK FOR LATER
        MOVE.L  A5,-0xC4(A6)                    | REMEMBER GLOBAL PTR
        MOVE.L  (A5),A0                         | GET GLOBAL PTR
        MOVE.L  WIDEOPEN(A0),-0xD0(A6)          | STASH WIDEOPEN IN BIGRGN
        MOVE.L  (A0),A3                         | GET GRAFPTR
        TST     PNVIS(A3)                       | IS PNVIS NEGATIVE ?
        BLT     DRAWLINE_GOHOME                 | YES, QUIT
        MOVE.L  A3,-0xC8(A6)                    | SAVE PORT FOR LATER

| -------------------------------------------------------
|
| QUIT IF PEN MODE NOT IN 8..15
|
        MOVEQ   #-8,D0                          | MASK FOR PEN MODE
        AND     PNMODE(A3),D0                   | GET ALL BUT 3 BITS OF PEN MODE
        CMPI    #0x8,D0                         | IS IT COPY, OR, XOR, BIC?
        BNE     DRAWLINE_GOHOME                 | NO, QUIT

| -------------------------------------------------------
|
| Check for color filtering. Alter mode and pattern accordingly.
|
        MOVE    PNMODE(A3),-(SP)                | PUSH PEN MODE
        PEA.L   PNPAT(A3)                       | PUSH ADDR OF PEN PATTERN
        TST     COLRBIT(A3)                     | IS COLORBIT = 0 ?
        BMI.B   DRAWLINE_NOCOLOR                | NO COLOR, CONTINUE
        JSR     ColorMap(PC)                    | CHECK AGAINST THECOLOR, THEFILTER
DRAWLINE_NOCOLOR:
        MOVE.L  (SP)+,-0xB0(A6)                 | GET (ALTERED) PATTERN
        MOVE    (SP)+,-0xCA(A6)                 | AND (ALTERED) MODE

| ---------------------------------------------------------
|
| GET CLIPRGN AND VISRGN HANDLES AND DE-REFERENCE THEM
|
        MOVE.L  A3,A5                           | PUT GRAFPTR IN A5
        MOVE.L  CLIPRGN(A5),A2                  | GET CLIPRGN HANDLE
        MOVE.L  (A2),A2                         | GET CLIPRGN POINTER
        MOVE.L  VISRGN(A5),A3                   | GET VISRGN HANDLE
        MOVE.L  (A3),A3                         | GET VISRGN POINTER
        MOVEM   0x8(A6),D1-D4                   | GET P1 AND P2

| -------------------------------------------------------------
|
| SET UP LINERECT, THE RECTANGLE BOUNDING THE LINE AND PEN
|
        CMP     D3,D1                           | IS V1 > V2 ?
        BLE.B   VOK2                            | NO, CONTINUE
        EXG     D1,D3                           | YES, SWAP VERT
VOK2:
        CMP     D4,D2                           | IS H1 > H2 ?
        BLE.B   VOK2_NO                         | NO, CONTINUE
        EXG     D2,D4                           | NO SWAP HORIZ
VOK2_NO:
        ADD     0x36(A5),D4                     | ADD PEN WIDTH TO RIGHT
        ADD     0x34(A5),D3                     | ADD PEN HEIGHT TO BOTTOM
        MOVEM   D1-D4,-0x48(A6)                 | SAVE LINERECT

| -----------------------------------------------------------------------
|
| CALC MINRECT, THE INTERSECTION OF LINERECT, BITMAP BOUNDS,
| CLIPRGN BBOX, AND VISRGN BBOX. QUIT IF NO INTERSECTION.
|
        PEA.L   -0x48(A6)                       | PUSH LINE RECT
        PEA.L   0x8(A5)                         | PUSH BITMAP BOUNDS

| -----------------------------------------------------------------------
|
        PEA.L   RGNBBOX(A2)                     | PUSH CLIPRGN BBOX
        PEA.L   RGNBBOX(A3)                     | PUSH VISRGN BBOX
        MOVE    #4,-(SP)                        | PUSH NRECTS=4
        PEA.L   -0x50(A6)                       | PUSH DST ADDR
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ     DRAWLINE_GOHOME                 | QUIT IF NO INTERSECT

|
| HIDE CURSOR IF CURSOR INTERSECTS MINRECT.
|
        PEA.L   -0x50(A6)                       | PUSH SHIELDRECT PARAMETER
        MOVE.L  0x8(A5),-(SP)                   | PUSH BITMAP TOPLEFT AS OFFSET
        MOVE.L  -0xC4(A6),A5                    | GET GLOBAL PTR

        JSR     ShieldCursor(PC)                | HIDE CURSOR IF IT INTERSECTS
        MOVE.L  -0xC8(A6),A5                    | GET BACK THEPORT

|
| CHECK FOR BOTH VISRGN AND CLIPRGN RECTANGULAR
|
        CLR.B   -0xCC(A6)                       | FASTFLAG := FALSE
        CMPI    #0xA,(A2)                       | IS CLIPRGN RECTANGULAR?

        BNE.B   DRAWLINE_YESFLAG_NO             | NO, CONTINUE
        CMPI    #0xA,(A3)                       | IS VISRGN RECTANGULAR?
        BEQ.B   DRAWLINE_CKPAT                  | YES, CONTINUE

|
| If only visRgn is non-rectangular, then check if
| its intersection with minrect would be rectangular.
| IF TrimRect(visRgn,minRect) then treat as rectangular.
|
        MOVE.L  VISRGN(A5),-(SP)                | push rgnHandle
        PEA.L   -0x50(A6)                       | push addr of minRect
        JSR     TrimRect(PC)                    | call trimRect
        BLT     DRAWLINE_DONE                   | quit if intersection empty
        BGT.B   DRAWLINE_YESFLAG_NO             | continue if non-rectangular

|
| CHECK FOR BLACK OR WHITE PATTERN
|
| Called during boot.
DRAWLINE_CKPAT:
        MOVE.L  -0xB0(A6),A0                    | POINT TO PATTERN

|
| CHECK FOR BLACK OR WHITE PATTERN
|
        MOVE.L  (A0)+,D0                        | GET 1ST HALF OF PATTERN
        CMP.L   (A0)+,D0                        | IS IT SAME AS 2ND HALF ?
        BNE.B   DRAWLINE_YESFLAG_NO             | NO, CONTINUE
        NOT.L   D0                              | IS PATTERN BLACK ?
        BEQ.B   DRAWLINE_YESFLAG                | YES, WE MADE IT
        NOT.L   D0                              | IS PATTERN WHITE ?
        BNE.B   DRAWLINE_YESFLAG_NO             | NO, CONTINUE
        EORI    #0x4,-0xCA(A6)                  | FLIP INVERT BIT IN MODE
DRAWLINE_YESFLAG:
        ST.B    -0xCC(A6)                       | RECT CLIPPED AND BLACK

|
| fast case: map mode into black,xor,white, or do-nothing
|
        MOVEQ   #7,D0                           | GET 3 BIT MASK
        AND     -0xCA(A6),D0                    | GET 3 BITS OF MODE
        MOVE.B  DRAWLINE_YESFLAG_CONT(PC,D0.W),D0 | GET FAST MODE FROM TABLE
        BMI     DRAWLINE_DONE                   | QUIT IF DO-NOTHING MODE
        MOVE    D0,-0xCA(A6)                    | UPDATE MODE
        BRA.B   DRAWLINE_YESFLAG_NO             | AND CONTINUE

| ----------------------------------------------------------
|
| DRAWLINE_YESFLAG_CONT - indexed branch table for DrawLine region scan modes
|
DRAWLINE_YESFLAG_CONT:
  .byte 0x00,0x00,0x01,0x02,0x02,0xFF           | BLACK,BLACK,XOR,WHITE,WHITE,NOP
  .byte 0xFF,0xFF                               | NOP,NOP
| DRAWLINE_YESFLAG_NO - DrawLine entry point when pen mode skip-flag is clear
DRAWLINE_YESFLAG_NO:
        MOVEM   0x8(A6),D1-D4                   | GET P1 AND P2

| FLAGOK

|
| GET THE TWO LINE ENDPOINTS INTO REGISTERS
| AND CHECK FOR HORIZONTAL OR VERTICAL LINE
|
        CMP     D2,D4                           | H1=H2 ?
        BEQ.B   HVLINE                          | YES, DO VERTICAL LINE
        CMP     D1,D3                           | NO, IS V2 > V1 ?
        BGT.B   SLANTED                         | YES, DRAW SLANTED LINE
        BLT.B   VSWAP                           | SWAP POINTS AND DRAW SLANTED

| ELSE V1=V2, DO HORIZONTAL

| -----------------------------------------------------------
|
| LINE IS EITHER HORIZONTAL OR VERTICAL.
| CHECK FOR ONE DOT LINE, BLACK OR WHITE PATTERN, AND
| CLIPRGN AND VISRGN BOTH RECTANGULAR. IF SO, OPTIMIZE FAST LINES.
|
| Called during boot.
HVLINE:
        TST.B   -0xCC(A6)                       | RECT CLIPPED AND BLACK ?

| ELSE V1=V2, DO HORIZONTAL

| -----------------------------------------------------------
|
| LINE IS EITHER HORIZONTAL OR VERTICAL.
| CHECK FOR ONE DOT LINE, BLACK OR WHITE PATTERN, AND
| CLIPRGN AND VISRGN BOTH RECTANGULAR. IF SO, OPTIMIZE FAST LINES.
|
        BEQ.B   NOTFAST                         | NO, CONTINUE
        CMPI.L  #0x10001,0x34(A5)               | IS PEN SIZE 1,1?

        BEQ     FASTLINE                        | YES, DO IT FAST !

| --------------------------------------------------------------------
|
| NOT FASTLINE. PUSH PARAMS AND CALL RGNBLT FOR HORIZ OR VERT LINE.
|
| Called during boot.
NOTFAST:
        PEA.L   PORTBITS(A5)                    | PUSH SRCBITS = DSTBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L   -0x50(A6)                       | PUSH SRCRECT = DSTRECT
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    PNMODE(A5),-(SP)                | PUSH MODE
        PEA.L   PNPAT(A5)                       | PUSH PATTERN
        MOVE.L  CLIPRGN(A5),-(SP)               | PUSH CLIPRGN HANDLE
        MOVE.L  VISRGN(A5),-(SP)                | PUSH VISRGN HANDLE
        MOVE.L  -0xD0(A6),-(SP)                 | PUSH SAVED WIDEOPEN
        MOVE.L  -0xC4(A6),A5                    | GET GLOBAL PTR
        JSR     RgnBlt(PC)                      | DRAW THE HORIZ OR VERT LINE
        BRA     DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| -------------------------------------------------------------
|
| THE LINE IS SLANTED. SORT VERTICALLY
| AND DRAW TOP TO BOTTOM AS HORIZONTAL SLABS.
|
VSWAP:
        EXG     D1,D3                           | SORT POINTS BY VERTICAL
        EXG     D2,D4                           | SWAP HORIZ TO MATCH

| -------------------------------------------------------------
|
| THE LINE IS SLANTED. SORT VERTICALLY
| AND DRAW TOP TO BOTTOM AS HORIZONTAL SLABS.
|
SLANTED:
        MOVE    D3,D0                           | COPY LINE BOTTOM
        ADD     0x34(A5),D0                     | ADD PEN HEIGHT
        CMP     0x2(A2),D0                      | IS BOTTOM < CLIPRGN TOP?
        BLE     DRAWLINE_DONE                   | YES, RESTORE CURSOR AND QUIT
        CMP     0x6(A2),D1                      | IS TOP >= CLIPRGN BOTTOM?
        BGE     DRAWLINE_DONE                   | YES, RESTORE CURSOR AND QUIT
        MOVE    D2,-0xB4(A6)                    | INIT LEFT EDGE INTEGER
        MOVE    #-0x8000,-0xB2(A6)              | INIT LEFT EDGE FRACTION

| -------------------------------------------------------------
|
| SET UP INITIAL FIXED POINT LEFTEDGE AND RIGHTEDGE
| AND CHECK FOR ZERO PENSIZE.
|
        MOVE.L  -0xB4(A6),-0xB8(A6)             | RIGHTEDGE:=LEFTEDGE
        MOVE    0x36(A5),D0                     | GET PEN WIDTH

| -------------------------------------------------------------
|
        BLE     DRAWLINE_DONE                   | QUIT IF PENWIDTH <= 0
        ADD     D0,-0xB8(A6)                    | ADD PEN WIDTH TO RIGHT EDGE
        MOVE    0x34(A5),D6                     | GET PEN HEIGHT
        BLE     DRAWLINE_DONE                   | QUIT IF PEN HEIGHT <= 0

| ----------------------------------------------------
|
| CALC FIXED POINT SLOPE = FixRatio(dh,dv);
|
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    D4,-(SP)                        | PUSH BOTTOM HORIZ
        SUB     D2,(SP)                         | CALC DH
        MOVE    D3,-(SP)                        | PUSH BOTTOM VERT
        SUB     D1,(SP)                         | CALC DV
        _FixRatio                               | CALC FIXED POINT SLOPE DH/DV
        MOVE.L  (SP)+,D7                        | POP RESULT
        MOVE.L  D7,-0xBC(A6)                    | SAVE FOR LATER

|
| CALC adjust := pen height * slope
|
        CLR.L   -(SP)                           | PUSH ROOM FOR FCN RESULT
        CLR.W   -(SP)                           | PUSH LOWORD = 0
        MOVE    D6,-(SP)                        | PUSH PEN HEIGHT
        MOVE.L  D7,-(SP)                        | PUSH SLOPE
        _FixMul                                 | CALC FixMul(pnSize.v,slope)
        MOVE.L  (SP)+,D6                        | POP ANSWER INTO D6

|
| ADJUST LEFTEDGE AND RIGHTEDGE DEPENDING ON SIGN AND MAGNITUDE OF SLOPE
|
        MOVE.L  D7,D0                           | COPY SLOPE
        ASR.L   #1,D0                           | CALC SLOPE/2
        ADD.L   D0,-0xB4(A6)                    | ADD SLOPE/2 TO LEFT EDGE
        ADD.L   D0,-0xB8(A6)                    | ADD SLOPE/2 TO RIGHT EDGE
        TST.L   D7                              | IS SLOPE NEGATIVE ?
        BMI.B   NEGSLOPE                        | YES, CONTINUE
        SUB.L   D6,-0xB4(A6)                    | SUBTRACT ADJUST FROM LEFTEDGE
        CMPI.L  #0x10000,D7                     | IS SLOPE >= 1.0?
        BGE.B   SLANTED_NO                      | NO, BRANCH
        ADD.L   D7,-0xB4(A6)                    | ADD SLOPE TO LEFTEDGE
        BRA.B   NEGSLOPE_CONT                   | CONTINUE

| ----------------------------------------------------------
|
| SLANTED_NO
|
SLANTED_NO:
        SUBQ.W  #0x1,-0xB8(A6)                  | ADJUST RIGHT EDGE
        BRA.B   NEGSLOPE_CONT                   | CONTINUE

| ----------------------------------------------------
|
| SLOPE IS NEGATIVE
|
NEGSLOPE:
        SUB.L   D6,-0xB8(A6)                    | SUBTRACT ADJUST FROM RIGHTEDGE
        CMPI.L  #0xFFFF0000,D7                  | IS SLOPE <= -1.0?

| ----------------------------------------------------
|
| SLOPE IS NEGATIVE
|
        BLT.B   NEGSLOPE_NO                     | NO, CONTINUE
        ADD.L   D7,-0xB8(A6)                    | ADD SLOPE TO RIGHTEDGE
        BRA.B   NEGSLOPE_CONT                   | CONTINUE

| ----------------------------------------------------------
|
| NEGSLOPE_NO
|
NEGSLOPE_NO:
        ADDQ.W  #0x1,-0xB4(A6)                  | ADJUST LEFT EDGE
NEGSLOPE_CONT:
        MOVEM   -0x50(A6),D1-D4                 | GET MINRECT (TOP,LEFT,BOTTOM,RIGHT)
        CMP     -0x48(A6),D1                    | IS MINRECT TOP == LINERECT TOP?

|
| ADJUST LEFTEDGE AND RIGHTEDGE IF LINE WAS CLIPPED VERTICALLY
|
        BEQ.B   NEGSLOPE_NO_2                   | NO, CONTINUE
        MOVE    D1,D0                           | COPY MINRECT TOP
        SUB     -0x48(A6),D0                    | CALC VERTICAL CLIP AMOUNT
        MOVE.L  D7,D5                           | GET 32 BIT SLOPE
        SWAP    D5                              | GET HI WORD OF SLOPE
        MULS    D0,D5                           | MULT TIMES DISCARD
        SWAP    D5                              | PUT RESULT IN HI WORD
        CLR.W   D5                              | CLEAR LO WORD
        MOVE.L  D7,D6                           | GET NEW COPY OF SLOPE
        MULU    D0,D6                           | MULT LO WORD TIMES DISCARD
        ADD.L   D6,D5                           | CALC 32BIT SLOPE*DISCARD
        ADD.L   D5,-0xB4(A6)                    | BUMP LEFTEDGE TO NEW TOP
        ADD.L   D5,-0xB8(A6)                    | BUMP RIGHTEDGE TO NEW TOP
NEGSLOPE_NO_2:
        MOVE    -0x4E(A6),D2                    | GET MINRECT LEFT
        SUB     0xA(A5),D2                      | SUBTRACT BITMAP BOUNDS LEFT
        ANDI    #-0x10,D2                       | TRUNCATE TO 16-BIT WORD BOUNDARY
        ADD     0xA(A5),D2                      | RE-ADD BITMAP BOUNDS LEFT

| TOPOK
|
| CALC BUFLEFT
|
        MOVE    D2,-0xA4(A6)                    | SAVE AS BUFLEFT

|
| IF FASTFLAG, THEN SKIP REGION SETUP
|
        TST.B   -0xCC(A6)                       | RECT CLIPPED AND BLACK ?

        BNE     DRAWLINE_CLRMASK_SKIP           | YES, DON'T WASTE TIME WITH SETUP
        MOVE    -0x4A(A6),D0                    | GET MINRECT RIGHT

|
| CALC BUFSIZE
|
        SUB     D2,D0                           | CALC MAXH-BUFLEFT
        LSR     #5,D0                           | DIV BY 32 FOR LONGS
        MOVE    D0,-0xA6(A6)                    | BUFSIZE = # LONGS - 1

|
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK
|
DRAWLINE_CLRMASK:
        CLR.L   -(SP)                           | CLRMASK: ALLOCATE AND CLEAR ONE LONG
        DBF     D0,DRAWLINE_CLRMASK             | LOOP TILL DONE
        MOVE.L  A7,-0xA2(A6)                    | REMEMBER WHERE MASKBUF IS

| -------------------------------------------------------------------------
|
| INIT STATE RECORDS AND ALLOCATE BUFFERS FOR EACH NON-RECTANGULAR REGION
|
        CLR     D5                              | INIT BOTH ARE RECT
        MOVE    #-0x7FFF,-0x5A(A6)              | STATEA MINH := -32767
        MOVE    #0x7FFF,-0x58(A6)               | STATEA MAXH := 32767
        CMPI    #0xA,(A2)                       | IS CLIPRGN RECTANGULAR?
        BEQ.B   DRAWLINE_CLRMASK_OK             | YES, CONTINUE
        ADDQ.W  #0x2,D5                         | FLAG CLIPRGN NON-RECTANGULAR
        MOVE.L  A2,A0                           | POINT TO CLIPRGN
        LEA.L   -0x68(A6),A1                    | POINT TO STATE RECORD A
        BSR.B   DRAWLINE_CLRMASK_CONT           | INIT STATE, ALLOC BUFFER
DRAWLINE_CLRMASK_OK:
        MOVE    #-0x7FFF,-0x72(A6)              | STATEB MINH := -32767
        MOVE    #0x7FFF,-0x70(A6)               | STATEB MAXH := 32767
        CMPI    #0xA,(A3)                       | IS VISRGN RECTANGULAR?

| ARECT
        BEQ.B   DRAWLINE_CLRMASK_EXIT           | YES, CONTINUE
        ADDQ.W  #0x4,D5                         | FLAG VISRGN NON-RECTANGULAR
        MOVE.L  A3,A0                           | POINT TO VISRGN
        LEA.L   -0x80(A6),A1                    | POINT TO STATE RECORD B
        PEA.L   DRAWLINE_CLRMASK_EXIT(PC)       | PUSH FAKE RETURN ADDR
| DRAWLINE_CLRMASK_CONT -- iNIT STATE, ALLOC BUFFER.
DRAWLINE_CLRMASK_CONT:
        MOVE    -0x4E(A6),D0                    | GET MINRECT LEFT
        MOVE    -0x4A(A6),D1                    | GET MINRECT RIGHT
        MOVE    -0xA4(A6),D2                    | GET BUFLEFT
        JMP     InitRgn(PC)                     | INIT STATE, ALLOC BUFFER

| ----------------------------------------------------------
|
| DRAWLINE_CLRMASK_EXIT
|
DRAWLINE_CLRMASK_EXIT:
        MOVE    D5,-0x9E(A6)                    | SAVE RECTFLAG

| BRECT

| --------------------------------------------------------------------
|
| IF BOTH REGIONS ARE RECTANGULAR, THEN DRAW MINRECT INTO MASK BUFFER
|
        BNE.B   DRAWLINE_CLRMASK_SKIP           | NO, CONTNUE
        MOVE.L  -0xA2(A6),A0                    | YES, POINT TO MASK BUFFER
        MOVE    -0x4E(A6),D3                    | GET MINRECT LEFT
        SUB     -0xA4(A6),D3                    | MAKE IT BUFFER RELATIVE
        MOVE    -0x4A(A6),D4                    | GET MINRECT RIGHT
        SUB     -0xA4(A6),D4                    | MAKE IT BUFFER RELATIVE
        JSR     XorSlab(PC)                     | AND XOR BETWEEN THEM
DRAWLINE_CLRMASK_SKIP:
        MOVE    -0x50(A6),D1                    | GET MINRECT TOP
        SUB     0x8(A5),D1                      | SUBTRACT BITMAP BOUNDS TOP
        MULU    0x6(A5),D1                      | MULTIPLY BY ROWBYTES
        ADD.L   0x2(A5),D1                      | ADD BITMAP BASE ADDRESS
        SUB     0xA(A5),D2                      | SUBTRACT BITMAP BOUNDS LEFT

| NOTRECT

| SKIPSETUP

| ------------------------------------
|
| CALC STARTING DSTLEFT
|
        LSR     #3,D2                           | CALC BUFLEFT DIV 8
        EXT.L   D2                              | CLR HI WORD
        ADD.L   D2,D1                           | ADD HORIZ BYTE OFFSET
        MOVE.L  D1,-0xC0(A6)                    | SAVE AS DSTLEFT

| ----------------------------------------------------
|
| MAKE LEFTEDGE,RIGHTEDGE,MINRECT RELATIVE TO BUFFER LEFT
|
        MOVE    -0xA4(A6),D1                    | GET BUFLEFT
        SUB     D1,-0xB4(A6)                    | ADJUST LEFT EDGE
        SUB     D1,-0xB8(A6)                    | ADJUST RIGHT EDGE
        SUB     D1,-0x4E(A6)                    | ADJUST MINRECT LEFT
        SUB     D1,-0x4A(A6)                    | ADJUST MINRECT RIGHT

| ------------------------------------------------------------
|
| TAKE FAST OR SLOW OUTER CONTROL LOOP FOR SLANTED LINES:
|
        TST.B   -0xCC(A6)                       | ARE WE RECT CLIPPED BLACK ?

| ----------------------------------------------------
|

| ------------------------------------------------------------
|
        BEQ.B   GOSLOW                          | NO, CONTINUE
        MOVE    -0xCA(A6),D2                    | GET (ALTERED) PEN MODE
        JSR     FastSlabMode(PC)                | Get fast case jump in A4
        LEA.L   DT_mMaskTab(PC),A0              | point to mask table
        LEA.L   -0x50(A6),A3                    | POINT TO MINRECT
        MOVE.L  -0xBC(A6),D7                    | GET FIXED POINT SLOPE
        MOVE    0x6(A5),D6                      | GET ROWBYTES
        MOVE.L  -0xC0(A6),A5                    | GET DSTLEFT
        MOVE    -0x4C(A6),D5                    | GET MINRECT BOTTOM
        SUB     -0x50(A6),D5                    | SUBTRACT MINRECT TOP
        SUBQ.W  #0x1,D5                         | ADJUST FOR DBF
DRAWLINE_CLRMASK_LOOP:
        MOVE    -0xB4(A6),D1                    | GET LEFT EDGE INTEGER
        MOVE    -0xB8(A6),D2                    | GET RIGHT EDGE INTEGER
        MOVE.L  A5,A1                           | INIT DSTPTR TO LEFT
        JSR     DrawSlab(PC)                    | DRAW ONE SLAB IN PENMODE
        ADD     D6,A5                           | BUMP DST TO NEXT ROW
        ADD.L   D7,-0xB4(A6)                    | ADD SLOPE TO LEFT EDGE
        ADD.L   D7,-0xB8(A6)                    | ADD SLOPE TO RIGHT EDGE
        DBF     D5,DRAWLINE_CLRMASK_LOOP        | LOOP FOR ALL SCANLINES
        BRA     DRAWLINE_DONE                   | AND QUIT

| ----------------------------------------------------------
|
| GOSLOW
|
GOSLOW:
        MOVE    -0xCA(A6),D2                    | GET (ALTERED) PEN MODE
        JSR     SlabMode(PC)                    | GET DrawSlab CASE JUMP IN A4

| ------------------------------------------------------------------
|
| EXPAND 8 BYTE PATTERN TO 16 LONGS AND INIT PATTERN SELECTOR
|
        CLR.L   D7                              | SAY NOT INVERTED
        MOVE    -0xCA(A6),D2                    | GET (ALTERED) PEN MODE
        BCLR    #2,D2                           | TEST AND CLR INVERT BIT
        BEQ.B   GOSLOW_SKIP                     | SKIP IF NOT INVERTED
        NOT.L   D7                              | INVERTED; D7 GETS ALL 1'S
GOSLOW_SKIP:
        MOVE    0xA(A5),D2                      | GET BITMAP BOUNDS LEFT
        MOVE.L  -0xB0(A6),A0                    | POINT TO BYTE WIDE PATTERN
        LEA.L   -0x40(A6),A1                    | POINT TO EXPANDED PATTERN
        MOVE.L  -0xC4(A6),A5                    | GET GLOBAL PTR
        JSR     PatExpand(PC)                   | EXPAND 8 BYTES TO 16 LONGS
        MOVE.L  -0xC8(A6),A5                    | RESTORE GRAFPTR IN A5
        MOVEQ.L #0xF,D7                         | TREAT COORD MOD 16
        AND     -0x50(A6),D7                    | APPLY MINRECT TOP
        LSL     #2,D7                           | QUAD FOR LONG INDEX

|
| FOR EACH SLAB, MAKE MASK BUFFER CURRENT AND DRAW SLAB
|
        LEA.L   -0x50(A6),A3                    | POINT TO MINRECT
        MOVE    0x6(A5),D5                      | GET ROWBYTES
        MOVE.L  -0xC0(A6),A5                    | GET DSTLEFT
        MOVE.L  -0xBC(A6),D4                    | GET FIXED POINT SLOPE
        MOVE    -0x50(A6),-0xA8(A6)             | INIT CURRENT VERT TO MINRECT TOP

NXTMASK:
        BSR.B   DRAWLINE_GOHOME_CONT            | MAKE MASK BUFFER CURRENT
        MOVE.L  -0x40(A6,D7.W),D6               | GET PATTERN LONG
        MOVE    -0xB4(A6),D1                    | GET LEFT EDGE INTEGER
        MOVE    -0xB8(A6),D2                    | GET RIGHT EDGE INTEGER
        LEA.L   DT_mMaskTab(PC),A0              | point to mask table
        MOVE.L  A5,A1                           | INIT DSTPTR TO LEFT
        MOVE.L  -0xA2(A6),A2                    | INIT MASKPTR TO LEFT
        JSR     DrawSlab(PC)                    | DRAW ONE SLAB IN PENMODE
        ADDQ.W  #0x4,D7                         | BUMP PATTERN INDEX
        ANDI    #0x3F,D7                        | WRAP PATTERN INDEX MOD 64
        ADD     D5,A5                           | BUMP DST TO NEXT ROW
        ADD.L   D4,-0xB4(A6)                    | ADD SLOPE TO LEFT EDGE
        ADD.L   D4,-0xB8(A6)                    | ADD SLOPE TO RIGHT EDGE
        ADDQ.W  #0x1,-0xA8(A6)                  | BUMP CURRENT VERT
        MOVE    -0xA8(A6),D0                    | GET CURRENT VERT
        CMP     -0x4C(A6),D0                    | ARE WE AT MINRECT BOTTOM?
        BLT.B   NXTMASK                         | NO, LOOP ALL SCAN LINES
| Called by: NOTFAST, DRAWLINE_CLRMASK_LOOP, ENDCLR, ENDTOGL, ENDSET (and 3 more)
DRAWLINE_DONE:
        MOVE.L  -0xC4(A6),A5                    | GET GLOBAL PTR
        JSR     ShowCursor(PC)                  | RESTORE CURSOR
DRAWLINE_GOHOME:
        MOVE.L  -0x9C(A6),SP                    | STRIP BUFFER
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | RELEASE LOCAL VARIABLES
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR INTO A0
        ADDQ.W  #0x8,SP                         | STRIP PARAMETERS
        JMP     (A0)                            | JUMP THRU A0 TO RETURN

| -----------------------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE THE MASK BUFFER
| BASED ON WHICH REGIONS ARE RECTANGULAR
|
DRAWLINE_GOHOME_CONT:
        MOVE    -0xA8(A6),D0                    | GET CURRENT VERT COORD
        MOVE    -0x9E(A6),D1                    | GET RECTFLAG = 0,2,4
        MOVE    DRAWLINE_GOHOME_CONT_2(PC,D1.W),D1 | GET MASK MODE OFFSET
        JMP     DRAWLINE_GOHOME_CONT_2(PC,D1.W) | JUMP TO MASK ROUTINE

| ----------------------------------------------------------
|
| DRAWLINE_GOHOME_CONT_2 - indexed branch table for DrawLine region masking modes
|
DRAWLINE_GOHOME_CONT_2:
  .byte 0x00,0x16,0x00,0x08,0x00,0x18           | OFFSETS: BOTH RECT, A ONLY, B ONLY
  .byte 0x00,0x1E                               | OFFSET: BOTH NON-RECT

| --------------------------------------------------------------------
|
| ONLY REGION A IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
DRAWLINE_GOHOME_CONT_3:
        LEA.L   -0x68(A6),A1                    | POINT TO STATE RECORD A

| -----------------------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE THE MASK BUFFER
| BASED ON WHICH REGIONS ARE RECTANGULAR
|

| --------------------------------------------------------------------
|
DRAWLINE_JSRSEEK:
        JSR     SeekRgn(PC)                     | SEEK REGION TO CURRENT VERT
        MOVE.L  SCANBUF(A1),-0xA2(A6)           | USE REGION SCAN BUFFER AS MASK
DRAWLINE_JSRSEEK_CONT:
        RTS                                     | IGNORE

| --------------------------------------------------------------------
|
| ONLY REGION B IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
DRAWLINE_JSRSEEK_CONT_2:
        LEA.L   -0x80(A6),A1                    | POINT TO STATE RECORD B

| --------------------------------------------------------------------
|
        BRA.B   DRAWLINE_JSRSEEK                | SEEK REGION AND USE AS MASK

| -------------------------------------------------------------------
|
| REGIONS A AND B ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
DRAWLINE_JSRSEEK_CONT_3:
        LEA.L   -0x68(A6),A1                    | POINT TO STATE RECORD A

| -------------------------------------------------------------------
|
        JSR     SeekRgn(PC)                     | SEEK REGION TO CURRENT VERT
        LEA.L   -0x80(A6),A1                    | POINT TO STATE RECORD B
        JSR     SeekRgn(PC)                     | SEEK REGION TO CURRENT VERT
        MOVE.L  -0x60(A6),A0                    | GET REGION A SCAN BUFFER
        MOVE.L  -0x78(A6),A1                    | GET REGION B SCAN BUFFER
        MOVE.L  -0xA2(A6),A2                    | GET COMPOSITE MASK BUFFER
        MOVE    -0xA6(A6),D1                    | GET MASK BUFFER SIZE IN LONGS
DRAWLINE_ABLOOP:
        MOVE.L  (A0)+,D0                        | ABLOOP
        AND.L   (A1)+,D0                        | INTERSECT A AND B
        MOVE.L  D0,(A2)+                        | STORE IN COMPOSITE MASK
        DBF     D1,DRAWLINE_ABLOOP              | LOOP FOR ALL LONGS IN SCANLINE
        RTS                                     | RETURN


| -------------------------------------------------------
|
| SET UP AND DRAW A FAST HORIZONTAL OR VERTICAL LINE.
|
| Called during boot.
FASTLINE:
        CMP     D1,D3                           | IS LINE HORIZONTAL ?
        BNE     VLINE                           | NO, MUST BE VERTICAL
        BSR     HVSETUP                         | GET DSTPTR,ROWBYTES,HGLOBAL
        MOVE    0x20(A0,D0.W),D6                | GET LEFT MASK
        MOVE    -0x4A(A6),D2                    | GET MINRECT RIGHT
        SUB     0xA(A5),D2                      | SUBTRACT BITMAP BOUNDS LEFT
        MOVE    D2,D0                           | MAKE A COPY OF RIGHT
        ANDI    #0xF,D0                         | MASK OUT LOWER 4 BITS
        ADD     D0,D0                           | DOUBLE FOR TABLE
        MOVE    0x0(A0,D0.W),D3                 | GET RIGHT MASK
        LSR     #4,D2                           | CONVERT DOTS TO WORDS
        CMPI    #0x1,-0xCA(A6)                  | CHECK IF MODE IS WHITE (1)
        BLT.B   HSET                            | BR IF BLACK
        BEQ.B   HTOGL                           | BR IF XOR

| ELSE WHITE

| ------------------------------------------------------
|
| DRAW A WHITE HORIZONTAL LINE
|
        NOT     D6                              | MAKE NOT LEFTMASK
        NOT     D3                              | MAKE NOT RIGHTMASK
        SUB     D1,D2                           | CALC WORDCOUNT
        BEQ.B   ENDCLR                          | BR IF ALL IN ONE WORD
        AND     D6,(A4)+                        | DO LEFT WORD WITH MASK
        CLR.L   D6                              | FLUSH LEFTMASK FOR END
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BEQ.B   ENDCLR                          | BR IF NO UNMASKED WORDS
        LSR     #1,D2                           | HALVE WORDCOUNT FOR LONGCOUNT
        BCC.B   CLRONE                          | BR IF EVEN # WORDS LEFT
        MOVE    D6,(A4)+                        | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BRA.B   CLRMORE                         | SEE IF ANY LONGS LEFT TO DO

| ----------------------------------------------------------
|
| CLRTWO
|
CLRTWO:
        MOVE.L  D6,(A4)+                        | FILL A LONG WITH BLACK
CLRONE:
        MOVE.L  D6,(A4)+                        | FILL ANOTHER LONG
        SUBQ.W  #0x2,D2                         | DECREMENT LONGCOUNT
CLRMORE:
        BGT.B   CLRTWO                          | YES, AT LEAST TWO LONGS
        BEQ.B   CLRONE                          | YES, FINISH UP LAST LONG
ENDCLR:
        OR      D3,D6                           | COMBINE LEFT AND RIGHT MASK
        AND     D6,(A4)                         | DRAW LINE
        BRA     DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| --------------------------------------------------
|
| DRAW AN XOR HORIZONTAL LINE
|
HTOGL:
        SUB     D1,D2                           | CALC WORDCOUNT
        BEQ.B   ENDTOGL                         | BR IF ALL IN ONE WORD
        EOR     D6,(A4)+                        | DO LEFT WORD WITH MASK
        MOVEQ   #-1,D6                          | FLUSH LEFTMASK FOR END
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BEQ.B   ENDTOGL                         | BR IF NO UNMASKED WORDS
        LSR     #1,D2                           | HALVE WORDCOUNT FOR LONGCOUNT
        BCC.B   TOGLONE                         | BR IF EVEN # WORDS LEFT
        EOR     D6,(A4)+                        | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BRA.B   TOGLMORE                        | SEE IF ANY LONGS LEFT TO DO

| ----------------------------------------------------------
|
| TOGLTWO
|
TOGLTWO:
        NOT.L   (A4)+                           | INVERT A LONG
TOGLONE:
        NOT.L   (A4)+                           | INVERT ANOTHER LONG
        SUBQ.W  #0x2,D2                         | DECREMENT LONGCOUNT
TOGLMORE:
        BGT.B   TOGLTWO                         | YES, AT LEAST TWO LONGS
        BEQ.B   TOGLONE                         | YES, FINISH UP LAST LONG
ENDTOGL:
        AND     D3,D6                           | COMBINE LEFT AND RIGHT MASK
        EOR     D6,(A4)                         | DRAW LINE
        BRA     DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| --------------------------------------------
|
| DRAW A BLACK HORIZONTAL LINE
|
| Called during boot.
HSET:
        SUB     D1,D2                           | CALC WORDCOUNT
        BEQ.B   ENDSET                          | BR IF ALL IN ONE WORD
        OR      D6,(A4)+                        | DO LEFT WORD WITH MASK
        MOVEQ   #-1,D6                          | FLUSH LEFTMASK FOR END
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BEQ.B   ENDSET                          | BR IF NO UNMASKED WORDS
        LSR     #1,D2                           | HALVE WORDCOUNT FOR LONGCOUNT
        BCC.B   SETONE                          | BR IF EVEN # WORDS LEFT
        MOVE    D6,(A4)+                        | ELSE MAKE EVEN BY DOING A WORD
        SUBQ.W  #0x1,D2                         | DECREMENT COUNT
        BRA.B   SETMORE                         | SEE IF ANY LONGS LEFT TO DO

| ----------------------------------------------------------
|
| SETTWO
|
| Called during boot.
SETTWO:
        MOVE.L  D6,(A4)+                        | FILL A LONG WITH BLACK
SETONE:
        MOVE.L  D6,(A4)+                        | FILL ANOTHER LONG
        SUBQ.W  #0x2,D2                         | DECREMENT LONGCOUNT
SETMORE:
        BGT.B   SETTWO                          | YES, AT LEAST TWO LONGS
        BEQ.B   SETONE                          | YES, FINISH UP LAST LONG
ENDSET:
        AND     D3,D6                           | COMBINE LEFT AND RIGHT MASK
        OR      D6,(A4)                         | DRAW LINE
        BRA     DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| -------------------------------------------------------
|
| DRAW A VERTICAL LINE.
|
| Called during boot.
VLINE:
        BSR.B   HVSETUP                         | GET DSTPTR,ROWBYTES,HGLOBAL
        MOVE    0x40(A0,D0.W),D0                | GET DOT MASK
        MOVE    -0x4C(A6),D1                    | GET MINRECT BOTTOM
        SUB     -0x50(A6),D1                    | SUBTRACT MINRECT TOP
        SUBQ.W  #0x1,D1                         | ADJUST FOR DBF
        CMPI    #0x1,-0xCA(A6)                  | CHECK IF MODE IS WHITE (1)
        BLT.B   VSET                            | BR IF BLACK
        BEQ.B   VTOGL                           | BR IF XOR

| ELSE WHITE
        NOT     D0                              | MAKE NOTMASK
VCLR:
        AND     D0,(A4)                         | CLEAR ONE DOT
        ADD     D7,A4                           | BUMP TO NEXT ROW
        DBF     D1,VCLR                         | LOOP ALL DOTS
        BRA     DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| ----------------------------------------------------------
|
| VTOGL
|
VTOGL:
        EOR     D0,(A4)                         | TOGGLE ONE DOT
        ADD     D7,A4                           | BUMP TO NEXT ROW
        DBF     D1,VTOGL                        | LOOP ALL DOTS
        BRA     DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| ----------------------------------------------------------
|
| VSET
|
| Called during boot.
VSET:
        OR      D0,(A4)                         | SET ONE DOT
        ADD     D7,A4                           | BUMP TO NEXT ROW
        DBF     D1,VSET                         | LOOP ALL DOTS
        BRA     DRAWLINE_DONE                   | RESTORE CURSOR AND QUIT

| ----------------------------------------------------------
|
| HVSETUP
|
| Called during boot.
HVSETUP:
        MOVE.L  0x2(A5),A4                      | GET BITMAP BASE ADDRESS
        MOVE    -0x50(A6),D0                    | GET MINRECT TOP
        SUB     0x8(A5),D0                      | SUBTRACT BITMAP BOUNDS TOP
        MOVE    0x6(A5),D7                      | GET ROWBYTES

| ------------------------------------------------------------------------
|
| LOCAL ROUTINE TO SET UP POINTER TO FIRST WORD, BIT INDEX, AND ROWBYTES
|
| INPUTS: MINRECT
| A5: thePort
|
| OUTPUTS: D0: STARTING HORIZ GLOBAL COORDS
| D1: STARTING HORIZ GLOBAL DIV 16
| D7: ROWBYTES
| A0: MaskTab
| A4: POINTER TO FIRST WORD
|
| CLOBBERS: D0,D1,D7,A0,A4
|
        MULU    D7,D0                           | MULT TOP BY ROWBYTES
        ADD.L   D0,A4                           | ADD TO BASEADDR
        MOVE    -0x4E(A6),D0                    | GET MINRECT LEFT
        SUB     0xA(A5),D0                      | SUBTRACT BITMAP BOUNDS LEFT
        MOVE    D0,D1                           | MAKE A COPY
        LSR     #4,D1                           | CONVERT BITS TO WORDS
        ADD     D1,A4                           | ADD TO RUNNING TOTAL
        ADD     D1,A4                           | TWICE FOR BYTES
        LEA.L   DT_mMaskTab(PC),A0              | return with masktab in A0
        ANDI    #0xF,D0                         | MASK OUT LOWER 4 BITS
        ADD     D0,D0                           | DOUBLE FOR TABLE
        RTS                                     | RETURN



