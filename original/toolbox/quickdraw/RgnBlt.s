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
        JSR     DrawControls(PC)                | FontMgr cursor stub (legacy)
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
        JSR     FMQD_ShowCursor(PC)             | call FMQD_ShowCursor
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
        RTS                                     | return to caller
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x70(A6),A1                  | A1 = &regionB
        JSR     SeekRgn(PC)                     | advance region state to current row
        RTS                                     | return to caller
        MOVE    -0xBC(A6),D0                    | D0 := -0xBC(A6)
        LEA.L     -0x88(A6),A1                  | A1 = &rgnState
        JSR     SeekRgn(PC)                     | RESTORE CURSOR
        RTS                                     | return to caller
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
        RTS                                     | return to caller
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
        RTS                                     | return to caller
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
StdRRect:
        LINK    A6,#0x0                         | set up stack frame, reserve 0x0 locals
        MOVEM.L D7/A3-A4,-(SP)                  | save scratch regs to stack
        MOVE.B  16(A6),D7                       | D7 := maskRgn
        JSR     CheckPic(PC)                    | call CheckPic
        BLE.W   STDRRECT_NOTPIC                 | if signed <= -> STDRRECT_NOTPIC
        MOVE.B  D7,-(SP)                        | push D7
        JSR     PutPicVerb(PC)                  | call PutPicVerb
        MOVE.L  0x5C(A3),A0                     | A0 := 0x5C(A3)
        MOVE.L  (A0),A0                         | A0 := (A0)
        MOVE.L  8(A6),D0                        | D0 := pat
        CMP.L   0x4C(A0),D0                     | compare D0 with 0x4C(A0)
        BEQ.B   OVALOK                          | if zero -> OVALOK
        MOVE.L  D0,0x4C(A0)                     | 0x4C(A0) := D0
        MOVE.L  D0,-(SP)                        | push D0
        MOVE.B  #0xB,-(SP)                      | push #0xB
        JSR     PutPicByte(PC)                  | call PutPicByte
        JSR     PutPicLong(PC)                  | call PutPicLong
OVALOK:
        MOVEQ.L #0x40,D0                        | D0 := #0x40
        ADD     D7,D0                           | D0 += D7
        MOVE.B  D0,-(SP)                        | push D0
        MOVE.L  12(A6),-(SP)                    | -(SP) := mode
        JSR     PutPicRect(PC)                  | call PutPicRect
STDRRECT_NOTPIC:
        MOVE.L  12(A6),-(SP)                    | -(SP) := mode
        TST.B   D7                              | test D7
        BNE.B   STDRRECT_NOTFRM                 | if non-zero -> STDRRECT_NOTFRM
        TST.L   0x60(A3)                        | test 0x60(A3)
        BEQ.B   STDRRECT_NOTRGN                 | if zero -> STDRRECT_NOTRGN
        MOVE.L  12(A6),-(SP)                    | -(SP) := mode
        MOVE.L  8(A6),-(SP)                     | -(SP) := pat
        MOVE.L  -0x94(A4),-(SP)                 | push -0x94(A4)
        PEA.L     -0x96(A4)                     | push effective addr -0x96(A4)
        PEA.L     -0x98(A4)                     | push effective addr -0x98(A4)
        JSR     RR_OVAL_HELPER(PC)              | call RR_OVAL_HELPER
STDRRECT_NOTRGN:
        MOVE.B  #0x1,-(SP)                      | push #0x1
        BRA.B   STDRRECT_DOIT                   | jump to STDRRECT_DOIT
STDRRECT_NOTFRM:
        CLR.B   -(SP)                           | push zero word
STDRRECT_DOIT:
        MOVE.L  8(A6),-(SP)                     | -(SP) := pat
        JSR     PushVerb(PC)                    | pc-relative jsr (was raw .short pair)
        CLR     -(SP)                           | push zero word
        MOVE    #0x168,-(SP)                    | push #0x168
        JSR     DrawArc(PC)                     | call DrawArc
        MOVEM.L (SP)+,D7/A3-A4                  | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0xA,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS

| ---------------------------------------------------------------
| PROCEDURE CallRRect(r: Rect; ovWd,ovHt: INTEGER);
| code shared by FrameRoundRect, PaintRoundRect, EraseRoundRect,
| InvertRoundRect, and FillRoundRect.
| enter with verb in D0.
| Called during boot.
CallRRect:
        MOVE.L  (SP)+,A0                        | pop return address into A0
        MOVE.L  (SP)+,D1                        | pop D1
        MOVE.L  (SP)+,A1                        | pop A1
        MOVE.B  D0,-(SP)                        | push D0
        MOVE.L  A1,-(SP)                        | push A1
        MOVE.L  D1,-(SP)                        | push D1
        MOVE.L  A0,-(SP)                        | push A0
        MOVE.L  (A5),A0                         | A0 := (A5)
        MOVE.L  (A0),A0                         | A0 := (A0)
        MOVE.L  0x68(A0),D0                     | D0 := 0x68(A0)
        LEA     StdRRect(PC),A0                 | A0 = &StdRRect(PC)
        BEQ.B   CALLRRECT_CONT                  | if zero -> CALLRRECT_CONT
        MOVE.L  D0,A0                           | A0 := D0
        MOVE.L  12(A0),A0                       | A0 := 12(A0)
CALLRRECT_CONT:
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| PROCEDURE FrameRoundRect(r: Rect; ovWd, ovHt: INTEGER);
| Plus equivalent: RRects.s 95.
FrameRoundRect:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE PaintRoundRect(r: Rect; ovWd, ovHt: INTEGER);
| Plus equivalent: RRects.s 103.
PaintRoundRect:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE EraseRoundRect(r: Rect; ovWd, ovHt: INTEGER);
| Plus equivalent: RRects.s 112.
EraseRoundRect:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE InvertRoundRect(r: Rect; ovWd, ovHt: INTEGER);
| Plus equivalent: RRects.s 121.
InvertRoundRect:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallRRect(PC)                   | SHARE COMMON CODE

| ----------------------------------------------------------
| PROCEDURE FillRoundRect(r: Rect; ovWd, ovHt: INTEGER; pat: Pattern);
| Plus equivalent: RRects.s 130.
FillRoundRect:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallRRect(PC)                   | SHARE COMMON CODE
StdOval:
        LINK    A6,#-0x4                        | set up stack frame, reserve -0x4 locals
        MOVEM.L D7/A3-A4,-(SP)                  | save scratch regs to stack
        MOVE.B  12(A6),D7                       | D7 := mode
        JSR     CheckPic(PC)                    | call CheckPic
        BLE.W   STDOVAL_NOTPIC                  | if signed <= -> STDOVAL_NOTPIC
        MOVE.B  D7,-(SP)                        | push D7
        JSR     PutPicVerb(PC)                  | call PutPicVerb
        MOVEQ.L #0x50,D0                        | D0 := #0x50
        ADD     D7,D0                           | D0 += D7
        MOVE.B  D0,-(SP)                        | push D0
        MOVE.L  8(A6),-(SP)                     | -(SP) := pat
        JSR     PutPicRect(PC)                  | call PutPicRect
STDOVAL_NOTPIC:
        MOVE.L  8(A6),A0                        | A0 := pat
        MOVE    6(A0),D0                        | D0 := 6(A0)
        SUB     2(A0),D0                        | D0 -= 2(A0)
        MOVE    D0,-2(A6)                       | -2(A6) := D0
        MOVE    4(A0),D0                        | D0 := 4(A0)
        SUB     (A0),D0                         | D0 -= (A0)
        MOVE    D0,-4(A6)                       | -4(A6) := D0
        MOVE.L  A0,-(SP)                        | push A0
        TST.B   D7                              | test D7
        BNE.B   NOTFR                           | if non-zero -> NOTFR
        TST.L   0x60(A3)                        | test 0x60(A3)
        BEQ.B   STDOVAL_NOTRGN                  | if zero -> STDOVAL_NOTRGN
        MOVE.L  A0,-(SP)                        | push A0
        MOVE.L  -4(A6),-(SP)                    | push -4(A6)
        MOVE.L  -0x94(A4),-(SP)                 | push -0x94(A4)
        PEA.L     -0x96(A4)                     | push effective addr -0x96(A4)
        PEA.L     -0x98(A4)                     | push effective addr -0x98(A4)
        JSR     RR_OVAL_HELPER(PC)              | call RR_OVAL_HELPER
STDOVAL_NOTRGN:
        MOVE.B  #0x1,-(SP)                      | push #0x1
        BRA.B   STDOVAL_DOIT                    | LOOP BACK FOR NEXT ROW
NOTFR:
        CLR.B   -(SP)                           | push zero word
STDOVAL_DOIT:
        MOVE.L  -4(A6),-(SP)                    | push -4(A6)
        JSR     PushVerb(PC)                    | pc-relative jsr (was raw .short pair)
        CLR     -(SP)                           | push zero word
        MOVE    #0x168,-(SP)                    | push #0x168
        JSR     DrawArc(PC)                     | call DrawArc
        MOVEM.L (SP)+,D7/A3-A4                  | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDQ.W  #0x6,SP                         | pop parameter bytes from stack
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| CallOval -- verb-dispatch helper used by Frame/Paint/Erase/Invert/
| FillOval. Pops verb in D0, looks up ovalProc via QDProcs or
| falls back to StdOval. Plus equivalent: Ovals.s 151.
CallOval:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF RECT
        MOVE.B  D0,-(SP)                        | PUSH VERB
        MOVE.L  A1,-(SP)                        | PUSH ADDR OF RECT
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  0x68(A0),D0                     | IS GRAFPROCS NIL ?
        LEA     StdOval(PC),A0                  | _StdOval (ovalProc)
        BEQ.B   CALLOVAL_USESTD                 | YES, USE STD PROC
        MOVE.L  D0,A0                           | NO, GET PROC PTR
        MOVE.L  16(A0),A0                       | GET ovalProc
CALLOVAL_USESTD:
        JMP     (A0)                            | USESTD: GO TO IT

| ----------------------------------------------------------
| PROCEDURE FrameOval(r: Rect); Plus equivalent: Ovals.s 100.
FrameOval:
        MOVEQ.L #0x0,D0                         | VERB = FRAME
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE PaintOval(r: Rect); Plus equivalent: Ovals.s 108.
PaintOval:
        MOVEQ.L #0x1,D0                         | VERB = PAINT
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE EraseOval(r: Rect); Plus equivalent: Ovals.s 116.
EraseOval:
        MOVEQ.L #0x2,D0                         | VERB = ERASE
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE InvertOval(r: Rect); Plus equivalent: Ovals.s 124.
InvertOval:
        MOVEQ.L #0x3,D0                         | VERB = INVERT
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| PROCEDURE FillOval(r: Rect; pat: Pattern); Plus equivalent: Ovals.s 132.
FillOval:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,A1                        | POP ADDR OF PATTERN
        MOVE.L  A0,-(SP)                        | RESTORE RETURN ADDR
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     0x28(A0),A0                   | POINT TO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | COPY PAT INTO FILLPAT
        MOVE.L  (A1)+,(A0)+                     | ALL EIGHT BYTES
        MOVEQ.L #0x4,D0                         | VERB = FILL
        JMP     CallOval(PC)                    | SHARE COMMON CODE

| ----------------------------------------------------------
| RR_OVAL_HELPER -- internal RoundRect/Oval drawing helper.
| Called from StdRRect (line 365) and StdOval (line 480).
| Takes 3 params: rect handle (16(A6)) + 2 offset words
| (8(A6), 12(A6)) -- used to scale dimensions for oval overlay.
| NOT _TEDispose -- that lives in textedit.s. Earlier mass-rename
| pass mislabeled this.
RR_OVAL_HELPER:
        LINK    A6,#-0x32                       | set up stack frame
        MOVEM.L D0-D7/A1-A5,-(SP)               | save scratch regs to stack
        MOVE.L  16(A6),A3                       | A3 := maskRgn
        MOVE.L  (A3),A3                         | A3 := (A3)
        MOVE.L  A3,A2                           | A2 := A3
        MOVE.L  12(A6),A0                       | A0 := mode
        ADDA.W  (A0),A3                         | A3 += (A0)
        MOVE.L  A2,A1                           | A1 := A2
        MOVE.L  8(A6),A0                        | A0 := pat
        ADDA.W  (A0),A1                         | A1 += (A0)
        MOVE.L  24(A6),-(SP)                    | -(SP) := srcRgn
        PEA.L     -0x2A(A6)                     | push effective addr -0x2A(A6)
        MOVE    22(A6),-(SP)                    | push 22(A6)
        MOVE    20(A6),-(SP)                    | -(SP) := dstRgn
        JSR     InitOval(PC)                    | call InitOval
        MOVE    -0x24(A6),-0x30(A6)             | jump via A0
        MOVE    -0x20(A6),-0x32(A6)             | -0x32(A6) := -0x20(A6)
        MOVE    20(A6),D0                       | D0 := dstRgn
        ASR     #0x1,D0                         | D0 >>= 1 (arith)
        ADD     -0x2A(A6),D0                    | D0 += -0x2A(A6)
        MOVE    D0,-0x2C(A6)                    | -0x2C(A6) := D0
        MOVE.L  24(A6),A0                       | A0 := srcRgn
        ADD     4(A0),D0                        | D0 += 4(A0)
        SUB     (A0),D0                         | D0 -= (A0)
        SUB     20(A6),D0                       | D0 -= 20(A6)
        MOVE    D0,-0x2E(A6)                    | -0x2E(A6) := D0
        MOVE    -0x2A(A6),D6                    | D6 := -0x2A(A6)
        MOVE    -0x30(A6),D5                    | D5 := -0x30(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x32(A6),D5                    | D5 := -0x32(A6)
        JSR     PUTPT(PC)                       | call PUTPT
NXTVERT:
        CMP     -0x2C(A6),D6                    | compare D6 with -0x2C(A6)
        BLT.B   PUTOVAL_YESBUMP                 | if signed < -> PUTOVAL_YESBUMP
        CMP     -0x2E(A6),D6                    | compare D6 with -0x2E(A6)
        BLT.B   PUTOVAL_YESBUMP_SKIP            | if signed < -> PUTOVAL_YESBUMP_SKIP
PUTOVAL_YESBUMP:
        PEA.L     -0x2A(A6)                     | push effective addr -0x2A(A6)
        MOVE    D6,-(SP)                        | push D6
        JSR     BumpOval(PC)                    | call BumpOval
        MOVE    -0x24(A6),D5                    | D5 := -0x24(A6)
        CMP     -0x30(A6),D5                    | compare D5 with -0x30(A6)
        BEQ.B   PUTOVAL_YESBUMP_OK              | if zero -> PUTOVAL_YESBUMP_OK
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x30(A6),D5                    | D5 := -0x30(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x24(A6),-0x30(A6)             | -0x30(A6) := -0x24(A6)
PUTOVAL_YESBUMP_OK:
        MOVE    -0x20(A6),D5                    | D5 := -0x20(A6)
        CMP     -0x32(A6),D5                    | compare D5 with -0x32(A6)
        BEQ.B   PUTOVAL_YESBUMP_SKIP            | if zero -> PUTOVAL_YESBUMP_SKIP
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x32(A6),D5                    | D5 := -0x32(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x20(A6),-0x32(A6)             | -0x32(A6) := -0x20(A6)
PUTOVAL_YESBUMP_SKIP:
        ADDQ.W  #0x1,D6                         | D6 += #0x1
        CMP     -0x28(A6),D6                    | compare D6 with -0x28(A6)
        BLT.B   NXTVERT                         | if signed < -> NXTVERT
        MOVE    -0x30(A6),D5                    | D5 := -0x30(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        MOVE    -0x32(A6),D5                    | D5 := -0x32(A6)
        JSR     PUTPT(PC)                       | call PUTPT
        SUBA.L  A2,A3                           | A3 -= A2
        MOVE.L  12(A6),A0                       | A0 := mode
        MOVE    A3,(A0)                         | (A0) := A3
        MOVEM.L (SP)+,D0-D7/A1-A5               | restore scratch regs from stack
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address into A0
        ADDA.W  #0x14,SP                        | pop parameter bytes from stack
        JMP     (A0)                            | RTS

| -----------------------------------------------------------------------
| Local routine to Append a point to the end of the saved points buffer,
| extending buffer if necessary. If pt is a duplicate of the last pt,
| cancel both instead.
| INPUTS: D5: HORIZ COORD
| D6: VERT COORD
| A1: BUFLIMIT GETS EXPANDED AND RELOCATED
| A2: BUFSTART GETS RELOCATED
| A3: BUFPTR GETS BUMPED AND RELOCATED
| ALTERS: A1,A2,A3, VAR SIZE
| Called during boot.
PUTPT:
        CMPA.L  A1,A3                           | compare A3 with A1
        BLT.B   PUTOVAL_SIZEOK                  | if signed < -> PUTOVAL_SIZEOK
        SUBA.L  A2,A3                           | A3 -= A2
        SUBA.L  A2,A1                           | A1 -= A2
        ADDA.W  #0x400,A1                       | A1 += #0x400
        MOVEM.L D0-A3,-(SP)                     | save scratch regs to stack
        MOVE.L  8(A6),A0                        | PUT HORIZ COORD
        MOVE    A1,(A0)                         | (A0) := A1
        MOVE.L  16(A6),-(SP)                    | -(SP) := maskRgn
        MOVE    A1,-(SP)                        | push A1
        JSR     SetHSize(PC)                    | call SetHSize
        MOVEM.L (SP)+,D0-A3                     | restore scratch regs from stack
        MOVE.L  16(A6),A2                       | A2 := maskRgn
        MOVE.L  (A2),A2                         | A2 := (A2)
        ADDA.L  A2,A3                           | A3 += A2
        ADDA.L  A2,A1                           | A1 += A2
| -------------------------------------------------------------------
| ADD NEW POINT TO THE SAVE BUFFER UNLESS IT MATCHED THE PREVIOUS PT.
| DELETE DUPLICATE POINTS SINCE THEY WILL CANCEL EACH OTHER ANYWAY.
| Called during boot.
PUTOVAL_SIZEOK:
        CMPA.L  A2,A3                           | compare A3 with A2
        BEQ.B   APPEND                          | if zero -> APPEND
        CMP     -2(A3),D5                       | compare D5 with -2(A3)
        BNE.B   APPEND                          | if non-zero -> APPEND
        CMP     -4(A3),D6                       | compare D6 with -4(A3)
        BNE.B   APPEND                          | if non-zero -> APPEND
        SUBQ.W  #0x4,A3                         | A3 -= #0x4
        RTS                                     | return to caller

| ----------------------------------------------------------
| APPEND -- append (vert,horiz) point pair to region build buffer.
| Used by PUTOVAL_SIZEOK helper in RgnBlt.s. In Plus this small
| helper lives at the tail of PutOval.s as `APPEND:`.
| Inputs: D6 = vert, D5 = horiz, A3 = bufPtr.
APPEND:
        MOVE    D6,(A3)+                        | PUT VERT COORD
        MOVE    D5,(A3)+                        | PUT HORIZ COORD
        RTS                                     | RETURN
