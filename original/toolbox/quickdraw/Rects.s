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
|

| .PROC StdRect,2
| .REF CheckPic,PutPicVerb,PutPicRect
| .REF PutRect,FrRect,PushVerb,DrawRect
| ---------------------------------------------------------------
| PROCEDURE StdRect(verb: GrafVerb; r: Rect);
| A6 OFFSETS OF PARAMS AFTER LINK:
| Called during boot.
StdRect:
        LINK    A6,#0x0                         | set up frame (no locals)
        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.B  12(A6),D7                       | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.W   STDRECT_NOTPIC                  | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVEQ.L #0x30,D0                        | rectNoun in hi nibble (opcode $3X)
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | PUSH OPCODE
        MOVE.L  8(A6),-(SP)                     | PUSH ADDR OF RECT
        JSR     PutPicRect(PC)                  | PUT OPCODE AND RECTANGLE
STDRECT_NOTPIC:
        MOVE.L  8(A6),-(SP)                     | PUSH RECT FOR FrRect or DrawRect
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDRECT_NOTFR                   | NO, CONTINUE
        TST.L   0x60(A3)                        | YES, IS RGNSAVE TRUE ?
        BEQ.B   STDRECT_NOTRGN                  | NO, CONTINUE
        MOVE.L  8(A6),-(SP)                     | YES, PUSH ADDR OF RECT
        MOVE.L  -0x94(A4),-(SP)                 | PUSH RGNBUF
        PEA.L     -0x96(A4)                     | PUSH VAR RGNINDEX
        PEA.L     -0x98(A4)                     | PUSH VAR RGNMAX
        JSR     PutRect(PC)                     | ADD A RECT TO THERGN
STDRECT_NOTRGN:
        JSR     FrRect(PC)                      | FrRect(rect)
        BRA.B   STDRECT_GOHOME                  | -> exit
STDRECT_NOTFR:
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        JSR     DrawRect(PC)                    | DrawRect(rect,mode,pat);
STDRECT_GOHOME:
        MOVEM.L (SP)+,D7/A3-A4                  | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | pop 6 bytes of params
        JMP     (A0)                            | RTS
| Called by: STDRECT_NOTFR, STDRRECT_DOIT, STDOVAL_DOIT, DOIT, STDPOLY_NOTFR (and 1 more)
PushVerb:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        CMPI.B  #0x1,D7                         | verb <= 1 (frame/paint)?
        BLE.B   PUSHVERB_PAINT1                 | yes -> use pnMode/pnPat
        CMPI.B  #0x3,D7                         | verb < 3 (erase)?
        BLT.B   PUSHVERB_ERASE1                 | yes -> erase: patCopy + bkPat
        BEQ.B   PUSHVERB_ERASE1_CONT            | verb == 3 -> invert: patXor + black
        MOVE    #0x8,-(SP)                      | push mode = patCopy (fill)
        PEA.L     0x28(A3)                      | push pat = fillPat
        BRA.B   PUSHVERB_DONE                   | -> exit
PUSHVERB_ERASE1:
        MOVE    #0x8,-(SP)                      | push mode = patCopy (erase)
        PEA.L     0x20(A3)                      | push pat = bkPat
        BRA.B   PUSHVERB_DONE                   | -> exit
PUSHVERB_ERASE1_CONT:
        MOVE    #0xA,-(SP)                      | push mode = patXor (invert)
        PEA.L     -16(A4)                       | push pat = black (in QD globals)
        BRA.B   PUSHVERB_DONE                   | -> exit
PUSHVERB_PAINT1:
        MOVE    0x38(A3),-(SP)                  | push mode = pnMode
        PEA.L     0x3A(A3)                      | push pat = pnPat
PUSHVERB_DONE:
        JMP     (A0)                            | RTS

| ---------------------------------------------------------------
| PROCEDURE CallRect(r: Rect);
| code shared by FrameRect, PaintRect, EraseRect, InverRect, and FillRect.
| enter with verb in D0.
| Called during boot.
CallRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | A0 = QuickDraw globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  0x68(A0),D0                     | D0 = grafProcs handle (0 if std)
        LEA     StdRect(PC),A0                  | A0 = StdRect (default)
        BEQ.B   CALLRECT_CONT                   | YES, USE STD PROC
        MOVE.L  D0,A0                           | A0 = grafProcs ptr
        MOVE.L  8(A0),A0                        | NO, GET PROC PTR
CALLRECT_CONT:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE FrameRect(r: Rect).
FrameRect:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallRect(PC)                    | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE PaintRect(r: Rect).
PaintRect:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallRect(PC)                    | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE EraseRect(r: Rect).
EraseRect:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallRect(PC)                    | SHARE COMMON CODE

| ----------------------------------------------------------
|
| _InverRect ($A8A4): invert the pixels inside a rectangle
| Pascal: PROCEDURE InvertRect(r: Rect);
| CallRect with verb invert (3): calls the port's rectProc (StdRect if
| grafProcs is nil).
| Apple source name: InvertRect (1983 Rects.a; MacSEROM.lst: INVERTRECT)
|
InverRect:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallRect(PC)                    | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE FillRect(r: Rect; pat: Pattern);
FillRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A0                         | get current grafPort
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | verb = fill
        JMP     CallRect(PC)                    | share common rect dispatcher

| .PROC DrawRect,3
| .REF RgnBlt
| ----------------------------------------------------------
| PROCEDURE DrawRect(r: Rect; mode: INTEGER; pat: Pattern);
| Rectangle is given in local coordinates.
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
| PARAMSIZE .EQU 10 ;TOTAL BYTES OF PARAMS
| DSTRECT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF RECT
| MODE .EQU DSTRECT-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PAT
| Called during boot.
DrawRect:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A1                         | GET CURRENT GRAFPORT
        TST     0x42(A1)                        | IS PNVIS >= 0 ?
        BLT.B   DRAWRECT_EXIT_2                 | NO, QUIT
        PEA.L     2(A1)                         | PUSH SRCBITS = DSTBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        MOVE.L  14(A6),-(SP)                    | PUSH SRCRECT = DSTRECT
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    12(A6),-(SP)                    | PUSH MODE
        MOVE.L  8(A6),-(SP)                     | PUSH ADDR OF PATTERN
        MOVE.L  28(A1),-(SP)                    | PUSH CLIPRGN
        MOVE.L  24(A1),-(SP)                    | PUSH VISRGN
        MOVE.L  -0x82(A0),-(SP)                 | PUSH WIDE OPEN
        JSR     RgnBlt(PC)                      | CALL RGNBLT
DRAWRECT_EXIT_2:
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xA,SP                         | pop 10 bytes of params
        JMP     (A0)                            | RTS

| .PROC FrRect,1
| .REF RgnBlt
| ----------------------------------------------------------
| PROCEDURE FrRect(r: Rect);
| Draws an outline inside a rect.
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
| DSTRECT .EQU 8 ;LONG, ADDR OF RECT
| H1 .EQU -2 ;WORD
| H2 .EQU H1-2 ;WORD
| H3 .EQU H2-2 ;WORD
| H4 .EQU H3-4 ;WORD
| V1 .EQU H4-2 ;WORD
| V2 .EQU V1-2 ;WORD
| V3 .EQU V2-2 ;WORD
| V4 .EQU V3-4 ;WORD
| TEMPRECT .EQU V4-8 ;RECT
| VARSIZE .EQU TEMPRECT ;TOTAL SIZE OF LOCALS
| Called during boot.
FrRect:
        LINK    A6,#-0x1C                       | allocate local variables
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A0                         | get current grafPort
        TST     0x42(A0)                        | IS PNVIS NEGATIVE ?
        BLT.W   DORECT_SKIP                     | YES, DON'T DRAW AT ALL
        MOVE.L  8(A6),A1                        | POINT TO INPUT RECT
        MOVE.L  (A1)+,-28(A6)                   | copy input rect
        MOVE.L  (A1)+,-24(A6)                   | copy input rect
        LEA.L     -28(A6),A1                    | POINT TO COPIED RECT
        MOVE    0x36(A0),D2                     | GET PEN WIDTH
        MOVE    2(A1),D0                        | get left edge
        MOVE    D0,-2(A6)                       | H1:=LEFT
        ADD     D2,D0                           | calculate H2
        MOVE    D0,-4(A6)                       | H2:=LEFT+PENWIDTH
        MOVE    6(A1),D1                        | get right edge
        MOVE    D1,-10(A6)                      | H4:=RIGHT
        SUB     D2,D1                           | calculate H3
        MOVE    D1,-6(A6)                       | H3:=RIGHT-PENWIDTH
        CMP     D1,D0                           | IS H2 >= H3 ?
        BGE.W   DORECT_CONT                     | yes -> H2..H3 collapses, fill solid
        MOVE    0x34(A0),D2                     | D2 = pen height
        MOVE    (A1),D0                         | D0 = top edge
        MOVE    D0,-12(A6)                      | V1 = top
        ADD     D2,D0                           | calculate V2
        MOVE    D0,-14(A6)                      | V2 = top + penHt
        MOVE    4(A1),D1                        | D1 = bottom edge
        MOVE    D1,-20(A6)                      | V4 = bottom
        SUB     D2,D1                           | calculate V3
        MOVE    D1,-16(A6)                      | V3 = bottom - penHt
        CMP     D1,D0                           | IS V2 >= V3 ?
        BGE.W   DORECT_CONT                     | yes -> rect too small, fill solid
        MOVE    -2(A6),-26(A6)                  | jump via A0
        MOVE    -6(A6),-22(A6)                  | tempRect.right = H3 (top edge)
        MOVE    -12(A6),-28(A6)                 | tempRect.top = V1 (top edge)
        MOVE    -14(A6),-24(A6)                 | tempRect.bot = V2 (top edge)
        BSR.B   DORECT                          | paint top edge
        MOVE    -6(A6),-26(A6)                  | tempRect.left = H3 (right edge)
        MOVE    -10(A6),-22(A6)                 | tempRect.right = H4 (right edge)
        MOVE    -16(A6),-24(A6)                 | tempRect.bot = V3 (right edge)
        BSR.B   DORECT                          | PAINT TOP EDGE
        MOVE    -4(A6),-26(A6)                  | tempRect.left = H2 (bottom edge)
        MOVE    -16(A6),-28(A6)                 | tempRect.top = V3 (bottom edge)
        MOVE    -20(A6),-24(A6)                 | tempRect.bot = V4 (bottom edge)
        BSR.B   DORECT                          | PAINT RIGHT EDGE
        MOVE    -2(A6),-26(A6)                  | tempRect.left = H1 (left edge)
        MOVE    -4(A6),-22(A6)                  | tempRect.right = H2 (left edge)
        MOVE    -14(A6),-28(A6)                 | tempRect.top = V2 (left edge)
        BSR.B   DORECT                          | PAINT BOTTOM EDGE
        BRA.B   DORECT_SKIP                     | -> exit

| ----------------------------------------------------------
| DORECT
| Called during boot.
DORECT:
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A1                         | GET CURRENT GRAFPORT
        PEA.L     2(A1)                         | PUSH SRCBITS = DSTBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L     -28(A6)                       | PUSH SRCRECT = DSTRECT
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT, LOCAL COORDS
        MOVE    0x38(A1),-(SP)                  | PUSH PEN MODE
        PEA.L     0x3A(A1)                      | PUSH ADDR OF PEN PATTERN
        MOVE.L  28(A1),-(SP)                    | PUSH CLIPRGN
        MOVE.L  24(A1),-(SP)                    | PUSH VISRGN
        MOVE.L  -0x82(A0),-(SP)                 | PUSH WIDE OPEN
        JSR     RgnBlt(PC)                      | CALL RGNBLT
        RTS                                     | return from DORECT
DORECT_CONT:
        BSR.B   DORECT                          | FILL TEMPRECT SOLID
DORECT_SKIP:
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | strip 4 bytes (rect param), keep ret
        RTS                                     | return from FrRect

| .PROC SetRect
| ----------------------------------------------------------
| PROCEDURE SetRect(VAR r: Rect; left,top,right,bottom: INTEGER);
| { assign 4 integers into a rectangle }
| Called during boot.
SetRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | POP BOTRIGHT POINT
        MOVE.L  (SP)+,D0                        | POP TOPLEFT POINT
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.L  D0,(A1)+                        | INSTALL TOPLEFT
        MOVE.L  D1,(A1)+                        | INSTALL BOTRIGHT
        JMP     (A0)                            | RETURN
| ----------------------------------------------------------
|
| _EqualRect ($A8A6): compare two rectangles
| Pascal: FUNCTION EqualRect(rect1, rect2: Rect): BOOLEAN;
| TRUE if topLeft and botRight are both identical. CLOBBERS D0,A0,A1.
|
EqualRect:
        MOVE.L  (SP)+,D0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT2
        MOVE.L  (SP)+,A0                        | POP ADDR OF RECT1
        CMPM.L  (A0)+,(A1)+                     | IS TOPLEFT SAME ?
        BNE.B   SETRECT_EXIT                    | NO, RETURN FALSE
        CMPM.L  (A0)+,(A1)+                     | YES, IS BOTRIGHT SAME TOO ?
        BNE.B   SETRECT_EXIT                    | NO, RETURN FALSE
        MOVE.B  #0x1,(SP)                       | YES, RETURN TRUE
        BRA.B   EQUALRECT_EXIT                  | AND QUIT (skip CLR.B of result)
SETRECT_EXIT:
        CLR.B    (SP)                           | RETURN FALSE
EQUALRECT_EXIT:                                 | DONE
        MOVE.L   D0,-(SP)                       | PUSH RETURN ADDR
        RTS                                     | AND RETURN

| .PROC EmptyRect
| ----------------------------------------------------------
| FUNCTION EmptyRect(r: Rect): BOOLEAN;
| CLOBBERS D0,D1,A0,A1.
| Called during boot (7,391 times in 30s trace).
EmptyRect:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE.L  (SP)+,A0                        | POP ADDR OF RECT
        MOVE    (A0)+,D0                        | GET TOP
        MOVE    (A0)+,D1                        | GET LEFT
        CMP     (A0)+,D0                        | IS TOP >= BOTTOM ?
        BGE.B   EMPTYRECT_EXIT                  | YES, RETURN TRUE
        CMP     (A0)+,D1                        | IS LEFT >= RIGHT ?
        BGE.B   EMPTYRECT_EXIT                  | YES, RETURN TRUE
        CLR.B   (SP)                            | NOT EMPTY, RETURN FALSE
        BRA.B   EMPTYRECT_RETURN                | AND QUIT (skip the TRUE-path MOVE.B)
EMPTYRECT_EXIT:
        MOVE.B   #0x1,(SP)                      | YES, RETURN TRUE
EMPTYRECT_RETURN:
        JMP      (A1)                           | RETURN

| .PROC OffsetRect
| ----------------------------------------------------------
| PROCEDURE OffsetRect(VAR r: Rect; dh,dv: INTEGER);
| Called during boot.
OffsetRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | POP DV
        MOVE    (SP)+,D0                        | POP DH
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        ADD     D1,(A1)+                        | TOP:=TOP+DV
        ADD     D0,(A1)+                        | LEFT:=LEFT+DH
        ADD     D1,(A1)+                        | BOTTOM:=BOTTOM+DV
        ADD     D0,(A1)+                        | RIGHT:=RIGHT+DH
        JMP     (A0)                            | RETURN

| .PROC InsetRect
| ----------------------------------------------------------
| PROCEDURE InsetRect(VAR r: Rect; dh,dv: INTEGER);
| { inset a rectangle on all 4 sides }
| Called during boot.
InsetRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D1                        | POP DV
        MOVE    (SP)+,D0                        | POP DH
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        ADD     D1,(A1)+                        | ADD DV TO TOP
        ADD     D0,(A1)+                        | ADD DH TO LEFT
        SUB     D1,(A1)+                        | SUBTRACT DV FROM BOTTOM
        SUB     D0,(A1)+                        | SUBTRACT DH FROM RIGHT
        JMP     (A0)                            | DONE: RETURN
| ----------------------------------------------------------
|
| _SectRect ($A8AA): intersection of two rectangles
| Pascal: FUNCTION SectRect(src1, src2: Rect; VAR dstRect: Rect): BOOLEAN;
| Calls RSect with nRects = 2. Returns TRUE and the intersection in
| dstRect, else FALSE and dstRect = (0,0,0,0); dstRect may also be one
| of the inputs.
|
SectRect:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVE.L  16(A6),-(SP)                    | PUSH SRCA POINTER
        MOVE.L  12(A6),-(SP)                    | PUSH SRCB POINTER
        MOVE    #0x2,-(SP)                      | push nRects = 2 (intersect 2 rects)
        MOVE.L  8(A6),-(SP)                     | PUSH DST POINTER
        BSR.W   RSect                           | CALC INTERSECTION
        SNE     20(A6)                          | STORE BOOLEAN RESULT
        NEG.B   20(A6)                          | CONVERT $FF TO $01
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xC,SP                         | pop 12 bytes of params
        JMP     (A0)                            | RTS

| ---------------------------------------------------
| ASSEMBLY CALLABLE ROUTINE TO COMPUTE THE INTERSECTION OF
| ANY NUMBER OF RECTANGLES.
| INPUTS: PUSH ADDRESSES OF EACH INPUT RECTANGLE (LONGS)
| PUSH # OF RECTANGLES (WORD)
| PUSH ADDRESS OF OUTPUT RECTANGLE (LONG)
| RETURNS DST=(0,0,0,0) AND Z-FLAG SET IF NO INTERSECTION
| CLOBBERS: D0,A0
| Called during boot (10,843 times in 30s trace).
RSect:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L D1-D4/A1,-(SP)                  | SAVE REGS
        LEA.L     12(A6),A1                     | POINT TO NRECTS
        MOVE    (A1)+,D0                        | GET NRECTS COUNT
        BLE.B   SECTRECT_EMPTY                  | EMPTY IF NRECTS <= 0
        MOVE.L  (A1)+,A0                        | POINT TO FIRST RECT
        MOVEM   (A0)+,D1-D4                     | GET TOP, LEFT, BOT, RIGHT
        SUBQ.W  #0x1,D0                         | DECREMENT RECT COUNT
        BRA.B   RSECT_TEST_EMPTY                | CHECK THIS RECT AND LOOP
RSECT_LOOP:
        MOVE.L  (A1)+,A0                        | POINT TO NEXT RECT
        CMP     (A0)+,D1                        | IS TOP < NEXT TOP ?
        BGE.B   RSECT_TOP_OK                    | NO, CONTINUE
        MOVE    -2(A0),D1                       | YES, TOP:=NEXT TOP
RSECT_TOP_OK:
        CMP     (A0)+,D2                        | IS LEFT < NEXT LEFT ?
        BGE.B   RSECT_LEFT_OK                   | NO, CONTINUE
        MOVE    -2(A0),D2                       | YES, LEFT:=NEXT LEFT
RSECT_LEFT_OK:
        CMP     (A0)+,D3                        | IS BOTTOM > NEXT BOT ?
        BLE.B   RSECT_BOT_OK                    | NO, CONTINUE
        MOVE    -2(A0),D3                       | YES, BOTTOM:=NEXT BOT
RSECT_BOT_OK:
        CMP     (A0)+,D4                        | IS RIGHT > NEXT RIGHT ?
        BLE.B   RSECT_TEST_EMPTY                | NO, CONTINUE
        MOVE    -2(A0),D4                       | YES, RIGHT:=NEXT RIGHT
RSECT_TEST_EMPTY:
        CMP     D1,D3                           | IS BOTTOM <= TOP ?
        BLE.B   SECTRECT_EMPTY                  | YES, EMPTY
        CMP     D2,D4                           | IS RIGHT <= LEFT ?
        BLE.B   SECTRECT_EMPTY                  | YES, EMPTY
        DBRA    D0,RSECT_LOOP                   | LOOP FOR ALL RECTANGLES
        BRA.B   SECTRECT_DONE                   | DONE

| ----------------------------------------------------------
| SECTRECT_EMPTY
| Called during boot.
SECTRECT_EMPTY:
        CLR     D1                              | ALL EMPTY RECTS ARE (0,0,0,0)
        CLR     D2                              | ALL EMPTY RECTS ARE (0,0,0,0)
        CLR     D3                              | ALL EMPTY RECTS ARE (0,0,0,0)
        CLR     D4                              | ALL EMPTY RECTS ARE (0,0,0,0)
SECTRECT_DONE:
        MOVE.L  0x8(A6),A0                      | GET DST ADDR
        MOVE    D1,(A0)+                        | STORE DST TOP
        MOVE    D2,(A0)+                        | DST LEFT
        MOVE    D3,(A0)+                        | DST BOT
        MOVE    D4,(A0)+                        | DST RIGHT
        MOVE    0xC(A6),D0                      | GET NRECTS COUNT AGAIN
        LSL     #0x2,D0                         | TIMES 4 BYTES PER RECTANGLE
        ADDQ.W  #0x6,D0                         | PLUS 6 BYTES FOR NRECTS AND DSTPTR
        CMP     D1,D3                           | SET Z-FLAG IF EMPTY RECT
        MOVEM.L (SP)+,D1-D4/A1                  | RESTORE REGS
        UNLK    A6                              | RELEASE STATIC FRAME PTR
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADD     D0,SP                           | STRIP VARIABLE NUMBER OF PARAMS
        JMP     (A0)                            | RETURN WITH Z-FLAG IF EMPTY
| ----------------------------------------------------------
|
| _UnionRect ($A8AB): smallest rectangle enclosing two rectangles
| Pascal: PROCEDURE UnionRect(src1, src2: Rect; VAR dstRect: Rect);
| Works correctly even if one of the sources is the destination.
|
UnionRect:
        MOVE.L  12(SP),A0                       | GET ADDR OF SRC1
        MOVE.L  8(SP),A1                        | GET ADDR OF SRC2
        MOVE    (A0)+,D0                        | TOP:=TOP1
        CMP     (A1)+,D0                        | IS TOP2 < TOP ?
        BLE.B   UNIONRECT_TOPOK                 | NO, CONTINUE
        MOVE    -2(A1),D0                       | YES, TOP:=TOP2
UNIONRECT_TOPOK:
        SWAP    D0                              | PUT TOP IN HI WORD
        MOVE    (A0)+,D0                        | LEFT:=LEFT1
        CMP     (A1)+,D0                        | IS LEFT2 < LEFT ?
        BLE.B   UNIONRECT_LEFTOK                | NO, CONTINUE
        MOVE    -2(A1),D0                       | YES, LEFT:=LEFT2
UNIONRECT_LEFTOK:
        MOVE    (A0)+,D1                        | BOTTOM:=BOTTOM1
        CMP     (A1)+,D1                        | IS BOTTOM2 > BOTTOM ?
        BGE.B   UNIONRECT_BOTOK                 | NO, CONTINUE
        MOVE    -2(A1),D1                       | YES, BOTTOM:=BOTTOM2
UNIONRECT_BOTOK:
        SWAP    D1                              | PUT BOTTOM IN HI WORD
        MOVE    (A0)+,D1                        | RIGHT:=RIGHT1
        CMP     (A1)+,D1                        | IS RIGHT2 > RIGHT1 ?
        BGE.B   UNIONRECT_RIGHTOK               | NO, CONTINUE
        MOVE    -2(A1),D1                       | YES, RIGHT:=RIGHT2
UNIONRECT_RIGHTOK:
        MOVE.L  4(SP),A0                        | POINT TO DST RECT
        MOVE.L  D0,(A0)+                        | INSTALL TOPLEFT
        MOVE.L  D1,(A0)+                        | INSTALL BOTRIGHT
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xC,SP                         | pop 12 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _Pt2Rect ($A8AC): smallest rectangle containing two points
| Pascal: PROCEDURE Pt2Rect(pt1, pt2: Point; VAR dstRect: Rect);
|
Pt2Rect:
        MOVE.L  4(SP),A0                        | POINT TO DST RECT
        MOVE    14(SP),D0                       | GET H1
        MOVE    10(SP),D1                       | GET H2
        CMP     D0,D1                           | IS H2 < H1 ?
        BGE.B   HOK                             | NO, CONTINUE
        EXG     D0,D1                           | YES, SWAP THEM
HOK:
        MOVE    D0,2(A0)                        | INSTALL DST LEFT = MIN(H1,H2)
        MOVE    D1,6(A0)                        | INSTALL DST RIGHT = MAX(H1,H2)
        MOVE    12(SP),D0                       | GET V1
        MOVE    8(SP),D1                        | GET V2
        CMP     D0,D1                           | IS V2 < V1 ?
        BGE.B   HOK_NO                          | NO, CONTINUE
        EXG     D0,D1                           | YES, SWAP THEM
HOK_NO:
        MOVE    D0,(A0)                         | install dst top = min(V1,V2)
        MOVE    D1,4(A0)                        | INSTALL DST BOTTOM = MAX(V1,V2)
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDA.W  #0xC,SP                         | strip 3 parameters (12 bytes)
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _PtInRect ($A8AD): test whether a point lies inside a rectangle
| Pascal: FUNCTION PtInRect(pt: Point; r: Rect): BOOLEAN;
| TRUE if top <= pt.v < bottom and left <= pt.h < right.
|
PtInRect:
        LINK    A6,#0x0                         | NO LOCAL VARS
        MOVE.L  8(A6),A0                        | GET RECT PTR
        MOVE    14(A6),D0                       | GET HORIZ COORD (PT.H)
        MOVE    12(A6),D1                       | GET VERT COORD (PT.V)
        CLR.B   16(A6)                          | INIT BOOLEAN TO FALSE
        CMP     (A0)+,D1                        | IS PT.V < TOP ?
        BLT.B   PTINRECT_EXIT                   | YES, QUIT
        CMP     (A0)+,D0                        | IS PT.H < LEFT ?
        BLT.B   PTINRECT_EXIT                   | YES, QUIT
        CMP     (A0)+,D1                        | IS PT.V >= BOTTOM ?
        BGE.B   PTINRECT_EXIT                   | YES, QUIT
        CMP     (A0)+,D0                        | IS PT.H >= RIGHT ?
        BGE.B   PTINRECT_EXIT                   | YES, QUIT
        ADDQ.B  #0x1,16(A6)                     | RETURN BOOLEAN TRUE
PTINRECT_EXIT:
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | pop 8 bytes of parameters
        JMP     (A0)                            | RTS

| .PROC PutRect,4
| .REF SetSize
| ----------------------------------------------------------------
| PROCEDURE PutRect(r: Rect; bufHandle: Handle; VAR index,size: INTEGER);
| Puts the four inversion points of a rectangle
| Clobbers D0,A0,A1
| A6 OFFSETS OF PARAMETERS AFTER LINK:
| PARAMSIZE .EQU 16 ;TOTAL SIZE OF PARAMETERS
| RECT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF RECT
| BUFHANDLE .EQU RECT-4 ;LONG, HANDLE
| INDEX .EQU BUFHANDLE-4 ;LONG, ADDR OF INTEGER
| SIZE .EQU INDEX-4 ;LONG, ADDR OF INTEGER
PutRect:
        LINK    A6,#0x0                         | NO LOCAL VARIABLES
        MOVE.L  12(A6),A0                       | POINT TO INDEX
        MOVE.L  8(A6),A1                        | POINT TO SIZE
        MOVEQ.L #0x10,D0                        | 16 bytes for 4 points
        ADD     (A0),D0                         | GET CURRENT INDEX + 16
        CMP     (A1),D0                         | IS NEW INDEX > SIZE ?
        BLE.B   PUTRECT_SIZEOK                  | NO, CONTINUE
        ADDI    #0x400,(A1)                     | (A1) += 0x400
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        MOVE.L  16(A6),-(SP)                    | PUSH HANDLE PARAM
        MOVE    (A1),-(SP)                      | PUSH NEW SIZE
        JSR     SetHSize(PC)                    | MAKE THE BUFFER BIGGER
        MOVEM.L (SP)+,D3/A2                     | RESTORE REGS
        MOVE.L  12(A6),A0                       | POINT TO INDEX AGAIN

| ------------------------------------------------------------
| NOW INSTALL THE 4 NEW INVERSION POINTS
PUTRECT_SIZEOK:
        MOVE.L  16(A6),A1                       | GET BUFHANDLE
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        ADDA.W  (A0),A1                         | ADD INDEX FOR POINTER
        ADDI    #0x10,(A0)                      | (A0) += 0x10
        MOVE.L  20(A6),A0                       | POINT TO RECTANGLE
        MOVE.L  (A0),(A1)+                      | PUT TOPLEFT POINT
        MOVE    (A0),(A1)+                      | PUT TOP-RIGHT POINT
        MOVE    6(A0),(A1)+                     | PUT TOP-RIGHT POINT
        MOVE    4(A0),(A1)+                     | PUT BOTTOM-LEFT POINT
        MOVE    2(A0),(A1)+                     | PUT BOTTOM-LEFT POINT
        MOVE.L  4(A0),(A1)+                     | PUT BOTRIGHT POINT
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0x10,SP                        | pop 16 bytes of parameters
        JMP     (A0)                            | RTS

