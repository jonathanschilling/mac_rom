| =========================================================================
| DRVR 9 .MPP -- AppleTalk LAP, DDP and NBP driver (SE ROM, version 48)
| =========================================================================
| ROM offsets +0x33122..+0x34677: the 8-byte ROM resource header and the
| driver body from +0x3312A (MacSEROM.lst: _DRVR_9_.MPP).
|
| LocalTalk link access (LAP) on SCC channel B (the printer port), DDP,
| RTMP (network number and bridge only), the Echo Protocol and NBP; the
| Open also opens .ATP.  This is the "new calls" release (Inside
| Macintosh V-508..519): version 48 (NCVersion) in dCtlQueue+1.  New
| against the Mac Plus driver (version 19, src/plus/resources/
| res_drvr_mpp.s):
|   - Resources (IM V-518): 8 LAP protocol handlers, 12 statically
|     assigned sockets, 127 dynamic sockets ($80..$FE, each with its own
|     listener slot; the highest free number is assigned), 6 concurrent
|     NBP requests (each with its own NBP ID and retry timer).
|   - SetSelfSend (256) and intranode delivery: with SelfSend on, LAPWRITE
|     hands frames for our own node (and broadcasts) to the protocol
|     handler directly, reading from the WDS through SELF_READ_JT.
|   - KillNBP (254) aborts one NBP call (reqAborted); LookupName,
|     ConfirmName and RegisterName are taken off the driver queue while
|     they wait, so other calls run meanwhile; a RegisterName also checks
|     the names being registered by other pending calls.
|   - The Echo Protocol (EP, DDP type 4): socket 4 answers echo requests
|     (EP_LISTENER, buffer EPBufPtr).
|   - Server node numbers: an extended Open (immediate bit set, ioMix bit
|     31) picks the node ID in $80..$FE with 120 rounds of lapENQ instead
|     of 20 (IM V-515); bit 7 of the PRAM hint SPATalkB remembers it.
|   - The LAP timing constants are computed from TimeDBRA / TimeSCCDB on
|     ROMs >= $76 (SE), else the fixed Mac Plus values are used.
|   - LAP statistics (15 counters), read and cleared by Status csCode 400.
|   - Smaller changes: send-byte timeouts are caught (BMI after
|     LAP_SENDBYTE; the Plus tested BEQ), the data frame after our lapCTS
|     is awaited for VDataTO polls, RegisterName marks the NIS open only
|     after it opened, the names-table entries above BufPtr survive the
|     goodbye kiss, which no longer stops pending NBP requests (the Plus
|     ran UnloadNBP = KillNBP there).
|
| Control calls (csCode - 242; 242..249 through E_MPP_CONTROL_TBL,
| 250..256 through NRPtr to NBP_DISPATCH; csCodes from System 7.1
| AppleTalk.a, parameter blocks IM II-307..324, V-516..518):
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
|   252 RemoveName    REMOVENAME     |
|   253 RegisterName  REGISTERNAME   | via NBP_DISPATCH
|   254 KillNBP       KILLNBP        |
|   255 UnloadNBP     UNLOADNBP      |
|   256 SetSelfSend   SETSELFSEND   /
| csCode 1 (killCode) returns at once; csCode < 0 (goodbye kiss: the
| driver has dNeedGoodbye) unlinks the names-table entries in the
| application heap.  Status: csCode 400 copies the 15 LAP statistics
| counters to the buffer at csParam and clears them (no Apple name known;
| not in Inside Macintosh).  Prime: not supported.
|
| Receive path: LAP_RCVINT (SCC Rx interrupt) reads the LAP header and the
| length word into the read header area (RHA) and jumps to the protocol
| handler of the LAP type (DDP_RCVSHORT / DDP_RCVLONG for types 1 and 2),
| which reads the DDP header and jumps to the listener of the destination
| socket; handlers and listeners read the rest through READPACKET and
| READREST (A4 -> LAP_READ_JT; IM II-325..329).  Transmit path: LAPWRITE
| (CSMA/CA with lapRTS/lapCTS dialog, random backoff, synchronous;
| deferred to an interrupt when the line is busy).  While interrupts are
| off, bytes arriving on the modem port (SCC channel A, VIA PA7 = W/REQ)
| are saved on the stack and handed to PollProc (as the disk driver does).
|
| MPP variables (ABusVars, $356 bytes; names as in Apple's ATalkEqu.a and
| the later vardefs / LAPvars sources):
|   +$000 sysLAPAddr (node ID), +$001 RHA (toRHA, 24 bytes), +$019
|         sysABridge (node of a bridge, 0 = none), +$01A sysNetNum, +$01C
|         vSCCEnable (SR enabling SCC interrupts), +$01E atpVars (.ATP)
|   +$022 NumOfPHs (8), +$023 NumOfSkts (12)
|   +$024 8 LAP protocol types ($FF = free; 6 = longDDP, 7 = shortDDP)
|   +$02C 8 protocol handler addresses
|   +$04C 12 static DDP socket numbers (0 = free; entry 10 = socket 4,
|         the echoer, entry 11 = socket 1, RTMP)
|   +$058 12 socket listener addresses
|   +$088 EPBufPtr: Echo Protocol buffer ($28B bytes, see EP_LISTENER)
|   +$08C 127 listener addresses of the dynamic sockets $80..$FE (0 =
|         not open)
|   +$288 VBL task (MPP_VBLTASK, every 20 ticks)
|   +$296 NRPtr: NBP code (NBP_DISPATCH), bit 31 = installed
|   +$29A LookupPtr: lookup-reply code (LUCODE), bit 31 = NIS open
|   +$29E NRVars: NBP variables ($A1 bytes, see NBP_INIT)
|   +$2A2 JDDPWrite: MPP_JDDPWRITE (+0 DDPWrite, +2 open socket)
|   +$2A6 NTQueueHd: names table (list of names-table entries)
|   +$2AA LUQElPtr: lookup-reply parameter block/buffer ($98 bytes) + $1A
|   +$2AE SelfSend (byte, SetSelfSend; 0 = off)
|   LAP: +$2B0 WDSPtr, +$2B4 LAPWrtRtn, +$2B8 RandomSeed, +$2BA DestNode,
|   +$2BB fLAPAdrValid, +$2BC fGoodCTS (0 while a lapCTS is expected),
|   +$2BD fAdrInUse, +$2BE fSendENQ, +$2BF VBLDeferCnt, +$2C0 lbackOff,
|   +$2C1 backoff, +$2C2 collsnHistory, +$2C3 deferHistory, +$2C4
|   deferTries, +$2C5 collsnTries, +$2C6 BridgeTime; timing loop counts
|   +$2C8 VAbortWait, +$2CA VRTimeout, +$2CC VSTimeout, +$2CE VDataTO,
|   +$2D0 VGetXXX, +$2D2 VXmitOn, +$2D4 VRTStoCTS, +$2D6 VWait100;
|   +$2D8 SaveA45, +$2E0 SaveDskRtn, +$2E4 SavePS, +$2E8 SaveBIn, +$2EC
|   SaveBOut, +$2F0 SaveVects (3), +$2FC SaveRegs (5), +$310 VAVBufA (VIA
|   vBufA address), +$314 VSTData (6 SCC writes after a send; +$315 =
|   VDisTxRTS)
|   statistics (15 longs): +$31A IntCount (receive interrupts), +$31E
|   RcvCount (frames read to the end), +$322 XmitCount (frames sent),
|   +$326 CRCCount, +$32A OVRCount (overruns), +$32E UNDCount (receive
|   timeouts, underrunErr), +$332 NoHandCnt (no protocol handler), +$336
|   LenErrCnt, +$33A BadCount (bad control frames), +$33E CollsnCount,
|   +$342 DeferCount, +$346 IdleTOCount (deferred write timed out), +$34A
|   BadDDP (destination socket 0), +$34E NoDtaCount (no data after our
|   lapCTS), +$352 RandomCTS (unexpected control frames)
|
| Apple's sources and patches: the System 6/7 ROM patches (System 7.1
| PatchSEROM.a) name the source files of this driver -- atalk:lap.a (LAP
| code) and atalk:nonres.a (the NBP code reached through NRPtr, "non-
| resident" in the RAM driver) -- and fix three of its bugs, all in the
| VInstall patch: P019 (MPP_VBLTASK, VBLDeferCnt), PB073 (NBP_SENDREQ,
| VBL task installed twice) and PAB185 (NBP_SENDREQ, LookupName replies
| written to location 0).  A fourth suspected bug is in NBP_LISTENER_KEEP.
|
| Sources: Inside Macintosh II-261..330 ("The AppleTalk Manager"; protocol
| handlers and socket listeners II-325..329) and V-508..522, Inside
| Macintosh: Networking (1994) "DDP", "NBP", "LAP Manager", MPW 1.0
| ATalkEqu.a, System 7.1 AppleTalk.a, ATalkPrivateEQU.a, PatchSEROM.a and
| OS/NetBoot/ATIncludes (vardefs2.a, LAPvars2.a: names of the variables),
| the Zilog Z8530 SCC documentation; the Mac Plus driver for the shared
| code.
| =========================================================================

Resource_DRVR_0009_DotMPP:
| ROM resource header of DRVR 9 (8 bytes)
Resource_DRVR_0009_DotMPP_Header:
        .long   0xC0001556                      | ROM resource header: tag $C0, physical size $1556 (8 + $154E)
        .long   0x00000070                      | relative handle: master pointer at ROM zone + $70
| -------------------------------------------------------------------------
| DRVR header (Inside Macintosh II-188): flags, delay, event mask, menu,
| the offsets of the five entry points from the start of the header, the
| driver name; then the version byte (48, also stored by the Open) and 4.
| -------------------------------------------------------------------------
Driver_MPP:
| MacSEROM.lst name of the driver resource
_DRVR_9_.MPP:
        .short  0x5C00                          | drvrFlags: dNeedLock, dNeedGoodbye, dStatEnable, dCtlEnable
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no desk accessory events
        .short  0x0000                          | drvrMenu: no menu
        .short  E_MPP_Open-Driver_MPP           | drvrOpen: $0AB2
        .short  E_MPP_Prime-Driver_MPP          | drvrPrime: $03C0 (not supported)
        .short  E_MPP_Control-Driver_MPP        | drvrCtl: $001A
        .short  E_MPP_Status-Driver_MPP         | drvrStatus: $038C
        .short  E_MPP_Close-Driver_MPP          | drvrClose: $0A0A
        .byte   4                               | drvrName: length byte
        .ascii  ".MPP"                          | drvrName: driver name
        .byte   0x20                            | pad byte
        .byte   0x30,0x04                       | version 48 (as set by E_MPP_Open), 4 (not referenced)

| -------------------------------------------------------------------------
| E_MPP_Control: A0 = parameter block, A1 = .MPP DCE.  Calls the
| AtalkHk1 hook, then dispatches with A2 = MPP variables, D1.B =
| csParam+0 (socket / protType / interval / newSelfFlag), A1 = csParam+2
| (listener / wdsPointer / handler / entityPtr / ntQElPtr), D3 = csCode -
| 242, D0 = controlErr.  Also called by NBP_STARTNEXT (JSR) for the next
| queued call.
| -------------------------------------------------------------------------
E_MPP_Control:
        MOVE.L  (AtalkHk1).W,D3                 | AtalkHk1: AppleTalk hook
        BLE.B   E_MPP_CONTROL_NOHOOK            | none (<= 0) ->
        MOVEA.L D3,A2                           | A2 = hook routine
        JSR     (A2)                            | call the AtalkHk1 hook (A0 = parameter block)
E_MPP_CONTROL_NOHOOK:
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        MOVE.L  A2,D0                           | .MPP open?
        BNE.B   E_MPP_CONTROL_CSCODE            | yes ->
        MOVEQ.L #-0x11,D0                       | controlErr (-17)
        BRA.W   MPP_DONE_A1                     | -> IODone
| dispatch on csCode
E_MPP_CONTROL_CSCODE:
        MOVE.W  csCode(A0),D3                   | D3 = csCode
        BMI.B   E_MPP_CONTROL_GOODBYE           | negative: goodbye kiss ->
| csCode 1 (killCode)
        SUBQ.W  #0x1,D3                         | csCode 1?
        BNE.B   E_MPP_CONTROL_RANGE             | no ->
        RTS                                     | KillIO: nothing to cancel, return
| csCode must be 242..256
E_MPP_CONTROL_RANGE:
        MOVEQ.L #-0x11,D0                       | controlErr (-17) if out of range
        SUBI.W  #0xF1,D3                        | D3 = csCode - 242 (after the -1 above)
        BLT.W   MPP_DONE_A1                     | < 242 -> controlErr
        CMPI.W  #0xE,D3                         | > 256?
        BGT.W   MPP_DONE_A1                     | yes -> controlErr
| common arguments; 242..249 are resident, 250..256 are NBP calls
        MOVE.B  csParam(A0),D1                  | D1 = csParam+0
        MOVEA.L 0x1E(A0),A1                     | A1 = csParam+2
        CMPI.W  #0x7,D3                         | csCode > 249?
        BGT.B   E_MPP_CONTROL_NBP               | yes -> NBP code
| 242..249 through the dispatch table
        LEA.L   E_MPP_CONTROL_TBL(PC),A3        | A3 = dispatch table
        ADDA.W  D3,A3                           | + index
        ADDA.W  D3,A3                           | (word entries)
        MOVEA.W (A3),A3                         | offset from the driver start
        PEA.L   Driver_MPP(PC)                  | driver start
        ADDA.L  (SP)+,A3                        | A3 = handler
        JMP     (A3)                            | -> handler (from E_MPP_CONTROL_TBL)

| E_MPP_CONTROL_TBL - csCode 242..249, offsets from Driver_MPP
E_MPP_CONTROL_TBL:
        .short  LOOKUPREPLY-Driver_MPP          | 242 LookupReply ($0094)
        .short  WRITELAP-Driver_MPP             | 243 WriteLAP ($037A)
        .short  DETACHPH-Driver_MPP             | 244 DetachPH ($0366)
        .short  ATTACHPH-Driver_MPP             | 245 AttachPH ($0336)
        .short  WRITEDDP-Driver_MPP             | 246 WriteDDP ($015E)
        .short  CLOSESKT-Driver_MPP             | 247 CloseSkt ($010E)
        .short  OPENSKT-Driver_MPP              | 248 OpenSkt ($00B4)
        .short  LOADNBP-Driver_MPP              | 249 LoadNBP ($009E)
| negative csCode (goodbye kiss): if the NIS is open, LUCODE+2 drops the
| names in the application heap; then IODone.  D0 is not set here: the
| call completes with the low word of the MPP variables pointer
| (harmless: the result of the goodbye kiss is not looked at).
E_MPP_CONTROL_GOODBYE:
        MOVE.L  0x29A(A2),D1                    | D1 = LookupPtr
        BPL.B   E_MPP_CONTROL_GOODBYE_DONE      | NIS not open ->
        MOVEA.L D1,A3                           | A3 = LUCODE
        JSR     0x2(A3)                         | LUCODE_GOODBYE: NBP_DROPAPPLNAMES
E_MPP_CONTROL_GOODBYE_DONE:
        BRA.B   E_MPP_CONTROL_DONE              | -> IODone
| csCode 250..256: to the NBP code via NRPtr (installed by the Open)
E_MPP_CONTROL_NBP:
        MOVEA.L 0x296(A2),A3                    | A3 = NRPtr (NBP_DISPATCH)
        JMP     (A3)                            | -> NBP code

| -------------------------------------------------------------------------
| LookupReply (csCode 242): issued by NIS_LISTENER (to this driver) for a
| received LkUp packet; runs the lookup-reply code via LookupPtr
| -------------------------------------------------------------------------
LOOKUPREPLY:
        MOVE.L  0x29A(A2),D2                    | D2 = LookupPtr
        BPL.B   E_MPP_CONTROL_DONE              | not installed -> IODone (controlErr)
        MOVEA.L D2,A3                           | A3 = LUCODE
        JMP     (A3)                            | -> LUCODE_REPLY -> NBP_LKUPREPLY

| -------------------------------------------------------------------------
| LoadNBP (csCode 249): nothing to load in the ROM driver - noErr
| -------------------------------------------------------------------------
LOADNBP:
        CLR.W   D0                              | noErr
| Called by: E_MPP_CONTROL_GOODBYE, LOOKUPREPLY, CLOSESKT (via
| CLOSESKT_DONE: OPENSKT, WRITEDDP)
E_MPP_CONTROL_DONE:
        BRA.W   MPP_DONE                        | -> IODone with D0

| -------------------------------------------------------------------------
| MPP_INSTALLNBP: store NRPtr = NBP_DISPATCH (bit 31 set) and jump into
| it; E_MPP_Open calls this with D3 = 7, i.e. NBP_INIT
| -------------------------------------------------------------------------
MPP_INSTALLNBP:
        LEA.L   NBP_DISPATCH(PC),A3             | A3 = NBP code entry
        MOVE.L  A3,0x296(A2)                    | NRPtr
        BSET    #0x7,0x296(A2)                  | bit 31: NBP code installed
        JMP     (A3)                            | -> NBP_DISPATCH

| -------------------------------------------------------------------------
| OpenSkt (csCode 248): socket = 1..127 to open that socket, 0 to get a
| new one (the highest free one of 128..254, returned in socket);
| listener = socket listener.  ddpSktErr if in use, >= 128 or the table
| is full.
| -------------------------------------------------------------------------
OPENSKT:
        BSR.B   MPP_OPENSOCKET                  | open socket D1, listener A1
        MOVE.B  D1,csParam(A0)                  | return the socket number
        BRA.B   CLOSESKT_DONE                   | -> IODone with D0

| -------------------------------------------------------------------------
| MPP_OPENSOCKET: open socket D1 (0 = assign a dynamic one) with listener
| A1: statically assigned sockets 1..127 go into the 12-entry socket
| table, dynamic ones into the listener table of $80..$FE -> D1.B =
| socket, D0 = noErr or ddpSktErr.  Uses D2.  Also called through
| JDDPWrite+2 (MPP_JOPENSOCKET) by the NBP code.
| -------------------------------------------------------------------------
MPP_OPENSOCKET:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr (-91)
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        TST.B   D1                              | socket 0?
        BEQ.B   MPP_OPENSOCKET_DAS              | yes: assign a dynamic socket ->
        BMI.B   MPP_OPENSOCKET_EXIT             | >= 128 -> ddpSktErr
        BSR.B   MPP_FINDSKT                     | already open?
        BEQ.B   MPP_OPENSOCKET_EXIT             | yes -> ddpSktErr
| find a free entry in the socket table
        MOVEQ.L #0xB,D2                         | 12 entries
MPP_OPENSOCKET_LOOP:
        TST.B   0x4C(A2,D2.W)                   | entry free?
        DBEQ.W  D2,MPP_OPENSOCKET_LOOP          | no -> next
        BNE.B   MPP_OPENSOCKET_EXIT             | table full -> ddpSktErr
        MOVE.B  D1,0x4C(A2,D2.W)                | socket number
        LSL.W   #0x2,D2                         | long index
        MOVE.L  A1,0x58(A2,D2.W)                | socket listener
MPP_OPENSOCKET_NOERR:
        CLR.W   D0                              | noErr
MPP_OPENSOCKET_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return from MPP_OPENSOCKET
| dynamic socket: the highest free entry of the table at +$8C
MPP_OPENSOCKET_DAS:
        MOVE.W  #0x1F8,D2                       | D2 = offset of socket $FE ((254 - 128) * 4)
        MOVE.L  A3,D1                           | save A3
        LEA.L   0x288(A2),A3                    | A3 -> end of the table (+$8C + 127 * 4)
MPP_OPENSOCKET_DASLOOP:
        TST.L   -(A3)                           | listener 0: free?
        BEQ.B   MPP_OPENSOCKET_DASFOUND         | yes ->
        SUBQ.W  #0x4,D2                         | next lower socket
        BPL.B   MPP_OPENSOCKET_DASLOOP          | down to $80
        MOVEA.L D1,A3                           | restore A3
        BRA.B   MPP_OPENSOCKET_EXIT             | all in use -> ddpSktErr
MPP_OPENSOCKET_DASFOUND:
        MOVE.L  A1,(A3)                         | listener of the socket
        MOVEA.L D1,A3                           | restore A3
        LSR.W   #0x2,D2                         | entry number
        ADDI.B  #0x80,D2                        | socket = $80 + entry
        MOVE.B  D2,D1                           | D1.B = socket
        BRA.B   MPP_OPENSOCKET_NOERR            | -> noErr

| -------------------------------------------------------------------------
| CloseSkt (csCode 247): close socket D1 (statically assigned: free its
| table entry; dynamic: clear its listener).  ddpSktErr if 0 or not open.
| -------------------------------------------------------------------------
CLOSESKT:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr (-91)
        TST.B   D1                              | socket 0?
        BEQ.B   CLOSESKT_DONE                   | yes -> ddpSktErr
        BMI.B   CLOSESKT_DAS                    | 128..255: dynamic socket ->
        BSR.B   MPP_FINDSKT                     | D2 = its entry
        BNE.B   CLOSESKT_DONE                   | not open -> ddpSktErr
        CLR.B   0x4C(A2,D2.W)                   | free the entry
CLOSESKT_NOERR:
        CLR.W   D0                              | noErr
| Called by: OPENSKT, CLOSESKT, WRITEDDP
CLOSESKT_DONE:
        BRA.W   E_MPP_CONTROL_DONE              | -> IODone with D0
CLOSESKT_DAS:
        BSR.B   MPP_FINDDAS                     | D2 = offset of its listener
        TST.W   D2                              | open?
        BMI.B   CLOSESKT_DONE                   | no -> ddpSktErr
        ADDA.W  D2,A2                           | A2 = MPP variables + offset
        CLR.L   0x8C(A2)                        | listener 0: socket closed
        SUBA.W  D2,A2                           | A2 = MPP variables again
        BRA.B   CLOSESKT_NOERR                  | -> noErr

| -------------------------------------------------------------------------
| MPP_FINDSKT: find socket D1 in the socket table (statically assigned
| sockets) -> EQ and D2 = entry if found
| Called by MPP_OPENSOCKET, CLOSESKT, DDPWRITE.
| -------------------------------------------------------------------------
MPP_FINDSKT:
        MOVEQ.L #0xB,D2                         | 12 entries
MPP_FINDSKT_LOOP:
        CMP.B   0x4C(A2,D2.W),D1                | this socket?
        DBEQ.W  D2,MPP_FINDSKT_LOOP             | no -> next
        RTS                                     | EQ = found

| -------------------------------------------------------------------------
| MPP_FINDDAS: dynamic socket D1 ($80..$FE): D2 = offset of its listener
| in the table at +$8C ((D1 - $80) * 4) if it is open, else D2 = -1.
| Called by CLOSESKT, DDPWRITE.
| -------------------------------------------------------------------------
MPP_FINDDAS:
        MOVEQ.L #0x0,D2                         | D2.L = 0
        MOVE.B  D1,D2                           | D2 = socket
        CMPI.W  #0xFE,D2                        | $FF?
        BHI.B   MPP_FINDDAS_NONE                | yes -> not a socket
        SUBI.W  #0x80,D2                        | entry number (negative below $80)
        LSL.W   #0x2,D2                         | offset
        ADDA.W  D2,A2                           | A2 = MPP variables + offset
        TST.L   0x8C(A2)                        | listener set (socket open)?
        SUBA.W  D2,A2                           | A2 = MPP variables again
        BNE.B   MPP_FINDDAS_EXIT                | yes -> D2 = offset
MPP_FINDDAS_NONE:
        MOVEQ.L #-0x1,D2                        | D2 = -1: not open
MPP_FINDDAS_EXIT:
        RTS                                     | return from MPP_FINDDAS (test D2)

| -------------------------------------------------------------------------
| WriteDDP (csCode 246): send the datagram described by the WDS at
| wdsPointer from socket D1; checksumFlag = checksum long headers.
| -------------------------------------------------------------------------
WRITEDDP:
        MOVE.B  0x1D(A0),D3                     | D3 = checksumFlag
        BSR.B   MPP_JDDPWRITE                   | DDPWRITE
        BRA.B   CLOSESKT_DONE                   | -> IODone with D0

| -------------------------------------------------------------------------
| MPP_JDDPWRITE: the JDDPWrite entries (MPP variables +$2A2): +0 DDPWRITE,
| +2 MPP_JOPENSOCKET (MPP_OPENSOCKET), used by the NBP code
| -------------------------------------------------------------------------
MPP_JDDPWRITE:
        BRA.B   DDPWRITE                        | +0: -> DDPWRITE
MPP_JOPENSOCKET:
        BRA.W   MPP_OPENSOCKET                  | +2: -> MPP_OPENSOCKET

| -------------------------------------------------------------------------
| DDPWRITE: send a datagram.  A1 = WDS (first entry -> 16-byte header
| area at an odd address: +7 dest net, +11 dest node, +13 dest socket,
| +15 DDP type), D1 = source socket (open: static or dynamic), D3.B =
| checksum flag.  Builds a short header (dest net 0 or ours) or a long one,
| then LAPWRITE (returns through LAPWrtRtn, possibly later).  D0 = noErr,
| ddpSktErr, ddpLenErr, noBridgeErr or excessCollsns.
| Called by WRITEDDP (via MPP_JDDPWRITE), NBP_SENDREQ, NBP_VBLTASK,
| NBP_SENDREPLY (via JDDPWrite)
| -------------------------------------------------------------------------
DDPWRITE:
        MOVEQ.L #-0x5B,D0                       | ddpSktErr (-91)
        TST.B   D1                              | socket 0?
        BEQ.B   DDPWRITE_EXIT                   | yes -> ddpSktErr
        BSR.B   MPP_FINDDAS                     | an open dynamic socket?
        TST.W   D2                              | ...
        BPL.B   DDPWRITE_SKTOK                  | yes ->
        BSR.B   MPP_FINDSKT                     | an open static socket?
        BNE.B   DDPWRITE_EXIT                   | no -> ddpSktErr
DDPWRITE_SKTOK:
| complete the header in the first WDS entry
        MOVE.L  A1,-(SP)                        | save the WDS pointer
        ADDQ.W  #0x2,A1                         | skip the length of entry 1
        MOVEA.L (A1)+,A3                        | A3 = header area
        ADDQ.W  #0x7,A3                         | A3 -> +7 dest network
        MOVE.B  D1,0x7(A3)                      | +14 source socket
        MOVE.W  (A3),D0                         | D0 = dest network
        BEQ.B   DDPWRITE_SHORT                  | 0 = this network -> short header
        CMP.W   0x1A(A2),D0                     | = sysNetNum?
        BEQ.B   DDPWRITE_SHORT                  | yes -> short header
| long header: source network and node, optional checksum
        MOVE.W  0x1A(A2),0x2(A3)                | +9 source network = sysNetNum
        MOVE.B  (A2),0x5(A3)                    | +12 source node = sysLAPAddr
        MOVE.B  0x4(A3),D1                      | D1 = dest node (+11)
        MOVEA.L A3,A0                           | A0 -> checksummed part (from +7)
        CLR.W   -(A3)                           | +5 ddpChecksum = 0
        TST.B   D3                              | checksum wanted?
        BEQ.B   DDPWRITE_LONG                   | no ->
        MOVEQ.L #0x9,D0                         | 9 header bytes (+7..+15)
        CLR.W   D3                              | checksum = 0
        CLR.W   D2                              | D2 bits 15-8 clear for DDPWRITE_CHECKSUM
        BSR.B   DDPWRITE_CHECKSUM               | add them
DDPWRITE_CKSLOOP:
        MOVE.W  (A1)+,D0                        | D0 = length of the next WDS entry
        BEQ.B   DDPWRITE_CKSDONE                | 0 = end of WDS ->
        MOVEA.L (A1)+,A0                        | A0 = its data
        BSR.B   DDPWRITE_CHECKSUM               | add them
        BRA.B   DDPWRITE_CKSLOOP                | next entry
| store the checksum (a computed 0 is sent as $FFFF)
DDPWRITE_CKSDONE:
        MOVE.W  D3,(A3)                         | ddpChecksum
        BNE.B   DDPWRITE_LONG                   | not 0 ->
        SUBQ.W  #0x1,(A3)                       | 0 -> $FFFF
| LAP type longDDP; the frame goes to the bridge, if one is known
DDPWRITE_LONG:
        MOVEQ.L #0x2,D3                         | D3 = LAP type 2 (longDDP)
        MOVEQ.L #0x10,D0                        | header entry: 3 LAP + 13 DDP bytes
        MOVE.B  0x19(A2),D2                     | D2 = sysABridge
        BNE.B   DDPWRITE_LENGTH                 | bridge known -> send to it
        MOVE.B  D1,D2                           | else send to the dest node directly ...
        TST.W   0x1A(A2)                        | ... when no network number is known
        BEQ.B   DDPWRITE_LENGTH                 | sysNetNum = 0 ->
        MOVEQ.L #-0x5D,D0                       | noBridgeErr (-93)
        ADDQ.W  #0x4,SP                         | drop the WDS pointer
        RTS                                     | return with the error

| -------------------------------------------------------------------------
| DDPWRITE_CHECKSUM: DDP checksum over D0 bytes at (A0)+ into D3 (add,
| rotate left one bit); D2 bits 15-8 must be clear
| Called by DDPWRITE (header, WDS entries) and EP_LISTENER_GOT.
| -------------------------------------------------------------------------
DDPWRITE_CHECKSUM:
        MOVE.B  (A0)+,D2                        | next byte
        ADD.W   D2,D3                           | add it
        ROL.W   #0x1,D3                         | rotate left one bit
        SUBQ.W  #0x1,D0                         | count
        BNE.B   DDPWRITE_CHECKSUM               | loop
| Called by: DDPWRITE, DDP_RCVLONG, DDP_RCVSHORT, DDPWRITE_LENERR
DDPWRITE_EXIT:
        RTS                                     | return from DDPWRITE_CHECKSUM / DDPWRITE

| -------------------------------------------------------------------------
| DDPWRITE_SHORT: short header - move dest socket, source socket and type
| down to +5..+7 (over the high byte of the dest network); LAP
| destination = dest node, LAP type shortDDP
| -------------------------------------------------------------------------
DDPWRITE_SHORT:
        MOVEA.L A3,A0                           | A0 -> +7
        ADDQ.W  #0x8,A0                         | A0 -> +15 DDP type
        MOVE.B  (A0),(A3)                       | +7 = DDP type (sDDPType)
        MOVE.W  -(A0),-(A3)                     | +5/+6 = dest/source socket (from +13/+14)
        SUBQ.W  #0x2,A0                         | A0 -> +11
        MOVE.B  (A0),D2                         | D2 = dest node
        MOVEQ.L #0x1,D3                         | D3 = LAP type 1 (shortDDP)
        MOVEQ.L #0x8,D0                         | header entry: 3 LAP + 5 DDP bytes
| total length from the WDS
DDPWRITE_LENGTH:
        MOVEA.L (SP)+,A1                        | A1 = WDS
        MOVE.W  D0,(A1)                         | length of entry 1 = header size
        CLR.W   D1                              | D1 = total length
        MOVEA.L A1,A0                           | A0 -> first entry
DDPWRITE_LENLOOP:
        TST.W   (A0)                            | length 0 = end?
        BEQ.B   DDPWRITE_SEND                   | yes ->
        BMI.B   DDPWRITE_LENERR                 | negative -> ddpLenErr
        ADD.W   (A0),D1                         | add the length
        ADDQ.W  #0x6,A0                         | next entry (6 bytes)
        BRA.B   DDPWRITE_LENLOOP                | loop
| ddpLength, LAP type and destination, then LAPWRITE
DDPWRITE_SEND:
        MOVE.W  D1,-(A3)                        | +3 length word = total
        SUBQ.W  #0x3,(A3)                       | - LAP header = datagram length
        SUB.W   D0,D1                           | D1 = data length
        CMPI.W  #0x24A,D1                       | > ddpMaxData (586)?
        BHI.B   DDPWRITE_LENERR                 | yes -> ddpLenErr
        MOVE.B  D3,-(A3)                        | +2 lapType
        SUBQ.W  #0x2,A3                         | A3 -> +0
        MOVE.B  D2,(A3)                         | +0 lapDstAdr (+1 lapSrcAdr: set by LAP_SENDFRAME)
        BRA.W   LAPWRITE                        | send the frame (A1 = WDS)
| datagram too long
DDPWRITE_LENERR:
        MOVEQ.L #-0x5C,D0                       | ddpLenErr (-92)
        BRA.B   DDPWRITE_EXIT                   | -> return

| -------------------------------------------------------------------------
| DDP_RCVLONG: protocol handler of LAP type 2 (longDDP).  Reads the other
| 11 header bytes into the RHA; delivers only datagrams for our network.
| -------------------------------------------------------------------------
DDP_RCVLONG:
        MOVEQ.L #0xB,D3                         | 11 bytes (13-byte header, length already read)
        MOVE.W  0x1A(A2),D2                     | D2 = sysNetNum
        JSR     (A4)                            | ReadPacket
        BNE.B   DDPWRITE_EXIT                   | error -> return
        CMP.W   0x8(A2),D2                      | ddpDstNet (RHA+7) = our network?
        BEQ.B   DDP_RCVSOCKET                   | yes -> to the socket listener
        BRA.B   DDP_RCVDISCARD                  | no -> drop

| -------------------------------------------------------------------------
| DDP_RCVSHORT: protocol handler of LAP type 1 (shortDDP).  Reads the
| other 3 header bytes (dest socket, source socket, type) into the RHA.
| -------------------------------------------------------------------------
DDP_RCVSHORT:
        MOVEQ.L #0x3,D3                         | 3 bytes (5-byte header, length already read)
        JSR     (A4)                            | ReadPacket
        BNE.B   DDPWRITE_EXIT                   | error -> return
| DDP_RCVSOCKET: jump to the listener of the destination socket (D0):
| 1..127 from the socket table, $80..$FE from the dynamic-socket table;
| socket 0 is counted (BadDDP) and dropped, $FF dropped
DDP_RCVSOCKET:
        MOVEQ.L #0xB,D2                         | 12 socket table entries
        MOVE.B  -0x3(A3),D0                     | D0 = destination socket (3 bytes before A3)
        BEQ.B   DDP_RCVBADSKT                   | socket 0 -> count, drop
        BPL.B   DDP_RCVSOCKET_LOOP              | 1..127 -> socket table
        CMPI.B  #0xFE,D0                        | $FF?
        BHI.B   DDP_RCVDISCARD                  | yes -> drop
        MOVEQ.L #0x0,D2                         | D2.L = 0
        MOVE.B  D0,D2                           | D2 = socket
        SUBI.W  #0x80,D2                        | entry number
        LSL.W   #0x2,D2                         | offset
        LEA.L   0x8C(A2),A5                     | A5 = dynamic-socket listeners
        MOVE.L  0x0(A5,D2.W),D2                 | D2 = listener of the socket
        BEQ.B   DDP_RCVDISCARD                  | not open -> drop
        MOVEA.L D2,A5                           | A5 = socket listener
        JMP     (A5)                            | -> listener of the dynamic socket
DDP_RCVSOCKET_LOOP:
        CMP.B   0x4C(A2,D2.W),D0                | this socket?
        DBEQ.W  D2,DDP_RCVSOCKET_LOOP           | no -> next
        BNE.B   DDP_RCVDISCARD                  | not open -> drop
        LSL.W   #0x2,D2                         | long index
        MOVEA.L 0x58(A2,D2.W),A5                | A5 = socket listener
        JMP     (A5)                            | -> listener of the static socket
DDP_RCVBADSKT:
        ADDQ.L  #0x1,0x34A(A2)                  | BadDDP + 1
| DDP_RCVDISCARD: drop the packet - ReadRest with D3 = 0 (left 0 by the
| successful ReadPacket)
| Called by: DDP_RCVLONG, DDP_RCVSOCKET, DDP_RCVSOCKET_LOOP, RTMP_LISTENER
DDP_RCVDISCARD:
        JMP     0x2(A4)                         | ReadRest: discard the rest, return to MPP

| -------------------------------------------------------------------------
| RTMP_LISTENER: listener of socket 1 (RTMP).  From an RTMP data packet
| (DDP type 1) it takes the network number and the router's node ID
| (ID length 8): sysNetNum, sysABridge, BridgeTime = 255 (aged by
| MPP_VBLTASK).  The RTMP header is read over the DDP type byte, so the
| network number lands word aligned.
| -------------------------------------------------------------------------
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
        ST.B    0x2C6(A2)                       | BridgeTime = 255 VBL periods
        MOVE.W  -(A3),0x1A(A2)                  | sysNetNum = rtmpNet
RTMP_LISTENER_EXIT:
        RTS                                     | return to MPP

| -------------------------------------------------------------------------
| EP_LISTENER: listener of socket 4, the Echo Protocol's echoer (DDP type
| 4; Inside Macintosh V-519, Networking "DDP").  An Echo Request (first
| data byte 1) is read into the EP buffer (EPBufPtr: a parameter block for
| WriteDDP from socket 4 with its WDS at +$22, a DDP header template at
| +$31 (odd) and the data at +$41) and sent back as an Echo Reply (2) to
| the requester through an async WriteDDP call to this driver.  While the
| previous reply is still being sent (ioResult > 0), requests are dropped;
| a long-header request with a wrong checksum is ignored.
| -------------------------------------------------------------------------
EP_LISTENER:
        CMPI.B  #0x4,-(A3)                      | A3 back to the DDP type byte: type 4 (AEP)?
        BNE.B   EP_LISTENER_DISCARD             | no -> drop
        MOVE.L  A3,D2                           | D2 -> DDP type byte in the RHA
        MOVEA.L 0x88(A2),A3                     | A3 = EP buffer (EPBufPtr)
        TST.W   ioResult(A3)                    | previous reply still being sent?
        BGT.B   EP_LISTENER_DISCARD             | yes -> drop
        MOVE.W  #0x24A,D3                       | up to ddpMaxData (586) bytes
        LEA.L   0x41(A3),A3                     | A3 -> data area of the EP buffer
        JSR     0x2(A4)                         | ReadRest: the echo data
        BEQ.B   EP_LISTENER_GOT                 | ok ->
        RTS                                     | error -> return to MPP
EP_LISTENER_DISCARD:
        CLR.W   D3                              | buffer size 0
        JMP     0x2(A4)                         | ReadRest: discard, return to MPP
| answer an Echo Request
EP_LISTENER_GOT:
        MOVE.W  #0x24A,D0                       | buffer size
        SUB.W   D3,D0                           | - bytes not filled = bytes received
        BEQ.B   EP_LISTENER_EXIT                | none -> ignore
        MOVEA.L 0x88(A2),A0                     | A0 = EP buffer (parameter block)
        CMPI.B  #0x1,0x41(A0)                   | function 1 = Echo Request?
        BNE.B   EP_LISTENER_EXIT                | no (a reply) -> ignore
        MOVE.W  D0,0x28(A0)                     | WDS entry 2 length = data length
        MOVEA.L D2,A3                           | A3 -> DDP type byte in the RHA
        MOVE.B  -(A3),0x3E(A0)                  | header +13 dest socket = source socket of the request
        MOVE.B  0x2(A2),D0                      | D0 = lapSrcAdr (requester node, short header)
        MOVEQ.L #0x0,D1                         | D1 = network 0
        SUBQ.B  #0x1,0x3(A2)                    | lapType = 1 (shortDDP)? (byte destroyed)
        BEQ.B   EP_LISTENER_REPLY               | yes -> address complete
| long header: verify a nonzero checksum, then take ddpSrcNet/ddpSrcNode
        MOVEA.L A0,A1                           | A1 = EP buffer
        LEA.L   0x6(A2),A0                      | A0 -> ddpChecksum in the RHA
        MOVE.W  (A0)+,D1                        | D1 = ddpChecksum
        SNE.B   0x1D(A1)                        | checksumFlag of the reply = (request was checksummed)
        BEQ.B   EP_LISTENER_LONG                | no checksum ->
        MOVEQ.L #0x9,D0                         | 9 header bytes (ddpDstNet .. ddpType)
        CLR.W   D3                              | checksum = 0
        CLR.W   D2                              | D2 bits 15-8 clear
        BSR.W   DDPWRITE_CHECKSUM               | add them
        LEA.L   0x41(A1),A0                     | A0 = echo data
        MOVE.W  0x28(A1),D0                     | D0 = data length
        BSR.W   DDPWRITE_CHECKSUM               | add them
        TST.W   D3                              | computed checksum = 0?
        BNE.B   EP_LISTENER_CKSCMP              | no ->
        SUBQ.W  #0x1,D3                         | yes: $FFFF
EP_LISTENER_CKSCMP:
        CMP.W   D3,D1                           | = ddpChecksum?
        BNE.B   EP_LISTENER_EXIT                | no -> ignore the request
EP_LISTENER_LONG:
        MOVEA.L A1,A0                           | A0 = EP buffer
        MOVE.B  -0x2(A3),D0                     | D0 = ddpSrcNode
        MOVE.W  -0x5(A3),D1                     | D1 = ddpSrcNet
| reply: destination = requester, function 2, WriteDDP (async)
EP_LISTENER_REPLY:
        MOVE.B  D0,0x3C(A0)                     | header +11 dest node
        MOVE.W  D1,0x38(A0)                     | header +7 dest network
        ADDQ.B  #0x1,0x41(A0)                   | function 2 = Echo Reply
        _ControlAsync                           | WriteDDP (csCode 246) from socket 4
EP_LISTENER_EXIT:
        RTS                                     | return to MPP

| -------------------------------------------------------------------------
| AttachPH (csCode 245): enter protocol handler handler for LAP type
| protType (1..127) in the protocol table.  lapProtErr if invalid,
| already attached or the table (8 entries, 2 used by DDP) is full.
| -------------------------------------------------------------------------
ATTACHPH:
        MOVEQ.L #-0x5E,D0                       | lapProtErr (-94)
        TST.B   D1                              | protType 1..127?
        BLE.B   ATTACHPH_DONE                   | no -> lapProtErr
        BSR.B   MPP_FINDPH                      | already attached?
        BEQ.B   ATTACHPH_DONE                   | yes -> lapProtErr
        MOVEQ.L #0x7,D2                         | 8 entries
ATTACHPH_LOOP:
        LEA.L   0x24(A2,D2.W),A3                | A3 -> protocol type of the entry
        TST.B   (A3)                            | free ($FF)?
        DBMI.W  D2,ATTACHPH_LOOP                | no -> next
        BPL.B   ATTACHPH_DONE                   | table full -> lapProtErr
        LSL.W   #0x2,D2                         | long index
        MOVE.L  A1,0x2C(A2,D2.W)                | protocol handler
        MOVE.B  D1,(A3)                         | protocol type
ATTACHPH_NOERR:
        CLR.W   D0                              | noErr
| Called by: ATTACHPH, DETACHPH, WRITELAP
ATTACHPH_DONE:
        BRA.B   MPP_DONE                        | -> IODone with D0

| -------------------------------------------------------------------------
| MPP_FINDPH: find LAP type D1 in the protocol table -> EQ and D2 =
| entry if found
| -------------------------------------------------------------------------
MPP_FINDPH:
        MOVEQ.L #0x7,D2                         | 8 entries
MPP_FINDPH_LOOP:
        CMP.B   0x24(A2,D2.W),D1                | this type?
        DBEQ.W  D2,MPP_FINDPH_LOOP              | no -> next
        RTS                                     | EQ = found

| -------------------------------------------------------------------------
| DetachPH (csCode 244): remove LAP type protType from the protocol
| table.  lapProtErr if not attached.
| -------------------------------------------------------------------------
DETACHPH:
        MOVEQ.L #-0x5E,D0                       | lapProtErr (-94)
        MOVEQ.L #0x7,D2                         | 8 entries
DETACHPH_LOOP:
        CMP.B   0x24(A2,D2.W),D1                | this type?
        DBEQ.W  D2,DETACHPH_LOOP                | no -> next
        BNE.B   ATTACHPH_DONE                   | not attached -> lapProtErr
        ST.B    0x24(A2,D2.W)                   | entry free ($FF)
        BRA.B   ATTACHPH_NOERR                  | -> IODone, noErr

| -------------------------------------------------------------------------
| WriteLAP (csCode 243): send the frame described by the WDS at
| wdsPointer (first entry: lapDstAdr, lapSrcAdr filled in, lapType
| 1..127, then the data).  lapProtErr, excessCollsns.
| -------------------------------------------------------------------------
WRITELAP:
        MOVEA.L 0x2(A1),A0                      | A0 = first WDS entry (LAP header)
        MOVEQ.L #-0x5E,D0                       | lapProtErr (-94)
        TST.B   0x2(A0)                         | lapType 1..127?
        BLE.B   ATTACHPH_DONE                   | no -> lapProtErr
        MOVE.B  (A0),D2                         | D2 = lapDstAdr
        BSR.B   LAPWRITE                        | send it (A1 = WDS)
        BRA.B   MPP_DONE                        | -> IODone with D0

| -------------------------------------------------------------------------
| E_MPP_Status: csCode 400 copies the 15 statistics counters (+$31A) to
| the 60-byte buffer at csParam and clears them, interrupts off; any other
| csCode: statusErr.  Note: D0 is -1 after the DBF loop, so the call
| completes with ioResult -1, not noErr.
| -------------------------------------------------------------------------
E_MPP_Status:
        MOVEQ.L #-0x12,D0                       | statusErr (-18)
        CMPI.W  #0x190,csCode(A0)               | csCode 400 (statistics)?
        BNE.B   MPP_DONE                        | no -> IODone (statusErr)
        MOVEA.L csParam(A0),A1                  | A1 = buffer (csParam)
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        ADDA.W  #0x31A,A2                       | A2 -> statistics (IntCount)
        MOVEQ.L #0xE,D0                         | 15 counters
        MOVEQ.L #0x0,D1                         | D1 = 0
E_MPP_STATUS_LOOP:
        MOVE.L  (A2),(A1)+                      | copy the counter
        MOVE.L  D1,(A2)+                        | and clear it
        DBF.W   D0,E_MPP_STATUS_LOOP            | next one (ends with D0 = -1)
        MOVE.W  (SP)+,SR                        | restore SR
| MPP_DONE / MPP_DONE_A1: IODone with D0 (A1 = .MPP DCE from AbusDCE /
| already in A1)
| Called by: E_MPP_CONTROL_DONE, ATTACHPH_DONE (AttachPH, DetachPH),
| WRITELAP, E_MPP_Status; MPP_DONE_A1 by E_MPP_Control
MPP_DONE:
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE (AbusDCE)
MPP_DONE_A1:
        MOVE.L  (JIODone).W,-(SP)               | push the IODone vector
        RTS                                     | -> IODone (completes the current call)

| -------------------------------------------------------------------------
| .MPP Prime: not supported - clear drvrActive and return without
| completing the call
| -------------------------------------------------------------------------
E_MPP_Prime:
        BCLR    #0x7,dCtlFlags+1(A1)            | dCtlFlags: clear drvrActive
        RTS                                     | return from E_MPP_Prime

| -------------------------------------------------------------------------
| LAPWRITE: send a LocalTalk frame.  A1 = WDS (first entry: frame header),
| D2 = destination node ($FF = broadcast).  The return address is kept in
| LAPWrtRtn and the write ends with a jump there (D0 = noErr or
| excessCollsns); when the line is busy the call returns to the caller's
| caller at once and the write resumes later from LAP_EXTINT or
| MPP_VBLTASK.  With SelfSend on, a data frame for our own node is only
| handed to our own protocol handler (LAPWRITE_SELF), a broadcast is
| handed to it and then sent.  Each network attempt: random wait
| (lbackOff), inter-dialog gap, sync pulse, lapRTS (lapENQ when fSendENQ
| is set) to D2, wait for lapCTS (none for a broadcast), then the data
| frame (LAP_SENDFRAME).
| Called by: DDPWRITE (DDPWRITE_SEND), WRITELAP, MPP_LAPSEND
| -------------------------------------------------------------------------
LAPWRITE:
        CLR.B   0x2BE(A2)                       | fSendENQ = 0: a data frame
        MOVE.L  A1,0x2B0(A2)                    | WDSPtr = WDS
| LAPWRITE_ENQ: entry used to send an ENQ (fSendENQ set by the caller)
LAPWRITE_ENQ:
        MOVE.L  (SP)+,0x2B4(A2)                 | LAPWrtRtn = return address
        MOVE.L  (ATalkHk2).W,D3                 | AtalkHk2: AppleTalk hook
        BLE.B   LAPWRITE_NOHOOK                 | none (<= 0) ->
        MOVEA.L D3,A3                           | A3 = hook routine
        JSR     (A3)                            | call the AtalkHk2 hook
| intranode delivery (SelfSend on, data frame for us or broadcast)?
LAPWRITE_NOHOOK:
        TST.B   0x2AE(A2)                       | SelfSend on?
        BEQ.W   LAPWRITE_NETWORK                | no -> to the network
        TST.B   0x2BE(A2)                       | fSendENQ (an ENQ)?
        BNE.B   LAPWRITE_SELFCHK                | yes -> to the network
        CMP.B   (A2),D2                         | to our own node?
        BEQ.B   LAPWRITE_SELF                   | yes -> deliver here only
        CMPI.B  #0xFF,D2                        | broadcast?
LAPWRITE_SELFCHK:
        BNE.W   LAPWRITE_NETWORK                | no -> to the network
| hand the frame to our protocol handler: LAP header and length word into
| the RHA, then the handler reads the rest through SELF_READ_JT
LAPWRITE_SELF:
        MOVEM.L D2/A1-A2/A4-A5,-(SP)            | save registers
        MOVE.W  SR,-(SP)                        | save SR
        LEA.L   0x1(A2),A3                      | A3 = RHA (toRHA)
        MOVEQ.L #0x5,D3                         | 5 bytes: LAP header + length word
        SUBA.L  A0,A0                           | A0 = 0: offset in the current WDS entry
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        BSR.B   SELF_COPY                       | copy them from the WDS
        MOVE.B  (A2),0x2(A2)                    | RHA lapSrcAdr = sysLAPAddr
        MOVEQ.L #0x7,D2                         | 8 protocol table entries
        MOVE.B  0x3(A2),D0                      | D0 = lapType
        MOVE.W  0x4(A2),D1                      | D1 = length word
        ANDI.W  #0x3FF,D1                       | datagram length (10 bits)
        SUBQ.W  #0x2,D1                         | D1 = bytes left after the length word
LAPWRITE_SELFPH:
        CMP.B   0x24(A2,D2.W),D0                | handler for this type?
        DBEQ.W  D2,LAPWRITE_SELFPH              | no -> next
        BNE.B   LAPWRITE_SELFDONE               | none -> skip
        LSL.W   #0x2,D2                         | long index
        MOVEA.L 0x2C(A2,D2.W),A5                | A5 = protocol handler
        LEA.L   SELF_READ_JT(PC),A4             | A4 = ReadPacket/ReadRest from the WDS
        JSR     (A5)                            | call the protocol handler (it returns with RTS)
LAPWRITE_SELFDONE:
        MOVE.W  (SP)+,SR                        | restore SR
        MOVEM.L (SP)+,D2/A1-A2/A4-A5            | restore registers
        CMPI.B  #0xFF,D2                        | broadcast?
        BEQ.B   LAPWRITE_NETWORK                | yes -> send it to the others too
        MOVEA.L 0x2B4(A2),A0                    | A0 = LAPWrtRtn
        MOVEQ.L #0x0,D0                         | noErr
        JMP     (A0)                            | continue the caller

| -------------------------------------------------------------------------
| SELF_READ_JT: A4 for a protocol handler called by LAPWRITE_SELF -
| JSR (A4) = ReadPacket, JSR 2(A4) = ReadRest; they copy from the frame
| being sent (A1 = current WDS entry, A0 = offset in it) instead of
| reading the SCC.  D1 = bytes left; results as LAP_READ_JT (no CRC).
| -------------------------------------------------------------------------
SELF_READ_JT:
        BRA.B   SELF_READPACKET                 | (A4): ReadPacket; 2(A4) = SELF_READREST below
| SELF_READREST: copy the rest (D1 bytes) into the D3-byte buffer at A3;
| D3 = 0 exact, > 0 bytes not filled, < 0 bytes that did not fit; noErr
SELF_READREST:
        TST.W   D3                              | buffer size 0?
        BEQ.B   SELF_READREST_END               | yes -> nothing to copy
        SUB.W   D3,D1                           | D1 = bytes left - buffer size
        BSR.B   SELF_COPY                       | copy D3 bytes
SELF_READREST_END:
        MOVE.W  D1,D3                           | D3 = -(bytes left - buffer size)
        NEG.W   D3                              | (see above)
        MOVEQ.L #0x0,D0                         | noErr (EQ)
        RTS                                     | return to the handler
| SELF_READPACKET: copy D3 bytes to (A3)+; D1 -= D3; lengthErr if the
| frame ended early
SELF_READPACKET:
        SUB.W   D3,D1                           | bytes left after this read
        BSR.B   SELF_COPY                       | copy D3 bytes
        BEQ.B   SELF_READPACKET_EXIT            | all copied -> EQ
        MOVEQ.L #-0x4,D0                        | lengthErr (-4)
SELF_READPACKET_EXIT:
        RTS                                     | return to the handler

| -------------------------------------------------------------------------
| SELF_COPY: copy D3 bytes of the frame described by the WDS (A1 ->
| current entry, A0 = offset in it) to (A3)+, entry after entry ->
| D0 = D3 = bytes not copied (0, EQ: all).  Uses _BlockMove.
| Called by LAPWRITE_SELF, SELF_READREST, SELF_READPACKET.
| -------------------------------------------------------------------------
SELF_COPY:
        MOVEQ.L #0x0,D0                         | D0.L = 0
        MOVE.W  (A1),D0                         | D0 = length of the current entry
        SUB.W   A0,D0                           | - offset = bytes left in it
        BNE.B   SELF_COPY_PART                  | some ->
        ADDQ.W  #0x6,A1                         | entry used up: next entry
        SUBA.L  A0,A0                           | offset 0
        MOVE.W  (A1),D0                         | D0 = its length
        BEQ.B   SELF_COPY_EXIT                  | 0 = end of the WDS ->
SELF_COPY_PART:
        CMP.W   D0,D3                           | fewer wanted than the entry has?
        BCC.B   SELF_COPY_MOVE                  | no ->
        MOVE.W  D3,D0                           | yes: copy only D3
SELF_COPY_MOVE:
        MOVEM.L D0/A0-A1,-(SP)                  | save count, offset, entry
        ADDA.L  0x2(A1),A0                      | A0 = entry pointer + offset (source)
        MOVEA.L A3,A1                           | A1 = destination
        _BlockMove                              | copy D0 bytes
        MOVEM.L (SP)+,D0/A0-A1                  | restore count, offset, entry
        ADDA.W  D0,A0                           | offset += count
        ADDA.W  D0,A3                           | destination += count
        SUB.W   D0,D3                           | bytes still wanted
        BNE.B   SELF_COPY                       | more -> next part
SELF_COPY_EXIT:
        MOVE.W  D3,D0                           | D0 = bytes not copied
        RTS                                     | return from SELF_COPY (EQ = all)

| -------------------------------------------------------------------------
| LAPWRITE_NETWORK: send the frame on the network.  First adapt the
| global backoff mask to the collision/deferral history of the last 8
| sends.
| -------------------------------------------------------------------------
LAPWRITE_NETWORK:
        MOVE.B  D2,0x2BA(A2)                    | DestNode
        LEA.L   0x2C1(A2),A3                    | A3 -> backoff
        MOVE.B  (A3)+,D3                        | D3 = backoff (global mask)
        MOVE.B  (A3),D2                         | D2 = collsnHistory
        ADD.B   D2,(A3)+                        | collsnHistory << 1 (one send older)
        BSR.B   LAP_COUNTBITS                   | collisions in the last 8 sends - 2
        BLE.B   LAPWRITE_DEFERS                 | 2 or fewer -> look at the deferrals
| more than 2 collisions: double the mask
        ADD.B   D3,D3                           | backoff * 2 ...
        ADDQ.B  #0x1,D3                         | ... + 1
        ANDI.W  #0xF,D3                         | at most $F
        CLR.B   -0x1(A3)                        | collsnHistory = 0
        BRA.B   LAPWRITE_INIT                   | ->

| -------------------------------------------------------------------------
| LAP_COUNTBITS: D0 = (number of 1 bits in D2.B) - 2, condition codes set
| (GT = 3 or more).  Uses D1.
| -------------------------------------------------------------------------
LAP_COUNTBITS:
        MOVEQ.L #0x0,D0                         | count = 0
        MOVEQ.L #0x7,D1                         | 8 bits
LAP_COUNTBITS_LOOP:
        BTST    D1,D2                           | bit set?
        BEQ.B   LAP_COUNTBITS_NEXT              | no ->
        ADDQ.W  #0x1,D0                         | count it
LAP_COUNTBITS_NEXT:
        DBF.W   D1,LAP_COUNTBITS_LOOP           | next bit
        SUBQ.B  #0x2,D0                         | - 2
        RTS                                     | return from LAP_COUNTBITS

| -------------------------------------------------------------------------
| LAPWRITE_DEFERS: few collisions - halve the mask when fewer than 2 of
| the last 8 sends were deferred (deferHistory then set to $FF)
| -------------------------------------------------------------------------
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
        MOVEM.L (SCCRd),A0-A1                   | A0/A1 = SCC channel B control (read/write)
| LAPWRITE_START: begin (or resume) the transmission, SR on the stack
LAPWRITE_START:
        MOVE.W  SR,-(SP)                        | save SR
| LAPWRITE_TRY: one attempt; D3 = D0 so that LAPWRITE_BUSY can tell how
| long we waited
LAPWRITE_TRY:
        MOVE.W  D0,D3                           | D3 = D0 (no wait yet)
        BTST    #0x4,(A0)                       | RR0 Sync/Hunt: receiver hunting (no frame on the line)?
        BEQ.B   LAPWRITE_SENSE                  | no, a frame is in progress -> busy
        BSR.W   MPP_RANDOM                      | D0 = random number
        AND.B   0x2C0(A2),D0                    | masked with lbackOff
        ANDI.W  #0xF,D0                         | 0..15
        MOVE.W  D0,D3                           | D3 = random wait in ~100 us steps
        BEQ.B   LAPWRITE_IDG                    | none ->
LAPWRITE_WAIT:
        BSR.B   LAP_WAIT100                     | wait ~100 us; frame on the line?
        BEQ.B   LAPWRITE_SENSE                  | yes -> busy
        SUBQ.W  #0x1,D0                         | count down
        BNE.B   LAPWRITE_WAIT                   | loop
| inter-dialog gap: 4 more steps with interrupts off; the DPLL watches
| for any activity meanwhile
LAPWRITE_IDG:
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        MOVE.B  #0xE,(A1)                       | WR0: select WR14
        MOVEQ.L #0x3,D0                         | 4 steps
        ADDQ.W  #0x3,D3                         | D3 = steps waited when the gap ends
        MOVE.B  #0x41,(A1)                      | WR14 = $41: DPLL reset missing clock, BRG on
LAPWRITE_IDGLOOP:
        BSR.B   LAP_WAIT100                     | wait ~100 us; frame on the line?
        DBEQ.W  D0,LAPWRITE_IDGLOOP             | no -> next step
| line still free?
LAPWRITE_SENSE:
        BEQ.W   LAPWRITE_BUSY                   | frame seen -> busy
        MOVE.B  #0xA,(A1)                       | WR0: select RR10
        MOVE.B  0x2BA(A2),D2                    | D2 = DestNode
        TST.B   (A0)                            | RR10 bit 7: one clock missing?
        BMI.W   LAPWRITE_BUSY                   | yes: activity during the gap (e.g. a sync pulse) -> busy
| line free: sync pulse (RTS on, off), then lapRTS or lapENQ
        MOVE.B  #0x5,(A1)                       | WR0: select WR5
        MOVEQ.L #-0x7C,D0                       | D0 = $84 (lapRTS)
        MOVE.B  #0x62,(A1)                      | WR5 = $62: RTS on (line driver on), Tx off
        TST.B   0x2BE(A2)                       | fSendENQ?
        BEQ.B   LAPWRITE_SENDCTL                | no ->
        MOVEQ.L #-0x7F,D0                       | D0 = $81 (lapENQ)
| end the sync pulse, send the control frame
LAPWRITE_SENDCTL:
        MOVE.B  #0x5,(A1)                       | WR0: select WR5
        NOP                                     | SCC recovery time
        MOVE.B  0x315(A2),(A1)                  | WR5 = VDisTxRTS ($60): RTS off
        BSR.W   LAP_SENDCTL                     | send lapRTS/lapENQ to DestNode
        ADDQ.B  #0x1,D2                         | DestNode = $FF?
        BEQ.B   LAPWRITE_BCAST                  | broadcast: no lapCTS ->
        CLR.B   0x2BC(A2)                       | fGoodCTS = 0: a lapCTS is expected
        BSR.W   LAP_POLLRCV                     | receive the answer, if any
        TST.B   0x2BE(A2)                       | sending ENQs?
        BEQ.B   LAPWRITE_CHKCTS                 | no ->
        TST.B   0x2BD(A2)                       | fAdrInUse (ACK or other frame for the address)?
        BEQ.B   LAPWRITE_COLLISION              | no answer -> send the ENQ again
        BRA.B   LAPWRITE_NOERR                  | answered -> done
| lapCTS received? then send the data frame; fGoodCTS = $FF again
| (unsolicited lapCTS frames are counted as RandomCTS)
LAPWRITE_CHKCTS:
        TST.B   0x2BC(A2)                       | fGoodCTS (lapCTS came)?
        ST.B    0x2BC(A2)                       | fGoodCTS = $FF: no lapCTS expected now
        BEQ.B   LAPWRITE_COLLISION              | no lapCTS: assume a collision
        BRA.B   LAPWRITE_DATA                   | -> data frame

| -------------------------------------------------------------------------
| LAP_WAIT100: wait ~100 us (VWait100 DBF loops), then test RR0
| Sync/Hunt -> EQ if the receiver has left hunt mode (a frame is on the
| line).  The loop is entered through two branches, laid out like the
| loop that measured TimeDBRA (SETUPTIMEK), so the loop count computed
| from TimeDBRA holds.  Uses D1.
| Called by LAPWRITE_WAIT, LAPWRITE_IDGLOOP, LAPWRITE_BCAST.
| -------------------------------------------------------------------------
LAP_WAIT100:
        MOVE.W  0x2D6(A2),D1                    | D1 = VWait100
        BRA.B   LAP_WAIT100_ENTER               | -> into the loop
LAP_WAIT100_LOOP:
        DBF.W   D1,LAP_WAIT100_LOOP             | delay
        BRA.B   LAP_WAIT100_SENSE               | done ->
LAP_WAIT100_ENTER:
        BRA.B   LAP_WAIT100_LOOP                | -> the DBF loop
LAP_WAIT100_SENSE:
        BTST    #0x4,(A0)                       | RR0 Sync/Hunt
        RTS                                     | EQ = frame on the line

| -------------------------------------------------------------------------
| LAPWRITE_BCAST: broadcast - after the lapRTS the line must stay quiet
| for ~100 us (~200 us when VWait100 >= 114, i.e. on a fast CPU)
| -------------------------------------------------------------------------
LAPWRITE_BCAST:
        BSR.B   LAP_WAIT100                     | wait ~100 us; frame on the line?
        BEQ.B   LAPWRITE_COLLISION              | yes -> collision
        CMPI.W  #0x72,0x2D6(A2)                 | VWait100 < 114 loops?
        BCS.B   LAPWRITE_DATA                   | yes -> send
        BSR.B   LAP_WAIT100                     | fast CPU: wait ~100 us more
        BEQ.B   LAPWRITE_COLLISION              | frame on the line -> collision
| send the data frame
LAPWRITE_DATA:
        BSR.W   LAP_SENDFRAME                   | send the frame of WDSPtr
| done
LAPWRITE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        ADDQ.L  #0x1,0x322(A2)                  | XmitCount + 1
| return through LAPWrtRtn
LAPWRITE_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        MOVEA.L 0x2B4(A2),A0                    | A0 = LAPWrtRtn
        JMP     (A0)                            | continue the caller

| -------------------------------------------------------------------------
| LAPWRITE_COLLISION: no lapCTS (or line busy after a broadcast lapRTS):
| record a collision, widen lbackOff, retry up to collsnTries times
| -------------------------------------------------------------------------
LAPWRITE_COLLISION:
        ADDQ.L  #0x1,0x33E(A2)                  | CollsnCount + 1
        MOVE.W  (SP),SR                         | restore SR (it stays on the stack)
        BSET    #0x0,0x2C2(A2)                  | collsnHistory: collision in this send
        MOVE.B  0x2C0(A2),D0                    | lbackOff ...
        ADD.B   D0,D0                           | ... * 2 ...
        ADDQ.B  #0x1,D0                         | ... + 1
        MOVE.B  D0,0x2C0(A2)                    | store it
        MOVEQ.L #-0x5F,D0                       | excessCollsns (-95)
        SUBQ.B  #0x1,0x2C5(A2)                  | collsnTries - 1
        BEQ.B   LAPWRITE_EXIT                   | used up -> excessCollsns
        BRA.W   LAPWRITE_TRY                    | try again

| -------------------------------------------------------------------------
| LAPWRITE_BUSY: the line is busy.  If it went busy after we had waited
| at least 4 steps, count a deferral (deferTries; lbackOff and
| deferHistory bit 0); then wait for the end of the frame on the line.
| -------------------------------------------------------------------------
LAPWRITE_BUSY:
        SUB.W   D0,D3                           | D3 = steps waited
        SUBQ.W  #0x4,D3                         | fewer than 4?
        BLT.B   LAPWRITE_DEFER                  | yes -> just wait
        ADDQ.L  #0x1,0x342(A2)                  | DeferCount + 1
        MOVEQ.L #-0x5F,D0                       | excessCollsns (-95)
        SUBQ.B  #0x1,0x2C4(A2)                  | deferTries - 1
        BEQ.B   LAPWRITE_EXIT                   | used up -> excessCollsns
        BSET    #0x0,0x2C0(A2)                  | lbackOff at least 1
        BSET    #0x0,0x2C3(A2)                  | deferHistory: deferral in this send
| wait: the abort at the end of the frame raises an external/status
| interrupt (LAP_EXTINT); MPP_VBLTASK resumes after 20-40 ticks anyway
LAPWRITE_DEFER:
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        MOVE.B  #0xF,(A1)                       | WR0: select WR15
        MOVEQ.L #-0x78,D0                       | $88
        MOVE.B  D0,(A1)                         | WR15 = $88: break/abort and DCD interrupts
        ADDQ.B  #0x2,0x2BF(A2)                  | VBLDeferCnt + 2
        MOVEQ.L #0x0,D0                         | noErr
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return to the caller's caller (write pending)

| -------------------------------------------------------------------------
| LAP_EXTINT: SCC channel B external/status interrupt (ExtStsDT[0]:
| changes other than DCD alone; D1 = changed enabled RR0 bits).  Resumes
| a deferred LAPWRITE; otherwise passes a DCD change to the mouse handler.
| -------------------------------------------------------------------------
LAP_EXTINT:
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        TST.B   0x2BF(A2)                       | write waiting (VBLDeferCnt)?
        BNE.B   LAP_EXTINT_RESUME               | yes -> resume it
        BTST    #0x3,D1                         | DCD (mouse Y) changed too?
        BEQ.B   LAP_RTS                         | no -> ignore
        MOVEA.L (ExtStsDT_1).W,A3               | A3 = DCD handler (ExtStsDT[1], mouse Y)
        JMP     (A3)                            | -> the mouse handler
| LAP_EXTINT_RESUME / LAP_RESUMEWRITE: resume a deferred LAPWRITE
LAP_EXTINT_RESUME:
        CLR.B   0x2BF(A2)                       | VBLDeferCnt = 0
LAP_RESUMEWRITE:
        MOVE.B  #0xF,(A1)                       | WR0: select WR15
        MOVEQ.L #0x8,D0                         | $08
        MOVE.B  D0,(A1)                         | WR15 = $08: DCD (mouse) interrupt only
        MOVE.W  0x1C(A2),SR                     | SR = vSCCEnable
        BRA.W   LAPWRITE_START                  | next attempt

| -------------------------------------------------------------------------
| MPP_VBLTASK: VBL task, every 20 ticks (A0 = task).  Ages BridgeTime
| (sysABridge forgotten after 255 periods without RTMP) and resumes a
| deferred LAPWRITE when VBLDeferCnt runs out (counted as IdleTOCount).
| Bug (System patch P019, lap.a; the same in the Mac Plus driver): the
| test and the decrement of VBLDeferCnt run at VBL interrupt level, so
| LAP_EXTINT (SCC level) can clear it in between and the SUBQ makes it
| $FF; the patch has _VInstall substitute a wrapper that calls this task
| with interrupts off (IPL 6).
| -------------------------------------------------------------------------
MPP_VBLTASK:
        MOVE.W  #0x14,vblCount(A0)              | vblCount = 20 ticks
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        SUBQ.B  #0x1,0x2C6(A2)                  | BridgeTime - 1
        BNE.B   MPP_VBLTASK_DEFER               | not expired ->
        CLR.B   0x19(A2)                        | sysABridge = 0 (no bridge)
| deferred write waiting?
MPP_VBLTASK_DEFER:
        TST.B   0x2BF(A2)                       | VBLDeferCnt
        BEQ.B   LAP_RTS                         | no write waiting -> return
        SUBQ.B  #0x1,0x2BF(A2)                  | count down
        BNE.B   LAP_RTS                         | not yet -> return
        MOVEM.L (SCCRd),A0-A1                   | A0/A1 = SCC channel B control
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        BSR.W   LAP_RCVRESET                    | receiver back to hunt mode
        ADDQ.L  #0x1,0x346(A2)                  | IdleTOCount + 1
        BRA.B   LAP_RESUMEWRITE                 | resume the write

| -------------------------------------------------------------------------
| LAP_POLLRCV: poll VGetXXX times for a received byte (the answer to a
| lapRTS/lapENQ) and receive the frame through LAP_RCVFRAME.  Preserves
| A0-A2.  Called by LAPWRITE_SENDCTL.
| -------------------------------------------------------------------------
LAP_POLLRCV:
        MOVEM.L A0-A2,-(SP)                     | save A0-A2
        MOVE.W  0x2D0(A2),D1                    | D1 = VGetXXX polls
LAP_POLLRCV_LOOP:
        BTST    #0x0,(A0)                       | RR0: Rx character available?
        DBNE.W  D1,LAP_POLLRCV_LOOP             | no -> poll again
        BEQ.B   LAP_POLLRCV_EXIT                | nothing came ->
        BSR.W   LAP_RCVFRAME                    | receive the frame
LAP_POLLRCV_EXIT:
        MOVEM.L (SP)+,A0-A2                     | restore A0-A2
LAP_RTS:
        RTS                                     | return

| -------------------------------------------------------------------------
| MPP_RANDOM: RandomSeed = byte-swapped (RandomSeed * 773 + 1); returns
| it in D0.  Called by LAPWRITE_TRY and E_MPP_Open.
| -------------------------------------------------------------------------
MPP_RANDOM:
        MOVE.W  0x2B8(A2),D0                    | D0 = RandomSeed
        MULU.W  #0x305,D0                       | * 773
        ADDQ.W  #0x1,D0                         | + 1
        MOVE.W  D0,-(SP)                        | push it
        LSL.W   #0x8,D0                         | low byte to the high byte
        MOVE.B  (SP)+,D0                        | old high byte to the low byte
        MOVE.W  D0,0x2B8(A2)                    | new RandomSeed
        RTS                                     | return from MPP_RANDOM

| LAP_TXON_TBL: SCC writes for LAP_TXON - WR5 = $6B (Tx on, RTS on, 8
| bits, Tx CRC on), WR3 = $D0 (receiver off, enter hunt mode)
LAP_TXON_TBL:
        .byte   0x05,0x6B,0x03,0xD0             | WR0 = 5, WR5 = $6B, WR0 = 3, WR3 = $D0

| -------------------------------------------------------------------------
| LAP_SENDBYTE: wait (VSTimeout polls) for the Tx buffer, then write D3
| to the channel B data register.  Returns TST D1: MI (D1 = -1) on a
| timeout without writing (the callers test BMI).
| -------------------------------------------------------------------------
LAP_SENDBYTE:
        MOVE.W  0x2CC(A2),D1                    | D1 = VSTimeout polls
LAP_SENDBYTE_LOOP:
        BTST    #0x2,(A0)                       | RR0: Tx buffer empty?
        DBNE.W  D1,LAP_SENDBYTE_LOOP            | no -> poll again
        BEQ.B   LAP_SENDBYTE_EXIT               | timeout -> no write
        MOVE.B  D3,0x4(A1)                      | write the byte
LAP_SENDBYTE_EXIT:
        TST.W   D1                              | MI = timeout
        RTS                                     | return from LAP_SENDBYTE

| -------------------------------------------------------------------------
| LAP_TXON: turn the transmitter on (LAP_TXON_TBL), let it send flags for
| VXmitOn loops, then reset the Tx CRC generator
| -------------------------------------------------------------------------
LAP_TXON:
        LEA.L   LAP_TXON_TBL(PC),A3             | A3 = SCC writes
        MOVEQ.L #0x4,D3                         | 4 bytes
        BSR.W   LAP_SCCWRITE                    | write them
        MOVE.W  0x2D2(A2),D3                    | D3 = VXmitOn
LAP_TXON_DELAY:
        DBF.W   D3,LAP_TXON_DELAY               | opening flags go out meanwhile
        MOVE.B  #0x80,(A1)                      | WR0 = $80: reset Tx CRC generator
        RTS                                     | return from LAP_TXON

| -------------------------------------------------------------------------
| LAP_SENDFRAME: send the frame of the WDS at WDSPtr (lapSrcAdr filled in
| with our node), then CRC, closing flag and abort (LAP_ENDFRAME).
| Interrupts are off: received modem-port bytes (VIA PA7 low) are pushed
| on the stack and handed to PollProc afterwards.
| Called by LAPWRITE_DATA.
| -------------------------------------------------------------------------
LAP_SENDFRAME:
        MOVEM.L A0-A1/A4-A6,0x2FC(A2)           | save registers (SaveRegs)
        MOVE.L  (DskRtnAdr).W,-(SP)             | save DskRtnAdr
        MOVE.L  (PollStack).W,-(SP)             | save PollStack
        MOVE.L  SP,(PollStack).W                | PollStack = start of the polled bytes
        MOVEA.L 0x310(A2),A5                    | A5 = VIA vBufA (PA7 = SCC W/REQ)
        LEA.L   0x6(A0),A6                      | A6 = SCC channel A data (read)
        MOVEA.L 0x2B0(A2),A4                    | A4 = WDS (WDSPtr)
        BSR.B   LAP_TXON                        | transmitter on
        MOVE.W  (A4)+,D3                        | D3 = length of the first entry
        MOVEA.L (A4)+,A3                        | A3 = its data (frame header)
        MOVE.B  (A3)+,0x4(A1)                   | send lapDstAdr
        SUBQ.W  #0x1,D3                         | one byte less
        MOVE.B  (A2),(A3)                       | lapSrcAdr = sysLAPAddr
| byte loop
LAP_SENDFRAME_LOOP:
        MOVE.W  0x2CC(A2),D0                    | D0 = VSTimeout polls
LAP_SENDFRAME_WAIT:
        BTST    #0x2,(A0)                       | RR0: Tx buffer empty?
        DBNE.W  D0,LAP_SENDFRAME_WAIT           | no -> poll again
        BNE.B   LAP_SENDFRAME_BYTE              | yes ->
        BSR.W   LAP_TXOFF                       | timeout: transmitter off
        BRA.B   LAP_SENDFRAME_POLL              | -> finish
| send the next byte; save a modem-port byte, if one arrived
LAP_SENDFRAME_BYTE:
        MOVE.B  (A3)+,0x4(A1)                   | next byte to the Tx buffer
        TST.B   (A5)                            | VIA PA7 low (channel A byte waiting)?
        BMI.B   LAP_SENDFRAME_COUNT             | no ->
        MOVE.B  (A6),-(SP)                      | yes: push it for PollProc
LAP_SENDFRAME_COUNT:
        SUBQ.W  #0x1,D3                         | count
        BGT.B   LAP_SENDFRAME_LOOP              | more in this entry ->
        MOVE.W  (A4)+,D3                        | D3 = length of the next entry
        BEQ.B   LAP_SENDFRAME_END               | 0 = end of WDS ->
        MOVEA.L (A4)+,A3                        | A3 = its data
        BRA.B   LAP_SENDFRAME_LOOP              | send it
| all bytes sent: end the frame
LAP_SENDFRAME_END:
        BSR.B   LAP_ENDFRAME                    | CRC, flag, abort, transmitter off
| let PollProc process the saved modem-port bytes
LAP_SENDFRAME_POLL:
        MOVE.L  (PollProc).W,D3                 | PollProc installed?
        BEQ.B   LAP_SENDFRAME_EXIT              | no ->
        MOVEA.L D3,A4                           | A4 = PollProc
        JSR     (A4)                            | call PollProc (the disk driver's poll routine)
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables again
LAP_SENDFRAME_EXIT:
        MOVEM.L 0x2FC(A2),A0-A1/A4-A6           | restore registers
        MOVEA.L (PollStack).W,SP                | drop the polled bytes
        MOVE.L  (SP)+,(PollStack).W             | restore PollStack
        MOVE.L  (SP)+,(DskRtnAdr).W             | restore DskRtnAdr
        RTS                                     | return from LAP_SENDFRAME

| -------------------------------------------------------------------------
| LAP_SENDCTL: send a LAP control frame: lapDstAdr = D2, lapSrcAdr =
| sysLAPAddr, lapType = D0.B ($81 lapENQ, $82 lapACK, $84 lapRTS,
| $85 lapCTS); falls into LAP_ENDFRAME (LAP_TXOFF on a send timeout)
| Called by LAPWRITE_SENDCTL, LAP_REPLYCTL.
| -------------------------------------------------------------------------
LAP_SENDCTL:
        BSR.W   LAP_TXON                        | transmitter on
        MOVE.B  D2,0x4(A1)                      | send lapDstAdr
        MOVE.B  (A2),D3                         | D3 = sysLAPAddr
        BSR.W   LAP_SENDBYTE                    | send lapSrcAdr
        BMI.B   LAP_TXOFF                       | timeout -> transmitter off
        MOVE.B  D0,D3                           | D3 = lapType
        BSR.W   LAP_SENDBYTE                    | send it
        BMI.B   LAP_TXOFF                       | timeout -> transmitter off
| LAP_ENDFRAME: let the SCC append CRC and closing flag at the underrun,
| then hold the line marking (abort sequence) and turn the transmitter off
LAP_ENDFRAME:
        MOVE.B  #0xC0,(A1)                      | WR0 = $C0: reset Tx underrun/EOM latch
        LSL.W   #0x1,D3                         | delay
LAP_ENDFRAME_EOM:
        BTST    #0x6,(A0)                       | RR0: Tx underrun/EOM (CRC being sent)?
        BEQ.B   LAP_ENDFRAME_EOM                | no -> wait
LAP_ENDFRAME_TBE:
        BTST    #0x2,(A0)                       | RR0: Tx buffer empty?
        BEQ.B   LAP_ENDFRAME_TBE                | no -> wait
        MOVE.B  #0x5,(A1)                       | WR0: select WR5
        MOVEQ.L #0x0,D3                         | D3.W = 0
        MOVE.B  #0x62,(A1)                      | WR5 = $62: Tx off, RTS on: line marks (abort)
        MOVE.W  0x2C8(A2),D3                    | D3 = VAbortWait
LAP_ENDFRAME_ABORT:
        DBF.W   D3,LAP_ENDFRAME_ABORT           | wait
| LAP_TXOFF: write VSTData - WR5 = $60 (RTS off), WR14 = $41 (DPLL reset
| missing clock, BRG on), WR3 = $DD (receiver on, hunt mode)
LAP_TXOFF:
        LEA.L   0x314(A2),A3                    | A3 = VSTData
        MOVEQ.L #0x6,D3                         | 6 bytes
| LAP_SCCWRITE: write D3 bytes from (A3) to the channel B control register
LAP_SCCWRITE:
        MOVE.B  (A3)+,(A1)                      | next byte
        SUBQ.W  #0x1,D3                         | count
        BNE.B   LAP_SCCWRITE                    | loop
        RTS                                     | return from LAP_SCCWRITE

| -------------------------------------------------------------------------
| LAP_RCVINT: SCC channel B receive interrupt (Lvl2DT[2]); A0/A1 = SCC
| channel B control.  LAP_RCVFRAME (also from LAP_POLLRCV and after our
| lapCTS): read lapDstAdr, lapSrcAdr, lapType into the RHA (2 * VRTimeout
| polls per byte); control frames -> LAP_RCVCTL; data frames: read the
| length word and jump to the protocol handler (A4 = LAP_READ_JT, D1 =
| bytes left, A3 -> RHA, A4/A5 saved in SaveA45).
| -------------------------------------------------------------------------
LAP_RCVINT:
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        ADDQ.L  #0x1,0x31A(A2)                  | IntCount + 1
LAP_RCVFRAME:
        LEA.L   0x1(A2),A3                      | A3 = RHA (toRHA)
        MOVE.B  0x4(A0),(A3)+                   | lapDstAdr
        MOVE.W  0x2CA(A2),D1                    | D1 = VRTimeout ...
        ADD.W   D1,D1                           | ... * 2: poll budget for the header
LAP_RCVFRAME_SRC:
        BTST    #0x0,(A0)                       | RR0: Rx character available?
        DBNE.W  D1,LAP_RCVFRAME_SRC             | no -> poll again
        BEQ.B   LAP_RCVFRAME_TIMEOUT            | timeout ->
        MOVE.B  0x4(A0),(A3)+                   | lapSrcAdr
LAP_RCVFRAME_TYPE:
        BTST    #0x0,(A0)                       | Rx character available?
        DBNE.W  D1,LAP_RCVFRAME_TYPE            | no -> poll again
        BEQ.B   LAP_RCVFRAME_TIMEOUT            | timeout ->
        MOVE.B  0x4(A0),D0                      | D0 = lapType
        MOVE.B  D0,(A3)+                        | into the RHA
        BMI.B   LAP_RCVCTL                      | $80-$FF: control frame ->
| find the protocol handler of the type
        MOVEQ.L #0x7,D2                         | 8 entries
LAP_RCVFRAME_FINDPH:
        CMP.B   0x24(A2,D2.W),D0                | this type?
        DBEQ.W  D2,LAP_RCVFRAME_FINDPH          | no -> next
        LSL.W   #0x2,D2                         | long index (negative: none)
| length word (10 bits, includes itself)
        MOVE.W  0x2CA(A2),D0                    | D0 = VRTimeout ...
        ADD.W   D0,D0                           | ... * 2: poll budget
LAP_RCVFRAME_LEN1:
        BTST    #0x0,(A0)                       | Rx character available?
        DBNE.W  D0,LAP_RCVFRAME_LEN1            | no -> poll again
        BEQ.B   LAP_RCVFRAME_TIMEOUT            | timeout ->
        MOVE.B  0x4(A0),(A3)                    | length high byte
        MOVEQ.L #0x3,D1                         | 2 bits
        AND.B   (A3)+,D1                        | D1 = length bits 9-8
        LSL.W   #0x8,D1                         | to bits 9-8
        MOVEM.L A4-A5,0x2D8(A2)                 | save A4/A5 (SaveA45)
LAP_RCVFRAME_LEN2:
        BTST    #0x0,(A0)                       | Rx character available?
        DBNE.W  D0,LAP_RCVFRAME_LEN2            | no -> poll again
LAP_RCVFRAME_TIMEOUT:
        BEQ.W   LAP_RCVTIMEOUT                  | timeout -> count, discard the frame
        MOVE.B  0x4(A0),D1                      | length bits 7-0
        MOVE.B  D1,(A3)+                        | into the RHA
        SUBQ.W  #0x2,D1                         | D1 = bytes left after the length word
        TST.W   D2                              | protocol handler found?
        BMI.B   LAP_RCVFRAME_NOPH               | no ->
        MOVEA.L 0x2C(A2,D2.W),A5                | A5 = protocol handler
        LEA.L   LAP_READ_JT(PC),A4              | A4 = ReadPacket/ReadRest jump table
        JMP     (A5)                            | -> protocol handler

| -------------------------------------------------------------------------
| LAP_RCVFRAME_NOPH: no handler for the type - read and drop the rest
| (ReadRest with no buffer, counted as NoHandCnt), unless the frame has
| already ended
| -------------------------------------------------------------------------
LAP_RCVFRAME_NOPH:
        MOVE.B  #0x1,(A1)                       | WR0: select RR1
        MOVEQ.L #-0x60,D0                       | $A0
        AND.B   (A0),D0                         | RR1: end of frame or Rx overrun?
        BNE.W   LAP_RCVERR                      | yes -> error, reset the receiver
        ADDQ.L  #0x1,0x332(A2)                  | NoHandCnt + 1
        CLR.W   D3                              | buffer size 0
        BRA.W   READREST                        | read and drop the rest

| -------------------------------------------------------------------------
| LAP_RCVCTL: control frame (lapType in D0).  Reads the CRC.  While our
| address is not yet valid, a frame sent to it (not broadcast) means the
| address is taken (fAdrInUse).  Else: lapENQ -> answer lapACK; lapRTS ->
| answer lapCTS (not to a broadcast), then receive the data frame;
| others: fGoodCTS = (frame is lapCTS), counted as RandomCTS when no
| lapCTS was expected.  Types above $85 -> BadCount.
| -------------------------------------------------------------------------
LAP_RCVCTL:
        MOVEQ.L #0x7F,D2                        | mask
        AND.B   D0,D2                           | D2 = lapType - $80
        CMPI.B  #0x5,D2                         | above $85?
        BGT.B   LAP_RCVBADCTL                   | yes -> count, discard
        BSR.B   LAP_RCVCRC                      | read the CRC, check the frame
        BNE.B   LAP_RCVCTL_EXIT                 | bad -> return
        CMPI.B  #0xFF,0x1(A2)                   | lapDstAdr = $FF (broadcast)?
        SEQ.B   D1                              | D1 = $FF if broadcast
        BEQ.B   LAP_RCVCTL_TYPE                 | broadcast -> process
        TST.B   0x2BB(A2)                       | fLAPAdrValid?
        BNE.B   LAP_RCVCTL_TYPE                 | yes -> process
        ST.B    0x2BD(A2)                       | no: fAdrInUse
LAP_RCVCTL_EXIT:
        RTS                                     | return
| dispatch on the control frame type
LAP_RCVCTL_TYPE:
        SUBQ.B  #0x1,D2                         | $81 lapENQ?
        BEQ.B   LAP_RCVCTL_ENQ                  | yes -> answer lapACK
        SUBQ.B  #0x3,D2                         | $84 lapRTS?
        BEQ.B   LAP_RCVCTL_RTS                  | yes -> answer lapCTS
        TST.B   0x2BC(A2)                       | fGoodCTS = 0: lapCTS expected?
        BEQ.B   LAP_RCVCTL_CTS                  | yes ->
        ADDQ.L  #0x1,0x352(A2)                  | no: RandomCTS + 1
LAP_RCVCTL_CTS:
        SUBQ.B  #0x1,D2                         | $85 lapCTS?
        SEQ.B   0x2BC(A2)                       | fGoodCTS = (lapCTS)
        RTS                                     | return
| lapRTS: answer lapCTS unless it was broadcast, then receive the data
| frame that follows (NoDtaCount if none comes within VDataTO polls)
LAP_RCVCTL_RTS:
        TST.B   D1                              | broadcast?
        BNE.B   LAP_RCVCTL_DATA                 | yes: no lapCTS ->
        MOVE.W  0x2D4(A2),D0                    | D0 = VRTStoCTS
LAP_RCVCTL_DELAY:
        DBF.W   D0,LAP_RCVCTL_DELAY             | short delay
        MOVEQ.L #-0x7B,D0                       | D0 = $85 (lapCTS)
        BSR.B   LAP_REPLYCTL                    | send it to the sender
LAP_RCVCTL_DATA:
        MOVE.W  0x2CE(A2),D1                    | D1 = VDataTO polls
LAP_RCVCTL_WAITDATA:
        BTST    #0x0,(A0)                       | RR0: Rx character available?
        DBNE.W  D1,LAP_RCVCTL_WAITDATA          | no -> poll again
        BNE.W   LAP_RCVFRAME                    | yes -> receive the data frame
        ADDQ.L  #0x1,0x34E(A2)                  | NoDtaCount + 1
        RTS                                     | return
| lapENQ for our address: answer lapACK
LAP_RCVCTL_ENQ:
        MOVEQ.L #-0x7E,D0                       | D0 = $82 (lapACK)
| LAP_REPLYCTL: send control frame D0 to the sender (lapSrcAdr in the RHA)
LAP_REPLYCTL:
        MOVE.B  0x2(A2),D2                      | D2 = lapSrcAdr of the received frame
        BRA.W   LAP_SENDCTL                     | send it
| (unreachable: count NoHandCnt and reset the receiver)
        ADDQ.L  #0x1,0x332(A2)                  | NoHandCnt + 1
        BRA.B   LAP_SPECIALINT                  | -> reset the receiver
| control frame type above $85: count, reset the receiver
LAP_RCVBADCTL:
        ADDQ.L  #0x1,0x33A(A2)                  | BadCount + 1
        BRA.B   LAP_SPECIALINT                  | -> reset the receiver
| header byte timeout in LAP_RCVFRAME: count (underrun)
LAP_RCVTIMEOUT:
        ADDQ.L  #0x1,0x32E(A2)                  | UNDCount + 1
| LAP_SPECIALINT: SCC channel B special receive condition (Lvl2DT[3]),
| also used to drop a frame: reset the receiver (twice)
LAP_SPECIALINT:
        BSR.B   LAP_RCVRESET                    | reset the receiver
        BRA.B   LAP_RCVRESET                    | and once more

| -------------------------------------------------------------------------
| LAP_RCVCRC: read the two CRC bytes that end the frame (VRTimeout polls
| each): the first must not, the second must have end of frame, without
| CRC error; then reset the receiver.  D0 = 0 or overrunErr (-1), crcErr
| (-2), underrunErr (-3, timeout), lengthErr (-4), each also counted;
| condition codes from D0.  Called by LAP_RCVCTL, READREST_END.
| -------------------------------------------------------------------------
LAP_RCVCRC:
        CLR.W   D0                              | D0 = noErr
        MOVE.W  0x2CA(A2),D1                    | D1 = VRTimeout polls
LAP_RCVCRC_WAIT1:
        BTST    #0x0,(A0)                       | RR0: Rx character available?
        DBNE.W  D1,LAP_RCVCRC_WAIT1             | no -> poll again
        BEQ.B   LAP_UNDERRUN                    | timeout -> underrunErr
        BSR.B   LAP_GETRR1                      | D1 = RR1
        BMI.B   LAP_LENERR                      | end of frame already: frame short -> lengthErr
        TST.B   0x4(A0)                         | read (drop) the first CRC byte
        MOVE.W  0x2CA(A2),D1                    | D1 = VRTimeout polls
LAP_RCVCRC_WAIT2:
        BTST    #0x0,(A0)                       | Rx character available?
        DBNE.W  D1,LAP_RCVCRC_WAIT2             | no -> poll again
        BEQ.B   LAP_UNDERRUN                    | timeout -> underrunErr
        BSR.B   LAP_GETRR1                      | D1 = RR1
        BPL.B   LAP_LENERR                      | no end of frame: frame long -> lengthErr
        LSL.B   #0x1,D1                         | RR1 bit 6 (CRC error) -> N
        BMI.B   LAP_CRCERR                      | CRC error -> crcErr
| LAP_RCVRESET: re-arm the receiver for the next frame: receiver off and
| hunt, drain the 3-byte FIFO, receiver on (hunt, address search), error
| reset, interrupt on the next character.  Condition codes from D0.
| Called by: LAP_SPECIALINT, MPP_VBLTASK, READPACKET_ERR, LAP_LENERR,
| LAP_UNDERRUN, LAP_CRCERR, LAP_OVERRUN
LAP_RCVRESET:
        BSR.B   LAP_GETRR1                      | D1 = RR1
        BTST    #0x5,D1                         | Rx overrun?
        BEQ.B   LAP_RCVRESET_HUNT               | no ->
        BCLR    #0x7,(IntFlag)                  | IntFlag bit 7 = 0: ask for shorter interrupts-off periods
LAP_RCVRESET_HUNT:
        MOVEQ.L #-0x30,D1                       | $D0
        BSR.B   LAP_SETWR3                      | WR3 = $D0: receiver off, enter hunt mode
        MOVEQ.L #0x2,D1                         | 3 bytes
LAP_RCVRESET_DRAIN:
        TST.B   0x4(A0)                         | read (drop) a FIFO byte
        DBF.W   D1,LAP_RCVRESET_DRAIN           | loop
        MOVEQ.L #-0x23,D1                       | $DD
        BSR.B   LAP_SETWR3                      | WR3 = $DD: Rx on, 8 bits, hunt, CRC, address search
        MOVE.B  #0x30,(A1)                      | WR0 = $30: error reset
        MOVE.W  (SP),(SP)                       | delay (SCC recovery time)
        MOVE.B  #0x20,(A1)                      | WR0 = $20: enable interrupt on next Rx character
        TST.W   D0                              | condition codes = result
        RTS                                     | return

| -------------------------------------------------------------------------
| LAP_SETWR3: WR3 = D1
| -------------------------------------------------------------------------
LAP_SETWR3:
        MOVE.B  #0x3,(A1)                       | WR0: select WR3
        NOP                                     | SCC recovery time
        MOVE.B  D1,(A1)                         | WR3 = D1
        RTS                                     | return from LAP_SETWR3

| -------------------------------------------------------------------------
| LAP_GETRR1: D1 = RR1 (bit 7 end of frame, 6 CRC error, 5 Rx overrun)
| -------------------------------------------------------------------------
LAP_GETRR1:
        MOVE.B  #0x1,(A1)                       | WR0: select RR1
        NOP                                     | SCC recovery time
        MOVE.B  (A0),D1                         | D1 = RR1
        RTS                                     | return from LAP_GETRR1

| -------------------------------------------------------------------------
| receive errors: count the error, D0 = its code, reset the receiver.
| LAP_RCVERR: from LAP_RCVFRAME_NOPH with D0 = RR1 bits 7/5.
| -------------------------------------------------------------------------
LAP_RCVERR:
        MOVE.B  D0,D1                           | D1 = RR1 bits
        MOVEQ.L #0x0,D0                         | D0.L = 0
LAP_LENERR:
        BTST    #0x5,D1                         | Rx overrun?
        BNE.B   LAP_OVERRUN                     | yes -> overrunErr
        ADDQ.L  #0x1,0x336(A2)                  | LenErrCnt + 1
        MOVEQ.L #-0x4,D0                        | lengthErr (-4)
        BRA.B   LAP_RCVRESET                    | reset the receiver
LAP_UNDERRUN:
        ADDQ.L  #0x1,0x32E(A2)                  | UNDCount + 1
        MOVEQ.L #-0x3,D0                        | underrunErr (-3)
        BRA.B   LAP_RCVRESET                    | reset the receiver
LAP_CRCERR:
        ADDQ.L  #0x1,0x326(A2)                  | CRCCount + 1
        MOVEQ.L #-0x2,D0                        | crcErr (-2)
        BRA.B   LAP_RCVRESET                    | reset the receiver
LAP_OVERRUN:
        ADDQ.L  #0x1,0x32A(A2)                  | OVRCount + 1
        MOVEQ.L #-0x1,D0                        | overrunErr (-1)
        BRA.B   LAP_RCVRESET                    | reset the receiver

| -------------------------------------------------------------------------
| LAP_READ_JT: A4 for protocol handlers and socket listeners - JSR (A4) =
| ReadPacket (through READPACKET_JMP, out of BRA.B range), JSR 2(A4) =
| ReadRest
| -------------------------------------------------------------------------
READPACKET_JMP:
        BRA.W   READPACKET                      | -> READPACKET
LAP_READ_JT:
        BRA.B   READPACKET_JMP                  | (A4): ReadPacket; 2(A4) = READREST below

| -------------------------------------------------------------------------
| READREST: read the rest of the packet (D1 bytes left) into the buffer
| at A3, D3 bytes long (excess bytes are dropped), then check the CRC
| (LAP_RCVCRC).  D3 = 0 if it fit exactly, > 0 if bytes were left
| unfilled, < 0 if (-D3) bytes did not fit.  Saves modem-port bytes for
| PollProc.  Restores A4/A5; counts a good frame (RcvCount); condition
| codes / D0 = result.  Also used by LAP_RCVFRAME_NOPH.
| -------------------------------------------------------------------------
READREST:
        MOVEA.L 0x310(A2),A5                    | A5 = VIA vBufA (PA7 = SCC W/REQ)
        MOVEA.L SP,A4                           | A4 = start of the polled bytes
| byte loop
READREST_LOOP:
        MOVE.W  0x2CA(A2),D0                    | D0 = VRTimeout polls
        SUBQ.W  #0x1,D1                         | one byte less to go
        BMI.B   READREST_END                    | all read ->
READREST_WAIT:
        BTST    #0x0,(A0)                       | RR0: Rx character available?
        DBNE.W  D0,READREST_WAIT                | no -> poll again
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
| end of packet: CRC, then let PollProc have the saved modem-port bytes
READREST_END:
        BSR.W   LAP_RCVCRC                      | CRC, end of frame; D0 = result
        MOVE.L  (PollStack).W,0x2E4(A2)         | save PollStack (SavePS)
        MOVE.L  A4,(PollStack).W                | PollStack = start of the polled bytes
        MOVE.L  (PollProc).W,D1                 | PollProc installed?
        BEQ.B   READREST_NOPOLL                 | no ->
        MOVEM.L D0/D2-D3/A3/A6,0x2FC(A2)        | save registers (SaveRegs)
        LEA.L   0x6(A0),A6                      | A6 = SCC channel A data (read)
        MOVEA.L D1,A0                           | A0 = PollProc
        MOVE.L  (DskRtnAdr).W,0x2E0(A2)         | save DskRtnAdr (SaveDskRtn)
        JSR     (A0)                            | call PollProc (the disk driver's poll routine)
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables again
        MOVE.L  0x2E0(A2),(DskRtnAdr).W         | restore DskRtnAdr
        MOVEM.L 0x2FC(A2),D0/D2-D3/A3/A6        | restore registers
READREST_NOPOLL:
        MOVEA.L (PollStack).W,SP                | drop the polled bytes
        MOVE.L  0x2E4(A2),(PollStack).W         | restore PollStack
| READ_EXIT: restore A4/A5 (SaveA45), count a good frame, condition codes
| from D0
READ_EXIT:
        MOVEM.L 0x2D8(A2),A4-A5                 | restore A4/A5
        TST.W   D0                              | error?
        BNE.B   READ_EXIT_RESULT                | yes ->
        ADDQ.L  #0x1,0x31E(A2)                  | RcvCount + 1
READ_EXIT_RESULT:
        TST.W   D0                              | condition codes = result
READPACKET_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| READPACKET: read D3 bytes of the packet into (A3)+; D1 -= D3.  D0/
| condition codes = 0 if all were read; on overrunErr (-1), underrunErr
| (-3, timeout) or lengthErr (-4, frame ended early) the error is
| counted, the receiver reset and A4/A5 restored (the caller must just
| return).
| -------------------------------------------------------------------------
READPACKET:
        SUB.W   D3,D1                           | bytes left after this read
READPACKET_LOOP:
        MOVE.W  0x2CA(A2),D0                    | D0 = VRTimeout polls
READPACKET_WAIT:
        BTST    #0x0,(A0)                       | RR0: Rx character available?
        DBNE.W  D0,READPACKET_WAIT              | no -> poll again
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
        ADDQ.L  #0x1,0x32A(A2)                  | OVRCount + 1
        MOVEQ.L #-0x1,D0                        | overrunErr (-1)
        BRA.B   READPACKET_ERR                  | ->
| no byte came - underrunErr
READPACKET_TIMEOUT:
        ADDQ.L  #0x1,0x32E(A2)                  | UNDCount + 1
        MOVEQ.L #-0x3,D0                        | underrunErr (-3)
        BRA.B   READPACKET_ERR                  | ->
| frame shorter than its length word - lengthErr
READPACKET_LENERR:
        ADDQ.L  #0x1,0x336(A2)                  | LenErrCnt + 1
        MOVEQ.L #-0x4,D0                        | lengthErr (-4)
READPACKET_ERR:
        BSR.W   LAP_RCVRESET                    | reset the receiver
        BRA.B   READ_EXIT                       | restore A4/A5, return NE

| -------------------------------------------------------------------------
| E_MPP_Close: closes .ATP (atpVars flag set first), stops the NBP retry
| timers (NBP code entry with D3 = 0: NBP_CLOSE), resets SCC channel B
| (mouse interrupt kept), removes the VBL task and the interrupt
| handlers, gives units 7/8 (.BIn/.BOut) back and frees the EP buffer,
| the NBP variables, the lookup-reply block and the MPP variables.
| -------------------------------------------------------------------------
E_MPP_Close:
        MOVEA.L (UTableBase).W,A4               | A4 = unit table
        ADDA.W  #0x28,A4                        | A4 -> unit 10 (.ATP) entry
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        MOVE.L  A2,D0                           | .MPP open?
        BEQ.B   E_MPP_CLOSE_PORT                | no -> only release the port
| close .ATP
        ST.B    0x1E(A2)                        | atpVars flag byte: .ATP must not call .MPP
        SUBA.W  #0x32,SP                        | parameter block on the stack
        MOVEA.L SP,A0                           | A0 = it
        MOVE.W  #-0xB,ioRefNum(A0)              | ioRefNum = -11 (.ATP)
        _Close                                  | close .ATP
        ADDA.W  #0x32,SP                        | drop the parameter block
| stop the NBP requests
        MOVEQ.L #0x0,D3                         | D3 = 0 (< 7): NBP_CLOSE
        MOVEA.L 0x296(A2),A0                    | A0 = NRPtr (NBP_DISPATCH)
        JSR     (A0)                            | NBP_DISPATCH -> NBP_CLOSE: remove the retry timers
| SCC, VBL task, interrupt handlers
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        LEA.L   MPP_SCCRESET_TBL(PC),A0         | A0 = SCC table
        BSR.B   MPP_SCCINIT                     | reset channel B
        LEA.L   0x288(A2),A0                    | A0 = VBL task (+$288)
        _VRemove                                | remove it
        LEA.L   0x2F0(A2),A0                    | A0 = SaveVects
        LEA.L   (Lvl2DT_2).W,A3                 | A3 = Lvl2DT[2]
        MOVE.L  (A0)+,(A3)+                     | Lvl2DT[2]: channel B Rx character
        MOVE.L  (A0)+,(A3)+                     | Lvl2DT[3]: channel B special receive
        MOVE.L  (A0)+,(ExtStsDT).W              | ExtStsDT[0]: channel B external/status
| give units 8 (.BOut) and 7 (.BIn) back
        MOVEA.L -(A4),A0                        | A4 -> unit 9 (.MPP) entry (A0 not used)
        MOVE.L  0x2EC(A2),D0                    | SaveBOut
        BEQ.B   E_MPP_CLOSE_BIN                 | none ->
        MOVE.L  D0,-0x4(A4)                     | unit 8 = .BOut DCE handle
E_MPP_CLOSE_BIN:
        MOVE.L  0x2E8(A2),D0                    | SaveBIn
        BEQ.B   E_MPP_CLOSE_FREE                | none ->
        MOVE.L  D0,-0x8(A4)                     | unit 7 = .BIn DCE handle
| free the blocks
E_MPP_CLOSE_FREE:
        MOVE.W  (SP)+,SR                        | restore SR
        MOVEA.L 0x88(A2),A0                     | A0 = EP buffer (EPBufPtr)
        _DisposePtr                             | free it
        MOVEA.L 0x29E(A2),A0                    | A0 = NRVars
        _DisposePtr                             | free it
        MOVE.L  0x2AA(A2),D0                    | D0 = LUQElPtr (lookup-reply block + $1A)
        BEQ.B   E_MPP_CLOSE_VARS                | none (no name registered) ->
        MOVEQ.L #0x1A,D1                        | back ...
        SUB.L   D1,D0                           | ... to the start of the block
        MOVEA.L D0,A0                           | A0 = lookup-reply block
        _DisposePtr                             | free it
E_MPP_CLOSE_VARS:
        MOVEA.L A2,A0                           | A0 = MPP variables
        _DisposePtr                             | free them
E_MPP_CLOSE_PORT:
        ST.B    (PortBUse).W                    | PortBUse = $FF: port B free
E_MPP_CLOSE_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| MPP_SCCINIT: write a table of words (value << 8) + register to SCC
| channel B (register number, then value) up to a 0 word
| Called by E_MPP_Close, MPP_SCCSETUP.
| -------------------------------------------------------------------------
MPP_SCCINIT:
        MOVEA.L (SCCWr).W,A3                    | A3 = SCC channel B control (write)
MPP_SCCINIT_LOOP:
        MOVE.W  (A0)+,D0                        | D0 = next word
        BEQ.B   E_MPP_CLOSE_EXIT                | 0 = end -> return
        MOVE.B  D0,(A3)                         | WR0: register number (low byte)
        ROR.W   #0x8,D0                         | value to the low byte
        MOVE.B  D0,(A3)                         | write the value
        BRA.B   MPP_SCCINIT_LOOP                | next word
| MPP_SCCRESET_TBL: channel B after Close - reset, mouse Y (DCD) on
MPP_SCCRESET_TBL:
        .byte   0x4A,0x09,0x00,0x0A,0x10,0x00   | WR9 = $4A (reset channel B, MIE, NV), WR10 = 0, WR0 = $10 (reset ext/status)
        .byte   0x08,0x0F,0x01,0x01,0x00,0x00   | WR15 = $08 (DCD interrupt), WR1 = $01 (ext/status int. on), end

| -------------------------------------------------------------------------
| E_MPP_Open: port B must be free (PortBUse < 0) and configured for
| AppleTalk or unconfigured (SPConfig); an extended open (immediate bit
| of the _Open trap set, IM V-515) with ioMix bit 31 asks for a server
| node ID ($80..$FE).  Allocates the variables, takes units 7/8 (.BIn/
| .BOut, if not opened) out of the unit table, computes the LAP timing
| loop counts, sets up SCC channel B for LocalTalk, picks a node ID (PRAM
| hint SPATalkB, else random) and sends lapENQs until no node answers,
| installs DDP, the RTMP socket (1) and the echoer socket (4), asks for a
| router (RTMP request), opens .ATP and initializes NBP.  A0 = parameter
| block, A1 = .MPP DCE.  portInUse, portNotCf, memFullErr.
| -------------------------------------------------------------------------
E_MPP_Open:
        BTST    #0x9,ioTrap(A0)                 | immediate bit of the _Open trap: extended open?
        BEQ.B   E_MPP_OPEN_WSNODE               | no -> workstation node
        TST.B   0x1C(A0)                        | ioMix (ioMisc, +$1C) bit 31: server node wanted?
        BPL.B   E_MPP_OPEN_WSNODE               | no ->
        BSET    #0x7,(SPATalkB)                 | SPATalkB bit 7: server node range
        BRA.B   E_MPP_OPEN_PORT                 | ->
E_MPP_OPEN_WSNODE:
        BCLR    #0x7,(SPATalkB)                 | SPATalkB bit 7 clear: workstation range
E_MPP_OPEN_PORT:
        MOVEQ.L #-0x61,D0                       | portInUse (-97)
        TST.B   (PortBUse).W                    | port B in use (>= 0)?
        BPL.B   E_MPP_CLOSE_EXIT                | yes -> return portInUse
| SPConfig: port B use type must be useFree (0) or useATalk (1)
        MOVEQ.L #-0x62,D0                       | portNotCf (-98)
        MOVE.B  (SPConfig).W,D1                 | SPConfig
        ANDI.B  #0xF,D1                         | port B use type (low nibble)
        SUBQ.B  #0x1,D1                         | > useATalk?
        BGT.B   E_MPP_CLOSE_EXIT                | yes -> return portNotCf
| allocate the MPP variables
        CLR.L   (ABusVars).W                    | ABusVars = nil meanwhile
        MOVE.L  #0x356,D0                       | $356 = 854 bytes
        _NewPtrSysClear                         | zeroed block in the system heap
        BNE.B   E_MPP_CLOSE_EXIT                | out of memory -> return
| initialize
        MOVE.B  #0x1,(PortBUse).W               | PortBUse = useATalk (1)
        MOVEA.L A0,A2                           | A2 = MPP variables
        MOVE.L  A2,(ABusVars).W                 | ABusVars
        MOVE.L  A1,(ABusVars_dce).W             | AbusDCE = .MPP DCE
| take unit 8 (.BOut) out of the unit table unless it has been opened
        MOVEA.L (UTableBase).W,A0               | A0 = unit table
        MOVEA.L 0x20(A0),A3                     | A3 = unit 8 DCE handle (.BOut)
        MOVE.L  A3,D0                           | installed?
        BEQ.B   E_MPP_OPEN_BIN                  | no ->
        MOVEA.L (A3),A3                         | A3 = DCE
        TST.B   dCtlQueue+1(A3)                 | dCtlQueue+1 (version, set by its Open)?
        BNE.B   E_MPP_OPEN_BIN                  | set: driver in use -> leave it
        MOVE.L  D0,0x2EC(A2)                    | SaveBOut
        CLR.L   0x20(A0)                        | remove it from the unit table
| the same for unit 7 (.BIn)
E_MPP_OPEN_BIN:
        MOVEA.L 0x1C(A0),A3                     | A3 = unit 7 DCE handle (.BIn)
        MOVE.L  A3,D0                           | installed?
        BEQ.B   E_MPP_OPEN_PHTBL                | no ->
        MOVEA.L (A3),A3                         | A3 = DCE
        TST.B   dCtlQueue+1(A3)                 | dCtlQueue+1 (version, set by its Open)?
        BNE.B   E_MPP_OPEN_PHTBL                | set: driver in use -> leave it
        MOVE.L  D0,0x2E8(A2)                    | SaveBIn
        CLR.L   0x1C(A0)                        | remove it from the unit table
| table sizes; all 8 LAP protocol table entries free
E_MPP_OPEN_PHTBL:
        MOVE.W  #0x80C,0x22(A2)                 | NumOfPHs = 8, NumOfSkts = 12
        MOVEQ.L #0x7,D0                         | 8 entries
E_MPP_OPEN_PHLOOP:
        ST.B    0x24(A2,D0.W)                   | protocol type $FF = free
        DBF.W   D0,E_MPP_OPEN_PHLOOP            | loop
| LAP configuration from MPP_CONFIG_TBL
        LEA.L   MPP_CONFIG_TBL(PC),A0           | A0 = configuration table
        MOVEA.L (VIA).W,A1                      | A1 = VIA base
        ADDA.W  #0x1E00,A1                      | + vBufA (register 15: port A, no handshake)
        MOVE.L  A1,0x310(A2)                    | VAVBufA = its address
        MOVE.L  (A0)+,0x314(A2)                 | VSTData bytes 0-3
        MOVE.W  (A0)+,0x318(A2)                 | VSTData bytes 4-5
        MOVE.W  (A0)+,0x1C(A2)                  | vSCCEnable = $2100
| the 8 timing loop counts (VAbortWait .. VWait100): computed from the
| CPU speed on ROMs >= $76, else copied from MPP_CONFIG_TBL
        LEA.L   0x2C8(A2),A1                    | A1 -> VAbortWait
        MOVEQ.L #0x10,D0                        | 16 bytes (8 words)
        MOVEA.L (ROMBase).W,A3                  | A3 = ROM base
        CMPI.B  #0x76,0x9(A3)                   | ROM version >= $76 (SE: TimeDBRA/TimeSCCDB set)?
        BLT.B   E_MPP_OPEN_OLDTIMES             | no -> fixed values
        MOVEQ.L #0x0,D1                         | D1.L = 0
        MOVE.W  (TimeDBRA).W,D1                 | D1 = DBRA loops per millisecond
        DIVU.W  #0x64,D1                        | / 100: about the CPU clock in MHz
        LEA.L   MPP_TIMING_TBL(PC),A3           | A3 = timing table
| count = (time - cycles / MHz) * loops per ms / 1000 - 1
E_MPP_OPEN_TIMELOOP:
        MOVE.W  (A3)+,D3                        | D3 = time in microseconds
        MOVEQ.L #0x0,D2                         | D2.L = 0
        MOVE.B  (A3)+,D2                        | D2 = overhead in CPU cycles
        DIVU.W  D1,D2                           | / MHz = overhead in microseconds
        SUB.W   D2,D3                           | time left for the loop
        TST.B   (A3)+                           | loop type: $FF = SCC polling loop?
        BMI.B   E_MPP_OPEN_SCCTIME              | yes ->
        MULU.W  (TimeDBRA).W,D3                 | * DBRA loops per millisecond
E_MPP_OPEN_TIMESTORE:
        DIVU.W  #0x3E8,D3                       | / 1000
        SUBQ.W  #0x1,D3                         | DBF count
        MOVE.W  D3,(A1)+                        | store it
        SUBQ.W  #0x2,D0                         | 8 values
        BNE.B   E_MPP_OPEN_TIMELOOP             | loop
        BRA.B   E_MPP_OPEN_VECTORS              | ->
E_MPP_OPEN_SCCTIME:
        MULU.W  (TimeSCCDB).W,D3                | * SCC polling loops per millisecond
        BRA.B   E_MPP_OPEN_TIMESTORE            | ->
E_MPP_OPEN_OLDTIMES:
        _BlockMove                              | copy the 8 fixed values (A0 -> A1, D0 = 16)
| install the interrupt handlers and the VBL task, set up the SCC
E_MPP_OPEN_VECTORS:
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
| SCC channel B vectors; the old ones go to SaveVects
        LEA.L   (Lvl2DT_2).W,A3                 | A3 = Lvl2DT[2]
        LEA.L   0x2F0(A2),A1                    | A1 = SaveVects
        LEA.L   LAP_RCVINT(PC),A0               | Rx character handler
        MOVE.L  (A3),(A1)+                      | save the old Lvl2DT[2]
        MOVE.L  A0,(A3)+                        | Lvl2DT[2] = LAP_RCVINT
        LEA.L   LAP_SPECIALINT(PC),A0           | special receive condition handler
        MOVE.L  (A3),(A1)+                      | save the old Lvl2DT[3]
        MOVE.L  A0,(A3)+                        | Lvl2DT[3] = LAP_SPECIALINT
        LEA.L   LAP_EXTINT(PC),A0               | external/status handler
        MOVE.L  (ExtStsDT).W,(A1)               | save the old ExtStsDT[0]
        MOVE.L  A0,(ExtStsDT).W                 | ExtStsDT[0] = LAP_EXTINT
| VBL task
        LEA.L   0x288(A2),A0                    | A0 = VBL task (+$288)
        MOVE.W  #0x1,qType(A0)                  | qType = vType (1)
        LEA.L   MPP_VBLTASK(PC),A1              | A1 = MPP_VBLTASK
        MOVE.L  A1,vblAddr(A0)                  | vblAddr
        MOVE.W  #0x14,vblCount(A0)              | vblCount = 20 ticks
        _VInstall                               | install it
        BSR.W   MPP_SCCSETUP                    | SCC channel B for LocalTalk
        MOVE.W  (Ticks_LoWord).W,0x2B8(A2)      | RandomSeed = Ticks
        MOVE.W  (SP)+,SR                        | restore SR
| node ID: the hint in PRAM unless 0 or $FF, else random in the range of
| bit 7 of SPATalkB
        MOVE.B  (SPATalkB).W,D0                 | D0 = SPATalkB (node ID hint)
E_MPP_OPEN_CHKNODE:
        TST.B   D0                              | 0?
        BEQ.B   E_MPP_OPEN_RANDOM               | yes -> random
        CMPI.B  #0xFF,D0                        | $FF (broadcast)?
        BNE.B   E_MPP_OPEN_TRYNODE              | no -> try it
E_MPP_OPEN_RANDOM:
        BSR.W   MPP_RANDOM                      | D0 = random number
        BCLR    #0x7,D0                         | workstation range ...
        TST.B   (SPATalkB).W                    | ... unless a server node is wanted
        BPL.B   E_MPP_OPEN_CHKNODE              | workstation -> check it
        BSET    #0x7,D0                         | server range $80..$FF
        BRA.B   E_MPP_OPEN_CHKNODE              | -> check it
| claim it: 20 (workstation) or 120 (server) rounds of lapENQ to that
| address must stay unanswered
E_MPP_OPEN_TRYNODE:
        MOVEQ.L #0x13,D4                        | 20 rounds
        TST.B   D0                              | server node?
        BPL.B   E_MPP_OPEN_CLAIM                | no ->
        MOVEQ.L #0x77,D4                        | 120 rounds (more thorough, IM V-515)
E_MPP_OPEN_CLAIM:
        MOVE.B  D0,(A2)                         | sysLAPAddr = candidate
        CLR.B   0x2BB(A2)                       | fLAPAdrValid = 0
        MOVEA.L (SCCWr).W,A1                    | A1 = SCC channel B control (write)
        MOVE.B  #0x6,(A1)                       | WR0: select WR6
        CLR.B   0x2BD(A2)                       | fAdrInUse = 0
        MOVE.B  (A2),(A1)                       | WR6 = node ID (SDLC address for the address search)
E_MPP_OPEN_ENQLOOP:
        ST.B    0x2BE(A2)                       | fSendENQ
        MOVE.B  (A2),D2                         | D2 = candidate address
        BSR.W   MPP_SENDENQ                     | send lapENQs to it
E_MPP_OPEN_ENQWAIT:
        TST.B   0x2BE(A2)                       | write finished (fSendENQ cleared)?
        BNE.B   E_MPP_OPEN_ENQWAIT              | no -> wait
        TST.B   0x2BD(A2)                       | fAdrInUse (somebody answered)?
        BNE.B   E_MPP_OPEN_RANDOM               | yes -> try another address
        DBF.W   D4,E_MPP_OPEN_ENQLOOP           | next round
| node ID is ours: keep it as the PRAM hint
        MOVE.B  (A2),(SPATalkB).W               | SPATalkB = node ID (bit 7 = server range)
        ST.B    0x2BB(A2)                       | fLAPAdrValid
        LEA.L   (SysParam_SPValid).W,A0         | A0 = SysParam
        MOVEQ.L #-0x1,D0                        | all bytes (64K-ROM interface; ignored here)
        _WriteParam                             | write SysParam to the clock chip PRAM
| DDP protocol handlers: entries 7 (type 1) and 6 (type 2)
        LEA.L   DDP_RCVSHORT(PC),A3             | A3 = shortDDP handler
        LEA.L   0x4C(A2),A0                     | A0 -> end of the handler table
        MOVE.L  A3,-(A0)                        | handler entry 7
        LEA.L   DDP_RCVLONG(PC),A3              | A3 = longDDP handler
        MOVE.L  A3,-(A0)                        | handler entry 6
| protocol types
        LEA.L   0x2C(A2),A0                     | A0 -> end of the type table
        MOVE.B  #0x1,-(A0)                      | type entry 7 = 1 (shortDDP)
        MOVE.B  #0x2,-(A0)                      | type entry 6 = 2 (longDDP)
| RTMP socket 1 in socket table entry 11, then ask for a router
        LEA.L   RTMP_LISTENER(PC),A0            | A0 = RTMP listener
        MOVE.L  A0,0x84(A2)                     | listener of entry 11
        MOVE.B  #0x1,0x57(A2)                   | entry 11 = socket 1 (RTMP)
        BSR.W   MPP_RTMPREQUEST                 | broadcast an RTMP request
| the echoer: EP buffer, socket 4 in socket table entry 10
        MOVE.L  #0x28B,D0                       | $28B bytes: EP buffer
        _NewPtrSysClear                         | zeroed block in the system heap
        BNE.B   E_MPP_OPEN_PTRS                 | out of memory -> no echoer
        MOVE.L  A0,0x88(A2)                     | EPBufPtr
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE
        MOVE.W  dCtlRefNum(A1),ioRefNum(A0)     | ioRefNum = .MPP refNum
        LEA.L   csCode(A0),A1                   | A1 -> csCode
        MOVE.W  #0xF6,(A1)+                     | csCode = 246 (WriteDDP)
        MOVE.W  #0x400,(A1)+                    | socket 4, checksumFlag 0
        LEA.L   0x22(A0),A3                     | A3 = WDS (+$22)
        MOVE.L  A3,(A1)+                        | wdsPointer
        LEA.L   0x31(A0),A1                     | A1 = DDP header template (+$31, odd)
        MOVE.L  A1,0x2(A3)                      | WDS entry 1 pointer
        MOVE.B  #0x4,0xF(A1)                    | +15 DDP type 4 (AEP)
        LEA.L   0x41(A0),A1                     | A1 = echo data (+$41)
        MOVE.L  A1,0x8(A3)                      | WDS entry 2 pointer
        LEA.L   EP_LISTENER(PC),A1              | A1 = echoer listener
        MOVE.L  A1,0x80(A2)                     | listener of entry 10
        MOVE.B  #0x4,0x56(A2)                   | entry 10 = socket 4 (echoer)
| JDDPWrite and LookupPtr (bit 31 clear: NIS opened by the first RegisterName)
E_MPP_OPEN_PTRS:
        LEA.L   MPP_JDDPWRITE(PC),A0            | A0 = DDP jump table
        MOVE.L  A0,0x2A2(A2)                    | JDDPWrite
        LEA.L   LUCODE(PC),A3                   | A3 = lookup-reply code
        MOVE.L  A3,0x29A(A2)                    | LookupPtr
| open .ATP
        SUBA.W  #0x32,SP                        | parameter block on the stack
        LEA.L   MPP_ATPNAME(PC),A0              | A0 = ".ATP"
        MOVE.L  A0,0x12(SP)                     | ioNamePtr
        MOVEA.L SP,A0                           | A0 = parameter block
        CLR.B   ioPermssn(A0)                   | ioPermssn = 0
        _Open                                   | open .ATP
        ADDA.W  #0x32,SP                        | drop the parameter block
        MOVEQ.L #0x7,D3                         | NBP code entry 0 = NBP_INIT
        BSR.W   MPP_INSTALLNBP                  | install and initialize NBP
        TST.W   0x1A(A2)                        | sysNetNum known (router answered)?
        BNE.B   E_MPP_OPEN_DONE                 | yes ->
        BSR.B   MPP_RTMPREQUEST                 | no: ask once more
E_MPP_OPEN_DONE:
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE
        MOVE.B  #0x30,dCtlQueue+1(A1)           | dCtlQueue+1: driver version 48
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from E_MPP_Open

| -------------------------------------------------------------------------
| MPP_RTMPREQUEST: broadcast an RTMP request (DDP type 5, socket 1 to
| socket 1) as a LAP frame built on the stack, and wait until it is sent.
| Routers answer with RTMP data, handled by RTMP_LISTENER.
| Called by E_MPP_Open (twice).
| -------------------------------------------------------------------------
MPP_RTMPREQUEST:
        CLR.W   -(SP)                           | WDS: terminator
        SUBQ.W  #0x4,SP                         | WDS: pointer (set below)
        MOVE.W  #0x9,-(SP)                      | WDS: length 9
        MOVEA.L SP,A1                           | A1 = WDS
        MOVE.W  #0x501,-(SP)                    | DDP type 5 (RTMP request), RTMP function 1
        MOVE.W  #0x101,-(SP)                    | dest socket 1, source socket 1
        MOVE.W  #0x6,-(SP)                      | ddpLength = 6
        MOVE.W  #0x1,-(SP)                      | lapSrcAdr (set when sent), lapType 1 (shortDDP)
        ST.B    D2                              | D2 = $FF (broadcast)
        MOVE.W  D2,-(SP)                        | lapDstAdr = $FF (after a pad byte)
        LEA.L   0x1(SP),A3                      | A3 = frame (9 bytes, odd address)
        MOVE.L  A3,0xB(A3)                      | WDS pointer = frame
        BSR.B   MPP_LAPSEND                     | send it, set +$2BE when done
MPP_RTMPREQUEST_WAIT:
        TST.B   0x2BE(A2)                       | sent?
        BEQ.B   MPP_RTMPREQUEST_WAIT            | no -> wait
        ADDA.W  #0x12,SP                        | drop frame and WDS
        RTS                                     | return from MPP_RTMPREQUEST

| -------------------------------------------------------------------------
| MPP_LAPSEND: LAPWRITE, then set +$2BE (fSendENQ, here a 'sent' flag)
| when the write has finished (now or later from the deferred write)
| -------------------------------------------------------------------------
MPP_LAPSEND:
        BSR.W   LAPWRITE                        | send the frame; resumes here when done
        ST.B    0x2BE(A2)                       | sent
        RTS                                     | return
| MPP_ATPNAME: driver name for the _Open of .ATP
MPP_ATPNAME:
        .byte   0x04,0x2E,0x41,0x54,0x50,0x20   | Pascal string ".ATP" and a pad byte
| MPP_SENDENQ: LAPWRITE_ENQ (lapENQs to D2), then clear fSendENQ when the
| write has finished
MPP_SENDENQ:
        BSR.W   LAPWRITE_ENQ                    | send lapENQ; resumes here when done
        CLR.B   0x2BE(A2)                       | fSendENQ = 0: finished
        RTS                                     | return

| -------------------------------------------------------------------------
| MPP_SCCSETUP: program SCC channel B for LocalTalk (two tables)
| -------------------------------------------------------------------------
MPP_SCCSETUP:
        LEA.L   MPP_SCCLAP_TBL(PC),A0           | A0 = first table
        BSR.W   MPP_SCCINIT                     | write it
        LEA.L   MPP_SCCLAP_TBL2(PC),A0          | A0 = second table
        BRA.W   MPP_SCCINIT                     | write it, return
| MPP_SCCLAP_TBL: words (value << 8) + register for MPP_SCCINIT
MPP_SCCLAP_TBL:
        .byte   0x40,0x09,0x20,0x04,0xE0,0x0A   | WR9 = $40 reset channel B, WR4 = $20 SDLC x1, WR10 = $E0 FM0, CRC preset
        .byte   0x00,0x06,0x7E,0x07,0x06,0x0C   | WR6 = 0 (address), WR7 = $7E (flag), WR12 = 6 (BRG: ~230 kbit/s)
        .byte   0x00,0x0D,0xC0,0x0E,0xDD,0x03   | WR13 = 0, WR14 = $C0 (DPLL FM mode), WR3 = $DD (Rx on, hunt, CRC, address search)
        .byte   0x00,0x02,0x08,0x0F,0x09,0x01   | WR2 = 0, WR15 = $08 (DCD int.), WR1 = $09 (Rx int. first char/special, ext/status int.)
        .byte   0x0A,0x09,0x00,0x00             | WR9 = $0A (MIE, NV), end
| MPP_SCCLAP_TBL2: clocks and transmitter
MPP_SCCLAP_TBL2:
        .byte   0x70,0x0B,0x21,0x0E,0x60,0x05   | WR11 = $70 (Rx clock DPLL, Tx clock BRG), WR14 = $21 (DPLL search, BRG on), WR5 = $60 (Tx off, RTS off)
        .byte   0x00,0x00                       | end
| MPP_CONFIG_TBL: copied by E_MPP_Open: VSTData (6), vSCCEnable, then the
| fixed timing loop counts for ROMs before the SE's (the Mac Plus values)
MPP_CONFIG_TBL:
        .byte   0x05,0x60,0x0E,0x41,0x03,0xDD   | VSTData: WR5 = $60, WR14 = $41, WR3 = $DD
        .short  0x2100                          | vSCCEnable = $2100
        .short  0x0046                          | VAbortWait = 70
        .short  0x0014                          | VRTimeout = 20 polls
        .short  0x001E                          | VSTimeout = 30 polls
        .short  0x0082                          | VDataTO = 130 polls
        .short  0x007D                          | VGetXXX = 125 polls
        .short  0x0028                          | VXmitOn = 40
        .short  0x0014                          | VRTStoCTS = 20
        .short  0x0039                          | VWait100 = 57
| MPP_TIMING_TBL: per timing value: time in microseconds (word), overhead
| of the surrounding code in CPU cycles (byte), loop type ($FF = SCC
| polling loop, TimeSCCDB; 0 = DBF loop, TimeDBRA)
MPP_TIMING_TBL:
        .byte   0x00,0x62,0x3A,0x00             | VAbortWait: 98 us, 58 cycles, DBF
        .byte   0x00,0x64,0x00,0xFF             | VRTimeout: 100 us, SCC polls
        .byte   0x00,0xC8,0x00,0xFF             | VSTimeout: 200 us, SCC polls
        .byte   0x01,0xF4,0x00,0xFF             | VDataTO: 500 us, SCC polls
        .byte   0x01,0x90,0x72,0xFF             | VGetXXX: 400 us, 114 cycles, SCC polls
        .byte   0x00,0x46,0x2C,0x00             | VXmitOn: 70 us, 44 cycles, DBF
        .byte   0x00,0x1E,0x00,0x00             | VRTStoCTS: 30 us, DBF
        .byte   0x00,0x64,0x5A,0x00             | VWait100: 100 us, 90 cycles, DBF
MPP_COPYRIGHT:
        .ascii  "COPYRIGHT (C) APPLE COMPUTER"  | copyright string (not referenced)

| -------------------------------------------------------------------------
| NBP_DISPATCH: NBP code entry (NRPtr).  D3 = csCode - 242; entry D3 - 7
| of NBP_DISPATCH_TBL is called with A3 = NRVars (A0 = parameter block,
| A1 = entityPtr / ntQElPtr, D1.B = interval).  D3 < 7 (from E_MPP_Close
| with D3 = 0): NBP_CLOSE.
| -------------------------------------------------------------------------
NBP_DISPATCH:
        SUBQ.W  #0x7,D3                         | D3 = csCode - 249
        BMI.B   NBP_CLOSE                       | negative (.MPP Close) ->
        ADD.W   D3,D3                           | word index
        LEA.L   NBP_DISPATCH_TBL(PC),A3         | A3 = table
        ADDA.W  D3,A3                           | A3 -> entry
        MOVE.W  (A3),D3                         | offset from NBP_DISPATCH
        LEA.L   NBP_DISPATCH(PC),A3             | A3 = NBP_DISPATCH
        ADDA.W  D3,A3                           | A3 = routine
        MOVE.L  A3,-(SP)                        | push it
        MOVEA.L 0x29E(A2),A3                    | A3 = NRVars
        RTS                                     | -> routine (from NBP_DISPATCH_TBL)
| NBP_DISPATCH_TBL - offsets from NBP_DISPATCH; entry 0 (249, LoadNBP in
| the RAM driver) is only reached from E_MPP_Open
NBP_DISPATCH_TBL:
        .short  NBP_INIT-NBP_DISPATCH           | 0 NBP_INIT ($004A)
        .short  CONFIRMNAME-NBP_DISPATCH        | 250 ConfirmName ($0098)
        .short  LOOKUPNAME-NBP_DISPATCH         | 251 LookupName ($01E2)
        .short  REMOVENAME-NBP_DISPATCH         | 252 RemoveName ($0144)
        .short  REGISTERNAME-NBP_DISPATCH       | 253 RegisterName ($009C)
        .short  KILLNBP-NBP_DISPATCH            | 254 KillNBP ($007C)
        .short  UNLOADNBP-NBP_DISPATCH          | 255 UnloadNBP ($00FE)
        .short  SETSELFSEND-NBP_DISPATCH        | 256 SetSelfSend ($008A)

| -------------------------------------------------------------------------
| NBP_CLOSE: (.MPP Close) remove the retry timers of all active NBP
| requests; the requests are not completed
| -------------------------------------------------------------------------
NBP_CLOSE:
        MOVEA.L 0x29E(A2),A3                    | A3 = NRVars
        MOVEQ.L #0x5,D2                         | 6 request slots
NBP_CLOSE_LOOP:
        TST.B   0x2(A3,D2.W)                    | slot active (NBP ID set)?
        BEQ.B   NBP_CLOSE_NEXT                  | no ->
        MOVE.W  D2,D3                           | D3 = slot
        MULU.W  #0x12,D3                        | * 18
        LEA.L   0xC(A3,D3.W),A0                 | A0 = its VBL task
        _VRemove                                | remove it
NBP_CLOSE_NEXT:
        SUBQ.W  #0x1,D2                         | next slot
        BPL.B   NBP_CLOSE_LOOP                  | loop
        RTS                                     | return to E_MPP_Close

| -------------------------------------------------------------------------
| NBP_INIT: allocate NRVars and open the NBP socket (dynamic number,
| listener NBP_LISTENER), on which requests go out and replies come in.
| NRVars ($A1 bytes): +$00 6 (number of request slots), +$02 6 bytes: NBP
| ID of each active request (0 = free), +$08 6 x 18 bytes: per request +0
| the call, +4 the VBL task of its retry timer (NBP_VBLTASK), +$74 NBP
| socket, +$75 last NBP ID, +$76 WDS of the request packet (header ->
| +$91, 7 bytes -> +$8A, entity name, 0), +$8A NBP header and tuple
| address (enumerator 0), +$91 DDP header template.  A2 = MPP
| variables; D0 = result.
| -------------------------------------------------------------------------
NBP_INIT:
        MOVE.L  #0xA1,D0                        | $A1 bytes
        _NewPtrSysClear                         | zeroed block in the system heap
        BNE.B   NBP_INIT_EXIT                   | out of memory -> return
        LEA.L   NBP_LISTENER(PC),A1             | A1 = listener
        MOVEA.L 0x2A2(A2),A3                    | A3 = JDDPWrite
        CLR.W   D1                              | socket 0: assign one
        JSR     0x2(A3)                         | MPP_JOPENSOCKET: open the NBP socket
        TST.W   D0                              | opened?
        BNE.B   NBP_INIT_FAIL                   | no ->
        MOVE.B  D1,0x74(A0)                     | +$74 = NBP socket
        MOVE.B  #0x6,(A0)                       | +$00 = 6 request slots
        MOVE.L  A0,0x29E(A2)                    | NRVars
NBP_INIT_EXIT:
        RTS                                     | return from NBP_INIT
| free the block, return the error
NBP_INIT_FAIL:
        MOVE.W  D0,D1                           | save the error
        _DisposePtr                             | free the block
        MOVE.W  D1,D0                           | D0 = error
        RTS                                     | return from NBP_INIT

| -------------------------------------------------------------------------
| KillNBP (csCode 254, IM V-518): abort the NBP call at nKillQEl
| (csParam): it completes with reqAborted; KillNBP completes with noErr,
| or cbNotFound if nKillQEl is not an active NBP call.
| -------------------------------------------------------------------------
KILLNBP:
        MOVEA.L csParam(A0),A0                  | A0 = nKillQEl (the call to abort)
        MOVE.W  #-0x451,D0                      | reqAborted (-1105)
        BSR.W   NBP_COMPLETE                    | complete it; D0 = noErr or cbNotFound
        BRA.B   NBP_IODONE                      | -> IODone (KillNBP) with D0

| -------------------------------------------------------------------------
| SetSelfSend (csCode 256, IM V-516): oldSelfFlag = SelfSend, SelfSend =
| newSelfFlag; noErr
| -------------------------------------------------------------------------
SETSELFSEND:
        MOVE.B  0x2AE(A2),0x1D(A0)              | oldSelfFlag = SelfSend
        MOVE.B  csParam(A0),0x2AE(A2)           | SelfSend = newSelfFlag
        BRA.B   UNLOADNBP                       | -> IODone, noErr

| -------------------------------------------------------------------------
| ConfirmName (csCode 250): send a LkUp for entityPtr directly to node
| confirmAddr.  A reply sets newSocket: noErr if it is the socket of
| confirmAddr, nbpConfDiff if not; nbpNoConfirm if none comes.
| -------------------------------------------------------------------------
CONFIRMNAME:
        BRA.W   NBP_SENDREQ                     | -> send the LkUp (NBP_BUILDREQ takes confirmAddr)

| -------------------------------------------------------------------------
| RegisterName (csCode 253): enter the names-table entry at ntQElPtr
| (address, entity) in the names table; the first call opens the NIS
| (socket 2) and allocates the lookup-reply block.  With verifyFlag the
| name is first looked up (own table or a pending RegisterName:
| nbpDuplicate; network: LkUp, a reply means nbpDuplicate).  nbpNISErr,
| memFullErr, tooManyReqs.
| -------------------------------------------------------------------------
REGISTERNAME:
        MOVE.L  A0,D3                           | D3 = parameter block
        TST.L   0x29A(A2)                       | LookupPtr bit 31: NIS open?
        BMI.B   REGISTERNAME_VERIFY             | yes ->
| first registration: lookup-reply block and the NIS
        MOVE.L  #0x98,D0                        | $98 bytes: lookup-reply block
        _NewPtrSysClear                         | allocate it
        BNE.B   REGISTERNAME_FAIL               | out of memory -> IODone with the error
        ADDA.W  #0x1A,A0                        | A0 -> its csCode field
        MOVE.L  A0,0x2AA(A2)                    | LUQElPtr
        MOVEM.L D1/A1/A3,-(SP)                  | save registers
        MOVEQ.L #0x2,D1                         | socket 2 (NIS)
        MOVEA.L 0x29A(A2),A1                    | A1 = LUCODE ...
        ADDQ.W  #0x4,A1                         | ... +4 = NIS_LISTENER
        MOVEA.L 0x2A2(A2),A3                    | A3 = JDDPWrite
        JSR     0x2(A3)                         | MPP_JOPENSOCKET: open the NIS
        MOVEM.L (SP)+,D1/A1/A3                  | restore registers
        TST.W   D0                              | opened?
        BEQ.B   REGISTERNAME_NISOK              | yes ->
        MOVE.W  #-0x405,D0                      | nbpNISErr (-1029)
        BRA.B   REGISTERNAME_FAIL               | -> IODone with it
| NIS open
REGISTERNAME_NISOK:
        BSET    #0x7,0x29A(A2)                  | LookupPtr bit 31: NIS open
        MOVEA.L D3,A0                           | A0 = parameter block
| verify the name first?
REGISTERNAME_VERIFY:
        TST.B   0x22(A0)                        | verifyFlag?
        BEQ.B   REGISTERNAME_ENTER              | no -> enter it now
        ADDA.W  #0x9,A1                         | A1 -> entity name (ntEntity)
        BSR.W   NBP_FINDPENDING                 | being registered by a pending call?
        BNE.B   REGISTERNAME_DUP                | yes -> nbpDuplicate
        BSR.B   NBP_FINDNAME                    | in our names table?
        BEQ.W   NBP_SENDREQ                     | no -> look it up on the network
REGISTERNAME_DUP:
        MOVE.W  #-0x403,D0                      | nbpDuplicate (-1027)
REGISTERNAME_FAIL:
        BRA.B   NBP_IODONE                      | -> IODone with D0
REGISTERNAME_ENTER:
        BSR.B   NBP_ENTERNAME                   | enter the name
| UnloadNBP (csCode 255): nothing to unload - noErr (also the noErr exit
| of RegisterName, RemoveName, SetSelfSend)
UNLOADNBP:
        CLR.W   D0                              | noErr
| NBP_IODONE: IODone with D0 (completes the call at the head of the .MPP
| queue)
| Called by: KILLNBP, REGISTERNAME, UNLOADNBP, REMOVENAME, NBP_SENDREQ
NBP_IODONE:
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE
        MOVEA.L (JIODone).W,A0                  | IODone vector
        JMP     (A0)                            | -> IODone

| -------------------------------------------------------------------------
| NBP_ENTERNAME: enter names-table entry A1 (interrupts off): tuple node =
| our node, a tuple enumerator not yet used on its socket, linked in at
| the end.  Uses D1-D2, A3.
| Called by REGISTERNAME_ENTER, NBP_TIMEOUT_REGISTER.
| -------------------------------------------------------------------------
NBP_ENTERNAME:
        CLR.W   D2                              | D2 = enumerator candidate
        MOVE.B  0x7(A1),D1                      | D1 = ntSocket
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
NBP_ENTERNAME_ENUM:
        ADDQ.W  #0x1,D2                         | next candidate
        LEA.L   0x2A6(A2),A3                    | A3 -> NTQueueHd
NBP_ENTERNAME_LOOP:
        TST.L   (A3)                            | end of the table?
        BEQ.B   NBP_ENTERNAME_LINK              | yes: candidate is free ->
        MOVEA.L (A3),A3                         | A3 = next entry
        CMP.B   0x7(A3),D1                      | same socket?
        BNE.B   NBP_ENTERNAME_LOOP              | no ->
        TST.B   D2                              | candidate wrapped to 0?
        BEQ.B   NBP_ENTERNAME_LOOP              | yes: take it anyway
        CMP.B   0x8(A3),D2                      | enumerator in use?
        BEQ.B   NBP_ENTERNAME_ENUM              | yes -> next candidate
        BRA.B   NBP_ENTERNAME_LOOP              | no -> next entry
| fill in the tuple, link the entry at the end (A3 = last entry)
NBP_ENTERNAME_LINK:
        MOVE.B  (A2),0x6(A1)                    | tuple node = sysLAPAddr
        MOVE.B  D2,0x8(A1)                      | tuple enumerator
        CLR.L   (A1)                            | ntLink = nil
        MOVE.L  A1,(A3)                         | link it in
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return from NBP_ENTERNAME

| -------------------------------------------------------------------------
| RemoveName (csCode 252): unlink the names-table entry with the name
| at entityPtr.  nbpNotFound.
| -------------------------------------------------------------------------
REMOVENAME:
        MOVE.W  #-0x404,D0                      | nbpNotFound (-1028)
        BSR.B   NBP_FINDNAME                    | D3 = entry
        BEQ.B   NBP_IODONE                      | not found -> nbpNotFound
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        LEA.L   0x2A6(A2),A0                    | A0 -> NTQueueHd
REMOVENAME_LOOP:
        CMP.L   (A0),D3                         | next is the entry?
        BEQ.B   REMOVENAME_UNLINK               | yes ->
        MOVEA.L (A0),A0                         | A0 = next
        BRA.B   REMOVENAME_LOOP                 | loop
| unlink it
REMOVENAME_UNLINK:
        MOVEA.L D3,A1                           | A1 = entry
        MOVE.L  (A1),(A0)                       | predecessor -> successor
        MOVE.W  (SP)+,SR                        | restore SR
        BRA.B   UNLOADNBP                       | -> IODone, noErr

| -------------------------------------------------------------------------
| NBP_FINDNAME: find the names-table entry whose object and type equal
| those at A1 (NBP_CMPENTITY) -> D3 = entry, NE; or D3 = 0, EQ.
| Preserves the other registers.  Called by REGISTERNAME, REMOVENAME.
| -------------------------------------------------------------------------
NBP_FINDNAME:
        MOVEM.L D0-D1/A0-A3,-(SP)               | save registers
        MOVEA.L A1,A3                           | A3 = name searched for
        LEA.L   0x2A6(A2),A2                    | A2 -> NTQueueHd
        MOVEQ.L #0x0,D3                         | D3 = 0 (not found)
NBP_FINDNAME_LOOP:
        TST.L   (A2)                            | end of the table?
        BEQ.B   NBP_FINDNAME_EXIT               | yes -> EQ
        MOVEA.L (A2),A2                         | A2 = next entry
        MOVEA.L A2,A0                           | A0 = entry
        MOVEA.L A3,A1                           | A1 = name searched for
        BSR.B   NBP_CMPENTITY                   | same object and type?
        BNE.B   NBP_FINDNAME_LOOP               | no -> next entry
        MOVE.L  A2,D3                           | D3 = entry (NE)
NBP_FINDNAME_EXIT:
        MOVEM.L (SP)+,D0-D1/A0-A3               | restore registers
        RTS                                     | return from NBP_FINDNAME

| -------------------------------------------------------------------------
| NBP_CMPENTITY: compare object and type (with their length bytes) of the
| names-table entry A0 (its ntEntity at +9) with the name at A1, by
| _CmpString (case-insensitive) -> EQ if equal.  Uses D0-D1, A0.
| Called by NBP_FINDNAME, NBP_FINDPENDING.
| -------------------------------------------------------------------------
NBP_CMPENTITY:
        CLR.W   D0                              | D0.W = 0
        MOVE.B  (A1),D0                         | object length
        ADD.B   0x1(A1,D0.W),D0                 | + type length
        ADDQ.W  #0x2,D0                         | + 2 length bytes
        MOVE.W  D0,D1                           | D1 = size
        SWAP.W  D0                              | both lengths of the
        MOVE.W  D1,D0                           | compare = size
        ADDA.W  #0x9,A0                         | A0 -> entity name of the entry (ntEntity)
        _CmpString                              | equal? (D0 = 0)
        TST.W   D0                              | EQ = equal
        RTS                                     | return from NBP_CMPENTITY

| -------------------------------------------------------------------------
| NBP_FINDPENDING: is the name at A1 being registered by a pending
| RegisterName (one of the active NBP requests)? -> NE (D3 = -1) if so,
| EQ (D3 = 0) if not.  A3 = NRVars.  Called by REGISTERNAME.
| -------------------------------------------------------------------------
NBP_FINDPENDING:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save registers
        MOVEQ.L #0x0,D3                         | D3 = 0 (no)
        MOVEQ.L #0x5,D2                         | 6 request slots
NBP_FINDPENDING_LOOP:
        TST.B   0x2(A3,D2.W)                    | slot active?
        DBNE.W  D2,NBP_FINDPENDING_LOOP         | no -> next
        BEQ.B   NBP_FINDPENDING_EXIT            | no more active slots ->
        MOVE.W  D2,D1                           | D1 = slot
        MULU.W  #0x12,D1                        | * 18
        MOVEA.L 0x8(A3,D1.W),A0                 | A0 = its call
        CMPI.W  #0xFD,csCode(A0)                | RegisterName (253)?
        BNE.B   NBP_FINDPENDING_NEXT            | no ->
        MOVEA.L 0x1E(A0),A0                     | A0 = its ntQElPtr
        MOVE.L  A1,-(SP)                        | save A1
        BSR.B   NBP_CMPENTITY                   | same name?
        MOVEA.L (SP)+,A1                        | restore A1
        BNE.B   NBP_FINDPENDING_NEXT            | no ->
        MOVEQ.L #-0x1,D3                        | yes: D3 = -1
NBP_FINDPENDING_EXIT:
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore registers
        TST.W   D3                              | NE = being registered
        RTS                                     | return from NBP_FINDPENDING
NBP_FINDPENDING_NEXT:
        SUBQ.W  #0x1,D2                         | next slot
        BMI.B   NBP_FINDPENDING_EXIT            | none left ->
        BRA.B   NBP_FINDPENDING_LOOP            | loop

| -------------------------------------------------------------------------
| LookupName (csCode 251): look up entityPtr in the whole network; the
| replies (NBP_LISTENER) go into retBuffPtr/retBuffSize, numGotten
| counts them.  Ends at maxToGet, a full buffer or after count retries.
| -------------------------------------------------------------------------
LOOKUPNAME:
        CLR.W   0x2A(A0)                        | numGotten = 0
| NBP_SENDREQ: start an NBP request (ConfirmName, LookupName, verifying
| RegisterName) A0 for entity A1 in a free request slot: new NBP ID,
| retry timer (interval D1 * 8 ticks), send the request, then take the
| call off the .MPP queue (it stays pending in its slot) and start the
| next queued call.  A LookupName keeps its return buffer state in the
| call: qLink = next free byte, +$12 = bytes left.  tooManyReqs.
| Bugs fixed by the System's VInstall patch (nonres.a): PAB185 - this state
| is set only after the first send, so a LookupName reply that comes back
| at once is stored where qLink points (0: location zero); the patch skips
| the first send (18 bytes after the _VInstall) and lets the timer send
| it a tick later.  PB073 - the _VInstall is skipped when the slot's VBL
| task is still in the VBL queue (e.g. a slot that NBP_COMPLETE freed
| inside its expiring timer task, without _VRemove, reused by a call made
| from the completion routine).
NBP_SENDREQ:
        MOVE.W  #-0x449,D0                      | tooManyReqs (-1097)
        MOVEQ.L #0x5,D2                         | 6 request slots
NBP_SENDREQ_SLOT:
        TST.B   0x2(A3,D2.W)                    | slot free?
        DBEQ.W  D2,NBP_SENDREQ_SLOT             | no -> next
        BNE.W   NBP_IODONE                      | all busy -> IODone (tooManyReqs)
NBP_SENDREQ_ID:
        ADDQ.B  #0x1,0x75(A3)                   | next NBP ID ...
        BEQ.B   NBP_SENDREQ_ID                  | ... never 0
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        MOVE.B  0x75(A3),0x2(A3,D2.W)           | slot: NBP ID (in use)
        MULU.W  #0x12,D2                        | slot * 18
        LEA.L   0x8(A3,D2.W),A2                 | A2 -> slot: call
        MOVE.L  A0,(A2)+                        | the call
        MOVE.W  (SP)+,SR                        | restore SR
| retry timer: the slot's VBL task
        MOVEA.L A2,A0                           | A0 = VBL task of the slot
        ADDQ.W  #0x4,A2                         | skip qLink
        MOVE.W  #0x1,(A2)+                      | qType = vType (1)
        PEA.L   NBP_VBLTASK(PC)                 | NBP_VBLTASK ...
        MOVE.L  (SP)+,(A2)+                     | ... = vblAddr
        LSL.W   #0x3,D1                         | interval * 8 ticks
        ANDI.W  #0x3FF,D1                       | at most $3FF
        MOVE.W  D1,(A2)+                        | vblCount
        _VInstall                               | start the retry timer
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables again
| send the request
        BSR.B   NBP_BUILDREQ                    | WDS and packet for slot D2
        LEA.L   0x76(A3),A1                     | A1 = WDS (NRVars+$76)
        MOVEA.L 0x2A2(A2),A0                    | A0 = JDDPWrite
        CLR.B   D3                              | no checksum
        JSR     (A0)                            | DDPWRITE; resumes here when sent
| take the call off the .MPP queue, keep it pending
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE
        BCLR    #0x7,dCtlFlags+1(A1)            | dCtlFlags: clear drvrActive
        MOVEA.L dCtlQHead(A1),A0                | A0 = this call (head of the queue)
        MOVE.L  (A0),dCtlQHead(A1)              | dCtlQHead = next call in the queue
        BNE.B   NBP_SENDREQ_DEQUEUED            | there is one ->
        CLR.L   dCtlQTail(A1)                   | queue empty: dCtlQTail = nil
NBP_SENDREQ_DEQUEUED:
        CMPI.W  #0xFB,csCode(A0)                | LookupName (251)?
        BNE.B   NBP_STARTNEXT                   | no ->
        MOVE.L  0x22(A0),(A0)                   | qLink = retBuffPtr: next free byte
        MOVE.W  0x26(A0),0x12(A0)               | +$12 = retBuffSize: bytes left
| NBP_STARTNEXT: start the next queued call, if any (as a new
| E_MPP_Control); entered with SR on the stack, A1 = .MPP DCE
NBP_STARTNEXT:
        MOVE.L  dCtlQHead(A1),D0                | next call queued?
        BEQ.B   NBP_STARTNEXT_NONE              | no ->
        MOVEA.L D0,A0                           | A0 = next parameter block
        MOVEQ.L #0x0,D0                         | clear D0
        BSET    #0x7,dCtlFlags+1(A1)            | dCtlFlags: set drvrActive again
        MOVE.W  (SP)+,SR                        | restore SR
        JSR     E_MPP_Control(PC)               | process it
        MOVEQ.L #0x0,D0                         | D0 = 0
        RTS                                     | return
NBP_STARTNEXT_NONE:
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return

| -------------------------------------------------------------------------
| NBP_BUILDREQ: build the request packet of slot D2 (D2 = slot * 18) for
| entity A1 in NRVars A3: LkUp (control 2, 1 tuple) to the node of
| confirmAddr for a ConfirmName, else LkUp to all nodes ($FF) or BrRq
| (control 1) to the bridge; tuple = our address and the NBP socket.  The
| WDS at +$76: header template +$91, 7 bytes from +$8A, the entity name.
| Called by NBP_SENDREQ, NBP_VBLTASK_BUILD.
| -------------------------------------------------------------------------
NBP_BUILDREQ:
        MOVEA.L 0x8(A3,D2.W),A0                 | A0 = the call of the slot
        DIVU.W  #0x12,D2                        | D2 = slot
        MOVE.B  0x2(A3,D2.W),0x8B(A3)           | nbpID = NBP ID of the slot
        MOVEQ.L #0x21,D3                        | control LkUp (2), 1 tuple
        CMPI.W  #0xFA,csCode(A0)                | ConfirmName (250)?
        BNE.B   NBP_BUILDREQ_BCAST              | no ->
        MOVE.L  0x22(A0),D2                     | D2 = confirmAddr (net.W, node.B, socket.B)
        LSR.W   #0x8,D2                         | D2.W = node, high word = network
        BRA.B   NBP_BUILDREQ_WDS                | ->
NBP_BUILDREQ_BCAST:
        MOVEQ.L #0x0,D2                         | network 0 ...
        ST.B    D2                              | ... node $FF (broadcast)
        MOVE.B  0x19(A2),D0                     | D0 = sysABridge
        BEQ.B   NBP_BUILDREQ_WDS                | no bridge ->
        MOVEQ.L #0x11,D3                        | bridge: control BrRq (1), 1 tuple
        MOVE.B  D0,D2                           | to the bridge
| WDS: header template, NBP header + tuple address, entity name
NBP_BUILDREQ_WDS:
        MOVE.L  A1,D0                           | D0 = entity name
        LEA.L   0x78(A3),A1                     | A1 -> WDS entry 1 pointer (+$78)
        LEA.L   0x91(A3),A0                     | A0 = header template (+$91, odd)
        MOVE.L  A0,(A1)+                        | entry 1 pointer
        MOVE.B  #0x2,0xD(A0)                    | +13 dest socket 2 (NIS)
        MOVE.B  D2,0xB(A0)                      | +11 dest node
        SWAP.W  D2                              | D2.W = network
        MOVE.W  D2,0x7(A0)                      | +7 dest network
        MOVE.B  #0x2,0xF(A0)                    | +15 DDP type 2 (NBP)
        MOVE.W  #0x7,(A1)+                      | entry 2 length = 7
        LEA.L   0x8A(A3),A0                     | A0 = NBP header (+$8A)
        MOVE.L  A0,(A1)+                        | entry 2 pointer
        MOVE.B  D3,(A0)                         | nbpControl/nbpTCount (nbpID set above)
        ADDQ.W  #0x2,A0                         | A0 -> tuple
        MOVE.W  0x1A(A2),(A0)+                  | tuple network = sysNetNum
        MOVE.B  (A2),(A0)+                      | tuple node = sysLAPAddr
        MOVE.B  0x74(A3),D1                     | D1 = NBP socket (replies come here)
        MOVE.B  D1,(A0)                         | tuple socket
        MOVEA.L D0,A0                           | A0 = entity name
        CLR.W   D2                              | D2.W = 0
        MOVE.B  (A0),D2                         | object length
        ADD.B   0x1(A0,D2.W),D2                 | + type length
        ADD.B   0x2(A0,D2.W),D2                 | + zone length
        ADDQ.B  #0x3,D2                         | + 3 length bytes
        MOVE.W  D2,(A1)+                        | entry 3 length
        MOVE.L  A0,(A1)+                        | entry 3 pointer = entity name
        CLR.W   (A1)                            | end of WDS
        RTS                                     | return from NBP_BUILDREQ

| -------------------------------------------------------------------------
| NBP_VBLTASK: retry timer of an NBP request (A0 = the VBL task of its
| slot): count - 1; at 0 NBP_VBLTASK_TIMEOUT, else send the request again
| after interval * 8 ticks.  The resend uses the shared WDS of NRVars, so
| it waits (one tick at a time) while .MPP is busy (drvrActive); it marks
| .MPP busy meanwhile and then starts a call queued in the meantime.
| (The "Nonres VBL task" of the System patches, $434232.)
| -------------------------------------------------------------------------
NBP_VBLTASK:
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        MOVEA.L (ABusVars_dce).W,A3             | A3 = .MPP DCE
        LEA.L   -0x4(A0),A1                     | A1 -> slot: call
        MOVE.L  A1,D2                           | D2 = its address
        MOVEA.L (A1),A1                         | A1 = the call
        SUBQ.B  #0x1,0x1D(A1)                   | count - 1
        BEQ.B   NBP_VBLTASK_TIMEOUT             | 0 -> no more retries
        BSET    #0x7,dCtlFlags+1(A3)            | .MPP busy? (and mark it busy)
        BEQ.B   NBP_VBLTASK_RESEND              | no -> resend now
| .MPP busy: try again at the next tick
NBP_VBLTASK_LATER:
        MOVE.W  #0x1,vblCount(A0)               | vblCount = 1
        ADDQ.B  #0x1,0x1D(A1)                   | undo the count
        RTS                                     | return
| resend: timer = interval * 8 ticks, rebuild the packet, DDPWrite
NBP_VBLTASK_RESEND:
        MOVEA.L 0x29E(A2),A3                    | A3 = NRVars
        CLR.W   D0                              | D0.W = 0
        MOVE.B  0x1C(A1),D0                     | interval
        LSL.W   #0x3,D0                         | * 8 ticks
        MOVE.W  D0,vblCount(A0)                 | vblCount
        MOVE.W  csCode(A1),D3                   | D3 = csCode of the call
        MOVEA.L 0x1E(A1),A1                     | A1 = entityPtr / ntQElPtr
        CMPI.W  #0xFD,D3                        | RegisterName (253)?
        BNE.B   NBP_VBLTASK_BUILD               | no ->
        ADDA.W  #0x9,A1                         | A1 -> entity name (ntEntity)
NBP_VBLTASK_BUILD:
        LEA.L   0x8(A3),A0                      | A0 -> slot 0
        SUB.L   A0,D2                           | D2 = slot * 18
        EXT.L   D2                              | (long)
        BSR.W   NBP_BUILDREQ                    | WDS and packet
        LEA.L   0x76(A3),A1                     | A1 = WDS (NRVars+$76)
        MOVEA.L 0x2A2(A2),A0                    | A0 = JDDPWrite
        CLR.B   D3                              | no checksum
        JSR     (A0)                            | DDPWRITE; resumes here when sent
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE
        BCLR    #0x7,dCtlFlags+1(A1)            | dCtlFlags: clear drvrActive
        BRA.W   NBP_STARTNEXT                   | start a queued call, if any
| no more retries; while .MPP still sends this very call's first request,
| wait
NBP_VBLTASK_TIMEOUT:
        BTST    #0x7,dCtlFlags+1(A3)            | .MPP busy?
        BEQ.B   NBP_TIMEOUT                     | no ->
        CMPA.L  dCtlQHead(A3),A1                | busy with this call (still queued)?
        BEQ.B   NBP_VBLTASK_LATER               | yes -> wait a tick
| NBP_TIMEOUT: retries used up - RegisterName: nobody has the name, enter
| it; ConfirmName: nbpNoConfirm; LookupName: done (noErr).  Nothing if the
| call has completed already (KillNBP).  The VBL task is not reinstalled.
NBP_TIMEOUT:
        MOVEA.L 0x29E(A2),A3                    | A3 = NRVars
        MOVE.W  csCode(A1),D0                   | D0 = csCode of the call
        MOVEA.L A1,A0                           | A0 = the call
        MOVEA.L 0x1E(A1),A1                     | A1 = ntQElPtr / entityPtr
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        TST.W   ioResult(A0)                    | still pending (ioResult > 0)?
        BLE.B   NBP_TIMEOUT_EXIT                | no -> nothing to do
        CMPI.W  #0xFD,D0                        | RegisterName (253)?
        BEQ.B   NBP_TIMEOUT_REGISTER            | yes -> enter the name
        CMPI.W  #0xFA,D0                        | ConfirmName (250)?
        BNE.B   NBP_TIMEOUT_NOERR               | no (LookupName) -> noErr
        MOVE.W  #-0x401,D0                      | nbpNoConfirm (-1025)
        BRA.B   NBP_TIMEOUT_DONE                | -> complete
NBP_TIMEOUT_REGISTER:
        BSR.W   NBP_ENTERNAME                   | enter the name
NBP_TIMEOUT_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
NBP_TIMEOUT_DONE:
        BSR.B   NBP_COMPLETE                    | complete the call
NBP_TIMEOUT_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return

| -------------------------------------------------------------------------
| NBP_COMPLETE: complete the active NBP call A0 with D0: free its slot,
| stop its retry timer (unless it has just run out: vblCount 0), set
| ioResult and call its ioCompletion -> D0 = 0; D0 = cbNotFound if A0
| is not an active NBP call.  NBP_COMPLETE_NOERR: with noErr.
| Called by: KILLNBP, NBP_TIMEOUT_DONE, NBP_LISTENER_NOTLKUP,
| NBP_LISTENER_DUPLICATE, NBP_LISTENER_DONE
| -------------------------------------------------------------------------
NBP_COMPLETE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
NBP_COMPLETE:
        MOVEA.L 0x29E(A2),A3                    | A3 = NRVars
        MOVEQ.L #0x5,D2                         | 6 request slots
NBP_COMPLETE_LOOP:
        TST.B   0x2(A3,D2.W)                    | slot active?
        DBNE.W  D2,NBP_COMPLETE_LOOP            | no -> next
        BEQ.B   NBP_COMPLETE_NOTFOUND           | no more active slots ->
        MOVE.W  D2,D3                           | D3 = slot
        MULU.W  #0x12,D3                        | * 18
        MOVE.L  0x8(A3,D3.W),D1                 | D1 = its call
        SUB.L   A0,D1                           | this one?
        AND.L   (Lo3Bytes).W,D1                 | (24-bit addresses)
        BNE.B   NBP_COMPLETE_NEXT               | no ->
        MOVE.W  D0,ioResult(A0)                 | ioResult = D0
        LEA.L   0xC(A3,D3.W),A1                 | A1 = VBL task of the slot
        TST.W   vblCount(A1)                    | still running?
        BEQ.B   NBP_COMPLETE_FREE               | no (ran out, removed by the VBL manager) ->
        EXG     A0,A1                           | A0 = VBL task
        MOVE.W  D0,D1                           | save D0
        _VRemove                                | stop the retry timer
        MOVE.W  D1,D0                           | restore D0
        MOVEA.L A1,A0                           | A0 = the call
NBP_COMPLETE_FREE:
        CLR.B   0x2(A3,D2.W)                    | slot free
        MOVE.L  ioCompletion(A0),D1             | D1 = ioCompletion
        BEQ.B   NBP_COMPLETE_EXIT               | none ->
        MOVEA.L D1,A1                           | A1 = completion routine
        TST.W   D0                              | condition codes = result
        JSR     (A1)                            | call the ioCompletion routine of the call
NBP_COMPLETE_EXIT:
        MOVEQ.L #0x0,D0                         | D0 = 0: found
        RTS                                     | return from NBP_COMPLETE
NBP_COMPLETE_NEXT:
        SUBQ.W  #0x1,D2                         | next slot
        BPL.B   NBP_COMPLETE_LOOP               | loop
NBP_COMPLETE_NOTFOUND:
        MOVE.W  #-0x44E,D0                      | cbNotFound (-1102)
        RTS                                     | return from NBP_COMPLETE

| -------------------------------------------------------------------------
| NBP_LISTENER_NOTLKUP: reply for a RegisterName (-> nbpDuplicate) or a
| ConfirmName (A5 = the call): newSocket = socket of the first tuple;
| noErr if it is the socket of confirmAddr, else nbpConfDiff
| -------------------------------------------------------------------------
NBP_LISTENER_NOTLKUP:
        MOVE.L  A5,D2                           | D2 = the call
        CMPI.W  #0xFD,csCode(A5)                | RegisterName (253)?
        BEQ.B   NBP_LISTENER_DUPLICATE          | yes -> nbpDuplicate
        MOVEQ.L #0x4,D3                         | 4 bytes: tuple net, node, socket
        JSR     0x2(A4)                         | ReadRest
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        MOVE.B  -(A3),D0                        | D0 = tuple socket
        MOVEA.L 0x29E(A2),A3                    | A3 = NRVars
        MOVEA.L D2,A0                           | A0 = the ConfirmName call
        MOVE.B  D0,0x26(A0)                     | newSocket
        CMP.B   0x25(A0),D0                     | socket of confirmAddr?
        BEQ.B   NBP_COMPLETE_NOERR              | yes -> noErr
        MOVE.W  #-0x402,D0                      | nbpConfDiff (-1026)
        BRA.W   NBP_COMPLETE                    | -> complete
| someone answered the verifying LkUp of a RegisterName - nbpDuplicate
NBP_LISTENER_DUPLICATE:
        JSR     0x2(A4)                         | ReadRest (D3 = 0: discard)
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        MOVEA.L D2,A0                           | A0 = the RegisterName call
        MOVE.W  #-0x403,D0                      | nbpDuplicate (-1027)
        BRA.W   NBP_COMPLETE                    | -> complete
| return to MPP
| Called by: NBP_LISTENER, NBP_LISTENER_NOTLKUP, NBP_LISTENER_DUPLICATE,
| NBP_LISTENER_COUNTED
NBP_LISTENER_EXIT:
        RTS                                     | return from NBP_LISTENER
| drop the packet
NBP_LISTENER_DISCARD:
        CLR.W   D3                              | buffer size 0
        JMP     0x2(A4)                         | ReadRest: discard, return to MPP

| -------------------------------------------------------------------------
| NBP_LISTENER: listener of the NBP socket - replies to our requests.
| Reads the NBP header; drops it unless its NBP ID belongs to an active
| request (A5 = that call).  LookupName: the tuples go straight into the
| return buffer; tuples already received (same address and enumerator)
| are removed, numGotten counted; the call ends at maxToGet or a full
| buffer.
| -------------------------------------------------------------------------
NBP_LISTENER:
        MOVEQ.L #0x2,D3                         | 2 bytes: control/count, NBP ID
        JSR     (A4)                            | ReadPacket
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        MOVEA.L 0x29E(A2),A5                    | A5 = NRVars
        LEA.L   0x8(A5),A5                      | A5 -> end of the NBP IDs (+$02..+$07)
        MOVEQ.L #0x5,D2                         | 6 request slots
        MOVE.B  -(A3),D0                        | D0 = nbpID
        BEQ.B   NBP_LISTENER_DISCARD            | 0 -> drop
NBP_LISTENER_IDLOOP:
        CMP.B   -(A5),D0                        | NBP ID of this slot?
        DBEQ.W  D2,NBP_LISTENER_IDLOOP          | no -> next
        BNE.B   NBP_LISTENER_DISCARD            | none -> drop
        SUBA.W  D2,A5                           | A5 -> NRVars+$02
        MULU.W  #0x12,D2                        | slot * 18
        ADDQ.W  #0x6,A5                         | A5 -> NRVars+$08 (slot 0)
        MOVEA.L 0x0(A5,D2.W),A5                 | A5 = the call of the slot
        MOVE.B  -(A3),D2                        | D2 = nbpControl/nbpTCount
        CMPI.W  #0xFB,csCode(A5)                | LookupName (251)?
        BNE.B   NBP_LISTENER_NOTLKUP            | no ->
| LookupName: read the tuples into the return buffer
        MOVEA.L (A5),A3                         | A3 = next free byte of the buffer (qLink)
        MOVE.W  0x12(A5),D3                     | D3 = bytes left
        MOVE.L  A5,-(SP)                        | save the call
        JSR     0x2(A4)                         | ReadRest
        MOVEA.L (SP)+,A1                        | A1 = the LookupName call
        BNE.B   NBP_LISTENER_EXIT               | error -> return
        SUBI.B  #0x30,D2                        | control must be 3 (LkUp-Reply)
        BLE.B   NBP_LISTENER_EXIT               | no tuples / other packet -> ignore
        CMPI.B  #0xF,D2                         | more than 15 tuples?
        BGT.B   NBP_LISTENER_EXIT               | yes -> ignore
        MOVE.L  A3,D1                           | D1 = end of the data read
        MOVEA.L 0x29E(A2),A3                    | A3 = NRVars
        CLR.W   D0                              | D0.W = 0
        TST.W   D3                              | truncated (D3 < 0)?
        BPL.B   NBP_LISTENER_DEDUP              | no: all D2 tuples complete
| truncated: count the complete tuples
        CLR.W   D2                              | D2 = complete tuples
        MOVEA.L (A1),A0                         | A0 = first new tuple
NBP_LISTENER_COUNTLOOP:
        ADDQ.W  #0x5,A0                         | skip address and enumerator
        CMP.L   A0,D1                           | past the end?
        BLE.B   NBP_LISTENER_COUNTED            | yes -> stop
        MOVE.B  (A0)+,D0                        | object length
        ADDA.W  D0,A0                           | skip the object
        CMP.L   A0,D1                           | past the end?
        BLE.B   NBP_LISTENER_COUNTED            | yes -> stop
        MOVE.B  (A0)+,D0                        | type length
        ADDA.W  D0,A0                           | skip the type
        CMP.L   A0,D1                           | past the end?
        BLE.B   NBP_LISTENER_COUNTED            | yes -> stop
        MOVE.B  (A0)+,D0                        | zone length
        ADDA.W  D0,A0                           | skip the zone
        CMP.L   A0,D1                           | past the end?
        BLT.B   NBP_LISTENER_COUNTED            | yes -> stop
        ADDQ.W  #0x1,D2                         | one more complete tuple
        BRA.B   NBP_LISTENER_COUNTLOOP          | next
| none complete: ignore the packet
NBP_LISTENER_COUNTED:
        TST.W   D2                              | complete tuples?
        BEQ.W   NBP_LISTENER_EXIT               | none -> ignore
| remove tuples already in the buffer (same address and enumerator)
NBP_LISTENER_DEDUP:
        MOVEM.L A2/A4-A6,-(SP)                  | save A2/A4-A6
        CLR.W   D1                              | D1 = new tuples kept
        MOVE.L  0x22(A1),D3                     | D3 = retBuffPtr (start of the buffer)
        MOVEA.L (A1),A5                         | A5 = first new tuple
        MOVEA.L A5,A6                           | A6 = where kept tuples go
NBP_LISTENER_DEDUPLOOP:
        MOVEA.L D3,A4                           | A4 = first old tuple
NBP_LISTENER_SCANLOOP:
        CMPA.L  (A1),A4                         | end of the old tuples?
        BEQ.B   NBP_LISTENER_KEEP               | yes: new one is unique ->
        MOVEA.L A4,A0                           | A0 = old tuple
        MOVEA.L A5,A2                           | A2 = new tuple
        CMPM.B  (A0)+,(A2)+                     | network high byte
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A2)+                     | network low byte
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A2)+                     | node
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A2)+                     | socket
        BNE.B   NBP_LISTENER_SCANNEXT           | differs ->
        CMPM.B  (A0)+,(A2)+                     | enumerator
        BEQ.B   NBP_LISTENER_DROP               | same: duplicate -> drop
NBP_LISTENER_SCANNEXT:
        ADDQ.W  #0x5,A4                         | skip address and enumerator
        MOVE.B  (A4),D0                         | object length
        ADD.B   0x1(A4,D0.W),D0                 | + type length
        ADD.B   0x2(A4,D0.W),D0                 | + zone length
        ADDQ.W  #0x3,D0                         | + 3 length bytes
        ADDA.W  D0,A4                           | next old tuple
        BRA.B   NBP_LISTENER_SCANLOOP           | loop
| keep the new tuple: move it down to A6 if tuples were dropped.
| Suspected bug: A1, the LookupName call, is also used as the _BlockMove
| destination; once a tuple has been moved down, the scan (CMPA.L (A1),
| A4) and the end (qLink, numGotten, bytes left at (A1)) work on the
| moved tuple instead of the call.  It happens when a reply packet holds
| a duplicate tuple before a new one.  (The Mac Plus driver kept this
| state in NRVars and was not affected.)
NBP_LISTENER_KEEP:
        MOVE.B  0x5(A5),D0                      | object length
        ADD.B   0x6(A5,D0.W),D0                 | + type length
        ADD.B   0x7(A5,D0.W),D0                 | + zone length
        ADDQ.W  #0x8,D0                         | + 5 + 3 = tuple size
        MOVEA.L A5,A0                           | A0 = source
        ADDA.W  D0,A5                           | A5 = next new tuple
        CMPA.L  A0,A6                           | already in place?
        BEQ.B   NBP_LISTENER_INPLACE            | yes ->
        MOVEA.L A6,A1                           | A1 = destination
        ADDA.W  D0,A6                           | advance it
        _BlockMove                              | move the tuple down
        BRA.B   NBP_LISTENER_COUNTNEW           | ->
| in place
NBP_LISTENER_INPLACE:
        MOVEA.L A5,A6                           | A6 = next free place
NBP_LISTENER_COUNTNEW:
        ADDQ.W  #0x1,D1                         | one more kept
NBP_LISTENER_NEXTTUPLE:
        SUBQ.B  #0x1,D2                         | tuples left
        BNE.B   NBP_LISTENER_DEDUPLOOP          | more ->
        MOVE.L  A6,(A1)                         | qLink = next free byte of the buffer
        SUBA.L  0x22(A1),A6                     | A6 = bytes used
        MOVE.W  0x26(A1),D0                     | retBuffSize
        SUB.W   A6,D0                           | - used = bytes left
        MOVEM.L (SP)+,A2/A4-A6                  | restore A2/A4-A6
        MOVEA.L A1,A0                           | A0 = the LookupName call
        ADD.W   0x2A(A1),D1                     | + numGotten
        MOVE.W  D1,0x2A(A1)                     | numGotten
        CMP.W   0x28(A1),D1                     | >= maxToGet?
        BPL.B   NBP_LISTENER_DONE               | yes -> complete
        MOVE.W  D0,0x12(A1)                     | +$12 = bytes left
        BNE.B   NBP_LISTENER_RTS                | room left -> wait for more
| complete the LookupName (noErr) unless .MPP is still sending its first
| request (the call is still at the head of the queue)
NBP_LISTENER_DONE:
        MOVEA.L (ABusVars_dce).W,A3             | A3 = .MPP DCE
        BTST    #0x7,dCtlFlags+1(A3)            | .MPP busy?
        BEQ.W   NBP_COMPLETE_NOERR              | no -> complete it, noErr
        CMPA.L  dCtlQHead(A3),A1                | busy with this call?
        BNE.W   NBP_COMPLETE_NOERR              | no -> complete it, noErr
NBP_LISTENER_RTS:
        RTS                                     | return to MPP (call still pending)
| duplicate - skip the new tuple (it is overwritten by the next kept one)
NBP_LISTENER_DROP:
        ADDQ.W  #0x5,A5                         | skip address and enumerator
        MOVE.B  (A5),D0                         | object length
        ADD.B   0x1(A5,D0.W),D0                 | + type length
        ADD.B   0x2(A5,D0.W),D0                 | + zone length
        ADDQ.W  #0x3,D0                         | + 3 length bytes
        ADDA.W  D0,A5                           | A5 = next new tuple
        BRA.B   NBP_LISTENER_NEXTTUPLE          | ->

| -------------------------------------------------------------------------
| LUCODE: lookup-reply code entry table (LookupPtr): +0 LookupReply, +2
| goodbye kiss, +4 NIS socket listener
| -------------------------------------------------------------------------
LUCODE:
        BRA.B   LUCODE_REPLY                    | +0: LookupReply -> NBP_LKUPREPLY
LUCODE_GOODBYE:
        BRA.B   NBP_DROPAPPLNAMES               | +2: goodbye kiss -> NBP_DROPAPPLNAMES
| NIS_LISTENER: +4 - listener of socket 2 (names information socket).
| Reads a received LkUp packet into the lookup-reply parameter block (at
| csParam) and issues the LookupReply call (csCode 242) to this driver;
| drops the packet while that block is busy, and ignores our own lookups
| unless SelfSend is on.
NIS_LISTENER:
        MOVEA.L 0x2AA(A2),A3                    | A3 -> csCode of the block (LUQElPtr)
        TST.W   (A3)+                           | busy (csCode set)?
        BNE.B   NIS_LISTENER_BUSY               | yes -> drop the packet
        MOVEQ.L #0x7C,D3                        | up to 124 bytes
        JSR     0x2(A4)                         | ReadRest into csParam
        BNE.B   NIS_LISTENER_EXIT               | error -> return
        MOVEA.L 0x2AA(A2),A0                    | A0 -> csCode of the block
        TST.B   0x2AE(A2)                       | SelfSend on?
        BNE.B   NIS_LISTENER_QUEUE              | yes: answer our own lookups too
        MOVE.B  0x6(A0),D0                      | D0 = node of the tuple (csParam+4)
        CMP.B   (A2),D0                         | our node?
        BNE.B   NIS_LISTENER_QUEUE              | no -> answer it
        MOVE.W  0x4(A0),D0                      | D0 = network of the tuple (csParam+2)
        CMP.W   0x1A(A2),D0                     | our network?
        BEQ.B   NIS_LISTENER_EXIT               | yes: our own lookup -> ignore
| queue the LookupReply call
NIS_LISTENER_QUEUE:
        MOVE.W  #0xF2,(A0)                      | csCode = 242 (LookupReply): block busy
        SUBA.W  #0x1A,A0                        | A0 = parameter block
        LEA.L   NIS_LUCOMPLETION(PC),A1         | A1 = completion routine
        MOVE.L  A1,ioCompletion(A0)             | ioCompletion
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE
        MOVE.W  dCtlRefNum(A1),ioRefNum(A0)     | ioRefNum = .MPP refNum
        _ControlAsync                           | queue it
NIS_LISTENER_EXIT:
        RTS                                     | return to MPP
| block in use - drop the packet
NIS_LISTENER_BUSY:
        CLR.W   D3                              | buffer size 0
        JMP     0x2(A4)                         | ReadRest: discard, return to MPP
| LUCODE_REPLY: -> NBP_LKUPREPLY
LUCODE_REPLY:
        BRA.B   NBP_LKUPREPLY                   | -> NBP_LKUPREPLY

| -------------------------------------------------------------------------
| NBP_DROPAPPLNAMES: goodbye kiss - unlink every names-table entry that
| lies in the application area: not in the system heap (below its end,
| SysZone^.bkLim) and below BufPtr (the memory above BufPtr, reserved by
| system code, is kept; the Mac Plus driver checked only the system heap)
| -------------------------------------------------------------------------
NBP_DROPAPPLNAMES:
        LEA.L   0x2A6(A2),A3                    | A3 -> NTQueueHd
        MOVEA.L (SysZone).W,A0                  | A0 = system heap zone (bkLim first)
NBP_DROPAPPLNAMES_LOOP:
        MOVE.L  (A3),D1                         | D1 = next entry
        BEQ.B   NBP_DROPAPPLNAMES_EXIT          | end ->
        AND.L   (Lo3Bytes).W,D1                 | 24-bit address
        MOVEA.L D1,A1                           | A1 = entry
        CMPA.L  (A0),A1                         | below the end of the system heap?
        BCS.B   NBP_DROPAPPLNAMES_KEEP          | yes -> keep it
        CMPA.L  (BufPtr).W,A1                   | at or above BufPtr (reserved high memory)?
        BCC.B   NBP_DROPAPPLNAMES_KEEP          | yes -> keep it
        MOVE.L  (A1),(A3)                       | no: unlink it
        BRA.B   NBP_DROPAPPLNAMES_LOOP          | next
| keep the entry, go on from it
NBP_DROPAPPLNAMES_KEEP:
        MOVEA.L A1,A3                           | A3 = entry (its link field)
        BRA.B   NBP_DROPAPPLNAMES_LOOP          | next
| end of the names table
NBP_DROPAPPLNAMES_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| NBP_LKUPREPLY: LookupReply call, A0 = the lookup-reply block with the
| LkUp packet at csParam (+$1C control, +$1D NBP ID, +$1E tuple of the
| requester, +$23 entity name).  Collects the names-table entries whose
| object and type match ('=' matches all; the zone is not checked) and
| answers with LkUp-Reply packets (15 tuples / 584 bytes at most each)
| from socket 2 to the requester's socket.
| -------------------------------------------------------------------------
NBP_LKUPREPLY:
        MOVE.L  0x2A6(A2),D2                    | D2 = first names-table entry
        BEQ.W   NBP_LKUPREPLY_IODONE            | none -> done
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  0x1C(A2),SR                     | SR = vSCCEnable
        MOVEM.L A2/A4-A5,-(SP)                  | save registers
        MOVEA.L A0,A4                           | A4 = lookup-reply block
        MOVE.W  NBP_CMPSTRINGTRAP(PC),D0        | D0 = _CmpString trap word ($A03C)
        _GetTrapAddress                         | A0 = its routine
        MOVEA.L A0,A2                           | A2 = CmpString routine (for NBP_CMPNAME)
        CLR.W   D3                              | D3 = matches
| scan the names table; matching entries are pushed on the stack
NBP_LKUPREPLY_LOOP:
        MOVEA.L D2,A3                           | A3 = entry
        ADDA.W  #0x9,A3                         | A3 -> its entity name (ntEntity)
        LEA.L   0x23(A4),A5                     | A5 -> requested entity name
        MOVEA.L A3,A1                           | A1 = entry object
        MOVEA.L A5,A0                           | A0 = requested object
        CMPI.B  #0x3D,0x1(A5)                   | requested object starts with '='?
        BEQ.B   NBP_LKUPREPLY_TYPE              | yes: matches all ->
        BSR.W   NBP_CMPNAME                     | objects equal?
        BNE.B   NBP_LKUPREPLY_NEXT              | no -> next entry
| object matches: compare the types
NBP_LKUPREPLY_TYPE:
        CLR.W   D0                              | D0.W = 0
        MOVE.B  (A5)+,D0                        | length of the requested object
        ADDA.W  D0,A5                           | A5 -> requested type
        MOVEA.L A3,A1                           | A1 -> entry object
        MOVE.B  (A1)+,D0                        | its length
        ADDA.W  D0,A1                           | A1 -> entry type
        MOVEA.L A5,A0                           | A0 = requested type
        CMPI.B  #0x3D,0x1(A5)                   | requested type starts with '='?
        BEQ.B   NBP_LKUPREPLY_MATCH             | yes: matches all ->
        BSR.W   NBP_CMPNAME                     | types equal?
        BNE.B   NBP_LKUPREPLY_NEXT              | no -> next entry
| match: remember the entity
NBP_LKUPREPLY_MATCH:
        MOVE.L  A3,-(SP)                        | push the entity pointer
        ADDQ.W  #0x1,D3                         | count it
| next entry
NBP_LKUPREPLY_NEXT:
        MOVE.L  -0x9(A3),D2                     | D2 = ntLink
        BNE.B   NBP_LKUPREPLY_LOOP              | more ->
        TST.W   D3                              | any match?
        BEQ.W   NBP_LKUPREPLY_DONE              | no -> done
| DDP header template at +$1F (odd) to the requester's socket, WDS at +$30
        LEA.L   0x1F(A4),A1                     | A1 = header template
        LEA.L   0x1E(A4),A5                     | A5 -> requester tuple address
        MOVE.W  (A5)+,0x7(A1)                   | +7 dest network
        MOVE.B  (A5)+,0xB(A1)                   | +11 dest node
        MOVE.B  (A5)+,0xD(A1)                   | +13 dest socket
        MOVE.B  #0x2,0xF(A1)                    | +15 DDP type 2 (NBP)
        MOVE.L  A1,0x32(A4)                     | WDS entry 1 pointer
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables again
| one LkUp-Reply packet
NBP_LKUPREPLY_PACKET:
        MOVE.B  0x1E(A4),0x26(A4)               | restore the dest network high byte (lost by a short header)
        CLR.W   D2                              | D2 = bytes in this packet
        CLR.W   D1                              | D1 = tuples in this packet
        LEA.L   0x36(A4),A3                     | A3 -> WDS entry 2
        LEA.L   0x1C(A4),A1                     | A1 = NBP header (+$1C control/count, +$1D NBP ID)
        MOVE.W  #0x2,(A3)+                      | entry 2 length = 2
        MOVE.L  A1,(A3)+                        | entry 2 pointer = NBP header
| one WDS entry per tuple, straight from the names-table entry
NBP_LKUPREPLY_TUPLE:
        MOVEA.L (SP),A5                         | A5 = next matching entity
        CLR.W   D0                              | D0.W = 0
        MOVE.B  (A5),D0                         | object length
        ADD.B   0x1(A5,D0.W),D0                 | + type length
        MOVE.B  #0x1,0x2(A5,D0.W)               | zone length = 1 ...
        MOVE.B  #0x2A,0x3(A5,D0.W)              | ... zone = "*"
        ADDI.W  #0x9,D0                         | tuple size: + address, enumerator, 3 lengths, zone
        ADD.W   D0,D2                           | add to the packet size
        CMPI.W  #0x248,D2                       | 584 bytes or more?
        BGE.B   NBP_LKUPREPLY_SEND              | yes -> send without it
        ADDQ.W  #0x4,SP                         | pop the entity
        MOVE.W  D0,(A3)+                        | WDS entry length = tuple size
        SUBQ.W  #0x5,A5                         | A5 -> tuple (ntTuple)
        MOVE.L  A5,(A3)+                        | WDS entry pointer
        MOVE.W  0x1A(A2),(A5)                   | tuple network = sysNetNum
        ADDQ.W  #0x1,D1                         | one more tuple
        SUBQ.W  #0x1,D3                         | one match less
        BEQ.B   NBP_LKUPREPLY_SEND              | none left -> send
        CMPI.W  #0xF,D1                         | 15 tuples (tupleMax)?
        BNE.B   NBP_LKUPREPLY_TUPLE             | no -> add the next
| send the packet and wait for the write
NBP_LKUPREPLY_SEND:
        CLR.W   (A3)+                           | end of WDS
        ORI.W   #0x30,D1                        | control 3 (LkUp-Reply), tuple count
        MOVE.B  D1,(A1)                         | nbpControl/nbpTCount
        MOVEA.W D3,A5                           | A5 = matches left
        CLR.B   0x2F(A4)                        | write-done flag = 0
        BSR.B   NBP_SENDREPLY                   | DDPWrite from socket 2
NBP_LKUPREPLY_WAIT:
        TST.B   0x2F(A4)                        | written?
        BEQ.B   NBP_LKUPREPLY_WAIT              | no -> wait
        MOVE.W  A5,D3                           | D3 = matches left
        BNE.B   NBP_LKUPREPLY_PACKET            | more -> next packet
| done
NBP_LKUPREPLY_DONE:
        MOVEM.L (SP)+,A2/A4-A5                  | restore registers
        MOVE.W  (SP)+,SR                        | restore SR
| NBP_LKUPREPLY_IODONE: complete the LookupReply call (its completion
| routine frees the block)
NBP_LKUPREPLY_IODONE:
        MOVEA.L (JIODone).W,A0                  | IODone vector
        MOVEA.L (ABusVars_dce).W,A1             | A1 = .MPP DCE
        MOVEQ.L #0x0,D0                         | noErr
        JMP     (A0)                            | -> IODone

| -------------------------------------------------------------------------
| NBP_SENDREPLY: DDPWrite the WDS at +$30 of the lookup-reply block (A4)
| from socket 2 (NIS), no checksum; sets the write-done flag (+$2F)
| when the write has finished
| -------------------------------------------------------------------------
NBP_SENDREPLY:
        MOVEQ.L #0x2,D1                         | D1 = source socket 2 (NIS)
        LEA.L   0x30(A4),A1                     | A1 = WDS
        MOVEA.L 0x2A2(A2),A0                    | A0 = JDDPWrite
        CLR.B   D3                              | no checksum
        JSR     (A0)                            | DDPWRITE; resumes here when done
        MOVEA.L 0x2AA(A2),A0                    | A0 -> csCode of the block
        ST.B    0x15(A0)                        | write-done flag (+$2F)
        RTS                                     | return

| NBP_CMPSTRINGTRAP - the _CmpString trap word ($A03C), for _GetTrapAddress
NBP_CMPSTRINGTRAP:
        .short  0xA03C                          | _CmpString
| NBP_CMPNAME: compare the Pascal strings at A0 and A1 with the CmpString
| routine in A2 (A0/A1 -> text, D0 = lengths) -> EQ if equal
| (case-insensitive)
NBP_CMPNAME:
        MOVEQ.L #0x0,D0                         | D0 = 0
        MOVE.B  (A0)+,D0                        | length of string A0
        SWAP.W  D0                              | to the high word
        MOVE.B  (A1)+,D0                        | length of string A1
        JSR     (A2)                            | CmpString routine (_GetTrapAddress): D0 = 0 if equal
        TST.W   D0                              | EQ = equal
        RTS                                     | return from NBP_CMPNAME

| -------------------------------------------------------------------------
| NIS_LUCOMPLETION: ioCompletion of the LookupReply call - csCode = 0
| (the lookup-reply block is free again)
| -------------------------------------------------------------------------
NIS_LUCOMPLETION:
        CLR.W   csCode(A0)                      | csCode = 0: block free
        RTS                                     | return

