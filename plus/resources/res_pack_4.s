|
| resource : 'PACK' 4 - SANE Floating-Point Arithmetic (FP68K)
| IEEE 754 implementation for 68000 (no FPU)
| Selector word on stack encodes: operation (bits 0-4), format (bits 13-14)
| Formats: 0=extended(80-bit), 1=double(64-bit), 2=single(32-bit), 3=comp(64-bit int)
| Operations: 0=add, 2=sub, 4=mul, 6=div, 8=cmp, $A=cvt, $C=rem,
| $E=sqrt, $10=rint, $12=tint, $14=scalb, $16=logb, $18=class
OPERATIONS:
        BRA.B   FP68K_SKIP                      | skip resource header
  .byte 0x00,0x00
  .ascii "PACK"
  .byte 0x00,0x04,0x00,0x02
| FP68K entry point (from _FP68K trap)
FP68K_SKIP:
        LINK    A6,#-0x2                        | 2 bytes local
        MOVEM.L D0-D7/A0-A4,-(SP)               | save all registers
        MOVE    #0xA4A,A0                       | A0 = FPState address offset
        BRA.B   FP68K_CONT_2                    | -> common dispatch

| ----------------------------------------------------------
|
| FP68K_CONT: operation descriptor table (15 entries)
| Each word: bits 7-0 = handler offset, bits 15-8 = operand requirements
|
FP68K_CONT:
  .byte  0x00,0xE1,0x00,0xE1,0x00,0xE1
  .byte 0x00,0xE1,0x00,0xC1,0x00,0xC1
  .byte 0x00,0xE1,0x00,0x61,0x01,0x61
  .byte 0x00,0xA0,0x00,0xA0,0x00,0xA0
  .byte 0x00,0xA1,0x00,0xA0,0x00,0x41
| FP68K_EMPTY: alternate FP68K entry (for internal calls)
| Called by: FP68K_CONT_106, FP68K_DONE_13, FP68K_CONT_116, FP68K_OK_35, FP68K_OK_36 (and 2 more)
FP68K_EMPTY:
        LINK    A6,#-0x2                        | 2 bytes local
        MOVEM.L D0-D7/A0-A4,-(SP)               | save all registers
| common dispatch: parse selector and dispatch to operation handler
FP68K_CONT_2:
        MOVE    0x8(A6),D6                      | D6 = selector word from stack
| decode selector: extract operation code and operand format
        MOVEQ.L #0x1E,D7                        | mask for operation code (bits 1-4)
        AND     D6,D7                           | D7 = operation * 2 (table index)
        BCLR    #0x0,D6                         | test/clear environment access bit
        BNE     FP68K_CONT_95                   | environment op (get/set flags) ->
| look up operation descriptor from FP68K_CONT table
        BCLR    #0x7,0x1(A0)                    | clear FP state flag
        OR      FP68K_CONT(PC,D7.W),D6          | merge handler info into D6
| extract rounding mode from FP state
        MOVEQ.L #0x60,D0                        | rounding mode bits mask
        AND.B   0x1(A0),D0                      | get current rounding mode
        ROR     #0x7,D0                         | position for dispatch
        OR      D0,D6                           | merge into D6
| handle two-operand format encoding
        BTST    #0x8,D6                         | two-operand format?
        BEQ.B   FP68K_NO                        | no ->
        MOVE    D6,D0                           | copy selector for format split
        ANDI    #0xFF,D6                        | isolate handler offset
        ANDI    #0x3800,D0                      | isolate source format bits
        MOVE    D0,D1                           | copy source format
        LSL     #0x3,D1                         | shift for dest format
        ROR     #0x3,D0                         | position source format
        OR      D0,D6                           | merge formats
        OR      D1,D6                           | add dest format to descriptor
| set up operand registers
FP68K_NO:
        SWAP    D6                              | operation info to high word
        CLR.L   D2                              | clear accumulator
        MOVE.L  D2,D3                           | clear extended mantissa
        MOVE    D2,D6                           | clear flags
        BTST    #0x17,D6                        | has destination operand?
        BEQ.B   FP68K_NO_2                      | no ->
        MOVE.L  D6,D0                           | copy for format extraction
        SWAP    D0                              | get high word
        ROR     #0x7,D0                         | extract dest format code
        MOVE.L  0xA(A6),A3                      | A3 = dest operand ptr
        BSR     FP68K_CONT_5                    | unpack dest to D4:D5, exp in A4
FP68K_NO_2:
        BTst    #0x16,D6                        | has source operand?
        BEQ.B   FP68K_NO_3                      | no ->
        MOVE.L  D4,A1                           | save dest mantissa high
        MOVE.L  D5,A2                           | save dest mantissa low
        MOVE.L  A4,-(SP)                        | save dest exponent
        ROR.B   #0x1,D6                         | shift sign into carry
        ADD     D2,D2                           | D2 = D2 * 2 (NaN count shift)
        MOVE    D3,D0                           | save D3 class code
        ADD     D3,D3                           | D3 = D3 * 2
        ADD     D0,D3                           | D3 = D3 * 3 (interleave classes)
        MOVE.L  D6,D0                           | copy for format extraction
        SWAP    D0                              | get high word
        ROL     #0x6,D0                         | extract source format code
        MOVE.L  0xE(A6),A3                      | A3 = source operand ptr
        BSR     FP68K_CONT_5                    | unpack source to D4:D5
        MOVE.L  (SP)+,A3                        | restore dest exponent to A3
FP68K_NO_3:
        ASL.B   #0x1,D6                         | combine sign bits
        BVC.B   FP68K_SKIP_2                    | same sign -> skip
        BSET    #0x6,D6                         | set opposite-signs flag
FP68K_SKIP_2:
        ROXR.B  #0x1,D6                         | finalize sign encoding
        MOVE    D7,D0                           | D0 = operation index
        CLR.L   D7                              | clear guard bits
        PEA.L   FP68K_EXIT(PC)                  | push return address (pack result)
        TST     D2                              | any NaN operands?
        BNE     FP68K_OK_4                      | yes, propagate NaN ->
| FP operation dispatch: D0 = operation * 2 -> jump to handler
FP68K_CONT_3:
        MOVE    FP68K_CONT_4(PC,D0.W),D0        | get handler offset from table
        JMP     FP68K_CONT_3(PC,D0.W)           | dispatch to FP operation

| FP operation handler table (offsets from FP68K_CONT_3):
| 0=add, 1=sub, 2=mul, 3=div, 4=cmp, 5=cmpunord,
| 6=cvt, 7=sqrt, 8=rem, 9=rint, 10=tint, 11=scalb,
| 12=logb, 13=class, 14=setenv
FP68K_CONT_4:
  .byte  0x04,0xBC,0x04,0xB8,0x05,0x56
  .byte 0x05,0xF6,0x07,0x0C,0x07,0x0C
  .byte 0x06,0x8E,0x07,0x78,0x07,0xEC
  .byte 0x08,0x54,0x07,0x80,0x07,0x8C
  .byte 0x09,0x30,0x08,0xFA,0x09,0x40
| FP68K_EXIT: return from FP operation - pack result and clean up
FP68K_EXIT:
        BTst    #0x15,D6                        | need to pack result?
        BEQ.B   FP68K_EXIT_2                    | no, already packed ->
        MOVE.L  D6,D0                           | copy for format extraction
        SWAP    D0                              | get high word
        ROR     #0x7,D0                         | extract destination format
        BSR     FP68K_CONT_31                   | pack to destination format
FP68K_EXIT_2:
        SWAP    D7                              | D7 high = condition codes
        MOVE    (A0),D0                         | get SANE exception flags
        CLR.B   D6                              | clear low byte for OR
        OR      D6,D0                           | merge pending exceptions
        MOVE    D0,(A0)+                        | update exception state
        ROR     #0x8,D6                         | extract halt enable mask
        AND     D6,D0                           | masked halts pending?
        BEQ.B   FP68K_NO_4                      | no halts ->
        MOVE    D7,-(SP)                        | push condition codes
        MOVE    D0,-(SP)                        | push halt exceptions
        PEA.L   (SP)                            | push halt info ptr
        MOVEM.L 0x6(A6),D0-D3                   | restore original params
        MOVEM.L D0-D3,-(SP)                     | pass to halt handler
        ADDQ.L  #0x2,SP                         | adjust stack alignment
        MOVE.L  (A0),A0                         | A0 = halt vector
        JSR     (A0)                            | call halt handler
        MOVE.L  (SP)+,D7                        | recover condition codes
FP68K_NO_4:
        BTst    #0x10,D6                        | three-operand operation?
        BEQ.B   FP68K_EXIT_4                    | no, two-operand return ->
FP68K_EXIT_3:
        MOVEQ.L #0x10,D0                        | stack cleanup = 16 bytes
        MOVEQ.L #0xE,D1                         | return address offset = 14
        BRA.B   FP68K_EXIT_5                    | -> common return

| ----------------------------------------------------------
|
| FP68K_EXIT_4
|
| FP68K_EXIT_4: two-operand return (pop 12 bytes of params)
FP68K_EXIT_4:
        MOVEQ.L #0xC,D0                         | stack cleanup size
        MOVEQ.L #0xA,D1                         | return address offset
| FP68K_EXIT_5: common FP return - clean stack and restore regs
FP68K_EXIT_5:
        MOVE    D0,-0x2(A6)                     | save stack cleanup size
        MOVE.L  0x4(A6),0x0(A6,D1.W)            | relocate return address
        MOVE.L  (A6),A6                         | unlink frame
        MOVE    D7,CCR                          | restore condition codes
        MOVEM.L (SP)+,D0-D7/A0-A4               | restore all registers
        ADDA    (SP),SP                         | pop params per size
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_EXIT_6: three-operand return (pop 20 bytes of params)
|
FP68K_EXIT_6:
        MOVEQ.L #0x14,D0                        | stack cleanup = 20 bytes
        MOVEQ.L #0x12,D1                        | return address offset = 18
        BRA.B   FP68K_EXIT_5                    | -> common return

| ----------------------------------------------------------
|
| FP68K_CONT_5
|
| FP68K_CONT_5: unpack source operand to extended format (80-bit)
| Dispatches by format code to extract sign, exponent, mantissa
| D0 bits 1-3 = format: 0=extended, 1=double, 2=single, 3=extended, 4=integer, 5=long, 6=comp
FP68K_CONT_5:
        CLR.L   D4                              | clear mantissa high
        MOVE.L  D4,D5                           | clear mantissa low
        ANDI    #0xE,D0                         | mask to format * 2
        MOVE    FP68K_CONT_6(PC,D0.W),D0        | get handler offset
        JMP     FP68K_CONT_5(PC,D0.W)           | dispatch by format

| FP68K_CONT_5 format dispatch table (offsets from FP68K_CONT_5)
FP68K_CONT_6:
  .byte  0x00,0x68,0x00,0xF2,0x00,0xC8
  .byte 0x00,0x68,0x00,0x1E,0x00,0x26
  .byte 0x00,0x2C
| format 4: unpack 16-bit integer to extended
FP68K_CONT_7:
        MOVEQ.L #0xF,D0                         | 16-bit exponent bias
        MOVE    (A3),D4                         | load 16-bit integer
        SWAP    D4                              | shift to high word
        BRA.B   FP68K_NO_5                      | -> normalize
| format 5: unpack 32-bit long integer to extended
FP68K_CONT_8:
        MOVEQ.L #0x1F,D0                        | 32-bit exponent bias
        MOVE.L  (A3),D4                         | load 32-bit integer
        BRA.B   FP68K_NO_5                      | -> normalize

| ----------------------------------------------------------
|
| FP68K_CONT_9
|
| format 6: unpack 64-bit comp (integer) to extended
FP68K_CONT_9:
        MOVEQ.L #0x3F,D0                        | 64-bit exponent bias
        MOVE.L  (A3),D4                         | load high 32 bits
        MOVE.L  0x4(A3),D5                      | load low 32 bits
        BEQ.B   FP68K_CONT_10                   | low = 0, check for special values ->
        TST.L   D4                              | set flags for high word
        BRA.B   FP68K_CONT_11                   | -> normalize

| ----------------------------------------------------------
|
| comp special case: check for NaN encoding ($80000000:00000000)
|
FP68K_CONT_10:
        CMPI.L  #0x80000000,D4                  | comp NaN?
        BNE.B   FP68K_NO_5                      | no, normalize normally ->
| comp NaN: encode as extended NaN
        MOVE    #0x7FFF,A4                      | max exponent = NaN/Inf
        MOVEQ.L #0x14,D4                        | NaN payload
        SWAP    D4                              | move payload to high word
        BSET    #0x1E,D4                        | set NaN signaling bit
        BRA.B   FP68K_DONE                      | -> done unpacking

| ----------------------------------------------------------
|
| normalize integer mantissa: find MSB and set exponent
|
FP68K_NO_5:
        TST.L   D4                              | mantissa zero?
        BEQ.B   FP68K_EMPTY_3                   | yes -> zero result
FP68K_CONT_11:
        BPL.B   FP68K_CONT_12                   | positive -> normalize
        BSET    #0x7,D6                         | set sign flag for negative
        NEG.L   D5                              | negate to get absolute value
        NEGX.L  D4                              | negate high with borrow
FP68K_CONT_12:
        ADDI    #0x3FFF,D0                      | add extended exponent bias
        TST.L   D4                              | MSB set? (already normalized)
        BMI.B   FP68K_OK                        | yes -> store exponent
        BRA.B   FP68K_LOOP                      | no -> shift left to normalize

| ----------------------------------------------------------
|
| FP68K_CONT_13: unpack extended (80-bit) to internal format
| Already in native format; just extract sign and check for special values
|
FP68K_CONT_13:
        MOVE    (A3),D0                         | D0 = exponent+sign word
        BPL.B   FP68K_SKIP_3                    | positive -> skip sign
        BSET    #0x7,D6                         | record negative sign
        BCLR    #0xF,D0                         | clear sign from exponent
FP68K_SKIP_3:
        MOVE.L  PORTBITS(A3),D4                 | D4 = mantissa high 32 bits
        MOVE.L  0x6(A3),D5                      | D5 = mantissa low 32 bits
        CMPI    #0x7FFF,D0                      | max exponent (NaN/Inf)?
        BEQ.B   FP68K_OK_2                      | yes -> handle special
        TST.L   D4                              | explicit integer bit set?
        BMI.B   FP68K_OK                        | yes, already normalized ->
FP68K_EMPTY_2:
        TST.L   D4                              | high mantissa zero?
        BNE.B   FP68K_NO_6                      | no, denormalized ->
        TST.L   D5                              | low mantissa zero?
        BNE.B   FP68K_NO_6                      | no, denormalized ->
| both mantissa halves zero = true zero
FP68K_EMPTY_3:
        SUBA.L  A4,A4                           | exponent = 0
        ADDQ.W  #0x2,D3                         | class = zero
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_NO_6: denormalized number - left-shift until MSB set
|
FP68K_NO_6:
        BSet    #0x1F,D3                        | mark as denormal
FP68K_LOOP:
        SUBQ.W  #0x1,D0                         | decrement exponent
        ADD.L   D5,D5                           | left-shift mantissa
        ADDX.L  D4,D4                           | propagate carry to high
        BPL.B   FP68K_LOOP                      | loop until MSB set
FP68K_OK:
        EXT.L   D0                              | sign-extend exponent to long
        MOVE.L  D0,A4                           | store exponent in A4
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_2
|
| FP68K_OK_2: exponent = $7FFF - classify as NaN or infinity
FP68K_OK_2:
        MOVE    #0x7FFF,A4                      | store max exponent
        BCLR    #0x1F,D4                        | clear explicit integer bit
        TST.L   D4                              | mantissa high nonzero?
        BNE.B   FP68K_DONE                      | yes -> NaN
        TST.L   D5                              | mantissa low nonzero?
        BNE.B   FP68K_DONE                      | yes -> NaN
        ADDQ.W  #0x4,D3                         | class = infinity (D3 += 4)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_DONE: NaN detected - set signaling/quiet flag
|
FP68K_DONE:
        BSet    #0x1E,D4                        | test/set quiet NaN bit
        BNE.B   FP68K_CONT_14                   | already quiet NaN ->
        BSET    #0x8,D6                         | flag signaling NaN (invalid)
FP68K_CONT_14:
        ADDQ.W  #0x2,D2                         | class = NaN (D2 += 2)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_15: unpack IEEE single (32-bit) to internal extended
| Extracts sign, 8-bit exponent, 23-bit mantissa
|
FP68K_CONT_15:
        CLR.L   D0                              | clear exponent accumulator
        MOVE.L  (A3),D4                         | load 32-bit single value
        ADD.B   D6,D6                           | shift sign flag left
        ADD.L   D4,D4                           | shift out sign bit into X
        ROXR.B  #0x1,D6                         | capture sign in D6 bit 7
        ROL.L   #0x8,D4                         | rotate exponent to low byte
        MOVE.B  D4,D0                           | D0 = biased exponent
        BEQ.B   FP68K_EMPTY_4                   | zero exponent -> denorm/zero
        MOVE.B  #0x1,D4                         | set implicit leading 1 bit
        ROR.L   #0x1,D4                         | position mantissa MSB at bit 31
        CMPI.B  #0xFF,D0                        | max exponent?
        BEQ.B   FP68K_OK_2                      | yes -> NaN or infinity
        ADDI    #0x3F80,D0                      | rebias: single(127) -> ext(16383)
        BRA.B   FP68K_OK                        | -> store exponent

| ----------------------------------------------------------
|
| FP68K_EMPTY_4
|
FP68K_EMPTY_4:
        MOVE    #0x3F81,D0                      | min single exponent (rebiased)
        ROR.L   #0x1,D4                         | shift mantissa right (no implicit 1)
        BRA.B   FP68K_EMPTY_2                   | -> check for zero/denorm

| ----------------------------------------------------------
|
| FP68K_CONT_16: unpack IEEE double (64-bit) to internal extended
| Extracts sign, 11-bit exponent, 52-bit mantissa
|
FP68K_CONT_16:
        MOVE.L  (A3),D4                         | load double high word
        BPL.B   FP68K_SKIP_4                    | positive -> skip sign
        BSET    #0x7,D6                         | record negative sign
FP68K_SKIP_4:
        MOVE.L  0x4(A3),D5                      | load double low word
        ROL.L   #0x8,D5                         | rotate mantissa bits
        ROL.L   #0x3,D5                         | align low mantissa
        ROL.L   #0x8,D4                         | rotate high word
        ROL.L   #0x4,D4                         | align high mantissa
        MOVE    D4,D0                           | save for exponent extraction
        LSR.L   #0x1,D4                         | shift mantissa right
        ANDI    #-0x800,D4                      | mask high mantissa bits
        MOVE    D5,D1                           | get low bits for merge
        ANDI    #0x7FF,D1                       | isolate bits to merge up
        OR      D1,D4                           | combine into high mantissa
        ANDI    #-0x800,D5                      | mask low mantissa bits
        ANDI    #0x7FF,D0                       | extract 11-bit exponent
        BNE.B   FP68K_CONT_17                   | nonzero -> normal or special
        MOVE    #0x3C01,D0                      | min double exponent (rebiased)
        BRA     FP68K_EMPTY_2                   | -> check for zero/denorm

| ----------------------------------------------------------
|
| FP68K_CONT_17
|
FP68K_CONT_17:
        CMPI    #0x7FF,D0                       | max double exponent?
        BEQ     FP68K_OK_2                      | yes -> NaN or infinity
        BSET    #0x1F,D4                        | set implicit leading 1 bit
        ADDI    #0x3C00,D0                      | rebias: double(1023) -> ext(16383)
        BRA     FP68K_OK                        | -> store exponent

| ----------------------------------------------------------
|
| FP68K_OK_3: construct NaN result with payload from D0
|
FP68K_OK_3:
        BSet    #0x8,D6                         | flag invalid operation
        SWAP    D0                              | payload to high word
        BSET    #0x1E,D0                        | set quiet NaN bit
        MOVE.L  D0,D4                           | mantissa high = NaN payload
        CLR.L   D5                              | mantissa low = 0
        MOVE    #0x7FFF,A4                      | exponent = NaN
        BRA.B   FP68K_OK_6                      | -> NaN result path

| ----------------------------------------------------------
|
| FP68K_OK_4: NaN propagation - select NaN with largest payload
|
FP68K_OK_4:
        CMPI    #0x2,D2                         | only source is NaN?
        BEQ.B   FP68K_OK_6                      | yes, use source NaN as result
        CMPI    #0x4,D2                         | only dest is NaN?
        BEQ.B   FP68K_OK_5                      | yes, use dest NaN ->
        MOVE.L  #0xFF0000,D0                    | mask for NaN payload comparison
        MOVE.L  A1,D1                           | D1 = dest mantissa high
        AND.L   D0,D1                           | isolate dest NaN payload
        AND.L   D4,D0                           | isolate source NaN payload
        CMP.L   D0,D1                           | compare payloads
        BLE.B   FP68K_OK_6                      | source >= dest, keep source
FP68K_OK_5:
        ROL.B   #0x1,D6                         | swap sign to match dest
        MOVE.L  A3,A4                           | use dest exponent
        MOVE.L  A2,D5                           | use dest mantissa low
        MOVE.L  A1,D4                           | use dest mantissa high
FP68K_OK_6:
        BTst    #0x1A,D6                        | convert-to-integer operation?
        BEQ.B   FP68K_NO_7                      | no -> normal NaN result
        CLR.L   D4                              | clear mantissa high
        MOVEQ.L #0x1,D5                         | prepare integer NaN result
        ROR.L   #0x1,D5                         | D5 = $80000000
        BTST    #0x18,D6                        | target is 16-bit int?
        BNE.B   FP68K_EXIT_7                    | yes -> return $8000
        BTST    #0x19,D6                        | target is 32-bit long?
        BNE.B   FP68K_EXIT_8                    | yes -> return $80000000
        SWAP    D5                              | D5 = $00008000 for 16-bit
FP68K_EXIT_7:
        BSet    #0x8,D6                         | flag invalid operation
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_EXIT_8
|
| FP68K_EXIT_8: comp NaN result - return $80000000:00000000
FP68K_EXIT_8:
        exg     D4,D5                           | swap for 64-bit comp NaN
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_NO_7: NaN result post-processing - handle pack/return
|
FP68K_NO_7:
        BTst    #0x15,D6                        | need to pack result?
        BNE.B   FP68K_OK_8                      | yes -> truncate NaN for format
        BTST    #0x14,D6                        | compare operation?
        BNE.B   FP68K_EXIT_9                    | yes -> return unordered
        MOVEQ.L #0x2,D0                         | condition = unordered
        BRA     FP68K_CONT_71                   | -> set condition code

| ----------------------------------------------------------
|
| FP68K_EXIT_9: NaN in compare - return unordered, flag if signaling
|
FP68K_EXIT_9:
        MOVEQ.L #0x1,D0                         | assume ordered compare
        BCLR    #0x8,D6                         | was signaling NaN?
        BNE.B   FP68K_OK_7                      | yes -> flag invalid
        ADDQ.W  #0x1,D0                         | no -> unordered (D0 = 2)
FP68K_OK_7:
        BRA     FP68K_NO_33                     | -> store class result

| ----------------------------------------------------------
|
| FP68K_OK_8: truncate NaN mantissa for target format (single/double)
|
FP68K_OK_8:
        BTst    #0x1F,D6                        | single precision target?
        BEQ.B   FP68K_NO_8                      | no -> check double
        MOVEQ.L #0x0,D5                         | clear low mantissa
        MOVE.B  D5,D4                           | clear low byte of high mantissa
        BRA.B   FP68K_NO_9                      | -> ensure nonzero payload

| ----------------------------------------------------------
|
| FP68K_NO_8: truncate NaN for double precision
|
FP68K_NO_8:
        BTst    #0x1E,D6                        | double precision target?
        BEQ.B   FP68K_NO_9                      | no -> extended, no truncation
        ANDI    #-0x800,D5                      | mask low 11 bits (double limit)
FP68K_NO_9:
        MOVE.L  D4,D0                           | copy mantissa high
        BCLR    #0x1E,D0                        | clear quiet NaN bit for test
        OR.L    D5,D0                           | combine with low mantissa
        BNE.B   FP68K_DONE_2                    | payload nonzero -> done
        MOVEQ.L #0x15,D4                        | default NaN payload = 21
        SWAP    D4                              | shift to high word
        BSET    #0x1E,D4                        | set quiet NaN bit
FP68K_DONE_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_18
|
| FP68K_CONT_18/FP68K_CONT_19: propagate source operand as result (identity op)
FP68K_CONT_18:
        ADD.B   D6,D6                           | use source sign (shift left)
FP68K_CONT_19:
        MOVE.L  A1,D4                           | result = source mantissa high
        MOVE.L  A2,D5                           | result = source mantissa low
        MOVE.L  A3,A4                           | result = source exponent
FP68K_CONT_20:
        RTS                                     | identity: return operand as-is

| ----------------------------------------------------------
|
| FP68K_CONT_21: right-shift mantissa D4:D5:D7 by D0 bits
| Shifts out bits are OR'd into D7 for rounding decisions
|
FP68K_CONT_21:
        CMPI    #0x42,D0                        | clamp shift count to 66 max
        BLS.B   FP68K_DONE_3                    | within range ->
        MOVE    #0x42,D0                        | cap at 66 bits
FP68K_DONE_3:
        LSR.L   #0x1,D4                         | shift mantissa high right
        ROXR.L  #0x1,D5                         | propagate through mantissa low
        ROXR    #0x1,D7                         | shift into guard bits
        SCS.B   D1                              | D1 = $FF if bit shifted out
        OR.B    D1,D7                           | accumulate sticky bit
        SUBQ.W  #0x1,D0                         | decrement shift count
        BNE.B   FP68K_DONE_3                    | loop until done
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_22: normalize result - check for zero, then left-shift to MSB
|
FP68K_CONT_22:
        TST.L   D4                              | mantissa high nonzero?
        BNE.B   FP68K_OK_9                      | yes -> normalize
        TST.L   D5                              | mantissa low nonzero?
        BNE.B   FP68K_OK_9                      | yes -> normalize
        TST     D7                              | guard bits nonzero?
        BNE.B   FP68K_OK_9                      | yes -> normalize
        SUBA.L  A4,A4                           | all zero: result is zero
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_9
|
FP68K_OK_9:
        TST.L   D4                              | test mantissa high
        BRA.B   FP68K_CONT_23                   | -> check if normalized

| ----------------------------------------------------------
|
| FP68K_LOOP_2: normalize loop - left-shift until MSB set
|
FP68K_LOOP_2:
        SUBQ.L  #0x1,A4                         | decrement exponent
        ADD     D7,D7                           | shift guard bits left
        ADDX.L  D5,D5                           | shift mantissa low left
        ADDX.L  D4,D4                           | shift mantissa high left
FP68K_CONT_23:
        BPL.B   FP68K_LOOP_2                    | loop until MSB set
| FP68K_EXIT_10: round result per precision mode and check overflow
FP68K_EXIT_10:
        TST.L   D6                              | single precision mode?
        BMI     FP68K_OK_13                     | yes -> round to single
        BTST    #0x1E,D6                        | double precision mode?
        BNE     FP68K_OK_14                     | yes -> round to double
        SUBA.L  A3,A3                           | A3 = 0 (min extended exponent)
        BSR.B   FP68K_CONT_24                   | denormalize if exponent < min
        CLR.L   D1                              | rounding increment high = 0
        MOVEQ.L #0x1,D2                         | rounding increment low = 1
        BTST    #0x0,D5                         | test LSB for round-to-even
        BSR.B   FP68K_CONT_26                   | apply rounding
        MOVE    #0x7FFE,A3                      | max extended exponent
        BSR.B   FP68K_CONT_29                   | check for overflow
        BEQ.B   FP68K_DONE_4                    | no overflow -> done
        MOVE.L  A3,A4                           | set exponent to max
        MOVEQ.L #-0x1,D4                        | mantissa = all ones
        MOVE.L  D4,D5                           | (largest finite value)
FP68K_DONE_4:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_24: align mantissa by shifting right (A4-A3) bits
| Used to align operands before addition/subtraction
|
FP68K_CONT_24:
        MOVE.L  A3,D0                           | D0 = min exponent
        SUB.L   A4,D0                           | D0 = min - current (shift needed)
        BGT.B   FP68K_CONT_25                   | positive -> need to denormalize
        RTS                                     | no shift needed

| ----------------------------------------------------------
|
| FP68K_CONT_25
|
FP68K_CONT_25:
        BSet    #0x9,D6                         | set denormalized result flag
        MOVE.L  A3,A4                           | use min exponent
        BRA.B   FP68K_CONT_21                   | -> right-shift by D0 bits

| ----------------------------------------------------------
|
| FP68K_CONT_26: apply IEEE rounding based on guard/round/sticky bits
| D7 = guard bits, D6 bit 7 = sign; rounds per SANE mode
|
FP68K_CONT_26:
        SNE.B   D0                              | D0 = $FF if LSB was set (for even)
        TST     D7                              | any guard/round/sticky bits?
        BNE.B   FP68K_OK_10                     | yes -> rounding needed
        BCLR    #0x9,D6                         | clear denorm flag (exact result)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_10: result is inexact - apply rounding mode
|
FP68K_OK_10:
        BSet    #0xC,D6                         | set inexact exception flag
        BTST    #0x5,(A0)                       | rounding mode bit 5 set?
        BEQ.B   FP68K_NO_10                     | no -> round-to-nearest or up
        BTST    #0x6,(A0)                       | rounding mode bit 6 set?
        BEQ.B   FP68K_SKIP_5                    | mode=01: round toward zero -> skip
        RTS                                     | mode=11: round down (negative)

| ----------------------------------------------------------
|
| FP68K_SKIP_5: round toward +infinity - round up if positive
|
FP68K_SKIP_5:
        TST.B   D6                              | check sign
        BPL.B   FP68K_OK_11                     | positive -> round up
        RTS                                     | negative -> truncate

| ----------------------------------------------------------
|
| FP68K_NO_10: round-to-nearest or round up
|
FP68K_NO_10:
        BTst    #0x6,(A0)                       | rounding mode bit 6 set?
        BNE.B   FP68K_CONT_28                   | mode=10: round toward -inf ->
        CMPI    #-0x8000,D7                     | guard bit exactly 0.5?
        BCC.B   FP68K_CONT_27                   | >= 0.5 -> check for tie
        RTS                                     | < 0.5 -> truncate (round down)

| ----------------------------------------------------------
|
| FP68K_CONT_27: round-to-nearest tie-breaking (round to even)
|
FP68K_CONT_27:
        BHI.B   FP68K_OK_11                     | > 0.5 -> round up
        TST.B   D0                              | LSB was odd?
        BNE.B   FP68K_OK_11                     | yes -> round up (to even)
        RTS                                     | even -> truncate (already even)

| ----------------------------------------------------------
|
| FP68K_CONT_28: round toward -infinity - round up if negative
|
FP68K_CONT_28:
        TST.B   D6                              | check sign
        BMI.B   FP68K_OK_11                     | negative -> round up magnitude
        RTS                                     | positive -> truncate

| ----------------------------------------------------------
|
| FP68K_OK_11: perform the rounding increment
|
FP68K_OK_11:
        BSet    #0x7,0x1(A0)                    | set "rounded up" flag in state
        ADD.L   D2,D5                           | add rounding increment low
        ADDX.L  D1,D4                           | propagate carry to high
        BCC.B   FP68K_DONE_5                    | no mantissa overflow -> done
        ROXR.L  #0x1,D4                         | overflow: shift right
        ADDQ.L  #0x1,A4                         | bump exponent
FP68K_DONE_5:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_29: check for overflow - compare exponent A4 against max A3
| Returns Z=1 if no overflow, else sets overflow/infinity
|
FP68K_CONT_29:
        CMPA.L  A4,A3                           | result exponent > max?
        BLT.B   FP68K_OK_12                     | yes -> overflow
        CLR     D0                              | Z=1: no overflow
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_12: overflow - set infinity or max finite per rounding mode
|
FP68K_OK_12:
        BSet    #0xA,D6                         | set overflow exception
        BSET    #0xC,D6                         | set inexact exception
        MOVE    #0x7FFF,A4                      | exponent = infinity
        CLR.L   D4                              | mantissa = 0 (infinity default)
        MOVE.L  D4,D5                           | clear low mantissa
        MOVE.B  (A0),D1                         | get rounding mode
        ANDI.B  #0x60,D1                        | isolate mode bits
        BNE.B   FP68K_NO_11                     | not round-to-nearest -> check
        RTS                                     | round-to-nearest: return infinity

| ----------------------------------------------------------
|
| FP68K_NO_11: overflow with directed rounding - may saturate to max finite
|
FP68K_NO_11:
        CMPI.B  #0x60,D1                        | round toward zero?
        BNE.B   FP68K_NO_12                     | no -> check direction
        TST.B   D1                              | Z=0: return max finite (not inf)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_NO_12: overflow with round up/down - depends on sign
|
FP68K_NO_12:
        TST.B   D6                              | check result sign
        BMI.B   FP68K_CONT_30                   | negative -> check round down
        CMPI.B  #0x20,D1                        | round toward +inf? (Z=1 if yes)
        RTS                                     | +inf+positive: overflow to inf

| ----------------------------------------------------------
|
| FP68K_CONT_30: negative overflow - round toward -inf gives infinity
|
FP68K_CONT_30:
        CMPI.B  #0x40,D1                        | round toward -inf? (Z=1 if yes)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_13: round to single precision (24-bit mantissa)
|
FP68K_OK_13:
        MOVE    #0x3F81,A3                      | min single exponent (rebiased)
        BSR     FP68K_CONT_24                   | denormalize if needed
        TST.L   D5                              | any bits in low mantissa?
        SNE.B   D0                              | D0 = sticky bits from D5
        OR.B    D0,D7                           | merge into guard word
        ADD.B   D4,D4                           | shift out guard bit from D4
        ROXR    #0x1,D7                         | guard bit into D7 MSB
        OR.B    D4,D7                           | merge remaining low bits
        CLR.L   D5                              | clear low mantissa (single=32-bit)
        CLR.B   D4                              | clear low byte of mantissa high
        MOVE.L  #0x100,D1                       | rounding increment = bit 8
        CLR.L   D2                              | high increment = 0
        BTST    #0x8,D4                         | test LSB for round-to-even
        BSR     FP68K_CONT_26                   | apply rounding
        MOVE    #0x407E,A3                      | max single exponent (rebiased)
        BSR.B   FP68K_CONT_29                   | check overflow
        BEQ.B   FP68K_DONE_6                    | no overflow -> done
        MOVE.L  A3,A4                           | set exponent to max
        MOVEQ.L #-0x1,D4                        | mantissa = $FFFFFF00
        CLR.B   D4                              | (max single mantissa)
FP68K_DONE_6:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_14: round to double precision (53-bit mantissa)
|
FP68K_OK_14:
        MOVE    #0x3C01,A3                      | min double exponent (rebiased)
        BSR     FP68K_CONT_24                   | denormalize if needed
        MOVE    #0x7FF,D0                       | mask for low 11 bits
        AND     D5,D0                           | extract bits to become guard
        ANDI    #-0x800,D5                      | truncate mantissa to 53 bits
        LSL     #0x5,D0                         | position guard bits
        LSR     #0x1,D7                         | make room for guard bit
        BCC.B   FP68K_SKIP_6                    | no bit shifted out -> skip
        BSET    #0x0,D7                         | preserve shifted-out bit
FP68K_SKIP_6:
        OR      D0,D7                           | merge guard bits into D7
        CLR.L   D1                              | rounding increment high = 0
        MOVE.L  #0x800,D2                       | rounding increment = bit 11
        BTST    #0xB,D5                         | test LSB for round-to-even
        BSR     FP68K_CONT_26                   | apply rounding
        MOVE    #0x43FE,A3                      | max double exponent (rebiased)
        BSR     FP68K_CONT_29                   | check overflow
        BEQ.B   FP68K_DONE_7                    | no overflow -> done
        MOVE.L  A3,A4                           | set exponent to max
        MOVEQ.L #-0x1,D4                        | mantissa high = all ones
        MOVE.L  #0xFFFFF800,D5                  | mantissa low = max double bits
FP68K_DONE_7:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_31: pack result into destination format
| D0 bits 1-3 = format code, dispatches via FP68K_CONT_32
|
FP68K_CONT_31:
        ANDI    #0xE,D0                         | mask format * 2 for table index
        MOVE    FP68K_CONT_32(PC,D0.W),D0       | get handler offset
        MOVE.L  0xA(A6),A3                      | A3 = dest operand ptr
        MOVE    A4,D3                           | D3 = result exponent
        CMPI    #0x7FFF,D3                      | is NaN or infinity?
        JMP     FP68K_CONT_31(PC,D0.W)          | dispatch to format packer

| Jump Table
FP68K_CONT_32:
  .byte  0x00,0x32,0x00,0x86,0x00,0x60
  .byte 0x00,0x00,0x00,0x24,0x00,0x28
  .byte 0x00,0x2C
| FP68K_CONT_33: pack to 16-bit integer
FP68K_CONT_33:
        MOVE    D5,(A3)                         | store 16-bit integer result
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_34: pack to 32-bit long integer
|
FP68K_CONT_34:
        MOVE.L  D5,(A3)                         | store 32-bit long integer result
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_35: pack to 64-bit comp (integer)
|
FP68K_CONT_35:
        MOVE.L  D4,(A3)+                        | store comp high 32 bits
        MOVE.L  D5,(A3)                         | store comp low 32 bits
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_36: pack to extended (80-bit) - denormalize if needed
|
FP68K_CONT_36:
        BTst    #0x9,D6                         | denormalized result?
        BEQ.B   FP68K_NO_13                     | no -> store directly
        TST     D3                              | exponent zero?
        BEQ.B   FP68K_NO_13                     | yes -> already denorm format
        TST.L   D4                              | mantissa high nonzero?
        BNE.B   FP68K_OK_15                     | yes -> renormalize
        TST.L   D5                              | mantissa low nonzero?
        BNE.B   FP68K_LOOP_3                    | yes -> renormalize
        CLR.L   D3                              | both zero -> true zero exponent
        BRA.B   FP68K_NO_13                     | -> store

| ----------------------------------------------------------
|
| FP68K_LOOP_3
|
FP68K_LOOP_3:
        SUBQ.W  #0x1,D3                         | decrement exponent
        ADD.L   D5,D5                           | shift mantissa left
        ADDX.L  D4,D4                           | propagate carry
FP68K_OK_15:
        BPL.B   FP68K_LOOP_3                    | loop until MSB set
FP68K_NO_13:
        TST.B   D6                              | check result sign
        BPL.B   FP68K_SKIP_7                    | positive -> skip
        ADDI    #-0x8000,D3                     | set sign bit in exponent word
FP68K_SKIP_7:
        MOVE    D3,(A3)+                        | store exponent+sign word
        MOVE.L  D4,(A3)+                        | store mantissa high
        MOVE.L  D5,(A3)                         | store mantissa low
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_37: pack to IEEE single (32-bit) - encode sign/exp/mantissa
|
FP68K_CONT_37:
        BNE.B   FP68K_NO_14                     | not NaN/Inf -> normal pack
        MOVE    #0x4080,D3                      | infinity: single exp = $FF << 1
        BRA.B   FP68K_NO_15                     | -> encode

| ----------------------------------------------------------
|
| FP68K_NO_14: pack normal single - adjust exponent
|
FP68K_NO_14:
        TST     D3                              | exponent zero (denorm)?
        BNE.B   FP68K_NO_15                     | no -> normal
        MOVE    #0x3F81,D3                      | force min single exponent
FP68K_NO_15:
        SUBI    #0x3F80,D3                      | remove extended bias, add single
        ADD.L   D4,D4                           | shift out implicit integer bit
        BCS.B   FP68K_SKIP_8                    | had integer bit -> skip
        SUBQ.W  #0x1,D3                         | no integer bit: adjust exponent
FP68K_SKIP_8:
        OR      D3,D4                           | merge exponent into mantissa
        ROR.L   #0x8,D4                         | position exponent field
        ADD.B   D6,D6                           | shift sign into carry
        ROXR.L  #0x1,D4                         | insert sign bit
        MOVE.L  D4,(A3)                         | store 32-bit single result
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_38: pack to IEEE double (64-bit) - encode sign/exp/mantissa
|
FP68K_CONT_38:
        BNE.B   FP68K_NO_16                     | not NaN/Inf -> normal pack
        MOVE    #0x4400,D3                      | infinity: double exp = $7FF << 1
        BRA.B   FP68K_NO_17                     | -> encode

| ----------------------------------------------------------
|
| FP68K_NO_16: pack normal double - adjust exponent
|
FP68K_NO_16:
        TST     D3                              | exponent zero (denorm)?
        BNE.B   FP68K_NO_17                     | no -> normal
        MOVE    #0x3C01,D3                      | force min double exponent
FP68K_NO_17:
        SUBI    #0x3C00,D3                      | remove extended bias, add double
        TST.L   D4                              | implicit integer bit set?
        BMI.B   FP68K_SKIP_9                    | yes -> skip adjust
        SUBQ.W  #0x1,D3                         | no integer bit: adjust exponent
FP68K_SKIP_9:
        MOVE.L  #0x7FF,D0                       | mask for low 11 bits
        AND.L   D4,D0                           | extract bits to merge into D5
        OR.L    D0,D5                           | combine with low mantissa
        ROR.L   #0x8,D5                         | position low word
        ROR.L   #0x3,D5                         | finish positioning
        ANDI    #-0x800,D4                      | mask out bits moved to D5
        ADD.L   D4,D4                           | shift out implicit integer bit
        OR      D3,D4                           | merge exponent into high word
        ROR.L   #0x8,D4                         | position high word
        ROR.L   #0x3,D4                         | finish positioning
        ADD.B   D6,D6                           | shift sign into carry
        ROXR.L  #0x1,D4                         | insert sign bit
        MOVE.L  D4,(A3)+                        | store double high word
        MOVE.L  D5,(A3)                         | store double low word
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_39: FP subtract - negate source sign then fall into add
|
FP68K_CONT_39:
        EORI.B  #0xA0,D6                        | negate source: flip sign+xor flags
FP68K_CONT_40:
        MOVE    FP68K_CONT_41(PC,D3.W),D3       | get class-dispatch offset
        JMP     FP68K_CONT_40(PC,D3.W)          | dispatch by operand class pair

| Jump Table
FP68K_CONT_41:
  .byte  0x00,0x1A,0x00,0x80,0xFD,0xB8
  .byte 0x00,0x88,0x00,0x66,0xFD,0xB8
  .byte 0xFD,0xB0,0xFD,0xB0,0x00,0x8C
| FP68K_CONT_42: add core - align exponents and add/subtract mantissas
FP68K_CONT_42:
        MOVE.L  D4,D3                           | D3 = source mantissa high
        MOVE.L  A1,D4                           | D4 = dest mantissa high
        EXG     D5,A2                           | swap mantissa low halves
        MOVE    A4,D0                           | D0 = source exponent
        SUB     A3,D0                           | D0 = exponent difference
        BEQ.B   FP68K_CONT_44                   | same exponent, add directly ->
        BGT.B   FP68K_CONT_43                   | source > dest, shift dest ->
        EXG     D5,A2                           | swap so larger-exp is in D4:D5
        EXG     D4,D3                           | swap mantissa high halves
        NEG     D0                              | negate shift count
        MOVE.L  A3,A4                           | use larger exponent as result
        ADD.B   D6,D6                           | swap sign sense
        ASR.B   #0x1,D6                         | restore sign with new sense
FP68K_CONT_43:
        BSR     FP68K_CONT_21                   | right-shift smaller operand by D0
FP68K_CONT_44:
        BTst    #0x5,D6                         | opposite signs?
        BNE.B   FP68K_OK_16                     | yes, subtract ->
| same signs: add mantissas
        ADD.L   A2,D5                           | add low mantissa halves
        ADDX.L  D3,D4                           | add high with carry
        BCC.B   FP68K_NO_18                     | no overflow ->
        ROXR.L  #0x1,D4                         | overflow: shift right and increment exp
        ROXR.L  #0x1,D5                         | propagate through low
        ROXR    #0x1,D7                         | shift into guard bits
        ADDQ.L  #0x1,A4                         | bump result exponent
FP68K_NO_18:
        BRA     FP68K_EXIT_10                   | -> round and pack

| ----------------------------------------------------------
|
| FP68K_OK_16: subtraction path - negate and subtract mantissas
|
FP68K_OK_16:
        NOT.B   D6                              | tentatively flip sign for subtract
        SUB.L   A2,D5                           | subtract low mantissa halves
        SUBX.L  D3,D4                           | subtract high with borrow
        BEQ.B   FP68K_EMPTY_5                   | high zero -> check for cancellation
        BCC.B   FP68K_CONT_45                   | result positive -> normalize
        NEG     D7                              | negate guard bits
        NEGX.L  D5                              | negate result (was negative)
        NEGX.L  D4                              | negate high mantissa
        NOT.B   D6                              | restore original sign (flip back)
FP68K_CONT_45:
        BRA     FP68K_OK_9                      | -> normalize result

| ----------------------------------------------------------
|
| FP68K_CONT_46: add special case - both operands zero, pick sign per IEEE
|
FP68K_CONT_46:
        BTst    #0x5,D6                         | opposite signs?
        BEQ.B   FP68K_EMPTY_6                   | no, same sign -> keep sign
FP68K_EMPTY_5:
        SUBA.L  A4,A4                           | result exponent = 0 (zero)
        CLR.B   D6                              | default: positive zero
        BTST    #0x6,(A0)                       | rounding toward -inf?
        BEQ.B   FP68K_EMPTY_6                   | no -> positive zero
        BTST    #0x5,(A0)                       | round toward zero?
        BNE.B   FP68K_EMPTY_6                   | yes -> positive zero
        NOT.B   D6                              | round toward -inf: negative zero
FP68K_EMPTY_6:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_47: add - infinity + finite = infinity (propagate infinity)
|
FP68K_CONT_47:
        MOVE.L  A2,D5                           | result = source mantissa low
        MOVE.L  A1,D4                           | result = source mantissa high
        MOVE.L  A3,A4                           | result = source exponent
        ADD.B   D6,D6                           | use source sign
FP68K_CONT_48:
        BRA     FP68K_EXIT_10                   | -> round and pack

| ----------------------------------------------------------
|
| FP68K_CONT_49: add - inf + inf; same sign = inf, opposite = invalid NaN
|
FP68K_CONT_49:
        BTst    #0x5,D6                         | inf + inf: same signs?
        BNE.B   FP68K_CONT_50                   | opposite signs -> invalid
        RTS                                     | same signs -> return infinity

| ----------------------------------------------------------
|
| FP68K_CONT_50: inf + (-inf) = invalid - generate NaN with payload 2
|
FP68K_CONT_50:
        MOVEQ.L #0x2,D0                         | invalid NaN payload = 2 (inf-inf)
        BRA     FP68K_OK_3                      | -> construct NaN result

| ----------------------------------------------------------
|
| FP68K_CONT_51: FP multiply - dispatch by operand class combination
|
FP68K_CONT_51:
        ROL.B   #0x2,D6                         | combine signs via XOR (A*B sign)
        MOVEQ.L #0x8,D0                         | invalid NaN payload = 8 (0*inf)
        MOVE    FP68K_CONT_52(PC,D3.W),D3       | get class-dispatch offset
        JMP     FP68K_CONT_51(PC,D3.W)          | dispatch by operand class pair

| Jump Table
FP68K_CONT_52:
  .byte  0x00,0x1E,0xFD,0x1E,0xFD,0x1E
  .byte 0xFD,0x18,0xFD,0x1E,0xFC,0x70
  .byte 0xFD,0x18,0xFC,0x70,0xFD,0x1E
| FP68K_CONT_53: multiply core - 64x64 bit multiply using four 32x32 partial products
FP68K_CONT_53:
        ADDA.L  A3,A4                           | result exponent = exp_a + exp_b - bias
        SUBA    #0x3FFE,A4                      | subtract extended bias - 1
        MOVEM.L D5-D6/A0,-(SP)                  | save src_lo/flags/state ptr
        MOVE.L  D4,A3                           | A3 = source mantissa high
        CLR.L   D4                              | clear product accumulator high
        MOVE.L  D4,D5                           | clear product accumulator low
        MOVE.L  D4,A0                           | clear overflow accumulator
        MOVE.L  (SP),D1                         | D1 = source mantissa low
        BNE.B   FP68K_CONT_54                   | nonzero -> do full multiply
        MOVE.L  A2,D0                           | D0 = dest mantissa low
        BEQ.B   FP68K_SKIP_11                   | both low zero -> skip partials
        BRA.B   FP68K_SKIP_10                   | -> skip first partial product

| ----------------------------------------------------------
|
| FP68K_CONT_54
|
FP68K_CONT_54:
        MOVE.L  A2,D0                           | D0 = dest mantissa low
        BSR.B   FP68K_CONT_55                   | partial product: src_lo * dst_lo
        TST.L   D5                              | any overflow bits?
        SNE.B   D7                              | set sticky if nonzero
        MOVE.L  D4,D5                           | shift accumulator down
        CLR.L   D4                              | clear high accumulator
        MOVE.L  (SP),D1                         | D1 = source mantissa low
        MOVE.L  A1,D0                           | D0 = dest mantissa high
        BSR.B   FP68K_CONT_55                   | partial product: src_lo * dst_hi
FP68K_SKIP_10:
        MOVE.L  A3,D1                           | D1 = source mantissa high
        MOVE.L  A2,D0                           | D0 = dest mantissa low
        BSR.B   FP68K_CONT_55                   | partial product: src_hi * dst_lo
        TST     D5                              | low bits of partial result?
        SNE.B   D0                              | set sticky if nonzero
        OR.B    D0,D7                           | merge sticky bits
        SWAP    D5                              | get high word of low accumulator
        OR      D5,D7                           | merge into guard bits
        MOVE.L  D4,D5                           | shift accumulator down
        MOVE.L  A0,D4                           | get overflow word
FP68K_SKIP_11:
        MOVE.L  A3,D1                           | D1 = source mantissa high
        MOVE.L  A1,D0                           | D0 = dest mantissa high
        BSR.B   FP68K_CONT_55                   | partial product: src_hi * dst_hi
        MOVEM.L (SP)+,D0/D6/A0                  | restore saved regs
        BRA     FP68K_OK_9                      | -> normalize result

| ----------------------------------------------------------
|
| FP68K_CONT_55: 32x32->64 unsigned multiply, accumulating into D4:D5
| D0 * D1 -> added to D4:D5:A0 (128-bit running total)
| Uses four 16x16 partial products via MULU
|
FP68K_CONT_55:
        MOVE    D1,D2                           | D2 = D1.lo (multiplicand low)
        MOVE    D1,D3                           | D3 = D1.lo (for cross product)
        MULU    D0,D2                           | D2 = D0.lo * D1.lo
        MOVE    D0,D6                           | D6 = D0.lo
        SWAP    D0                              | D0 = D0.hi
        SWAP    D1                              | D1 = D1.hi
        MULU    D1,D6                           | D6 = D0.lo * D1.hi
        MULU    D0,D3                           | D3 = D0.hi * D1.lo
        MULU    D0,D1                           | D1 = D0.hi * D1.hi
        SWAP    D2                              | D2.hi = low product high word
        CLR.L   D0                              | clear for carry propagation
        MOVE    D2,D0                           | D0 = carry from low product
        ADD.L   D0,D3                           | add carry to cross product
        ADD.L   D6,D3                           | add other cross product
        MOVE    D3,D2                           | D2 = cross product low word
        SWAP    D2                              | position for 64-bit result
        CLR     D3                              | clear for carry capture
        ADDX    D3,D3                           | capture carry from cross add
        SWAP    D3                              | position carry
        ADD.L   D3,D1                           | add carry to high product
        ADD.L   D2,D5                           | accumulate into result low
        ADDX.L  D1,D4                           | accumulate into result high
        BCC.B   FP68K_DONE_8                    | no overflow -> done
        ADDQ.W  #0x1,A0                         | count overflow
FP68K_DONE_8:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_56: FP divide - dispatch by operand class combination
|
FP68K_CONT_56:
        ROL.B   #0x2,D6                         | combine signs via XOR (A/B sign)
        MOVEQ.L #0x4,D0                         | invalid NaN payload = 4 (0/0)
        MOVE    FP68K_CONT_57(PC,D3.W),D3       | get class-dispatch offset
        JMP     FP68K_CONT_56(PC,D3.W)          | dispatch by operand class pair

| Jump Table
FP68K_CONT_57:
  .byte  0x00,0x34,0x00,0x1E,0x00,0x2C
  .byte 0xFC,0x78,0xFB,0xD0,0xFC,0x78
  .byte 0xFC,0x78,0xFC,0x78,0xFB,0xD0
| FP68K_CONT_58: multiply/divide - result is infinity (overflow)
FP68K_CONT_58:
        BSet    #0xB,D6                         | set divide-by-zero exception
        MOVE    #0x7FFF,A4                      | exponent = infinity
        CLR.L   D4                              | mantissa = 0 (infinity)
        MOVE.L  D4,D5                           | clear low mantissa
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_59: multiply/divide - result is zero (underflow)
|
FP68K_CONT_59:
        SUBA.L  A4,A4                           | exponent = 0
        MOVE.L  A4,D4                           | mantissa = 0 (zero result)
        MOVE.L  D4,D5                           | clear low mantissa
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_60
|
| FP68K_CONT_60: divide core - restoring division, 64 quotient bits
FP68K_CONT_60:
        exg     A3,A4                           | swap exponents for subtraction
        SUBA.L  A3,A4                           | A4 = exp_dst - exp_src
        ADDA    #0x3FFF,A4                      | add extended bias
        MOVEQ.L #0x41,D0                        | 65 iterations for extended
        TST.L   D6                              | single precision mode?
        BPL.B   FP68K_NO_19                     | no -> 65 iterations
        MOVEQ.L #0x21,D0                        | 33 iterations for single
FP68K_NO_19:
        CMP.L   A1,D4                           | compare dividend vs divisor high
        BNE.B   FP68K_NO_20                     | not equal -> check order
        CMP.L   A2,D5                           | compare low halves
FP68K_NO_20:
        BLS.B   FP68K_OK_17                     | dividend <= divisor -> ok
        ADDQ.W  #0x1,D0                         | need one extra iteration
        SUBQ.L  #0x1,A4                         | adjust exponent accordingly
FP68K_OK_17:
        MOVE.L  A1,D1                           | D1 = dividend high (dest mant hi)
        MOVE.L  A2,D2                           | D2 = dividend low (dest mant lo)
        MOVE.L  D4,D3                           | D3 = divisor high (src mant hi)
        MOVE.L  D5,A2                           | A2 = divisor low (src mant lo)
        BSR.B   FP68K_LOOP_4                    | perform division loop
        TST.L   D6                              | single precision mode?
        BPL.B   FP68K_NO_21                     | no -> result in D4:D5
        MOVE.L  D5,D4                           | single: quotient in low word
        CLR.L   D5                              | clear low mantissa
FP68K_NO_21:
        MOVE    #0x10,CCR                       | set X flag for first shift
        ROXR.L  #0x1,D4                         | shift quotient right with guard
        ROXR.L  #0x1,D5                         | propagate through low
        ROXR    #0x1,D7                         | shift into guard bits
        OR.L    D2,D1                           | any remainder bits?
        SNE.B   D7                              | set sticky if remainder nonzero
        BRA     FP68K_EXIT_10                   | -> round and pack

| ----------------------------------------------------------
|
| FP68K_LOOP_4: division loop - D0 iterations of shift-and-subtract
| Divides D1:D2 by D3:A2, quotient in D4:D5
|
FP68K_LOOP_4:
        CLR.L   D4                              | clear quotient high
        MOVE.L  D4,D5                           | clear quotient low
        BRA.B   FP68K_CONT_61                   | -> first comparison

| ----------------------------------------------------------
|
| FP68K_DONE_9: division loop iteration - shift and conditionally subtract
|
FP68K_DONE_9:
        ADD.L   D5,D5                           | shift quotient left
        ADDX.L  D4,D4                           | propagate carry
        ADD.L   D2,D2                           | shift dividend left
        ADDX.L  D1,D1                           | propagate carry
        BCS.B   FP68K_CONT_62                   | overflow means dividend >= divisor
FP68K_CONT_61:
        CMP.L   D3,D1                           | compare dividend vs divisor high
        BNE.B   FP68K_NO_22                     | not equal -> check result
        CMP.L   A2,D2                           | compare low halves
FP68K_NO_22:
        BCS.B   FP68K_SKIP_12                   | dividend < divisor -> skip sub
FP68K_CONT_62:
        ADDQ.B  #0x1,D5                         | set quotient bit
        SUB.L   A2,D2                           | subtract divisor low from dividend
        SUBX.L  D3,D1                           | subtract divisor high with borrow
FP68K_SKIP_12:
        SUBQ.W  #0x1,D0                         | decrement iteration count
        BNE.B   FP68K_DONE_9                    | loop until done
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_63: FP compare - dispatch by operand class combination
|
FP68K_CONT_63:
        CLR     0x6(SP)                         | clear quotient word (for remainder)
        ADD.B   D6,D6                           | extract sign to carry
        MOVEQ.L #0x9,D0                         | invalid NaN payload = 9
        ANDI.L  #0x3FFFFFFF,D6                  | clear precision mode bits
        MOVE    FP68K_CONT_64(PC,D3.W),D3       | get class-dispatch offset
        JMP     FP68K_CONT_63(PC,D3.W)          | dispatch by operand class pair

| Jump Table
FP68K_CONT_64:
  .byte  0x00,0x28,0xFB,0x38,0x00,0x30
  .byte 0xFB,0xE0,0xFB,0x38,0xFB,0xE0
  .byte 0xFB,0x38,0xFB,0x38,0xFB,0x38
| FP68K_CONT_65: FP remainder core - iterative shift-subtract
FP68K_CONT_65:
        MOVE.L  A3,D0                           | D0 = dest exponent
        ADDQ.L  #0x2,D0                         | add 2 for iteration count
        SUB.L   A4,D0                           | D0 = iterations needed
        BGT.B   FP68K_CONT_67                   | divisor < dividend, iterate ->
| FP68K_CONT_66: |dividend| < |divisor|, remainder = dividend
FP68K_CONT_66:
        MOVE.L  A1,D4                           | result = dest mantissa high
        MOVE.L  A2,D5                           | result = dest mantissa low
        MOVE.L  A3,A4                           | result = dest exponent
        BRA.B   FP68K_CONT_69                   | -> normalize remainder

| ----------------------------------------------------------
|
| FP68K_CONT_67
|
FP68K_CONT_67:
        SUBQ.L  #0x1,A4                         | adjust exponent for extra shift
        MOVE.L  A1,D1                           | D1 = dividend high
        MOVE.L  A2,D2                           | D2 = dividend low
        MOVE.L  D4,D3                           | D3 = divisor high
        MOVE.L  D5,A2                           | A2 = divisor low
        BSR.B   FP68K_LOOP_4                    | divide: quotient in D4:D5
        BTST    #0x0,D5                         | quotient odd?
        BEQ.B   FP68K_OK_18                     | even -> remainder is final
        TST.L   D1                              | remainder high zero?
        BNE.B   FP68K_CONT_68                   | nonzero -> adjust for IEEE rem
        TST.L   D2                              | remainder low zero?
        BNE.B   FP68K_CONT_68                   | nonzero -> adjust
        BTST    #0x1,D5                         | quotient bit 1 set? (round to even)
        BEQ.B   FP68K_SKIP_13                   | no -> don't adjust
FP68K_CONT_68:
        BChg    #0x7,D6                         | flip result sign
        ADDQ.W  #0x2,D5                         | round quotient to even
FP68K_SKIP_13:
        exg     D2,A2                           | swap remainder/divisor low
        EXG     D1,D3                           | swap remainder/divisor high
        SUB.L   A2,D2                           | remainder = divisor - remainder
        SUBX.L  D3,D1                           | borrow propagation
FP68K_OK_18:
        LSR.B   #0x1,D5                         | extract low quotient bits
        BTST    #0x6,D6                         | original signs differed?
        BEQ.B   FP68K_NO_23                     | no -> keep quotient sign
        NEG.B   D5                              | negate quotient bits
FP68K_NO_23:
        EXT     D5                              | sign-extend quotient byte
        MOVE    D5,0x6(SP)                      | store quotient bits on stack
        MOVE.L  D1,D4                           | remainder high -> result
        MOVE.L  D2,D5                           | remainder low -> result
FP68K_CONT_69:
        BRA     FP68K_CONT_22                   | -> normalize remainder

| ----------------------------------------------------------
|
| FP68K_CONT_70: FP convert - format conversion dispatch
|
FP68K_CONT_70:
        MOVE    FP68K_CONT_72(PC,D3.W),D3       | get class-dispatch offset
        JSR     FP68K_CONT_70(PC,D3.W)          | dispatch conversion handler
FP68K_CONT_71:
        CMPI    #0x2,D0                         | result = unordered?
        BNE.B   FP68K_SKIP_14                   | no -> store condition
        BTST    #0x11,D6                        | signaling compare mode?
        BEQ.B   FP68K_SKIP_14                   | no -> skip
        BSET    #0x8,D6                         | flag invalid (unordered + signal)
FP68K_SKIP_14:
        MOVE    D0,D7                           | save condition code
        SWAP    D7                              | to high word for return
        RTS                                     | return to caller

| Jump Table
FP68K_CONT_72:
  .byte  0x00,0x48,0x00,0x30,0x00,0x34
  .byte 0x00,0x34,0x00,0x44,0x00,0x34
  .byte 0x00,0x30,0x00,0x30,0x00,0x3E
| FP68K_CONT_73: compare - ordered compare, swap sign sense
FP68K_CONT_73:
        ADD.B   D6,D6                           | shift dest sign to bit 7
        NOT.B   D6                              | invert for opposite ordering
| FP68K_OK_19: compare returns 0 (less) or $19 (greater)
FP68K_OK_19:
        MOVEQ.L #0x0,D0                         | assume less than
        TST.B   D6                              | check combined sign
        BMI.B   FP68K_CONT_74                   | negative = less ->
        MOVEQ.L #0x19,D0                        | positive = greater
FP68K_CONT_74:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_75: compare - source is zero (equal if dest zero, else ordered)
|
FP68K_CONT_75:
        BTst    #0x5,D6                         | dest has different sign?
        BNE.B   FP68K_OK_19                     | yes -> ordered by sign
FP68K_CONT_76:
        MOVEQ.L #0x4,D0                         | result = equal
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_77: compare - both normal, compare magnitudes
|
FP68K_CONT_77:
        BTst    #0x5,D6                         | different signs?
        BNE.B   FP68K_OK_19                     | yes -> ordered by sign
        CMPA.L  A4,A3                           | compare exponents
        BGT.B   FP68K_CONT_78                   | dest > src -> swap sense
        BLT.B   FP68K_CONT_79                   | dest < src -> src greater
        CMPA.L  D4,A1                           | same exp: compare mantissa high
        BHI.B   FP68K_CONT_78                   | dest > src -> swap
        BCS.B   FP68K_CONT_79                   | dest < src -> ordered
        CMPA.L  D5,A2                           | compare mantissa low
        BEQ.B   FP68K_CONT_76                   | exactly equal
        BCS.B   FP68K_CONT_79                   | dest < src
FP68K_CONT_78:
        NOT.B   D6                              | flip ordering sense
FP68K_CONT_79:
        MOVEQ.L #0x19,D0                        | assume greater-than
        TST.B   D6                              | check sign
        BPL.B   FP68K_CONT_80                   | positive -> greater
        MOVEQ.L #0x0,D0                         | negative -> less-than
FP68K_CONT_80:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_NO_24: FP square root entry - dispatch by operand class
|
FP68K_NO_24:
        TST     D3                              | class = normal (zero)?
        BEQ     FP68K_EXIT_10                   | yes -> round and return
        RTS                                     | NaN/Inf/zero: return as-is

| ----------------------------------------------------------
|
| FP68K_CONT_81: FP round-to-integer (rint) - round using current SANE mode
|
FP68K_CONT_81:
        TST     D3                              | class = normal?
        BEQ.B   FP68K_OK_20                     | yes -> round to integer
        RTS                                     | NaN/Inf/zero: return as-is

| ----------------------------------------------------------
|
| FP68K_OK_20: rint - round using current SANE rounding mode
|
FP68K_OK_20:
        BSR.B   FP68K_CONT_84                   | shift out fractional bits
        MOVE    (A0),A2                         | save current environment
        BRA.B   FP68K_CONT_83                   | -> round and restore

| ----------------------------------------------------------
|
| FP68K_CONT_82: FP truncate-to-integer (tint) - round toward zero
|
FP68K_CONT_82:
        TST     D3                              | class = normal?
        BEQ.B   FP68K_OK_21                     | yes -> truncate to integer
        RTS                                     | NaN/Inf/zero: return as-is

| ----------------------------------------------------------
|
| FP68K_OK_21: tint - force round-toward-zero mode, then round
|
FP68K_OK_21:
        BSR.B   FP68K_CONT_84                   | shift out fractional bits
        MOVE    (A0),A2                         | save current environment
        BSET    #0x6,(A0)                       | set round mode bit 6
        BSET    #0x5,(A0)                       | set round mode bit 5 = toward zero
FP68K_CONT_83:
        BSR     FP68K_EXIT_10                   | round per mode
        MOVE    A2,(A0)                         | restore original environment
        TST.L   D4                              | result normalized?
        BMI.B   FP68K_DONE_10                   | yes -> done
        BNE.B   FP68K_LOOP_5                    | nonzero -> renormalize
        TST.L   D5                              | low mantissa nonzero?
        BNE.B   FP68K_LOOP_5                    | yes -> renormalize
        SUBA.L  A4,A4                           | result is zero, clear exponent
        BRA.B   FP68K_DONE_10                   | -> done

| ----------------------------------------------------------
|
| FP68K_LOOP_5: renormalize after rint/tint rounding
|
FP68K_LOOP_5:
        SUBQ.L  #0x1,A4                         | decrement exponent
        ADD.L   D5,D5                           | shift mantissa left
        ADDX.L  D4,D4                           | propagate carry
        BPL.B   FP68K_LOOP_5                    | loop until MSB set
FP68K_DONE_10:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_84: compute precision limit for current format
| Returns D0 = max mantissa bits (24 for single, 53 for double, 64 for extended)
|
FP68K_CONT_84:
        TST.L   D6                              | single precision mode?
        BMI.B   FP68K_OK_22                     | yes -> 24 bits
        BTST    #0x1E,D6                        | double precision mode?
        BEQ.B   FP68K_NO_25                     | no -> extended (64 bits)
        MOVEQ.L #0x34,D0                        | double: 52 mantissa bits
        BRA     FP68K_CONT_85                   | -> compute shift

| ----------------------------------------------------------
|
| FP68K_OK_22: single precision - 23 mantissa bits
|
FP68K_OK_22:
        MOVEQ.L #0x17,D0                        | single: 23 mantissa bits
        BRA     FP68K_CONT_85                   | -> compute shift

| ----------------------------------------------------------
|
| FP68K_NO_25: extended precision - 63 mantissa bits
|
FP68K_NO_25:
        MOVEQ.L #0x3F,D0                        | extended: 63 mantissa bits
FP68K_CONT_85:
        ADDI    #0x3FFF,D0                      | add extended bias for comparison
        MOVE    D0,D1                           | D1 = max biased exponent
        SUB.L   A4,D0                           | D0 = bits to shift out
        BGT.B   FP68K_CONT_86                   | fractional bits exist -> shift
        RTS                                     | no fraction -> already integer

| ----------------------------------------------------------
|
| FP68K_CONT_86: shift out fractional bits into guard word
|
FP68K_CONT_86:
        MOVE    D1,A4                           | set exponent to integer limit
        BSR     FP68K_CONT_21                   | right-shift D0 bits
        MOVE    #0x0,CCR                        | clear X flag for rounding
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_87: FP convert-to-integer (comp/int/long) - pack mantissa
| Handles clamping to integer range and NaN/infinity cases
|
FP68K_CONT_87:
        BTst    #0x1A,D6                        | converting to integer type?
        BEQ.B   FP68K_NO_24                     | no -> normal convert path
        CMPI    #0x2,D3                         | source is NaN?
        BNE.B   FP68K_NO_26                     | no -> check infinity
        RTS                                     | NaN -> return NaN as integer

| ----------------------------------------------------------
|
| FP68K_NO_26: convert infinity to integer - clamp to max
|
FP68K_NO_26:
        CMPI    #0x4,D3                         | source is infinity?
        BNE.B   FP68K_NO_27                     | no -> normal value
        MOVEQ.L #-0x1,D4                        | D4 = $FFFFFFFF (max magnitude)
        BRA.B   FP68K_NO_28                     | -> clamp to integer range

| ----------------------------------------------------------
|
| FP68K_NO_27: convert normal value to integer - round and clamp
|
FP68K_NO_27:
        BSR.B   FP68K_NO_25                     | shift out fractional bits
        BLE.B   FP68K_NO_28                     | no fraction -> already integer
        CLR.L   D1                              | rounding increment high = 0
        MOVEQ.L #0x1,D2                         | rounding increment low = 1
        BTST    #0x0,D5                         | test LSB for round-to-even
        BSR     FP68K_CONT_26                   | apply rounding
FP68K_NO_28:
        MOVEQ.L #0x1,D1                         | prepare max positive value
        ROR.L   #0x1,D1                         | D1 = $80000000
        BTST    #0x18,D6                        | target is 16-bit integer?
        BNE.B   FP68K_OK_23                     | yes -> check 16-bit range
        BTST    #0x19,D6                        | target is 32-bit long?
        BNE.B   FP68K_OK_26                     | yes -> check 32-bit range
        SWAP    D1                              | D1 = $00008000 (16-bit max+1)
FP68K_OK_23:
        TST.L   D4                              | high mantissa nonzero?
        BNE.B   FP68K_OK_25                     | yes -> overflow
        CMP.L   D1,D5                           | value > max positive?
        BHI.B   FP68K_OK_25                     | yes -> overflow
        BCS.B   FP68K_OK_24                     | less -> in range
        TST.B   D6                              | exactly max: negative?
        BPL.B   FP68K_OK_25                     | positive -> overflow (max+1)
FP68K_OK_24:
        TST.B   D6                              | check sign for negation
        BPL.B   FP68K_DONE_11                   | positive -> done
        NEG.L   D5                              | negate low mantissa
        NEGX.L  D4                              | negate high mantissa
FP68K_DONE_11:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_25: integer overflow - return max value, flag invalid
|
FP68K_OK_25:
        MOVE.L  D1,D5                           | D5 = max magnitude for type
FP68K_CONT_88:
        BSet    #0x8,D6                         | flag invalid operation
        BCLR    #0xC,D6                         | clear inexact (invalid overrides)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_26: 64-bit comp range check
|
FP68K_OK_26:
        TST.L   D4                              | high word in range?
        BPL.B   FP68K_OK_24                     | yes -> negate if needed
        CLR.L   D5                              | overflow: clear low
        MOVE.L  D1,D4                           | D4 = $80000000 (comp NaN/max)
        BRA.B   FP68K_CONT_88                   | -> flag invalid

| ----------------------------------------------------------
|
| FP68K_CONT_89: FP square root core - non-restoring digit recurrence
| Uses iterative shift-subtract algorithm for 64-bit precision
|
FP68K_CONT_89:
        CMPI    #0x2,D3                         | operand is NaN?
        BNE.B   FP68K_NO_29                     | no -> check sign
        RTS                                     | NaN -> return NaN

| ----------------------------------------------------------
|
| FP68K_NO_29
|
FP68K_NO_29:
        MOVEQ.L #0x1,D0                         | invalid payload = 1 (sqrt neg)
        TST.B   D6                              | operand negative?
        BMI     FP68K_OK_3                      | yes -> invalid NaN
        CMPI    #0x4,D3                         | operand is infinity?
        BNE.B   FP68K_NO_30                     | no -> normal sqrt
        RTS                                     | sqrt(+inf) = +inf

| ----------------------------------------------------------
|
| FP68K_NO_30
|
FP68K_NO_30:
        MOVE    A4,D0                           | D0 = input exponent
        ASR     #0x1,D0                         | halve exponent for sqrt
        MOVE    SR,D1                           | save carry (odd exponent flag)
        BCC.B   FP68K_SKIP_15                   | even exponent -> skip adjust
        ADDQ.W  #0x1,D0                         | odd: round up halved exponent
FP68K_SKIP_15:
        ADDI    #0x1FFF,D0                      | add half-bias ($3FFF/2)
        MOVE    D0,A4                           | store result exponent
        MOVE.L  D6,A1                           | save flags
        MOVE.L  D7,A2                           | save guard bits
        MOVE.L  D5,D7                           | D7 = mantissa low (radicand lo)
        MOVE.L  D4,D6                           | D6 = mantissa high (radicand hi)
        CLR.L   D3                              | clear remainder accumulator
        MOVE.L  D3,D2                           | clear remainder high
        ADD.L   D7,D7                           | shift radicand left
        ADDX.L  D6,D6                           | propagate carry
        ADDX    D3,D3                           | into accumulator
        MOVE    D1,CCR                          | restore carry (odd exponent?)
        BCS.B   FP68K_CONT_90                   | odd -> already shifted once
        ADD.L   D7,D7                           | even: shift radicand again
        ADDX.L  D6,D6                           | propagate carry
        ADDX    D3,D3                           | into accumulator
FP68K_CONT_90:
        MOVE.L  D2,D0                           | D0 = 0 (root accumulator high)
        MOVE.L  D2,D4                           | D4 = 0 (root accumulator mid)
        MOVEQ.L #0x3,D5                         | D5 = initial root digit trial
        SUBQ.W  #0x1,D3                         | initial subtract from remainder
        MOVEQ.L #0x41,D1                        | 65 iterations
        MOVE    D1,A3                           | save counter in A3
        CLR.L   D1                              | clear overflow accumulator
| FP68K_LOOP_6: non-restoring sqrt loop - two bits of radicand per iteration
FP68K_LOOP_6:
        ADD.L   D7,D7                           | shift radicand left (bit 1)
        ADDX.L  D6,D6                           | propagate
        ADDX.L  D3,D3                           | into remainder
        ADDX.L  D2,D2                           | propagate
        ADDX    D1,D1                           | propagate
        ADD.L   D7,D7                           | shift radicand left (bit 2)
        ADDX.L  D6,D6                           | propagate
        ADDX.L  D3,D3                           | into remainder
        ADDX.L  D2,D2                           | propagate
        ADDX    D1,D1                           | propagate
        ADD.L   D5,D5                           | shift root left
        ADDX.L  D4,D4                           | propagate
        ADDX    D0,D0                           | propagate
        SUBQ.W  #0x1,D5                         | trial: root * 2 - 1
        SUB.L   D5,D3                           | subtract trial from remainder
        SUBX.L  D4,D2                           | propagate borrow
        SUBX    D0,D1                           | propagate borrow
        BCC.B   FP68K_OK_27                     | remainder >= 0 -> digit is 1
        ADD.L   D5,D3                           | restore remainder (undo subtract)
        ADDX.L  D4,D2                           | propagate
        ADDX    D0,D1                           | propagate
        BRA.B   FP68K_OK_28                     | -> digit is 0

| ----------------------------------------------------------
|
| FP68K_OK_27
|
FP68K_OK_27:
        ADDQ.W  #0x2,D5                         | root digit = 1 (add 2 to root)
FP68K_OK_28:
        exg     D0,A3                           | swap counter/accumulator
        SUBQ.W  #0x1,D0                         | decrement iteration count
        EXG     D0,A3                           | swap back
        BNE.B   FP68K_LOOP_6                    | loop until all bits computed
        MOVE.L  A1,D6                           | restore flags
        MOVE.L  A2,D7                           | restore guard bits
        OR.L    D2,D1                           | any remainder bits?
        OR.L    D3,D1                           | check all parts
        BNE.B   FP68K_CONT_91                   | nonzero remainder -> inexact
        SUBQ.W  #0x1,D5                         | exact: adjust root LSB
FP68K_CONT_91:
        MOVEQ.L #0x3,D1                         | shift root right 3 positions
FP68K_LOOP_7:
        LSR     #0x1,D0                         | shift root high right
        ROXR.L  #0x1,D4                         | propagate into root mid
        ROXR.L  #0x1,D5                         | propagate into root low
        ROXR    #0x1,D7                         | shift into guard bits
        SUBQ.W  #0x1,D1                         | decrement shift count
        BNE.B   FP68K_LOOP_7                    | loop 3 times
        BRA     FP68K_EXIT_10                   | -> round and pack

| ----------------------------------------------------------
|
| FP68K_CONT_92: FP logb - extract unbiased exponent as integer
| Returns exponent - $3FFF as extended-precision value
|
FP68K_CONT_92:
        CLR.B   D6                              | clear sign (logb always positive)
        CMPI    #0x2,D3                         | operand is NaN?
        BNE.B   FP68K_NO_31                     | no -> check infinity
        ORI     #0x880,D6                       | flag invalid + set exception
        MOVE    #0x7FFF,A4                      | return NaN
        CLR.L   D4                              | clear mantissa
        MOVE.L  D4,D5                           | clear low mantissa
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_NO_31: logb - check for infinity
|
FP68K_NO_31:
        CMPI    #0x4,D3                         | operand is infinity?
        BNE.B   FP68K_NO_32                     | no -> normal logb
        RTS                                     | logb(inf) = +inf

| ----------------------------------------------------------
|
| FP68K_NO_32: logb - extract unbiased exponent as extended value
|
FP68K_NO_32:
        CLR.L   D5                              | clear low mantissa
        SUBA    #0x3FFF,A4                      | remove bias -> unbiased exponent
        MOVE.L  A4,D4                           | D4 = unbiased exponent
        BPL.B   FP68K_SKIP_16                   | positive -> skip sign
        ORI.B   #0x80,D6                        | set negative sign
        NEG.L   D4                              | negate for absolute value
FP68K_SKIP_16:
        MOVE    #0x401E,A4                      | exponent = 30 + bias (integer)
        BRA     FP68K_CONT_22                   | -> normalize integer mantissa

| ----------------------------------------------------------
|
| FP68K_CONT_93: FP scalb - multiply by 2^n (add integer to exponent)
|
FP68K_CONT_93:
        TST     D3                              | class = normal?
        BEQ.B   FP68K_OK_29                     | yes -> add to exponent
        RTS                                     | NaN/Inf/zero: return as-is

| ----------------------------------------------------------
|
| FP68K_OK_29: scalb - add integer n to exponent (multiply by 2^n)
|
FP68K_OK_29:
        MOVE.L  0xE(A6),A3                      | A3 = ptr to integer n
        ADDA    (A3),A4                         | exponent += n
        BRA     FP68K_EXIT_10                   | -> round and pack

| ----------------------------------------------------------
|
| RETURNS_9: FP classify - return SANE class code
| Returns: -6=SNaN, -5=QNaN, -4=Inf, -3=Zero, -2=Normal, -1=Denormal
| Positive values for positive operand, negative for negative
|
RETURNS_9:
        MOVEQ.L #0x5,D0                         | start with class = SNaN (5)
        TST.L   D3                              | check class descriptor
        BMI.B   FP68K_CONT_94                   | denormal (negative D3) -> class 6
        BEQ.B   FP68K_NO_33                     | normal -> class 5 (not reached)
        SUBQ.W  #0x2,D0                         | D0 = 3 (zero class)
        CMPI    #0x4,D3                         | infinity?
        BEQ.B   FP68K_NO_33                     | yes -> class 3 (infinite)
FP68K_CONT_94:
        ADDQ.W  #0x1,D0                         | adjust class code
FP68K_NO_33:
        TST.B   D6                              | operand negative?
        BEQ.B   FP68K_NO_34                     | no -> positive class
        NEG     D0                              | negate for negative operand
FP68K_NO_34:
        MOVE.L  0xA(A6),A3                      | A3 = result ptr
        MOVE    D0,(A3)                         | store class code
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_95: FP environment operations - get/set flags, halt vector, etc.
| D7 indexes into FP68K_CONT_96 dispatch table
|
FP68K_CONT_95:
        MOVEM.L 0xA(A6),A1-A2                   | A1/A2 = operand pointers
        MOVE    FP68K_CONT_96(PC,D7.W),D7       | get handler offset
        JMP     FP68K_CONT_95(PC,D7.W)          | dispatch environment operation

| Jump Table
FP68K_CONT_96:
  .byte  0x00,0x2A,0x00,0x34,0x00,0x38
  .byte 0x00,0x3E,0x01,0xF2,0x05,0x5A
  .byte 0x00,0x44,0x00,0x4A,0x00,0x5E
  .byte 0x00,0x72,0x01,0xD8,0x00,0x2E
  .byte 0x01,0xE4,0x00,0x52
| FP68K_CONT_97: setEnv - load SANE environment word from (A1) into state
FP68K_CONT_97:
        MOVE    (A1),(A0)                       | load environment word from (A1)
        BRA.B   FP68K_EXIT_11                   | -> return

| ----------------------------------------------------------
|
| FP68K_CONT_98: getEnv - read SANE environment word into (A1)
|
FP68K_CONT_98:
        MOVE    (A0),(A1)                       | read environment to (A1)
        CLR     (A0)                            | clear exceptions (procExit)
        BRA.B   FP68K_EXIT_11                   | -> return

| ----------------------------------------------------------
|
| FP68K_CONT_99: getEnv2 - read environment word (alternate)
|
FP68K_CONT_99:
        MOVE    (A0),(A1)                       | read environment to (A1)
        BRA.B   FP68K_EXIT_11                   | -> return (no clear)

| ----------------------------------------------------------
|
| FP68K_CONT_100: setHaltVector - store halt handler address
|
FP68K_CONT_100:
        MOVE.L  (A1),0x2(A0)                    | store halt vector from (A1)
        BRA.B   FP68K_EXIT_11                   | -> return

| ----------------------------------------------------------
|
| FP68K_CONT_101: getHaltVector - read halt handler address
|
FP68K_CONT_101:
        MOVE.L  0x2(A0),(A1)                    | read halt vector to (A1)
        BRA.B   FP68K_EXIT_11                   | -> return

| ----------------------------------------------------------
|
| FP68K_CONT_102: setSign - toggle sign bit of operand at (A1)
|
FP68K_CONT_102:
        BChg    #0x7,(A1)                       | toggle sign bit of (A1)
        BRA.B   FP68K_EXIT_11                   | -> return

| ----------------------------------------------------------
|
| FP68K_CONT_103: clearSign - clear sign bit (make positive)
|
FP68K_CONT_103:
        BClr    #0x7,(A1)                       | clear sign bit (absolute value)
FP68K_EXIT_11:
        BRA     FP68K_EXIT_4                    | -> two-operand return

| ----------------------------------------------------------
|
| FP68K_CONT_104: testException - test specific SANE exception flag bit
|
FP68K_CONT_104:
        MOVE    (A1),D0                         | D0 = exception bit number
        BTST    D0,(A0)                         | test that bit in environment
        SNE.B   D0                              | D0 = $FF if set, $00 if clear
        NEG.B   D0                              | D0 = 1 if set, 0 if clear
        MOVE.B  D0,(A1)                         | store boolean result
        BRA.B   FP68K_EXIT_11                   | -> return

| ----------------------------------------------------------
|
| FP68K_CONT_105: copySign - copy sign from (A1) to (A2)
|
FP68K_CONT_105:
        BTst    #0x7,(A1)                       | source sign negative?
        BEQ.B   FP68K_NO_35                     | no -> clear dest sign
        BSET    #0x7,(A2)                       | copy negative sign to dest
        BRA.B   FP68K_EXIT_12                   | -> return

| ----------------------------------------------------------
|
| FP68K_NO_35: copySign - copy positive sign
|
FP68K_NO_35:
        BClr    #0x7,(A2)                       | clear dest sign (positive)
FP68K_EXIT_12:
        BRA     FP68K_EXIT_3                    | -> three-operand return

| ----------------------------------------------------------
|
| FP68K_CONT_106: nextAfter - return next representable FP value toward target
| Increments or decrements mantissa by 1 ULP in the appropriate direction
|
FP68K_CONT_106:
        SUBA    #0x16,SP                        | allocate 22 bytes temp space
        MOVE.L  A7,A4                           | A4 = temp buffer base
        MOVE    D6,D5                           | save selector
        ANDI    #0x3800,D5                      | isolate dest format bits
        ADDQ.W  #0x1,D6                         | adjust return type
        SWAP    D6                              | move to high word
        CLR     D6                              | clear low word
        MOVE.L  A2,-(SP)                        | push dest operand ptr
        PEA.L   0xA(A4)                         | push temp[10] (extended buffer)
        MOVEQ.L #0xE,D0                         | selector = convert
        OR      D5,D0                           | merge dest format
        MOVE    D0,-(SP)                        | push selector
        BSR     FP68K_EMPTY                     | convert dest to extended at temp[10]
        CLR.L   (A4)                            | zero temp[0..9] (extended zero)
        CLR.L   0x4(A4)                         | clear bytes 4-7
        CLR     0x8(A4)                         | clear bytes 8-9
        PEA.L   (A4)                            | push zero operand
        PEA.L   0xA(A4)                         | push dest extended
        MOVE    #0x8,-(SP)                      | selector = compare
        BSR     FP68K_EMPTY                     | compare dest vs zero
        SNE.B   D4                              | D4 = nonzero if dest != 0
        MOVE.L  A1,-(SP)                        | push source operand ptr
        PEA.L   (A4)                            | push temp (for result)
        MOVE    D0,-(SP)                        | push convert selector
        BSR     FP68K_EMPTY                     | convert source to extended
        PEA.L   (A4)                            | push source extended
        PEA.L   0xA(A4)                         | push dest extended
        MOVE    #0x8,-(SP)                      | selector = compare
        BSR     FP68K_EMPTY                     | compare source vs dest
        BVC.B   FP68K_NO_36                     | not unordered -> continue
        PEA.L   (A4)                            | push source (NaN)
        PEA.L   0xA(A4)                         | push dest
        MOVE    #0x4,-(SP)                      | selector = multiply (propagate NaN)
        BSR     FP68K_EMPTY                     | propagate NaN
        PEA.L   0xA(A4)                         | push result
        MOVE.L  A2,-(SP)                        | push original dest ptr
        MOVEQ.L #0x10,D0                        | selector = convert back
        OR      D5,D0                           | merge dest format
        MOVE    D0,-(SP)                        | push selector
        BSR     FP68K_EMPTY                     | convert NaN result to dest format
        BRA     FP68K_EXIT_13                   | -> cleanup and return

| ----------------------------------------------------------
|
| FP68K_NO_36
|
FP68K_NO_36:
        BEQ.B   FP68K_EXIT_13                   | source == dest -> return dest as-is
        BCC.B   FP68K_CONT_107                  | source > dest -> need to decrease
        BTST    #0x7,(A2)                       | dest negative?
        BEQ.B   FP68K_NO_37                     | no -> increment toward source
        BRA.B   FP68K_OK_31                     | yes -> decrement toward source

| ----------------------------------------------------------
|
| FP68K_CONT_107: source > dest - decrement if positive, increment if negative
|
FP68K_CONT_107:
        BTst    #0x7,(A2)                       | dest negative?
        BEQ.B   FP68K_OK_31                     | positive -> decrement magnitude
FP68K_NO_37:
        BTst    #0xC,D5                         | single format?
        BEQ.B   FP68K_NO_38                     | no -> check double
        ADDQ.L  #0x1,(A2)                       | increment single by 1 ULP
        BRA.B   FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_NO_38
|
FP68K_NO_38:
        BTst    #0xB,D5                         | double format?
        BEQ.B   FP68K_NO_39                     | no -> extended
        ADDQ.L  #0x1,0x4(A2)                    | increment double low word
        BCC.B   FP68K_DONE_12                   | no carry -> done
        ADDQ.L  #0x1,(A2)                       | propagate carry to high word
FP68K_DONE_12:
        BRA.B   FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_NO_39
|
FP68K_NO_39:
        ADDQ.L  #0x1,0x6(A2)                    | increment extended mantissa low
        BCC.B   FP68K_DONE_13                   | no carry -> done
        ADDQ.L  #0x1,0x2(A2)                    | carry to mantissa high
        BCC.B   FP68K_DONE_13                   | no carry -> done
        ROXR    0x2(A2)                         | mantissa overflow: shift right
        ADDQ.W  #0x1,(A2)                       | increment exponent
        CMPI    #0x7FFF,(A2)                    | exponent overflow to infinity?
        BEQ.B   FP68K_OK_30                     | yes -> clear mantissa MSB
        CMPI    #-0x1,(A2)                      | negative exponent overflow?
        BNE.B   FP68K_DONE_13                   | no -> done
FP68K_OK_30:
        BClr    #0x7,0x2(A2)                    | clear integer bit (infinity form)
| Called by: FP68K_NO_37, FP68K_OK_31, FP68K_NO_41, FP68K_NO_42, FP68K_NO_44
FP68K_DONE_13:
        MOVE.L  A2,-(SP)                        | push result operand ptr
        PEA.L   0x14(A4)                        | push temp for classify result
        MOVEQ.L #0x1C,D0                        | selector = classify
        OR      D5,D0                           | merge format
        MOVE    D0,-(SP)                        | push selector
        BSR     FP68K_EMPTY                     | classify the result
        MOVE    0x14(A4),D1                     | D1 = class code
        BPL.B   FP68K_SKIP_17                   | positive -> skip negate
        NEG     D1                              | make class code positive
FP68K_SKIP_17:
        CMPI    #0x3,D1                         | class = zero?
        BNE.B   FP68K_NO_40                     | no -> check other classes
        ORI     #0x1400,D6                      | flag underflow + inexact
        BRA.B   FP68K_EXIT_13                   | -> cleanup and return

| ----------------------------------------------------------
|
| FP68K_NO_40
|
FP68K_NO_40:
        CMPI    #0x5,D1                         | class = normal?
        BEQ.B   FP68K_EXIT_13                   | yes -> no exceptions
        ORI     #0x1200,D6                      | flag underflow + inexact
FP68K_EXIT_13:
        ADDA    #0x16,SP                        | deallocate temp space
        BRA     FP68K_EXIT_2                    | -> pack result and return

| ----------------------------------------------------------
|
| FP68K_OK_31
|
| FP68K_OK_31: nextAfter decrement path - decrease magnitude by 1 ULP
FP68K_OK_31:
        BTst    #0xC,D5                         | single format?
        BEQ.B   FP68K_NO_42                     | no -> check double
        TST.B   D4                              | dest was zero?
        BNE.B   FP68K_NO_41                     | no -> simple decrement
        BCHG    #0x7,(A2)                       | flip sign (cross zero)
        ADDQ.L  #0x1,(A2)                       | increment to smallest magnitude
        BRA.B   FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_NO_41: decrement single by 1 ULP
|
FP68K_NO_41:
        SUBQ.L  #0x1,(A2)                       | decrement single value
        BRA.B   FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_NO_42: decrement double by 1 ULP
|
FP68K_NO_42:
        BTst    #0xB,D5                         | double format?
        BEQ.B   FP68K_NO_44                     | no -> extended
        TST.B   D4                              | dest was zero?
        BNE.B   FP68K_NO_43                     | no -> simple decrement
        BCHG    #0x7,(A2)                       | flip sign (cross zero)
        ADDQ.W  #0x1,0x6(A2)                    | increment to smallest double
        BRA.B   FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_NO_43: decrement double low word, borrow into high
|
FP68K_NO_43:
        SUBQ.L  #0x1,0x4(A2)                    | decrement double low word
        BCC.B   FP68K_DONE_14                   | no borrow -> done
        SUBQ.L  #0x1,(A2)                       | borrow into high word
FP68K_DONE_14:
        BRA.B   FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_NO_44: decrement extended by 1 ULP
|
FP68K_NO_44:
        TST.B   D4                              | dest was zero?
        BNE.B   FP68K_NO_45                     | no -> simple decrement
        BCHG    #0x7,(A2)                       | flip sign (cross zero)
        ADDQ.W  #0x1,0x8(A2)                    | increment mantissa low to min
        BRA.B   FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_NO_45: decrement extended mantissa, handle borrow through exponent
|
FP68K_NO_45:
        SUBQ.L  #0x1,0x6(A2)                    | decrement mantissa low
        BCC.B   FP68K_DONE_15                   | no borrow -> done
        SUBQ.L  #0x1,0x2(A2)                    | borrow into mantissa high
        BMI.B   FP68K_CONT_108                  | underflow -> check exponent
        TST     (A2)                            | exponent zero?
        BEQ.B   FP68K_DONE_15                   | yes -> result is denorm, done
        CMPI    #-0x8000,(A2)                   | negative exponent word?
        BEQ.B   FP68K_DONE_15                   | yes -> done
        ADDI    #-0x8000,0x2(A2)                | restore sign bit in mantissa
        BRA.B   FP68K_CONT_109                  | -> decrement exponent

| ----------------------------------------------------------
|
| FP68K_CONT_108: mantissa borrow into exponent
|
FP68K_CONT_108:
        BCC.B   FP68K_DONE_15                   | no further borrow -> done
FP68K_CONT_109:
        SUBQ.W  #0x1,(A2)                       | decrement exponent
FP68K_DONE_15:
        BRA     FP68K_DONE_13                   | -> check result class

| ----------------------------------------------------------
|
| FP68K_CONT_110: setException - set specified SANE exception flag
|
FP68K_CONT_110:
        SWAP    D6                              | access high word for exception flags
        CLR     D6                              | clear low word
        MOVE    (A1),D0                         | D0 = exception bit number
        ADDQ.W  #0x8,D0                         | offset into exception flags byte
        BSET    D0,D6                           | set that exception flag
        BRA.B   FP68K_EXIT_14                   | -> return via pack path

| ----------------------------------------------------------
|
| FP68K_CONT_111: procEntry - save current env, set new rounding mode
|
FP68K_CONT_111:
        SWAP    D6                              | access high word
        MOVE    #0x1F00,D6                      | mask for exception flags
        AND     (A0),D6                         | capture current exceptions
        MOVE    (A1),(A0)                       | set new environment from (A1)
FP68K_EXIT_14:
        BRA     FP68K_EXIT_2                    | -> pack result and return

| ----------------------------------------------------------
|
| FP68K_CONT_112: Num2Dec - convert FP number to Decimal record
| Unpacks FP value, handles INF/NaN, then converts to
| decimal digits via repeated multiply-by-10
|
FP68K_CONT_112:
        SUBA    #0x14,SP                        | allocate 20 bytes temp space
        MOVE.L  A7,A3                           | A3 = temp buffer base
        LEA.L   0x4(A2),A4                      | A4 = decimal string start
        MOVE    0x2(A2),D3                      | D3 = decimal exponent
        SWAP    D6                              | save selector in high word
        CLR.L   D4                              | clear mantissa high
        MOVE.L  D4,D5                           | clear mantissa low
        MOVE.L  D4,D7                           | clear guard bits
        MOVEQ.L #0x13,D2                        | max 19 significant digits
        MOVE.B  (A4)+,D6                        | D6 = string length
        BEQ.B   FP68K_EMPTY_8                   | empty string -> zero
        MOVE.B  (A4),D0                         | first char of string
        CMPI.B  #0x49,D0                        | 'I' for infinity?
        BEQ.B   FP68K_OK_32                     | yes -> infinity
        CMPI.B  #0x4E,D0                        | 'N' for NaN?
        BNE.B   FP68K_NO_48                     | no -> normal decimal digits
        MOVE.B  -0x1(A4),D2                     | D2 = NaN payload length
        ADDQ.L  #0x1,A4                         | skip 'N'
        SUBQ.B  #0x1,D2                         | adjust for 'N' prefix
        MOVEQ.L #0x8,D0                         | 8 hex digits for high word
        CMPI.B  #0x4,D2                         | fewer than 4 digits?
        BGE.B   FP68K_NO_46                     | no -> full 8 digits
        SUBQ.B  #0x4,D0                         | adjust digit count
        ADD.B   D2,D0                           | D0 = actual hex digits
FP68K_NO_46:
        BSR.B   FP68K_LOOP_8                    | extract hex digits to D5
        MOVE.L  D5,D4                           | high NaN payload
        CLR.L   D5                              | clear for low part
        MOVEQ.L #0x8,D0                         | 8 more hex digits
        BSR.B   FP68K_LOOP_8                    | extract low hex digits
        BRA.B   FP68K_CONT_113                  | -> validate NaN payload

| ----------------------------------------------------------
|
| FP68K_LOOP_8: extract hex nibbles from NaN payload into mantissa
| Reads D0 hex digits, packing into D5 via rotate-and-OR
|
FP68K_LOOP_8:
        ROL.L   #0x4,D5                         | make room for next nibble
        SUBQ.B  #0x1,D2                         | any digits remaining?
        BMI.B   FP68K_EMPTY_7                   | no -> leave zero nibble
        MOVE.B  (A4)+,D1                        | read hex ASCII digit
        CMPI.B  #0x39,D1                        | is it A-F?
        BLE.B   FP68K_NO_47                     | no -> 0-9
        ADDI.B  #0x9,D1                         | adjust A-F to binary
FP68K_NO_47:
        ANDI.B  #0xF,D1                         | mask to 4-bit nibble
        OR.B    D1,D5                           | merge into result
FP68K_EMPTY_7:
        SUBQ.W  #0x1,D0                         | decrement digit count
        BNE.B   FP68K_LOOP_8                    | loop for all digits
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_113
|
FP68K_CONT_113:
        ANDI.L  #0x7FFFFFFF,D4                  | clear sign bit from payload
        BNE.B   FP68K_OK_32                     | nonzero payload -> valid NaN
        MOVEQ.L #0x15,D4                        | default NaN payload = 21
        SWAP    D4                              | shift to high word
        BSET    #0x1E,D4                        | set quiet NaN bit
FP68K_OK_32:
        MOVE    #0x7FFF,D0                      | exponent = NaN/Inf
        BRA.B   FP68K_CONT_114                  | -> store extended value

| ----------------------------------------------------------
|
| FP68K_NO_48
|
FP68K_NO_48:
        CMPI.B  #0x30,D0                        | first digit = '0' (zero)?
        BNE.B   FP68K_NEXT                      | no -> parse decimal digits
FP68K_EMPTY_8:
        CLR.L   D0                              | exponent = 0 (zero result)
FP68K_CONT_114:
        TST.B   (A2)                            | sign negative?
        BEQ.B   FP68K_NO_49                     | no -> positive
        BSET    #0xF,D0                         | set sign bit in exponent word
FP68K_NO_49:
        BSR     FP68K_CONT_117                  | store extended value at (A3)
        BRA     FP68K_CONT_116                  | -> convert to dest format

| ----------------------------------------------------------
|
| FP68K_CONT_115: multiply D4:D5 by 10 using shifts (x*10 = x*8 + x*2)
|
FP68K_CONT_115:
        ADD.L   D5,D5                           | x2 low
        ADDX.L  D4,D4                           | x2 high
        MOVE.L  D5,D1                           | save x2 low
        MOVE.L  D4,D0                           | save x2 high
        ADD.L   D5,D5                           | x4 low
        ADDX.L  D4,D4                           | x4 high
        ADD.L   D5,D5                           | x8 low
        ADDX.L  D4,D4                           | x8 high
        ADD.L   D1,D5                           | x8+x2 = x10 low
        ADDX.L  D0,D4                           | x8+x2 = x10 high
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_NEXT
|
FP68K_NEXT:
        BSR.B   FP68K_CONT_115                  | multiply accumulator by 10
        MOVEQ.L #0xF,D0                         | mask for ASCII digit
        AND.B   (A4)+,D0                        | D0 = digit value (0-9)
        ADD.L   D0,D5                           | add to mantissa low
        CLR     D0                              | clear for carry propagation
        ADDX.L  D0,D4                           | propagate carry to high
        SUBQ.B  #0x1,D6                         | more string chars?
        BEQ.B   FP68K_DONE_17                   | no -> done with digits
        SUBQ.B  #0x1,D2                         | max precision reached?
        BNE.B   FP68K_NEXT                      | no -> next digit
        MOVE.B  #0xF,D7                         | mask for rounding digit
        AND.B   (A4),D7                         | D7 = next digit (for rounding)
        BRA.B   FP68K_SKIP_18                   | -> skip remaining digits

| ----------------------------------------------------------
|
| FP68K_DONE_16
|
FP68K_DONE_16:
        CMPI    #0x1B,D3                        | exponent > 27?
        BLE.B   FP68K_SKIP_18                   | no -> stop multiplying
        BSR.B   FP68K_CONT_115                  | multiply by 10 (scale up)
        SUBQ.W  #0x1,D3                         | decrement remaining exponent
FP68K_DONE_17:
        SUBQ.W  #0x1,D2                         | decrement precision counter
        BNE.B   FP68K_DONE_16                   | loop until done
FP68K_SKIP_18:
        MOVE    #0x403E,D0                      | exponent = 63 + bias (64-bit int)
        TST.B   (A2)                            | sign negative?
        BEQ.B   FP68K_NO_50                     | no -> positive
        BSET    #0xF,D0                         | set sign bit
FP68K_NO_50:
        BSR.B   FP68K_CONT_117                  | store extended value at (A3)
        BSR.B   FP68K_CONT_118                  | apply power-of-10 scaling
FP68K_CONT_116:
        SWAP    D6                              | restore selector
        ANDI    #0x3800,D6                      | isolate dest format bits
        ORI     #0x10,D6                        | add convert-to-dest selector
        PEA.L   (A3)                            | push extended source
        MOVE.L  0xA(A6),-(SP)                   | push dest operand ptr
        MOVE    D6,-(SP)                        | push selector
        BSR     FP68K_EMPTY                     | convert extended to dest format
        ADDA    #0x14,SP                        | deallocate temp space
        BRA     FP68K_EXIT_3                    | -> three-operand return

| ----------------------------------------------------------
|
| FP68K_CONT_117: store extended value (D0:D4:D5) into temp at (A3)
|
FP68K_CONT_117:
        MOVE    D0,(A3)+                        | store exponent+sign word
        MOVE.L  D4,(A3)+                        | store mantissa high
        MOVE.L  D5,(A3)                         | store mantissa low
        SUBQ.L  #0x6,A3                         | rewind pointer to start
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_118: apply rounding direction for Num2Dec/Dec2Num scaling
| Chooses round-up or round-down based on format and sign
|
FP68K_CONT_118:
        MOVE.B  (A0),D6                         | read current rounding mode
        MOVE.B  D6,-(SP)                        | save on stack
        ANDI.B  #0x60,D6                        | isolate rounding mode bits
        BEQ.B   FP68K_OK_33                     | round-to-nearest -> use as-is
        MOVEQ.L #0x40,D1                        | D1 = round-toward-minus-inf mode
        TST.B   (A3)                            | value negative?
        BPL.B   FP68K_NO_51                     | no -> check positive direction
        CMPI.B  #0x40,D6                        | mode = round toward -inf?
        BEQ.B   FP68K_OK_34                     | yes -> invert for magnitude
        BRA.B   FP68K_NO_52                     | -> apply direction

| ----------------------------------------------------------
|
| FP68K_OK_33
|
FP68K_OK_33:
        MOVE.B  D6,(A0)                         | set round-to-nearest mode
        BRA.B   FP68K_CONT_119                  | -> do the scaling

| ----------------------------------------------------------
|
| FP68K_NO_51
|
FP68K_NO_51:
        CMPI.B  #0x20,D6                        | mode = round toward +inf?
        BNE.B   FP68K_NO_52                     | no -> keep direction
FP68K_OK_34:
        EORI.B  #0x60,D1                        | invert direction for this sign
FP68K_NO_52:
        TST     D3                              | exponent negative?
        BPL.B   FP68K_NO_53                     | no -> keep direction
        EORI.B  #0x60,D1                        | invert for negative power
FP68K_NO_53:
        MOVE.B  D1,(A0)                         | set adjusted rounding mode
FP68K_CONT_119:
        LEA.L   0xA(A3),A1                      | A1 = second temp extended slot
        BSR     FP68K_CONT_121                  | compute power-of-10 scale factor
        ORI.B   #0x60,(A0)                      | set round-toward-zero for multiply
        PEA.L   0xA(A3)                         | push scale factor
        PEA.L   (A3)                            | push value to scale
        MOVEQ.L #0x4,D0                         | selector = multiply
        TST     D3                              | exponent positive?
        BPL.B   FP68K_OK_35                     | yes -> multiply
        MOVEQ.L #0x6,D0                         | negative -> divide by power
FP68K_OK_35:
        MOVE    D0,-(SP)                        | push multiply/divide selector
        BSR     FP68K_EMPTY                     | scale the value
        BTST    #0x4,(A0)                       | inexact flag set?
        SNE.B   D0                              | D0 = $FF if inexact
        TST.B   D7                              | rounding digit nonzero?
        SNE.B   D7                              | D7 = $FF if nonzero
        OR.B    D7,D0                           | combine inexact indicators
        MOVE.B  (A0),D1                         | get environment byte
        ANDI.B  #0x1F,D1                        | mask exception flags
        OR.B    (SP)+,D1                        | merge saved rounding mode
        MOVE.B  D1,(A0)                         | restore environment
        NEG.B   D0                              | D0 = 1 if any inexactness
        BEQ.B   FP68K_DONE_18                   | exact -> done
        BSET    #0x4,(A0)                       | set inexact flag
        TST.B   D6                              | round-to-nearest mode?
        BEQ.B   FP68K_OK_37                     | yes -> special tie-break
        CMPI.B  #0x60,D6                        | round toward zero?
        BEQ.B   FP68K_DONE_18                   | yes -> already truncated
        MOVE.L  #0x1,-(SP)                      | build 1-ULP extended value
        CLR.L   -(SP)                           | mantissa low = 0
        MOVE    (A3),-(SP)                      | copy exponent
        SUBQ.W  #0x1,(SP)                       | exponent - 1 for ULP
        BCS.B   FP68K_CONT_120                  | underflow -> fix
        BVC.B   FP68K_OK_36                     | no overflow -> ok
FP68K_CONT_120:
        ADDQ.W  #0x1,(SP)                       | restore exponent
FP68K_OK_36:
        PEA.L   (SP)                            | push ULP operand
        PEA.L   (A3)                            | push value
        CLR     -(SP)                           | selector = add
        BSR     FP68K_EMPTY                     | add 1 ULP for directed rounding
        ADDA    #0xA,SP                         | clean up stack
        BRA.B   FP68K_DONE_18                   | -> done

| ----------------------------------------------------------
|
| FP68K_OK_37
|
FP68K_OK_37:
        MOVE    (A3),D0                         | get result exponent
        ADDQ.W  #0x1,D0                         | increment for tie-break check
        ADD     D0,D0                           | double (shift out sign bit)
        BEQ.B   FP68K_DONE_18                   | zero -> no tie-break needed
        BSET    #0x0,0x9(A3)                    | set LSB for round-to-odd
FP68K_DONE_18:
        RTS                                     | return to caller
| POWER_TBL prefix: extended-precision powers of 10 for large exponents
| Each 14-byte entry: 2-byte exp_delta, 2-byte sign, 10-byte extended value
| Used by FP68K_CONT_121 to scale by 10^14, 10^27, 10^55, 10^110, 10^220, etc.
  .byte 0x00,0x0E,0x00,0x00,0x40,0x2D
  .byte 0xB5,0xE6,0x20,0xF4,0x80,0x00
  .byte 0x00,0x00,0x00,0x1B,0x00,0x00
  .byte 0x40,0x58,0xCE,0xCB,0x8F,0x27
  .byte 0xF4,0x20,0x0F,0x3A,0x00,0x37
  .byte 0x00,0x01,0x40,0xB5,0xD0,0xCF
  .byte 0x4B,0x50,0xCF,0xE2,0x07,0x66
  .byte 0x00,0x6C,0x00,0x01,0x41,0x65
  .byte 0xDA,0x01,0xEE,0x64,0x1A,0x70
  .byte 0x8D,0xEA,0x00,0xCE,0xFF,0xFF
  .byte 0x42,0xAB,0x9F,0x79,0xA1,0x69
  .byte 0xBD,0x20,0x3E,0x41,0x01,0x9C
  .byte 0x00,0x01,0x45,0x57,0xC6,0xB0
  .byte 0xA0,0x96,0xA9,0x52,0x02,0xBE
  .byte 0x03,0x38,0x00,0x01,0x4A,0xB0
  .byte 0x9A,0x35,0xB2,0x46,0x41,0xD0
  .byte 0x59,0x53,0x06,0x70,0x00,0x01
  .byte 0x55,0x61,0xB9,0xC9,0x4B,0x7F
  .byte 0xA8,0xD7,0x65,0x15
POWER_TBL:
  .byte  0x0C,0xE0,0x00,0x01,0x6A,0xC4
  .byte 0x86,0xD4,0x8D,0x66,0x26,0xC2
  .byte 0x7E,0xEC
| FP68K_CONT_121 -- compute power-of-10 scale factor.
FP68K_CONT_121:
        MOVEQ.L #0x9,D1                         | 9 table entries to process
        MOVE    D3,D0                           | D0 = absolute decimal exponent
        BPL.B   FP68K_OK_38                     | positive -> ok
        NEG     D0                              | make positive
FP68K_OK_38:
        CMPI    #0xF,D0                         | exponent < 15?
        BCS.B   FP68K_OK_41                     | yes -> use small table directly
        CMPI    #0x1388,D0                      | exponent > 5000?
        BCS.B   FP68K_OK_39                     | no -> ok
        MOVE    #0x1388,D0                      | clamp to 5000
FP68K_OK_39:
        LEA.L   POWER_TBL(PC),A2                | A2 = large power table
FP68K_LOOP_9:
        CMP     (A2),D0                         | remaining exp >= table entry?
        BCS.B   FP68K_SKIP_19                   | no -> skip this power
        SUB     (A2)+,D0                        | subtract and advance to sign
        TST     (A2)                            | inexact entry? (sign word)
        BEQ.B   FP68K_NO_55                     | no -> exact power, use directly
        BSET    #0x4,(A0)                       | flag inexact (approximate power)
        BTST    #0x6,(A0)                       | rounding toward -inf?
        BEQ.B   FP68K_NO_54                     | no -> check +inf
        TST     (A2)                            | sign of correction?
        BLE.B   FP68K_NO_55                     | <= 0 -> use lower bound
        BRA.B   FP68K_CONT_122                  | -> use adjusted bound

| ----------------------------------------------------------
|
| FP68K_NO_54
|
FP68K_NO_54:
        BTst    #0x5,(A0)                       | rounding toward +inf?
        BEQ.B   FP68K_NO_55                     | no -> use exact value
        TST     (A2)                            | sign of correction?
        BGE.B   FP68K_NO_55                     | >= 0 -> use lower bound
FP68K_CONT_122:
        MOVE.L  A2,-(SP)                        | save table pointer
        MOVE    0xA(A2),-(SP)                   | push adjusted exponent
        TST     (A2)+                           | correction positive?
        BPL.B   FP68K_OK_40                     | yes -> increment exponent
        ADDQ.W  #0x1,(SP)                       | negative: bump exponent up
        BRA.B   FP68K_CONT_123                  | -> build adjusted value

| ----------------------------------------------------------
|
| FP68K_OK_40
|
FP68K_OK_40:
        SUBQ.W  #0x1,(SP)                       | positive: decrement exponent
FP68K_CONT_123:
        MOVE.L  0x4(A2),-(SP)                   | push adjusted mantissa low
        MOVE.L  (A2),-(SP)                      | push adjusted mantissa high
        MOVE.L  A7,A2                           | A2 = stack-based extended value
        BSR.B   FP68K_CONT_124                  | multiply by adjusted power
        ADDQ.L  #0x8,SP                         | clean up stack (8 bytes)
        ADDQ.L  #0x2,SP                         | clean up stack (2 bytes)
        MOVE.L  (SP)+,A2                        | restore table pointer
        ADDQ.L  #0x2,A2                         | skip sign word
        BRA.B   FP68K_NEXT_2                    | -> advance to next entry

| ----------------------------------------------------------
|
| FP68K_NO_55
|
FP68K_NO_55:
        ADDQ.L  #0x2,A2                         | skip sign word
        BSR.B   FP68K_CONT_124                  | multiply by this power of 10
FP68K_NEXT_2:
        SUBQ.L  #0x4,A2                         | back up past sign+delta words
FP68K_SKIP_19:
        SUBA    #0xE,A2                         | advance to next table entry
        SUBQ.W  #0x1,D1                         | decrement entry counter
        BNE.B   FP68K_LOOP_9                    | loop for all 9 entries
FP68K_OK_41:
        MULU    #0xA,D0                         | remaining exp * 10 bytes/entry
        LEA.L   FP68K_CONT_125(PC,D0.W),A2      | A2 = small power-of-10 entry
| FP68K_CONT_124: multiply or store power of 10 into scale factor at (A1)
FP68K_CONT_124:
        TST.L   D1                              | first call (D1 >= 0)?
        BPL.B   FP68K_OK_42                     | yes -> store directly
        PEA.L   (A2)                            | push power-of-10 operand
        PEA.L   (A1)                            | push accumulated scale factor
        MOVE    #0x4,-(SP)                      | selector = multiply
        BSR     FP68K_EMPTY                     | multiply into scale factor
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_OK_42
|
FP68K_OK_42:
        MOVE    (A2)+,(A1)+                     | copy exponent word
        MOVE.L  (A2)+,(A1)+                     | copy mantissa high
        MOVE.L  (A2),(A1)                       | copy mantissa low
        SUBQ.L  #0x6,A1                         | rewind dest pointer
        SUBQ.L  #0x6,A2                         | rewind source pointer
        BSET    #0x1F,D1                        | mark as initialized
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_125: extended-precision powers of 10 (10^0 through 10^14)
| Used for decimal-to-binary conversion scaling
|
FP68K_CONT_125:
  .byte  0x3F,0xFF,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00,0x40,0x02
  .byte 0xA0,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x40,0x05,0xC8,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x40,0x08,0xFA,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x00,0x40,0x0C
  .byte 0x9C,0x40,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x40,0x0F,0xC3,0x50
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x40,0x12,0xF4,0x24,0x00,0x00
  .byte 0x00,0x00,0x00,0x00,0x40,0x16
  .byte 0x98,0x96,0x80,0x00,0x00,0x00
  .byte 0x00,0x00,0x40,0x19,0xBE,0xBC
  .byte 0x20,0x00,0x00,0x00,0x00,0x00
  .byte 0x40,0x1C,0xEE,0x6B,0x28,0x00
  .byte 0x00,0x00,0x00,0x00,0x40,0x20
  .byte 0x95,0x02,0xF9,0x00,0x00,0x00
  .byte 0x00,0x00,0x40,0x23,0xBA,0x43
  .byte 0xB7,0x40,0x00,0x00,0x00,0x00
  .byte 0x40,0x26,0xE8,0xD4,0xA5,0x10
  .byte 0x00,0x00,0x00,0x00,0x40,0x2A
  .byte 0x91,0x84,0xE7,0x2A,0x00,0x00
  .byte 0x00,0x00,0x40,0x2D,0xB5,0xE6
  .byte 0x20,0xF4,0x80,0x00,0x00,0x00
| FP68K_CONT_126: Dec2Num extended - convert Decimal record to extended FP
| Parses sign, digits, handles NaN/Inf/Zero, then builds mantissa
| and scales by power of 10 to produce final extended result
FP68K_CONT_126:
        MOVE    D6,D0                           | save selector
        ROL     #0x6,D0                         | extract format code
        CLR.L   D2                              | clear NaN counter
        MOVE.L  D2,D3                           | clear class
        MOVE.L  D2,D6                           | clear flags
        MOVE.L  D2,D7                           | clear guard bits
        MOVE.L  A2,A3                           | A3 = source operand ptr
        BSR     FP68K_CONT_5                    | unpack source to extended
        MOVE    A4,D0                           | D0 = source exponent
        MOVE.L  0x12(A6),A4                     | A4 = DecForm ptr
        SUBA    #0x1E,SP                        | allocate 30 bytes temp space
        MOVE.L  A7,A3                           | A3 = temp buffer base
        ROL.B   #0x1,D6                         | sign bit to bit 0
        MOVE.B  D6,(A1)                         | store sign in Decimal record
        MOVE.B  #0x1,0x4(A1)                    | default: 1 digit
        TST     D2                              | source is NaN?
        BEQ.B   FP68K_NO_56                     | no -> check other specials
        ADDQ.L  #0x4,A1                         | advance to digit string
        MOVE.B  #0x11,(A1)+                     | string length = 17
        MOVE.B  #0x4E,(A1)+                     | 'N' for NaN
        BSR.B   FP68K_CONT_127                  | convert D4 to 8 hex digits
        MOVE.L  D5,D4                           | get low NaN payload
        BSR.B   FP68K_CONT_127                  | convert to 8 more hex digits
        SUBA    #0x16,A1                        | rewind pointer to record start
        BRA     FP68K_EXIT_16                   | -> cleanup and return

| ----------------------------------------------------------
|
| FP68K_CONT_127: convert 32-bit D4 to 8 hex ASCII digits at (A1)+
|
FP68K_CONT_127:
        MOVEQ.L #0x8,D0                         | 8 hex digits per 32-bit word
FP68K_LOOP_10:
        ROL.L   #0x4,D4                         | rotate next nibble to low bits
        MOVEQ.L #0xF,D1                         | nibble mask
        AND.B   D4,D1                           | D1 = nibble value (0-15)
        ORI.B   #0x30,D1                        | convert to ASCII '0'-'?'
        CMPI.B  #0x39,D1                        | is it 0-9?
        BLE.B   FP68K_DONE_19                   | yes -> done
        ADDQ.B  #0x7,D1                         | adjust for A-F
FP68K_DONE_19:
        MOVE.B  D1,(A1)+                        | store hex ASCII digit
        SUBQ.W  #0x1,D0                         | decrement digit count
        BNE.B   FP68K_LOOP_10                   | loop for all 8 digits
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_NO_56: Dec2Num - handle zero, infinity, and NaN decimal records
|
FP68K_NO_56:
        TST     D3                              | class = normal?
        BEQ.B   FP68K_OK_44                     | yes -> convert normally
        MOVEQ.L #0x30,D0                        | '0' for zero
        CMPI    #0x2,D3                         | class = zero?
        BEQ.B   FP68K_OK_43                     | yes -> store '0'
        MOVEQ.L #0x49,D0                        | 'I' for infinity
FP68K_OK_43:
        MOVE.B  D0,0x5(A1)                      | store class char in digit string
        BRA     FP68K_EXIT_16                   | -> cleanup and return

| ----------------------------------------------------------
|
| FP68K_OK_44: Dec2Num normal - convert decimal digits to binary mantissa
| Estimates decimal exponent using log10(2) approximation
|
FP68K_OK_44:
        MOVE.L  D4,D1                           | save mantissa high
        MOVE    D0,D1                           | D1.lo = exponent
        SUBI    #0x3FFF,D1                      | D1.lo = unbiased exponent
        SWAP    D1                              | D1.hi = unbiased exponent
        ADD     D1,D1                           | D1.lo = 2 * mantissa high word
        TST     D0                              | exponent negative?
        BPL.B   FP68K_OK_45                     | no -> ok
FP68K_LOOP_11:
        LSR.L   #0x1,D4                         | shift mantissa right
        ROXR.L  #0x1,D5                         | propagate
        ADDQ.W  #0x1,D0                         | increment exponent
        BMI.B   FP68K_LOOP_11                   | loop until exponent >= 0
FP68K_OK_45:
        ROR     #0x1,D6                         | save sign in high bit
        OR      D6,D0                           | merge sign into exponent
        BSR     FP68K_CONT_117                  | store extended value at (A3)
        CLR.L   D4                              | clear estimated decimal exponent
        TST.B   (A4)                            | fixed-decimal format?
        BNE.B   FP68K_RETRY                     | yes -> skip estimation
| estimate decimal exponent using log10(2) approximation
| log10(2) ~ 0x4D104D42 / 2^32 ~ 0.30103
        MOVE.L  #0x4D104D42,D0                  | log10(2) * 2^32 (approx)
        TST.L   D1                              | exponent negative?
        BPL.B   FP68K_OK_46                     | no -> ok
        ADDQ.W  #0x1,D0                         | adjust for negative rounding
FP68K_OK_46:
        MOVE.L  D0,D4                           | copy for multiplication
        SWAP    D4                              | D4 = log10(2) high word
        MULU    D1,D4                           | partial product 1
        CLR     D4                              | discard low word
        SWAP    D4                              | shift to high
        SWAP    D1                              | D1 = unbiased exponent
        MOVE    D1,D5                           | save for second multiply
        MULS    D0,D5                           | partial product 2
        SWAP    D5                              | get high word
        EXT.L   D5                              | sign extend
        ADD.L   D5,D4                           | accumulate
        SWAP    D0                              | D0 = log10(2) high word
        MULS    D1,D0                           | partial product 3
        ADD.L   D0,D4                           | accumulate
        SWAP    D4                              | D4 = estimated decimal exponent
        ADDQ.W  #0x1,D4                         | round up estimate
FP68K_RETRY:
        BSR     FP68K_CONT_129                  | get requested digit count in D3
        SUB     D4,D3                           | D3 = digits - estimated exp
        MOVE.L  0xA(A6),A1                      | A1 = Decimal record ptr
        MOVE    D3,0x2(A1)                      | store decimal exponent
        NEG     0x2(A1)                         | negate for Decimal.exp convention
        MOVE    (A3),0x14(A3)                   | save original extended exponent
        MOVE.L  PORTBITS(A3),0x16(A3)           | save original mantissa high
        MOVE.L  0x6(A3),0x1A(A3)                | save original mantissa low
        BSR     FP68K_CONT_118                  | scale by power of 10
        PEA.L   (A3)                            | push scaled value
        MOVE    #0x14,-(SP)                     | selector = rint (round to integer)
        BSR     FP68K_EMPTY                     | round to integer
        LEA.L   0xA(A3),A1                      | A1 = second temp slot
        TST.B   (A4)                            | fixed-decimal format?
        BNE.B   FP68K_OK_47                     | yes -> use fixed digit count
        BSR.B   FP68K_CONT_129                  | get requested digits
        BRA.B   FP68K_CONT_128                  | -> compute scale factor

| ----------------------------------------------------------
|
| FP68K_OK_47
|
FP68K_OK_47:
        MOVEQ.L #0x13,D3                        | fixed: use max 19 digits
FP68K_CONT_128:
        BSR     FP68K_CONT_121                  | build power-of-10 scale factor
        MOVE    (A3),D0                         | get scaled result exponent
        BCLR    #0xF,D0                         | clear sign for comparison
        CMP     (A1),D0                         | compare with scale factor exp
        BNE.B   FP68K_OK_48                     | different -> check which is larger
        MOVE.L  PORTBITS(A3),D0                 | compare mantissa high
        CMP.L   0x2(A1),D0                      | vs scale factor mantissa high
        BNE.B   FP68K_OK_48                     | different -> check
        MOVE.L  0x6(A3),D0                      | compare mantissa low
        CMP.L   0x6(A1),D0                      | vs scale factor mantissa low
FP68K_OK_48:
        BCS.B   FP68K_CONT_130                  | value < scale -> too few digits
        TST.B   (A4)                            | fixed-decimal format?
        BNE.B   FP68K_OK_49                     | yes -> overflow
        ADDQ.W  #0x1,D4                         | increment estimated exponent
        MOVE    0x14(A3),(A3)                   | restore original extended value
        MOVE.L  0x16(A3),PORTBITS(A3)           | restore mantissa high
        MOVE.L  0x1A(A3),0x6(A3)                | restore mantissa low
        BRA.B   FP68K_RETRY                     | retry with adjusted estimate

| ----------------------------------------------------------
|
| FP68K_OK_49: Num2Dec overflow - digit count exceeds capacity, return '?'
|
FP68K_OK_49:
        MOVE.L  0xA(A6),A1                      | A1 = Decimal record ptr
        MOVE.B  #0x3F,0x5(A1)                   | store '?' (overflow indicator)
        BRA     FP68K_EXIT_16                   | -> cleanup and return

| ----------------------------------------------------------
|
| FP68K_CONT_129: get requested digit count from DecForm, clamped to [1,19]
|
FP68K_CONT_129:
        MOVE    0x2(A4),D3                      | D3 = requested digits from DecForm
        TST.B   (A4)                            | fixed-decimal format?
        BNE.B   FP68K_EXIT_15                   | yes -> use as-is
        TST     D3                              | digits <= 0?
        BLE.B   FP68K_OK_50                     | yes -> force minimum 1
        CMPI    #0x13,D3                        | digits > 19?
        BLE.B   FP68K_EXIT_15                   | no -> ok
        MOVEQ.L #0x13,D3                        | clamp to 19 max
        BRA.B   FP68K_EXIT_15                   | -> return

| ----------------------------------------------------------
|
| FP68K_OK_50: force minimum 1 digit
|
FP68K_OK_50:
        MOVEQ.L #0x1,D3                         | minimum 1 significant digit
FP68K_EXIT_15:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FP68K_CONT_130: Num2Dec - adjust if too few digits, try one fewer
|
FP68K_CONT_130:
        TST.B   (A4)                            | fixed-decimal format?
        BNE.B   FP68K_SKIP_20                   | yes -> skip adjustment
        BSR.B   FP68K_CONT_129                  | get requested digit count
        SUBQ.W  #0x1,D3                         | try one fewer digit
        BSR     FP68K_CONT_121                  | build scale factor for D3 digits
        MOVE    (A3),D0                         | get result exponent
        BCLR    #0xF,D0                         | clear sign
        CMP     (A1),D0                         | compare with scale factor
        BNE.B   FP68K_CONT_131                  | different -> check which
        MOVE.L  PORTBITS(A3),D0                 | compare mantissa high
        CMP.L   0x2(A1),D0                      | vs scale factor
        BNE.B   FP68K_CONT_131                  | different -> check
        MOVE.L  0x6(A3),D0                      | compare mantissa low
        CMP.L   0x6(A1),D0                      | vs scale factor
FP68K_CONT_131:
        BCC.B   FP68K_SKIP_20                   | value >= scale -> ok
        MOVE    (A1),(A3)                       | use scale factor as result
        MOVE.L  0x2(A1),PORTBITS(A3)            | copy mantissa high
        MOVE.L  0x6(A1),0x6(A3)                 | copy mantissa low
        NOP                                     | alignment padding
FP68K_SKIP_20:
        MOVE.L  0xA(A6),A1                      | A1 = Decimal record ptr
        MOVE    (A3),D3                         | D3 = result exponent+sign
        MOVE.L  PORTBITS(A3),D1                 | D1 = mantissa high
        BNE.B   FP68K_CONT_132                  | nonzero -> convert to digits
        MOVE.B  #0x30,0x5(A1)                   | mantissa zero -> store '0'
        BRA     FP68K_EXIT_16                   | -> cleanup and return

| ----------------------------------------------------------
|
| FP68K_CONT_132: Num2Dec - convert binary mantissa to decimal via multiply-by-5
| D1:D2 = denormalized mantissa, produces 19 decimal digits
|
FP68K_CONT_132:
        MOVE.L  0x6(A3),D2                      | D2 = mantissa low
        BCLR    #0xF,D3                         | clear sign from exponent
        SUBI    #0x403E,D3                      | remove bias (63 + $3FFF)
        BEQ.B   FP68K_CONT_133                  | exponent = 0 -> already integer
FP68K_LOOP_12:
        LSR.L   #0x1,D1                         | shift mantissa right
        ROXR.L  #0x1,D2                         | propagate
        ADDQ.W  #0x1,D3                         | increment toward 0
        BMI.B   FP68K_LOOP_12                   | loop until exponent = 0
FP68K_CONT_133:
| divide 64-bit integer by 10^19 to extract decimal digits
| divisor = 10^19 = $8AC72304:89E80000
        MOVE.L  #0x8AC72304,D3                  | divisor high = 10^19 high
        MOVE.L  #0x89E80000,A2                  | divisor low = 10^19 low
        MOVEQ.L #0x41,D0                        | 65 iterations
        BSR     FP68K_LOOP_4                    | divide: quotient=D4:D5, rem=D1:D2
        ADDQ.L  #0x1,D5                         | round up remainder
        ADDX.L  D0,D4                           | propagate carry
        ADDQ.L  #0x4,A1                         | advance past Decimal header
        MOVE.L  A1,A2                           | A2 = digit output ptr
        CLR.B   (A2)+                           | clear digit count
        MOVEQ.L #0x13,D6                        | 19 decimal digits to extract
| FP68K_LOOP_13: extract decimal digits via multiply-by-10 (x*10 = x*8 + x*2)
FP68K_LOOP_13:
        ADD.L   D5,D5                           | shift left (x2)
        ADDX.L  D4,D4                           | propagate carry
        ADDX    D0,D0                           | propagate carry
        MOVE.L  D5,D3                           | save x2 low
        MOVE.L  D4,D2                           | save x2 high
        MOVE    D0,D1                           | save x2 overflow
        ADD.L   D5,D5                           | shift left (x4)
        ADDX.L  D4,D4                           | propagate
        ADDX    D0,D0                           | propagate
        ADD.L   D5,D5                           | shift left (x8)
        ADDX.L  D4,D4                           | propagate
        ADDX    D0,D0                           | propagate
        ADD.L   D3,D5                           | x8 + x2 = x10 low
        ADDX.L  D2,D4                           | propagate
        ADDX    D1,D0                           | D0 = decimal digit (0-9)
        TST     D0                              | digit zero?
        BEQ.B   FP68K_SKIP_21                   | yes -> skip leading zero
        ORI.L   #0x130,D0                       | convert to ASCII ('0' = $30)
        MOVE.B  D0,(A2)+                        | store decimal digit
        CLR.B   D0                              | clear for next iteration
        ADDQ.B  #0x1,(A1)                       | increment digit count
FP68K_SKIP_21:
        SUBQ.B  #0x1,D6                         | decrement digit counter
        BNE.B   FP68K_LOOP_13                   | loop for all 19 digits
FP68K_EXIT_16:
        ADDA    #0x1E,SP                        | deallocate temp space
        BRA     FP68K_EXIT_6                    | -> three-operand return

| end of resource : 'PACK' 4

| resource header
  .long 0xC000004C                              | Length
  .long 0x00000080                              | ?
