| =========================================================================
| DRVR 40 .XPP -- AppleTalk Session Protocol (workstation end) and AFP
| =========================================================================
| ROM offsets +0x37020..+0x37A27: an 8-byte ROM resource header and the
| $A00-byte driver at +0x37028 (MacSEROM.lst: _DRVR_40_.XPP), identical in
| both SE ROMs. The Mac Plus ROM has no .XPP; the SE ROM is the first to
| carry it.
|
| The "Extended Protocol Package" driver (Inside Macintosh V-523..V-550)
| implements the workstation end of the AppleTalk Session Protocol (ASP,
| version $0100) and the small part of the AppleTalk Filing Protocol (AFP)
| that is more than a one-to-one ASP call (login, logout, read, write).
| It runs on top of the .ATP driver: every network operation is an
| asynchronous _Control call to .ATP (refNum -11, XPP_CALLATP) with an ATP
| parameter block that lives in the caller's session control block (SCB)
| or in the command control block (CCB) at the end of the caller's
| parameter block (ccbStart). Driver version 5 (byte after the name; Open
| also stores it in DCtlQueue+1). This 1987 version knows csCodes 247..255
| only (no xCall, csCode 246, of the later drivers).
|
| Entry points (Device Manager: A0 = parameter block, A1 = DCE, D0 = 0):
|   Open     E_XPP_Open: only with AppleTalk on port B (PortBUse use type
|            useATalk, else portInUse); creates the AppleTalk Global Block
|            (AGBHandle) if there is none, allocates the 48-byte driver
|            variables, sets xppLoadedBit (5) in PortBUse. Opening an open
|            driver just returns noErr (and the refNum).
|   Close    E_XPP_Close: closErr while a session exists; else clears
|            xppLoadedBit and the AGB's xppVarPtr (the variables are not
|            disposed).
|   Control  E_XPP_Control: calls the AGB's xppHook (a patch hook) first,
|            ignores KillIO (csCode 1) and dispatches csCode 247..255:
|              247 closeAll     XPP_CLOSEALL    ASPCloseAll
|              248 abortOS      XPP_ABORTOS     ASPAbortOS
|              249 getParms     XPP_GETPARMS    ASPGetParms
|              250 afpCall      XPP_AFPCALL     AFPCommand
|              251 getStatus    XPP_GETSTATUS   ASPGetStatus
|              252 userWrite    XPP_USERCMD     ASPUserWrite
|              253 userCommand  XPP_USERCMD     ASPUserCommand
|              254 closeSess    XPP_CLOSESESS   ASPCloseSession
|              255 openSess     XPP_OPENSESS    ASPOpenSession
|            any other csCode: controlErr.
|   Prime, Status: not enabled in drvrFlags; the stub only clears
|            drvrActive.
|
| Call handling: a call that has to wait for the network is taken out of
| the driver's I/O queue as soon as it is under way (XPP_DEQUEUE, which
| starts the next queued call at once), linked into its session's list of
| active calls (scbCallList, through qLink) and completed later by
| XPP_COMPLETE, which sets ioResult and calls ioCompletion itself, as .ATP
| does. Calls that are answered at once (errors, GetParms) and AbortOS and
| CloseAll, which stay at the head of the queue until they are done,
| complete through jIODone (XPP_DONE). The high byte of csCode is used
| internally: $FF marks an AFPCommand in progress; its low byte is then
| the ASP call the AFP command is mapped to ($FC userWrite, $FD
| userCommand, $FE closeSess, $FF openSess).
|
| AppleTalk Global Block (AGB; AGBHandle $D1C, -1 = none yet; Apple's
| ATalkPrivateEQU.a), $10 bytes:
|   +0  xppVarPtr   the driver variables (0 = .XPP closed)
|   +4  xppHook     patch hook: called on every Control call and AFP step
|   +8  atpHook     .ATP's patch hook                +$C  filler
| Driver variables (at xppVarPtr, $30 bytes, NewPtrSysClear):
|   +0  xppDCE      the driver's DCE
|   +4  xppGen      (byte) generation count: high byte of the next sessRefnum
|   +6  xppMaxSess  (byte) number of session slots: 10 (GetParms numSesss)
|   +8  xppSessTbl  10 longs: the SCB of each session slot (0 = free)
| sessRefnum = generation * 256 + 4 * slot number.
|
| Session control block (SCB; caller's memory, scbMemSize = $C0 bytes):
|   +$00 scbAttnBytes (word) attention bytes of the last Attention
|   +$02 scbState     (byte) 1 opening, 2 open, 3 open being aborted,
|                     5 closing, 6 closed by the server or timed out
|                     (cleared to 0 when the session is set up)
|   +$03 scbSessID    (byte) session ID from the OpenSessReply
|   +$04 scbRefnum    (word) sessRefnum
|   +$06 scbWSS       (byte) workstation session socket (WSS)
|   +$07 scbSLSSkt    (byte) socket number of the server's SLS
|   +$08 scbSrvAddr   (long) server address: net.W, node.B, socket.B --
|                     the SLS while opening, the SSS once open
|   +$0C scbSeqNum    (word) next Command/Write sequence number
|   +$0E scbWrBSize   (word) GetRequest buffer: WriteContinue buffer size
|   +$10 scbATPPB     ATP parameter block: the tickle request; KillSendReq
|                     of AbortOS; CloseSess, KillSendReq, RelRspCB and
|                     CloseATPSkt while closing
|   +$42 scbReqPB     ATP parameter block: OpenATPSkt and OpenSess while
|                     opening; then the GetRequest on the WSS that
|                     receives the server's requests, and its responses
|   +$74 scbVBL       VBL task: session timer (tickleTime = 2 minutes)
|   +$82 scbCallList  (long) list of the session's active calls
|   +$86 scbAuxPB     ATP parameter block: KillSendReq of the tickle;
|                     else a one-entry BDS (OpenSessReply, CloseSess reply,
|                     response to the server's CloseSess) or, after a
|                     failed open, the result code
|   +$B8 scbAttnRtn   (long) attention routine (0 = none)
| Command control block (CCB, at ccbStart = $32 of the XPP parameter block
| of a UserCommand, UserWrite, GetStatus or AFPCommand call):
|   +$00          ATP parameter block of the request
|   +$32          reply BDS: n1 = MIN(rbSize DIV 578 + 1, 8) entries
|   UserWrite only:
|   +$32+12*n1    ATP parameter block of the write data (SendResponse to
|                 the server's WriteContinue); reqLength = size to write,
|                 reqPointer = the XPP parameter block
|   +$64+12*n1    write data BDS: n2 = MIN(wdSize DIV 578 + 1, 8) entries
|
| ASP packets (ATP requests; user bytes in [], Inside AppleTalk's names):
|   OpenSess       WS->SLS  XO   [aspOpenSess 4, WSS, version $0100.W]
|     OpenSessReply              [SSS, session ID, error code.W]
|   CloseSess      WS->SSS  ALO  [aspCloseSess 1, session ID, 0.W]
|                  SRV->WSS      answered with an empty response
|   Command        WS->SSS  XO   [aspCommand 2, session ID, seq.W] + command
|     CmdReply                   cmdResult (user bytes) + up to 8 packets
|   Write          WS->SSS  XO   [aspWrite 6, session ID, seq.W] + command
|   WriteContinue  SRV->WSS XO   [aspDataWrite 7, session ID, seq.W] +
|                                buffer size.W; response: the write data
|     WriteReply                 cmdResult (user bytes) + reply data
|   GetStatus      WS->SLS  ALO  [aspGetStat 3, 0, 0.W]; reply: status
|   Tickle         WS->SLS  ALO  [aspTickle 5, session ID, 0.W], resent
|                                every 30 s forever, never answered
|   Attention      SRV->WSS ALO  [aspAttention 8, session ID, code.W];
|                                answered with an empty AddResponse
| A request from the server counts only with the session's ID and from
| the server's node (and net, if both are known); each one, like each
| command reply, restarts the session timer, which closes the session
| after 2 minutes without a sign of the server.
|
| AFPCommand (csCode 250); the first byte of the command block is the AFP
| command:
|   0, 15 (GetSrvrInfo: use GetStatus), 255   afpParmErr; cbSize 0 too
|   18 FPLogin      OpenSession (afpAddrBlock, afpSCBPtr, afpAttnRoutine),
|                   then the login command as a UserCommand; when the
|                   server answers neither 0 nor afpAuthContinue in
|                   cmdResult, the session is closed again
|   19 FPLoginCont  UserCommand; failure closes the session
|   20 FPLogout     CloseSession
|   27 FPRead       UserCommands of up to quantumSize bytes until reqCount
|                   bytes are read, cmdResult is not 0 (e.g. end of file)
|                   or a chunk ends with newLineChar (newLineFlag set)
|   33 FPWrite      UserWrites of up to quantumSize bytes until reqCount
|                   bytes are written (startEndFlag handled)
|   $C0..$FE        UserWrite (wdSize, wdPtr)
|   all others      UserCommand
| rwOffset, reqCount and rbPtr/wdPtr are updated as the transfer goes
| on; reqCount returns the number of bytes moved.
|
| Suspected bugs (see the code): FPRead/FPWrite chunks after the first,
| the login command after the OpenSession and the CloseSession after a
| failed login run XPP_DEQUEUE again for a call that has already left the
| I/O queue (dCtlQHead := its stale qLink, drvrActive cleared), and errors
| found there complete through jIODone (the wrong call); FPLogin with
| cbSize > 578 returns controlErr instead of aspSizeErr.
|
| Sources: Inside Macintosh V, "The AppleTalk Manager" (calls, parameter
| block, CCB sizes, attention routine, AFP mapping); Inside Macintosh:
| Networking (ASP, AFP, ATP chapters); System 7.1 sources
| Interfaces/AIncludes/AppleTalk.a and SysErr.a (equates, error codes),
| Internal/Asm/AtalkPrivateEQU.a (AGB), Libs/InterfaceSrcs/nAppleTalk.a
| (glue). No source of this driver is available: the routine names are
| descriptive, the xpp* and scb* field names are this file's.
| =========================================================================

| -------------------------------------------------------------------------
| Equates: Apple's names and values (AppleTalk.a, SysErr.a,
| ATalkPrivateEQU.a; the include files have none of them), then the
| driver variables and the SCB (names of this file).
| -------------------------------------------------------------------------
| XPP parameter block (Inside Macintosh V-535)
.set cmdResult, 0x12                            | (long) command result: user bytes of the reply
.set sessRefnum, 0x1C                           | (word) session reference number
.set aspTimeout, 0x1E                           | (byte) retry interval in seconds
.set aspRetry, 0x1F                             | (byte) number of retries
.set serverAddr, 0x20                           | (long) server's socket address
.set scbPointer, 0x24                           | (long) session control block
.set attnRoutine, 0x28                          | (long) attention routine
.set cbSize, 0x20                               | (word) command block size
.set cbPtr, 0x22                                | (long) command block
.set rbSize, 0x26                               | (word) reply buffer size, reply size
.set rbPtr, 0x28                                | (long) reply buffer
.set wdSize, 0x2C                               | (word) write data size, size written
.set wdPtr, 0x2E                                | (long) write data
.set ccbStart, 0x32                             | command control block (driver's memory)
.set aspMaxCmdSize, 0x1C                        | (word) GetParms: largest command block
.set aspQuantumSize, 0x1E                       | (word) GetParms: largest reply/write
.set numSesss, 0x20                             | (word) GetParms: number of sessions
.set abortSCBPtr, 0x1C                          | (long) AbortOS: SCB of the OpenSession
.set afpAddrBlock, 0x2C                         | (long) FPLogin: server address
.set afpSCBPtr, 0x30                            | (long) FPLogin: session control block
.set afpAttnRoutine, 0x34                       | (long) FPLogin: attention routine
| XPP csCodes
.set closeAll, 247                              | close all sessions
.set abortOS, 248                               | abort an OpenSession
.set getParms, 249                              | get ASP parameters
.set afpCall, 250                               | AFP command
.set getStatus, 251                             | get server status
.set userWrite, 252                             | ASP Write
.set userCommand, 253                           | ASP Command
.set closeSess, 254                             | close a session
.set openSess, 255                              | open a session
| ATP parameter block
.set userData, 0x12                             | (long) ATP user bytes
.set atpSocket, 0x1C                            | (byte) socket
.set atpFlags, 0x1D                             | (byte) control flags
.set addrBlock, 0x1E                            | (long) remote socket address
.set reqLength, 0x22                            | (word) request/response data size
.set reqPointer, 0x24                           | (long) request/response data
.set bdsPointer, 0x28                           | (long) response BDS
.set numOfBuffs, 0x2C                           | (byte) SendRequest: response buffers
.set timeoutVal, 0x2D                           | (byte) SendRequest: retry interval, seconds
.set numOfResps, 0x2E                           | (byte) SendRequest: responses received
.set retryCount, 0x2F                           | (byte) SendRequest: retries, 255 = forever
.set rspNum, 0x2C                               | (byte) AddResponse: response number
.set bdsSize, 0x2D                              | (byte) SendResponse: BDS entries
.set transID, 0x2E                              | (word) GetRequest/SendResponse: transaction ID
.set aKillQEl, 0x2C                             | (long) KillSendReq: call to cancel
.set atpXOvalue, 0x20                           | atpFlags bit 5: exactly-once (XO) transaction
.set atpEOMvalue, 0x10                          | atpFlags bit 4: end of message
.set atpMaxData, 0x242                          | 578 data bytes per ATP packet
| .ATP csCodes
.set nSendRequest, 248                          | SendRequest from a given socket
.set relRspCB, 249                              | release a response control block
.set closeATPSkt, 250                           | close an ATP socket
.set addResponse, 251                           | send one response packet
.set sendResponse, 252                          | send a response
.set getRequest, 253                            | receive a request on a socket
.set openATPSkt, 254                            | open an ATP socket
.set sendRequest, 255                           | send a request
.set killSendReq, 258                           | cancel a SendRequest/NSendRequest
.set atpRefNum, -11                             | .ATP refNum: -(atpUnitNum 10 + 1)
| buffer data structure (BDS) entry
.set bdsBuffSz, 0                               | (word) buffer size
.set bdsBuffAdr, 2                              | (long) buffer
.set bdsDataSz, 6                               | (word) bytes received
.set bdsUserData, 8                             | (long) user bytes of the packet
.set bdsEntrySz, 12                             | size of a BDS entry
| ASP: offsets in the user bytes, commands, constants
.set aspSSSNum, 0                               | OpenSessReply: server session socket
.set aspWSSNum, 1                               | OpenSess: workstation session socket
.set aspSessID, 1                               | session ID (requests, OpenSessReply)
.set aspVersNum, 2                              | OpenSess: ASP version
.set aspOpenErr, 2                              | OpenSessReply: error code
.set aspSeqNum, 2                               | Command/Write/WriteContinue: sequence number
.set aspAttnCode, 2                             | Attention: attention bytes
.set aspCloseSess, 1                            | CloseSess
.set aspCommand, 2                              | Command
.set aspGetStat, 3                              | GetStatus
.set aspOpenSess, 4                             | OpenSess
.set aspTickle, 5                               | Tickle
.set aspWrite, 6                                | Write
.set aspDataWrite, 7                            | WriteContinue (from the server)
.set aspAttention, 8                            | Attention (from the server)
.set aspVersion, 0x0100                         | ASP version 1.0
.set maxCmdSize, atpMaxData                     | largest command block: 578
.set quantumSize, atpMaxData*8                  | largest reply or write: 4624
.set tickleInt, 30                              | tickle interval in seconds
.set tickleTime, tickleInt*60*4                 | session timeout: 7200 ticks
| result codes
.set badUnitErr, -21                            | bad refNum (no driver)
.set notOpenErr, -28                            | driver not open
.set portInUse, -97                             | port in use / AppleTalk not open
.set aspBufTooSmall, -1067                      | reply larger than the buffer
.set aspNoMoreSess, -1068                       | no free session slot
.set aspNoServers, -1069                        | no server answered
.set aspParamErr, -1070                         | bad session refNum / server error
.set aspSessClosed, -1072                       | session closing
.set aspSizeErr, -1073                          | command block too big
.set reqFailed, -1096                           | SendRequest: retry count exceeded
.set cbNotFound, -1102                          | control block not found
.set reqAborted, -1105                          | SendRequest aborted (KillSendReq)
.set afpAuthContinue, -5001                     | FPLogin: continue with FPLoginCont
.set afpParmErr, -5019                          | bad AFP command
| AFP commands, command block of FPRead/FPWrite, FPWrite reply
.set afpGetSInfo, 15                            | FPGetSrvrInfo
.set afpLogin, 18                               | FPLogin
.set afpContLogin, 19                           | FPLoginCont
.set afpLogout, 20                              | FPLogout
.set afpRead, 27                                | FPRead
.set afpWrite, 33                               | FPWrite
.set afpUseWrite, 0xC0                          | first command mapped to ASP Write
.set startEndFlag, 1                            | (byte) FPWrite: bit 7 = offset from the end
.set rwOffset, 4                                | (long) offset in the fork
.set reqCount, 8                                | (long) bytes to read/write, bytes moved
.set newLineFlag, 0xC                           | (byte) FPRead: bit 7 = stop at newLineChar
.set newLineChar, 0xD                           | (byte) FPRead: newline character
.set lastWritten, 0                             | (long) FPWrite reply: offset after the data
| AppleTalk Global Block, PortBUse
.set xppVarPtr, 0                               | (long) AGB: driver variables
.set xppHook, 4                                 | (long) AGB: patch hook
.set agbSize, 0x10                              | size of the AGB
.set xppLoadedBit, 5                            | PortBUse bit: .XPP open
| driver variables (this file's names)
.set xppDCE, 0                                  | (long) the driver's DCE
.set xppGen, 4                                  | (byte) sessRefnum generation count
.set xppMaxSess, 6                              | (byte) number of session slots
.set xppSessTbl, 8                              | 10 longs: SCB per slot, 0 = free
.set xppVarSize, 0x30                           | size of the variables
.set xppNumSess, 10                             | session slots
| session control block (this file's names)
.set scbAttnBytes, 0x00                         | (word) attention bytes
.set scbState, 0x02                             | (byte) session state, see below
.set scbSessID, 0x03                            | (byte) session ID
.set scbRefnum, 0x04                            | (word) sessRefnum
.set scbWSS, 0x06                               | (byte) workstation session socket
.set scbSLSSkt, 0x07                            | (byte) socket of the server's SLS
.set scbSrvAddr, 0x08                           | (long) server address (SLS, then SSS)
.set scbSeqNum, 0x0C                            | (word) next sequence number
.set scbWrBSize, 0x0E                           | (word) WriteContinue buffer size
.set scbATPPB, 0x10                             | ATP pb: tickle, closing
.set scbReqPB, 0x42                             | ATP pb: opening, GetRequest on the WSS
.set scbVBL, 0x74                               | VBL task: session timer
.set scbCallList, 0x82                          | (long) active calls of the session
.set scbAuxPB, 0x86                             | ATP pb / one-entry BDS
.set scbAttnRtn, 0xB8                           | (long) attention routine
| session states (scbState)
.set ssOpening, 1                               | OpenATPSkt/OpenSess under way
.set ssOpen, 2                                  | open
.set ssAborted, 3                               | AbortOS: OpenSession being aborted
.set ssClosing, 5                               | being closed by this end
.set ssDead, 6                                  | closed by the server or timed out

| -------------------------------------------------------------------------
| ROM resource header (8 bytes before the driver): $C0 flags + the block
| size $A08 (header + $A00 bytes of driver, so the next resource follows
| at +0x37A28); the second long rises by 4 from one ROM resource to the
| next.
| -------------------------------------------------------------------------
Resource_DRVR_0028_DotXPP:
Resource_DRVR_0028_DotXPP_Header:
    ROM_RESOURCE DRVR_40                        | 8-byte resource header (include/romrsrc.inc)

| -------------------------------------------------------------------------
| DRVR header (Inside Macintosh II-188): flags, delay, event mask, menu,
| the offsets of the five entry points, the name and the version.
| -------------------------------------------------------------------------
Driver_XPP:
_DRVR_40_.XPP:
        .short  0x4400                          | drvrFlags: dNeedLock+dCtlEnable (Control calls only)
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no desk accessory events
        .short  0x0000                          | drvrMenu: no menu
        .short  E_XPP_Open-Driver_XPP           | drvrOpen: $001A
        .short  E_XPP_PrimeStatus-Driver_XPP    | drvrPrime: $044A (not enabled)
        .short  E_XPP_Control-Driver_XPP        | drvrCtl: $0068
        .short  E_XPP_PrimeStatus-Driver_XPP    | drvrStatus: $044A (not enabled)
        .short  E_XPP_Close-Driver_XPP          | drvrClose: $00BC
        .byte   4                               | drvrName: length byte
        .ascii  ".XPP"                          | drvrName: driver name
        .byte   0                               | pad to a word boundary
        .byte   5                               | driver version 5 (Open copies it to DCtlQueue+1)
        .byte   0                               | second version byte: 0

| -------------------------------------------------------------------------
| E_XPP_Open -- driver Open (A1 = DCE).
| AppleTalk must be open on port B: PortBUse bit 7 clear (port in use) and
| use type useATalk in bits 0-3, else portInUse. Creates the AppleTalk
| Global Block if AGBHandle is still -1, allocates the driver variables
| (10 session slots), stores them in the AGB (xppVarPtr), sets
| xppLoadedBit in PortBUse and the driver version (5) in the DCE. If the
| driver is already open, nothing is done and noErr returned.
| Out: D0 = noErr, portInUse or a Memory Manager error.
| -------------------------------------------------------------------------
E_XPP_Open:
        MOVEA.L (AGBHandle).W,A0                | A0 = AGB handle
        MOVE.L  A0,D1                           | D1 = AGBHandle
        ADDQ.L  #0x1,D1                         | 0 if AGBHandle = -1: no AGB yet
        BNE.B   XPP_OPEN_HAVEAGB                | there is one ->
        MOVEQ.L #agbSize,D0                     | D0 = $10 bytes for the AGB
        _NewHandleSysClear                      | A0 = new AGB (system heap, zeroed)
        BNE.B   XPP_OPEN_EXIT                   | no memory -> return the error
        MOVE.L  A0,(AGBHandle).W                | AGBHandle = new AGB
XPP_OPEN_HAVEAGB:
        MOVEA.L (A0),A2                         | A2 = AGB
        TST.L   xppVarPtr(A2)                   | driver variables already there?
        BNE.B   XPP_OPEN_NOERR                  | yes, already open -> noErr
        MOVEQ.L #portInUse,D0                   | D0 = portInUse (-97) for the checks below
        MOVE.B  (PortBUse).W,D1                 | D1 = port B use byte
        BMI.B   XPP_OPEN_EXIT                   | bit 7 set: port not in use (no AppleTalk) ->
        ANDI.B  #0xF,D1                         | bits 0-3: use type
        SUBQ.B  #useATalk,D1                    | used by AppleTalk (useATalk = 1)?
        BNE.B   XPP_OPEN_EXIT                   | no, by something else -> portInUse
        BSET    #xppLoadedBit,(PortBUse).W      | PortBUse bit 5: .XPP open
        MOVEA.L A0,A2                           | A2 = AGB handle
        MOVEQ.L #xppVarSize,D0                  | D0 = $30 bytes of driver variables
        _NewPtrSysClear                         | A0 = driver variables (zeroed)
        BNE.B   XPP_OPEN_EXIT                   | no memory -> error (xppLoadedBit stays set)
        MOVEA.L (A2),A2                         | A2 = AGB
        MOVE.L  A0,xppVarPtr(A2)                | AGB xppVarPtr = driver variables
        MOVE.B  #0x5,dCtlQueue+1(A1)            | DCE version byte: driver version 5
        MOVE.B  #xppNumSess,xppMaxSess(A0)      | 10 session slots
        MOVE.L  A1,xppDCE(A0)                   | remember the DCE
XPP_OPEN_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
XPP_OPEN_EXIT:
        RTS                                     | return D0 to the Device Manager

| -------------------------------------------------------------------------
| E_XPP_Control -- driver Control (A0 = XPP parameter block, A1 = DCE).
| Calls the patch hook, then dispatches on csCode through XPP_CTL_TABLE;
| the handlers are entered with A0 = parameter block, A1 = DCE and
| D0 = controlErr. KillIO (csCode 1) needs no action: return D0 (noErr).
| Unknown csCodes complete with controlErr.
| Called by: the Device Manager; XPP_DEQUEUE (next queued call)
| -------------------------------------------------------------------------
E_XPP_Control:
        BSR.B   XPP_CALLHOOK                    | let a patch see the call first
        MOVE.W  csCode(A0),D2                   | D2 = csCode
        SUBQ.W  #0x1,D2                         | KillIO (csCode 1)?
        BNE.B   XPP_CTL_DISPATCH                | no ->
        RTS                                     | KillIO: nothing to do
XPP_CTL_DISPATCH:
        MOVEQ.L #controlErr,D0                  | D0 = controlErr (-17) by default
        SUBI.W  #closeAll-1,D2                  | D2 = csCode - 247 (closeAll)
        BLT.W   XPP_DONE                        | below closeAll -> controlErr
        CMPI.W  #openSess-closeAll,D2           | above openSess (255)?
        BGT.W   XPP_DONE                        | yes -> controlErr
        ADD.W   D2,D2                           | word index
        LEA.L   XPP_CTL_TABLE(PC),A3            | A3 = dispatch table
        ADDA.W  D2,A3                           | A3 -> entry for this csCode
        MOVEA.W (A3),A3                         | handler offset from the driver start
        LEA.L   Driver_XPP(PC),A2               | A2 = start of the driver
        ADDA.L  A2,A3                           | A3 = handler
        JMP     (A3)                            | -> XPP_CLOSEALL ... XPP_OPENSESS
| dispatch table: handler offsets from the driver start, csCode 247..255
XPP_CTL_TABLE:
        .short  XPP_CLOSEALL-Driver_XPP         | 247 closeAll    (ASPCloseAll)
        .short  XPP_ABORTOS-Driver_XPP          | 248 abortOS     (ASPAbortOS)
        .short  XPP_GETPARMS-Driver_XPP         | 249 getParms    (ASPGetParms)
        .short  XPP_AFPCALL-Driver_XPP          | 250 afpCall     (AFPCommand)
        .short  XPP_GETSTATUS-Driver_XPP        | 251 getStatus   (ASPGetStatus)
        .short  XPP_USERCMD-Driver_XPP          | 252 userWrite   (ASPUserWrite)
        .short  XPP_USERCMD-Driver_XPP          | 253 userCommand (ASPUserCommand)
        .short  XPP_CLOSESESS-Driver_XPP        | 254 closeSess   (ASPCloseSession)
        .short  XPP_OPENSESS-Driver_XPP         | 255 openSess    (ASPOpenSession)

| -------------------------------------------------------------------------
| XPP_CALLHOOK -- call the AGB's xppHook if a patch installed one (A0 and
| A1 as the hook's caller has them). Changes D3, A2.
| Called by: E_XPP_Control, XPP_AFP_STEP
| -------------------------------------------------------------------------
XPP_CALLHOOK:
        MOVEA.L (AGBHandle).W,A2                | A2 = AGB handle
        MOVEA.L (A2),A2                         | A2 = AGB
        MOVE.L  xppHook(A2),D3                  | D3 = patch hook
        BEQ.B   XPP_CALLHOOK_RTS                | none ->
        MOVEA.L D3,A2                           | A2 = hook
        JSR     (A2)                            | call the xppHook patch
XPP_CALLHOOK_RTS:
        RTS                                     | return from XPP_CALLHOOK

| -------------------------------------------------------------------------
| E_XPP_Close -- driver Close. closErr while any session slot is in use;
| else clear xppLoadedBit and the AGB's xppVarPtr. The 48-byte variable
| block is not disposed of: it is lost (a later Open allocates a new one).
| -------------------------------------------------------------------------
E_XPP_Close:
        BSR.W   XPP_ANYSESS                     | any session left?
        BNE.B   XPP_CLOSE_NOSESS                | no ->
        MOVEQ.L #closErr,D0                     | closErr (-24): sessions active
        RTS                                     | return closErr, driver stays open
XPP_CLOSE_NOSESS:
        BCLR    #xppLoadedBit,(PortBUse).W      | PortBUse bit 5: .XPP closed
        MOVEA.L (AGBHandle).W,A2                | A2 = AGB handle
        MOVEA.L (A2),A2                         | A2 = AGB
        CLR.L   xppVarPtr(A2)                   | xppVarPtr = 0 (variables abandoned)
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from E_XPP_Close

| -------------------------------------------------------------------------
| XPP_CLOSEALL -- csCode 247 closeAll (ASPCloseAll): close every session.
| Takes the first slot in use, starts closing it (XPP_STARTCLOSE) and
| returns; when that session is closed, XPP_WSSCLOSED comes back here
| (no CloseSession call is waiting on it), until no session is left and
| the call completes with noErr. The call stays at the head of the I/O
| queue (driver busy) meanwhile.
| -------------------------------------------------------------------------
XPP_CLOSEALL:
        BSR.W   XPP_ANYSESS                     | A2 = SCB of a session in use?
        BNE.W   XPP_DONE_NOERR                  | none left -> complete with noErr
        MOVE.B  #ssClosing,scbState(A2)         | session state: closing
        BRA.W   XPP_STARTCLOSE                  | close it (comes back when done)

| -------------------------------------------------------------------------
| XPP_ABORTOS -- csCode 248 abortOS (ASPAbortOS): abort a pending
| OpenSession (or FPLogin) given its SCB (abortSCBPtr). The OpenSess
| request on scbReqPB is cancelled with a KillSendReq on scbATPPB; the
| OpenSession then fails with reqAborted (XPP_OPENREPLY) and this call
| completes with noErr when the KillSendReq is done (XPP_DONE_NOERR).
| cbNotFound if no OpenSession is pending on the SCB or its WSS is still
| being opened. Stays at the head of the I/O queue until done.
| -------------------------------------------------------------------------
XPP_ABORTOS:
        MOVEA.L abortSCBPtr(A0),A2              | A2 = SCB of the OpenSession to abort
        MOVE.W  SR,-(SP)                        | save the interrupt level
        MOVE.W  #0x2600,SR                      | interrupts off (level 6): state must not change
        MOVEA.L scbCallList(A2),A1              | A1 = first active call of the session
        MOVE.L  A1,D0                           | any?
        BEQ.B   XPP_ABORTOS_NOTFOUND            | no -> cbNotFound
        CMPI.B  #openSess,csCode+1(A1)          | an OpenSession (or FPLogin) call?
        BNE.B   XPP_ABORTOS_NOTFOUND            | no -> cbNotFound
        LEA.L   scbReqPB(A2),A1                 | A1 = the OpenSess request's ATP pb
        CMPI.W  #openATPSkt,csCode(A1)          | still opening the WSS (no request yet)?
        BEQ.B   XPP_ABORTOS_NOTFOUND            | yes -> cbNotFound
        MOVE.B  #ssAborted,scbState(A2)         | session state: open being aborted
        MOVE.W  (SP)+,SR                        | interrupts back on
        LEA.L   scbATPPB(A2),A0                 | A0 = free ATP pb of the SCB
        LEA.L   XPP_DONE_NOERR(PC),A3           | completion: finish AbortOS with noErr
| fall into XPP_KILLSENDREQ: cancel the OpenSess request (A1)

| -------------------------------------------------------------------------
| XPP_KILLSENDREQ -- issue .ATP KillSendReq: cancel the SendRequest or
| NSendRequest of the ATP pb A1 (it completes with reqAborted).
|   A0 (in) -- ATP pb for the KillSendReq call
|   A1 (in) -- the request to cancel (aKillQEl)
|   A3 (in) -- completion routine
| Called by: XPP_ABORTOS (fall-through), XPP_KILLTICKLE, XPP_ABORTCALLS
| -------------------------------------------------------------------------
XPP_KILLSENDREQ:
        MOVE.L  A1,aKillQEl(A0)                 | aKillQEl = request to cancel
        MOVE.W  #killSendReq,D0                 | .ATP csCode 258: KillSendReq
| fall into XPP_CALLATP

| -------------------------------------------------------------------------
| XPP_CALLATP -- issue an asynchronous .ATP Control call.
|   A0 (in)  -- ATP parameter block (in the SCB or the CCB)
|   D0 (in)  -- .ATP csCode
|   A3 (in)  -- completion routine, 0 = none (completion routines get
|               A0 = the ATP pb, D0 = result and the CCR of TST.W D0)
|   D0 (out) -- result of _Control,ASYNC
| If .ATP is not open (notOpenErr) or not there (badUnitErr), the Device
| Manager does not call ioCompletion: then the completion routine is
| jumped to directly with that error.
| Called by: XPP_DOOPEN, XPP_WSSOPENED, XPP_OPENREPLY_CLOSE, XPP_OPENED,
| XPP_TICKLEKILLED, XPP_ABORTCALLS, XPP_CLOSEWSS, XPP_USERCMD_SEND,
| XPP_GETSTATUS, XPP_SRVCLOSE, XPP_ATTENTION, XPP_GETREQUEST,
| XPP_WRITECONT_SIZE, XPP_KILLSENDREQ (fall-through)
| -------------------------------------------------------------------------
XPP_CALLATP:
        MOVE.W  D0,csCode(A0)                   | csCode = the .ATP call
        MOVE.L  A3,ioCompletion(A0)             | ioCompletion = A3
        MOVE.W  #atpRefNum,ioRefNum(A0)         | ioRefNum = -11: .ATP
        _ControlAsync                           | queue the call on .ATP
        BEQ.B   XPP_CALLATP_RTS                 | under way -> return
        CMPI.W  #notOpenErr,D0                  | .ATP not open (-28)?
        BEQ.B   XPP_CALLATP_NOTOPEN             | yes -> call the completion routine
        CMPI.W  #badUnitErr,D0                  | .ATP not installed (-21)?
        BEQ.B   XPP_CALLATP_NOTOPEN             | yes -> call the completion routine
XPP_CALLATP_RTS:
        RTS                                     | return D0 = _Control result
XPP_CALLATP_NOTOPEN:
        TST.L   ioCompletion(A0)                | completion routine given?
        BEQ.B   XPP_CALLATP_RTS                 | no -> just return the error
        TST.W   D0                              | CCR = result, as the Device Manager sets it
        JMP     (A3)                            | -> completion routine with the error
| AbortOS: nothing to abort
XPP_ABORTOS_NOTFOUND:
        MOVE.W  (SP)+,SR                        | interrupts back on
        MOVE.W  #cbNotFound,D0                  | cbNotFound (-1102)
        BRA.B   XPP_DONE                        | complete AbortOS

| -------------------------------------------------------------------------
| XPP_GETPARMS -- csCode 249 getParms (ASPGetParms): return aspMaxCmdSize
| = 578, aspQuantumSize = 4624 (8 * 578) and numSesss = 10.
| -------------------------------------------------------------------------
XPP_GETPARMS:
        MOVE.W  #maxCmdSize,aspMaxCmdSize(A0)   | aspMaxCmdSize = 578 (one ATP packet)
        MOVE.W  #quantumSize,aspQuantumSize(A0) | aspQuantumSize = 4624 (8 ATP packets)
        BSR.W   XPP_GETVARS                     | A1 = driver variables
        MOVEQ.L #0x0,D0                         | clear the high byte
        MOVE.B  xppMaxSess(A1),D0               | D0 = number of session slots (10)
        MOVE.W  D0,numSesss(A0)                 | numSesss = 10
| complete the call at the head of the I/O queue with noErr
| Branch from: XPP_CLOSEALL; completion routine of XPP_ABORTOS
XPP_DONE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr

| -------------------------------------------------------------------------
| XPP_DONE -- complete the call at the head of the driver's I/O queue
| through jIODone (sets ioResult, calls ioCompletion, starts the next
| queued call).
|   D0 (in) -- result code
| Branch from: XPP_CTL_DISPATCH, XPP_ABORTOS_NOTFOUND, XPP_DONE_NOERR,
| XPP_ERRDONE, XPP_AFP_PARMERR
| -------------------------------------------------------------------------
XPP_DONE:
        BSR.W   XPP_GETVARS                     | A1 = driver variables
        MOVEA.L xppDCE(A1),A1                   | A1 = DCE
        MOVEA.L (JIODone).W,A0                  | A0 = IODone
        JMP     (A0)                            | IODone(A1 = DCE, D0 = result)

| -------------------------------------------------------------------------
| XPP_ERRDONE -- complete a call with an error found when it is started:
| an AFPCommand gets its csCode (afpCall) back first. Goes through
| jIODone, i.e. assumes the call is still at the head of the I/O queue
| (not so for the later steps of an AFP call -- see XPP_DEQUEUE).
|   D0 (in) -- result code
| Branch from: XPP_DOOPEN, XPP_CLOSESESS, XPP_USERCMD, XPP_AFP_LOGIN
| -------------------------------------------------------------------------
XPP_ERRDONE:
        TST.B   csCode(A0)                      | csCode high byte $FF: AFPCommand?
        BPL.B   XPP_DONE                        | no -> complete as it is
        MOVE.W  #afpCall,csCode(A0)             | csCode = afpCall again
        BRA.B   XPP_DONE                        | complete the AFPCommand

| -------------------------------------------------------------------------
| XPP_OPENSESS -- csCode 255 openSess (ASPOpenSession): open a session
| with the server at serverAddr, using the caller's SCB (scbPointer) and
| attention routine (attnRoutine), aspTimeout and aspRetry.
| -------------------------------------------------------------------------
XPP_OPENSESS:
        MOVEA.L scbPointer(A0),A2               | A2 = SCB
        MOVE.L  serverAddr(A0),D3               | D3 = server address (its SLS)
        MOVE.L  attnRoutine(A0),D2              | D2 = attention routine

| -------------------------------------------------------------------------
| XPP_DOOPEN -- open a session (OpenSession, FPLogin).
|   A0 (in) -- the XPP parameter block (aspTimeout, aspRetry)
|   A2 (in) -- SCB, D3 (in) -- server's SLS address, D2 (in) -- attention
|              routine
| Takes a session slot (XPP_NEWSESS clears the SCB and gives the
| sessRefnum, returned at once in sessRefnum), lets the next queued call
| start and opens the workstation session socket: .ATP OpenATPSkt on
| scbReqPB, continued in XPP_WSSOPENED.
| Branch from: XPP_OPENSESS (fall-through), XPP_AFP_LOGIN
| -------------------------------------------------------------------------
XPP_DOOPEN:
        BSR.W   XPP_NEWSESS                     | D1 = sessRefnum of a free slot, SCB cleared
        BNE.B   XPP_ERRDONE                     | no free slot -> aspNoMoreSess
        MOVE.B  #ssOpening,scbState(A2)         | session state: opening
        MOVE.L  D2,scbAttnRtn(A2)               | attention routine
        MOVE.W  D1,sessRefnum(A0)               | return sessRefnum
        MOVE.L  D3,scbSrvAddr(A2)               | server address = the SLS for now
        MOVE.B  D3,scbSLSSkt(A2)                | remember the SLS socket number
        MOVE.L  A0,scbCallList(A2)              | the open call is the session's only call
        BSR.W   XPP_DEQUEUE                     | detach it; start the next queued call
        LEA.L   scbReqPB(A2),A0                 | A0 = ATP pb for opening
        MOVE.W  #openATPSkt,D0                  | .ATP OpenATPSkt: the WSS (atpSocket 0 = any)
        LEA.L   XPP_WSSOPENED(PC),A3            | continue in XPP_WSSOPENED
        BRA.W   XPP_CALLATP                     | open the socket

| -------------------------------------------------------------------------
| XPP_WSSOPENED -- completion of OpenATPSkt (A0 = scbReqPB, D0 = result):
| send OpenSess to the server's SLS: SendRequest XO, user bytes
| [aspOpenSess, WSS, aspVersion], no data, one response buffer of 0 bytes
| at scbAuxPB (only the reply's user bytes matter), aspTimeout/aspRetry
| of the call; continued in XPP_OPENREPLY.
| -------------------------------------------------------------------------
XPP_WSSOPENED:
        LEA.L   -scbReqPB(A0),A2                | A2 = SCB
        BMI.W   XPP_OPENFAIL                    | no socket -> fail the open with D0
        MOVE.B  atpSocket(A0),scbWSS(A2)        | WSS = the socket just opened
        LEA.L   atpSocket(A0),A3                | A3 -> parameters of the SendRequest
        MOVE.W  #atpXOvalue,(A3)+               | atpSocket 0, atpFlags = XO
        MOVE.L  scbSrvAddr(A2),(A3)+            | addrBlock = server's SLS
        CLR.W   (A3)+                           | reqLength = 0: no data
        CLR.L   (A3)+                           | reqPointer = nil
        LEA.L   scbAuxPB(A2),A1                 | A1 = one-entry BDS (zeroed: 0-byte buffer)
        MOVE.L  A1,(A3)+                        | bdsPointer = scbAuxPB
        MOVE.B  #0x1,(A3)+                      | numOfBuffs = 1
        MOVEA.L scbCallList(A2),A1              | A1 = the OpenSession call
        MOVE.B  aspTimeout(A1),(A3)             | timeoutVal = aspTimeout
        ADDQ.W  #0x2,A3                         | skip numOfResps
        MOVE.B  aspRetry(A1),(A3)+              | retryCount = aspRetry
        LEA.L   userData(A0),A1                 | A1 -> ATP user bytes
        MOVE.B  #aspOpenSess,(A1)+              | aspCmdCode = OpenSess (4)
        MOVE.B  scbWSS(A2),(A1)+                | aspWSSNum = our WSS
        MOVE.W  #aspVersion,(A1)+               | aspVersNum = $0100
        LEA.L   XPP_OPENREPLY(PC),A3            | continue in XPP_OPENREPLY
        MOVE.W  #sendRequest,D0                 | .ATP SendRequest
        BRA.W   XPP_CALLATP                     | send OpenSess

| -------------------------------------------------------------------------
| XPP_OPENREPLY -- completion of the OpenSess request (A0 = scbReqPB):
| the OpenSessReply's user bytes are in the BDS at scbAuxPB. Error codes:
| reqFailed (no answer) -> aspNoServers; AbortOS -> reqAborted; the
| server's error code (aspBadVersNum, aspServerBusy, ...) is passed on,
| a positive one becomes aspParamErr. On an error the WSS is closed
| first (XPP_OPENFAIL_CLOSED); on success go to XPP_OPENED.
| -------------------------------------------------------------------------
XPP_OPENREPLY:
        LEA.L   -scbReqPB(A0),A2                | A2 = SCB
        BMI.B   XPP_OPENREPLY_ERR               | request failed or was killed ->
        MOVE.W  #reqAborted,D0                  | D0 = reqAborted (-1105)
        CMPI.B  #ssAborted,scbState(A2)         | AbortOS came meanwhile?
        BEQ.B   XPP_OPENREPLY_ERR               | yes -> fail with reqAborted
        LEA.L   scbAuxPB+bdsUserData+4(A2),A1   | A1 -> end of the reply's user bytes
        MOVE.W  -(A1),D0                        | D0 = aspOpenErr (user bytes 2-3)
        BEQ.B   XPP_OPENED                      | 0: session open ->
        BMI.B   XPP_OPENREPLY_ERR               | server's error code ->
        MOVE.W  #aspParamErr,D0                 | positive code: aspParamErr
XPP_OPENREPLY_ERR:
        CMPI.W  #reqFailed,D0                   | retries exhausted (-1096)?
        BNE.B   XPP_OPENREPLY_CLOSE             | no ->
        MOVE.W  #aspNoServers,D0                | yes: aspNoServers (-1069)
XPP_OPENREPLY_CLOSE:
        MOVE.B  scbWSS(A2),atpSocket(A0)        | atpSocket = the WSS
        MOVE.W  D0,scbAuxPB(A2)                 | keep the result code meanwhile
        MOVE.W  #closeATPSkt,D0                 | .ATP CloseATPSkt
        LEA.L   XPP_OPENFAIL_CLOSED(PC),A3      | continue in XPP_OPENFAIL_CLOSED
        BRA.W   XPP_CALLATP                     | close the WSS

| -------------------------------------------------------------------------
| XPP_OPENFAIL_CLOSED -- completion of CloseATPSkt after a failed open
| (A0 = scbReqPB): fail the open with the saved result.
| XPP_OPENFAIL -- free the session slot, complete the open call with D0.
| -------------------------------------------------------------------------
XPP_OPENFAIL_CLOSED:
        LEA.L   -scbReqPB(A0),A2                | A2 = SCB
        MOVE.W  scbAuxPB(A2),D0                 | D0 = saved result code
XPP_OPENFAIL:
        MOVE.W  D0,D1                           | keep the result
        BSR.W   XPP_FREESESS                    | free the session slot
        MOVE.W  D1,D0                           | D0 = result
        BRA.B   XPP_DONEFIRST                   | complete the open call (no attention call)

| -------------------------------------------------------------------------
| XPP_OPENED -- the server accepted the session (A0 = scbReqPB, A1 ->
| user bytes 2 of the OpenSessReply at scbAuxPB): take the session ID and
| the server session socket (SSS), start listening on the WSS for the
| server's requests (GetRequest on scbReqPB), start the tickle on
| scbATPPB, install the session timer and complete the open with noErr.
| -------------------------------------------------------------------------
XPP_OPENED:
        MOVE.B  -(A1),scbSessID(A2)             | session ID (aspSessID)
        MOVE.L  scbSrvAddr(A2),D3               | D3 = server's SLS address (for the tickles)
        MOVE.B  -(A1),scbSrvAddr+3(A2)          | server address socket = the SSS (aspSSSNum)
        MOVE.B  scbWSS(A2),atpSocket(A0)        | GetRequest on the WSS
        LEA.L   scbWrBSize(A2),A3               | A3 = 2-byte request buffer
        MOVE.L  A3,reqPointer(A0)               | reqPointer = scbWrBSize
        BSR.W   XPP_GETREQUEST                  | listen for the server's requests
        LEA.L   scbATPPB(A2),A0                 | A0 = ATP pb of the tickle
        LEA.L   atpSocket(A0),A3                | A3 -> parameters of the NSendRequest
        MOVE.B  scbWSS(A2),(A3)+                | atpSocket = WSS (send from the WSS)
        CLR.B   (A3)+                           | atpFlags = 0: at-least-once
        MOVE.L  D3,(A3)+                        | addrBlock = server's SLS
        CLR.W   (A3)+                           | reqLength = 0
        CLR.L   (A3)+                           | reqPointer = nil
        CLR.L   (A3)+                           | bdsPointer = nil
        MOVE.W  #tickleInt,(A3)+                | numOfBuffs 0, timeoutVal = 30 s
        MOVE.W  #0xFFFF,(A3)+                   | numOfResps, retryCount = 255: resend forever
        LEA.L   userData(A0),A3                 | A3 -> ATP user bytes
        MOVE.B  #aspTickle,(A3)+                | aspCmdCode = Tickle (5)
        MOVE.B  scbSessID(A2),(A3)+             | aspSessID
        CLR.W   (A3)+                           | unused bytes 2-3
        MOVE.W  #nSendRequest,D0                | .ATP NSendRequest
        SUBA.L  A3,A3                           | no completion routine
        BSR.W   XPP_CALLATP                     | start the tickle (never completes by itself)
        LEA.L   scbVBL+qType(A2),A0             | A0 -> session timer's qType
        MOVE.W  #vType,(A0)+                    | qType = vType
        LEA.L   XPP_SESSTIMEOUT(PC),A3          | vblAddr = XPP_SESSTIMEOUT
        MOVE.L  A3,(A0)+                        | vblAddr
        MOVE.W  #tickleTime,(A0)                | vblCount = 7200 ticks (2 minutes)
        LEA.L   scbVBL(A2),A0                   | A0 = session timer
        _VInstall                               | start it
        MOVEQ.L #0x0,D0                         | noErr
        MOVE.B  #ssOpen,scbState(A2)            | session state: open
| complete the session's first call (the open call) with D0

| -------------------------------------------------------------------------
| XPP_DONEFIRST -- complete the first call of the session's list.
| XPP_UNLINKDONE -- take the call A0 off the list of the session A2 and
| complete it with D0 (it must be on the list).
| Branch from: XPP_OPENFAIL, XPP_CMDREPLY_DONE, XPP_WRITEDATA_SENT
| -------------------------------------------------------------------------
XPP_DONEFIRST:
        MOVEA.L scbCallList(A2),A0              | A0 = first call of the session
XPP_UNLINKDONE:
        MOVE.L  A1,-(SP)                        | save A1
        MOVE.W  SR,-(SP)                        | save the interrupt level
        MOVE.W  #0x2600,SR                      | interrupts off (level 6)
        LEA.L   scbCallList(A2),A1              | A1 = list head (qLink at offset 0)
XPP_UNLINKDONE_LOOP:
        CMPA.L  (A1),A0                         | next element is our call?
        BEQ.B   XPP_UNLINKDONE_FOUND            | yes ->
        MOVEA.L (A1),A1                         | follow qLink
        BRA.B   XPP_UNLINKDONE_LOOP             | and look on
XPP_UNLINKDONE_FOUND:
        MOVE.L  (A0),(A1)                       | unlink the call (its qLink stays as it is)
        MOVE.W  (SP)+,SR                        | interrupts back on
        MOVEA.L (SP)+,A1                        | restore A1

| -------------------------------------------------------------------------
| XPP_CALLDONE -- an ASP call has finished with D0: if it is a step of an
| AFPCommand (csCode high byte $FF), go on in XPP_AFP_STEP, else complete
| it (XPP_COMPLETE).
| Branch from: XPP_UNLINKDONE (fall-through), XPP_WSSCLOSED
| -------------------------------------------------------------------------
XPP_CALLDONE:
        TST.W   csCode(A0)                      | AFPCommand in progress?
        BMI.W   XPP_AFP_STEP                    | yes -> next AFP step

| -------------------------------------------------------------------------
| XPP_COMPLETE -- complete a call that has left the I/O queue: ioResult
| = D0, then ioCompletion (A0 = parameter block, D0 = result, CCR set).
| Preserves D1-D3/A0-A3.
| Branch from: XPP_CALLDONE (fall-through), XPP_STATUSREPLY, XPP_AFP_DONE
| -------------------------------------------------------------------------
XPP_COMPLETE:
        MOVEM.L D1-D3/A0-A3,-(SP)               | save registers
        MOVE.W  D0,ioResult(A0)                 | ioResult = result
        MOVE.L  ioCompletion(A0),D1             | D1 = completion routine
        BEQ.B   XPP_COMPLETE_EXIT               | none ->
        MOVEA.L D1,A1                           | A1 = completion routine
        TST.W   D0                              | CCR = result
        JSR     (A1)                            | call the caller's ioCompletion
XPP_COMPLETE_EXIT:
        MOVEM.L (SP)+,D1-D3/A0-A3               | restore registers
        RTS                                     | return from XPP_COMPLETE

| -------------------------------------------------------------------------
| XPP_CLOSESESS -- csCode 254 closeSess (ASPCloseSession), also FPLogout
| and the end of a failed FPLogin: close the session sessRefnum. The call
| leaves the I/O queue and waits on the session's list; the session is
| closed by the chain XPP_STARTCLOSE -> XPP_TICKLEKILLED ->
| XPP_ABORTCALLS -> XPP_CLOSEWSS -> XPP_WSSCLOSED, which completes it.
| aspParamErr for a bad sessRefnum, aspSessClosed if already closing.
| Branch from: XPP_CTL_TABLE, XPP_AFP_LOGOUT, XPP_AFP_LOGINREPLY
| -------------------------------------------------------------------------
XPP_CLOSESESS:
        MOVE.W  sessRefnum(A0),D1               | D1 = sessRefnum
        BSR.W   XPP_FINDSESS                    | A2 = its SCB, open?
        BNE.W   XPP_ERRDONE                     | no -> aspParamErr / aspSessClosed
        MOVE.B  #ssClosing,scbState(A2)         | session state: closing
        BSR.W   XPP_DEQUEUE                     | detach the call; start the next queued call
        BSR.W   XPP_LINKCALL                    | wait on the session's call list

| -------------------------------------------------------------------------
| XPP_STARTCLOSE -- begin to close the session A2 (state ssClosing): stop
| the session timer, then
| XPP_KILLTICKLE -- (session timer already gone) cancel the tickle on
| scbATPPB with a KillSendReq on scbAuxPB; continued in XPP_TICKLEKILLED.
| Branch from: XPP_CLOSEALL, XPP_CLOSESESS (fall-through);
| XPP_SESSTIMEOUT (XPP_KILLTICKLE)
| -------------------------------------------------------------------------
XPP_STARTCLOSE:
        LEA.L   scbVBL(A2),A0                   | A0 = session timer
        _VRemove                                | stop it
XPP_KILLTICKLE:
        LEA.L   XPP_TICKLEKILLED(PC),A3         | continue in XPP_TICKLEKILLED
        LEA.L   scbAuxPB(A2),A0                 | A0 = ATP pb for the KillSendReq
        LEA.L   scbATPPB(A2),A1                 | A1 = the tickle request
        BRA.W   XPP_KILLSENDREQ                 | cancel the tickle

| -------------------------------------------------------------------------
| XPP_TICKLEKILLED -- completion of the tickle's KillSendReq (A0 =
| scbAuxPB). Unless the server closed the session or it timed out
| (ssDead), send CloseSess to the server's SSS: SendRequest ALO, user
| bytes [aspCloseSess, session ID, 0], no data, one 0-byte response
| buffer (at scbAuxPB), 1 s timeout, 1 retry. Then (completion or ssDead)
| XPP_ABORTCALLS.
| -------------------------------------------------------------------------
XPP_TICKLEKILLED:
        LEA.L   -scbAuxPB(A0),A2                | A2 = SCB
        MOVEA.L A0,A1                           | A1 = scbAuxPB, now the reply BDS
        LEA.L   scbATPPB(A2),A0                 | A0 = the tickle's ATP pb, now free
        CMPI.B  #ssDead,scbState(A2)            | closed by the server or timed out?
        BEQ.B   XPP_ABORTCALLS                  | yes -> no CloseSess to send
        LEA.L   atpSocket(A0),A3                | A3 -> parameters of the SendRequest
        CLR.W   (A3)+                           | atpSocket 0, atpFlags 0: at-least-once
        MOVE.L  scbSrvAddr(A2),(A3)+            | addrBlock = server session socket (SSS)
        CLR.W   (A3)+                           | reqLength = 0
        CLR.L   (A3)+                           | reqPointer = nil
        MOVE.L  A1,(A3)+                        | bdsPointer = scbAuxPB
        CLR.W   (A1)+                           | bdsBuffSz = 0
        CLR.L   (A1)+                           | bdsBuffAdr = nil
        MOVE.B  #0x1,(A3)+                      | numOfBuffs = 1
        MOVE.B  #0x1,(A3)+                      | timeoutVal = 1 s
        MOVE.W  #0x1,(A3)+                      | numOfResps 0, retryCount = 1
        LEA.L   userData(A0),A3                 | A3 -> ATP user bytes
        MOVE.B  #aspCloseSess,(A3)+             | aspCmdCode = CloseSess (1)
        MOVE.B  scbSessID(A2),(A3)+             | aspSessID
        CLR.W   (A3)+                           | unused bytes 2-3
        MOVE.W  #sendRequest,D0                 | .ATP SendRequest
        LEA.L   XPP_ABORTCALLS(PC),A3           | continue in XPP_ABORTCALLS
        BRA.W   XPP_CALLATP                     | send CloseSess

| -------------------------------------------------------------------------
| XPP_ABORTCALLS -- (A0 = scbATPPB) end every active call of the closing
| session, one per pass: for each call not a CloseSession, a UserWrite's
| write data response still under way is released (RelRspCB), then the
| call's request is cancelled (KillSendReq: it completes with reqAborted,
| which XPP_CMDREPLY turns into aspSessClosed and unlinks). Each .ATP call
| comes back here; when only CloseSession calls are left, close the WSS.
| Branch from: XPP_TICKLEKILLED; completion routine of its own .ATP calls
| -------------------------------------------------------------------------
XPP_ABORTCALLS:
        LEA.L   -scbATPPB(A0),A2                | A2 = SCB
        LEA.L   scbCallList(A2),A1              | A1 = list head
XPP_ABORTCALLS_LOOP:
        MOVE.L  (A1),D1                         | D1 = next call
        BEQ.B   XPP_CLOSEWSS                    | none left -> close the WSS
        MOVEA.L D1,A1                           | A1 = the call
        CMPI.B  #closeSess,csCode+1(A1)         | a CloseSession (or FPLogout)?
        BEQ.B   XPP_ABORTCALLS_LOOP             | yes -> leave it, it completes at the end
        CMPI.B  #userWrite,csCode+1(A1)         | a UserWrite?
        BNE.B   XPP_ABORTCALLS_KILL             | no -> cancel its request
        MOVE.L  A0,D2                           | keep scbATPPB
        MOVEA.L A1,A0                           | A0 = the UserWrite call
        MOVEA.L A1,A3                           | (keep the call)
        BSR.W   XPP_GETWRPB                     | A1 = its write data ATP pb
        EXG     A1,A3                           | A1 = the call, A3 = write data pb
        MOVEA.L D2,A0                           | A0 = scbATPPB again
        TST.W   ioResult(A3)                    | write data response under way?
        BLE.B   XPP_ABORTCALLS_KILL             | no -> cancel the request
        MOVE.B  atpSocket(A3),atpSocket(A0)     | RelRspCB: its socket (WSS),
        MOVE.L  addrBlock(A3),addrBlock(A0)     | the server's address
        MOVE.W  transID(A3),transID(A0)         | and the transaction ID
        MOVE.W  #relRspCB,D0                    | .ATP RelRspCB: end the response
        LEA.L   XPP_ABORTCALLS(PC),A3           | then scan the list again
        BRA.W   XPP_CALLATP                     | release it
XPP_ABORTCALLS_KILL:
        LEA.L   ccbStart(A1),A1                 | A1 = the call's request (CCB ATP pb)
        LEA.L   XPP_ABORTCALLS(PC),A3           | then scan the list again
        BRA.W   XPP_KILLSENDREQ                 | cancel it

| -------------------------------------------------------------------------
| XPP_CLOSEWSS -- (A0 = scbATPPB) all calls ended: close the workstation
| session socket (this also ends the GetRequest on it); continued in
| XPP_WSSCLOSED.
| -------------------------------------------------------------------------
XPP_CLOSEWSS:
        MOVE.B  scbWSS(A2),atpSocket(A0)        | atpSocket = WSS
        MOVE.W  #closeATPSkt,D0                 | .ATP CloseATPSkt
        LEA.L   XPP_WSSCLOSED(PC),A3            | continue in XPP_WSSCLOSED
        BRA.W   XPP_CALLATP                     | close the WSS

| -------------------------------------------------------------------------
| XPP_WSSCLOSED -- completion of the WSS's CloseATPSkt (A0 = scbATPPB):
| the session is gone. Free the slot, call the attention routine with
| D0 = sessRefnum, D1 = 0 (session closed), then: ssDead -> done (nobody
| waits); a CloseSession call on the list -> complete it (D0 = noErr);
| none -> it was CloseAll: close the next session.
| -------------------------------------------------------------------------
XPP_WSSCLOSED:
        LEA.L   -scbATPPB(A0),A2                | A2 = SCB
        MOVEA.L scbCallList(A2),A0              | A0 = waiting CloseSession call, if any
        MOVE.B  scbState(A2),D2                 | D2 = state (ssClosing or ssDead)
        MOVE.W  scbRefnum(A2),D1                | D1 = sessRefnum
        MOVEA.L scbAttnRtn(A2),A3               | A3 = attention routine
        BSR.W   XPP_FREESESS                    | free the slot (D0 = 0)
        MOVE.L  A3,D3                           | attention routine given?
        BEQ.B   XPP_WSSCLOSED_NOATTN            | no ->
        EXG     D0,D1                           | D0 = sessRefnum, D1 = 0: closed
        MOVEM.L D2/A0/A2,-(SP)                  | save state, call, SCB
        JSR     (A3)                            | call the attention routine
        MOVEM.L (SP)+,D2/A0/A2                  | restore
        CLR.W   D0                              | noErr
XPP_WSSCLOSED_NOATTN:
        SUBQ.B  #ssDead,D2                      | closed by the server / timed out?
        BEQ.B   XPP_RETURN                      | yes -> nothing to complete
        MOVE.L  A0,D1                           | a CloseSession call waiting?
        BEQ.W   XPP_CLOSEALL                    | no: CloseAll -> next session
        BRA.W   XPP_CALLDONE                    | complete the CloseSession (noErr)

| -------------------------------------------------------------------------
| E_XPP_PrimeStatus -- driver Prime and Status: never called (drvrFlags
| enables Control only); just clears drvrActive in dCtlFlags.
| XPP_RETURN: its RTS, a common return for other routines.
| -------------------------------------------------------------------------
E_XPP_PrimeStatus:
        BCLR    #drvrActive,dCtlFlags+1(A1)     | driver no longer busy
| Branch from: XPP_WSSCLOSED_NOATTN, XPP_CMDREPLY_OK
XPP_RETURN:
        RTS                                     | return

| -------------------------------------------------------------------------
| XPP_USERCMD -- csCode 253 userCommand (ASPUserCommand) and csCode 252
| userWrite (ASPUserWrite), also the ASP calls of AFPCommand: send the
| command block (cbSize, cbPtr) to the server's SSS as an ASP Command or
| Write: NSendRequest from the WSS, XO, user bytes [aspCommand or
| aspWrite, session ID, sequence number], timeoutVal = aspTimeout,
| retries forever, reply into rbPtr/rbSize through the CCB's reply BDS.
| For a Write the CCB also gets the write data's ATP pb and BDS (wdSize,
| wdPtr), which the server fetches with WriteContinue (XPP_WRITECONT).
| The call leaves the I/O queue and waits on the session's list;
| completion in XPP_CMDREPLY. aspParamErr/aspSessClosed for a bad or
| closing session, aspSizeErr if cbSize > 578.
| Branch from: XPP_CTL_TABLE, XPP_AFP_SEND, XPP_AFP_LOGINSTEP
| -------------------------------------------------------------------------
XPP_USERCMD:
        LEA.L   sessRefnum(A0),A3               | A3 -> sessRefnum
        MOVE.W  (A3),D1                         | D1 = sessRefnum
        BSR.W   XPP_FINDSESS                    | A2 = its SCB, open?
        BNE.W   XPP_ERRDONE                     | no -> aspParamErr / aspSessClosed
        ADDQ.W  #cbSize-sessRefnum,A3           | A3 -> cbSize
        MOVE.W  #aspSizeErr,D0                  | D0 = aspSizeErr (-1073)
        CMPI.W  #maxCmdSize,(A3)                | command block > 578 bytes?
        BHI.W   XPP_ERRDONE                     | yes -> aspSizeErr
        MOVE.W  scbSeqNum(A2),D1                | D1 = this request's sequence number
        ADDQ.W  #0x1,scbSeqNum(A2)              | next sequence number
        BSR.W   XPP_DEQUEUE                     | detach the call; start the next queued call
        MOVE.W  D1,D0                           | D0 = sequence number
        LEA.L   ccbStart+atpSocket(A0),A1       | A1 -> parameters of the CCB's NSendRequest
        MOVE.B  scbWSS(A2),(A1)+                | atpSocket = WSS (send from the WSS)
        MOVE.B  #atpXOvalue,(A1)+               | atpFlags = XO
        MOVE.L  scbSrvAddr(A2),(A1)+            | addrBlock = server session socket (SSS)
        MOVE.W  (A3)+,(A1)+                     | reqLength = cbSize
        MOVE.L  (A3)+,(A1)+                     | reqPointer = cbPtr
        MOVE.L  A4,-(SP)                        | save A4
        LEA.L   ccbStart+ioQElSize(A0),A4       | A4 = reply BDS, after the ATP pb
        MOVE.L  A4,(A1)+                        | bdsPointer = reply BDS
        MOVE.W  (A3)+,D3                        | D3 = rbSize
        MOVE.L  (A3)+,D2                        | D2 = rbPtr
        BSR.W   XPP_BUILDBDS                    | reply BDS, D1 = entries, A4 after it
        MOVEQ.L #aspCommand,D2                  | D2 = ASP Command (2)
        CMPI.B  #userWrite,csCode+1(A0)         | a UserWrite?
        BNE.B   XPP_USERCMD_SEND                | no ->
        MOVE.W  (A3),D3                         | D3 = wdSize
        MOVE.W  D3,reqLength(A4)                | write data pb: reqLength = size to write
        CLR.W   (A3)+                           | wdSize = 0 (bytes written so far)
        MOVE.L  (A3)+,D2                        | D2 = wdPtr
        CLR.W   ioResult(A4)                    | write data pb: not under way
        MOVE.L  A0,reqPointer(A4)               | write data pb: reqPointer = the call
        ADDA.W  #ioQElSize,A4                   | A4 = write data BDS, after the pb
        SWAP    D1                              | keep the reply BDS count
        BSR.B   XPP_BUILDBDS                    | write data BDS (wdSize, wdPtr)
        SWAP    D1                              | D1 = reply BDS count again
        MOVEQ.L #aspWrite,D2                    | D2 = ASP Write (6)
XPP_USERCMD_SEND:
        MOVEA.L (SP)+,A4                        | restore A4
        MOVE.B  D1,(A1)+                        | numOfBuffs = reply BDS entries
        MOVE.B  aspTimeout(A0),(A1)+            | timeoutVal = aspTimeout
        MOVE.W  #0xFFFF,(A1)+                   | numOfResps, retryCount 255: retry forever
        BSR.W   XPP_LINKCALL                    | put the call on the session's list
        LEA.L   ccbStart(A0),A0                 | A0 = the CCB's ATP pb
        LEA.L   userData(A0),A1                 | A1 -> ATP user bytes
        MOVE.B  D2,(A1)+                        | aspCmdCode = Command or Write
        MOVE.B  scbSessID(A2),(A1)+             | aspSessID
        MOVE.W  D0,(A1)+                        | aspSeqNum = sequence number
        LEA.L   XPP_CMDREPLY(PC),A3             | continue in XPP_CMDREPLY
        MOVE.W  #nSendRequest,D0                | .ATP NSendRequest
        BRA.W   XPP_CALLATP                     | send the request

| -------------------------------------------------------------------------
| XPP_CMDREPLY -- completion of a Command/Write request (A0 = the CCB's
| ATP pb, D0 = result): reply size into rbSize (XPP_REPLYSIZE), the first
| reply packet's user bytes into cmdResult. reqAborted (the session is
| being closed) becomes aspSessClosed. A reply restarts the session timer.
| A Write whose write data response is still under way is completed by
| XPP_WRITEDATA_SENT instead. Completion: XPP_UNLINKDONE.
| -------------------------------------------------------------------------
XPP_CMDREPLY:
        BSR.W   XPP_REPLYSIZE                   | A0 = the call, rbSize set, D0 = result
        MOVE.L  bdsUserData(A1),cmdResult(A0)   | cmdResult = user bytes of the first reply packet
        MOVE.W  sessRefnum(A0),D1               | D1 = sessRefnum
        MOVE.W  D0,D2                           | keep the result
        BSR.W   XPP_FINDSESS                    | A2 = SCB
        MOVE.W  D2,D0                           | D0 = result
        CMPI.W  #reqAborted,D0                  | request cancelled by the close?
        BNE.B   XPP_CMDREPLY_OK                 | no ->
        MOVE.W  #aspSessClosed,D0               | aspSessClosed (-1072)
        BRA.B   XPP_CMDREPLY_DONE               | complete
XPP_CMDREPLY_OK:
        MOVE.W  #tickleTime,scbVBL+vblCount(A2) | the server is there: restart the session timer
        CMPI.B  #userWrite,csCode+1(A0)         | a Write?
        BNE.B   XPP_CMDREPLY_DONE               | no -> complete
        BSR.W   XPP_GETWRPB                     | A1 = its write data ATP pb
        TST.W   ioResult(A1)                    | write data response still under way?
        BGT.W   XPP_RETURN                      | yes -> XPP_WRITEDATA_SENT completes
XPP_CMDREPLY_DONE:
        BRA.W   XPP_UNLINKDONE                  | unlink and complete the call

| -------------------------------------------------------------------------
| XPP_BUILDBDS -- build a BDS for a buffer: entries of atpMaxData (578)
| bytes, then one for the rest (also when it is 0 bytes, as ASP asks for
| one more response than the buffer holds) unless there are 8 already.
| The size is cut to quantumSize (8 * 578).
|   D3 (in)     -- buffer size (word)
|   D2 (in)     -- buffer address
|   A4 (in/out) -- where to build the BDS / after it
|   D1 (out)    -- number of BDS entries
| Called by: XPP_USERCMD (twice), XPP_GETSTATUS
| -------------------------------------------------------------------------
XPP_BUILDBDS:
        CMPI.W  #quantumSize,D3                 | more than 8 packets?
        BLS.B   XPP_BUILDBDS_DIV                | no ->
        MOVE.W  #quantumSize,D3                 | yes: 4624 bytes at most
XPP_BUILDBDS_DIV:
        EXT.L   D3                              | D3 = size as a long
        DIVS.W  #atpMaxData,D3                  | D3 = rest:full packets
        MOVE.W  D3,D1                           | D1 = number of full packets
        BEQ.B   XPP_BUILDBDS_LAST               | none ->
XPP_BUILDBDS_LOOP:
        MOVE.W  #atpMaxData,(A4)+               | bdsBuffSz = 578
        MOVE.L  D2,(A4)+                        | bdsBuffAdr = buffer
        ADDQ.W  #0x2,A4                         | skip bdsDataSz
        CLR.L   (A4)+                           | bdsUserData = 0
        ADDI.L  #atpMaxData,D2                  | next 578 bytes of the buffer
        SUBQ.W  #0x1,D3                         | count full packets
        BNE.B   XPP_BUILDBDS_LOOP               | next entry
XPP_BUILDBDS_LAST:
        CMPI.W  #0x8,D1                         | 8 entries already?
        BEQ.B   XPP_BUILDBDS_RTS                | yes -> done
        ADDQ.W  #0x1,D1                         | one more entry
        SWAP    D3                              | D3 = rest of the buffer
        MOVE.W  D3,(A4)+                        | bdsBuffSz = rest (may be 0)
        MOVE.L  D2,(A4)+                        | bdsBuffAdr
        ADDQ.W  #0x2,A4                         | skip bdsDataSz
        CLR.L   (A4)+                           | bdsUserData = 0
XPP_BUILDBDS_RTS:
        RTS                                     | return from XPP_BUILDBDS

| -------------------------------------------------------------------------
| XPP_DEQUEUE -- detach the call A0 from the head of the driver's I/O
| queue and mark the driver not busy, so that the next queued call can
| start: if there is one, it is started here (E_XPP_Control, recursively).
| The call is then completed by XPP_COMPLETE. Interrupts are off while
| the queue is changed.
|   A0 (in) -- the call (must be the head of the queue)
|   D0 (out) -- 0
| Preserves D1-D3/A0/A2/A3; changes A1.
| Suspected bug: the second and later steps of an AFPCommand (FPRead and
| FPWrite chunks, the login command after the OpenSession, the
| CloseSession of a failed login) come here again although the call has
| left the queue already. Its qLink still holds what followed it on the
| session's call list when it was unlinked (XPP_UNLINKDONE does not clear
| it), so dCtlQHead becomes nil -- dropping the call at the head of the
| queue, e.g. a CloseAll or AbortOS under way, which then never completes
| -- or that older call of the session (perhaps finished meanwhile),
| which is then started again here.
| Called by: XPP_DOOPEN, XPP_CLOSESESS, XPP_USERCMD, XPP_GETSTATUS
| -------------------------------------------------------------------------
XPP_DEQUEUE:
        BSR.W   XPP_GETVARS                     | A1 = driver variables
        MOVEA.L xppDCE(A1),A1                   | A1 = DCE
        MOVE.W  SR,-(SP)                        | save the interrupt level
        MOVE.W  #0x2600,SR                      | interrupts off (level 6)
        BCLR    #drvrActive,dCtlFlags+1(A1)     | driver no longer busy
        MOVE.L  (A0),dCtlQHead(A1)              | dCtlQHead = next queued call (qLink)
        BNE.B   XPP_DEQUEUE_NEXT                | there is one ->
        CLR.L   dCtlQTail(A1)                   | queue empty: dCtlQTail = nil
XPP_DEQUEUE_NEXT:
        CLR.L   (A0)                            | qLink = nil: the call is detached
        MOVE.L  dCtlQHead(A1),D0                | D0 = next queued call
        BEQ.B   XPP_DEQUEUE_RTS                 | none ->
        BSET    #drvrActive,dCtlFlags+1(A1)     | driver busy with it
        MOVE.W  (SP)+,SR                        | interrupts back on
        MOVEM.L D1-D3/A0/A2-A3,-(SP)            | save registers
        MOVEA.L D0,A0                           | A0 = next call
        MOVEQ.L #0x0,D0                         | D0 = 0, as from the Device Manager
        BSR.W   E_XPP_Control                   | start it
        MOVEM.L (SP)+,D1-D3/A0/A2-A3            | restore registers
        MOVEQ.L #0x0,D0                         | D0 = 0
        RTS                                     | return from XPP_DEQUEUE
XPP_DEQUEUE_RTS:
        MOVE.W  (SP)+,SR                        | interrupts back on
        RTS                                     | return from XPP_DEQUEUE

| -------------------------------------------------------------------------
| XPP_GETSTATUS -- csCode 251 getStatus (ASPGetStatus): ask the server at
| serverAddr (its SLS) for its status block, no session needed:
| SendRequest ALO, user bytes [aspGetStat, 0, 0], aspTimeout/aspRetry,
| reply into rbPtr/rbSize through the CCB's BDS. The call leaves the I/O
| queue; completion in XPP_STATUSREPLY.
| -------------------------------------------------------------------------
XPP_GETSTATUS:
        LEA.L   rbSize(A0),A3                   | A3 -> rbSize
        BSR.B   XPP_DEQUEUE                     | detach the call; start the next queued call
        LEA.L   ccbStart+atpSocket(A0),A1       | A1 -> parameters of the CCB's SendRequest
        CLR.W   (A1)+                           | atpSocket 0, atpFlags 0: at-least-once
        MOVE.L  serverAddr(A0),(A1)+            | addrBlock = server's SLS
        CLR.W   (A1)+                           | reqLength = 0
        CLR.L   (A1)+                           | reqPointer = nil
        MOVE.L  A4,-(SP)                        | save A4
        LEA.L   ccbStart+ioQElSize(A0),A4       | A4 = reply BDS, after the ATP pb
        MOVE.L  A4,(A1)+                        | bdsPointer = reply BDS
        MOVE.W  (A3)+,D3                        | D3 = rbSize
        MOVE.L  (A3)+,D2                        | D2 = rbPtr
        BSR.W   XPP_BUILDBDS                    | reply BDS, D1 = entries
        MOVEA.L (SP)+,A4                        | restore A4
        MOVE.B  D1,(A1)+                        | numOfBuffs = BDS entries
        MOVE.B  aspTimeout(A0),(A1)             | timeoutVal = aspTimeout
        ADDQ.W  #0x2,A1                         | skip numOfResps
        MOVE.B  aspRetry(A0),(A1)+              | retryCount = aspRetry
        LEA.L   ccbStart(A0),A0                 | A0 = the CCB's ATP pb
        LEA.L   userData(A0),A1                 | A1 -> ATP user bytes
        CLR.L   (A1)                            | all 0, then
        MOVE.B  #aspGetStat,(A1)+               | aspCmdCode = GetStatus (3)
        MOVE.W  #sendRequest,D0                 | .ATP SendRequest
        LEA.L   XPP_STATUSREPLY(PC),A3          | continue in XPP_STATUSREPLY
        BRA.W   XPP_CALLATP                     | send GetStatus

| -------------------------------------------------------------------------
| XPP_STATUSREPLY -- completion of GetStatus (A0 = the CCB's ATP pb):
| reply size into rbSize, complete the call (reqFailed -> aspNoServers).
| -------------------------------------------------------------------------
XPP_STATUSREPLY:
        BSR.B   XPP_REPLYSIZE                   | A0 = the call, rbSize set, D0 = result
        BRA.W   XPP_COMPLETE                    | complete GetStatus

| -------------------------------------------------------------------------
| XPP_REPLYSIZE -- after a request with a reply BDS: rbSize = 578 *
| (responses - 1) + bytes in the last response; aspBufTooSmall if that
| response did not fit its buffer (counted up to the buffer size).
| reqFailed (no answer) becomes aspNoServers.
|   A0 (in)  -- the CCB's ATP pb;  (out) -- the XPP parameter block
|   D0 (in/out) -- result
|   A1 (out) -- the reply BDS
| Called by: XPP_CMDREPLY, XPP_STATUSREPLY
| -------------------------------------------------------------------------
XPP_REPLYSIZE:
        MOVEA.L bdsPointer(A0),A1               | A1 = reply BDS
        MOVE.B  numOfResps(A0),D3               | D3 = responses received
        LEA.L   -ccbStart(A0),A0                | A0 = the XPP parameter block
        TST.W   D0                              | request failed?
        BNE.B   XPP_REPLYSIZE_MAP               | yes -> no size
        EXT.W   D3                              | D3 = number of responses
        SUBQ.W  #0x1,D3                         | index of the last one
        MOVE.W  D3,D2                           | D2 = full responses before it
        MULU.W  #bdsEntrySz,D3                  | D3 = offset of its BDS entry
        MOVE.W  bdsDataSz(A1,D3.W),D1           | D1 = bytes in the last response
        CMP.W   bdsBuffSz(A1,D3.W),D1           | more than its buffer holds?
        BLS.B   XPP_REPLYSIZE_SUM               | no ->
        MOVE.W  #aspBufTooSmall,D0              | aspBufTooSmall (-1067): reply cut off
        MOVE.W  bdsBuffSz(A1,D3.W),D1           | count only the buffer size
XPP_REPLYSIZE_SUM:
        MULU.W  #atpMaxData,D2                  | 578 bytes per full response
        ADD.W   D2,D1                           | D1 = reply size
        MOVE.W  D1,rbSize(A0)                   | rbSize = reply size
XPP_REPLYSIZE_MAP:
        CMPI.W  #reqFailed,D0                   | no answer (-1096)?
        BNE.B   XPP_REPLYSIZE_RTS               | no ->
        MOVE.W  #aspNoServers,D0                | aspNoServers (-1069)
XPP_REPLYSIZE_RTS:
        RTS                                     | return from XPP_REPLYSIZE

| -------------------------------------------------------------------------
| XPP_AFPCALL -- csCode 250 afpCall (AFPCommand): map the AFP command in
| the first byte of the command block to ASP calls (table in the banner).
| csCode becomes $FF00 + the ASP csCode used, so that the end of the ASP
| call comes back to XPP_AFP_STEP; ioCmdAddr (pb+8) counts the bytes
| moved by FPRead/FPWrite. afpParmErr for cbSize 0 and commands 0, 15
| and 255 (csCode then keeps its $FF high byte).
| -------------------------------------------------------------------------
XPP_AFPCALL:
        TST.W   cbSize(A0)                      | empty command block?
        BNE.B   XPP_AFP_START                   | no ->
XPP_AFP_PARMERR:
        MOVE.W  #afpParmErr,D0                  | afpParmErr (-5019)
        BRA.W   XPP_DONE                        | complete the call
XPP_AFP_START:
        ST.B    csCode(A0)                      | csCode high byte $FF: AFP call in progress
        CLR.L   ioCmdAddr(A0)                   | bytes moved so far = 0
| XPP_AFP_NEXT -- issue the (next) ASP call for the AFP command
| Branch from: XPP_AFP_RWCOUNT (next FPRead/FPWrite chunk)
XPP_AFP_NEXT:
        MOVEA.L cbPtr(A0),A1                    | A1 = AFP command block
        MOVE.B  (A1),D1                         | D1 = AFP command
        BEQ.B   XPP_AFP_PARMERR                 | 0: no such command
        CMPI.B  #afpGetSInfo,D1                 | FPGetSrvrInfo (15): ASPGetStatus's job
        BEQ.B   XPP_AFP_PARMERR                 | -> afpParmErr
        CMPI.B  #0xFF,D1                        | 255: no such command
        BEQ.B   XPP_AFP_PARMERR                 | -> afpParmErr
        CMPI.B  #afpLogin,D1                    | FPLogin (18)?
        BEQ.B   XPP_AFP_LOGIN                   | -> OpenSession first
        CMPI.B  #afpLogout,D1                   | FPLogout (20)?
        BEQ.B   XPP_AFP_LOGOUT                  | -> CloseSession
        MOVE.B  #userWrite,csCode+1(A0)         | ASP call: Write ...
        LEA.L   wdSize(A0),A3                   | (A3 -> wdSize)
        CMPI.B  #afpWrite,D1                    | FPWrite (33)?
        BEQ.B   XPP_AFP_RWSIZE                  | yes -> Write of the next chunk
        CMPI.B  #afpUseWrite,D1                 | command $C0..$FE?
        BCC.B   XPP_AFP_SEND                    | yes -> Write with wdSize/wdPtr
        MOVE.B  #userCommand,csCode+1(A0)       | else ASP call: Command
        CMPI.B  #afpRead,D1                     | FPRead (27)?
        BNE.B   XPP_AFP_SEND                    | no -> plain Command
        SUBQ.W  #wdSize-rbSize,A3               | A3 -> rbSize
| FPRead/FPWrite: this chunk is MIN(reqCount, quantumSize) bytes
XPP_AFP_RWSIZE:
        MOVE.L  reqCount(A1),D2                 | D2 = bytes still to move
        CMPI.L  #quantumSize,D2                 | more than one quantum?
        BLS.B   XPP_AFP_RWSIZE_SET              | no ->
        MOVE.W  #quantumSize,D2                 | yes: 4624 bytes
XPP_AFP_RWSIZE_SET:
        MOVE.W  D2,(A3)                         | rbSize / wdSize = chunk size
XPP_AFP_SEND:
        BRA.W   XPP_USERCMD                     | send the Command / Write

| -------------------------------------------------------------------------
| XPP_AFP_STEP -- an ASP call of an AFPCommand has ended (A0 = the call,
| D0 = result): FPLogin/FPLoginCont go on in XPP_AFP_LOGINSTEP,
| FPRead/FPWrite in XPP_AFP_RWSTEP; any other command is done
| (XPP_AFP_DONE: csCode = afpCall again, complete the call).
| Branch from: XPP_CALLDONE
| -------------------------------------------------------------------------
XPP_AFP_STEP:
        BSR.W   XPP_CALLHOOK                    | let a patch see this step
        MOVEA.L cbPtr(A0),A1                    | A1 = AFP command block
        MOVE.B  (A1),D1                         | D1 = AFP command
        CMPI.B  #afpLogin,D1                    | FPLogin?
        BEQ.B   XPP_AFP_LOGINSTEP               | yes ->
        CMPI.B  #afpContLogin,D1                | FPLoginCont (19)?
        BEQ.B   XPP_AFP_LOGINSTEP               | yes ->
        LEA.L   wdSize(A0),A3                   | A3 -> wdSize
        CMPI.B  #afpWrite,D1                    | FPWrite?
        BEQ.B   XPP_AFP_RWSTEP                  | yes ->
        SUBQ.W  #wdSize-rbSize,A3               | A3 -> rbSize
        CMPI.B  #afpRead,D1                     | FPRead?
        BEQ.B   XPP_AFP_RWSTEP                  | yes ->
| XPP_AFP_DONE -- complete the AFPCommand with D0
| Branch from: XPP_AFP_LOGINSTEP, XPP_AFP_LOGINREPLY, XPP_AFP_RWDONE
XPP_AFP_DONE:
        MOVE.W  #afpCall,csCode(A0)             | csCode = afpCall again
        BRA.W   XPP_COMPLETE                    | complete the call
| FPLogout: ASP CloseSession of sessRefnum
XPP_AFP_LOGOUT:
        MOVE.B  #closeSess,csCode+1(A0)         | ASP call: CloseSession
        BRA.W   XPP_CLOSESESS                   | close the session
| FPLogin: first open a session (afpAddrBlock, afpSCBPtr, afpAttnRoutine;
| these overlap the CCB, which the login command later uses)
XPP_AFP_LOGIN:
        CMPI.W  #maxCmdSize,cbSize(A0)          | command block > 578 bytes?
        BHI.W   XPP_ERRDONE                     | yes -> error (D0 = controlErr here: bug, not aspSizeErr)
        MOVE.B  #openSess,csCode+1(A0)          | ASP call: OpenSession
        MOVEA.L afpSCBPtr(A0),A2                | A2 = SCB
        MOVE.L  afpAddrBlock(A0),D3             | D3 = server address (SLS)
        MOVE.L  afpAttnRoutine(A0),D2           | D2 = attention routine
        BRA.W   XPP_DOOPEN                      | open the session
| FPLogin/FPLoginCont step: after the OpenSession send the login command
| (Command); after the Command check cmdResult: 0 or afpAuthContinue
| completes the call, anything else closes the session (CloseSession),
| after which the call completes (ioResult noErr, cmdResult the error)
XPP_AFP_LOGINSTEP:
        TST.W   D0                              | ASP call failed?
        BNE.B   XPP_AFP_DONE                    | yes -> complete with the error
        LEA.L   csCode+1(A0),A1                 | A1 -> ASP call just done
        CMPI.B  #userCommand,(A1)               | the login command?
        BEQ.B   XPP_AFP_LOGINREPLY              | yes -> check the server's answer
        CMPI.B  #closeSess,(A1)                 | the CloseSession after a failure?
        BEQ.B   XPP_AFP_DONE                    | yes -> complete
        MOVE.B  #userCommand,(A1)               | session open: ASP call Command
        BRA.W   XPP_USERCMD                     | send the login command
XPP_AFP_LOGINREPLY:
        MOVE.L  cmdResult(A0),D1                | D1 = AFP result from the server
        BEQ.B   XPP_AFP_DONE                    | 0: logged in ->
        CMPI.W  #afpAuthContinue,D1             | afpAuthContinue (-5001): go on with FPLoginCont?
        BEQ.B   XPP_AFP_DONE                    | yes -> complete
        MOVE.B  #closeSess,(A1)                 | login refused: ASP call CloseSession
        BRA.W   XPP_CLOSESESS                   | close the session
| FPRead/FPWrite step (A3 -> rbSize / wdSize = bytes of this chunk):
| count the bytes; stop on an error, when cmdResult is not 0, when the
| chunk covers the rest of reqCount or, when reading with newLineFlag,
| when the chunk ends with newLineChar; else advance rwOffset, reqCount
| and rbPtr/wdPtr and send the next chunk.
XPP_AFP_RWSTEP:
        TST.W   D0                              | chunk failed?
        BNE.B   XPP_AFP_RWDONE                  | yes -> finish
        MOVEQ.L #0x0,D3                         | clear the high word
        MOVE.W  (A3)+,D3                        | D3 = bytes moved now; A3 -> rbPtr / wdPtr
        ADD.L   D3,ioCmdAddr(A0)                | add to the total
        TST.L   cmdResult(A0)                   | AFP error (end of file, ...)?
        BNE.B   XPP_AFP_RWDONE                  | yes -> finish
        CMP.L   reqCount(A1),D3                 | all requested bytes moved?
        BCC.B   XPP_AFP_RWDONE                  | yes -> finish
        CMPI.B  #afpRead,D1                     | reading?
        BNE.B   XPP_AFP_WRITEMORE               | no, writing ->
        TST.B   newLineFlag(A1)                 | stop at a newline character?
        BPL.B   XPP_AFP_RWADVANCE               | no ->
        MOVEA.L (A3),A2                         | A2 = start of this chunk (rbPtr)
        MOVE.B  -0x1(A2,D3.W),D1                | D1 = last byte read
        CMP.B   newLineChar(A1),D1              | the newline character?
        BEQ.B   XPP_AFP_RWDONE                  | yes -> the read ends here
XPP_AFP_RWADVANCE:
        ADD.L   D3,rwOffset(A1)                 | rwOffset += chunk
XPP_AFP_RWCOUNT:
        SUB.L   D3,reqCount(A1)                 | reqCount -= chunk
        ADD.L   D3,(A3)                         | rbPtr / wdPtr += chunk
        BRA.W   XPP_AFP_NEXT                    | send the next chunk
| writing: an offset from the end of the fork (startEndFlag) holds for
| the first chunk only; then continue at the reply's lastWritten
XPP_AFP_WRITEMORE:
        BCLR    #0x7,startEndFlag(A1)           | offset from the end? (now from the start)
        BEQ.B   XPP_AFP_RWADVANCE               | no -> advance rwOffset
        MOVEA.L rbPtr(A0),A2                    | A2 = FPWrite reply
        MOVE.L  lastWritten(A2),D1              | D1 = offset after the bytes written
        MOVE.L  D1,rwOffset(A1)                 | rwOffset = that (from the start)
        BRA.B   XPP_AFP_RWCOUNT                 | count the chunk
XPP_AFP_RWDONE:
        MOVE.L  ioCmdAddr(A0),reqCount(A1)      | reqCount = bytes moved in all
        BRA.W   XPP_AFP_DONE                    | complete the AFPCommand

| -------------------------------------------------------------------------
| XPP_SRVREQ -- completion of the GetRequest on the WSS (A0 = scbReqPB):
| a request from the server. It counts only with the session's ID and
| from the server's node (and net, when both nets are known); then the
| session timer restarts and the ASP command decides: CloseSess ->
| XPP_SRVCLOSE, WriteContinue -> XPP_WRITECONT, Attention ->
| XPP_ATTENTION. Anything else (the server's Tickle, strangers) just
| re-arms the GetRequest (still set up in A0).
| -------------------------------------------------------------------------
XPP_SRVREQ:
        MOVE.W  #0x2,reqLength(A0)              | buffer size 2 again for the next request
        LEA.L   -scbReqPB(A0),A2                | A2 = SCB
        MOVE.B  userData+aspSessID(A0),D1       | D1 = session ID of the request
        CMP.B   scbSessID(A2),D1                | our session?
        BNE.B   XPP_SRVREQ_IGNORE               | no -> ignore
        MOVE.W  addrBlock(A0),D2                | D2 = sender's net
        BEQ.B   XPP_SRVREQ_NODE                 | 0: no net to compare ->
        MOVE.W  scbSrvAddr(A2),D3               | D3 = server's net
        BEQ.B   XPP_SRVREQ_NODE                 | 0: no net to compare ->
        CMP.W   D2,D3                           | same net?
        BNE.B   XPP_SRVREQ_IGNORE               | no -> ignore
XPP_SRVREQ_NODE:
        MOVE.B  addrBlock+2(A0),D2              | D2 = sender's node
        CMP.B   scbSrvAddr+2(A2),D2             | the server's node?
        BNE.B   XPP_SRVREQ_IGNORE               | no -> ignore
        MOVE.W  #tickleTime,scbVBL+vblCount(A2) | the server is there: restart the session timer
        MOVE.B  userData(A0),D1                 | D1 = ASP command (aspCmdCode)
        SUBQ.B  #aspCloseSess,D1                | CloseSess (1)?
        BEQ.B   XPP_SRVCLOSE                    | yes -> the server closes the session
        SUBQ.B  #aspDataWrite-aspCloseSess,D1   | WriteContinue (7)?
        BEQ.W   XPP_WRITECONT                   | yes -> send the write data
        SUBQ.B  #aspAttention-aspDataWrite,D1   | Attention (8)?
        BEQ.B   XPP_ATTENTION                   | yes -> attention
XPP_SRVREQ_IGNORE:
        _ControlAsync                           | re-issue the GetRequest
XPP_SRVREQ_RTS:
        RTS                                     | return from XPP_SRVREQ

| -------------------------------------------------------------------------
| XPP_SRVCLOSE -- the server sent CloseSess (A0 = scbReqPB, A2 = SCB):
| unless the session is already closing, answer it with an empty
| SendResponse (one 0-byte BDS entry at scbAuxPB); then
| XPP_SRVCLOSE_REPLIED stops the session timer and closes the session
| without sending CloseSess (ssDead). The GetRequest is not re-armed.
| -------------------------------------------------------------------------
XPP_SRVCLOSE:
        LEA.L   scbState(A2),A1                 | A1 -> session state
        CMPI.B  #ssClosing,(A1)                 | already closing?
        BEQ.B   XPP_SRVREQ_RTS                  | yes -> ignore the request
        CMPI.B  #ssDead,(A1)                    | already closed by the server?
        BEQ.B   XPP_SRVREQ_RTS                  | yes -> ignore
        MOVE.B  #ssClosing,(A1)                 | session state: closing
        LEA.L   scbAuxPB(A2),A1                 | A1 = one-entry response BDS
        MOVE.L  A1,bdsPointer(A0)               | bdsPointer = scbAuxPB
        CLR.L   (A1)+                           | bdsBuffSz 0, bdsBuffAdr high word 0
        CLR.L   (A1)+                           | bdsBuffAdr low word 0, bdsDataSz 0
        CLR.L   (A1)+                           | bdsUserData = 0
        MOVE.W  #0x101,numOfBuffs(A0)           | numOfBuffs = 1, bdsSize = 1
        MOVE.W  #sendResponse,D0                | .ATP SendResponse
        LEA.L   XPP_SRVCLOSE_REPLIED(PC),A3     | continue in XPP_SRVCLOSE_REPLIED
        BRA.W   XPP_CALLATP                     | answer the CloseSess

| -------------------------------------------------------------------------
| XPP_SRVCLOSE_REPLIED -- completion of the CloseSess response (A0 =
| scbReqPB): stop the session timer, then as at a timeout:
| XPP_SESSTIMEOUT -- VBL task of the session timer (A0 = scbVBL): nothing
| heard from the server for 2 minutes. Mark the session ssDead and close
| it without CloseSess (XPP_KILLTICKLE). The VBL task's vblCount stays 0,
| so the Vertical Retrace Manager removes it.
| -------------------------------------------------------------------------
XPP_SRVCLOSE_REPLIED:
        LEA.L   scbVBL-scbReqPB(A0),A0          | A0 = session timer
        _VRemove                                | stop it
XPP_SESSTIMEOUT:
        LEA.L   -scbVBL(A0),A2                  | A2 = SCB
        MOVE.B  #ssDead,scbState(A2)            | session state: closed by the server / timed out
        BRA.W   XPP_KILLTICKLE                  | close the session

| -------------------------------------------------------------------------
| XPP_ATTENTION -- the server sent an Attention (A0 = scbReqPB, A2 =
| SCB): put the attention bytes into the SCB (scbAttnBytes), answer with
| an empty AddResponse (completion XPP_GETREQUEST re-arms the
| GetRequest), then call the attention routine, if any and the bytes are
| not 0, with D0 = sessRefnum and D1 = attention bytes.
| -------------------------------------------------------------------------
XPP_ATTENTION:
        MOVE.W  userData+aspAttnCode(A0),D1     | D1 = attention bytes
        MOVE.W  D1,scbAttnBytes(A2)             | first word of the SCB = attention bytes
        MOVEA.L scbAttnRtn(A2),A1               | A1 = attention routine
        CLR.L   userData(A0)                    | response user bytes = 0
        CLR.W   reqLength(A0)                   | no response data
        CLR.B   atpFlags(A0)                    | atpFlags = 0
        CLR.B   rspNum(A0)                      | response number 0
        MOVE.W  #addResponse,D0                 | .ATP AddResponse
        LEA.L   XPP_GETREQUEST(PC),A3           | then listen again (XPP_GETREQUEST)
        BSR.W   XPP_CALLATP                     | answer the Attention
        MOVE.L  A1,D0                           | attention routine given?
        BEQ.B   XPP_ATTENTION_RTS               | no ->
        TST.W   D1                              | attention bytes 0?
        BEQ.B   XPP_ATTENTION_RTS               | yes -> no call
        MOVE.W  scbRefnum(A2),D0                | D0 = sessRefnum
        JMP     (A1)                            | -> attention routine (D0, D1), returns to our caller
XPP_ATTENTION_RTS:
        RTS                                     | return from XPP_ATTENTION

| -------------------------------------------------------------------------
| XPP_GETREQUEST -- issue the GetRequest on the WSS that receives the
| server's requests (2-byte buffer at scbWrBSize); completion XPP_SRVREQ.
|   A0 (in) -- scbReqPB (atpSocket = WSS, reqPointer set)
| Called by: XPP_OPENED; completion routine of XPP_ATTENTION's AddResponse
| -------------------------------------------------------------------------
XPP_GETREQUEST:
        MOVE.W  #0x2,reqLength(A0)              | reqLength = 2 (buffer size word)
        MOVE.W  #getRequest,D0                  | .ATP GetRequest
        LEA.L   XPP_SRVREQ(PC),A3               | continue in XPP_SRVREQ
        BRA.W   XPP_CALLATP                     | listen on the WSS

| -------------------------------------------------------------------------
| XPP_WRITECONT -- the server sent WriteContinue (A0 = scbReqPB, A2 =
| SCB, request data scbWrBSize = buffer size at the server): find the
| UserWrite with this sequence number and send it its write data as the
| response (SendResponse from the WSS, EOM, as much as the server's
| buffer takes; wdSize returns that size); completion XPP_WRITEDATA_SENT.
| Then (or if no such Write is active) re-arm the GetRequest.
| -------------------------------------------------------------------------
XPP_WRITECONT:
        MOVE.W  userData+aspSeqNum(A0),D1       | D1 = sequence number of the Write
        MOVE.W  scbWrBSize(A2),D2               | D2 = buffer size at the server
        MOVEA.L A0,A3                           | A3 = the GetRequest pb
        LEA.L   scbCallList(A2),A0              | A0 = list head
XPP_WRITECONT_FIND:
        MOVE.L  (A0),D0                         | D0 = next active call
        BEQ.B   XPP_WRITECONT_REARM             | none -> ignore the request
        MOVEA.L D0,A0                           | A0 = the call
        CMPI.B  #userWrite,csCode+1(A0)         | a UserWrite?
        BNE.B   XPP_WRITECONT_FIND              | no -> next
        CMP.W   ccbStart+userData+aspSeqNum(A0),D1 | its sequence number?
        BNE.B   XPP_WRITECONT_FIND              | no -> next
        BSR.W   XPP_GETWRPB                     | A1 = its write data ATP pb
        MOVE.W  reqLength(A1),D1                | D1 = size to write
        CMP.W   D1,D2                           | does the server take it all?
        BCC.B   XPP_WRITECONT_SIZE              | yes ->
        MOVE.W  D2,D1                           | no: only the server's buffer size
XPP_WRITECONT_SIZE:
        MOVE.W  D1,wdSize(A0)                   | wdSize = bytes written
        MOVEA.L A1,A0                           | A0 = write data pb
        MOVE.L  addrBlock(A3),addrBlock(A0)     | addrBlock = requester (the server)
        MOVE.W  transID(A3),transID(A0)         | transID of the WriteContinue
        MOVE.B  scbWSS(A2),atpSocket(A0)        | atpSocket = WSS
        LEA.L   ioQElSize(A0),A1                | A1 = write data BDS, after the pb
        SUBQ.W  #0x1,D1                         | size - 1
        EXT.L   D1                              | as a long
        DIVS.W  #atpMaxData,D1                  | D1 = rest:index of the last packet
        MOVE.W  D1,D2                           | D2 = index of the last packet
        MULU.W  #bdsEntrySz,D2                  | D2 = offset of its BDS entry
        SWAP    D1                              | D1 = (size - 1) MOD 578
        ADDQ.W  #0x1,D1                         | D1 = bytes in the last packet
        MOVE.W  D1,bdsBuffSz(A1,D2.W)           | last entry's bdsBuffSz = those bytes
        MOVE.L  A1,bdsPointer(A0)               | bdsPointer = write data BDS
        SWAP    D1                              | D1 = index of the last packet
        ADDQ.W  #0x1,D1                         | D1 = number of packets
        MOVE.B  D1,numOfBuffs(A0)               | numOfBuffs = packets to send
        MOVE.B  D1,bdsSize(A0)                  | bdsSize = BDS entries
        MOVE.B  #atpEOMvalue,atpFlags(A0)       | atpFlags = EOM: that is all
        MOVEA.L A3,A1                           | A1 = the GetRequest pb (keep it)
        MOVE.W  #sendResponse,D0                | .ATP SendResponse
        LEA.L   XPP_WRITEDATA_SENT(PC),A3       | continue in XPP_WRITEDATA_SENT
        BSR.W   XPP_CALLATP                     | send the write data
        MOVEA.L A1,A3                           | A3 = the GetRequest pb
XPP_WRITECONT_REARM:
        MOVEA.L A3,A0                           | A0 = the GetRequest pb
        _ControlAsync                           | re-issue the GetRequest
        RTS                                     | return from XPP_WRITECONT

| -------------------------------------------------------------------------
| XPP_WRITEDATA_SENT -- completion of the write data response (A0 = write
| data pb, reqPointer = the UserWrite call). If the Write's request has
| already finished (reply in), complete the call now with the session's
| status (noErr, or aspSessClosed when closing); else XPP_CMDREPLY will.
| In the first case the request's own result (e.g. aspBufTooSmall from
| XPP_REPLYSIZE) is not kept: XPP_CMDREPLY returned without storing it.
| -------------------------------------------------------------------------
XPP_WRITEDATA_SENT:
        MOVEA.L reqPointer(A0),A0               | A0 = the UserWrite call
        MOVE.W  SR,-(SP)                        | save the interrupt level
        MOVE.W  #0x2600,SR                      | interrupts off (level 6)
        TST.W   ccbStart+ioResult(A0)           | Write request still under way?
        BGT.B   XPP_WRITEDATA_SENT_EXIT         | yes -> XPP_CMDREPLY completes the call
        MOVE.W  sessRefnum(A0),D1               | D1 = sessRefnum
        BSR.B   XPP_FINDSESS                    | A2 = SCB, D0 = noErr or aspSessClosed
        BSR.W   XPP_UNLINKDONE                  | unlink and complete the call
XPP_WRITEDATA_SENT_EXIT:
        MOVE.W  (SP)+,SR                        | interrupts back on
        RTS                                     | return from XPP_WRITEDATA_SENT

| -------------------------------------------------------------------------
| XPP_GETWRPB -- the write data ATP pb of a UserWrite call: after the
| CCB's request pb and its reply BDS (numOfBuffs entries).
|   A0 (in)  -- the UserWrite call;  A1 (out) -- write data ATP pb
| Changes D3.
| Called by: XPP_ABORTCALLS, XPP_CMDREPLY_OK, XPP_WRITECONT_FIND
| -------------------------------------------------------------------------
XPP_GETWRPB:
        MOVEQ.L #0x0,D3                         | clear the high bytes
        MOVE.B  ccbStart+numOfBuffs(A0),D3      | D3 = reply BDS entries
        MULU.W  #bdsEntrySz,D3                  | D3 = size of the reply BDS
        LEA.L   ccbStart+ioQElSize(A0,D3.W),A1  | A1 = write data pb after it
        RTS                                     | return from XPP_GETWRPB

| -------------------------------------------------------------------------
| XPP_GETVARS -- A1 (out) = the driver variables (AGB xppVarPtr).
| Called by: XPP_GETPARMS, XPP_DONE, XPP_DEQUEUE, XPP_LASTSLOT
| -------------------------------------------------------------------------
XPP_GETVARS:
        MOVEA.L (AGBHandle).W,A1                | A1 = AGB handle
        MOVEA.L (A1),A1                         | A1 = AGB
        MOVEA.L xppVarPtr(A1),A1                | A1 = driver variables
        RTS                                     | return from XPP_GETVARS

| -------------------------------------------------------------------------
| XPP_FINDSESS -- look up a session by its sessRefnum.
|   D1 (in)  -- sessRefnum (generation << 8 + 4 * slot)
|   A2 (out) -- its SCB (when the slot is in use)
|   D0 (out) -- noErr (session open), aspSessClosed (closing, aborted or
|               closed by the server), aspParamErr (no such session or
|               still opening); CCR set accordingly (BNE = error)
| Preserves A1.
| Called by: XPP_CLOSESESS, XPP_USERCMD, XPP_CMDREPLY, XPP_WRITEDATA_SENT
| -------------------------------------------------------------------------
XPP_FINDSESS:
        MOVE.L  A1,-(SP)                        | save A1
        BSR.B   XPP_LASTSLOT                    | A1 = variables, D0 = offset of the last slot
        CMP.B   D0,D1                           | slot offset beyond the last slot?
        BHI.B   XPP_FINDSESS_BAD                | yes -> aspParamErr
        MOVE.B  D1,D0                           | D0 = slot byte of the refNum
        ANDI.W  #0xFC,D0                        | D0 = 4 * slot
        MOVEA.L xppSessTbl(A1,D0.W),A2          | A2 = SCB in that slot
        MOVE.L  A2,D0                           | slot in use?
        BEQ.B   XPP_FINDSESS_BAD                | no -> aspParamErr
        CMP.W   scbRefnum(A2),D1                | the same session (generation)?
        BNE.B   XPP_FINDSESS_BAD                | no -> aspParamErr
        CMPI.B  #ssOpening,scbState(A2)         | still being opened?
        BEQ.B   XPP_FINDSESS_BAD                | yes -> aspParamErr
        MOVE.W  #aspSessClosed,D0               | D0 = aspSessClosed (-1072)
        CMPI.B  #ssOpen,scbState(A2)            | open?
        BNE.B   XPP_FINDSESS_EXIT               | no -> aspSessClosed
        CLR.W   D0                              | noErr
XPP_FINDSESS_EXIT:
        MOVEA.L (SP)+,A1                        | restore A1
        RTS                                     | return D0 and the CCR
XPP_FINDSESS_BAD:
        MOVE.W  #aspParamErr,D0                 | aspParamErr (-1070)
        BRA.B   XPP_FINDSESS_EXIT               | return the error

| -------------------------------------------------------------------------
| XPP_NEWSESS -- take a free session slot for the SCB A2: store the SCB
| in it, clear the SCB (186 bytes, up to scbAttnRtn) and put the new
| sessRefnum = generation << 8 + 4 * slot into scbRefnum. The generation
| count is bumped on every attempt.
|   A2 (in)  -- SCB
|   D1 (out) -- sessRefnum
|   D0 (out) -- noErr, or aspNoMoreSess (CCR set). Preserves A1.
| Called by: XPP_DOOPEN
| -------------------------------------------------------------------------
XPP_NEWSESS:
        MOVE.L  A1,-(SP)                        | save A1
        BSR.B   XPP_LASTSLOT                    | A1 = variables, D0 = offset of the last slot
        MOVE.B  xppGen(A1),D1                   | D1 = generation count
        ADDQ.B  #0x1,xppGen(A1)                 | bump it
        ASL.W   #0x8,D1                         | D1 = generation << 8
XPP_NEWSESS_LOOP:
        TST.L   xppSessTbl(A1,D0.W)             | slot free?
        BEQ.B   XPP_NEWSESS_FOUND               | yes ->
        SUBQ.W  #0x4,D0                         | previous slot
        BPL.B   XPP_NEWSESS_LOOP                | look on
        MOVE.W  #aspNoMoreSess,D0               | all in use: aspNoMoreSess (-1068)
        BRA.B   XPP_NEWSESS_EXIT                | return the error
XPP_NEWSESS_FOUND:
        MOVE.L  A2,xppSessTbl(A1,D0.W)          | the slot belongs to this SCB
        MOVE.B  D0,D1                           | D1 = generation << 8 + 4 * slot
        MOVEA.L A2,A1                           | A1 = SCB
        MOVEQ.L #0x5D,D0                        | 93 words = SCB+$00..$B9
XPP_NEWSESS_CLEAR:
        CLR.W   (A1)+                           | clear the SCB
        SUBQ.W  #0x1,D0                         | count words
        BNE.B   XPP_NEWSESS_CLEAR               | next (D0 ends as 0: noErr)
        MOVE.W  D1,scbRefnum(A2)                | scbRefnum = sessRefnum
XPP_NEWSESS_EXIT:
        MOVEA.L (SP)+,A1                        | restore A1
        TST.W   D0                              | CCR = result
        RTS                                     | return from XPP_NEWSESS

| -------------------------------------------------------------------------
| XPP_LASTSLOT -- A1 (out) = driver variables, D0 (out) = offset of the
| last session slot in xppSessTbl: 4 * (xppMaxSess - 1).
| Called by: XPP_FINDSESS, XPP_NEWSESS, XPP_FREESESS, XPP_ANYSESS
| -------------------------------------------------------------------------
XPP_LASTSLOT:
        BSR.B   XPP_GETVARS                     | A1 = driver variables
        MOVEQ.L #0x0,D0                         | clear the high bytes
        MOVE.B  xppMaxSess(A1),D0               | D0 = number of slots (10)
        SUBQ.W  #0x1,D0                         | last slot number
        ASL.W   #0x2,D0                         | D0 = its offset (* 4)
        RTS                                     | return from XPP_LASTSLOT

| -------------------------------------------------------------------------
| XPP_FREESESS -- free the session slot of the SCB A2.
|   D0 (out) -- 0 when found (else negative). Changes A1.
| Called by: XPP_OPENFAIL, XPP_WSSCLOSED
| -------------------------------------------------------------------------
XPP_FREESESS:
        BSR.B   XPP_LASTSLOT                    | A1 = variables, D0 = offset of the last slot
XPP_FREESESS_LOOP:
        CMPA.L  xppSessTbl(A1,D0.W),A2          | slot of this SCB?
        BEQ.B   XPP_FREESESS_FOUND              | yes ->
        SUBQ.W  #0x4,D0                         | previous slot
        BPL.B   XPP_FREESESS_LOOP               | look on
        RTS                                     | not found
XPP_FREESESS_FOUND:
        CLR.L   xppSessTbl(A1,D0.W)             | slot free
        MOVEQ.L #0x0,D0                         | D0 = 0
        RTS                                     | return from XPP_FREESESS

| -------------------------------------------------------------------------
| XPP_LINKCALL -- put the call A0 at the head of the active-call list of
| the session A2 (through its qLink), interrupts off.
| Called by: XPP_CLOSESESS, XPP_USERCMD_SEND
| -------------------------------------------------------------------------
XPP_LINKCALL:
        MOVE.W  SR,-(SP)                        | save the interrupt level
        MOVE.W  #0x2600,SR                      | interrupts off (level 6)
        MOVE.L  scbCallList(A2),(A0)            | qLink = old head of the list
        MOVE.L  A0,scbCallList(A2)              | the call is the new head
        MOVE.W  (SP)+,SR                        | interrupts back on
        RTS                                     | return from XPP_LINKCALL

| -------------------------------------------------------------------------
| XPP_ANYSESS -- find a session slot in use (from the last slot down).
|   A2 (out) -- its SCB
|   D0 (out) -- 0 and CCR EQ when one is found; negative and NE if none
| Called by: E_XPP_Close, XPP_CLOSEALL
| -------------------------------------------------------------------------
XPP_ANYSESS:
        BSR.B   XPP_LASTSLOT                    | A1 = variables, D0 = offset of the last slot
XPP_ANYSESS_LOOP:
        TST.L   xppSessTbl(A1,D0.W)             | slot in use?
        BNE.B   XPP_ANYSESS_FOUND               | yes ->
        SUBQ.W  #0x4,D0                         | previous slot
        BPL.B   XPP_ANYSESS_LOOP                | look on
        RTS                                     | none: D0 negative, NE
XPP_ANYSESS_FOUND:
        MOVEA.L xppSessTbl(A1,D0.W),A2          | A2 = its SCB
        MOVEQ.L #0x0,D0                         | D0 = 0, EQ
        RTS                                     | return from XPP_ANYSESS
    ROM_RESOURCE_END DRVR_40                    | end of the data: pads to even, sets the sizes

