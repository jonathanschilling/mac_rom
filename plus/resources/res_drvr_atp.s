| DRVR 10 - .ATP (AppleTalk Transaction Protocol) driver
| resource : 'DRVR' 10 '.ATP'
|
| ATP on top of DDP: every packet goes out with a WriteDDP call to the
| .MPP driver, and every ATP socket (responding sockets and the private
| socket of each SendRequest) has ATP_LISTENER as its DDP socket listener.
| Control calls (csCode - 249 indexes E_ATP_CONTROL_DISPATCH_TBL; csCodes
| from MPW 1.0 ATalkEqu, parameter blocks in Inside Macintosh II-315..319):
|   249 RelRspCB      RELRSPCB      cancel an exactly-once SendResponse
|   250 CloseATPSkt   CLOSEATPSKT   close a responding socket
|   251 AddResponse   ADDRESPONSE   send one more response packet
|   252 SendResponse  SENDRESPONSE  answer a request (BDS of packets)
|   253 GetRequest    GETREQUEST    wait for a request on a socket
|   254 OpenATPSkt    OPENATPSKT    open a responding socket
|   255 SendRequest   SENDREQUEST   send a request, collect responses
|   256 RelTCB        RELTCB        abort a SendRequest (reqAborted)
| 249-253 need an open responding socket in atpSocket (else badATPSkt).
| csCode 1 (killCode) returns at once; csCode < 0 (goodbye kiss, which
| _Launch does not send here: no dNeedGoodbye) closes .ATP on a 128K Mac
| (MemTop < $30000) and completes at once otherwise.
|
| Calls that cannot complete at once (GetRequest, SendRequest and an
| exactly-once SendResponse) are taken off the driver's I/O queue by
| ATP_DETACHREQ and completed later by ATP_COMPLETE; the driver goes on
| with the next queued call.  Calls to .MPP go through ATP_MPPCALL, an
| async _Control on one of three parameter blocks (CBs): the BSR to it
| returns to the caller's caller at once, and execution resumes after the
| BSR when .MPP completes the call (from ATP_MPPDONE, D0 = result).
|
| ATP header (atpHdSz = 8): +0 atpControl (bits 7-6 function: $40 TReq,
| $80 TResp, $C0 TRel; bit 5 XO, bit 4 EOM, bit 3 STS), +1 atpBitmap
| (TReq) / atpRespNo (TResp), +2 atpTransID, +4 atpUserData.
| atpFlags in the parameter block: bit 5 XO, 4 EOM, 3 STS, 1 tidValid,
| 0 sendCHK.
|
| ATPVars ($212 bytes, system heap; pointer in MPP variable atpVars =
| ABusVars+$1E, high byte = flag set by the .MPP Close):
|   +$00  6 bytes   request slots: socket of each SendRequest (0 = free)
|   +$06  6 longs   request slots: SendRequest parameter block
|   +$1E  6 words   request slots: transaction ID
|   +$2A  6 bytes   request slots: retry timer in seconds (0 = stopped)
|   +$30  6 bytes   responding sockets (OpenATPSkt; 0 = free)
|   +$36  6 longs   responding sockets: queue of waiting GetRequests
|   +$4E  6 longs   responding sockets: addrBlock filter (0 = any)
|   +$66  8 x 12    RspCBs (exactly-once responses): +0 socket (0 =
|                   free), +1 release timer (seconds), +2 requester
|                   address, +6 TID, +8 SendResponse (0 = none yet)
|   +$C6  long      .ATP DCE
|   +$CA  word      next transaction ID (seeded from Ticks)
|   +$CC  14 bytes  VBL task (ATP_VBLTASK, every 60 ticks)
|   +$DA, +$142, +$1AA: CBs of $68 bytes for the calls to .MPP:
|     +$00 IOParam (ioCompletion = ATP_MPPDONE, ioRefNum = .MPP refNum
|          while in use, 0 = free), +$1C socket, +$1D checksumFlag,
|     +$1E listener / wdsPointer, +$22 saved D1-D3/A0-A1, +$36 address
|     to resume at, +$3A WDS (header entry -> +$4F, 8 bytes -> +$60,
|     data entry, 0), +$4F DDP header template, +$60 ATP header
|

| resource header
    ROM_RESOURCE DRVR_10                        | 8-byte resource header (include/romrsrc.inc)
_DRVR_10_.ATP:
        DC.W    0x4400                          | drvrFlags: dNeedLock, dCtlEnable
  .short 0x0000                                 | drvrDelay (no periodic)
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x0018                                 | drvrOpen offset: E_ATP_Open
  .short 0x01D0                                 | drvrPrime offset: E_ATP_PrimeStatus
  .short 0x0066                                 | drvrCtl offset: E_ATP_Control
  .short 0x01D0                                 | drvrStatus offset: E_ATP_PrimeStatus
  .short 0x00EE                                 | drvrClose offset: E_ATP_Close
  .byte 0x04                                    | drvrName length

| Name
  .ascii ".ATP"                                 | drvrName

| end of Name
  .byte 0x20                                    | pad to word boundary

| .ATP Open: needs an open .MPP (ABusVars set); allocates ATPVars and
| installs the once-per-second VBL task.  A1 = .ATP DCE.
E_ATP_Open:
        MOVE.L  (ABusVars).w,A3                 | A3 = MPP variables
        MOVE.L  A3,D1                           | .MPP open?
        BEQ.B   E_ATP_OPEN_EXIT                 | no -> return
        TST.L   0x1E(A3)                        | atpVars already set?
        BNE.B   E_ATP_OPEN_EXIT                 | yes, .ATP already open -> return
| allocate ATPVars
        MOVE    #0x212,D0                       | $212 = 530 bytes
        _NewPtrSysClear                         | zeroed block in the system heap
        BRA.B   E_ATP_OPEN_CHECK                | skip the next word
  .byte 0xA3,0x1E                               | never executed: trap word $A31E (_NewPtr,CLEAR: application heap)
| E_ATP_OPEN_CHECK - test the result of _NewPtrSysClear
E_ATP_OPEN_CHECK:
        BNE.B   E_ATP_OPEN_EXIT                 | out of memory -> return
| initialize
        BSET    #0x4,(PortBUse).w               | atpLoadedBit (4): .ATP open
        MOVE.L  A0,0x1E(A3)                     | atpVars = ATPVars
        CLR.B   0x1E(A3)                        | clear its high (flag) byte
        MOVE.B  #0x13,0x7(A1)                   | dCtlQueue+1: driver version 19
| DCE pointer, TID seed and VBL task in ATPVars
        LEA.L   0xC6(A0),A2                     | A2 -> ATPVars+$C6
        MOVE.L  A1,(A2)+                        | +$C6 = .ATP DCE
        MOVE    (Ticks_LoWord).w,(A2)+          | +$CA = first transaction ID (from Ticks)
        MOVE.L  A2,A0                           | A0 = VBL task at +$CC
        ADDQ.W  #0x4,A2                         | skip qLink
        MOVE    #0x1,(A2)+                      | qType = vType (1)
        LEA.L   ATP_VBLTASK(PC),A1              | A1 = ATP_VBLTASK
        MOVE.L  A1,(A2)+                        | vblAddr
        MOVE    #0x3C,(A2)+                     | vblCount = 60 ticks (1 second)
        _VInstall                               | install the VBL task
E_ATP_OPEN_EXIT:
        RTS                                     | return from E_ATP_Open

| ----------------------------------------------------------
|
| E_ATP_Control
|
| .ATP Control: A0 = parameter block, A1 = .ATP DCE.  Dispatches
| csCode 249..256 through E_ATP_CONTROL_DISPATCH_TBL with A2 = ATPVars,
| D1.B = atpSocket, D2 = slot index of the responding socket (249-253),
| D3 = addrBlock and atpFlags masked to its flag bits.
E_ATP_Control:
        TST.L   (ABusVars).w                    | .MPP open?
        BNE.B   E_ATP_CONTROL_CSCODE            | yes ->
        MOVEQ.L #-0x11,D0                       | controlErr (-17)
E_ATP_CONTROL_IODONE:
        BRA     ATP_DONE_A1                     | -> IODone with D0
| dispatch on csCode
E_ATP_CONTROL_CSCODE:
        MOVE    0x1A(A0),D2                     | D2 = csCode
        BMI.B   E_ATP_CONTROL_GOODBYE           | negative: goodbye kiss ->
        SUBQ.W  #0x1,D2                         | csCode 1 (killCode)?
        BNE.B   E_ATP_CONTROL_RANGE             | no ->
        RTS                                     | KillIO: nothing to cancel, return
| csCode must be 249..256
E_ATP_CONTROL_RANGE:
        MOVEQ.L #-0x11,D0                       | controlErr (-17) if out of range
        SUBI    #0xF8,D2                        | D2 = csCode - 249 (after the -1 above)
        BLT.B   E_ATP_CONTROL_IODONE            | < 249 -> controlErr
        CMPI    #0x7,D2                         | > 256?
        BGT.B   E_ATP_CONTROL_IODONE            | yes -> controlErr
| handler address from the dispatch table
        ADD     D2,D2                           | word index
        LEA.L   E_ATP_CONTROL_DISPATCH_TBL(PC),A3 | A3 = dispatch table
        ADDA    D2,A3                           | A3 -> entry
        MOVE    (A3),A3                         | offset from the driver start
        LEA.L   _DRVR_10_.ATP(PC),A2            | A2 = driver start
        ADDA.L  A2,A3                           | A3 = handler
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars (atpVars)
        MOVE.B  0x1C(A0),D1                     | D1 = atpSocket
        SUBI    #0xA,D2                         | csCode >= 254 (OpenATPSkt, SendRequest, RelTCB)?
        BPL.B   E_ATP_CONTROL_JUMP              | yes -> no open socket needed
        MOVE    #-0x44B,D0                      | badATPSkt (-1099)
        TST.B   D1                              | atpSocket = 0?
        BEQ.B   E_ATP_CONTROL_EXIT              | yes -> badATPSkt
        MOVEQ.L #0x5,D2                         | 6 responding sockets
E_ATP_CONTROL_SKTLOOP:
        CMP.B   0x30(A2,D2.W),D1                | this responding socket?
        DBEQ    D2,E_ATP_CONTROL_SKTLOOP        | no -> next
        BNE.B   E_ATP_CONTROL_EXIT              | not open -> badATPSkt
E_ATP_CONTROL_JUMP:
        MOVE.L  0x1E(A0),D3                     | D3 = addrBlock (net.W, node.B, socket.B)
        ANDI.B  #0x3F,0x1D(A0)                  | atpFlags: clear bits 7-6 (FlagMask)
        JMP     (A3)                            | -> handler

| E_ATP_CONTROL_DISPATCH_TBL - csCode 249..256, offsets from _DRVR_10_.ATP
E_ATP_CONTROL_DISPATCH_TBL:
  .byte  0x05,0xEC,0x01,0x96,0x02,0xEC          | 249 RelRspCB $5EC, 250 CloseATPSkt $196, 251 AddResponse $2EC
  .byte 0x02,0x1E,0x01,0xD8,0x01,0x4E           | 252 SendResponse $21E, 253 GetRequest $1D8, 254 OpenATPSkt $14E
  .byte 0x03,0x80,0x05,0x94                     | 255 SendRequest $380, 256 RelTCB $594
| negative csCode (goodbye kiss): close .ATP only when MemTop < $30000
| (a 128K Mac, where the RAM-based .ATP lived in the application heap)
E_ATP_CONTROL_GOODBYE:
        CMPI    #0x2,(MemTop).w                 | high word of MemTop > 2 (MemTop >= $30000)?
        BGT     ATP_DONE_A1                     | yes -> IODone at once, .ATP stays open (D0 not set)
        BSR.B   E_ATP_Close                     | close .ATP
E_ATP_CONTROL_EXIT:
        BRA     ATP_DONE                        | -> IODone with D0

| ----------------------------------------------------------
|
| .ATP Close: waits for a free CB, closes the sockets of all request
| slots and responding sockets (CloseSkt calls to .MPP), then removes the
| VBL task and frees ATPVars.  When the .MPP Close has set the flag byte
| of atpVars (negative), .MPP can no longer be called: only the last step.
|
E_ATP_Close:
        MOVE.L  (ABusVars).w,A1                 | A1 = MPP variables
        MOVE.L  A1,D0                           | .MPP open?
        BEQ.B   E_ATP_CLOSE_EXIT                | no -> return
        MOVE.L  0x1E(A1),A2                     | A2 = ATPVars (atpVars)
        MOVE.L  A2,D0                           | flag byte set (.MPP closing)?
        BMI.B   E_ATP_CLOSE_FREE                | yes -> only free the memory
| wait until a CB is free (outstanding .MPP calls complete meanwhile)
E_ATP_CLOSE_WAITCB:
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   E_ATP_CLOSE_WAITCB              | none free -> try again
| close the sockets of the request slots
        MOVEQ.L #0x6,D2                         | 6 request slots
        LEA.L   (A2),A0                         | A0 = request sockets (ATPVars+$00)
        BSR.B   ATP_CLOSESOCKETS                | CloseSkt each of them
E_ATP_CLOSE_WAITREQ:
        TST     ioResult(A3)                    | last CloseSkt still in progress?
        BGT.B   E_ATP_CLOSE_WAITREQ             | yes -> wait
| close the responding sockets
        MOVEQ.L #0x6,D2                         | 6 responding sockets
        LEA.L   0x30(A2),A0                     | A0 = responding sockets (ATPVars+$30)
        BSR.B   ATP_CLOSESOCKETS                | CloseSkt each of them
E_ATP_CLOSE_WAITRSP:
        TST     ioResult(A3)                    | last CloseSkt still in progress?
        BGT.B   E_ATP_CLOSE_WAITRSP             | yes -> wait
| remove the VBL task, free ATPVars
E_ATP_CLOSE_FREE:
        PEA.L   0xCC(A2)                        | VBL task at ATPVars+$CC
        CLR.B   (SP)                            | without the flag byte
        MOVE.L  (SP)+,A0                        | A0 = VBL task
        _VRemove                                | remove it
        MOVE.L  A2,A0                           | A0 = ATPVars
        _DisposePtr                             | free it
        CLR.L   0x1E(A1)                        | atpVars = nil
        BCLR    #0x4,(PortBUse).w               | atpLoadedBit (4): .ATP closed
E_ATP_CLOSE_EXIT:
        RTS                                     | return from E_ATP_Close

| ----------------------------------------------------------
|
| ATP_CLOSESOCKETS: CloseSkt (via .MPP) every nonzero socket of a table.
| A0 = socket table, D2 = entries, A3 = claimed CB (ioResult cleared
| first, so the caller's wait loop ends when nothing was closed).  Each
| CloseSkt resumes the loop when it completes.
|
ATP_CLOSESOCKETS:
        CLR     ioResult(A3)                    | ioResult = 0 (nothing in progress)
ATP_CLOSESOCKETS_LOOP:
        SUBQ.W  #0x1,D2                         | next entry
        BMI.B   E_ATP_CLOSE_EXIT                | all done -> return
        MOVE.B  (A0)+,D1                        | D1 = socket
        BEQ.B   ATP_CLOSESOCKETS_LOOP           | slot free -> next
        MOVE    #0xF7,D0                        | csCode 247 = CloseSkt
        BSR     ATP_MPPCALL                     | close it; resumes here when done
        BRA.B   ATP_CLOSESOCKETS_LOOP           | next entry

| ----------------------------------------------------------
|
| OpenATPSkt (csCode 254): open a responding socket.  atpSocket = socket
| to open (0 = assign one), addrBlock = addresses to accept requests from
| (0 in a field = any).  Opens the DDP socket with ATP_LISTENER as its
| listener; returns the socket in atpSocket.  tooManySkts, noDataArea.
|
OPENATPSKT:
        MOVE    #-0x44A,D0                      | tooManySkts (-1098)
        MOVEQ.L #0x5,D2                         | 6 responding-socket slots
OPENATPSKT_LOOP:
        TST.B   0x30(A2,D2.W)                   | slot free?
        DBEQ    D2,OPENATPSKT_LOOP              | no -> next
        BNE.B   ATP_DONE                        | all in use -> IODone (tooManySkts)
| get a CB for the OpenSkt call
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_DONE                        | none -> IODone (noDataArea)
| OpenSkt via .MPP: D1 = socket, listener = ATP_LISTENER
        LEA.L   ATP_LISTENER(PC),A1             | A1 = ATP socket listener
        MOVE.L  A1,0x1E(A3)                     | CB listener field
        MOVE    #0xF8,D0                        | csCode 248 = OpenSkt
        BSR     ATP_MPPCALL                     | open the socket; resumes here when done
        MOVE.B  csParam(A3),D1                  | D1 = socket opened (CB socket field)
        BSR     ATP_FREECB                      | release the CB
        TST     D0                              | OpenSkt result
        BNE.B   ATP_DONE                        | error -> IODone with it
| fill in the responding-socket slot
        LSL     #0x2,D2                         | long index
        CLR.L   0x36(A2,D2.W)                   | no GetRequest waiting
        MOVE.L  D3,0x4E(A2,D2.W)                | addrBlock filter
        LSR     #0x2,D2                         | byte index
        MOVE.B  D1,0x30(A2,D2.W)                | socket number
        MOVE.B  D1,0x1C(A0)                     | return it in atpSocket
        BRA.B   ATP_DONE_NOERR                  | -> IODone, noErr

| ----------------------------------------------------------
|
| CLOSEATPSKT
|
| CloseATPSkt (csCode 250): close responding socket atpSocket (D2 = its
| slot): CloseSkt via .MPP, then free the slot and the socket's RspCBs.
| GetRequests still queued on the socket are not completed.  noDataArea.
CLOSEATPSKT:
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_DONE                        | none -> IODone (noDataArea)
        MOVE    #0xF7,D0                        | csCode 247 = CloseSkt
        BSR     ATP_MPPCALL                     | close the socket; resumes here when done
        BSR     ATP_FREECB                      | release the CB
        TST     D0                              | CloseSkt result
        BNE.B   ATP_DONE                        | error -> IODone with it
| free the slot and the socket's RspCBs
        CLR.B   0x30(A2,D2.W)                   | responding-socket slot free
        LEA.L   0x66(A2),A1                     | A1 = RspCBs
        MOVEQ.L #0x7,D2                         | 8 RspCBs
CLOSEATPSKT_LOOP:
        CMP.B   (A1),D1                         | RspCB of this socket?
        BNE.B   CLOSEATPSKT_NEXT                | no ->
        CLR.B   (A1)                            | yes: free it
CLOSEATPSKT_NEXT:
        ADDA    #0xC,A1                         | next RspCB (12 bytes)
        DBF     D2,CLOSEATPSKT_LOOP             | loop over all 8
| ATP_DONE_NOERR / ATP_DONE / ATP_DONE_A1: common exits, IODone with D0
| (noErr; A1 = .ATP DCE from ATPVars; A1 already loaded)
ATP_DONE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
| ATP_DONE - A1 = .ATP DCE, then IODone with D0
ATP_DONE:
        MOVE.L  0xC6(A2),A1                     | A1 = .ATP DCE (ATPVars+$C6)
ATP_DONE_A1:
        MOVE.L  (JIODone).w,A0                  | IODone vector
        JMP     (A0)                            | -> IODone (completes the current call)

| ----------------------------------------------------------
|
| .ATP Prime and Status: not supported - clear drvrActive and return
| without completing the call
|
E_ATP_PrimeStatus:
        BCLR    #0x7,0x5(A1)                    | dCtlFlags: clear drvrActive
        RTS                                     | return from E_ATP_PrimeStatus

| ----------------------------------------------------------
|
| GETREQUEST
|
| GetRequest (csCode 253): queue the call on responding socket atpSocket
| (D2 = slot) until a request arrives; ATP_LISTENER_DELIVER fills in
| userData, atpFlags, addrBlock, reqLength, bitMap and transID and
| completes it.  reqLength/reqPointer = request buffer.
GETREQUEST:
        LSL     #0x2,D2                         | long index
        LEA.L   0x36(A2,D2.W),A3                | A3 -> GetRequest queue head of the socket
| append the call at the end of the queue, interrupts off
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
GETREQUEST_LOOP:
        TST.L   (A3)                            | end of the queue?
        BEQ.B   GETREQUEST_APPEND               | yes ->
        MOVE.L  (A3),A3                         | next element
        BRA.B   GETREQUEST_LOOP                 | walk on
| link the call in at the end (its qLink is cleared below)
GETREQUEST_APPEND:
        MOVE.L  A0,(A3)                         | last element -> this call
| ATP_DETACHREQ: take the current call (A0) off the .ATP I/O queue without
| completing it, then start the next queued call, if any (as a new
| E_ATP_Control).  Entered with the caller's SR on the stack.
ATP_DETACHREQ:
        MOVE.L  0xC6(A2),A1                     | A1 = .ATP DCE
        BCLR    #0x7,0x5(A1)                    | dCtlFlags: clear drvrActive
        MOVE.L  (A0),0x8(A1)                    | dCtlQHead = next call in the queue
        BNE.B   ATP_DETACHREQ_UNLINK            | there is one ->
        CLR.L   0xC(A1)                         | queue empty: dCtlQTail = nil
ATP_DETACHREQ_UNLINK:
        CLR.L   (A0)                            | qLink of the detached call = nil
        MOVE.L  0x8(A1),D0                      | next call queued?
        BEQ.B   ATP_DETACHREQ_EXIT              | no ->
| start the next queued call
        MOVE.L  D0,A0                           | A0 = next parameter block
        MOVEQ.L #0x0,D0                         | clear D0
        BSET    #0x7,0x5(A1)                    | dCtlFlags: set drvrActive again
        MOVE    (SP)+,SR                        | restore SR
        BRA     E_ATP_Control                   | -> process it
| no other call queued
ATP_DETACHREQ_EXIT:
        MOVE    (SP)+,SR                        | restore SR
        RTS                                     | return from ATP_DETACHREQ

| ----------------------------------------------------------
|
| SendResponse (csCode 252): send numOfBuffs response packets from the
| BDS at bdsPointer (bdsSize entries) to addrBlock with transID; the EOM
| flag of atpFlags goes into the last packet.  Each sent BDS entry gets
| bdsDataSz = -1, the unused ones 0 (AddResponse fills them in later).
| Not exactly-once (no RspCB): completes at once.  Exactly-once: the
| call is attached to the RspCB and completes on TRel (noErr), RelRspCB
| (noErr) or release timeout (noRelErr).  badBuffNum, noDataArea.
|
SENDRESPONSE:
        MOVE.L  0x28(A0),A1                     | A1 = bdsPointer
        SWAP    D1                              | atpSocket to the high word
        MOVE    #-0x44C,D0                      | badBuffNum (-1100)
        MOVE.B  0x2C(A0),D1                     | D1.B = numOfBuffs
        BEQ.B   SENDRESPONSE_SENT               | 0: send nothing now ->
        CMPI.B  #0x8,D1                         | more than atpMaxNum (8)?
        BHI.B   SENDRESPONSE_EXIT               | yes -> IODone (badBuffNum)
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   SENDRESPONSE_EXIT               | none -> IODone (noDataArea)
        ST.B    0x61(A3)                        | atpRespNo = $FF (+1 = 0 for the first packet)
| build and send one response packet per BDS entry
SENDRESPONSE_LOOP:
        LEA.L   0x60(A3),A3                     | A3 -> ATP header in the CB
        MOVEQ.L #-0x80,D0                       | function code $80 = TResp
        SUBQ.B  #0x1,D1                         | one packet less to go
        BNE.B   SENDRESPONSE_CTL                | not the last one ->
        OR.B    0x1D(A0),D0                     | last packet: add atpFlags (EOM)
SENDRESPONSE_CTL:
        MOVE.B  D0,(A3)+                        | atpControl
        ADDQ.B  #0x1,(A3)+                      | atpRespNo = next sequence number
        MOVE    0x2E(A0),(A3)+                  | atpTransID = transID
        MOVE    (A1)+,D0                        | D0 = bdsBuffSz (data length)
        MOVE.L  (A1)+,D2                        | D2 = bdsBuffAdr (data)
        MOVE    #-0x1,(A1)+                     | bdsDataSz = -1: packet sent
        MOVE.L  (A1)+,(A3)+                     | atpUserData = bdsUserData
        LEA.L   -0x68(A3),A3                    | A3 = CB (was CB+$68)
        SWAP    D1                              | D1.W = atpSocket
        BSR     ATP_SENDPKT                     | WriteDDP; resumes here when done
        CMPI    #-0x5C,D0                       | ddpLenErr (-92)?
        BEQ.B   SENDRESPONSE_ABORT              | yes -> stop, IODone with it
        SWAP    D1                              | D1.B = packets left
        TST.B   D1                              | any?
        BNE.B   SENDRESPONSE_LOOP               | yes -> next packet
        BSR     ATP_FREECB                      | release the CB
| mark the BDS entries beyond numOfBuffs as not sent
SENDRESPONSE_SENT:
        SWAP    D1                              | D1.W = atpSocket
        MOVE.B  0x2D(A0),D2                     | D2 = bdsSize
        SUB.B   0x2C(A0),D2                     | - numOfBuffs = entries not sent
        BEQ.B   SENDRESPONSE_RSPCB              | none ->
SENDRESPONSE_CLRLOOP:
        CLR     0x6(A1)                         | bdsDataSz = 0: no response yet
        ADDA    #0xC,A1                         | next BDS entry (12 bytes)
        SUBQ.B  #0x1,D2                         | count down
        BNE.B   SENDRESPONSE_CLRLOOP            | loop
| exactly-once? then hand the call to the RspCB of the transaction
SENDRESPONSE_RSPCB:
        MOVE    0x2E(A0),D0                     | D0 = transID
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        BSR.B   ATP_FINDRSPCB                   | RspCB of (atpSocket, addrBlock, transID)?
        BNE     ADDRESPONSE_NOERR               | none (not XO) -> IODone, noErr
        MOVE.L  A0,0x8(A1)                      | RspCB: this SendResponse
        CLR.B   0x1(A1)                         | restart the release timer
        BRA     ATP_DETACHREQ                   | leave the call pending

| ----------------------------------------------------------
|
| SENDRESPONSE_ABORT - WriteDDP failed with ddpLenErr: release the CB;
| SENDRESPONSE_EXIT - IODone with D0 (also used by AddResponse)
|
SENDRESPONSE_ABORT:
        BSR     ATP_FREECB                      | release the CB
SENDRESPONSE_EXIT:
        BRA     ATP_DONE                        | -> IODone with D0

| ----------------------------------------------------------
|
| ATP_FINDRSPCB
|
| ATP_FINDRSPCB: find the RspCB of a transaction.  D1.B = responding
| socket, D3 = requester address, D0 = TID -> EQ and A1 = RspCB if found
| (NE if not).  Uses D2.
ATP_FINDRSPCB:
        LEA.L   0x66(A2),A1                     | A1 = first RspCB
        MOVEQ.L #0x7,D2                         | 8 RspCBs
ATP_FINDRSPCB_LOOP:
        CMP.B   (A1),D1                         | same socket?
        BNE.B   ATP_FINDRSPCB_NEXT              | no ->
        ADDQ.W  #0x2,A1                         | A1 -> requester address
        BSR.B   ATP_CMPADDR                     | same address?
        SUBQ.W  #0x2,A1                         | A1 -> RspCB again
        BNE.B   ATP_FINDRSPCB_NEXT              | no ->
        CMP     0x6(A1),D0                      | same TID?
        BEQ.B   ATP_FINDRSPCB_EXIT              | yes -> found (EQ)
ATP_FINDRSPCB_NEXT:
        ADDA    #0xC,A1                         | next RspCB (12 bytes)
        DBF     D2,ATP_FINDRSPCB_LOOP           | loop over all 8
ATP_FINDRSPCB_EXIT:
        RTS                                     | EQ = found, NE = not found

| ----------------------------------------------------------
|
| ATP_CMPADDR
|
| ATP_CMPADDR: compare internet address D3 (net.W, node.B, socket.B)
| with the one at (A1) -> EQ if equal; node and socket must match, a
| network number of 0 on either side matches any network.
ATP_CMPADDR:
        CMP.L   (A1),D3                         | whole address equal?
        BEQ.B   ATP_CMPADDR_EXIT                | yes -> EQ
        CMP     0x2(A1),D3                      | node and socket equal?
        BNE.B   ATP_CMPADDR_EXIT                | no -> NE
        TST     (A1)                            | network at (A1) = 0?
        BEQ.B   ATP_CMPADDR_EXIT                | yes -> EQ
        MOVE.L  D3,-(SP)                        | push D3
        TST     (SP)+                           | its network = 0? (EQ / NE)
        ADDQ.W  #0x2,SP                         | pop the rest
ATP_CMPADDR_EXIT:
        RTS                                     | return from ATP_CMPADDR

| ----------------------------------------------------------
|
| AddResponse (csCode 251): send one more response packet: rspNum
| (0-7), reqLength/reqPointer = data, userData, atpFlags (EOM), transID,
| addrBlock.  For an exactly-once transaction the packet is also entered
| in the BDS of the pending SendResponse (numOfBuffs extended), so a
| retransmission request can resend it.  badBuffNum, ddpLenErr,
| noSendResp (XO and no SendResponse yet), noDataArea.
|
ADDRESPONSE:
        MOVE    #-0x44C,D0                      | badBuffNum (-1100)
        MOVE.B  0x2C(A0),D2                     | D2 = rspNum
        CMPI.B  #0x8,D2                         | 0..7?
        BCC.B   SENDRESPONSE_EXIT               | no -> IODone (badBuffNum)
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   SENDRESPONSE_EXIT               | none -> IODone (noDataArea)
        MOVEQ.L #-0x5C,D0                       | ddpLenErr (-92)
        CMPI    #0x242,0x22(A0)                 | reqLength > atpMaxData (578)?
        BHI.B   SENDRESPONSE_EXIT               | yes -> IODone (ddpLenErr; the CB stays claimed)
| build the TResp header in the CB
        LEA.L   0x60(A3),A3                     | A3 -> ATP header in the CB
        MOVEQ.L #-0x80,D0                       | function code $80 = TResp
        OR.B    0x1D(A0),D0                     | add atpFlags (EOM)
        MOVE.B  D0,(A3)+                        | atpControl
        MOVE.B  D2,(A3)+                        | atpRespNo = rspNum
        MOVE    0x2E(A0),(A3)+                  | atpTransID = transID
| send it
        BSR     ATP_SETDATA                     | user bytes, D0/D2 = reqLength/reqPointer
        BSR     ATP_SENDPKT                     | WriteDDP; resumes here when done
        BSR     ATP_FREECB                      | release the CB
        MOVE    0x2E(A0),D0                     | D0 = transID
        MOVE    SR,-(SP)                        | save SR
| exactly-once transaction? (RspCB present)
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
  .short 0x6180                                 | BSR.B ATP_FINDRSPCB (displacement -128)
        BNE.B   ADDRESPONSE_NOERR               | no RspCB (not XO) -> IODone, noErr
| enter the packet in the BDS of the pending SendResponse
        MOVE.L  0x8(A1),A3                      | A3 = SendResponse of the RspCB
        MOVE    #-0x44F,D0                      | noSendResp (-1103)
        MOVE.L  A3,D2                           | SendResponse issued yet?
        BEQ.B   ADDRESPONSE_RESTSR              | no -> IODone (noSendResp)
        MOVE.B  0x1D(A0),D2                     | AddResponse atpFlags
        OR.B    D2,0x1D(A3)                     | merge into the SendResponse atpFlags (EOM)
| numOfBuffs of the SendResponse = max(numOfBuffs, rspNum + 1)
        CLR     D2                              | D2 = rspNum (word)
        MOVE.B  0x2C(A0),D2                     | rspNum
        LEA.L   0x2C(A3),A3                     | A3 -> numOfBuffs of the SendResponse
        CMP.B   (A3),D2                         | rspNum < numOfBuffs?
        BLT.B   ADDRESPONSE_BDS                 | yes -> keep it
        MOVE.B  D2,(A3)                         | numOfBuffs = rspNum
        ADDQ.B  #0x1,(A3)                       | + 1
ADDRESPONSE_BDS:
        MOVE.L  -(A3),A3                        | A3 = bdsPointer of the SendResponse
        MULU    #0xC,D2                         | entry offset (12 bytes each)
        ADDA    D2,A3                           | A3 -> BDS entry rspNum
        MOVE    0x22(A0),(A3)+                  | bdsBuffSz = reqLength
        MOVE.L  0x24(A0),(A3)+                  | bdsBuffAdr = reqPointer
        MOVE    #-0x1,(A3)+                     | bdsDataSz = -1: packet sent
        MOVE.L  0x12(A0),(A3)                   | bdsUserData = userData
        CLR.B   0x1(A1)                         | restart the release timer
ADDRESPONSE_NOERR:
        CLR     D0                              | noErr
ADDRESPONSE_RESTSR:
        MOVE    (SP)+,SR                        | restore SR
ADDRESPONSE_EXIT:
        BRA     ATP_DONE                        | -> IODone with D0

| ----------------------------------------------------------
|
| SendRequest (csCode 255): open a private DDP socket (dynamic number),
| fill in a free request slot, send the TReq (addrBlock, reqLength/
| reqPointer, userData, XO/STS from atpFlags, bitmap of numOfBuffs
| responses) and leave the call pending.  Returns reqTID (tidValid set
| in atpFlags); ATP_LISTENER stores the responses in the BDS, ATP_VBLTASK
| retransmits after timeOutVal seconds up to retryCount times (255 =
| forever).  tooManyReqs, ddpLenErr, noDataArea; reqFailed, reqAborted.
|
SENDREQUEST:
        MOVE    #-0x449,D0                      | tooManyReqs (-1097)
        MOVEQ.L #0x5,D2                         | 6 request slots
SENDREQUEST_LOOP:
        TST.B   0x0(A2,D2.W)                    | slot free?
        DBEQ    D2,SENDREQUEST_LOOP             | no -> next
        BNE.B   ADDRESPONSE_EXIT                | all in use -> IODone (tooManyReqs)
        MOVEQ.L #-0x5C,D0                       | ddpLenErr (-92)
        CMPI    #0x242,0x22(A0)                 | reqLength > atpMaxData (578)?
        BHI.B   ADDRESPONSE_EXIT                | yes -> IODone (ddpLenErr)
        CLR.B   D1                              | socket 0: let .MPP assign one
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   ADDRESPONSE_EXIT                | none -> IODone (noDataArea)
        LEA.L   ATP_LISTENER(PC),A1             | A1 = ATP socket listener
        MOVE.L  A1,0x1E(A3)                     | CB listener field
        MOVE    #0xF8,D0                        | csCode 248 = OpenSkt
        BSR     ATP_MPPCALL                     | open the socket; resumes here when done
        BEQ.B   SENDREQUEST_OPENED              | opened ->
        BSR     ATP_FREECB                      | failed: release the CB
        BRA.B   ADDRESPONSE_EXIT                | -> IODone with the OpenSkt error

| ----------------------------------------------------------
|
| SENDREQUEST_OPENED
|
| socket opened: D1 = its number, D2 = free request slot
SENDREQUEST_OPENED:
        MOVE.B  csParam(A3),D1                  | D1 = socket opened (CB socket field)
| currBitmap = one bit per expected response (bits 0..numOfBuffs-1)
        LEA.L   0x1D(A0),A1                     | A1 -> atpFlags
        BCLR    #0x4,(A1)                       | clear EOM (set when the last response arrives)
        CLR.B   -(A1)                           | currBitmap = 0
        MOVE.B  0x2C(A0),D0                     | D0 = numOfBuffs
        BEQ.B   SENDREQUEST_SLOT                | none ->
        SUBQ.B  #0x1,D0                         | highest bit number
SENDREQUEST_BITLOOP:
        BSet    D0,(A1)                         | set the bit of this response
        SUBQ.B  #0x1,D0                         | next lower bit
        BPL.B   SENDREQUEST_BITLOOP             | down to bit 0
| fill in the request slot
SENDREQUEST_SLOT:
        CLR.B   0x2E(A0)                        | numOfResps = 0
        LSL     #0x2,D2                         | long index
        MOVE.L  A0,0x6(A2,D2.W)                 | slot: parameter block
        LSR     #0x1,D2                         | word index
| next transaction ID
        LEA.L   0xCA(A2),A1                     | A1 -> next TID (ATPVars+$CA)
        MOVE    (A1),0x1E(A2,D2.W)              | slot: TID
        MOVE    (A1),0x16(A0)                   | reqTID = TID
        BSET    #0x1,0x1D(A0)                   | atpFlags: tidValid
        ADDQ.W  #0x1,(A1)                       | advance the TID counter
| socket and retry timer of the slot
        LSR     #0x1,D2                         | byte index
        MOVE.B  D1,0x0(A2,D2.W)                 | slot: socket
        LEA.L   0x2A(A2,D2.W),A1                | A1 -> slot retry timer
        CLR.B   (A1)                            | timer stopped while sending
| send the TReq
        LSL     #0x1,D2                         | word index
        BSR     ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        BSR.B   ATP_SENDPKT                     | WriteDDP; resumes here when done
        BSR     ATP_FREECB                      | release the CB
        MOVE.B  0x2D(A0),(A1)                   | retry timer = timeOutVal (seconds)
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        BRA     ATP_DETACHREQ                   | leave the call pending

| ----------------------------------------------------------
|
| ATP_SENDPKT
|
| ATP_SENDPKT: send the ATP packet of CB A3 (header at CB+$60): builds the
| WDS (DDP header template with type ATP and destination D3, the 8-byte
| ATP header, D0 bytes at D2) and issues WriteDDP from socket D1, with a
| checksum if atpFlags (A0) has sendCHK.  Resumes the caller when done.
| Called by: SENDRESPONSE, ADDRESPONSE, SENDREQUEST, ATP_VBLTASK,
| ATP_LISTENER (STS retransmit, TRel, duplicate-request responses)
ATP_SENDPKT:
        MOVEM.L A0-A1,-(SP)                     | save A0-A1
        BTST    #0x0,0x1D(A0)                   | atpFlags: sendCHK?
        SNE.B   0x1D(A3)                        | CB checksumFlag = TRUE if so
        ANDI.B  #0xF8,0x60(A3)                  | atpControl: clear bits 2-0 (ControlMask)
        LEA.L   0x3A(A3),A1                     | A1 = WDS (CB+$3A)
        MOVE.L  A1,0x1E(A3)                     | CB wdsPointer
        ADDQ.W  #0x2,A1                         | skip the (unused) length of entry 1
| WDS entry 1: DDP header template (odd address CB+$4F)
        LEA.L   0x4F(A3),A0                     | A0 = header template
        MOVE.L  A0,(A1)+                        | entry 1 pointer
        MOVE.B  #0x3,0xF(A0)                    | +15 DDP type = 3 (ATP)
        ADDQ.W  #0x7,A0                         | A0 -> +7 destination network
        MOVE.L  D3,(A0)+                        | +7 dest network (+9/+10 scratch)
        MOVE    D3,(A0)+                        | +11 dest node (+12 scratch)
        MOVE.B  D3,(A0)                         | +13 dest socket
| WDS entry 2: ATP header, entry 3: data, then the terminator
        MOVE    #0x8,(A1)+                      | entry 2 length = atpHdSz (8)
        LEA.L   0x60(A3),A0                     | A0 = ATP header (CB+$60)
        MOVE.L  A0,(A1)+                        | entry 2 pointer
        MOVE    D0,(A1)+                        | entry 3 length = data length
        MOVE.L  D2,(A1)+                        | entry 3 pointer = data
        CLR     (A1)+                           | end of WDS
        MOVEM.L (SP)+,A0-A1                     | restore A0-A1
| WriteDDP via .MPP
        MOVE    #0xF6,D0                        | csCode 246 = WriteDDP
| ATP_MPPCALL: async _Control D0 to .MPP with CB A3 (socket D1).  Saves
| D1-D3/A0-A1 and the return address in the CB and returns to the
| caller's caller; ATP_MPPDONE resumes after the BSR when the call
| completes (D0 = result, A2 = ATPVars, CB in A3).
| Called by: ATP_CLOSESOCKETS, OPENATPSKT, CLOSEATPSKT, SENDREQUEST,
| ATP_VBLTASK_FAIL, RELTCB_FOUND, ATP_LISTENER_CLOSE (and ATP_SENDPKT)
ATP_MPPCALL:
        MOVEM.L D1-D3/A0-A1,0x22(A3)            | save D1-D3/A0-A1 in CB+$22
        MOVE.L  (SP)+,0x36(A3)                  | address to resume at -> CB+$36
        LEA.L   ATP_MPPDONE(PC),A0              | A0 = completion routine
        MOVE.L  A0,0xC(A3)                      | ioCompletion = ATP_MPPDONE
        MOVE.L  A3,A0                           | A0 = CB
        MOVE.B  D1,0x1C(A0)                     | socket
        MOVE    D0,0x1A(A0)                     | csCode
        _ControlAsync                           | queue the call to .MPP (ioRefNum set by ATP_GETCB)
        RTS                                     | return to the caller's caller

| ----------------------------------------------------------
|
| ATP_MPPDONE: ioCompletion of the CBs (A0 = CB, D0 = result): restore
| the saved registers and continue after the BSR ATP_MPPCALL, with
| A3 = CB, A2 = ATPVars and the condition codes set from D0
|
ATP_MPPDONE:
        MOVE.L  A0,A3                           | A3 = CB
        MOVE.L  0x36(A0),-(SP)                  | push the address to resume at
        MOVEM.L 0x22(A0),D1-D3/A0-A1            | restore D1-D3/A0-A1
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        TST     D0                              | condition codes = result
        RTS                                     | resume the caller

| ----------------------------------------------------------
|
| ATP_BUILDTREQ: TReq header in CB A3 from SendRequest A0 (D2 = word
| index of its request slot): control $40 + atpFlags without EOM,
| bitmap = currBitmap, slot TID; D3 = addrBlock.  Falls into ATP_SETDATA.
|
ATP_BUILDTREQ:
        LEA.L   0x60(A3),A3                     | A3 -> ATP header in the CB
        MOVEQ.L #0x40,D0                        | function code $40 = TReq
        OR.B    0x1D(A0),D0                     | add atpFlags (XO, STS)
        BCLR    #0x4,D0                         | no EOM in a request
        MOVE.B  D0,(A3)+                        | atpControl
        MOVE.B  0x1C(A0),(A3)+                  | atpBitmap = currBitmap (responses still missing)
        MOVE    0x1E(A2,D2.W),(A3)+             | atpTransID = slot TID
        MOVE.L  0x1E(A0),D3                     | D3 = addrBlock (destination)
| ATP_SETDATA: atpUserData = userData, D0/D2 = reqLength/reqPointer of
| parameter block A0; A3 back to the CB (A3 = CB+$64 on entry)
ATP_SETDATA:
        MOVE.L  0x12(A0),(A3)                   | atpUserData = userData
        MOVE    0x22(A0),D0                     | D0 = reqLength
        MOVE.L  0x24(A0),D2                     | D2 = reqPointer
        SUBA    #0x64,A3                        | A3 = CB
        RTS                                     | return from ATP_SETDATA

| ----------------------------------------------------------
|
| ATP_VBLTASK: VBL task, once per second (A0 = task).  Request slots:
| count down the retry timers; on expiry retransmit the TReq (bitmap of
| the responses still missing) or, when retryCount is used up, close the
| socket and complete the SendRequest with reqFailed.  RspCBs: count
| the release timers up; after 30 seconds (releaseTime) free the RspCB
| and complete its SendResponse with noRelErr.
|
ATP_VBLTASK:
        MOVE    #0x3C,0xA(A0)                   | vblCount = 60: run again in 1 second
        LEA.L   -0xCC(A0),A2                    | A2 = ATPVars (task at +$CC)
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_VBLTASK_RSPCBS              | none: skip the request slots this time
        MOVEQ.L #0x6,D2                         | 6 request slots
| scan the request slots
ATP_VBLTASK_REQLOOP:
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
ATP_VBLTASK_NEXTREQ:
        SUBQ.W  #0x1,D2                         | next slot
        BMI.B   ATP_VBLTASK_REQDONE             | all done ->
        MOVE.B  0x0(A2,D2.W),D1                 | D1 = socket of the slot
        BEQ.B   ATP_VBLTASK_NEXTREQ             | slot free ->
        LEA.L   0x2A(A2,D2.W),A1                | A1 -> retry timer
        TST.B   (A1)                            | running?
        BEQ.B   ATP_VBLTASK_NEXTREQ             | no ->
        SUBQ.B  #0x1,(A1)                       | one second less
        BNE.B   ATP_VBLTASK_NEXTREQ             | not expired ->
| retry timer expired
        MOVE    D2,D3                           | D3 = slot
        LSL     #0x2,D3                         | long index
        MOVE.L  0x6(A2,D3.W),A0                 | A0 = SendRequest
        CMPI.B  #0xFF,0x2F(A0)                  | retryCount = 255 (retry forever)?
        BEQ.B   ATP_VBLTASK_RETRY               | yes -> retransmit
        SUBQ.B  #0x1,0x2F(A0)                   | retryCount - 1
        BCS.B   ATP_VBLTASK_FAIL                | was 0 -> give up
| retransmit the TReq
ATP_VBLTASK_RETRY:
        MOVE.B  0x2D(A0),(A1)                   | retry timer = timeOutVal
        MOVE    D2,A1                           | A1 = slot (kept across ATP_SENDPKT)
        LSL     #0x1,D2                         | word index
        BSR.B   ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        MOVE    (SP)+,SR                        | restore SR
        BSR     ATP_SENDPKT                     | WriteDDP; resumes here when done
        MOVE    A1,D2                           | D2 = slot
        BRA.B   ATP_VBLTASK_REQLOOP             | scan on
| retries used up: close the socket, complete with reqFailed
ATP_VBLTASK_FAIL:
        MOVE    (SP)+,SR                        | restore SR
        CLR.B   0x0(A2,D2.W)                    | free the request slot
        MOVE    #0xF7,D0                        | csCode 247 = CloseSkt
        BSR     ATP_MPPCALL                     | close the socket; resumes here when done
        MOVE    #-0x448,D0                      | reqFailed (-1096)
        BSR     ATP_COMPLETE                    | complete the SendRequest
        BRA.B   ATP_VBLTASK_REQLOOP             | scan on
| request slots done: release the CB
ATP_VBLTASK_REQDONE:
        MOVE    (SP)+,SR                        | restore SR
        BSR     ATP_FREECB                      | release the CB
| release timers of the RspCBs
ATP_VBLTASK_RSPCBS:
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        MOVEQ.L #0x8,D2                         | 8 RspCBs
        LEA.L   0x66(A2),A3                     | A3 = first RspCB
ATP_VBLTASK_RSPLOOP:
        SUBQ.W  #0x1,D2                         | next RspCB
        BMI.B   ATP_VBLTASK_EXIT                | all done ->
| RspCB in use: one second older; released after 30 seconds
        TST.B   (A3)+                           | socket (0 = free)
        BEQ.B   ATP_VBLTASK_NEXTRSP             | free ->
        ADDQ.B  #0x1,(A3)                       | release timer + 1 second
        CMPI.B  #0x1E,(A3)                      | 30 seconds (releaseTime)?
        BNE.B   ATP_VBLTASK_NEXTRSP             | not yet ->
| release timeout: free the RspCB, complete its SendResponse with noRelErr
        MOVE.L  0x7(A3),A0                      | A0 = SendResponse (RspCB+8)
        CLR.B   -0x1(A3)                        | free the RspCB
        MOVE.L  A0,D0                           | SendResponse issued?
        BEQ.B   ATP_VBLTASK_NEXTRSP             | no ->
        MOVE    #-0x44D,D0                      | noRelErr (-1101)
        BSR.B   ATP_COMPLETE                    | complete it
ATP_VBLTASK_NEXTRSP:
        ADDA    #0xB,A3                         | next RspCB (12 bytes)
        BRA.B   ATP_VBLTASK_RSPLOOP             | loop
| done
ATP_VBLTASK_EXIT:
        MOVE    (SP)+,SR                        | restore SR
        RTS                                     | return from ATP_VBLTASK

| ----------------------------------------------------------
|
| ATP_COMPLETE: complete a call that ATP_DETACHREQ took off the queue:
| ioResult = D0, then call its ioCompletion routine (A0 = parameter
| block, D0 = result), if any.  Preserves D1-D3/A0-A3.
| Called by: ATP_VBLTASK, RELTCB_FOUND, RELRSPCB, ATP_LISTENER (TRel,
| last response, request delivered)
ATP_COMPLETE:
        MOVE    D0,0x10(A0)                     | ioResult = D0
        MOVEM.L D1-D3/A0-A3,-(SP)               | save registers
        MOVE.L  0xC(A0),D1                      | D1 = ioCompletion
        BEQ.B   ATP_COMPLETE_EXIT               | none ->
        MOVE.L  D1,A1                           | A1 = completion routine
        TST     D0                              | condition codes = result
        JSR     (A1)                            | call it
ATP_COMPLETE_EXIT:
        MOVEM.L (SP)+,D1-D3/A0-A3               | restore registers
        RTS                                     | return from ATP_COMPLETE

| ----------------------------------------------------------
|
| RelTCB (csCode 256): abort the SendRequest with transID to addrBlock:
| close its socket, free its slot and complete it with reqAborted.
| cbNotFound, noDataArea.
|
RELTCB:
        MOVE    0x2E(A0),D1                     | D1 = transID
        MOVEQ.L #0x5,D2                         | 6 request slots
RELTCB_LOOP:
        TST.B   0x0(A2,D2.W)                    | slot in use?
        BEQ.B   RELTCB_NEXT                     | no ->
        MOVE    D2,D0                           | D0 = slot
        LSL     #0x1,D0                         | word index
        CMP     0x1E(A2,D0.W),D1                | same TID?
        BNE.B   RELTCB_NEXT                     | no ->
        LSL     #0x1,D0                         | long index
        MOVE.L  0x6(A2,D0.W),A0                 | A0 = SendRequest of the slot
        LEA.L   0x1E(A0),A1                     | A1 -> its addrBlock
        BSR     ATP_CMPADDR                     | same destination as D3?
        BEQ.B   RELTCB_FOUND                    | yes ->
RELTCB_NEXT:
        DBF     D2,RELTCB_LOOP                  | next slot
| RELTCB_NOTFOUND - no such transaction (also used by RelRspCB)
RELTCB_NOTFOUND:
        MOVE    #-0x44E,D0                      | cbNotFound (-1102)
        BRA     ATP_DONE                        | -> IODone

| ----------------------------------------------------------
|
| RELTCB_FOUND
|
| found: A0 = SendRequest, D2 = its slot
RELTCB_FOUND:
        BSR     ATP_GETCB                       | A3 = free CB
        BNE     ATP_DONE                        | none -> IODone (noDataArea)
        MOVE.B  0x0(A2,D2.W),D1                 | D1 = socket of the request
        CLR.B   0x0(A2,D2.W)                    | free the request slot
        MOVE    #0xF7,D0                        | csCode 247 = CloseSkt
        BSR     ATP_MPPCALL                     | close the socket; resumes here when done
        BSR     ATP_FREECB                      | release the CB
        MOVE    #-0x451,D0                      | reqAborted (-1105)
        BSR.B   ATP_COMPLETE                    | complete the SendRequest
| RELTCB_DONE - complete the RelTCB / RelRspCB call with noErr
RELTCB_DONE:
        BRA     ATP_DONE_NOERR                  | -> IODone, noErr

| ----------------------------------------------------------
|
| RelRspCB (csCode 249): release the RspCB of (atpSocket, addrBlock,
| transID) without waiting for TRel or the release timer; its
| SendResponse, if any, completes with noErr.  cbNotFound.
|
RELRSPCB:
        MOVE    0x2E(A0),D0                     | D0 = transID
        BSR     ATP_FINDRSPCB                   | A1 = RspCB of (D1, D3, D0)
        BNE.B   RELTCB_NOTFOUND                 | none -> cbNotFound
        MOVE.L  0x8(A1),A0                      | A0 = its SendResponse
        CLR.B   (A1)                            | free the RspCB
        MOVE.L  A0,D0                           | SendResponse issued?
        BEQ.B   RELRSPCB_DONE                   | no ->
        CLR     D0                              | noErr
        BSR     ATP_COMPLETE                    | complete the SendResponse
RELRSPCB_DONE:
        BRA.B   RELTCB_DONE                     | -> IODone, noErr

| ----------------------------------------------------------
|
| ATP_LISTENER_DISCARD: drop the packet: ReadRest with a zero buffer (it
| returns to MPP), discarding the saved RHA pointer
|
ATP_LISTENER_DISCARD:
        CLR     D3                              | buffer size 0
        ADDQ.W  #0x4,SP                         | drop the saved RHA pointer
        JMP     0x2(A4)                         | ReadRest: discard the rest, return to MPP

| ----------------------------------------------------------
|
| ATP_LISTENER_TREQ: TReq (function code 01) - D0 = destination socket,
| A5 = ATPVars.  Reads the request data into the buffer of the first
| GetRequest queued on the socket (nothing if none is queued).
|
ATP_LISTENER_TREQ:
        ADD.B   D2,D2                           | bit 6 of atpControl -> N
        BPL.B   ATP_LISTENER_DISCARD            | function code 00: invalid, drop
| find the responding socket
        MOVEQ.L #0x5,D2                         | 6 responding sockets
ATP_LISTENER_TREQLOOP:
        CMP.B   0x30(A5,D2.W),D0                | this socket?
        DBEQ    D2,ATP_LISTENER_TREQLOOP        | no -> next
        BNE.B   ATP_LISTENER_DISCARD            | not a responding socket -> drop
| read the request into the first queued GetRequest's buffer
        LSL     #0x2,D2                         | long index
        MOVE.L  0x36(A5,D2.W),A5                | A5 = first queued GetRequest
        MOVE.L  A5,D0                           | any?
        BEQ.B   ATP_LISTENER_TREQREAD           | no: D3 = 0, data discarded
        MOVE    0x22(A5),D3                     | D3 = reqLength (buffer size)
        MOVE.L  0x24(A5),A3                     | A3 = reqPointer
ATP_LISTENER_TREQREAD:
        JSR     0x2(A4)                         | ReadRest
        BSR     ATP_CHKPKT                      | errors, checksum; D1 = requester address
        MOVE.L  (SP)+,A3                        | A3 = saved RHA pointer (after the ATP header)
        BEQ     ATP_LISTENER_GOTREQ             | packet OK ->
ATP_LISTENER_EXIT:
        RTS                                     | return to MPP

| ----------------------------------------------------------
|
| ATP_LISTENER_DROP - short-branch path to ATP_LISTENER_DISCARD
|
ATP_LISTENER_DROP:
        BRA.B   ATP_LISTENER_DISCARD            | -> drop the packet

| ----------------------------------------------------------
|
| ATP_LISTENER_TREL: TRel (function code 11) - the requester releases an
| exactly-once transaction: free its RspCB and complete the SendResponse
| (userData = user bytes of the TRel).  D0 = destination socket.
|
ATP_LISTENER_TREL:
        MOVE.B  D0,D2                           | D2 = responding socket
        MOVE.L  (SP)+,A3                        | A3 = saved RHA pointer (after the ATP header)
        JSR     0x2(A4)                         | ReadRest (D3 = 0: no data)
        BSR     ATP_CHKPKT                      | errors, checksum; D1 = requester address
        BNE.B   ATP_LISTENER_EXIT               | bad packet ->
        MOVE.L  D1,D3                           | D3 = requester address
        MOVE    -0x6(A3),D0                     | D0 = atpTransID
        MOVE.B  D2,D1                           | D1 = responding socket
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        BSR     ATP_FINDRSPCB                   | RspCB of the transaction?
        BNE.B   ATP_LISTENER_EXIT               | none ->
| free the RspCB, complete its SendResponse
        CLR.B   (A1)                            | free the RspCB
        MOVE.L  0x8(A1),D0                      | its SendResponse
        BEQ.B   ATP_LISTENER_EXIT               | none issued ->
        MOVE.L  D0,A0                           | A0 = SendResponse
        MOVE.L  -(A3),0x12(A0)                  | userData = atpUserData of the TRel
        CLR     D0                              | noErr
        BRA     ATP_COMPLETE                    | complete the SendResponse

| ----------------------------------------------------------
|
| ATP_LISTENER: DDP socket listener of all ATP sockets (MPP socket
| listener conventions: A2 = MPP variables, A3 -> next free RHA byte,
| A4 = ReadPacket/ReadRest jump table, D0 = destination socket, D1 =
| bytes left).  Reads the ATP header into the RHA one byte before A3
| (over the DDP type byte, so the TID and user bytes are word aligned)
| and dispatches on the function code: TReq -> ATP_LISTENER_TREQ,
| TRel -> ATP_LISTENER_TREL, TResp (response to a SendRequest) here.
|
ATP_LISTENER:
        MOVEQ.L #0x8,D3                         | atpHdSz = 8 bytes
        SUBQ.W  #0x1,A3                         | over the DDP type byte (word alignment)
        JSR     (A4)                            | ReadPacket: ATP header
ATP_LISTENER_CHKERR:
        BNE.B   ATP_LISTENER_EXIT               | error -> return
        MOVE.L  0x1E(A2),A5                     | A5 = ATPVars (atpVars)
        MOVE.L  A3,-(SP)                        | save the RHA pointer (after the ATP header)
        SUBQ.W  #0x8,A3                         | A3 -> atpControl
        MOVE.B  -0x2(A3),D0                     | D0 = DDP destination socket (2 bytes before)
        MOVE.B  (A3)+,D2                        | D2 = atpControl
  .short 0x6A80                                 | BPL.B ATP_LISTENER_TREQ (displacement -128): bit 7 clear
        ADD.B   D2,D2                           | bit 6 -> N
        BMI.B   ATP_LISTENER_TREL               | function code 11 = TRel ->
| function code 10 = TResp: find the request slot of the socket
        MOVEQ.L #0x5,D2                         | 6 request slots
ATP_LISTENER_TRESPLOOP:
        CMP.B   0x0(A5,D2.W),D0                 | socket of this request?
        DBEQ    D2,ATP_LISTENER_TRESPLOOP       | no -> next
| not a request socket: drop
        BNE.B   ATP_LISTENER_DROP               | none -> drop
| read the data straight into the BDS buffer of this response number
        LSL     #0x2,D2                         | long index
        MOVE.L  0x6(A5,D2.W),A5                 | A5 = SendRequest
        MOVE.B  (A3),D3                         | D3 = atpRespNo
        CMP.B   0x2C(A5),D3                     | >= numOfBuffs?
        BCC.B   ATP_LISTENER_DROP               | yes -> drop
| BDS entry = bdsPointer + 12 * atpRespNo
        ASL     #0x2,D3                         | * 4
        MOVE    D3,D0                           | D0 = 4 * n
        ADD     D0,D3                           | 8 * n
        ADD     D0,D3                           | 12 * n
        MOVE.L  0x28(A5),A3                     | A3 = bdsPointer
        ADDA    D3,A3                           | A3 -> BDS entry
        MOVE    (A3)+,D3                        | D3 = bdsBuffSz
        MOVE.L  (A3)+,A3                        | A3 = bdsBuffAdr
| ReadRest into the buffer
        JSR     0x2(A4)                         | ReadRest (D3 = bytes not filled)
        BSR     ATP_CHKPKT                      | errors, checksum; D1 = responder address
        MOVE.L  (SP)+,A3                        | A3 = saved RHA pointer
        BNE.B   ATP_LISTENER_CHKERR             | bad packet -> return
| the response must come from the addrBlock of the request
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        MOVE.L  0x6(A2,D2.W),A0                 | A0 = SendRequest
        LEA.L   0x1E(A0),A1                     | A1 -> its addrBlock
        EXG     D1,D3                           | D3 = responder address
        BSR     ATP_CMPADDR                     | same?
        EXG     D1,D3                           | D1 = address, D3 = bytes not filled
        BNE.B   ATP_LISTENER_CHKERR             | no -> ignore
| and carry the TID of the request
        LSR     #0x1,D2                         | word index
        MOVE.L  -(A3),D1                        | D1 = atpUserData
        MOVE    -(A3),D0                        | D0 = atpTransID
        CMP     0x1E(A2,D2.W),D0                | TID of the request?
        BNE.B   ATP_LISTENER_CHKERR             | no -> ignore
| store bdsDataSz and bdsUserData of the response
        MOVE.B  -(A3),D0                        | D0 = atpRespNo
        CMPI.B  #0x7,D0                         | 0..7?
        BHI.B   ATP_LISTENER_CHKERR             | no -> ignore
        EXT     D0                              | word
        MULU    #0xC,D0                         | BDS entry offset
        MOVE.L  0x28(A0),A1                     | A1 = bdsPointer
        ADDA    D0,A1                           | A1 -> BDS entry
        MOVE    (A1),D0                         | D0 = bdsBuffSz
        ADDQ.W  #0x6,A1                         | A1 -> bdsDataSz
        SUB     D3,D0                           | - bytes not filled = bytes received
        MOVE    D0,(A1)+                        | bdsDataSz
        MOVE.L  D1,(A1)+                        | bdsUserData = atpUserData
| clear the bit of this response in currBitmap
        LEA.L   0x1C(A0),A1                     | A1 -> currBitmap
        MOVE.B  (A3),D3                         | D3 = atpRespNo
        SUBQ.W  #0x1,A3                         | A3 -> atpControl
        BCLR    D3,(A1)                         | clear its bit
        BEQ.B   ATP_LISTENER_STS                | was clear: duplicate ->
        ADDQ.B  #0x1,0x2E(A0)                   | numOfResps + 1
| EOM: no responses beyond this one
        MOVEQ.L #0x4,D1                         | atpEOMBit (4)
        BTST    D1,(A3)                         | EOM in atpControl?
        BEQ.B   ATP_LISTENER_STS                | no ->
ATP_LISTENER_EOMLOOP:
        BClr    D3,(A1)                         | clear the bits of response D3 ...
        ADDQ.B  #0x1,D3                         | ... and all higher ones
        CMPI.B  #0x8,D3                         | up to bit 7
        BNE.B   ATP_LISTENER_EOMLOOP            | loop
        BSET    D1,0x1D(A0)                     | set EOM in atpFlags
| STS set in the response: resend the TReq with the bitmap still missing
ATP_LISTENER_STS:
        MOVE.B  -0x2(A3),D1                     | D1 = DDP destination socket (our request socket)
        BTST    #0x3,(A3)                       | atpSTSBit (3) set?
        BEQ.B   ATP_LISTENER_ALLRCVD            | no ->
| send the TReq again
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_LISTENER_ALLRCVD            | none -> skip
        MOVE    D2,A1                           | A1 = slot word index (kept across ATP_SENDPKT)
        BSR     ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        BSR.B   ATP_SCCENABLE                   | allow SCC interrupts again
        BSR     ATP_SENDPKT                     | WriteDDP; resumes here when done
        BSR     ATP_FREECB                      | release the CB
        MOVE    A1,D2                           | D2 = slot word index
| all responses received? then the transaction is complete
ATP_LISTENER_ALLRCVD:
        TST.B   0x1C(A0)                        | currBitmap = 0?
        BNE.B   ATP_SCCENABLE_EXIT              | no, wait for more -> return
| free the slot, send TRel if exactly-once, close the socket, complete
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_SCCENABLE_EXIT              | none -> return (completion lost)
        MOVE    0x1E(A2,D2.W),0x62(A3)          | atpTransID of the TRel = slot TID
        LSR     #0x1,D2                         | byte index
        CLR.B   0x0(A2,D2.W)                    | free the request slot
        BSR.B   ATP_SCCENABLE                   | allow SCC interrupts again
| exactly-once: send TRel to the responder
        BTST    #0x5,0x1D(A0)                   | atpFlags: XO?
        BEQ.B   ATP_LISTENER_CLOSE              | no ->
        MOVE.L  0x1E(A0),D3                     | D3 = addrBlock (responder)
        MOVE.B  #0xC0,0x60(A3)                  | atpControl = $C0 (TRel)
        CLR     D0                              | no data
        BSR     ATP_SENDPKT                     | send the TRel; resumes here when done
ATP_LISTENER_CLOSE:
        MOVE    #0xF7,D0                        | csCode 247 = CloseSkt
        BSR     ATP_MPPCALL                     | close the request socket; resumes here when done
        BSR     ATP_FREECB                      | release the CB
        CLR     D0                              | noErr
        BRA     ATP_COMPLETE                    | complete the SendRequest

| ----------------------------------------------------------
|
| ATP_SCCENABLE: SR = vSCCEnable (MPP variables +$1C): allow SCC
| interrupts during the post-processing of a received packet
|
ATP_SCCENABLE:
        MOVE.L  A1,-(SP)                        | save A1
        MOVE.L  (ABusVars).w,A1                 | A1 = MPP variables
        MOVE    0x1C(A1),SR                     | SR = vSCCEnable
        MOVE.L  (SP)+,A1                        | restore A1
ATP_SCCENABLE_EXIT:
        RTS                                     | return from ATP_SCCENABLE

| ----------------------------------------------------------
|
| ATP_LISTENER_GOTREQ
|
| ATP_LISTENER_GOTREQ: request read (A3 -> end of the ATP header in the
| RHA, D1 = requester address, D2 = socket slot * 4).  Exactly-once: a
| known transaction (RspCB present) is a retransmitted request ->
| ATP_LISTENER_RESEND; a new one gets an RspCB when a GetRequest waits.
ATP_LISTENER_GOTREQ:
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        MOVE.L  -(A3),A1                        | A1 = atpUserData
        MOVE    -(A3),D0                        | D0 = atpTransID
| exactly-once request?
        BTST    #0x5,-0x2(A3)                   | atpXOBit (5) in atpControl?
        BEQ.B   ATP_LISTENER_TODELIVER          | no -> deliver it
| known transaction?
        MOVEM.L D0-D4/A1/A3,-(SP)               | save registers
        MOVE.L  D1,D3                           | D3 = requester address
        MOVE.B  -0x4(A3),D1                     | D1 = DDP destination socket (responding socket)
        MOVE    D2,D4                           | D4 = socket slot * 4
        BSR     ATP_FINDRSPCB                   | RspCB of (socket, requester, TID)?
        BEQ.B   ATP_LISTENER_RESEND             | yes: request retransmitted ->
| new transaction: allocate an RspCB if a GetRequest waits
        TST.L   0x36(A2,D4.W)                   | GetRequest queued on the socket?
        BEQ.B   ATP_LISTENER_XODONE             | no -> no RspCB
        LEA.L   0x66(A2),A1                     | A1 = first RspCB
        MOVEQ.L #0x7,D2                         | 8 RspCBs
ATP_LISTENER_RSPCBLOOP:
        TST.B   (A1)                            | free?
        BEQ.B   ATP_LISTENER_NEWRSPCB           | yes ->
        ADDA    #0xC,A1                         | next RspCB (12 bytes)
        DBF     D2,ATP_LISTENER_RSPCBLOOP       | loop
| no RspCB free: ignore the request (the requester retries)
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore registers
        RTS                                     | return to MPP

| ----------------------------------------------------------
|
| ATP_LISTENER_NEWRSPCB
|
| fill in the free RspCB at A1
ATP_LISTENER_NEWRSPCB:
        MOVE.B  D1,(A1)+                        | +0 responding socket
        CLR.B   (A1)+                           | +1 release timer = 0
        MOVE.L  D3,(A1)+                        | +2 requester address
        MOVE    D0,(A1)+                        | +6 TID
        CLR.L   (A1)+                           | +8 no SendResponse yet
ATP_LISTENER_XODONE:
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore registers
| deliver the request
ATP_LISTENER_TODELIVER:
        BRA.B   ATP_LISTENER_DELIVER            | -> first queued GetRequest

| ----------------------------------------------------------
|
| ATP_LISTENER_RESEND: retransmitted exactly-once request - resend the
| response packets it asks for (atpBitmap) from the BDS of the pending
| SendResponse (entries with bdsDataSz <> 0); A1 = RspCB
|
ATP_LISTENER_RESEND:
        MOVE.L  A1,A0                           | A0 = RspCB
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore registers
        MOVE.L  D1,D3                           | D3 = requester address
        MOVE.B  -0x4(A3),D1                     | D1 = responding socket
        CLR.B   0x1(A0)                         | restart the release timer
        MOVE.L  0x8(A0),D2                      | D2 = SendResponse of the RspCB
        BEQ.B   ATP_LISTENER_RTS                | none yet -> nothing to resend
| D1.B = requested bitmap (socket in the high word), A1 = BDS
        SWAP    D1                              | socket to the high word
        MOVE.B  -(A3),D1                        | D1.B = atpBitmap of the request
        MOVE.L  D2,A0                           | A0 = SendResponse
        MOVE.L  0x28(A0),A1                     | A1 = its bdsPointer
        MOVE    D0,D2                           | D2 = TID
        BSR     ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_LISTENER_RTS                | none -> give up
| TResp header with sequence number -1 (incremented per entry)
        MOVE.B  #0x80,0x60(A3)                  | atpControl = $80 (TResp)
        ST.B    0x61(A3)                        | atpRespNo = $FF
        MOVE    D2,0x62(A3)                     | atpTransID = TID
        BSR     ATP_SCCENABLE                   | allow SCC interrupts again
| one pass per BDS entry
ATP_LISTENER_RESENDLOOP:
        ADDQ.B  #0x1,0x61(A3)                   | next sequence number
        MOVE.B  0x61(A3),D0                     | D0 = sequence number
        SUB.B   0x2C(A0),D0                     | >= numOfBuffs?
        BGE     ATP_FREECB                      | yes: done, release the CB and return
        ADDQ.B  #0x1,D0                         | last packet?
        BNE.B   ATP_LISTENER_RESENDBDS          | no ->
        MOVE.B  0x1D(A0),D0                     | SendResponse atpFlags
        OR.B    D0,0x60(A3)                     | add them (EOM) to atpControl
ATP_LISTENER_RESENDBDS:
| take the BDS entry; send it if requested and present
        MOVE    (A1)+,D0                        | D0 = bdsBuffSz
        MOVE.L  (A1)+,D2                        | D2 = bdsBuffAdr
        ADDQ.W  #0x2,A1                         | skip bdsDataSz
        MOVE.L  (A1)+,0x64(A3)                  | atpUserData = bdsUserData
        LSR     #0x1,D1                         | next bitmap bit -> C
        BCC.B   ATP_LISTENER_RESENDLOOP         | not requested -> next
        TST     -0x6(A1)                        | bdsDataSz = 0 (not supplied yet)?
        BEQ.B   ATP_LISTENER_RESENDLOOP         | yes -> next
| send it
        SWAP    D1                              | D1.W = socket
        BSR     ATP_SENDPKT                     | WriteDDP; resumes here when done
        SWAP    D1                              | D1.B = bitmap
        BRA.B   ATP_LISTENER_RESENDLOOP         | next entry

| ----------------------------------------------------------
|
| ATP_LISTENER_RTS
|
| return to MPP
ATP_LISTENER_RTS:
        RTS                                     | return from ATP_LISTENER

| ----------------------------------------------------------
|
| ATP_LISTENER_DELIVER: complete the first GetRequest queued on the
| socket with the request: userData, bitMap, transID, atpFlags =
| atpControl, addrBlock = requester, reqLength = request size; dropped
| if no GetRequest waits or the requester fails the addrBlock filter.
|
ATP_LISTENER_DELIVER:
        MOVE.L  0x36(A2,D2.W),-(SP)             | first queued GetRequest
        MOVE.L  (SP)+,A0                        | A0 = it (test for nil)
        BEQ.B   ATP_LISTENER_RTS                | none -> drop the request
| return the request fields
        MOVE.L  A1,0x12(A0)                     | userData = atpUserData
        MOVE.B  -(A3),0x2C(A0)                  | bitMap = atpBitmap
        MOVE    D0,0x2E(A0)                     | transID = atpTransID
        LEA.L   0x1D(A0),A1                     | A1 -> atpFlags
        MOVE.B  -(A3),(A1)+                     | atpFlags = atpControl (XO bit)
        MOVE.L  D1,(A1)                         | addrBlock = requester address
| check the requester against the addrBlock filter of the socket
        LEA.L   0x4E(A2,D2.W),A3                | A3 -> filter (from OpenATPSkt)
        CMPM    (A1)+,(A3)+                     | same network?
        BEQ.B   ATP_LISTENER_FILTNODE           | yes ->
        TST     -0x2(A3)                        | filter network = 0 (any)?
        BNE.B   ATP_LISTENER_RTS                | no -> drop the request
ATP_LISTENER_FILTNODE:
        MOVEQ.L #0x2,D0                         | node, then socket
ATP_LISTENER_FILTLOOP:
        CMPM.B  (A1)+,(A3)+                     | same?
        BEQ.B   ATP_LISTENER_FILTNEXT           | yes ->
        TST.B   -0x1(A3)                        | filter field = 0 (any)?
        BNE.B   ATP_LISTENER_RTS                | no -> drop the request
ATP_LISTENER_FILTNEXT:
        SUBQ.W  #0x1,D0                         | next field
        BNE.B   ATP_LISTENER_FILTLOOP           | loop (ends with D0 = 0)
| accepted: request size, dequeue, complete
        SUB     D3,(A1)                         | reqLength -= bytes not filled
        MOVE.L  (A0),0x36(A2,D2.W)              | dequeue the GetRequest
        BRA     ATP_COMPLETE                    | complete it (D0 = noErr)

| ----------------------------------------------------------
|
| ATP_CHKPKT: after ReadRest (Z = no error): verify the DDP checksum of a
| long-header packet (if nonzero) and return D1 = source address (net.W,
| node.B, socket.B; net 0 for a short header), Z set if all is well.
| A2 = MPP variables, RHA at A2+1 (the DDP type byte holds atpControl).
|
ATP_CHKPKT:
        BNE.B   ATP_CHKPKT_EXIT                 | ReadRest error -> NE
        MOVEQ.L #0x0,D1                         | D1 = 0 (network 0)
        LEA.L   0x2(A2),A0                      | A0 -> lapSrcAdr in the RHA
        MOVE.B  0x7(A2),D0                      | D0 = sDDPSrcSkt (short header)
        MOVE.B  (A0)+,D1                        | D1 = lapSrcAdr (source node)
        SUBQ.B  #0x1,(A0)+                      | lapType = 1 (shortDDP)? (byte destroyed)
        BEQ.B   ATP_CHKPKT_ADDR                 | yes -> address complete
| long header: checksum
        MOVEM.L D2-D4,-(SP)                     | save D2-D4
        MOVE    (A0)+,D1                        | D1 = ddpLength (hop count + length)
        MOVE    (A0)+,D4                        | D4 = ddpChecksum
        BEQ.B   ATP_CHKPKT_RESTORE              | 0: not checksummed -> OK
| checksum the header from ddpDstNet to ddpSrcSkt, the type byte
        MOVEQ.L #0x8,D2                         | 8 bytes
        CLR     D3                              | checksum = 0
        BSR.B   ATP_CHECKSUM                    | add them
        ADDQ.W  #0x3,D3                         | DDP type 3 (its RHA byte now holds atpControl)
        ROL     #0x1,D3                         | rotate as in ATP_CHECKSUM
| the ATP header
        MOVEQ.L #0x8,D2                         | 8 bytes
        BSR.B   ATP_CHECKSUM                    | add them
| the data (D1 bytes ending at A3)
        ANDI    #0x3FF,D1                       | datagram length (ddpLenMask)
        SUBI    #0x15,D1                        | - 13 (DDP header) - 8 (ATP header)
        BEQ.B   ATP_CHKPKT_ZERO                 | no data ->
        MOVE.L  A3,A0                           | A0 = end of the data read
        SUBA    D1,A0                           | A0 -> start of the data
        MOVE    D1,D2                           | D2 = data length
        BSR.B   ATP_CHECKSUM                    | add them
| a computed 0 is sent as $FFFF
ATP_CHKPKT_ZERO:
        TST     D3                              | computed checksum = 0?
        BNE.B   ATP_CHKPKT_COMPARE              | no ->
        SUBQ.W  #0x1,D3                         | yes: use $FFFF
ATP_CHKPKT_COMPARE:
        CMP     D4,D3                           | = ddpChecksum?
ATP_CHKPKT_RESTORE:
        MOVEM.L (SP)+,D2-D4                     | restore D2-D4
        BNE.B   ATP_CHKPKT_EXIT                 | checksum error -> NE
| source address from the long header
        MOVE.L  0xA(A2),D1                      | ddpSrcNet.W, ddpDstNode, ddpSrcNode
        MOVE.B  0xD(A2),D1                      | ddpSrcNode (already in the low byte)
        MOVE.B  0xF(A2),D0                      | D0 = ddpSrcSkt
ATP_CHKPKT_ADDR:
        LSL     #0x8,D1                         | source node to bits 15-8
        MOVE.B  D0,D1                           | source socket to bits 7-0
        CLR     D0                              | noErr (Z set)
ATP_CHKPKT_EXIT:
        RTS                                     | return from ATP_CHKPKT

| ----------------------------------------------------------
|
| ATP_CHECKSUM: DDP checksum over D2 bytes at (A0)+: D3 = (D3 + byte)
| rotated left one bit, per byte.  D0 must have bits 15-8 clear.
|
ATP_CHECKSUM:
        MOVE.B  (A0)+,D0                        | next byte
        ADD     D0,D3                           | add it
        ROL     #0x1,D3                         | rotate left one bit
        SUBQ.W  #0x1,D2                         | count
        BNE.B   ATP_CHECKSUM                    | loop
        RTS                                     | return from ATP_CHECKSUM

| ----------------------------------------------------------
|
| ATP_GETCB: claim a free CB for a call to .MPP -> A3 = CB, D0 = noErr,
| or D0 = noDataArea (all three busy).  A CB is free when its ioRefNum
| is 0; claiming it stores the .MPP refNum there.
|
| Called by: E_ATP_Close, OPENATPSKT, CLOSEATPSKT, SENDRESPONSE,
| ADDRESPONSE, SENDREQUEST, ATP_VBLTASK, RELTCB_FOUND, ATP_LISTENER
ATP_GETCB:
        MOVE.L  (ABusVars_dce).w,A3             | A3 = .MPP DCE (AbusDCE)
        MOVE    dCtlRefNum(A3),D0               | D0 = .MPP refNum
        LEA.L   0xDA(A2),A3                     | first CB (ATPVars+$DA)
        TST     ioRefNum(A3)                    | in use?
        BEQ.B   ATP_GETCB_CLAIM                 | no -> take it
| second CB
        LEA.L   0x142(A2),A3                    | ATPVars+$142
        TST     ioRefNum(A3)                    | in use?
        BEQ.B   ATP_GETCB_CLAIM                 | no -> take it
| third CB
        LEA.L   0x1AA(A2),A3                    | ATPVars+$1AA
        TST     ioRefNum(A3)                    | in use?
        BEQ.B   ATP_GETCB_CLAIM                 | no -> take it
        MOVE    #-0x450,D0                      | noDataArea (-1104): too many outstanding calls
        RTS                                     | return from ATP_GETCB (NE)

| ----------------------------------------------------------
|
| ATP_GETCB_CLAIM: mark CB A3 as in use
|
ATP_GETCB_CLAIM:
        MOVE    D0,ioRefNum(A3)                 | ioRefNum = .MPP refNum (in use)
        CLR     D0                              | noErr (Z set)
        RTS                                     | return from ATP_GETCB

| ----------------------------------------------------------
|
| ATP_FREECB: release CB A3
|
| Called by: OPENATPSKT, CLOSEATPSKT, SENDRESPONSE, ADDRESPONSE,
| SENDREQUEST, ATP_VBLTASK, RELTCB_FOUND, ATP_LISTENER
ATP_FREECB:
        CLR     ioRefNum(A3)                    | ioRefNum = 0 (free)
        RTS                                     | return from ATP_FREECB
    ROM_RESOURCE_END DRVR_10                    | end of the data: pads to even, sets the sizes

| end of resource : 'DRVR' 10 '.ATP'

