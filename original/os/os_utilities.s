| Operating System Utilities
|
| Apple source: SysUtil.a (MacSEROM.lst module SYSUTIL). In ROM order:
|   ReadParam, WriteParam      - parameter RAM: low-memory copy SysParam <->
|                                clock chip
|   ReadDateTime, SetDateTime  - the clock (Time)
|   Delay                      - wait D0 ticks
|   CmpString (EqualString), UprString, with UPRSTRING_TBL
|   ReadPRAM                   - read the 20 bytes of parameter RAM
|   InitUtil                   - _InitUtil: copy parameter RAM to SysParam
|                                and the clock to Time, write the defaults
|                                if parameter RAM is invalid
|   WPOn, WPOff                - clock chip write protect
| The bit-level clock chip access (ClkRW) is in hw/rtc.s.
|
| References: Inside Macintosh Vol II, Ch 13 (Operating System Utilities).

| ----------------------------------------------------------
| _ReadParam ($A037): read PRAM into low-memory SysParam block
ReadParam:
        LEA.L     (SysParam_SPValid).w,A1       | A1 = dest (SysParam area)
        BSR.B   READPARAM_CONT                  | read 20 bytes from RTC PRAM
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from _ReadParam
| READPARAM_CONT: copy selected bytes from A1 to A0 based on D0 bitmask.
| Iterates 20 bytes; if corresponding bit in D0 is set, copies byte.
READPARAM_CONT:
        MOVEQ.L #0x13,D2                        | loop count: 20 bytes (PRAM size minus 1)
READPARAM_LOOP:
        LSR.L   #0x1,D0                         | shift out next bit
        BCC.B   READPARAM_SKIP                  | bit clear -> skip this byte
        MOVE.B  (A1),(A0)+                      | copy byte from source to dest
READPARAM_SKIP:
        ADDQ.L  #0x1,A1                         | advance source pointer
        DBRA    D2,READPARAM_LOOP               | next byte
        RTS                                     | return from READPARAM_CONT

| ----------------------------------------------------------
| _WriteParam ($A038): write SysParam block to RTC PRAM (selective).
| Caller passes bitmask in D0; only bytes with set bit are written.
| Then verify by reading back and comparing.
WriteParam:
        LEA.L     (SysParam_SPValid).w,A1       | A1 = source (SysParam area)
        EXG     A0,A1                           | A0 := SysParam, A1 := caller buffer
        BSR.B   READPARAM_CONT                  | selectively copy bytes per bitmask
        BSR.W   WPOFF_CONT                      | write SysParam to RTC PRAM
        LEA.L     (Scratch20).w,A1              | temp buffer for readback
        BSR.W   ReadPRAM                        | read PRAM into temp
        LEA.L     (SysParam_SPValid).w,A0       | A0 = original SysParam
        MOVEQ.L #-0x57,D0                       | assume prWrErr (-87)
        MOVEQ.L #0x4,D2                         | 5 longwords = 20 bytes
WRITEPARAM_LOOP:
        CMPM.L  (A0)+,(A1)+                     | compare written vs read-back
        BNE.B   WRITEPARAM_ERR                  | mismatch -> return prWrErr
        DBRA    D2,WRITEPARAM_LOOP              | loop 5 longwords
        MOVEQ.L #0x0,D0                         | noErr (verified)
WRITEPARAM_ERR:
        RTS                                     | return from _WriteParam

| ----------------------------------------------------------
| _ReadDateTime ($A039): read date/time from RTC into Time global,
| then return it via A0.
ReadDateTime:
        BSR.W   INITUTIL_CONT                   | read 4-byte time from RTC chip
        MOVE.L  (Time).w,(A0)                   | copy Time to caller's buffer
        RTS                                     | return from _ReadDateTime

| ----------------------------------------------------------
| _SetDateTime ($A03A): set date/time in RTC.
| Caller passes new time in D0.
SetDateTime:
        MOVE.L  D0,(Time).w                     | store new time in global
        BRA.W   INITUTIL_CONT_2                 | -> write to RTC chip

| ----------------------------------------------------------
| _Delay ($A03B): delay for specified number of ticks (1/60 sec)
| A0 = tick count to delay
Delay:
        MOVE    #0x2000,SR                      | enable interrupts (so ticks advance)
        MOVE.L  (Ticks).w,D0                    | D0 = start tick count
        ADD.L   A0,D0                           | D0 = target tick count
DELAY_LOOP:
        CMP.L   (Ticks).w,D0                    | check current tick count against target
        BGT.B   DELAY_LOOP                      | loop until current ticks >= target
        RTS                                     | return from Delay

| ----------------------------------------------------------
| CmpString -- _CmpString trap implementation. Compares two Pascal
| strings byte-by-byte using a character-translation helper for
| diacritic/case stripping. Returns Z=1 if equal.
| Stack on entry: D0 (high:low) packs the two byte counts.
CmpString:
        MOVE.L   D3,-(SP)                       | save D3 (compare uses scratch byte)
        MOVE    D0,D2                           | D2 = length2 (low word of D0)
        SWAP    D0                              | D0.lo = length1
UPRSTRING_XLATE_BASE:                           | PC-rel base = UPRSTRING_TBL - $80
        CMP     D0,D2                           | same length?
        BNE.B   CMPSTRING_NEQ                   | length mismatch -> not equal
        MOVEQ.L #0x0,D2                         | D2.b = 0 (clear before MOVE.B)
        BRA.B   CMPSTRING_NEXT                  | enter loop tail (DBRA test)
CMPSTRING_LOOP:
        MOVE.B  (A1)+,D2                        | D2 = next char from string 2
        BSR.B   STRING_XLATE                    | fold to upper/strip diacritics
        MOVE.B  D2,D3                           | D3 = folded char from string 2
        MOVE.B  (A0)+,D2                        | D2 = next char from string 1
        BSR.B   STRING_XLATE                    | fold to upper/strip diacritics
        CMP.B   D2,D3                           | same folded character?
        BNE.B   CMPSTRING_NEQ                   | differ -> not equal
CMPSTRING_NEXT:
        DBRA    D0,CMPSTRING_LOOP               | next byte (D0 = length-1 counter)
        MOVEQ.L #0x0,D0                         | return 0 (equal)
        BRA.B   CMPSTRING_EXIT                  | -> restore D3 and return
CMPSTRING_NEQ:
        MOVEQ.L #0x1,D0                         | return 1 (not equal)
CMPSTRING_EXIT:
        MOVE.L  (SP)+,D3                        | restore D3
        RTS                                     | return from _CmpString
| STRING_XLATE - fold the character in D2.B (D2.W < $100) for
| CmpString and UprString, as selected by the trap word in D1:
| bit 9 (,MARKS) set = strip diacritical marks ($80-$CD, first part
| of UPRSTRING_TBL); bit 10 (,CASE) clear = convert to upper case
| ($61-$9F via the second part of UPRSTRING_TBL; $BE/$BF -> $AE/$AF,
| $CF -> $CE).
STRING_XLATE:
        BTST    #0x9,D1                         | MARKS bit: strip diacritical marks?
        BEQ.B   STRING_XLATE_LOWER              | no -> keep the marks
        CMPI.B  #0x80,D2                        | below high-ASCII?
        BCS.B   STRING_XLATE_LOWER              | ASCII -> no diacritic mapping
        CMPI.B  #0xCD,D2                        | above accented-letter range?
        BHI.B   STRING_XLATE_LOWER              | branch if > (unsigned)
        MOVE.B  UPRSTRING_XLATE_BASE(PC,D2.W),D2 | D2 = UPRSTRING_TBL[D2-$80]
STRING_XLATE_LOWER:
        BTST    #0xA,D1                         | CASE bit: case-sensitive?
        BNE.B   STRING_XLATE_DONE               | yes -> keep the case
        CMPI.B  #0x61,D2                        | below 'a'?
        BCS.B   STRING_XLATE_DONE               | yes -> already upper or non-letter
        CMPI.B  #0x9F,D2                        | above lowercase 'z'+accents range?
        BHI.B   STRING_XLATE_AC                 | yes -> check next range
        MOVE.B  STRING_XLATE_DONE+1(PC,D2.W),D2 | D2 = UPRSTRING_TBL[$4E+D2-$61]
        BRA.B   STRING_XLATE_DONE               | done -> return uppercase
STRING_XLATE_AC:
        CMPI.B  #0xBE,D2                        | below $BE (ae)?
        BCS.B   STRING_XLATE_DONE               | yes -> done
        CMPI.B  #0xBF,D2                        | above $BF (o-slash)?
        BHI.B   STRING_XLATE_AE                 | branch if > (unsigned)
        SUBI.B  #0x10,D2                        | $BE ae -> $AE AE, $BF o-slash -> $AF
        BRA.B   STRING_XLATE_DONE               | done -> return uppercase ligature
STRING_XLATE_AE:
        CMPI.B  #0xCF,D2                        | specifically lowercase oe?
        BNE.B   STRING_XLATE_DONE               | no -> done
        SUBQ.B  #0x1,D2                         | fold oe -> OE
STRING_XLATE_DONE:
        RTS                                     | return folded char in D2

| ----------------------------------------------------------
| _UprString ($A054): convert a string to upper case in place
| Pascal: PROCEDURE UprString(VAR theString: Str255; diacSens: BOOLEAN);
| Entry: A0 = first character, D0.W = length; trap bit 9 (,MARKS,
|        for diacSens = FALSE) also strips diacritical marks
| Exit:  D0 = noErr (0)
| Each character is folded by STRING_XLATE (shared with CmpString).
UprString:
        MOVEQ.L #0x0,D2                         | clear D2 (STRING_XLATE indexes with D2.W)
        BRA.B   UPRSTRING_LOOP_2                | enter loop tail
UPRSTRING_LOOP:
        MOVE.B  (A0),D2                         | D2 = character
        BSR.B   STRING_XLATE                    | apply case/diacritic folding
        MOVE.B  D2,(A0)+                        | write folded character back
UPRSTRING_LOOP_2:
        DBRA    D0,UPRSTRING_LOOP               | loop over all characters
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        RTS                                     | return from _UprString

| ----------------------------------------------------------
| UPRSTRING_TBL -- 142 bytes: the two mapping tables of STRING_XLATE.
| $4E94-$4EE1 (78 bytes): diacritical-mark strip table for $80-$CD,
| read as UPRSTRING_XLATE_BASE(PC,D2.W) = UPRSTRING_TBL + D2 - $80;
| accented letters map to their plain letters, others to themselves.
| $4EE2-$4F20 (63 bytes): upper-case table for $61-$9F, read as
| STRING_XLATE_DONE+1(PC,D2.W) = $4EE2 + D2 - $61; letters with no
| upper-case form in the character set map to themselves.
| $4F21: pad byte. Row notes give the result per character ("=" =
| unchanged); character codes are Mac Roman (IM I Appendix K).
| Previous disassembly rendered this as pseudo-instructions
| (BSR.B, MULU, etc.) because many of the bytes coincidentally form
| legal 68000 opcodes when interpreted as code.
UPRSTRING_TBL:
        .byte   0x41,0x41,0x43,0x45,0x4E,0x4F,0x55,0x61 | strip $80-$87: A A C E N O U a
        .byte   0x61,0x61,0x61,0x61,0x61,0x63,0x65,0x65 | strip $88-$8F: a a a a a c e e
        .byte   0x65,0x65,0x69,0x69,0x69,0x69,0x6E,0x6F | strip $90-$97: e e i i i i n o
        .byte   0x6F,0x6F,0x6F,0x6F,0x75,0x75,0x75,0x75 | strip $98-$9F: o o o o u u u u
        .byte   0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7 | strip $A0-$A7: = = = = = = = =
        .byte   0xA8,0xA9,0xAA,0xAB,0xAC,0xAD,0xAE,0x4F | strip $A8-$AF: = = = = = = = O
        .byte   0xB0,0xB1,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7 | strip $B0-$B7: = = = = = = = =
        .byte   0xB8,0xB9,0xBA,0x61,0x6F,0xBD,0xBE,0x6F | strip $B8-$BF: = = = a o = = o
        .byte   0xC0,0xC1,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7 | strip $C0-$C7: = = = = = = = =
        .byte   0xC8,0xC9,0xCA,0x41,0x41,0x4F,0x41,0x42 | strip $C8-$CD: = = = A A O; upper a b
        .byte   0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A | upper $63-$6A: C D E F G H I J
        .byte   0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52 | upper $6B-$72: K L M N O P Q R
        .byte   0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A | upper $73-$7A: S T U V W X Y Z
        .byte   0x7B,0x7C,0x7D,0x7E,0x7F,0x80,0x81,0x82 | upper $7B-$82: = = = = = = = =
        .byte   0x83,0x84,0x85,0x86,0x87,0xCB,0x89,0x80 | upper $83-$8A: = = = = = $CB = $80
        .byte   0xCC,0x81,0x82,0x83,0x8F,0x90,0x91,0x92 | upper $8B-$92: $CC $81 $82 $83 = = = =
        .byte   0x93,0x94,0x95,0x84,0x97,0x98,0x99,0x85 | upper $93-$9A: = = = $84 = = = $85
        .byte   0xCD,0x9C,0x9D,0x9E,0x86,0x00   | upper $9B-$9F: $CD = = = $86; pad

| ReadPRAM: read 20 bytes from RTC PRAM into buffer at A1
| PRAM is split: 16 bytes at RTC registers $C1-$FC, 4 bytes at $A1-$AC
ReadPRAM:
        MOVEM.L D1-D2/D5/A1,-(SP)               | save regs
        MOVEQ.L #-0x3F,D1                       | D1 = $C1 (first PRAM read command)
        MOVEQ.L #0xF,D5                         | 16 bytes in first block
        BSR.B   READPRAM_LOOP                   | read 16 bytes
        MOVEQ.L #-0x5F,D1                       | D1 = $A1 (second PRAM block)
        MOVEQ.L #0x3,D5                         | 4 bytes in second block
        BSR.B   READPRAM_LOOP                   | read 4 bytes
        MOVEM.L (SP)+,D1-D2/D5/A1               | restore regs
        RTS                                     | return from ReadPRAM

| ----------------------------------------------------------
|
| READPRAM_LOOP: read consecutive RTC registers into buffer at A1
| D1 = starting RTC command, D5 = byte count - 1
|
| Called during boot.
READPRAM_LOOP:
        BSR.W   ClkRW                           | read one byte from RTC -> D2
        MOVE.B  D2,(A1)+                        | store byte, advance pointer
        ADDQ.B  #0x4,D1                         | next RTC register address
        DBRA    D5,READPRAM_LOOP                | loop
        RTS                                     | return from READPRAM_LOOP

| ----------------------------------------------------------
| READPRAM_CONT
READPRAM_CONT:                                  | 20-byte data table (not code)
  .byte 0xA8, 0x00, 0x00, 0x00, 0xCC, 0x0A
  .byte 0xCC, 0x0A, 0x00, 0x00, 0x00, 0x00
  .byte 0x00, 0x02, 0x63, 0x00, 0x03, 0x88
  .byte 0x00, 0x4C
| InitUtil - PRAM/RTC init: read system parameters into low memory
InitUtil:
        MOVEQ.L #0x0,D0                         | assume noErr
        BSR.W   WPOff                           | disable RTC write protect
        MOVEQ.L #0x31,D1                        | RTC command: write test register
        CLR.B   D2                              | data = 0 (clear test mode)
        BSR.W   ClkRW                           | write to RTC
        BSR.W   WPOn                            | re-enable write protect
        LEA.L     (SysParam_SPValid).w,A1       | A1 = SysParam destination
        BSR.B   ReadPRAM                        | read 20 bytes from PRAM
        BSR.B   INITUTIL_CONT                   | read date/time from RTC -> Time
        MOVEQ.L #0x0,D0                         | assume noErr
        CMPI.B  #0xA8,(A1)                      | valid PRAM signature? ($A8)
        BEQ.B   INITUTIL_OK                     | yes -> done
        MOVEQ.L #-0x58,D0                       | prInitErr (-88): PRAM was uninitialized
        MOVEQ.L #0x4,D1                         | 5 longwords = 20 bytes
        LEA     READPRAM_CONT(PC),A0            | A0 = default PRAM values
INITUTIL_LOOP:
        MOVE.L  (A0)+,(A1)+                     | copy defaults to SysParam
        DBRA    D1,INITUTIL_LOOP                | loop 5 longwords
        BSR.B   WPOFF_CONT                      | write defaults back to RTC PRAM
INITUTIL_OK:
        RTS                                     | return from InitUtil
INITUTIL_CONT:
        MOVEM.L D1-D2/D4-D5/A2-A3,-(SP)         | save registers
        MOVEQ.L #0x1,D4                         | retry count = 1 (read up to 2x)
        MOVEQ.L #0x0,D0                         | assume noErr
INITUTIL_LOOP_2:
        MOVEQ.L #-0x63,D1                       | RTC command: read seconds ($9D)
        MOVEQ.L #0x7,D5                         | 8 reads (4 bytes * 2 for verify)
        LEA.L   (Scratch20).w,A2                | dest buffer
        MOVE.L  A2,A3                           | save start for comparison
INITUTIL_LOOP_3:
        BSR.W   ClkRW                           | write 16 bytes
        MOVE.B  D2,(A2)+                        | RTC write command for second block
        SUBQ.B  #0x4,D1                         | next register address (descending)
        DBRA    D5,INITUTIL_LOOP_3              | loop 8 reads
        CMPM.L  (A3)+,(A3)+                     | compare first 4 bytes with second 4
        BEQ.B   INITUTIL_FOUND                  | match -> valid read
        DBRA    D4,INITUTIL_LOOP_2              | retry once
        MOVEQ.L #-0x55,D0                       | clkRdErr (-85): read failed
INITUTIL_FOUND:
        MOVE.L  (Scratch20).w,(Time).w          | store time in low-mem global
        MOVEM.L (SP)+,D1-D2/D4-D5/A2-A3         | restore registers
        TST     D0                              | set CCR for caller
        RTS                                     | return to caller (@ $4FC2)
| ----------------------------------------------------------
| INITUTIL_CONT_2: write date/time to RTC chip (for SetDateTime)
| Writes 4 bytes, reads back to verify
INITUTIL_CONT_2:
        MOVEM.L D1-D5,-(SP)                     | save registers
        BSR.B   WPOff                           | disable write protect
        MOVE.L  (Time).w,D3                     | D3 = time value to write
        MOVEQ.L #0x1,D5                         | retry count
INITUTIL_LOOP_4:
        MOVE.L  D3,D2                           | D2 = data to write (shifts out)
        MOVEQ.L #0x1,D1                         | RTC command: write seconds ($01)
        MOVEQ.L #0x3,D4                         | 4 bytes to write
INITUTIL_LOOP_5:
        BSR.B   ClkRW                           | write one byte to RTC
        ADDQ.B  #0x4,D1                         | next RTC register address
        LSR.L   #0x8,D2                         | shift to next byte
        DBRA    D4,INITUTIL_LOOP_5              | loop 4 bytes
        BSR.B   INITUTIL_CONT                   | read time back from RTC
        BNE.B   INITUTIL_ERR_2                  | read error -> done
        CMP.L   (Time).w,D3                     | written value matches read?
        BEQ.B   INITUTIL_ERR_2                  | yes -> success
        DBRA    D5,INITUTIL_LOOP_4              | retry once
        MOVEQ.L #-0x56,D0                       | clkWrErr (-86): write failed
INITUTIL_ERR_2:
        BSR.B   WPOn                            | re-enable write protect
        MOVEM.L (SP)+,D1-D5                     | restore registers
        RTS                                     | return from SetDateTime
WPOn:
        MOVEQ.L #0x35,D1                        | RTC command: write protect register
        MOVEQ.L #-0x2B,D2                       | data = $D5 (enable WP)
        BRA.B   ClkRW                           | tail-call ClkRW (write to RTC)
WPOff:
        MOVEQ.L #0x35,D1                        | RTC command: write protect register
        MOVEQ.L #0x55,D2                        | data = $55 (disable WP)
        BRA.B   ClkRW                           | tail-call ClkRW (write to RTC)
WPOFF_CONT:
        MOVEM.L D1-D3/A2,-(SP)                  | save regs
        BSR.B   WPOff                           | disable write protect
        LEA.L     (SysParam_SPValid).w,A2       | A2 = source (SysParam block)
        MOVE.B  #0x41,D1                        | RTC write command for first block
        MOVEQ.L #0xF,D3                         | 16 bytes in first block
        BSR.B   WPOFF_LOOP                      | write 16 bytes
        MOVE.B  #0x21,D1                        | RTC write command for second block
        MOVEQ.L #0x3,D3                         | 4 bytes in second block
        BSR.B   WPOFF_LOOP                      | write 4 bytes
        BSR.B   WPOn                            | re-enable write protect
        MOVEM.L (SP)+,D1-D3/A2                  | restore regs
        RTS                                     | return from WPOFF_CONT (WritePRAM)
WPOFF_LOOP:
        MOVE.B  (A2)+,D2                        | D2 = next byte to write
        BSR.B   ClkRW                           | write byte to RTC register
        ADDQ.B  #0x4,D1                         | next RTC register address
        DBRA    D3,WPOFF_LOOP                   | loop bytes
        RTS                                     | return from WPOFF_LOOP
