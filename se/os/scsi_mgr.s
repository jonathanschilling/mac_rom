| SCSI Manager
|
| Apple sources: SCSIMgrInit.a and SCSIMgr.a (MacSEROM.lst module
| SCSISTUFF): INITSCSIMGR and the SCSI Manager trap (_SCSIDispatch
| $A815) for the NCR 5380 SCSI controller.
|
| Public routines (sub-selectors of _SCSIDispatch):
| SCSIReset - reset the SCSI bus
| SCSIGet - arbitrate for the SCSI bus
| SCSISelect - select a SCSI target device
| CMP_COPY_FROM_DISK - send a SCSI command block
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

| ----------------------------------------------------------
| INITSCSIMGR - SCSI Manager initialization (called once at boot)
| Allocates the SCSI globals block (0x74 bytes), populates the
| dispatch jump table from PC-relative offsets in SCSI_DISPATCH_OFFSETS, sets
| the host SCSI ID from XPRam parameter byte, and issues an initial
| SCSIReset to put the bus into a known state.
| Globals layout:
|   +0x00..+0x5F : 24 long absolute jump addresses (one per selector)
|   +0x60       : host SCSI ID mask byte (1 << host_id)
|   +0x61..    : runtime state (busy flag, last-reset tick, etc.)
SCSISTUFF:                                      | Apple source module (MacSEROM.lst)
INITSCSIMGR:
    MOVEQ.L     #0x74,D0                        | request 0x74 bytes for SCSI globals
    _NewPtrSysClear                             | _NewPtr in system zone, cleared
    BNE.B       SCSI_INIT_RTS                   | allocation failed -> bail
    MOVE.L      A0,D0                           | A0 = ptr to new block
    AND.L       (Lo3Bytes).W,D0                 | strip any tag bits from 24-bit address
    MOVEA.L     D0,A0                           | clean address back into A0
    MOVE.L      A0,(SCSIGlobals).W              | publish to SCSIGlobals lowmem
    MOVEQ.L     #0x17,D1                        | 23: 24 selector slots minus 1 (DBF)
    LEA.L       SCSI_DISPATCH_OFFSETS(PC),A1    | A1 -> dispatch offset table
    MOVE.L      A1,D0                           | D0 = PC base for offsets
SCSI_INIT_LOOP:
    MOVEQ.L     #0x0,D2                         | clear D2 (zero-extend below)
    MOVE.W      (A1)+,D2                        | fetch 16-bit selector offset
    ADD.L       D0,D2                           | D2 = absolute handler address
    MOVE.L      D2,(A0)+                        | store as long in globals
    DBF.W       D1,SCSI_INIT_LOOP               | next selector
    MOVE.W      D7,-(A7)                        | reserve a word on stack for XPRam read
    MOVEA.L     A7,A0                           | A0 -> stack scratch byte
    MOVE.L      #0x10002,D0                     | 1 byte from PRAM offset 2
    _ReadXPRam                                  | read XPRam config byte
    MOVE.B      (A7),D0                         | grab read result
    ANDI.B      #0x78,D0                        | mask SCSI-config nibble (bits 3..6)
    CMPI.B      #0x48,D0                        | already initialized signature?
    BEQ.B       SCSI_PRAM_OK                    | yes -> keep stored value
    MOVE.B      #0x4F,(A7)                      | no: write default 0x4F (host id 7)
    MOVEA.L     A7,A0                           | A0 -> updated value on stack
    MOVE.L      #0x10002,D0                     | 1 byte to PRAM offset 2
    _WriteXPRam                                 | persist new SCSI config byte
SCSI_PRAM_OK:
    MOVE.B      (A7),D0                         | reload final XPRam byte
    ANDI.B      #0x7,D0                         | low 3 bits = host SCSI ID
    MOVEQ.L     #0x1,D1                         | base bit
    LSL.B       D0,D1                           | D1 = 1 << host_id (ID mask)
    MOVEA.L     (SCSIGlobals).W,A0              | A0 -> globals
    MOVE.B      D1,0x60(A0)                     | store host ID mask in globals
    MOVE.B      D1,(SCSIDrvrs).W                | mirror in SCSIDrvrs lowmem
    CLR.W       -(A7)                           | push selector 0 = SCSIReset
    _SCSIDispatch                               | bring bus to known state via _SCSIDispatch
    ADDQ.L      #0x2,A7                         | drop selector word
SCSI_INIT_RTS:
    RTS                                         | return from INITSCSIMGR
| ----------------------------------------------------------
| _SCSIDispatch ($A815) trap entry - SE FDHD SCSI Manager
| Stack on entry: ... params ... selectorWord(W) returnAddr(L)
| 24 selectors total (vs 11 on Plus); SE adds SelAtn/MsgIn/MsgOut and
| reserves 14..23 for future use (all routed to SCSIunimplemented).
SCSIMGR:
    MOVEA.L     (A7)+,A0                        | pop return address
    MOVE.W      (A7)+,D0                        | pop selector word
    MOVE.L      A0,-(A7)                        | push return address back below params
    CMPI.W      #0x18,D0                        | selector >= 24?
    BCC.B       P_SCSIunimplemented             | yes -> SysError(scNotImpErr)
    BSR.W       SCSI_PROLOGUE                   | SCSI prologue: A3=SCSIBase, A4=SCSIGlobals
    MOVE.W      D0,D1                           | save selector in D1 for blind-mode test
    LSL.W       #0x2,D0                         | selector * 4 bytes/long
    MOVEA.L     0x0(A4,D0.W),A0                 | A0 = SCSIGlobals[selector] handler addr
    JMP         (A0)                            | dispatch to selector handler
| ----------------------------------------------------------
| Dispatch offset table - 24 word offsets relative to SCSI_DISPATCH_OFFSETS
| INITSCSIMGR converts these to absolute longs in SCSIGlobals[0..23].
| sel 0=SCSIReset(+0x46), 1=SCSIGet(+0x5C), 2=SCSISelect(+0x90),
| 3=CMP_COPY_FROM_DISK(+0xB8), 4=SCSIComplete(+0x168), 5=SCSIRead(+0xD6),
| 6=SCSIWrite(+0xD4), 7=SCSIInstall(+0x36), 8=SCSIRBlind(+0xD6),
| 9=SCSIWBlind(+0xD4), 10=SCSIStat(+0x38), 11=SCSISelAtn(+0x90),
| 12=SCSIMsgIn(+0x1BE), 13=SCSIMsgOut(+0x1D2), 14..23 -> +0x30 (unimplemented)
SCSI_DISPATCH_OFFSETS:
    .long       0x0046005C                      | sel 0,1: Reset, Get
    .long       0x009000B8                      | sel 2,3: Select, Cmd
    .long       0x016800D6                      | sel 4,5: Complete, Read
    .long       0x00D40036                      | sel 6,7: Write, Install
    .long       0x00D600D4                      | sel 8,9: RBlind, WBlind
    .long       0x00380090                      | sel 10,11: Stat, SelAtn
    .long       0x01BE01D2                      | sel 12,13: MsgIn, MsgOut
    .long       0x00300030                      | sel 14,15: -> unimplemented
    .long       0x00300030                      | sel 16,17: -> unimplemented
    .long       0x00300030                      | sel 18,19: -> unimplemented
    .long       0x00300030                      | sel 20,21: -> unimplemented
    .long       0x00300030                      | sel 22,23: -> unimplemented
| P_SCSIunimplemented - called from 1 place

| Selectors 14..23: any caller using a reserved selector lands here.
P_SCSIunimplemented:
    MOVEQ.L     #0xC,D0                         | dsCoreErr (12) - feature not implemented
    _SysError                                   | system error: should not return
SCSI_UNIMPL_HANG:
    BRA.B       SCSI_UNIMPL_HANG                | hang if SysError ever does return
| ----------------------------------------------------------
| Selector 7: SCSIInstall - on SE FDHD this is a no-op stub
| (interrupt-driven SCSI handler is wired into VIA2; nothing to do).
P_SCSIInstall:
    BRA.B       SCSI_RETURN_OK                  | -> epilogue, no result
| ----------------------------------------------------------
| Selector 10: SCSIStat - return NCR 5380 sBSR/sCSR as result word
P_SCSIStat:
    MOVE.B      0x50(A3),0x8(A6)                | sBSR (bus & status) -> high byte
    MOVE.B      0x40(A3),0x9(A6)                | sCSR (current SCSI bus status) -> low byte
    BRA.B       SCSI_RETURN_OK                  | -> epilogue, params already in place
| ----------------------------------------------------------
| Selector 0: SCSIReset - assert SCSI bus reset, clear busy flag
P_SCSIReset:
    BSR.W       SCSI_ASSERT_RST                 | toggle RST line; settle
    MOVE.W      D7,0x8(A6)                      | result word = noErr
    MOVE.B      D7,0x61(A4)                     | clear bus-busy flag in globals
    MOVE.W      D7,0x62(A4)                     | clear last-target / status word
SCSI_RETURN_OK:
    MOVEQ.L     #0x0,D0                         | 0 stack-param bytes to drop
    BRA.W       SCSI_EPILOGUE                   | restore regs and return
| ----------------------------------------------------------
| Selector 1: SCSIGet - arbitrate for the SCSI bus
| Wait while another driver owns the bus (busy flag), then mark
| ourselves busy and run the NCR 5380 arbitration sequence.
P_SCSIGet:
    MOVE.W      (TimeSCCDB).W,D1                | base loop count from calibrated tick
    MULU.W      #0x64,D1                        | * 100 ticks of wait budget
    MOVE.L      D1,D5                           | mirror into D5 for upper-word counter
    SWAP.W      D5                              | high half drives outer loop
SCSI_GET_WAIT:
    TST.B       0x61(A4)                        | someone else owns the bus?
    DBEQ.W      D1,SCSI_GET_WAIT                | spin while busy (low half)
    DBEQ.W      D5,SCSI_GET_WAIT                | spin while busy (high half)
    BEQ.B       SCSI_GET_TRY                    | bus free -> attempt arbitration
    MOVEQ.L     #0x7,D0                         | scBusTOErr - bus stayed busy
    BRA.B       SCSI_GET_STORE                  | store result and return
SCSI_GET_TRY:
    MOVE.B      #0x1,0x61(A4)                   | claim bus-busy flag
    BSR.W       SCSI_ARBITRATE                  | run NCR 5380 arbitrate sequence
    BEQ.B       SCSI_GET_STORE                  | won arbitration -> store noErr
    MOVE.B      D7,0x61(A4)                     | lost: release busy flag
SCSI_GET_STORE:
    MOVE.W      D0,0x8(A6)                      | store result code in caller's slot
    BRA.B       SCSI_RETURN_OK                  | -> epilogue (0 params to drop)
| ----------------------------------------------------------
| Selectors 2 (SCSISelect) and 11 (SCSISelAtn) - select target
| For SelAtn, set bit 31 of D0 to flag attention-assert mode to
| SCSI_DO_SELECT. Param: 0x8(A6) target SCSI ID; result: 0xA(A6).
P_SCSISelect_SelAtn:
    MOVEQ.L     #0x0,D0                         | clear ATN flag
    CMPI.W      #0xB,D1                         | selector 11 = SCSISelAtn?
    BNE.B       SCSI_SEL_GO                     | no -> plain select
    BSET        #0x1F,D0                        | yes: bit 31 = assert ATN during select
SCSI_SEL_GO:
    MOVE.W      0x8(A6),D0                      | low word: target SCSI ID
    MOVE.W      #0xFA,D6                        | 250-tick selection timeout
    BSR.W       SCSI_DO_SELECT                  | run selection sequence
    BEQ.B       SCSI_SEL_DONE                   | success
    MOVE.B      D7,0x61(A4)                     | failed: release bus-busy flag
SCSI_SEL_DONE:
    MOVE.W      D0,0xA(A6)                      | store result code
    MOVEQ.L     #0x2,D0                         | 2 param bytes to drop
    BRA.W       SCSI_EPILOGUE                   | -> epilogue
| ----------------------------------------------------------
| Selector 3: CMP_COPY_FROM_DISK - send a SCSI command descriptor block
| Params: 0xA(A6) = ptr to CDB, 0x8(A6) = CDB length; result: 0xE(A6)
P_SCSICmd:
    MOVEA.L     0xA(A6),A2                      | A2 -> CDB buffer
    MOVE.W      0x8(A6),D2                      | D2 = CDB length in bytes
    BSR.W       SCSI_SEND_CDB                   | send CDB during command phase
    BEQ.B       SCSI_CMD_DONE                   | success
    MOVE.B      D7,0x61(A4)                     | error: release bus-busy flag
SCSI_CMD_DONE:
    MOVE.W      D0,0xE(A6)                      | store result code
    MOVEQ.L     #0x6,D0                         | 6 param bytes to drop
    BRA.W       SCSI_EPILOGUE                   | -> epilogue
| ----------------------------------------------------------
| Selectors 5 (SCSIRead), 6 (SCSIWrite), 8 (SCSIRBlind), 9 (SCSIWBlind)
| Run the TIB (transfer-instruction-block) interpreter.
| D4: 0xFF (write), 0x00 (read); bit 15 = blind/pseudo-DMA mode.
| Param: 0x8(A6) = ptr to TIB array.
P_SCSIWrite:
    ST.B        D4                              | D4.B = 0xFF: flag write direction
P_SCSIRead:
    MOVEQ.L     #0x6,D3                         | D3 = bit-position 6 (sBSR REQ bit shift)
    CMPI.W      #0x8,D1                         | selector >= 8 -> blind?
    BLT.B       SCSI_READ_LOAD_TIB              | no -> polled mode
    BSET        #0xF,D4                         | yes: bit 15 = blind transfer
SCSI_READ_LOAD_TIB:
    MOVEA.L     0x8(A6),A1                      | A1 -> TIB array
    TST.B       D4                              | write direction?
    BMI.B       SCSI_TIB_LOOP                   | yes -> skip read-prep
    BSR.W       SCSI_PREP_READ                  | else: prep target into data-in phase
| TIB interpreter: 10-byte entries (opcode.W, scParam1.L, scParam2.L)
SCSI_TIB_LOOP:
    MOVEA.L     0x2(A1),A2                      | A2 = scParam1 (buffer ptr or src addr)
    MOVE.W      (A1),D0                         | D0 = TIB opcode
    MOVE.L      0x6(A1),D2                      | D2 = scParam2 (count or value)
    SUBQ.W      #0x1,D0                         | opcode 1? (scInc)
    BEQ.B       P_SCSI_scInc                    | -> scInc handler
    SUBQ.W      #0x1,D0                         | opcode 2? (scNoInc)
    BEQ.B       P_SCSI_scNoInc                  | -> scNoInc handler
    SUBQ.W      #0x1,D0                         | opcode 3? (scAdd)
    BEQ.B       P_SCSI_scAdd                    | -> scAdd handler
    SUBQ.W      #0x1,D0                         | opcode 4? (scMove)
    BEQ.B       P_SCSI_scMove                   | -> scMove handler
    SUBQ.W      #0x1,D0                         | opcode 5? (scLoop)
    BEQ.B       P_SCSI_scLoop                   | -> scLoop handler
    SUBQ.W      #0x1,D0                         | opcode 6? (scNOp)
    BEQ.B       P_SCSI_scNOp                    | -> scNOp handler
    SUBQ.W      #0x1,D0                         | opcode 7? (scStop)
    BEQ.B       P_SCSI_scStop                   | -> scStop handler
    SUBQ.W      #0x1,D0                         | opcode 8? (scComp)
    BEQ.B       P_SCSI_scComp                   | -> scComp handler
    MOVEQ.L     #0x4,D0                         | unknown: scBadParmsErr
    BRA.B       SCSI_TIB_EXIT                   | abort TIB
| scInc - transfer D2 bytes, advance scParam1 pointer by D2
P_SCSI_scInc:
    BSR.W       SCSI_XFER_ENGINE                | move D2 bytes via A2
    BNE.B       SCSI_TIB_EXIT                   | error -> abort
    ADD.L       D2,0x2(A1)                      | scParam1 += transferred bytes
    BRA.B       P_SCSI_scNOp                    | -> next TIB entry
| scNoInc - transfer D2 bytes without advancing scParam1
P_SCSI_scNoInc:
    BSR.W       SCSI_XFER_ENGINE                | move D2 bytes via A2 (ptr stays put)
    BNE.B       SCSI_TIB_EXIT                   | error -> abort
    BRA.B       P_SCSI_scNOp                    | -> next TIB entry
| scAdd - *(long*)scParam1 += scParam2
P_SCSI_scAdd:
    ADD.L       D2,(A2)                         | atomic add at A2 by D2
    BRA.B       P_SCSI_scNOp                    | -> next TIB entry
| scMove - *(long*)scParam2 = *(long*)scParam1
P_SCSI_scMove:
    MOVEA.L     D2,A0                           | A0 = scParam2 dest address
    MOVE.L      (A2),(A0)                       | copy long
    BRA.B       P_SCSI_scNOp                    | -> next TIB entry
| scLoop - decrement scParam2; if >0, jump back by scParam1 offset
P_SCSI_scLoop:
    SUBQ.L      #0x1,D2                         | --counter
    BEQ.B       P_SCSI_scStop                   | reached 0 -> stop
    MOVE.L      D2,0x6(A1)                      | store decremented counter
    ADDA.L      A2,A1                           | A1 += scParam1 (signed offset)
    BRA.B       SCSI_TIB_LOOP                   | re-enter at branch target
| scStop - terminate TIB execution, return noErr
P_SCSI_scStop:
    MOVEQ.L     #0x0,D0                         | noErr
    BRA.B       SCSI_TIB_EXIT                   | -> exit
| scComp - set compare-mode flag and fall into scInc
P_SCSI_scComp:
    MOVE.B      #0x1,D4                         | D4.B = 1: compare/verify mode
    BRA.B       P_SCSI_scInc                    | reuse scInc engine
| scNOp - advance A1 past current 10-byte TIB entry
| Called by: SCSI_TIB_LOOP, P_SCSI_scInc, P_SCSI_scNoInc, P_SCSI_scAdd, P_SCSI_scMove
P_SCSI_scNOp:
    ADDA.W      #0xA,A1                         | sizeof(SCSIInstr) = 10
    BRA.B       SCSI_TIB_LOOP                   | -> fetch next TIB
| TIB exit: clean up NCR 5380 state, store result
SCSI_TIB_EXIT:
    MOVE.B      D7,0x21(A3)                     | sMR = 0: leave DMA/arbitrate mode
    MOVE.B      D7,0x11(A3)                     | sICR = 0: release bus signals
    MOVE.W      D0,0xC(A6)                      | store result code
    MOVEQ.L     #0x4,D0                         | 4 param bytes to drop
    BRA.W       SCSI_EPILOGUE                   | -> epilogue
| ----------------------------------------------------------
| Selector 4: SCSIComplete - finish a transaction (status + msg-in)
| Params: 0x8(A6) timeout, 0xC(A6) ptr to message word,
|         0x10(A6) ptr to status word; result: 0x14(A6).
P_SCSIComplete:
    MOVE.W      D7,-(A7)                        | reserve status accumulator on stack
    MOVE.B      D7,0x21(A3)                     | sMR = 0: ensure not in DMA mode
    MOVE.L      (Ticks).W,D4                    | D4 = current tick count
    ADD.L       0x8(A6),D4                      | D4 = deadline (now + timeout)
SCSI_CMPL_POLL:
    MOVEQ.L     #0x0,D2                         | clear status byte accumulator
    BSR.W       SCSI_READ_STATUS                | try to read status phase byte
    BEQ.B       SCSI_CMPL_GOT_STATUS            | got it -> read msg-in
    CMPI.B      #0x5,D0                         | phase mismatch?
    BNE.B       SCSI_CMPL_CHKTMO                | other err: maybe timeout
    BSR.W       SCSI_HANDLE_BAD_PHASE           | drain unexpected phase
    BEQ.B       SCSI_CMPL_CHKTMO                | recovered: retry
    MOVE.W      D0,(A7)                         | save error in stack scratch
SCSI_CMPL_CHKTMO:
    CMP.L       (Ticks).W,D4                    | deadline still in future?
    BHI.B       SCSI_CMPL_POLL                  | yes -> retry status read
    MOVE.W      D0,(A7)                         | timed out: cache last err
    BRA.B       SCSI_CMPL_RESULT                | -> store and exit
SCSI_CMPL_GOT_STATUS:
    MOVEA.L     0x10(A6),A1                     | A1 -> caller's status word
    MOVE.W      D2,(A1)                         | store status byte
    BSR.W       SCSI_READ_MSGIN                 | read message-in byte into D2
    BEQ.B       SCSI_CMPL_GOT_MSG               | success
    MOVE.W      D0,(A7)                         | error: cache it
    BRA.B       SCSI_CMPL_CHKTMO                | retry-or-exit decision
SCSI_CMPL_GOT_MSG:
    MOVEA.L     0xC(A6),A1                      | A1 -> caller's message word
    MOVE.W      D2,(A1)                         | store msg-in byte
SCSI_CMPL_RESULT:
    MOVE.W      (A7)+,0x14(A6)                  | pop scratch -> caller's result
    MOVE.B      D7,0x61(A4)                     | release bus-busy flag
    MOVE.L      (Ticks).W,0x64(A4)              | record last-completion tick
    MOVEQ.L     #0xC,D0                         | 12 param bytes to drop
    BRA.B       SCSI_EPILOGUE                   | -> epilogue
| ----------------------------------------------------------
| Selector 12: SCSIMsgIn - read one message-in byte from target
| Param: 0x8(A6) = ptr to caller's message word; result: 0xC(A6).
P_SCSIMsgIn:
    BSR.W       SCSI_READ_MSGIN                 | D2 = msg byte
    BNE.B       SCSI_MSGIN_DONE                 | error: skip store
    MOVEA.L     0x8(A6),A1                      | A1 -> caller's message word
    MOVE.W      D2,(A1)                         | store msg byte
SCSI_MSGIN_DONE:
    MOVE.W      D0,0xC(A6)                      | store result code
    MOVEQ.L     #0x4,D0                         | 4 param bytes to drop
    BRA.B       SCSI_EPILOGUE                   | -> epilogue
| ----------------------------------------------------------
| Selector 13: SCSIMsgOut - send one message-out byte to target
| Param: 0x8(A6) = message byte; result: 0xA(A6).
P_SCSIMsgOut:
    MOVE.W      0x8(A6),D2                      | D2 = msg byte to send
    BSR.W       SCSI_SEND_MSGOUT                | drive message-out phase
    MOVE.W      D0,0xA(A6)                      | store result code
    MOVEQ.L     #0x2,D0                         | 2 param bytes to drop
    BRA.B       SCSI_EPILOGUE                   | -> epilogue
| ----------------------------------------------------------
| SCSI_PROLOGUE - common entry for all selector handlers
| Build a frame, save D2-D7/A2-A4, set A3=SCSIBase A4=SCSIGlobals,
| zero-init D7 and D4, then dispatch to the handler body via JMP (A0).
| Called by: SCSIMGR (after dispatch-table jump)
SCSI_PROLOGUE:
    MOVEA.L     (A7)+,A0                        | pop BSR return addr (handler body)
    LINK        A6,#-0x8                        | local frame: 8 bytes for saved BusErrorVector
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save callee-saved regs
    MOVEA.L     (SCSIBase).W,A3                 | A3 -> NCR 5380 base
    MOVEA.L     (SCSIGlobals).W,A4              | A4 -> SCSI globals
    MOVEQ.L     #0x0,D7                         | D7 = 0 (clear-register constant)
    MOVEQ.L     #0x0,D4                         | D4 = 0 (transfer flags: read, polled)
    JMP         (A0)                            | resume at handler body
| ----------------------------------------------------------
| SCSI_EPILOGUE - common exit for all selector handlers
| Restore registers, drop param bytes, return to caller of trap.
| D0 (input) = number of param bytes to drop from caller's stack.
SCSI_EPILOGUE:
    MOVEM.L     (A7)+,D2-D7/A2-A4               | restore callee-saved regs
    UNLK        A6                              | release frame
    MOVEA.L     (A7)+,A0                        | pop trap return address
    ADDA.W      D0,A7                           | drop D0 bytes of selector params
    JMP         (A0)                            | return to caller of _SCSIDispatch
| ----------------------------------------------------------
| SCSI_ARBITRATE - run NCR 5380 arbitration sequence
| Used by SCSIGet to win the bus. On success returns Z=1, D0=0.
| Returns scArbNBErr (3) on no bus-free, retries on lost arbitration.
| Sets sCDR with our ID mask, asserts ARB mode in sMR, polls AIP, then
| checks bus winner by XOR with our mask + carry comparison.
SCSI_ARBITRATE:
    LEA.L       0x10(A3),A0                     | A0 -> sICR (initiator command reg)
    MOVE.B      0x60(A4),0x1(A3)                | sCDR = host ID mask (assert our ID on bus)
SCSI_ARB_TRY:
    MOVEQ.L     #0x0,D1                         | clear D1 (zero-extend below)
    MOVE.W      (TimeSCCDB).W,D1                | base wait count from calibrated tick
    MULU.W      #0x64,D1                        | * 100 = arbitration timeout budget
    MOVE.L      D1,D5                           | mirror to D5
    SWAP.W      D5                              | high half drives outer loop
    MOVE.B      D7,0x21(A3)                     | sMR = 0: ensure arb cleared
    NOP                                         | bus settling delay
    MOVE.B      #0x1,0x21(A3)                   | sMR bit0 = 1: enable ARBITRATE mode
SCSI_ARB_WAIT_AIP:
    BTST        #0x6,(A0)                       | sICR bit 6 = AIP (arbitration in progress)?
    DBNE.W      D1,SCSI_ARB_WAIT_AIP            | spin while not AIP (low half)
    DBNE.W      D5,SCSI_ARB_WAIT_AIP            | spin while not AIP (high half)
    BNE.B       SCSI_ARB_GOT_AIP                | got AIP -> check winner
    MOVE.B      D7,0x21(A3)                     | timed out: clear sMR
    MOVEQ.L     #0x3,D0                         | scArbNBErr (no bus free / timeout)
    RTS                                         | return error
SCSI_ARB_GOT_AIP:
    BSR.W       SCSI_ARB_DELAY                  | arbitration delay (per SCSI spec, ~2.4us)
    BTST        #0x5,(A0)                       | sICR bit 5 = LA (lost arbitration)?
    BNE.B       SCSI_ARB_TRY                    | yes: retry
    MOVEQ.L     #0x0,D0                         | clear scratch for higher-priority cmp
    MOVEQ.L     #0x0,D2                         | clear winner ID accumulator
    MOVE.B      (A3),D0                         | sCDR read: bus IDs asserted
    MOVE.B      0x60(A4),D2                     | D2 = our ID mask
    EOR.B       D2,D0                           | clear our bit from observed IDs
    CMP.W       D0,D2                           | our mask >= remaining? (we have higher priority)
    BCS.B       SCSI_ARB_TRY                    | someone with higher ID present -> retry
    BTST        #0x5,(A0)                       | re-check LA after race window
    BNE.B       SCSI_ARB_TRY                    | lost: retry
    MOVEQ.L     #0x0,D0                         | won: noErr
    RTS                                         | return success
| ----------------------------------------------------------
| SCSI_DO_SELECT - select target SCSI device
| Inputs: D0 low word = target SCSI ID; D0 bit31 = assert-ATN flag
|         D6 = selection timeout in NCR 5380 ticks
| Output: D0 = result code (0=ok, 0x05=phase err, 0xC=selErr)
SCSI_DO_SELECT:
    LEA.L       0x11(A3),A0                     | A0 -> sICR write port
    MOVEQ.L     #0x1,D1                         | base bit
    LSL.B       D0,D1                           | D1 = 1 << target_id (target ID mask byte)
    MOVE.L      D0,D3                           | save D0 to D3 (preserves ATN flag in bit31)
    MOVE.B      #0x4,(A0)                       | sICR = BSY (de-assert) - prepare for sel
    BSR.W       SCSI_ARB_DELAY                  | settling delay before sel
    MOVE.B      0x60(A4),D2                     | D2 = host ID mask
    MOVE.B      D7,0x31(A3)                     | sTCR = 0: data-out phase signals
    OR.B        D2,D1                           | bus = target_mask | host_mask (both IDs)
    MOVE.B      D1,0x1(A3)                      | sCDR = target+host IDs (data out)
    MOVE.B      #0xD,D4                         | sICR pattern: BSY|SEL|DataBus (no ATN)
    TST.L       D3                              | check ATN flag (bit31 was set?)
    BPL.B       SCSI_SEL_NO_ATN                 | no ATN
    ORI.B       #0x2,D4                         | yes: also assert ATN bit
SCSI_SEL_NO_ATN:
    MOVE.B      D4,(A0)                         | sICR = sel-pattern (assert SEL+BSY+ATN?)
    MOVE.B      D7,0x21(A3)                     | sMR = 0: out of arb mode
    MOVE.B      D7,0x41(A3)                     | sCSR clear (clear status latches)
    BCLR        #0x3,D4                         | clear BSY bit (target should now drive BSY)
    MOVE.B      D4,(A0)                         | sICR = SEL only (target sees selection)
    BSR.W       SCSI_ARB_DELAY                  | post-deassert delay (BSY trans)
    MOVE.W      D6,D1                           | D1 = sel timeout
    BSR.W       SCSI_WAIT_BSY                   | wait for target to assert BSY
    BNE.B       SCSI_SEL_FAIL                   | timed out -> selErr
    BSR.W       SCSI_ARB_DELAY                  | settling delay before bus-free
    ANDI.B      #0xA,D4                         | keep only ATN+? (release SEL)
    MOVE.B      D4,(A0)                         | sICR = post-select state
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return success
SCSI_SEL_FAIL:
    MOVE.B      D7,(A0)                         | sICR = 0: release bus signals
    TST.W       D0                              | propagate D0 result code from SCSI_WAIT_BSY
    RTS                                         | return error
| ----------------------------------------------------------
| SCSI_SEND_CDB - send a SCSI command descriptor block
| Inputs: A2 -> CDB bytes, D2 = byte count
| Drives target through command phase using sICR/sCDR handshakes.
| Output: D0 = result code (0=ok, scCommErr/scPhaseErr on fault)
SCSI_SEND_CDB:
    MOVE.B      #0x2,0x31(A3)                   | sTCR = 2: assert C/D (command phase)
    BSR.W       SCSI_WAIT_REQ                   | wait for target REQ
    BNE.B       SCSI_CDB_DONE                   | error -> exit
    BSR.W       SCSI_CHECK_PHASE                | verify phase = command
    BNE.B       SCSI_CDB_DONE                   | mismatch -> exit
    SUBQ.L      #0x1,D2                         | DBF count: bytes - 1
SCSI_CDB_LOOP:
    MOVE.B      (A2)+,0x1(A3)                   | sCDR = next CDB byte
    MOVE.B      #0x1,0x11(A3)                   | sICR = ACK (handshake byte)
    BSR.W       SCSI_WAIT_REQ                   | wait for target REQ ack -> drop
    BNE.B       SCSI_CDB_DONE                   | error
    MOVE.B      #0x11,0x11(A3)                  | sICR = ACK + DataBus drive
    BSR.W       SCSI_WAIT_REQ_DROP              | wait for REQ to drop
    BNE.B       SCSI_CDB_DONE                   | error
    MOVE.B      D7,0x11(A3)                     | sICR = 0: release ACK
    DBF.W       D2,SCSI_CDB_LOOP                | next byte
    MOVEQ.L     #0x0,D0                         | noErr
SCSI_CDB_DONE:
    RTS                                         | return D0 = result
| ----------------------------------------------------------
| SCSI_XFER_ENGINE - main data-transfer engine for SCSIRead/Write
| Inputs: A2 = data buffer ptr, D2 = byte count,
|         D3 = REQ bit position (6, for sBSR & 0x40 polling),
|         D4 = transfer flags:
|              bit 15 set -> blind / pseudo-DMA mode
|              bit  7 set -> write direction (0xFF set by SCSIWrite)
|              bit  0 set -> compare/verify mode (set by scComp)
| The engine installs a bus-error trampoline (SCSI_BUSERR_HANDLER) so that an
| unexpected bus fault during the inner loop returns scBusError (9).
| It chooses one of four inner loops based on D4: blind DMA, polled
| read, polled write, or polled compare. After the loop, the bus-
| error vector is restored from -0x8(A6).
SCSI_XFER_ENGINE:
    MOVE.L      D2,D0                           | check byte count
    BEQ.W       SCSI_XFER_DONE                  | zero -> exit early
    MOVEM.L     D2/A1,-(A7)                     | save scratch regs
    MOVE.L      A7,-0x4(A6)                     | save SP for bus-error unwind
    MOVE.L      (BusErrorVector).W,-0x8(A6)     | save existing bus-err vector
    LEA.L       SCSI_BUSERR_HANDLER(PC),A0      | A0 -> our bus-error trampoline
    MOVE.L      A0,(BusErrorVector).W           | install temporary handler
    TST.B       D4                              | write direction?
    BPL.B       SCSI_XFER_WAIT_REQ              | no (read/compare) -> poll REQ
SCSI_XFER_WRITE_WAIT:
    BTST        #0x5,0x40(A3)                   | sBSR bit 5 = DMA REQ (DRQ)?
    BEQ.B       SCSI_XFER_WRITE_WAIT            | spin until target requests data
    BSR.W       SCSI_PREP_READ                  | enter DMA mode (write side)
    BRA.B       SCSI_XFER_PHASE_CHK             | -> phase verification
SCSI_XFER_WAIT_REQ:
    BTST        D3,0x50(A3)                     | sBSR bit 6 = REQ asserted?
    BNE.B       SCSI_XFER_DISPATCH              | got REQ -> begin transfer
    BTST        #0x5,0x40(A3)                   | sCSR bit 5 = bus disconnect / EOP?
    BEQ.B       SCSI_XFER_WAIT_REQ              | neither -> keep polling
SCSI_XFER_PHASE_CHK:
    BTST        #0x3,0x50(A3)                   | sBSR bit 3 = phase match?
    BNE.B       SCSI_XFER_DISPATCH              | yes -> dispatch transfer mode
    MOVEQ.L     #0x5,D0                         | scPhaseErr (phase mismatch)
    BRA.W       SCSI_XFER_RESTORE               | -> restore vector and exit
SCSI_XFER_DISPATCH:
    MOVEQ.L     #0x0,D0                         | clear result accumulator
    MOVE.L      D2,D5                           | mirror count to D5
    SWAP.W      D5                              | high half drives outer loop
    TST.W       D4                              | bit 15 set (blind / pseudo-DMA)?
    BMI.B       SCSI_XFER_BLIND                 | yes -> blind path
    TST.B       D4                              | direction?
    BPL.B       SCSI_XFER_RW_DEC                | byte-positive -> read or compare
    LEA.L       0x201(A3),A1                    | A1 -> sCDR write port (data-out)
    BRA.B       SCSI_XFER_W_NEXT                | -> polled write DBF (skip first body)
SCSI_XFER_RW_DEC:
    LEA.L       0x260(A3),A0                    | A0 -> sIDR read port (data-in)
    BEQ.B       SCSI_XFER_R_NEXT                | D4.B == 0 -> read DBF (skip first body)
    BRA.B       SCSI_XFER_C_NEXT                | D4.B != 0 -> compare/verify
SCSI_XFER_C_LOOP:
    BTST        D3,0x50(A3)                     | wait for REQ
    BEQ.B       SCSI_XFER_C_PHCHK               | no REQ -> check disconnect
    MOVE.B      (A0),D1                         | read data byte from target
    CMP.B       (A2)+,D1                        | compare with caller's buffer
    BEQ.B       SCSI_XFER_C_NEXT                | match -> continue
    MOVEQ.L     #0x6,D0                         | scCompareErr (verify mismatch)
SCSI_XFER_C_NEXT:
    DBF.W       D2,SCSI_XFER_C_LOOP             | next byte (low half)
    DBF.W       D5,SCSI_XFER_C_LOOP             | next byte (high half)
    BRA.W       SCSI_XFER_RESTORE               | done
SCSI_XFER_C_PHCHK:
    BTST        #0x3,0x50(A3)                   | phase still match?
    BNE.B       SCSI_XFER_C_LOOP                | yes -> retry REQ wait
    BRA.B       SCSI_XFER_R_PHERR               | no -> phase err
SCSI_XFER_R_LOOP:
    BTST        D3,0x50(A3)                     | wait for REQ
    BEQ.B       SCSI_XFER_R_PHCHK               | no REQ -> check disconnect
    MOVE.B      (A0),(A2)+                      | read data byte into buffer
SCSI_XFER_R_NEXT:
    DBF.W       D2,SCSI_XFER_R_LOOP             | next byte (low half)
    DBF.W       D5,SCSI_XFER_R_LOOP             | next byte (high half)
    BRA.B       SCSI_XFER_RESTORE               | done
SCSI_XFER_R_PHCHK:
    BTST        #0x3,0x50(A3)                   | phase still match?
    BNE.B       SCSI_XFER_R_LOOP                | yes -> retry REQ wait
SCSI_XFER_R_PHERR:
    MOVEQ.L     #0x5,D0                         | scPhaseErr
    BRA.B       SCSI_XFER_RESTORE               | done
SCSI_XFER_W_LOOP:
    BTST        D3,0x50(A3)                     | wait for REQ
    BEQ.B       SCSI_XFER_W_PHCHK               | no REQ -> check disconnect
    MOVE.B      (A2)+,(A1)                      | write data byte to target
SCSI_XFER_W_NEXT:
    DBF.W       D2,SCSI_XFER_W_LOOP             | next byte (low half)
    DBF.W       D5,SCSI_XFER_W_LOOP             | next byte (high half)
    BRA.B       SCSI_XFER_DRAIN                 | wait for drain after last byte
SCSI_XFER_W_PHCHK:
    BTST        #0x3,0x50(A3)                   | phase still match?
    BNE.B       SCSI_XFER_W_LOOP                | yes -> retry REQ wait
    MOVEQ.L     #0x5,D0                         | scPhaseErr
    BRA.B       SCSI_XFER_CLR                   | -> clear NCR regs and exit
SCSI_XFER_BLIND:
    LEA.L       0x260(A3),A0                    | A0 -> blind read port
    LEA.L       0x201(A3),A1                    | A1 -> blind write port
SCSI_XFER_BLIND_WAIT:
    BTST        D3,0x50(A3)                     | wait for REQ
    BEQ.B       SCSI_XFER_BLIND_WAIT            | spin
    TST.B       D4                              | direction?
    BEQ.B       SCSI_XFER_BLIND_R               | byte-zero -> blind read
    BMI.B       SCSI_XFER_BLIND_W               | byte-negative -> blind write
    BSR.B       SCSI_BLIND_COMPARE              | else: blind compare/verify
    BRA.B       SCSI_XFER_RESTORE               | done
SCSI_XFER_BLIND_R:
    BSR.B       SCSI_BLIND_READ                 | unrolled blind read
    BRA.B       SCSI_XFER_RESTORE               | done
SCSI_XFER_BLIND_W:
    BSR.W       SCSI_BLIND_WRITE                | unrolled blind write
SCSI_XFER_DRAIN:
    MOVE.W      (TimeSCCDB).W,D1                | drain timeout
SCSI_XFER_DRAIN_LOOP:
    BTST        D3,0x50(A3)                     | REQ still asserted? (more bytes pending)
    BNE.B       SCSI_XFER_CLR                   | yes -> exit (target stalled)
    BTST        #0x3,0x50(A3)                   | phase still match?
    BEQ.B       SCSI_XFER_CLR                   | no -> phase done, exit
    DBF.W       D1,SCSI_XFER_DRAIN_LOOP         | retry until timeout
    MOVEQ.L     #0x2,D0                         | scCommErr (drain timeout)
| Bus-error trampoline target re-enters here too.
| Called by: SCSI_XFER_DRAIN_LOOP, SCSI_BUSERR_HANDLER, SCSI_XFER_W_PHCHK
SCSI_XFER_CLR:
    MOVE.B      D7,0x21(A3)                     | sMR = 0: out of DMA mode
    MOVE.B      D7,0x11(A3)                     | sICR = 0: release bus signals
| Common exit: restore bus-error vector + saved regs, return D0
| Called by: SCSI_XFER_PHASE_CHK, SCSI_XFER_C_NEXT, SCSI_XFER_R_NEXT, SCSI_XFER_R_PHERR, SCSI_XFER_BLIND_WAIT (and 1 more)
SCSI_XFER_RESTORE:
    MOVE.L      -0x8(A6),(BusErrorVector).W     | restore prior bus-error vector
    MOVEM.L     (A7)+,D2/A1                     | restore scratch regs
    TST.W       D0                              | set CCR for caller (BEQ if noErr)
SCSI_XFER_DONE:
    RTS                                         | return D0 = result code
| ----------------------------------------------------------
| SCSI_BUSERR_HANDLER - bus-error trampoline installed during xfer
| If the inner loop touches a faulting address, the 68000 bus-error
| exception lands here. We unwind to the saved SP, set scBusError
| (9) or scPhaseErr (5) based on the bus state, then jump into the
| common cleanup path of SCSI_XFER_ENGINE.
SCSI_BUSERR_HANDLER:
    MOVEA.L     -0x4(A6),A7                     | restore SP from saved location
    MOVEQ.L     #0x9,D0                         | scBusError (data bus error)
    BTST        #0x3,0x50(A3)                   | phase match still?
    BNE.B       SCSI_XFER_CLR                   | yes -> bus err only
    MOVEQ.L     #0x5,D0                         | no: scPhaseErr
    BRA.B       SCSI_XFER_CLR                   | -> cleanup
| ----------------------------------------------------------
|
| SCSI_BLIND_CMP_LOOP / SCSI_BLIND_COMPARE -- compare-while-read loop
|
| For verify-after-write: reads byte from data port (A0) and
| compares against next byte at (A2)+. On any mismatch, sets
| D0 = scCompareErr (6). Two nested DBFs handle large counts.
|
SCSI_BLIND_CMP_LOOP:
    MOVE.B      (A0),D1                         | D1 = byte from SCSI data port
    CMP.B       (A2)+,D1                        | matches expected ?
    BEQ.B       SCSI_BLIND_COMPARE              | yes, continue
    MOVEQ.L     #0x6,D0                         | no, D0 = scCompareErr
SCSI_BLIND_COMPARE:
    DBF.W       D2,SCSI_BLIND_CMP_LOOP          | inner loop (low half)
    DBF.W       D5,SCSI_BLIND_CMP_LOOP          | outer loop (high half)
    RTS                                         | return from compare loop
| ----------------------------------------------------------
|
| SCSI_BLIND_READ -- pseudo-DMA fast read into A2
|
| D2 = byte count, D3 = stride shift, D7 = alignment bit.
| Reads 1 byte for alignment if needed, then unrolls MoveP.L
| instructions (16 longs = 64 bytes per iteration) to drain the
| NCR 5380 data port at maximum speed. Trailing tail bytes
| handled by SCSI_BLIND_READ_TAIL_BODY.
|
SCSI_BLIND_READ:
    MOVE.L      A2,D5                           | D5 = A2 (test alignment)
    BTST        D7,D5                           | aligned to long boundary ?
    BEQ.B       SCSI_BLIND_READ_ALIGNED         | yes, skip pre-byte
    MOVE.B      (A0),(A2)+                      | read 1 byte for alignment
    SUBQ.L      #0x1,D2                         | dec count
SCSI_BLIND_READ_ALIGNED:
    MOVE.L      D2,D1                           | D1 = byte count
    LSR.L       D3,D1                           | / 64 = chunk count
    BEQ.B       SCSI_BLIND_READ_TAIL_LOOP       | < 64 bytes left, tail loop only
    SUBQ.L      #0x1,D1                         | DBF needs count-1
    MOVEQ.L     #0x3F,D5                        | D5 = 63 mask
    AND.L       D5,D2                           | D2 = remaining tail bytes
    MOVE.L      D1,D6                           | D6 = chunk count
    SWAP.W      D6                              | hi half for outer DBF
SCSI_BLIND_READ_LOOP:

| ----------------------------------------------------------
| SCSI_BLIND_READ_LOOP inner-loop body: 16 unrolled (MoveP.L (A0),D5; MOVE.L D5,(A2)+)
| pairs read 16 long-words = 64 bytes from the NCR 5380 data port
| (A0, accessed via MoveP.L every other byte) into the buffer at
| (A2)+. The MoveP.L instructions are emitted as raw .byte 0x0B 0x48
| 0x00 0x00 because GNU as for m68k can't synthesize MoveP.L to/from
| an address register with displacement in the SE FDHD encoding form.
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +0..+3
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +4..+7
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +8..+11
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +12..+15
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +16..+19
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +20..+23
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +24..+27
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +28..+31
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +32..+35
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +36..+39
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +40..+43
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +44..+47
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +48..+51
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +52..+55
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +56..+59
    .byte 0x0B,0x48,0x00,0x00                   | MoveP.L $0(A0),D5
    MOVE.L      D5,(A2)+                        | store +60..+63
    DBF.W       D1,SCSI_BLIND_READ_LOOP         | inner loop (low half)
    DBF.W       D6,SCSI_BLIND_READ_LOOP         | outer loop (high half)
    BRA.B       SCSI_BLIND_READ_TAIL_LOOP       | go to tail loop
| Tail-byte loop: copy 1 byte at a time for the leftover
| (D2 + 1) bytes that didn't fit in a 64-byte unrolled chunk.
SCSI_BLIND_READ_TAIL_BODY:
    MOVE.B      (A0),(A2)+                      | read 1 byte from data port
SCSI_BLIND_READ_TAIL_LOOP:
    DBF.W       D2,SCSI_BLIND_READ_TAIL_BODY    | until tail exhausted
    RTS                                         | return from SCSI_BLIND_READ
| ----------------------------------------------------------
|
| SCSI_BLIND_WRITE -- pseudo-DMA fast write from A2 to A1
|
| D2 = byte count, D3 = stride shift, D7 = alignment bit.
| Symmetric to SCSI_BLIND_READ but writes A2-resident data to
| the NCR 5380 data port (A1) via 16x unrolled MoveP.L
| instructions per inner-loop iteration.
|
SCSI_BLIND_WRITE:
    MOVE.L      A2,D5                           | D5 = A2 (test alignment)
    BTST        D7,D5                           | aligned to long boundary ?
    BEQ.B       SCSI_BLIND_WRITE_ALIGNED        | yes, skip pre-byte
    MOVE.B      (A2)+,(A1)                      | write 1 byte for alignment
    SUBQ.L      #0x1,D2                         | dec count
SCSI_BLIND_WRITE_ALIGNED:
    MOVE.L      D2,D1                           | D1 = byte count
    LSR.L       D3,D1                           | / 64 = chunk count
    BEQ.B       SCSI_BLIND_WRITE_TAIL_LOOP      | < 64 bytes left, tail only
    SUBQ.L      #0x1,D1                         | DBF needs count-1
    MOVEQ.L     #0x3F,D5                        | D5 = 63 mask
    AND.L       D5,D2                           | D2 = remaining tail bytes
    MOVE.L      D1,D6                           | D6 = chunk count
    SWAP.W      D6                              | hi half for outer DBF
| ----------------------------------------------------------
| SCSI_BLIND_WRITE_LOOP inner-loop body: 16 unrolled (MOVE.L (A2)+,D5; MoveP.L D5,$0(A1))
| pairs send 16 long-words = 64 bytes from the buffer at (A2)+ to
| the NCR 5380 data port (A1, accessed via MoveP.L every other byte).
| The MoveP.L instructions are emitted as raw .byte 0x0B 0xC9 0x00 0x00
| because GNU as can't synthesize MoveP.L D5,$0(A1).
SCSI_BLIND_WRITE_LOOP:
    MOVE.L      (A2)+,D5                        | load +0..+3
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +4..+7
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +8..+11
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +12..+15
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +16..+19
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +20..+23
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +24..+27
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +28..+31
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +32..+35
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +36..+39
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +40..+43
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +44..+47
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +48..+51
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +52..+55
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +56..+59
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    MOVE.L      (A2)+,D5                        | load +60..+63
    .byte 0x0B,0xC9,0x00,0x00                   | MoveP.L D5,$0(A1)
    DBF.W       D1,SCSI_BLIND_WRITE_LOOP        | inner loop (low half)
    DBF.W       D6,SCSI_BLIND_WRITE_LOOP        | outer loop (high half)
    BRA.B       SCSI_BLIND_WRITE_TAIL_LOOP      | go to tail loop
| Tail-byte loop for SCSI_BLIND_WRITE.
SCSI_BLIND_WRITE_TAIL_BODY:
    MOVE.B      (A2)+,(A1)                      | write 1 byte to data port
SCSI_BLIND_WRITE_TAIL_LOOP:
    DBF.W       D2,SCSI_BLIND_WRITE_TAIL_BODY   | until tail exhausted
    RTS                                         | return from SCSI_BLIND_WRITE
| ----------------------------------------------------------
| SCSI_PREP_READ - prepare DMA mode for the next transfer
| Called from SCSI_XFER_ENGINE before write loops, and from blind
| paths before read/write. Sets sTCR phase, enables DMA mode in sMR,
| and primes either the read or write DMA start register based on D4.
SCSI_PREP_READ:
    MOVEQ.L     #0x1,D0                         | default phase = data-out
    TST.B       D4                              | direction?
    BPL.B       SCSI_PREP_PHASE                 | byte-positive (read or compare) -> data-in
    MOVEQ.L     #0x0,D0                         | byte-negative (write) -> data-out (overwrite)
SCSI_PREP_PHASE:
    MOVE.B      D0,0x31(A3)                     | sTCR = phase (0=data-out, 1=data-in)
    MOVE.B      #0x2,0x21(A3)                   | sMR = DMA mode bit
    TST.B       D4                              | direction?
    BMI.B       SCSI_PREP_WRITE                 | byte-negative -> write-side DMA prime
    MOVE.B      D7,0x71(A3)                     | sRESET write: start DMA recv
    RTS                                         | return from SCSI_PREP_PHASE
SCSI_PREP_WRITE:
    MOVE.B      #0x1,0x11(A3)                   | sICR bit 0 = ASSERT_DBUS (drive data lines)
    MOVE.B      D7,0x51(A3)                     | sBSR write: start DMA send
    RTS                                         | return from SCSI_PREP_WRITE
| ----------------------------------------------------------
| SCSI_READ_STATUS - read one status-phase byte from the target
| Sets sTCR for status phase, waits for REQ, reads status into D2,
| handshakes ACK, and waits for REQ to drop.
| Output: D0 = result (0=ok, 5=phase err, 2=timeout); D2 = status.
SCSI_READ_STATUS:
    MOVE.B      #0x3,0x31(A3)                   | sTCR = 3: status phase
    BSR.W       SCSI_WAIT_REQ                   | wait for target REQ
    BNE.B       SCSI_READ_STATUS_DONE           | timeout/error -> exit
    BSR.W       SCSI_CHECK_PHASE                | verify phase match
    BNE.B       SCSI_READ_STATUS_DONE           | mismatch -> exit
    MOVE.B      (A3),D2                         | sCDR read = status byte
    MOVE.B      #0x10,0x11(A3)                  | sICR = ACK (bit 4)
    BSR.W       SCSI_WAIT_REQ_DROP              | wait for REQ to drop
    BNE.B       SCSI_READ_STATUS_DONE           | timeout -> exit
    MOVE.B      D7,0x11(A3)                     | sICR = 0: release ACK
    MOVEQ.L     #0x0,D0                         | noErr
SCSI_READ_STATUS_DONE:
    RTS                                         | return D0 = result
| ----------------------------------------------------------
| SCSI_READ_MSGIN - read one message-in byte from the target
| Output: D0 = result, D2 = message byte (zero-extended)
SCSI_READ_MSGIN:
    MOVE.B      #0x7,0x31(A3)                   | sTCR = 7: message-in phase
    BSR.W       SCSI_WAIT_REQ                   | wait for REQ
    BNE.B       SCSI_READ_MSGIN_DONE            | error -> exit
    BSR.W       SCSI_CHECK_PHASE                | verify phase
    BNE.B       SCSI_READ_MSGIN_DONE            | mismatch -> exit
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.B      (A3),D2                         | sCDR read = msg byte
    MOVE.B      #0x10,0x11(A3)                  | sICR = ACK
    BSR.W       SCSI_WAIT_REQ_DROP              | wait for REQ to drop
    BNE.B       SCSI_READ_MSGIN_DONE            | timeout -> exit
    MOVE.B      D7,0x11(A3)                     | sICR = 0: release ACK
    MOVEQ.L     #0x0,D0                         | noErr
SCSI_READ_MSGIN_DONE:
    RTS                                         | return D0 = result
| ----------------------------------------------------------
| SCSI_SEND_MSGOUT - send one message-out byte to the target
| Input: D2 = byte to send; Output: D0 = result.
SCSI_SEND_MSGOUT:
    MOVE.B      #0x6,0x31(A3)                   | sTCR = 6: message-out phase
    BSR.W       SCSI_WAIT_REQ                   | wait for REQ
    BNE.B       SCSI_SEND_MSGOUT_DONE           | error -> exit
    BSR.W       SCSI_CHECK_PHASE                | verify phase
    BNE.B       SCSI_SEND_MSGOUT_DONE           | mismatch -> exit
    MOVE.B      #0x1,0x11(A3)                   | sICR bit 0 = drive data bus
    MOVE.B      D2,0x1(A3)                      | sCDR = msg byte to send
    MOVE.B      #0x11,0x11(A3)                  | sICR = ACK + drive
    BSR.W       SCSI_WAIT_REQ_DROP              | wait for target ACK
    BNE.B       SCSI_SEND_MSGOUT_DONE           | timeout -> exit
    MOVE.B      D7,0x11(A3)                     | sICR = 0: release bus
    MOVEQ.L     #0x0,D0                         | noErr
SCSI_SEND_MSGOUT_DONE:
    RTS                                         | return D0 = result
| ----------------------------------------------------------
| SCSI_ARB_DELAY - short busy-wait delay (~50 cycles)
| Used as the SCSI bus-settling delay after assertions.
| Called by: SCSI_SEL_NO_ATN, SCSI_ARB_GOT_AIP, SCSI_DO_SELECT, SCSI_BAD_PHASE_HANDSHAKE
SCSI_ARB_DELAY:
    MOVEQ.L     #0x30,D0                        | 48 iterations
SCSI_ARB_DELAY_LOOP:
    DBF.W       D0,SCSI_ARB_DELAY_LOOP          | spin
    RTS                                         | return from SCSI_ARB_DELAY_LOOP
| ----------------------------------------------------------
| SCSI_ASSERT_RST - assert SCSI bus RST line for >25us, then release
| Per SCSI spec, RST must be held >25us. Uses TimeDBRA / 8 ticks for
| the assertion window, masks all interrupts during reset, then waits
| TimeDBRA * 0x113 ticks for bus-free recovery.
SCSI_ASSERT_RST:
    MOVE.W      (TimeDBRA).W,D0                 | calibrated DBRA tick count
    LSR.W       #0x3,D0                         | / 8 -> ~25us window
    MOVE.W      SR,-(A7)                        | save status register
    ORI.W       #0x300,SR                       | IPL = 7 (mask all interrupts)
    MOVE.B      #0x80,0x11(A3)                  | sICR = RST (bit 7)
SCSI_RST_HOLD:
    DBF.W       D0,SCSI_RST_HOLD                | hold RST asserted
    MOVE.B      D7,0x11(A3)                     | sICR = 0: release RST
    TST.B       0x70(A3)                        | sRESET read: clear pending IRQ
    MOVE.W      (A7)+,SR                        | restore SR (re-enable IRQs)
    MOVE.W      (TimeDBRA).W,D0                 | recovery wait
    MULU.W      #0x113,D0                       | * 0x113 (= bus settle time)
    MOVE.L      D0,D5                           | mirror to D5
    SWAP.W      D5                              | high half drives outer loop
SCSI_RST_RECOVER:
    DBF.W       D0,SCSI_RST_RECOVER             | spin (low half)
    DBF.W       D5,SCSI_RST_RECOVER             | spin (high half)
    MOVE.B      D7,0x21(A3)                     | sMR = 0: out of any DMA mode
    RTS                                         | return from SCSI_RST_RECOVER
| ----------------------------------------------------------
| SCSI_WAIT_BSY - wait for target to assert BSY (selection ack)
| Input: D1 = base timeout in NCR ticks (caller scales)
| Output: D0 = 0 (BSY seen) or 2 (timeout)
SCSI_WAIT_BSY:
    MULU.W      (TimeSCCDB).W,D1                | scale by calibrated tick
    MOVE.L      D1,D5                           | mirror
    SWAP.W      D5                              | high half
    MOVEQ.L     #0x0,D0                         | clear result
SCSI_WAIT_BSY_LOOP:
    BTST        #0x6,0x40(A3)                   | sCSR bit 6 = BSY?
    DBNE.W      D1,SCSI_WAIT_BSY_LOOP           | spin until BSY (low half)
    DBNE.W      D5,SCSI_WAIT_BSY_LOOP           | spin until BSY (high half)
    BNE.B       SCSI_WAIT_BSY_DONE              | got BSY
    MOVEQ.L     #0x2,D0                         | scCommErr (timeout)
SCSI_WAIT_BSY_DONE:
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from SCSI_WAIT_BSY_DONE
| ----------------------------------------------------------
| SCSI_WAIT_BSY_DROP (unlabeled fallthrough copy in original ROM)
| Mirror of SCSI_WAIT_BSY but waits for BSY to drop instead of rise.
| Currently dead code (no callers) but preserved for byte-identity.
    MULU.W      (TimeSCCDB).W,D1                | scale by calibrated tick
    MOVE.L      D1,D5                           | mirror
    SWAP.W      D5                              | high half
    MOVEQ.L     #0x0,D0                         | clear result
SCSI_WAIT_BSY_DROP_LOOP:
    BTST        #0x6,0x40(A3)                   | sCSR bit 6 = BSY?
    DBEQ.W      D1,SCSI_WAIT_BSY_DROP_LOOP      | spin while BSY (low half)
    DBEQ.W      D5,SCSI_WAIT_BSY_DROP_LOOP      | spin while BSY (high half)
    BEQ.B       SCSI_WAIT_BSY_DROP_DONE         | BSY dropped
    MOVEQ.L     #0x2,D0                         | scCommErr (timeout)
SCSI_WAIT_BSY_DROP_DONE:
    TST.W       D0                              | set CCR
    RTS                                         | return from SCSI_WAIT_BSY_DROP_DONE
| ----------------------------------------------------------
| SCSI_WAIT_REQ_DROP - wait for target REQ (sBSR bit 5) to drop
| Output: D0 = 0 (drop seen) or 2 (timeout)
| Called by: SCSI_CDB_LOOP, SCSI_READ_STATUS, SCSI_READ_MSGIN, SCSI_SEND_MSGOUT, SCSI_BAD_PHASE_HANDSHAKE
SCSI_WAIT_REQ_DROP:
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.W      (TimeSCCDB).W,D1                | base timeout
    LSL.L       #0x4,D1                         | * 16 ticks
    MOVE.L      D1,D5                           | mirror
    SWAP.W      D5                              | high half
    MOVEQ.L     #0x0,D0                         | clear result
SCSI_WAIT_REQ_DROP_LOOP:
    BTST        #0x5,0x40(A3)                   | sCSR bit 5 = REQ asserted?
    DBEQ.W      D1,SCSI_WAIT_REQ_DROP_LOOP      | spin while asserted (low half)
    DBEQ.W      D5,SCSI_WAIT_REQ_DROP_LOOP      | spin while asserted (high half)
    BEQ.B       SCSI_WAIT_REQ_DROP_DONE         | REQ dropped
    MOVEQ.L     #0x2,D0                         | scCommErr (timeout)
SCSI_WAIT_REQ_DROP_DONE:
    TST.W       D0                              | set CCR
    RTS                                         | return from SCSI_WAIT_REQ_DROP_DONE
| ----------------------------------------------------------
| SCSI_WAIT_REQ - wait for target REQ (sBSR bit 5) to assert
| Output: D0 = 0 (REQ seen) or 2 (timeout)
| Called by: SCSI_SEND_CDB, SCSI_CDB_LOOP, SCSI_READ_STATUS, SCSI_READ_MSGIN, SCSI_SEND_MSGOUT (and 1 more)
SCSI_WAIT_REQ:
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.W      (TimeSCCDB).W,D1                | base timeout
    LSL.L       #0x4,D1                         | * 16 ticks
    MOVE.L      D1,D5                           | mirror
    SWAP.W      D5                              | high half
    MOVEQ.L     #0x0,D0                         | clear result
SCSI_WAIT_REQ_LOOP:
    BTST        #0x5,0x40(A3)                   | sCSR bit 5 = REQ asserted?
    DBNE.W      D1,SCSI_WAIT_REQ_LOOP           | spin until asserted (low half)
    DBNE.W      D5,SCSI_WAIT_REQ_LOOP           | spin until asserted (high half)
    BNE.B       SCSI_WAIT_REQ_DONE              | got REQ
    MOVEQ.L     #0x2,D0                         | scCommErr (timeout)
SCSI_WAIT_REQ_DONE:
    TST.W       D0                              | set CCR
    RTS                                         | return from SCSI_WAIT_REQ_DONE
| ----------------------------------------------------------
| SCSI_HANDLE_BAD_PHASE - drain unexpected bus phase to recover
| When the target enters a phase we didn't expect (e.g. msg-in or
| status during data-in), this routine reads/writes a single dummy
| byte to clear the REQ, restores the original sTCR, and retries the
| caller's phase. Cap of 10 retries enforced via a stack scratch.
SCSI_HANDLE_BAD_PHASE:
    MOVE.W      D7,-(A7)                        | reserve scratch on stack
SCSI_BAD_PHASE_LOOP:
    BSR.B       SCSI_WAIT_REQ                   | wait for any REQ
    BEQ.B       SCSI_BAD_PHASE_HAVE_REQ         | got REQ
    MOVE.W      D0,(A7)                         | save error code
    BRA.B       SCSI_BAD_PHASE_DONE             | exit
SCSI_BAD_PHASE_HAVE_REQ:
    BTST        #0x3,0x50(A3)                   | phase match (back to expected)?
    BEQ.B       SCSI_BAD_PHASE_DRAIN            | no -> drain a byte
    BRA.B       SCSI_BAD_PHASE_DONE             | yes -> done
SCSI_BAD_PHASE_DRAIN:
    MOVE.B      0x30(A3),D3                     | save sTCR (caller's phase)
    MOVE.B      0x40(A3),D2                     | sCSR
    ASR.L       #0x2,D2                         | shift bits 2..4 down
    ANDI.B      #0x7,D2                         | extract phase code
    MOVE.B      D2,0x31(A3)                     | sTCR = current target phase
    BTST        #0x2,0x40(A3)                   | I/O bit = 1 (in)?
    BEQ.B       SCSI_BAD_PHASE_OUT              | no -> out
    MOVE.B      (A3),D2                         | sCDR read: drain byte
    MOVE.B      #0x10,0x11(A3)                  | sICR = ACK
    BRA.B       SCSI_BAD_PHASE_HANDSHAKE        | -> drop ACK
SCSI_BAD_PHASE_OUT:
    MOVE.B      #0x1,0x11(A3)                   | sICR = drive
    MOVE.B      #0xEE,0x1(A3)                   | sCDR = pad value 0xEE
    MOVE.B      #0x11,0x11(A3)                  | sICR = ACK + drive
SCSI_BAD_PHASE_HANDSHAKE:
    MOVE.W      #0xA,(A7)                       | retry budget = 10 ticks
    BSR.W       SCSI_WAIT_REQ_DROP              | wait for target ACK
    BNE.B       SCSI_BAD_PHASE_DONE             | timeout
    MOVE.B      D7,0x11(A3)                     | release sICR
    MOVE.B      D3,0x31(A3)                     | restore caller's sTCR
    BSR.W       SCSI_ARB_DELAY                  | settle delay
    BTST        #0x3,0x50(A3)                   | back in caller's phase?
    BEQ.B       SCSI_BAD_PHASE_LOOP             | no -> drain another byte
SCSI_BAD_PHASE_DONE:
    MOVE.W      (A7)+,D0                        | pop result
    RTS                                         | return from SCSI_BAD_PHASE_DONE
| ----------------------------------------------------------
| SCSI_CHECK_PHASE - verify sBSR phase-match bit (bit 3)
| Output: D0 = 0 (match) or 5 (scPhaseErr)
SCSI_CHECK_PHASE:
    MOVEQ.L     #0x0,D0                         | default noErr
    BTST        #0x3,0x50(A3)                   | sBSR bit 3 = phase match?
    BNE.B       SCSI_CHECK_PHASE_DONE           | yes -> noErr
    MOVEQ.L     #0x5,D0                         | scPhaseErr
SCSI_CHECK_PHASE_DONE:
    TST.W       D0                              | set CCR for caller
    RTS                                         | return D0 = result
