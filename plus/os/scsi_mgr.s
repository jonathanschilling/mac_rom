| SCSI Manager
|
| Implements the SCSI Manager trap (_SCSIDispatch $A815) for the
| Mac Plus NCR 5380 SCSI controller at SCSI_Base (0x580000).
|
| Public routines (sub-selectors of _SCSIDispatch):
| SCSIReset - reset the SCSI bus
| SCSIGet - arbitrate for the SCSI bus
| SCSISelect - select a SCSI target device
| SCSICmd - send a SCSI command block
| SCSIRead - read data from SCSI target (polled transfer)
| SCSIWrite - write data to SCSI target (polled transfer)
| SCSIComplete - complete a SCSI transaction, get status and message
| SCSIStat - get SCSI bus status
| SCSIInstall - install SCSI interrupt handler (stub on Mac Plus)
| SCSIRBlind - read data from SCSI target (blind/pseudo-DMA)
| SCSIWBlind - write data to SCSI target (blind/pseudo-DMA)
|
| Transfer instruction (TIB) opcodes for SCSIRead/SCSIWrite:
| scInc (1) - transfer with auto-increment
| scNoInc (2) - transfer without increment (single register)
| scAdd (3) - transfer with explicit address increment
| scMove (4) - block move transfer
| scLoop (5) - repeat previous TIB entry
| scNop (6) - no operation (skip 10 bytes)
| scStop (7) - end of TIB
| scComp (8) - compare (verify) transfer
|
| Register conventions established by SCSI_PROLOGUE (prologue):
| A3 = SCSI_Base ($580000, even bytes = NCR 5380 read ports)
| A4 = SCSI_Base+1 ($580001, odd bytes = NCR 5380 write ports)
| D7 = 0 (constant zero for clearing registers)
| D4 = transfer flags (bit 15: blind mode, bit 0: compare, $FF: write)
|
| NCR 5380 register access (offsets from A3/A4):
| +$00 sCDR Current Data / Output Data Register
| +$10 sICR Initiator Command Register (read: AIP/LA; write: BSY/SEL/ATN/ACK)
| +$20 sMR Mode Register (arbitration, DMA, target, parity)
| +$30 sTCR Target Command Register (assert I/O, C/D, MSG phase bits)
| +$40 sCSR Current SCSI Bus Status (BSY/SEL/REQ/MSG/C-D/I-O/RST/parity)
| +$50 sBSR Bus & Status Register (DMA end, phase match, IRQ, parity err)
| +$60 sIDR Input Data Register (latched bus data)
| +$70 sRESET Reset Parity/Interrupt (read) / Init DMA Rx Start (write)
|
| Register offsets: reads via A3 use the hwregs.inc equates
| sICR (+$10), sTCR (+$30) and sBSR (+$50); all other accesses
| (and every write via A4) use plain hex offsets, e.g. 0x40(A3)
| = sCSR read, 0x20(A4) = sMR write.
|
| References:
| Inside Macintosh: Devices, Ch 3: SCSI Manager
| NCR 5380 SCSI Protocol Controller datasheet
| MPW 1.0 SCSI.h, SCSIEqu.a
|
| _SCSIDispatch ($A815) entry point
| Extracts selector word from stack and dispatches to handler
| Stack on entry: ... params ... selector(W) returnAddr(L)
SCSIDispatch:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE    (SP)+,D0                        | pop selector word (0-10)
        MOVE.L  A0,-(SP)                        | push return address back below params
        LEA.L   SCSI_DT_RESET(PC),A0            | A0 -> dispatch branch table
        MOVE    D0,D1                           | save selector in D1 (for blind mode check)
        LSL     #0x2,D0                         | selector * 4 (each BRA.W is 4 bytes)
        JMP     0x0(A0,D0.W)                    | jump to dispatch table[selector]

| ----------------------------------------------------------
| _SCSIDispatch branch table - one BRA.W per selector
| Selector 0: SCSIReset
SCSI_DT_RESET:
        BRA     SCSIReset                       | execute SCSI bus reset operation

| ----------------------------------------------------------
| Selector 1: SCSIGet (arbitrate for SCSI bus)
SCSI_DT_GET:
        BRA     SCSIGet                         | execute SCSI bus arbitration

| ----------------------------------------------------------
| Selector 2: SCSISelect (select target device)
SCSI_DT_SELECT:
        BRA     SCSISelect                      | execute target device selection

| ----------------------------------------------------------
| Selector 3: SCSICmd (send command descriptor block)
SCSI_DT_CMD:
        BRA     SCSICmd                         | execute send command phase

| ----------------------------------------------------------
| Selector 4: SCSIComplete (get status + message, release bus)
SCSI_DT_COMPLETE:
        BRA     SCSIComplete                    | execute bus completion sequence

| ----------------------------------------------------------
| Selector 5: SCSIRead (polled read via TIB)
SCSI_DT_READ:
        BRA     SCSIRead                        | execute polled SCSI read operation

| ----------------------------------------------------------
| Selector 6: SCSIWrite (polled write via TIB)
SCSI_DT_WRITE:
        BRA     SCSIWrite                       | execute polled SCSI write operation

| ----------------------------------------------------------
| Selector 7: SCSIInstall (install interrupt handler - stub)
SCSI_DT_INSTALL:
        BRA     SCSIInstall                     | execute handler installation (stub)

| ----------------------------------------------------------
| Selector 8: SCSIRBlind (blind/pseudo-DMA read via TIB)
| D1=8 signals blind mode to SCSIRead (checked at SCSI_CHECK_BLIND)
SCSI_DT_RBLIND:
        BRA     SCSIRead                        | execute blind pseudo-DMA read

| ----------------------------------------------------------
| Selector 9: SCSIWBlind (blind/pseudo-DMA write via TIB)
SCSI_DT_WBLIND:
        BRA     SCSIWrite                       | execute blind pseudo-DMA write

| ----------------------------------------------------------
| Selector 10: SCSIStat (return bus status registers)
SCSI_DT_STAT:
        BRA.B   SCSIStat                        | execute status read operation

| ----------------------------------------------------------
| SCSIInstall - install SCSI interrupt handler
| Mac Plus has no SCSI interrupt wired, so this is a no-op stub
SCSIInstall:
        RTS                                     | return immediately (no interrupts on Plus)

| ----------------------------------------------------------
| SCSIStat - reads sBSR and sCSR but stores them at 8(SP)/9(SP): after
| SCSI_PROLOGUE (LINK + MOVEM.L of 9 regs) those are the high word of the
| saved D4 (restored by SCSI_EPILOGUE); the result at 8(A6) is not written
SCSIStat:
        BSR     SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
        MOVE.B  sBSR(A3),0x8(SP)                | sBSR -> 8(SP) = saved D4 bits 31-24, not the result
        MOVE.B  0x40(A3),0x9(SP)                | sCSR -> 9(SP) = saved D4 bits 23-16
        BRA.B   SCSI_RETURN_OK                  | return noErr, clean up 0 param bytes

| ----------------------------------------------------------
| SCSIReset - assert RST on SCSI bus for >25 usec, then release
SCSIReset:
        BSR     SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
        BSR     SCSI_ASSERT_RST                 | assert RST via sICR, delay, release, clear sMR
SCSI_RETURN_OK:
        MOVEQ.L #0x0,D0                         | return noErr
        BRA     SCSI_EPILOGUE                   | epilogue: clean up 0 param bytes from stack

| ----------------------------------------------------------
| SCSIGet - arbitrate for the SCSI bus
| Calls SCSI_ARBITRATE to perform NCR 5380 arbitration sequence
| Result in D0: 0=won arbitration, 2=lost/timeout
SCSIGet:
        BSR     SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
        BSR     SCSI_ARBITRATE                  | perform bus arbitration (sets D0)
        MOVE    D0,0x8(A6)                      | store result code in caller's param area
        BRA.B   SCSI_RETURN_OK                  | return noErr (result already in param)

| ----------------------------------------------------------
| SCSISelect - select a SCSI target device
| Param: 8(A6) = target SCSI ID (0-6)
| Result: 0xA(A6) = result code from selection
SCSISelect:
        BSR     SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
        MOVE    0x8(A6),D0                      | D0 = target SCSI ID
        BSR     SCSI_DO_SELECT                  | perform selection sequence
        MOVE    D0,0xA(A6)                      | store result code
        MOVEQ.L #0x2,D0                         | 2 bytes of params to remove from stack
        BRA     SCSI_EPILOGUE                   | epilogue

| ----------------------------------------------------------
| SCSICmd - send a SCSI command descriptor block to target
| Params: 0xA(A6) = pointer to CDB, 8(A6) = CDB length
SCSICmd:
        BSR     SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
        MOVE.L  0xA(A6),A2                      | A2 -> command descriptor block
        MOVE    0x8(A6),D2                      | D2 = CDB length in bytes
        BSR     SCSI_SEND_CDB                   | send CDB bytes in command phase
        MOVE    D0,0xE(A6)                      | store result code
        MOVEQ.L #0x6,D0                         | 6 bytes of params to remove from stack
        BRA     SCSI_EPILOGUE                   | epilogue

| ----------------------------------------------------------
| SCSIRead - read data from target using TIB instructions
| Also handles SCSIRBlind (selector 8) when D1 >= 8
| Param: 8(A6) = pointer to TIB array
SCSIRead:
        BSR     SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
SCSI_CHECK_BLIND:
        CMPI    #0x8,D1                         | selector >= 8? (SCSIRBlind/SCSIWBlind)
        BLT.B   SCSI_LOAD_TIB                   | no: polled mode
        BSET    #0xF,D4                         | set bit 15 of D4 = blind transfer mode
SCSI_LOAD_TIB:
        MOVE.L  0x8(A6),A1                      | A1 -> TIB instruction array
| TIB interpreter loop - fetch and dispatch each TIB instruction
| TIB entry: word opcode at (A1), long scParam1 at 2(A1), long scParam2 at 6(A1)
SCSI_TIB_LOOP:
        MOVE    (A1),D0                         | D0 = TIB opcode
        MOVE.L  0x2(A1),A2                      | A2 = scParam1 (buffer ptr or offset)
        MOVE.L  0x6(A1),D2                      | D2 = scParam2 (byte count or value)
        SUBQ.W  #0x1,D0                         | opcode 1? (scInc)
        BEQ.B   SCSI_scInc                      | dispatch to scInc implementation
        SUBQ.W  #0x1,D0                         | opcode 2? (scNoInc)
        BEQ.B   SCSI_scNoInc                    | dispatch to scNoInc implementation
        SUBQ.W  #0x1,D0                         | opcode 3? (scAdd)
        BEQ.B   SCSI_scAdd                      | dispatch to scAdd implementation
        SUBQ.W  #0x1,D0                         | opcode 4? (scMove)
        BEQ.B   SCSI_scMove                     | dispatch to scMove implementation
        SUBQ.W  #0x1,D0                         | opcode 5? (scLoop)
        BEQ.B   SCSI_scLoop                     | dispatch to scLoop implementation
        SUBQ.W  #0x1,D0                         | opcode 6? (scNop)
        BEQ.B   SCSI_scNOp                      | dispatch to scNOp implementation
        SUBQ.W  #0x1,D0                         | opcode 7? (scStop)
        BEQ.B   SCSI_scStop                     | dispatch to scStop implementation
        SUBQ.W  #0x1,D0                         | opcode 8? (scComp)
        BEQ.B   SCSI_scComp                     | dispatch to scComp implementation
        MOVEQ.L #0x4,D0                         | unknown opcode: return scBadParmsErr
        BRA.B   SCSI_TIB_EXIT                   | abort TIB loop due to error

| ----------------------------------------------------------
| scInc - transfer D2 bytes, then advance scParam1 pointer by D2
SCSI_scInc:
        BSR     SCSI_XFER_ENGINE                | perform SCSI data transfer (D2 bytes via A2)
        BNE.B   SCSI_TIB_EXIT                   | transfer error: exit TIB loop
        ADD.L   D2,0x2(A1)                      | advance scParam1 pointer by bytes transferred
        BRA.B   SCSI_scNOp                      | advance to next TIB entry

| ----------------------------------------------------------
| scNoInc - transfer D2 bytes without advancing buffer pointer
SCSI_scNoInc:
        BSR     SCSI_XFER_ENGINE                | perform SCSI data transfer (D2 bytes via A2)
        BNE.B   SCSI_TIB_EXIT                   | transfer error: exit TIB loop
        BRA.B   SCSI_scNOp                      | advance to next TIB entry (ptr unchanged)

| ----------------------------------------------------------
| scAdd - add scParam2 long value to the long at address scParam1
SCSI_scAdd:
        ADD.L   D2,(A2)                         | *(long*)scParam1 += scParam2
        BRA.B   SCSI_scNOp                      | advance to next TIB entry

| ----------------------------------------------------------
| scMove - copy long from address scParam1 to address scParam2
SCSI_scMove:
        MOVE.L  D2,A0                           | A0 = scParam2 (destination address)
        MOVE.L  (A2),(A0)                       | *(long*)scParam2 = *(long*)scParam1
        BRA.B   SCSI_scNOp                      | advance to next TIB entry

| ----------------------------------------------------------
| scLoop - decrement scParam2 counter; if >0, jump back by scParam1 offset
SCSI_scLoop:
        SUBQ.L  #0x1,D2                         | decrement loop counter
        BEQ.B   SCSI_scStop                     | counter reached 0: stop
        MOVE.L  D2,0x6(A1)                      | store decremented counter back in TIB
        ADDA.L  A2,A1                           | A1 += scParam1 (signed byte offset to target TIB)
        BRA.B   SCSI_TIB_LOOP                   | re-enter TIB interpreter at target entry

| ----------------------------------------------------------
| scStop - terminate TIB execution, return noErr
SCSI_scStop:
        MOVEQ.L #0x0,D0                         | return noErr
        BRA.B   SCSI_TIB_EXIT                   | exit TIB interpreter

| ----------------------------------------------------------
| scComp - compare SCSI data against memory buffer (verify mode)
| Sets D4 bit 0 to flag compare mode, then falls into scInc transfer
SCSI_scComp:
        MOVE.B  #0x1,D4                         | D4.B=1: compare mode (SCSI_XFER_ENGINE checks this)
        BRA.B   SCSI_scInc                      | use scInc transfer with compare logic

| ----------------------------------------------------------
| scNop - skip this TIB entry (advance A1 by 10 bytes = sizeof(SCSIInstr))
SCSI_scNOp:
        ADDA    #0xA,A1                         | advance past 10-byte TIB entry (2+4+4)
        BRA.B   SCSI_TIB_LOOP                   | fetch next TIB instruction

| ----------------------------------------------------------
| SCSI_TIB_EXIT - TIB interpreter exit: store result and return
SCSI_TIB_EXIT:
        MOVE    D0,0xC(A6)                      | store TIB result code in caller's param area
        MOVEQ.L #0x4,D0                         | 4 bytes of params to remove from stack
        BRA     SCSI_EPILOGUE                   | epilogue

| ----------------------------------------------------------
| SCSIWrite - write data to target using TIB instructions
| Also handles SCSIWBlind (selector 9) via same blind mode flag
| Param: 8(A6) = pointer to TIB array
SCSIWrite:
        BSR     SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
        ST.B    D4                              | D4 = 0xFF: flag write direction for SCSI_XFER_ENGINE
        BRA     SCSI_CHECK_BLIND                | enter TIB interpreter (checks D1 for blind)

| ----------------------------------------------------------
| SCSIComplete - complete SCSI transaction: read status + message bytes
| Params: 8(A6) = timeout (ticks), 0xC(A6) = ptr to message word,
| 0x10(A6) = ptr to status word
| Waits for target to enter status phase, reads status byte, then
| reads message-in byte. Returns scCommErr on timeout.
SCSIComplete:
        BSR.B   SCSI_PROLOGUE                   | set up frame, A3/A4 -> NCR 5380
        MOVE.L  (Ticks).w,D6                    | D6 = current tick count
        ADD.L   0x8(A6),D6                      | D6 = deadline = now + timeout parameter
| Poll loop: wait for status phase or handle unexpected phases
SCSI_CMPL_POLL:
        MOVEQ.L #0x0,D2                         | clear status accumulator
        BSR     SCSI_READ_STATUS                | try to read status byte (status phase)
        BEQ.B   SCSI_CMPL_GOT_STATUS            | success: got status byte in D2
        CMPI.B  #0x5,D0                         | phase error? (bus not in status phase)
        BNE.B   SCSI_CMPL_CHKTMO                | no: some other error, check timeout
        BSR     SCSI_HANDLE_BAD_PHASE           | handle unexpected phase (bit-bucket/pad data)
SCSI_CMPL_CHKTMO:
        CMP.L   (Ticks).w,D6                    | past deadline?
        BLE.B   SCSI_CMPL_STORE                 | yes: timeout, return scCommErr
        BRA.B   SCSI_CMPL_POLL                  | no: retry status phase

| ----------------------------------------------------------
| SCSI_CMPL_GOT_STATUS - status byte received; now read message-in byte
SCSI_CMPL_GOT_STATUS:
        MOVE.L  0x10(A6),A1                     | A1 -> caller's status word
        MOVE    D2,(A1)                         | store status byte from target
        BSR     SCSI_READ_MSGIN                 | read message-in byte into D2
        BNE.B   SCSI_CMPL_STORE                 | error: skip message storage
        MOVE.L  0xC(A6),A1                      | A1 -> caller's message word
        MOVE    D2,(A1)                         | store message-in byte from target
SCSI_CMPL_STORE:
        MOVE    D0,0x14(A6)                     | store result code in caller's param area
        MOVEQ.L #0xC,D0                         | 12 bytes of params to remove from stack
        BRA.B   SCSI_EPILOGUE                   | epilogue

| ----------------------------------------------------------
| SCSI_PROLOGUE - prologue for all SCSIDispatch handlers
| Sets up stack frame, saves registers, initializes NCR 5380 pointers
| Called by: SCSIStat, SCSIReset, SCSIGet, SCSISelect, SCSICmd (and 2 more)
SCSI_PROLOGUE:
        MOVE.L  (SP)+,A0                        | pop BSR return address (handler body)
        LINK    A6,#0x0                         | create stack frame
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers
        MOVE.L  #SCSI_Base,A3                   | A3 -> NCR 5380 read ports (even bytes)
        MOVE.L  #SCSI_Base+1,A4                 | A4 -> NCR 5380 write ports (odd bytes)
        MOVEQ.L #0x0,D7                         | D7 = 0 constant (used to clear registers)
        MOVEQ.L #0x0,D4                         | D4 = 0 (transfer flags: polled, read, no compare)
        JMP     (A0)                            | return to handler body

| ----------------------------------------------------------
| SCSI_EPILOGUE - epilogue for all SCSIDispatch handlers
| D0 = number of parameter bytes to remove from caller's stack
SCSI_EPILOGUE:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    D0,SP                           | remove D0 bytes of params from caller's stack
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
| SCSI_ARBITRATE - SCSIGet: arbitrate for the SCSI bus using NCR 5380
| Returns D0=0 if arbitration won, D0=2 (scCommErr) if lost/timeout
SCSI_ARBITRATE:
        MOVE.B  #0x80,(A4)                      | write sCDR: put our SCSI ID 7 (bit 7) on data bus
        MOVE.B  #0x1,0x20(A4)                   | write sMR: set arbitrate mode (bit 0)
        BTST    #0x6,sICR(A3)                   | read sICR bit 6: AIP (arbitration in progress)?
        BEQ     SCSI_ARB_FAIL                   | not set: arbitration failed to start
        BSR     SCSI_BUS_SETTLE                 | short delay (~50 bus-settle cycles)
        BTST    #0x5,sICR(A3)                   | read sICR bit 5: LA (lost arbitration)?
        BNE     SCSI_ARB_FAIL                   | lost: higher-priority device won
        MOVEQ.L #0x0,D0                         | clear D0 for ID comparison
        MOVEQ.L #0x0,D2                         | clear high byte for word-length CMP
        MOVE.B  (A3),D0                         | read sCDR: current data bus (all IDs asserted)
        MOVE.B  #0x80,D2                        | D2 = our ID bit (SCSI ID 7)
        EOR.B   D2,D0                           | remove our own bit from bus snapshot
        CMP     D0,D2                           | any remaining bits >= our ID?
        BLT.B   SCSI_ARB_FAIL                   | yes: higher ID present, we lose
        BTST    #0x5,sICR(A3)                   | re-check LA bit (lost arbitration during compare)
        BNE     SCSI_ARB_FAIL                   | lost: exit with error
        CLR     D0                              | D0 = 0: arbitration won
        RTS                                     | return to caller (D0=0 for success)

| ----------------------------------------------------------
| SCSI_ARB_FAIL - arbitration failed: clear mode register and return scCommErr
SCSI_ARB_FAIL:
        MOVE.B  D7,0x20(A4)                     | write sMR: clear arbitrate mode (D7=0)
        MOVE.B  #0x2,D0                         | D0 = scCommErr (2)
        RTS                                     | return to caller with error status

| ----------------------------------------------------------
| SCSI_DO_SELECT - SCSISelect: select target device after winning arbitration
| D0 = target SCSI ID (0-6) on entry
| Returns D0=0 if target responded, D0=2 (scCommErr) if timeout
SCSI_DO_SELECT:
        MOVEQ.L #0x1,D1                         | D1 = 1
        LSL.B   D0,D1                           | D1 = target ID bit mask (1 << target_id)
        MOVE.B  #0x4,0x10(A4)                   | write sICR: assert SEL (bit 2)
        BSR     SCSI_BUS_SETTLE                 | short delay for bus settle
        MOVE.B  #0x80,D2                        | D2 = our ID bit (SCSI ID 7)
        MOVE.B  D7,0x30(A4)                     | write sTCR: clear all phase bits
        OR.B    D2,D1                           | D1 = initiator | target ID bits on data bus
        MOVE.B  D1,(A4)                         | write sCDR: put both IDs on SCSI data bus
        MOVE.B  #0xD,0x10(A4)                   | write sICR: assert DATA BUS + SEL + BSY ($01|$04|$08)
        MOVE.B  D7,0x20(A4)                     | write sMR: exit arbitration mode
        MOVE.B  D7,0x40(A4)                     | write select-enable reg: clear (no reselection)
        MOVE.B  #0x5,0x10(A4)                   | write sICR: assert DATA BUS + SEL, release BSY
        BSR     SCSI_BUS_SETTLE                 | delay for target to detect SEL + its ID
        MOVEQ.L #0x7D,D1                        | D1 = 125: timeout loop count (~250 usec)
        BSR     SCSI_WAIT_BSY                   | wait for target BSY (sCSR bit 6)
        BNE.B   SCSI_SEL_RELEASE                | timeout: target did not respond
        BSR     SCSI_BUS_SETTLE                 | delay for bus settle after target BSY
        CLR     D0                              | D0 = 0: selection succeeded
SCSI_SEL_RELEASE:
        MOVE.B  D7,0x10(A4)                     | write sICR: release all (SEL, DATA BUS)
        RTS                                     | return to caller with status

| ----------------------------------------------------------
| SCSI_SEND_CDB - send SCSI command descriptor block (command phase)
| A2 -> CDB bytes, D2 = CDB length
| Sets TCR to command phase (C/D=1, I/O=0 => $02), then sends each
| byte with REQ/ACK handshake
| Returns D0=0 on success, D0=2 on timeout
SCSI_SEND_CDB:
        MOVE.B  #0x2,0x30(A4)                   | write sTCR: assert C/D (command phase: C/D=1, I/O=0)
        MOVE.L  #0xBA94,D1                      | D1 = 48,276: timeout counter for REQ wait
        BSR     SCSI_WAIT_PHASE_MATCH           | wait for target REQ (sCSR bit 5)
        BNE.B   SCSI_CDB_DONE                   | timeout: exit with error
        BSR     SCSI_VERIFY_PHASE               | verify bus phase matches expected (C/D set, I/O clear)
        BNE.B   SCSI_CDB_DONE                   | phase mismatch: target not in command phase
        SUBQ.W  #0x1,D2                         | D2 = byte count - 1 (for DBF loop)
| Send each CDB byte with REQ/ACK handshake
SCSI_CDB_BYTE_LOOP:
        MOVE.L  #0xBA94,D1                      | reset timeout counter for each byte
        MOVE.B  (A2)+,(A4)                      | write next CDB byte to sCDR (output data)
        MOVE.B  #0x1,0x10(A4)                   | write sICR: assert DATA BUS (drive data onto bus)
        BSR     SCSI_WAIT_PHASE_MATCH           | wait for target REQ (sCSR bit 5)
        BNE     SCSI_CDB_DONE                   | timeout waiting for REQ
        MOVE.B  #0x11,0x10(A4)                  | write sICR: assert DATA BUS + ACK ($01|$10)
        MOVE.L  #0xBA94,D1                      | reset timeout counter
        BSR     SCSI_WAIT_REQ_CLEAR             | wait for REQ deasserted (handshake complete)
        BNE     SCSI_CDB_DONE                   | timeout waiting for REQ release
        MOVE.B  D7,0x10(A4)                     | write sICR: release DATA BUS and ACK
        DBF     D2,SCSI_CDB_BYTE_LOOP           | loop for remaining CDB bytes
        CLR     D0                              | D0 = 0: all CDB bytes sent successfully
SCSI_CDB_DONE:
        RTS                                     | return to caller with status

| ----------------------------------------------------------
| SCSI_XFER_ENGINE - SCSI data transfer engine (used by scInc, scNoInc, scComp)
| A2 -> buffer, D2 = byte count
| D4 flags: bit 15 = blind mode, byte = 0xFF write, byte = 0x01 compare, byte = 0 read
| Both modes move the bytes through the pseudo-DMA port (SCSI_Base+$200);
| polled mode waits for DRQ (sBSR bit 6) before each byte, blind mode only before the first
SCSI_XFER_ENGINE:
        MOVEM.L D2/A1-A2,-(SP)                  | save work registers
        MOVEQ.L #0x1,D0                         | D0 = 1 (data-in TCR: I/O=1, C/D=0)
        TST.B   D4                              | write mode? (D4.B negative = $FF)
        BPL.B   SCSI_XFER_SET_TCR               | no: read or compare, TCR=1 is correct
        MOVEQ.L #0x0,D0                         | write mode: TCR=0 (data-out: I/O=0, C/D=0)
SCSI_XFER_SET_TCR:
        MOVE.B  D0,0x30(A4)                     | write sTCR: set bus phase for data transfer
        MOVE.L  #0x17528,D1                     | D1 = 95,528: long timeout for data phase
        BSR     SCSI_WAIT_PHASE_MATCH           | wait for target REQ (sCSR bit 5)
        BNE     SCSI_XFER_RETURN                | timeout: exit with error
        BSR     SCSI_VERIFY_PHASE               | verify REQ asserted and phase correct
        BNE     SCSI_XFER_RETURN                | phase error: target changed phase unexpectedly
        MOVE.B  #0x2,0x20(A4)                   | write sMR: enable DMA mode (bit 1)
        TST.B   D4                              | write mode?
        BMI.B   SCSI_XFER_WR_SETUP              | yes: go to write setup
| Read/compare setup: start DMA receive
        MOVE.B  D7,0x70(A4)                     | write sRESET: start initiator DMA receive
        BRA.B   SCSI_XFER_MODE_SEL              | go to transfer mode selection

| ----------------------------------------------------------
| SCSI_XFER_WR_SETUP - write mode DMA setup
SCSI_XFER_WR_SETUP:
        MOVE.B  #0x1,0x10(A4)                   | write sICR: assert DATA BUS (enable output)
        MOVE.B  D7,0x50(A4)                     | write sBSR: start DMA send
| SCSI_XFER_MODE_SEL - select polled vs blind transfer, then dispatch by direction
| Pseudo-DMA: access NCR 5380 at base+$200 for handshake-free byte I/O
SCSI_XFER_MODE_SEL:
        MOVE.L  A3,A0                           | A0 = SCSI read base (even)
        MOVE.L  A4,A1                           | A1 = SCSI write base (odd)
        MOVE    #0x200,D6                       | D6 = $200: pseudo-DMA offset
        ADDA    D6,A0                           | A0 -> pseudo-DMA read port (SCSI_Base+$200)
        ADDA    D6,A1                           | A1 -> pseudo-DMA write port (SCSI_Base+$201)
        MOVEQ.L #0x0,D0                         | clear result (noErr)
        MOVEQ.L #0x6,D3                         | D3 = bit 6: DMA request bit position in sBSR
        TST     D4                              | check D4.W: blind mode? (bit 15 set)
        BMI.B   SCSI_BLIND_FIRST_DRQ            | yes: blind transfer (no per-byte REQ poll)
| Polled transfer: check D4.B for direction
        TST.B   D4                              | D4.B: 0=read, 1=compare, $FF=write
        BEQ.B   SCSI_POLL_RD_LOOP               | 0: polled read
        BMI.B   SCSI_POLL_WR_LOOP               | negative ($FF): polled write
| Polled compare loop: read each byte and compare against buffer
SCSI_POLL_CMP_LOOP:
        BTst    D3,sBSR(A3)                     | poll sBSR bit 6: DMA request (byte available)?
        BEQ.B   SCSI_POLL_CMP_LOOP              | not yet: spin until DRQ
        MOVE.B  (A0),D1                         | read byte from pseudo-DMA port
        CMP.B   (A2)+,D1                        | compare with expected buffer byte
        BEQ.B   SCSI_POLL_CMP_NEXT              | match: continue
        MOVEQ.L #0x6,D0                         | mismatch: D0 = scCompareErr (6)
SCSI_POLL_CMP_NEXT:
        SUBQ.L  #0x1,D2                         | decrement byte count
        BNE.B   SCSI_POLL_CMP_LOOP              | more bytes: continue polling
        BRA.B   SCSI_XFER_EXIT_DMA              | done: exit transfer

| ----------------------------------------------------------
| SCSI_POLL_RD_LOOP - polled read loop: read bytes with DRQ polling
SCSI_POLL_RD_LOOP:
        BTst    D3,sBSR(A3)                     | poll sBSR bit 6: DMA request (byte available)?
        BEQ.B   SCSI_POLL_RD_LOOP               | not yet: spin until DRQ
        MOVE.B  (A0),(A2)+                      | read byte from pseudo-DMA port into buffer
        SUBQ.L  #0x1,D2                         | decrement byte count
        BNE.B   SCSI_POLL_RD_LOOP               | more bytes: continue
        BRA.B   SCSI_XFER_EXIT_DMA              | done: exit transfer

| ----------------------------------------------------------
| SCSI_POLL_WR_LOOP - polled write loop: write bytes with DRQ polling
SCSI_POLL_WR_LOOP:
        BTst    D3,sBSR(A3)                     | poll sBSR bit 6: DMA request (ready for byte)?
        BEQ.B   SCSI_POLL_WR_LOOP               | not yet: spin until DRQ
        MOVE.B  (A2)+,(A1)                      | write buffer byte to pseudo-DMA port
        SUBQ.L  #0x1,D2                         | decrement byte count
        BNE.B   SCSI_POLL_WR_LOOP               | more bytes: continue
        BRA.B   SCSI_WR_FINAL_DRQ               | done: wait for final DRQ then exit

| ----------------------------------------------------------
| SCSI_BLIND_FIRST_DRQ - blind transfer: first byte uses DRQ poll, rest are blind
| Blind: no DRQ check after the first byte - relies on device speed
SCSI_BLIND_FIRST_DRQ:
        BTst    D3,sBSR(A3)                     | poll sBSR bit 6: wait for first DRQ
        BEQ.B   SCSI_BLIND_FIRST_DRQ            | spin until first byte ready
        TST.B   D4                              | check direction: 0=read, 1=compare, $FF=write
        BEQ.B   SCSI_BLIND_RD_LOOP              | 0: blind read
        BMI.B   SCSI_BLIND_WR_LOOP              | negative: blind write
| Blind compare loop (no per-byte DRQ check after first byte)
SCSI_BLIND_CMP_LOOP:
        MOVE.B  (A0),D1                         | read byte from pseudo-DMA port (no DRQ check)
        CMP.B   (A2)+,D1                        | compare with expected buffer byte
        BEQ.B   SCSI_BLIND_CMP_NEXT             | match: continue
        MOVEQ.L #0x6,D0                         | mismatch: D0 = scCompareErr (6)
SCSI_BLIND_CMP_NEXT:
        SUBQ.L  #0x1,D2                         | decrement byte count
        BNE.B   SCSI_BLIND_CMP_LOOP             | more bytes: continue blind compare
        BRA.B   SCSI_XFER_EXIT_DMA              | done: exit transfer

| ----------------------------------------------------------
| SCSI_BLIND_RD_LOOP - blind read loop (no per-byte DRQ check)
SCSI_BLIND_RD_LOOP:
        MOVE.B  (A0),(A2)+                      | read byte from pseudo-DMA port into buffer
        SUBQ.L  #0x1,D2                         | decrement byte count
        BNE.B   SCSI_BLIND_RD_LOOP              | more bytes: continue
        BRA.B   SCSI_XFER_EXIT_DMA              | done: exit transfer

| ----------------------------------------------------------
| SCSI_BLIND_WR_LOOP - blind write loop (no per-byte DRQ check)
SCSI_BLIND_WR_LOOP:
        MOVE.B  (A2)+,(A1)                      | write buffer byte to pseudo-DMA port
        SUBQ.L  #0x1,D2                         | decrement byte count
        BNE.B   SCSI_BLIND_WR_LOOP              | more bytes: continue
| SCSI_WR_FINAL_DRQ - after write: wait for final DRQ (last byte accepted by 5380)
SCSI_WR_FINAL_DRQ:
        BTst    D3,sBSR(A3)                     | poll sBSR bit 6: final DRQ (last byte drained)?
        BEQ.B   SCSI_WR_FINAL_DRQ               | spin until 5380 accepts last byte
| SCSI_XFER_EXIT_DMA - transfer complete: exit DMA mode
SCSI_XFER_EXIT_DMA:
        MOVE.B  D7,0x20(A4)                     | write sMR: clear DMA mode (D7=0)
        MOVE.B  D7,0x10(A4)                     | write sICR: release DATA BUS and ACK
SCSI_XFER_RETURN:
        TST     D0                              | set Z flag from result code
        MOVEM.L (SP)+,D2/A1-A2                  | restore work registers
        RTS                                     | return to caller with Z flag reflecting status

| ----------------------------------------------------------
| SCSI_READ_STATUS - read status byte from target (status phase)
| Sets TCR to status phase (C/D=1, I/O=1, MSG=0 => $03), reads one byte
| Returns: D0=0 and status byte in D2 on success, D0=2 on timeout,
| D0=5 on phase error
SCSI_READ_STATUS:
        MOVE.B  #0x3,0x30(A4)                   | write sTCR: status phase (C/D=1, I/O=1)
        MOVE.L  #0xBA94,D1                      | timeout counter
        BSR     SCSI_WAIT_PHASE_MATCH           | wait for target REQ (sCSR bit 5)
        BNE.B   SCSI_RDSTAT_DONE                | timeout: return error
        BSR     SCSI_VERIFY_PHASE               | verify REQ asserted and bus in status phase
        BNE.B   SCSI_RDSTAT_DONE                | phase mismatch: return scPhaseErr
        MOVE.B  (A3),D2                         | read sCDR: status byte from target
        MOVE.B  #0x10,0x10(A4)                  | write sICR: assert ACK (bit 4) to complete handshake
        MOVE.L  #0xBA94,D1                      | reset timeout
        BSR     SCSI_WAIT_REQ_CLEAR             | wait for REQ deasserted (target saw our ACK)
        BNE     SCSI_RDSTAT_DONE                | timeout: return error
        MOVE.B  D7,0x10(A4)                     | write sICR: release ACK
        CLR     D0                              | D0 = 0: success
SCSI_RDSTAT_DONE:
        RTS                                     | return to caller with status

| ----------------------------------------------------------
| SCSI_READ_MSGIN - read message-in byte from target (message-in phase)
| Sets TCR to message-in phase (C/D=1, I/O=1, MSG=1 => $07), reads one byte
| Returns: D0=0 and message byte in D2, or D0=2/5 on error
SCSI_READ_MSGIN:
        MOVE.B  #0x7,0x30(A4)                   | write sTCR: message-in phase (MSG=1, C/D=1, I/O=1)
        MOVE.L  #0xBA94,D1                      | timeout counter
        BSR     SCSI_WAIT_PHASE_MATCH           | wait for target REQ (sCSR bit 5)
        BNE     SCSI_RDMSG_DONE                 | timeout: return error
        BSR     SCSI_VERIFY_PHASE               | verify REQ asserted and bus in message-in phase
        BNE.B   SCSI_RDMSG_DONE                 | phase mismatch: return error
        MOVEQ.L #0x0,D2                         | clear D2 for message byte
        MOVE.L  #0xBA94,D1                      | reset timeout
        MOVE.B  (A3),D2                         | read sCDR: message-in byte from target
        MOVE.B  #0x10,0x10(A4)                  | write sICR: assert ACK to complete handshake
        BSR     SCSI_WAIT_REQ_CLEAR             | wait for REQ deasserted
        BNE     SCSI_RDMSG_DONE                 | timeout: return error
        MOVE.B  D7,0x10(A4)                     | write sICR: release ACK
        CLR     D0                              | D0 = 0: success
SCSI_RDMSG_DONE:
        RTS                                     | return to caller with status

| ----------------------------------------------------------
| SCSI_READ_BUS_PHASE - read current bus phase from sCSR
| Returns phase bits (I/O + C/D) in D0, masked to 0x0C
| Used to detect which information transfer phase the target is in
SCSI_READ_BUS_PHASE:
        MOVE.B  0x40(A3),D0                     | read sCSR: current SCSI bus status
        ANDI.B  #0xC,D0                         | mask to I/O (bit 2) + C/D (bit 3) phase bits
        RTS                                     | return to caller with phase bits in D0

| ----------------------------------------------------------
| SCSI_BUS_SETTLE - short bus-settle delay (~50 iterations, ~20 usec)
| Used after signal changes to allow SCSI bus signals to stabilize
SCSI_BUS_SETTLE:
        MOVEQ.L #0x30,D0                        | D0 = 48: loop iterations
SCSI_SETTLE_LOOP:
        DBF     D0,SCSI_SETTLE_LOOP             | spin for ~50 iterations (bus settle time)
        RTS                                     | return from SCSI_SETTLE_LOOP

| ----------------------------------------------------------
| SCSI_ASSERT_RST - SCSI bus reset: assert RST for ~200 usec, then release
| Per SCSI spec, RST must be held at least 25 usec
SCSI_ASSERT_RST:
        MOVE    SR,-(SP)                        | save status register (interrupt state)
        ORI     #0x300,SR                       | disable all maskable interrupts during reset
        MOVE.B  #0x80,0x10(A4)                  | write sICR: assert RST (bit 7)
        MOVE    #0x64,D0                        | D0 = 100: delay loop count (~200 usec)
SCSI_RST_HOLD_LOOP:
        DBF     D0,SCSI_RST_HOLD_LOOP           | hold RST asserted for >25 usec
        MOVE.B  D7,0x10(A4)                     | write sICR: release RST
        MOVE    (SP)+,SR                        | restore interrupt state
        MOVE.L  #0x17528,D0                     | D0 = 95,528: post-reset recovery delay
SCSI_RST_RECOVER_LOOP:
        SUBQ.L  #0x1,D0                         | bus free delay: SCSI spec requires 800 msec
        BGT.B   SCSI_RST_RECOVER_LOOP           | spin until delay expires
        MOVE.B  D7,0x20(A4)                     | write sMR: clear mode register
        RTS                                     | return from SCSI_RST_RECOVER_LOOP

| ----------------------------------------------------------
| SCSI_WAIT_BSY - wait for target BSY asserted (selection response)
| Polls sCSR bit 6 (BSY) until set or D1 timeout expires
| Returns D0=0 if BSY detected, D0=2 (scCommErr) on timeout
SCSI_WAIT_BSY:
        CLR     D0                              | assume success
SCSI_BSY_POLL_LOOP:
        BTst    #0x6,0x40(A3)                   | read sCSR bit 6: BSY asserted by target?
        BNE.B   SCSI_BSY_POLL_DONE              | yes: target responded, exit with D0=0
        SUBQ.L  #0x1,D1                         | decrement timeout counter
        BNE.B   SCSI_BSY_POLL_LOOP              | not expired: keep polling
        MOVEQ.L #0x2,D0                         | timeout: D0 = scCommErr (2)
SCSI_BSY_POLL_DONE:
        TST     D0                              | set Z flag from result
        RTS                                     | return to caller with Z flag reflecting status

| ----------------------------------------------------------
| SCSI_WAIT_BSY_CLEAR - wait for BSY deasserted (bus free detection)
| Polls sCSR bit 6 (BSY) until clear or D1 timeout expires
| Returns D0=0 if bus free, D0=2 (scCommErr) on timeout
SCSI_WAIT_BSY_CLEAR:
        CLR     D0                              | assume success
SCSI_BFREE_POLL_LOOP:
        BTst    #0x6,0x40(A3)                   | read sCSR bit 6: BSY still asserted?
        BEQ     SCSI_BFREE_POLL_DONE            | cleared: bus is free, exit with D0=0
        SUBQ.L  #0x1,D1                         | decrement timeout counter
        BNE.B   SCSI_BFREE_POLL_LOOP            | not expired: keep polling
        MOVEQ.L #0x2,D0                         | timeout: D0 = scCommErr (2)
SCSI_BFREE_POLL_DONE:
        TST     D0                              | set Z flag from result
        RTS                                     | return to caller with Z flag reflecting status

| ----------------------------------------------------------
| SCSI_WAIT_REQ_CLEAR - wait for REQ deasserted (handshake complete)
| Polls sCSR bit 5 (REQ) until clear or D1 timeout
| Returns D0=0 on success, D0=2 (scCommErr) on timeout
SCSI_WAIT_REQ_CLEAR:
        CLR     D0                              | assume success
SCSI_REQCLR_POLL_LOOP:
        BTst    #0x5,0x40(A3)                   | read sCSR bit 5: REQ still asserted?
        BEQ     SCSI_REQCLR_POLL_DONE           | deasserted: handshake acknowledged, exit
        SUBQ.L  #0x1,D1                         | decrement timeout counter
        BNE.B   SCSI_REQCLR_POLL_LOOP           | not expired: keep polling
        MOVEQ.L #0x2,D0                         | timeout: D0 = scCommErr (2)
SCSI_REQCLR_POLL_DONE:
        TST     D0                              | set Z flag from result
        RTS                                     | return to caller with Z flag reflecting status

| ----------------------------------------------------------
| SCSI_WAIT_PHASE_MATCH - wait for REQ (despite the label: no phase test)
| Polls sCSR bit 5 (REQ) until set or D1 timeout; phase match (sBSR
| bit 3) is tested separately by SCSI_VERIFY_PHASE
| Returns D0=0 on match, D0=2 (scCommErr) on timeout
SCSI_WAIT_PHASE_MATCH:
        CLR     D0                              | assume success
SCSI_PMATCH_POLL_LOOP:
        BTst    #0x5,0x40(A3)                   | read sCSR bit 5: REQ asserted?
        BNE     SCSI_PMATCH_POLL_DONE           | yes: target requesting transfer, exit
        SUBQ.L  #0x1,D1                         | decrement timeout counter
        BNE.B   SCSI_PMATCH_POLL_LOOP           | not expired: keep polling
        MOVEQ.L #0x2,D0                         | timeout: D0 = scCommErr (2)
SCSI_PMATCH_POLL_DONE:
        TST     D0                              | set Z flag from result
        RTS                                     | return to caller with Z flag reflecting status

| ----------------------------------------------------------
| SCSI_HANDLE_BAD_PHASE - handle unexpected bus phase during SCSIComplete
| If target is not in status phase, bit-bucket data or pad bytes
| to force bus through to status phase. Loops until phase changes
| to MSG or bus error occurs.
| D3 is used to save/restore the current TCR across phase handling.
SCSI_HANDLE_BAD_PHASE:
        BSR.B   SCSI_WAIT_PHASE_MATCH           | wait for REQ (target has data to transfer)
        BNE.B   SCSI_BAD_PHASE_EXIT             | timeout: exit with error
        BTST    #0x3,sBSR(A3)                   | read sBSR bit 3: phase match?
        BNE.B   SCSI_BAD_PHASE_OK               | phase matches TCR: done, return noErr
        MOVE.B  sTCR(A3),D3                     | save current sTCR value in D3
        MOVE.B  0x40(A3),D2                     | read sCSR: get actual bus phase bits
        ASR.L   #0x2,D2                         | shift I/O and C/D bits down to bits 0-2
        ANDI.B  #0x7,D2                         | mask to phase bits (MSG/C-D/I-O)
        MOVE.B  D2,0x30(A4)                     | write sTCR: match target's actual phase
        BTST    #0x2,0x40(A3)                   | read sCSR bit 2: I/O direction?
        BEQ.B   SCSI_PAD_BYTE_OUT               | I/O=0 (data-out): pad bytes to target
| I/O=1 (data-in): bit-bucket incoming byte
        MOVE.B  (A3),D2                         | read sCDR: discard incoming data byte
        MOVE.B  #0x10,0x10(A4)                  | write sICR: assert ACK
        BRA.B   SCSI_BAD_PHASE_WAIT             | wait for handshake completion

| ----------------------------------------------------------
| SCSI_PAD_BYTE_OUT - pad byte to target (data-out phase during cleanup)
SCSI_PAD_BYTE_OUT:
        MOVE.B  #0x1,0x10(A4)                   | write sICR: assert DATA BUS
        MOVE.B  #0x1,(A4)                       | write sCDR: send pad byte (0x01)
        MOVE.B  #0x11,0x10(A4)                  | write sICR: assert DATA BUS + ACK ($01|$10)
SCSI_BAD_PHASE_WAIT:
        BSR.B   SCSI_WAIT_REQ_CLEAR             | wait for REQ deasserted (handshake done)
        BNE.B   SCSI_BAD_PHASE_EXIT             | timeout: exit with error
        MOVE.B  D7,0x10(A4)                     | write sICR: release ACK and DATA BUS
        MOVE.B  D3,0x30(A4)                     | restore original sTCR (status phase setting)
        BSR     SCSI_BUS_SETTLE                 | short delay for bus settle
        BTST    #0x3,sBSR(A3)                   | read sBSR bit 3: phase match now?
        BEQ.B   SCSI_HANDLE_BAD_PHASE           | no: loop, handle another unexpected byte
SCSI_BAD_PHASE_OK:
        CLR     D0                              | D0 = 0: phase matched (reached status phase)
SCSI_BAD_PHASE_EXIT:
        RTS                                     | return from SCSI_BAD_PHASE_EXIT

| ----------------------------------------------------------
| SCSI_VERIFY_PHASE - verify bus is in expected phase (sBSR phase-match bit only; REQ is not tested)
| Checks sBSR bit 3 (phase match): if set, target phase matches TCR
| Returns D0=0 if phase correct, D0=5 (scPhaseErr) if mismatch
SCSI_VERIFY_PHASE:
        CLR     D0                              | assume success
        BTST    #0x3,sBSR(A3)                   | read sBSR bit 3: phase match?
        BNE.B   SCSI_VPHASE_DONE                | match: return noErr
        MOVEQ.L #0x5,D0                         | mismatch: D0 = scPhaseErr (5)
SCSI_VPHASE_DONE:
        TST     D0                              | set Z flag from result
        RTS                                     | return to caller with Z flag reflecting status

