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
| BOOT_SCSI_RESCAN/WrBlocks - raw disk block I/O via Device Manager
|
| References:
| Inside Macintosh: Files, Ch 2: "Data Organization on Volumes"

| CACHE: get BTCB from FCB cache extension
| Input: A1=FCB array, D1=refnum offset
| Returns: A4=BTCB-0x1C (cache control), Z=1 if no cache
CACHE:
    MOVE.L	0x18(A1,D1.W),D0                     | D0 = cache ptr from FCB
    BEQ.B	CACHE_DONE                            | no cache ->
    MOVEA.L	D0,A4                               | A4 = cache header
    SUBA.W	#0x1C,A4                             | back up to control block base
CACHE_DONE:
    RTS                                         | return (Z set if no cache)
| ----------------------------------------------------------
|
| FLUSH_DIRTY: flush dirty cache block if needed
|
FLUSH_DIRTY:
    BSR.B	CACHE                                 | get cache control -> A4
    BEQ.B	FLUSHDIRTY_EXIT                       | no cache ->
    BTST	#0x5,0x1A(A4)                          | write-protected?
    BNE.B	FLUSHDIRTY_EXIT                       | yes, skip ->
    BCLR	#0x7,0x1A(A4)                          | dirty flag set? (clear it)
    BEQ.B	FLUSHDIRTY_EXIT                       | was not dirty ->
    MOVE.L	(A7)+,-(A6)                          | save return address
    JSR	WRITEOWNBUF(PC)                         | write dirty buffer to disk
    MOVE.L	(A6)+,-(A7)                          | restore return address
FLUSHDIRTY_EXIT:
    RTS                                         | return from FlushDirty
| Called by: OFFLINE_SKIP_2, CREATE_CONT_7, L_MFILEREAD_CONT, FILECLOSE_OK_2, VBTCLOSE (and 3 more)
FLUSHCACHE:
    MOVE.L	(0x700).W,-(A7)                      | HFS vector: FlushCache trampoline
    RTS                                         | dispatch via vector
VFLUSHCACHE:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1-D6/A0-A4,-(A6)                   | save regs
    CMPA.L	(SysCtlCPtr).W,A1                    | flushing the control cache?
    BNE.B	FLUSH_MAIN                            | no, proceed to main flush ->
    TST.B	(SysCRefCnt).W                        | flush forced?
    BNE.B	FLUSH_MAIN                            | yes, skip clean-check ->
    MOVEQ.L	#0x0,D5                             | D5 = clean buffer count
    MOVEA.L	A1,A3                               | A3 = cache queue header (CQH)
    MOVEA.L	A3,A4                               | start at top of queue
FLUSH_SCAN_NEXT:
    MOVEA.L	(A4),A4                             | next buffer in queue
    CMPA.L	A3,A4                                | back to top?
    BEQ.B	FLUSH_CHK_CLEAN                       | yes, check ratio ->
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BNE.B	FLUSH_COUNT_CLEAN                     | yes, counts as clean ->
    BTST	#0x6,0x1A(A4)                          | CBHFlags: in use?
    BNE.B	FLUSH_SCAN_NEXT                       | yes, skip ->
    BTST	#0x7,0x1A(A4)                          | CBHFlags: dirty?
    BNE.B	FLUSH_SCAN_NEXT                       | yes, skip ->
FLUSH_COUNT_CLEAN:
    ADDQ.W	#0x1,D5                              | bump clean count
    BRA.B	FLUSH_SCAN_NEXT                       | continue scan ->
| ----------------------------------------------------------
|
| FLUSH_CHK_CLEAN - check if more than 25% of control cache buffers are clean
|
| Called during boot.
FLUSH_CHK_CLEAN:
    MOVE.W	0x8(A3),D6                           | CQHNumBuf: total buffers
    LSR.W	#0x2,D6                               | 25% threshold
    CMP.W	D6,D5                                 | > 25% clean?
    BHI.W	FLUSH_EXIT_OK                         | yes, no flush needed ->
FLUSH_MAIN:
    MOVE.B	D1,D5                                | D5 = option flags
    MOVEA.L	A1,A3                               | A3 = cache queue header
    MOVE.W	D0,D1                                | D1 = refnum
    BLE.B	FLUSH_ZERO_MATCH                      | volume flush ->
    MOVEA.L	(FCBSPtr).W,A1                      | FCB array base
    MOVEA.L	0x14(A1,D1.W),A2                    | A2 = VCB ptr
    BSR.B	FLUSH_DIRTY                           | flush any installed OwnBuf
    MOVE.L	0x0(A1,D1.W),D3                      | D3 = file number
    BTST	#0x1,0x4(A1,D1.W)                      | resource fork?
    SNE.B	D6                                    | D6 = fork type flag
FLUSH_ZERO_MATCH:
    MOVEQ.L	#0x0,D4                             | D4 = last flushed disk block
FLUSH_RESTART:
    MOVEQ.L	#0x0,D2                             | D2 = current match (0 = none)
    MOVEA.L	A3,A4                               | start at top of queue
| Called by: FLUSH_CHK_MATCH, FLUSH_CHK_ORDER, FLUSH_VOL_MATCH
FLUSH_SEARCH_NEXT:
    MOVEA.L	(A4),A4                             | next buffer in queue
    CMPA.L	A3,A4                                | back to top?
    BNE.B	FLUSH_CHK_MATCH                       | no, check this buffer ->
    TST.L	D2                                    | found a match?
    BEQ.B	FLUSH_EXIT_OK                         | no matches left, done ->
    MOVEA.L	A1,A4                               | A4 = best match buffer
    MOVE.L	0x12(A4),D4                          | D4 = CBHDBlk of last flushed
    BRA.B	FLUSH_WRITE_BUF                       | go flush it ->
| ----------------------------------------------------------
|
| FLUSH_CHK_MATCH - FlushCache: check if buffer matches flush criteria
|
| Called during boot.
FLUSH_CHK_MATCH:
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BNE.B	FLUSH_SEARCH_NEXT                     | yes, skip ->
    CMPA.L	0x8(A4),A2                           | CBHVCBPtr: same volume?
    BNE.B	FLUSH_SEARCH_NEXT                     | no, skip ->
    TST.W	D1                                    | volume-level flush?
    BLT.B	FLUSH_VOL_MATCH                       | yes, match all on volume ->
    CMP.L	0xC(A4),D3                            | CBHFlNum: same file number?
    BNE.B	FLUSH_SEARCH_NEXT                     | no, skip ->
    CMP.B	0x1B(A4),D6                           | CBHFkType: same fork?
    BNE.B	FLUSH_SEARCH_NEXT                     | no, skip ->
FLUSH_VOL_MATCH:
    TST.L	D2                                    | any match yet?
    BEQ.B	FLUSH_CHK_ORDER                       | no, accept this one ->
    CMP.L	0x12(A4),D2                           | CBHDBlk < current match?
    BLT.B	FLUSH_SEARCH_NEXT                     | no, keep better match ->
FLUSH_CHK_ORDER:
    CMP.L	0x12(A4),D4                           | CBHDBlk > last flushed?
    BGE.B	FLUSH_SEARCH_NEXT                     | no, already flushed ->
    MOVE.L	0x12(A4),D2                          | D2 = new best match block
    MOVEA.L	A4,A1                               | A1 = best match buffer
    BRA.B	FLUSH_SEARCH_NEXT                     | keep searching ->
| ----------------------------------------------------------
|
| FLUSH_WRITE_BUF - FlushCache: flush next matching buffer in disk order
|
| Called during boot.
FLUSH_WRITE_BUF:
    BTST	#0x7,0x1A(A4)                          | CBHFlags: dirty?
    BEQ.B	FLUSH_CHK_TRASH                       | no ->
    JSR	WRITEBLOCK(PC)                          | write buffer to disk
    BCLR	#0x7,0x1A(A4)                          | clear dirty flag
FLUSH_CHK_TRASH:
    BTST	#0x0,D5                                | trash option requested?
    BEQ.B	FLUSH_RESTART                         | no, keep buffer ->
    BTST	#0x6,0x1A(A4)                          | CBHFlags: in use?
    BNE.B	FLUSH_RESTART                         | yes, keep it ->
    BSR.W	MarkEmpty                             | mark buffer empty
    BRA.B	FLUSH_RESTART                         | continue flushing ->
| ----------------------------------------------------------
|
| FLUSH_EXIT_OK - FlushCache exit: no error
|
| Called during boot.
FLUSH_EXIT_OK:
    CLR.W	D0                                    | result = noErr
    MOVEM.L	(A6)+,D1-D6/A0-A4                   | restore regs
    MOVE.L	(A6)+,-(A7)                          | restore return address to stack
    TST.W	D0                                    | set condition codes
    RTS                                         | return from FlushCache
| Called by: FLUSHMDB, MOUNTVOL_SKIP_2, L_MFILEREAD_CONT_6, FILECLOSE_NO_2, READBM_NEXT_3 (and 4 more)
GETBLOCK:
    MOVE.L	(0x704).W,-(A7)                      | HFS vector: GetBlock trampoline
    RTS                                         | dispatch via vector
VGETBLOCK:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1-D7/A1-A5,-(A6)                   | save regs
    MOVE.B	D1,D3                                | D3 = option flags (GBread/GBexist/GBnew...)
    MOVEA.L	A1,A3                               | A3 = cache queue header (CQH)
    MOVE.W	D0,D1                                | D1 = file refnum or volume refnum
    BLT.W	GB_VOL_REF                            | negative = volume block ->
    MOVEA.L	(FCBSPtr).W,A1                      | FCB array base
    MOVEA.L	0x14(A1,D1.W),A2                    | A2 = VCB ptr
    MOVE.L	0x0(A1,D1.W),D7                      | D7 = file number
    BTST	#0x1,0x4(A1,D1.W)                      | resource fork?
    SNE.B	D4                                    | D4 = fork type ($FF=rsrc, $00=data)
    MOVEA.L	A3,A4                               | start at top of queue
| Called by: GB_FILE_SEARCH
GB_FILE_SEARCH:
    MOVEA.L	(A4),A4                             | next buffer in queue
    CMPA.L	A3,A4                                | back to top?
    BEQ.B	GB_CHK_OWNBUF                         | not found in cache ->
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BNE.B	GB_FILE_SEARCH                        | yes, skip ->
    CMPA.L	0x8(A4),A2                           | CBHVCBPtr: same volume?
    BNE.B	GB_FILE_SEARCH                        | no ->
    CMP.L	0xC(A4),D7                            | CBHFlNum: same file?
    BNE.B	GB_FILE_SEARCH                        | no ->
    CMP.B	0x1B(A4),D4                           | CBHFkType: same fork?
    BNE.B	GB_FILE_SEARCH                        | no ->
    CMP.L	0x16(A4),D2                           | CBHFlBlk: same file block?
    BEQ.W	GB_FOUND_IT                           | yes, found it ->
    BRA.B	GB_FILE_SEARCH                        | continue search ->
| ----------------------------------------------------------
|
| GB_CHK_OWNBUF - GetBlock: file block not in cache, check OwnBuf
|
| Called during boot.
GB_CHK_OWNBUF:
    BSR.W	CACHE                                 | local (OwnBuf) cache buffer?
    BEQ.B	GB_MAP_BLOCK                          | no OwnBuf ->
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BNE.B	GB_MAP_BLOCK                          | yes, unusable ->
    CMP.L	0x16(A4),D2                           | CBHFlBlk: same file block?
    BEQ.W	GB_EXIT_OK                            | yes, use OwnBuf ->
GB_MAP_BLOCK:
    MOVEM.L	D3-D4,-(A6)                         | save option flags and fork type
    MOVEQ.L	#0x0,D4                             | cache buffer size
    MOVE.W	0xA(A3),D4                           | CQHBufSize
    MOVE.L	D2,D5                                | file block number
    LSL.L	#0x8,D5                               | x 256
    ADD.L	D5,D5                                 | x 2 = file position (x 512)
    JSR	LG2PHYS(PC)                             | map to logical disk block
    MOVE.L	D2,D6                                | D6 = file block number
    MOVE.L	D3,D2                                | D2 = disk block number
    MOVEM.L	(A6)+,D3-D4                         | restore option flags and fork type
    TST.W	D0                                    | mapping error?
    BNE.W	GB_EXIT                               | exit with error ->
    MOVE.L	0x18(A1,D1.W),D0                     | local OwnBuf?
    BEQ.B	GB_CACHE_SEARCH                       | no, search general cache ->
    BSR.W	FLUSH_DIRTY                           | flush OwnBuf if dirty
    MOVE.L	D2,0x12(A4)                          | CBHDBlk = disk block
    MOVE.L	D6,0x16(A4)                          | CBHFlBlk = file block
    CLR.B	0x1A(A4)                              | clear CBHFlags
    JSR	READOWNBUF(PC)                          | read block into OwnBuf
    BEQ.W	GB_EXIT_OK                            | success ->
    BSR.W	MarkEmpty                             | read error: mark empty
    BRA.W	GB_EXIT                               | exit with error ->
| ----------------------------------------------------------
|
| GB_VOL_REF - GetBlock: logical block on volume was requested (GBVolRef)
|
| Called during boot.
GB_VOL_REF:
    MOVEQ.L	#0x0,D1                             | no file refnum
    MOVEQ.L	#0x0,D7                             | no file number
    MOVEQ.L	#-0x1,D6                            | no file block number
    MOVEQ.L	#0x0,D4                             | no fork type
GB_CACHE_SEARCH:
    SUBA.L	A0,A0                                | A0 = ptr to empty buffer (none yet)
    SUBA.L	A1,A1                                | A1 = ptr to clean buffer (none yet)
    SUBA.L	A5,A5                                | A5 = ptr to dirty buffer (none yet)
    MOVEA.L	A3,A4                               | start at top of queue
GB_SCAN_NEXT:
    MOVEA.L	(A4),A4                             | next buffer in queue
    CMPA.L	A3,A4                                | back to top?
    BEQ.B	GB_SELECT                             | yes, select best candidate ->
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BEQ.B	GB_CHK_NONEMPTY                       | no ->
    MOVEA.L	A4,A0                               | save ptr to empty buffer
    BRA.B	GB_SCAN_NEXT                          | continue search ->
| ----------------------------------------------------------
|
| GB_CHK_NONEMPTY - GetBlock: non-empty buffer, check if it's the one we want
|
| Called during boot.
GB_CHK_NONEMPTY:
    TST.W	D1                                    | file-level search?
    BNE.B	GB_CHK_INUSE                          | yes, won't match by disk block ->
    CMPA.L	0x8(A4),A2                           | CBHVCBPtr: same volume?
    BNE.B	GB_CHK_INUSE                          | no ->
    CMP.L	0x12(A4),D2                           | CBHDBlk: same disk block?
    BEQ.W	GB_FOUND_IT                           | yes, found it ->
GB_CHK_INUSE:
    BTST	#0x6,0x1A(A4)                          | CBHFlags: in use?
    BNE.B	GB_SCAN_NEXT                          | yes, skip ->
    BTST	#0x7,0x1A(A4)                          | CBHFlags: dirty?
    BEQ.B	GB_SAVE_CLEAN                         | no, this is clean ->
    MOVEA.L	A4,A5                               | save ptr to dirty buffer
    BRA.B	GB_SCAN_NEXT                          | continue search ->
| ----------------------------------------------------------
|
| GB_SAVE_CLEAN - GetBlock: found a clean (not dirty) non-in-use buffer
|
| Called during boot.
GB_SAVE_CLEAN:
    MOVEA.L	A4,A1                               | save ptr to clean buffer
    BRA.B	GB_SCAN_NEXT                          | continue search ->
| ----------------------------------------------------------
|
| GB_SELECT - GetBlock: block not found, select a buffer to use (GBSelect)
|
| Called during boot.
GB_SELECT:
    BTST	#0x1,D3                                | GBexist: must already exist?
    BEQ.B	GB_PICK_BUFFER                        | no ->
    MOVEQ.L	#0x3,D0                             | result = ChNotFound
    BRA.W	GB_EXIT                               | exit ->
| ----------------------------------------------------------
|
| GB_PICK_BUFFER - GetBlock: select best available buffer (empty > clean > dirty)
|
| Called during boot.
GB_PICK_BUFFER:
    MOVEA.L	A0,A4                               | try empty buffer first
    MOVE.L	A4,D0                                | have one?
    BNE.B	GB_ASSIGN                             | yes, use it ->
    MOVEA.L	A1,A4                               | try clean buffer
    MOVE.L	A4,D0                                | have one?
    BNE.B	GB_ASSIGN                             | yes, use it ->
    MOVEA.L	A5,A4                               | try dirty buffer
    MOVE.L	A4,D0                                | have one?
    BNE.B	GB_EVICT_DIRTY                        | yes, flush first ->
    MOVEQ.L	#0x1,D0                             | result = ChNoBuf (all in use)
    BRA.W	GB_EXIT                               | exit ->
| ----------------------------------------------------------
|
| GB_EVICT_DIRTY - GetBlock: must evict dirty buffer (flush all blocks of same file first)
|
GB_EVICT_DIRTY:
    MOVEM.L	D0-D2/A1-A2,-(A6)                   | save regs over flush
    MOVE.B	(SysCRefCnt).W,D2                    | save CacheFlag
    ST.B	(SysCRefCnt).W                         | force real flush
    MOVEQ.L	#0x0,D1                             | regular flush options
    MOVEA.L	A3,A1                               | cache queue header
    MOVEA.L	0x8(A4),A2                          | CBHVCBPtr for dirty block
    MOVE.W	0x10(A4),D0                          | CBHFRefNum
    BGT.B	GB_FLUSH_VREF                         | file block ->
    MOVE.W	0x4E(A2),D0                          | vcbVRefNum instead
GB_FLUSH_VREF:
    JSR	FLUSHCACHE(PC)                          | flush all blocks of same file
    MOVE.B	D2,(SysCRefCnt).W                    | restore CacheFlag
    MOVEM.L	(A6)+,D0-D2/A1-A2                   | restore regs
    CMPA.L	(SysCtlCPtr).W,A3                    | control cache?
    BNE.B	GB_ASSIGN                             | no ->
    ST.B	(SysCRefCnt).W                         | force flush: cache is full
| GBAssign: assign buffer to new block, read it from disk
GB_ASSIGN:
    BSET	#0x6,0x1A(A4)                          | set in-use flag
    BCLR	#0x5,0x1A(A4)                          | clear empty flag
    BCLR	#0x7,0x1A(A4)                          | clear dirty flag
    MOVE.L	A2,0x8(A4)                           | CBHVCBPtr = volume
    MOVE.L	D2,0x12(A4)                          | CBHDBlk = disk block
    MOVE.W	D1,0x10(A4)                          | CBHFRefNum = file refnum
    MOVE.L	D7,0xC(A4)                           | CBHFlNum = file number
    MOVE.B	D4,0x1B(A4)                          | CBHFkType = fork type
    MOVE.L	D6,0x16(A4)                          | CBHFlBlk = file block
    BTST	#0x2,D3                                | GBnew: no-read requested?
    BNE.B	GB_REQUEUE                            | yes, skip read ->
GB_READ_BLK:
    CLR.L	(BufTgDate).W                         | clear tag date
    JSR	READOWNBUF(PC)                          | read block from disk
    BNE.B	GB_READ_ERR                           | error ->
    JSR	TFSVCBTST(PC)                           | HFS volume?
    BNE.B	GB_REQUEUE                            | no, skip write-count scavenge ->
    MOVE.L	(BufTgDate).W,D0                     | get tag write-count
    CMP.L	0x64(A2),D0                           | vcbWrCnt: already up to date?
    BLS.B	GB_REQUEUE                            | yes ->
    MOVE.L	D0,0x64(A2)                          | update vcbWrCnt
    BRA.B	GB_REQUEUE                            | ->
| ----------------------------------------------------------
|
| GB_READ_ERR - GetBlock: read error, mark buffer empty
|
GB_READ_ERR:
    CLR.B	0x1A(A4)                              | clear CBHFlags
    BSR.W	MarkEmpty                             | mark buffer empty
    BRA.B	GB_EXIT                               | exit with error ->
| ----------------------------------------------------------
|
| GB_FOUND_IT - GetBlock: found requested buffer (GBFoundIt)
|
| Called during boot.
GB_FOUND_IT:
    BSET	#0x6,0x1A(A4)                          | set in-use (was it already?)
    BEQ.B	GB_CHK_REREAD                         | no, buffer is ours ->
    MOVEQ.L	#0x2,D0                             | result = ChInUse
    BRA.B	GB_EXIT                               | exit ->
| ----------------------------------------------------------
|
| GB_CHK_REREAD - GetBlock: check for forced re-read (GBread flag)
|
| Called during boot.
GB_CHK_REREAD:
    BTST	#0x0,D3                                | GBread: forced re-read?
    BNE.B	GB_READ_BLK                           | yes, re-read ->
| GBReQueue: re-queue buffer for LRU
GB_REQUEUE:
    JSR	DQCBuf(PC)                              | detach buffer from queue
    MOVEA.L	A3,A0                               | queue header
    JSR	NQCBuf(PC)                              | insert at MRU position
    BTST	#0x3,D3                                | GBrelease: immediate release?
    BEQ.B	GB_EXIT_OK                            | no ->
    BCLR	#0x6,0x1A(A4)                          | clear in-use flag
GB_EXIT_OK:
    LEA.L	0x1C(A4),A0                           | A0 = CBHData (buffer data area)
    MOVEQ.L	#0x0,D0                             | result = noErr
| Called by: GB_MAP_BLOCK, GB_SELECT, GB_PICK_BUFFER, GB_READ_ERR, GB_FOUND_IT
GB_EXIT:
    MOVEM.L	(A6)+,D1-D7/A1-A5                   | restore regs
    MOVE.L	(A6)+,-(A7)                          | restore return address to stack
    TST.W	D0                                    | set condition codes
    RTS                                         | return from GetBlock
INITCACHE:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1-D3/A0/A4,-(A6)                   | save regs
    MOVE.W	D0,D2                                | D2 = number of buffers
    MOVE.W	D1,D3                                | D3 = buffer data size
    ADDI.W	#0x1C,D1                             | + CBH header size (lenCBH=28)
    MOVEQ.L	#0x0,D0                             | total allocation size
    MOVE.W	D2,D0                                | = num buffers

    MULU.W	D1,D0                                | D0 = numBufs * (bufSize + CBH header)
    ADDI.L	#0xC,D0                              | + CQH header (lenCQH=12)
    _NewPtrSysClear                             | allocate cache memory
    BNE.B	INITC_EXIT                            | error ->
    MOVEA.L	A0,A1                               | A1 = cache queue header (CQH)
    MOVE.L	A1,(A1)                              | CQH FLink = self (empty circular)
    MOVE.L	A1,0x4(A1)                           | CQH BLink = self
    MOVE.W	D2,0x8(A1)                           | CQHNumBuf = number of buffers
    MOVE.W	D3,0xA(A1)                           | CQHBufSize = buffer data size
    LEA.L	0xC(A1),A4                            | A4 = first buffer
    SUBQ.W	#0x1,D2                              | adjust for DBF
INITC_LOOP:
    MOVEA.L	A1,A0                               | queue header
    JSR	NQCBuf(PC)                              | insert buffer into queue
    BSR.B	MarkEmpty                             | mark buffer empty
    ADDA.L	D1,A4                                | advance to next buffer
    DBF.W	D2,INITC_LOOP                         | loop for all buffers
    CLR.W	D0                                    | result = noErr
INITC_EXIT:
    MOVEM.L	(A6)+,D1-D3/A0/A4                   | restore regs
    MOVE.L	(A6)+,-(A7)                          | restore return address to stack
    TST.W	D0                                    | set condition codes
    RTS                                         | return from InitCache
| ----------------------------------------------------------
|
| MarkEmpty - MarkEmpty: mark buffer empty and zero disk block
|
| Called during boot.
MarkEmpty:
    BSET	#0x5,0x1A(A4)                          | set CBHempty flag
    CLR.L	0x12(A4)                              | clear CBHDBlk
    RTS                                         | return from MarkEmpty
| Called by: HFSCATMOVE_CONT_3, SETFILEINFO_MFS_FLUSH, BLKALLOC_OK_2, BLKALLOC_NO_5, BLKDEALLOC_CONT (and 12 more)
MARKBLOCK:
    MOVE.L	(0x708).W,-(A7)                      | HFS vector: MarkBlock trampoline
    RTS                                         | dispatch via vector
VMARKBLOCK:
    BSET	#0x7,-0x2(A0)                          | set dirty flag (CBHFlags at data-2)
    RTS                                         | return from MarkBlock
| Called by: HFSE_NO_6, HFSE_CONT_9, HFSE_NO_7, CREATE_FOUND, WRPART (and 1 more)
MARKA5BLOCK:
    EXG	A0,A5                                   | swap: A5 has the data ptr
    BSR.B	MARKBLOCK                             | mark block dirty via vector
    EXG	A0,A5                                   | restore A0 and A5
    RTS                                         | return from MarkA5Block
| Called by: FLUSHMDB, MOUNTVOL_SKIP_2, HFSE_OK_3, FILECLOSE_NO_2, BTOPEN_RELBLK (and 3 more)
RELBLOCK:
    MOVE.L	(0x70C).W,-(A7)                      | HFS vector: RelBlock trampoline
    RTS                                         | dispatch via vector
VRELBLOCK:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1/A0-A1/A3-A4,-(A6)                | save regs
    LEA.L	-0x1C(A0),A4                          | A4 = CBH (back up lenCBH from data)
    BCLR	#0x6,0x1A(A4)                          | clear in-use flag
    BTST	#0x1,D1                                | RBtrash: trash buffer?
    BEQ.B	RB_CHK_DIRTY                          | no ->
    BSR.B	MarkEmpty                             | mark buffer empty
    BCLR	#0x7,0x1A(A4)                          | clear dirty flag
    BRA.B	RB_EXIT_OK                            | done ->
| ----------------------------------------------------------
|
| RB_CHK_DIRTY - RelBlock: check dirty/write options
|
RB_CHK_DIRTY:
    BTST	#0x2,D1                                | RBdirty: mark dirty?
    BEQ.B	RB_CHK_WRITE                          | no ->
    BSET	#0x7,0x1A(A4)                          | set dirty flag
RB_CHK_WRITE:
    BTST	#0x0,D1                                | RBwrite: force write to disk?
    BEQ.B	RB_EXIT_OK                            | no ->
    MOVEA.L	A1,A3                               | A3 = CQH (for WriteBlock)
    JSR	WRITEBLOCK(PC)                          | write block to disk
    BCLR	#0x7,0x1A(A4)                          | clear dirty flag
    BRA.B	RB_EXIT                               | done ->
| RBExit
RB_EXIT_OK:
    CLR.W	D0                                    | result = noErr
RB_EXIT:
    MOVEM.L	(A6)+,D1/A0-A1/A3-A4                | restore regs
    MOVE.L	(A6)+,-(A7)                          | restore return address to stack
    TST.W	D0                                    | set condition codes
    RTS                                         | return from RelBlock
TRASHVBLKS:
    MOVE.L	(0x714).W,-(A7)                      | HFS vector: TrashVBlks trampoline
    RTS                                         | dispatch via vector
VTRASHVBLKS:
    MOVEM.L	A3-A4,-(A7)                         | save regs
    MOVEA.L	A1,A3                               | A3 = cache queue header
    MOVEA.L	A3,A4                               | start at top of queue
TV_SCAN_NEXT:
    MOVEA.L	(A4),A4                             | next buffer in queue
    CMPA.L	A3,A4                                | back to top?
    BEQ.B	TV_EXIT                               | done ->
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BNE.B	TV_SCAN_NEXT                          | yes, skip ->
    CMPA.L	0x8(A4),A2                           | CBHVCBPtr: same volume?
    BNE.B	TV_SCAN_NEXT                          | no, skip ->
    BSR.W	MarkEmpty                             | invalidate: mark empty
    BRA.B	TV_SCAN_NEXT                          | continue ->
| ----------------------------------------------------------
|
| TV_EXIT
|
TV_EXIT:
    MOVEM.L	(A7)+,A3-A4                         | restore regs
    RTS                                         | return from TrashVBlks
TRASHFBLOCKS:
    MOVEM.L	D0-D6/A0-A4,-(A7)                   | save regs
    MOVE.L	D0,D3                                | D3 = extent info (block range)
    MOVEQ.L	#0x0,D1                             | D1 = 0 (all matching blocks)
    BRA.B	L_TrashBlocks                         | -> TrashBlocks
TRASHBLOCKS:
    MOVEM.L	D0-D6/A0-A4,-(A7)                   | save regs
    MOVEQ.L	#0x9,D3                             | shift for 512-byte blocks
    MOVE.L	D1,D4                                | D4 = start byte offset
    LSR.L	D3,D4                                 | / 512 = start block number
    MOVEQ.L	#-0x1,D5                            | sentinel
    CMP.L	D2,D5                                 | unlimited range?
    BEQ.B	TB_CVT_END_BLK                        | yes, trash from start ->
    MOVE.L	D2,D5                                | D5 = byte count
    ADD.L	D1,D5                                 | + start offset
    SUBQ.L	#0x1,D5                              | - 1 = last byte in range
TB_CVT_END_BLK:
    LSR.L	D3,D5                                 | / 512 = end block number
    MOVE.W	D0,D1                                | D1 = file refnum
    BLE.B	TB_EXIT                               | invalid refnum ->
    MOVEA.L	(FCBSPtr).W,A1                      | FCB array base
    MOVEA.L	0x14(A1,D1.W),A2                    | A2 = VCB ptr
    MOVE.L	0x0(A1,D1.W),D3                      | D3 = file number
    BTST	#0x1,0x4(A1,D1.W)                      | resource fork?
    SNE.B	D6                                    | D6 = fork type flag
    BSR.W	CACHE                                 | check OwnBuf first
    BEQ.B	L_TrashBlocks                         | no OwnBuf ->
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BNE.B	L_TrashBlocks                         | yes ->
    MOVE.L	0x16(A4),D0                          | CBHFlBlk
    CMP.L	D4,D0                                 | before trash range?
    BLT.B	L_TrashBlocks                         | yes ->
    CMP.L	D5,D0                                 | after trash range?
    BGT.B	L_TrashBlocks                         | yes ->
    BSR.W	MarkEmpty                             | invalidate OwnBuf
| Called by: TB_CVT_END_BLK, TRASHFBLOCKS
L_TrashBlocks:
    MOVE.L	(0x710).W,-(A7)                      | HFS vector: TrashBlocks trampoline
    RTS                                         | dispatch via vector
VTRASHBLOCKS:
    MOVEA.L	0x54(A2),A3                         | A3 = volume cache queue (vcbCtlBuf)
    MOVEA.L	A3,A4                               | start at top of queue
| Called by: TB_SCAN_NEXT, TB_INVALIDATE
TB_SCAN_NEXT:
    MOVEA.L	(A4),A4                             | next buffer in queue
    CMPA.L	A3,A4                                | back to top?
    BEQ.B	TB_EXIT                               | done ->
    BTST	#0x5,0x1A(A4)                          | CBHFlags: empty?
    BNE.B	TB_SCAN_NEXT                          | yes, skip ->
    CMPA.L	0x8(A4),A2                           | CBHVCBPtr: same volume?
    BNE.B	TB_SCAN_NEXT                          | no ->
    CMP.L	0xC(A4),D3                            | CBHFlNum: same file?
    BNE.B	TB_SCAN_NEXT                          | no ->
    TST.W	D1                                    | trash all blocks? (D1=0)
    BEQ.B	TB_INVALIDATE                         | yes ->
    CMP.B	0x1B(A4),D6                           | CBHFkType: same fork?
    BNE.B	TB_SCAN_NEXT                          | no ->
    MOVE.L	0x16(A4),D0                          | CBHFlBlk
    CMP.L	D4,D0                                 | before range?
    BLT.B	TB_SCAN_NEXT                          | yes ->
    CMP.L	D5,D0                                 | after range?
    BGT.B	TB_SCAN_NEXT                          | yes ->
TB_INVALIDATE:
    BSR.W	MarkEmpty                             | invalidate buffer
    BRA.B	TB_SCAN_NEXT                          | continue scan ->
| ----------------------------------------------------------
|
| TB_EXIT
|
TB_EXIT:
    MOVEM.L	(A7)+,D0-D6/A0-A4                   | restore regs
    RTS                                         | return from TrashBlocks
CACHERDIP:
    MOVE.L	(0x71C).W,-(A7)                      | HFS vector: CacheRdIP trampoline
    RTS                                         | dispatch via vector
VCACHERDIP:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVE.L	D3,-(A6)                             | save D3
    MOVEM.L	D1/A1,-(A6)                         | save D1/A1
    MOVE.W	D1,D0                                | D0 = file refnum
    MOVEQ.L	#0x0,D1                             | no options
    MOVEA.L	0x54(A2),A1                         | A1 = volume cache queue (vcbCtlBuf)
    BSR.W	FLUSHCACHE                            | flush file's cache blocks
    MOVEM.L	(A6)+,D1/A1                         | restore D1/A1
    BNE.B	RDIP_DONE                             | error ->
    JSR	LG2PHYS(PC)                             | map file block to disk block
    BNE.B	RDIP_DONE                             | error ->
    JSR	RDBLOCKS(PC)                            | read blocks from disk
RDIP_DONE:
    BRA.B	CACHEWRIP_EXIT                        | -> common exit
CACHEWRIP:
    MOVE.L	(0x718).W,-(A7)                      | HFS vector: CacheWrIP trampoline
    RTS                                         | dispatch via vector
VCACHEWRIP:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVE.L	D3,-(A6)                             | save D3
    JSR	LG2PHYS(PC)                             | map file block to disk block
    BNE.B	CACHEWRIP_EXIT                        | error ->
    MOVEM.L	D1-D2,-(A6)                         | save D1-D2
    MOVE.W	D1,D0                                | file refnum
    MOVE.L	D5,D1                                | start byte offset
    MOVE.L	D6,D2                                | byte count
    BSR.W	TRASHBLOCKS                           | trash stale cached blocks
    MOVEM.L	(A6)+,D1-D2                         | restore D1-D2
    JSR	WRBLOCKS(PC)                            | write blocks to disk
CACHEWRIP_EXIT:
    MOVE.L	(A6)+,D3                             | restore D3
    MOVE.L	(A6)+,-(A7)                          | restore return address to stack
    TST.W	D0                                    | set condition codes
    RTS                                         | return from CacheRdIP/CacheWrIP
| ----------------------------------------------------------
|
| DQCBuf - DQCBuf: dequeue cache buffer from circular list
|
| Called during boot.
DQCBuf:
    MOVEM.L	A0-A1,-(A7)                         | save regs
    MOVEA.L	0x4(A4),A0                          | A0 = prev (BLink)
    MOVEA.L	(A4),A1                             | A1 = next (FLink)
    MOVE.L	A1,(A0)                              | prev->FLink = next
    MOVE.L	A0,0x4(A1)                           | next->BLink = prev
    MOVEM.L	(A7)+,A0-A1                         | restore regs
    RTS                                         | return from DQCBuf
| ----------------------------------------------------------
|
| NQCBuf - NQCBuf: enqueue cache buffer after A0 in circular list
|
| Called during boot.
NQCBuf:
    MOVE.L	A1,-(A7)                             | save A1
    MOVEA.L	(A0),A1                             | A1 = old next (A0->FLink)
    MOVE.L	A1,(A4)                              | new->FLink = old next
    MOVE.L	A4,0x4(A1)                           | old next->BLink = new
    MOVE.L	A4,(A0)                              | A0->FLink = new
    MOVE.L	A0,0x4(A4)                           | new->BLink = A0
    MOVEA.L	(A7)+,A1                            | restore A1
    RTS                                         | return from NQCBuf
| Apple source module: CACHEIO
READOWNBUF:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1-D7/A0-A5,-(A6)                   | save regs
    MOVEQ.L	#0x0,D1                             | D1 = 0 (read operation)
    BRA.B	BASICIO_SETUP                         | -> set up I/O params
WRITEOWNBUF:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1-D7/A0-A5,-(A6)                   | save regs
    BRA.B	WBLK_SETUP_TAGS                       | -> set up tags for write
WRITEBLOCK:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1-D7/A0-A5,-(A6)                   | save regs
    MOVEA.L	0x8(A4),A2                          | A2 = CBHVCBPtr
    MOVE.L	0x12(A4),D0                          | D0 = CBHDBlk
    MOVE.W	0x10(A4),D1                          | D1 = CBHFRefNum
    BEQ.B	BASICIO_VOLBLK                        | volume block (no FCB) ->
WBLK_SETUP_TAGS:
    MOVEA.L	(FCBSPtr).W,A1                      | FCB array base
    MOVE.L	0x16(A4),D0                          | D0 = CBHFlBlk
BASICIO_VOLBLK:
    BSR.W	P_SetUpTags                           | set up disk tags
    MOVEQ.L	#0x1,D1                             | D1 = 1 (write operation)
BASICIO_SETUP:
    LEA.L	(Params).W,A0                         | A0 = I/O parameter block
    MOVE.W	0x48(A2),0x16(A0)                    | ioVRefNum from VCB
    MOVE.W	0x4A(A2),0x18(A0)                    | ioDrvNum from VCB
    LEA.L	0x1C(A4),A1                           | A1 = CBHData (buffer data area)
    MOVE.L	A1,0x20(A0)                          | ioBuffer = buffer data
    MOVE.W	#0x1,0x2C(A0)                        | ioPosMode = fsFromStart
    MOVE.L	#0x200,0x24(A0)                      | ioReqCount = 512 bytes
    MOVE.L	0x12(A4),D0                          | CBHDBlk
    LSL.L	#0x8,D0                               | x 256
    ADD.L	D0,D0                                 | x 2 = byte position (x 512)
    MOVE.L	D0,0x2E(A0)                          | ioPosOffset = disk position
L_BasicIO:
    MOVE.L	(0x720).W,-(A7)                      | HFS vector: BasicIO trampoline
    RTS                                         | dispatch via vector
VBASICIO:
    MOVE.L	A6,(HFSStkPtr).W                     | save HFS stack pointer
    TST.B	(NxtDB).W                             | async I/O in progress?
    BNE.B	BASICIO_ASYNC                         | yes, use async path ->
    TST.B	D1                                    | write operation?
    BNE.B	BASICIO_WRITE                         | yes ->
    _Read                                       | synchronous read
    BRA.B	BASICIO_RECOVER                       | -> recover context
| ----------------------------------------------------------
|
| BASICIO_WRITE - synchronous write
|
| Called during boot.
BASICIO_WRITE:
    _Write                                      | synchronous write
    BRA.B	BASICIO_RECOVER                       | -> recover context
| ----------------------------------------------------------
|
| BASICIO_ASYNC - async I/O path
|
BASICIO_ASYNC:
    LEA.L	BASICIO_IOCOMP(PC),A1                 | completion routine address
    MOVE.L	A1,0xC(A0)                           | ioCompletion = our handler
    BCLR	#0x7,(HFSFlags)                        | clear "I/O done" flag
    TST.B	D1                                    | write operation?
    BNE.B	BASICIO_AWRITE                        | yes ->
    _ReadAsync                                  | async read
    BRA.B	BASICIO_ACHK                          | -> check completion
| ----------------------------------------------------------
|
| BASICIO_AWRITE - async write
|
BASICIO_AWRITE:
    _WriteAsync                                 | async write
BASICIO_ACHK:
    BEQ.B	BASICIO_QUEUED                        | I/O queued ok ->
    TST.W	0x10(A0)                              | ioResult: still pending?
    BLE.B	BASICIO_RESUME                        | error or not started ->
BASICIO_QUEUED:
    BSET	#0x7,(HFSFlags)                        | signal I/O done
    BNE.B	BASICIO_RECOVER                       | completion already ran ->
BASICIO_RTS:
    RTS                                         | return from BASICIO_RTS
BASICIO_IOCOMP:
    BSET	#0x7,(HFSFlags)                        | I/O completion: signal done
    BEQ.B	BASICIO_RTS                           | main thread already passed ->
BASICIO_RESUME:
    MOVEM.L	D4-D7/A4-A6,-(A7)                   | save caller's regs
    PEA.L	BASICIO_COMPRET(PC)                   | push cleanup return address
BASICIO_RECOVER:
    MOVEA.L	(HFSStkPtr).W,A6                    | restore HFS stack
    MOVEM.L	(A6)+,D1-D7/A0-A5                   | restore regs
    MOVE.L	(A6)+,-(A7)                          | restore return address to stack
    TST.W	D0                                    | check I/O result
    BEQ.B	BASICIO_DONE                          | noErr ->
    CMPI.W	#0xFFBF,D0                           | ioErr (-65)?
    BEQ.B	BASICIO_DONE                          | treat as success ->
    MOVE.W	D0,(FSTemp4).W                       | save original error
    MOVEQ.L	#-0x24,D0                           | return ioErr (-36)
BASICIO_DONE:
    TST.W	D0                                    | set condition codes
    RTS                                         | return from BasicIO
| ----------------------------------------------------------
|
| BASICIO_COMPRET - completion return: restore interrupted context
|
BASICIO_COMPRET:
    MOVEM.L	(A7)+,D4-D7/A4-A6                   | restore interrupted regs
    RTS                                         | return to interrupted code
RDBLOCKS:
    MOVE.L	(0x724).W,-(A7)                      | HFS vector: BOOT_SCSI_RESCAN trampoline
    RTS                                         | dispatch via vector
VRDBLOCKS:
    MOVEQ.L	#0x0,D0                             | D0 = 0 (read operation)
RDBLK_ENTRY:
    MOVE.L	(A7)+,-(A6)                          | save return address on A6 stack
    MOVEM.L	D1-D7/A0-A5,-(A6)                   | save regs
    MOVEA.L	0x20(A0),A5                         | buffer address
    ADDA.L	0x28(A0),A5                          | + ioActCount (append position)
    MOVE.W	D0,D1                                | D1 = read/write flag
    MOVEQ.L	#0x40,D0                            | no-cache bit mask
    AND.B	0x2D(A0),D0                           | preserve caller's no-cache flag
    LEA.L	(Params).W,A0                         | A0 = I/O parameter block
    MOVE.W	0x4A(A2),0x18(A0)                    | ioDrvNum from VCB
    MOVE.W	0x48(A2),0x16(A0)                    | ioVRefNum from VCB
    MOVE.L	A5,0x20(A0)                          | ioBuffer
    MOVE.L	D6,0x24(A0)                          | ioReqCount = byte count
    MOVE.W	#0x1,0x2C(A0)                        | ioPosMode = fsFromStart
    OR.B	D0,0x2D(A0)                            | merge no-cache flag
    MOVE.L	D3,D0                                | disk block number
    LSL.L	#0x8,D0                               | x 256
    ADD.L	D0,D0                                 | x 2 = byte position (x 512)
    MOVE.L	D0,0x2E(A0)                          | ioPosOffset
    BRA.W	L_BasicIO                             | -> BasicIO
WRBLOCKS:
    MOVE.L	(0x728).W,-(A7)                      | HFS vector: WrBlocks trampoline
    RTS                                         | dispatch via vector
VWRBLOCKS:
    MOVE.L	D5,D0                                | file byte position
    LSR.L	#0x8,D0                               | / 256
    LSR.L	#0x1,D0                               | / 2 = file block for tags
    BSR.B	P_SetUpTags                           | set up disk tags
    MOVEQ.L	#0x1,D0                             | D0 = 1 (write operation)
    BRA.B	RDBLK_ENTRY                           | -> BOOT_SCSI_RESCAN entry
| ----------------------------------------------------------
|
| P_Set Up Tags
|
| Called during boot.
P_SetUpTags:
    MOVE.L	(0x72C).W,-(A7)                      | HFS vector: SetUpTags trampoline
    RTS                                         | dispatch via vector
VSETUPTAGS:
    TST.W	D1                                    | file block? (D1 = refnum)
    BEQ.B	TAGS_VOL_BLOCK                        | no, volume block ->
    MOVE.L	0x0(A1,D1.W),(BufTgFNum).W           | tag: file number from FCB
    MOVE.L	D0,(BufTgFFlg).W                     | tag: file block number
    MOVE.B	0x4(A1,D1.W),(BufTgFFlg).W           | tag: file flags from FCB
    MOVE.L	0x32(A1,D1.W),(BufTgHD20).W          | tag: HD20 field 1
    MOVE.L	0x3A(A1,D1.W),(BufTgHD20_1).W        | tag: HD20 field 2
SETUPTAGS_DATE:
    JSR	TFSVCBTST(PC)                           | HFS volume?
    BNE.B	TAGS_MFS_DATE                         | no, use Time ->
    MOVE.L	0x64(A2),(BufTgDate).W               | tag date = vcbWrCnt
    ADDQ.L	#0x1,0x64(A2)                        | bump vcbWrCnt
    RTS                                         | return from SetUpTags
| ----------------------------------------------------------
|
| TAGS_VOL_BLOCK - set up tags for non-file (volume) block
|
| Called during boot.
TAGS_VOL_BLOCK:
    MOVE.L	D0,(BufTgFFlg).W                     | tag: block number
    MOVEQ.L	#0x1,D0                             | volume block file number = 1
    MOVE.L	D0,(BufTgFNum).W                     | tag: file number
    CLR.L	(BufTgHD20).W                         | clear HD20 tag
    CLR.L	(BufTgHD20_1).W                       | clear HD20 tag 2
    BRA.B	SETUPTAGS_DATE                        | -> set tag date
TAGS_MFS_DATE:
    MOVE.L	(Time).W,(BufTgDate).W               | non-HFS: use system time
    RTS                                         | return from SetUpTags
