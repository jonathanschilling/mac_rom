| ------------------------------------------------------------
|
| --> GRAFASM.TEXT
|
| Miscellaneous unclassified routines.
|
| The 1984 ROM places its handful of fixed-point math primitives
| (LongMul, FixMul, FixRatio, HiWord/LoWord/FixRound) inside the
| QuickDraw GrafAsm region for ROM-layout reasons. They are not part
| of QuickDraw proper -- they are general-purpose Toolbox utilities
| later split out into dialog_mgr.s + toolbox_utils.s in the Plus ROM.
|
| Routines:
|   LongMul  - 64-bit signed multiply of two 32-bit Fixed values
|   FixMul   - 16.16 fixed-point multiply (dest = a * b)
|   FixRatio - Fix(numer / denom) without intermediate overflow
|   HiWord, LoWord, FixRound - bitfield helpers for Fixed values
|
| Note: classic's file layout starts with tail-end fragments of other
| QuickDraw routines (SLAB_NEXT8 et al., pattern-fill continuations
| that physically sit here in the 1984 ROM). The real InitGraf entry
| is further down in this file (labeled).

SLAB_NEXT8:
        MOVE    D6,D0                           | GET PATTERN DATA
        AND     (A2)+,D1                        | mask pattern with edge mask
        AND     D1,D0                           | isolate src bits inside mask
        NOT     D1                              | invert mask for dst-keep
        AND     (A1),D1                         | keep dst bits outside mask
        OR      D0,D1                           | merge src and kept dst
        MOVE    D1,(A1)+                        | UPDATE DST
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT8                      | more words -> loop
        BEQ.B   SLABMODE_HANDLERS               | last word -> apply edge mask
        RTS                                     | done
SLAB_END9:
        AND     D3,D1                           | srcOr last word: apply edge mask
SLAB_NEXT9:
        AND     D6,D1                           | srcOr: AND mask with pattern
        AND     (A2)+,D1                        | AND with bg pattern lookup
        OR      D1,(A1)+                        | OR result into dst (srcOr)
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT9                      | more words -> loop
        BEQ.B   SLAB_END9                       | last word -> apply edge mask
        RTS                                     | done
SLAB_END10:
        AND     D3,D1                           | srcXor last word: apply edge mask
SLAB_NEXT10:
        AND     D6,D1                           | srcXor: AND mask with pattern
        AND     (A2)+,D1                        | AND with bg pattern lookup
        EOR     D1,(A1)+                        | XOR into dst (srcXor)
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT10                     | more words -> loop
        BEQ.B   SLAB_END10                      | last word -> apply edge mask
        RTS                                     | done
SLAB_END11:
        AND     D3,D1                           | srcBic last word: apply edge mask
SLAB_NEXT11:
        AND     D6,D1                           | srcBic: AND mask with pattern
        AND     (A2)+,D1                        | AND with bg pattern lookup
        NOT     D1                              | invert for bit-clear
        AND     D1,(A1)+                        | clear bits in dst (srcBic)
        MOVEQ.L #-0x1,D1                        | reset mask for next word
        SUBQ.W  #0x1,D2                         | decrement word count
        BGT.B   SLAB_NEXT11                     | more words -> loop
        BEQ.B   SLAB_END11                      | last word -> apply edge mask
        RTS                                     | done


LongMul:
        LINK    A6,#0x0                         | no locals
        MOVEM.L D0-D1/A1-A2,-(SP)               | save scratch regs
        MOVE.L  8(A6),A0                        | A0 = result ptr (4-byte product)
        LEA.L     16(A6),A1                     | A1 = end of operand A (4 bytes)
        LEA      12(FP),A2                      | A2 = end of operand B
| LONGMUL_ABS_A -- take absolute values, track sign in D6.
LONGMUL_ABS_A:
        TST.L   (A2)+                           | peek operand B sign
        SMI     D1                              | D1 := (N == 1)
        BPL.B   LONGMUL_ABS_B                   | positive -> skip negate
        NEG.L    -4(A2)                         | negate operand B in place
LONGMUL_ABS_B:
        TST.L   (A1)+                           | peek operand A sign
        BPL.B   LONGMUL_MUL                     | positive -> skip negate
        NOT.B   D1                              | flip sign tracker
        NEG.L   (A2)                            | (A2) = -(A2)
LONGMUL_MUL:
        MOVE    -(A1),D0                        | A.lo
        MULU    -(A2),D0                        | D0 = D0 *u -(A2)
        MOVE.L  D0,4(A0)                        | partial = A.lo * B.lo
        MOVE    -(A1),D0                        | A.hi
        MULU    -(A2),D0                        | D0 = D0 *u -(A2)
        MOVE.L  D0,(A0)                         | partial = A.hi * B.hi
        MOVE    (A1)+,D0                        | A.hi for cross product
        MULU    2(A2),D0                        | D0 = D0 *u 2(A2)
        ADD.L   D0,2(A0)                        | 2(A0) += D0
        BCC.B   LONGMUL_FOLD2                   | no carry -> skip
        ADDQ.W  #0x1,(A0)                       | (A0) += 0x1
LONGMUL_FOLD2:
        MOVE    (A2),D0                         | B.hi for second cross
        MULU    (A1),D0                         | D0 = D0 *u (A1)
        ADD.L   D0,2(A0)                        | 2(A0) += D0
        BCC.B   LONGMUL_FOLD3                   | no carry -> skip
        ADDQ.W  #0x1,(A0)                       | (A0) += 0x1
LONGMUL_FOLD3:
        TST.B   D1                              | result negative?
        BEQ.B   LONGMUL_EXIT                    | positive -> done
        NEG.L   4(A0)                           | 4(A0) = -4(A0)
        NEGX.L  (A0)                            | (A0) = -(A0) (with X bit)

| ----------------------------------------------------------
| LONGMUL_EXIT
| Called during boot.
LONGMUL_EXIT:
        MOVEM.L (SP)+,D0-D1/A1-A2               | restore scratch regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS
FixMul:
        LINK    A6,#-0x8                        | allocate 8-byte result
        MOVE.L  12(A6),-(SP)                    | push operand A
        MOVE.L  8(A6),-(SP)                     | push operand B
        PEA.L     -8(A6)                        | push result ptr
        JSR     LongMul(PC)                     | compute 64-bit product
        MOVE.L  -6(A6),16(A6)                   | return middle 32 bits (Fixed)
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return addr
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
| Called by: StdTxMeas, PTTOANGLE_NONHORIZ, SLANTED, NOSWAP, STOPOK (and 1 more)
FixRatio:
        MOVE    6(SP),D0                        | D0 = numer
        EXT.L    D0                             | sign-extend numer to long
        SMI     D1                              | D1 := (N == 1)
        BPL.B   FIXRATIO_POSNUM                 | positive -> skip negate
        NEG.L   D0                              | abs(numer)
FIXRATIO_POSNUM:
        TST     4(SP)                           | denom == 0?
        BNE.B   FIXRATIO_DEN_NONZERO            | nonzero -> divide
        MOVE.L  #0x7FFFFFFF,0x8(SP)             | denom=0 -> return INT_MAX
        BRA.B   FIXRATIO_DONE                   | skip division
FIXRATIO_DEN_NONZERO:
        BPL.B   FIXRATIO_DENPOS                 | denom positive -> skip
        NOT     D1                              | flip sign tracker
        NEG     4(SP)                           | 4(SP) = -4(SP)
FIXRATIO_DENPOS:
        DIVS    4(SP),D0                        | D0 = D0 /s 4(SP)
        MOVE    D0,8(SP)                        | integer part of result
        CLR     D0                              | zero D0 for fractional divide
        DIVU    4(SP),D0                        | D0 = D0 /u 4(SP)
        MOVE    D0,10(SP)                       | fractional part of result
FIXRATIO_DONE:
        TST.B   D1                              | overall sign negative?
        BEQ.B   FIXRATIO_EXIT                   | positive -> done
        NEG.L   8(SP)                           | 8(SP) = -8(SP)
FIXRATIO_EXIT:
        MOVE.L  (SP)+,(SP)                      | COPY A LONG INTO GLOBALS
        RTS                                     | return Fixed result
        MOVE    4(SP),8(SP)                     | RESTORE REG
        MOVE.L  (SP)+,(SP)                      | strip 4 bytes
        RTS                                     | return
        MOVE    6(SP),8(SP)                     | move numer over denom slot
        MOVE.L  (SP)+,(SP)                      | strip 4 bytes
        RTS                                     | return
        MOVE.L  #0x8000,D0                      | half-word rounding bias
        TST.L   4(SP)                           | test sign
        BPL.B   FIXRATIO_OVFL                   | positive -> skip neg
        NEG.L   D0                              | negate bias for negative
FIXRATIO_OVFL:
        ADD.L   D0,4(SP)                        | 4(SP) += D0
        MOVE    4(SP),8(SP)                     | return high word as result
        MOVE.L  (SP)+,(SP)                      | strip 4 bytes
        RTS                                     | return

| --------------------------------------------------
| PROCEDURE InitGraf(globalPtr: Ptr);
| Called during boot.
InitGraf:
        LINK    A6,#0x0                         | NO LOCALS
        MOVE.L  A4,-(SP)                        | SAVE REG
        MOVE.L  8(A6),A4                        | GET POINTER TO QUICKDRAW GLOBALS
        MOVE.L  A4,(A5)                         | SAVE IN MAGIC LOCATION
        LEA.L   -0xCA(A4),A0                    | SET UP START POINTER (LASTGRAFGLOB)
        LEA.L   4(A4),A1                        | SET UP LIMIT POINTER
CLRLP:
        CLR     (A0)+                           | CLEAR A WORD
        CMPA.L  A1,A0                           | CHECK LIMIT POINTER
        BNE.B   CLRLP                           | CLEAR ALL GLOBALS
        LEA.L     -0x90(A4),A4                  | POINT TO WIDEDATA
        MOVE.L  A4,D0                           | REMEMBER ADDR OF WIDEDATA
        MOVE    #0xA,(A4)+                      | wideData.rgnSize := 10
        MOVE.L  #0x80018001,(A4)+               | rgnBBox top-left = (-32767, -32767)
        MOVE.L  #0x7FFF7FFF,(A4)+               | rgnBBox bot-right = (+32767, +32767)
        MOVE.L  A4,D1                           | REMEMBER ADDR OF WIDEMASTER
        MOVE.L  D0,(A4)+                        | wideMaster := @wideData
        MOVE.L  D1,(A4)+                        | wideOpen := @wideMaster
        MOVEQ.L #0x1,D0                         | PREPARE RANDSEED INITIAL VALUE
        MOVE.L  D0,(A4)+                        | randSeed := 1
        CLR.L   -(SP)                           | reserve room for screenBase result
        JSR     PUSH_JScrnAddr(PC)              | get screen base address
        MOVE.L  (SP)+,(A4)+                     | screenBits.baseAddr := result
        PEA.L     8(A4)                         | push @screenBits.bottom
        PEA.L     6(A4)                         | push @screenBits.right
        JSR     PUSH_JScrnSize(PC)              | fill screen height/width
        MOVE    8(A4),D0                        | get screen width (pixels)
        LSR     #0x3,D0                         | /8 -> rowBytes
        MOVE    D0,(A4)+                        | screenBits.rowBytes := width/8
        CLR.L   (A4)+                           | screenBits.bounds.topLeft := 0
        ADDQ.W  #0x4,A4                         | skip past screenBits trailer
        MOVEQ.L #0x1A,D0                        | loop count = 26 longs (cursor + patterns)
        LEA     CURDATA(PC),A0                  | POINT TO CURSOR DATA
CRSRLP:
        MOVE.L  (A0)+,(A4)+                     | COPY A LONG INTO GLOBALS
        DBF     D0,CRSRLP                       | LOOP FOR 27 LONGS

| thePort := NIL
        MOVE.L  (SP)+,A4                        | RESTORE REG
        UNLK    A6                              | DESTROY STACK FRAME
        MOVE.L  (SP)+,(SP)                      | STRIP PARAMETER
        RTS                                     | AND RETURN

| QuickDraw default globals data: arrow cursor + 5 standard patterns
| Patterns are 8x8 pixels, 1 bit per pixel, 1 byte per row.
| Bit 7 = leftmost pixel, bit 0 = rightmost pixel (MSB first).
| These are tiled to fill any area when used as pen, background, or fill patterns.
| (see also: github.com/jonathanschilling/PatternDrafter)
| arrow.data (16x16 cursor image, 1=black):
| ..**............
| .***............
| .****...........
| .*****..........
| .*******.........
| .*******........
| .*********.......
| .**.***.........
| .*...***.........
| .....***........
| ......**........
| ................
| ----------------------------------------------------------
| CURDATA -- default QuickDraw cursor + 5 standard patterns
| 68 bytes arrow cursor (16 rows shape + 16 rows mask + hotSpot)
| 40 bytes patterns: gray, ltGray, dkGray (50%), black, white
| ----------------------------------------------------------
CURDATA:                                        | arrow cursor shape
        .short  0x0000, 0x4000, 0x6000, 0x7000  | rows 0-3
        .short  0x7800, 0x7C00, 0x7E00, 0x7F00  | rows 4-7
        .short  0x7F80, 0x7C00, 0x6C00, 0x4600  | rows 8-11
        .short  0x0600, 0x0300, 0x0300, 0x0000  | rows 12-15
CURMASK:                                        | arrow cursor mask
        .short  0xC000, 0xE000, 0xF000, 0xF800  | rows 0-3
        .short  0xFC00, 0xFE00, 0xFF00, 0xFF80  | rows 4-7
        .short  0xFFC0, 0xFFE0, 0xFE00, 0xEF00  | rows 8-11
        .short  0xCF00, 0x8780, 0x0780, 0x0380  | rows 12-15
CURHOTSPOT:                                     | arrow hotSpot (1,1)
        .short  0x0001, 0x0001                  | hotSpot v/h
| Standard QuickDraw patterns (8 bytes each)
QDPATTERNS:
        .byte   0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD | gray
        .byte   0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 | ltGray
        .byte   0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 | dkGray (50%)
        .byte   0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF | black
        .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 | white

| ----------------------------------------------------------
| .PROC OpenPort,1
| PROCEDURE OpenPort(port: GrafPtr);
| Initialize a GrafPort to defaults: allocate clipRgn/visRgn, set
| portBits = screenBits, install wide-open clipRgn, then fall
| through to InitPort to initialize the rest of port state.
| Plus equivalent: GrafAsm.s 153.
| Called during boot.
OpenPort:
        CLR.L   -(SP)                           | MAKE ROOM FOR FUNCTION RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A NEW REGION
        CLR.L   -(SP)                           | MAKE ROOM FOR FUNCTION RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A SECOND NEW REGION
        MOVE.L  12(SP),A0                       | POINT TO PORT
        MOVE.L  (SP)+,28(A0)                    | INSTALL NEW REGION INTO CLIPRGN
        MOVE.L  (SP)+,24(A0)                    | AND OTHER INTO VISRGN
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  4(SP),A1                        | GET PORT PARAM
        MOVE.L  A1,(A0)                         | SetPort(port)
        CLR     (A1)+                           | DEVICE := 0
        LEA.L     -0x7A(A0),A0                  | POINT TO SCREENBITS
        MOVE.L  (A0)+,(A1)+                     | portBits := screenBits
        MOVE    (A0)+,(A1)+                     | COPY ROWBYTES
        MOVE.L  (A0),(A1)+                      | COPY TOPLEFT
        MOVE.L  4(A0),(A1)+                     | COPY BOTRIGHT
        MOVE.L  (A0),(A1)+                      | portRect := screenBits.bounds
        MOVE.L  4(A0),(A1)+                     | all 8 bytes
        MOVE.L  (A1)+,-(SP)                     | visRgn := screenBits.bounds
        MOVE.L  A0,-(SP)                        | PUSH ADDR OF RECT
        JSR     RectRgn(PC)                     | CALL RECTRGN
        MOVE.L  4(SP),A1                        | GET PORT PARAM
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  -0x82(A0),-(SP)                 | PUSH WIDE OPEN RGN
        MOVE.L  28(A1),-(SP)                    | PUSH CLIPRGN
        JSR     CopyRgn(PC)                     | SET TO WIDE OPEN

| ----------------------------------------------------------
| .PROC InitPort,1
| PROCEDURE InitPort(port: GrafPtr);
| Re-initialize port state to defaults. Reachable as trap
| _InitPort entry, AND as fall-through from OpenPort.
| Plus equivalent: GrafAsm.s 172.
| Called during boot.
InitPort:
        MOVE.L  4(SP),A1                        | GET PORT PARAM
        LEA.L     0x20(A1),A1                   | POINT TO BKPAT
        CLR.L   (A1)+                           | bkPat := white
        CLR.L   (A1)+                           | CLEAR SECOND LONG OF WHITE
        MOVEQ.L #-0x1,D0                        | GET ALL ONES
        MOVE.L  D0,(A1)+                        | fillPat := Black
        MOVE.L  D0,(A1)+                        | SECOND LONG OF BLACK
        CLR.L   (A1)+                           | pnLoc := (0,0)
        MOVE.L  #0x00010001,(A1)+               | pnSize := (1,1)
        MOVE    #0x8,(A1)+                      | pnMode := patCopy
        MOVE.L  D0,(A1)+                        | pnPat := black
        MOVE.L  D0,(A1)+                        | SECOND LONG OF BLACK
        CLR     (A1)+                           | pnVis := 0
        CLR.L   (A1)+                           | txFont, txFace := 0
        MOVE    #0x1,(A1)+                      | txMode := srcOr
        CLR     (A1)+                           | txSize := 0
        CLR.L   (A1)+                           | spExtra := 0.0
        MOVE.L  #0x21,(A1)+                     | fgColor := blackColor
        MOVE.L  #0x1E,(A1)+                     | bkColor := whiteColor
        CLR.L   (A1)+                           | colrBit,patStretch := 0
        CLR.L   (A1)+                           | picSave := Nil
        CLR.L   (A1)+                           | rgnSave := Nil
        CLR.L   (A1)+                           | polySave := Nil
        CLR.L   (A1)+                           | grafProcs := Nil
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| .PROC ClosePort,1
| PROCEDURE ClosePort(port: GrafPtr);
| Disposes of clipRgn and visRgn handles. Plus uses inline
| _DisposeHandle; classic uses NEWRGN_CONT (a Pascal-stack
| _DisposeHandle wrapper).
| Plus equivalent: GrafAsm.s 228.
| Called during boot.
ClosePort:
        MOVE.L  4(SP),A0                        | GET PORT
        MOVE.L  28(A0),-(SP)                    | PUSH VISRGN HANDLE
        JSR     NEWRGN_CONT(PC)                 | DisposeHandle wrapper
        MOVE.L  4(SP),A0                        | GET PORT
        MOVE.L  24(A0),-(SP)                    | PUSH CLIPRGN HANDLE
        JSR     NEWRGN_CONT(PC)                 | DisposeHandle wrapper
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| .PROC SetStdProcs,1
| PROCEDURE SetStdProcs(VAR procs: QDProcs);
| Fill a QDProcs record with standard QuickDraw procedure pointers.
| Order matches QDProcs (GrafTypes.s).
| Plus equivalent: GrafAsm.s 242.
| Called during boot.
SetStdProcs:
        MOVE.L  4(SP),A1                        | GET ADDRESS OF PROC RECORD
        LEA     StdText(PC),A0                  | textProc = StdText
        MOVE.L  A0,(A1)+                        | install textProc
        LEA     StdLine(PC),A0                  | lineProc = StdLine
        MOVE.L  A0,(A1)+                        | install lineProc
| Continue J-vector install: rect/RRect/oval/arc/poly/rgn/comment/textWid/getPic/putPic.
        LEA     StdRect(PC),A0                  | rectProc = StdRect
        MOVE.L  A0,(A1)+                        | install rectProc
        LEA     StdRRect(PC),A0                 | rRectProc = StdRRect
        MOVE.L  A0,(A1)+                        | install rRectProc
        LEA     StdOval(PC),A0                  | ovalProc = StdOval
        MOVE.L  A0,(A1)+                        | install ovalProc
        LEA     StdArc(PC),A0                   | arcProc = StdArc
        MOVE.L  A0,(A1)+                        | install arcProc
        LEA     StdPoly(PC),A0                  | polyProc = StdPoly
        MOVE.L  A0,(A1)+                        | install polyProc
        LEA     StdRgn(PC),A0                   | rgnProc = StdRgn
        MOVE.L  A0,(A1)+                        | install rgnProc
        LEA     StdBits(PC),A0                  | bitsProc = StdBits
        MOVE.L  A0,(A1)+                        | install bitsProc
        LEA     StdComment(PC),A0               | commentProc = StdComment
        MOVE.L  A0,(A1)+                        | install commentProc
        LEA     StdTxMeas(PC),A0                | txMeasProc = StdTxMeas
        MOVE.L  A0,(A1)+                        | install txMeasProc
        LEA     StdGetPic(PC),A0                | getPicProc = StdGetPic
        MOVE.L  A0,(A1)+                        | install getPicProc
        LEA     StdPutPic(PC),A0                | putPicProc = StdPutPic
        MOVE.L  A0,(A1)+                        | install putPicProc
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| ----------------------------------------------------------
| .PROC GlobalToLocal,1
| PROCEDURE GlobalToLocal(VAR pt: Point);
| Convert a global-coord point to current grafport's local coords.
| Plus equivalent: GrafAsm.s 280.
| Called during boot.
GlobalToLocal:
        MOVEM.L D0/A0-A1,-(SP)                  | save regs
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  16(SP),A1                       | A1 = VAR pt addr
        MOVE    8(A0),D0                        | D0 = portRect.top global
        SUB     D0,(A1)+                        | pt.v -= portRect.top global
        MOVE    10(A0),D0                       | D0 = portRect.left global
        SUB     D0,(A1)+                        | pt.h -= portRect.left global
        MOVEM.L (SP)+,D0/A0-A1                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| ----------------------------------------------------------
| .PROC LocalToGlobal,1
| PROCEDURE LocalToGlobal(VAR pt: Point);
| Convert a local-coord point to global coords.
| Plus equivalent: GrafAsm.s 268. Trap: _LocalToGlobal ($A871).
| Called during boot.
LocalToGlobal:
        MOVEM.L D0/A0-A1,-(SP)                  | save regs
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  16(SP),A1                       | A1 = VAR pt addr
        MOVE    8(A0),D0                        | D0 = portRect.top global
        ADD     D0,(A1)+                        | pt.v += portRect.top global
        MOVE    10(A0),D0                       | D0 = portRect.left global
        ADD     D0,(A1)+                        | pt.h += portRect.left global
        MOVEM.L (SP)+,D0/A0-A1                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| ----------------------------------------------------------
| PROCEDURE GrafDevice(device: INTEGER);
| Plus equivalent: GrafAsm.s 365.
GrafDevice:
        MOVEQ.L #0x0,D0                         | port offset 0 = device
        JMP     L_mPortWord(PC)                 | install word into port

| ----------------------------------------------------------
| PROCEDURE SetPort(gp: GrafPtr); Plus equivalent: GrafAsm.s 341.
SetPort:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  4(SP),(A0)                      | install new thePort
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| ----------------------------------------------------------
| PROCEDURE GetPort(VAR gp: GrafPtr); Plus equivalent: GrafAsm.s 352.
GetPort:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  4(SP),A1                        | A1 = VAR addr
        MOVE.L  (A0),(A1)                       | copy thePort to VAR
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| ----------------------------------------------------------
| PROCEDURE SetPortBits(bm: BitMap); Plus equivalent: GrafAsm.s 376.
SetPBits:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     2(A0),A0                      | POINT TO PORTBITS
        MOVE.L  4(SP),A1                        | POINT TO BITMAP
        MOVE.L  (A1)+,(A0)+                     | COPY BASEADDR
        MOVE    (A1)+,(A0)+                     | COPY ROWBYTES
SETPORTBITS_SHARE:
        MOVE.L  (A1)+,(A0)+                     | SHARE: COPY BOUNDS.TOPLEFT
        MOVE.L  (A1)+,(A0)+                     | COPY BOUNDS.BOTRIGHT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| .PROC PortSize,2
| ----------------------------------------------------------
| PROCEDURE PortSize(width,height: INTEGER);
| Called during boot.
PortSize:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE    0x12(A0),D0                     | GET PORTRECT.LEFT
        ADD     0x6(SP),D0                      | ADD WIDTH
        MOVE    D0,0x16(A0)                     | UPDATE PORTRECT.RIGHT
        MOVE    0x10(A0),D0                     | GET PORTRECT.TOP
        ADD     0x4(SP),D0                      | ADD HEIGHT
        MOVE    D0,0x14(A0)                     | UPDATE PORTRECT.BOTTOM
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| PROCEDURE MovePortTo(leftGlobal, topGlobal: INTEGER);
| Plus equivalent: GrafAsm.s 427.
MovePortTo:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE    18(A0),D0                       | GET PORTRECT.LEFT
        SUB     10(A0),D0                       | CONVERT TO GLOBAL
        SUB     6(SP),D0                        | SUB LEFTGLOBAL FOR DH
        MOVE    16(A0),D1                       | GET PORTRECT.TOP
        SUB     8(A0),D1                        | CONVERT TO GLOBAL
        SUB     4(SP),D1                        | SUB TOPGLOBAL FOR DV
        ADD     D0,10(A0)                       | 10(A0) += D0
        ADD     D0,14(A0)                       | 14(A0) += D0
        ADD     D1,8(A0)                        | 8(A0) += D1
        ADD     D1,12(A0)                       | 12(A0) += D1
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| PROCEDURE SetOrigin(h, v: INTEGER);
| Adjust port origin and offset clipRgn. Plus equivalent: GrafAsm.s 455.
SetOrigin:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  4(SP),D0                        | D0 = (h,v) packed
        CMP.L   16(A0),D0                       | already at this origin?
        BEQ.B   SETORIGIN_DONE                  | yes, skip
        MOVE    6(SP),D0                        | GET H
        SUB     18(A0),D0                       | dh = h - portRect.left
        MOVE    4(SP),D1                        | GET V
        SUB     16(A0),D1                       | dv = v - portRect.top
        ADD     D0,10(A0)                       | 10(A0) += D0
        ADD     D0,14(A0)                       | 14(A0) += D0
        ADD     D1,8(A0)                        | 8(A0) += D1
        ADD     D1,12(A0)                       | 12(A0) += D1
        ADD     D0,18(A0)                       | 18(A0) += D0
        ADD     D0,22(A0)                       | 22(A0) += D0
        ADD     D1,16(A0)                       | 16(A0) += D1
        ADD     D1,20(A0)                       | 20(A0) += D1
        MOVE.L  24(A0),-(SP)                    | PUSH PARMS FOR LATER
        MOVE    D0,-(SP)                        | push dh for OffsetRgn
        MOVE    D1,-(SP)                        | push dv for OffsetRgn
        JSR     OffsetRgn(PC)                   | slide clipRgn by (dh,dv)
SETORIGIN_DONE:
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| PROCEDURE SetClip(rgn: RgnHandle); copy rgn into theport^.clipRgn.
| Plus equivalent: GrafAsm.s 503.
SetClip:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (A5),A1                         | A1 = QD globals
        MOVE.L  (A1),A1                         | A1 = thePort
        MOVE.L  28(A1),-(SP)                    | PUSH thePort^.clipRgn (dst)
        MOVE.L  A0,-(SP)                        | restore return addr
        JMP     CopyRgn(PC)                     | CopyRgn(srcRgn, dstRgn)

| ----------------------------------------------------------
| PROCEDURE GetClip(rgn: RgnHandle); copy theport^.clipRgn into rgn.
| Plus equivalent: GrafAsm.s 517.
GetClip:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | POP arg RGN HANDLE
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | GET CURRENT GRAFPORT
        MOVE.L  28(A1),-(SP)                    | PUSH THEPORT^.CLIPRGN (src)
        MOVE.L  D0,-(SP)                        | PUSH arg RGN (dst)
        MOVE.L  A0,-(SP)                        | restore return addr
        JMP     CopyRgn(PC)                     | CopyRgn(src, dst)

| ----------------------------------------------------------
| PROCEDURE ClipRect(r: Rect); set thePort^.clipRgn to a rect.
| Plus equivalent: GrafAsm.s 485.
ClipRect:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  4(SP),A1                        | A1 = rect ptr
        MOVE.L  28(A0),-(SP)                    | push clipRgn
        MOVE.L  A1,-(SP)                        | push rect
        JSR     RectRgn(PC)                     | RectRgn equivalent
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| ----------------------------------------------------------
| PROCEDURE BackPat(pat: Pattern); set thePort^.bkPat.
| Plus equivalent: GrafAsm.s 393.
BackPat:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        LEA.L     0x20(A0),A0                   | A0 = bkPat
        MOVE.L  4(SP),A1                        | A1 = source pat
        MOVE.L  (A1)+,(A0)+                     | copy pat into bkPat
        MOVE.L  (A1)+,(A0)+                     | all 8 bytes
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return

| ----------------------------------------------------------
| PROCEDURE AddPt(src: Point; VAR dst: Point);
| Plus equivalent: GrafAsm.s 312.
AddPt:
        MOVEM.L D0/A0,-(SP)                     | save regs
        MOVE.L  12(SP),A0                       | A0 = VAR dst
        MOVE    16(SP),D0                       | D0 = src.v
        ADD     D0,(A0)+                        | dst.v += src.v
        MOVE    18(SP),D0                       | D0 = src.h
        ADD     D0,(A0)+                        | dst.h += src.h
        MOVEM.L (SP)+,D0/A0                     | restore regs
        MOVE.L  (SP)+,(SP)                      | strip dst
        MOVE.L  (SP)+,(SP)                      | strip src
        RTS                                     | return

| ----------------------------------------------------------
| PROCEDURE SubPt(src: Point; VAR dst: Point);
| Plus equivalent: GrafAsm.s 322.
SubPt:
        MOVEM.L D0/A0,-(SP)                     | save regs
        MOVE.L  12(SP),A0                       | A0 = VAR dst
        MOVE    16(SP),D0                       | D0 = src.v
        SUB     D0,(A0)+                        | dst.v -= src.v
        MOVE    18(SP),D0                       | D0 = src.h
        SUB     D0,(A0)+                        | dst.h -= src.h
        MOVEM.L (SP)+,D0/A0                     | restore regs
        MOVE.L  (SP)+,(SP)                      | strip dst
        MOVE.L  (SP)+,(SP)                      | strip src
        RTS                                     | return

| .PROC SetPt
| -------------------------------------------------------------
| PROCEDURE SetPt(VAR pt: Point; h,v: INTEGER);
| Called during boot.
SetPt:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | POP H,V
        MOVE.L  (SP)+,A1                        | POP VAR ADDR OF PT
        MOVE.L  D0,(A1)                         | STORE H,V INTO PT
        JMP     (A0)                            | RETURN

| .PROC EqualPt
| ----------------------------------------------------------
| FUNCTION EqualPt(pt1,pt2: Point): BOOLEAN;
| CLOBBERS D0,A0.
EqualPt:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | pop point1
        CMP.L   (SP)+,D0                        | is point2 = point1 ?
        SEQ     (SP)                            | IF YES, SET TO TRUE
        NEG.B   (SP)                            | CONVERT -1 TO 1
        JMP     (A0)                            | RETURN
