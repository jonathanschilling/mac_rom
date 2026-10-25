| ------------------------------------------------------------------
|
| --> STRETCH.TEXT

| --------------------------------------------------------------
|
| PROCEDURE StretchBits(srcBits, dstBits: BitMap;
|                       srcRect, dstRect: Rect;
|                       mode: INTEGER;
|                       rgnA, rgnB, rgnC: RgnHandle);
|
| Transfer a rectangle of bits from srcBits to dstBits, stretching
| or compressing according to srcRect and dstRect. The transfer is
| clipped to the intersection of rgnA, rgnB, and rgnC.
|
| Restrictions: transfer mode 0..7 only. If numer <> denom, then
| src and dst bitmaps do not overlap.
|
| COPYRIGHT APPLE COMPUTER INC.
| DESIGNED AND WRITTEN BY BILL ATKINSON.
|
| A6 offsets after LINK A6,#-0x9A:
|   PARAMSIZE = 30
|   SRCBITS = 0x22, DSTBITS = 0x1E, SRCRECT = 0x1A, DSTRECT = 0x16
|   MODE = 0x14, RGNA = 0x10, RGNB = 0xC, RGNC = 0x8
| Locals (selected):
|   NUMER  = -4   (point: hi=dh, lo=dw)
|   DENOM  = -8   (point)
|   VERROR = -0xC (integer)
|   MINRECT = -0x14 (rect)
|   MASKBUF = -0x70 (long)
|   STATEA = -0x40, STATEB = -0x58, STATEC = -0x70
|
STRETCHBITS:
    LINK	A6,#-0x9A                              | link and allocate local vars
    MOVEM.L	D0-D7/A1-A4,-(A7)                   | save regs
    MOVE.L	A7,-0x6C(A6)                         | remember stack for later
| ----------------------------------------------------------------
|
| Calc Numer and Denom based on dstRect and srcRect.
| If Numer = Denom then just call RgnBlt.
|
    MOVEA.L	0x16(A6),A0                         | point to dstRect
    MOVE.W	0x4(A0),D0                           | get dst bottom
    SUB.W	(A0),D0                               | calc dst height
    SWAP.W	D0                                   | put in hi word
    MOVE.W	0x6(A0),D0                           | get dst right
    SUB.W	0x2(A0),D0                            | calc dst width
    MOVEA.L	0x1A(A6),A0                         | point to srcRect
    MOVE.W	0x4(A0),D1                           | get src bottom
    SUB.W	(A0),D1                               | calc src height
    SWAP.W	D1                                   | put in hi word
    MOVE.W	0x6(A0),D1                           | get src right
    SUB.W	0x2(A0),D1                            | calc src width
    CMP.L	D0,D1                                 | are both rects same size ?
    BNE.B	STRETCH                               | no, do stretch
| ----------------------------------------------------------
|
| XRGNBLT -- 1:1 size: just call RgnBlt directly
|
XRGNBLT:
    MOVE.L	0x22(A6),-(A7)                       | push srcBits
    MOVE.L	0x1E(A6),-(A7)                       | push dstBits
    MOVE.L	0x1A(A6),-(A7)                       | push srcRect
    MOVE.L	0x16(A6),-(A7)                       | push dstRect
    MOVE.W	0x14(A6),-(A7)                       | push mode
    MOVE.L	-0x94(A6),-(A7)                      | push pat
    MOVE.L	0x10(A6),-(A7)                       | push rgnA
    MOVE.L	0xC(A6),-(A7)                        | push rgnB
    MOVE.L	0x8(A6),-(A7)                        | push rgnC
    JSR	RGNBLT(PC)                              | call RgnBlt
    BRA.W	STRETCHBITS_GOHOME                    | and quit
| ----------------------------------------------------------
|
| STRETCH
|
| Called during boot.
| ----------------------------------------------------------
|
| STRETCH -- src and dst sizes differ; set up stretch state
|
STRETCH:
    MOVE.L	D0,-0x4(A6)                          | Numer := dst size
    MOVE.L	D1,-0x8(A6)                          | Denom := src size
    JSR	SETUPSTRETCH(PC)                        | calc CaseJump and horiz fract
    MOVE.L	A0,-0x98(A6)                         | save case jump for later
    MOVE.W	D0,-0x9A(A6)                         | save fraction for later
| ----------------------------------------------------------------
|
| Adjust mode and pattern for color separation
|
    MOVE.W	0x14(A6),-(A7)                       | push input mode
    MOVE.L	-0x94(A6),-(A7)                      | push addr of dummy pattern
    JSR	COLORMAP(PC)                            | alter for color separation
    MOVE.L	(A7)+,-0x94(A6)                      | get (altered) pattern
    MOVE.W	(A7)+,D2                             | get (altered) mode
    MOVE.W	D2,D3                                | copy mode
    ROR.W	#0x4,D3                               | is pattern bit set ?
    BCS.B	XRGNBLT                               | yes, use RgnBlt to do pat
    MOVE.W	D2,0x14(A6)                          | no, update (altered) mode
| -------------------------------------------------------------------
|
| Calc MinRect = intersection of dstRect, dstBits.bounds, and three
| region bounding boxes. Quit if the intersection is empty.
|
    MOVEA.L	0x1E(A6),A3                         | point to dst BitMap
    MOVE.L	0x16(A6),-(A7)                       | push addr of dstRect
    PEA.L	0x6(A3)                               | push addr of dstBits.bounds
    MOVEA.L	0x10(A6),A0                         | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    PEA.L	0x2(A0)                               | push rgn bbox
    MOVEA.L	0xC(A6),A0                          | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    PEA.L	0x2(A0)                               | push rgn bbox
    MOVEA.L	0x8(A6),A0                          | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    PEA.L	0x2(A0)                               | push rgn bbox
    MOVE.W	#0x5,-(A7)                           | push nRects = 5
    PEA.L	-0x14(A6)                             | push where to put result
    JSR	RSECT(PC)                               | intersect all rects
    BEQ.W	STRETCHBITS_GOHOME                    | quit if result is empty
| ----------------------------------------------------
|
| Hide the cursor if it intersects MinRect
|
    PEA.L	-0x14(A6)                             | push shield rect
    MOVE.L	0x6(A3),-(A7)                        | push dstBits.bounds.top and left
    JSR	SHIELDCURSOR(PC)                        | remove cursor if intersect
    MOVE.W	-0x6(A6),D0                          | get dst width
    SUBQ.W	#0x1,D0                              | minus one for DBRA
| -----------------------------------------------------------------------
|
| Allocate and clear SrcBuf to hold SrcWidth
|
    LSR.W	#0x5,D0                               | and div by 32 for longs
    MOVE.W	D0,-0x1E(A6)                         | save for later
    CLR.L	-(A7)                                 | clear a long of slop at right
CLRSRC:
    CLR.L	-(A7)                                 | allocate and clear a long
    DBF.W	D0,CLRSRC                             | loop entire buffer
    MOVE.L	A7,-0x18(A6)                         | remember where SrcBuf is
    MOVE.W	-0x2(A6),D0                          | get src width
    SUBQ.W	#0x1,D0                              | minus one for DBRA
| -----------------------------------------------------------------------
|
| Allocate and clear DstBuf to hold DstWidth
|
    LSR.W	#0x5,D0                               | and div by 32 for longs
    MOVE.W	D0,-0x20(A6)                         | save for later
    CLR.L	-(A7)                                 | clear a long of slop at right
    CLR.L	-(A7)                                 | clear another long of slop
CLRDST:
    CLR.L	-(A7)                                 | allocate and clear a long
    DBF.W	D0,CLRDST                             | loop entire buffer
    MOVE.L	A7,-0x1C(A6)                         | remember where DstBuf is
| --------------------------------------------------------
|
| Calc BufLeft and BufSize for rgn scanline buffers
|
    MOVEA.L	0x16(A6),A0                         | point to dstRect
    MOVE.W	0x2(A0),D1                           | get dstRect left
    SUB.W	0x8(A3),D1                            | sub dst bbox left
    ANDI.W	#0xFFF0,D1                           | truncate to multiple of 16
    ADD.W	0x8(A3),D1                            | add dst bbox left
    MOVE.W	D1,-0x74(A6)                         | save as BufLeft
    MOVE.W	-0xE(A6),D0                          | get dstRect right
    SUB.W	D1,D0                                 | calc width in dots
    LSR.W	#0x5,D0                               | div by 32 for longs
    MOVE.W	D0,-0x76(A6)                         | BufSize = # longs - 1
| -----------------------------------------------------------------------
|
| Allocate and clear a scanline buffer for the composite mask
|
STRETCHBITS_CLRMASK:
    CLR.L	-(A7)                                 | allocate and clear
    DBF.W	D0,STRETCHBITS_CLRMASK                | loop till done
    MOVE.L	A7,-0x72(A6)                         | remember where MaskBuf is
| -------------------------------------------------------------------
|
| Init state records Vert0 and Vert1 in case rectangular
|
    MOVE.W	#0x7FFF,D0                           | get max int
    MOVE.W	D0,-0x28(A6)                         | init A state right
    MOVE.W	D0,-0x40(A6)                         | init B state right
    MOVE.W	D0,-0x58(A6)                         | init C state right
    NEG.W	D0                                    | get min int
    MOVE.W	D0,-0x2A(A6)                         | init A state left
    MOVE.W	D0,-0x42(A6)                         | init B state left
    MOVE.W	D0,-0x5A(A6)                         | init C state left
| ----------------------------------------------------------------------
|
| Allocate buffers and init state records for each non-rect region
|
    MOVEQ.L	#0xA,D7                             | rgn size if rectangular
    CLR.W	D5                                    | init all rgns rect
    MOVEA.L	0x10(A6),A0                         | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    CMP.W	(A0),D7                               | is RgnA rectangular ?
    BEQ.B	STRETCHBITS_CLRMASK_SKIP              | yes, skip it
    ADDQ.W	#0x2,D5                              | set RgnA flag
    LEA.L	-0x38(A6),A1                          | point to state record A
    BSR.B	STRETCHBITS_CLRMASK_CONT              | init state, alloc buffer
STRETCHBITS_CLRMASK_SKIP:
    MOVEA.L	0xC(A6),A0                          | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    CMP.W	(A0),D7                               | is RgnB rectangular ?
    BEQ.B	STRETCHBITS_CLRMASK_SKIP_2            | yes, skip it
    ADDQ.W	#0x4,D5                              | set RgnB flag
    LEA.L	-0x50(A6),A1                          | point to state record B
    BSR.B	STRETCHBITS_CLRMASK_CONT              | init state, alloc buffer
STRETCHBITS_CLRMASK_SKIP_2:
    MOVEA.L	0x8(A6),A0                          | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    CMP.W	(A0),D7                               | is RgnC rectangular ?
    BEQ.B	STRETCHBITS_CLRMASK_EXIT              | yes, skip it
    ADDQ.W	#0x8,D5                              | set RgnC flag
    LEA.L	-0x68(A6),A1                          | point to state record C
    PEA.L	STRETCHBITS_CLRMASK_EXIT(PC)          | push fake return addr
| STRETCHBITS_CLRMASK_CONT -- init state, alloc buffer
STRETCHBITS_CLRMASK_CONT:
    MOVE.W	-0x12(A6),D0                         | get MinRect left
    MOVE.W	-0xE(A6),D1                          | get MinRect right
    MOVE.W	-0x74(A6),D2                         | get BufLeft
    JMP	INITRGN(PC)                             | init state, alloc buffer
| ----------------------------------------------------------
|
| STRETCHBITS_CLRMASK_EXIT -- if all rgns rect, draw MinRect into mask
|
STRETCHBITS_CLRMASK_EXIT:
    MOVE.W	D5,-0x6E(A6)                         | save RectFlag
    BNE.B	STRETCHBITS_CLRMASK_NO                | no, continue
    MOVEA.L	-0x72(A6),A0                        | yes, point to mask buffer
    MOVE.W	-0x12(A6),D3                         | get MinRect left
    SUB.W	-0x74(A6),D3                          | make it buffer relative
    MOVE.W	-0xE(A6),D4                          | get MinRect right
    SUB.W	-0x74(A6),D4                          | make it buffer relative
    JSR	XORSLAB(PC)                             | and XOR between them
| ------------------------------------------------------
|
| Set up invert flag in D7 to reflect mode bit 2
|
STRETCHBITS_CLRMASK_NO:
    MOVEQ.L	#0x0,D7                             | say not inverted
    MOVE.W	0x14(A6),D2                          | get transfer mode
    BMI.W	STRETCHBITS_DONE                      | quit if mode negative
    BCLR	#0x2,D2                                | test and clr invert bit
    BEQ.B	STRETCHBITS_CLRMASK_SKIP_3            | skip if not inverted
    NOT.L	D7                                    | inverted: D7 gets all 1's
STRETCHBITS_CLRMASK_SKIP_3:
    CMPI.W	#0x7,D2                              | is mode > 7 ?
| --------------------------------------------------
|
| Calculate case jump for different transfer modes
|
    BGT.W	STRETCHBITS_DONE                      | yes, quit
    LEA.L	STRETCHBITS_ABCDONE_MODE_TBL(PC),A0   | point to mode table
    MOVE.B	0x0(A0,D2.W),D2                      | get table entry
    SUBA.W	D2,A0                                | compute address
    MOVE.L	A0,-0x90(A6)                         | save for later
| ------------------------------------------------
|
| Set up SrcRow, SrcLimit, SrcShift, and SrcAddr
|
    MOVEA.L	0x22(A6),A2                         | point to srcBits
    MOVE.W	0x4(A2),D0                           | get src rowBytes
    EXT.L	D0                                    | and extend to long
    MOVE.L	D0,-0x82(A6)                         | SrcRow := src rowBytes
    MOVE.W	0xA(A2),D1                           | get src bottom
    SUB.W	0x6(A2),D1                            | calc src height
    MULU.W	D0,D1                                | mult by src rowBytes
    ADD.L	(A2),D1                               | add SrcBase
    ADDQ.L	#0x2,D1                              | plus two byte slop
    MOVE.L	D1,-0x8A(A6)                         | save result as SrcLimit
    MOVEA.L	0x1A(A6),A0                         | point to srcRect
    MOVE.W	0x2(A0),D1                           | get srcRect left
    SUB.W	0x8(A2),D1                            | subtract src left
    MOVE.W	D1,D5                                | make a copy
    NEG.W	D5                                    | negate it and
    ANDI.W	#0xF,D5                              | treat MOD 16 for SrcShift
    MOVE.W	(A0),D0                              | get srcRect top
    SUB.W	0x6(A2),D0                            | subtract src top
    MULU.W	0x4(A2),D0                           | mult by src rowBytes
    MOVEA.L	(A2),A0                             | get SrcBase
    ADDA.L	D0,A0                                | add vertical offset
    ADD.W	D5,D1                                 | adjust SrcLeft for SrcShift
    ASR.W	#0x4,D1                               | convert dots to words
    ADDA.W	D1,A0                                | add horizontal offset
    ADDA.W	D1,A0                                | twice for bytes
    MOVE.L	A0,-0x7A(A6)                         | save as SrcAddr
| ----------------------------------------------------
|
| Calc starting DstRow, DstShift, and DstAddr
|
    MOVE.W	0x4(A3),D0                           | get dst rowBytes
    EXT.L	D0                                    | extend to long
    MOVE.L	D0,-0x86(A6)                         | DstRow := dst rowBytes
    MOVEA.L	0x16(A6),A0                         | point to dstRect
    MOVE.W	(A0),-0x8C(A6)                       | current vert := dstRect top
    MOVE.W	0x2(A0),D1                           | get dstRect left
    SUB.W	0x8(A3),D1                            | subtract dst left
    MOVEQ.L	#0xF,D6                             | MOD 16 mask
    AND.W	D1,D6                                 | treat MOD 16 for DstShift
    MOVE.W	-0x14(A6),D0                         | get MinRect top
    SUB.W	0x6(A3),D0                            | subtract dst top
    MULU.W	0x4(A3),D0                           | mult by dst rowBytes
    MOVEA.L	(A3),A0                             | get DstBase
    ADDA.L	D0,A0                                | add vertical offset
    ASR.W	#0x4,D1                               | convert dots to words
    ADDA.W	D1,A0                                | add horiz offset
    ADDA.W	D1,A0                                | twice for bytes
    MOVE.L	A0,-0x7E(A6)                         | save as DstAddr
    MOVE.W	-0x8(A6),D0                          | get Denom.v
| -----------------------------------------------------
|
| Init error term for DDA
|
    LSR.W	#0x1,D0                               | divide by 2
    NEG.W	D0                                    | negate for initial error
    MOVE.W	D0,-0xC(A6)                          | VError := -Denom.v/2
| -----------------------------------------------------
|
| Get first scanline of src into SrcBuf
|
NEXTSRC:
    MOVEA.L	-0x7A(A6),A0                        | point to src bitmap
    CMPA.L	-0x8A(A6),A0                         | is it exhausted ?
    BCC.W	STRETCHBITS_DONE                      | quit if exhausted
    MOVEA.L	-0x18(A6),A1                        | point to SrcBuf
    MOVE.W	-0x1E(A6),D1                         | get count of longs
NEXTSRC_LOOP:
    MOVE.L	-0x2(A0),D0                          | get first long of src
    LSR.L	D5,D0                                 | align to SrcBuf
    MOVE.W	D0,(A1)+                             | put a word to SrcBuf
    MOVE.L	(A0)+,D0                             | get a second long
    LSR.L	D5,D0                                 | align to SrcBuf
    MOVE.W	D0,(A1)+                             | put a word to SrcBuf
    DBF.W	D1,NEXTSRC_LOOP                       | loop for all longs
    MOVE.L	-0x82(A6),D2                         | get src rowBytes
    ADD.L	D2,-0x7A(A6)                          | bump src to next row
    MOVE.W	-0x4(A6),D0                          | get Numer.v
    ADD.W	D0,-0xC(A6)                           | VError := VError + Numer.v
    BGT.B	SRCLOOP_EXIT                          | skip if VError > 0
| -----------------------------------------------------
|
| WHILE (VError < 0) DO merge other scanlines into SrcBuf
|
SRCLOOP:
    MOVEA.L	-0x7A(A6),A0                        | point to src bitmap
    CMPA.L	-0x8A(A6),A0                         | is it exhausted ?
    BCC.B	SRCLOOP_EXIT                          | quit if exhausted
    MOVEA.L	-0x18(A6),A1                        | point to SrcBuf
    MOVE.W	-0x1E(A6),D1                         | get count of longs
SRCLOOP_LOOP:
    MOVE.L	-0x2(A0),D0                          | get next long of src
    LSR.L	D5,D0                                 | align to SrcBuf
    OR.W	D0,(A1)+                               | OR a word to SrcBuf
    MOVE.L	(A0)+,D0                             | get a second long
    LSR.L	D5,D0                                 | align to SrcBuf
    OR.W	D0,(A1)+                               | OR a word to SrcBuf
    DBF.W	D1,SRCLOOP_LOOP                       | loop for all longs
    ADD.L	D2,-0x7A(A6)                          | bump src to next row
    MOVE.W	-0x4(A6),D0                          | get Numer.v
    ADD.W	D0,-0xC(A6)                           | VError := VError + Numer.v
    BLE.B	SRCLOOP                               | loop while VError <= 0
| ----------------------------------------------------------
|
| Horizontally stretch SrcBuf into DstBuf
|
SRCLOOP_EXIT:
    MOVEA.L	-0x18(A6),A0                        | point to SrcBuf
    MOVEA.L	-0x1C(A6),A1                        | point to DstBuf
    MOVE.W	-0x20(A6),D0                         | get DstLongs
    LSL.W	#0x2,D0                               | quad for byte offset
    LEA.L	0x4(A1,D0.W),A2                       | point to DstLimit
    MOVE.W	-0x9A(A6),D4                         | get horizontal fraction
    MOVEA.L	-0x98(A6),A3                        | get case jump
    JSR	(A3)                                    | and call StretchRow
| -------------------------------------------------------
|
| Transfer one or more copies of DstBuf into dstBits
|
STRETCHBITS_NXTMASK:
    MOVE.W	-0x8C(A6),D0                         | get current vert
    CMP.W	-0x14(A6),D0                          | is it < MinRect.top ?
    BLT.B	NEXTDST_SKIP                          | yes, skip transfer
    BSR.W	STRETCHBITS_GOHOME_CONT               | else update mask buffer
    MOVEA.L	-0x1C(A6),A3                        | A3 := DstBuf
    MOVEA.L	-0x7E(A6),A4                        | A4 := DstAddr
    MOVEA.L	-0x72(A6),A2                        | A2 := MaskBuf
    MOVE.W	-0x76(A6),D2                         | D2 := BufSize
    MOVEA.L	-0x90(A6),A0                        | get mode case-jump addr
    JMP	(A0)                                    | dispatch to stretch row blitter
| ----------------------------------------------------------
|
| NEXTDST -- bump dst pointer to next row
|
NEXTDST:
    MOVE.L	-0x86(A6),D0                         | get DstRow
    ADD.L	D0,-0x7E(A6)                          | bump DstAddr to next row
NEXTDST_SKIP:
    ADDQ.W	#0x1,-0x8C(A6)                       | bump current vert
    MOVE.W	-0x8C(A6),D0                         | get current vert
    CMP.W	-0x10(A6),D0                          | is vert >= MinRect.bottom ?
    BEQ.B	STRETCHBITS_DONE                      | yes, all done
    MOVE.W	-0x8(A6),D0                          | get Denom.v
    SUB.W	D0,-0xC(A6)                           | VError := VError - Denom.v
    BGE.B	STRETCHBITS_NXTMASK                   | if VError >= 0, repeat row
    BRA.W	NEXTSRC                               | else fetch next src scanline
STRETCHBITS_DONE:
    JSR	SHOWCURSOR(PC)                          | restore the cursor
STRETCHBITS_GOHOME:
    MOVEA.L	-0x6C(A6),A7                        | strip stack scan buffers
    MOVEM.L	(A7)+,D0-D7/A1-A4                   | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x1E,A7                             | strip 30 bytes of params
    JMP	(A0)                                    | tail-call return from STRETCHBITS_GOHOME via A0
| -----------------------------------------------------------------
|
| Local routine to update mask buffer to current vertical coord
|
STRETCHBITS_GOHOME_CONT:
    MOVE.W	-0x8C(A6),D0                         | get current vert
    MOVE.W	-0x6E(A6),D1                         | get RectFlag
    MOVE.W	STRETCHBITS_RECTFLAG_TBL(PC,D1.W),D1 | get branch offset from table
    JMP	STRETCHBITS_RECTFLAG_TBL(PC,D1.W)       | dispatch on RectFlag
| ----------------------------------------------------------
|
| STRETCHBITS_RECTFLAG_TBL -- branch offsets table for RectFlag (5 entries):
|   0x009A: all rect (no-op, jump to JSRSEEK_CONT)
|   0x0010: only A non-rect (-> _CONT_3)
|   0x0016: only A non-rect (alt path)
|   0x002A: only B non-rect (-> _CONT_4)
|   0x001C: only B non-rect (alt path)
|   0x004A: only C non-rect (-> ENTRY_17B6A)
|   0x006A: only A,B non-rect (-> ENTRY_17B78)
|   0x009C: A,B,C all non-rect (-> ENTRY_17BEA)
|
STRETCHBITS_RECTFLAG_TBL:
    .short	0x009A
    .long	0x00100016
    .long	0x002A001C
    .long	0x004A006A
    .short	0x009C
| --------------------------------------------------------------------
|
| Only region A is non rectangular. Update it and use it as the mask.
|
STRETCHBITS_GOHOME_CONT_3:
    LEA.L	-0x38(A6),A1                          | point to RgnA state
    BRA.B	STRETCHBITS_JSRSEEK                   | seek and use as mask
| --------------------------------------------------------------------
|
| Only region B is non rectangular. Update it and use it as the mask.
|
STRETCHBITS_GOHOME_CONT_4:
    LEA.L	-0x50(A6),A1                          | point to RgnB state
    BRA.B	STRETCHBITS_JSRSEEK                   | seek and use as mask
| --------------------------------------------------------------------
|
| Only region C is non rectangular. Update it and use it as the mask.
|
STRETCHBITS_GOHOME_CONT_5:
    LEA.L	-0x68(A6),A1                          | point to RgnC state
| Common: SeekRgn for one region, then store its scan buffer as MaskBuf
STRETCHBITS_JSRSEEK:
    MOVE.L	-0x72(A6),0x8(A1)                    | use scan buffer as MaskBuf
    JMP	SEEKRGN(PC)                             | seek and return
| --------------------------------------------------------------------
|
| Two regions A and B are non rectangular. Update each, then form
| intersection in the MaskBuf.
|
STRETCHBITS_GOHOME_CONT_AB:
    LEA.L	-0x38(A6),A1                          | point to StateA
    JSR	SEEKRGN(PC)                             | seek RgnA to current vert
    MOVE.W	D1,-(A7)                             | save D1 (changed flag)
    LEA.L	-0x50(A6),A1                          | point to StateB
    JSR	SEEKRGN(PC)                             | seek RgnB to current vert
    OR.W	(A7)+,D1                               | OR change flags
    BEQ.B	JSRSEEK_RTS                           | nothing changed, return
    MOVEA.L	-0x30(A6),A0                        | get StateA scanBuf
    MOVEA.L	-0x48(A6),A1                        | get StateB scanBuf
    BRA.B	STRETCHBITS_CPY2BUF                   | go intersect AB into MaskBuf
| --------------------------------------------------------------------
|
| Two regions A and C are non rectangular.
|
STRETCHBITS_GOHOME_CONT_AC:
    LEA.L	-0x38(A6),A1                          | point to StateA
    JSR	SEEKRGN(PC)                             | seek RgnA to current vert
    MOVE.W	D1,-(A7)                             | save D1 (changed flag)
    LEA.L	-0x68(A6),A1                          | point to StateC
    JSR	SEEKRGN(PC)                             | seek RgnC to current vert
    OR.W	(A7)+,D1                               | OR change flags
    BEQ.B	JSRSEEK_RTS                           | nothing changed, return
    MOVEA.L	-0x30(A6),A0                        | get StateA scanBuf
    MOVEA.L	-0x60(A6),A1                        | get StateC scanBuf
    BRA.B	STRETCHBITS_CPY2BUF                   | go intersect AC into MaskBuf
| --------------------------------------------------------------------
|
| Two regions B and C are non rectangular.
|
STRETCHBITS_GOHOME_CONT_BC:
    LEA.L	-0x50(A6),A1                          | point to StateB
    JSR	SEEKRGN(PC)                             | seek RgnB to current vert
    MOVE.W	D1,-(A7)                             | save D1 (changed flag)
    LEA.L	-0x68(A6),A1                          | point to StateC
    JSR	SEEKRGN(PC)                             | seek RgnC to current vert
    OR.W	(A7)+,D1                               | OR change flags
    BEQ.B	JSRSEEK_RTS                           | nothing changed, return
    MOVEA.L	-0x48(A6),A0                        | get StateB scanBuf
    MOVEA.L	-0x60(A6),A1                        | get StateC scanBuf
| Common 2-region intersection into MaskBuf
STRETCHBITS_CPY2BUF:
    MOVEA.L	-0x72(A6),A2                        | A2 := MaskBuf
    MOVE.W	-0x76(A6),D1                         | D1 := BufSize
STRETCHBITS_BCLOOP:
    MOVE.L	(A0)+,D0                             | get a long from rgn1 buf
    AND.L	(A1)+,D0                              | AND with rgn2 buf
    MOVE.L	D0,(A2)+                             | store in MaskBuf
    DBF.W	D1,STRETCHBITS_BCLOOP                 | loop entire buffer
JSRSEEK_RTS:
    RTS                                         | return from JSRSEEK_RTS
| --------------------------------------------------------------------
|
| Three regions A, B, C are non rectangular.
| Update each, then form intersection in MaskBuf.
|
STRETCHBITS_GOHOME_CONT_ABC:
    LEA.L	-0x38(A6),A1                          | point to StateA
    JSR	SEEKRGN(PC)                             | seek RgnA
    MOVE.W	D1,-(A7)                             | save changed flag
    LEA.L	-0x50(A6),A1                          | point to StateB
    JSR	SEEKRGN(PC)                             | seek RgnB
    OR.W	D1,(A7)                                | OR with prior change flag
    LEA.L	-0x68(A6),A1                          | point to StateC
    JSR	SEEKRGN(PC)                             | seek RgnC
    OR.W	(A7)+,D1                               | OR with combined change flag
    BEQ.B	STRETCHBITS_ABCDONE                   | nothing changed, return
    MOVEA.L	-0x30(A6),A0                        | get StateA scanBuf
    MOVEA.L	-0x48(A6),A1                        | get StateB scanBuf
    MOVEA.L	-0x60(A6),A2                        | get StateC scanBuf
    MOVEA.L	-0x72(A6),A3                        | A3 := MaskBuf
    MOVE.W	-0x76(A6),D1                         | D1 := BufSize
STRETCHBITS_ABCLOOP:
    MOVE.L	(A0)+,D0                             | get long from RgnA buf
    AND.L	(A1)+,D0                              | AND with RgnB buf
    AND.L	(A2)+,D0                              | AND with RgnC buf
    MOVE.L	D0,(A3)+                             | store in MaskBuf
    DBF.W	D1,STRETCHBITS_ABCLOOP                | loop entire buffer
STRETCHBITS_ABCDONE:
    RTS                                         | return from STRETCHBITS_ABCDONE
| ---------------------------------------------------------------
|
| Per-mode StretchBits scanline blitters. Each one fetches the
| (already horizontally-stretched) src long from DstBuf, aligns
| it to the dst BitMap word boundary via D6 shift, optionally
| inverts via D7 (for notSrc modes), masks via MaskBuf, and
| merges into dst.
|
| INPUTS to each loop:
|   A2: MaskPtr   D2: longCnt
|   A3: SrcPtr    D6: dstShift
|   A4: DstPtr    D7: invert (-1 if notSrc, 0 otherwise)
|
| -------------------------------------------------------
|
| MODE 0 OR 4: SRC --> DST (srcCopy / notSrcCopy)
|
STRETCHBITS_ABCDONE_LOOP:
    MOVE.L	-0x2(A3),D0                          | fetch next dst word
    LSR.L	D6,D0                                 | align to dst
    SWAP.W	D0                                   | put into hi half of D0
    MOVE.L	(A3)+,D1                             | get src from BitMap and bump right
    LSR.L	D6,D1                                 | align to dst
    MOVE.W	D1,D0                                | assemble one long
    EOR.L	D7,D0                                 | invert src if mode bit 2 set
    MOVE.L	(A2)+,D1                             | get mask
    AND.L	D1,D0                                 | mask src
    NOT.L	D1                                    | form NotMask
    AND.L	(A4),D1                               | get dst data
    OR.L	D1,D0                                  | merge with src data
    MOVE.L	D0,(A4)+                             | put result in dst
    DBF.W	D2,STRETCHBITS_ABCDONE_LOOP           | loop all longs this row
    BRA.W	NEXTDST                               | go for next row
| -------------------------------------------------------
|
| MODE 1 OR 5: SRC OR DST --> DST (srcOr / notSrcOr)
|
STRETCHBITS_ABCDONE_LOOP_2:
    MOVE.L	-0x2(A3),D0                          | fetch next dst word
    LSR.L	D6,D0                                 | align to dst
    SWAP.W	D0                                   | put into hi half of D0
    MOVE.L	(A3)+,D1                             | get src from BitMap
    LSR.L	D6,D1                                 | align to dst
    MOVE.W	D1,D0                                | assemble one long
    EOR.L	D7,D0                                 | invert src if mode bit 2 set
    AND.L	(A2)+,D0                              | AND with mask
    OR.L	D0,(A4)+                               | OR result into dst
    DBF.W	D2,STRETCHBITS_ABCDONE_LOOP_2         | loop all longs this row
    BRA.W	NEXTDST                               | loop for next row
| -------------------------------------------------------
|
| MODE 2 OR 6: SRC XOR DST --> DST (srcXor / notSrcXor)
|
STRETCHBITS_ABCDONE_LOOP_3:
    MOVE.L	-0x2(A3),D0                          | fetch next dst word
    LSR.L	D6,D0                                 | align to dst
    SWAP.W	D0                                   | put into hi half of D0
    MOVE.L	(A3)+,D1                             | get src from BitMap
    LSR.L	D6,D1                                 | align to dst
    MOVE.W	D1,D0                                | assemble one long
    EOR.L	D7,D0                                 | invert src if mode bit 2 set
    AND.L	(A2)+,D0                              | AND with mask
    EOR.L	D0,(A4)+                              | XOR result into dst
    DBF.W	D2,STRETCHBITS_ABCDONE_LOOP_3         | loop all longs this row
    BRA.W	NEXTDST                               | loop for next row
| -------------------------------------------------------
|
| MODE 3 OR 7: SRC BIC DST --> DST (srcBic / notSrcBic)
|
STRETCHBITS_ABCDONE_LOOP_4:
    MOVE.L	-0x2(A3),D0                          | fetch next dst word
    LSR.L	D6,D0                                 | align to dst
    SWAP.W	D0                                   | put into hi half of D0
    MOVE.L	(A3)+,D1                             | get src from BitMap
    LSR.L	D6,D1                                 | align to dst
    MOVE.W	D1,D0                                | assemble one long
    EOR.L	D7,D0                                 | invert src if mode bit 2 set
    AND.L	(A2)+,D0                              | AND with mask
    NOT.L	D0                                    | invert for BIC
    AND.L	D0,(A4)+                              | BIC result into dst
    DBF.W	D2,STRETCHBITS_ABCDONE_LOOP_4         | loop all longs this row
    BRA.W	NEXTDST                               | loop for next row
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
| Stretch case offsets table -- backwards-relative offsets to the
| four StretchRow loops (1x, 2x, 3x, 4x src reads per dst write).
| Used by SetUpStretch via "MOVE.B 0x0(A0,D2.W),D2" + "SUBA.W D2,A0".
STRETCHBITS_ABCDONE_MODE_TBL:
    .short	0x7A56                               | 0x7A: STRETCHBITS_ABCDONE_LOOP, 0x56: ABCDONE_LOOP_2
    .short	0x3A1E                               | 0x3A: STRETCHBITS_ABCDONE_LOOP_3, 0x1E: ABCDONE_LOOP_4
| --------------------------------------------------------------
|
| SetUpStretch -- calc CaseJump and horiz Fract.
|
| Call with Numer in D0, Denom in D1.
| Returns case jump in A0, fraction in D0.
|
SETUPSTRETCH:
    LEA.L	WHITE2_ERR(PC),A0                     | point to abort
    TST.W	D0                                    | is Numer <= 0 ?
    BLE.W	FOUND                                 | yes, point to abort
    TST.W	D1                                    | is Denom <= 0 ?
    BLE.W	FOUND                                 | yes, point to abort
    LEA.L	SHRNKING_LOOP(PC),A0                  | point to fast copy
    CMP.W	D1,D0                                 | is Numer = Denom ?
    BEQ.W	FOUND                                 | yes, use fast copy
    BLT.B	SHRNKING                              | no, branch if shrinking
|
| We will be stretching. Calc fract = denom/numer and check for fast.
|
    MOVE.W	D0,D3                                | make a copy of Numer
    MOVE.W	D1,D4                                | make a copy of Denom
    CLR.L	-(A7)                                 | room for fcn result
    MOVE.W	D1,-(A7)                             | push Denom
    MOVE.W	D0,-(A7)                             | push Numer
    _FixRatio                                   | call FixRatio, < 1.0
    MOVE.L	(A7)+,D0                             | pop result
    LEA.L	QRTR2_LOOP_2(PC),A0                   | check for fast ratios
    CMPI.W	#0x8000,D0                           | half ratio (= 2x stretch) ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	QUAD(PC),A0                           | check for quadruple
    CMPI.W	#0x4000,D0                           | quadruple ratio (4x) ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	EIGHT(PC),A0                          | check for octuple
    CMPI.W	#0x2000,D0                           | octuple ratio (8x) ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	SIXTEEN(PC),A0                        | check for hexadecuple
    CMPI.W	#0x1000,D0                           | hexadecuple ratio (16x) ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	QRTR2_LOOP(PC),A0                     | check for 1.5 ratio
    CMPI.W	#0xAAAA,D0                           | 1.5 ratio ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	TRIPLE(PC),A0                         | check for triple
    CMPI.W	#0x5555,D0                           | triple ratio (3x) ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	SIX(PC),A0                            | check for sextuple
    CMPI.W	#0x2AAA,D0                           | sextuple ratio (6x) ?
    BEQ.B	FOUND                                 | yes, branch
|
| Check for any multiple of 8
|
    EXT.L	D3                                    | clear hi word of Numer
    DIVU.W	D4,D3                                | calc Numer DIV Denom
    MOVE.W	D3,D1                                | save quotient
    ANDI.L	#0xFFFF0007,D3                       | is it a multiple of 8 ?
    BNE.B	NOMATCH                               | no, use general stretch
    MOVE.W	D1,D0                                | yes, return quotient in D0
    LEA.L	EIGHTS(PC),A0                         | point to fast routine
    RTS                                         | and return
| ----------------------------------------------------------
|
| NOMATCH -- no fast match, use general slow stretch
|
NOMATCH:
    LEA.L	WHITE1_CONT(PC),A0                    | point to slow general code
| Called by: SETUPSTRETCH, SHRNKING
FOUND:
    RTS                                         | return with case jump in A0
|
| We will be shrinking. Calc fract = numer/denom and check for fast.
|
SHRNKING:
    CLR.L	-(A7)                                 | room for fcn result
    MOVE.W	D0,-(A7)                             | push Numer
    MOVE.W	D1,-(A7)                             | push Denom
    _FixRatio                                   | call FixRatio, < 1.0
    MOVE.L	(A7)+,D0                             | pop result
    LEA.L	HALF(PC),A0                           | check for fast ratios
    CMPI.W	#0x8000,D0                           | half ratio (= 1/2 shrink) ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	HALF2_CONT(PC),A0                     | check for quarter
    CMPI.W	#0x4000,D0                           | quarter ratio (1/4) ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	THREE4(PC),A0                         | check for 3/4
    CMPI.W	#0xC000,D0                           | 3/4 ratio ?
    BEQ.B	FOUND                                 | yes, branch
    LEA.L	SHRINK(PC),A0                         | general shrink routine
    BRA.B	FOUND                                 | done
| -----------------------------------------------
|
| Numer = Denom: just copy longs (1:1 stretch row)
|
SHRNKING_LOOP:
    MOVE.L	(A0)+,(A1)+                          | copy one long
    MOVE.L	(A0)+,(A1)+                          | copy another long
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	SHRNKING_LOOP                         | loop until DstLimit
    RTS                                         | all done
| ---------------------------------------------------
|
| THREE4 -- shrink to three quarters
|
THREE4:
    MOVEQ.L	#0x3,D3                             | mask for hi 2 bits
    ROR.L	#0x2,D3                               | i.e. 0xC0000000
    CLR.L	-(A7)                                 | allocate a long of temp
THREE4A:
    MOVE.L	(A0)+,D0                             | get a long of src
    MOVEQ.L	#0x7,D2                             | init count of 24 dst bits
THREE4B:
    ADD.L	D0,D0                                 | get 1 bit of src
    ADDX.L	D1,D1                                | put 1 bit to dst
    ADD.L	D3,D0                                 | put hi 2 bits into carry
    ADDX.L	D1,D1                                | shift into dst
    LSL.L	#0x3,D0                               | shift left 3 bits
    ADDX.L	D1,D1                                | put carry bit into dst
    DBF.W	D2,THREE4B                            | loop 8 times
    MOVE.L	D1,(A7)                              | stash 3 dst bytes in temp
    MOVE.B	0x1(A7),(A1)+                        | put first byte to dst
    MOVE.B	0x2(A7),(A1)+                        | put second byte to dst
    MOVE.B	0x3(A7),(A1)+                        | put third byte to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	THREE4A                               | loop until DstLimit
    ADDQ.W	#0x4,A7                              | cleanup temp storage
    RTS                                         | and quit
| ---------------------------------------------------
|
| HALF -- shrink to one half
|
HALF:
    MOVEQ.L	#0x3,D3                             | mask for hi 2 bits
    ROR.L	#0x2,D3                               | i.e. 0xC0000000
HALF1:
    MOVE.L	(A0)+,D0                             | get a long of src
    MOVEQ.L	#0x7,D2                             | init count of 16 dst bits
HALF2:
    ADD.L	D3,D0                                 | put OR of hi bits into carry
    ADDX.W	D1,D1                                | shift bit into dst
    LSL.L	#0x2,D0                               | shift left 2 bits
    ADD.L	D3,D0                                 | put OR of hi bits into carry
    ADDX.L	D1,D1                                | shift bit into dst
    LSL.L	#0x2,D0                               | shift left 2 bits
    DBF.W	D2,HALF2                              | loop 8 times
    MOVE.W	D1,(A1)+                             | then put a word to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	HALF1                                 | loop until DstLimit
    RTS                                         | yes, quit
| ---------------------------------------------------
|
| HALF2_CONT / QRTR1 -- shrink to one quarter
|
HALF2_CONT:
    MOVE.L	#0xF0000000,D3                       | mask for hi 4 bits
QRTR1:
    MOVE.L	(A0)+,D0                             | get a long of src
    MOVEQ.L	#0x7,D2                             | init count of 8 dst bits
QRTR2:
    ADD.L	D3,D0                                 | put OR of hi bits into carry
    ADDX.L	D1,D1                                | shift bit into dst
    LSL.L	#0x4,D0                               | shift left 4 bits
    DBF.W	D2,QRTR2                              | loop 8 times
    MOVE.B	D1,(A1)+                             | then put a byte to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	QRTR1                                 | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------
|
| QRTR2_LOOP -- stretch to 1.5 times as wide. Each src byte becomes
| 1.5 dst bytes (3 dst bytes per 2 src bytes), via a 16-entry
| table of 4-bit -> 6-bit expansions in QRTR2_CONT.
|
QRTR2_LOOP:
    MOVE.B	(A0)+,D0                             | get first byte from src
    MOVE.W	D0,D1                                | make an extra copy
    LSR.B	#0x4,D1                               | get hi nibble
    MOVE.B	QRTR2_CONT(PC,D1.W),D2               | expand to 6 bits
    LSL.L	#0x6,D2                               | shift over 6
    ANDI.W	#0xF,D0                              | get lo nibble
    MOVE.B	QRTR2_CONT(PC,D0.W),D2               | expand to 6 bits
    LSL.L	#0x6,D2                               | shift over 6
    MOVE.B	(A0)+,D0                             | get second byte from src
    MOVE.W	D0,D1                                | make an extra copy
    LSR.B	#0x4,D1                               | get hi nibble
    MOVE.B	QRTR2_CONT(PC,D1.W),D2               | expand to 6 bits
    LSL.L	#0x6,D2                               | shift over 6
    ANDI.W	#0xF,D0                              | get lo nibble
    MOVE.B	QRTR2_CONT(PC,D0.W),D2               | expand to 6 bits
    LSR.L	#0x2,D2                               | right justify
    SWAP.W	D2                                   | flip words
    MOVE.B	D2,(A1)+                             | put first byte to dst
    SWAP.W	D2                                   | flip back again
    MOVE.W	D2,D1                                | move for second byte
    ROR.W	#0x8,D1                               | rotate to get second byte
    MOVE.B	D1,(A1)+                             | put second byte to dst
    MOVE.B	D2,(A1)+                             | put third byte to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	QRTR2_LOOP                            | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------------------
|
| QRTR2_CONT -- 4-bit input nibble -> 6-bit doubled-bit output for 1.5x stretch.
| 16 entries (one per nibble value 0..F), each is a 6-bit pattern where every
| input bit is replicated. E.g. 0001 -> 000011 (0x03), 1010 -> 110011 (0x33).
|
QRTR2_CONT:
    .short	0x000C                               | 0000 -> 0x00, 0001 -> 0x0C
    .long	0x101C606C                            | 0010..0101: 0x10,0x1C,0x60,0x6C
    .long	0x707C808C                            | 0110..1001: 0x70,0x7C,0x80,0x8C
    .long	0x909CE0EC                            | 1010..1101: 0x90,0x9C,0xE0,0xEC
    .short	0xF0FC                               | 1110 -> 0xF0, 1111 -> 0xFC
| RTS ;ALL DONE

| .BYTE $60,$6C,$70,$7C
| .BYTE $80,$8C,$90,$9C
| .BYTE $E0,$EC,$F0,$FC

| -----------------------------------------------
|
| QRTR2_LOOP_2 -- double using table lookup. Each src byte
| becomes 2 dst bytes (each nibble expands to a byte where
| every input bit is replicated 2 times via NIBBLE_DOUBLE_TBL).
|
QRTR2_LOOP_2:
    MOVE.B	(A0)+,D0                             | get a byte from src
    MOVE.W	D0,D1                                | make an extra copy
    LSR.B	#0x4,D1                               | get hi nibble
    MOVE.B	NIBBLE_DOUBLE_TBL(PC,D1.W),(A1)+     | put expanded byte to dst
    ANDI.W	#0xF,D0                              | get lo nibble
    MOVE.B	NIBBLE_DOUBLE_TBL(PC,D0.W),(A1)+     | put expanded byte to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	QRTR2_LOOP_2                          | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------------------
|
| NIBBLE_DOUBLE_TBL -- 4-bit nibble -> 8-bit doubled output for 2x stretch.
| 16 entries: each input bit replicated to 2 output bits.
| E.g. 0001 -> 00000011 (0x03), 1010 -> 11001100 (0xCC).
|
NIBBLE_DOUBLE_TBL:
    .short	0x0003                               | 0000 -> 0x00, 0001 -> 0x03
    .long	0x0C0F3033                            | 0010..0101: 0x0C,0x0F,0x30,0x33
    .long	0x3C3FC0C3                            | 0110..1001: 0x3C,0x3F,0xC0,0xC3
    .long	0xCCCFF0F3                            | 1010..1101: 0xCC,0xCF,0xF0,0xF3
    .short	0xFCFF                               | 1110 -> 0xFC, 1111 -> 0xFF
| RTS ;ALL DONE

| .BYTE $30,$33,$3C,$3F
| .BYTE $C0,$C3,$CC,$CF
| .BYTE $F0,$F3,$FC,$FF

| -----------------------------------------------
|
| TRIPLE -- triple using table lookup. Each src byte becomes
| 3 dst bytes (each input bit replicated 3x via three different
| nibble-position tables for the 8-bit input split as 3+3+2 bits).
|
TRIPLE:
    MOVE.B	(A0)+,D0                             | get a byte from src
    MOVE.W	D0,D1                                | make a copy
    MOVE.W	D0,D2                                | make another copy
    LSR.B	#0x5,D2                               | get hi 3 bits
    MOVE.B	TRIPLE_CONT(PC,D2.W),(A1)+           | expand to 8 bits, put to dst
    LSR.B	#0x2,D1                               | shift mid 3 bits down
    ANDI.W	#0xF,D1                              | mask to 4 bits (incl. one bit overlap)
    MOVE.B	TRIPLE_CONT_2(PC,D1.W),(A1)+         | expand mid bits, put to dst
    ANDI.W	#0x7,D0                              | mask lo 3 bits
    MOVE.B	TRIPLE_CONT_3(PC,D0.W),(A1)+         | expand lo bits, put to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	TRIPLE                                | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------------------
|
| TRIPLE_CONT -- 3-bit input -> 8-bit triplicated output (hi byte).
| 8 entries: each input bit replicated 3x, top 1 bit hardcoded.
| Input bits b2 b1 b0 -> output b2*3 b1*3 b0*3 in MS bits.
|
TRIPLE_CONT:
    .short	0x0003
    .long	0x1C1FE0E3
    .short	0xFCFF
| -----------------------------------------------------------
|
| TRIPLE_CONT_2 -- 4-bit input -> 8-bit triplicated mid byte.
| 16 entries.
|
TRIPLE_CONT_2:
    .short	0x0001
    .long	0x0E0F7071
    .long	0x7E7F8081
    .long	0x8E8FF0F1
    .short	0xFEFF
| -----------------------------------------------------------
|
| TRIPLE_CONT_3 -- 3-bit input -> 8-bit triplicated lo byte.
| 8 entries.
|
TRIPLE_CONT_3:
    .short	0x0007
    .long	0x383FC0C7
    .short	0xF8FF
| -----------------------------------------------
|
| QUAD -- quadruple using table lookup. Each src nibble
| becomes a 16-bit dst word with each input bit replicated 4x.
|
QUAD:
    MOVE.B	(A0)+,D0                             | get a byte from src
    MOVE.W	D0,D1                                | make an extra copy
    ANDI.W	#0xF0,D1                             | mask hi nibble
    LSR.W	#0x3,D1                               | shift for table index (mult by 2)
    MOVE.W	QUAD_CONT(PC,D1.W),(A1)+             | quadruple to dst
    ANDI.W	#0xF,D0                              | mask lo nibble
    ADD.W	D0,D0                                 | double for table index
    MOVE.W	QUAD_CONT(PC,D0.W),(A1)+             | quadruple to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	QUAD                                  | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------------------
|
| QUAD_CONT -- 4-bit input nibble -> 16-bit quadrupled output for 4x stretch.
| 16 word entries (one per nibble value 0..F), each input bit replicated 4x.
| E.g. 0001 -> 0000000000001111 (0x000F).
|
QUAD_CONT:
    .long	0x0000000F                            | 0000 -> 0x0000, 0001 -> 0x000F
    .long	0x00F000FF                            | 0010 -> 0x00F0, 0011 -> 0x00FF
    .long	0x0F000F0F                            | 0100 -> 0x0F00, 0101 -> 0x0F0F
    .long	0x0FF00FFF                            | 0110 -> 0x0FF0, 0111 -> 0x0FFF
    .long	0xF000F00F                            | 1000 -> 0xF000, 1001 -> 0xF00F
    .long	0xF0F0F0FF                            | 1010 -> 0xF0F0, 1011 -> 0xF0FF
    .long	0xFF00FF0F                            | 1100 -> 0xFF00, 1101 -> 0xFF0F
    .long	0xFFF0FFFF                            | 1110 -> 0xFFF0, 1111 -> 0xFFFF
| -----------------------------------------------
|
| SIX -- stretch by six (sextuple) using table lookup. Each src
| byte becomes 6 dst bytes, with input split as 3+4+3 bits indexing
| three different tables (SIX_CONT for hi 3 bits, SIX_CONT_2 for
| middle 4 bits, SIX_CONT_3 for lo 3 bits).
|
SIX:
    MOVE.B	(A0)+,D0                             | get a byte from src
    MOVE.W	D0,D1                                | make an extra copy
    ANDI.W	#0xE0,D1                             | mask hi 3 bits
    LSR.B	#0x4,D1                               | shift for table index
    MOVE.W	SIX_CONT(PC,D1.W),(A1)+              | sextuple to dst
    MOVE.W	D0,D1                                | get src byte again
    ANDI.W	#0x3C,D1                             | mask mid 4 bits
    LSR.B	#0x1,D1                               | shift for table index
    MOVE.W	SIX_CONT_2(PC,D1.W),(A1)+            | sextuple to dst
    MOVE.W	D0,D1                                | get src byte again
    ANDI.W	#0x7,D1                              | mask lo 3 bits
    ADD.W	D1,D1                                 | double for table index
    MOVE.W	SIX_CONT_3(PC,D1.W),(A1)+            | sextuple to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	SIX                                   | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------------------
|
| SIX_CONT -- 3-bit input -> 16-bit sextupled hi word. 8 entries.
| Each input bit is replicated 6x in the output.
|
SIX_CONT:
    .long	0x0000000F                            | 000 -> 0x0000, 001 -> 0x000F
    .long	0x03F003FF                            | 010 -> 0x03F0, 011 -> 0x03FF
    .long	0xFC00FC0F                            | 100 -> 0xFC00, 101 -> 0xFC0F
    .long	0xFFF0FFFF                            | 110 -> 0xFFF0, 111 -> 0xFFFF
| -----------------------------------------------------------
|
| SIX_CONT_2 -- 4-bit input -> 16-bit sextupled mid word. 16 entries.
|
SIX_CONT_2:
    .long	0x00000003
    .long	0x00FC00FF
    .long	0x3F003F03
    .long	0x3FFC3FFF
    .long	0xC000C003
    .long	0xC0FCC0FF
    .long	0xFF00FF03
    .long	0xFFFCFFFF
| -----------------------------------------------------------
|
| SIX_CONT_3 -- 3-bit input -> 16-bit sextupled lo word. 8 entries.
|
SIX_CONT_3:
    .long	0x0000003F
    .long	0x0FC00FFF
    .long	0xF000F03F
    .long	0xFFC0FFFF
| -----------------------------------------------
|
| EIGHT -- scale up by eight (octuple) using table lookup.
| Each src nibble becomes a 32-bit dst long with each input
| bit replicated 8x.
|
EIGHT:
    MOVE.B	(A0)+,D0                             | get a byte of src
    MOVE.W	D0,D1                                | make an extra copy
    ANDI.W	#0xF0,D1                             | mask hi nibble
    LSR.W	#0x2,D1                               | shift for table index (mult by 4)
    MOVE.L	EIGHT_CONT(PC,D1.W),(A1)+            | octuple to dst
    ANDI.W	#0xF,D0                              | mask lo nibble
    LSL.W	#0x2,D0                               | shift for table index (mult by 4)
    MOVE.L	EIGHT_CONT(PC,D0.W),(A1)+            | octuple to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	EIGHT                                 | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------------------
|
| EIGHT_CONT -- 4-bit nibble -> 32-bit octupled output for 8x stretch.
| 16 long entries (each 8 bytes apart? actually 4 bytes for long).
| Each input bit replicated 8x.
|
EIGHT_CONT:
    .short	0x0000
    .long	0x00000000
    .long	0x00FF0000
    .long	0xFF000000
    .long	0xFFFF00FF
    .long	0x000000FF
    .long	0x00FF00FF
    .long	0xFF0000FF
    .long	0xFFFFFF00
    .long	0x0000FF00
    .long	0x00FFFF00
    .long	0xFF00FF00
    .long	0xFFFFFFFF
    .long	0x0000FFFF
    .long	0x00FFFFFF
    .long	0xFF00FFFF
    .short	0xFFFF
| -----------------------------------------------
|
| SIXTEEN -- scale up by 16. Each src bit becomes a full dst word
| (white = 0x0000 or black = 0xFFFF). Reads src 16 bits at a time
| via MOVE.W and shifts one bit out per dst word via ADDX.
|
SIXTEEN:
    MOVEQ.L	#-0x1,D1                            | get some black
    MOVE.W	#0x8000,D0                           | init src mask
SIXTENA:
    ADD.W	D0,D0                                 | get one bit of src
    BCC.B	WHITE16                               | br if white
    BNE.B	BLACK16                               | br if black
    MOVE.W	(A0)+,D0                             | else get next src word
    ADDX.W	D0,D0                                | shift src bit out, 1 bit in
    BCS.B	BLACK16                               | br if black
WHITE16:
    CLR.W	(A1)+                                 | put a word of white to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	SIXTENA                               | loop until DstLimit
    RTS                                         | all done
| ----------------------------------------------------------
|
| BLACK16 -- emit a black word
|
BLACK16:
    MOVE.W	D1,(A1)+                             | put a word of black to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    BCS.B	SIXTENA                               | loop until DstLimit
    RTS                                         | all done
| -----------------------------------------------
|
| EIGHTS -- scale up by any multiple of 8 greater than 2.
| D4 contains scale factor; LSR by 3 gives count of bytes per src bit.
|
EIGHTS:
    LSR.W	#0x3,D4                               | divide scale factor by 8
    SUBQ.W	#0x1,D4                              | minus one for DBRA
    MOVE.W	#0x8000,D0                           | init src mask
EIGHTS1:
    ADD.W	D0,D0                                 | get one src bit in carry
    BNE.B	EIGHTS2                               | time for new src ?
    MOVE.W	(A0)+,D0                             | yes, get next src long
    ADDX.W	D0,D0                                | shift src bit out, 1 bit in
EIGHTS2:
    SCS.B	D1                                    | set or clr a byte (0xFF or 0x00)
    MOVE.W	D4,D2                                | init loop count
EIGHTS3:
    MOVE.B	D1,(A1)+                             | put one byte to dst
    CMPA.L	A2,A1                                | is DstPtr >= DstLimit ?
    DBHI.W	D2,EIGHTS3                           | loop till scale or dst full
    BLS.B	EIGHTS1                               | more src if dst not full
    BRA.B	WHITE2_ERR                            | then quit
| ------------------------------------------------------------------
|
| SHRINK -- do full ratio scaling, shrinking one bit at a time.
| Bresenham-style DDA: D3 carries error term, D4 is ratio (numer).
|
SHRINK:
    CLR.W	D1                                    | init dst word
    MOVE.W	#0x8000,D0                           | init src mask
    MOVE.W	D0,D2                                | init mask
    MOVE.W	D4,D3                                | copy ratio
    LSR.W	#0x1,D3                               | init err to ratio/2
NXTSRC1:
    ADD.W	D0,D0                                 | get src bit
    BCC.B	WHITE1                                | branch if white
    BNE.B	NXTSRC1_CONT                          | branch if black
    MOVE.W	(A0)+,D0                             | else get new src word
    ADDX.W	D0,D0                                | get src bit
    BCC.B	WHITE1                                | and continue
NXTSRC1_CONT:
    OR.W	D2,D1                                  | set a bit in dst
WHITE1:
    ADD.W	D4,D3                                 | time for next dst bit ?
    BCC.B	NXTSRC1                               | no, loop more src
    ROR.W	#0x1,D2                               | yes, rotate mask
    BCC.B	NXTSRC1                               | loop if dst word OK
    MOVE.W	D1,(A1)+                             | else write word to dst
    CLR.W	D1                                    | reset dst word
    CMPA.L	A2,A1                                | DstPtr >= DstLimit ?
    BCS.B	NXTSRC1                               | loop until DstLimit
    RTS                                         | yes, quit
| ------------------------------------------------------------------
|
| WHITE1_CONT -- do full ratio scaling, stretching one bit at a time.
| Bresenham-style DDA, mirror image of SHRINK above.
|
WHITE1_CONT:
    CLR.W	D1                                    | init dst word
    MOVE.W	#0x8000,D0                           | init src mask
    MOVE.W	D0,D2                                | init mask
    MOVE.W	D4,D3                                | copy ratio
    LSR.W	#0x1,D3                               | init err to ratio/2
NXTSRC2:
    ADD.W	D0,D0                                 | get src bit
    BCC.B	WHITE2                                | branch if white
    BNE.B	BLACKOK_CONT                          | branch if black
    MOVE.W	(A0)+,D0                             | else get new src word
    ADDX.W	D0,D0                                | get src bit
    BCC.B	WHITE2                                | continue with white
    BRA.B	BLACKOK_CONT                          | continue with black
| ----------------------------------------------------------
|
| BLACKOK -- src bit was 1, time for next dst bit
|
BLACKOK:
    ADD.W	D4,D3                                 | time for next src bit ?
    BCS.B	NXTSRC2                               | yes, loop for src
BLACKOK_CONT:
    OR.W	D2,D1                                  | set a bit of dst
    ROR.W	#0x1,D2                               | rotate mask
    BCC.B	BLACKOK                               | loop if dst word OK
    MOVE.W	D1,(A1)+                             | else write word to dst
    CLR.W	D1                                    | reset dst word
    CMPA.L	A2,A1                                | DstPtr >= DstLimit ?
    BCS.B	BLACKOK                               | loop until DstLimit
    RTS                                         | yes, quit
| ----------------------------------------------------------
|
| WHITEOK -- src bit was 0, time for next dst bit
|
WHITEOK:
    ADD.W	D4,D3                                 | time for next src bit ?
    BCS.B	NXTSRC2                               | yes, loop for src
WHITE2:
    ROR.W	#0x1,D2                               | rotate mask
    BCC.B	WHITEOK                               | loop if dst word OK
    MOVE.W	D1,(A1)+                             | else write word to dst
    CLR.W	D1                                    | reset dst word
    CMPA.L	A2,A1                                | DstPtr >= DstLimit ?
    BCS.B	WHITEOK                               | loop until DstLimit
WHITE2_ERR:
    RTS                                         | done
