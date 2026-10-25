| ------------------------------------------------------------------
|
| --> RGNBLT.TEXT
|
| Low level block transfer clipped to an arbitrary region.
|

| .PROC RgnBlt,9
| .REF BitBlt,RSect,ShieldCursor,ShowCursor
| .REF SeekRgn,PatExpand,ColorMap,InitRgn,TrimRect
| --------------------------------------------------------------
|
| PROCEDURE RgnBlt(srcBits,dstBits: BitMap;
| srcRect,dstRect: Rect;
| mode: INTEGER; pat: Pattern;
| rgnA,rgnB,rgnC: RgnHandle);
|
| TRANSFERS A RECTANGULAR BLOCK OF BITS CLIPPED TO THE DESTINATION
| BITMAP'S BOUNDS AND TO THE INTERSECTION OF THREE REGIONS.
| MODE SPECIFIES THE TRANSFER MODE AND WHETHER THE SOURCE SHOULD COME
| FROM THE SOURCE BITMAP OR FROM A REPEATING PATTERN.
| COPYRIGHT APPLE COMPUTER INC.
| DESIGNED AND WRITTEN BY BILL ATKINSON
| THIS CODE IS POSITION INDEPENDENT, RE-ENTRANT, AND READ-ONLY.
| CLOBBERS ONLY A0.
| MODES: 0 SRC --> DST
| 1 SRC OR DST --> DST | jump via A2 | jump via A2
| 2 SRC XOR DST --> DST
| 3 SRC BIC DST --> DST
| 4 (NOT SRC) --> DST
| 5 (NOT SRC) OR DST --> DST
| 6 (NOT SRC) XOR DST --> DST
| 7 (NOT SRC) BIC DST --> DST
| 8 PATTERN --> DST
| 9 PATTERN OR DST --> DST
| 10 PATTERN XOR DST --> DST
| 11 PATTERN BIC DST --> DST
| 12 (NOT PATTERN) --> DST
| 13 (NOT PATTERN) OR DST --> DST
| 14 (NOT PATTERN) XOR DST --> DST
| 15 (NOT PATTERN) BIC DST --> DST
| Called during boot.
| Called by: NOTPORT_NO, DRAWLINE_USERGN, DrawRect, DORECT, DrawRgn (and 1 more)
RgnBlt:
        LINK    A6,#-0xCE                       | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | save scratch regs to stack
        MOVE.L  SP,-0x8C(A6)                    | -0x8C(A6) := SP
        MOVE.L  A5,-0xCC(A6)                    | -0xCC(A6) := A5
        MOVE    24(A6),-(SP)                    | push 24(A6)
        MOVE.L  20(A6),-(SP)                    | push 20(A6)
        JSR     ColorMap(PC)                    | call ColorMap
        MOVE.L  (SP)+,20(A6)                    | pop 20(A6)
        MOVE    (SP)+,24(A6)                    | pop 24(A6)
        MOVE.L  16(A6),A1                       | A1 := 16(A6)
        MOVE.L  (A1),A1                         | A1 := (A1)
        MOVE.L  12(A6),A2                       | A2 := mode
OKRECT:
        MOVE.L  (A2),A2                         | A2 := (A2)
        MOVE.L  8(A6),A3                        | A3 := pat
        MOVE.L  (A3),A3                         | A3 := (A3)
        MOVE.L  26(A6),A4                       | A4 := srcBits
        MOVE.L  0x22(A6),A5                     | A5 := 0x22(A6)
        MOVE.L  A4,-(SP)                        | push A4
        PEA.L     6(A5)                         | push effective addr 6(A5)
        PEA.L     2(A1)                         | push effective addr 2(A1)
        PEA.L     2(A2)                         | push effective addr 2(A2)
        PEA.L     2(A3)                         | push effective addr 2(A3)
        MOVE    #0x5,-(SP)                      | push #0x5
        PEA.L     -0x94(A6)                     | push effective addr -0x94(A6)
        JSR     RSect(PC)                       | intersect rects, branch if empty
        BEQ.W   RGNBLT_GOHOME                   | if zero -> RGNBLT_GOHOME
        PEA.L     -0x94(A6)                     | push effective addr -0x94(A6)
        MOVE.L  6(A5),-(SP)                     | push 6(A5)
        MOVE.L  -0xCC(A6),A5                    | A5 := -0xCC(A6)
        JSR     ShieldCursor(PC)                | ShieldCursor(minRect, dstBits.bounds.topLeft)
        MOVE.L  0x22(A6),A5                     | A5 := 0x22(A6)
        MOVE    #0x1E,D0                        | D0 := #0x1E
        SUB     (A1),D0                         | D0 -= (A1)
        SUB     (A2),D0                         | D0 -= (A2)
        SUB     (A3),D0                         | D0 -= (A3)
        BNE.B   OKRECT_NO                       | if non-zero -> OKRECT_NO
        MOVE.L  30(A6),A2                       | A2 := 30(A6)
        LEA.L     -0xC8(A6),A0                  | A0 = &-0xC8(A6)
        MOVE    -0x94(A6),D0                    | D0 := -0x94(A6)
        SUB     (A4),D0                         | D0 -= (A4)
        ADD     (A2),D0                         | D0 += (A2)
        MOVE    D0,(A0)                         | (A0) := D0
        MOVE    -0x92(A6),D0                    | D0 := -0x92(A6)
        SUB     2(A4),D0                        | D0 -= 2(A4)
        ADD     2(A2),D0                        | D0 += 2(A2)
        MOVE    D0,2(A0)                        | 2(A0) := D0
        MOVE.L  0x26(A6),-(SP)                  | push 0x26(A6)
        MOVE.L  A5,-(SP)                        | push A5
        MOVE.L  A0,-(SP)                        | push A0
        PEA.L     -0x94(A6)                     | push effective addr -0x94(A6)
        MOVE    24(A6),-(SP)                    | -(SP) := srcRgn
        MOVE.L  20(A6),-(SP)                    | -(SP) := dstRgn
        MOVE.L  -0xCC(A6),A5                    | A5 := -0xCC(A6)
        JSR     BitBlt(PC)                      | call BitBlt for this clip rect
        BRA.W   RGNBLT_DONE                     | jump to RGNBLT_DONE
OKRECT_NO:
        MOVE    -0x92(A6),D1                    | D1 := -0x92(A6)
        SUB     8(A5),D1                        | D1 -= 8(A5)
        ANDI    #-0x10,D1                       | mask D1 with #-0x10
        ADD     8(A5),D1                        | D1 += 8(A5)
        MOVE    D1,-0xA0(A6)                    | -0xA0(A6) := D1
        MOVE    -0x8E(A6),D0                    | D0 := -0x8E(A6)
        SUB     D1,D0                           | D0 -= D1
        LSR     #0x5,D0                         | D0 >>= 5 (logical)
        MOVE    D0,-0xA2(A6)                    | -0xA2(A6) := D0
| -----------------------------------------------------------------------
| ALLOCATE AND CLEAR A SCANLINE BUFFER FOR THE COMPOSITE MASK.
| Called during boot.
RGNBLT_CLRMASK:
        CLR.L   -(SP)                           | push zero word
        DBRA    D0,RGNBLT_CLRMASK               | loop D0 -> RGNBLT_CLRMASK
        MOVE.L  SP,-0x9A(A6)                    | -0x9A(A6) := SP
        MOVE    #-0x7FFF,-0x4A(A6)              | srcBump := #-0x7FFF
        MOVE    #-0x7FFF,-0x62(A6)              | -0x62(A6) := #-0x7FFF
        MOVE    #-0x7FFF,-0x7A(A6)              | -0x7A(A6) := #-0x7FFF
        MOVE    #0x7FFF,-0x48(A6)               | dstRow := #0x7FFF
        MOVE    #0x7FFF,-0x60(A6)               | -0x60(A6) := #0x7FFF
        MOVE    #0x7FFF,-0x78(A6)               | -0x78(A6) := #0x7FFF
        CLR     -0x96(A6)                       | clear -0x96(A6)
        CMPI    #0xA,(A1)                       | is rgnA a rectangle?
        BEQ.B   RGNBLT_CLRMASK_CONT_2           | if zero -> RGNBLT_CLRMASK_CONT_2
        ADDQ.W  #0x2,-0x96(A6)                  | -0x96(A6) += 0x2
        MOVE.L  A1,A0                           | A0 := A1
        LEA.L     -0x58(A6),A1                  | A1 = &-0x58(A6)
        MOVE    -0x92(A6),D0                    | D0 := -0x92(A6)
        MOVE    -0x8E(A6),D1                    | D1 := -0x8E(A6)
        MOVE    -0xA0(A6),D2                    | D2 := -0xA0(A6)
        JSR     InitRgn(PC)                     | walk region into per-row state
RGNBLT_CLRMASK_CONT_2:
        CMPI    #0xA,(A2)                       | is rgnB a rectangle?
        BEQ.B   RGNBLT_CLRMASK_CONT_3           | if zero -> RGNBLT_CLRMASK_CONT_3
        ADDQ.W  #0x4,-0x96(A6)                  | -0x96(A6) += 0x4
        MOVE.L  A2,A0                           | A0 := A2
        LEA.L     -0x70(A6),A1                  | A1 = &-0x70(A6)
        MOVE    -0x92(A6),D0                    | D0 := -0x92(A6)
        MOVE    -0x8E(A6),D1                    | D1 := -0x8E(A6)
        MOVE    -0xA0(A6),D2                    | D2 := -0xA0(A6)
        JSR     InitRgn(PC)                     | walk region into per-row state
RGNBLT_CLRMASK_CONT_3:
        CMPI    #0xA,(A3)                       | is rgnC a rectangle?
        BEQ.B   RGNBLT_CLRMASK_CONT_4           | if zero -> RGNBLT_CLRMASK_CONT_4
        ADDQ.W  #0x8,-0x96(A6)                  | -0x96(A6) += 0x8
        MOVE.L  A3,A0                           | A0 := A3
        LEA.L     -0x88(A6),A1                  | A1 = &-0x88(A6)
        MOVE    -0x92(A6),D0                    | D0 := -0x92(A6)
        MOVE    -0x8E(A6),D1                    | D1 := -0x8E(A6)
        MOVE    -0xA0(A6),D2                    | D2 := -0xA0(A6)
        JSR     InitRgn(PC)                     | walk region into per-row state
RGNBLT_CLRMASK_CONT_4:
        CMPI    #0x2,-0x96(A6)                  | compare regionFlags with #0x2
        BNE.B   RGNBLT_CLRMASK_CONT_5           | if non-zero -> RGNBLT_CLRMASK_CONT_5
        MOVE.L   -154(FP),-80(FP)               | dstAddr := -154(FP)
        BRA.B   RGNBLT_CLRMASK_NO_4             | jump to RGNBLT_CLRMASK_NO_4
RGNBLT_CLRMASK_CONT_5:
        CMPI    #0x4,-0x96(A6)                  | compare regionFlags with #0x4
        BNE.B   RGNBLT_CLRMASK_NO_3             | if non-zero -> RGNBLT_CLRMASK_NO_3
        MOVE.L  -0x9A(A6),-0x68(A6)             | -0x68(A6) := -0x9A(A6)
        BRA.B   RGNBLT_CLRMASK_NO_4             | jump to RGNBLT_CLRMASK_NO_4
RGNBLT_CLRMASK_NO_3:
        CMPI    #0x8,-0x96(A6)                  | compare regionFlags with #0x8
        BNE.B   RGNBLT_CLRMASK_NO_4             | if non-zero -> RGNBLT_CLRMASK_NO_4
        MOVE.L  -0x9A(A6),-0x80(A6)             | -0x80(A6) := -0x9A(A6)
RGNBLT_CLRMASK_NO_4:
        MOVE    -0x94(A6),-0xAC(A6)             | -0xAC(A6) := -0x94(A6)
        MOVE    -0x90(A6),-0xAE(A6)             | -0xAE(A6) := -0x90(A6)
        MOVE    #0x1,-0xB0(A6)                  | -0xB0(A6) := #0x1
        MOVE    #0x4,-0xB2(A6)                  | -0xB2(A6) := #0x4
        MOVE    4(A5),D0                        | D0 := 4(A5)
        EXT.L    D0                             | sign-extend D0
        MOVE.L  D0,-0xBA(A6)                    | -0xBA(A6) := D0
        MOVE.L  -0x9A(A6),-0x9E(A6)             | FIRSTV:=BOTTOM-1
        CLR.L   D7                              | clear D7
        MOVE    24(A6),D2                       | LASTV:=TOP-1
        BMI.W   RGNBLT_DONE                     | if negative -> RGNBLT_DONE
        BCLR    #0x2,D2                         | clear bit #0x2 of D2
        BEQ.B   RGNBLT_CLRMASK_NO_5             | if zero -> RGNBLT_CLRMASK_NO_5
        NOT.L   D7                              | invert D7
RGNBLT_CLRMASK_NO_5:
        ANDI    #0xF,D2                         | mask D2 with #0xF
        MOVEQ.L #0x3,D0                         | D0 := #0x3
        AND     D2,D0                           | D0 := D0 AND D2
        ADD     D0,D2                           | D2 += D0
        LEA     ABCDONE_MODE_TBL(PC),A0         | A0 = &ABCDONE_MODE_TBL(PC)
        ADDA.W  0(A0,D2.W),A0                   | D2.W),A0 += 0(A0
        MOVE.L  A0,-0xC0(A6)                    | -0xC0(A6) := A0
        BTST    #0x3,D2                         | test bit #0x3 of D2
        BEQ.B   RGNBLT_CLRMASK_NO_6             | DO LAST WITH LASTMASK
        MOVE    8(A5),D2                        | D2 := 8(A5)
        MOVE.L  20(A6),A0                       | A0 := 20(A6)
        LEA.L     -0x40(A6),A1                  | A1 = &expat
        MOVE.L  -0xCC(A6),A5                    | A5 := -0xCC(A6)
        JSR     PatExpand(PC)                   | expand 8-byte pattern to 16-long table
        MOVE.L  0x22(A6),A5                     | A5 := 0x22(A6)
        MOVEQ.L #0xF,D7                         | D7 := #0xF
        AND     -0x94(A6),D7                    | D7 := D7 AND -0x94(A6)
        LSL     #0x2,D7                         | D7 <<= 2
        MOVE.L  -0x40(A6,D7.W),D6               | D6 = pattern word from expanded table
        BRA.W   RGNBLT_GETDST                   | jump to RGNBLT_GETDST
RGNBLT_CLRMASK_NO_6:
        MOVE.L  30(A6),A2                       | A2 := 30(A6)
        MOVE.L  0x26(A6),A3                     | A3 := 0x26(A6)
        MOVE    4(A3),D0                        | D0 := 4(A3)
        EXT.L    D0                             | sign-extend D0
        MOVE.L  D0,-0xB6(A6)                    | -0xB6(A6) := D0
        MOVE.L  (A3),D0                         | D0 := (A3)
        CMP.L   (A5),D0                         | compare D0 with (A5)
        BNE.B   RGNBLT_SRCOK                    | if non-zero -> RGNBLT_SRCOK
        MOVE    (A4),D0                         | D0 := (A4)
        SUB     6(A5),D0                        | D0 -= 6(A5)
        MOVE    (A2),D1                         | D1 := (A2)
        SUB     6(A5),D1                        | D1 -= 6(A5)
        SUB     D1,D0                           | D0 -= D1
        BLT.B   RGNBLT_SRCOK                    | if signed < -> RGNBLT_SRCOK
        BGT.B   RGNBLT_CLRMASK_NO_7             | if signed > -> RGNBLT_CLRMASK_NO_7
        MOVE    2(A4),D0                        | D0 := 2(A4)
        SUB     8(A5),D0                        | D0 -= 8(A5)
        MOVE    2(A2),D1                        | D1 := 2(A2)
        SUB     8(A3),D1                        | D1 -= 8(A3)
        SUB     D1,D0                           | D0 -= D1
        BLE.B   RGNBLT_SRCOK                    | if signed <= -> RGNBLT_SRCOK
        NEG     -0xB2(A6)                       | -0xB2(A6) = --0xB2(A6)
        BRA.B   RGNBLT_SRCOK                    | LOOP BACK FOR NEXT ROW
RGNBLT_CLRMASK_NO_7:
        NEG     -0xB0(A6)                       | -0xB0(A6) = --0xB0(A6)
        NEG.L   -0xB6(A6)                       | -0xB6(A6) = --0xB6(A6)
        NEG.L   -0xBA(A6)                       | -0xBA(A6) = --0xBA(A6)
        MOVE    -0x90(A6),-0xAC(A6)             | -0xAC(A6) := -0x90(A6)
        SUBQ.W  #0x1,-0xAC(A6)                  | -0xAC(A6) -= #0x1
        MOVE    -0x94(A6),-0xAE(A6)             | -0xAE(A6) := -0x94(A6)
        SUBQ.W  #0x1,-0xAE(A6)                  | -0xAE(A6) -= #0x1
| ----------------------------------------------
| CALC SHIFTCNT
| ------------------------------------------------------------
| DV IS POSITIVE, WE MUST TRANSFER UPSIDE-DOWN FROM BOTTOM.
| Called during boot.
RGNBLT_SRCOK:
        MOVE    2(A4),D6                        | D6 := 2(A4)
        SUB     8(A5),D6                        | D6 -= 8(A5)
        MOVE    2(A2),D1                        | D1 := 2(A2)
        SUB     8(A3),D1                        | D1 -= 8(A3)
        SUB     D1,D6                           | D6 -= D1
        ANDI    #0xF,D6                         | mask D6 with #0xF
        MOVE    -0xAC(A6),D0                    | D0 := -0xAC(A6)
        SUB     (A4),D0                         | D0 -= (A4)
        ADD     (A2),D0                         | D0 += (A2)
        SUB     6(A3),D0                        | D0 -= 6(A3)
        MULU    4(A3),D0                        | D0 = D0 *u 4(A3)
        MOVE.L  (A3),A0                         | A0 := (A3)
        ADDA.L  D0,A0                           | A0 += D0
        MOVE    -0x92(A6),D0                    | D0 := -0x92(A6)
        SUB     2(A4),D0                        | D0 -= 2(A4)
        ADD     2(A2),D0                        | D0 += 2(A2)
        SUB     8(A3),D0                        | D0 -= 8(A3)
        ADD     D6,D0                           | D0 += D6
        LSR     #0x4,D0                         | D0 >>= 4 (logical)
        ADD     D0,D0                           | D0 += D0
        ADDA.W  D0,A0                           | A0 += D0
        MOVE.L  A0,-0xAA(A6)                    | -0xAA(A6) := A0
| ------------------------------------
| CALC STARTING DSTADDR
| Called during boot.
RGNBLT_GETDST:
        MOVE    -0xAC(A6),D0                    | GET FIRST DST VERT
        SUB     6(A5),D0                        | D0 -= 6(A5)
        MULU    4(A5),D0                        | D0 = D0 *u 4(A5)
        MOVE.L  (A5),A0                         | STRIP BUFFER
        ADDA.L  D0,A0                           | ADD VERTICAL OFFSET
        MOVE    -0x92(A6),D0                    | GET DST LEFT
        SUB     8(A5),D0                        | D0 -= 8(A5)
        LSR     #0x4,D0                         | CONVERT DOTS TO WORDS
        ADD     D0,D0                           | DOUBLE FOR BYTES
        ADDA.W  D0,A0                           | ADD HORIZ OFFSET
        MOVE.L  A0,-0xA6(A6)                    | SAVE AS DSTADDR
        TST     -0xB2(A6)                       | BUMPING BACKWARD ?
        BPL.B   RGNBLT_GETDST_NO                | NO, CONTINUE
        MOVE    -0xA2(A6),D0                    | GET BUFFER SIZE
        ASL     #0x2,D0                         | D0 <<= 2 (arith)
        EXT.L    D0                             | CLEAR HI WORD
        ADD.L   D0,-0xA6(A6)                    | ADJUST DSTADDR
        ADD.L   D0,-0xAA(A6)                    | ADJUST SRCADDR
        ADD.L   D0,-0x9E(A6)                    | ADJUST MASKADDR
RGNBLT_GETDST_NO:
        MOVE.W   -172(FP),-188(FP)              | -188(FP) := curRow

| -------------------------------------------------------
| MAKE MASK BUFFER CURRENT FOR THIS VERTICAL.
| THEN SET UP AND DRAW CURRENT SCANLINE.
| HBUMPOK
| Called during boot (1,767 times in 30s trace).
RGNBLT_NXTMASK:
        JSR     RGNBLT_GOHOME_CONT(PC)          | MAKE MASK BUFFER CURRENT
        MOVE.L  -0xAA(A6),A3                    | INIT SRCPTR
        MOVE.L  -0xA6(A6),A5                    | INIT DSTPTR FOR ROW
        MOVE.L  -0x9E(A6),A4                    | INIT MASKPTR FOR ROW
        MOVE    -0xA2(A6),D2                    | INIT COUNT OF LONGS
        MOVE.L  -0xC0(A6),A2                    | GET MODE CASE JUMP
        JMP     (A2)                            | TAKE MODE JUMP
RGNBLT_NXTMASK_NEXT:
        MOVE.L  -0xB6(A6),D0                    | D0 := rowOffset
        ADD.L   D0,-0xAA(A6)                    | -0xAA(A6) += D0
        BRA.B   BUMPV                           | CONTINUE WITH NEXT ROW
RGNBLT_NXTMASK_NEXT_2:
        ADDQ.W  #0x4,D7                         | D7 += #0x4
        ANDI    #0x3F,D7                        | mask D7 with #0x3F
        MOVE.L  -0x40(A6,D7.W),D6               | D6 = mask-pattern word at A6[-64+D7]

| -----------------------------------------------------
| BUMP DESTINATION VERTICALLY AND LOOP FOR ALL ROWS
| Called during boot (1,767 times in 30s trace).
BUMPV:
        MOVE.L  -0xBA(A6),D0                    | GET DST ROWBYTES
        ADD.L   D0,-0xA6(A6)                    | BUMP DST TO NEXT ROW
        MOVE    -0xBC(A6),D0                    | GET CURRENT VERT
        ADD     -0xB0(A6),D0                    | BUMP UP OR DOWN A SCAN LINE
        MOVE    D0,-0xBC(A6)                    | UPDATE CURRENT VERT
        CMP     -0xAE(A6),D0                    | ARE WE AT THE LAST SCAN LINE ?
        BNE.B   RGNBLT_NXTMASK                  | NO, LOOP FOR ALL SCAN LINES
RGNBLT_DONE:
        MOVE.L  -0xCC(A6),A5                    | A5 := saveA5
        JSR     ShowCursor(PC)                  | call ShowCursor
RGNBLT_GOHOME:
        MOVE.L  -0x8C(A6),SP                    | SP := savedRgnSP
        MOVEM.L (SP)+,D0-D7/A1-A5               | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0x22,SP                        | pop parameter bytes from stack
        JMP     (A0)                            | RTS
RGNBLT_GOHOME_CONT:
        MOVE    -0x96(A6),D0                    | D0 = op index
| Raw instruction bytes: MOVE.W PC@(6,D0.W),D0 + JMP PC@(2,D0.W,D0)
| (computed jump table -- GNU as label math gets PC-rel displacement
| wrong for these back-to-back PC-indexed ops, so kept as .short).
        .short  0x303B, 0x0006                  | MOVE.W RGNBLT_GOHOME_CONT_2(PC,D0.W),D0
        .short  0x4EFB, 0x0002                  | JMP RGNBLT_GOHOME_CONT_2(PC,D0.W) via D0
RGNBLT_GOHOME_CONT_2:                           | computed-jump table base (16 bytes)
        .short  0xFFE2                          | $7A5A
        .short  0x0010, 0x001E                  | $7A5C
        .short  0x003A                          | $7A60
        .short  0x002C, 0x0074                  | $7A62
        .short  0x00AE                          | $7A66
        .short  0x00E8                          | $7A68
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x58(A6),A1                  | A1 = &regionA
        JSR     SeekRgn(PC)                     | advance region state to current row
        RTS                                     | return from RGNBLT_GOHOME_CONT_2
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x70(A6),A1                  | A1 = &regionB
        JSR     SeekRgn(PC)                     | advance region state to current row
        RTS                                     | return from RGNBLT_GOHOME_CONT_2
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x88(A6),A1                  | A1 = &rgnState
        JSR     SeekRgn(PC)                     | RESTORE CURSOR
        RTS                                     | return from RGNBLT_GOHOME_CONT_2
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x58(A6),A1                  | POINT TO STATE RECORD B
        JSR     SeekRgn(PC)                     | UPDATE RGNB
        MOVE    D1,-0xCE(A6)                    | -0xCE(A6) := D1
        LEA.L     -0x70(A6),A1                  | A1 = &regionB
        JSR     SeekRgn(PC)                     | advance region state to current row
        OR      D1,-0xCE(A6)                    | -0xCE(A6) |= D1
        BEQ.B   ABLOOP_DONE                     | NO, WE'RE DONE
        MOVE.L  -0x50(A6),A0                    | A0 := -0x50(A6)
        MOVE.L  -0x68(A6),A1                    | A1 := rgnPtrB
        MOVE.L  -0x9A(A6),A2                    | A2 := rgnBufPtr
        MOVE    -0xA2(A6),D1                    | D1 := wordCnt
ABLOOP:
        MOVE.L  (A0)+,D0                        | D0 := (A0)+
        AND.L   (A1)+,D0                        | D0 := D0 AND (A1)+
        MOVE.L  D0,(A2)+                        | (A2)+ := D0
        DBRA    D1,ABLOOP                       | loop D1 -> ABLOOP
ABLOOP_DONE:
        RTS                                     | return from ABLOOP_DONE
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x58(A6),A1                  | A1 = &regionA
        JSR     SeekRgn(PC)                     | advance region state to current row
        MOVE    D1,-0xCE(A6)                    | -0xCE(A6) := D1
        LEA.L     -0x88(A6),A1                  | A1 = &rgnState
        JSR     SeekRgn(PC)                     | advance region state to current row
        OR      D1,-0xCE(A6)                    | -0xCE(A6) |= D1
        BEQ.B   ACLOOP_DONE                     | NO, WE'RE DONE
        MOVE.L  -0x50(A6),A0                    | A0 := -0x50(A6)
        MOVE.L  -0x80(A6),A1                    | A1 := rgnPtrC
        MOVE.L  -0x9A(A6),A2                    | A2 := rgnBufPtr
        MOVE    -0xA2(A6),D1                    | D1 := wordCnt
ACLOOP:
        MOVE.L  (A0)+,D0                        | D0 := (A0)+
        AND.L   (A1)+,D0                        | D0 := D0 AND (A1)+
        MOVE.L  D0,(A2)+                        | (A2)+ := D0
        DBRA    D1,ACLOOP                       | loop D1 -> ACLOOP
ACLOOP_DONE:
        RTS                                     | return from ACLOOP_DONE
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x70(A6),A1                  | A1 = &regionB
        JSR     SeekRgn(PC)                     | advance region state to current row
        MOVE    D1,-0xCE(A6)                    | -0xCE(A6) := D1
        LEA.L     -0x88(A6),A1                  | A1 = &rgnState
        JSR     SeekRgn(PC)                     | advance region state to current row
        OR      D1,-0xCE(A6)                    | -0xCE(A6) |= D1
        BEQ.B   BCLOOP_DONE                     | NO, WE'RE DONE
        MOVE.L  -0x68(A6),A0                    | A0 := rgnPtrB
        MOVE.L  -0x80(A6),A1                    | A1 := rgnPtrC
        MOVE.L  -0x9A(A6),A2                    | A2 := rgnBufPtr
        MOVE    -0xA2(A6),D1                    | D1 := wordCnt
BCLOOP:
        MOVE.L  (A0)+,D0                        | D0 := (A0)+
        AND.L   (A1)+,D0                        | D0 := D0 AND (A1)+
        MOVE.L  D0,(A2)+                        | (A2)+ := D0
        DBRA    D1,BCLOOP                       | loop D1 -> BCLOOP
BCLOOP_DONE:
        RTS                                     | ALL 3 ARE RECT, DO NOTHING
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x58(A6),A1                  | POINT TO STATE RECORD A
        JSR     SeekRgn(PC)                     | UPDATE RGNA
        MOVE    D1,-0xCE(A6)                    | -0xCE(A6) := D1
        LEA.L     -0x70(A6),A1                  | A1 = &regionB
        JSR     SeekRgn(PC)                     | advance region state to current row
        OR      D1,-0xCE(A6)                    | -0xCE(A6) |= D1
        LEA.L     -0x88(A6),A1                  | A1 = &rgnState
        JSR     SeekRgn(PC)                     | advance region state to current row
        OR      D1,-0xCE(A6)                    | -0xCE(A6) |= D1
        BEQ.B   ABCLOOP_CONT                    | NO, WE'RE DONE
        MOVE.L  -0x50(A6),A0                    | A0 := -0x50(A6)
        MOVE.L  -0x68(A6),A1                    | A1 := rgnPtrB
        MOVE.L  -0x80(A6),A2                    | A2 := rgnPtrC
        MOVEA.L  -154(FP),A3                    | A3 := rgnBufPtr
        MOVE.W   -162(FP),D1                    | D1 := wordCnt
ABCLOOP:
        MOVE.L  (A0)+,D0                        | GET MASK WORD A
        AND.L   (A1)+,D0                        | AND WITH MASK WORD B
        AND.L   (A2)+,D0                        | AND WITH MASK WORD C
        MOVE.L  D0,(A3)+                        | SAVE TO MASK BUFFER
        DBF     D1,ABCLOOP                      | LOOP FOR ALL WORDS
ABCLOOP_CONT:
        RTS                                     | return to caller (@ $7B8C)
| ----------------------------------------------------------
| ABCDONE_MODE_TBL - indexed branch table for RgnBlt transfer modes
ABCDONE_MODE_TBL:                               | mode-dispatch table (16 bytes raw)
        .short  0x0010, 0x0040                  | $7B8E mode slot 0
        .short  0x0068, 0x0090                  | $7B92 mode slot 1
        .short  0x00BA                          | $7B96 mode slot 2
        .short  0x00D0                          | $7B98 mode slot 3
        .short  0x00DE                          | $7B9A mode slot 4
        .short  0x00EC                          | $7B9C mode slot 5
ABCDONE_LOOP:
        MOVE.L  -2(A3),D0                       | GET SRC FROM BITMAP
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA.W  -0xB2(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        MOVE.L  (A4),D1                         | GET MASK
        ADDA.W  -0xB2(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        AND.L   D1,D0                           | MASK SRC
        NOT.L   D1                              | FORM NOTMASK
        AND.L   (A5),D1                         | GET DST DATA
        OR.L    D1,D0                           | MERGE WITH SRC DATA
        MOVE.L  D0,(A5)                         | PUT RESULT IN DST
        ADDA.W  -0xB2(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBRA    D2,ABCDONE_LOOP                 | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT             | GO FOR NEXT ROW

| ----------------------------------------------------------
| ABCDONE_LOOP_2
ABCDONE_LOOP_2:
        MOVE.L  -2(A3),D0                       | GET SRC FROM BITMAP
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA.W  -0xB2(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A4),D0                         | AND WITH MASK
        ADDA.W  -0xB2(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        OR.L    D0,(A5)                         | OR RESULT INTO DST
        ADDA.W  -0xB2(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBRA    D2,ABCDONE_LOOP_2               | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT             | LOOP FOR NEXT ROW
ABCDONE_LOOP_3:
        MOVE.L  -2(A3),D0                       | GET SRC FROM BITMAP
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA.W  -0xB2(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A4),D0                         | AND WITH MASK
        ADDA.W  -0xB2(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        EOR.L   D0,(A5)                         | XOR RESULT INTO DST
        ADDA.W  -0xB2(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBRA    D2,ABCDONE_LOOP_3               | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT             | LOOP FOR NEXT ROW
ABCDONE_LOOP_4:
        MOVE.L  -2(A3),D0                       | GET SRC FROM BITMAP
        LSR.L   D6,D0                           | ALIGN TO DST
        SWAP    D0                              | PUT INTO HI HALF OF D0
        MOVE.L  (A3),D1                         | GET SRC FROM BITMAP
        ADDA.W  -0xB2(A6),A3                    | BUMP 4 BYTES RIGHT OR LEFT
        LSR.L   D6,D1                           | ALIGN TO DST
        MOVE    D1,D0                           | ASSEMBLE ONE LONG
        EOR.L   D7,D0                           | INVERT SRC IF MODE BIT 2 SET
        AND.L   (A4),D0                         | AND WITH MASK
        ADDA.W  -0xB2(A6),A4                    | BUMP 4 BYTES RIGHT OR LEFT
        NOT.L   D0                              | INVERT FOR BIC
        AND.L   D0,(A5)                         | BIC RESULT INTO DST
        ADDA.W  -0xB2(A6),A5                    | BUMP 4 BYTES RIGHT OR LEFT
        DBRA    D2,ABCDONE_LOOP_4               | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT             | LOOP FOR NEXT ROW

| -------------------------------------------------------
| MODE 8 OR 12: PATTERN --> DST (FILLING AREAS, DRAWING LINES)
| Called during boot (15,986 times in 30s trace).
ABCDONE_LOOP_5:
        MOVE.L  D6,D0                           | MASK8: GET PATTERN DATA
        MOVE.L  (A4)+,D1                        | GET MASK
        AND.L   D1,D0                           | MASK PATTERN DATA
        NOT.L   D1                              | MAKE NOTMASK
        AND.L   (A5),D1                         | GET DST DATA
        OR.L    D1,D0                           | MERGE WITH PAT DATA
        MOVE.L  D0,(A5)+                        | PUT RESULT TO DST
        DBRA    D2,ABCDONE_LOOP_5               | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW
ABCDONE_LOOP_6:
        MOVE.L  D6,D0                           | MASK9: GET PATTERN DATA
        AND.L   (A4)+,D0                        | MASK PATTERN DATA
        OR.L    D0,(A5)+                        | OR RESULT INTO DST
        DBRA    D2,ABCDONE_LOOP_6               | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW
ABCDONE_LOOP_7:
        MOVE.L  D6,D0                           | MASK10: GET PATTERN DATA
        AND.L   (A4)+,D0                        | MASK PATTERN DATA
        EOR.L   D0,(A5)+                        | XOR RESULT INTO DST
        DBRA    D2,ABCDONE_LOOP_7               | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW
ABCDONE_LOOP_8:
        MOVE.L  D6,D0                           | MASK11: GET PATTERN DATA
        AND.L   (A4)+,D0                        | MASK PATTERN DATA
        NOT.L   D0                              | jump via A0
        AND.L   D0,(A5)+                        | BIC RESULT INTO DST
        DBRA    D2,ABCDONE_LOOP_8               | LOOP ALL LONGS THIS ROW
        BRA.W   RGNBLT_NXTMASK_NEXT_2           | LOOP BACK FOR NEXT ROW
