| =========================================================================
| PACK 7 -- the Binary-Decimal Conversion Package (Apple: Pkg7, BinDec.a)
| =========================================================================
| ROM offsets +0x1C9D8..+0x1CF25: the 8-byte header of the ROM resource at
| +0x1C9D8, then the package, $546 bytes from +0x1C9E0 (_PACK_7_ in
| MacPlusROM.lst) on; type PACK, ID 7, no name, attributes $58 (resSysHeap,
| resLocked, resProtected). The same in all three Plus ROMs, and byte for
| byte the PACK 7 of the SE ROMs (src/se/resources/res_pack_7.s).
|
| Version 1 (header word; Apple's change history: LAK 13 Nov 83, JTC
| 15 Jan 85, KLH 19 Aug 85 added the SANE scanner and formatter). The
| code follows Apple's System 7.1 sources BinDec.a, Str2Dec.a and
| Dec2Str.a line by line; this 1986 version masks the string pointer in
| Str2Dec with Lo3Bytes where the 1989 source (v1.2, "32 bit clean")
| calls _StripAddress.
|
| Entry: _Pack7 ($A9EE) with a selector word on the stack (above the
| return address); the package removes it:
|   0  NumToString   (LBin2Dec, IM I-489): D0.L = number, A0 = string:
|                    the decimal Pascal string, '-' only if negative; all
|                    registers preserved.
|   1  StringToNum   (LDec2Bin, IM I-490): A0 = Pascal string -> D0.L,
|                    optional '+'/'-', no overflow check (modulo 2^32),
|                    no check for digits either (low 4 bits of each
|                    character).
|   2  PStr2Dec      (_pstr2dec)  SANE scanner, Pascal calling convention:
|   4  CStr2Dec      (_cstr2dec)    (s: Pascal string / C string pointer;
|                                   VAR index: INTEGER; VAR d: Decimal;
|                                   VAR validPrefix: BOOLEAN): scan a number
|                                   from s[index] into the decimal record d,
|                                   advance index past it; validPrefix TRUE
|                                   if the string ended inside a number.
|   3  Dec2Str       (_dec2str)   SANE formatter: (f: DecForm (by
|                                   address); d: Decimal (by address);
|                                   VAR s: DecStr): d as a string, at most
|                                   80 characters, '?' if it does not fit.
|   other selectors: return at once.
| Decimal record: sgn (word, high byte 0/1), exp (word), sig (string[20]:
| up to 19 digits plus a 20th that records lost digits; 'I' infinity,
| 'N' + hex digits a NaN, '0' zero, '?' an unrepresentable value).
| DecForm: style (word, high byte: 0 FloatDecimal, 1 FixedDecimal) and
| digits (word).
|
| Labels: Apple's names with the prefix DECSTR_ (the Str2Dec states
| DECSTR_STATE0 ... DECSTR_STATE99, DECSTR_GETCHAR, ...); the targets of
| Apple's local labels are DECSTR_<label>_<n> for the @n that follows
| that label (e.g. DECSTR_SELECT2_2).
| Sources: Apple's BinDec.a, Str2Dec.a, Dec2Str.a (Mac OS 7.1 tree,
| Toolbox/SANE), Inside Macintosh I-487..I-491 (Binary-Decimal Conversion
| Package), the Apple Numerics Manual (SANE).
| =========================================================================

| -------------------------------------------------------------------------
| ROM resource header: a Memory Manager style block header (tag $C0 and
| the physical size, then a relative-handle field) in front of the
| resource data, as for every ROM resource.
| -------------------------------------------------------------------------
    ROM_RESOURCE PACK_7                         | 8-byte resource header (include/romrsrc.inc)
| -------------------------------------------------------------------------
| Package header: branch to the entry, flags word, 'PACK', ID, version.
| -------------------------------------------------------------------------
_PACK_7_:
        BRA.B   DECSTR_PKG7_ENTRY               | skip the package header to the selector test
        .short  0x0000                          | flags word
        .ascii  "PACK"                          | resource type
        .short  0x0007                          | resource ID 7
        .short  0x0001                          | version 1
| -------------------------------------------------------------------------
| Pkg7 entry: selector at 4(SP). Selector 0 (NumToString) falls through.
| -------------------------------------------------------------------------
DECSTR_PKG7_ENTRY:
        SUBQ.W  #0x1,0x4(SP)                    | selector - 1: negative only for 0 (NumToString)
        BPL.B   STRINGTONUM                     | selector 1-4 ->
| selector 0 -- NumToString (Apple LBIN2DEC): D0.L to a decimal Pascal
| string at A0, leading zeros suppressed ("0" for zero); all registers
| are preserved.
        MOVE.L  (SP),0x2(SP)                    | return address over the selector word
        ADDQ.W  #0x2,SP                         | pop the selector
        MOVEM.L D0-D6/A1,-(SP)                  | save D0-D6/A1: NumToString preserves all registers
| convert binary to 10-digit BCD using repeated add-with-carry
        MOVEQ.L #0x0,D1                         | D1.B..D5.B: 10 BCD digits, 2 per byte
        MOVEQ.L #0x0,D2                         | clear BCD digit pair 2
        MOVEQ.L #0x0,D3                         | clear BCD digit pair 3
        MOVEQ.L #0x0,D4                         | clear BCD digit pair 4
        MOVEQ.L #0x0,D5                         | clear BCD digit pair 5
        MOVEQ.L #0x1F,D6                        | 32 bits to convert
        LEA.L   0x1(A0),A1                      | A1 = output string (past length byte)
| check sign
        TST.L   D0                              | positive?
        BGT.B   DECSTR_BDPOSVAL                 | yes ->
        BMI.B   DECSTR_BDNEGVAL                 | negative ->
        MOVE.B  #0x30,(A1)+                     | zero: write '0'
        BRA.B   DECSTR_BDFIN                    | -> done
| negative: write '-' sign and negate
DECSTR_BDNEGVAL:
        MOVE.B  #0x2D,(A1)+                     | write '-'
        NEG.L   D0                              | make positive
| shift-and-add BCD conversion: 32 iterations of double-dabble
DECSTR_BDPOSVAL:
        ADD.L   D0,D0                           | shift MSB into carry
        ABCD    D5,D5                           | D5 := 2 * D5 + X (BCD), the carry into D4
        ABCD    D4,D4                           | BCD double digit pair 4
        ABCD    D3,D3                           | BCD double digit pair 3
        ABCD    D2,D2                           | BCD double digit pair 2
        ABCD    D1,D1                           | D1:D2:D3:D4:D5 = 10-digit BCD
        DBF.W   D6,DECSTR_BDPOSVAL              | 32 times; D6.W ends as $FFFF: skip leading zeros
| convert BCD digits to ASCII and store
        BSR.B   DECSTR_BD1OUT                   | convert D1 (2 digits) -> ASCII
        MOVE.B  D2,D1                           | load BCD digit pair 2
        BSR.B   DECSTR_BD1OUT                   | convert D2
        MOVE.B  D3,D1                           | load BCD digit pair 3
        BSR.B   DECSTR_BD1OUT                   | convert D3
        MOVE.B  D4,D1                           | load BCD digit pair 4
        BSR.B   DECSTR_BD1OUT                   | convert D4
        MOVE.B  D5,D1                           | convert D5
        BSR.B   DECSTR_BD1OUT                   | convert D5 to ASCII digits
DECSTR_BDFIN:
        MOVE.W  A1,D0                           | D0 = end of string pointer
        SUB.W   A0,D0                           | D0 = string length + 1
        SUBQ.B  #0x1,D0                         | D0 = string length
        MOVE.B  D0,(A0)                         | store Pascal string length byte
        MOVEM.L (SP)+,D0-D6/A1                  | restore registers
        RTS                                     | return from NumToString (LBin2Dec): Pascal string at A0
| ----------------------------------------------------------
|
| DECSTR_BD1OUT
|
| DECSTR_BD1OUT: convert BCD byte pair to two ASCII digits
| D1 = packed BCD byte, outputs to (A1)+
| D6 bit 15: leading-zero suppression flag
| Called by: DECSTR_BDPOSVAL
DECSTR_BD1OUT:
        ROR.W   #0x4,D1                         | get high nibble
        BSR.B   DECSTR_BD1DIGOUT                | output high digit
        ROL.W   #0x4,D1                         | get low nibble
| DECSTR_BD1DIGOUT: output one BCD digit as ASCII (with leading zero suppression)
DECSTR_BD1DIGOUT:
        TST.W   D6                              | suppressing leading zeros?
        BPL.B   DECSTR_BDDOIT                   | no, always output ->
        TST.B   D1                              | digit is zero?
        BEQ.B   DECSTR_BDSKIPIT                 | yes, suppress it ->
        MOVEQ.L #0x0,D6                         | first nonzero: stop suppressing
DECSTR_BDDOIT:
        ORI.B   #0x30,D1                        | convert BCD to ASCII ('0'=$30)
        MOVE.B  D1,(A1)+                        | output digit
        SUB.B   D1,D1                           | clear for next digit
DECSTR_BDSKIPIT:
        RTS                                     | return: digit stored, or leading zero skipped (BD1OUT)
| ----------------------------------------------------------
|
| STRINGTONUM (Apple select1) -- selectors 1-4: pop the selector word;
| selector 1 falls into StringToNum, 2-4 go to DECSTR_SELECT2.
STRINGTONUM:
        MOVE.W  0x4(SP),D0                      | D0 = selector - 1 (decremented at the entry)
        MOVE.L  (SP),0x2(SP)                    | return address over the selector word
        ADDQ.W  #0x2,SP                         | pop the selector
        SUBQ.W  #0x1,D0                         | D0 = selector - 2: negative for 1 (StringToNum)
        BPL.B   DECSTR_SELECT2                  | selector 2-4: SANE string routines ->
| selector 1 -- StringToNum (Apple LDEC2BIN): the Pascal string at A0
| (optional sign, digits) to D0.L, modulo 2^32; A0 preserved.
        MOVEM.L D1-D3/A0,-(SP)                  | save regs
        MOVEQ.L #0x0,D0                         | clear result
        MOVEQ.L #0x0,D1                         | clear D1
        MOVEQ.L #0x0,D3                         | clear sign flag
        MOVE.B  (A0)+,D2                        | D2 = Pascal string length
        BEQ.B   DECSTR_DBFIN                    | empty string -> return 0
| check for leading sign character
        CMPI.B  #0x2B,(A0)                      | '+' ?
        BEQ.B   DECSTR_DBPOSSIGN                | yes, skip it ->
        CMPI.B  #0x2D,(A0)                      | '-' ?
        BNE.B   DECSTR_DBNOSIGN                 | no sign, start digits ->
        MOVEQ.L #0x1,D3                         | D3 = negative flag
DECSTR_DBPOSSIGN:
        ADDQ.L  #0x1,A0                         | skip sign character
        SUBQ.B  #0x1,D2                         | one fewer character
        BEQ.B   DECSTR_DBFIN                    | empty after sign ->
| digit loop: D0 = D0 * 10 + digit (using shifts: *10 = *2 + *8)
DECSTR_DBNOSIGN:
        MOVEQ.L #0xF,D1                         | mask for ASCII digit
        AND.B   (A0)+,D1                        | D1 = digit value (0-9)
        ADD.L   D0,D0                           | D0 * 2
        ADD.L   D0,D1                           | D1 = D0*2 + digit
        LSL.L   #0x2,D0                         | D0 * 8 (was *2, now *8)
        ADD.L   D1,D0                           | D0 = D0*8 + D0*2 + digit = D0*10 + digit
        SUBQ.B  #0x1,D2                         | more digits?
        BNE.B   DECSTR_DBNOSIGN                 | yes ->
| apply sign
        TST.B   D3                              | negative?
        BEQ.B   DECSTR_DBFIN                    | no ->
        NEG.L   D0                              | negate result
DECSTR_DBFIN:
        MOVEM.L (SP)+,D1-D3/A0                  | restore regs
        RTS                                     | return from StringToNum (LDec2Bin): D0 = the value
| ----------------------------------------------------------
|
| DECSTR_SELECT2
|
| PACK 7 extended dispatch: selector 2=PStr2Dec, 3=Dec2Str, 4=CStr2Dec
DECSTR_SELECT2:
        SUBQ.W  #0x1,D0                         | D0 = selector - 3
        BMI.B   DECSTR_SELECT2_2                | selector 2: PStr2Dec ->
        BEQ.B   DEC2STR                         | selector 3: Dec2Str ->
        CMPI.W  #0x1,D0                         | selector 4: CStr2Dec?
        BEQ.B   DECSTR_SELECT2_4                | yes ->
        RTS                                     | selector > 4: return, selector word already popped
| selector 2: PStr2Dec
DECSTR_SELECT2_2:
        JMP     DECSTR_PSTR2DEC                 | -> _pstr2dec
| selector 3: Dec2Str
DEC2STR:
        JMP     DEC2STR_ENTRY                   | -> _dec2str
| selector 4: CStr2Dec
DECSTR_SELECT2_4:
        JMP     CSTR2DEC                        | -> _cstr2dec
| ----------------------------------------------------------
| CSTR2DEC -- _cstr2dec: PROCEDURE CStr2Dec(s: CStrPtr; VAR index:
| INTEGER; VAR d: Decimal; VAR validPrefix: BOOLEAN): scan the C string
| (NUL-terminated) s from s[index]. Sets the C-string flag (bit 31 of
| D1) and joins the Pascal entry (Apple Str2Dec.a).
CSTR2DEC:
        MOVEQ.L #0x1,D1                         | C string flag (FLCSTRING) ...
        ROR.L   #0x1,D1                         | ... in bit 31 of D1
        BRA.B   DECSTR_START                    | -> the common scanner (Start)
| ----------------------------------------------------------
| DECSTR_CONT_5 -- _pstr2dec: PROCEDURE PStr2Dec(s: DecStr; VAR index:
| INTEGER; VAR d: Decimal; VAR validPrefix: BOOLEAN): scan the Pascal
| string s from s[index] into the decimal record d (a finite state
| scanner: State0 blanks, State1 sign, State2 leading zeros, State4
| integer digits, State6/7 fraction, State8 exponent, State99 INF/NaN).
| d starts as a signaling NaN ('N0011') so that it is valid even if
| nothing is accepted; index ends one past the last character accepted.
| Registers: A0 next character, A3 last character (Pascal), A1 d, A2
| last digit stored in d.sig, D0 character, D1 lost digits - fraction
| digits, D2.B digit count (bit 31 exponent sign), D4 flags (bit 31 C
| string, bit 15 a zero seen, bit 16 validPrefix), D5 exponent, D6
| fallback character pointer (-1 = none), D7 '9'.
DECSTR_PSTR2DEC:
        MOVEQ.L #0x0,D1                         | bit 31 of D1 clear: Pascal string
| DECSTR_START: common part of PStr2Dec and CStr2Dec.
DECSTR_START:
        LINK    A6,#0x0                         | frame: 8(A6) validPrefix, 12 d, 16 index, 20 s
        MOVEM.L D2-D7/A2-A3,-(SP)               | save D2-D7/A2-A3 (at -32(A6))
        MOVEM.L 0xC(A6),D4-D6                   | D4 = &d, D5 = &index, D6 = &s
        AND.L   (Lo3Bytes).W,D6                 | strip the high byte of &s (7.1 source: _StripAddress)
        MOVEA.L D6,A0                           | A0 = s
        MOVEA.L D5,A1                           | A1 = &index
        MOVEQ.L #0x0,D6                         | D6 := 0, for the length byte
        MOVE.B  (A0),D6                         | D6 = length of s (Pascal)
        LEA.L   0x0(A0,D6.W),A3                 | A3 = &s + length = the last character
        ADDA.W  (A1),A0                         | A0 = &s + index: the first character
        MOVE.L  A0,D6                           | D6 = fallback pointer: the start
        MOVEA.L D4,A1                           | A1 = d
        LEA.L   0x4(A1),A2                      | A2 = d.sig (length byte)
        MOVE.L  D1,D4                           | D4 bit 31 = C string flag
        ADDI.B  #0x30,D4                        | D4.B := '0'
        MOVEQ.L #0x39,D7                        | D7 := '9'
        MOVEQ.L #0x0,D0                         | D0 := 0: character
        MOVEQ.L #0x0,D1                         | D1 := 0: lost digits - fraction digits
        MOVEQ.L #0x0,D2                         | D2 := 0: digit count, bit 31 exponent sign
        MOVEQ.L #0x0,D3                         | D3 := 0: NaN code / match character
        MOVEQ.L #0x0,D5                         | D5 := 0: exponent
        CLR.L   (A1)                            | d.sgn := 0, d.exp := 0
        MOVE.L  #0x54E3030,(A2)                 | d.sig := 'N0011', a signaling NaN: length 5, 'N00' ...
        MOVE.W  #0x3131,0x4(A2)                 | ... '11'
DECSTR_STATE0:
        BSR.W   DECSTR_GETCHAR                  | State0: next character (GetChar)
        CMPI.B  #0x20,D0                        | space?
        BEQ.B   DECSTR_STATE0                   | skip leading spaces
        CMPI.B  #0xCA,D0                        | option-space (non-breaking space)?
        BEQ.B   DECSTR_STATE0                   | skip leading option-spaces
        CMPI.B  #0x9,D0                         | tab?
        BEQ.B   DECSTR_STATE0                   | skip leading tabs
        CMPI.B  #0x2B,D0                        | State1: '+'?
        BEQ.B   DECSTR_STATE1_1                 | skip positive sign
        CMPI.B  #0x2D,D0                        | '-' sign?
        BNE.B   DECSTR_STATE2                   | no sign, start parsing ->
        ADDQ.B  #0x1,(A1)                       | d.sgn := 1: minus
DECSTR_STATE1_1:
        BSR.B   DECSTR_GETCHAR                  | read next char
DECSTR_STATE2:
        CMPI.B  #0x30,D0                        | State2: leading '0'?
        BCS.B   DECSTR_STATE2_1                 | below '0': '.' or the end ->
        BHI.B   DECSTR_STATE2_2                 | above '0': digit or letter ->
        BSET    #0xF,D4                         | a zero has been seen (FLZERO)
        MOVEQ.L #-0x1,D6                        | no fallback pointer: the current one is valid
        BSR.B   DECSTR_GETCHAR                  | next character
        BRA.B   DECSTR_STATE2                   | skip all leading zeros
| ----------------------------------------------------------
| DECSTR_STATE2_1 (Apple State2 @1): a character below '0', maybe after
| leading zeros: '.' starts the fraction; after zeros the number is 0;
| otherwise there is no number.
DECSTR_STATE2_1:
        CMPI.B  #0x2E,D0                        | '.'?
        BEQ.W   DECSTR_STATE6                   | yes: fraction before any nonzero digit (State6) ->
        TST.W   D4                              | a zero seen (bit 15)?
        BPL.W   DECSTR_STATEBACKUP              | no: no number here, back up ->
        BRA.W   DECSTR_STATENUM                 | yes: the number is 0 (StateNum) ->
| ----------------------------------------------------------
| DECSTR_STATE2_2 (Apple State2 @2): a character above '0': a digit, or
| after leading zeros the end of the digits, else perhaps INF or NaN.
DECSTR_STATE2_2:
        CMPI.B  #0x39,D0                        | compare with '9'
        BLS.B   DECSTR_STATE4                   | a digit 1-9: integer digits (State4) ->
        TST.W   D4                              | leading zeros seen?
        BPL.W   DECSTR_STATE99                  | no: perhaps INF or NaN (State99) ->
        BRA.W   DECSTR_STATE8                   | yes: look for an exponent (State8) ->
| ----------------------------------------------------------
| DECSTR_STATE4: integer digits; State5 at DECSTR_STATE5
| looks for the decimal point.
DECSTR_STATE4:
        MOVEQ.L #-0x1,D6                        | no fallback pointer
DECSTR_STATE4_1:
        BSR.B   DECSTR_APPENDDIGIT              | append the digit, next character (AppendDigit)
        BCS.B   DECSTR_STATE5                   | below '0': maybe '.' ->
        CMPI.B  #0x39,D0                        | another digit?
        BLS.B   DECSTR_STATE4_1                 | yes ->
DECSTR_STATE5:
        CMPI.B  #0x2E,D0                        | State5: '.'?
        BNE.W   DECSTR_STATE8                   | no: maybe an exponent (State8) ->
        BSR.B   DECSTR_GETCHAR                  | the character after '.'
        BCS.W   DECSTR_STATENUM                 | below '0': end of the number ->
        BRA.B   DECSTR_STATE75                  | fraction digits (State75) ->
| ----------------------------------------------------------
| DECSTR_APPENDDIGIT: append the digit D0 to d.sig (A2),
| count it in D2.B; past 19 digits only OR it into the 20th and count it
| as lost (D1 + 1); then get the next character (GetChar).
DECSTR_APPENDDIGIT:
        CMPI.B  #0x13,D2                        | check if we have 19 digits (max precision)
        BLT.B   DECSTR_APPENDDIGIT_1            | < 19 -> store digit
        BGT.B   DECSTR_APPENDDIGIT_3            | beyond the 20th: OR it into the 20th ->
        ADDQ.W  #0x1,D1                         | the 20th digit: one lost digit (exponent + 1)
DECSTR_APPENDDIGIT_1:
        ADDQ.L  #0x1,A2                         | advance digit buffer pointer
        MOVE.B  D0,(A2)                         | store ASCII digit
        ADDQ.B  #0x1,D2                         | increment significant digit count
        BRA.B   DECSTR_GETCHAR                  | read next char
| ----------------------------------------------------------
| DECSTR_APPENDDIGIT_3: digit 21 and later -- OR it into the 20th digit.
DECSTR_APPENDDIGIT_3:
        OR.B    D0,(A2)                         | OR extra digits into last digit (for rounding)
        ADDQ.W  #0x1,D1                         | one more lost digit
| DECSTR_GETCHAR -- D0 := next character of the string,
| flags of CMPI.B #'0',D0; at the end of the string (NUL for a C string,
| past A3 for a Pascal string) set validPrefix and end the number or back
| up instead of returning.
| Called by: DECSTR_STATE0, DECSTR_STATE2, DECSTR_STATE5, DECSTR_APPENDDIGIT_1, DECSTR_STATE6 (and 4 more)
DECSTR_GETCHAR:
        TST.L   D4                              | C string (bit 31)?
        BPL.B   DECSTR_GETCHAR_1                | no: Pascal string ->
        MOVE.B  (A0)+,D0                        | next character of the C string
        BEQ.B   DECSTR_GETCHAR_5                | NUL: end of the string ->
        BRA.B   DECSTR_GETCHAR_2                | -> compare with '0' and return
| ----------------------------------------------------------
| DECSTR_GETCHAR_1: Pascal string -- end reached when A0 passes A3.
DECSTR_GETCHAR_1:
        CMPA.L  A0,A3                           | past the last character?
        BLT.B   DECSTR_GETCHAR_3                | yes: end of the string ->
        MOVE.B  (A0)+,D0                        | next character
DECSTR_GETCHAR_2:
        CMPI.B  #0x30,D0                        | flags: compare with '0' for the caller
        RTS                                     | return D0 = next character, flags of CMP with '0' (GetChar)
| ----------------------------------------------------------
| DECSTR_GETCHAR_3: end of the Pascal string; DECSTR_GETCHAR_5: end of either
| string -- validPrefix := TRUE, then back up to the fallback pointer
| if there is one, else end the number (StateNum).
DECSTR_GETCHAR_3:
        ADDQ.L  #0x1,A0                         | step past the end, as past a C NUL
DECSTR_GETCHAR_5:
        BSET    #0x10,D4                        | validPrefix := TRUE: the string ended early (FLVALPREF)
        TST.L   D6                              | fallback pointer saved?
        BPL.W   DECSTR_STATEBACKUP              | yes: back up to it ->
        BRA.W   DECSTR_STATENUM                 | no: end of the number ->
| ----------------------------------------------------------
| DECSTR_STATE6: '.' before any nonzero digit -- skip
| fraction zeros (counted in D1), then scan the fraction digits.
DECSTR_STATE6:
        BSR.B   DECSTR_GETCHAR                  | the character after '.'
        BEQ.B   DECSTR_STATE6_3                 | '0' ->
        BCS.B   DECSTR_STATE6_1                 | below '0': '.junk' or '0.junk' ->
        CMPI.B  #0x39,D0                        | a digit?
        BLS.B   DECSTR_STATE7                   | yes: fraction digits (State7) ->
DECSTR_STATE6_1:
        TST.W   D4                              | not a digit: a zero seen before?
        BPL.W   DECSTR_STATEBACKUP              | no: no number here, back up ->
        BRA.B   DECSTR_STATE8                   | yes ('0.'): look for an exponent ->
| ----------------------------------------------------------
| DECSTR_STATE6_3: a fraction zero before the first nonzero digit.
DECSTR_STATE6_3:
        BSET    #0xF,D4                         | a zero has been seen
        MOVEQ.L #-0x1,D6                        | no fallback pointer
        SUBQ.W  #0x1,D1                         | count the fraction zero
        BRA.B   DECSTR_STATE6                   | more zeros?
| ----------------------------------------------------------
| DECSTR_STATE7: fraction digits, each counted in D1.
DECSTR_STATE7:
        MOVEQ.L #-0x1,D6                        | no fallback pointer
        SUBQ.W  #0x1,D1                         | one more fraction digit
        BSR.B   DECSTR_APPENDDIGIT              | append it, next character (AppendDigit)
        BCS.B   DECSTR_STATENUM                 | below '0': end of the number ->
DECSTR_STATE75:
        CMPI.B  #0x39,D0                        | State75: another digit?
        BLS.B   DECSTR_STATE7                   | still a digit -> loop
| DECSTR_STATE8: optional exponent -- 'E' or 'e', optional
| sign, digits; magnitudes from 8192 ($2000) up are held at 8192, which
| overflows anyway. D6 keeps the position of the 'E' in case no digits
| follow ("123e-" scans as 123).
DECSTR_STATE8:
        MOVE.L  A0,D6                           | fallback pointer ...
        SUBQ.L  #0x1,D6                         | ... = the 'E', in case no digits follow
        CMPI.B  #0x45,D0                        | 'E'?
        BEQ.B   DECSTR_STATE8_1                 | yes, parse exponent ->
        CMPI.B  #0x65,D0                        | 'e'?
        BNE.B   DECSTR_STATENUM                 | no exponent: end of the number ->
| exponent sign
DECSTR_STATE8_1:
        BSR.B   DECSTR_GETCHAR                  | the character after 'E'
        CMPI.B  #0x2B,D0                        | '+'?
        BEQ.B   DECSTR_STATE8_3                 | skip sign ->
        CMPI.B  #0x2D,D0                        | '-'?
        BNE.B   DECSTR_STATE8_7                 | no sign, parse digits ->
        BSET    #0x1F,D2                        | negative exponent (FLEXPSGN)
DECSTR_STATE8_3:
        BSR.B   DECSTR_GETCHAR                  | next character
| exponent digits: D5 := D5 * 10 + digit, at most 8192
DECSTR_STATE8_7:
        CMPI.B  #0x30,D0                        | < '0'?
        BCS.B   DECSTR_STATE8_15                | not a digit ->
        CMPI.B  #0x39,D0                        | > '9'?
        BHI.B   DECSTR_STATE8_15                | not a digit ->
        MOVEQ.L #-0x1,D6                        | an exponent digit: no fallback pointer
        ANDI.W  #0xF,D0                         | ASCII to binary digit
        MULU.W  #0xA,D5                         | D5 *= 10
        ADD.W   D0,D5                           | D5 += digit
        CMPI.W  #0x2000,D5                      | 8192 or more?
        BCS.B   DECSTR_STATE8_13                | no ->
        MOVE.W  #0x2000,D5                      | hold it at 8192: overflows on conversion anyway
DECSTR_STATE8_13:
        BRA.B   DECSTR_STATE8_3                 | next exponent digit
| ----------------------------------------------------------
| DECSTR_STATE8_15 (Apple @15): end of the exponent -- without digits back
| up to the 'E'.
DECSTR_STATE8_15:
        TST.L   D6                              | any exponent digits (D6 = -1)?
        BPL.W   DECSTR_STATEBACKUP              | no: back up to the 'E' ->
| DECSTR_STATENUM -- the first character after the
| number has been read: back up over it; store '0' for a zero, strip
| trailing zeros from d.sig, set d.exp; then DECSTR_STATEFIN.
| Called by: DECSTR_STATE2_1, DECSTR_STATE5, DECSTR_GETCHAR_5, DECSTR_STATE7, DECSTR_STATE8
DECSTR_STATENUM:
        SUBQ.L  #0x1,A0                         | back over the character that ended the number
DECSTR_STNUM2:
        TST.B   D2                              | StNum2: any significant digits?
        BNE.B   DECSTR_STNUM2_1                 | yes -> finalize
        TST.W   D4                              | no: leading zeros seen?
        BPL.B   DECSTR_STATEFIN                 | no: nothing scanned, d stays the NaN ->
        MOVE.W  #0x130,(A2)                     | d.sig := '0'
        BRA.B   DECSTR_STATEFIN                 | finish
| ----------------------------------------------------------
| DECSTR_STNUM2_1: nonzero number -- apply the exponent sign, strip trailing
| zeros from d.sig (each one exponent + 1, except the lost-digit 20th).
DECSTR_STNUM2_1:
        TST.L   D2                              | negative exponent (bit 31)?
        BPL.B   DECSTR_STNUM2_3                 | positive ->
        NEG.W   D5                              | yes: negate it
DECSTR_STNUM2_3:
        CMPI.B  #0x30,0x4(A1,D2.W)              | last digit of d.sig '0'?
        BNE.B   DECSTR_STNUM2_5                 | no: done ->
        SUBQ.B  #0x1,D2                         | strip it
        CMPI.B  #0x13,D2                        | was it the 20th (lost-digit) digit?
        BEQ.B   DECSTR_STNUM2_4                 | yes: already counted ->
        ADDQ.W  #0x1,D5                         | exponent + 1 for the stripped zero
DECSTR_STNUM2_4:
        BRA.B   DECSTR_STNUM2_3                 | loop to check next trailing zero
| ----------------------------------------------------------
| DECSTR_STNUM2_5: d.sig length := D2.B, d.exp := exponent + D1.
DECSTR_STNUM2_5:
        MOVE.B  D2,0x4(A1)                      | d.sig length := digit count
        ADD.W   D1,D5                           | exponent + (lost digits - fraction digits)
        MOVE.W  D5,0x2(A1)                      | d.exp := exponent
| DECSTR_STATEFIN: store index and validPrefix, restore
| the registers, pop the parameters and return.
| Called by: DECSTR_STNUM2, DECSTR_INF_3, DECSTR_INF_3_1, DECSTR_INF_3_3
DECSTR_STATEFIN:
        SUBA.L  0x14(A6),A0                     | current pointer - s = new index
        MOVEA.L 0x10(A6),A1                     | A1 = &index
        MOVE.W  A0,(A1)                         | index := one past the last character accepted
        MOVEA.L 0x4(A6),A0                      | A0 = the caller's return address
        MOVEA.L 0x8(A6),A1                      | A1 = &validPrefix
        SWAP.W  D4                              | validPrefix flag (bit 16) into bit 0
        MOVE.B  D4,(A1)                         | validPrefix := it
        MOVEM.L -0x20(A6),D2-D7/A2-A3           | restore D2-D7/A2-A3
        UNLK    A6                              | drop the frame
        ADDA.W  #0x14,SP                        | pop the return address and the 4 parameters
        JMP     (A0)                            | return to the caller
| ----------------------------------------------------------
| DECSTR_STATE99: no digits -- $B0 (the infinity sign), "INF",
| or "NaN" with an optional decimal code in parentheses; partial matches
| back up to the fallback pointer.
DECSTR_STATE99:
        CMPI.B  #0xB0,D0                        | $B0, the infinity sign in Mac Roman?
        BEQ.W   DECSTR_INF_2                    | yes: infinity ->
        SUBQ.L  #0x1,A0                         | rewind to this character
        MOVEQ.L #0x49,D3                        | 'I'?
        BSR.W   DECSTR_GETMAPPED                | GetMapped
        BEQ.W   DECSTR_STATEINF                 | yes: try "INF" ->
        CMPI.B  #0x4E,D0                        | 'N'?
        BNE.B   DECSTR_STATEBACKUP              | no: no number, back up ->
        MOVEQ.L #0x41,D3                        | 'A'?
        BSR.W   DECSTR_GETMAPPED                | match 'A'
        BNE.B   DECSTR_STATEBACKUP              | no: back up ->
        MOVEQ.L #0x4E,D3                        | 'N'?
        BSR.W   DECSTR_GETMAPPED                | match 'N'
        BNE.W   DECSTR_STATEBACKUP              | no: back up ->
        MOVE.L  #0x54E3430,(A2)+                | d.sig := 'N4000' (NaNZero): 5, 'N4' ...
        MOVE.W  #0x3030,(A2)                    | ... '00'; A2 -> the NaN code digits
        MOVE.L  A0,D6                           | fallback pointer: after "NaN"
        BSR.W   DECSTR_GETCHAR                  | next character
        CMPI.B  #0x28,D0                        | '('?
        BNE.B   DECSTR_STATEBACKUP              | no: just "NaN", back up to it ->
        MOVEQ.L #0x0,D3                         | D3 := 0: the NaN code
DECSTR_STATE99_51:
        BSR.W   DECSTR_GETCHAR                  | next character
        BCS.B   DECSTR_STATE99_57               | below '0': maybe ')' ->
        CMPI.B  #0x39,D0                        | a digit?
        BHI.B   DECSTR_STATEBACKUP              | no: back up to "NaN" ->
        MULU.W  #0xA,D3                         | code * 10
        ANDI.W  #0xF,D0                         | digit value
        ADD.W   D0,D3                           | + digit
        BRA.B   DECSTR_STATE99_51               | next digit
| ----------------------------------------------------------
| DECSTR_STATE99_57: NaN code digits read -- require ')', then store the
| low byte of the code as two hex digits after 'N'.
DECSTR_STATE99_57:
        CMPI.B  #0x29,D0                        | ')'?
        BNE.B   DECSTR_STATEBACKUP              | no: back up to "NaN" ->
        BSR.B   DECSTR_NIBOUT                   | hex digit of the low nibble (NibOut)
        ROR.W   #0x8,D0                         | into the high byte
        ROR.B   #0x4,D3                         | high nibble of the code into the low nibble
        BSR.B   DECSTR_NIBOUT                   | its hex digit
        ROR.W   #0x8,D0                         | D0.W = high digit, low digit
        MOVE.W  D0,(A2)                         | d.sig := 'N40hh': the code in hex
        BRA.B   DECSTR_INF_3                    | -> as for INF
| ----------------------------------------------------------
| DECSTR_STATEBACKUP -- the scan went past the last valid
| number: resume at the fallback pointer D6 and end there.
| Called by: DECSTR_STATE99, DECSTR_STATEINF, DECSTR_STATE2_1, DECSTR_GETCHAR_5, DECSTR_STATE6_1 (and 3 more)
DECSTR_STATEBACKUP:
        MOVEA.L D6,A0                           | resume at the fallback pointer
        BRA.W   DECSTR_STNUM2                   | -> StNum2
| ----------------------------------------------------------
| DECSTR_STATEINF: 'I' read -- "INF" (any case) is infinity.
DECSTR_STATEINF:
        MOVEQ.L #0x4E,D3                        | 'N'?
        BSR.B   DECSTR_GETMAPPED                | match 'N'
        BNE.B   DECSTR_STATEBACKUP              | no: back up ->
        MOVEQ.L #0x46,D3                        | 'F'?
        BSR.B   DECSTR_GETMAPPED                | match 'F'
        BNE.B   DECSTR_STATEBACKUP              | no: back up ->
DECSTR_INF_2:
        MOVE.W  #0x149,(A2)                     | d.sig := 'I': infinity
DECSTR_INF_3:
        MOVEQ.L #-0x1,D6                        | no fallback pointer
        TST.L   D4                              | C string?
        BPL.B   DECSTR_INF_3_1                  | no: Pascal ->
        MOVE.B  (A0),D0                         | C: the character after the token
        BNE.W   DECSTR_STATEFIN                 | not the end: done ->
        BRA.B   DECSTR_INF_3_3                  | NUL: set validPrefix ->
| ----------------------------------------------------------
| DECSTR_INF_3_1: Pascal string -- at its end set validPrefix.
DECSTR_INF_3_1:
        CMPA.L  A0,A3                           | at the end of the Pascal string?
        BGE.W   DECSTR_STATEFIN                 | no: done ->
DECSTR_INF_3_3:
        BSET    #0x10,D4                        | validPrefix := TRUE
        BRA.W   DECSTR_STATEFIN                 | -> StateFin
| ----------------------------------------------------------
| DECSTR_GETMAPPED -- next character, a-z mapped to
| A-Z, compared with D3.B (EQ if equal).
| Called by: DECSTR_STATE99, DECSTR_STATEINF
DECSTR_GETMAPPED:
        BSR.W   DECSTR_GETCHAR                  | next character (GetChar)
        CMPI.B  #0x61,D0                        | compare with 'a'
        BCS.B   DECSTR_GETMAPPED_1              | < 'a' -> not lowercase
        CMPI.B  #0x7A,D0                        | compare with 'z'
        BHI.B   DECSTR_GETMAPPED_1              | > 'z' -> not lowercase
        SUBI.B  #0x20,D0                        | convert to uppercase
DECSTR_GETMAPPED_1:
        CMP.B   D3,D0                           | the wanted letter?
        RTS                                     | return D0 = next char, upper case; EQ if = D3.B (GetMapped)
| ----------------------------------------------------------
| DECSTR_NIBOUT -- D0.B := ASCII hex digit of the low
| nibble of D3.
DECSTR_NIBOUT:
        MOVE.B  #0xF,D0                         | nibble mask (D0 high bits kept)
        AND.B   D3,D0                           | D0.B = low nibble of D3
        CMPI.B  #0x9,D0                         | above 9?
        BLS.B   DECSTR_NIBOUT_61                | no: 0-9 ->
        ADDQ.B  #0x7,D0                         | A-F: + 7 ('A' = '9' + 8)
DECSTR_NIBOUT_61:
        ADDI.B  #0x30,D0                        | + '0'
        RTS                                     | return D0.B = ASCII hex digit of D3's low nibble (NibOut)
| ----------------------------------------------------------
| DEC2STR_ENTRY -- _dec2str: PROCEDURE Dec2Str(f: DecForm; d: Decimal;
| VAR s: DecStr) (f and d passed by address): format the decimal record
| d as a string, FloatDecimal ("-1.234e+5": sign or blank, f.digits
| significant digits) or FixedDecimal ("-12.30": f.digits decimals);
| INF, NAN(ddd) or '?' (does not fit in 80 characters) for the special
| values. Registers (Apple Dec2Str.a): A0 output string, A1 d.sig, D1
| d.sig length, D2 output length - 80, D4 d.sgn/d.exp, D5 the DecForm.
DEC2STR_ENTRY:
        MOVEM.L D2-D5,-(SP)                     | save D2-D5
        LINK    A6,#0x0                         | frame: 24(A6) &s, 28 &d, 32 &f
        MOVEA.L 0x20(A6),A0                     | A0 = &f
        MOVE.L  (A0),D5                         | D5 = f: style (high word), digits (low word)
        MOVEA.L 0x18(A6),A0                     | A0 = &s
        MOVEA.L 0x1C(A6),A1                     | A1 = &d
        MOVE.L  (A1)+,D4                        | D4 = d.sgn, d.exp
        ADDQ.W  #0x1,A0                         | A0 = s[1]: the first character
        MOVEQ.L #-0x50,D2                       | D2 = length - 80 (wmax): above 0 = too long
        MOVEQ.L #0x0,D1                         | D1 := 0, for the length byte
        MOVE.B  (A1)+,D1                        | D1 = length of d.sig; A1 = its first digit
        BEQ.B   DECSTR_ITSAPASS                 | empty d.sig: '?' ->
        BTST    #0x18,D4                        | d.sgn = 1 (bit 24 = bit 0 of its high byte)?
        BEQ.B   DECSTR_HEYITSPOS                | no: positive ->
        MOVE.B  #0x2D,(A0)+                     | store the sign '-'
        BRA.B   DECSTR_D2INC                    | -> count it
| ----------------------------------------------------------
| DECSTR_HEYITSPOS: positive -- a leading blank in float
| style only.
DECSTR_HEYITSPOS:
        BTST    #0x18,D5                        | FixedDecimal style (bit 24)?
        BNE.B   DECSTR_HEYITSFXD                | yes: no blank ->
        MOVE.B  #0x20,(A0)+                     | ' ' in place of the sign (float style)
DECSTR_D2INC:
        ADDQ.W  #0x1,D2                         | count the sign character
DECSTR_HEYITSFXD:
        MOVE.B  (A1),D0                         | D0 = first character of d.sig
        CMPI.B  #0x3F,D0                        | '?': no representable value?
DECSTR_ITSAPASS:
        BEQ.W   DECSTR_ERRXIT                   | yes (or empty d.sig): s := '?' ->
        ORI.B   #0x20,D0                        | lower case: 'N', 'I' -> 'n', 'i'
        CMPI.B  #0x69,D0                        | 'i': infinity?
        BEQ.W   DECSTR_INFFOUND                 | yes: "INF" ->
        CMPI.B  #0x6E,D0                        | 'n': NaN?
        BNE.B   DECSTR_ITSANUMBER               | no: a number ->
        MOVE.B  #0x4E,(A0)+                     | store 'N' of "NAN(" ...
        MOVE.B  #0x41,(A0)+                     | ... 'A' ...
        MOVE.B  #0x4E,(A0)+                     | ... 'N' ...
        MOVE.B  #0x28,(A0)+                     | ... and '('
        MOVE.B  #0x29,0x3(A0)                   | ')' after the 3 code digits: 'NAN(ddd)'
        ADDQ.W  #0x5,D2                         | 5 characters so far
        MOVEQ.L #0x0,D3                         | D3 := 0: the binary NaN code
        CMPI.B  #0x5,D1                         | more than 4 code digits after the N?
        BLE.B   DECSTR_LNGTHOK                  | no ->
        MOVEQ.L #0x5,D1                         | use only the first 4
DECSTR_LNGTHOK:
        BSR.B   DECSTR_HEX2BIN                  | D3 = the last code digit (Hex2Bin)
        MOVE.L  D3,D0                           | D0 = low nibble
        BSR.B   DECSTR_HEX2BIN                  | D3 = the digit before it
        ASL.B   #0x4,D3                         | high nibble
        OR.L    D0,D3                           | D3 = the code byte
DECSTR_FINNAN:
        MOVEQ.L #0x4,D0                         | FinNaN: print the code as 3 decimal digits
        BRA.B   DECSTR_FROMNAN                  | -> the digit printer (FromNaN)
| ----------------------------------------------------------
| DECSTR_HEX2BIN -- D1 := D1 - 1; D3.B := value of the
| hex digit d.sig[D1]; when no digits are left go on at DECSTR_FINNAN
| (FinNaN) instead of returning.
DECSTR_HEX2BIN:
        SUBQ.W  #0x1,D1                         | previous digit of d.sig
        BLE.B   DECSTR_FINNAN                   | none left (only the N): FinNaN ->
        MOVE.B  0x0(A1,D1.W),D3                 | D3 = the hex digit character
        CMPI.B  #0x39,D3                        | 0-9?
        BLE.B   DECSTR_DECMLFND                 | yes, numeric ->
        SUBQ.B  #0x7,D3                         | A-F: - 7
DECSTR_DECMLFND:
        ANDI.B  #0xF,D3                         | its value
        RTS                                     | return D3.B = value of the hex digit (DecmlFnd)
| ----------------------------------------------------------
| DECSTR_ITSANUMBER: a number -- '0' gets exponent 0; then
| float or fixed style.
DECSTR_ITSANUMBER:
        CMPI.B  #0x30,(A1)                      | d.sig = '0'?
        BNE.B   DECSTR_NOTAZERO                 | no ->
        MOVEQ.L #0x1,D1                         | one digit
        MOVEQ.L #0x0,D4                         | exponent 0 (and sign: printed already)
DECSTR_NOTAZERO:
        BTST    #0x18,D5                        | FixedDecimal style?
        BNE.W   DECSTR_ITSFIXED                 | yes ->
        TST.W   D5                              | float style: f.digits >= 1?
        BGT.B   DECSTR_DIGITSOK                 | yes ->
        MOVEQ.L #0x1,D5                         | at least 1 digit
DECSTR_DIGITSOK:
        MOVEQ.L #0x1,D0                         | one digit ...
        BSR.B   DECSTR_ADDDIGITS                | ... before the point (AddDigits)
        MOVE.W  D1,D3                           | D3 = number of digits ...
        EXT.L   D3                              | ... as a long
        SUBQ.L  #0x1,D3                         | - 1: digits after the point
        BGT.B   DECSTR_NEEDPOINT                | some: need the point ->
        CMPI.W  #0x1,D5                         | f.digits > 1 (zeros to add)?
        BLE.B   DECSTR_NOPOINT                  | no: no point ->
DECSTR_NEEDPOINT:
        BSR.B   DECSTR_ADDPOINT                 | '.' (AddPoint)
        MOVE.W  D3,D0                           | the other digits
        BSR.B   DECSTR_ADDDIGITS                | AddDigits
        MOVE.W  D5,D0                           | f.digits ...
        SUB.W   D1,D0                           | ... - length of d.sig: trailing zeros
        BSR.B   DECSTR_ADDZEROS                 | AddZeros
DECSTR_NOPOINT:
        ADDQ.W  #0x2,D2                         | NoPoint: 'e' and the sign
        BGT.B   DECSTR_ERRXIT                   | too long: '?' ->
        MOVE.B  #0x65,(A0)+                     | 'e' (the sign separately: s may be odd)
        EXT.L   D4                              | d.exp as a long
        ADD.L   D4,D3                           | exponent = d.exp + length(d.sig) - 1
        BLT.B   DECSTR_NEGEXP                   | negative ->
        MOVE.B  #0x2B,(A0)+                     | store the exponent sign '+'
        BRA.B   DECSTR_GETEXPDIGS               | -> its digits
| ----------------------------------------------------------
| DECSTR_NEGEXP: negative exponent.
DECSTR_NEGEXP:
        MOVE.B  #0x2D,(A0)+                     | store the exponent sign '-'
        NEG.L   D3                              | magnitude
DECSTR_GETEXPDIGS:
        MOVEQ.L #0x0,D0                         | GetExpDigs: D0 = table index * 2, from 0
DECSTR_FROMNAN:
        LEA.L   PACK_7_POW10_TABLE(PC),A1       | A1 = the tens table (FromNaN)
DECSTR_NEXTCMP:
        ADDQ.W  #0x2,D0                         | NextCmp: next power of ten
        CMP.W   -0x2(A1,D0.W),D3                | value >= this power?
        BCS.B   DECSTR_GETINLOOP                | no: start printing below it ->
        CMPI.B  #0x8,D0                         | checked 10^4 too?
        BLT.B   DECSTR_NEXTCMP                  | no -> next power
DECSTR_NEXTDIG:
        DIVU.W  -0x2(A1,D0.W),D3                | NextDig: digit = value / 10^k, remainder in the high word
DECSTR_LASTDIG:
        ADDQ.W  #0x1,D2                         | LastDig: count the character
        BGT.B   DECSTR_ERRXIT                   | too long: '?' ->
        ADDI.W  #0x30,D3                        | digit to ASCII
        MOVE.B  D3,(A0)+                        | store it
        SWAP.W  D3                              | D3 = the remainder
        EXT.L   D3                              | clear the high word
DECSTR_GETINLOOP:
        SUBQ.W  #0x2,D0                         | GetInLoop: next lower power
        BGT.B   DECSTR_NEXTDIG                  | divide by it ->
        BEQ.B   DECSTR_LASTDIG                  | the units digit ->
        BRA.B   DECSTR_SETLENGTH                | -> set the length and return
| ----------------------------------------------------------
| DECSTR_ADDDIGITS -- append D0 digits from (A1)+ (none if
| D0 <= 0); too long -> '?'.
| Called by: DECSTR_DIGITSOK, DECSTR_NEEDPOINT, DECSTR_ITSFIXED, DECSTR_ALLBEFORE, DECSTR_FROMMID
DECSTR_ADDDIGITS:
        BLE.B   DECSTR_ENDDIGITS                | D0 <= 0: nothing to append
        ADD.W   D0,D2                           | new length
        BGT.B   DECSTR_ERRXIT                   | too long: '?' ->
DECSTR_LOOPD:
        MOVE.B  (A1)+,(A0)+                     | append a digit of d.sig
        SUBQ.W  #0x1,D0                         | count
        BGT.B   DECSTR_LOOPD                    | more ->
DECSTR_ENDDIGITS:
        RTS                                     | return: D0 digits appended (EndDigits)
| ----------------------------------------------------------
| DECSTR_ADDPOINT -- append '.'.
DECSTR_ADDPOINT:
        ADDQ.W  #0x1,D2                         | one more character
        BGT.B   DECSTR_ERRXIT                   | too long: '?' ->
        MOVE.B  #0x2E,(A0)+                     | store the decimal point '.'
        RTS                                     | return: '.' appended (AddPoint)
| ----------------------------------------------------------
| DECSTR_LOOPZ / DECSTR_ADDZEROS -- append
| D0 zeros (none if D0 <= 0).
DECSTR_LOOPZ:
        ADDQ.W  #0x1,D2                         | one more character
        BGT.B   DECSTR_ERRXIT                   | too long: '?' ->
        MOVE.B  #0x30,(A0)+                     | store one '0'
| Called by: DECSTR_ALLBEFORE, DECSTR_ALLAFTER, DECSTR_NEEDPOINT, DECSTR_FROMMID
DECSTR_ADDZEROS:
        SUBQ.W  #0x1,D0                         | count
        BGE.B   DECSTR_LOOPZ                    | more ->
        RTS                                     | return: the zeros appended (EndZeros)
| ----------------------------------------------------------
| DECSTR_ERRXIT -- the result does not fit: s := '?'.
| Called by: DECSTR_ITSAPASS, DECSTR_NOPOINT, DECSTR_LASTDIG, DECSTR_ADDDIGITS, DECSTR_ADDPOINT (and 1 more)
DECSTR_ERRXIT:
        MOVEA.L 0x18(A6),A0                     | A0 = &s
        MOVE.W  #0x13F,(A0)                     | s := '?' (length 1)
        BRA.B   DECSTR_DEC2STR_DONE             | -> return
| ----------------------------------------------------------
| DECSTR_ITSFIXED: fixed style -- integer digits, '.',
| f.digits fraction digits.
DECSTR_ITSFIXED:
        MOVE.W  D1,D3                           | D3 = length of d.sig ...
        ADD.W   D4,D3                           | ... + d.exp: digits before the point
        BLE.B   DECSTR_ALLAFTER                 | none: "0.0..ddd" ->
        TST.W   D4                              | d.exp >= 0?
        BGE.B   DECSTR_ALLBEFORE                | yes: all digits before the point ->
        MOVE.W  D3,D0                           | the integer digits
        BSR.B   DECSTR_ADDDIGITS                | AddDigits
        BSR.B   DECSTR_ADDPOINT                 | AddPoint: append the decimal point
        MOVEQ.L #0x0,D0                         | D0 = -d.exp ...
        SUB.W   D4,D0                           | ... digits after the point
        BRA.B   DECSTR_FROMMID                  | -> FromMid
| ----------------------------------------------------------
| DECSTR_ALLBEFORE: all digits left of the point.
DECSTR_ALLBEFORE:
        MOVE.W  D1,D0                           | all digits of d.sig
        BSR.B   DECSTR_ADDDIGITS                | AddDigits
        MOVE.W  D4,D0                           | d.exp zeros
        BSR.B   DECSTR_ADDZEROS                 | AddZeros
        MOVE.W  D5,D0                           | f.digits decimals?
        BLE.B   DECSTR_SETLENGTH                | none: done ->
        BSR.B   DECSTR_ADDPOINT                 | AddPoint: append the decimal point
        BSR.B   DECSTR_ADDZEROS                 | f.digits zeros
        BRA.B   DECSTR_SETLENGTH                | -> set the length
| ----------------------------------------------------------
| DECSTR_ALLAFTER: all digits right of the point: "0.00ddd".
DECSTR_ALLAFTER:
        MOVEQ.L #0x1,D0                         | one '0' ...
        BSR.B   DECSTR_ADDZEROS                 | ... before the point
        BSR.B   DECSTR_ADDPOINT                 | AddPoint: append the decimal point
        MOVEQ.L #0x0,D0                         | D0 = -(d.exp + length): ...
        SUB.W   D3,D0                           | ... zeros after the point
        BSR.B   DECSTR_ADDZEROS                 | AddZeros
        MOVE.W  D1,D0                           | all digits of d.sig
DECSTR_FROMMID:
        BSR.B   DECSTR_ADDDIGITS                | FromMid: AddDigits
        MOVE.W  D4,D0                           | d.exp ...
        ADD.W   D5,D0                           | ... + f.digits: zeros to fill the decimals
        BSR.B   DECSTR_ADDZEROS                 | AddZeros
DECSTR_SETLENGTH:
        MOVEA.L 0x18(A6),A0                     | SetLength: A0 = &s
        ADDI.W  #0x50,D2                        | D2 + 80 = length
        MOVE.B  D2,(A0)                         | length byte of s
DECSTR_DEC2STR_DONE:
        UNLK    A6                              | drop the frame
        MOVEM.L (SP)+,D2-D5/A0                  | restore D2-D5, A0 = return address
        ADDA.W  #0xC,SP                         | pop the 3 parameters
        JMP     (A0)                            | return to the caller
| ----------------------------------------------------------
| DECSTR_INFFOUND: "INF".
| ----------------------------------------------------------
DECSTR_INFFOUND:
        MOVE.B  #0x49,(A0)+                     | store 'I' of "INF" ...
        MOVE.B  #0x4E,(A0)+                     | ... 'N' ...
        MOVE.B  #0x46,(A0)                      | ... and 'F'
        ADDQ.W  #0x3,D2                         | 3 more characters
        BRA.B   DECSTR_SETLENGTH                | -> set the length and return
| ----------------------------------------------------------
| PACK_7_POW10_TABLE (Apple tens): divisors for printing an exponent (or
| a NaN code) of up to 5 decimal digits with DIVU, highest place first.
PACK_7_POW10_TABLE:
        .short  10                              | 10^1
        .short  100                             | 10^2
        .short  1000                            | 10^3
        .short  10000                           | 10^4
    ROM_RESOURCE_END PACK_7                     | end of the data: pads to even, sets the sizes

