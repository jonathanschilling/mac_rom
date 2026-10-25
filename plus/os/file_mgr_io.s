| File Manager -- calls on open files (refnum-based)
|
| Apple sources: TFSRFN1.a ... TFSRFN3.a and MFSRFN1.a ... MFSRFN3.a,
| included by TFS.a (MacSEROM.lst module TURBOFS): GetFPos, SetFPos,
| FileRead and FileWrite (the File Manager's _Read/_Write), FlushFile,
| FileClose, GetEOF, the refnum check RFNCall, Allocate, SetEOF, AdjEOF
| and Lg2Phys (logical file position -> physical disk block through the
| file's extents). Each call handles HFS and MFS volumes.
|
| References: Inside Macintosh Vol II, Ch 4: The File Manager;
| Inside Macintosh Vol IV, Ch 19: The File Manager

| GetFPos -- _GetFPos ($A018): FUNCTION GetFPos (refNum: INTEGER; VAR filePos: LONGINT) OSErr;
| ----------------------------------------------------------
|
| _GetFPos ($A018)
|
GetFPos:
        CLR.B   0x2D(A0)                        | clear
| SetFPos -- _SetFPos ($A044): FUNCTION SetFPos (refNum: INTEGER; posMode: INTEGER; posOff:
SetFPos:
        CLR.L   0x24(A0)                        | clear
| FileRead (vFileRead)
L_mFileRead:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     P_RFNCall                       | RFNCall: map the reference number
        BNE     L_MFILEREAD_EXIT_3              | exit on errors (don't set IOPosOffset)
        BSR.B   SEEK                            | Seek: do any positioning, D5=cur pos, D7=IOReqCount
        BNE.B   L_MFILEREAD_EXIT_2              | exit if positioned before file start
| figure min(requested count, distance to EOF)
        NEG.L   D2                              | EOF - current pos (from Seek)
        BMI.B   L_MFILEREAD_CONT_2              | if negative, report end of file
        CMP.L   D2,D7                           | number of bytes desired within EOF?
        BLE.B   L_MFILEREAD_CONT                | br if so
        MOVE.L  D2,D7                           | just read distance to EOF
L_MFILEREAD_CONT:
        TST.L   D7                              | byte count 0?
        BEQ.B   L_MFILEREAD_DONE                | all done if none to read
        MOVE    ioPosMode(A0),D2                | get newline stuff
        LSR     #0x8,D2                         | newline char in low byte, enb in carry
        BCS.B   L_MFILEREAD_CONT_3              | if newline enabled, do it differently
        BTST    #0x6,0x2D(A0)                   | read verify?
        BEQ.B   L_MFILEREAD_NO                  | br if not
        MOVEM.L D1/A1,-(A6)                     | save A1/D1 across FlushCache call
        MOVE    D1,D0                           | set up to flush file's blocks
        MOVEQ.L #0x0,D1                         | just normal call
        MOVE.L  vcbBufAdr(A2),A1                | point to volume buffer
        JSR     P_mFlushCache(PC)               | write all file blocks before read-verify
        MOVEM.L (A6)+,D1/A1                     | and trash so we actually read them
L_MFILEREAD_NO:
        MOVE    D5,D2                           | current file position (low word)
        ANDI    #0x1FF,D2                       | check lower 9 bits for blk bndry read
        BEQ.B   RDMAIN                          | br if so (can read into place)
| RdPart: must read a partial block first
RDPART:
        BSR     L_MFILEREAD_CONT_5              | RdFileBlk: read the data block
        BNE.B   L_MFILEREAD_EXIT                | exit on errors
        BTST    #0x6,0x2D(A0)                   | read verify only?
        SNE.B   D0                              | $00 if not, $FF if so
        BSR     DOPART                          | DoPart: copy partial block to user buffer
        BNE.B   L_MFILEREAD_EXIT                | exit on verify errors
| RdMain: read multiple blocks into place in user's buffer
RDMAIN:
        MOVE.L  D7,D4                           | number of bytes we want
        BEQ.B   L_MFILEREAD_DONE                | all done if no more bytes
        ANDI    #-0x200,D4                      | only read whole blocks ($FE00 mask)
        TST.L   D4                              | any whole blocks to read?
        BEQ.B   RDPART                          | br if not
        JSR     P_mCacheRDIP(PC)                | CacheRdIP: read blocks into user buffer
        BNE.B   L_MFILEREAD_EXIT                | disk errors ->
        BSR     FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        BRA.B   RDMAIN                          | loop
| FRdOK
L_MFILEREAD_DONE:
        MOVEQ.L #0x0,D0                         | no errors (except maybe EOF)
L_MFILEREAD_EXIT:
        TST     D0                              | other error?
        BNE.B   L_MFILEREAD_EXIT_2              | br if so
        MOVE.L  0x28(A0),D2                     | if actual count != requested count
        CMP.L   0x24(A0),D2                     | (IOActCount vs IOReqCount)
        BEQ.B   L_MFILEREAD_EXIT_2              | (br if equal, no EOF)
| FRdEOFXit
L_MFILEREAD_CONT_2:
        MOVEQ.L #-0x27,D0                       | EOFErr: hit end of file
L_MFILEREAD_EXIT_2:
        MOVE.L  D5,0x10(A1,D1.W)                | update current position in FCB (FCBCrPs)
        MOVE.L  D5,ioPosOffset(A0)              | always return current pos
L_MFILEREAD_EXIT_3:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_3
|
| FRNewLine: reading while looking for end of line characters
L_MFILEREAD_CONT_3:
        BSR.B   L_MFILEREAD_CONT_5              | RdFileBlk: read the data block
        BNE.B   L_MFILEREAD_EXIT                | exit on errors
        MOVE.L  D5,D2                           | current file position
        ANDI    #0x1FF,D2                       | get the index within block
        MOVE.L  0x20(A0),A3                     | user buffer (IOBuffer)
        MOVE.L  0x28(A0),D4                     | where to start continuing read (IOActCount)
| newline byte-by-byte scan loop
L_MFILEREAD_LOOP:
        MOVE.B  0x0(A5,D2.W),D0                 | get byte from the buffer
        MOVE.B  D0,0x0(A3,D4.L)                 | put it into user's area
        ADDQ.L  #0x1,0x28(A0)                   | actually read another byte (IOActCount)
        ADDQ.L  #0x1,D4                         | incr destination byte offset
        ADDQ.W  #0x1,D2                         | incr source byte offset
        ADDQ.L  #0x1,D5                         | incr current position
        CMP.B   ioPosMode(A0),D0                | is it the EOL character?
        BNE.B   L_MFILEREAD_NO_2                | no ->
        MOVEQ.L #0x0,D0                         | no error, we found EOL
        BRA.B   L_MFILEREAD_EXIT_2              | exit ->
L_MFILEREAD_NO_2:
        SUBQ.L  #0x1,D7                         | decr byte count
        BEQ.B   L_MFILEREAD_DONE                | exit, checking for EOF condition
        CMP     D6,D2                           | reached end of buffer?
        BCS.B   L_MFILEREAD_LOOP                | loop if not
        BRA.B   L_MFILEREAD_CONT_3              | get another block

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_4
|
| Called during boot.
| L_MFILEREAD_CONT_4/PreRdFileBlk: read file block, but only if within current LEOF
L_MFILEREAD_CONT_4:
        BSR.B   L_MFILEREAD_CONT_6              | read the file block
        CMP.L   D3,D5                           | current pos < LEOF boundary? (D3=rounded LEOF)
        BCS.B   L_MFILEREAD_OK                  | yes, block has valid data ->
        MOVEQ.L #0x4,D1                         | no, block is beyond LEOF: RBdirty option
        BRA.B   L_MFILEREAD_OK                  | ->

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_5
|
| Called during boot.
| L_MFILEREAD_CONT_5/RdFileBlk: read a file block into volume cache
L_MFILEREAD_CONT_5:
        BSR.B   L_MFILEREAD_CONT_6              | map file pos and read block
        BTST    #0x6,0x2D(A0)                   | read verify mode? (IOPosMode bit 6)
        BEQ.B   L_MFILEREAD_OK                  | no ->
        MOVEQ.L #0x1,D1                         | yes: force read (GBRead option)
L_MFILEREAD_OK:
        MOVE.L  vcbBufAdr(A2),A1                | volume cache queue
        MOVE.L  D5,D2                           | file position
        LSR.L   #0x8,D2                         | / 256...
        LSR.L   #0x1,D2                         | / 2 = file block number
        RTS                                     | return cache queue and block number

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_6
|
| Called during boot.
L_MFILEREAD_CONT_6:
        MOVEM.L D1-D2/A0-A1,-(A6)               | save regs
| L_MFILEREAD_CONT_6: read file block into cache (PreRdFileBlk helper)
| only reads if block is within current LEOF
        MOVE.L  (SP)+,A1                        | A1 = Lg2Phys vector
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE    D1,D0                           | file refnum
        MOVEQ.L #0x0,D1                         | no GetBlock options
        MOVEQ.L #0x2,D6                         | D6 = 512 (block size)
        LSL.L   #0x8,D6                         | D6 = 0x200 = 512 bytes
        JSR     (A1)                            | Lg2Phys: map file pos to disk block
        ADDQ.B  #0x8,D1                         | D1 = GBrelease option
        JSR     P_mGetBlock(PC)                 | GetBlock: read block from cache
        MOVE.L  A0,A5                           | A5 = block data pointer
        MOVE.L  (A6)+,-(SP)                     | restore return address
        MOVEM.L (A6)+,D1-D2/A0-A1               | restore regs
        TST     D0                              | set condition codes
        RTS                                     | return with block data in A5

| ----------------------------------------------------------
|
| File Write
|
| Called during boot.
FileWrite:
        BSR     FSQUEUE_SETUP                   | call helper
        BSR     TstMod                          | call helper
| FileWrite (vFileWrite)
        BNE.B   FILEWRITE_NO_3                  | br if not allowed to modify
        BSR     SEEK                            | Seek: position and set up D5, D7
        BNE.B   FILEWRITE_CONT                  | br if positioned before start
        TST.L   D2                              | positioned past EOF?
        BMI.B   FILEWRITE_NO                    | br if not
        ADD.L   D2,D5                           | extend added to cur pos
| set up D3 so PreRdFileBlk knows when block must actually be read
FILEWRITE_NO:
        MOVE.L  #0x1FF,D3                       | 511
        ADD.L   D4,D3                           | add current LEOF from Seek
        ANDI    #-0x200,D3                      | LEOF rounded to next block boundary
| see if file has to be made physically longer
        MOVE.L  D5,D4                           | current position after positioning
        ADD.L   D7,D4                           | end byte for write + 1
        CMP.L   0x8(A1,D1.W),D4                 | will it fit within old EOF? (FCBEOF)
        BLS.B   SAMELEN                         | if so, leave file at same phys length
        SUB.L   0xC(A1,D1.W),D4                 | past the phys end? (FCBPLen)
        BLS.B   FILEWRITE_NO_2                  | no, just reset the EOF
| ran off physical end: allocate more blocks
        BSR     ADJEOF_CONT_4                   | Alloc: allocate more space
FILEWRITE_CONT:
        BNE.B   FILEWRITE_EXIT                  | exit if didn't get it
| update logical length
FILEWRITE_NO_2:
        MOVE.L  D5,D4                           | current position after positioning
        ADD.L   D7,D4                           | + # bytes to write
        MOVE.L  D4,0x8(A1,D1.W)                 | is new logical end-of-file (FCBEOF)
| SameLen: data will fit, start writing
SAMELEN:
        MOVE    D5,D0                           | check if writing to a block boundary
        ANDI    #0x1FF,D0                       | if so, low 9 bits will be 0
        BEQ.B   WRMAIN                          | if so, try writing full blocks out
| WrPart: must write a partial block first
WRPART:
        BSR     L_MFILEREAD_CONT_4              | PreRdFileBlk: get the appropriate block
        BNE.B   FILEWRITE_ERR                   | skip if bad read
        MOVEQ.L #0x1,D0                         | D0=1 for write
        BSR.B   DOPART                          | DoPart: copy data from user buffer
        JSR     MarkA5Block(PC)                 | mark the block dirty
| WrMain: write entire blocks
WRMAIN:
        MOVE.L  D7,D4                           | number bytes we want
        BEQ.B   FILEWRITE_DONE                  | all done if no more bytes
        ANDI    #-0x200,D4                      | only write whole blocks ($FE00)
        TST.L   D4                              | must want at least 512 bytes
        BEQ.B   WRPART                          | br if not
        JSR     P_mCacheWRIP(PC)                | CacheWrIP: write blocks from user buffer
        BNE.B   FILEWRITE_ERR                   | disk errors ->
        BSR.B   FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        BRA.B   WRMAIN                          | loop
| FWrOK
FILEWRITE_DONE:
        MOVEQ.L #0x0,D0                         | no errors
FILEWRITE_ERR:
        BSR     P_AdjEof                        | AdjEOF: adjust other FCBs for this file
        MOVE.L  D5,0x10(A1,D1.W)                | update current position in FCB (FCBCrPs)
FILEWRITE_EXIT:
        MOVE.L  0x10(A1,D1.W),ioPosOffset(A0)   | always return current pos
FILEWRITE_NO_3:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| FILEWRITE_CONT_2 - UpdteCntPos: update byte count, actual count, and file position
|
| Called during boot.
FILEWRITE_CONT_2:
        SUB.L   D6,D7                           | adjust for number of bytes read/written
        ADD.L   D6,0x28(A0)                     | actually transferred this many more (IOActCount)
        ADD.L   D6,D5                           | update current position
        RTS                                     | return updated counts and position

| ----------------------------------------------------------
|
| DOPART
|
| Called during boot.
| DoPart: copy partial block to/from user buffer
| D0: 0=read, 1=write, $FF=verify-read
DOPART:
        MOVE.L  D5,D2                           | current file position
        ANDI    #0x1FF,D2                       | get index within block
        SUB     D2,D6                           | D6 = bytes remaining in this block
        CMP.L   D6,D7                           | need more than one block's worth?
        BCC.B   FILEWRITE_OK                    | no, D6 is fine
        MOVE.L  D7,D6                           | yes, limit to bytes remaining
FILEWRITE_OK:
        MOVE.L  0x20(A0),A3                     | user buffer (IOBuffer)
        ADDA.L  0x28(A0),A3                     | + IOActCount = target
        BSR.B   FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        MOVEM.L D1/A0-A2,-(SP)                  | save regs
        MOVE.L  A3,A0                           | source = user buffer
        MOVE.L  A5,A1                           | dest = cache buffer
        ADDA    D2,A1                           | + index into block
        TST.B   D0                              | D0 > 0? (write)
        BGT.B   FILEWRITE_OK_2                  | yes, user->cache ->
        BMI.B   FILEWRITE_CONT_3                | D0 < 0? (verify) ->
        EXG     A0,A1                           | read: swap src/dst (cache->user)
FILEWRITE_OK_2:
        MOVE.L  D6,D0                           | byte count
        MOVE.L  (0x4B8).w,A2                    | _BlockMove vector
        JSR     (A2)                            | move the data
FILEWRITE_ERR_2:
        MOVEQ.L #0x0,D0                         | no error
FILEWRITE_EXIT_2:
        MOVEM.L (SP)+,D1/A0-A2                  | restore regs
        RTS                                     | exit DoPart
| verify mode: compare bytes
FILEWRITE_CONT_3:
        MOVEQ.L #-0x24,D0                       | assume IOErr
        SUBQ.W  #0x1,D6                         | loop count - 1
FILEWRITE_LOOP:
        CMPM.B  (A0)+,(A1)+                     | compare bytes
        DBNE    D6,FILEWRITE_LOOP               | loop until mismatch or done
        BNE.B   FILEWRITE_EXIT_2                | mismatch: return IOErr
        BRA.B   FILEWRITE_ERR_2                 | match: return no error

| ----------------------------------------------------------
|
| FILEWRITE_CONT_4
|
| Called during boot.
FILEWRITE_CONT_4:
        MOVE    vcbAllocPtr(A2),D0              | VCB field
        MOVE    vcbVBMSt(A2),D3                 | VCB field
        ADD     D3,D0                           | D0 = AllocPtr + VBMSt
        MOVE    D0,(MaxDB).w                    | set max directory block
        BRA.B   FILEWRITE_NO_4                  | ->

| ----------------------------------------------------------
|
| FILEWRITE_NEXT
|
| Called during boot.
| FILEWRITE_NEXT: read next MFS directory block (advance CkdDB)
FILEWRITE_NEXT:
        MOVE    (CkdDB).w,D3                    | current directory block number
        ADDQ.W  #0x1,D3                         | next block
        CMP     (MaxDB).w,D3                    | past end of directory?
        BCS.B   FILEWRITE_NO_4                  | no ->
        MOVEQ.L #-0x21,D0                       | dirFulErr (-33): directory full
        RTS                                     | return from FILEWRITE_NEXT

| ----------------------------------------------------------
|
| FILEWRITE_NO_4
|
| Called during boot.
| FILEWRITE_NO_4: read MFS directory block D3 into cache
FILEWRITE_NO_4:
        MOVE    D3,(CkdDB).w                    | update current directory block
        BSR     L_MFILEREAD_CONT_6              | read block into cache (A5 = data)
        MOVE.L  (SysCtlCPtr).w,A1               | A1 = system control cache
        BRA.B   FILEWRITE_CONT_7                | ->

| FILEWRITE_NEXT_2 -- read next block.
| ----------------------------------------------------------
|
| FILEWRITE_NEXT_2
|
FILEWRITE_NEXT_2:
        BSR     L_MFILEREAD_CONT_6              | call helper
        BRA.B   FILEWRITE_CONT_6                | ->

| ----------------------------------------------------------
|
| FILEWRITE_CONT_5
|
| FILEWRITE_CONT_5: read MFS directory block D3 into volume cache
FILEWRITE_CONT_5:
        BSR     L_MFILEREAD_CONT_6              | read block D3 into cache
        MOVEQ.L #0x4,D1                         | RBdirty option (release dirty)
FILEWRITE_CONT_6:
        MOVE.L  (SysVolCPtr).w,A1               | system volume cache
FILEWRITE_CONT_7:
        MOVEQ.L #0x0,D2                         | block 0 (for GetBlock)
        MOVE    D3,D2                           | D2 = directory block number
        MOVE    vcbVRefNum(A2),D0               | VCB field
        RTS                                     | return from FILEWRITE_CONT_7

| ----------------------------------------------------------
|
| _FlushFile ($A045)
|
| _FlushFile ($A045)
FlushFile:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST.B    (FlushOnly).w                   | indicate flush only (don't close)
        BRA.B   FILECLOSE_CONT                  | share code with FileClose
| FileClose
FileClose:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        CLR.B   (FlushOnly).w                   | indicate close (not just flush)
FILECLOSE_CONT:
        BSR     P_RFNCall                       | RfNCall: is refnum for a valid open file?
        BEQ.B   FILECLOSE_CONT_2                | br if valid
        CMPI    #-0x35,D0                       | volume offline? (VolOffLinErr)
        BNE.B   FILECLOSE_ERR                   | no, some other error ->
FILECLOSE_CONT_2:
        BSR.B   FILECLOSE_CONT_3                | FClose: do the actual flush/close
FILECLOSE_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| FILECLOSE_CONT_3
|
| Called during boot.
| FClose: do the actual flush/close for TFS files
FILECLOSE_CONT_3:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D3/A0-A5,-(A6)               | save registers
        BSR     TFSVCBTst                       | TFS volume?
        BNE     FILECLOSE_NO_3                  | no, MFS close ->
| check if file has a B-tree open
        TST.L   0x22(A1,D1.W)                   | B-tree BTCB ptr? (FCBBTCBptr)
        BEQ.B   FILECLOSE_NO                    | no ->
        MOVE    D1,D0                           | file refnum
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FILECLOSE_OK                    | yes, just flush ->
        JSR     P_mBTClose(PC)                  | BTClose: close the B-tree
        BRA.B   FILECLOSE_CONT_4                | ->

| ----------------------------------------------------------
|
| FILECLOSE_OK
|
FILECLOSE_OK:
        JSR     P_mBTFlush(PC)                  | call helper
FILECLOSE_CONT_4:
        BNE     FILECLOSE_ERR_4                 | error ->
| FClose TFS path: flush/close a single TFS file
FILECLOSE_NO:
        MOVEQ.L #0x0,D0                         | assume no error
        TST     vcbDrvNum(A2)                   | volume online?
        BEQ     FILECLOSE_SKIP_2                | no (offline), skip flush ->
        CMPI.L  #0x10,0x0(A1,D1.W)              | system file? (CNID < 16)

        BCS     FILECLOSE_SKIP_2                | yes, skip (handled by volume flush) ->
| check if FCB is dirty
        BCLR    #0x7,0x4(A1,D1.W)               | clear FCB dirty bit (FCBModBit)
        BEQ     FILECLOSE_DONE                  | was clean, skip flush ->
| FCB was dirty: check if we should/can flush
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   UPDTECNTPOS                     | yes, skip truncate ->
        BSR     TstMod                          | can we modify this file?
        BNE.B   UPDTECNTPOS                     | no, skip truncate ->
| truncate to clump-rounded PEOF on close
        MOVE.L  0xC(A1,D1.W),D3                 | D3 = current PEOF (FCBPLen)
        BTST    #0x6,0x4(A1,D1.W)               | own clump size? (FCBOwnClp)
        BEQ.B   FILECLOSE_SKIP                  | no, skip rounding ->
        MOVEM.L D0-D1,-(SP)                     | save regs
        MOVE.L  D3,D0                           | D0 = new PEOF in alloc blocks
        MOVE.L  0x1E(A1,D1.W),D1                | get clump size for file (FCBClmpSize)
        BSR     RoundAlloc                      | round up to next clump
        MOVE.L  vcbAlBlkSiz(A2),D1              | allocation block size
        MULU    D1,D0                           | compute new EOF in bytes
        MOVE.L  D0,D3                           | D3 = rounded PEOF
        MOVEM.L (SP)+,D0-D1                     | restore scratch regs
FILECLOSE_SKIP:
        JSR     P_mTruncateFile(PC)             | TruncateFile: truncate to rounded length
        BNE     FILECLOSE_ERR_3                 | error ->
| UpdteCntPos: update catalog record from FCB
UPDTECNTPOS:
        MOVE.L  A1,-(A6)                        | save FCB array ptr
        MOVE.L  0x3A(A1,D1.W),D0                | parent DirID (FCBDirID)
        LEA.L   0x3E(A1,D1.W),A0                | ptr to CName (FCBCName)
        MOVEQ.L #0x0,D2                         | no hint
        JSR     CMGetCN(PC)                     | locate catalog record
        MOVE.L  A1,A5                           | A5 = catalog data record
        MOVE.L  (A6)+,A1                        | restore FCB array ptr
        BNE     FILECLOSE_ERR_3                 | error ->
| copy FCB extent record back to catalog
        MOVEM.L A0-A1,-(SP)                     | save regs
        LEA.L   0x26(A1,D1.W),A0                | source = FCB extent record (FCBExtRec)
        LEA.L   0x4A(A5),A3                     | dest = data fork extents (filExtRec)
        BTST    #0x9,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
        BEQ.B   FILECLOSE_NO_2                  | no ->
        LEA.L   0x56(A5),A3                     | dest = rsrc fork extents (filRExtRec)
FILECLOSE_NO_2:
        MOVE.L  A3,A1                           | dest for _BlockMove
        MOVEQ.L #0xC,D0                         | extent record length (lenXDR)
        _BlockMove                              | copy extent record to catalog
        MOVEM.L (SP)+,A0-A1                     | restore regs
| update file info in catalog record
        LEA.L   0x18(A5),A3                     | ptr to file lengths in catalog
        BSR     FILECLOSE_CONT_6                | UpdFlNtry: update file entry from FCB
        MOVE.L  (Time).w,0x30(A5)               | set modification date (filMdDat)
        JSR     CMUpdateCN(PC)                  | update the catalog record
        BNE.B   FILECLOSE_ERR_3                 | error ->
| if resource fork with LEOF >= 128, update rsrc fork block 0 in volume cache
        BTST    #0x9,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
        BEQ.B   FILECLOSE_DONE                  | no, done ->
        CMPI.L  #0x80,0x8(A1,D1.W)              | LEOF >= 128 bytes? (FCBEOF)

        BCS.B   FILECLOSE_DONE                  | no, skip resource map copy ->
| read resource fork block 0 from volume cache and update it
        MOVEM.L D1/A1,-(A6)                     | save regs
        MOVE.L  A0,A3                           | A3 = catalog key record
        MOVE.L  vcbBufAdr(A2),A1                | volume cache
        MOVE    D1,D0                           | file refnum
        MOVEQ.L #0x0,D1                         | no GetBlock options
        MOVEQ.L #0x0,D2                         | block 0
        JSR     P_mGetBlock(PC)                 | get resource fork block 0
        BNE.B   FILECLOSE_ERR_2                 | error ->
| copy catalog info into resource fork block 0 for Desktop file
        MOVE.L  A0,-(SP)                        | save block ptr
        LEA.L   ioFFlNum(A0),A1                 | dest = first 32 bytes in block
        LEA.L   0x6(A3),A0                      | source = catalog key CName area
        MOVEQ.L #0x20,D0                        | 32 bytes
        _BlockMove                              | copy key info
        MOVEQ.L #0x20,D0                        | 32 bytes just copied
        ADDA.L  D0,A1                           | advance dest by 32
        LEA.L   0x2(A5),A0                      | source = catalog record (past type)
        MOVEQ.L #0x12,D0                        | 18 bytes
        _BlockMove                              | copy file flags/dates
        MOVEQ.L #0x12,D0                        | 18 bytes just copied
        ADDA.L  D0,A1                           | advance dest by 18
        LEA.L   0x38(A5),A0                     | source = extended Finder info
        MOVEQ.L #0x10,D0                        | 16 bytes
        _BlockMove                              | copy Finder info
        MOVEQ.L #0x10,D0                        | 16 bytes just copied
        ADDA.L  D0,A1                           | advance dest by 16
        MOVE.L  0x2C(A5),(A1)+                  | copy filCrDat
        MOVE.L  0x1A(A5),(A1)+                  | copy filLgLen (data fork)
        MOVE.L  0x24(A5),(A1)+                  | copy filRLgLen (rsrc fork)
        MOVE.L  (SP)+,A0                        | restore block ptr
        MOVE.L  vcbBufAdr(A2),A1                | volume cache
        MOVEQ.L #0x4,D1                         | release dirty (RBdirty)
        JSR     P_mRelBlock(PC)                 | release block
FILECLOSE_ERR_2:
        MOVEM.L (A6)+,D1/A1                     | restore regs
FILECLOSE_DONE:
        MOVEQ.L #0x0,D0                         | no error
| FClose exit: flush volume cache for this file
FILECLOSE_ERR_3:
        MOVEM.L D0-D1/A1,-(A6)                  | save regs
        MOVE    D1,D0                           | file refnum
        MOVEQ.L #0x0,D1                         | no FlushCache options
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FILECLOSE_OK_2                  | yes, no trash ->
        MOVEQ.L #0x1,D1                         | FCtrash: trash after flush
FILECLOSE_OK_2:
        MOVE.L  vcbBufAdr(A2),A1                | volume cache
        JSR     P_mFlushCache(PC)               | flush volume cache for this file
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   FILECLOSE_OK_3                  | yes ->
        BSR     CREATE_CONT_7                   | MFS: flush MFS directory
FILECLOSE_OK_3:
        MOVEM.L (A6)+,D0-D1/A1                  | restore saved error code and regs
| if closing (not just flushing), clear the FCB
FILECLOSE_SKIP_2:
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FILECLOSE_ERR_4                 | yes, keep FCB ->
        LEA.L   0x0(A1,D1.W),A3                 | point to FCB entry
        MOVEQ.L #0x2E,D2                        | (FCB length / 2) - 1
FILECLOSE_LOOP:
        CLR     (A3)+                           | clear the FCB
        DBF     D2,FILECLOSE_LOOP               | until all done
FILECLOSE_ERR_4:
        MOVEM.L (A6)+,D1-D3/A0-A5               | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit FClose

| ----------------------------------------------------------
|
| FILECLOSE_NO_3
|
| Called during boot.
| MFS FClose path
FILECLOSE_NO_3:
        BClr    #0x7,0x4(A1,D1.W)               | clear FCB dirty bit (FCBModBit)
        BEQ.B   FILECLOSE_DONE                  | was clean, skip flush ->
| find the file's MFS directory entry
        MOVE    0x1C(A1,D1.W),D3                | start block (FCBStBlk, used as dir hint)
        BSR     FILEWRITE_NO_4                  | read directory block containing this file
        BNE.B   FILECLOSE_ERR_3                 | error ->
        MOVEQ.L #0x0,D0                         | initial entry offset
        MOVE.L  0x0(A1,D1.W),D3                 | file number (FCBFlNm)
FILECLOSE_CONT_5:
        CMP.L   0x12(A5,D0.W),D3                | match file number in directory entry?
        BEQ.B   FILECLOSE_OK_4                  | yes ->
        BSR     CREATE_NEXT                     | next directory entry
        BCS.B   FILECLOSE_CONT_5                | keep scanning
        MOVEQ.L #-0x2B,D0                       | FNFErr: file not in directory
        BRA.B   FILECLOSE_ERR_3                 | ->

| ----------------------------------------------------------
|
| FILECLOSE_OK_4
|
| Called during boot.
| MFS FClose: update directory entry from FCB data
FILECLOSE_OK_4:
        LEA.L   0x16(A5,D0.W),A3                | ptr to fork lengths in MFS entry
        BSR.B   FILECLOSE_CONT_6                | UpdFlNtry: copy FCB lengths to entry
        MOVE.L  (Time).w,0x2E(A5,D0.W)          | set modification date
        JSR     MarkA5Block(PC)                 | mark directory block dirty
        BRA.B   FILECLOSE_DONE                  | ->

| ----------------------------------------------------------
|
| FILECLOSE_CONT_6
|
| Called during boot.
| FILECLOSE_CONT_6/UpdFlNtry: update file lengths in catalog from FCB
| A3 = ptr to file length fields in catalog, (A1,D1) = FCB
FILECLOSE_CONT_6:
        MOVE.L  A4,-(SP)                        | save A4
        LEA.L   0x4(A1,D1.W),A4                 | A4 = FCB flags (FCBMdRByt)
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
|
| _GetEOF ($A011)
|
| Called during boot.
| _GetEOF ($A011)
GetEOF:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   P_RFNCall                       | RfNCall: is refnum for a valid open file?
        BNE.B   GETEOF_NO                       | br if not
        MOVE.L  0x8(A1,D1.W),0x1C(A0)           | return the logical EOF (FCBEOF -> IOLEOF)
GETEOF_NO:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| P_RFN Call
|
| Called during boot.
P_RFNCall:
        MOVE.L  (0x790).w,-(SP)                 | HFS vector: RFNCall
        RTS                                     | return from P_RFNCall

| ----------------------------------------------------------
|
| RFN Call
|
| Called during boot.
| RFNCall: map a reference number to FCB/VCB pointers
RFNCall:
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB array
        MOVEQ.L #0x0,D1                         | clear high word
        MOVE    ioRefNum(A0),D1                 | D1 = file refnum
        BSR.B   CKFILERFN                       | CkFileRfn: validate refnum
        BNE.B   RFNCALL_CONT                    | invalid ->
        MOVE.L  0x0(A1,D1.W),D2                 | D2 = file number (FCBFlNm)
        MOVE.L  0x14(A1,D1.W),A2                | A2 = VCB pointer (FCBVPtr)
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        BSR     FNDFILNAME_CONT_4               | CkExtFS: check for external file system
RFNCALL_CONT:
        TST     D0                              | set condition codes
        RTS                                     | exit RFNCall

| ----------------------------------------------------------
|
| CKFILERFN
|
| Called during boot.
| CkFileRfn: check that refnum points to a valid open file
CKFILERFN:
        MOVEQ.L #-0x33,D0                       | assume refnum error (RFNumErr)
        MOVEQ.L #0x0,D2                         | clear high word
        MOVE    D1,D2                           | check refnum alignment
        DIVU    #0x5E,D2                        | / FCB size
        SWAP    D2                              | get remainder
        SUBQ.W  #0x2,D2                         | remainder must be 2 (offset past FCB header)
        BNE.B   RFNCALL_OK                      | invalid refnum ->
        CMP     (A1),D1                         | past end of FCB array?
        BCC.B   RFNCALL_OK                      | yes, invalid ->
        MOVEQ.L #-0x26,D0                       | assume closed file (FNOpnErr)
        TST.L   0x0(A1,D1.W)                    | FCB in use? (FCBFlNm)
        BEQ.B   RFNCALL_OK                      | no, file not open ->
        MOVEQ.L #0x0,D0                         | valid open file
RFNCALL_OK:
        TST     D0                              | set condition codes
        RTS                                     | exit CkFileRfn

| ----------------------------------------------------------
|
| TstMod: test if we may modify this file
|
| Called during boot.
TstMod:
        BSR.B   P_RFNCall                       | RfNCall: map the reference number
        BNE.B   TSTMOD_EXIT                     | exit on errors
        MOVEQ.L #-0x3D,D0                       | assume wrPermErr
        BTST    #0x0,0x4(A1,D1.W)               | write permission? (FCBWriteBit)
        BEQ.B   TSTMOD_EXIT                     | no, can't modify ->
        BSR     SETVOLINFO_HFS_CONT_3           | check volume write protect
TSTMOD_EXIT:
        TST     D0                              | set condition codes
        RTS                                     | exit TstMod

| ----------------------------------------------------------
|
| Get FCB Info_hfs
|
| _GetFCBInfo (HFS): return info about an open FCB
GetFCBInfo_hfs:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   FNDFCB                          | FndFCB: find the FCB by refnum or index
        BNE.B   GETFCBINFO_HFS_ERR              | error ->
        MOVE    D1,ioRefNum(A0)                 | return the actual refnum
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB entry
| copy first 20 bytes of FCB to param block
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x20(A0),A1                     | dest = ioFCBFlNm area in param block
        MOVE.L  A3,A0                           | source = FCB
        MOVEQ.L #0x14,D0                        | 20 bytes (FCBFlNm through FCBVPtr)
        _BlockMove                              | copy FCB fields
        MOVE.L  (SP)+,A0                        | restore param block
| copy additional FCB fields
        MOVE    vcbVRefNum(A2),0x34(A0)         | ioFCBVRefNum = volume refnum
        MOVE.L  0x1E(A3),0x36(A0)               | ioFCBClpSiz = clump size (FCBClmpSize)
        MOVE.L  fcbDirID(A3),0x3A(A0)           | ioFCBParID = parent DirID (FCBDirID)
| copy FCB CName to caller's buffer
        MOVE.L  ioFileName(A0),D0               | filename buffer pointer
        BEQ.B   GETFCBINFO_HFS_NO               | no buffer ->
        MOVE.L  D0,A1                           | A1 = dest buffer
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x3E(A3),A0                     | source = FCBCName
        MOVEQ.L #0x1,D0                         | include length byte
        ADD.B   (A0),D0                         | + name length
        _BlockMove                              | copy the file name (length byte + characters) to the caller's buffer
        MOVE.L  (SP)+,A0                        | restore param block pointer
| GetFCBInfo exit: set requested volume and check external FS
GETFCBINFO_HFS_NO:
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        MOVE.L  A3,D1                           | D1 = FCB pointer
        BSR     CKExtFS                         | check external FS
GETFCBINFO_HFS_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| FNDFCB
|
| FndFCB: find an FCB by refnum or by index (for GetFCBInfo)
FNDFCB:
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    ioRefNum(A0),D1                 | requested refnum
        MOVE    0x1C(A0),D0                     | ioFCBIndx: index (0 = use refnum)
        BEQ.B   GETFCBINFO_HFS_FOUND            | index=0: use refnum directly ->
| indexed search: find Nth user-open FCB
        MOVEQ.L #0x0,D2                         | D2 = VCB filter (0 = any volume)
        MOVE    ioVRefNum(A0),D2                | filter by volume?
        BEQ.B   GETFCBINFO_HFS_NO_2             | no VRefNum: scan all ->
        MOVE    D2,D0                           | determine volume from VRefNum
        BSR     P_DTRMV1                        | DTRMV1
        BNE.B   GETFCBINFO_HFS_ERR_2            | error ->
        MOVE.L  A2,D2                           | D2 = VCB pointer filter
        MOVE    0x1C(A0),D0                     | restore index
GETFCBINFO_HFS_NO_2:
        BSR     HFSE_CONT_14                    | Gt1stFCB
GETFCBINFO_HFS_CONT:
        MOVE.L  0x0(A1,D1.W),D3                 | file number (FCBFlNm)
        BEQ.B   GETFCBINFO_HFS_SKIP             | FCB empty, skip ->
        MOVE.L  0x14(A1,D1.W),A2                | VCB pointer (FCBVPtr)
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   GETFCBINFO_HFS_OK               | no, MFS file ok ->
        CMPI.L  #0x10,D3                        | system file? (CNID < 16)
        BCS.B   GETFCBINFO_HFS_SKIP             | yes, skip system files ->
GETFCBINFO_HFS_OK:
        TST.L   D2                              | volume filter active?
        BEQ.B   GETFCBINFO_HFS_NO_3             | no ->
        CMP.L   0x14(A1,D1.W),D2                | same volume? (FCBVPtr)
        BNE.B   GETFCBINFO_HFS_SKIP             | no, skip ->
GETFCBINFO_HFS_NO_3:
        SUBQ.W  #0x1,D0                         | decrement index
        BEQ.B   GETFCBINFO_HFS_FOUND            | found the Nth one ->
GETFCBINFO_HFS_SKIP:
        BSR     HFSE_NEXT                       | GtNxtFCB
        BCS.B   GETFCBINFO_HFS_CONT             | more FCBs ->
        MOVEQ.L #-0x26,D0                       | FNOpnErr: no matching FCB found
        BRA.B   GETFCBINFO_HFS_ERR_2            | ->

| ----------------------------------------------------------
|
| GETFCBINFO_HFS_FOUND
|
GETFCBINFO_HFS_FOUND:
        BSR     CKFILERFN                       | call helper
GETFCBINFO_HFS_ERR_2:
        TST     D0                              | test
        RTS                                     | return from GETFCBINFO_HFS_ERR_2

| ----------------------------------------------------------
|
| hfs Un_Lock Range
|
| _LockRng / _UnlockRng (HFS): stub - always succeeds
hfsUn_LockRange:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     P_RFNCall                       | RfNCall: validate refnum
        BNE.B   HFSUN_LOCKRANGE_ERR             | error ->
        MOVEQ.L #0x0,D0                         | no error (range locking not implemented)
HFSUN_LOCKRANGE_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| HFSUN_LOCKRANGE_CONT
|
| HFSUN_LOCKRANGE_CONT/FileAlloc: allocate space for file (MFS/HFS dispatch)
HFSUN_LOCKRANGE_CONT:
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   HFSUN_LOCKRANGE_NO              | no, MFS alloc ->
        BSR     GETFILEINFO_OK_14               | TFSBitTst: check HFS flag
        BEQ     ADJEOF_CONT_4                   | HFS: use Alloc ->
        BRA     ADJEOF_CONT_5                   | MFS path ->

| ----------------------------------------------------------
|
| HFSUN_LOCKRANGE_NO
|
HFSUN_LOCKRANGE_NO:
        MOVEQ.L #0x0,D0                         | noErr
        BRA     LG2PHYS_CONT_2                  | ->

| ----------------------------------------------------------
|
| _Allocate ($A010)
|
| _Allocate ($A010): pre-allocate disk space for a file
Allocate:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     TstMod                          | test if we may modify this file
        BNE.B   ALLOCATE_ERR                    | br if not
        MOVEQ.L #0x0,D6                         | D6 = 0 (bytes allocated so far)
        MOVE.L  0x24(A0),D4                     | D4 = requested bytes (ioReqCount)
        BEQ.B   ALLOCATE_EMPTY                  | zero request ->
        TST     vcbFreeBks(A2)                  | any free blocks?
        BEQ.B   ALLOCATE_EMPTY                  | no, disk full ->
        BSR.B   HFSUN_LOCKRANGE_CONT            | FileAlloc: allocate the space
        BNE.B   ALLOCATE_ERR                    | error ->
ALLOCATE_EMPTY:
        MOVE.L  D6,0x28(A0)                     | return actual bytes allocated (ioActCount)
        BSR     P_AdjEof                        | AdjEOF: adjust other FCBs
        MOVEQ.L #-0x22,D0                       | DskFulErr (in case partial alloc)
        CMP.L   0x24(A0),D6                     | compare
        BCS.B   ALLOCATE_ERR                    | unsigned less ->
        MOVEQ.L #0x0,D0                         | noErr
ALLOCATE_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| _SetEOF ($A012)
|
| Called during boot.
| _SetEOF ($A012)
SetEOF:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     TstMod                          | test if we may modify this file
        BNE.B   SETEOF_EXIT                     | br if not
        MOVE.L  0x1C(A0),D7                     | get requested logical end of file (IOLEOF)
        MOVE.L  D7,D4                           | and copy it
        SUB.L   0xC(A1,D1.W),D4                 | compare with current PEOF (FCBPLen)
        BHI.B   SETEOF_CONT_3                   | it's longer: alloc blks ->
        BCS.B   SETEOF_CONT                     | it's shorter: dealloc blks ->
| SEOFOK: same length or file adjusted
SETEOF_OK:
        BSR     GETFILEINFO_OK_14               | TFSBitTst: was HFS bit set?
        BEQ.B   SETEOF_NO                       | if not, adjust LEOF as requested
        CMP.L   0x8(A1,D1.W),D7                 | is new PEOF < current LEOF? (FCBEOF)
        BCC.B   SETEOF_OK_2                     | if not, current LEOF is still valid
SETEOF_NO:
        MOVE.L  D7,0x8(A1,D1.W)                 | set the new LEOF (FCBEOF)
        CMP.L   0x10(A1,D1.W),D7                | is current position past this? (FCBCrPs)
        BCC.B   SETEOF_OK_2                     | br if not
        MOVE.L  D7,0x10(A1,D1.W)                | if so, pin to this (FCBCrPs)
SETEOF_OK_2:
        BSR     P_AdjEof                        | AdjEOF: adjust any other FCBs for this file
        MOVEQ.L #0x0,D0                         | no error
SETEOF_EXIT:
        BRA     FSQUEUE_DONE                    | CmdDone
| shrtnFil: shorten the file
SETEOF_CONT:
        BSR     GETFILEINFO_OK_15               | TFSVolTst: is it TFS?
        BNE     ADJEOF_NO                       | no, MFS handles it ->
        MOVE.L  D7,D4                           | recover requested LEOF
| truncate the file space beyond the new PEOF
        MOVE.L  D4,D3                           | used to figure new physical length
        ST.B    (FlushOnly).w                   | set "round to extent" to avoid thrashing
        JSR     P_mTruncateFile(PC)             | truncate PEOF to LEOF
        BNE.B   SETEOF_EXIT                     | exit if in trouble
SETEOF_CONT_2:
        MOVEM.L D0-D2,-(A6)                     | save scratch regs
        MOVE    D1,D0                           | file refnum
        MOVE.L  0xC(A1,D1.W),D1                 | new PEOF (FCBPLen)
        MOVEQ.L #-0x1,D2                        | trash to end of file
        JSR     P_mTrashBlocks(PC)              | trash cached blocks beyond new length
        MOVEM.L (A6)+,D0-D2                     | restore scratch regs
        BRA.B   SETEOF_OK                       | go adjust LEOF
| lngthnFil: lengthen the file
SETEOF_CONT_3:
        JSR     ADJEOF_CONT_4(PC)               | Alloc: allocate more space
        BNE.B   SETEOF_EXIT                     | exit if can't allocate
        BRA.B   SETEOF_OK                       | ->

| ----------------------------------------------------------
|
| P_Adj Eof
|
| Called during boot.
P_AdjEof:
        MOVE.L  (0x794).w,-(SP)                 | HFS vector: AdjEof
        RTS                                     | return from P_AdjEof

| ----------------------------------------------------------
|
| Adj Eof
|
| Called during boot.
| AdjEOF: adjust EOF in other open FCBs for this file
| copies LEOF/PEOF from current FCB to all other FCBs with same file number
AdjEof:
        MOVEM.L D0-D6/A0-A5,-(SP)               | save all regs
| extract file info from current FCB
        ADDA    D1,A1                           | point to this FCB
        MOVE.L  (A1)+,D2                        | D2 = file number (FCBFlNm)
        BSET    #0x7,(A1)                       | mark FCB dirty (FCBModBit)
        MOVE    (A1),D0                         | D0 = FCB flags
        MOVEM.L (A1)+,D3-D6/A2                  | D3=flags, D4=StBlk, D5=LEOF, D6=PEOF, A2=CrPs?
        MOVE    D0,D6                           | D6 = FCB flags (for fork type check)
        LEA.L   0xE(A1),A1                      | skip past FCBVPtr area
        MOVEM.L (A1)+,A3-A5                     | A3-A5 = remaining FCB fields
| scan all FCBs for matching file number
        BSR     HFSE_CONT_15                    | Gt1stMatch: find first FCB with same file #
        BNE.B   ADJEOF_FOUND_2                  | no matches ->
ADJEOF_FOUND:
        LEA.L   0x4(A1,D1.W),A0                 | point to this FCB's flags
        MOVE    (A0)+,D0                        | get this FCB's flags
        EOR     D6,D0                           | compare fork type
        LSL     #0x7,D0                         | resource fork bit in carry
        BCS.B   ADJEOF_SKIP                     | different fork type, skip ->
| same fork: update EOF/PEOF from current FCB
        MOVE    D3,(A0)+                        | update StBlk
        MOVE.L  D4,(A0)+                        | update LEOF
        MOVE.L  D5,(A0)+                        | update PEOF
        LEA.L   0x22(A0),A0                     | skip to end of FCB
        MOVEM.L A3-A5,-(A0)                     | update remaining fields
ADJEOF_SKIP:
        BSR     HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
        BEQ.B   ADJEOF_FOUND                    | found one ->
ADJEOF_FOUND_2:
        MOVEM.L (SP)+,D0-D6/A0-A5               | restore regs
        RTS                                     | exit AdjEOF

| ----------------------------------------------------------
|
| ADJEOF_NO
|
| Called during boot.
ADJEOF_NO:
        MOVEQ.L #0x0,D6                         | D6 = 0
| MFS SetEOF shrink: walk chain to truncation point
        MOVE    0x6(A1,D1.W),D3                 | D3 = start alloc block (FCBStBlk)
        MOVE.L  vcbAlBlkSiz(A2),D2              | D2 = alloc block size
        MOVE.L  D7,D4                           | D4 = new LEOF
        BNE.B   ADJEOF_CONT_2                   | nonzero, walk chain ->
        CLR     0x6(A1,D1.W)                    | LEOF=0: clear start block (FCBStBlk)
        BRA.B   ADJEOF_CONT_3                   | go free entire chain ->

| ----------------------------------------------------------
|
| ADJEOF_CONT
|
| Called during boot.
ADJEOF_CONT:
        MOVE    D5,D3                           | D3 = current alloc block number
| MFS SetEOF shrink: walk chain to new PEOF and truncate
ADJEOF_CONT_2:
        ADD.L   D2,D6                           | accumulate PEOF
        BSR     LG2PHYS_NEXT_2                  | get next block in chain
        SUB.L   D2,D4                           | subtract alloc block size from remaining
        BHI.B   ADJEOF_CONT                     | more to walk ->
| reached the new PEOF: truncate the chain
        CMP.L   0xC(A1,D1.W),D6                 | new PEOF >= current PEOF?
        BCC     SETEOF_OK                       | yes, nothing to truncate ->
        MOVE    D5,-(SP)                        | save next block
        MOVEQ.L #0x1,D5                         | mark current block as end-of-chain (1)
        BSR     LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: write end-of-chain to alloc map
        MOVE    (SP)+,D3                        | D3 = first block to free
ADJEOF_CONT_3:
        BSR     LG2PHYS_CONT_10                 | MFSDealloc: free remaining chain
        MOVE.L  D6,0xC(A1,D1.W)                 | update FCBPLen to new PEOF
        MOVE.L  D6,D4                           | D4 = new PEOF (for LEOF adjustment)
        BRA     SETEOF_CONT_2                   | go adjust LEOF ->

| ----------------------------------------------------------
|
| ADJEOF_CONT_4
|
| ADJEOF_CONT_4/Alloc: allocate disk space for file (MFS/HFS dispatch)
ADJEOF_CONT_4:
        BSR     GETFILEINFO_OK_15               | TFSVolTst: is it TFS?
        BNE     LG2PHYS_NO_3                    | no, MFS Alloc ->
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE.L  D3,-(A6)                        | save D3
        MOVEQ.L #0x0,D3                         | D3 = 0
        BRA.B   ADJEOF_CONT_6                   | ->

| ----------------------------------------------------------
|
| ADJEOF_CONT_5
|
ADJEOF_CONT_5:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE.L  D3,-(A6)                        | save D3 on A6 stack
        ST.B    D3                              | Set byte to true
ADJEOF_CONT_6:
        JSR     P_mExtendFile(PC)               | call helper
        MOVE.L  (A6)+,D3                        | restore D3 from A6 stack
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | test
        RTS                                     | return from ADJEOF_CONT_6

| ----------------------------------------------------------
|
| P_m Lg2Phys
|
| Called during boot.
P_mLg2Phys:
        MOVE.L  (0x6FC).w,-(SP)                 | HFS vector: Lg2Phys
        RTS                                     | return from P_mLg2Phys

| ----------------------------------------------------------
|
| Lg2Phys
|
| Called during boot.
Lg2Phys:
        BSR     GETFILEINFO_OK_15               | TFSVCBTst: is it an HFS volume?
        BNE.B   LG2PHYS_NO                      | no, MFS path ->
        JMP     MapFBlock(PC)                   | HFS: use extent-based mapping

| ----------------------------------------------------------
|
| LG2PHYS_NO - MFS Lg2Phys: simple linear extent mapping
|
| Called during boot.
LG2PHYS_NO:
        MOVEM.L D1-D2/D4-D5/D7,-(SP)            | save registers
        MOVE.L  vcbAlBlkSiz(A2),D7              | D7 = allocation block size
        MOVE    0x6(A1,D1.W),D3                 | D3 = start alloc block from FCB
        ADD.L   D5,D4                           | D4 = end position (pos + max bytes - 1)
        SUBQ.L  #0x1,D4                         | adjust to last byte in range
        MOVEQ.L #0x9,D1                         | shift count for /512
        MOVEQ.L #0x0,D6                         | D6 = bytes mapped so far
        LSR.L   D1,D4                           | D4 = end block (in 512-byte blocks)
        LSR.L   D1,D7                           | D7 = alloc block size in 512-byte blocks
        MOVE.L  D5,D2                           | D2 = start block
        LSR.L   D1,D2                           | convert bytes to 512-byte blocks
        BRA.B   LG2PHYS_CONT                    | ->

| ----------------------------------------------------------
|
| LG2PHYS_NEXT
|
| Called during boot (3,127 times in 30s trace).
| walk MFS extent chain
LG2PHYS_NEXT:
        BSR.B   LG2PHYS_NEXT_2                  | get next extent entry
        MOVE    D5,D3                           | D3 = next alloc block start
        SUB     D7,D4                           | adjust end/start for this extent
        SUB     D7,D2                           | blocks remaining in this extent
LG2PHYS_CONT:
        CMP     D7,D2                           | start block within this extent?
        BCC.B   LG2PHYS_NEXT                    | no, try next extent
| found the right extent: compute disk block
        MOVE    D3,D0                           | alloc block start
        SUBQ.W  #0x2,D0                         | - 2 (alloc blocks start at 2)
        MULU    D7,D0                           | * alloc blk size (in 512-byte blocks)
        ADD     D2,D0                           | + offset within alloc block
        ADD     vcbAlBlSt(A2),D0                | + volume alloc block start
        MOVE.L  D0,-(SP)                        | save disk block number
| count contiguous blocks from this extent
LG2PHYS_OK:
        MOVE    D7,D0                           | blocks remaining in this extent
        SUB     D2,D0                           | - offset into extent
        ADD     D0,D6                           | add to contiguous block count
        SUB     D0,D4                           | subtract from remaining request
        BMI.B   LG2PHYS_DONE                    | done if covered all requested blocks
        BSR.B   LG2PHYS_NEXT_2                  | get next extent
        MOVEQ.L #0x0,D2                         | start at beginning of next extent
        ADDQ.W  #0x1,D3                         | check if next extent is contiguous
        CMP     D3,D5                           | (next alloc block == expected?)
        BEQ.B   LG2PHYS_OK                      | yes, keep counting contiguous blocks
| validate result and convert to byte count
LG2PHYS_DONE:
        MOVE.L  (SP)+,D3                        | restore disk block number
        MOVE    D3,D0                           | ending block = start + count
        ADD     D6,D0                           | D0 = start block + block count
        MOVE    vcbAlBlSt(A2),D4                | volume alloc block start
        MULU    vcbNmAlBlks(A2),D7              | total disk blocks = NmAlBlks * blk size
        ADD     D4,D7                           | + alloc start = end of volume
        CMP     D7,D0                           | past end of volume?
        BHI.B   LG2PHYS_ERR                     | yes, error ->
        CMP     D4,D3                           | before alloc start?
        BCS.B   LG2PHYS_ERR                     | yes, error ->
        ASL.L   D1,D6                           | convert block count to byte count (*512)
        MOVEM.L (SP)+,D1-D2/D4-D5/D7            | restore registers
        CMP.L   D4,D6                           | more than requested?
        BLS.B   LG2PHYS_NO_2                    | no ->
        MOVE.L  D4,D6                           | limit to requested amount
LG2PHYS_NO_2:
        MOVEQ.L #0x0,D0                         | success
        RTS                                     | return from Lg2Phys with success
LG2PHYS_ERR:
        MOVEM.L (SP)+,D1-D2/D4-D5/D7            | restore registers
        MOVE    #0x10,D0                        | FNFErr: mapping error
        RTS                                     | return from Lg2Phys with error

| ----------------------------------------------------------
|
| LG2PHYS_NEXT_2
|
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

| ----------------------------------------------------------
|
| LG2PHYS_NO_3 - MFS Alloc: allocate space for file (Alloc entry for MFS)
|
LG2PHYS_NO_3:
        MOVE.L  D4,D0                           | D0 = max bytes to allocate
LG2PHYS_CONT_2:
        MOVEM.L D1-D5/D7/A0-A3,-(SP)            | save regs
        MOVE.L  vcbAlBlkSiz(A2),D7              | alloc block size
        MOVE.L  D7,D6                           | compute free space in bytes
        MULU    vcbFreeBks(A2),D6               | = alloc blk size * free blocks
        CMP.L   D6,D4                           | request > free space?
        BLS.B   LG2PHYS_NO_4                    | no ->
        MOVE.L  D6,D4                           | limit to available space
LG2PHYS_NO_4:
        CMP.L   D0,D4                           | enough space?
        BCC.B   LG2PHYS_OK_2                    | yes ->
        MOVEQ.L #-0x22,D0                       | DskFulErr
LG2PHYS_EXIT:
        MOVEM.L (SP)+,D1-D5/D7/A0-A3            | restore regs
        RTS                                     | exit Alloc with DskFulErr
| MFS Alloc: extend file by allocating blocks from alloc map
LG2PHYS_OK_2:
        MOVE.L  0xC(A1,D1.W),D2                 | D2 = current PEOF (FCBPLen)
        MOVEQ.L #0x0,D6                         | D6 = bytes allocated so far
        MOVE    0x6(A1,D1.W),D3                 | D3 = start alloc block (FCBStBlk)
        BNE.B   LG2PHYS_CONT_3                  | have blocks already ->
| first allocation: get a new start block
        BSR.B   LG2PHYS_NEXT_3                  | find free block
        MOVE    D5,0x6(A1,D1.W)                 | set start block (FCBStBlk)
        MOVE    D5,D3                           | D3 = current alloc block
        MOVEQ.L #0x1,D5                         | D5 = 1
        BSR     LG2PHYS_CONT_9                  | call helper
        BRA.B   LG2PHYS_CONT_5                  | ->

| ----------------------------------------------------------
|
| LG2PHYS_ERR_2
|
LG2PHYS_ERR_2:
        MOVE    D5,D3                           | D3 = next alloc block in chain
LG2PHYS_CONT_3:
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        CMPI    #0x1,D5                         | compare
        BNE.B   LG2PHYS_ERR_2                   | error ->
LG2PHYS_NO_5:
        CMP     vcbNmAlBlks(A2),D3              | compare
        BHI.B   LG2PHYS_OK_3                    | yes ->
        ADDQ.W  #0x1,D3                         | peek at next block
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        SUBQ.W  #0x1,D3                         | restore current block number
| found free block: link it into the chain
        TST     D5                              | next block occupied?
        BNE.B   LG2PHYS_OK_3                    | yes, find another free ->
        MOVE    D3,D5                           | new block = current + 1
        ADDQ.W  #0x1,D5                         | D5 = next sequential block
LG2PHYS_CONT_4:
        BSR     LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: link current -> new block in map
        MOVE    D5,D3                           | D3 = new block (now current)
        MOVEQ.L #0x1,D5                         | mark new block as end-of-chain (1)
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: set new block's map entry
| update counts
LG2PHYS_CONT_5:
        ADD.L   D7,D6                           | add alloc block size to allocated
        ADD.L   D7,D2                           | add to PEOF
        SUBQ.W  #0x1,vcbFreeBks(A2)             | one fewer free block
        CMP.L   D6,D4                           | allocated enough?
        BHI.B   LG2PHYS_NO_5                    | no, allocate more ->
| done: update FCB PEOF
        MOVE.L  D2,0xC(A1,D1.W)                 | update FCBPLen
        BSR     MarkVCB                         | mark VCB dirty
        MOVEQ.L #0x0,D0                         | no error
        BRA.B   LG2PHYS_EXIT                    | exit ->
| next block is occupied: find a free one
LG2PHYS_OK_3:
        BSR.B   LG2PHYS_NEXT_3                  | LG2PHYS_NEXT_3: scan for next free block
        BRA.B   LG2PHYS_CONT_4                  | link it in ->

| ----------------------------------------------------------
|
| LG2PHYS_NEXT_3
|
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
        BCHG    #0x0,D5                         | odd entry? (old bit 0 of D5; flipped for the next entry)
        BNE.B   LG2PHYS_ERR_3                   | odd: its low nibble here + the next byte ->
        MOVE.B  (A1),D1                         | read low nibble byte
        LSR     #0x4,D1                         | shift nibble to low position
        BRA.B   LG2PHYS_CONT_6                  | ->

| ----------------------------------------------------------
|
| LG2PHYS_ERR_3
|
LG2PHYS_ERR_3:
        MOVE.B  (A1)+,D1                        | read low byte of 12-bit entry
        ANDI    #0xFFF,D1                       | mask
| MFS Alloc scan: check if this block is free (entry = 0)
LG2PHYS_CONT_6:
        BNE.B   LG2PHYS_NO_8                    | not free, end of free run ->
        ADD.L   D7,D3                           | extend free run by alloc block size
        CMP.L   D6,D3                           | better than current best?
        BLS.B   LG2PHYS_NO_7                    | no ->
        MOVE.L  D3,D6                           | yes, update best free run length
        MOVE    D2,(SP)                         | save best-fit start block
        CMP.L   D4,D3                           | compare
        BCC.B   LG2PHYS_CONT_8                  | unsigned greater or equal ->
LG2PHYS_NO_7:
        ADDQ.W  #0x1,D0                         | advance to next alloc block
        BRA.B   LG2PHYS_CONT_7                  | ->

| ----------------------------------------------------------
|
| LG2PHYS_NO_8
|
LG2PHYS_NO_8:
        ADDQ.W  #0x1,D0                         | advance past occupied block
        MOVE    D0,D2                           | D2 = new free run start candidate
        MOVEQ.L #0x0,D3                         | D3 = 0: length of the free run so far
LG2PHYS_CONT_7:
        CMP     A3,D0                           | compare
        BLS.B   LG2PHYS_NO_6                    | no ->
LG2PHYS_CONT_8:
        MOVE    (SP)+,D5                        | D5 = best-fit start block
        MOVEM.L (SP)+,D0-D4/D6/A1/A3            | restore regs
        RTS                                     | return from LG2PHYS_CONT_8

| ----------------------------------------------------------
|
| LG2PHYS_CONT_9
|
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

| ----------------------------------------------------------
|
| LG2PHYS_CONT_10
|
| LG2PHYS_CONT_10/MFSDealloc: free an MFS allocation chain starting at block D3
LG2PHYS_CONT_10:
        TST     D3                              | start block = 0?
        BEQ.B   LG2PHYS_CONT_11                 | nothing to free ->
LG2PHYS_NO_9:
        BSR     LG2PHYS_NEXT_2                  | get next block in chain (D5)
        MOVE    D5,-(SP)                        | save next block
        CLR     D5                              | write 0 (free) to map entry
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: write 0 to alloc map
        ADDQ.W  #0x1,vcbFreeBks(A2)             | increment free block count
        MOVE    (SP)+,D3                        | D3 = next block in chain
        CMPI    #0x1,D3                         | end-of-chain marker? (block 1)
        BNE.B   LG2PHYS_NO_9                    | no, keep freeing ->
        BSR     MarkVCB                         | mark VCB dirty
LG2PHYS_CONT_11:
        RTS                                     | exit MFSDealloc

