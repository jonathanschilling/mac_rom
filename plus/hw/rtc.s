| Clock chip (RTC) access -- ClkRW, _ReadXPRam, _WriteXPRam
|
| Apple source: Clock.a (MacSEROM.lst module CLOCK). The real-time clock is
| a serial device on VIA port B (data, clock and enable lines; vRTCData,
| vRTCClk, vRTCEnb): ClkRW reads or writes one clock register; ReadXPRam
| and WriteXPRam ($A051/$A052) access the 256 bytes of extended parameter
| RAM of the Mac Plus clock chip. The bit-banging primitives themselves
| (ClkNoMem, WriteRTCByte, ReadRTCByte) are in boot/vectors.s, where the
| startup code needs them before memory is usable.
|
| References: Inside Macintosh Vol III, Ch 2 (real-time clock);
| Inside Macintosh Vol IV, Ch 8 (extended parameter RAM).

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

