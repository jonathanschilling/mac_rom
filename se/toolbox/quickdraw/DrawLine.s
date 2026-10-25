| -----------------------------------------------------------------
|
| --> DRAWLINE.TEXT

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
|
| Local-variable A6 offsets (-0x40 EXPAT[16-long pat], -0x48 LINERECT,
| -0x50 MINRECT, then RgnState A/B/C, -0x9C SAVESTK, -0x9E RECTFLAG,
| -0xA2 MASKBUF, -0xA4 BUFLEFT, -0xA6 BUFSIZE, -0xA8 VERT, -0xAC MODECASE,
| -0xB0 PAT, -0xB4 LEFTEDGE, -0xB8 RIGHTEDGE, -0xBC SLOPE, -0xC0 DSTLEFT,
| -0xC4 SAVEA5, -0xC8 PORT, -0xCA MODE, -0xCC FASTFLAG, -0xD0 BIGRGN).
|
| Called during boot.
DRAWLINE:
    LINK	A6,#-0xD0                              | ALLOCATE LOCAL VARIABLES
    MOVEM.L	D0-D7/A1-A5,-(A7)                   | SAVE REGS
    MOVE.L	A7,-0x9C(A6)                         | REMEMBER STACK FOR LATER
    MOVE.L	A5,-0xC4(A6)                         | REMEMBER GLOBAL PTR
    MOVEA.L	(A5),A0                             | GET GLOBAL PTR
    MOVE.L	-0x82(A0),-0xD0(A6)                  | STASH WIDEOPEN IN BIGRGN
    MOVEA.L	(A0),A3                             | GET GRAFPTR
    TST.W	0x42(A3)                              | IS PNVIS NEGATIVE ?
    BLT.W	DRAWLINE_GOHOME                       | YES, QUIT
    MOVE.L	A3,-0xC8(A6)                         | SAVE PORT FOR LATER
| -------------------------------------------------------
|
| QUIT IF PEN MODE NOT IN 8..15
|
    MOVEQ.L	#-0x8,D0                            | MASK FOR PEN MODE
    AND.W	0x38(A3),D0                           | GET ALL BUT 3 BITS OF PEN MODE
    CMPI.W	#0x8,D0                              | IS IT COPY, OR, XOR, BIC?
    BNE.W	DRAWLINE_GOHOME                       | NO, QUIT
| -------------------------------------------------------
|
| Check for color filtering. Alter mode and pattern accordingly.
|
    MOVE.W	0x38(A3),-(A7)                       | PUSH PEN MODE
    PEA.L	0x3A(A3)                              | PUSH ADDR OF PEN PATTERN
    TST.W	0x58(A3)                              | IS COLORBIT = 0 ?
    BMI.B	DRAWLINE_NOCOLOR                      | NO COLOR, CONTINUE
    JSR	COLORMAP(PC)                            | CHECK AGAINST THECOLOR, THEFILTER
DRAWLINE_NOCOLOR:
    MOVE.L	(A7)+,-0xB0(A6)                      | GET (ALTERED) PATTERN
    MOVE.W	(A7)+,-0xCA(A6)                      | AND (ALTERED) MODE
| ---------------------------------------------------------
|
| GET CLIPRGN AND VISRGN HANDLES AND DE-REFERENCE THEM
|
    MOVEA.L	A3,A5                               | PUT GRAFPTR IN A5
    MOVEA.L	0x1C(A5),A2                         | GET CLIPRGN HANDLE
    MOVEA.L	(A2),A2                             | GET CLIPRGN POINTER
    MOVEA.L	0x18(A5),A3                         | GET VISRGN HANDLE
    MOVEA.L	(A3),A3                             | GET VISRGN POINTER
    MOVEM.W	0x8(A6),D1-D4                       | GET P1 AND P2
| -------------------------------------------------------------
|
| SET UP LINERECT, THE RECTANGLE BOUNDING THE LINE AND PEN
|
    CMP.W	D3,D1                                 | IS V1 > V2 ?
    BLE.B	VOK2                                  | NO, CONTINUE
    EXG	D1,D3                                   | YES, SWAP VERT
VOK2:
    CMP.W	D4,D2                                 | IS H1 > H2 ?
    BLE.B	VOK2_NO                               | NO, CONTINUE
    EXG	D2,D4                                   | NO SWAP HORIZ
VOK2_NO:
    ADD.W	0x36(A5),D4                           | ADD PEN WIDTH TO RIGHT
    ADD.W	0x34(A5),D3                           | ADD PEN HEIGHT TO BOTTOM
    MOVEM.W	D1-D4,-0x48(A6)                     | SAVE LINERECT
| -----------------------------------------------------------------------
|
| CALC MINRECT, THE INTERSECTION OF LINERECT, BITMAP BOUNDS,
| CLIPRGN BBOX, AND VISRGN BBOX. QUIT IF NO INTERSECTION.
|
    PEA.L	-0x48(A6)                             | PUSH LINE RECT
    PEA.L	0x8(A5)                               | PUSH BITMAP BOUNDS
    PEA.L	0x2(A2)                               | PUSH CLIPRGN BBOX
    PEA.L	0x2(A3)                               | PUSH VISRGN BBOX
    MOVE.W	#0x4,-(A7)                           | PUSH NRECTS=4
    PEA.L	-0x50(A6)                             | PUSH DST ADDR
    JSR	RSECT(PC)                               | CALC INTERSECTION
    BEQ.W	DRAWLINE_GOHOME                       | QUIT IF NO INTERSECT
|
| HIDE CURSOR IF CURSOR INTERSECTS MINRECT.
|
    PEA.L	-0x50(A6)                             | PUSH SHIELDRECT PARAMETER
    MOVE.L	0x8(A5),-(A7)                        | PUSH BITMAP TOPLEFT AS OFFSET
    MOVEA.L	-0xC4(A6),A5                        | GET GLOBAL PTR
    JSR	SHIELDCURSOR(PC)                        | HIDE CURSOR IF IT INTERSECTS
    MOVEA.L	-0xC8(A6),A5                        | GET BACK THEPORT
|
| CHECK FOR BOTH VISRGN AND CLIPRGN RECTANGULAR
|
    CLR.B	-0xCC(A6)                             | FASTFLAG := FALSE
    CMPI.W	#0xA,(A2)                            | IS CLIPRGN RECTANGULAR?
    BNE.B	DRAWLINE_YESFLAG_NO                   | NO, CONTINUE
    CMPI.W	#0xA,(A3)                            | IS VISRGN RECTANGULAR?
    BEQ.B	DRAWLINE_CKPAT                        | YES, CONTINUE
|
| If only visRgn is non-rectangular, then check if
| its intersection with minrect would be rectangular.
| IF TrimRect(visRgn,minRect) then treat as rectangular.
|
    MOVE.L	0x18(A5),-(A7)                       | push rgnHandle
    PEA.L	-0x50(A6)                             | push addr of minRect
    JSR	TRIMRECT(PC)                            | call trimRect
    BLT.W	DRAWLINE_DONE                         | quit if intersection empty
    BGT.B	DRAWLINE_YESFLAG_NO                   | continue if non-rectangular
|
| CHECK FOR BLACK OR WHITE PATTERN
|
| Called during boot.
DRAWLINE_CKPAT:
    MOVEA.L	-0xB0(A6),A0                        | POINT TO PATTERN
|
| CHECK FOR BLACK OR WHITE PATTERN
|
    MOVE.L	(A0)+,D0                             | GET 1ST HALF OF PATTERN
    CMP.L	(A0)+,D0                              | IS IT SAME AS 2ND HALF ?
    BNE.B	DRAWLINE_YESFLAG_NO                   | NO, CONTINUE
    NOT.L	D0                                    | IS PATTERN BLACK ?
    BEQ.B	DRAWLINE_YESFLAG                      | YES, WE MADE IT
    NOT.L	D0                                    | IS PATTERN WHITE ?
    BNE.B	DRAWLINE_YESFLAG_NO                   | NO, CONTINUE
    EORI.W	#0x4,-0xCA(A6)                       | FLIP INVERT BIT IN MODE
DRAWLINE_YESFLAG:
    ST.B	-0xCC(A6)                              | RECT CLIPPED AND BLACK
|
| fast case: map mode into black,xor,white, or do-nothing
|
    MOVEQ.L	#0x7,D0                             | GET 3 BIT MASK
    AND.W	-0xCA(A6),D0                          | GET 3 BITS OF MODE
    MOVE.B	DRAWLINE_YESFLAG_CONT(PC,D0.W),D0    | GET FAST MODE FROM TABLE
    BMI.W	DRAWLINE_DONE                         | QUIT IF DO-NOTHING MODE
    MOVE.W	D0,-0xCA(A6)                         | UPDATE MODE
    BRA.B	DRAWLINE_YESFLAG_NO                   | AND CONTINUE
| ----------------------------------------------------------
|
| DRAWLINE_YESFLAG_CONT: 8-byte mode table for DrawLine fast-line dispatch
|     index = mode & 7. Result -> stored back into MODE local.
|     0x00,0x00 = mode 0,1: BLACK
|     0x01      = mode 2:   XOR
|     0x02,0x02 = mode 3,4: WHITE
|     0xFF,0xFF,0xFF = mode 5,6,7: NOP (do nothing, signed-negative)
|
DRAWLINE_YESFLAG_CONT:
    .short	0x0000
    .long	0x010202FF
    .short	0xFFFF
| DRAWLINE_YESFLAG_NO - DrawLine entry point when pen mode skip-flag is clear
| Called by: VOK2_NO, DRAWLINE_CKPAT, DRAWLINE_YESFLAG
DRAWLINE_YESFLAG_NO:
    MOVEM.W	0x8(A6),D1-D4                       | GET P1 AND P2
| FLAGOK
|
| GET THE TWO LINE ENDPOINTS INTO REGISTERS
| AND CHECK FOR HORIZONTAL OR VERTICAL LINE
|
    CMP.W	D2,D4                                 | H1=H2 ?
    BEQ.B	HVLINE                                | YES, DO VERTICAL LINE
    CMP.W	D1,D3                                 | NO, IS V2 > V1 ?
    BGT.B	SLANTED                               | YES, DRAW SLANTED LINE
    BLT.B	VSWAP                                 | SWAP POINTS AND DRAW SLANTED
| ELSE V1=V2, DO HORIZONTAL
| -----------------------------------------------------------
|
| LINE IS EITHER HORIZONTAL OR VERTICAL.
| CHECK FOR ONE DOT LINE, BLACK OR WHITE PATTERN, AND
| CLIPRGN AND VISRGN BOTH RECTANGULAR. IF SO, OPTIMIZE FAST LINES.
|
| Called during boot.
HVLINE:
    TST.B	-0xCC(A6)                             | RECT CLIPPED AND BLACK ?
    BEQ.B	NOTFAST                               | NO, CONTINUE
    CMPI.L	#0x10001,0x34(A5)                    | IS PEN SIZE 1,1?
    BEQ.W	FASTLINE                              | YES, DO IT FAST !
| --------------------------------------------------------------------
|
| NOT FASTLINE. PUSH PARAMS AND CALL RGNBLT FOR HORIZ OR VERT LINE.
|
| Called during boot.
NOTFAST:
    PEA.L	0x2(A5)                               | PUSH SRCBITS = DSTBITS
    MOVE.L	(A7),-(A7)                           | PUSH DSTBITS
    PEA.L	-0x50(A6)                             | PUSH SRCRECT = DSTRECT
    MOVE.L	(A7),-(A7)                           | PUSH DSTRECT
    MOVE.W	0x38(A5),-(A7)                       | PUSH MODE
    PEA.L	0x3A(A5)                              | PUSH PATTERN
    MOVE.L	0x1C(A5),-(A7)                       | PUSH CLIPRGN HANDLE
    MOVE.L	0x18(A5),-(A7)                       | PUSH VISRGN HANDLE
    MOVE.L	-0xD0(A6),-(A7)                      | PUSH SAVED WIDEOPEN
    MOVEA.L	-0xC4(A6),A5                        | GET GLOBAL PTR
    JSR	RGNBLT(PC)                              | DRAW THE HORIZ OR VERT LINE
    BRA.W	DRAWLINE_DONE                         | RESTORE CURSOR AND QUIT
| -------------------------------------------------------------
|
| THE LINE IS SLANTED. SORT VERTICALLY
| AND DRAW TOP TO BOTTOM AS HORIZONTAL SLABS.
|
VSWAP:
    EXG	D1,D3                                   | SORT POINTS BY VERTICAL
    EXG	D2,D4                                   | SWAP HORIZ TO MATCH
SLANTED:
    MOVE.W	D3,D0                                | COPY LINE BOTTOM
    ADD.W	0x34(A5),D0                           | ADD PEN HEIGHT
    CMP.W	0x2(A2),D0                            | IS BOTTOM < CLIPRGN TOP?
    BLE.W	DRAWLINE_DONE                         | YES, RESTORE CURSOR AND QUIT
    CMP.W	0x6(A2),D1                            | IS TOP >= CLIPRGN BOTTOM?
    BGE.W	DRAWLINE_DONE                         | YES, RESTORE CURSOR AND QUIT
    MOVE.W	D2,-0xB4(A6)                         | INIT LEFT EDGE INTEGER
    MOVE.W	#0x8000,-0xB2(A6)                    | INIT LEFT EDGE FRACTION (0.5)
| -------------------------------------------------------------
|
| SET UP INITIAL FIXED POINT LEFTEDGE AND RIGHTEDGE
| AND CHECK FOR ZERO PENSIZE.
|
    MOVE.L	-0xB4(A6),-0xB8(A6)                  | RIGHTEDGE:=LEFTEDGE
    MOVE.W	0x36(A5),D0                          | GET PEN WIDTH
    BLE.W	DRAWLINE_DONE                         | QUIT IF PENWIDTH <= 0
    ADD.W	D0,-0xB8(A6)                          | ADD PEN WIDTH TO RIGHT EDGE
    MOVE.W	0x34(A5),D6                          | GET PEN HEIGHT
    BLE.W	DRAWLINE_DONE                         | QUIT IF PEN HEIGHT <= 0
| ----------------------------------------------------
|
| CALC FIXED POINT SLOPE = FixRatio(dh,dv);
|
    CLR.L	-(A7)                                 | MAKE ROOM FOR FCN RESULT
    MOVE.W	D4,-(A7)                             | PUSH BOTTOM HORIZ
    SUB.W	D2,(A7)                               | CALC DH
    MOVE.W	D3,-(A7)                             | PUSH BOTTOM VERT
    SUB.W	D1,(A7)                               | CALC DV
    _FixRatio                                   | CALC FIXED POINT SLOPE DH/DV
    MOVE.L	(A7)+,D7                             | POP RESULT
    MOVE.L	D7,-0xBC(A6)                         | SAVE FOR LATER
|
| CALC adjust := pen height * slope
|
    CLR.L	-(A7)                                 | PUSH ROOM FOR FCN RESULT
    CLR.W	-(A7)                                 | PUSH LOWORD = 0
    MOVE.W	D6,-(A7)                             | PUSH PEN HEIGHT
    MOVE.L	D7,-(A7)                             | PUSH SLOPE
    _FixMul                                     | CALC FixMul(pnSize.v,slope)
    MOVE.L	(A7)+,D6                             | POP ANSWER INTO D6
|
| ADJUST LEFTEDGE AND RIGHTEDGE DEPENDING ON SIGN AND MAGNITUDE OF SLOPE
|
    MOVE.L	D7,D0                                | COPY SLOPE
    ASR.L	#0x1,D0                               | CALC SLOPE/2
    ADD.L	D0,-0xB4(A6)                          | ADD SLOPE/2 TO LEFT EDGE
    ADD.L	D0,-0xB8(A6)                          | ADD SLOPE/2 TO RIGHT EDGE
    TST.L	D7                                    | IS SLOPE NEGATIVE ?
    BMI.B	NEGSLOPE                              | YES, CONTINUE
    SUB.L	D6,-0xB4(A6)                          | SUBTRACT ADJUST FROM LEFTEDGE
    CMPI.L	#0x10000,D7                          | IS SLOPE >= 1.0?
    BGE.B	SLANTED_NO                            | NO, BRANCH
    ADD.L	D7,-0xB4(A6)                          | ADD SLOPE TO LEFTEDGE
    BRA.B	NEGSLOPE_CONT                         | CONTINUE
| ----------------------------------------------------------
|
| SLANTED_NO
|
SLANTED_NO:
    SUBQ.W	#0x1,-0xB8(A6)                       | ADJUST RIGHT EDGE
    BRA.B	NEGSLOPE_CONT                         | CONTINUE
| ----------------------------------------------------
|
| SLOPE IS NEGATIVE
|
NEGSLOPE:
    SUB.L	D6,-0xB8(A6)                          | SUBTRACT ADJUST FROM RIGHTEDGE
    CMPI.L	#0xFFFF0000,D7                       | IS SLOPE <= -1.0?
    BLT.B	NEGSLOPE_NO                           | NO, CONTINUE
    ADD.L	D7,-0xB8(A6)                          | ADD SLOPE TO RIGHTEDGE
    BRA.B	NEGSLOPE_CONT                         | CONTINUE
| ----------------------------------------------------------
|
| NEGSLOPE_NO
|
NEGSLOPE_NO:
    ADDQ.W	#0x1,-0xB4(A6)                       | ADJUST LEFT EDGE
NEGSLOPE_CONT:
    MOVEM.W	-0x50(A6),D1-D4                     | GET MINRECT (TOP,LEFT,BOTTOM,RIGHT)
    CMP.W	-0x48(A6),D1                          | IS MINRECT TOP == LINERECT TOP?
|
| ADJUST LEFTEDGE AND RIGHTEDGE IF LINE WAS CLIPPED VERTICALLY
|
    BEQ.B	NEGSLOPE_NO_2                         | NO, CONTINUE
    MOVE.W	D1,D0                                | COPY MINRECT TOP
    SUB.W	-0x48(A6),D0                          | CALC VERTICAL CLIP AMOUNT
    MOVE.L	D7,D5                                | GET 32 BIT SLOPE
    SWAP.W	D5                                   | GET HI WORD OF SLOPE
    MULS.W	D0,D5                                | MULT TIMES DISCARD
    SWAP.W	D5                                   | PUT RESULT IN HI WORD
    CLR.W	D5                                    | CLEAR LO WORD
    MOVE.L	D7,D6                                | GET NEW COPY OF SLOPE
    MULU.W	D0,D6                                | MULT LO WORD TIMES DISCARD
    ADD.L	D6,D5                                 | CALC 32BIT SLOPE*DISCARD
    ADD.L	D5,-0xB4(A6)                          | BUMP LEFTEDGE TO NEW TOP
    ADD.L	D5,-0xB8(A6)                          | BUMP RIGHTEDGE TO NEW TOP
NEGSLOPE_NO_2:
    MOVE.W	-0x4E(A6),D2                         | GET MINRECT LEFT
    SUB.W	0xA(A5),D2                            | SUBTRACT BITMAP BOUNDS LEFT
    ANDI.W	#0xFFF0,D2                           | TRUNCATE TO 16-BIT WORD BOUNDARY
    ADD.W	0xA(A5),D2                            | RE-ADD BITMAP BOUNDS LEFT
| TOPOK
|
| CALC BUFLEFT
|
    MOVE.W	D2,-0xA4(A6)                         | SAVE AS BUFLEFT
|
| IF FASTFLAG, THEN SKIP REGION SETUP
|
    TST.B	-0xCC(A6)                             | RECT CLIPPED AND BLACK ?
    BNE.W	DRAWLINE_CLRMASK_SKIP                 | YES, DON'T WASTE TIME WITH SETUP
    MOVE.W	-0x4A(A6),D0                         | GET MINRECT RIGHT
|
| CALC BUFSIZE
|
    SUB.W	D2,D0                                 | CALC MAXH-BUFLEFT
    LSR.W	#0x5,D0                               | DIV BY 32 FOR LONGS
    MOVE.W	D0,-0xA6(A6)                         | BUFSIZE = # LONGS - 1
|
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK
|
DRAWLINE_CLRMASK:
    CLR.L	-(A7)                                 | CLRMASK: ALLOCATE AND CLEAR ONE LONG
    DBF.W	D0,DRAWLINE_CLRMASK                   | LOOP TILL DONE
    MOVE.L	A7,-0xA2(A6)                         | REMEMBER WHERE MASKBUF IS
| -------------------------------------------------------------------------
|
| INIT STATE RECORDS AND ALLOCATE BUFFERS FOR EACH NON-RECTANGULAR REGION
|
    CLR.W	D5                                    | INIT BOTH ARE RECT
    MOVE.W	#0x8001,-0x5A(A6)                    | STATEA MINH := -32767
    MOVE.W	#0x7FFF,-0x58(A6)                    | STATEA MAXH := 32767
    CMPI.W	#0xA,(A2)                            | IS CLIPRGN RECTANGULAR?
    BEQ.B	DRAWLINE_CLRMASK_OK                   | YES, CONTINUE
    ADDQ.W	#0x2,D5                              | FLAG CLIPRGN NON-RECTANGULAR
    MOVEA.L	A2,A0                               | POINT TO CLIPRGN
    LEA.L	-0x68(A6),A1                          | POINT TO STATE RECORD A
    BSR.B	DRAWLINE_CLRMASK_CONT                 | INIT STATE, ALLOC BUFFER
DRAWLINE_CLRMASK_OK:
    MOVE.W	#0x8001,-0x72(A6)                    | STATEB MINH := -32767
    MOVE.W	#0x7FFF,-0x70(A6)                    | STATEB MAXH := 32767
    CMPI.W	#0xA,(A3)                            | IS VISRGN RECTANGULAR?
    BEQ.B	DRAWLINE_CLRMASK_EXIT                 | YES, CONTINUE
    ADDQ.W	#0x4,D5                              | FLAG VISRGN NON-RECTANGULAR
    MOVEA.L	A3,A0                               | POINT TO VISRGN
    LEA.L	-0x80(A6),A1                          | POINT TO STATE RECORD B
    PEA.L	DRAWLINE_CLRMASK_EXIT(PC)             | PUSH FAKE RETURN ADDR
| DRAWLINE_CLRMASK_CONT -- iNIT STATE, ALLOC BUFFER.
DRAWLINE_CLRMASK_CONT:
    MOVE.W	-0x4E(A6),D0                         | GET MINRECT LEFT
    MOVE.W	-0x4A(A6),D1                         | GET MINRECT RIGHT
    MOVE.W	-0xA4(A6),D2                         | GET BUFLEFT
    JMP	INITRGN(PC)                             | INIT STATE, ALLOC BUFFER
| ----------------------------------------------------------
|
| DRAWLINE_CLRMASK_EXIT
|
DRAWLINE_CLRMASK_EXIT:
    MOVE.W	D5,-0x9E(A6)                         | SAVE RECTFLAG
| --------------------------------------------------------------------
|
| IF BOTH REGIONS ARE RECTANGULAR, THEN DRAW MINRECT INTO MASK BUFFER
|
    BNE.B	DRAWLINE_CLRMASK_SKIP                 | NO, CONTINUE
    MOVEA.L	-0xA2(A6),A0                        | YES, POINT TO MASK BUFFER
    MOVE.W	-0x4E(A6),D3                         | GET MINRECT LEFT
    SUB.W	-0xA4(A6),D3                          | MAKE IT BUFFER RELATIVE
    MOVE.W	-0x4A(A6),D4                         | GET MINRECT RIGHT
    SUB.W	-0xA4(A6),D4                          | MAKE IT BUFFER RELATIVE
    JSR	XORSLAB(PC)                             | AND XOR BETWEEN THEM
DRAWLINE_CLRMASK_SKIP:
    MOVE.W	-0x50(A6),D1                         | GET MINRECT TOP
    SUB.W	0x8(A5),D1                            | SUBTRACT BITMAP BOUNDS TOP
    MULU.W	0x6(A5),D1                           | MULTIPLY BY ROWBYTES
    ADD.L	0x2(A5),D1                            | ADD BITMAP BASE ADDRESS
    SUB.W	0xA(A5),D2                            | SUBTRACT BITMAP BOUNDS LEFT
| -------------------------------------
|
| CALC STARTING DSTLEFT
|
    LSR.W	#0x3,D2                               | CALC BUFLEFT DIV 8
    EXT.L	D2                                    | CLR HI WORD
    ADD.L	D2,D1                                 | ADD HORIZ BYTE OFFSET
    MOVE.L	D1,-0xC0(A6)                         | SAVE AS DSTLEFT
| ----------------------------------------------------
|
| MAKE LEFTEDGE,RIGHTEDGE,MINRECT RELATIVE TO BUFFER LEFT
|
    MOVE.W	-0xA4(A6),D1                         | GET BUFLEFT
    SUB.W	D1,-0xB4(A6)                          | ADJUST LEFT EDGE
    SUB.W	D1,-0xB8(A6)                          | ADJUST RIGHT EDGE
    SUB.W	D1,-0x4E(A6)                          | ADJUST MINRECT LEFT
    SUB.W	D1,-0x4A(A6)                          | ADJUST MINRECT RIGHT
| ------------------------------------------------------------
|
| TAKE FAST OR SLOW OUTER CONTROL LOOP FOR SLANTED LINES:
|
    TST.B	-0xCC(A6)                             | ARE WE RECT CLIPPED BLACK ?
    BEQ.B	GOSLOW                                | NO, CONTINUE
    MOVE.W	-0xCA(A6),D2                         | GET (ALTERED) PEN MODE
    JSR	FASTSLABMODE(PC)                        | Get fast case jump in A4
    LEA.L	MASKTAB(PC),A0                        | point to mask table
    LEA.L	-0x50(A6),A3                          | POINT TO MINRECT
    MOVE.L	-0xBC(A6),D7                         | GET FIXED POINT SLOPE
    MOVE.W	0x6(A5),D6                           | GET ROWBYTES
    MOVEA.L	-0xC0(A6),A5                        | GET DSTLEFT
    MOVE.W	-0x4C(A6),D5                         | GET MINRECT BOTTOM
    SUB.W	-0x50(A6),D5                          | SUBTRACT MINRECT TOP
    SUBQ.W	#0x1,D5                              | ADJUST FOR DBF
DRAWLINE_CLRMASK_LOOP:
    MOVE.W	-0xB4(A6),D1                         | GET LEFT EDGE INTEGER
    MOVE.W	-0xB8(A6),D2                         | GET RIGHT EDGE INTEGER
    MOVEA.L	A5,A1                               | INIT DSTPTR TO LEFT
    JSR	DRAWSLAB(PC)                            | DRAW ONE SLAB IN PENMODE
    ADDA.W	D6,A5                                | BUMP DST TO NEXT ROW
    ADD.L	D7,-0xB4(A6)                          | ADD SLOPE TO LEFT EDGE
    ADD.L	D7,-0xB8(A6)                          | ADD SLOPE TO RIGHT EDGE
    DBF.W	D5,DRAWLINE_CLRMASK_LOOP              | LOOP FOR ALL SCANLINES
    BRA.W	DRAWLINE_DONE                         | AND QUIT
| ----------------------------------------------------------
|
| GOSLOW
|
GOSLOW:
    MOVE.W	-0xCA(A6),D2                         | GET (ALTERED) PEN MODE
    JSR	SLABMODE(PC)                            | GET DrawSlab CASE JUMP IN A4
| ------------------------------------------------------------------
|
| EXPAND 8 BYTE PATTERN TO 16 LONGS AND INIT PATTERN SELECTOR
|
    MOVEQ.L	#0x0,D7                             | SAY NOT INVERTED
    MOVE.W	-0xCA(A6),D2                         | GET (ALTERED) PEN MODE
    BCLR	#0x2,D2                                | TEST AND CLR INVERT BIT
    BEQ.B	GOSLOW_SKIP                           | SKIP IF NOT INVERTED
    NOT.L	D7                                    | INVERTED; D7 GETS ALL 1'S
GOSLOW_SKIP:
    MOVE.W	0xA(A5),D2                           | GET BITMAP BOUNDS LEFT
    MOVEA.L	-0xB0(A6),A0                        | POINT TO BYTE WIDE PATTERN
    LEA.L	-0x40(A6),A1                          | POINT TO EXPANDED PATTERN
    MOVEA.L	-0xC4(A6),A5                        | GET GLOBAL PTR
    JSR	PATEXPAND(PC)                           | EXPAND 8 BYTES TO 16 LONGS
    MOVEA.L	-0xC8(A6),A5                        | RESTORE GRAFPTR IN A5
    MOVEQ.L	#0xF,D7                             | TREAT COORD MOD 16
    AND.W	-0x50(A6),D7                          | APPLY MINRECT TOP
    LSL.W	#0x2,D7                               | QUAD FOR LONG INDEX
|
| FOR EACH SLAB, MAKE MASK BUFFER CURRENT AND DRAW SLAB
|
    LEA.L	-0x50(A6),A3                          | POINT TO MINRECT
    MOVE.W	0x6(A5),D5                           | GET ROWBYTES
    MOVEA.L	-0xC0(A6),A5                        | GET DSTLEFT
    MOVE.L	-0xBC(A6),D4                         | GET FIXED POINT SLOPE
    MOVE.W	-0x50(A6),-0xA8(A6)                  | INIT CURRENT VERT TO MINRECT TOP
NXTMASK:
    BSR.B	DRAWLINE_GOHOME_CONT                  | MAKE MASK BUFFER CURRENT
    MOVE.L	-0x40(A6,D7.W),D6                    | GET PATTERN LONG
    MOVE.W	-0xB4(A6),D1                         | GET LEFT EDGE INTEGER
    MOVE.W	-0xB8(A6),D2                         | GET RIGHT EDGE INTEGER
    LEA.L	MASKTAB(PC),A0                        | point to mask table
    MOVEA.L	A5,A1                               | INIT DSTPTR TO LEFT
    MOVEA.L	-0xA2(A6),A2                        | INIT MASKPTR TO LEFT
    JSR	DRAWSLAB(PC)                            | DRAW ONE SLAB IN PENMODE
    ADDQ.W	#0x4,D7                              | BUMP PATTERN INDEX
    ANDI.W	#0x3F,D7                             | WRAP PATTERN INDEX MOD 64
    ADDA.W	D5,A5                                | BUMP DST TO NEXT ROW
    ADD.L	D4,-0xB4(A6)                          | ADD SLOPE TO LEFT EDGE
    ADD.L	D4,-0xB8(A6)                          | ADD SLOPE TO RIGHT EDGE
    ADDQ.W	#0x1,-0xA8(A6)                       | BUMP CURRENT VERT
    MOVE.W	-0xA8(A6),D0                         | GET CURRENT VERT
    CMP.W	-0x4C(A6),D0                          | ARE WE AT MINRECT BOTTOM?
    BLT.B	NXTMASK                               | NO, LOOP ALL SCAN LINES
| Called by: SLANTED, VOK2_NO, DRAWLINE_YESFLAG, NOTFAST, DRAWLINE_CLRMASK_LOOP (and 6 more)
DRAWLINE_DONE:
    MOVEA.L	-0xC4(A6),A5                        | GET GLOBAL PTR
    JSR	SHOWCURSOR(PC)                          | RESTORE CURSOR
DRAWLINE_GOHOME:
    MOVEA.L	-0x9C(A6),A7                        | STRIP BUFFER
    MOVEM.L	(A7)+,D0-D7/A1-A5                   | RESTORE REGISTERS
    UNLK	A6                                     | RELEASE LOCAL VARIABLES
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR INTO A0
    ADDQ.W	#0x8,A7                              | STRIP PARAMETERS
    JMP	(A0)                                    | JUMP THRU A0 TO RETURN
| -----------------------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE THE MASK BUFFER
| BASED ON WHICH REGIONS ARE RECTANGULAR
|
DRAWLINE_GOHOME_CONT:
    MOVE.W	-0xA8(A6),D0                         | GET CURRENT VERT COORD
    MOVE.W	-0x9E(A6),D1                         | GET RECTFLAG = 0,2,4
    MOVE.W	DRAWLINE_GOHOME_CONT_2(PC,D1.W),D1   | GET MASK MODE OFFSET
    JMP	DRAWLINE_GOHOME_CONT_2(PC,D1.W)         | JUMP TO MASK ROUTINE
| ----------------------------------------------------------
|
| DRAWLINE_GOHOME_CONT_2: 8-byte mask-mode offset table.
|     index = RECTFLAG (0..6 step 2)
|     0x0016 = both rectangular: skip update (just RTS)
|     0x0008 = only A non-rect: update A only
|     0x0018 = only B non-rect: update B only
|     0x001E = both non-rect: update both, intersect into mask buffer
|
DRAWLINE_GOHOME_CONT_2:
    .long	0x00160008
    .long	0x0018001E
| --------------------------------------------------------------------
|
| ONLY REGION A IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
DRAWLINE_GOHOME_CONT_3:
    LEA.L	-0x68(A6),A1                          | POINT TO STATE RECORD A
| -----------------------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE THE MASK BUFFER
| BASED ON WHICH REGIONS ARE RECTANGULAR
|

| --------------------------------------------------------------------
|
DRAWLINE_JSRSEEK:
    JSR	SEEKRGN(PC)                             | SEEK REGION TO CURRENT VERT
    MOVE.L	0x8(A1),-0xA2(A6)                    | USE REGION SCAN BUFFER AS MASK
DRAWLINE_JSRSEEK_CONT:
    RTS                                         | IGNORE
| --------------------------------------------------------------------
|
| ONLY REGION B IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
DRAWLINE_JSRSEEK_CONT_2:
    LEA.L	-0x80(A6),A1                          | POINT TO STATE RECORD B
    BRA.B	DRAWLINE_JSRSEEK                      | SEEK REGION AND USE AS MASK
| -------------------------------------------------------------------
|
| REGIONS A AND B ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
DRAWLINE_JSRSEEK_CONT_3:
    LEA.L	-0x68(A6),A1                          | POINT TO STATE RECORD A
    JSR	SEEKRGN(PC)                             | SEEK REGION TO CURRENT VERT
    LEA.L	-0x80(A6),A1                          | POINT TO STATE RECORD B
    JSR	SEEKRGN(PC)                             | SEEK REGION TO CURRENT VERT
    MOVEA.L	-0x60(A6),A0                        | GET REGION A SCAN BUFFER
    MOVEA.L	-0x78(A6),A1                        | GET REGION B SCAN BUFFER
    MOVEA.L	-0xA2(A6),A2                        | GET COMPOSITE MASK BUFFER
    MOVE.W	-0xA6(A6),D1                         | GET MASK BUFFER SIZE IN LONGS
DRAWLINE_ABLOOP:
    MOVE.L	(A0)+,D0                             | ABLOOP
    AND.L	(A1)+,D0                              | INTERSECT A AND B
    MOVE.L	D0,(A2)+                             | STORE IN COMPOSITE MASK
    DBF.W	D1,DRAWLINE_ABLOOP                    | LOOP FOR ALL LONGS IN SCANLINE
    RTS                                         | AND RETURN
| -------------------------------------------------------
|
| SET UP AND DRAW A FAST HORIZONTAL OR VERTICAL LINE.
|
| Called during boot.
FASTLINE:
    CMP.W	D1,D3                                 | IS LINE HORIZONTAL ?
    BNE.W	VLINE                                 | NO, MUST BE VERTICAL
    BSR.W	HVSETUP                               | GET DSTPTR,ROWBYTES,HGLOBAL
    MOVE.W	0x20(A0,D0.W),D6                     | GET LEFT MASK
    MOVE.W	-0x4A(A6),D2                         | GET MINRECT RIGHT
    SUB.W	0xA(A5),D2                            | SUBTRACT BITMAP BOUNDS LEFT
    MOVE.W	D2,D0                                | MAKE A COPY OF RIGHT
    ANDI.W	#0xF,D0                              | MASK OUT LOWER 4 BITS
    ADD.W	D0,D0                                 | DOUBLE FOR TABLE
    MOVE.W	0x0(A0,D0.W),D3                      | GET RIGHT MASK
    LSR.W	#0x4,D2                               | CONVERT DOTS TO WORDS
    CMPI.W	#0x1,-0xCA(A6)                       | CHECK IF MODE IS WHITE (1)
    BLT.B	HSET                                  | BR IF BLACK
    BEQ.B	HTOGL                                 | BR IF XOR
| ELSE WHITE
| ------------------------------------------------------
|
| DRAW A WHITE HORIZONTAL LINE
|
    NOT.W	D6                                    | MAKE NOT LEFTMASK
    NOT.W	D3                                    | MAKE NOT RIGHTMASK
    SUB.W	D1,D2                                 | CALC WORDCOUNT
    BEQ.B	ENDCLR                                | BR IF ALL IN ONE WORD
    AND.W	D6,(A4)+                              | DO LEFT WORD WITH MASK
    MOVEQ.L	#0x0,D6                             | FLUSH LEFTMASK FOR END
    SUBQ.W	#0x1,D2                              | DECREMENT COUNT
    BEQ.B	ENDCLR                                | BR IF NO UNMASKED WORDS
    LSR.W	#0x1,D2                               | HALVE WORDCOUNT FOR LONGCOUNT
    BCC.B	CLRONE                                | BR IF EVEN # WORDS LEFT
    MOVE.W	D6,(A4)+                             | ELSE MAKE EVEN BY DOING A WORD
    SUBQ.W	#0x1,D2                              | DECREMENT COUNT
    BRA.B	CLRMORE                               | SEE IF ANY LONGS LEFT TO DO
| ----------------------------------------------------------
|
| CLRTWO
|
CLRTWO:
    MOVE.L	D6,(A4)+                             | FILL A LONG WITH BLACK
CLRONE:
    MOVE.L	D6,(A4)+                             | FILL ANOTHER LONG
    SUBQ.W	#0x2,D2                              | DECREMENT LONGCOUNT
CLRMORE:
    BGT.B	CLRTWO                                | YES, AT LEAST TWO LONGS
    BEQ.B	CLRONE                                | YES, FINISH UP LAST LONG
ENDCLR:
    OR.W	D3,D6                                  | COMBINE LEFT AND RIGHT MASK
    AND.W	D6,(A4)                               | DRAW LINE
    BRA.W	DRAWLINE_DONE                         | RESTORE CURSOR AND QUIT
| --------------------------------------------------
|
| DRAW AN XOR HORIZONTAL LINE
|
HTOGL:
    SUB.W	D1,D2                                 | CALC WORDCOUNT
    BEQ.B	ENDTOGL                               | BR IF ALL IN ONE WORD
    EOR.W	D6,(A4)+                              | DO LEFT WORD WITH MASK
    MOVEQ.L	#-0x1,D6                            | FLUSH LEFTMASK FOR END
    SUBQ.W	#0x1,D2                              | DECREMENT COUNT
    BEQ.B	ENDTOGL                               | BR IF NO UNMASKED WORDS
    LSR.W	#0x1,D2                               | HALVE WORDCOUNT FOR LONGCOUNT
    BCC.B	TOGLONE                               | BR IF EVEN # WORDS LEFT
    EOR.W	D6,(A4)+                              | ELSE MAKE EVEN BY DOING A WORD
    SUBQ.W	#0x1,D2                              | DECREMENT COUNT
    BRA.B	TOGLMORE                              | SEE IF ANY LONGS LEFT TO DO
| ----------------------------------------------------------
|
| TOGLTWO
|
TOGLTWO:
    NOT.L	(A4)+                                 | INVERT A LONG
TOGLONE:
    NOT.L	(A4)+                                 | INVERT ANOTHER LONG
    SUBQ.W	#0x2,D2                              | DECREMENT LONGCOUNT
TOGLMORE:
    BGT.B	TOGLTWO                               | YES, AT LEAST TWO LONGS
    BEQ.B	TOGLONE                               | YES, FINISH UP LAST LONG
ENDTOGL:
    AND.W	D3,D6                                 | COMBINE LEFT AND RIGHT MASK
    EOR.W	D6,(A4)                               | DRAW LINE
    BRA.W	DRAWLINE_DONE                         | RESTORE CURSOR AND QUIT
| --------------------------------------------
|
| DRAW A BLACK HORIZONTAL LINE
|
| Called during boot.
HSET:
    SUB.W	D1,D2                                 | CALC WORDCOUNT
    BEQ.B	ENDSET                                | BR IF ALL IN ONE WORD
    OR.W	D6,(A4)+                               | DO LEFT WORD WITH MASK
    MOVEQ.L	#-0x1,D6                            | FLUSH LEFTMASK FOR END
    SUBQ.W	#0x1,D2                              | DECREMENT COUNT
    BEQ.B	ENDSET                                | BR IF NO UNMASKED WORDS
    LSR.W	#0x1,D2                               | HALVE WORDCOUNT FOR LONGCOUNT
    BCC.B	SETONE                                | BR IF EVEN # WORDS LEFT
    MOVE.W	D6,(A4)+                             | ELSE MAKE EVEN BY DOING A WORD
    SUBQ.W	#0x1,D2                              | DECREMENT COUNT
    BRA.B	SETMORE                               | SEE IF ANY LONGS LEFT TO DO
| ----------------------------------------------------------
|
| SETTWO
|
| Called during boot.
SETTWO:
    MOVE.L	D6,(A4)+                             | FILL A LONG WITH BLACK
SETONE:
    MOVE.L	D6,(A4)+                             | FILL ANOTHER LONG
    SUBQ.W	#0x2,D2                              | DECREMENT LONGCOUNT
SETMORE:
    BGT.B	SETTWO                                | YES, AT LEAST TWO LONGS
    BEQ.B	SETONE                                | YES, FINISH UP LAST LONG
ENDSET:
    AND.W	D3,D6                                 | COMBINE LEFT AND RIGHT MASK
    OR.W	D6,(A4)                                | DRAW LINE
    BRA.W	DRAWLINE_DONE                         | RESTORE CURSOR AND QUIT
| -------------------------------------------------------
|
| DRAW A VERTICAL LINE.
|
| Called during boot.
VLINE:
    BSR.B	HVSETUP                               | GET DSTPTR,ROWBYTES,HGLOBAL
    MOVE.W	0x40(A0,D0.W),D0                     | GET DOT MASK
    MOVE.W	-0x4C(A6),D1                         | GET MINRECT BOTTOM
    SUB.W	-0x50(A6),D1                          | SUBTRACT MINRECT TOP
    SUBQ.W	#0x1,D1                              | ADJUST FOR DBF
    CMPI.W	#0x1,-0xCA(A6)                       | CHECK IF MODE IS WHITE (1)
    BLT.B	VSET                                  | BR IF BLACK
    BEQ.B	VTOGL                                 | BR IF XOR
| ELSE WHITE
    NOT.W	D0                                    | MAKE NOTMASK
VCLR:
    AND.W	D0,(A4)                               | CLEAR ONE DOT
    ADDA.W	D7,A4                                | BUMP TO NEXT ROW
    DBF.W	D1,VCLR                               | LOOP ALL DOTS
    BRA.W	DRAWLINE_DONE                         | RESTORE CURSOR AND QUIT
| ----------------------------------------------------------
|
| VTOGL
|
VTOGL:
    EOR.W	D0,(A4)                               | TOGGLE ONE DOT
    ADDA.W	D7,A4                                | BUMP TO NEXT ROW
    DBF.W	D1,VTOGL                              | LOOP ALL DOTS
    BRA.W	DRAWLINE_DONE                         | RESTORE CURSOR AND QUIT
| ----------------------------------------------------------
|
| VSET
|
| Called during boot.
VSET:
    OR.W	D0,(A4)                                | SET ONE DOT
    ADDA.W	D7,A4                                | BUMP TO NEXT ROW
    DBF.W	D1,VSET                               | LOOP ALL DOTS
    BRA.W	DRAWLINE_DONE                         | RESTORE CURSOR AND QUIT
| ----------------------------------------------------------
|
| HVSETUP -- LOCAL ROUTINE TO SET UP POINTER TO FIRST WORD, BIT INDEX, AND ROWBYTES.
|
| INPUTS:  MINRECT and A5:thePort
| OUTPUTS: D0=starting horiz global, D1=horiz global div 16,
|          D7=rowbytes, A0=MaskTab, A4=ptr to first dst word
| CLOBBERS: D0,D1,D7,A0,A4
|
| Called during boot.
HVSETUP:
    MOVEA.L	0x2(A5),A4                          | GET BITMAP BASE ADDRESS
    MOVE.W	-0x50(A6),D0                         | GET MINRECT TOP
    SUB.W	0x8(A5),D0                            | SUBTRACT BITMAP BOUNDS TOP
    MOVE.W	0x6(A5),D7                           | GET ROWBYTES
    MULU.W	D7,D0                                | MULT TOP BY ROWBYTES
    ADDA.L	D0,A4                                | ADD TO BASEADDR
    MOVE.W	-0x4E(A6),D0                         | GET MINRECT LEFT
    SUB.W	0xA(A5),D0                            | SUBTRACT BITMAP BOUNDS LEFT
    MOVE.W	D0,D1                                | MAKE A COPY
    LSR.W	#0x4,D1                               | CONVERT BITS TO WORDS
    ADDA.W	D1,A4                                | ADD TO RUNNING TOTAL
    ADDA.W	D1,A4                                | TWICE FOR BYTES
    LEA.L	MASKTAB(PC),A0                        | return with masktab in A0
    ANDI.W	#0xF,D0                              | MASK OUT LOWER 4 BITS
    ADD.W	D0,D0                                 | DOUBLE FOR TABLE
    RTS                                         | AND RETURN
