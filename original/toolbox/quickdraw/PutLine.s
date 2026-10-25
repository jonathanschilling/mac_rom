| -----------------------------------------------------------
|
| --> PUTLINE.TEXT
|
| Decompose a line segment into a list of inversion points.

PutLine:
        LINK.W   FP,#-4                         | local for length
        MOVEM.L D3-D7/A2-A4,-(SP)               | SAVE REGS, 8*4 ==> 32
        MOVE    26(A6),D2                       | D2 = newPt.h
        MOVE    22(A6),D4                       | D4 = oldPt.h
        CMP     D2,D4                           | IS THIS A VERTICAL LINE ?
        BEQ.W   PUTLINE_GOHOME                  | YES, IGNORE IT
        MOVE    D2,D0                           | GET H1
        SUB     D4,D0                           | SUBTRACT H2
        BPL.W   VSET_LOOP_END                   | BR IF DH POS
        NEG     D0                              | ELSE TAKE ABSOLUTE VALUE
VSET_LOOP_END:
        MOVE    24(A6),D1                       | D1 = newPt.v
        SUB     20(A6),D1                       | dv = newPt.v - oldPt.v
        BPL.W   VSET_CONT_3                     | BR IF DV POS
        NEG     D1                              | ELSE TAKE ABSOLUTE VALUE
VSET_CONT_3:
        CMP     D1,D0                           | IS DH <= DV ?
        BLE.B   DVPOS_OK                        | YES, CONTINUE
        MOVE    D1,D0                           | NO, PUT MIN(DH,DV) INTO D0

DVPOS_OK:
        ADDQ.W  #0x1,D0                         | add 1 to min(dh,dv) for endpoints
        LSL     #0x3,D0                         | times 8 for bytesNeeded
        MOVE.L  16(A6),A3                       | A3 = destination point buffer handle
        MOVE.L  12(A6),A4                       | A4 = ptr to buffer index variable
        ADD     (A4),D0                         | newSize = index + bytesNeeded
        MOVE.L  8(A6),A0                        | A0 = ptr to bufMax
        CMP     (A0),D0                         | need to grow dstBuf?
        BLE.B   DVPOS_NO                        | no -> continue
        ADDI    #0x200,D0                       | expand by 512-byte chunks
        MOVE    D0,(A0)                         | update bufMax
        MOVE.L  A3,-(SP)                        | push dstBuf handle for SetHSize
        MOVE    D0,-(SP)                        | push new bufMax
        JSR     SetHSize(PC)                    | grow the buffer
        MOVE    26(A6),D2                       | restore pt1.h clobbered by SetHSize
DVPOS_NO:
        MOVE.L  (A3),A3                         | DE-REFERENCE DSTHANDLE
        ADDA.W  (A4),A3                         | add index for current buf ptr
        MOVE    24(A6),D1                       | D1 = pt1.v
        MOVE    20(A6),D3                       | D3 = pt2.v
        CMP     D1,D3                           | horizontal line?
        BNE.B   PUTLINE_SLANTED                 | no -> handle slope
        MOVE    D1,(A3)+                        | put V1 vert coord
        MOVE    D2,(A3)+                        | put H1 horiz coord
        MOVE    D3,(A3)+                        | put V2 vert coord
        MOVE    D4,(A3)+                        | put H2 horiz coord
        BRA.W   NOCHNG_EXIT                     | done -> update index
PUTLINE_SLANTED:
        BGT.B   NOSWAP                          | already in vertical order -> skip
        EXG     D1,D3                           | sort points by vertical
        EXG     D2,D4                           | jump via A0
NOSWAP:
        MOVE    D1,D6                           | init V to topV
        CLR.L   -(SP)                           | reserve FixRatio result slot
        MOVE    D4,-(SP)                        | push botH
        SUB     D2,(SP)                         | (SP) -= D2
        MOVE    D3,-(SP)                        | push botV
        SUB     D1,(SP)                         | (SP) -= D1
        JSR     FixRatio(PC)                    | compute fixed-point slope
        MOVE.L  (SP)+,D7                        | D7 = slope (16.16 fixed)
        MOVE    D2,-4(A6)                       | local horiz.int = topH
        MOVE    #-0x8000,-2(A6)                 | local horiz.frac = 0.5
        MOVE.L  D7,D0                           | D0 = copy of slope
        ASR.L   #0x1,D0                         | D0 = slope / 2
        ADD.L   D0,-4(A6)                       | -4(A6) += D0
        TST.L   D7                              | slope sign?
        BMI.B   NOSWAP_OK                       | slope < 0 -> handle negative
        CMPI.L  #0x00010000,D7                  | D7 >= +65536?
        BGE.B   NOSWAP_NO                       | yes -> overflow: skip half
        ADD.L   D7,-4(A6)                       | no -> add D7 for small deltas
        BRA.B   NOSWAP_NO                       | skip neg-slope handling
NOSWAP_OK:
        CMPI.L  #0xFFFF0000,D7                  | D7 <= -65536?
        BGE.B   NOSWAP_NO                       | no -> skip rounding
        ADDQ.W  #0x1,-4(A6)                     | yes -> round up (towards zero)
NOSWAP_NO:
        MOVE    D2,D5                           | oldH = topH
LOOP:
        CMP     -4(A6),D5                       | oldH == new horiz.int?
        BEQ.B   NOCHNG                          | yes -> no slab to emit
        MOVE    D6,(A3)+                        | put vert coord (slab top)
        MOVE    D5,(A3)+                        | put oldH
        MOVE    -4(A6),D5                       | oldH = new horiz.int
        MOVE    D6,(A3)+                        | put vert coord (slab bot)
        MOVE    D5,(A3)+                        | put new horiz coord
NOCHNG:
        ADDQ.W  #0x1,D6                         | advance vert to next scanline
        ADD.L   D7,-4(A6)                       | -4(A6) += D7
        CMP     D6,D3                           | reached bottom?
        BNE.B   LOOP                            | no -> next slab
        CMP     D4,D5                           | oldH == botH (no last slab)?
        BEQ.B   NOCHNG_EXIT                     | yes -> done
        MOVE    D6,(A3)+                        | emit final slab vert
        MOVE    D5,(A3)+                        | emit final slab oldH
        MOVE    D6,(A3)+                        | emit final slab vert
        MOVE    D4,(A3)+                        | emit final slab botH
NOCHNG_EXIT:
        MOVE.L  16(A6),A0                       | A0 = dst handle
        SUBA.L  (A0),A3                         | A3 = bytes added (index delta)
        MOVE    A3,(A4)                         | update index
PUTLINE_GOHOME:
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | jump via A0
        ADDA.W  #0x14,SP                        | pop 20 bytes of params
        JMP     (A0)                            | RTS
