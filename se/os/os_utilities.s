| Operating System Utilities
|
| Apple source: SysUtil.a (MacSEROM.lst module SYSUTIL). In ROM order:
|   ASYNCPATCH                 - (an RTS: patch point)
|   ReadParam, WriteParam      - parameter RAM: low-memory copy SysParam <->
|                                clock chip
|   ReadDateTime, SetDateTime  - the clock (Time)
|   Delay                      - wait D0 ticks
|   CmpString (EqualString), RelString, UprString, with the character
|                                tables CONVERSION_TBL / STRIP_TBL
|   ReadPRAM                   - read the 20 bytes of parameter RAM
|   InitUtil                   - _InitUtil: copy parameter RAM to SysParam,
|                                write the defaults if it is invalid
|   WPOn, WPOff                - clock chip write protect
| The bit-level clock chip access (ClkRW, _ReadXPRam, _WriteXPRam, ClkNoMem) is
| in hw/rtc.s.
|
| References: Inside Macintosh Vol II, Ch 13 (Operating System Utilities).

| Apple source module: SYSUTIL
ASYNCPATCH:
    RTS                                         | return from ASYNCPATCH
READPARAM:
    LEA.L	(SysParam_SPValid).W,A1               | A1 = system parameter RAM
    BSR.B	READPARAM_CONT                        | copy selected bytes
    MOVEQ.L	#0x0,D0                             | result = noErr
    RTS                                         | return from ReadParam
| ----------------------------------------------------------
|
| READPARAM_CONT
|
| READPARAM_CONT: copy selected bytes from A1 to A0 based on D0 bitmask
| Iterates 20 bytes; if corresponding bit in D0 is set, copies byte
READPARAM_CONT:
    MOVEQ.L	#0x13,D2                            | 20 bytes to scan
READPARAM_LOOP:
    LSR.L	#0x1,D0                               | shift out next bit
    BCC.B	READPARAM_SKIP                        | bit clear: skip this byte
    MOVE.B	(A1),(A0)+                           | copy selected byte
READPARAM_SKIP:
    ADDQ.L	#0x1,A1                              | next source byte
    DBF.W	D2,READPARAM_LOOP                     | loop for 20 bytes
    RTS                                         | return from ReadParam
WRITEPARAM:
    BSR.W	WPOFF_CONT                            | write param RAM to hardware
    LEA.L	(Scratch20).W,A1                      | scratch buffer
    BSR.W	READPRAM                              | read back from hardware
    LEA.L	(SysParam_SPValid).W,A0               | compare against in-memory copy
    MOVEQ.L	#-0x57,D0                           | D0 = prWriteErr (-87)
    MOVEQ.L	#0x4,D2                             | 5 longwords = 20 bytes
WRITEPARAM_LOOP:
    CMPM.L	(A0)+,(A1)+                          | verify byte matches
    BNE.B	WRITEPARAM_ERR                        | mismatch: return error ->
    DBF.W	D2,WRITEPARAM_LOOP                    | check all 20 bytes
    MOVEQ.L	#0x0,D0                             | result = noErr
WRITEPARAM_ERR:
    RTS                                         | return from WRITEPARAM_ERR
READDATETIME:
    BSR.W	INITUTIL_CONT                         | read RTC into Time
    MOVE.L	(Time).W,(A0)                        | return time to caller
    RTS                                         | return from ReadDateTime
SETDATETIME:
    MOVE.L	D0,(Time).W                          | set system time
    BRA.W	INITUTIL_CONT_2                       | write time to RTC
DELAY:
    MOVE.W	#0x2000,SR                           | enable interrupts (IPL=0)
    MOVE.L	(Ticks).W,D0                         | current tick count
    ADD.L	A0,D0                                 | + delay count = target tick
DELAY_LOOP:
    CMP.L	(Ticks).W,D0                          | reached target?
    BGT.B	DELAY_LOOP                            | no, keep waiting
    RTS                                         | return from DELAY_LOOP
| ----------------------------------------------------------
|
| CMPSTRING
|
| CmpString: lengths differ -> not equal
CMPSTRING:
    MOVE.W	D0,D2                                | D2 = str1 length
    SWAP.W	D0                                   | D0 = str2 length
    CMP.W	D0,D2                                 | same length?
    BNE.B	CMPSTRING_NOTEQUAL                    | no, not equal ->
    SWAP.W	D0                                   | restore D0
    BSR.B	RELSTRING                             | compare characters
    BPL.B	CMPSTRING_CONT                        | result >= 0 ->
    NEG.L	D0                                    | make positive (abs value)
CMPSTRING_CONT:
    RTS                                         | return D0: 0=equal, >0=not equal
CMPSTRING_NOTEQUAL:
    MOVEQ.L	#0x1,D0                             | result = not equal
    RTS                                         | return from CmpString
RELSTRING:
    BSR.B	RELSTRING_CONT_4                      | set up comparison tables
    MOVEQ.L	#0x0,D4                             | D4 = 0 (equal so far)
    MOVE.W	D0,D2                                | D2 = str1 length
    SWAP.W	D0                                   | D0 = str2 length
    CMP.W	D0,D2                                 | compare lengths
    BEQ.B	RELSTRING_LOOP_2                      | equal, compare all ->
    BHI.B	RELSTRING_OK                          | str1 longer ->
    MOVEQ.L	#0x1,D4                             | str1 shorter: bias = +1
    MOVE.W	D2,D0                                | D0 = min length
    CMP.W	D4,D4                                 | set Z flag
    BRA.B	RELSTRING_LOOP_2                      | ->
| ----------------------------------------------------------
|
| RELSTRING_OK
|
| Called during boot.
RELSTRING_OK:
    MOVEQ.L	#-0x1,D4                            | str1 longer: bias = -1
    CMP.W	D4,D4                                 | set Z flag
    BRA.B	RELSTRING_LOOP_2                      | ->
| ----------------------------------------------------------
|
| RELSTRING_LOOP
|
| Called during boot.
RELSTRING_LOOP:
    MOVEQ.L	#0x0,D2                             | clear high byte
    MOVE.B	(A0)+,D2                             | next char from str1
    BSR.B	RELSTRING_CONT                        | apply case/diacritical mapping
    ADD.W	D2,D2                                 | word index into sort table
    MOVE.W	0x0(A3,D2.W),D3                      | D3 = sort weight for str1 char
    MOVEQ.L	#0x0,D2                             | clear high byte
    MOVE.B	(A1)+,D2                             | next char from str2
    BSR.B	RELSTRING_CONT                        | apply case/diacritical mapping
    ADD.W	D2,D2                                 | word index into sort table
    CMP.W	0x0(A3,D2.W),D3                       | compare sort weights
RELSTRING_LOOP_2:
    DBNE.W	D0,RELSTRING_LOOP                    | loop until mismatch or end
    BEQ.B	RELSTRING_EXIT_2                      | all equal ->
    BHI.B	RELSTRING_EXIT                        | str1 > str2 ->
    MOVEQ.L	#-0x1,D0                            | str1 < str2
    BRA.B	RELSTRING_EXIT_3                      | ->
| ----------------------------------------------------------
|
| RELSTRING_EXIT
|
| Called during boot.
RELSTRING_EXIT:
    MOVEQ.L	#0x1,D4                             | str1 > str2
RELSTRING_EXIT_2:
    MOVE.L	D4,D0                                | D0 = length-based tiebreaker
RELSTRING_EXIT_3:
    BRA.B	RELSTRING_EXIT_4                      | -> restore regs
| ----------------------------------------------------------
|
| RELSTRING_CONT
|
| Called during boot.
RELSTRING_CONT:
    TST.W	D1                                    | diacritical-sensitive?
    BPL.B	RELSTRING_CONT_2                      | yes, skip stripping ->
    MOVE.B	DIAC_STRIP_TBL(PC,D2.W),D2           | strip diacriticals
RELSTRING_CONT_2:
    TST.B	D1                                    | case-sensitive?
    BMI.B	RELSTRING_CONT_3                      | yes, skip conversion ->
    MOVE.B	0x0(A2,D2.W),D2                      | convert to uppercase
RELSTRING_CONT_3:
    RTS                                         | return char in D2
| ----------------------------------------------------------
|
| RELSTRING_CONT_4
|
| RELSTRING_CONT_4: set up character comparison tables for string operations
| D1 encodes case/marks sensitivity flags
| A2 = uppercase table (CONVERSION_TBL), A3 = diacritical stripping table (STRIP_TBL)
RELSTRING_CONT_4:
    MOVE.L	(A7)+,D2                             | D2 = caller's return addr
    MOVEM.L	D2-D4/A2-A3,-(A7)                   | save regs + return addr
    LEA.L	UPPER_FOLD_TBL(PC),A2                 | A2 = uppercase table
    LEA.L	STRIP_TBL(PC),A3                      | A3 = sort weight table
    ROL.W	#0x6,D1                               | encode case/marks flags
    ROR.B	#0x1,D1                               | into D1.W and D1.B sign bits
    MOVEQ.L	#0x0,D2                             | clear working reg
    RTS                                         | return from RELSTRING_CONT_4
| ----------------------------------------------------------
|
| RELSTRING_EXIT_4
|
| RelString/CmpString exit: restore regs
RELSTRING_EXIT_4:
    MOVEM.L	(A7)+,D3-D4/A2-A3                   | restore regs
    RTS                                         | return from RelString
UPRSTRING:
    BSR.B	RELSTRING_CONT_4                      | set up conversion tables
    BRA.B	UPPERSTRING_LOOP_2                    | -> loop entry
| ----------------------------------------------------------
|
| UPPERSTRING_LOOP
|
UPPERSTRING_LOOP:
    MOVE.B	(A0),D2                              | get char
    BSR.B	RELSTRING_CONT                        | apply case/diacritical mapping
    MOVE.B	D2,(A0)+                             | store converted char
UPPERSTRING_LOOP_2:
    DBF.W	D0,UPPERSTRING_LOOP                   | loop for all chars
    MOVEQ.L	#0x0,D0                             | result = noErr
    BRA.B	RELSTRING_EXIT_4                      | -> restore regs
| ----------------------------------------------------------
| DIAC_STRIP_TBL (= DIAC_STRIP_TBL): 256-byte diacritical-stripping
| table indexed by char code. ASCII portion (0x00..0x7F) is
| identity (case preserved). High-bit chars (0x80..0xFF)
| collapse accented Mac extended characters to their base
| ASCII letter for the diacritic-insensitive comparison mode
| of RelString/IUEqualString/IUMagString. Examples:
|   0x80 (A-umlaut)  -> 0x41 'A'    0x8E (e-acute)   -> 0x65 'e'
|   0x82 (C-cedilla) -> 0x43 'C'    0x97 (o-grave)   -> 0x6F 'o'
|   0x83 (E-acute)   -> 0x45 'E'    0xCB (A-grave)   -> 0x41 'A'
|   0x84 (N-tilde)   -> 0x4E 'N'    0xCC (A-tilde)   -> 0x41 'A'
| Used at RELSTRING_CONT (line 19361) when D1 sign bit is clear.
DIAC_STRIP_TBL:
    .long	0x00010203
    .long	0x04050607
    .long	0x08090A0B
    .long	0x0C0D0E0F
    .long	0x10111213
    .long	0x14151617
    .long	0x18191A1B
    .long	0x1C1D1E1F
    .long	0x20212223
    .long	0x24252627
    .long	0x28292A2B
    .long	0x2C2D2E2F
    .long	0x30313233
    .long	0x34353637
    .long	0x38393A3B
    .long	0x3C3D3E3F
    .long	0x40414243
    .long	0x44454647
    .long	0x48494A4B
    .long	0x4C4D4E4F
    .long	0x50515253
    .long	0x54555657
    .long	0x58595A5B
    .long	0x5C5D5E5F
    .long	0x60616263
    .long	0x64656667
    .long	0x68696A6B
    .long	0x6C6D6E6F
    .long	0x70717273
    .long	0x74757677
    .long	0x78797A7B
    .long	0x7C7D7E7F
    .long	0x41414345
    .long	0x4E4F5561
    .long	0x61616161
    .long	0x61636565
    .long	0x65656969
    .long	0x69696E6F
    .long	0x6F6F6F6F
    .long	0x75757575
    .long	0xA0A1A2A3
    .long	0xA4A5A6A7
    .long	0xA8A9AAAB
    .long	0xACADAE4F
    .long	0xB0B1B2B3
    .long	0xB4B5B6B7
    .long	0xB8B9BA61
    .long	0x6FBDBE6F
    .long	0xC0C1C2C3
    .long	0xC4C5C6C7
    .long	0xC8C9CA41
    .long	0x414FCECF
    .long	0xD0D1D2D3
    .long	0xD4D5D6D7
    .long	0x79D9DADB
    .long	0xDCDDDEDF
    .long	0xE0E1E2E3
    .long	0xE4E5E6E7
    .long	0xE8E9EAEB
    .long	0xECEDEEEF
    .long	0xF0F1F2F3
    .long	0xF4F5F6F7
    .long	0xF8F9FAFB
    .long	0xFCFDFEFF
| ----------------------------------------------------------
| UPPER_FOLD_TBL (= UPPER_FOLD_TBL): 256-byte case-folding table
| indexed by char code. Folds ASCII a-z (0x61..0x7A) to A-Z
| (0x41..0x5A) and high-bit Mac chars to their case-folded
| equivalent for the case-insensitive mode of RelString/
| UpperString/IUEqualString. ASCII 0x00..0x40 unchanged,
| 0x60 (`) -> 0x61 (a) is a quirk preserved from earlier ROMs.
| A2 register is loaded with this table at RELSTRING_CONT_4.
UPPER_FOLD_TBL:
    .long	0x00010203
    .long	0x04050607
    .long	0x08090A0B
    .long	0x0C0D0E0F
    .long	0x10111213
    .long	0x14151617
    .long	0x18191A1B
    .long	0x1C1D1E1F
    .long	0x20212223
    .long	0x24252627
    .long	0x28292A2B
    .long	0x2C2D2E2F
    .long	0x30313233
    .long	0x34353637
    .long	0x38393A3B
    .long	0x3C3D3E3F
    .long	0x40414243
    .long	0x44454647
    .long	0x48494A4B
    .long	0x4C4D4E4F
    .long	0x50515253
    .long	0x54555657
    .long	0x58595A5B
    .long	0x5C5D5E5F
    .long	0x61414243
    .long	0x44454647
    .long	0x48494A4B
    .long	0x4C4D4E4F
    .long	0x50515253
    .long	0x54555657
    .long	0x58595A7B
    .long	0x7C7D7E7F
    .long	0x80818283
    .long	0x84858687
    .long	0xCB8980CC
    .long	0x8182838F
    .long	0x90919293
    .long	0x94958497
    .long	0x989985CD
    .long	0x9C9D9E86
    .long	0xA0A1A2A3
    .long	0xA4A5A6A7
    .long	0xA8A9AAAB
    .long	0xACADAEAF
    .long	0xB0B1B2B3
    .long	0xB4B5B6B7
    .long	0xB8B9BABB
    .long	0xBCBDAEAF
    .long	0xC0C1C2C3
    .long	0xC4C5C6C7
    .long	0xC8C9CACB
    .long	0xCCCDCECE
    .long	0xD0D1D2D3
    .long	0xD4D5D6D7
    .long	0xD8D9DADB
    .long	0xDCDDDEDF
    .long	0xE0E1E2E3
    .long	0xE4E5E6E7
    .long	0xE8E9EAEB
    .long	0xECEDEEEF
    .long	0xF0F1F2F3
    .long	0xF4F5F6F7
    .long	0xF8F9FAFB
    .long	0xFCFDFEFF
| ----------------------------------------------------------
| STRIP_TBL: 256-entry x 16-bit international-collation weight
| table. Each entry packs (primary_char << 8) | diacritic_weight,
| where primary_char is the base ASCII letter for collation and
| diacritic_weight is a low-byte priority used as a secondary
| sort key when two strings differ only in diacriticals. ASCII
| 0x00..0x5F have the form 0xCC00 (char, no diacritic). Lowercase
| a-z (0x60..0x7F slot range) uses 0x4180/0x4280/etc. = uppercase
| with no-diacritic top-bit flag. High-bit chars 0x80+ map to
| (base_letter, diacritic_kind) pairs (e.g. 0x80 -> 0x4108 =
| 'A' + diacritic 0x08 = umlaut). A3 register is loaded with
| this table at RELSTRING_CONT_4.
STRIP_TBL:
    .long	0x00000100
    .long	0x02000300
    .long	0x04000500
    .long	0x06000700
    .long	0x08000900
    .long	0x0A000B00
    .long	0x0C000D00
    .long	0x0E000F00
    .long	0x10001100
    .long	0x12001300
    .long	0x14001500
    .long	0x16001700
    .long	0x18001900
    .long	0x1A001B00
    .long	0x1C001D00
    .long	0x1E001F00
    .long	0x20002100
    .long	0x22002300
    .long	0x24002500
    .long	0x26002700
    .long	0x28002900
    .long	0x2A002B00
    .long	0x2C002D00
    .long	0x2E002F00
    .long	0x30003100
    .long	0x32003300
    .long	0x34003500
    .long	0x36003700
    .long	0x38003900
    .long	0x3A003B00
    .long	0x3C003D00
    .long	0x3E003F00
    .long	0x40004100
    .long	0x42004300
    .long	0x44004500
    .long	0x46004700
    .long	0x48004900
    .long	0x4A004B00
    .long	0x4C004D00
    .long	0x4E004F00
    .long	0x50005100
    .long	0x52005300
    .long	0x54005500
    .long	0x56005700
    .long	0x58005900
    .long	0x5A005B00
    .long	0x5C005D00
    .long	0x5E005F00
    .long	0x61004180
    .long	0x42804380
    .long	0x44804580
    .long	0x46804780
    .long	0x48804980
    .long	0x4A804B80
    .long	0x4C804D80
    .long	0x4E804F80
    .long	0x50805180
    .long	0x52805380
    .long	0x54805580
    .long	0x56805780
    .long	0x58805980
    .long	0x5A807B00
    .long	0x7C007D00
    .long	0x7E007F00
    .long	0x4108410C
    .long	0x43104502
    .long	0x4E0A4F08
    .long	0x55084182
    .long	0x41844186
    .long	0x4188418A
    .long	0x418C4390
    .long	0x45824584
    .long	0x45864588
    .long	0x49824984
    .long	0x49864988
| STRIP_TBL (continued): entries $96-$FF
    .long	0x4E8A4F82
    .long	0x4F844F86
    .long	0x4F884F8A
    .long	0x55825584
    .long	0x55865588
    .long	0xA000A100
    .long	0xA200A300
    .long	0xA400A500
    .long	0xA6005382
    .long	0xA800A900
    .long	0xAA00AB00
    .long	0xAC00AD00
    .long	0x41144F0E
    .long	0xB000B100
    .long	0xB200B300
    .long	0xB400B500
    .long	0xB600B700
    .long	0xB800B900
    .long	0xBA004192
    .long	0x4F92BD00
    .long	0x41944F8E
    .long	0xC000C100
    .long	0xC200C300
    .long	0xC400C500
    .long	0xC6002206
    .long	0x2208C900
    .long	0x20004104
    .long	0x410A4F0A
    .long	0x4F144F94
    .long	0xD000D100
    .long	0x22022204
    .long	0x27022704
    .long	0xD600D700
    .long	0x5988D900
    .long	0xDA00DB00
    .long	0xDC00DD00
    .long	0xDE00DF00
    .long	0xE000E100
    .long	0xE200E300
    .long	0xE400E500
    .long	0xE600E700
    .long	0xE800E900
    .long	0xEA00EB00
    .long	0xEC00ED00
    .long	0xEE00EF00
    .long	0xF000F100
    .long	0xF200F300
    .long	0xF400F500
    .long	0xF600F700
    .long	0xF800F900
    .long	0xFA00FB00
    .long	0xFC00FD00
    .long	0xFE00FF00
| READPRAM - called from 2 places

READPRAM:
    MOVEM.L	D1-D2/D5/A1,-(A7)                   | save regs
    MOVEQ.L	#-0x3F,D1                           | $C1: first PRAM read command
    MOVEQ.L	#0xF,D5                             | 16 bytes in first block
    BSR.B	READPRAM_LOOP                         | read 16 bytes
    MOVEQ.L	#-0x5F,D1                           | $A1: second PRAM block
    MOVEQ.L	#0x3,D5                             | 4 bytes in second block
    BSR.B	READPRAM_LOOP                         | read 4 bytes
    MOVEM.L	(A7)+,D1-D2/D5/A1                   | restore regs
    RTS                                         | return from ReadPRAM
| ----------------------------------------------------------
|
| READPRAM_LOOP: read consecutive RTC registers into buffer at A1
| D1 = starting RTC command, D5 = byte count - 1
|
| Called during boot.
READPRAM_LOOP:
    JSR	CLKRW(PC)                               | read one RTC register -> D2
    MOVE.B	D2,(A1)+                             | store byte, advance ptr
    ADDQ.B	#0x4,D1                              | next RTC register address
    DBF.W	D5,READPRAM_LOOP                      | loop for all bytes
    RTS                                         | return from ReadPRAM loop
| ----------------------------------------------------------
|
| READPRAM_CONT
|
READPRAM_CONT:
    .long	0xA8000000
    .long	0xCC0ACC0A
    .long	0x00000000
    .long	0x00026300
    .long	0x0388004C
INITUTIL:
    CLR.W	-(A7)                                 | space for result code
    BSR.W	WPOFF                                 | disable RTC write protect
    MOVEQ.L	#0x31,D1                            | RTC cmd: write test register
    CLR.B	D2                                    | data = 0 (clear test mode)
    JSR	CLKRW(PC)                               | write to RTC
    BSR.W	WPON                                  | re-enable write protect
    LEA.L	(SysParam_SPValid).W,A1               | A1 = SysParam destination
    BSR.B	READPRAM                              | read 20 bytes from PRAM
    BSR.B	INITUTIL_CONT                         | read date/time -> Time
    MOVEQ.L	#0x0,D0                             | assume noErr
    CMPI.B	#0xA8,(A1)                           | valid PRAM signature ($A8)?
    BEQ.B	INITUTIL_OK                           | yes ->
    MOVE.W	#0xFFA8,(A7)                         | prInitErr (-88)
    MOVEQ.L	#0x4,D1                             | 5 longwords = 20 bytes
    LEA.L	READPRAM_CONT(PC),A0                  | A0 = default PRAM values
INITUTIL_LOOP:
    MOVE.L	(A0)+,(A1)+                          | copy defaults to SysParam
    DBF.W	D1,INITUTIL_LOOP                      | loop 5 longwords
    BSR.W	WPOFF_CONT                            | write defaults to RTC PRAM
| check for extended PRAM (Mac Plus has 256 bytes)
INITUTIL_OK:
    BTST	#0x6,(HWCfgFlags)                      | extended PRAM available?
    BEQ.B	INITUTIL_NO                           | no ->
    LEA.L	(Scratch20).W,A0                      | temp buffer
    MOVE.L	#0x4000C,D0                          | length 4, offset 12
    _ReadXPRam                                  | read XPRAM signature
    MOVE.L	#0x42756773,D1                       | 'Bugs' signature
    CMP.L	(A0),D1                               | already initialized?
    BEQ.B	INITUTIL_NO                           | yes ->
    MOVE.W	#0xFFA8,(A7)                         | set prInitErr
    MOVE.L	D1,(A0)                              | write 'Bugs' to buffer
    MOVE.L	#0x4000C,D0                          | length 4, offset 12
    _WriteXPRam                                 | write signature to XPRAM
    MOVEQ.L	#0x20,D1                            | start zeroing from offset $20
INITUTIL_DONE:
    MOVEQ.L	#0x4,D0                             | length 4
    SWAP.W	D0                                   | D0.hi = 4
    MOVE.W	D1,D0                                | D0.lo = offset
    CLR.L	(A0)                                  | zero buffer
    _WriteXPRam                                 | clear 4 XPRAM bytes
    ADDQ.B	#0x4,D1                              | next offset
    CMPI.B	#0x8,D1                              | wrapped to offset 8?
    BNE.B	INITUTIL_DONE                         | no, keep clearing
INITUTIL_NO:
    MOVE.W	(A7)+,D0                             | D0 = init result code
    BNE.B	INITUTIL_ERR                          | error, skip flag set ->
    BSET	#0x5,(HWCfgFlags)                      | PRAM initialized ok
INITUTIL_ERR:
    EXT.L	D0                                    | sign-extend error code
    RTS                                         | return from InitUtil
| ----------------------------------------------------------
|
| INITUTIL_CONT
|
| Called during boot.
| INITUTIL_CONT: read date/time from RTC chip (4 bytes, read twice for consistency)
| RTC stores seconds since midnight Jan 1, 1904 as 4 bytes
| Reads twice and compares to detect mid-update glitches
INITUTIL_CONT:
    MOVEM.L	D1-D2/D4-D5/A2-A3,-(A7)             | save regs
    MOVEQ.L	#0x1,D4                             | retry count = 1 (read up to 2x)
    MOVEQ.L	#0x0,D0                             | assume noErr
INITUTIL_LOOP_2:
    MOVEQ.L	#-0x63,D1                           | $9D: RTC read seconds command
    MOVEQ.L	#0x7,D5                             | 8 reads (4 bytes x 2 for verify)
    LEA.L	(Scratch20).W,A2                      | dest buffer
    MOVEA.L	A2,A3                               | save start for comparison
INITUTIL_LOOP_3:
    JSR	CLKRW(PC)                               | read one RTC register byte
    MOVE.B	D2,(A2)+                             | store byte
    SUBQ.B	#0x4,D1                              | next register address
    DBF.W	D5,INITUTIL_LOOP_3                    | read 8 bytes total
    CMPM.L	(A3)+,(A3)+                          | first 4 == second 4?
    BEQ.B	INITUTIL_FOUND                        | match: valid read ->
    DBF.W	D4,INITUTIL_LOOP_2                    | retry once
    MOVEQ.L	#-0x55,D0                           | clkRdErr (-85)
INITUTIL_FOUND:
    MOVE.L	(Scratch20).W,(Time).W               | store in Time global
    MOVEM.L	(A7)+,D1-D2/D4-D5/A2-A3             | restore regs
    TST.L	D0                                    | set condition codes
    RTS                                         | return from INITUTIL_FOUND
| ----------------------------------------------------------
|
| INITUTIL_CONT_2: write date/time to RTC chip (for SetDateTime)
| Writes 4 bytes, reads back to verify
INITUTIL_CONT_2:
    MOVEM.L	D1-D5,-(A7)                         | save regs
    BSR.B	WPOFF                                 | disable RTC write protect
    MOVE.L	(Time).W,D3                          | D3 = time value to write
    MOVEQ.L	#0x1,D5                             | retry count
INITUTIL_LOOP_4:
    MOVE.L	D3,D2                                | D2 = data to write (shifts out)
    MOVEQ.L	#0x1,D1                             | RTC cmd: write seconds ($01)
    MOVEQ.L	#0x3,D4                             | 4 bytes to write
INITUTIL_LOOP_5:
    JSR	CLKRW(PC)                               | write one byte to RTC
    ADDQ.B	#0x4,D1                              | next register address
    LSR.L	#0x8,D2                               | shift to next byte
    DBF.W	D4,INITUTIL_LOOP_5                    | write all 4 bytes
    BSR.B	INITUTIL_CONT                         | read back and verify
    BNE.B	INITUTIL_ERR_2                        | read error ->
    CMP.L	(Time).W,D3                           | matches what we wrote?
    BEQ.B	INITUTIL_ERR_2                        | yes, success ->
    DBF.W	D5,INITUTIL_LOOP_4                    | retry once
    MOVEQ.L	#-0x56,D0                           | clkWrErr (-86)
INITUTIL_ERR_2:
    BSR.B	WPON                                  | re-enable write protect
    MOVEM.L	(A7)+,D1-D5                         | restore regs
    RTS                                         | return from SetDateTime
WPON:
    MOVEQ.L	#0x35,D1                            | RTC cmd: write-protect register
    MOVEQ.L	#-0x2B,D2                           | $D5: enable write protect
    JMP	CLKRW(PC)                               | write to RTC
WPOFF:
    MOVEQ.L	#0x35,D1                            | RTC cmd: write-protect register
    MOVEQ.L	#0x55,D2                            | $55: disable write protect
    JMP	CLKRW(PC)                               | write to RTC
| ----------------------------------------------------------
|
| WPOFF_CONT: write SysParam (20 bytes) to RTC PRAM
|
WPOFF_CONT:
    MOVEM.L	D1-D3/A2,-(A7)                      | save regs
    BSR.B	WPOFF                                 | disable write protect
    LEA.L	(SysParam_SPValid).W,A2               | A2 = SysParam source
    MOVE.B	#0x41,D1                             | $41: first PRAM write cmd
    MOVEQ.L	#0xF,D3                             | 16 bytes in first block
    BSR.B	WPOFF_LOOP                            | write 16 bytes
    MOVE.B	#0x21,D1                             | $21: second PRAM block
    MOVEQ.L	#0x3,D3                             | 4 bytes in second block
    BSR.B	WPOFF_LOOP                            | write 4 bytes
    BSR.B	WPON                                  | re-enable write protect
    MOVEM.L	(A7)+,D1-D3/A2                      | restore regs
    RTS                                         | return from WritePRAM
| ----------------------------------------------------------
|
| WPOFF_LOOP: write consecutive bytes from A2 to RTC registers
| D1 = starting RTC command, D3 = byte count - 1
|
WPOFF_LOOP:
    MOVE.B	(A2)+,D2                             | D2 = next byte to write
    JSR	CLKRW(PC)                               | write byte to RTC
    ADDQ.B	#0x4,D1                              | next register address
    DBF.W	D3,WPOFF_LOOP                         | loop for all bytes
    RTS                                         | return from WPOFF_LOOP
