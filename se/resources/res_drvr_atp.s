| =========================================================================
| DRVR 10 .ATP -- AppleTalk Transaction Protocol driver (SE ROM, version 46)
| =========================================================================
| ROM offsets +0x324A2..+0x33121: the 8-byte ROM resource header and the
| driver body from +0x324AA (MacSEROM.lst: _DRVR_10_.ATP).  The .MPP Open
| opens it (unit 10, refNum -11), the .MPP Close closes it.
|
| ATP on top of DDP: every packet goes out with a WriteDDP call to .MPP
| (ATP_MPPCALL: an async _Control on one of five CBs; the BSR to it returns
| to the caller's caller at once and execution resumes after the BSR when
| .MPP completes the call), every packet comes in through the DDP socket
| listeners of the ATP sockets.  This is the "new calls" release of the
| AppleTalk drivers (Inside Macintosh V-508..519; the Open stores version 46
| in dCtlQueue+1, the .MPP 48 = NCVersion).  New against the Mac Plus
| driver (version 19, src/plus/resources/res_drvr_atp.s):
|   - NSendRequest (248): a request sent through an open responding socket
|     instead of a private socket; several may be pending on a socket (at
|     most ATPVars+$4CA, computed from TimeDBRA by the Open: 9 on a 68000
|     ROM before the SE's, 14 on the SE, 62 on a Mac II -- IM V-519).  Its
|     retry timer is the intBuff byte of the parameter block; its responses
|     arrive at the responding socket (ATP_LISTENER_COMMON).
|   - KillGetReq (257) and KillSendReq (258) abort one GetRequest or one
|     (N)SendRequest (aKillQEl) with reqAborted.
|   - More resources (IM V-518): 12 SendRequests, 32 responding sockets, 16
|     RspCBs, 5 CBs.  Each responding socket has its own listener entry
|     (ATP_LISTENER + 4 * slot); the private sockets of SendRequests have
|     their own listener (ATP_REQLISTENER).
|   - The ATP hook of the AppleTalk Global Block (AGBHandle^ +8, atpHook)
|     is called at every control call on ROMs >= $76 (sMgrROM: the SE).
|   - ATP_GETCB claims a CB with interrupts off; ATP_DETACHREQ starts the
|     next queued call with a BSR (NSendRequest goes on after it); a
|     SendRequest whose last response came while no CB was free waits for
|     that response again instead of being lost; the TRel carries zero user
|     bytes; the listeners check the DDP type (3).
|   - No goodbye-kiss handling (a negative csCode gives controlErr).
| Unchanged: OpenATPSkt, CloseATPSkt, GetRequest, SendResponse,
| AddResponse, SendRequest, RelTCB, RelRspCB, the TReq retransmission and
| the exactly-once RspCBs with their 30-second release timer.
|
| Control calls (csCode - 248 indexes E_ATP_CONTROL_DISPATCH_TBL; csCodes
| from System 7.1 AppleTalk.a, parameter blocks IM II-315..319, V-516..518):
|   248 NSendRequest  NSENDREQUEST  request through an open socket
|   249 RelRspCB      RELRSPCB      cancel an exactly-once SendResponse
|   250 CloseATPSkt   CLOSEATPSKT   close a responding socket
|   251 AddResponse   ADDRESPONSE   send one more response packet
|   252 SendResponse  SENDRESPONSE  answer a request (BDS of packets)
|   253 GetRequest    GETREQUEST    wait for a request on a socket
|   254 OpenATPSkt    OPENATPSKT    open a responding socket
|   255 SendRequest   SENDREQUEST   send a request, collect responses
|   256 RelTCB        RELTCB        abort a SendRequest (reqAborted)
|   257 KillGetReq    KILLGETREQ    abort a GetRequest (reqAborted)
|   258 KillSendReq   KILLSENDREQ   abort a (N)SendRequest (reqAborted)
| 248-253 need an open responding socket in atpSocket (else badATPSkt).
| csCode 1 (killCode) returns at once.  Calls that cannot complete at once
| (GetRequest, SendRequest, NSendRequest, an exactly-once SendResponse) are
| taken off the driver's I/O queue by ATP_DETACHREQ and completed later by
| ATP_COMPLETE.
|
| ATP header (atpHdSz = 8): +0 atpControl (bits 7-6 function: $40 TReq,
| $80 TResp, $C0 TRel; bit 5 XO, bit 4 EOM, bit 3 STS), +1 atpBitmap
| (TReq) / atpRespNo (TResp), +2 atpTransID, +4 atpUserData.
| Parameter block (csParam = +$1C): +$12 userData, +$16 reqTID, +$1C
| atpSocket / currBitmap, +$1D atpFlags (bit 5 XO, 4 EOM, 3 STS, 1
| tidValid, 0 sendCHK), +$1E addrBlock, +$22 reqLength, +$24 reqPointer,
| +$28 bdsPointer, +$2C numOfBuffs / bitMap / rspNum (byte) or aKillQEl
| (long), +$2D timeOutVal / bdsSize, +$2E numOfResps (byte) / transID
| (word), +$2F retryCount, +$30 intBuff (NSendRequest).  BDS entry (12
| bytes): +0 bdsBuffSz, +2 bdsBuffAdr, +6 bdsDataSz, +8 bdsUserData.
|
| ATPVars ($4CC bytes, system heap; pointer in the MPP variable atpVars =
| ABusVars+$1E, high byte = flag set by the .MPP Close):
|   +$000 4 bytes   12, 32, 16, 5: number of request slots, responding
|                   sockets, RspCBs and CBs (set by the Open only)
|   +$004 12 bytes  request slots: socket of each SendRequest (0 = free)
|   +$010 12 longs  request slots: SendRequest parameter block
|   +$040 12 bytes  request slots: retry timer in seconds (0 = stopped)
|   +$04C 32 bytes  responding sockets (OpenATPSkt; 0 = free)
|   +$06C 32 longs  responding sockets: queue of waiting GetRequests
|   +$0EC 32 longs  responding sockets: queue of pending NSendRequests
|   +$16C 32 longs  responding sockets: addrBlock filter (0 = any)
|   +$1EC 16 x 12   RspCBs (exactly-once responses): +0 socket (0 =
|                   free), +1 release timer (seconds), +2 requester
|                   address, +6 TID, +8 SendResponse (0 = none yet)
|   +$2AC long      .ATP DCE
|   +$2B0 word      next transaction ID (seeded from Ticks)
|   +$2B2 14 bytes  VBL task (ATP_VBLTASK, every 60 ticks)
|   +$2C0 5 x $68   CBs for the calls to .MPP: +$00 IOParam (ioCompletion
|                   = ATP_MPPDONE, ioRefNum = .MPP refNum while in use, 0
|                   = free), +$1C socket, +$1D checksumFlag, +$1E
|                   listener / wdsPointer, +$22 saved D1-D3/A0-A1, +$36
|                   address to resume at, +$3A WDS (header entry -> +$4F,
|                   8 bytes -> +$60, data entry, 0), +$4F DDP header
|                   template, +$60 ATP header
|   +$4C8 byte      bit 7: ATP_VBLTASK running (re-entry guard)
|   +$4C9 byte      TimeDBRA/100 (about the CPU clock in MHz), 5 on ROMs
|                   before the SE's (no TimeDBRA)
|   +$4CA word      most NSendRequests per socket: (+$4C9 * 120 - 142) / 48
| Apple calls the request slots the TCB table (TSktNum = +$04, TQElPtr =
| +$10; TCBE = 12 entries) in the System patch PMAB301 below.
|
| Apple's names: the System 6/7 ROM patches (System 7.1 PatchSEROM.a,
| PatchPlusROM.a) name some ROM routines: SndRqInit (ATP_SNDRQINIT),
| ReadResp (ATP_READRESP), ATPIgnore (ATP_LISTENER_DISCARD), JATPEx2
| (ADDRESPONSE_EXIT) and, for the Mac Plus driver, GetDataArea (ATP_GETCB),
| CheckTime (ATP_VBLTASK), ATPExit (ATP_DONE), NoBuffs
| (SENDRESPONSE_SENT).  The other labels keep the names of the Mac Plus
| tree.  Patch PMAB301 (11/1987) fixes a bug of this driver: see
| ATP_READRESP.
|
| Sources: Inside Macintosh II-261..330 ("The AppleTalk Manager"; socket
| listeners II-325..329) and V-508..522 (new calls, resource table V-518),
| Inside Macintosh: Networking "ATP" (1994), System 7.1 AppleTalk.a and
| ATalkPrivateEQU.a (csCodes, AGB, sMgrROM), PatchSEROM.a and
| PatchPlusROM.a (ROM patches, Apple's names), MPW 1.0 ATalkEqu.a, the Mac
| Plus driver for the shared code.
| =========================================================================

Resource_DRVR_000A_DotATP:
| ROM resource header of DRVR 10 (8 bytes)
Resource_DRVR_000A_DotATP_Header:
    ROM_RESOURCE DRVR_10                        | 8-byte resource header (include/romrsrc.inc)
| -------------------------------------------------------------------------
| DRVR header (Inside Macintosh II-188): flags, delay, event mask, menu,
| the offsets of the five entry points from the start of the header, the
| driver name; then the version byte (46, also stored by the Open) and 0.
| -------------------------------------------------------------------------
Driver_ATP:
| MacSEROM.lst name of the driver resource
_DRVR_10_.ATP:
        .short  0x4400                          | drvrFlags: dNeedLock, dCtlEnable
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no desk accessory events
        .short  0x0000                          | drvrMenu: no menu
        .short  E_ATP_Open-Driver_ATP           | drvrOpen: $001A
        .short  E_ATP_PrimeStatus-Driver_ATP    | drvrPrime: $022C (not supported)
        .short  E_ATP_Control-Driver_ATP        | drvrCtl: $0098
        .short  E_ATP_PrimeStatus-Driver_ATP    | drvrStatus: $022C (not supported)
        .short  E_ATP_Close-Driver_ATP          | drvrClose: $013A
        .byte   4                               | drvrName: length byte
        .ascii  ".ATP"                          | drvrName: driver name
        .byte   0x20                            | pad byte
        .byte   0x2E,0x00                       | version 46 (as set by E_ATP_Open), 0

| -------------------------------------------------------------------------
| E_ATP_Open: needs an open .MPP (ABusVars set); allocates ATPVars, stores
| the resource counts, the DCE, the first TID and the NSendRequest limit
| per socket, and installs the once-per-second VBL task.  A1 = .ATP DCE.
| Called by the .MPP Open (_Open of ".ATP").  Returns D0 = the _VInstall
| result or the _NewPtr error (memFullErr); D0 is not set when .MPP is
| not open or .ATP is already open.
| -------------------------------------------------------------------------
E_ATP_Open:
        MOVEA.L (ABusVars).W,A3                 | A3 = MPP variables
        MOVE.L  A3,D1                           | .MPP open?
        BEQ.B   E_ATP_OPEN_EXIT                 | no -> return
        TST.L   0x1E(A3)                        | atpVars already set?
        BNE.B   E_ATP_OPEN_EXIT                 | yes, .ATP already open -> return
| allocate ATPVars
        MOVE.W  #0x4CC,D0                       | $4CC = 1228 bytes
        _NewPtrSysClear                         | zeroed block in the system heap
        BNE.B   E_ATP_OPEN_EXIT                 | out of memory -> return
| initialize
        BSET    #0x4,(PortBUse)                 | atpLoadedBit (4): .ATP open
        MOVE.L  A0,0x1E(A3)                     | atpVars = ATPVars
        CLR.B   0x1E(A3)                        | clear its high (flag) byte
        MOVE.B  #0x2E,dCtlQueue+1(A1)           | dCtlQueue+1: driver version 46
        MOVE.W  #0xC20,(A0)                     | +0 = 12 request slots, +1 = 32 responding sockets
        MOVE.W  #0x1005,0x2(A0)                 | +2 = 16 RspCBs, +3 = 5 CBs
| DCE pointer and TID seed in ATPVars
        LEA.L   0x2AC(A0),A2                    | A2 -> ATPVars+$2AC
        MOVE.L  A1,(A2)+                        | +$2AC = .ATP DCE
        MOVE.W  (Ticks_LoWord).W,(A2)+          | +$2B0 = first transaction ID (from Ticks)
| speed factor: TimeDBRA/100 (DBRA loops per 10 us, about the clock in
| MHz) on ROMs from the SE's on, else 5
        MOVEQ.L #0x5,D0                         | default 5
        MOVEA.L (ROMBase).W,A3                  | A3 = ROM base
        CMPI.B  #0x76,0x9(A3)                   | ROM version >= $76 (sMgrROM: SE or later)?
        BLT.B   E_ATP_OPEN_SPEED                | no -> keep 5
        MOVE.W  (TimeDBRA).W,D0                 | D0 = DBRA loops per millisecond
        DIVU.W  #0x64,D0                        | / 100
| NSendRequest limit per socket = (factor * 120 - 142) / 48: 9 for 5, 14
| for 7 (SE), 62 for 26 (Mac II), as listed in IM V-519
E_ATP_OPEN_SPEED:
        MOVE.B  D0,0x4C9(A0)                    | +$4C9 = speed factor
        MULU.W  #0x78,D0                        | * 120
        SUBI.W  #0x8E,D0                        | - 142
        DIVU.W  #0x30,D0                        | / 48
        MOVE.W  D0,0x4CA(A0)                    | +$4CA = most NSendRequests per socket (quotient)
| VBL task at +$2B2
        MOVEA.L A2,A0                           | A0 = VBL task at +$2B2
        ADDQ.W  #0x4,A2                         | skip qLink
        MOVE.W  #0x1,(A2)+                      | qType = vType (1)
        LEA.L   ATP_VBLTASK(PC),A1              | A1 = ATP_VBLTASK
        MOVE.L  A1,(A2)+                        | vblAddr
        MOVE.W  #0x3C,(A2)+                     | vblCount = 60 ticks (1 second)
        _VInstall                               | install the VBL task
E_ATP_OPEN_EXIT:
        RTS                                     | return from E_ATP_Open

| -------------------------------------------------------------------------
| E_ATP_Control: A0 = parameter block, A1 = .ATP DCE.  Calls the ATP hook
| of the AppleTalk Global Block (ROMs >= $76), then dispatches csCode
| 248..258 through E_ATP_CONTROL_DISPATCH_TBL with A2 = ATPVars, D1.B =
| atpSocket, D2 = the slot (0..31) of the responding socket atpSocket
| (248..253; else (csCode - 254) * 2), D3 = addrBlock, and atpFlags
| masked to its flag bits.  The handlers end in IODone
| (ATP_DONE and friends) or leave the call pending (ATP_DETACHREQ).
| Also called by ATP_DETACHREQ for the next queued call.
| -------------------------------------------------------------------------
E_ATP_Control:
        MOVEA.L (ROMBase).W,A2                  | A2 = ROM base
        CMPI.B  #0x76,0x9(A2)                   | ROM version >= $76 (AGB pointer in low memory)?
        BLT.B   E_ATP_CONTROL_NOHOOK            | no ->
        MOVEA.L (AGBHandle).W,A2                | A2 = AGBHandle (AppleTalk Global Block)
        MOVE.L  A2,D3                           | -1 = no AGB?
        ADDQ.L  #0x1,D3                         | ...
        BEQ.B   E_ATP_CONTROL_NOHOOK            | yes ->
        MOVEA.L (A2),A2                         | A2 = AGB
        MOVE.L  0x8(A2),D3                      | D3 = atpHook (AGB+8)
        BEQ.B   E_ATP_CONTROL_NOHOOK            | none ->
        MOVEA.L D3,A2                           | A2 = hook routine
        JSR     (A2)                            | call the ATP patch hook (A0 = parameter block)
E_ATP_CONTROL_NOHOOK:
        TST.L   (ABusVars).W                    | .MPP open?
        BNE.B   E_ATP_CONTROL_CSCODE            | yes ->
        MOVEQ.L #-0x11,D0                       | controlErr (-17)
E_ATP_CONTROL_IODONE:
        BRA.W   ATP_DONE_A1                     | -> IODone with D0
| dispatch on csCode
E_ATP_CONTROL_CSCODE:
        MOVE.W  csCode(A0),D2                   | D2 = csCode
        SUBQ.W  #0x1,D2                         | csCode 1 (killCode)?
        BNE.B   E_ATP_CONTROL_RANGE             | no ->
        RTS                                     | KillIO: nothing to cancel, return
| csCode must be 248..258
E_ATP_CONTROL_RANGE:
        MOVEQ.L #-0x11,D0                       | controlErr (-17) if out of range
        SUBI.W  #0xF7,D2                        | D2 = csCode - 248 (after the -1 above)
        BLT.B   E_ATP_CONTROL_IODONE            | < 248 (or negative) -> controlErr
        CMPI.W  #0xA,D2                         | > 258?
        BGT.B   E_ATP_CONTROL_IODONE            | yes -> controlErr
| handler address from the dispatch table
        ADD.W   D2,D2                           | word index
        LEA.L   E_ATP_CONTROL_DISPATCH_TBL(PC),A3 | A3 = dispatch table
        ADDA.W  D2,A3                           | A3 -> entry
        MOVEA.W (A3),A3                         | offset from the driver start
        LEA.L   Driver_ATP(PC),A2               | A2 = driver start
        ADDA.L  A2,A3                           | A3 = handler
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        MOVEA.L 0x1E(A2),A2                     | A2 = ATPVars (atpVars)
        MOVE.B  csParam(A0),D1                  | D1 = atpSocket
        SUBI.W  #0xC,D2                         | csCode >= 254 (OpenATPSkt .. KillSendReq)?
        BPL.B   E_ATP_CONTROL_JUMP              | yes -> no open socket needed
| 248..253: atpSocket must be an open responding socket
        MOVE.W  #-0x44B,D0                      | badATPSkt (-1099)
        TST.B   D1                              | atpSocket = 0?
        BEQ.W   ATP_DONE                        | yes -> IODone (badATPSkt)
        MOVEQ.L #0x1F,D2                        | 32 responding sockets
E_ATP_CONTROL_SKTLOOP:
        CMP.B   0x4C(A2,D2.W),D1                | this responding socket?
        DBEQ.W  D2,E_ATP_CONTROL_SKTLOOP        | no -> next
        BNE.W   ATP_DONE                        | not open -> IODone (badATPSkt)
E_ATP_CONTROL_JUMP:
        MOVE.L  0x1E(A0),D3                     | D3 = addrBlock (net.W, node.B, socket.B)
        ANDI.B  #0x3F,0x1D(A0)                  | atpFlags: clear bits 7-6 (FlagMask)
        JMP     (A3)                            | -> handler (from E_ATP_CONTROL_DISPATCH_TBL)

| E_ATP_CONTROL_DISPATCH_TBL - csCode 248..258, offsets from Driver_ATP
E_ATP_CONTROL_DISPATCH_TBL:
        .short  NSENDREQUEST-Driver_ATP         | 248 NSendRequest ($04A8)
        .short  RELRSPCB-Driver_ATP             | 249 RelRspCB ($0812)
        .short  CLOSEATPSKT-Driver_ATP          | 250 CloseATPSkt ($01F2)
        .short  ADDRESPONSE-Driver_ATP          | 251 AddResponse ($03A2)
        .short  SENDRESPONSE-Driver_ATP         | 252 SendResponse ($02D4)
        .short  GETREQUEST-Driver_ATP           | 253 GetRequest ($0234)
        .short  OPENATPSKT-Driver_ATP           | 254 OpenATPSkt ($019C)
        .short  SENDREQUEST-Driver_ATP          | 255 SendRequest ($0436)
        .short  RELTCB-Driver_ATP               | 256 RelTCB ($07BA)
        .short  KILLGETREQ-Driver_ATP           | 257 KillGetReq ($0286)
        .short  KILLSENDREQ-Driver_ATP          | 258 KillSendReq ($0776)

| -------------------------------------------------------------------------
| E_ATP_Close: waits for a free CB, closes the sockets of all request
| slots and responding sockets (CloseSkt calls to .MPP), then removes the
| VBL task and frees ATPVars.  When the .MPP Close has set the flag byte
| of atpVars (negative), .MPP can no longer be called: only the last step.
| Pending calls are not completed.  Called by the .MPP Close (_Close).
| -------------------------------------------------------------------------
E_ATP_Close:
        MOVEA.L (ABusVars).W,A1                 | A1 = MPP variables
        MOVE.L  A1,D0                           | .MPP open?
        BEQ.B   E_ATP_CLOSE_EXIT                | no -> return
        MOVEA.L 0x1E(A1),A2                     | A2 = ATPVars (atpVars)
        MOVE.L  A2,D0                           | flag byte set (.MPP closing)?
        BMI.B   E_ATP_CLOSE_FREE                | yes -> only free the memory
| wait until a CB is free (outstanding .MPP calls complete meanwhile)
E_ATP_CLOSE_WAITCB:
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.B   E_ATP_CLOSE_WAITCB              | none free -> try again
| close the sockets of the request slots
        MOVEQ.L #0xC,D2                         | 12 request slots
        LEA.L   0x4(A2),A0                      | A0 = request sockets (ATPVars+$04)
        BSR.B   ATP_CLOSESOCKETS                | CloseSkt each of them
E_ATP_CLOSE_WAITREQ:
        TST.W   ioResult(A3)                    | last CloseSkt still in progress?
        BGT.B   E_ATP_CLOSE_WAITREQ             | yes -> wait
| close the responding sockets
        MOVEQ.L #0x20,D2                        | 32 responding sockets
        LEA.L   0x4C(A2),A0                     | A0 = responding sockets (ATPVars+$4C)
        BSR.B   ATP_CLOSESOCKETS                | CloseSkt each of them
E_ATP_CLOSE_WAITRSP:
        TST.W   ioResult(A3)                    | last CloseSkt still in progress?
        BGT.B   E_ATP_CLOSE_WAITRSP             | yes -> wait
| remove the VBL task, free ATPVars
E_ATP_CLOSE_FREE:
        PEA.L   0x2B2(A2)                       | VBL task at ATPVars+$2B2
        CLR.B   (SP)                            | without the flag byte
        MOVEA.L (SP)+,A0                        | A0 = VBL task
        _VRemove                                | remove it
        MOVEA.L A2,A0                           | A0 = ATPVars
        _DisposePtr                             | free it
        CLR.L   0x1E(A1)                        | atpVars = nil
        BCLR    #0x4,(PortBUse)                 | atpLoadedBit (4): .ATP closed
E_ATP_CLOSE_EXIT:
        RTS                                     | return from E_ATP_Close

| -------------------------------------------------------------------------
| ATP_CLOSESOCKETS: CloseSkt (via .MPP) every nonzero socket of a table.
| A0 = socket table, D2 = entries, A3 = claimed CB (ioResult cleared
| first, so the caller's wait loop ends when nothing was closed).  Each
| CloseSkt resumes the loop when it completes.  Called by E_ATP_Close.
| -------------------------------------------------------------------------
ATP_CLOSESOCKETS:
        CLR.W   ioResult(A3)                    | ioResult = 0 (nothing in progress)
ATP_CLOSESOCKETS_LOOP:
        SUBQ.W  #0x1,D2                         | next entry
        BMI.B   E_ATP_CLOSE_EXIT                | all done -> return
        MOVE.B  (A0)+,D1                        | D1 = socket
        BEQ.B   ATP_CLOSESOCKETS_LOOP           | slot free -> next
        MOVE.W  #0xF7,D0                        | csCode 247 = CloseSkt
        BSR.W   ATP_MPPCALL                     | close it; resumes here when done
        BRA.B   ATP_CLOSESOCKETS_LOOP           | next entry

| -------------------------------------------------------------------------
| OpenATPSkt (csCode 254): open a responding socket.  atpSocket = socket
| to open (0 = assign one), addrBlock = addresses to accept requests from
| (0 in a field = any).  Opens the DDP socket with the slot's entry of
| ATP_LISTENER as its listener; returns the socket in atpSocket.
| tooManySkts, noDataArea, the OpenSkt errors (ddpSktErr).
| -------------------------------------------------------------------------
OPENATPSKT:
        MOVE.W  #-0x44A,D0                      | tooManySkts (-1098)
        MOVEQ.L #0x1F,D2                        | 32 responding-socket slots
OPENATPSKT_LOOP:
        TST.B   0x4C(A2,D2.W)                   | slot free?
        DBEQ.W  D2,OPENATPSKT_LOOP              | no -> next
        BNE.B   ATP_DONE                        | all in use -> IODone (tooManySkts)
| get a CB for the OpenSkt call
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_DONE                        | none -> IODone (noDataArea)
| OpenSkt via .MPP: D1 = socket, listener = ATP_LISTENER + 4 * slot
        LEA.L   ATP_LISTENER(PC),A1             | A1 = listener entry of slot 0
        LSL.W   #0x2,D2                         | slot * 4
        ADDA.W  D2,A1                           | A1 = listener entry of this slot
        MOVE.L  A1,0x1E(A3)                     | CB listener field
        MOVE.W  #0xF8,D0                        | csCode 248 = OpenSkt
        BSR.W   ATP_MPPCALL                     | open the socket; resumes here when done
        MOVE.B  csParam(A3),D1                  | D1 = socket opened (CB socket field)
        BSR.W   ATP_FREECB                      | release the CB
        TST.W   D0                              | OpenSkt result
        BNE.B   ATP_DONE                        | error -> IODone with it
| fill in the responding-socket slot (offsets beyond the 8-bit index
| displacement: A2 is moved instead)
        ADDA.W  D2,A2                           | A2 = ATPVars + slot * 4
        CLR.L   0x6C(A2)                        | no GetRequest waiting
        CLR.L   0xEC(A2)                        | no NSendRequest pending
        MOVE.L  D3,0x16C(A2)                    | addrBlock filter
        SUBA.W  D2,A2                           | A2 = ATPVars again
        LSR.W   #0x2,D2                         | byte index
        ADDA.W  D2,A2                           | A2 = ATPVars + slot
        MOVE.B  D1,0x4C(A2)                     | socket number
        SUBA.W  D2,A2                           | A2 = ATPVars again
        MOVE.B  D1,csParam(A0)                  | return it in atpSocket
        BRA.B   ATP_DONE_NOERR                  | -> IODone, noErr

| -------------------------------------------------------------------------
| CloseATPSkt (csCode 250): close responding socket atpSocket (D2 = its
| slot): CloseSkt via .MPP, then free the slot and the socket's RspCBs.
| GetRequests and NSendRequests still queued on the socket are not
| completed (KillGetReq / KillSendReq abort them).  noDataArea.
| -------------------------------------------------------------------------
CLOSEATPSKT:
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_DONE                        | none -> IODone (noDataArea)
        MOVE.W  #0xF7,D0                        | csCode 247 = CloseSkt
        BSR.W   ATP_MPPCALL                     | close the socket; resumes here when done
        BSR.W   ATP_FREECB                      | release the CB
        TST.W   D0                              | CloseSkt result
        BNE.B   ATP_DONE                        | error -> IODone with it
| free the slot and the socket's RspCBs
        CLR.B   0x4C(A2,D2.W)                   | responding-socket slot free
        LEA.L   0x1EC(A2),A1                    | A1 = RspCBs
        MOVEQ.L #0xF,D2                         | 16 RspCBs
CLOSEATPSKT_LOOP:
        CMP.B   (A1),D1                         | RspCB of this socket?
        BNE.B   CLOSEATPSKT_NEXT                | no ->
        CLR.B   (A1)                            | yes: free it
CLOSEATPSKT_NEXT:
        ADDA.W  #0xC,A1                         | next RspCB (12 bytes)
        DBF.W   D2,CLOSEATPSKT_LOOP             | loop over all 16
| ATP_DONE_NOERR / ATP_DONE / ATP_DONE_A1: common exits, IODone with D0
| (noErr; A1 = .ATP DCE from ATPVars; A1 already loaded)
| Called by: OPENATPSKT, KILLGETREQ, RELTCB (RelTCB, RelRspCB, KillSendReq)
ATP_DONE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
| ATP_DONE (ATPExit in Apple's Mac Plus source)
| Called by: E_ATP_Control, OPENATPSKT, CLOSEATPSKT, KILLGETREQ,
| KILLSENDREQ, RELTCB, SENDRESPONSE / ADDRESPONSE / SENDREQUEST (via
| SENDRESPONSE_EXIT, ADDRESPONSE_EXIT), NSENDREQUEST
ATP_DONE:
        MOVEA.L 0x2AC(A2),A1                    | A1 = .ATP DCE (ATPVars+$2AC)
ATP_DONE_A1:
        MOVEA.L (JIODone).W,A0                  | IODone vector
        JMP     (A0)                            | -> IODone (completes the current call)

| -------------------------------------------------------------------------
| .ATP Prime and Status: not supported - clear drvrActive and return
| without completing the call
| -------------------------------------------------------------------------
E_ATP_PrimeStatus:
        BCLR    #0x7,dCtlFlags+1(A1)            | dCtlFlags: clear drvrActive
        RTS                                     | return from E_ATP_PrimeStatus

| -------------------------------------------------------------------------
| GetRequest (csCode 253): queue the call on responding socket atpSocket
| (D2 = slot) until a request arrives; ATP_LISTENER_DELIVER fills in
| userData, atpFlags, addrBlock, reqLength, bitMap and transID and
| completes it.  reqLength/reqPointer = request buffer.
| -------------------------------------------------------------------------
GETREQUEST:
        LSL.W   #0x2,D2                         | long index
        LEA.L   0x6C(A2,D2.W),A1                | A1 -> GetRequest queue head of the socket
| ATP_APPENDREQ: append call A0 at the end of the queue whose head is at
| A1 (interrupts off), then ATP_DETACHREQ.  Also called (BSR) by
| NSENDREQUEST: it returns to its caller with D0 = 0 after ATP_DETACHREQ.
ATP_APPENDREQ:
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
ATP_APPENDREQ_LOOP:
        TST.L   (A1)                            | end of the queue?
        BEQ.B   ATP_APPENDREQ_LINK              | yes ->
        MOVEA.L (A1),A1                         | next element
        BRA.B   ATP_APPENDREQ_LOOP              | walk on
| link the call in at the end (its qLink is cleared below)
ATP_APPENDREQ_LINK:
        MOVE.L  A0,(A1)                         | last element -> this call
| ATP_DETACHREQ: take the current call (A0) off the .ATP I/O queue without
| completing it, then process the next queued call, if any, by calling
| E_ATP_Control (D1-D3/A0/A2-A3 preserved).  Entered with the caller's SR
| on the stack; returns with D0 = 0.  Used by SENDRESPONSE (exactly-once),
| SENDREQUEST and, through ATP_APPENDREQ, GETREQUEST and NSENDREQUEST.
ATP_DETACHREQ:
        MOVEA.L 0x2AC(A2),A1                    | A1 = .ATP DCE
        BCLR    #0x7,dCtlFlags+1(A1)            | dCtlFlags: clear drvrActive
        MOVE.L  (A0),dCtlQHead(A1)              | dCtlQHead = next call in the queue
        BNE.B   ATP_DETACHREQ_UNLINK            | there is one ->
        CLR.L   dCtlQTail(A1)                   | queue empty: dCtlQTail = nil
ATP_DETACHREQ_UNLINK:
        CLR.L   (A0)                            | qLink of the detached call = nil
        MOVE.L  dCtlQHead(A1),D0                | next call queued?
        BEQ.B   ATP_DETACHREQ_EXIT              | no ->
| start the next queued call
        BSET    #0x7,dCtlFlags+1(A1)            | dCtlFlags: set drvrActive again
        MOVE.W  (SP)+,SR                        | restore SR
        MOVEM.L D1-D3/A0/A2-A3,-(SP)            | save registers
        MOVEA.L D0,A0                           | A0 = next parameter block
        MOVEQ.L #0x0,D0                         | clear D0
        BSR.W   E_ATP_Control                   | process it (A1 = DCE)
        MOVEM.L (SP)+,D1-D3/A0/A2-A3            | restore registers
        MOVEQ.L #0x0,D0                         | D0 = 0
        RTS                                     | return from ATP_DETACHREQ
| no other call queued
ATP_DETACHREQ_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return from ATP_DETACHREQ

| -------------------------------------------------------------------------
| KillGetReq (csCode 257): abort the GetRequest at aKillQEl: unlink it from
| the GetRequest queue of its socket and complete it with reqAborted; the
| KillGetReq call completes with noErr, or cbNotFound if aKillQEl is not
| a queued GetRequest (IM V-518).
| -------------------------------------------------------------------------
KILLGETREQ:
        MOVEA.L 0x2C(A0),A1                     | A1 = aKillQEl (the GetRequest)
        MOVE.W  #-0x44E,D0                      | cbNotFound (-1102)
        MOVE.B  csParam(A1),D1                  | D1 = its atpSocket
        BEQ.B   KILLGETREQ_EXIT                 | 0 -> cbNotFound
        MOVEQ.L #0x1F,D2                        | 32 responding sockets
KILLGETREQ_SKTLOOP:
        CMP.B   0x4C(A2,D2.W),D1                | this socket?
        DBEQ.W  D2,KILLGETREQ_SKTLOOP           | no -> next
        BNE.B   KILLGETREQ_EXIT                 | not open -> cbNotFound
        ASL.W   #0x2,D2                         | long index
        LEA.L   0x6C(A2,D2.W),A3                | A3 -> GetRequest queue head of the socket
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
KILLGETREQ_LOOP:
        MOVE.L  (A3),D3                         | D3 = next queued GetRequest
        BEQ.B   KILLGETREQ_NOTFOUND             | end of the queue -> cbNotFound
        SUB.L   A1,D3                           | the one to kill?
        AND.L   (Lo3Bytes).W,D3                 | (24-bit addresses)
        BEQ.B   KILLGETREQ_FOUND                | yes ->
        MOVEA.L (A3),A3                         | next element
        BRA.B   KILLGETREQ_LOOP                 | walk on
| unlink it and complete it with reqAborted
KILLGETREQ_FOUND:
        MOVE.L  (A1),(A3)                       | predecessor -> its successor
        MOVE.W  (SP)+,SR                        | restore SR
        MOVEA.L A1,A0                           | A0 = the GetRequest
        MOVE.W  #-0x451,D0                      | reqAborted (-1105)
        BSR.W   ATP_COMPLETE                    | complete it
        BRA.W   ATP_DONE_NOERR                  | -> IODone (KillGetReq), noErr
KILLGETREQ_NOTFOUND:
        MOVE.W  (SP)+,SR                        | restore SR
KILLGETREQ_EXIT:
        BRA.W   ATP_DONE                        | -> IODone (cbNotFound)

| -------------------------------------------------------------------------
| SendResponse (csCode 252): send numOfBuffs response packets from the
| BDS at bdsPointer (bdsSize entries) to addrBlock with transID; the EOM
| flag of atpFlags goes into the last packet.  Each sent BDS entry gets
| bdsDataSz = -1, the unused ones 0 (AddResponse fills them in later).
| Not exactly-once (no RspCB): completes at once.  Exactly-once: the
| call is attached to the RspCB and completes on TRel (noErr), RelRspCB
| (noErr) or release timeout (noRelErr).  badBuffNum, noDataArea.
| -------------------------------------------------------------------------
SENDRESPONSE:
        MOVEA.L 0x28(A0),A1                     | A1 = bdsPointer
        SWAP.W  D1                              | atpSocket to the high word
        MOVE.W  #-0x44C,D0                      | badBuffNum (-1100)
        MOVE.B  0x2C(A0),D1                     | D1.B = numOfBuffs
        BEQ.B   SENDRESPONSE_SENT               | 0: send nothing now ->
        CMPI.B  #0x8,D1                         | more than atpMaxNum (8)?
        BHI.B   SENDRESPONSE_EXIT               | yes -> IODone (badBuffNum)
        BSR.W   ATP_GETCB                       | A3 = free CB
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
        MOVE.W  0x2E(A0),(A3)+                  | atpTransID = transID
        MOVE.W  (A1)+,D0                        | D0 = bdsBuffSz (data length)
        MOVE.L  (A1)+,D2                        | D2 = bdsBuffAdr (data)
        MOVE.W  #0xFFFF,(A1)+                   | bdsDataSz = -1: packet sent
        MOVE.L  (A1)+,(A3)+                     | atpUserData = bdsUserData
        LEA.L   -0x68(A3),A3                    | A3 = CB (was CB+$68)
        SWAP.W  D1                              | D1.W = atpSocket
        BSR.W   ATP_SENDPKT                     | WriteDDP; resumes here when done
        CMPI.W  #0xFFA4,D0                      | ddpLenErr (-92)?
        BEQ.B   SENDRESPONSE_ABORT              | yes -> stop, IODone with it
        SWAP.W  D1                              | D1.B = packets left
        TST.B   D1                              | any?
        BNE.B   SENDRESPONSE_LOOP               | yes -> next packet
        BSR.W   ATP_FREECB                      | release the CB
| mark the BDS entries beyond numOfBuffs as not sent (NoBuffs in Apple's
| Mac Plus source)
SENDRESPONSE_SENT:
        SWAP.W  D1                              | D1.W = atpSocket
        MOVE.B  0x2D(A0),D2                     | D2 = bdsSize
        SUB.B   0x2C(A0),D2                     | - numOfBuffs = entries not sent
        BEQ.B   SENDRESPONSE_RSPCB              | none ->
SENDRESPONSE_CLRLOOP:
        CLR.W   0x6(A1)                         | bdsDataSz = 0: no response yet
        ADDA.W  #0xC,A1                         | next BDS entry (12 bytes)
        SUBQ.B  #0x1,D2                         | count down
        BNE.B   SENDRESPONSE_CLRLOOP            | loop
| exactly-once? then hand the call to the RspCB of the transaction
SENDRESPONSE_RSPCB:
        MOVE.W  0x2E(A0),D0                     | D0 = transID
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        BSR.B   ATP_FINDRSPCB                   | RspCB of (atpSocket, addrBlock, transID)?
        BNE.W   ADDRESPONSE_NOERR               | none (not XO) -> IODone, noErr
        MOVE.L  A0,0x8(A1)                      | RspCB: this SendResponse
        CLR.B   0x1(A1)                         | restart the release timer
        BRA.W   ATP_DETACHREQ                   | leave the call pending
| SENDRESPONSE_ABORT - WriteDDP failed with ddpLenErr: release the CB;
| SENDRESPONSE_EXIT - IODone with D0 (also used by AddResponse)
SENDRESPONSE_ABORT:
        BSR.W   ATP_FREECB                      | release the CB
| Called by: SENDRESPONSE, ADDRESPONSE (error exits)
SENDRESPONSE_EXIT:
        BRA.W   ATP_DONE                        | -> IODone with D0

| -------------------------------------------------------------------------
| ATP_FINDRSPCB: find the RspCB of a transaction.  A2 = ATPVars, D1.B =
| responding socket, D3 = requester address, D0 = TID -> EQ and A1 =
| RspCB if found (NE if not).  Uses D2.
| Called by: SENDRESPONSE, ADDRESPONSE, RELRSPCB, ATP_LISTENER_TREL,
| ATP_LISTENER_GOTREQ
| -------------------------------------------------------------------------
ATP_FINDRSPCB:
        LEA.L   0x1EC(A2),A1                    | A1 = first RspCB
        MOVEQ.L #0xF,D2                         | 16 RspCBs
ATP_FINDRSPCB_LOOP:
        CMP.B   (A1),D1                         | same socket?
        BNE.B   ATP_FINDRSPCB_NEXT              | no ->
        ADDQ.W  #0x2,A1                         | A1 -> requester address
        BSR.B   ATP_CMPADDR                     | same address?
        SUBQ.W  #0x2,A1                         | A1 -> RspCB again
        BNE.B   ATP_FINDRSPCB_NEXT              | no ->
        CMP.W   0x6(A1),D0                      | same TID?
        BEQ.B   ATP_FINDRSPCB_EXIT              | yes -> found (EQ)
ATP_FINDRSPCB_NEXT:
        ADDA.W  #0xC,A1                         | next RspCB (12 bytes)
        DBF.W   D2,ATP_FINDRSPCB_LOOP           | loop over all 16
ATP_FINDRSPCB_EXIT:
        RTS                                     | EQ = found, NE = not found

| -------------------------------------------------------------------------
| ATP_CMPADDR: compare internet address D3 (net.W, node.B, socket.B)
| with the one at (A1) -> EQ if equal; node and socket must match, a
| network number of 0 on either side matches any network.
| Called by ATP_FINDRSPCB, RELTCB, ATP_LISTENER_GOTRSP.
| -------------------------------------------------------------------------
ATP_CMPADDR:
        CMP.L   (A1),D3                         | whole address equal?
        BEQ.B   ATP_CMPADDR_EXIT                | yes -> EQ
        CMP.W   0x2(A1),D3                      | node and socket equal?
        BNE.B   ATP_CMPADDR_EXIT                | no -> NE
        TST.W   (A1)                            | network at (A1) = 0?
        BEQ.B   ATP_CMPADDR_EXIT                | yes -> EQ
        MOVE.L  D3,-(SP)                        | push D3
        TST.W   (SP)+                           | its network = 0? (EQ / NE)
        ADDQ.W  #0x2,SP                         | pop the rest
ATP_CMPADDR_EXIT:
        RTS                                     | return from ATP_CMPADDR

| -------------------------------------------------------------------------
| AddResponse (csCode 251): send one more response packet: rspNum
| (0-7), reqLength/reqPointer = data, userData, atpFlags (EOM), transID,
| addrBlock.  For an exactly-once transaction the packet is also entered
| in the BDS of the pending SendResponse (numOfBuffs extended), so a
| retransmission request can resend it.  badBuffNum, ddpLenErr,
| noSendResp (XO and no SendResponse yet), noDataArea.
| -------------------------------------------------------------------------
ADDRESPONSE:
        MOVE.W  #-0x44C,D0                      | badBuffNum (-1100)
        MOVE.B  0x2C(A0),D2                     | D2 = rspNum
        CMPI.B  #0x8,D2                         | 0..7?
        BCC.B   SENDRESPONSE_EXIT               | no -> IODone (badBuffNum)
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.B   SENDRESPONSE_EXIT               | none -> IODone (noDataArea)
        MOVEQ.L #-0x5C,D0                       | ddpLenErr (-92)
        CMPI.W  #0x242,0x22(A0)                 | reqLength > atpMaxData (578)?
        BHI.B   SENDRESPONSE_EXIT               | yes -> IODone (ddpLenErr; the CB stays claimed)
| build the TResp header in the CB
        LEA.L   0x60(A3),A3                     | A3 -> ATP header in the CB
        MOVEQ.L #-0x80,D0                       | function code $80 = TResp
        OR.B    0x1D(A0),D0                     | add atpFlags (EOM)
        MOVE.B  D0,(A3)+                        | atpControl
        MOVE.B  D2,(A3)+                        | atpRespNo = rspNum
        MOVE.W  0x2E(A0),(A3)+                  | atpTransID = transID
| send it
        BSR.W   ATP_SETDATA                     | user bytes, D0/D2 = reqLength/reqPointer
        BSR.W   ATP_SENDPKT                     | WriteDDP; resumes here when done
        BSR.W   ATP_FREECB                      | release the CB
        MOVE.W  0x2E(A0),D0                     | D0 = transID
        MOVE.W  SR,-(SP)                        | save SR
| exactly-once transaction? (RspCB present)
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        BSR.B   ATP_FINDRSPCB                   | RspCB of (atpSocket, addrBlock, transID)?
        BNE.B   ADDRESPONSE_NOERR               | no RspCB (not XO) -> IODone, noErr
| enter the packet in the BDS of the pending SendResponse
        MOVEA.L 0x8(A1),A3                      | A3 = SendResponse of the RspCB
        MOVE.W  #-0x44F,D0                      | noSendResp (-1103)
        MOVE.L  A3,D2                           | SendResponse issued yet?
        BEQ.B   ADDRESPONSE_RESTSR              | no -> IODone (noSendResp)
        MOVE.B  0x1D(A0),D2                     | AddResponse atpFlags
        OR.B    D2,0x1D(A3)                     | merge into the SendResponse atpFlags (EOM)
| numOfBuffs of the SendResponse = max(numOfBuffs, rspNum + 1)
        CLR.W   D2                              | D2 = rspNum (word)
        MOVE.B  0x2C(A0),D2                     | rspNum
        LEA.L   0x2C(A3),A3                     | A3 -> numOfBuffs of the SendResponse
        CMP.B   (A3),D2                         | rspNum < numOfBuffs?
        BLT.B   ADDRESPONSE_BDS                 | yes -> keep it
        MOVE.B  D2,(A3)                         | numOfBuffs = rspNum
        ADDQ.B  #0x1,(A3)                       | + 1
ADDRESPONSE_BDS:
        MOVEA.L -(A3),A3                        | A3 = bdsPointer of the SendResponse
        MULU.W  #0xC,D2                         | entry offset (12 bytes each)
        ADDA.W  D2,A3                           | A3 -> BDS entry rspNum
        MOVE.W  0x22(A0),(A3)+                  | bdsBuffSz = reqLength
        MOVE.L  0x24(A0),(A3)+                  | bdsBuffAdr = reqPointer
        MOVE.W  #0xFFFF,(A3)+                   | bdsDataSz = -1: packet sent
        MOVE.L  0x12(A0),(A3)                   | bdsUserData = userData
        CLR.B   0x1(A1)                         | restart the release timer
ADDRESPONSE_NOERR:
        CLR.W   D0                              | noErr
ADDRESPONSE_RESTSR:
        MOVE.W  (SP)+,SR                        | restore SR
| ADDRESPONSE_EXIT (JATPEx2 in Apple's source): -> ATP_DONE
ADDRESPONSE_EXIT:
        BRA.W   ATP_DONE                        | -> IODone with D0

| -------------------------------------------------------------------------
| SendRequest (csCode 255): open a private DDP socket (dynamic number,
| listener ATP_REQLISTENER), fill in a free request slot, send the TReq
| (addrBlock, reqLength/reqPointer, userData, XO/STS from atpFlags,
| bitmap of numOfBuffs responses) and leave the call pending.  Returns
| reqTID (tidValid set in atpFlags); ATP_READRESP stores the
| responses in the BDS, ATP_VBLTASK retransmits after timeOutVal seconds
| up to retryCount times (255 = forever).  tooManyReqs, ddpLenErr,
| noDataArea; later reqFailed, reqAborted.
| -------------------------------------------------------------------------
SENDREQUEST:
        MOVE.W  #-0x449,D0                      | tooManyReqs (-1097)
        MOVEQ.L #0xB,D2                         | 12 request slots
SENDREQUEST_LOOP:
        TST.B   0x4(A2,D2.W)                    | slot free?
        DBEQ.W  D2,SENDREQUEST_LOOP             | no -> next
        BNE.B   ADDRESPONSE_EXIT                | all in use -> IODone (tooManyReqs)
        BSR.W   ATP_SNDRQINIT                   | reqLength ok? A3 = free CB
        BNE.B   ADDRESPONSE_EXIT                | no -> IODone (ddpLenErr / noDataArea)
        CLR.B   D1                              | socket 0: let .MPP assign one
        LEA.L   ATP_REQLISTENER(PC),A1          | A1 = listener of the request sockets
        MOVE.L  A1,0x1E(A3)                     | CB listener field (patch PMAB301 rejoins here, ToROMSendReq)
        MOVE.W  #0xF8,D0                        | csCode 248 = OpenSkt
        BSR.W   ATP_MPPCALL                     | open the socket; resumes here when done
        BEQ.B   SENDREQUEST_OPENED              | opened ->
        BSR.W   ATP_FREECB                      | failed: release the CB
        BRA.B   ADDRESPONSE_EXIT                | -> IODone with the OpenSkt error
| socket opened: D1 = its number, D2 = free request slot
SENDREQUEST_OPENED:
        MOVE.B  csParam(A3),D1                  | D1 = socket opened (CB socket field)
        BSR.W   ATP_SETBITMAP                   | currBitmap, numOfResps = 0, D2 = slot * 4
| fill in the request slot; next transaction ID
        MOVE.L  A0,0x10(A2,D2.W)                | slot: parameter block
        LEA.L   0x2B0(A2),A1                    | A1 -> next TID (ATPVars+$2B0)
        MOVE.W  (A1),0x16(A0)                   | reqTID = TID
        BSET    #0x1,0x1D(A0)                   | atpFlags: tidValid
        ADDQ.W  #0x1,(A1)                       | advance the TID counter
| socket and retry timer of the slot
        LSR.W   #0x2,D2                         | byte index
        MOVE.B  D1,0x4(A2,D2.W)                 | slot: socket
        LEA.L   0x40(A2,D2.W),A1                | A1 -> slot retry timer
        CLR.B   (A1)                            | timer stopped while sending
| send the TReq
        BSR.W   ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        BSR.W   ATP_SENDPKT                     | WriteDDP; resumes here when done
        BSR.W   ATP_FREECB                      | release the CB
        MOVE.B  0x2D(A0),(A1)                   | retry timer = timeOutVal (seconds)
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        BRA.W   ATP_DETACHREQ                   | leave the call pending

| -------------------------------------------------------------------------
| NSendRequest (csCode 248, IM V-516): like SendRequest, but through the
| open responding socket atpSocket (D2 = its slot).  The call is appended
| to the NSendRequest queue of the socket (at most ATPVars+$4CA of them,
| else tooManyReqs) with a TID not used by another NSendRequest of the
| socket; its retry timer is intBuff (PB+$30).  ATP_LISTENER_COMMON takes
| the responses, ATP_VBLTASK retransmits.  The call is detached before the
| TReq is sent.  ddpLenErr, noDataArea, tooManyReqs (note: this error
| leaves the CB claimed); later reqFailed, reqAborted.
| -------------------------------------------------------------------------
NSENDREQUEST:
        BSR.B   ATP_SNDRQINIT                   | reqLength ok? A3 = free CB
        BNE.B   NSENDREQUEST_EXIT               | no -> IODone (ddpLenErr / noDataArea)
        BSR.B   ATP_SETBITMAP                   | currBitmap, numOfResps = 0, D2 = slot * 4
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
| count the NSendRequests of the socket; skip TIDs they use
NSENDREQUEST_TID:
        LEA.L   0xEC(A2),A1                     | A1 -> NSendRequest queues
        ADDA.W  D2,A1                           | A1 -> queue head of this socket
        MOVE.W  0x2B0(A2),D3                    | D3 = next TID
        MOVEQ.L #0x0,D0                         | D0 = NSendRequests queued
NSENDREQUEST_LOOP:
        TST.L   (A1)                            | end of the queue?
        BEQ.B   NSENDREQUEST_COUNTED            | yes ->
        ADDQ.W  #0x1,D0                         | count it
        MOVEA.L (A1),A1                         | next NSendRequest
        CMP.W   0x16(A1),D3                     | its reqTID = the candidate?
        BNE.B   NSENDREQUEST_LOOP               | no -> next
        ADDQ.W  #0x1,0x2B0(A2)                  | yes: skip this TID
        BRA.B   NSENDREQUEST_TID                | and scan again
NSENDREQUEST_COUNTED:
        MOVE.W  (SP)+,SR                        | restore SR
        CMP.W   0x4CA(A2),D0                    | fewer than the limit per socket?
        BCS.B   NSENDREQUEST_QUEUE              | yes ->
        MOVE.W  #-0x449,D0                      | tooManyReqs (-1097; the CB is not released)
NSENDREQUEST_EXIT:
        BRA.W   ATP_DONE                        | -> IODone with D0
| queue the call on the socket, send the TReq
NSENDREQUEST_QUEUE:
        MOVE.W  D3,0x16(A0)                     | reqTID = TID
        BSET    #0x1,0x1D(A0)                   | atpFlags: tidValid
        ADDQ.W  #0x1,0x2B0(A2)                  | advance the TID counter
        MOVE.B  0x2D(A0),0x30(A0)               | intBuff = timeOutVal: retry timer (seconds)
        LEA.L   0xEC(A2),A1                     | A1 -> NSendRequest queues
        ADDA.W  D2,A1                           | A1 -> queue head of this socket
        BSR.W   ATP_APPENDREQ                   | append it, take it off the driver queue
        BSR.W   ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        BSR.B   ATP_SENDPKT                     | WriteDDP (from atpSocket); resumes here when done
        MOVEQ.L #0x0,D0                         | D0 = 0
        BRA.W   ATP_FREECB                      | release the CB, return

| -------------------------------------------------------------------------
| ATP_SNDRQINIT (SndRqInit in Apple's source): reqLength of A0 must be <=
| atpMaxData (578), else D0 = ddpLenErr; then claim a CB (A3; D0 =
| noDataArea if none).  Returns the condition codes of D0 (EQ = ok).
| Called by SENDREQUEST, NSENDREQUEST.
| -------------------------------------------------------------------------
ATP_SNDRQINIT:
        MOVEQ.L #-0x5C,D0                       | ddpLenErr (-92)
        CMPI.W  #0x242,0x22(A0)                 | reqLength > atpMaxData (578)?
        BHI.B   ATP_SNDRQINIT_EXIT              | yes -> ddpLenErr
        BSR.W   ATP_GETCB                       | A3 = free CB
ATP_SNDRQINIT_EXIT:
        TST.W   D0                              | EQ = ok
        RTS                                     | return from ATP_SNDRQINIT

| -------------------------------------------------------------------------
| ATP_SETBITMAP: currBitmap of request A0 = one bit per expected response
| (bits 0..numOfBuffs-1), EOM cleared, numOfResps = 0; D2 = D2 * 4 (slot
| -> long index).  Uses D0, A1.  Called by SENDREQUEST, NSENDREQUEST.
| -------------------------------------------------------------------------
ATP_SETBITMAP:
        LEA.L   0x1D(A0),A1                     | A1 -> atpFlags
        BCLR    #0x4,(A1)                       | clear EOM (set when the last response arrives)
        CLR.B   -(A1)                           | currBitmap = 0
        MOVE.B  0x2C(A0),D0                     | D0 = numOfBuffs
        BEQ.B   ATP_SETBITMAP_DONE              | none ->
        SUBQ.B  #0x1,D0                         | highest bit number
ATP_SETBITMAP_LOOP:
        BSET    D0,(A1)                         | set the bit of this response
        SUBQ.B  #0x1,D0                         | next lower bit
        BPL.B   ATP_SETBITMAP_LOOP              | down to bit 0
ATP_SETBITMAP_DONE:
        CLR.B   0x2E(A0)                        | numOfResps = 0
        LSL.W   #0x2,D2                         | long index
        RTS                                     | return from ATP_SETBITMAP

| -------------------------------------------------------------------------
| ATP_SENDPKT: send the ATP packet of CB A3 (header at CB+$60): builds the
| WDS (DDP header template with type ATP and destination D3, the 8-byte
| ATP header, D0 bytes at D2) and issues WriteDDP from socket D1, with a
| checksum if atpFlags (A0) has sendCHK.  Resumes the caller when done.
| Called by: SENDRESPONSE, ADDRESPONSE, SENDREQUEST, NSENDREQUEST,
| ATP_VBLTASK, ATP_LISTENER_STS, ATP_LISTENER_XO, ATP_LISTENER_RESENDBDS
| -------------------------------------------------------------------------
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
        MOVE.W  D3,(A0)+                        | +11 dest node (+12 scratch)
        MOVE.B  D3,(A0)                         | +13 dest socket
| WDS entry 2: ATP header, entry 3: data, then the terminator
        MOVE.W  #0x8,(A1)+                      | entry 2 length = atpHdSz (8)
        LEA.L   0x60(A3),A0                     | A0 = ATP header (CB+$60)
        MOVE.L  A0,(A1)+                        | entry 2 pointer
        MOVE.W  D0,(A1)+                        | entry 3 length = data length
        MOVE.L  D2,(A1)+                        | entry 3 pointer = data
        CLR.W   (A1)+                           | end of WDS
        MOVEM.L (SP)+,A0-A1                     | restore A0-A1
| WriteDDP via .MPP
        MOVE.W  #0xF6,D0                        | csCode 246 = WriteDDP
| ATP_MPPCALL: async _Control D0 to .MPP with CB A3 (socket D1).  Saves
| D1-D3/A0-A1 and the return address in the CB and returns to the
| caller's caller with D0 = 0; ATP_MPPDONE resumes after the BSR when the
| call completes (D0 = result, A2 = ATPVars, CB in A3).
| Called by: ATP_CLOSESOCKETS, OPENATPSKT, CLOSEATPSKT, SENDREQUEST,
| ATP_VBLTASK_FAIL, RELTCB_FOUND, ATP_LISTENER_CLOSE (and ATP_SENDPKT)
ATP_MPPCALL:
        MOVEM.L D1-D3/A0-A1,0x22(A3)            | save D1-D3/A0-A1 in CB+$22
        MOVE.L  (SP)+,0x36(A3)                  | address to resume at -> CB+$36
        LEA.L   ATP_MPPDONE(PC),A0              | A0 = completion routine
        MOVE.L  A0,ioCompletion(A3)             | ioCompletion = ATP_MPPDONE
        MOVEA.L A3,A0                           | A0 = CB
        MOVE.B  D1,csParam(A0)                  | socket
        MOVE.W  D0,csCode(A0)                   | csCode
        _ControlAsync                           | queue the call to .MPP (ioRefNum set by ATP_GETCB)
        MOVEQ.L #0x0,D0                         | D0 = 0
        RTS                                     | return to the caller's caller

| -------------------------------------------------------------------------
| ATP_MPPDONE: ioCompletion of the CBs (A0 = CB, D0 = result): restore
| the saved registers and continue after the BSR ATP_MPPCALL, with
| A3 = CB, A2 = ATPVars and the condition codes set from D0
| -------------------------------------------------------------------------
ATP_MPPDONE:
        MOVEA.L A0,A3                           | A3 = CB
        MOVE.L  0x36(A0),-(SP)                  | push the address to resume at
        MOVEM.L 0x22(A0),D1-D3/A0-A1            | restore D1-D3/A0-A1
        MOVEA.L (ABusVars).W,A2                 | A2 = MPP variables
        MOVEA.L 0x1E(A2),A2                     | A2 = ATPVars
        TST.W   D0                              | condition codes = result
        RTS                                     | resume the caller

| -------------------------------------------------------------------------
| ATP_BUILDTREQ: TReq header in CB A3 from (N)SendRequest A0: control $40
| + atpFlags without EOM, bitmap = currBitmap, TID = reqTID; D3 =
| addrBlock.  Falls into ATP_SETDATA.
| Called by: SENDREQUEST, NSENDREQUEST, ATP_VBLTASK, ATP_LISTENER_STS
| -------------------------------------------------------------------------
ATP_BUILDTREQ:
        LEA.L   0x60(A3),A3                     | A3 -> ATP header in the CB
        MOVEQ.L #0x40,D0                        | function code $40 = TReq
        OR.B    0x1D(A0),D0                     | add atpFlags (XO, STS)
        BCLR    #0x4,D0                         | no EOM in a request
        MOVE.B  D0,(A3)+                        | atpControl
        MOVE.B  0x1C(A0),(A3)+                  | atpBitmap = currBitmap (responses still missing)
        MOVE.W  0x16(A0),(A3)+                  | atpTransID = reqTID
        MOVE.L  0x1E(A0),D3                     | D3 = addrBlock (destination)
| ATP_SETDATA: atpUserData = userData, D0/D2 = reqLength/reqPointer of
| parameter block A0; A3 back to the CB (A3 = CB+$64 on entry)
ATP_SETDATA:
        MOVE.L  0x12(A0),(A3)                   | atpUserData = userData
        MOVE.W  0x22(A0),D0                     | D0 = reqLength
        MOVE.L  0x24(A0),D2                     | D2 = reqPointer
        SUBA.W  #0x64,A3                        | A3 = CB
ATP_SETDATA_EXIT:
        RTS                                     | return from ATP_SETDATA (also ATP_VBLTASK's early exit)

| -------------------------------------------------------------------------
| ATP_FIRSTNSREQ: A0 = first NSendRequest queued on responding socket
| slot D2 (A2 = ATPVars), D0 = A0; EQ if none.
| Called by ATP_VBLTASK (twice).
| -------------------------------------------------------------------------
ATP_FIRSTNSREQ:
        MOVE.W  D2,D0                           | D0 = slot
        LSL.W   #0x2,D0                         | long index
        ADDA.W  D0,A2                           | A2 = ATPVars + slot * 4
        MOVEA.L 0xEC(A2),A0                     | A0 = queue head of the slot
        SUBA.W  D0,A2                           | A2 = ATPVars again
        MOVE.L  A0,D0                           | EQ if none
        RTS                                     | return from ATP_FIRSTNSREQ

| -------------------------------------------------------------------------
| ATP_REQFAILED: complete request A0 with reqFailed (retries used up)
| -------------------------------------------------------------------------
ATP_REQFAILED:
        MOVE.W  #-0x448,D0                      | reqFailed (-1096)
        BRA.W   ATP_COMPLETE                    | complete it

| -------------------------------------------------------------------------
| ATP_RETRYCOUNT: one retry of request A0 used up: retryCount - 1 unless
| it is 255 (retry forever).  C set if retryCount was already 0 (give up).
| Called by ATP_VBLTASK (SendRequest and NSendRequest timers).
| -------------------------------------------------------------------------
ATP_RETRYCOUNT:
        CMPI.B  #0xFF,0x2F(A0)                  | retryCount = 255 (retry forever)?
        BEQ.B   ATP_RETRYCOUNT_EXIT             | yes -> C clear
        SUBQ.B  #0x1,0x2F(A0)                   | retryCount - 1 (C set if it was 0)
ATP_RETRYCOUNT_EXIT:
        RTS                                     | return from ATP_RETRYCOUNT

| -------------------------------------------------------------------------
| ATP_UNLINKNSREQ: remove request A0 from the NSendRequest queue of
| responding socket slot D2 (interrupts off) -> EQ and D0 = 0 if it was
| there, else NE and D0 = cbNotFound.  Uses A1.
| Called by ATP_VBLTASK_NSFAIL, KILLSENDREQ, ATP_LISTENER_REQDONE.
| -------------------------------------------------------------------------
ATP_UNLINKNSREQ:
        MOVE.W  D2,D0                           | D0 = slot
        LSL.W   #0x2,D0                         | long index
        LEA.L   0xEC(A2),A1                     | A1 -> NSendRequest queues
        ADDA.W  D0,A1                           | A1 -> queue head of the slot
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
ATP_UNLINKNSREQ_LOOP:
        MOVE.L  (A1),D0                         | D0 = next element
        BEQ.B   ATP_UNLINKNSREQ_NONE            | end of the queue -> not found
        SUB.L   A0,D0                           | the request?
        AND.L   (Lo3Bytes).W,D0                 | (24-bit addresses)
        BEQ.B   ATP_UNLINKNSREQ_FOUND           | yes ->
        MOVEA.L (A1),A1                         | next element
        BRA.B   ATP_UNLINKNSREQ_LOOP            | walk on
ATP_UNLINKNSREQ_FOUND:
        MOVE.L  (A0),(A1)                       | predecessor -> its successor (D0 = 0)
ATP_UNLINKNSREQ_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        TST.W   D0                              | EQ = removed
        RTS                                     | return from ATP_UNLINKNSREQ
ATP_UNLINKNSREQ_NONE:
        MOVE.W  #-0x44E,D0                      | cbNotFound (-1102)
        BRA.B   ATP_UNLINKNSREQ_EXIT            | -> return NE

| -------------------------------------------------------------------------
| ATP_VBLTASK: VBL task, once per second (A0 = task at ATPVars+$2B2).
| Re-entry guard: when it is already running it only asks to be called
| again at the next tick.  Request slots: count down the retry timers; on
| expiry retransmit the TReq (bitmap of the responses still missing) or,
| when retryCount is used up, close the socket and complete the
| SendRequest with reqFailed.  NSendRequests (per responding socket): the
| intBuff timers of all of them count down; expired ones are retransmitted
| or dequeued and completed with reqFailed.  RspCBs: count the release
| timers up; after 30 seconds (releaseTime) free the RspCB and complete
| its SendResponse with noRelErr.  The request-slot and NSendRequest scans
| need a CB (skipped when none is free).  (CheckTime in Apple's Mac Plus
| source.)
| -------------------------------------------------------------------------
ATP_VBLTASK:
        LEA.L   -0x2B2(A0),A2                   | A2 = ATPVars (task at +$2B2)
        MOVE.W  #0x1,vblCount(A0)               | vblCount = 1: if busy, try again next tick
        BSET    #0x7,0x4C8(A2)                  | +$4C8 bit 7: VBL task running?
        BNE.B   ATP_SETDATA_EXIT                | yes (re-entered) -> return
        MOVE.W  #0x3C,vblCount(A0)              | vblCount = 60: run again in 1 second
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.W   ATP_VBLTASK_RSPCBS              | none: skip the request timers this time
        MOVEQ.L #0xC,D2                         | 12 request slots
| scan the request slots
ATP_VBLTASK_REQLOOP:
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
ATP_VBLTASK_NEXTREQ:
        SUBQ.W  #0x1,D2                         | next slot
        BMI.B   ATP_VBLTASK_NSREQS              | all done -> NSendRequests
        MOVE.B  0x4(A2,D2.W),D1                 | D1 = socket of the slot
        BEQ.B   ATP_VBLTASK_NEXTREQ             | slot free ->
        LEA.L   0x40(A2,D2.W),A1                | A1 -> retry timer
        TST.B   (A1)                            | running?
        BEQ.B   ATP_VBLTASK_NEXTREQ             | no ->
        SUBQ.B  #0x1,(A1)                       | one second less
        BNE.B   ATP_VBLTASK_NEXTREQ             | not expired ->
| retry timer expired
        MOVE.W  D2,D3                           | D3 = slot
        LSL.W   #0x2,D3                         | long index
        MOVEA.L 0x10(A2,D3.W),A0                | A0 = SendRequest
        BSR.W   ATP_RETRYCOUNT                  | one retry less (255 = forever)
        BCS.B   ATP_VBLTASK_FAIL                | was 0 -> give up
| retransmit the TReq
        MOVE.B  0x2D(A0),(A1)                   | retry timer = timeOutVal
        MOVEA.W D2,A1                           | A1 = slot (kept across ATP_SENDPKT)
        BSR.W   ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        MOVE.W  (SP)+,SR                        | restore SR
        BSR.W   ATP_SENDPKT                     | WriteDDP; resumes here when done
        MOVE.W  A1,D2                           | D2 = slot
        BRA.B   ATP_VBLTASK_REQLOOP             | scan on
| retries used up: close the socket, complete with reqFailed
ATP_VBLTASK_FAIL:
        MOVE.W  (SP)+,SR                        | restore SR
        CLR.B   0x4(A2,D2.W)                    | free the request slot
        MOVE.W  #0xF7,D0                        | csCode 247 = CloseSkt
        BSR.W   ATP_MPPCALL                     | close the socket; resumes here when done
        BSR.W   ATP_REQFAILED                   | complete the SendRequest (reqFailed)
        BRA.B   ATP_VBLTASK_REQLOOP             | scan on
| NSendRequests: the responding sockets (interrupts still off)
ATP_VBLTASK_NSREQS:
        MOVEQ.L #0x20,D2                        | 32 responding sockets
ATP_VBLTASK_NEXTSKT:
        SUBQ.W  #0x1,D2                         | next socket
        BMI.B   ATP_VBLTASK_REQDONE             | all done ->
        MOVE.B  0x4C(A2,D2.W),D1                | D1 = socket
        BEQ.B   ATP_VBLTASK_NEXTSKT             | slot free ->
        BSR.W   ATP_FIRSTNSREQ                  | A0 = first NSendRequest of the socket
        BEQ.B   ATP_VBLTASK_NEXTSKT             | none ->
| one second less for every NSendRequest of the socket
ATP_VBLTASK_NSCOUNT:
        SUBQ.B  #0x1,0x30(A0)                   | intBuff timer - 1
        MOVEA.L (A0),A0                         | next NSendRequest
        MOVE.L  A0,D0                           | any?
        BNE.B   ATP_VBLTASK_NSCOUNT             | yes -> count it down too
| look for an expired one (from the start of the queue)
ATP_VBLTASK_NSSCAN:
        BSR.W   ATP_FIRSTNSREQ                  | A0 = first NSendRequest of the socket
        BEQ.B   ATP_VBLTASK_NEXTSKT             | none ->
ATP_VBLTASK_NSFIND:
        TST.B   0x30(A0)                        | timer expired (0)?
        BEQ.B   ATP_VBLTASK_NSEXPIRED           | yes ->
        MOVEA.L (A0),A0                         | next NSendRequest
        MOVE.L  A0,D0                           | any?
        BNE.B   ATP_VBLTASK_NSFIND              | yes ->
        BRA.B   ATP_VBLTASK_NEXTSKT             | no expired one -> next socket
| expired: retransmit (timer = timeOutVal) or give up
ATP_VBLTASK_NSEXPIRED:
        BSR.W   ATP_RETRYCOUNT                  | one retry less (255 = forever)
        BCS.B   ATP_VBLTASK_NSFAIL              | was 0 -> give up
        MOVE.B  0x2D(A0),0x30(A0)               | timer = timeOutVal
        MOVEA.W D2,A1                           | A1 = socket slot (kept across ATP_SENDPKT)
        BSR.W   ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        MOVE.W  (SP)+,SR                        | restore SR
        BSR.W   ATP_SENDPKT                     | WriteDDP from the socket; resumes here when done
        MOVE.W  A1,D2                           | D2 = socket slot
ATP_VBLTASK_NSRESCAN:
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        BRA.B   ATP_VBLTASK_NSSCAN              | look for the next expired one
| retries used up: dequeue it, complete with reqFailed
ATP_VBLTASK_NSFAIL:
        BSR.W   ATP_UNLINKNSREQ                 | remove it from the socket's queue
        MOVE.W  (SP)+,SR                        | restore SR
        BSR.W   ATP_REQFAILED                   | complete the NSendRequest (reqFailed)
        BRA.B   ATP_VBLTASK_NSRESCAN            | scan on
| request timers done: release the CB
ATP_VBLTASK_REQDONE:
        MOVE.W  (SP)+,SR                        | restore SR
        BSR.W   ATP_FREECB                      | release the CB
| release timers of the RspCBs
ATP_VBLTASK_RSPCBS:
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
        MOVEQ.L #0x10,D2                        | 16 RspCBs
        LEA.L   0x1EC(A2),A3                    | A3 = first RspCB
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
        MOVEA.L 0x7(A3),A0                      | A0 = SendResponse (RspCB+8)
        CLR.B   -0x1(A3)                        | free the RspCB
        MOVE.L  A0,D0                           | SendResponse issued?
        BEQ.B   ATP_VBLTASK_NEXTRSP             | no ->
        MOVE.W  #-0x44D,D0                      | noRelErr (-1101)
        BSR.B   ATP_COMPLETE                    | complete it
ATP_VBLTASK_NEXTRSP:
        ADDA.W  #0xB,A3                         | next RspCB (12 bytes)
        BRA.B   ATP_VBLTASK_RSPLOOP             | loop
| done
ATP_VBLTASK_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        BCLR    #0x7,0x4C8(A2)                  | VBL task no longer running
        RTS                                     | return from ATP_VBLTASK

| -------------------------------------------------------------------------
| ATP_COMPLETE: complete a call that ATP_DETACHREQ took off the queue:
| ioResult = D0, then call its ioCompletion routine (A0 = parameter
| block, D0 = result), if any.  Preserves D1-D3/A0-A3.
| Called by: ATP_VBLTASK, ATP_REQFAILED, KILLGETREQ, RELTCB, RELRSPCB,
| ATP_LISTENER_TREL, ATP_LISTENER_COMPLETE, ATP_LISTENER_DELIVER
| -------------------------------------------------------------------------
ATP_COMPLETE:
        MOVE.W  D0,ioResult(A0)                 | ioResult = D0
        MOVEM.L D1-D3/A0-A3,-(SP)               | save registers
        MOVE.L  ioCompletion(A0),D1             | D1 = ioCompletion
        BEQ.B   ATP_COMPLETE_EXIT               | none ->
        MOVEA.L D1,A1                           | A1 = completion routine
        TST.W   D0                              | condition codes = result
        JSR     (A1)                            | call the ioCompletion routine of the call
ATP_COMPLETE_EXIT:
        MOVEM.L (SP)+,D1-D3/A0-A3               | restore registers
        RTS                                     | return from ATP_COMPLETE

| -------------------------------------------------------------------------
| KillSendReq (csCode 258, IM V-517): abort the request at aKillQEl: an
| NSendRequest (its csCode is 248) is looked for in the NSendRequest
| queues of all responding sockets and dequeued; a SendRequest in the
| request slots (its socket is closed, its slot freed: RELTCB_FOUND).  The
| request completes with reqAborted, the KillSendReq call with noErr or
| cbNotFound.
| -------------------------------------------------------------------------
KILLSENDREQ:
        MOVEA.L 0x2C(A0),A0                     | A0 = aKillQEl (the request)
        CMPI.W  #0xF8,csCode(A0)                | an NSendRequest (248)?
        BNE.B   KILLSENDREQ_SREQ                | no -> a SendRequest
        MOVEQ.L #0x1F,D2                        | 32 responding sockets
KILLSENDREQ_SKTLOOP:
        TST.B   0x4C(A2,D2.W)                   | socket open?
        BEQ.B   KILLSENDREQ_NEXTSKT             | no ->
        BSR.W   ATP_UNLINKNSREQ                 | in its NSendRequest queue? (dequeued)
        BEQ.B   RELTCB_ABORT                    | yes -> complete it with reqAborted
KILLSENDREQ_NEXTSKT:
        DBF.W   D2,KILLSENDREQ_SKTLOOP          | next socket
KILLSENDREQ_NOTFOUND:
        MOVE.W  #-0x44E,D0                      | cbNotFound (-1102)
        BRA.W   ATP_DONE                        | -> IODone
| a SendRequest: find its request slot
KILLSENDREQ_SREQ:
        MOVEQ.L #0xB,D2                         | 12 request slots
KILLSENDREQ_SLOTLOOP:
        TST.B   0x4(A2,D2.W)                    | slot in use?
        BEQ.B   KILLSENDREQ_NEXTSLOT            | no ->
        MOVE.W  D2,D3                           | D3 = slot
        LSL.W   #0x2,D3                         | long index
        MOVE.L  0x10(A2,D3.W),D3                | D3 = SendRequest of the slot
        SUB.L   A0,D3                           | the one to kill?
        AND.L   (Lo3Bytes).W,D3                 | (24-bit addresses)
        BEQ.B   RELTCB_FOUND                    | yes -> close its socket, complete it
KILLSENDREQ_NEXTSLOT:
        DBF.W   D2,KILLSENDREQ_SLOTLOOP         | next slot
        BRA.B   KILLSENDREQ_NOTFOUND            | not found -> cbNotFound

| -------------------------------------------------------------------------
| RelTCB (csCode 256): abort the SendRequest with transID to addrBlock
| (request slots only, not NSendRequests: IM V-517): close its socket,
| free its slot and complete it with reqAborted.  cbNotFound, noDataArea.
| -------------------------------------------------------------------------
RELTCB:
        MOVE.W  0x2E(A0),D1                     | D1 = transID
        MOVEQ.L #0xB,D2                         | 12 request slots
RELTCB_LOOP:
        TST.B   0x4(A2,D2.W)                    | slot in use?
        BEQ.B   RELTCB_NEXT                     | no ->
        MOVE.W  D2,D0                           | D0 = slot
        LSL.W   #0x2,D0                         | long index
        MOVEA.L 0x10(A2,D0.W),A0                | A0 = SendRequest of the slot
        CMP.W   0x16(A0),D1                     | its reqTID = transID?
        BNE.B   RELTCB_NEXT                     | no ->
        LEA.L   0x1E(A0),A1                     | A1 -> its addrBlock
        BSR.W   ATP_CMPADDR                     | same destination as D3?
        BEQ.B   RELTCB_FOUND                    | yes ->
RELTCB_NEXT:
        DBF.W   D2,RELTCB_LOOP                  | next slot
| RELTCB_NOTFOUND - no such transaction (also used by RelRspCB)
RELTCB_NOTFOUND:
        MOVE.W  #-0x44E,D0                      | cbNotFound (-1102)
        BRA.W   ATP_DONE                        | -> IODone
| found (also from KillSendReq): A0 = SendRequest, D2 = its slot
RELTCB_FOUND:
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.W   ATP_DONE                        | none -> IODone (noDataArea)
        MOVE.B  0x4(A2,D2.W),D1                 | D1 = socket of the request
        CLR.B   0x4(A2,D2.W)                    | free the request slot
        MOVE.W  #0xF7,D0                        | csCode 247 = CloseSkt
        BSR.W   ATP_MPPCALL                     | close the socket; resumes here when done
        BSR.W   ATP_FREECB                      | release the CB
| RELTCB_ABORT - complete request A0 with reqAborted (also KillSendReq)
RELTCB_ABORT:
        MOVE.W  #-0x451,D0                      | reqAborted (-1105)
        BSR.W   ATP_COMPLETE                    | complete the request
| RELTCB_DONE - complete the RelTCB / RelRspCB / KillSendReq call, noErr
RELTCB_DONE:
        BRA.W   ATP_DONE_NOERR                  | -> IODone, noErr

| -------------------------------------------------------------------------
| RelRspCB (csCode 249): release the RspCB of (atpSocket, addrBlock,
| transID) without waiting for TRel or the release timer; its
| SendResponse, if any, completes with noErr.  cbNotFound.
| -------------------------------------------------------------------------
RELRSPCB:
        MOVE.W  0x2E(A0),D0                     | D0 = transID
        BSR.W   ATP_FINDRSPCB                   | A1 = RspCB of (D1, D3, D0)
        BNE.B   RELTCB_NOTFOUND                 | none -> cbNotFound
        MOVEA.L 0x8(A1),A0                      | A0 = its SendResponse
        CLR.B   (A1)                            | free the RspCB
        MOVE.L  A0,D0                           | SendResponse issued?
        BEQ.B   RELRSPCB_DONE                   | no ->
        CLR.W   D0                              | noErr
        BSR.W   ATP_COMPLETE                    | complete the SendResponse
RELRSPCB_DONE:
        BRA.B   RELTCB_DONE                     | -> IODone, noErr

| -------------------------------------------------------------------------
| ATP_LISTENER_TREL: TRel (function code 11) on a responding socket - the
| requester releases an exactly-once transaction: read the other 5 header
| bytes, free the RspCB and complete its SendResponse (userData = user
| bytes of the TRel).  From ATP_LISTENER_COMMON (3 header bytes read).
| -------------------------------------------------------------------------
ATP_LISTENER_TREL:
        MOVEQ.L #0x5,D3                         | buffer: the 5 header bytes left
        JSR     0x2(A4)                         | ReadRest (into the RHA)
        BSR.W   ATP_CHKPKT                      | errors, checksum; D1 = requester, A3 = header end
        BNE.B   ATP_LISTENER_EXIT               | bad packet ->
        MOVE.L  D1,D3                           | D3 = requester address
        MOVE.W  -0x6(A3),D0                     | D0 = atpTransID
        MOVE.B  -0xA(A3),D1                     | D1 = DDP destination socket (the responding socket)
        MOVEA.L 0x1E(A2),A2                     | A2 = ATPVars
        BSR.W   ATP_FINDRSPCB                   | RspCB of the transaction?
        BNE.B   ATP_LISTENER_EXIT               | none ->
| free the RspCB, complete its SendResponse
        CLR.B   (A1)                            | free the RspCB
        MOVE.L  0x8(A1),D0                      | its SendResponse
        BEQ.B   ATP_LISTENER_EXIT               | none issued ->
        MOVEA.L D0,A0                           | A0 = SendResponse
        MOVE.L  -(A3),0x12(A0)                  | userData = atpUserData of the TRel
        CLR.W   D0                              | noErr
        BRA.W   ATP_COMPLETE                    | complete the SendResponse

| -------------------------------------------------------------------------
| ATP_LISTENER_TREQ: TReq (function code 01) on a responding socket (D2 =
| slot * 4, A5 = ATPVars, D3 = atpControl, 3 header bytes read): read the
| other 5 header bytes, then the request data into the buffer of the
| first GetRequest queued on the socket (discarded if none waits) and go
| on in ATP_LISTENER_GOTREQ.
| -------------------------------------------------------------------------
ATP_LISTENER_TREQ:
        ADD.B   D3,D3                           | bit 6 of atpControl -> N
        BPL.W   ATP_LISTENER_DISCARD            | function code 00: invalid, drop
        MOVE.W  #0x5,D3                         | 5 bytes: the rest of the ATP header
        JSR     (A4)                            | ReadPacket
        BNE.B   ATP_LISTENER_EXIT               | error -> return
| read the request into the first queued GetRequest's buffer
        MOVEA.L 0x6C(A5,D2.W),A5                | A5 = first queued GetRequest
        MOVE.L  A5,D3                           | any? (else D3 = 0: data discarded)
        BEQ.B   ATP_LISTENER_TREQREAD           | no ->
        MOVE.W  0x22(A5),D3                     | D3 = reqLength (buffer size)
        MOVEA.L 0x24(A5),A3                     | A3 = reqPointer
ATP_LISTENER_TREQREAD:
        JSR     0x2(A4)                         | ReadRest
        BSR.W   ATP_CHKPKT                      | errors, checksum; D1 = requester, A3 = header end
        BEQ.W   ATP_LISTENER_GOTREQ             | packet OK ->
ATP_LISTENER_EXIT:
        RTS                                     | return to MPP

| -------------------------------------------------------------------------
| ATP_LISTENER: DDP socket listener of the responding sockets, one 4-byte
| entry per responding-socket slot (OpenATPSkt gives slot n the listener
| ATP_LISTENER + 4 * n): D2 = n * 4, then ATP_LISTENER_COMMON.  MPP
| socket listener conventions (IM II-325..329): A2 = MPP variables, A3 ->
| next free RHA byte (after the DDP header), A4 = ReadPacket/ReadRest jump
| table, D1 = bytes left.
| -------------------------------------------------------------------------
ATP_LISTENER:
        MOVEQ.L #0x0,D2                         | slot 0
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT1:
        MOVEQ.L #0x4,D2                         | slot 1
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT2:
        MOVEQ.L #0x8,D2                         | slot 2
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT3:
        MOVEQ.L #0xC,D2                         | slot 3
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT4:
        MOVEQ.L #0x10,D2                        | slot 4
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT5:
        MOVEQ.L #0x14,D2                        | slot 5
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT6:
        MOVEQ.L #0x18,D2                        | slot 6
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT7:
        MOVEQ.L #0x1C,D2                        | slot 7
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT8:
        MOVEQ.L #0x20,D2                        | slot 8
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT9:
        MOVEQ.L #0x24,D2                        | slot 9
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT10:
        MOVEQ.L #0x28,D2                        | slot 10
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT11:
        MOVEQ.L #0x2C,D2                        | slot 11
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT12:
        MOVEQ.L #0x30,D2                        | slot 12
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT13:
        MOVEQ.L #0x34,D2                        | slot 13
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT14:
        MOVEQ.L #0x38,D2                        | slot 14
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT15:
        MOVEQ.L #0x3C,D2                        | slot 15
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT16:
        MOVEQ.L #0x40,D2                        | slot 16
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT17:
        MOVEQ.L #0x44,D2                        | slot 17
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT18:
        MOVEQ.L #0x48,D2                        | slot 18
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT19:
        MOVEQ.L #0x4C,D2                        | slot 19
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT20:
        MOVEQ.L #0x50,D2                        | slot 20
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT21:
        MOVEQ.L #0x54,D2                        | slot 21
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT22:
        MOVEQ.L #0x58,D2                        | slot 22
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT23:
        MOVEQ.L #0x5C,D2                        | slot 23
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT24:
        MOVEQ.L #0x60,D2                        | slot 24
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT25:
        MOVEQ.L #0x64,D2                        | slot 25
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT26:
        MOVEQ.L #0x68,D2                        | slot 26
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT27:
        MOVEQ.L #0x6C,D2                        | slot 27
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT28:
        MOVEQ.L #0x70,D2                        | slot 28
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT29:
        MOVEQ.L #0x74,D2                        | slot 29
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT30:
        MOVEQ.L #0x78,D2                        | slot 30
        BRA.B   ATP_LISTENER_COMMON             | -> common part
ATP_LISTENER_SLOT31:
        MOVEQ.L #0x7C,D2                        | slot 31
        NOP                                     | (fills the 4-byte entry; falls through)
| ATP_LISTENER_COMMON: check the DDP type (3 = ATP), read 3 header bytes
| over the DDP type byte (atpControl, bitmap/sequence, TID high byte; the
| TID and user bytes come out word aligned) and dispatch on the function
| code: TReq -> ATP_LISTENER_TREQ, TRel -> ATP_LISTENER_TREL, TResp
| (response to an NSendRequest sent through this socket) here.
| Called by: ATP_LISTENER and its 31 other slot entries
ATP_LISTENER_COMMON:
        MOVEQ.L #0x3,D3                         | 3 bytes
        CMPI.B  #0x3,-(A3)                      | A3 back to the DDP type byte: type 3 (ATP)?
        BNE.B   ATP_LISTENER_DISCARD            | no -> drop
        JSR     (A4)                            | ReadPacket: atpControl, atpBitmap/atpRespNo, TID high
        BNE.B   ATP_LISTENER_TRESPEXIT          | error -> return
        MOVEA.L 0x1E(A2),A5                     | A5 = ATPVars (atpVars)
        MOVE.B  -0x3(A3),D3                     | D3 = atpControl
        BPL.B   ATP_LISTENER_TOTREQ             | bit 7 clear: TReq (or invalid) ->
        ADD.B   D3,D3                           | bit 6 -> N
        BMI.B   ATP_LISTENER_TOTREL             | function code 11 = TRel ->
| function code 10 = TResp: an NSendRequest of this socket with the TID?
        ADDA.W  D2,A5                           | A5 = ATPVars + slot * 4
        MOVEA.L 0xEC(A5),A5                     | A5 = first NSendRequest of the socket
        MOVE.L  A5,D0                           | any?
        BEQ.B   ATP_LISTENER_DISCARD            | no -> drop
        MOVEQ.L #0x3,D3                         | 3 more bytes: TID low, user bytes 0-1
        JSR     (A4)                            | ReadPacket
        BNE.B   ATP_LISTENER_TRESPEXIT          | error -> return
        MOVE.W  -0x4(A3),D0                     | D0 = atpTransID
ATP_LISTENER_NSLOOP:
        CMP.W   0x16(A5),D0                     | reqTID of this NSendRequest?
        BEQ.B   ATP_LISTENER_NSFOUND            | yes ->
        MOVEA.L (A5),A5                         | next NSendRequest
        MOVE.L  A5,D3                           | any?
        BNE.B   ATP_LISTENER_NSLOOP             | yes -> compare
| ATP_LISTENER_DISCARD (ATPIgnore in Apple's source): drop the packet
| (ReadRest with buffer size 0)
| Called by: ATP_LISTENER_COMMON, ATP_LISTENER_TREQ, ATP_READRESP,
| ATP_REQLISTENER
ATP_LISTENER_DISCARD:
        CLR.W   D3                              | buffer size 0
        JMP     0x2(A4)                         | ReadRest: discard the rest, return to MPP
ATP_LISTENER_TOTREQ:
        BRA.W   ATP_LISTENER_TREQ               | -> TReq
ATP_LISTENER_TOTREL:
        BRA.W   ATP_LISTENER_TREL               | -> TRel
| the NSendRequest A5 of the TID: read the last 2 header bytes
ATP_LISTENER_NSFOUND:
        MOVEQ.L #0x2,D3                         | 2 bytes: user bytes 2-3
        JSR     (A4)                            | ReadPacket
        BNE.B   ATP_LISTENER_TRESPEXIT          | error -> return
| ATP_READRESP (ReadResp in Apple's source): TResp for request A5
| (SendRequest or NSendRequest; whole ATP header read, A3 -> its end):
| read the data straight into the BDS buffer of the response number.
| Bug (fixed by the System patch PMAB301, 11/1987): for a SendRequest the
| data is read before ATP_LISTENER_GOTRSP checks the TID, so a delayed
| duplicate response of an earlier transaction overwrites the BDS buffer
| (an NSendRequest is found by its TID first).  The patch installs its
| own SendRequest listener that checks the TID and then jumps here.
ATP_READRESP:
        MOVE.B  -0x7(A3),D3                     | D3 = atpRespNo
        CMP.B   0x2C(A5),D3                     | >= numOfBuffs?
        BCC.B   ATP_LISTENER_DISCARD            | yes -> drop
| BDS entry = bdsPointer + 12 * atpRespNo
        ASL.W   #0x2,D3                         | * 4
        MOVE.W  D3,D0                           | D0 = 4 * n
        ADD.W   D0,D3                           | 8 * n
        ADD.W   D0,D3                           | 12 * n
        MOVEA.L 0x28(A5),A3                     | A3 = bdsPointer
        ADDA.W  D3,A3                           | A3 -> BDS entry
        MOVE.W  (A3)+,D3                        | D3 = bdsBuffSz
        MOVEA.L (A3)+,A3                        | A3 = bdsBuffAdr
| ReadRest into the buffer
        MOVE.L  A5,-(SP)                        | save the request
        JSR     0x2(A4)                         | ReadRest (D3 = bytes not filled)
        BSR.W   ATP_CHKPKT                      | errors, checksum; D1 = responder, A3 = header end
        MOVEA.L (SP)+,A0                        | A0 = the request
        BEQ.B   ATP_LISTENER_GOTRSP             | packet OK ->
| Called by: ATP_LISTENER_COMMON, ATP_LISTENER_NSFOUND, ATP_REQLISTENER,
| ATP_LISTENER_GOTRSP (bad packet or not for us)
ATP_LISTENER_TRESPEXIT:
        RTS                                     | return to MPP

| -------------------------------------------------------------------------
| ATP_REQLISTENER: DDP socket listener of the private sockets of the
| SendRequests (one per request slot): only TResp packets count; finds the
| request slot of the destination socket (D2 = slot * 4, A5 = its
| SendRequest) and goes on in ATP_READRESP (no TID check first: see
| there).
| -------------------------------------------------------------------------
ATP_REQLISTENER:
        MOVEQ.L #0x8,D3                         | atpHdSz = 8 bytes
        CMPI.B  #0x3,-(A3)                      | A3 back to the DDP type byte: type 3 (ATP)?
        BNE.B   ATP_LISTENER_DISCARD            | no -> drop
        JSR     (A4)                            | ReadPacket: the ATP header (over the type byte)
        BNE.B   ATP_LISTENER_TRESPEXIT          | error -> return
        MOVEA.L 0x1E(A2),A5                     | A5 = ATPVars
        MOVE.B  -0xA(A3),D0                     | D0 = DDP destination socket
        MOVE.B  -0x8(A3),D2                     | D2 = atpControl
        BPL.B   ATP_LISTENER_DISCARD            | TReq: not on a request socket -> drop
        ADD.B   D2,D2                           | bit 6 -> N
        BMI.B   ATP_LISTENER_DISCARD            | TRel -> drop
| find the request slot of the socket
        MOVEQ.L #0xB,D2                         | 12 request slots
        LEA.L   0x10(A5),A5                     | A5 -> end of the request sockets (ATPVars+$10)
ATP_REQLISTENER_LOOP:
        CMP.B   -(A5),D0                        | socket of this request?
        DBEQ.W  D2,ATP_REQLISTENER_LOOP         | no -> next
        BNE.B   ATP_LISTENER_DISCARD            | none -> drop
        SUBA.W  D2,A5                           | A5 = ATPVars+$04
        LSL.W   #0x2,D2                         | slot * 4
        ADDA.W  D2,A5                           | A5 = ATPVars+$04 + slot * 4
        MOVEA.L 0xC(A5),A5                      | A5 = SendRequest of the slot (ATPVars+$10 + slot * 4)
        BRA.B   ATP_READRESP                    | read the response

| -------------------------------------------------------------------------
| ATP_LISTENER_GOTRSP: a response read for request A0 (D1 = responder,
| D3 = bytes not filled, A3 -> end of the ATP header in the RHA, D2 =
| slot * 4: request slot or responding-socket slot).  It must come from
| addrBlock with the reqTID; then bdsDataSz/bdsUserData, currBitmap,
| numOfResps, EOM; STS -> resend the TReq; all responses there -> free the
| slot (SendRequest) or dequeue (NSendRequest), send TRel if XO, close a
| SendRequest's socket and complete the request.
| -------------------------------------------------------------------------
ATP_LISTENER_GOTRSP:
        MOVEA.L 0x1E(A2),A2                     | A2 = ATPVars
        LEA.L   0x1E(A0),A1                     | A1 -> its addrBlock
        EXG     D1,D3                           | D3 = responder address
        BSR.W   ATP_CMPADDR                     | same?
        EXG     D1,D3                           | D1 = address, D3 = bytes not filled
        BNE.B   ATP_LISTENER_TRESPEXIT          | no -> ignore
| and carry the TID of the request
        MOVE.L  -(A3),D1                        | D1 = atpUserData
        MOVE.W  -(A3),D0                        | D0 = atpTransID
        CMP.W   0x16(A0),D0                     | reqTID of the request?
        BNE.B   ATP_LISTENER_TRESPEXIT          | no -> ignore
| store bdsDataSz and bdsUserData of the response
        MOVE.B  -(A3),D0                        | D0 = atpRespNo
        CMPI.B  #0x7,D0                         | 0..7?
        BHI.B   ATP_LISTENER_TRESPEXIT          | no -> ignore
        EXT.W   D0                              | word
        MULU.W  #0xC,D0                         | BDS entry offset
        MOVEA.L 0x28(A0),A1                     | A1 = bdsPointer
        ADDA.W  D0,A1                           | A1 -> BDS entry
        MOVE.W  (A1),D0                         | D0 = bdsBuffSz
        ADDQ.W  #0x6,A1                         | A1 -> bdsDataSz
        SUB.W   D3,D0                           | - bytes not filled = bytes received
        MOVE.W  D0,(A1)+                        | bdsDataSz
        MOVE.L  D1,(A1)+                        | bdsUserData = atpUserData
| clear the bit of this response in currBitmap
        LEA.L   0x1C(A0),A1                     | A1 -> currBitmap
        MOVE.B  (A3),D3                         | D3 = atpRespNo
        SWAP.W  D2                              | remember atpRespNo ...
        MOVE.B  D3,D2                           | ... in D2 bits 23-16
        SWAP.W  D2                              | (D2.W = slot * 4 again)
        SUBQ.W  #0x1,A3                         | A3 -> atpControl
        BCLR    D3,(A1)                         | clear its bit
        BEQ.B   ATP_LISTENER_STS                | was clear: duplicate ->
        ADDQ.B  #0x1,0x2E(A0)                   | numOfResps + 1
| EOM: no responses beyond this one
        MOVEQ.L #0x4,D1                         | atpEOMBit (4)
        BTST    D1,(A3)                         | EOM in atpControl?
        BEQ.B   ATP_LISTENER_STS                | no ->
ATP_LISTENER_EOMLOOP:
        BCLR    D3,(A1)                         | clear the bits of response D3 ...
        ADDQ.B  #0x1,D3                         | ... and all higher ones
        CMPI.B  #0x8,D3                         | up to bit 7
        BNE.B   ATP_LISTENER_EOMLOOP            | loop
        BSET    D1,0x1D(A0)                     | set EOM in atpFlags
| STS set in the response: resend the TReq with the bitmap still missing
ATP_LISTENER_STS:
        MOVE.B  -0x2(A3),D1                     | D1 = DDP destination socket (our request socket)
        BTST    #0x3,(A3)                       | atpSTSBit (3) set?
        BEQ.B   ATP_LISTENER_ALLRCVD            | no ->
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_LISTENER_ALLRCVD            | none -> skip
        MOVEA.L D2,A1                           | A1 = D2 (kept across ATP_SENDPKT)
        BSR.W   ATP_BUILDTREQ                   | TReq header, D3 = addrBlock, D0/D2 = request data
        BSR.B   ATP_SCCENABLE                   | allow SCC interrupts again
        BSR.W   ATP_SENDPKT                     | WriteDDP; resumes here when done
        BSR.W   ATP_FREECB                      | release the CB
        MOVE.L  A1,D2                           | D2 = slot * 4, atpRespNo in bits 23-16
| all responses received? then the transaction is complete
ATP_LISTENER_ALLRCVD:
        TST.B   0x1C(A0)                        | currBitmap = 0?
        BNE.B   ATP_SCCENABLE_EXIT              | no, wait for more -> return
        BSR.W   ATP_GETCB                       | A3 = free CB
        BEQ.B   ATP_LISTENER_REQDONE            | got one ->
| no CB free: set the bit of this response again, so that the transaction
| ends when the response comes again (the TReq retransmission asks for
| it; numOfResps then counts it twice)
        SWAP.W  D2                              | D2.B = atpRespNo
        BSET    D2,0x1C(A0)                     | its bit in currBitmap again
        BRA.B   ATP_SCCENABLE_EXIT              | -> return
| free the slot (SendRequest) or dequeue (NSendRequest)
ATP_LISTENER_REQDONE:
        MOVE.W  0x16(A0),0x62(A3)               | atpTransID of the TRel = reqTID
        LSR.W   #0x2,D2                         | D2 = slot
        CMPI.W  #0xF8,csCode(A0)                | an NSendRequest (248)?
        BNE.B   ATP_LISTENER_FREESLOT           | no ->
        BSR.W   ATP_UNLINKNSREQ                 | remove it from the socket's queue
        BRA.B   ATP_LISTENER_XO                 | ->
ATP_LISTENER_FREESLOT:
        CLR.B   0x4(A2,D2.W)                    | free the request slot
ATP_LISTENER_XO:
        BSR.B   ATP_SCCENABLE                   | allow SCC interrupts again
| exactly-once: send TRel to the responder
        BTST    #0x5,0x1D(A0)                   | atpFlags: XO?
        BEQ.B   ATP_LISTENER_CLOSE              | no ->
        MOVE.L  0x1E(A0),D3                     | D3 = addrBlock (responder)
        MOVE.B  #0xC0,0x60(A3)                  | atpControl = $C0 (TRel)
        CLR.L   0x64(A3)                        | atpUserData = 0
        CLR.W   D0                              | no data
        BSR.W   ATP_SENDPKT                     | send the TRel; resumes here when done
| close the private socket of a SendRequest
ATP_LISTENER_CLOSE:
        CMPI.W  #0xF8,csCode(A0)                | an NSendRequest (248)?
        BEQ.B   ATP_LISTENER_COMPLETE           | yes: its socket stays open ->
        MOVE.W  #0xF7,D0                        | csCode 247 = CloseSkt
        BSR.W   ATP_MPPCALL                     | close the request socket; resumes here when done
ATP_LISTENER_COMPLETE:
        BSR.W   ATP_FREECB                      | release the CB
        CLR.W   D0                              | noErr
        BRA.W   ATP_COMPLETE                    | complete the request

| -------------------------------------------------------------------------
| ATP_SCCENABLE: SR = vSCCEnable (MPP variables +$1C): allow SCC
| interrupts during the post-processing of a received packet
| Called by ATP_LISTENER_STS, ATP_LISTENER_XO, ATP_LISTENER_RESEND.
| -------------------------------------------------------------------------
ATP_SCCENABLE:
        MOVE.L  A1,-(SP)                        | save A1
        MOVEA.L (ABusVars).W,A1                 | A1 = MPP variables
        MOVE.W  0x1C(A1),SR                     | SR = vSCCEnable
        MOVEA.L (SP)+,A1                        | restore A1
ATP_SCCENABLE_EXIT:
        RTS                                     | return from ATP_SCCENABLE

| -------------------------------------------------------------------------
| ATP_LISTENER_GOTREQ: request read on a responding socket (A3 -> end of
| the ATP header in the RHA, D1 = requester address, D2 = socket slot *
| 4, D3 = bytes not filled).  Exactly-once: a known transaction (RspCB
| present) is a retransmitted request -> ATP_LISTENER_RESEND; a new one
| gets an RspCB when a GetRequest waits.  Then ATP_LISTENER_DELIVER.
| -------------------------------------------------------------------------
ATP_LISTENER_GOTREQ:
        MOVEA.L 0x1E(A2),A2                     | A2 = ATPVars
        MOVEA.L -(A3),A1                        | A1 = atpUserData
        MOVE.W  -(A3),D0                        | D0 = atpTransID
| exactly-once request?
        BTST    #0x5,-0x2(A3)                   | atpXOBit (5) in atpControl?
        BEQ.B   ATP_LISTENER_TODELIVER          | no -> deliver it
| known transaction?
        MOVEM.L D0-D4/A1/A3,-(SP)               | save registers
        MOVE.L  D1,D3                           | D3 = requester address
        MOVE.B  -0x4(A3),D1                     | D1 = DDP destination socket (responding socket)
        MOVE.W  D2,D4                           | D4 = socket slot * 4
        BSR.W   ATP_FINDRSPCB                   | RspCB of (socket, requester, TID)?
        BEQ.B   ATP_LISTENER_RESEND             | yes: request retransmitted ->
| new transaction: allocate an RspCB if a GetRequest waits
        TST.L   0x6C(A2,D4.W)                   | GetRequest queued on the socket?
        BEQ.B   ATP_LISTENER_XODONE             | no -> no RspCB
        LEA.L   0x1EC(A2),A1                    | A1 = first RspCB
        MOVEQ.L #0xF,D2                         | 16 RspCBs
ATP_LISTENER_RSPCBLOOP:
        TST.B   (A1)                            | free?
        BEQ.B   ATP_LISTENER_NEWRSPCB           | yes ->
        ADDA.W  #0xC,A1                         | next RspCB (12 bytes)
        DBF.W   D2,ATP_LISTENER_RSPCBLOOP       | loop
| no RspCB free: ignore the request (the requester retries)
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore registers
        RTS                                     | return to MPP
| fill in the free RspCB at A1
ATP_LISTENER_NEWRSPCB:
        MOVE.B  D1,(A1)+                        | +0 responding socket
        CLR.B   (A1)+                           | +1 release timer = 0
        MOVE.L  D3,(A1)+                        | +2 requester address
        MOVE.W  D0,(A1)+                        | +6 TID
        CLR.L   (A1)+                           | +8 no SendResponse yet
ATP_LISTENER_XODONE:
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore registers
| deliver the request
ATP_LISTENER_TODELIVER:
        BRA.B   ATP_LISTENER_DELIVER            | -> first queued GetRequest

| -------------------------------------------------------------------------
| ATP_LISTENER_RESEND: retransmitted exactly-once request - resend the
| response packets it asks for (atpBitmap) from the BDS of the pending
| SendResponse (entries with bdsDataSz <> 0); A1 = RspCB
| -------------------------------------------------------------------------
ATP_LISTENER_RESEND:
        MOVEA.L A1,A0                           | A0 = RspCB
        MOVEM.L (SP)+,D0-D4/A1/A3               | restore registers
        MOVE.L  D1,D3                           | D3 = requester address
        MOVE.B  -0x4(A3),D1                     | D1 = responding socket
        CLR.B   0x1(A0)                         | restart the release timer
        MOVE.L  0x8(A0),D2                      | D2 = SendResponse of the RspCB
        BEQ.B   ATP_LISTENER_RTS                | none yet -> nothing to resend
| D1.B = requested bitmap (socket in the high word), A1 = BDS
        SWAP.W  D1                              | socket to the high word
        MOVE.B  -(A3),D1                        | D1.B = atpBitmap of the request
        MOVEA.L D2,A0                           | A0 = SendResponse
        MOVEA.L 0x28(A0),A1                     | A1 = its bdsPointer
        MOVE.W  D0,D2                           | D2 = TID
        BSR.W   ATP_GETCB                       | A3 = free CB
        BNE.B   ATP_LISTENER_RTS                | none -> give up
| TResp header with sequence number -1 (incremented per entry)
        MOVE.B  #0x80,0x60(A3)                  | atpControl = $80 (TResp)
        ST.B    0x61(A3)                        | atpRespNo = $FF
        MOVE.W  D2,0x62(A3)                     | atpTransID = TID
        BSR.W   ATP_SCCENABLE                   | allow SCC interrupts again
| one pass per BDS entry
ATP_LISTENER_RESENDLOOP:
        ADDQ.B  #0x1,0x61(A3)                   | next sequence number
        MOVE.B  0x61(A3),D0                     | D0 = sequence number
        SUB.B   0x2C(A0),D0                     | >= numOfBuffs?
        BGE.W   ATP_FREECB                      | yes: done, release the CB and return
        ADDQ.B  #0x1,D0                         | last packet?
        BNE.B   ATP_LISTENER_RESENDBDS          | no ->
        MOVE.B  0x1D(A0),D0                     | SendResponse atpFlags
        OR.B    D0,0x60(A3)                     | add them (EOM) to atpControl
ATP_LISTENER_RESENDBDS:
| take the BDS entry; send it if requested and present
        MOVE.W  (A1)+,D0                        | D0 = bdsBuffSz
        MOVE.L  (A1)+,D2                        | D2 = bdsBuffAdr
        ADDQ.W  #0x2,A1                         | skip bdsDataSz
        MOVE.L  (A1)+,0x64(A3)                  | atpUserData = bdsUserData
        LSR.W   #0x1,D1                         | next bitmap bit -> C
        BCC.B   ATP_LISTENER_RESENDLOOP         | not requested -> next
        TST.W   -0x6(A1)                        | bdsDataSz = 0 (not supplied yet)?
        BEQ.B   ATP_LISTENER_RESENDLOOP         | yes -> next
| send it
        SWAP.W  D1                              | D1.W = socket
        BSR.W   ATP_SENDPKT                     | WriteDDP; resumes here when done
        SWAP.W  D1                              | D1.B = bitmap
        BRA.B   ATP_LISTENER_RESENDLOOP         | next entry
| return to MPP
| Called by: ATP_LISTENER_RESEND, ATP_LISTENER_DELIVER (no GetRequest,
| filtered out)
ATP_LISTENER_RTS:
        RTS                                     | return from the listener

| -------------------------------------------------------------------------
| ATP_LISTENER_DELIVER: complete the first GetRequest queued on the
| socket with the request: userData, bitMap, transID, atpFlags =
| atpControl, addrBlock = requester, reqLength = request size; dropped
| if no GetRequest waits or the requester fails the addrBlock filter.
| -------------------------------------------------------------------------
ATP_LISTENER_DELIVER:
        MOVE.L  0x6C(A2,D2.W),-(SP)             | first queued GetRequest
        MOVEA.L (SP)+,A0                        | A0 = it (test for nil)
        BEQ.B   ATP_LISTENER_RTS                | none -> drop the request
| return the request fields
        MOVE.L  A1,0x12(A0)                     | userData = atpUserData
        MOVE.B  -(A3),0x2C(A0)                  | bitMap = atpBitmap
        MOVE.W  D0,0x2E(A0)                     | transID = atpTransID
        LEA.L   0x1D(A0),A1                     | A1 -> atpFlags
        MOVE.B  -(A3),(A1)+                     | atpFlags = atpControl (XO bit)
        MOVE.L  D1,(A1)                         | addrBlock = requester address
| check the requester against the addrBlock filter of the socket
        LEA.L   0x16C(A2),A3                    | A3 -> addrBlock filters (ATPVars+$16C)
        ADDA.W  D2,A3                           | A3 -> filter of this socket (from OpenATPSkt)
        CMPM.W  (A1)+,(A3)+                     | same network?
        BEQ.B   ATP_LISTENER_FILTNODE           | yes ->
        TST.W   -0x2(A3)                        | filter network = 0 (any)?
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
        SUB.W   D3,(A1)                         | reqLength -= bytes not filled
        MOVE.L  (A0),0x6C(A2,D2.W)              | dequeue the GetRequest
        BRA.W   ATP_COMPLETE                    | complete it (D0 = noErr)

| -------------------------------------------------------------------------
| ATP_CHKPKT: after ReadRest (Z = no error): verify the DDP checksum of a
| long-header packet (if nonzero) and return D1 = source address (net.W,
| node.B, socket.B; net 0 for a short header), A3 -> end of the ATP header
| in the RHA, Z set if all is well.  A2 = MPP variables, RHA at A2+1
| (the DDP type byte holds atpControl).
| Called by: ATP_LISTENER_TREL, ATP_LISTENER_TREQ, ATP_READRESP
| -------------------------------------------------------------------------
ATP_CHKPKT:
        BNE.B   ATP_CHKPKT_EXIT                 | ReadRest error -> NE
        MOVEQ.L #0x0,D1                         | D1 = 0 (network 0)
        LEA.L   0x2(A2),A0                      | A0 -> lapSrcAdr in the RHA
        MOVE.B  0x7(A2),D0                      | D0 = sDDPSrcSkt (short header)
        MOVE.B  (A0)+,D1                        | D1 = lapSrcAdr (source node)
        SUBQ.B  #0x1,(A0)+                      | lapType = 1 (shortDDP)? (byte destroyed)
        BEQ.B   ATP_CHKPKT_SHORT                | yes -> address complete
| long header: checksum
        MOVEM.L D2-D4,-(SP)                     | save D2-D4
        MOVE.W  (A0)+,D1                        | D1 = ddpLength (hop count + length)
        MOVE.W  (A0)+,D4                        | D4 = ddpChecksum
        BEQ.B   ATP_CHKPKT_RESTORE              | 0: not checksummed -> OK
| checksum the header from ddpDstNet to ddpSrcSkt, the type byte
        MOVEQ.L #0x8,D2                         | 8 bytes
        CLR.W   D3                              | checksum = 0
        BSR.B   ATP_CHECKSUM                    | add them
        ADDQ.W  #0x3,D3                         | DDP type 3 (its RHA byte now holds atpControl)
        ROL.W   #0x1,D3                         | rotate as in ATP_CHECKSUM
| the ATP header
        MOVEQ.L #0x8,D2                         | 8 bytes
        BSR.B   ATP_CHECKSUM                    | add them
| the data (D1 bytes ending at A3)
        ANDI.W  #0x3FF,D1                       | datagram length (ddpLenMask)
        SUBI.W  #0x15,D1                        | - 13 (DDP header) - 8 (ATP header)
        BEQ.B   ATP_CHKPKT_ZERO                 | no data ->
        MOVEA.L A3,A0                           | A0 = end of the data read
        SUBA.W  D1,A0                           | A0 -> start of the data
        MOVE.W  D1,D2                           | D2 = data length
        BSR.B   ATP_CHECKSUM                    | add them
| a computed 0 is sent as $FFFF
ATP_CHKPKT_ZERO:
        TST.W   D3                              | computed checksum = 0?
        BNE.B   ATP_CHKPKT_COMPARE              | no ->
        SUBQ.W  #0x1,D3                         | yes: use $FFFF
ATP_CHKPKT_COMPARE:
        CMP.W   D4,D3                           | = ddpChecksum?
ATP_CHKPKT_RESTORE:
        MOVEM.L (SP)+,D2-D4                     | restore D2-D4
        BNE.B   ATP_CHKPKT_EXIT                 | checksum error -> NE
| source address from the long header
        MOVE.L  0xA(A2),D1                      | ddpSrcNet.W, ddpDstNode, ddpSrcNode
        MOVE.B  0xD(A2),D1                      | ddpSrcNode (already in the low byte)
        MOVE.B  0xF(A2),D0                      | D0 = ddpSrcSkt
        LEA.L   0x18(A2),A3                     | A3 -> end of the ATP header (RHA+$17, after a long header)
        BRA.B   ATP_CHKPKT_ADDR                 | ->
ATP_CHKPKT_SHORT:
        LEA.L   0x10(A2),A3                     | A3 -> end of the ATP header (RHA+$F, after a short header)
ATP_CHKPKT_ADDR:
        LSL.W   #0x8,D1                         | source node to bits 15-8
        MOVE.B  D0,D1                           | source socket to bits 7-0
        CLR.W   D0                              | noErr (Z set)
ATP_CHKPKT_EXIT:
        RTS                                     | return from ATP_CHKPKT

| -------------------------------------------------------------------------
| ATP_CHECKSUM: DDP checksum over D2 bytes at (A0)+: D3 = (D3 + byte)
| rotated left one bit, per byte.  D0 must have bits 15-8 clear.
| Called by ATP_CHKPKT (three times).
| -------------------------------------------------------------------------
ATP_CHECKSUM:
        MOVE.B  (A0)+,D0                        | next byte
        ADD.W   D0,D3                           | add it
        ROL.W   #0x1,D3                         | rotate left one bit
        SUBQ.W  #0x1,D2                         | count
        BNE.B   ATP_CHECKSUM                    | loop
        RTS                                     | return from ATP_CHECKSUM

| -------------------------------------------------------------------------
| ATP_GETCB: claim a free CB for a call to .MPP (interrupts off while the
| five CBs are searched) -> A3 = CB, D0 = noErr (EQ), or D0 = noDataArea
| (NE, all five busy).  A CB is free when its ioRefNum is 0; claiming it
| stores the .MPP refNum there.  Preserves D1.  (GetDataArea in Apple's
| source; the Mac Plus version searched with interrupts on, fixed there by
| a System patch.)
| Called by: E_ATP_Close, OPENATPSKT, CLOSEATPSKT, SENDRESPONSE,
| ADDRESPONSE, ATP_SNDRQINIT, ATP_VBLTASK, RELTCB_FOUND, ATP_LISTENER_STS,
| ATP_LISTENER_ALLRCVD, ATP_LISTENER_RESEND
| -------------------------------------------------------------------------
ATP_GETCB:
        MOVEA.L (ABusVars_dce).W,A3             | A3 = .MPP DCE (AbusDCE)
        MOVE.W  dCtlRefNum(A3),D0               | D0 = .MPP refNum
        LEA.L   0x2C0(A2),A3                    | A3 = first CB (ATPVars+$2C0)
        MOVE.L  D1,-(SP)                        | save D1
        MOVEQ.L #0x5,D1                         | 5 CBs
        MOVE.W  SR,-(SP)                        | save SR
        MOVE.W  #0x2600,SR                      | interrupts off (IPL 6)
ATP_GETCB_LOOP:
        TST.W   ioRefNum(A3)                    | in use?
        BEQ.B   ATP_GETCB_CLAIM                 | no -> take it
        ADDA.W  #0x68,A3                        | next CB ($68 bytes)
        SUBQ.W  #0x1,D1                         | count
        BNE.B   ATP_GETCB_LOOP                  | loop
        MOVE.W  #-0x450,D0                      | noDataArea (-1104): too many outstanding calls
ATP_GETCB_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        MOVE.L  (SP)+,D1                        | restore D1
        TST.W   D0                              | condition codes = result
        RTS                                     | return from ATP_GETCB
| mark CB A3 as in use
ATP_GETCB_CLAIM:
        MOVE.W  D0,ioRefNum(A3)                 | ioRefNum = .MPP refNum (in use)
        CLR.W   D0                              | noErr (Z set)
        BRA.B   ATP_GETCB_EXIT                  | -> return

| -------------------------------------------------------------------------
| ATP_FREECB: release CB A3
| Called by: OPENATPSKT, CLOSEATPSKT, SENDRESPONSE, ADDRESPONSE,
| SENDREQUEST, NSENDREQUEST, ATP_VBLTASK, RELTCB_FOUND, ATP_LISTENER
| -------------------------------------------------------------------------
ATP_FREECB:
        CLR.W   ioRefNum(A3)                    | ioRefNum = 0 (free)
        RTS                                     | return from ATP_FREECB
    ROM_RESOURCE_END DRVR_10                    | end of the data: pads to even, sets the sizes

