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

| ----------------------------------------------------------
| _InfoScrap ($A9F9) - return ScrapStuff record ptr.
| Pascal: function InfoScrap: PScrapStuff;
| Calls _ZeroScrap if scrap not yet initialized, then returns
| ptr to ScrapSize/Handle/State/Name lowmem block as a record.
| (MacSEROM.lst also lists TE68KEND, the end of the TextEdit
| module, at this offset.)
| ----------------------------------------------------------
| Apple source module: SCRAPMGR
INFOSCRAP:
    TST.W       (ScrapState).W                  | scrap initialized?
    BGE.B       INFOSCRAP_RETURN                | yes -> just return ptr
    SUBQ.W      #0x4,A7                         | room for ZeroScrap result
    _ZeroScrap                                  | initialize empty scrap
    ADDQ.W      #0x4,A7                         | discard result
INFOSCRAP_RETURN:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    LEA.L       (ScrapSize).W,A1                | A1 = ScrapStuff record
    MOVE.L      A1,(A7)                         | replace return slot with result
    JMP         (A0)                            | tail-call return from INFOSCRAP_RETURN via A0
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
    MOVEA.L     (A7)+,A1                        | A1 = saved return address
    LINK        A6,#-0x58                       | 0x58 bytes locals (incl IOParam)
    MOVEM.L     D2-D7/A2-A4,-(A7)               | save scratch registers
    MOVE.L      A1,-(A7)                        | restore return addr on stack
| SCRAP_LOAD_GLOBALS -- reload scrap globals into registers.
SCRAP_LOAD_GLOBALS:
    MOVEM.L     (ScrapSize),D4-D6/A2            | D4=ScrapSize, D5=Handle, D6.W=State, A2=Name
    LEA.L       (ScrapHandle).W,A4              | A4 -> ScrapHandle global
    LEA.L       -0x50(A6),A0                    | A0 = local IOParam block
    MOVEA.L     A0,A3                           | A3 = IOParam (kept across calls)
    MOVE.L      A2,0x12(A0)                     | ioFileName = ScrapName
    MOVE.W      (BootDrive).W,0x16(A0)          | ioVRefNum = BootDrive
    CLR.W       0x1A(A0)                        | ioVersNum = 0
    CLR.L       0x1C(A0)                        | ioPermssn/ioMisc = 0
    TST.W       D6                              | scrap in memory?
    BNE.B       SCRAP_RTS_OK                    | yes -> no file open needed
| ScrapState=0: scrap is on disk, open Clipboard File
SCRAP_OPEN_FILE:
    _Open                                       | open Clipboard File
    BEQ.B       SCRAP_RTS                       | success: return with D0=0
    CMPI.W      #0xFFCF,D0                      | dirNFErr (no scrap dir)?
    BEQ.B       SCRAP_RTS_OK                    | yes -> no scrap available
    CMPI.W      #0xFFD5,D0                      | fnfErr (no Clipboard File)?
    BNE.B       SCRAP_RTS                       | no -> return error
    _Create                                     | create Clipboard File
    BNE.B       SCRAP_RTS                       | failed -> return error
    _GetFileInfo                                | get file info into A0
    MOVE.L      #0x434C4950,0x20(A0)            | fileType = 'CLIP'
    MOVE.L      #0x4D414353,0x24(A0)            | fileCreator = 'MACS'
    BSET        #0x4,0x28(A0)                   | set Bundle bit (invisible)
    _SetFileInfo                                | apply Finder info
    BNE.B       SCRAP_RTS                       | failed -> return error
    BRA.B       SCRAP_OPEN_FILE                 | retry _Open
UNLOADSCRAP:
    BSR.B       SCRAP_SETUP                     | setup IOParam + load globals
    BNE.B       SCRAP_EXIT                      | error -> exit
    TST.W       D6                              | scrap on disk (state <= 0)?
    BLE.B       SCRAP_NOERR                     | yes -> nothing to do
    BSR.B       SCRAP_OPEN_FILE                 | open Clipboard File
    MOVE.L      D4,D0                           | D0 = ScrapSize
    BSR.B       SCRAP_IOPARAM_HDL               | set IOParam from ScrapHandle
    _Write                                      | flush scrap to disk
    BNE.B       SCRAP_EXIT                      | error -> exit
    MOVEA.L     D5,A0                           | A0 = ScrapHandle
    _DisposeHandle                              | free in-memory copy
    CLR.L       (A4)+                           | ScrapHandle = nil
    CLR.L       (A4)+                           | ScrapState/Name = 0
SCRAP_NOERR:
    MOVEQ.L     #0x0,D0                         | success
| ----------------------------------------------------------
| SCRAP_EXIT - common exit for Scrap Manager trap routines
|
| Stores D0 (result code) into stack frame result, restores
| registers, unlinks frame. D0 = byte count to strip from
| stack for parameters (0 for UnloadScrap/LoadScrap/ZeroScrap,
| 0xC for GetScrap, varies for PutScrap).
|
| Called by: LOADSCRAP, UNLOADSCRAP, ZEROSCRAP, ZERO_STORE_HDL, ZERO_TRUNCATE
SCRAP_EXIT:
    EXT.L       D0                              | sign-extend error code
    MOVE.L      D0,0x8(A6)                      | store result in stack-frame slot
    MOVEQ.L     #0x0,D0                         | strip 0 bytes (no params)
SCRAP_EXIT_STRIP:
    MOVEM.L     (A7)+,D2-D7/A2-A4               | restore registers
    UNLK        A6                              | tear down frame
    MOVEA.L     (A7)+,A0                        | A0 = return address
    ADDA.W      D0,A7                           | strip params from stack
    JMP         (A0)                            | tail-call return from SCRAP_EXIT_STRIP via A0
| ----------------------------------------------------------
|
| SCRAP_RTS_OK - return noErr (scrap not on disk, or directory not found)
|
| Called during boot.
SCRAP_RTS_OK:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (success)
SCRAP_RTS:
    RTS                                         | return from SCRAP_RTS
LOADSCRAP:
    BSR.W       SCRAP_SETUP                     | setup IOParam + load globals
    BNE.B       SCRAP_EXIT                      | error -> exit
    TST.W       D6                              | scrap already in memory?
    BNE.B       SCRAP_NOERR                     | yes -> done
    MOVE.L      D4,D0                           | D0 = ScrapSize
    _NewHandle                                  | allocate ScrapHandle
    BNE.B       SCRAP_EXIT                      | failed -> exit
    MOVE.L      A0,(A4)+                        | ScrapHandle = new handle
    ADDQ.L      #0x1,(A4)+                      | ScrapState = +1 (in memory)
    MOVE.L      D4,D0                           | D0 = bytes to read
    BSR.B       SCRAP_IOPARAM_A0                | set IOParam (buffer = *A0)
    _Read                                       | load file into ScrapHandle
    BRA.B       SCRAP_EXIT                      | -> exit
| ----------------------------------------------------------
|
| SCRAP_IOPARAM_HDL - set up IOParam for Read/Write using ScrapHandle buffer
|
| SCRAP_IOPARAM_HDL entry: dereferences ScrapHandle (D5) for ioBuffer.
| SCRAP_IOPARAM_A0 entry: uses A0 already set as handle (dereferences it).
| Sets ioByteCount=D0, ioPosMode=fsFromStart, ioPosOffset=0.
|
SCRAP_IOPARAM_HDL:
    MOVEA.L     D5,A0                           | A0 = ScrapHandle
| SCRAP_IOPARAM_A0 -- set up IOParam: buffer=*handle, count=D0.
SCRAP_IOPARAM_A0:
    MOVE.L      (A0),0x20(A3)                   | ioBuffer = *A0
    MOVE.L      D0,0x24(A3)                     | ioByteCount = D0
    MOVE.W      #0x1,0x2C(A3)                   | ioPosMode = fsFromStart
    CLR.L       0x2E(A3)                        | ioPosOffset = 0
    MOVEA.L     A3,A0                           | A0 = IOParam ptr
    RTS                                         | return from SCRAP_IOPARAM_A0
ZEROSCRAP:
    BSR.W       SCRAP_SETUP                     | setup IOParam + load globals
    BNE.B       SCRAP_EXIT                      | error -> exit
    MOVE.L      D0,(ScrapSize).W                | ScrapSize = 0
    ADDQ.W      #0x8,0x4(A4)                    | bump ScrapCount (skip flag bit)
    BPL.B       ZERO_CHK_STATE                  | overflow? -> normal
    NEG.W       0x4(A4)                         | wrap to positive
ZERO_CHK_STATE:
    TST.W       D6                              | scrap state?
    BEQ.B       ZERO_TRUNCATE                   | on disk -> truncate file
    BGT.B       ZERO_RESIZE_HDL                 | in memory -> resize handle
    _NewHandle                                  | uninitialized -> create empty
    BRA.B       ZERO_STORE_HDL                  | -> store new handle
| ----------------------------------------------------------
|
| ZERO_RESIZE_HDL - resize existing scrap handle to 0 bytes
|
ZERO_RESIZE_HDL:
    MOVEA.L     D5,A0                           | A0 = existing ScrapHandle
    _SetHandleSize                              | resize to 0 bytes (D0=0)
ZERO_STORE_HDL:
    MOVE.L      A0,(A4)+                        | ScrapHandle = handle
    MOVE.W      (A4)+,(A4)                      | clear ScrapState (= 0)
    BRA.B       SCRAP_EXIT                      | -> exit
| ----------------------------------------------------------
|
| ZERO_TRUNCATE - scrap on disk: truncate Clipboard File to 0 bytes
|
ZERO_TRUNCATE:
    CLR.L       0x1C(A0)                        | ioMisc = 0 (new EOF)
    _SetEOF                                     | truncate Clipboard File
    BRA.B       SCRAP_EXIT                      | -> exit
| ----------------------------------------------------------
|
| SCRAP_READ_DATA - read D0 bytes from scrap at offset D3 into buffer A1
|
| If scrap is in memory (D6 > 0): BlockMove from *ScrapHandle+D3.
| If scrap is on disk (D6 = 0): Read from Clipboard File at offset D3.
| D0 = byte count, D3 = offset into scrap, A1 = destination buffer.
|
SCRAP_READ_DATA:
    TST.W       D6                              | scrap in memory?
    BEQ.B       SCRAP_READ_FILE                 | no -> read from disk
    MOVEA.L     D5,A2                           | A2 = ScrapHandle
    MOVEA.L     (A2),A0                         | A0 = scrap data
    ADDA.L      D3,A0                           | A0 = scrap data + offset
    _BlockMove                                  | copy D0 bytes to (A1)
    BRA.B       SCRAP_RTS_OK                    | success
| ----------------------------------------------------------
|
| SCRAP_READ_FILE - read from Clipboard File at position D3
|
SCRAP_READ_FILE:
    BSR.B       SCRAP_IOPARAM_HDL               | set up IOParam (sets ioByteCount=D0)
    MOVE.L      D3,0x2E(A0)                     | ioPosOffset = D3
    MOVE.L      A1,0x20(A0)                     | ioBuffer = A1 (caller's buf)
    _Read                                       | read from Clipboard File
    RTS                                         | return from SCRAP_READ_FILE
GETSCRAP:
    BSR.W       SCRAP_SETUP                     | setup IOParam + load globals
    BNE.B       GETSCRAP_ERR                    | error -> exit
    BSR.W       SCRAP_ENSURE_INIT               | initialize scrap if needed
    BMI.B       GETSCRAP_ERR                    | failed -> exit
    MOVEQ.L     #0x0,D3                         | D3 = scan offset
| scan through scrap entries looking for matching type
GETSCRAP_SCAN:
    CMP.L       D4,D3                           | reached end of scrap?
    BGE.B       GETSCRAP_NOTYPE                 | yes -> type not found
    MOVEQ.L     #0x8,D0                         | D0 = 8 bytes (type + len)
    LEA.L       -0x58(A6),A1                    | A1 = local 8-byte buffer
    BSR.B       SCRAP_READ_DATA                 | read scrap entry header
    BNE.B       GETSCRAP_ERR                    | error -> exit
    ADDQ.L      #0x8,D3                         | advance past header
    MOVE.L      (A1)+,D7                        | D7 = entry's type code
    CMP.L       0xC(A6),D7                      | matches requested type?
    BEQ.B       GETSCRAP_FOUND                  | yes -> return data
    ADD.L       (A1)+,D3                        | D3 += entry length
    ADDQ.L      #0x1,D3                         | + 1 (for word alignment)
    BCLR        D0,D3                           | clear bit 0 (round to even)
    BRA.B       GETSCRAP_SCAN                   | scan next entry
| ----------------------------------------------------------
|
| GETSCRAP_NOTYPE - requested scrap type not found in scrap
|
GETSCRAP_NOTYPE:
    MOVEQ.L     #-0x66,D0                       | D0 = noTypeErr (-102)
    BRA.B       GETSCRAP_SET_ERR                | -> store error
| ----------------------------------------------------------
|
| GETSCRAP_FOUND - found matching type; D3 = offset to data, (A1) = data length
|
GETSCRAP_FOUND:
    MOVEA.L     0x8(A6),A2                      | A2 = offset out param ptr
    MOVE.L      D3,(A2)                         | *offsetPtr = data offset
    MOVE.L      (A1),D0                         | D0 = data length
    MOVE.L      D0,0x14(A6)                     | result = data length
    MOVE.L      0x10(A6),D1                     | D1 = dest handle param
    BEQ.B       GETSCRAP_DONE                   | nil -> just return length
    MOVEA.L     D1,A0                           | A0 = dest handle
    _SetHandleSize                              | resize to fit data
    BNE.B       GETSCRAP_ERR                    | failed -> exit
    MOVE.L      (A1),D0                         | D0 = data length
    MOVEA.L     (A0),A1                         | A1 = dest buffer
    BSR.B       SCRAP_READ_DATA                 | copy data to dest
    BEQ.B       GETSCRAP_DONE                   | success -> exit
| Called by: GETSCRAP, PUTSCRAP, GETSCRAP_SCAN, GETSCRAP_FOUND, SCRAP_ENSURE_INIT
GETSCRAP_ERR:
    EXT.L       D0                              | sign-extend error code
GETSCRAP_SET_ERR:
    MOVE.L      D0,0x14(A6)                     | store result
GETSCRAP_DONE:
    MOVEQ.L     #0xC,D0                         | param size = 12 bytes
    BRA.W       SCRAP_EXIT_STRIP                | -> strip & exit
| ----------------------------------------------------------
|
| SCRAP_ENSURE_INIT - ensure scrap is initialized before read/write
|
| If ScrapState < 0 (uninitialized), calls ZeroScrap to create
| an empty scrap, then reloads globals via SCRAP_LOAD_GLOBALS.
|
SCRAP_ENSURE_INIT:
    TST.W       D6                              | scrap initialized?
    BGE.B       ENSUREINIT_RTS                  | yes -> done
    SUBQ.W      #0x4,A7                         | room for _ZeroScrap result
    _ZeroScrap                                  | initialize scrap to empty
    MOVE.L      (A7)+,D0                        | D0 = result code
    BMI.B       GETSCRAP_ERR                    | failed -> exit
    BSR.W       SCRAP_LOAD_GLOBALS              | reload (zeroed) globals
ENSUREINIT_RTS:
    RTS                                         | return from SCRAP_ENSURE_INIT
PUTSCRAP:
    BSR.W       SCRAP_SETUP                     | setup IOParam + load globals
    BSR.B       SCRAP_ENSURE_INIT               | initialize if needed
    BMI.B       GETSCRAP_ERR                    | failed -> exit
    BSR.W       SCRAP_IOPARAM_HDL               | set up IOParam
    MOVEQ.L     #0x8,D0                         | 8 bytes (type + length)
    LEA.L       0xC(A6),A0                      | A0 = type/length param
    BSR.B       SCRAP_APPEND                    | append entry header
    MOVEA.L     0x8(A6),A0                      | A0 = source data ptr
    MOVE.L      0x10(A6),D0                     | D0 = data length
    MOVEQ.L     #-0x2,D1                        | D1 = ~1 (mask)
    ADDQ.L      #0x1,D0                         | D0 += 1 (round up)
    AND.L       D1,D0                           | round to even (word align)
    BSR.B       SCRAP_APPEND                    | append data bytes
    MOVE.L      D4,-(A4)                        | ScrapSize = new total size
    BRA.B       GETSCRAP_ERR                    | -> store result code
| ----------------------------------------------------------
|
| SCRAP_APPEND - append D0 bytes from A0 to the scrap at current offset D4
|
| If scrap is in memory: uses _PtrAndHand to append to ScrapHandle.
| If scrap is on disk: writes to Clipboard File at offset D4.
| Advances D4 (running ScrapSize) by D0 bytes.
|
SCRAP_APPEND:
    MOVE.L      D4,0x2E(A3)                     | ioPosOffset = current ScrapSize
    ADD.L       D0,D4                           | advance running ScrapSize
    TST.W       D6                              | scrap in memory?
    BEQ.B       SCRAP_WRITE_FILE                | no -> write to disk
    MOVEA.L     D5,A1                           | A1 = ScrapHandle
    _PtrAndHand                                 | append D0 bytes from A0 to A1
    RTS                                         | return from SCRAP_APPEND
SCRAP_WRITE_FILE:
    MOVE.L      A0,0x20(A3)                     | ioBuffer = source ptr
    MOVE.L      D0,0x24(A3)                     | ioByteCount = D0
    MOVEA.L     A3,A0                           | A0 = IOParam
    _Write                                      | append data to Clipboard File
    RTS                                         | return from SCRAP_APPEND
