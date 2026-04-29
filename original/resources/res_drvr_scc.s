
| ----------------------------------------------------------
| Serial driver DRVR headers (4 x 24 bytes) @ ROM $2552
| In the 64K ROM the four built-in serial drivers (.AIn, .AOut, .BIn,
| .BOut) have their DRVR headers embedded directly in the ROM rather
| than as 'DRVR' resources in the resource fork. Each header is 24
| bytes: 10-byte flags/offsets + Pascal-string name padded to a word.
| drvrFlags: bit 0x0E set in .AIn/.BIn (read-enable), bit 0x0F in
| .AOut/.BOut (write-enable); all have dNeedTime+dNeedGoodBye.
| drvrOpen/Prime/Ctl/Status/Close: offsets relative to the header.

Driver_AIn:                                     | .AIn header @ $2552
        .short  0x4D00, 0x0000, 0x0000, 0x0000  | flags, delay, eMask, menu
        .short  0x0060, 0x036A, 0x0232, 0x01F6  | open=$60, prime=$36A, ctl=$232, status=$1F6
        .short  0x01F4                          | close=$1F4
        .byte   0x04                            | drvrName length = 4
        .ascii  ".AIn"                          | drvrName
        .byte   0x20                            | pad to word boundary

Driver_AOut:                                    | .AOut header @ $256A
        .short  0x4E00, 0x0000, 0x0000, 0x0000  | flags, delay, eMask, menu
        .short  0x0054, 0x02A4, 0x021A, 0x01DE  | open=$54, prime=$2A4, ctl=$21A, status=$1DE
        .short  0x019C                          | close=$19C
        .byte   0x05                            | drvrName length = 5
        .ascii  ".AOut"                         | drvrName

Driver_BIn:                                     | .BIn header @ $2582
        .short  0x4D00, 0x0000, 0x0000, 0x0000  | flags, delay, eMask, menu
        .short  0x0036, 0x0340, 0x0208, 0x01CC  | open=$36, prime=$340, ctl=$208, status=$1CC
        .short  0x01C4                          | close=$1C4
        .byte   0x04                            | drvrName length = 4
        .ascii  ".BIn"                          | drvrName
        .byte   0x20                            | pad to word boundary

| Driver_BOut - .BOut DRVR header (modem-port output): flags + dispatch table
Driver_BOut:                                    | .BOut header @ $259A
        .short  0x4E00, 0x0000, 0x0000, 0x0000  | flags, delay, eMask, menu
        .short  0x0050, 0x027A, 0x01F0, 0x01B4  | open=$50, prime=$27A, ctl=$1F0, status=$1B4
        .short  0x017E                          | close=$17E
        .byte   0x05                            | drvrName length = 5
        .ascii  ".BOut"                         | drvrName
        MOVE.L  A1,(SerialVars_a_dce).w         | (first MOVE.L/RTS pair @ $25B2)
        RTS                                     | return: AIn DCE saved
        MOVE.L  A1,(ABusVars_dce).w             | (ABusVars_dce).w
        RTS                                     | return: BIn DCE saved
        MOVEQ.L #0x8,D0                         | D0 = 8 (port A SCC dispatch offset)
        LEA.L     (SerialVars_a).w,A2           | A2 = port A serial vars head
        LEA     SCCInt_AOutEmpty(PC),A3         | A3 = port A TX-empty handler
        LEA     SCCInt_AChng_AOut(PC),A4        | A4 = port A external/status handler
        LEA     SCCInt_AInAvail(PC),A5          | A5 = port A RX-available handler
        LEA     SCCInt_AInSpcl(PC),A6           | A6 = port A RX-special handler
        MOVEQ.L #0x2,D1                         | D1 = 2 (port A IRQ slot)
        MOVEQ.L #-0x9,D2                        | D2 = -9 (default port A flags)
        MOVEQ.L #-0x80,D3                       | D3 = -128 (port A WR1 default)
        MOVE    (SPPortA).w,D4                  | D4 = port A SerConfig (PRAM)
        BSR.B   DRIVER_BOUT_CONT_CONT_2         | install vectors and init port
        PEA.L   AOut_PollProc(PC)               | push port A poll proc
        MOVE.L  (SP)+,(PollProc).w              | install AOut_PollProc as PollProc
        RTS                                     | return: port A driver opened
        MOVEQ.L #0x0,D0                         | D0 = 0 (port B SCC dispatch offset)
        LEA.L     (ABusVars).w,A2               | A2 = port B (ABusVars) head
        LEA     SCCInt_BOutEmpty(PC),A3         | A3 = port B TX-empty handler
        LEA     SCCInt_BChng_BOut(PC),A4        | A4 = port B external/status handler
        LEA     SCCInt_BInAvail(PC),A5          | A5 = port B RX-available handler
        LEA     SCCInt_BInSpcl(PC),A6           | A6 = port B RX-special handler
        MOVEQ.L #0x0,D1                         | D1 = 0 (port B IRQ slot)
        MOVEQ.L #0x17,D2                        | D2 = $17 (default port B flags)
        MOVEQ.L #0x40,D3                        | D3 = $40 (port B WR1 default)
        MOVE    (SPPortB).w,D4                  | D4 = port B SerConfig (PRAM)
DRIVER_BOUT_CONT_CONT_2:
        LEA.L     (ExtStsDT).w,A0               | A0 = SCC ExtStatus dispatch table
        MOVE.L  A4,0(A0,D0.W)                   | install ExtStsDT[port] = handler
        LEA.L     (Lvl2DT).w,A0                 | A0 = level-2 SCC dispatch table
        ADD     D0,D0                           | D0 *= 2 (long-word table index)
        MOVE.L  A3,0(A0,D0.W)                   | Lvl2DT[port] = TX-empty handler
        MOVEM.L  A5-FP,8(A0,D0.W)               | install RX/spcl handlers in Lvl2DT
        MOVEQ.L #0x70,D0                        | D0 = $70 = 112 bytes for serial vars
        _NewHandleSysClear                      | allocate cleared system handle
        BSET    #0x7,(A0)                       | set high bit of master ptr (locked)
        MOVE.L  A0,iconIDCC(A1)                 | dCtlStorage = handle ptr
        MOVE.L  (A0),(A2)                       | SerialVars[port] = block ptr
        MOVE.L  (A0),A2                         | A2 = serial vars block
        MOVE.L  A2,A3                           | A3 = working ptr (start of vars)
        MOVE.L  A1,(A3)+                        | vars[0] = DCE pointer
        MOVE    D1,(A3)+                        | vars[4] = IRQ slot index
        BSR.W   E_BINOUT_CONTROL_CONT_5         | enqueue ServErrCode handler
        ST      17(A2)                          | 17(A2) := -1 (true)
        ST      20(A2)                          | 20(A2) := -1 (true)
        MOVE.B  D3,0x20(A2)                     | vars[$20] = default WR1 flags
        MOVE.B  D2,0x29(A2)                     | vars[$29] = default port flags
DRIVER_BOUT_CONT_CONT_3:
        MOVE    D4,0x2A(A2)                     | vars[$2A] = SerConfig (PRAM)
        LEA.L     0x21(A2),A3                   | A3 = SCC register shadow array
        LEA     E_BOUT_OPEN_DECODE_TBL(PC),A4   | A4 = SerConfig decode table
        MOVEQ.L #0x7,D0                         | D0 = 7 (8 entries to decode)
| Loop: extract each SCC register value from SerConfig via decode table
| Each entry: rotate count, AND mask, OR mask - applied to D4
E_BOUT_OPEN_LOOP:
        MOVE.B  (A4)+,D1                        | D1 = rotate count for this entry
        MOVE    D4,D3                           | D3 = SerConfig (working copy)
        ROL     D1,D3                           | D3 rotate left D1
        AND.B   (A4)+,D3                        | D3 &= AND mask for this entry
        OR.B    (A4)+,D3                        | D3 |= OR mask for this entry
        MOVE.B  D3,(A3)+                        | store decoded byte in shadow array
        DBRA    D0,E_BOUT_OPEN_LOOP             | loop for all 8 decode entries
        MOVEQ.L #0x64,D1                        | D1 = $64 (parity-bits mask)
        AND.B   (A3),D1                         | D1 = parity bits from WR4
        MOVE.B  D1,0x22(A2)                     | D0 = next (reg, value) pair
        BSR.B   E_BOUT_OPEN_CONT_5              | call register-write helper
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return: SCC port opened
| E_BOUT_OPEN_DECODE_TBL: SerConfig decode table -- 4 entries of
| (rotate-byte, AND-mask-byte, OR-value-byte) x 2 SCC-register pairs.
| Plus's later revision doubles this to 8 entries.
E_BOUT_OPEN_DECODE_TBL:
  .byte 0x04, 0x0F, 0x40, 0x00, 0x00, 0x00      | entry 0: rot=4 mask=$0F OR=$40; entry 1: nop
  .byte 0x0C, 0xC0, 0x00, 0x0B, 0x60, 0x02      | entry 2: rot=12 mask=$C0; entry 3: WR11 clk
E_BOUT_OPEN_DECODE_TBL_CONT:                    | internal xref
  .byte 0x00, 0xFF, 0x00, 0x08, 0x03, 0x00      | entry 4: pass-through; entry 5: WR3 Rx bits
  .byte 0x0C, 0xC0, 0x01, 0x0B, 0x60, 0x0A      | entry 6: stop bits; entry 7: WR11 DPLL
| REGISTER_TBL: SCC initialization sequence as (register, value) pairs.
| 0xFF in the value column means "use the shadow array for this register".
REGISTER_TBL:                                   | REGISTER_TBL start
  .byte 0x09, 0xFF, 0x04, 0xFF, 0x01, 0xFF      | WR9=MIE, WR4=shadow, WR1=shadow
  .byte 0x00, 0x02, 0x03, 0xFF, 0x05, 0xFF      | WR0 reset, WR3=shadow, WR5=shadow
  .byte 0x02, 0x09, 0x50, 0x0B, 0x0C, 0xFF      | WR2=intVec, WR10=NRZ, WR12=shadow
  .byte 0x0D, 0xFF, 0x03, 0xFF, 0x05, 0xFF      | WR13=shadow, WR3=en, WR5=en
  .byte 0x01, 0x0E, 0xA8, 0x0F, 0x40, 0x00      | WR1=shadow, WR14=BRG, WR15=DCD, WR0=reset
  .byte 0x40, 0x00, 0x01, 0xFF, 0x0A, 0x09      | WR0=reset x2, WR1=shadow, WR10, WR9
E_BOUT_OPEN_CONT_5:
        LEA     REGISTER_TBL(PC),A3             | A3 = SCC init register table
        MOVEQ.L #0x24,D1                        | D1 = $24 = 36 (18 reg/val pairs)
FORMAT:
        MOVE    SR,-(SP)                        | save SR (preserve IPL)
        MOVEM.L A0-A2,-(SP)                     | save A0-A2 to stack
        MOVE    4(A2),D2                        | D2 = SCC port offset
        MOVEM.L (SCCRd).w,A0-A1                 | A0=SCCRd, A1=SCCWr base addrs
        ADDA.W  D2,A0                           | A0 = port-specific SCC read addr
        ADDA.W  D2,A1                           | A1 = port-specific SCC write addr
        ORI     #0x300,SR                       | raise IPL=3 (mask SCC ints)
        MOVE.B  (A0),D2                         | dummy read to reset SCC reg ptr
        LEA.L     0x20(A2),A2                   | A2 = SCC register shadow array
E_BOUT_OPEN_LOOP_2:
        MOVE    (A3)+,D0                        | D0 = (reg#, value) word
        TST.B   D0                              | value byte == $FF (use shadow)?
        BPL.B   E_BOUT_OPEN_NO                  | value byte < $80 -> use literal
        MOVE.B  (A2)+,D0                        | D0.lo = next shadow byte
        ROR     #0x8,D0                         | rotate value into low byte
E_BOUT_OPEN_NO:
        MOVE.B  D0,(A1)                         | write reg# to SCC (selects)
        ROR     #0x8,D0                         | rotate value into low byte
        MOVE.L  (SP),(SP)                       | SCC settling delay
        MOVE.B  D0,(A1)                         | write value to selected SCC reg
        SUBQ.W  #0x2,D1                         | advance pair counter
        BGT.B   E_BOUT_OPEN_LOOP_2              | more pairs -> loop
        MOVE.B  (A0),D2                         | read RR0 (status)
        LSL.B   #0x2,D2                         | shift DCD bit (RR0[3]) into N flag
        MOVEM.L (SP)+,A0-A2                     | restore A0-A2
        SMI     28(A2)                          | 28(A2) := (N == 1)
        RTE                                     | restore SR and return
E_BOUT_OPEN_DECODE_TBL_CONT_2_CONT_5:
| === SCC config data (4 bytes) ===
        .short  0x09FF
        .short  0x080F
        NEGX.B  D0                              | D0 = -D0 (with X bit)
        NEGX.B  D0                              | D0 = -D0 (with X bit)
        BTST    D0,D1                           | test bit D0 of D1
        CLR.L   (PollProc).w                    | clear PollProc lowmem (no polling)
        LEA.L     (Lvl2DT_4).w,A4               | A4 = port A level-2 dispatch slot
        LEA.L     (ExtStsDT_A).w,A5             | A5 = port A ExtStatus slot
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A serial vars block
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_3   | join common close path
        LEA.L     (Lvl2DT).w,A4                 | A4 = port B level-2 dispatch slot
        LEA.L     (ExtStsDT).w,A5               | A5 = port B ExtStatus slot
        MOVE.L  (ABusVars).w,A2                 | A2 = port B serial vars block
E_BOUT_OPEN_DECODE_TBL_CONT_3:
        LEA     E_BOUT_OPEN_DECODE_TBL_CONT_2_CONT_5(PC),A3 | A3 = SCC reset register table
        MOVEQ.L #0xA,D1                         | D1 = 10 = 5 reg/val pairs (close)
        BSR.B   FORMAT                          | write reset table to SCC
        LEA     E_BOUT_OPEN_DECODE_TBL_CONT_4(PC),A3 | A3 = stub-RTS handler
        MOVE.L  A3,(A4)                         | install stub at Lvl2DT slot
        MOVE.L  A3,(A5)                         | install stub at ExtStsDT slot
        ADDQ.L  #0x8,A4                         | skip to RX-avail slot
        MOVE.L  A3,(A4)+                        | stub RX-avail handler
        MOVE.L  A3,(A4)                         | stub RX-special handler
        MOVE.L  iconIDCC(A1),A0                 | A0 = dCtlStorage handle
        _DisposeHandle                          | free serial vars block
        CLR.L   iconIDCC(A1)                    | 20(A1) := 0
        CLR.L   (A2)                            | clear SerialVars/ABusVars head
E_BOUT_OPEN_DECODE_TBL_CONT_4:
        RTS                                     | stub: return immediately
        MOVEA.L (SerialVars_a).w,A2             | A2 -> port-A Serial driver private-storage ptr
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_5   | join Status common path
        MOVE.L  (ABusVars).w,A2                 | A2 = port B serial vars block
E_BOUT_OPEN_DECODE_TBL_CONT_5:
        LEA.L     26(A0),A0                     | A0 = csParam (CntrlParam+26)
        MOVEQ.L #-0x12,D0                       | D0 = -18 = statusErr
        MOVEQ.L #0x2,D1                         | D1 = 2 (csCode 2 = SerStatus)
        SUB     (A0)+,D1                        | compute csCode - 2 (Z=1 for csCode 2)
        BNE.B   E_BOUT_OPEN_DECODE_TBL_CONT_6   | not csCode 2 -> try csCode 9
        BSR.W   RETURNS_13                      | get serial driver status
        BSR.W   RETURNS_14                      | get RX buffer chars-available count
        CLR     (A0)+                           | CSParam[0] = 0 (errCount placeholder)
        MOVE    D0,(A0)                         | CSParam[2] = chars available
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_8   | return noErr via JIODone
E_BOUT_OPEN_DECODE_TBL_CONT_6:
        ADDQ.W  #0x6,D1                         | D1 += 6: csCode 8 path?
        BNE.B   E_BOUT_OPEN_DECODE_TBL_CONT_7   | not csCode 8 -> exit with statusErr
        MOVE    24(A2),(A0)+                    | CSParam[0] = error counters
        CLR.B   24(A2)                          | reset error count
        MOVE.L  26(A2),(A0)+                    | CSParam[2..5] = port flags+config
E_BOUT_OPEN_DECODE_TBL_CONT_8:
        MOVEQ.L #0x0,D0                         | D0 = noErr
E_BOUT_OPEN_DECODE_TBL_CONT_7:
        MOVE.L  (JIODone).w,-(SP)               | push JIODone vector
        RTS                                     | dispatch to IODone
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A serial vars
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_10  | join control common path
        MOVE.L  (ABusVars).w,A2                 | A2 = port B serial vars
E_BOUT_OPEN_DECODE_TBL_CONT_10:
        LEA.L     26(A0),A0                     | A0 = csCode in CntrlParam
        MOVE    (A0)+,D1                        | D1 = csCode
        SUBQ.W  #0x1,D1                         | csCode == 1 (KillIO)?
        BNE.B   E_BOUT_OPEN_DECODE_TBL_CONT_9   | no -> try other csCodes
        CLR     26(A2)                          | clear pending byte counter
        CLR.L   0x2C(A2)                        | clear input/output queue ptrs
        RTS                                     | return: KillIO done
E_BOUT_OPEN_DECODE_TBL_CONT_9:
        SUBQ.W  #0x7,D1                         | csCode == 8 (SerSetBuf)?
        BNE.B   E_BOUT_OPEN_DECODE_TBL_CONT_13  | no -> try csCode 9
        MOVE    (A0)+,D4                        | D4 = new SerConfig word
        CMP     0x2A(A2),D4                     | same as current config?
        BEQ.B   E_BOUT_OPEN_DECODE_TBL_CONT_11  | unchanged -> noErr
        BSR.W   DRIVER_BOUT_CONT_CONT_3         | reprogram SCC with new config
E_BOUT_OPEN_DECODE_TBL_CONT_11:
        MOVEQ.L #0x0,D0                         | D0 = noErr
E_BOUT_OPEN_DECODE_TBL_CONT_12:
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_7   | return noErr via JIODone
E_BOUT_OPEN_DECODE_TBL_CONT_13:
        SUBQ.W  #0x1,D1                         | csCode == 9 (SerHShake)?
        BNE.B   GETFILEINFO_NO_10_CONT_2        | no -> try csCode 10
        PEA.L   E_BOUT_OPEN_DECODE_TBL_CONT_11(PC) | push noErr exit
        CLR.L   0x2C(A2)                        | clear handshake config
        MOVE.L  (A0)+,A4                        | A4 = handshake CSParam ptr
        MOVE    (A0),D1                         | D1 = handshake config word
        BNE.B   E_BINOUT_CONTROL_EMPTY_2        | nonzero -> install handshake
| MFS GetFileInfo: copy MFS directory entry to param block
E_BINOUT_CONTROL_CONT_5:
        LEA.L   0x30(A2),A4                     | A4 = param block result buffer
        MOVEQ.L #0x40,D1                        | D1 = directory entry size (64 bytes)
E_BINOUT_CONTROL_EMPTY_2:
        LEA.L     6(A2),A3                      | A3 = transmit-buffer slot in vars
        MOVE.L  A4,(A3)+                        | vars[6] = handshake buffer ptr
        MOVE    D1,(A3)+                        | vars[10] = config (XOFF char)
        LSR     #0x2,D1                         | D1 >>= 2 (XON char)
        MOVE    D1,(A3)+                        | vars[12] = XON char threshold
        MOVE    D1,(A3)+                        | vars[14] = XOFF threshold
        RTS                                     | return: handshake configured
GETFILEINFO_NO_10_CONT_2:
        SUBQ.W  #0x1,D1                         | csCode == 10 (SerSetBrk)?
        BNE.B   GETFILEINFO_NO_10_NO            | no -> try csCode 11
        ADDA.W  #0x10,A2                        | A2 += 16 (advance to break-buf)
        MOVE.L  (A0)+,(A2)+                     | copy break ptr/length 1
        MOVE    (A0)+,(A2)+                     | copy break length 2
        MOVE.B  (A0)+,(A2)                      | A0 = JFetch vector (get next byte)
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_11  | call subroutine via A0
GETFILEINFO_NO_10_NO:
        MOVE.B  0x28(A2),D0                     | write byte to SCC data register
        SUBQ.W  #0x1,D1                         | csCode == 11 (SerHShake) match?
        BEQ.B   GETFILEINFO_NO_10_CONT_3        | yes -> set break high
        BSET    #0x4,D0                         | set break-bit (WR5 bit 4 = SBRK)
        SUBQ.W  #0x1,D1                         | csCode == 12 (clear break)?
        BNE.B   GETFILEINFO_NO_10_NO_2          | no -> controlErr
GETFILEINFO_NO_10_CONT_3:
        BSR.B   RETURNS_11                      | A3 = SCC port write address
        MOVE.B  #0x5,(A3)                       | restore interrupts
        MOVE.L  (SP),(SP)                       | SCC settling delay
        MOVE.B  D0,(A3)                         | write WR5 with break bit modified
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_11  | branch to exit
GETFILEINFO_NO_10_NO_2:
        MOVEQ.L #-0x11,D0                       | D0 = -17 = controlErr
GETFILEINFO_NO_10_CONT_4:
        BRA.B   E_BOUT_OPEN_DECODE_TBL_CONT_12  | return result via JIODone
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A serial vars
        BRA.B   GETFILEINFO_NO_10_CONT_4_CONT   | join Prime common path
        MOVE.L  (ABusVars).w,A2                 | A2 = port B serial vars
GETFILEINFO_NO_10_CONT_4_CONT:
        MOVE    SR,-(SP)                        | save SR (preserve IPL)
        ORI     #0x300,SR                       | raise IPL=3 (mask SCC ints)
        BSR.B   RETURNS_12                      | test handshake state
        BNE.B   E_BOUT_PRIME_EXIT               | yes -> output blocked
| Transmit loop: send chars while SCC Tx buffer has room
E_BOUT_PRIME_LOOP:
        BSR.B   RETURNS_11                      | A3 = SCC port; test TX-empty bit
        BEQ.B   E_BOUT_PRIME_EXIT               | no -> output not blocked
        MOVE.B  23(A2),D0                       | D0 = pending out byte (XOFF, etc)
        CLR.B   23(A2)                          | clear pending out byte
        ANDI    #0xFF,D0                        | strip high bits, set Z flag
        BNE.B   E_BOUT_PRIME_CONT_2             | pending byte set -> use it
        MOVE.L  (JFetch).w,A0                   | A0 = JFetch vector (get next byte)
        JSR     (A0)                            | call subroutine via A0
E_BOUT_PRIME_CONT_2:
        MOVE.B  D0,4(A3)                        | A0 = current zone pointer (return value)
        TST     D0                              | test D0 (set N from D0[15])
        BMI.B   E_BOUT_PRIME_CONT_3             | end-of-stream -> mark idle
E_BOUT_PRIME_EXIT:
        ST      27(A2)                          | 27(A2) := -1 (true)
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTE                                     | restore SR and return
E_BOUT_PRIME_CONT_3:
        CLR.B   27(A2)                          | clear TX-active flag (idle)
        MOVE    (SP)+,SR                        | restore SR (re-enable ints)
E_BOUT_PRIME_DONE:
        MOVEQ.L #0x0,D0                         | D0 = noErr
        BRA.B   GETFILEINFO_NO_10_CONT_4        | return via JIODone
RETURNS_11:
        MOVEA.L (SCCRd).w,A3                    | A3 = SCC read base (from lowmem $1D8)
        ADDA.W  4(A2),A3                        | A3 += port offset (0 for A, 2 for B)
        BTST    #0x2,(A3)                       | test SCC RR0 bit 2 (TX buffer empty)
        ADDA.L  #0x00200001,A3                  | A3 += $00200001 (SCC write base delta + 1)
        RTS                                     | return Z = !TXempty, A3 = TX addr
RETURNS_12:
        TST.B   16(A2)                          | vars[$10]: software handshake on?
        BEQ.B   E_BOUT_PRIME_NO                 | no -> check hardware
        TST.B   29(A2)                          | vars[$1D]: XOFF received?
        BNE.B   E_BOUT_PRIME_OK                 | yes -> output blocked
E_BOUT_PRIME_NO:
        TST.B   17(A2)                          | vars[$11]: hardware CTS handshake?
        BEQ.B   E_BOUT_PRIME_NO_2               | no -> not blocked
        TST.B   28(A2)                          | vars[$1C]: CTS state (1=clear)?
        BEQ.B   E_BOUT_PRIME_NO_2               | CTS asserted -> not blocked
E_BOUT_PRIME_OK:
        MOVEQ.L #0x1,D0                         | D0 = 1 = blocked
        RTS                                     | return Z=0 (blocked)
E_BOUT_PRIME_NO_2:
        MOVEQ.L #0x0,D0                         | D0 = 0 = not blocked
        RTS                                     | return Z=1 (not blocked)
SCCInt_BOutEmpty:
        MOVE.L  (ABusVars).w,A2                 | A2 = port B serial vars
        BRA.B   SCCINT_AOUTEMPTY_EMPTY          | join common TX-empty handler

| ----------------------------------------------------------
| SCCInt_AOutEmpty
| Called during boot.
SCCInt_AOutEmpty:
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A serial vars
SCCINT_AOUTEMPTY_EMPTY:
        TST.B   23(A2)                          | vars[$17]: pending out byte set?
        BNE.B   SCCINT_AOUTEMPTY_OK             | yes -> deliver pending byte
        TST.B   27(A2)                          | vars[$1B]: TX-active flag set?
        BEQ.B   SCCINT_AOUTEMPTY_NO             | idle -> reset TX interrupt
        BSR.B   RETURNS_12                      | test handshake state
        BNE.B   SCCINT_AOUTEMPTY_NO             | blocked -> reset TX interrupt
SCCINT_AOUTEMPTY_OK:
        MOVE.L  (A2),A1                         | A1 = DCE pointer
        MOVE    SR,-(SP)                        | save SR (preserve IPL)
        BRA.W   E_BOUT_PRIME_LOOP               | feed next byte to SCC
SCCINT_AOUTEMPTY_NO:
        MOVE.B  #0x28,(A1)                      | SCC WR0 = $28: reset TX interrupt
        RTS                                     | return from interrupt
SCCINT_AOUTEMPTY_OK_2:
        CLR.B   29(A2)                          | clear XOFF-received flag
SCCINT_AOUTEMPTY_CONT:                          | @ $28B4 (skip-CLR entry)
        TST.B   27(A2)                          | TX-active flag set?
        BNE.B   SCCINT_AOUTEMPTY_OK             | active -> resume transmit
        RTS                                     | return from interrupt
        MOVE.L  (SerialVars_a).w,A2             | A2 = port A serial vars
        BRA.B   GETFILEINFO_NO_8_CONT_CONT_4    | join common RX-status handler
        MOVE.L  (ABusVars).w,A2                 | A2 = port B serial vars
GETFILEINFO_NO_8_CONT_CONT_4:
        BSR.B   RETURNS_13                      | get serial driver status

E_BIN_PRIME_LOOP:
        MOVE    SR,-(SP)                        | save SR (enter critical section)
        ORI     #0x300,SR                       | raise IPL to 3 (mask SCC interrupts)
        CMP     0x2C(A2),D2                     | ring buffer empty? (read tail == write head)
        BEQ.B   E_BIN_PRIME_EMPTY               | yes -> mark empty, exit
        MOVE.B  0(A3,D2.W),D0                   | D0 = next byte from ring buffer
        ADDQ.W  #0x1,D2                         | advance read tail
        CMP     D3,D2                           | tail past end of buffer?
        BNE.B   E_BIN_PRIME_NO                  | no -> keep new tail
        MOVEQ.L #0x0,D2                         | yes -> wrap tail to 0
E_BIN_PRIME_NO:
        MOVE    D2,0x2E(A2)                     | store updated read tail back to SERDVars
        BSR.B   E_BIN_PRIME_CONT_4              | push JStash and return (saved-PC trampoline)
        MOVE    (SP)+,SR                        | restore SR (exit critical section)
        TST     D0                              | byte successfully fetched?
        BPL.B   E_BIN_PRIME_LOOP                | yes -> loop for next byte
        BSR.B   E_BIN_PRIME_CONT_2              | enter critical section + check XOFF state
        BRA.W   E_BOUT_PRIME_DONE               | done with input poll
E_BIN_PRIME_EMPTY:
        ST      26(A2)                          | 26(A2) := -1 (true)
        BRA.B   E_BIN_PRIME_CONT_3              | skip SR-save, fall into XOFF check
E_BIN_PRIME_CONT_2:
        MOVE    SR,-(SP)                        | save SR (enter critical section)
        ORI     #0x300,SR                       | raise IPL to 3
E_BIN_PRIME_CONT_3:
        TST.B   22(A2)                          | XOFF auto-handshake enabled?
        BEQ.B   E_BIN_PRIME_DONE                | no -> done
        BSR.B   RETURNS_13                      | load ring buffer state from SERDVars
        BSR.B   RETURNS_14                      | compute used bytes in ring buffer
        CMP     12(A2),D0                       | below low-water mark?
        BHI.B   E_BIN_PRIME_DONE                | branch if > (unsigned)
        BCLR    #0x7,25(A2)                     | clear "we sent XOFF" flag
        BEQ.B   E_BIN_PRIME_DONE                | already cleared -> done
        MOVE.B  18(A2),D0                       | D0 = XON char from SERDVars
        BSR.B   E_BIN_PRIME_CONT_7              | queue char for transmit
E_BIN_PRIME_DONE:
        MOVEQ.L #0x0,D0                         | return noErr
        RTE                                     | return from exception
E_BIN_PRIME_CONT_4:
        MOVE.L  (JStash).w,-(SP)                | push saved PC from JStash onto stack
        RTS                                     | jump to JStash (saved-PC trampoline)
E_BIN_PRIME_CONT_7:
        LEA.L     23(A2),A0                     | A0 = &SERDVars.flowControl byte
        TST.B   (A0)                            | already a pending TX char?
        BEQ.B   E_BIN_PRIME_NO_2                | no -> latch new char
E_BIN_PRIME_CONT_8:
        CLR.B   (A0)                            | clear pending-TX flag
E_BIN_PRIME_CONT_9:
        RTS                                     | return
E_BIN_PRIME_NO_2:
        MOVE.B  D0,(A0)                         | latch new TX char
        BSR.W   RETURNS_11                      | check transmit ready bit
        BEQ.B   E_BIN_PRIME_CONT_9              | not ready -> leave latched
        MOVE.B  D0,4(A3)                        | ready -> write directly to SCC data reg
        BRA.B   E_BIN_PRIME_CONT_8              | clear pending flag, return

| ----------------------------------------------------------
| RETURNS_13: load ring buffer state registers from SERDVars
| Returns: A3=buffer ptr, D3=size, D1=write head, D2=read tail
RETURNS_13:
        MOVEA.L  6(A2),A3                       | A3 = ring buffer base from SERDVars
        MOVE.W   10(A2),D3                      | D3 = ring buffer size
        MOVEM   0x2C(A2),D1-D2                  | D1=write head, D2=read tail
        RTS                                     | return
RETURNS_14:
        MOVE    D1,D0                           | D0 = write head
        SUB     D2,D0                           | D0 = head - tail (used bytes if no wrap)
        BCC.W   E_BIN_PRIME_DONE_2              | no underflow -> done
        ADD     D3,D0                           | wrap: add buffer size
E_BIN_PRIME_DONE_2:
        RTS                                     | return; D0 = ring-buffer used bytes
AOut_PollProc:
        MOVE.L  (PollStack).w,A4                | A4 = saved poll-stack base
        MOVE.L  (SP)+,(DskRtnAdr).w             | stash return PC in DskRtnAdr
| Poll loop: wait for disk byte, then transmit serial byte
AOUT_POLLPROC_CONT:
        TST.B   (A5)                            | disk byte ready?
        BMI.B   AOUT_POLLPROC_CONT_2            | yes -> service serial output queue
        MOVE.B  (A6),-(SP)                      | push disk byte (busy-wait)
        BRA.B   AOUT_POLLPROC_CONT              | loop until ready
AOUT_POLLPROC_CONT_2:
        CMPA.L  SP,A4                           | any pending serial bytes on stack?
        BEQ.B   AOUT_POLLPROC_EXIT              | no -> done
        SUBQ.W  #0x2,A4                         | step back two bytes
        MOVE.B  (A4),D0                         | D0 = byte to transmit
        LEA.L     (SerialVars_a).w,A3           | A3 = port-A SERDVars
        LEA.L   (0x9FFFFA).l,A0                 | LEA abs-long -> addr reg
        LEA.L   (0xBFFFFB).l,A1                 | LEA abs-long -> addr reg
        BSR.B   SCCINT_AINAVAIL_CONT_2          | process byte through SCC RX path
        BRA.B   AOUT_POLLPROC_CONT              | next iteration
AOUT_POLLPROC_EXIT:
        MOVE.L  (PollStack).w,SP                | restore caller stack
        MOVE.L  (DskRtnAdr).w,-(SP)             | push saved return PC back on stack
        RTS                                     | return to caller
SCCInt_BInAvail:
        LEA.L     (ABusVars).w,A3               | A3 = AppleTalk port-B SERDVars
        BRA.B   SCCINT_AINAVAIL_CONT            | join port-A code path
SCCInt_AInAvail:
        LEA.L     (SerialVars_a).w,A3           | A3 = port-A SERDVars
SCCINT_AINAVAIL_CONT:
        MOVE.B  4(A0),D0                        | D0 = SCC RR1 status byte
SCCINT_AINAVAIL_CONT_2:
        MOVE.L  (A3)+,A2                        | A2 = primary SERDVars from chain
        MOVE.L  (A3),A3                         | A3 = secondary SERDVars
        TST.B   16(A2)                          | XON/XOFF flow-control enabled?
        BEQ.B   SCCINT_AINAVAIL_NO              | no -> store byte directly
        MOVEQ.L #0x7F,D1                        | D1 = 0x7F mask (strip parity)
        AND.B   D0,D1                           | D1 = received char with parity stripped
        CMP.B   18(A2),D1                       | matches XON char?
        BEQ.W   SCCINT_AOUTEMPTY_OK_2           | yes -> resume transmit
        CMP.B   19(A2),D1                       | matches XOFF char?
        BNE.B   SCCINT_AINAVAIL_NO              | no flow-control char -> store byte
        ST      29(A2)                          | 29(A2) := -1 (true)
        BRA.B   SCCINT_AINAVAIL_DONE            | XOFF processed -> done

| ----------------------------------------------------------
| SCCINT_AINAVAIL_NO: store received byte - check if read is pending
SCCINT_AINAVAIL_NO:
        TST.B   26(A2)                          | breakpoint mode active?
        BEQ.B   SCCINT_AINAVAIL_NO_2            | no -> normal store
        MOVE.L  A3,A1                           | A1 = secondary SERDVars (for breakpoint)
        BSR.W   E_BIN_PRIME_CONT_4              | invoke breakpoint trampoline
        BPL.B   SCCINT_AINAVAIL_DONE            | handled -> done
        CLR.B   26(A2)                          | clear breakpoint mode
        BRA.W   E_BOUT_PRIME_DONE               | done with this byte
SCCINT_AINAVAIL_NO_2:
        BSR.W   RETURNS_13                      | load ring buffer state
        MOVE.B  D0,0(A3,D1.W)                   | store byte at ring buffer[head]
        ADDQ.W  #0x1,D1                         | advance write head
        CMP     D3,D1                           | head past end?
        BNE.B   SCCINT_AINAVAIL_SKIP_2          | no
        MOVEQ.L #0x0,D1                         | yes -> wrap head to 0
SCCINT_AINAVAIL_SKIP_2:
        CMP     D2,D1                           | head == tail (buffer full)?
        BNE.B   SCCINT_AINAVAIL_NO_3            | no -> store new head
        BSET    #0x0,24(A2)                     | yes -> set "buffer overrun" flag
        RTS                                     | drop byte, return
SCCINT_AINAVAIL_NO_3:
        MOVE.W   D1,44(A2)                      | store new write head
        TST.B   22(A2)                          | XOFF auto-handshake enabled?
        BEQ.B   SCCINT_AINAVAIL_DONE            | no -> done
        BSR.W   RETURNS_14                      | compute used bytes
        SUB     D0,D3                           | D3 = free bytes remaining
        CMP     14(A2),D0                       | above high-water mark?
        BCC.B   SCCINT_AINAVAIL_DONE            | no -> done
        BSET    #0x7,25(A2)                     | set "we sent XOFF" flag
        BNE.B   SCCINT_AINAVAIL_DONE            | already set -> done
        MOVE.B  19(A2),D0                       | A2 = SERDVars pointer
        BSR.W   E_BIN_PRIME_CONT_7              | queue XOFF for transmit
SCCINT_AINAVAIL_DONE:
        RTS                                     | return
SCCInt_BInSpcl:
        LEA.L     (ABusVars).w,A3               | A3 = AppleTalk port-B SERDVars
        BRA.B   SCCINT_AINSPCL_CONT             | join port-A handler
SCCInt_AInSpcl:
        LEA.L     (SerialVars_a).w,A3           | A3 = port-A SERDVars
SCCINT_AINSPCL_CONT:
        MOVE.B  #0x1,(A1)                       | evtNum = 11 (device driver event)
        MOVE.L  (A3)+,A2                        | A2 = primary SERDVars
        MOVE.L  (A3),A3                         | low byte = changed bits
        MOVE.B  (A0),D1                         | D1 = SCC RR0 status byte
        MOVEQ.L #0x70,D3                        | D3 = error-bits mask (parity/overrun/framing)
        AND.B   D3,D1                           | D1 = error bits only
        OR.B    D1,24(A2)                       | 24(A2) |= D1
        MOVE.B  4(A0),D0                        | D0 = SCC data byte
        MOVE.B  20(A2),D2                       | D2 = previous error bits
        EOR.B   D1,D2                           | D2 = bits that changed
        MOVE.B  #0x30,(A1)                      | reset error latch in SCC
        AND.B   D3,D2                           | mask to error bits only
        BEQ.W   SCCINT_AINAVAIL_NO              | no error change -> normal store
        TST.B   26(A2)                          | breakpoint mode?
        BEQ.B   SCCINT_AINAVAIL_DONE            | no -> done
        MOVEQ.L #-0x59,D0                       | D0 = framingErr (-89)
SCCINT_AINSPCL_ERR_2:
        MOVE.L  A3,A1                           | A1 = secondary SERDVars
        CLR.B   26(A2)                          | clear breakpoint mode
        BRA.W   E_BOUT_OPEN_DECODE_TBL_CONT_7   | return error to caller
SCCInt_BChng_BOut:
        LEA.L     (ABusVars).w,A3               | A3 = AppleTalk port-B SERDVars
        BRA.B   SCCINT_ACHNG_AOUT_CONT          | join port-A handler
SCCInt_AChng_AOut:
        LEA.L     (SerialVars_a).w,A3           | A3 = port-A SERDVars
SCCINT_ACHNG_AOUT_CONT:
        MOVE.L  (A3)+,A2                        | A2 = primary SERDVars
        MOVE.L  (A3),A3                         | A3 = secondary SERDVars
        MOVE.B  D1,D2                           | D2 = changed-bits copy
        AND.B   21(A2),D2                       | mask to enabled-event bits
        BEQ.B   SCCINT_ACHNG_AOUT_SKIP          | no enabled event -> skip post
        MOVEM.L D0/A0,-(SP)                     | save D0/A0 around _PostEvent
        MOVE    #0xB,A0                         | A0 = driverEvt (event class 11)
        ASL     #0x8,D0                         | D0 high byte = SCC data byte
        MOVE.B  D1,D0                           | D0 low byte = changed-bits
        SWAP    D0                              | move into PostEvent message word
        MOVE    24(A3),D0                       | merge SERDVars status word
        _PostEvent                              | post driver event
        MOVEM.L (SP)+,D0/A0                     | restore D0/A0
SCCINT_ACHNG_AOUT_SKIP:
        TST.B   D1                              | any change at all?
        BMI.B   SCCINT_ACHNG_AOUT_CONT_2        | break-detect bit -> error path
        LSL.B   #0x2,D0                         | shift CTS bit into N flag
        SMI     28(A2)                          | 28(A2) := (N == 1)
        BPL.W   SCCINT_AOUTEMPTY_CONT           | CTS asserted -> resume TX
        RTS                                     | return
SCCINT_ACHNG_AOUT_CONT_2:
        TST.B   D0                              | break-condition bit set?
        BMI.B   SCCINT_ACHNG_AOUT_ERR           | yes -> error
        MOVE.B  4(A0),D0                        | read SCC RR1 (clears latch)
        RTS                                     | return
SCCINT_ACHNG_AOUT_ERR:
        MOVEQ.L #-0x5A,D0                       | D0 = breakRecd (-90)
        TST.B   26(A2)                          | breakpoint mode?
        BNE.B   SCCINT_AINSPCL_ERR_2            | yes -> propagate error
        RTS                                     | return
