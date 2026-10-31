| DRVR 9 - .MPP (AppleTalk Macintosh Packet Protocol) driver
| resource : 'DRVR' 9 '.MPP'
|
| LocalTalk link access (LAP) on SCC channel B (the printer port), DDP,
| RTMP (network number and bridge only) and NBP.  Control calls (csCode -
| 242 indexes E_MPP_CONTROL_DISPATCH_TBL, 250-255 go to the NBP code;
| csCodes from MPW 1.0 ATalkEqu, parameter blocks Inside Macintosh
| II-307..324):
|   242 LookupReply   LOOKUPREPLY   (queued to itself by NIS_LISTENER)
|   243 WriteLAP      WRITELAP      send a LAP frame
|   244 DetachPH      DETACHPH      remove a LAP protocol handler
|   245 AttachPH      ATTACHPH      install a LAP protocol handler
|   246 WriteDDP      WRITEDDP      send a datagram
|   247 CloseSkt      CLOSESKT      close a DDP socket
|   248 OpenSkt       OPENSKT       open a DDP socket
|   249 LoadNBP       LOADNBP       no-op (NBP is in ROM)
|   250 ConfirmName   CONFIRMNAME   \
|   251 LookupName    LOOKUPNAME     |
|   252 RemoveName    REMOVENAME     | via NBP_DISPATCH
|   253 RegisterName  REGISTERNAME   |
|   254 KillNBP       KILLNBP        |
|   255 UnloadNBP     UNLOADNBP     /
| csCode 1 (killCode) returns at once.  csCode < 0 (goodbye kiss, sent
| by _Launch because the driver has dNeedGoodbye) unlinks names-table
| entries that lie in the application heap, then completes as UnloadNBP.
|
| Receive path: LAP_RCVINT (SCC Rx interrupt) reads the LAP header and the
| length word into the read header area (RHA) and jumps to the protocol
| handler of the LAP type (DDP_RCVSHORT / DDP_RCVLONG for types 1 and 2),
| which reads the DDP header and jumps to the listener of the destination
| socket; handlers and listeners read the rest through READPACKET and
| READREST (A4 -> LAP_READ_JT).  Transmit path: LAPWRITE (CSMA/CA with
| lapRTS/lapCTS dialog, random backoff, synchronous; deferred to an
| interrupt when the line is busy).  While interrupts are off, bytes
| arriving on the modem port (SCC channel A, VIA PA7 = W/REQ) are saved on
| the stack and handed to PollProc (as the disk driver does).
|
| MPP variables (ABusVars, $FC bytes; names as in Apple's later LAPvars /
| vardefs sources):
|   +$00 sysLAPAddr (node ID), +$01 RHA (toRHA, 24 bytes), +$19
|   sysABridge (node of a bridge, 0 = none), +$1A sysNetNum, +$1C
|   vSCCEnable (SR enabling SCC interrupts), +$1E atpVars (.ATP)
|   +$22 4 LAP protocol types ($FF = free; 2 = longDDP, 1 = shortDDP)
|   +$26 4 protocol handler addresses
|   +$36 14 DDP socket numbers (0 = free; last = 1, the RTMP socket)
|   +$44 14 socket listener addresses
|   +$7C VBL task (MPP_VBLTASK, every 20 ticks)
|   +$8A NRPtr: NBP code (NBP_DISPATCH), bit 31 = installed
|   +$8E LookupPtr: lookup-reply code (LUCODE), bit 31 = NIS open
|   +$92 NRVars: NBP variables ($47 bytes, see NBP_INIT)
|   +$96 JDDPWrite: MPP_JDDPWRITE (+0 DDPWrite, +2 open socket)
|   +$9A NTQueueHd: names table (list of names-table entries)
|   +$9E LUQElPtr: lookup-reply parameter block/buffer ($98 bytes) + $1A
|   LAP: +$A2 WDSPtr, +$A6 LAPWrtRtn, +$AA RandomSeed, +$AC DestNode,
|   +$AD fLAPAdrValid, +$AE fGoodCTS, +$AF fAdrInUse, +$B0 fSendENQ,
|   +$B1 VBLDeferCnt, +$B2 lbackOff, +$B3 backoff, +$B4 collsnHistory,
|   +$B5 deferHistory, +$B6 deferTries, +$B7 collsnTries, +$B8
|   BridgeTime, +$B9 abort-sequence delay, +$BA SaveA45, +$C2
|   SaveDskRtn, +$C6 SavePS, +$CA SaveBIn, +$CE SaveBOut, +$D2
|   SaveVects (3), +$DE SaveRegs (5), +$F2 VIA vBufA address, +$F6
|   VSTData (6 SCC writes after a send; +$F7 = VDisTxRTS)
|

| resource header
    ROM_RESOURCE DRVR_9                         | 8-byte resource header (include/romrsrc.inc)
_DRVR_9_.MPP:
  .short 0x5C00                                 | drvrFlags: dNeedLock, dNeedGoodbye, dStatEnable, dCtlEnable
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x07FC                                 | drvrOpen offset: E_MPP_Open
  .short 0x0290                                 | drvrPrime offset: E_MPP_Prime
  .short 0x001A                                 | drvrCtl offset: E_MPP_Control
  .short 0x0284                                 | drvrStatus offset: E_MPP_Status
  .short 0x0774                                 | drvrClose offset: E_MPP_Close
  .byte 0x04                                    | drvrName length

| Name
  .ascii ".MPP"                                 | drvrName

| end of Name
  .byte 0x20,0x28,0x13                          | pad byte and two unreferenced bytes ($13 = 19 = the driver version set by Open)

| .MPP Control: A0 = parameter block, A1 = .MPP DCE.  Calls the
| AtalkHk1 hook, then dispatches with A2 = MPP variables, D1.B =
| csParam+0 (socket / protType / interval), A1 = csParam+2 (listener /
| wdsPointer / handler / entityPtr / ntQElPtr), D3 = csCode - 242.
E_MPP_Control:
        MOVE.L  (AtalkHk1).w,D3                 | AtalkHk1: AppleTalk hook
        BLE.B   E_MPP_CONTROL_NOHOOK            | none (<= 0) ->
        MOVE.L  D3,A2                           | A2 = hook routine
        JSR     (A2)                            | call it
E_MPP_CONTROL_NOHOOK:
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
        MOVE.L  A2,D0                           | .MPP open?
        BNE.B   E_MPP_CONTROL_CSCODE            | yes ->
        MOVEQ.L #-0x11,D0                       | controlErr (-17)
        BRA     MPP_DONE_A1                     | -> IODone
| dispatch on csCode
E_MPP_CONTROL_CSCODE:
        MOVE    0x1A(A0),D3                     | D3 = csCode
        BMI.B   E_MPP_CONTROL_GOODBYE           | negative: goodbye kiss ->
| csCode 1 (killCode)
        SUBQ.W  #0x1,D3                         | csCode 1?
        BNE.B   E_MPP_CONTROL_RANGE             | no ->
        RTS                                     | KillIO: nothing to cancel, return
| csCode must be 242..255
E_MPP_CONTROL_RANGE:
        MOVEQ.L #-0x11,D0                       | controlErr (-17) if out of range
        SUBI    #0xF1,D3                        | D3 = csCode - 242 (after the -1 above)
        BLT     MPP_DONE_A1                     | < 242 -> controlErr
        CMPI    #0xD,D3                         | > 255?
        BGT     MPP_DONE_A1                     | yes -> controlErr
| common arguments; 242..249 are resident, 250..255 are NBP calls
        MOVE.B  0x1C(A0),D1                     | D1 = csParam+0
        MOVE.L  0x1E(A0),A1                     | A1 = csParam+2
        CMPI    #0x7,D3                         | csCode > 249?
        BGT.B   E_MPP_CONTROL_NBP               | yes -> NBP code
| 242..249 through the dispatch table
        LEA.L   E_MPP_CONTROL_DISPATCH_TBL(PC),A3 | A3 = dispatch table
        ADDA    D3,A3                           | + index
        ADDA    D3,A3                           | (word entries)
        MOVE    (A3),A3                         | offset from the driver start
        PEA.L   _DRVR_9_.MPP(PC)                | driver start
        ADDA.L  (SP)+,A3                        | A3 = handler
        JMP     (A3)                            | -> handler

| E_MPP_CONTROL_DISPATCH_TBL - csCode 242..249, offsets from _DRVR_9_.MPP
E_MPP_CONTROL_DISPATCH_TBL:
  .byte  0x00,0x96,0x02,0x72,0x02,0x5E          | 242 LookupReply $96, 243 WriteLAP $272, 244 DetachPH $25E
  .byte 0x02,0x2E,0x01,0x1E,0x01,0x00           | 245 AttachPH $22E, 246 WriteDDP $11E, 247 CloseSkt $100
  .byte 0x00,0xB6,0x00,0xA0                     | 248 OpenSkt $B6, 249 LoadNBP $A0
| negative csCode (goodbye kiss): if the NIS is open, LUCODE+2 drops the
| names in the application heap; then on to the NBP code (with D3 < 0)
E_MPP_CONTROL_GOODBYE:
        MOVE.L  0x8E(A2),D1                     | D1 = LookupPtr
        BPL.B   E_MPP_CONTROL_NBP               | NIS not open ->
        MOVE.L  D1,A3                           | A3 = LUCODE
        JSR     0x2(A3)                         | NBP_DROPAPPLNAMES (via LUCODE_GOODBYE)
| csCode 250..255 (and the goodbye kiss): to the NBP code via NRPtr
E_MPP_CONTROL_NBP:
        MOVE.L  0x8A(A2),D2                     | D2 = NRPtr
        BPL.B   E_MPP_CONTROL_DONE              | NBP code not installed -> IODone (controlErr)
        MOVE.L  D2,A3                           | A3 = NBP_DISPATCH
        JMP     (A3)                            | -> NBP code

| ----------------------------------------------------------
|
| LookupReply (csCode 242): issued by NIS_LISTENER (to this driver) for a
| received LkUp packet; runs the lookup-reply code via LookupPtr
|
LOOKUPREPLY:
        MOVE.L  0x8E(A2),D2                     | D2 = LookupPtr
        BPL.B   E_MPP_CONTROL_DONE              | not installed -> IODone (controlErr)
        MOVE.L  D2,A3                           | A3 = LUCODE
        JMP     (A3)                            | -> LUCODE_REPLY -> NBP_LKUPREPLY

| ----------------------------------------------------------
|
| LoadNBP (csCode 249): nothing to load in the ROM driver - noErr
|
LOADNBP:
        CLR     D0                              | noErr
E_MPP_CONTROL_DONE:
        BRA     MPP_DONE                        | -> IODone with D0

| ----------------------------------------------------------
|
| MPP_INSTALLNBP: store NRPtr = NBP_DISPATCH (bit 31 set) and jump into
| it; E_MPP_Open calls this with D3 = 7, i.e. NBP_INIT
|
MPP_INSTALLNBP:
        LEA.L   NBP_DISPATCH(PC),A3             | A3 = NBP code entry
        MOVE.L  A3,0x8A(A2)                     | NRPtr
        BSET    #0x7,0x8A(A2)                   | bit 31: NBP code installed
        JMP     (A3)                            | -> NBP_DISPATCH

| ----------------------------------------------------------
|
| OPENSKT
|
| OpenSkt (csCode 248): socket = 1..127 to open that socket, 0 to get a
| new one (128..254, returned in socket); listener = socket listener.
| ddpSktErr if in use, >= 128 or the socket table (14 entries) is full.
OPENSKT:
        BSR.B   MPP_OPENSOCKET                  | open socket D1, listener A1
        MOVE.B  D1,0x1C(A0)                     | return the socket number
        BRA.B   CLOSESKT_DONE                   | -> IODone with D0

| ----------------------------------------------------------
|
| MPP_OPENSOCKET: enter socket D1 (0 = assign one) with listener A1 in the
| socket table -> D1 = socket, D0 = noErr or ddpSktErr.  Uses D2.
| Also called through JDDPWrite+2 (MPP_JOPENSOCKET) by the NBP code.
|
MPP_OPENSOCKET:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr (-91)
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        TST.B   D1                              | socket 0?
        BEQ.B   MPP_OPENSOCKET_FREE             | yes: assign one ->
        BMI.B   MPP_OPENSOCKET_EXIT             | >= 128 -> ddpSktErr
        BSR.B   MPP_FINDSKT                     | already open?
        BEQ.B   MPP_OPENSOCKET_EXIT             | yes -> ddpSktErr
| find a free entry in the socket table
MPP_OPENSOCKET_FREE:
        MOVEQ.L #0xD,D2                         | 14 entries
MPP_OPENSOCKET_LOOP:
        TST.B   0x36(A2,D2.W)                   | entry free?
        DBEQ    D2,MPP_OPENSOCKET_LOOP          | no -> next
        BNE.B   MPP_OPENSOCKET_EXIT             | table full -> ddpSktErr
        TST.B   D1                              | socket given?
        BNE.B   MPP_OPENSOCKET_STORE            | yes ->
        BSR     MPP_RANDOM                      | D0 = random number
        ANDI.B  #0xF0,D0                        | random high nibble
        OR.B    D2,D0                           | entry number in the low nibble
        BSET    #0x7,D0                         | 128..254 (dynamic sockets)
        MOVE.B  D0,D1                           | D1 = new socket number
MPP_OPENSOCKET_STORE:
        MOVE.B  D1,0x36(A2,D2.W)                | socket number
        LSL     #0x2,D2                         | long index
        MOVE.L  A1,0x44(A2,D2.W)                | socket listener
        CLR     D0                              | noErr
MPP_OPENSOCKET_EXIT:
        MOVE    (SP)+,SR                        | restore SR
        RTS                                     | return from MPP_OPENSOCKET

| ----------------------------------------------------------
|
| CloseSkt (csCode 247): remove socket D1 from the socket table.
| ddpSktErr if 0 or not open.
|
CLOSESKT:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr (-91)
        TST.B   D1                              | socket 0?
        BEQ.B   CLOSESKT_DONE                   | yes -> ddpSktErr
        BSR.B   MPP_FINDSKT                     | D2 = its entry
        BNE.B   CLOSESKT_DONE                   | not open -> ddpSktErr
        CLR.B   0x36(A2,D2.W)                   | free the entry
        CLR     D0                              | noErr
CLOSESKT_DONE:
        BRA.B   E_MPP_CONTROL_DONE              | -> IODone with D0

| ----------------------------------------------------------
|
| MPP_FINDSKT: find socket D1 in the socket table -> EQ and D2 = entry if
| found
|
MPP_FINDSKT:
        MOVEQ.L #0xD,D2                         | 14 entries
MPP_FINDSKT_LOOP:
        CMP.B   0x36(A2,D2.W),D1                | this socket?
        DBEQ    D2,MPP_FINDSKT_LOOP             | no -> next
        RTS                                     | EQ = found

| ----------------------------------------------------------
|
| WRITEDDP
|
| WriteDDP (csCode 246): send the datagram described by the WDS at
| wdsPointer from socket D1; checksumFlag = checksum long headers.
WRITEDDP:
        MOVE.B  0x1D(A0),D3                     | D3 = checksumFlag
        BSR.B   MPP_JDDPWRITE                   | DDPWRITE
        BRA.B   CLOSESKT_DONE                   | -> IODone with D0

| ----------------------------------------------------------
|
| MPP_JDDPWRITE: JDDPWrite+0 (MPP variables +$96) - DDPWRITE
|
MPP_JDDPWRITE:
        BRA.B   DDPWRITE                        | -> DDPWRITE

| ----------------------------------------------------------
|
| MPP_JOPENSOCKET: JDDPWrite+2 - MPP_OPENSOCKET
|
MPP_JOPENSOCKET:
        BRA.B   MPP_OPENSOCKET                  | -> MPP_OPENSOCKET

| ----------------------------------------------------------
|
| DDPWRITE
|
| DDPWRITE: send a datagram.  A1 = WDS (first entry -> 16-byte header
| area at an odd address: +7 dest net, +11 dest node, +13 dest socket,
| +15 DDP type), D1 = source socket, D3.B = checksum flag.  Builds a
| short header (dest net 0 or ours) or a long one, then LAPWRITE.
| D0 = noErr, ddpSktErr, ddpLenErr or noBridgeErr.
DDPWRITE:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr (-91)
        TST.B   D1                              | socket 0?
        BEQ.B   DDPWRITE_EXIT                   | yes -> ddpSktErr
        BSR.B   MPP_FINDSKT                     | socket open?
        BNE.B   DDPWRITE_EXIT                   | no -> ddpSktErr
| complete the header in the first WDS entry
        MOVE.L  A1,-(SP)                        | save the WDS pointer
        ADDQ.W  #0x2,A1                         | skip the length of entry 1
        MOVE.L  (A1)+,A3                        | A3 = header area
        ADDQ.W  #0x7,A3                         | A3 -> +7 dest network
        MOVE.B  D1,0x7(A3)                      | +14 source socket
        MOVE    (A3),D0                         | D0 = dest network
        BEQ.B   DDPWRITE_SHORT                  | 0 = this network -> short header
        CMP     0x1A(A2),D0                     | = sysNetNum?
        BEQ.B   DDPWRITE_SHORT                  | yes -> short header
| long header: source network and node, optional checksum
        MOVE    0x1A(A2),0x2(A3)                | +9 source network = sysNetNum
        MOVE.B  (A2),0x5(A3)                    | +12 source node = sysLAPAddr
        MOVE.B  0x4(A3),D1                      | D1 = dest node (+11)
        MOVE.L  A3,A0                           | A0 -> checksummed part (from +7)
        CLR     -(A3)                           | +5 ddpChecksum = 0
        TST.B   D3                              | checksum wanted?
        BEQ.B   DDPWRITE_LONG                   | no ->
        MOVEQ.L #0x9,D0                         | 9 header bytes (+7..+15)
        CLR     D3                              | checksum = 0
        BSR.B   DDPWRITE_CHECKSUM               | add them
DDPWRITE_CKSLOOP:
        MOVE    (A1)+,D0                        | D0 = length of the next WDS entry
        BEQ.B   DDPWRITE_CKSDONE                | 0 = end of WDS ->
        MOVE.L  (A1)+,A0                        | A0 = its data
        BSR.B   DDPWRITE_CHECKSUM               | add them
        BRA.B   DDPWRITE_CKSLOOP                | next entry

| ----------------------------------------------------------
|
| DDPWRITE_CKSDONE
|
| store the checksum (a computed 0 is sent as $FFFF)
DDPWRITE_CKSDONE:
        MOVE    D3,(A3)                         | ddpChecksum
        BNE.B   DDPWRITE_LONG                   | not 0 ->
        SUBQ.W  #0x1,(A3)                       | 0 -> $FFFF
| LAP type longDDP; the frame goes to the bridge, if one is known
DDPWRITE_LONG:
        MOVEQ.L #0x2,D3                         | D3 = LAP type 2 (longDDP)
        MOVEQ.L #0x10,D0                        | header entry: 3 LAP + 13 DDP bytes
        MOVE.B  0x19(A2),D2                     | D2 = sysABridge
        BNE.B   DDPWRITE_LENGTH                 | bridge known -> send to it
        MOVE.B  D1,D2                           | else send to the dest node directly ...
        TST     0x1A(A2)                        | ... when no network number is known
        BEQ.B   DDPWRITE_LENGTH                 | sysNetNum = 0 ->
        MOVEQ.L #-0x5D,D0                       | noBridgeErr (-93)
        ADDQ.W  #0x4,SP                         | drop the WDS pointer
        RTS                                     | return with the error

| ----------------------------------------------------------
|
| DDPWRITE_CHECKSUM: DDP checksum over D0 bytes at (A0)+ into D3
| (add, rotate left one bit); D2 bits 15-8 must be clear
|
DDPWRITE_CHECKSUM:
        MOVE.B  (A0)+,D2                        | next byte
        ADD     D2,D3                           | add it
        ROL     #0x1,D3                         | rotate left one bit
        SUBQ.W  #0x1,D0                         | count
        BNE.B   DDPWRITE_CHECKSUM               | loop
DDPWRITE_EXIT:
        RTS                                     | return from DDPWRITE_CHECKSUM / DDPWRITE

| ----------------------------------------------------------
|
| DDPWRITE_SHORT: short header - move dest socket, source socket and type
| down to +5..+7 (over the high byte of the dest network); LAP
| destination = dest node, LAP type shortDDP
|
DDPWRITE_SHORT:
        MOVE.L  A3,A0                           | A0 -> +7
        ADDQ.W  #0x8,A0                         | A0 -> +15 DDP type
        MOVE.B  (A0),(A3)                       | +7 = DDP type (sDDPType)
        MOVE    -(A0),-(A3)                     | +5/+6 = dest/source socket (from +13/+14)
        SUBQ.W  #0x2,A0                         | A0 -> +11
        MOVE.B  (A0),D2                         | D2 = dest node
        MOVEQ.L #0x1,D3                         | D3 = LAP type 1 (shortDDP)
        MOVEQ.L #0x8,D0                         | header entry: 3 LAP + 5 DDP bytes
| total length from the WDS
DDPWRITE_LENGTH:
        MOVE.L  (SP)+,A1                        | A1 = WDS
        MOVE    D0,(A1)                         | length of entry 1 = header size
        CLR     D1                              | D1 = total length
        MOVE.L  A1,A0                           | A0 -> first entry
DDPWRITE_LENLOOP:
        TST     (A0)                            | length 0 = end?
        BEQ.B   DDPWRITE_SEND                   | yes ->
        BMI.B   DDPWRITE_LENERR                 | negative -> ddpLenErr
        ADD     (A0),D1                         | add the length
        ADDQ.W  #0x6,A0                         | next entry (6 bytes)
        BRA.B   DDPWRITE_LENLOOP                | loop

| ----------------------------------------------------------
|
| DDPWRITE_SEND: ddpLength, LAP type and destination, then LAPWRITE
|
DDPWRITE_SEND:
        MOVE    D1,-(A3)                        | +3 length word = total
        SUBQ.W  #0x3,(A3)                       | - LAP header = datagram length
        SUB     D0,D1                           | D1 = data length
        CMPI    #0x24A,D1                       | > ddpMaxData (586)?
        BHI.B   DDPWRITE_LENERR                 | yes -> ddpLenErr
        MOVE.B  D3,-(A3)                        | +2 lapType
        SUBQ.W  #0x2,A3                         | A3 -> +0
        MOVE.B  D2,(A3)                         | +0 lapDstAdr (+1 lapSrcAdr: set by LAP_SENDFRAME)
        BRA     LAPWRITE                        | send the frame (A1 = WDS)

| ----------------------------------------------------------
|
| DDPWRITE_LENERR: datagram too long
|
DDPWRITE_LENERR:
        MOVEQ.L #-0x5C,D0                       | ddpLenErr (-92)
        BRA.B   DDPWRITE_EXIT                   | -> return

| ----------------------------------------------------------
|
| DDP_RCVLONG: protocol handler of LAP type 2 (longDDP).  Reads the other
| 11 header bytes into the RHA; delivers only datagrams for our network.
|
DDP_RCVLONG:
        MOVEQ.L #0xB,D3                         | 11 bytes (13-byte header, length already read)
        MOVE    0x1A(A2),D2                     | D2 = sysNetNum
        JSR     (A4)                            | ReadPacket
        BNE.B   DDPWRITE_EXIT                   | error -> return
        CMP     0x8(A2),D2                      | ddpDstNet (RHA+7) = our network?
        BEQ.B   DDP_RCVSOCKET                   | yes -> to the socket listener
        BRA.B   DDP_RCVDISCARD                  | no -> drop

| ----------------------------------------------------------
|
| DDP_RCVSHORT: protocol handler of LAP type 1 (shortDDP).  Reads the
| other 3 header bytes (dest socket, source socket, type) into the RHA.
|
DDP_RCVSHORT:
        MOVEQ.L #0x3,D3                         | 3 bytes (5-byte header, length already read)
        JSR     (A4)                            | ReadPacket
        BNE.B   DDPWRITE_EXIT                   | error -> return
| DDP_RCVSOCKET: jump to the listener of the destination socket (D0)
DDP_RCVSOCKET:
        MOVEQ.L #0xD,D2                         | 14 socket table entries
        MOVE.B  -0x3(A3),D0                     | D0 = destination socket (3 bytes before A3)
        BEQ.B   DDP_RCVDISCARD                  | socket 0 -> drop
DDP_RCVSOCKET_LOOP:
        CMP.B   0x36(A2,D2.W),D0                | this socket?
        DBEQ    D2,DDP_RCVSOCKET_LOOP           | no -> next
        BNE.B   DDP_RCVDISCARD                  | not open -> drop
        LSL     #0x2,D2                         | long index
        MOVE.L  0x44(A2,D2.W),A5                | A5 = socket listener
        JMP     (A5)                            | -> listener

| ----------------------------------------------------------
|
| DDP_RCVDISCARD: drop the packet - ReadRest with D3 = 0 (left 0 by the
| successful ReadPacket)
|
DDP_RCVDISCARD:
        JMP     0x2(A4)                         | ReadRest: discard the rest, return to MPP

| ----------------------------------------------------------
|
| RTMP_LISTENER: listener of socket 1 (RTMP).  From an RTMP data packet
| (DDP type 1) it takes the network number and the router's node ID
| (ID length 8): sysNetNum, sysABridge, BridgeTime = 255 (aged by
| MPP_VBLTASK).  The RTMP header is read over the DDP type byte, so the
| network number lands word aligned.
|
RTMP_LISTENER:
        SUBQ.B  #0x1,-(A3)                      | A3 back to the DDP type byte: type 1 (RTMP data)?
        BNE.B   DDP_RCVDISCARD                  | no -> drop
        MOVEQ.L #0x4,D3                         | 4 bytes: network, ID length, ID
        JSR     0x2(A4)                         | ReadRest
        BNE.B   RTMP_LISTENER_EXIT              | error -> return
        MOVE.B  -(A3),D2                        | D2 = router node ID (rtmpID)
        SUBQ.B  #0x8,-(A3)                      | rtmpIDLen = 8 bits?
        BNE.B   RTMP_LISTENER_EXIT              | no -> ignore
        MOVE.B  D2,0x19(A2)                     | sysABridge = router node
        ST.B    0xB8(A2)                        | BridgeTime = 255 VBL periods
        MOVE    -(A3),0x1A(A2)                  | sysNetNum = rtmpNet
RTMP_LISTENER_EXIT:
        RTS                                     | return to MPP

| ----------------------------------------------------------
|
| AttachPH (csCode 245): enter protocol handler handler for LAP type
| protType (1..127) in the protocol table.  lapProtErr if invalid,
| already attached or the table (4 entries, 2 used by DDP) is full.
|
ATTACHPH:
        MOVEQ.L #-0x5E,D0                       | lapProtErr (-94)
        TST.B   D1                              | protType 1..127?
        BLE.B   ATTACHPH_DONE                   | no -> lapProtErr
        BSR.B   MPP_FINDPH                      | already attached?
        BEQ.B   ATTACHPH_DONE                   | yes -> lapProtErr
        MOVEQ.L #0x3,D2                         | 4 entries
ATTACHPH_LOOP:
        LEA.L   0x22(A2,D2.W),A3                | A3 -> protocol type of the entry
        TST.B   (A3)                            | free ($FF)?
        DBMI    D2,ATTACHPH_LOOP                | no -> next
        BPL.B   ATTACHPH_DONE                   | table full -> lapProtErr
        LSL     #0x2,D2                         | long index
        MOVE.L  A1,0x26(A2,D2.W)                | protocol handler
        MOVE.B  D1,(A3)                         | protocol type
ATTACHPH_NOERR:
        CLR     D0                              | noErr
ATTACHPH_DONE:
        BRA.B   MPP_DONE                        | -> IODone with D0

| ----------------------------------------------------------
|
| MPP_FINDPH: find LAP type D1 in the protocol table -> EQ and D2 =
| entry if found
|
MPP_FINDPH:
        MOVEQ.L #0x3,D2                         | 4 entries
MPP_FINDPH_LOOP:
        CMP.B   0x22(A2,D2.W),D1                | this type?
        DBEQ    D2,MPP_FINDPH_LOOP              | no -> next
        RTS                                     | EQ = found

| ----------------------------------------------------------
|
| DetachPH (csCode 244): remove LAP type protType from the protocol
| table.  lapProtErr if not attached.
|
DETACHPH:
        MOVEQ.L #-0x5E,D0                       | lapProtErr (-94)
        MOVEQ.L #0x3,D2                         | 4 entries
DETACHPH_LOOP:
        CMP.B   0x22(A2,D2.W),D1                | this type?
        DBEQ    D2,DETACHPH_LOOP                | no -> next
        BNE.B   ATTACHPH_DONE                   | not attached -> lapProtErr
        ST.B    0x22(A2,D2.W)                   | entry free ($FF)
        BRA.B   ATTACHPH_NOERR                  | -> IODone, noErr

| ----------------------------------------------------------
|
| WriteLAP (csCode 243): send the frame described by the WDS at
| wdsPointer (first entry: lapDstAdr, lapSrcAdr filled in, lapType
| 1..127, then the data).  lapProtErr, excessCollsns.
|
WRITELAP:
        MOVE.L  0x2(A1),A0                      | A0 = first WDS entry (LAP header)
        MOVEQ.L #-0x5E,D0                       | lapProtErr (-94)
        TST.B   0x2(A0)                         | lapType 1..127?
        BLE.B   ATTACHPH_DONE                   | no -> lapProtErr
        MOVE.B  (A0),D2                         | D2 = lapDstAdr
        BSR.B   LAPWRITE                        | send it (A1 = WDS)
        BRA.B   MPP_DONE                        | -> IODone with D0

| ----------------------------------------------------------
|
| E_MPP_Status
|
| .MPP Status: no status calls - statusErr
E_MPP_Status:
        MOVEQ.L #-0x12,D0                       | statusErr (-18)
| MPP_DONE / MPP_DONE_A1: IODone with D0 (A1 = .MPP DCE from AbusDCE /
| already in A1)
MPP_DONE:
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE (AbusDCE)
MPP_DONE_A1:
        MOVE.L  (JIODone).w,-(SP)               | push the IODone vector
        RTS                                     | -> IODone (completes the current call)

| ----------------------------------------------------------
|
| .MPP Prime: not supported - clear drvrActive and return without
| completing the call
|
E_MPP_Prime:
        BCLR    #0x7,0x5(A1)                    | dCtlFlags: clear drvrActive
        RTS                                     | return from E_MPP_Prime

| ----------------------------------------------------------
|
| LAPWRITE
|
| LAPWRITE: send a LocalTalk frame.  A1 = WDS (first entry: frame header),
| D2 = destination node ($FF = broadcast).  The return address is kept in
| LAPWrtRtn and the write ends with a jump there (D0 = noErr or
| excessCollsns); when the line is busy the call returns to the caller's
| caller at once and the write resumes later from LAP_EXTINT or
| MPP_VBLTASK.  Each attempt: random wait (lbackOff), inter-dialog gap,
| sync pulse, lapRTS (lapENQ when fSendENQ is set) to D2, wait for lapCTS
| (none for a broadcast), then the data frame (LAP_SENDFRAME).
LAPWRITE:
        CLR.B   0xB0(A2)                        | fSendENQ = 0: a data frame
        MOVE.L  A1,0xA2(A2)                     | WDSPtr = WDS
| LAPWRITE_ENQ: entry used to send an ENQ (fSendENQ set by the caller)
LAPWRITE_ENQ:
        MOVE.L  (SP)+,0xA6(A2)                  | LAPWrtRtn = return address
        MOVE.L  (ATalkHk2).w,D3                 | AtalkHk2: AppleTalk hook
        BLE.B   LAPWRITE_NOHOOK                 | none (<= 0) ->
        MOVE.L  D3,A3                           | A3 = hook routine
        JSR     (A3)                            | call it
LAPWRITE_NOHOOK:
        MOVE.B  D2,0xAC(A2)                     | DestNode
| adapt the global backoff mask to the collision/deferral history
        LEA.L   0xB3(A2),A3                     | A3 -> backoff
        MOVE.B  (A3)+,D3                        | D3 = backoff (global mask)
        MOVE.B  (A3),D2                         | D2 = collsnHistory
        ADD.B   D2,(A3)+                        | collsnHistory << 1 (one send older)
        BSR.B   LAP_COUNTBITS                   | collisions in the last 8 sends - 2
        BLE.B   LAPWRITE_DEFERS                 | 2 or fewer -> look at the deferrals
| more than 2 collisions: double the mask
        ADD.B   D3,D3                           | backoff * 2 ...
        ADDQ.B  #0x1,D3                         | ... + 1
        ANDI    #0xF,D3                         | at most $F
        CLR.B   -0x1(A3)                        | collsnHistory = 0
        BRA.B   LAPWRITE_INIT                   | ->

| ----------------------------------------------------------
|
| LAP_COUNTBITS: D0 = (number of 1 bits in D2.B) - 2, condition codes set
| (GT = 3 or more).  Uses D1.
|
LAP_COUNTBITS:
        MOVEQ.L #0x0,D0                         | count = 0
        MOVEQ.L #0x7,D1                         | 8 bits
LAP_COUNTBITS_LOOP:
        BTst    D1,D2                           | bit set?
        BEQ.B   LAP_COUNTBITS_NEXT              | no ->
        ADDQ.W  #0x1,D0                         | count it
LAP_COUNTBITS_NEXT:
        DBF     D1,LAP_COUNTBITS_LOOP           | next bit
        SUBQ.B  #0x2,D0                         | - 2
        RTS                                     | return from LAP_COUNTBITS

| ----------------------------------------------------------
|
| LAPWRITE_DEFERS: few collisions - halve the mask when fewer than 2 of
| the last 8 sends were deferred (deferHistory then set to $FF)
|
LAPWRITE_DEFERS:
        MOVE.B  (A3),D2                         | D2 = deferHistory
        BSR.B   LAP_COUNTBITS                   | deferrals - 2
        BGE.B   LAPWRITE_INIT                   | 2 or more -> keep the mask
        LSR.B   #0x1,D3                         | backoff / 2
        ST.B    (A3)                            | deferHistory = $FF
| tries, local and global backoff for this send
LAPWRITE_INIT:
        MOVE.B  (A3),D2                         | D2 = deferHistory
        ADD.B   D2,(A3)+                        | deferHistory << 1
        MOVEQ.L #0x20,D0                        | 32
        MOVE.B  D0,(A3)+                        | deferTries = 32
        MOVE.B  D0,(A3)                         | collsnTries = 32
        SUBQ.W  #0x5,A3                         | A3 -> lbackOff
        MOVE.B  D3,(A3)+                        | lbackOff = backoff
        MOVE.B  D3,(A3)+                        | backoff = new mask
        MOVEM.L (SCCRd).w,A0-A1                 | A0/A1 = SCC channel B control (read/write)
| LAPWRITE_START: begin (or resume) the transmission, SR on the stack
LAPWRITE_START:
        MOVE    SR,-(SP)                        | save SR
| LAPWRITE_TRY: one attempt; D3 = D0 so that LAPWRITE_BUSY can tell how
| long we waited
LAPWRITE_TRY:
        MOVE    D0,D3                           | D3 = D0 (no wait yet)
        BTST    #0x4,(A0)                       | RR0 Sync/Hunt: receiver hunting (no frame on the line)?
        BEQ.B   LAPWRITE_SENSE                  | no, a frame is in progress -> busy
        BSR     MPP_RANDOM                      | D0 = random number
        AND.B   0xB2(A2),D0                     | masked with lbackOff
        ANDI    #0xF,D0                         | 0..15
        MOVE    D0,D3                           | D3 = random wait in ~100 us steps
        BEQ.B   LAPWRITE_IDG                    | none ->
LAPWRITE_WAIT:
        BSR.B   LAP_WAIT100                     | wait ~100 us; frame on the line?
        BEQ.B   LAPWRITE_SENSE                  | yes -> busy
        SUBQ.W  #0x1,D0                         | count down
        BNE.B   LAPWRITE_WAIT                   | loop
| inter-dialog gap: 4 more steps with interrupts off; the DPLL watches
| for any activity meanwhile
LAPWRITE_IDG:
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        MOVE.B  #0xE,(A1)                       | WR0: select WR14
        MOVEQ.L #0x3,D0                         | 4 steps
        ADDQ.W  #0x3,D3                         | D3 = steps waited when the gap ends
        MOVE.B  #0x41,(A1)                      | WR14 = $41: DPLL reset missing clock, BRG on
LAPWRITE_IDGLOOP:
        BSR.B   LAP_WAIT100                     | wait ~100 us; frame on the line?
        DBEQ    D0,LAPWRITE_IDGLOOP             | no -> next step
| line still free?
LAPWRITE_SENSE:
        BEQ     LAPWRITE_BUSY                   | frame seen -> busy
        MOVE.B  #0xA,(A1)                       | WR0: select RR10
        MOVE.B  0xAC(A2),D2                     | D2 = DestNode
        TST.B   (A0)                            | RR10 bit 7: one clock missing?
        BMI     LAPWRITE_BUSY                   | yes: activity during the gap (e.g. a sync pulse) -> busy
| line free: sync pulse (RTS on, off), then lapRTS or lapENQ
        MOVE.B  #0x5,(A1)                       | WR0: select WR5
        MOVEQ.L #-0x7C,D0                       | D0 = $84 (lapRTS)
        MOVE.B  #0x62,(A1)                      | WR5 = $62: RTS on (line driver on), Tx off
        TST.B   0xB0(A2)                        | fSendENQ?
        BEQ.B   LAPWRITE_SENDCTL                | no ->
        MOVEQ.L #-0x7F,D0                       | D0 = $81 (lapENQ)
| end the sync pulse, send the control frame
LAPWRITE_SENDCTL:
        MOVE.B  #0x5,(A1)                       | WR0: select WR5
        NOP                                     | SCC recovery time
        MOVE.B  0xF7(A2),(A1)                   | WR5 = VDisTxRTS ($60): RTS off
        BSR     LAP_SENDCTL                     | send lapRTS/lapENQ to DestNode
        ADDQ.B  #0x1,D2                         | DestNode = $FF?
        BEQ.B   LAPWRITE_BCAST                  | broadcast: no lapCTS ->
        CLR.B   0xAE(A2)                        | fGoodCTS = 0
        BSR     LAP_POLLRCV                     | receive the answer, if any
        TST.B   0xB0(A2)                        | sending ENQs?
        BEQ.B   LAPWRITE_CHKCTS                 | no ->
        TST.B   0xAF(A2)                        | fAdrInUse (ACK or other frame for the address)?
        BEQ.B   LAPWRITE_COLLISION              | no answer -> send the ENQ again
        BRA.B   LAPWRITE_NOERR                  | answered -> done

| ----------------------------------------------------------
|
| LAPWRITE_CHKCTS: lapCTS received? then send the data frame
|
LAPWRITE_CHKCTS:
        TST.B   0xAE(A2)                        | fGoodCTS?
        BEQ.B   LAPWRITE_COLLISION              | no lapCTS: assume a collision
        BRA.B   LAPWRITE_DATA                   | -> data frame

| ----------------------------------------------------------
|
| LAP_WAIT100: wait ~100 us, then test RR0 Sync/Hunt -> EQ if the
| receiver has left hunt mode (a frame is on the line).  Uses D1.
|
LAP_WAIT100:
        MOVEQ.L #0x3C,D1                        | 61 iterations
LAP_WAIT100_LOOP:
        DBF     D1,LAP_WAIT100_LOOP             | delay
        BTST    #0x4,(A0)                       | RR0 Sync/Hunt
        RTS                                     | EQ = frame on the line

| ----------------------------------------------------------
|
| LAPWRITE_BCAST: broadcast - after the lapRTS the line must stay quiet
| for ~100 us
|
LAPWRITE_BCAST:
        BSR.B   LAP_WAIT100                     | wait ~100 us; frame on the line?
        BEQ.B   LAPWRITE_COLLISION              | yes -> collision
| send the data frame
LAPWRITE_DATA:
        BSR     LAP_SENDFRAME                   | send the frame of WDSPtr
| done
LAPWRITE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
| return through LAPWrtRtn
LAPWRITE_EXIT:
        MOVE    (SP)+,SR                        | restore SR
        MOVE.L  0xA6(A2),A0                     | A0 = LAPWrtRtn
        JMP     (A0)                            | continue the caller

| ----------------------------------------------------------
|
| LAPWRITE_COLLISION: no lapCTS (or line busy after a broadcast lapRTS):
| record a collision, widen lbackOff, retry up to collsnTries times
|
LAPWRITE_COLLISION:
        MOVE    (SP),SR                         | restore SR (it stays on the stack)
        BSET    #0x0,0xB4(A2)                   | collsnHistory: collision in this send
        MOVE.B  0xB2(A2),D0                     | lbackOff ...
        ADD.B   D0,D0                           | ... * 2 ...
        ADDQ.B  #0x1,D0                         | ... + 1
        MOVE.B  D0,0xB2(A2)                     | store it
        MOVEQ.L #-0x5F,D0                       | excessCollsns (-95)
        SUBQ.B  #0x1,0xB7(A2)                   | collsnTries - 1
        BEQ.B   LAPWRITE_EXIT                   | used up -> excessCollsns
        BRA     LAPWRITE_TRY                    | try again

| ----------------------------------------------------------
|
| LAPWRITE_BUSY: the line is busy.  If it went busy after we had waited
| at least 4 steps, count a deferral (deferTries; lbackOff and
| deferHistory bit 0); then wait for the end of the frame on the line.
|
LAPWRITE_BUSY:
        SUB     D0,D3                           | D3 = steps waited
        SUBQ.W  #0x4,D3                         | fewer than 4?
        BLT.B   LAPWRITE_DEFER                  | yes -> just wait
        MOVEQ.L #-0x5F,D0                       | excessCollsns (-95)
        SUBQ.B  #0x1,0xB6(A2)                   | deferTries - 1
        BEQ.B   LAPWRITE_EXIT                   | used up -> excessCollsns
        BSET    #0x0,0xB2(A2)                   | lbackOff at least 1
        BSET    #0x0,0xB5(A2)                   | deferHistory: deferral in this send
| wait: the abort at the end of the frame raises an external/status
| interrupt (LAP_EXTINT); MPP_VBLTASK resumes after 20-40 ticks anyway
LAPWRITE_DEFER:
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        MOVE.B  #0xF,(A1)                       | WR0: select WR15
        MOVEQ.L #-0x78,D0                       | $88
        MOVE.B  D0,(A1)                         | WR15 = $88: break/abort and DCD interrupts
        ADDQ.B  #0x2,0xB1(A2)                   | VBLDeferCnt + 2
        MOVEQ.L #0x0,D0                         | noErr
        MOVE    (SP)+,SR                        | restore SR
        RTS                                     | return to the caller's caller (write pending)

| ----------------------------------------------------------
|
| LAP_EXTINT: SCC channel B external/status interrupt (ExtStsDT[0]:
| changes other than DCD alone; D1 = changed enabled RR0 bits).  Resumes
| a deferred LAPWRITE; otherwise passes a DCD change to the mouse handler.
|
LAP_EXTINT:
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
        TST.B   0xB1(A2)                        | write waiting (VBLDeferCnt)?
        BNE.B   LAP_EXTINT_RESUME               | yes -> resume it
        BTST    #0x3,D1                         | DCD (mouse Y) changed too?
        BEQ.B   LAP_RTS                         | no -> ignore
        MOVE.L  (ExtStsDT_1).w,A3               | A3 = DCD handler (ExtStsDT[1], mouse Y)
        JMP     (A3)                            | -> it

| ----------------------------------------------------------
|
| LAP_EXTINT_RESUME
|
| LAP_EXTINT_RESUME / LAP_RESUMEWRITE: resume a deferred LAPWRITE
LAP_EXTINT_RESUME:
        CLR.B   0xB1(A2)                        | VBLDeferCnt = 0
LAP_RESUMEWRITE:
        MOVE.B  #0xF,(A1)                       | WR0: select WR15
        MOVEQ.L #0x8,D0                         | $08
        MOVE.B  D0,(A1)                         | WR15 = $08: DCD (mouse) interrupt only
        MOVE    0x1C(A2),SR                     | SR = vSCCEnable
        BRA     LAPWRITE_START                  | next attempt

| ----------------------------------------------------------
|
| MPP_VBLTASK: VBL task, every 20 ticks (A0 = task).  Ages BridgeTime
| (sysABridge forgotten after 255 periods without RTMP) and resumes a
| deferred LAPWRITE when VBLDeferCnt runs out.
|
MPP_VBLTASK:
        MOVE    #0x14,0xA(A0)                   | vblCount = 20 ticks
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
        SUBQ.B  #0x1,0xB8(A2)                   | BridgeTime - 1
        BNE.B   MPP_VBLTASK_DEFER               | not expired ->
        CLR.B   0x19(A2)                        | sysABridge = 0 (no bridge)
| deferred write waiting?
MPP_VBLTASK_DEFER:
        TST.B   0xB1(A2)                        | VBLDeferCnt
        BEQ.B   LAP_RTS                         | no write waiting -> return
        SUBQ.B  #0x1,0xB1(A2)                   | count down
        BNE.B   LAP_RTS                         | not yet -> return
        MOVEM.L (SCCRd).w,A0-A1                 | A0/A1 = SCC channel B control
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        BSR     LAP_RCVRESET                    | receiver back to hunt mode
        BRA.B   LAP_RESUMEWRITE                 | resume the write

| ----------------------------------------------------------
|
| LAP_POLLRCV: poll ~125 times for a received byte (the answer to a
| lapRTS/lapENQ, or the data frame after our lapCTS) and receive the frame
| through LAP_RCVFRAME.  Preserves A0-A2.
|
LAP_POLLRCV:
        MOVEM.L A0-A2,-(SP)                     | save A0-A2
        MOVEQ.L #0x7D,D1                        | 126 polls
LAP_POLLRCV_LOOP:
        BTst    #0x0,(A0)                       | RR0: Rx character available?
        DBNE    D1,LAP_POLLRCV_LOOP             | no -> poll again
        BEQ.B   LAP_POLLRCV_EXIT                | nothing came ->
        BSR     LAP_RCVFRAME                    | receive the frame
LAP_POLLRCV_EXIT:
        MOVEM.L (SP)+,A0-A2                     | restore A0-A2
LAP_RTS:
        RTS                                     | return

| ----------------------------------------------------------
|
| MPP_RANDOM: RandomSeed = byte-swapped (RandomSeed * 773 + 1); returns
| it in D0
|
MPP_RANDOM:
        MOVE    0xAA(A2),D0                     | D0 = RandomSeed
        MULU    #0x305,D0                       | * 773
        ADDQ.W  #0x1,D0                         | + 1
        MOVE    D0,-(SP)                        | push it
        LSL     #0x8,D0                         | low byte to the high byte
        MOVE.B  (SP)+,D0                        | old high byte to the low byte
        MOVE    D0,0xAA(A2)                     | new RandomSeed
        RTS                                     | return from MPP_RANDOM

| ----------------------------------------------------------
|
| LAP_TXON_TBL: SCC writes for LAP_TXON - WR5 = $6B (Tx on, RTS on, 8
| bits, Tx CRC on), WR3 = $D0 (receiver off, enter hunt mode)
|
LAP_TXON_TBL:
  .byte  0x05,0x6B,0x03,0xD0                    | WR0 = 5, WR5 = $6B, WR0 = 3, WR3 = $D0
| LAP_SENDBYTE: wait (31 polls) for the Tx buffer, then write D3 to the
| channel B data register.  Returns TST D1: EQ only if D1 = 0; a timeout
| leaves D1 = -1 (NE) without writing, which the callers do not catch.
LAP_SENDBYTE:
        MOVEQ.L #0x1E,D1                        | 31 polls
LAP_SENDBYTE_LOOP:
        BTst    #0x2,(A0)                       | RR0: Tx buffer empty?
        DBNE    D1,LAP_SENDBYTE_LOOP            | no -> poll again
        BEQ.B   LAP_SENDBYTE_EXIT               | timeout -> no write
        MOVE.B  D3,0x4(A1)                      | write the byte
LAP_SENDBYTE_EXIT:
        TST     D1                              | EQ if D1 = 0
        RTS                                     | return from LAP_SENDBYTE

| ----------------------------------------------------------
|
| LAP_TXON: turn the transmitter on (LAP_TXON_TBL), let it send flags for
| a moment, then reset the Tx CRC generator
|
LAP_TXON:
        LEA.L   LAP_TXON_TBL(PC),A3             | A3 = SCC writes
        MOVEQ.L #0x4,D3                         | 4 bytes
        BSR     LAP_SCCWRITE                    | write them
        MOVEQ.L #0x28,D3                        | 41 iterations
LAP_TXON_DELAY:
        DBF     D3,LAP_TXON_DELAY               | opening flags go out meanwhile
        MOVE.B  #0x80,(A1)                      | WR0 = $80: reset Tx CRC generator
        RTS                                     | return from LAP_TXON

| ----------------------------------------------------------
|
| LAP_SENDFRAME: send the frame of the WDS at WDSPtr (lapSrcAdr filled in
| with our node), then CRC, closing flag and abort (LAP_ENDFRAME).
| Interrupts are off: received modem-port bytes (VIA PA7 low) are pushed
| on the stack and handed to PollProc afterwards.
|
LAP_SENDFRAME:
        MOVEM.L A0-A1/A4-A6,0xDE(A2)            | save registers (SaveRegs)
        MOVE.L  (DskRtnAdr).w,-(SP)             | save DskRtnAdr
        MOVE.L  (PollStack).w,-(SP)             | save PollStack
        MOVE.L  A7,(PollStack).w                | PollStack = start of the polled bytes
        MOVE.L  0xF2(A2),A5                     | A5 = VIA vBufA (PA7 = SCC W/REQ)
        LEA.L   0x6(A0),A6                      | A6 = SCC channel A data (read)
        MOVE.L  0xA2(A2),A4                     | A4 = WDS (WDSPtr)
        BSR.B   LAP_TXON                        | transmitter on
        MOVE    (A4)+,D3                        | D3 = length of the first entry
        MOVE.L  (A4)+,A3                        | A3 = its data (frame header)
        MOVE.B  (A3)+,0x4(A1)                   | send lapDstAdr
        SUBQ.W  #0x1,D3                         | one byte less
        MOVE.B  (A2),(A3)                       | lapSrcAdr = sysLAPAddr
| byte loop
LAP_SENDFRAME_LOOP:
        MOVEQ.L #0x1E,D0                        | 31 polls
LAP_SENDFRAME_WAIT:
        BTst    #0x2,(A0)                       | RR0: Tx buffer empty?
        DBNE    D0,LAP_SENDFRAME_WAIT           | no -> poll again
        BNE.B   LAP_SENDFRAME_BYTE              | yes ->
        BSR.B   LAP_TXOFF                       | timeout: transmitter off
        BRA.B   LAP_SENDFRAME_POLL              | -> finish

| ----------------------------------------------------------
|
| LAP_SENDFRAME_BYTE
|
| send the next byte; save a modem-port byte, if one arrived
LAP_SENDFRAME_BYTE:
        MOVE.B  (A3)+,0x4(A1)                   | next byte to the Tx buffer
        TST.B   (A5)                            | VIA PA7 low (channel A byte waiting)?
        BMI.B   LAP_SENDFRAME_COUNT             | no ->
        MOVE.B  (A6),-(SP)                      | yes: push it for PollProc
LAP_SENDFRAME_COUNT:
        SUBQ.W  #0x1,D3                         | count
        BGT.B   LAP_SENDFRAME_LOOP              | more in this entry ->
        MOVE    (A4)+,D3                        | D3 = length of the next entry
        BEQ.B   LAP_SENDFRAME_END               | 0 = end of WDS ->
        MOVE.L  (A4)+,A3                        | A3 = its data
        BRA.B   LAP_SENDFRAME_LOOP              | send it

| ----------------------------------------------------------
|
| LAP_SENDFRAME_END
|
| all bytes sent: end the frame
LAP_SENDFRAME_END:
        BSR.B   LAP_ENDFRAME                    | CRC, flag, abort, transmitter off
| let PollProc process the saved modem-port bytes
LAP_SENDFRAME_POLL:
        MOVE.L  (PollProc).w,D3                 | PollProc installed?
        BEQ.B   LAP_SENDFRAME_EXIT              | no ->
        MOVE.L  D3,A4                           | A4 = PollProc
        JSR     (A4)                            | call it
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables again
LAP_SENDFRAME_EXIT:
        MOVEM.L 0xDE(A2),A0-A1/A4-A6            | restore registers
        MOVE.L  (PollStack).w,SP                | drop the polled bytes
        MOVE.L  (SP)+,(PollStack).w             | restore PollStack
        MOVE.L  (SP)+,(DskRtnAdr).w             | restore DskRtnAdr
        RTS                                     | return from LAP_SENDFRAME

| ----------------------------------------------------------
|
| LAP_SENDCTL: send a LAP control frame: lapDstAdr = D2, lapSrcAdr =
| sysLAPAddr, lapType = D0.B ($81 lapENQ, $82 lapACK, $84 lapRTS,
| $85 lapCTS); falls into LAP_ENDFRAME
|
LAP_SENDCTL:
        BSR     LAP_TXON                        | transmitter on
        MOVE.B  D2,0x4(A1)                      | send lapDstAdr
        MOVE.B  (A2),D3                         | D3 = sysLAPAddr
        BSR     LAP_SENDBYTE                    | send lapSrcAdr
        BEQ.B   LAP_TXOFF                       | (see LAP_SENDBYTE) -> transmitter off
        MOVE.B  D0,D3                           | D3 = lapType
        BSR     LAP_SENDBYTE                    | send it
        BEQ.B   LAP_TXOFF                       | (see LAP_SENDBYTE) -> transmitter off
| LAP_ENDFRAME: let the SCC append CRC and closing flag at the underrun,
| then hold the line marking (abort sequence) and turn the transmitter off
LAP_ENDFRAME:
        MOVE.B  #0xC0,(A1)                      | WR0 = $C0: reset Tx underrun/EOM latch
        LSL     #0x1,D3                         | delay
LAP_ENDFRAME_EOM:
        BTst    #0x6,(A0)                       | RR0: Tx underrun/EOM (CRC being sent)?
        BEQ.B   LAP_ENDFRAME_EOM                | no -> wait
LAP_ENDFRAME_TBE:
        BTst    #0x2,(A0)                       | RR0: Tx buffer empty?
        BEQ.B   LAP_ENDFRAME_TBE                | no -> wait
        MOVE.B  #0x5,(A1)                       | WR0: select WR5
        MOVEQ.L #0x0,D3                         | D3.W = 0
        MOVE.B  #0x62,(A1)                      | WR5 = $62: Tx off, RTS on: line marks (abort)
        MOVE.B  0xB9(A2),D3                     | D3 = abort-sequence delay
LAP_ENDFRAME_ABORT:
        DBF     D3,LAP_ENDFRAME_ABORT           | wait
| LAP_TXOFF: write VSTData - WR5 = $60 (RTS off), WR14 = $41 (DPLL reset
| missing clock, BRG on), WR3 = $DD (receiver on, hunt mode)
LAP_TXOFF:
        LEA.L   0xF6(A2),A3                     | A3 = VSTData
        MOVEQ.L #0x6,D3                         | 6 bytes
| LAP_SCCWRITE: write D3 bytes from (A3) to the channel B control register
LAP_SCCWRITE:
        MOVE.B  (A3)+,(A1)                      | next byte
        SUBQ.W  #0x1,D3                         | count
        BNE.B   LAP_SCCWRITE                    | loop
        RTS                                     | return from LAP_SCCWRITE

| ----------------------------------------------------------
|
| LAP_RCVINT: SCC channel B receive interrupt (Lvl2DT[2]); A0/A1 = SCC
| channel B control.  LAP_RCVFRAME (also from LAP_POLLRCV): read lapDstAdr,
| lapSrcAdr, lapType into the RHA; control frames -> LAP_RCVCTL; data
| frames: read the length word and jump to the protocol handler (A4 =
| LAP_READ_JT, D1 = bytes left, A3 -> RHA, A4/A5 saved in SaveA45).
|
LAP_RCVINT:
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
| LAP_RCVFRAME
LAP_RCVFRAME:
        LEA.L   0x1(A2),A3                      | A3 = RHA (toRHA)
        MOVE.B  0x4(A0),(A3)+                   | lapDstAdr
        MOVEQ.L #0x28,D1                        | poll budget for the header
LAP_RCVFRAME_SRC:
        BTst    #0x0,(A0)                       | RR0: Rx character available?
        DBNE    D1,LAP_RCVFRAME_SRC             | no -> poll again
        BEQ.B   LAP_RCVFRAME_TIMEOUT            | timeout ->
        MOVE.B  0x4(A0),(A3)+                   | lapSrcAdr
LAP_RCVFRAME_TYPE:
        BTst    #0x0,(A0)                       | Rx character available?
        DBNE    D1,LAP_RCVFRAME_TYPE            | no -> poll again
        BEQ.B   LAP_RCVFRAME_TIMEOUT            | timeout ->
        MOVE.B  0x4(A0),D0                      | D0 = lapType
        MOVE.B  D0,(A3)+                        | into the RHA
        BMI.B   LAP_RCVCTL                      | $80-$FF: control frame ->
| find the protocol handler of the type
        MOVEQ.L #0x3,D2                         | 4 entries
LAP_RCVFRAME_FINDPH:
        CMP.B   0x22(A2,D2.W),D0                | this type?
        DBEQ    D2,LAP_RCVFRAME_FINDPH          | no -> next
        LSL     #0x2,D2                         | long index (negative: none)
| length word (10 bits, includes itself)
        MOVEQ.L #0x28,D0                        | poll budget
LAP_RCVFRAME_LEN1:
        BTst    #0x0,(A0)                       | Rx character available?
        DBNE    D0,LAP_RCVFRAME_LEN1            | no -> poll again
        BEQ.B   LAP_RCVFRAME_TIMEOUT            | timeout ->
        MOVE.B  0x4(A0),(A3)                    | length high byte
        MOVEQ.L #0x3,D1                         | 2 bits
        AND.B   (A3)+,D1                        | D1 = length bits 9-8
        LSL     #0x8,D1                         | to bits 9-8
        MOVEM.L A4-A5,0xBA(A2)                  | save A4/A5 (SaveA45)
LAP_RCVFRAME_LEN2:
        BTst    #0x0,(A0)                       | Rx character available?
        DBNE    D0,LAP_RCVFRAME_LEN2            | no -> poll again
LAP_RCVFRAME_TIMEOUT:
        BEQ.B   LAP_SPECIALINT                  | timeout -> discard the frame
        MOVE.B  0x4(A0),D1                      | length bits 7-0
        MOVE.B  D1,(A3)+                        | into the RHA
        SUBQ.W  #0x2,D1                         | D1 = bytes left after the length word
        TST     D2                              | protocol handler found?
        BMI.B   LAP_RCVFRAME_NOPH               | no ->
        MOVE.L  0x26(A2,D2.W),A5                | A5 = protocol handler
        LEA.L   LAP_READ_JT(PC),A4              | A4 = ReadPacket/ReadRest jump table
        JMP     (A5)                            | -> protocol handler

| ----------------------------------------------------------
|
| LAP_RCVFRAME_NOPH: no handler for the type - read and drop the rest
| (ReadRest with no buffer), unless the frame has already ended
|
LAP_RCVFRAME_NOPH:
        MOVE.B  #0x1,(A1)                       | WR0: select RR1
        MOVEQ.L #-0x60,D0                       | $A0
        AND.B   (A0),D0                         | RR1: end of frame or Rx overrun?
        BNE     LAP_LENERR                      | yes -> error, reset the receiver
        CLR     D3                              | buffer size 0
        BRA     READREST                        | read and drop the rest

| ----------------------------------------------------------
|
| LAP_RCVCTL: control frame (lapType in D0).  Reads the CRC.  While our
| address is not yet valid, a frame sent to it (not broadcast) means the
| address is taken (fAdrInUse).  Else: lapENQ -> answer lapACK; lapRTS ->
| answer lapCTS (not to a broadcast), then receive the data frame;
| fGoodCTS = (frame is lapCTS).
|
LAP_RCVCTL:
        MOVEQ.L #0x7F,D2                        | mask
        AND.B   D0,D2                           | D2 = lapType - $80
        CMPI.B  #0x5,D2                         | above $85?
        BGT.B   LAP_SPECIALINT                  | yes -> discard
        BSR.B   LAP_RCVCRC                      | read the CRC, check the frame
        BNE.B   LAP_RCVCTL_EXIT                 | bad -> return
        CMPI.B  #0xFF,0x1(A2)                   | lapDstAdr = $FF (broadcast)?
        SEQ.B   D1                              | D1 = $FF if broadcast
        BEQ.B   LAP_RCVCTL_TYPE                 | broadcast -> process
        TST.B   0xAD(A2)                        | fLAPAdrValid?
        BNE.B   LAP_RCVCTL_TYPE                 | yes -> process
        ST.B    0xAF(A2)                        | no: fAdrInUse
LAP_RCVCTL_EXIT:
        RTS                                     | return

| ----------------------------------------------------------
|
| LAP_RCVCTL_TYPE: dispatch on the control frame type
|
LAP_RCVCTL_TYPE:
        SUBQ.B  #0x1,D2                         | $81 lapENQ?
        BEQ.B   LAP_RCVCTL_ENQ                  | yes -> answer lapACK
        SUBQ.B  #0x3,D2                         | $84 lapRTS?
        BEQ.B   LAP_RCVCTL_RTS                  | yes -> answer lapCTS
        SUBQ.B  #0x1,D2                         | $85 lapCTS?
        SEQ.B   0xAE(A2)                        | fGoodCTS = (lapCTS)
        RTS                                     | return

| ----------------------------------------------------------
|
| LAP_RCVCTL_RTS: lapRTS - answer lapCTS unless it was broadcast, then
| receive the data frame that follows
|
LAP_RCVCTL_RTS:
        TST.B   D1                              | broadcast?
        BNE.B   LAP_RCVCTL_DATA                 | yes: no lapCTS ->
        MOVEQ.L #0x14,D0                        | 21 iterations
LAP_RCVCTL_DELAY:
        DBF     D0,LAP_RCVCTL_DELAY             | short delay
        MOVEQ.L #-0x7B,D0                       | D0 = $85 (lapCTS)
        BSR.B   LAP_REPLYCTL                    | send it to the sender
LAP_RCVCTL_DATA:
        BRA     LAP_POLLRCV                     | receive the data frame

| ----------------------------------------------------------
|
| LAP_RCVCTL_ENQ
|
| lapENQ for our address: answer lapACK
LAP_RCVCTL_ENQ:
        MOVEQ.L #-0x7E,D0                       | D0 = $82 (lapACK)
| LAP_REPLYCTL: send control frame D0 to the sender (lapSrcAdr in the RHA)
LAP_REPLYCTL:
        MOVE.B  0x2(A2),D2                      | D2 = lapSrcAdr of the received frame
        BRA     LAP_SENDCTL                     | send it

| ----------------------------------------------------------
|
| LAP_SPECIALINT: SCC channel B special receive condition (Lvl2DT[3]),
| also used to drop a frame: reset the receiver (twice)
|
LAP_SPECIALINT:
        BSR.B   LAP_RCVRESET                    | reset the receiver
        BRA.B   LAP_RCVRESET                    | and once more

| ----------------------------------------------------------
|
| LAP_RCVCRC: read the two CRC bytes that end the frame: the first must
| not, the second must have end of frame, without CRC error; then reset
| the receiver.  D0 = 0 or overrunErr (-1), crcErr (-2), underrunErr
| (-3, timeout), lengthErr (-4); condition codes from D0.
|
LAP_RCVCRC:
        CLR     D0                              | D0 = noErr
        MOVEQ.L #0x10,D1                        | 17 polls
LAP_RCVCRC_WAIT1:
        BTst    #0x0,(A0)                       | RR0: Rx character available?
        DBNE    D1,LAP_RCVCRC_WAIT1             | no -> poll again
        BEQ.B   LAP_UNDERRUN                    | timeout -> underrunErr
        BSR.B   LAP_GETRR1                      | D1 = RR1
        BMI.B   LAP_LENERR                      | end of frame already: frame short -> lengthErr
        TST.B   0x4(A0)                         | read (drop) the first CRC byte
        MOVEQ.L #0x10,D1                        | 17 polls
LAP_RCVCRC_WAIT2:
        BTst    #0x0,(A0)                       | Rx character available?
        DBNE    D1,LAP_RCVCRC_WAIT2             | no -> poll again
        BEQ.B   LAP_UNDERRUN                    | timeout -> underrunErr
        BSR.B   LAP_GETRR1                      | D1 = RR1
        BPL.B   LAP_LENERR                      | no end of frame: frame long -> lengthErr
        LSL.B   #0x1,D1                         | RR1 bit 6 (CRC error) -> N
        BMI.B   LAP_CRCERR                      | CRC error -> crcErr
| LAP_RCVRESET: re-arm the receiver for the next frame: receiver off and
| hunt, drain the 3-byte FIFO, receiver on (hunt, address search), error
| reset, interrupt on the next character.  Condition codes from D0.
LAP_RCVRESET:
        BSR.B   LAP_GETRR1                      | D1 = RR1
        BTST    #0x5,D1                         | Rx overrun?
        BEQ.B   LAP_RCVRESET_HUNT               | no ->
        BCLR    #0x7,(IntFlag).w                | IntFlag bit 7 = 0: ask for shorter interrupts-off periods
LAP_RCVRESET_HUNT:
        MOVEQ.L #-0x30,D1                       | $D0
        BSR.B   LAP_SETWR3                      | WR3 = $D0: receiver off, enter hunt mode
        MOVEQ.L #0x2,D1                         | 3 bytes
LAP_RCVRESET_DRAIN:
        TST.B   0x4(A0)                         | read (drop) a FIFO byte
        DBF     D1,LAP_RCVRESET_DRAIN           | loop
        MOVEQ.L #-0x23,D1                       | $DD
        BSR.B   LAP_SETWR3                      | WR3 = $DD: Rx on, 8 bits, hunt, CRC, address search
        MOVE.B  #0x30,(A1)                      | WR0 = $30: error reset
        MOVE    (SP),(SP)                       | delay (SCC recovery time)
        MOVE.B  #0x20,(A1)                      | WR0 = $20: enable interrupt on next Rx character
        TST     D0                              | condition codes = result
        RTS                                     | return

| ----------------------------------------------------------
|
| LAP_SETWR3: WR3 = D1
|
LAP_SETWR3:
        MOVE.B  #0x3,(A1)                       | WR0: select WR3
        NOP                                     | SCC recovery time
        MOVE.B  D1,(A1)                         | WR3 = D1
        RTS                                     | return from LAP_SETWR3

| ----------------------------------------------------------
|
| LAP_GETRR1: D1 = RR1 (bit 7 end of frame, 6 CRC error, 5 Rx overrun)
|
LAP_GETRR1:
        MOVE.B  #0x1,(A1)                       | WR0: select RR1
        NOP                                     | SCC recovery time
        MOVE.B  (A0),D1                         | D1 = RR1
        RTS                                     | return from LAP_GETRR1

| ----------------------------------------------------------
|
| LAP_LENERR / LAP_UNDERRUN / LAP_CRCERR / LAP_OVERRUN: subtract from D0
| (0 on entry) down to the error code, then reset the receiver
|
LAP_LENERR:
        BTst    #0x5,D1                         | Rx overrun?
        BNE.B   LAP_OVERRUN                     | yes -> overrunErr
        MOVEQ.L #-0x1,D0                        | lengthErr path: from -1 down to -4
LAP_UNDERRUN:
        SUBQ.W  #0x1,D0                         | underrunErr entry (D0 = 0): down to -3
LAP_CRCERR:
        SUBQ.W  #0x1,D0                         | crcErr entry (D0 = 0): down to -2
LAP_OVERRUN:
        SUBQ.W  #0x1,D0                         | overrunErr entry (D0 = 0): -1
        BRA.B   LAP_RCVRESET                    | reset the receiver

| ----------------------------------------------------------
|
| LAP_READ_JT: A4 for protocol handlers and socket listeners - JSR (A4) =
| ReadPacket, JSR 2(A4) = ReadRest
|
LAP_READ_JT:
        BRA.B   READPACKET                      | (A4): ReadPacket; 2(A4) = READREST below

| ----------------------------------------------------------
|
| READREST: read the rest of the packet (D1 bytes left) into the buffer
| at A3, D3 bytes long (excess bytes are dropped), then check the CRC
| (LAP_RCVCRC).  D3 = 0 if it fit exactly, > 0 if bytes were left
| unfilled, < 0 if (-D3) bytes did not fit.  Saves modem-port bytes for
| PollProc.  Restores A4/A5; condition codes / D0 = result.
|
READREST:
        MOVE.L  0xF2(A2),A5                     | A5 = VIA vBufA (PA7 = SCC W/REQ)
        MOVE.L  A7,A4                           | A4 = start of the polled bytes
| byte loop
READREST_LOOP:
        MOVEQ.L #0x10,D0                        | 17 polls
        SUBQ.W  #0x1,D1                         | one byte less to go
        BMI.B   READREST_END                    | all read ->
READREST_WAIT:
        BTst    #0x0,(A0)                       | RR0: Rx character available?
        DBNE    D0,READREST_WAIT                | no -> poll again
        BEQ.B   READREST_END                    | timeout -> end
        MOVE.B  0x4(A0),D0                      | D0 = data byte
        TST.B   (A5)                            | VIA PA7 low (channel A byte waiting)?
        BMI.B   READREST_STORE                  | no ->
        MOVE.B  0x6(A0),-(SP)                   | yes: push it for PollProc
READREST_STORE:
        SUBQ.W  #0x1,D3                         | room in the buffer?
        BMI.B   READREST_LOOP                   | no -> drop the byte
        MOVE.B  D0,(A3)+                        | store it
        BRA.B   READREST_LOOP                   | next byte

| ----------------------------------------------------------
|
| READREST_END
|
| end of packet: CRC, then let PollProc have the saved modem-port bytes
READREST_END:
        BSR     LAP_RCVCRC                      | CRC, end of frame; D0 = result
        MOVE.L  (PollStack).w,0xC6(A2)          | save PollStack (SavePS)
        MOVE.L  A4,(PollStack).w                | PollStack = start of the polled bytes
        MOVE.L  (PollProc).w,D1                 | PollProc installed?
        BEQ.B   READREST_NOPOLL                 | no ->
        MOVEM.L D0/D2-D3/A3/A6,0xDE(A2)         | save registers (SaveRegs)
        LEA.L   0x6(A0),A6                      | A6 = SCC channel A data (read)
        MOVE.L  D1,A0                           | A0 = PollProc
        MOVE.L  (DskRtnAdr).w,0xC2(A2)          | save DskRtnAdr (SaveDskRtn)
        JSR     (A0)                            | call PollProc
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables again
        MOVE.L  0xC2(A2),(DskRtnAdr).w          | restore DskRtnAdr
        MOVEM.L 0xDE(A2),D0/D2-D3/A3/A6         | restore registers
READREST_NOPOLL:
        MOVE.L  (PollStack).w,SP                | drop the polled bytes
        MOVE.L  0xC6(A2),(PollStack).w          | restore PollStack
| READ_EXIT: restore A4/A5 (SaveA45), condition codes from D0
READ_EXIT:
        MOVEM.L 0xBA(A2),A4-A5                  | restore A4/A5
        TST     D0                              | condition codes = result
READPACKET_EXIT:
        RTS                                     | return

| ----------------------------------------------------------
|
| READPACKET: read D3 bytes of the packet into (A3)+; D1 -= D3.  D0/
| condition codes = 0 if all were read; on overrunErr (-1), underrunErr
| (-3, timeout) or lengthErr (-4, frame ended early) the receiver is
| reset and A4/A5 restored (the caller must just return).
|
READPACKET:
        SUB     D3,D1                           | bytes left after this read
READPACKET_LOOP:
        MOVEQ.L #0x10,D0                        | 17 polls
READPACKET_WAIT:
        BTst    #0x0,(A0)                       | RR0: Rx character available?
        DBNE    D0,READPACKET_WAIT              | no -> poll again
        BEQ.B   READPACKET_TIMEOUT              | timeout ->
        MOVE.B  0x4(A0),(A3)+                   | store the byte
        SUBQ.W  #0x1,D3                         | count
        BNE.B   READPACKET_LOOP                 | loop (ends with D3 = 0)
| frame ended early or overrun?
        MOVE.B  #0x1,(A1)                       | WR0: select RR1
        MOVEQ.L #-0x60,D0                       | $A0
        AND.B   (A0),D0                         | RR1: end of frame / Rx overrun?
        BEQ.B   READPACKET_EXIT                 | neither -> return (EQ)
        BMI.B   READPACKET_LENERR               | end of frame -> lengthErr
        MOVEQ.L #-0x1,D0                        | overrunErr (-1)
        BRA.B   READPACKET_ERR                  | ->

| ----------------------------------------------------------
|
| READPACKET_TIMEOUT: no byte came - underrunErr
|
READPACKET_TIMEOUT:
        MOVEQ.L #-0x3,D0                        | underrunErr (-3)
        BRA.B   READPACKET_ERR                  | ->

| ----------------------------------------------------------
|
| READPACKET_LENERR: frame shorter than its length word - lengthErr
|
READPACKET_LENERR:
        MOVEQ.L #-0x4,D0                        | lengthErr (-4)
READPACKET_ERR:
        BSR     LAP_RCVRESET                    | reset the receiver
        BRA.B   READ_EXIT                       | restore A4/A5, return NE

| ----------------------------------------------------------
|
| E_MPP_Close
|
| .MPP Close: closes .ATP (atpVars flag set first), resets SCC channel B
| (mouse interrupt kept), removes the VBL task and the interrupt
| handlers, gives units 7/8 (.BIn/.BOut) back and frees the variables.
E_MPP_Close:
        MOVE.L  (UTableBase).w,A4               | A4 = unit table
        ADDA    #0x28,A4                        | A4 -> unit 10 (.ATP) entry
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
        MOVE.L  A2,D0                           | .MPP open?
        BEQ     E_MPP_CLOSE_PORT                | no -> only release the port
| close .ATP
        ST.B    0x1E(A2)                        | atpVars flag byte: .ATP must not call .MPP
        SUBA    #0x32,SP                        | parameter block on the stack
        MOVE.L  A7,A0                           | A0 = it
        MOVE    #-0xB,0x18(A0)                  | ioRefNum = -11 (.ATP)
        _Close                                  | close .ATP
        ADDA    #0x32,SP                        | drop the parameter block
| SCC, VBL task, interrupt handlers
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        LEA.L   MPP_SCCRESET_TBL(PC),A0         | A0 = SCC table
        BSR.B   MPP_SCCINIT                     | reset channel B
        LEA.L   0x7C(A2),A0                     | A0 = VBL task
        _VRemove                                | remove it
        LEA.L   0xD2(A2),A0                     | A0 = SaveVects
        LEA.L   (Lvl2DT_2).w,A3                 | A3 = Lvl2DT[2]
        MOVE.L  (A0)+,(A3)+                     | Lvl2DT[2]: channel B Rx character
        MOVE.L  (A0)+,(A3)+                     | Lvl2DT[3]: channel B special receive
        MOVE.L  (A0)+,(ExtStsDT).w              | ExtStsDT[0]: channel B external/status
| give units 8 (.BOut) and 7 (.BIn) back
        MOVE.L  -(A4),A0                        | A4 -> unit 9 (.MPP) entry (A0 not used)
        MOVE.L  0xCE(A2),D0                     | SaveBOut
        BEQ.B   E_MPP_CLOSE_BIN                 | none ->
        MOVE.L  D0,-0x4(A4)                     | unit 8 = .BOut DCE handle
E_MPP_CLOSE_BIN:
        MOVE.L  0xCA(A2),D0                     | SaveBIn
        BEQ.B   E_MPP_CLOSE_FREE                | none ->
        MOVE.L  D0,-0x8(A4)                     | unit 7 = .BIn DCE handle
E_MPP_CLOSE_FREE:
        MOVE    (SP)+,SR                        | restore SR
        MOVE.L  A2,A0                           | A0 = MPP variables
        _DisposePtr                             | free them
E_MPP_CLOSE_PORT:
        ST.B    (PortBUse).w                    | PortBUse = $FF: port B free
E_MPP_CLOSE_EXIT:
        RTS                                     | return

| ----------------------------------------------------------
|
| MPP_SCCINIT: write a table of words (value << 8) + register to SCC
| channel B (register number, then value) up to a 0 word
|
MPP_SCCINIT:
        MOVE.L  (SCCWr).w,A3                    | A3 = SCC channel B control (write)
MPP_SCCINIT_LOOP:
        MOVE    (A0)+,D0                        | D0 = next word
        BEQ.B   E_MPP_CLOSE_EXIT                | 0 = end -> return
        MOVE.B  D0,(A3)                         | WR0: register number (low byte)
        ROR     #0x8,D0                         | value to the low byte
        MOVE.B  D0,(A3)                         | write the value
        BRA.B   MPP_SCCINIT_LOOP                | next word

| ----------------------------------------------------------
|
| MPP_SCCRESET_TBL
|
| MPP_SCCRESET_TBL: channel B after Close - reset, mouse Y (DCD) on
MPP_SCCRESET_TBL:
  .byte  0x4A,0x09,0x00,0x0A,0x10,0x00          | WR9 = $4A (reset channel B, MIE, NV), WR10 = 0, WR0 = $10 (reset ext/status)
  .byte 0x08,0x0F,0x01,0x01,0x00,0x00           | WR15 = $08 (DCD interrupt), WR1 = $01 (ext/status int. on), end

| .MPP Open: port B must be free (PortBUse < 0) and configured for
| AppleTalk or unconfigured (SPConfig); allocates the variables, takes
| units 7/8 (.BIn/.BOut, if not opened) out of the unit table, sets up
| SCC channel B for LocalTalk, picks a node ID (PRAM hint SPATalkB, else
| random) and sends lapENQs until no node answers, installs DDP and
| the RTMP socket, asks for a router (RTMP request), opens .ATP and
| initializes NBP.  portInUse, portNotCf, memFullErr.
E_MPP_Open:
        MOVEQ.L #-0x61,D0                       | portInUse (-97)
        TST.B   (PortBUse).w                    | port B in use (>= 0)?
        BPL.B   E_MPP_CLOSE_EXIT                | yes -> return portInUse
| SPConfig: port B use type must be useFree (0) or useATalk (1)
        MOVEQ.L #-0x62,D0                       | portNotCf (-98)
        MOVE.B  (SPConfig).w,D1                 | SPConfig
        ANDI.B  #0xF,D1                         | port B use type (low nibble)
        SUBQ.B  #0x1,D1                         | > useATalk?
        BGT.B   E_MPP_CLOSE_EXIT                | yes -> return portNotCf
| allocate the MPP variables
        CLR.L   (ABusVars).w                    | ABusVars = nil meanwhile
        MOVE.L  #0xFC,D0                        | $FC = 252 bytes
        _NewPtrSysClear                         | zeroed block in the system heap
        BNE.B   E_MPP_CLOSE_EXIT                | out of memory -> return
| initialize
        MOVE.B  #0x1,(PortBUse).w               | PortBUse = useATalk (1)
        MOVE.L  A0,A2                           | A2 = MPP variables
        MOVE.L  A2,(ABusVars).w                 | ABusVars
        MOVE.L  A1,(ABusVars_dce).w             | AbusDCE = .MPP DCE
| take unit 8 (.BOut) out of the unit table unless it has been opened
        MOVE.L  (UTableBase).w,A0               | A0 = unit table
        MOVE.L  0x20(A0),A3                     | A3 = unit 8 DCE handle (.BOut)
        MOVE.L  A3,D0                           | installed?
        BEQ.B   E_MPP_OPEN_BIN                  | no ->
        MOVE.L  (A3),A3                         | A3 = DCE
        TST.B   0x7(A3)                         | dCtlQueue+1 (version, set by its Open)?
        BNE.B   E_MPP_OPEN_BIN                  | set: driver in use -> leave it
        MOVE.L  D0,0xCE(A2)                     | SaveBOut
        CLR.L   0x20(A0)                        | remove it from the unit table
| the same for unit 7 (.BIn)
E_MPP_OPEN_BIN:
        MOVE.L  0x1C(A0),A3                     | A3 = unit 7 DCE handle (.BIn)
        MOVE.L  A3,D0                           | installed?
        BEQ.B   E_MPP_OPEN_PHTBL                | no ->
        MOVE.L  (A3),A3                         | A3 = DCE
        TST.B   0x7(A3)                         | dCtlQueue+1 (version, set by its Open)?
        BNE.B   E_MPP_OPEN_PHTBL                | set: driver in use -> leave it
        MOVE.L  D0,0xCA(A2)                     | SaveBIn
        CLR.L   0x1C(A0)                        | remove it from the unit table
| all 4 LAP protocol table entries free
E_MPP_OPEN_PHTBL:
        MOVEQ.L #0x3,D0                         | 4 entries
E_MPP_OPEN_PHLOOP:
        ST.B    0x22(A2,D0.W)                   | protocol type $FF = free
        DBF     D0,E_MPP_OPEN_PHLOOP            | loop
| LAP configuration from MPP_CONFIG_TBL
        LEA.L   MPP_CONFIG_TBL(PC),A1           | A1 = configuration table
        LEA.L   (VIA_PortA2).l,A0               | A0 = VIA vBufA (PA7 = SCC W/REQ)
        MOVE.L  A0,0xF2(A2)                     | +$F2 = its address
        MOVE.L  (A1)+,0xF6(A2)                  | VSTData bytes 0-3
        MOVE    (A1)+,0xFA(A2)                  | VSTData bytes 4-5
        MOVE    (A1)+,0x1C(A2)                  | vSCCEnable = $2100
        MOVE.B  (A1)+,0xB9(A2)                  | abort-sequence delay = $46
| install the interrupt handlers and the VBL task, set up the SCC
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
| SCC channel B vectors; the old ones go to SaveVects
        LEA.L   (Lvl2DT_2).w,A3                 | A3 = Lvl2DT[2]
        LEA.L   0xD2(A2),A1                     | A1 = SaveVects
        LEA.L   LAP_RCVINT(PC),A0               | Rx character handler
        MOVE.L  (A3),(A1)+                      | save the old Lvl2DT[2]
        MOVE.L  A0,(A3)+                        | Lvl2DT[2] = LAP_RCVINT
        LEA.L   LAP_SPECIALINT(PC),A0           | special receive condition handler
        MOVE.L  (A3),(A1)+                      | save the old Lvl2DT[3]
        MOVE.L  A0,(A3)+                        | Lvl2DT[3] = LAP_SPECIALINT
        LEA.L   LAP_EXTINT(PC),A0               | external/status handler
        MOVE.L  (ExtStsDT).w,(A1)               | save the old ExtStsDT[0]
        MOVE.L  A0,(ExtStsDT).w                 | ExtStsDT[0] = LAP_EXTINT
| VBL task
        LEA.L   0x7C(A2),A0                     | A0 = VBL task (+$7C)
        MOVE    #0x1,0x4(A0)                    | qType = vType (1)
        LEA.L   MPP_VBLTASK(PC),A1              | A1 = MPP_VBLTASK
        MOVE.L  A1,0x6(A0)                      | vblAddr
        MOVE    #0x14,0xA(A0)                   | vblCount = 20 ticks
        _VInstall                               | install it
        BSR     MPP_SCCSETUP                    | SCC channel B for LocalTalk
        MOVE    (Ticks_LoWord).w,0xAA(A2)       | RandomSeed = Ticks
        MOVE    (SP)+,SR                        | restore SR
| node ID: the hint in PRAM if 1..127, else random
        MOVE.B  (SPATalkB).w,D0                 | D0 = SPATalkB (node ID hint)
        BGT.B   E_MPP_OPEN_TRYNODE              | 1..127 -> try it
E_MPP_OPEN_RANDOM:
        BSR     MPP_RANDOM                      | D0 = random number
E_MPP_OPEN_TRYNODE:
        ANDI    #0x7F,D0                        | 0..127
        BEQ.B   E_MPP_OPEN_RANDOM               | 0 -> another one
| claim it: 20 rounds of lapENQ to that address must stay unanswered
        MOVEQ.L #0x13,D4                        | 20 rounds
        MOVE.B  D0,(A2)                         | sysLAPAddr = candidate
        CLR.B   0xAD(A2)                        | fLAPAdrValid = 0
        MOVE.L  (SCCWr).w,A1                    | A1 = SCC channel B control (write)
        MOVE.B  #0x6,(A1)                       | WR0: select WR6
        CLR.B   0xAF(A2)                        | fAdrInUse = 0
        MOVE.B  (A2),(A1)                       | WR6 = node ID (SDLC address for the address search)
E_MPP_OPEN_ENQLOOP:
        ST.B    0xB0(A2)                        | fSendENQ
        MOVE.B  (A2),D2                         | D2 = candidate address
        BSR     MPP_SENDENQ                     | send lapENQs to it
E_MPP_OPEN_ENQWAIT:
        TST.B   0xB0(A2)                        | write finished (fSendENQ cleared)?
        BNE.B   E_MPP_OPEN_ENQWAIT              | no -> wait
        TST.B   0xAF(A2)                        | fAdrInUse (somebody answered)?
        BNE.B   E_MPP_OPEN_RANDOM               | yes -> try another address
        DBF     D4,E_MPP_OPEN_ENQLOOP           | next round
| node ID is ours: keep it as the PRAM hint
        MOVE.B  (A2),(SPATalkB).w               | SPATalkB = node ID
        ST.B    0xAD(A2)                        | fLAPAdrValid
        LEA.L   (SysParam_SPValid).w,A0         | A0 = SysParam
        MOVEQ.L #-0x1,D0                        | all bytes (64K-ROM interface; ignored here)
        _WriteParam                             | write SysParam to the clock chip PRAM
| DDP protocol handlers: entries 3 (type 1) and 2 (type 2)
        LEA.L   DDP_RCVSHORT(PC),A3             | A3 = shortDDP handler
        LEA.L   0x36(A2),A0                     | A0 -> end of the handler table
        MOVE.L  A3,-(A0)                        | handler entry 3
        LEA.L   DDP_RCVLONG(PC),A3              | A3 = longDDP handler
        MOVE.L  A3,-(A0)                        | handler entry 2
| protocol types
        LEA.L   0x26(A2),A0                     | A0 -> end of the type table
        MOVE.B  #0x1,-(A0)                      | type entry 3 = 1 (shortDDP)
        MOVE.B  #0x2,-(A0)                      | type entry 2 = 2 (longDDP)
| RTMP socket 1 in socket table entry 13, then ask for a router
        LEA.L   RTMP_LISTENER(PC),A0            | A0 = RTMP listener
        MOVE.L  A0,0x78(A2)                     | listener of entry 13
        MOVE.B  #0x1,0x43(A2)                   | entry 13 = socket 1 (RTMP)
        BSR     MPP_RTMPREQUEST                 | broadcast an RTMP request
| JDDPWrite and LookupPtr (bit 31 clear: NIS opened by the first RegisterName)
        LEA.L   MPP_JDDPWRITE(PC),A0            | A0 = DDP jump table
        MOVE.L  A0,0x96(A2)                     | JDDPWrite
        LEA.L   LUCODE(PC),A3                   | A3 = lookup-reply code
        MOVE.L  A3,0x8E(A2)                     | LookupPtr
| open .ATP
        SUBA    #0x32,SP                        | parameter block on the stack
        LEA.L   MPP_ATPNAME(PC),A0              | A0 = ".ATP"
        MOVE.L  A0,0x12(SP)                     | ioNamePtr
        MOVE.L  A7,A0                           | A0 = parameter block
        CLR.B   0x1B(A0)                        | ioPermssn = 0
        _Open                                   | open .ATP
        ADDA    #0x32,SP                        | drop the parameter block
        MOVEQ.L #0x7,D3                         | NBP code entry 0 = NBP_INIT
        BSR     MPP_INSTALLNBP                  | install and initialize NBP
        TST     0x1A(A2)                        | sysNetNum known (router answered)?
        BNE.B   E_MPP_OPEN_DONE                 | yes ->
        BSR.B   MPP_RTMPREQUEST                 | no: ask once more
E_MPP_OPEN_DONE:
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE
        MOVE.B  #0x13,0x7(A1)                   | dCtlQueue+1: driver version 19
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from E_MPP_Open

| ----------------------------------------------------------
|
| MPP_RTMPREQUEST: broadcast an RTMP request (DDP type 5, socket 1 to
| socket 1) as a LAP frame built on the stack, and wait until it is sent.
| Routers answer with RTMP data, handled by RTMP_LISTENER.
|
MPP_RTMPREQUEST:
        CLR     -(SP)                           | WDS: terminator
        SUBQ.W  #0x4,SP                         | WDS: pointer (set below)
        MOVE    #0x9,-(SP)                      | WDS: length 9
        MOVE.L  A7,A1                           | A1 = WDS
        MOVE    #0x501,-(SP)                    | DDP type 5 (RTMP request), RTMP function 1
        MOVE    #0x101,-(SP)                    | dest socket 1, source socket 1
        MOVE    #0x6,-(SP)                      | ddpLength = 6
        MOVE    #0x1,-(SP)                      | lapSrcAdr (set when sent), lapType 1 (shortDDP)
        ST.B    D2                              | D2 = $FF (broadcast)
        MOVE    D2,-(SP)                        | lapDstAdr = $FF (after a pad byte)
        LEA.L   0x1(SP),A3                      | A3 = frame (9 bytes, odd address)
        MOVE.L  A3,0xB(A3)                      | WDS pointer = frame
        BSR.B   MPP_LAPSEND                     | send it, set +$B0 when done
MPP_RTMPREQUEST_WAIT:
        TST.B   0xB0(A2)                        | sent?
        BEQ.B   MPP_RTMPREQUEST_WAIT            | no -> wait
        ADDA    #0x12,SP                        | drop frame and WDS
        RTS                                     | return from MPP_RTMPREQUEST

| ----------------------------------------------------------
|
| MPP_LAPSEND: LAPWRITE, then set +$B0 (fSendENQ, here a 'sent' flag) when
| the write has finished (now or later from the deferred write)
|
MPP_LAPSEND:
        BSR     LAPWRITE                        | send the frame; resumes here when done
        ST.B    0xB0(A2)                        | sent
        RTS                                     | return

| ----------------------------------------------------------
|
| MPP_ATPNAME
|
| MPP_ATPNAME: driver name for the _Open of .ATP
MPP_ATPNAME:
  .byte  0x04,0x2E,0x41,0x54,0x50,0x20          | Pascal string ".ATP" and a pad byte
| MPP_SENDENQ: LAPWRITE_ENQ (lapENQs to D2), then clear fSendENQ when the
| write has finished
MPP_SENDENQ:
        BSR     LAPWRITE_ENQ                    | send lapENQ; resumes here when done
        CLR.B   0xB0(A2)                        | fSendENQ = 0: finished
        RTS                                     | return

| ----------------------------------------------------------
|
| MPP_SCCSETUP: program SCC channel B for LocalTalk (two tables)
|
MPP_SCCSETUP:
        LEA.L   MPP_SCCLAP_TBL(PC),A0           | A0 = first table
        BSR     MPP_SCCINIT                     | write it
        LEA.L   MPP_SCCLAP_TBL2(PC),A0          | A0 = second table
        BRA     MPP_SCCINIT                     | write it, return

| ----------------------------------------------------------
|
| MPP_SCCLAP_TBL
|
| MPP_SCCLAP_TBL: words (value << 8) + register for MPP_SCCINIT
MPP_SCCLAP_TBL:
  .byte  0x40,0x09,0x20,0x04,0xE0,0x0A          | WR9 = $40 reset channel B, WR4 = $20 SDLC x1, WR10 = $E0 FM0, CRC preset
  .byte 0x00,0x06,0x7E,0x07,0x06,0x0C           | WR6 = 0 (address), WR7 = $7E (flag), WR12 = 6 (BRG: ~230 kbit/s)
  .byte 0x00,0x0D,0xC0,0x0E,0xDD,0x03           | WR13 = 0, WR14 = $C0 (DPLL FM mode), WR3 = $DD (Rx on, hunt, CRC, address search)
  .byte 0x00,0x02,0x08,0x0F,0x09,0x01           | WR2 = 0, WR15 = $08 (DCD int.), WR1 = $09 (Rx int. first char/special, ext/status int.)
  .byte 0x0A,0x09,0x00,0x00                     | WR9 = $0A (MIE, NV), end
| MPP_SCCLAP_TBL2: clocks and transmitter
MPP_SCCLAP_TBL2:
  .byte 0x70,0x0B,0x21,0x0E,0x60,0x05           | WR11 = $70 (Rx clock DPLL, Tx clock BRG), WR14 = $21 (DPLL search, BRG on), WR5 = $60 (Tx off, RTS off)
  .byte 0x00,0x00                               | end
| MPP_CONFIG_TBL: copied by E_MPP_Open: VSTData (6), vSCCEnable,
| abort-sequence delay
MPP_CONFIG_TBL:
  .byte 0x05,0x60,0x0E,0x41,0x03,0xDD           | VSTData: WR5 = $60, WR14 = $41, WR3 = $DD
  .byte 0x21,0x00,0x46,0x00                     | vSCCEnable = $2100, delay $46, pad
  .ascii "COPYRIGHT (C) APPLE COMPUTER"         | copyright string
| LUCODE: lookup-reply code entry table (LookupPtr): +0 LookupReply,
| +2 goodbye kiss, +4 NIS socket listener
LUCODE:
        BRA.B   LUCODE_REPLY                    | +0: LookupReply -> NBP_LKUPREPLY

| ----------------------------------------------------------
|
| LUCODE_GOODBYE: +2 - drop names in the application heap
|
LUCODE_GOODBYE:
        BRA.B   NBP_DROPAPPLNAMES               | -> NBP_DROPAPPLNAMES

| ----------------------------------------------------------
|
| NIS_LISTENER: +4 - listener of socket 2 (names information socket).
| Reads a received LkUp packet into the lookup-reply parameter block (at
| csParam) and issues the LookupReply call (csCode 242) to this driver;
| drops the packet while that block is busy or if the request is ours.
|
NIS_LISTENER:
        MOVE.L  0x9E(A2),A3                     | A3 -> csCode of the block (LUQElPtr)
        TST     (A3)+                           | busy (csCode set)?
        BNE.B   NIS_LISTENER_BUSY               | yes -> drop the packet
        MOVEQ.L #0x7C,D3                        | up to 124 bytes
        JSR     0x2(A4)                         | ReadRest into csParam
        BNE.B   NIS_LISTENER_EXIT               | error -> return
        MOVE.L  0x9E(A2),A0                     | A0 -> csCode of the block
        MOVE.B  0x6(A0),D0                      | D0 = node of the tuple (csParam+4)
        CMP.B   (A2),D0                         | our node?
        BNE.B   NIS_LISTENER_QUEUE              | no -> answer it
        MOVE    0x4(A0),D0                      | D0 = network of the tuple (csParam+2)
        CMP     0x1A(A2),D0                     | our network?
        BEQ.B   NIS_LISTENER_EXIT               | yes: our own lookup -> ignore
| queue the LookupReply call
NIS_LISTENER_QUEUE:
        MOVE    #0xF2,(A0)                      | csCode = 242 (LookupReply): block busy
        SUBA    #0x1A,A0                        | A0 = parameter block
        LEA.L   NIS_LUCOMPLETION(PC),A1         | A1 = completion routine
        MOVE.L  A1,0xC(A0)                      | ioCompletion
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE
        MOVE    0x18(A1),0x18(A0)               | ioRefNum = .MPP refNum (dCtlRefNum)
        _ControlAsync                           | queue it
NIS_LISTENER_EXIT:
        RTS                                     | return to MPP

| ----------------------------------------------------------
|
| NIS_LISTENER_BUSY: block in use - drop the packet
|
NIS_LISTENER_BUSY:
        CLR     D3                              | buffer size 0
        JMP     0x2(A4)                         | ReadRest: discard, return to MPP

| ----------------------------------------------------------
|
| LUCODE_REPLY: -> NBP_LKUPREPLY
|
LUCODE_REPLY:
        BRA.B   NBP_LKUPREPLY                   | -> NBP_LKUPREPLY

| ----------------------------------------------------------
|
| NBP_DROPAPPLNAMES: goodbye kiss - unlink every names-table entry that
| does not lie in the system heap (below the end of SysZone)
|
NBP_DROPAPPLNAMES:
        LEA.L   0x9A(A2),A3                     | A3 -> NTQueueHd
        MOVE.L  (SysZone).w,A0                  | A0 = system heap zone (bkLim first)
NBP_DROPAPPLNAMES_LOOP:
        MOVE.L  (A3),D1                         | D1 = next entry
        BEQ.B   NBP_DROPAPPLNAMES_EXIT          | end ->
        AND.L   (Lo3Bytes).w,D1                 | 24-bit address
        MOVE.L  D1,A1                           | A1 = entry
        CMPA.L  (A0),A1                         | below the end of the system heap?
        BCS     NBP_DROPAPPLNAMES_KEEP          | yes -> keep it
        MOVE.L  (A1),(A3)                       | no: unlink it
        BRA.B   NBP_DROPAPPLNAMES_LOOP          | next

| ----------------------------------------------------------
|
| NBP_DROPAPPLNAMES_KEEP
|
| keep the entry, go on from it
NBP_DROPAPPLNAMES_KEEP:
        MOVE.L  A1,A3                           | A3 = entry (its link field)
        BRA.B   NBP_DROPAPPLNAMES_LOOP          | next

| ----------------------------------------------------------
|
| NBP_DROPAPPLNAMES_EXIT
|
| end of the names table
NBP_DROPAPPLNAMES_EXIT:
        RTS                                     | return

| ----------------------------------------------------------
|
| NBP_LKUPREPLY: LookupReply call, A0 = the lookup-reply block with the
| LkUp packet at csParam (+$1C control, +$1D NBP ID, +$1E tuple of the
| requester, +$23 entity name).  Collects the names-table entries whose
| object and type match ('=' matches all; the zone is not checked) and
| answers with LkUp-Reply packets (15 tuples / 584 bytes at most each)
| from socket 2 to the requester's socket.
|
NBP_LKUPREPLY:
        MOVE.L  0x9A(A2),D2                     | D2 = first names-table entry
        BEQ     NBP_LKUPREPLY_IODONE            | none -> done
        MOVE    SR,-(SP)                        | save SR
        MOVE    0x1C(A2),SR                     | SR = vSCCEnable
        MOVEM.L A2/A4-A5,-(SP)                  | save registers
        MOVE.L  A0,A4                           | A4 = lookup-reply block
        MOVE    NBP_CMPSTRINGTRAP(PC),D0        | D0 = _CmpString trap word ($A03C)
        _GetTrapAddress                         | A0 = its routine
        MOVE.L  A0,A2                           | A2 = CmpString routine (for NBP_CMPNAME)
        CLR     D3                              | D3 = matches
| scan the names table; matching entries are pushed on the stack
NBP_LKUPREPLY_LOOP:
        MOVE.L  D2,A3                           | A3 = entry
        ADDA    #0x9,A3                         | A3 -> its entity name (ntEntity)
        LEA.L   0x23(A4),A5                     | A5 -> requested entity name
        MOVE.L  A3,A1                           | A1 = entry object
        MOVE.L  A5,A0                           | A0 = requested object
        CMPI.B  #0x3D,0x1(A5)                   | requested object starts with '='?
        BEQ.B   NBP_LKUPREPLY_TYPE              | yes: matches all ->
        BSR     NBP_CMPNAME                     | objects equal?
        BNE.B   NBP_LKUPREPLY_NEXT              | no -> next entry
| object matches: compare the types
NBP_LKUPREPLY_TYPE:
        CLR     D0                              | D0.W = 0
        MOVE.B  (A5)+,D0                        | length of the requested object
        ADDA    D0,A5                           | A5 -> requested type
        MOVE.L  A3,A1                           | A1 -> entry object
        MOVE.B  (A1)+,D0                        | its length
        ADDA    D0,A1                           | A1 -> entry type
        MOVE.L  A5,A0                           | A0 = requested type
        CMPI.B  #0x3D,0x1(A5)                   | requested type starts with '='?
        BEQ.B   NBP_LKUPREPLY_MATCH             | yes: matches all ->
        BSR     NBP_CMPNAME                     | types equal?
        BNE.B   NBP_LKUPREPLY_NEXT              | no -> next entry
| match: remember the entity
NBP_LKUPREPLY_MATCH:
        MOVE.L  A3,-(SP)                        | push the entity pointer
        ADDQ.W  #0x1,D3                         | count it
| next entry
NBP_LKUPREPLY_NEXT:
        MOVE.L  -0x9(A3),D2                     | D2 = ntLink
        BNE.B   NBP_LKUPREPLY_LOOP              | more ->
        TST     D3                              | any match?
        BEQ     NBP_LKUPREPLY_DONE              | no -> done
| DDP header template at +$1F (odd) to the requester's socket, WDS at +$30
        LEA.L   0x1F(A4),A1                     | A1 = header template
        LEA.L   0x1E(A4),A5                     | A5 -> requester tuple address
        MOVE    (A5)+,0x7(A1)                   | +7 dest network
        MOVE.B  (A5)+,0xB(A1)                   | +11 dest node
        MOVE.B  (A5)+,0xD(A1)                   | +13 dest socket
        MOVE.B  #0x2,0xF(A1)                    | +15 DDP type 2 (NBP)
        MOVE.L  A1,0x32(A4)                     | WDS entry 1 pointer
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables again
| one LkUp-Reply packet
NBP_LKUPREPLY_PACKET:
        MOVE.B  0x1E(A4),0x26(A4)               | restore the dest network high byte (lost by a short header)
        CLR     D2                              | D2 = bytes in this packet
        CLR     D1                              | D1 = tuples in this packet
        LEA.L   0x36(A4),A3                     | A3 -> WDS entry 2
        LEA.L   0x1C(A4),A1                     | A1 = NBP header (+$1C control/count, +$1D NBP ID)
        MOVE    #0x2,(A3)+                      | entry 2 length = 2
        MOVE.L  A1,(A3)+                        | entry 2 pointer = NBP header
| one WDS entry per tuple, straight from the names-table entry
NBP_LKUPREPLY_TUPLE:
        MOVE.L  (SP),A5                         | A5 = next matching entity
        CLR     D0                              | D0.W = 0
        MOVE.B  (A5),D0                         | object length
        ADD.B   0x1(A5,D0.W),D0                 | + type length
        MOVE.B  #0x1,0x2(A5,D0.W)               | zone length = 1 ...
        MOVE.B  #0x2A,0x3(A5,D0.W)              | ... zone = "*"
        ADDI    #0x9,D0                         | tuple size: + address, enumerator, 3 lengths, zone
        ADD     D0,D2                           | add to the packet size
        CMPI    #0x248,D2                       | 584 bytes or more?
        BGE.B   NBP_LKUPREPLY_SEND              | yes -> send without it
        ADDQ.W  #0x4,SP                         | pop the entity
        MOVE    D0,(A3)+                        | WDS entry length = tuple size
        SUBQ.W  #0x5,A5                         | A5 -> tuple (ntTuple)
        MOVE.L  A5,(A3)+                        | WDS entry pointer
        MOVE    0x1A(A2),(A5)                   | tuple network = sysNetNum
        ADDQ.W  #0x1,D1                         | one more tuple
        SUBQ.W  #0x1,D3                         | one match less
        BEQ.B   NBP_LKUPREPLY_SEND              | none left -> send
        CMPI    #0xF,D1                         | 15 tuples (tupleMax)?
        BNE.B   NBP_LKUPREPLY_TUPLE             | no -> add the next
| send the packet and wait for the write
NBP_LKUPREPLY_SEND:
        CLR     (A3)+                           | end of WDS
        ORI     #0x30,D1                        | control 3 (LkUp-Reply), tuple count
        MOVE.B  D1,(A1)                         | nbpControl/nbpTCount
        MOVE    D3,A5                           | A5 = matches left
        CLR.B   0x2F(A4)                        | write-done flag = 0
        BSR.B   NBP_SENDREPLY                   | DDPWrite from socket 2
NBP_LKUPREPLY_WAIT:
        TST.B   0x2F(A4)                        | written?
        BEQ.B   NBP_LKUPREPLY_WAIT              | no -> wait
        MOVE    A5,D3                           | D3 = matches left
        BNE.B   NBP_LKUPREPLY_PACKET            | more -> next packet
| done
NBP_LKUPREPLY_DONE:
        MOVEM.L (SP)+,A2/A4-A5                  | restore registers
        MOVE    (SP)+,SR                        | restore SR
| NBP_LKUPREPLY_IODONE: complete the LookupReply call (its completion
| routine frees the block)
NBP_LKUPREPLY_IODONE:
        MOVE.L  (JIODone).w,A0                  | IODone vector
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE
        JMP     (A0)                            | -> IODone

| ----------------------------------------------------------
|
| NBP_SENDREPLY: DDPWrite the WDS at +$30 of the lookup-reply block (A4)
| from socket 2 (NIS), no checksum; sets the write-done flag (+$2F)
| when the write has finished
|
NBP_SENDREPLY:
        MOVEQ.L #0x2,D1                         | D1 = source socket 2 (NIS)
        LEA.L   0x30(A4),A1                     | A1 = WDS
        MOVE.L  0x96(A2),A0                     | A0 = JDDPWrite
        CLR.B   D3                              | no checksum
        JSR     (A0)                            | DDPWRITE; resumes here when done
        MOVE.L  0x9E(A2),A0                     | A0 -> csCode of the block
        ST.B    0x15(A0)                        | write-done flag (+$2F)
        RTS                                     | return

| ----------------------------------------------------------
|
| NBP_CMPSTRINGTRAP - the _CmpString trap word ($A03C), for _GetTrapAddress
|
NBP_CMPSTRINGTRAP:
  .byte 0xA0,0x3C                               | _CmpString ($A03C)
| NBP_CMPNAME: compare the Pascal strings at A0 and A1 with the CmpString
| routine in A2 (A0/A1 -> text, D0 = lengths) -> EQ if equal
| (case-insensitive)
NBP_CMPNAME:
        MOVEQ.L #0x0,D0                         | D0 = 0
        MOVE.B  (A0)+,D0                        | length of string A0
        SWAP    D0                              | to the high word
        MOVE.B  (A1)+,D0                        | length of string A1
        JSR     (A2)                            | CmpString: D0 = 0 if equal
        TST     D0                              | EQ = equal
        RTS                                     | return from NBP_CMPNAME

| ----------------------------------------------------------
|
| NIS_LUCOMPLETION: ioCompletion of the LookupReply call - csCode = 0
| (the lookup-reply block is free again)
|
NIS_LUCOMPLETION:
        CLR     0x1A(A0)                        | csCode = 0: block free
        RTS                                     | return

| ----------------------------------------------------------
|
| NBP_DISPATCH: NBP code entry (NRPtr).  D3 = csCode - 242; entry D3 - 7
| of NBP_DISPATCH_TBL is called with A3 = NRVars (A0 = parameter block,
| A1 = entityPtr / ntQElPtr, D1.B = interval).  D3 < 7: the goodbye kiss.
|
NBP_DISPATCH:
        SUBQ.W  #0x7,D3                         | D3 = csCode - 249
        BMI.B   NBP_DISPATCH_GOODBYE            | negative (goodbye kiss) ->
        ADD     D3,D3                           | word index
        LEA.L   NBP_DISPATCH_TBL(PC),A3         | A3 = table
        ADDA    D3,A3                           | A3 -> entry
        MOVE    (A3),D3                         | offset from NBP_DISPATCH
        LEA.L   NBP_DISPATCH(PC),A3             | A3 = NBP_DISPATCH
        ADDA    D3,A3                           | A3 = routine
        MOVE.L  A3,-(SP)                        | push it
        MOVE.L  0x92(A2),A3                     | A3 = NRVars
        RTS                                     | -> routine

| NBP_DISPATCH_TBL - offsets from NBP_DISPATCH; entry 0 (249, LoadNBP in
| the RAM driver) is only reached from E_MPP_Open
NBP_DISPATCH_TBL:
  .byte  0x00,0x44,0x00,0x82,0x01,0x7C          | 0 NBP_INIT, 250 ConfirmName, 251 LookupName
  .byte 0x01,0x20,0x00,0x8A,0x02,0x62           | 252 RemoveName, 253 RegisterName, 254 KillNBP
  .byte 0x00,0x2E                               | 255 UnloadNBP
| NBP_DISPATCH_GOODBYE: goodbye kiss - like UnloadNBP
NBP_DISPATCH_GOODBYE:
        MOVE.L  0x92(A2),A3                     | A3 = NRVars
| UnloadNBP (csCode 255): nothing to unload - as KillNBP
UNLOADNBP:
        BRA     KILLNBP                         | stop the NBP request, IODone noErr
| NBP_FREESKT: unreferenced - remove socket D0 from the socket table
NBP_FREESKT:
        MOVEQ.L #0xD,D2                         | 14 entries
NBP_FREESKT_LOOP:
        CMP.B   0x36(A2,D2.W),D0                | this socket?
        DBEQ    D2,NBP_FREESKT_LOOP             | no -> next
        .short 0x6604                           | BNE.B *+6 (to the RTS): not found
        CLR.B   0x36(A2,D2.W)                   | free the entry
        RTS                                     | return
| NBP_INIT: allocate NRVars and open the NBP socket (dynamic number,
| listener NBP_LISTENER), on which requests go out and replies come in.
| NRVars ($47 bytes): +$00 NBP socket, +$01 NBP ID, +$02 dest network
| (kept for retries), +$04 VBL task (NBP_VBLTASK), +$12 active call
| (0 = none), +$16 LookupName: next free byte in retBuffPtr, +$1A bytes
| left, +$1C WDS (header -> +$37, 7 bytes -> +$30, entity name, 0),
| +$30 NBP header and tuple address, +$37 DDP header template
NBP_INIT:
        MOVEQ.L #0x47,D0                        | $47 bytes
        BSR.B   NBP_NEWPTR                      | zeroed block in the system heap
        BNE.B   NBP_INIT_EXIT                   | out of memory -> return
        MOVE    #0x1,0x8(A0)                    | VBL task: qType = vType (1)
        LEA.L   NBP_VBLTASK(PC),A1              | A1 = NBP_VBLTASK
        MOVE.L  A1,0xA(A0)                      | vblAddr
        LEA.L   NBP_LISTENER(PC),A1             | A1 = listener
        MOVE.L  0x96(A2),A3                     | A3 = JDDPWrite
        CLR     D1                              | socket 0: assign one
        JSR     0x2(A3)                         | MPP_OPENSOCKET
        TST     D0                              | opened?
        BNE.B   NBP_INIT_FAIL                   | no ->
        MOVE.B  D1,(A0)                         | +$00 = NBP socket
        MOVE.L  A0,0x92(A2)                     | NRVars
NBP_INIT_EXIT:
        RTS                                     | return from NBP_INIT

| ----------------------------------------------------------
|
| NBP_INIT_FAIL: free the block, return the error
|
NBP_INIT_FAIL:
        MOVE    D0,D1                           | save the error
        _DisposePtr                             | free the block
        MOVE    D1,D0                           | D0 = error
        RTS                                     | return from NBP_INIT

| ----------------------------------------------------------
|
| NBP_NEWPTR: zeroed block of D0 bytes in the system heap -> A0, D0
|
NBP_NEWPTR:
        _NewPtrSysClear                         | allocate it
        BRA.B   NBP_NEWPTR_EXIT                 | skip the next word
  .byte 0xA3,0x1E                               | never executed: trap word $A31E (_NewPtr,CLEAR: application heap)
NBP_NEWPTR_EXIT:
        RTS                                     | return from NBP_NEWPTR

| ----------------------------------------------------------
|
| ConfirmName (csCode 250): send a LkUp for entityPtr directly to node
| confirmAddr.  A reply sets newSocket: noErr if it is the socket of
| confirmAddr, nbpConfDiff if not; nbpNoConfirm if none comes.
|
CONFIRMNAME:
        MOVE.L  0x22(A0),D2                     | D2 = confirmAddr (net.W, node.B, socket.B)
        BRA     NBP_SENDREQ                     | -> send the LkUp

| ----------------------------------------------------------
|
| RegisterName (csCode 253): enter the names-table entry at ntQElPtr
| (address, entity) in the names table; the first call opens the NIS
| (socket 2) and allocates the lookup-reply block.  With verifyFlag the
| name is first looked up (own table: nbpDuplicate; network: LkUp, a
| reply means nbpDuplicate).  nbpNISErr, memFullErr.
|
REGISTERNAME:
        MOVE.L  A0,D3                           | D3 = parameter block
        TST.L   0x8E(A2)                        | LookupPtr bit 31: NIS open?
        BMI.B   REGISTERNAME_VERIFY             | yes ->
| first registration: lookup-reply block and the NIS
        NOP                                     | (no operation)
        MOVE.L  #0x98,D0                        | $98 bytes: lookup-reply block
        BSET    #0x7,0x8E(A2)                   | LookupPtr bit 31 (stays set if a step below fails)
        BSR.B   NBP_NEWPTR                      | allocate it
        BNE.B   REGISTERNAME_FAIL               | out of memory -> IODone with the error
        ADDA    #0x1A,A0                        | A0 -> its csCode field
        MOVE.L  A0,0x9E(A2)                     | LUQElPtr
        MOVEM.L D1/A1/A3,-(SP)                  | save registers
        MOVEQ.L #0x2,D1                         | socket 2 (NIS)
        MOVE.L  0x8E(A2),A1                     | A1 = LUCODE (bit 31 set) ...
        ADDQ.W  #0x4,A1                         | ... +4 = NIS_LISTENER
        MOVE.L  0x96(A2),A3                     | A3 = JDDPWrite
        JSR     0x2(A3)                         | MPP_OPENSOCKET
        MOVEM.L (SP)+,D1/A1/A3                  | restore registers
        TST     D0                              | opened?
        BEQ.B   REGISTERNAME_NISOK              | yes ->
        MOVE    #-0x405,D0                      | nbpNISErr (-1029)
        BRA.B   REGISTERNAME_FAIL               | -> IODone with it

| ----------------------------------------------------------
|
| REGISTERNAME_NISOK
|
| NIS open
REGISTERNAME_NISOK:
        BSet    #0x7,0x8E(A2)                   | LookupPtr bit 31: NIS open
        MOVE.L  D3,A0                           | A0 = parameter block
| verify the name first?
REGISTERNAME_VERIFY:
        TST.B   0x22(A0)                        | verifyFlag?
        BEQ.B   NBP_ENTERNAME                   | no -> enter it now
        ADDA    #0x9,A1                         | A1 -> entity name (ntEntity)
        BSR.B   NBP_FINDNAME                    | in our names table?
        BEQ     NBP_BCASTREQ                    | no -> look it up on the network
        MOVE    #-0x403,D0                      | yes: nbpDuplicate (-1027)
| REGISTERNAME_FAIL - complete the NBP call with D0 (also RemoveName)
REGISTERNAME_FAIL:
        BRA     NBP_DONE                        | -> NBP_DONE

| ----------------------------------------------------------
|
| NBP_ENTERNAME: enter names-table entry A1: tuple node = our node, a
| tuple enumerator not yet used on its socket, linked in at the end;
| then complete the call with noErr
|
NBP_ENTERNAME:
        CLR     D2                              | D2 = enumerator candidate
        MOVE.B  0x7(A1),D1                      | D1 = ntSocket
NBP_ENTERNAME_ENUM:
        ADDQ.W  #0x1,D2                         | next candidate
        LEA.L   0x9A(A2),A0                     | A0 -> NTQueueHd
NBP_ENTERNAME_LOOP:
        TST.L   (A0)                            | end of the table?
        BEQ.B   NBP_ENTERNAME_LINK              | yes: candidate is free ->
        MOVE.L  (A0),A0                         | A0 = next entry
        CMP.B   0x7(A0),D1                      | same socket?
        BNE.B   NBP_ENTERNAME_LOOP              | no ->
        TST.B   D2                              | candidate wrapped to 0?
        BEQ.B   NBP_ENTERNAME_LOOP              | yes: take it anyway
        CMP.B   0x8(A0),D2                      | enumerator in use?
        BEQ.B   NBP_ENTERNAME_ENUM              | yes -> next candidate
        BRA.B   NBP_ENTERNAME_LOOP              | no -> next entry

| ----------------------------------------------------------
|
| NBP_ENTERNAME_LINK
|
| fill in the tuple, link the entry at the end (A0 = last entry)
NBP_ENTERNAME_LINK:
        MOVE.B  (A2),0x6(A1)                    | tuple node = sysLAPAddr
        MOVE.B  D2,0x8(A1)                      | tuple enumerator
        CLR.L   (A1)                            | ntLink = nil
        MOVE.L  A1,(A0)                         | link it in
        BRA.B   REMOVENAME_DONE                 | -> complete, noErr

| ----------------------------------------------------------
|
| RemoveName (csCode 252): unlink the names-table entry with the name
| at entityPtr.  nbpNotFound.
|
REMOVENAME:
        MOVE    #-0x404,D0                      | nbpNotFound (-1028)
        BSR.B   NBP_FINDNAME                    | D3 = entry
        BEQ.B   REGISTERNAME_FAIL               | not found -> nbpNotFound
        MOVE    SR,-(SP)                        | save SR
        MOVE    #0x2600,SR                      | interrupts off (IPL 6)
        LEA.L   0x9A(A2),A0                     | A0 -> NTQueueHd
REMOVENAME_LOOP:
        CMP.L   (A0),D3                         | next is the entry?
        BEQ.B   REMOVENAME_UNLINK               | yes ->
        MOVE.L  (A0),A0                         | A0 = next
        BRA.B   REMOVENAME_LOOP                 | loop

| ----------------------------------------------------------
|
| REMOVENAME_UNLINK
|
| unlink it
REMOVENAME_UNLINK:
        MOVE.L  D3,A1                           | A1 = entry
        MOVE.L  (A1),(A0)                       | predecessor -> successor
        MOVE    (SP)+,SR                        | restore SR
REMOVENAME_DONE:
        BRA     KILLNBP                         | -> complete, noErr


| ----------------------------------------------------------
|
| NBP_FINDNAME
|
| NBP_FINDNAME: find the entry whose object and type equal those at A1
| (_CmpString over both strings and their length bytes) -> D3 = entry,
| NE; or D3 = 0, EQ.  Preserves the other registers.
NBP_FINDNAME:
        MOVEM.L D0-D1/A0-A3,-(SP)               | save registers
        MOVE.L  A1,A3                           | A3 = name searched for
        LEA.L   0x9A(A2),A2                     | A2 -> NTQueueHd
        CLR.L   D3                              | D3 = 0 (not found)
NBP_FINDNAME_LOOP:
        TST.L   (A2)                            | end of the table?
        BEQ.B   NBP_FINDNAME_EXIT               | yes -> EQ
        CLR     D0                              | D0.W = 0
        MOVE.B  (A3),D0                         | object length
        ADD.B   0x1(A3,D0.W),D0                 | + type length
        ADDQ.W  #0x2,D0                         | + 2 length bytes
        MOVE    D0,D1                           | D1 = size
        SWAP    D0                              | both lengths of the
        MOVE    D1,D0                           | compare = size
        MOVE.L  (A2),A2                         | A2 = next entry
        MOVE.L  A2,A1                           | A1 = entry ...
        ADDA    #0x9,A1                         | ... entity name (ntEntity)
        MOVE.L  A3,A0                           | A0 = name searched for
        _CmpString                              | equal? (D0 = 0)
        TST     D0                              | equal?
        BNE.B   NBP_FINDNAME_LOOP               | no -> next entry
        MOVE.L  A2,D3                           | D3 = entry (NE)
NBP_FINDNAME_EXIT:
        MOVEM.L (SP)+,D0-D1/A0-A3               | restore registers
        RTS                                     | return from NBP_FINDNAME

| ----------------------------------------------------------
|
| LookupName (csCode 251): look up entityPtr in the whole network; the
| replies (NBP_LISTENER) go into retBuffPtr/retBuffSize, numGotten
| counts them.  Ends at maxToGet, a full buffer or after count retries.
|
LOOKUPNAME:
        CLR     0x2A(A0)                        | numGotten = 0
        MOVE.L  0x22(A0),0x16(A3)               | NRVars+$16 = retBuffPtr
        MOVE    0x26(A0),0x1A(A3)               | NRVars+$1A = retBuffSize
| NBP_BCASTREQ: request to the whole network (LookupName, verifying
| RegisterName)
NBP_BCASTREQ:
        CLR.L   D2                              | no address given
| NBP_SENDREQ: send the request for entity A1 and start the retry timer
| (interval D1 * 8 ticks).  D2 = address: with a node, a LkUp goes to
| that node; else to all ($FF) or, if a bridge is known, a BrRq to it.
NBP_SENDREQ:
        MOVEQ.L #0x21,D3                        | control LkUp (2), 1 tuple
        LSR     #0x8,D2                         | D2.W = node of the address
        BNE.B   NBP_SENDREQ_SETUP               | given -> to that node
        ST.B    D2                              | else node $FF (broadcast)
        MOVE.B  0x19(A2),D0                     | D0 = sysABridge
        BEQ.B   NBP_SENDREQ_SETUP               | no bridge ->
        MOVEQ.L #0x11,D3                        | bridge: control BrRq (1), 1 tuple
        MOVE.B  D0,D2                           | to the bridge
| active call, destination network, retry timer
NBP_SENDREQ_SETUP:
        MOVE.L  A0,0x12(A3)                     | +$12 active call
        SWAP    D2                              | D2.W = network, high word = node
        MOVE    D2,0x2(A3)                      | +$02 dest network (for retries)
        LEA.L   0x4(A3),A0                      | A0 = VBL task (+$04)
        LSL     #0x3,D1                         | interval * 8 ticks
        ANDI    #0x3FF,D1                       | at most $3FF
        MOVE    D1,0xA(A0)                      | vblCount
        _VInstall                               | start the retry timer
| WDS: header template, NBP header + tuple address, entity name
        MOVE.L  A1,D0                           | D0 = entity name
        LEA.L   0x1E(A3),A1                     | A1 -> WDS entry 1 pointer (+$1E)
        LEA.L   0x37(A3),A0                     | A0 = header template (+$37, odd)
        MOVE.L  A0,(A1)+                        | entry 1 pointer
        MOVE.B  #0x2,0xD(A0)                    | +13 dest socket 2 (NIS)
        MOVE    D2,0x7(A0)                      | +7 dest network
        SWAP    D2                              | D2.B = node
        MOVE.B  D2,0xB(A0)                      | +11 dest node
        MOVE.B  #0x2,0xF(A0)                    | +15 DDP type 2 (NBP)
        MOVE    #0x7,(A1)+                      | entry 2 length = 7
        LEA.L   0x30(A3),A0                     | A0 = NBP header (+$30)
        MOVE.L  A0,(A1)+                        | entry 2 pointer
        MOVE.B  D3,(A0)+                        | nbpControl/nbpTCount
        ADDQ.B  #0x1,0x1(A3)                    | next NBP ID
        MOVE.B  0x1(A3),(A0)+                   | nbpID
        MOVE    0x1A(A2),(A0)+                  | tuple network = sysNetNum
        MOVE.B  (A2),(A0)+                      | tuple node = sysLAPAddr
        MOVE.B  (A3),D1                         | D1 = NBP socket (replies come here)
        MOVE.B  D1,(A0)                         | tuple socket
        MOVE.L  D0,A0                           | A0 = entity name
        CLR     D2                              | D2.W = 0
        MOVE.B  (A0),D2                         | object length
        ADD.B   0x1(A0,D2.W),D2                 | + type length
        ADD.B   0x2(A0,D2.W),D2                 | + zone length
        ADDQ.B  #0x3,D2                         | + 3 length bytes
        MOVE    D2,(A1)+                        | entry 3 length
        MOVE.L  A0,(A1)+                        | entry 3 pointer = entity name
        CLR     (A1)                            | end of WDS
| NBP_WRITE: DDPWrite the request from the NBP socket (D1), no checksum
NBP_WRITE:
        LEA.L   0x1C(A3),A1                     | A1 = WDS (+$1C)
        MOVE.L  0x96(A2),A0                     | A0 = JDDPWrite
        CLR.B   D3                              | no checksum
        JSR     (A0)                            | DDPWRITE
        RTS                                     | return (the call stays pending)

| ----------------------------------------------------------
|
| NBP_VBLTASK: NBP retry timer (A0 = task): count - 1; at 0 NBP_TIMEOUT,
| else send the request again after interval * 8 ticks
|
NBP_VBLTASK:
        MOVE.L  (ABusVars).w,A2                 | A2 = MPP variables
        MOVE.L  0x92(A2),A3                     | A3 = NRVars
        MOVE.L  0x12(A3),A1                     | A1 = active call
        SUBQ.B  #0x1,0x1D(A1)                   | count - 1
        BEQ.B   NBP_TIMEOUT                     | 0 -> no more retries
        CLR     D0                              | D0.W = 0
        MOVE.B  0x1C(A1),D0                     | interval
        LSL     #0x3,D0                         | * 8 ticks
        MOVE    D0,0xA(A0)                      | vblCount
        MOVE    0x2(A3),0x3E(A3)                | restore the dest network (+$3E) for a long header
        MOVE.B  (A3),D1                         | D1 = NBP socket
        BRA.B   NBP_WRITE                       | send again

| ----------------------------------------------------------
|
| NBP_TIMEOUT: retries used up - RegisterName: nobody has the name, enter
| it; ConfirmName: nbpNoConfirm; LookupName: done (noErr)
|
NBP_TIMEOUT:
        MOVE    0x1A(A1),D0                     | D0 = csCode of the call
        MOVE.L  0x1E(A1),A1                     | A1 = ntQElPtr / entityPtr
        CMPI    #0xFD,D0                        | RegisterName (253)?
        BEQ     NBP_ENTERNAME                   | yes -> enter the name
        CMPI    #0xFA,D0                        | ConfirmName (250)?
        BNE.B   KILLNBP                         | no (LookupName) -> noErr
        MOVE    #-0x401,D0                      | nbpNoConfirm (-1025)
        BRA.B   NBP_DONE                        | -> complete

| ----------------------------------------------------------
|
| KillNBP (csCode 254), also the noErr completion of the NBP calls:
| NBP_DONE stops the retry timer, forgets the active call and calls IODone
| with D0 (completing the call at the head of the .MPP queue)
|
KILLNBP:
        CLR     D0                              | noErr
NBP_DONE:
        MOVE    D0,D1                           | save D0
        LEA.L   0x4(A3),A0                      | A0 = VBL task (NRVars+$04)
        _VRemove                                | stop the retry timer
        MOVE    D1,D0                           | D0 = result
        CLR.L   0x12(A3)                        | no active call
        MOVE.L  (ABusVars_dce).w,A1             | A1 = .MPP DCE
        MOVE.L  (JIODone).w,A0                  | IODone vector
        JMP     (A0)                            | -> IODone

| ----------------------------------------------------------
|
| NBP_LISTENER_NOTLKUP: reply for a RegisterName (-> nbpDuplicate) or a
| ConfirmName: newSocket = socket of the first tuple; noErr if it is the
| socket of confirmAddr, else nbpConfDiff
|
NBP_LISTENER_NOTLKUP:
        CMPI    #0xFD,0x1A(A5)                  | RegisterName (253)?
        BEQ.B   NBP_LISTENER_DUPLICATE          | yes -> nbpDuplicate
        MOVEQ.L #0x4,D3                         | 4 bytes: tuple net, node, socket
        JSR     0x2(A4)                         | ReadRest
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        MOVE.B  -(A3),D2                        | D2 = tuple socket
        MOVE.L  0x92(A2),A3                     | A3 = NRVars
        MOVE.L  0x12(A3),A1                     | A1 = ConfirmName call
        MOVE.B  D2,0x26(A1)                     | newSocket
        CMP.B   0x25(A1),D2                     | socket of confirmAddr?
        BEQ.B   KILLNBP                         | yes -> noErr
        MOVE    #-0x402,D0                      | nbpConfDiff (-1026)
        BRA.B   NBP_DONE                        | -> complete

| ----------------------------------------------------------
|
| NBP_LISTENER_DUPLICATE: someone answered the verifying LkUp of a
| RegisterName - nbpDuplicate
|
NBP_LISTENER_DUPLICATE:
        JSR     0x2(A4)                         | ReadRest (D3 = 0: discard)
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        MOVE.L  0x92(A2),A3                     | A3 = NRVars
        MOVE    #-0x403,D0                      | nbpDuplicate (-1027)
        BRA.B   NBP_DONE                        | -> complete

| ----------------------------------------------------------
|
| NBP_LISTENER_EXIT
|
| return to MPP
NBP_LISTENER_EXIT:
        RTS                                     | return from NBP_LISTENER

| ----------------------------------------------------------
|
| NBP_LISTENER_DISCARD: drop the packet
|
NBP_LISTENER_DISCARD:
        CLR     D3                              | buffer size 0
        JMP     0x2(A4)                         | ReadRest: discard, return to MPP

| ----------------------------------------------------------
|
| NBP_LISTENER: listener of the NBP socket - replies to our requests.
| Reads the NBP header; drops it unless a call is active and the NBP ID
| matches.  LookupName: the tuples go straight into the return buffer;
| tuples already received (same address and enumerator) are removed,
| numGotten counted; the call ends at maxToGet or a full buffer.
|
NBP_LISTENER:
        MOVEQ.L #0x2,D3                         | 2 bytes: control/count, NBP ID
        JSR     (A4)                            | ReadPacket
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        MOVE.L  0x92(A2),A5                     | A5 = NRVars
        MOVE.L  0x12(A5),D0                     | D0 = active call
        BEQ.B   NBP_LISTENER_DISCARD            | none -> drop
        MOVE.B  -(A3),D2                        | D2 = nbpID
        CMP.B   0x1(A5),D2                      | ours?
        BNE.B   NBP_LISTENER_DISCARD            | no -> drop
        MOVE.B  -(A3),D2                        | D2 = nbpControl/nbpTCount
        EXG     D0,A5                           | A5 = call, D0 = NRVars
        CMPI    #0xFB,0x1A(A5)                  | LookupName (251)?
        BNE.B   NBP_LISTENER_NOTLKUP            | no ->
| LookupName: read the tuples into the return buffer
        MOVE.L  D0,A5                           | A5 = NRVars
        MOVE.L  0x16(A5),A3                     | A3 = next free byte of the buffer
        MOVE    0x1A(A5),D3                     | D3 = bytes left
        JSR     0x2(A4)                         | ReadRest
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        SUBI.B  #0x30,D2                        | control must be 3 (LkUp-Reply)
        BLE.B   NBP_LISTENER_EXIT               | no tuples / other packet -> ignore
        CMPI.B  #0xF,D2                         | more than 15 tuples?
        BGT.B   NBP_LISTENER_EXIT               | yes -> ignore
        MOVE.L  A3,D1                           | D1 = end of the data read
        MOVE.L  0x92(A2),A3                     | A3 = NRVars
        CLR     D0                              | D0.W = 0
        TST     D3                              | truncated (D3 < 0)?
        BPL.B   NBP_LISTENER_DEDUP              | no: all D2 tuples complete
| truncated: count the complete tuples
        CLR     D2                              | D2 = complete tuples
        MOVE.L  0x16(A3),A0                     | A0 = first new tuple
NBP_LISTENER_COUNTLOOP:
        ADDQ.W  #0x5,A0                         | skip address and enumerator
        CMP.L   A0,D1                           | past the end?
        BLE.B   NBP_LISTENER_COUNTED            | yes -> stop
        MOVE.B  (A0)+,D0                        | object length
        ADDA    D0,A0                           | skip the object
        CMP.L   A0,D1                           | past the end?
        BLE.B   NBP_LISTENER_COUNTED            | yes -> stop
        MOVE.B  (A0)+,D0                        | type length
        ADDA    D0,A0                           | skip the type
        CMP.L   A0,D1                           | past the end?
        BLE.B   NBP_LISTENER_COUNTED            | yes -> stop
        MOVE.B  (A0)+,D0                        | zone length
        ADDA    D0,A0                           | skip the zone
        CMP.L   A0,D1                           | past the end?
        BLT.B   NBP_LISTENER_COUNTED            | yes -> stop
        ADDQ.W  #0x1,D2                         | one more complete tuple
        BRA.B   NBP_LISTENER_COUNTLOOP          | next

| ----------------------------------------------------------
|
| NBP_LISTENER_COUNTED
|
| none complete: ignore the packet
NBP_LISTENER_COUNTED:
        TST     D2                              | complete tuples?
  .short 0x6780                                 | BEQ.B NBP_LISTENER_EXIT (displacement -128): none
| remove tuples already in the buffer (same address and enumerator)
NBP_LISTENER_DEDUP:
        MOVEM.L A4-A6,-(SP)                     | save A4-A6
        CLR     D1                              | D1 = new tuples kept
        MOVE.L  0x12(A3),A5                     | A5 = LookupName call
        MOVE.L  0x22(A5),D3                     | D3 = retBuffPtr (start of the buffer)
        MOVE.L  0x16(A3),A5                     | A5 = first new tuple
        MOVE.L  A5,A6                           | A6 = where kept tuples go
NBP_LISTENER_DEDUPLOOP:
        MOVE.L  D3,A4                           | A4 = first old tuple
NBP_LISTENER_SCANLOOP:
        CMPA.L  0x16(A3),A4                     | end of the old tuples?
        BEQ.B   NBP_LISTENER_KEEP               | yes: new one is unique ->
        MOVE.L  A4,A0                           | A0 = old tuple
        MOVE.L  A5,A1                           | A1 = new tuple
        CMPM.B  (A0)+,(A1)+                     | network high byte
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A1)+                     | network low byte
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A1)+                     | node
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A1)+                     | socket
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A1)+                     | enumerator
        BEQ.B   NBP_LISTENER_DROP               | same: duplicate -> drop
NBP_LISTENER_SCANNEXT:
        ADDQ.W  #0x5,A4                         | skip address and enumerator
        MOVE.B  (A4),D0                         | object length
        ADD.B   0x1(A4,D0.W),D0                 | + type length
        ADD.B   0x2(A4,D0.W),D0                 | + zone length
        ADDQ.W  #0x3,D0                         | + 3 length bytes
        ADDA    D0,A4                           | next old tuple
        BRA.B   NBP_LISTENER_SCANLOOP           | loop

| ----------------------------------------------------------
|
| NBP_LISTENER_KEEP
|
| keep the new tuple: move it down to A6 if tuples were dropped
NBP_LISTENER_KEEP:
        MOVE.B  0x5(A5),D0                      | object length
        ADD.B   0x6(A5,D0.W),D0                 | + type length
        ADD.B   0x7(A5,D0.W),D0                 | + zone length
        ADDQ.W  #0x8,D0                         | + 5 + 3 = tuple size
        MOVE.L  A5,A0                           | A0 = source
        ADDA    D0,A5                           | A5 = next new tuple
        CMPA.L  A0,A6                           | already in place?
        BEQ.B   NBP_LISTENER_INPLACE            | yes ->
        MOVE.L  A6,A1                           | A1 = destination
        ADDA    D0,A6                           | advance it
        _BlockMove                              | move the tuple down
        BRA.B   NBP_LISTENER_COUNTNEW           | ->

| ----------------------------------------------------------
|
| NBP_LISTENER_INPLACE
|
| in place
NBP_LISTENER_INPLACE:
        MOVE.L  A5,A6                           | A6 = next free place
NBP_LISTENER_COUNTNEW:
        ADDQ.W  #0x1,D1                         | one more kept
NBP_LISTENER_NEXTTUPLE:
        SUBQ.B  #0x1,D2                         | tuples left
        BNE.B   NBP_LISTENER_DEDUPLOOP          | more ->
        MOVE.L  A6,0x16(A3)                     | next free byte of the buffer
        MOVE.L  0x12(A3),A0                     | A0 = LookupName call
        SUBA.L  0x22(A0),A6                     | A6 = bytes used
        MOVE    0x26(A0),D0                     | retBuffSize
        SUB     A6,D0                           | - used = bytes left
        MOVEM.L (SP)+,A4-A6                     | restore A4-A6
        ADD     0x2A(A0),D1                     | + numGotten
        MOVE    D1,0x2A(A0)                     | numGotten
        CMP     0x28(A0),D1                     | >= maxToGet?
        BPL     KILLNBP                         | yes -> complete, noErr
        MOVE    D0,0x1A(A3)                     | bytes left
        BEQ     KILLNBP                         | buffer full -> complete, noErr
        RTS                                     | return to MPP (call still pending)

| ----------------------------------------------------------
|
| NBP_LISTENER_DROP: duplicate - skip the new tuple (it is overwritten by
| the next kept one)
|
NBP_LISTENER_DROP:
        ADDQ.W  #0x5,A5                         | skip address and enumerator
        MOVE.B  (A5),D0                         | object length
        ADD.B   0x1(A5,D0.W),D0                 | + type length
        ADD.B   0x2(A5,D0.W),D0                 | + zone length
        ADDQ.W  #0x3,D0                         | + 3 length bytes
        ADDA    D0,A5                           | A5 = next new tuple
        BRA.B   NBP_LISTENER_NEXTTUPLE          | ->
    ROM_RESOURCE_END DRVR_9                     | end of the data: pads to even, sets the sizes

| end of resource : 'DRVR' 9 '.MPP'

