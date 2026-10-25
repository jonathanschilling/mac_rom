| -----------------------------------------------------------
|
|
|     ****   *****   ***   *****   ***
|     *   *  *      *   *    *    *   *
|     *   *  *      *        *    *
|     ****   ***    *        *     ***
|     * *    *      *        *        *
|     *  *   *      *   *    *    *   *
|     *   *  *****   ***     *     ***
|
|
|
|  Procedures for operating on rectangles.

| ASCII art:
| ****   *****   ***   *****   ***
| *   *  *      *   *    *    *   *
| *   *  *      *        *    *
| ****   ***    *        *     ***
| * *    *      *        *        *
| *  *   *      *   *    *    *   *
| *   *  *****   ***     *     ***
|
| Procedures for operating on rectangles.
|
| .PROC StdRect,2
| .REF CheckPic,PutPicVerb,PutPicRect
| .REF PutRect,FrRect,PushVerb,DrawRect
| ---------------------------------------------------------------
|
| PROCEDURE StdRect(verb: GrafVerb; r: Rect);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|   VERB +0xC byte (GrafVerb), RECT +0x8 long (addr-of-rect)
|
| Called during boot.
STDRECT:
    LINK	A6,#0x0                                | NO LOCALS
    MOVEM.L	D7/A3-A4,-(A7)                      | SAVE REGS
    MOVE.B	0xC(A6),D7                           | GET VERB
    JSR	CHECKPIC(PC)                            | SET UP A4,A3 AND CHECK PICSAVE
    BLE.B	STDRECT_NOTPIC                        | BRANCH IF NOT PICSAVE
    MOVE.B	D7,-(A7)                             | PUSH VERB
    JSR	PUTPICVERB(PC)                          | PUT ADDIONAL PARAMS TO THEPIC
    MOVEQ.L	#0x30,D0                            | GET RECTNOUN IN HI NIBBLE
    ADD.W	D7,D0                                 | PUT VERB IN LO NIBBLE
    MOVE.B	D0,-(A7)                             | PUSH OPCODE
    MOVE.L	0x8(A6),-(A7)                        | PUSH ADDR OF RECT
    JSR	PUTPICRECT(PC)                          | PUT OPCODE AND RECTANGLE
STDRECT_NOTPIC:
    MOVE.L	0x8(A6),-(A7)                        | PUSH RECT FOR FrRect or DrawRect
    TST.B	D7                                    | IS VERB FRAME ?
    BNE.B	STDRECT_NOTFR                         | NO, CONTINUE
    TST.L	0x60(A3)                              | YES, IS RGNSAVE TRUE ?
    BEQ.B	STDRECT_NOTRGN                        | NO, CONTINUE
    MOVE.L	0x8(A6),-(A7)                        | YES, PUSH ADDR OF RECT
    MOVE.L	-0x94(A4),-(A7)                      | PUSH RGNBUF
    PEA.L	-0x96(A4)                             | PUSH VAR RGNINDEX
    PEA.L	-0x98(A4)                             | PUSH VAR RGNMAX
    JSR	PUTRECT(PC)                             | ADD A RECT TO THERGN
STDRECT_NOTRGN:
    JSR	FRRECT(PC)                              | FrRect(rect)
    BRA.B	STDRECT_GOHOME                        | branch to exit
| ----------------------------------------------------------
|
| STDRECT_NOTFR
|
| Called during boot.
STDRECT_NOTFR:
    JSR	PUSHVERB(PC)                            | PUSH MODE AND PATTERN
    JSR	DRAWRECT(PC)                            | DrawRect(rect,mode,pat);
STDRECT_GOHOME:
    MOVEM.L	(A7)+,D7/A3-A4                      | GOHOME: RESTORE REGS
    UNLK	A6                                     | destroy stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDQ.W	#0x6,A7                              | pop 6 bytes of parameters
    JMP	(A0)                                    | tail-call return from STDRECT_GOHOME via A0
| .PROC PushVerb
| ----------------------------------------------------------
|
| PUSH A MODE AND A PATTERN, BASED ON VERB
| ENTER WITH VERB IN D7, GRAFGLOBALS IN A4, THEPORT IN A3.
|
| CLOBBERS A0.
|
| frame: pnMode, pnPat
| paint: pnMode, pnPat
| erase: patCopy, bkPat
| invert: patXor, black
| fill: patCopy, fillPat
|
| Called by: STDRECT_NOTFR, STDRRECT_DOIT, STDOVAL_DOIT, DOIT, STDPOLY_NOTFR (and 1 more)
PUSHVERB:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVE.W	#0x8,-(A7)                           | PUSH MODE = PATCOPY (IE. DEFAULT)
    CMPI.B	#0x1,D7                              | case on verb
    BLE.B	PUSHVERB_PAINT1                       | branch if frame or paint
    CMPI.B	#0x3,D7                              | check if invert
    BLT.B	PUSHVERB_ERASE1                       | branch if erase
    BEQ.B	PUSHVERB_ERASE1_CONT                  | branch if invert
    PEA.L	0x28(A3)                              | PUSH PAT := FILLPAT
    BRA.B	PUSHVERB_DONE                         | branch to exit
| ----------------------------------------------------------
|
| PUSHVERB_ERASE1
|
| Called during boot.
PUSHVERB_ERASE1:
    PEA.L	0x20(A3)                              | PUSH PAT = BKPAT
    BRA.B	PUSHVERB_DONE                         | branch to exit
| ----------------------------------------------------------
|
| PUSHVERB_ERASE1_CONT
|
| Called during boot.
PUSHVERB_ERASE1_CONT:
    ADDQ.W	#0x2,(A7)                            | adjust, push mode = patXor
    PEA.L	-0x10(A4)                             | PUSH PAT = BLACK
    BRA.B	PUSHVERB_DONE                         | branch to exit
| ----------------------------------------------------------
|
| PUSHVERB_PAINT1
|
| Called during boot.
PUSHVERB_PAINT1:
    MOVE.W	0x38(A3),(A7)                        | PAINT1: REPLACE, PUSH MODE = PNMODE
    PEA.L	0x3A(A3)                              | PUSH PAT = PNPAT
PUSHVERB_DONE:
    JMP	(A0)                                    | DONE: RETURN TO CALLER
| .PROC FillRect,2
| .DEF CallRect,FrameRect,PaintRect,EraseRect,InvertRect
| .REF StdRect
| ----------------------------------------------------------
|
| PROCEDURE FillRect(r: Rect; pat: Pattern);
|
| Called during boot.
FILLRECT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVEA.L	(A7)+,A1                            | POP ADDR OF PATTERN
    MOVE.L	A0,-(A7)                             | PUT RETURN ADDR BACK
    MOVEA.L	(A5),A0                             | point to QuickDraw globals
    MOVEA.L	(A0),A0                             | get current grafPort
    LEA.L	0x28(A0),A0                           | POINT TO FILLPAT
    MOVE.L	(A1)+,(A0)+                          | COPY PAT INTO FILLPAT
    MOVE.L	(A1)+,(A0)+                          | ALL EIGHT BYTES
    MOVEQ.L	#0x4,D0                             | verb = fill
    BRA.B	CALLRECT                              | SHARE COMMON CODE
| ----------------------------------------------------------
|
| PROCEDURE FrameRect(r: Rect);
|
FRAMERECT:
    MOVEQ.L	#0x0,D0                             | verb = frame
    BRA.B	CALLRECT                              | SHARE COMMON CODE
| ----------------------------------------------------------
|
| PROCEDURE PaintRect(r: Rect);
|
PAINTRECT:
    MOVEQ.L	#0x1,D0                             | verb = paint
    BRA.B	CALLRECT                              | SHARE COMMON CODE
| ----------------------------------------------------------
|
| PROCEDURE EraseRect(r: Rect);
|
ERASERECT:
    MOVEQ.L	#0x2,D0                             | verb = erase
    BRA.B	CALLRECT                              | SHARE COMMON CODE
| ----------------------------------------------------------
|
| PROCEDURE InvertRect(r: Rect);
|
INVERTRECT:
    MOVEQ.L	#0x3,D0                             | verb = invert
    NOP                                         | alignment padding
| ---------------------------------------------------------------
|
| CallRect: shared by FrameRect, PaintRect, EraseRect, InvertRect, FillRect.
| Pops return addr + rect addr, pushes verb byte + rect + return addr,
| dispatches via grafProcs.rectProc or _StdRect.
|
CALLRECT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVEA.L	(A7)+,A1                            | POP ADDR OF RECT
    MOVE.B	D0,-(A7)                             | PUSH VERB
    MOVE.L	A1,-(A7)                             | PUSH ADDR OF RECT
    MOVE.L	A0,-(A7)                             | PUT BACK RETURN ADDR
    MOVEA.L	(A5),A0                             | point to QuickDraw globals
    MOVEA.L	(A0),A0                             | get current grafPort
    MOVE.L	0x68(A0),D0                          | IS GRAFPROCS NIL ?
    MOVEA.L	(0x1080).W,A0                       | _StdRect (rectProc)
    BEQ.B	CALLRECT_USESTD                       | YES, USE STD PROC
    MOVEA.L	D0,A0                               | NO, GRAB GRAFPROCS PTR
    MOVEA.L	0x8(A0),A0                          | NO, GET PROC PTR
CALLRECT_USESTD:
    JMP	(A0)                                    | USESTD: GO TO IT
| .PROC DrawRect,3
| .REF RgnBlt
| ----------------------------------------------------------
|
| PROCEDURE DrawRect(rect: Rect; mode: INTEGER; pat: Pattern);
|
| Called by StdRect after PushVerb.
|
DRAWRECT:
    LINK	A6,#0x0                                | NO LOCALS
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A1                             | GET CURRENT GRAFPORT
    TST.W	0x42(A1)                              | IS PNVIS NEGATIVE ?
    BLT.B	DRAWRECT_EXIT                         | YES, QUIT
    PEA.L	0x2(A1)                               | PUSH SRCBITS = PORTBITS
    MOVE.L	(A7),-(A7)                           | PUSH DSTBITS
    MOVE.L	0xE(A6),-(A7)                        | PUSH SRCRECT
    MOVE.L	(A7),-(A7)                           | PUSH DSTRECT
    MOVE.W	0xC(A6),-(A7)                        | PUSH MODE
    MOVE.L	0x8(A6),-(A7)                        | PUSH PAT
    MOVE.L	0x1C(A1),-(A7)                       | PUSH CLIPRGN
    MOVE.L	0x18(A1),-(A7)                       | PUSH VISRGN
    MOVE.L	-0x82(A0),-(A7)                      | PUSH WIDEOPEN
    JSR	RGNBLT(PC)                              | CALL RgnBlt
DRAWRECT_EXIT:
    UNLK	A6                                     | destroy stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0xA,A7                              | pop 10 bytes of parameters
    JMP	(A0)                                    | tail-call return from DRAWRECT_EXIT via A0
| .PROC FrRect,1
| .REF RgnBlt
| ----------------------------------------------------------
|
| PROCEDURE FrRect(r: Rect);
| Draws an outline inside a rect.
|
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
|   DSTRECT +0x8 long, addr-of-rect
|   H1 -0x2, H2 -0x4, H3 -0x6, H4 -0xA (word, four pen-box H coords)
|   V1 -0xC, V2 -0xE, V3 -0x10, V4 -0x14 (word, four pen-box V coords)
|   TEMPRECT -0x1C..-0x15 rect (current edge being painted)
|
| Called during boot.
FRRECT:
    LINK	A6,#-0x1C                              | allocate local variables
    MOVEA.L	(A5),A0                             | point to QuickDraw globals
    MOVEA.L	(A0),A0                             | get current grafPort
    TST.W	0x42(A0)                              | IS PNVIS NEGATIVE ?
    BLT.W	FILLED_SKIP                           | YES, DON'T DRAW AT ALL
    MOVEA.L	0x8(A6),A1                          | POINT TO INPUT RECT
    MOVE.L	(A1)+,-0x1C(A6)                      | copy input rect
    MOVE.L	(A1)+,-0x18(A6)                      | copy input rect
|
| Now set up h1,h2,h3,h4 and v1,v2,v3,v4
|
    LEA.L	-0x1C(A6),A1                          | POINT TO COPIED RECT
    MOVE.W	0x36(A0),D2                          | GET PEN WIDTH
    MOVE.W	0x2(A1),D0                           | get left edge
    MOVE.W	D0,-0x2(A6)                          | H1:=LEFT
    ADD.W	D2,D0                                 | calculate H2
    MOVE.W	D0,-0x4(A6)                          | H2:=LEFT+PENWIDTH
    MOVE.W	0x6(A1),D1                           | get right edge
    MOVE.W	D1,-0xA(A6)                          | H4:=RIGHT
    SUB.W	D2,D1                                 | calculate H3
    MOVE.W	D1,-0x6(A6)                          | H3:=RIGHT-PENWIDTH
    CMP.W	D1,D0                                 | IS H2 >= H3 ?
    BGE.B	FRRECT_OK                             | YES, FILL IT IN SOLID
    MOVE.W	0x34(A0),D2                          | GET PEN HEIGHT
    MOVE.W	(A1),D0                              | get top edge
    MOVE.W	D0,-0xC(A6)                          | V1:=TOP
    ADD.W	D2,D0                                 | calculate V2
    MOVE.W	D0,-0xE(A6)                          | V2:=TOP+PENHEIGHT
    MOVE.W	0x4(A1),D1                           | get bottom edge
    MOVE.W	D1,-0x14(A6)                         | V4:=BOTTOM
    SUB.W	D2,D1                                 | calculate V3
    MOVE.W	D1,-0x10(A6)                         | V3:=BOTTOM-PENHEIGHT
    CMP.W	D1,D0                                 | IS V2 >= V3 ?
    BGE.B	FRRECT_OK                             | YES, FILL IT IN SOLID
    MOVE.W	-0x2(A6),-0x1A(A6)                   | setup tempRect left = H1
    MOVE.W	-0x6(A6),-0x16(A6)                   | setup tempRect right = H3
    MOVE.W	-0xC(A6),-0x1C(A6)                   | setup tempRect top = V1
    MOVE.W	-0xE(A6),-0x18(A6)                   | setup tempRect bottom = V2
|
| PEN IS NOT SO BIG AS TO FILL IN SOLID. BREAK RECT INTO 4 EDGES.
|
    BSR.B	DORECT                                | PAINT TOP EDGE
    MOVE.W	-0x6(A6),-0x1A(A6)                   | setup tempRect left = H3
    MOVE.W	-0xA(A6),-0x16(A6)                   | setup tempRect right = H4
    MOVE.W	-0x10(A6),-0x18(A6)                  | setup tempRect bottom = V3
    BSR.B	DORECT                                | PAINT RIGHT EDGE
    MOVE.W	-0x4(A6),-0x1A(A6)                   | setup tempRect left = H2
    MOVE.W	-0x10(A6),-0x1C(A6)                  | setup tempRect top = V3
    MOVE.W	-0x14(A6),-0x18(A6)                  | setup tempRect bottom = V4
    BSR.B	DORECT                                | PAINT BOTTOM EDGE
    MOVE.W	-0x2(A6),-0x1A(A6)                   | setup tempRect left = H1
    MOVE.W	-0x4(A6),-0x16(A6)                   | setup tempRect right = H2
    MOVE.W	-0xE(A6),-0x1C(A6)                   | setup tempRect top = V2
FRRECT_OK:
    BRA.B	FILLED                                | PAINT LEFT EDGE
| ----------------------------------------------------------
|
| DORECT - LOCAL ROUTINE TO PAINT TEMPRECT, GIVEN IN LOCAL COORDS
|
| Called during boot.
DORECT:
    MOVEA.L	(A5),A0                             | point to QuickDraw globals
    MOVEA.L	(A0),A1                             | GET CURRENT GRAFPORT
    PEA.L	0x2(A1)                               | PUSH SRCBITS = DSTBITS
    MOVE.L	(A7),-(A7)                           | PUSH DSTBITS
    PEA.L	-0x1C(A6)                             | PUSH SRCRECT = DSTRECT
    MOVE.L	(A7),-(A7)                           | PUSH DSTRECT, LOCAL COORDS
    MOVE.W	0x38(A1),-(A7)                       | PUSH PEN MODE
    PEA.L	0x3A(A1)                              | PUSH ADDR OF PEN PATTERN
    MOVE.L	0x1C(A1),-(A7)                       | PUSH CLIPRGN
    MOVE.L	0x18(A1),-(A7)                       | PUSH VISRGN
    MOVE.L	-0x82(A0),-(A7)                      | PUSH WIDE OPEN
    JSR	RGNBLT(PC)                              | CALL RGNBLT
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| FILLED
|
| Called during boot.
FILLED:
    BSR.B	DORECT                                | FILL TEMPRECT SOLID
FILLED_SKIP:
    UNLK	A6                                     | destroy stack frame
    MOVE.L	(A7)+,(A7)                           | strip param and replace ret addr
    RTS                                         | AND RETURN
| .PROC SetRect
| ----------------------------------------------------------
|
| PROCEDURE SetRect(VAR r: Rect; left,top,right,bottom: INTEGER);
| { assign 4 integers into a rectangle }
|
| Called during boot.
SETRECT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVE.L	(A7)+,D1                             | POP BOTRIGHT POINT
    MOVE.L	(A7)+,D0                             | POP TOPLEFT POINT
    MOVEA.L	(A7)+,A1                            | POP ADDR OF RECT
    MOVE.L	D0,(A1)+                             | INSTALL TOPLEFT
    MOVE.L	D1,(A1)+                             | INSTALL BOTRIGHT
    JMP	(A0)                                    | RETURN
| .PROC EqualRect
| ----------------------------------------------------------
|
| FUNCTION EqualRect(rect1,rect2: Rect): BOOLEAN;
| { return TRUE if rect1 = rect2 }
|
EQUALRECT:
    MOVE.L	(A7)+,D0                             | POP RETURN ADDR (low long)
    MOVEA.L	(A7)+,A1                            | POP RECT2 ADDR
    MOVEA.L	(A7)+,A0                            | POP RECT1 ADDR
    CMPM.L	(A0)+,(A1)+                          | COMPARE FIRST LONG
    BNE.B	FALSE                                 | NO MATCH, RETURN FALSE
    CMPM.L	(A0)+,(A1)+                          | COMPARE SECOND LONG
    BNE.B	FALSE                                 | NO MATCH, RETURN FALSE
    MOVE.B	#0x1,(A7)                            | TRUE
    BRA.B	EQUALRECT_DONE                        | BRANCH TO EXIT
| ----------------------------------------------------------
|
| FALSE
|
FALSE:
    CLR.B	(A7)                                  | FALSE
EQUALRECT_DONE:
    MOVE.L	D0,-(A7)                             | put back return addr
    RTS                                         | RETURN
| .PROC EmptyRect
| ----------------------------------------------------------
|
| FUNCTION EmptyRect(r: Rect): BOOLEAN;
|
| CLOBBERS D0,D1,A0,A1.
|
| Called during boot (7,391 times in 30s trace).
EMPTYRECT:
    MOVEA.L	(A7)+,A1                            | POP RETURN ADDR
    MOVEA.L	(A7)+,A0                            | POP ADDR OF RECT
    MOVE.W	(A0)+,D0                             | GET TOP
    MOVE.W	(A0)+,D1                             | GET LEFT
    CMP.W	(A0)+,D0                              | IS TOP >= BOTTOM ?
    BGE.B	EMPTYRECT_EMPTY                       | YES, RETURN TRUE
    CMP.W	(A0)+,D1                              | IS LEFT >= RIGHT ?
    BGE.B	EMPTYRECT_EMPTY                       | YES, RETURN TRUE
    CLR.B	(A7)                                  | NOT EMPTY, RETURN FALSE
    BRA.B	EMPTYRECT_DONE                        | AND QUIT
| ----------------------------------------------------------
|
| EMPTYRECT_EMPTY
|
| Called during boot (7,383 times in 30s trace).
EMPTYRECT_EMPTY:
    MOVE.B	#0x1,(A7)                            | EMPTY: RETURN TRUE
EMPTYRECT_DONE:
    JMP	(A1)                                    | DONE: RETURN
| .PROC OffsetRect
| ----------------------------------------------------------
|
| PROCEDURE OffsetRect(VAR r: Rect; dh,dv: INTEGER);
|
| Called during boot.
OFFSETRECT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVE.W	(A7)+,D1                             | POP DV
    MOVE.W	(A7)+,D0                             | POP DH
    MOVEA.L	(A7)+,A1                            | POP ADDR OF RECT
    ADD.W	D1,(A1)+                              | TOP:=TOP+DV
    ADD.W	D0,(A1)+                              | LEFT:=LEFT+DH
    ADD.W	D1,(A1)+                              | BOTTOM:=BOTTOM+DV
    ADD.W	D0,(A1)+                              | RIGHT:=RIGHT+DH
    JMP	(A0)                                    | RETURN
| .PROC InsetRect
| ----------------------------------------------------------
|
| PROCEDURE InsetRect(VAR r: Rect; dh,dv: INTEGER);
| { inset a rectangle on all 4 sides }
|
| Called during boot.
INSETRECT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDR
    MOVE.W	(A7)+,D1                             | POP DV
    MOVE.W	(A7)+,D0                             | POP DH
    MOVEA.L	(A7)+,A1                            | POP ADDR OF RECT
    ADD.W	D1,(A1)+                              | ADD DV TO TOP
    ADD.W	D0,(A1)+                              | ADD DH TO LEFT
    SUB.W	D1,(A1)+                              | SUBTRACT DV FROM BOTTOM
    SUB.W	D0,(A1)+                              | SUBTRACT DH FROM RIGHT
    JMP	(A0)                                    | DONE: RETURN
| .FUNC SectRect,3
| .DEF RSect
| ---------------------------------------------------------
|
| FUNCTION SectRect(srcA,srcB: Rect; VAR dstC: Rect): BOOLEAN;
|
| Returns TRUE and intersection in dst,
| else FALSE and dst = 0,0,0,0.
| Dst may also be used as one of the inputs
|
| Called during boot.
SECTRECT:
    LINK	A6,#0x0                                | NO LOCAL VARS
    MOVE.L	0x10(A6),-(A7)                       | PUSH SRCA POINTER
    MOVE.L	0xC(A6),-(A7)                        | PUSH SRCB POINTER
    MOVE.W	#0x2,-(A7)                           | PUSH NRECTS=2
    MOVE.L	0x8(A6),-(A7)                        | PUSH DST POINTER
    BSR.B	RSECT                                 | CALC INTERSECTION
    SNE.B	0x14(A6)                              | STORE BOOLEAN RESULT
    NEG.B	0x14(A6)                              | CONVERT $FF TO $01
    UNLK	A6                                     | destroy stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0xC,A7                              | pop 12 bytes of parameters
    JMP	(A0)                                    | tail-call return from SECTRECT via A0
| ---------------------------------------------------
|
| ASSEMBLY CALLABLE ROUTINE TO COMPUTE THE INTERSECTION OF
| ANY NUMBER OF RECTANGLES.
|
| INPUTS: PUSH ADDRESSES OF EACH INPUT RECTANGLE (LONGS)
|         PUSH # OF RECTANGLES (WORD)
|         PUSH ADDRESS OF OUTPUT RECTANGLE (LONG)
|
| MPP_OPENSOCKET DST=(0,0,0,0) AND Z-FLAG SET IF NO INTERSECTION
|
| CLOBBERS: D0,A0
|
| Called by: NOSTRCH, VOK2_NO, SECTRECT, RGNBLT, NOCOLOR (and 5 more)
| Called during boot (10,843 times in 30s trace).
RSECT:
    LINK	A6,#0x0                                | no local vars
    MOVEM.L	D1-D4/A1,-(A7)                      | SAVE REGS
    LEA.L	0xC(A6),A1                            | POINT TO NRECTS
    MOVE.W	(A1)+,D0                             | GET NRECTS COUNT
    BLE.B	SECTRECT_EMPTY                        | EMPTY IF NRECTS <= 0
    MOVEA.L	(A1)+,A0                            | POINT TO FIRST RECT
    MOVEM.W	(A0)+,D1-D4                         | GET TOP, LEFT, BOT, RIGHT
    SUBQ.W	#0x1,D0                              | DECREMENT RECT COUNT
    BRA.B	RTOK                                  | CHECK THIS RECT AND LOOP
| ----------------------------------------------------------
|
| NEXTRECT
|
| Called during boot (12,436 times in 30s trace).
NEXTRECT:
    MOVEA.L	(A1)+,A0                            | POINT TO NEXT RECT
    CMP.W	(A0)+,D1                              | IS TOP < NEXT TOP ?
    BGE.B	SECTRECT_TOPOK                        | NO, CONTINUE
    MOVE.W	-0x2(A0),D1                          | YES, TOP:=NEXT TOP
SECTRECT_TOPOK:
    CMP.W	(A0)+,D2                              | TOPOK: IS LEFT < NEXT LEFT ?
    BGE.B	SECTRECT_LEFTOK                       | NO, CONTINUE
    MOVE.W	-0x2(A0),D2                          | YES, LEFT:=NEXT LEFT
SECTRECT_LEFTOK:
    CMP.W	(A0)+,D3                              | LEFTOK: IS BOTTOM > NEXT BOT ?
    BLE.B	SECTRECT_BOTOK                        | NO, CONTINUE
    MOVE.W	-0x2(A0),D3                          | YES, BOTTOM:=NEXT BOT
SECTRECT_BOTOK:
    CMP.W	(A0)+,D4                              | BOTOK: IS RIGHT > NEXT RIGHT ?
    BLE.B	RTOK                                  | NO, CONTINUE
    MOVE.W	-0x2(A0),D4                          | YES, RIGHT:=NEXT RIGHT
RTOK:
    CMP.W	D1,D3                                 | IS BOTTOM <= TOP ?
    BLE.B	SECTRECT_EMPTY                        | YES, EMPTY
    CMP.W	D2,D4                                 | IS RIGHT <= LEFT ?
    BLE.B	SECTRECT_EMPTY                        | YES, EMPTY
    DBF.W	D0,NEXTRECT                           | LOOP FOR ALL RECTANGLES
    BRA.B	SECTRECT_DONE                         | DONE
| ----------------------------------------------------------
|
| SECTRECT_EMPTY
|
| Called during boot.
SECTRECT_EMPTY:
    CLR.W	D1                                    | ALL EMPTY RECTS ARE (0,0,0,0)
    CLR.W	D2                                    | ALL EMPTY RECTS ARE (0,0,0,0)
    CLR.W	D3                                    | ALL EMPTY RECTS ARE (0,0,0,0)
    CLR.W	D4                                    | ALL EMPTY RECTS ARE (0,0,0,0)
SECTRECT_DONE:
    MOVEA.L	0x8(A6),A0                          | POINT TO DST RECT
    MOVE.W	D1,(A0)+                             | INSTALL TOP
    MOVE.W	D2,(A0)+                             | INSTALL LEFT
    MOVE.W	D3,(A0)+                             | INSTALL BOTTOM
    MOVE.W	D4,(A0)+                             | INSTALL RIGHT
    MOVE.W	0xC(A6),D0                           | GET NRECTS COUNT
    LSL.W	#0x2,D0                               | times 4 for byte count of pointers
    ADDQ.W	#0x6,D0                              | + 4 (output) + 2 (NRECTS) bytes
    CMP.W	D1,D3                                 | set Z if dst empty
    MOVEM.L	(A7)+,D1-D4/A1                      | RESTORE REGS
    UNLK	A6                                     | destroy stack frame
    MOVEA.L	(A7)+,A0                            | pop return addr
    ADDA.W	D0,A7                                | strip varargs (NRECTS pointers + result)
    JMP	(A0)                                    | tail-call back
| .PROC UnionRect,3
| .DEF Pt2Rect
| ----------------------------------------------------------
|
| PROCEDURE UnionRect(* src1,src2: Rect; VAR dst: Rect *);
|
| { compute smallest rectangle containing both input rectangles }
| { works correctly even if one of the sources is the destination }
|
| Called during boot.
UNIONRECT:
    MOVEA.L	0xC(A7),A0                          | GET ADDR OF SRC1
    MOVEA.L	0x8(A7),A1                          | GET ADDR OF SRC2
    MOVE.W	(A0)+,D0                             | TOP:=TOP1
    CMP.W	(A1)+,D0                              | IS TOP2 < TOP ?
    BLE.B	UNIONRECT_TOPOK                       | NO, CONTINUE
    MOVE.W	-0x2(A1),D0                          | YES, TOP:=TOP2
UNIONRECT_TOPOK:
    SWAP.W	D0                                   | TOPOK: PUT TOP IN HI WORD
    MOVE.W	(A0)+,D0                             | LEFT:=LEFT1
    CMP.W	(A1)+,D0                              | IS LEFT2 < LEFT ?
    BLE.B	UNIONRECT_LEFTOK                      | NO, CONTINUE
    MOVE.W	-0x2(A1),D0                          | YES, LEFT:=LEFT2
UNIONRECT_LEFTOK:
    MOVE.W	(A0)+,D1                             | LEFTOK: BOTTOM:=BOTTOM1
    CMP.W	(A1)+,D1                              | IS BOTTOM2 > BOTTOM ?
    BGE.B	UNIONRECT_BOTOK                       | NO, CONTINUE
    MOVE.W	-0x2(A1),D1                          | YES, BOTTOM:=BOTTOM2
UNIONRECT_BOTOK:
    SWAP.W	D1                                   | BOTOK: PUT BOTTOM IN HI WORD
    MOVE.W	(A0)+,D1                             | RIGHT:=RIGHT1
    CMP.W	(A1)+,D1                              | IS RIGHT2 > RIGHT1 ?
    BGE.B	UNIONRECT_RIGHTOK                     | NO, CONTINUE
    MOVE.W	-0x2(A1),D1                          | YES, RIGHT:=RIGHT2
UNIONRECT_RIGHTOK:
    MOVEA.L	0x4(A7),A0                          | POINT TO DST RECT
    MOVE.L	D0,(A0)+                             | INSTALL TOPLEFT
    MOVE.L	D1,(A0)+                             | INSTALL BOTRIGHT
    BRA.B	PT2RECT_SHARE                         | STRIP 3 PARAMETERS AND RETURN
| ----------------------------------------------------------
|
| PROCEDURE Pt2Rect(* pt1,pt2: Point; VAR dst: Rect *);
|
| { make a rectangle from two points }
|
| Called during boot.
PT2RECT:
    MOVEA.L	0x4(A7),A0                          | POINT TO DST RECT
    MOVE.W	0xE(A7),D0                           | GET H1
    MOVE.W	0xA(A7),D1                           | GET H2
    CMP.W	D0,D1                                 | IS H2 < H1 ?
    BGE.B	HOK                                   | NO, CONTINUE
    EXG	D0,D1                                   | YES, SWAP THEM
HOK:
    MOVE.W	D0,0x2(A0)                           | INSTALL DST LEFT = MIN(H1,H2)
    MOVE.W	D1,0x6(A0)                           | INSTALL DST RIGHT = MAX(H1,H2)
    MOVE.W	0xC(A7),D0                           | GET V1
    MOVE.W	0x8(A7),D1                           | GET V2
    CMP.W	D0,D1                                 | IS V2 < V1 ?
    BGE.B	HOK_NO                                | NO, CONTINUE
    EXG	D0,D1                                   | YES, SWAP THEM
HOK_NO:
    MOVE.W	D0,(A0)                              | INSTALL DST TOP = MIN(V1,V2)
    MOVE.W	D1,0x4(A0)                           | INSTALL DST BOTTOM = MAX(V1,V2)
PT2RECT_SHARE:
    MOVEA.L	(A7)+,A0                            | SHARE: POP RETURN ADDR
    ADDA.W	#0xC,A7                              | STRIP 3 PARAMETERS
    JMP	(A0)                                    | AND RETURN
| .PROC PtInRect
| ------------------------------------------------------------
|
| FUNCTION PtInRect(pt: Point; r: Rect): BOOLEAN;
|
| Returns TRUE if point is within the rectangle.
|
| Called during boot (43,763 times in 30s trace).
PTINRECT:
    LINK	A6,#0x0                                | NO LOCAL VARS
    MOVEA.L	0x8(A6),A0                          | POINT TO DST RECT
    MOVE.W	0xE(A6),D0                           | GET DH or PT.H
    MOVE.W	0xC(A6),D1                           | GET DV or PT.V
    CLR.B	0x10(A6)                              | INIT BOOLEAN TO FALSE
    CMP.W	(A0)+,D1                              | IS PT.V < TOP ?
    BLT.B	PTINRECT_EXIT                         | YES, QUIT
    CMP.W	(A0)+,D0                              | IS PT.H < LEFT ?
    BLT.B	PTINRECT_EXIT                         | YES, QUIT
    CMP.W	(A0)+,D1                              | IS PT.V >= BOTTOM ?
    BGE.B	PTINRECT_EXIT                         | YES, QUIT
    CMP.W	(A0)+,D0                              | IS PT.H >= RIGHT ?
    BGE.B	PTINRECT_EXIT                         | YES, QUIT
    ADDQ.B	#0x1,0x10(A6)                        | RETURN BOOLEAN TRUE
PTINRECT_EXIT:
    UNLK	A6                                     | destroy stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDQ.W	#0x8,A7                              | pop parameters
    JMP	(A0)                                    | tail-call return from PTINRECT_EXIT via A0
| .PROC PutRect,4
| .REF SetSize
| ----------------------------------------------------------------
|
| PROCEDURE PutRect(r: Rect; bufHandle: Handle; VAR index,size: INTEGER);
|
| Puts the four inversion points of a rectangle.
|
| Clobbers D0,A0,A1
|
PUTRECT:
    LINK	A6,#0x0                                | NO LOCAL VARIABLES
| ------------------------------------------------------------
|
| IS THERE ROOM FOR FOUR NEW POINTS IN THE POINT BUFFER ?
|
    MOVEA.L	0xC(A6),A0                          | POINT TO INDEX
    MOVEA.L	0x8(A6),A1                          | POINT TO SIZE
    MOVEQ.L	#0x10,D0                            | 16 bytes for 4 points
    ADD.W	(A0),D0                               | GET CURRENT INDEX + 16
    CMP.W	(A1),D0                               | IS NEW INDEX > SIZE ?
    BLE.B	PUTRECT_SIZEOK                        | NO, CONTINUE
    ADDI.W	#0x400,(A1)                          | ADD 1024 TO SIZE
| -------------------------------------------------------------
|
| NO, GROW THE POINT BUFFER ENOUGH FOR 256 MORE POINTS
|
    MOVEM.L	D3/A2,-(A7)                         | SAVE REGS
    MOVE.L	0x10(A6),-(A7)                       | PUSH HANDLE PARAM
    MOVE.W	(A1),-(A7)                           | PUSH NEW SIZE
    JSR	SETHSIZE(PC)                            | MAKE THE BUFFER BIGGER
    MOVEM.L	(A7)+,D3/A2                         | RESTORE REGS
    MOVEA.L	0xC(A6),A0                          | POINT TO INDEX AGAIN
| ------------------------------------------------------------
|
| NOW INSTALL THE 4 NEW INVERSION POINTS
|
PUTRECT_SIZEOK:
    MOVEA.L	0x10(A6),A1                         | POINT TO HANDLE
    MOVEA.L	(A1),A1                             | DE-REFERENCE HANDLE
    ADDA.W	(A0),A1                              | ADD INDEX TO BUFPTR
    ADDI.W	#0x10,(A0)                           | BUMP INDEX BY 16
    MOVEA.L	0x14(A6),A0                         | POINT TO RECT
    MOVE.L	(A0),(A1)+                           | PUT (TOP,LEFT)
    MOVE.W	(A0),(A1)+                           | PUT TOP AGAIN
    MOVE.W	0x6(A0),(A1)+                        | PUT RIGHT
    MOVE.W	0x4(A0),(A1)+                        | PUT BOTTOM
    MOVE.W	0x2(A0),(A1)+                        | PUT LEFT
    MOVE.L	0x4(A0),(A1)+                        | PUT (BOTTOM,RIGHT)
    UNLK	A6                                     | destroy stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x10,A7                             | pop 16 bytes of parameters
    JMP	(A0)                                    | tail-call return from PUTRECT_SIZEOK via A0
