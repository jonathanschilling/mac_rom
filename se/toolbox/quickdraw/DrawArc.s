| -----------------------------------------------------------
|
| --> DRAWARC.TEXT
|
| Routine to draw solid or hollow Ovals, RoundRects or Arcs.

| .PROC DrawArc,8
| .REF InitOval,BumpOval,SlopeFromAngle
| .REF RSect,ShieldCursor,ShowCursor,TrimRect
| .REF InitRgn,SeekRgn,PatExpand,ColorMap
| .REF XorSlab,DrawSlab,SlabMode,FastSlabMode,MaskTab
| ----------------------------------------------------------------
|
| PROCEDURE DrawArc(dstRect: Rect;
|                   hollow: BOOLEAN;
|                   ovalWidth,ovalHeight,mode: INTEGER;
|                   pat: Pattern;
|                   startAngle,arcAngle: INTEGER);
|
| Routine to draw solid or hollow Ovals, RoundRects or Arcs.
| Backbone for StdOval / StdRRect / StdArc.
|
| Called during boot.
DRAWARC:
    LINK	A6,#-0x142                             | ALLOCATE LOCAL VARS
    MOVEM.L	D0-D7/A1-A5,-(A7)                   | SAVE REGS
    MOVE.L	A7,-0x94(A6)                         | REMEMBER STACK FOR LATER
    MOVE.L	A5,-0xAA(A6)                         | REMEMBER GLOBAL PTR
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A3                             | GET CURRENT GRAFPORT
    TST.W	0x42(A3)                              | IS PNVIS NEG ?
    BLT.W	DRAWARC_GOHOME                        | YES, QUIT
    MOVE.L	A3,-0xAE(A6)                         | SAVE CURRENT GRAFPORT
| -------------------------------------------------------
|
| QUIT IF MODE NOT IN 8..15
|
    MOVEQ.L	#-0x8,D0                            | MASK TO KILL BOTTOM 3 BITS
    AND.W	0x10(A6),D0                           | GET ALL BUT 3 BITS OF MODE
    CMPI.W	#0x8,D0                              | IS PEN MODE 8..15 ?
    BNE.W	DRAWARC_GOHOME                        | NO, QUIT
| ----------------------------------------------------------------
|
| ADJUST MODE AND PATTERN IF COLOR FILTERING.
|
    TST.W	0x58(A3)                              | IS COLORBIT = 0 ?
    BMI.B	NOCOLOR                               | YES, DON'T MAP
    MOVE.W	0x10(A6),-(A7)                       | PUSH INPUT MODE
    MOVE.L	0xC(A6),-(A7)                        | PUSH ADDR OF INPUT PATTERN
    JSR	COLORMAP(PC)                            | ALTER BY THECOLOR, THEFILTER
    MOVE.L	(A7)+,0xC(A6)                        | GET (ALTERED) PATTERN
    MOVE.W	(A7)+,0x10(A6)                       | GET (ALTERED) MODE
NOCOLOR:
    MOVEA.L	A3,A5                               | PUT GRAFPORT IN A5
| ---------------------------------------------------------
|
| GET CLIPRGN AND VISRGN HANDLES AND DE-REFERENCE THEM
|
    MOVEA.L	0x1C(A5),A2                         | GET CLIPRGN HANDLE
    MOVEA.L	(A2),A2                             | GET CLIPRGN POINTER
    MOVEA.L	0x18(A5),A3                         | GET VISRGN HANDLE
    MOVEA.L	(A3),A3                             | GET VISRGN POINTER
| -----------------------------------------------------------------------
|
| CALC MINRECT, THE INTERSECTION OF DSTRECT, BITMAP BOUNDS,
| CLIPRGN BBOX, AND VISRGN BBOX. QUIT IF NO INTERSECTION.
|
    MOVE.L	0x18(A6),-(A7)                       | PUSH DSTRECT
    PEA.L	0x8(A5)                               | PUSH BITMAP BOUNDS
    PEA.L	0x2(A2)                               | PUSH CLIPRGN BBOX
    PEA.L	0x2(A3)                               | PUSH VISRGN BBOX
    MOVE.W	#0x4,-(A7)                           | PUSH NRECTS=4
    PEA.L	-0x48(A6)                             | PUSH DST ADDR
    JSR	RSECT(PC)                               | CALC INTERSECTION
    BEQ.W	DRAWARC_GOHOME                        | QUIT IF NO INTERSECT
|
| CHECK FOR BOTH VISRGN AND CLIPRGN RECTANGULAR
|
    CLR.B	-0xB0(A6)                             | FASTFLAG := FALSE
    CMPI.W	#0xA,(A2)                            | IS CLIPRGN RECTANGULAR ?
    BNE.B	YESFLAG_NO                            | NO, CONTINUE
    CMPI.W	#0xA,(A3)                            | IS VISRGN RECTANGULAR ?
    BEQ.B	CKPAT                                 | YES, CONTINUE
|
| If only visRgn is non-rectangular, then check if
| its intersection with minrect would be rectangular.
| IF TrimRect(visRgn,minRect) then treat as rectangular.
|
    MOVE.L	0x18(A5),-(A7)                       | push rgnHandle
    PEA.L	-0x48(A6)                             | push addr of minRect
    JSR	TRIMRECT(PC)                            | call trimRect
    BLT.W	DRAWARC_GOHOME                        | quit if intersection empty
    BGT.B	YESFLAG_NO                            | continue if non-rectangular
|
| CHECK FOR BLACK OR WHITE PATTERN
|
| Called during boot.
CKPAT:
    MOVEA.L	0xC(A6),A0                          | POINT TO PATTERN
    MOVE.L	(A0)+,D0                             | GET 1ST HALF OF PATTERN
    CMP.L	(A0)+,D0                              | IS IT SAME AS 2ND HALF ?
    BNE.B	YESFLAG_NO                            | NO, CONTINUE
    NOT.L	D0                                    | IS PATTERN BLACK ?
    BEQ.B	YESFLAG                               | YES, WE MADE IT
    NOT.L	D0                                    | IS PATTERN WHITE ?
    BNE.B	YESFLAG_NO                            | NO, CONTINUE
    EORI.W	#0x4,0x10(A6)                        | YES, ALTER MODE AS IF BLACK
YESFLAG:
    ST.B	-0xB0(A6)                              | REMEMBER RECT CLIPPED AND BLACK
|
| fast case: map mode into black,xor,white, or do-nothing
|
    MOVEQ.L	#0x7,D0                             | GET 3 BIT MASK
    AND.W	0x10(A6),D0                           | GET 3 BITS OF MODE
    MOVE.B	YESFLAG_CONT(PC,D0.W),D0             | MAP TO BLACK,XOR,WHITE,NOP
    BMI.W	DRAWARC_GOHOME                        | QUIT IF DO-NOTHING MODE
    MOVE.W	D0,0x10(A6)                          | UPDATE MODE
    BRA.B	YESFLAG_NO                            | AND CONTINUE
| ----------------------------------------------------------
|
| YESFLAG_CONT: 8-byte mode-mapping table (index = mode & 7).
|     0x00,0x00,0x01,0x02,0x02,0xFF,0xFF,0xFF
|     mode 0 (copy)        -> BLACK
|     mode 1 (or)          -> BLACK
|     mode 2 (xor)         -> XOR
|     mode 3 (bic)         -> WHITE
|     mode 4 (notSrcCopy)  -> WHITE
|     mode 5,6,7           -> NOP (negative => quit)
|
YESFLAG_CONT:
    .long	0x00000102
    .long	0x02FFFFFF
| FLAGOK
|
| NOTE WHETHER FULL CIRCLE OR ARC
|
| Called during boot.
YESFLAG_NO:
    CLR.B	-0x11A(A6)                            | clear ARCFLAG
    MOVE.W	0x8(A6),D0                           | GET ARC ANGLE
    BEQ.W	DRAWARC_GOHOME                        | QUIT IF ARC ANGLE = 0
    BPL.B	POSANG                                | IS ANGLE NEG ?
    ADD.W	D0,0xA(A6)                            | YES, ADJUST START ANGLE
    NEG.W	D0                                    | AND MAKE ARC ANGLE POSITIVE
    MOVE.W	D0,0x8(A6)                           | UPDATE INPUT PARAM
POSANG:
    CMPI.W	#0x168,D0                            | IS ARC ANGLE >= 360 ?
    SLT.B	-0x119(A6)                            | REMEMBER FOR LATER (SKIPFLAG)
    BGE.W	NOTARC                                | NO, SKIP SETUP (full-circle case)
| ---------------------------------------------------------------
|
| IF ARCANGLE < 360 THEN SET UP ARC STUFF
|
| TREAT STARTANGLE MOD 360
|
    MOVE.W	0xA(A6),D0                           | GET STARTANGLE
    EXT.L	D0                                    | SIGN EXTEND FOR DIVIDE
    DIVS.W	#0x168,D0                            | TREAT STARTANGLE MOD 360
    SWAP.W	D0                                   | GET THE REMAINDER
    TST.W	D0                                    | WAS IT NEGATIVE ?
    BPL.B	STARTOK                               | NO, CONTINUE
    ADDI.W	#0x168,D0                            | YES, ADD 360 TO MAKE POSITIVE
STARTOK:
    MOVE.W	D0,0xA(A6)                           | REPLACE INPUT PARAM
    ADD.W	0x8(A6),D0                            | CALC STOPANGLE
    CMPI.W	#0x168,D0                            | IS STOPANGLE >= 360 ?
    BLT.B	STOPOK                                | NO, CONTINUE
    SUBI.W	#0x168,D0                            | YES, WRAP AROUND MOD 360
STOPOK:
    MOVE.W	D0,-0x11C(A6)                        | SAVE STOPANGLE FOR LATER
    MOVEA.L	0x18(A6),A0                         | POINT TO DSTRECT
    MOVE.W	(A0),D0                              | GET DSTTOP
    ADD.W	0x4(A0),D0                            | ADD DSTBOTTOM
    ASR.W	#0x1,D0                               | DIVIDE BY 2
    MOVE.W	D0,-0x11E(A6)                        | MID VERT := (DSTBOT+DSTTOP)/2
    MOVE.W	0x2(A0),D0                           | GET DSTLEFT
    ADD.W	0x6(A0),D0                            | ADD DSTRIGHT
    ASR.W	#0x1,D0                               | DIVIDE BY 2
    MOVE.W	D0,-0x120(A6)                        | MID HORIZ := (DSTLEFT+DSTRIGHT)/2
    MOVE.W	0x6(A0),D0                           | GET DSTRIGHT
    SUB.W	0x2(A0),D0                            | SUBTRACT DSTLEFT
    MOVE.W	D0,-0x122(A6)                        | WIDTH := DSTRIGHT - DSTLEFT
    MOVE.W	0x4(A0),D0                           | GET DSTBOTTOM
    SUB.W	(A0),D0                               | SUBTRACT DSTTOP
    MOVE.W	D0,-0x124(A6)                        | HEIGHT := DSTBOTTOM - DSTTOP
    CLR.L	-(A7)                                 | MAKE ROOM FOR FCN RESULT
    MOVE.W	-0x122(A6),-(A7)                     | PUSH WIDTH
    MOVE.W	-0x124(A6),-(A7)                     | PUSH HEIGHT
    _FixRatio                                   | CALC ASPECT RATIO
    MOVE.L	(A7)+,D7                             | SAVE RESULT IN D7
| --------------------------------------------
|
| CALC SLOPE1 FROM STARTANGLE
|
    CLR.L	-(A7)                                 | MAKE ROOM FOR FCN RESULT
    MOVE.W	0xA(A6),-(A7)                        | PUSH STARTANG
    JSR	SLOPEFROMANGLE(PC)                      | CALC SLOPE1
    MOVE.L	(A7)+,D0                             | POP SLOPE1
    CLR.L	-(A7)                                 | ROOM FOR FCN RESULT
    MOVE.L	D0,-(A7)                             | PUSH SLOPE1
    MOVE.L	D7,-(A7)                             | PUSH ASPECT RATIO
    _FixMul                                     | scale slope1
    MOVE.L	(A7)+,-0x128(A6)                     | SAVE RESULT FOR LATER
| --------------------------------------------
|
| CALC SLOPE2 FROM STOPANGLE
|
    CLR.L	-(A7)                                 | MAKE ROOM FOR FCN RESULT
    MOVE.W	-0x11C(A6),-(A7)                     | PUSH STOPANGLE
    JSR	SLOPEFROMANGLE(PC)                      | CALC SLOPE2
    MOVE.L	(A7)+,D0                             | POP SLOPE2
    CLR.L	-(A7)                                 | ROOM FOR FCN RESULT
    MOVE.L	D0,-(A7)                             | PUSH SLOPE
    MOVE.L	D7,-(A7)                             | PUSH ASPECT RATIO
    _FixMul                                     | SCALE SLOPE2
    MOVE.L	(A7)+,-0x12C(A6)                     | SAVE RESULT FOR LATER
| ---------------------------------------------------------
|
| CALC HORIZ COORDS OF LINE1 AND LINE2 AT TOP OF DSTRECT
|
    MOVE.W	-0x120(A6),D6                        | GET MIDHORIZ
    SWAP.W	D6                                   | PUT MIDHORIZ IN HI WORD
    CLR.W	D6                                    | CALC MIDHORIZ*64K
    MOVE.W	-0x124(A6),D7                        | GET HEIGHT
    LSR.W	#0x1,D7                               | CALC HEIGHT DIV 2
    MOVE.W	-0x126(A6),D0                        | GET SLOPE1 LO WORD
    MULU.W	D7,D0                                | CALC LO PARTIAL PRODUCT
    MOVE.L	D0,-0x130(A6)                        | ACCUMULATE IT
    MOVE.W	-0x128(A6),D0                        | GET SLOPE1 HI WORD
    MULS.W	D7,D0                                | CALC HI PARTIAL PRODUCT
    ADD.W	D0,-0x130(A6)                         | ADD HI PRODUCT TO ACCUMULATOR
    MOVE.L	D6,D0                                | COPY MIDHORIZ*64K
    SUB.L	-0x130(A6),D0                         | CALC MIDH*64K-SLOPE*(HT DIV 2)
    MOVE.L	D0,-0x130(A6)                        | STORE AS LINE1 HORIZ AT TOP
    MOVE.W	-0x12A(A6),D0                        | GET SLOPE2 LO WORD
    MULU.W	D7,D0                                | CALC LO PARTIAL PRODUCT
    MOVE.L	D0,-0x134(A6)                        | ACCUMULATE IT
    MOVE.W	-0x12C(A6),D0                        | GET SLOPE2 HI WORD
    MULS.W	D7,D0                                | CALC HI PARTIAL PRODUCT
    ADD.W	D0,-0x134(A6)                         | ADD HI PRODUCT TO ACCUMULATOR
    SUB.L	-0x134(A6),D6                         | CALC MIDH*64K-SLOPE*(HT DIV 2)
    MOVE.L	D6,-0x134(A6)                        | STORE AS LINE2 HORIZ AT TOP
| ----------------------------------------------------------
|
| SET UP FLAG1 AND FLAG2 TO TELL WHICH HALF EACH LINE IS ACTIVE IN:
| CODE IS: NEG = ACTIVE IN TOP, POS = ACTIVE IN BOTTOM, 0 = HORIZONTAL
|
    MOVE.W	0xA(A6),D0                           | GET STARTANGLE
    CMPI.W	#0xB4,D0                             | IS STARTANGLE >= 180 ?
    BGE.B	STOPOK_OK                             | YES, USE 270 BASE
    SUBI.W	#0x5A,D0                             | FLAG1 := STARTANGLE - 90
    BRA.B	STOPOK_CONT                           | CONTINUE
| ----------------------------------------------------------
|
| STOPOK_OK
|
STOPOK_OK:
    SUBI.W	#0x10E,D0                            | SUBTRACT 270
    NEG.W	D0                                    | FLAG1 := 270-STARTANGLE
STOPOK_CONT:
    MOVE.W	D0,-0x136(A6)                        | SAVE FLAG1
    MOVE.W	-0x11C(A6),D0                        | GET STOPANGLE
    CMPI.W	#0xB4,D0                             | IS STOPANGLE >= 180 ?
    BGE.B	STOPOK_OK_2                           | YES, USE 270 BASE
    SUBI.W	#0x5A,D0                             | FLAG2 := STOPANGLE - 90
    BRA.B	STOPOK_CONT_2                         | CONTINUE
| ----------------------------------------------------------
|
| STOPOK_OK_2
|
STOPOK_OK_2:
    SUBI.W	#0x10E,D0                            | SUBTRACT 270
    NEG.W	D0                                    | FLAG2 := 270-STOPANGLE
STOPOK_CONT_2:
    MOVE.W	D0,-0x138(A6)                        | save FLAG2
|
| Set up SKIPFLAG to skip over unused arc portions
|
    MOVE.W	0x8(A6),D0                           | get ArcAngle
    CMPI.W	#0xB4,D0                             | is ArcAngle > 180 ?
    BGT.B	NOTARC                                | skip if angle > 180
    BLT.B	ACUTE                                 | deal with acute angle
    CMPI.W	#0x5A,0xA(A6)                        | is StartAngle = 90 ?
    SEQ.B	-0x11A(A6)                            | so skip if start=90
    BRA.B	NOTARC                                | continue to oval init
| ----------------------------------------------------------
|
| ACUTE -- arc spans <= 180 degrees
|
ACUTE:
    MOVE.W	-0x136(A6),D0                        | get FLAG1
    OR.W	-0x138(A6),D0                          | OR with FLAG2
    SPL.B	-0x11A(A6)                            | SKIP := FLAG1 AND FLAG2 both >= 0
| ---------------------------------------------------------------
|
| INIT OUTER OVAL STATE RECORD
|
NOTARC:
    MOVEA.L	0x18(A6),A0                         | point to dstRect
    LEA.L	-0x114(A6),A1                         | point to outer oval record
    MOVE.W	0x12(A6),D1                          | get OvalHeight
    MOVE.W	0x14(A6),D2                          | get OvalWidth
    JSR	INITOVAL(PC)                            | initialize outer oval record
    MOVE.W	0x12(A6),D0                          | get OvalHeight
    ASR.W	#0x1,D0                               | calc OvalHeight DIV 2
    ADD.W	-0x114(A6),D0                         | add outer oval top
    MOVE.W	D0,-0x116(A6)                        | save SkipTop
    MOVEA.L	0x18(A6),A0                         | point to dstRect
    ADD.W	0x4(A0),D0                            | add bottom
    SUB.W	(A0),D0                               | subtract top
    SUB.W	0x12(A6),D0                           | subtract OvalHeight
    MOVE.W	D0,-0x118(A6)                        | save SkipBot
    MOVE.W	#0x7FFF,-0xE6(A6)                    | init inner oval top to max
| ---------------------------------------------------
|
| If this is a hollow oval, then calc dstRect inset by PenSize,
| and init innerOval. (If innerOval empty, switch to solid).
|
    TST.B	0x16(A6)                              | is HollowFlag true ?
    BEQ.B	SOLID                                 | no, skip inner oval (SOLID)
    MOVEA.L	0x18(A6),A0                         | point to dstRect
    MOVEM.W	(A0),D0-D3                          | get top, left, bottom, right
    MOVE.L	0x34(A5),D4                          | get thePort^.PnSize
    ADD.W	D4,D1                                 | left := dstLeft + penWidth
    SUB.W	D4,D3                                 | right := dstRight - penWidth
    CMP.W	D3,D1                                 | is left >= right ?
    BGE.B	SOLID                                 | yes, empty rect (SOLID)
    SWAP.W	D4                                   | get PnSize.v
    ADD.W	D4,D0                                 | top := dstTop + penHeight
    SUB.W	D4,D2                                 | bottom := dstBottom - penHeight
    CMP.W	D2,D0                                 | is top >= bottom ?
    BGE.B	SOLID                                 | yes, empty rect (SOLID)
    MOVEM.W	D0-D3,-0xB8(A6)                     | save inset rect in TempRect
    LEA.L	-0xB8(A6),A0                          | point to dstRect inset by PenSize
    LEA.L	-0xE6(A6),A1                          | point to inner oval record
    MOVE.W	0x12(A6),D1                          | get outer OvalHeight
    SUB.W	D4,D1                                 | inner height := outer - 2*penHeight
    SUB.W	D4,D1                                 | subtract 2nd penHeight
    MOVE.W	0x14(A6),D2                          | get outer OvalWidth
    SWAP.W	D4                                   | get pen width
    SUB.W	D4,D2                                 | inner width := outer - 2*penWidth
    SUB.W	D4,D2                                 | subtract 2nd penWidth
    JSR	INITOVAL(PC)                            | initialize inner oval record
| ----------------------------------------------------------------
|
| HIDE CURSOR IF CURSOR INTERSECTS MINRECT
| (SOLID entry point: skip InnerOval setup)
|
SOLID:
    PEA.L	-0x48(A6)                             | push ShieldRect parameter
    MOVE.L	0x8(A5),-(A7)                        | push portBits.bounds.topLeft
    MOVEA.L	-0xAA(A6),A5                        | get global ptr
    JSR	SHIELDCURSOR(PC)                        | hide cursor if it intersects
    MOVEA.L	-0xAE(A6),A5                        | restore GrafPort in A5
    MOVE.W	-0x46(A6),D2                         | get MinRect left
    SUB.W	0xA(A5),D2                            | subtract portBits.bounds.left
    ANDI.W	#0xFFF0,D2                           | round down to mult of 16
    ADD.W	0xA(A5),D2                            | add back bounds.left
| ------------------------------------
|
| Calc BufLeft
|
    MOVE.W	D2,-0x9C(A6)                         | save as BufLeft
|
| If FastFlag, then skip region setup
|
    TST.B	-0xB0(A6)                             | rect clipped and black ?
    BNE.W	CLRMASK_SKIP                          | yes, don't waste time with setup
    MOVE.W	-0x42(A6),D0                         | get MinRect right
|
| Calc BufSize
|
    SUB.W	D2,D0                                 | calc maxH-BufLeft
    LSR.W	#0x5,D0                               | div by 32 for longs
    MOVE.W	D0,-0x9E(A6)                         | BufSize = # longs - 1
| -------------------------------------------------------------------------
|
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK
|
CLRMASK:
    CLR.L	-(A7)                                 | allocate and clear one long
    DBF.W	D0,CLRMASK                            | loop till done
    MOVE.L	A7,-0x9A(A6)                         | remember where MaskBuf is
| -------------------------------------------------------------------------
|
| INIT STATE RECORDS AND ALLOCATE BUFFERS FOR EACH NON-RECTANGULAR REGION
|
    CLR.W	D5                                    | init both are rect
    MOVE.W	#0x8001,-0x52(A6)                    | StateA NextV := -32767
    MOVE.W	#0x7FFF,-0x50(A6)                    | StateA EndV := 32767
    CMPI.W	#0xA,(A2)                            | is clipRgn rectangular ?
    BEQ.B	CLRMASK_OK                            | yes, continue
    ADDQ.W	#0x2,D5                              | flag clipRgn non-rect
    MOVEA.L	A2,A0                               | point to clipRgn
    LEA.L	-0x60(A6),A1                          | point to state record A
    BSR.B	CLRMASK_CONT                          | init state, alloc buffer
CLRMASK_OK:
    MOVE.W	#0x8001,-0x6A(A6)                    | StateB NextV := -32767
    MOVE.W	#0x7FFF,-0x68(A6)                    | StateB EndV := 32767
    CMPI.W	#0xA,(A3)                            | is visRgn rectangular ?
    BEQ.B	CLRMASK_EXIT                          | yes, continue
    ADDQ.W	#0x4,D5                              | flag visRgn non-rect
    MOVEA.L	A3,A0                               | point to visRgn
    LEA.L	-0x78(A6),A1                          | point to state record B
    PEA.L	CLRMASK_EXIT(PC)                      | push fake return addr
| CLRMASK_CONT -- init state, alloc buffer.
CLRMASK_CONT:
    MOVE.W	-0x46(A6),D0                         | get MinRect left
    MOVE.W	-0x42(A6),D1                         | get MinRect right
    MOVE.W	-0x9C(A6),D2                         | get BufLeft
    JMP	INITRGN(PC)                             | init state, alloc buffer
| ----------------------------------------------------------
|
| CLRMASK_EXIT -- if both regions are rectangular,
| then draw MinRect into mask buffer.
|
CLRMASK_EXIT:
    MOVE.W	D5,-0x96(A6)                         | save RectFlag
    BNE.B	CLRMASK_SKIP                          | no, continue
    MOVEA.L	-0x9A(A6),A0                        | yes, point to mask buffer
    MOVE.W	-0x46(A6),D3                         | get MinRect left
    SUB.W	-0x9C(A6),D3                          | make it buffer relative
    MOVE.W	-0x42(A6),D4                         | get MinRect right
    SUB.W	-0x9C(A6),D4                          | make it buffer relative
    JSR	XORSLAB(PC)                             | and XOR between them
CLRMASK_SKIP:
    MOVE.W	-0x48(A6),D1                         | get MinRect top
    SUB.W	0x8(A5),D1                            | subtract bounds.top
    MULU.W	0x6(A5),D1                           | mult by rowBytes
    ADD.L	0x2(A5),D1                            | add baseAddr
    SUB.W	0xA(A5),D2                            | subtract bounds.left
| ------------------------------------
|
| Calc starting dstLeft
|
    LSR.W	#0x3,D2                               | calc BufLeft DIV 8
    EXT.L	D2                                    | clr hi word
    ADD.L	D2,D1                                 | add horiz byte offset
    MOVE.L	D1,-0xA6(A6)                         | save as DstLeft
| ----------------------------------------------------
|
| Make all horizontal coordinates relative to buffer
|
    MOVE.W	-0x9C(A6),D1                         | get BufLeft
    SUB.W	D1,-0x46(A6)                          | MinRect.left -= BufLeft
    SUB.W	D1,-0x42(A6)                          | MinRect.right -= BufLeft
    SUB.W	D1,-0xF2(A6)                          | outer leftEdge -= BufLeft
    SUB.W	D1,-0xEE(A6)                          | outer rightEdge -= BufLeft
    SUB.W	D1,-0xC4(A6)                          | inner leftEdge -= BufLeft
    SUB.W	D1,-0xC0(A6)                          | inner rightEdge -= BufLeft
    SUB.W	D1,-0x130(A6)                         | LINE1 -= BufLeft
    SUB.W	D1,-0x134(A6)                         | LINE2 -= BufLeft
| ---------------------------------------------------
|
| Set up case jump based on mode and FastFlag
|
    MOVE.W	0x10(A6),D2                          | get (altered) pen mode
    TST.B	-0xB0(A6)                             | rect clipped and black ?
    BEQ.B	CLRMASK_NO                            | no, use normal slab mode
    JSR	FASTSLABMODE(PC)                        | yes, get fast modeCase in A4
    MOVE.L	A4,-0xA2(A6)                         | save for later
    CLR.W	-0x142(A6)                            | make unused PatIndex even
    BRA.W	GOFORIT                               | skip pattern stuff
| ----------------------------------------------------------
|
| CLRMASK_NO -- normal mode: get mode case + expand pattern
|
CLRMASK_NO:
    JSR	SLABMODE(PC)                            | get normal modeCase in A4
    MOVE.L	A4,-0xA2(A6)                         | save for later
| ------------------------------------------------------------------
|
| EXPAND 8 BYTE PATTERN TO 16 LONGS AND INIT PATTERN SELECTOR
|
    MOVEQ.L	#0x0,D7                             | say not inverted
    MOVE.W	0x10(A6),D2                          | get mode
    BCLR	#0x2,D2                                | test and clr invert bit
    BEQ.B	CLRMASK_SKIP_2                        | skip if not inverted
    NOT.L	D7                                    | inverted; D7 gets all 1's
CLRMASK_SKIP_2:
    MOVE.W	0xA(A5),D2                           | get portBits.bounds.left
    MOVEA.L	0xC(A6),A0                          | point to byte-wide pattern
    LEA.L	-0x40(A6),A1                          | point to expanded pattern
    MOVEA.L	-0xAA(A6),A5                        | get global ptr
    JSR	PATEXPAND(PC)                           | expand 8-byte pattern to 16 longs
    MOVEA.L	-0xAE(A6),A5                        | restore GrafPort in A5
    MOVEQ.L	#0xF,D0                             | treat coord MOD 16
    AND.W	-0x48(A6),D0                          | MinRect.top MOD 16
    LSL.W	#0x2,D0                               | quad for 4-byte patterns
    MOVE.W	D0,-0x142(A6)                        | set up pattern index
GOFORIT:
    MOVE.W	-0x114(A6),D7                        | get outer oval top as VERT
| ------------------------------------------------------------
|
| BUMP OVAL STATE RECORDS UNLESS VERT IS BETWEEN SKIPTOP AND SKIPBOT
|
| Called during boot.
DRAWARC_NEXTROW:
    CMP.W	-0x116(A6),D7                         | is VERT < SkipTop ?
    BLT.B	YESBUMP                               | yes, OK to bump ovals
    CMP.W	-0x118(A6),D7                         | is VERT >= SkipBot ?
    BLT.B	NOBUMP                                | no, skip bumping
YESBUMP:
    MOVE.W	D7,-(A7)                             | stash current VERT
    MOVE.W	D7,D0                                | copy current vertical
    LEA.L	-0x114(A6),A3                         | point to outer oval state record
    JSR	BUMPOVAL(PC)                            | bump it to next scanline
    MOVE.W	(A7),D0                              | copy current VERT
    LEA.L	-0xE6(A6),A3                          | point to inner oval state record
    JSR	BUMPOVAL(PC)                            | bump it to next scanline
    MOVE.W	(A7)+,D7                             | recover saved current VERT
| --------------------------------------------------
|
| ADJUST ARC STUFF AS WE CROSS THE MIDDLE VERTICALLY
|
NOBUMP:
    CMP.W	-0x11E(A6),D7                         | is current VERT = MidVert ?
    BNE.B	ACUTE1_SKIP_2                         | no, continue
    TST.B	-0x119(A6)                            | are we doing an arc ?
    BEQ.B	ACUTE1_SKIP_2                         | no, skip
    NEG.W	-0x136(A6)                            | yes, invert flags as we cross
    NEG.W	-0x138(A6)                            | invert FLAG2
|
| Re-calculate SKIPFLAG, and quit if it becomes true
|
    CLR.B	-0x11A(A6)                            | reset SkipFlag
    MOVE.W	0x8(A6),D0                           | get ArcAngle
    CMPI.W	#0xB4,D0                             | is ArcAngle > 180 ?
    BGT.B	ACUTE1_SKIP                           | skip if angle > 180
    BLT.B	ACUTE1                                | deal with acute angle
    CMPI.W	#0x10E,0xA(A6)                       | is StartAngle = 270 ?
    BNE.B	ACUTE1_SKIP                           | no, continue
    BRA.W	DRAWARC_DONE                          | yes, we're all done
| ----------------------------------------------------------
|
| ACUTE1 -- arc spans <= 180 degrees, post-mid case
|
ACUTE1:
    MOVE.W	-0x136(A6),D0                        | get FLAG1
    OR.W	-0x138(A6),D0                          | OR with FLAG2
    BPL.W	DRAWARC_DONE                          | quit if both FLAG1 and FLAG2 >= 0
| OBTUSE1
|
| NOW SWAP THE ROLES OF LINE1 AND LINE2 AS THEY CROSS THE MIDDLE
|
ACUTE1_SKIP:
    MOVE.W	-0x136(A6),D0                        | swap FLAG1 and FLAG2
    MOVE.W	-0x138(A6),-0x136(A6)                | FLAG1 := old FLAG2
    MOVE.W	D0,-0x138(A6)                        | FLAG2 := old FLAG1
    MOVE.L	-0x130(A6),D0                        | swap LINE1 and LINE2
    MOVE.L	-0x134(A6),-0x130(A6)                | LINE1 := old LINE2
    MOVE.L	D0,-0x134(A6)                        | LINE2 := old LINE1
    MOVE.L	-0x128(A6),D0                        | swap SLOPE1 and SLOPE2
    MOVE.L	-0x12C(A6),-0x128(A6)                | SLOPE1 := old SLOPE2
    MOVE.L	D0,-0x12C(A6)                        | SLOPE2 := old SLOPE1
ACUTE1_SKIP_2:
    CMP.W	-0x48(A6),D7                          | is VERT < MinRect.top ?
    BLT.W	NODRAW                                | yes, don't draw
    TST.B	-0x11A(A6)                            | are we skipping ?
    BNE.W	DOSLAB_SKIP                           | yes, skip
| ------------------------------------------------
|
| Seek mask to the current vertical, and
| branch based on solid or hollow oval or arc.
|
    TST.B	-0xB0(A6)                             | rect clipped and black ?
    BNE.B	NOMASK                                | yes, don't bother with mask
    BSR.W	DRAWARC_GOHOME_CONT                   | make MaskBuf current
NOMASK:
    TST.B	-0x119(A6)                            | are we doing an arc ?
    BNE.B	NOMASK_OK                             | yes, go to it
    CMP.W	-0xE6(A6),D7                          | is VERT < inner oval top ?
    BLT.W	SOVAL                                 | no, treat as solid oval
    CMP.W	-0xE4(A6),D7                          | is VERT >= inner oval bot ?
    BGE.W	SOVAL                                 | no, treat as solid oval
    BRA.W	HOVAL                                 | yes, process hollow oval
| ----------------------------------------------------------
|
| NOMASK_OK -- solid or hollow arc: calc OuterLeft and OuterRight
|
NOMASK_OK:
    MOVE.W	-0xF2(A6),D1                         | D1 := outer leftEdge
    TST.W	-0x136(A6)                            | is LINE1 active ?
    BPL.B	NOMASK_SKIP                           | no, skip LINE1 clip
    CMP.W	-0x130(A6),D1                         | is leftEdge < LINE1 ?
    BGE.B	NOMASK_SKIP                           | no, keep leftEdge
    MOVE.W	-0x130(A6),D1                        | yes, clip to LINE1
NOMASK_SKIP:
    MOVE.W	D1,-0x13A(A6)                        | save OuterLeft
    MOVE.W	-0xEE(A6),D2                         | D2 := outer rightEdge
    TST.W	-0x138(A6)                            | is LINE2 active ?
    BPL.B	NOMASK_SKIP_2                         | no, skip LINE2 clip
    CMP.W	-0x134(A6),D2                         | is rightEdge > LINE2 ?
    BLE.B	NOMASK_SKIP_2                         | no, keep rightEdge
    MOVE.W	-0x134(A6),D2                        | yes, clip to LINE2
NOMASK_SKIP_2:
    MOVE.W	D2,-0x13C(A6)                        | save OuterRight
    CMP.W	-0xE6(A6),D7                          | is VERT < inner oval top ?
    BLT.W	SARC                                  | no, process solid arc
    CMP.W	-0xE4(A6),D7                          | is VERT >= inner oval bot ?
    BGE.W	SARC                                  | no, process solid arc
    MOVE.W	-0xC4(A6),D0                         | get inner leftEdge
| --------------------------------------------------
|
| HOLLOW ARC: CALC INNERLEFT AND INNERRIGHT
|
    TST.W	-0x138(A6)                            | is LINE2 active ?
    BPL.B	NOMASK_SKIP_3                         | no, skip LINE2 clip
    CMP.W	-0x134(A6),D0                         | is leftEdge > LINE2 ?
    BLE.B	NOMASK_SKIP_3                         | no, keep leftEdge
    MOVE.W	-0x134(A6),D0                        | yes, clip to LINE2
NOMASK_SKIP_3:
    MOVE.W	D0,-0x13E(A6)                        | save InnerLeft
    MOVE.W	-0xC0(A6),D0                         | get inner rightEdge
    TST.W	-0x136(A6)                            | is LINE1 active ?
    BPL.B	NOMASK_SKIP_4                         | no, skip LINE1 clip
    CMP.W	-0x130(A6),D0                         | is rightEdge < LINE1 ?
    BGE.B	NOMASK_SKIP_4                         | no, keep rightEdge
    MOVE.W	-0x130(A6),D0                        | yes, clip to LINE1
NOMASK_SKIP_4:
    MOVE.W	D0,-0x140(A6)                        | save InnerRight
| --------------------------------------------------
|
| If OuterLeft < OuterRight then paint two slabs
|
    CMP.W	D2,D1                                 | is OuterLeft < OuterRight ?
    BGE.B	NOMASK_NO                             | no, try obtuse case
    MOVE.W	-0x13E(A6),D2                        | D2 := InnerLeft
    BSR.B	ONESLAB                               | draw left slab
    MOVE.W	-0x140(A6),D1                        | D1 := InnerRight
    MOVE.W	-0x13C(A6),D2                        | D2 := OuterRight
    BRA.W	DOSLAB                                | draw right slab
|
| ELSE IF BOTH LINES ACTIVE AND ANGLE > 180 THEN PAINT TWO OR THREE SLABS
|
NOMASK_NO:
    MOVE.W	-0x136(A6),D0                        | get FLAG1
    AND.W	-0x138(A6),D0                         | are both lines active ?
    BPL.W	DOSLAB_SKIP                           | no, continue
    CMPI.W	#0xB4,0x8(A6)                        | is ArcAngle > 180 ?
    BLE.W	DOSLAB_SKIP                           | no, continue
    CMP.W	-0x13E(A6),D2                         | is InnerLeft = OuterRight ?
    BNE.B	NOMASK_NO_2                           | no, continue
    MOVE.W	-0xC4(A6),D2                         | use inner leftEdge instead
    BRA.B	NOMASK_CONT                           | draw merged slab
| ----------------------------------------------------------
|
| NOMASK_NO_2 -- not three slabs, try two
|
NOMASK_NO_2:
    MOVE.W	-0x13A(A6),D0                        | get OuterLeft
    CMP.W	-0x140(A6),D0                         | is InnerRight = OuterLeft ?
    BNE.B	NOMASK_NO_3                           | no, continue
    MOVE.W	-0xC0(A6),D1                         | use inner rightEdge instead
    MOVE.W	-0x13C(A6),D2                        | D2 := OuterRight
| NOT3
NOMASK_CONT:
    BSR.B	ONESLAB                               | draw merged slab
NOMASK_NO_3:
    MOVE.W	-0xF2(A6),D1                         | D1 := outer leftEdge
    MOVE.W	-0x13E(A6),D2                        | D2 := InnerLeft
    BSR.B	ONESLAB                               | draw left slab
    MOVE.W	-0x140(A6),D1                        | D1 := InnerRight
    MOVE.W	-0xEE(A6),D2                         | D2 := outer rightEdge
    BRA.B	DOSLAB                                | draw right slab
| ---------------------------------------------------------
|
| LOCAL PROCEDURE TO SET UP AND DRAW ONE SLAB
|
| Called by: HOVAL, NOMASK_SKIP_4, NOMASK_CONT, NOMASK_NO_3, SARC (and 1 more)
ONESLAB:
    MOVEQ.L	#0x3F,D6                            | get wrap-around mask
    AND.W	-0x142(A6),D6                         | get PatIndex MOD 64
    MOVE.L	-0x40(A6,D6.W),D6                    | get expanded pattern long
    LEA.L	MASKTAB(PC),A0                        | point to mask table
    MOVEA.L	-0xA6(A6),A1                        | init DstPtr to left
    MOVEA.L	-0x9A(A6),A2                        | init MaskPtr to left
    LEA.L	-0x48(A6),A3                          | point to MinRect
    MOVEA.L	-0xA2(A6),A4                        | get mode case jump
    JMP	DRAWSLAB(PC)                            | draw one horizontal slab
| ----------------------------------------------------
|
| SOLID ARC: IF OUTERLEFT < OUTERRIGHT THEN PAINT ONE SLAB
|
SARC:
    CMP.W	D2,D1                                 | is OuterLeft < OuterRight ?
    BLT.B	DOSLAB                                | yes, do one slab between them
|
| ELSE IF BOTH LINES ACTIVE AND ANGLE > 180 THEN PAINT TWO SLABS
|
    MOVE.W	-0x136(A6),D0                        | get FLAG1
    AND.W	-0x138(A6),D0                         | are both lines active ?
    BPL.B	DOSLAB_SKIP                           | no, continue
    CMPI.W	#0xB4,0x8(A6)                        | is ArcAngle > 180 ?
    BLE.B	DOSLAB_SKIP                           | no, continue
    MOVE.W	-0xF2(A6),D1                         | D1 := outer leftEdge
    BSR.B	ONESLAB                               | draw left slab
    MOVE.W	-0x13A(A6),D1                        | D1 := OuterLeft (LINE1 clipped)
    MOVE.W	-0xEE(A6),D2                         | D2 := outer rightEdge
    BRA.B	DOSLAB                                | draw right slab
| ----------------------------------------------------------
|
| HOVAL -- hollow oval: draw two slabs between outer and inner ovals
|
HOVAL:
    MOVE.W	-0xF2(A6),D1                         | D1 := outer leftEdge
    MOVE.W	-0xC4(A6),D2                         | D2 := inner leftEdge
    BSR.B	ONESLAB                               | draw horiz slab between them
    MOVE.W	-0xC0(A6),D1                         | D1 := inner rightEdge
    MOVE.W	-0xEE(A6),D2                         | D2 := outer rightEdge
    BSR.B	ONESLAB                               | draw horiz slab between them
    BRA.B	DOSLAB_SKIP                           | skip to next row
| ----------------------------------------------------------
|
| SOVAL -- solid oval: draw one slab between left and right edges of outer oval
|
SOVAL:
    MOVE.W	-0xF2(A6),D1                         | D1 := outer leftEdge
    MOVE.W	-0xEE(A6),D2                         | D2 := outer rightEdge
| ----------------------------------------------------
|
| DOSLAB -- emit one horizontal slab and bump per-row state
|
DOSLAB:
    BSR.B	ONESLAB                               | draw the slab
| -------------------------------------------------------------
|
| Bump pattern index, dstPtr, line endpoints to next scanline
|
| Called by: NOMASK_NO, SARC, ACUTE1_SKIP_2, HOVAL
DOSLAB_SKIP:
    ADDQ.W	#0x4,-0x142(A6)                      | bump PatIndex by one row
    MOVE.W	0x6(A5),D0                           | get rowBytes
    EXT.L	D0                                    | extend to long
    ADD.L	D0,-0xA6(A6)                          | DstLeft += rowBytes
NODRAW:
    MOVE.L	-0x128(A6),D0                        | get SLOPE1
    ADD.L	D0,-0x130(A6)                         | LINE1 += SLOPE1
    MOVE.L	-0x12C(A6),D0                        | get SLOPE2
    ADD.L	D0,-0x134(A6)                         | LINE2 += SLOPE2
    ADDQ.W	#0x1,D7                              | bump VERT
    CMP.W	-0x44(A6),D7                          | is VERT < MinRect.bottom ?
    BLT.W	DRAWARC_NEXTROW                       | yes, do another row
| ---------------------------------------------------------
|
| DRAWARC_DONE -- show cursor and unwind
|
DRAWARC_DONE:
    MOVEA.L	-0xAA(A6),A5                        | get global ptr
    JSR	SHOWCURSOR(PC)                          | show the cursor
| ---------------------------------------------------------
|
| DRAWARC_GOHOME -- restore stack and return to caller
|
| Called by: DRAWARC, NOCOLOR, YESFLAG, YESFLAG_NO
DRAWARC_GOHOME:
    MOVEA.L	-0x94(A6),A7                        | restore stack ptr
    MOVEM.L	(A7)+,D0-D7/A1-A5                   | restore registers
    UNLK	A6                                     | unlink frame
    MOVEA.L	(A7)+,A0                            | get return addr
    ADDA.W	#0x14,A7                             | strip parameters from stack
    JMP	(A0)                                    | tail-call return from DRAWARC_GOHOME via A0
| -----------------------------------------------------------------------------
|
| LOCAL ROUTINE TO UPDATE THE MASK BUFFER
| BASED ON WHICH REGIONS ARE RECTANGULAR
|
DRAWARC_GOHOME_CONT:
    MOVE.W	D7,D0                                | SeekMask: get current vert coord
    MOVE.W	-0x96(A6),D1                         | get RectFlag = 0,2,4
    MOVE.W	DRAWARC_GOHOME_CONT_2(PC,D1.W),D1    | get branch offset
    JMP	DRAWARC_GOHOME_CONT_2(PC,D1.W)          | dispatch on RectFlag
| ----------------------------------------------------------
|
| DRAWARC_GOHOME_CONT_2 - indexed branch table for DrawArc region masking modes
|
| Branch offsets: BOTH RECT, A ONLY, B ONLY, BOTH NON-RECT
DRAWARC_GOHOME_CONT_2:
    .short	0x0016
    .long	0x00080018
    .short	0x001E
|
| ONLY REGION A IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
DRAWARC_GOHOME_CONT_3:
    LEA.L	-0x60(A6),A1                          | POINT TO STATEA
| JSRSEEK - call SeekRgn(StateA), store buffer pointer as scan mask
JSRSEEK:
    JSR	SEEKRGN(PC)                             | seek region to current vert
    MOVE.L	0x8(A1),-0x9A(A6)                    | use region buf as mask
JSRSEEK_CONT:
    RTS                                         | ignore
|
| ONLY REGION B IS NON RECTANGULAR. UPDATE IT AND USE IT AS THE MASK
|
JSRSEEK_CONT_2:
    LEA.L	-0x78(A6),A1                          | point to StateB
    BRA.B	JSRSEEK                               | seek and use as mask
|
| REGIONS A AND B ARE NON-RECTANGULAR. UPDATE EACH,
| THEN FORM INTERSECTION IN THE MASK BUFFER.
|
JSRSEEK_CONT_3:
    LEA.L	-0x60(A6),A1                          | point to StateA
    JSR	SEEKRGN(PC)                             | seek clipRgn to current vert
    LEA.L	-0x78(A6),A1                          | point to StateB
    JSR	SEEKRGN(PC)                             | seek visRgn to current vert
    MOVEA.L	-0x58(A6),A0                        | get StateA scanBuf ptr
    MOVEA.L	-0x70(A6),A1                        | get StateB scanBuf ptr
    MOVEA.L	-0x9A(A6),A2                        | get MaskBuf ptr
    MOVE.W	-0x9E(A6),D1                         | get BufSize (loop count)
ABLOOP:
    MOVE.L	(A0)+,D0                             | get next clipRgn long
    AND.L	(A1)+,D0                              | intersect with visRgn
    MOVE.L	D0,(A2)+                             | store in MaskBuf
    DBF.W	D1,ABLOOP                             | loop for all longs
    RTS                                         | return from ABLOOP
| ------------------------------------------------------------
|
| PROCEDURE InitOval(dstRect: Rect; VAR oval: OvalRec;
|                    ovalWidth, ovalHeight: INTEGER);
|
| Initialize an oval state record to fit the given rectangle.
|
| INPUTS:  A0: dstRect
|          A1: ovalRec
|          D1: ovalHeight
|          D2: ovalWidth
|
| CLOBBERS D0,D1,D2
|
INITOVAL:
    MOVE.W	(A0),(A1)                            | init oval top to dstRect top
    MOVE.W	0x4(A0),0x2(A1)                      | init oval bottom
| -----------------------------------------------------------
|
| Clamp negative widths/heights to zero
|
    TST.W	D2                                    | is OvalWidth negative ?
    BPL.B	OK1                                   | no, continue
    CLR.W	D2                                    | yes, pin it to 0
OK1:
    TST.W	D1                                    | is OvalHeight negative ?
    BPL.B	OK1_NO                                | no, continue
    CLR.W	D1                                    | yes, pin it to 0
| ----------------------------------------------------------
|
| Check OvalWidth and OvalHeight, trim if bigger than dstRect
|
OK1_NO:
    MOVE.W	0x6(A0),D0                           | get dstRect right
    SUB.W	0x2(A0),D0                            | calc dstRect width
    CMP.W	D0,D2                                 | is OvalWidth > DstWidth ?
    BLE.B	INITOVAL_OK3                          | no, continue
    MOVE.W	D0,D2                                | yes, OvalWidth := DstWidth
INITOVAL_OK3:
    MOVE.W	0x4(A0),D0                           | get dstRect bottom
    SUB.W	(A0),D0                               | calc dstRect height
    CMP.W	D0,D1                                 | is OvalHeight > DstHeight ?
    BLE.B	INITOVAL_OK3_NO                       | no, continue
    MOVE.W	D0,D1                                | yes, OvalHeight := DstHeight
| -----------------------------------------------------------
|
| Set up oval left edge and oval right edge as fixed-point numbers
|
INITOVAL_OK3_NO:
    MOVE.W	0x6(A0),0x26(A1)                     | rightEdge.hi := dstRight
    CLR.W	0x28(A1)                              | rightEdge.lo := 0
    MOVE.W	0x2(A0),0x22(A1)                     | leftEdge.hi := dstLeft
    CLR.W	0x24(A1)                              | leftEdge.lo := 0
    MOVE.W	D2,D0                                | get oval width
    SWAP.W	D0                                   | put in hi word
    CLR.W	D0                                    | clear lo word for fixed point
    LSR.L	#0x1,D0                               | calc oval width DIV 2
    ADD.L	D0,0x22(A1)                           | add OvalWd/2 to leftEdge
    SUB.L	D0,0x26(A1)                           | subtract OvalWd/2 from rightEdge
    MOVE.L	#0x8000,D0                           | get fixed point 1/2
    MOVE.L	D0,0x2A(A1)                          | save in oval state record
    ADD.L	D0,0x26(A1)                           | bias right edge +1/2
| INIT OvalY TO -OvalHeight + 1 (scaled by 2, biased 1/2 scanline)
    MOVEQ.L	#0x1,D0                             | start with 1
    SUB.W	D1,D0                                 | calc 1 - OvalHeight
    MOVE.W	D0,0x4(A1)                           | OvalY := 1-Height
| INIT RsqYsq TO 2*OvalHeight - 1
    MOVE.W	D1,D0                                | get height
    EXT.L	D0                                    | clear out hi word
    ADD.L	D0,D0                                 | calc 2*Height
    SUBQ.L	#0x1,D0                              | subtract 1
    MOVE.L	D0,0x6(A1)                           | RsqYsq := 2*Height-1
| INIT Square to 0.0
    CLR.L	0xA(A1)                               | Square := 0
    CLR.L	0xE(A1)                               | Square lo := 0
| OddNum := 1 times aspect ratio squared
    CLR.L	-(A7)                                 | get ready for function result
    MOVE.W	D1,-(A7)                             | push numerator = height
    MOVE.W	D2,-(A7)                             | push denominator = width
    _FixRatio                                   | calc fixed point height/width
    MOVE.L	(A7),-(A7)                           | duplicate result
    PEA.L	0x12(A1)                              | push addr for result
    _LongMul                                    | calc 64-bit (height/width)^2
    MOVE.L	0x16(A1),D0                          | get OddNum lo long
| OddBump := 2 times aspect ratio squared
    ADD.L	D0,D0                                 | double it
    MOVE.L	D0,0x1E(A1)                          | store as OddBump lo
    MOVE.L	0x12(A1),D0                          | get OddNum hi long
    ADDX.L	D0,D0                                | double hi long with carry
    MOVE.L	D0,0x1A(A1)                          | store as OddBump hi
    RTS                                         | return from INITOVAL
| ------------------------------------------------------------
|
| LOCAL PROCEDURE BumpOval(VAR oval: OvalRec; vert: INTEGER);
|
| Bump an oval state record to the next scanline down.
|
| INPUTS:  A3 points to oval state record
|          D0 contains current vert
|
| CLOBBERS D0-D7, A0-A3
|
BUMPOVAL:
    CMP.W	(A3)+,D0                              | is vert < oval top ?
    BLT.B	BUMPOVAL_GOHOME                       | yes, ignore
    CMP.W	(A3)+,D0                              | is vert >= oval bottom ?
    BGE.B	BUMPOVAL_GOHOME                       | yes, ignore
    MOVE.W	(A3),D0                              | get OvalY
    ADDQ.W	#0x2,(A3)+                           | OvalY += 2; advance ptr
    MOVEM.L	(A3),D1-D7/A0-A2                    | get rest of the oval record
    BRA.B	WHILE1                                | go to loop start
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
|
BUMPOVAL_MORE1:
    ADDA.L	A2,A1                                | rightEdge := rightEdge + 1/2
    SUBA.L	A2,A0                                | leftEdge := leftEdge - 1/2
    ADD.L	D5,D3                                 | Square := Square + OddNum
    ADDX.L	D4,D2                                | all 64 bits of it
    ADD.L	D7,D5                                 | OddNum := OddNum + OddBump
    ADDX.L	D6,D4                                | all 64 bits of it
WHILE1:
    CMP.L	D1,D2                                 | is Square < RsqYsq ?
    BLT.B	BUMPOVAL_MORE1                        | yes, loop
    BRA.B	WHILE2                                | no, go to next loop start
| -----------------------------------------------
|
| WHILE SQUARE > RSQYSQ DO MAKE OVAL SMALLER
|
BUMPOVAL_MORE2:
    SUBA.L	A2,A1                                | rightEdge := rightEdge - 1/2
    ADDA.L	A2,A0                                | leftEdge := leftEdge + 1/2
    SUB.L	D7,D5                                 | OddNum := OddNum - OddBump
    SUBX.L	D6,D4                                | all 64 bits of it
    SUB.L	D5,D3                                 | Square := Square - OddNum
    SUBX.L	D4,D2                                | all 64 bits of it
WHILE2:
    CMP.L	D1,D2                                 | is Square > RsqYsq ?
    BGT.B	BUMPOVAL_MORE2                        | yes, loop
    ADDQ.W	#0x1,D0                              | OvalY + 1
    EXT.L	D0                                    | sign extend to a long
    ASL.L	#0x2,D0                               | calc 4*(OvalY+1)
    SUB.L	D0,D1                                 | RsqYsq := RsqYsq - 4*(OvalY+1)
    MOVEM.L	D1-D7/A0-A2,(A3)                    | update oval record
BUMPOVAL_GOHOME:
    RTS                                         | return from BUMPOVAL_GOHOME
