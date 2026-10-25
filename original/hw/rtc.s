| Clock chip (RTC) access -- ClkRW
|
| Apple source: Clock.a (MacSEROM.lst module CLOCK). The real-time clock
| is a serial device on VIA port B (data, clock and enable lines): ClkRW
| reads or writes one clock register (D1 = command, D2 = data), with the
| bit loops WRITE_RTC_BYTE / WRITE_RTC_BIT_LOOP and READ_RTC_BYTE /
| READ_RTC_BIT_LOOP. The Mac Plus keeps these bit-banging primitives in
| its startup code (ClkNoMem) and adds the extended parameter RAM traps.
|
| 128K vs 512K divergence: the interrupt-mask immediate at $5040 (inside
| ClkRW) differs (1 on 128K, 3 on 512K) -- wrapped in an
| `.if ROM_TARGET == MAC_128K` block.
|
| References: Inside Macintosh Vol III, Ch 2 (real-time clock).

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
