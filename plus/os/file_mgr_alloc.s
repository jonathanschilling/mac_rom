| File Manager -- allocation: volume bitmap and file extents
|
| Apple sources: VSM.a, the Volume Space Manager (MacSEROM.lst module
| VSM: BlkAlloc, BlkDealloc, BlkChk, UpdateFree, ReadBM -- allocation
| blocks in the volume bitmap), and FXM.a, the File Extent Manager (module
| FXM: DeallocFile, ExtendFile, MapFBlock, TruncateFile, XFSearch,
| XRUpdate -- a file's extent records and the extents B-tree).
|
| References: Inside Macintosh Vol IV, Ch 19: The File Manager (data
| organization on HFS volumes)

| P_mBlkAlloc -- allocate the disk space.
| ----------------------------------------------------------
|
| P_m Blk Alloc
|
P_mBlkAlloc:
        MOVE.L  (0x77C).w,-(SP)                 | HFS vector: BlkAlloc
        RTS                                     | return from P_mBlkAlloc

| ----------------------------------------------------------
|
| Blk Alloc
|
BlkAlloc:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1/D4-D7/A0-A1,-(A6)            | save caller's registers
        TST     vcbFreeBks(A2)                  | any blocks free at all?
        BEQ     BLKALLOC_EXIT_2                 | exit if not (DskFulErr)
        ANDI    #0x1,D3                         | clear all extra bits for our use
        TST     D2                              | preferred starting block selected?
        BNE.B   BLKALLOC_OK                     | yes, leave it be
        MOVE    vcbAllocPtr(A2),D2              | no, start from volume-wide pointer
        BSET    #0x7,D3                         | set flag to update vcbAllocPtr later
BLKALLOC_OK:
        SWAP    D3                              | get high word accessible
        MOVE    D2,D3                           | store starting block
        SWAP    D3                              | restore flags word for use
        BCLR    #0xF,D3                         | clear wrap-around flag
| blkLoop
BLKALLOC_NO:
        BSR     ReadBM                          | pick up the bitmap block of interest
        TST     D1                              | no errors?
        BMI     BKALLOCEXIT                     | if negative, D0 is now error code
        MOVE    vcbNmAlBlks(A2),A1              | set up the size of the volume
| look for free fragment at or beyond starting block
BLKALLOC_CONT:
        CMP     A1,D2                           | reached end-of-volume?
        BCS.B   BLKALLOC_NO_2                   | if not (D2 < A1), march along
        ROL.L   D1,D0                           | rotate D0 back into place
        MOVE.L  D0,0x0(A0,D6.W)                 | replace it in the buffer (clean)
        CLR     D2                              | reset starting block to beginning
        BSR     ReadBM                          | read the appropriate bitmap block
        BSET    #0xF,D3                         | indicate we wrapped around the EOV
        BNE     BLKALLOC_EXIT_2                 | exit if already set (DskFulErr)
BLKALLOC_NO_2:
        TST     D1                              | any errors occur?
        BMI     BKALLOCEXIT                     | punt on errors
        TST.L   D0                              | if bit 31 clear (free alloc block)?
        BPL.B   BLKALLOC_CONT_2                 | if so, check fragment size
        BSR     READBM_CONT_2                   | FrBitScan: look for another free bit
        BRA.B   BLKALLOC_CONT                   | and keep trying

| ----------------------------------------------------------
|
| BLKALLOC_CONT_2
|
| bkAlFree: found a free fragment, check if big enough
BLKALLOC_CONT_2:
        SUBA    D2,A1                           | change A1 to # blocks left to EOV
        BTST    #0x0,D3                         | is contiguous allocation requested?
        BEQ     BLKALLOC_NO_4                   | if not, just start allocating here
        MOVE.L  D4,-(A6)                        | store original alloc request size
        MOVEM.L D0-D1,-(A6)                     | free up for use in division
        MOVE.L  D4,D0                           | set up to divide
        MOVE    0x1E(A2),D1                     | by allocation block size (vcbAlBlkSiz+2)
        JSR     DivUp(PC)                       | round result up to next alloc block
        MOVE.L  D0,D4                           | D4 = min number of alloc blocks
        MOVEM.L (A6)+,D0-D1                     | restore original registers
        CLR     D7                              | set up fragment length count
BLKALLOC_CONT_3:
        CMP     D7,D4                           | check current length: enough already?
        BLS.B   BLKALLOC_CONT_4                 | if request <= fragment so far, go for it
        CMP     A1,D7                           | reached the edge?
        BEQ.B   BLKALLOC_NO_3                   | if so, fragment wasn't big enough
        TST.L   D0                              | if bit 31 set (allocated block)?
        BMI.B   BLKALLOC_NO_3                   | if so, fragment wasn't big enough
        ADDQ.W  #0x1,D7                         | bump fragment length count
        BSR     READBM_NEXT                     | NextBit: pick up next bit from bitmap
        TST     D1                              | any errors occur?
        BMI     BKALLOCEXIT                     | punt on errors
        BRA.B   BLKALLOC_CONT_3                 | otherwise keep trying
| fragment too small
BLKALLOC_NO_3:
        MOVE.L  (A6)+,D4                        | restore original request size (bytes)
        ADD     D7,D2                           | update starting block
        CMP     A1,D7                           | did we reach to the EOV?
        BCS.B   BLKALLOC_NEXT                   | nope, try this for next position
        BTST    #0xF,D3                         | did we wrap around yet?
        BNE.B   BLKALLOC_EXIT                   | yes, give up: history repeats itself
        BSET    #0xF,D3                         | no, give it another shot
        CLR     D2                              | from the beginning of the volume
BLKALLOC_NEXT:
        BTst    #0xF,D3                         | did we wrap around yet?
        BEQ     BLKALLOC_NO                     | if not, scan on
        SWAP    D3                              | get a hold of the starting block
        CMP     D2,D3                           | are we back where we started?
        BLS.B   BLKALLOC_EXIT                   | if we're beyond the start, quit
        SWAP    D3                              | otherwise, restore D3
        BRA     BLKALLOC_NO                     | and scan on
BLKALLOC_EXIT:
        ROL.L   D1,D0                           | rotate D0 back into place
        MOVE.L  D0,0x0(A0,D6.W)                 | and replace it in the buffer
        BRA     BLKALLOC_EXIT_2                 | exit with DskFulErr, D3=0
| contiguous fragment big enough
BLKALLOC_CONT_4:
        MOVE.L  (A6)+,D4                        | retrieve request size in bytes
        ROL.L   D1,D0                           | restore D0 to original position
        MOVE.L  D0,0x0(A0,D6.W)                 | replace it in the buffer (still clean)
        BSR     ReadBM                          | set up from the current position (D2)
        TST     D1                              | any errors occur?
        BMI     BKALLOCEXIT                     | punt on errors
| bkAllocDoIt: round request to clump size and start allocating
BLKALLOC_NO_4:
        MOVEM.L D0-D1,-(A6)                     | save current bitmap word & bit count
        MOVE.L  D4,D0                           | get requested allocation length (bytes)
        MOVE.L  0x1E(A3),D1                     | get clump size for file (FCBClmpSize)
        JSR     RoundAlloc(PC)                  | divide, rounding up -> size in AlBlks
        MOVE.L  D0,D4                           | stash it away
        MOVEM.L (A6)+,D0-D1                     | retrieve original bitmap word & count
        CLR.L   D7                              | zero out actual allocation counter
| mark blocks allocated from the starting block
BLKALLOC_OK_2:
        TST     D4                              | allocated enough already?
        BEQ.B   BKALLOCOK                       | if so, quit
        CMP     A1,D7                           | is there more here?
        BCC.B   BKALLOCOK                       | if D7 >= A1, reached EOV
        TST.L   D0                              | check bit 31 (current block)
        BMI.B   BKALLOCOK                       | if allocated, stop trying
        TST     vcbFreeBks(A2)                  | does vol think there are bits left?
        BEQ.B   BKALLOCOK                       | nope, we're done
        SUBQ.W  #0x1,vcbFreeBks(A2)             | one fewer now
        JSR     MarkVCB(PC)                     | mark the VCB dirty
        BSET    #0x1F,D0                        | mark current block as allocated
        ADDQ.W  #0x1,D7                         | add one to allocated block count
        SUBQ.W  #0x1,D4                         | subtract one from request size
        JSR     P_mMarkBlock(PC)                | this block is dirty
        BSR     READBM_NEXT                     | NextBit: get next bit from bitmap
        TST     D1                              | check: any errors reading BM?
        BGE.B   BLKALLOC_OK_2                   | if D1>0, all was well
        BRA.B   BKALLOCEXIT                     | otherwise give up (D0 is error code)
| BkAllocOK: allocation is done
BKALLOCOK:
        BTst    #0x7,D3                         | did we start from VCB's AllocPtr?
        BEQ.B   BLKALLOC_NO_5                   | if not, never mind
        MOVE    D2,D4                           | prepare new allocPtr
        CMP     vcbNmAlBlks(A2),D4              | is it at EOV?
        BCS.B   BLKALLOC_OK_3                   | if CS, D4 < NmAlBlks: ok
        CLR     D4                              | if D4 >= NmAlBlks, wrap around
BLKALLOC_OK_3:
        MOVE    D4,vcbAllocPtr(A2)              | update VCB's allocation pointer
BLKALLOC_NO_5:
        ROL.L   D1,D0                           | rotate bitmap word back into place
        MOVE.L  D0,0x0(A0,D6.W)                 | put it back where it came from
        JSR     P_mMarkBlock(PC)                | mark the buffer dirty
        MOVE.L  D7,D3                           | return actual allocation size
        MOVEQ.L #0x0,D0                         | sweet success
| BkAllocExit
BKALLOCEXIT:
        MOVEM.L (A6)+,D1/D4-D7/A0-A1            | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes for return
        RTS                                     | and call it a day
| bkAllocFull
BLKALLOC_EXIT_2:
        MOVEQ.L #0x0,D3                         | no blocks allocated
        MOVEQ.L #-0x22,D0                       | disk is full (DskFulErr)
        BRA.B   BKALLOCEXIT                     | return with error

| P_mBlkDealloc -- deallocate the space.
| ----------------------------------------------------------
|
| P_m Blk Dealloc
|
P_mBlkDealloc:
        MOVE.L  (0x780).w,-(SP)                 | HFS vector: BlkDealloc
        RTS                                     | return from P_mBlkDealloc

| ----------------------------------------------------------
|
| Blk Dealloc
|
BlkDealloc:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D6/A0,-(A6)                  | save registers for use
        MOVEQ.L #0x0,D0                         | set up completion code
        TST     D3                              | check block count
        BEQ.B   BLKDEALLOC_DONE                 | if zero, we're done
        BSR     ReadBM                          | pick up the relevant bitmap information
BLKDEALLOC_CONT:
        TST     D1                              | any error occur?
        BMI.B   BLKDEALLOC_DONE                 | if not, keep going
        BCLR    #0x1F,D0                        | free up the block
        JSR     P_mMarkBlock(PC)                | call helper
        ADDQ.W  #0x1,vcbFreeBks(A2)             | one more free block on volume
        JSR     MarkVCB(PC)                     | call helper
        SUBQ.W  #0x1,D3                         | decrement blocks remaining
        BEQ.B   BLKDEALLOC_OK                   | ok ->
        BSR     READBM_NEXT                     | call helper
        BRA.B   BLKDEALLOC_CONT                 | continue deallocating
BLKDEALLOC_OK:
        ROL.L   D1,D0                           | rotate D0 back into position
        MOVE.L  D0,0x0(A0,D6.W)                 | put bitmap word back
        MOVEQ.L #0x0,D0                         | success
BLKDEALLOC_DONE:
        MOVEM.L (A6)+,D1-D6/A0                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit BlkDealloc

| ----------------------------------------------------------
|
| Blk Chk
|
| BlkChk: check and fix bitmap for extent record blocks
BlkChk:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D7/A1,-(A6)                  | save registers
        MOVE.L  A0,A1                           | A1 = ptr to extent record
        MOVEQ.L #0x0,D3                         | D3 = error flag (0 = ok)
        MOVEQ.L #0x0,D7                         | D7 = extent record offset index
BLKCHK_NEXT:
        MOVE    0x0(A1,D7.W),D2                 | D2 = start alloc block from extent
        MOVEQ.L #0x0,D4                         | clear high word
        MOVE    0x2(A1,D7.W),D4                 | D4 = block count from extent
        BEQ.B   BLKCHK_DONE                     | empty extent, done ->
        BSR.B   ReadBM                          | read bitmap for start block
        BRA.B   BLKCHK_CONT                     | ->
BLKCHK_LOOP:
        BSet    #0x1F,D0                        | mark block as allocated
        BNE.B   BLKCHK_OK                       | was already set ->
        MOVEQ.L #-0x1,D3                        | block was free: flag error
        JSR     P_mMarkBlock(PC)                | mark bitmap dirty
BLKCHK_OK:
        ADDQ.W  #0x1,D2                         | next block number
        ROL.L   #0x1,D0                         | advance to next bit in bitmap word
        SUBQ.W  #0x1,D1                         | decrement bits remaining
        BGT.B   BLKCHK_CONT                     | bits left ->
        TST     D4                              | more blocks to check?
        BEQ.B   BLKCHK_NO                       | no ->
        BSR     READBM_NEXT_2                   | NextWord: get next bitmap word
BLKCHK_CONT:
        TST     D1                              | any error?
        BMI.B   BLKCHK_ERR                      | error ->
        DBF     D4,BLKCHK_LOOP                  | check next block
        ROL.L   D1,D0                           | rotate back
BLKCHK_NO:
        MOVE.L  D0,0x0(A0,D6.W)                 | put bitmap word back
        ADDQ.W  #0x4,D7                         | next extent descriptor (4 bytes each)
        CMPI    #0xC,D7                         | all 3 extents checked? (3*4=12)
        BCS.B   BLKCHK_NEXT                     | no, check next extent ->
BLKCHK_DONE:
        MOVE.L  D3,D0                           | return error flag
BLKCHK_ERR:
        MOVEM.L (A6)+,D1-D7/A1                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST.L   D0                              | set condition codes
        RTS                                     | exit BlkChk

| ----------------------------------------------------------
|
| UpdateFree: recount free blocks by scanning entire bitmap
|
UpdateFree:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D0-D6/A0-A1,-(A6)               | save registers
        MOVEQ.L #0x0,D4                         | D4 = free block counter
        MOVEQ.L #0x0,D2                         | start at block 0
        BSR     ReadBM                          | read first bitmap block
        MOVE    vcbNmAlBlks(A2),D2              | D2 = total allocation blocks
UPDATEFREE_CONT:
        TST     D1                              | any error?
        BMI.B   UPDATEFREE_ERR                  | error ->
        TST.L   D0                              | bit 31 clear? (free block)
        BMI.B   UPDATEFREE_NO                   | no, allocated ->
        ADDQ.W  #0x1,D4                         | count free block
UPDATEFREE_NO:
        SUBQ.W  #0x1,D2                         | more blocks to scan?
        BEQ.B   UPDATEFREE_DONE                 | no, done ->
        BSR     READBM_NEXT                     | NextBit: get next bitmap bit
        BRA.B   UPDATEFREE_CONT                 | keep scanning
UPDATEFREE_DONE:
        MOVE    D4,vcbFreeBks(A2)               | update VCB free block count
UPDATEFREE_ERR:
        MOVEM.L (A6)+,D0-D6/A0-A1               | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit UpdateFree

| ReadBM -- pick up the bitmap block of interest.
| ----------------------------------------------------------
|
| Read BM
|
| Called by: BLKALLOC_NO, BLKALLOC_CONT, BLKALLOC_CONT_4, BlkDealloc, BLKCHK_NEXT (and 1 more)
ReadBM:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE    D2,D5                           | D5 = alloc block number
        LSR     #0x8,D5                         | divide by 4096
        LSR     #0x4,D5                         | D5 = bitmap disk block index
| ReadBM: read bitmap block for allocation block D2
        MOVE    D2,D6                           | D6 = alloc block number
        ANDI    #0xFE0,D6                       | mask to word boundary (block / 32)
        LSR     #0x3,D6                         | byte offset into bitmap buffer
        MOVE    D2,D1                           | D1 = bit position within word
        ANDI    #0x1F,D1                        | mask to 0-31
        BSR     READBM_NEXT_3                   | GetBMBlk: read the bitmap block
        BEQ.B   READBM_OK                       | ok ->
        MOVEQ.L #-0x1,D1                        | error: set D1 negative
        BRA.B   READBM_CONT                     | ->
READBM_OK:
        MOVE.L  0x0(A0,D6.W),D0                 | D0 = bitmap longword
        ROL.L   D1,D0                           | rotate target bit to bit 31
        NEG     D1                              | D1 = 32 - bit position
        ADDI    #0x20,D1                        | = bits remaining in this word
READBM_CONT:
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit ReadBM

| ----------------------------------------------------------
|
| READBM_NEXT - NextBit: advance to next bit in bitmap
|
| Called by: BLKALLOC_CONT_3, BLKALLOC_OK_2, BLKDEALLOC_CONT, UPDATEFREE_NO, READBM_CONT_2
READBM_NEXT:
        MOVE.L  (SP)+,-(A6)                     | save return address
        ROL.L   #0x1,D0                         | rotate to next bit
        SUBQ.W  #0x1,D1                         | decrement bits remaining
        BNE.B   READBM_EXIT                     | more bits in this word ->
        BSR.B   READBM_NEXT_2                   | NextWord: get next bitmap word
READBM_EXIT:
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit NextBit

| ----------------------------------------------------------
|
| READBM_CONT_2 - FrBitScan: scan for next free bit, skipping $FFFFFFFF words
|
READBM_CONT_2:
        MOVE.L  (SP)+,-(A6)                     | save return address
        ADDQ.W  #0x1,D2                         | advance past current block
        BSR.B   READBM_NEXT                     | NextBit: get next bit
READBM_CONT_3:
        CMP.L   (MinusOne).w,D0                 | all bits set (all allocated)?
        BNE.B   READBM_EXIT                     | no, found a potential free bit ->
        ADD     D1,D2                           | skip past remaining bits in word
        CMP     A1,D2                           | past end of volume?
        BCC.B   READBM_OK_2                     | yes, back up ->
        BSR.B   READBM_NEXT_2                   | NextWord: get next word
        BRA.B   READBM_CONT_3                   | keep scanning
READBM_OK_2:
        SUB     D1,D2                           | back up starting position
        BRA.B   READBM_EXIT                     | return

| ----------------------------------------------------------
|
| READBM_NEXT_2 - NextWord: get next longword from bitmap buffer
|
READBM_NEXT_2:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE.L  D0,0x0(A0,D6.W)                 | put current word back in buffer
        ADDQ.W  #0x4,D6                         | advance buffer index by 4 bytes
        CMPI    #0x200,D6                       | past end of 512-byte buffer?
        BCS.B   READBM_NO                       | no, still in same block ->
        ADDQ.W  #0x1,D5                         | next bitmap block number
        BSR     READBM_NEXT_3                   | GetBMBlk: read next bitmap block
        BEQ.B   READBM_OK_3                     | ok ->
        MOVEQ.L #-0x1,D1                        | error: set D1 negative
        BRA.B   READBM_CONT_4                   | ->
READBM_OK_3:
        CLR     D6                              | reset buffer index to start
READBM_NO:
        MOVE.L  0x0(A0,D6.W),D0                 | D0 = next bitmap longword
        MOVEQ.L #0x20,D1                        | D1 = 32 bits in this word
READBM_CONT_4:
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit NextWord

| ----------------------------------------------------------
|
| READBM_NEXT_3 - GetBMBlk: read a volume bitmap block from cache
|
READBM_NEXT_3:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D2/A1-A2,-(A6)               | save registers
        MOVE    vcbVRefNum(A2),D0               | volume refnum
        MOVEQ.L #0x0,D2                         | clear high word
        MOVE    vcbVBMSt(A2),D2                 | bitmap start block (VCBVBMSt)
        ADD     D5,D2                           | + bitmap block offset = logical block
        MOVE.L  vcbMAdr(A2),A1                  | bitmap cache queue (VCBMAdr)
        MOVEQ.L #0x8,D1                         | GetBlock with GBrelease option
        JSR     P_mGetBlock(PC)                 | get the bitmap block
        MOVEM.L (A6)+,D1-D2/A1-A2               | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit GetBMBlk

| P_mDeallocFile -- deallocate all file extents.
| ----------------------------------------------------------
|
| P_m Dealloc File
|
P_mDeallocFile:
        MOVE.L  (0x764).w,-(SP)                 | HFS vector: DeallocFile
        RTS                                     | return from P_mDeallocFile

| ----------------------------------------------------------
|
| Dealloc File
|
DeallocFile:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D7/A0-A1/A3-A4,-(A6)         | save registers
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        MOVE.L  A0,A3                           | A3 = ptr to CName
        MOVE.L  D0,D7                           | D7 = ParID
        CLR.B   D6                              | D6 = initial fork type (0 = data fork)
| DFFkLoop: locate catalog record for file
DEALLOCFILE_CONT:
        CLR     D4                              | initial FABN
        MOVE.L  A3,A0                           | ptr to CName
        MOVE.L  D7,D0                           | ParID
        CLR.L   D2                              | no hint
        JSR     CMGetCN(PC)                     | locate catalog record
        BNE     DEALLOCFILE_ERR                 | didn't get it ->
        CMPI.B  #0x2,(A1)                       | file CNode? (CMFilCN)
        BEQ.B   DEALLOCFILE_OK                  | yes ->
        MOVEQ.L #0x30,D0                        | result = 'not found' (CMnotfound)
        BNE     DEALLOCFILE_ERR                 | exit ->
DEALLOCFILE_OK:
        MOVE.L  0x14(A1),D5                     | D5 = file number (filFlNum)
        LEA.L   0x2(A4),A0                      | ptr to FXM key buffer (FXVxkrOff)
        CLR     0x6(A0)                         | indicate catalog resident extent record (xkrFABN=0)
        TST.B   D6                              | deleting the data fork?
        BNE.B   DEALLOCFILE_NO                  | no ->
        LEA.L   0x4A(A1),A1                     | position to data fork extent record (filExtRec)
        BRA.B   DEALLOCFILE_FOUND               | copy extent record ->
DEALLOCFILE_NO:
        LEA.L   0x56(A1),A1                     | position to resource fork extent record (filRExtRec)
        BRA.B   DEALLOCFILE_FOUND               | copy extent record ->
| DFRecLoop: set up key for next extent file record
DEALLOCFILE_NEXT:
        LEA.L   0x2(A4),A0                      | A0 = ptr to FXM key buffer
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        MOVE.B  D6,0x1(A0)                      | fork type (xkrFkType)
        MOVE.L  D5,0x2(A0)                      | file number (xkrFNum)
        MOVE    D4,0x6(A0)                      | file alloc block number (xkrFABN)
| get the next extent record
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        CLR.L   D2                              | no hint
        JSR     P_mBTSearch(PC)                 | find the record
        BEQ.B   DEALLOCFILE_FOUND               | found it ->
        CMPI    #0x20,D0                        | record not found? (BTnotfound)
        BEQ.B   DEALLOCFILE_DONE                | yes, done with this fork ->
        BRA.B   DEALLOCFILE_ERR                 | error ->
| DFCopyRec: copy extent data to FXM buffer
DEALLOCFILE_FOUND:
        LEA.L   0xA(A4),A0                      | dest = xdr buffer in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index in long words (lenxdr/4 - 1)
DEALLOCFILE_LOOP:
        MOVE.L  (A1)+,(A0)+                     | copy the record
        DBF     D0,DEALLOCFILE_LOOP             | loop for 3 longwords (12 bytes)
| DFRelExt: release extents for this record
        LEA.L   0xA(A4),A1                      | A1 = ptr to extent record
        CLR     D1                              | offset to 1st extent
DEALLOCFILE_NEXT_2:
        MOVE    0x0(A1,D1.W),D2                 | starting alloc blk number (xdrStABN)
        MOVE    0x2(A1,D1.W),D3                 | number of alloc blks (xdrNumABlks)
        BEQ.B   DEALLOCFILE_NO_2                | extent not used, delete the record ->
        JSR     P_mBlkDealloc(PC)               | deallocate the space
        BNE.B   DEALLOCFILE_ERR                 | error ->
        ADD     D3,D4                           | bump FABN to beg of next extent
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff)
        BLE.B   DEALLOCFILE_NEXT_2              | no, release next one ->
| DFDelRec: delete extent record
DEALLOCFILE_NO_2:
        LEA.L   0x2(A4),A0                      | A0 = ptr to search key
        TST     0x6(A0)                         | catalog resident record? (xkrFABN)
        BEQ.B   DEALLOCFILE_OK_2                | yes, nothing to delete ->
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTDelete(PC)                 | delete the record
        BNE.B   DEALLOCFILE_ERR                 | error ->
DEALLOCFILE_OK_2:
        TST     D3                              | end with null extent entry?
        BNE.B   DEALLOCFILE_NEXT                | no, get next record for same fork ->
| DFNxtFork: check for another fork
DEALLOCFILE_DONE:
        NOT.B   D6                              | just finished resource fork ($FF -> $00)?
        BNE     DEALLOCFILE_CONT                | $00 -> $FF: release space for resource fork
| DFExit
        CLR     D0                              | result = ok
        BSR     TRUNCATEFILE_CONT_5             | XFFlush: flush the extent file
DEALLOCFILE_ERR:
        ADDA    #0x16,A6                        | de-allocate FXM vars (lenFXVars)
        MOVEM.L (A6)+,D1-D7/A0-A1/A3-A4         | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | test
        RTS                                     | return from DEALLOCFILE_ERR

| P_mExtendFile -- extend the file.
| ----------------------------------------------------------
|
| P_m Extend File
|
P_mExtendFile:
        MOVE.L  (0x768).w,-(SP)                 | HFS vector: ExtendFile
        RTS                                     | return from P_mExtendFile

| ----------------------------------------------------------
|
| Extend File
|
| ExtendFile: extend the disk space allocated to a file
ExtendFile:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D5/D7/A0-A4,-(A6)            | save regs
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        BSET    #0x6,(A4)                       | 1st try contig allocation (FXVTContig)
        TST.B   D3                              | forced contiguous requested? (EFContig)
        BEQ.B   EXTENDFILE_NO                   | no ->
        BSET    #0x7,(A4)                       | set flag
EXTENDFILE_NO:
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB pointer
        MOVE.L  0xC(A3),-(A6)                   | save previous PEOF (FCBPLen)
| round # of bytes requested up to next alloc blk
        MOVE.L  vcbAlBlkSiz(A2),D0              | allocation block size
        ADD.L   D0,D4                           | D4 + AlBlkSiz (for rounding up)
        SUBQ.L  #0x1,D4                         | adjust for integer division
        DIVU    D0,D4                           | D4 / AlBlkSiz = blocks needed
        MULU    D0,D4                           | D4 rounded up
| EFLocExt: locate extent mapping new PEOF - 1 (last byte)
        MOVE.L  0xC(A3),D0                      | current PEOF (FCBPLen)
        ADD.L   D4,D0                           | + # of bytes requested = new PEOF
        SUBQ.L  #0x1,D0                         | new PEOF - 1 = last byte in file
        BSR     XFSearch                        | locate the extent
        BNE.B   EXTENDFILE_CONT                 | didn't find it ->
        ADD.L   D4,0xC(A3)                      | update PEOF (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        BRA     EXTENDFILE_DONE                 | all done ->
EXTENDFILE_CONT:
        CMPI    #0x10,D0                        | out of range? (FXRangeErr)
        BNE     EXTENDFILE_ERR                  | no, some error ->
        MOVE.L  D2,D7                           | D7 = BTree hint
        MOVE    D3,D6                           | D6 = ending FABN + 1
| adjust PEOF to end of extent
        MOVE    D6,D0                           | (ending FABN + 1)
        MULU    0x1E(A2),D0                     | in bytes = max PEOF for extent
        SUB.L   0xC(A3),D0                      | PEOF already at end of extent?
        BEQ.B   EXTENDFILE_RETRY                | yes ->
        ADD.L   D0,0xC(A3)                      | no, adjust PEOF to end of extent
        BSET    #0x7,0x4(A3)                    | mark FCB dirty
        SUB.L   D0,D4                           | adjust remaining count
| EFAddSpace: allocate additional disk space
EXTENDFILE_RETRY:
        MOVE    0x0(A1,D1.W),D5                 | starting alloc blk number (xdrStABN)
        ADD     0x2(A1,D1.W),D5                 | + # of blks = last blk + 1
EXTENDFILE_CONT_2:
        MOVE    D5,D2                           | preferred starting blk = last blk + 1
        BTST    #0x6,(A4)                       | trying for contig? (FXVTContig)
        SNE.B   D3                              | yes, set flag for BlkAlloc
        JSR     P_mBlkAlloc(PC)                 | allocate the disk space
        BEQ.B   EXTENDFILE_CONT_3               | got it ->
        CMPI    #-0x22,D0                       | disk full error? (DskFulErr)
        BNE     EXTENDFILE_ERR                  | no, some other error ->
        BCLR    #0x6,(A4)                       | did we just try for contig?
        BEQ     EXTENDFILE_ERR                  | no, must be out of space ->
        BTST    #0x7,(A4)                       | forced contig requested? (FXVFContig)
        BNE     EXTENDFILE_ERR                  | yes, couldn't get it ->
        BRA.B   EXTENDFILE_CONT_2               | try non-contig ->
| EFExtExt: see if current extent can be extended
EXTENDFILE_CONT_3:
        CMP     D2,D5                           | get preferred space?
        BNE.B   EXTENDFILE_NO_2                 | no, must add an extent ->
        ADD     D3,0x2(A1,D1.W)                 | add new blks to current extent (xdrNumABlks)
        BRA.B   EXTENDFILE_CONT_4               | use common code ->

| ----------------------------------------------------------
|
| EXTENDFILE_NO_2
|
| EFAddExt: add a new extent entry
EXTENDFILE_NO_2:
        TST     0x2(A1,D1.W)                    | current extent null? (xdrNumABlks)
        BEQ.B   EXTENDFILE_OK                   | yes, use it ->
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff)
        BGT.B   EXTENDFILE_OK_2                 | yes ->
EXTENDFILE_OK:
        MOVE    D2,0x0(A1,D1.W)                 | set starting alloc blk # (xdrStABN)
        MOVE    D3,0x2(A1,D1.W)                 | and # of blks (xdrNumABlks)
| EFUpdExt: update the extent record
EXTENDFILE_CONT_4:
        MOVE.L  D7,D2                           | BTree hint
        BSR     XFSEARCH_CONT_4                 | XRUpdate: update the extent record
        BNE     EXTENDFILE_ERR                  | error ->
        MOVE.L  D2,D7                           | D7 = new hint
        BRA.B   EXTENDFILE_CONT_5               | go update FCB ->

| ----------------------------------------------------------
|
| EXTENDFILE_OK_2
|
| EFNewRec: add a new extent record
EXTENDFILE_OK_2:
        MOVE.L  (A3),D5                         | D5 = file number (FCBFlNm)
        CMPI.L  #0x3,D5                         | mapping the extents file? (FSXtCNID=3)
        BNE.B   EXTENDFILE_NO_3                 | no ->
        MOVEQ.L #0x11,D0                        | result = 'extent file overflow' (FXOvFlErr)
        BRA.B   EXTENDFILE_ERR                  | exit ->

| ----------------------------------------------------------
|
| EXTENDFILE_NO_3
|
EXTENDFILE_NO_3:
        LEA.L   0x2(A4),A0                      | point to FXM key buffer (FXVxkrOff)
        LEA.L   0xA(A4),A1                      | point to FXM data buffer (FXVxdrOff)
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        CLR.B   0x1(A0)                         | assume data fork (xkrFkType)
        BTST    #0x1,0x4(A3)                    | mapping resource fork? (FCBRscBit)
        SNE.B   0x1(A0)                         | yes, set resource fork flag
        MOVE.L  D5,0x2(A0)                      | file number (xkrFNum)
        MOVE    D6,0x6(A0)                      | starting FABN (xkrFABN)
| clear new extent record
        MOVE    #0x5,D0                         | (lenxdr/2)-1
EXTENDFILE_LOOP:
        CLR     (A1)+                           | zero a word
        DBF     D0,EXTENDFILE_LOOP              | loop for 6 words (12 bytes)
        LEA.L   0xA(A4),A1                      | restore ptr to xdr
        CLR     D1                              | offset to 1st extent
        MOVE    D2,0x0(A1,D1.W)                 | set starting alloc blk # (xdrStABN)
        MOVE    D3,0x2(A1,D1.W)                 | and # of blks (xdrNumABlks)
        MOVE.L  D1,-(A6)                        | save D1
        MOVE    #0xC,D1                         | record length (lenxdr)
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTInsert(PC)                 | insert the new record
        MOVE.L  (A6)+,D1                        | restore D1
        TST     D0                              | restore BTInsert result
        BNE.B   EXTENDFILE_ERR                  | error ->
        MOVE.L  D2,D7                           | D7 = new hint
| EFUpdFCB: update FCB and see if more space is needed
EXTENDFILE_CONT_5:
        ADD     D3,D6                           | update ending FABN + 1
        MULU    0x1E(A2),D3                     | convert # of blks to bytes (VCBAlBlkSiz+2)
        ADD.L   D3,0xC(A3)                      | adjust PEOF to include new space (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        SUB.L   D3,D4                           | allocated enough space?
        BGT     EXTENDFILE_RETRY                | no, do it again ->
        ADD.L   D4,0xC(A3)                      | adjust PEOF to alloc blk boundary
| EFExit
EXTENDFILE_DONE:
        CLR     D0                              | result = ok
        BSR     TRUNCATEFILE_CONT_5             | XFFlush: flush the extent file
EXTENDFILE_ERR:
        MOVE.L  0xC(A3),D6                      | new PEOF (FCBPLen)
        MOVE.L  (A6)+,D1                        | - previous PEOF
        SUB.L   D1,D6                           | = # of bytes allocated
        ADDA    #0x16,A6                        | de-allocate FXM vars
        MOVEM.L (A6)+,D1-D5/D7/A0-A4            | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit ExtendFile

| ----------------------------------------------------------
|
| FXM Key Cmp
|
| FXMKeyCmp: compare two extent file keys
FXMKeyCmp:
        MOVEM.L A0-A1,-(SP)                     | save registers
| compare file ID's
        MOVE.L  0x2(A0),D0                      | compare file numbers (xkrFNum)
        CMP.L   0x2(A1),D0                      | compare search vs. trial file number
        BHI.B   FXMKEYCMP_CONT_2                | search fileNum > trial fileNum ->
        BCS.B   FXMKEYCMP_CONT                  | search fileNum < trial fileNum ->
| file ID's equal, compare fork types
        MOVE.B  0x1(A0),D0                      | compare fork types (xkrFkType)
        CMP.B   0x1(A1),D0                      | compare search vs. trial fork type
        BHI.B   FXMKEYCMP_CONT_2                | search fork > trial fork ->
        BCS.B   FXMKEYCMP_CONT                  | search fork < trial fork ->
| fork types equal, compare starting block numbers
        MOVE    0x6(A0),D0                      | compare block numbers (xkrFABN)
        CMP     0x6(A1),D0                      | compare search vs. trial block num
        BHI.B   FXMKEYCMP_CONT_2                | search block > trial block ->
        BCS.B   FXMKEYCMP_CONT                  | search block < trial block ->
| KCIsEQ
        CLR     D0                              | result = "equal"
        BRA.B   FXMKEYCMP_EXIT                  | return equal
| KCIsLT
FXMKEYCMP_CONT:
        MOVE    #-0x1,D0                        | result = "less than"
        BRA.B   FXMKEYCMP_EXIT                  | return less than
| KCIsGT
FXMKEYCMP_CONT_2:
        MOVE    #0x1,D0                         | result = "greater than"
FXMKEYCMP_EXIT:
        MOVEM.L (SP)+,A0-A1                     | restore regs
        TST     D0                              | test
        RTS                                     | return from FXMKEYCMP_EXIT

| ----------------------------------------------------------
|
| Map F Block
|
| MapFBlock: maps file position to physical disk address (HFS)
MapFBlock:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D2/D4-D5/D7/A0-A1/A3-A4,-(A6) | save registers
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB pointer
| locate the extent mapping the desired file position
        MOVE.L  D5,D0                           | file position
        BSR     XFSearch                        | locate the extent
        BNE.B   MAPFBLOCK_EXIT                  | exit on errors
        LEA.L   0x0(A1,D1.W),A1                 | A1 = ptr to extent entry
        MOVE    D3,D1                           | D1 = beg FABN for extent
        SUB     0x2(A1),D1                      | (ending FABN+1 - numABlks = beg FABN)
        MOVE    D3,D2                           | D2 = end FABN in extent + 1
| determine end of available space (PEOF or end of extent)
        MULU    0x1E(A2),D2                     | convert end FABN+1 to file pos (VCBAlBlkSiz+2)
        MOVE.L  0xC(A3),D0                      | get PEOF (FCBPLen)
        CMP.L   D0,D2                           | end of extent > PEOF?
        BLE.B   MAPFBLOCK_NO                    | no, use end of extent ->
        MOVE.L  D0,D2                           | yes, use PEOF
MAPFBLOCK_NO:
        DIVU    0x1E(A2),D2                     | D2 = end of avail space (end FABN+1)
| set up some constants
        MOVE.L  vcbAlBlkSiz(A2),D6              | D6 = # blks per alloc blk
        DIVU    #0x200,D6                       | (alloc blk size / 512)
        MOVEQ.L #0x0,D7                         | D7 = start blk # for alloc blks
        MOVE    vcbAlBlSt(A2),D7                | volume alloc block start (VCBAlBlSt)
| calculate physical start block
        MOVE.L  D5,D3                           | file position / alloc blk size
        DIVU    0x1E(A2),D3                     | = FABN mapping file position
        SWAP    D3                              | get remainder in low word
        MOVEQ.L #0x0,D0                         | compute block offset within alloc block
        MOVE    D3,D0                           | D0 = remainder (bytes into alloc block)
        LSR.L   #0x8,D0                         | / 256
        LSR.L   #0x1,D0                         | / 2 = offset in phys blocks
        SWAP    D3                              | restore FABN
        SUB     D1,D3                           | - beg FABN = alloc blk delta
        ADD     (A1),D3                         | + starting ABN (xdrStABN)
        MULU    D6,D3                           | convert to physical block #
        ADD     D0,D3                           | + offset within alloc block
        ADD.L   D7,D3                           | + alloc block start on volume
| calculate number of available bytes
        MOVE    D2,D6                           | end FABN+1 * alloc blk size
        MULU    0x1E(A2),D6                     | = ending file pos + 1
        SUB.L   D5,D6                           | - file position = size avail
        CMP.L   D4,D6                           | compare with desired number
        BCS.B   MAPFBLOCK_CONT                  | < D4 bytes, leave it alone
        MOVE.L  D4,D6                           | > D4 bytes, set to D4 bytes
MAPFBLOCK_CONT:
        MOVEQ.L #0x0,D0                         | we're ok
| MFExit
MAPFBLOCK_EXIT:
        ADDA    #0x16,A6                        | de-allocate FXM vars
        MOVEM.L (A6)+,D1-D2/D4-D5/D7/A0-A1/A3-A4 | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set CCR for result
        RTS                                     | exit MapFBlock

| P_mTruncateFile -- truncateFile: truncate to rounded length.
| ----------------------------------------------------------
|
| P_m Truncate File
|
P_mTruncateFile:
        MOVE.L  (0x76C).w,-(SP)                 | HFS vector: TruncateFile
        RTS                                     | return from P_mTruncateFile

| ----------------------------------------------------------
|
| Truncate File
|
TruncateFile:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D7/A0-A4,-(A6)               | save registers
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB pointer
        BTST    #0x1,0x4(A3)                    | mapping resource fork? (FCBRscBit)
        SNE.B   D6                              | D6 = option flags
| TFLocExt: locate extent mapping last byte of truncated file
        MOVE.L  D3,D5                           | D5 = new PEOF
        MOVE.L  vcbAlBlkSiz(A2),D0              | round the new PEOF
        ADD.L   D0,D5                           | D5 + AlBlkSiz (for rounding up)
        SUBQ.L  #0x1,D5                         | adjust for integer division
        DIVU    D0,D5                           | D5 / AlBlkSiz = blocks needed
        MULU    D0,D5                           | up to next alloc blk
        MOVE.L  D5,D0                           | new PEOF - 1 = last byte in file
        SUBQ.L  #0x1,D0                         | point to last byte of file
        BGE.B   TRUNCATEFILE_CONT               | new PEOF > 0 ->
| truncating to zero: release all extents
        MOVE.L  D5,0xC(A3)                      | update PEOF in FCB (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        SUBA.L  A0,A0                           | indicate FCB resident record
        MOVEQ.L #0x0,D7                         | no hint
        LEA.L   0x26(A3),A1                     | point to FCB extent record (FCBExtRec)
        CLR     D4                              | last FABN in extent + 1
        BRA     TRUNCATEFILE_CONT_3             | release all extents ->
TRUNCATEFILE_CONT:
        BSR     XFSearch                        | locate the extent
        BNE     TRUNCATEFILE_ERR                | error ->
        MOVE.L  D2,D7                           | D7 = BTree hint
        MOVE    D3,D4                           | D4 = last FABN in extent + 1
        MOVE.L  D5,0xC(A3)                      | update PEOF in FCB (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        TST.B   (FlushOnly).w                   | truncate to end of extent? (TFTrunExt)
        BEQ.B   TRUNCATEFILE_NO                 | no, truncate to new PEOF ->
        MOVE    0x2(A1,D1.W),D3                 | D3 = # of blks in extent (xdrNumABlks)
        BRA     TRUNCATEFILE_EMPTY              | release remaining extents in record ->
| TFTrunPEOF: truncate extent containing new PEOF
TRUNCATEFILE_NO:
        MOVE.L  D5,D0                           | new PEOF - 1 (last byte in file)
        SUBQ.L  #0x1,D0                         | point to last byte of truncated file
        DIVU    0x1E(A2),D0                     | / alloc blk size = last FABN in file
        SUB     D0,D3                           | (last extent FABN+1) - (last file FABN)
        SUBQ.W  #0x1,D3                         | - 1 = # to deallocate
        BEQ.B   TRUNCATEFILE_CONT_2             | nothing to deallocate ->
        MOVE    0x0(A1,D1.W),D2                 | starting ABN (xdrStABN)
        ADD     0x2(A1,D1.W),D2                 | + # alloc blks in extent
        SUB     D3,D2                           | - # to dealloc = starting ABN to free
        JSR     P_mBlkDealloc(PC)               | deallocate the space
        BNE     TRUNCATEFILE_ERR                | error ->
TRUNCATEFILE_CONT_2:
        MOVE    D3,D0                           | D0 = # of blks deallocated
        MOVE    0x2(A1,D1.W),D3                 | D3 = orig # of blks (xdrNumABlks)
        SUB     D0,0x2(A1,D1.W)                 | update # of blks in extent
        BNE.B   TRUNCATEFILE_EMPTY              | extent not empty ->
        CLR     0x0(A1,D1.W)                    | set extent null (xdrStABN)
        BRA.B   TRUNCATEFILE_EMPTY              | release remaining extents in record ->
| TFLoop: get next extent record in BTree
TRUNCATEFILE_NEXT:
        LEA.L   0x2(A4),A0                      | A0 = ptr to search key buffer (FXVxkrOff)
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        MOVE.B  D6,0x1(A0)                      | fork type (xkrFkType)
        MOVE.L  (A3),0x2(A0)                    | file number (xkrFNum = FCBFlNm)
        MOVE    D4,0x6(A0)                      | file alloc block number (xkrFABN)
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        CLR.L   D2                              | no hint
        JSR     P_mBTSearch(PC)                 | find the record
        BEQ.B   TRUNCATEFILE_FOUND              | found it ->
        CMPI    #0x20,D0                        | record not found? (BTnotfound)
        BEQ.B   TRUNCATEFILE_DONE               | yes, all done ->
        BRA.B   TRUNCATEFILE_ERR                | error ->
TRUNCATEFILE_FOUND:
        MOVE.L  D2,D7                           | save hint in D7
| copy extent data to FXM buffer
        LEA.L   0xA(A4),A0                      | dest = xdr buffer in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index in long words (lenxdr/4 - 1)
TRUNCATEFILE_LOOP:
        MOVE.L  (A1)+,(A0)+                     | copy the record
        DBF     D0,TRUNCATEFILE_LOOP            | loop for 3 longwords (12 bytes)
        LEA.L   0x2(A4),A0                      | A0 = ptr to search key
        LEA.L   0xA(A4),A1                      | A1 = ptr to extent record
| TFRelExt: release extents for this record
TRUNCATEFILE_CONT_3:
        CLR     D1                              | offset to 1st extent
TRUNCATEFILE_NEXT_2:
        MOVE    0x0(A1,D1.W),D2                 | starting alloc blk number (xdrStABN)
        MOVE    0x2(A1,D1.W),D3                 | number of alloc blks (xdrNumABlks)
        BEQ.B   TRUNCATEFILE_NO_2               | extent not used, update the record ->
        JSR     P_mBlkDealloc(PC)               | deallocate the space
        BNE.B   TRUNCATEFILE_ERR                | error ->
        CLR.L   0x0(A1,D1.W)                    | set the extent null
        ADD     D3,D4                           | bump FABN to beg of next extent
| TFRelRExt
TRUNCATEFILE_EMPTY:
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt=4)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff=8)
        BLE.B   TRUNCATEFILE_NEXT_2             | no, release next one ->
| TFUpdRec: update extent record
TRUNCATEFILE_NO_2:
        TST     0x2(A1)                         | 1st extent null? (xdrNumABlks)
        BEQ.B   TRUNCATEFILE_OK                 | yes, delete record ->
        MOVE.L  D7,D2                           | BTree hint
        BSR     XFSEARCH_CONT_4                 | XRUpdate: update the record
        BRA.B   TRUNCATEFILE_OK_2               | ->

| ----------------------------------------------------------
|
| TRUNCATEFILE_OK
|
TRUNCATEFILE_OK:
        MOVE.L  A0,D0                           | FCB resident record?
        BEQ.B   TRUNCATEFILE_OK_2               | yes, nothing to delete ->
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTDelete(PC)                 | delete the record
        BNE.B   TRUNCATEFILE_ERR                | error ->
TRUNCATEFILE_OK_2:
        TST     D3                              | end with null extent entry?
        BNE.B   TRUNCATEFILE_NEXT               | no, continue with next record ->
| TFExit
TRUNCATEFILE_DONE:
        CLR     D0                              | result = ok
        BSR.B   TRUNCATEFILE_CONT_5             | XFFlush: flush the extent file
TRUNCATEFILE_ERR:
        ADDA    #0x16,A6                        | de-allocate FXM vars (lenFXVars)
        MOVEM.L (A6)+,D1-D7/A0-A4               | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit TruncateFile

| ----------------------------------------------------------
|
| TRUNCATEFILE_CONT_4 - FXSetUp: allocate FXM vars on A6 stack
|
TRUNCATEFILE_CONT_4:
        SUBA    #0x16,A6                        | allocate FXM vars (lenFXVars)
        MOVE.L  A6,A4                           | A4 = pointer to FXM vars
        CLR.B   (A4)                            | clear all flags (FXVFlags)
        RTS                                     | exit FXSetUp

| ----------------------------------------------------------
|
| TRUNCATEFILE_CONT_5
|
| XFFlush: flush the extent file for a specified volume
TRUNCATEFILE_CONT_5:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A1,-(A6)                     | save registers
        MOVE    0xA4(A2),D1                     | D1 = refnum of extent file (VCBXTRef)
        MOVE    D1,D0                           | flush the extent BTree
        JSR     P_mBTFlush(PC)                  | flush B-tree to disk
        BNE.B   TRUNCATEFILE_ERR_2              | error ->
        MOVE.L  (FCBSPtr).w,A1                  | FCB dirty? (FCBModBit)
        BTST    #0x7,0x4(A1,D1.W)               | test dirty bit in FCB flags
        BEQ.B   TRUNCATEFILE_DONE_2             | no, all done ->
        JSR     MarkVCB(PC)                     | mark the VCB dirty
        JSR     FlushMDB(PC)                    | flush the MDB
        BNE.B   TRUNCATEFILE_ERR_2              | error ->
TRUNCATEFILE_DONE_2:
        CLR     D0                              | result = 'ok'
TRUNCATEFILE_ERR_2:
        MOVEM.L (A6)+,D1/A1                     | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit XFFlush

| ----------------------------------------------------------
|
| XF Search
|
| XFSearch: search extent file for extent mapping a file position
XFSearch:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D4-D6,-(A6)                     | save regs
        MOVE.L  D0,D4                           | D4 = file position to be mapped
        DIVU    0x1E(A2),D4                     | convert to FABN (VCBAlBlkSiz+2)
        MOVE.L  (A3),D5                         | D5 = file number (FCBFlNm)
| FSSchFCB: search FCB extent record first
        SUBA.L  A0,A0                           | indicate FCB resident record
        MOVEQ.L #0x0,D2                         | no hint
        LEA.L   0x26(A3),A1                     | point to extent record (FCBExtRec)
        MOVE    D4,D0                           | desired FABN
        CLR     D3                              | starting FABN
        BSR     XFSEARCH_CONT_2                 | XRSearch: search record for extent entry
        BEQ     XFSEARCH_FOUND_2                | found it ->
        CMPI    #0x8,D1                         | end before last extent entry? (maxExtOff)
        BLT     XFSEARCH_ERR                    | yes, no more extents ->
        TST     0x2(A1,D1.W)                    | end with a null extent? (xdrNumABlks)
        BEQ     XFSEARCH_ERR                    | yes, no more extents ->
        CMPI.L  #0x3,D5                         | mapping the extents file? (FSXtCNID)
        BEQ     XFSEARCH_ERR                    | yes, no more extents ->
| FSSchFile: locate desired record in extents file
        LEA.L   0x2(A4),A0                      | A0 = ptr to key buffer (FXVxkrOff)
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        BTST    #0x1,0x4(A3)                    | mapping resource fork? (FCBRscBit)
        SNE.B   D6                              | D6 = fork flag
        MOVE.B  D6,0x1(A0)                      | fork type (xkrFkType)
        MOVE.L  D5,0x2(A0)                      | file number (xkrFNum)
        MOVE    D4,0x6(A0)                      | desired FABN (xkrFABN)
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        CLR.L   D2                              | no hint
        JSR     P_mBTSearch(PC)                 | search BTree for extent record
        BEQ.B   XFSEARCH_FOUND                  | a direct hit ->
        CMPI    #0x20,D0                        | result = 'not found'? (BTnotfound)
        BNE.B   XFSEARCH_ERR                    | no, error ->
        MOVE    0xA4(A2),D0                     | extents file refnum
        MOVEQ.L #-0x1,D1                        | indicate previous record
        JSR     P_mBTGetRecord(PC)              | get previous extent record
        BEQ.B   XFSEARCH_CONT                   | got it ->
        CMPI    #0x20,D0                        | result = 'not found'?
        BEQ.B   XFSEARCH_OK                     | yes, no extent record ->
        BRA.B   XFSEARCH_ERR                    | error ->
XFSEARCH_CONT:
        CMP.L   0x2(A0),D5                      | same file? (xkrFNum)
        BNE.B   XFSEARCH_OK                     | no ->
        CMP.B   0x1(A0),D6                      | same fork? (xkrFkType)
        BEQ.B   XFSEARCH_FOUND                  | yes, we got it ->
| FSMissed: didn't find extent record, return pointing to last extent in FCB
XFSEARCH_OK:
        SUBA.L  A0,A0                           | indicate FCB resident record
        MOVEQ.L #0x0,D2                         | no hint
        LEA.L   0x26(A3),A1                     | point to FCB extent record
        MOVE    #0x8,D1                         | the last extent (maxExtOff)
        MOVEQ.L #0x10,D0                        | result = 'range error' (FXRangeErr)
        BRA.B   XFSEARCH_ERR                    | exit ->

| ----------------------------------------------------------
|
| XFSEARCH_FOUND
|
| FSCopyRec: found extent record, copy key and data into FXM vars
XFSEARCH_FOUND:
        MOVE.L  A1,-(SP)                        | save ptr(xdr) in cache buffer
        LEA.L   0x2(A4),A1                      | dest = key buffer in FXM vars (FXVxkrOff)
        MOVEQ.L #0x1,D0                         | loop index (lenxkr/4 - 1)
XFSEARCH_LOOP:
        MOVE.L  (A0)+,(A1)+                     | copy the key record
        DBF     D0,XFSEARCH_LOOP                | loop for 2 longwords (8 bytes)
        MOVE.L  (SP)+,A0                        | source = xdr in cache buffer
        LEA.L   0xA(A4),A1                      | dest = xdr in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index (lenxdr/4 - 1)
XFSEARCH_LOOP_2:
        MOVE.L  (A0)+,(A1)+                     | copy the data record
        DBF     D0,XFSEARCH_LOOP_2              | loop for 3 longwords (12 bytes)
| FSSchRec: search record for desired extent entry
        LEA.L   0x2(A4),A0                      | A0 = ptr to xkr in FXM vars
        LEA.L   0xA(A4),A1                      | A1 = ptr to xdr in FXM vars
        MOVE    0x6(A0),D3                      | D3 = beg FABN for extent record (xkrFABN)
        MOVE    D4,D0                           | desired FABN
        BSR     XFSEARCH_CONT_2                 | XRSearch: search record for desired FABN
        BNE.B   XFSEARCH_ERR                    | didn't find it ->
| FSExit
XFSEARCH_FOUND_2:
        CLR     D0                              | result = ok
XFSEARCH_ERR:
        MOVEM.L (A6)+,D4-D6                     | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit XFSearch

| ----------------------------------------------------------
|
| XFSEARCH_CONT_2
|
| XRSearch: search extent record for extent mapping a given FABN
| D0=desired FABN, A1=ptr to xdr, D3=beginning FABN for record
XFSEARCH_CONT_2:
        MOVE.L  D2,-(SP)                        | save regs
        MOVE    D0,D2                           | D2 = desired FABN
        CLR     D1                              | D1 = initial offset
XFSEARCH_NO:
        MOVE    0x2(A1,D1.W),D0                 | number of alloc blks in extent (xdrNumABlks)
        BEQ.B   XFSEARCH_EMPTY                  | null extent ->
        ADD     D0,D3                           | ending FABN + 1
        CMP     D2,D3                           | desired FABN within this extent?
        BHI.B   XFSEARCH_DONE                   | yes, all done ->
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff)
        BLE.B   XFSEARCH_NO                     | no, continue search ->
XFSEARCH_EMPTY:
        SUBQ.W  #0x4,D1                         | back up to previous extent
        BGE.B   XFSEARCH_CONT_3                 | still within the record ->
        CLR     D1                              | reset to 1st extent
XFSEARCH_CONT_3:
        MOVEQ.L #0x10,D0                        | result = 'range error' (FXRangeErr)
        BRA.B   XFSEARCH_EXIT                   | exit ->
| RSExit
XFSEARCH_DONE:
        CLR     D0                              | result = ok
XFSEARCH_EXIT:
        MOVE.L  (SP)+,D2                        | restore regs
        TST     D0                              | set condition codes
        RTS                                     | exit XRSearch

| ----------------------------------------------------------
|
| XFSEARCH_CONT_4 - XRUpdate: update the current extent record
|
XFSEARCH_CONT_4:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A0-A1,-(A6)                  | save registers
        MOVE.L  A0,D0                           | FCB resident record?
        BNE.B   XFSEARCH_NO_2                   | no, must update extents file ->
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        BRA.B   XFSEARCH_DONE_2                 | all done ->
| RUUpdFile: re-locate and update extent file record
XFSEARCH_NO_2:
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTSearch(PC)                 | re-locate the extent file record
        BNE.B   XFSEARCH_ERR_2                  | error ->
        LEA.L   0xA(A4),A0                      | source = xdr in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index (lenxdr/4 - 1)
XFSEARCH_LOOP_3:
        MOVE.L  (A0)+,(A1)+                     | update the xdr in cache buffer
        DBF     D0,XFSEARCH_LOOP_3              | loop for 3 longwords (12 bytes)
        MOVE    0xA4(A2),D0                     | extents file refnum
        JSR     P_mBTUpdate(PC)                 | update BTree record
        BNE.B   XFSEARCH_ERR_2                  | error ->
XFSEARCH_DONE_2:
        CLR     D0                              | result = 'ok'
XFSEARCH_ERR_2:
        MOVEM.L (A6)+,D1/A0-A1                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit XRUpdate
