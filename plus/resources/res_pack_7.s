|
| PACK 7: Binary-Decimal Conversion Package (NumToString, StringToNum)
| Converts 32-bit integers to/from decimal ASCII strings
| Uses 68000 BCD (ABCD) instructions for binary-to-BCD conversion
|
| PACK 4: SANE Floating Point Arithmetic (IEEE 754)
| Implements: add, subtract, multiply, divide, compare, convert,
| square root, remainder, logb, scalb, classify, and more
| Supports: single (32-bit), double (64-bit), extended (80-bit), comp (64-bit int)
|
| PACK 5: SANE Transcendental Functions
| Implements: ln, log2, log, exp, exp2, exp1, sin, cos, tan, atan
|
| resource : 'PACK' 7
| Binary-Decimal Conversion Package
IMPLEMENTS_2:
        BRA.B   DECSTR_SKIP                     | skip resource header
  .byte 0x00,0x00                               | flags: unused
  .ascii "PACK"                                 | resource type identifier
  .byte 0x00,0x07,0x00,0x01                     | resource ID = 7, version = 1
| PACK 7 entry: dispatch NumToString (selector 0) or StringToNum (selector 1)
DECSTR_SKIP:
        SUBQ.W  #0x1,0x4(SP)                    | test selector (0=NumToString, 1=StringToNum)
        BPL.B   STRINGTONUM                     | no, StringToNum falls through ->
| NumToString: convert D0.L to decimal ASCII string at A0
        MOVE.L  (SP),0x2(SP)                    | shift return address
        ADDQ.W  #0x2,SP                         | pop selector
        MOVEM.L D0-D6/A1,-(SP)                  | save regs
| convert binary to 10-digit BCD using repeated add-with-carry
        MOVEQ.L #0x0,D1                         | clear BCD accumulators
        MOVEQ.L #0x0,D2                         | clear BCD digit pair 2
        MOVEQ.L #0x0,D3                         | clear BCD digit pair 3
        MOVEQ.L #0x0,D4                         | clear BCD digit pair 4
        MOVEQ.L #0x0,D5                         | clear BCD digit pair 5
        MOVEQ.L #0x1F,D6                        | 32 bits to convert
        LEA.L   0x1(A0),A1                      | A1 = output string (past length byte)
| check sign
        TST.L   D0                              | positive?
        BGT.B   DECSTR_LOOP                     | yes ->
        BMI.B   DECSTR_CONT                     | negative ->
        MOVE.B  #0x30,(A1)+                     | zero: write '0'
        BRA.B   DECSTR_DONE                     | -> done
| negative: write '-' sign and negate
DECSTR_CONT:
        MOVE.B  #0x2D,(A1)+                     | write '-'
        NEG.L   D0                              | make positive
| shift-and-add BCD conversion: 32 iterations of double-dabble
DECSTR_LOOP:
        ADD.L   D0,D0                           | shift MSB into carry
        ABCD    D5,D5                           | add carry into BCD digit pair
        ABCD    D4,D4                           | BCD double digit pair 4
        ABCD    D3,D3                           | BCD double digit pair 3
        ABCD    D2,D2                           | BCD double digit pair 2
        ABCD    D1,D1                           | D1:D2:D3:D4:D5 = 10-digit BCD
        DBF     D6,DECSTR_LOOP                  | repeat for all 32 bits
| convert BCD digits to ASCII and store
        BSR.B   DECSTR_CONT_2                   | convert D1 (2 digits) -> ASCII
        MOVE.B  D2,D1                           | load BCD digit pair 2
        BSR.B   DECSTR_CONT_2                   | convert D2
        MOVE.B  D3,D1                           | load BCD digit pair 3
        BSR.B   DECSTR_CONT_2                   | convert D3
        MOVE.B  D4,D1                           | load BCD digit pair 4
        BSR.B   DECSTR_CONT_2                   | convert D4
        MOVE.B  D5,D1                           | convert D5
        BSR.B   DECSTR_CONT_2                   | convert D5 to ASCII digits
DECSTR_DONE:
        MOVE    A1,D0                           | D0 = end of string pointer
        SUB     A0,D0                           | D0 = string length + 1
        SUBQ.B  #0x1,D0                         | D0 = string length
        MOVE.B  D0,(A0)                         | store Pascal string length byte
        MOVEM.L (SP)+,D0-D6/A1                  | restore registers
        RTS                                     | return

| ----------------------------------------------------------
|
| DECSTR_CONT_2
|
| DECSTR_CONT_2: convert BCD byte pair to two ASCII digits
| D1 = packed BCD byte, outputs to (A1)+
| D6 bit 15: leading-zero suppression flag
DECSTR_CONT_2:
        ROR     #0x4,D1                         | get high nibble
        BSR.B   DECSTR_CONT_3                   | output high digit
        ROL     #0x4,D1                         | get low nibble
| DECSTR_CONT_3: output one BCD digit as ASCII (with leading zero suppression)
DECSTR_CONT_3:
        TST     D6                              | suppressing leading zeros?
        BPL.B   DECSTR_NO                       | no, always output ->
        TST.B   D1                              | digit is zero?
        BEQ.B   DECSTR_OK                       | yes, suppress it ->
        MOVEQ.L #0x0,D6                         | first nonzero: stop suppressing
DECSTR_NO:
        ORI.B   #0x30,D1                        | convert BCD to ASCII ('0'=$30)
        MOVE.B  D1,(A1)+                        | output digit
        SUB.B   D1,D1                           | clear for next digit
DECSTR_OK:
        RTS                                     | return

| ----------------------------------------------------------
|
| StringToNum: convert decimal ASCII string to 32-bit integer
| A0 = Pascal string -> D0.L = result
|
STRINGTONUM:
        MOVE    0x4(SP),D0                      | get selector
        MOVE.L  (SP),0x2(SP)                    | shift return address
        ADDQ.W  #0x2,SP                         | pop selector
        SUBQ.W  #0x1,D0                         | selector 1?
        BPL.B   DECSTR_OK_2                     | yes, selector >= 2 (SANE routines) ->
| StringToNum: convert decimal ASCII string to 32-bit integer
        MOVEM.L D1-D3/A0,-(SP)                  | save regs
        MOVEQ.L #0x0,D0                         | clear result
        MOVEQ.L #0x0,D1                         | clear D1
        MOVEQ.L #0x0,D3                         | clear sign flag
        MOVE.B  (A0)+,D2                        | D2 = Pascal string length
        BEQ.B   DECSTR_EXIT                     | empty string -> return 0
| check for leading sign character
        CMPI.B  #0x2B,(A0)                      | '+' ?
        BEQ.B   DECSTR_SKIP_2                   | yes, skip it ->
        CMPI.B  #0x2D,(A0)                      | '-' ?
        BNE.B   DECSTR_NO_2                     | no sign, start digits ->
        MOVEQ.L #0x1,D3                         | D3 = negative flag
DECSTR_SKIP_2:
        ADDQ.L  #0x1,A0                         | skip sign character
        SUBQ.B  #0x1,D2                         | one fewer character
        BEQ.B   DECSTR_EXIT                     | empty after sign ->
| digit loop: D0 = D0 * 10 + digit (using shifts: *10 = *2 + *8)
DECSTR_NO_2:
        MOVEQ.L #0xF,D1                         | mask for ASCII digit
        AND.B   (A0)+,D1                        | D1 = digit value (0-9)
        ADD.L   D0,D0                           | D0 * 2
        ADD.L   D0,D1                           | D1 = D0*2 + digit
        LSL.L   #0x2,D0                         | D0 * 8 (was *2, now *8)
        ADD.L   D1,D0                           | D0 = D0*8 + D0*2 + digit = D0*10 + digit
        SUBQ.B  #0x1,D2                         | more digits?
        BNE.B   DECSTR_NO_2                     | yes ->
| apply sign
        TST.B   D3                              | negative?
        BEQ.B   DECSTR_EXIT                     | no ->
        NEG.L   D0                              | negate result
DECSTR_EXIT:
        MOVEM.L (SP)+,D1-D3/A0                  | restore regs
        RTS                                     | return

| ----------------------------------------------------------
|
| DECSTR_OK_2
|
| PACK 7 extended dispatch: selector 2=PStr2Dec, 3=Dec2Str, 4=CStr2Dec
DECSTR_OK_2:
        SUBQ.W  #0x1,D0                         | adjust selector
        BMI.B   DECSTR_CONT_4                   | 0: PStr2Dec (Pascal string to decimal record) ->
        BEQ.B   DEC2STR                         | 1: Dec2Str (decimal record to Pascal string) ->
        CMPI    #0x1,D0                         | 2: CStr2Dec (C string to decimal record)?
        BEQ.B   DECSTR_OK_3                     | yes ->
        RTS                                     | unknown selector

| PStr2Dec: parse Pascal string into Decimal record
DECSTR_CONT_4:
        JMP     DECSTR_CONT_5(PC)               | -> Dec2Str implementation

| Dec2Str: convert DecForm + Decimal record to Pascal string
DEC2STR:
        JMP     STACK(PC)                       | -> Str2Dec implementation

| CStr2Dec: parse C string into Decimal record
DECSTR_OK_3:
        JMP     DEC2NUM(PC)                     | -> Dec2Num implementation

| ----------------------------------------------------------
|
| Dec2Num: convert Decimal record to 80-bit extended
| D1 bit 31 set = output to extended, clear = output to double/single
|
DEC2NUM:
        MOVEQ.L #0x1,D1                         | set extended flag
        ROR.L   #0x1,D1                         | D1 = $80000000 (extended format)
        BRA.B   DECSTR_CONT_6                   | -> common conversion

| ----------------------------------------------------------
|
| Dec2Str entry: format decimal number as ASCII string
|
DECSTR_CONT_5:
        MOVEQ.L #0x0,D1                         | D1 = 0 (string output mode)
DECSTR_CONT_6:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L D2-D7/A2-A3,-(SP)               | save regs
        MOVEM.L 0xC(A6),D4-D6                   | D4=Decimal ptr, D5=Index ptr, D6=String ptr
        AND.L   (Lo3Bytes).w,D6                 | strip high byte from string pointer
        MOVE.L  D6,A0                           | A0 = string pointer
        MOVE.L  D5,A1                           | A1 = Index pointer
        MOVEQ.L #0x0,D6                         | clear D6
        MOVE.B  (A0),D6                         | D6 = string length (Pascal)
        LEA.L   0x0(A0,D6.W),A3                 | A3 = pointer to end of Pascal string
        ADDA    (A1),A0                         | A0 = pointer to string + Index (current pos)
        MOVE.L  A0,D6                           | D6 = saved start position
        MOVE.L  D4,A1                           | A1 = Decimal record pointer
        LEA.L   0x4(A1),A2                      | A2 = Decimal.sig (significant digits string)
        MOVE.L  D1,D4                           | D4 = input mode flags (0 or $80000000)
        ADDI.B  #0x30,D4                        | set bit 4 or 5 of flags?
        MOVEQ.L #0x39,D7                        | D7 = '9'
        MOVEQ.L #0x0,D0                         | clear D0
        MOVEQ.L #0x0,D1                         | D1 = decimal point seen flag / char count
        MOVEQ.L #0x0,D2                         | D2 = significant digit count
        MOVEQ.L #0x0,D3                         | clear D3
        MOVEQ.L #0x0,D5                         | D5 = exponent
        CLR.L   (A1)                            | Decimal.sgn and Decimal.exp = 0
        MOVE.L  #0x54E3030,(A2)                 | init sig with length 5, 'N', '0', '0'
        MOVE    #0x3131,0x4(A2)                 | init sig with '1', '1'
DECSTR_SKIP_3:
        BSR     DECSTR_SKIP_7                   | read next char
        CMPI.B  #0x20,D0                        | space?
        BEQ.B   DECSTR_SKIP_3                   | skip leading spaces
        CMPI.B  #0xCA,D0                        | option-space (non-breaking space)?
        BEQ.B   DECSTR_SKIP_3                   | skip leading option-spaces
        CMPI.B  #0x9,D0                         | tab?
        BEQ.B   DECSTR_SKIP_3                   | skip leading tabs
        CMPI.B  #0x2B,D0                        | '+' sign?
        BEQ.B   DECSTR_SKIP_4                   | skip positive sign
        CMPI.B  #0x2D,D0                        | '-' sign?
        BNE.B   DECSTR_SKIP_5                   | no sign, start parsing ->
        ADDQ.B  #0x1,(A1)                       | set Decimal.sgn to 1 (negative)
DECSTR_SKIP_4:
        BSR.B   DECSTR_SKIP_7                   | read next char
DECSTR_SKIP_5:
        CMPI.B  #0x30,D0                        | compare with '0'
        BCS.B   DECSTR_SKIP_6                   | less than '0' -> not a digit
        BHI.B   DECSTR_CONT_7                   | greater than '0' -> valid digit 1-9
        BSET    #0xF,D4                         | set flag: leading zero seen
        MOVEQ.L #-0x1,D6                        | mark that we have seen digits
        BSR.B   DECSTR_SKIP_7                   | read next char
        BRA.B   DECSTR_SKIP_5                   | loop to skip all leading zeros

| ----------------------------------------------------------
|
| DECSTR_SKIP_6: Str2Dec - no integer part found, check for decimal point
|
DECSTR_SKIP_6:
        CMPI.B  #0x2E,D0                        | decimal point?
        BEQ     DECSTR_LOOP_3                   | yes -> parse fractional part
        TST     D4                              | check if we saw any zeros
        BPL     DECSTR_ERR_2                    | no zeros, no digits -> parse error
        BRA     DECSTR_ERR                      | zeros seen -> value is 0.0

| ----------------------------------------------------------
|
| DECSTR_CONT_7: Str2Dec - digit > '0' found, accumulate significant digits
|
DECSTR_CONT_7:
        CMPI.B  #0x39,D0                        | compare with '9'
        BLS.B   DECSTR_CONT_8                   | <= '9' -> it's a valid integer digit
        TST     D4                              | check if any leading zeros were seen
        BPL     DECSTR_NO_6                     | no zeros -> might be special (INF/NAN)
        BRA     DECSTR_NO_4                     | zeros seen -> end of number, check exponent

| ----------------------------------------------------------
|
| DECSTR_CONT_8: Str2Dec - accumulate integer digits into decimal record
|
DECSTR_CONT_8:
        MOVEQ.L #-0x1,D6                        | mark that we have seen integer digits
DECSTR_LOOP_2:
        BSR.B   DECSTR_CONT_10                  | accumulate digit
        BCS.B   DECSTR_CONT_9                   | carry set -> overflow or decimal point?
        CMPI.B  #0x39,D0                        | still a digit?
        BLS.B   DECSTR_LOOP_2                   | yes -> loop
DECSTR_CONT_9:
        CMPI.B  #0x2E,D0                        | decimal point?
        BNE     DECSTR_NO_4                     | no -> end of fraction, check exponent
        BSR.B   DECSTR_SKIP_7                   | skip decimal point, read next char
        BCS     DECSTR_ERR                      | carry set -> parse error?
        BRA.B   DECSTR_CONT_14                  | start parsing fractional digits

| ----------------------------------------------------------
|
| DECSTR_CONT_10: store digit into decimal record, advance to next character
| D0 = digit character, D2 = digit count, (A2) = digit buffer
|
DECSTR_CONT_10:
        CMPI.B  #0x13,D2                        | check if we have 19 digits (max precision)
        BLT.B   DECSTR_CONT_11                  | < 19 -> store digit
        BGT.B   DECSTR_CONT_12                  | > 19 -> overflow, adjust exponent
        ADDQ.W  #0x1,D1                         | increment decimal point offset
DECSTR_CONT_11:
        ADDQ.L  #0x1,A2                         | advance digit buffer pointer
        MOVE.B  D0,(A2)                         | store ASCII digit
        ADDQ.B  #0x1,D2                         | increment significant digit count
        BRA.B   DECSTR_SKIP_7                   | read next char

| ----------------------------------------------------------
|
| DECSTR_CONT_12: digit overflow - OR remaining digits to detect rounding
|
DECSTR_CONT_12:
        OR.B    D0,(A2)                         | OR extra digits into last digit (for rounding)
        ADDQ.W  #0x1,D1                         | increment decimal point offset
| DECSTR_SKIP_7 -- read next char.
| Called by: DECSTR_SKIP_3, DECSTR_SKIP_5, DECSTR_CONT_9, DECSTR_CONT_11, DECSTR_LOOP_3 (and 4 more)
DECSTR_SKIP_7:
        TST.L   D4                              | check C-string flag (bit 31)
        BPL.B   DECSTR_NO_3                     | not C-string -> Pascal string read
        MOVE.B  (A0)+,D0                        | C-string: read byte and advance
        BEQ.B   DECSTR_EMPTY                    | null terminator -> end of string
        BRA.B   DECSTR_CONT_13                  | continue

| ----------------------------------------------------------
|
| DECSTR_NO_3: DECSTR_SKIP_7 alternate - read next char from counted string
|
DECSTR_NO_3:
        CMPA.L  A0,A3                           | reached end of Pascal string?
        BLT.B   DECSTR_OK_4                     | yes -> end of string
        MOVE.B  (A0)+,D0                        | Pascal string: read byte and advance
DECSTR_CONT_13:
        CMPI.B  #0x30,D0                        | set flags based on comparison with '0'
        RTS                                     | return

| ----------------------------------------------------------
|
| DECSTR_OK_4: past end of string - set end-of-input flag
|
DECSTR_OK_4:
        ADDQ.L  #0x1,A0                         | advance past end?
DECSTR_EMPTY:
        BSet    #0x10,D4                        | set end-of-string flag
        TST.L   D6                              | have we seen any valid digits?
        BPL     DECSTR_ERR_2                    | no -> parse error
        BRA     DECSTR_ERR                      | yes -> finish parsing

| ----------------------------------------------------------
|
| DECSTR_LOOP_3: Str2Dec - parse fractional digits after decimal point
|
DECSTR_LOOP_3:
        BSR.B   DECSTR_SKIP_7                   | read next char after decimal point
        BEQ.B   DECSTR_OK_5                     | is it '0'?
        BCS.B   DECSTR_SKIP_8                   | < '0' -> not a digit
        CMPI.B  #0x39,D0                        | compare with '9'
        BLS.B   DECSTR_LOOP_4                   | <= '9' -> valid fractional digit
DECSTR_SKIP_8:
        TST     D4                              | check flags
        BPL     DECSTR_ERR_2                    | no digits before point -> parse error
        BRA.B   DECSTR_NO_4                     | digits before point -> check exponent

| ----------------------------------------------------------
|
| DECSTR_OK_5: leading zero after decimal point - decrement exponent
|
DECSTR_OK_5:
        BSet    #0xF,D4                         | set leading zero flag
        MOVEQ.L #-0x1,D6                        | mark digits seen
        SUBQ.W  #0x1,D1                         | decrement exponent (shift point right)
        BRA.B   DECSTR_LOOP_3                   | loop for more leading zeros

| ----------------------------------------------------------
|
| DECSTR_LOOP_4: accumulate fractional digits, adjusting exponent
|
DECSTR_LOOP_4:
        MOVEQ.L #-0x1,D6                        | mark digits seen
        SUBQ.W  #0x1,D1                         | decrement exponent
        BSR.B   DECSTR_CONT_10                  | accumulate fractional digit
        BCS.B   DECSTR_ERR                      | carry set -> end of number
DECSTR_CONT_14:
        CMPI.B  #0x39,D0                        | compare with '9'
        BLS.B   DECSTR_LOOP_4                   | still a digit -> loop
| parse optional exponent ('E' or 'e')
DECSTR_NO_4:
        MOVE.L  A0,D6                           | save position before exponent
        SUBQ.L  #0x1,D6                         | adjust pointer for exponent char
        CMPI.B  #0x45,D0                        | 'E'?
        BEQ.B   DECSTR_OK_6                     | yes, parse exponent ->
        CMPI.B  #0x65,D0                        | 'e'?
        BNE.B   DECSTR_ERR                      | no exponent ->
| exponent: parse optional sign and digit accumulation
DECSTR_OK_6:
        BSR.B   DECSTR_SKIP_7                   | get next char
        CMPI.B  #0x2B,D0                        | '+'?
        BEQ.B   DECSTR_SKIP_9                   | skip sign ->
        CMPI.B  #0x2D,D0                        | '-'?
        BNE.B   DECSTR_NO_5                     | no sign, parse digits ->
        BSET    #0x1F,D2                        | set negative exponent flag
DECSTR_SKIP_9:
        BSR.B   DECSTR_SKIP_7                   | read next char
| exponent digit loop: D5 = D5 * 10 + digit, clamped at 8192
DECSTR_NO_5:
        CMPI.B  #0x30,D0                        | < '0'?
        BCS.B   DECSTR_SKIP_10                  | not a digit ->
        CMPI.B  #0x39,D0                        | > '9'?
        BHI.B   DECSTR_SKIP_10                  | not a digit ->
        MOVEQ.L #-0x1,D6                        | mark valid exponent seen
        ANDI    #0xF,D0                         | ASCII to binary digit
        MULU    #0xA,D5                         | D5 *= 10
        ADD     D0,D5                           | D5 += digit
        CMPI    #0x2000,D5                      | overflow clamp at 8192
        BCS.B   DECSTR_LOOP_5                   | no overflow -> loop
        MOVE    #0x2000,D5                      | clamp exponent magnitude
DECSTR_LOOP_5:
        BRA.B   DECSTR_SKIP_9                   | loop exponent digits

| ----------------------------------------------------------
|
| DECSTR_SKIP_10: exponent parsing done - check if valid digits were found
|
DECSTR_SKIP_10:
        TST.L   D6                              | were any exponent digits seen?
        BPL     DECSTR_ERR_2                    | no -> rollback exponent parsing
DECSTR_ERR:
        SUBQ.L  #0x1,A0                         | back up one character
DECSTR_EXIT_2:
        TST.B   D2                              | any significant digits?
        BNE.B   DECSTR_OK_7                     | yes -> finalize
        TST     D4                              | check flags
        BPL.B   DECSTR_EXIT_3                   | no digits -> return 0
        MOVE    #0x130,(A2)                     | store '0' as significant digit
        BRA.B   DECSTR_EXIT_3                   | finish

| ----------------------------------------------------------
|
| DECSTR_OK_7: finalize decimal record - apply sign, strip trailing zeros
|
DECSTR_OK_7:
        TST.L   D2                              | check exponent sign flag
        BPL.B   DECSTR_EMPTY_2                  | positive ->
        NEG     D5                              | negative -> negate exponent
DECSTR_EMPTY_2:
        CMPI.B  #0x30,0x4(A1,D2.W)              | last digit is '0'?
        BNE.B   DECSTR_DONE_2                   | no -> done stripping zeros
        SUBQ.B  #0x1,D2                         | remove trailing zero
        CMPI.B  #0x13,D2                        | was it the 19th digit?
        BEQ.B   DECSTR_SKIP_11                  | yes -> don't adjust exponent
        ADDQ.W  #0x1,D5                         | adjust exponent for stripped zero
DECSTR_SKIP_11:
        BRA.B   DECSTR_EMPTY_2                  | loop to check next trailing zero

| ----------------------------------------------------------
|
| DECSTR_DONE_2: store digit count and final exponent into decimal record
|
DECSTR_DONE_2:
        MOVE.B  D2,0x4(A1)                      | store significant digit count
        ADD     D1,D5                           | add fractional point offset to exponent
        MOVE    D5,0x2(A1)                      | store final exponent
DECSTR_EXIT_3:
        SUBA.L  0x14(A6),A0                     | calculate parsed character count
        MOVE.L  0x10(A6),A1                     | A1 = Index pointer
        MOVE    A0,(A1)                         | update Index
        MOVE.L  0x4(A6),A0                      | A0 = return address (ValidPrefix logic?)
        MOVE.L  0x8(A6),A1                      | A1 = ValidPrefix pointer
        SWAP    D4                              | get flags
        MOVE.B  D4,(A1)                         | store ValidPrefix result
        MOVEM.L -0x20(A6),D2-D7/A2-A3           | restore regs
        UNLK    A6                              | tear down stack frame
        ADDA    #0x14,SP                        | pop parameters
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| DECSTR_NO_6: Str2Dec - check for special values (INF, NAN) or infinity symbol
|
DECSTR_NO_6:
        CMPI.B  #0xB0,D0                        | infinity symbol (\xB0)?
        BEQ     DECSTR_OK_8                     | yes -> INF
        SUBQ.L  #0x1,A0                         | back up
        MOVEQ.L #0x49,D3                        | D3 = 'I'
        BSR     DECSTR_FOUND_2                  | match 'I'
        BEQ     DECSTR_FOUND                    | matched -> check for INF
        CMPI.B  #0x4E,D0                        | 'N'?
        BNE.B   DECSTR_ERR_2                    | no -> parse error
        MOVEQ.L #0x41,D3                        | D3 = 'A'
        BSR     DECSTR_FOUND_2                  | match 'A'
        BNE.B   DECSTR_ERR_2                    | no -> parse error
        MOVEQ.L #0x4E,D3                        | D3 = 'N'
        BSR     DECSTR_FOUND_2                  | match 'N'
        BNE     DECSTR_ERR_2                    | no -> parse error
        MOVE.L  #0x54E3430,(A2)+                | init NaN payload
        MOVE    #0x3030,(A2)                    | init NaN payload
        MOVE.L  A0,D6                           | save pos
        BSR     DECSTR_SKIP_7                   | read next char
        CMPI.B  #0x28,D0                        | opening '('?
        BNE.B   DECSTR_ERR_2                    | no -> basic NaN
        MOVEQ.L #0x0,D3                         | clear NaN payload accumulator
DECSTR_LOOP_6:
        BSR     DECSTR_SKIP_7                   | read payload digit
        BCS.B   DECSTR_CONT_15                  | carry set -> end of digits
        CMPI.B  #0x39,D0                        | > '9'?
        BHI.B   DECSTR_ERR_2                    | invalid payload digit
        MULU    #0xA,D3                         | payload *= 10
        ANDI    #0xF,D0                         | convert ASCII to binary
        ADD     D0,D3                           | add to payload
        BRA.B   DECSTR_LOOP_6                   | loop

| ----------------------------------------------------------
|
| DECSTR_CONT_15: NAN code parsed - expect closing ')' and encode NaN payload
|
DECSTR_CONT_15:
        CMPI.B  #0x29,D0                        | closing ')'?
        BNE.B   DECSTR_ERR_2                    | no -> parse error
        BSR.B   DECSTR_CONT_18                  | convert high nibble of payload
        ROR     #0x8,D0                         | shift
        ROR.B   #0x4,D3                         | shift
        BSR.B   DECSTR_CONT_18                  | convert low nibble of payload
        ROR     #0x8,D0                         | shift
        MOVE    D0,(A2)                         | store NaN payload
        BRA.B   DECSTR_CONT_16                  | finish

| ----------------------------------------------------------
|
| DECSTR_ERR_2: Str2Dec - backtrack on parse failure, restart from saved position
|
DECSTR_ERR_2:
        MOVE.L  D6,A0                           | restore saved string pointer
        BRA     DECSTR_EXIT_2                   | return partial match

| ----------------------------------------------------------
|
| DECSTR_FOUND: matched 'I' - check for 'INF' (infinity)
|
DECSTR_FOUND:
        MOVEQ.L #0x4E,D3                        | D3 = 'N'
        BSR.B   DECSTR_FOUND_2                  | match 'N'
        BNE.B   DECSTR_ERR_2                    | no -> parse error
        MOVEQ.L #0x46,D3                        | D3 = 'F'
        BSR.B   DECSTR_FOUND_2                  | match 'F'
        BNE.B   DECSTR_ERR_2                    | no -> parse error
DECSTR_OK_8:
        MOVE    #0x149,(A2)                     | store 'I' for INF
DECSTR_CONT_16:
        MOVEQ.L #-0x1,D6                        | mark success
        TST.L   D4                              | check flags
        BPL.B   DECSTR_CONT_17                  | Pascal string -> check length
        MOVE.B  (A0),D0                         | C-string -> read char
        BNE     DECSTR_EXIT_3                   | not null -> return
        BRA.B   DECSTR_EMPTY_3                  | null -> set EOF flag

| ----------------------------------------------------------
|
| DECSTR_CONT_17: check for end of counted string after special value
|
DECSTR_CONT_17:
        CMPA.L  A0,A3                           | check if at end of Pascal string
        BGE     DECSTR_EXIT_3                   | not at end -> return
DECSTR_EMPTY_3:
        BSet    #0x10,D4                        | set EOF flag
        BRA     DECSTR_EXIT_3                   | return

| ----------------------------------------------------------
|
| DECSTR_FOUND_2: read next char, convert lowercase to uppercase, compare with D3
| Used for case-insensitive matching of 'INF', 'NAN' strings
|
DECSTR_FOUND_2:
        BSR     DECSTR_SKIP_7                   | read char
        CMPI.B  #0x61,D0                        | compare with 'a'
        BCS.B   DECSTR_NO_7                     | < 'a' -> not lowercase
        CMPI.B  #0x7A,D0                        | compare with 'z'
        BHI.B   DECSTR_NO_7                     | > 'z' -> not lowercase
        SUBI.B  #0x20,D0                        | convert to uppercase
DECSTR_NO_7:
        CMP.B   D3,D0                           | compare with target char
        RTS                                     | return

| ----------------------------------------------------------
|
| DECSTR_CONT_18: convert nibble (0-15) from D3 to hex ASCII digit in D0
|
DECSTR_CONT_18:
        MOVE.B  #0xF,D0                         | mask
        AND.B   D3,D0                           | get nibble
        CMPI.B  #0x9,D0                         | compare with 9
        BLS.B   DECSTR_CONT_19                  | <= 9 -> digit
        ADDQ.B  #0x7,D0                         | adjust for A-F
DECSTR_CONT_19:
        ADDI.B  #0x30,D0                        | convert to ASCII
        RTS                                     | return

| ----------------------------------------------------------
|
| STACK: Dec2Str entry - format decimal record as ASCII string
| Stack: DecForm ptr, Decimal record ptr, string ptr, index ptr
|
STACK:
        MOVEM.L D2-D5,-(SP)                     | save work registers
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  0x20(A6),A0                     | A0 = ptr to DecForm record
        MOVE.L  (A0),D5                         | D5 = DecForm (style + digits)
        MOVE.L  0x18(A6),A0                     | A0 = output string ptr
        MOVE.L  0x1C(A6),A1                     | A1 = Decimal record ptr
        MOVE.L  (A1)+,D4                        | D4 = sign + exponent from Decimal
        ADDQ.W  #0x1,A0                         | skip string length byte
        MOVEQ.L #-0x50,D2                       | D2 = char count (starts negative)
        MOVEQ.L #0x0,D1                         | clear digit count
        MOVE.B  (A1)+,D1                        | D1 = significant digit count
        BEQ.B   DECSTR_EMPTY_4                  | zero digits = special value ->
        BTST    #0x18,D4                        | negative sign bit set?
        BEQ.B   DECSTR_NO_8                     | no, positive ->
        MOVE.B  #0x2D,(A0)+                     | write '-' sign
        BRA.B   DECSTR_CONT_20                  | -> continue formatting

| ----------------------------------------------------------
|
| DECSTR_NO_8: positive number - emit leading space if fixed-format
|
DECSTR_NO_8:
        BTst    #0x18,D5                        | fixed-format style?
        BNE.B   DECSTR_OK_9                     | yes, no leading space ->
        MOVE.B  #0x20,(A0)+                     | write ' ' for positive in sci format
DECSTR_CONT_20:
        ADDQ.W  #0x1,D2                         | count sign/space character
DECSTR_OK_9:
        MOVE.B  (A1),D0                         | D0 = first digit char
        CMPI.B  #0x3F,D0                        | '?' = missing/zero value?
DECSTR_EMPTY_4:
        BEQ     DECSTR_EMPTY_5                  | yes, format zero ->
        ORI.B   #0x20,D0                        | convert to lowercase for compare
        CMPI.B  #0x69,D0                        | 'i' = infinity?
        BEQ     DECSTR_OK_14                    | yes, format "INF" ->
        CMPI.B  #0x6E,D0                        | 'n' = NaN?
        BNE.B   DECSTR_NO_10                    | no, format normal number ->
        MOVE.B  #0x4E,(A0)+                     | write 'N'
        MOVE.B  #0x41,(A0)+                     | write 'A'
        MOVE.B  #0x4E,(A0)+                     | write 'N'
        MOVE.B  #0x28,(A0)+                     | write '('
        MOVE.B  #0x29,0x3(A0)                   | write ')' at end
        ADDQ.W  #0x5,D2                         | count "NAN()" = 5 chars
        MOVEQ.L #0x0,D3                         | clear NaN code accumulator
        CMPI.B  #0x5,D1                         | more than 5 NaN code digits?
        BLE.B   DECSTR_NO_9                     | no ->
        MOVEQ.L #0x5,D1                         | clamp to 5 digits max
DECSTR_NO_9:
        BSR.B   DECSTR_CONT_21                  | get high nibble of NaN code
        MOVE.L  D3,D0                           | save in D0
        BSR.B   DECSTR_CONT_21                  | get low nibble
        ASL.B   #0x4,D3                         | shift low nibble to high position
        OR.L    D0,D3                           | combine into NaN payload byte
DECSTR_DONE_3:
        MOVEQ.L #0x4,D0                         | 4 chars for NaN hex digits
        BRA.B   DECSTR_CONT_25                  | -> write hex digits to output

| DECSTR_CONT_21 -- get high nibble of NaN code.
| ----------------------------------------------------------
|
| DECSTR_CONT_21
|
DECSTR_CONT_21:
        SUBQ.W  #0x1,D1                         | decrement digit index
        BLE.B   DECSTR_DONE_3                   | no more digits, done ->
        MOVE.B  0x0(A1,D1.W),D3                 | get digit from decimal record
        CMPI.B  #0x39,D3                        | ASCII digit <= '9'?
        BLE.B   DECSTR_OK_10                    | yes, numeric ->
        SUBQ.B  #0x7,D3                         | adjust hex letter (A-F) offset
DECSTR_OK_10:
        ANDI.B  #0xF,D3                         | mask to 4-bit nibble value
        RTS                                     | return

| ----------------------------------------------------------
|
| DECSTR_NO_10: Dec2Str - format normal number (not INF/NAN)
|
DECSTR_NO_10:
        CMPI.B  #0x30,(A1)                      | first digit is '0'?
        BNE.B   DECSTR_NO_11                    | no ->
        MOVEQ.L #0x1,D1                         | force 1 digit ("0")
        MOVEQ.L #0x0,D4                         | clear exponent
DECSTR_NO_11:
        BTst    #0x18,D5                        | fixed-format style?
        BNE     DECSTR_OK_12                    | yes, use fixed format ->
        TST     D5                              | scientific digits > 0?
        BGT.B   DECSTR_OK_11                    | yes ->
        MOVEQ.L #0x1,D5                         | at least 1 digit in mantissa
DECSTR_OK_11:
        MOVEQ.L #0x1,D0                         | copy 1 leading digit
        BSR.B   DECSTR_CONT_28                  | write first significant digit
        MOVE    D1,D3                           | D3 = digit count
        EXT.L   D3                              | sign-extend for exponent calc
        SUBQ.L  #0x1,D3                         | D3 = digits after first
        BGT.B   DECSTR_CONT_22                  | more digits after point ->
        CMPI    #0x1,D5                         | requested only 1 sig digit?
        BLE.B   DECSTR_SKIP_12                  | yes, skip decimal point ->
DECSTR_CONT_22:
        BSR.B   DECSTR_CONT_29                  | write '.' decimal point
        MOVE    D3,D0                           | D0 = remaining significant digits
        BSR.B   DECSTR_CONT_28                  | copy remaining digits to output
        MOVE    D5,D0                           | D0 = total digits requested
        SUB     D1,D0                           | D0 = trailing zeros needed
        BSR.B   DECSTR_CONT_30                  | pad with '0' chars
DECSTR_SKIP_12:
        ADDQ.W  #0x2,D2                         | account for 'e' and sign chars
        BGT.B   DECSTR_EMPTY_5                  | output overflow ->
        MOVE.B  #0x65,(A0)+                     | write 'e' exponent indicator
        EXT.L   D4                              | sign-extend exponent
        ADD.L   D4,D3                           | D3 = final base-10 exponent
        BLT.B   DECSTR_CONT_23                  | negative exponent ->
        MOVE.B  #0x2B,(A0)+                     | write '+' exponent sign
        BRA.B   DECSTR_CONT_24                  | -> format exponent digits

| ----------------------------------------------------------
|
| DECSTR_CONT_23: negative exponent in scientific notation
|
DECSTR_CONT_23:
        MOVE.B  #0x2D,(A0)+                     | write '-' exponent sign
        NEG.L   D3                              | make exponent positive for output
DECSTR_CONT_24:
        MOVEQ.L #0x0,D0                         | start at lowest power-of-10 table entry
DECSTR_CONT_25:
        LEA.L   DECSTR_CONT_33(PC),A1           | A1 = powers-of-10 table (10,100,1000,...)
DECSTR_NEXT:
        ADDQ.W  #0x2,D0                         | advance to next power of 10
        CMP     -0x2(A1,D0.W),D3                | value >= this power?
        BCS.B   DECSTR_SKIP_13                  | no, skip this digit position ->
        CMPI.B  #0x8,D0                         | checked all 4 table entries?
        BLT.B   DECSTR_NEXT                     | no, try next ->
DECSTR_CONT_26:
        DIVU    -0x2(A1,D0.W),D3                | D3 quotient = digit, remainder stays
DECSTR_CONT_27:
        ADDQ.W  #0x1,D2                         | count output character
        BGT.B   DECSTR_EMPTY_5                  | output overflow ->
        ADDI    #0x30,D3                        | convert digit to ASCII
        MOVE.B  D3,(A0)+                        | write digit
        SWAP    D3                              | D3 = remainder for next digit
        EXT.L   D3                              | sign-extend remainder
DECSTR_SKIP_13:
        SUBQ.W  #0x2,D0                         | move to next lower power
        BGT.B   DECSTR_CONT_26                  | more powers -> divide
        BEQ.B   DECSTR_CONT_27                  | ones digit -> just output
        BRA.B   DECSTR_DONE_4                   | done -> finalize string

| ----------------------------------------------------------
|
| DECSTR_CONT_28: copy D0 digits from (A1)+ to (A0)+, checking output overflow
|
| Called by: DECSTR_OK_11, DECSTR_CONT_22, DECSTR_OK_12, DECSTR_OK_13, DECSTR_CONT_32
DECSTR_CONT_28:
        BLE.B   DECSTR_EXIT_4                   | no digits to copy -> return
        ADD     D0,D2                           | update output char count
        BGT.B   DECSTR_EMPTY_5                  | output overflow ->
DECSTR_LOOP_7:
        MOVE.B  (A1)+,(A0)+                     | copy digit to output
        SUBQ.W  #0x1,D0                         | decrement digit count
        BGT.B   DECSTR_LOOP_7                   | more digits -> loop
DECSTR_EXIT_4:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DECSTR_CONT_29: emit decimal point '.' to output
|
DECSTR_CONT_29:
        ADDQ.W  #0x1,D2                         | count '.' character
        BGT.B   DECSTR_EMPTY_5                  | output overflow ->
        MOVE.B  #0x2E,(A0)+                     | write '.' decimal point
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DECSTR_LOOP_8: emit '0' padding characters, decrement count
|
DECSTR_LOOP_8:
        ADDQ.W  #0x1,D2                         | count '0' padding char
        BGT.B   DECSTR_EMPTY_5                  | output overflow ->
        MOVE.B  #0x30,(A0)+                     | write '0' pad character
| DECSTR_CONT_30 -- pad with '0' chars.
DECSTR_CONT_30:
        SUBQ.W  #0x1,D0                         | decrement pad count
        BGE.B   DECSTR_LOOP_8                   | more padding needed -> loop
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DECSTR_EMPTY_5: output overflow - string too long, return '?' error
|
DECSTR_EMPTY_5:
        MOVE.L  0x18(A6),A0                     | A0 = output string ptr
        MOVE    #0x13F,(A0)                     | store "?" overflow error marker
        BRA.B   DECSTR_EXIT_5                   | -> clean up and return

| ----------------------------------------------------------
|
| DECSTR_OK_12: Dec2Str fixed-format output (exponent = decimal places)
|
DECSTR_OK_12:
        MOVE    D1,D3                           | D3 = significant digit count
        ADD     D4,D3                           | D3 = digits before decimal point
        BLE.B   DECSTR_CONT_31                  | all digits after point ->
        TST     D4                              | exponent >= 0?
        BGE.B   DECSTR_OK_13                    | yes, no fractional part in digits ->
        MOVE    D3,D0                           | D0 = integer part digit count
        BSR.B   DECSTR_CONT_28                  | write integer part digits
        BSR.B   DECSTR_CONT_29                  | write '.' decimal point
        MOVEQ.L #0x0,D0                         | compute fractional digit count
        SUB     D4,D0                           | D0 = -exponent = fractional digits
        BRA.B   DECSTR_CONT_32                  | -> write fractional digits

| ----------------------------------------------------------
|
| DECSTR_OK_13: fixed-format with positive exponent - digits, zeros, then decimal
|
DECSTR_OK_13:
        MOVE    D1,D0                           | D0 = all significant digits
        BSR.B   DECSTR_CONT_28                  | write all significant digits
        MOVE    D4,D0                           | D0 = trailing zeros count
        BSR.B   DECSTR_CONT_30                  | pad with trailing zeros
        MOVE    D5,D0                           | D0 = decimal places requested
        BLE.B   DECSTR_DONE_4                   | none requested -> done
        BSR.B   DECSTR_CONT_29                  | write '.' decimal point
        BSR.B   DECSTR_CONT_30                  | pad decimal places with zeros
        BRA.B   DECSTR_DONE_4                   | -> finalize string

| ----------------------------------------------------------
|
| DECSTR_CONT_31: fixed-format with leading zeros (number < 1.0): "0.00...digits"
|
DECSTR_CONT_31:
        MOVEQ.L #0x1,D0                         | write "0" before decimal point
        BSR.B   DECSTR_CONT_30                  | write leading '0'
        BSR.B   DECSTR_CONT_29                  | write '.' decimal point
        MOVEQ.L #0x0,D0                         | compute leading zero count
        SUB     D3,D0                           | D0 = zeros before first sig digit
        BSR.B   DECSTR_CONT_30                  | pad with leading fractional zeros
        MOVE    D1,D0                           | D0 = significant digits to copy
DECSTR_CONT_32:
        BSR.B   DECSTR_CONT_28                  | write significant fractional digits
        MOVE    D4,D0                           | D0 = exponent
        ADD     D5,D0                           | D0 = trailing zeros to fill
        BSR.B   DECSTR_CONT_30                  | pad remaining decimal places
DECSTR_DONE_4:
        MOVE.L  0x18(A6),A0                     | A0 = output string base
        ADDI    #0x50,D2                        | convert count to string length
        MOVE.B  D2,(A0)                         | store Pascal string length byte
DECSTR_EXIT_5:
        UNLK    A6                              | tear down stack frame
        MOVEM.L (SP)+,D2-D5/A0                  | restore regs + return addr in A0
        ADDA    #0xC,SP                         | pop 3 parameters (12 bytes)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| DECSTR_OK_14: Dec2Str - output "INF" for infinity
|
DECSTR_OK_14:
        MOVE.B  #0x49,(A0)+                     | write 'I'
        MOVE.B  #0x4E,(A0)+                     | write 'N'
        MOVE.B  #0x46,(A0)                      | write 'F'
        ADDQ.W  #0x3,D2                         | count 3 chars for "INF"
        BRA.B   DECSTR_DONE_4                   | -> finalize string

| ----------------------------------------------------------
|
| DECSTR_CONT_33: powers of 10 table for exponent digit extraction
| 10, 100, 1000, 10000
|
DECSTR_CONT_33:
  .byte  0x00,0x0A,0x00,0x64,0x03,0xE8          | 10, 100, 1000
  .byte 0x27,0x10                               | 10000

| end of resource : 'PACK' 7

| resource header
  .long 0xC0001066                              | Length
  .long 0x00000078                              | ?
