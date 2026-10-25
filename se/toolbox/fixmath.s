| Toolbox Utilities: fixed-point arithmetic
|
| This file contains, in ROM order:
| - _LongMul, _FracMul, _FixMul and their shared 32 x 32-bit multiply
| - _FracDiv, _FixDiv (shared shift-and-subtract division)
| - _FracSqrt
| - _FixRatio, _LoWord, _HiWord, _FixRound
| - _FracCos, _FracSin (shared octant reduction and polynomials)
| - _FixATan2
| - Fixed/Fract <-> extended: _Fix2X, _Frac2X, _X2Fix, _X2Frac
| - Fixed/Fract/LongInt: _Fix2Long, _Frac2Fix, _Long2Fix, _Fix2Frac
| Apple's source is the fixed-point part of Munger.a (System 7.1:
| Toolbox/Munger/Munger.a, formerly AdMath.ASM; that later copy has 68020
| versions of LongMul/FixMul/FracMul/FixRatio and some fixes noted below).
| Most routines use the Pascal stack convention through FIXPT_ENTRY
| (Apple: StdEntry): LINK A6,#0 and save D0-D6/A1, so the parameters start
| at $08(A6) and all registers except A0 are preserved. Fixed/Fract
| results that overflow are pinned to $7FFFFFFF (positive) or $80000000
| (negative).
|
| Fixed-point formats (Inside Macintosh I and IV):
| Fixed = 32-bit signed, 16.16 (high word = integer, low word = fraction)
| Fract = 32-bit signed, 2.30 (2 integer bits, 30 fraction bits)
| Extended = 80-bit SANE extended (1 sign + 15 exponent + 64 mantissa)
|
| References:
| Inside Macintosh Vol I, Toolbox Utilities (FixRatio, FixMul, FixRound,
|   HiWord, LoWord, LongMul: I-467..I-472)
| Inside Macintosh Vol IV, Toolbox Utilities (Fract, FracMul, FixDiv,
|   FracDiv, FracSqrt, FracSin, FracCos, FixATan2, conversions)

| ----------------------------------------------------------
| LongMul ($A867) - 32x32 signed multiply yielding 64-bit result.
| Stack: multiplicand(+$0C), multiplier(+$10), result ptr(+$08).
| Result is two longs (hi:lo) stored at the pointer.
| ----------------------------------------------------------
LONGMUL:
    BSR.W       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEQ.L     #0x1,D5                         | D5=1: LongMul mode (64-bit result)
    MOVEM.L     0xC(A6),D1-D2                   | D1=multiplicand, D2=multiplier
    BSR.W       FIXMUL_CONT_8                   | take absolute values, track sign in D6
    BRA.B       FIXMUL_CONT_2                   | enter shared multiply core
| ----------------------------------------------------------
| LONGMUL_EXIT - LongMul epilogue: apply sign to 64-bit result and
| store hi:lo result at caller's pointer.
| ----------------------------------------------------------
LONGMUL_EXIT:
    TST.B       D6                              | check combined sign flag
    BPL.B       LONGMUL_NO                      | positive result: no negation needed
    NEG.L       D4                              | negate low 32 bits
    NEGX.L      D0                              | negate high 32 bits with borrow
LONGMUL_NO:
    MOVEA.L     0x8(A6),A0                      | A0 = result pointer from stack
    MOVE.L      D0,(A0)+                        | store high 32 bits of 64-bit product
    MOVE.L      D4,(A0)                         | store low 32 bits of 64-bit product
    MOVE.W      #0xC,0x8(A6)                    | param size = 12 bytes to strip
    BRA.W       FIXMUL_EXIT_4                   | shared epilogue: restore and return
| ----------------------------------------------------------
| RestoreEntries / FRACMUL ($A84D) - 16.16 fixed-point divide.
| Computes (D1/D2) as Fixed result. D5=-1 selects divide path.
| ----------------------------------------------------------
| Called by: FRACSIN_POLY_TERM, ATAN_POLY_LOOP, FRACSIN_REDUCED, ATAN_DO_FRACDIV
FRACMUL:
    BSR.W       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEQ.L     #-0x1,D5                        | D5=-1: FixDiv mode (shift result left 2)
    BRA.B       FIXMUL_CONT                     | enter shared multiply/divide core
| ----------------------------------------------------------
| FixMul ($A868) - 16.16 fixed-point multiply.
| Computes (D1*D2) >> 16 as Fixed result. D5=0 selects multiply.
| ----------------------------------------------------------
FIXMUL:
    BSR.W       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEQ.L     #0x0,D5                         | D5=0: FixMul mode (extract middle 32 bits)
FIXMUL_CONT:
    BSR.W       FIXMUL_CONT_7                   | load params into D1-D2, set sign in D6
FIXMUL_CONT_2:
    MOVEQ.L     #0x1,D4                         | D4 = 0x00010000 (Fixed 1.0)
    SWAP.W      D4                              | shift to high word
    CMP.L       D4,D1                           | is multiplicand exactly 1.0?
    BNE.B       FIXMUL_NO                       | no: check multiplier
    MOVE.L      D2,D1                           | yes: result = other operand
    BRA.B       FIXMUL_NO_2                     | shortcut: no multiply needed
| ----------------------------------------------------------
| FIXMUL_NO - Check if multiplier is exactly 1.0 (0x10000).
| If so, the result is just the multiplicand.
| ----------------------------------------------------------
FIXMUL_NO:
    CMP.L       D4,D2                           | is multiplier exactly 1.0?
    BNE.B       ALGORITHM                       | no: full multiply needed
FIXMUL_NO_2:
    MOVEQ.L     #0x0,D0                         | D0:D4 = 64-bit result
    MOVEQ.L     #0x0,D4                         | clear low 32 bits
    MOVE.W      D1,D4                           | D4 = low word of operand << 16
    SWAP.W      D4                              | position as fractional part
    SWAP.W      D1                              | get high word of operand
    MOVE.W      D1,D0                           | D0 = integer part of result
    BRA.B       FIXMUL_CONT_3                   | go apply mode-specific adjustment
| ----------------------------------------------------------
| ALGORITHM - Full unsigned 32x32 multiply using four 16x16 MULUs.
| Produces 64-bit result in D0 (high) : D4 (low).
| Algorithm: (D1h:D1l) * (D2h:D2l) using schoolbook multiply.
| ----------------------------------------------------------
ALGORITHM:
    MOVE.W      D2,D4                           | D4 = D2.lo
    MULU.W      D1,D4                           | D4 = D1.lo * D2.lo (low partial product)
    SWAP.W      D2                              | get D2.hi
    MOVE.W      D2,D3                           | D3 = D2.hi
    MULU.W      D1,D3                           | D3 = D1.lo * D2.hi (middle product 1)
    SWAP.W      D1                              | get D1.hi
    MOVE.W      D2,D0                           | D0 = D2.hi
    MULU.W      D1,D0                           | D0 = D1.hi * D2.hi (high partial product)
    SWAP.W      D2                              | restore D2.lo
    MULU.W      D1,D2                           | D2 = D1.hi * D2.lo (middle product 2)
    ADD.L       D3,D2                           | D2 = sum of two middle products
    MOVEQ.L     #0x0,D3                         | D3 = carry from middle products
    MOVE.W      D2,D3                           | D3.lo = D2.lo (middle sum low word)
    SWAP.W      D3                              | D3 = D2.lo << 16 (positioned for D4 add)
    MOVE.W      D3,D2                           | D2.lo = 0 (clear after swap)
    SWAP.W      D2                              | D2 = middle sum high word (carry into D0)
    ADD.L       D3,D4                           | add middle contribution to low result
    ADDX.L      D2,D0                           | add carry + high middle to high result
FIXMUL_CONT_3:
    TST.L       D5                              | check operation mode
    BEQ.B       FIXMUL_CONT_4                   | D5=0: FixMul (extract middle 32 bits)
    BPL.B       LONGMUL_EXIT                    | D5>0: LongMul (return full 64-bit result)
    ADD.L       D4,D4                           | D5<0: FixDiv - shift left 2 to get 16.16
    ADDX.L      D0,D0                           | shift with carry through D0:D4
    ADD.L       D4,D4                           | second shift left
    ADDX.L      D0,D0                           | shift with carry
    BRA.B       FIXMUL_CONT_5                   | go round and check overflow
| ----------------------------------------------------------
| FIXMUL_CONT_4 - FixMul: extract middle 32 bits from 64-bit product.
| D0:D4 holds the 64-bit unsigned product; we need bits 16-47.
| ----------------------------------------------------------
FIXMUL_CONT_4:
    SWAP.W      D0                              | D0.lo = high word of result
    TST.W       D0                              | overflow if high word non-zero
    BNE.B       FIXMUL_EXIT_5                   | overflow: return max Fixed value
    SWAP.W      D4                              | D4.lo = bits 16-31 of product
    MOVE.W      D4,D0                           | D0 = integer part from D4 high word
FIXMUL_CONT_5:
    TST.L       D4                              | check low bits for rounding
    BPL.B       FIXMUL_EXIT                     | MSB clear: no round up needed
    ADDQ.L      #0x1,D0                         | round up result
    BCS.B       FIXMUL_EXIT_5                   | carry out: overflow
FIXMUL_EXIT:
    TST.L       D0                              | check if result fits in signed long
    BMI.B       FIXMUL_EXIT_5                   | bit 31 set: overflow
    TST.B       D6                              | check sign flag from operand signs
    BEQ.B       FIXMUL_EXIT_2                   | both same sign: result positive
    NEG.L       D0                              | different signs: negate result
| Called by: FIXMUL_EXIT_5, FIXMUL_EXIT, FIXDIV_EMPTY, FIXDIV_CONT_2, ATAN_SIGN_RESULT
FIXMUL_EXIT_2:
    MOVE.W      #0x8,0x8(A6)                    | param size = 8 bytes to strip
    MOVE.L      D0,0x10(A6)                     | store Fixed result in return slot
    BRA.B       FIXMUL_EXIT_4                   | shared epilogue
| ----------------------------------------------------------
| FIXMUL_EXIT_3 - Return word-sized result (for FixRatio).
| Stores result and param strip size, then epilogue.
| ----------------------------------------------------------
| Called by: FRACSQRT_NO, FIXMUL_SAME_SIGN_RTS, FIXRATIO_EXIT_2, FRACSIN_SIGN_RTS
FIXMUL_EXIT_3:
    MOVE.W      #0x4,0x8(A6)                    | param size = 4 bytes to strip
    MOVE.L      D0,0xC(A6)                      | store result in return slot
FIXMUL_EXIT_4:
    MOVEM.L     (A7)+,D0-D6/A1                  | restore all saved registers
    UNLK        A6                              | discard LINK frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDA.W      (A7),A7                         | strip params (size word on top of stack)
    JMP         (A0)                            | tail-call return from FIXMUL_EXIT_4 via A0
| ----------------------------------------------------------
| FIXMUL_CONT_6 - Common prologue for fixed-point math routines.
| Creates LINK frame and saves registers.
| Pops own return addr and jumps back (acts as macro).
| ----------------------------------------------------------
| Called by: LONGMUL, FRACMUL, FIXMUL, FRACDIV, FIXDIV (and 5 more)
FIXMUL_CONT_6:
    MOVEA.L     (A7)+,A0                        | save return address (back to caller)
    LINK        A6,#0x0                         | create stack frame (no locals)
    MOVEM.L     D0-D6/A1,-(A7)                  | save all working registers
    JMP         (A0)                            | return to caller (inline prologue)
| ----------------------------------------------------------
| FIXMUL_CONT_7 - Load two Fixed params from stack frame into D1-D2.
| Falls through to FIXMUL_CONT_8 for sign normalization.
| ----------------------------------------------------------
FIXMUL_CONT_7:
    MOVEM.L     0x8(A6),D1-D2                   | D1 = first param, D2 = second param
| FIXMUL_CONT_8 -- take absolute values, track sign in D6.
FIXMUL_CONT_8:
    TST.L       D1                              | test sign of first operand
    SMI.B       D6                              | D6 = $FF if negative, $00 if positive
    BPL.B       FIXMUL_SKIP                     | already positive: skip negation
    NEG.L       D1                              | make D1 positive (absolute value)
FIXMUL_SKIP:
    TST.L       D2                              | test sign of second operand
    BPL.B       FIXMUL_SKIP_2                   | already positive: skip negation
    NEG.L       D2                              | make D2 positive (absolute value)
    NOT.B       D6                              | toggle sign flag (XOR signs)
FIXMUL_SKIP_2:
    RTS                                         | return with signs resolved
| ----------------------------------------------------------
| FIXMUL_EXIT_5 - Overflow handler: return max or min Fixed value.
| If D6 (sign) is set, returns $80000001 (most negative).
| If D6 is clear, returns $7FFFFFFF (most positive).
| ----------------------------------------------------------
| Called by: FIXDIV_CONT_2, FIXMUL_CONT_4, FIXMUL_CONT_5, FIXMUL_EXIT, FIXDIV_CONT
FIXMUL_EXIT_5:
    MOVEQ.L     #0x1,D0                         | D0 = 1
    ROR.L       #0x1,D0                         | D0 = $80000000 (rotate 1 into MSB)
    TST.B       D6                              | check sign flag
    BNE.B       FIXMUL_EXIT_2                   | negative: return $80000000 (min Fixed)
    SUBQ.L      #0x1,D0                         | D0 = $7FFFFFFF (max positive Fixed)
    BRA.B       FIXMUL_EXIT_2                   | store and return
| ----------------------------------------------------------
| FRACDIV - FixDiv non-restoring division (full precision).
| D3=31 iterations for 32-bit quotient precision.
| ----------------------------------------------------------
FRACDIV:
    BSR.B       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEQ.L     #0x1F,D3                        | D3 = 31 bits for full precision
    BRA.B       FIXDIV_CONT                     | enter shared division setup
| ----------------------------------------------------------
| FIXDIV - FixDiv with reduced 18-bit precision.
| Fewer iterations for faster approximate quotient.
| ----------------------------------------------------------
FIXDIV:
    BSR.B       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEQ.L     #0x11,D3                        | D3 = 17 bits for reduced precision
FIXDIV_CONT:
    BSR.B       FIXMUL_CONT_7                   | load D1/D2 from params, normalize signs
    MOVEQ.L     #0x0,D0                         | D0 = quotient accumulator (starts at 0)
    TST.L       D1                              | test divisor
    BNE.B       FIXDIV_EMPTY                    | non-zero: proceed with division
    BRA.B       FIXMUL_EXIT_5                   | divide by zero: return overflow
| ----------------------------------------------------------
| FIXDIV_NO - Normalize divisor: shift left until MSB is set.
| ----------------------------------------------------------
FIXDIV_NO:
    ADDQ.W      #0x1,D3                         | one more quotient bit available
    ADD.L       D1,D1                           | shift divisor left
FIXDIV_EMPTY:
    BPL.B       FIXDIV_NO                       | MSB not set: keep shifting
    TST.L       D2                              | test dividend
    BEQ.B       FIXMUL_EXIT_2                   | zero: result = 0
    BRA.B       FIXDIV_CONT_2                   | enter dividend normalization
| Normalize dividend: shift left until MSB is set.
FIXDIV_NO_2:
    SUBQ.W      #0x1,D3                         | one fewer quotient bit
    ADD.L       D2,D2                           | shift dividend left
FIXDIV_CONT_2:
    BPL.B       FIXDIV_NO_2                     | MSB not set: keep shifting
    TST.W       D3                              | any quotient bits to compute?
    BLE.B       FIXMUL_EXIT_2                   | none: result underflows to 0
    CMPI.W      #0x20,D3                        | more than 31 bits needed?
    BLT.B       FIXDIV_LOOP_2                   | no: proceed with division loop
    BGT.B       FIXMUL_EXIT_5                   | yes: overflow
    CMP.L       D1,D2                           | edge case: 32 bits, check sign
    BCS.B       FIXDIV_CONT_4                   | dividend < divisor: enter loop
    BRA.B       FIXMUL_EXIT_5                   | overflow
| ----------------------------------------------------------
| FIXDIV_LOOP-FIXDIV_CONT_4 - Non-restoring binary long division loop.
| ----------------------------------------------------------
FIXDIV_LOOP:
    ADD.L       D0,D0                           | shift quotient left for next bit
    ADD.L       D2,D2                           | shift remainder left (next bit in)
    BCS.B       FIXDIV_CONT_3                   | carry out: remainder >= divisor
FIXDIV_LOOP_2:
    CMP.L       D1,D2                           | compare remainder vs divisor
    BCS.B       FIXDIV_CONT_4                   | remainder < divisor: quotient bit = 0
FIXDIV_CONT_3:
    SUB.L       D1,D2                           | subtract divisor from remainder
    ADDQ.W      #0x1,D0                         | set quotient bit = 1
FIXDIV_CONT_4:
    DBF.W       D3,FIXDIV_LOOP                  | loop for all quotient bits
    LSR.L       #0x1,D0                         | shift out guard bit; C = rounding bit
    BCC.W       FIXMUL_EXIT                     | no rounding: check sign and return
    ADDQ.L      #0x1,D0                         | round up quotient
    BRA.W       FIXMUL_EXIT                     | check sign and return
| ----------------------------------------------------------
| FRACSQRT - FracSqrt: 16.16 fixed-point square root.
| Non-restoring algorithm. Input at 0x8(A6).
| Returns 16.16 Fixed via FIXMUL_EXIT_3.
| ----------------------------------------------------------
FRACSQRT:
    BSR.W       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVE.L      0x8(A6),D3                      | D3 = input radicand
    MOVEQ.L     #0x0,D0                         | D0 = root accumulator
    MOVEQ.L     #0x1,D1                         | D1 = trial subtraction constant
    ROR.L       #0x2,D1                         | D1 = $40000000 (start at MSB pair)
    MOVEQ.L     #0x0,D2                         | D2 = extended remainder (high word)
    MOVEQ.L     #0x1F,D4                        | D4 = 31 iterations for 32-bit root
FRACSQRT_LOOP:
    SUB.L       D1,D3                           | trial subtract: remainder -= trial
    SUBX.L      D0,D2                           | extended subtraction with borrow
    BCC.B       FRACSQRT_NO                     | no borrow: subtraction succeeded
    ADD.L       D1,D3                           | restore: undo failed subtraction
    ADDX.L      D0,D2                           | restore extended remainder
FRACSQRT_NO:
    EORI.B      #0x10,CCR                       | toggle extend flag (invert borrow)
    ADDX.L      D0,D0                           | shift root left, insert result bit
    ADD.L       D3,D3                           | shift radicand left (next bit pair)
    ADDX.L      D2,D2                           | shift extended remainder left
    ADD.L       D3,D3                           | second shift of bit pair
    ADDX.L      D2,D2                           | second shift of remainder
    DBF.W       D4,FRACSQRT_LOOP                | loop for all 32 root bits
    LSR.L       #0x1,D0                         | shift out guard bit; C = round bit
    BCC.W       FIXMUL_EXIT_3                   | no rounding: return result
    ADDQ.L      #0x1,D0                         | round up root
    BRA.W       FIXMUL_EXIT_3                   | return via word-result epilogue
| ----------------------------------------------------------
| _FixRatio ($A869) - Compute ratio of two integers as Fixed.
| Stack: numer(+$08 word), denom(+$0A word).
| Returns 16.16 Fixed = numer/denom. Equal inputs = 1.0.
| ----------------------------------------------------------
FIXRATIO:
    BSR.W       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEM.W     0x8(A6),D1-D2                   | D1 = numer, D2 = denom (words)
    CMP.W       D1,D2                           | numer == denom?
    BEQ.B       FIXRATIO_EXIT_2                 | yes: return exactly 1.0 ($10000)
    BSR.W       FIXMUL_CONT_8                   | normalize signs into D6
    TST.L       D1                              | test denominator
    BNE.B       FIXRATIO_EMPTY                  | non-zero: safe to divide
    MOVEQ.L     #-0x1,D0                        | D0 = $FFFFFFFF
    LSR.L       #0x1,D0                         | D0 = $7FFFFFFF (max positive Fixed)
    BRA.B       FIXRATIO_EXIT                   | apply sign and return
| ----------------------------------------------------------
| FIXRATIO_EMPTY - Standard Fixed ratio: integer part via DIVS,
| fractional part via DIVU on remainder.
| ----------------------------------------------------------
FIXRATIO_EMPTY:
    DIVS.W      D1,D2                           | D2.hi = remainder, D2.lo = quotient
    MOVE.W      D2,D0                           | D0 = integer quotient
    SWAP.W      D0                              | move integer to high word of result
    CLR.W       D2                              | clear quotient, keep remainder in hi word
    DIVU.W      D1,D2                           | D2 = (remainder<<16) / denom = fraction
    MOVE.W      D2,D0                           | D0.lo = fractional part
FIXRATIO_EXIT:
    TST.B       D6                              | check sign flag
    BEQ.B       FIXMUL_SAME_SIGN_RTS            | same signs: result positive
    NEG.L       D0                              | different signs: negate result
FIXMUL_SAME_SIGN_RTS:
    BRA.W       FIXMUL_EXIT_3                   | return Fixed result
| numer == denom: return Fixed 1.0 ($00010000)
FIXRATIO_EXIT_2:
    MOVEQ.L     #0x1,D0                         | D0 = 1
    SWAP.W      D0                              | D0 = $00010000 = Fixed 1.0
    BRA.W       FIXMUL_EXIT_3                   | return
| ----------------------------------------------------------
| _LoWord ($A86B) - Extract low word of long.
| Stack: value(+$04 long). Returns word in result position.
| ----------------------------------------------------------
LOWORD:
    MOVE.W      0x6(A7),0x8(A7)                 | copy low word to result position
    BRA.B       HIWORD_MOVE_RETURN              | shared return
| ----------------------------------------------------------
| _HiWord ($A86A) - Extract high word of long.
| ----------------------------------------------------------
HIWORD:
    MOVE.W      0x4(A7),0x8(A7)                 | copy high word to result position
HIWORD_MOVE_RETURN:
    MOVE.L      (A7)+,(A7)                      | move return addr over discarded long param
    RTS                                         | return with word result on stack
| ----------------------------------------------------------
| _FixRound ($A86C) - Round Fixed to nearest integer.
| Stack: value(+$04 Fixed). Returns word in result position.
| ----------------------------------------------------------
FIXROUND:
    MOVEA.L     (A7)+,A0                        | A0 = return address (saved over param)
    MOVEQ.L     #0x1,D1                         | D1 = 1
    ROR.W       #0x1,D1                         | D1 = $00008000 (rounding constant)
    MOVE.L      (A7)+,D0                        | D0 = Fixed value
    BPL.B       FIXROUND_CONT                   | positive: use +0.5 rounding
    NOT.W       D1                              | negative: D1 = $FFFF7FFF (-0.5 rounding)
FIXROUND_CONT:
    ADD.L       D1,D0                           | add rounding constant
    BVC.B       FIXROUND_SATURATE_TAIL          | no overflow: result is valid
    MOVEQ.L     #-0x2,D0                        | overflow: clamp to extreme
    ROR.L       #0x1,D0                         | D0 = $7FFFFFFF or $80000000
FIXROUND_SATURATE_TAIL:
    SWAP.W      D0                              | high word now in low half
    MOVE.W      D0,(A7)                         | store rounded integer in result slot
    JMP         (A0)                            | jump to saved return address
| ----------------------------------------------------------
| FracCos ($A847) - 16.16 fixed-point cosine (Plus's SetDeskCPat).
| D6=2 selects cosine mode (cos via tangent identity).
| ----------------------------------------------------------
FRACCOS:
    BSR.W       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEQ.L     #0x2,D6                         | D6 = 2 (cosine mode)
    BRA.B       FRACSIN_CONT                    | enter shared trig core
| ----------------------------------------------------------
| FracSin ($A848) - 16.16 fixed-point sine (Plus's LOC_C72E).
| D6=0 selects sine mode.
| ----------------------------------------------------------
FRACSIN:
    BSR.W       FIXMUL_CONT_6                   | set up LINK frame, save regs
    MOVEQ.L     #0x0,D6                         | D6 = 0 (sine mode)
FRACSIN_CONT:
    MOVE.L      0x8(A6),D3                      | D3 = input angle value
    BPL.B       FRACSIN_NO                      | positive: no negation needed
    TST.L       D6                              | check computation mode
    BNE.B       FRACSIN_CONT_2                  | cosine mode: just negate input
    ADDQ.W      #0x4,D6                         | sine: add correction offset for sign
FRACSIN_CONT_2:
    NEG.L       D3                              | negate to work with absolute value
FRACSIN_NO:
    MOVE.L      #0xC910,D5                      | D5 = 51472 (degree scaling constant)
    DIVU.W      D5,D3                           | D3 = quotient:remainder from scaling
    ADD.L       D3,D6                           | accumulate scaled result with mode offset
    CLR.W       D3                              | clear low word of D3
    SWAP.W      D3                              | move result to high word
    BTST        #0x0,D6                         | test sign flag
    BEQ.B       FRACSIN_REDUCED                 | skip if positive
    SUB.W       D5,D3                           | negate by subtracting from complement
    NEG.W       D3                              | final negation
FRACSIN_REDUCED:
    SWAP.W      D3                              | swap back
    LSR.L       #0x3,D3                         | divide by 8 for coefficient index
    MOVE.L      A2,-(A7)                        | save A2
    SUBA.W      #0x10,A7                        | allocate 16 bytes on stack
    MOVE.L      D3,-(A7)                        | push coefficient index
    MOVE.L      D3,-(A7)                        | push again for squaring multiply
    BSR.W       FRACMUL                         | square the input via FixDiv core
    MOVE.L      (A7)+,D5                        | pop squared result
    MOVE.B      #0x66,-(A7)                     | push test pattern for sign bits
    BTST        D6,(A7)+                        | test sign combination flags
    BNE.B       FRACSIN_POLYCOS                 | branch if negative-operand path
    LEA.L       FRACSIN_SN0(PC),A2              | positive: use FRACSIN_SN0 table
    MOVEQ.L     #0x4,D4                         | 2 terms (index 0,4)
    BRA.B       FRACSIN_POLY                    | skip negative coefficient processing
FRACSIN_POLYCOS:
    LEA.L       FRACSIN_CS0(PC),A2              | negative: use FRACSIN_CS0 table
    MOVEQ.L     #0x8,D4                         | 3 terms (index 0,4,8)
FRACSIN_POLY:
    MOVE.L      0x4(A2,D4.W),-(A7)              | push initial accumulator from table
FRACSIN_POLY_TERM:
    MOVE.L      D5,-(A7)                        | push squared multiplier
    BSR.W       FRACMUL                         | multiply accumulator by ratio^2 (Horner)
    MOVE.L      0x0(A2,D4.W),D0                 | load next polynomial coefficient
    ADD.L       D0,(A7)                         | add coefficient to running sum
    SUBQ.W      #0x4,D4                         | move to next table entry
    BPL.B       FRACSIN_POLY_TERM               | loop until all terms processed
    MOVE.B      #0x66,-(A7)                     | push test pattern for sign bits
    BTST        D6,(A7)+                        | test sign combination flags
    BNE.B       FRACSIN_NOTSINE                 | skip remainder correction if negative
    MOVE.L      D3,-(A7)                        | push linear remainder
    JSR         FRACMUL(PC)                     | multiply in remainder correction
FRACSIN_NOTSINE:
    MOVE.L      (A7)+,D0                        | pop final polynomial result
    MOVEA.L     (A7)+,A2                        | restore A2
    MOVE.B      #0xF0,-(A7)                     | push sign test mask
    BTST        D6,(A7)+                        | test if result should be negated
    BEQ.B       FRACSIN_SIGN_RTS                | skip if positive result
    NEG.L       D0                              | negate result
FRACSIN_SIGN_RTS:
    BRA.W       FIXMUL_EXIT_3                   | return Fixed result via word epilogue
| ----------------------------------------------------------
|
| FRACSIN_SN0 - polynomial coefficients for positive-operand path
|
FRACSIN_SN0:
    .short      0x7FFF
    .long       0xD609AAB3
    .long       0x314D10A2
    .short      0x08E5
| FRACSIN_CS0 - polynomial coefficients for negative-operand path
FRACSIN_CS0:
    .short      0x4000
    .long       0x00008000
    .long       0x11A72AA7
    .long       0xF29AFA6E
    .short      0x2A42
| ----------------------------------------------------------
| FixAtan2 ($A849) - 16.16 fixed-point arctangent of dy/dx.
| Stack: dvsr/dx(+$0C), dvnd/dy(+$08). Returns angle in
| Fixed degrees. D6 tracks sign/swap flags:
| bit 0 = dividend negative, bit 1 = divisor negative,
| bit 2 = operands swapped (|dvnd| > |dvsr|).
| ----------------------------------------------------------
FIXATAN2:
    BSR.W       FIXMUL_CONT_6                   | set up stack frame
    MOVEQ.L     #0x0,D6                         | clear sign/swap flags
    MOVE.L      0xC(A6),D3                      | D3 = divisor from stack frame
    BPL.B       ATAN_DVSR_ABS                   | skip if divisor positive
    ADDQ.W      #0x2,D6                         | set bit 1: divisor was negative
    NEG.L       D3                              | take absolute value of divisor
    BPL.B       ATAN_DVSR_ABS                   | branch unless $80000000
    SUBQ.W      #0x1,D3                         | clamp $80000000 to $7FFFFFFF
ATAN_DVSR_ABS:
    MOVE.L      0x8(A6),D0                      | D0 = dividend from stack frame
    BPL.B       ATAN_ABS_DIVIDEND               | skip if dividend positive
    ADDQ.W      #0x1,D6                         | set bit 0: dividend was negative
    NEG.L       D0                              | take absolute value of dividend
    BPL.B       ATAN_ABS_DIVIDEND               | branch unless $80000000
    SUBQ.W      #0x1,D0                         | clamp $80000000 to $7FFFFFFF
ATAN_ABS_DIVIDEND:
    MOVE.L      A2,-(A7)                        | save A2
    SUBA.W      #0x20,A7                        | allocate 32-byte work area
    CMP.L       D3,D0                           | compare |dividend| vs |divisor|
    BLE.B       ATAN_NO_SWAP                    | branch if |dividend| <= |divisor|
    ADDQ.W      #0x4,D6                         | set bit 2: operands swapped
    MOVE.L      D3,-(A7)                        | push smaller value (divisor)
    BEQ.B       ATAN_DVSR_ZERO                  | if divisor=0, result is 0
    MOVE.L      D0,-(A7)                        | push larger value (dividend)
    BRA.B       ATAN_DO_FRACDIV                 | proceed to division
| ATAN_DVSR_ZERO: divisor is zero, return zero
ATAN_DVSR_ZERO:
    MOVE.L      D3,D0                           | D0 = 0 (divisor was zero)
ATAN_DEALLOC_RTS:
    ADDA.W      #0x24,A7                        | deallocate work area + pushed values
    BRA.B       ATAN_RESTORE_A2                 | skip to sign adjustment
| ATAN_NO_SWAP: |dividend| <= |divisor|, no swap needed
ATAN_NO_SWAP:
    MOVE.L      D0,-(A7)                        | push dividend (smaller or equal)
    BEQ.B       ATAN_DEALLOC_RTS                | if dividend=0, result is 0
    MOVE.L      D3,-(A7)                        | push divisor
ATAN_DO_FRACDIV:
    BSR.W       FRACDIV                         | divide smaller by larger
    MOVE.L      (A7),D3                         | D3 = quotient ratio
    MOVE.L      (A7),-(A7)                      | duplicate for squaring
    BSR.W       FRACMUL                         | square the ratio
    MOVE.L      (A7)+,D5                        | D5 = ratio squared
    LEA.L       ATAN_COEFF_TBL(PC),A2           | A2 -> Chebyshev coefficient table
    MOVE.L      0x14(A2),-(A7)                  | push last coefficient as accumulator
    MOVEQ.L     #0x10,D4                        | 5 coefficients (index 0x00..0x10)
ATAN_POLY_LOOP:
    MOVE.L      D5,-(A7)                        | push ratio squared
    BSR.W       FRACMUL                         | multiply accumulator by ratio^2
    MOVE.L      0x0(A2,D4.W),D0                 | load next Chebyshev coefficient
    ADD.L       D0,(A7)                         | add to running sum (Horner's method)
    SUBQ.W      #0x4,D4                         | advance to next coefficient
    BPL.B       ATAN_POLY_LOOP                  | loop for all 5 coefficients
    MOVE.L      D3,-(A7)                        | push original ratio
    JSR         FRACMUL(PC)                     | multiply polynomial result by ratio
    MOVE.L      (A7)+,D0                        | D0 = final polynomial result
    MOVEQ.L     #0xE,D2                         | shift count = 14 for rounding
    LSR.L       D2,D0                           | shift right 14 to scale result
    BCC.B       ATAN_RESTORE_A2                 | skip if no rounding needed
    ADDQ.L      #0x1,D0                         | round up if shifted-out bit was set
ATAN_RESTORE_A2:
    MOVEA.L     (A7)+,A2                        | restore A2
    MOVE.L      #0x19220,D5                     | D5 = pi/2 in fixed-point (0x19220)
    BTST        #0x2,D6                         | were operands swapped?
    BEQ.B       ATAN_CHK_DVSR                   | skip if not swapped
    SUB.L       D5,D0                           | result = pi/2 - result (complement)
    NEG.L       D0                              | negate to get correct quadrant
ATAN_CHK_DVSR:
    BTST        #0x1,D6                         | was divisor negative?
    BEQ.B       ATAN_CHK_DVND                   | skip if divisor positive
    LSL.L       #0x1,D5                         | D5 = pi (double pi/2)
    SUB.L       D5,D0                           | result = pi - result
    NEG.L       D0                              | adjust sign for negative divisor
ATAN_CHK_DVND:
    BTST        #0x0,D6                         | was dividend negative?
    BEQ.B       ATAN_SIGN_RESULT                | skip if dividend positive
    NEG.L       D0                              | negate result for negative dividend
ATAN_SIGN_RESULT:
    BRA.W       FIXMUL_EXIT_2                   | return result via common exit
| ----------------------------------------------------------
|
| ATAN_COEFF_TBL - Chebyshev polynomial coefficients for arctan approx
|
ATAN_COEFF_TBL:
    .long       0x3FFFA073
    .long       0xEAB64EBE
    .long       0x0C62F72C
    .long       0xF88C77F2
    .long       0x035E92FE
    .long       0xFF3FFE62
| ----------------------------------------------------------
| _Fix2X ($A843) - convert Fixed (16.16) to 80-bit SANE extended
| Input: Fixed value on stack, pointer to 10-byte extended on stack.
| Exponent bias for Fixed: 0x400E.
| ----------------------------------------------------------
FIX2X:
    MOVE.W      #0x400E,D1                      | exponent bias for Fixed (16.16)
    BRA.B       FIX_TO_EXTENDED                 | share conversion code with Frac2X
| ----------------------------------------------------------
| _Frac2X ($A845) - convert Fract (2.30) to 80-bit SANE extended.
| Exponent bias for Fract: 0x4000.
| ----------------------------------------------------------
FRAC2X:
    MOVE.W      #0x4000,D1                      | exponent bias for Fract (2.30)
FIX_TO_EXTENDED:
    MOVEA.L     (A7)+,A0                        | pop return address
    MOVE.L      (A7)+,D0                        | pop fixed/fract value
    BNE.B       FIX2X_NORMALIZE                 | branch if value is nonzero
    MOVEQ.L     #0x0,D1                         | zero: exponent = 0
    BRA.B       FIX2X_STORE                     | store zero extended result
| ----------------------------------------------------------
| FIX2X_NORMALIZE - normalize the fixed/fract mantissa
| ----------------------------------------------------------
FIX2X_NORMALIZE:
    BPL.B       FIX2X_SHIFT_LEFT                | branch if value positive
    ADDI.W      #0x8000,D1                      | set sign bit in exponent word
    NEG.L       D0                              | make mantissa positive
    BMI.B       FIX2X_STORE                     | if $80000000, already normalized
FIX2X_SHIFT_LEFT:
    SUBQ.W      #0x1,D1                         | decrement exponent for each left shift
    LSL.L       #0x1,D0                         | shift mantissa left to normalize
    BPL.B       FIX2X_SHIFT_LEFT                | loop until MSB is set (normalized)
FIX2X_STORE:
    MOVEA.L     (A7),A1                         | A1 -> destination extended (10 bytes)
    MOVE.W      D1,(A1)                         | store exponent + sign word
    MOVE.L      D0,0x2(A1)                      | store high 32 bits of mantissa
    CLR.L       0x6(A1)                         | clear low 32 bits of mantissa
    JMP         (A0)                            | tail-call return from FIX2X_STORE via A0
| ----------------------------------------------------------
| _X2Fix ($A844) - convert 80-bit SANE extended to Fixed (16.16)
| Clamps to $80000000 / $7FFFFFFF on overflow.
| ----------------------------------------------------------
X2FIX:
    MOVE.W      #0x400E,D1                      | exponent bias for Fixed (16.16)
    BRA.B       X2FIX_CONVERT                   | share conversion code with X2Frac
| ----------------------------------------------------------
| _X2Frac ($A846) - convert 80-bit SANE extended to Fract (2.30)
| ----------------------------------------------------------
X2FRAC:
    MOVE.W      #0x4000,D1                      | exponent bias for Fract (2.30)
X2FIX_CONVERT:
    MOVEM.L     (A7)+,A0-A1                     | A0=return addr, A1->extended source
    MOVE.W      (A1),D0                         | D0 = exponent+sign word of extended
    BCLR        #0xF,D0                         | clear sign bit, keep raw exponent
    SUB.W       D0,D1                           | D1 = shift count (bias - exponent)
    BLT.B       X2FIX_OVERFLOW                  | overflow if exponent > bias
    MOVE.L      0x2(A1),D0                      | D0 = high 32 bits of mantissa
    TST.W       D1                              | shift count = 0?
    BNE.B       X2FIX_SHIFT                     | branch if shifting needed
    TST.W       0x6(A1)                         | check low mantissa for rounding
    BRA.B       X2FIX_CHK_ROUND                 | test rounding bit
| ----------------------------------------------------------
| X2FIX_SHIFT - mantissa needs right-shifting by D1 bits
| ----------------------------------------------------------
X2FIX_SHIFT:
    CMPI.W      #0x20,D1                        | shift >= 32 bits?
    BLT.B       X2FIX_DO_SHIFT                  | branch if shift < 32
    BNE.B       X2FIX_UNDERFLOW                 | shift > 32: result is 0 or -1
    MOVEQ.L     #0x0,D0                         | shift exactly 32: D0=0
    TST.W       0x2(A1)                         | check MSB for rounding
X2FIX_CHK_ROUND:
    BMI.B       X2FIX_ROUND_UP                  | round up if MSB of remainder set
    BRA.B       X2FIX_CHK_SIGN                  | no rounding needed
| ----------------------------------------------------------
| X2FIX_DO_SHIFT - right-shift mantissa by D1 (1..31) bits
| ----------------------------------------------------------
X2FIX_DO_SHIFT:
    LSR.L       D1,D0                           | shift mantissa right by D1
    BCC.B       X2FIX_CHK_SIGN                  | skip rounding if no carry out
X2FIX_ROUND_UP:
    ADDQ.L      #0x1,D0                         | round up (half-to-even)
    BCS.B       X2FIX_OVERFLOW                  | overflow from rounding: clamp
X2FIX_CHK_SIGN:
    TST.W       (A1)                            | test sign of original extended
    BMI.B       X2FIX_NEGATE                    | branch if negative: negate result
    TST.L       D0                              | positive: check for overflow
    BMI.B       X2FIX_OVERFLOW                  | bit 31 set = positive overflow
| Called by: FIX2LONG_POS, X2FIX_NEGATE, X2FIX_ROTATE, FIX2LONG_NEG_RND, LONG2FIX_SHIFT
X2FIX_STORE:
    MOVE.L      D0,(A7)                         | store result on stack
    JMP         (A0)                            | tail-call return from X2FIX_STORE via A0
| X2FIX_UNDERFLOW: shift > 32, result underflows to 0
X2FIX_UNDERFLOW:
    MOVEQ.L     #0x0,D0                         | result is zero magnitude
X2FIX_NEGATE:
    NEG.L       D0                              | negate for signed result
    BLE.B       X2FIX_STORE                     | if <= 0, store and return
| X2FIX_OVERFLOW: clamp result to $7FFFFFFF or $80000000
X2FIX_OVERFLOW:
    TST.W       (A1)                            | check sign of extended source
X2FIX_CLAMP:
    BPL.B       X2FIX_POS_CLAMP                 | branch if positive overflow
    MOVEQ.L     #0x1,D0                         | negative overflow: start with 1
    BRA.B       X2FIX_ROTATE                    | rotate to get $80000000
| X2FIX_POS_CLAMP: positive overflow, clamp to $7FFFFFFF
X2FIX_POS_CLAMP:
    MOVEQ.L     #0x0,D0                         | D0 = 0
    SUBQ.L      #0x2,D0                         | D0 = $FFFFFFFE
X2FIX_ROTATE:
    ROR.L       #0x1,D0                         | rotate right: $01->$80000000, $FFFFFFFE->$7FFFFFFF
    BRA.B       X2FIX_STORE                     | store clamped result and return
| ----------------------------------------------------------
| _Fix2Long ($A840) - convert Fixed (16.16) to LongInt.
| Rounds the fractional part: 0.5 rounds away from zero.
| ----------------------------------------------------------
FIX2LONG:
    MOVEQ.L     #0x10,D1                        | shift 16 to discard fraction bits
    BRA.B       FIX2LONG_SHIFT                  | share code with Frac2Fix
| ----------------------------------------------------------
| _Frac2Fix ($A842) - convert Fract (2.30) to Fixed (16.16)
| Right-shifts by 14 bits to convert 2.30 -> 16.16 format.
| ----------------------------------------------------------
FRAC2FIX:
    MOVEQ.L     #0xE,D1                         | shift 14 to convert 2.30 -> 16.16
FIX2LONG_SHIFT:
    MOVEA.L     (A7)+,A0                        | pop return address
    MOVE.L      (A7)+,D0                        | pop input value
    BPL.B       FIX2LONG_POS                    | branch if positive
    NEG.L       D0                              | make positive for shifting
    LSR.L       D1,D0                           | right-shift by D1 bits
    BCC.B       FIX2LONG_NEG_RND                | skip rounding if no carry
    ADDQ.L      #0x1,D0                         | round up (away from zero)
FIX2LONG_NEG_RND:
    NEG.L       D0                              | restore negative sign
    BRA.B       X2FIX_STORE                     | store result and return
| FIX2LONG_POS: positive path (shift and round)
FIX2LONG_POS:
    LSR.L       D1,D0                           | right-shift positive value
    BCC.B       X2FIX_STORE                     | skip rounding if no carry
    ADDQ.L      #0x1,D0                         | round up
    BRA.B       X2FIX_STORE                     | store result and return
| ----------------------------------------------------------
| _Long2Fix ($A83F) - convert LongInt to Fixed (16.16)
| Left-shifts by 16 to place integer in high word.
| Clamps on overflow to $7FFFFFFF or $80000000.
| ----------------------------------------------------------
LONG2FIX:
    MOVEQ.L     #0x10,D1                        | shift 16 to create 16.16 from integer
    BRA.B       LONG2FIX_SHIFT                  | share code with Fix2Frac
| ----------------------------------------------------------
| _Fix2Frac ($A841) - convert Fixed (16.16) to Fract (2.30)
| Left-shifts by 14 to convert 16.16 -> 2.30 format.
| Clamps on overflow.
| ----------------------------------------------------------
FIX2FRAC:
    MOVEQ.L     #0xE,D1                         | shift 14 to convert 16.16 -> 2.30
LONG2FIX_SHIFT:
    MOVEA.L     (A7)+,A0                        | pop return address
    MOVE.L      (A7)+,(A7)                      | move input to result position
    MOVE.L      (A7),D0                         | D0 = input value
    ASL.L       D1,D0                           | left-shift (arithmetic, preserves sign)
    BVC.B       X2FIX_STORE                     | no overflow: store shifted result
    MOVE.L      (A7),D1                         | overflow: reload original for sign test
    BRA.B       X2FIX_CLAMP                     | clamp to $7FFFFFFF or $80000000
