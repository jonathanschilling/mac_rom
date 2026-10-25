| -----------------------------------------------------------
|
|
|     ****   ***  *****  *     *     *     ****    ***
|     *   *   *     *    **   **    * *    *   *  *   *
|     *   *   *     *    * * * *   *   *   *   *  *
|     ****    *     *    *  *  *   *   *   ****    ***
|     *   *   *     *    *     *   *****   *          *
|     *   *   *     *    *     *   *   *   *      *   *
|     ****   ***    *    *     *   *   *   *       ***
|
|
|
|  QuickDraw Routines to operate on BitMaps.

| ---------------------------------------------------------------
|
| PROCEDURE StdBits(VAR srcBits: BitMap;
|                   VAR srcRect: Rect;
|                   VAR dstRect: Rect;
|                   mode: INTEGER;
|                   maskRgn: RgnHandle);
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 18
|   SRCBITS   = PARAMSIZE+8-4  (LONG, addr of BitMap)
|   SRCRECT   = SRCBITS-4      (LONG, addr of Rect)
|   DSTRECT   = SRCRECT-4      (LONG, addr of Rect)
|   MODE      = DSTRECT-2      (WORD)
|   MASKRGN   = MODE-4         (LONG, RgnHandle)
| Locals:
|   MYBITS  = -14   (BitMap)
|   PACKBUF = -270  (256-byte scanline packing buffer)
|   SRCPTR  = -274  (LONG)
|   DSTPTR  = -278  (LONG)
|
STDBITS:
    LINK	A6,#-0x116                             | allocate local vars
    MOVEM.L	D3-D7/A2-A4,-(A7)                   | save regs
    JSR	CHECKPIC(PC)                            | set up A4,A3 and check PicSave
    BLE.W	STDBITS_NOTPIC                        | branch if not PicSave
    MOVEQ.L	#0x8,D6                             | D6 := 8 (pack threshold)
|
| Trim srcBits
|
    MOVEA.L	0x16(A6),A0                         | get addr of srcBits
    LEA.L	-0xE(A6),A1                           | point to my copy
    MOVEA.L	(A0),A3                             | get baseAddr
    MOVE.W	0x4(A0),D4                           | get old rowBytes
    MOVE.L	0x6(A0),0x6(A1)                      | copy bounds top+left
    MOVE.L	0xA(A0),0xA(A1)                      | copy bounds bottom+right
    MOVEA.L	0x12(A6),A0                         | point to srcRect
    MOVE.W	(A0),D0                              | get srcRect.top
    SUB.W	0x6(A1),D0                            | calc SkipTop
    BLE.B	TOPOK                                 | continue if SkipTop neg
    ADD.W	D0,0x6(A1)                            | adjust bounds.top
    MULU.W	D4,D0                                | calc vert offset
    ADDA.L	D0,A3                                | adjust baseAddr
TOPOK:
    MOVE.W	0x4(A0),D0                           | get srcRect.bottom
    CMP.W	0xA(A1),D0                            | is bottom < bounds.bot ?
    BGE.B	BOTOK                                 | no, continue
    MOVE.W	D0,0xA(A1)                           | yes, trim bounds.bottom
BOTOK:
    MOVE.W	0x2(A0),D0                           | get srcRect.left
    SUB.W	0x8(A1),D0                            | calc SkipLeft
    BLE.B	LEFTOK                                | continue if SkipLeft neg
    LSR.W	#0x3,D0                               | div by 8 for skip bytes
    ADDA.W	D0,A3                                | offset baseAddr horiz
    LSL.W	#0x3,D0                               | bytes times 8 for dots
    ADD.W	D0,0x8(A1)                            | adjust bounds.left
LEFTOK:
    MOVE.W	0x6(A0),D0                           | get srcRect.right
    SUB.W	0x8(A1),D0                            | calc delta right
    ADDQ.W	#0x7,D0                              | round up to byte
    LSR.W	#0x3,D0                               | to next mult of 8
    LSL.W	#0x3,D0                               | convert back to dots
    ADD.W	0x8(A1),D0                            | add bounds.left back
    CMP.W	0xC(A1),D0                            | is new right < bounds.right ?
    BGE.B	LEFTOK_NO                             | no, continue
    MOVE.W	D0,0xC(A1)                           | yes, trim bounds.right
LEFTOK_NO:
    MOVE.W	0xC(A1),D5                           | get trimmed right
    SUB.W	0x8(A1),D5                            | calc width in dots
    ADDI.W	#0xF,D5                              | round up to word
|
| Calc new rowBytes after trimming
|
    LSR.W	#0x4,D5                               | div by 16
    BLE.W	START2_DONE                           | ignore if NewRow <= 0
    ADD.W	D5,D5                                 | double for new rowBytes
    MOVE.W	D5,0x4(A1)                           | copy rowBytes
    MOVE.B	#0x90,-(A7)                          | base opcode for BitsRect
    TST.L	0x8(A6)                               | is maskRgn nil ?
    BEQ.B	NOTRGN                                | yes, continue
    ADDQ.B	#0x1,(A7)                            | change to BitsRgn opcode
NOTRGN:
    CMP.W	D6,D5                                 | is NewRow < 8 ?
    BLT.B	NOPACK                                | yes, don't bitpack
    ADDQ.B	#0x8,(A7)                            | add PackBits flag to opcode
NOPACK:
    JSR	PUTPICBYTE(PC)                          | put opcode to thePic
    PEA.L	-0xA(A6)                              | push addr of MyBits+rowBytes
    MOVE.W	#0xA,-(A7)                           | push ByteCount = 10
    JSR	PUTPICDATA(PC)                          | put rowBytes, bounds to thePic
    MOVE.L	0x12(A6),-(A7)                       | push srcRect addr
    MOVE.W	D6,-(A7)                             | push ByteCount = 8
    JSR	PUTPICDATA(PC)                          | put srcRect
    MOVE.L	0xE(A6),-(A7)                        | push dstRect addr
    MOVE.W	D6,-(A7)                             | push ByteCount = 8
    JSR	PUTPICDATA(PC)                          | put dstRect
    MOVE.W	0xC(A6),-(A7)                        | push mode word
    JSR	PUTPICWORD(PC)                          | put mode
    TST.L	0x8(A6)                               | is maskRgn nil ?
    BEQ.B	NOPACK_SKIP                           | yes, skip it
    MOVE.L	0x8(A6),-(A7)                        | no, push maskRgn
    JSR	PUTPICRGN(PC)                           | put maskRgn to thePic
| NOMASK
|
| NOW PUT THE BITMAP DATA: IF NEWROW >= 8 THEN USE PACKBITS
|
NOPACK_SKIP:
    LEA.L	-0xE(A6),A2                           | point to (trimmed) bitmap
    MOVE.W	0xA(A2),D7                           | get bounds.bottom
    SUB.W	0x6(A2),D7                            | calc height
|
| Now put the bitmap data: if NewRow >= 8 then use PackBits
|
    CMP.W	D6,D5                                 | is NewRow < 8 ?
    BLT.B	START2                                | yes, don't try to pack
    BRA.B	START1                                | go to loop start
| ----------------------------------------------------------
|
| MORE1 -- pack one scanline via PackBits and emit packed length + data
|
MORE1:
    MOVE.L	A3,-0x112(A6)                        | SrcPtr := ^scanline data
    LEA.L	-0x10E(A6),A0                         | point to PackBuf
    MOVE.L	A0,-0x116(A6)                        | DstPtr := @PackBuf
    PEA.L	-0x112(A6)                            | push VAR SrcPtr
    PEA.L	-0x116(A6)                            | push VAR DstPtr
    MOVE.W	D5,-(A7)                             | push SrcBytes = NewRow
    JSR	PACKBITS(PC)                            | pack row into PackBuf
    MOVE.L	-0x116(A6),D6                        | get updated DstPtr
    LEA.L	-0x10E(A6),A0                         | point to PackBuf
    SUB.L	A0,D6                                 | calc packed ByteCount
    MOVE.B	D6,-(A7)                             | push packed ByteCount
    JSR	PUTPICBYTE(PC)                          | put packed ByteCount to thePic
    PEA.L	-0x10E(A6)                            | push PackBuf addr
    MOVE.W	D6,-(A7)                             | push packed size
    JSR	PUTPICDATA(PC)                          | put packed data to thePic
    ADDA.W	D4,A3                                | add OldRow to bits ptr
START1:
    DBF.W	D7,MORE1                              | loop for height rows
    BRA.B	START2_DONE                           | skip to done
|
| Row width < 8, don't use PackBits
|
MORE2:
    MOVE.L	A3,-(A7)                             | push addr of bits
    MOVE.W	D5,-(A7)                             | push ByteCount = NewRow
    JSR	PUTPICDATA(PC)                          | put one row of bitmap data
    ADDA.W	D4,A3                                | add OldRow to bits ptr
START2:
    DBF.W	D7,MORE2                              | loop for height rows
START2_DONE:
    MOVEA.L	(A4),A3                             | restore thePort ptr
STDBITS_NOTPIC:
    TST.W	0x42(A3)                              | is PnVis >= 0 ?
    BLT.B	STDBITS_GOHOME                        | no, quit
    MOVE.L	0x16(A6),-(A7)                       | push srcBits
    PEA.L	0x2(A3)                               | push dstBits = portBits
    MOVE.L	0x12(A6),-(A7)                       | push srcRect
    MOVE.L	0xE(A6),-(A7)                        | push dstRect
    MOVE.W	0xC(A6),-(A7)                        | push mode
    MOVE.L	0x1C(A3),-(A7)                       | push clipRgn
    MOVE.L	0x18(A3),-(A7)                       | push visRgn
    MOVE.L	0x8(A6),-(A7)                        | push maskRgn
    BNE.B	MASKOK                                | was it nil ?
    MOVE.L	-0x82(A4),(A7)                       | yes, replace with WideOpen
MASKOK:
    JSR	STRETCHBITS(PC)                         | call StretchBits
STDBITS_GOHOME:
    MOVEM.L	(A7)+,D3-D7/A2-A4                   | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x12,A7                             | strip 18 bytes of params
    JMP	(A0)                                    | tail-call return from STDBITS_GOHOME via A0
| ---------------------------------------------------------------
|
| PROCEDURE CopyBits(srcBits, dstBits: BitMap;
|                    srcRect, dstRect: Rect;
|                    mode: INTEGER;
|                    maskRgn: RgnHandle);
|
| A6 offsets of params and locals after LINK:
|   PARAMSIZE = 22
|   SRCBITS   = PARAMSIZE+8-4  (LONG, addr of BitMap)
|   DSTBITS   = SRCBITS-4      (LONG, addr of BitMap)
|   SRCRECT   = DSTBITS-4      (LONG, addr of Rect)
|   DSTRECT   = SRCRECT-4      (LONG, addr of Rect)
|   MODE      = DSTRECT-2      (WORD)
|   MASKRGN   = MODE-4         (LONG, RgnHandle)
|
COPYBITS:
    LINK	A6,#0x0                                | no local vars
    MOVEM.L	D6-D7/A2-A4,-(A7)                   | save regs
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEA.L	(A4),A3                             | get thePort
    MOVEA.L	0x1A(A6),A2                         | point to srcBits
    MOVE.L	(A2),D7                              | get src baseAddr
    MOVE.L	-0x7A(A4),D6                         | get screen baseAddr
    CMP.L	D6,D7                                 | is src from the screen ?
    BNE.B	SRCOK                                 | no, continue
    MOVE.L	0x12(A6),-(A7)                       | yes, push srcRect
    MOVE.L	0x6(A2),-(A7)                        | push srcBits.bounds.topLeft
    JSR	SHIELDCURSOR(PC)                        | hide the cursor if in srcRect
| -----------------------------------------------------
|
| Test if dst is to thePort. (If so, we clip.)
|
SRCOK:
    MOVEA.L	0x16(A6),A1                         | point to dstBits
    MOVE.L	A3,D0                                | is thePort nil ?
    BEQ.B	NOTPORT                               | yes, not to thePort
    BTST	#0x0,D0                                | is thePort odd ?
    BNE.B	NOTPORT                               | yes, not to thePort
    MOVE.L	0x2(A3),D0                           | get port baseAddr
    CMP.L	(A1),D0                               | does dst baseAddr = port ?
    BNE.B	NOTPORT                               | no, not to thePort
    MOVE.L	0x8(A3),D0                           | get port bounds.topLeft
    CMP.L	0x6(A1),D0                            | is bounds.topLeft same ?
    BEQ.B	TOPORT                                | yes, it's probably to thePort
|
| Dst is definitely not to thePort, so we can't use the capture proc.
| StretchBits(srcBits,dstBits,srcRect,dstRect,mode,wideOpen,wideOpen,maskRgn)
|
NOTPORT:
    MOVE.L	A2,-(A7)                             | push srcBits
    MOVE.L	A1,-(A7)                             | push dstBits
    MOVE.L	0x12(A6),-(A7)                       | push srcRect
    MOVE.L	0xE(A6),-(A7)                        | push dstRect
    MOVE.W	0xC(A6),-(A7)                        | push mode
    MOVE.L	-0x82(A4),-(A7)                      | push WideOpen
    MOVE.L	(A7),-(A7)                           | push WideOpen
    MOVE.L	0x8(A6),-(A7)                        | push maskRgn
    BNE.B	COPYBITS_MASKOK                       | was it nil ?
    MOVE.L	-0x82(A4),(A7)                       | yes, replace with WideOpen
COPYBITS_MASKOK:
    JSR	STRETCHBITS(PC)                         | call StretchBits
    BRA.B	CLEANUP                               | and continue
|
| Dst is probably to thePort, so we use the capture proc.
| CallBits(srcBits,srcRect,dstRect,mode,maskRgn)
|
TOPORT:
    MOVE.L	A2,-(A7)                             | push srcBits
    MOVE.L	0x12(A6),-(A7)                       | push srcRect
    MOVE.L	0xE(A6),-(A7)                        | push dstRect
    MOVE.W	0xC(A6),-(A7)                        | push mode
    MOVE.L	0x8(A6),-(A7)                        | push maskRgn (nil OK)
    MOVE.L	0x68(A3),D0                          | is GrafProcs nil ?
    MOVEA.L	(0x11AC).W,A0                       | _StdBits (BitsProc)
    BEQ.B	COPYBITS_USESTD                       | yes, use std proc
    MOVEA.L	D0,A0                               | point to GrafProcs
    MOVEA.L	0x20(A0),A0                         | no, get proc ptr
COPYBITS_USESTD:
    JSR	(A0)                                    | call it
CLEANUP:
    CMP.L	D6,D7                                 | was src from the screen ?
    BNE.B	COPYBITS_DONE                         | no, continue
    JSR	SHOWCURSOR(PC)                          | yes, replace cursor
COPYBITS_DONE:
    MOVEM.L	(A7)+,D6-D7/A2-A4                   | restore regs
    UNLK	A6                                     | release local vars
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x16,A7                             | strip 22 bytes of params
    JMP	(A0)                                    | tail-call return from COPYBITS_DONE via A0
| --------------------------------------------------------------
|
| PROCEDURE CopyMask(srcBits, maskBits, dstBits: BitMap;
|                    srcRect, maskRect, dstRect: Rect);
|
| New routine added to QuickDraw April 28, 1985 by Bill Atkinson.
| CopyRight 1985 Apple Computer Inc.
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 24
|   SRCBITS   = PARAMSIZE+8-4
|   MASKBITS  = SRCBITS-4
|   DSTBITS   = MASKBITS-4
|   SRCRECT   = DSTBITS-4
|   MASKRECT  = SRCRECT-4
|   DSTRECT   = MASKRECT-4
|
COPYMASK:
    LINK	A6,#-0x5E                              | allocate local vars
    MOVEM.L	D0-D7/A1-A4,-(A7)                   | save regs
    MOVE.L	A7,-0x5E(A6)                         | remember stack for later
    MOVEA.L	(A5),A2                             | point to QD globals
    MOVE.L	-0x82(A2),-0xC(A6)                   | init RGNA to WideOpen
    MOVE.L	-0x82(A2),-0x10(A6)                  | init RGNB to WideOpen
    MOVEA.L	(A2),A2                             | get thePort
    MOVEA.L	0x14(A6),A4                         | A4 points to dstBits
    MOVEA.L	0x8(A6),A3                          | A3 points to dstRect
    MOVE.L	0x2(A2),D0                           | get port baseAddr
    CMP.L	(A4),D0                               | is dst = port BitMap ?
|
| If dst is in thePort, then clip to visRgn and clipRgn
|
    BNE.B	COPYMASK_NO                           | no, continue
    MOVE.L	0x1C(A2),-0xC(A6)                    | yes, clip to clipRgn
    MOVE.L	0x18(A2),-0x10(A6)                   | and to visRgn
| NOTPORT
|
| Calc MinRect, the intersection of dstRect, dstBits.bounds,
| and two region bounding boxes. Quit if result is empty.
|
COPYMASK_NO:
    MOVE.L	A3,-(A7)                             | push dstRect
    PEA.L	0x6(A4)                               | push dstBits.bounds
    MOVEA.L	-0xC(A6),A0                         | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    PEA.L	0x2(A0)                               | push bounding box
    MOVEA.L	-0x10(A6),A0                        | get RgnHandle
    MOVEA.L	(A0),A0                             | de-reference it
    PEA.L	0x2(A0)                               | push bounding box
    MOVE.W	#0x4,-(A7)                           | push nRects = 4
    PEA.L	-0x8(A6)                              | push where to put result
    JSR	RSECT(PC)                               | intersect 4 rects
    BEQ.W	COPYMASK_GOHOME                       | quit if empty
    JSR	HIDECURSOR(PC)                          | else hide the cursor
    MOVE.W	-0x6(A6),D1                          | get MinRect left
    SUB.W	0x8(A4),D1                            | subtract dst bounds.left
    ANDI.W	#0xFFF0,D1                           | round down to mult of 16
    ADD.W	0x8(A4),D1                            | add back bounds.left
|
| Calc BufLeft so that RgnBuf will align to dstBits
|
    MOVE.W	D1,-0x42(A6)                         | save as BufLeft
|
| Init both region state records and allocate buffers
|
    MOVEA.L	-0xC(A6),A0                         | get RgnHandle
    LEA.L	-0x28(A6),A1                          | point to state record
| AGAIN -- bitmap region init loop entry: dereference rgn, init
|          scan state, allocate scanline buffer
AGAIN:
    MOVEA.L	(A0),A0                             | de-reference RgnHandle
    CMPI.W	#0xA,(A0)                            | is region rectangular ?
    SEQ.B	D7                                    | remember for below
    MOVE.W	-0x6(A6),D0                          | get MinRect left
    MOVE.W	-0x2(A6),D1                          | get MinRect right
    MOVE.W	-0x42(A6),D2                         | get BufLeft
    JSR	INITRGN(PC)                             | init state, alloc buffer
|
| If region was rectangular, draw top scanline into its buffer
| and set up ThisV and NextV so SeekRgn does nothing
|
    TST.B	D7                                    | was region rectangular ?
    BEQ.B	NOTRECT                               | no, continue
    MOVE.W	#0x8001,0xE(A1)                      | NextV := -32767
    MOVE.W	#0x7FFF,0x10(A1)                     | EndV := 32767
    MOVEA.L	0x8(A1),A0                          | point to buffer
    MOVE.W	-0x6(A6),D3                          | get MinRect left
    SUB.W	-0x42(A6),D3                          | make buffer relative
    MOVE.W	-0x2(A6),D4                          | get MinRect right
    SUB.W	-0x42(A6),D4                          | make buffer relative
    JSR	XORSLAB(PC)                             | draw into buffer
NOTRECT:
    LEA.L	-0x40(A6),A0                          | point to state record B
    CMPA.L	A0,A1                                | did we just do RgnB ?
    BEQ.B	GETDST                                | yes, continue
    MOVEA.L	A0,A1                               | no, point to StateB
    MOVEA.L	-0x10(A6),A0                        | get RgnB handle
    BRA.B	AGAIN                                 | and loop to init StateB
|
| Set up dstRow and starting dstAddr
|
GETDST:
    MOVE.W	0x4(A4),D1                           | get dst rowBytes
    EXT.L	D1                                    | make it long
    MOVE.L	D1,-0x5A(A6)                         | save dstRow for later
    MOVE.W	-0x8(A6),D0                          | get MinRect top
    SUB.W	0x6(A4),D0                            | subtract dst bounds.top
    MULU.W	D1,D0                                | mult by rowBytes
    MOVEA.L	(A4),A0                             | get dst baseAddr
    ADDA.L	D0,A0                                | add vertical offset
    MOVE.W	-0x6(A6),D0                          | get MinRect left
    SUB.W	0x8(A4),D0                            | subtract dst bounds.left
    LSR.W	#0x4,D0                               | convert dots to words
    ADD.W	D0,D0                                 | double for bytes
    ADDA.W	D0,A0                                | add horizontal offset
    MOVE.L	A0,-0x4E(A6)                         | save result in dstAddr
|
| Set up srcRow, srcShift, and starting srcAddr
|
    MOVEA.L	0x10(A6),A1                         | point to srcRect
    MOVEA.L	0x1C(A6),A2                         | point to srcBits
    MOVE.W	0x4(A2),D1                           | get src rowBytes
    EXT.L	D1                                    | make it long
    MOVE.L	D1,-0x52(A6)                         | save srcRow for later
    MOVE.W	0x2(A3),D6                           | get dst left
    SUB.W	0x8(A4),D6                            | subtract dst bounds.left
    MOVE.W	0x2(A1),D1                           | get src left
    SUB.W	0x8(A2),D1                            | subtract src bounds.left
    SUB.W	D1,D6                                 | calc delta horiz
    ANDI.W	#0xF,D6                              | SrcShift := delta MOD 16
    MOVE.W	-0x8(A6),D0                          | get MinRect top
    SUB.W	(A3),D0                               | subtract dstRect.top
    ADD.W	(A1),D0                               | add srcRect.top
    SUB.W	0x6(A2),D0                            | subtract src bounds.top
    MULU.W	0x4(A2),D0                           | mult by src rowBytes
    MOVEA.L	(A2),A0                             | get src baseAddr
    ADDA.L	D0,A0                                | add vertical offset
    MOVE.W	-0x6(A6),D0                          | get MinRect left
    SUB.W	0x2(A3),D0                            | convert from dst coords
    ADD.W	0x2(A1),D0                            | to src coords
    SUB.W	0x8(A2),D0                            | subtract src bounds.left
    ADD.W	D6,D0                                 | add SrcShift
    LSR.W	#0x4,D0                               | convert dots to words
    ADD.W	D0,D0                                 | double for bytes
    ADDA.W	D0,A0                                | add horiz offset
    MOVE.L	A0,-0x46(A6)                         | save srcAddr for later
|
| Set up maskRow, maskShift, and starting maskAddr
|
    MOVEA.L	0xC(A6),A1                          | point to maskRect
    MOVEA.L	0x18(A6),A2                         | point to maskBits
    MOVE.W	0x4(A2),D1                           | get mask rowBytes
    EXT.L	D1                                    | make it long
    MOVE.L	D1,-0x56(A6)                         | save maskRow for later
    MOVE.W	0x2(A3),D7                           | get dst left
    SUB.W	0x8(A4),D7                            | subtract dst bounds.left
    MOVE.W	0x2(A1),D1                           | get mask left
    SUB.W	0x8(A2),D1                            | subtract mask bounds.left
    SUB.W	D1,D7                                 | calc delta horiz
    ANDI.W	#0xF,D7                              | MaskShift := delta MOD 16
    MOVE.W	-0x8(A6),D0                          | get MinRect top
    SUB.W	(A3),D0                               | subtract dstRect.top
    ADD.W	(A1),D0                               | add maskRect.top
    SUB.W	0x6(A2),D0                            | subtract mask bounds.top
    MULU.W	0x4(A2),D0                           | mult by mask rowBytes
    MOVEA.L	(A2),A0                             | get mask baseAddr
    ADDA.L	D0,A0                                | add vertical offset
    MOVE.W	-0x6(A6),D0                          | get MinRect left
    SUB.W	0x2(A3),D0                            | convert from dst coords
    ADD.W	0x2(A1),D0                            | to mask coords
    SUB.W	0x8(A2),D0                            | subtract mask bounds.left
    ADD.W	D7,D0                                 | add MaskShift
    LSR.W	#0x4,D0                               | convert dots to words
    ADD.W	D0,D0                                 | double for bytes
    ADDA.W	D0,A0                                | add horiz offset
    MOVE.L	A0,-0x4A(A6)                         | save maskAddr for later
    MOVE.W	-0x8(A6),D5                          | init vert to MinRect.top
COPYMASK_NEXTROW:
    MOVE.W	D5,D0                                | get current vert
    LEA.L	-0x28(A6),A1                          | point to state record A
    JSR	SEEKRGN(PC)                             | seek region to current vert
    MOVE.W	D5,D0                                | get current vert
    LEA.L	-0x40(A6),A1                          | point to state record B
    JSR	SEEKRGN(PC)                             | seek region to current vert
    MOVEA.L	-0x20(A6),A0                        | get StateA scanBuf ptr
    MOVEA.L	-0x38(A6),A1                        | get StateB scanBuf ptr
    MOVEA.L	-0x46(A6),A2                        | init SrcPtr
    MOVEA.L	-0x4A(A6),A3                        | init MaskPtr
    MOVEA.L	-0x4E(A6),A4                        | init DstPtr
    MOVE.W	-0x1C(A6),D3                         | get long count for loop
COPYMASK_NEXTROW_LOOP:
    MOVE.L	-0x2(A2),D0                          | get src long (unaligned)
    LSR.L	D6,D0                                 | align to dst
    SWAP.W	D0                                   | put result in hi word
    MOVE.L	(A2)+,D1                             | get second long of src
    LSR.L	D6,D1                                 | align to dst
    MOVE.W	D1,D0                                | combine hi and lo src halves
    MOVE.L	-0x2(A3),D1                          | get mask long (unaligned)
    LSR.L	D7,D1                                 | align to dst
    SWAP.W	D1                                   | put result in hi word
    MOVE.L	(A3)+,D2                             | get second long of mask
    LSR.L	D7,D2                                 | align to dst
    MOVE.W	D2,D1                                | combine hi and lo mask halves
    AND.L	(A0)+,D1                              | and with RgnA buffer
    AND.L	(A1)+,D1                              | and with RgnB buffer
    AND.L	D1,D0                                 | mask src data
    NOT.L	D1                                    | form NotMask
    AND.L	(A4),D1                               | get dst data
    OR.L	D1,D0                                  | merge with src data
    MOVE.L	D0,(A4)+                             | store result into dst
    DBF.W	D3,COPYMASK_NEXTROW_LOOP              | loop all longs this scanline
|
| Bump vertically and loop for all scanlines
|
    MOVE.L	-0x52(A6),D0                         | get src rowBytes
    ADD.L	D0,-0x46(A6)                          | bump src to next row
    MOVE.L	-0x56(A6),D0                         | get mask rowBytes
    ADD.L	D0,-0x4A(A6)                          | bump mask to next row
    MOVE.L	-0x5A(A6),D0                         | get dst rowBytes
    ADD.L	D0,-0x4E(A6)                          | bump dst to next row
    ADDQ.W	#0x1,D5                              | bump vert
    CMP.W	-0x4(A6),D5                           | is vert < MinRect.bottom ?
    BNE.B	COPYMASK_NEXTROW                      | yes, do next row
    JSR	SHOWCURSOR(PC)                          | restore cursor
COPYMASK_GOHOME:
    MOVEA.L	-0x5E(A6),A7                        | strip variable-sized buffer
    MOVEM.L	(A7)+,D0-D7/A1-A4                   | restore registers
    UNLK	A6                                     | release local vars
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x18,A7                             | strip 24 bytes of params
    JMP	(A0)                                    | tail-call return from COPYMASK_GOHOME via A0
| -------------------------------------------------------------------------
|
| PROCEDURE SeedFill(srcPtr, dstPtr: Ptr;
|                    srcRow, dstRow, height, words: INTEGER;
|                    seedH, seedV: INTEGER);
|
SEEDFILL:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVEQ.L	#-0x1,D0                            | get a long of -1
    MOVE.L	D0,-(A7)                             | push edge = all ones
    BRA.B	CALCMASK_SHARE                        | share common code
| -------------------------------------------------------------------------
|
| PROCEDURE CalcMask(srcPtr, dstPtr: Ptr;
|                    srcRow, dstRow, height, words: INTEGER);
|
CALCMASK:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVEQ.L	#-0x1,D0                            | get a long of -1
    MOVE.L	D0,-(A7)                             | push seed = (-1,-1)
    CLR.L	-(A7)                                 | push edge = zeros
| -------------------------------------------------------------------------
|
| LOCAL PROCEDURE MakeMask(srcPtr, dstPtr: Ptr;
|                          srcRow, dstRow, height, words: INTEGER;
|                          seedH, seedV: INTEGER;
|                          edge: LongInt);
|
| A6 offsets after LINK:
|   srcPtr=0x1C, dstPtr=0x18, srcRow=0x16, dstRow=0x14, height=0x12,
|   words=0x10, seedH=0xE, seedV=0xC, edge=0x8
|   dstBump=-2, saveStk=-6
|
CALCMASK_SHARE:
    MOVE.L	A0,-(A7)                             | restore return addr
    LINK	A6,#-0x6                               | allocate local vars
    MOVEM.L	D3-D7/A2-A4,-(A7)                   | save regs
    MOVE.L	A7,-0x6(A6)                          | save stack pointer
|
| Prepare height and words for DBRA count. Quit if either <= 0.
|
    MOVE.W	0x10(A6),D5                          | get count of words
    BLE.W	INVERT2_EXIT                          | quit if words <= 0
    SUBQ.W	#0x1,D5                              | adjust for DBRA
    SUBQ.W	#0x1,0x12(A6)                        | adjust height for DBRA
    BLT.W	INVERT2_EXIT                          | quit if height <= 0
|
| Init dst to all ones
|
    MOVE.W	0x10(A6),D0                          | get # of words
    ADD.W	D0,D0                                 | double for bytes
    MOVE.W	0x14(A6),D1                          | get dstRow
    SUB.W	D0,D1                                 | subtract bytes for dstBump
    MOVE.W	D1,-0x2(A6)                          | save dstBump for later
    MOVEA.L	0x18(A6),A2                         | point to dst
    MOVEQ.L	#-0x1,D0                            | get some black
    MOVE.W	0x12(A6),D3                          | init DBRA rowCount
BLACK1:
    MOVE.W	D5,D2                                | init DBRA wordCount
BLACK2:
    MOVE.W	D0,(A2)+                             | put a word of black
    DBF.W	D2,BLACK2                             | loop all words in row
    ADDA.W	D1,A2                                | bump to next row
    DBF.W	D3,BLACK1                             | loop height rows
|
| Clear one dst pixel at (seedH, seedV)
|
    MOVE.W	0xC(A6),D0                           | get seed vert coord
    BLT.B	NOSEED                                | skip if neg (no seed)
    MULU.W	0x14(A6),D0                          | mul times dst row
    MOVEA.L	0x18(A6),A0                         | point to dst
    ADDA.L	D0,A0                                | offset to seed row
    MOVE.W	0xE(A6),D0                           | get seed horiz coord
    MOVE.W	D0,D1                                | copy seedH
    LSR.W	#0x3,D0                               | div by 8 for byte
    NOT.W	D1                                    | invert bit number
    BCLR	D1,0x0(A0,D0.W)                        | clear seed pixel bit
|
| Allocate a scanline buffer of ones or zeros on the stack
|
NOSEED:
    MOVE.L	0x8(A6),D6                           | get zero or all ones (edge)
    MOVE.W	D5,D1                                | get LongCount
NEXTBUF:
    MOVE.W	D6,-(A7)                             | write a word of ones or zeros
    DBF.W	D1,NEXTBUF                            | loop all words
    MOVEA.L	0x1C(A6),A0                         | point to top of src
    MOVEA.L	0x18(A6),A2                         | point to top of dst
NXTPASS:
    SF.B	D7                                     | clear dirty flag
    MOVE.W	0x12(A6),D4                          | get DBRA rowCount
    MOVEA.L	A7,A1                               | point dst above to EdgeBuf
|
| Smear dst zeros down and to the right, smear limited by src
|
CALCMASK_NEXTROW:
    MOVE.L	D6,D1                                | init prev dst to edge
    MOVE.W	D5,D3                                | get DBRA WordCount
RNEXT:
    MOVE.W	(A2),D1                              | get dst word
    BNE.B	RDSTOK                                | is it already zero ?
    ADDQ.W	#0x2,A0                              | skip src word
    ADDQ.W	#0x2,A1                              | skip above word
    ADDQ.W	#0x2,A2                              | skip dst word
    SWAP.W	D1                                   | put prev dst in hi word
    DBF.W	D3,RNEXT                              | loop all words in row
    BRA.W	LSMEAR                                | and continue below
| ----------------------------------------------------------
|
| RDSTOK -- vertical-smear setup for a non-zero dst word
|
RDSTOK:
    MOVE.W	(A0)+,D2                             | get src word
    AND.W	(A1)+,D1                              | smear zeros down
    OR.W	D2,D1                                  | limit vertical smear by src
    BRA.B	RSTART                                | go to loop start
| ----------------------------------------------------------
|
| RMORE -- iterate horizontal smear within current word
|
RMORE:
    MOVE.W	D0,D1                                | update dst
RSTART:
    MOVE.L	D1,D0                                | copy dst and prev dst word
    LSR.L	#0x1,D0                               | shift right with carry from prev
    AND.W	D1,D0                                 | smear zeros to the right
    OR.W	D2,D0                                  | limit smear by src
    CMP.W	D1,D0                                 | any changes ?
    BNE.B	RMORE                                 | yes, keep smearing
    CMP.W	(A2),D1                               | has dst changed ?
    BEQ.B	RSAME                                 | no, leave it alone
    ST.B	D7                                     | yes, set dirty flag
RSAME:
    MOVE.W	D1,(A2)+                             | write dst to memory
    SWAP.W	D1                                   | put prev dst in hi word
    DBF.W	D3,RNEXT                              | loop all words in row
|
| Smear dst zeros down and to the left, smear limited by src
|
LSMEAR:
    MOVE.L	D6,D1                                | init prev dst to edge
    MOVE.W	D5,D3                                | get DBRA WordCount
LNEXT:
    MOVE.W	-(A2),D1                             | get dst word
    BNE.B	LDSTOK                                | is dst already zero ?
    SUBQ.W	#0x2,A0                              | back up src word
    SUBQ.W	#0x2,A1                              | back up above word
    SWAP.W	D1                                   | put prev dst in hi word
    DBF.W	D3,LNEXT                              | loop all words in row
    BRA.B	LSAME_CONT                            | and continue
| ----------------------------------------------------------
|
| LDSTOK -- vertical-smear setup for a non-zero dst word (left direction)
|
LDSTOK:
    MOVE.W	-(A0),D2                             | get src word
    AND.W	-(A1),D1                              | smear zeros down
    OR.W	D2,D1                                  | limit vertical smear by src
    BRA.B	LSTART                                | go to loop start
| ----------------------------------------------------------
|
| LMORE -- iterate horizontal smear (left)
|
LMORE:
    MOVE.W	D0,D1                                | update dst
LSTART:
    MOVE.L	D1,D0                                | copy dst and prev dst word
    ROL.L	#0x1,D0                               | shift left with carry from prev
    AND.W	D1,D0                                 | smear zeros to the left
    OR.W	D2,D0                                  | limit smear by src
    CMP.W	D1,D0                                 | any changes ?
    BNE.B	LMORE                                 | yes, keep smearing
    CMP.W	(A2),D1                               | has dst changed ?
    BEQ.B	LSAME                                 | no, leave it alone
    ST.B	D7                                     | yes, set dirty flag
    MOVE.W	D1,(A2)                              | write dst to memory
LSAME:
    SWAP.W	D1                                   | put prev dst in hi word
    DBF.W	D3,LNEXT                              | loop all words in row
|
| Bump three pointers down and loop for height scanlines
|
LSAME_CONT:
    ADDA.W	0x16(A6),A0                          | bump SrcPtr down a row
    ADDA.W	0x14(A6),A2                          | bump DstPtr down a row
    MOVEA.L	A2,A1                               | copy DstPtr
    SUBA.W	0x14(A6),A1                          | point to dst above
    DBF.W	D4,CALCMASK_NEXTROW                   | loop all rows
|
| If dirty flag set, repeat the entire scan upside-down then
| right-side up until no further changes occur.
|
    NEG.W	0x16(A6)                              | flip srcRow sign
    NEG.W	0x14(A6)                              | flip dstRow sign
    ADDA.W	0x16(A6),A0                          | bump back to last row
    ADDA.W	0x14(A6),A2                          | bump back to last row
    TST.B	D7                                    | did anything change ?
    BNE.W	NXTPASS                               | yes, do another pass
    TST.W	D6                                    | was edge = -1 (CalcMask) ?
    BPL.B	INVERT2_EXIT                          | no (SeedFill), skip invert
|
| For CalcMask, invert dst (the result is the mask, the inverse
| of the smeared region).
|
    MOVE.W	-0x2(A6),D1                          | get dstBump
    MOVEA.L	0x18(A6),A2                         | point to top of dst
    MOVE.W	0x12(A6),D3                          | get DBRA rowCount
INVERT1:
    MOVE.W	D5,D2                                | init DBRA WordCount
INVERT2:
    NOT.W	(A2)+                                 | invert one word
    DBF.W	D2,INVERT2                            | loop all words in row
    ADDA.W	D1,A2                                | bump to next row
    DBF.W	D3,INVERT1                            | loop all rows
INVERT2_EXIT:
    MOVEA.L	-0x6(A6),A7                         | strip stack scanline buffer
    MOVEM.L	(A7)+,D3-D7/A2-A4                   | restore regs
    UNLK	A6                                     | release local vars
    MOVEA.L	(A7)+,A0                            | pop return addr
    ADDA.W	#0x18,A7                             | strip 24 bytes of params
    JMP	(A0)                                    | tail-call return from INVERT2_EXIT via A0
| ---------------------------------------------------------------------
|
| PROCEDURE ScrollRect(dstRect: Rect; dh, dv: INTEGER;
|                      updateRgn: RgnHandle);
|
| Scroll a rectangular block of bits, erase, and return an
| update region.
|
SCROLLRECT:
    LINK	A6,#-0x8                               | allocate srcRect local
    MOVEM.L	D6-D7/A3-A4,-(A7)                   | save regs
    MOVEA.L	(A5),A4                             | point to QD globals
    MOVEA.L	(A4),A3                             | get thePort
    TST.W	0x42(A3)                              | is PnVis < 0 ?
    BLT.W	ABORT                                 | yes, quit fast
    TST.L	0xC(A6)                               | is dstRect nil ?
    BEQ.W	ABORT                                 | yes, quit fast
    CLR.L	-(A7)                                 | room for fcn result
    JSR	NEWRGN(PC)                              | allocate srcRgn
    MOVE.L	(A7)+,D7                             | get srcRgn handle in D7
    CLR.L	-(A7)                                 | room for fcn result
    JSR	NEWRGN(PC)                              | allocate dstRgn
    MOVE.L	(A7)+,D6                             | get dstRgn handle in D6
|
| srcRgn := dstRect SectScan visRgn SectScan clipRgn
|
    MOVE.L	D7,-(A7)                             | push srcRgn
    MOVE.L	0x10(A6),-(A7)                       | push dstRect
    JSR	RECTRGN(PC)                             | RectRgn(srcRgn,dstRect)
    MOVE.L	D7,-(A7)                             | push srcRgn
    MOVE.L	0x18(A3),-(A7)                       | push visRgn
    MOVE.L	D7,-(A7)                             | push srcRgn
    JSR	SECTRGN(PC)                             | SectRgn(srcRgn,visRgn,srcRgn)
    MOVE.L	D7,-(A7)                             | push srcRgn
    MOVE.L	0x1C(A3),-(A7)                       | push clipRgn
    MOVE.L	D7,-(A7)                             | push srcRgn
    JSR	SECTRGN(PC)                             | SectRgn(srcRgn,clipRgn,srcRgn)
|
| dstRgn := offset srcRgn
|
    MOVE.L	D7,-(A7)                             | push srcRgn
    MOVE.L	D6,-(A7)                             | push dstRgn
    JSR	COPYRGN(PC)                             | CopyRgn(srcRgn,dstRgn)
    MOVE.L	D6,-(A7)                             | push dstRgn
    MOVE.L	0xC(A6),-(A7)                        | push dh,dv packed
    JSR	OFFSETRGN(PC)                           | OffsetRgn(dstRgn,dh,dv)
    MOVEA.L	0x10(A6),A0                         | point to dstRect
    MOVE.L	(A0)+,-0x8(A6)                       | copy dstRect into srcRect
    MOVE.L	(A0)+,-0x4(A6)                       | copy bottom+right
    MOVE.L	0xC(A6),D0                           | get dh in lo word
    SUB.W	D0,-0x6(A6)                           | srcRect.left -= dh
    SUB.W	D0,-0x2(A6)                           | srcRect.right -= dh
    SWAP.W	D0                                   | get dv in lo word
    SUB.W	D0,-0x8(A6)                           | srcRect.top -= dv
    SUB.W	D0,-0x4(A6)                           | srcRect.bottom -= dv
|
| Compute updateRgn := srcRgn - dstRgn
|
    MOVE.L	D7,-(A7)                             | push srcRgn
    MOVE.L	D6,-(A7)                             | push dstRgn
    MOVE.L	0x8(A6),-(A7)                        | push updateRgn
    JSR	DIFFRGN(PC)                             | DiffRgn(srcRgn,dstRgn,updateRgn)
|
| ShieldCursor(dstRect, portBits.bounds.topLeft) -- protect source
|
    MOVE.L	0x10(A6),-(A7)                       | push dstRect
    MOVE.L	0x8(A3),-(A7)                        | push portBits.bounds.topLeft
    JSR	SHIELDCURSOR(PC)                        | remove cursor if intersects
|
| Copy all bits which are in both srcRgn and dstRgn.
| RgnBlt(portBits, portBits, srcRect, dstRect, srcCopy, white,
|        dstRgn, srcRgn, wideOpen)
|
    PEA.L	0x2(A3)                               | push srcBits
    MOVE.L	(A7),-(A7)                           | push dstBits
    PEA.L	-0x8(A6)                              | push srcRect
    MOVE.L	0x10(A6),-(A7)                       | push dstRect
    CLR.W	-(A7)                                 | push mode = srcCopy
    CLR.L	-(A7)                                 | pat not used
    MOVE.L	D6,-(A7)                             | push dstRgn
    MOVE.L	D7,-(A7)                             | push srcRgn
    MOVE.L	-0x82(A4),-(A7)                      | push WideOpen
    JSR	RGNBLT(PC)                              | copy the bits
|
| Erase the update region.
| RgnBlt(portBits, portBits, dstRect, dstRect, patCopy, bkPat,
|        updateRgn, wideOpen, wideOpen)
|
    PEA.L	0x2(A3)                               | push srcBits
    MOVE.L	(A7),-(A7)                           | push dstBits
    MOVE.L	0x10(A6),-(A7)                       | push srcRect
    MOVE.L	(A7),-(A7)                           | push dstRect
    MOVE.W	#0x8,-(A7)                           | push mode = patCopy
    PEA.L	0x20(A3)                              | push pat = bkPat
    MOVE.L	0x8(A6),-(A7)                        | push updateRgn
    MOVE.L	-0x82(A4),-(A7)                      | push WideOpen
    MOVE.L	(A7),-(A7)                           | push WideOpen
    JSR	RGNBLT(PC)                              | erase the update rgn
    JSR	SHOWCURSOR(PC)                          | restore the cursor
    MOVEA.L	D7,A0                               | get srcRgn
    _DisposeHandle                              | discard srcRgn
    MOVEA.L	D6,A0                               | get dstRgn
    _DisposeHandle                              | discard dstRgn
    BRA.B	ABORT_DONE                            | skip to done
| ----------------------------------------------------------
|
| ABORT -- early-exit path: empty the updateRgn
|
ABORT:
    MOVE.L	0x8(A6),-(A7)                        | push updateRgn handle
    JSR	SETEMPTYRGN(PC)                         | set it to empty
ABORT_DONE:
    MOVEM.L	(A7)+,D6-D7/A3-A4                   | restore regs
    UNLK	A6                                     | release local vars
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0xC,A7                              | strip 12 bytes of params
    JMP	(A0)                                    | tail-call return from ABORT_DONE via A0
| ---------------------------------------------------------------------
|
| PROCEDURE PackBits(VAR srcPtr, dstPtr: Ptr; srcBytes: INTEGER);
|
| Packs one scanline of data, compressing equal bytes.
| Returns updated srcPtr and dstPtr.
|
| Equates for parameters are shared with UnpackBits:
|   PARAMSIZE = 10
|   SRCPTR    = PARAMSIZE+4-4  (LONG, VAR)
|   DSTPTR    = SRCPTR-4       (LONG, VAR)
|   SRCBYTES  = DSTPTR-2       (WORD)
|   DSTBYTES  = SRCBYTES       (alias)
|
PACKBITS:
    MOVE.L	A2,-(A7)                             | save regs
    MOVEA.L	0xE(A7),A0                          | get addr of SrcPtr VAR
    MOVEA.L	(A0),A0                             | get SrcPtr itself
    MOVEA.L	0xA(A7),A1                          | get addr of DstPtr VAR
    MOVEA.L	(A1),A1                             | get DstPtr itself
    MOVE.W	0x8(A7),D1                           | get SrcBytes
    SUBQ.W	#0x1,D1                              | adjust for DBRA
    BLT.B	ENDFILL_EXIT                          | quit if SrcBytes <= 0
    MOVE.B	(A0)+,D0                             | get first byte of src
    BRA.B	START                                 | and go to loop start
| ----------------------------------------------------------
|
| FILLOP -- emit a fill-op header byte and start a copy run
|
FILLOP:
    MOVE.B	-0x1(A0),D0                          | get prev src byte
    SUB.W	A0,D2                                 | compute FillOp
    ADDQ.W	#0x1,D2                              | adjust count
    MOVE.B	D2,(A2)                              | store FillOp
START:
    MOVE.W	A0,D2                                | remember SrcStart
    MOVEA.L	A1,A2                               | remember OpLoc
    CLR.B	(A1)+                                 | reserve room for opcode
    CMP.B	(A0),D0                               | is next src the same ?
    BNE.B	DOCOPY                                | no, use copy loop
    CMP.B	0x1(A0),D0                            | three in a row ?
    BNE.B	DOCOPY                                | no, use copy loop
    BRA.B	DOFILL                                | yes, use fill loop
| ----------------------------------------------------------
|
| NXTCOPY -- continue copying bytes; switch to fill if 3-in-a-row
|
NXTCOPY:
    MOVE.B	(A0)+,D0                             | get byte of src
    CMP.B	(A0),D0                               | is the next the same ?
    BNE.B	DOCOPY                                | no, continue
    CMP.B	0x1(A0),D0                            | three in a row ?
    BEQ.B	COPYOP                                | yes, end of copy run
DOCOPY:
    MOVE.B	D0,(A1)+                             | copy data to dst
    DBF.W	D1,NXTCOPY                            | and loop for more
ENDCOPY:
    SUB.W	A0,D2                                 | compute CopyOp
    NEG.W	D2                                    | negate only
    MOVE.B	D2,(A2)                              | install CopyOp
    BRA.B	ENDFILL_EXIT                          | and quit
| ----------------------------------------------------------
|
| COPYOP -- end of copy run; install CopyOp byte and start FillOp
|
COPYOP:
    TST.W	D1                                    | is this the last src byte ?
    BEQ.B	DOCOPY                                | yes, finish off copy run
    SUB.W	A0,D2                                 | compute CopyOp
    NOT.W	D2                                    | negate and subtract 1
    MOVE.B	D2,(A2)                              | store CopyOp
    MOVE.L	A0,D2                                | remember SrcStart
    MOVEA.L	A1,A2                               | remember OpLoc
    CLR.B	(A1)+                                 | reserve room for opcode
DOFILL:
    MOVE.B	D0,(A1)+                             | copy the data byte
NXTFILL:
    CMP.B	(A0)+,D0                              | is next byte the same ?
    DBNE.W	D1,NXTFILL                           | loop till not same or end src
    BEQ.B	ENDFILL                               | branch if src exhausted
    SUBQ.W	#0x1,D1                              | dec src counter
    BGE.B	FILLOP                                | br if src not exhausted
ENDFILL:
    SUB.W	A0,D2                                 | compute FillOp
    ADDQ.W	#0x1,D2                              | adjust count
    MOVE.B	D2,(A2)                              | install FillOp
ENDFILL_EXIT:
    MOVEQ.L	#0x0,D0                             | clear for word load
    MOVE.W	0x8(A7),D0                           | get SrcBytes
    MOVEA.L	0xE(A7),A0                          | get addr of SrcPtr VAR
    ADD.L	D0,(A0)                               | bump SrcPtr
    MOVEA.L	0xA(A7),A2                          | get addr of DstPtr VAR
    MOVE.L	A1,(A2)                              | update DstPtr
    MOVEA.L	(A7)+,A2                            | restore regs
ENDFILL_EXIT_2:
    MOVEA.L	(A7)+,A0                            | pop return addr
    ADDA.W	#0xA,A7                              | strip 10 bytes of params
    JMP	(A0)                                    | and return
| --------------------------------------------------------
|
| PROCEDURE UnpackBits(VAR srcPtr, dstPtr: Ptr; dstBytes: INTEGER);
|
| Unpacks one scanline of data, as compressed by PackBits.
| Returns updated srcPtr and dstPtr.
|
| Equates for parameters are the same as PackBits.
|
UNPACKBITS:
    MOVEA.L	0xA(A7),A0                          | get addr of SrcPtr
    MOVEA.L	(A0),A0                             | get SrcPtr itself
    MOVEA.L	0x6(A7),A1                          | get addr of DstPtr
    MOVEA.L	(A1),A1                             | get DstPtr itself
    MOVE.W	0x4(A7),D2                           | get DstBytes
    EXT.L	D2                                    | make it long
    ADD.L	A1,D2                                 | limit := DstPtr + ByteCount
    BRA.B	UNPACKBITS_SKIP                       | start unpack loop
| ----------------------------------------------------------
|
| UNPACKBITS_CONT -- 0..127: copy 1..128 bytes
|
UNPACKBITS_CONT:
    EXT.W	D1                                    | sign extend copy count
UNPACKBITS_LOOP:
    MOVE.B	(A0)+,(A1)+                          | copy one byte from src to dst
    DBF.W	D1,UNPACKBITS_LOOP                    | loop for copy count
UNPACKBITS_SKIP:
    CMPA.L	D2,A1                                | has dst reached limit ?
    BCC.B	UNPACKBITS_DONE                       | yes, done
    MOVE.B	(A0)+,D1                             | no, get opcode
    BPL.B	UNPACKBITS_CONT                       | 0..127 -> copy 1..128 bytes
    NEG.B	D1                                    | -1..-127 -> fill 2..128 bytes
    BVS.B	UNPACKBITS_SKIP                       | skip if -128 (NOP)
    EXT.W	D1                                    | sign extend fill count
    MOVE.B	(A0)+,D0                             | get fill data byte
UNPACKBITS_LOOP_2:
    MOVE.B	D0,(A1)+                             | fill one byte
    DBF.W	D1,UNPACKBITS_LOOP_2                  | loop for fill count
    BRA.B	UNPACKBITS_SKIP                       | check if more to unpack
| ----------------------------------------------------------
|
| UNPACKBITS_DONE
|
UNPACKBITS_DONE:
    MOVE.L	A0,D0                                | save updated SrcPtr
    MOVEA.L	0xA(A7),A0                          | get VAR addr
    MOVE.L	D0,(A0)                              | update VAR SrcPtr
    MOVEA.L	0x6(A7),A0                          | get VAR addr
    MOVE.L	A1,(A0)                              | update VAR DstPtr
    BRA.B	ENDFILL_EXIT_2                        | share common exit
