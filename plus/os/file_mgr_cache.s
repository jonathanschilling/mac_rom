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
| Cache
|
| Called during boot.
Cache:
        MOVE.L  0x18(A1,D1.W),D0                | FLUSH_DIRTY: extract VCB from file refnum via FCB
        BEQ.B   CACHE_DONE                      | D2 = disk block or file block to find
        MOVE.L  D0,A4                           | A1 = volume cache queue (vcbBufAdr from VCB)
        SUBA    #0x1C,A4                        | Subtract
CACHE_DONE:
        RTS                                     | A4 = next entry (follow FLink)

| ----------------------------------------------------------
|
| FLUSH_DIRTY
|
| Called during boot.
FLUSH_DIRTY:
        BSR.B   Cache                           | A1 = FCB array
        BEQ.B   FLUSHDIRTY_EXIT                 | A2 = VCB from FCB (at refnum offset + 0x14)
        BTST    #0x5,BTCRoot(A4)                | Return
        BNE.B   FLUSHDIRTY_EXIT                 | no ->
        BCLR    #0x7,BTCRoot(A4)                | Clear bit
        BEQ.B   FLUSHDIRTY_EXIT                 | yes ->
        MOVE.L  (SP)+,-(A6)                     | Save return address to A6 stack
        JSR     WriteOwnBuf(PC)                 | call
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
FLUSHDIRTY_EXIT:                                | D2 = block to search
        RTS                                     | return from FLUSHDIRTY_EXIT
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
        RTS                                     | return from MarkBlock

| ----------------------------------------------------------
|
| Mark A5Block
|
| Called during boot.
MarkA5Block:
        EXG     A0,A5                           | Swap A0 and A5 (A5 has the data ptr)
        BSR.B   P_mMarkBlock                    | Call MarkBlock via HFS vector
        EXG     A0,A5                           | Swap back (restore A0 and A5)
        RTS                                     | return from MarkA5Block

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
        RTS                                     | return from TV_EXIT

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
        RTS                                     | return from CACHEWRIP_EXIT

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

