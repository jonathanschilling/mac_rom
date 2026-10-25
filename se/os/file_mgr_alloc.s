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

| Apple source module: VSM
BLKALLOC:
    MOVE.L      (0x77C).W,-(A7)                 | push BlkAlloc vector address
    RTS                                         | jump to HFS vector
VBLKALLOC:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/D4-D7/A0-A1,-(A6)            | save caller's registers
    TST.W       0x2A(A2)                        | any blocks free? (vcbFreeBks)
    BEQ.W       BLKALLOC_EXIT_2                 | no, disk full
    ANDI.W      #0x1,D3                         | preserve only contiguous flag bit
    TST.W       D2                              | preferred start block given?
    BNE.B       BLKALLOC_OK                     | yes, use it
    MOVE.W      0x18(A2),D2                     | no, use vcbAllocPtr
    BSET        #0x7,D3                         | flag to update vcbAllocPtr later
BLKALLOC_OK:
    SWAP.W      D3                              | save flags in high word
    MOVE.W      D2,D3                           | store starting block
    SWAP.W      D3                              | restore flags in low word
    BCLR        #0xF,D3                         | clear wrap-around flag
BLKALLOC_LOOP:
    BSR.W       P_ReadBM                        | ReadBM: read bitmap block for D2
    TST.W       D1                              | error?
    BMI.W       BKALLOCEXIT                     | yes, exit
    MOVEA.W     0x1A(A2),A1                     | A1 = vcbNmAlBlks (volume size)
BLKALLOC_CONT:
    CMP.W       A1,D2                           | reached end of volume?
    BCS.B       BLKALLOC_NO_2                   | no, continue scanning
    ROL.L       D1,D0                           | rotate bitmap word back into place
    MOVE.L      D0,0x0(A0,D6.W)                 | replace in bitmap buffer
    CLR.W       D2                              | wrap around to beginning
    BSR.W       P_ReadBM                        | read bitmap block for block 0
    BSET        #0xF,D3                         | indicate we wrapped around EOV
    BNE.W       BLKALLOC_EXIT_2                 | already wrapped, disk full
BLKALLOC_NO_2:
    TST.W       D1                              | error?
    BMI.W       BKALLOCEXIT                     | yes, exit
    TST.L       D0                              | bit 31 set = allocated?
    BPL.B       BLKALLOC_CONT_2                 | clear = free block found
    BSR.W       READBM_CONT_2                   | FrBitScan: scan for next free bit
    BRA.B       BLKALLOC_CONT                   | keep scanning
BLKALLOC_CONT_2:
    SUBA.W      D2,A1                           | A1 = blocks left to end of volume
    BTST        #0x0,D3                         | contiguous alloc requested?
    BEQ.B       BLKALLOC_NO_4                   | no, just start allocating
    MOVE.L      D4,-(A6)                        | save original alloc request
    MOVEM.L     D0-D1,-(A6)                     | save for division
    MOVE.L      D4,D0                           | bytes to allocate
    MOVE.W      0x1E(A2),D1                     | vcbAlBlkSiz high word
    JSR         DIVUP(PC)                       | round up to alloc blocks
    MOVE.L      D0,D4                           | D4 = min alloc blocks needed
    MOVEM.L     (A6)+,D0-D1                     | restore
    CLR.W       D7                              | fragment length counter
BLKALLOC_CONT_3:
    CMP.W       D7,D4                           | fragment >= needed?
    BLS.B       BLKALLOC_CONT_4                 | yes, large enough
    CMP.W       A1,D7                           | reached end of volume?
    BEQ.B       BLKALLOC_NO_3                   | yes, fragment too small
    TST.L       D0                              | bit 31 = allocated?
    BMI.B       BLKALLOC_NO_3                   | yes, fragment too small
    ADDQ.W      #0x1,D7                         | extend fragment
    BSR.W       READBM_NEXT                     | NextBit: read next bitmap bit
    TST.W       D1                              | error?
    BMI.W       BKALLOCEXIT                     | yes, exit
    BRA.B       BLKALLOC_CONT_3                 | keep checking fragment
| fragment too small
BLKALLOC_NO_3:
    MOVE.L      (A6)+,D4                        | restore original request (bytes)
    ADD.W       D7,D2                           | advance past this fragment
    CMP.W       A1,D7                           | reached end of volume?
    BCS.B       BLKALLOC_NEXT                   | no, try next position
    BTST        #0xF,D3                         | already wrapped around?
    BNE.B       BLKALLOC_EXIT                   | yes, give up
    BSET        #0xF,D3                         | mark wrapped around
    CLR.W       D2                              | restart from beginning
BLKALLOC_NEXT:
    BTST        #0xF,D3                         | wrapped around?
    BEQ.W       BLKALLOC_LOOP                   | no, keep scanning
    SWAP.W      D3                              | get starting block from high word
    CMP.W       D2,D3                           | back where we started?
    BLS.B       BLKALLOC_EXIT                   | yes, give up
    SWAP.W      D3                              | restore flags
    BRA.W       BLKALLOC_LOOP                   | keep scanning
BLKALLOC_EXIT:
    ROL.L       D1,D0                           | rotate bitmap back into place
    MOVE.L      D0,0x0(A0,D6.W)                 | write back to buffer
    BRA.W       BLKALLOC_EXIT_2                 | exit: disk full
BLKALLOC_CONT_4:
    MOVE.L      (A6)+,D4                        | restore original request (bytes)
    ROL.L       D1,D0                           | rotate bitmap back
    MOVE.L      D0,0x0(A0,D6.W)                 | write back to buffer
    BSR.W       P_ReadBM                        | re-read bitmap for allocation
    TST.W       D1                              | error?
    BMI.W       BKALLOCEXIT                     | yes, exit
BLKALLOC_NO_4:
    MOVEM.L     D0-D1,-(A6)                     | save for RoundAlloc
    MOVE.L      D4,D0                           | bytes to allocate
    MOVE.L      0x1E(A3),D1                     | clump size (FCBClmpSize)
    JSR         ROUNDALLOC(PC)                  | round up to clump boundary
    MOVE.L      D0,D4                           | D4 = rounded alloc blocks
    MOVEM.L     (A6)+,D0-D1                     | restore
    MOVEQ.L     #0x0,D7                         | blocks allocated counter
| mark blocks allocated from the starting block
BLKALLOC_OK_2:
    TST.W       D4                              | all blocks allocated?
    BEQ.B       BKALLOCOK                       | yes, done
    CMP.W       A1,D7                           | reached end of volume?
    BCC.B       BKALLOCOK                       | yes, stop
    TST.L       D0                              | current bit = already allocated?
    BMI.B       BKALLOCOK                       | yes, stop
    TST.W       0x2A(A2)                        | any free blocks left? (vcbFreeBks)
    BEQ.B       BKALLOCOK                       | no, stop
    SUBQ.W      #0x1,0x2A(A2)                   | decrement vcbFreeBks
    JSR         MARKVCB(PC)                     | mark VCB dirty
    BSET        #0x1F,D0                        | mark allocated in bitmap (bit 31)
    ADDQ.W      #0x1,D7                         | count this block
    SUBQ.W      #0x1,D4                         | decrement remaining request
    JSR         MARKBLOCK(PC)                   | mark bitmap block dirty
    BSR.W       READBM_NEXT                     | NextBit: advance to next bit
    TST.W       D1                              | error?
    BGE.B       BLKALLOC_OK_2                   | no, continue
    BRA.B       BKALLOCEXIT                     | error, exit
| BkAllocOK: allocation is done
BKALLOCOK:
    BTST        #0x7,D3                         | update vcbAllocPtr?
    BEQ.B       BLKALLOC_NO_5                   | no, skip
    MOVE.W      D2,D4                           | current alloc position
    CMP.W       0x1A(A2),D4                     | past end? (vcbNmAlBlks)
    BCS.B       BLKALLOC_OK_3                   | no
    CLR.W       D4                              | wrap to 0
BLKALLOC_OK_3:
    MOVE.W      D4,0x18(A2)                     | update vcbAllocPtr
BLKALLOC_NO_5:
    ROL.L       D1,D0                           | rotate bitmap back
    MOVE.L      D0,0x0(A0,D6.W)                 | write back to buffer
    JSR         MARKBLOCK(PC)                   | mark bitmap block dirty
    MOVE.L      D7,D3                           | D3 = blocks allocated (return)
    MOVEQ.L     #0x0,D0                         | noErr
| Called by: BLKALLOC_LOOP, BLKALLOC_NO_2, BLKALLOC_CONT_3, BLKALLOC_CONT_4, BLKALLOC_OK_2 (and 1 more)
BKALLOCEXIT:
    MOVEM.L     (A6)+,D1/D4-D7/A0-A1            | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from BlkAlloc
| bkAllocFull
BLKALLOC_EXIT_2:
    MOVEQ.L     #0x0,D3                         | 0 blocks allocated
    MOVEQ.L     #-0x22,D0                       | dskFulErr (-34)
    BRA.B       BKALLOCEXIT                     | exit
BLKDEALLOC:
    MOVE.L      (0x780).W,-(A7)                 | push BlkDealloc vector address
    RTS                                         | jump to HFS vector
VBLKDEALLOC:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D6/A0,-(A6)                  | save registers
    MOVEQ.L     #0x0,D0                         | assume noErr
    TST.W       D3                              | any blocks to free?
    BEQ.B       BLKDEALLOC_DONE                 | no, done
    BSR.W       P_ReadBM                        | read bitmap block for D2
BLKDEALLOC_CONT:
    TST.W       D1                              | error?
    BMI.B       BLKDEALLOC_DONE                 | yes, exit
    BCLR        #0x1F,D0                        | clear bit 31 (mark free in bitmap)
    JSR         MARKBLOCK(PC)                   | mark bitmap block dirty
    ADDQ.W      #0x1,0x2A(A2)                   | increment vcbFreeBks
    JSR         MARKVCB(PC)                     | mark VCB dirty
    SUBQ.W      #0x1,D3                         | decrement blocks remaining
    BEQ.B       BLKDEALLOC_OK                   | done, write back bitmap
    BSR.W       READBM_NEXT                     | NextBit: advance to next
    BRA.B       BLKDEALLOC_CONT                 | continue freeing
BLKDEALLOC_OK:
    ROL.L       D1,D0                           | rotate bitmap back into place
    MOVE.L      D0,0x0(A0,D6.W)                 | write back to buffer
    MOVEQ.L     #0x0,D0                         | noErr
BLKDEALLOC_DONE:
    MOVEM.L     (A6)+,D1-D6/A0                  | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from BlkDealloc
BLKCHK:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D7/A1,-(A6)                  | save registers
    MOVEA.L     A0,A1                           | A1 = ptr to extent record
    MOVEQ.L     #0x0,D3                         | D3 = error flag (0 = ok)
    MOVEQ.L     #0x0,D7                         | D7 = extent record offset
BLKCHK_NEXT:
    MOVE.W      0x0(A1,D7.W),D2                 | start alloc block from extent
    MOVEQ.L     #0x0,D4                         | clear high word
    MOVE.W      0x2(A1,D7.W),D4                 | block count from extent
    BEQ.B       BLKCHK_DONE                     | empty extent, done
    BSR.B       P_ReadBM                        | read bitmap for start block
    BRA.B       BLKCHK_CONT                     | check first block
BLKCHK_LOOP:
    BSET        #0x1F,D0                        | mark block allocated (bit 31)
    BNE.B       BLKCHK_OK                       | was already set, ok
    MOVEQ.L     #-0x1,D3                        | block was free: flag error
    JSR         MARKBLOCK(PC)                   | mark bitmap dirty
BLKCHK_OK:
    ADDQ.W      #0x1,D2                         | next block number
    ROL.L       #0x1,D0                         | advance to next bit in bitmap
    SUBQ.W      #0x1,D1                         | decrement bits remaining in word
    BGT.B       BLKCHK_CONT                     | bits left in word
    TST.W       D4                              | more blocks to check?
    BEQ.B       BLKCHK_NO                       | no, write back
    BSR.W       READBM_NEXT_2                   | NextWord: load next bitmap word
BLKCHK_CONT:
    TST.W       D1                              | error?
    BMI.B       BLKCHK_ERR                      | yes, exit
    DBF.W       D4,BLKCHK_LOOP                  | check next block
    ROL.L       D1,D0                           | rotate bitmap back
BLKCHK_NO:
    MOVE.L      D0,0x0(A0,D6.W)                 | write bitmap word back
    ADDQ.W      #0x4,D7                         | next extent (4 bytes each)
    CMPI.W      #0xC,D7                         | all 3 extents checked? (3*4=12)
    BCS.B       BLKCHK_NEXT                     | no, check next extent
BLKCHK_DONE:
    MOVE.L      D3,D0                           | return error flag
BLKCHK_ERR:
    MOVEM.L     (A6)+,D1-D7/A1                  | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.L       D0                              | set condition codes
    RTS                                         | exit BlkChk
UPDATEFREE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D0-D6/A0-A1,-(A6)               | save registers
    MOVEQ.L     #0x0,D4                         | D4 = free block counter
    MOVEQ.L     #0x0,D2                         | start at block 0
    BSR.B       P_ReadBM                        | read first bitmap block
    MOVE.W      0x1A(A2),D2                     | D2 = total alloc blocks (vcbNmAlBlks)
UPDATEFREE_LOOP:
    TST.W       D1                              | error?
    BMI.B       UPDATEFREE_ERR                  | yes, exit
    TST.L       D0                              | bit 31 clear? (free block)
    BMI.B       UPDATEFREE_NO                   | no, allocated
    ADDQ.W      #0x1,D4                         | count free block
UPDATEFREE_NO:
    SUBQ.W      #0x1,D2                         | more blocks to scan?
    BEQ.B       UPDATEFREE_DONE                 | no, done
    BSR.B       READBM_NEXT                     | NextBit: advance to next
    BRA.B       UPDATEFREE_LOOP                 | keep scanning
UPDATEFREE_DONE:
    MOVE.W      D4,0x2A(A2)                     | update vcbFreeBks
UPDATEFREE_ERR:
    MOVEM.L     (A6)+,D0-D6/A0-A1               | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    RTS                                         | exit UpdateFree
| Called by: BLKALLOC_LOOP, BLKALLOC_CONT, BLKALLOC_CONT_4, VBLKDEALLOC, BLKCHK_NEXT (and 1 more)
P_ReadBM:
    MOVE.L      (0x7D8).W,-(A7)                 | push ReadBM vector address
    RTS                                         | jump to HFS vector
VREADBM:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVE.W      D2,D5                           | D5 = alloc block number
    LSR.W       #0x8,D5                         | / 256...
    LSR.W       #0x4,D5                         | / 16 = bitmap block number (/4096)
    MOVE.W      D2,D6                           | D6 = alloc block number
    ANDI.W      #0xFE0,D6                       | mask to 32-block groups
    LSR.W       #0x3,D6                         | byte offset within bitmap block
    MOVE.W      D2,D1                           | D1 = alloc block number
    ANDI.W      #0x1F,D1                        | bit within longword (0-31)
    BSR.B       READBM_NEXT_3                   | read bitmap cache block
    BEQ.B       READBM_OK                       | success
    MOVEQ.L     #-0x1,D1                        | error: D1 = -1 (flag)
    BRA.B       READBM_CONT                     | exit with error
READBM_OK:
    MOVE.L      0x0(A0,D6.W),D0                 | get longword from bitmap
    ROL.L       D1,D0                           | rotate target bit to bit 31
    NEG.W       D1                              | D1 = -(bit position)
    ADDI.W      #0x20,D1                        | D1 = bits remaining in word
READBM_CONT:
    MOVE.L      (A6)+,-(A7)                     | restore return address
    RTS                                         | return from ReadBM
| ----------------------------------------------------------
|
| READBM_NEXT - NextBit: advance to next bit in bitmap
|
| Called by: BLKALLOC_CONT_3, BLKALLOC_OK_2, BLKDEALLOC_CONT, UPDATEFREE_NO, READBM_CONT_2
READBM_NEXT:
    MOVE.L      (A7)+,-(A6)                     | save return address
    ROL.L       #0x1,D0                         | rotate to next bit
    SUBQ.W      #0x1,D1                         | decrement bits remaining
    BNE.B       READBM_EXIT                     | more bits in this word
    BSR.B       READBM_NEXT_2                   | NextWord: load next longword
READBM_EXIT:
    MOVE.L      (A6)+,-(A7)                     | restore return address
    RTS                                         | return from NextBit
| ----------------------------------------------------------
|
| READBM_CONT_2 - FrBitScan: scan for next free bit, skipping $FFFFFFFF words
|
READBM_CONT_2:
    MOVE.L      (A7)+,-(A6)                     | save return address
    ADDQ.W      #0x1,D2                         | advance block number
    BSR.B       READBM_NEXT                     | rotate to next bit
READBM_CONT_3:
    CMP.L       (MinusOne).W,D0                 | all-ones word? (all allocated)
    BNE.B       READBM_EXIT                     | no, found a free bit
    ADD.W       D1,D2                           | skip entire word
    CMP.W       A1,D2                           | past end of volume?
    BCC.B       READBM_OK_2                     | yes, back up
    BSR.B       READBM_NEXT_2                   | NextWord: load next word
    BRA.B       READBM_CONT_3                   | keep scanning
READBM_OK_2:
    SUB.W       D1,D2                           | back up starting position
    BRA.B       READBM_EXIT                     | return
READBM_NEXT_2:
    MOVE.L      (A7)+,-(A6)                     | save return address
    MOVE.L      D0,0x0(A0,D6.W)                 | write current word back to buffer
    ADDQ.W      #0x4,D6                         | advance buffer index by 4 bytes
    CMPI.W      #0x200,D6                       | past end of 512-byte block?
    BCS.B       READBM_NO                       | no, still in same block
    ADDQ.W      #0x1,D5                         | next bitmap block number
    BSR.B       READBM_NEXT_3                   | GetBMBlk: read next bitmap block
    BEQ.B       READBM_OK_3                     | success
    MOVEQ.L     #-0x1,D1                        | error: D1 = -1 (flag)
    BRA.B       READBM_CONT_4                   | exit with error
READBM_OK_3:
    CLR.W       D6                              | reset buffer index to start
READBM_NO:
    MOVE.L      0x0(A0,D6.W),D0                 | get next bitmap longword
    MOVEQ.L     #0x20,D1                        | 32 bits in this word
READBM_CONT_4:
    MOVE.L      (A6)+,-(A7)                     | restore return address
    RTS                                         | return from NextWord
| ----------------------------------------------------------
|
| READBM_NEXT_3 - GetBMBlk: read a volume bitmap block from cache
|
READBM_NEXT_3:
    MOVE.L      (A7)+,-(A6)                     | save return address
    MOVEM.L     D1-D2/A1-A2,-(A6)               | save registers
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum: volume refnum
    MOVEQ.L     #0x0,D2                         | clear high word
    MOVE.W      0x16(A2),D2                     | vcbVBMSt: bitmap start block
    ADD.W       D5,D2                           | + bitmap block offset
    MOVEA.L     0x50(A2),A1                     | vcbMAdr: bitmap cache queue
    MOVEQ.L     #0x8,D1                         | GBrelease option
    JSR         GETBLOCK(PC)                    | get the bitmap block
    MOVEM.L     (A6)+,D1-D2/A1-A2               | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from GetBMBlk
| Apple source module: FXM
DEALLOCFILE:
    MOVE.L      (0x764).W,-(A7)                 | push DeallocFile vector address
    RTS                                         | jump to HFS vector
VDEALLOCFILE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D7/A0-A1/A3-A4,-(A6)         | save registers
    BSR.W       TRUNCATEFILE_CONT_4             | FXSetUp: set up common vars
    MOVEA.L     A0,A3                           | A3 = ptr to CName
    MOVE.L      D0,D7                           | D7 = parent DirID
    CLR.B       D6                              | D6 = fork type (0 = data fork)
DEALLOCFILE_CONT:
    CLR.W       D4                              | initial FABN = 0
    MOVEA.L     A3,A0                           | ptr to CName
    MOVE.L      D7,D0                           | parent DirID
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         CMGETCN(PC)                     | CMGetCN: locate catalog record
    BNE.W       DEALLOCFILE_ERR                 | error
    CMPI.B      #0x2,(A1)                       | file CNode? (cdrFilRec)
    BEQ.B       DEALLOCFILE_OK                  | yes
    MOVEQ.L     #0x30,D0                        | CMnotfound
    BNE.W       DEALLOCFILE_ERR                 | not a file, error
DEALLOCFILE_OK:
    MOVE.L      0x14(A1),D5                     | D5 = file number (filFlNum)
    LEA.L       0x2(A4),A0                      | ptr to FXM key buffer
    CLR.W       0x6(A0)                         | xkrFABN = 0 (catalog resident)
    TST.B       D6                              | data fork?
    BNE.B       DEALLOCFILE_NO                  | no, resource fork
    LEA.L       0x4A(A1),A1                     | data fork extents (filExtRec)
    BRA.B       DEALLOCFILE_FOUND               | copy extent record
DEALLOCFILE_NO:
    LEA.L       0x56(A1),A1                     | rsrc fork extents (filRExtRec)
    BRA.B       DEALLOCFILE_FOUND               | copy extent record
| DFRecLoop: set up key for next extent file record
DEALLOCFILE_NEXT:
    LEA.L       0x2(A4),A0                      | ptr to FXM key buffer
    MOVE.B      #0x7,(A0)                       | key length (lenxkr-1)
    MOVE.B      D6,0x1(A0)                      | fork type (xkrFkType)
    MOVE.L      D5,0x2(A0)                      | file number (xkrFNum)
    MOVE.W      D4,0x6(A0)                      | file alloc block number (xkrFABN)
    MOVE.W      0xA4(A2),D0                     | extents file refnum (VCBXTRef)
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         BTSEARCH(PC)                    | BTSearch: find extent record
    BEQ.B       DEALLOCFILE_FOUND               | found it
    CMPI.W      #0x20,D0                        | BTnotfound?
    BEQ.B       DEALLOCFILE_DONE                | yes, done with this fork
    BRA.B       DEALLOCFILE_ERR                 | error
| DFCopyRec: copy extent data to FXM buffer
DEALLOCFILE_FOUND:
    LEA.L       0xA(A4),A0                      | dest = xdr buffer in FXM vars
    MOVEQ.L     #0x2,D0                         | 3 longwords (12 bytes)
DEALLOCFILE_LOOP:
    MOVE.L      (A1)+,(A0)+                     | copy extent record
    DBF.W       D0,DEALLOCFILE_LOOP             | loop for 3 longwords
    LEA.L       0xA(A4),A1                      | A1 = ptr to extent record copy
    CLR.W       D1                              | offset to first extent
DEALLOCFILE_NEXT_2:
    MOVE.W      0x0(A1,D1.W),D2                 | start alloc block (xdrStABN)
    MOVE.W      0x2(A1,D1.W),D3                 | block count (xdrNumABlks)
    BEQ.B       DEALLOCFILE_NO_2                | extent empty, delete record
    JSR         BLKDEALLOC(PC)                  | BlkDealloc: free the blocks
    BNE.B       DEALLOCFILE_ERR                 | error
    ADD.W       D3,D4                           | bump FABN past this extent
    ADDQ.W      #0x4,D1                         | next extent descriptor (4 bytes)
    CMPI.W      #0x8,D1                         | past last extent? (3 * 4 = 12)
    BLE.B       DEALLOCFILE_NEXT_2              | no, free next extent
| DFDelRec: delete extent record from extents B-tree
DEALLOCFILE_NO_2:
    LEA.L       0x2(A4),A0                      | ptr to search key
    TST.W       0x6(A0)                         | catalog resident? (xkrFABN = 0)
    BEQ.B       DEALLOCFILE_OK_2                | yes, nothing to delete
    MOVE.W      0xA4(A2),D0                     | extents file refnum (VCBXTRef)
    JSR         BTDELETE(PC)                    | BTDelete: delete extent record
    BNE.B       DEALLOCFILE_ERR                 | error
DEALLOCFILE_OK_2:
    TST.W       D3                              | ended with null extent?
    BNE.B       DEALLOCFILE_NEXT                | no, get next record for same fork
DEALLOCFILE_DONE:
    NOT.B       D6                              | toggle fork type (data <-> rsrc)
    BNE.W       DEALLOCFILE_CONT                | was data fork, now do resource fork
    CLR.W       D0                              | noErr
    BSR.W       TRUNCATEFILE_CONT_5             | flush extents B-tree
| Called by: DEALLOCFILE_CONT, DEALLOCFILE_NEXT, DEALLOCFILE_NEXT_2, DEALLOCFILE_NO_2
DEALLOCFILE_ERR:
    ADDA.W      #0x16,A6                        | skip FXM local vars on A6 stack
    MOVEM.L     (A6)+,D1-D7/A0-A1/A3-A4         | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from DeallocFile
EXTENDFILE:
    MOVE.L      (0x768).W,-(A7)                 | push ExtendFile vector address
    RTS                                         | jump to HFS vector
VEXTENDFILE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D5/D7/A0-A4,-(A6)            | save registers
    BSR.W       TRUNCATEFILE_CONT_4             | FXSetUp: set up common vars
    LEA.L       0x0(A1,D1.W),A3                 | A3 = FCB pointer
    MOVE.L      0xC(A3),-(A6)                   | save previous PEOF (FCBPLen)
    BTST        #0x0,D3                         | contiguous requested? (EFContig)
    BEQ.B       EXTENDFILE_TRY_CONTIG           | no, skip space check
    MOVE.W      0x2A(A2),D0                     | vcbFreeBks: free blocks
    MULU.W      0x1E(A2),D0                     | * alloc blk size = free bytes
    CMP.L       D4,D0                           | enough free space?
    BCC.B       EXTENDFILE_TRY_CONTIG           | yes, proceed
    MOVEQ.L     #-0x22,D0                       | dskFulErr (-34)
    BRA.W       EXTENDFILE_ERR                  | not enough for contiguous alloc
EXTENDFILE_TRY_CONTIG:
    BSET        #0x6,(A4)                       | FXVTContig: try contig first
    BTST        #0x1,D3                         | forced contiguous? (EFForce)
    BEQ.B       EXTENDFILE_FORCED_CONTIG        | no
    BSET        #0x7,(A4)                       | FXVFContig: forced contig flag
EXTENDFILE_FORCED_CONTIG:
    MOVE.L      0x1C(A2),D0                     | vcbAlBlkSiz: alloc block size
    ADD.L       D0,D4                           | D4 + AlBlkSiz (for rounding)
    SUBQ.L      #0x1,D4                         | -1 for integer division
    DIVU.W      D0,D4                           | / AlBlkSiz = blocks needed
    MULU.W      D0,D4                           | rounded up to alloc boundary
    MOVE.L      0xC(A3),D0                      | current PEOF (FCBPLen)
    ADD.L       D4,D0                           | + requested = new PEOF
    SUBQ.L      #0x1,D0                         | -1 = last byte in file
    BSR.W       P_XFSearch                      | XFSearch: locate the extent
    BNE.B       EXTENDFILE_CONT                 | extent not found, allocate
    ADD.L       D4,0xC(A3)                      | update PEOF (FCBPLen)
    BSET        #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
    BRA.W       EXTENDFILE_DONE                 | done, exit success
EXTENDFILE_CONT:
    CMPI.W      #0x10,D0                        | FXRangeErr? (out of extent range)
    BNE.W       EXTENDFILE_ERR                  | no, some other error
    MOVE.L      D2,D7                           | D7 = B-tree hint
    MOVE.W      D3,D6                           | D6 = ending FABN + 1
    MOVE.W      D6,D0                           | (ending FABN + 1)
    MULU.W      0x1E(A2),D0                     | * alloc blk size = max PEOF for extent
    SUB.L       0xC(A3),D0                      | PEOF already at end of extent?
    BEQ.B       EXTENDFILE_RETRY                | yes, start allocating
    ADD.L       D0,0xC(A3)                      | adjust PEOF to end of extent
    BSET        #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
    SUB.L       D0,D4                           | adjust remaining count
| EFAddSpace: allocate additional disk space
EXTENDFILE_RETRY:
    MOVE.W      0x0(A1,D1.W),D5                 | start alloc block (xdrStABN)
    ADD.W       0x2(A1,D1.W),D5                 | + num blocks = last + 1
EXTENDFILE_CONT_2:
    MOVE.W      D5,D2                           | preferred start = last + 1
    BTST        #0x6,(A4)                       | trying contig? (FXVTContig)
    SNE.B       D3                              | set flag for BlkAlloc
    JSR         BLKALLOC(PC)                    | BlkAlloc: allocate disk space
    BEQ.B       EXTENDFILE_CONT_3               | got it
    CMPI.W      #0xFFDE,D0                      | dskFulErr (-34)?
    BNE.W       EXTENDFILE_ERR                  | no, some other error
    BCLR        #0x6,(A4)                       | just tried contig?
    BEQ.W       EXTENDFILE_ERR                  | no, must be out of space
    BTST        #0x7,(A4)                       | forced contig? (FXVFContig)
    BNE.W       EXTENDFILE_ERR                  | yes, couldn't get it
    BRA.B       EXTENDFILE_CONT_2               | retry non-contiguous
| EFExtExt: see if current extent can be extended
EXTENDFILE_CONT_3:
    CMP.W       D2,D5                           | got preferred (contiguous) space?
    BNE.B       EXTENDFILE_NO_2                 | no, must add new extent
    ADD.W       D3,0x2(A1,D1.W)                 | extend current extent (xdrNumABlks)
    BRA.B       EXTENDFILE_CONT_4               | update extent record
| ----------------------------------------------------------
|
| EXTENDFILE_NO_2
|
| EFAddExt: add a new extent entry
EXTENDFILE_NO_2:
    TST.W       0x2(A1,D1.W)                    | current extent null? (xdrNumABlks)
    BEQ.B       EXTENDFILE_OK                   | yes, reuse it
    ADDQ.W      #0x4,D1                         | bump to next extent (lenExt)
    CMPI.W      #0x8,D1                         | past last extent? (maxExtOff)
    BGT.B       EXTENDFILE_OK_2                 | yes, need new B-tree record
EXTENDFILE_OK:
    MOVE.W      D2,0x0(A1,D1.W)                 | set start block (xdrStABN)
    MOVE.W      D3,0x2(A1,D1.W)                 | set block count (xdrNumABlks)
EXTENDFILE_CONT_4:
    MOVE.L      D7,D2                           | B-tree hint
    BSR.W       XFSEARCH_CONT_4                 | XRUpdate: update extent record
    BNE.W       EXTENDFILE_ERR                  | error
    MOVE.L      D2,D7                           | D7 = new hint
    BRA.B       EXTENDFILE_CONT_5               | go update FCB
| ----------------------------------------------------------
|
| EXTENDFILE_OK_2
|
| EFNewRec: add a new extent record
EXTENDFILE_OK_2:
    MOVE.L      (A3),D5                         | file number (FCBFlNm)
    CMPI.L      #0x3,D5                         | extents file itself? (FSXtCNID)
    BNE.B       EXTENDFILE_NO_3                 | no, proceed
    MOVEQ.L     #0x11,D0                        | FXOvFlErr (extent file overflow)
    BRA.B       EXTENDFILE_ERR                  | can't extend extents file
| ----------------------------------------------------------
|
| EXTENDFILE_NO_3
|
EXTENDFILE_NO_3:
    LEA.L       0x2(A4),A0                      | ptr to FXM key buffer
    LEA.L       0xA(A4),A1                      | ptr to FXM data buffer
    MOVE.B      #0x7,(A0)                       | key length (lenxkr-1)
    CLR.B       0x1(A0)                         | assume data fork (xkrFkType)
    BTST        #0x1,0x4(A3)                    | resource fork? (FCBRscBit)
    SNE.B       0x1(A0)                         | set fork type flag
    MOVE.L      D5,0x2(A0)                      | file number (xkrFNum)
    MOVE.W      D6,0x6(A0)                      | starting FABN (xkrFABN)
    MOVE.W      #0x5,D0                         | (12/2)-1 = 5 words
EXTENDFILE_LOOP:
    CLR.W       (A1)+                           | clear extent record
    DBF.W       D0,EXTENDFILE_LOOP              | zero all 12 bytes
    LEA.L       0xA(A4),A1                      | restore ptr to xdr buffer
    CLR.W       D1                              | first extent
    MOVE.W      D2,0x0(A1,D1.W)                 | set start block (xdrStABN)
    MOVE.W      D3,0x2(A1,D1.W)                 | set block count (xdrNumABlks)
    MOVE.L      D1,-(A6)                        | save D1
    MOVE.W      #0xC,D1                         | record length (lenxdr = 12)
    MOVE.W      0xA4(A2),D0                     | extents file refnum (VCBXTRef)
    JSR         BTINSERT(PC)                    | BTInsert: insert new extent record
    MOVE.L      (A6)+,D1                        | restore D1
    TST.W       D0                              | BTInsert result
    BNE.B       EXTENDFILE_ERR                  | error
    MOVE.L      D2,D7                           | D7 = new B-tree hint
| EFUpdFCB: update FCB and see if more space is needed
EXTENDFILE_CONT_5:
    ADD.W       D3,D6                           | update ending FABN + 1
    MULU.W      0x1E(A2),D3                     | blocks * alloc blk size = bytes
    ADD.L       D3,0xC(A3)                      | adjust PEOF (FCBPLen)
    BSET        #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
    SUB.L       D3,D4                           | allocated enough space?
    BGT.W       EXTENDFILE_RETRY                | no, allocate more
    ADD.L       D4,0xC(A3)                      | adjust PEOF to alloc boundary
EXTENDFILE_DONE:
    CLR.W       D0                              | noErr
    BSR.W       TRUNCATEFILE_CONT_5             | XFFlush: flush extents B-tree
| Called by: EXTENDFILE_CONT_2, VEXTENDFILE, EXTENDFILE_CONT, EXTENDFILE_CONT_4, EXTENDFILE_OK_2 (and 1 more)
EXTENDFILE_ERR:
    MOVE.L      0xC(A3),D6                      | new PEOF (FCBPLen)
    MOVE.L      (A6)+,D1                        | - previous PEOF
    SUB.L       D1,D6                           | D6 = bytes actually allocated
    ADDA.W      #0x16,A6                        | deallocate FXM vars
    MOVEM.L     (A6)+,D1-D5/D7/A0-A4            | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from ExtendFile
FXMKEYCMP:
    MOVEM.L     A0-A1,-(A7)                     | save registers
    MOVE.L      0x2(A0),D0                      | compare file numbers (xkrFNum)
    CMP.L       0x2(A1),D0                      | search vs. trial
    BHI.B       FXMKEYCMP_CONT_2                | search > trial
    BCS.B       FXMKEYCMP_CONT                  | search < trial
    MOVE.B      0x1(A0),D0                      | compare fork types (xkrFkType)
    CMP.B       0x1(A1),D0                      | search vs. trial
    BHI.B       FXMKEYCMP_CONT_2                | search > trial
    BCS.B       FXMKEYCMP_CONT                  | search < trial
    MOVE.W      0x6(A0),D0                      | compare FABNs (xkrFABN)
    CMP.W       0x6(A1),D0                      | search vs. trial
    BHI.B       FXMKEYCMP_CONT_2                | search > trial
    BCS.B       FXMKEYCMP_CONT                  | search < trial
    CLR.W       D0                              | equal: return 0
    BRA.B       FXMKEYCMP_EXIT                  | exit
| KCIsLT
FXMKEYCMP_CONT:
    MOVE.W      #0xFFFF,D0                      | less than: return -1
    BRA.B       FXMKEYCMP_EXIT                  | exit
FXMKEYCMP_CONT_2:
    MOVE.W      #0x1,D0                         | greater than: return +1
FXMKEYCMP_EXIT:
    MOVEM.L     (A7)+,A0-A1                     | restore registers
    TST.W       D0                              | set condition codes
    RTS                                         | return from FXMKeyCmp
MAPFBLOCK:
    MOVE.L      (0x7D0).W,-(A7)                 | push MapFBlock vector address
    RTS                                         | jump to HFS vector
VMAPFBLOCK:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D2/D4-D5/D7/A0-A1/A3-A4,-(A6) | save registers
    BSR.W       TRUNCATEFILE_CONT_4             | FXSetUp: set up common vars
    LEA.L       0x0(A1,D1.W),A3                 | A3 = FCB pointer
    MOVE.L      D5,D0                           | D0 = file byte position
    BSR.W       P_XFSearch                      | XFSearch: locate extent for byte pos
    BNE.B       MAPFBLOCK_EXIT                  | error
    LEA.L       0x0(A1,D1.W),A1                 | A1 = extent record
    MOVE.W      D3,D1                           | D1 = ending FABN + 1
    SUB.W       0x2(A1),D1                      | - block count = FABN of this extent
    MOVE.W      D3,D2                           | D2 = ending FABN + 1
    MULU.W      0x1E(A2),D2                     | * alloc blk size = end byte pos
    MOVE.L      0xC(A3),D0                      | D0 = PEOF (FCBPLen)
    CMP.L       D0,D2                           | end pos > PEOF?
    BLE.B       MAPFBLOCK_NO                    | no, use end pos
    MOVE.L      D0,D2                           | limit to PEOF
MAPFBLOCK_NO:
    DIVU.W      0x1E(A2),D2                     | / alloc blk size = ending alloc block
    MOVE.L      0x1C(A2),D6                     | vcbAlBlkSiz
    DIVU.W      #0x200,D6                       | / 512 = blocks per alloc block
    MOVEQ.L     #0x0,D7                         | clear high word
    MOVE.W      0x24(A2),D7                     | vcbAlBlSt: alloc block start
    MOVE.L      D5,D3                           | D3 = file byte position
    DIVU.W      0x1E(A2),D3                     | / alloc blk size = FABN.remainder
    SWAP.W      D3                              | D3.W = remainder (byte within block)
    MOVEQ.L     #0x0,D0                         | clear for shift
    MOVE.W      D3,D0                           | byte offset within alloc block
    LSR.L       #0x8,D0                         | / 256...
    LSR.L       #0x1,D0                         | / 2 = 512-byte block within alloc block
    SWAP.W      D3                              | D3 = FABN
    SUB.W       D1,D3                           | - FABN of this extent
    ADD.W       (A1),D3                         | + start alloc block (xdrStABN)
    MULU.W      D6,D3                           | * blocks per alloc block
    ADD.W       D0,D3                           | + block within alloc block
    ADD.L       D7,D3                           | + volume alloc start = disk block
    MOVE.W      D2,D6                           | ending alloc block
    MULU.W      0x1E(A2),D6                     | * alloc blk size = end byte pos
    SUB.L       D5,D6                           | - start pos = contiguous bytes
    CMP.L       D4,D6                           | more than requested?
    BCS.B       MAPFBLOCK_CONT                  | no, use actual
    MOVE.L      D4,D6                           | limit to requested
MAPFBLOCK_CONT:
    MOVEQ.L     #0x0,D0                         | noErr
| MFExit
MAPFBLOCK_EXIT:
    ADDA.W      #0x16,A6                        | deallocate FXM vars
    MOVEM.L     (A6)+,D1-D2/D4-D5/D7/A0-A1/A3-A4 | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from MapFBlock
TRUNCATEFILE:
    MOVE.L      (0x76C).W,-(A7)                 | push TruncateFile vector address
    RTS                                         | jump to HFS vector
VTRUNCATEFILE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D7/A0-A4,-(A6)               | save registers
    BSR.W       TRUNCATEFILE_CONT_4             | FXSetUp: set up common vars
    LEA.L       0x0(A1,D1.W),A3                 | A3 = FCB pointer
    MOVE.B      D2,D6                           | D6 = truncate options
    MOVE.L      D3,D5                           | D5 = new PEOF
    MOVE.L      0x1C(A2),D0                     | vcbAlBlkSiz: alloc block size
    ADD.L       D0,D5                           | D5 + AlBlkSiz (for rounding)
    SUBQ.L      #0x1,D5                         | -1 for integer division
    DIVU.W      D0,D5                           | / AlBlkSiz = blocks needed
    MULU.W      D0,D5                           | rounded up to alloc boundary
    MOVE.L      D5,D0                           | new PEOF - 1
    SUBQ.L      #0x1,D0                         | point to last byte
    BGE.B       TRUNCATEFILE_FIND_EXTENT        | new PEOF > 0
    MOVE.L      D5,0xC(A3)                      | update PEOF in FCB (FCBPLen)
    BSET        #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
    SUBA.L      A0,A0                           | indicate FCB resident record
    MOVEQ.L     #0x0,D7                         | no B-tree hint
    LEA.L       0x26(A3),A1                     | FCB extent record (FCBExtRec)
    CLR.W       D4                              | FABN = 0
    BRA.W       TRUNCATEFILE_CONT_3             | release all extents
TRUNCATEFILE_FIND_EXTENT:
    BSR.W       P_XFSearch                      | XFSearch: locate the extent
    BNE.W       TRUNCATEFILE_ERR                | error
    MOVE.L      D2,D7                           | D7 = B-tree hint
    MOVE.W      D3,D4                           | D4 = ending FABN + 1
    MOVE.L      D5,0xC(A3)                      | update PEOF (FCBPLen)
    BSET        #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
    BTST        #0x0,D6                         | truncate to extent boundary?
    BEQ.B       TRUNCATEFILE_NO                 | no, truncate to new PEOF
    MOVE.W      0x2(A1,D1.W),D3                 | block count (xdrNumABlks)
    BRA.W       TRUNCATEFILE_EMPTY              | skip to releasing remaining extents
| TFTrunPEOF: truncate extent containing new PEOF
TRUNCATEFILE_NO:
    MOVE.L      D5,D0                           | new PEOF
    SUBQ.L      #0x1,D0                         | last byte in file
    DIVU.W      0x1E(A2),D0                     | / alloc blk size = last FABN
    SUB.W       D0,D3                           | (ending FABN+1) - last FABN
    SUBQ.W      #0x1,D3                         | -1 = blocks to deallocate
    BEQ.B       TRUNCATEFILE_CONT_2             | nothing to deallocate
    MOVE.W      0x0(A1,D1.W),D2                 | start block (xdrStABN)
    ADD.W       0x2(A1,D1.W),D2                 | + num blocks in extent
    SUB.W       D3,D2                           | - to dealloc = first block to free
    JSR         BLKDEALLOC(PC)                  | BlkDealloc: free the blocks
    BNE.W       TRUNCATEFILE_ERR                | error
TRUNCATEFILE_CONT_2:
    MOVE.W      D3,D0                           | blocks deallocated
    MOVE.W      0x2(A1,D1.W),D3                 | original block count (xdrNumABlks)
    SUB.W       D0,0x2(A1,D1.W)                 | update extent block count
    BNE.B       TRUNCATEFILE_EMPTY              | extent not empty
    CLR.W       0x0(A1,D1.W)                    | set extent null (xdrStABN = 0)
    BRA.B       TRUNCATEFILE_EMPTY              | release remaining extents
TRUNCATEFILE_RELEASE_EXTENT:
    LEA.L       0x2(A4),A0                      | ptr to FXM key buffer
    MOVE.B      #0x7,(A0)                       | key length (lenxkr-1)
    BTST        #0x1,0x4(A3)                    | resource fork? (FCBRscBit)
    SNE.B       0x1(A0)                         | set fork type (xkrFkType)
    MOVE.L      (A3),0x2(A0)                    | file number (xkrFNum = FCBFlNm)
    MOVE.W      D4,0x6(A0)                      | file alloc block number (xkrFABN)
    MOVE.W      0xA4(A2),D0                     | extents file refnum (VCBXTRef)
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         BTSEARCH(PC)                    | BTSearch: find extent record
    BEQ.B       TRUNCATEFILE_FOUND              | found it
    CMPI.W      #0x20,D0                        | BTnotfound?
    BEQ.B       TRUNCATEFILE_DONE               | yes, all done
    BRA.B       TRUNCATEFILE_ERR                | error
TRUNCATEFILE_FOUND:
    MOVE.L      D2,D7                           | save B-tree hint
    LEA.L       0xA(A4),A0                      | dest = xdr buffer in FXM
    MOVEQ.L     #0x2,D0                         | 3 longwords (12 bytes)
TRUNCATEFILE_LOOP:
    MOVE.L      (A1)+,(A0)+                     | copy extent record
    DBF.W       D0,TRUNCATEFILE_LOOP            | loop for 3 longwords
    LEA.L       0x2(A4),A0                      | A0 = search key
    LEA.L       0xA(A4),A1                      | A1 = extent record copy
TRUNCATEFILE_CONT_3:
    CLR.W       D1                              | offset to first extent
TRUNCATEFILE_NEXT_2:
    MOVE.W      0x0(A1,D1.W),D2                 | start alloc block (xdrStABN)
    MOVE.W      0x2(A1,D1.W),D3                 | block count (xdrNumABlks)
    BEQ.B       TRUNCATEFILE_NO_2               | extent empty, update record
    JSR         BLKDEALLOC(PC)                  | BlkDealloc: free the blocks
    BNE.B       TRUNCATEFILE_ERR                | error
    CLR.L       0x0(A1,D1.W)                    | set extent null
    ADD.W       D3,D4                           | bump FABN past this extent
| TFRelRExt
TRUNCATEFILE_EMPTY:
    ADDQ.W      #0x4,D1                         | next extent (4 bytes)
    CMPI.W      #0x8,D1                         | past last extent? (3 * 4 = 12)
    BLE.B       TRUNCATEFILE_NEXT_2             | no, release next
TRUNCATEFILE_NO_2:
    TST.W       0x2(A1)                         | first extent null?
    BEQ.B       TRUNCATEFILE_OK                 | yes, delete record
    MOVE.L      D7,D2                           | B-tree hint
    BSR.W       XFSEARCH_CONT_4                 | XRUpdate: update extent record
    BRA.B       TRUNCATEFILE_DELETE_REC         | continue
TRUNCATEFILE_OK:
    MOVE.L      A0,D0                           | FCB resident record? (A0 = 0)
    BEQ.B       TRUNCATEFILE_DELETE_REC         | yes, nothing to delete
    MOVE.W      0xA4(A2),D0                     | extents file refnum (VCBXTRef)
    JSR         BTDELETE(PC)                    | BTDelete: delete extent record
    BNE.B       TRUNCATEFILE_ERR                | error
TRUNCATEFILE_DELETE_REC:
    TST.W       D3                              | more extents to process?
    BNE.W       TRUNCATEFILE_RELEASE_EXTENT     | yes, get next record
| TFExit
TRUNCATEFILE_DONE:
    CLR.W       D0                              | noErr
    BSR.B       TRUNCATEFILE_CONT_5             | XFFlush: flush extents B-tree
| Called by: TRUNCATEFILE_FIND_EXTENT, TRUNCATEFILE_NO, TRUNCATEFILE_RELEASE_EXTENT, TRUNCATEFILE_NEXT_2, TRUNCATEFILE_OK
TRUNCATEFILE_ERR:
    ADDA.W      #0x16,A6                        | deallocate FXM vars
    MOVEM.L     (A6)+,D1-D7/A0-A4               | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from TruncateFile
| ----------------------------------------------------------
|
| TRUNCATEFILE_CONT_4 - FXSetUp: allocate FXM vars on A6 stack
|
TRUNCATEFILE_CONT_4:
    SUBA.W      #0x16,A6                        | allocate FXM vars on A6 stack
    MOVEA.L     A6,A4                           | A4 = FXM var base
    CLR.B       (A4)                            | clear FXM flags
    RTS                                         | return from FXSetUp
TRUNCATEFILE_CONT_5:
    MOVE.L      (A7)+,-(A6)                     | save return address
    MOVEM.L     D1/A1,-(A6)                     | save registers
    MOVE.W      0xA4(A2),D1                     | extents file refnum (VCBXTRef)
    MOVE.W      D1,D0                           | for BTFlush call
    JSR         BTFLUSH(PC)                     | BTFlush: flush extents B-tree
    BNE.B       CLOSEFILE_NOERR_RESTORE         | error
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array base
    BTST        #0x7,0x4(A1,D1.W)               | extents file dirty? (FCBModBit)
    BEQ.B       CLOSEFILE_FLUSH_MDB             | no, done
    JSR         MARKVCB(PC)                     | mark VCB dirty
    JSR         FLUSHMDB(PC)                    | flush master directory block
    BNE.B       CLOSEFILE_NOERR_RESTORE         | error
CLOSEFILE_FLUSH_MDB:
    CLR.W       D0                              | noErr
CLOSEFILE_NOERR_RESTORE:
    MOVEM.L     (A6)+,D1/A1                     | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from XFFlush
P_XFSearch:
    MOVE.L      (0x7D4).W,-(A7)                 | push XFSearch vector address
    RTS                                         | jump to HFS vector
VXFSEARCH:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D4-D6,-(A6)                     | save registers
    MOVE.L      D0,D4                           | D4 = file position to map
    DIVU.W      0x1E(A2),D4                     | / alloc blk size = FABN
    MOVE.L      (A3),D5                         | D5 = file number (FCBFlNm)
    SUBA.L      A0,A0                           | indicate FCB resident record
    MOVEQ.L     #0x0,D2                         | no B-tree hint
    LEA.L       0x26(A3),A1                     | FCB extent record (FCBExtRec)
    MOVE.W      D4,D0                           | desired FABN
    CLR.W       D3                              | starting FABN = 0
    BSR.W       XFSEARCH_CONT_2                 | XRSearch: search FCB extents
    BEQ.W       XFSEARCH_FOUND_2                | found in FCB, done
    CMPI.W      #0x8,D1                         | ended before last extent?
    BLT.W       XFSEARCH_ERR                    | yes, no more extents
    TST.W       0x2(A1,D1.W)                    | null extent at end? (xdrNumABlks)
    BEQ.W       XFSEARCH_ERR                    | yes, no more extents
    CMPI.L      #0x3,D5                         | extents file? (FSXtCNID)
    BEQ.W       XFSEARCH_ERR                    | can't overflow extents file
    LEA.L       0x2(A4),A0                      | ptr to FXM key buffer
    MOVE.B      #0x7,(A0)                       | key length (lenxkr-1)
    BTST        #0x1,0x4(A3)                    | resource fork? (FCBRscBit)
    SNE.B       D6                              | D6 = fork type flag
    MOVE.B      D6,0x1(A0)                      | fork type (xkrFkType)
    MOVE.L      D5,0x2(A0)                      | file number (xkrFNum)
    MOVE.W      D4,0x6(A0)                      | desired FABN (xkrFABN)
    MOVE.W      0xA4(A2),D0                     | extents file refnum (VCBXTRef)
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         BTSEARCH(PC)                    | BTSearch: search extents B-tree
    BEQ.B       XFSEARCH_FOUND                  | direct hit
    CMPI.W      #0x20,D0                        | BTnotfound?
    BNE.B       XFSEARCH_ERR                    | no, error
    MOVE.W      0xA4(A2),D0                     | extents file refnum
    MOVEQ.L     #-0x1,D1                        | previous record
    JSR         BTGETRECORD(PC)                 | BTGetRecord: get previous
    BEQ.B       XFSEARCH_CONT                   | got it
    CMPI.W      #0x20,D0                        | BTnotfound?
    BEQ.B       XFSEARCH_OK                     | no previous, use FCB extents
    BRA.B       XFSEARCH_ERR                    | error
XFSEARCH_CONT:
    CMP.L       0x2(A0),D5                      | same file? (xkrFNum)
    BNE.B       XFSEARCH_OK                     | no, wrong file
    CMP.B       0x1(A0),D6                      | same fork? (xkrFkType)
    BEQ.B       XFSEARCH_FOUND                  | yes, found it
XFSEARCH_OK:
    SUBA.L      A0,A0                           | indicate FCB resident record
    MOVEQ.L     #0x0,D2                         | no hint
    LEA.L       0x26(A3),A1                     | point to FCB extent record
    MOVE.W      #0x8,D1                         | last extent offset (maxExtOff)
    MOVEQ.L     #0x10,D0                        | FXRangeErr
    BRA.B       XFSEARCH_ERR                    | exit with range error
| ----------------------------------------------------------
|
| XFSEARCH_FOUND
|
| FSCopyRec: found extent record, copy key and data into FXM vars
XFSEARCH_FOUND:
    MOVE.L      A1,-(A7)                        | save ptr to xdr in cache
    LEA.L       0x2(A4),A1                      | dest = key buffer in FXM
    MOVEQ.L     #0x1,D0                         | 2 longwords (8-byte key)
XFSEARCH_LOOP:
    MOVE.L      (A0)+,(A1)+                     | copy key record
    DBF.W       D0,XFSEARCH_LOOP                | loop for 2 longwords
    MOVEA.L     (A7)+,A0                        | source = xdr in cache
    LEA.L       0xA(A4),A1                      | dest = xdr buffer in FXM
    MOVEQ.L     #0x2,D0                         | 3 longwords (12-byte data)
XFSEARCH_LOOP_2:
    MOVE.L      (A0)+,(A1)+                     | copy data record
    DBF.W       D0,XFSEARCH_LOOP_2              | loop for 3 longwords
    LEA.L       0x2(A4),A0                      | A0 = xkr in FXM
    LEA.L       0xA(A4),A1                      | A1 = xdr in FXM
    MOVE.W      0x6(A0),D3                      | beginning FABN (xkrFABN)
    MOVE.W      D4,D0                           | desired FABN
    BSR.B       XFSEARCH_CONT_2                 | XRSearch: find extent in record
    BNE.B       XFSEARCH_ERR                    | not found
| FSExit
XFSEARCH_FOUND_2:
    CLR.W       D0                              | noErr
| Called by: VXFSEARCH, XFSEARCH_OK, XFSEARCH_LOOP_2
XFSEARCH_ERR:
    MOVEM.L     (A6)+,D4-D6                     | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from XFSearch
| ----------------------------------------------------------
|
| XFSEARCH_CONT_2
|
| XRSearch: search extent record for extent mapping a given FABN
| D0=desired FABN, A1=ptr to xdr, D3=beginning FABN for record
XFSEARCH_CONT_2:
    MOVE.L      D2,-(A7)                        | save D2
    MOVE.W      D0,D2                           | D2 = desired FABN
    CLR.W       D1                              | D1 = extent offset
XFSEARCH_NO:
    MOVE.W      0x2(A1,D1.W),D0                 | block count (xdrNumABlks)
    BEQ.B       XFSEARCH_EMPTY                  | null extent
    ADD.W       D0,D3                           | ending FABN + 1
    CMP.W       D2,D3                           | desired FABN within this extent?
    BHI.B       XFSEARCH_DONE                   | yes, found
    ADDQ.W      #0x4,D1                         | next extent (lenExt)
    CMPI.W      #0x8,D1                         | past last extent? (maxExtOff)
    BLE.B       XFSEARCH_NO                     | no, continue
XFSEARCH_EMPTY:
    SUBQ.W      #0x4,D1                         | back up to previous extent
    BGE.B       XFSEARCH_CONT_3                 | still valid
    CLR.W       D1                              | reset to first extent
XFSEARCH_CONT_3:
    MOVEQ.L     #0x10,D0                        | FXRangeErr
    BRA.B       XFSEARCH_EXIT                   | exit
| RSExit
XFSEARCH_DONE:
    CLR.W       D0                              | noErr
XFSEARCH_EXIT:
    MOVE.L      (A7)+,D2                        | restore D2
    TST.W       D0                              | set condition codes
    RTS                                         | return from XRSearch
| ----------------------------------------------------------
|
| XFSEARCH_CONT_4 - XRUpdate: update the current extent record
|
XFSEARCH_CONT_4:
    MOVE.L      (A7)+,-(A6)                     | save return address
    MOVEM.L     D1/A0-A1,-(A6)                  | save registers
    MOVE.L      A0,D0                           | FCB resident record? (A0 = 0)
    BNE.B       XFSEARCH_NO_2                   | no, update extents file
    BSET        #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
    BRA.B       XFSEARCH_DONE_2                 | done
XFSEARCH_NO_2:
    MOVE.W      0xA4(A2),D0                     | extents file refnum (VCBXTRef)
    JSR         BTSEARCH(PC)                    | BTSearch: re-locate extent record
    BNE.B       XFSEARCH_ERR_2                  | error
    LEA.L       0xA(A4),A0                      | source = xdr in FXM vars
    MOVEQ.L     #0x2,D0                         | 3 longwords (12 bytes)
XFSEARCH_LOOP_3:
    MOVE.L      (A0)+,(A1)+                     | copy updated record to B-tree
    DBF.W       D0,XFSEARCH_LOOP_3              | loop for 3 longwords
    MOVE.W      0xA4(A2),D0                     | extents file refnum

    JSR         BTUPDATE(PC)                    | write updated xdr back to B-tree
    BNE.B       XFSEARCH_ERR_2                  | BTUpdate error ->
XFSEARCH_DONE_2:
    CLR.W       D0                              | result = noErr
XFSEARCH_ERR_2:
    MOVEM.L     (A6)+,D1/A0-A1                  | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from XRUpdate
