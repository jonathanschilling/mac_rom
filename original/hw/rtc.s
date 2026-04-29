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
| INITUTIL_CONT - read 4-byte time from RTC chip into Time global.
| INITUTIL_CONT_2 - write Time to RTC chip with read-back verify.
| WPOn/WPOff - toggle the RTC's write-protect register ($0D / $8D).
| WPOFF_CONT - write SysParam (20 bytes) to RTC PRAM.
| ClkRW - read or write one RTC register byte (D1=cmd,D2=data).
| Plus 1986 refactored this into a thin trampoline that
| JMPs to the ClkNoMem trap; classic 1984 has the full
| inline bit-bang implementation here.
| WRITE_RTC_BYTE / WRITE_RTC_BIT_LOOP - shift 8 bits out to RTC.
| READ_RTC_BYTE / READ_RTC_BIT_LOOP - shift 8 bits in from RTC.
|
| Plus-only routines absent from classic (real 1986 evolution):
| ClkRW - in classic this is the inline implementation, not
| a trampoline. The trap-table-driven dispatch was a
| Plus refactor.
| ReadXPRam / WriteXPRam - extended PRAM (256 bytes vs 20 bytes)
| only available on hardware with the 256-byte clock
| chip variant. Plus added these traps; classic 1984
| does not expose them.
|
| 128K vs 512K divergence: the IPL-mask byte at $5040 (inside
| ClkRW) differs (1 on 128K, 3 on 512K) -- wrapped in an
| `.if ROM_TARGET == MAC_128K` block.
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
| Called by: READPRAM_LOOP, InitUtil, INITUTIL_LOOP_3, INITUTIL_LOOP_5, WPOn (and 2 more)
ClkRW:
        MOVE    SR,-(SP)                        | save SR (will block interrupts)
        MOVEM.L D1/D3-D5/A1,-(SP)               | save scratch regs
        MOVE.L  #0xEFE1FE,A1                    | absolute-long addressing
| --- ROM-variant difference @ $5040 (interrupt-mask immediate) ---
| MAC_128K: ORI.W #0x100,SR -- raise IPL mask to level 1
| MAC_512K: ORI.W #0x300,SR -- raise IPL mask to level 3 (blocks VIA too)
| Reason: 1984-10 revision widened the interrupt lockout around a
| critical font-cache update so that VIA Timer 2 interrupts can't
| preempt it either.
.if ROM_TARGET == MAC_128K
        ORI     #0x100,SR                       | 128K: IPL->1
.else
        ORI     #0x300,SR                       | 512K: IPL->3
.endif
        MOVE.B  (A1),D3                         | D3 = current VIA Port B state
        MOVEQ.L #0x1,D4                         | D4 = vRTCClk bit position
        ANDI.B  #0xF9,D3                        | clear rtcClk + rtcEnb (start condition)
        TST.B   D1                              | command bit 7 = read flag?
        BMI.B   CLKRW_READ                      | yes -> read sequence
        BSR.B   WRITE_RTC_BYTE                  | write command byte to RTC
        MOVE    D2,D1                           | D1 = data byte to write
        BSR.B   WRITE_RTC_BYTE                  | write data byte to RTC
        BRA.B   CLKRW_EXIT                      | done -> deassert chip-enable
CLKRW_READ:
        BSR.B   WRITE_RTC_BYTE                  | write read-command byte
        BSR.B   READ_RTC_BYTE                   | read data byte from RTC into D2
CLKRW_EXIT:
        BSET    #0x2,(A1)                       | set rtcEnb (deselect RTC)
        MOVEM.L (SP)+,D1/D3-D5/A1               | restore scratch regs
        RTE                                     | restore SR + return (was MOVE SR,-(SP))
WRITE_RTC_BYTE:
        MOVEQ.L #0x7,D5                         | 8-bit shift count
| WriteRTCByte bit-shift loop
WRITE_RTC_BIT_LOOP:
        ROR.B   #0x1,D3                         | rotate prev VIA bit out of LSB
        ROXL.B  #0x1,D1                         | X = next data bit (MSB first)
        ROXL.B  #0x1,D3                         | insert data bit into D3 LSB (rtcData)
        MOVE.B  D3,(A1)                         | drive Port B with clk=0, data bit
        BSET    D4,(A1)                         | pulse rtcClk high (latches bit into RTC)
        DBRA    D5,WRITE_RTC_BIT_LOOP           | next bit
        RTS                                     | return to caller (@ $5074)
READ_RTC_BYTE:
        MOVEQ.L #0x7,D5                         | 8-bit shift count
        BCLR    #0x0,vDIRB(A1)                  | clear PortB bit 0 direction (drive data line as input)
        MOVE.B  D3,D4                           | D4 = base port B value
        BSET    #0x1,D4                         | D4 = port B with rtcClk high
| ReadRTCByte bit-clock loop
READ_RTC_BIT_LOOP:
        MOVE.B  D3,(A1)                         | drive port with rtcClk=0
        MOVE.B  D4,(A1)                         | drive port with rtcClk=1 (RTC outputs bit)
        MOVE.B  (A1),D1                         | sample port B back from RTC
        LSR.B   #0x1,D1                         | shift rtcData bit (LSB) into X
        ROXL.B  #0x1,D2                         | rotate sampled bit into D2 (MSB first)
        DBRA    D5,READ_RTC_BIT_LOOP            | next bit
        BSET    #0x0,vDIRB(A1)                  | set PortB bit 0 direction (drive data line as output)
        RTS                                     | return D2 = read byte
