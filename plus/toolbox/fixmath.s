| Miscellaneous Toolbox Utilities: Fixed-Point Math and SystemEvent
|
| This file contains:
| - Tail end of SANE/math package routines (binary-coded decimal math)
| - Fixed-point <-> extended conversion: Fix2X, Frac2X, X2Fix, X2Frac
| - Fixed-point <-> integer conversion: Fix2Long, Frac2Fix, Long2Fix, Fix2Frac
| - _SystemEvent: dispatches system events by event code
|
| Fixed-point formats (Inside Macintosh I):
| Fixed = 32-bit signed, 16.16 (high word = integer, low word = fraction)
| Fract = 32-bit signed, 2.30 (2 integer bits, 30 fraction bits)
| Extended = 80-bit SANE extended (1 sign + 15 exponent + 64 mantissa)
|
| References:
| Inside Macintosh Vol I, Ch 15: The Scrap Manager
| Inside Macintosh Vol I, Toolbox Utilities (fixed-point math)

| ----------------------------------------------------------
| LongMul ($A867) - 32x32 signed multiply yielding 64-bit result.
| Stack: multiplicand(+$0C), multiplier(+$10), result ptr(+$08).
| Result is two longs (hi:lo) stored at the pointer.
| ----------------------------------------------------------
LongMul:
        BSR     FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEQ.L #0x1,D5                         | D5=1: LongMul mode (64-bit result)
        MOVEM.L 0xC(A6),D1-D2                   | D1=multiplicand, D2=multiplier
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
| RestoreEntries - FixDiv ($A84D): 16.16 fixed-point divide.
| Computes (D1/D2) as Fixed result. D5=-1 selects divide path.
| ----------------------------------------------------------
RestoreEntries:
        BSR     FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEQ.L #-0x1,D5                        | D5=-1: FixDiv mode (shift result left 2)
        BRA.B   FIXMUL_CONT                     | enter shared multiply/divide core

| ----------------------------------------------------------
| FixMul ($A868) - 16.16 fixed-point multiply.
| Computes (D1*D2) >> 16 as Fixed result. D5=0 selects multiply.
| ----------------------------------------------------------
FixMul:
        BSR     FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEQ.L #0x0,D5                         | D5=0: FixMul mode (extract middle 32 bits)
FIXMUL_CONT:
        BSR     FIXMUL_CONT_7                   | load params into D1-D2, set sign in D6
FIXMUL_CONT_2:
        MOVEQ.L #0x1,D4                         | D4 = 0x00010000 (Fixed 1.0)
        SWAP    D4                              | shift to high word
        CMP.L   D4,D1                           | is multiplicand exactly 1.0?
        BNE.B   FIXMUL_NO                       | no: check multiplier
        MOVE.L  D2,D1                           | yes: result = other operand
        BRA.B   FIXMUL_NO_2                     | shortcut: no multiply needed

| ----------------------------------------------------------
| FIXMUL_NO - Check if multiplier is exactly 1.0 (0x10000).
| If so, the result is just the multiplicand.
| ----------------------------------------------------------
FIXMUL_NO:
        CMP.L   D4,D2                           | is multiplier exactly 1.0?
        BNE.B   ALGORITHM                       | no: full multiply needed
FIXMUL_NO_2:
        MOVEQ.L #0x0,D0                         | D0:D4 = 64-bit result
        MOVEQ.L #0x0,D4                         | clear low 32 bits
        MOVE    D1,D4                           | D4 = low word of operand << 16
        SWAP    D4                              | position as fractional part
        SWAP    D1                              | get high word of operand
        MOVE    D1,D0                           | D0 = integer part of result
        BRA.B   FIXMUL_CONT_3                   | go apply mode-specific adjustment

| ----------------------------------------------------------
| ALGORITHM - Full unsigned 32x32 multiply using four 16x16 MULUs.
| Produces 64-bit result in D0 (high) : D4 (low).
| Algorithm: (D1h:D1l) * (D2h:D2l) using schoolbook multiply.
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
        ADD.L   D3,D2                           | D2 = sum of two middle products
        MOVEQ.L #0x0,D3                         | D3 = carry from middle products
        MOVE    D2,D3                           | D3.lo = D2.lo (middle sum low word)
        SWAP    D3                              | D3 = D2.lo << 16 (positioned for D4 add)
        MOVE    D3,D2                           | D2.lo = 0 (clear after swap)
        SWAP    D2                              | D2 = middle sum high word (carry into D0)
        ADD.L   D3,D4                           | add middle contribution to low result
        ADDX.L  D2,D0                           | add carry + high middle to high result
FIXMUL_CONT_3:
        TST.L   D5                              | check operation mode
        BEQ.B   FIXMUL_CONT_4                   | D5=0: FixMul (extract middle 32 bits)
        BPL.B   LONGMUL_EXIT                    | D5>0: LongMul (return full 64-bit result)
        ADD.L   D4,D4                           | D5<0: FixDiv - shift left 2 to get 16.16
        ADDX.L  D0,D0                           | shift with carry through D0:D4
        ADD.L   D4,D4                           | second shift left
        ADDX.L  D0,D0                           | shift with carry
        BRA.B   FIXMUL_CONT_5                   | go round and check overflow

| ----------------------------------------------------------
| FIXMUL_CONT_4 - FixMul: extract middle 32 bits from 64-bit product.
| D0:D4 holds the 64-bit unsigned product; we need bits 16-47.
| ----------------------------------------------------------
FIXMUL_CONT_4:
        SWAP    D0                              | D0.lo = high word of result
        TST     D0                              | overflow if high word non-zero
        BNE.B   FIXMUL_EXIT_5                   | overflow: return max Fixed value
        SWAP    D4                              | D4.lo = bits 16-31 of product
        MOVE    D4,D0                           | D0 = integer part from D4 high word
FIXMUL_CONT_5:
        TST.L   D4                              | check low bits for rounding
        BPL.B   FIXMUL_EXIT                     | MSB clear: no round up needed
        ADDQ.L  #0x1,D0                         | round up result
        BCS.B   FIXMUL_EXIT_5                   | carry out: overflow
FIXMUL_EXIT:
        TST.L   D0                              | check if result fits in signed long
        BMI.B   FIXMUL_EXIT_5                   | bit 31 set: overflow
        TST.B   D6                              | check sign flag from operand signs
        BEQ.B   FIXMUL_EXIT_2                   | both same sign: result positive
        NEG.L   D0                              | different signs: negate result
FIXMUL_EXIT_2:
        MOVE    #0x8,0x8(A6)                    | param size = 8 bytes to strip
        MOVE.L  D0,0x10(A6)                     | store Fixed result in return slot
        BRA.B   FIXMUL_EXIT_4                   | shared epilogue

| ----------------------------------------------------------
| FIXMUL_EXIT_3 - Return word-sized result (for FixRatio).
| Stores result and param strip size, then epilogue.
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
| FIXMUL_CONT_6 - Common prologue for fixed-point math routines.
| Creates LINK frame and saves registers.
| Pops own return addr and jumps back (acts as macro).
| ----------------------------------------------------------
| Called by: LongMul, RestoreEntries, FixMul, NewCDialog, DelComp (and 5 more)
FIXMUL_CONT_6:
        MOVE.L  (SP)+,A0                        | save return address (back to caller)
        LINK    A6,#0x0                         | create stack frame (no locals)
        MOVEM.L D0-D6/A1,-(SP)                  | save all working registers
        JMP     (A0)                            | return to caller (inline prologue)

| ----------------------------------------------------------
| FIXMUL_CONT_7 - Load two Fixed params from stack frame into D1-D2.
| Falls through to FIXMUL_CONT_8 for sign normalization.
| ----------------------------------------------------------
FIXMUL_CONT_7:
        MOVEM.L 0x8(A6),D1-D2                   | D1 = first param, D2 = second param
| FIXMUL_CONT_8 -- take absolute values, track sign in D6.
FIXMUL_CONT_8:
        TST.L   D1                              | test sign of first operand
        SMI.B   D6                              | D6 = $FF if negative, $00 if positive
        BPL.B   FIXMUL_SKIP                     | already positive: skip negation
        NEG.L   D1                              | make D1 positive (absolute value)
FIXMUL_SKIP:
        TST.L   D2                              | test sign of second operand
        BPL.B   FIXMUL_SKIP_2                   | already positive: skip negation
        NEG.L   D2                              | make D2 positive (absolute value)
        NOT.B   D6                              | toggle sign flag (XOR signs)
FIXMUL_SKIP_2:
        RTS                                     | return with signs resolved

| ----------------------------------------------------------
| FIXMUL_EXIT_5 - Overflow handler: return max or min Fixed value.
| If D6 (sign) is set, returns $80000001 (most negative).
| If D6 is clear, returns $7FFFFFFF (most positive).
| ----------------------------------------------------------
FIXMUL_EXIT_5:
        MOVEQ.L #0x1,D0                         | D0 = 1
        ROR.L   #0x1,D0                         | D0 = $80000000 (rotate 1 into MSB)
        TST.B   D6                              | check sign flag
        BNE.B   FIXMUL_EXIT_2                   | negative: return $80000000 (min Fixed)
        SUBQ.L  #0x1,D0                         | D0 = $7FFFFFFF (max positive Fixed)
        BRA.B   FIXMUL_EXIT_2                   | store and return

| ----------------------------------------------------------
|
| NewCDialog - FixDiv non-restoring division (full precision).
| D3=31 iterations for 32-bit quotient precision.
|
NewCDialog:
        BSR.B   FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEQ.L #0x1F,D3                        | D3 = 31 bits for full precision
        BRA.B   DELCOMP_CONT                    | enter shared division setup

| ----------------------------------------------------------
| DelComp - FixDiv with reduced 18-bit precision.
| Fewer iterations for faster approximate quotient.
| ----------------------------------------------------------
DelComp:
        BSR.B   FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEQ.L #0x11,D3                        | D3 = 17 bits for reduced precision
DELCOMP_CONT:
        BSR.B   FIXMUL_CONT_7                   | load D1/D2 from params, normalize signs
        MOVEQ.L #0x0,D0                         | D0 = quotient accumulator (starts at 0)
        TST.L   D1                              | test divisor
        BNE.B   DELCOMP_EMPTY                   | non-zero: proceed with division
        BRA.B   FIXMUL_EXIT_5                   | divide by zero: return overflow

| ----------------------------------------------------------
| DELCOMP_NO - Normalize divisor: shift left until MSB is set.
| ----------------------------------------------------------
DELCOMP_NO:
        ADDQ.W  #0x1,D3                         | one more quotient bit available
        ADD.L   D1,D1                           | shift divisor left
DELCOMP_EMPTY:
        BPL.B   DELCOMP_NO                      | MSB not set: keep shifting
        TST.L   D2                              | test dividend
        BEQ.B   FIXMUL_EXIT_2                   | zero: result = 0
        BRA.B   DELCOMP_CONT_2                  | enter dividend normalization

| ----------------------------------------------------------
| DELCOMP_NO_2 - Normalize dividend: shift left until MSB is set.
| ----------------------------------------------------------
DELCOMP_NO_2:
        SUBQ.W  #0x1,D3                         | one fewer quotient bit
        ADD.L   D2,D2                           | shift dividend left
DELCOMP_CONT_2:
        BPL.B   DELCOMP_NO_2                    | MSB not set: keep shifting
        TST     D3                              | any quotient bits to compute?
        BLE.B   FIXMUL_EXIT_2                   | none: result underflows to 0
        CMPI    #0x1F,D3                        | more than 31 bits needed?
        BLE.B   DELCOMP_LOOP_2                  | no: proceed with division loop
        BRA.B   FIXMUL_EXIT_5                   | yes: overflow

| ----------------------------------------------------------
| DELCOMP_LOOP-DELCOMP_CONT_4 - Non-restoring binary long division loop.
| ----------------------------------------------------------
DELCOMP_LOOP:
        ADD.L   D0,D0                           | shift quotient left for next bit
        ADD.L   D2,D2                           | shift remainder left (next bit in)
        BCS.B   DELCOMP_CONT_3                  | carry out: remainder >= divisor
DELCOMP_LOOP_2:
        CMP.L   D1,D2                           | compare remainder vs divisor
        BCS.B   DELCOMP_CONT_4                  | remainder < divisor: quotient bit = 0
DELCOMP_CONT_3:
        SUB.L   D1,D2                           | subtract divisor from remainder
        ADDQ.W  #0x1,D0                         | set quotient bit = 1
DELCOMP_CONT_4:
        DBF     D3,DELCOMP_LOOP                 | loop for all quotient bits
        LSR.L   #0x1,D0                         | shift out guard bit; C = rounding bit
        BCC     FIXMUL_EXIT                     | no rounding: check sign and return
        ADDQ.L  #0x1,D0                         | round up quotient
        BRA     FIXMUL_EXIT                     | check sign and return

| ----------------------------------------------------------
|
| SaveEntries - FracSqrt: 16.16 fixed-point square root.
| Non-restoring algorithm. Input at 0x8(A6).
| Returns 16.16 Fixed via FIXMUL_EXIT_3.
|
SaveEntries:
        BSR     FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVE.L  0x8(A6),D3                      | D3 = input radicand
        MOVEQ.L #0x0,D0                         | D0 = root accumulator
        MOVEQ.L #0x1,D1                         | D1 = trial subtraction constant
        ROR.L   #0x2,D1                         | D1 = $40000000 (start at MSB pair)
        MOVEQ.L #0x0,D2                         | D2 = extended remainder (high word)
        MOVEQ.L #0x1F,D4                        | D4 = 31 iterations for 32-bit root
SAVEENTRIES_LOOP:
        SUB.L   D1,D3                           | trial subtract: remainder -= trial
        SUBX.L  D0,D2                           | extended subtraction with borrow
        BCC.B   SAVEENTRIES_NO                  | no borrow: subtraction succeeded
        ADD.L   D1,D3                           | restore: undo failed subtraction
        ADDX.L  D0,D2                           | restore extended remainder
SAVEENTRIES_NO:
        EORI.B  #0x10,CCR                       | toggle extend flag (invert borrow)
        ADDX.L  D0,D0                           | shift root left, insert result bit
        ADD.L   D3,D3                           | shift radicand left (next bit pair)
        ADDX.L  D2,D2                           | shift extended remainder left
        ADD.L   D3,D3                           | second shift of bit pair
        ADDX.L  D2,D2                           | second shift of remainder
        DBF     D4,SAVEENTRIES_LOOP             | loop for all 32 root bits
        LSR.L   #0x1,D0                         | shift out guard bit; C = round bit
        BCC     FIXMUL_EXIT_3                   | no rounding: return result
        ADDQ.L  #0x1,D0                         | round up root
        BRA     FIXMUL_EXIT_3                   | return via word-result epilogue

| ----------------------------------------------------------
| _FixRatio ($A869) - Compute ratio of two integers as Fixed.
| Stack: numer(+$08 word), denom(+$0A word).
| Returns 16.16 Fixed = numer/denom. Equal inputs = 1.0.
| ----------------------------------------------------------
FixRatio:
        BSR     FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEM   0x8(A6),D1-D2                   | D1 = numer, D2 = denom (words)
        CMP     D1,D2                           | numer == denom?
        BEQ.B   FIXRATIO_EXIT_2                 | yes: return exactly 1.0 ($10000)
        BSR     FIXMUL_CONT_8                   | normalize signs into D6
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
| _LoWord ($A86B) - Extract low word of long.
| Stack: value(+$04 long). Returns word in result position.
| ----------------------------------------------------------
LoWord:
        MOVE    0x6(SP),0x8(SP)                 | copy low word to result position
        BRA.B   HIWORD_EXIT                     | shared return

| ----------------------------------------------------------
| _HiWord ($A86A) - Extract high word of long.
| Stack: value(+$04 long). Returns word in result position.
| ----------------------------------------------------------
HiWord:
        MOVE    0x4(SP),0x8(SP)                 | copy high word to result position
HIWORD_EXIT:
        MOVE.L  (SP)+,(SP)                      | slide return addr down over param
        RTS                                     | return upper word

| ----------------------------------------------------------
| _FixRound ($A86C) - Round 16.16 Fixed to integer.
| Adds 0.5 ($8000) then extracts integer part.
| Clamps to max/min integer on overflow.
| ----------------------------------------------------------
FixRound:
        MOVEQ.L #0x1,D1                         | D1 = 1
        ROR     #0x1,D1                         | D1 = $8000 (0.5 in Fixed fraction)
        MOVE.L  0x4(SP),D0                      | D0 = Fixed value from stack
        BPL.B   FIXROUND_CONT                   | positive: add +0.5
        NEG.L   D1                              | negative: add -0.5 (round toward zero)
FIXROUND_CONT:
        ADD.L   D1,D0                           | D0 += 0.5 (or -0.5)
        BVC.B   FIXROUND_NO                     | no overflow: extract integer
        BPL.B   FIXROUND_CONT_2                 | overflow positive: D1=$8000 -> clamp max
        SUBQ.W  #0x1,D1                         | negative overflow: D1=$7FFF
FIXROUND_CONT_2:
        SWAP    D1                              | move clamp value to high word
        MOVE.L  D1,D0                           | D0 = clamped result
FIXROUND_NO:
        SWAP    D0                              | D0.lo = integer part of rounded value
        MOVE    D0,0x8(SP)                      | store word result
        BRA.B   HIWORD_EXIT                     | return (strip params)

| ----------------------------------------------------------
| SetDeskCPat - Angle-to-slope conversion (tangent approx).
| D6=2: tangent mode. Converts angle in degrees to slope.
| Uses 51472 ($C910 = 360*143.0) as degree scaling factor.
| ----------------------------------------------------------
SetDeskCPat:
        BSR     FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEQ.L #0x2,D6                         | D6 = 2 (tangent computation mode)
        BRA.B   GETCWMGRPORT_CONT               | enter shared angle/slope code

| ----------------------------------------------------------
| GetCWMgrPort - Slope-to-angle conversion (arctangent).
| D6=0: arctangent mode. Converts slope to angle.
| ----------------------------------------------------------
GetCWMgrPort:
        BSR     FIXMUL_CONT_6                   | set up LINK frame, save regs
        MOVEQ.L #0x0,D6                         | D6 = 0 (arctangent mode)
GETCWMGRPORT_CONT:
        MOVE.L  0x8(A6),D3                      | D3 = input angle or slope value
        BPL.B   GETCWMGRPORT_NO                 | positive: no negation needed
        TST.L   D6                              | check computation mode
        BNE.B   GETCWMGRPORT_CONT_2             | tangent mode: just negate input
        ADDQ.W  #0x4,D6                         | arctangent: add correction offset
GETCWMGRPORT_CONT_2:
        NEG.L   D3                              | negate to work with absolute value
GETCWMGRPORT_NO:
        MOVE.L  #0xC910,D5                      | D5 = 51472 (degree scaling constant)
        DIVU    D5,D3                           | D3 = quotient:remainder from scaling
        ADD.L   D3,D6                           | accumulate scaled result with mode offset
        CLR     D3                              | clear low word of D3
        SWAP    D3                              | move result to high word
        BTST    #0x0,D6                         | test sign flag
        BEQ.B   BCD_POSITIVE                    | skip if positive
        SUB     D5,D3                           | negate by subtracting from complement
        NEG     D3                              | final negation
BCD_POSITIVE:
        SWAP    D3                              | swap back
        LSR.L   #0x3,D3                         | divide by 8 for coefficient index
        MOVE.L  A2,-(SP)                        | save A2
        SUBA.L  #0x10,SP                        | allocate 16 bytes on stack
        MOVE.L  D3,-(SP)                        | push coefficient index
        MOVE.L  D3,-(SP)                        | push again for multiply
        BSR     RestoreEntries                  | multiply via SANE routine
        MOVE.L  (SP)+,D5                        | pop partial result
        MOVE.B  #0x66,-(SP)                     | push test pattern for sign bits
        BTST    D6,(SP)+                        | test sign combination flags
        BNE.B   BCD_NEG_OPERAND                 | branch if negative operand
        LEA.L   BCD_COEFF_POS(PC),A2            | positive: use coefficient table BCD_COEFF_POS
        MOVEQ.L #0x4,D4                         | 2 terms (index 0,4)
        BRA.B   BCD_EVAL_POLY                   | skip negative coefficient processing

| ----------------------------------------------------------
|
| BCD_NEG_OPERAND - negative operand path
|
BCD_NEG_OPERAND:
        LEA.L   BCD_COEFF_NEG(PC),A2            | negative: use coefficient table BCD_COEFF_NEG
        MOVEQ.L #0x8,D4                         | 3 terms (index 0,4,8)
BCD_EVAL_POLY:
        MOVE.L  0x4(A2,D4.W),-(SP)              | push initial accumulator from table
BCD_POLY_LOOP:
        MOVE.L  D5,-(SP)                        | push multiplier
        BSR     RestoreEntries                  | multiply accumulator by coefficient
        MOVE.L  0x0(A2,D4.W),D0                 | load next coefficient from table
        ADD.L   D0,(SP)                         | add coefficient to running total
        SUBQ.W  #0x4,D4                         | move to next table entry
        BPL.B   BCD_POLY_LOOP                   | loop until all terms processed
        MOVE.B  #0x66,-(SP)                     | push test pattern for sign bits
        BTST    D6,(SP)+                        | test sign combination flags
        BNE.B   BCD_SKIP_REMAINDER              | skip remainder correction if negative
        MOVE.L  D3,-(SP)                        | push remainder term
        JSR     RestoreEntries(PC)              | multiply in remainder correction
BCD_SKIP_REMAINDER:
        MOVE.L  (SP)+,D0                        | pop final result
        MOVE.L  (SP)+,A2                        | restore A2
        MOVE.B  #0xF0,-(SP)                     | push sign test mask
        BTST    D6,(SP)+                        | test if result should be negated
        BEQ.B   BCD_RESULT_POS                  | skip if positive result
        NEG.L   D0                              | negate result
BCD_RESULT_POS:
        BRA     FIXMUL_EXIT_3                   | return to caller

| ----------------------------------------------------------
|
| BCD_COEFF_POS - polynomial coefficients for positive-operand path
|
BCD_COEFF_POS:
  .byte 0x7F,0xFF,0xD6,0x09,0xAA,0xB3
  .byte 0x31,0x4D,0x10,0xA2,0x08,0xE5

| BCD_COEFF_NEG - polynomial coefficients for negative-operand path
BCD_COEFF_NEG:
  .byte 0x40,0x00,0x00,0x00,0x80,0x00
  .byte 0x11,0xA7,0x2A,0xA7,0xF2,0x9A
  .byte 0xFA,0x6E,0x2A,0x42

| ----------------------------------------------------------
|
| GetCTable - SANE extended-precision division helper
|
| Performs polynomial approximation for division using
| Chebyshev coefficients. D6 tracks sign/swap flags:
| bit 0 = dividend negative, bit 1 = divisor negative,
| bit 2 = operands were swapped (|dividend| > |divisor|)
|
GetCTable:
        BSR     FIXMUL_CONT_6                   | set up stack frame
        MOVEQ.L #0x0,D6                         | clear sign/swap flags
        MOVE.L  0xC(A6),D3                      | D3 = divisor from stack frame
        BPL.B   ATAN_DVSR_ABS                   | skip if divisor positive
        ADDQ.W  #0x2,D6                         | set bit 1: divisor was negative
        NEG.L   D3                              | take absolute value of divisor
        BPL.B   ATAN_DVSR_ABS                   | branch unless $80000000
        SUBQ.W  #0x1,D3                         | clamp $80000000 to $7FFFFFFF
ATAN_DVSR_ABS:
        MOVE.L  0x8(A6),D0                      | D0 = dividend from stack frame
        BPL.B   ATAN_DVND_ABS                   | skip if dividend positive
        ADDQ.W  #0x1,D6                         | set bit 0: dividend was negative
        NEG.L   D0                              | take absolute value of dividend
        BPL.B   ATAN_DVND_ABS                   | branch unless $80000000
        SUBQ.W  #0x1,D0                         | clamp $80000000 to $7FFFFFFF
ATAN_DVND_ABS:
        MOVE.L  A2,-(SP)                        | save A2
        SUBA.L  #0x20,SP                        | allocate 32-byte work area
        CMP.L   D3,D0                           | compare |dividend| vs |divisor|
        BLE.B   ATAN_NO_SWAP                    | branch if |dividend| <= |divisor|
        ADDQ.W  #0x4,D6                         | set bit 2: operands swapped
        MOVE.L  D3,-(SP)                        | push smaller value (divisor)
        BEQ.B   ATAN_DVSR_ZERO                  | if divisor=0, result is 0
        MOVE.L  D0,-(SP)                        | push larger value (dividend)
        BRA.B   ATAN_DO_DIVIDE                  | proceed to division

| ----------------------------------------------------------
|
| ATAN_DVSR_ZERO - divisor is zero, return zero
|
ATAN_DVSR_ZERO:
        MOVE.L  D3,D0                           | D0 = 0 (divisor was zero)
ATAN_RESULT_ZERO:
        ADDA.L  #0x24,SP                        | deallocate work area + pushed values
        BRA.B   ATAN_RESTORE_A2                 | skip to sign adjustment

| ----------------------------------------------------------
|
| ATAN_NO_SWAP - |dividend| <= |divisor|, no swap needed
|
ATAN_NO_SWAP:
        MOVE.L  D0,-(SP)                        | push dividend (smaller or equal)
        BEQ.B   ATAN_RESULT_ZERO                | if dividend=0, result is 0
        MOVE.L  D3,-(SP)                        | push divisor
ATAN_DO_DIVIDE:
        BSR     NewCDialog                      | divide smaller by larger
        MOVE.L  (SP),D3                         | D3 = quotient ratio
        MOVE.L  (SP),-(SP)                      | duplicate for squaring
        BSR     RestoreEntries                  | square the ratio
        MOVE.L  (SP)+,D5                        | D5 = ratio squared
        LEA.L   ATAN_COEFF_TBL(PC),A2           | A2 -> Chebyshev coefficient table
        MOVE.L  0x14(A2),-(SP)                  | push last coefficient as accumulator
        MOVEQ.L #0x10,D4                        | 5 coefficients (index 0x00..0x10)
ATAN_CHEBY_LOOP:
        MOVE.L  D5,-(SP)                        | push ratio squared
        BSR     RestoreEntries                  | multiply accumulator by ratio^2
        MOVE.L  0x0(A2,D4.W),D0                 | load next Chebyshev coefficient
        ADD.L   D0,(SP)                         | add to running sum (Horner's method)
        SUBQ.W  #0x4,D4                         | advance to next coefficient
        BPL.B   ATAN_CHEBY_LOOP                 | loop for all 5 coefficients
        MOVE.L  D3,-(SP)                        | push original ratio
        JSR     RestoreEntries(PC)              | multiply polynomial result by ratio
        MOVE.L  (SP)+,D0                        | D0 = final polynomial result
        MOVEQ.L #0xE,D2                         | shift count = 14 for rounding
        LSR.L   D2,D0                           | shift right 14 to scale result
        BCC.B   ATAN_RESTORE_A2                 | skip if no rounding needed
        ADDQ.L  #0x1,D0                         | round up if shifted-out bit was set
ATAN_RESTORE_A2:
        MOVE.L  (SP)+,A2                        | restore A2
        MOVE.L  #0x19220,D5                     | D5 = pi/2 in fixed-point (0x19220)
        BTST    #0x2,D6                         | were operands swapped?
        BEQ.B   ATAN_CHK_DVSR                   | skip if not swapped
        SUB.L   D5,D0                           | result = pi/2 - result (complement)
        NEG.L   D0                              | negate to get correct quadrant
ATAN_CHK_DVSR:
        BTst    #0x1,D6                         | was divisor negative?
        BEQ.B   ATAN_CHK_DVND                   | skip if divisor positive
        LSL.L   #0x1,D5                         | D5 = pi (double pi/2)
        SUB.L   D5,D0                           | result = pi - result
        NEG.L   D0                              | adjust sign for negative divisor
ATAN_CHK_DVND:
        BTst    #0x0,D6                         | was dividend negative?
        BEQ.B   ATAN_RETURN                     | skip if dividend positive
        NEG.L   D0                              | negate result for negative dividend
ATAN_RETURN:
        BRA     FIXMUL_EXIT_2                   | return result via common exit

| ----------------------------------------------------------
|
| ATAN_COEFF_TBL - Chebyshev polynomial coefficients for arctan approx
|
ATAN_COEFF_TBL:
  .byte 0x3F,0xFF,0xA0,0x73,0xEA,0xB6
  .byte 0x4E,0xBE,0x0C,0x62,0xF7,0x2C
  .byte 0xF8,0x8C,0x77,0xF2,0x03,0x5E
  .byte 0x92,0xFE,0xFF,0x3F,0xFE,0x62

| ----------------------------------------------------------
|
| _Fix2X ($A843) - convert Fixed (16.16) to 80-bit SANE extended
|
| Input: Fixed value on stack, pointer to 10-byte extended on stack
| Output: 80-bit extended written to destination
| Exponent bias for Fixed: 0x400E (integer part has 15 significant bits)
|
Fix2X:
        MOVE    #0x400E,D1                      | exponent bias for Fixed (16.16)
        BRA.B   FIX_TO_EXTENDED                 | share conversion code with Frac2X

| ----------------------------------------------------------
|
| _Frac2X ($A845) - convert Fract (2.30) to 80-bit SANE extended
|
| Exponent bias for Fract: 0x4000 (2 integer bits, 30 fraction bits)
|
Frac2X:
        MOVE    #0x4000,D1                      | exponent bias for Fract (2.30)
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
| _X2Fix ($A844) - convert 80-bit SANE extended to Fixed (16.16)
|
| Input: pointer to 10-byte extended on stack
| Output: Fixed value (long) on stack
| Clamps to $80000000 (negative overflow) or $7FFFFFFF (positive overflow)
|
X2Fix:
        MOVE    #0x400E,D1                      | exponent bias for Fixed (16.16)
        BRA.B   X2FIX_CONVERT                   | share conversion code with X2Frac

| ----------------------------------------------------------
|
| _X2Frac ($A846) - convert 80-bit SANE extended to Fract (2.30)
|
X2Frac:
        MOVE    #0x4000,D1                      | exponent bias for Fract (2.30)
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
        BNE.B   X2FIX_UNDERFLOW                 | shift > 32: result is 0 or -1
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
        ADDQ.L  #0x1,D0                         | round up (half-to-even)
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
| _Fix2Long ($A840) - convert Fixed (16.16) to LongInt
|
| Rounds the fractional part: 0.5 rounds away from zero.
| Fix2Long(0x00018000) = 2 (1.5 rounds to 2)
|
Fix2Long:
        MOVEQ.L #0x10,D1                        | shift 16 to discard fraction bits
        BRA.B   FIX2LONG_SHIFT                  | share code with Frac2Fix

| ----------------------------------------------------------
|
| _Frac2Fix ($A842) - convert Fract (2.30) to Fixed (16.16)
|
| Right-shifts by 14 bits to convert 2.30 -> 16.16 format.
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
        ADDQ.W  #0x1,D0                         | round up (away from zero)
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
        ADDQ.W  #0x1,D0                         | round up
        BRA.B   X2FIX_STORE                     | store result and return

| ----------------------------------------------------------
|
| _Long2Fix ($A83F) - convert LongInt to Fixed (16.16)
|
| Left-shifts by 16 to place integer in high word.
| Clamps on overflow to $7FFFFFFF or $80000000.
|
Long2Fix:
        MOVEQ.L #0x10,D1                        | shift 16 to create 16.16 from integer
        BRA.B   LONG2FIX_SHIFT                  | share code with Fix2Frac

| ----------------------------------------------------------
|
| _Fix2Frac ($A841) - convert Fixed (16.16) to Fract (2.30)
|
| Left-shifts by 14 to convert 16.16 -> 2.30 format.
| Clamps on overflow.
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
