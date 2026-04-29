| DRVR 9 - .MPP (AppleTalk, Macintosh Packet Protocol) driver
| resource : 'DRVR' 9 '.MPP'
|
| Implements DDP (Datagram Delivery Protocol) and LAP (Link Access Protocol)
| over the SCC serial port using LocalTalk framing.
|
| Provides:
| - DDP socket management (OpenSkt, CloseSkt, WriteDDP)
| - NBP name registration/lookup (Register, Lookup, Confirm, Remove)
| - LAP protocol handler installation
| - SCC interrupt-driven packet receive/transmit
|
| Data structures:
| ABusVars (low-memory global): AppleTalk state, node ID, socket table
| MPPParamBlock: csCode dispatch for all protocol operations
|
Driver_MPP:
  .short 0x5C00                                 | drvrFlags (needsLock|needsTime|needsGoodbye)
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x07FC                                 | drvrOpen offset
  .short 0x0290                                 | drvrPrime offset
  .short 0x001A                                 | drvrCtl offset
  .short 0x0284                                 | drvrStatus offset
  .short 0x0774                                 | drvrClose offset
  .byte 0x04                                    | drvrName length

| Name
  .ascii ".MPP"                                 | drvrName: driver name string

| end of Name
  .byte 0x20,0x28,0x13                          | padding to word-align entry point

| .MPP Control: dispatch AppleTalk control calls
| csCodes: 248=WriteDDP, 249=OpenSkt, 250=CloseSkt, 251=WriteLAP,
| 252=SetSelfSend, 253=AttachPH, 254=DetachPH, 255=GetNodeAddr,
| 256=Register, 257=Lookup, 258=Confirm, 259=Remove, 260=KillNBP
E_MPP_Control:
        MOVE.L  (AtalkHk1).w,D3                 | AppleTalk hook installed?
        BLE.B   E_MPP_CONTROL_NO                | no ->
        MOVE.L  D3,A2                           | A2 = hook proc
        JSR     (A2)                            | call hook before dispatch
E_MPP_CONTROL_NO:
        MOVE.L  (ABusVars).w,A2                 | A2 = AppleTalk bus variables
        MOVE.L  A2,D0                           | initialized?
        BNE.B   E_MPP_CONTROL_OK                | yes ->
        MOVEQ.L #-0x11,D0                       | ddpLenErr: not initialized
        BRA     E_MPP_STATUS_ERR                | -> error exit
| dispatch on csCode
E_MPP_CONTROL_OK:
        MOVE    0x1A(A0),D3                     | D3 = csCode
        BMI.B   E_MPP_CONTROL_CONT              | negative: close/reopen ->
| csCode 1 = KillIO (no-op for MPP)
        SUBQ.W  #0x1,D3                         | csCode 1?
        BNE.B   E_MPP_CONTROL_NO_2              | no ->
        RTS                                     | KillIO: just return
| validate csCode range (242-255 = MPP operations)
E_MPP_CONTROL_NO_2:
        MOVEQ.L #-0x11,D0                       | assume paramErr
        SUBI    #0xF1,D3                        | D3 -= 242 (base MPP csCode - 1)
        BLT     E_MPP_STATUS_ERR                | < 242: invalid ->
        CMPI    #0xD,D3                         | > 255?
        BGT     E_MPP_STATUS_ERR                | yes, invalid ->
| set up common params and dispatch
        MOVE.B  0x1C(A0),D1                     | D1 = socket number from csParam
        MOVE.L  0x1E(A0),A1                     | A1 = data pointer from csParam
        CMPI    #0x7,D3                         | DDP operation (0-7)?
        BGT.B   E_MPP_CONTROL_NO_3              | no, NBP operation ->
| dispatch DDP/LAP operations via jump table
        LEA.L   E_MPP_CONTROL_DISPATCH_TBL(PC),A3 | DDP dispatch table
        ADDA    D3,A3                           | index by csCode
        ADDA    D3,A3                           | word offset
        MOVE    (A3),A3                         | get relative offset
        PEA.L   Driver_MPP(PC)                  | base address
        ADDA.L  (SP)+,A3                        | absolute handler address
        JMP     (A3)                            | dispatch

| DDP dispatch table (offsets from Driver_MPP):
| 0=WriteLAP, 1=AttachPH, 2=DetachPH, 3=WriteDDP,
| 4=CloseSkt, 5=OpenSkt, 6=GetNodeAddr, 7=SetSelfSend
E_MPP_CONTROL_DISPATCH_TBL:
  .byte  0x00,0x96,0x02,0x72,0x02,0x5E          | WriteLAP=+150, AttachPH=+626, DetachPH=+606
  .byte 0x02,0x2E,0x01,0x1E,0x01,0x00           | WriteDDP=+558, CloseSkt=+286, OpenSkt=+256
  .byte 0x00,0xB6,0x00,0xA0                     | GetNodeAddr=+182, SetSelfSend=+160
| negative csCode: call close/reopen hooks
E_MPP_CONTROL_CONT:
        MOVE.L  0x8E(A2),D1                     | close hook installed?
        BPL.B   E_MPP_CONTROL_NO_3              | no ->
        MOVE.L  D1,A3                           | A3 = close hook routine address
        JSR     PORTBITS(A3)                    | call close hook
| NBP operations: dispatch via NBP handler
E_MPP_CONTROL_NO_3:
        MOVE.L  0x8A(A2),D2                     | NBP handler installed?
        BPL.B   E_MPP_CONTROL_NO_4              | no ->
        MOVE.L  D2,A3                           | A3 = NBP handler routine address
        JMP     (A3)                            | dispatch to NBP handler

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_2
|
E_MPP_CONTROL_CONT_2:
        MOVE.L  0x8E(A2),D2                     | close/reopen hook address
        BPL.B   E_MPP_CONTROL_NO_4              | not installed ->
        MOVE.L  D2,A3                           | A3 = hook procedure
        JMP     (A3)                            | dispatch to close/reopen hook

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_3
|
E_MPP_CONTROL_CONT_3:
        CLR     D0                              | noErr: operation succeeded
E_MPP_CONTROL_NO_4:
        BRA     E_MPP_STATUS_CONT               | -> IODone completion

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_4
|
E_MPP_CONTROL_CONT_4:
        LEA.L   E_MPP_OPEN_DISPATCH_TBL(PC),A3  | A3 = NBP dispatch table
        MOVE.L  A3,0x8A(A2)                     | install NBP handler in ABusVars
        BSET    #0x7,0x8A(A2)                   | set high bit = handler valid
        JMP     (A3)                            | jump into NBP dispatcher

| ----------------------------------------------------------
|
| OPENSKT
|
| OpenSkt (csCode 249): open a DDP socket
| D1 = requested socket number (0 = dynamic assignment)
OPENSKT:
        BSR.B   RETURNS                         | allocate DDP socket
        MOVE.B  D1,0x1C(A0)                     | return assigned socket in csParam
        BRA.B   E_MPP_CONTROL_DONE              | -> complete

| ----------------------------------------------------------
|
| RETURNS: allocate a DDP socket
| D1 = requested socket (0=dynamic, 1-254=specific)
| Returns: D1 = assigned socket, D0 = error if failed
|
RETURNS:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr: assume socket error
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | raise IPL (critical section)
        TST.B   D1                              | dynamic assignment?
        BEQ.B   E_MPP_CONTROL_OK_2              | yes, find free ->
        BMI.B   E_MPP_CONTROL_CONT_5            | invalid (negative) ->
        BSR.B   RETURNS_2                       | check if specific socket available
        BEQ.B   E_MPP_CONTROL_CONT_5            | already in use ->
| find a free socket slot (scan 14 slots)
E_MPP_CONTROL_OK_2:
        MOVEQ.L #0xD,D2                         | 14 socket slots (0-13)
E_MPP_CONTROL_LOOP:
        TST.B   0x36(A2,D2.W)                   | slot available?
        DBEQ    D2,E_MPP_CONTROL_LOOP           | try next
        BNE.B   E_MPP_CONTROL_CONT_5            | all in use ->
        TST.B   D1                              | specific socket requested?
        BNE.B   E_MPP_CONTROL_OK_3              | yes, use it ->
        BSR     RETURNS_5                       | generate pseudo-random number
        ANDI.B  #0xF0,D0                        | keep high nibble as randomizer
        OR.B    D2,D0                           | combine with slot index
        BSET    #0x7,D0                         | set bit 7 (dynamic socket range)
        MOVE.B  D0,D1                           | D1 = dynamically assigned socket
E_MPP_CONTROL_OK_3:
        MOVE.B  D1,0x36(A2,D2.W)                | store socket number in table slot
        LSL     #0x2,D2                         | D2 *= 4 (long word index)
        MOVE.L  A1,0x44(A2,D2.W)                | store socket listener in handler table
        CLR     D0                              | noErr: socket opened
E_MPP_CONTROL_CONT_5:
        MOVE    (SP)+,SR                        | restore saved interrupt state
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_6: CloseSkt - close a DDP socket by number
|
E_MPP_CONTROL_CONT_6:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr: assume socket error
        TST.B   D1                              | socket number specified?
        BEQ.B   E_MPP_CONTROL_DONE              | no, invalid ->
        BSR.B   RETURNS_2                       | find socket in table
        BNE.B   E_MPP_CONTROL_DONE              | not found ->
        CLR.B   0x36(A2,D2.W)                   | clear socket from table (free slot)
        CLR     D0                              | noErr: socket closed
E_MPP_CONTROL_DONE:
        BRA.B   E_MPP_CONTROL_NO_4              | -> IODone completion

| ----------------------------------------------------------
|
| RETURNS_2: find socket D1 in socket table
| Returns: D2 = slot index, Z flag set if found
|
RETURNS_2:
        MOVEQ.L #0xD,D2                         | scan 14 socket slots (13..0)
E_MPP_CONTROL_LOOP_2:
        CMP.B   0x36(A2,D2.W),D1                | slot matches socket number?
        DBEQ    D2,E_MPP_CONTROL_LOOP_2         | no, try next slot
        RTS                                     | Z=1 if found, D2=slot index

| ----------------------------------------------------------
|
| CLOSESKT
|
| CloseSkt (csCode 250): close a DDP socket
CLOSESKT:
        MOVE.B  0x1D(A0),D3                     | D3 = socket listener flag
        BSR.B   E_MPP_CONTROL_CONT_7            | close the socket
        BRA.B   E_MPP_CONTROL_DONE              | -> IODone

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_7: close DDP socket D1
|
E_MPP_CONTROL_CONT_7:
        BRA.B   E_MPP_CONTROL_CONT_9            | -> close implementation

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_8: SetSelfSend (csCode 252) - configure self-send mode
| Reuses OpenSkt to register a loopback socket
|
E_MPP_CONTROL_CONT_8:
        BRA.B   RETURNS                         | reuse OpenSkt socket allocator

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_9
|
| E_MPP_CONTROL_CONT_9: close DDP socket - deregister and free slot
E_MPP_CONTROL_CONT_9:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr
        TST.B   D1                              | socket number valid?
        BEQ.B   E_MPP_CONTROL_ERR               | zero: invalid ->
        BSR.B   RETURNS_2                       | find socket in table -> A1
        BNE.B   E_MPP_CONTROL_ERR               | not found ->
| build DDP close packet
        MOVE.L  A1,-(SP)                        | save socket table entry
        ADDQ.W  #0x2,A1                         | skip socket number
        MOVE.L  (A1)+,A3                        | A3 = socket listener record
        ADDQ.W  #0x7,A3                         | point to DDP header area
        MOVE.B  D1,0x7(A3)                      | set source socket in header
        MOVE    (A3),D0                         | destination network number
        BEQ.B   E_MPP_CONTROL_EMPTY_3           | zero: no close needed ->
        CMP     0x1A(A2),D0                     | same network as ours?
        BEQ.B   E_MPP_CONTROL_EMPTY_3           | yes ->
| send close notification to remote network
        MOVE    0x1A(A2),PORTBITS(A3)           | set source network number
        MOVE.B  (A2),0x5(A3)                    | set source node ID
        MOVE.B  0x4(A3),D1                      | dest socket from header
        MOVE.L  A3,A0                           | A0 = packet data
        CLR     -(A3)                           | clear packet header
        TST.B   D3                              | listener flag?
        BEQ.B   E_MPP_CONTROL_EMPTY_2           | no listener ->
        MOVEQ.L #0x9,D0                         | DDP type 9 = close notification
        CLR     D3                              | clear flag
        BSR.B   E_MPP_CONTROL_CONT_10           | send close notification
E_MPP_CONTROL_NEXT:
        MOVE    (A1)+,D0                        | next data chunk length
        BEQ.B   E_MPP_CONTROL_EMPTY             | zero = end of data list ->
        MOVE.L  (A1)+,A0                        | A0 = chunk data pointer
        BSR.B   E_MPP_CONTROL_CONT_10           | checksum this chunk
        BRA.B   E_MPP_CONTROL_NEXT              | continue with next chunk

| ----------------------------------------------------------
|
| E_MPP_CONTROL_EMPTY
|
E_MPP_CONTROL_EMPTY:
        MOVE    D3,(A3)                         | store running checksum
        BNE.B   E_MPP_CONTROL_EMPTY_2           | non-zero ->
        SUBQ.W  #0x1,(A3)                       | force checksum to -1 (0 = no cksum)
E_MPP_CONTROL_EMPTY_2:
        MOVEQ.L #0x2,D3                         | DDP type 2 = extended header
        MOVEQ.L #0x10,D0                        | 16 bytes in extended DDP header
        MOVE.B  0x19(A2),D2                     | D2 = bridge node (router)
        BNE.B   E_MPP_CONTROL_NO_5              | have a router ->
        MOVE.B  D1,D2                           | use dest node as next hop
        TST     0x1A(A2)                        | our network number known?
        BEQ.B   E_MPP_CONTROL_NO_5              | no, proceed anyway ->
        MOVEQ.L #-0x5D,D0                       | ddpBadSkt: can't route without bridge
        ADDQ.W  #0x4,SP                         | discard return address
        RTS                                     | return error to caller

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_10: DDP checksum - rotate-add D0 bytes from (A0) into D3
|
E_MPP_CONTROL_CONT_10:
        MOVE.B  (A0)+,D2                        | fetch next data byte
        ADD     D2,D3                           | add to running checksum
        ROL     #0x1,D3                         | rotate left (CRC-like mixing)
        SUBQ.W  #0x1,D0                         | decrement byte count
        BNE.B   E_MPP_CONTROL_CONT_10           | more bytes ->
E_MPP_CONTROL_ERR:
        RTS                                     | return with checksum in D3

| ----------------------------------------------------------
|
| E_MPP_CONTROL_EMPTY_3: build short-form DDP header (same network, no routing)
|
E_MPP_CONTROL_EMPTY_3:
        MOVE.L  A3,A0                           | A0 = DDP header start
        ADDQ.W  #0x8,A0                         | point past short header
        MOVE.B  (A0),(A3)                       | copy DDP type byte
        MOVE    -(A0),-(A3)                     | copy dest/src socket pair
        SUBQ.W  #0x2,A0                         | back up to dest node
        MOVE.B  (A0),D2                         | D2 = destination node
        MOVEQ.L #0x1,D3                         | DDP type 1 = short header
        MOVEQ.L #0x8,D0                         | 8 bytes in short DDP header
E_MPP_CONTROL_NO_5:
        MOVE.L  (SP)+,A1                        | restore socket table entry pointer
        MOVE    D0,(A1)                         | store header length in data list
        CLR     D1                              | D1 = total packet length accumulator
        MOVE.L  A1,A0                           | A0 = scan pointer for data list
E_MPP_CONTROL_NEXT_2:
        TST     (A0)                            | end of data list?
        BEQ.B   E_MPP_CONTROL_OK_4              | yes ->
        BMI.B   E_MPP_CONTROL_ERR_2             | error marker ->
        ADD     (A0),D1                         | accumulate chunk length
        ADDQ.W  #0x6,A0                         | advance past length+pointer entry
        BRA.B   E_MPP_CONTROL_NEXT_2            | scan next chunk

| ----------------------------------------------------------
|
| E_MPP_CONTROL_OK_4: finalize DDP packet length and transmit
|
E_MPP_CONTROL_OK_4:
        MOVE    D1,-(A3)                        | store total length in header
        SUBQ.W  #0x3,(A3)                       | subtract 3 (LAP header not counted)
        SUB     D0,D1                           | D1 = data length without header
        CMPI    #0x24A,D1                       | exceeds max DDP data (586 bytes)?
        BHI.B   E_MPP_CONTROL_ERR_2             | yes, packet too large ->
        MOVE.B  D3,-(A3)                        | store LAP type byte in frame
        SUBQ.W  #0x2,A3                         | back up past LAP dest/src
        MOVE.B  D2,(A3)                         | store destination node ID
        BRA     E_MPP_PRIME_CONT                | -> transmit LAP frame

| ----------------------------------------------------------
|
| E_MPP_CONTROL_ERR_2: DDP packet too large error
|
E_MPP_CONTROL_ERR_2:
        MOVEQ.L #-0x5C,D0                       | ddpLenErr: packet exceeds max size
        BRA.B   E_MPP_CONTROL_ERR               | -> return error

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_11: receive handler for extended DDP packets (type 2)
| Reads extended DDP header (11 additional bytes after LAP)
|
E_MPP_CONTROL_CONT_11:
        MOVEQ.L #0xB,D3                         | 11 bytes in extended DDP header body
        MOVE    0x1A(A2),D2                     | D2 = our network number
        JSR     (A4)                            | read header bytes from SCC
        BNE.B   E_MPP_CONTROL_ERR               | receive error ->
        CMP     0x8(A2),D2                      | dest network matches ours?
        BEQ.B   E_MPP_CONTROL_OK_5              | yes, deliver to socket ->
        BRA.B   E_MPP_CONTROL_NO_6              | wrong network, discard ->

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_12: receive handler for short DDP packets (type 1)
| Reads 3 bytes: length, dest socket, src socket
|
E_MPP_CONTROL_CONT_12:
        MOVEQ.L #0x3,D3                         | 3 bytes in short DDP header body
        JSR     (A4)                            | read header bytes from SCC
        BNE.B   E_MPP_CONTROL_ERR               | receive error ->
| E_MPP_CONTROL_OK_5: dispatch received DDP packet to socket listener
E_MPP_CONTROL_OK_5:
        MOVEQ.L #0xD,D2                         | scan 14 socket table slots
        MOVE.B  -0x3(A3),D0                     | D0 = destination socket number
        BEQ.B   E_MPP_CONTROL_NO_6              | socket 0 = invalid ->
E_MPP_CONTROL_LOOP_3:
        CMP.B   0x36(A2,D2.W),D0                | match socket in table?
        DBEQ    D2,E_MPP_CONTROL_LOOP_3         | no, try next slot
        BNE.B   E_MPP_CONTROL_NO_6              | socket not registered ->
        LSL     #0x2,D2                         | D2 *= 4 (long word index)
        MOVE.L  0x44(A2,D2.W),A5                | A5 = socket listener handler
        JMP     (A5)                            | dispatch to socket listener

| ----------------------------------------------------------
|
| E_MPP_CONTROL_NO_6: discard packet - flush remaining SCC data
|
E_MPP_CONTROL_NO_6:
        JMP     0x2(A4)                         | jump to SCC flush/abort receive

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_13: receive AARP (AppleTalk Address Resolution Protocol) packet
| Validates AARP hardware type, extracts network number
|
E_MPP_CONTROL_CONT_13:
        SUBQ.B  #0x1,-(A3)                      | decrement remaining LAP bytes
        BNE.B   E_MPP_CONTROL_NO_6              | not AARP type -> discard
        MOVEQ.L #0x4,D3                         | read 4 AARP header bytes
        JSR     0x2(A4)                         | receive from SCC
        BNE.B   E_MPP_CONTROL_ERR_3             | error ->
        MOVE.B  -(A3),D2                        | D2 = sender's node ID
        SUBQ.B  #0x8,-(A3)                      | check hardware type (8 = Ethernet)
        BNE.B   E_MPP_CONTROL_ERR_3             | wrong hw type -> ignore
        MOVE.B  D2,0x19(A2)                     | store bridge/router node ID
        ST.B    0xB8(A2)                        | set AARP response received flag
        MOVE    -(A3),0x1A(A2)                  | store our network number from AARP
E_MPP_CONTROL_ERR_3:
        RTS                                     | return to interrupt handler

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_14: AttachPH - install a LAP protocol handler
| D1 = LAP type, A1 = handler address
|
E_MPP_CONTROL_CONT_14:
        MOVEQ.L #-0x5E,D0                       | lapProtErr: assume protocol error
        TST.B   D1                              | LAP type valid (> 0)?
        BLE.B   E_MPP_CONTROL_ERR_4             | no, invalid ->
        BSR.B   RETURNS_3                       | check if type already registered
        BEQ.B   E_MPP_CONTROL_ERR_4             | already attached -> error
        MOVEQ.L #0x3,D2                         | scan 4 LAP handler slots (3..0)
E_MPP_CONTROL_LOOP_4:
        LEA.L   0x22(A2,D2.W),A3                | A3 -> LAP type slot
        TST.B   (A3)                            | slot empty ($FF = empty)?
        DBMI    D2,E_MPP_CONTROL_LOOP_4         | not empty, try next
        BPL.B   E_MPP_CONTROL_ERR_4             | all slots full -> error
        LSL     #0x2,D2                         | D2 *= 4 (handler table index)
        MOVE.L  A1,0x26(A2,D2.W)                | install handler address
        MOVE.B  D1,(A3)                         | register LAP type in slot
E_MPP_CONTROL_EXIT:
        CLR     D0                              | noErr: handler attached
E_MPP_CONTROL_ERR_4:
        BRA.B   E_MPP_STATUS_CONT               | -> IODone completion

| ----------------------------------------------------------
|
| RETURNS_3: find LAP protocol handler for type D1
| Returns: Z=1 if found, D2 = slot index
|
RETURNS_3:
        MOVEQ.L #0x3,D2                         | scan 4 LAP handler slots (3..0)
E_MPP_CONTROL_LOOP_5:
        CMP.B   0x22(A2,D2.W),D1                | slot matches LAP type?
        DBEQ    D2,E_MPP_CONTROL_LOOP_5         | no, try next
        RTS                                     | Z=1 if found

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_15: DetachPH - remove a LAP protocol handler
| D1 = LAP type to detach
|
E_MPP_CONTROL_CONT_15:
        MOVEQ.L #-0x5E,D0                       | lapProtErr: assume not found
        MOVEQ.L #0x3,D2                         | scan 4 LAP handler slots
E_MPP_CONTROL_LOOP_6:
        CMP.B   0x22(A2,D2.W),D1                | slot matches LAP type?
        DBEQ    D2,E_MPP_CONTROL_LOOP_6         | no, try next
        BNE.B   E_MPP_CONTROL_ERR_4             | not found -> error
        ST.B    0x22(A2,D2.W)                   | mark slot as empty ($FF)
        BRA.B   E_MPP_CONTROL_EXIT              | -> return noErr

| ----------------------------------------------------------
|
| E_MPP_CONTROL_CONT_16: WriteLAP - send a raw LAP frame
| A1+2 = pointer to LAP write data structure
|
E_MPP_CONTROL_CONT_16:
        MOVE.L  0x2(A1),A0                      | A0 = LAP write data pointer
        MOVEQ.L #-0x5E,D0                       | lapProtErr: assume protocol error
        TST.B   0x2(A0)                         | LAP type valid (> 0)?
        BLE.B   E_MPP_CONTROL_ERR_4             | no -> error
        MOVE.B  (A0),D2                         | D2 = destination node for LAP frame
        BSR.B   E_MPP_PRIME_CONT                | transmit LAP frame
        BRA.B   E_MPP_STATUS_CONT               | -> IODone completion

| ----------------------------------------------------------
|
| E_MPP_Status
|
| .MPP Status: not implemented (returns statusErr)
E_MPP_Status:
        MOVEQ.L #-0x12,D0                       | statusErr (-18)
E_MPP_STATUS_CONT:
        MOVE.L  (ABusVars_dce).w,A1             | DCE for IODone
E_MPP_STATUS_ERR:
        MOVE.L  (JIODone).w,-(SP)               | JIODone vector
        RTS                                     | -> IODone

| ----------------------------------------------------------
|
| .MPP Prime: not implemented (clear busy, return)
|
E_MPP_Prime:
        BCLR    #0x7,0x5(A1)                    | clear DCE busy flag
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT
|
| E_MPP_PRIME_CONT: set up LocalTalk transmit - begin LAP frame assembly
| A1 = data pointer, D2 = LAP type byte
E_MPP_PRIME_CONT:
        CLR.B   0xB0(A2)                        | clear transmit state
        MOVE.L  A1,0xA2(A2)                     | save data pointer
| E_MPP_PRIME_CONT_2: common transmit entry - set up collision backoff
E_MPP_PRIME_CONT_2:
        MOVE.L  (SP)+,0xA6(A2)                  | save return address for completion
        MOVE.L  (ATalkHk2).w,D3                 | transmit hook installed?
        BLE.B   E_MPP_PRIME_NO                  | no ->
        MOVE.L  D3,A3                           | A3 = transmit hook routine address
        JSR     (A3)                            | call transmit hook
E_MPP_PRIME_NO:
        MOVE.B  D2,0xAC(A2)                     | save LAP type
| collision backoff: CSMA/CA with random exponential backoff
        LEA.L   0xB3(A2),A3                     | A3 = collision state
        MOVE.B  (A3)+,D3                        | D3 = backoff counter
        MOVE.B  (A3),D2                         | D2 = collision history byte
        ADD.B   D2,(A3)+                        | shift collision history
        BSR.B   E_MPP_PRIME_CONT_3              | count collisions in history
        BLE.B   E_MPP_PRIME_CONT_4              | few collisions ->
| many collisions: increase backoff interval
        ADD.B   D3,D3                           | double backoff
        ADDQ.B  #0x1,D3                         | + 1
        ANDI    #0xF,D3                         | clamp to 15 slots
        CLR.B   -0x1(A3)                        | clear collision history
        BRA.B   E_MPP_PRIME_CONT_5              | -> start backoff timer

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_3: count set bits in D2 (collision frequency estimator)
| Returns D0 = bit count - 2 (positive = many collisions)
|
E_MPP_PRIME_CONT_3:
        MOVEQ.L #0x0,D0                         | D0 = bit counter
        MOVEQ.L #0x7,D1                         | 8 bits to test
E_MPP_PRIME_LOOP:
        BTst    D1,D2                           | bit set?
        BEQ.B   E_MPP_PRIME_NO_2                | no ->
        ADDQ.W  #0x1,D0                         | count it
E_MPP_PRIME_NO_2:
        DBF     D1,E_MPP_PRIME_LOOP             | loop through all LAP entries
        SUBQ.B  #0x2,D0                         | threshold: > 2 = heavy traffic
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_4: few recent collisions - try reducing backoff
|
E_MPP_PRIME_CONT_4:
        MOVE.B  (A3),D2                         | D2 = recent collision history
        BSR.B   E_MPP_PRIME_CONT_3              | count collisions
        BGE.B   E_MPP_PRIME_CONT_5              | still moderate traffic ->
        LSR.B   #0x1,D3                         | halve backoff (channel is quiet)
        ST.B    (A3)                            | reset collision history
| E_MPP_PRIME_CONT_5: begin CSMA/CA transmit attempt with computed backoff
E_MPP_PRIME_CONT_5:
        MOVE.B  (A3),D2                         | D2 = collision history byte
        ADD.B   D2,(A3)+                        | shift history, advance pointer
        MOVEQ.L #0x20,D0                        | 32 = max inter-frame delay slots
        MOVE.B  D0,(A3)+                        | store retry limit (32 attempts)
        MOVE.B  D0,(A3)                         | store second retry limit
        SUBQ.W  #0x5,A3                         | rewind to backoff counter fields
        MOVE.B  D3,(A3)+                        | store backoff count (primary)
        MOVE.B  D3,(A3)+                        | store backoff count (secondary)
        MOVEM.L (SCCRd).w,A0-A1                 | A0=SCC read base, A1=SCC write base
| E_MPP_PRIME_LOOP_2: CSMA/CA transmit loop - sense carrier, backoff, transmit
E_MPP_PRIME_LOOP_2:
        MOVE    SR,-(SP)                        | save SR for restore on collision
E_MPP_PRIME_RETRY:
        MOVE    D0,D3                           | D3 = remaining inter-frame slots
        BTST    #0x4,(A0)                       | SCC RR0 bit 4: DCD (carrier detect)
        BEQ.B   E_MPP_PRIME_CONT_7              | carrier present -> defer
        BSR     RETURNS_5                       | generate random backoff delay
        AND.B   0xB2(A2),D0                     | mask with backoff window
        ANDI    #0xF,D0                         | clamp to 0-15 slot times
        MOVE    D0,D3                           | D3 = random backoff count
        BEQ.B   E_MPP_PRIME_EMPTY               | zero wait -> go ahead
E_MPP_PRIME_CONT_6:
        BSR.B   RETURNS_4                       | wait one slot time, check carrier
        BEQ.B   E_MPP_PRIME_CONT_7              | carrier appeared -> defer
        SUBQ.W  #0x1,D0                         | decrement wait counter
        BNE.B   E_MPP_PRIME_CONT_6              | more slots to wait ->
| E_MPP_PRIME_EMPTY: channel idle - begin transmit sequence
E_MPP_PRIME_EMPTY:
        MOVE    #0x2600,SR                      | raise IPL (no interrupts during TX)
        MOVE.B  #0xE,(A1)                       | SCC WR14: enter DPLL search mode
        MOVEQ.L #0x3,D0                         | 3 additional CTS checks
        ADDQ.W  #0x3,D3                         | add to collision counter
        MOVE.B  #0x41,(A1)                      | SCC WR14: enable DPLL + BR gen
E_MPP_PRIME_LOOP_3:
        BSR.B   RETURNS_4                       | wait one slot, check CTS
        DBEQ    D0,E_MPP_PRIME_LOOP_3           | loop until CTS or timeout
| E_MPP_PRIME_CONT_7: check if channel acquired
E_MPP_PRIME_CONT_7:
        BEQ     E_MPP_PRIME_CONT_9              | channel busy -> collision backoff
        MOVE.B  #0xA,(A1)                       | SCC WR10: select FM0 encoding
        MOVE.B  0xAC(A2),D2                     | D2 = LAP type from saved state
        TST.B   (A0)                            | check SCC RR0 for DCD loss
        BMI     E_MPP_PRIME_CONT_9              | DCD dropped -> collision
        MOVE.B  #0x5,(A1)                       | SCC WR5 register select
        MOVEQ.L #-0x7C,D0                       | 0x84 = TX enable, RTS, 8bit, CRC
        MOVE.B  #0x62,(A1)                      | SCC WR5: CRC preset + SDLC mode
        TST.B   0xB0(A2)                        | ENQ/ACK mode (AARP probe)?
        BEQ.B   E_MPP_PRIME_NO_3                | no, normal DDP ->
        MOVEQ.L #-0x7F,D0                       | 0x81 = TX enable, no RTS (probe)
| E_MPP_PRIME_NO_3: program SCC for SDLC transmit
E_MPP_PRIME_NO_3:
        MOVE.B  #0x5,(A1)                       | SCC WR5 register select
        NOP                                     | SCC register access delay
        MOVE.B  0xF7(A2),(A1)                   | load SCC WR5 with TX config byte
        BSR     E_MPP_PRIME_CONT_15             | send SDLC opening flags + LAP header
        ADDQ.B  #0x1,D2                         | D2 was $FF (broadcast)? -> 0
        BEQ.B   E_MPP_PRIME_SKIP                | broadcast: skip data body ->
        CLR.B   0xAE(A2)                        | clear TX-complete flag
        BSR     E_MPP_PRIME_CONT_13             | transmit packet data body via SCC
        TST.B   0xB0(A2)                        | ENQ/ACK mode (probe)?
        BEQ.B   E_MPP_PRIME_NO_4                | no, check normal TX result ->
        TST.B   0xAF(A2)                        | probe collision detected?
        BEQ.B   E_MPP_PRIME_RETRY_2             | yes -> retry with new backoff
        BRA.B   E_MPP_PRIME_EXIT                | probe succeeded -> return OK

| ----------------------------------------------------------
|
| E_MPP_PRIME_NO_4: check normal DDP transmit result
|
E_MPP_PRIME_NO_4:
        TST.B   0xAE(A2)                        | TX underrun detected?
        BEQ.B   E_MPP_PRIME_RETRY_2             | yes -> retry with collision backoff
        BRA.B   E_MPP_PRIME_DONE                | TX complete -> send closing flags

| ----------------------------------------------------------
|
| RETURNS_4: wait one LocalTalk slot time (~400us), test carrier
| Returns: Z=1 if carrier detected (DCD low)
|
RETURNS_4:
        MOVEQ.L #0x3C,D1                        | 60 iterations (~400us at 7.8MHz)
E_MPP_PRIME_LOOP_4:
        DBF     D1,E_MPP_PRIME_LOOP_4           | busy-wait delay loop
        BTST    #0x4,(A0)                       | SCC RR0 bit 4: DCD (carrier detect)
        RTS                                     | Z=1 if carrier present

| ----------------------------------------------------------
|
| E_MPP_PRIME_SKIP: broadcast frame - wait for slot then close
|
E_MPP_PRIME_SKIP:
        BSR.B   RETURNS_4                       | wait one slot time, check carrier
        BEQ.B   E_MPP_PRIME_RETRY_2             | carrier collision -> retry
| E_MPP_PRIME_DONE: send SDLC closing flags and CRC
E_MPP_PRIME_DONE:
        BSR     E_MPP_PRIME_ERR_2               | transmit CRC, closing flag, abort
| E_MPP_PRIME_EXIT: transmit complete - return success
E_MPP_PRIME_EXIT:
        MOVEQ.L #0x0,D0                         | noErr: transmit succeeded
| E_MPP_PRIME_CONT_8: restore SR and return to caller via saved return address
E_MPP_PRIME_CONT_8:
        MOVE    (SP)+,SR                        | restore saved interrupt state
        MOVE.L  0xA6(A2),A0                     | A0 = saved completion return address
        JMP     (A0)                            | return to transmit caller

| ----------------------------------------------------------
|
| E_MPP_PRIME_RETRY_2: collision detected - exponential backoff and retry
|
E_MPP_PRIME_RETRY_2:
        MOVE    (SP),SR                         | restore SR (keep on stack for retry)
        BSET    #0x0,0xB4(A2)                   | set collision-occurred flag
        MOVE.B  0xB2(A2),D0                     | D0 = current backoff window
        ADD.B   D0,D0                           | double the backoff window
        ADDQ.B  #0x1,D0                         | ensure odd (randomizer spread)
        MOVE.B  D0,0xB2(A2)                     | store widened backoff window
        MOVEQ.L #-0x5F,D0                       | cbNotFound: collision error code
        SUBQ.B  #0x1,0xB7(A2)                   | decrement retry counter
        BEQ.B   E_MPP_PRIME_CONT_8              | retries exhausted -> give up
        BRA     E_MPP_PRIME_RETRY               | -> retry CSMA/CA from backoff

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_9: deferred transmit - channel was busy, handle collision
|
E_MPP_PRIME_CONT_9:
        SUB     D0,D3                           | adjust collision counter
        SUBQ.W  #0x4,D3                         | subtract initial CTS checks
        BLT.B   E_MPP_PRIME_SKIP_2              | short defer, not a real collision ->
        MOVEQ.L #-0x5F,D0                       | cbNotFound: collision error
        SUBQ.B  #0x1,0xB6(A2)                   | decrement deferred-retry counter
        BEQ.B   E_MPP_PRIME_CONT_8              | retries exhausted -> give up
        BSET    #0x0,0xB2(A2)                   | widen backoff window (set bit 0)
        BSET    #0x0,0xB5(A2)                   | mark deferred collision flag
| E_MPP_PRIME_SKIP_2: set SCC to receive mode and schedule deferred transmit
E_MPP_PRIME_SKIP_2:
        MOVE    #0x2600,SR                      | raise IPL for SCC register access
        MOVE.B  #0xF,(A1)                       | SCC WR15 register select
        MOVEQ.L #-0x78,D0                       | 0x88 = DCD + break/abort IE
        MOVE.B  D0,(A1)                         | enable DCD interrupt for carrier sense
        ADDQ.B  #0x2,0xB1(A2)                   | set deferred-transmit pending flag
        MOVEQ.L #0x0,D0                         | noErr (deferred, not failed)
        MOVE    (SP)+,SR                        | restore interrupt state
        RTS                                     | return (TX will resume on interrupt)

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_10: SCC external/status interrupt handler
| Called when SCC detects DCD change (carrier sense) or break/abort
|
E_MPP_PRIME_CONT_10:
        MOVE.L  (ABusVars).w,A2                 | A2 = AppleTalk bus variables
        TST.B   0xB1(A2)                        | deferred transmit pending?
        BNE.B   E_MPP_PRIME_OK                  | yes, resume deferred TX ->
        BTST    #0x3,D1                         | SCC RR0 bit 3: DCD interrupt?
        BEQ.B   E_MPP_PRIME_EMPTY_2             | no, not our interrupt ->
        MOVE.L  (ExtStsDT_1).w,A3               | A3 = previous ext/status handler
        JMP     (A3)                            | chain to original handler

| ----------------------------------------------------------
|
| E_MPP_PRIME_OK: resume deferred transmit after carrier-sense interrupt
|
E_MPP_PRIME_OK:
        CLR.B   0xB1(A2)                        | clear deferred-TX pending flag
E_MPP_PRIME_CONT_11:
        MOVE.B  #0xF,(A1)                       | SCC WR15 register select
        MOVEQ.L #0x8,D0                         | 0x08 = DCD interrupt enable only
        MOVE.B  D0,(A1)                         | restore minimal interrupt mask
        MOVE    0x1C(A2),SR                     | restore saved SR from ABusVars
        BRA     E_MPP_PRIME_LOOP_2              | -> resume CSMA/CA transmit loop

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_12: VBL task - periodic AppleTalk housekeeping (20 ticks)
| Decrements AARP timer, handles deferred transmit countdown
|
E_MPP_PRIME_CONT_12:
        MOVE    #0x14,0xA(A0)                   | reschedule VBL in 20 ticks (1/3 sec)
        MOVE.L  (ABusVars).w,A2                 | A2 = ABusVars
        SUBQ.B  #0x1,0xB8(A2)                   | decrement AARP validity timer
        BNE.B   E_MPP_PRIME_NO_5                | not expired ->
        CLR.B   0x19(A2)                        | timer expired: clear bridge node ID
E_MPP_PRIME_NO_5:
        TST.B   0xB1(A2)                        | deferred transmit pending?
        BEQ.B   E_MPP_PRIME_EMPTY_2             | no ->
        SUBQ.B  #0x1,0xB1(A2)                   | decrement deferred-TX countdown
        BNE.B   E_MPP_PRIME_EMPTY_2             | not zero yet ->
        MOVEM.L (SCCRd).w,A0-A1                 | A0=SCC read, A1=SCC write
        MOVE    #0x2600,SR                      | disable interrupts for SCC access
        BSR     E_MPP_PRIME_CONT_25             | reset SCC to receive mode
        BRA.B   E_MPP_PRIME_CONT_11             | -> resume deferred transmit

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_13: poll SCC for incoming packet during transmit gap
| Handles any received frame that arrives while we own the bus
|
E_MPP_PRIME_CONT_13:
        MOVEM.L A0-A2,-(SP)                     | save registers across receive check
        MOVEQ.L #0x7D,D1                        | 125 iteration poll timeout
E_MPP_PRIME_LOOP_5:
        BTst    #0x0,(A0)                       | SCC RR0 bit 0: RX char available?
        DBNE    D1,E_MPP_PRIME_LOOP_5           | no, keep polling
        BEQ.B   E_MPP_PRIME_NO_6                | timeout with no data ->
        BSR     E_MPP_PRIME_CONT_21             | process received LAP frame
E_MPP_PRIME_NO_6:
        MOVEM.L (SP)+,A0-A2                     | restore registers
E_MPP_PRIME_EMPTY_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| RETURNS_5: pseudo-random number generator (linear congruential)
| seed = seed * 773 + 1, then byte-swap for better randomness
| Returns: D0 = random 16-bit value
|
RETURNS_5:
        MOVE    0xAA(A2),D0                     | D0 = current PRNG seed
        MULU    #0x305,D0                       | multiply by 773
        ADDQ.W  #0x1,D0                         | add 1 (LCG increment)
        MOVE    D0,-(SP)                        | push result to stack
        LSL     #0x8,D0                         | shift high byte to low position
        MOVE.B  (SP)+,D0                        | merge: swap high/low bytes
        MOVE    D0,0xAA(A2)                     | store new seed in ABusVars
        RTS                                     | return random value in D0

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_14: SCC WR5/WR3 reset command bytes (inline data)
|
E_MPP_PRIME_CONT_14:
  .byte  0x05,0x6B,0x03,0xD0                    | WR5=0x6B (TX off), WR3=0xD0 (RX off)
| RETURNS_6: wait for SCC TX buffer empty, send byte D3
| Returns: Z=1 if timeout (D1 exhausted), NZ if sent
RETURNS_6:
        MOVEQ.L #0x1E,D1                        | 30 iteration poll timeout
E_MPP_PRIME_LOOP_6:
        BTst    #0x2,(A0)                       | SCC RR0 bit 2: TX buffer empty?
        DBNE    D1,E_MPP_PRIME_LOOP_6           | not empty, keep waiting
        BEQ.B   E_MPP_PRIME_SKIP_3              | timeout -> skip write
        MOVE.B  D3,0x4(A1)                      | write byte D3 to SCC TX data reg
E_MPP_PRIME_SKIP_3:
        TST     D1                              | set Z flag based on timeout
        RTS                                     | Z=1 if timed out

| ----------------------------------------------------------
|
| E_MPP_PRIME_ERR: reset SCC TX/RX and send SDLC abort sequence
| Disables TX/RX via WR5/WR3, then sends abort pattern
|
E_MPP_PRIME_ERR:
        LEA.L   E_MPP_PRIME_CONT_14(PC),A3      | A3 = SCC reset command bytes
        MOVEQ.L #0x4,D3                         | 4 register/value pairs
        BSR     E_MPP_PRIME_CONT_19             | write reset commands to SCC
        MOVEQ.L #0x28,D3                        | 40 iteration delay
E_MPP_PRIME_LOOP_7:
        DBF     D3,E_MPP_PRIME_LOOP_7           | wait for SCC to settle
        MOVE.B  #0x80,(A1)                      | SCC: send SDLC abort (8 ones)
        RTS                                     | return with TX/RX disabled

| ----------------------------------------------------------
|
| E_MPP_PRIME_ERR_2: transmit packet data body, CRC, closing flag
| Iterates through data chunk list at (A2+$A2), sends via SCC
|
E_MPP_PRIME_ERR_2:
        MOVEM.L A0-A1/A4-A6,0xDE(A2)            | save registers in ABusVars scratch
        MOVE.L  (DskRtnAdr).w,-(SP)             | save disk return address
        MOVE.L  (PollStack).w,-(SP)             | save poll stack pointer
        MOVE.L  A7,(PollStack).w                | set current SP as poll stack
        MOVE.L  0xF2(A2),A5                     | A5 = VIA Port A address
        LEA.L   0x6(A0),A6                      | A6 = SCC data read register
        MOVE.L  0xA2(A2),A4                     | A4 = data chunk list pointer
        BSR.B   E_MPP_PRIME_ERR                 | reset SCC TX/RX, send abort
        MOVE    (A4)+,D3                        | D3 = first chunk byte count
        MOVE.L  (A4)+,A3                        | A3 = first chunk data pointer
        MOVE.B  (A3)+,0x4(A1)                   | send first byte to SCC TX data
        SUBQ.W  #0x1,D3                         | decrement chunk byte count
        MOVE.B  (A2),(A3)                       | patch our node ID into data
| E_MPP_PRIME_NEXT: transmit loop - send data bytes via SCC
E_MPP_PRIME_NEXT:
        MOVEQ.L #0x1E,D0                        | 30 iteration TX-ready poll timeout
E_MPP_PRIME_LOOP_8:
        BTst    #0x2,(A0)                       | SCC RR0 bit 2: TX buffer empty?
        DBNE    D0,E_MPP_PRIME_LOOP_8           | not ready, keep polling
        BNE.B   E_MPP_PRIME_NEXT_2              | TX ready -> send next byte
        BSR.B   E_MPP_PRIME_ERR_3               | timeout: abort transmit sequence
        BRA.B   E_MPP_PRIME_EXIT_2              | -> cleanup and return

| ----------------------------------------------------------
|
| E_MPP_PRIME_NEXT_2: send next data byte and check for incoming frame
|
E_MPP_PRIME_NEXT_2:
        MOVE.B  (A3)+,0x4(A1)                   | write next byte to SCC TX data
        TST.B   (A5)                            | VIA Port A: check for RX activity
        BMI.B   E_MPP_PRIME_NO_7                | no incoming frame ->
        MOVE.B  (A6),-(SP)                      | read SCC RX byte (discard on stack)
E_MPP_PRIME_NO_7:
        SUBQ.W  #0x1,D3                         | decrement chunk byte count
        BGT.B   E_MPP_PRIME_NEXT                | more bytes in chunk ->
        MOVE    (A4)+,D3                        | D3 = next chunk byte count
        BEQ.B   E_MPP_PRIME_EMPTY_3             | zero = end of data list ->
        MOVE.L  (A4)+,A3                        | A3 = next chunk data pointer
        BRA.B   E_MPP_PRIME_NEXT                | -> transmit next chunk

| ----------------------------------------------------------
|
| E_MPP_PRIME_EMPTY_3: all data sent - transmit CRC and closing flag
|
E_MPP_PRIME_EMPTY_3:
        BSR.B   E_MPP_PRIME_CONT_16             | send CRC, SDLC closing flag, cleanup
| E_MPP_PRIME_EXIT_2: post-transmit cleanup - call poll proc, restore state
E_MPP_PRIME_EXIT_2:
        MOVE.L  (PollProc).w,D3                 | disk poll procedure installed?
        BEQ.B   E_MPP_PRIME_NO_8                | no ->
        MOVE.L  D3,A4                           | A4 = poll procedure
        JSR     (A4)                            | call disk poll (cooperative multitask)
        MOVE.L  (ABusVars).w,A2                 | reload A2 (may have been clobbered)
E_MPP_PRIME_NO_8:
        MOVEM.L 0xDE(A2),A0-A1/A4-A6            | restore saved registers
        MOVE.L  (PollStack).w,SP                | restore stack pointer
        MOVE.L  (SP)+,(PollStack).w             | restore original poll stack
        MOVE.L  (SP)+,(DskRtnAdr).w             | restore disk return address
        RTS                                     | return to transmit caller

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_15: send SDLC opening flags + LAP dest/src header bytes
| D2 = LAP type, (A2) = our node ID
|
E_MPP_PRIME_CONT_15:
        BSR     E_MPP_PRIME_ERR                 | reset SCC, send abort pattern
        MOVE.B  D2,0x4(A1)                      | TX first byte: LAP dest node
        MOVE.B  (A2),D3                         | D3 = our node ID (LAP source)
        BSR     RETURNS_6                       | wait TX ready, send source node
        BEQ.B   E_MPP_PRIME_ERR_3               | TX timeout -> abort
        MOVE.B  D0,D3                           | D3 = LAP type byte
        BSR     RETURNS_6                       | wait TX ready, send LAP type
        BEQ.B   E_MPP_PRIME_ERR_3               | TX timeout -> abort
| E_MPP_PRIME_CONT_16: send CRC and SDLC closing flag
E_MPP_PRIME_CONT_16:
        MOVE.B  #0xC0,(A1)                      | SCC: reset TX CRC generator
        LSL     #0x1,D3                         | shift (delay for CRC calc)
E_MPP_PRIME_CONT_17:
        BTst    #0x6,(A0)                       | SCC RR0 bit 6: TX underrun/EOM?
        BEQ.B   E_MPP_PRIME_CONT_17             | wait for underrun latch ->
E_MPP_PRIME_CONT_18:
        BTst    #0x2,(A0)                       | SCC RR0 bit 2: TX buffer empty?
        BEQ.B   E_MPP_PRIME_CONT_18             | wait for last byte to shift out ->
        MOVE.B  #0x5,(A1)                       | SCC WR5 register select
        MOVEQ.L #0x0,D3                         | clear D3 for delay counter
        MOVE.B  #0x62,(A1)                      | SCC WR5: TX enable, SDLC/CRC mode
        MOVE.B  0xB9(A2),D3                     | D3 = post-TX settling delay count
E_MPP_PRIME_LOOP_9:
        DBF     D3,E_MPP_PRIME_LOOP_9           | wait for CRC to transmit
| E_MPP_PRIME_ERR_3: write SCC register cleanup sequence (6 bytes from ABusVars+$F6)
E_MPP_PRIME_ERR_3:
        LEA.L   0xF6(A2),A3                     | A3 = SCC register init table
        MOVEQ.L #0x6,D3                         | 6 bytes to write
| E_MPP_PRIME_CONT_19: write D3 bytes from (A3) to SCC write register
E_MPP_PRIME_CONT_19:
        MOVE.B  (A3)+,(A1)                      | write next byte to SCC
        SUBQ.W  #0x1,D3                         | decrement count
        BNE.B   E_MPP_PRIME_CONT_19             | more bytes ->
        RTS                                     | return with SCC configured

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_20: SCC receive interrupt handler - incoming LAP frame
| Reads LAP header bytes (dest, src, type), dispatches to protocol handler
|
E_MPP_PRIME_CONT_20:
        MOVE.L  (ABusVars).w,A2                 | A2 = AppleTalk bus variables
| E_MPP_PRIME_CONT_21 -- process received LAP frame.
E_MPP_PRIME_CONT_21:
        LEA.L   0x1(A2),A3                      | A3 = LAP header buffer in ABusVars
        MOVE.B  0x4(A0),(A3)+                   | read LAP dest node from SCC RX data
        MOVEQ.L #0x28,D1                        | 40 iteration RX poll timeout
E_MPP_PRIME_LOOP_10:
        BTst    #0x0,(A0)                       | SCC RR0 bit 0: RX char available?
        DBNE    D1,E_MPP_PRIME_LOOP_10          | wait for next byte
        BEQ.B   E_MPP_PRIME_ERR_4               | timeout -> abort receive
        MOVE.B  0x4(A0),(A3)+                   | read LAP source node
E_MPP_PRIME_LOOP_11:
        BTst    #0x0,(A0)                       | RX char available?
        DBNE    D1,E_MPP_PRIME_LOOP_11          | wait for LAP type byte
        BEQ.B   E_MPP_PRIME_ERR_4               | timeout ->
        MOVE.B  0x4(A0),D0                      | D0 = LAP type byte
        MOVE.B  D0,(A3)+                        | store in header buffer
        BMI.B   E_MPP_PRIME_CONT_22             | bit 7 set: control frame ->
| look up LAP protocol handler for this type
        MOVEQ.L #0x3,D2                         | scan 4 LAP handler slots
E_MPP_PRIME_LOOP_12:
        CMP.B   0x22(A2,D2.W),D0                | slot matches LAP type?
        DBEQ    D2,E_MPP_PRIME_LOOP_12          | no, try next
        LSL     #0x2,D2                         | D2 *= 4 (handler table index)
| read DDP length/hop count word (first 2 bytes of DDP header)
        MOVEQ.L #0x28,D0                        | 40 iteration poll timeout
E_MPP_PRIME_LOOP_13:
        BTst    #0x0,(A0)                       | RX char available?
        DBNE    D0,E_MPP_PRIME_LOOP_13          | wait
        BEQ.B   E_MPP_PRIME_ERR_4               | timeout ->
        MOVE.B  0x4(A0),(A3)                    | read DDP length high byte
        MOVEQ.L #0x3,D1                         | mask for 10-bit length (high 2 bits)
        AND.B   (A3)+,D1                        | D1 = length high bits (0-3)
        LSL     #0x8,D1                         | shift to high byte position
        MOVEM.L A4-A5,0xBA(A2)                  | save A4-A5 in ABusVars scratch
E_MPP_PRIME_LOOP_14:
        BTst    #0x0,(A0)                       | RX char available?
        DBNE    D0,E_MPP_PRIME_LOOP_14          | wait for length low byte
E_MPP_PRIME_ERR_4:
        BEQ.B   E_MPP_PRIME_CONT_24             | timeout -> discard frame
        MOVE.B  0x4(A0),D1                      | read DDP length low byte
        MOVE.B  D1,(A3)+                        | store in receive buffer
        SUBQ.W  #0x2,D1                         | subtract 2 (already read 2 header bytes)
        TST     D2                              | LAP handler found? (D2 >= 0)
        BMI.B   E_MPP_PRIME_NO_9                | no handler for this type ->
        MOVE.L  0x26(A2,D2.W),A5                | A5 = LAP protocol handler
        LEA.L   E_MPP_PRIME_CONT_28(PC),A4      | A4 = SCC byte-read subroutine
        JMP     (A5)                            | dispatch to protocol handler

| ----------------------------------------------------------
|
| E_MPP_PRIME_NO_9: no LAP handler - try default receive into buffer
|
E_MPP_PRIME_NO_9:
        MOVE.B  #0x1,(A1)                       | SCC: point to RR1 (special conditions)
        MOVEQ.L #-0x60,D0                       | 0xA0 mask: end-of-frame + RX overrun
        AND.B   (A0),D0                         | check SCC RR1 status
        BNE     E_MPP_PRIME_ERR_6               | frame error -> abort
        CLR     D3                              | D3 = 0 (no bytes to store)
        BRA     E_MPP_PRIME_CONT_29             | -> receive remaining data to stack

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_22: LAP control frame (type $80-$85)
| Handles ENQ/ACK for AARP node address acquisition
|
E_MPP_PRIME_CONT_22:
        MOVEQ.L #0x7F,D2                        | mask off high bit
        AND.B   D0,D2                           | D2 = control frame subtype (0-5)
        CMPI.B  #0x5,D2                         | valid control type (0-5)?
        BGT.B   E_MPP_PRIME_CONT_24             | invalid -> discard frame
        BSR.B   RETURNS_7                       | receive control frame body via SCC
        BNE.B   E_MPP_PRIME_ERR_5               | receive error ->
        CMPI.B  #0xFF,0x1(A2)                   | LAP dest was broadcast ($FF)?
        SEQ.B   D1                              | D1 = $FF if broadcast, 0 if unicast
        BEQ.B   E_MPP_PRIME_OK_2                | broadcast -> process control frame
        TST.B   0xAD(A2)                        | AARP probe phase complete?
        BNE.B   E_MPP_PRIME_OK_2                | yes -> accept unicast control
        ST.B    0xAF(A2)                        | set collision flag (address in use)
E_MPP_PRIME_ERR_5:
        RTS                                     | return to interrupt handler

| ----------------------------------------------------------
|
| E_MPP_PRIME_OK_2: dispatch LAP control frame by subtype
| 1=ENQ, 4=ACK, 5=RTS/CTS
|
E_MPP_PRIME_OK_2:
        SUBQ.B  #0x1,D2                         | subtype 1 (ENQ)?
        BEQ.B   E_MPP_PRIME_OK_5                | yes -> send ACK response
        SUBQ.B  #0x3,D2                         | subtype 4 (ACK)?
        BEQ.B   E_MPP_PRIME_OK_3                | yes -> handle ACK
        SUBQ.B  #0x1,D2                         | subtype 5 (RTS)?
        SEQ.B   0xAE(A2)                        | set TX-complete flag if RTS
        RTS                                     | return to interrupt handler

| ----------------------------------------------------------
|
| E_MPP_PRIME_OK_3: received ACK - if broadcast, ignore; else respond
|
E_MPP_PRIME_OK_3:
        TST.B   D1                              | was it a broadcast ACK?
        BNE.B   E_MPP_PRIME_OK_4                | yes -> ignore (poll for bus activity)
        MOVEQ.L #0x14,D0                        | 20 iteration delay
E_MPP_PRIME_LOOP_15:
        DBF     D0,E_MPP_PRIME_LOOP_15          | wait before responding
        MOVEQ.L #-0x7B,D0                       | 0x85 = LAP CTS control frame type
        BSR.B   E_MPP_PRIME_CONT_23             | send CTS response frame
E_MPP_PRIME_OK_4:
        BRA     E_MPP_PRIME_CONT_13             | -> poll for more incoming data

| ----------------------------------------------------------
|
| E_MPP_PRIME_OK_5: received ENQ - reply with ACK
|
E_MPP_PRIME_OK_5:
        MOVEQ.L #-0x7E,D0                       | 0x82 = LAP ACK control frame type
| E_MPP_PRIME_CONT_23: send LAP control frame (type in D0, dest = sender)
E_MPP_PRIME_CONT_23:
        MOVE.B  0x2(A2),D2                      | D2 = sender's node (from LAP header)
        BRA     E_MPP_PRIME_CONT_15             | -> transmit control frame

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_24: discard frame - reset SCC receiver twice (flush FIFO)
|
E_MPP_PRIME_CONT_24:
        BSR.B   E_MPP_PRIME_CONT_25             | first SCC receiver reset
        BRA.B   E_MPP_PRIME_CONT_25             | second reset (clears 3-byte FIFO)

| ----------------------------------------------------------
|
| RETURNS_7: receive LAP control frame body (2 data bytes + CRC check)
| Returns: D0 = 0 if good CRC, nonzero if error
|
RETURNS_7:
        CLR     D0                              | D0 = error accumulator (0 = OK)
        MOVEQ.L #0x10,D1                        | 16 iteration RX poll timeout
E_MPP_PRIME_LOOP_16:
        BTst    #0x0,(A0)                       | SCC RR0 bit 0: RX char available?
        DBNE    D1,E_MPP_PRIME_LOOP_16          | wait for first data byte
        BEQ.B   E_MPP_PRIME_ERR_7               | timeout -> error
        BSR.B   E_MPP_PRIME_CONT_27             | read RR1 status into D1
        BMI.B   E_MPP_PRIME_ERR_6               | framing error -> adjust error count
        TST.B   0x4(A0)                         | read and discard RX data byte
        MOVEQ.L #0x10,D1                        | 16 iteration poll timeout
E_MPP_PRIME_LOOP_17:
        BTst    #0x0,(A0)                       | RX char available?
        DBNE    D1,E_MPP_PRIME_LOOP_17          | wait for second byte
        BEQ.B   E_MPP_PRIME_ERR_7               | timeout ->
        BSR.B   E_MPP_PRIME_CONT_27             | read RR1 status
        BPL.B   E_MPP_PRIME_ERR_6               | no end-of-frame -> error
        LSL.B   #0x1,D1                         | shift to check CRC error bit
        BMI.B   E_MPP_PRIME_ERR_8               | CRC error -> return error
| E_MPP_PRIME_CONT_25: reset SCC receiver - flush FIFO, re-enable hunt mode
E_MPP_PRIME_CONT_25:
        BSR.B   E_MPP_PRIME_CONT_27             | read SCC RR1 into D1
        BTST    #0x5,D1                         | RR1 bit 5: end-of-frame?
        BEQ.B   E_MPP_PRIME_NO_10               | no ->
        BCLR    #0x7,(IntFlag).w                | clear interrupt pending flag
E_MPP_PRIME_NO_10:
        MOVEQ.L #-0x30,D1                       | 0xD0 = WR3: RX 8bit, enter hunt, RX en
        BSR.B   E_MPP_PRIME_CONT_26             | write to SCC WR3
        MOVEQ.L #0x2,D1                         | 3 bytes to drain from FIFO
E_MPP_PRIME_LOOP_18:
        TST.B   0x4(A0)                         | read and discard SCC RX data
        DBF     D1,E_MPP_PRIME_LOOP_18          | drain remaining FIFO bytes
        MOVEQ.L #-0x23,D1                       | 0xDD = WR3: RX 8bit, auto-enable, RX en
        BSR.B   E_MPP_PRIME_CONT_26             | write to SCC WR3
        MOVE.B  #0x30,(A1)                      | SCC: reset highest IUS (end interrupt)
        MOVE    (SP),(SP)                       | NOP-style delay (SCC recovery time)
        MOVE.B  #0x20,(A1)                      | SCC: reset RX interrupt on next char
        TST     D0                              | set flags based on error accumulator
        RTS                                     | return with Z flag from D0

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_26: write SCC WR3 register with value in D1
|
E_MPP_PRIME_CONT_26:
        MOVE.B  #0x3,(A1)                       | SCC WR3 register select
        NOP                                     | SCC register access delay
        MOVE.B  D1,(A1)                         | write WR3 value
        RTS                                     | return

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_27: read SCC RR1 (special receive conditions) into D1
|
E_MPP_PRIME_CONT_27:
        MOVE.B  #0x1,(A1)                       | SCC RR1 register select
        NOP                                     | SCC register access delay
        MOVE.B  (A0),D1                         | D1 = RR1 (framing/CRC/overrun status)
        RTS                                     | return with status in D1

| ----------------------------------------------------------
|
| E_MPP_PRIME_ERR_6: receive error - accumulate error code and reset SCC
| Each error path falls through to subtract different amounts from D0
|
E_MPP_PRIME_ERR_6:
        BTst    #0x5,D1                         | RR1 bit 5: end-of-frame?
        BNE.B   E_MPP_PRIME_ERR_9               | yes, just -1 (minor error)
        MOVEQ.L #-0x1,D0                        | D0 = -1 (will become -4 total)
E_MPP_PRIME_ERR_7:
        SUBQ.W  #0x1,D0                         | -2: timeout error
E_MPP_PRIME_ERR_8:
        SUBQ.W  #0x1,D0                         | -3: CRC error
E_MPP_PRIME_ERR_9:
        SUBQ.W  #0x1,D0                         | -1/-2/-3/-4: error severity
        BRA.B   E_MPP_PRIME_CONT_25             | -> reset SCC receiver

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_28: SCC data read subroutine - used as A4 callback by protocol handlers
|
E_MPP_PRIME_CONT_28:
        BRA.B   E_MPP_PRIME_CONT_31             | -> read D3 bytes from SCC into (A3)

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_29: receive remaining packet data into buffer (A3) and stack
| D1 = remaining byte count, D3 = buffer capacity
|
E_MPP_PRIME_CONT_29:
        MOVE.L  0xF2(A2),A5                     | A5 = VIA Port A address
        MOVE.L  A7,A4                           | A4 = save stack pointer
| E_MPP_PRIME_NEXT_3: receive loop - one byte per iteration
E_MPP_PRIME_NEXT_3:
        MOVEQ.L #0x10,D0                        | 16 iteration RX poll timeout
        SUBQ.W  #0x1,D1                         | decrement expected byte count
        BMI.B   E_MPP_PRIME_CONT_30             | all bytes received -> finish
E_MPP_PRIME_LOOP_19:
        BTst    #0x0,(A0)                       | SCC RR0 bit 0: RX char available?
        DBNE    D0,E_MPP_PRIME_LOOP_19          | wait for data
        BEQ.B   E_MPP_PRIME_CONT_30             | timeout -> finish early
        MOVE.B  0x4(A0),D0                      | D0 = received data byte
        TST.B   (A5)                            | VIA Port A: check handshake line
        BMI.B   E_MPP_PRIME_NO_11               | no collision ->
        MOVE.B  0x6(A0),-(SP)                   | push SCC special condition byte
E_MPP_PRIME_NO_11:
        SUBQ.W  #0x1,D3                         | decrement buffer space
        BMI.B   E_MPP_PRIME_NEXT_3              | buffer full, discard but keep reading
        MOVE.B  D0,(A3)+                        | store byte in receive buffer
        BRA.B   E_MPP_PRIME_NEXT_3              | -> next byte

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_30: packet receive complete - check CRC, call poll proc
|
E_MPP_PRIME_CONT_30:
        BSR     RETURNS_7                       | receive CRC bytes, validate frame
        MOVE.L  (PollStack).w,0xC6(A2)          | save current poll stack in ABusVars
        MOVE.L  A4,(PollStack).w                | set our saved SP as poll stack
        MOVE.L  (PollProc).w,D1                 | disk poll procedure installed?
        BEQ.B   E_MPP_PRIME_NO_12               | no ->
        MOVEM.L D0/D2-D3/A3/A6,0xDE(A2)         | save registers in ABusVars scratch
        LEA.L   0x6(A0),A6                      | A6 = SCC data read address
        MOVE.L  D1,A0                           | A0 = poll procedure address
        MOVE.L  (DskRtnAdr).w,0xC2(A2)          | save disk return address
        JSR     (A0)                            | call disk poll (cooperative multitask)
        MOVE.L  (ABusVars).w,A2                 | reload A2 (poll may have changed it)
        MOVE.L  0xC2(A2),(DskRtnAdr).w          | restore disk return address
        MOVEM.L 0xDE(A2),D0/D2-D3/A3/A6         | restore saved registers
E_MPP_PRIME_NO_12:
        MOVE.L  (PollStack).w,SP                | restore stack pointer
        MOVE.L  0xC6(A2),(PollStack).w          | restore original poll stack
| E_MPP_PRIME_ERR_10: finish receive - restore A4-A5, set flags, return
E_MPP_PRIME_ERR_10:
        MOVEM.L 0xBA(A2),A4-A5                  | restore A4-A5 from ABusVars scratch
        TST     D0                              | set Z flag from receive result
E_MPP_PRIME_EXIT_3:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_PRIME_CONT_31: read D3 bytes from SCC into buffer at (A3)
| Called via JMP (A4) or JSR (A4) by DDP receive handlers
|
E_MPP_PRIME_CONT_31:
        SUB     D3,D1                           | adjust remaining packet length
E_MPP_PRIME_CONT_32:
        MOVEQ.L #0x10,D0                        | 16 iteration RX poll timeout
E_MPP_PRIME_LOOP_20:
        BTst    #0x0,(A0)                       | SCC RR0 bit 0: RX char available?
        DBNE    D0,E_MPP_PRIME_LOOP_20          | wait for data byte
        BEQ.B   E_MPP_PRIME_ERR_11              | timeout -> error
        MOVE.B  0x4(A0),(A3)+                   | read byte from SCC into buffer
        SUBQ.W  #0x1,D3                         | decrement byte count
        BNE.B   E_MPP_PRIME_CONT_32             | more bytes to read ->
        MOVE.B  #0x1,(A1)                       | SCC: select RR1 (status register)
        MOVEQ.L #-0x60,D0                       | 0xA0 mask: end-of-frame + overrun
        AND.B   (A0),D0                         | check receive status
        BEQ.B   E_MPP_PRIME_EXIT_3              | clean -> return OK (Z=1)
        BMI.B   E_MPP_PRIME_ERR_12              | end-of-frame (premature) -> error
        MOVEQ.L #-0x1,D0                        | RX overrun error
        BRA.B   E_MPP_PRIME_ERR_13              | -> reset and return error

| ----------------------------------------------------------
|
| E_MPP_PRIME_ERR_11: SCC receive timeout during byte read
|
E_MPP_PRIME_ERR_11:
        MOVEQ.L #-0x3,D0                        | timeout error code
        BRA.B   E_MPP_PRIME_ERR_13              | -> reset and return error

| ----------------------------------------------------------
|
| E_MPP_PRIME_ERR_12: premature end-of-frame during byte read
|
E_MPP_PRIME_ERR_12:
        MOVEQ.L #-0x4,D0                        | premature EOF error code
E_MPP_PRIME_ERR_13:
        BSR     E_MPP_PRIME_CONT_25             | reset SCC receiver
        BRA.B   E_MPP_PRIME_ERR_10              | -> restore regs, return error status

| ----------------------------------------------------------
|
| E_MPP_Close
|
| .MPP Close: shut down AppleTalk, restore serial drivers
| Closes .ATP, removes SCC interrupt handler and VBL task,
| restores .BIn/.BOut drivers to unit table, frees ABusVars
E_MPP_Close:
        MOVE.L  (UTableBase).w,A4               | A4 = unit table
        ADDA    #0x28,A4                        | point past serial driver slots
        MOVE.L  (ABusVars).w,A2                 | A2 = ABusVars
        MOVE.L  A2,D0                           | initialized?
        BEQ     E_MPP_CLOSE_NO                  | no, nothing to close ->
| close .ATP driver first
        ST.B    0x1E(A2)                        | mark as closing
        SUBA    #0x32,SP                        | allocate IOParam on stack
        MOVE.L  A7,A0                           | A0 = IOParam block on stack
        MOVE    #-0xB,0x18(A0)                  | ioRefNum = -11 (.ATP)
        _Close                                  | close .ATP driver
        ADDA    #0x32,SP                        | pop IOParam
| remove SCC interrupt handler and VBL task
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | disable interrupts
        LEA.L   INIT_TBL(PC),A0                 | SCC init table (reset to default)
        BSR.B   E_MPP_CLOSE_CONT                | reprogram SCC for normal serial
        LEA.L   0x7C(A2),A0                     | VBL task record
        _VRemove                                | remove retransmission VBL
        LEA.L   0xD2(A2),A0                     | saved interrupt vectors in ABusVars
        LEA.L   (Lvl2DT_2).w,A3                 | A3 = level 2 dispatch table slot
        MOVE.L  (A0)+,(A3)+                     | restore original SCC RX handler
        MOVE.L  (A0)+,(A3)+                     | restore original SCC TX handler
        MOVE.L  (A0)+,(ExtStsDT).w              | restore original ext/status handler
| restore .BOut and .BIn serial drivers to unit table
        MOVE.L  -(A4),A0                        | A4 already past serial slots; back up
        MOVE.L  0xCE(A2),D0                     | saved .BOut DCE handle
        BEQ.B   E_MPP_CLOSE_EMPTY               | none saved ->
        MOVE.L  D0,-0x4(A4)                     | restore .BOut to unit table
E_MPP_CLOSE_EMPTY:
        MOVE.L  0xCA(A2),D0                     | saved .BIn DCE handle
        BEQ.B   E_MPP_CLOSE_EMPTY_2             | none saved ->
        MOVE.L  D0,-0x8(A4)                     | restore .BIn to unit table
E_MPP_CLOSE_EMPTY_2:
        MOVE    (SP)+,SR                        | restore interrupt state
        MOVE.L  A2,A0                           | A0 = ABusVars pointer
        _DisposePtr                             | free ABusVars memory block
E_MPP_CLOSE_NO:
        ST.B    (PortBUse).w                    | mark port B as available ($FF)
E_MPP_CLOSE_ERR:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_CLOSE_CONT: program SCC from register/value table at (A0)
| Table format: word pairs (reg, value), terminated by 0x0000
|
E_MPP_CLOSE_CONT:
        MOVE.L  (SCCWr).w,A3                    | A3 = SCC write register base
E_MPP_CLOSE_NEXT:
        MOVE    (A0)+,D0                        | D0 = next register/value word
        BEQ.B   E_MPP_CLOSE_ERR                 | zero = end of table -> return
        MOVE.B  D0,(A3)                         | write register number to SCC
        ROR     #0x8,D0                         | swap bytes: value -> low byte
        MOVE.B  D0,(A3)                         | write register value to SCC
        BRA.B   E_MPP_CLOSE_NEXT                | -> next table entry

| ----------------------------------------------------------
|
| INIT_TBL
|
INIT_TBL:
  .byte  0x4A,0x09,0x00,0x0A,0x10,0x00          | SCC init: WR9=0x4A, WR0=0x0A, WR16=0x00
  .byte 0x08,0x0F,0x01,0x01,0x00,0x00           | WR8=0x0F, WR1=0x01, terminator 0x0000

| .MPP Open: initialize AppleTalk network
| Allocates ABusVars ($FC = 252 bytes), configures SCC for LocalTalk,
| takes over serial port from .AIn/.AOut drivers, gets node address
E_MPP_Open:
        MOVEQ.L #-0x61,D0                       | portInUse error
        TST.B   (PortBUse).w                    | printer port already in use?
        BPL.B   E_MPP_CLOSE_ERR                 | yes ->
| check PRAM: port B must be configured for AppleTalk
        MOVEQ.L #-0x62,D0                       | portNotCf error
        MOVE.B  (SPConfig).w,D1                 | PRAM port config
        ANDI.B  #0xF,D1                         | port B nibble (low 4 bits)
        SUBQ.B  #0x1,D1                         | 1 = AppleTalk
        BGT.B   E_MPP_CLOSE_ERR                 | not AppleTalk ->
| allocate AppleTalk bus state block
        CLR.L   (ABusVars).w                    | clear old pointer
        MOVE.L  #0xFC,D0                        | 252 bytes for ABusVars
        _NewPtrSysClear                         | allocate zeroed in system heap
        BNE.B   E_MPP_CLOSE_ERR                 | failed ->
| initialize AppleTalk state
        MOVE.B  #0x1,(PortBUse).w               | mark port B as AppleTalk
        MOVE.L  A0,A2                           | A2 = ABusVars
        MOVE.L  A2,(ABusVars).w                 | save global pointer
        MOVE.L  A1,(ABusVars_dce).w             | save DCE
| steal .BIn and .BOut serial drivers (save and remove from unit table)
        MOVE.L  (UTableBase).w,A0               | unit table
        MOVE.L  0x20(A0),A3                     | unit 8 = .BOut DCE handle
        MOVE.L  A3,D0                           | installed?
        BEQ.B   E_MPP_OPEN_NO                   | no ->
        MOVE.L  (A3),A3                         | dereference DCE
        TST.B   0x7(A3)                         | driver open?
        BNE.B   E_MPP_OPEN_NO                   | yes, can't steal ->
        MOVE.L  D0,0xCE(A2)                     | save .BOut handle in ABusVars
        CLR.L   0x20(A0)                        | remove from unit table
| steal .BIn similarly
E_MPP_OPEN_NO:
        MOVE.L  0x1C(A0),A3                     | unit 7 = .BIn DCE handle
        MOVE.L  A3,D0                           | installed?
        BEQ.B   E_MPP_OPEN_NO_2                 | no ->
        MOVE.L  (A3),A3                         | dereference
        TST.B   0x7(A3)                         | open?
        BNE.B   E_MPP_OPEN_NO_2                 | yes ->
        MOVE.L  D0,0xCA(A2)                     | save .BIn handle
        CLR.L   0x1C(A0)                        | remove from unit table
| initialize LAP protocol handlers (4 slots, all empty)
E_MPP_OPEN_NO_2:
        MOVEQ.L #0x3,D0                         | 4 LAP handler slots
E_MPP_OPEN_LOOP:
        ST.B    0x22(A2,D0.W)                   | mark slot as empty ($FF)
        DBF     D0,E_MPP_OPEN_LOOP              | loop to clear all DDP socket slots
| set up SCC and VIA addresses for LocalTalk I/O
        LEA.L   CONFIG_TBL(PC),A1               | A1 = SCC config table
        LEA.L   (VIA_PortA2).l,A0               | VIA Port A for handshake
        MOVE.L  A0,0xF2(A2)                     | store VIA address in ABusVars
        MOVE.L  (A1)+,0xF6(A2)                  | SCC read/write base addresses
        MOVE    (A1)+,0xFA(A2)                  | SCC channel offset
        MOVE    (A1)+,0x1C(A2)                  | baud rate divisor
        MOVE.B  (A1)+,0xB9(A2)                  | SCC interrupt mask
| configure SCC for SDLC mode (LocalTalk framing)
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | disable interrupts for SCC init
| install SCC interrupt handlers - save originals in ABusVars+$D2
        LEA.L   (Lvl2DT_2).w,A3                 | A3 = level 2 interrupt dispatch table
        LEA.L   0xD2(A2),A1                     | A1 = save area in ABusVars
        LEA.L   E_MPP_PRIME_CONT_20(PC),A0      | A0 = our SCC RX interrupt handler
        MOVE.L  (A3),(A1)+                      | save original RX handler
        MOVE.L  A0,(A3)+                        | install our RX handler
        LEA.L   E_MPP_PRIME_CONT_24(PC),A0      | A0 = our SCC TX interrupt handler
        MOVE.L  (A3),(A1)+                      | save original TX handler
        MOVE.L  A0,(A3)+                        | install our TX handler (discard frame)
        LEA.L   E_MPP_PRIME_CONT_10(PC),A0      | A0 = our ext/status handler
        MOVE.L  (ExtStsDT).w,(A1)               | save original ext/status handler
        MOVE.L  A0,(ExtStsDT).w                 | install our ext/status handler
| install VBL task for periodic AppleTalk housekeeping
        LEA.L   0x7C(A2),A0                     | A0 = VBL task record in ABusVars
        MOVE    #0x1,0x4(A0)                    | vblType = 1 (standard VBL)
        LEA.L   E_MPP_PRIME_CONT_12(PC),A1      | A1 = VBL task procedure
        MOVE.L  A1,0x6(A0)                      | store VBL proc address
        MOVE    #0x14,0xA(A0)                   | vblCount = 20 ticks (1/3 second)
        _VInstall                               | install VBL task
        BSR     E_MPP_OPEN_CONT_5               | initialize SCC for SDLC/LocalTalk
        MOVE    (Ticks_LoWord).w,0xAA(A2)       | seed PRNG with current tick count
        MOVE    (SP)+,SR                        | restore interrupt state
| acquire LocalTalk node address via AARP probing
        MOVE.B  (SPATalkB).w,D0                 | D0 = PRAM AppleTalk node hint
        BGT.B   E_MPP_OPEN_CONT                 | valid hint -> use it
E_MPP_OPEN_RETRY:
        BSR     RETURNS_5                       | generate random node address
E_MPP_OPEN_CONT:
        ANDI    #0x7F,D0                        | mask to valid range 1-127
        BEQ.B   E_MPP_OPEN_RETRY                | zero invalid, try again ->
| AARP probe: test if node address is in use (20 attempts)
        MOVEQ.L #0x13,D4                        | 20 probe attempts (19+1 via DBF)
        MOVE.B  D0,(A2)                         | tentative node ID -> ABusVars byte 0
        CLR.B   0xAD(A2)                        | clear "probe complete" flag
        MOVE.L  (SCCWr).w,A1                    | A1 = SCC write register base
        MOVE.B  #0x6,(A1)                       | SCC WR6 register select (SDLC addr)
        CLR.B   0xAF(A2)                        | clear collision-detected flag
        MOVE.B  (A2),(A1)                       | set SCC SDLC address to our node ID
E_MPP_OPEN_LOOP_2:
        ST.B    0xB0(A2)                        | set ENQ/ACK probe mode flag
        MOVE.B  (A2),D2                         | D2 = our tentative node ID
        BSR     E_MPP_OPEN_CONT_4               | send ENQ probe (LAP control frame)
E_MPP_OPEN_NO_3:
        TST.B   0xB0(A2)                        | probe response received?
        BNE.B   E_MPP_OPEN_NO_3                 | not yet, busy-wait ->
        TST.B   0xAF(A2)                        | collision detected (node in use)?
        BNE.B   E_MPP_OPEN_RETRY                | yes -> pick new random address
        DBF     D4,E_MPP_OPEN_LOOP_2            | repeat probe for reliability
| address acquired - save to PRAM
        MOVE.B  (A2),(SPATalkB).w               | store node ID in PRAM
        ST.B    0xAD(A2)                        | mark probe phase complete
        LEA.L   (SysParam_SPValid).w,A0         | A0 = parameter RAM validation
        MOVEQ.L #-0x1,D0                        | write all parameter RAM
        _WriteParam                             | save PRAM to disk/NVRAM
| install DDP receive handlers in socket handler table
        LEA.L   E_MPP_CONTROL_CONT_12(PC),A3    | A3 = short DDP receive handler
        LEA.L   0x36(A2),A0                     | A0 = after DDP handler table slot 1
        MOVE.L  A3,-(A0)                        | install short DDP handler (type 1)
        LEA.L   E_MPP_CONTROL_CONT_11(PC),A3    | A3 = extended DDP receive handler
        MOVE.L  A3,-(A0)                        | install extended DDP handler (type 2)
| register LAP types 1 and 2 for DDP short/extended frames
        LEA.L   0x26(A2),A0                     | A0 = past LAP type slots
        MOVE.B  #0x1,-(A0)                      | LAP type 1 = short DDP
        MOVE.B  #0x2,-(A0)                      | LAP type 2 = extended DDP
| install AARP handler and initialize NBP
        LEA.L   E_MPP_CONTROL_CONT_13(PC),A0    | A0 = AARP receive handler
        MOVE.L  A0,0x78(A2)                     | install as bridge protocol handler
        MOVE.B  #0x1,0x43(A2)                   | set socket 1 = DDP/NIS socket active
        BSR     E_MPP_OPEN_RETRY_2              | send AARP request for network number
| install DDP close handler and NBP close/reopen hook
        LEA.L   E_MPP_CONTROL_CONT_7(PC),A0     | A0 = DDP socket close procedure
        MOVE.L  A0,0x96(A2)                     | install in ABusVars
        LEA.L   E_MPP_OPEN_CONT_6(PC),A3        | A3 = NBP close/reopen hook
        MOVE.L  A3,0x8E(A2)                     | install close/reopen handler
| open .ATP driver
        SUBA    #0x32,SP                        | allocate IOParam on stack
        LEA.L   E_MPP_OPEN_CONT_3(PC),A0        | A0 = ".ATP" driver name string
        MOVE.L  A0,0x12(SP)                     | ioNamePtr = ".ATP"
        MOVE.L  A7,A0                           | A0 = IOParam pointer
        CLR.B   0x1B(A0)                        | ioPermssn = 0 (default)
        _Open                                   | open .ATP driver
        ADDA    #0x32,SP                        | pop IOParam from stack
        MOVEQ.L #0x7,D3                         | D3 = 7 (NBP dispatch entry point)
        BSR     E_MPP_CONTROL_CONT_4            | install NBP handler, dispatch
        TST     0x1A(A2)                        | network number acquired?
        BNE.B   E_MPP_OPEN_OK                   | yes ->
        BSR.B   E_MPP_OPEN_RETRY_2              | retry AARP network number request
E_MPP_OPEN_OK:
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE pointer
        MOVE.B  #0x13,0x7(A1)                   | set DCE flags (open, time, goodbye)
        MOVEQ.L #0x0,D0                         | noErr: MPP open succeeded
        RTS                                     | return to Device Manager

| ----------------------------------------------------------
|
| E_MPP_OPEN_RETRY_2: send AARP request to learn our network number
| Builds AARP packet on stack, transmits via LAP, waits for response
|
E_MPP_OPEN_RETRY_2:
        CLR     -(SP)                           | push terminator (end of data list)
        SUBQ.W  #0x4,SP                         | reserve space for data pointer
        MOVE    #0x9,-(SP)                      | push AARP data length (9 bytes)
        MOVE.L  A7,A1                           | A1 = start of data list on stack
        MOVE    #0x501,-(SP)                    | AARP: protocol type + opcode
        MOVE    #0x101,-(SP)                    | AARP: hw addr len + proto addr len
        MOVE    #0x6,-(SP)                      | AARP: protocol type (6 = AARP)
        MOVE    #0x1,-(SP)                      | AARP: hardware type (1 = LocalTalk)
        ST.B    D2                              | D2 = $FF (broadcast destination)
        MOVE    D2,-(SP)                        | push broadcast + padding
        LEA.L   0x1(SP),A3                      | A3 = AARP packet data start
        MOVE.L  A3,0xB(A3)                      | store data pointer in data list
        BSR.B   E_MPP_OPEN_CONT_2               | transmit AARP request frame
E_MPP_OPEN_NO_4:
        TST.B   0xB0(A2)                        | response received yet?
        BEQ.B   E_MPP_OPEN_NO_4                 | no, busy-wait ->
        ADDA    #0x12,SP                        | pop AARP packet from stack
        RTS                                     | return with network info in ABusVars

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_2: transmit and set completion flag
|
E_MPP_OPEN_CONT_2:
        BSR     E_MPP_PRIME_CONT                | transmit LAP frame
        ST.B    0xB0(A2)                        | set transmit-complete flag
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_3
|
E_MPP_OPEN_CONT_3:
  .byte  0x04,0x2E,0x41,0x54,0x50,0x20          | ".ATP " (4 chars + space padding)
| E_MPP_OPEN_CONT_4: transmit ENQ probe and clear completion flag (async wait)
E_MPP_OPEN_CONT_4:
        BSR     E_MPP_PRIME_CONT_2              | set up transmit with backoff
        CLR.B   0xB0(A2)                        | clear completion flag (wait for ACK)
        RTS                                     | return (caller busy-waits on flag)

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_5: initialize SCC for SDLC/LocalTalk mode
| Programs SCC with two register tables (E_MPP_OPEN_INIT_TBL + E_MPP_OPEN_INIT_TBL_2)
|
E_MPP_OPEN_CONT_5:
        LEA.L   E_MPP_OPEN_INIT_TBL(PC),A0      | A0 = primary SCC init table
        BSR     E_MPP_CLOSE_CONT                | program SCC registers
        LEA.L   E_MPP_OPEN_INIT_TBL_2(PC),A0    | A0 = secondary SCC init table
        BRA     E_MPP_CLOSE_CONT                | program remaining registers

| ----------------------------------------------------------
|
| E_MPP_OPEN_INIT_TBL
|
E_MPP_OPEN_INIT_TBL:
  .byte  0x40,0x09,0x20,0x04,0xE0,0x0A          | SCC: WR9 reset, WR4 SDLC, WR10 FM0
  .byte 0x00,0x06,0x7E,0x07,0x06,0x0C           | WR6=0x00 sync, WR7=0x7E flag, WR12 baud lo
  .byte 0x00,0x0D,0xC0,0x0E,0xDD,0x03           | WR13 baud hi, WR14 DPLL, WR3 Rx 8-bit
  .byte 0x00,0x02,0x08,0x0F,0x09,0x01           | WR2 intvec, WR15 DCD IE, WR1 Rx int
  .byte 0x0A,0x09,0x00,0x00                     | WR10 FM0, WR9 MIE, terminator
| Serial driver SCC register initialization templates
| Loaded via LEA and copied to SCC hardware registers
E_MPP_OPEN_INIT_TBL_2:
  .byte 0x70,0x0B,0x21,0x0E,0x60,0x05           | SCC: WR11 Rx/Tx clk, WR14 BRG en, WR5 Tx
  .byte 0x00,0x00                               | terminator (end of E_MPP_OPEN_INIT_TBL_2)
CONFIG_TBL:
  .byte 0x05,0x60,0x0E,0x41,0x03,0xDD           | SCC: WR5 Tx enable, WR14 DPLL, WR3 Rx en
  .byte 0x21,0x00,0x46,0x00                     | WR1 ext int, terminator pair
  .ascii "COPYRIGHT (C) APPLE COMPUTER"         | embedded copyright notice
E_MPP_OPEN_CONT_6:
        BRA.B   E_MPP_OPEN_CONT_9               | -> NBP close/reopen handler

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_7: NBP KillNBP - cancel pending NBP operations
|
E_MPP_OPEN_CONT_7:
        BRA.B   E_MPP_OPEN_CONT_10              | -> walk and cancel NBP queue

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_8: handle incoming AARP/ZIP packet on NIS socket
| Checks if network number changed, sends WriteDDP to update router
|
E_MPP_OPEN_CONT_8:
        MOVE.L  0x9E(A2),A3                     | A3 = NIS (Names Info Socket) buffer
        TST     (A3)+                           | NIS packet pending?
        BNE.B   E_MPP_OPEN_OK_2                 | yes, flush remaining data ->
        MOVEQ.L #0x7C,D3                        | read 124 bytes of NIS data
        JSR     0x2(A4)                         | receive data from SCC
        BNE.B   E_MPP_OPEN_ERR                  | receive error ->
        MOVE.L  0x9E(A2),A0                     | A0 = NIS buffer
        MOVE.B  0x6(A0),D0                      | D0 = sender node ID from packet
        CMP.B   (A2),D0                         | same as our node?
        BNE.B   E_MPP_OPEN_NO_5                 | no -> network info changed
        MOVE    0x4(A0),D0                      | D0 = network number from packet
        CMP     0x1A(A2),D0                     | same as our network?
        BEQ.B   E_MPP_OPEN_ERR                  | yes, nothing to do ->
| network info changed - send update via WriteDDP control call
E_MPP_OPEN_NO_5:
        MOVE    #0xF2,(A0)                      | csCode for WriteDDP (242+16=258?)
        SUBA    #0x1A,A0                        | back up to IOParam start
        LEA.L   E_MPP_OPEN_CONT_15(PC),A1       | A1 = completion routine
        MOVE.L  A1,0xC(A0)                      | ioCompletion = E_MPP_OPEN_CONT_15
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE
        MOVE    0x18(A1),0x18(A0)               | copy ioRefNum from DCE
        _ControlAsync                           | issue async control call
E_MPP_OPEN_ERR:
        RTS                                     | return to receive handler

| ----------------------------------------------------------
|
| E_MPP_OPEN_OK_2: NIS packet already pending - flush SCC receive data
|
E_MPP_OPEN_OK_2:
        CLR     D3                              | D3 = 0 (no bytes to store)
        JMP     0x2(A4)                         | -> flush remaining SCC data

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_9: NBP close/reopen hook entry
|
E_MPP_OPEN_CONT_9:
        BRA.B   E_MPP_OPEN_CONT_11              | -> process pending NBP operations

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_10: KillNBP - walk NBP name list, remove out-of-zone entries
|
E_MPP_OPEN_CONT_10:
        LEA.L   0x9A(A2),A3                     | A3 = head of NBP name list
        MOVE.L  (SysZone).w,A0                  | A0 = system zone header
E_MPP_OPEN_NEXT:
        MOVE.L  (A3),D1                         | D1 = next entry link
        BEQ.B   E_MPP_OPEN_EMPTY                | null = end of list ->
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit address
        MOVE.L  D1,A1                           | A1 = entry pointer
        CMPA.L  (A0),A1                         | entry within system zone?
        BCS     E_MPP_OPEN_OK_3                 | yes, keep it ->
        MOVE.L  (A1),(A3)                       | unlink stale entry from list
        BRA.B   E_MPP_OPEN_NEXT                 | -> check next

| ----------------------------------------------------------
|
| E_MPP_OPEN_OK_3: valid entry - advance scan pointer
|
E_MPP_OPEN_OK_3:
        MOVE.L  A1,A3                           | advance to this entry
        BRA.B   E_MPP_OPEN_NEXT                 | -> check next

| ----------------------------------------------------------
|
| E_MPP_OPEN_EMPTY: end of NBP name list walk
|
E_MPP_OPEN_EMPTY:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_11: NBP Lookup - search registered names for matches
| Called from close/reopen hook when NBP requests are pending
|
E_MPP_OPEN_CONT_11:
        MOVE.L  0x9A(A2),D2                     | D2 = first NBP name entry
        BEQ     E_MPP_OPEN_DONE                 | no entries -> done
        MOVE    SR,-(SP)                        | save SR
        MOVE    0x1C(A2),SR                     | set IPL from ABusVars
        MOVEM.L A2/A4-A5,-(SP)                  | save registers
        MOVE.L  A0,A4                           | A4 = IOParam / lookup request
        MOVE    E_MPP_OPEN_CONT_14(PC),D0       | D0 = _CmpString trap number ($A03C)
        _GetTrapAddress                         | A0 = address of _CmpString
        MOVE.L  A0,A2                           | A2 = _CmpString entry point
        CLR     D3                              | D3 = match counter
| E_MPP_OPEN_CONT_12: scan NBP name list for matches against lookup request
E_MPP_OPEN_CONT_12:
        MOVE.L  D2,A3                           | A3 = current NBP entry
        ADDA    #0x9,A3                         | skip entry header (9 bytes)
        LEA.L   0x23(A4),A5                     | A5 = lookup name in request
        MOVE.L  A3,A1                           | A1 = registered name (for compare)
        MOVE.L  A5,A0                           | A0 = lookup pattern (for compare)
        CMPI.B  #0x3D,0x1(A5)                   | lookup object = '=' (wildcard)?
        BEQ.B   E_MPP_OPEN_FOUND                | yes, matches any name ->
        BSR     RETURNS_8                       | compare object names via _CmpString
        BNE.B   E_MPP_OPEN_FOUND_3              | no match ->
| E_MPP_OPEN_FOUND: object matches - compare type strings
E_MPP_OPEN_FOUND:
        CLR     D0                              | clear high byte
        MOVE.B  (A5)+,D0                        | D0 = lookup object length
        ADDA    D0,A5                           | skip past lookup object string
        MOVE.L  A3,A1                           | A1 = registered name
        MOVE.B  (A1)+,D0                        | D0 = registered object length
        ADDA    D0,A1                           | skip past registered object string
        MOVE.L  A5,A0                           | A0 = lookup type string
        CMPI.B  #0x3D,0x1(A5)                   | lookup type = '=' (wildcard)?
        BEQ.B   E_MPP_OPEN_FOUND_2              | yes, matches any type ->
        BSR     RETURNS_8                       | compare type strings
        BNE.B   E_MPP_OPEN_FOUND_3              | no match ->
| E_MPP_OPEN_FOUND_2: both object and type match - record this entry
E_MPP_OPEN_FOUND_2:
        MOVE.L  A3,-(SP)                        | push matched entry pointer
        ADDQ.W  #0x1,D3                         | increment match count
| E_MPP_OPEN_FOUND_3: advance to next NBP entry in linked list
E_MPP_OPEN_FOUND_3:
        MOVE.L  -0x9(A3),D2                     | D2 = next entry link
        BNE.B   E_MPP_OPEN_CONT_12              | more entries ->
        TST     D3                              | any matches found?
        BEQ     E_MPP_OPEN_FOUND_4              | no matches -> clean up
| build NBP LkUp reply packet from request parameters
        LEA.L   0x1F(A4),A1                     | A1 = reply packet header area
        LEA.L   0x1E(A4),A5                     | A5 = request parameters
        MOVE    (A5)+,0x7(A1)                   | copy dest network number
        MOVE.B  (A5)+,0xB(A1)                   | copy dest node ID
        MOVE.B  (A5)+,0xD(A1)                   | copy dest socket number
        MOVE.B  #0x2,0xF(A1)                    | NBP function = 2 (LkUp-Reply)
        MOVE.L  A1,0x32(A4)                     | store reply header pointer
        MOVE.L  (ABusVars).w,A2                 | reload A2 = ABusVars
| E_MPP_OPEN_NEXT_2: build data chunk list for NBP reply packet
E_MPP_OPEN_NEXT_2:
        MOVE.B  0x1E(A4),0x26(A4)               | copy NBP ID to reply
        CLR     D2                              | D2 = accumulated data length
        CLR     D1                              | D1 = tuples packed in this packet
        LEA.L   0x36(A4),A3                     | A3 = data chunk list builder
        LEA.L   0x1C(A4),A1                     | A1 = NBP header data area
        MOVE    #0x2,(A3)+                      | first chunk = 2-byte NBP header
        MOVE.L  A1,(A3)+                        | pointer to NBP header
| E_MPP_OPEN_NEXT_3: pack matched NBP name tuples into reply data list
E_MPP_OPEN_NEXT_3:
        MOVE.L  (SP),A5                         | A5 = next matched entry (from stack)
        CLR     D0                              | clear high byte
        MOVE.B  (A5),D0                         | D0 = object name length
        ADD.B   0x1(A5,D0.W),D0                 | add type name length
        MOVE.B  #0x1,0x2(A5,D0.W)               | zone name length = 1 ('*')
        MOVE.B  #0x2A,0x3(A5,D0.W)              | zone name = '*' (this zone)
        ADDI    #0x9,D0                         | add 9-byte tuple header
        ADD     D0,D2                           | accumulate total data size
        CMPI    #0x248,D2                       | packet too full (> 584 bytes)?
        BGE.B   E_MPP_OPEN_OK_4                 | yes, send what we have ->
        ADDQ.W  #0x4,SP                         | pop this entry's pointer
        MOVE    D0,(A3)+                        | store tuple chunk length
        SUBQ.W  #0x5,A5                         | back up to tuple address header
        MOVE.L  A5,(A3)+                        | store tuple data pointer
        MOVE    0x1A(A2),(A5)                   | fill in our network number
        ADDQ.W  #0x1,D1                         | count tuples in this packet
        SUBQ.W  #0x1,D3                         | decrement remaining matches
        BEQ.B   E_MPP_OPEN_OK_4                 | no more -> send packet
        CMPI    #0xF,D1                         | max 15 tuples per NBP packet?
        BNE.B   E_MPP_OPEN_NEXT_3               | room for more -> pack next
| E_MPP_OPEN_OK_4: finalize and send NBP reply packet
E_MPP_OPEN_OK_4:
        CLR     (A3)+                           | terminate data chunk list
        ORI     #0x30,D1                        | merge tuple count into NBP func byte
        MOVE.B  D1,(A1)                         | store NBP function + count
        MOVE    D3,A5                           | A5 = remaining match count
        CLR.B   0x2F(A4)                        | clear transmit-done flag
        BSR.B   E_MPP_OPEN_CONT_13              | send NBP reply via WriteDDP
E_MPP_OPEN_NO_6:
        TST.B   0x2F(A4)                        | transmit complete?
        BEQ.B   E_MPP_OPEN_NO_6                 | not yet, busy-wait ->
        MOVE    A5,D3                           | D3 = remaining matches
        BNE.B   E_MPP_OPEN_NEXT_2               | more to send -> build next packet
| E_MPP_OPEN_FOUND_4: all replies sent - restore registers
E_MPP_OPEN_FOUND_4:
        MOVEM.L (SP)+,A2/A4-A5                  | restore saved registers
        MOVE    (SP)+,SR                        | restore interrupt state
| E_MPP_OPEN_DONE: IODone - complete the control call
E_MPP_OPEN_DONE:
        MOVE.L  (JIODone).w,A0                  | A0 = JIODone vector
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE
        JMP     (A0)                            | -> IODone completion

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_13: send NBP reply packet via DDP socket close procedure
|
E_MPP_OPEN_CONT_13:
        MOVEQ.L #0x2,D1                         | D1 = DDP type 2 (NBP)
        LEA.L   0x30(A4),A1                     | A1 = reply data chunk list
        MOVE.L  0x96(A2),A0                     | A0 = DDP close/send procedure
        CLR.B   D3                              | D3 = 0 (no socket listener)
        JSR     (A0)                            | send DDP packet
        MOVE.L  0x9E(A2),A0                     | A0 = NIS buffer
        ST.B    0x15(A0)                        | set NIS transmit-complete flag
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_14 - _InitResources trap word ($A03C), used as inline constant
|
E_MPP_OPEN_CONT_14:
  .byte 0xA0,0x3C                               | _InitResources trap word ($A03C)
| RETURNS_8: compare two Pascal strings using _CmpString
| A0 = string 1 (length byte + chars), A1 = string 2
| Returns: Z=1 if equal
RETURNS_8:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0)+,D0                        | D0.low = string 1 length
        SWAP    D0                              | move to high word
        MOVE.B  (A1)+,D0                        | D0.low = string 2 length
        JSR     (A2)                            | call _CmpString (address in A2)
        TST     D0                              | set Z flag from result
        RTS                                     | Z=1 if strings match

| ----------------------------------------------------------
|
| E_MPP_OPEN_CONT_15: WriteDDP completion routine - clear ioResult
|
E_MPP_OPEN_CONT_15:
        CLR     0x1A(A0)                        | ioResult = noErr
        RTS                                     | return from completion

| ----------------------------------------------------------
|
| E_MPP_OPEN_DISPATCH_TBL: NBP csCode dispatcher
| D3 = csCode - 242 (from main dispatch). NBP ops are 7-13 (Register..KillNBP)
|
E_MPP_OPEN_DISPATCH_TBL:
        SUBQ.W  #0x7,D3                         | adjust D3: 7->0, 8->1, etc.
        BMI.B   E_MPP_OPEN_NO_7                 | < 7: not NBP -> call DDP handler
        ADD     D3,D3                           | word offset into jump table
        LEA.L   JUMP_TBL(PC),A3                 | A3 = NBP jump table
        ADDA    D3,A3                           | index into table
        MOVE    (A3),D3                         | D3 = relative offset from E_MPP_OPEN_DISPATCH_TBL
        LEA.L   E_MPP_OPEN_DISPATCH_TBL(PC),A3  | A3 = base address
        ADDA    D3,A3                           | A3 = absolute handler address
        MOVE.L  A3,-(SP)                        | push handler address for RTS dispatch
        MOVE.L  0x92(A2),A3                     | A3 = NBP state block
        RTS                                     | dispatch to handler via RTS

| Jump Table
JUMP_TBL:
  .byte  0x00,0x44,0x00,0x82,0x01,0x7C          | Register=+68, Lookup=+130, Remove=+380
  .byte 0x01,0x20,0x00,0x8A,0x02,0x62           | Confirm=+288, KillNBP=+138, closehook=+610
  .byte 0x00,0x2E                               | NBPcompletion=+46
E_MPP_OPEN_NO_7:
        MOVE.L  0x92(A2),A3                     | A3 = NBP state block
E_MPP_OPEN_CONT_16:
        BRA     E_1056_LOOP_DONE_2              | -> complete with noErr
| Dead code - unreachable subroutine left from earlier ROM version.
| Searches for D0 byte in 14-byte table at 0x36(A2), clears if found.
        MOVEQ.L #0xD,D2                         | D2 = 13 (max socket index)
E_1056_LOOP:
        CMP.B   0x36(A2,D2.W),D0                | socket number match?
        DBEQ    D2,E_1056_LOOP                  | loop until match or done
        .short 0x6604                           | BNE.B *+6 (skip CLR+RTS)
        CLR.B   0x36(A2,D2.W)                   | clear socket slot
        RTS                                     | return
| E_1056_LOOP_CONT: initialize NBP state block - allocate and configure
E_1056_LOOP_CONT:
        MOVEQ.L #0x47,D0                        | 71 bytes for NBP state block
        BSR.B   E_1056_LOOP_CONT_2              | allocate in system heap
        BNE.B   E_1056_LOOP_ERR                 | alloc failed ->
        MOVE    #0x1,0x8(A0)                    | VBL vblType = 1
        LEA.L   E_1056_LOOP_CONT_9(PC),A1       | A1 = NBP VBL task procedure
        MOVE.L  A1,0xA(A0)                      | store VBL proc address
        LEA.L   E_1056_LOOP_CONT_11(PC),A1      | A1 = NBP DDP receive handler
        MOVE.L  0x96(A2),A3                     | A3 = DDP close/send procedure
        CLR     D1                              | D1 = 0 (no specific socket)
        JSR     PORTBITS(A3)                    | open DDP socket for NBP
        TST     D0                              | socket opened successfully?
        BNE.B   E_1056_LOOP_ERR_2               | no -> free memory and return error
        MOVE.B  D1,(A0)                         | store assigned socket number
        MOVE.L  A0,0x92(A2)                     | install NBP state block in ABusVars
E_1056_LOOP_ERR:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| E_1056_LOOP_ERR_2: NBP init failed - free state block, return error
|
E_1056_LOOP_ERR_2:
        MOVE    D0,D1                           | save error code
        _DisposePtr                             | free the allocated block
        MOVE    D1,D0                           | restore error code
        RTS                                     | return error to caller

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_2: allocate D0 bytes of zeroed system heap memory
|
E_1056_LOOP_CONT_2:
        _NewPtrSysClear                         | allocate zeroed pointer in sys heap
        BRA.B   E_1056_LOOP_SKIP                | skip over inline trap word
  .byte 0xA3,0x1E                               | _NewPtrSysClear (dead trap word)
E_1056_LOOP_SKIP:
        RTS                                     | return with A0=pointer, D0=error

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_3: NBP Lookup - initiate name lookup request
| csParam+0x22 = target address for lookup
|
E_1056_LOOP_CONT_3:
        MOVE.L  0x22(A0),D2                     | D2 = target network:node for lookup
        BRA     E_1056_LOOP_CONT_8              | -> build and send NBP LkUp packet

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_4: NBP Register - register a name on the network
| A0 = IOParam, A1+9 = name entity to register
|
E_1056_LOOP_CONT_4:
        MOVE.L  A0,D3                           | D3 = save IOParam pointer
        TST.L   0x8E(A2)                        | close/reopen handler installed?
        BMI.B   E_1056_LOOP_OK_2                | yes, already initialized ->
| first-time NBP registration: allocate NIS buffer and open socket
        NOP                                     | alignment padding
        MOVE.L  #0x98,D0                        | 152 bytes for NIS state buffer
        BSET    #0x7,0x8E(A2)                   | mark handler as being set up
        BSR.B   E_1056_LOOP_CONT_2              | allocate zeroed system memory
        BNE.B   E_1056_LOOP_ERR_3               | alloc failed -> error
        ADDA    #0x1A,A0                        | skip IOParam header area
        MOVE.L  A0,0x9E(A2)                     | store NIS buffer pointer
        MOVEM.L D1/A1/A3,-(SP)                  | save registers
        MOVEQ.L #0x2,D1                         | D1 = DDP type 2 (NBP socket)
        MOVE.L  0x8E(A2),A1                     | A1 = close/reopen handler block
        ADDQ.W  #0x4,A1                         | point to socket data area
        MOVE.L  0x96(A2),A3                     | A3 = DDP close/send procedure
        JSR     PORTBITS(A3)                    | open NBP socket
        MOVEM.L (SP)+,D1/A1/A3                  | restore registers
        TST     D0                              | socket opened?
        BEQ.B   E_1056_LOOP_OK                  | yes ->
        MOVE    #-0x405,D0                      | nbpNISErr: NIS socket open failed
        BRA.B   E_1056_LOOP_ERR_3               | -> error exit

| ----------------------------------------------------------
|
| E_1056_LOOP_OK: NIS socket opened - proceed with name registration
|
E_1056_LOOP_OK:
        BSet    #0x7,0x8E(A2)                   | mark close/reopen handler valid
        MOVE.L  D3,A0                           | restore IOParam pointer
| E_1056_LOOP_OK_2: check if name is already registered
E_1056_LOOP_OK_2:
        TST.B   0x22(A0)                        | async flag set?
        BEQ.B   E_1056_LOOP_NO                  | no -> register as new name
        ADDA    #0x9,A1                         | A1 points to name entity (skip header)
        BSR.B   E_1056_LOOP_CONT_6              | search for existing registration
        BEQ     E_1056_LOOP_FOUND               | found -> update existing entry
        MOVE    #-0x403,D0                      | nbpNotFound: name not registered
E_1056_LOOP_ERR_3:
        BRA     E_1056_LOOP_ERR_4               | -> error/cleanup exit

| ----------------------------------------------------------
|
| E_1056_LOOP_NO
|
E_1056_LOOP_NO:
        CLR     D2                              | clear ID counter
        MOVE.B  0x7(A1),D1                      | D1 = target socket number
E_1056_LOOP_NEXT:
        ADDQ.W  #0x1,D2                         | increment ID counter
        LEA.L   0x9A(A2),A0                     | A0 = names table list head
E_1056_LOOP_NEXT_2:
        TST.L   (A0)                            | end of list?
        BEQ.B   E_1056_LOOP_OK_3                | yes -> append it
        MOVE.L  (A0),A0                         | A0 = next entry
        CMP.B   0x7(A0),D1                      | socket match?
        BNE.B   E_1056_LOOP_NEXT_2              | no -> check next
        TST.B   D2                              | checking ID?
        BEQ.B   E_1056_LOOP_NEXT_2              | no -> check next
        CMP.B   0x8(A0),D2                      | ID match?
        BEQ.B   E_1056_LOOP_NEXT                | yes -> collision, try next ID
        BRA.B   E_1056_LOOP_NEXT_2              | no -> check next entry

| ----------------------------------------------------------
|
| E_1056_LOOP_OK_3
|
E_1056_LOOP_OK_3:
        MOVE.B  (A2),0x6(A1)                    | store node ID in entry
        MOVE.B  D2,0x8(A1)                      | store assigned ID in entry
        CLR.L   (A1)                            | clear next pointer
        MOVE.L  A1,(A0)                         | append entry to list
        BRA.B   E_1056_LOOP_DONE                | done

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_5
|
E_1056_LOOP_CONT_5:
        MOVE    #-0x404,D0                      | D0 = nbpNotFound
        BSR.B   E_1056_LOOP_CONT_6              | find entry in list
        BEQ.B   E_1056_LOOP_ERR_3               | not found -> error
        MOVE    SR,-(SP)                        | save interrupt state
        MOVE    #0x2600,SR                      | disable interrupts
        LEA.L   0x9A(A2),A0                     | A0 = list head
E_1056_LOOP_LOOP:
        CMP.L   (A0),D3                         | is this the target entry?
        BEQ.B   E_1056_LOOP_OK_4                | yes ->
        MOVE.L  (A0),A0                         | next entry
        BRA.B   E_1056_LOOP_LOOP                | loop

| ----------------------------------------------------------
|
| E_1056_LOOP_OK_4
|
E_1056_LOOP_OK_4:
        MOVE.L  D3,A1                           | A1 = entry to remove
        MOVE.L  (A1),(A0)                       | bypass entry in linked list
        MOVE    (SP)+,SR                        | restore interrupts
E_1056_LOOP_DONE:
        BRA     E_1056_LOOP_DONE_2              | complete with noErr

| E_1056_LOOP_CONT_6 -- search for existing registration.
| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_6
|
E_1056_LOOP_CONT_6:
        MOVEM.L D0-D1/A0-A3,-(SP)               | save registers
        MOVE.L  A1,A3                           | A3 = target string
        LEA.L   0x9A(A2),A2                     | A2 = list head
        CLR.L   D3                              | D3 = 0 (not found flag)
E_1056_LOOP_LOOP_2:
        TST.L   (A2)                            | end of list?
        BEQ.B   E_1056_LOOP_EXIT                | yes -> return
        CLR     D0                              | clear D0
        MOVE.B  (A3),D0                         | D0 = string 1 length
        ADD.B   0x1(A3,D0.W),D0                 | add string 2 length
        ADDQ.W  #0x2,D0                         | add length bytes
        MOVE    D0,D1                           | copy length
        SWAP    D0                              | length in high word for CmpString
        MOVE    D1,D0                           | length in both halves
        MOVE.L  (A2),A2                         | next entry
        MOVE.L  A2,A1                           | A1 = entry
        ADDA    #0x9,A1                         | A1 = string pointer in entry
        MOVE.L  A3,A0                           | A0 = target string
        _CmpString                              | compare entity name strings
        TST     D0                              | match?
        BNE.B   E_1056_LOOP_LOOP_2              | no -> loop
        MOVE.L  A2,D3                           | D3 = found entry
E_1056_LOOP_EXIT:
        MOVEM.L (SP)+,D0-D1/A0-A3               | restore registers
        RTS                                     | return

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_7
|
E_1056_LOOP_CONT_7:
        CLR     0x2A(A0)                        | clear matched names count
        MOVE.L  0x22(A0),0x16(A3)               | set buffer pointer
        MOVE    0x26(A0),0x1A(A3)               | set buffer size
E_1056_LOOP_FOUND:
        CLR.L   D2                              | D2 = 0
E_1056_LOOP_CONT_8:
        MOVEQ.L #0x21,D3                        | D3 = broadcast socket
        LSR     #0x8,D2                         | shift ID
        BNE.B   E_1056_LOOP_EMPTY               | not zero ->
        ST.B    D2                              | D2 = 0xFF (broadcast)
        MOVE.B  0x19(A2),D0                     | get bridge node
        BEQ.B   E_1056_LOOP_EMPTY               | no bridge ->
        MOVEQ.L #0x11,D3                        | send to bridge (socket 0x11)
        MOVE.B  D0,D2                           | D2 = bridge node ID
E_1056_LOOP_EMPTY:
        MOVE.L  A0,0x12(A3)                     | store param block
        SWAP    D2                              | prepare node ID
        MOVE    D2,PORTBITS(A3)                 | set port bits
        LEA.L   0x4(A3),A0                      | A0 = VBL task
        LSL     #0x3,D1                         | convert to ticks
        ANDI    #0x3FF,D1                       | mask max ticks
        MOVE    D1,0xA(A0)                      | set vblCount
        _VInstall                               | install NBP retry VBL task
        MOVE.L  A1,D0                           | save string ptr
        LEA.L   0x1E(A3),A1                     | A1 = write data header
        LEA.L   0x37(A3),A0                     | A0 = DDP header
        MOVE.L  A0,(A1)+                        | set header ptr
        MOVE.B  #0x2,0xD(A0)                    | set DDP type (NBP)
        MOVE    D2,0x7(A0)                      | set dest network
        SWAP    D2                              | get node ID
        MOVE.B  D2,0xB(A0)                      | set dest node
        MOVE.B  #0x2,0xF(A0)                    | set dest socket (NBP)
        MOVE    #0x7,(A1)+                      | set header length
        LEA.L   PNLOC(A3),A0                    | A0 = NBP tuple
        MOVE.L  A0,(A1)+                        | set tuple ptr
        MOVE.B  D3,(A0)+                        | set tuple function/count
        ADDQ.B  #0x1,0x1(A3)                    | increment NBP ID
        MOVE.B  0x1(A3),(A0)+                   | set NBP ID
        MOVE    0x1A(A2),(A0)+                  | set tuple network
        MOVE.B  (A2),(A0)+                      | set tuple node
        MOVE.B  (A3),D1                         | set tuple socket
        MOVE.B  D1,(A0)                         | set tuple socket
        MOVE.L  D0,A0                           | restore string ptr
        CLR     D2                              | clear D2
        MOVE.B  (A0),D2                         | get string 1 len
        ADD.B   0x1(A0,D2.W),D2                 | add string 2 len
        ADD.B   0x2(A0,D2.W),D2                 | add string 3 len
        ADDQ.B  #0x3,D2                         | add length bytes
        MOVE    D2,(A1)+                        | set tuple length
        MOVE.L  A0,(A1)+                        | set string ptr
        CLR     (A1)                            | clear next ptr
E_1056_LOOP_RETRY:
        LEA.L   CLIPRGN(A3),A1                  | A1 = MPP param block
        MOVE.L  0x96(A2),A0                     | A0 = writeLAP entry
        CLR.B   D3                              | D3 = 0
        JSR     (A0)                            | call writeLAP
        RTS                                     | return

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_9
|
E_1056_LOOP_CONT_9:
        MOVE.L  (ABusVars).w,A2                 | get AppleTalk vars
        MOVE.L  0x92(A2),A3                     | A3 = NBP state block
        MOVE.L  0x12(A3),A1                     | A1 = MPP param block
        SUBQ.B  #0x1,0x1D(A1)                   | decrement retry count
        BEQ.B   E_1056_LOOP_CONT_10             | retries exhausted ->
        CLR     D0                              | clear D0
        MOVE.B  0x1C(A1),D0                     | D0 = retry interval
        LSL     #0x3,D0                         | convert to ticks
        MOVE    D0,0xA(A0)                      | reset VBL timer
        MOVE    PORTBITS(A3),0x3E(A3)           | reset node ID
        MOVE.B  (A3),D1                         | D1 = socket
        BRA.B   E_1056_LOOP_RETRY               | -> send packet again

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_10
|
E_1056_LOOP_CONT_10:
        MOVE    0x1A(A1),D0                     | D0 = tuple function
        MOVE.L  0x1E(A1),A1                     | A1 = string ptr
        CMPI    #0xFD,D0                        | lookup?
        BEQ     E_1056_LOOP_NO                  | yes ->
        CMPI    #0xFA,D0                        | confirm?
        BNE.B   E_1056_LOOP_DONE_2              | no -> return
        MOVE    #-0x401,D0                      | D0 = nbpConfDiff
        BRA.B   E_1056_LOOP_ERR_4               | -> finish

| ----------------------------------------------------------
|
| E_1056_LOOP_DONE_2
|
E_1056_LOOP_DONE_2:
        CLR     D0                              | D0 = noErr
E_1056_LOOP_ERR_4:
        MOVE    D0,D1                           | save error code
        LEA.L   0x4(A3),A0                      | A0 = VBL task
        _VRemove                                | remove NBP retry VBL task
        MOVE    D1,D0                           | restore error code
        CLR.L   0x12(A3)                        | clear active request
        MOVE.L  (ABusVars_dce).w,A1             | A1 = DCE
        MOVE.L  (JIODone).w,A0                  | A0 = JIODone vector
        JMP     (A0)                            | -> IODone

| ----------------------------------------------------------
|
| E_1056_LOOP_NO_2
|
E_1056_LOOP_NO_2:
        CMPI    #0xFD,0x1A(A5)                  | is it a lookup?
        BEQ.B   E_1056_LOOP_OK_5                | yes ->
        MOVEQ.L #0x4,D3                         | D3 = read 4 bytes
        JSR     0x2(A4)                         | call ReadRest
        BNE.B   E_1056_LOOP_ERR_5               | error -> return
        MOVE.B  -(A3),D2                        | get node ID from packet
        MOVE.L  0x92(A2),A3                     | A3 = NBP state
        MOVE.L  0x12(A3),A1                     | A1 = param block
        MOVE.B  D2,0x26(A1)                     | save node ID
        CMP.B   0x25(A1),D2                     | confirm match?
        BEQ.B   E_1056_LOOP_DONE_2              | yes -> success
        MOVE    #-0x402,D0                      | D0 = nbpConfDiff
        BRA.B   E_1056_LOOP_ERR_4               | -> finish

| ----------------------------------------------------------
|
| E_1056_LOOP_OK_5
|
E_1056_LOOP_OK_5:
        JSR     0x2(A4)                         | call ReadRest
        BNE.B   E_1056_LOOP_ERR_5               | error -> return
        MOVE.L  0x92(A2),A3                     | A3 = NBP state
        MOVE    #-0x403,D0                      | D0 = nbpDuplicate
        BRA.B   E_1056_LOOP_ERR_4               | -> finish

| ----------------------------------------------------------
|
| E_1056_LOOP_ERR_5
|
E_1056_LOOP_ERR_5:
        RTS                                     | return

| ----------------------------------------------------------
|
| E_1056_LOOP_NO_3
|
E_1056_LOOP_NO_3:
        CLR     D3                              | flush remaining bytes
        JMP     0x2(A4)                         | -> ReadRest

| ----------------------------------------------------------
|
| E_1056_LOOP_CONT_11
|
E_1056_LOOP_CONT_11:
        MOVEQ.L #0x2,D3                         | D3 = read 2 bytes
        JSR     (A4)                            | call ReadPacket
        BNE.B   E_1056_LOOP_ERR_5               | error -> return
        MOVE.L  0x92(A2),A5                     | A5 = NBP state
        MOVE.L  0x12(A5),D0                     | D0 = active request
        BEQ.B   E_1056_LOOP_NO_3                | no request -> flush
        MOVE.B  -(A3),D2                        | get NBP ID
        CMP.B   0x1(A5),D2                      | match expected ID?
        BNE.B   E_1056_LOOP_NO_3                | no -> flush
        MOVE.B  -(A3),D2                        | get function/tuple count
        EXG     D0,A5                           | A5 = param block, D0 = NBP state
        CMPI    #0xFB,0x1A(A5)                  | is it a lookup reply?
        BNE.B   E_1056_LOOP_NO_2                | no -> handle confirm/register
        MOVE.L  D0,A5                           | A5 = NBP state
        MOVE.L  0x16(A5),A3                     | A3 = reply buffer
        MOVE    0x1A(A5),D3                     | D3 = buffer size
        JSR     0x2(A4)                         | call ReadRest into buffer
        BNE.B   E_1056_LOOP_ERR_5               | error -> return
        SUBI.B  #0x30,D2                        | subtract NBP reply base
        BLE.B   E_1056_LOOP_ERR_5               | <= 0 -> ignore
        CMPI.B  #0xF,D2                         | > 15 tuples?
        BGT.B   E_1056_LOOP_ERR_5               | yes -> ignore
        MOVE.L  A3,D1                           | D1 = end of read data
        MOVE.L  0x92(A2),A3                     | A3 = NBP state
        CLR     D0                              | clear D0
        TST     D3                              | buffer overflow?
        BPL.B   E_1056_LOOP_NO_4                | no -> parse tuples
        CLR     D2                              | D2 = tuple count
        MOVE.L  0x16(A3),A0                     | A0 = buffer start
E_1056_LOOP_NEXT_3:
        ADDQ.W  #0x5,A0                         | skip tuple header
        CMP.L   A0,D1                           | past end?
        BLE.B   E_1056_LOOP_OK_6                | yes -> stop
        MOVE.B  (A0)+,D0                        | string 1 len
        ADDA    D0,A0                           | skip string 1
        CMP.L   A0,D1                           | past end?
        BLE.B   E_1056_LOOP_OK_6                | yes -> stop
        MOVE.B  (A0)+,D0                        | string 2 len
        ADDA    D0,A0                           | skip string 2
        CMP.L   A0,D1                           | past end?
        BLE.B   E_1056_LOOP_OK_6                | yes -> stop
        MOVE.B  (A0)+,D0                        | string 3 len
        ADDA    D0,A0                           | skip string 3
        CMP.L   A0,D1                           | past end?
        BLT.B   E_1056_LOOP_OK_6                | yes -> stop
        ADDQ.W  #0x1,D2                         | valid tuple, count it
        BRA.B   E_1056_LOOP_NEXT_3              | -> next tuple

| ----------------------------------------------------------
|
| E_1056_LOOP_OK_6
|
E_1056_LOOP_OK_6:
        TST     D2                              | any tuples?
  .short 0x6780                                 | BEQ.B E_1056_LOOP_ERR_5
E_1056_LOOP_NO_4:
        MOVEM.L A4-A6,-(SP)                     | save registers
        CLR     D1                              | D1 = unique count
        MOVE.L  0x12(A3),A5                     | A5 = param block
        MOVE.L  0x22(A5),D3                     | D3 = old buffer end
        MOVE.L  0x16(A3),A5                     | A5 = new tuples
        MOVE.L  A5,A6                           | A6 = dest for unique tuples
E_1056_LOOP_NEXT_4:
        MOVE.L  D3,A4                           | A4 = scan existing tuples
E_1056_LOOP_LOOP_3:
        CMPA.L  0x16(A3),A4                     | done scanning?
        BEQ.B   E_1056_LOOP_OK_7                | yes -> add tuple
        MOVE.L  A4,A0                           | A0 = existing tuple
        MOVE.L  A5,A1                           | A1 = new tuple
        CMPM.B  (A0)+,(A1)+                     | compare net
        BNE.B   E_1056_LOOP_NEXT_5              | diff -> next
        CMPM.B  (A0)+,(A1)+                     | compare net
        BNE.B   E_1056_LOOP_NEXT_5              | diff -> next
        CMPM.B  (A0)+,(A1)+                     | compare node
        BNE.B   E_1056_LOOP_NEXT_5              | diff -> next
        CMPM.B  (A0)+,(A1)+                     | compare socket
        BNE.B   E_1056_LOOP_NEXT_5              | diff -> next
        CMPM.B  (A0)+,(A1)+                     | compare enumerator
        BEQ.B   E_1056_LOOP_SKIP_3              | duplicate -> skip
E_1056_LOOP_NEXT_5:
        ADDQ.W  #0x5,A4                         | skip tuple header
        MOVE.B  (A4),D0                         | string 1 len
        ADD.B   0x1(A4,D0.W),D0                 | add string 2 len
        ADD.B   0x2(A4,D0.W),D0                 | add string 3 len
        ADDQ.W  #0x3,D0                         | add length bytes
        ADDA    D0,A4                           | skip names
        BRA.B   E_1056_LOOP_LOOP_3              | -> loop

| ----------------------------------------------------------
|
| E_1056_LOOP_OK_7
|
E_1056_LOOP_OK_7:
        MOVE.B  0x5(A5),D0                      | string 1 len
        ADD.B   0x6(A5,D0.W),D0                 | add string 2 len
        ADD.B   0x7(A5,D0.W),D0                 | add string 3 len
        ADDQ.W  #0x8,D0                         | add header+len bytes
        MOVE.L  A5,A0                           | source ptr
        ADDA    D0,A5                           | advance A5 to next
        CMPA.L  A0,A6                           | dest == source?
        BEQ.B   E_1056_LOOP_SKIP_2              | yes -> skip move
        MOVE.L  A6,A1                           | dest ptr
        ADDA    D0,A6                           | advance dest
        _BlockMove                              | copy NBP tuple to buffer
        BRA.B   E_1056_LOOP_NEXT_6              | -> next

| ----------------------------------------------------------
|
| E_1056_LOOP_SKIP_2
|
E_1056_LOOP_SKIP_2:
        MOVE.L  A5,A6                           | dest = source
E_1056_LOOP_NEXT_6:
        ADDQ.W  #0x1,D1                         | count unique tuple
E_1056_LOOP_NEXT_7:
        SUBQ.B  #0x1,D2                         | loop all new tuples
        BNE.B   E_1056_LOOP_NEXT_4              | -> next
        MOVE.L  A6,0x16(A3)                     | update buffer end
        MOVE.L  0x12(A3),A0                     | A0 = param block
        SUBA.L  0x22(A0),A6                     | used buffer space
        MOVE    0x26(A0),D0                     | total buffer size
        SUB     A6,D0                           | remaining space
        MOVEM.L (SP)+,A4-A6                     | restore registers
        ADD     0x2A(A0),D1                     | add previous match count
        MOVE    D1,0x2A(A0)                     | update total matches
        CMP     0x28(A0),D1                     | reached max matches?
        BPL     E_1056_LOOP_DONE_2              | yes -> complete
        MOVE    D0,0x1A(A3)                     | update remaining space
        BEQ     E_1056_LOOP_DONE_2              | buffer full -> complete
        RTS                                     | return

| ----------------------------------------------------------
|
| E_1056_LOOP_SKIP_3
|
E_1056_LOOP_SKIP_3:
        ADDQ.W  #0x5,A5                         | skip tuple header
        MOVE.B  (A5),D0                         | string 1 len
        ADD.B   0x1(A5,D0.W),D0                 | add string 2 len
        ADD.B   0x2(A5,D0.W),D0                 | add string 3 len
        ADDQ.W  #0x3,D0                         | add length bytes
        ADDA    D0,A5                           | advance past duplicate
        BRA.B   E_1056_LOOP_NEXT_7              | -> next tuple

| end of resource : 'DRVR' 9 '.MPP'

| resource header
  .long 0xC0000870                              | Length
  .long 0x00000068                              | ?

