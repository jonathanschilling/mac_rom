| RTC (Real-Time Clock) bit-bang and Parameter RAM (PRAM) access
|
| Low-level bit-banged protocol to talk to the 58321A RTC chip via
| VIA port B. The protocol serializes one bit per VIA write, so each
| byte requires 8 reads or writes interleaved with chip-select /
| shift-register toggling.
|
| Routines:
| ReadPRAM - read 20 bytes of PRAM (16 + 4 in two register blocks)
| into caller's buffer.
| InitUtil - Utility Manager init: read full PRAM, cross-check with
| ROM-default table, write defaults on first-boot.
| WPOn/WPOff - toggle the RTC's write-protect register ($0D / $8D).
| ClkRW - generic read/write one RTC register (Plus only).
| ReadXPRam / WriteXPRam - extended PRAM access (Plus only -- XPRAM
| covers RTC regs beyond the classic PRAM).
| WRITE_RTC_BIT_LOOP / READ_RTC_BIT_LOOP - inner bit-bang loops.
|
| 128K vs 512K divergence: the IPL-mask byte at $5040 (inside
| WPOFF_CONT) differs (1 on 128K, 3 on 512K) -- wrapped in an
| `.if ROM_TARGET == MAC_128K` block (applies to classic only).
|
| References: Inside Macintosh Vol II, Ch 11 (Utility Manager);
| RTC 58321A datasheet (bit-serial protocol).


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
        JSR     ClkRW(PC)                       | read one byte from RTC -> D2
        MOVE.B  D2,(A1)+                        | store byte, advance pointer
        ADDQ.B  #0x4,D1                         | next RTC register address
        DBF     D5,READPRAM_LOOP                | loop
        RTS                                     | return from READPRAM_LOOP

| ----------------------------------------------------------
|
| READPRAM_CONT
|
READPRAM_CONT:
  .byte 0xA8,0x00,0x00,0x00,0xCC,0x0A
  .byte 0xCC,0x0A,0x00,0x00,0x00,0x00
  .byte 0x00,0x02,0x63,0x00,0x03,0x88
  .byte 0x00,0x4C

| _InitUtil ($A03F): initialize Parameter RAM from RTC
| Reads PRAM, validates it, reinitializes if invalid
| Called during boot before most other managers
InitUtil:
        CLR     -(SP)                           | space for result
        BSR     WPOff                           | disable RTC write protect
| reset RTC test register
        MOVEQ.L #0x31,D1                        | RTC command: write test register
        CLR.B   D2                              | data = 0 (clear test mode)
        JSR     ClkRW(PC)                       | write to RTC
        BSR     WPOn                            | re-enable write protect
| read PRAM and date/time
        LEA.L   (SysParam_SPValid).w,A1         | A1 = SysParam destination
        BSR.B   ReadPRAM                        | read 20 bytes from PRAM
        BSR.B   INITUTIL_CONT                   | read date/time from RTC -> Time
| validate PRAM magic byte
        MOVEQ.L #0x0,D0                         | assume noErr
        CMPI.B  #0xA8,(A1)                      | valid PRAM signature? ($A8)
        BEQ.B   INITUTIL_OK                     | yes ->
| invalid PRAM: initialize with defaults from READPRAM_CONT
        MOVE    #-0x58,(SP)                     | prInitErr (-88)
        MOVEQ.L #0x4,D1                         | 5 longwords = 20 bytes
        LEA.L   READPRAM_CONT(PC),A0            | A0 = default PRAM values
INITUTIL_LOOP:
        MOVE.L  (A0)+,(A1)+                     | copy defaults to SysParam
        DBF     D1,INITUTIL_LOOP                | loop 5 longwords
        BSR     WPOFF_CONT                      | write defaults to RTC PRAM
| check for extended PRAM (Mac Plus has 256 bytes)
INITUTIL_OK:
        BTst    #0x6,(HWCfgFlags).w             | extended PRAM available?
        BEQ.B   INITUTIL_NO                     | no ->
        LEA.L   (Scratch20).w,A0                | temp buffer for extended PRAM
        MOVE.L  #0x4000C,D0                     | D0 = length 4, offset 12
        _ReadXPRam                              | read extended PRAM signature
        MOVE.L  #0x42756773,D1                  | D1 = 'Bugs' signature
        CMP.L   (A0),D1                         | signature matches?
        BEQ.B   INITUTIL_NO                     | yes -> extended PRAM is initialized
        MOVE    #-0x58,(SP)                     | set prInitErr
        MOVE.L  D1,(A0)                         | write 'Bugs' signature to buffer
        MOVE.L  #0x4000C,D0                     | D0 = length 4, offset 12
        _WriteXPRam                             | initialize signature in XPRAM
        MOVEQ.L #0x20,D1                        | start zeroing from offset 32 ($20)
INITUTIL_DONE:
        MOVEQ.L #0x4,D0                         | length 4
        SWAP    D0                              | D0.hi = 4
        MOVE    D1,D0                           | D0.lo = offset
        CLR.L   (A0)                            | clear buffer
        _WriteXPRam                             | write 0 to XPRAM
        ADDQ.B  #0x4,D1                         | next offset (wraps at 256)
        CMPI.B  #0x8,D1                         | stop when reaching offset 8 (skips 8..31)
        BNE.B   INITUTIL_DONE                   | loop until done
INITUTIL_NO:
        MOVE    (SP)+,D0                        | D0 = initialization error code
        BNE.B   INITUTIL_ERR                    | if error, skip setting flag
        BSET    #0x5,(HWCfgFlags).w             | set flag: PRAM initialized successfully
INITUTIL_ERR:
        EXT.L   D0                              | sign-extend error code
        RTS                                     | return from InitUtil

| ----------------------------------------------------------
|
| INITUTIL_CONT
|
| Called during boot.
| INITUTIL_CONT: read date/time from RTC chip (4 bytes, read twice for consistency)
| RTC stores seconds since midnight Jan 1, 1904 as 4 bytes
| Reads twice and compares to detect mid-update glitches
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
        JSR     ClkRW(PC)                       | read one RTC register byte
        MOVE.B  D2,(A2)+                        | store byte
        SUBQ.B  #0x4,D1                         | next register address
        DBF     D5,INITUTIL_LOOP_3              | loop 8 times
| verify: first 4 bytes should match second 4 bytes
        CMPM.L  (A3)+,(A3)+                     | compare first 4 with second 4
        BEQ.B   INITUTIL_FOUND                  | match -> valid read
        DBF     D4,INITUTIL_LOOP_2              | retry once
        MOVEQ.L #-0x55,D0                       | clkRdErr (-85): read failed
INITUTIL_FOUND:
        MOVE.L  (Scratch20).w,(Time).w          | store in Time global
        MOVEM.L (SP)+,D1-D2/D4-D5/A2-A3         | restore registers
        TST.L   D0                              | set condition codes
        RTS                                     | return from INITUTIL_CONT (ReadTime)

| ----------------------------------------------------------
|
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
        JSR     ClkRW(PC)                       | write one byte to RTC
        ADDQ.B  #0x4,D1                         | next register
        LSR.L   #0x8,D2                         | shift to next byte
        DBF     D4,INITUTIL_LOOP_5              | loop 4 bytes
| verify: read back and compare
        BSR.B   INITUTIL_CONT                   | read time from RTC
        BNE.B   INITUTIL_ERR_2                  | read error -> done
        CMP.L   (Time).w,D3                     | written value matches read?
        BEQ.B   INITUTIL_ERR_2                  | yes -> success
        DBF     D5,INITUTIL_LOOP_4              | retry once
        MOVEQ.L #-0x56,D0                       | clkWrErr (-86): write failed
INITUTIL_ERR_2:
        BSR.B   WPOn                            | re-enable write protect
        MOVEM.L (SP)+,D1-D5                     | restore regs
        RTS                                     | return from SetDateTime

| ----------------------------------------------------------
|
| WP On
|
| WPOn: enable RTC write protect (write $D5 to WP register)
WPOn:
        MOVEQ.L #0x35,D1                        | RTC command: write protect register
        MOVEQ.L #-0x2B,D2                       | data = $D5 (enable WP)
        JMP     ClkRW(PC)                       | write to RTC

| ----------------------------------------------------------
|
| WPOff: disable RTC write protect (write $55 to WP register)
|
WPOff:
        MOVEQ.L #0x35,D1                        | RTC command: write protect register
        MOVEQ.L #0x55,D2                        | data = $55 (disable WP)
        JMP     ClkRW(PC)                       | write to RTC

| ----------------------------------------------------------
|
| WPOFF_CONT: write SysParam (20 bytes) to RTC PRAM
|
WPOFF_CONT:
        MOVEM.L D1-D3/A2,-(SP)                  | save regs
        BSR.B   WPOff                           | disable write protect
        LEA.L   (SysParam_SPValid).w,A2         | A2 = source (SysParam block)
        MOVE.B  #0x41,D1                        | RTC write command for first block
        MOVEQ.L #0xF,D3                         | 16 bytes in first block
        BSR.B   WPOFF_LOOP                      | write 16 bytes
        MOVE.B  #0x21,D1                        | RTC write command for second block
        MOVEQ.L #0x3,D3                         | 4 bytes in second block
        BSR.B   WPOFF_LOOP                      | write 4 bytes
        BSR.B   WPOn                            | re-enable write protect
        MOVEM.L (SP)+,D1-D3/A2                  | restore regs
        RTS                                     | return from WPOFF_CONT (WritePRAM)

| ----------------------------------------------------------
|
| WPOFF_LOOP: write consecutive bytes from A2 to RTC registers
| D1 = starting RTC command, D3 = byte count - 1
|
WPOFF_LOOP:
        MOVE.B  (A2)+,D2                        | D2 = next byte to write
        JSR     ClkRW(PC)                       | write to RTC register
        ADDQ.B  #0x4,D1                         | next RTC register address
        DBF     D3,WPOFF_LOOP                   | loop
        RTS                                     | return from WPOFF_LOOP

| ----------------------------------------------------------
|
| Clk RW
|
| Called during boot.
ClkRW:
        MOVE    SR,-(SP)                        | save status register
        MOVEM.L D1/D3-D6/A0-A1/A5-A6,-(SP)      | save registers
        LEA.L   CLKRW_EXIT(PC),A5               | A5 = return address for ClkNoMem
        MOVE.L  (0x54C).w,A0                    | $54C is the trap table entry for ClkNoMem
        JMP     (A0)                            | jump to ClkNoMem trap handler

| ----------------------------------------------------------
|
| CLKRW_EXIT
|
| Called during boot.
CLKRW_EXIT:
        MOVEM.L (SP)+,D1/D3-D6/A0-A1/A5-A6      | restore registers
        MOVE    (SP)+,SR                        | restore status register
        RTS                                     | return from ClkRW/CLKRW_EXIT

| ----------------------------------------------------------
|
| CLKRW_CONT
|
| Called during boot.
CLKRW_CONT:
        MOVE.L  A0,A1                           | A1 = buffer pointer
        MOVEQ.L #0x2,D3                         | D3 = command prefix
        MOVE    D0,D4                           | D4 = PRAM offset
        SWAP    D0                              | D0.lo = length
        MOVE    D0,D5                           | D5 = length
        SUBQ.W  #0x1,D5                         | D5 = length - 1 (for DBF loop)
        RTS                                     | return from CLKRW_CONT

| ----------------------------------------------------------
|
| _ReadXPRam ($A051)
|
| Called during boot.
ReadXPRam:
        MOVEM.L D1-D5/A1,-(SP)                  | save registers
        BSR.B   CLKRW_CONT                      | unpack arguments (A1=buf, D4=off, D5=len)
        MOVEQ.L #0x17,D0                        | D0 = read extended PRAM command ($17)
        BRA.B   WRITEXPRAM_CONT                 | execute RTC command

| WriteXPRam -- trap handler for _WriteXPRam ($A052).
| ----------------------------------------------------------
|
| _WriteXPRam ($A052)
|
WriteXPRam:
        MOVEM.L D1-D5/A1,-(SP)                  | save registers
        BSR.B   CLKRW_CONT                      | unpack arguments
        JSR     WPOff(PC)                       | disable RTC write protect
        MOVEQ.L #0x7,D0                         | D0 = write extended PRAM command ($07)
WRITEXPRAM_CONT:
        BTst    #0x6,(HWCfgFlags).w             | extended PRAM available?
        BEQ.B   WRITEXPRAM_ERR                  | no -> return error
WRITEXPRAM_LOOP:
        LSL.B   #0x1,D4                         | shift top bits of offset
        ROXL    #0x1,D0                         | into RTC command word
        DBF     D3,WRITEXPRAM_LOOP              | loop 3 times
        LSL     #0x1,D0                         | align command
        MOVEQ.L #0x6,D3                         | shift remaining 7 bits
WRITEXPRAM_LOOP_2:
        LSL.B   #0x1,D4                         | shift lower bits of offset
        ROXL    #0x1,D0                         | into RTC command word
        DBF     D3,WRITEXPRAM_LOOP_2            | loop 7 times
WRITEXPRAM_LOOP_3:
        MOVE    D0,D1                           | D1 = assembled RTC command
        ROR     #0x8,D1                         | move command byte to low byte for ClkRW
        MOVE.B  (A1),D2                         | D2 = byte to write (ignored if reading)
        BSR.B   ClkRW                           | execute RTC command
        MOVE.B  D2,(A1)+                        | store byte read (ignored if writing)
        ORI.B   #0x80,D0                        | set command bits for next byte
        ADDQ.W  #0x4,D0                         | increment XPRAM address
        ANDI    #-0x4001,D0                     | mask address bits
        ORI     #0x3800,D0                      | set read/write command bits
        DBF     D5,WRITEXPRAM_LOOP_3            | loop for all bytes
        JSR     WPOn(PC)                        | re-enable RTC write protect
        MOVEQ.L #0x0,D0                         | return noErr (0)
WRITEXPRAM_EXIT:
        MOVEM.L (SP)+,D1-D5/A1                  | restore registers
        RTS                                     | return from ReadXPRam/WriteXPRam

| ----------------------------------------------------------
|
| WRITEXPRAM_ERR
|
WRITEXPRAM_ERR:
        MOVEQ.L #-0x57,D0                       | return prWrErr (-87)
        BRA.B   WRITEXPRAM_EXIT                 | -> exit

