| Scrap Manager -- InfoScrap, UnlodeScrap, LodeScrap, ZeroScrap, GetScrap, PutScrap
|
| Apple source: ScrapMgr.a (MacSEROM.lst module SCRAPMGR). The desk scrap
| (clipboard) lives in memory (ScrapState > 0) or in the file "Clipboard
| File" on the system volume (ScrapState = 0); ScrapState < 0 means it has
| not been initialized. ScrapStuff (low memory, ScrapSize $0960): +0
| scrapSize, +4 scrapHandle, +8 scrapCount, +10 scrapState, +12 scrapName.
| The scrap is a sequence of entries: type (4 bytes), length (4 bytes),
| data (padded to even length).
|
| References: Inside Macintosh Vol I, Ch 15 (The Scrap Manager).

| ----------------------------------------------------------
| Scrap Manager: InfoScrap, UnloadScrap, LoadScrap, ZeroScrap, GetScrap,
| PutScrap. Low-memory globals (the ScrapStuff record): ScrapSize ($960),
| ScrapHandle ($964), ScrapCount ($968), ScrapState ($96A: > 0 scrap in
| memory, 0 on disk, < 0 not initialized) and ScrapName ($96C).
| Each scrap entry is type (4 bytes), length (4 bytes) and the data,
| padded to an even length.
| ----------------------------------------------------------
|
| _InfoScrap ($A9F9): return a pointer to the scrap information
| Pascal: FUNCTION InfoScrap: PScrapStuff;
| Returns @ScrapSize, the start of the ScrapStuff globals.
|
InfoScrap:
        MOVE.L  (SP)+,A0                        | pop return address
        LEA.L     (ScrapSize).w,A1              | A1 = ScrapSize lomem
        MOVE.L  A1,(SP)                         | function result := @ScrapSize
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| XTRIMMEASURE_CONT_6_CONT_3 - common prologue of the Scrap Manager traps
| Builds a LINK A6 frame (with the trap caller's return address at
| 4(A6)) and saves D2-D7/A2-A4; D4 = ScrapSize, D5 = ScrapHandle,
| D6.W = ScrapState (high word ScrapCount), A2 = ScrapName,
| A4 = @ScrapHandle, A3 = A0 = IOParam for the Clipboard File at
| -$50(A6). If the scrap is on disk (ScrapState = 0) the file is opened
| (XTRIMMEASURE_CONT_6_CONT_4: _Open, opWrErr accepted, _Create and retry
| if not found). Exit: D0 = result code, CCR set from it.
| Called by: XTRIMMEASURE_CONT_6_CONT_4, XTRIMMEASURE_CONT_6_CONT_9, XTRIMMEASURE_CONT_6_CONT_11, XTRIMMEASURE_CONT_6_CONT_16, GETSCRAP_DONE
XTRIMMEASURE_CONT_6_CONT_3:
        MOVE.L  (SP)+,A1                        | A1 = saved return address
        LINK    A6,#-0x58                       | set up stack frame
        MOVEM.L D2-D7/A2-A4,-(SP)               | save working registers
        MOVE.L  A1,-(SP)                        | re-push return address
        MOVEM.L (ScrapSize).w,D4-D6/A2          | (ScrapSize).w -> D4-D6/A2
        LEA.L     (ScrapHandle).w,A4            | A4 -> scrap globals (handle/state)
        LEA.L     -0x50(A6),A0                  | A0 -> local IOParam block
        MOVE.L  A0,A3                           | A3 = IOParam block ptr
        MOVE.L  A2,18(A0)                       | ioFileName = scrap filename ptr
        CLR     22(A0)                          | ioVRefNum = 0 (default volume)
        CLR     26(A0)                          | ioVersNum, ioPermssn := 0 (fsCurPerm)
        CLR.L   28(A0)                          | ioMisc = 0
        TST     D6                              | ScrapState = 0 (scrap on disk)?
        BNE.B   XTRIMMEASURE_CONT_6_CONT_8      | no (in memory or uninit): skip open
XTRIMMEASURE_CONT_6_CONT_4:
        _Open                                   | open Clipboard File
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_9      | success: return ioRefNum
        CMPI    #-0x31,D0                       | opWrErr (-49): file already open?
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_8      | yes -> treat as success
        CMPI    #-0x2B,D0                       | fnfErr (file not found)?
        BNE.B   XTRIMMEASURE_CONT_6_CONT_9      | other err: return error
        _Create                                 | file missing: create it
        BNE.B   XTRIMMEASURE_CONT_6_CONT_9      | create failed: return error
        BRA.B   XTRIMMEASURE_CONT_6_CONT_4      | retry _Open
| ----------------------------------------------------------
|
| _UnlodeScrap ($A9FA): write the scrap to the Clipboard File
| Pascal: FUNCTION UnloadScrap: LongInt;
| If the scrap is in memory: opens (or creates) the Clipboard File,
| writes ScrapSize bytes from ScrapHandle at position 0, disposes the
| handle and clears ScrapHandle and the ScrapCount/ScrapState long
| (scrap now on disk). Otherwise just returns noErr. The file is left
| open. Result: OSErr as a LongInt.
|
UnloadScrap:
        BSR.B   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | setup err: return error
        TST     D6                              | ScrapState: in memory?
        BLE.B   XTRIMMEASURE_CONT_6_CONT_5      | on disk/uninit: noErr
        BSR.B   XTRIMMEASURE_CONT_6_CONT_4      | open (or create) the Clipboard File
        MOVE.L  D4,D0                           | D0 = ScrapSize
        BSR.B   XTRIMMEASURE_CONT_6_CONT_10     | build IOParam from handle
        _Write                                  | write scrap to file
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | write err: return error
        MOVE.L  D5,A0                           | A0 = ScrapHandle
        _DisposeHandle                          | free in-memory scrap
        CLR.L   (A4)+                           | ScrapHandle := NIL
        CLR.L   (A4)+                           | ScrapCount := 0, ScrapState := 0 (on disk)
XTRIMMEASURE_CONT_6_CONT_5:
        MOVEQ.L #0x0,D0                         | D0 = noErr
XTRIMMEASURE_CONT_6_CONT_6:
        EXT.L    D0                             | sign-extend result
        MOVE.L  D0,8(A6)                        | store result (LongInt) in the function result
        MOVEQ.L #0x0,D0                         | strip 0 param bytes
XTRIMMEASURE_CONT_6_CONT_7:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore working registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  D0,SP                           | SP += D0
        JMP     (A0)                            | RTS
XTRIMMEASURE_CONT_6_CONT_8:
        MOVEQ.L #0x0,D0                         | D0 = noErr
XTRIMMEASURE_CONT_6_CONT_9:
        RTS                                     | return from setup
| ----------------------------------------------------------
|
| _LodeScrap ($A9FB): read the scrap from the Clipboard File into memory
| Pascal: FUNCTION LoadScrap: LongInt;
| If the scrap is on disk: NewHandle(ScrapSize) -> ScrapHandle,
| ScrapState := 1 (in memory), then reads ScrapSize bytes from position
| 0 of the (already opened) Clipboard File. Otherwise returns noErr.
| Apple source name: LoadScrap (MacSEROM.lst: LOADSCRAP)
|
LodeScrap:
        BSR.B   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | setup err: return error
        TST     D6                              | ScrapState <> 0 (in memory / uninit)?
        BNE.B   XTRIMMEASURE_CONT_6_CONT_5      | yes: just return
        MOVE.L  D4,D0                           | D0 = ScrapSize
        _NewHandle                              | allocate scrap buffer
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | alloc fail: error
        MOVE.L  A0,(A4)+                        | ScrapHandle = new handle
        ADDQ.L  #0x1,(A4)+                      | ScrapState := 1 (in memory)
        BSR.B   XTRIMMEASURE_CONT_6_CONT_11     | build IOParam from A0
        _Read                                   | read scrap data from file
        BRA.B   XTRIMMEASURE_CONT_6_CONT_6      | return result code
| XTRIMMEASURE_CONT_6_CONT_10/_11 - set up the IOParam at A3 for a read or
| write of D0 bytes from position 0, buffer = ScrapHandle^ (_10) or A0^
| (_11); returns A0 = A3.
XTRIMMEASURE_CONT_6_CONT_10:
        MOVE.L  D5,A0                           | A0 = ScrapHandle
XTRIMMEASURE_CONT_6_CONT_11:
        MOVE.L  (A0),ioBuffer(A3)               | ioBuffer = *handle
        MOVE.L  D0,ioByteCount(A3)              | ioByteCount = D0
        MOVE    #0x1,0x2C(A3)                   | ioPosMode = fsFromStart
        CLR.L   ioPosOffset(A3)                 | ioPosOffset = 0
        MOVE.L  A3,A0                           | A0 = IOParam block
        RTS                                     | return with IOParam ready
| ----------------------------------------------------------
|
| _ZeroScrap ($A9FC): clear the scrap
| Pascal: FUNCTION ZeroScrap: LongInt;
| ScrapSize := 0 and ScrapCount := ScrapCount + 8. On disk: truncates
| the Clipboard File (_SetEOF 0). In memory: SetHandleSize(ScrapHandle,
| 0). Not initialized: allocates an empty handle; in the last two cases
| ScrapHandle := that handle and ScrapState := ScrapCount (in memory).
|
ZeroScrap:
        BSR.W   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | setup err: return
        MOVE.L  D0,(ScrapSize).w                | ScrapSize = 0
        ADDQ.W  #0x8,4(A4)                      | ScrapCount += 8
        TST     D6                              | scrap state?
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_14     | on disk: truncate file
        BGT.B   XTRIMMEASURE_CONT_6_CONT_12     | in memory: resize handle
        _NewHandle                              | uninit: allocate empty handle
        BRA.B   XTRIMMEASURE_CONT_6_CONT_13     | store handle, set state
XTRIMMEASURE_CONT_6_CONT_12:
        MOVE.L  D5,A0                           | A0 = ScrapHandle
        _SetHandleSize                          | shrink scrap to 0 bytes
XTRIMMEASURE_CONT_6_CONT_13:
        MOVE.L  A0,(A4)+                        | ScrapHandle := A0
        MOVE    (A4)+,(A4)                      | ScrapState := ScrapCount
        BRA.B   XTRIMMEASURE_CONT_6_CONT_6      | return result code
XTRIMMEASURE_CONT_6_CONT_14:
        CLR.L   28(A0)                          | ioMisc = 0 (truncate to 0)
        _SetEOF                                 | truncate Clipboard File
        BRA.B   XTRIMMEASURE_CONT_6_CONT_6      | return result code
| XTRIMMEASURE_CONT_6_CONT_15 - copy D0 bytes at scrap offset D3 to A1:
| BlockMove from ScrapHandle^ if the scrap is in memory, else _Read from
| the Clipboard File (XTRIMMEASURE_CONT_6_CONT_16). Exit: D0 = result.
XTRIMMEASURE_CONT_6_CONT_15:
        TST     D6                              | scrap on disk?
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_16     | yes: read from file
        MOVE.L  D5,A2                           | A2 = ScrapHandle
        MOVE.L  (A2),A0                         | A0 = *ScrapHandle
        ADDA.L  D3,A0                           | A0 += offset D3
        _BlockMove                              | copy D0 bytes to A1
        BRA.B   XTRIMMEASURE_CONT_6_CONT_8      | return noErr
XTRIMMEASURE_CONT_6_CONT_16:
        BSR.B   XTRIMMEASURE_CONT_6_CONT_10     | build IOParam from ScrapHandle
        MOVE.L  D3,0x2E(A0)                     | ioPosOffset = D3
        MOVE.L  A1,0x20(A0)                     | ioBuffer = A1 (caller dest)
        _Read                                   | read D0 bytes from file
        RTS                                     | return Read result
| ----------------------------------------------------------
|
| _GetScrap ($A9FD): get the data of a given type from the scrap
| Pascal: FUNCTION GetScrap(hDest: Handle; theType: ResType;
|                           VAR offset: LongInt): LongInt;
| Walks the scrap entries (8-byte type/length headers read with
| XTRIMMEASURE_CONT_6_CONT_15) until theType is found: offset := data
| offset, result := data length; unless hDest is NIL, hDest is resized
| and the data copied into it. Errors: noScrapErr (-100) if the scrap
| is not initialized, noTypeErr (-102) if theType is not found.
|
GetScrap:
        BSR.W   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   GETSCRAP_ERR                    | setup err: return error
        MOVEQ.L #-0x64,D0                       | D0 = noScrapErr (-100)
        TST     D6                              | scrap initialized?
        BMI.B   GETSCRAP_ERR                    | uninit: return error
        MOVEQ.L #0x0,D3                         | D3 = scan offset (0)
| scan through scrap entries looking for matching type
GETSCRAP_SCAN:
        CMP.L   D4,D3                           | D3 >= D4 (walked off end)?
        BGE.B   GETSCRAP_NOTYPE                 | yes: report noTypeErr (-> $FE0A)
        MOVEQ.L #0x8,D0                         | D0 = 8 bytes (type + length header)
        LEA.L     -0x58(A6),A1                  | A1 = local header buffer
        BSR.B   XTRIMMEASURE_CONT_6_CONT_15     | read the header at offset D3
        BNE.B   GETSCRAP_ERR                    | read error -> return it
        ADDQ.L  #0x8,D3                         | advance to next scrap entry
        MOVE.L  (A1)+,D7                        | D7 = entry type
        CMP.L   12(A6),D7                       | matches theType?
        BEQ.B   GETSCRAP_FOUND                  | yes: -> found path
        ADD.L   (A1)+,D3                        | skip entry data (length)
        ADDQ.L  #0x1,D3                         | round up by 1
        BCLR    D0,D3                           | clear bit 0 (D0 = 0 here): word-align
        BRA.B   GETSCRAP_SCAN                   | keep scanning
| ----------------------------------------------------------
| GETSCRAP_NOTYPE ($FE0A) - reached by the BGE.B above when GETSCRAP_SCAN
| walks past the end of the scrap without finding theType. Sets noTypeErr
| (-102) and branches to GETSCRAP_ERR+2 ($FE30), skipping its EXT.L since
| D0 is already a long.
GETSCRAP_NOTYPE:
        MOVEQ   #-0x66,D0                       | D0 = -102 (noTypeErr)
        BRA.B   GETSCRAP_ERR+2                  | store the error (skip EXT.L)
GETSCRAP_FOUND:
        MOVE.L  8(A6),A2                        | A2 -> VAR offset param
        MOVE.L  D3,(A2)                         | store data offset
        MOVE.L  (A1),D0                         | D0 = entry data length
        MOVE.L  D0,20(A6)                       | store length as result
        MOVE.L  16(A6),D1                       | D1 = hDest handle
        BEQ.B   GETSCRAP_DONE                   | NIL: just return length
        MOVE.L  D1,A0                           | A0 = hDest handle
        _SetHandleSize                          | resize hDest to D0 bytes
        BNE.B   GETSCRAP_ERR                    | resize failed: error
        MOVE.L  (A1),D0                         | D0 = data length again
        MOVE.L  (A0),A1                         | A1 = *hDest (dest ptr)
        BSR.B   XTRIMMEASURE_CONT_6_CONT_15     | copy D0 bytes from scrap+D3
        BEQ.B   GETSCRAP_DONE                   | success: return length
GETSCRAP_ERR:
        EXT.L    D0                             | sign-extend error code
        MOVE.L  D0,20(A6)                       | store error as result
GETSCRAP_DONE:
        MOVEQ.L #0xC,D0                         | strip 12 param bytes
        BRA.W   XTRIMMEASURE_CONT_6_CONT_7      | share scrap epilog
| ----------------------------------------------------------
|
| _PutScrap ($A9FE): append data of a given type to the scrap
| Pascal: FUNCTION PutScrap(length: LongInt; theType: ResType;
|                           source: Ptr): LongInt;
| noScrapErr (-100) if the scrap is not initialized. Appends the 8-byte
| header (theType and length are adjacent on the stack) and then the
| data, rounded up to an even length, with SCRAP_APPEND (PtrAndHand in
| memory, _Write at the end of the Clipboard File on disk), then
| updates ScrapSize. The prologue result is not checked.
|
PutScrap:
        BSR.W   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BSR.W   XTRIMMEASURE_CONT_6_CONT_10     | build IOParam from ScrapHandle
        MOVEQ.L #-0x64,D0                       | D0 = noScrapErr (-100)
        TST     D6                              | scrap initialized?
        BMI.B   GETSCRAP_ERR                    | uninit: error
        MOVEQ.L #0x8,D0                         | header size = 8 bytes
        LEA.L     12(A6),A0                     | A0 -> theType, length (8-byte header)
        BSR.B   SCRAP_APPEND                    | append type+length header
        MOVE.L  8(A6),A0                        | A0 = source data ptr
        MOVE.L  16(A6),D0                       | D0 = data length
        MOVEQ.L #-0x2,D1                        | D1 = even-mask
        ADDQ.L  #0x1,D0                         | length += 1 for round-up
        AND.L   D1,D0                           | align length to even
        BSR.B   SCRAP_APPEND                    | append data bytes
        MOVE.L  D4,-(A4)                        | ScrapSize := D4 (new total)
        BRA.B   GETSCRAP_ERR                    | epilog
| SCRAP_APPEND - append D0 bytes from A0 at scrap offset D4 (D4 += D0):
| PtrAndHand to ScrapHandle if in memory, else _Write to the file.
SCRAP_APPEND:
        MOVE.L  D4,0x2E(A3)                     | ioPosOffset = current end
        ADD.L   D0,D4                           | D4 += D0 (new size)
        TST     D6                              | scrap on disk?
        BEQ.B   SCRAP_WRITE_FILE                | yes: write to file
        MOVE.L  D5,A1                           | A1 = ScrapHandle
        _PtrAndHand                             | append A0[D0] to handle
        RTS                                     | return from append
SCRAP_WRITE_FILE:
        MOVE.L  A0,ioBuffer(A3)                 | ioBuffer = source A0
        MOVE.L  D0,ioByteCount(A3)              | ioByteCount = D0
        MOVE.L  A3,A0                           | A0 = IOParam block
        _Write                                  | write D0 bytes at end of file
        RTS                                     | return Write result
