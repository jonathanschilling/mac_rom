|
| resource : 'PACK' 5 - SANE Transcendental Functions (Elems68K)
| Implements: ln(x), log2(x), ln(1+x), exp(x), exp2(x), exp(x)-1,
| sin(x), cos(x), tan(x), atan(x), RandomX
| All operate on 80-bit extended precision via _FP68K calls
| Selector word on stack: bits 14-15 = operand format, bits 0-4 = function
IMPLEMENTS:
        BRA.B   ELEMS_SKIP                      | skip resource header
  .byte 0x00,0x00
  .ascii "PACK"
  .byte 0x00,0x05,0x00,0x01
| PACK 5 entry: dispatch transcendental function
ELEMS_SKIP:
        LINK    A6,#-0x30                       | 48 bytes local (temp extended values)
        MOVEM.L D0-D7/A0-A4,-(SP)               | save all working registers
        CLR.L   D3                              | clear selector
        MOVE.L  (AppPacks_5).w,A0               | lock PACK 5 handle
        MOVE.B  (A0),-0x30(A6)                  | save lock state
        BSET    #0x7,(A0)                       | lock it
| parse selector and operand pointers from stack
        LEA.L   0x4(A6),A3                      | A3 = result pointer slot
        LEA.L   0x8(A6),A0                      | A0 = stack params
        MOVE    (A0)+,D3                        | D3 = selector word
        BPL.B   ELEMS_CONT_2                    | simple function ->
| two-operand function: extract source and dest pointers
        MOVE.L  (A0)+,A4                        | A4 = source operand ptr
        MOVE.L  (A0),D4                         | D4 = dest operand ptr
        BTST    #0xE,D3                         | extended format?
        BNE.B   ELEMS_OK_2                      | yes ->
| non-extended: convert source to extended first
        MOVE.L  (A3),(A0)                       | move result ptr
        MOVE    #0xA,(A3)                       | conversion opcode: to-extended
        MOVE.L  A4,D5                           | save source ptr
        MOVEQ.L #0xF,D2                         | format mask
        CMPI    #-0x7FF0,D3                     | special selector?
        BEQ.B   ELEMS_OK                        | yes ->
ELEMS_CONT:
        MOVE.L  D4,A0                           | A0 = dest operand for classify
        BSR.B   ELEMS_EMPTY                     | classify dest operand
        MOVE    D0,D2                           | D2 = dest class
ELEMS_OK:
        BRA.B   ELEMS_CONT_3                    | -> classify and dispatch

| ----------------------------------------------------------
|
| ELEMS_OK_2
|
ELEMS_OK_2:
        ADDQ.L  #0x4,A0                         | skip past source ptr on stack
        MOVE.L  (A0),D5                         | D5 = dest operand ptr
        MOVE.L  (A3),(A0)                       | move return addr down
        MOVE    #0xE,(A3)                       | FP opcode: extended-to-extended copy
        BRA.B   ELEMS_CONT                      | -> classify and dispatch

| ----------------------------------------------------------
|
| ELEMS_EMPTY: classify extended value at (A0) - returns D0 = SANE class code
| Calls _FP68K classify opcode and normalizes result
|
ELEMS_EMPTY:
        PEA.L   (A0)                            | push value to classify
        PEA.L   -0x4(A6)                        | push result dest
        MOVE    #0x1C,-(SP)                     | FP opcode: classify
        _FP68K                                  | classify the value
        MOVE    -0x4(A6),D0                     | D0 = SANE class code
        BPL.B   ELEMS_DONE                      | positive class -> done
        NEG     D0                              | make class positive
        ORI     #-0x8000,D0                     | set high bit = negative flag
ELEMS_DONE:
        RTS                                     | return D0 = class|sign

| ----------------------------------------------------------
|
| ELEMS_CONT_2
|
| PACK 5 simple function dispatch (single operand)
| Selector bits 0-4 select function:
| 0=ln(x), 2=log2(x), 4=ln(1+x), 6=exp(x), 8=exp2(x),
| 10=exp(x)-1, 12=sin(x), 14=cos(x), 16=tan(x), 18=atan(x), 20=RandomX
ELEMS_CONT_2:
        MOVEQ.L #0xF,D2                         | D2 = format mask
        MOVE.L  (A0),A4                         | A4 = operand handle
        MOVE.L  (A3),(A0)                       | save result location
        MOVE    #0x6,(A3)                       | conversion opcode
        MOVE.L  A4,D5                           | D5 = save operand
| classify operand and check for special cases
ELEMS_CONT_3:
        MOVE.L  D5,A0                           | A0 = operand
        BSR.B   ELEMS_EMPTY                     | classify: D0 = NaN/Inf/Zero/Normal
        MOVE    D0,D1                           | save class
        PEA.L   -0x2(A6)                        | push temp
        MOVE    #0x17,-(SP)                     | FP opcode: procExit
        _FP68K                                  | restore state
        SUBQ.B  #0x3,D2                         | adjust format
        BGE.B   ELEMS_CONT_4                    | extended format ->
| non-extended: copy operand, convert, then operate
        MOVE.L  D5,A0                           | A0 = source operand ptr
        MOVE.L  A4,A1                           | A1 = temp extended dest
        BSR.B   ELEMS_EXIT                      | copy 10-byte value
        MOVE.L  D4,-(SP)                        | push source
        PEA.L   (A4)                            | push dest
        CLR     -(SP)                           | FP opcode: add (finalize conversion)
        _FP68K                                  | convert source to extended
        BRA.B   ELEMS_CONT_5                    | -> dispatch function

| ----------------------------------------------------------
|
| ELEMS_CONT_4: extended format - convert source and dispatch function
|
ELEMS_CONT_4:
        SUBQ.B  #0x3,D1                         | class >= 3 (normal/denormal)?
        BGE.B   ELEMS_OK_3                      | yes, dispatch function ->
        MOVE.L  D5,-(SP)                        | push source operand
        PEA.L   (A4)                            | push dest (temp extended)
        MOVE    #0xE,-(SP)                      | FP opcode: extended copy
        _FP68K                                  | copy source to temp
ELEMS_CONT_5:
        BRA     ELEMS_EXIT_12                   | -> dispatch function

| ----------------------------------------------------------
|
| ELEMS_OK_3: PACK 5 function dispatch via ELEMS_CONT_6 jump table
| D3 bits 1-4 select: 0-3=ln/log2/ln1p, 4-5=exp/exp2,
| 6-7=sin/cos, 8=tan, 9=atan, 10=RandomX, etc.
|
ELEMS_OK_3:
        MOVE    D3,D0                           | D0 = selector word
        ANDI    #0xFE,D0                        | mask to even function index
        MOVE    ELEMS_CONT_6(PC,D0.W),D0        | D0 = jump offset from table
        JMP     ELEMS_OK_3(PC,D0.W)             | dispatch to function handler

| Jump Table
ELEMS_CONT_6:
  .byte  0x01,0x3A,0x01,0x3A,0x01,0x3A
  .byte 0x01,0x3A,0x03,0x26,0x03,0x26
  .byte 0x03,0xD6,0x03,0xD6,0x04,0xE6
  .byte 0x06,0x08,0x06,0xF8,0x07,0x8E
  .byte 0x08,0xE8,0x09,0x3A,0x0A,0x52
  .byte 0x0B,0x3C,0x0C,0x80
| ELEMS_EXIT: copy 10-byte extended value from (A0) to (A1)
| Called by: ELEMS_CONT_85, ELEMS_CONT_26, ELEMS_NO_5, ELEMS_CONT_47, ELEMS_OK_21 (and 26 more)
ELEMS_EXIT:
        MOVE.L  (A0)+,(A1)+                     | copy bytes 0-3
        MOVE.L  (A0)+,(A1)+                     | copy bytes 4-7
        MOVE    (A0),(A1)                       | copy bytes 8-9 (exponent+sign)
        SUBQ.L  #0x8,A1                         | restore A1 to start
        RTS                                     | return with A1 = dest start

| ----------------------------------------------------------
|
| ELEMS_CONT_7: polynomial evaluation using Horner's method
| Evaluates polynomial at (A0) using coefficients from (A1)
| Uses _FP68K for extended-precision multiply and add
|
ELEMS_CONT_7:
        MOVE    (A1)+,D0                        | D0 = polynomial degree
        PEA.L   (A1)                            | push first coefficient ptr
        PEA.L   (A0)                            | push accumulator
        MOVE    #0xE,-(SP)                      | FP opcode: copy (initialize accum)
        _FP68K                                  | accum = first coefficient
| Horner loop: accum = accum * x + next_coeff
ELEMS_OK_4:
        PEA.L   (A2)                            | push x value
        PEA.L   (A0)                            | push accumulator
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | accum *= x
        ADDQ.L  #0x8,A1                         | advance to next coefficient
        ADDQ.L  #0x2,A1                         | (10 bytes per extended)
        PEA.L   (A1)                            | push next coefficient
        PEA.L   (A0)                            | push accumulator
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | accum += coeff
        SUBQ.W  #0x1,D0                         | more terms?
        BGT.B   ELEMS_OK_4                      | yes ->
        ADDQ.L  #0x8,A1                         | skip past last coefficient
        ADDQ.L  #0x2,A1                         | (complete 10-byte advance)
        RTS                                     | return with A1 past last coeff

| ----------------------------------------------------------
|
| FP exception flag test helpers
| ELEMS_EXIT_2-ELEMS_EXIT_3: test specific SANE exception flags (invalid, overflow, etc.)
|
| Called by: ELEMS_NO_5, ELEMS_OK_11, ELEMS_NO_9, ELEMS_OK_15, ELEMS_CONT_59 (and 2 more)
ELEMS_EXIT_2:
        MOVEQ.L #0x1,D0                         | test flag bit 1 (overflow)
        BRA.B   ELEMS_CONT_10                   | -> test and clear flag
| ELEMS_CONT_8 -- set underflow exception.
ELEMS_CONT_8:
        MOVEQ.L #0x2,D0                         | test flag bit 2 (underflow)
        BRA.B   ELEMS_CONT_10                   | -> test and clear flag
| ELEMS_CONT_9 -- test invalid flag.
ELEMS_CONT_9:
        MOVEQ.L #0x0,D0                         | test flag bit 0 (invalid)
        BRA.B   ELEMS_CONT_10                   | -> test and clear flag
| ELEMS_EXIT_3 -- test inexact flag.
ELEMS_EXIT_3:
        MOVEQ.L #0x4,D0                         | test flag bit 4 (inexact)
| common: get SANE environment, clear specified flag, restore
ELEMS_CONT_10:
        SUBQ.L  #0x2,SP                         | space for environment word
        PEA.L   (SP)                            | push ptr to environment word
        MOVE    #0x3,-(SP)                      | FP opcode: getEnv
        _FP68K                                  | get current SANE environment
        BCLR    D0,(SP)                         | clear the specified flag
        PEA.L   (SP)                            | push ptr to modified environment
        MOVE    #0x1,-(SP)                      | FP opcode: setEnv
        _FP68K                                  | restore with flag cleared
ELEMS_EXIT_4:
        ADDQ.L  #0x2,SP                         | pop environment word
        TST.B   D0                              | set Z flag from result
        RTS                                     | Z=1 if flag was clear

| ----------------------------------------------------------
|
| ELEMS_CONT_11: set underflow exception flag (bit 2)
|
ELEMS_CONT_11:
        MOVEQ.L #0x2,D0                         | underflow flag bit
        BRA.B   ELEMS_CONT_16                   | -> set exception common

| ----------------------------------------------------------
|
| ELEMS_CONT_12: set overflow exception flag (bit 1)
|
| Called by: ELEMS_NO_4, ELEMS_NO_6, ELEMS_OK_10, ELEMS_NO_12, ELEMS_CONT_69
ELEMS_CONT_12:
        MOVEQ.L #0x1,D0                         | overflow flag bit
        BRA.B   ELEMS_CONT_16                   | -> set exception common

| ----------------------------------------------------------
|
| ELEMS_CONT_13
|
| ELEMS_CONT_12-ELEMS_CONT_15: set SANE exception flags
| ELEMS_CONT_12: set overflow flag (bit 1)
| ELEMS_CONT_13: set inexact flag (bit 3)
ELEMS_CONT_13:
        MOVEQ.L #0x3,D0                         | inexact flag
        BRA.B   ELEMS_CONT_16                   | -> set exception common
| ELEMS_CONT_14: set invalid flag (bit 0)
ELEMS_CONT_14:
        MOVEQ.L #0x0,D0                         | invalid flag
        BRA.B   ELEMS_CONT_16                   | -> set exception common
| ELEMS_CONT_15: set divide-by-zero flag (bit 4)
ELEMS_CONT_15:
        MOVEQ.L #0x4,D0                         | divByZero flag
| common: set flag in SANE environment
ELEMS_CONT_16:
        MOVE    D0,-(SP)                        | push flag bit number
        PEA.L   (SP)                            | push ptr to flag word
        MOVE    #0x15,-(SP)                     | FP opcode: setException
        _FP68K                                  | set the exception flag
        BRA.B   ELEMS_EXIT_4                    | -> pop and return

| ----------------------------------------------------------
|
| ELEMS_EMPTY_2-ELEMS_OK_5: SANE rounding mode helpers
| ELEMS_EMPTY_2: set round-toward-zero (chop) mode
ELEMS_EMPTY_2:
        MOVEQ.L #0x3,D0                         | rounding mode 3 = toward zero
        BRA.B   ELEMS_CONT_20                   | -> set rounding mode common
| ELEMS_CONT_17: set round-down (floor) mode
ELEMS_CONT_17:
        MOVEQ.L #0x1,D0                         | rounding mode 1 = toward -inf
        BRA.B   ELEMS_CONT_20                   | -> set rounding mode common

| ----------------------------------------------------------
|
| ELEMS_CONT_18: set round-up (ceiling) mode
|
ELEMS_CONT_18:
        MOVEQ.L #0x2,D0                         | rounding mode 2 = toward +inf
        BRA.B   ELEMS_CONT_20                   | -> set rounding mode common

| ----------------------------------------------------------
|
| ELEMS_CONT_19
|
| ELEMS_CONT_18: set round-up (ceiling) mode
| ELEMS_CONT_19: set round-to-nearest (default) mode
ELEMS_CONT_19:
        MOVEQ.L #0x0,D0                         | rounding mode 0 = nearest
        BRA.B   ELEMS_CONT_20                   | -> set rounding mode common
| ELEMS_OK_5: set round-toward-positive-infinity mode
ELEMS_OK_5:
        MOVEQ.L #0x4,D0                         | rounding mode 4
| common: get/set SANE rounding mode via procEntry
ELEMS_CONT_20:
        MOVE    D0,-(SP)                        | push rounding mode
        PEA.L   (SP)                            | push ptr to rounding mode word
        MOVE    #0x1B,-(SP)                     | FP opcode: procEntry (save/set round mode)
        _FP68K                                  | save old env, set new rounding
        MOVE.B  (SP),D0                         | D0 = previous rounding mode
        BRA.B   ELEMS_EXIT_4                    | -> pop and return

| ----------------------------------------------------------
|
| ELEMS_CONT_21: classify extended value and extract magnitude
| A1 = extended value -> sets up A3 = magnitude copy, D6 = class flags
|
ELEMS_CONT_21:
        MOVE    #0x7FFF,-0x6(A6)                | max exponent (for comparison)
        LEA.L   -0x1A(A6),A3                    | A3 = local copy destination
        MOVE.L  0x6(A1),-(A3)                   | copy mantissa low
        MOVE.L  0x2(A1),-(A3)                   | copy mantissa high
        MOVE    (A1),-(A3)                      | copy exponent+sign
        BCLR    #0x7,(A3)                       | clear sign bit (work with magnitude)
        BSR.B   ELEMS_RETRY                     | compare |x| with threshold constant
        BGE.B   ELEMS_NO_2                      | |x| >= threshold, no prescale needed ->
        PEA.L   ELEMS_CONT_97(PC)               | push scale factor constant
        PEA.L   (A3)                            | push magnitude copy
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | subtract scale factor from exponent
        TST.B   (A1)                            | original value negative?
        BPL.B   ELEMS_NO                        | no ->
        NEG     -0x6(A6)                        | negate scale exponent for negative input
ELEMS_NO:
        BSR.B   ELEMS_NO_3                      | apply 2^n scale to result
ELEMS_NO_2:
        BSR.B   ELEMS_RETRY                     | compare |x| with threshold again
        BGE.B   ELEMS_CONT_22                   | still above threshold ->
        PEA.L   ELEMS_CONT_97(PC)               | push threshold constant
        BRA.B   ELEMS_CONT_23                   | -> apply final logb scaling

| ----------------------------------------------------------
|
| ELEMS_CONT_22
|
ELEMS_CONT_22:
        PEA.L   (A3)                            | push magnitude copy
ELEMS_CONT_23:
        PEA.L   -0x6(A6)                        | push scale exponent dest
        MOVE    #0x2010,-(SP)                   | FP opcode: logb (extract exponent)
        _FP68K                                  | get binary exponent of value
        TST.B   (A1)                            | original value negative?
        BPL.B   ELEMS_NO_3                      | no -> scale result
        NEG     -0x6(A6)                        | negate exponent for negative input
| ELEMS_NO_3: scale result by power of 2 (multiply by 2^n)
ELEMS_NO_3:
        PEA.L   -0x6(A6)                        | push exponent
        PEA.L   (A0)                            | push result
        MOVE    #0x2018,-(SP)                   | FP opcode: scalb (x * 2^n)
        _FP68K                                  | scale the result
        RTS                                     | return scaled result

| ----------------------------------------------------------
|
| ELEMS_RETRY: load constant from coefficient table ELEMS_CONT_97
| Copies an extended constant into the temp area at -$24(A6)
|
ELEMS_RETRY:
        PEA.L   -0x24(A6)                       | push dest (temp)
        PEA.L   ELEMS_CONT_97(PC)               | push source constant
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare with constant
        RTS                                     | return CC from comparison

| ----------------------------------------------------------
|
| ELEMS_CONT_24: ln(x) / log2(x) / ln(1+x) entry point
| D1 = sub-function (0=ln, 1=log2, 2=ln(1+x))
|
ELEMS_CONT_24:
        SUBQ.B  #0x1,D1                         | adjust selector
        BPL.B   ELEMS_CONT_25                   | log2 or ln(1+x) ->
        TST     D1                              | NaN or special?
        BPL     ELEMS_EXIT_9                    | yes ->
ELEMS_ERR:
        MOVEQ.L #0x24,D0                        | invalid operation NaN code
        BRA     ELEMS_EXIT_11                   | -> signal invalid and return NaN

| ----------------------------------------------------------
|
| ELEMS_CONT_25
|
ELEMS_CONT_25:
        BTst    #0x2,D3                         | ln(1+x) variant?
        BNE.B   ELEMS_OK_6                      | yes ->
        TST.B   D1                              | operand is zero?
        BEQ.B   ELEMS_OK_7                      | yes, log(0) = -inf ->
        TST     D1                              | operand is negative?
        BMI.B   ELEMS_ERR                       | yes, log(negative) = NaN ->
        BRA.B   ELEMS_CONT_27                   | normal positive, compute log ->

| ----------------------------------------------------------
|
| ELEMS_OK_6
|
ELEMS_OK_6:
        TST.B   D1                              | ln(1+x): is x zero?
        BEQ     ELEMS_EXIT_12                   | yes, ln(1+0)=0, return x as-is ->
        PEA.L   (A4)                            | push operand x
        PEA.L   ELEMS_CONT_93(PC)               | push constant -1.0
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare x with -1.0
        BHI.B   ELEMS_ERR                       | x < -1: domain error, return NaN ->
        BCS.B   ELEMS_CONT_26                   | x > -1: valid, compute ln(1+x) ->
ELEMS_OK_7:
        BRA     ELEMS_CONT_32                   | x == -1: ln(0) = -inf ->

| ----------------------------------------------------------
|
| ELEMS_CONT_26
|
ELEMS_CONT_26:
        MOVE.L  A4,A0                           | A0 = source (x)
        LEA.L   -0x10(A6),A1                    | A1 = temp copy dest
        BSR     ELEMS_EXIT                      | save copy of x in temp
        PEA.L   ELEMS_CONT_92(PC)               | push constant 1.0
        PEA.L   (A4)                            | push x
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | x = 1 + x
        PEA.L   ELEMS_CONT_109(PC)              | push lower range bound
        PEA.L   (A4)                            | push (1+x)
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare (1+x) with lower bound
        BLE.B   ELEMS_CONT_27                   | (1+x) <= bound: use general path ->
        PEA.L   (A4)                            | push (1+x)
        PEA.L   ELEMS_CONT_108(PC)              | push upper range bound
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare (1+x) with upper bound
        BLS.B   ELEMS_CONT_27                   | (1+x) > upper: use general path ->
        MOVE.L  A1,A0                           | A0 = saved x copy
        MOVE.L  A4,A1                           | A1 = result dest
        BSR     ELEMS_EXIT                      | restore original x to result
        BSR     ELEMS_CONT_29                   | compute ln(1+x) via rational approx
        BRA     ELEMS_CONT_28                   | -> apply log2 conversion if needed

| ----------------------------------------------------------
|
| ELEMS_CONT_27
|
ELEMS_CONT_27:
        MOVE.L  A4,A0                           | A0 = operand
        LEA.L   -0x10(A6),A1                    | A1 = temp storage
        BSR     ELEMS_EXIT                      | copy operand to temp
        PEA.L   (A1)                            | push temp copy
        MOVE    #0x1A,-(SP)                     | FP opcode: negate
        _FP68K                                  | negate temp copy
        BCHG    #0x7,(A1)                       | toggle sign bit of temp
        MOVE.L  A4,A0                           | A0 = operand for ELEMS_CONT_21
        BSR     ELEMS_CONT_21                   | extract exponent, range-reduce
        BCHG    #0x7,(A1)                       | restore sign bit
        PEA.L   ELEMS_CONT_108(PC)              | push sqrt(2) threshold
        PEA.L   (A4)                            | push reduced operand
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare with sqrt(2)
        BLE     ELEMS_SKIP_2                    | within range -> skip adjustment
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   -0x10(A6)                       | push exponent accumulator
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | increment exponent by 1
        PEA.L   ELEMS_CONT_96(PC)               | push 0.5
        PEA.L   (A4)                            | push reduced operand
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | halve the reduced operand
ELEMS_SKIP_2:
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A4)                            | push reduced operand
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | f = x - 1.0 (reduced argument)
        BSR     ELEMS_CONT_29                   | compute ln(1+f) via rational approx
        PEA.L   -0x10(A6)                       | push exponent * ln(2) term
        PEA.L   (A4)                            | push ln(fraction) result
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | result = ln(fraction) + n*ln(2)
ELEMS_CONT_28:
        BTst    #0x1,D3                         | log2 variant (vs ln)?
        BNE.B   ELEMS_OK_8                      | yes, already in log2 form ->
        PEA.L   ELEMS_CONT_110(PC)              | push 1/ln(2) = log2(e)
        PEA.L   (A4)                            | push ln result
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | convert ln to log2
ELEMS_OK_8:
        BRA     ELEMS_EXIT_12                   | -> return result

| ----------------------------------------------------------
|
| ELEMS_CONT_29: ln(x) core - rational approximation via ELEMS_CONT_88/ELEMS_CONT_89 coefficients
| Uses P/Q polynomial ratio in reduced argument after range reduction
|
ELEMS_CONT_29:
        PEA.L   (A4)                            | push operand ptr
        PEA.L   -0x6(A6)                        | push class result dest
        MOVE    #0x1C,-(SP)                     | FP opcode: classify
        _FP68K                                  | classify reduced argument
        MOVE    -0x6(A6),D0                     | D0 = class code
        BPL.B   ELEMS_CONT_30                   | positive class ->
        NEG     D0                              | take absolute class value
ELEMS_CONT_30:
        SUBQ.W  #0x4,D0                         | class 4 = zero?
        BNE.B   ELEMS_NO_4                      | no -> continue
        RTS                                     | ln(0) already handled, return

| ----------------------------------------------------------
|
| ELEMS_NO_4
|
ELEMS_NO_4:
        SUBQ.W  #0x1,D0                         | class 5 = denormalized?
        BEQ.B   ELEMS_NO_5                      | no, normal -> compute ln
        PEA.L   ELEMS_CONT_110(PC)              | push ln(2) for overflow scale
        BSR     ELEMS_CONT_12                   | set overflow exception
        BRA.B   ELEMS_CONT_31                   | -> divide result by ln(2)

| ----------------------------------------------------------
|
| ELEMS_NO_5
|
ELEMS_NO_5:
        MOVE.L  A4,A0                           | A0 = reduced arg f
        LEA.L   -0x1A(A6),A1                    | A1 = temp g
        BSR     ELEMS_EXIT                      | g = f (save copy)
        PEA.L   ELEMS_CONT_96(PC)               | push 2.0
        PEA.L   (A4)                            | push f
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | f = f + 2.0
        PEA.L   (A4)                            | push (f+2)
        PEA.L   (A1)                            | push g
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | g = g / (f+2) = s
        MOVE.L  A1,A0                           | A0 = s (reduced ratio)
        PEA.L   (A1)                            | push s (already on stack)
        PEA.L   (A1)                            | push s again
        LEA.L   -0x24(A6),A1                    | A1 = temp for s^2
        BSR     ELEMS_EXIT                      | save s to temp
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | s^2 = s * s
        MOVE.L  A4,A0                           | A0 = accum for P(s^2)
        LEA.L   ELEMS_CONT_88(PC),A1            | A1 = ln numerator coefficients
        LEA.L   -0x1A(A6),A2                    | A2 = s^2 value
        BSR     ELEMS_CONT_7                    | P(s^2) via Horner's method
        PEA.L   -0x24(A6)                       | push s^2
        PEA.L   (A4)                            | push P(s^2)
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | P(s^2) * s^2
        LEA.L   -0x24(A6),A0                    | A0 = accum for Q(s^2)
        LEA.L   ELEMS_CONT_89(PC),A1            | A1 = ln denominator coefficients
        LEA.L   -0x1A(A6),A2                    | A2 = s^2 value
        BSR     ELEMS_CONT_7                    | Q(s^2) via Horner's method
        BSR     ELEMS_EXIT_2                    | test overflow flag
        PEA.L   -0x24(A6)                       | push Q(s^2)
ELEMS_CONT_31:
        PEA.L   (A4)                            | push result
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = P(s^2) / Q(s^2)
        BSR     ELEMS_CONT_15                   | set divByZero exception flag
        RTS                                     | return ln approximation

| ----------------------------------------------------------
|
| ELEMS_EXIT_5: return -infinity constant
|
ELEMS_EXIT_5:
        LEA.L   ELEMS_CONT_94(PC),A0            | A0 = +0.0 constant
        BRA.B   ELEMS_CONT_33                   | -> copy constant to result

| ----------------------------------------------------------
|
| ELEMS_EXIT_6: return -0.0 constant
|
ELEMS_EXIT_6:
        LEA.L   ELEMS_CONT_95(PC),A0            | A0 = -0.0 constant
        BRA.B   ELEMS_CONT_33                   | -> copy constant to result

| ----------------------------------------------------------
|
| ELEMS_EXIT_7: return +1.0 constant
|
ELEMS_EXIT_7:
        LEA.L   ELEMS_CONT_92(PC),A0            | A0 = +1.0 constant
        BRA.B   ELEMS_CONT_33                   | -> copy constant to result

| ----------------------------------------------------------
|
| ELEMS_EXIT_8: return -1.0 constant
|
ELEMS_EXIT_8:
        LEA.L   ELEMS_CONT_93(PC),A0            | A0 = -1.0 constant
        BRA.B   ELEMS_CONT_33                   | -> copy constant to result

| ----------------------------------------------------------
|
| ELEMS_ERR_2: set invalid exception then return +NaN
|
ELEMS_ERR_2:
        BSR     ELEMS_CONT_13                   | set inexact exception
ELEMS_EXIT_9:
        LEA.L   ELEMS_CONT_98(PC),A0            | A0 = +NaN constant
        BRA.B   ELEMS_CONT_33                   | -> copy constant to result

| ----------------------------------------------------------
|
| ELEMS_CONT_32: set invalid exception then return -NaN
|
ELEMS_CONT_32:
        BSR     ELEMS_CONT_13                   | set inexact exception
ELEMS_EXIT_10:
        LEA.L   ELEMS_CONT_99(PC),A0            | A0 = -NaN constant
| Called by: ELEMS_EXIT_5, ELEMS_EXIT_6, ELEMS_EXIT_7, ELEMS_EXIT_8, ELEMS_EXIT_9
ELEMS_CONT_33:
        MOVE.L  A4,A1                           | A1 = result dest
        BSR     ELEMS_EXIT                      | copy constant to result
        BRA.B   ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_EXIT_11: construct NaN with payload D0 and set invalid exception
|
ELEMS_EXIT_11:
        ORI.L   #0x7FFF4000,D0                  | D0 = NaN with exp=7FFF, code in low bits
        MOVE.L  D0,(A4)+                        | store exponent+sign and NaN code
        CLR.L   (A4)+                           | clear mantissa low
        CLR     (A4)                            | clear mantissa tail
        SUBQ.L  #0x8,A4                         | restore A4 to start of result
        BSR     ELEMS_CONT_14                   | set invalid exception flag
| ELEMS_EXIT_12: PACK 5 common return - restore SANE state and unlock package
| Called by: ELEMS_CONT_33, ELEMS_CONT_34, ELEMS_OK_9, ELEMS_CONT_43, ELEMS_CONT_48 (and 4 more)
ELEMS_EXIT_12:
        PEA.L   -0x2(A6)                        | push saved environment
        MOVE    #0x19,-(SP)                     | FP opcode: procExit
        _FP68K                                  | restore SANE environment
        MOVE.L  (AppPacks_5).w,A0               | unlock PACK 5 handle
        MOVE.B  -0x30(A6),(A0)                  | restore lock state
        MOVEM.L (SP)+,D0-D7/A0-A4               | restore all regs
        UNLK    A6                              | deallocate local frame
        ADDA    (SP),SP                         | pop variable-size params
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| ELEMS_CONT_34: exp(x) / exp2(x) - exponential functions
| D1 = sub-function: 0=exp(x), 1=exp2(x)
|
ELEMS_CONT_34:
        SUBQ.B  #0x1,D1                         | check class: 1=zero
        BEQ.B   ELEMS_EXIT_7                    | zero -> return 1.0 (e^0=1)
        BGT.B   ELEMS_CONT_35                   | normal -> compute exp
        TST     D1                              | negative class = -inf?
        BMI.B   ELEMS_EXIT_5                    | -inf -> return +0.0
        BRA.B   ELEMS_EXIT_12                   | NaN -> return as-is

| ----------------------------------------------------------
|
| ELEMS_CONT_35
|
ELEMS_CONT_35:
        BTst    #0x1,D3                         | exp2 variant?
        BEQ.B   ELEMS_NO_6                      | no -> exp(x) path
        BSR.B   ELEMS_CONT_36                   | split x into int + frac for 2^x
        BRA.B   ELEMS_OK_9                      | -> compute 2^frac and scale

| ----------------------------------------------------------
|
| ELEMS_NO_6
|
ELEMS_NO_6:
        BSR     ELEMS_CONT_37                   | convert x -> 2^(x*log2e) parts
        BSR     ELEMS_CONT_18                   | set round-up mode, get old mode
        BEQ.B   ELEMS_OK_9                      | was already round-up -> ok
        BSR     ELEMS_CONT_15                   | set divByZero exception
        TST     D1                              | check sign of result
        BPL.B   ELEMS_EXIT_9                    | positive overflow -> +NaN
        BSR     ELEMS_CONT_8                    | set underflow exception
        BSR     ELEMS_CONT_12                   | set overflow exception
        BRA     ELEMS_EXIT_5                    | -> return +0.0 (underflow)

| ----------------------------------------------------------
|
| ELEMS_OK_9
|
ELEMS_OK_9:
        BSR     ELEMS_CONT_40                   | compute 2^frac - 1 via rational approx
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A4)                            | push (2^frac - 1)
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | result = 2^frac
        MOVE.L  A4,A0                           | A0 = result
        LEA.L   -0x10(A6),A1                    | A1 = integer exponent
        BSR     ELEMS_CONT_21                   | scale by 2^n (result * 2^int)
        BRA.B   ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_CONT_36: exp2(x) core - compute 2^x using integer part + fraction
| Truncates x to integer, subtracts to get fractional part
|
ELEMS_CONT_36:
        MOVE.L  A4,A0                           | A0 = x
        LEA.L   -0x10(A6),A1                    | A1 = temp for int part
        BSR     ELEMS_EXIT                      | copy x to temp
        PEA.L   (A1)                            | push temp
        MOVE    #0x14,-(SP)                     | FP opcode: truncate to integer
        _FP68K                                  | temp = trunc(x)
        BSR     ELEMS_EXIT_3                    | test inexact flag
        PEA.L   (A1)                            | push int part
        PEA.L   (A4)                            | push x
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | x = x - trunc(x) = frac part
        RTS                                     | return: A4=frac, -0x10=int

| ----------------------------------------------------------
|
| ELEMS_CONT_37: exp(x) core - compute e^x by converting to 2^(x/ln2)
| Multiplies x by log2(e), then calls exp2 pipeline
|
ELEMS_CONT_37:
        MOVE.L  A4,A0                           | A0 = x
        LEA.L   -0x10(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | temp = x
        PEA.L   ELEMS_CONT_110(PC)              | push ln(2)
        MOVE.L  (SP),-(SP)                      | dup ln(2) ptr on stack
        MOVE.L  (SP),-(SP)                      | dup again (need 3 copies)
        PEA.L   (A4)                            | push x
        MOVE    #0xC,-(SP)                      | FP opcode: remainder
        _FP68K                                  | x = x rem ln(2) (fractional part)
        PEA.L   (A4)                            | push remainder
        PEA.L   (A1)                            | push temp (original x)
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | temp = x - remainder
        PEA.L   (A1)                            | push (x - remainder)
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | temp = (x-rem)/ln(2) = integer part
        PEA.L   (A1)                            | push integer part
        MOVE    #0x14,-(SP)                     | FP opcode: truncate to integer
        _FP68K                                  | round to exact integer
        PEA.L   (A4)                            | push fractional remainder
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | frac = remainder / ln(2)
        BRA     ELEMS_EXIT_3                    | -> test inexact flag and return

| ----------------------------------------------------------
|
| ELEMS_CONT_38: exp(x)-1 / exp2(x)-1 - "minus one" exponential variants
| Returns exp(x)-1 with better precision for small x
|
ELEMS_CONT_38:
        SUBQ.B  #0x1,D1                         | check class: 1=zero
        BGT.B   ELEMS_CONT_39                   | normal -> compute exp-1
        BEQ     ELEMS_EXIT_13                   | zero -> return 0 (e^0-1=0)
        TST     D1                              | -inf?
        BMI     ELEMS_EXIT_8                    | -inf -> return -1.0 (e^-inf-1)
ELEMS_EXIT_13:
        BRA     ELEMS_EXIT_12                   | NaN/zero -> return as-is

| ----------------------------------------------------------
|
| ELEMS_CONT_39
|
ELEMS_CONT_39:
        SUBQ.B  #0x1,D1                         | adjust class for +inf check
        BTST    #0x1,D3                         | exp2 variant?
        BEQ.B   ELEMS_NO_8                      | no -> exp(x)-1 path
        TST.B   D1                              | is +inf?
        BEQ.B   ELEMS_NO_7                      | no -> normal exp2-1 computation
        PEA.L   ELEMS_CONT_110(PC)              | push ln(2)
        PEA.L   (A4)                            | push x
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | x = x * ln(2) (convert to natural)
ELEMS_OK_10:
        BSR     ELEMS_CONT_12                   | set overflow exception
        BSR     ELEMS_CONT_15                   | set divByZero exception
        BRA.B   ELEMS_EXIT_14                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_NO_7
|
ELEMS_NO_7:
        BSR     ELEMS_CONT_36                   | split x into int + frac for 2^x
        BRA.B   ELEMS_OK_11                     | -> compute 2^frac - 1

| ----------------------------------------------------------
|
| ELEMS_NO_8
|
ELEMS_NO_8:
        TST.B   D1                              | is +inf?
        BNE.B   ELEMS_OK_10                     | yes -> overflow
  .short 0x6180                                 | Bsr.B ELEMS_CONT_37
        BSR     ELEMS_CONT_18                   | set round-up mode
        BEQ.B   ELEMS_OK_11                     | was round-up -> ok
        BSR     ELEMS_CONT_15                   | set divByZero exception
        TST     D1                              | check direction
        BPL     ELEMS_EXIT_9                    | positive overflow -> +NaN
        BSR     ELEMS_CONT_8                    | set underflow exception
        BRA     ELEMS_EXIT_8                    | -> return -1.0

| ----------------------------------------------------------
|
| ELEMS_OK_11
|
ELEMS_OK_11:
        BSR     ELEMS_CONT_40                   | compute 2^frac - 1
        PEA.L   ELEMS_CONT_94(PC)               | push 0.0
        PEA.L   -0x10(A6)                       | push integer part
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | is integer part zero?
        BEQ.B   ELEMS_EXIT_14                   | yes -> result is just 2^frac-1
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A4)                            | push (2^frac - 1)
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | result = 2^frac
        MOVE.L  A4,A0                           | A0 = 2^frac
        LEA.L   -0x10(A6),A1                    | A1 = integer exponent
        BSR     ELEMS_CONT_21                   | scale: result = 2^frac * 2^int
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A4)                            | push scaled result
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | result = 2^x - 1
        BSR     ELEMS_EXIT_2                    | test overflow flag
ELEMS_EXIT_14:
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_CONT_40: 2^f - 1 for fractional part - rational approximation
| Uses polynomial/rational P/Q minimax via ELEMS_CONT_90/ELEMS_CONT_91 coefficients
|
ELEMS_CONT_40:
        PEA.L   ELEMS_CONT_94(PC)               | push 0.0
        PEA.L   (A4)                            | push fractional part f
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | is f == 0?
        BNE.B   ELEMS_NO_9                      | no -> compute 2^f - 1
        RTS                                     | f=0: 2^0-1=0, return

| ----------------------------------------------------------
|
| ELEMS_NO_9
|
ELEMS_NO_9:
        LEA.L   -0x24(A6),A1                    | A1 = temp for f^2
        MOVE.L  A4,A0                           | A0 = f
        BSR     ELEMS_EXIT                      | copy f to temp
        PEA.L   (A1)                            | push f
        PEA.L   (A1)                            | push f
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | f^2 = f * f
        LEA.L   -0x1A(A6),A0                    | A0 = accum for P(f^2)
        LEA.L   ELEMS_CONT_90(PC),A1            | A1 = 2^f numerator coefficients
        LEA.L   -0x24(A6),A2                    | A2 = f^2
        BSR     ELEMS_CONT_7                    | P(f^2) via Horner's method
        PEA.L   -0x1A(A6)                       | push P(f^2)
        PEA.L   (A4)                            | push f
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | result = f * P(f^2)
        LEA.L   -0x1A(A6),A0                    | A0 = accum for Q(f^2)
        LEA.L   ELEMS_CONT_91(PC),A1            | A1 = 2^f denominator coefficients
        LEA.L   -0x24(A6),A2                    | A2 = f^2
        BSR     ELEMS_CONT_7                    | Q(f^2) via Horner's method
        PEA.L   (A4)                            | push f*P(f^2)
        PEA.L   -0x1A(A6)                       | push Q(f^2)
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | Q(f^2) - f*P(f^2)
        PEA.L   ELEMS_CONT_96(PC)               | push 2.0
        PEA.L   (A4)                            | push f*P(f^2)
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | 2*f*P(f^2)
        PEA.L   -0x1A(A6)                       | push (Q - f*P)
        PEA.L   (A4)                            | push 2*f*P
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = 2*f*P / (Q - f*P)
        BSR     ELEMS_CONT_15                   | set divByZero exception
        BRA     ELEMS_EXIT_2                    | -> test overflow and return

| ----------------------------------------------------------
|
| ELEMS_CONT_41: x^y (power) - computes x raised to integer or real power
| D4 = exponent ptr, A4 = base ptr
|
ELEMS_CONT_41:
        MOVE.L  D4,A0                           | A0 = exponent y ptr
        MOVE    (A0),D2                         | D2 = y exponent+sign word
        BEQ     ELEMS_EXIT_7                    | y=0 -> return 1.0 (x^0=1)
        SUBQ.B  #0x1,D1                         | check base class: 1=zero
        BGT.B   ELEMS_CONT_42                   | normal base -> compute power
        ASR     #0x1,D2                         | test y sign bit
        BCS.B   ELEMS_OK_12                     | y is negative -> keep base sign
        BCLR    #0x7,(A4)                       | y positive: force base positive
ELEMS_OK_12:
        ADDX    D2,D2                           | restore D2, test inf bit
        BPL     ELEMS_EXIT_12                   | base not inf -> return as-is
        TST.B   D1                              | base is zero? (class 0)
        BPL.B   ELEMS_EMPTY_3                   | zero base -> handle 0^y
        TST.B   (A4)                            | base is inf, check sign
        BPL     ELEMS_EXIT_5                    | +inf^neg -> +0.0
        BRA     ELEMS_EXIT_6                    | -inf^neg -> -0.0

| ----------------------------------------------------------
|
| ELEMS_EMPTY_3
|
ELEMS_EMPTY_3:
        TST.B   (A4)                            | check base sign
        BPL     ELEMS_ERR_2                     | 0^y with y<0, +base -> +NaN
        BRA     ELEMS_CONT_32                   | 0^y with y<0, -base -> -NaN

| ----------------------------------------------------------
|
| ELEMS_CONT_42
|
ELEMS_CONT_42:
        MOVE    D2,D0                           | D0 = y exponent word
        BPL.B   ELEMS_CONT_43                   | positive ->
        NEG     D0                              | D0 = |y exponent|
ELEMS_CONT_43:
        CMPI    #0xFF,D0                        | |y| small integer (<=255)?
        BHI.B   ELEMS_NO_10                     | no -> use general x^y path
        BSR.B   ELEMS_OK_13                     | compute x^n by binary squaring
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_NO_10
|
ELEMS_NO_10:
        MOVE    (A4),-(SP)                      | save base sign+exponent
        BCLR    #0x7,(A4)                       | force base positive for ln
        MOVE.L  D4,-(SP)                        | save exponent ptr
        PEA.L   -0x10(A6)                       | push temp dest for y copy
        MOVE.L  (SP),D4                         | D4 = temp ptr
        MOVE    #0x200E,-(SP)                   | FP opcode: x2x (extended copy)
        _FP68K                                  | copy y to temp
        BSR     ELEMS_CONT_47                   | compute |x|^y via exp(y*ln|x|)
        MOVE    (SP)+,D0                        | restore original base sign
        BPL.B   ELEMS_DONE_2                    | base was positive -> done
        ASR     #0x1,D2                         | check if y is odd integer
        BCC.B   ELEMS_DONE_2                    | even -> result stays positive
        BSET    #0x7,(A4)                       | odd -> negate result
ELEMS_DONE_2:
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_OK_13: integer power - compute x^n by repeated squaring
| D2 = exponent, A4 = base; uses binary exponentiation
|
ELEMS_OK_13:
        MOVE.L  A4,A0                           | A0 = base x
        LEA.L   -0x1A(A6),A1                    | A1 = temp for x copy
        BSR     ELEMS_EXIT                      | save copy of x
        BSR.B   ELEMS_CONT_46                   | compute x^|n| by squaring
        TST     D2                              | exponent negative?
        BMI.B   ELEMS_OK_14                     | yes -> need 1/result
ELEMS_CONT_44:
        MOVE.L  A1,A0                           | A0 = computed result
        MOVE.L  A4,A1                           | A1 = output dest
        BRA     ELEMS_EXIT                      | copy result to output

| ----------------------------------------------------------
|
| ELEMS_OK_14
|
ELEMS_OK_14:
        LEA.L   ELEMS_CONT_92(PC),A0            | A0 = 1.0
        LEA.L   (A4),A1                         | A1 = result dest
        BSR     ELEMS_EXIT                      | result = 1.0
        BSR     ELEMS_CONT_17                   | set round-down mode
        BNE.B   ELEMS_OK_15                     | was not round-down -> inexact path
        BSR     ELEMS_CONT_18                   | try round-up mode
        BNE.B   ELEMS_OK_15                     | was not round-up -> inexact path
        PEA.L   -0x10(A6)                       | push x^|n| accumulator
        PEA.L   (A4)                            | push result (1.0)
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = 1.0 / x^|n|
        RTS                                     | return x^(-n)

| ----------------------------------------------------------
|
| ELEMS_OK_15
|
ELEMS_OK_15:
        BSR     ELEMS_CONT_8                    | set underflow exception
        BSR     ELEMS_EXIT_2                    | test overflow flag
        PEA.L   -0x1A(A6)                       | push saved base x
        PEA.L   (A4)                            | push result
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = result / x
        MOVE    D2,D0                           | D0 = original exponent
        BPL.B   ELEMS_CONT_45                   | positive ->
        NEG     D0                              | D0 = |exponent|
ELEMS_CONT_45:
        BSR.B   ELEMS_CONT_46                   | recompute x^(|n|-1) by squaring
        BRA.B   ELEMS_CONT_44                   | -> copy result to output

| ----------------------------------------------------------
|
| ELEMS_CONT_46: binary exponentiation loop - square and multiply
| Scans D0 bits right-to-left, squaring base each iteration
|
ELEMS_CONT_46:
        LEA.L   ELEMS_CONT_92(PC),A0            | A0 = 1.0
        LEA.L   -0x10(A6),A1                    | A1 = accumulator
        BSR     ELEMS_EXIT                      | accum = 1.0
        BRA.B   ELEMS_LOOP                      | -> enter squaring loop

| ----------------------------------------------------------
|
| ELEMS_OK_16
|
ELEMS_OK_16:
        PEA.L   (A4)                            | push base
        PEA.L   (A4)                            | push base
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | base = base^2 (square)
ELEMS_LOOP:
        LSR     #0x1,D0                         | shift out next exponent bit
        BCC.B   ELEMS_SKIP_3                    | bit=0 -> skip multiply
        PEA.L   (A4)                            | push current base power
        PEA.L   (A1)                            | push accumulator
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | accum *= base^(2^k)
ELEMS_SKIP_3:
        TST     D0                              | more exponent bits?
        BNE.B   ELEMS_OK_16                     | yes -> continue squaring
        RTS                                     | done: accum = x^|n|

| ----------------------------------------------------------
|
| ELEMS_CONT_47: real power via exp(y*ln(x)) - general x^y computation
| Converts to ln, multiplies by exponent, then exponentiates
|
ELEMS_CONT_47:
        MOVE.L  A4,A0                           | A0 = base x
        LEA.L   -0x1A(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | temp = x
        PEA.L   (A1)                            | push temp (x)
        MOVE    #0x2,-(SP)                      | selector: log2(x)
        BSR     IMPLEMENTS                      | temp = log2(x) via PACK 5
        MOVE.L  D4,-(SP)                        | push exponent y
        PEA.L   (A1)                            | push log2(x)
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = y * log2(x)
        PEA.L   (A1)                            | push y*log2(x)
        MOVE    #0xA,-(SP)                      | selector: exp2(x)
        BSR     IMPLEMENTS                      | temp = 2^(y*log2(x)) = x^y
        MOVE.L  A1,A0                           | A0 = result source
        MOVE.L  A4,A1                           | A1 = result dest
        BRA     ELEMS_EXIT                      | copy result and return

| ----------------------------------------------------------
|
| ELEMS_CONT_48: x^i (compound) - x raised to integer i, with sign handling
| Handles negative base by computing |x|^i and restoring sign
|
ELEMS_CONT_48:
        TST     D1                              | check base class
        BMI.B   ELEMS_CONT_49                   | negative base -> special handling
        BSR     ELEMS_CONT_51                   | dispatch power by class
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_OK_17: power - exponent is 0 (x^0 = 1 for any finite x)
|
ELEMS_OK_17:
        ADDQ.L  #0x4,SP                         | discard return address
ELEMS_OK_18:
        BSR     ELEMS_EXIT_3                    | test inexact flag
        MOVEQ.L #0x25,D0                        | NaN code 37: invalid power
        BRA     ELEMS_EXIT_11                   | -> construct NaN and return

| ----------------------------------------------------------
|
| ELEMS_CONT_49: power with negative base - handle via |x|^y with sign
|
ELEMS_CONT_49:
        TST.B   D2                              | exponent zero?
        BEQ.B   ELEMS_OK_18                     | yes -> invalid (0^0)
        MOVE.L  D4,A0                           | A0 = exponent y ptr
        LEA.L   -0x10(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | temp = y
        PEA.L   (A1)                            | push y
        MOVE    #0x14,-(SP)                     | FP opcode: truncate to integer
        _FP68K                                  | temp = trunc(y)
        BSR     ELEMS_OK_5                      | test if y was not integer
        BNE.B   ELEMS_OK_18                     | non-integer -> invalid for neg base
        PEA.L   ELEMS_CONT_96(PC)               | push 2.0
        PEA.L   (A1)                            | push trunc(y)
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | temp = trunc(y) / 2
        PEA.L   (A1)                            | push y/2
        MOVE    #0x14,-(SP)                     | FP opcode: truncate to integer
        _FP68K                                  | test if y/2 is integer (y even?)
        PEA.L   -0x6(A6)                        | push env dest
        MOVE    #0x3,-(SP)                      | FP opcode: getEnv
        _FP68K                                  | get environment (inexact = y odd)
        BSR     ELEMS_EXIT_3                    | test inexact flag
        BCLR    #0x7,(A4)                       | force base positive: |x|
        BSR     ELEMS_CONT_51                   | compute |x|^y
        BTST    #0x4,-0x6(A6)                   | was y odd? (inexact bit set)
        BEQ.B   ELEMS_CONT_50                   | even -> result stays positive
        BCHG    #0x7,(A4)                       | odd -> negate result
ELEMS_CONT_50:
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_CONT_51: power function dispatcher - handles special cases
| D1 = class of base, D2 = class of exponent
|
ELEMS_CONT_51:
        SUBQ.B  #0x1,D1                         | base class -= 1 (test zero)
        BNE.B   ELEMS_EMPTY_4                   | not zero -> check inf/normal
        SUBQ.B  #0x1,D2                         | exponent class -= 1 (test zero)
        BEQ.B   ELEMS_OK_17                     | 0^0 -> invalid (NaN)
        TST     D2                              | exponent negative class?
        BPL.B   ELEMS_CONT_52                   | positive exp -> 0^n = 0
        BSR     ELEMS_CONT_13                   | set inexact exception
        LEA.L   ELEMS_CONT_98(PC),A0            | A0 = +NaN (0^neg = invalid)
        BRA.B   ELEMS_CONT_53                   | -> copy to result

| ----------------------------------------------------------
|
| ELEMS_CONT_52: power - base is zero, return zero constant
|
ELEMS_CONT_52:
        LEA.L   ELEMS_CONT_94(PC),A0            | A0 = +0.0 (base=0, exp>0)
ELEMS_CONT_53:
        MOVE.L  A4,A1                           | A1 = result dest
        BRA     ELEMS_EXIT                      | copy constant to result

| ----------------------------------------------------------
|
| ELEMS_EMPTY_4: power general case - check small integer exponent fast path
|
ELEMS_EMPTY_4:
        BPL.B   ELEMS_OK_19                     | base is normal -> check exp
        SUBQ.B  #0x1,D2                         | base is inf, check exp=zero
        BNE.B   ELEMS_EMPTY_5                   | nonzero exp -> general path
        BRA     ELEMS_OK_17                     | inf^0 -> invalid (NaN)

| ----------------------------------------------------------
|
| ELEMS_OK_19: power - exponent is finite, check if x=1 (shortcut)
|
ELEMS_OK_19:
        SUBQ.B  #0x1,D2                         | check exp class: zero?
        BPL.B   ELEMS_EMPTY_5                   | not zero -> general path
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A4)                            | push base x
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | is x == 1.0?
        BEQ     ELEMS_OK_17                     | yes -> 1^y is invalid per SANE
ELEMS_EMPTY_5:
        MOVE    D2,D6                           | save exponent class in D6
        MOVE.L  D4,-(SP)                        | push exponent y
        PEA.L   -0x4(A6)                        | push dest for logb result
        MOVE    #0x2010,-(SP)                   | FP opcode: logb
        _FP68K                                  | get binary exponent of y
        BSR     ELEMS_CONT_19                   | set round-nearest, get old mode
        SNE.B   D7                              | D7 != 0 if rounding was not nearest
        BSR     ELEMS_CONT_9                    | test invalid flag
        BSR     ELEMS_OK_5                      | test special rounding mode
        SNE.B   D1                              | D1 != 0 if special
        OR.B    D1,D7                           | D7 = any rounding anomaly
        BNE.B   ELEMS_CONT_55                   | anomaly -> use general real path
        MOVE    -0x4(A6),D2                     | D2 = logb(y) = integer exponent
        MOVE    D2,D0                           | D0 = exponent
        BPL.B   ELEMS_CONT_54                   | positive ->
        NEG     D0                              | D0 = |exponent|
ELEMS_CONT_54:
        CMPI    #0xFF,D0                        | small integer exponent?
        BLE     ELEMS_OK_13                     | yes -> fast integer power path
ELEMS_CONT_55:
        BSR     ELEMS_EXIT_3                    | test inexact flag
        BSR     ELEMS_CONT_47                   | general: x^y via exp(y*ln(x))
        TST.B   D6                              | was exponent inf?
        BMI     ELEMS_EXIT_3                    | yes -> test inexact
        RTS                                     | return result

| ----------------------------------------------------------
|
| ELEMS_CONT_56: annuity(x,y) - (1-(1+x)^(-y))/x financial function
| D5 = rate ptr, D4 = periods ptr, A4 = result ptr
|
ELEMS_CONT_56:
        PEA.L   ELEMS_CONT_93(PC)               | push -1.0
        MOVE.L  D5,-(SP)                        | push rate r
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare rate with -1.0
        BLT     ELEMS_ERR_3                     | r < -1 -> domain error
        BGT     ELEMS_CONT_57                   | r > -1 -> normal computation
        SUBQ.B  #0x1,D2                         | r == -1: check period class
        BNE.B   ELEMS_EMPTY_6                   | period not zero -> check sign
ELEMS_EXIT_15:
        BRA     ELEMS_EXIT_7                    | annuity(-1,0) -> return 1.0

| ----------------------------------------------------------
|
| ELEMS_EMPTY_6: annuity - rate is positive, check base sign for domain error
|
ELEMS_EMPTY_6:
        MOVE.L  D4,A0                           | A0 = period n ptr
        TST.B   (A0)                            | check period sign
        BMI     ELEMS_ERR_2                     | n < 0 -> NaN (domain error)
ELEMS_EXIT_16:
        BRA     ELEMS_EXIT_5                    | n >= 0 -> return +0.0

| ----------------------------------------------------------
|
| ELEMS_CONT_57: annuity - rate > 0, dispatch by period class
|
ELEMS_CONT_57:
        SUBQ.B  #0x1,D2                         | check period class -= 1
        BEQ.B   ELEMS_EXIT_15                   | period=zero -> return 1.0
        BGT.B   ELEMS_CONT_58                   | period normal -> compute
        SUBQ.B  #0x1,D1                         | period is special, check rate
        BEQ.B   ELEMS_ERR_3                     | rate=zero, period=inf -> error
        EOR     D2,D1                           | test sign mismatch
        BMI.B   ELEMS_EXIT_16                   | mismatched signs -> return 0
        BRA     ELEMS_EXIT_9                    | -> return NaN

| ----------------------------------------------------------
|
| ELEMS_CONT_58: annuity normal case - compute (1-(1+r)^(-n))/r
|
ELEMS_CONT_58:
        LEA.L   -0x1A(A6),A1                    | A1 = temp for rate copy
        MOVE.L  D5,A0                           | A0 = rate r
        BSR     ELEMS_EXIT                      | temp = r
        MOVE    (A1),D0                         | D0 = rate exponent+sign
        BCLR    #0xF,D0                         | clear sign bit
        CMPI    #0x3F7F,D0                      | |rate| small? (exp < -128)
        BLT.B   ELEMS_OK_20                     | yes -> use ln(1+r) small-rate path
        PEA.L   (A1)                            | push rate r
        MOVE    #0x6,-(SP)                      | selector: ln(1+x)
        BSR     IMPLEMENTS                      | temp = ln(1+r)
        MOVE.L  D4,-(SP)                        | push period n
        PEA.L   (A1)                            | push ln(1+r)
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = n * ln(1+r)
        PEA.L   (A1)                            | push n*ln(1+r)
        MOVE    #0xA,-(SP)                      | selector: exp2(x)
        BRA.B   ELEMS_CONT_59                   | -> finish via exp

| ----------------------------------------------------------
|
| ELEMS_OK_20
|
ELEMS_OK_20:
        MOVE.L  D4,-(SP)                        | push period n
        PEA.L   (A1)                            | push rate r
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = n * r
        PEA.L   (A1)                            | push n*r
        MOVE    #0x8,-(SP)                      | selector: exp(x)-1
ELEMS_CONT_59:
        BSR     ELEMS_EXIT_2                    | test overflow flag
        BSR     IMPLEMENTS                      | compute exp variant via PACK 5
        MOVE.L  A1,A0                           | A0 = result source
        MOVE.L  A4,A1                           | A1 = output dest
        BSR     ELEMS_EXIT                      | copy result to output
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_ERR_3: annuity/compound - rate < -1, domain error -> NaN
|
ELEMS_ERR_3:
        MOVEQ.L #0x26,D0                        | NaN code 38: financial domain error
        BRA     ELEMS_EXIT_11                   | -> construct NaN and return

| ----------------------------------------------------------
|
| ELEMS_CONT_60: compound(x,y) - (1+x)^y financial compound function
| D5 = rate ptr, D4 = periods ptr, A4 = result ptr
|
ELEMS_CONT_60:
        PEA.L   ELEMS_CONT_93(PC)               | push -1.0
        MOVE.L  D5,-(SP)                        | push rate r
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare rate with -1.0
        BLT.B   ELEMS_ERR_3                     | r < -1 -> domain error
        BNE.B   ELEMS_CONT_61                   | r != -1 -> normal compound
        SUBQ.B  #0x1,D2                         | r == -1: check period class
        BEQ.B   ELEMS_EXIT_18                   | period=0 -> return +0.0
        TST     D2                              | check period sign
        BPL     ELEMS_ERR_2                     | period > 0 -> NaN
ELEMS_EXIT_17:
        BRA     ELEMS_EXIT_8                    | period < 0 -> return -1.0

| ----------------------------------------------------------
|
| ELEMS_CONT_61: compound - rate > 0, normal computation
|
ELEMS_CONT_61:
        SUBQ.B  #0x1,D2                         | check period class
        BNE.B   ELEMS_CONT_62                   | period nonzero -> compute
ELEMS_EXIT_18:
        BRA     ELEMS_EXIT_5                    | period=0 -> return +0.0

| ----------------------------------------------------------
|
| ELEMS_CONT_62: compound - both operands finite, compute (1+r)^n
|
ELEMS_CONT_62:
        SUBQ.B  #0x1,D1                         | check rate class
        BGT.B   ELEMS_OK_21                     | rate is normal -> compute
        BLT.B   ELEMS_EMPTY_7                   | rate is zero -> special
ELEMS_CONT_63:
        MOVE.L  A4,A1                           | A1 = result dest
        MOVE.L  D4,A0                           | A0 = period n
        BSR     ELEMS_EXIT                      | result = n (compound(0,n)=n)
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_EMPTY_7: compound - period is zero, result is 1.0
|
ELEMS_EMPTY_7:
        TST     D2                              | rate=0: check period sign
        BPL.B   ELEMS_EXIT_18                   | period>=0, rate=0 -> return 0
        PEA.L   ELEMS_CONT_93(PC)               | push -1.0
        MOVE.L  D4,-(SP)                        | push period n
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare n with -1.0
        BEQ.B   ELEMS_EXIT_17                   | n == -1 -> return -1.0
        BGT     ELEMS_EXIT_6                    | n > -1 -> return -0.0
        BRA     ELEMS_EXIT_10                   | n < -1 -> return -NaN

| ----------------------------------------------------------
|
| ELEMS_OK_21: compound - period is infinity, check for convergence
|
ELEMS_OK_21:
        TST.B   D2                              | period is inf: check rate sign
        BPL.B   ELEMS_CONT_64                   | rate normal -> compute compound
        EOR     D2,D1                           | compare sign classes
        BMI.B   ELEMS_CONT_63                   | opposite signs -> copy period
        MOVE.L  D5,A0                           | A0 = rate r
        LEA.L   -0x1A(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | temp = r
        PEA.L   (A1)                            | push temp (rate)
        MOVE.L  A4,A1                           | A1 = result dest
        LEA.L   ELEMS_CONT_92(PC),A0            | A0 = 1.0
        BSR     ELEMS_EXIT                      | result = 1.0
        PEA.L   (A1)                            | push result
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = 1.0 / rate
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_CONT_64: compound normal - compute (1+r)^n via exp(n*ln(1+r))
|
ELEMS_CONT_64:
        LEA.L   -0x1A(A6),A1                    | A1 = temp
        MOVE.L  D5,A0                           | A0 = rate r
        BSR     ELEMS_EXIT                      | temp = r
        MOVE    (A1),D0                         | D0 = rate exponent+sign
        BCLR    #0xF,D0                         | clear sign
        CMPI    #0x3F7F,D0                      | |rate| small? (exp < -128)
        BLT.B   ELEMS_OK_22                     | yes -> small-rate path
        PEA.L   (A1)                            | push rate r
        MOVE    #0x6,-(SP)                      | selector: ln(1+x)
        BSR     IMPLEMENTS                      | temp = ln(1+r)
        MOVE.L  D4,-(SP)                        | push period n
        PEA.L   (A1)                            | push ln(1+r)
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = n * ln(1+r)
        BCHG    #0x7,(A1)                       | negate: -n*ln(1+r)
        CMPI    #0x4007,(A1)                    | |result| > 128?
        BLT.B   ELEMS_NO_11                     | no -> use exp directly
        MOVE.L  D5,A0                           | A0 = rate
        CMPI    #0x407F,(A0)                    | rate very large?
        BGE.B   ELEMS_OK_24                     | yes -> high-precision path
ELEMS_NO_11:
        PEA.L   (A1)                            | push -n*ln(1+r)
        MOVE    #0xE,-(SP)                      | selector: exp(x)
        BRA.B   ELEMS_CONT_65                   | -> compute exp

| ----------------------------------------------------------
|
| ELEMS_OK_22
|
ELEMS_OK_22:
        MOVE.L  D4,-(SP)                        | push period n
        PEA.L   (A1)                            | push rate r
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = n * r (small rate approx)
        BCHG    #0x7,(A1)                       | negate: -n*r
        PEA.L   (A1)                            | push -n*r
        MOVE    #0xC,-(SP)                      | selector: exp(x)-1
ELEMS_CONT_65:
        BSR     IMPLEMENTS                      | compute exp variant via PACK 5
        BCHG    #0x7,(A1)                       | negate result back
        MOVE.L  D5,-(SP)                        | push rate r
        PEA.L   (A1)                            | push result
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = result / rate
ELEMS_EXIT_19:
        BSR     ELEMS_EXIT_2                    | test overflow flag
        BSR     ELEMS_CONT_8                    | test underflow flag
        MOVE.L  A1,A0                           | A0 = result
        BSR     ELEMS_EMPTY                     | classify result
        SUBQ.B  #0x3,D0                         | class 3 = underflow?
        BNE.B   ELEMS_NO_12                     | no ->
        BSR     ELEMS_CONT_11                   | set underflow exception
        BRA.B   ELEMS_OK_23                     | -> copy result

| ----------------------------------------------------------
|
| ELEMS_NO_12
|
ELEMS_NO_12:
        SUBQ.B  #0x2,D0                         | class 5 = normal?
        BEQ.B   ELEMS_OK_23                     | yes -> just copy
        BSR     ELEMS_CONT_12                   | set overflow exception
ELEMS_OK_23:
        LEA.L   -0x1A(A6),A0                    | A0 = result source
        MOVE.L  A4,A1                           | A1 = output dest
        BSR     ELEMS_EXIT                      | copy result to output
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_OK_24: compound - large n*ln(1+r), use high-precision path
|
ELEMS_OK_24:
        MOVE.L  D5,A0                           | A0 = rate r
        BSR     ELEMS_EXIT                      | temp = r
        PEA.L   (A1)                            | push rate
        MOVE    #0x2,-(SP)                      | selector: log2(x)
        BSR     IMPLEMENTS                      | temp = log2(1+r)
        LEA.L   -0x24(A6),A1                    | A1 = temp2
        MOVE.L  D4,A0                           | A0 = period n
        BSR     ELEMS_EXIT                      | temp2 = n
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A1)                            | push n
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | temp2 = n + 1
        PEA.L   (A1)                            | push (n+1)
        LEA.L   -0x1A(A6),A1                    | A1 = log2(1+r)
        PEA.L   (A1)                            | push log2(1+r)
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | result = (n+1)*log2(1+r)
        BCHG    #0x7,(A1)                       | negate result
        PEA.L   (A1)                            | push -result
        MOVE    #0xA,-(SP)                      | selector: exp2(x)
        BSR     IMPLEMENTS                      | compute 2^(-result)
        BCHG    #0x7,(A1)                       | negate back
        BRA.B   ELEMS_EXIT_19                   | -> classify and return

| ----------------------------------------------------------
|
| ELEMS_CONT_66: sin(x) - sine function
| Reduces argument modulo pi/2 via range reduction, then
| evaluates minimax polynomial approximation
|
ELEMS_CONT_66:
        MOVEQ.L #0x21,D0                        | NaN code 33: trig invalid
        MOVEQ.L #0x0,D2                         | quadrant offset = 0 (sin)
        SUBQ.B  #0x1,D1                         | check class: 1=zero
        BEQ     ELEMS_EXIT_12                   | zero -> sin(0)=0, return
ELEMS_CONT_67:
        BMI     ELEMS_EXIT_11                   | inf/NaN -> return NaN
        BSR.B   ELEMS_CONT_71                   | range reduce: x mod pi/2
        BTST    #0x0,D2                         | odd quadrant?
        BNE.B   ELEMS_OK_25                     | yes -> use cosine kernel
        BSR.B   ELEMS_CONT_72                   | even quadrant: sine kernel
        BRA.B   ELEMS_CONT_68                   | -> adjust sign by quadrant

| ----------------------------------------------------------
|
| ELEMS_OK_25
|
ELEMS_OK_25:
        BSR     ELEMS_CONT_75                   | odd quadrant: cosine kernel
ELEMS_CONT_68:
        ANDI    #0x3,D2                         | D2 = quadrant mod 4
        SUBQ.W  #0x2,D2                         | quadrant >= 2?
        BMI.B   ELEMS_EXIT_20                   | no -> sign is correct
        BCHG    #0x7,(A4)                       | quadrant 2,3 -> negate result
ELEMS_EXIT_20:
        BSR     ELEMS_EXIT_2                    | test overflow flag
        BSR     ELEMS_CONT_15                   | set divByZero exception
        PEA.L   (A4)                            | push result
        PEA.L   -0x4(A6)                        | push class dest
        MOVE    #0x1C,-(SP)                     | FP opcode: classify
        _FP68K                                  | classify result
        MOVE    -0x4(A6),D0                     | D0 = class code
        BPL.B   ELEMS_CONT_69                   | positive ->
        NEG     D0                              | absolute class
ELEMS_CONT_69:
        SUBQ.W  #0x6,D0                         | class 6 = denormalized?
        BNE.B   ELEMS_DONE_3                    | no -> done
        BSR     ELEMS_CONT_12                   | set overflow exception
ELEMS_DONE_3:
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_CONT_70: cos(x) - cosine function
| Same as sin but with quadrant offset (+1 in D2)
|
ELEMS_CONT_70:
        MOVEQ.L #0x21,D0                        | NaN code 33: trig invalid
        MOVEQ.L #0x1,D2                         | quadrant offset = 1 (cos)
        SUBQ.B  #0x1,D1                         | check class: 1=zero
        BNE.B   ELEMS_CONT_67                   | nonzero -> compute cos
        BRA     ELEMS_EXIT_7                    | cos(0) = 1.0

| ----------------------------------------------------------
|
| ELEMS_CONT_71: trig range reduction - divide by pi/2 via remainder
| ELEMS_CONT_105 = pi (two words: pi and pi/2 for extended precision)
| Computes quadrant in D2 from remainder operation
|
ELEMS_CONT_71:
        PEA.L   ELEMS_CONT_105(PC)              | push pi/2 constant
        PEA.L   (A4)                            | push x
        MOVE    #0xC,-(SP)                      | FP opcode: remainder
        _FP68K                                  | x = x rem (pi/2), D0 = quotient
        ADD     D0,D2                           | D2 += quotient (quadrant count)
        RTS                                     | return reduced x in A4

| ----------------------------------------------------------
|
| ELEMS_CONT_72: sine kernel - Chebyshev polynomial for sin(x) on [-pi/4, pi/4]
| Uses P/Q rational approximation via ELEMS_CONT_114 coefficients
|
ELEMS_CONT_72:
        LEA.L   ELEMS_CONT_114(PC),A2           | A2 = sin coefficients
        BSR.B   ELEMS_CONT_74                   | eval P(x^2)/Q(x^2) rational
        PEA.L   (A4)                            | push x
        PEA.L   (A2)                            | push P/Q result
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | P/Q * x
        PEA.L   (A2)                            | push P/Q * x
        PEA.L   (A0)                            | push x^2
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | x^2 * (P/Q * x)
        PEA.L   (A0)                            | push x^3 * P/Q
        PEA.L   (A4)                            | push x
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | sin(x) = x - x^3*P(x^2)/Q(x^2)
        RTS                                     | return sin approximation

| ----------------------------------------------------------
|
| ELEMS_CONT_73: trig polynomial setup - squares argument, evaluates P(x^2)
|
ELEMS_CONT_73:
        BSR.B   ELEMS_CONT_74                   | eval P(x^2)/Q(x^2) rational
        PEA.L   (A2)                            | push P/Q result
        PEA.L   (A0)                            | push x^2
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | x^2 * P(x^2)/Q(x^2)
        RTS                                     | return in A0

| ----------------------------------------------------------
|
| ELEMS_CONT_74: evaluate P(x^2)/Q(x^2) rational approximation
| Squares x, then evaluates numerator P and denominator Q
| using Horner's method via ELEMS_CONT_7, returns P(x^2)/Q(x^2)
|
ELEMS_CONT_74:
        MOVE.L  A4,A0                           | A0 = x
        LEA.L   -0x10(A6),A1                    | A1 = temp for x^2
        BSR     ELEMS_EXIT                      | temp = x
        PEA.L   (A1)                            | push x
        PEA.L   (A1)                            | push x
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = x^2
        EXG     A1,A2                           | A2 = x^2, A1 = coeff table ptr
        LEA.L   -0x24(A6),A0                    | A0 = accum for P(x^2)
        BSR     ELEMS_CONT_7                    | P(x^2) via Horner's method
        PEA.L   (A0)                            | push P(x^2) (for later divide)
        LEA.L   -0x1A(A6),A0                    | A0 = accum for Q(x^2)
        BSR     ELEMS_CONT_7                    | Q(x^2) via Horner's method
        PEA.L   (A0)                            | push Q(x^2) (for divide)
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = P(x^2) / Q(x^2)
        RTS                                     | return: A2=result, A0=x^2

| ----------------------------------------------------------
|
| ELEMS_CONT_75: cosine kernel - polynomial for cos(x) on [-pi/4, pi/4]
| Uses ELEMS_CONT_115 coefficients, with identity cos(x) = 1 - 2*sin^2(x/2)
| for small arguments to preserve precision
|
ELEMS_CONT_75:
        LEA.L   ELEMS_CONT_115(PC),A2           | A2 = cos coefficients
        BSR.B   ELEMS_CONT_73                   | eval x^2*P(x^2)/Q(x^2)
        PEA.L   (A2)                            | push rational result
        PEA.L   (A0)                            | push x^2
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | x^2 * rational
        PEA.L   ELEMS_CONT_101(PC)              | push 0.25
        PEA.L   (A2)                            | push x^2 * rational
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare with 0.25
        BGT.B   ELEMS_CONT_76                   | > 0.25 -> complementary form
        PEA.L   ELEMS_CONT_102(PC)              | push 0.5
        PEA.L   (A2)                            | push correction term
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | correction * 0.5
        PEA.L   (A2)                            | push half-correction
        PEA.L   (A0)                            | push x^2
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | x^2 - correction
        MOVE.L  A4,A1                           | A1 = result dest
        BSR     ELEMS_EXIT                      | copy subtraction result
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A4)                            | push result
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | cos = 1 - x^2*correction
        RTS                                     | return cosine approximation

| ----------------------------------------------------------
|
| ELEMS_CONT_76: cos kernel - |x| > pi/4, use complementary identity
|
ELEMS_CONT_76:
        BClr    #0x7,(A4)                       | |x| for complementary form
        PEA.L   ELEMS_CONT_102(PC)              | push 0.5
        PEA.L   (A4)                            | push |x|
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | |x| - 0.5
        PEA.L   (A0)                            | push x^2 (already computed)
        MOVE.L  A4,A0                           | A0 = |x| - 0.5
        MOVE.L  A2,A1                           | A1 = temp dest
        BSR     ELEMS_EXIT                      | save (|x|-0.5) to temp
        PEA.L   ELEMS_CONT_102(PC)              | push 0.5
        PEA.L   (A1)                            | push temp
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = 0.5 * (|x|-0.5)
        PEA.L   (A1)                            | push scaled temp
        PEA.L   (A4)                            | push intermediate
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | multiply terms
        PEA.L   (A4)                            | push partial result
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | subtract from x^2 term
        PEA.L   (A1)                            | push correction
        PEA.L   (A4)                            | push result
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | combine terms
        BCHG    #0x7,(A4)                       | negate intermediate
        PEA.L   ELEMS_CONT_104(PC)              | push 0.875 constant
        PEA.L   (A4)                            | push result
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | cos = 0.875 + correction
        RTS                                     | return cosine approximation

| ----------------------------------------------------------
|
| ELEMS_CONT_77: tan(x) - tangent function
| Reduces modulo pi/2, computes sin/cos, then divides
| Handles sign based on quadrant from range reduction
|
ELEMS_CONT_77:
        MOVEQ.L #0x21,D0                        | NaN code 33: trig invalid
        MOVEQ.L #0x0,D2                         | quadrant offset = 0
        SUBQ.B  #0x1,D1                         | check class
        BMI     ELEMS_EXIT_11                   | inf/NaN -> return NaN
        BEQ     ELEMS_EXIT_12                   | zero -> tan(0)=0, return
        BSR     ELEMS_CONT_71                   | range reduce x mod pi/2
        BSR.B   ELEMS_CONT_78                   | compute tan via rational approx
        ROR     #0x1,D2                         | test if odd quadrant (cotan)
        BCC.B   ELEMS_OK_26                     | even -> result is tan directly
        BCHG    #0x7,(A4)                       | negate for cot = -tan
        MOVE.L  A4,A0                           | A0 = tan result
        LEA.L   -0x10(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | save tan to temp
        PEA.L   (A1)                            | push tan value
        LEA.L   ELEMS_CONT_92(PC),A0            | A0 = 1.0
        MOVE.L  A4,A1                           | A1 = result dest
        BSR     ELEMS_EXIT                      | result = 1.0
        PEA.L   (A4)                            | push 1.0
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = 1.0 / tan = cot
        BSR     ELEMS_EMPTY_2                   | set round-toward-zero mode
        BEQ.B   ELEMS_OK_26                     | was already chop -> ok
        BCHG    #0x7,(A4)                       | restore sign if rounding changed
ELEMS_OK_26:
        BRA     ELEMS_EXIT_20                   | -> final sign check and return

| ----------------------------------------------------------
|
| ELEMS_CONT_78: tan kernel - computes sin(x)/cos(x) using ELEMS_CONT_116 coefficients
|
ELEMS_CONT_78:
        LEA.L   ELEMS_CONT_116(PC),A2           | A2 = tan coefficients
        BSR     ELEMS_CONT_73                   | eval x^2*P(x^2)/Q(x^2)
        MOVE.L  A4,A0                           | A0 = x
        LEA.L   -0x2E(A6),A1                    | A1 = deep temp for x copy
        BSR     ELEMS_EXIT                      | save x copy
        PEA.L   (A2)                            | push rational result
        PEA.L   (A1)                            | push x copy
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | x * P/Q
        PEA.L   (A1)                            | push x*P/Q
        LEA.L   -0x1A(A6),A0                    | A0 = x^2 value
        PEA.L   (A0)                            | push x^2
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | x^2 * x*P/Q = x^3*P/Q
        PEA.L   ELEMS_CONT_101(PC)              | push 0.25
        PEA.L   (A2)                            | push x^2*P/Q
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare with 0.25
        BGT.B   ELEMS_CONT_79                   | > 0.25 -> use large-arg form
        PEA.L   ELEMS_CONT_100(PC)              | push 3.0
        PEA.L   (A1)                            | push x^3*P/Q
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | x^3*P/Q / 3
        PEA.L   (A1)                            | push correction term
        PEA.L   (A0)                            | push x^2
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | x^2 + correction
        BRA.B   ELEMS_CONT_80                   | -> combine with x

| ----------------------------------------------------------
|
| ELEMS_CONT_79: tan kernel - |x| > pi/4, compute via identity tan = sin/cos
|
ELEMS_CONT_79:
        PEA.L   (A0)                            | push x^2 (for later use)
        MOVE.L  A4,A0                           | A0 = x
        LEA.L   -0x24(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | temp = x
        PEA.L   ELEMS_CONT_103(PC)              | push 0.75
        PEA.L   (A1)                            | push x
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | temp = x - 0.75
        PEA.L   ELEMS_CONT_100(PC)              | push 3.0
        PEA.L   (A1)                            | push (x - 0.75)
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | temp = (x-0.75) / 3
        PEA.L   (A2)                            | push rational result
        PEA.L   (A1)                            | push quotient
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | multiply by rational
        PEA.L   (A1)                            | push product
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | add to x^2 term
        PEA.L   ELEMS_CONT_101(PC)              | push 0.25
        PEA.L   (A2)                            | push rational
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | scale rational
        PEA.L   (A2)                            | push scaled rational
        PEA.L   (A1)                            | push accumulated
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | combine all correction terms
        MOVE.L  A1,A0                           | A0 = final correction
ELEMS_CONT_80:
        PEA.L   (A0)                            | push correction term
        PEA.L   (A4)                            | push x (result dest)
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | result = x + correction = tan(x)
        RTS                                     | return tangent approximation

| ----------------------------------------------------------
|
| ELEMS_CONT_81: atan(x) - arctangent function
| Handles special cases (0, inf), then calls ELEMS_CONT_83 for core
|
ELEMS_CONT_81:
        SUBQ.B  #0x1,D1                         | check class: 1=zero
        BGE.B   ELEMS_EMPTY_8                   | zero/normal -> handle
        LEA.L   ELEMS_CONT_105(PC),A0           | A0 = pi/2 constant
        MOVE.L  A4,A1                           | A1 = result dest
        BSR     ELEMS_EXIT                      | result = pi/2 (atan(inf))
        CLR.B   D1                              | clear low byte
        OR      D1,(A4)                         | preserve sign of input
        BRA.B   ELEMS_EXIT_21                   | -> return

| ----------------------------------------------------------
|
| ELEMS_EMPTY_8: atan - operand is zero, return zero
|
ELEMS_EMPTY_8:
        BNE.B   ELEMS_CONT_82                   | normal -> compute atan
ELEMS_EXIT_21:
        BRA     ELEMS_EXIT_12                   | zero -> atan(0)=0, return

| ----------------------------------------------------------
|
| ELEMS_CONT_82: atan normal case - reduce argument and evaluate polynomial
|
ELEMS_CONT_82:
        BClr    #0x7,(A4)                       | work with |x|
        BSR.B   ELEMS_CONT_83                   | compute atan(|x|)
        CLR.B   D1                              | clear low byte
        OR      D1,(A4)                         | restore original sign
        BRA     ELEMS_EXIT_20                   | -> classify result and return

| ----------------------------------------------------------
|
| ELEMS_CONT_83: atan kernel - rational polynomial via ELEMS_CONT_117 coefficients
| For |x| > 1, uses identity atan(x) = pi/2 - atan(1/x)
| For |x| <= threshold, uses P(x^2)/Q(x^2) directly
|
ELEMS_CONT_83:
        MOVEQ.L #0x0,D2                         | D2 = 0: direct path flag
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A4)                            | push |x|
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare |x| with 1.0
        BLS.B   ELEMS_CONT_84                   | |x| <= 1 -> direct evaluation
        MOVEQ.L #-0x1,D2                        | D2 = -1: reciprocal path
        MOVE.L  A4,A0                           | A0 = |x|
        LEA.L   -0x10(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | temp = |x|
        PEA.L   (A1)                            | push |x|
        LEA.L   ELEMS_CONT_92(PC),A0            | A0 = 1.0
        MOVE.L  A4,A1                           | A1 = result dest
        BSR     ELEMS_EXIT                      | result = 1.0
        PEA.L   (A1)                            | push 1.0
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | result = 1/|x| (for atan(1/x))
ELEMS_CONT_84:
        MOVE.L  (A4)+,-(SP)                     | save original x on stack
        MOVE.L  (A4)+,-(SP)                     | (10 bytes total)
        MOVE    (A4),-(SP)                      | save last 2 bytes
        SUBQ.L  #0x8,A4                         | restore A4 pointer
        PEA.L   ELEMS_CONT_113(PC)              | push atan threshold constant
        PEA.L   (A4)                            | push reduced arg
        MOVE    #0x8,-(SP)                      | FP opcode: compare
        _FP68K                                  | compare with threshold
        BGT.B   ELEMS_CONT_85                   | > threshold -> large-arg path
        LEA.L   ELEMS_CONT_117(PC),A2           | A2 = atan coefficients
        BSR     ELEMS_CONT_74                   | eval P(x^2)/Q(x^2) rational
        PEA.L   (A0)                            | push x^2 * P/Q
        PEA.L   (A4)                            | push x
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | x * P(x^2)/Q(x^2)
        BRA     ELEMS_CONT_86                   | -> finish: subtract from saved x

| ----------------------------------------------------------
|
| ELEMS_CONT_85: atan - |x| > threshold, use atan(x) = pi/2 - atan(1/x)
|
ELEMS_CONT_85:
        MOVE.L  A4,A0                           | A0 = reduced arg
        LEA.L   -0x10(A6),A1                    | A1 = temp
        BSR     ELEMS_EXIT                      | temp = reduced arg
        PEA.L   ELEMS_CONT_111(PC)              | push atan scaling constant
        PEA.L   (A1)                            | push temp
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | temp = arg * scale
        PEA.L   (A1)                            | push scaled arg
        LEA.L   ELEMS_CONT_92(PC),A0            | A0 = 1.0
        LEA.L   -0x24(A6),A1                    | A1 = temp2
        BSR     ELEMS_EXIT                      | temp2 = 1.0
        PEA.L   (A1)                            | push 1.0
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | temp2 = 1.0 / (arg*scale)
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   (A1)                            | push quotient
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | temp2 = 1 + 1/(arg*scale)
        PEA.L   ELEMS_CONT_92(PC)               | push 1.0
        PEA.L   -0x10(A6)                       | push arg*scale
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | temp = 1 + arg*scale
        PEA.L   ELEMS_CONT_111(PC)              | push atan constant
        PEA.L   (A4)                            | push result
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | result = arg - constant
        MOVE.L  A4,A0                           | A0 = (arg - const)
        LEA.L   -0x2E(A6),A1                    | A1 = deep temp
        BSR     ELEMS_EXIT                      | save (arg - const)
        PEA.L   -0x10(A6)                       | push (1 + arg*scale)
        PEA.L   (A4)                            | push (arg - const)
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | reduced = (arg-c)/(1+arg*c)
        PEA.L   -0x24(A6)                       | push (1 + 1/(arg*c))
        PEA.L   (A1)                            | push saved (arg-c)
        MOVE    #0x6,-(SP)                      | FP opcode: divide
        _FP68K                                  | correction term
        LEA.L   ELEMS_CONT_117(PC),A2           | A2 = atan coefficients
        BSR     ELEMS_CONT_74                   | eval P(x^2)/Q(x^2)
        PEA.L   (A0)                            | push P/Q * x^2
        PEA.L   (A4)                            | push reduced arg
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | reduced * P/Q
        PEA.L   ELEMS_CONT_112(PC)              | push atan offset constant
        PEA.L   (A4)                            | push result
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | add atan offset
        PEA.L   -0x2E(A6)                       | push saved correction
        PEA.L   (A4)                            | push result
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | final atan approximation
ELEMS_CONT_86:
        LEA.L   -0x8(A6),A1                     | A1 = temp for saved x
        MOVE    (SP)+,(A1)                      | restore saved x bytes 8-9
        MOVE.L  (SP)+,-(A1)                     | restore bytes 4-7
        MOVE.L  (SP)+,-(A1)                     | restore bytes 0-3
        PEA.L   (A1)                            | push original x
        PEA.L   (A4)                            | push computed correction
        MOVE    #0x2,-(SP)                      | FP opcode: subtract
        _FP68K                                  | result = x - correction
        TST     D2                              | reciprocal path used?
        BNE.B   ELEMS_OK_27                     | yes -> add pi/2
        BCHG    #0x7,(A4)                       | negate (direct path sign fix)
        RTS                                     | return atan result

| ----------------------------------------------------------
|
| ELEMS_OK_27: atan - finish: add pi/2 for reciprocal path
|
ELEMS_OK_27:
        PEA.L   ELEMS_CONT_105(PC)              | push pi/2
        PEA.L   (A4)                            | push atan(1/x) result
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | atan(x) = pi/2 + atan(1/x)
        RTS                                     | return atan result

| ----------------------------------------------------------
|
| ELEMS_CONT_87: RandomX - pseudo-random number generator
| Multiplies seed by constant and reduces modulo 2^31
|
ELEMS_CONT_87:
        PEA.L   ELEMS_CONT_106(PC)              | push multiplier (16807.0)
        PEA.L   (A4)                            | push seed
        MOVE    #0x4,-(SP)                      | FP opcode: multiply
        _FP68K                                  | seed = seed * 16807
        PEA.L   ELEMS_CONT_107(PC)              | push modulus (2^31 - 2)
        PEA.L   (A4)                            | push seed
        MOVE    #0xC,-(SP)                      | FP opcode: remainder
        _FP68K                                  | seed = seed mod (2^31-2)
        TST.B   (A4)                            | is seed negative?
        BPL.B   ELEMS_DONE_4                    | no -> done
        PEA.L   ELEMS_CONT_107(PC)              | push modulus
        PEA.L   (A4)                            | push seed
        CLR     -(SP)                           | FP opcode: add
        _FP68K                                  | seed = seed + modulus (make pos)
ELEMS_DONE_4:
        BRA     ELEMS_EXIT_12                   | -> common return

| ----------------------------------------------------------
|
| ELEMS_CONT_88: ln(x) numerator polynomial coefficients (degree 5)
|
ELEMS_CONT_88:
  .byte  0x00,0x05,0x3F,0xF6,0xB9,0x46
  .byte 0x46,0xAF,0xF6,0xCE,0x3B,0xFF
  .byte 0x3F,0xF9,0x94,0xF4,0x32,0x21
  .byte 0x4D,0x61,0xFB,0xEB,0x3F,0xFB
  .byte 0xDC,0x97,0x89,0x03,0xD9,0x44
  .byte 0x78,0x93,0x3F,0xFF,0x9F,0x9E
  .byte 0x39,0x46,0x57,0xCA,0x1D,0x05
  .byte 0xC0,0x01,0xCD,0x6B,0xC5,0x3A
  .byte 0x46,0xEC,0xDC,0x9A,0x40,0x01
  .byte 0xB4,0x83,0x97,0xE7,0xBA,0xE6
  .byte 0xFC,0xE0
| ELEMS_CONT_89: ln(x) denominator polynomial coefficients (degree 2)
ELEMS_CONT_89:
  .byte  0x00,0x02,0x3F,0xFF,0x80,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0xC0,0x00,0xB8,0x18,0x35,0xC3
  .byte 0xCE,0x0A,0x5E,0x1D,0x3F,0xFF
  .byte 0xFA,0x3E,0xDF,0x0E,0xDD,0xF4
  .byte 0x1A,0x96
| ELEMS_CONT_90: 2^f-1 numerator polynomial coefficients (degree 3)
ELEMS_CONT_90:
  .byte  0x00,0x03,0xBF,0xEE,0xFF,0x88
  .byte 0x90,0xC8,0x1B,0x20,0x9B,0x79
  .byte 0x3F,0xF9,0xDA,0x5C,0x84,0xEF
  .byte 0xB8,0x13,0x27,0x2F,0x40,0x03
  .byte 0x97,0xD3,0xBA,0xEA,0xF8,0x0F
  .byte 0xFD,0x45,0x40,0x09,0xAB,0x86
  .byte 0x71,0xA1,0x95,0xBE,0xFF,0x0C
| ELEMS_CONT_91: 2^f-1 denominator polynomial coefficients (degree 2)
ELEMS_CONT_91:
  .byte  0x00,0x02,0x3F,0xFF,0x80,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x40,0x06,0xD5,0x48,0x70,0x02
  .byte 0x98,0x4B,0x5A,0xB4,0x40,0x0A
  .byte 0xF7,0x75,0x61,0x2E,0x96,0xB7
  .byte 0x07,0x80
| Extended-precision constants (10 bytes each)
ELEMS_CONT_92:                                  | +1.0
  .byte  0x3F,0xFF,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_93:                                  | -1.0
  .byte  0xBF,0xFF,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_94:                                  | +0.0
  .byte  0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_95:                                  | -0.0
  .byte  0x80,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_96:                                  | +2.0
  .byte  0x40,0x00,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_97:                                  | 32766.0 (max scalb)
  .byte  0x40,0x0D,0xFF,0xFE,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_98:                                  | +NaN (quiet)
  .byte  0x7F,0xFF,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_99:                                  | -NaN (quiet)
  .byte  0xFF,0xFF,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_100:                                 | +3.0
  .byte  0x40,0x00,0xC0,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_101:                                 | +0.25
  .byte  0x3F,0xFD,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_102:                                 | +0.5
  .byte  0x3F,0xFE,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_103:                                 | +0.75
  .byte  0x3F,0xFE,0xC0,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_104:                                 | +0.875
  .byte  0x3F,0xFE,0xE0,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_105:                                 | pi and pi/2 (for trig range reduction)
  .byte  0x3F,0xFF,0xC9,0x0F,0xDA,0xA2
  .byte 0x21,0x68,0xC2,0x35,0x3F,0xFE
  .byte 0xC9,0x0F,0xDA,0xA2,0x21,0x68
  .byte 0xC2,0x35
| ELEMS_CONT_106: RandomX multiplier = 16807 (7^5, Park-Miller LCG constant)
ELEMS_CONT_106:
  .byte  0x40,0x0D,0x83,0x4E,0x00,0x00
  .byte 0x00,0x00,0x00,0x00
| ELEMS_CONT_107: RandomX modulus = 2^31 - 2 = 2147483646
ELEMS_CONT_107:
  .byte  0x40,0x1D,0xFF,0xFF,0xFF,0xFE
  .byte 0x00,0x00,0x00,0x00
ELEMS_CONT_108:                                 | sqrt(2) = 1.41421356...
  .byte  0x3F,0xFF,0xB5,0x04,0xF3,0x33
  .byte 0xF9,0xDE,0x64,0x84
| ELEMS_CONT_109: sqrt(2)/2 = 0.70710678... followed by 2*ln(2) for ln range reduction
ELEMS_CONT_109:
  .byte  0x3F,0xFE,0xB5,0x04,0xF3,0x33
  .byte 0xF9,0xDE,0x64,0x84,0x40,0x00
  .byte 0xAD,0xF8,0x54,0x58,0xA2,0xBB
  .byte 0x4A,0x9B
ELEMS_CONT_110:                                 | ln(2) = 0.693147180...
  .byte  0x3F,0xFE,0xB1,0x72,0x17,0xF7
  .byte 0xD1,0xCF,0x79,0xAC
| ELEMS_CONT_111: atan threshold/scale constant (~0.57735 = tan(pi/6) = 1/sqrt(3))
ELEMS_CONT_111:
  .byte  0x3F,0xFE,0x93,0xCD,0x3A,0x2C
  .byte 0x81,0x98,0xE2,0x6A
| ELEMS_CONT_112: atan offset constant (~pi/6 = 0.5235987...)
ELEMS_CONT_112:
  .byte  0x3F,0xFA,0xDC,0x2A,0x86,0xB1
  .byte 0x5F,0xDB,0x64,0x62
| ELEMS_CONT_113: atan range threshold (~0.26795 = 2-sqrt(3))
ELEMS_CONT_113:
  .byte  0x3F,0xFD,0x89,0x30,0xA2,0xF4
  .byte 0xF6,0x6A,0xB1,0x8A
| ELEMS_CONT_114: sin(x) P/Q rational coefficients (degree 3 each)
ELEMS_CONT_114:
  .byte  0x00,0x03,0x3F,0xFF,0x80,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x40,0x07,0x88,0xD8,0xB8,0x44
  .byte 0xA6,0xA8,0x5A,0x30,0x40,0x0E
  .byte 0x8A,0x15,0x8A,0x49,0x09,0x79
  .byte 0x23,0x20,0x40,0x13,0xFA,0xA9
  .byte 0xFE,0x26,0xFE,0x63,0xF2,0x2B
  .byte 0x00,0x03,0xBF,0xFE,0xC2,0x50
  .byte 0x86,0xAE,0x43,0xF5,0xCB,0xF5
  .byte 0x40,0x06,0x9E,0x76,0xEC,0x66
  .byte 0xBE,0xE7,0x6B,0xA2,0xC0,0x0C
  .byte 0xAF,0x51,0xA1,0xD6,0xC4,0xC4
  .byte 0xAA,0x01,0x40,0x11,0xA7,0x1B
  .byte 0xFE,0xC4,0xA9,0x97,0xF6,0xCE
| ELEMS_CONT_115: cos(x) P/Q rational coefficients (degree 3 each)
ELEMS_CONT_115:
  .byte  0x00,0x03,0x3F,0xFF,0x80,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x40,0x07,0xA6,0xD9,0x6A,0x95
  .byte 0xFB,0xDF,0x96,0x85,0x40,0x0E
  .byte 0xC7,0xA7,0xEA,0x65,0xE8,0x5D
  .byte 0x15,0x6B,0x40,0x14,0xD2,0x6E
  .byte 0x87,0x1C,0x7B,0x17,0x52,0xB2
  .byte 0x00,0x03,0xBF,0xFB,0xD5,0x7E
  .byte 0x18,0xD7,0xA6,0xF6,0xD7,0x58
  .byte 0x40,0x03,0xE3,0x64,0x93,0x7E
  .byte 0x32,0xB3,0xD0,0x72,0xC0,0x0A
  .byte 0xA6,0x2D,0x40,0x56,0x58,0x6B
  .byte 0xC0,0x45,0x40,0x10,0x8C,0x49
  .byte 0xAF,0x68,0x52,0x0F,0x8C,0x7A
| ELEMS_CONT_116: tan(x) P/Q rational coefficients (degree 3 each)
ELEMS_CONT_116:
  .byte  0x00,0x03,0xBF,0xFF,0x80,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x40,0x05,0xB5,0x13,0x03,0x24
  .byte 0x83,0xC0,0x09,0x55,0xC0,0x09
  .byte 0xD1,0xFF,0xB2,0x42,0x57,0x62
  .byte 0xE0,0xCF,0x40,0x0A,0xE1,0x90
  .byte 0x93,0x09,0x93,0x76,0x66,0xAB
  .byte 0x00,0x03,0xBF,0xE9,0xB1,0xFC
  .byte 0x33,0x63,0xD7,0x9B,0x28,0x38
  .byte 0x3F,0xFD,0xAA,0x9D,0x71,0xD8
  .byte 0x3E,0xC7,0x4C,0xD1,0xC0,0x03
  .byte 0xE9,0xCD,0x8E,0x24,0xB9,0x65
  .byte 0x7D,0xBB,0x40,0x07,0xF0,0x9A
  .byte 0x36,0x70,0x9D,0x4B,0x18,0x36
| ELEMS_CONT_117: atan(x) P/Q rational coefficients (degree 4 each)
ELEMS_CONT_117:
  .byte  0x00,0x04,0x3F,0xFF,0x98,0xD3
  .byte 0x1E,0xAE,0x2A,0xFA,0x5D,0xAD
  .byte 0x40,0x03,0x8F,0x79,0x4C,0xD8
  .byte 0xB3,0xCD,0xEF,0xD9,0x40,0x05
  .byte 0x8E,0x37,0xED,0x85,0x70,0xB8
  .byte 0xB3,0x68,0x40,0x05,0xCD,0xA4
  .byte 0xBE,0xA1,0xAC,0x59,0xF3,0xB8
  .byte 0x40,0x04,0xC4,0x05,0x9C,0x55
  .byte 0x4C,0xF0,0xC6,0x56,0x00,0x04
  .byte 0x3F,0xFF,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00,0x40,0x02
  .byte 0xA2,0x3B,0x6C,0x13,0x1F,0x92
  .byte 0x0E,0x30,0x40,0x03,0xC3,0xC8
  .byte 0x59,0x3D,0xFA,0x3A,0x48,0x6F
  .byte 0x40,0x03,0x82,0xAE,0x68,0x38
  .byte 0xDD,0xF5,0xD9,0x45,0x00,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x00

| end of resource : 'PACK' 5

| resource header
  .long 0xC00011C0                              | Length
  .long 0x0000007C                              | ?
