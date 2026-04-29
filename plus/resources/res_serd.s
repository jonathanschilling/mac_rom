| SERD 0 - Serial drivers (.AIn/.AOut/.BIn/.BOut)
|
| Contains 4 DRVR resources for the two SCC serial ports:
| .AIn (refNum -6): modem port input (SCC channel A)
| .AOut (refNum -7): modem port output (SCC channel A)
| .BIn (refNum -8): printer port input (SCC channel B)
| .BOut (refNum -9): printer port output (SCC channel B)
|
| SCC hardware: Zilog 8530, read at 0x9FFFF8, write at 0xBFFFF9
| Channel A = modem port, Channel B = printer port
| Mouse tracking also uses SCC DCD transitions for quadrature.
|
| Driver header layout per Inside Macintosh: Devices, Fig 1-6.
|
| Serial driver private storage (SERDVars), 0x8C bytes at (A2):
| 0x00 DCE pointer (from A1 at open time)
| 0x04 SCC register offset for this channel (0=B, 8=A)
| 0x06 receive buffer pointer
| 0x0A receive buffer size
| 0x0C XOff threshold (low water mark for flow control)
| 0x0E XOn threshold (high water mark - stop accepting)
| 0x10 CTS handshake flags (fCTS from SerShk)
| 0x11 DTR handshake enable (fDTR from SerShk)
| 0x12 XOn character
| 0x13 XOff character
| 0x14 error replace enable (fInX from SerShk)
| 0x15 event mask for ext status changes (evts from SerShk)
| 0x16 XOn/XOff flow control enable
| 0x17 previous XOn/XOff enable state
| 0x18 cumulative error bits (overrun|parity|framing in low; overflow bit 0)
| 0x1A read pending flag (set when waiting for data)
| 0x1B write in progress flag
| 0x1C CTS state (true = CTS asserted)
| 0x1D output stopped flag (XOFF received from remote)
| 0x1E WR5 shadow (DTR/RTS/break control, written to SCC)
| 0x1F WR5 value with DTR asserted
| 0x20 WR9 value (master interrupt control)
| 0x21-0x28 SCC write-register shadow array (WR1,WR3,WR4,WR5,WR10,WR11,WR12,WR13)
| 0x29 SCC channel ID byte (for WR9 reset addressing)
| 0x2A current SerConfig word
| 0x2C write head index (ring buffer)
| 0x2E read tail index (ring buffer)
| 0x30-0x6F default 64-byte receive ring buffer
| 0x70 DCD transition count (for break detection rate limit)
| 0x72 last DCD transition tick (Ticks value)
| 0x76 pending output character (flow control char to prepend)
| 0x77 data mask (0x1F/0x3F/0x7F/0xFF for 5/6/7/8 data bits)
| 0x78 XOn replace char (word: high=match, low=replacement)
| 0x79 XOn replace char with bit 7 cleared
| 0x7A saved flow control enable (backup of 0x16)
| 0x7B assert DTR on close flag (set by csCode 17 / kSERDAssertDTR)
| 0x7C-0x8B saved interrupt vectors (4 longs, restored on close)
|
| resource : 'SERD' 0
| Serial Drivers
SERD_CONT:
        BRA.B   SERD_SKIP                       | skip header data -> SERD loader
  .byte 0x00,0x00                               | flags: unused
  .ascii "SERD"                                 | resource type identifier
  .byte 0x00,0x00,0x00,0x02                     | resource ID = 0, version = 2
| SERD loader: install all 4 serial drivers into unit table
SERD_SKIP:
        PEA.L   Driver_BOut(PC)                 | push driver addresses (reversed order)
        PEA.L   Driver_BIn(PC)                  | so they pop as AIn, AOut, BIn, BOut
        PEA.L   Driver_AOut(PC)                 | push .AOut driver header address
        PEA.L   Driver_AIn(PC)                  | push .AIn driver header address
        MOVEQ.L #-0x6,D3                        | D3 = first refNum (-6 = .AIn)
| install loop: installs .AIn(-6), .AOut(-7), .BIn(-8), .BOut(-9)
SERD_NO:
        MOVE    D3,D0                           | D0 = refNum for DrvrInstall
        _DrvrInstallResrvMemA0Result            | allocate DCE -> A0 (handle)
        BSET    #0x7,(A0)                       | lock the DCE handle
        MOVE.L  (A0),A0                         | A0 = DCE (dereferenced)
        MOVE.L  (SP)+,A1                        | A1 = driver header (from stack)
        MOVE.L  A1,(A0)+                        | DCE.dCtlDriver = driver ptr
        MOVE    (A1),(A0)+                      | DCE.dCtlFlags = drvrFlags
        MOVE    #0x2,(A0)                       | DCE.dCtlQHdr.qFlags = 2 (queue active)
        SUBQ.W  #0x1,D3                         | next refNum
        CMPI    #-0x9,D3                        | done all 4?
        BGE.B   SERD_NO                         | no ->
        RTS                                     | all 4 drivers installed

| ----------------------------------------------------------
|
| Driver_A In
|
Driver_AIn:
  .short 0x4D00                                 | drvrFlags
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x0060                                 | drvrOpen
  .short 0x05B0                                 | drvrPrime
  .short 0x0340                                 | drvrCtl
  .short 0x02FA                                 | drvrStatus
  .short 0x02CC                                 | drvrClose
  .byte 0x04                                    | drvrName length

| Name
  .ascii ".AIn"                                 | drvrName: modem port input

| end of Name
  .byte 0x20                                    | align to word

Driver_AOut:
  .short 0x4E00                                 | drvrFlags
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x00A2                                 | drvrOpen
  .short 0x04DE                                 | drvrPrime
  .short 0x0328                                 | drvrCtl
  .short 0x02E2                                 | drvrStatus
  .short 0x024C                                 | drvrClose
  .byte 0x05                                    | drvrName length

| Name
  .ascii ".AOut"                                | drvrName: modem port output

| end of Name
Driver_BIn:
  .short 0x4D00                                 | drvrFlags
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x0038                                 | drvrOpen
  .short 0x0586                                 | drvrPrime
  .short 0x0316                                 | drvrCtl
  .short 0x02D0                                 | drvrStatus
  .short 0x029C                                 | drvrClose
  .byte 0x04                                    | drvrName length

| Name
  .ascii ".BIn"                                 | drvrName: printer port input

| end of Name
  .byte 0x20                                    | align to word

Driver_BOut:
  .short 0x4E00                                 | drvrFlags
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x00A0                                 | drvrOpen
  .short 0x04B4                                 | drvrPrime
  .short 0x02FE                                 | drvrCtl
  .short 0x02B8                                 | drvrStatus
  .short 0x0230                                 | drvrClose
  .byte 0x05                                    | drvrName length

| Name
  .ascii ".BOut"                                | drvrName: printer port output

| end of Name
| .AIn Open: open modem port input driver
E_AIn_Open:
        BSR.B   E_BIN_OPEN_CONT_2               | set up for channel A
        MOVE.L  A1,(SerialVars_a_dce).w         | save DCE for port A input
        BRA.B   E_BIN_OPEN_CONT                 | -> finish open

| ----------------------------------------------------------
|
| .BIn Open: open printer port input driver
|
E_BIn_Open:
        BSR.B   E_BIN_OPEN_CONT_3               | set up for channel B
        MOVE.L  A1,(ABusVars_dce).w             | save DCE for port B input
E_BIN_OPEN_CONT:
        MOVE.B  #0x2,0x7(A1)                    | DCE.dCtlFlags byte: set dRAMBased
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | input driver open complete

| ----------------------------------------------------------
|
| E_BIN_OPEN_CONT_2: set up register offsets for SCC channel A (modem port)
|
E_BIN_OPEN_CONT_2:
        MOVEQ.L #0x4,D1                         | SPConfig shift for port A (high nibble)
        MOVEQ.L #0x8,D2                         | SCC register offset for channel A
        BRA.B   E_BIN_OPEN_CONT_4               | -> check port config

| ----------------------------------------------------------
|
| E_BIN_OPEN_CONT_3: set up register offsets for SCC channel B (printer port)
|
E_BIN_OPEN_CONT_3:
        MOVEQ.L #0x0,D1                         | SPConfig shift for port B (low nibble)
        MOVEQ.L #0x0,D2                         | SCC register offset for channel B
| check if port is configured for serial (SPConfig)
E_BIN_OPEN_CONT_4:
        MOVE.B  (SPConfig).w,D0                 | PRAM port config byte
        LSR.B   D1,D0                           | shift to get this port's nibble
        ANDI.B  #0xF,D0                         | mask to 4 bits
        BEQ.B   E_BIN_OPEN_FOUND                | 0 = modem, ok ->
        SUBQ.B  #0x2,D0                         | 2 = printer, also ok ->
        BEQ.B   E_BIN_OPEN_FOUND                | match -> proceed to port-use check
        MOVEQ.L #-0x62,D0                       | portNotCf (-98): port not configured
E_BIN_OPEN_ERR:
        ADDQ.W  #0x4,SP                         | pop return address (skip caller)
        RTS                                     | return error in D0

| ----------------------------------------------------------
|
| E_BIN_OPEN_FOUND: check port-in-use status (PortAUse/PortBUse)
|
E_BIN_OPEN_FOUND:
        MOVE    (PortAUse).w,D0                 | load port use flags word
        ROR     D2,D0                           | rotate to get this channel's byte
        BCLR    #0x7,D0                         | test & clear "free" flag (bit 7)
        BNE.B   E_BIN_OPEN_OK                   | was free -> mark as serial
        EORI.B  #0x2,D0                         | check if already useAsync (2)
        BEQ.B   E_BIN_OPEN_OK_2                 | already open for serial -> ok
        MOVEQ.L #-0x61,D0                       | portInUse (-97): port in use
        BRA.B   E_BIN_OPEN_ERR                  | -> error exit

| ----------------------------------------------------------
|
| E_BIN_OPEN_OK: mark port as in use for async serial
|
E_BIN_OPEN_OK:
        MOVE.B  #0x2,D0                         | useAsync = 2
        ROR     D2,D0                           | rotate back to channel position
        MOVE    D0,(PortAUse).w                 | store updated port use flags
E_BIN_OPEN_OK_2:
        RTS                                     | port validated

| ----------------------------------------------------------
|
| E_A Out_Open: open modem port output driver
| Pushes interrupt vectors and params for shared open code
|
E_AOut_Open:
        BSR.B   E_BIN_OPEN_CONT_2               | validate port A config
        LEA.L   (SerialVars_a).w,A2             | A2 = ptr to port A vars pointer
        PEA.L   AOut_PollProc(PC)               | push poll proc address
        PEA.L   SCCInt_AInSpcl(PC)              | push special-condition ISR
        PEA.L   SCCInt_AInAvail(PC)             | push receive-available ISR
        PEA.L   SCCInt_AOutEmpty(PC)            | push transmit-empty ISR
        PEA.L   (Lvl2DT_4).w                    | push Lvl2 dispatch table slot (ch A)
        PEA.L   SCCInt_AChng_AOut(PC)           | push ext/status-change ISR
        PEA.L   (ExtStsDT_A).w                  | push ext status dispatch slot (ch A)
        MOVEQ.L #0x2,D1                         | SCC register pair offset (ch A = 2)
        MOVEQ.L #-0x9,D2                        | WR9 channel-A reset cmd (0xC0 | 0x09)
        MOVEQ.L #-0x7E,D3                       | WR9 value: MIE+DLC+NV (0x82 negated)
        MOVE    (SPPortA).w,D4                  | D4 = SerConfig from PRAM port A
        BRA.B   E_BOUT_OPEN_CONT                | -> shared output open

| ----------------------------------------------------------
|
| E_B Out_Open: open printer port output driver
|
E_BOut_Open:
        BSR.B   E_BIN_OPEN_CONT_3               | validate port B config
        LEA.L   (ABusVars).w,A2                 | A2 = ptr to port B vars pointer
        CLR.L   -(SP)                           | no poll proc for port B
        PEA.L   SCCInt_BInSpcl(PC)              | push special-condition ISR
        PEA.L   SCCInt_BInAvail(PC)             | push receive-available ISR
        PEA.L   SCCInt_BOutEmpty(PC)            | push transmit-empty ISR
        PEA.L   (Lvl2DT).w                      | push Lvl2 dispatch table slot (ch B)
        PEA.L   SCCInt_BChng_BOut(PC)           | push ext/status-change ISR
        PEA.L   (ExtStsDT).w                    | push ext status dispatch slot (ch B)
        MOVEQ.L #0x0,D1                         | SCC register pair offset (ch B = 0)
        MOVEQ.L #0x17,D2                        | WR9 value: channel-B reset (0x40|0x09) -- stored, not negated
        MOVEQ.L #0x42,D3                        | WR9: MIE+DLC (0x42) for ch B
        MOVE    (SPPortB).w,D4                  | D4 = SerConfig from PRAM port B
| Shared output driver open: allocate SERDVars, install ISRs, parse SerConfig
E_BOUT_OPEN_CONT:
        MOVEQ.L #0x46,D0                        | 0x46 = 70
        ADD.L   D0,D0                           | D0 = 0x8C = 140 bytes for SERDVars
        _ResrvMemSys                            | reserve space in system heap
        MOVEQ.L #0x46,D0                        | 0x46 = 70
        ADD.L   D0,D0                           | D0 = 0x8C bytes
        _NewHandleSysClear                      | allocate zeroed handle -> A0
        BEQ.B   E_BOUT_OPEN_CONT_2              | success -> continue
        ADDA    #0x1C,SP                        | error: discard 7 stacked longs
        RTS                                     | return MemErr in D0

| ----------------------------------------------------------
|
| E_BOUT_OPEN_CONT_2: SERDVars allocated - install vectors and configure SCC
|
E_BOUT_OPEN_CONT_2:
        MOVE.L  A0,0x14(A1)                     | DCE.dCtlStorage = handle to SERDVars
        MOVE.B  #0x2,0x7(A1)                    | DCE.dCtlFlags: set dRAMBased
        MOVE.L  (A0),(A2)                       | store dereferenced ptr in global
        BSET    #0x7,(A0)                       | lock the SERDVars handle
        MOVE.L  (A0),A2                         | A2 = SERDVars pointer
        LEA.L   0x7C(A2),A3                     | A3 = saved vector area in SERDVars
| Install interrupt vectors, saving old values for restore on close
        MOVE.L  (SP)+,A0                        | A0 = ExtStsDT slot address
        MOVE.L  (A0),(A3)+                      | save old ext status vector
        MOVE.L  (SP)+,(A0)                      | install new ext/status-change ISR
        MOVE.L  (SP)+,A0                        | A0 = Lvl2DT slot address
        MOVE.L  (A0),(A3)+                      | save old Lvl2 ext/status vector
        MOVE.L  (SP)+,(A0)+                     | install transmit-empty ISR in slot 0
        ADDQ.W  #0x4,A0                         | skip slot 1 (ext/status, already set)
        MOVE.L  (A0),(A3)+                      | save old Lvl2 receive vector
        MOVE.L  (SP)+,(A0)+                     | install receive-available ISR
        MOVE.L  (A0),(A3)+                      | save old Lvl2 special-cond vector
        MOVE.L  (SP)+,(A0)+                     | install special-condition ISR
        MOVE.L  (SP)+,D0                        | pop poll proc address (or NULL)
        BEQ.B   E_BOUT_OPEN_SKIP                | no poll proc -> skip
        MOVE.L  D0,(PollProc).w                 | install AOut poll procedure
E_BOUT_OPEN_SKIP:
        MOVE.L  A2,A3                           | A3 -> SERDVars base
        MOVE.L  A1,(A3)+                        | +0x00: store DCE pointer
        MOVE    D1,(A3)+                        | +0x04: SCC register pair offset
        BSR     E_BINOUT_CONTROL_CONT_5         | init default 64-byte receive buffer
        ST.B    0x14(A2)                        | +0x14: enable error replacement
        MOVE.B  D3,0x20(A2)                     | +0x20: WR9 shadow (master int ctrl)
        MOVE.B  D2,0x29(A2)                     | +0x29: channel ID for WR9 addressing
| Parse SerConfig word in D4 into SCC register shadows
E_BOUT_OPEN_CONT_3:
        MOVE    #-0x4000,D0                     | mask = 0xC000 (baud rate bits 15-14)
        AND     D4,D0                           | isolate baud rate selector
        BNE.B   E_BOUT_OPEN_EMPTY               | non-zero = valid baud rate bits
        MOVE    #-0x33F6,D4                     | default: 0xCC0A = 9600,8,N,1 + clk
E_BOUT_OPEN_EMPTY:
        MOVE    #0xC00,D0                       | mask bits 11-10: data bits selector
        AND     D4,D0                           | isolate data bits field
        ROL     #0x6,D0                         | rotate to byte index (0,2,4,6)
        MOVE.B  E_BOUT_OPEN_CONT_4(PC,D0.W),0x77(A2) | +0x77: set data mask from lookup
        LEA.L   0x21(A2),A3                     | A3 -> SCC register shadow array
        LEA.L   E_BOUT_OPEN_DECODE_TBL(PC),A4   | A4 -> config decode table
        MOVEQ.L #0x7,D0                         | 8 register shadows to compute
| Loop: extract each SCC register value from SerConfig via decode table
| Each entry: rotate count, AND mask, OR mask - applied to D4
E_BOUT_OPEN_LOOP:
        MOVE.B  (A4)+,D1                        | D1 = rotate count for this field
        MOVE    D4,D3                           | D3 = copy of SerConfig
        ROL     D1,D3                           | rotate field bits to low position
        AND.B   (A4)+,D3                        | mask to relevant bits
        OR.B    (A4)+,D3                        | OR in fixed bits for register
        MOVE.B  D3,(A3)+                        | store in shadow array
        DBF     D0,E_BOUT_OPEN_LOOP             | loop for all 8 registers
        MOVEQ.L #0x64,D1                        | mask 0x64: bits for WR3 auto-enables
        AND.B   (A3)+,D1                        | mask WR14 shadow (clock source)
        MOVE.B  D1,0x22(A2)                     | +0x22: store filtered WR3 value
        MOVE    D4,(A3)                         | +0x2A: store full SerConfig word
        MOVEQ.L #0x8,D0                         | WR5 base: Tx enable (bit 3)
        OR.B    0x24(A2),D0                     | OR in WR5 shadow (data bits, RTS)
        MOVE.B  D0,0x1F(A2)                     | +0x1F: WR5 with DTR asserted
        MOVE.B  0x28(A2),0x1E(A2)               | +0x1E: WR5 initial = shadow[7] (no DTR)
        BSR.B   E_BOUT_OPEN_CONT_5              | program SCC with full register set
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | output driver open complete

| ----------------------------------------------------------
|
| E_BOUT_OPEN_CONT_4: data mask lookup - indexed by data-bits field
| 5 bits=0x1F, 6 bits=0x7F(?), 7 bits=0x3F, 8 bits=0xFF
|
E_BOUT_OPEN_CONT_4:
  .byte  0x1F,0x7F,0x3F,0xFF                    | 5-bit=$1F, 6-bit=$7F, 7-bit=$3F, 8-bit=$FF
| E_BOUT_OPEN_DECODE_TBL: SerConfig decode table - 8 entries of (rotate, AND-mask, OR-value)
| Extracts SCC WR values from the 16-bit SerConfig word
E_BOUT_OPEN_DECODE_TBL:
  .byte  0x04,0x0F,0x40,0x00,0x00,0x00          | entry 0: rot=4, mask=$0F, OR=$40; entry 1: nop
  .byte 0x0C,0xC0,0x00,0x0B,0x60,0x02           | entry 2: rot=12, mask=$C0; entry 3: WR11 clk
  .byte 0x00,0xFF,0x00,0x08,0x03,0x00           | entry 4: pass-through; entry 5: WR3 Rx bits
  .byte 0x0C,0xC0,0x01,0x0B,0x60,0x8A           | entry 6: stop bits; entry 7: WR11 DPLL
| REGISTER_TBL: SCC full initialization register sequence
| Pairs of (register, value) - 0xFF means "use shadow array value"
| Programs WR2,WR9,WR4,WR1,WR3,WR5,WR10,WR11,WR12,WR13,WR14,WR15,WR1,WR9
REGISTER_TBL:
  .byte  0x02,0x09,0x04,0xFF,0x01,0xFF          | WR2=intVec, WR9=MIE, WR4=shadow, WR1=shadow
  .byte 0x03,0xFF,0x05,0xFF,0x00,0x02           | WR3=shadow, WR5=shadow, WR0 reset, WR10=$50
  .byte 0x00,0x0A,0x50,0x0B,0x0C,0xFF           | WR10=NRZ, WR11=clk, WR12=shadow baud lo
  .byte 0x0D,0xFF,0x03,0xFF,0x05,0xFF           | WR13=shadow baud hi, WR3=en, WR5=en
  .byte 0x01,0x0E,0xA8,0x0F,0x10,0x00           | WR1=shadow, WR14=BRG, WR15=DCD, WR16=0
  .byte 0x10,0x00,0x01,0xFF,0x0A,0x09           | WR16=0, WR1=Rx int, WR10=NRZ, WR9=MIE
| RETURNS_10: load SCC read/write base addresses adjusted for this channel
| Returns: A0 = SCC read control, A1 = SCC write control
RETURNS_10:
        MOVEM.L (SCCRd).w,A0-A1                 | A0=SCCRd base, A1=SCCWr base
        ADDA    0x4(A2),A0                      | add channel offset to read base
        ADDA    0x4(A2),A1                      | add channel offset to write base
        RTS                                     | A0/A1 = channel-specific SCC addrs

| ----------------------------------------------------------
|
| E_BOUT_OPEN_CONT_5: program SCC with full register init sequence (REGISTER_TBL)
|
E_BOUT_OPEN_CONT_5:
        LEA.L   REGISTER_TBL(PC),A3             | A3 -> full init register table
        MOVEQ.L #0x24,D1                        | 36 bytes = 18 register pairs
| FORMAT: write D1/2 bytes of SCC register pairs from table at A3
| Format: high byte = register number, low byte = value (0xFF = use shadow)
FORMAT:
        MOVE    SR,-(SP)                        | save status register
        MOVEM.L A0-A2,-(SP)                     | save work registers
        BSR.B   RETURNS_10                      | get SCC read/write addresses
        ORI     #0x300,SR                       | disable interrupts (IPL=3)
        MOVE.B  (A0),D2                         | read SCC RR0 to reset register ptr
        LEA.L   0x21(A2),A2                     | A2 -> SCC register shadow array
| Loop: write register pairs to SCC
E_BOUT_OPEN_LOOP_2:
        MOVE    (A3)+,D0                        | D0 = next (reg, value) pair
        TST.B   D0                              | high byte negative?
        BPL.B   E_BOUT_OPEN_NO                  | no -> use value from table
        MOVE.B  (A2)+,D0                        | yes (0xFF): substitute shadow value
        ROR     #0x8,D0                         | swap reg number back to high byte
E_BOUT_OPEN_NO:
        MOVE.B  D0,(A1)                         | write register number to SCC
        ROR     #0x8,D0                         | rotate value to low byte
        MOVE.L  (SP),(SP)                       | delay for SCC register access timing
        MOVE.B  D0,(A1)                         | write register value to SCC
        SUBQ.W  #0x2,D1                         | count down 2 bytes per pair
        BGT.B   E_BOUT_OPEN_LOOP_2              | more pairs -> loop
        NOP                                     | timing delay after last write
        MOVE.B  (A0),D2                         | read RR0 to latch current status
        MOVEM.L (SP)+,A0-A2                     | restore registers
        LSL.B   #0x2,D2                         | shift RR0 bit 5 (CTS) to bit 7
        SMI.B   0x1C(A2)                        | +0x1C: set CTS state (FF=asserted)
        MOVE    (SP)+,SR                        | restore interrupts
        RTS                                     | SCC register programming done

| ----------------------------------------------------------
|
| E_BOUT_OPEN_CONT_6: SCC close/reset register sequence
| Disables interrupts and resets channel to idle state
|
E_BOUT_OPEN_CONT_6:
  .byte  0x02,0x09,0x04,0xFF,0x01,0xFF          | WR2=intVec, WR9=MIE, WR4=shadow, WR1=shadow
  .byte 0x03,0xFF,0x05,0xFF,0x08,0x0F           | WR3=disable, WR5=disable, WR8=$0F Tx data
  .byte 0x01,0x01,0x0A,0x09                     | WR1=ext int only, WR10=NRZ, WR9=MIE

| .AOut Close: close modem port output driver
E_AOut_Close:
        CLR.L   (PollProc).w                    | remove poll procedure
        LEA.L   (Lvl2DT_4).w,A4                 | A4 = Lvl2 dispatch table (ch A)
        LEA.L   (ExtStsDT_A).w,A5               | A5 = ext status table (ch A)
        LEA.L   (SerialVars_a).w,A6             | A6 = port A vars global
        MOVEQ.L #0x8,D3                         | D3 = 8: rotate count for ch A position
        BRA.B   E_BOUT_CLOSE_CONT               | -> shared close

| ----------------------------------------------------------
|
| E_B Out_Close: close printer port output driver
|
E_BOut_Close:
        LEA.L   (Lvl2DT).w,A4                   | A4 = Lvl2 dispatch table (ch B)
        LEA.L   (ExtStsDT).w,A5                 | A5 = ext status table (ch B)
        LEA.L   (ABusVars).w,A6                 | A6 = port B vars global
        MOVEQ.L #0x0,D3                         | D3 = 0: no rotate for ch B position
| Shared output driver close
E_BOUT_CLOSE_CONT:
        MOVE.L  (A6),A2                         | A2 = SERDVars pointer
        TST.B   0x7B(A2)                        | +0x7B: assert DTR on close?
        BPL.B   E_BOUT_CLOSE_SKIP               | no -> skip DTR assertion
        MOVEQ.L #-0x9,D0                        | mask 0xF7: clear break bit (bit 3)
        AND.B   0x1E(A2),D0                     | mask current WR5 shadow
        MOVE.B  D0,0x24(A2)                     | store as WR5 shadow (no break, keep DTR)
E_BOUT_CLOSE_SKIP:
        BSR.B   E_ABIN_CLOSE_CONT               | drain transmit buffer
        LEA.L   E_BOUT_OPEN_CONT_6(PC),A3       | A3 -> close register sequence
        MOVEQ.L #0x10,D1                        | 16 bytes = 8 register pairs
        BSR     FORMAT                          | write close sequence to SCC
| Restore saved interrupt vectors
        LEA.L   0x7C(A2),A3                     | A3 -> saved vectors in SERDVars
        MOVE.L  (A3)+,(A5)                      | restore ext status vector
        MOVE.L  (A3)+,(A4)+                     | restore Lvl2 transmit-empty vector
        ADDQ.L  #0x4,A4                         | skip ext/status slot
        MOVE.L  (A3)+,(A4)+                     | restore Lvl2 receive vector
        MOVE.L  (A3),(A4)                       | restore Lvl2 special-cond vector
        MOVE.L  0x14(A1),A0                     | A0 = DCE.dCtlStorage handle
        _DisposeHandle                          | free SERDVars
        CLR.L   0x14(A1)                        | clear DCE.dCtlStorage
        CLR.L   (A6)                            | clear port vars global
        MOVE    (PortAUse).w,D0                 | load port use flags
        ROR     D3,D0                           | rotate to this channel's byte
        ST.B    D0                              | mark as free (0xFF = useFree)
        ROR     D3,D0                           | rotate back to original position
        MOVE    D0,(PortAUse).w                 | store updated flags
| .AIn/.BIn Close: input drivers have no private storage to free
E_ABIn_Close:
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | input close is a no-op

| ----------------------------------------------------------
|
| E_ABIN_CLOSE_CONT: drain SCC transmit buffer - poll until all chars sent
|
E_ABIN_CLOSE_CONT:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save registers
        BSR     RETURNS_10                      | get SCC read/write for channel
        MOVEQ.L #-0x1,D1                        | D1 = loop counter (max iterations)
E_ABIN_CLOSE_LOOP:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts
        MOVE.B  (A0),D0                         | read RR0
        MOVE.L  (SP),(SP)                       | SCC access delay
        MOVE.B  #0x1,(A1)                       | select WR1 (point to RR1)
        MOVE.L  (SP),(SP)                       | SCC access delay
        MOVE.B  (A0),D0                         | read RR1 (Tx status)
        MOVE    (SP)+,SR                        | restore interrupts
        LSR.B   #0x1,D0                         | shift "all sent" bit to carry
        DBCS    D1,E_ABIN_CLOSE_LOOP            | loop until all-sent or timeout
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore registers
        RTS                                     | Tx buffer drained

| ----------------------------------------------------------
|
| E_A In Out_Status: status call for modem port
|
E_AInOut_Status:
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A SERDVars
        BRA.B   E_BINOUT_STATUS_CONT            | -> shared status handler

| ----------------------------------------------------------
|
| E_B In Out_Status: status call for printer port
|
E_BInOut_Status:
        MOVE.L  (ABusVars).w,A2                 | A2 = port B SERDVars
| Shared Status handler - dispatches SerGetBuf (csCode 2) and SerStatus (csCode 8)
E_BINOUT_STATUS_CONT:
        MOVE    0x6(A0),-(SP)                   | save ioTrap word
        MOVE.L  A1,-(SP)                        | save DCE pointer
        MOVE    SR,-(SP)                        | save status register
        ORI     #0x300,SR                       | disable interrupts
        LEA.L   0x1A(A0),A0                     | A0 -> csParam area of param block
        MOVEQ.L #-0x12,D0                       | default error: statusErr (-18)
        MOVE.L  A2,D1                           | test if SERDVars allocated
        BLE.B   E_BINOUT_CONTROL_ERR            | NULL -> error exit
        MOVE    (A0)+,D1                        | D1 = csCode
        SUBQ.W  #0x2,D1                         | csCode 2 = SerGetBuf?
        BNE.B   E_BINOUT_STATUS_NEXT            | no -> try next
| SerGetBuf: return bytes available in receive buffer
        BSR     RETURNS_13                      | load ring buffer state
        BSR     RETURNS_14                      | D0 = bytes in buffer
        CLR     (A0)+                           | clear high word of count
        MOVE    D0,(A0)                         | store byte count in csParam
        BRA.B   E_BINOUT_CONTROL_EXIT_2         | -> success exit

| ----------------------------------------------------------
|
| E_BINOUT_STATUS_NEXT: check for csCode 8 (SerStatus)
|
E_BINOUT_STATUS_NEXT:
        SUBQ.W  #0x6,D1                         | csCode 8 (after -2-6)?
        BNE.B   E_BINOUT_CONTROL_ERR            | no -> statusErr
| SerStatus: return cumulative errors and status
        MOVE    0x18(A2),(A0)+                  | copy cumErr word to csParam
        CLR.B   0x18(A2)                        | clear cumulative errors
        MOVE.L  0x1A(A2),(A0)+                  | copy status longs (rdPend, wrProg, etc)
        BRA.B   E_BINOUT_CONTROL_EXIT_2         | -> success exit

| ----------------------------------------------------------
|
| E_A In Out_Control: control call for modem port
|
E_AInOut_Control:
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A SERDVars
        BRA.B   E_BINOUT_CONTROL_CONT           | -> shared control handler

| ----------------------------------------------------------
|
| E_B In Out_Control: control call for printer port
|
E_BInOut_Control:
        MOVE.L  (ABusVars).w,A2                 | A2 = port B SERDVars
| Shared Control handler - dispatches csCode 1 (KillIO) or 8-27 via jump table
E_BINOUT_CONTROL_CONT:
        MOVE    0x6(A0),-(SP)                   | save ioTrap word
        MOVE.L  A1,-(SP)                        | save DCE pointer
        MOVE    SR,-(SP)                        | save status register
        ORI     #0x300,SR                       | disable interrupts
        LEA.L   0x1A(A0),A0                     | A0 -> csParam area
        MOVE    (A0)+,D1                        | D1 = csCode
        SUBQ.W  #0x1,D1                         | csCode 1 = KillIO?
        BNE.B   E_BINOUT_CONTROL_NO             | no -> dispatch table
| KillIO: abort pending read and reset buffer
        MOVE.L  A2,D2                           | test if SERDVars allocated
        BLE.B   E_BINOUT_CONTROL_EXIT           | NULL -> just return
        CLR     0x1A(A2)                        | clear read pending flag
        CLR.L   0x2C(A2)                        | reset write/read indices to 0
E_BINOUT_CONTROL_EXIT:
        MOVE    (SP)+,SR                        | restore interrupts
        ADDQ.W  #0x6,SP                         | discard saved DCE + ioTrap
        RTS                                     | KillIO complete (synchronous return)

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_NO: dispatch control csCodes 8-27 via jump table E_BINOUT_CONTROL_DISPATCH_TBL
|
E_BINOUT_CONTROL_NO:
        MOVE.L  A2,D2                           | test if SERDVars allocated
        BLE.B   E_BINOUT_CONTROL_EMPTY          | NULL -> controlErr
        LEA.L   E_BINOUT_CONTROL_DISPATCH_TBL(PC),A1 | A1 -> control dispatch table
        SUBQ.W  #0x7,D1                         | normalize: csCode 8 -> index 0
        BMI.B   E_BINOUT_CONTROL_EMPTY          | csCode < 8 -> controlErr
        CMPI    #0x13,D1                        | max index 19 (csCode 27)
        BHI.B   E_BINOUT_CONTROL_EMPTY          | csCode > 27 -> controlErr
        ADD     D1,D1                           | word index -> byte offset
        MOVE    0x0(A1,D1.W),D1                 | load relative offset from table
        MOVE.B  0x28(A2),D0                     | D0 = WR5 shadow (used by some handlers)
        JSR     0x0(A1,D1.W)                    | jump to control handler
| Common success exit for Status and Control
E_BINOUT_CONTROL_EXIT_2:
        MOVEQ.L #0x0,D0                         | noErr
| Common exit: restore SR, DCE, check if async
E_BINOUT_CONTROL_ERR:
        MOVE    (SP)+,SR                        | restore interrupts
        MOVE.L  (SP)+,A1                        | restore DCE pointer
        BTST    #0x9,(SP)+                      | test noQueueBit in saved ioTrap
        BEQ.B   E_BINOUT_CONTROL_ERR_2          | not set -> async, call IODone
        RTS                                     | synchronous -> return directly

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_ERR_2: call IODone via vector (async completion)
|
E_BINOUT_CONTROL_ERR_2:
        MOVE.L  (JIODone).w,-(SP)               | push JIODone vector
        RTS                                     | jump to IODone

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_2: unimplemented control code handler
|
E_BINOUT_CONTROL_CONT_2:
        ADDQ.W  #0x4,SP                         | discard return address from JSR
E_BINOUT_CONTROL_EMPTY:
        MOVEQ.L #-0x11,D0                       | controlErr (-17)
        BRA.B   E_BINOUT_CONTROL_ERR            | -> common exit

| Control dispatch jump table (csCodes 8-27, 20 entries)
| csCode 8 = SerReset csCode 9 = SerSetBuf
| csCode 10 = SerHShake csCode 11 = SerHShake (alt)
| csCode 12 = SerSetBreak csCode 13 = kSERDSetMIDI
| csCode 14 = SerClrBreak csCode 15 = (unimplemented)
| csCode 16 = SetBaud csCode 17 = kSERDAssertDTR
| csCode 18 = kSERDNegDTR csCode 19 = clearXOff
| csCode 20 = sendXOff csCode 21-27 = extended
E_BINOUT_CONTROL_DISPATCH_TBL:
  .byte  0x00,0x28,0x00,0x34,0x00,0x5A          | cs8=SerReset+40, cs9=SerSetBuf+52, cs10=SerHShake+90
  .byte 0x00,0xC6,0x00,0xB6,0x00,0xD4           | cs11=SerHShake+198, cs12=SetBreak+182, cs13=SetMIDI+212
  .byte 0x00,0x54,0xFF,0xFA,0x00,0x94           | cs14=ClrBreak+84, cs15=unimpl-6, cs16=SetBaud+148
  .byte 0x00,0xA6,0x00,0x9A,0x01,0x3A           | cs17=AssertDTR+166, cs18=NegDTR+154, cs19=ClrXOff+314
  .byte 0x01,0x34,0x01,0x02,0x01,0xF4           | cs20=SendXOff+308, cs21=+258, cs22=+500
  .byte 0x02,0x9E,0x01,0x08,0x03,0x9A           | cs23=+670, cs24=+264, cs25=+922
  .byte 0x01,0x1C,0x01,0x2C                     | cs26=+284, cs27=+300
| E_BINOUT_CONTROL_CONT_3: csCode 8 - SerReset: reconfigure SCC with new SerConfig
E_BINOUT_CONTROL_CONT_3:
        MOVE    (A0)+,D4                        | D4 = new SerConfig word from csParam
        CMP     0x2A(A2),D4                     | same as current config?
        BEQ.B   E_BINOUT_CONTROL_OK             | yes -> nothing to do
        BRA     E_BOUT_OPEN_CONT_3              | -> reparse SerConfig and reprogram SCC

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_4: csCode 9 - SerSetBuf: set custom receive buffer
|
E_BINOUT_CONTROL_CONT_4:
        CLR.L   0x2C(A2)                        | reset write/read ring buffer indices
        MOVE.L  (A0)+,A4                        | A4 = new buffer pointer from csParam
        MOVE    (A0),D1                         | D1 = new buffer size
        BNE.B   E_BINOUT_CONTROL_EMPTY_2        | non-zero -> use custom buffer
| E_BINOUT_CONTROL_CONT_5: set default 64-byte internal receive buffer
E_BINOUT_CONTROL_CONT_5:
        LEA.L   0x30(A2),A4                     | A4 -> default buffer at +0x30
        MOVEQ.L #0x40,D1                        | 64 bytes default size
E_BINOUT_CONTROL_EMPTY_2:
        LEA.L   0x6(A2),A3                      | A3 -> buffer descriptor fields
        MOVE.L  A4,(A3)+                        | +0x06: buffer pointer
        MOVE    D1,(A3)+                        | +0x0A: buffer size
        LSR     #0x2,D1                         | D1 = size/4 (quarter-full threshold)
        MOVE    D1,(A3)+                        | +0x0C: XOff threshold (low water)
        MOVE    D1,(A3)+                        | +0x0E: XOn threshold (high water)
E_BINOUT_CONTROL_OK:
        RTS                                     | buffer configured

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_6: csCode 10 - SerHShake: set handshake options (from csParam byte)
| csParam+7 contains the fInX flags byte
|
E_BINOUT_CONTROL_CONT_6:
        MOVE.B  0x7(A0),-(SP)                   | save fInX value from csParam
        BRA.B   E_BINOUT_CONTROL_CONT_8         | -> shared handshake setup

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_7: csCode 11 - SerHShake (from SerShk record in csParam)
| Uses current saved XOn/XOff state
|
E_BINOUT_CONTROL_CONT_7:
        MOVE.B  0x17(A2),-(SP)                  | save current XOn/XOff enable state
E_BINOUT_CONTROL_CONT_8:
        TST.B   0x10(A2)                        | was CTS handshake previously enabled?
        BNE.B   E_BINOUT_CONTROL_SKIP           | yes -> skip clearing XOFF-received
        CLR.B   0x1D(A2)                        | clear output-stopped flag
E_BINOUT_CONTROL_SKIP:
        MOVE.L  (A0)+,0x10(A2)                  | +0x10: copy SerShk fCTS/fDTR/fXOn/fInX
        MOVE    (A0)+,0x14(A2)                  | +0x14: copy errs and evts bytes
        MOVE.B  (A0)+,D0                        | D0 = fXOn (XOn/XOff enable flag)
        MOVE.B  D0,0x16(A2)                     | +0x16: store XOn/XOff enable
        MOVE.B  D0,0x7A(A2)                     | +0x7A: save backup copy
        BNE.B   E_BINOUT_CONTROL_SKIP_2         | if enabled -> skip
        BSR     E_BIN_PRIME_CONT_6              | disable XOff: clear software flow ctrl
E_BINOUT_CONTROL_SKIP_2:
        BSR     SCCINT_AOUTEMPTY_CONT           | check if transmit should resume
        MOVE.B  (SP)+,D0                        | restore previous XOn/XOff state
        CMP.B   0x17(A2),D0                     | did XOn char change?
        BEQ.B   E_BINOUT_CONTROL_DONE           | no change -> done
        MOVE.B  D0,0x17(A2)                     | +0x17: update previous state
        BEQ.B   E_BINOUT_CONTROL_OK_2           | was disabled -> deassert DTR
E_BINOUT_CONTROL_DONE:
        RTS                                     | handshake options applied

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_9: csCode 17 - kSERDAssertDTR: set "assert DTR on close"
|
E_BINOUT_CONTROL_CONT_9:
        MOVE.B  (A0),0x7B(A2)                   | +0x7B: store DTR-on-close flag
        RTS                                     | DTR-on-close flag set

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_10: csCode 18 - kSERDNegDTR: assert DTR (raise DTR line)
| Sets WR5 to include DTR bit, updates output flags
|
E_BINOUT_CONTROL_CONT_10:
        MOVE.B  0x1F(A2),D0                     | D0 = WR5 value with DTR asserted
        BSET    #0x6,0x19(A2)                   | set "DTR asserted" flag in flow state
        BRA.B   E_BINOUT_CONTROL_CONT_11        | -> write WR5 to SCC

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_OK_2: deassert DTR (lower DTR line)
|
E_BINOUT_CONTROL_OK_2:
        MOVE.B  0x28(A2),D0                     | D0 = WR5 shadow without DTR
        BCLR    #0x6,0x19(A2)                   | clear "DTR asserted" flag
| Write WR5 value to SCC (DTR/RTS/break control)
E_BINOUT_CONTROL_CONT_11:
        MOVE.B  D0,0x1E(A2)                     | +0x1E: update WR5 shadow
        BRA.B   E_BINOUT_CONTROL_CONT_13        | -> write WR5 via RETURNS_11

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_12: csCode 12 - SerSetBreak: assert break on serial line
| Sets the "send break" bit in WR5 and writes it
|
E_BINOUT_CONTROL_CONT_12:
        MOVE    0x4(SP),SR                      | restore caller's SR (re-enable ints)
        BSR     E_ABIN_CLOSE_CONT               | drain transmit buffer first
        ORI     #0x300,SR                       | disable interrupts again
        BSET    #0x4,D0                         | set WR5 bit 4 = send break
| Write SCC WR5 register with value in D0
E_BINOUT_CONTROL_CONT_13:
        MOVEQ.L #0x5,D1                         | WR5 register number
| E_BINOUT_CONTROL_CONT_14: write SCC write-register D1 with value D0
E_BINOUT_CONTROL_CONT_14:
        BSR     RETURNS_11                      | get SCC write address -> A3
        MOVE.B  D1,(A3)                         | select write register D1
        MOVE.L  (SP),(SP)                       | SCC access timing delay
        MOVE.B  D0,(A3)                         | write value D0 to selected register
        RTS                                     | SCC register written

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_15: csCode 16 - SetBaud: set baud rate from explicit divisor
| csParam contains desired baud rate; computes BRG time constant
| SCC baud rate = 3,672,000 / (2 * (TC + 2)) [with x16 clock mode]
|
E_BINOUT_CONTROL_CONT_15:
        MOVE.L  #0x1C015,D2                     | D2 = 115733 (Mac clock / 32 rounded)
        MOVE.L  D2,D3                           | D3 = copy for actual baud calc
        MOVEQ.L #0x0,D0                         | clear high word
        MOVE    (A0),D0                         | D0 = desired baud rate
        MOVE.L  D0,D1                           | D1 = baud rate
        LSR     #0x1,D1                         | D1 = baud/2 (for rounding)
        ADD.L   D1,D2                           | D2 = 115733 + baud/2
        DIVU    D0,D2                           | D2 = (115733 + baud/2) / baud = TC+2
        MOVE    D2,D1                           | D1 = TC+2 (for actual baud calc)
        SUBQ.W  #0x2,D2                         | D2 = time constant
        MOVE.B  D2,0x25(A2)                     | +0x25: WR12 shadow = TC low byte
        LSR     #0x8,D2                         | shift high byte
        MOVE.B  D2,0x26(A2)                     | +0x26: WR13 shadow = TC high byte
        DIVU    D1,D3                           | D3 = 115733 / (TC+2) = actual baud
        MOVE    D3,(A0)                         | return actual baud rate in csParam
        CLR     0x2A(A2)                        | clear SerConfig (custom baud mode)
        BRA     E_BOUT_OPEN_CONT_5              | reprogram SCC registers

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_16: csCode 13 - kSERDSetMIDI: stop output (XOFF state)
|
E_BINOUT_CONTROL_CONT_16:
        ST.B    0x1D(A2)                        | +0x1D: set output-stopped flag
        RTS                                     | output halted

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_17: csCode 19 - clear XOFF state, resume output with XOn
|
E_BINOUT_CONTROL_CONT_17:
        BClr    #0x7,0x19(A2)                   | clear "XOFF sent" flag
        MOVE.B  0x7A(A2),0x16(A2)               | restore XOn/XOff enable from backup
        MOVE.B  0x12(A2),D0                     | D0 = XOn character
E_BINOUT_CONTROL_CONT_18:
        BRA     E_BIN_PRIME_NO_2                | -> queue char for transmission

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_19: csCode 20 - send XOFF to remote, suspend input flow
|
E_BINOUT_CONTROL_CONT_19:
        BSet    #0x7,0x19(A2)                   | set "XOFF sent" flag
        CLR.B   0x16(A2)                        | disable XOn/XOff (manual control now)
        MOVE.B  0x13(A2),D0                     | D0 = XOff character
        BRA.B   E_BINOUT_CONTROL_CONT_18        | -> queue XOff for transmission

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_20: csCode 14 - SerClrBreak: deassert break on serial line
| Writes WR9 (master interrupt control) to clear break state
|
E_BINOUT_CONTROL_CONT_20:
        MOVE.B  0x20(A2),D0                     | D0 = WR9 shadow value
        MOVEQ.L #0x9,D1                         | WR9 register number
        BRA.B   E_BINOUT_CONTROL_CONT_14        | -> write register

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_21: csCode 21 - kSERDSetPEChar: set parity error replace char (word)
|
E_BINOUT_CONTROL_CONT_21:
        MOVE    (A0),0x78(A2)                   | +0x78: store replace char word
        RTS                                     | replace char set

| ----------------------------------------------------------
|
| E_BINOUT_CONTROL_CONT_22: csCode 22 - kSERDSetPEAlt: set parity error char with mask
|
E_BINOUT_CONTROL_CONT_22:
        MOVE.B  (A0),0x78(A2)                   | +0x78: store match character
        MOVE.B  (A0),0x79(A2)                   | +0x79: store replacement character
        BCLR    #0x7,0x79(A2)                   | clear bit 7 of replacement (strip parity)
        RTS                                     | alternate replace char set

| ----------------------------------------------------------
|
| E_A Out_Prime: .AOut Write - polled transmit for modem port
|
E_AOut_Prime:
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A SERDVars
        BRA.B   E_BOUT_PRIME_CONT               | -> shared write handler

| ----------------------------------------------------------
|
| E_B Out_Prime: .BOut Write - polled transmit for printer port
|
E_BOut_Prime:
        MOVE.L  (ABusVars).w,A2                 | A2 = port B SERDVars
| Shared Write handler: transmit bytes from ioBuffer via polled output
E_BOUT_PRIME_CONT:
        MOVE    SR,-(SP)                        | save status register
        ORI     #0x300,SR                       | disable interrupts
        ST.B    0x1B(A2)                        | +0x1B: mark write in progress
        BSR.B   RETURNS_12                      | check if output blocked (CTS/XOFF)
        BNE.B   E_BOUT_PRIME_EXIT               | blocked -> exit, ISR will resume
| Transmit loop: send chars while SCC Tx buffer has room
E_BOUT_PRIME_LOOP:
        BSR.B   RETURNS_11                      | check SCC Tx buffer empty (Z flag)
        BEQ.B   E_BOUT_PRIME_EXIT               | Tx not ready -> done for now
        MOVE.B  0x76(A2),D0                     | D0 = pending flow control char
        CLR.B   0x76(A2)                        | clear pending char
        ANDI    #0xFF,D0                        | mask to byte, set flags
        BNE.B   E_BOUT_PRIME_CONT_2             | have pending char -> send it
        MOVE.L  (JFetch).w,A0                   | A0 = JFetch vector (get next byte)
        JSR     (A0)                            | D0 = next byte from ioBuffer
E_BOUT_PRIME_CONT_2:
        MOVE.B  D0,0x4(A3)                      | write byte to SCC data register
        TST     D0                              | check if JFetch returned negative
        BMI.B   E_BOUT_PRIME_CONT_3             | negative = buffer exhausted
E_BOUT_PRIME_EXIT:
        MOVEQ.L #0x0,D0                         | noErr (more to send or blocked)
        MOVE    (SP)+,SR                        | restore interrupts
        RTS                                     | return to Device Mgr (write pending)

| ----------------------------------------------------------
|
| E_BOUT_PRIME_CONT_3: write complete - all bytes transmitted
|
E_BOUT_PRIME_CONT_3:
        CLR.B   0x1B(A2)                        | clear write-in-progress flag
        MOVE    (SP)+,SR                        | restore interrupts
E_BOUT_PRIME_DONE:
        MOVEQ.L #0x0,D0                         | noErr
        BRA     E_BINOUT_CONTROL_ERR_2          | -> IODone (async completion)

| ----------------------------------------------------------
|
| RETURNS_11: check SCC Tx buffer status and return write address
| Returns: A3 = SCC write data address, Z flag = Tx buffer empty
| Tests RR0 bit 2 (Tx buffer empty)
|
RETURNS_11:
        MOVE.L  (SCCRd).w,A3                    | A3 = SCC read base
        ADDA    0x4(A2),A3                      | add channel offset
        TST.B   (A3)                            | read RR0 (resets register pointer)
        MOVE    (SP),(SP)                       | SCC access timing delay
        BTST    #0x2,(A3)                       | test RR0 bit 2: Tx buffer empty?
        ADDA.L  #0x200001,A3                    | A3 = SCC write data register address
        RTS                                     | Z flag reflects Tx empty status

| ----------------------------------------------------------
|
| RETURNS_12: check if output is blocked by flow control
| Returns: D0 != 0 if output should be held (CTS low or XOFF received)
|
RETURNS_12:
        TST.B   0x10(A2)                        | CTS handshake enabled?
        BEQ.B   E_BOUT_PRIME_NO                 | no -> check XOFF
        TST.B   0x1D(A2)                        | XOFF received from remote?
        BNE.B   E_BOUT_PRIME_OK                 | yes -> output blocked
E_BOUT_PRIME_NO:
        TST.B   0x11(A2)                        | DTR handshake enabled?
        BEQ.B   E_BOUT_PRIME_NO_2               | no -> output not blocked
        TST.B   0x1C(A2)                        | CTS asserted?
        BEQ.B   E_BOUT_PRIME_NO_2               | no (CTS low) -> not blocked
E_BOUT_PRIME_OK:
        MOVEQ.L #0x1,D0                         | output is blocked
        RTS                                     | D0=1: caller should wait

| ----------------------------------------------------------
|
| E_BOUT_PRIME_NO_2: output not blocked
|
E_BOUT_PRIME_NO_2:
        MOVEQ.L #0x0,D0                         | output is clear to send
        RTS                                     | D0=0: caller may transmit

| ----------------------------------------------------------
|
| SCCInt_BOutEmpty: Tx buffer empty ISR for printer port (ch B)
|
SCCInt_BOutEmpty:
        MOVE.L  (ABusVars).w,A2                 | A2 = port B SERDVars
        BRA.B   SCCINT_AOUTEMPTY_EMPTY          | -> shared Tx empty handler

| ----------------------------------------------------------
|
| SCCInt_AOutEmpty: Tx buffer empty ISR for modem port (ch A)
|
SCCInt_AOutEmpty:
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A SERDVars
| Shared Tx buffer empty interrupt handler
SCCINT_AOUTEMPTY_EMPTY:
        TST.B   0x76(A2)                        | pending flow control char waiting?
        BNE.B   SCCINT_AOUTEMPTY_OK             | yes -> transmit it now
        TST.B   0x1B(A2)                        | write in progress?
        BEQ.B   SCCINT_AOUTEMPTY_NO             | no -> reset Tx interrupt pending
        BSR.B   RETURNS_12                      | check if output blocked
        BNE.B   SCCINT_AOUTEMPTY_NO             | blocked -> reset Tx int, wait for CTS
| Resume transmit: feed next char to SCC
SCCINT_AOUTEMPTY_OK:
        MOVE.L  (A2),A1                         | A1 = DCE pointer
        MOVE    SR,-(SP)                        | save SR (for E_BOUT_PRIME_LOOP return path)
        BRA     E_BOUT_PRIME_LOOP               | -> transmit loop

| ----------------------------------------------------------
|
| SCCINT_AOUTEMPTY_NO: nothing to send - reset SCC Tx interrupt pending
|
SCCINT_AOUTEMPTY_NO:
        MOVE.B  #0x28,(A1)                      | WR0 cmd: reset Tx interrupt pending
        RTS                                     | Tx empty ISR done, nothing to send

| ----------------------------------------------------------
|
| SCCINT_AOUTEMPTY_OK_2: XOn received - clear output-stopped, check if should resume
|
SCCINT_AOUTEMPTY_OK_2:
        CLR.B   0x1D(A2)                        | clear XOFF-received flag
| SCCINT_AOUTEMPTY_CONT: check if pending write should resume after flow control change
SCCINT_AOUTEMPTY_CONT:
        BSR.B   RETURNS_12                      | check if output still blocked
        BNE.B   SCCINT_AOUTEMPTY_EXIT           | still blocked -> return
        TST.B   0x1B(A2)                        | write in progress?
        BNE.B   SCCINT_AOUTEMPTY_OK             | yes -> resume transmit
SCCINT_AOUTEMPTY_EXIT:
        RTS                                     | no write to resume

| ----------------------------------------------------------
|
| E_A In_Prime: .AIn Read - interrupt-driven receive for modem port
|
E_AIn_Prime:
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A SERDVars
        BRA.B   E_BIN_PRIME_CONT                | -> shared read handler

| ----------------------------------------------------------
|
| E_B In_Prime: .BIn Read - interrupt-driven receive for printer port
|
E_BIn_Prime:
        MOVE.L  (ABusVars).w,A2                 | A2 = port B SERDVars
| Shared Read handler: copy bytes from ring buffer to ioBuffer
E_BIN_PRIME_CONT:
        MOVEQ.L #-0x13,D0                       | readErr (-19) default
        MOVE.L  A2,D1                           | test if SERDVars allocated
        BLE     E_BINOUT_CONTROL_ERR_2          | NULL -> error via IODone
        BSR.B   RETURNS_13                      | load ring buffer state
| Read loop: copy bytes from ring buffer to caller's ioBuffer
E_BIN_PRIME_LOOP:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts
        CMP     0x2C(A2),D2                     | read tail == write head?
        BEQ.B   E_BIN_PRIME_EMPTY               | yes -> buffer empty, wait
        MOVE.B  0x0(A3,D2.W),D0                 | D0 = next byte from ring buffer
        ADDQ.W  #0x1,D2                         | advance read tail
        CMP     D3,D2                           | past end of buffer?
        BNE.B   E_BIN_PRIME_NO                  | no -> continue
        MOVEQ.L #0x0,D2                         | wrap read tail to start
E_BIN_PRIME_NO:
        MOVE    D2,0x2E(A2)                     | +0x2E: update read tail index
        BSR.B   E_BIN_PRIME_CONT_4              | call JStash (store byte in ioBuffer)
        MOVE    (SP)+,SR                        | restore interrupts
        TST     D0                              | JStash result: negative = done
        BPL.B   E_BIN_PRIME_LOOP                | more to read -> loop
        BSR.B   E_BIN_PRIME_CONT_2              | check flow control (may send XOn)
        BRA     E_BOUT_PRIME_DONE               | -> IODone (read complete)

| ----------------------------------------------------------
|
| E_BIN_PRIME_EMPTY: ring buffer empty - set read-pending flag and wait
|
E_BIN_PRIME_EMPTY:
        ST.B    0x1A(A2)                        | +0x1A: set read-pending flag
        BRA.B   E_BIN_PRIME_CONT_3              | -> check flow control thresholds

| ----------------------------------------------------------
|
| E_BIN_PRIME_CONT_2: after read - check if buffer low enough to resume flow
|
E_BIN_PRIME_CONT_2:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts
E_BIN_PRIME_CONT_3:
        TST     0x16(A2)                        | XOn/XOff flow control enabled?
        BEQ.B   E_BIN_PRIME_DONE                | no -> done
        BSR.B   RETURNS_13                      | load ring buffer state
        BSR.B   RETURNS_14                      | D0 = bytes in buffer
        CMP     0xC(A2),D0                      | below XOff threshold (low water)?
        BHI.B   E_BIN_PRIME_DONE                | no, still above -> don't send XOn
        BSR.B   E_BIN_PRIME_CONT_5              | send XOn if needed (buffer drained)
E_BIN_PRIME_DONE:
        MOVEQ.L #0x0,D0                         | noErr
        MOVE    (SP)+,SR                        | restore interrupts
        RTS                                     | flow control check done

| ----------------------------------------------------------
|
| E_BIN_PRIME_CONT_4: call JStash vector (store received byte in ioBuffer)
|
E_BIN_PRIME_CONT_4:
        MOVE.L  (JStash).w,-(SP)                | push JStash vector address
E_BIN_PRIME_EXIT:
        RTS                                     | jump to JStash

| ----------------------------------------------------------
|
| RETURNS_13: load ring buffer state registers from SERDVars
| Returns: A3=buffer ptr, D3=size, D1=write head, D2=read tail
|
RETURNS_13:
        MOVE.L  0x6(A2),A3                      | A3 = receive buffer pointer
        MOVE    0xA(A2),D3                      | D3 = buffer size
        MOVEM   0x2C(A2),D1-D2                  | D1 = write head, D2 = read tail
        RTS                                     | ring buffer state loaded

| ----------------------------------------------------------
|
| RETURNS_14: compute bytes available in ring buffer
| Returns: D0 = (write head - read tail), wrapped if negative
|
RETURNS_14:
        MOVE    D1,D0                           | D0 = write head
        SUB     D2,D0                           | D0 = head - tail
        BCC.B   E_BIN_PRIME_DONE_2              | non-negative -> done
        ADD     D3,D0                           | wrap: add buffer size
E_BIN_PRIME_DONE_2:
        RTS                                     | D0 = byte count in buffer

| ----------------------------------------------------------
|
| E_BIN_PRIME_CONT_5: send XOn/deassert DTR if buffer has drained below threshold
|
E_BIN_PRIME_CONT_5:
        TST.B   0x17(A2)                        | DTR handshake was enabled?
        BEQ.B   E_BIN_PRIME_SKIP                | no -> check XOff
        BCLR    #0x6,0x19(A2)                   | clear "DTR asserted" flag
        BEQ.B   E_BIN_PRIME_SKIP                | was already clear -> skip
        BSR     E_BINOUT_CONTROL_OK_2           | deassert DTR line
E_BIN_PRIME_SKIP:
        TST.B   0x16(A2)                        | XOn/XOff enabled?
        BEQ.B   E_BIN_PRIME_EXIT                | no -> return
| E_BIN_PRIME_CONT_6: clear "XOFF sent" flag and send XOn if we had sent XOFF
E_BIN_PRIME_CONT_6:
        BClr    #0x7,0x19(A2)                   | clear "XOFF sent" flag
        BEQ.B   E_BIN_PRIME_EXIT                | was not set -> nothing to send
        MOVE.B  0x12(A2),D0                     | D0 = XOn character
| E_BIN_PRIME_CONT_7: queue a flow control character for transmission
E_BIN_PRIME_CONT_7:
        TST.B   0x76(A2)                        | already have a pending char?
        BEQ.B   E_BIN_PRIME_NO_2                | no -> queue this one
E_BIN_PRIME_CONT_8:
        CLR.B   0x76(A2)                        | cancel pending char (XOn overrides)
E_BIN_PRIME_CONT_9:
        RTS                                     | flow control char handled

| ----------------------------------------------------------
|
| E_BIN_PRIME_NO_2: queue flow control char and try to transmit immediately
|
E_BIN_PRIME_NO_2:
        MOVE.B  D0,0x76(A2)                     | +0x76: store pending output char
        BSR     RETURNS_11                      | check if SCC Tx buffer empty
        BEQ.B   E_BIN_PRIME_CONT_9              | Tx busy -> char will be sent by ISR
        MOVE.B  D0,0x4(A3)                      | Tx empty: write char to SCC data reg
        BRA.B   E_BIN_PRIME_CONT_8              | clear pending flag

| ----------------------------------------------------------
|
| A Out_Poll Proc: modem port polling procedure
| Called during disk I/O to keep serial output alive
| Reads bytes from disk buffer, transmits via SCC channel A
|
AOut_PollProc:
        MOVE.L  (PollStack).w,A4                | A4 = polling stack pointer
        MOVE.L  (SP)+,(TwiggyVars).w            | save return address in temp global
| Poll loop: wait for disk byte, then transmit serial byte
AOUT_POLLPROC_CONT:
        TST.B   (A5)                            | test IWM status (disk ready?)
        BMI.B   AOUT_POLLPROC_CONT_2            | bit 7 set -> disk byte ready
        MOVE.B  (A6),-(SP)                      | read disk byte, push to poll stack
        BRA.B   AOUT_POLLPROC_CONT              | keep polling

| ----------------------------------------------------------
|
| AOUT_POLLPROC_CONT_2: disk byte ready - transmit pending serial data
|
AOUT_POLLPROC_CONT_2:
        CMPA.L  A7,A4                           | poll stack back to starting point?
        BEQ.B   AOUT_POLLPROC_EXIT              | yes -> all done, return
        SUBQ.W  #0x2,A4                         | back up poll stack pointer
        MOVE.B  (A4),D0                         | D0 = byte to transmit
        LEA.L   (SerialVars_a).w,A3             | A3 = port A vars
        LEA.L   (SCC_RdCtlA).l,A0               | SCC channel A control read
        LEA.L   (SCC_WrCtlA).l,A1               | SCC channel A control write
        BSR.B   SCCINT_AINAVAIL_CONT_2          | process received byte
        BRA.B   AOUT_POLLPROC_CONT              | continue polling

| ----------------------------------------------------------
|
| AOUT_POLLPROC_EXIT: polling complete - restore stack and return
|
AOUT_POLLPROC_EXIT:
        MOVE.L  (PollStack).w,SP                | restore stack pointer
        MOVE.L  (TwiggyVars).w,-(SP)            | push saved return address
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| SCCInt_BInAvail: receive data available ISR for printer port (ch B)
|
SCCInt_BInAvail:
        LEA.L   (ABusVars).w,A3                 | A3 = port B vars
        BRA.B   SCCINT_AINAVAIL_CONT            | -> shared receive handler

| ----------------------------------------------------------
|
| SCCInt_AInAvail: receive data available ISR for modem port (ch A)
|
SCCInt_AInAvail:
        LEA.L   (SerialVars_a).w,A3             | A3 = port A vars
| Shared receive data available handler
SCCINT_AINAVAIL_CONT:
        MOVE.B  0x4(A0),D0                      | read received byte from SCC data reg
| SCCINT_AINAVAIL_CONT_2: process received byte in D0
| A3 -> vars global (dereferenced to get SERDVars+DCE)
SCCINT_AINAVAIL_CONT_2:
        MOVE.L  (A3)+,A2                        | A2 = SERDVars pointer
        MOVE.L  (A3),A3                         | A3 = DCE pointer
        AND.B   0x77(A2),D0                     | mask data bits (5/6/7/8 bit mode)
        MOVE.B  0x78(A2),D1                     | D1 = parity error replace match char
        BEQ.B   SCCINT_AINAVAIL_SKIP            | no replace char -> skip
        CMP.B   D1,D0                           | received byte matches replace char?
        BNE.B   SCCINT_AINAVAIL_SKIP            | no -> keep original
        MOVE.B  0x79(A2),D0                     | substitute replacement character
SCCINT_AINAVAIL_SKIP:
        TST.B   0x10(A2)                        | CTS/software flow control enabled?
        BEQ.B   SCCINT_AINAVAIL_NO              | no -> store byte directly
        CMP.B   0x12(A2),D0                     | received XOn character?
        BEQ     SCCINT_AOUTEMPTY_OK_2           | yes -> clear XOFF, resume output
        CMP.B   0x13(A2),D0                     | received XOff character?
        BNE.B   SCCINT_AINAVAIL_NO              | no -> store byte
        ST.B    0x1D(A2)                        | set output-stopped flag (XOFF received)
        BRA.B   SCCINT_AINAVAIL_DONE            | done (don't store XOff in buffer)

| ----------------------------------------------------------
|
| SCCINT_AINAVAIL_NO: store received byte - check if read is pending
|
SCCINT_AINAVAIL_NO:
        TST.B   0x1A(A2)                        | read operation pending?
        BEQ.B   SCCINT_AINAVAIL_NO_2            | no -> store in ring buffer
        MOVE.L  A3,A1                           | A1 = DCE for JStash
        BSR     E_BIN_PRIME_CONT_4              | call JStash (store byte in ioBuffer)
        BPL.B   SCCINT_AINAVAIL_DONE            | more room -> done
        CLR.B   0x1A(A2)                        | read satisfied: clear pending flag
        BRA     E_BOUT_PRIME_DONE               | -> IODone

| ----------------------------------------------------------
|
| SCCINT_AINAVAIL_NO_2: store byte in ring buffer (no read pending)
|
SCCINT_AINAVAIL_NO_2:
        BSR     RETURNS_13                      | load ring buffer state
        MOVE.B  D0,0x0(A3,D1.W)                 | store byte at write head
        ADDQ.W  #0x1,D1                         | advance write head
        CMP     D3,D1                           | past end of buffer?
        BNE.B   SCCINT_AINAVAIL_SKIP_2          | no -> continue
        MOVEQ.L #0x0,D1                         | wrap write head to start
SCCINT_AINAVAIL_SKIP_2:
        CMP     D2,D1                           | write head caught read tail?
        BNE.B   SCCINT_AINAVAIL_NO_3            | no -> buffer not full
        BSET    #0x0,0x18(A2)                   | set buffer overflow bit in cumErr
        BRA.B   SCCINT_AINAVAIL_DONE            | discard byte (buffer full)

| ----------------------------------------------------------
|
| SCCINT_AINAVAIL_NO_3: byte stored - check flow control thresholds
|
SCCINT_AINAVAIL_NO_3:
        MOVE    D1,0x2C(A2)                     | update write head index
        TST     0x16(A2)                        | XOn/XOff flow control enabled?
        BEQ.B   SCCINT_AINAVAIL_DONE            | no -> done
        BSR     RETURNS_14                      | D0 = bytes in buffer
        SUB     D0,D3                           | D3 = free space remaining
        CMP     0xE(A2),D3                      | below XOn threshold (high water)?
        BCC.B   SCCINT_AINAVAIL_DONE            | enough room -> done
| Buffer nearly full - apply flow control
        TST.B   0x17(A2)                        | DTR handshake enabled?
        BEQ.B   SCCINT_AINAVAIL_NO_4            | no -> try XOff
        BSET    #0x6,0x19(A2)                   | set "DTR asserted" flag
        BNE.B   SCCINT_AINAVAIL_SKIP_2          | already asserted -> skip
        BSR     E_BINOUT_CONTROL_CONT_10        | assert DTR (tell remote to stop)
        TST.B   0x16(A2)                        | XOff also enabled?
        BEQ.B   SCCINT_AINAVAIL_DONE            | no -> done
| SCCINT_AINAVAIL_NO_4: send XOff to tell remote to stop sending
SCCINT_AINAVAIL_NO_4:
        BSet    #0x7,0x19(A2)                   | set "XOFF sent" flag
        BNE.B   SCCINT_AINAVAIL_DONE            | already sent -> don't duplicate
        MOVE.B  0x13(A2),D0                     | D0 = XOff character
        BSR     E_BIN_PRIME_CONT_7              | queue XOff for transmission
SCCINT_AINAVAIL_DONE:
        RTS                                     | receive interrupt handled

| ----------------------------------------------------------
|
| SCCInt_BInSpcl: special receive condition ISR for printer port (ch B)
| Handles parity/framing/overrun errors and break detection
|
SCCInt_BInSpcl:
        LEA.L   (ABusVars).w,A3                 | A3 = port B vars
        BRA.B   SCCINT_AINSPCL_CONT             | -> shared special handler

| ----------------------------------------------------------
|
| SCCInt_AInSpcl: special receive condition ISR for modem port (ch A)
|
SCCInt_AInSpcl:
        LEA.L   (SerialVars_a).w,A3             | A3 = port A vars
| Shared special receive condition handler
SCCINT_AINSPCL_CONT:
        MOVE.B  #0x1,(A1)                       | select RR1 (special receive status)
        MOVE.L  (A3)+,A2                        | A2 = SERDVars pointer
        MOVE.L  (A3),A3                         | A3 = DCE pointer
        MOVE.B  (A0),D1                         | D1 = RR1 (parity|overrun|framing bits)
        MOVEQ.L #0x70,D3                        | mask 0x70: error bits (parity|Rx overrun|framing)
        AND.B   D3,D1                           | isolate error bits
        OR.B    D1,0x18(A2)                     | accumulate into cumErr
        MOVE.B  0x4(A0),D0                      | read received data byte (clears error)
        AND.B   0x77(A2),D0                     | apply data bit mask
        MOVE.B  0x14(A2),D2                     | D2 = error replace flags
        AND.B   D1,D2                           | mask with actual errors
        MOVE.B  #0x30,(A1)                      | WR0 cmd: error reset
        AND.B   D3,D2                           | any matching errors?
        BNE.B   SCCINT_AINSPCL_ERR              | yes -> handle error condition
| No flagged errors - check for character replacement
        MOVE.B  0x78(A2),D3                     | D3 = parity error replace char
        BEQ.B   SCCINT_AINSPCL_OK               | no replace char -> store as-is
        CMP.B   D0,D3                           | byte matches replace char?
        BNE.B   SCCINT_AINSPCL_FOUND            | no match -> check break
        MOVE.B  0x79(A2),D0                     | substitute replacement character
SCCINT_AINSPCL_FOUND:
        BTst    #0x4,D1                         | RR1 bit 4: parity error?
        BEQ.B   SCCINT_AINSPCL_OK               | no -> store byte
        MOVE.B  D3,D0                           | parity error: use replace char
SCCINT_AINSPCL_OK:
        BRA     SCCINT_AINAVAIL_NO              | -> store byte in buffer

| ----------------------------------------------------------
|
| SCCINT_AINSPCL_ERR: error condition flagged - abort pending read if any
|
SCCINT_AINSPCL_ERR:
        TST.B   0x1A(A2)                        | read pending?
        BEQ.B   SCCINT_AINAVAIL_DONE            | no -> discard byte, return
        MOVEQ.L #-0x59,D0                       | parityErr (-89)
SCCINT_AINSPCL_ERR_2:
        MOVE.L  A3,A1                           | A1 = DCE for IODone
        CLR.B   0x1A(A2)                        | clear read-pending flag
        BRA     E_BINOUT_CONTROL_ERR_2          | -> IODone with error

| ----------------------------------------------------------
|
| SCCInt_BChng_BOut: ext/status change ISR for printer port (ch B)
| Handles DCD transitions, break detect, CTS changes
|
SCCInt_BChng_BOut:
        LEA.L   (ABusVars).w,A3                 | A3 = port B vars
        BRA.B   SCCINT_ACHNG_AOUT_CONT          | -> shared handler

| ----------------------------------------------------------
|
| SCCInt_AChng_AOut: ext/status change ISR for modem port (ch A)
|
SCCInt_AChng_AOut:
        LEA.L   (SerialVars_a).w,A3             | A3 = port A vars
| Shared external/status change handler
| RR0 in D0 (from dispatcher), D1 = XORed status bits (changed bits)
SCCINT_ACHNG_AOUT_CONT:
        MOVE.L  (A3)+,A2                        | A2 = SERDVars pointer
        MOVE.L  (A3),A3                         | A3 = DCE pointer
        MOVE.B  D1,D2                           | D2 = changed status bits
        AND.B   0x15(A2),D2                     | mask with event-enable bits (evts)
        BEQ.B   SCCINT_ACHNG_AOUT_SKIP          | no enabled events changed -> skip
| Post device driver event for status change
        MOVEM.L D0/A0,-(SP)                     | save registers
        MOVE    #0xB,A0                         | evtNum = 11 (device driver event)
        ASL     #0x8,D0                         | shift RR0 to high byte of event msg
        MOVE.B  D1,D0                           | low byte = changed bits
        SWAP    D0                              | move to high word
        MOVE    VISRGN(A3),D0                   | low word = driver refNum from DCE
        _PostEvent                              | post event to event queue
        MOVEM.L (SP)+,D0/A0                     | restore registers
SCCINT_ACHNG_AOUT_SKIP:
        TST.B   D1                              | test bit 7 of changed bits (break/abort)
        BMI.B   SCCINT_ACHNG_AOUT_CONT_2        | break detected -> handle break
| DCD or CTS transition
        LSL.B   #0x2,D0                         | shift RR0 bit 5 (CTS) to bit 7
        SMI.B   0x1C(A2)                        | +0x1C: update CTS state
| Rate-limit DCD transitions (break detect protection)
        CMPI    #0x50,0x70(A2)                  | DCD count >= 80 this tick?
        BCS.B   SCCINT_ACHNG_AOUT_NO            | no -> continue
        MOVEQ.L #-0x78,D0                       | WR15 value: disable ext/status ints
        MOVEQ.L #0xF,D1                         | WR15 register number
        BSR     E_BINOUT_CONTROL_CONT_14        | write WR15 to throttle interrupts
SCCINT_ACHNG_AOUT_NO:
        MOVE.L  (Ticks).w,D2                    | D2 = current tick count
        CMP.L   0x72(A2),D2                     | same tick as last transition?
        BEQ.B   SCCINT_ACHNG_AOUT_OK            | yes -> just increment count
        MOVE.L  D2,0x72(A2)                     | +0x72: update last transition tick
        CLR     0x70(A2)                        | +0x70: reset transition count
SCCINT_ACHNG_AOUT_OK:
        ADDQ.W  #0x1,0x70(A2)                   | increment DCD transition count
        BRA     SCCINT_AOUTEMPTY_CONT           | check if transmit should resume

| ----------------------------------------------------------
|
| SCCINT_ACHNG_AOUT_CONT_2: break/abort detected - check if real break or just transition
|
SCCINT_ACHNG_AOUT_CONT_2:
        TST.B   D0                              | test RR0 bit 7: break still active?
        BMI.B   SCCINT_ACHNG_AOUT_ERR           | yes -> report break error
        MOVE.B  0x4(A0),D0                      | read and discard data byte
        RTS                                     | transient glitch - ignore

| ----------------------------------------------------------
|
| SCCINT_ACHNG_AOUT_ERR: real break detected - abort pending read with error
|
SCCINT_ACHNG_AOUT_ERR:
        MOVEQ.L #-0x5A,D0                       | breakRecd (-90): break received
        TST.B   0x1A(A2)                        | read pending?
        BNE.B   SCCINT_AINSPCL_ERR_2            | yes -> abort read with breakRecd
        RTS                                     | no pending read -> just return

| end of resource : 'SERD' 0

| resource header
  .long 0xC0000406                              | Length
  .long 0x0000006C                              | ?

