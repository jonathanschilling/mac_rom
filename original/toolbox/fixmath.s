| Fixed-point arithmetic -- LongMul, FixMul, FixRatio, HiWord, LoWord, FixRound
|
| The 64K ROM links these Toolbox Utilities between QuickDraw's Util and
| GrafAsm (QuickDraw is their main user); the Mac Plus has them, with the
| newer Fract routines, in toolbox/fixmath.s after the Munger code.
| LongMul is a signed 32 x 32 -> 64 bit multiply, FixMul multiplies two
| Fixed (16.16) values, FixRatio divides two integers into a Fixed,
| HiWord/LoWord return the halves of a long, FixRound rounds a Fixed.
|
| References: Inside Macintosh Vol I, Ch 16: Toolbox Utilities

| ----------------------------------------------------------
| LongMul -- 64-bit signed multiply of two 32-bit Fixed values
|
| Stack frame on entry (after LINK):
|   8(A6)  result ptr (8-byte 64-bit product output)
|   12(A6) operand B (4-byte signed Fixed)
|   16(A6) operand A (4-byte signed Fixed)
|
| Computes A*B as a 64-bit signed product. Called by FixMul and by
| InitOval (DrawArc.s).
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
        MOVE.L  (SP)+,(SP)                      | pop return addr over params (strip 4 bytes)
        RTS                                     | return Fixed result
| ----------------------------------------------------------
|
| _HiWord ($A86A): return the high-order word of a long
| Pascal: FUNCTION HiWord(x: LongInt): INTEGER;
| Entry: 4(SP) = x; result word at 8(SP)
|
HiWord:
        MOVE    4(SP),8(SP)                     | result := high word of x
        MOVE.L  (SP)+,(SP)                      | pop return addr over x (strip 4 bytes)
        RTS                                     | return from HiWord
| ----------------------------------------------------------
|
| _LoWord ($A86B): return the low-order word of a long
| Pascal: FUNCTION LoWord(x: LongInt): INTEGER;
| Entry: 4(SP) = x; result word at 8(SP)
|
LoWord:
        MOVE    6(SP),8(SP)                     | result := low word of x
        MOVE.L  (SP)+,(SP)                      | pop return addr over x (strip 4 bytes)
        RTS                                     | return from LoWord
| ----------------------------------------------------------
|
| _FixRound ($A86C): round a Fixed number to an integer
| Pascal: FUNCTION FixRound(x: Fixed): INTEGER;
| Entry: 4(SP) = x; result word at 8(SP)
| Adds 0.5 ($8000) to x (-0.5 if x < 0) and returns the high word. As the
| high word of a negative Fixed is its floor, negative x yield floor(x-0.5)
| (IM I: FixRound is meant for positive numbers). No overflow check.
|
FixRound:
        MOVE.L  #0x8000,D0                      | D0 = $8000 = 0.5 (rounding bias)
        TST.L   4(SP)                           | x negative?
        BPL.B   FIXRATIO_OVFL                   | no -> add +0.5
        NEG.L   D0                              | yes -> add -0.5
FIXRATIO_OVFL:
        ADD.L   D0,4(SP)                        | x := x + bias
        MOVE    4(SP),8(SP)                     | result := high word (integer part)
        MOVE.L  (SP)+,(SP)                      | pop return addr over x (strip 4 bytes)
        RTS                                     | return from FixRound

