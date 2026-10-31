| Clock chip (RTC) access -- ClkRW, _ReadXPRam, _WriteXPRam, ClkNoMem
|
| Apple source: Clock.a (MacSEROM.lst module CLOCK). The real-time clock is
| a serial device on VIA port B (data, clock and enable lines): CLKRW
| reads or writes one clock register, READXPRAM and WRITEXPRAM ($A051,
| $A052) access the 256 bytes of extended parameter RAM, CLKNOMEM ($A053)
| is the bit-level transfer that works without RAM (the Mac Plus has it in
| its startup code).
|
| References: Inside Macintosh Vol III, Ch 2 (real-time clock);
| Inside Macintosh Vol IV, Ch 8 (extended parameter RAM).

| Called by: READPRAM_LOOP, INITUTIL, INITUTIL_LOOP_3, INITUTIL_LOOP_5, WPON (and 3 more)
CLOCK:                                          | Apple source module (MacSEROM.lst)
CLKRW:
    MOVE.W      SR,-(A7)                        | save status register
    MOVEM.L     D1/D3-D6/A0-A1/A5-A6,-(A7)      | save regs
    LEA.L       CLKRW_EXIT(PC),A5               | A5 = return address
    MOVEA.L     (0x54C).W,A0                    | RTC driver vector
    JMP         (A0)                            | dispatch to RTC driver
| ----------------------------------------------------------
|
| CLKRW_EXIT
|
| Called during boot.
CLKRW_EXIT:
    MOVEM.L     (A7)+,D1/D3-D6/A0-A1/A5-A6      | restore regs
    MOVE.W      (A7)+,SR                        | restore status register
    RTS                                         | return from Clock
| ----------------------------------------------------------
|
| CLKRW_CONT
|
| Called during boot.
CLKRW_CONT:
    MOVEA.L     A0,A1                           | A1 = buffer ptr
    MOVEQ.L     #0x2,D3                         | 3 bits of offset to extract
    MOVE.W      D0,D4                           | D4 = offset (low word)
    SWAP.W      D0                              | D0 = length (high word)
    MOVE.W      D0,D5                           | D5 = byte count
    SUBQ.W      #0x1,D5                         | adjust for DBF
    RTS                                         | return from CLKRW_CONT
READXPRAM:
    MOVEM.L     D1-D5/A1,-(A7)                  | save regs
    BSR.B       CLKRW_CONT                      | parse D0 into offset/length
    MOVEQ.L     #0x17,D0                        | $17: XPRAM read command base
    BRA.B       WRITEXPRAM_CONT                 | -> build RTC command
WRITEXPRAM:
    MOVEM.L     D1-D5/A1,-(A7)                  | save regs
    BSR.B       CLKRW_CONT                      | parse D0 into offset/length
    JSR         WPOFF(PC)                       | disable write protect
    MOVEQ.L     #0x7,D0                         | $07: XPRAM write command base
WRITEXPRAM_CONT:
    BTST        #0x6,(HWCfgFlags)               | extended PRAM available?
    BEQ.B       WRITEXPRAM_ERR                  | no, error ->
WRITEXPRAM_LOOP:
    LSL.B       #0x1,D4                         | shift offset bit into X
    ROXL.W      #0x1,D0                         | rotate into command word
    DBF.W       D3,WRITEXPRAM_LOOP              | encode 3 offset bits
    LSL.W       #0x1,D0                         | shift command left
    MOVEQ.L     #0x6,D3                         | 7 more offset bits
WRITEXPRAM_LOOP_2:
    LSL.B       #0x1,D4                         | shift offset bit into X
    ROXL.W      #0x1,D0                         | rotate into command word
    DBF.W       D3,WRITEXPRAM_LOOP_2            | encode remaining offset bits
WRITEXPRAM_LOOP_3:
    MOVE.W      D0,D1                           | D1 = RTC command for this byte
    ROR.W       #0x8,D1                         | swap command bytes for RTC
    MOVE.B      (A1),D2                         | D2 = data to write (or dummy)
    BSR.B       CLKRW                           | read/write one XPRAM byte
    MOVE.B      D2,(A1)+                        | store read byte, advance ptr
    ORI.B       #0x80,D0                        | advance to next XPRAM register
    ADDQ.W      #0x4,D0                         | bump register address
    ANDI.W      #0xBFFF,D0                      | clear bit 14
    ORI.W       #0x3800,D0                      | set extended PRAM bits
    DBF.W       D5,WRITEXPRAM_LOOP_3            | loop for all bytes
    JSR         WPON(PC)                        | re-enable write protect
    MOVEQ.L     #0x0,D0                         | result = noErr
WRITEXPRAM_EXIT:
    MOVEM.L     (A7)+,D1-D5/A1                  | restore regs
    RTS                                         | return from ReadXPRam/WriteXPRam
WRITEXPRAM_ERR:
    MOVEQ.L     #-0x57,D0                       | prWrErr (-87): no XPRAM
    BRA.B       WRITEXPRAM_EXIT                 | -> exit
CLKNOMEM:
    ORI.W       #0x300,SR                       | IPL=3: mask VIA interrupts
    MOVEA.L     #0xEFE1FE,A1                    | A1 = VIA PortB register
    MOVE.B      (A1),D3                         | D3 = current PortB state
    MOVEQ.L     #0x1,D4                         | D4 = clock bit (PB1)
    ANDI.B      #0xF9,D3                        | clear PB1 (clock) and PB2 (CS)
    MOVE.W      D1,D6                           | save command
    ANDI.W      #0x78,D6                        | extract register address bits
    CMPI.W      #0x38,D6                        | extended command? ($38 = XPRAM)
    BNE.B       RTC_SINGLE_CMD                  | no, normal command ->
    MOVE.W      D1,D6                           | save full command for later
    LEA.L       RTC_EXT_CMD_SENT(PC),A6         | return: process 2nd byte
    JMP         WriteRTCByte(PC)                | send first command byte
RTC_EXT_CMD_SENT:
    LSR.W       #0x8,D1                         | D1 = second command byte
    TST.B       D6                              | test read/write bit
    BRA.B       RTC_READ_OR_WRITE               | -> check direction
RTC_SINGLE_CMD:
    TST.B       D1                              | test read/write bit
RTC_READ_OR_WRITE:
    BMI.B       RTC_READ_PATH                   | read operation ->
    LEA.L       RTC_SEND_DATA_BYTE(PC),A6       | return: send data byte
    JMP         WriteRTCByte(PC)                | send command byte
RTC_SEND_DATA_BYTE:
    MOVE.W      D2,D1                           | D1 = data byte to write
    LEA.L       RTC_WRITE_DONE(PC),A6           | return: disable chip
    JMP         WriteRTCByte(PC)                | send data byte
RTC_WRITE_DONE:
    BRA.B       RTC_DISABLE_CHIP                | -> deselect RTC
RTC_READ_PATH:
    LEA.L       RTC_READ_DATA_BYTE(PC),A6       | return: read data byte
    JMP         WriteRTCByte(PC)                | send command byte
RTC_READ_DATA_BYTE:
    LEA.L       RTC_DISABLE_CHIP(PC),A6         | return: disable chip
    JMP         ReadRTCByte(PC)                 | read data byte -> D2
| RTC_DISABLE_CHIP - RTC transaction complete; disable chip and return
| Called during boot.
RTC_DISABLE_CHIP:
    BSET        #0x2,(A1)                       | Set PB2 high: disable RTC chip
    JMP         (A5)                            | return to RTC caller via A5
| Write 8 bits to RTC via VIA PortB bit-bang serial.
| Shifts D1 MSB-first out through PB0 (data), clocking PB1 (clock) for each bit.
| return address in A6
| Called during boot.
WriteRTCByte:
    MOVEQ.L     #0x7,D5                         | 8 bits to send
| WriteRTCByte bit-shift loop
WRITE_RTC_BIT_LOOP:
    ROR.B       #0x1,D3                         | save current PB0 in bit 7
    ROXL.B      #0x1,D1                         | shift data bit into X
    ROXL.B      #0x1,D3                         | shift X into PB0 (data out)
    MOVE.B      D3,(A1)                         | set data bit, clock low
    BSET        D4,(A1)                         | clock high (PB1): latch data
    DBF.W       D5,WRITE_RTC_BIT_LOOP           | loop 8 bits
    JMP         (A6)                            | return via A6
| Read 8 bits from RTC via VIA PortB bit-bang serial.
| Switches PB0 to input, clocks PB1, reads data from PB0 into D2.
| return address in A6
| Called during boot.
ReadRTCByte:
    MOVEQ.L     #0x7,D5                         | 8 bits to read
    BCLR        #0x0,0x400(A1)                  | set PB0 as input (DDRB)
    MOVE.B      D3,D4                           | D4 = PortB with clock high
    BSET        #0x1,D4                         | set PB1 (clock bit)
| ReadRTCByte bit-clock loop
READ_RTC_BIT_LOOP:
    MOVE.B      D3,(A1)                         | clock low
    MOVE.B      D4,(A1)                         | clock high: data valid
    MOVE.B      (A1),D1                         | read PortB
    LSR.B       #0x1,D1                         | shift PB0 data into X
    ROXL.B      #0x1,D2                         | rotate X into D2
    DBF.W       D5,READ_RTC_BIT_LOOP            | loop 8 bits
    BSET        #0x0,0x400(A1)                  | restore PB0 as output (DDRB)
    JMP         (A6)                            | return via A6
