| File Manager - Block Cache
|
| Caches disk blocks in memory for the B-tree and catalog operations.
| Each cached block is tagged with its volume, file, and block number.
| Dirty blocks are written back on FlushCache or when evicted.
|
| Cache operations (via low-memory vector trampolines):
| GetBlock - read a disk block into cache (or find existing)
| RelBlock - release a cached block
| MarkBlock - mark a cached block as dirty
| FlushCache - write all dirty blocks to disk
| TrashBlocks - invalidate cached blocks for a volume
| InitCache - initialize the block cache
| CacheRDIP/CacheWRIP - cache-through read/write
| RdBlocks/WrBlocks - raw disk block I/O via Device Manager
|
| References:
| Inside Macintosh: Files, Ch 2: "Data Organization on Volumes"
|

| ----------------------------------------------------------
|
| P_m Flush Cache
|
| Called during boot.
P_mFlushCache:
        MOVE.L  (0x700).w,-(SP)                 | HFS vector: FlushCache
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Flush Cache
|
| Called during boot.
FlushCache:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D6/A0-A4,-(A6)               | save registers
        CMPA.L  (SysCtlCPtr).w,A1               | going for the control cache?
        BNE.B   FLUSH_MAIN                      | br if not
        TST.B   (SysCRefCnt).w                  | flushing time?
        BNE.B   FLUSH_MAIN                      | br if so
        MOVEQ.L #0x0,D5                         | zero number of clean blocks
        MOVE.L  A1,A3                           | A3 = ptr(CQH)
        MOVE.L  A3,A4                           | start at top of queue
FLUSH_SCAN_NEXT:
        MOVE.L  (A4),A4                         | position to next buffer
        CMPA.L  A3,A4                           | back to top of queue?
        BEQ.B   FLUSH_CHK_CLEAN                 | br if so
        BTST    #0x5,CBHFlags(A4)               | buffer empty?
        BNE.B   FLUSH_COUNT_CLEAN               | br if so
        BTST    #0x6,CBHFlags(A4)               | buffer in use?
        BNE.B   FLUSH_SCAN_NEXT                 | yes, continue scan ->
        BTST    #0x7,CBHFlags(A4)               | dirty buffer?
        BNE.B   FLUSH_SCAN_NEXT                 | yes, continue scan ->
FLUSH_COUNT_CLEAN:
        ADDQ.W  #0x1,D5                         | bump clean block count
        BRA.B   FLUSH_SCAN_NEXT                 | and continue scan

| ----------------------------------------------------------
|
| FLUSH_CHK_CLEAN - check if more than 25% of control cache buffers are clean
|
| Called during boot.
FLUSH_CHK_CLEAN:
        MOVE    0x8(A3),D6                      | CQHNumBuf: number of buffers in cache
        LSR     #0x2,D6                         | 25% of total buffer count
        CMP     D6,D5                           | more than 25% clean?
        BHI     FLUSH_EXIT_OK                   | exit ok if so (no flush needed)
FLUSH_MAIN:
        MOVE.B  D1,D5                           | D5 = option flags
        MOVE.L  A1,A3                           | A3 = ptr(CQH)
        MOVE    D0,D1                           | D1 = refnum
        BLE.B   FLUSH_ZERO_MATCH                | br if volume flush ->
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB ptr
        MOVE.L  0x14(A1,D1.W),A2                | A2 = VCB ptr
        BSR.B   FLUSH_DIRTY                     | flush any installed buffer
        MOVE.L  0x0(A1,D1.W),D3                 | D3 = file number
        BTST    #0x1,0x4(A1,D1.W)               | resource fork?
        SNE.B   D6                              | $FF=resource fork, $00=data fork
FLUSH_ZERO_MATCH:
        MOVEQ.L #0x0,D4                         | zero last match
FLUSH_RESTART:
        MOVEQ.L #0x0,D2                         | zero current match
        MOVE.L  A3,A4                           | start at top of queue
FLUSH_SEARCH_NEXT:
        MOVE.L  (A4),A4                         | position to next buffer
        CMPA.L  A3,A4                           | back to top of queue?
        BNE.B   FLUSH_CHK_MATCH                 | br if not
        TST.L   D2                              | any match?
        BEQ.B   FLUSH_EXIT_OK                   | exit if not
        MOVE.L  A1,A4                           | pass buffer ptr in A4
        MOVE.L  CBHDBlk(A4),D4                  | save last match disk block
        BRA.B   FLUSH_WRITE_BUF                 | and go flush it

| ----------------------------------------------------------
|
| FLUSH_CHK_MATCH - FlushCache: check if buffer matches flush criteria
|
| Called during boot.
FLUSH_CHK_MATCH:
        BTst    #0x5,CBHFlags(A4)               | buffer empty?
        BNE.B   FLUSH_SEARCH_NEXT               | yes, continue search ->
        CMPA.L  CBHVCBPtr(A4),A2                | same volume?
        BNE.B   FLUSH_SEARCH_NEXT               | no, continue search ->
        TST     D1                              | check type of flush
        BLT.B   FLUSH_VOL_MATCH                 | volume refnum, flush volume ->
        CMP.L   CBHFlNum(A4),D3                 | same file number?
        BNE.B   FLUSH_SEARCH_NEXT               | no, continue search ->
        CMP.B   CBHFkType(A4),D6                | same fork?
        BNE.B   FLUSH_SEARCH_NEXT               | no, continue search ->
FLUSH_VOL_MATCH:
        TST.L   D2                              | any match yet? (ascending order)
        BEQ.B   FLUSH_CHK_ORDER                 | br if not
        CMP.L   CBHDBlk(A4),D2                  | before current match block on disk?
        BLT.B   FLUSH_SEARCH_NEXT               | keep searching if not
FLUSH_CHK_ORDER:
        CMP.L   CBHDBlk(A4),D4                  | after last block we flushed?
        BGE.B   FLUSH_SEARCH_NEXT               | br if not
        MOVE.L  CBHDBlk(A4),D2                  | save low-water mark
        MOVE.L  A4,A1                           | and its buffer ptr
        BRA.B   FLUSH_SEARCH_NEXT               | and keep searching

| ----------------------------------------------------------
|
| FLUSH_WRITE_BUF - FlushCache: flush next matching buffer in disk order
|
| Called during boot.
FLUSH_WRITE_BUF:
        BTst    #0x7,CBHFlags(A4)               | buffer dirty?
        BEQ.B   FLUSH_CHK_TRASH                 | no ->
        JSR     WriteBlock(PC)                  | write it on disk
        BCLR    #0x7,CBHFlags(A4)               | set not dirty
FLUSH_CHK_TRASH:
        BTst    #0x0,D5                         | trash option requested?
        BEQ.B   FLUSH_RESTART                   | no, keep it around ->
        BTST    #0x6,CBHFlags(A4)               | buffer in use?
        BNE.B   FLUSH_RESTART                   | yes, keep it around ->
        BSR     MarkEmpty                       | set it to empty
        BRA.B   FLUSH_RESTART                   | and keep searching

| ----------------------------------------------------------
|
| FLUSH_EXIT_OK - FlushCache exit: no error
|
| Called during boot.
FLUSH_EXIT_OK:
        CLR     D0                              | result = ok
        MOVEM.L (A6)+,D1-D6/A0-A4               | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set result code
        RTS                                     | back to caller

| ----------------------------------------------------------
|
| P_m Get Block
|
| Called during boot.
P_mGetBlock:
        MOVE.L  (0x704).w,-(SP)                 | HFS vector: GetBlock
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Get Block
|
| Called during boot.
GetBlock:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D7/A1-A5,-(A6)               | save regs
        MOVE.B  D1,D3                           | D3 = option flags
        MOVE.L  A1,A3                           | A3 = ptr(CQH)
        MOVE    D0,D1                           | D1 = volume or file refnum?
        BLT     GB_VOL_REF                      | volume ->
        MOVE.L  (FCBSPtr).w,A1                  | A1 = ptr(1st FCB)
        MOVE.L  0x14(A1,D1.W),A2                | A2 = ptr(VCB)
        MOVE.L  0x0(A1,D1.W),D7                 | D7 = file number
        BTST    #0x1,0x4(A1,D1.W)               | resource fork?
        SNE.B   D4                              | yes, indicate resource fork
        MOVE.L  A3,A4                           | start at top of queue
GB_FILE_SEARCH:
        MOVE.L  (A4),A4                         | position to next buffer
        CMPA.L  A3,A4                           | back to top of queue?
        BEQ.B   GB_CHK_OWNBUF                   | yes ->
        BTST    #0x5,CBHFlags(A4)               | buffer empty?
        BNE.B   GB_FILE_SEARCH                  | yes, continue search ->
        CMPA.L  CBHVCBPtr(A4),A2                | same volume?
        BNE.B   GB_FILE_SEARCH                  | no, continue search ->
        CMP.L   CBHFlNum(A4),D7                 | same file number?
        BNE.B   GB_FILE_SEARCH                  | no, continue search ->
        CMP.B   CBHFkType(A4),D4                | same fork?
        BNE.B   GB_FILE_SEARCH                  | no, continue search ->
        CMP.L   CBHFlBlk(A4),D2                 | same file block?
        BEQ     GB_FOUND_IT                     | yes, found it ->
        BRA.B   GB_FILE_SEARCH                  | continue search

| ----------------------------------------------------------
|
| GB_CHK_OWNBUF - GetBlock: file block not in cache, check OwnBuf
|
| Called during boot.
GB_CHK_OWNBUF:
        BSR     Cache                           | local buffer?
        BEQ.B   GB_MAP_BLOCK                    | give up search if not
        BTST    #0x5,CBHFlags(A4)               | buffer empty?
        BNE.B   GB_MAP_BLOCK                    | give up search if so
        CMP.L   CBHFlBlk(A4),D2                 | same file block?
        BEQ     GB_EXIT_OK                      | exit successfully if so
GB_MAP_BLOCK:
        MOVEM.L D3-D4,-(A6)                     | save option flags and fork type
        MOVEQ.L #0x0,D4                         | cache buffer size
        MOVE    0xA(A3),D4                      | (from CQH)
        MOVE.L  D2,D5                           | file block number
        LSL.L   #0x8,D5                         | file block number x 512
        ADD.L   D5,D5                           | = file position
        JSR     P_mLg2Phys(PC)                  | map to logical block (Lg2Phys)
        MOVE.L  D2,D6                           | D6 = file block number
        MOVE.L  D3,D2                           | D2 = logical block number
        MOVEM.L (A6)+,D3-D4                     | restore option flags and fork type
        TST     D0                              | any mapping errors?
        BNE     GB_EXIT                         | exit if we were unable to map block
        MOVE.L  0x18(A1,D1.W),D0                | local buffer?
        BEQ.B   GB_CACHE_SEARCH                 | search for cache block if not
        BSR     FLUSH_DIRTY                     | make sure it's clean (sets up A4)
        MOVE.L  D2,CBHDBlk(A4)                  | store logical disk block in CBH
        MOVE.L  D6,CBHFlBlk(A4)                 | store file block in CBH
        CLR.B   CBHFlags(A4)                    | clear all bits (not empty, not dirty)
        JSR     ReadOwnBuf(PC)                  | read the block
        BEQ     GB_EXIT_OK                      | exit if successful
        BSR     MarkEmpty                       | mark it empty
        BRA     GB_EXIT                         | exit with error

| ----------------------------------------------------------
|
| GB_VOL_REF - GetBlock: logical block on volume was requested (GBVolRef)
|
| Called during boot.
GB_VOL_REF:
        MOVEQ.L #0x0,D1                         | indicate no given file refnum
        MOVEQ.L #0x0,D7                         | no file number
        MOVEQ.L #-0x1,D6                        | no file block number
        MOVEQ.L #0x0,D4                         | no fork type
GB_CACHE_SEARCH:
        SUBA.L  A0,A0                           | initialize ptr to empty buffer
        SUBA.L  A1,A1                           | ptr to clean buffer
        SUBA.L  A5,A5                           | ptr to dirty buffer
        MOVE.L  A3,A4                           | start at top of queue
GB_SCAN_NEXT:
        MOVE.L  (A4),A4                         | position to next buffer
        CMPA.L  A3,A4                           | back to top of queue?
        BEQ.B   GB_SELECT                       | yes ->
        BTST    #0x5,CBHFlags(A4)               | empty buffer?
        BEQ.B   GB_CHK_NONEMPTY                 | no ->
        MOVE.L  A4,A0                           | yes, save ptr to empty buffer
        BRA.B   GB_SCAN_NEXT                    | continue search ->

| ----------------------------------------------------------
|
| GB_CHK_NONEMPTY - GetBlock: non-empty buffer, check if it's the one we want
|
| Called during boot.
GB_CHK_NONEMPTY:
        TST     D1                              | searching by file?
        BNE.B   GB_CHK_INUSE                    | br if so (shouldn't be found here)
        CMPA.L  CBHVCBPtr(A4),A2                | same volume?
        BNE.B   GB_CHK_INUSE                    | no ->
        CMP.L   CBHDBlk(A4),D2                  | same disk block?
        BEQ     GB_FOUND_IT                     | yes, found it ->
GB_CHK_INUSE:
        BTst    #0x6,CBHFlags(A4)               | buffer in use?
        BNE.B   GB_SCAN_NEXT                    | yes, continue search ->
        BTST    #0x7,CBHFlags(A4)               | dirty buffer?
        BEQ.B   GB_SAVE_CLEAN                   | no ->
        MOVE.L  A4,A5                           | yes, save ptr to dirty buffer
        BRA.B   GB_SCAN_NEXT                    | continue search

| ----------------------------------------------------------
|
| GB_SAVE_CLEAN - GetBlock: found a clean (not dirty) non-in-use buffer
|
| Called during boot.
GB_SAVE_CLEAN:
        MOVE.L  A4,A1                           | save ptr to clean buffer
        BRA.B   GB_SCAN_NEXT                    | continue search

| ----------------------------------------------------------
|
| GB_SELECT - GetBlock: block not found, select a buffer to use (GBSelect)
|
| Called during boot.
GB_SELECT:
        BTst    #0x1,D3                         | request for an existing block? (GBexist)
        BEQ.B   GB_PICK_BUFFER                  | no ->
        MOVEQ.L #0x3,D0                         | result = 'not found' (ChNotFound)
        BRA     GB_EXIT                         | exit ->

| ----------------------------------------------------------
|
| GB_PICK_BUFFER - GetBlock: select best available buffer (empty > clean > dirty)
|
| Called during boot.
GB_PICK_BUFFER:
        MOVE.L  A0,A4                           | do we have an empty one?
        MOVE.L  A4,D0                           | test if ptr is non-null
        BNE.B   GB_ASSIGN                       | yes, use it ->
        MOVE.L  A1,A4                           | do we have a clean one?
        MOVE.L  A4,D0                           | test if ptr is non-null
        BNE.B   GB_ASSIGN                       | yes, use it ->
        MOVE.L  A5,A4                           | do we have a dirty one?
        MOVE.L  A4,D0                           | test if ptr is non-null
        BNE.B   GB_EVICT_DIRTY                  | yes, write it first ->
        MOVEQ.L #0x1,D0                         | result = 'all buffers in use' (ChNoBuf)
        BRA     GB_EXIT                         | exit ->

| ----------------------------------------------------------
|
| GB_EVICT_DIRTY - GetBlock: must evict dirty buffer (flush all blocks of same file first)
|
GB_EVICT_DIRTY:
        MOVEM.L D0-D2/A1-A2,-(A6)               | save regs over flush call
        MOVE.B  (SysCRefCnt).w,D2               | save CacheFlag value
        ST.B    (SysCRefCnt).w                  | set for real flush (force it)
        MOVEQ.L #0x0,D1                         | regular flush options
        MOVE.L  A3,A1                           | cache queue header
        MOVE.L  CBHVCBPtr(A4),A2                | VCB ptr for this dirty block
        MOVE    CBHFRefNum(A4),D0               | file refnum for this dirty block
        BGT.B   GB_FLUSH_VREF                   | br if it's a file block
        MOVE    vcbVRefNum(A2),D0               | otherwise pass the VRefnum
GB_FLUSH_VREF:
        JSR     P_mFlushCache(PC)               | should flush it out...
        MOVE.B  D2,(SysCRefCnt).w               | restore cache flag
        MOVEM.L (A6)+,D0-D2/A1-A2               | restore registers
        CMPA.L  (SysCtlCPtr).w,A3               | going for the control cache?
        BNE.B   GB_ASSIGN                       | br if not
        ST.B    (SysCRefCnt).w                  | better start flushing: we're full
| GBAssign: assign buffer to new block, read it from disk
GB_ASSIGN:
        BSet    #0x6,CBHFlags(A4)               | set in use
        BCLR    #0x5,CBHFlags(A4)               | not empty
        BCLR    #0x7,CBHFlags(A4)               | and not dirty
        MOVE.L  A2,CBHVCBPtr(A4)                | new volume ptr
        MOVE.L  D2,CBHDBlk(A4)                  | disk block number
        MOVE    D1,CBHFRefNum(A4)               | file refnum
        MOVE.L  D7,CBHFlNum(A4)                 | file number
        MOVE.B  D4,CBHFkType(A4)                | fork type
        MOVE.L  D6,CBHFlBlk(A4)                 | and file block number
        BTST    #0x2,D3                         | no-read requested? (GBnoRead)
        BNE.B   GB_REQUEUE                      | yes, skip read ->
| GBReadBlk: read block from disk into cache buffer
GB_READ_BLK:
        CLR.L   (BufTgDate).w                   | always clear tag date
        JSR     ReadOwnBuf(PC)                  | read node from disk
        BNE.B   GB_READ_ERR                     | exit on errors
| scavenge VCB write count from tag data whenever we read a block
        JSR     TFSVCBTst(PC)                   | TFS (HFS) volume?
        BNE.B   GB_REQUEUE                      | skip write-count scavenge if not
        MOVE.L  (BufTgDate).w,D0                | get tag write-count
        CMP.L   vcbWrCnt(A2),D0                 | make sure it's <= VCB write count
        BLS.B   GB_REQUEUE                      | br if so
        MOVE.L  D0,vcbWrCnt(A2)                 | update VCB write count if not...
        BRA.B   GB_REQUEUE                      | go re-queue the buffer ->

| ----------------------------------------------------------
|
| GB_READ_ERR - GetBlock: read error, mark buffer empty
|
GB_READ_ERR:
        CLR.B   CBHFlags(A4)                    | not in use or dirty
        BSR     MarkEmpty                       | mark it empty
        BRA.B   GB_EXIT                         | read error ->

| ----------------------------------------------------------
|
| GB_FOUND_IT - GetBlock: found requested buffer (GBFoundIt)
|
| Called during boot.
GB_FOUND_IT:
        BSet    #0x6,CBHFlags(A4)               | buffer in use?
        BEQ.B   GB_CHK_REREAD                   | no ->
        MOVEQ.L #0x2,D0                         | error, buffer in use (ChInUse)
        BRA.B   GB_EXIT                         | exit ->

| ----------------------------------------------------------
|
| GB_CHK_REREAD - GetBlock: check for forced re-read (GBread flag)
|
| Called during boot.
GB_CHK_REREAD:
        BTst    #0x0,D3                         | forced read requested? (GBread)
        BNE.B   GB_READ_BLK                     | yes, read it ->
| GBReQueue: re-queue buffer for LRU
GB_REQUEUE:
        JSR     DQCBuf(PC)                      | DQCBuf: detach buffer from queue
        MOVE.L  A3,A0                           | put on top
        JSR     NQCBuf(PC)                      | NQCBuf: insert at MRU position
        BTST    #0x3,D3                         | immediate release requested? (GBrelease)
        BEQ.B   GB_EXIT_OK                      | br if not
        BCLR    #0x6,CBHFlags(A4)               | set not in-use
GB_EXIT_OK:
        LEA.L   CBHData(A4),A0                  | A0 = addr(cache buffer data)
        MOVEQ.L #0x0,D0                         | result = ok
| Called by: GB_MAP_BLOCK, GB_SELECT, GB_PICK_BUFFER, GB_READ_ERR, GB_FOUND_IT
GB_EXIT:
        MOVEM.L (A6)+,D1-D7/A1-A5               | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set result code
        RTS                                     | back to caller

| ----------------------------------------------------------
|
| Init Cache
|
| Called during boot.
InitCache:
        MOVE.L  (SP)+,-(A6)                     | save return addr on A6 stack
        MOVEM.L D1-D3/A0/A4,-(A6)               | save regs
| allocate memory for cache queue
        MOVE    D0,D2                           | D2 = # of buffers
        MOVE    D1,D3                           | D3 = buffer size
        ADDI    #0x1C,D1                        | D1 = size of buffer + buffer header (lenCBH=28)
        MOVEQ.L #0x0,D0                         | calculate total size
        MOVE    D2,D0                           | D0 = number of buffers
        MULU    D1,D0                           | for all buffers
        ADDI.L  #0xC,D0                         | + queue header (lenCQH=12)
        _NewPtrSysClear                         | allocate the memory
        BNE.B   INITC_EXIT                      | couldn't get it ->
        MOVE.L  A0,A1                           | A1 = ptr(CQH)
| initialize the cache queue
        MOVE.L  A1,(A1)                         | initialize queue FLink to self
        MOVE.L  A1,0x4(A1)                      | BLink to self (empty circular list)
        MOVE    D2,0x8(A1)                      | CQHNumBuf: set number of buffers
        MOVE    D3,0xA(A1)                      | CQHBufSize: set buffer size
        LEA.L   0xC(A1),A4                      | A4 = addr(1st buffer)
        SUBQ.W  #0x1,D2                         | D2 = # of buffers - 1 (for DBRA)
INITC_LOOP:
        MOVE.L  A1,A0                           | attach buffer
        JSR     NQCBuf(PC)                      | NQCBuf: insert at end of queue
        BSR.B   MarkEmpty                       | MarkEmpty: mark buffer empty
        ADDA.L  D1,A4                           | bump to next buffer
        DBF     D2,INITC_LOOP                   | init next buffer
        CLR     D0                              | result = 'ok'
INITC_EXIT:
        MOVEM.L (A6)+,D1-D3/A0/A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set up condition codes
        RTS                                     | exit InitCache

| ----------------------------------------------------------
|
| MarkEmpty - MarkEmpty: mark buffer empty and zero disk block
|
| Called during boot.
MarkEmpty:
        BSET    #0x5,CBHFlags(A4)               | mark buffer empty (CBHempty)
        CLR.L   CBHDBlk(A4)                     | zero disk block for empty buffers
        RTS                                     | return from MarkEmpty

| ----------------------------------------------------------
|
| P_m Mark Block
|
| Called during boot.
P_mMarkBlock:
        MOVE.L  (0x708).w,-(SP)                 | HFS vector: MarkBlock
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Mark Block
|
| Called during boot.
MarkBlock:
        BSET    #0x7,-0x2(A0)                   | A0 points to CBHData; CBHFlags is at A0-2: set dirty bit
        RTS                                     | Return

| ----------------------------------------------------------
|
| Mark A5Block
|
| Called during boot.
MarkA5Block:
        EXG     A0,A5                           | Swap A0 and A5 (A5 has the data ptr)
        BSR.B   P_mMarkBlock                    | Call MarkBlock via HFS vector
        EXG     A0,A5                           | Swap back (restore A0 and A5)
        RTS                                     | Return

| ----------------------------------------------------------
|
| P_m Rel Block
|
| Called during boot.
P_mRelBlock:
        MOVE.L  (0x70C).w,-(SP)                 | HFS vector: RelBlock
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Rel Block
|
| Called during boot.
RelBlock:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A0-A1/A3-A4,-(A6)            | save registers
        LEA.L   -0x1C(A0),A4                    | A4 = ptr to CBH (back up lenCBH from data ptr)
        BCLR    #0x6,CBHFlags(A4)               | set not in-use
        BTST    #0x1,D1                         | buffer to be trashed? (RBtrash)
        BEQ.B   RB_CHK_DIRTY                    | no ->
        BSR.B   MarkEmpty                       | mark it empty
        BCLR    #0x7,CBHFlags(A4)               | and not dirty
        BRA.B   RB_EXIT_OK                      | all done ->

| ----------------------------------------------------------
|
| RB_CHK_DIRTY - RelBlock: check dirty/write options
|
RB_CHK_DIRTY:
        BTst    #0x2,D1                         | buffer dirty? (RBdirty)
        BEQ.B   RB_CHK_WRITE                    | no ->
        BSET    #0x7,CBHFlags(A4)               | set dirty flag
RB_CHK_WRITE:
        BTst    #0x0,D1                         | RBwrite: force immediate write to disk?
        BEQ.B   RB_EXIT_OK                      | no ->
        MOVE.L  A1,A3                           | A3 = CQH (needed by WriteBlock)
        JSR     WriteBlock(PC)                  | write block to disk
        BCLR    #0x7,CBHFlags(A4)               | set cache buffer not dirty
        BRA.B   RB_EXIT                         | all done ->
| RBExit
RB_EXIT_OK:
        CLR     D0                              | indicate no error
RB_EXIT:
        MOVEM.L (A6)+,D1/A0-A1/A3-A4            | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set up condition codes
        RTS                                     | exit RelBlock

| P_mTrashVBlks -- trash bitmap blocks for this volume.
| ----------------------------------------------------------
|
| P_m Trash V Blks
|
P_mTrashVBlks:
        MOVE.L  (0x714).w,-(SP)                 | HFS vector: TrashVBlks
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Trash V Blks
|
TrashVBlks:
        MOVEM.L A3-A4,-(SP)                     | Save regs
        MOVE.L  A1,A3                           | A3 = cache queue header
        MOVE.L  A3,A4                           | A4 = start traversal from header
TV_SCAN_NEXT:
        MOVE.L  (A4),A4                         | A4 = next entry
        CMPA.L  A3,A4                           | Wrapped around?
        BEQ.B   TV_EXIT                         | Yes: done
        BTST    #0x5,CBHFlags(A4)               | CBHempty? Already empty, skip
        BNE.B   TV_SCAN_NEXT                    | Empty: skip
        CMPA.L  CBHVCBPtr(A4),A2                | Same VCB as volume being unmounted?
        BNE.B   TV_SCAN_NEXT                    | Different volume: skip
        BSR     MarkEmpty                       | Invalidate: mark entry empty, clear disk block
        BRA.B   TV_SCAN_NEXT                    | Continue scanning

| ----------------------------------------------------------
|
| TV_EXIT
|
TV_EXIT:
        MOVEM.L (SP)+,A3-A4                     | Restore registers
        RTS                                     | Return

| TrashFBlocks -- trash cached blocks for this file.
| ----------------------------------------------------------
|
| Trash F Blocks
|
TrashFBlocks:
        MOVEM.L D0-D6/A0-A4,-(SP)               | Save all working registers
        MOVE.L  D0,D3                           | D3 = extent info (for block range calculation)
        MOVEQ.L #0x0,D1                         | D1 = 0 (process all matching blocks)
        BRA.B   L_TrashBlocks                   | Fall through to TrashBlocks

| P_mTrashBlocks -- trash cached blocks in the written range (now stale).
| ----------------------------------------------------------
|
| P_m Trash Blocks
|
P_mTrashBlocks:
        MOVEM.L D0-D6/A0-A4,-(SP)               | Save all working registers
        MOVEQ.L #0x9,D3                         | D3 = 9 (shift for 512-byte blocks: >>9 = /512)
        MOVE.L  D1,D4                           | D4 = start byte offset of range to trash
        LSR.L   D3,D4                           | D4 >>= 9: convert byte offset to block number
        MOVEQ.L #-0x1,D5                        | D5 = -1 (sentinel)
        CMP.L   D2,D5                           | D2 = -1? (unlimited range)
        BEQ.B   TB_CVT_END_BLK                  | Yes: trash all blocks from start
        MOVE.L  D2,D5                           | D5 = end byte offset
        ADD.L   D1,D5                           | D5 = start + count
        SUBQ.L  #0x1,D5                         | D5 -= 1 (last byte in range)
TB_CVT_END_BLK:
        LSR.L   D3,D5                           | D5 >>= 9: convert end byte to block number
        MOVE    D0,D1                           | D1 = file refnum from D0
        BLE.B   TB_EXIT                         | D1 <= 0: skip FCB lookup
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB array base
        MOVE.L  0x14(A1,D1.W),A2                | A2 = VCB from FCB
        MOVE.L  0x0(A1,D1.W),D3                 | D3 = file number from FCB
        BTST    #0x1,0x4(A1,D1.W)               | Test resource fork bit
        SNE.B   D6                              | D6 = fork type flag
        BSR     Cache                           | Search volume cache for this file
        BEQ.B   L_TrashBlocks                   | Not found: fall through to TrashBlocks
        BTST    #0x5,CBHFlags(A4)               | CBHempty?
        BNE.B   L_TrashBlocks                   | Empty: fall through
        MOVE.L  CBHFlBlk(A4),D0                 | D0 = file block number of cached entry
        CMP.L   D4,D0                           | Block < range start? (before trash range)
        BLT.B   L_TrashBlocks                   | Yes: don't trash (before range)
        CMP.L   D5,D0                           | Block > range end? (after trash range)
        BGT.B   L_TrashBlocks                   | Yes: don't trash (after range)
        BSR     MarkEmpty                       | Block in range: invalidate this cache entry
L_TrashBlocks:
        MOVE.L  (0x710).w,-(SP)                 | HFS vector: TrashBlocks
        RTS                                     | Return (via trampoline)

| ----------------------------------------------------------
|
| Trash Blocks
|
TrashBlocks:
        MOVE.L  vcbBufAdr(A2),A3                | A3 = volume buffer cache (from VCB)
        MOVE.L  A3,A4                           | A4 = start from header
TB_SCAN_NEXT:
        MOVE.L  (A4),A4                         | A4 = next entry in volume cache chain
        CMPA.L  A3,A4                           | Wrapped around?
        BEQ.B   TB_EXIT                         | Yes: done
        BTST    #0x5,CBHFlags(A4)               | CBHempty? Skip already-empty entries
        BNE.B   TB_SCAN_NEXT                    | Empty: skip
        CMPA.L  CBHVCBPtr(A4),A2                | Same VCB?
        BNE.B   TB_SCAN_NEXT                    | Different volume: skip
        CMP.L   CBHFlNum(A4),D3                 | Same file number (CNID)?
        BNE.B   TB_SCAN_NEXT                    | Different file: skip
        TST     D1                              | D1=0? (trash all forks of this file)
        BEQ.B   TB_INVALIDATE                   | D1=0: trash without further checks
        CMP.B   CBHFkType(A4),D6                | Same fork type?
        BNE.B   TB_SCAN_NEXT                    | Different fork: skip
        MOVE.L  CBHFlBlk(A4),D0                 | D0 = file block of this entry
        CMP.L   D4,D0                           | Block < start of trash range?
        BLT.B   TB_SCAN_NEXT                    | Before range: skip
        CMP.L   D5,D0                           | Block > end of trash range?
        BGT.B   TB_SCAN_NEXT                    | After range: skip
TB_INVALIDATE:
        BSR     MarkEmpty                       | Invalidate: mark empty, clear disk block
        BRA.B   TB_SCAN_NEXT                    | Continue scanning

| ----------------------------------------------------------
|
| TB_EXIT
|
TB_EXIT:
        MOVEM.L (SP)+,D0-D6/A0-A4               | Restore registers
        RTS                                     | Return from TrashBlocks

| ----------------------------------------------------------
|
| P_m Cache RDIP
|
| Called during boot.
P_mCacheRDIP:
        MOVE.L  (0x71C).w,-(SP)                 | HFS vector: CacheRDIP
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Cache RDIP
|
| Called during boot.
CacheRDIP:
        MOVE.L  (SP)+,-(A6)                     | Save return addr
        MOVE.L  D3,-(A6)                        | Save D3
        MOVEM.L D1/A1,-(A6)                     | Save D1/A1
        MOVE    D1,D0                           | D0 = file refnum (for FlushCache)
        MOVEQ.L #0x0,D1                         | D1 = 0: flush ALL dirty blocks of this file first
        MOVE.L  vcbBufAdr(A2),A1                | A1 = volume buffer cache queue
        BSR     P_mFlushCache                   | Flush file's dirty blocks before direct read (avoid stale data)
        MOVEM.L (A6)+,D1/A1                     | Restore D1/A1
        BNE.B   RDIP_DONE                       | Flush error? Return error
        JSR     P_mLg2Phys(PC)                  | Map file offset to physical disk block via Lg2Phys
        BNE.B   RDIP_DONE                       | Mapping error? Return error
        JSR     P_mRdBlocks(PC)                 | Read block directly from disk (bypasses cache entirely)
RDIP_DONE:
        BRA.B   CACHEWRIP_EXIT                  | Fall through to common exit

| P_mCacheWRIP -- cacheWrIP: write blocks from user buffer.
| ----------------------------------------------------------
|
| P_m Cache WRIP
|
P_mCacheWRIP:
        MOVE.L  (0x718).w,-(SP)                 | HFS vector: CacheWRIP
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Cache WRIP
|
CacheWRIP:
        MOVE.L  (SP)+,-(A6)                     | Save return address
        MOVE.L  D3,-(A6)                        | Save D3
        JSR     P_mLg2Phys(PC)                  | Map file offset to physical disk block
        BNE.B   CACHEWRIP_EXIT                  | Mapping error? Return error
        MOVEM.L D1-D2,-(A6)                     | Save D1-D2 for TrashBlocks
        MOVE    D1,D0                           | D0 = file refnum
        MOVE.L  D5,D1                           | D1 = byte offset (start of written range)
        MOVE.L  D6,D2                           | D2 = byte count (length of written range)
        BSR     P_mTrashBlocks                  | Trash cached blocks in the written range (now stale)
        MOVEM.L (A6)+,D1-D2                     | Restore D1-D2
        JSR     P_mWrBlocks(PC)                 | Write data directly to disk (bypasses cache)
CACHEWRIP_EXIT:
        MOVE.L  (A6)+,D3                        | Restore D3
        MOVE.L  (A6)+,-(SP)                     | Restore return address
        TST     D0                              | Set Z flag
        RTS                                     | Return

| ----------------------------------------------------------
|
| DQCBuf - DQCBuf: dequeue cache buffer from circular list
|
| Called during boot.
DQCBuf:
        MOVEM.L A0-A1,-(SP)                     | save regs
        MOVE.L  CBHBlink(A4),A0                 | addr of previous Q element
        MOVE.L  (A4),A1                         | addr of next Q element
        MOVE.L  A1,(A0)                         | link to next element
        MOVE.L  A0,0x4(A1)                      | link to previous element
        MOVEM.L (SP)+,A0-A1                     | restore regs
        RTS                                     | exit DQCBuf

| ----------------------------------------------------------
|
| NQCBuf - NQCBuf: enqueue cache buffer after A0 in circular list
|
| Called during boot.
NQCBuf:
        MOVE.L  A1,-(SP)                        | save reg
        MOVE.L  (A0),A1                         | addr of next Q element
        MOVE.L  A1,(A4)                         | link to next element
        MOVE.L  A4,0x4(A1)                      | back-link next to new entry
        MOVE.L  A4,(A0)                         | link to previous element
        MOVE.L  A0,CBHBlink(A4)                 | back-link new entry to A0
        MOVE.L  (SP)+,A1                        | restore reg
        RTS                                     | exit NQCBuf

| ----------------------------------------------------------
|
| Read Own Buf
|
| Called during boot.
ReadOwnBuf:
        MOVE.L  (SP)+,-(A6)                     | Save return address
        MOVEM.L D1-D7/A0-A5,-(A6)               | Save all working registers
        MOVEQ.L #0x0,D1                         | D1 = 0 (read operation flag for BasicIO)
        BRA.B   BASICIO_SETUP                   | Jump to common I/O path

| WriteOwnBuf -- call.
| ----------------------------------------------------------
|
| Write Own Buf
|
WriteOwnBuf:
        MOVE.L  (SP)+,-(A6)                     | Save return address
        MOVEM.L D1-D7/A0-A5,-(A6)               | Save all working registers
        BRA.B   WBLK_SETUP_TAGS                 | Jump to write setup

| ----------------------------------------------------------
|
| Write Block
|
| Called during boot.
WriteBlock:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D7/A0-A5,-(A6)               | save regs on HFS stack
        MOVE.L  CBHVCBPtr(A4),A2                | A2 = VCB ptr from cache buffer header
        MOVE.L  CBHDBlk(A4),D0                  | D0 = disk block (pass if not a file block)
        MOVE    CBHFRefNum(A4),D1               | D1 = file refnum or 0 (volume block)
        NOP                                     | (was: BEQ.S TagCont in Sys7, patched out)
WBLK_SETUP_TAGS:
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB ptr (pass for file tag setup)
        MOVE.L  CBHFlBlk(A4),D0                 | D0 = file block number (for tag data)
        BSR     P_SetUpTags                     | set up tag data (file num, block, write count)
        MOVEQ.L #0x1,D1                         | indicate 'write' operation
BASICIO_SETUP:
        LEA.L   (Params).w,A0                   | use FS I/O param block
        MOVE    vcbDrvNum(A2),ioVRefNum(A0)     | drive number from VCB
        MOVE    vcbDRefNum(A2),ioRefNum(A0)     | driver refnum from VCB
        LEA.L   CBHData(A4),A1                  | addr(cache buffer data)
        MOVE.L  A1,0x20(A0)                     | IOBuffer = cache data area
        MOVE    #0x1,ioPosMode(A0)              | position mode 1 (from disk start)
        MOVE.L  #0x200,0x24(A0)                 | always r/w 512 bytes (BufSiz)

        MOVE.L  CBHDBlk(A4),D0                  | physical disk block
        LSL.L   #0x8,D0                         | block * 256...
        ADD.L   D0,D0                           | ...* 2 = block * 512
        MOVE.L  D0,ioPosOffset(A0)              | gives disk byte address
L_BasicIO:
        MOVE.L  (0x720).w,-(SP)                 | HFS vector: BasicIO
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Basic IO
|
| Called during boot.
BasicIO:
        MOVE.L  A6,(HFSStkPtr).w                | save HFS stack ptr (for async resume)
        TST.B   (NxtDB).w                       | was FS call async? (FSCallAsync)
        BNE.B   BASICIO_ASYNC                   | br if so (keep it that way)
        TST.B   D1                              | 'read' operation?
        BNE.B   BASICIO_WRITE                   | no, must be a 'write' ->
        _Read                                   | read it synchronously
        BRA.B   BASICIO_RECOVER                 | then continue ->

| ----------------------------------------------------------
|
| BASICIO_WRITE - synchronous write
|
| Called during boot.
BASICIO_WRITE:
        _Write                                  | write it synchronously
        BRA.B   BASICIO_RECOVER                 | then continue ->

| ----------------------------------------------------------
|
| BASICIO_ASYNC - async I/O path
|
BASICIO_ASYNC:
        LEA.L   BASICIO_IOCOMP(PC),A1           | I/O completion address
        MOVE.L  A1,ioCompletion(A0)             | set completion routine
        BCLR    #0x7,(HFSFlags).w               | clear 'HFS continued' flag (HFSContd)
        TST.B   D1                              | 'read' operation?
        BNE.B   BASICIO_AWRITE                  | no, must be a 'write' ->
        _ReadAsync                              | read it asynchronously
        BRA.B   BASICIO_ACHK                    | check result ->

| ----------------------------------------------------------
|
| BASICIO_AWRITE - async write
|
BASICIO_AWRITE:
        _WriteAsync                             | write it asynchronously
BASICIO_ACHK:
        BEQ.B   BASICIO_SETFLAG                 | br if no immediate error
        TST     ioResult(A0)                    | immediate error? for sure?
        BLE.B   BASICIO_RESUME                  | br if so (driver returned garbage otherwise)
BASICIO_SETFLAG:
        BSet    #0x7,(HFSFlags).w               | we're now returning from the trap
        BNE.B   BASICIO_RESUME                  | if we already returned, do I/O comp now
BASICIO_RTS:
        RTS                                     | return to caller (complete async)

| ----------------------------------------------------------
|
| BASICIO_IOCOMP - async I/O completion routine
|
BASICIO_IOCOMP:
        BSET    #0x7,(HFSFlags).w               | we're continuing now (HFSContd)
        BEQ.B   BASICIO_RTS                     | if trap didn't really return async, RTS now
BASICIO_RESUME:
        MOVEM.L D4-D7/A4-A6,-(SP)               | preserve all significant registers
        PEA.L   BASICIO_COMPRET(PC)             | return to BASICIO_COMPRET to restore regs
BASICIO_RECOVER:
        MOVE.L  (HFSStkPtr).w,A6                | recover HFS private stack pointer
        MOVEM.L (A6)+,D1-D7/A0-A5               | retrieve registers off A6 stack
        MOVE.L  (A6)+,-(SP)                     | pop ret address off HFS stack
        TST     D0                              | any errors?
        BEQ.B   BASICIO_ERRCHK                  | br if not
        CMPI    #-0x41,D0                       | offline? (OffLinErr = -65)
        BEQ.B   BASICIO_ERRCHK                  | br if so (pass through)
        MOVE    D0,(FSTemp4).w                  | save original error for debugging
        MOVEQ.L #-0x24,D0                       | transform to generic IOErr (-36)
BASICIO_ERRCHK:
        RTS                                     | return to caller with error code

| ----------------------------------------------------------
|
| BASICIO_COMPRET - completion return: restore interrupted context
|
BASICIO_COMPRET:
        MOVEM.L (SP)+,D4-D7/A4-A6               | restore significant registers
        RTS                                     | we're done with it

| ----------------------------------------------------------
|
| P_m Rd Blocks
|
| Called during boot.
P_mRdBlocks:
        MOVE.L  (0x724).w,-(SP)                 | HFS vector: RdBlocks
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Rd Blocks
|
| Called during boot.
RdBlocks:
        MOVEQ.L #0x0,D0                         | indicate 'read' operation
RDBLK_ENTRY:
        MOVE.L  (SP)+,-(A6)                     | save caller's addr on A6 stack
        MOVEM.L D1-D7/A0-A5,-(A6)               | save regs on HFS stack
        MOVE.L  0x20(A0),A5                     | A5 = user buffer address (IOBuffer)
        ADDA.L  0x28(A0),A5                     | + IOActCount = target for this transfer
        MOVE    D0,D1                           | save read/write indication in D1
        MOVEQ.L #0x40,D0                        | bit 6 mask (verify mode)
        AND.B   0x2D(A0),D0                     | save verify mode bit from IOPosMode
        LEA.L   (Params).w,A0                   | A0 = fixed FS I/O param block
        MOVE    vcbDRefNum(A2),ioRefNum(A0)     | driver refnum from VCB
        MOVE    vcbDrvNum(A2),ioVRefNum(A0)     | drive number from VCB
        MOVE.L  A5,0x20(A0)                     | IOBuffer = computed target address
        MOVE.L  D6,0x24(A0)                     | IOReqCount = byte count to transfer
        MOVE    #0x1,ioPosMode(A0)              | position mode 1 (from disk start)
        OR.B    D0,0x2D(A0)                     | pass verify bit on to disk driver
        MOVE.L  D3,D0                           | D0 = starting disk block number
        LSL.L   #0x8,D0                         | block * 256...
        ADD.L   D0,D0                           | ...* 2 = block * 512 = byte offset
        MOVE.L  D0,ioPosOffset(A0)              | absolute disk byte address
        BRA     L_BasicIO                       | head for BasicIO

| P_mWrBlocks -- write data directly to disk (bypasses cache).
| ----------------------------------------------------------
|
| P_m Wr Blocks
|
P_mWrBlocks:
        MOVE.L  (0x728).w,-(SP)                 | HFS vector: WrBlocks
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Wr Blocks
|
WrBlocks:
        MOVE.L  D5,D0                           | current file position
        LSR.L   #0x8,D0                         | form current file block (pos / 256...)
        LSR.L   #0x1,D0                         | .../ 2 = pos / 512 = start file block
        BSR.B   P_SetUpTags                     | set up tag data for write
        MOVEQ.L #0x1,D0                         | indicate 'write' operation
        BRA.B   RDBLK_ENTRY                     | share setup code with RdBlocks

| ----------------------------------------------------------
|
| P_Set Up Tags
|
| Called during boot.
P_SetUpTags:
        MOVE.L  (0x72C).w,-(SP)                 | HFS vector: SetUpTags
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| Set Up Tags
|
| Called during boot.
SetUpTags:
        TST     D1                              | is it a file block? (D1=file refnum)
        BEQ.B   TAGS_VOL_BLOCK                  | br if not (volume block) ->
        MOVE.L  0x0(A1,D1.W),(BufTgFNum).w      | set up file number in tag (FCBFlNm)
        MOVE.L  D0,(BufTgFFlg).w                | file block number in tag flags field
        MOVE.B  0x4(A1,D1.W),(BufTgFFlg).w      | FCB flags byte (resource fork bit) in tag
        MOVE.L  0x32(A1,D1.W),(BufTgHD20).w     | set Finder file type in HD20 tag (FCBFType)
        MOVE.L  0x3A(A1,D1.W),(BufTgHD20_1).w   | set parent DirID in HD20 tag (FCBDirID)
TAGS_CHK_TFS:
        JSR     TFSVCBTst(PC)                   | is it MFS or HFS?
        BNE.B   TAGS_MFS_DATE                   | br if MFS ->
        MOVE.L  vcbWrCnt(A2),(BufTgDate).w      | set write count in tag data (HFS)
        ADDQ.L  #0x1,vcbWrCnt(A2)               | bump volume write count
        RTS                                     | return from SetUpTags (HFS path)

| ----------------------------------------------------------
|
| TAGS_VOL_BLOCK - set up tags for non-file (volume) block
|
| Called during boot.
TAGS_VOL_BLOCK:
        MOVE.L  D0,(BufTgFFlg).w                | filblk = logical block on volume
        MOVEQ.L #0x1,D0                         | FSRtParID (parent DirID of root = 1)
        MOVE.L  D0,(BufTgFNum).w                | filnum = parent DirID of root
        CLR.L   (BufTgHD20).w                   | no HFS tag data for volume level I/O
        CLR.L   (BufTgHD20_1).w                 | (clear second HD20 tag longword)
        BRA.B   TAGS_CHK_TFS                    | rejoin common TFS/MFS tag path

| ----------------------------------------------------------
|
| TAGS_MFS_DATE - MFS tag: use current time instead of write count
|
| Called during boot.
TAGS_MFS_DATE:
        MOVE.L  (Time).w,(BufTgDate).w          | use date for MFS (not write count)
        RTS                                     | return from SetUpTags (MFS path)

| ----------------------------------------------------------
|
| Check SCSI
|
| Called during boot.
CheckSCSI:
        TST.B   (HWCfgFlags).w                  | check hardware config flags
| --- ROM-variant difference @ $7D44 ---
| v1: BEQ.B SCSI_EXIT -- branched when HWCfgFlags == 0.
| v2/v3: BPL.B SCSI_EXIT -- branches when bit-7 (hasSCSI) is clear.
| Reason: v1's BEQ tested the whole byte instead of the hasSCSI flag
| bit, so a machine with SCSI present plus any other flag bit
| set would incorrectly skip the probe. v2 fixed this with BPL.
.if ROM_TARGET == MAC_PLUS_V1
        BEQ.B   SCSI_EXIT                       | Plus v1: skip when HWCfgFlags==0 (buggy)
.else
        BPL.B   SCSI_EXIT                       | Plus v2/v3: skip when hasSCSI bit clear
.endif
        MOVEM.L D0-D7/A0-A6,-(SP)               | save all registers
| --- ROM-variant difference @ $7D4A-$7D4D ---
| v1/v2: inline SCSI reset here -- `CLR.W -(SP); _SCSIDispatch` pushes the
| SCSIReset selector and calls the SCSI Manager.
| v3: two NOPs -- the reset now happens only from the extra-area SCSI
| patch (EXTRA_CONT in src/extra/extra.s), not here.
| Reason: same factoring that redirected InitIOMgr at $08AC; avoids
| doing the reset twice during boot.
.if ROM_TARGET < MAC_PLUS_V3
        CLR     -(SP)                           | Plus v1/v2: push selector 0 = SCSIReset
        _SCSIDispatch                           | Plus v1/v2: reset SCSI bus
.else
        NOP                                     | Plus v3: (reset moved to extra-area patch)
        NOP                                     | Plus v3: (reset moved to extra-area patch)
.endif
        MOVEQ.L #0x6,D5                         | D5 = 6: start from SCSI ID 6 (scan down to 0)
SCSI_PROBE_LOOP:
        BTst    D5,(SCSIDrvrs).w                | already found a driver at this ID?
        BNE.B   SCSI_NEXT_ID                    | yes: skip (already installed)
        BSR.B   SCSIProbeDevice                 | probe SCSI device at ID D5
SCSI_NEXT_ID:
        SUBQ.W  #0x1,D5                         | next lower SCSI ID
        BGE.B   SCSI_PROBE_LOOP                 | loop until all IDs 6..0 checked
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore all registers
SCSI_EXIT:
        RTS                                     | return from CheckSCSI

| ----------------------------------------------------------
|
| SCSIProbeDevice
|
| Called during boot.
SCSIProbeDevice:                                | probe SCSI device at ID in D5
        SUBA.L  #0x100,SP                       | allocate 256 bytes on stack for read buffer
        MOVE.L  A7,A2                           | A2 = stack buffer (destination for reads)
        MOVEQ.L #0x0,D3                         | D3 = block 0 (read device descriptor map)
        MOVEQ.L #0x1,D2                         | D2 = 1 block to read
        MOVE    #0x100,D4                       | D4 = 256 bytes per block
        BSR.B   SCSIReadBlocks                  | Read block 0 from SCSI device
        BNE.B   SCSI_PROBE_EXIT                 | Read failed: no SCSI disk
        CMPI    #0x4552,(SP)                    | Check for Apple driver partition map signature 'ER'
        BNE.B   SCSI_PROBE_EXIT                 | Not Apple partition: skip
        MOVE    0x2(SP),D4                      | D4 = partition block size
        MOVE    0x10(SP),D0                     | D0 = partition map entry count
        LEA.L   0x12(SP),A0                     | A0 = partition map entries
        MOVE.L  0xC(SP),D7                      | D7 = driver descriptor from partition map
SCSI_FIND_DRVR:
        CMPI    #0x1,0x6(A0)                    | Partition type = Apple_Driver (type 1)?
        BEQ.B   SCSI_LOAD_DRVR                  | Yes: found SCSI driver partition
        ADDQ.L  #0x8,A0                         | Next partition entry
        SUBQ.W  #0x1,D0                         | More entries?
        BNE.B   SCSI_FIND_DRVR                  | No: no bootable SCSI partition
        BRA.B   SCSI_PROBE_EXIT                 | Done: no SCSI driver found

| ----------------------------------------------------------
|
| SCSI_LOAD_DRVR
|
SCSI_LOAD_DRVR:
        BSet    D5,(SCSIDrvrs).w                | Mark this SCSI ID as having a driver
        MOVE.L  (A0),D3                         | D3 = driver physical block start on disk
        MOVE    0x4(A0),D2                      | D2 = driver block count
        MOVE.L  D4,D0                           | D4 = partition block size
        MULU    D2,D0                           | D0 = total driver size in bytes
        _NewPtrSys                              | Allocate memory for SCSI driver code
        MOVE.L  A0,A3                           | A3 = driver code buffer
        MOVE.L  A0,A2                           | A2 = buffer for reading driver
        BSR.B   SCSIReadBlocks                  | Read SCSI driver from disk into buffer
        BNE.B   SCSI_PROBE_EXIT                 | Read failed: abort
        MOVEQ.L #0x1,D3                         | D3 = starting block 1 (for partition map)
        MOVEQ.L #0x1,D2                         | D2 = 1 block
        MOVE    #0x100,D4                       | D4 = 256 bytes
        MOVE.L  A7,A2                           | A2 = stack buffer for re-reading partition map
        BSR.B   SCSIReadBlocks                  | Re-read partition map
        BNE.B   SCSI_PROBE_EXIT                 | Failed: abort
        MOVE.L  A2,A0                           | A0 = partition data
        JSR     (A3)                            | Execute loaded SCSI driver init routine (installs driver in Unit Table)
SCSI_PROBE_EXIT:
        ADDA    #0x100,SP                       | Clean up 256-byte stack allocation
        RTS                                     | Return from CheckSCSI

| ----------------------------------------------------------
|
| SCSIReadBlocks
|
| Called during boot.
SCSIReadBlocks:
        LEA.L   (scratch8).w,A0                 | A0 -> scratch8 (SCSI command block buffer)
        MOVE.B  #0x8,(A0)+                      | SCSI opcode = 8 (READ)
        SWAP    D3                              | Swap D3 to get high word (LUN + LBA high)
        ANDI.B  #0x1F,D3                        | Mask LBA high bits (5 bits)
        MOVE.B  D3,(A0)+                        | Store LUN + LBA high byte
        SWAP    D3                              | Swap back, store LBA low word
        MOVE    D3,(A0)+                        | Store LBA middle bytes
        MOVE.B  D2,(A0)+                        | Store block count
        CLR.B   (A0)+                           | Control byte = 0
        MULU    D2,D4                           | D4 = total transfer size (blocks * block size)
        SUBA    #0x14,SP                        | Allocate 20 bytes on stack for TIB (Transfer Instruction Block)
        MOVE.L  A7,D6                           | D6 = TIB pointer (save for SCSIRead)
        SUBQ.W  #0x2,SP                         | Make room for SCSIGet result
        MOVE    #0x1,-(SP)                      | Push selector = 1
        _SCSIDispatch                           | _SCSIDispatch(SCSIGet): arbitrate for SCSI bus
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        MOVE    D5,-(SP)                        | Push SCSI target ID
        MOVE    #0x2,-(SP)                      | Push selector = 2
        _SCSIDispatch                           | _SCSIDispatch(SCSISelect): select target device by SCSI ID
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        PEA.L   (scratch8).w                    | Push command block address (scratch8)
        MOVE    #0x6,-(SP)                      | Push command length = 6
        MOVE    #0x3,-(SP)                      | Push selector = 3
        _SCSIDispatch                           | _SCSIDispatch(SCSICmd): send 6-byte SCSI READ command
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        MOVE.L  D6,A0                           | A0 = TIB buffer on stack
        MOVE    #0x1,(A0)+                      | TIB opcode 1 = scInc (transfer with auto-increment)
        MOVE.L  A2,(A0)+                        | TIB buffer = read destination address
        MOVE.L  D4,(A0)+                        | TIB count = total bytes to transfer
        MOVE    #0x7,(A0)+                      | TIB terminator 7 = scStop (end of transfer list)
        MOVE.L  D6,-(SP)                        | Push TIB pointer for SCSIRead
        MOVE    #0x5,-(SP)                      | Push selector = 5
        _SCSIDispatch                           | _SCSIDispatch(SCSIRead): execute TIB-based data transfer
        PEA.L   (scratch8).w                    | Push status buffer address
        PEA.L   (scratch8_2).w                  | Push message buffer address
        MOVE.L  #0x3C,-(SP)                     | Push timeout = 60 ticks
        MOVE    #0x4,-(SP)                      | Push selector = 4
        _SCSIDispatch                           | _SCSIDispatch(SCSIComplete): get status/message, release bus
        TST     (SP)                            | Check result
        BNE.B   SCSI_READ_ERR                   | Error: clean up and return
        ADDQ.L  #0x2,SP                         | Clean SCSIComplete result from stack
        ADDA    #0x14,SP                        | Clean TIB from stack
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | Return success

| ----------------------------------------------------------
|
| SCSI_READ_ERR
|
| Called during boot.
SCSI_READ_ERR:
        ADDQ.L  #0x2,SP                         | Clean result from stack
        ADDA    #0x14,SP                        | Clean TIB from stack
        MOVEQ.L #-0x1,D0                        | D0 = -1 (error)
        RTS                                     | Return error

| ----------------------------------------------------------
|
| TrapDispatchTbl - Compressed trap dispatch table
|
| Delta-encoded ROM offsets for all implemented A-line traps.
| Decoded at boot by vectors.s to fill ToolDispTable (512 Toolbox
| traps at $800) and DispatchTab (256 OS traps at $400).
|
| Encoding per byte:
| 0x80 = skip (trap is Unimplemented)
| 0x81..0xFF = 1-byte signed delta * 2 from previous address
| 0x01..0x7E = 1-byte signed delta * 2 from previous address
| 0x00 = next 2 bytes are absolute ROM offset
| 0x7F = next 2 bytes are absolute ROM offset
| 0xFF,0x00 = next 2 bytes are 16-bit big-endian ROM offset
|
| Total: 1134 bytes covering 768 trap table entries.
|
TrapDispatchTbl:
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | Toolbox traps $A800..$A805: skip
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | Toolbox traps $A806..$A80B: skip
  .byte 0x80,0xFF,0x00,0x01,0x3C,0x76           | $A80C skip; $A80D=abs; deltas...
  .byte 0x95,0xF3,0x93,0x17,0x8A,0x7F           | Toolbox trap deltas (continued)
  .byte 0xCA,0xEC,0x80,0x02,0x00,0x7F           | deltas; $A818 skip; deltas
  .byte 0x8B,0xFF,0x00,0x00,0xCA,0xF0           | delta; abs offset; delta
  .byte 0xFF,0x00,0x01,0x5A,0x56,0x7D           | abs offset; deltas
  .byte 0xB0,0x54,0xF7,0x83,0x1E,0xC9           | Toolbox trap deltas (continued)
  .byte 0x61,0x80,0xCD,0x1E,0x8A,0xA2           | delta; skip; deltas
  .byte 0x05,0x2C,0x5C,0x64,0x91,0x96           | Toolbox trap deltas (continued)
  .byte 0x7F,0xFA,0x14,0x49,0x12,0xB8           | Toolbox trap deltas (continued)
  .byte 0xAF,0x59,0x20,0x85,0x37,0x05           | Toolbox trap deltas (continued)
  .byte 0x81,0x81,0x81,0x81,0x81,0x81           | 6x small negative delta (-2)
  .byte 0xFF,0x00,0x00,0x28,0x0A,0x7B           | abs offset; deltas
  .byte 0x34,0xFF,0x00,0x00,0xF2,0x60           | delta; abs offset; delta
  .byte 0x8A,0x48,0xCD,0x04,0xF4,0x1F           | Toolbox trap deltas (continued)
  .byte 0xA1,0x7F,0xFC,0x26,0xF4,0xB7           | Toolbox trap deltas (continued)
  .byte 0x80,0x80,0x80,0x20,0x23,0x7F           | 3 skips; deltas
  .byte 0xF0,0x92,0x7F,0xF0,0x7F,0xB4           | Toolbox trap deltas (continued)
  .byte 0x99,0x7F,0xEA,0x99,0x7F,0x2B           | Toolbox trap deltas (continued)
  .byte 0x84,0x7F,0xA9,0x7F,0x6F,0xE9           | Toolbox trap deltas (continued)
  .byte 0x53,0x87,0x2C,0x7C,0x80,0x80           | deltas; 2 skips
  .byte 0xFF,0x00,0x00,0x82,0xC6,0x88           | abs offset; deltas
  .byte 0x8E,0x83,0x3A,0xC0,0x45,0x43           | Toolbox trap deltas (continued)
  .byte 0x98,0x80,0x87,0x84,0x7F,0xF8           | delta; skip; deltas
  .byte 0x8D,0x84,0x8B,0x87,0x85,0x80           | deltas; skip
  .byte 0x8C,0xA9,0x82,0x87,0x00,0xEA           | deltas; abs offset
  .byte 0x9A,0xFF,0x00,0x01,0x57,0xB2           | delta; abs offset; delta
  .byte 0x9A,0x00,0xAA,0xA1,0x7F,0xFC           | delta; abs offset; deltas
  .byte 0x89,0xFF,0x00,0x00,0x88,0x84           | delta; abs offset; delta
  .byte 0x7F,0x91,0xE3,0xF5,0x84,0xB2           | Toolbox trap deltas (continued)
  .byte 0x7F,0xF7,0x84,0x88,0x93,0x90           | Toolbox trap deltas (continued)
  .byte 0x96,0xA3,0x86,0x7F,0xF1,0x7F           | Toolbox trap deltas (continued)
  .byte 0xB9,0x7F,0x92,0xC3,0x84,0x00           | deltas; abs offset
  .byte 0x87,0x85,0x86,0x00,0xDC,0xA0           | deltas; abs offset; delta
  .byte 0x89,0x94,0x7F,0xD6,0x7F,0xE7           | Toolbox trap deltas (continued)
  .byte 0x9B,0x82,0x00,0xF4,0x7F,0x2A           | deltas; abs offset; delta
  .byte 0x7F,0xD2,0x93,0x80,0x04,0xE3           | deltas; skip; deltas
  .byte 0xC9,0x8B,0x8C,0x86,0x80,0xC6           | deltas; skip; delta
  .byte 0x82,0x86,0x82,0x91,0x88,0x87           | Toolbox trap deltas (continued)
  .byte 0x83,0x8A,0x80,0x03,0x28,0xD5           | deltas; skip; deltas
  .byte 0x82,0x82,0x82,0x7F,0xEF,0x00           | deltas; abs offset
  .byte 0xBF,0x7F,0xF9,0xA1,0x89,0x89           | Toolbox trap deltas (continued)
  .byte 0xCE,0x9F,0x9B,0x7F,0x59,0x05           | Toolbox trap deltas (continued)
  .byte 0xE3,0xC9,0x82,0x82,0x82,0x82           | Toolbox trap deltas (continued)
  .byte 0x80,0x9D,0xC4,0x82,0x82,0x82           | skip; deltas
  .byte 0x82,0x04,0xF5,0x7B,0xC5,0xBF           | Toolbox trap deltas (continued)
  .byte 0x82,0x82,0x82,0x82,0x04,0x86           | Toolbox trap deltas (continued)
  .byte 0x7F,0x4F,0x00,0xF9,0xBB,0x82           | deltas; abs offset; deltas
  .byte 0x82,0x82,0x82,0x9B,0x9A,0xB7           | Toolbox trap deltas (continued)
  .byte 0x84,0x0A,0x52,0xC8,0x75,0xED           | Toolbox trap deltas (continued)
  .byte 0xB3,0x82,0x82,0x82,0x82,0x80           | deltas; skip
  .byte 0xF1,0x92,0x84,0x97,0xAB,0xA7           | Toolbox trap deltas (continued)
  .byte 0x86,0xAE,0x87,0x99,0xCE,0x88           | Toolbox trap deltas (continued)
  .byte 0x9F,0x82,0x82,0x82,0xF5,0xB0           | Toolbox trap deltas (continued)
  .byte 0x63,0xF4,0x1F,0xD8,0x00,0xBF           | deltas; abs offset; delta
  .byte 0x61,0x83,0x25,0xF0,0x7A,0xAF           | Toolbox trap deltas (continued)
  .byte 0x05,0x64,0x7F,0xBD,0x00,0x83           | deltas; abs offset; delta
  .byte 0x8B,0xDE,0x9E,0x84,0x80,0x05           | deltas; skip; delta
  .byte 0x13,0xAC,0xB1,0x6E,0x26,0x7C           | Toolbox trap deltas (continued)
  .byte 0x76,0x80,0x15,0x70,0x05,0x6E           | deltas; skip; deltas
  .byte 0xD3,0x7A,0xAD,0x05,0xA7,0x7F           | Toolbox trap deltas (continued)
  .byte 0xE5,0x17,0xD1,0x7E,0x70,0x79           | Toolbox trap deltas (continued)
  .byte 0xA9,0x8C,0x01,0x6C,0x7E,0xCE           | Toolbox trap deltas (continued)
  .byte 0xAC,0xA2,0x92,0xD5,0xB6,0x97           | Toolbox trap deltas (continued)
  .byte 0xD1,0x85,0xCA,0xE3,0x00,0xE1           | deltas; abs offset; delta
  .byte 0x87,0x94,0x95,0x87,0x8E,0x8C           | Toolbox trap deltas (continued)
  .byte 0xE7,0x00,0x88,0xA0,0xDD,0xBB           | delta; abs offset; deltas
  .byte 0x98,0xCE,0xAB,0x9D,0x91,0x95           | Toolbox trap deltas (continued)
  .byte 0xE5,0x00,0x94,0xA0,0x8F,0x82           | delta; abs offset; deltas
  .byte 0x82,0x00,0x81,0x7B,0x40,0x00           | deltas; abs offsets
  .byte 0x86,0x83,0x04,0x88,0x04,0x19           | Toolbox trap deltas (continued)
  .byte 0x7E,0xFC,0x01,0x2C,0x7B,0xF2           | Toolbox trap deltas (continued)
  .byte 0x88,0xD0,0xD1,0xC5,0x95,0x8E           | Toolbox trap deltas (continued)
  .byte 0x01,0xBF,0x8A,0x7E,0x5E,0x02           | Toolbox trap deltas (continued)
  .byte 0x3B,0x7F,0xE4,0x82,0x82,0x82           | Toolbox trap deltas (continued)
  .byte 0x82,0x82,0x82,0xCE,0x01,0x38           | Toolbox trap deltas (continued)
  .byte 0x7E,0xE2,0x00,0xF5,0xCC,0x00           | deltas; abs offset; abs offset
  .byte 0x81,0x7D,0x60,0x02,0x24,0xFF           | Toolbox trap deltas (continued)
  .byte 0x00,0x00,0x1F,0x38,0xFF,0x00           | abs offset; abs offset (start)
  .byte 0x01,0x19,0x24,0x09,0xEC,0x7F           | abs offset (end); deltas
  .byte 0x96,0x7F,0xBB,0x03,0x58,0x7D           | Toolbox trap deltas (continued)
  .byte 0x83,0x00,0xA1,0x92,0x8E,0x8F           | delta; abs offset; deltas
  .byte 0x8D,0x9F,0x87,0x8C,0x94,0x96           | Toolbox trap deltas (continued)
  .byte 0x8C,0xA1,0x87,0x82,0x82,0xA1           | Toolbox trap deltas (continued)
  .byte 0x82,0x82,0x97,0xD9,0x00,0x7F           | deltas; abs offset (start)
  .byte 0x7E,0x86,0x82,0x01,0xBC,0x7D           | abs offset (end); deltas
  .byte 0xF3,0xFF,0x00,0x00,0x19,0xF0           | delta; abs offset; delta
  .byte 0x7F,0xED,0xFF,0x00,0x01,0x10           | delta; abs offset (start)
  .byte 0x00,0x7F,0xFE,0x7F,0xD2,0x8B           | abs offset (end); deltas
  .byte 0x7F,0xCB,0x89,0x7F,0xE9,0xD7           | Toolbox trap deltas (continued)
  .byte 0x1E,0x51,0xED,0xAD,0x7D,0x7F           | Toolbox trap deltas (continued)
  .byte 0x00,0xEF,0x9C,0x02,0x38,0x7E           | abs offset; deltas
  .byte 0x14,0x9D,0xE7,0x9B,0xC3,0x01           | Toolbox trap deltas (continued)
  .byte 0xA0,0x7C,0x88,0x7F,0xFA,0x82           | Toolbox trap deltas (continued)
  .byte 0x82,0x01,0xFC,0xAD,0xA6,0x92           | Toolbox trap deltas (continued)
  .byte 0x84,0xA3,0xAB,0x7F,0xF0,0x7E           | Toolbox trap deltas (continued)
  .byte 0x92,0x7C,0x2D,0xD8,0x95,0x77           | Toolbox trap deltas (continued)
  .byte 0x34,0x01,0xC9,0xF4,0x9F,0xF1           | Toolbox trap deltas (continued)
  .byte 0x01,0x61,0x04,0x99,0x7B,0xBB           | Toolbox trap deltas (continued)
  .byte 0x95,0xCE,0xA5,0xB2,0xA2,0x02           | Toolbox trap deltas (continued)
  .byte 0xCD,0x9F,0xD9,0x01,0xD4,0x7E           | Toolbox trap deltas (continued)
  .byte 0x6A,0x8A,0x99,0xA3,0x7F,0x44           | Toolbox trap deltas (continued)
  .byte 0x00,0xE1,0x7F,0x88,0x00,0xE5           | abs offset; deltas; abs offset
  .byte 0x7F,0x23,0x7F,0xF4,0x7F,0xB6           | Toolbox trap deltas (continued)
  .byte 0x79,0x92,0x12,0x1D,0xE0,0xE9           | Toolbox trap deltas (continued)
  .byte 0xBE,0xBB,0xA7,0x8D,0x8D,0x84           | Toolbox trap deltas (continued)
  .byte 0x84,0x84,0x84,0xAB,0xA8,0xBF           | Toolbox trap deltas (continued)
  .byte 0x6E,0xC3,0x10,0x43,0x80,0x6C           | deltas; skip; delta
  .byte 0xF2,0x08,0x40,0x13,0xDC,0xBC           | Toolbox trap deltas (continued)
  .byte 0xFF,0x00,0x00,0x11,0xDC,0x7F           | abs offset; delta
  .byte 0xB3,0x7E,0xC1,0xFF,0x00,0x01           | deltas; abs offset (start)
  .byte 0x60,0x8E,0x86,0x93,0x8F,0xEF           | abs offset (end); deltas
  .byte 0xA2,0x9D,0x96,0xBD,0x97,0x02           | Toolbox trap deltas (continued)
  .byte 0x50,0x93,0x87,0x01,0x40,0x91           | Toolbox trap deltas (continued)
  .byte 0x8B,0x94,0xF6,0xB2,0x7F,0xB7           | Toolbox trap deltas (continued)
  .byte 0xB6,0x74,0xCE,0x00,0xB2,0x8F           | deltas; abs offset; delta
  .byte 0x84,0x8D,0x0C,0x32,0x91,0xC0           | Toolbox trap deltas (continued)
  .byte 0x81,0x81,0x81,0x81,0x81,0x81           | 6x small negative delta (-2)
  .byte 0x81,0x73,0x88,0x4E,0x83,0xC5           | Toolbox trap deltas (continued)
  .byte 0xBE,0x7F,0xFD,0x00,0xC1,0x9C           | deltas; abs offset; delta
  .byte 0x20,0x94,0x86,0x0F,0x8E,0x0B           | Toolbox trap deltas (continued)
  .byte 0x26,0xBD,0x9A,0x9A,0xA6,0xB8           | Toolbox trap deltas (continued)
  .byte 0x80,0xFF,0x00,0x00,0x21,0xF4           | skip; abs offset; delta
  .byte 0x00,0xC9,0x9C,0xB8,0x8A,0x87           | abs offset; deltas
  .byte 0x93,0x09,0xD7,0x04,0xDF,0x01           | Toolbox trap deltas (continued)
  .byte 0x15,0x7E,0x07,0x02,0x34,0x03           | Toolbox trap deltas (continued)
  .byte 0x30,0x7E,0xFA,0x76,0x6F,0x7C           | Toolbox trap deltas (continued)
  .byte 0x22,0x13,0x4B,0x7F,0x59,0x00           | deltas; abs offset (start)
  .byte 0xC0,0x70,0x9E,0x02,0x47,0xA8           | abs offset (end); deltas
  .byte 0x77,0xC9,0x05,0x3A,0x0D,0x18           | Toolbox trap deltas (continued)
  .byte 0xFF,0x00,0x00,0xFF,0x38,0xB6           | abs offset; deltas
  .byte 0x83,0xB5,0x94,0xCD,0x8E,0x90           | Toolbox trap deltas (continued)
  .byte 0x7F,0xFB,0xA3,0x91,0x96,0x7F           | Toolbox trap deltas (continued)
  .byte 0xFA,0x8F,0x9F,0x7F,0xE5,0xBD           | Toolbox trap deltas (continued)
  .byte 0x85,0x7F,0xD1,0x7E,0x84,0x00           | deltas; abs offset (start)
  .byte 0xCB,0x06,0x23,0xFF,0x00,0x00           | abs offset (end); deltas; abs offset
  .byte 0x26,0xEC,0xBC,0xC4,0x8F,0x7A           | abs offset (end); deltas
  .byte 0x10,0xA5,0x0B,0xE3,0xFF,0x00           | deltas; abs offset (start)
  .byte 0x01,0x02,0x74,0x7A,0x8E,0x8D           | abs offset (end); deltas
  .byte 0x90,0x85,0x84,0x89,0xFF,0x00           | deltas; abs offset (start)
  .byte 0x00,0x24,0xCA,0xAF,0xFF,0x00           | abs offset (end); deltas; abs (start)
  .byte 0x00,0xFC,0xC2,0x01,0xAE,0xFF           | abs offset (end); deltas; abs (start)
  .byte 0x00,0x00,0x48,0x8A,0x85,0x7F           | abs offset (end); deltas
  .byte 0xDF,0x03,0x61,0x01,0x18,0x67           | Toolbox trap deltas (continued)
  .byte 0x63,0x7F,0xD8,0xFF,0x00,0x01           | deltas; abs offset (start)
  .byte 0x01,0x1C,0x00,0x94,0x85,0x7F           | abs offset (end); abs offset; deltas
  .byte 0x11,0x7F,0xA7,0x98,0xFF,0x00           | deltas; abs offset (start)
  .byte 0x00,0x25,0x58,0xFF,0x00,0x00           | abs offset (end); abs offset (start)
  .byte 0xF7,0x2C,0xEC,0x03,0x0A,0x85           | abs offset (end); deltas
  .byte 0xFF,0x00,0x00,0x01,0xF8,0xFF           | abs offset; abs offset (start)
  .byte 0x00,0x00,0xF8,0x78,0x80,0x80           | abs offset (end); 2 skips
  .byte 0x02,0xFF,0x3B,0xAE,0x87,0x8D           | delta; special; deltas
  .byte 0x80,0x80,0x80,0x80,0x80,0xFF           | 5 skips; abs (start)
  .byte 0x00,0x00,0x28,0x52,0xFF,0x00           | abs offset (end); abs (start)
  .byte 0x00,0xFF,0xB0,0xAD,0xD2,0x00           | abs offset (end); deltas; abs (start)
  .byte 0xEF,0x7F,0x09,0xCE,0x80,0x80           | abs offset (end); deltas; 2 skips
  .byte 0x80,0x80,0x80,0xFF,0x00,0x00           | 3 skips; abs offset (start)
  .byte 0x0C,0x7A,0xE9,0x80,0x80,0x80           | abs offset (end); delta; 3 skips
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | Toolbox traps: all Unimplemented
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | end of Toolbox skip block
  .byte 0x24,0x4D,0x10,0x73,0xF5,0x01           | OS traps $A000+: deltas
  .byte 0x22,0x8B,0xEC,0x7F,0xBD,0xFD           | OS trap deltas (continued)
  .byte 0x7F,0xEA,0xF5,0xBC,0xA7,0x89           | OS trap deltas (continued)
  .byte 0x74,0xF8,0xA0,0x00,0xD3,0xB3           | deltas; abs offset; deltas
  .byte 0xE1,0x01,0x50,0xE0,0xC6,0x03           | OS trap deltas (continued)
  .byte 0x16,0x00,0xE7,0x7C,0x34,0x00           | delta; abs offset; deltas; abs (start)
  .byte 0xBE,0x7F,0x8D,0x75,0xED,0xEA           | abs offset (end); deltas
  .byte 0x01,0x0E,0x04,0x04,0x80,0x68           | deltas; skip; delta
  .byte 0x58,0x10,0xC3,0x00,0xAE,0x73           | deltas; abs offset; deltas
  .byte 0x79,0x00,0xA4,0x04,0x12,0x04           | delta; abs offset; deltas
  .byte 0xE1,0x00,0xEF,0x80,0x80,0x80           | delta; abs offset; 3 skips
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | OS traps: all Unimplemented
  .byte 0x80,0x80,0x80,0x80,0x80,0x80           | (skip block continues)
  .byte 0x80,0x80,0x80,0xFF,0x00,0x00           | 3 skips; abs offset (start)
  .byte 0xF6,0x7A,0x1F,0x2D,0x02,0x84           | abs offset (end); deltas
  .byte 0x7E,0x1E,0x05,0x8F,0x12,0x62           | OS trap deltas (continued)
  .byte 0x01,0x2D,0xBA,0x00,0x00,0x00           | deltas; 3 zero padding bytes (end)

