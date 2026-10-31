| SERD 0 -- the serial drivers .AIn, .AOut, .BIn, .BOut (driver version 2)
|
| resource : 'SERD' 0
|
| The four serial drivers of the 128K ROM: one input and one output driver
| for each channel of the Zilog Z8530 SCC; channel A drives the modem port,
| channel B the printer port. The input and output driver of a port share
| one block of variables (SERDVars), which the output driver's Open
| allocates, so the output driver must be opened first (and both before
| reading).
|
|   driver  refNum  port     header       SERDVars pointer  input DCE
|   .AIn     -6     modem    Driver_AIn   SerialVars+0      SerialVars+4
|   .AOut    -7     modem    Driver_AOut  SerialVars+0
|   .BIn     -8     printer  Driver_BIn   SerialVars+8      SerialVars+12
|   .BOut    -9     printer  Driver_BOut  SerialVars+8
|
| (SerialVars = $2D0, 16 bytes; lowmem.inc calls the four longs SerialVars_a,
| SerialVars_a_dce, ABusVars and ABusVars_dce: AppleTalk keeps its own
| pointer in the port B slot, the two cannot use the printer port at once.)
|
| Installation: InitIOMgr loads 'SERD' 0 from the ROM map and calls its first
| byte (_SERD_0_); SERD_INSTALL_DRVRS creates the four DCEs with _DrvrInstall.
| The drivers stay closed until an application opens them.
|
| Entry points (offsets in the DRVR headers; A0 = parameter block, A1 = DCE,
| D0 = 0 on entry):
|   Open     .AIn/.BIn (E_AIn_Open, E_BIn_Open): check the port (SPConfig,
|            PortAUse/PortBUse) and note the input DCE.
|            .AOut/.BOut (E_AOut_Open, E_BOut_Open): check the port, allocate
|            SERDVars, install the SCC interrupt handlers (port A also the
|            poll procedure), program the SCC from the PRAM SerConfig
|            (SPPortA/SPPortB; invalid: 9600 baud, 8 data bits, no parity,
|            2 stop bits) and assert DTR. fCTS stays 0: no CTS flow
|            control until SerHShake, although Inside Macintosh IV says
|            the driver opens with hardware handshake on (the 64K and the
|            SE driver do set fCTS).
|   Prime    .AIn/.BIn read from the input buffer (SERD_READ); .AOut/.BOut
|            send one character and let the Tx interrupt send the rest
|            (SERD_WRITE).
|   Control  E_AInOut_Control / E_BInOut_Control, one for both drivers of a
|   Status   port (E_AInOut_Status / E_BInOut_Status). They run with
|            interrupts masked and finish through IODone, or return
|            directly for an immediate call (noQueueBit).
|   Close    .AIn/.BIn: nothing (E_ABIn_Close). .AOut/.BOut: wait until all
|            characters are sent, shut the channel down (DTR negated unless
|            csCode 16 bit 7 is set), restore the interrupt vectors, free
|            SERDVars and mark the port free.
|
| Status calls:
|   2   SerGetBuf: number of characters in the input buffer (long)
|   8   SerStatus: the 6-byte SerStaRec; cumErrs is cleared afterwards
|   (No csCode 9: the driver version, 2, is the low byte of the DCE's
|   dCtlQueue flags. Inside Macintosh IV: ROM driver 0, RAM driver 1, 128K
|   ROM driver 2.)
| Control calls (names as in Inside Macintosh: Devices, ch. 7 / Serial.h):
|   1   KillIO: clear rdPend and wrPend, empty the input buffer
|   8   SerReset: new SerConfig (baud, data bits, parity, stop bits)
|   9   SerSetBuf: new input buffer (length 0 = the built-in 64 bytes)
|   10  SerHShake: SerShk record, first 7 bytes (fDTR unchanged)
|   11  SerClrBrk: write WR5 without send-break
|   12  SerSetBrk: wait until all is sent, then set send-break in WR5
|   13  set baud rate (csParam = rate; the rate set is returned)
|   14  SerHShake with fDTR (8th byte): DTR input flow control
|   15  (serSetMIDI of later drivers) not supported: controlErr
|   16  miscellaneous options: bit 7 = leave DTR as it is at close
|       (bit 6, external clock, came later and is ignored here)
|   17  assert DTR                 18  negate DTR
|   19  parity error replacement character (a good character equal to it
|       has bit 7 cleared)
|   20  parity error replacement character + alternate character
|   21  set the XOff state (xOffHold), as if XOff had been received
|   22  clear the XOff state
|   23  send XOn if XOff was sent last    24  send XOn
|   25  send XOff if XOn was sent last    26  send XOff
|   27  reset the SCC channel (WR9)
|   other csCodes: controlErr
| Inside Macintosh IV lists 14, 16, 17, 18 and 20 as new in the 128K ROM;
| 13, 19 and 21-27 come from the RAM serial driver of Inside Macintosh II.
|
| SerConfig word (Inside Macintosh II, "SerReset"): bits 0-9 baud-rate time
| constant (baud9600 = 10), bits 10-11 data bits (0 = 5, 1 = 7, 2 = 6,
| 3 = 8), bits 12-13 parity (1 odd, 3 even, else none), bits 14-15 stop
| bits (1 = 1, 2 = 1.5, 3 = 2; 0 is invalid). The bit layouts match the
| SCC's WR3/WR4/WR5 fields, so SERD_CONFIG_TBL can cut them out with a
| rotate and a mask.
|
| SCC addresses: SCCRd/SCCWr hold the read/write base (channel B control);
| + aCtl (2) gives channel A, + sccData (4) the data register. The level-2
| interrupt dispatcher (Lvl2Int_SCC) calls the handlers installed in Lvl2DT
| with A0 = the channel's control register (read), A1 = the same register
| (write); the ext/status handler gets D0 = RR0 and D1 = the changed RR0
| bits that are enabled in WR15.
|
| Sources: Inside Macintosh II ch. 9 "The Serial Drivers", IV ch. 22 "The
| Serial Driver", Inside Macintosh: Devices ch. 7; MPW 1.0 SysEqu.a (SerShk,
| SerStaRec, PortAUse); System 7.1 Serial.h (csCode names), HardwareEqu.a
| (macConst = 114709); Zilog Z8530 register descriptions.
|
| SERDVars -- the variables of one port, SV_SIZE bytes in a locked block in
| the system heap (handle in the output DCE's dCtlStorage, pointer in
| SerialVars+0 / +8; A2 in all routines). The SV_* names are this file's;
| +$10..+$17 hold a SerShk record and +$18..+$1D the SerStaRec that SerStatus
| returns (field names as in Inside Macintosh).
.set SV_OUTDCE, 0x00                            | output driver's DCE (.AOut/.BOut) [long]
.set SV_CHANOFS, 0x04                           | channel offset from SCCRd/SCCWr: aCtl (2) or bCtl (0) [word]
.set SV_BUFPTR, 0x06                            | input buffer [pointer]
.set SV_BUFSIZE, 0x0A                           | input buffer size [word]
.set SV_LOWMARK, 0x0C                           | input flow control ends at <= this many chars (size/4) [word]
.set SV_HIMARK, 0x0E                            | input flow control starts at < this much room (size/4) [word]
.set SV_FXON, 0x10                              | fXOn: XOn/XOff output flow control (stop on XOff)
.set SV_FCTS, 0x11                              | fCTS: CTS output flow control (0 after Open)
.set SV_XON, 0x12                               | xOn: XOn character
.set SV_XOFF, 0x13                              | xOff: XOff character
.set SV_ERRS, 0x14                              | errs: errors that abort a read ($10/$20/$40); $FF after Open
.set SV_EVTS, 0x15                              | evts: RR0 changes that post a driver event ($20 CTS, $80 break)
.set SV_FINX, 0x16                              | fInX: XOn/XOff input flow control
.set SV_FDTR, 0x17                              | fDTR: DTR input flow control (csCode 14)
.set SV_CUMERRS, 0x18                           | cumErrs: 1 sw overrun, $10 parity, $20 hw overrun, $40 framing
.set SV_XOFFSENT, 0x19                          | xOffSent: bit 7 XOff sent, bit 6 DTR negated
.set SV_RDPEND, 0x1A                            | rdPend: a read waits for characters
.set SV_WRPEND, 0x1B                            | wrPend: a write is in progress
.set SV_CTSHOLD, 0x1C                           | ctsHold: $FF while the CTS bit of RR0 is set (handshake input negated)
.set SV_XOFFHOLD, 0x1D                          | xOffHold: XOff received (or csCode 21)
.set SV_WR5, 0x1E                               | WR5 as written by Open and the DTR calls (current DTR state)
.set SV_WR5NODTR, 0x1F                          | WR5: transmitter on, RTS, DTR negated
.set SV_WR9RESET, 0x20                          | WR9 command that resets this channel: $82 (A) / $42 (B)
| shadow registers, in the order SERD_WRITEREGS uses them (SV_WR4 on):
.set SV_WR4, 0x21                               | WR4: x16 clock, stop bits, parity
.set SV_WR1INIT, 0x22                           | WR1 while the channel is programmed: interrupts off
.set SV_WR3OFF, 0x23                            | WR3: bits per character, receiver off
.set SV_WR5OFF, 0x24                            | WR5: bits per character, RTS, transmitter off, DTR negated
.set SV_WR12, 0x25                              | WR12: baud-rate time constant, low byte
.set SV_WR13, 0x26                              | WR13: time constant, high byte
.set SV_WR3ON, 0x27                             | WR3: receiver on
.set SV_WR5ON, 0x28                             | WR5: transmitter on, RTS, DTR asserted
.set SV_WR1, 0x29                               | WR1: interrupt enables, $F7 (A, with W/REQ) / $17 (B)
.set SV_CONFIG, 0x2A                            | SerConfig the channel runs with (0 after csCode 13) [word]
.set SV_INIDX, 0x2C                             | input buffer: where the next character goes [word]
.set SV_OUTIDX, 0x2E                            | input buffer: next character to read [word]
.set SV_DEFBUF, 0x30                            | built-in input buffer, 64 bytes
.set SV_EXTCOUNT, 0x70                          | ext/status interrupts in the current tick [word]
.set SV_EXTTICK, 0x72                           | Ticks value of that tick [long]
.set SV_FLOWCHAR, 0x76                          | XOn/XOff character waiting to be sent (0 = none)
.set SV_DATAMASK, 0x77                          | mask for received characters: $1F/$3F/$7F/$FF
.set SV_PECHAR, 0x78                            | parity error replacement character (0 = off)
.set SV_PEALT, 0x79                             | replaces a good character equal to SV_PECHAR
.set SV_FINXSAVE, 0x7A                          | fInX as set by SerHShake (csCode 26 clears SV_FINX, 24 restores it)
.set SV_MISC, 0x7B                              | csCode 16 options: bit 7 = leave DTR alone at close
.set SV_OLDVECS, 0x7C                           | vectors replaced by Open: ExtStsDT slot, Tx, Rx, special [4 longs]
.set SV_SIZE, 0x8C                              | size of SERDVars

| resource header: pseudo heap-block header of the ROM resource (as the
| Memory Manager's block header, so that a handle to the ROM resource
| behaves like one to a heap block)
    ROM_RESOURCE SERD_0                         | 8-byte resource header (include/romrsrc.inc)

| ----------------------------------------------------------
| _SERD_0_ -- resource entry: a BRA over the resource's own header
| (flags, type 'SERD', ID 0, version 2) to the installer.
_SERD_0_:
        BRA.B   SERD_INSTALL_DRVRS              | skip the resource header
  .byte 0x00,0x00                               | flags: none
  .ascii "SERD"                                 | resource type
  .byte 0x00,0x00,0x00,0x02                     | resource ID 0, version 2

| ----------------------------------------------------------
| SERD_INSTALL_DRVRS -- install the four serial drivers (called once by
| InitIOMgr through the resource's handle). For refNum -6 .. -9 it creates
| the DCE with _DrvrInstall (ResrvMem variant, DCE handle in A0), locks it
| and fills in the ROM driver: dCtlDriver = the DRVR header, dCtlFlags =
| its drvrFlags, dCtlQueue flags = 2 (low byte = driver version 2).
| The DRVR headers are pushed in reverse order so that they pop as .AIn,
| .AOut, .BIn, .BOut. Changes D0, D3, A0, A1.
SERD_INSTALL_DRVRS:
        PEA.L   Driver_BOut(PC)                 | refNum -9: .BOut
        PEA.L   Driver_BIn(PC)                  | refNum -8: .BIn
        PEA.L   Driver_AOut(PC)                 | refNum -7: .AOut
        PEA.L   Driver_AIn(PC)                  | refNum -6: .AIn (popped first)
        MOVEQ.L #-0x6,D3                        | D3 = first refNum (.AIn)
SERD_INSTALL_LOOP:
        MOVE    D3,D0                           | D0 = refNum for _DrvrInstall
        _DrvrInstallResrvMemA0Result            | create the DCE, handle -> A0
        BSET    #0x7,(A0)                       | lock the DCE (master pointer lock bit)
        MOVE.L  (A0),A0                         | A0 = DCE
        MOVE.L  (SP)+,A1                        | A1 = this driver's DRVR header
        MOVE.L  A1,(A0)+                        | dCtlDriver = DRVR header (ROM driver: pointer)
        MOVE    (A1),(A0)+                      | dCtlFlags = drvrFlags
        MOVE    #0x2,(A0)                       | dCtlQueue flags: low byte = version 2
        SUBQ.W  #0x1,D3                         | next refNum
        CMPI    #-0x9,D3                        | past .BOut (-9)?
        BGE.B   SERD_INSTALL_LOOP               | no -> install the next driver
        RTS                                     | return to InitIOMgr

| ----------------------------------------------------------
| DRVR headers. drvrFlags $4D00 (input) = dNeedLock + dStatEnable +
| dCtlEnable + dReadEnable; $4E00 (output) = the same with dWritEnable.
| No periodic action, no event mask, no menu. The routine offsets are
| relative to each header.
Driver_AIn:
  .short 0x4D00                                 | drvrFlags: read, control, status, needs lock
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short E_AIn_Open-Driver_AIn                  | drvrOpen
  .short E_AIn_Prime-Driver_AIn                 | drvrPrime: read
  .short E_AInOut_Control-Driver_AIn            | drvrCtl
  .short E_AInOut_Status-Driver_AIn             | drvrStatus
  .short E_ABIn_Close-Driver_AIn                | drvrClose
  .byte 0x04                                    | drvrName length
  .ascii ".AIn"                                 | drvrName: modem port input
  .byte 0x20                                    | pad to a word boundary

| .AOut -- modem port output driver
Driver_AOut:
  .short 0x4E00                                 | drvrFlags: write, control, status, needs lock
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short E_AOut_Open-Driver_AOut                | drvrOpen
  .short E_AOut_Prime-Driver_AOut               | drvrPrime: write
  .short E_AInOut_Control-Driver_AOut           | drvrCtl
  .short E_AInOut_Status-Driver_AOut            | drvrStatus
  .short E_AOut_Close-Driver_AOut               | drvrClose
  .byte 0x05                                    | drvrName length
  .ascii ".AOut"                                | drvrName: modem port output

| .BIn -- printer port input driver
Driver_BIn:
  .short 0x4D00                                 | drvrFlags: read, control, status, needs lock
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short E_BIn_Open-Driver_BIn                  | drvrOpen
  .short E_BIn_Prime-Driver_BIn                 | drvrPrime: read
  .short E_BInOut_Control-Driver_BIn            | drvrCtl
  .short E_BInOut_Status-Driver_BIn             | drvrStatus
  .short E_ABIn_Close-Driver_BIn                | drvrClose
  .byte 0x04                                    | drvrName length
  .ascii ".BIn"                                 | drvrName: printer port input
  .byte 0x20                                    | pad to a word boundary

| .BOut -- printer port output driver
Driver_BOut:
  .short 0x4E00                                 | drvrFlags: write, control, status, needs lock
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short E_BOut_Open-Driver_BOut                | drvrOpen
  .short E_BOut_Prime-Driver_BOut               | drvrPrime: write
  .short E_BInOut_Control-Driver_BOut           | drvrCtl
  .short E_BInOut_Status-Driver_BOut            | drvrStatus
  .short E_BOut_Close-Driver_BOut               | drvrClose
  .byte 0x05                                    | drvrName length
  .ascii ".BOut"                                | drvrName: printer port output

| ----------------------------------------------------------
| E_AIn_Open / E_BIn_Open -- Open of an input driver: check the port, note
| the DCE (A1) in SerialVars+4 / +12 for the receive interrupt code, set
| the driver version. The SCC and the variables are set up by the output
| driver's Open. Returns D0 = noErr, portNotCf or portInUse.
E_AIn_Open:
        BSR.B   SERD_CHECKPORT_A                | port A free or ours? (error: returns from Open)
        MOVE.L  A1,(SerialVars+4).w             | SerialVars+4 = .AIn DCE
        BRA.B   SERD_INOPEN_DONE                | -> set the version, noErr

| ----------------------------------------------------------
| E_BIn_Open -- Open of .BIn (see E_AIn_Open).
E_BIn_Open:
        BSR.B   SERD_CHECKPORT_B                | port B free or ours? (error: returns from Open)
        MOVE.L  A1,(SerialVars+12).w            | SerialVars+12 = .BIn DCE
SERD_INOPEN_DONE:
        MOVE.B  #0x2,dCtlQueue+1(A1)            | low byte of dCtlQueue flags = version 2
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from the input Open

| ----------------------------------------------------------
| SERD_CHECKPORT_A / SERD_CHECKPORT_B -- check that a port may be used by
| the serial driver and claim it. The port's nibble of SPConfig (PRAM:
| bits 4-7 port A, 0-3 port B) must be useFree (0) or useAsync (2); its
| PortAUse/PortBUse byte must be free (bit 7 set) or already useAsync. A
| free port is marked useAsync. On an error the routine discards its own
| return address and so returns from the calling Open with D0 = portNotCf
| (-98) or portInUse (-97). Changes D0, D1 (SPConfig shift), D2 (PortAUse
| rotate count: 8 for A, 0 for B).
SERD_CHECKPORT_A:
        MOVEQ.L #0x4,D1                         | port A: SPConfig bits 4-7
        MOVEQ.L #0x8,D2                         | port A: PortAUse is the high byte of the word
        BRA.B   SERD_CHECKPORT                  | -> common check

| ----------------------------------------------------------
| SERD_CHECKPORT_B -- port B entry of SERD_CHECKPORT_A.
SERD_CHECKPORT_B:
        MOVEQ.L #0x0,D1                         | port B: SPConfig bits 0-3
        MOVEQ.L #0x0,D2                         | port B: PortBUse is the low byte
SERD_CHECKPORT:
        MOVE.B  (SPConfig).w,D0                 | D0 = PRAM port configuration
        LSR.B   D1,D0                           | this port's nibble
        ANDI.B  #0xF,D0                         | to bits 0-3
        BEQ.B   SERD_CHECKPORT_USE              | useFree (0) -> ok
        SUBQ.B  #0x2,D0                         | useAsync (2)?
        BEQ.B   SERD_CHECKPORT_USE              | yes -> ok
        MOVEQ.L #-0x62,D0                       | portNotCf (-98): configured for another use
SERD_CHECKPORT_ERR:
        ADDQ.W  #0x4,SP                         | drop our return address
        RTS                                     | return from the Open with the error

| ----------------------------------------------------------
| SERD_CHECKPORT_USE -- the port's current use: PortAUse (high byte) and
| PortBUse (low byte) are read as one word and rotated so that this port's
| byte is the low byte.
SERD_CHECKPORT_USE:
        MOVE    (PortAUse).w,D0                 | D0 = PortAUse:PortBUse
        ROR     D2,D0                           | this port's byte -> low byte
        BCLR    #0x7,D0                         | bit 7 = 1: port not in use
        BNE.B   SERD_CHECKPORT_CLAIM            | free -> claim it
        EORI.B  #0x2,D0                         | in use: as useAsync (ours)?
        BEQ.B   SERD_CHECKPORT_OK               | yes -> ok
        MOVEQ.L #-0x61,D0                       | portInUse (-97): AppleTalk or another use
        BRA.B   SERD_CHECKPORT_ERR              | -> return from the Open

| ----------------------------------------------------------
| SERD_CHECKPORT_CLAIM -- mark the port as in use by the serial driver.
SERD_CHECKPORT_CLAIM:
        MOVE.B  #useAsync,D0                    | port byte = useAsync, bit 7 clear (in use)
        ROR     D2,D0                           | rotate back
        MOVE    D0,(PortAUse).w                 | store PortAUse:PortBUse
SERD_CHECKPORT_OK:
        RTS                                     | port ok, return to the Open

| ----------------------------------------------------------
| E_AOut_Open / E_BOut_Open -- Open of an output driver. Check the port,
| then push the handler addresses for SERD_OUTOPEN (in the order it pops
| them: ExtStsDT slot, ext/status handler, Lvl2DT slot, Tx, Rx, special,
| poll procedure) and load the channel constants:
|   D1 = channel offset (aCtl/bCtl), D2 = WR1 interrupt enables ($F7: port
|   A also sets W/REQ on received characters, which the .Sony driver polls
|   during disk transfers; $17 port B), D3 = WR9 channel reset command
|   ($82/$42), D4 = SerConfig from PRAM (SPPortA/SPPortB).
E_AOut_Open:
        BSR.B   SERD_CHECKPORT_A                | port A free or ours? (error: returns from Open)
        LEA.L   (SerialVars).w,A2               | A2 = SerialVars+0: port A pointer
        PEA.L   SERD_POLLPROC(PC)               | PollProc: pass polled bytes to port A
        PEA.L   SERD_SPINT_A(PC)                | special receive condition handler
        PEA.L   SERD_RXINT_A(PC)                | receive character available handler
        PEA.L   SERD_TXINT_A(PC)                | transmit buffer empty handler
        PEA.L   (Lvl2DT_4).w                    | Lvl2DT+16: channel A Tx slot (vTxA)
        PEA.L   SERD_EXTINT_A(PC)               | ext/status change handler
        PEA.L   (ExtStsDT_A).w                  | ExtStsDT+8: channel A slot (vComIntA)
        MOVEQ.L #aCtl,D1                        | channel offset: channel A control
        MOVEQ.L #-0x9,D2                        | WR1 = $F7: Rx/Tx/ext ints, W/REQ on receive
        MOVEQ.L #-0x7E,D3                       | WR9 = $82: reset channel A (no vector)
        MOVE    (SPPortA).w,D4                  | D4 = SerConfig of port A (PRAM)
        BRA.B   SERD_OUTOPEN                    | -> common output Open

| ----------------------------------------------------------
| E_BOut_Open -- Open of .BOut (see E_AOut_Open); no poll procedure.
E_BOut_Open:
        BSR.B   SERD_CHECKPORT_B                | port B free or ours? (error: returns from Open)
        LEA.L   (SerialVars+8).w,A2             | A2 = SerialVars+8: port B pointer
        CLR.L   -(SP)                           | no poll procedure
        PEA.L   SERD_SPINT_B(PC)                | special receive condition handler
        PEA.L   SERD_RXINT_B(PC)                | receive character available handler
        PEA.L   SERD_TXINT_B(PC)                | transmit buffer empty handler
        PEA.L   (Lvl2DT).w                      | Lvl2DT+0: channel B Tx slot (vTxB)
        PEA.L   SERD_EXTINT_B(PC)               | ext/status change handler
        PEA.L   (ExtStsDT).w                    | ExtStsDT+0: channel B slot (vComIntB)
        MOVEQ.L #bCtl,D1                        | channel offset: channel B control
        MOVEQ.L #0x17,D2                        | WR1 = $17: Rx/Tx/ext ints
        MOVEQ.L #0x42,D3                        | WR9 = $42: reset channel B (no vector)
        MOVE    (SPPortB).w,D4                  | D4 = SerConfig of port B (PRAM)
| SERD_OUTOPEN -- common output Open: allocate SERDVars (cleared) in the
| system heap; without memory, drop the 7 pushed longs and return the
| Memory Manager's error.
SERD_OUTOPEN:
        MOVEQ.L #0x46,D0                        | $46 ...
        ADD.L   D0,D0                           | ... * 2 = SV_SIZE ($8C)
        _ResrvMemSys                            | make room low in the system heap
        MOVEQ.L #0x46,D0                        | $46 ...
        ADD.L   D0,D0                           | ... * 2 = SV_SIZE
        _NewHandleSysClear                      | A0 = handle to cleared SERDVars
        BEQ.B   SERD_OUTOPEN_GOTVARS            | ok ->
        ADDA    #0x1C,SP                        | drop the 7 pushed longs
        RTS                                     | return from Open with D0 = memFullErr

| ----------------------------------------------------------
| SERD_OUTOPEN_GOTVARS -- install SERDVars and the interrupt handlers, save
| the replaced vectors in SV_OLDVECS (Close puts them back).
SERD_OUTOPEN_GOTVARS:
        MOVE.L  A0,dCtlStorage(A1)              | dCtlStorage = SERDVars handle
        MOVE.B  #0x2,dCtlQueue+1(A1)            | low byte of dCtlQueue flags = version 2
        MOVE.L  (A0),(A2)                       | SerialVars+0/+8 = SERDVars pointer
        BSET    #0x7,(A0)                       | lock SERDVars (master pointer lock bit)
        MOVE.L  (A0),A2                         | A2 = SERDVars
        LEA.L   SV_OLDVECS(A2),A3               | A3 = save area for the old vectors
        MOVE.L  (SP)+,A0                        | A0 = ExtStsDT slot of the channel
        MOVE.L  (A0),(A3)+                      | save its old handler
        MOVE.L  (SP)+,(A0)                      | install SERD_EXTINT_A/B
        MOVE.L  (SP)+,A0                        | A0 = channel's Lvl2DT Tx slot
        MOVE.L  (A0),(A3)+                      | save the old Tx handler
        MOVE.L  (SP)+,(A0)+                     | install SERD_TXINT_A/B
        ADDQ.W  #0x4,A0                         | skip the ext/status slot (ROM dispatcher stays)
        MOVE.L  (A0),(A3)+                      | save the old Rx handler
        MOVE.L  (SP)+,(A0)+                     | install SERD_RXINT_A/B
        MOVE.L  (A0),(A3)+                      | save the old special-condition handler
        MOVE.L  (SP)+,(A0)+                     | install SERD_SPINT_A/B
        MOVE.L  (SP)+,D0                        | D0 = poll procedure (0 for port B)
        BEQ.B   SERD_OUTOPEN_INITVARS           | none ->
        MOVE.L  D0,(PollProc).w                 | PollProc = SERD_POLLPROC
SERD_OUTOPEN_INITVARS:
        MOVE.L  A2,A3                           | A3 = SERDVars
        MOVE.L  A1,(A3)+                        | SV_OUTDCE = this (output) DCE
        MOVE    D1,(A3)+                        | SV_CHANOFS = aCtl/bCtl
        BSR     SERD_DEFAULTBUF                 | input buffer = built-in 64 bytes
        ST.B    SV_ERRS(A2)                     | errs = $FF: every receive error aborts a read
        MOVE.B  D3,SV_WR9RESET(A2)              | WR9 channel reset command
        MOVE.B  D2,SV_WR1(A2)                   | WR1 interrupt enables
| SERD_SETCONFIG -- set the channel up from the SerConfig word in D4 (Open,
| csCode 8 SerReset): data mask, shadow registers from SERD_CONFIG_TBL,
| SV_CONFIG, the WR5 values with and without DTR, then program the SCC
| (SERD_INITSCC; DTR asserted). An invalid word (stop bits 0) is replaced
| by $CC0A (9600 baud, 8 data bits, no parity, 2 stop bits). Returns
| D0 = noErr. Changes D0-D4, A3, A4.
SERD_SETCONFIG:
        MOVE    #-0x4000,D0                     | $C000: stop-bits field
        AND     D4,D0                           | stop bits given?
        BNE.B   SERD_SETCONFIG_VALID            | yes ->
        MOVE    #-0x33F6,D4                     | no: $CC0A = baud9600+data8+noParity+stop20
SERD_SETCONFIG_VALID:
        MOVE    #0xC00,D0                       | $0C00: data-bits field
        AND     D4,D0                           | isolate it
        ROL     #0x6,D0                         | -> index 0-3 (bits 10-11 rotate to 0-1)
        MOVE.B  SERD_DATAMASK_TBL(PC,D0.W),SV_DATAMASK(A2) | mask for received characters
        LEA.L   SV_WR4(A2),A3                   | A3 = first shadow register
        LEA.L   SERD_CONFIG_TBL(PC),A4          | A4 = rotate/AND/OR table
        MOVEQ.L #0x7,D0                         | 8 shadow registers (SV_WR4..SV_WR5ON)
SERD_SETCONFIG_LOOP:
        MOVE.B  (A4)+,D1                        | rotate count
        MOVE    D4,D3                           | D3 = SerConfig
        ROL     D1,D3                           | move the field to the register's bit position
        AND.B   (A4)+,D3                        | keep the field
        OR.B    (A4)+,D3                        | add the register's fixed bits
        MOVE.B  D3,(A3)+                        | store the shadow register
        DBF     D0,SERD_SETCONFIG_LOOP          | next register
        MOVEQ.L #0x64,D1                        | $64: W/REQ function bits, parity special
        AND.B   (A3)+,D1                        | of SV_WR1 (A3 -> SV_CONFIG afterwards)
        MOVE.B  D1,SV_WR1INIT(A2)               | WR1 while programming: no interrupts
        MOVE    D4,(A3)                         | SV_CONFIG = SerConfig
        MOVEQ.L #0x8,D0                         | WR5 bit 3: transmitter enable
        OR.B    SV_WR5OFF(A2),D0                | + bits per character, RTS
        MOVE.B  D0,SV_WR5NODTR(A2)              | SV_WR5NODTR = transmitter on, DTR negated
        MOVE.B  SV_WR5ON(A2),SV_WR5(A2)         | current WR5: transmitter on, DTR asserted
        BSR.B   SERD_INITSCC                    | program the channel
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from Open / SerReset

| ----------------------------------------------------------
| SERD_DATAMASK_TBL -- received-character mask, indexed by SerConfig bits
| 10-11 (the SCC's bits-per-character code).
SERD_DATAMASK_TBL:
  .byte 0x1F,0x7F,0x3F,0xFF                     | data5, data7, data6, data8
| SERD_CONFIG_TBL -- how SERD_SETCONFIG builds the shadow registers from
| the SerConfig word: per register a rotate count (ROL.W), an AND mask
| and an OR value.
SERD_CONFIG_TBL:
  .byte 0x04,0x0F,0x40                          | SV_WR4: stop bits + parity (bits 12-15), x16 clock
  .byte 0x00,0x00,0x00                          | SV_WR1INIT: 0 (replaced from SV_WR1 afterwards)
  .byte 0x0C,0xC0,0x00                          | SV_WR3OFF: Rx bits per character (bits 10-11), receiver off
  .byte 0x0B,0x60,0x02                          | SV_WR5OFF: Tx bits per character, RTS, transmitter off
  .byte 0x00,0xFF,0x00                          | SV_WR12: time constant bits 0-7
  .byte 0x08,0x03,0x00                          | SV_WR13: time constant bits 8-9
  .byte 0x0C,0xC0,0x01                          | SV_WR3ON: Rx bits per character, receiver on
  .byte 0x0B,0x60,0x8A                          | SV_WR5ON: Tx bits per character, DTR, transmitter on, RTS
| SERD_INIT_REGS -- register list that programs the channel (SERD_INITSCC).
| A pair whose second byte is $FF takes the value from the next shadow
| register (SV_WR4 on) and its first byte is the register number; in any
| other pair the second byte is the register number and the first the
| value (see SERD_WRITEREGS).
SERD_INIT_REGS:
  .byte 0x02,0x09                               | WR9 = $02: master interrupt enable off, no vector
  .byte 0x04,0xFF                               | WR4 = SV_WR4: x16 clock, stop bits, parity
  .byte 0x01,0xFF                               | WR1 = SV_WR1INIT: interrupts off
  .byte 0x03,0xFF                               | WR3 = SV_WR3OFF: receiver off
  .byte 0x05,0xFF                               | WR5 = SV_WR5OFF: transmitter off
  .byte 0x00,0x02                               | WR2 = $00: interrupt vector
  .byte 0x00,0x0A                               | WR10 = $00: NRZ
  .byte 0x50,0x0B                               | WR11 = $50: Rx and Tx clock = baud-rate generator
  .byte 0x0C,0xFF                               | WR12 = SV_WR12: time constant low
  .byte 0x0D,0xFF                               | WR13 = SV_WR13: time constant high
  .byte 0x03,0xFF                               | WR3 = SV_WR3ON: receiver on
  .byte 0x05,0xFF                               | WR5 = SV_WR5ON: transmitter on, RTS, DTR
  .byte 0x01,0x0E                               | WR14 = $01: baud-rate generator on (clock from RTxC)
  .byte 0xA8,0x0F                               | WR15 = $A8: break, CTS and DCD (mouse) interrupts
  .byte 0x10,0x00                               | WR0 = $10: reset ext/status interrupts
  .byte 0x10,0x00                               | WR0 = $10: again
  .byte 0x01,0xFF                               | WR1 = SV_WR1: interrupts on
  .byte 0x0A,0x09                               | WR9 = $0A: master interrupt enable, no vector

| ----------------------------------------------------------
| SERD_SCCADDR -- A0 = this channel's SCC control register for reading,
| A1 = for writing (SCCRd/SCCWr + SV_CHANOFS). Called by SERD_WRITEREGS
| and SERD_WAITSENT.
SERD_SCCADDR:
        MOVEM.L (SCCRd).w,A0-A1                 | A0 = SCCRd, A1 = SCCWr (channel B control)
        ADDA    SV_CHANOFS(A2),A0               | + channel offset
        ADDA    SV_CHANOFS(A2),A1               | + channel offset
        RTS                                     | return with A0/A1 = channel control

| ----------------------------------------------------------
| SERD_INITSCC -- program the channel with SERD_INIT_REGS (18 pairs).
| SERD_WRITEREGS -- write the register list at A3, D1 bytes long, to this
| channel with interrupts masked; $FF pairs take the next shadow register
| from SV_WR4 on. Then read RR0 and set ctsHold from its CTS bit.
| A2 = SERDVars. Changes D0-D2, A3.
SERD_INITSCC:
        LEA.L   SERD_INIT_REGS(PC),A3           | A3 = register list
        MOVEQ.L #0x24,D1                        | 36 bytes = 18 pairs
SERD_WRITEREGS:
        MOVE    SR,-(SP)                        | save the interrupt level
        MOVEM.L A0-A2,-(SP)                     | save A0-A2
        BSR.B   SERD_SCCADDR                    | A0/A1 = channel control (read/write)
        ORI     #0x300,SR                       | mask interrupts (IPL 3)
        MOVE.B  (A0),D2                         | dummy read: register pointer -> 0
        LEA.L   SV_WR4(A2),A2                   | A2 = first shadow register
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
        NOP                                     | delay before the next SCC access
        MOVE.B  (A0),D2                         | D2 = RR0
        MOVEM.L (SP)+,A0-A2                     | restore A0-A2
        LSL.B   #0x2,D2                         | RR0 bit 5 (CTS) -> N
        SMI.B   SV_CTSHOLD(A2)                  | ctsHold = $FF if CTS bit set
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return from SERD_WRITEREGS

| ----------------------------------------------------------
| SERD_CLOSE_REGS -- register list that shuts the channel down (output
| Close): receiver, transmitter and channel interrupts off, only the DCD
| interrupt for the mouse stays enabled. WR5 = SV_WR5OFF, DTR negated
| unless Close copied the current DTR state there (csCode 16 bit 7).
SERD_CLOSE_REGS:
  .byte 0x02,0x09                               | WR9 = $02: master interrupt enable off
  .byte 0x04,0xFF                               | WR4 = SV_WR4
  .byte 0x01,0xFF                               | WR1 = SV_WR1INIT: interrupts off
  .byte 0x03,0xFF                               | WR3 = SV_WR3OFF: receiver off
  .byte 0x05,0xFF                               | WR5 = SV_WR5OFF: transmitter off
  .byte 0x08,0x0F                               | WR15 = $08: only the DCD (mouse) interrupt
  .byte 0x01,0x01                               | WR1 = $01: ext/status interrupts only
  .byte 0x0A,0x09                               | WR9 = $0A: master interrupt enable, no vector

| ----------------------------------------------------------
| E_AOut_Close / E_BOut_Close -- Close of an output driver: remove the poll
| procedure (port A), then SERD_OUTCLOSE with A4 = the channel's Lvl2DT Tx
| slot, A5 = its ExtStsDT slot, A6 = its SerialVars pointer, D3 = PortAUse
| rotate count.
E_AOut_Close:
        CLR.L   (PollProc).w                    | no poll procedure any more
        LEA.L   (Lvl2DT_4).w,A4                 | A4 = Lvl2DT+16: channel A Tx slot
        LEA.L   (ExtStsDT_A).w,A5               | A5 = ExtStsDT+8: channel A slot
        LEA.L   (SerialVars).w,A6               | A6 = SerialVars+0: port A pointer
        MOVEQ.L #0x8,D3                         | PortAUse: high byte
        BRA.B   SERD_OUTCLOSE                   | -> common output Close

| ----------------------------------------------------------
| E_BOut_Close -- Close of .BOut (see E_AOut_Close).
E_BOut_Close:
        LEA.L   (Lvl2DT).w,A4                   | A4 = Lvl2DT+0: channel B Tx slot
        LEA.L   (ExtStsDT).w,A5                 | A5 = ExtStsDT+0: channel B slot
        LEA.L   (SerialVars+8).w,A6             | A6 = SerialVars+8: port B pointer
        MOVEQ.L #0x0,D3                         | PortBUse: low byte
| SERD_OUTCLOSE -- common output Close: keep DTR if csCode 16 bit 7 asked
| for it, wait until all characters are sent, shut the channel down,
| restore the interrupt vectors, free SERDVars, clear the SerialVars
| pointer and mark the port free.
SERD_OUTCLOSE:
        MOVE.L  (A6),A2                         | A2 = SERDVars
        TST.B   SV_MISC(A2)                     | csCode 16 bit 7: leave DTR alone?
        BPL.B   SERD_OUTCLOSE_RESET             | no -> SV_WR5OFF negates DTR
        MOVEQ.L #-0x9,D0                        | $F7: all but transmitter enable
        AND.B   SV_WR5(A2),D0                   | current WR5 (DTR as it is), transmitter off
        MOVE.B  D0,SV_WR5OFF(A2)                | WR5 for the close list
SERD_OUTCLOSE_RESET:
        BSR.B   SERD_WAITSENT                   | wait until the last character has left
        LEA.L   SERD_CLOSE_REGS(PC),A3          | A3 = shut-down register list
        MOVEQ.L #0x10,D1                        | 16 bytes = 8 pairs
        BSR     SERD_WRITEREGS                  | write it
        LEA.L   SV_OLDVECS(A2),A3               | A3 = vectors saved by Open
        MOVE.L  (A3)+,(A5)                      | ExtStsDT slot
        MOVE.L  (A3)+,(A4)+                     | Tx slot
        ADDQ.L  #0x4,A4                         | skip the ext/status slot
        MOVE.L  (A3)+,(A4)+                     | Rx slot
        MOVE.L  (A3),(A4)                       | special-condition slot
        MOVE.L  dCtlStorage(A1),A0              | A0 = SERDVars handle
        _DisposeHandle                          | free SERDVars
        CLR.L   dCtlStorage(A1)                 | no storage
        CLR.L   (A6)                            | SerialVars pointer = 0: port closed
        MOVE    (PortAUse).w,D0                 | D0 = PortAUse:PortBUse
        ROR     D3,D0                           | this port's byte -> low byte
        ST.B    D0                              | $FF: port not in use
        ROR     D3,D0                           | rotate back
        MOVE    D0,(PortAUse).w                 | store PortAUse:PortBUse
| E_ABIn_Close -- Close of .AIn/.BIn (nothing to do) and the end of the
| output Close.
E_ABIn_Close:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from Close

| ----------------------------------------------------------
| SERD_WAITSENT -- wait until the transmitter has sent everything: poll RR1
| bit 0 (All Sent) with interrupts masked for each read, at most 65536
| times. Called by SERD_OUTCLOSE and SERD_SERSETBRK (break and close start
| after the current transmission). Preserves all registers.
SERD_WAITSENT:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save D0-D1/A0-A1
        BSR     SERD_SCCADDR                    | A0/A1 = channel control (read/write)
        MOVEQ.L #-0x1,D1                        | at most 65536 polls
SERD_WAITSENT_LOOP:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
        MOVE.B  (A0),D0                         | dummy read: register pointer -> 0
        MOVE.L  (SP),(SP)                       | delay between SCC accesses
        MOVE.B  #0x1,(A1)                       | select RR1
        MOVE.L  (SP),(SP)                       | delay
        MOVE.B  (A0),D0                         | D0 = RR1
        MOVE    (SP)+,SR                        | restore the interrupt level
        LSR.B   #0x1,D0                         | bit 0 (All Sent) -> C
        DBCS    D1,SERD_WAITSENT_LOOP           | not all sent -> poll again
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore D0-D1/A0-A1
        RTS                                     | return from SERD_WAITSENT

| ----------------------------------------------------------
| E_AInOut_Status / E_BInOut_Status -- Status of both drivers of port A / B.
| SERD_STATUS: csCode 2 SerGetBuf, csCode 8 SerStatus; statusErr for other
| codes or a closed port (no SERDVars). Saves ioTrap, the DCE and SR for
| the common exit (SERD_CTLSTAT_EXIT).
E_AInOut_Status:
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars (0: not open)
        BRA.B   SERD_STATUS                     | -> common Status

| ----------------------------------------------------------
| E_BInOut_Status -- Status of port B (see E_AInOut_Status).
E_BInOut_Status:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars (0: not open)
SERD_STATUS:
        MOVE    ioTrap(A0),-(SP)                | save ioTrap (noQueueBit for the exit)
        MOVE.L  A1,-(SP)                        | save the DCE
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
        LEA.L   csCode(A0),A0                   | A0 -> csCode
        MOVEQ.L #statusErr,D0                   | default result: statusErr
        MOVE.L  A2,D1                           | port open?
        BLE.B   SERD_CTLSTAT_EXIT               | no -> statusErr
        MOVE    (A0)+,D1                        | D1 = csCode, A0 -> csParam
        SUBQ.W  #0x2,D1                         | csCode 2 (SerGetBuf)?
        BNE.B   SERD_STATUS_CS8                 | no ->
        BSR     SERD_GETBUF                     | D1/D2 = in/out index, D3 = size
        BSR     SERD_BUFCOUNT                   | D0 = characters in the input buffer
        CLR     (A0)+                           | csParam: count, high word 0
        MOVE    D0,(A0)                         | low word
        BRA.B   SERD_CTLSTAT_NOERR              | -> noErr

| ----------------------------------------------------------
| SERD_STATUS_CS8 -- csCode 8 SerStatus: copy the SerStaRec (cumErrs,
| xOffSent, rdPend, wrPend, ctsHold, xOffHold) and clear cumErrs.
SERD_STATUS_CS8:
        SUBQ.W  #0x6,D1                         | csCode 8?
        BNE.B   SERD_CTLSTAT_EXIT               | no -> statusErr
        MOVE    SV_CUMERRS(A2),(A0)+            | cumErrs, xOffSent
        CLR.B   SV_CUMERRS(A2)                  | errors are reported once
        MOVE.L  SV_RDPEND(A2),(A0)+             | rdPend, wrPend, ctsHold, xOffHold
        BRA.B   SERD_CTLSTAT_NOERR              | -> noErr

| ----------------------------------------------------------
| E_AInOut_Control / E_BInOut_Control -- Control of both drivers of port
| A / B. SERD_CONTROL: csCode 1 (KillIO) is handled inline and returns
| directly; csCodes 8-27 go through SERD_CTL_TBL with A0 -> csParam,
| A2 = SERDVars, D0 = SV_WR5ON (used by csCodes 11 and 12) and the saved
| SR at 4(SP); other codes and a closed port give controlErr.
E_AInOut_Control:
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars (0: not open)
        BRA.B   SERD_CONTROL                    | -> common Control

| ----------------------------------------------------------
| E_BInOut_Control -- Control of port B (see E_AInOut_Control).
E_BInOut_Control:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars (0: not open)
SERD_CONTROL:
        MOVE    ioTrap(A0),-(SP)                | save ioTrap (noQueueBit for the exit)
        MOVE.L  A1,-(SP)                        | save the DCE
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
        LEA.L   csCode(A0),A0                   | A0 -> csCode
        MOVE    (A0)+,D1                        | D1 = csCode, A0 -> csParam
        SUBQ.W  #killCode,D1                    | csCode 1 (KillIO)?
        BNE.B   SERD_CONTROL_TABLE              | no -> table
        MOVE.L  A2,D2                           | port open?
        BLE.B   SERD_KILLIO_EXIT                | no -> nothing to do
        CLR     SV_RDPEND(A2)                   | rdPend = wrPend = 0
        CLR.L   SV_INIDX(A2)                    | in = out index: input buffer empty
SERD_KILLIO_EXIT:
        MOVE    (SP)+,SR                        | restore the interrupt level
        ADDQ.W  #0x6,SP                         | drop the DCE and ioTrap
        RTS                                     | return to KillIO (D0 = 0 from the Device Manager)

| ----------------------------------------------------------
| SERD_CONTROL_TABLE -- csCodes 8-27 through SERD_CTL_TBL.
SERD_CONTROL_TABLE:
        MOVE.L  A2,D2                           | port open?
        BLE.B   SERD_CTL_BADCODE                | no -> controlErr
        LEA.L   SERD_CTL_TBL(PC),A1             | A1 = dispatch table
        SUBQ.W  #0x7,D1                         | D1 = csCode - 8
        BMI.B   SERD_CTL_BADCODE                | below 8 -> controlErr
        CMPI    #0x13,D1                        | above 27?
        BHI.B   SERD_CTL_BADCODE                | yes -> controlErr
        ADD     D1,D1                           | word index
        MOVE    0x0(A1,D1.W),D1                 | D1 = handler offset from the table
        MOVE.B  SV_WR5ON(A2),D0                 | D0 = WR5 (transmitter on, DTR) for csCodes 11/12
        JSR     0x0(A1,D1.W)                    | call the csCode's handler
| SERD_CTLSTAT_NOERR / SERD_CTLSTAT_EXIT -- common end of Control and
| Status: restore SR and the DCE; an immediate call (noQueueBit in the
| saved ioTrap) returns directly, a queued one completes through IODone.
SERD_CTLSTAT_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
SERD_CTLSTAT_EXIT:
        MOVE    (SP)+,SR                        | restore the interrupt level
        MOVE.L  (SP)+,A1                        | A1 = DCE
        BTST    #noQueueBit,(SP)+               | immediate call? (bit 1 of ioTrap's high byte)
        BEQ.B   SERD_IODONE                     | no -> complete through IODone
        RTS                                     | immediate: return directly

| ----------------------------------------------------------
| SERD_IODONE -- complete the request of the DCE in A1 with result D0:
| jump through JIODone (IODone returns to our caller).
| Called by: SERD_CTLSTAT_EXIT, SERD_DONE_NOERR, SERD_READ, SERD_ABORTREAD
SERD_IODONE:
        MOVE.L  (JIODone).w,-(SP)               | push IODone's address
        RTS                                     | jump to IODone

| ----------------------------------------------------------
| SERD_CTL_UNIMP -- csCode 15 (not supported): drop the return address of
| the handler call, controlErr.
SERD_CTL_UNIMP:
        ADDQ.W  #0x4,SP                         | drop the JSR return address
SERD_CTL_BADCODE:
        MOVEQ.L #controlErr,D0                  | controlErr
        BRA.B   SERD_CTLSTAT_EXIT               | -> common exit

| SERD_CTL_TBL -- Control handlers for csCodes 8-27, word offsets from the
| table (called by SERD_CONTROL_TABLE).
SERD_CTL_TBL:
  .short SERD_SERRESET-SERD_CTL_TBL             | 8   SerReset
  .short SERD_SERSETBUF-SERD_CTL_TBL            | 9   SerSetBuf
  .short SERD_SERHSHAKE-SERD_CTL_TBL            | 10  SerHShake
  .short SERD_WRITEWR5-SERD_CTL_TBL             | 11  SerClrBrk: WR5 = D0 (no break)
  .short SERD_SERSETBRK-SERD_CTL_TBL            | 12  SerSetBrk
  .short SERD_SETBAUD-SERD_CTL_TBL              | 13  set baud rate
  .short SERD_HSHAKEDTR-SERD_CTL_TBL            | 14  SerHShake with fDTR
  .short SERD_CTL_UNIMP-SERD_CTL_TBL            | 15  not supported
  .short SERD_SETMISC-SERD_CTL_TBL              | 16  miscellaneous options
  .short SERD_SETDTR-SERD_CTL_TBL               | 17  assert DTR
  .short SERD_CLRDTR-SERD_CTL_TBL               | 18  negate DTR
  .short SERD_SETPECHAR-SERD_CTL_TBL            | 19  parity error replacement
  .short SERD_SETPECHARALT-SERD_CTL_TBL         | 20  parity error replacement + alternate
  .short SERD_SETXOFF-SERD_CTL_TBL              | 21  set the XOff state
  .short SERD_CLRXOFF-SERD_CTL_TBL              | 22  clear the XOff state
  .short SERD_SENDXONCOND-SERD_CTL_TBL          | 23  XOn if XOff was sent
  .short SERD_SENDXON-SERD_CTL_TBL              | 24  XOn
  .short SERD_SENDXOFFCOND-SERD_CTL_TBL         | 25  XOff if XOn was sent
  .short SERD_SENDXOFF-SERD_CTL_TBL             | 26  XOff
  .short SERD_CHANRESET-SERD_CTL_TBL            | 27  reset the channel

| ----------------------------------------------------------
| SERD_SERRESET -- csCode 8 SerReset: csParam = SerConfig. A new value is
| set up through SERD_SETCONFIG (shadow registers, SCC programmed).
SERD_SERRESET:
        MOVE    (A0)+,D4                        | D4 = new SerConfig
        CMP     SV_CONFIG(A2),D4                | the current one?
        BEQ.B   SERD_SETBUF_RTS                 | yes -> nothing to do
        BRA     SERD_SETCONFIG                  | set it up, return noErr

| ----------------------------------------------------------
| SERD_SERSETBUF -- csCode 9 SerSetBuf: csParam = buffer pointer (long),
| csParam+4 = its length (0: the built-in buffer). Empties the buffer.
SERD_SERSETBUF:
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
SERD_SETBUF_RTS:
        RTS                                     | return from the buffer setup

| ----------------------------------------------------------
| SERD_HSHAKEDTR -- csCode 14: SerShk record with fDTR (csParam+7).
| SERD_SERHSHAKE -- csCode 10 SerHShake: SerShk record, fDTR unchanged.
| Both copy fXOn, fCTS, xOn, xOff, errs, evts, fInX; a cleared fInX sends
| XOn if XOff had been sent, output restarts if it is no longer held, and
| switching DTR flow control off asserts DTR.
SERD_HSHAKEDTR:
        MOVE.B  0x7(A0),-(SP)                   | push the new fDTR
        BRA.B   SERD_HSHAKE_COMMON              | -> common part

| ----------------------------------------------------------
| SERD_SERHSHAKE -- csCode 10 (see SERD_HSHAKEDTR).
SERD_SERHSHAKE:
        MOVE.B  SV_FDTR(A2),-(SP)               | push the current fDTR (unchanged)
SERD_HSHAKE_COMMON:
        TST.B   SV_FXON(A2)                     | XOn/XOff output flow control was on?
        BNE.B   SERD_HSHAKE_COPY                | yes -> keep xOffHold
        CLR.B   SV_XOFFHOLD(A2)                 | no: drop a stale XOff state
SERD_HSHAKE_COPY:
        MOVE.L  (A0)+,SV_FXON(A2)               | fXOn, fCTS, xOn, xOff
        MOVE    (A0)+,SV_ERRS(A2)               | errs, evts
        MOVE.B  (A0)+,D0                        | D0 = fInX
        MOVE.B  D0,SV_FINX(A2)                  | fInX
        MOVE.B  D0,SV_FINXSAVE(A2)              | and its copy for csCode 24
        BNE.B   SERD_HSHAKE_RESUME              | input flow control on ->
        BSR     SERD_SENDXONCOND                | off: send XOn if XOff was sent
SERD_HSHAKE_RESUME:
        BSR     SERD_CHECKRESUME                | restart output if no longer held
        MOVE.B  (SP)+,D0                        | D0 = new fDTR
        CMP.B   SV_FDTR(A2),D0                  | changed?
        BEQ.B   SERD_HSHAKE_DONE                | no -> done
        MOVE.B  D0,SV_FDTR(A2)                  | fDTR
        BEQ.B   SERD_SETDTR                     | DTR flow control off -> assert DTR
SERD_HSHAKE_DONE:
        RTS                                     | return from SerHShake

| ----------------------------------------------------------
| SERD_SETMISC -- csCode 16: csParam byte = options; only bit 7 (leave DTR
| alone at Close) is used.
SERD_SETMISC:
        MOVE.B  (A0),SV_MISC(A2)                | SV_MISC = option byte
        RTS                                     | return from csCode 16

| ----------------------------------------------------------
| SERD_CLRDTR -- csCode 18: negate DTR (also used by the receive code for
| DTR input flow control): WR5 = SV_WR5NODTR, dtrNegated set.
| SERD_SETDTR -- csCode 17: assert DTR: WR5 = SV_WR5ON, dtrNegated clear.
| Both keep the value in SV_WR5. Change D0, D1, A3.
SERD_CLRDTR:
        MOVE.B  SV_WR5NODTR(A2),D0              | D0 = WR5 with DTR negated
        BSET    #0x6,SV_XOFFSENT(A2)            | xOffSent: dtrNegated
        BRA.B   SERD_DTR_WRITE                  | -> write WR5

| ----------------------------------------------------------
| SERD_SETDTR -- csCode 17 (see SERD_CLRDTR).
SERD_SETDTR:
        MOVE.B  SV_WR5ON(A2),D0                 | D0 = WR5 with DTR asserted
        BCLR    #0x6,SV_XOFFSENT(A2)            | xOffSent: dtrNegated off
SERD_DTR_WRITE:
        MOVE.B  D0,SV_WR5(A2)                   | remember the DTR state
        BRA.B   SERD_WRITEWR5                   | -> write WR5

| ----------------------------------------------------------
| SERD_SERSETBRK -- csCode 12 SerSetBrk: wait (with the caller's interrupt
| level) until all characters are sent, then write WR5 = D0 (SV_WR5ON from
| the dispatcher, so DTR is asserted too) with send-break.
SERD_SERSETBRK:
        MOVE    0x4(SP),SR                      | caller's interrupt level (SR saved by SERD_CONTROL)
        BSR     SERD_WAITSENT                   | let the transmitter finish
        ORI     #0x300,SR                       | mask interrupts again
        BSET    #0x4,D0                         | WR5 bit 4: send break
| SERD_WRITEWR5 -- write D0 to WR5; also csCode 11 SerClrBrk, entered with
| D0 = SV_WR5ON (no break: note that this asserts DTR even after csCode 18).
| SERD_WRITEREG -- write D0 to SCC register D1 of this channel. Changes A3.
SERD_WRITEWR5:
        MOVEQ.L #0x5,D1                         | WR5
SERD_WRITEREG:
        BSR     SERD_TXREADY                    | A3 = channel control (write)
        MOVE.B  D1,(A3)                         | select the register
        MOVE.L  (SP),(SP)                       | delay between SCC accesses
        MOVE.B  D0,(A3)                         | write the value
        RTS                                     | return from the register write

| ----------------------------------------------------------
| SERD_SETBAUD -- csCode 13: csParam = baud rate. Time constant
| TC = round(114709 / rate) - 2 (114709 = 3.6707 MHz SCC clock / 32,
| HardwareEqu.a macConst; x16 clock), into SV_WR12/SV_WR13; the rate
| actually set, 114709 / (TC + 2), is returned in csParam. SV_CONFIG is
| cleared (it no longer describes the rate, so the next SerReset is never
| skipped) and the channel reprogrammed. No check of the rate: 0 divides
| by zero, 1 overflows the DIVU.
SERD_SETBAUD:
        MOVE.L  #0x1C015,D2                     | D2 = 114709 (macConst)
        MOVE.L  D2,D3                           | D3 = the same
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A0),D0                         | D0 = requested rate
        MOVE.L  D0,D1                           | D1 = rate
        LSR     #0x1,D1                         | rate / 2 (rounding)
        ADD.L   D1,D2                           | 114709 + rate/2
        DIVU    D0,D2                           | D2 = TC + 2, rounded
        MOVE    D2,D1                           | D1 = TC + 2
        SUBQ.W  #0x2,D2                         | D2 = time constant
        MOVE.B  D2,SV_WR12(A2)                  | WR12: low byte
        LSR     #0x8,D2                         | high byte
        MOVE.B  D2,SV_WR13(A2)                  | WR13
        DIVU    D1,D3                           | D3 = 114709 / (TC + 2) = rate set
        MOVE    D3,(A0)                         | return it in csParam
        CLR     SV_CONFIG(A2)                   | SerConfig unknown
        BRA     SERD_INITSCC                    | reprogram the channel

| ----------------------------------------------------------
| SERD_SETXOFF -- csCode 21: set xOffHold, as if XOff had been received
| (output stops if fXOn is set).
SERD_SETXOFF:
        ST.B    SV_XOFFHOLD(A2)                 | xOffHold = $FF
        RTS                                     | return from csCode 21

| ----------------------------------------------------------
| SERD_SENDXON -- csCode 24: send XOn unconditionally and switch automatic
| input flow control back to the SerHShake setting (csCode 26 clears it).
SERD_SENDXON:
        BCLR    #0x7,SV_XOFFSENT(A2)            | xOffSent: XOff no longer outstanding
        MOVE.B  SV_FINXSAVE(A2),SV_FINX(A2)     | fInX as set by SerHShake
        MOVE.B  SV_XON(A2),D0                   | D0 = XOn character
SERD_SENDXONOFF:
        BRA     SERD_SENDFLOW                   | send it now or after the current character

| ----------------------------------------------------------
| SERD_SENDXOFF -- csCode 26: send XOff unconditionally; automatic input
| flow control (fInX) is off until csCode 24 (it would send XOn).
SERD_SENDXOFF:
        BSET    #0x7,SV_XOFFSENT(A2)            | xOffSent: XOff sent
        CLR.B   SV_FINX(A2)                     | no automatic XOn
        MOVE.B  SV_XOFF(A2),D0                  | D0 = XOff character
        BRA.B   SERD_SENDXONOFF                 | -> send it

| ----------------------------------------------------------
| SERD_CHANRESET -- csCode 27: reset the channel with WR9 = SV_WR9RESET
| (the caller must do a SerReset before using the port again).
SERD_CHANRESET:
        MOVE.B  SV_WR9RESET(A2),D0              | D0 = channel reset command
        MOVEQ.L #0x9,D1                         | WR9
        BRA.B   SERD_WRITEREG                   | -> write it

| ----------------------------------------------------------
| SERD_SETPECHARALT -- csCode 20: csParam = replacement character,
| csParam+1 = alternate character (for a good character equal to the
| replacement).
SERD_SETPECHARALT:
        MOVE    (A0),SV_PECHAR(A2)              | SV_PECHAR, SV_PEALT
        RTS                                     | return from csCode 20

| ----------------------------------------------------------
| SERD_SETPECHAR -- csCode 19: csParam = replacement character; a good
| character equal to it arrives with bit 7 cleared.
SERD_SETPECHAR:
        MOVE.B  (A0),SV_PECHAR(A2)              | replacement character
        MOVE.B  (A0),SV_PEALT(A2)               | alternate = the same ...
        BCLR    #0x7,SV_PEALT(A2)               | ... with bit 7 cleared
        RTS                                     | return from csCode 19

| ----------------------------------------------------------
| E_AOut_Prime / E_BOut_Prime -- Write (Prime) of .AOut / .BOut.
| SERD_WRITE: mark the write in progress and send its first character
| unless output is held; the Tx interrupt sends the others (SERD_TXINT ->
| SERD_XMIT). The request completes through IODone after its last
| character.
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
        ST.B    SV_WRPEND(A2)                   | wrPend: write in progress
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
        MOVEQ.L #0x0,D0                         | noErr (write still in progress)
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return (the write stays pending)

| ----------------------------------------------------------
| SERD_XMIT_LAST -- the last byte is in the transmitter: the write is done.
SERD_XMIT_LAST:
        CLR.B   SV_WRPEND(A2)                   | no write in progress
        MOVE    (SP)+,SR                        | restore the interrupt level
| SERD_DONE_NOERR -- complete the request of the DCE in A1 with noErr.
SERD_DONE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        BRA     SERD_IODONE                     | -> IODone

| ----------------------------------------------------------
| SERD_TXREADY -- A3 = this channel's control register for writing; Z = 0
| if the transmit buffer is empty (RR0 bit 2, txBE). The first read resets
| the SCC's register pointer to RR0. Changes A3.
SERD_TXREADY:
        MOVE.L  (SCCRd).w,A3                    | A3 = SCC read base
        ADDA    SV_CHANOFS(A2),A3               | + channel offset: channel control (read)
        TST.B   (A3)                            | dummy read: register pointer -> 0
        MOVE    (SP),(SP)                       | delay between SCC accesses
        BTST    #txBE,(A3)                      | RR0 bit 2: transmit buffer empty?
        ADDA.L  #SCCWBase-SCCRBase,A3           | A3 = channel control (write); flags unchanged
        RTS                                     | Z = 0: buffer empty

| ----------------------------------------------------------
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

| ----------------------------------------------------------
| SERD_OUTHELD_NO -- output may go.
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
        BRA     SERD_XMIT                       | -> send the next character

| ----------------------------------------------------------
| SERD_TXINT_IDLE -- nothing to send: reset the Tx interrupt.
SERD_TXINT_IDLE:
        MOVE.B  #0x28,(A1)                      | WR0 = $28: reset Tx interrupt pending
        RTS                                     | return to the SCC dispatcher

| ----------------------------------------------------------
| SERD_CLRXOFF -- csCode 22, and XOn received: clear xOffHold.
| SERD_CHECKRESUME -- restart a pending write if output is no longer held
| (SerHShake, CTS change, XOn).
SERD_CLRXOFF:
        CLR.B   SV_XOFFHOLD(A2)                 | xOffHold = 0
SERD_CHECKRESUME:
        BSR.B   SERD_OUTHELD                    | output still held?
        BNE.B   SERD_CHECKRESUME_RTS            | yes -> nothing to do
        TST.B   SV_WRPEND(A2)                   | write in progress?
        BNE.B   SERD_TXRESUME                   | yes -> continue it
SERD_CHECKRESUME_RTS:
        RTS                                     | return from SERD_CHECKRESUME

| ----------------------------------------------------------
| E_AIn_Prime / E_BIn_Prime -- Read (Prime) of .AIn / .BIn.
| SERD_READ: pass characters from the input buffer to the read (JStash)
| until it is satisfied (-> IODone) or the buffer is empty; then rdPend is
| set and the receive interrupt delivers the rest. Ends input flow control
| when the buffer has drained. readErr if the port is not open.
E_AIn_Prime:
        MOVE.L  (SerialVars).w,A2               | A2 = port A SERDVars
        BRA.B   SERD_READ                       | -> common Read

| ----------------------------------------------------------
| E_BIn_Prime -- Read of .BIn (see E_AIn_Prime).
E_BIn_Prime:
        MOVE.L  (SerialVars+8).w,A2             | A2 = port B SERDVars
SERD_READ:
        MOVEQ.L #readErr,D0                     | readErr
        MOVE.L  A2,D1                           | port open?
        BLE     SERD_IODONE                     | no -> complete with readErr
        BSR.B   SERD_GETBUF                     | A3 = buffer, D3 = size, D2 = out index
SERD_READ_LOOP:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
        CMP     SV_INIDX(A2),D2                 | buffer empty?
        BEQ.B   SERD_READ_PEND                  | yes -> wait for characters
        MOVE.B  0x0(A3,D2.W),D0                 | D0 = next character
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
        BSR.B   SERD_INFLOW                     | end input flow control if drained
        BRA     SERD_DONE_NOERR                 | -> IODone, noErr

| ----------------------------------------------------------
| SERD_READ_PEND -- input buffer empty: the read waits (rdPend); return to
| the Device Manager after the flow-control check.
SERD_READ_PEND:
        ST.B    SV_RDPEND(A2)                   | rdPend: the receive code completes the read
        BRA.B   SERD_INFLOW_MASKED              | -> flow control check, SR already pushed

| ----------------------------------------------------------
| SERD_INFLOW -- with interrupts masked: if input flow control (fInX or
| fDTR) is on and at most SV_LOWMARK characters are left in the buffer,
| end it (SERD_RESUMEIN). SERD_INFLOW_MASKED: entry with SR pushed.
| Returns D0 = noErr.
SERD_INFLOW:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | mask interrupts
SERD_INFLOW_MASKED:
        TST     SV_FINX(A2)                     | fInX or fDTR set?
        BEQ.B   SERD_INFLOW_EXIT                | no -> done
        BSR.B   SERD_GETBUF                     | buffer state
        BSR.B   SERD_BUFCOUNT                   | D0 = characters in the buffer
        CMP     SV_LOWMARK(A2),D0               | at most the low mark?
        BHI.B   SERD_INFLOW_EXIT                | no -> keep the remote stopped
        BSR.B   SERD_RESUMEIN                   | assert DTR / send XOn
SERD_INFLOW_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return from the flow control check

| ----------------------------------------------------------
| SERD_STASH -- jump through JStash: Stash stores D0 into the buffer of the
| request of the DCE in A1 and returns D0 < 0 (N set) when it is full.
SERD_STASH:
        MOVE.L  (JStash).w,-(SP)                | push Stash's address
SERD_RESUMEIN_RTS:
        RTS                                     | jump to Stash (also an RTS for SERD_RESUMEIN)

| ----------------------------------------------------------
| SERD_GETBUF -- input buffer state: A3 = buffer, D3 = size, D1 = in index,
| D2 = out index.
| Called by: SERD_STATUS, SERD_READ, SERD_INFLOW, SERD_RXBUFFER
SERD_GETBUF:
        MOVE.L  SV_BUFPTR(A2),A3                | A3 = input buffer
        MOVE    SV_BUFSIZE(A2),D3               | D3 = its size
        MOVEM   SV_INIDX(A2),D1-D2              | D1 = in index, D2 = out index
        RTS                                     | return with the buffer state

| ----------------------------------------------------------
| SERD_BUFCOUNT -- D0 = number of characters in the input buffer (D1 - D2,
| plus the size D3 when the in index has wrapped).
SERD_BUFCOUNT:
        MOVE    D1,D0                           | in index
        SUB     D2,D0                           | - out index
        BCC.B   SERD_BUFCOUNT_RTS               | not wrapped ->
        ADD     D3,D0                           | + buffer size
SERD_BUFCOUNT_RTS:
        RTS                                     | D0 = characters in the buffer

| ----------------------------------------------------------
| SERD_RESUMEIN -- end input flow control: assert DTR again if fDTR is set
| and DTR was negated, send XOn if fInX is set and XOff was sent.
| SERD_SENDXONCOND -- csCode 23: send XOn if XOff was sent last.
SERD_RESUMEIN:
        TST.B   SV_FDTR(A2)                     | DTR flow control?
        BEQ.B   SERD_RESUMEIN_XON               | no -> XOn part
        BCLR    #0x6,SV_XOFFSENT(A2)            | DTR negated?
        BEQ.B   SERD_RESUMEIN_XON               | no -> XOn part
        BSR     SERD_SETDTR                     | assert DTR
SERD_RESUMEIN_XON:
        TST.B   SV_FINX(A2)                     | XOn/XOff input flow control?
        BEQ.B   SERD_RESUMEIN_RTS               | no -> done
SERD_SENDXONCOND:
        BCLR    #0x7,SV_XOFFSENT(A2)            | XOff sent last?
        BEQ.B   SERD_RESUMEIN_RTS               | no -> nothing to send
        MOVE.B  SV_XON(A2),D0                   | D0 = XOn character
| SERD_QUEUEFLOW -- send the flow-control character D0; if the opposite one
| is still waiting to be sent, the two cancel and neither is sent.
SERD_QUEUEFLOW:
        TST.B   SV_FLOWCHAR(A2)                 | a character still waiting?
        BEQ.B   SERD_SENDFLOW                   | no -> send this one
SERD_QUEUEFLOW_CLR:
        CLR.B   SV_FLOWCHAR(A2)                 | nothing waiting (sent or cancelled)
SERD_QUEUEFLOW_RTS:
        RTS                                     | return from SERD_QUEUEFLOW

| ----------------------------------------------------------
| SERD_SENDFLOW -- send the flow-control character D0 now if the transmit
| buffer is empty, else leave it in SV_FLOWCHAR for SERD_XMIT. Changes A3.
SERD_SENDFLOW:
        MOVE.B  D0,SV_FLOWCHAR(A2)              | waiting character
        BSR     SERD_TXREADY                    | transmit buffer empty?
        BEQ.B   SERD_QUEUEFLOW_RTS              | no -> sent before the next byte
        MOVE.B  D0,sccData(A3)                  | yes: send it now
        BRA.B   SERD_QUEUEFLOW_CLR              | -> no longer waiting

| ----------------------------------------------------------
| SERD_POLLPROC -- modem port (channel A) poll procedure (PollProc): the
| .Sony driver's EmptyPD calls it after a disk access with the bytes that
| its polling (_PollSCC) pushed on the stack, one per word below
| PollStack (A5 = VIA port A, A6 = SCC channel A data, from SetUpPoll).
| It passes them, oldest first, to the receive code, polling the SCC on.
| The return address is kept in PollRtnAddr ($128, MPW 1.0 Private.a;
| lowmem.inc calls it TwiggyVars).
SERD_POLLPROC:
        MOVE.L  (PollStack).w,A4                | A4 = PollStack: start of the poll data
        MOVE.L  (SP)+,(TwiggyVars).w            | PollRtnAddr = return address
| poll the SCC while processing the poll data
SERD_POLLPROC_POLL:
        TST.B   (A5)                            | VIA port A bit 7 (SCC W/REQ) = 0: byte waiting?
        BMI.B   SERD_POLLPROC_NEXT              | no ->
        MOVE.B  (A6),-(SP)                      | yes: push it (poll data)
        BRA.B   SERD_POLLPROC_POLL              | poll again

| ----------------------------------------------------------
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

| ----------------------------------------------------------
| SERD_POLLPROC_EXIT -- discard the poll data (SP = PollStack) and return
SERD_POLLPROC_EXIT:
        MOVE.L  (PollStack).w,SP                | SP = PollStack
        MOVE.L  (TwiggyVars).w,-(SP)            | push the saved return address (PollRtnAddr)
        RTS                                     | return (to EmptyPD)

| ----------------------------------------------------------
| SERD_RXINT_B / SERD_RXINT_A -- receive character available interrupt
| (Lvl2DT vRxB / vRxA; A0 = channel control, read). SERD_RXCHAR (also from
| SERD_POLLPROC) takes the character in D0 with A3 -> the port's two
| SerialVars longs: mask it to the data bits, replace a good character
| equal to the parity replacement character by the alternate, handle
| XOn/XOff (fXOn), then store it (SERD_RXSTORE).
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
        AND.B   SV_DATAMASK(A2),D0              | keep the data bits
        MOVE.B  SV_PECHAR(A2),D1                | D1 = parity replacement character
        BEQ.B   SERD_RXCHAR_FLOW                | none ->
        CMP.B   D1,D0                           | good character equal to it?
        BNE.B   SERD_RXCHAR_FLOW                | no ->
        MOVE.B  SV_PEALT(A2),D0                 | yes: the alternate character
SERD_RXCHAR_FLOW:
        TST.B   SV_FXON(A2)                     | XOn/XOff output flow control?
        BEQ.B   SERD_RXSTORE                    | no -> store the character
        CMP.B   SV_XON(A2),D0                   | XOn?
        BEQ     SERD_CLRXOFF                    | yes -> clear xOffHold, resume output
        CMP.B   SV_XOFF(A2),D0                  | XOff?
        BNE.B   SERD_RXSTORE                    | no -> store the character
        ST.B    SV_XOFFHOLD(A2)                 | xOffHold: output stops
        BRA.B   SERD_RXINT_RTS                  | (XOn/XOff are not stored)

| ----------------------------------------------------------
| SERD_RXSTORE -- give the character D0 to a waiting read (Stash; a full
| read completes with noErr) or put it into the input buffer.
SERD_RXSTORE:
        TST.B   SV_RDPEND(A2)                   | read waiting?
        BEQ.B   SERD_RXBUFFER                   | no -> input buffer
        MOVE.L  A3,A1                           | A1 = input DCE
        BSR     SERD_STASH                      | Stash: into the read's buffer
        BPL.B   SERD_RXINT_RTS                  | not full yet -> done
        CLR.B   SV_RDPEND(A2)                   | read satisfied
        BRA     SERD_DONE_NOERR                 | -> IODone, noErr

| ----------------------------------------------------------
| SERD_RXBUFFER -- put the character into the input buffer; a full buffer
| drops it (cumErrs swOverrunErr). When less than SV_HIMARK bytes are free
| and input flow control is on, negate DTR (fDTR) and/or send XOff (fInX).
| Bug: if DTR is already negated, the BNE after the BSET goes back to
| SERD_RXBUFFER_CHK with D3 = free space instead of the buffer size; when
| the in index has wrapped below the out index, SERD_BUFCOUNT then gives 0,
| D3 stays below SV_HIMARK and the receive interrupt loops forever (the
| SE driver has the same code).
SERD_RXBUFFER:
        BSR     SERD_GETBUF                     | A3 = buffer, D3 = size, D1/D2 = in/out index
        MOVE.B  D0,0x0(A3,D1.W)                 | store the character
        ADDQ.W  #0x1,D1                         | advance the in index
        CMP     D3,D1                           | past the end?
        BNE.B   SERD_RXBUFFER_CHK               | no ->
        MOVEQ.L #0x0,D1                         | wrap to 0
SERD_RXBUFFER_CHK:
        CMP     D2,D1                           | buffer full (in reaches out)?
        BNE.B   SERD_RXBUFFER_STORED            | no -> keep the character
        BSET    #0x0,SV_CUMERRS(A2)             | cumErrs: swOverrunErr
        BRA.B   SERD_RXINT_RTS                  | character lost

| ----------------------------------------------------------
| SERD_RXBUFFER_STORED -- the character is in; check input flow control.
SERD_RXBUFFER_STORED:
        MOVE    D1,SV_INIDX(A2)                 | store the in index
        TST     SV_FINX(A2)                     | fInX or fDTR set?
        BEQ.B   SERD_RXINT_RTS                  | no -> done
        BSR     SERD_BUFCOUNT                   | D0 = characters in the buffer
        SUB     D0,D3                           | D3 = free space
        CMP     SV_HIMARK(A2),D3                | less than the high mark free?
        BCC.B   SERD_RXINT_RTS                  | no -> done
        TST.B   SV_FDTR(A2)                     | DTR flow control?
        BEQ.B   SERD_SENDXOFFCOND               | no -> XOff
        BSET    #0x6,SV_XOFFSENT(A2)            | DTR already negated?
        BNE.B   SERD_RXBUFFER_CHK               | yes -> (bug, see above)
        BSR     SERD_CLRDTR                     | negate DTR
        TST.B   SV_FINX(A2)                     | XOn/XOff input flow control too?
        BEQ.B   SERD_RXINT_RTS                  | no -> done
| SERD_SENDXOFFCOND -- csCode 25, and input buffer nearly full: send XOff
| if XOn was sent last.
SERD_SENDXOFFCOND:
        BSET    #0x7,SV_XOFFSENT(A2)            | XOff already sent?
        BNE.B   SERD_RXINT_RTS                  | yes -> nothing to send
        MOVE.B  SV_XOFF(A2),D0                  | D0 = XOff character
        BSR     SERD_QUEUEFLOW                  | send it
| SERD_RXINT_RTS -- end of the receive code.
| Called by: SERD_RXCHAR_FLOW, SERD_RXSTORE, SERD_RXBUFFER_CHK,
| SERD_RXBUFFER_STORED, SERD_SENDXOFFCOND, SERD_SPINT_ABORT (8 branches)
SERD_RXINT_RTS:
        RTS                                     | return to the SCC dispatcher (or caller)

| ----------------------------------------------------------
| SERD_SPINT_B / SERD_SPINT_A -- special receive condition interrupt
| (Lvl2DT vSCB / vSCA; A0/A1 = channel control): parity error, receive
| overrun or framing error (RR1 bits 4-6). The errors are added to
| cumErrs; one that is in errs aborts a waiting read with rcvrErr (-89)
| and the character is dropped. Otherwise the character is stored, a
| parity error replaced by the replacement character if one is set.
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
        AND.B   SV_DATAMASK(A2),D0              | keep the data bits
        MOVE.B  SV_ERRS(A2),D2                  | D2 = errors that abort
        AND.B   D1,D2                           | that occurred
        MOVE.B  #0x30,(A1)                      | WR0 = $30: error reset
        AND.B   D3,D2                           | any?
        BNE.B   SERD_SPINT_ABORT                | yes -> abort the read
        MOVE.B  SV_PECHAR(A2),D3                | D3 = parity replacement character
        BEQ.B   SERD_SPINT_STORE                | none -> store the character
        CMP.B   D0,D3                           | character equal to it?
        BNE.B   SERD_SPINT_PARITY               | no ->
        MOVE.B  SV_PEALT(A2),D0                 | yes: the alternate character
SERD_SPINT_PARITY:
        BTST    #0x4,D1                         | parity error?
        BEQ.B   SERD_SPINT_STORE                | no -> store the character
        MOVE.B  D3,D0                           | yes: the replacement character
SERD_SPINT_STORE:
        BRA     SERD_RXSTORE                    | -> read or input buffer

| ----------------------------------------------------------
| SERD_SPINT_ABORT -- abort a waiting read with rcvrErr; drop the
| character.
SERD_SPINT_ABORT:
        TST.B   SV_RDPEND(A2)                   | read waiting?
        BEQ.B   SERD_RXINT_RTS                  | no -> just drop the character
        MOVEQ.L #-0x59,D0                       | rcvrErr (-89): SCC receiver error
| SERD_ABORTREAD -- complete the waiting read of the input DCE (A3) with
| the error in D0 (also breakRecd from SERD_EXTINT_BRKRECD).
SERD_ABORTREAD:
        MOVE.L  A3,A1                           | A1 = input DCE
        CLR.B   SV_RDPEND(A2)                   | no read waiting
        BRA     SERD_IODONE                     | -> IODone with the error

| ----------------------------------------------------------
| SERD_EXTINT_B / SERD_EXTINT_A -- ext/status interrupt of the channel
| (ExtStsDT vComIntB / vComIntA, called by the ROM's ext/status dispatcher
| for changes other than DCD alone; D0 = RR0, D1 = changed enabled bits,
| A0/A1 = channel control). Posts a driver event for changes in evts,
| handles break (bit 7) and CTS (bit 5): ctsHold follows the CTS bit;
| 80 or more interrupts within one tick are taken for an external clock
| on the handshake line and CTS interrupts are switched off (WR15 = $88).
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
        SMI.B   SV_CTSHOLD(A2)                  | ctsHold = $FF if CTS bit set
        CMPI    #0x50,SV_EXTCOUNT(A2)           | 80 interrupts within this tick?
        BCS.B   SERD_EXTINT_COUNT               | no ->
        MOVEQ.L #-0x78,D0                       | WR15 = $88: break and DCD only (CTS off)
        MOVEQ.L #0xF,D1                         | WR15
        BSR     SERD_WRITEREG                   | write it
SERD_EXTINT_COUNT:
        MOVE.L  (Ticks).w,D2                    | D2 = Ticks
        CMP.L   SV_EXTTICK(A2),D2               | same tick as the last interrupt?
        BEQ.B   SERD_EXTINT_INC                 | yes -> count on
        MOVE.L  D2,SV_EXTTICK(A2)               | new tick
        CLR     SV_EXTCOUNT(A2)                 | count from 0
SERD_EXTINT_INC:
        ADDQ.W  #0x1,SV_EXTCOUNT(A2)            | count this interrupt
        BRA     SERD_CHECKRESUME                | restart output if CTS released it

| ----------------------------------------------------------
| SERD_EXTINT_BREAK -- break/abort changed: at the start of a break
| (RR0 bit 7 set) abort a waiting read with breakRecd; at its end read
| and drop the null character the SCC receives.
SERD_EXTINT_BREAK:
        TST.B   D0                              | RR0 bit 7: break in progress?
        BMI.B   SERD_EXTINT_BRKRECD             | yes -> break received
        MOVE.B  sccData(A0),D0                  | end of break: drop the null character
        RTS                                     | return to the dispatcher

| ----------------------------------------------------------
| SERD_EXTINT_BRKRECD -- break received: abort a waiting read with
| breakRecd (-90) (cumErrs breakErr is not set by this driver).
SERD_EXTINT_BRKRECD:
        MOVEQ.L #-0x5A,D0                       | breakRecd (-90)
        TST.B   SV_RDPEND(A2)                   | read waiting?
        BNE.B   SERD_ABORTREAD                  | yes -> complete it with the error
        RTS                                     | return to the dispatcher
    ROM_RESOURCE_END SERD_0                     | end of the data: pads to even, sets the sizes

| end of resource : 'SERD' 0

