| File Manager -- calls on open files (refnum-based)
|
| GetFPos, SetFPos, the File Manager side of _Read/_Write (FileRead,
| FileWrite: positioning, the volume buffer, the file's allocation blocks
| through the block map), FlushFile, Close, GetEOF, SetEOF, Allocate and
| Lg2Phys (file position -> disk block). The corresponding Mac Plus code is
| in Apple's TFSRfN/MFSRfN files (Plus tree: os/file_mgr_io.s).
|
| FileParam - File information parameter block (MPW 1.0 Files.h):
| Offset 0-22: same as IOParam header (qLink..ioVRefNum)
| Offset 24: ioFRefNum INTEGER file reference number
| Offset 26: ioFVersNum BYTE file version number
| Offset 28: ioFDirIndex INTEGER directory index
| Offset 30: ioFlAttrib BYTE file attributes
| Offset 31: ioFlVersNum BYTE file version number
| Offset 32: ioFlFndrInfo FInfo Finder info (16 bytes)
| Offset 48: ioFlNum LongInt file number
| Offset 52: ioFlStBlk INTEGER first alloc block of data fork
| Offset 54: ioFlLgLen LongInt logical length of data fork
| Offset 58: ioFlPyLen LongInt physical length of data fork
| Offset 62: ioFlRStBlk INTEGER first alloc block of resource fork
| Offset 64: ioFlRLgLen LongInt logical length of resource fork
| Offset 68: ioFlRPyLen LongInt physical length of resource fork
| Offset 72: ioFlCrDat LongInt creation date
| Offset 76: ioFlMdDat LongInt modification date
|
| FInfo - Finder information (16 bytes, MPW 1.0 Files.h):
| Offset 0: fdType OSType file type (e.g. 'TEXT', 'APPL')
| Offset 4: fdCreator OSType creator application
| Offset 8: fdFlags INTEGER Finder flags
| Offset 10: fdLocation Point position in folder window
| Offset 14: fdFldr INTEGER folder containing file

| GetFPos -- _GetFPos ($A018): FUNCTION GetFPos (refNum: INTEGER; VAR filePos: LONGINT) OSErr;
| SetFPos -- _SetFPos ($A044): FUNCTION SetFPos (refNum: INTEGER; posMode: INTEGER; posOff: LONGINT) OSErr;
| GetFPos clears ioPosMode (fsAtMark) and ioReqCount, then falls into
| L_mFileRead which positions and reads zero bytes (returning the mark
| in IOPosOffset). SetFPos uses caller's ioPosMode but clears
| ioReqCount, so it falls into L_mFileRead from one instruction later.
GetFPos:
        CLR.B   (ioPosMode+1)(A0)               | ioPosMode low byte = 0 (fsAtMark)
SetFPos:
        CLR.L   ioReqCount(A0)                  | ioReqCount = 0

| FileRead (vFileRead)
L_mFileRead:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.W   RFNCall                         | resolve refNum -> A1, D1
        BNE.W   L_MFILEREAD_EXIT_3              | bad refNum -> exit
        BSR.B   SEEK                            | set FCB mark to ioPosOffset
        BNE.W   L_MFILEREAD_EXIT_2              | seek error -> exit
        NEG.L   D2                              | D2 = bytes-to-EOF (positive if at EOF)
        BMI.W   L_MFILEREAD_CONT_2              | past EOF -> 0 bytes path
        CMP.L   D2,D7                           | ioReqCount > bytes-to-EOF?
        BLE.B   L_MFILEREAD_CONT                | no -> use ioReqCount
        MOVE.L  D2,D7                           | yes -> clamp to bytes-to-EOF
L_MFILEREAD_CONT:
        TST.L   D7                              | any bytes to read?
        BEQ.B   L_MFILEREAD_DONE                | zero -> done (just position)
        MOVE    ioPosMode(A0),D2                | D2 = ioPosMode word
        LSR.W    #0x8,D2                        | shift newline-mode flag into bit 0
        BCS.W    L_MFILEREAD_CONT_3             | newline mode -> byte-scan path
        MOVE    D5,D2                           | current file position (low word)
        ANDI    #0x1FF,D2                       | check lower 9 bits for blk bndry read
        BEQ.B   RDPART_CONT                     | br if so (can read into place)

| RdPart: must read a partial block first
RDPART:
        BSR.W   HFSE_RDFILEBLK                  | RdFileBlk: read the data block
        BNE.B   L_MFILEREAD_EXIT                | block-read err -> exit
        BTST    #0x6,(ioPosMode+1)(A0)          | read verify only?
        SNE     D0                              | D0 = -1 if verify-only
        BSR.W   DOPART                          | DoPart: copy partial block to user buffer
        BNE.B   L_MFILEREAD_EXIT                | copy err -> exit
RDPART_CONT:
        MOVE.L  D7,D4                           | D4 = bytes still to read
        BEQ.B   L_MFILEREAD_DONE                | zero -> done
        CMPI.L  #0x200,D4                       | less than one block?
        BCS.B   RDPART                          | yes -> partial block path
        ANDI    #-0x200,D4                      | round D4 down to whole blocks
        BSR.W   LG2PHYS_NO                      | map logical -> physical block
        MOVE    D3,D4                           | user buffer (IOBuffer)
        BSR.W   FS_CUR_BUF_BLOCK                | compute extent contig blocks
        BPL.B   RDPART_CONT_2                   | contiguous -> bulk read
        CMP     D4,D3                           | contiguous count > requested?
        BCS.B   RDPART_CONT_2                   | yes -> use it
        CMP     D0,D3                           | below physical extent end?
        BCC.B   RDPART_CONT_2                   | no -> use partial bulk
        MOVE.L  D6,(FSTemp4).w                  | stash D6 across split read
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_4     | issue extent-bounded read
        BNE.B   L_MFILEREAD_EXIT                | err -> exit
        MOVE.L  (FSTemp4).w,D6                  | restore D6
RDPART_CONT_2:
        MOVE    D4,D3                           | D3 = blocks for this read
        MOVE.L  ioBuffer(A0),A5                 | A5 = user buffer base
        ADDA.L  ioActCount(A0),A5               | A5 += bytes already transferred
        BSR.W   FILEOPEN_CONT_6_CONT_CONT       | issue read into user buffer
        BNE.B   L_MFILEREAD_EXIT                | err -> exit
        BSR.W   FILEWRITE_CONT_2                | advance D5/D7/ioActCount
        BRA.B   RDPART_CONT                     | loop until D7 = 0

| L_MFILEREAD_DONE - wait for one VBL tick, then loop back to smooth and refill
L_MFILEREAD_DONE:
        MOVEQ.L #0x0,D0                         | return noErr
L_MFILEREAD_EXIT:
        TST     D0                              | other error?
        BNE.B   L_MFILEREAD_EXIT_2              | br if so
        MOVE.L  ioActCount(A0),D2               | if actual count != requested count
        CMP.L   ioReqCount(A0),D2               | (IOActCount vs IOReqCount)
        BEQ.B   L_MFILEREAD_EXIT_2              | (br if equal, no EOF)
L_MFILEREAD_CONT_2:
        MOVEQ.L #-0x27,D0                       | D0 = eofErr (-39)
L_MFILEREAD_EXIT_2:
        MOVE.L  D5,fcbCrPs(A1,D1.W)             | store cumulative byte offset into param
        MOVE.L  D5,ioPosOffset(A0)              | return new file position
L_MFILEREAD_EXIT_3:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done
L_MFILEREAD_CONT_3:
        BSR.W   HFSE_RDFILEBLK                  | read one file data block
        BNE.B   L_MFILEREAD_EXIT                | block-read err -> exit
        MOVE.L  D5,D2                           | D2 = current position
        ANDI    #0x1FF,D2                       | D2 = offset within block
        MOVE.L  ioBuffer(A0),A3                 | A3 = user buffer base
        MOVE.L  ioActCount(A0),D4               | D4 = bytes already transferred

| newline byte-by-byte scan loop
L_MFILEREAD_LOOP:
        MOVE.B  0(A5,D2.W),D0                   | get byte from the buffer
        MOVE.B  D0,0(A3,D4.L)                   | put it into user's area
        ADDQ.L  #0x1,ioActCount(A0)             | actually read another byte (IOActCount)
        ADDQ.L  #0x1,D4                         | incr destination byte offset
        ADDQ.W  #0x1,D2                         | incr source byte offset
        ADDQ.L  #0x1,D5                         | incr current position
        CMP.B   ioPosMode(A0),D0                | is it the EOL character?
        BNE.B   L_MFILEREAD_NO_2                | no ->
        MOVEQ.L #0x0,D0                         | no error, we found EOL
        BRA.B   L_MFILEREAD_EXIT_2              | newline found -> success exit
L_MFILEREAD_NO_2:
        SUBQ.L  #0x1,D7                         | decr byte count
        BEQ.B   L_MFILEREAD_DONE                | count exhausted -> done
        CMP     D6,D2                           | reached end of buffer?
        BCS.B   L_MFILEREAD_LOOP                | loop if not
        BRA.B   L_MFILEREAD_CONT_3              | need next block from disk
| ----------------------------------------------------------
| L_MFILEREAD_LOOP_NO_CONT -- pick buffer ptr for FCB I/O.
| Push FCB.fcbExtBuf; if non-nil use it, else use VCB default
| buffer. On exit A5 = chosen buffer, (SP) unchanged above.
| ----------------------------------------------------------
L_MFILEREAD_LOOP_NO_CONT:
        MOVE.L  fcbBfAdr(A1,D1.W),-(SP)         | push FCB.fcbExtBuf
        BNE.B   HFSE_GETBUF_A5_RET              | non-nil -> use FCB buffer
        MOVE.L  vcbBufAdr(A2),(SP)              | nil -> use VCB default buffer
HFSE_GETBUF_A5_RET:
        MOVEA.L (SP)+,A5                        | A5 = chosen buffer ptr
        RTS                                     | return from buffer-pick helper

| ----------------------------------------------------------
| HFSE_RDFILEBLK -- read one file data block.
| Called from RDPART ($44C8) via BSR.W to this address.
| Uses FCB extent buffer (via the helper above), then falls into
| the common block-read tail at HFSE_RDFILEBLK_CONT.
| ----------------------------------------------------------
HFSE_RDFILEBLK:
        MOVEQ.L #0x1,D4                         | D4 = 1 (read one block)
        BSR.W   LG2PHYS_NO                      | map logical -> physical block
        BSR.B   L_MFILEREAD_LOOP_NO_CONT        | A5 = FCB extent buffer
        BRA.B   HFSE_RDFILEBLK_CONT             | -> common block-read tail
HFSE_READ_VBM_BLOCK:                            | entry from HFSE_NO/HFSE_OK
        MOVEA.L vcbBufAdr(A2),A5                | A5 = VCB default buffer
HFSE_RDFILEBLK_CONT:
        MOVEQ.L #0x2,D6                         | D6 = 2 (block-size shift base)
        ASL.L   #0x8,D6                         | D6 = 0x200 (512-byte block size)
        MOVEA.L (SP)+,A6                        | A6 = requested block number
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | do block read @ $4624

        BSR.W   SRCHNODE_GT_CONT_CONT_2         | D0 = current block tag
        CMP     D0,D3                           | block tag matches request?
        BNE.B   L_MFILEREAD_LOOP_NO_CONT_5      | no -> need real I/O
        MOVEQ.L #0x0,D0                         | buffer hit -> noErr
L_MFILEREAD_LOOP_NO_CONT_2:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | set up Disk Mgr param block
L_MFILEREAD_LOOP_NO_CONT_3:
        TST     D0                              | any error?
        BEQ.B   L_MFILEREAD_LOOP_NO_CONT_4      | no -> return success
        MOVEQ.L #-0x24,D0                       | D0 = ioErr (-36)
L_MFILEREAD_LOOP_NO_CONT_4:
        JMP     (A6)                            | return via saved A6 PC
L_MFILEREAD_LOOP_NO_CONT_5:
        BCLR    #0x7,-2(A5)                     | buffer dirty? (clear dirty bit)
        BEQ.B   L_MFILEREAD_LOOP_NO_CONT_7      | clean -> just read in
        MOVE    D0,D3                           | D3 = saved tag for reuse
        LEA     L_MFILEREAD_LOOP_NO_CONT_6(PC),A1 | A1 = "after-flush" PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | build write param block
        MOVEM.L -10(A5),D0-D1                   | D0/D1 = stored block tag
        MOVEM.L D0-D1,(BufTgFNum).w             | stamp BufTgFNum/BufTgFFlg
        _WriteAsync                             | flush buffer to disk
        RTS                                     | return from flush request
L_MFILEREAD_LOOP_NO_CONT_6:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | post-flush continuation
        BNE.B   L_MFILEREAD_LOOP_NO_CONT_3      | flush err -> propagate
L_MFILEREAD_LOOP_NO_CONT_7:
        LEA.L     (Params).w,A0                 | A0 = global Params block
        LEA     FILEOPEN_CONT_6(PC),A1          | A1 = "after-read" PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | build read param block
        _ReadAsync                              | issue async read
        RTS                                     | return from read request
FILEOPEN_CONT_6:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | post-read continuation
        BEQ.B   FILEOPEN_CONT_6_CONT            | ok -> save tag from buffer
        MOVEQ.L #0x0,D3                         | err -> mark buffer empty
FILEOPEN_CONT_6_CONT:
        MOVE    D3,-2(A5)                       | buffer header := tag (clean)
        MOVE.L  (BufTgFNum).w,-10(A5)           | stash file number in buffer
        MOVE.L  (BufTgFFlg).w,-6(A5)            | stash file flags in buffer
        BRA.B   L_MFILEREAD_LOOP_NO_CONT_3      | join error-test path
FILEOPEN_CONT_6_CONT_CONT:
        MOVE.L  (SP)+,A6                        | A6 = saved return PC
        MOVE.B  (ioPosMode+1)(A0),D0            | D0 = ioPosMode low byte
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | set up D2/D3/A1 for I/O
        LSL.B   #0x1,D0                         | shift verify-flag into N
        BPL.B   FILEOPEN_CONT_6_CONT_CONT_2     | not verify -> normal read
        BSET    #0x6,(ioPosMode+1)(A0)          | flag verify-only mode
FILEOPEN_CONT_6_CONT_CONT_2:
        LEA     L_MFILEREAD_LOOP_NO_CONT_2(PC),A1 | A1 = "after-read" PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | build read param block
        _ReadAsync                              | issue async read
        RTS                                     | return from FILEOPEN_CONT_6_CONT_CONT_2
FILEOPEN_CONT_6_CONT_CONT_2_CONT:
        MOVEM.L (HFSVars_HFSStkTop).w,D1-A6     | restore registers from HFSStkTop
        RTS                                     | return from FILEOPEN_CONT_6_CONT_CONT_2_CONT
FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT:
        MOVEM.L D1-A6,(HFSVars_HFSStkTop).w     | stash registers to HFSStkTop
        LEA.L     (Params).w,A0                 | A0 = global Params block
        MOVE    vcbDRefNum(A2),ioRefNum(A0)     | ioRefNum = vcb driver refNum
        MOVE.L  A5,ioBuffer(A0)                 | ioBuffer = cache block
        MOVE.L  D6,ioReqCount(A0)               | ioReqCount = transfer size
        MOVE    #0x1,ioPosMode(A0)              | ioPosMode = fsFromStart
        RTS                                     | return; param block ready
FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2:
        MOVE.L  A1,ioCompletion(A0)             | ioCompletion = completion routine
        MOVEQ.L #0x0,D6                         | D6 = 0 (clear high bytes)
        MOVE    D3,D6                           | D6 = block number (low word)
        ASL.L   #0x1,D6                         | D6 = block * 2
        ASL.L   #0x8,D6                         | D6 = block * 512 = byte offset
        MOVE.L  D6,ioPosOffset(A0)              | ioPosOffset := byte offset
        MOVE    vcbDrvNum(A2),ioVRefNum(A0)     | ioVRefNum := drive number
        RTS                                     | return; pb fully set
FILEOPEN_CONT_6_CONT_CONT_3:
        MOVE.L  vcbBufAdr(A2),A5                | A5 = volume default buffer
FILEOPEN_CONT_6_CONT_CONT_4:
        MOVEQ.L #0x2,D6                         | D6 = 2 (block-size shift base)
        ASL.L   #0x8,D6                         | D6 = 0x200 (one block)
        MOVE.L  (SP)+,A6                        | A6 = saved return PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | set up Disk Mgr param block
        MOVEM.L -10(A5),D0-D1                   | D0/D1 = stored block tag
        MOVEM.L D0-D1,(BufTgFNum).w             | stamp BufTgFNum/BufTgFFlg
        LEA     FILE_WRITE_TAG_PROC(PC),A1      | A1 = "after-write" PC
FILEOPEN_CONT_6_CONT_CONT_5:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | finish param block
        _WriteAsync                             | flush block to disk
        RTS                                     | return from write request

| ----------------------------------------------------------
| FILE_WRITE_TAG_PROC -- async write completion / tag proc
| Used as a code-pointer hook by FILEOPEN_CONT_6_CONT_CONT_4 (line
| ~800) which loads its address into A1 before calling _WriteAsync.
FILE_WRITE_TAG_PROC:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | restore caller's registers
        MOVE    D3,-2(A5)                       | stamp tag word into buffer
        BRA.W   L_MFILEREAD_LOOP_NO_CONT_3      | join error-test path
PreRdFileBlk:                                   | prep cache tags + read block
        MOVE.L  (SP)+,A6                        | A6 = saved return PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | set up Disk Mgr param block
        MOVE.L  fcbFlNm(A1,D1.W),(BufTgFNum).w  | BufTgFNum := FCB file number
        MOVE    fcbFlags(A1,D1.W),(BufTgFFlg).w | BufTgFFlg := FCB flags
        MOVE.L  D5,D0                           | D0 = current byte position
        LSR.L   #0x8,D0                         | / 256
        LSR.L   #0x1,D0                         | / 2 = block number within file
        MOVE    D0,(BufTgFBkNum).w              | BufTgFBkNum := block number
        BSR.W   L_MFILEREAD_LOOP_NO_CONT        | A5 = chosen buffer
        BSR.W   SRCHNODE_GT_CONT_CONT_2         | D0 = current buffer tag
        CMP     D3,D0                           | matches request?
        BCS.B   FILEREAD_ISSUE                  | below request -> reuse buffer
        LSR.L   #0x8,D6                         | D6 = read length / 256
        LSR.L   #0x1,D6                         | D6 = blocks in this read
        ADD     D3,D6                           | D6 = end-block of this read
        CMP     D6,D0                           | buffer tag past read end?
        BCC.B   FILEREAD_ISSUE                  | yes -> reuse buffer
        CLR     -2(A5)                          | invalidate buffer (mismatch)
FILEREAD_ISSUE:
        LEA     L_MFILEREAD_LOOP_NO_CONT_2(PC),A1 | A1 = "after-read" PC
        BRA.B   FILEOPEN_CONT_6_CONT_CONT_5     | issue async read

| ----------------------------------------------------------
| FileWrite -- _Write ($A003) for file paths.
| Pascal: function FileWrite(refNum: INTEGER; buffPtr: Ptr;
| count: LongInt; mode: INTEGER): OSErr;
| Writes data from a buffer to an open file. Device Manager's
| Write trap entry in device_mgr.s forwards here (JMP FileWrite(PC)
| at device_mgr.s:376) when the refnum is a positive file refNum
| rather than a negative driver refNum. Sequence: FSQUEUE_SETUP,
| TstMod (modification check), Seek (position file), then either
| same-length or extend-and-write paths.
FileWrite:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.W   TstMod                          | TstMod: caller is allowed to modify?
        BNE.W   FILEWRITE_NO_3                  | denied -> error
        BSR.W   SEEK                            | Seek: position and set up D5, D7
        BNE.B   FILEWRITE_CONT                  | error positioning ->
        TST.L   D2                              | positioned past EOF?
        BMI.B   FILEWRITE_NO                    | yes ->
        ADD.L   D2,D5                           | extend added to current position
FILEWRITE_NO:
        MOVE.L  D5,D4                           | D4 = file position
        ADD.L   D7,D4                           | D4 = end-of-write position
        CMP.L   fcbEOF(A1,D1.W),D4              | past current logical EOF?
        BLS.B   SAMELEN                         | no -> overwrite path
        SUB.L   fcbPLen(A1,D1.W),D4             | D4 -= fcbPLen(A1,D1.W)
        BLS.B   FILEWRITE_NO_2                  | fits in physical -> just bump EOF
        BSR.W   LG2PHYS_NO_3                    | allocate more extents
FILEWRITE_CONT:
        BNE.B   FILEWRITE_EXIT                  | err -> exit
FILEWRITE_NO_2:
        MOVE.L  D5,D4                           | D4 = position
        ADD.L   D7,D4                           | actually transferred this many more (IOActCount)
        MOVE.L  D4,fcbEOF(A1,D1.W)              | fcbEOF := new logical EOF
SAMELEN:
        MOVE    D5,D0                           | current file position
        ANDI    #0x1FF,D0                       | get index within block
        BEQ.B   WRMAIN                          | on block boundary -> bulk write
WRPART:
        BSR.W   HFSE_RDFILEBLK                  | read the block
        BNE.B   FILEWRITE_ERR                   | read err -> exit
        MOVEQ.L #0x1,D0                         | D0=1 for write
        BSR.B   DOPART                          | merge user data into buffer
        BSET    #0x7,-2(A5)                     | flag buffer dirty
WRMAIN:
        MOVE.L  D7,D4                           | D4 = bytes still to write
        BEQ.B   FILEWRITE_DONE                  | zero -> done
        CMPI.L  #0x200,D4                       | less than one block?
        BCS.B   WRPART                          | yes -> partial write
        ANDI    #-0x200,D4                      | round down to whole blocks
        BSR.W   LG2PHYS_NO                      | map logical -> physical block
        MOVE.L  ioBuffer(A0),A5                 | A5 = user buffer base
        ADDA.L  ioActCount(A0),A5               | A5 += ioActCount offset
        BSR.W   PreRdFileBlk                    | read block + update tags
        BNE.B   FILEWRITE_ERR                   | err -> exit
        BSR.B   FILEWRITE_CONT_2                | advance D5/D7/ioActCount
        BRA.B   WRMAIN                          | loop until D7 = 0
FILEWRITE_DONE:
        MOVEQ.L #0x0,D0                         | return noErr
FILEWRITE_ERR:
        BSR.W   AdjEof                          | MFSDealloc: free remaining extent chain
        MOVE.L  D5,fcbCrPs(A1,D1.W)             | FCB current mark = D5
FILEWRITE_EXIT:
        MOVE.L  fcbCrPs(A1,D1.W),ioPosOffset(A0) | copy mark back to IOParam.ioPosOffset
FILEWRITE_NO_3:
        BRA.W   FSQUEUE_DONE                    | -> common exit ($3954)

| ----------------------------------------------------------
| FILEWRITE_CONT_2 - UpdteCntPos: update byte count, actual count, and file position
| Called during boot.
FILEWRITE_CONT_2:
        SUB.L   D6,D7                           | adjust for number of bytes read/written
        ADD.L   D6,ioActCount(A0)               | actually transferred this many more (IOActCount)
        ADD.L   D6,D5                           | update current position
        RTS                                     | return updated counts and position
DOPART:
        MOVE.L  D5,D2                           | current file position
        ANDI    #0x1FF,D2                       | get index within block
        SUB     D2,D6                           | D6 = bytes remaining in this block
        CMP.L   D6,D7                           | need more than one block's worth?
        BCC.B   FILEWRITE_OK                    | no, D6 is fine
        MOVE.L  D7,D6                           | yes, limit to bytes remaining
FILEWRITE_OK:
        MOVE.L  ioBuffer(A0),A3                 | user buffer (IOBuffer)
        ADDA.L  ioActCount(A0),A3               | + IOActCount = target
        BSR.B   FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        MOVEM.L A0-A1,-(SP)                     | save regs
        MOVE.L  A3,A0                           | source = user buffer
        MOVE.L  A5,A1                           | dest = cache buffer
        ADDA.W  D2,A1                           | + index into block
        TST.B   D0                              | D0 > 0? (write)
        BGT.B   FILEWRITE_OK_2                  | yes, user->cache ->
        BMI.B   FILEWRITE_CONT_3                | verify (-1) -> compare path
        EXG     A0,A1                           | read (0) -> swap to cache->user
FILEWRITE_OK_2:
        MOVE.L  D6,D0                           | D0 = byte count
        _BlockMove                              | copy D0 bytes A0->A1
FILEWRITE_ERR_2:
        MOVEQ.L #0x0,D0                         | return noErr
FILEWRITE_EXIT_2:
        MOVEM.L (SP)+,A0-A1                     | restore A0/A1
        RTS                                     | return from DOPART
FILEWRITE_CONT_3:
        MOVEQ.L #-0x24,D0                       | D0 = ioErr (presumed for verify)
FILEWRITE_LOOP:
        CMPM.B  (A0)+,(A1)+                     | compare user vs cache byte
        BNE.B   FILEWRITE_EXIT_2                | mismatch -> verify error
        SUBQ.W  #0x1,D6                         | decrement byte count
        BNE.B   FILEWRITE_LOOP                  | loop until done
        BRA.B   FILEWRITE_ERR_2                 | verify match -> noErr

| ----------------------------------------------------------
| FlushFile -- _FlushFile ($A045).
| Pascal: function FlushFile(refNum: INTEGER): OSErr;
| Writes any pending data and FCB updates for an open file to
| disk without closing the file. Sets FlushOnly := -1 (true) so
| the common path skips the FCB-disposal step.
FlushFile:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST      (FlushOnly).w                   | FlushOnly := -1 (flush only)
        BRA.B   FILECLOSE_CONT                  | -> common flush/close path

| ----------------------------------------------------------
| FileClose -- _Close ($A001) for file paths.
| Pascal: function FileClose(refNum: INTEGER): OSErr;
| Closes an open file: flushes pending data, releases the FCB
| slot. Sets FlushOnly := 0 so the common path runs the full
| close (flush + dispose). Device Manager's Close trap entry in
| device_mgr.s also forwards file-refnum requests here.
FileClose:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        CLR.B   (FlushOnly).w                   | FlushOnly := 0 (close, not just flush)
FILECLOSE_CONT:
        BSR.W   RFNCall                         | RfNCall: is refnum for a valid open file?
        BEQ.B   FILECLOSE_CONT_2                | br if valid
        CMPI    #-0x35,D0                       | volume offline? (VolOffLinErr)
        BNE.B   FILECLOSE_ERR                   | no, some other error -> skip flush
FILECLOSE_CONT_2:
        BSR.B   FILECLOSE_NO_3                  | flush FCBs on offline volume
FILECLOSE_ERR:
        BRA.W    FSQUEUE_DONE                   | -> common exit
FS_CUR_BUF_BLOCK:
        BSR.W   L_MFILEREAD_LOOP_NO_CONT        | A5 = chosen buffer
        MOVE    -2(A5),D3                       | D3 = block tag from buffer
        BCLR    #0xF,D3                         | strip dirty-bit, leave block num
        RTS                                     | return; D3 = clean block num
FILECLOSE_NO_3:
        MOVE.L  (SP)+,A4                        | A4 = saved return PC
        BCLR    #0x7,fcbFlags(A1,D1.W)          | FCB dirty? (clear & test)
        BEQ.B   FILECLOSE_DISPOSE               | clean -> skip flush, dispose FCB
        BSR.B   FS_CUR_BUF_BLOCK                | get current buffer block num
        BPL.B   FILECLOSE_WRITE_DIR             | buffer matches FCB -> just write dir
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_4     | flush dirty buffer to disk
        BNE.B   FILECLOSE_FLUSH_EXIT            | flush err -> exit
FILECLOSE_WRITE_DIR:
        MOVE    fcbFlPos(A1,D1.W),D3            | D3 = FCB.fcbCtlgBlk or similar
        BSR.W   HFSE_READ_VBM_BLOCK             | read directory block
        BNE.B   FILECLOSE_FLUSH_EXIT            | error ->
FILECLOSE_DIR_SCAN:                             | directory entry scan loop top
        MOVEQ.L #0x0,D0                         | D0 = 0 (offset within block)
        MOVE.L  fcbFlNm(A1,D1.W),D3             | D3 = FCB.fcbFlNm (target file number)
FILECLOSE_CONT_5:
        CMP.L   0x12(A5,D0.W),D3                | match?
        BEQ.B   FILECLOSE_OK_4                  | yes ->
        BSR.W   CREATE_NEXT                     | advance D0 to next directory entry
        BCS.B   FILECLOSE_CONT_5                | more entries -> retry compare
        MOVEQ.L #-0x2B,D0                       | D0 = FNFErr (file not found)
        BRA.B   FILECLOSE_FLUSH_EXIT            | return error via A4
FILECLOSE_OK_4:
        LEA.L     0x16(A5,D0.W),A3              | A3 = &directory-entry[D0+0x16]
        BSR.B   FP68K_CONT_128_LOOP_CONT_BODY   | process found entry
        MOVE.L  (Time).w,0x2E(A5,D0.W)          | timestamp = current time
        BSET    #0x7,-2(A5)                     | flag dir block as dirty
FILECLOSE_DISPOSE:
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FILECLOSE_KEEP_FCB              | yes, keep FCB ->
        LEA.L     fcbFlNm(A1,D1.W),A3           | point to FCB entry
        MOVEQ.L #0xE,D0                         | D0 = 14 (clear 15 words)
FILECLOSE_CLR_FCB:
        CLR     (A3)+                           | clear one FCB word
        DBRA    D0,FILECLOSE_CLR_FCB            | loop 15 words
FILECLOSE_KEEP_FCB:
        MOVEQ.L #0x0,D0                         | return noErr
FILECLOSE_FLUSH_EXIT:
        JMP     (A4)                            | return via saved A4
FP68K_CONT_128_LOOP_CONT_BODY:                  | @ $4824 (directory-entry handler)

| ----------------------------------------------------------
| FILECLOSE_CONT_6
| Called during boot.
| FILECLOSE_CONT_6/UpdFlNtry: update file lengths in catalog from FCB
| A3 = ptr to file length fields in catalog, (A1,D1) = FCB
FILECLOSE_CONT_6:
        MOVE.L  A4,-(SP)                        | save A4
        LEA.L   fcbFlags(A1,D1.W),A4            | A4 = FCB flags (FCBMdRByt)
        MOVE    (A4)+,D3                        | get flags
        LSL     #0x7,D3                         | resource fork bit in carry
        BCC.B   FILECLOSE_CONT_7                | data fork ->
        ADDA    #0xA,A3                         | skip data fork fields (10 bytes)
FILECLOSE_CONT_7:
        MOVE    (A4)+,(A3)+                     | copy start block (FCBStBlk)
        MOVE.L  (A4)+,(A3)+                     | copy LEOF (FCBEOF)
        MOVE.L  (A4)+,(A3)+                     | copy PEOF (FCBPLen)
        MOVE.L  (SP)+,A4                        | restore A4
        RTS                                     | exit UpdFlNtry

| ----------------------------------------------------------
| _GetEOF ($A011): get logical end of file
| Returns FCB.fcbEOF in ioMisc (offset 28).
GetEOF:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   RFNCall                         | RfNCall: is refnum for a valid open file?
        BNE.B   GETEOF_NO                       | br if not
        MOVE.L  fcbEOF(A1,D1.W),28(A0)          | return the logical EOF (FCBEOF -> IOLEOF)
GETEOF_NO:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done
RFNCall:
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB table base
        CLR.L   D1                              | D1 = 0 (clear high bytes)
        MOVE    ioRefNum(A0),D1                 | D1 = refNum from param block
        MOVE.L  D1,D2                           | D2 = refNum (working copy)
        MOVEQ.L #-0x33,D0                       | D0 = rfNumErr (-51) preset
        DIVU    #0x1E,D2                        | D2 = D2 /u #0x1E
        SWAP    D2                              | D2 high word = remainder
        SUBQ.W  #0x2,D2                         | D2 -= 0x2 (remainder -> FCB index)
        BNE.B   RFNCALL_CONT                    | non-zero -> misaligned refnum -> rfNumErr
        CMP     (A1),D1                         | D1 <= (A1) = FCBS byte count?
        BCC.B   RFNCALL_CONT                    | no (D1 too large) -> rfNumErr
        MOVEQ.L #-0x26,D0                       | D0 = rfNumErr (if FCB turns out closed)
        MOVE.L  fcbFlNm(A1,D1.W),D2             | D2 = FCB.fcbFlNm (file number; 0 = closed)
        BEQ.B   RFNCALL_CONT                    | FCB closed -> return rfNumErr
        MOVEA.L fcbVPtr(A1,D1.W),A2             | A2 = FCB.fcbVPtr (VCB)
        BSR.W   FNDFILNAME_CONT_4               | validate + load helper
RFNCALL_CONT:
        TST.W   D0                              | Z reflects noErr / error
        RTS                                     | return; D0 = result

| ----------------------------------------------------------
| TstMod: test if we may modify this file
| Called during boot.
TstMod:
        BSR.B   RFNCall                         | validate refnum -> A1, D1
        BNE.B   TSTMOD_EXIT                     | exit on errors
        MOVEQ.L #-0x3D,D0                       | assume wrPermErr
        BTST    #0x0,fcbFlags(A1,D1.W)          | write permission? (FCBWriteBit)
        BEQ.B   TSTMOD_EXIT                     | no, can't modify ->
        BSR.W   SETVOLINFO_HFS_CONT_3           | check volume write protect
TSTMOD_EXIT:
        TST     D0                              | set CCR from D0
        RTS                                     | return; D0 = err code

| ----------------------------------------------------------
| _Allocate ($A010): pre-allocate disk space for a file
| Plus 1986 added zero-request and free-blocks early-out checks;
| classic 1984 always calls FileAlloc.
Allocate:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   TstMod                          | verify refNum + write perms
        BNE.B   ALLOCATE_ERR                    | denied -> exit
        MOVE.L  ioReqCount(A0),D4               | D4 = ioReqCount (bytes requested)
        MOVEQ.L #0x0,D0                         | D0 = 0 (no flags)
        BSR.W   LG2PHYS_CONT_2                  | allocate D4 bytes -> D6
        BNE.B   ALLOCATE_ERR                    | err -> exit
        MOVE.L  D6,ioActCount(A0)               | return actual bytes allocated (ioActCount)
        BSR.W   AdjEof                          | AdjEOF: adjust other FCBs
        MOVEQ.L #-0x22,D0                       | DskFulErr (in case partial alloc)
        CMP.L   ioReqCount(A0),D6               | got full request?
        BCS.B   ALLOCATE_ERR                    | unsigned less ->
        MOVEQ.L #0x0,D0                         | dupFNErr
ALLOCATE_ERR:
        BRA.W   FSQUEUE_DONE                    | -> noErr

| ----------------------------------------------------------
| _SetEOF ($A012): set logical end-of-file
SetEOF:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   TstMod                          | verify refnum + write perms
        BNE.B   SETEOF_EXIT                     | test failed -> exit via common tail
        MOVE.L  28(A0),D7                       | D7 = ioMisc (new EOF)
        MOVE.L  D7,D4                           | D4 = new EOF (work copy)
        SUB.L   fcbPLen(A1,D1.W),D4             | D4 -= fcbPLen(A1,D1.W)
        BCS.B   ADJEOF_NO                       | shrinking -> truncate
        BHI.B   SETEOF_CONT_3                   | branch if > (unsigned)
SETEOF_NO:
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
        MOVE.L  D7,fcbEOF(A1,D1.W)              | FCB.fcbEOF = requested EOF
        CMP.L   fcbCrPs(A1,D1.W),D7             | mark > new EOF?
        BCC.B   SETEOF_OK_2                     | no -> skip mark update
        MOVE.L  D7,fcbCrPs(A1,D1.W)             | yes: clamp FCB current mark to new EOF
SETEOF_OK_2:
        BSR.B   AdjEof                          | adjust physical EOF to match
SETEOF_EXIT:
        BRA.W   FSQUEUE_DONE                    | -> common FS exit

| ----------------------------------------------------------
| ADJEOF_NO
| Called during boot.
ADJEOF_NO:
        MOVEQ.L #0x0,D6                         | dupFNErr
        MOVE    fcbSBlk(A1,D1.W),D3             | D3 = start alloc block (FCBStBlk)
        MOVE.L  vcbAlBlkSiz(A2),D2              | D2 = alloc block size
        MOVE.L  D7,D4                           | D4 = new LEOF
        BNE.B   ADJEOF_CONT_2                   | nonzero, walk chain ->
        CLR     fcbSBlk(A1,D1.W)                | LEOF=0: clear start block (FCBStBlk)
        BRA.B   ADJEOF_CONT_3                   | free entire extent chain
ADJEOF_CONT:
        MOVE.W   D5,D3                          | D3 = next alloc block in chain
ADJEOF_CONT_2:
        ADD.L   D2,D6                           | D6 += alloc-block size (running total)
        BSR.W   LG2PHYS_NEXT_2                  | walk to next extent in MFS map
        SUB.L   D2,D4                           | subtract one block-size from D4
        BHI.B   ADJEOF_CONT                     | branch if > (unsigned)
        CMP.L   fcbPLen(A1,D1.W),D6             | reached old physical EOF?
        BCC.B   SETEOF_NO                       | yes -> nothing to free
        MOVE    D5,-(SP)                        | D3 = next alloc block start
        MOVEQ.L #0x1,D5                         | D5 = 1 (mark "free chain")
        BSR.W   LG2PHYS_CONT_9                  | free extents past D6
        MOVE    (SP)+,D3                        | restore D3
ADJEOF_CONT_3:
        BSR.W   LG2PHYS_CONT_10                 | free remaining extents
        MOVE.L  D6,fcbPLen(A1,D1.W)             | fcbPLen := new physical length
        BRA.B   SETEOF_NO                       | finalize (set logical EOF)
SETEOF_CONT_3:
        BSR.W   LG2PHYS_NO_3                    | extend file to new EOF
        BNE.B   SETEOF_EXIT                     | LG2PHYS_NO_3 error -> exit via common tail
        BRA.B   SETEOF_NO                       | finalize EOF
AdjEof:
        MOVEM.L D0-D6/A0-A2,-(SP)               | save D0-D6/A0-A2
        ADDA.W  D1,A1                           | A1 = current FCB
        MOVE.L  (A1)+,D2                        | D2 = file number; A1 -> flags
        BSET    #0x7,(A1)                       | set fcbDirty bit
        MOVE    (A1),D0                         | D0 = FCB flags (incl fork bit)
        MOVEM.L (A1)+,D3-D6/A2                  | (A1)+ -> D3-D6/A2
        MOVE    D0,D6                           | D6 = our FCB flags
        BSR.W   HFSE_NEXT_CONT                  | search first FCB matching this fileID
        BNE.B   ADJEOF_FOUND_2                  | no more FCBs -> exit
ADJEOF_FOUND:
        LEA.L     fcbFlags(A1,D1.W),A0          | point to this FCB's flags
        MOVE    (A0)+,D0                        | get this FCB's flags
        EOR     D6,D0                           | D0 = bits that differ from us
        LSL     #0x7,D0                         | resource fork bit in carry
        BCS.B   ADJEOF_SKIP                     | fork bit differs -> skip update
        MOVE    D3,(A0)+                        | update StBlk
        MOVE.L  D4,(A0)+                        | update LEOF
        MOVE.L  D5,(A0)+                        | update PEOF
ADJEOF_SKIP:
        BSR.W   HFSE_ERR_9                      | advance to next FCB match
        BEQ.B   ADJEOF_FOUND                    | another match -> update it too
ADJEOF_FOUND_2:
        MOVEM.L (SP)+,D0-D6/A0-A2               | restore D0-D6/A0-A2
        RTS                                     | return from AdjEof

| ----------------------------------------------------------
| LG2PHYS_NO - MFS Lg2Phys: simple linear extent mapping
| Called during boot.
LG2PHYS_NO:
        MOVEM.L D1-D2/D4-D5/D7,-(SP)            | save registers
        MOVE.L  vcbAlBlkSiz(A2),D7              | D7 = allocation block size
        MOVE    fcbSBlk(A1,D1.W),D3             | D3 = start alloc block from FCB
        ADD.L   D5,D4                           | D4 = end position (pos + max bytes - 1)
        SUBQ.L  #0x1,D4                         | adjust to last byte in range
        MOVEQ.L #0x9,D1                         | shift count for /512
        MOVEQ.L #0x0,D6                         | D6 = bytes mapped so far
        LSR.L   D1,D4                           | D4 = end block (in 512-byte blocks)
        LSR.L   D1,D7                           | D7 = alloc block size in 512-byte blocks
        MOVE.L  D5,D2                           | D2 = start block
        LSR.L   D1,D2                           | convert bytes to 512-byte blocks
        BRA.B   LG2PHYS_CONT                    | enter walk loop
LG2PHYS_NEXT:
        BSR.B   LG2PHYS_NEXT_2                  | walk to next alloc block
        MOVE    D5,D3                           | D3 = next alloc block start
        SUB     D7,D4                           | adjust end/start for this extent
        SUB     D7,D2                           | blocks remaining in this extent
LG2PHYS_CONT:
        CMP     D7,D2                           | start block within this extent?
        BCC.B   LG2PHYS_NEXT                    | no, try next extent
        MOVE    D3,D0                           | alloc block start
        SUBQ.W  #0x2,D0                         | - 2 (alloc blocks start at 2)
        MULU    D7,D0                           | D0 = block * blocks-per-alloc
        ADD     D2,D0                           | + offset within alloc block
        ADD     vcbAlBlSt(A2),D0                | + volume alloc block start
        MOVE    D0,-(SP)                        | stash starting block on stack
| count contiguous blocks from this extent
LG2PHYS_OK:
        MOVE    D7,D0                           | blocks remaining in this extent
        SUB     D2,D0                           | - offset into extent
        ADD     D0,D6                           | add to contiguous block count
        SUB     D0,D4                           | subtract from remaining request
        BMI.B   LG2PHYS_DONE                    | done if covered all requested blocks
        BSR.B   LG2PHYS_NEXT_2                  | walk to next extent in chain
        MOVEQ.L #0x0,D2                         | start at beginning of next extent
        ADDQ.W  #0x1,D3                         | check if next extent is contiguous
        CMP     D3,D5                           | (next alloc block == expected?)
        BEQ.B   LG2PHYS_OK                      | yes, keep counting contiguous blocks
LG2PHYS_DONE:
        MOVE    (SP)+,D3                        | D3 = starting physical block
        MOVE    D3,D0                           | D0 = starting block
        ADD     D6,D0                           | D0 = ending block (sanity check)
        MOVE    vcbAlBlSt(A2),D4                | D4 = volume alloc block start
        MULU    vcbNmAlBlks(A2),D7              | D7 = D7 *u 26(A2)
        ADD     D4,D7                           | D7 = volume end (alloc area)
        CMP     D7,D0                           | ending block past volume end?
        BHI.B   LG2PHYS_ERR                     | yes -> bad volume metadata
        CMP     D4,D3                           | starting block before alloc area?
        BCS.B   LG2PHYS_ERR                     | yes -> bad
        ASL.L   D1,D6                           | D6 = bytes (D6 * 512)
        MOVEM.L (SP)+,D1-D2/D4-D5/D7            | restore D1-D2/D4-D5/D7
        CMP.L   D4,D6                           | contiguous bytes > requested?
        BLS.B   LG2PHYS_NO_2                    | no -> use D6 as-is
        MOVE.L  D4,D6                           | yes -> clamp to requested
LG2PHYS_NO_2:
        RTS                                     | return; D6 = bytes mappable
LG2PHYS_ERR:
        MOVEQ.L #0x1B,D0                        | D0 = dsBadAllocBlock (27)
        _SysError                               | fatal: corrupt alloc map
| ----------------------------------------------------------
| LG2PHYS_NEXT_2
| Called during boot (3,700 times in 30s trace).
| LG2PHYS_NEXT_2: MFS alloc map lookup - get next alloc block from 12-bit map
| D3 = current alloc block, returns D5 = next alloc block
LG2PHYS_NEXT_2:
        MOVEM.L D0/A2,-(SP)                     | save regs
        MOVE.L  vcbMAdr(A2),A2                  | A2 = allocation map base
        MOVE    D3,D0                           | alloc block number
        SUBQ.W  #0x2,D0                         | subtract 2 (map starts at block 2)
        MULU    #0xC,D0                         | * 12 bits per entry
        ROR.L   #0x4,D0                         | convert bit offset to byte.nibble
        ASL     #0x1,D0                         | byte offset (word-aligned)
        MOVE.L  0x0(A2,D0.W),D5                 | get longword containing 12-bit entry
        CLR     D0                              | isolate nibble offset
        ROL.L   #0x4,D0                         | shift nibble index to low bits
        ADDI    #0xC,D0                         | + 12 bits
        ROL.L   D0,D5                           | rotate entry to low 12 bits
        ANDI    #0xFFF,D5                       | mask to 12 bits
        MOVEM.L (SP)+,D0/A2                     | restore regs
        RTS                                     | return with entry in D5
LG2PHYS_NO_3:
        MOVE.L   D4,D0                          | D0 = bytes still needed
LG2PHYS_CONT_2:
        MOVEM.L D1-D5/D7-A3,-(SP)               | save regs
        MOVE.L  vcbAlBlkSiz(A2),D7              | alloc block size
        MOVE.L  D7,D6                           | compute free space in bytes
        MULU    vcbFreeBks(A2),D6               | D6 = D6 *u 0x2A(A2)
        CMP.L   D6,D4                           | request > free space?
        BLS.B   LG2PHYS_NO_4                    | no ->
        MOVE.L  D6,D4                           | limit to available space
LG2PHYS_NO_4:
        CMP.L   D0,D4                           | enough space?
        BCC.B   LG2PHYS_OK_2                    | yes ->
        MOVEQ.L #-0x22,D0                       | DskFulErr
LG2PHYS_EXIT:
        MOVEM.L (SP)+,D1-D5/D7-A3               | restore D1-D5/D7-A3
        RTS                                     | return from MFS alloc

| MFS Alloc: extend file by allocating blocks from alloc map
LG2PHYS_OK_2:
        MOVE.L  fcbPLen(A1,D1.W),D2             | D2 = current PEOF (FCBPLen)
        MOVEQ.L #0x0,D6                         | D6 = bytes allocated so far
        MOVE    fcbSBlk(A1,D1.W),D3             | D3 = start alloc block (FCBStBlk)
        BNE.B   LG2PHYS_CONT_3                  | have blocks already ->
        BSR.B   LG2PHYS_NEXT_3                  | find free block
        MOVE    D5,fcbSBlk(A1,D1.W)             | set start block (FCBStBlk)
        MOVE    D5,D3                           | D3 = current alloc block
        MOVEQ.L #0x1,D5                         | dupFNErr
        BSR.W   LG2PHYS_CONT_9                  | call helper
        BRA.B   LG2PHYS_CONT_5                  | count this block, advance
LG2PHYS_ERR_2:
        MOVE.W   D5,D3                          | read high byte of 12-bit entry
LG2PHYS_CONT_3:
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        CMPI    #0x1,D5                         | end-of-chain (1)?
        BNE.B   LG2PHYS_ERR_2                   | error ->
LG2PHYS_NO_5:
        CMP     vcbNmAlBlks(A2),D3              | block past end of volume?
        BHI.B   LG2PHYS_OK_3                    | yes ->
        ADDQ.W  #0x1,D3                         | peek at next block
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        SUBQ.W  #0x1,D3                         | restore current block number
        TST     D5                              | next block occupied?
        BNE.B   LG2PHYS_OK_3                    | yes, find another free ->
        MOVE    D3,D5                           | new block = current + 1
        ADDQ.W  #0x1,D5                         | D5 = next sequential block
LG2PHYS_CONT_4:
        BSR     LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: link current -> new block in map
        MOVE    D5,D3                           | D3 = new block (now current)
        MOVEQ.L #0x1,D5                         | mark new block as end-of-chain (1)
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: set new block's map entry
LG2PHYS_CONT_5:
        ADD.L   D7,D6                           | D6 += alloc-block bytes (running)
        ADD.L   D7,D2                           | D2 += alloc-block bytes (PEOF)
        SUBQ.W  #0x1,vcbFreeBks(A2)             | 0x2A(A2) -= 0x1
        CMP.L   D6,D4                           | allocated enough?
        BHI.B   LG2PHYS_NO_5                    | branch if > (unsigned)
        MOVE.L  D2,fcbPLen(A1,D1.W)             | D2 = new free run start candidate
        ST      6(A2)                           | 6(A2) := -1 (true)
        MOVEQ.L #0x0,D0                         | return noErr
        BRA.B   LG2PHYS_EXIT                    | restore regs and return
LG2PHYS_OK_3:
        BSR.B   LG2PHYS_NEXT_3                  | find another free run
        BRA.B   LG2PHYS_CONT_4                  | link new run into chain

| ----------------------------------------------------------
| LG2PHYS_NEXT_3
| LG2PHYS_NEXT_3: MFS find free block - scan alloc map for best free run
LG2PHYS_NEXT_3:
        MOVEM.L D0-D4/D6/A1/A3,-(SP)            | save regs
        SUB.L   D6,D4                           | remaining bytes needed
        CMP.L   vcbClpSiz(A2),D4                | more than one clump?
        BCC.B   LG2PHYS_OK_4                    | yes, use full request ->
        MOVE.L  vcbClpSiz(A2),D4                | no, round up to clump size

| MFS Alloc: scan entire alloc map for best-fit free chain
LG2PHYS_OK_4:
        MOVE.L  vcbMAdr(A2),A1                  | A1 = alloc map base
        MOVE    vcbNmAlBlks(A2),A3              | A3 = total alloc blocks
        ADDQ.W  #0x1,A3                         | + 1 (sentinel)
        MOVEQ.L #0x0,D5                         | D5 = nibble toggle (odd/even 12-bit entry)
        MOVEQ.L #0x2,D0                         | D0 = current block number (start at 2)
        MOVEQ.L #0x2,D2                         | D2 = best-fit start block
        MOVEQ.L #0x0,D3                         | D3 = current free run length
        MOVEQ.L #0x0,D6                         | D6 = best free run length
        CLR     -(SP)                           | push best-fit block number (0 = none)
LG2PHYS_NO_6:
        MOVE.B  (A1)+,D1                        | read high byte of 12-bit entry
        LSL     #0x8,D1                         | shift to high position
        BCHG    #0x0,D5                         | D5 ^= 1<<0x0
        BNE.B   LG2PHYS_ERR_3                   | error ->
        MOVE.B  (A1),D1                         | read low nibble byte
        LSR     #0x4,D1                         | shift nibble to low position
        BRA.B   LG2PHYS_CONT_6                  | test 12-bit entry for free
LG2PHYS_ERR_3:
        MOVE.B   (A1)+,D1                       | read low byte of 12-bit entry
        ANDI.W   #0xFFF,D1                      | isolate low 12 bits

| MFS Alloc scan: check if this block is free (entry = 0)
LG2PHYS_CONT_6:
        BNE.B   LG2PHYS_NO_8                    | not free, end of free run ->
        ADD.L   D7,D3                           | extend free run by alloc block size
        CMP.L   D6,D3                           | better than current best?
        BLS.B   LG2PHYS_NO_7                    | no ->
        MOVE.L  D3,D6                           | yes, update best free run length
        MOVE    D2,(SP)                         | save best-fit start block
        CMP.L   D4,D3                           | run >= requested size?
        BCC.B   LG2PHYS_CONT_8                  | unsigned greater or equal ->
LG2PHYS_NO_7:
        ADDQ.W  #0x1,D0                         | advance to next block
        BRA.B   LG2PHYS_CONT_7                  | loop scan
LG2PHYS_NO_8:
        ADDQ.W  #0x1,D0                         | advance past occupied block
        MOVE    D0,D2                           | D2 = new free run start candidate
        MOVEQ.L #0x0,D3                         | dupFNErr
LG2PHYS_CONT_7:
        CMP     A3,D0                           | end of alloc map?
        BLS.B   LG2PHYS_NO_6                    | branch if <= (unsigned)
LG2PHYS_CONT_8:
        MOVE    (SP)+,D5                        | D5 = best-fit start block
        MOVEM.L (SP)+,D0-D4/D6/A1/A3            | restore D0-D4/D6/A1/A3
        RTS                                     | return from free-run scan

| ----------------------------------------------------------
| LG2PHYS_CONT_9
| LG2PHYS_CONT_9: MFS alloc map write - set 12-bit entry in alloc map
| D3 = alloc block number, D5 = value to store (12-bit next block)
LG2PHYS_CONT_9:
        MOVEM.L D0/D6/A2,-(SP)                  | save regs
        MOVE.L  vcbMAdr(A2),A2                  | A2 = allocation map base
        MOVE    D3,D0                           | alloc block number
        SUBQ.W  #0x2,D0                         | subtract 2 (map starts at block 2)
        MULU    #0xC,D0                         | * 12 bits per entry
        ROR.L   #0x4,D0                         | convert bit offset to byte.nibble
        ASL     #0x1,D0                         | word-aligned byte offset
        MOVE.L  0x0(A2,D0.W),D6                 | get longword containing entry
        SWAP    D0                              | get nibble offset
        LSR     #0x8,D0                         | shift nibble index
        LSR     #0x4,D0                         | to low 4 bits
        ADDI    #0xC,D0                         | + 12 bits
        ROL.L   D0,D6                           | rotate entry to low 12 bits
        ANDI    #-0x1000,D6                     | clear old 12-bit value
        OR      D5,D6                           | merge new value
        ROR.L   D0,D6                           | rotate back to position
        SWAP    D0                              | restore byte offset
        MOVE.L  D6,0x0(A2,D0.W)                 | write back to alloc map
        MOVEM.L (SP)+,D0/D6/A2                  | restore regs
        RTS                                     | return after updating map
LG2PHYS_CONT_10:
        TST     D3                              | D3 = first alloc block in chain
        BEQ.B   LG2PHYS_CONT_11                 | empty chain -> nothing to free
LG2PHYS_NO_9:
        BSR.W   LG2PHYS_NEXT_2                  | get next block in chain (D5)
        MOVE    D5,-(SP)                        | save next block
        CLR     D5                              | write 0 (free) to map entry
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: write 0 to alloc map
        ADDQ.W  #0x1,vcbFreeBks(A2)             | increment free block count
        MOVE    (SP)+,D3                        | D3 = next block in chain
        CMPI    #0x1,D3                         | end-of-chain marker? (block 1)
        BNE.B   LG2PHYS_NO_9                    | no, keep freeing ->
        ST      6(A2)                           | 6(A2) := -1 (true, VCB dirty)
LG2PHYS_CONT_11:                                | @ $4B42 (skip-all exit)
        RTS                                     | return from chain-free helper
