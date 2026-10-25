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
|
| _LongMul ($A867): signed 32 x 32 -> 64-bit multiply
| Pascal: PROCEDURE LongMul(a, b: LONGINT; VAR dest: Int64Bit);
| Entry: after FIXPT_ENTRY, a = $10(A6), b = $0C(A6), @dest = $08(A6)
| Exit:  dest.hiLong:dest.loLong = a*b; 12 bytes of parameters removed;
|        all registers except A0 preserved
| Takes the magnitudes (sign in D6.B), runs the shared unsigned multiply
| (FIXMUL_CONT_2/ALGORITHM) with D5 = 1 and negates the 64-bit product in
| LONGMUL_EXIT if the signs differed.
|
LongMul:
        BSR     FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEQ.L #0x1,D5                         | D5=1: LongMul mode (64-bit result)
        MOVEM.L 0xC(A6),D1-D2                   | D1 = b, D2 = a
        BSR     FIXMUL_CONT_8                   | take absolute values, track sign in D6
        BRA.B   FIXMUL_CONT_2                   | enter shared multiply core

| ----------------------------------------------------------
| LONGMUL_EXIT - LongMul epilogue: apply sign to 64-bit result and
| store hi:lo result at caller's pointer.
| ----------------------------------------------------------
LONGMUL_EXIT:
        TST.B   D6                              | check combined sign flag
        BPL.B   LONGMUL_NO                      | positive result: no negation needed
        NEG.L   D4                              | negate low 32 bits
        NEGX.L  D0                              | negate high 32 bits with borrow
LONGMUL_NO:
        MOVE.L  0x8(A6),A0                      | A0 = result pointer from stack
        MOVE.L  D0,(A0)+                        | store high 32 bits of 64-bit product
        MOVE.L  D4,(A0)                         | store low 32 bits of 64-bit product
        MOVE    #0xC,0x8(A6)                    | param size = 12 bytes to strip
        BRA     FIXMUL_EXIT_4                   | shared epilogue: restore and return

| ----------------------------------------------------------
|
| _FracMul ($A84A): multiply two Fract (2.30) values
| Pascal: FUNCTION FracMul(x, y: Fract): Fract;
| Entry: after FIXPT_ENTRY, x = $0C(A6), y = $08(A6); result at $10(A6)
| Exit:  result = x*y / 2^30, rounded; $7FFFFFFF / $80000000 on overflow;
|        all registers except A0 preserved
| Shares the FixMul code with D5 = -1: the 64-bit product of the
| magnitudes is shifted left 2 (FIXMUL_CONT_3), so D0 = product bits
| 61..30, and bit 29 rounds.
|
FracMul:
        BSR     FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEQ.L #-0x1,D5                        | D5 = -1: FracMul (product >> 30)
        BRA.B   FIXMUL_CONT                     | enter the shared multiply code

| ----------------------------------------------------------
|
| _FixMul ($A868): multiply two Fixed (16.16) values
| Pascal: FUNCTION FixMul(a, b: Fixed): Fixed;
| Entry: after FIXPT_ENTRY, a = $0C(A6), b = $08(A6); result at $10(A6)
| Exit:  result = a*b / 2^16, rounded; $7FFFFFFF / $80000000 on overflow;
|        all registers except A0 preserved
| D5 = 0. FIXMUL_CONT..ALGORITHM is the multiply shared with LongMul
| (D5 = 1) and FracMul (D5 = -1): magnitudes in D1/D2 (sign in D6.B); an
| operand of exactly $00010000 short-cuts to a shift, otherwise four MULUs
| form the unsigned 64-bit product in D0:D4; FIXMUL_CONT_3 then extracts
| the result according to D5.
|
FixMul:
        BSR     FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEQ.L #0x0,D5                         | D5=0: FixMul mode (extract middle 32 bits)
FIXMUL_CONT:
        BSR     FIXMUL_CONT_7                   | D1 = |param 2|, D2 = |param 1|, D6 = sign
FIXMUL_CONT_2:
        MOVEQ.L #0x1,D4                         | D4 = 1
        SWAP    D4                              | D4 = $00010000 (Fixed 1.0)
        CMP.L   D4,D1                           | |param 2| = $00010000?
        BNE.B   FIXMUL_NO                       | no: check |param 1|
        MOVE.L  D2,D1                           | yes: product = other operand << 16
        BRA.B   FIXMUL_NO_2                     | shortcut: no multiply needed

| ----------------------------------------------------------
| FIXMUL_NO - Is the other operand exactly $00010000? Then the 64-bit
| product is just D1 << 16 (FIXMUL_NO_2), valid for all three modes;
| otherwise do the full multiply (ALGORITHM).
| ----------------------------------------------------------
FIXMUL_NO:
        CMP.L   D4,D2                           | |param 1| = $00010000?
        BNE.B   ALGORITHM                       | no: full multiply needed
FIXMUL_NO_2:
        MOVEQ.L #0x0,D0                         | D0:D4 = D1 << 16 (64-bit product)
        MOVEQ.L #0x0,D4                         | clear low 32 bits
        MOVE    D1,D4                           | D4.W = low word of D1
        SWAP    D4                              | D4 = D1.lo << 16
        SWAP    D1                              | get high word of operand
        MOVE    D1,D0                           | D0 = D1.hi
        BRA.B   FIXMUL_CONT_3                   | go apply mode-specific adjustment

| ----------------------------------------------------------
| ALGORITHM - Full unsigned 32x32 multiply using four 16x16 MULUs.
| Produces 64-bit result in D0 (high) : D4 (low).
| Algorithm: (D1h:D1l) * (D2h:D2l) using schoolbook multiply. Both
| operands are magnitudes <= $80000000, so the middle sum cannot carry.
| ----------------------------------------------------------
ALGORITHM:
        MOVE    D2,D4                           | D4 = D2.lo
        MULU    D1,D4                           | D4 = D1.lo * D2.lo (low partial product)
        SWAP    D2                              | get D2.hi
        MOVE    D2,D3                           | D3 = D2.hi
        MULU    D1,D3                           | D3 = D1.lo * D2.hi (middle product 1)
        SWAP    D1                              | get D1.hi
        MOVE    D2,D0                           | D0 = D2.hi
        MULU    D1,D0                           | D0 = D1.hi * D2.hi (high partial product)
        SWAP    D2                              | restore D2.lo
        MULU    D1,D2                           | D2 = D1.hi * D2.lo (middle product 2)
        ADD.L   D3,D2                           | D2 = sum of middle products (no carry)
        MOVEQ.L #0x0,D3                         | clear D3
        MOVE    D2,D3                           | D3.lo = D2.lo (middle sum low word)
        SWAP    D3                              | D3 = D2.lo << 16 (positioned for D4 add)
        MOVE    D3,D2                           | D2.lo = 0 (clear after swap)
        SWAP    D2                              | D2 = middle sum >> 16
        ADD.L   D3,D4                           | add middle contribution to low result
        ADDX.L  D2,D0                           | add carry + high middle to high result
| FIXMUL_CONT_3 -- D0:D4 = unsigned 64-bit product; select the result by D5
FIXMUL_CONT_3:
        TST.L   D5                              | check operation mode
        BEQ.B   FIXMUL_CONT_4                   | D5=0: FixMul (extract middle 32 bits)
        BPL.B   LONGMUL_EXIT                    | D5>0: LongMul (return full 64-bit result)
        ADD.L   D4,D4                           | D5 < 0: FracMul - shift D0:D4 left 2
        ADDX.L  D0,D0                           | shift with carry through D0:D4
        ADD.L   D4,D4                           | second shift left
        ADDX.L  D0,D0                           | D0 = product bits 61..30 (Fract)
        BRA.B   FIXMUL_CONT_5                   | go round and check overflow

| ----------------------------------------------------------
| FIXMUL_CONT_4 - FixMul: extract middle 32 bits from 64-bit product.
| D0:D4 holds the 64-bit unsigned product; we need bits 16-47.
| ----------------------------------------------------------
FIXMUL_CONT_4:
        SWAP    D0                              | D0.W = product bits 63..48
        TST     D0                              | overflow if high word non-zero
        BNE.B   FIXPT_OVERFLOW                  | overflow: pin to max/min
        SWAP    D4                              | D4.lo = bits 16-31 of product
        MOVE    D4,D0                           | D0 = product bits 47..16
| FIXMUL_CONT_5 -- round: D4 bit 31 is the first bit below the result
FIXMUL_CONT_5:
        TST.L   D4                              | D4 bit 31 = round bit
        BPL.B   FIXMUL_EXIT                     | MSB clear: no round up needed
        ADDQ.L  #0x1,D0                         | round up result
        BCS.B   FIXPT_OVERFLOW                  | carry out: overflow
| FIXMUL_EXIT (Apple: reSign) -- apply sign D6.B to magnitude D0, pin overflow
FIXMUL_EXIT:
        TST.L   D0                              | check if result fits in signed long
        BMI.B   FIXPT_OVERFLOW                  | bit 31 set: overflow
        TST.B   D6                              | check sign flag from operand signs
        BEQ.B   FIXMUL_EXIT_2                   | both same sign: result positive
        NEG.L   D0                              | different signs: negate result
| FIXMUL_EXIT_2 (Apple: TwoParmExit) -- return D0 from a two-parameter function
FIXMUL_EXIT_2:
        MOVE    #0x8,0x8(A6)                    | param size = 8 bytes to strip
        MOVE.L  D0,0x10(A6)                     | store result in function result slot
        BRA.B   FIXMUL_EXIT_4                   | shared epilogue

| ----------------------------------------------------------
| FIXMUL_EXIT_3 - common exit for functions with 4 bytes of parameters
| (FracSqrt, FixRatio, FracCos, FracSin): long result D0 -> $0C(A6).
| FIXMUL_EXIT_4: restore D0-D6/A1, UNLK, pop the return address, remove
| the number of parameter bytes stored at $08(A6) and return.
| Apple source names: OneParmExit, CustomExit (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
FIXMUL_EXIT_3:
        MOVE    #0x4,0x8(A6)                    | param size = 4 bytes to strip
        MOVE.L  D0,0xC(A6)                      | store result in return slot
FIXMUL_EXIT_4:
        MOVEM.L (SP)+,D0-D6/A1                  | restore all saved registers
        UNLK    A6                              | discard LINK frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    (SP),SP                         | strip params (size word on top of stack)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
| FIXPT_ENTRY - common entry of the fixed-point routines: pops its own
| return address into A0, LINK A6,#0, saves D0-D6/A1 and jumps back. The
| parameters then start at $08(A6), the caller's return address is $04(A6).
| Apple source name: StdEntry (System 7.1 Toolbox/Munger/Munger.a; called
| FixPtStdEntry at Plus $15880 in System 7.1 MungerPatches.a)
| ----------------------------------------------------------
| Called by: LongMul, FracMul, FixMul, FracDiv, FixDiv (and 5 more)
FIXPT_ENTRY:
        MOVE.L  (SP)+,A0                        | A0 = return address into the caller
        LINK    A6,#0x0                         | create stack frame (no locals)
        MOVEM.L D0-D6/A1,-(SP)                  | save all working registers
        JMP     (A0)                            | return to caller (inline prologue)

| ----------------------------------------------------------
| FIXMUL_CONT_7 - load the two parameters: D1 = $08(A6) (2nd parameter),
| D2 = $0C(A6) (1st), then fall into FIXMUL_CONT_8: D1/D2 := magnitudes,
| D6.B = $FF if exactly one was negative (sign of the result), else $00.
| Apple source names: fixArgs, fixArg1 (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
FIXMUL_CONT_7:
        MOVEM.L 0x8(A6),D1-D2                   | D1 = param 2 ($08), D2 = param 1 ($0C)
| FIXMUL_CONT_8 -- D1/D2 := magnitudes, D6.B := sign of the result (also
| entered directly by LongMul and FixRatio with their own D1/D2)
FIXMUL_CONT_8:
        TST.L   D1                              | test sign of D1
        SMI.B   D6                              | D6 = $FF if negative, $00 if positive
        BPL.B   FIXMUL_SKIP                     | already positive: skip negation
        NEG.L   D1                              | make D1 positive (absolute value)
FIXMUL_SKIP:
        TST.L   D2                              | test sign of D2
        BPL.B   FIXMUL_SKIP_2                   | already positive: skip negation
        NEG.L   D2                              | make D2 positive (absolute value)
        NOT.B   D6                              | toggle sign flag (XOR signs)
FIXMUL_SKIP_2:
        RTS                                     | return with signs resolved

| ----------------------------------------------------------
| FIXPT_OVERFLOW - overflow: return $80000000 if D6.B <> 0 (negative
| result), else $7FFFFFFF, through the two-parameter exit FIXMUL_EXIT_2.
| Apple source name: fixOver (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
FIXPT_OVERFLOW:
        MOVEQ.L #0x1,D0                         | D0 = 1
        ROR.L   #0x1,D0                         | D0 = $80000000 (rotate 1 into MSB)
        TST.B   D6                              | check sign flag
        BNE.B   FIXMUL_EXIT_2                   | negative: return $80000000
        SUBQ.L  #0x1,D0                         | D0 = $7FFFFFFF (most positive)
        BRA.B   FIXMUL_EXIT_2                   | store and return

| ----------------------------------------------------------
|
| _FracDiv ($A84B): divide, giving a Fract (2.30) quotient
| Pascal: FUNCTION FracDiv(x, y: Fract): Fract;
| Entry: after FIXPT_ENTRY, x = $0C(A6), y = $08(A6); result at $10(A6)
| Exit:  result = x/y * 2^30, rounded (Fract / Fract -> Fract);
|        y = 0: $7FFFFFFF if x >= 0, $80000000 if x < 0; overflow pinned;
|        all registers except A0 preserved
| Same code as FixDiv, but with D3 = 31 quotient steps (1 integer + 30
| fraction + 1 rounding bit, minus 1 for DBF).
|
FracDiv:
        BSR.B   FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEQ.L #0x1F,D3                        | D3 = 31 steps (1 + 30 + 1 round - 1)
        BRA.B   FIXDIV_CONT                     | enter shared division setup

| ----------------------------------------------------------
|
| _FixDiv ($A84D): divide, giving a Fixed (16.16) quotient
| Pascal: FUNCTION FixDiv(x, y: Fixed): Fixed;
| Entry: after FIXPT_ENTRY, x = $0C(A6), y = $08(A6); result at $10(A6)
| Exit:  result = x/y * 2^16, rounded (Fixed / Fixed -> Fixed);
|        y = 0: $7FFFFFFF if x >= 0, $80000000 if x < 0; overflow pinned;
|        all registers except A0 preserved
| D3 = quotient steps: 17 (1 integer + 16 fraction + 1 rounding bit - 1).
| FIXDIV_CONT (Apple: comDiv, shared with FracDiv) takes the magnitudes
| (D1 = |y|, D2 = |x|), shifts each left until bit 31 is set (+1 step per
| divisor shift, -1 per dividend shift), returns 0 for <= 0 steps and
| overflow for more than 31, else develops D3+1 quotient bits in D0 and
| rounds with the last one. A count of exactly 32 always overflows here;
| Apple later handled it separately (Munger.a changes <A279>/<A343>, 1986).
|
FixDiv:
        BSR.B   FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEQ.L #0x11,D3                        | D3 = 17 steps (1 + 16 + 1 round - 1)
FIXDIV_CONT:
        BSR.B   FIXMUL_CONT_7                   | D1 = |y| (divisor), D2 = |x|, D6 = sign
        MOVEQ.L #0x0,D0                         | D0 = quotient accumulator (starts at 0)
        TST.L   D1                              | test divisor
        BNE.B   FIXDIV_EMPTY                    | non-zero: proceed with division
        BRA.B   FIXPT_OVERFLOW                  | divide by zero: return overflow

| ----------------------------------------------------------
| FIXDIV_NO - Normalize divisor: shift left until MSB is set.
| ----------------------------------------------------------
FIXDIV_NO:
        ADDQ.W  #0x1,D3                         | one more quotient bit available
        ADD.L   D1,D1                           | shift divisor left
FIXDIV_EMPTY:
        BPL.B   FIXDIV_NO                       | MSB not set: keep shifting
        TST.L   D2                              | test dividend
        BEQ.B   FIXMUL_EXIT_2                   | zero: result = 0
        BRA.B   FIXDIV_CONT_2                   | enter dividend normalization

| ----------------------------------------------------------
| FIXDIV_NO_2 - Normalize dividend: shift left until MSB is set.
| ----------------------------------------------------------
FIXDIV_NO_2:
        SUBQ.W  #0x1,D3                         | one fewer quotient bit
        ADD.L   D2,D2                           | shift dividend left
FIXDIV_CONT_2:
        BPL.B   FIXDIV_NO_2                     | MSB not set: keep shifting
        TST     D3                              | any quotient bits to compute?
        BLE.B   FIXMUL_EXIT_2                   | none: result underflows to 0
        CMPI    #0x1F,D3                        | more than 31 bits needed?
        BLE.B   FIXDIV_LOOP_2                   | no: proceed with division loop
        BRA.B   FIXPT_OVERFLOW                  | yes: overflow

| ----------------------------------------------------------
| FIXDIV_LOOP - shift-and-subtract binary division of D2 by D1: one
| quotient bit into D0 per step (D3+1 steps, entered at the compare);
| a carry out of D2 forces the subtract. The last bit is the round bit.
| ----------------------------------------------------------
FIXDIV_LOOP:
        ADD.L   D0,D0                           | shift quotient left for next bit
        ADD.L   D2,D2                           | shift remainder left (next bit in)
        BCS.B   FIXDIV_CONT_3                   | carry out: remainder >= divisor
FIXDIV_LOOP_2:
        CMP.L   D1,D2                           | compare remainder vs divisor
        BCS.B   FIXDIV_CONT_4                   | remainder < divisor: quotient bit = 0
FIXDIV_CONT_3:
        SUB.L   D1,D2                           | subtract divisor from remainder
        ADDQ.W  #0x1,D0                         | set quotient bit = 1
FIXDIV_CONT_4:
        DBF     D3,FIXDIV_LOOP                  | loop for all quotient bits
        LSR.L   #0x1,D0                         | shift out guard bit; C = rounding bit
        BCC     FIXMUL_EXIT                     | no rounding: check sign and return
        ADDQ.L  #0x1,D0                         | round up quotient
        BRA     FIXMUL_EXIT                     | check sign and return

| ----------------------------------------------------------
|
| _FracSqrt ($A849): square root of a Fract (2.30)
| Pascal: FUNCTION FracSqrt(x: Fract): Fract;
| Entry: after FIXPT_ENTRY, x = $08(A6); result at $0C(A6)
| Exit:  result = sqrt(x), rounded; x and the result are taken as
|        unsigned (0 <= x < 4, 0 <= result < 2); all registers except A0
|        preserved
| Bit-by-bit (schoolbook) square root: radicand in D2:D3, root in D0 with
| the trial bits "01" in D1 ($40000000); 32 steps give 31 root bits plus a
| rounding bit. The borrow of each trial subtraction is the complement of
| the next root bit.
|
FracSqrt:
        BSR     FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVE.L  0x8(A6),D3                      | D3 = x (unsigned radicand)
        MOVEQ.L #0x0,D0                         | D0 = root accumulator
        MOVEQ.L #0x1,D1                         | D1 = trial subtraction constant
        ROR.L   #0x2,D1                         | D1 = $40000000 (trial bits 01)
        MOVEQ.L #0x0,D2                         | D2 = high long of radicand D2:D3
        MOVEQ.L #0x1F,D4                        | 32 steps (DBF count 31)
FRACSQRT_LOOP:
        SUB.L   D1,D3                           | trial subtract: remainder -= trial
        SUBX.L  D0,D2                           | extended subtraction with borrow
        BCC.B   FRACSQRT_NO                     | no borrow: root bit = 1, keep the result
        ADD.L   D1,D3                           | restore: undo failed subtraction
        ADDX.L  D0,D2                           | restore extended remainder
FRACSQRT_NO:
        EORI.B  #0x10,CCR                       | complement X: X = new root bit
        ADDX.L  D0,D0                           | shift root left, insert result bit
        ADD.L   D3,D3                           | shift radicand left (next bit pair)
        ADDX.L  D2,D2                           | shift extended remainder left
        ADD.L   D3,D3                           | second shift of bit pair
        ADDX.L  D2,D2                           | second shift of remainder
        DBF     D4,FRACSQRT_LOOP                | loop for all 32 root bits
        LSR.L   #0x1,D0                         | shift out guard bit; C = round bit
        BCC     FIXMUL_EXIT_3                   | no rounding: return result
        ADDQ.L  #0x1,D0                         | round up root
        BRA     FIXMUL_EXIT_3                   | return via the one-parameter exit

| ----------------------------------------------------------
|
| _FixRatio ($A869): ratio of two integers as a Fixed value
| Pascal: FUNCTION FixRatio(numer, denom: INTEGER): Fixed;
| Entry: after FIXPT_ENTRY, denom = $08(A6).W, numer = $0A(A6).W;
|        result at $0C(A6)
| Exit:  result = numer/denom, truncated toward zero; numer = denom
|        (including 0/0) gives exactly 1.0; denom = 0 gives $7FFFFFFF,
|        or $80000001 if numer < 0 (as documented in IM I-467)
| Integer part by DIVS of the magnitudes, fraction by DIVU of the
| remainder shifted left 16; the sign is applied at FIXRATIO_EXIT.
|
FixRatio:
        BSR     FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEM   0x8(A6),D1-D2                   | D1 = denom, D2 = numer (sign-extended)
        CMP     D1,D2                           | numer == denom?
        BEQ.B   FIXRATIO_EXIT_2                 | yes: return exactly 1.0 ($10000)
        BSR     FIXMUL_CONT_8                   | D1/D2 = magnitudes, D6.B = result sign
        TST.L   D1                              | test denominator
        BNE.B   FIXRATIO_EMPTY                  | non-zero: safe to divide
        MOVEQ.L #-0x1,D0                        | D0 = $FFFFFFFF
        LSR.L   #0x1,D0                         | D0 = $7FFFFFFF (max positive Fixed)
        BRA.B   FIXRATIO_EXIT                   | apply sign and return

| ----------------------------------------------------------
| FIXRATIO_EMPTY - Standard Fixed ratio: integer part via DIVS,
| fractional part via DIVU on remainder.
| ----------------------------------------------------------
FIXRATIO_EMPTY:
        DIVS    D1,D2                           | D2.hi = remainder, D2.lo = quotient
        MOVE    D2,D0                           | D0 = integer quotient
        SWAP    D0                              | move integer to high word of result
        CLR     D2                              | clear quotient, keep remainder in hi word
        DIVU    D1,D2                           | D2 = (remainder<<16) / denom = fraction
        MOVE    D2,D0                           | D0.lo = fractional part
FIXRATIO_EXIT:
        TST.B   D6                              | check sign flag
        BEQ.B   FIXRATIO_CONT                   | same signs: result positive
        NEG.L   D0                              | different signs: negate result
FIXRATIO_CONT:
        BRA     FIXMUL_EXIT_3                   | return Fixed result

| ----------------------------------------------------------
| FIXRATIO_EXIT_2 - numer == denom: return Fixed 1.0 ($00010000).
| ----------------------------------------------------------
FIXRATIO_EXIT_2:
        MOVEQ.L #0x1,D0                         | D0 = 1
        SWAP    D0                              | D0 = $00010000 = Fixed 1.0
        BRA     FIXMUL_EXIT_3                   | return

| ----------------------------------------------------------
|
| _LoWord ($A86B): low-order word of a long integer
| Pascal: FUNCTION LoWord(x: LONGINT): INTEGER;
| Entry: 4(SP) = x, 8(SP) = INTEGER result slot (no frame, no registers)
| Exit:  result = bits 15..0 of x; x removed from the stack
|
LoWord:
        MOVE    0x6(SP),0x8(SP)                 | copy low word to result position
        BRA.B   HIWORD_EXIT                     | shared return

| ----------------------------------------------------------
|
| _HiWord ($A86A): high-order word of a long integer
| Pascal: FUNCTION HiWord(x: LONGINT): INTEGER;
| Entry: 4(SP) = x, 8(SP) = INTEGER result slot (no frame, no registers)
| Exit:  result = bits 31..16 of x; x removed from the stack
| HIWORD_EXIT (Apple: StripRet) is shared with LoWord and FixRound.
|
HiWord:
        MOVE    0x4(SP),0x8(SP)                 | copy high word to result position
HIWORD_EXIT:
        MOVE.L  (SP)+,(SP)                      | slide return addr down over param
        RTS                                     | return

| ----------------------------------------------------------
|
| _FixRound ($A86C): round a Fixed value to an integer
| Pascal: FUNCTION FixRound(x: Fixed): INTEGER;
| Entry: 4(SP) = x, 8(SP) = INTEGER result slot (no frame; uses D0-D1)
| Exit:  x >= 0: result = high word of x + 1/2 ($00008000), i.e. rounded
|        with .5 going up; $7FFF on overflow
|        x < 0: adds -1/2 ($FFFF8000) and takes the high word, i.e.
|        floor(x - 1/2): one less than the rounded value unless the low
|        word of x is $8000; $8000 (-32768) on overflow
| IM I-467 documents FixRound for positive x only. Apple later added
| $7FFF instead of -1/2 for x < 0 (Munger.a change <C156>, Sep 1986).
|
FixRound:
        MOVEQ.L #0x1,D1                         | D1 = 1
        ROR     #0x1,D1                         | D1 = $00008000 (Fixed 1/2)
        MOVE.L  0x4(SP),D0                      | D0 = x
        BPL.B   FIXROUND_CONT                   | x >= 0: add +1/2
        NEG.L   D1                              | x < 0: D1 = $FFFF8000 (-1/2)
FIXROUND_CONT:
        ADD.L   D1,D0                           | D0 += 0.5 (or -0.5)
        BVC.B   FIXROUND_NO                     | no overflow: extract integer
        BPL.B   FIXROUND_CONT_2                 | wrapped to >= 0: x < 0, pin to $8000
        SUBQ.W  #0x1,D1                         | x > 0 overflow: D1 = $00007FFF
FIXROUND_CONT_2:
        SWAP    D1                              | move clamp value to high word
        MOVE.L  D1,D0                           | D0 = clamped result
FIXROUND_NO:
        SWAP    D0                              | D0.W = high word (floor of the sum)
        MOVE    D0,0x8(SP)                      | store word result
        BRA.B   HIWORD_EXIT                     | return (strip params)

| ----------------------------------------------------------
|
| _FracCos ($A847): cosine of an angle in radians
| Pascal: FUNCTION FracCos(x: Fixed): Fract;
| Entry: after FIXPT_ENTRY, x = $08(A6) (Fixed, radians); result at
|        $0C(A6)
| Exit:  result = cos(x) as a Fract (2.30); all registers except A0
|        preserved
| Computed as sin(x + pi/2): enters the FracSin code with D6 = 2 (an
| offset of two octants of pi/4); cos is even, so a negative x is just
| replaced by |x| (see FracSin for the shared core).
|
FracCos:
        BSR     FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEQ.L #0x2,D6                         | D6 = 2: phase shift pi/2 (cosine)
        BRA.B   FRACSIN_CONT                    | enter the shared sine code

| ----------------------------------------------------------
|
| _FracSin ($A848): sine of an angle in radians
| Pascal: FUNCTION FracSin(x: Fixed): Fract;
| Entry: after FIXPT_ENTRY, x = $08(A6) (Fixed, radians); result at
|        $0C(A6)
| Exit:  result = sin(x) as a Fract (2.30); all registers except A0
|        preserved
| Shared core FRACSIN_CONT (Apple: FSin2); D6 counts octants of pi/4 and
| only its low 3 bits are used:
|   D6 = 0 (FracSin) or 2 (FracCos, cos x = sin(x + pi/2))
|   x < 0: FracSin adds 4 (sin(-x) = sin(x + pi)); FracCos does not
|   D6 += |x| div (pi/4) (DIVU by $C910 = pi/4 in Fixed), rm = remainder
|   D6 odd: reduced angle r = pi/4 - rm, else r = rm (0 <= r <= pi/4)
|   bit (D6 mod 8) of $66 set (octants 1,2,5,6): result = cos(r), else sin(r)
|   bit (D6 mod 8) of $F0 set (octants 4..7): result negated
| With t = r/2 as a Fract and t2 = t*t (FracMul):
|   sin(r) = t*(sn0 + t2*(sn1 + t2*sn2))
|   cos(r) = cs0 + t2*(cs1 + t2*(cs2 + t2*cs3))
| (coefficients at FRACSIN_SN0 and FRACSIN_CS0).
|
FracSin:
        BSR     FIXPT_ENTRY                     | set up LINK frame, save regs
        MOVEQ.L #0x0,D6                         | D6 = 0: sine, no phase shift
FRACSIN_CONT:
        MOVE.L  0x8(A6),D3                      | D3 = x (Fixed radians)
        BPL.B   FRACSIN_NO                      | positive: no negation needed
        TST.L   D6                              | cosine entry (D6 = 2)?
        BNE.B   FRACSIN_CONT_2                  | yes: cos(-x) = cos(x), just negate
        ADDQ.W  #0x4,D6                         | sine: +4 octants (sin(-x) = sin(x+pi))
FRACSIN_CONT_2:
        NEG.L   D3                              | D3 = |x|
FRACSIN_NO:
        MOVE.L  #0xC910,D5                      | D5 = $C910 = pi/4 in Fixed
        DIVU    D5,D3                           | D3 = rem:quot of |x| / (pi/4)
        ADD.L   D3,D6                           | D6 += octant (only bits 0-2 are used)
        CLR     D3                              | drop the quotient
        SWAP    D3                              | D3 = rm = |x| mod (pi/4), Fixed
        BTST    #0x0,D6                         | odd octant?
        BEQ.B   FRACSIN_REDUCED                 | even: r = rm
        SUB     D5,D3                           | odd: D3 = rm - pi/4
        NEG     D3                              | r = pi/4 - rm
| FRACSIN_REDUCED -- D3.W = reduced angle r (0..pi/4, Fixed fraction)
FRACSIN_REDUCED:
        SWAP    D3                              | D3 = r << 16
        LSR.L   #0x3,D3                         | D3 = t = r/2 as a Fract (r * 2^29)
        MOVE.L  A2,-(SP)                        | save A2
        SUBA.L  #0x10,SP                        | reserve 4 FracMul result slots
        MOVE.L  D3,-(SP)                        | push t
        MOVE.L  D3,-(SP)                        | push t
        BSR     FracMul                         | t*t
        MOVE.L  (SP)+,D5                        | D5 = t2 = t*t
        MOVE.B  #0x66,-(SP)                     | octant mask $66: octants 1,2,5,6
        BTST    D6,(SP)+                        | test bit (D6 mod 8), pop the mask
        BNE.B   FRACSIN_POLYCOS                 | set: use the cosine polynomial
        LEA.L   FRACSIN_SN0(PC),A2              | clear: sine coefficients sn0..sn2
        MOVEQ.L #0x4,D4                         | 2 Horner steps (offsets 4, 0)
        BRA.B   FRACSIN_POLY                    | evaluate

| ----------------------------------------------------------
|
| FRACSIN_POLYCOS - FracSin/FracCos: select the cosine polynomial (the
| label name is a misnomer). FRACSIN_POLY: Horner evaluation in t2 (D5),
| starting with the last coefficient; each FracMul result replaces the
| accumulator on the stack. The sine polynomial is then multiplied by t;
| finally the result is negated for octants 4..7 and returned as a Fract.
| Apple source names: PolyCos, PolyLoop, NotSine (System 7.1 Toolbox/Munger/Munger.a)
|
FRACSIN_POLYCOS:
        LEA.L   FRACSIN_CS0(PC),A2              | cosine coefficients cs0..cs3
        MOVEQ.L #0x8,D4                         | 3 Horner steps (offsets 8, 4, 0)
FRACSIN_POLY:
        MOVE.L  0x4(A2,D4.W),-(SP)              | acc = last coefficient (sn2 or cs3)
FRACSIN_POLY_LOOP:
        MOVE.L  D5,-(SP)                        | push t2
        BSR     FracMul                         | acc = acc * t2
        MOVE.L  0x0(A2,D4.W),D0                 | load next coefficient from table
        ADD.L   D0,(SP)                         | add coefficient to running total
        SUBQ.W  #0x4,D4                         | move to next table entry
        BPL.B   FRACSIN_POLY_LOOP               | loop until all terms processed
        MOVE.B  #0x66,-(SP)                     | octant mask $66 again
        BTST    D6,(SP)+                        | cosine polynomial used?
        BNE.B   FRACSIN_NOTSINE                 | yes: done
        MOVE.L  D3,-(SP)                        | sine: push t
        JSR     FracMul(PC)                     | acc = acc * t
FRACSIN_NOTSINE:
        MOVE.L  (SP)+,D0                        | pop final result
        MOVE.L  (SP)+,A2                        | restore A2
        MOVE.B  #0xF0,-(SP)                     | mask $F0: octants 4..7 are negative
        BTST    D6,(SP)+                        | test if result should be negated
        BEQ.B   FRACSIN_SIGN                    | skip if positive result
        NEG.L   D0                              | negate result
FRACSIN_SIGN:
        BRA     FIXMUL_EXIT_3                   | return the Fract via one-parameter exit

| ----------------------------------------------------------
|
| FRACSIN_SN0 - sine polynomial coefficients (Fract): sn0 = $7FFFD609
| (1.99999), sn1 = $AAB3314D (-1.33281), sn2 = $10A208E5 (0.25989)
| Apple source names: sn0..sn2 (System 7.1 Toolbox/Munger/Munger.a)
|
FRACSIN_SN0:
  .byte 0x7F,0xFF,0xD6,0x09,0xAA,0xB3           | sn0 = $7FFFD609, sn1 = $AAB3...
  .byte 0x31,0x4D,0x10,0xA2,0x08,0xE5           | ...314D, sn2 = $10A208E5

| FRACSIN_CS0 - cosine polynomial coefficients (Fract): cs0 = $40000000
| (1.0), cs1 = $800011A7 (-2.00000), cs2 = $2AA7F29A (0.66650),
| cs3 = $FA6E2A42 (-0.08703); Apple source names: cs0..cs3
FRACSIN_CS0:
  .byte 0x40,0x00,0x00,0x00,0x80,0x00           | cs0 = $40000000, cs1 = $8000...
  .byte 0x11,0xA7,0x2A,0xA7,0xF2,0x9A           | ...11A7, cs2 = $2AA7F29A
  .byte 0xFA,0x6E,0x2A,0x42                     | cs3 = $FA6E2A42

| ----------------------------------------------------------
|
| _FixATan2 ($A818): arctangent of y/x, i.e. the angle of the point (x,y)
| Pascal: FUNCTION FixATan2(x, y: LONGINT): Fixed;
| Entry: after FIXPT_ENTRY, x = $0C(A6), y = $08(A6); result at $10(A6)
| Exit:  result = angle in radians (Fixed), -pi..pi; (0,0) gives 0;
|        all registers except A0 preserved
| Only the ratio of |x| and |y| is used, so x and y may be of any one
| type (LongInt, Fixed or Fract). D6 flags: bit 0 = y < 0, bit 1 = x < 0,
| bit 2 = |y| > |x|. t = min(|x|,|y|) / max(|x|,|y|) by FracDiv (0..1);
| a = atan(t) = t*(at0 + t2*(at1 + ... + t2*at5)), t2 = t*t (FracMul,
| ATAN_COEFF_TBL), converted Fract -> Fixed with rounding; then
| a := pi/2 - a if bit 2, pi - a if bit 1, -a if bit 0 (pi/2 = $00019220).
| The $80000000 clamps use SUBQ.W, giving $8000FFFF instead of $7FFFFFFF;
| Apple later patched them to SUBQ.L (FixTypoInFixAtan2, System 7.1
| MungerPatches.a).
|
FixATan2:
        BSR     FIXPT_ENTRY                     | set up stack frame
        MOVEQ.L #0x0,D6                         | clear sign/swap flags
        MOVE.L  0xC(A6),D3                      | D3 = x
        BPL.B   ATAN_DVSR_ABS                   | x >= 0
        ADDQ.W  #0x2,D6                         | bit 1: x < 0
        NEG.L   D3                              | D3 = |x|
        BPL.B   ATAN_DVSR_ABS                   | branch unless $80000000
        SUBQ.W  #0x1,D3                         | meant $7FFFFFFF; .W gives $8000FFFF
ATAN_DVSR_ABS:
        MOVE.L  0x8(A6),D0                      | D0 = y
        BPL.B   ATAN_DVND_ABS                   | y >= 0
        ADDQ.W  #0x1,D6                         | bit 0: y < 0
        NEG.L   D0                              | D0 = |y|
        BPL.B   ATAN_DVND_ABS                   | branch unless $80000000
        SUBQ.W  #0x1,D0                         | meant $7FFFFFFF; .W gives $8000FFFF
| ATAN_DVND_ABS -- rejoin point of Apple's FixTypoInFixAtan2 patch (Plus $15A78)
ATAN_DVND_ABS:
        MOVE.L  A2,-(SP)                        | save A2
        SUBA.L  #0x20,SP                        | reserve 8 FracDiv/FracMul result slots
        CMP.L   D3,D0                           | compare |y| with |x|
        BLE.B   ATAN_NO_SWAP                    | |y| <= |x|: t = |y|/|x|
        ADDQ.W  #0x4,D6                         | bit 2: |y| > |x|, t = |x|/|y|
        MOVE.L  D3,-(SP)                        | push |x| (numerator)
        BEQ.B   ATAN_DVSR_ZERO                  | x = 0: t = 0
        MOVE.L  D0,-(SP)                        | push |y| (denominator)
        BRA.B   ATAN_DO_DIVIDE                  | proceed to division

| ----------------------------------------------------------
|
| ATAN_DVSR_ZERO - x = 0 (with |y| > 0): t = 0, so a = 0 and the fix-up
| gives +-pi/2. ATAN_RESULT_ZERO: also y = 0 (or 0/0) with a = 0. Both
| drop the reserved area and the pushed value and skip the polynomial.
| Apple source names: NoPoly, NoPoly2 (System 7.1 Toolbox/Munger/Munger.a)
|
ATAN_DVSR_ZERO:
        MOVE.L  D3,D0                           | D0 = 0 (x was 0)
ATAN_RESULT_ZERO:
        ADDA.L  #0x24,SP                        | drop 32-byte area + pushed value
        BRA.B   ATAN_RESTORE_A2                 | skip polynomial: quadrant fix-up

| ----------------------------------------------------------
|
| ATAN_NO_SWAP - |y| <= |x|: t = |y|/|x|. ATAN_DO_DIVIDE: t = FracDiv,
| t2 = FracMul(t,t), then Horner evaluation from at5 (5 steps) and a
| final multiply by t; each result replaces the accumulator on the stack.
| Apple source names: bigger, GetATanArg (System 7.1 Toolbox/Munger/Munger.a)
|
ATAN_NO_SWAP:
        MOVE.L  D0,-(SP)                        | push |y| (numerator)
        BEQ.B   ATAN_RESULT_ZERO                | y = 0 (or 0/0): angle 0 or pi
        MOVE.L  D3,-(SP)                        | push |x| (denominator)
ATAN_DO_DIVIDE:
        BSR     FracDiv                         | t = smaller/larger (Fract, 0..1)
        MOVE.L  (SP),D3                         | D3 = t
        MOVE.L  (SP),-(SP)                      | duplicate for squaring
        BSR     FracMul                         | square the ratio
        MOVE.L  (SP)+,D5                        | D5 = t2 = t*t
        LEA.L   ATAN_COEFF_TBL(PC),A2           | A2 -> coefficients at0..at5
        MOVE.L  0x14(A2),-(SP)                  | acc = at5
        MOVEQ.L #0x10,D4                        | 5 Horner steps (offsets 16..0)
ATAN_POLY_LOOP:
        MOVE.L  D5,-(SP)                        | push t2
        BSR     FracMul                         | multiply accumulator by ratio^2
        MOVE.L  0x0(A2,D4.W),D0                 | load next coefficient
        ADD.L   D0,(SP)                         | add to running sum (Horner's method)
        SUBQ.W  #0x4,D4                         | advance to next coefficient
        BPL.B   ATAN_POLY_LOOP                  | loop for at4..at0
        MOVE.L  D3,-(SP)                        | push t
        JSR     FracMul(PC)                     | multiply polynomial result by ratio
        MOVE.L  (SP)+,D0                        | D0 = a = atan(t) as a Fract
        MOVEQ.L #0xE,D2                         | shift count 14: Fract -> Fixed
        LSR.L   D2,D0                           | shift right 14 to scale result
        BCC.B   ATAN_RESTORE_A2                 | skip if no rounding needed
        ADDQ.L  #0x1,D0                         | round up if shifted-out bit was set
| ATAN_RESTORE_A2 (Apple: bypass) -- quadrant fix-up of a = atan(t) in D0
ATAN_RESTORE_A2:
        MOVE.L  (SP)+,A2                        | restore A2
        MOVE.L  #0x19220,D5                     | D5 = pi/2 in fixed-point (0x19220)
        BTST    #0x2,D6                         | |y| > |x|?
        BEQ.B   ATAN_CHK_DVSR                   | skip if not swapped
        SUB.L   D5,D0                           | D0 = a - pi/2
        NEG.L   D0                              | D0 = pi/2 - a
ATAN_CHK_DVSR:
        BTst    #0x1,D6                         | x < 0?
        BEQ.B   ATAN_CHK_DVND                   | no
        LSL.L   #0x1,D5                         | D5 = pi (double pi/2)
        SUB.L   D5,D0                           | D0 = a - pi
        NEG.L   D0                              | D0 = pi - a
ATAN_CHK_DVND:
        BTst    #0x0,D6                         | y < 0?
        BEQ.B   ATAN_RETURN                     | no
        NEG.L   D0                              | angle = -angle
ATAN_RETURN:
        BRA     FIXMUL_EXIT_2                   | return via the two-parameter exit

| ----------------------------------------------------------
|
| ATAN_COEFF_TBL - arctangent polynomial coefficients at0..at5 (Fract):
| $3FFFA073 (0.99998), $EAB64EBE (-0.33262), $0C62F72C (0.19354),
| $F88C77F2 (-0.11643), $035E92FE (0.05265), $FF3FFE62 (-0.01172)
| Apple source names: at0..at5 (System 7.1 Toolbox/Munger/Munger.a)
|
ATAN_COEFF_TBL:
  .byte 0x3F,0xFF,0xA0,0x73,0xEA,0xB6           | at0 = $3FFFA073, at1 = $EAB6...
  .byte 0x4E,0xBE,0x0C,0x62,0xF7,0x2C           | ...4EBE, at2 = $0C62F72C
  .byte 0xF8,0x8C,0x77,0xF2,0x03,0x5E           | at3 = $F88C77F2, at4 = $035E...
  .byte 0x92,0xFE,0xFF,0x3F,0xFE,0x62           | ...92FE, at5 = $FF3FFE62

| ----------------------------------------------------------
|
| _Fix2X ($A843): convert Fixed (16.16) to 80-bit SANE extended
| Pascal: FUNCTION Fix2X(x: Fixed): Extended;
| Entry: 4(SP) = x, 8(SP) = address of the 10-byte extended result
|        (no frame; uses D0-D1/A0-A1)
| Exit:  extended stored at the result address; x removed, the result
|        address left on the stack
| D1 = $400E = biased exponent of bit 31 of a Fixed (2^15); the value is
| normalized by shifting left, decrementing the exponent per shift.
|
Fix2X:
        MOVE    #0x400E,D1                      | exponent of bit 31 of a Fixed (2^15)
        BRA.B   FIX_TO_EXTENDED                 | share conversion code with Frac2X

| ----------------------------------------------------------
|
| _Frac2X ($A845): convert Fract (2.30) to 80-bit SANE extended
| Pascal: FUNCTION Frac2X(x: Fract): Extended;
| As Fix2X, with D1 = $4000 = biased exponent of bit 31 of a Fract (2^1).
| FIX_TO_EXTENDED (Apple: ComE) is the shared conversion.
|
Frac2X:
        MOVE    #0x4000,D1                      | exponent of bit 31 of a Fract (2^1)
FIX_TO_EXTENDED:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,D0                        | pop fixed/fract value
        BNE.B   FIX2X_NORMALIZE                 | branch if value is nonzero
        MOVEQ.L #0x0,D1                         | zero: exponent = 0
        BRA.B   FIX2X_STORE                     | store zero extended result

| ----------------------------------------------------------
|
| FIX2X_NORMALIZE - normalize the fixed/fract mantissa
|
FIX2X_NORMALIZE:
        BPL.B   FIX2X_SHIFT_LEFT                | branch if value positive
        ADDI    #-0x8000,D1                     | set sign bit in exponent word
        NEG.L   D0                              | make mantissa positive
        BMI.B   FIX2X_STORE                     | if $80000000, already normalized
FIX2X_SHIFT_LEFT:
        SUBQ.W  #0x1,D1                         | decrement exponent for each left shift
        LSL.L   #0x1,D0                         | shift mantissa left to normalize
        BPL.B   FIX2X_SHIFT_LEFT                | loop until MSB is set (normalized)
FIX2X_STORE:
        MOVE.L  (SP),A1                         | A1 -> destination extended (10 bytes)
        MOVE    D1,(A1)                         | store exponent + sign word
        MOVE.L  D0,0x2(A1)                      | store high 32 bits of mantissa
        CLR.L   0x6(A1)                         | clear low 32 bits of mantissa
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _X2Fix ($A844): convert 80-bit SANE extended to Fixed (16.16)
| Pascal: FUNCTION X2Fix(x: Extended): Fixed;
| Entry: 4(SP) = address of x (10 bytes), 8(SP) = result slot
|        (no frame; uses D0-D1/A0-A1)
| Exit:  result = x rounded to Fixed (the magnitude is rounded up when the
|        first dropped bit is 1); $7FFFFFFF / $80000000 on overflow, also
|        for NaN and infinity; x is assumed to be normalized
|
X2Fix:
        MOVE    #0x400E,D1                      | exponent of bit 31 of a Fixed (2^15)
        BRA.B   X2FIX_CONVERT                   | share conversion code with X2Frac

| ----------------------------------------------------------
|
| _X2Frac ($A846): convert 80-bit SANE extended to Fract (2.30)
| Pascal: FUNCTION X2Frac(x: Extended): Fract;
| As X2Fix, with D1 = $4000; X2FIX_CONVERT (Apple: X2F) is shared.
|
X2Frac:
        MOVE    #0x4000,D1                      | exponent of bit 31 of a Fract (2^1)
X2FIX_CONVERT:
        MOVEM.L (SP)+,A0-A1                     | A0=return addr, A1->extended source
        MOVE    (A1),D0                         | D0 = exponent+sign word of extended
        BCLR    #0xF,D0                         | clear sign bit, keep raw exponent
        SUB     D0,D1                           | D1 = shift count (bias - exponent)
        BLT.B   X2FIX_OVERFLOW                  | overflow if exponent > bias
        MOVE.L  0x2(A1),D0                      | D0 = high 32 bits of mantissa
        TST     D1                              | shift count = 0?
        BNE.B   X2FIX_SHIFT                     | branch if shifting needed
        TST     0x6(A1)                         | check low mantissa for rounding
        BRA.B   X2FIX_CHK_ROUND                 | test rounding bit

| ----------------------------------------------------------
|
| X2FIX_SHIFT - mantissa needs right-shifting by D1 bits
|
X2FIX_SHIFT:
        CMPI    #0x20,D1                        | shift >= 32 bits?
        BLT.B   X2FIX_DO_SHIFT                  | branch if shift < 32
        BNE.B   X2FIX_UNDERFLOW                 | shift > 32: result is 0
        MOVEQ.L #0x0,D0                         | shift exactly 32: D0=0
        TST     0x2(A1)                         | check MSB for rounding
X2FIX_CHK_ROUND:
        BMI.B   X2FIX_ROUND_UP                  | round up if MSB of remainder set
        BRA.B   X2FIX_CHK_SIGN                  | no rounding needed

| ----------------------------------------------------------
|
| X2FIX_DO_SHIFT - right-shift mantissa by D1 (1..31) bits
|
X2FIX_DO_SHIFT:
        LSR.L   D1,D0                           | shift mantissa right by D1
        BCC.B   X2FIX_CHK_SIGN                  | skip rounding if no carry out
X2FIX_ROUND_UP:
        ADDQ.L  #0x1,D0                         | round magnitude up (dropped bit was 1)
        BCS.B   X2FIX_OVERFLOW                  | overflow from rounding: clamp
X2FIX_CHK_SIGN:
        TST     (A1)                            | test sign of original extended
        BMI.B   X2FIX_NEGATE                    | branch if negative: negate result
        TST.L   D0                              | positive: check for overflow
        BMI.B   X2FIX_OVERFLOW                  | bit 31 set = positive overflow
X2FIX_STORE:
        MOVE.L  D0,(SP)                         | store result on stack
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| X2FIX_UNDERFLOW - shift > 32: result underflows to 0
|
X2FIX_UNDERFLOW:
        MOVEQ.L #0x0,D0                         | result is zero magnitude
X2FIX_NEGATE:
        NEG.L   D0                              | negate for signed result
        BLE.B   X2FIX_STORE                     | if <= 0, store and return
| fall through to overflow handler
X2FIX_OVERFLOW:
        TST     (A1)                            | check sign of extended source
X2FIX_CLAMP:
        BPL.B   X2FIX_POS_CLAMP                 | branch if positive overflow
        MOVEQ.L #0x1,D0                         | negative overflow: start with 1
        BRA.B   X2FIX_ROTATE                    | rotate to get $80000000

| ----------------------------------------------------------
|
| X2FIX_POS_CLAMP - positive overflow: clamp to $7FFFFFFF
|
X2FIX_POS_CLAMP:
        CLR.L   D0                              | D0 = 0
        SUBQ.L  #0x2,D0                         | D0 = $FFFFFFFE
X2FIX_ROTATE:
        ROR.L   #0x1,D0                         | rotate right: $01->$80000000, $FFFFFFFE->$7FFFFFFF
        BRA.B   X2FIX_STORE                     | store clamped result and return

| ----------------------------------------------------------
|
| _Fix2Long ($A840): convert Fixed (16.16) to LongInt
| Pascal: FUNCTION Fix2Long(x: Fixed): LONGINT;
| Entry: 4(SP) = x, 8(SP) = result slot (no frame; uses D0-D1/A0)
| Exit:  result = x rounded to an integer, halves away from zero
|        (Fix2Long($00018000) = 2)
| The magnitude is shifted right D1 = 16 bits and rounded with the last
| bit shifted out (FIX2LONG_SHIFT, Apple: ComFF, shared with Frac2Fix).
|
Fix2Long:
        MOVEQ.L #0x10,D1                        | shift 16 to discard fraction bits
        BRA.B   FIX2LONG_SHIFT                  | share code with Frac2Fix

| ----------------------------------------------------------
|
| _Frac2Fix ($A842): convert Fract (2.30) to Fixed (16.16)
| Pascal: FUNCTION Frac2Fix(x: Fract): Fixed;
| As Fix2Long, with a shift of D1 = 14 bits (rounded, halves away from 0).
| The rounding increment is ADDQ.W, so if the shifted magnitude has a low
| word of $FFFF the carry into the high word is lost (Apple changed both
| increments to ADDQ.L later: Munger.a change <A279>, Oct 1986).
|
Frac2Fix:
        MOVEQ.L #0xE,D1                         | shift 14 to convert 2.30 -> 16.16
FIX2LONG_SHIFT:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,D0                        | pop input value
        BPL.B   FIX2LONG_POS                    | branch if positive
        NEG.L   D0                              | make positive for shifting
        LSR.L   D1,D0                           | right-shift by D1 bits
        BCC.B   FIX2LONG_NEG_RND                | skip rounding if no carry
        ADDQ.W  #0x1,D0                         | round magnitude up (.W: no carry out)
FIX2LONG_NEG_RND:
        NEG.L   D0                              | restore negative sign
        BRA.B   X2FIX_STORE                     | store result and return

| ----------------------------------------------------------
|
| FIX2LONG_POS - positive path: shift and round
|
FIX2LONG_POS:
        LSR.L   D1,D0                           | right-shift positive value
        BCC.B   X2FIX_STORE                     | skip rounding if no carry
        ADDQ.W  #0x1,D0                         | round up (.W: no carry out of bit 15)
        BRA.B   X2FIX_STORE                     | store result and return

| ----------------------------------------------------------
|
| _Long2Fix ($A83F): convert LongInt to Fixed (16.16)
| Pascal: FUNCTION Long2Fix(x: LONGINT): Fixed;
| Entry: 4(SP) = x, 8(SP) = result slot (no frame; uses D0-D1/A0)
| Exit:  result = x shifted left 16 (ASL); $7FFFFFFF / $80000000 (by the
|        sign of x) if the shift overflows
|
Long2Fix:
        MOVEQ.L #0x10,D1                        | shift 16 to create 16.16 from integer
        BRA.B   LONG2FIX_SHIFT                  | share code with Fix2Frac

| ----------------------------------------------------------
|
| _Fix2Frac ($A841): convert Fixed (16.16) to Fract (2.30)
| Pascal: FUNCTION Fix2Frac(x: Fixed): Fract;
| As Long2Fix, with a shift of 14 bits; pinned to $7FFFFFFF / $80000000
| on overflow. LONG2FIX_SHIFT (Apple: ComLF) is shared.
|
Fix2Frac:
        MOVEQ.L #0xE,D1                         | shift 14 to convert 16.16 -> 2.30
LONG2FIX_SHIFT:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,(SP)                      | move input to result position
        MOVE.L  (SP),D0                         | D0 = input value
        ASL.L   D1,D0                           | left-shift (arithmetic, preserves sign)
        BVC.B   X2FIX_STORE                     | no overflow: store shifted result
        MOVE.L  (SP),D1                         | overflow: reload original for sign test
        BRA.B   X2FIX_CLAMP                     | clamp to $7FFFFFFF or $80000000
