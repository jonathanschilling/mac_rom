| The serial drivers .AIn, .AOut, .BIn, .BOut of the 64K ROM (the "ROM
| Serial Driver" of Inside Macintosh II, driver version 0) @ ROM $2552
|
| Built-in drivers, not a resource: InitIOMgr installs the four DRVR headers
| below from DRVR_INSTALL_TABLE (refNums -6 .. -9) but does not open them
| (only .Sound and .Sony are opened at startup). One input and one
| output driver for each channel of the Zilog Z8530 SCC: channel A drives
| the modem port, channel B the printer port. The input and output driver
| of a port share one block of variables (SERDVars), which the output
| driver's Open allocates, so the output driver must be opened first.
|
|   driver  refNum  port     header       SERDVars pointer  input DCE
|   .AIn     -6     modem    Driver_AIn   SerialVars+0      SerialVars+4
|   .AOut    -7     modem    Driver_AOut  SerialVars+0
|   .BIn     -8     printer  Driver_BIn   SerialVars+8      SerialVars+12
|   .BOut    -9     printer  Driver_BOut  SerialVars+8
|
| (SerialVars = $2D0, 16 bytes; lowmem.inc calls the four longs SerialVars_a,
| SerialVars_a_dce, ABusVars and ABusVars_dce: AppleTalk keeps its own
| pointer in the port B slot.)
|
| This is the ancestor of the 'SERD' 0 drivers of the Plus and SE ROMs
| (src/plus/resources/res_serd.s); where the code corresponds, the labels
| and the SERDVars names (SV_*) are the Plus driver's. Calls:
|   Status   2 SerGetBuf (characters in the input buffer, long),
|            8 SerStatus (the 6-byte SerStaRec; cumErrs is cleared)
|   Control  1 KillIO (clear rdPend/wrPend, empty the input buffer),
|            8 SerReset (new SerConfig), 9 SerSetBuf (input buffer;
|            length 0 = the built-in 64 bytes), 10 SerHShake (fXOn, fCTS,
|            xOn, xOff, errs, evts, fInX), 11 SerClrBrk, 12 SerSetBrk;
|            other codes: controlErr
| (Inside Macintosh II, "The Serial Drivers"; the other control calls came
| with the RAM serial driver and the 128K ROM.)
|
| What the 128K ROM driver changed (Inside Macintosh IV, "The Serial
| Driver", and the Plus code):
| - Open checks nothing here: no SPConfig/PortAUse test (portNotCf,
|   portInUse), and the vectors it replaces are not saved; Close installs
|   a dummy handler (E_ABIn_Close, an RTS) in the four interrupt slots.
| - DTR is never asserted (the WR5 values have no DTR bit), there is no
|   driver version byte, no CTS-clock guard, no wait for the transmitter
|   before Close (or a break), no data-bits mask and no parity-error
|   replacement.
| - Control and Status complete through IODone even for immediate calls,
|   and neither checks that the port is open (SERDVars pointer 0: they
|   work on low memory).
| - The lists write WR0 = $40 (reset Rx CRC checker) where the Plus writes
|   $10 (reset ext/status interrupts); Open and Close begin with a channel
|   reset (WR9 = $80 / $40).
| Bugs that Inside Macintosh II describes as limits of the ROM driver:
| - SERD_SPINT combines errs and the errors with EOR instead of AND, so
|   practically every receive error aborts the read ("the ROM Serial Driver
|   always terminates input requests when an error occurs").
| - SERD_RXBUFFER_STORED compares the number of characters in the buffer,
|   not the free space, with SV_HIMARK: XOff goes out when the buffer is
|   nearly empty ("doesn't support XOn/XOff input flow control").
| - E_AOut_Close / E_BOut_Close clear the first long of the freed SERDVars
|   block instead of the SerialVars pointer, which stays stale.
|
| SerConfig word (Inside Macintosh II, "SerReset"): bits 0-9 baud-rate time
| constant (baud9600 = 10), bits 10-11 data bits (0 = 5, 1 = 7, 2 = 6,
| 3 = 8), bits 12-13 parity (1 odd, 3 even, else none), bits 14-15 stop
| bits (1 = 1, 2 = 1.5, 3 = 2). The bit layouts match the SCC's WR3/WR4/WR5
| fields, so SERD_CONFIG_TBL can cut them out with a rotate and a mask.
|
| Entry conventions: Open/Prime/Control/Status/Close with A0 = parameter
| block, A1 = DCE, D0 = 0. The level-2 SCC dispatcher calls the interrupt
| handlers with A0 = the channel's control register (read), A1 = the same
| register (write); the ext/status handler gets D0 = RR0 and D1 = the
| changed RR0 bits that are enabled in WR15.
|
| SERDVars -- the variables of one port, SV_SIZE bytes in a locked block in
| the system heap (handle in the output DCE's dCtlStorage, pointer in
| SerialVars+0 / +8; A2 in all routines). The SV_* names are this file's;
| +$10..+$16 hold the SerShk record (7 bytes) and +$18..+$1D the SerStaRec
| that SerStatus returns (field names as in Inside Macintosh).
.set SV_OUTDCE, 0x00                            | output driver's DCE (.AOut/.BOut) [long]
.set SV_CHANOFS, 0x04                           | channel offset from SCCRd/SCCWr: aCtl (2) or bCtl (0) [word]
.set SV_BUFPTR, 0x06                            | input buffer [pointer]
.set SV_BUFSIZE, 0x0A                           | input buffer size [word]
.set SV_LOWMARK, 0x0C                           | XOn when at most this many chars are left (size/4) [word]
.set SV_HIMARK, 0x0E                            | XOff threshold (size/4, see the bug above) [word]
.set SV_FXON, 0x10                              | fXOn: XOn/XOff output flow control (stop on XOff)
.set SV_FCTS, 0x11                              | fCTS: CTS output flow control ($FF after Open)
.set SV_XON, 0x12                               | xOn: XOn character
.set SV_XOFF, 0x13                              | xOff: XOff character
.set SV_ERRS, 0x14                              | errs: errors that abort a read; $FF after Open
.set SV_EVTS, 0x15                              | evts: RR0 changes that post a driver event ($20 CTS, $80 break)
.set SV_FINX, 0x16                              | fInX: XOn/XOff input flow control
.set SV_FLOWCHAR, 0x17                          | XOn/XOff character waiting to be sent (0 = none)
.set SV_CUMERRS, 0x18                           | cumErrs: 1 sw overrun, $10 parity, $20 hw overrun, $40 framing
.set SV_XOFFSENT, 0x19                          | xOffSent: bit 7 XOff sent
.set SV_RDPEND, 0x1A                            | rdPend: a read waits for characters
.set SV_WRPEND, 0x1B                            | wrPend: a write is in progress
.set SV_CTSHOLD, 0x1C                           | ctsHold: $FF while the CTS bit of RR0 is set (handshake input negated)
.set SV_XOFFHOLD, 0x1D                          | xOffHold: XOff received
| shadow registers, in the order SERD_WRITEREGS uses them (SV_WR9RESET on):
.set SV_WR9RESET, 0x20                          | WR9 command that resets this channel: $80 (A) / $40 (B)
.set SV_WR4, 0x21                               | WR4: x16 clock, stop bits, parity
.set SV_WR1INIT, 0x22                           | WR1 while the channel is programmed: interrupts off
.set SV_WR3OFF, 0x23                            | WR3: bits per character, receiver off
.set SV_WR5OFF, 0x24                            | WR5: bits per character, RTS, transmitter off
.set SV_WR12, 0x25                              | WR12: baud-rate time constant, low byte
.set SV_WR13, 0x26                              | WR13: time constant, high byte
.set SV_WR3ON, 0x27                             | WR3: receiver on
.set SV_WR5ON, 0x28                             | WR5: transmitter on, RTS (no DTR)
.set SV_WR1, 0x29                               | WR1: interrupt enables, $F7 (A, with W/REQ) / $17 (B)
.set SV_CONFIG, 0x2A                            | SerConfig the channel runs with [word]
.set SV_INIDX, 0x2C                             | input buffer: where the next character goes [word]
.set SV_OUTIDX, 0x2E                            | input buffer: next character to read [word]
.set SV_DEFBUF, 0x30                            | built-in input buffer, 64 bytes
.set SV_SIZE, 0x70                              | size of SERDVars

| ----------------------------------------------------------
| DRVR headers (24 bytes each). drvrFlags $4D00 (input) = dNeedLock +
| dStatEnable + dCtlEnable + dReadEnable; $4E00 (output) = the same with
| dWritEnable. No periodic action, no event mask, no menu. The routine
| offsets are relative to each header.
Driver_AIn:                                     | .AIn header @ $2552
        .short  0x4D00                          | drvrFlags: read, control, status, needs lock
        .short  0x0000                          | drvrDelay
        .short  0x0000                          | drvrEMask
        .short  0x0000                          | drvrMenu
        .short  E_AIn_Open-Driver_AIn           | drvrOpen
        .short  E_AIn_Prime-Driver_AIn          | drvrPrime: read
        .short  E_AInOut_Control-Driver_AIn     | drvrCtl
        .short  E_AInOut_Status-Driver_AIn      | drvrStatus
        .short  E_ABIn_Close-Driver_AIn         | drvrClose
        .byte   0x04                            | drvrName length
        .ascii  ".AIn"                          | drvrName: modem port input
        .byte   0x20                            | pad to a word boundary

| .AOut -- modem port output driver
Driver_AOut:                                    | .AOut header @ $256A
        .short  0x4E00                          | drvrFlags: write, control, status, needs lock
        .short  0x0000                          | drvrDelay
        .short  0x0000                          | drvrEMask
        .short  0x0000                          | drvrMenu
        .short  E_AOut_Open-Driver_AOut         | drvrOpen
        .short  E_AOut_Prime-Driver_AOut        | drvrPrime: write
        .short  E_AInOut_Control-Driver_AOut    | drvrCtl
        .short  E_AInOut_Status-Driver_AOut     | drvrStatus
        .short  E_AOut_Close-Driver_AOut        | drvrClose
        .byte   0x05                            | drvrName length
        .ascii  ".AOut"                         | drvrName: modem port output

| .BIn -- printer port input driver
Driver_BIn:                                     | .BIn header @ $2582
        .short  0x4D00                          | drvrFlags: read, control, status, needs lock
        .short  0x0000                          | drvrDelay
        .short  0x0000                          | drvrEMask
        .short  0x0000                          | drvrMenu
        .short  E_BIn_Open-Driver_BIn           | drvrOpen
        .short  E_BIn_Prime-Driver_BIn          | drvrPrime: read
        .short  E_BInOut_Control-Driver_BIn     | drvrCtl
        .short  E_BInOut_Status-Driver_BIn      | drvrStatus
        .short  E_ABIn_Close-Driver_BIn         | drvrClose
        .byte   0x04                            | drvrName length
        .ascii  ".BIn"                          | drvrName: printer port input
        .byte   0x20                            | pad to a word boundary

| .BOut -- printer port output driver
Driver_BOut:                                    | .BOut header @ $259A
        .short  0x4E00                          | drvrFlags: write, control, status, needs lock
        .short  0x0000                          | drvrDelay
        .short  0x0000                          | drvrEMask
        .short  0x0000                          | drvrMenu
        .short  E_BOut_Open-Driver_BOut         | drvrOpen
        .short  E_BOut_Prime-Driver_BOut        | drvrPrime: write
        .short  E_BInOut_Control-Driver_BOut    | drvrCtl
        .short  E_BInOut_Status-Driver_BOut     | drvrStatus
        .short  E_BOut_Close-Driver_BOut        | drvrClose
        .byte   0x05                            | drvrName length
        .ascii  ".BOut"                         | drvrName: printer port output

| ----------------------------------------------------------
| E_AIn_Open / E_BIn_Open -- Open of an input driver: just note the DCE
| (A1) in SerialVars+4 / +12 for the receive interrupt code (D0 = 0 from
| the Device Manager). The output driver's Open sets the port up.
E_AIn_Open:
        MOVE.L  A1,(SerialVars+4).w             | SerialVars+4 = .AIn DCE
        RTS                                     | return noErr

| ----------------------------------------------------------
| E_BIn_Open -- Open of .BIn (see E_AIn_Open).
E_BIn_Open:
        MOVE.L  A1,(SerialVars+12).w            | SerialVars+12 = .BIn DCE
        RTS                                     | return noErr

| ----------------------------------------------------------
| E_AOut_Open / E_BOut_Open -- Open of an output driver: load the channel's
| constants and call SERD_OUTOPEN:
|   D0 = offset of the channel's slot in ExtStsDT (8 = A, 0 = B; twice
|   that in Lvl2DT), A2 -> its SerialVars pointer, A3-A6 = Tx, ext/status,
|   Rx and special-condition handlers, D1 = channel offset (aCtl/bCtl),
|   D2 = WR1 interrupt enables ($F7: port A also sets W/REQ on received
|   characters, which the .Sony driver polls during disk transfers; $17
|   port B), D3 = WR9 channel reset command ($80/$40), D4 = SerConfig from
|   PRAM (SPPortA/SPPortB). Port A also installs the poll procedure.
E_AOut_Open:
        MOVEQ.L #0x8,D0                         | channel A: ExtStsDT+8, Lvl2DT+16
        LEA.L   (SerialVars).w,A2               | A2 = SerialVars+0: port A pointer
        LEA     SERD_TXINT_A(PC),A3             | transmit buffer empty handler
        LEA     SERD_EXTINT_A(PC),A4            | ext/status change handler
        LEA     SERD_RXINT_A(PC),A5             | receive character available handler
        LEA     SERD_SPINT_A(PC),A6             | special receive condition handler
        MOVEQ.L #aCtl,D1                        | channel offset: channel A control
        MOVEQ.L #-0x9,D2                        | WR1 = $F7: Rx/Tx/ext ints, W/REQ on receive
        MOVEQ.L #-0x80,D3                       | WR9 = $80: reset channel A
        MOVE    (SPPortA).w,D4                  | D4 = SerConfig of port A (PRAM)
        BSR.B   SERD_OUTOPEN                    | install handlers, SERDVars, program the SCC
        PEA.L   SERD_POLLPROC(PC)               | poll procedure for port A ...
        MOVE.L  (SP)+,(PollProc).w              | ... into PollProc
        RTS                                     | return noErr (D0 from SERD_SETCONFIG)

| ----------------------------------------------------------
| E_BOut_Open -- Open of .BOut (see E_AOut_Open); no poll procedure.
E_BOut_Open:
        MOVEQ.L #0x0,D0                         | channel B: ExtStsDT+0, Lvl2DT+0
        LEA.L   (SerialVars+8).w,A2             | A2 = SerialVars+8: port B pointer
        LEA     SERD_TXINT_B(PC),A3             | transmit buffer empty handler
        LEA     SERD_EXTINT_B(PC),A4            | ext/status change handler
        LEA     SERD_RXINT_B(PC),A5             | receive character available handler
        LEA     SERD_SPINT_B(PC),A6             | special receive condition handler
        MOVEQ.L #bCtl,D1                        | channel offset: channel B control
        MOVEQ.L #0x17,D2                        | WR1 = $17: Rx/Tx/ext ints
        MOVEQ.L #0x40,D3                        | WR9 = $40: reset channel B
        MOVE    (SPPortB).w,D4                  | D4 = SerConfig of port B (PRAM)
| SERD_OUTOPEN -- install the handlers (the old vectors are not saved),
| allocate SERDVars (cleared, locked; no check of the result), fill them in
| (fCTS and errs $FF) and set the channel up (SERD_SETCONFIG).
SERD_OUTOPEN:
        LEA.L   (ExtStsDT).w,A0                 | A0 = ExtStsDT
        MOVE.L  A4,0(A0,D0.W)                   | channel slot (vComIntA/B) = ext/status handler
        LEA.L   (Lvl2DT).w,A0                   | A0 = Lvl2DT
        ADD     D0,D0                           | 16 = A, 0 = B
        MOVE.L  A3,0(A0,D0.W)                   | vTxA/vTxB = Tx handler
        MOVEM.L A5-A6,8(A0,D0.W)                | vRx, vSC = Rx and special-condition handlers
        MOVEQ.L #0x70,D0                        | SV_SIZE
        _NewHandleSysClear                      | A0 = handle to cleared SERDVars
        BSET    #0x7,(A0)                       | lock it (master pointer lock bit)
        MOVE.L  A0,dCtlStorage(A1)              | dCtlStorage = SERDVars handle
        MOVE.L  (A0),(A2)                       | SerialVars+0/+8 = SERDVars pointer
        MOVE.L  (A0),A2                         | A2 = SERDVars
        MOVE.L  A2,A3                           | A3 = SERDVars
        MOVE.L  A1,(A3)+                        | SV_OUTDCE = this (output) DCE
        MOVE    D1,(A3)+                        | SV_CHANOFS = aCtl/bCtl
        BSR.W   SERD_DEFAULTBUF                 | input buffer = built-in 64 bytes
        ST      SV_FCTS(A2)                     | fCTS = $FF: CTS flow control on
        ST      SV_ERRS(A2)                     | errs = $FF: every receive error aborts a read
        MOVE.B  D3,SV_WR9RESET(A2)              | WR9 channel reset command
        MOVE.B  D2,SV_WR1(A2)                   | WR1 interrupt enables
| SERD_SETCONFIG -- set the channel up from the SerConfig word in D4 (Open,
| csCode 8 SerReset): SV_CONFIG, shadow registers from SERD_CONFIG_TBL,
| then program the SCC (SERD_INITSCC). No check of the word. Returns
| D0 = noErr. Changes D0-D3, A3, A4.
SERD_SETCONFIG:
        MOVE    D4,SV_CONFIG(A2)                | SV_CONFIG = SerConfig
        LEA.L   SV_WR4(A2),A3                   | A3 = first shadow register built
        LEA     SERD_CONFIG_TBL(PC),A4          | A4 = rotate/AND/OR table
        MOVEQ.L #0x7,D0                         | 8 shadow registers (SV_WR4..SV_WR5ON)
SERD_SETCONFIG_LOOP:
        MOVE.B  (A4)+,D1                        | rotate count
        MOVE    D4,D3                           | D3 = SerConfig
        ROL     D1,D3                           | move the field to the register's bit position
        AND.B   (A4)+,D3                        | keep the field
        OR.B    (A4)+,D3                        | add the register's fixed bits
        MOVE.B  D3,(A3)+                        | store the shadow register
        DBRA    D0,SERD_SETCONFIG_LOOP          | next register
        MOVEQ.L #0x64,D1                        | $64: W/REQ function bits, parity special
        AND.B   (A3),D1                         | of SV_WR1
        MOVE.B  D1,SV_WR1INIT(A2)               | WR1 while programming: no interrupts
        BSR.B   SERD_INITSCC                    | program the channel
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from Open / SerReset
| SERD_CONFIG_TBL -- how SERD_SETCONFIG builds the shadow registers from
| the SerConfig word: per register a rotate count (ROL.W), an AND mask
| and an OR value (the Plus table differs only in DTR for SV_WR5ON).
SERD_CONFIG_TBL:
  .byte 0x04, 0x0F, 0x40                        | SV_WR4: stop bits + parity (bits 12-15), x16 clock
  .byte 0x00, 0x00, 0x00                        | SV_WR1INIT: 0 (replaced from SV_WR1 afterwards)
  .byte 0x0C, 0xC0, 0x00                        | SV_WR3OFF: Rx bits per character (bits 10-11), receiver off
  .byte 0x0B, 0x60, 0x02                        | SV_WR5OFF: Tx bits per character, RTS, transmitter off
  .byte 0x00, 0xFF, 0x00                        | SV_WR12: time constant bits 0-7
  .byte 0x08, 0x03, 0x00                        | SV_WR13: time constant bits 8-9
  .byte 0x0C, 0xC0, 0x01                        | SV_WR3ON: Rx bits per character, receiver on
  .byte 0x0B, 0x60, 0x0A                        | SV_WR5ON: Tx bits per character, transmitter on, RTS
| SERD_INIT_REGS -- register list that programs the channel (SERD_INITSCC).
| A pair whose second byte is $FF takes the value from the next shadow
| register (SV_WR9RESET on) and its first byte is the register number; in
| any other pair the second byte is the register number and the first the
| value (see SERD_WRITEREGS).
SERD_INIT_REGS:
  .byte 0x09, 0xFF                              | WR9 = SV_WR9RESET: reset the channel
  .byte 0x04, 0xFF                              | WR4 = SV_WR4: x16 clock, stop bits, parity
  .byte 0x01, 0xFF                              | WR1 = SV_WR1INIT: interrupts off
  .byte 0x00, 0x02                              | WR2 = $00: interrupt vector
  .byte 0x03, 0xFF                              | WR3 = SV_WR3OFF: receiver off
  .byte 0x05, 0xFF                              | WR5 = SV_WR5OFF: transmitter off
  .byte 0x02, 0x09                              | WR9 = $02: master interrupt enable off, no vector
  .byte 0x50, 0x0B                              | WR11 = $50: Rx and Tx clock = baud-rate generator
  .byte 0x0C, 0xFF                              | WR12 = SV_WR12: time constant low
  .byte 0x0D, 0xFF                              | WR13 = SV_WR13: time constant high
  .byte 0x03, 0xFF                              | WR3 = SV_WR3ON: receiver on
  .byte 0x05, 0xFF                              | WR5 = SV_WR5ON: transmitter on, RTS
  .byte 0x01, 0x0E                              | WR14 = $01: baud-rate generator on (clock from RTxC)
  .byte 0xA8, 0x0F                              | WR15 = $A8: break, CTS and DCD (mouse) interrupts
  .byte 0x40, 0x00                              | WR0 = $40: reset Rx CRC checker (Plus: $10)
  .byte 0x40, 0x00                              | WR0 = $40: again
  .byte 0x01, 0xFF                              | WR1 = SV_WR1: interrupts on
  .byte 0x0A, 0x09                              | WR9 = $0A: master interrupt enable, no vector

| ----------------------------------------------------------
| SERD_INITSCC -- program the channel with SERD_INIT_REGS (18 pairs).
| SERD_WRITEREGS -- write the register list at A3, D1 bytes long, to this
| channel with interrupts masked; $FF pairs take the next shadow register
| from SV_WR9RESET on. Then read RR0 and set ctsHold from its CTS bit.
| A2 = SERDVars. Changes D0-D2, A3. Ends with RTE: the SR it pushed and
| the return address are exactly an exception frame.
SERD_INITSCC:
        LEA     SERD_INIT_REGS(PC),A3           | A3 = register list
        MOVEQ.L #0x24,D1                        | 36 bytes = 18 pairs
SERD_WRITEREGS:
        MOVE    SR,-(SP)                        | save the interrupt level
        MOVEM.L A0-A2,-(SP)                     | save A0-A2
        MOVE    SV_CHANOFS(A2),D2               | D2 = channel offset
        MOVEM.L (SCCRd).w,A0-A1                 | A0 = SCCRd, A1 = SCCWr (channel B control)
        ADDA.W  D2,A0                           | A0 = channel control (read)
        ADDA.W  D2,A1                           | A1 = channel control (write)
        ORI     #0x300,SR                       | mask interrupts (IPL 3)
        MOVE.B  (A0),D2                         | dummy read: register pointer -> 0
        LEA.L   SV_WR9RESET(A2),A2              | A2 = first shadow register
SERD_WRITEREGS_LOOP:
        MOVE    (A3)+,D0                        | D0 = next pair (first byte high)
        TST.B   D0                              | second byte $FF?
        BPL.B   SERD_WRITEREGS_PAIR             | no: (value, register) ->
        MOVE.B  (A2)+,D0                        | yes: value = next shadow register
        ROR     #0x8,D0                         | low byte = register, high byte = value
SERD_WRITEREGS_PAIR:
        MOVE.B  D0,(A1)                         | select the register (WR0 pointer)
        ROR     #0x8,D0                         | value -> low byte
        MOVE.L  (SP),(SP)                       | delay between SCC accesses
        MOVE.B  D0,(A1)                         | write the register
        SUBQ.W  #0x2,D1                         | count the pair
        BGT.B   SERD_WRITEREGS_LOOP             | more -> next pair
        MOVE.B  (A0),D2                         | D2 = RR0
        LSL.B   #0x2,D2                         | RR0 bit 5 (CTS) -> N
        MOVEM.L (SP)+,A0-A2                     | restore A0-A2
        SMI     SV_CTSHOLD(A2)                  | ctsHold = $FF if CTS bit set
        RTE                                     | pop the saved SR and return

| ----------------------------------------------------------
| SERD_CLOSE_REGS -- register list that shuts the channel down (output
| Close): channel reset, then only the DCD interrupt for the mouse.
SERD_CLOSE_REGS:
  .byte 0x09, 0xFF                              | WR9 = SV_WR9RESET: reset the channel
  .byte 0x08, 0x0F                              | WR15 = $08: only the DCD (mouse) interrupt
  .byte 0x40, 0x00                              | WR0 = $40: reset Rx CRC checker
  .byte 0x40, 0x00                              | WR0 = $40: again
  .byte 0x01, 0x01                              | WR1 = $01: ext/status interrupts only

| ----------------------------------------------------------
| E_AOut_Close / E_BOut_Close -- Close of an output driver: remove the poll
| procedure (port A), then SERD_OUTCLOSE with A4 = the channel's Lvl2DT Tx
| slot, A5 = its ExtStsDT slot, A2 = SERDVars.
E_AOut_Close:
        CLR.L   (PollProc).w                    | no poll procedure any more
        LEA.L   (Lvl2DT_4).w,A4                 | A4 = Lvl2DT+16: channel A Tx slot
        LEA.L   (ExtStsDT_A).w,A5               | A5 = ExtStsDT+8: channel A slot
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars
        BRA.B   SERD_OUTCLOSE                   | -> common output Close

| ----------------------------------------------------------
| E_BOut_Close -- Close of .BOut (see E_AOut_Close).
E_BOut_Close:
        LEA.L   (Lvl2DT).w,A4                   | A4 = Lvl2DT+0: channel B Tx slot
        LEA.L   (ExtStsDT).w,A5                 | A5 = ExtStsDT+0: channel B slot
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars
| SERD_OUTCLOSE -- common output Close: reset the channel (without waiting
| for the transmitter), point its four interrupt slots at the dummy
| handler E_ABIn_Close, free SERDVars. Bug: CLR.L (A2) clears the first
| long of the freed block; the SerialVars pointer stays set.
SERD_OUTCLOSE:
        LEA     SERD_CLOSE_REGS(PC),A3          | A3 = shut-down register list
        MOVEQ.L #0xA,D1                         | 10 bytes = 5 pairs
        BSR.B   SERD_WRITEREGS                  | write it
        LEA     E_ABIn_Close(PC),A3             | A3 = dummy handler (RTS)
        MOVE.L  A3,(A4)                         | Tx slot
        MOVE.L  A3,(A5)                         | ExtStsDT slot
        ADDQ.L  #0x8,A4                         | skip the ext/status slot
        MOVE.L  A3,(A4)+                        | Rx slot
        MOVE.L  A3,(A4)                         | special-condition slot
        MOVE.L  dCtlStorage(A1),A0              | A0 = SERDVars handle
        _DisposeHandle                          | free SERDVars
        CLR.L   dCtlStorage(A1)                 | no storage
        CLR.L   (A2)                            | (meant: the SerialVars pointer)
| E_ABIn_Close -- Close of .AIn/.BIn (nothing to do, D0 = 0 from the Device
| Manager), the end of the output Close, and the dummy interrupt handler
| that Close leaves in the SCC vectors.
E_ABIn_Close:
        RTS                                     | return

| ----------------------------------------------------------
| E_AInOut_Status / E_BInOut_Status -- Status of both drivers of port A / B.
| SERD_STATUS: csCode 2 SerGetBuf, csCode 8 SerStatus, else statusErr;
| always completes through IODone.
E_AInOut_Status:
        MOVEA.L (SerialVars).w,A2               | A2 = port A SERDVars
        BRA.B   SERD_STATUS                     | -> common Status

| ----------------------------------------------------------
| E_BInOut_Status -- Status of port B (see E_AInOut_Status).
E_BInOut_Status:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars
SERD_STATUS:
        LEA.L   csCode(A0),A0                   | A0 -> csCode
        MOVEQ.L #statusErr,D0                   | default result: statusErr
        MOVEQ.L #0x2,D1                         | 2 ...
        SUB     (A0)+,D1                        | ... - csCode; A0 -> csParam
        BNE.B   SERD_STATUS_CS8                 | not 2 (SerGetBuf) ->
        BSR.W   SERD_GETBUF                     | D1/D2 = in/out index, D3 = size
        BSR.W   SERD_BUFCOUNT                   | D0 = characters in the input buffer
        CLR     (A0)+                           | csParam: count, high word 0
        MOVE    D0,(A0)                         | low word
        BRA.B   SERD_STATUS_NOERR               | -> noErr
| SERD_STATUS_CS8 -- csCode 8 SerStatus: copy the SerStaRec (cumErrs,
| xOffSent, rdPend, wrPend, ctsHold, xOffHold) and clear cumErrs.
SERD_STATUS_CS8:
        ADDQ.W  #0x6,D1                         | 2 - csCode + 6 = 0: csCode 8?
        BNE.B   SERD_IODONE                     | no -> statusErr
        MOVE    SV_CUMERRS(A2),(A0)+            | cumErrs, xOffSent
        CLR.B   SV_CUMERRS(A2)                  | errors are reported once
        MOVE.L  SV_RDPEND(A2),(A0)+             | rdPend, wrPend, ctsHold, xOffHold
SERD_STATUS_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
| SERD_IODONE -- complete the request of the DCE in A1 with result D0:
| jump through JIODone (IODone returns to our caller).
| Called by: SERD_STATUS_CS8, SERD_CTL_EXIT, SERD_ABORTREAD (SERD_STATUS
| falls into it)
SERD_IODONE:
        MOVE.L  (JIODone).w,-(SP)               | push IODone's address
        RTS                                     | jump to IODone

| ----------------------------------------------------------
| E_AInOut_Control / E_BInOut_Control -- Control of both drivers of port
| A / B. SERD_CONTROL tests the csCodes one after the other: 1 KillIO
| (returns directly), 8 SerReset, 9 SerSetBuf, 10 SerHShake, 11 SerClrBrk,
| 12 SerSetBrk; others controlErr. Completes through IODone.
E_AInOut_Control:
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars
        BRA.B   SERD_CONTROL                    | -> common Control

| ----------------------------------------------------------
| E_BInOut_Control -- Control of port B (see E_AInOut_Control).
E_BInOut_Control:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars
SERD_CONTROL:
        LEA.L   csCode(A0),A0                   | A0 -> csCode
        MOVE    (A0)+,D1                        | D1 = csCode, A0 -> csParam
        SUBQ.W  #killCode,D1                    | csCode 1 (KillIO)?
        BNE.B   SERD_CTL_CS8                    | no ->
        CLR     SV_RDPEND(A2)                   | rdPend = wrPend = 0
        CLR.L   SV_INIDX(A2)                    | in = out index: input buffer empty
        RTS                                     | return to KillIO (D0 = 0 from the Device Manager)
| SERD_CTL_CS8 -- csCode 8 SerReset: csParam = SerConfig; a new value is set
| up through SERD_SETCONFIG.
SERD_CTL_CS8:
        SUBQ.W  #0x7,D1                         | csCode 8?
        BNE.B   SERD_CTL_CS9                    | no ->
        MOVE    (A0)+,D4                        | D4 = new SerConfig
        CMP     SV_CONFIG(A2),D4                | the current one?
        BEQ.B   SERD_CTL_NOERR                  | yes -> nothing to do
        BSR.W   SERD_SETCONFIG                  | set it up
| SERD_CTL_NOERR / SERD_CTL_EXIT -- end of Control: result D0 via IODone.
SERD_CTL_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
SERD_CTL_EXIT:
        BRA.B   SERD_IODONE                     | -> IODone
| SERD_CTL_CS9 -- csCode 9 SerSetBuf: csParam = buffer pointer (long),
| csParam+4 = its length (0: the built-in buffer). Empties the buffer.
SERD_CTL_CS9:
        SUBQ.W  #0x1,D1                         | csCode 9?
        BNE.B   SERD_CTL_CS10                   | no ->
        PEA.L   SERD_CTL_NOERR(PC)              | return to the noErr exit
        CLR.L   SV_INIDX(A2)                    | in = out = 0: buffer empty
        MOVE.L  (A0)+,A4                        | A4 = new buffer
        MOVE    (A0),D1                         | D1 = its length
        BNE.B   SERD_SETBUF                     | nonzero -> use it
| SERD_DEFAULTBUF -- input buffer = the built-in 64 bytes at SV_DEFBUF
| (Open, SerSetBuf with length 0).
| SERD_SETBUF -- input buffer = A4, D1 bytes; both flow-control marks =
| length/4. Changes D1, A3, A4.
SERD_DEFAULTBUF:
        LEA.L   SV_DEFBUF(A2),A4                | A4 = built-in buffer
        MOVEQ.L #0x40,D1                        | 64 bytes
SERD_SETBUF:
        LEA.L   SV_BUFPTR(A2),A3                | A3 -> buffer fields
        MOVE.L  A4,(A3)+                        | SV_BUFPTR
        MOVE    D1,(A3)+                        | SV_BUFSIZE
        LSR     #0x2,D1                         | length / 4
        MOVE    D1,(A3)+                        | SV_LOWMARK
        MOVE    D1,(A3)+                        | SV_HIMARK
        RTS                                     | return (SerSetBuf: to SERD_CTL_NOERR)
| SERD_CTL_CS10 -- csCode 10 SerHShake: copy fXOn, fCTS, xOn, xOff, errs,
| evts, fInX (7 bytes).
SERD_CTL_CS10:
        SUBQ.W  #0x1,D1                         | csCode 10?
        BNE.B   SERD_CTL_CS11                   | no ->
        ADDA.W  #0x10,A2                        | A2 -> SV_FXON
        MOVE.L  (A0)+,(A2)+                     | fXOn, fCTS, xOn, xOff
        MOVE    (A0)+,(A2)+                     | errs, evts
        MOVE.B  (A0)+,(A2)                      | fInX
        BRA.B   SERD_CTL_NOERR                  | -> noErr
| SERD_CTL_CS11 -- csCode 11 SerClrBrk: WR5 = SV_WR5ON; csCode 12
| SerSetBrk: WR5 = SV_WR5ON + send-break (at once, even in the middle of
| a character).
SERD_CTL_CS11:
        MOVE.B  SV_WR5ON(A2),D0                 | D0 = WR5, no break
        SUBQ.W  #0x1,D1                         | csCode 11?
        BEQ.B   SERD_WRITEWR5                   | yes -> write it
        BSET    #0x4,D0                         | WR5 bit 4: send break
        SUBQ.W  #0x1,D1                         | csCode 12?
        BNE.B   SERD_CTL_BADCODE                | no -> controlErr
| SERD_WRITEWR5 -- write D0 to WR5, then noErr.
SERD_WRITEWR5:
        BSR.B   SERD_TXREADY                    | A3 = channel control (write)
        MOVE.B  #0x5,(A3)                       | select WR5
        MOVE.L  (SP),(SP)                       | delay between SCC accesses
        MOVE.B  D0,(A3)                         | write it
        BRA.B   SERD_CTL_NOERR                  | -> noErr
| SERD_CTL_BADCODE -- unknown csCode: controlErr.
SERD_CTL_BADCODE:
        MOVEQ.L #controlErr,D0                  | controlErr
| SERD_CTL_EXIT2 -- second hop to SERD_CTL_EXIT (short-branch reach).
SERD_CTL_EXIT2:
        BRA.B   SERD_CTL_EXIT                   | -> IODone

| ----------------------------------------------------------
| E_AOut_Prime / E_BOut_Prime -- Write (Prime) of .AOut / .BOut.
| SERD_WRITE: send the first character unless output is held; the Tx
| interrupt sends the others (SERD_TXINT -> SERD_XMIT). The request
| completes through IODone after its last character.
E_AOut_Prime:
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars
        BRA.B   SERD_WRITE                      | -> common Write

| ----------------------------------------------------------
| E_BOut_Prime -- Write of .BOut (see E_AOut_Prime).
E_BOut_Prime:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars
SERD_WRITE:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
        BSR.B   SERD_OUTHELD                    | output held (CTS or XOff)?
        BNE.B   SERD_XMIT_EXIT                  | yes -> wait for the release
| SERD_XMIT -- send the next character if the transmit buffer is empty: a
| waiting XOn/XOff character first, else the next byte of the write
| (JFetch, A1 = output DCE). The last byte (bit 15 of D0 set by Fetch)
| completes the write. Entered with SR pushed (Write, SERD_TXRESUME).
SERD_XMIT:
        BSR.B   SERD_TXREADY                    | transmit buffer empty? (A3 = channel control)
        BEQ.B   SERD_XMIT_EXIT                  | no -> the Tx interrupt comes later
        MOVE.B  SV_FLOWCHAR(A2),D0              | D0 = waiting XOn/XOff character
        CLR.B   SV_FLOWCHAR(A2)                 | taken
        ANDI    #0xFF,D0                        | (word: not the last byte) any?
        BNE.B   SERD_XMIT_CHAR                  | yes -> send it first
        MOVE.L  (JFetch).w,A0                   | A0 = Fetch
        JSR     (A0)                            | Fetch: D0 = next byte of the write (bit 15: last)
SERD_XMIT_CHAR:
        MOVE.B  D0,sccData(A3)                  | send it (data register)
        TST     D0                              | last byte of the write?
        BMI.B   SERD_XMIT_LAST                  | yes -> complete the write
SERD_XMIT_EXIT:
        ST      SV_WRPEND(A2)                   | wrPend: write in progress
        MOVEQ.L #0x0,D0                         | noErr (write still in progress)
        RTE                                     | pop the saved SR and return
| SERD_XMIT_LAST -- the last byte is in the transmitter: the write is done.
SERD_XMIT_LAST:
        CLR.B   SV_WRPEND(A2)                   | no write in progress
        MOVE    (SP)+,SR                        | restore the interrupt level
| SERD_DONE_NOERR -- complete the request of the DCE in A1 with noErr.
SERD_DONE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        BRA.B   SERD_CTL_EXIT2                  | -> IODone
| SERD_TXREADY -- A3 = this channel's control register for writing; Z = 0
| if the transmit buffer is empty (RR0 bit 2, txBE). Changes A3.
SERD_TXREADY:
        MOVEA.L (SCCRd).w,A3                    | A3 = SCC read base
        ADDA.W  SV_CHANOFS(A2),A3               | + channel offset: channel control (read)
        BTST    #txBE,(A3)                      | RR0 bit 2: transmit buffer empty?
        ADDA.L  #SCCWBase-SCCRBase,A3           | A3 = channel control (write); flags unchanged
        RTS                                     | Z = 0: buffer empty
| SERD_OUTHELD -- is output held? D0 = 1 (Z = 0) if fXOn is set and XOff
| was received, or fCTS is set and the CTS bit says hold; else D0 = 0.
SERD_OUTHELD:
        TST.B   SV_FXON(A2)                     | XOn/XOff output flow control?
        BEQ.B   SERD_OUTHELD_CTS                | no -> check CTS
        TST.B   SV_XOFFHOLD(A2)                 | XOff received?
        BNE.B   SERD_OUTHELD_YES                | yes -> held
SERD_OUTHELD_CTS:
        TST.B   SV_FCTS(A2)                     | CTS flow control?
        BEQ.B   SERD_OUTHELD_NO                 | no -> not held
        TST.B   SV_CTSHOLD(A2)                  | CTS bit set (handshake negated)?
        BEQ.B   SERD_OUTHELD_NO                 | no -> not held
SERD_OUTHELD_YES:
        MOVEQ.L #0x1,D0                         | held
        RTS                                     | return D0 = 1
SERD_OUTHELD_NO:
        MOVEQ.L #0x0,D0                         | not held
        RTS                                     | return D0 = 0

| ----------------------------------------------------------
| SERD_TXINT_B / SERD_TXINT_A -- transmit buffer empty interrupt (Lvl2DT
| vTxB / vTxA; A1 = channel control, write). SERD_TXINT sends a waiting
| XOn/XOff character or the next byte of the write; with nothing to send
| (no write, or output held) it resets the Tx interrupt.
SERD_TXINT_B:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars
        BRA.B   SERD_TXINT                      | -> common Tx interrupt

| ----------------------------------------------------------
| SERD_TXINT_A -- channel A (see SERD_TXINT_B).
SERD_TXINT_A:
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars
SERD_TXINT:
        TST.B   SV_FLOWCHAR(A2)                 | XOn/XOff character waiting?
        BNE.B   SERD_TXRESUME                   | yes -> send it
        TST.B   SV_WRPEND(A2)                   | write in progress?
        BEQ.B   SERD_TXINT_IDLE                 | no -> nothing to send
        BSR.B   SERD_OUTHELD                    | output held?
        BNE.B   SERD_TXINT_IDLE                 | yes -> wait for the release
| SERD_TXRESUME -- continue the write in SERD_XMIT (A1 = output DCE for
| Fetch and IODone; SR pushed for SERD_XMIT's exit).
SERD_TXRESUME:
        MOVE.L  (A2),A1                         | A1 = SV_OUTDCE: output DCE
        MOVE    SR,-(SP)                        | SR for SERD_XMIT's exit
        BRA.W   SERD_XMIT                       | -> send the next character
| SERD_TXINT_IDLE -- nothing to send: reset the Tx interrupt.
SERD_TXINT_IDLE:
        MOVE.B  #0x28,(A1)                      | WR0 = $28: reset Tx interrupt pending
        RTS                                     | return to the SCC dispatcher
| SERD_CLRXOFF -- XOn received: clear xOffHold.
| SERD_CHECKRESUME -- restart a pending write (XOn, CTS released); unlike
| the Plus driver it does not check SERD_OUTHELD again.
SERD_CLRXOFF:
        CLR.B   SV_XOFFHOLD(A2)                 | xOffHold = 0
SERD_CHECKRESUME:
        TST.B   SV_WRPEND(A2)                   | write in progress?
        BNE.B   SERD_TXRESUME                   | yes -> continue it
        RTS                                     | return from SERD_CHECKRESUME

| ----------------------------------------------------------
| E_AIn_Prime / E_BIn_Prime -- Read (Prime) of .AIn / .BIn.
| SERD_READ: pass characters from the input buffer to the read (JStash)
| until it is satisfied (-> IODone) or the buffer is empty; then rdPend is
| set and the receive interrupt delivers the rest. Sends XOn when the
| buffer has drained (fInX).
E_AIn_Prime:
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars
        BRA.B   SERD_READ                       | -> common Read

| ----------------------------------------------------------
| E_BIn_Prime -- Read of .BIn (see E_AIn_Prime).
E_BIn_Prime:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars
SERD_READ:
        BSR.B   SERD_GETBUF                     | A3 = buffer, D3 = size, D2 = out index
SERD_READ_LOOP:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
        CMP     SV_INIDX(A2),D2                 | buffer empty?
        BEQ.B   SERD_READ_PEND                  | yes -> wait for characters
        MOVE.B  0(A3,D2.W),D0                   | D0 = next character
        ADDQ.W  #0x1,D2                         | advance the out index
        CMP     D3,D2                           | past the end?
        BNE.B   SERD_READ_STASH                 | no ->
        MOVEQ.L #0x0,D2                         | wrap to 0
SERD_READ_STASH:
        MOVE    D2,SV_OUTIDX(A2)                | store the out index
        BSR.B   SERD_STASH                      | Stash: into the read's buffer (D0 < 0: full)
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST     D0                              | read satisfied?
        BPL.B   SERD_READ_LOOP                  | no -> next character
        BSR.B   SERD_INFLOW                     | XOn if the buffer has drained
        BRA.W   SERD_DONE_NOERR                 | -> IODone, noErr
| SERD_READ_PEND -- input buffer empty: the read waits (rdPend).
SERD_READ_PEND:
        ST      SV_RDPEND(A2)                   | rdPend: the receive code completes the read
        BRA.B   SERD_INFLOW_MASKED              | -> flow control check, SR already pushed
| SERD_INFLOW -- with interrupts masked: if fInX is set, XOff was sent and
| at most SV_LOWMARK characters are left, send XOn. SERD_INFLOW_MASKED:
| entry with SR pushed. Returns D0 = noErr (RTE pops the SR).
SERD_INFLOW:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
SERD_INFLOW_MASKED:
        TST.B   SV_FINX(A2)                     | XOn/XOff input flow control?
        BEQ.B   SERD_INFLOW_EXIT                | no -> done
        BSR.B   SERD_GETBUF                     | buffer state
        BSR.B   SERD_BUFCOUNT                   | D0 = characters in the buffer
        CMP     SV_LOWMARK(A2),D0               | at most the low mark?
        BHI.B   SERD_INFLOW_EXIT                | no -> done
        BCLR    #0x7,SV_XOFFSENT(A2)            | XOff sent?
        BEQ.B   SERD_INFLOW_EXIT                | no -> done
        MOVE.B  SV_XON(A2),D0                   | D0 = XOn character
        BSR.B   SERD_QUEUEFLOW                  | send it
SERD_INFLOW_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        RTE                                     | pop the saved SR and return
| SERD_STASH -- jump through JStash: Stash stores D0 into the buffer of the
| request of the DCE in A1 and returns D0 < 0 (N set) when it is full.
SERD_STASH:
        MOVE.L  (JStash).w,-(SP)                | push Stash's address
        RTS                                     | jump to Stash
| SERD_QUEUEFLOW -- send the flow-control character D0; if the opposite one
| is still waiting to be sent, the two cancel and neither is sent.
| Changes A0, A3.
SERD_QUEUEFLOW:
        LEA.L   SV_FLOWCHAR(A2),A0              | A0 -> waiting character
        TST.B   (A0)                            | a character still waiting?
        BEQ.B   SERD_SENDFLOW                   | no -> send this one
SERD_QUEUEFLOW_CLR:
        CLR.B   (A0)                            | nothing waiting (sent or cancelled)
SERD_QUEUEFLOW_RTS:
        RTS                                     | return from SERD_QUEUEFLOW
| SERD_SENDFLOW -- send D0 now if the transmit buffer is empty, else leave
| it in SV_FLOWCHAR for SERD_XMIT.
SERD_SENDFLOW:
        MOVE.B  D0,(A0)                         | waiting character
        BSR.W   SERD_TXREADY                    | transmit buffer empty?
        BEQ.B   SERD_QUEUEFLOW_RTS              | no -> sent before the next byte
        MOVE.B  D0,sccData(A3)                  | yes: send it now
        BRA.B   SERD_QUEUEFLOW_CLR              | -> no longer waiting

| ----------------------------------------------------------
| SERD_GETBUF -- input buffer state: A3 = buffer, D3 = size, D1 = in index,
| D2 = out index.
| Called by: SERD_STATUS, SERD_READ, SERD_INFLOW, SERD_RXBUFFER
SERD_GETBUF:
        MOVEA.L SV_BUFPTR(A2),A3                | A3 = input buffer
        MOVE.W  SV_BUFSIZE(A2),D3               | D3 = its size
        MOVEM   SV_INIDX(A2),D1-D2              | D1 = in index, D2 = out index
        RTS                                     | return with the buffer state
| SERD_BUFCOUNT -- D0 = number of characters in the input buffer (D1 - D2,
| plus the size D3 when the in index has wrapped).
SERD_BUFCOUNT:
        MOVE    D1,D0                           | in index
        SUB     D2,D0                           | - out index
        BCC.W   SERD_BUFCOUNT_RTS               | not wrapped ->
        ADD     D3,D0                           | + buffer size
SERD_BUFCOUNT_RTS:
        RTS                                     | D0 = characters in the buffer

| ----------------------------------------------------------
| SERD_POLLPROC -- modem port (channel A) poll procedure (PollProc): the
| .Sony driver calls it after a disk access with the bytes that its
| polling pushed on the stack, one per word below PollStack (A5 = VIA
| port A, A6 = SCC channel A data). It passes them, oldest first, to the
| receive code, polling the SCC on. The return address is kept in
| DskRtnAdr.
SERD_POLLPROC:
        MOVE.L  (PollStack).w,A4                | A4 = PollStack: start of the poll data
        MOVE.L  (SP)+,(DskRtnAdr).w             | DskRtnAdr = return address
| poll the SCC while processing the poll data
SERD_POLLPROC_POLL:
        TST.B   (A5)                            | VIA port A bit 7 (SCC W/REQ) = 0: byte waiting?
        BMI.B   SERD_POLLPROC_NEXT              | no ->
        MOVE.B  (A6),-(SP)                      | yes: push it (poll data)
        BRA.B   SERD_POLLPROC_POLL              | poll again
| SERD_POLLPROC_NEXT -- pass the next poll data byte to the receive code
SERD_POLLPROC_NEXT:
        CMPA.L  SP,A4                           | all poll data done (A4 = SP)?
        BEQ.B   SERD_POLLPROC_EXIT              | yes -> return
        SUBQ.W  #0x2,A4                         | next (older) byte: one per word
        MOVE.B  (A4),D0                         | D0 = received byte
        LEA.L   (SerialVars).w,A3               | A3 = port A pointers
        LEA.L   (SCC_RdCtlA).l,A0               | A0 = SCC channel A control (read)
        LEA.L   (SCC_WrCtlA).l,A1               | A1 = SCC channel A control (write)
        BSR.B   SERD_RXCHAR                     | into the input buffer like a received byte
        BRA.B   SERD_POLLPROC_POLL              | poll, then the next byte
| SERD_POLLPROC_EXIT -- discard the poll data (SP = PollStack) and return
SERD_POLLPROC_EXIT:
        MOVE.L  (PollStack).w,SP                | SP = PollStack
        MOVE.L  (DskRtnAdr).w,-(SP)             | push the saved return address
        RTS                                     | return to the .Sony driver

| ----------------------------------------------------------
| SERD_RXINT_B / SERD_RXINT_A -- receive character available interrupt
| (Lvl2DT vRxB / vRxA; A0 = channel control, read). SERD_RXCHAR (also from
| SERD_POLLPROC) takes the character in D0 with A3 -> the port's two
| SerialVars longs: handle XOn/XOff (fXOn; compared without bit 7), then
| store it (SERD_RXSTORE).
SERD_RXINT_B:
        LEA.L   (SerialVars+8).w,A3             | A3 -> port B pointers
        BRA.B   SERD_RXINT                      | -> common receive interrupt

| ----------------------------------------------------------
| SERD_RXINT_A -- channel A (see SERD_RXINT_B).
SERD_RXINT_A:
        LEA.L   (SerialVars).w,A3               | A3 -> port A pointers
SERD_RXINT:
        MOVE.B  sccData(A0),D0                  | D0 = received character (clears the interrupt)
SERD_RXCHAR:
        MOVE.L  (A3)+,A2                        | A2 = SERDVars
        MOVE.L  (A3),A3                         | A3 = input DCE (.AIn/.BIn)
        TST.B   SV_FXON(A2)                     | XOn/XOff output flow control?
        BEQ.B   SERD_RXSTORE                    | no -> store the character
        MOVEQ.L #0x7F,D1                        | 7 bits ...
        AND.B   D0,D1                           | ... of the character
        CMP.B   SV_XON(A2),D1                   | XOn?
        BEQ.W   SERD_CLRXOFF                    | yes -> clear xOffHold, resume output
        CMP.B   SV_XOFF(A2),D1                  | XOff?
        BNE.B   SERD_RXSTORE                    | no -> store the character
        ST      SV_XOFFHOLD(A2)                 | xOffHold: output stops
        BRA.B   SERD_RXINT_RTS                  | (XOn/XOff are not stored)

| ----------------------------------------------------------
| SERD_RXSTORE -- give the character D0 to a waiting read (Stash; a full
| read completes with noErr) or put it into the input buffer.
SERD_RXSTORE:
        TST.B   SV_RDPEND(A2)                   | read waiting?
        BEQ.B   SERD_RXBUFFER                   | no -> input buffer
        MOVE.L  A3,A1                           | A1 = input DCE
        BSR.W   SERD_STASH                      | Stash: into the read's buffer
        BPL.B   SERD_RXINT_RTS                  | not full yet -> done
        CLR.B   SV_RDPEND(A2)                   | read satisfied
        BRA.W   SERD_DONE_NOERR                 | -> IODone, noErr
| SERD_RXBUFFER -- put the character into the input buffer; a full buffer
| drops it (cumErrs swOverrunErr). With fInX, XOff is sent when fewer than
| SV_HIMARK characters are in the buffer (bug: the free space in D3 was
| meant; the Plus driver compares D3).
SERD_RXBUFFER:
        BSR.W   SERD_GETBUF                     | A3 = buffer, D3 = size, D1/D2 = in/out index
        MOVE.B  D0,0(A3,D1.W)                   | store the character
        ADDQ.W  #0x1,D1                         | advance the in index
        CMP     D3,D1                           | past the end?
        BNE.B   SERD_RXBUFFER_CHK               | no ->
        MOVEQ.L #0x0,D1                         | wrap to 0
SERD_RXBUFFER_CHK:
        CMP     D2,D1                           | buffer full (in reaches out)?
        BNE.B   SERD_RXBUFFER_STORED            | no -> keep the character
        BSET    #0x0,SV_CUMERRS(A2)             | cumErrs: swOverrunErr
        RTS                                     | character lost
| SERD_RXBUFFER_STORED -- the character is in; check input flow control.
SERD_RXBUFFER_STORED:
        MOVE.W  D1,SV_INIDX(A2)                 | store the in index
        TST.B   SV_FINX(A2)                     | XOn/XOff input flow control?
        BEQ.B   SERD_RXINT_RTS                  | no -> done
        BSR.W   SERD_BUFCOUNT                   | D0 = characters in the buffer
        SUB     D0,D3                           | D3 = free space (not used)
        CMP     SV_HIMARK(A2),D0                | characters (meant: free space) < the mark?
        BCC.B   SERD_RXINT_RTS                  | no -> done
        BSET    #0x7,SV_XOFFSENT(A2)            | XOff already sent?
        BNE.B   SERD_RXINT_RTS                  | yes -> nothing to send
        MOVE.B  SV_XOFF(A2),D0                  | D0 = XOff character
        BSR.W   SERD_QUEUEFLOW                  | send it
| SERD_RXINT_RTS -- end of the receive code.
| Called by: SERD_RXCHAR, SERD_RXSTORE, SERD_RXBUFFER_STORED, SERD_SPINT
| (6 branches)
SERD_RXINT_RTS:
        RTS                                     | return to the SCC dispatcher (or caller)

| ----------------------------------------------------------
| SERD_SPINT_B / SERD_SPINT_A -- special receive condition interrupt
| (Lvl2DT vSCB / vSCA; A0/A1 = channel control): parity error, receive
| overrun or framing error (RR1 bits 4-6). The errors are added to
| cumErrs; then (bug: errs EOR errors instead of AND) practically any
| error aborts a waiting read with rcvrErr (-89) and drops the character.
SERD_SPINT_B:
        LEA.L   (SerialVars+8).w,A3             | A3 -> port B pointers
        BRA.B   SERD_SPINT                      | -> common special-condition interrupt

| ----------------------------------------------------------
| SERD_SPINT_A -- channel A (see SERD_SPINT_B).
SERD_SPINT_A:
        LEA.L   (SerialVars).w,A3               | A3 -> port A pointers
SERD_SPINT:
        MOVE.B  #0x1,(A1)                       | select RR1
        MOVE.L  (A3)+,A2                        | A2 = SERDVars
        MOVE.L  (A3),A3                         | A3 = input DCE
        MOVE.B  (A0),D1                         | D1 = RR1
        MOVEQ.L #0x70,D3                        | $70: framing, Rx overrun, parity bits
        AND.B   D3,D1                           | D1 = the errors
        OR.B    D1,SV_CUMERRS(A2)               | add them to cumErrs
        MOVE.B  sccData(A0),D0                  | D0 = the character
        MOVE.B  SV_ERRS(A2),D2                  | D2 = errors that abort
        EOR.B   D1,D2                           | (meant: AND) with the errors
        MOVE.B  #0x30,(A1)                      | WR0 = $30: error reset
        AND.B   D3,D2                           | any?
        BEQ.W   SERD_RXSTORE                    | no -> store the character
        TST.B   SV_RDPEND(A2)                   | read waiting?
        BEQ.B   SERD_RXINT_RTS                  | no -> just drop the character
        MOVEQ.L #-0x59,D0                       | rcvrErr (-89): SCC receiver error
| SERD_ABORTREAD -- complete the waiting read of the input DCE (A3) with
| the error in D0 (also breakRecd from SERD_EXTINT_BRKRECD).
SERD_ABORTREAD:
        MOVE.L  A3,A1                           | A1 = input DCE
        CLR.B   SV_RDPEND(A2)                   | no read waiting
        BRA.W   SERD_IODONE                     | -> IODone with the error

| ----------------------------------------------------------
| SERD_EXTINT_B / SERD_EXTINT_A -- ext/status interrupt of the channel
| (ExtStsDT vComIntB / vComIntA, called by the ROM's ext/status dispatcher;
| D0 = RR0, D1 = changed enabled bits, A0/A1 = channel control). Posts a
| driver event for changes in evts and handles break (bit 7) and CTS
| (bit 5): ctsHold follows the CTS bit, a released CTS restarts a write.
SERD_EXTINT_B:
        LEA.L   (SerialVars+8).w,A3             | A3 -> port B pointers
        BRA.B   SERD_EXTINT                     | -> common ext/status interrupt

| ----------------------------------------------------------
| SERD_EXTINT_A -- channel A (see SERD_EXTINT_B).
SERD_EXTINT_A:
        LEA.L   (SerialVars).w,A3               | A3 -> port A pointers
SERD_EXTINT:
        MOVE.L  (A3)+,A2                        | A2 = SERDVars
        MOVE.L  (A3),A3                         | A3 = input DCE
        MOVE.B  D1,D2                           | D2 = changed bits
        AND.B   SV_EVTS(A2),D2                  | any that should post an event?
        BEQ.B   SERD_EXTINT_NOEVT               | no ->
        MOVEM.L D0/A0,-(SP)                     | save D0/A0
        MOVE    #0xB,A0                         | eventCode = 11 (driverEvt)
        ASL     #0x8,D0                         | message bits 24-31 = RR0
        MOVE.B  D1,D0                           | bits 16-23 = changed bits
        SWAP    D0                              | to the high word
        MOVE    dCtlRefNum(A3),D0               | bits 0-15 = refNum of .AIn/.BIn
        _PostEvent                              | post the driver event
        MOVEM.L (SP)+,D0/A0                     | restore D0/A0
SERD_EXTINT_NOEVT:
        TST.B   D1                              | break/abort bit changed?
        BMI.B   SERD_EXTINT_BREAK               | yes -> break
        LSL.B   #0x2,D0                         | RR0 bit 5 (CTS) -> N
        SMI     SV_CTSHOLD(A2)                  | ctsHold = $FF if CTS bit set
        BPL.W   SERD_CHECKRESUME                | CTS released -> restart a write
        RTS                                     | return to the dispatcher
| SERD_EXTINT_BREAK -- break/abort changed: at the start of a break
| (RR0 bit 7 set) abort a waiting read with breakRecd; at its end read
| and drop the null character the SCC receives.
SERD_EXTINT_BREAK:
        TST.B   D0                              | RR0 bit 7: break in progress?
        BMI.B   SERD_EXTINT_BRKRECD             | yes -> break received
        MOVE.B  sccData(A0),D0                  | end of break: drop the null character
        RTS                                     | return to the dispatcher
| SERD_EXTINT_BRKRECD -- break received: abort a waiting read with
| breakRecd (-90).
SERD_EXTINT_BRKRECD:
        MOVEQ.L #-0x5A,D0                       | breakRecd (-90)
        TST.B   SV_RDPEND(A2)                   | read waiting?
        BNE.B   SERD_ABORTREAD                  | yes -> complete it with the error
        RTS                                     | return to the dispatcher
