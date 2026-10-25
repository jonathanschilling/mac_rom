| Scrap Manager - InfoScrap, UnloadScrap, LodeScrap, ZeroScrap, GetScrap, PutScrap
|
| Manages the desk scrap (clipboard) for cut/copy/paste between
| applications. The scrap lives either in memory (ScrapState > 0)
| or on disk as "Clipboard File" (ScrapState = 0). ScrapState < 0
| means the scrap has not been initialized yet.
|
| ScrapStuff record (low memory at ScrapSize/$0960):
| +0 scrapSize (long) total byte size of scrap data
| +4 scrapHandle (handle) handle to in-memory scrap data
| +8 scrapCount (word) change counter, bumped by ZeroScrap
| +10 scrapState (word) >0=in memory, 0=on disk, <0=uninitialized
| +12 scrapName (ptr) -> Pascal string for scrap filename
|
| Scrap on-disk/in-memory format:
| Repeating entries of [type(4 bytes) + length(4 bytes) + data(length bytes)]
| Data is padded to even length. Total size = ScrapSize.
|
| Common register usage in SCRAP_SETUP setup:
| D4 = ScrapSize, D5 = ScrapHandle, D6 = ScrapState (word)
| A2 = ScrapName, A3 = local IOParam block at -0x50(A6)
| A4 = pointer to ScrapHandle low-memory global ($0964)
|
| References:
| Inside Macintosh Vol I, Ch 15: Scrap Manager
|

| ----------------------------------------------------------
|
| _InfoScrap ($A9F9) - FUNCTION InfoScrap: PScrapStuff
|
| Returns a pointer to the ScrapStuff record (at ScrapSize/$0960).
| If the scrap is uninitialized (ScrapState < 0), calls ZeroScrap
| first to create an empty scrap.
|
| Called during boot (7,390 times in 30s trace).
InfoScrap:
        TST     (ScrapState).w                  | check scrap state
        BGE.B   INFOSCRAP_RETURN                | >= 0: scrap exists (memory or disk)
        SUBQ.W  #0x4,SP                         | make room for ZeroScrap result
        _ZeroScrap                              | initialize empty scrap
        ADDQ.W  #0x4,SP                         | discard ZeroScrap result code
INFOSCRAP_RETURN:
        MOVE.L  (SP)+,A0                        | pop return address
        LEA.L   (ScrapSize).w,A1                | A1 -> ScrapStuff record in low mem
        MOVE.L  A1,(SP)                         | return PScrapStuff pointer
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| SCRAP_SETUP - common Scrap Manager setup routine
|
| Creates a stack frame with a local IOParam block (-0x50(A6))
| and loads all scrap globals into registers. If scrap is on disk
| (ScrapState=0), opens the "Clipboard File", creating it if needed.
|
| Output registers:
| D4 = ScrapSize, D5 = ScrapHandle, D6.W = ScrapState
| A2 = ScrapName ptr, A3 = local IOParam block, A4 -> ScrapHandle global
| Returns D0 = 0 on success, nonzero error code on failure.
|
| Called during boot.
SCRAP_SETUP:
        MOVE.L  (SP)+,A1                        | pop return address (before LINK)
        LINK    A6,#-0x58                       | allocate 88-byte local frame
        MOVEM.L D2-D7/A2-A4,-(SP)               | save all work registers
        MOVE.L  A1,-(SP)                        | push return address back
| SCRAP_LOAD_GLOBALS -- reload scrap globals into registers.
SCRAP_LOAD_GLOBALS:
        MOVEM.L (ScrapSize).w,D4-D6/A2          | D4=size, D5=handle, D6=count|state, A2=name
        LEA.L   (ScrapHandle).w,A4              | A4 -> ScrapHandle global ($0964)
        LEA.L   -0x50(A6),A0                    | A0 -> local IOParam block (80 bytes)
        MOVE.L  A0,A3                           | A3 = IOParam block for subroutines
        MOVE.L  A2,ioFileName(A0)               | ioFileName -> ScrapName ("Clipboard File")
        MOVE    (BootDrive).w,ioVRefNum(A0)     | ioVRefNum = boot volume
        CLR     ioFileType(A0)                  | ioFileType = 0
        CLR.L   ioOwnBuf(A0)                    | ioOwnBuf = NIL (no private buffer)
        TST     D6                              | test ScrapState
        BNE.B   SCRAP_RTS_OK                    | nonzero: scrap in memory or uninit, skip file I/O
| ScrapState=0: scrap is on disk, open Clipboard File
SCRAP_OPEN_FILE:
        _Open                                   | open Clipboard File
        BEQ.B   SCRAP_RTS                       | success: return with D0=0
        CMPI    #-0x31,D0                       | dirNFErr (-49)?
        BEQ.B   SCRAP_RTS_OK                    | directory not found: return success
        CMPI    #-0x2B,D0                       | fnfErr (-43)? file not found
        BNE.B   SCRAP_RTS                       | other error: propagate error code
| Clipboard File does not exist - create it
        _Create                                 | create the file
        BNE.B   SCRAP_RTS                       | creation failed: return error
        _GetFileInfo                            | get file info to set type/creator
        MOVE.L  #0x434C4950,ioFlUsrWds(A0)      | fdType = 'CLIP'

        MOVE.L  #0x4D414353,ioFlUsrWds+4(A0)    | fdCreator = 'MACS'

        BSET    #0x4,ioFlUsrWds+8(A0)           | set bit 12 of fdFlags (Apple: system bit)
        _SetFileInfo                            | apply file type/creator/flags
        BNE.B   SCRAP_RTS                       | SetFileInfo failed: return error
        BRA.B   SCRAP_OPEN_FILE                 | retry Open now that file exists

| ----------------------------------------------------------
|
| _UnloadScrap ($A9FA) - FUNCTION UnloadScrap: LongInt
|
| Writes the in-memory scrap to the Clipboard File on disk, then
| disposes the memory handle. If scrap is already on disk or
| uninitialized, does nothing and returns noErr.
| Sets ScrapHandle=NIL and ScrapState=0 (on disk) after writing.
|
UnloadScrap:
        BSR.B   SCRAP_SETUP                     | set up: open Clipboard File, load globals
        BNE.B   SCRAP_EXIT                      | error opening file: return error
        TST     D6                              | check ScrapState
        BLE.B   SCRAP_NOERR                     | <= 0: already on disk or uninit, nothing to do
| ScrapState > 0: scrap is in memory, write it to disk
        BSR.B   SCRAP_OPEN_FILE                 | reopen Clipboard File (may have been closed)
        MOVE.L  D4,D0                           | D0 = ScrapSize (bytes to write)
        BSR.B   SCRAP_IOPARAM_HDL               | set up IOParam: buffer=*ScrapHandle, count=D0
        _Write                                  | write scrap data to Clipboard File
        BNE.B   SCRAP_EXIT                      | write error: return error code
        MOVE.L  D5,A0                           | A0 = ScrapHandle
        _DisposeHandle                          | free the in-memory scrap
        CLR.L   (A4)+                           | ScrapHandle = NIL
        CLR.L   (A4)+                           | ScrapCount|ScrapState = 0 (on disk)
SCRAP_NOERR:
        MOVEQ.L #0x0,D0                         | D0 = noErr
| ----------------------------------------------------------
| SCRAP_EXIT - common exit for Scrap Manager trap routines
|
| Stores D0 (result code) into stack frame result, restores
| registers, unlinks frame. D0 = byte count to strip from
| stack for parameters (0 for UnloadScrap/LodeScrap/ZeroScrap,
| 0xC for GetScrap, varies for PutScrap).
|
SCRAP_EXIT:
        EXT.L   D0                              | sign-extend result to long
        MOVE.L  D0,0x8(A6)                      | store result in stack frame return value
        MOVEQ.L #0x0,D0                         | D0 = 0 (no extra params to strip)
SCRAP_EXIT_STRIP:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore saved registers
        UNLK    A6                              | remove local frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    D0,SP                           | strip parameters (D0 bytes)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| SCRAP_RTS_OK - return noErr (scrap not on disk, or directory not found)
|
| Called during boot.
SCRAP_RTS_OK:
        MOVEQ.L #0x0,D0                         | D0 = noErr
SCRAP_RTS:
        RTS                                     | return to caller (D0 = result code)

| ----------------------------------------------------------
|
| _LoadScrap ($A9FB) - FUNCTION LoadScrap: LongInt
|
| Reads the Clipboard File from disk into a newly allocated
| memory handle. If scrap is already in memory (ScrapState > 0),
| does nothing. After loading, sets ScrapHandle and ScrapState=1.
|
| Called during boot.
LodeScrap:
        BSR     SCRAP_SETUP                     | set up: open Clipboard File, load globals
        BNE.B   SCRAP_EXIT                      | error: return error code
        TST     D6                              | check ScrapState
        BNE.B   SCRAP_NOERR                     | nonzero: scrap in memory or uninit, return noErr
| ScrapState=0: scrap is on disk, load it into memory
        MOVE.L  D4,D0                           | D0 = ScrapSize (bytes to allocate)
        _NewHandle                              | allocate handle for scrap data
        BNE.B   SCRAP_EXIT                      | allocation failed: return error
        MOVE.L  A0,(A4)+                        | store new handle in ScrapHandle
        ADDQ.L  #0x1,(A4)+                      | set ScrapState = 1 (in memory)
        MOVE.L  D4,D0                           | D0 = ScrapSize (bytes to read)
        BSR.B   SCRAP_IOPARAM_A0                | set up IOParam: buffer=*handle, count=D0
        _Read                                   | read scrap data from Clipboard File
        BRA.B   SCRAP_EXIT                      | return Read result code

| ----------------------------------------------------------
|
| SCRAP_IOPARAM_HDL - set up IOParam for Read/Write using ScrapHandle buffer
|
| SCRAP_IOPARAM_HDL entry: dereferences ScrapHandle (D5) for ioBuffer.
| SCRAP_IOPARAM_A0 entry: uses A0 already set as handle (dereferences it).
| Sets ioByteCount=D0, ioPosMode=fsFromStart, ioPosOffset=0.
|
SCRAP_IOPARAM_HDL:
        MOVE.L  D5,A0                           | A0 = ScrapHandle
| SCRAP_IOPARAM_A0 -- set up IOParam: buffer=*handle, count=D0.
SCRAP_IOPARAM_A0:
        MOVE.L  (A0),ioBuffer(A3)               | ioBuffer = *handle (scrap data)
        MOVE.L  D0,ioByteCount(A3)              | ioByteCount = requested byte count
        MOVE    #0x1,ioPosMode(A3)              | ioPosMode = fsFromStart (read/write from BOF)
        CLR.L   ioPosOffset(A3)                 | ioPosOffset = 0 (start of file)
        MOVE.L  A3,A0                           | A0 = IOParam block for trap call
        RTS                                     | return with IOParam block prepared in A0

| ----------------------------------------------------------
|
| _ZeroScrap ($A9FC) - FUNCTION ZeroScrap: LongInt
|
| Clears the scrap contents and reinitializes it for new data.
| Bumps ScrapCount (ensures it stays positive by negating if needed).
| If scrap is in memory: resizes handle to 0 bytes.
| If scrap is uninitialized: allocates a new empty handle.
| If scrap is on disk: truncates the Clipboard File to 0 bytes.
|
| Called during boot.
ZeroScrap:
        BSR     SCRAP_SETUP                     | set up: open file if on disk, load globals
        BNE.B   SCRAP_EXIT                      | error: return error code
        MOVE.L  D0,(ScrapSize).w                | ScrapSize = 0 (D0=0 from successful SCRAP_SETUP)
        ADDQ.W  #0x8,0x4(A4)                    | bump ScrapCount by 8
        BPL.B   ZERO_CHK_STATE                  | still positive: ok
        NEG     0x4(A4)                         | overflowed: negate to keep positive
ZERO_CHK_STATE:
        TST     D6                              | check ScrapState
        BEQ.B   ZERO_TRUNCATE                   | 0: scrap on disk, truncate file
        BGT.B   ZERO_RESIZE_HDL                 | > 0: in memory, resize existing handle
| ScrapState < 0: uninitialized, allocate new handle
        _NewHandle                              | D0=0: allocate 0-byte handle
        BRA.B   ZERO_STORE_HDL                  | store handle and set state

| ----------------------------------------------------------
|
| ZERO_RESIZE_HDL - resize existing scrap handle to 0 bytes
|
ZERO_RESIZE_HDL:
        MOVE.L  D5,A0                           | A0 = existing ScrapHandle
        _SetHandleSize                          | resize to D0=0 bytes (empty scrap)
ZERO_STORE_HDL:
        MOVE.L  A0,(A4)+                        | store handle in ScrapHandle, advance A4
        MOVE    (A4)+,(A4)                      | copy ScrapCount to ScrapState (makes state positive)
        BRA.B   SCRAP_EXIT                      | return result code

| ----------------------------------------------------------
|
| ZERO_TRUNCATE - scrap on disk: truncate Clipboard File to 0 bytes
|
ZERO_TRUNCATE:
        CLR.L   ioOwnBuf(A0)                    | ioMisc/logical EOF = 0
        _SetEOF                                 | truncate Clipboard File to empty
        BRA.B   SCRAP_EXIT                      | return result code

| ----------------------------------------------------------
|
| SCRAP_READ_DATA - read D0 bytes from scrap at offset D3 into buffer A1
|
| If scrap is in memory (D6 > 0): BlockMove from *ScrapHandle+D3.
| If scrap is on disk (D6 = 0): Read from Clipboard File at offset D3.
| D0 = byte count, D3 = offset into scrap, A1 = destination buffer.
|
SCRAP_READ_DATA:
        TST     D6                              | check ScrapState
        BEQ.B   SCRAP_READ_FILE                 | 0: scrap on disk, use file Read
| scrap in memory: copy via BlockMove
        MOVE.L  D5,A2                           | A2 = ScrapHandle
        MOVE.L  (A2),A0                         | A0 = *ScrapHandle (dereferenced ptr)
        ADDA.L  D3,A0                           | A0 = source ptr + offset into scrap
        _BlockMove                              | copy D0 bytes from (A0) to (A1)
        BRA.B   SCRAP_RTS_OK                    | return noErr

| ----------------------------------------------------------
|
| SCRAP_READ_FILE - read from Clipboard File at position D3
|
SCRAP_READ_FILE:
        BSR.B   SCRAP_IOPARAM_HDL               | set up IOParam from ScrapHandle (dummy)
        MOVE.L  D3,ioPosOffset(A0)              | override ioPosOffset = D3 (byte offset)
        MOVE.L  A1,ioBuffer(A0)                 | override ioBuffer = destination ptr A1
        _Read                                   | read D0 bytes from file at offset D3
        RTS                                     | propagate _Read result back to SCRAP_READ_DATA caller

| ----------------------------------------------------------
|
| _GetScrap ($A9FD) - FUNCTION GetScrap(hDest: Handle; theType: ResType;
| VAR offset: LongInt): LongInt
|
| Searches the scrap for data matching theType (e.g. 'TEXT', 'PICT').
| Scrap format: repeating [type(4) + length(4) + data(padded to even)].
| If hDest is NIL, just returns the data length and offset.
| If hDest is non-NIL, resizes handle and copies the data into it.
|
| Stack frame (A6-relative):
| 0x14(A6) = function result (long): data length or error code
| 0x10(A6) = hDest parameter (handle or NIL)
| 0x0C(A6) = theType parameter (4-byte type code)
| 0x08(A6) = VAR offset parameter (pointer to long)
|
GetScrap:
        BSR     SCRAP_SETUP                     | common setup: open file, load globals
        BNE.B   GETSCRAP_ERR                    | error opening: return error
        BSR     SCRAP_ENSURE_INIT               | ensure scrap is initialized
        BMI.B   GETSCRAP_ERR                    | initialization failed: return error
        MOVEQ.L #0x0,D3                         | D3 = current offset into scrap data
| scan through scrap entries looking for matching type
GETSCRAP_SCAN:
        CMP.L   D4,D3                           | offset >= ScrapSize?
        BGE.B   GETSCRAP_NOTYPE                 | past end: type not found
        MOVEQ.L #0x8,D0                         | read 8 bytes (type + length header)
        LEA.L   -0x58(A6),A1                    | A1 -> temp buffer in stack frame
        BSR.B   SCRAP_READ_DATA                 | read entry header from scrap at offset D3
        BNE.B   GETSCRAP_ERR                    | read error: return error
        ADDQ.L  #0x8,D3                         | advance past header (type + length)
        MOVE.L  (A1)+,D7                        | D7 = scrap entry type code
        CMP.L   0xC(A6),D7                      | matches requested theType?
        BEQ.B   GETSCRAP_FOUND                  | found matching type
| skip this entry: advance D3 by data length, rounded up to even
        ADD.L   (A1)+,D3                        | D3 += data length
        ADDQ.L  #0x1,D3                         | round up to even boundary
        BCLR    D0,D3                           | clear bit 0 (D0=0 after ADD, so clears bit 0)
        BRA.B   GETSCRAP_SCAN                   | continue scanning

| ----------------------------------------------------------
|
| GETSCRAP_NOTYPE - requested scrap type not found in scrap
|
GETSCRAP_NOTYPE:
        MOVEQ.L #-0x66,D0                       | noTypeErr (-102): scrap type not found
        BRA.B   GETSCRAP_SET_ERR                | store error as function result

| ----------------------------------------------------------
|
| GETSCRAP_FOUND - found matching type; D3 = offset to data, (A1) = data length
|
GETSCRAP_FOUND:
        MOVE.L  0x8(A6),A2                      | A2 -> VAR offset parameter
        MOVE.L  D3,(A2)                         | store byte offset of this entry's data
        MOVE.L  (A1),D0                         | D0 = data length for this entry
        MOVE.L  D0,0x14(A6)                     | store length as function result
        MOVE.L  0x10(A6),D1                     | D1 = hDest handle
        BEQ.B   GETSCRAP_DONE                   | hDest=NIL: just return length, skip copy
| hDest is non-NIL: resize handle and copy data into it
        MOVE.L  D1,A0                           | A0 = hDest handle
        _SetHandleSize                          | resize hDest to D0 bytes
        BNE.B   GETSCRAP_ERR                    | resize failed: return error
        MOVE.L  (A1),D0                         | D0 = data length (reload after trap)
        MOVE.L  (A0),A1                         | A1 = *hDest (dereferenced destination ptr)
        BSR.B   SCRAP_READ_DATA                 | copy D0 bytes from scrap at offset D3 to *hDest
        BEQ.B   GETSCRAP_DONE                   | success: return with data length
GETSCRAP_ERR:
        EXT.L   D0                              | sign-extend error code to long
GETSCRAP_SET_ERR:
        MOVE.L  D0,0x14(A6)                     | store error code as function result
GETSCRAP_DONE:
        MOVEQ.L #0xC,D0                         | 12 bytes of parameters to strip
        BRA     SCRAP_EXIT_STRIP                | common exit: strip params and return

| ----------------------------------------------------------
|
| SCRAP_ENSURE_INIT - ensure scrap is initialized before read/write
|
| If ScrapState < 0 (uninitialized), calls ZeroScrap to create
| an empty scrap, then reloads globals via SCRAP_LOAD_GLOBALS.
|
SCRAP_ENSURE_INIT:
        TST     D6                              | check ScrapState
        BGE.B   ENSUREINIT_RTS                  | >= 0: already initialized, return
| scrap uninitialized: create empty scrap
        SUBQ.W  #0x4,SP                         | allocate space for ZeroScrap result
        _ZeroScrap                              | initialize empty scrap
        MOVE.L  (SP)+,D0                        | pop result code
        BMI.B   GETSCRAP_ERR                    | error: return error code
        BSR     SCRAP_LOAD_GLOBALS              | reload scrap globals into registers
ENSUREINIT_RTS:
        RTS                                     | return with scrap guaranteed to be initialized

| ----------------------------------------------------------
|
| _PutScrap ($A9FE) - FUNCTION PutScrap(length: LongInt; theType: ResType;
| source: Ptr): LongInt
|
| Appends a new scrap entry to the current scrap. Writes the
| 8-byte header [theType + length] followed by the data bytes
| (padded to even length). Updates ScrapSize to reflect new total.
|
| Stack frame (A6-relative):
| 0x10(A6) = length parameter (long)
| 0x0C(A6) = theType parameter (4-byte type code)
| 0x08(A6) = source parameter (Ptr to data)
|
PutScrap:
        BSR     SCRAP_SETUP                     | common setup: open file, load globals
        BSR.B   SCRAP_ENSURE_INIT               | ensure scrap is initialized
        BMI.B   GETSCRAP_ERR                    | initialization error: return error
| set up IOParam for file positioning at end of current scrap
        BSR     SCRAP_IOPARAM_HDL               | set up IOParam with ScrapHandle buffer
| write the 8-byte entry header: [theType(4) + length(4)]
        MOVEQ.L #0x8,D0                         | 8 bytes for type + length header
        LEA.L   0xC(A6),A0                      | A0 -> theType on stack (type+length adjacent)
        BSR.B   SCRAP_APPEND                    | append 8 header bytes to scrap
| write the data bytes, padded to even length
        MOVE.L  0x8(A6),A0                      | A0 = source pointer
        MOVE.L  0x10(A6),D0                     | D0 = data length
        MOVEQ.L #-0x2,D1                        | D1 = 0xFFFFFFFE (mask to round up to even)
        ADDQ.L  #0x1,D0                         | D0 = length + 1
        AND.L   D1,D0                           | round up to even byte count
        BSR.B   SCRAP_APPEND                    | append data bytes to scrap
| update ScrapSize to new total
        MOVE.L  D4,-(A4)                        | store updated D4 (total size) into ScrapSize
        BRA.B   GETSCRAP_ERR                    | return via common exit

| ----------------------------------------------------------
|
| SCRAP_APPEND - append D0 bytes from A0 to the scrap at current offset D4
|
| If scrap is in memory: uses _PtrAndHand to append to ScrapHandle.
| If scrap is on disk: writes to Clipboard File at offset D4.
| Advances D4 (running ScrapSize) by D0 bytes.
|
SCRAP_APPEND:
        MOVE.L  D4,ioPosOffset(A3)              | ioPosOffset = current end of scrap (D4)
        ADD.L   D0,D4                           | advance running size by D0 bytes
        TST     D6                              | check ScrapState
        BEQ.B   SCRAP_WRITE_FILE                | 0: scrap on disk, use file Write
| scrap in memory: append bytes to handle
        MOVE.L  D5,A1                           | A1 = ScrapHandle (destination)
        _PtrAndHand                             | append D0 bytes from (A0) to handle (A1)
        RTS                                     | return to PutScrap with _PtrAndHand error code

| ----------------------------------------------------------
|
| SCRAP_WRITE_FILE - write to Clipboard File at offset D4 (scrap on disk)
|
SCRAP_WRITE_FILE:
        MOVE.L  A0,ioBuffer(A3)                 | ioBuffer = source pointer
        MOVE.L  D0,ioByteCount(A3)              | ioByteCount = byte count
        MOVE.L  A3,A0                           | A0 = IOParam block
        _Write                                  | write data to Clipboard File
        RTS                                     | return to PutScrap with _Write error code
