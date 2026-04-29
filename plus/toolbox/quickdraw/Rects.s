|-----------------------------------------------------------
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
|
| PROCEDURE StdRect(verb: GrafVerb; r: Rect);
|
| A6 OFFSETS OF PARAMS AFTER LINK:
|
| Called during boot.
StdRect:
.set PARAMSIZE, 6                               | TOTAL BYTES OF PARAMS
.set VERB, PARAMSIZE+8-2                        | GRAFVERB
.set RECT, VERB-4                               | LONG, ADDR OF RECT

        LINK    A6,#0                           | NO LOCALS
        MOVEM.L D7/A3-A4,-(SP)                  | SAVE REGS
        MOVE.B  0xC(A6),D7                      | GET VERB
        JSR     CheckPic(PC)                    | SET UP A4,A3 AND CHECK PICSAVE
        BLE.B   STDRECT_NOTPIC                  | BRANCH IF NOT PICSAVE
        MOVE.B  D7,-(SP)                        | PUSH VERB
        JSR     PutPicVerb(PC)                  | PUT ADDIONAL PARAMS TO THEPIC
        MOVEQ.L #0x30,D0                        | GET RECTNOUN IN HI NIBBLE
        ADD     D7,D0                           | PUT VERB IN LO NIBBLE
        MOVE.B  D0,-(SP)                        | PUSH OPCODE
        MOVE.L  0x8(A6),-(SP)                   | PUSH ADDR OF RECT
        JSR     PutPicRect(PC)                  | PUT OPCODE AND RECTANGLE
STDRECT_NOTPIC:
        MOVE.L  0x8(A6),-(SP)                   | PUSH RECT FOR FrRect or DrawRect
        TST.B   D7                              | IS VERB FRAME ?
        BNE.B   STDRECT_NOTFR                   | NO, CONTINUE
        TST.L   RGNSAVE(A3)                     | YES, IS RGNSAVE TRUE ?
        BEQ.B   STDRECT_NOTRGN                  | NO, CONTINUE
        MOVE.L  0x8(A6),-(SP)                   | YES, PUSH ADDR OF RECT
        MOVE.L  RGNBUF(A4),-(SP)                | PUSH RGNBUF
        PEA.L   RGNINDEX(A4)                    | PUSH VAR RGNINDEX
        PEA.L   RGNMAX(A4)                      | PUSH VAR RGNMAX
        JSR     PutRect(PC)                     | ADD A RECT TO THERGN
STDRECT_NOTRGN:
        JSR     FrRect(PC)                      | FrRect(rect)
        BRA.B   STDRECT_GOHOME                  | branch to exit

| ----------------------------------------------------------
|
| STDRECT_NOTFR
|
| Called during boot.
STDRECT_NOTFR:
        JSR     PushVerb(PC)                    | PUSH MODE AND PATTERN
        JSR     DrawRect(PC)                    | DrawRect(rect,mode,pat);
STDRECT_GOHOME:
        MOVEM.L (SP)+,D7/A3-A4                  | GOHOME: RESTORE REGS
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | pop 6 bytes of parameters
        JMP     (A0)                            | return to caller

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
| Called during boot.
PushVerb:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    #8,-(SP)                        | PUSH MODE = PATCOPY (IE. DEFAULT)
        CMPI.B  #0x1,D7                         | case on verb
        BLE.B   PUSHVERB_PAINT1                 | branch if frame or paint
        CMPI.B  #0x3,D7                         | check if invert
        BLT.B   PUSHVERB_ERASE1                 | branch if erase
        BEQ.B   PUSHVERB_ERASE1_CONT            | branch if invert
        PEA.L   FILLPAT(A3)                     | PUSH PAT := FILLPAT
        BRA.B   PUSHVERB_DONE                   | branch to exit

| ----------------------------------------------------------
|
| PUSHVERB_ERASE1
|
| Called during boot.
PUSHVERB_ERASE1:
        PEA.L   BKPAT(A3)                       | PUSH PAT = BKPAT
        BRA.B   PUSHVERB_DONE                   | branch to exit

| ----------------------------------------------------------
|
| PUSHVERB_ERASE1_CONT
|
| Called during boot.
PUSHVERB_ERASE1_CONT:
        ADDQ.W  #0x2,(SP)                       | adjust, push mode = patXor
        PEA.L   BLACK(A4)                       | PUSH PAT = BLACK
        BRA.B   PUSHVERB_DONE                   | branch to exit

| ----------------------------------------------------------
|
| PUSHVERB_PAINT1
|
| Called during boot.
PUSHVERB_PAINT1:
        MOVE    PNMODE(A3),(SP)                 | PAINT1: REPLACE, PUSH MODE = PNMODE
        PEA.L   PNPAT(A3)                       | PUSH PAT = PNPAT
PUSHVERB_DONE:
        JMP     (A0)                            | DONE: RETURN TO CALLER

| .PROC FillRect,2
| .DEF CallRect,FrameRect,PaintRect,EraseRect,InvertRect
| .REF StdRect
| ----------------------------------------------------------
|
| PROCEDURE FillRect(r: Rect; pat: Pattern);
|
| Called during boot.
FillRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A0                         | get current grafPort
        LEA.L   FILLPAT(A0),A0                  | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | verb = fill

| ----------------------------------------------------------
|
| PROCEDURE FrameRect(r: Rect);
|
| FrameRect
        BRA.B   CallRect                        | SHARE COMMON CODE

| ----------------------------------------------------------
|
| _CopyPalette ($A8A1)
|
| Called during boot.
FrameRect:
        MOVEQ.L #0x0,D0                         | verb = frame

| ----------------------------------------------------------
|
| PROCEDURE PaintRect(r: Rect);
|
| PaintRect
        BRA.B   CallRect                        | SHARE COMMON CODE

| ----------------------------------------------------------
|
| _PaletteDispatch ($A8A2)
|
| Called during boot.
PaintRect:
        MOVEQ.L #0x1,D0                         | verb = paint

| ----------------------------------------------------------
|
| PROCEDURE EraseRect(r: Rect);
|
| EraseRect
        BRA.B   CallRect                        | SHARE COMMON CODE

| ----------------------------------------------------------
|
| _EraseRect ($A8A3)
|
| Called during boot.
EraseRect:
        MOVEQ.L #0x2,D0                         | verb = erase

| ----------------------------------------------------------
|
| PROCEDURE InvertRect(r: Rect);
|
| InvertRect
        BRA.B   CallRect                        | SHARE COMMON CODE

| ----------------------------------------------------------
|
| _InverRect ($A8A4)
|
| Called during boot.
InvertRect:
        MOVEQ.L #0x3,D0                         | verb = invert
        NOP                                     | alignment padding

| ---------------------------------------------------------------
|
| PROCEDURE CallRect(r: Rect);
|
| code shared by FrameRect, PaintRect, EraseRect, InvertRect, and FillRect.
| enter with verb in D0.
|
| Called during boot.
CallRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A0                         | get current grafPort
        MOVE.L  GRAFPROCS(A0),D0                | IS GRAFPROCS NIL ?
        MOVE.L  (0xE80).w,A0                    | _StdRect (rectProc)
        BEQ.B   CALLRECT_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | put procs ptr in A0
        MOVE.L  RECTPROC(A0),A0                 | NO, GET PROC PTR
CALLRECT_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| .PROC DrawRect,3
| .REF RgnBlt
| ----------------------------------------------------------
|
| PROCEDURE DrawRect(r: Rect; mode: INTEGER; pat: Pattern);
|
| Rectangle is given in local coordinates.
|
| A6 OFFSETS OF PARAMS AND LOCALS AFTER LINK:
|
| PARAMSIZE .EQU 10 ;TOTAL BYTES OF PARAMS
| DSTRECT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF RECT
| MODE .EQU DSTRECT-2 ;WORD
| PAT .EQU MODE-4 ;LONG, ADDR OF PAT
| Called during boot.
DrawRect:
.set PARAMSIZE, 10                              | TOTAL BYTES OF PARAMS
.set DSTRECT, PARAMSIZE+8-4                     | LONG, ADDR OF RECT
.set MODE, DSTRECT-2                            | WORD
.set PAT, MODE-4                                | LONG, ADDR OF PAT

        LINK    A6,#0                           | NO LOCAL VARS
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A1                         | GET CURRENT GRAFPORT
        TST     PNVIS(A1)                       | IS PNVIS >= 0 ?
        BLT.B   DRAWRECT_EXIT                   | NO, QUIT
        PEA.L   PORTBITS(A1)                    | PUSH SRCBITS = DSTBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        MOVE.L  0xE(A6),-(SP)                   | PUSH SRCRECT = DSTRECT
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT
        MOVE    0xC(A6),-(SP)                   | PUSH MODE
        MOVE.L  0x8(A6),-(SP)                   | PUSH ADDR OF PATTERN
        MOVE.L  CLIPRGN(A1),-(SP)               | PUSH CLIPRGN
        MOVE.L  VISRGN(A1),-(SP)                | PUSH VISRGN
        MOVE.L  WIDEOPEN(A0),-(SP)              | PUSH WIDE OPEN
        JSR     RgnBlt(PC)                      | CALL RGNBLT
DRAWRECT_EXIT:
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xA,SP                         | pop 10 bytes of parameters
        JMP     (A0)                            | return to caller

| .PROC FrRect,1
| .REF RgnBlt
| ----------------------------------------------------------
|
| PROCEDURE FrRect(r: Rect);
| Draws an outline inside a rect.
|
| A6 OFFSETS OF PARAMETERS AND LOCALS AFTER LINK:
|
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
.set DSTRECT, 8                                 | LONG, ADDR OF RECT
.set H1, -2                                     | WORD
.set H2, H1-2                                   | WORD
.set H3, H2-2                                   | WORD
.set H4, H3-4                                   | WORD
.set V1, H4-2                                   | WORD
.set V2, V1-2                                   | WORD
.set V3, V2-2                                   | WORD
.set V4, V3-4                                   | WORD
.set TEMPRECT, V4-8                             | RECT
.set VARSIZE, TEMPRECT                          | TOTAL SIZE OF LOCALS

        TST     PNVIS(A0)                       | IS PNVIS NEGATIVE ?
        BLT     FILLED_SKIP                     | YES, DON'T DRAW AT ALL
        MOVE.L  0x8(A6),A1                      | POINT TO INPUT RECT
        MOVE.L  (A1)+,-0x1C(A6)                 | copy input rect
        MOVE.L  (A1)+,-0x18(A6)                 | copy input rect

|
| Now set up h1,h2,h3,h4 and v1,v2,v3,v4
|
        LEA.L   -0x1C(A6),A1                    | POINT TO COPIED RECT
        MOVE    0x36(A0),D2                     | GET PEN WIDTH

        MOVE    LEFT(A1),D0                     | get left edge
        MOVE    D0,-0x2(A6)                     | H1:=LEFT
        ADD     D2,D0                           | calculate H2
        MOVE    D0,-0x4(A6)                     | H2:=LEFT+PENWIDTH
        MOVE    RIGHT(A1),D1                    | get right edge
        MOVE    D1,-0xA(A6)                     | H4:=RIGHT
        SUB     D2,D1                           | calculate H3
        MOVE    D1,-0x6(A6)                     | H3:=RIGHT-PENWIDTH
        CMP     D1,D0                           | IS H2 >= H3 ?
        BGE.B   FRRECT_OK                       | YES, FILL IT IN SOLID
        MOVE    0x34(A0),D2                     | GET PEN HEIGHT
        MOVE    (A1),D0                         | get top edge
        MOVE    D0,-0xC(A6)                     | V1:=TOP
        ADD     D2,D0                           | calculate H2
        MOVE    D0,-0xE(A6)                     | V2:=TOP+PENHEIGHT
        MOVE    BOTTOM(A1),D1                   | get bottom edge
        MOVE    D1,-0x14(A6)                    | V4:=BOTTOM
        SUB     D2,D1                           | calculate H3
        MOVE    D1,-0x10(A6)                    | V3:=BOTTOM-PENHEIGHT
        CMP     D1,D0                           | IS V2 >= V3 ?
        BGE.B   FRRECT_OK                       | YES, FILL IT IN SOLID
        MOVE    -0x2(A6),-0x1A(A6)              | setup tempRect left = H1
        MOVE    -0x6(A6),-0x16(A6)              | setup tempRect right = H3
        MOVE    -0xC(A6),-0x1C(A6)              | setup tempRect top = V1
        MOVE    -0xE(A6),-0x18(A6)              | setup tempRect bottom = V2

|
| PEN IS NOT SO BIG AS TO FILL IN SOLID. BREAK RECT INTO 4 EDGES.
|
        BSR.B   DORECT                          | PAINT TOP EDGE
        MOVE    -0x6(A6),-0x1A(A6)              | setup tempRect left = H3
        MOVE    -0xA(A6),-0x16(A6)              | setup tempRect right = H4
        MOVE    -0x10(A6),-0x18(A6)             | setup tempRect bottom = V3
        BSR.B   DORECT                          | PAINT RIGHT EDGE
        MOVE    -0x4(A6),-0x1A(A6)              | setup tempRect left = H2
        MOVE    -0x10(A6),-0x1C(A6)             | setup tempRect top = V3
        MOVE    -0x14(A6),-0x18(A6)             | setup tempRect bottom = V4
        BSR.B   DORECT                          | PAINT BOTTOM EDGE
        MOVE    -0x2(A6),-0x1A(A6)              | setup tempRect left = H1
        MOVE    -0x4(A6),-0x16(A6)              | setup tempRect right = H2
        MOVE    -0xE(A6),-0x1C(A6)              | setup tempRect top = V2
FRRECT_OK:
        BRA.B   FILLED                          | PAINT LEFT EDGE

| ----------------------------------------------------------
|
| DORECT
|
| Called during boot.
DORECT:
        MOVE.L  (A5),A0                         | point to QuickDraw globals
        MOVE.L  (A0),A1                         | GET CURRENT GRAFPORT

| --------------------------------------------------------
|
| LOCAL ROUTINE TO PAINT TEMPRECT, GIVEN IN LOCAL COORDS
|
        PEA.L   PORTBITS(A1)                    | PUSH SRCBITS = DSTBITS
        MOVE.L  (SP),-(SP)                      | PUSH DSTBITS
        PEA.L   -0x1C(A6)                       | PUSH SRCRECT = DSTRECT
        MOVE.L  (SP),-(SP)                      | PUSH DSTRECT, LOCAL COORDS
        MOVE    PNMODE(A1),-(SP)                | PUSH PEN MODE
        PEA.L   PNPAT(A1)                       | PUSH ADDR OF PEN PATTERN
        MOVE.L  CLIPRGN(A1),-(SP)               | PUSH CLIPRGN
        MOVE.L  VISRGN(A1),-(SP)                | PUSH VISRGN
        MOVE.L  WIDEOPEN(A0),-(SP)              | PUSH WIDE OPEN
        JSR     RgnBlt(PC)                      | CALL RGNBLT
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FILLED
|
| Called during boot.
FILLED:
        BSR.B   DORECT                          | FILL TEMPRECT SOLID
FILLED_SKIP:
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,(SP)                      | strip param and replace ret addr
        RTS                                     | return to caller

| .PROC SetRect
| ----------------------------------------------------------
|
| PROCEDURE SetRect(VAR r: Rect; left,top,right,bottom: INTEGER);
| { assign 4 integers into a rectangle }
|
| Called during boot.
SetRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D1                        | POP BOTRIGHT POINT
        MOVE.L  (SP)+,D0                        | POP TOPLEFT POINT
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.L  D0,(A1)+                        | INSTALL TOPLEFT
        MOVE.L  D1,(A1)+                        | INSTALL BOTRIGHT
        JMP     (A0)                            | RETURN

| .PROC EqualRect
| ----------------------------------------------------------
|
| FUNCTION EqualRect(rect1,rect2: Rect): BOOLEAN;
|
| CLOBBERS D0,A0,A1.
|
EqualRect:
        MOVE.L  (SP)+,D0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT2
        MOVE.L  (SP)+,A0                        | POP ADDR OF RECT1
        CMPM.L  (A0)+,(A1)+                     | IS TOPLEFT SAME ?
        BNE.B   FALSE                           | NO, RETURN FALSE
        CMPM.L  (A0)+,(A1)+                     | YES, IS BOTRIGHT SAME TOO ?
        BNE.B   FALSE                           | NO, RETURN FALSE
        MOVE.B  #1,(SP)                         | YES, RETURN TRUE
        BRA.B   EQUALRECT_DONE                  | AND QUIT

| ----------------------------------------------------------
|
| FALSE
|
FALSE:
        CLR.B   (SP)                            | RETURN FALSE
EQUALRECT_DONE:
        MOVE.L  D0,-(SP)                        | DONE: PUSH RETURN ADDR
        RTS                                     | return to caller

| .PROC EmptyRect
| ----------------------------------------------------------
|
| FUNCTION EmptyRect(r: Rect): BOOLEAN;
|
| CLOBBERS D0,D1,A0,A1.
|
| Called during boot (7,391 times in 30s trace).
EmptyRect:
        MOVE.L  (SP)+,A1                        | POP RETURN ADDR
        MOVE.L  (SP)+,A0                        | POP ADDR OF RECT
        MOVE    (A0)+,D0                        | GET TOP
        MOVE    (A0)+,D1                        | GET LEFT
        CMP     (A0)+,D0                        | IS TOP >= BOTTOM ?
        BGE.B   EMPTYRECT_EMPTY                 | YES, RETURN TRUE
        CMP     (A0)+,D1                        | IS LEFT >= RIGHT ?
        BGE.B   EMPTYRECT_EMPTY                 | YES, RETURN TRUE
        CLR.B   (SP)                            | NOT EMPTY, RETURN FALSE
        BRA.B   EMPTYRECT_DONE                  | AND QUIT

| ----------------------------------------------------------
|
| EMPTYRECT_EMPTY
|
| Called during boot (7,383 times in 30s trace).
EMPTYRECT_EMPTY:
        MOVE.B  #1,(SP)                         | EMPTY: RETURN TRUE
EMPTYRECT_DONE:
        JMP     (A1)                            | DONE: RETURN

| .PROC OffsetRect
| ----------------------------------------------------------
|
| PROCEDURE OffsetRect(VAR r: Rect; dh,dv: INTEGER);
|
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

| RTS ;AND RETURN
| .PROC InsetRect
| ----------------------------------------------------------
|
| PROCEDURE InsetRect(VAR r: Rect; dh,dv: INTEGER);
| { inset a rectangle on all 4 sides }
|
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
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| PARAMSIZE .EQU 12 ;SIZE OF PARAMETERS
| RESULT .EQU PARAMSIZE+8 ;BOOLEAN RESULT
| SRCA .EQU RESULT-4 ;LONG, ADDR OF RECTANGLE
| SRCB .EQU SRCA-4 ;LONG, ADDR OF RECTANGLE
| DST .EQU SRCB-4 ;LONG, ADDR OF RECTANGLE
| Called during boot.
SectRect:
.set PARAMSIZE, 12                              | SIZE OF PARAMETERS
.set RESULT, PARAMSIZE+8                        | BOOLEAN RESULT
.set SRCA, RESULT-4                             | LONG, ADDR OF RECTANGLE
.set SRCB, SRCA-4                               | LONG, ADDR OF RECTANGLE
.set DST, SRCB-4                                | LONG, ADDR OF RECTANGLE

        LINK    A6,#0                           | NO LOCAL VARS
        MOVE.L  0x10(A6),-(SP)                  | PUSH SRCA POINTER
        MOVE.L  0xC(A6),-(SP)                   | PUSH SRCB POINTER
        MOVE    #2,-(SP)                        | PUSH NRECTS=2
        MOVE.L  0x8(A6),-(SP)                   | PUSH DST POINTER
        BSR.B   RSect                           | CALC INTERSECTION
        SNE.B   0x14(A6)                        | STORE BOOLEAN RESULT
        NEG.B   0x14(A6)                        | CONVERT $FF TO $01
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xC,SP                         | pop 12 bytes of parameters
        JMP     (A0)                            | return to caller

| ---------------------------------------------------
|
| ASSEMBLY CALLABLE ROUTINE TO COMPUTE THE INTERSECTION OF
| ANY NUMBER OF RECTANGLES.
|
| INPUTS: PUSH ADDRESSES OF EACH INPUT RECTANGLE (LONGS)
| PUSH # OF RECTANGLES (WORD)
| PUSH ADDRESS OF OUTPUT RECTANGLE (LONG)
|
| RETURNS DST=(0,0,0,0) AND Z-FLAG SET IF NO INTERSECTION
|
| CLOBBERS: D0,A0
|
| Called during boot (10,843 times in 30s trace).
RSect:
        LINK    A6,#0                           | no local vars
        MOVEM.L D1-D4/A1,-(SP)                  | SAVE REGS
        LEA.L   0xC(A6),A1                      | POINT TO NRECTS
        MOVE    (A1)+,D0                        | GET NRECTS COUNT
        BLE.B   SECTRECT_EMPTY                  | EMPTY IF NRECTS <= 0
        MOVE.L  (A1)+,A0                        | POINT TO FIRST RECT
        MOVEM   (A0)+,D1-D4                     | GET TOP, LEFT, BOT, RIGHT
        SUBQ.W  #0x1,D0                         | DECREMENT RECT COUNT
        BRA.B   RTOK                            | CHECK THIS RECT AND LOOP

| ----------------------------------------------------------
|
| NEXTRECT
|
| Called during boot (12,436 times in 30s trace).
NEXTRECT:
        MOVE.L  (A1)+,A0                        | POINT TO NEXT RECT
        CMP     (A0)+,D1                        | IS TOP < NEXT TOP ?
        BGE.B   SECTRECT_TOPOK                  | NO, CONTINUE
        MOVE    -0x2(A0),D1                     | YES, TOP:=NEXT TOP
SECTRECT_TOPOK:
        CMP     (A0)+,D2                        | TOPOK: IS LEFT < NEXT LEFT ?
        BGE.B   SECTRECT_LEFTOK                 | NO, CONTINUE
        MOVE    -0x2(A0),D2                     | YES, LEFT:=NEXT LEFT
SECTRECT_LEFTOK:
        CMP     (A0)+,D3                        | LEFTOK: IS BOTTOM > NEXT BOT ?
        BLE.B   SECTRECT_BOTOK                  | NO, CONTINUE
        MOVE    -0x2(A0),D3                     | YES, BOTTOM:=NEXT BOT
SECTRECT_BOTOK:
        CMP     (A0)+,D4                        | BOTOK: IS RIGHT > NEXT RIGHT ?
        BLE.B   RTOK                            | NO, CONTINUE
        MOVE    -0x2(A0),D4                     | YES, RIGHT:=NEXT RIGHT
RTOK:
        CMP     D1,D3                           | IS BOTTOM <= TOP ?
        BLE.B   SECTRECT_EMPTY                  | YES, EMPTY
        CMP     D2,D4                           | IS RIGHT <= LEFT ?
        BLE.B   SECTRECT_EMPTY                  | YES, EMPTY
        DBF     D0,NEXTRECT                     | LOOP FOR ALL RECTANGLES
        BRA.B   SECTRECT_DONE                   | DONE

| ----------------------------------------------------------
|
| SECTRECT_EMPTY
|
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
        LSL     #2,D0                           | TIMES 4 BYTES PER RECTANGLE
        ADDQ.W  #0x6,D0                         | PLUS 6 BYTES FOR NRECTS AND DSTPTR
        CMP     D1,D3                           | SET Z-FLAG IF EMPTY RECT
        MOVEM.L (SP)+,D1-D4/A1                  | RESTORE REGS
        UNLK    A6                              | RELEASE STATIC FRAME PTR
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADD     D0,SP                           | STRIP VARIABLE NUMBER OF PARAMS
        JMP     (A0)                            | RETURN WITH Z-FLAG IF EMPTY

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
UnionRect:
        MOVE.L  0xC(SP),A0                      | GET ADDR OF SRC1
        MOVE.L  0x8(SP),A1                      | GET ADDR OF SRC2
        MOVE    (A0)+,D0                        | TOP:=TOP1
        CMP     (A1)+,D0                        | IS TOP2 < TOP ?
        BLE.B   UNIONRECT_TOPOK                 | NO, CONTINUE
        MOVE    -0x2(A1),D0                     | YES, TOP:=TOP2 / LEFT:=LEFT2
UNIONRECT_TOPOK:
        SWAP    D0                              | TOPOK: PUT TOP IN HI WORD
        MOVE    (A0)+,D0                        | LEFT:=LEFT1
        CMP     (A1)+,D0                        | IS LEFT2 < LEFT ?
        BLE.B   UNIONRECT_LEFTOK                | NO, CONTINUE
        MOVE    -0x2(A1),D0                     | YES, TOP:=TOP2 / LEFT:=LEFT2
UNIONRECT_LEFTOK:
        MOVE    (A0)+,D1                        | LEFTOK: BOTTOM:=BOTTOM1
        CMP     (A1)+,D1                        | IS BOTTOM2 > BOTTOM ?
        BGE.B   UNIONRECT_BOTOK                 | NO, CONTINUE
        MOVE    -0x2(A1),D1                     | YES, BOTTOM:=BOTTOM2 / RIGHT:=RIGHT2
UNIONRECT_BOTOK:
        SWAP    D1                              | BOTOK: PUT BOTTOM IN HI WORD
        MOVE    (A0)+,D1                        | RIGHT:=RIGHT1
        CMP     (A1)+,D1                        | IS RIGHT2 > RIGHT1 ?
        BGE.B   UNIONRECT_RIGHTOK               | NO, CONTINUE
        MOVE    -0x2(A1),D1                     | YES, BOTTOM:=BOTTOM2 / RIGHT:=RIGHT2
UNIONRECT_RIGHTOK:
        MOVE.L  0x4(SP),A0                      | POINT TO DST RECT
        MOVE.L  D0,(A0)+                        | INSTALL TOPLEFT
        MOVE.L  D1,(A0)+                        | INSTALL BOTRIGHT
        BRA.B   PT2RECT_SHARE                   | STRIP 3 PARAMETERS AND RETURN

| ----------------------------------------------------------
|
| PROCEDURE Pt2Rect(* pt1,pt2: Point; VAR dst: Rect *);
|
| { make a rectangle from two points }
|
| Called during boot.
Pt2Rect:
        MOVE.L  0x4(SP),A0                      | POINT TO DST RECT
        MOVE    0xE(SP),D0                      | GET H1
        MOVE    0xA(SP),D1                      | GET H2

| ----------------------------------------------------------
|
        CMP     D0,D1                           | IS H2 < H1 ?
        BGE.B   HOK                             | NO, CONTINUE
        EXG     D0,D1                           | YES, SWAP THEM
HOK:
        MOVE    D0,LEFT(A0)                     | INSTALL DST LEFT = MIN(H1,H2)
        MOVE    D1,RIGHT(A0)                    | INSTALL DST RIGHT = MAX(H1,H2)
        MOVE    0xC(SP),D0                      | GET V1
        MOVE    0x8(SP),D1                      | GET V2
        CMP     D0,D1                           | IS V2 < V1 ?
        BGE.B   HOK_NO                          | NO, CONTINUE
        EXG     D0,D1                           | YES, SWAP THEM
HOK_NO:
        MOVE    D0,(A0)                         | INSTALL DST TOP = MIN(V1,V2)
        MOVE    D1,BOTTOM(A0)                   | INSTALL DST BOTTOM = MAX(V1,V2)
PT2RECT_SHARE:
        MOVE.L  (SP)+,A0                        | SHARE: POP RETURN ADDR
        ADD     #12,SP                          | STRIP 3 PARAMETERS
        JMP     (A0)                            | AND RETURN

| .PROC PtInRect
| ------------------------------------------------------------
|
| FUNCTION PtInRect(pt: Point; r: Rect): BOOLEAN;
|
| Returns TRUE if point is within the rectangle.
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| PARAMSIZE .EQU 8 ;SIZE OF PARAMETERS
| RESULT .EQU PARAMSIZE+8 ;A6 OFFSETS AFTER LINK
| PT .EQU RESULT-4 ;POINT, VALUE
| R .EQU PT-4 ;LONG, ADDR OF RECTANGLE
| Called during boot (43,763 times in 30s trace).
PtInRect:
.set PARAMSIZE, 8                               | SIZE OF PARAMETERS
.set RESULT, PARAMSIZE+8                        | A6 OFFSETS AFTER LINK
.set PT, RESULT-4                               | POINT, VALUE
.set R, PT-4                                    | LONG, ADDR OF RECTANGLE

        LINK    A6,#0                           | NO LOCAL VARS
        MOVE.L  0x8(A6),A0                      | POINT TO DST RECT
        MOVE    0xE(A6),D0                      | GET DH or PT.H
        MOVE    0xC(A6),D1                      | GET DV or PT.V
        CLR.B   0x10(A6)                        | INIT BOOLEAN TO FALSE
        CMP     (A0)+,D1                        | IS PT.V < TOP ?
        BLT.B   PTINRECT_EXIT                   | YES, QUIT
        CMP     (A0)+,D0                        | IS PT.H < LEFT ?
        BLT.B   PTINRECT_EXIT                   | YES, QUIT
        CMP     (A0)+,D1                        | IS PT.V >= BOTTOM ?
        BGE.B   PTINRECT_EXIT                   | YES, QUIT
        CMP     (A0)+,D0                        | IS PT.H >= RIGHT ?
        BGE.B   PTINRECT_EXIT                   | YES, QUIT
        ADDQ.B  #0x1,0x10(A6)                   | RETURN BOOLEAN TRUE
PTINRECT_EXIT:
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | pop parameters
        JMP     (A0)                            | return to caller

| .PROC PutRect,4
| .REF SetSize
| ----------------------------------------------------------------
|
| PROCEDURE PutRect(r: Rect; bufHandle: Handle; VAR index,size: INTEGER);
|
| Puts the four inversion points of a rectangle
|
| Clobbers D0,A0,A1
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| PARAMSIZE .EQU 16 ;TOTAL SIZE OF PARAMETERS
| RECT .EQU PARAMSIZE+8-4 ;LONG, ADDR OF RECT
| BUFHANDLE .EQU RECT-4 ;LONG, HANDLE
| INDEX .EQU BUFHANDLE-4 ;LONG, ADDR OF INTEGER
| SIZE .EQU INDEX-4 ;LONG, ADDR OF INTEGER
PutRect:
.set PARAMSIZE, 16                              | TOTAL SIZE OF PARAMETERS
.set RECT, PARAMSIZE+8-4                        | LONG, ADDR OF RECT
.set BUFHANDLE, RECT-4                          | LONG, HANDLE
.set INDEX, BUFHANDLE-4                         | LONG, ADDR OF INTEGER
.set SIZE, INDEX-4                              | LONG, ADDR OF INTEGER

        LINK    A6,#0                           | NO LOCAL VARIABLES

| ------------------------------------------------------------
|
| IS THERE ROOM FOR FOUR NEW POINTS IN THE POINT BUFFER ?
|
        MOVE.L  0xC(A6),A0                      | POINT TO INDEX
        MOVE.L  0x8(A6),A1                      | POINT TO SIZE

| ------------------------------------------------------------
|
        MOVEQ   #16,D0                          | 16 bytes for 4 points
        ADD     (A0),D0                         | GET CURRENT INDEX + 16
        CMP     (A1),D0                         | IS NEW INDEX > SIZE ?
        BLE.B   PUTRECT_SIZEOK                  | NO, CONTINUE
        ADDI    #0x400,(A1)                     | ADD 1024 TO SIZE

| -------------------------------------------------------------
|
| NO, GROW THE POINT BUFFER ENOUGH FOR 256 MORE POINTS
|
        MOVEM.L D3/A2,-(SP)                     | SAVE REGS
        MOVE.L  0x10(A6),-(SP)                  | PUSH HANDLE PARAM
        MOVE    (A1),-(SP)                      | PUSH NEW SIZE
        JSR     SetHSize(PC)                    | MAKE THE BUFFER BIGGER
        MOVEM.L (SP)+,D3/A2                     | RESTORE REGS
        MOVE.L  0xC(A6),A0                      | POINT TO INDEX AGAIN

| ------------------------------------------------------------
|
| NOW INSTALL THE 4 NEW INVERSION POINTS
|
PUTRECT_SIZEOK:
        MOVE.L  0x10(A6),A1                     | GET BUFHANDLE

| ------------------------------------------------------------
|
| NOW INSTALL THE 4 NEW INVERSION POINTS
|
        MOVE.L  (A1),A1                         | DE-REFERENCE HANDLE
        ADD     (A0),A1                         | ADD INDEX FOR POINTER
        ADDI    #0x10,(A0)                      | BUMP INDEX
        MOVE.L  0x14(A6),A0                     | POINT TO RECTANGLE
        MOVE.L  (A0),(A1)+                      | PUT TOPLEFT POINT
        MOVE    (A0),(A1)+                      | PUT TOP-RIGHT POINT
        MOVE    RIGHT(A0),(A1)+                 | PUT TOP-RIGHT POINT
        MOVE    BOTTOM(A0),(A1)+                | PUT BOTTOM-LEFT POINT
        MOVE    LEFT(A0),(A1)+                  | PUT BOTTOM-LEFT POINT
        MOVE.L  BOTRIGHT(A0),(A1)+              | PUT BOTRIGHT POINT
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0x10,SP                        | pop 16 bytes of parameters
        JMP     (A0)                            | return to caller


