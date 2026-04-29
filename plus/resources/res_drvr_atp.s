| DRVR 10 - .ATP (AppleTalk Transaction Protocol) driver
| resource : 'DRVR' 10 '.ATP'
|
| Implements ATP on top of DDP (via .MPP driver):
| - SendRequest: send ATP request, await response
| - GetRequest: listen for incoming ATP requests
| - SendResponse: respond to a received request
| - RelCB: release a completion buffer
| - RelTCB: release a transaction control block
|
| ATP provides reliable request/response transactions over DDP
| with exactly-once semantics via transaction IDs and retransmission.
|
| Data structures:
| ATPVars (at ABusVars+$1E): 530-byte ($212) ATP state block
| +$00: flags
| +$C6: DCE pointer
| +$C8: tick count at open
| +$CA: VBL task record for retry timer (60-tick interval)
|
ATP_CONT:
        DC.W    0x4400                          | drvrFlags (needsLock|needsTime)
  .short 0x0000                                 | drvrDelay (no periodic)
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x0018                                 | drvrOpen offset
  .short 0x01D0                                 | drvrPrime offset
  .short 0x0066                                 | drvrCtl offset
  .short 0x01D0                                 | drvrStatus offset
  .short 0x00EE                                 | drvrClose offset
  .byte 0x04                                    | drvrName length

| Name
  .ascii ".ATP"                                 | drvrName: ATP protocol driver

| end of Name
  .byte 0x20                                    | align to word

| .ATP Open: initialize ATP protocol handler
| Allocates ATPVars block, installs VBL task for retransmission timer
E_ATP_Open:
        MOVE.L  (ABusVars).w,A3                 | A3 = AppleTalk bus variables
        MOVE.L  A3,D1                           | AppleTalk initialized?
        BEQ.B   E_ATP_OPEN_ERR                  | no ->
        TST.L   0x1E(A3)                        | ATP already open? (ATPVars ptr)
        BNE.B   E_ATP_OPEN_ERR                  | yes ->
| allocate ATP state block
        MOVE    #0x212,D0                       | 530 bytes for ATPVars
        _NewPtrSysClear                         | allocate zeroed in system heap
        BRA.B   E_ATP_OPEN_SKIP                 | (skip inline patch data)
  .byte 0xA3,0x1E                               | inline: MOVE.L A0,$1E(A3) patch target
| E_ATP_OPEN_SKIP - resume after inline patch bytes; check ATP state-block alloc result
E_ATP_OPEN_SKIP:
        BNE.B   E_ATP_OPEN_ERR                  | alloc failed ->
| initialize ATP state
        BSET    #0x4,(PortBUse).w               | mark printer port in use by ATP
        MOVE.L  A0,0x1E(A3)                     | store ATPVars pointer
        CLR.B   0x1E(A3)                        | clear ATP flags
        MOVE.B  #0x13,0x7(A1)                   | set DCE flags
| set up VBL task for ATP retransmission timer
        LEA.L   0xC6(A0),A2                     | A2 = ATP DCE/VBL area
        MOVE.L  A1,(A2)+                        | save DCE pointer
        MOVE    (Ticks_LoWord).w,(A2)+          | save open time
        MOVE.L  A2,A0                           | A0 = VBL task record
        ADDQ.W  #0x4,A2                         | skip qLink
        MOVE    #0x1,(A2)+                      | vblType = 1 (vType)
        LEA.L   E_ATP_PRIMESTATUS_RETRY(PC),A1  | VBL proc = ATP retry handler
        MOVE.L  A1,(A2)+                        | vblAddr
        MOVE    #0x3C,(A2)+                     | vblCount = 60 ticks (1 second)
        _VInstall                               | install VBL task
E_ATP_OPEN_ERR:
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_Control
|
| .ATP Control: dispatch ATP control calls
| csCode dispatch: 1=KillIO, 248-255=ATP operations
| ATP csCodes: 248=SendRequest, 249=GetRequest, 250=SendResponse,
| 251=AddResponse, 252=RelTCB, 253=RelRspCB, 254=OpenATPSkt, 255=CloseATPSkt
E_ATP_Control:
        TST.L   (ABusVars).w                    | AppleTalk initialized?
        BNE.B   E_ATP_CONTROL_OK_2              | yes ->
        MOVEQ.L #-0x11,D0                       | ddpLenErr: not initialized
E_ATP_CONTROL_OK:
        BRA     E_ATP_CLOSE_ERR_2               | -> IODone with error
| dispatch on csCode
E_ATP_CONTROL_OK_2:
        MOVE    0x1A(A0),D2                     | D2 = csCode
        BMI.B   E_ATP_CONTROL_CONT              | negative: special handling ->
        SUBQ.W  #0x1,D2                         | csCode 1?
        BNE.B   E_ATP_CONTROL_NO                | no ->
        RTS                                     | csCode 1 = KillIO (no-op, return)
| check for ATP csCode range (248-255)
E_ATP_CONTROL_NO:
        MOVEQ.L #-0x11,D0                       | assume error
        SUBI    #0xF8,D2                        | D2 -= 248 (base ATP csCode)
        BLT.B   E_ATP_CONTROL_OK                | < 248: invalid ->
        CMPI    #0x7,D2                         | > 255?
        BGT.B   E_ATP_CONTROL_OK                | yes, invalid ->
| dispatch via ATP control jump table
        ADD     D2,D2                           | word offset
        LEA.L   DISPATCH_TBL(PC),A3             | ATP control dispatch table
        ADDA    D2,A3                           | index into table
        MOVE    (A3),A3                         | get relative offset
        LEA.L   ATP_CONT(PC),A2                 | base address for offset
        ADDA.L  A2,A3                           | A3 = absolute address of handler
        MOVE.L  (ABusVars).w,A2                 | A2 = ABusVars global
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars block
        MOVE.B  0x1C(A0),D1                     | D1 = atpSocket from IOParam
        SUBI    #0xA,D2                         | csCode >= 254? (OpenATPSkt, CloseATPSkt, SendRequest, RelTCB)
        BPL.B   E_ATP_CONTROL_SKIP              | yes -> skip socket validation
        MOVE    #-0x44B,D0                      | assume badATPSkt error (-1099)
        TST.B   D1                              | atpSocket == 0?
        BEQ.B   E_ATP_CONTROL_ERR               | yes, zero is invalid -> return error
        MOVEQ.L #0x5,D2                         | scan 6 active sockets
E_ATP_CONTROL_LOOP:
        CMP.B   0x30(A2,D2.W),D1                | does atpSocket match this active socket?
        DBEQ    D2,E_ATP_CONTROL_LOOP           | no, keep checking
        BNE.B   E_ATP_CONTROL_ERR               | not found in active list -> return error
E_ATP_CONTROL_SKIP:
        MOVE.L  0x1E(A0),D3                     | D3 = addrBlock from IOParam
        ANDI.B  #0x3F,0x1D(A0)                  | clear reserved bits in atpFlags
        JMP     (A3)                            | jump to specific ATP handler

| ATP control dispatch table (offsets from ATP_CONT)
| 0=SendRequest, 1=GetRequest, 2=SendResponse, 3=AddResponse,
| 4=RelTCB, 5=RelRspCB, 6=OpenATPSkt, 7=CloseATPSkt
DISPATCH_TBL:
  .byte  0x05,0xEC,0x01,0x96,0x02,0xEC          | SendRequest=+1516, GetRequest=+406, SendResponse=+748
  .byte 0x02,0x1E,0x01,0xD8,0x01,0x4E           | AddResponse=+542, RelTCB=+472, RelRspCB=+334
  .byte 0x03,0x80,0x05,0x94                     | OpenATPSkt=+896, CloseATPSkt=+1428
| negative csCode: close and reopen (for low memory situations)
E_ATP_CONTROL_CONT:
        CMPI    #0x2,(MemTop).w                 | < 512K RAM?
        BGT     E_ATP_CLOSE_ERR_2               | no, error ->
        BSR.B   E_ATP_Close                     | close ATP
E_ATP_CONTROL_ERR:
        BRA     E_ATP_CLOSE_ERR                 | -> reopen

| ----------------------------------------------------------
|
| .ATP Close: shut down ATP protocol handler
| Cancels all pending transactions, removes VBL task, frees ATPVars
|
E_ATP_Close:
        MOVE.L  (ABusVars).w,A1                 | A1 = AppleTalk bus vars
        MOVE.L  A1,D0                           | initialized?
        BEQ.B   E_ATP_CLOSE_DONE                | no ->
        MOVE.L  0x1E(A1),A2                     | A2 = ATPVars block
        MOVE.L  A2,D0                           | ATP open?
        BMI.B   E_ATP_CLOSE_NO                  | no (negative = closed) ->
| cancel all pending send requests
E_ATP_CLOSE_CONT:
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | cancel next pending request
        BNE.B   E_ATP_CLOSE_CONT                | more to cancel ->
| close all ATP request listener sockets
        MOVEQ.L #0x6,D2                         | socket table size
        LEA.L   (A2),A0                         | A0 = request socket table
        BSR.B   E_ATP_CLOSE_CONT_4              | close request sockets
E_ATP_CLOSE_CONT_2:
        TST     PORTRECT(A3)                    | wait for close completion
        BGT.B   E_ATP_CLOSE_CONT_2              | still closing ->
| close all ATP response sockets
        MOVEQ.L #0x6,D2                         | socket table size
        LEA.L   0x30(A2),A0                     | A0 = response socket table
        BSR.B   E_ATP_CLOSE_CONT_4              | close response sockets
E_ATP_CLOSE_CONT_3:
        TST     PORTRECT(A3)                    | wait for close completion
        BGT.B   E_ATP_CLOSE_CONT_3              | still closing ->
| remove VBL retry timer and free memory
E_ATP_CLOSE_NO:
        PEA.L   0xCC(A2)                        | VBL task address
        CLR.B   (SP)                            | clear flags byte
        MOVE.L  (SP)+,A0                        | A0 = VBL task
        _VRemove                                | remove from VBL queue
        MOVE.L  A2,A0                           | A0 = ATPVars block
        _DisposePtr                             | free ATPVars memory
        CLR.L   0x1E(A1)                        | clear ATPVars pointer
        BCLR    #0x4,(PortBUse).w               | release printer port
E_ATP_CLOSE_DONE:
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_CLOSE_CONT_4: close all ATP sockets in a socket table
| A0 = socket table (6 entries), D2 = count
|
E_ATP_CLOSE_CONT_4:
        CLR     PORTRECT(A3)                    | clear completion counter
E_ATP_CLOSE_SKIP:
        SUBQ.W  #0x1,D2                         | next socket
        BMI.B   E_ATP_CLOSE_DONE                | all done ->
        MOVE.B  (A0)+,D1                        | D1 = socket number
        BEQ.B   E_ATP_CLOSE_SKIP                | empty slot, skip ->
        MOVE    #0xF7,D0                        | csCode $F7 = CloseDDPSkt (via MPP)
        BSR     E_ATP_PRIMESTATUS_CONT_10       | close this DDP socket
        BRA.B   E_ATP_CLOSE_SKIP                | next

| ----------------------------------------------------------
|
| GetRequest (csCode 249): listen for incoming ATP requests
| Finds a free responder slot, opens a DDP socket, registers listener
|
GETREQUEST:
        MOVE    #-0x44A,D0                      | assume reqFailed error
        MOVEQ.L #0x5,D2                         | scan 6 responder slots
E_ATP_CLOSE_LOOP:
        TST.B   0x30(A2,D2.W)                   | slot in use?
        DBEQ    D2,E_ATP_CLOSE_LOOP             | try next if so
        BNE.B   E_ATP_CLOSE_ERR                 | all full ->
| cancel any pending request on this slot
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | cancel pending
        BNE.B   E_ATP_CLOSE_ERR                 | error ->
| set up listener callback and open DDP socket
        LEA.L   E_ATP_PRIMESTATUS_CONT_21(PC),A1 | ATP request handler proc
        MOVE.L  A1,0x1E(A3)                     | set socket listener
        MOVE    #0xF8,D0                        | csCode $F8 = OpenDDPSkt (via MPP)
        BSR     E_ATP_PRIMESTATUS_CONT_10       | open a DDP socket
        MOVE.B  CLIPRGN(A3),D1                  | D1 = assigned socket number
        BSR     E_ATP_PRIMESTATUS_ERR_11        | register with NBP
        TST     D0                              | registered ok?
        BNE.B   E_ATP_CLOSE_ERR                 | no ->
| store responder state
        LSL     #0x2,D2                         | longword offset
        CLR.L   0x36(A2,D2.W)                   | clear transaction state
        MOVE.L  D3,0x4E(A2,D2.W)                | save request buffer pointer
        LSR     #0x2,D2                         | back to byte offset
        MOVE.B  D1,0x30(A2,D2.W)                | store socket number in slot
        MOVE.B  D1,0x1C(A0)                     | return socket in ioParam
        BRA.B   E_ATP_CLOSE_EXIT                | -> success

| ----------------------------------------------------------
|
| CLOSEATPSKT
|
| CloseATPSkt (csCode 255): close an ATP responder socket
CLOSEATPSKT:
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | cancel pending transactions
        BNE.B   E_ATP_CLOSE_ERR                 | error ->
        MOVE    #0xF7,D0                        | csCode = CloseDDPSkt
        BSR     E_ATP_PRIMESTATUS_CONT_10       | close the DDP socket
        BSR     E_ATP_PRIMESTATUS_ERR_11        | deregister from NBP
        TST     D0                              | ok?
        BNE.B   E_ATP_CLOSE_ERR                 | error ->
| clear responder slot and any associated transaction entries
        CLR.B   0x30(A2,D2.W)                   | clear socket number from slot
        LEA.L   0x66(A2),A1                     | A1 = transaction table (8 entries)
        MOVEQ.L #0x7,D2                         | 8 entries
E_ATP_CLOSE_LOOP_2:
        CMP.B   (A1),D1                         | entry for this socket?
        BNE.B   E_ATP_CLOSE_NO_2                | no ->
        CLR.B   (A1)                            | clear transaction entry
E_ATP_CLOSE_NO_2:
        ADDA    #0xC,A1                         | next entry (12 bytes each)
        DBF     D2,E_ATP_CLOSE_LOOP_2           | loop through all transaction entries
| common success exit
E_ATP_CLOSE_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
| common exit: call IODone
E_ATP_CLOSE_ERR:
        MOVE.L  0xC6(A2),A1                     | A1 = DCE from ATPVars
E_ATP_CLOSE_ERR_2:
        MOVE.L  (JIODone).w,A0                  | JIODone vector
        JMP     (A0)                            | -> IODone with D0 = result

| ----------------------------------------------------------
|
| .ATP Prime/Status: not implemented (just clear busy flag)
|
E_ATP_PrimeStatus:
        BCLR    #0x7,0x5(A1)                    | clear dCtlFlags busy bit
        RTS                                     | return

| ----------------------------------------------------------
|
| ADDRESPONSE
|
| AddResponse (csCode 251): queue a response buffer for a pending request
| Adds the IOParam to the linked list of response buffers at IPL 3
ADDRESPONSE:
        LSL     #0x2,D2                         | longword offset for slot
        LEA.L   0x36(A2,D2.W),A3                | A3 = response queue head for this slot
| walk to end of response queue (at elevated IPL)
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | raise to IPL 3 (disable AppleTalk ints)
E_ATP_PRIMESTATUS_CONT:
        TST.L   (A3)                            | end of queue?
        BEQ.B   E_ATP_PRIMESTATUS_OK            | yes ->
        MOVE.L  (A3),A3                         | follow link
        BRA.B   E_ATP_PRIMESTATUS_CONT          | walk to end of queue
| append this IOParam to end of queue
E_ATP_PRIMESTATUS_OK:
        MOVE.L  A0,(A3)                         | link new buffer at tail
| dequeue and process: start next queued request
E_ATP_PRIMESTATUS_CONT_2:
        MOVE.L  0xC6(A2),A1                     | A1 = DCE
        BCLR    #0x7,0x5(A1)                    | clear busy flag
        MOVE.L  (A0),0x8(A1)                    | move next queued request to active
        BNE.B   E_ATP_PRIMESTATUS_CONT_3        | have one ->
        CLR.L   0xC(A1)                         | no more: clear queue tail
E_ATP_PRIMESTATUS_CONT_3:
        CLR.L   (A0)                            | unlink processed request
        MOVE.L  0x8(A1),D0                      | next request?
        BEQ.B   E_ATP_PRIMESTATUS_NO            | no ->
| process next queued control call
        MOVE.L  D0,A0                           | A0 = next IOParam
        MOVEQ.L #0x0,D0                         | clear error
        BSET    #0x7,0x5(A1)                    | set busy flag
        MOVE    (SP)+,SR                        | restore IPL
        BRA     E_ATP_Control                   | -> re-enter control dispatch
| no more queued: return
E_ATP_PRIMESTATUS_NO:
        MOVE    (SP)+,SR                        | restore IPL
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_4
|
E_ATP_PRIMESTATUS_CONT_4:
        MOVE.L  0x28(A0),A1                     | A1 = bdsPointer (Buffer Data Structure)
        SWAP    D1                              | save atpSocket in high word of D1
        MOVE    #-0x44C,D0                      | assume badBuffNum error (-1100)
        MOVE.B  0x2C(A0),D1                     | D1 = numOfBuffs
        BEQ.B   E_ATP_PRIMESTATUS_ERR           | error if 0 buffers ->
        CMPI.B  #0x8,D1                         | > 8 buffers?
        BHI.B   E_ATP_PRIMESTATUS_ERR_3         | error if > 8 buffers ->
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | A3 = get free ATP control block
        BNE.B   E_ATP_PRIMESTATUS_ERR_3         | error if no blocks available ->
        ST.B    0x61(A3)                        | mark control block as response block
E_ATP_PRIMESTATUS_NEXT:
        LEA.L   RGNSAVE(A3),A3                  | A3 = ATP header area in RCB
        MOVEQ.L #-0x80,D0                       | control byte: response ($80)
        SUBQ.B  #0x1,D1                         | decrement buffer count
        BNE.B   E_ATP_PRIMESTATUS_SKIP          | if not last buffer, skip EOM flag ->
        OR.B    0x1D(A0),D0                     | if last buffer, include EOM flag from atpFlags
E_ATP_PRIMESTATUS_SKIP:
        MOVE.B  D0,(A3)+                        | store control byte
        ADDQ.B  #0x1,(A3)+                      | increment sequence number
        MOVE    0x2E(A0),(A3)+                  | store transaction ID
        MOVE    (A1)+,D0                        | D0 = buffSize from BDS
        MOVE.L  (A1)+,D2                        | D2 = buffPtr from BDS
        MOVE    #-0x1,(A1)+                     | set dataSize in BDS to pending (-1)
        MOVE.L  (A1)+,(A3)+                     | store userBytes into ATP header
        LEA.L   -GRAFPROCS(A3),A3               | restore A3 to CB base
        SWAP    D1                              | D1 = atpSocket
        BSR     E_ATP_PRIMESTATUS_CONT_9        | build WriteDDP param block and send async
        CMPI    #-0x5C,D0                       | badATPSkt error from _Control?
        BEQ.B   E_ATP_PRIMESTATUS_ERR_2         | yes -> error
        SWAP    D1                              | restore D1 = remaining buffer count
        TST.B   D1                              | was this the last buffer?
        BNE.B   E_ATP_PRIMESTATUS_NEXT          | no, loop to send next buffer ->
        BSR     E_ATP_PRIMESTATUS_ERR_11        | release control block
E_ATP_PRIMESTATUS_ERR:
        SWAP    D1                              | restore D1 = atpSocket
        MOVE.B  0x2D(A0),D2                     | D2 = bdsSize (total buffers)
        SUB.B   0x2C(A0),D2                     | calculate unsent buffers
        BEQ.B   E_ATP_PRIMESTATUS_CONT_5        | all buffers sent ->
E_ATP_PRIMESTATUS_LOOP:
        CLR     0x6(A1)                         | clear dataSize for unused BDS entry
        ADDA    #0xC,A1                         | advance to next BDS entry
        SUBQ.B  #0x1,D2                         | decrement unused count
        BNE.B   E_ATP_PRIMESTATUS_LOOP          | loop until all cleared
E_ATP_PRIMESTATUS_CONT_5:
        MOVE    0x2E(A0),D0                     | D0 = transaction ID
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | disable interrupts (IPL 3)
        BSR.B   E_ATP_PRIMESTATUS_CONT_6        | find transaction control block
        BNE     E_ATP_PRIMESTATUS_ERR_4         | not found -> error exit
        MOVE.L  A0,0x8(A1)                      | store IOParam in TCB
        CLR.B   0x1(A1)                         | clear TCB busy flag
        BRA     E_ATP_PRIMESTATUS_CONT_2        | -> queue completion

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_ERR_2
|
E_ATP_PRIMESTATUS_ERR_2:
        BSR     E_ATP_PRIMESTATUS_ERR_11        | release control block
E_ATP_PRIMESTATUS_ERR_3:
        BRA     E_ATP_CLOSE_ERR                 | -> IODone with error

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_6
|
| E_ATP_PRIMESTATUS_CONT_6: find a transaction control block (TCB) by transaction ID
| D0 = transaction ID -> A1 = TCB entry, NE if not found
E_ATP_PRIMESTATUS_CONT_6:
        LEA.L   0x66(A2),A1                     | A1 = transaction table base
        MOVEQ.L #0x7,D2                         | scan 8 entries
E_ATP_PRIMESTATUS_LOOP_2:
        CMP.B   (A1),D1                         | socket matches?
        BNE.B   E_ATP_PRIMESTATUS_NO_2          | no ->
        ADDQ.W  #0x2,A1                         | point to address block
        BSR.B   E_ATP_PRIMESTATUS_FOUND_2       | network address matches?
        SUBQ.W  #0x2,A1                         | restore pointer
        BNE.B   E_ATP_PRIMESTATUS_NO_2          | no ->
        CMP     0x6(A1),D0                      | transaction ID matches?
        BEQ.B   E_ATP_PRIMESTATUS_FOUND         | yes -> found
E_ATP_PRIMESTATUS_NO_2:
        ADDA    #0xC,A1                         | advance to next TCB entry
        DBF     D2,E_ATP_PRIMESTATUS_LOOP_2     | loop
E_ATP_PRIMESTATUS_FOUND:
        RTS                                     | return (Z flag set if found)

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_FOUND_2
|
| E_ATP_PRIMESTATUS_FOUND_2: compare network address with transaction entry
| D3 = source address, A1 = TCB entry -> EQ if match
E_ATP_PRIMESTATUS_FOUND_2:
        CMP.L   (A1),D3                         | full address match?
        BEQ.B   E_ATP_PRIMESTATUS_FOUND_3       | yes ->
        CMP     0x2(A1),D3                      | node+socket match?
        BNE.B   E_ATP_PRIMESTATUS_FOUND_3       | no ->
        TST     (A1)                            | network number zero? (any network)
        BEQ.B   E_ATP_PRIMESTATUS_FOUND_3       | yes, matches ->
        MOVE.L  D3,-(SP)                        | push for comparison
        TST     (SP)+                           | test network part
        ADDQ.W  #0x2,SP                         | pop
E_ATP_PRIMESTATUS_FOUND_3:
        RTS                                     | return

| ----------------------------------------------------------
|
| SendRequest (csCode 248): send an ATP request packet
| Builds DDP packet with ATP header, sends via WriteDDP
|
SENDREQUEST:
        MOVE    #-0x44C,D0                      | assume reqAborted error
        MOVE.B  0x2C(A0),D2                     | D2 = response bitmap
        CMPI.B  #0x8,D2                         | max 8 response packets
        BCC.B   E_ATP_PRIMESTATUS_ERR_3         | too many ->
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | allocate request control block
        BNE.B   E_ATP_PRIMESTATUS_ERR_3         | failed ->
        MOVEQ.L #-0x5C,D0                       | assume badATPSkt
        CMPI    #0x242,0x22(A0)                 | buffer too large? (578 bytes max)
        BHI.B   E_ATP_PRIMESTATUS_ERR_3         | yes ->
| build ATP request header
        LEA.L   RGNSAVE(A3),A3                  | A3 = ATP header area in RCB
        MOVEQ.L #-0x80,D0                       | control byte: request ($80)
        OR.B    0x1D(A0),D0                     | merge XO/STS flags from csParam
        MOVE.B  D0,(A3)+                        | store control byte
        MOVE.B  D2,(A3)+                        | store bitmap
        MOVE    0x2E(A0),(A3)+                  | store transaction ID
| send the request via DDP
        BSR     E_ATP_PRIMESTATUS_CONT_13       | set up destination address
        BSR     E_ATP_PRIMESTATUS_CONT_9        | send ATP request via WriteDDP
        BSR     E_ATP_PRIMESTATUS_ERR_11        | register for response
        MOVE    0x2E(A0),D0                     | D0 = transaction ID
        MOVE    SR,-(SP)                        | save SR for critical section
| enter critical section and look up transaction
        MOVE    #0x2600,SR                      | raise IPL 3
  .short 0x6180                                 | Bsr.B E_ATP_PRIMESTATUS_CONT_6 - find TCB by transaction ID
        BNE.B   E_ATP_PRIMESTATUS_ERR_4         | not found ->
| found existing transaction: merge response data
        MOVE.L  0x8(A1),A3                      | A3 = original request IOParam
        MOVE    #-0x44F,D0                      | assume tooManyReqs
        MOVE.L  A3,D2                           | still have original request?
        BEQ.B   E_ATP_PRIMESTATUS_NO_4          | no ->
        MOVE.B  0x1D(A0),D2                     | merge control flags
        OR.B    D2,0x1D(A3)                     | update original request flags
| store response buffer info in response descriptor array
        CLR     D2                              | zero-extend for index
        MOVE.B  0x2C(A0),D2                     | D2 = response sequence number
        LEA.L   0x2C(A3),A3                     | A3 = response count ptr
        CMP.B   (A3),D2                         | new sequence > current count?
        BLT.B   E_ATP_PRIMESTATUS_NO_3          | no ->
        MOVE.B  D2,(A3)                         | update count
        ADDQ.B  #0x1,(A3)                       | + 1 (count is 1-based)
E_ATP_PRIMESTATUS_NO_3:
        MOVE.L  -(A3),A3                        | A3 = response descriptor array base
        MULU    #0xC,D2                         | descriptor is 12 bytes
        ADDA    D2,A3                           | index to this response's descriptor
        MOVE    0x22(A0),(A3)+                  | store response data length
        MOVE.L  0x24(A0),(A3)+                  | store response data pointer
        MOVE    #-0x1,(A3)+                     | mark as received (-1)
        MOVE.L  0x12(A0),(A3)                   | store user reference
        CLR.B   0x1(A1)                         | clear TCB busy flag
E_ATP_PRIMESTATUS_ERR_4:
        CLR     D0                              | noErr
E_ATP_PRIMESTATUS_NO_4:
        MOVE    (SP)+,SR                        | restore IPL
E_ATP_PRIMESTATUS_ERR_5:
        BRA     E_ATP_CLOSE_ERR                 | -> IODone

| ----------------------------------------------------------
|
| SendResponse (csCode 250): send response to an ATP request
|
SENDRESPONSE:
        MOVE    #-0x449,D0                      | assume noRelErr
        MOVEQ.L #0x5,D2                         | scan 6 responder slots
E_ATP_PRIMESTATUS_LOOP_3:
        TST.B   0x0(A2,D2.W)                    | slot in use?
        DBEQ    D2,E_ATP_PRIMESTATUS_LOOP_3     | try next
        BNE.B   E_ATP_PRIMESTATUS_ERR_5         | all empty ->
        MOVEQ.L #-0x5C,D0                       | badATPSkt
        CMPI    #0x242,0x22(A0)                 | data too large?
        BHI.B   E_ATP_PRIMESTATUS_ERR_5         | yes, error ->
        CLR.B   D1                              | D1 = 0
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | allocate control block
        BNE.B   E_ATP_PRIMESTATUS_ERR_5         | failed -> error
        LEA.L   E_ATP_PRIMESTATUS_CONT_21(PC),A1 | ATP packet listener
        MOVE.L  A1,0x1E(A3)                     | save in control block
        MOVE    #0xF8,D0                        | csCode = AttachPH (via MPP)
        BSR     E_ATP_PRIMESTATUS_CONT_10       | issue async MPP call
        BEQ.B   E_ATP_PRIMESTATUS_CONT_7        | success ->
        BSR     E_ATP_PRIMESTATUS_ERR_11        | release control block on error
        BRA.B   E_ATP_PRIMESTATUS_ERR_5         | -> error exit

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_7
|
| DDP socket opened: set up response state
E_ATP_PRIMESTATUS_CONT_7:
        MOVE.B  CLIPRGN(A3),D1                  | D1 = assigned socket number
| build response bitmap (bits 0..N-1 set for N response packets)
        LEA.L   0x1D(A0),A1                     | A1 = control flags in IOParam
        BCLR    #0x4,(A1)                       | clear EOM flag
        CLR.B   -(A1)                           | clear bitmap byte
        MOVE.B  0x2C(A0),D0                     | D0 = number of response packets
        BEQ.B   E_ATP_PRIMESTATUS_EMPTY         | zero packets ->
        SUBQ.B  #0x1,D0                         | D0 = last bit index
E_ATP_PRIMESTATUS_CONT_8:
        BSet    D0,(A1)                         | set bit for this packet
        SUBQ.B  #0x1,D0                         | next lower bit
        BPL.B   E_ATP_PRIMESTATUS_CONT_8        | more bits ->
| store response state in responder table
E_ATP_PRIMESTATUS_EMPTY:
        CLR.B   0x2E(A0)                        | clear retry counter
        LSL     #0x2,D2                         | longword offset in table
        MOVE.L  A0,0x6(A2,D2.W)                 | store IOParam in responder slot
        LSR     #0x1,D2                         | word offset
| assign transaction ID from sequence counter
        LEA.L   0xCA(A2),A1                     | A1 = ATP sequence counter
        MOVE    (A1),0x1E(A2,D2.W)              | store current TID in slot
        MOVE    (A1),0x16(A0)                   | store TID in IOParam
        BSET    #0x1,0x1D(A0)                   | set STS (send transaction status) flag
        ADDQ.W  #0x1,(A1)                       | increment sequence counter
| store socket and retry state
        LSR     #0x1,D2                         | byte offset
        MOVE.B  D1,0x0(A2,D2.W)                 | store socket number in slot
        LEA.L   0x2A(A2,D2.W),A1                | A1 = retry count for this slot
        CLR.B   (A1)                            | reset retry count
| send the first response packet
        LSL     #0x1,D2                         | word offset
        BSR     E_ATP_PRIMESTATUS_CONT_12       | build response DDP header
        BSR.B   E_ATP_PRIMESTATUS_CONT_9        | send response via WriteDDP
        BSR     E_ATP_PRIMESTATUS_ERR_11        | register for release
        MOVE.B  0x2D(A0),(A1)                   | save response count
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | disable interrupts (IPL 3)
        BRA     E_ATP_PRIMESTATUS_CONT_2        | -> queue completion

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_9
|
| E_ATP_PRIMESTATUS_CONT_9: build WriteDDP param block for ATP packet
| Sets up DDP header fields, data pointer, destination address
| Called by: E_ATP_PRIMESTATUS_SKIP, SENDREQUEST, E_ATP_PRIMESTATUS_EMPTY, E_ATP_PRIMESTATUS_RETRY_2, E_ATP_PRIMESTATUS_OK_2 (and 2 more)
E_ATP_PRIMESTATUS_CONT_9:
        MOVEM.L A0-A1,-(SP)                     | save IOParam and DCE
        BTST    #0x0,0x1D(A0)                   | XO (exactly-once) flag?
        SNE.B   0x1D(A3)                        | copy to DDP control byte
        ANDI.B  #0xF8,RGNSAVE(A3)               | clear low 3 bits of ATP control
        LEA.L   PNPAT(A3),A1                    | A1 = DDP param block area
        MOVE.L  A1,0x1E(A3)                     | store param block ptr
        ADDQ.W  #0x2,A1                         | skip header
| set up DDP destination address
        LEA.L   0x4F(A3),A0                     | A0 = dest address area
        MOVE.L  A0,(A1)+                        | store dest address ptr
        MOVE.B  #0x3,0xF(A0)                    | ATP socket type = 3
        ADDQ.W  #0x7,A0                         | point to address fields
        MOVE.L  D3,(A0)+                        | destination network + node
        MOVE    D3,(A0)+                        | destination socket
        MOVE.B  D3,(A0)                         | copy low byte
| set up data pointer and length
        MOVE    #0x8,(A1)+                      | ATP header size = 8 bytes
        LEA.L   RGNSAVE(A3),A0                  | A0 = ATP header data
        MOVE.L  A0,(A1)+                        | data pointer
        MOVE    D0,(A1)+                        | data length
        MOVE.L  D2,(A1)+                        | user data
        CLR     (A1)+                           | clear padding
        MOVEM.L (SP)+,A0-A1                     | restore regs
| send via MPP WriteDDP control call
        MOVE    #0xF6,D0                        | csCode = WriteDDP (via MPP)
| E_ATP_PRIMESTATUS_CONT_10: issue async MPP control call
| Saves state in RCB, sends _ControlAsync, returns via completion
| Called by: E_ATP_CLOSE_SKIP, E_ATP_CLOSE_LOOP, CLOSEATPSKT, E_ATP_PRIMESTATUS_LOOP_3, E_ATP_PRIMESTATUS_CONT_14 (and 2 more)
E_ATP_PRIMESTATUS_CONT_10:
        MOVEM.L D1-D3/A0-A1,0x22(A3)            | save regs in RCB
        MOVE.L  (SP)+,0x36(A3)                  | save return address in RCB
        LEA.L   E_ATP_PRIMESTATUS_CONT_11(PC),A0 | completion routine
        MOVE.L  A0,0xC(A3)                      | ioCompletion = E_ATP_PRIMESTATUS_CONT_11
        MOVE.L  A3,A0                           | A0 = param block
        MOVE.B  D1,0x1C(A0)                     | socket number
        MOVE    D0,0x1A(A0)                     | csCode
        _ControlAsync                           | send async control call to MPP
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_11: completion routine for MPP control calls
| Restores state from RCB and returns to ATP caller
|
E_ATP_PRIMESTATUS_CONT_11:
        MOVE.L  A0,A3                           | A3 = completed param block
        MOVE.L  0x36(A0),-(SP)                  | push saved return address
        MOVEM.L 0x22(A0),D1-D3/A0-A1            | restore saved regs
        MOVE.L  (ABusVars).w,A2                 | A2 = ABusVars
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        TST     D0                              | set condition codes from result
        RTS                                     | return to ATP caller

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_12: build ATP response header
| Sets control byte to $40 (response), copies bitmap and TID
|
E_ATP_PRIMESTATUS_CONT_12:
        LEA.L   RGNSAVE(A3),A3                  | A3 = ATP header area
        MOVEQ.L #0x40,D0                        | response control byte ($40)
        OR.B    0x1D(A0),D0                     | merge EOM/STS flags
        BCLR    #0x4,D0                         | clear reserved bit
        MOVE.B  D0,(A3)+                        | store control byte
        MOVE.B  0x1C(A0),(A3)+                  | store bitmap/sequence
        MOVE    0x1E(A2,D2.W),(A3)+             | store transaction ID
        MOVE.L  0x1E(A0),D3                     | D3 = destination address
| E_ATP_PRIMESTATUS_CONT_13: common: set up data pointer and length from IOParam
E_ATP_PRIMESTATUS_CONT_13:
        MOVE.L  0x12(A0),(A3)                   | user data longword
        MOVE    0x22(A0),D0                     | D0 = data length
        MOVE.L  0x24(A0),D2                     | D2 = data pointer
        SUBA    #0x64,A3                        | back up to param block base
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_RETRY: VBL retry timer callback (runs every 60 ticks)
| Scans all pending ATP transactions and retransmits if needed
|
E_ATP_PRIMESTATUS_RETRY:
        MOVE    #0x3C,0xA(A0)                   | reschedule for 60 ticks (1 second)
        LEA.L   -0xCC(A0),A2                    | A2 = ATPVars (VBL record is at +$CC)
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | get pending request
        BNE.B   E_ATP_PRIMESTATUS_EMPTY_3       | none ->
        MOVEQ.L #0x6,D2                         | scan 7 responder slots
| scan responder slots for transactions needing retransmit
E_ATP_PRIMESTATUS_NEXT_2:
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | raise IPL
E_ATP_PRIMESTATUS_EMPTY_2:
        SUBQ.W  #0x1,D2                         | next slot
        BMI.B   E_ATP_PRIMESTATUS_CONT_15       | all scanned ->
        MOVE.B  0x0(A2,D2.W),D1                 | socket number for this slot
        BEQ.B   E_ATP_PRIMESTATUS_EMPTY_2       | empty slot ->
        LEA.L   0x2A(A2,D2.W),A1                | A1 = retry timer for this slot
        TST.B   (A1)                            | timer active?
        BEQ.B   E_ATP_PRIMESTATUS_EMPTY_2       | no ->
        SUBQ.B  #0x1,(A1)                       | decrement timer
        BNE.B   E_ATP_PRIMESTATUS_EMPTY_2       | not expired yet ->
| timer expired: check if retransmit limit reached
        MOVE    D2,D3                           | copy transaction index
        LSL     #0x2,D3                         | longword offset
        MOVE.L  0x6(A2,D3.W),A0                 | A0 = IOParam for this transaction
        CMPI.B  #0xFF,0x2F(A0)                  | infinite retries?
        BEQ.B   E_ATP_PRIMESTATUS_RETRY_2       | yes, always retry ->
        SUBQ.B  #0x1,0x2F(A0)                   | decrement retry count
        BCS.B   E_ATP_PRIMESTATUS_CONT_14       | exhausted -> give up
| retransmit the response
E_ATP_PRIMESTATUS_RETRY_2:
        MOVE.B  0x2D(A0),(A1)                   | reset retry timer
        MOVE    D2,A1                           | save slot index
        LSL     #0x1,D2                         | word offset
        BSR.B   E_ATP_PRIMESTATUS_CONT_12       | build response ATP header
        MOVE    (SP)+,SR                        | restore IPL
        BSR     E_ATP_PRIMESTATUS_CONT_9        | retransmit via WriteDDP
        MOVE    A1,D2                           | restore slot index
        BRA.B   E_ATP_PRIMESTATUS_NEXT_2        | scan next slot
| retry limit reached: give up on this transaction
E_ATP_PRIMESTATUS_CONT_14:
        MOVE    (SP)+,SR                        | restore IPL
        CLR.B   0x0(A2,D2.W)                    | clear socket from slot
        MOVE    #0xF7,D0                        | CloseDDPSkt
        BSR     E_ATP_PRIMESTATUS_CONT_10       | close the DDP socket
        MOVE    #-0x448,D0                      | reqFailed error
        BSR     E_ATP_PRIMESTATUS_ERR_6         | complete IOParam with error
        BRA.B   E_ATP_PRIMESTATUS_NEXT_2        | scan next slot
| all responder slots scanned: now scan request TCBs
E_ATP_PRIMESTATUS_CONT_15:
        MOVE    (SP)+,SR                        | restore IPL
        BSR     E_ATP_PRIMESTATUS_ERR_11        | clean up
| scan transaction control blocks for pending request retransmits
E_ATP_PRIMESTATUS_EMPTY_3:
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | raise IPL
        MOVEQ.L #0x8,D2                         | 8 TCB entries
        LEA.L   0x66(A2),A3                     | A3 = TCB table base
E_ATP_PRIMESTATUS_NEXT_3:
        SUBQ.W  #0x1,D2                         | next TCB
        BMI.B   E_ATP_PRIMESTATUS_CONT_16       | all scanned ->
| check TCB: is it active and has timer expired?
        TST.B   (A3)+                           | TCB socket number (0 = empty)
        BEQ.B   E_ATP_PRIMESTATUS_EMPTY_4       | empty ->
        ADDQ.B  #0x1,(A3)                       | increment idle timer
        CMPI.B  #0x1E,(A3)                      | 30 ticks = timeout?
        BNE.B   E_ATP_PRIMESTATUS_EMPTY_4       | not yet ->
| TCB timed out: abort the pending request
        MOVE.L  0x7(A3),A0                      | A0 = IOParam for this TCB
        CLR.B   -0x1(A3)                        | clear TCB socket (free it)
        MOVE.L  A0,D0                           | have IOParam?
        BEQ.B   E_ATP_PRIMESTATUS_EMPTY_4       | no ->
        MOVE    #-0x44D,D0                      | noDataArea error
        BSR.B   E_ATP_PRIMESTATUS_ERR_6         | complete with error
E_ATP_PRIMESTATUS_EMPTY_4:
        ADDA    #0xB,A3                         | advance to next TCB (12 bytes)
        BRA.B   E_ATP_PRIMESTATUS_NEXT_3        | scan next
| all TCBs scanned: done
E_ATP_PRIMESTATUS_CONT_16:
        MOVE    (SP)+,SR                        | restore IPL
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_ERR_6: complete an IOParam with error code D0
| Calls the ioCompletion routine if installed
|
| Called by: E_ATP_PRIMESTATUS_CONT_14, E_ATP_PRIMESTATUS_NEXT_3, E_ATP_PRIMESTATUS_FOUND_5, E_ATP_PRIMESTATUS_CONT_18, E_ATP_PRIMESTATUS_CONT_20 (and 2 more)
E_ATP_PRIMESTATUS_ERR_6:
        MOVE    D0,0x10(A0)                     | store result in ioResult
        MOVEM.L D1-D3/A0-A3,-(SP)               | save all regs
        MOVE.L  0xC(A0),D1                      | D1 = ioCompletion proc
        BEQ.B   E_ATP_PRIMESTATUS_NO_5          | no completion ->
        MOVE.L  D1,A1                           | A1 = completion routine
        TST     D0                              | set CC from result
        JSR     (A1)                            | call completion routine
E_ATP_PRIMESTATUS_NO_5:
        MOVEM.L (SP)+,D1-D3/A0-A3               | restore regs
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_17: ATP request received (DDP listener callback)
| Dispatched when an incoming ATP request arrives on an open socket
|
E_ATP_PRIMESTATUS_CONT_17:
        MOVE    0x2E(A0),D1                     | D1 = transaction ID from packet
        MOVEQ.L #0x5,D2                         | scan 6 responder slots
E_ATP_PRIMESTATUS_LOOP_4:
        TST.B   0x0(A2,D2.W)                    | slot active?
        BEQ.B   E_ATP_PRIMESTATUS_NO_6          | no ->
        MOVE    D2,D0                           | copy slot index
        LSL     #0x1,D0                         | word offset
        CMP     0x1E(A2,D0.W),D1                | TID matches?
        BNE.B   E_ATP_PRIMESTATUS_NO_6          | no ->
        LSL     #0x1,D0                         | longword offset
        MOVE.L  0x6(A2,D0.W),A0                 | A0 = IOParam for this transaction
        LEA.L   0x1E(A0),A1                     | A1 = address in IOParam
        BSR     E_ATP_PRIMESTATUS_FOUND_2       | compare source address
        BEQ.B   E_ATP_PRIMESTATUS_FOUND_5       | match: this is a retransmit ->
E_ATP_PRIMESTATUS_NO_6:
        DBF     D2,E_ATP_PRIMESTATUS_LOOP_4     | try next slot
E_ATP_PRIMESTATUS_FOUND_4:
        MOVE    #-0x44E,D0                      | cbNotFound error (-1102)
        BRA     E_ATP_CLOSE_ERR                 | -> IODone

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_FOUND_5
|
| retransmit detected: close old socket, complete old request
E_ATP_PRIMESTATUS_FOUND_5:
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | get pending request
        BNE     E_ATP_CLOSE_ERR                 | none ->
        MOVE.B  0x0(A2,D2.W),D1                 | D1 = old socket number
        CLR.B   0x0(A2,D2.W)                    | clear slot
        MOVE    #0xF7,D0                        | CloseDDPSkt
        BSR     E_ATP_PRIMESTATUS_CONT_10       | close old socket
        BSR     E_ATP_PRIMESTATUS_ERR_11        | clean up
        MOVE    #-0x451,D0                      | cbNotFound error
        BSR.B   E_ATP_PRIMESTATUS_ERR_6         | complete old request with error
E_ATP_PRIMESTATUS_EXIT:
        BRA     E_ATP_CLOSE_EXIT                | -> success exit

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_18: ATP release received (release transaction)
| Remote side acknowledges our response, free the TCB
|
E_ATP_PRIMESTATUS_CONT_18:
        MOVE    0x2E(A0),D0                     | D0 = transaction ID
        BSR     E_ATP_PRIMESTATUS_CONT_6        | find matching TCB
        BNE.B   E_ATP_PRIMESTATUS_FOUND_4       | not found ->
        MOVE.L  0x8(A1),A0                      | A0 = pending IOParam
        CLR.B   (A1)                            | free the TCB entry
        MOVE.L  A0,D0                           | have pending IOParam?
        BEQ.B   E_ATP_PRIMESTATUS_NO_7          | no ->
        CLR     D0                              | noErr
        BSR     E_ATP_PRIMESTATUS_ERR_6         | complete the IOParam
E_ATP_PRIMESTATUS_NO_7:
        BRA.B   E_ATP_PRIMESTATUS_EXIT          | -> exit

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_SKIP_2: ATP packet not for us - discard and return
|
E_ATP_PRIMESTATUS_SKIP_2:
        CLR     D3                              | clear result
        ADDQ.W  #0x4,SP                         | pop return address
        JMP     0x2(A4)                         | return to DDP listener framework

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_19: incoming ATP packet - dispatch by socket
| D2 = ATP control byte, D0 = dest socket
|
E_ATP_PRIMESTATUS_CONT_19:
        ADD.B   D2,D2                           | test request/response bit
        BPL.B   E_ATP_PRIMESTATUS_SKIP_2        | not a request, discard ->
| find responder slot matching this socket
        MOVEQ.L #0x5,D2                         | scan 6 slots
E_ATP_PRIMESTATUS_LOOP_5:
        CMP.B   0x30(A5,D2.W),D0                | socket match?
        DBEQ    D2,E_ATP_PRIMESTATUS_LOOP_5     | no, try next
        BNE.B   E_ATP_PRIMESTATUS_SKIP_2        | not found, discard ->
| found matching slot: get response buffer
        LSL     #0x2,D2                         | longword offset
        MOVE.L  0x36(A5,D2.W),A5                | A5 = response IOParam
        MOVE.L  A5,D0                           | valid?
        BEQ.B   E_ATP_PRIMESTATUS_NO_8          | no ->
        MOVE    0x22(A5),D3                     | D3 = response data length
        MOVE.L  0x24(A5),A3                     | A3 = response data pointer
E_ATP_PRIMESTATUS_NO_8:
        JSR     0x2(A4)                         | call DDP send framework
        BSR     E_ATP_PRIMESTATUS_CONT_24       | check send result
        MOVE.L  (SP)+,A3                        | restore A3
        BEQ     E_ATP_PRIMESTATUS_OK_3          | send ok ->
E_ATP_PRIMESTATUS_ERR_7:
        RTS                                     | return to DDP framework

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_FOUND_6: unknown ATP type, discard
|
E_ATP_PRIMESTATUS_FOUND_6:
        BRA.B   E_ATP_PRIMESTATUS_SKIP_2        | -> discard packet

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_20: ATP response received (for pending SendRequest)
| Match by TID, copy response data, complete the request
|
E_ATP_PRIMESTATUS_CONT_20:
        MOVE.B  D0,D2                           | D2 = sequence number
        MOVE.L  (SP)+,A3                        | A3 = packet data
        JSR     0x2(A4)                         | read DDP data
        BSR     E_ATP_PRIMESTATUS_CONT_24       | validate
        BNE.B   E_ATP_PRIMESTATUS_ERR_7         | error ->
        MOVE.L  D1,D3                           | D3 = source address
        MOVE    -0x6(A3),D0                     | D0 = transaction ID from packet
        MOVE.B  D2,D1                           | D1 = socket
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        BSR     E_ATP_PRIMESTATUS_CONT_6        | find matching TCB
        BNE.B   E_ATP_PRIMESTATUS_ERR_7         | not found ->
| found: deliver response to waiting request
        CLR.B   (A1)                            | free the TCB
        MOVE.L  0x8(A1),D0                      | D0 = pending IOParam
        BEQ.B   E_ATP_PRIMESTATUS_ERR_7         | none ->
        MOVE.L  D0,A0                           | A0 = IOParam
        MOVE.L  -(A3),0x12(A0)                  | copy user data from packet
        CLR     D0                              | noErr
        BRA     E_ATP_PRIMESTATUS_ERR_6         | complete the IOParam

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_21: DDP socket listener for incoming ATP requests
| Called by DDP when a packet arrives on an ATP socket
|
E_ATP_PRIMESTATUS_CONT_21:
        MOVEQ.L #0x8,D3                         | ATP header = 8 bytes
        SUBQ.W  #0x1,A3                         | back up for header read
        JSR     (A4)                            | read ATP header from DDP packet
E_ATP_PRIMESTATUS_ERR_8:
        BNE.B   E_ATP_PRIMESTATUS_ERR_7         | read error ->
        MOVE.L  0x1E(A2),A5                     | A5 = ATPVars
        MOVE.L  A3,-(SP)                        | save packet data ptr
        SUBQ.W  #0x8,A3                         | back up to ATP header
        MOVE.B  -PORTBITS(A3),D0                | D0 = dest socket from DDP header
        MOVE.B  (A3)+,D2                        | D2 = ATP control byte
  .short 0x6A80                                 | BPL.B E_ATP_PRIMESTATUS_CONT_19
        ADD.B   D2,D2                           | shift control byte left
        BMI.B   E_ATP_PRIMESTATUS_CONT_20       | if high bit set (TResp), handle response ->
        MOVEQ.L #0x5,D2                         | scan 6 active sockets
E_ATP_PRIMESTATUS_LOOP_6:
        CMP.B   0x0(A5,D2.W),D0                 | socket matches?
        DBEQ    D2,E_ATP_PRIMESTATUS_LOOP_6     | loop until match or end
| discard if socket not found
        BNE.B   E_ATP_PRIMESTATUS_FOUND_6       | no match ->
| look up response buffer for this socket/sequence
        LSL     #0x2,D2                         | longword offset
        MOVE.L  0x6(A5,D2.W),A5                 | A5 = response IOParam
        MOVE.B  (A3),D3                         | D3 = sequence number from ATP header
        CMP.B   0x2C(A5),D3                     | sequence >= response count?
        BCC.B   E_ATP_PRIMESTATUS_FOUND_6       | yes, invalid ->
| compute response descriptor index
        ASL     #0x2,D3                         | * 4
        MOVE    D3,D0                           | copy for multiply
        ADD     D0,D3                           | * 8
        ADD     D0,D3                           | * 12 (descriptor size)
        MOVE.L  0x28(A5),A3                     | A3 = response descriptor array
        ADDA    D3,A3                           | index to this descriptor
        MOVE    (A3)+,D3                        | D3 = data length for this response
        MOVE.L  (A3)+,A3                        | A3 = data pointer
| send the response packet via DDP
        JSR     0x2(A4)                         | call DDP send
        BSR     E_ATP_PRIMESTATUS_CONT_24       | validate send
        MOVE.L  (SP)+,A3                        | restore A3
        BNE.B   E_ATP_PRIMESTATUS_ERR_8         | send error ->
| verify the request matches our pending transaction
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        MOVE.L  0x6(A2,D2.W),A0                 | A0 = response IOParam
        LEA.L   0x1E(A0),A1                     | A1 = address in IOParam
        EXG     D1,D3                           | swap for E_ATP_PRIMESTATUS_FOUND_2
        BSR     E_ATP_PRIMESTATUS_FOUND_2       | verify source address
        EXG     D1,D3                           | restore
        BNE.B   E_ATP_PRIMESTATUS_ERR_8         | address mismatch ->
| valid request: check TID and bitmap
        LSR     #0x1,D2                         | word offset
        MOVE.L  -(A3),D1                        | D1 = user data from packet
        MOVE    -(A3),D0                        | D0 = transaction ID
        CMP     0x1E(A2,D2.W),D0                | matches our TID?
        BNE.B   E_ATP_PRIMESTATUS_ERR_8         | no ->
| process bitmap: mark received packets
        MOVE.B  -(A3),D0                        | D0 = bitmap/sequence byte
        CMPI.B  #0x7,D0                         | valid sequence? (0-7)
        BHI.B   E_ATP_PRIMESTATUS_ERR_8         | no ->
        EXT     D0                              | extend for multiply
        MULU    #0xC,D0                         | descriptor offset
        MOVE.L  0x28(A0),A1                     | A1 = our response descriptor array
        ADDA    D0,A1                           | index to this packet's descriptor
        MOVE    (A1),D0                         | D0 = max data length
        ADDQ.W  #0x6,A1                         | skip to actual data area
        SUB     D3,D0                           | D0 = remaining space
        MOVE    D0,(A1)+                        | store actual received length
        MOVE.L  D1,(A1)+                        | store user data
| update bitmap: clear bit for received packet
        LEA.L   0x1C(A0),A1                     | A1 = bitmap in IOParam
        MOVE.B  (A3),D3                         | D3 = sequence number
        SUBQ.W  #0x1,A3                         | back up to control byte
        BCLR    D3,(A1)                         | clear bitmap bit for this packet
        BEQ.B   E_ATP_PRIMESTATUS_OK_2          | was already clear ->
        ADDQ.B  #0x1,0x2E(A0)                   | increment received count
| check EOM (end of message): clear remaining bitmap bits
        MOVEQ.L #0x4,D1                         | EOM bit position
        BTST    D1,(A3)                         | EOM set in control byte?
        BEQ.B   E_ATP_PRIMESTATUS_OK_2          | no ->
E_ATP_PRIMESTATUS_NO_9:
        BClr    D3,(A1)                         | clear remaining bits
        ADDQ.B  #0x1,D3                         | next bit
        CMPI.B  #0x8,D3                         | past bit 7?
        BNE.B   E_ATP_PRIMESTATUS_NO_9          | no ->
        BSET    D1,0x1D(A0)                     | set EOM in IOParam flags
| check if all response packets received
E_ATP_PRIMESTATUS_OK_2:
        MOVE.B  -PORTBITS(A3),D1                | D1 = dest socket
        BTST    #0x3,(A3)                       | STS (status request) bit?
| STS request: retransmit our response
        BEQ.B   E_ATP_PRIMESTATUS_EMPTY_5       | no STS ->
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | get pending request
        BNE.B   E_ATP_PRIMESTATUS_EMPTY_5       | none ->
        MOVE    D2,A1                           | save slot index
        BSR     E_ATP_PRIMESTATUS_CONT_12       | build response ATP header
        BSR.B   E_ATP_PRIMESTATUS_CONT_22       | restore SR
        BSR     E_ATP_PRIMESTATUS_CONT_9        | retransmit response via DDP
        BSR     E_ATP_PRIMESTATUS_ERR_11        | clean up
        MOVE    A1,D2                           | restore slot index
| check if all bitmap bits cleared (all responses received)
E_ATP_PRIMESTATUS_EMPTY_5:
        TST.B   0x1C(A0)                        | bitmap empty? (all packets received)
        BNE.B   E_ATP_PRIMESTATUS_EMPTY_6       | no, still waiting ->
| all responses received: send release and complete
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | get pending request
        BNE.B   E_ATP_PRIMESTATUS_EMPTY_6       | none ->
        MOVE    0x1E(A2,D2.W),0x62(A3)          | save TID for release
        LSR     #0x1,D2                         | byte offset
        CLR.B   0x0(A2,D2.W)                    | free responder slot
        BSR.B   E_ATP_PRIMESTATUS_CONT_22       | restore SR
| send release packet if XO (exactly-once) mode
        BTST    #0x5,0x1D(A0)                   | XO flag set?
        BEQ.B   E_ATP_PRIMESTATUS_NO_10         | no ->
        MOVE.L  0x1E(A0),D3                     | D3 = dest address
        MOVE.B  #0xC0,RGNSAVE(A3)               | control = release ($C0)
        CLR     D0                              | data length = 0
        BSR     E_ATP_PRIMESTATUS_CONT_9        | send release via DDP
E_ATP_PRIMESTATUS_NO_10:
        MOVE    #0xF7,D0                        | CloseDDPSkt
        BSR     E_ATP_PRIMESTATUS_CONT_10       | close the socket
        BSR     E_ATP_PRIMESTATUS_ERR_11        | clean up
        CLR     D0                              | noErr
        BRA     E_ATP_PRIMESTATUS_ERR_6         | complete the IOParam

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_22: restore SR from saved value in ABusVars
|
E_ATP_PRIMESTATUS_CONT_22:
        MOVE.L  A1,-(SP)                        | save A1
        MOVE.L  (ABusVars).w,A1                 | A1 = ABusVars
        MOVE    0x1C(A1),SR                     | restore saved SR (IPL)
        MOVE.L  (SP)+,A1                        | restore A1
E_ATP_PRIMESTATUS_EMPTY_6:
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_OK_3
|
| E_ATP_PRIMESTATUS_OK_3: response sent successfully - check for XO retransmit
E_ATP_PRIMESTATUS_OK_3:
        MOVE.L  0x1E(A2),A2                     | A2 = ATPVars
        MOVE.L  -(A3),A1                        | A1 = user data from request
        MOVE    -(A3),D0                        | D0 = transaction ID
| check if exactly-once mode (need to save for retransmit)
        BTST    #0x5,-PORTBITS(A3)              | XO bit in control byte?
        BEQ.B   E_ATP_PRIMESTATUS_NO_12         | no, fire-and-forget ->
| XO mode: register TCB for potential retransmission
        MOVEM.L D0-D4/A1/A3,-(SP)               | save regs
        MOVE.L  D1,D3                           | D3 = source address
        MOVE.B  -0x4(A3),D1                     | D1 = source socket
        MOVE    D2,D4                           | D4 = slot offset
        BSR     E_ATP_PRIMESTATUS_CONT_6        | check if TCB already exists
        BEQ.B   E_ATP_PRIMESTATUS_OK_5          | yes, update it ->
| no existing TCB: find a free one
        TST.L   0x36(A2,D4.W)                   | responder has IOParam?
        BEQ.B   E_ATP_PRIMESTATUS_NO_11         | no ->
        LEA.L   0x66(A2),A1                     | A1 = TCB table
        MOVEQ.L #0x7,D2                         | 8 TCB entries
E_ATP_PRIMESTATUS_LOOP_7:
        TST.B   (A1)                            | TCB free?
        BEQ.B   E_ATP_PRIMESTATUS_OK_4          | yes ->
        ADDA    #0xC,A1                         | next TCB (12 bytes)
        DBF     D2,E_ATP_PRIMESTATUS_LOOP_7     | try next
| all TCBs full: can't save for retransmit
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore regs
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_OK_4
|
| found free TCB: save transaction state for retransmit
E_ATP_PRIMESTATUS_OK_4:
        MOVE.B  D1,(A1)+                        | store socket number
        CLR.B   (A1)+                           | clear idle timer
        MOVE.L  D3,(A1)+                        | store source address
        MOVE    D0,(A1)+                        | store transaction ID
        CLR.L   (A1)+                           | clear IOParam pointer
E_ATP_PRIMESTATUS_NO_11:
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore regs
| deliver request to application
E_ATP_PRIMESTATUS_NO_12:
        BRA.B   E_ATP_PRIMESTATUS_CONT_23       | -> queue request for app

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_OK_5: duplicate request - retransmit cached response
|
E_ATP_PRIMESTATUS_OK_5:
        MOVE.L  A1,A0                           | A0 = existing TCB
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore regs
        MOVE.L  D1,D3                           | D3 = requester address
        MOVE.B  -0x4(A3),D1                     | D1 = requester socket
        CLR.B   0x1(A0)                         | reset TCB timer
        MOVE.L  0x8(A0),D2                      | D2 = cached response IOParam
        BEQ.B   E_ATP_PRIMESTATUS_ERR_9         | no cached response ->
| retransmit all response packets from cache
        SWAP    D1                              | save socket in high word
        MOVE.B  -(A3),D1                        | D1.lo = bitmap from request
        MOVE.L  D2,A0                           | A0 = response IOParam
        MOVE.L  0x28(A0),A1                     | A1 = response descriptor array
        MOVE    D0,D2                           | D2 = TID
        BSR     E_ATP_PRIMESTATUS_NEXT_4        | get control block
        BNE.B   E_ATP_PRIMESTATUS_ERR_9         | failed ->
| build and send each requested response packet
        MOVE.B  #0x80,RGNSAVE(A3)               | control = response ($80)
        ST.B    0x61(A3)                        | init sequence counter to $FF
        MOVE    D2,0x62(A3)                     | store TID
        BSR     E_ATP_PRIMESTATUS_CONT_22       | restore SR
| response packet loop
E_ATP_PRIMESTATUS_SKIP_3:
        ADDQ.B  #0x1,0x61(A3)                   | increment sequence number
        MOVE.B  0x61(A3),D0                     | D0 = current sequence
        SUB.B   0x2C(A0),D0                     | past last packet?
        BGE     E_ATP_PRIMESTATUS_ERR_11        | yes, done ->
        ADDQ.B  #0x1,D0                         | at last packet?
        BNE.B   E_ATP_PRIMESTATUS_NO_13         | no ->
        MOVE.B  0x1D(A0),D0                     | merge EOM flag for last packet
        OR.B    D0,RGNSAVE(A3)                  | merge EOM into response flags
E_ATP_PRIMESTATUS_NO_13:
| get data for this response packet from descriptor array
        MOVE    (A1)+,D0                        | data length
        MOVE.L  (A1)+,D2                        | data pointer
        ADDQ.W  #0x2,A1                         | skip padding
        MOVE.L  (A1)+,POLYSAVE(A3)              | user data longword
        LSR     #0x1,D1                         | shift bitmap: need this packet?
        BCC.B   E_ATP_PRIMESTATUS_SKIP_3        | no, skip ->
        TST     -0x6(A1)                        | data length zero?
        BEQ.B   E_ATP_PRIMESTATUS_SKIP_3        | yes, skip ->
| send this response packet
        SWAP    D1                              | save bitmap
        BSR     E_ATP_PRIMESTATUS_CONT_9        | send via WriteDDP
        SWAP    D1                              | restore bitmap
        BRA.B   E_ATP_PRIMESTATUS_SKIP_3        | next packet

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_ERR_9
|
| no cached response
E_ATP_PRIMESTATUS_ERR_9:
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_23: deliver incoming ATP request to application
| Dequeues the pending GetRequest IOParam and fills it with request data
|
E_ATP_PRIMESTATUS_CONT_23:
        MOVE.L  0x36(A2,D2.W),-(SP)             | get pending GetRequest IOParam
        MOVE.L  (SP)+,A0                        | A0 = GetRequest IOParam (or nil)
        BEQ.B   E_ATP_PRIMESTATUS_ERR_9         | no pending request ->
| fill in request parameters
        MOVE.L  A1,0x12(A0)                     | store user data from request
        MOVE.B  -(A3),0x2C(A0)                  | store bitmap
        MOVE    D0,0x2E(A0)                     | store transaction ID
        LEA.L   0x1D(A0),A1                     | A1 = control flags area
        MOVE.B  -(A3),(A1)+                     | store control byte
        MOVE.L  D1,(A1)                         | store source address
| verify source address matches expected (for security)
        LEA.L   0x4E(A2,D2.W),A3                | A3 = expected address in slot
        CMPM    (A1)+,(A3)+                     | compare network number
        BEQ.B   E_ATP_PRIMESTATUS_FOUND_7       | match ->
        TST     -PORTBITS(A3)                   | wildcard (0)?
        BNE.B   E_ATP_PRIMESTATUS_ERR_9         | no, reject ->
E_ATP_PRIMESTATUS_FOUND_7:
        MOVEQ.L #0x2,D0                         | compare node + socket (2 bytes)
E_ATP_PRIMESTATUS_OK_6:
        CMPM.B  (A1)+,(A3)+                     | compare byte
        BEQ.B   E_ATP_PRIMESTATUS_FOUND_8       | match ->
        TST.B   -0x1(A3)                        | wildcard (0)?
        BNE.B   E_ATP_PRIMESTATUS_ERR_9         | no, reject ->
E_ATP_PRIMESTATUS_FOUND_8:
        SUBQ.W  #0x1,D0                         | more bytes?
        BNE.B   E_ATP_PRIMESTATUS_OK_6          | yes ->
| address verified: dequeue IOParam and complete
        SUB     D3,(A1)                         | adjust data length
        MOVE.L  (A0),0x36(A2,D2.W)              | dequeue: link next IOParam
        BRA     E_ATP_PRIMESTATUS_ERR_6         | complete the IOParam

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_CONT_24: validate DDP send result and extract source address
| Returns NE on error, D1 = source address on success
|
E_ATP_PRIMESTATUS_CONT_24:
        BNE.B   E_ATP_PRIMESTATUS_ERR_10        | DDP error ->
        MOVEQ.L #0x0,D1                         | clear address
        LEA.L   0x2(A2),A0                      | A0 = ABusVars network info
        MOVE.B  0x7(A2),D0                      | D0 = our node ID
        MOVE.B  (A0)+,D1                        | D1 = our network number high
        SUBQ.B  #0x1,(A0)+                      | decrement hop count
        BEQ.B   E_ATP_PRIMESTATUS_EMPTY_7       | zero hops: local delivery ->
| verify DDP checksum if present
        MOVEM.L D2-D4,-(SP)                     | save regs
        MOVE    (A0)+,D1                        | D1 = packet network number
        MOVE    (A0)+,D4                        | D4 = DDP checksum from packet
        BEQ.B   E_ATP_PRIMESTATUS_NO_16         | no checksum (0) ->
| compute rolling checksum over DDP header (8 bytes)
        MOVEQ.L #0x8,D2                         | 8 header bytes
        CLR     D3                              | clear accumulator
        BSR.B   E_ATP_PRIMESTATUS_OK_7          | checksum header
        ADDQ.W  #0x3,D3                         | add 3 (DDP magic)
        ROL     #0x1,D3                         | rotate
| checksum data portion (8 bytes of ATP header)
        MOVEQ.L #0x8,D2                         | 8 ATP header bytes
        BSR.B   E_ATP_PRIMESTATUS_OK_7          | checksum data
| checksum any remaining payload
        ANDI    #0x3FF,D1                       | D1 = DDP length field
        SUBI    #0x15,D1                        | - header overhead (21 bytes)
        BEQ.B   E_ATP_PRIMESTATUS_NO_14         | no payload ->
        MOVE.L  A3,A0                           | A0 = payload start
        SUBA    D1,A0                           | back up to data
        MOVE    D1,D2                           | D2 = payload length
        BSR.B   E_ATP_PRIMESTATUS_OK_7          | checksum payload
E_ATP_PRIMESTATUS_NO_14:
        TST     D3                              | checksum result zero?
        BNE.B   E_ATP_PRIMESTATUS_NO_15         | no ->
        SUBQ.W  #0x1,D3                         | zero maps to $FFFF
E_ATP_PRIMESTATUS_NO_15:
        CMP     D4,D3                           | matches packet checksum?
E_ATP_PRIMESTATUS_NO_16:
        MOVEM.L (SP)+,D2-D4                     | restore regs
        BNE.B   E_ATP_PRIMESTATUS_ERR_10        | checksum mismatch ->
| checksum ok: extract source address
        MOVE.L  0xA(A2),D1                      | our network+node
        MOVE.B  0xD(A2),D1                      | source node
        MOVE.B  0xF(A2),D0                      | source socket
E_ATP_PRIMESTATUS_EMPTY_7:
        LSL     #0x8,D1                         | shift for socket byte
        MOVE.B  D0,D1                           | D1 = full source address
        CLR     D0                              | noErr
E_ATP_PRIMESTATUS_ERR_10:
        RTS                                     | unreachable

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_OK_7: compute rolling checksum over D2 bytes at (A0)+
| Accumulates into D3 with rotate-left
|
E_ATP_PRIMESTATUS_OK_7:
        MOVE.B  (A0)+,D0                        | get next byte
        ADD     D0,D3                           | add to accumulator
        ROL     #0x1,D3                         | rotate left
        SUBQ.W  #0x1,D2                         | more bytes?
        BNE.B   E_ATP_PRIMESTATUS_OK_7          | yes ->
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_NEXT_4: get ATP control block for current operation
| Returns A3 = control block, D0 = error if busy
|
| Called by: E_ATP_CLOSE_CONT, E_ATP_CLOSE_LOOP, CLOSEATPSKT, E_ATP_PRIMESTATUS_CONT_4, SENDREQUEST (and 6 more)
E_ATP_PRIMESTATUS_NEXT_4:
        MOVE.L  (ABusVars_dce).w,A3             | A3 = .ATP DCE
        MOVE    VISRGN(A3),D0                   | D0 = DCE queue flags
        LEA.L   0xDA(A2),A3                     | A3 = ATP control block area
        TST     VISRGN(A3)                      | busy?
        BEQ.B   E_ATP_PRIMESTATUS_NO_17         | no ->
| try second control block
        LEA.L   0x142(A2),A3                    | try block 2
        TST     VISRGN(A3)                      | busy?
        BEQ.B   E_ATP_PRIMESTATUS_NO_17         | no ->
| try third control block
        LEA.L   0x1AA(A2),A3                    | try block 3
        TST     VISRGN(A3)                      | busy?
        BEQ.B   E_ATP_PRIMESTATUS_NO_17         | no ->
        MOVE    #-0x450,D0                      | noMoreCBs: all blocks busy
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_NO_17: claim the control block (mark as busy)
|
E_ATP_PRIMESTATUS_NO_17:
        MOVE    D0,VISRGN(A3)                   | mark block as in-use (store DCE flags)
        CLR     D0                              | noErr
        RTS                                     | return

| ----------------------------------------------------------
|
| E_ATP_PRIMESTATUS_ERR_11: release the current control block
|
| Called by: E_ATP_CLOSE_LOOP, CLOSEATPSKT, E_ATP_PRIMESTATUS_SKIP, SENDREQUEST, E_ATP_PRIMESTATUS_LOOP_3 (and 5 more)
E_ATP_PRIMESTATUS_ERR_11:
        CLR     VISRGN(A3)                      | mark block as free
        RTS                                     | return

| end of resource : 'DRVR' 10 '.ATP'

| resource header
  .long 0xC0000FD6                              | Length
  .long 0x00000064                              | ?

