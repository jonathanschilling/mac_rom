| -----------------------------------------------------------
|
| --> DRAWARC.TEXT
|
| Routine to draw solid or hollow Ovals, RoundRects or Arcs.
|
| ------------------------------------------------------
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

| .PROC StdArc,4
| .REF CheckPic, PutPicVerb, PutPicWord, PutPicRect
| .REF PushVerb, DrawArc
| ----------------------------------------------------------
| PROCEDURE StdArc(verb: GrafVerb; r: Rect;
| startAngle, arcAngle: INTEGER);
|
| Standard QuickDraw arc bottleneck. Pushed-args layout:
| 16(A6) = verb (byte), 12(A6) = rectPtr,
| 10(A6) = startAngle, 8(A6) = arcAngle.
| Called during boot.
StdArc:
        LINK    A6,#-0x4                        | ALLOCATE STACK FRAME
        MOVEM.L D4/D7/A3-A4,-(SP)               | SAVE REGS
        MOVE.B  16(A6),D7                       | GET VERB
        JSR     CheckPic(PC)                    | CheckPic -- sets up A3,A4
        BLE.W   STDARC_NOTPIC                   | branch if not picSave
        MOVE.B  D7,-(SP)                        | push verb for picture record
        JSR     PutPicVerb(PC)                  | record verb in current picture
        MOVEQ.L #0x60,D0                        | SET DEVICE TO 0
        ADD     D7,D0                           | put verb into low nibble (arc opcode)
        MOVE.B  D0,-(SP)                        | push opcode byte
        MOVE.L  12(A6),-(SP)                    | push addr of dst rect
        JSR     PutPicRect(PC)                  | record opcode + rect to picture
        MOVE    10(A6),-(SP)                    | push startAngle
        JSR     PutPicWord(PC)                  | record startAngle to picture
        MOVE    8(A6),-(SP)                     | push arcAngle
        JSR     PutPicWord(PC)                  | record arcAngle to picture
STDARC_NOTPIC:
        MOVE.L  12(A6),A0                       | A0 := dst rect ptr
        MOVE    6(A0),D0                        | get rect.right
        SUB     2(A0),D0                        | ovWd := rect.right - rect.left
        MOVE    D0,-2(A6)                       | save ovWd local
        MOVE    4(A0),D0                        | get rect.bottom
        SUB     (A0),D0                         | ovHt := rect.bottom - rect.top
        MOVE    D0,-4(A6)                       | save ovHt local
        MOVE.L  A0,-(SP)                        | push addr of rect (DrawArc arg)
        TST.B   D7                              | is verb FRAME (= 0)?
        BNE.B   STDARC_NOTFR                    | no, push hollow=FALSE
        MOVE.B  #0x1,-(SP)                      | yes, push hollow=TRUE
        BRA.B   DOIT                            | skip past hollow=FALSE branch
STDARC_NOTFR:
        CLR.B   -(SP)                           | push hollow=FALSE for non-frame verbs
DOIT:
        MOVE.L  -4(A6),-(SP)                    | push ovHt + ovWd as long
        JSR     PushVerb(PC)                    | pc-relative jsr (was raw .short pair)
        MOVE    10(A6),-(SP)                    | push startAngle to DrawArc
        MOVE    8(A6),-(SP)                     | push arcAngle to DrawArc
        JSR     DrawArc(PC)                     | DrawArc(r,hollow,ovWd,ovHt,mode,pat,startAng,arcAng)
        MOVEM.L (SP)+,D4/D7/A3-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS
| Called by: FrameArc, PaintArc, EraseArc, InvertArc, FillArc
CallArc:
        MOVE.L  (SP)+,A0                        | pop return addr
        MOVE.L  (SP)+,D1                        | pop both angles as long
        MOVE.L  (SP)+,A1                        | pop addr of rect
        MOVE.B  D0,-(SP)                        | push verb byte
        MOVE.L  A1,-(SP)                        | push addr of rect
        MOVE.L  D1,-(SP)                        | push both angles
        MOVE.L  A0,-(SP)                        | restore return address
        MOVE.L  (A5),A0                         | A0 := QuickDraw globals
        MOVE.L  (A0),A0                         | A0 := thePort
        MOVE.L  0x68(A0),D0                     | D0 := grafProcs (NIL means use Std)
        LEA     StdArc(PC),A0                   | A0 := StdArc as default
        BEQ.B   CALLARC_USESTD                  | grafProcs NIL? use std proc
        MOVE.L  D0,A0                           | A0 := grafProcs ptr
        MOVE.L  20(A0),A0                       | A0 := arcProc field
CALLARC_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| ----------------------------------------------------------
| PROCEDURE FrameArc(* r: Rect; startAngle, arcAngle: INTEGER *);
FrameArc:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE PaintArc(* r: Rect; startAngle, arcAngle: INTEGER *);
PaintArc:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE EraseArc(* r: Rect; startAngle, arcAngle: INTEGER *);
EraseArc:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE InvertArc(* r: Rect; startAngle, arcAngle: INTEGER *);
InvertArc:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE FillArc(* r: Rect; startAngle, arcAngle: INTEGER;
| pat: Pattern *);
FillArc:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | PUT RETURN ADDR BACK
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT (FILLPAT@$28)
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallArc(PC)                     | SHARE COMMON CODE

| -----------------------------------------------------------
| --> DRAWARC.TEXT (entry)
|
| PROCEDURE DrawArc(dstRect: Rect;
| hollow: BOOLEAN;
| ovalWidth, ovalHeight, mode: INTEGER;
| pat: Pattern;
| startAngle, arcAngle: INTEGER);
|
| Routine to draw solid or hollow Ovals, RoundRects, or Arcs.
| Called by StdArc / StdOval / StdRRect via verb dispatch and
| from RgnBlt's region builder.
| Called during boot.
DrawArc:
        LINK    A6,#-0x12E                      | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | SAVE REGS
        MOVE.L  SP,-0x34(A6)                    | SAVESTK := SP for buffer cleanup
        MOVE.L  A5,-0x106(A6)                   | SAVEA5 := QD globals ptr
        MOVE.L  (A5),A0                         | A0 := grafGlobals
        MOVE.L  (A0),A3                         | A3 := thePort (current grafPort)
        TST     0x42(A3)                        | is pnVis < 0 (pen hidden)?
        BLT.W   DRAWARC_GOHOME                  | YES, QUIT
        MOVE.L  A3,-0x102(A6)                   | PORT := current grafPort
        MOVE    8(A6),D0                        | get arcAngle
        BEQ.W   DRAWARC_GOHOME                  | zero arc, nothing to draw
        BPL.W   POSANG                          | skip if angle already positive
        ADD     D0,10(A6)                       | 10(A6) += D0
        NEG     D0                              | make arcAngle positive
        MOVE    D0,8(A6)                        | update arcAngle param
POSANG:
        CMPI    #0x168,D0                       | is arcAngle < 360?
        SLT     -0x107(A6)                      | set if <: -0x107(A6)
        MOVEQ.L #-0x8,D0                        | mask = ~7 (clear low 3 bits)
        AND     16(A6),D0                       | GET ALL BUT 3 BITS OF MODE
        CMPI    #0x8,D0                         | is mode in 8..15 range?
        BNE.W   DRAWARC_GOHOME                  | NO, QUIT
        MOVE    16(A6),-(SP)                    | PUSH INPUT MODE
        MOVE.L  12(A6),-(SP)                    | PUSH ADDR OF INPUT PATTERN
        JSR     ColorMap(PC)                    | ALTER BY THECOLOR, THEFILTER
        MOVE.L  (SP)+,12(A6)                    | GET (ALTERED) PATTERN
        MOVE    (SP)+,16(A6)                    | GET (ALTERED) MODE
        MOVE.L  -0x102(A6),A5                   | restore A5 to grafPort
        MOVE.L  28(A5),A2                       | GET CLIPRGN HANDLE
        MOVE.L  (A2),A2                         | GET CLIPRGN POINTER
        MOVE.L  24(A5),A3                       | GET VISRGN HANDLE
        MOVE.L  (A3),A3                         | GET VISRGN POINTER
        MOVE.L  24(A6),-(SP)                    | PUSH DSTRECT
        PEA.L     8(A5)                         | push portBits.bounds
        PEA.L     2(A2)                         | PUSH CLIPRGN BBOX
        PEA.L     2(A3)                         | PUSH VISRGN BBOX
        MOVE    #0x4,-(SP)                      | push nRects = 4
        PEA.L     -0x7C(A6)                     | push addr of MINRECT (dst)
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ.W   DRAWARC_GOHOME                  | QUIT IF NO INTERSECT
        CLR.B   -0x108(A6)                      | SKIPFLAG := FALSE
        TST.B   -0x107(A6)                      | is ARCFLAG set (arcAngle < 360)?
        BEQ.W   NOTARC                          | QUIT IF ARC ANGLE = 0
        MOVE    10(A6),D0                       | GET STARTANGLE
        EXT.L    D0                             | SIGN EXTEND FOR DIVIDE
        DIVS    #0x168,D0                       | D0 = D0 /s #0x168
        SWAP    D0                              | GET THE REMAINDER
        TST     D0                              | WAS IT NEGATIVE ?
        BPL.B   STARTOK                         | NO, CONTINUE
        ADDI    #0x168,D0                       | put startAngle in range 0..359
STARTOK:
        MOVE    D0,10(A6)                       | REPLACE INPUT PARAM
        ADD     8(A6),D0                        | CALC STOPANGLE
        CMPI    #0x168,D0                       | IS STOPANGLE >= 360 ?
        BLT.B   STOPOK                          | NO, CONTINUE
        SUBI    #0x168,D0                       | YES, WRAP AROUND MOD 360
STOPOK:
        MOVE    D0,-0x10A(A6)                   | SAVE STOPANGLE FOR LATER
        MOVE.L  24(A6),A0                       | POINT TO DSTRECT
        MOVE    (A0),D0                         | GET DSTTOP
        ADD     4(A0),D0                        | ADD DSTBOTTOM
        ASR     #0x1,D0                         | DIVIDE BY 2
        MOVE    D0,-0x10C(A6)                   | MID VERT := (DSTBOT+DSTTOP)/2
        MOVE    2(A0),D0                        | GET DSTLEFT
        ADD     6(A0),D0                        | ADD DSTRIGHT
        ASR     #0x1,D0                         | DIVIDE BY 2
        MOVE    D0,-0x10E(A6)                   | MID HORIZ := (DSTLEFT+DSTRIGHT)/2
        MOVE    6(A0),D0                        | GET DSTRIGHT
        SUB     2(A0),D0                        | SUBTRACT DSTLEFT
        MOVE    D0,-0x110(A6)                   | WIDTH := DSTRIGHT - DSTLEFT
        MOVE    4(A0),D0                        | GET DSTBOTTOM
        SUB     (A0),D0                         | SUBTRACT DSTTOP
        MOVE    D0,-0x112(A6)                   | HEIGHT := DSTBOTTOM -DSTTOP
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    -0x110(A6),-(SP)                | PUSH WIDTH
        MOVE    -0x112(A6),-(SP)                | PUSH HEIGHT
        JSR     FixRatio(PC)                    | compute aspect = height/width
        MOVE.L  (SP)+,D7                        | SAVE RESULT IN D7
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    10(A6),-(SP)                    | PUSH STARTANG
        JSR     SlopeFromAngle(PC)              | CALC SLOPE1
        MOVE.L  (SP)+,D0                        | POP SLOPE1
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D0,-(SP)                        | PUSH SLOPE1
        MOVE.L  D7,-(SP)                        | PUSH ASPECT RATIO
        JSR     FixMul(PC)                      | slope1 := slope1 * aspect
        MOVE.L  (SP)+,-0x116(A6)                | SLOPE1 := scaled result
        CLR.L   -(SP)                           | MAKE ROOM FOR FCN RESULT
        MOVE    -0x10A(A6),-(SP)                | push stopAngle
        JSR     SlopeFromAngle(PC)              | CALC SLOPE2
        MOVE.L  (SP)+,D0                        | POP SLOPE2
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D0,-(SP)                        | PUSH SLOPE
        MOVE.L  D7,-(SP)                        | PUSH ASPECT RATIO
        JSR     FixMul(PC)                      | slope2 := slope2 * aspect
        MOVE.L  (SP)+,-0x11A(A6)                | SLOPE2 := scaled result
        MOVE    -0x10E(A6),D6                   | D6 := midHoriz
        SWAP    D6                              | shift midHoriz into hi word
        CLR     D6                              | low word zero -> midHoriz*65536
        MOVE    -0x112(A6),D7                   | D7 := height
        LSR     #0x1,D7                         | height div 2
        MOVE    -0x114(A6),D0                   | get low word of slope1 (fract)
        MULU    D7,D0                           | CALC LO PARTIAL PRODUCT
        MOVE.L  D0,-0x11E(A6)                   | LINE1 := lo partial product
        MOVE    -0x116(A6),D0                   | get hi word of slope1
        MULS    D7,D0                           | CALC HI PARTIAL PRODUCT
        ADD     D0,-0x11E(A6)                   | -0x11E(A6) += D0
        MOVE.L  D6,D0                           | COPY MIDHORIZ*64K
        SUB.L   -0x11E(A6),D0                   | midH*64K - slope1*(ht div 2)
        MOVE.L  D0,-0x11E(A6)                   | LINE1 horiz at top of dstRect
        MOVE    -0x118(A6),D0                   | get low word of slope2 (fract)
        MULU    D7,D0                           | CALC LO PARTIAL PRODUCT
        MOVE.L  D0,-0x122(A6)                   | LINE2 := lo partial product
        MOVE    -0x11A(A6),D0                   | get hi word of slope2
        MULS    D7,D0                           | CALC HI PARTIAL PRODUCT
        ADD     D0,-0x122(A6)                   | -0x122(A6) += D0
        SUB.L   -0x122(A6),D6                   | midH*64K - slope2*(ht div 2)
        MOVE.L  D6,-0x122(A6)                   | LINE2 horiz at top of dstRect
        MOVE    10(A6),D0                       | get startAngle
        CMPI    #0xB4,D0                        | is startAngle < 180?
        BGE.B   STOPOK_OK                       | no, use 270 base
        SUBI    #0x5A,D0                        | FLAG1 := startAngle - 90
        BRA.B   STOPOK_CONT                     | skip 270 branch
STOPOK_OK:
        SUBI    #0x10E,D0                       | startAngle - 270
        NEG     D0                              | FLAG1 := 270-STARTANGLE
STOPOK_CONT:
        MOVE    D0,-0x124(A6)                   | SAVE FLAG1
        MOVE    -0x10A(A6),D0                   | GET STOPANGLE
        CMPI    #0xB4,D0                        | IS STOPANGLE >= 180 ?
        BGE.B   STOPOK_OK_2                     | YES, USE 270 BASE
        SUBI    #0x5A,D0                        | FLAG2 := STOPANGLE - 90
        BRA.B   STOPOK_CONT_2                   | CONTINUE
STOPOK_OK_2:
        SUBI.W   #0x10E,D0                      | stopAngle - 270
        NEG.W    D0                             | FLAG2 := 270-stopAngle
STOPOK_CONT_2:
        MOVE    D0,-0x126(A6)                   | SAVE FLAG2
        MOVE    8(A6),D0                        | GET ARCANGLE
        CMPI    #0xB4,D0                        | IS ARCANGLE > 180 ?
        BGT.B   NOTARC                          | SKIP IF ANGLE > 180
        BLT.B   ACUTE                           | DEAL WITH ACUTE ANGLE
        CMPI    #0x5A,10(A6)                    | IS STARTANGLE = 90 ?
        SEQ     -0x108(A6)                      | SKIPFLAG := (startAngle == 90)
        BRA.B   NOTARC                          | CONTINUE TO OVAL INIT
ACUTE:
        MOVE    -0x124(A6),D0                   | GET FLAG1
        OR      -0x126(A6),D0                   | flag1 OR flag2 (combined sign)
        SPL     -0x108(A6)                      | SKIPFLAG := (both flags >= 0)
NOTARC:
        MOVE.L  24(A6),-(SP)                    | push addr of dstRect
        PEA.L     -0xD8(A6)                     | push addr of OUTEROVAL state record
        MOVE    20(A6),-(SP)                    | push ovalWidth
        MOVE    18(A6),-(SP)                    | push ovalHeight
        JSR     InitOval(PC)                    | INITIALIZE OUTER OVAL RECORD
        MOVE    18(A6),D0                       | GET OVALHEIGHT
        ASR     #0x1,D0                         | ovalHeight div 2
        ADD     -0xD8(A6),D0                    | add OUTEROVAL.top
        MOVE    D0,-0xFC(A6)                    | SKIPTOP := top + ovalHt/2
        MOVE.L  24(A6),A0                       | POINT TO DSTRECT
        ADD     4(A0),D0                        | ADD BOTTOM
        SUB     (A0),D0                         | subtract dst.top
        SUB     18(A6),D0                       | SUBTRACT OVALHEIGHT
        MOVE    D0,-0xFE(A6)                    | SKIPBOT := bot - top - ovalHt
        MOVE    #0x7FFF,-0xAE(A6)               | INNEROVAL.top := MAXINT (unused)
        TST.B   22(A6)                          | IS HOLLOWFLAG TRUE ?
        BEQ.B   SOLID                           | NO, SKIP INNER OVAL
        MOVE.L  24(A6),A0                       | POINT TO DSTRECT
        MOVE    (A0),D2                         | get dst.top
        ADD     0x34(A5),D2                     | top += pnSize.v
        MOVE    4(A0),D3                        | get dst.bottom
        SUB     0x34(A5),D3                     | bot -= pnSize.v
        CMP     D3,D2                           | is top >= bot (empty vert)?
        BGE.B   SOLID                           | YES, EMPTY RECT
        MOVE    2(A0),D0                        | get dst.left
        ADD     0x36(A5),D0                     | left += pnSize.h
        MOVE    6(A0),D1                        | get dst.right
        SUB     0x36(A5),D1                     | right -= pnSize.h
        CMP     D1,D0                           | is left >= right (empty horiz)?
        BGE.B   SOLID                           | YES, EMPTY RECT
        MOVE    D0,-0x82(A6)                    | TEMPRECT.left := inset left
        MOVE    D1,-0x7E(A6)                    | TEMPRECT.right := inset right
        MOVE    D2,-0x84(A6)                    | TEMPRECT.top := inset top
        MOVE    D3,-0x80(A6)                    | TEMPRECT.bottom := inset bottom
        PEA.L     -0x84(A6)                     | push addr of inset rect
        PEA.L     -0xAE(A6)                     | push addr of INNEROVAL state record
        MOVE    20(A6),D0                       | get ovalWidth
        SUB     0x36(A5),D0                     | inner width = outer - 1 penWidth
        SUB     0x36(A5),D0                     | inner width = outer - 2*penWidth
        MOVE    D0,-(SP)                        | push inner ovalWidth
        MOVE    18(A6),D0                       | get ovalHeight
        SUB     0x34(A5),D0                     | inner height = outer - 1 penHt
        SUB     0x34(A5),D0                     | inner height = outer - 2*penHt
        MOVE    D0,-(SP)                        | push inner ovalHeight
        JSR     InitOval(PC)                    | INITIALIZE INNER OVAL RECORD
SOLID:
        PEA.L     -0x7C(A6)                     | push addr of MINRECT (shieldRect)
        MOVE.L  8(A5),-(SP)                     | push portBits.bounds.topLeft (delta to global)
        MOVE.L  -0x106(A6),A5                   | restore A5 to QD globals
        JSR     DrawControls(PC)                | HIDE CURSOR IF IT INTERSECTS
        MOVE.L  -0x102(A6),A5                   | restore A5 to grafPort
        MOVEM   -0x7C(A6),D1-D4                 | load minRect into D1-D4
        MOVE    #-0x7FFF,-10(A6)                | STATEA.thisV := -32767 (init)
        MOVE    #-0x7FFF,-0x22(A6)              | STATEB.thisV := -32767 (init)
        MOVE    #0x7FFF,-8(A6)                  | STATEA.nextV := 32767 (sentinel)
        MOVE    #0x7FFF,-0x20(A6)               | STATEB.nextV := 32767 (sentinel)
        MOVE    -0x7A(A6),D2                    | get minRect.left
        SUB     10(A5),D2                       | convert to global coords
        ANDI    #-0x10,D2                       | truncate to multiple of 16
        ADD     10(A5),D2                       | convert back to local
        MOVE    D2,-0xEE(A6)                    | BUFLEFT := aligned left
        MOVE    -0x76(A6),D0                    | get minRect.right
        SUB     D2,D0                           | CALC MAXH-BUFLEFT
        LSR     #0x5,D0                         | div by 32 -> longs count
        MOVE    D0,-0xF0(A6)                    | BUFSIZE := count of longs - 1
CLRMASK:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR ONE LONG
        DBRA    D0,CLRMASK                      | LOOP TILL DONE
        MOVE.L  SP,-0xEC(A6)                    | MASKBUF := SP (composite-mask buffer)
        CLR     -0xE0(A6)                       | RECTFLAG := 0 (both regions rect)
        CMPI    #0xA,(A2)                       | is clipRgn rectangular?
        BEQ.B   CLRMASK_OK                      | YES, CONTINUE
        ADDQ.W  #0x2,-0xE0(A6)                  | -0xE0(A6) += 0x2
        MOVE.L  A2,A0                           | POINT TO CLIPRGN
        LEA.L     -24(A6),A1                    | A1 := STATEA addr
        MOVE    -0x7A(A6),D0                    | D0 := minRect.left (minH)
        MOVE    -0x76(A6),D1                    | D1 := minRect.right (maxH)
        MOVE    -0xEE(A6),D2                    | D2 := BUFLEFT
        JSR     InitRgn(PC)                     | init STATEA, alloc scan buffer for clipRgn
CLRMASK_OK:
        CMPI    #0xA,(A3)                       | is visRgn rectangular?
        BEQ.B   CLRMASK_EXIT                    | YES, CONTINUE
        ADDQ.W  #0x4,-0xE0(A6)                  | -0xE0(A6) += 0x4
        MOVE.L  A3,A0                           | POINT TO VISRGN
        LEA.L     -0x30(A6),A1                  | A1 := STATEB addr
        MOVE    -0x7A(A6),D0                    | D0 := minRect.left (minH)
        MOVE    -0x76(A6),D1                    | D1 := minRect.right (maxH)
        MOVE    -0xEE(A6),D2                    | D2 := BUFLEFT
        JSR     InitRgn(PC)                     | init STATEB, alloc scan buffer for visRgn
CLRMASK_EXIT:
        TST     -0xE0(A6)                       | are both regions rectangular?
        BNE.B   CLRMASK_SKIP                    | NO, CONTNUE
        MOVE.L  -0xEC(A6),A0                    | A0 := MASKBUF
        MOVE    -0x7A(A6),D3                    | D3 := minRect.left
        SUB     -0xEE(A6),D3                    | left relative to BUFLEFT
        MOVE    -0x76(A6),D4                    | D4 := minRect.right
        SUB     -0xEE(A6),D4                    | right relative to BUFLEFT
        JSR     XorSlab(PC)                     | AND XOR BETWEEN THEM
CLRMASK_SKIP:
        MOVE    -0x7C(A6),D1                    | get minRect.top
        SUB     8(A5),D1                        | convert top to global
        MULU    6(A5),D1                        | multiply by dst rowBytes
        ADD.L   2(A5),D1                        | add baseAddr -> dst byte addr
        SUB     10(A5),D2                       | BUFLEFT to global
        LSR     #0x3,D2                         | BUFLEFT div 8 (byte offset)
        EXT.L    D2                             | CLR HI WORD
        ADD.L   D2,D1                           | ADD HORIZ BYTE OFFSET
        MOVE.L  D1,-0xF4(A6)                    | DSTLEFT := starting dst byte addr
        CLR.L   D7                              | SAY NOT INVERTED
        MOVE    16(A6),D2                       | GET MODE
        BCLR    #0x2,D2                         | test+clear invert bit
        BEQ.B   CLRMASK_SKIP_2                  | SKIP IF NOT INVERTED
        NOT.L   D7                              | INVERTED; D7 GETS ALL 1'S
CLRMASK_SKIP_2:
        JSR     SlabMode(PC)                    | get mode case-jump in A0
        MOVE.L  A0,-0xFA(A6)                    | MODECASE := slab-mode dispatch
        MOVE    10(A5),D2                       | get global-local left offset
        MOVE.L  12(A6),A0                       | POINT TO BYTE WIDE PATTERN
        LEA.L     -0x74(A6),A1                  | A1 := EXPAT (16-long expanded pat)
        MOVE.L  -0x106(A6),A5                   | A5 := QD globals for PatExpand
        JSR     PatExpand(PC)                   | EXPAND 8 BYTE PATTERN TO 16 LONGS
        MOVE.L  -0x102(A6),A5                   | A5 := grafPort
        MOVEQ.L #0xF,D7                         | mask = 15 (mod 16)
        AND     -0x7C(A6),D7                    | D7 := minRect.top mod 16
        LSL     #0x2,D7                         | x4 (longs in expanded pat)
        MOVE.L  -0x74(A6,D7.W),D6               | D6 = pattern word from expanded table
        MOVE    -0xEE(A6),D1                    | D1 := BUFLEFT
        SUB     D1,-0x7A(A6)                    | minRect.left -= BUFLEFT
        SUB     D1,-0x76(A6)                    | minRect.right -= BUFLEFT
        SUB     D1,-0xD2(A6)                    | OUTEROVAL.leftEdge -= BUFLEFT
        SUB     D1,-0xCE(A6)                    | OUTEROVAL.rightEdge -= BUFLEFT
        SUB     D1,-0xA8(A6)                    | INNEROVAL.leftEdge -= BUFLEFT
        SUB     D1,-0xA4(A6)                    | INNEROVAL.rightEdge -= BUFLEFT
        SUB     D1,-0x11E(A6)                   | LINE1 -= BUFLEFT
        SUB     D1,-0x122(A6)                   | LINE2 -= BUFLEFT
        MOVE    -0xD8(A6),-0xF6(A6)             | vert := OUTEROVAL.top (start)
DRAWARC_NEXTROW:
        MOVE    -0xF6(A6),D0                    | get current vert
        CMP     -0xFC(A6),D0                    | is vert < SKIPTOP?
        BLT.B   YESBUMP                         | YES, OK TO BUMP OVALS
        CMP     -0xFE(A6),D0                    | is vert < SKIPBOT?
        BLT.B   NOBUMP                          | NO, SKIP BUMPING
YESBUMP:
        PEA.L     -0xD8(A6)                     | push addr of OUTEROVAL state
        MOVE    D0,-(SP)                        | push current vert
        JSR     BumpOval(PC)                    | BUMP IT TO NEXT SCANLINE
        PEA.L     -0xAE(A6)                     | push addr of INNEROVAL state
        MOVE    D0,-(SP)                        | push current vert
        JSR     BumpOval(PC)                    | BUMP IT TO NEXT SCANLINE

| --------------------------------------------------
| ADJUST ARC STUFF AS WE CROSS THE MIDDLE VERTICALLY
| Called during boot.
NOBUMP:
        CMP     -0x10C(A6),D0                   | is current vert == midVert?
        BNE.B   ACUTE1_SKIP_2                   | NO, CONTINUE
        TST.B   -0x107(A6)                      | ARE WE DOING AN ARC ?
        BEQ.B   ACUTE1_SKIP_2                   | NO, SKIP
        NEG     -0x124(A6)                      | YES, INVERT FLAGS AS WE CROSS
        NEG     -0x126(A6)                      | INVERT FLAG2
        CLR.B   -0x108(A6)                      | RESET SKIPFLAG
        MOVE    8(A6),D0                        | GET ARCANGLE
        CMPI    #0xB4,D0                        | IS ARCANGLE > 180 ?
        BGT.B   ACUTE1_SKIP                     | SKIP IF ANGLE > 180
        BLT.B   ACUTE1                          | DEAL WITH ACUTE ANGLE
        CMPI    #0x10E,10(A6)                   | IS STARTANGLE = 270 ?
        BNE.B   ACUTE1_SKIP                     | NO, CONTINUE
        BRA.W   DRAWARC_DONE                    | YES, WE'RE ALL DONE
ACUTE1:
        MOVE    -0x124(A6),D0                   | GET FLAG1
        OR      -0x126(A6),D0                   | flag1 OR flag2 (combined sign)
        BPL.W   DRAWARC_DONE                    | QUIT IF BOTH FLAG1 AND FLAG2>=0

| OBTUSE1
| NOW SWAP THE ROLES OF LINE1 AND LINE2 AS THEY CROSS THE MIDDLE
ACUTE1_SKIP:
        MOVE    -0x124(A6),D0                   | SWAP FLAG1 AND FLAG2
        MOVE    -0x126(A6),-0x124(A6)           | FLAG1 := OLD FLAG2
        MOVE    D0,-0x126(A6)                   | FLAG2 := OLD FLAG1
        MOVE.L  -0x11E(A6),D0                   | SWAP LINE1 AND LINE2
        MOVE.L  -0x122(A6),-0x11E(A6)           | LINE1 := OLD LINE2
        MOVE.L  D0,-0x122(A6)                   | LINE2 := OLD LINE1
        MOVE.L  -0x116(A6),D0                   | SWAP SLOPE1 AND SLOPE2
        MOVE.L  -0x11A(A6),-0x116(A6)           | SLOPE1 := OLD SLOPE2
        MOVE.L  D0,-0x11A(A6)                   | SLOPE2 := OLD SLOPE1
        MOVE.W   -246(FP),D0                    | reload current vert
ACUTE1_SKIP_2:
        CMP     -0x7C(A6),D0                    | is vert < minRect.top?
        BLT.W   NODRAW                          | YES, DON'T DRAW
        TST.B   -0x108(A6)                      | is SKIPFLAG set?
        BNE.W   DOSLAB_SKIP                     | YES, SKIP
        JSR     MASKUPDATE(PC)                  | update composite mask buffer
        TST.B   -0x107(A6)                      | is ARCFLAG set?
        BNE.B   NOMASK_OK                       | YES, DON'T BOTHER WITH MASK
        MOVE    -0xF6(A6),D0                    | get current vert
        CMP     -0xAE(A6),D0                    | is vert < INNEROVAL.top?
        BLT.W   SOVAL                           | NO, TREAT AS SOLID OVAL
        CMP     -0xAC(A6),D0                    | is vert >= INNEROVAL.bot?
        BGE.W   SOVAL                           | NO, TREAT AS SOLID OVAL
        BRA.W   HOVAL                           | YES, PROCESS HOLLOW OVAL

| ----------------------------------------------------------
| NOMASK_OK
NOMASK_OK:
        MOVE    -0xD2(A6),D1                    | D1 := OUTER LEFTEDGE
        TST     -0x124(A6)                      | IS LINE1 ACTIVE ?
        BPL.B   NOMASK_SKIP                     | NO, SKIP LINE1 CLIP
        CMP     -0x11E(A6),D1                   | IS LEFTEDGE < LINE1 ?
        BGE.B   NOMASK_SKIP                     | NO, KEEP LEFTEDGE
        MOVE    -0x11E(A6),D1                   | YES, CLIP TO LINE1
NOMASK_SKIP:
        MOVE    D1,-0x128(A6)                   | SAVE OUTERLEFT
        MOVE    -0xCE(A6),D2                    | D2 := OUTER RIGHTEDGE
        TST     -0x126(A6)                      | IS LINE2 ACTIVE ?
        BPL.B   NOMASK_SKIP_2                   | NO, SKIP LINE2 CLIP
        CMP     -0x122(A6),D2                   | IS RIGHTEDGE > LINE2 ?
        BLE.B   NOMASK_SKIP_2                   | NO, KEEP RIGHTEDGE
        MOVE    -0x122(A6),D2                   | YES, CLIP TO LINE2
NOMASK_SKIP_2:
        MOVE.W   D2,-298(FP)                    | SAVE OUTERRIGHT
        MOVE    -0xF6(A6),D0                    | get current vert
        CMP     -0xAE(A6),D0                    | is vert < INNEROVAL.top?
        BLT.W   SARC                            | NO, PROCESS SOLID ARC
        CMP     -0xAC(A6),D0                    | is vert >= INNEROVAL.bot?
        BGE.W   SARC                            | NO, PROCESS SOLID ARC
        MOVE    -0xA8(A6),D0                    | GET INNER LEFTEDGE
        TST     -0x126(A6)                      | IS LINE2 ACTIVE ?
        BPL.B   NOMASK_SKIP_3                   | NO, SKIP LINE2 CLIP
        CMP     -0x122(A6),D0                   | IS LEFTEDGE > LINE2 ?
        BLE.B   NOMASK_SKIP_3                   | NO, KEEP LEFTEDGE
        MOVE    -0x122(A6),D0                   | YES, CLIP TO LINE2
NOMASK_SKIP_3:
        MOVE    D0,-0x12C(A6)                   | SAVE INNERLEFT
        MOVE    -0xA4(A6),D0                    | GET INNER RIGHTEDGE
        TST     -0x124(A6)                      | IS LINE1 ACTIVE ?
        BPL.B   NOMASK_SKIP_4                   | NO, SKIP LINE1 CLIP
        CMP     -0x11E(A6),D0                   | IS RIGHTEDGE < LINE1 ?
        BGE.B   NOMASK_SKIP_4                   | NO, KEEP RIGHTEDGE
        MOVE    -0x11E(A6),D0                   | YES, CLIP TO LINE1

NOMASK_SKIP_4:
        MOVE    D0,-0x12E(A6)                   | SAVE INNERRIGHT
        CMP     D2,D1                           | IS OUTERLEFT < OUTERRIGHT ?
        BGE.B   NOMASK_NO                       | NO, TRY OBTUSE CASE
        MOVE    -0x12C(A6),D2                   | D2 := INNERLEFT
        BSR.B   ONESLAB                         | DRAW LEFT SLAB
        MOVE    -0x12E(A6),D1                   | D1 := INNERRIGHT
        MOVE    -0x12A(A6),D2                   | D2 := OUTERRIGHT
        BRA.W   DOSLAB                          | DRAW RIGHT SLAB
NOMASK_NO:
        MOVE    -0x124(A6),D0                   | GET FLAG1
        AND     -0x126(A6),D0                   | ARE BOTH LINES ACTIVE ?
        BPL.W   DOSLAB_SKIP                     | NO, CONTINUE
        CMPI    #0xB4,8(A6)                     | IS ARCANGLE > 180 ?
        BLE.W   DOSLAB_SKIP                     | NO, CONTINUE
        CMP     -0x12C(A6),D2                   | IS INNERLEFT=OUTERRIGHT?
        BNE.B   NOMASK_NO_2                     | no, try other obtuse case
        MOVE    -0xA8(A6),D2                    | USE INNER LEFTEDGE INSTEAD
        BRA.W   NOMASK_CONT                     | draw third slab
NOMASK_NO_2:
        MOVE    -0x128(A6),D0                   | get OUTERLEFT
        CMP     -0x12E(A6),D0                   | is innerRight == outerLeft?
        BNE.B   NOMASK_NO_3                     | NO, CONTINUE
        MOVE    -0xA4(A6),D1                    | D1 := INNEROVAL.rightEdge
        MOVE    -0x12A(A6),D2                   | D2 := OUTERRIGHT
NOMASK_CONT:
        BSR.B   ONESLAB                         | draw third slab for obtuse arc
NOMASK_NO_3:
        MOVE    -0xD2(A6),D1                    | D1 := OUTER LEFTEDGE
        MOVE    -0x12C(A6),D2                   | D2 := INNERLEFT
        BSR.B   ONESLAB                         | DRAW LEFT SLAB
        MOVE    -0x12E(A6),D1                   | D1 := INNERRIGHT
        MOVE    -0xCE(A6),D2                    | D2 := OUTER RIGHTEDGE
        BRA.B   DOSLAB                          | draw right slab via DOSLAB
ONESLAB:
        MOVE.L  -0xFA(A6),A0                    | STRIP BUFFER
        MOVE.L  -0xF4(A6),A1                    | A1 := DSTLEFT
        MOVE.L  -0xEC(A6),A2                    | A2 := MASKBUF
        LEA.L     -0x7C(A6),A3                  | A3 := MINRECT addr
        JMP     DrawSlab(PC)                    | draw a horizontal slab
SARC:                                           | jump via A0
        CMP     D2,D1                           | IS OUTERLEFT < OUTERRIGHT ?
        BLT.B   DOSLAB                          | YES, DO ONE SLAB BETWEEN THEM
        MOVE    -0x124(A6),D0                   | get FLAG1
        AND     -0x126(A6),D0                   | AND FLAG2 (both active?)
        BPL.W   DOSLAB_SKIP                     | NO, CONTINUE
        CMPI    #0xB4,8(A6)                     | is arcAngle > 180?
        BLE.B   DOSLAB_SKIP                     | NO, CONTINUE
        MOVE    -0xD2(A6),D1                    | D1 := OUTEROVAL.leftEdge
        BSR.B   ONESLAB                         | draw left obtuse-arc slab
        MOVE    -0x128(A6),D1                   | D1 := OUTERLEFT
        MOVE    -0xCE(A6),D2                    | D2 := OUTEROVAL.rightEdge
        BRA.B   DOSLAB                          | draw right obtuse-arc slab

| ----------------------------------------------------------
| HOVAL
| Called during boot.
HOVAL:
        MOVE    -0xD2(A6),D1                    | D1 := OUTER LEFTEDGE
        MOVE    -0xA8(A6),D2                    | D2 := INNER LEFTEDGE
        BSR.B   ONESLAB                         | DRAW HORIZ SLAB BETWEEN THEM
        MOVE    -0xA4(A6),D1                    | D1 := INNER RIGHTEDGE
        MOVE    -0xCE(A6),D2                    | D2 := OUTER RIGHTEDGE
        BSR.B   ONESLAB                         | DRAW HORIZ SLAB BETWEEN THEM
        BRA.B   DOSLAB_SKIP                     | SKIP TO NEXT ROW
SOVAL:
        MOVE    -0xD2(A6),D1                    | D1 := OUTEROVAL.leftEdge
        MOVE    -0xCE(A6),D2                    | D2 := OUTEROVAL.rightEdge
DOSLAB:
        BSR.B   ONESLAB                         | DRAW HORIZ SLAB BETWEEN THEM
DOSLAB_SKIP:
        ADDQ.W  #0x4,D7                         | advance pattern index by 4
        ANDI    #0x3F,D7                        | wrap to 64 bytes (16 longs)
        MOVE.L  -0x74(A6,D7.W),D6               | D6 = pattern word from expanded table
        MOVE    6(A5),D0                        | get dst rowBytes
        EXT.L    D0                             | MAKE IT LONG
        ADD.L   D0,-0xF4(A6)                    | DSTLEFT += rowBytes (next row)
NODRAW:
        MOVE.L  -0x116(A6),D0                   | BUMP LINE1 AND LINE2
        ADD.L   D0,-0x11E(A6)                   | BUMP LINE1 BY SLOPE1
        MOVE.L  -0x11A(A6),D0                   | GET SLOPE2
        ADD.L   D0,-0x122(A6)                   | BUMP LINE2 BY SLOPE2
        ADDQ.W  #0x1,-0xF6(A6)                  | advance current vert by 1
        MOVE    -0xF6(A6),D0                    | reload current vert
        CMP     -0x78(A6),D0                    | is vert < minRect.bottom?
        BLT.W   DRAWARC_NEXTROW                 | NO, LOOP FOR MORE
DRAWARC_DONE:
        MOVE.L  -0x106(A6),A5                   | restore A5 to QD globals
        JSR     FMQD_ShowCursor(PC)             | RESTORE CURSOR
DRAWARC_GOHOME:
        MOVE.L  -0x34(A6),SP                    | restore SP from SAVESTK (free buffer)
        MOVEM.L (SP)+,D0-D7/A1-A5               | RESTORE REGISTERS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0x14,SP                        | strip 20 bytes of params
        JMP     (A0)                            | RTS
MASKUPDATE:
        MOVE    -0xE0(A6),D0                    | D0 = mode index
| Computed-jump dispatch via 2-byte offset table (see DrawLine.s DRAWLINE_ROWLOOP).
        .short  0x303B, 0x0006                  | MOVE.W MASKUPDATE_TBL(PC,D0.W),D0
        .short  0x4EFB, 0x0002                  | JMP MASKUPDATE_TBL(PC,D0.W)
MASKUPDATE_TBL:                                 | offset table (4 entries)
        .short  0x0008                          | mode 0 disp
        .short  0x000A                          | mode 2 disp
        ORI.B   #0x32,(A6)+                     | (A6)+ |= 0x32
        RTS                                     | both rect: nothing to do
        MOVE    -0xF6(A6),D0                    | A: get current vert
        LEA.L     -24(A6),A1                    | A1 := STATEA addr
        JSR     SeekRgn(PC)                     | advance STATEA scanbuf to vert
        MOVE.L  8(A1),-0xEC(A6)                 | MASKBUF := STATEA.scanBuf
        RTS                                     | return: only A non-rect
        MOVE    -0xF6(A6),D0                    | B: get current vert
        LEA.L     -0x30(A6),A1                  | A1 := STATEB addr
        JSR     SeekRgn(PC)                     | advance STATEB scanbuf to vert
        MOVE.L  8(A1),-0xEC(A6)                 | MASKBUF := STATEB.scanBuf
        RTS                                     | return: only B non-rect
        MOVE    -0xF6(A6),D0                    | AB: get current vert
        LEA.L     -24(A6),A1                    | A1 := STATEA addr
        JSR     SeekRgn(PC)                     | advance STATEA scanbuf
        LEA.L     -0x30(A6),A1                  | A1 := STATEB addr
        JSR     SeekRgn(PC)                     | advance STATEB scanbuf
        MOVE.L  -16(A6),A0                      | A0 := STATEA.scanBuf
        MOVE.L  -0x28(A6),A1                    | A1 := STATEB.scanBuf
        MOVE.L  -0xEC(A6),A2                    | A2 := MASKBUF
        MOVE    -0xF0(A6),D1                    | D1 := BUFSIZE
MASKUPDATE_LOOP:
        MOVE.L  (A0)+,D0                        | get next STATEA long
        AND.L   (A1)+,D0                        | AND with STATEB long (intersect)
        MOVE.L  D0,(A2)+                        | store into MASKBUF
        DBRA    D1,MASKUPDATE_LOOP              | loop for all longs in scan
        RTS                                     | return: AB intersection done

| ----------------------------------------------------------
| .PROC InitOval,4
|
| PROCEDURE InitOval(dstRect: Rect; VAR oval: OvalRec;
| ovalWidth, ovalHeight: INTEGER);
|
| Initialize an oval state record to fit the given rectangle.
| Classic uses Pascal stack-based interface (params at A6 offsets);
| Plus refactored to register-based (A0=rect, A1=oval, D1=ht, D2=wd).
| Called by DrawArc, StdOval/PutOval region build, and StdRRect.
| Called during boot.
InitOval:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D0-A5,-(SP)                     | save all regs
        MOVE.L  16(A6),A0                       | A0 := dstRect
        MOVE.L  12(A6),A1                       | A1 := ovalRec
        MOVE    (A0),(A1)                       | INIT OVAL TOP TO DSTRECT TOP
        MOVE    4(A0),2(A1)                     | INIT OVAL BOTTOM TO DSTRECT BOT
        MOVE    10(A6),D2                       | D2 := ovalWidth
        BGE.B   OK1                             | NO, CONTINUE if non-negative
        CLR     D2                              | YES, PIN width TO 0
OK1:
        MOVE    8(A6),D1                        | D1 := ovalHeight
        BGE.B   OK1_NO                          | NO, CONTINUE if non-negative
        CLR     D1                              | YES, PIN height TO 0

| OK2

| CHECK OVALWIDTH AND OVALHEIGHT, TRIM IF BIGGER THAN DSTRECT
| Called during boot.
OK1_NO:
        MOVE    6(A0),D0                        | GET DSTRECT RIGHT
        SUB     2(A0),D0                        | CALC DSTRECT WIDTH
        CMP     D0,D2                           | IS OVALWIDTH > DSTWIDTH ?
        BLE.B   INITOVAL_OK3                    | NO,CONTINUE
        MOVE    D0,D2                           | YES, OVALWIDTH:= DSTWIDTH
INITOVAL_OK3:
        MOVE    4(A0),D0                        | get rect.bottom
        SUB     (A0),D0                         | dstHeight = bottom - top
        CMP     D0,D1                           | IS OVALHEIGHT > DSTHEIGHT ?
        BLE.B   INITOVAL_OK3_NO                 | NO,CONTINUE
        MOVE    D0,D1                           | YES, OVALHEIGHT:= DSTHEIGHT
INITOVAL_OK3_NO:
        MOVE    6(A0),10(A1)                    | rightEdge.int := dst.right
        CLR     12(A1)                          | rightEdge.fract := 0
        MOVE    2(A0),6(A1)                     | leftEdge.int := dst.left
        CLR     8(A1)                           | leftEdge.fract := 0
        MOVE    D2,D0                           | GET OVAL WIDTH
        SWAP    D0                              | PUT IN HI WORD
        CLR     D0                              | CLEAR LO WORD FOR FIXED POINT
        LSR.L   #0x1,D0                         | ovalWidth*65536 / 2
        ADD.L   D0,6(A1)                        | leftEdge += ovalWd/2
        SUB.L   D0,10(A1)                       | rightEdge -= ovalWd/2
        ADDI.L  #0x8000,10(A1)                  | bias rightEdge by +0.5 (fixed)
        MOVEQ.L #0x1,D0                         | D0 := 1 (sign-extended)
        SUB     D1,D0                           | 1 - height
        MOVE    D0,4(A1)                        | OVALY:=1-HEIGHT
        MOVE    D1,D0                           | GET HEIGHT
        EXT.L    D0                             | CLEAR OUT HI WORD
        ADD.L   D0,D0                           | CALC 2*HEIGHT
        SUBQ.L  #0x1,D0                         | 2*height - 1
        MOVE.L  D0,14(A1)                       | RSQYSQ:=2*HEIGHT-1
        CLR.L   18(A1)                          | SQUARE hi := 0
        CLR.L   22(A1)                          | SQUARE:=0
        CLR.L   -(SP)                           | GET READY FOR FUNCTION RESULT
        MOVE    D1,-(SP)                        | PUSH NUMERATOR=HEIGHT
        MOVE    D2,-(SP)                        | PUSH DENOMINATOR=WIDTH
        JSR     FixRatio(PC)                    | compute fixed height/width
        MOVE.L  (SP),-(SP)                      | DUPLICATE RESULT
        PEA.L     26(A1)                        | PUSH ADDR FOR RESULT
        JSR     LongMul(PC)                     | ODDNUM := (h/w)^2 (64-bit)
        MOVE.L  30(A1),D0                       | get lo long of ODDNUM
        ADD.L   D0,D0                           | DOUBLE IT
        MOVE.L  D0,0x26(A1)                     | ODDBUMP.lo := ODDNUM*2 lo
        MOVE.L  26(A1),D0                       | get hi long of ODDNUM
        ADDX.L  D0,D0                           | D0 += D0 (with X bit)
        MOVE.L  D0,0x22(A1)                     | ODDBUMP.hi := ODDNUM*2 hi
        MOVEM.L (SP)+,D0-A5                     | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS
BumpOval:
        LINK    A6,#0x0                         | set up stack frame (no locals)
        MOVEM.L D0-A5,-(SP)                     | save all registers
        MOVE.L  10(A6),A2                       | A2 := ovalRec ptr
        MOVE    8(A6),D0                        | get vert param
        CMP     (A2),D0                         | jump via A0
        BLT.W   BUMPOVAL_GOHOME                 | YES, IGNORE
        CMP     2(A2),D0                        | is vert >= ovalBot?
        BGE.W   BUMPOVAL_GOHOME                 | YES, IGNORE
        MOVE.L  #0x8000,D3                      | D3 := fixed 0.5 ($00008000)
        MOVE.L  10(A2),D2                       | D2 := RIGHTEDGE
        MOVE.L  6(A2),D1                        | D1 := LEFTEDGE
        MOVE.L  14(A2),D4                       | D4 := RSQYSQ
        BRA.B   BUMPOVAL_WHILE1                 | enter test (while square < RSQYSQ)
BUMPOVAL_MORE1:
        ADD.L   D3,D2                           | rightEdge += 0.5
        SUB.L   D3,D1                           | leftEdge -= 0.5 (oval bigger)
        LEA.L     0x22(A2),A0                   | A0 := ODDBUMP+8 (lo long end)
        LEA.L     26(A2),A1                     | A1 := ODDNUM+4 (lo long end)
        SUB     D0,D0                           | clear X flag (D0 already 0)
        ADDX.L  -(A0),-(A1)                     | ODDNUM.lo += ODDBUMP.lo
        ADDX.L  -(A0),-(A1)                     | ODDNUM.hi += ODDBUMP.hi (with X)
        LEA.L     0x2A(A2),A0                   | A0 := ODDNUM+8 (lo long end)
        LEA.L     0x22(A2),A1                   | A1 := SQUARE+8 (lo long end)
        SUB     D0,D0                           | clear X flag
        ADDX.L  -(A0),-(A1)                     | SQUARE.lo += ODDNUM.lo
        ADDX.L  -(A0),-(A1)                     | SQUARE.hi += ODDNUM.hi (with X)
BUMPOVAL_WHILE1:                                | jump via A0
        CMP.L   18(A2),D4                       | is RSQYSQ > SQUARE.hi?
        BGT.B   BUMPOVAL_MORE1                  | yes, expand more
        BRA.B   BUMPOVAL_WHILE2                 | GO TO LOOP START
BUMPOVAL_MORE2:                                 | jump via A0
        SUB.L   D3,D2                           | rightEdge -= 0.5 (oval smaller)
        ADD.L   D3,D1                           | leftEdge += 0.5
        LEA.L     0x2A(A2),A0                   | A0 := ODDNUM+8 (lo long end)
        LEA.L     0x22(A2),A1                   | A1 := SQUARE+8 (lo long end)
        SUB     D0,D0                           | clear X flag
        SUBX.L  -(A0),-(A1)                     | SQUARE.lo -= ODDNUM.lo
        SUBX.L  -(A0),-(A1)                     | SQUARE.hi -= ODDNUM.hi (with X)
        LEA.L     0x22(A2),A0                   | A0 := ODDBUMP+8 (lo long end)
        LEA.L     26(A2),A1                     | A1 := ODDNUM+4 (lo long end)
        SUB     D0,D0                           | clear X flag
        SUBX.L  -(A0),-(A1)                     | ODDNUM.lo -= ODDBUMP.lo
        SUBX.L  -(A0),-(A1)                     | ODDNUM.hi -= ODDBUMP.hi (with X)
BUMPOVAL_WHILE2:
        CMP.L   18(A2),D4                       | is RSQYSQ < SQUARE.hi?
        BLT.B   BUMPOVAL_MORE2                  | YES, LOOP
        MOVE.L  D2,10(A2)                       | rightEdge := D2 (final)
        MOVE.L  D1,6(A2)                        | leftEdge := D1 (final)
        MOVE    4(A2),D0                        | get OVALY
        ADDQ.W  #0x1,D0                         | ovalY+1
        EXT.L    D0                             | SIGN EXTEND TO A LONG
        ASL.L   #0x2,D0                         | (ovalY+1)*4
        SUB.L   D0,14(A2)                       | RSQYSQ -= 4*(ovalY+1)
        ADDQ.W  #0x2,4(A2)                      | OVALY += 2 (next scanline)
BUMPOVAL_GOHOME:
        MOVEM.L (SP)+,D0-A5                     | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | RTS

| ----------------------------------------------------------------
| FUNCTION SlopeFromAngle(angle: INTEGER): Fixed;
| calculate the fixed point slope of a line, DH/DV = -65536 * Tan(angle).
| Input angle is treated MOD 180.
SlopeFromAngle:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE    (SP)+,D0                        | get angle param
        EXT.L    D0                             | sign-extend for DIVS
        DIVS    #0xB4,D0                        | angle MOD 180 (rem in hi)
        SWAP    D0                              | get remainder
        TST     D0                              | was remainder negative?
        BPL.B   SLOPEFROMANGLE_CONT             | no, continue
        ADDI    #0xB4,D0                        | yes, put in 0..179 range
SLOPEFROMANGLE_CONT:
        LSL     #0x2,D0                         | x4 (long entries in tbl)
        CMPI    #0x168,D0                       | is angle*4 <= 360?
        BLE.B   SLOPEFROMANGLE_CONT_2           | yes, use direct lookup
        SUBI    #0x2D0,D0                       | subtract 720 (mirror)
        NEG     D0                              | reflect for 90..180 half
        .short  0x2EBB, 0x000C                  | MOVE.L SLOPETBL(PC,D0.W),(SP) disp=12
        JMP     (A0)                            | return with positive slope
SLOPEFROMANGLE_CONT_2:
        .short  0x2EBB, 0x0006                  | MOVE.L SLOPETBL(PC,D0.W),(SP) disp=6
        NEG.L   (SP)                            | (SP) = -(SP) (negate for mirrored half)
        JMP     (A0)                            | return with negative slope
SLOPETBL:                                       | SLOPETBL: tan(angle)*65536, angle 0..90
        .long   0x00000000                      | tan(0 deg) * 65536
        .long   0x00000478                      | tan(1 deg) * 65536
        .long   0x000008F1                      | tan(2 deg) * 65536
        .long   0x00000D6B                      | tan(3 deg) * 65536
        .long   0x000011E7                      | tan(4 deg) * 65536
        .long   0x00001666                      | tan(5 deg) * 65536
        .long   0x00001AE8                      | tan(6 deg) * 65536
        .long   0x00001F6F                      | tan(7 deg) * 65536
        .long   0x000023FA                      | tan(8 deg) * 65536
        .long   0x0000288C                      | tan(9 deg) * 65536
        .long   0x00002D24                      | tan(10 deg) * 65536
        .long   0x000031C3                      | tan(11 deg) * 65536
        .long   0x0000366A                      | tan(12 deg) * 65536
        .long   0x00003B1A                      | tan(13 deg) * 65536
        .long   0x00003FD4                      | tan(14 deg) * 65536
        .long   0x00004498                      | tan(15 deg) * 65536
        .long   0x00004968                      | tan(16 deg) * 65536
        .long   0x00004E44                      | tan(17 deg) * 65536
        .long   0x0000532E                      | tan(18 deg) * 65536
        .long   0x00005826                      | tan(19 deg) * 65536
        .long   0x00005D2D                      | tan(20 deg) * 65536
        .long   0x00006245                      | tan(21 deg) * 65536
        .long   0x0000676E                      | tan(22 deg) * 65536
        .long   0x00006CAA                      | tan(23 deg) * 65536
        .long   0x000071FB                      | tan(24 deg) * 65536
        .long   0x00007760                      | tan(25 deg) * 65536
        .long   0x00007CDC                      | tan(26 deg) * 65536
        .long   0x00008270                      | tan(27 deg) * 65536
        .long   0x0000881E                      | tan(28 deg) * 65536
        .long   0x00008DE7                      | tan(29 deg) * 65536
        .long   0x000093CD                      | tan(30 deg) * 65536
        .long   0x000099D2                      | tan(31 deg) * 65536
        .long   0x00009FF7                      | tan(32 deg) * 65536
        .long   0x0000A640                      | tan(33 deg) * 65536
        .long   0x0000ACAD                      | tan(34 deg) * 65536
        .long   0x0000B341                      | tan(35 deg) * 65536
        .long   0x0000B9FF                      | tan(36 deg) * 65536
        .long   0x0000C0E9                      | tan(37 deg) * 65536
        .long   0x0000C802                      | tan(38 deg) * 65536
        .long   0x0000CF4E                      | tan(39 deg) * 65536
        .long   0x0000D6CF                      | tan(40 deg) * 65536
        .long   0x0000DE8A                      | tan(41 deg) * 65536
        .long   0x0000E681                      | tan(42 deg) * 65536
        .long   0x0000EEB9                      | tan(43 deg) * 65536
        .long   0x0000F737                      | tan(44 deg) * 65536
        .long   0x00010000                      | tan(45 deg) * 65536
        .long   0x00010919                      | tan(46 deg) * 65536
        .long   0x00011287                      | tan(47 deg) * 65536
        .long   0x00011C51                      | tan(48 deg) * 65536
        .long   0x0001267F                      | tan(49 deg) * 65536
        .long   0x00013117                      | tan(50 deg) * 65536
        .long   0x00013C22                      | tan(51 deg) * 65536
        .long   0x000147AA                      | tan(52 deg) * 65536
        .long   0x000153B9                      | tan(53 deg) * 65536
        .long   0x0001605B                      | tan(54 deg) * 65536
        .long   0x00016D9B                      | tan(55 deg) * 65536
        .long   0x00017B89                      | tan(56 deg) * 65536
        .long   0x00018A35                      | tan(57 deg) * 65536
        .long   0x000199AF                      | tan(58 deg) * 65536
        .long   0x0001AA0E                      | tan(59 deg) * 65536
        .long   0x0001BB68                      | tan(60 deg) * 65536
        .long   0x0001CDD6                      | tan(61 deg) * 65536
        .long   0x0001E177                      | tan(62 deg) * 65536
        .long   0x0001F66E                      | tan(63 deg) * 65536
        .long   0x00020CE1                      | tan(64 deg) * 65536
        .long   0x000224FE                      | tan(65 deg) * 65536
        .long   0x00023EFC                      | tan(66 deg) * 65536
        .long   0x00025B19                      | tan(67 deg) * 65536
        .long   0x0002799F                      | tan(68 deg) * 65536
        .long   0x00029AE7                      | tan(69 deg) * 65536
        .long   0x0002BF5B                      | tan(70 deg) * 65536
        .long   0x0002E77A                      | tan(71 deg) * 65536
        .long   0x000313E3                      | tan(72 deg) * 65536
        .long   0x00034556                      | tan(73 deg) * 65536
        .long   0x00037CC7                      | tan(74 deg) * 65536
        .long   0x0003BB68                      | tan(75 deg) * 65536
        .long   0x000402C2                      | tan(76 deg) * 65536
        .long   0x000454DB                      | tan(77 deg) * 65536
        .long   0x0004B462                      | tan(78 deg) * 65536
        .long   0x00052501                      | tan(79 deg) * 65536
        .long   0x0005ABD9                      | tan(80 deg) * 65536
        .long   0x00065051                      | tan(81 deg) * 65536
        .long   0x00071D88                      | tan(82 deg) * 65536
        .long   0x000824F3                      | tan(83 deg) * 65536
        .long   0x000983AD                      | tan(84 deg) * 65536
        .long   0x000B6E17                      | tan(85 deg) * 65536
        .long   0x000E4CF5                      | tan(86 deg) * 65536
        .long   0x001314BD                      | tan(87 deg) * 65536
        .long   0x001CA2D7                      | tan(88 deg) * 65536
        .long   0x00394A30                      | tan(89 deg) * 65536
        .long   0x7FFFFFFF                      | tan(90 deg) * 65536

| .FUNC AngleFromSlope,1
| .DEF SlopeFromAngle
| -----------------------------------------------------
| FUNCTION AngleFromSlope(slope: Fixed): INTEGER;
| Scans slope table for angle and returns angle 0..180
AngleFromSlope:
        MOVE.L  4(SP),D0                        | GET SLOPE
        SMI     D2                              | D2 := (N == 1)
        BPL.B   ANGLEFROMSLOPE_CONT             | CONTINUE IF POSITIVE
        NEG.L   D0                              | ELSE MAKE SLOPE POS
ANGLEFROMSLOPE_CONT:
        LEA     SLOPETBL(PC),A0                 | POINT TO TABLE OF SLOPES
        MOVE    #0xB4,D1                        | angle counter init = 180
        SUBI.L  #0x1F4,D0                       | bias slope by -500 for compare
ANGLEFROMSLOPE_SCAN:
        CMP.L   (A0)+,D0                        | compare against next tbl entry
        DBLE    D1,ANGLEFROMSLOPE_SCAN          | dble loop
        MOVE    #0xB4,D0                        | D0 := 180
        SUB     D1,D0                           | CALC 180-ANGLE = 90..180
        TST.B   D2                              | WAS DH POS ?
        BMI.B   ANGLEFROMSLOPE_CONT_2           | neg slope, return 90..180
        MOVE    D1,D0                           | YES, RETURN 0..90
ANGLEFROMSLOPE_CONT_2:
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        MOVE    D0,4(SP)                        | return angle as fcn result
        RTS                                     | return to caller

| .PROC PtToAngle,3
| .REF AngleFromSlope
| --------------------------------------------------------------
| PROCEDURE PtToAngle(r: Rect; pt: Point; VAR angle: INTEGER);
| Given a rectangle and a point, return the angle subtended by pt.
| Trap _PtToAngle ($A838). Plus version: Angles.s 136.
PtToAngle:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D6-D7/A4,-(SP)                  | save regs
        MOVE.L  16(A6),A4                       | A4 := rect ptr
        MOVE    4(A4),D0                        | GET RECT.BOTTOM
        ADD     (A4),D0                         | + rect.top
        ASR     #0x1,D0                         | center.v := (top+bot)/2
        MOVE    12(A6),D1                       | get pt.v
        SUB     D0,D1                           | DV := PT.V - CENTER.V
        MOVE    6(A4),D0                        | get rect.right
        ADD     2(A4),D0                        | + rect.left
        ASR     #0x1,D0                         | center.h := (left+right)/2
        MOVE    14(A6),D7                       | get pt.h
        SUB     D0,D7                           | DH := PT.H - CENTER.H
        BNE.B   PTTOANGLE_NONHORIZ              | CONTINUE IF DH <> 0
        TST     D1                              | WAS DV > 0 ?
        BLE.B   PTTOANGLE_HORIZ                 | NO, RETURN ANGLE = 0
        MOVE    #0xB4,D0                        | GET POLYHANDLE
        BRA.B   PTTOANGLE_DONE                  | skip non-horiz processing
PTTOANGLE_NONHORIZ:
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    D7,-(SP)                        | PUSH POLYHANDLE
        MOVE    D1,-(SP)                        | PUSH DV
        JSR     FixRatio(PC)                    | slope := DH / DV (fixed)
        MOVE.L  (SP)+,D6                        | GET SLOPE RESULT
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE    4(A4),D0                        | get rect.bottom
        SUB     (A4),D0                         | height = bot - top
        MOVE    D0,-(SP)                        | PUSH HEIGHT
        MOVE    6(A4),D0                        | get rect.right
        SUB     2(A4),D0                        | width = right - left
        MOVE    D0,-(SP)                        | PUSH WIDTH
        JSR     FixRatio(PC)                    | aspect := height/width
        MOVE.L  (SP)+,D0                        | GET ASPECT RESULT
        CLR.L   -(SP)                           | ROOM FOR FCN RESULT
        MOVE.L  D6,-(SP)                        | PUSH SLOPE
        MOVE.L  D0,-(SP)                        | PUSH ASPECT
        JSR     FixMul(PC)                      | slope2 := slope * aspect
        MOVE.L  (SP)+,D0                        | GET RESULT SLOPE2
        CLR     -(SP)                           | room for AngleFromSlope result
        MOVE.L  D0,-(SP)                        | PUSH SLOPE2
        JSR     AngleFromSlope(PC)              | SCAN FOR ARCTAN
        MOVE    (SP)+,D0                        | GET RESULT ANGLE
        TST     D7                              | WAS DH POSITIVE ?
        BPL.B   PTTOANGLE_DONE                  | YES, CONTINUE
        ADDI    #0xB4,D0                        | dh negative: angle += 180
        CMPI    #0x168,D0                       | did we wrap to 360?
        BNE.B   PTTOANGLE_DONE                  | NO, CONTINUE
PTTOANGLE_HORIZ:
        CLR     D0                              | YES, ANGLE := 0
PTTOANGLE_DONE:
        MOVE.L  8(A6),A0                        | GET VAR ADDR
        MOVE    D0,(A0)                         | STORE INTO ANGLE
        MOVEM.L (SP)+,D6-D7/A4                  | RESTORE REGS
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS
