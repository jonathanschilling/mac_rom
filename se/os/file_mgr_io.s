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

| _GetFPos ($A018): get file position (just Seek with mode 0)
GETFPOS:
    CLR.B       0x2D(A0)                        | ioPosMode = fsAtMark (0)
| _SetFPos ($A044): set file position (Seek with count=0)
SETFPOS:
    CLR.L       0x24(A0)                        | ioReqCount = 0
| _Read ($A002): read bytes from file
FILEREAD:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_RFNCall                       | resolve ioRefNum to FCB
    BNE.W       L_MFILEREAD_EXIT_3              | error: exit
    BSR.B       SEEK                            | position within file
    BNE.B       L_MFILEREAD_EXIT_2              | error: update position + exit
| clamp read count to bytes remaining before EOF
    NEG.L       D2                              | D2 = bytes left before EOF
    BMI.B       L_MFILEREAD_CONT_2              | past EOF: eofErr
    CMP.L       D2,D7                           | request > remaining?
    BLE.B       L_MFILEREAD_CONT                | no: read full amount
    MOVE.L      D2,D7                           | clamp to remaining
L_MFILEREAD_CONT:
    TST.L       D7                              | anything to read?
    BEQ.B       L_MFILEREAD_DONE                | no: done
| check for no-cache and newline-mode flags
    MOVE.W      0x2C(A0),D2                     | ioVersNum + ioPosMode high byte
    LSR.W       #0x8,D2                         | shift to get newline-mode flag
    BCS.B       L_MFILEREAD_CONT_3              | newline mode: special path
| check if caller wants cache bypass
    BTST        #0x6,0x2D(A0)                   | no-cache bit in ioPosMode?
    BEQ.B       L_MFILEREAD_NO                  | no: normal read
| flush cache for this file first
    MOVEM.L     D1/A1,-(A6)                     | save regs
    MOVE.W      D1,D0                           | FCB index
    MOVEQ.L     #0x0,D1                         | no FlushCache options
    MOVEA.L     0x54(A2),A1                     | vcbCtlBuf (cache ptr)
    ST.B        (SysCRefCnt).W                  | set system cache flag
    JSR         FLUSHCACHE(PC)                  | flush cache
    MOVEM.L     (A6)+,D1/A1                     | restore regs
L_MFILEREAD_NO:
| check for partial block at current position
    MOVE.W      D5,D2                           | current position
    ANDI.W      #0x1FF,D2                       | offset within 512-byte block
    BEQ.B       RDMAIN                          | block-aligned: skip partial
| RdPart: must read a partial block first
| read partial block (position not block-aligned)
RDPART:
    BSR.W       L_MFILEREAD_CONT_5              | map logical to physical block
    BNE.B       L_MFILEREAD_EXIT                | error: exit
    BTST        #0x6,0x2D(A0)                   | no-cache mode?
    SNE.B       D0                              | D0 = $FF if no-cache
    BSR.W       DOPART                          | read/copy partial block
    BNE.B       L_MFILEREAD_EXIT                | error: exit
| main read loop: whole blocks then partial remainder
RDMAIN:
    MOVE.L      D7,D4                           | D4 = bytes remaining
    BEQ.B       L_MFILEREAD_DONE                | none: done
    ANDI.W      #0xFE00,D4                      | round down to whole blocks
    TST.L       D4                              | any whole blocks?
    BEQ.B       RDPART                          | no: read final partial
    JSR         CACHERDIP(PC)                   | CacheRdIP: read whole blocks
    BNE.B       L_MFILEREAD_EXIT                | error: exit
    BSR.W       FILEWRITE_CONT_2                | update position + counts
    BRA.B       RDMAIN                          | check for more
| read complete
L_MFILEREAD_DONE:
    MOVEQ.L     #0x0,D0                         | no error
L_MFILEREAD_EXIT:
    TST.W       D0                              | check error
    BNE.B       L_MFILEREAD_EXIT_2              | error: update pos + exit
| check if we read less than requested (short read = eofErr)
    MOVE.L      0x28(A0),D2                     | ioActCount
    CMP.L       0x24(A0),D2                     | == ioReqCount?
    BEQ.B       L_MFILEREAD_EXIT_2              | yes: exit normally
L_MFILEREAD_CONT_2:
    MOVEQ.L     #-0x27,D0                       | eofErr (-39): hit EOF
| update file position in FCB and param block
L_MFILEREAD_EXIT_2:
    MOVE.L      D5,0x10(A1,D1.W)                | FCBCrPs = current position
    MOVE.L      D5,0x2E(A0)                     | ioPosOffset = current position
L_MFILEREAD_EXIT_3:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_3
|
| FRNewLine: reading while looking for end of line characters
| FRNewLine: read byte-by-byte looking for EOL character
L_MFILEREAD_CONT_3:
    BSR.B       L_MFILEREAD_CONT_5              | RdFileBlk: read data block
    BNE.B       L_MFILEREAD_EXIT                | error: exit
    MOVE.L      D5,D2                           | current file position
    ANDI.W      #0x1FF,D2                       | index within block
    MOVEA.L     0x20(A0),A3                     | A3 = user buffer (ioBuffer)
    MOVE.L      0x28(A0),D4                     | D4 = ioActCount (dest offset)
| newline byte-by-byte scan loop
L_MFILEREAD_LOOP:
    MOVE.B      0x0(A5,D2.W),D0                 | get byte from cache block
    MOVE.B      D0,0x0(A3,D4.L)                 | copy to user buffer
    ADDQ.L      #0x1,0x28(A0)                   | increment ioActCount
    ADDQ.L      #0x1,D4                         | increment dest offset
    ADDQ.W      #0x1,D2                         | increment block offset
    ADDQ.L      #0x1,D5                         | increment file position
    CMP.B       0x2C(A0),D0                     | is it the EOL character?
    BNE.B       L_MFILEREAD_NO_2                | no: keep scanning
    MOVEQ.L     #0x0,D0                         | found EOL: no error
    BRA.B       L_MFILEREAD_EXIT_2              | update position + exit
L_MFILEREAD_NO_2:
    SUBQ.L      #0x1,D7                         | decrement byte count
    BEQ.B       L_MFILEREAD_DONE                | exhausted: check EOF
    CMP.W       D6,D2                           | reached end of block?
    BCS.B       L_MFILEREAD_LOOP                | no: keep scanning
    BRA.B       L_MFILEREAD_CONT_3              | get next block
| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_4
|
| Called during boot.
| L_MFILEREAD_CONT_4/PreRdFileBlk: read file block, but only if within current LEOF
L_MFILEREAD_CONT_4:
    BSR.B       L_MFILEREAD_CONT_6              | read the file block
    CMP.L       D3,D5                           | current pos < LEOF boundary? (D3=rounded LEOF)
    BCS.B       L_MFILEREAD_OK                  | yes, block has valid data ->
    MOVEQ.L     #0x4,D1                         | no, block is beyond LEOF: RBdirty option
    BRA.B       L_MFILEREAD_OK                  | ->
| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_5
|
| Called during boot.
| L_MFILEREAD_CONT_5/RdFileBlk: read a file block into volume cache
L_MFILEREAD_CONT_5:
    BSR.B       L_MFILEREAD_CONT_6              | map file pos and read block
    BTST        #0x6,0x2D(A0)                   | read verify mode? (IOPosMode bit 6)
    BEQ.B       L_MFILEREAD_OK                  | no ->
    MOVEQ.L     #0x1,D1                         | yes: force read (GBRead option)
L_MFILEREAD_OK:
    MOVEA.L     0x54(A2),A1                     | A1 = vcbBufAdr (volume cache)
    MOVE.L      D5,D2                           | D2 = file position
    LSR.L       #0x8,D2                         | D2 = position / 512
    LSR.L       #0x1,D2                         | (logical block number)
    RTS                                         | return block# in D2
| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_6
|
| Called during boot.
| Lg2Phys + GetBlock: map file position to physical block and read
L_MFILEREAD_CONT_6:
    MOVEM.L     D1-D2/A0-A1,-(A6)               | save regs
    MOVEA.L     (A7)+,A1                        | A1 = Lg2Phys return address
    MOVE.L      (A7)+,-(A6)                     | save caller's return address
    MOVE.W      D1,D0                           | D0 = FCB index
    MOVEQ.L     #0x0,D1                         | clear options
    MOVEQ.L     #0x2,D6                         | D6 = 512 (block size)
    LSL.L       #0x8,D6                         | D6 = 0x200
    JSR         (A1)                            | call Lg2Phys: map to physical
    ADDQ.B      #0x8,D1                         | add GBRead option
    JSR         GETBLOCK(PC)                    | GetBlock: read into cache
    MOVEA.L     A0,A5                           | A5 = cache block data ptr
    MOVE.L      (A6)+,-(A7)                     | restore caller's return
    MOVEM.L     (A6)+,D1-D2/A0-A1               | restore regs
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from L_MFILEREAD_CONT_6
| _Write ($A003): write bytes to file
FILEWRITE:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_TstMod                        | TstMod: check write permission
    BNE.B       FILEWRITE_NO_3                  | not writable: exit
    BSR.W       SEEK                            | Seek: position within file
    BNE.B       FILEWRITE_CONT                  | error: check + exit
| if positioned before EOF, advance to write position
    TST.L       D2                              | distance past EOF?
    BMI.B       FILEWRITE_NO                    | past EOF: skip advance
    ADD.L       D2,D5                           | advance to EOF position
| set up D3 = rounded LEOF for PreRdFileBlk boundary check
FILEWRITE_NO:
    MOVE.L      #0x1FF,D3                       | round up mask
    ADD.L       D4,D3                           | D3 = LEOF + 0x1FF
    ANDI.W      #0xFE00,D3                      | D3 = LEOF rounded to block
| check if write extends beyond physical EOF
    MOVE.L      D5,D4                           | current position
    ADD.L       D7,D4                           | + write count = end position
    CMP.L       0x8(A1,D1.W),D4                 | beyond FCBEOF?
    BLS.B       SAMELEN                         | no: same physical length
    SUB.L       0xC(A1,D1.W),D4                 | beyond FCBPLen?
    BLS.B       FILEWRITE_NO_2                  | no: just update LEOF
    BSR.W       AllocOrExtendFile               | allocate more space
FILEWRITE_CONT:
    BNE.B       FILEWRITE_EXIT                  | error: exit
| update logical length (FCBEOF)
FILEWRITE_NO_2:
    MOVE.L      D5,D4                           | current position
    ADD.L       D7,D4                           | + write count = new LEOF
    MOVE.L      D4,0x8(A1,D1.W)                 | update FCBEOF
| SameLen: data fits in physical allocation, start writing
SAMELEN:
    MOVE.W      D5,D0                           | current position
    ANDI.W      #0x1FF,D0                       | offset within block
    BEQ.B       WRMAIN                          | block-aligned: skip partial
| write partial block
WRPART:
    BSR.W       L_MFILEREAD_CONT_4              | PreRdFileBlk: read existing block
    BNE.B       FILEWRITE_PEOF_DONE             | error: exit
    MOVEQ.L     #0x1,D0                         | D0 = 1 (write mode)
    BSR.B       DOPART                          | DoPart: copy partial from user
    JSR         MARKA5BLOCK(PC)                 | mark block dirty
| main write loop
WRMAIN:
    MOVE.L      D7,D4                           | bytes remaining
    BEQ.B       FILEWRITE_DONE                  | none: done
    ANDI.W      #0xFE00,D4                      | round down to whole blocks
    TST.L       D4                              | any whole blocks?
    BEQ.B       WRPART                          | no: write final partial
    JSR         CACHEWRIP(PC)                   | CacheWrIP: write whole blocks
    BNE.B       FILEWRITE_PEOF_DONE             | error: exit
    BSR.B       FILEWRITE_CONT_2                | UpdteCntPos: update counts
    BRA.B       WRMAIN                          | check for more
| write complete
FILEWRITE_DONE:
    MOVEQ.L     #0x0,D0                         | no error
FILEWRITE_PEOF_DONE:
    BSR.W       P_AdjEof                        | AdjEOF: update catalog LEOF
    MOVE.L      D5,0x10(A1,D1.W)                | update FCBCrPs
FILEWRITE_EXIT:
    MOVE.L      0x10(A1,D1.W),0x2E(A0)          | ioPosOffset = FCBCrPs
FILEWRITE_NO_3:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| FILEWRITE_CONT_2 - UpdteCntPos: update byte count, actual count, and file position
|
| Called during boot.
FILEWRITE_CONT_2:
    SUB.L       D6,D7                           | adjust for number of bytes read/written
    ADD.L       D6,0x28(A0)                     | actually transferred this many more (IOActCount)
    ADD.L       D6,D5                           | update current position
    RTS                                         | return updated counts and position
| ----------------------------------------------------------
|
| DOPART
|
| Called during boot.
| DoPart: copy partial block to/from user buffer
| D0: 0=read, 1=write, $FF=verify-read
DOPART:
    MOVE.L      D5,D2                           | current file position
    ANDI.W      #0x1FF,D2                       | offset within block
    SUB.W       D2,D6                           | D6 = bytes remaining in block
    CMP.L       D6,D7                           | more requested than block has?
    BCC.B       FILEWRITE_OK                    | no: use remaining
    MOVE.L      D7,D6                           | clamp to request size
FILEWRITE_OK:
    MOVEA.L     0x20(A0),A3                     | A3 = ioBuffer (user buffer)
    ADDA.L      0x28(A0),A3                     | + ioActCount = current dest
    BSR.B       FILEWRITE_CONT_2                | UpdteCntPos: update counts
    MOVEM.L     D1/A0-A2,-(A7)                  | save regs
    MOVEA.L     A3,A0                           | A0 = user buffer position
    MOVEA.L     A5,A1                           | A1 = cache block data
    ADDA.W      D2,A1                           | + block offset
| dispatch by mode: D0>0=write, D0=0=read, D0<0=verify
    TST.B       D0                              | mode?
    BGT.B       FILEWRITE_OK_2                  | write: user->cache
    BMI.B       FILEWRITE_CONT_3                | verify: compare
    EXG         A0,A1                           | read: swap src/dest
FILEWRITE_OK_2:
    MOVE.L      D6,D0                           | byte count
    MOVEA.L     (0x4B8).W,A2                    | jBlockMove vector
    JSR         (A2)                            | call BlockMove
FILEWRITE_ERR_2:
    MOVEQ.L     #0x0,D0                         | noErr
FILEWRITE_EXIT_2:
    MOVEM.L     (A7)+,D1/A0-A2                  | restore regs
    RTS                                         | return from DoPart
| verify mode: compare bytes
FILEWRITE_CONT_3:
    MOVEQ.L     #-0x24,D0                       | assume ioErr (-36)
    SUBQ.W      #0x1,D6                         | loop count - 1 for DBNE
FILEWRITE_LOOP:
    CMPM.B      (A0)+,(A1)+                     | compare user byte with cache byte
    DBNE.W      D6,FILEWRITE_LOOP               | loop until mismatch or done
    BNE.B       FILEWRITE_EXIT_2                | mismatch: return ioErr
    BRA.B       FILEWRITE_ERR_2                 | all matched: return noErr
| ----------------------------------------------------------
|
| FILEWRITE_CONT_4
|
| Called during boot.
FILEWRITE_CONT_4:
    MOVE.W      0x18(A2),D0                     | vcbAllocPtr: next alloc search start
    MOVE.W      0x16(A2),D3                     | vcbVBMSt: VBM start block
    ADD.W       D3,D0                           | D0 = max directory block number
    MOVE.W      D0,(MaxDB).W                    | set max directory block
    BRA.B       FILEWRITE_NO_4                  | read the first directory block
| ----------------------------------------------------------
|
| FILEWRITE_NEXT
|
| Called during boot.
| FILEWRITE_NEXT: read next MFS directory block (advance CkdDB)
FILEWRITE_NEXT:
    MOVE.W      (CkdDB).W,D3                    | current directory block number
    ADDQ.W      #0x1,D3                         | advance to next block
    CMP.W       (MaxDB).W,D3                    | past end of directory?
    BCS.B       FILEWRITE_NO_4                  | no, read this block
    MOVEQ.L     #-0x21,D0                       | dirFulErr (-33)
    RTS                                         | return: directory exhausted
| ----------------------------------------------------------
|
| FILEWRITE_NO_4
|
| Called during boot.
| FILEWRITE_NO_4: read MFS directory block D3 into cache
FILEWRITE_NO_4:
    MOVE.W      D3,(CkdDB).W                    | update current directory block
    BSR.W       L_MFILEREAD_CONT_6              | Lg2Phys+GetBlock: read block into cache
    MOVEA.L     (SysCtlCPtr).W,A1               | A1 = system control cache
    BRA.B       FILEWRITE_CONT_7                | set up block params and return
| FILEWRITE_NEXT_2 -- read next block.
| ----------------------------------------------------------
|
| FILEWRITE_NEXT_2
|
FILEWRITE_NEXT_2:
    BSR.W       L_MFILEREAD_CONT_6              | read block D3 into cache
    BRA.B       FILEWRITE_CONT_6                | use volume cache
| ----------------------------------------------------------
|
| FILEWRITE_CONT_5
|
| FILEWRITE_CONT_5: read MFS directory block D3 into volume cache
FILEWRITE_CONT_5:
    BSR.W       L_MFILEREAD_CONT_6              | read block D3 into cache
    MOVEQ.L     #0x4,D1                         | RBdirty: release dirty
FILEWRITE_CONT_6:
    MOVEA.L     (SysVolCPtr).W,A1               | system volume cache
FILEWRITE_CONT_7:
    MOVEQ.L     #0x0,D2                         | clear high word
    MOVE.W      D3,D2                           | D2 = directory block number
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum: volume reference number
    RTS                                         | return cache params
FLUSHFILE:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    ST.B        (FlushOnly).W                   | indicate flush only (don't close)
    BRA.B       FILECLOSE_BEGIN                 | share code with FileClose
FILECLOSE:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    CLR.B       (FlushOnly).W                   | indicate close (not just flush)
FILECLOSE_BEGIN:
    BSR.W       P_RFNCall                       | RfNCall: valid open file?
    BEQ.B       FILECLOSE_CONT_2                | yes, proceed
    CMPI.W      #0xFFCB,D0                      | volOffLinErr (-53)?
    BNE.B       FILECLOSE_ERR                   | no, some other error
FILECLOSE_CONT_2:
    BSR.B       FILECLOSE_CONT_3                | FClose: do the actual flush/close
FILECLOSE_ERR:
    BRA.W       FSQUEUE_DONE                    | CmdDone
FILECLOSE_CONT_3:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D3/A0-A5,-(A6)               | save registers
    BSR.W       TFSVCBTST                       | TFS (HFS) volume?
    BNE.W       FILECLOSE_NO_3                  | no, MFS close path
    TST.L       0x22(A1,D1.W)                   | B-tree BTCB ptr? (FCBBTCBPtr)
    BEQ.B       FILECLOSE_NO                    | no B-tree open, skip
    CMPI.L      #0x10,0x0(A1,D1.W)              | system file? (FCBFlNm <= 16)
    BLS.B       FILECLOSE_NO                    | yes, skip B-tree close
    MOVE.W      D1,D0                           | file refnum for BT call
    TST.B       (FlushOnly).W                   | flush only?
    BNE.B       FILECLOSE_OK                    | yes, just flush B-tree
    JSR         BTCLOSE(PC)                     | BTClose: close the B-tree
    BRA.B       FILECLOSE_BT_FLUSH              | check result
FILECLOSE_OK:
    JSR         BTFLUSH(PC)                     | BTFlush: flush the B-tree
FILECLOSE_BT_FLUSH:
    BNE.W       FILECLOSE_ERR_4                 | B-tree error, exit FClose
FILECLOSE_NO:
    MOVEQ.L     #0x0,D0                         | assume noErr
    TST.W       0x48(A2)                        | volume online? (vcbDrvNum)
    BEQ.W       FILECLOSE_SKIP_2                | no (offline), skip flush
    CMPI.L      #0x10,0x0(A1,D1.W)              | system file? (FCBFlNm < 16)
    BCS.W       FILECLOSE_SKIP_2                | yes, skip (handled by vol flush)
    BCLR        #0x7,0x4(A1,D1.W)               | clear FCB dirty bit (FCBModBit)
    BEQ.W       FILECLOSE_DONE                  | was clean, skip flush
    BSR.W       TstMod_Impl                     | TstMod: can we modify?
    BNE.B       UPDTECNTPOS                     | no, skip truncate to catalog update
    MOVE.L      0xC(A1,D1.W),D3                 | D3 = current PEOF (FCBPLen)
    BTST        #0x6,0x4(A1,D1.W)               | own clump size? (FCBOwnClp bit)
    BEQ.B       FILECLOSE_TRUNCATE              | no, skip rounding
    MOVEM.L     D0-D1,-(A7)                     | save regs
    MOVE.L      D3,D0                           | D0 = PEOF for rounding
    MOVE.L      0x1E(A1,D1.W),D1                | clump size (FCBClmpSize)
    BSR.W       ROUNDALLOC                      | round up to next clump
    MOVE.L      0x1C(A2),D1                     | vcbAlBlkSiz: alloc block size
    MULU.W      D1,D0                           | compute new PEOF in bytes
    MOVE.L      D0,D3                           | D3 = rounded PEOF
    MOVEM.L     (A7)+,D0-D1                     | restore regs
FILECLOSE_TRUNCATE:
    MOVEQ.L     #0x0,D2                         | no options
    JSR         TRUNCATEFILE(PC)                | truncate to rounded PEOF
    BNE.W       FILECLOSE_ERR_3                 | error, exit to cache flush
    BCLR        #0x7,0x4(A1,D1.W)               | re-clear dirty bit after truncate
UPDTECNTPOS:
    MOVE.L      A1,-(A6)                        | save FCB array ptr on A6 stack
    MOVE.L      0x3A(A1,D1.W),D0                | parent DirID (FCBDirID)
    LEA.L       0x3E(A1,D1.W),A0                | ptr to CName (FCBCName)
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         CMGETCN(PC)                     | CMGetCN: locate catalog record
    MOVEA.L     A1,A5                           | A5 = catalog data record
    MOVEA.L     (A6)+,A1                        | restore FCB array ptr
    BNE.W       FILECLOSE_ERR_3                 | catalog error, exit to flush
    MOVEM.L     A0-A1,-(A7)                     | save regs
    LEA.L       0x26(A1,D1.W),A0                | source = FCB extent record (FCBExtRec)
    LEA.L       0x4A(A5),A3                     | dest = data fork extents (filExtRec)
    BTST        #0x9,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
    BEQ.B       FILECLOSE_NO_2                  | no, data fork
    LEA.L       0x56(A5),A3                     | dest = rsrc fork extents (filRExtRec)
FILECLOSE_NO_2:
    MOVEA.L     A3,A1                           | dest for BlockMove
    MOVEQ.L     #0xC,D0                         | 12 bytes (extent record length)
    _BlockMove                                  | copy extent record to catalog
    MOVEM.L     (A7)+,A0-A1                     | restore regs
    LEA.L       0x18(A5),A3                     | ptr to file lengths in catalog
    BSR.W       FILECLOSE_CONT_6                | UpdFlNtry: update file entry from FCB
    MOVE.L      (Time).W,0x30(A5)               | set modification date (filMdDat)
    JSR         CMUPDATECN(PC)                  | CMUpdateCN: update catalog record
    BNE.B       FILECLOSE_ERR_3                 | error, exit to flush
    BTST        #0x9,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
    BEQ.B       FILECLOSE_DONE                  | no, done
    CMPI.L      #0x80,0x8(A1,D1.W)              | LEOF >= 128 bytes? (FCBEOF)
    BCS.B       FILECLOSE_DONE                  | no, skip resource map update
    MOVEM.L     D1/A1,-(A6)                     | save regs on A6 stack
    MOVEA.L     A0,A3                           | A3 = catalog key record
    MOVEA.L     0x54(A2),A1                     | vcbBufAdr: volume cache
    MOVE.W      D1,D0                           | file refnum
    MOVEQ.L     #0x0,D1                         | no GetBlock options
    MOVEQ.L     #0x0,D2                         | block 0
    JSR         GETBLOCK(PC)                    | get resource fork block 0
    BNE.B       FILECLOSE_ERR_2                 | error, skip update
    MOVE.L      A0,-(A7)                        | save block ptr
    LEA.L       0x30(A0),A1                     | dest = block offset 0x30
    LEA.L       0x6(A3),A0                      | source = catalog key CName area
    MOVEQ.L     #0x20,D0                        | 32 bytes
    _BlockMove                                  | copy key info
    MOVEQ.L     #0x20,D0                        | 32 bytes just copied
    ADDA.L      D0,A1                           | advance dest by 32
    LEA.L       0x2(A5),A0                      | source = catalog record (past type)
    MOVEQ.L     #0x12,D0                        | 18 bytes
    _BlockMove                                  | copy file flags/dates
    MOVEQ.L     #0x12,D0                        | 18 bytes just copied
    ADDA.L      D0,A1                           | advance dest by 18
    LEA.L       0x38(A5),A0                     | source = extended Finder info
    MOVEQ.L     #0x10,D0                        | 16 bytes
    _BlockMove                                  | copy Finder info
    MOVEQ.L     #0x10,D0                        | 16 bytes just copied
    ADDA.L      D0,A1                           | advance dest by 16
    MOVE.L      0x2C(A5),(A1)+                  | copy filCrDat (creation date)
    MOVE.L      0x1A(A5),(A1)+                  | copy filLgLen (data fork length)
    MOVE.L      0x24(A5),(A1)+                  | copy filRLgLen (rsrc fork length)
    MOVEA.L     (A7)+,A0                        | restore block ptr
    MOVEA.L     0x54(A2),A1                     | vcbBufAdr: volume cache
    MOVEQ.L     #0x4,D1                         | RBdirty: release dirty
    JSR         RELBLOCK(PC)                    | release cache block
FILECLOSE_ERR_2:
    MOVEM.L     (A6)+,D1/A1                     | restore regs from rsrc fork update
| Called by: FILECLOSE_NO_2, FILECLOSE_NO, FILECLOSE_NO_3, FILECLOSE_OK_4
FILECLOSE_DONE:
    MOVEQ.L     #0x0,D0                         | noErr
| Called by: FILECLOSE_TRUNCATE, UPDTECNTPOS, FILECLOSE_NO_2, FILECLOSE_NO_3, FILECLOSE_MFS_DIR_LOOP
FILECLOSE_ERR_3:
    MOVEM.L     D0-D1/A1,-(A6)                  | save error code and regs
    MOVE.W      D1,D0                           | file refnum for FlushCache
    MOVEQ.L     #0x0,D1                         | no FlushCache options
    TST.B       (FlushOnly).W                   | flush only?
    BNE.B       FILECLOSE_OK_2                  | yes, no trash
    MOVEQ.L     #0x1,D1                         | FCtrash: trash cache after flush
FILECLOSE_OK_2:
    MOVEA.L     0x54(A2),A1                     | vcbBufAdr: volume cache
    JSR         FLUSHCACHE(PC)                  | flush volume cache for this file
    BSR.W       TFSVCBTST                       | TFS (HFS) volume?
    BEQ.B       FILECLOSE_OK_3                  | yes, skip MFS directory flush
    BSR.W       CREATE_CONT_7                   | MFS: flush MFS directory
FILECLOSE_OK_3:
    MOVEM.L     (A6)+,D0-D1/A1                  | restore error code and regs
| if closing (not just flushing), clear the FCB
FILECLOSE_SKIP_2:
    TST.B       (FlushOnly).W                   | flush only?
    BNE.B       FILECLOSE_ERR_4                 | yes, keep FCB intact
    LEA.L       0x0(A1,D1.W),A3                 | point to FCB entry
    MOVEQ.L     #0x2E,D2                        | (94 / 2) - 1 = 46 words
FILECLOSE_LOOP:
    CLR.W       (A3)+                           | clear the FCB
    DBF.W       D2,FILECLOSE_LOOP               | until all 94 bytes cleared
FILECLOSE_ERR_4:
    MOVEM.L     (A6)+,D1-D3/A0-A5               | restore registers
    MOVE.L      (A6)+,-(A7)                     | restore return address from A6 stack
    TST.W       D0                              | set condition codes
    RTS                                         | exit FClose
FILECLOSE_NO_3:
    BCLR        #0x7,0x4(A1,D1.W)               | clear FCB dirty bit (FCBModBit)
    BEQ.B       FILECLOSE_DONE                  | was clean, skip flush
    MOVE.W      0x1C(A1,D1.W),D3                | directory block hint (FCBFlPos)
    BSR.W       FILEWRITE_NO_4                  | read directory block into cache
    BNE.B       FILECLOSE_ERR_3                 | error
    MOVEQ.L     #0x0,D0                         | initial entry offset
    MOVE.L      0x0(A1,D1.W),D3                 | file number (FCBFlNm)
FILECLOSE_MFS_DIR_LOOP:
    CMP.L       0x12(A5,D0.W),D3                | match file number in dir entry?
    BEQ.B       FILECLOSE_OK_4                  | yes, found it
    BSR.W       CREATE_NEXT                     | advance to next MFS dir entry
    BCS.B       FILECLOSE_MFS_DIR_LOOP          | keep scanning
    MOVEQ.L     #-0x2B,D0                       | fnfErr (-43): file not in directory
    BRA.B       FILECLOSE_ERR_3                 | error exit
FILECLOSE_OK_4:
    LEA.L       0x16(A5,D0.W),A3                | ptr to fork lengths in MFS entry
    BSR.B       FILECLOSE_CONT_6                | UpdFlNtry: copy FCB lengths to entry
    MOVE.L      (Time).W,0x2E(A5,D0.W)          | set modification date
    JSR         MARKA5BLOCK(PC)                 | mark directory block dirty
    BRA.B       FILECLOSE_DONE                  | done, exit to cache flush
| ----------------------------------------------------------
|
| FILECLOSE_CONT_6
|
| Called during boot.
| FILECLOSE_CONT_6/UpdFlNtry: update file lengths in catalog from FCB
| A3 = ptr to file length fields in catalog, (A1,D1) = FCB
FILECLOSE_CONT_6:
    MOVE.L      A4,-(A7)                        | save A4
    LEA.L       0x4(A1,D1.W),A4                 | A4 = FCB flags (FCBMdRByt)
    MOVE.W      (A4)+,D3                        | get flags word, advance past it
    LSL.W       #0x7,D3                         | resource fork bit into carry
    BCC.B       FILECLOSE_CONT_7                | data fork, no skip needed
    ADDA.W      #0xA,A3                         | skip data fork fields (10 bytes)
FILECLOSE_CONT_7:
    MOVE.W      (A4)+,(A3)+                     | copy start block (FCBStBlk)
    MOVE.L      (A4)+,(A3)+                     | copy LEOF (FCBEOF)
    MOVE.L      (A4)+,(A3)+                     | copy PEOF (FCBPLen)
    MOVEA.L     (A7)+,A4                        | restore A4
    RTS                                         | return from UpdFlNtry
GETEOF:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.B       P_RFNCall                       | RfNCall: valid open file?
    BNE.B       GETFCBINFO_HFS_ERR              | error, skip
    MOVE.L      0x8(A1,D1.W),0x1C(A0)           | return LEOF (FCBEOF -> ioMisc)
GETFCBINFO_HFS_ERR:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| P_RFN Call
|
| Called during boot.
P_RFNCall:
    MOVE.L      (0x790).W,-(A7)                 | push RfNCall vector address
    RTS                                         | jump to HFS vector
VRFNCALL:
    MOVEA.L     (FCBSPtr).W,A1                  | A1 = FCB array base
    MOVEQ.L     #0x0,D1                         | clear high word
    MOVE.W      0x18(A0),D1                     | D1 = ioRefNum from param block
    BSR.B       CKFILERFN                       | validate refnum
    BNE.B       RFNCALL_CONT                    | invalid, return error
    MOVE.L      0x0(A1,D1.W),D2                 | D2 = file number (FCBFlNm)
    MOVEA.L     0x14(A1,D1.W),A2                | A2 = VCB ptr (FCBVPtr)
    MOVE.L      A2,(ReqstVol).W                 | set requested volume
    BSR.W       CkExtFS_AndOnline               | find/verify volume
RFNCALL_CONT:
    TST.W       D0                              | set condition codes
    RTS                                         | return from RfNCall
| ----------------------------------------------------------
|
| CKFILERFN
|
| Called during boot.
| CkFileRfn: check that refnum points to a valid open file
CKFILERFN:
    MOVEQ.L     #-0x33,D0                       | assume rfNumErr (-51)
    MOVEQ.L     #0x0,D2                         | clear high word for divide
    MOVE.W      D1,D2                           | D2 = refnum
    DIVU.W      #0x5E,D2                        | divide by 94 (FCB entry size)
    SWAP.W      D2                              | D2.W = remainder
    SUBQ.W      #0x2,D2                         | must be 2 (first FCB at offset 2)
    BNE.B       CkFileRfn_RTS                   | bad alignment, not a valid FCB
    CMP.W       (A1),D1                         | refnum >= FCB array length?
    BCC.B       CkFileRfn_RTS                   | yes, out of range
    MOVEQ.L     #-0x26,D0                       | assume fnOpnErr (-38)
    TST.L       0x0(A1,D1.W)                    | FCBFlNm = 0? (file not open)
    BEQ.B       CkFileRfn_RTS                   | not open, return error
    MOVEQ.L     #0x0,D0                         | valid: noErr
CkFileRfn_RTS:
    TST.W       D0                              | set condition codes
    RTS                                         | return from CkFileRfn
P_TstMod:
    MOVE.L      (0x7C4).W,-(A7)                 | push TstMod vector address
    RTS                                         | jump to HFS vector
VTSTMOD:
    BSR.B       P_RFNCall                       | validate refnum first
    BNE.B       TstMod_VOL_CHECK                | invalid refnum, return error
TstMod_Impl:
    MOVEQ.L     #-0x3D,D0                       | assume wrPermErr (-61)
    BTST        #0x0,0x4(A1,D1.W)               | write permission? (FCBMdRByt bit 0)
    BEQ.B       TstMod_VOL_CHECK                | no, return wrPermErr
    BSR.W       SETVOLINFO_HFS_CONT_3           | check volume write protection
TstMod_VOL_CHECK:
    TST.W       D0                              | set condition codes
    RTS                                         | return from TstMod
GETFCBINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.B       FNDFCB                          | FndFCB: find FCB by refnum or index
    BNE.B       SETFCBINFO_DONE                 | error
    MOVE.W      D1,0x18(A0)                     | return actual refnum (ioRefNum)
    LEA.L       0x0(A1,D1.W),A3                 | A3 = FCB entry
    MOVE.L      A0,-(A7)                        | save param block
    LEA.L       0x20(A0),A1                     | dest = ioFCBFlNm in param block
    MOVEA.L     A3,A0                           | source = FCB
    MOVEQ.L     #0x14,D0                        | 20 bytes (FCBFlNm through FCBVPtr)
    _BlockMove                                  | copy FCB fields to param block
    MOVEA.L     (A7)+,A0                        | restore param block
    MOVE.W      0x4E(A2),0x34(A0)               | ioFCBVRefNum = vcbVRefNum
    MOVE.L      0x1E(A3),0x36(A0)               | ioFCBClpSiz = clump size (FCBClmpSize)
    MOVE.L      0x3A(A3),0x3A(A0)               | ioFCBParID = parent DirID (FCBDirID)
    MOVE.L      0x12(A0),D0                     | ioFileName buffer pointer
    BEQ.B       GETFCBINFO_HFS_NO               | no buffer, skip name copy
    MOVEA.L     D0,A1                           | A1 = dest buffer
    MOVE.L      A0,-(A7)                        | save param block
    LEA.L       0x3E(A3),A0                     | source = FCBCName (Pascal string)
    MOVEQ.L     #0x1,D0                         | include length byte
    ADD.B       (A0),D0                         | + name length
    _BlockMove                                  | copy file name to caller's buffer
    MOVEA.L     (A7)+,A0                        | restore param block
GETFCBINFO_HFS_NO:
    MOVE.L      A2,(ReqstVol).W                 | set requested volume
    MOVE.L      A3,D1                           | D1 = FCB pointer
    BSR.W       P_CKExtFS                       | check external file system
SETFCBINFO_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| FNDFCB
|
| FndFCB: find an FCB by refnum or by index (for GetFCBInfo)
FNDFCB:
    MOVEA.L     (FCBSPtr).W,A1                  | A1 = FCB array base
    MOVE.W      0x18(A0),D1                     | requested refnum (ioRefNum)
    MOVE.W      0x1C(A0),D0                     | ioFCBIndx (0 = use refnum)
    BEQ.B       FNDFCB_NOT_FOUND_ERR            | index=0: use refnum directly
    MOVEQ.L     #0x0,D2                         | VCB filter (0 = any volume)
    MOVE.W      0x16(A0),D2                     | ioVRefNum: filter by volume?
    BEQ.B       GETFCBINFO_INDEXED_BEGIN        | no VRefNum, scan all
    MOVE.W      D2,D0                           | determine volume from VRefNum
    BSR.W       P_DTRMV1                        | DTRMV1: resolve volume
    BNE.B       FNDFCB_RTS_WITH_VCB             | error
    MOVE.L      A2,D2                           | D2 = VCB pointer filter
    MOVE.W      0x1C(A0),D0                     | restore index
GETFCBINFO_INDEXED_BEGIN:
    BSR.W       HFSE_CONT_14                    | Gt1stFCB: position to first FCB
GETFCBINFO_HFS_CONT:
    MOVE.L      0x0(A1,D1.W),D3                 | file number (FCBFlNm)
    BEQ.B       GETFCBINFO_NEXT_FCB             | FCB empty, skip
    MOVEA.L     0x14(A1,D1.W),A2                | VCB pointer (FCBVPtr)
    BSR.W       TFSVCBTST                       | TFS (HFS) volume?
    BNE.B       GETFCBINFO_HFS_OK               | MFS file ok, check volume filter
    CMPI.L      #0x10,D3                        | system file? (CNID < 16)
    BCS.B       GETFCBINFO_NEXT_FCB             | yes, skip system files
GETFCBINFO_HFS_OK:
    TST.L       D2                              | volume filter active?
    BEQ.B       GETFCBINFO_HFS_NO_3             | no, accept this FCB
    CMP.L       0x14(A1,D1.W),D2                | same volume? (FCBVPtr)
    BNE.B       GETFCBINFO_NEXT_FCB             | no, skip
GETFCBINFO_HFS_NO_3:
    SUBQ.W      #0x1,D0                         | decrement index
    BEQ.B       FNDFCB_NOT_FOUND_ERR            | found the Nth one
GETFCBINFO_NEXT_FCB:
    BSR.W       HFSE_NEXT                       | GtNxtFCB: advance to next FCB
    BCS.B       GETFCBINFO_HFS_CONT             | more FCBs, keep scanning
    MOVEQ.L     #-0x26,D0                       | fnOpnErr (-38): no matching FCB
    BRA.B       FNDFCB_RTS_WITH_VCB             | return error
FNDFCB_NOT_FOUND_ERR:
    BSR.W       CKFILERFN                       | validate the refnum
    MOVEA.L     0x14(A1,D1.W),A2                | A2 = VCB ptr (FCBVPtr)
FNDFCB_RTS_WITH_VCB:
    TST.W       D0                              | set condition codes
    RTS                                         | return from FndFCB
P_hfsUn_LockRange:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_RFNCall                       | RfNCall: validate refnum
    BNE.B       SETFLOCK_RTS                    | error
    MOVEQ.L     #0x0,D0                         | noErr (locking not implemented)
SETFLOCK_RTS:
    BRA.W       FSQUEUE_DONE                    | CmdDone
AllocFile_OrAllocContig:
    MOVEQ.L     #0x0,D0                         | assume noErr
    BSR.W       TFSVCBTST                       | TFS (HFS) volume?
    BNE.W       LG2PHYS_CONT_2                  | MFS: return noErr
    BSR.W       TFSBitTst                       | TFSBitTst: check HFS alloc flag
    BEQ.B       ALLOCFILE_DEFAULT               | flag clear, use default
    MOVEQ.L     #0x2,D0                         | flag set, D0 = 2 (contiguous)
ALLOCFILE_DEFAULT:
    BRA.W       ALLOCEXTEND_HFS_BEGIN           | continue to ExtendFile
FILEALLOC:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_TstMod                        | TstMod: can we modify?
    BNE.B       ALLOCFILE_DONE                  | no, error
    MOVEQ.L     #0x0,D6                         | D6 = 0 (bytes allocated so far)
    MOVE.L      0x24(A0),D4                     | requested bytes (ioReqCount)
    BEQ.B       ALLOCATE_EMPTY                  | zero request, skip
    TST.W       0x2A(A2)                        | any free blocks? (vcbFreeBks)
    BEQ.B       ALLOCATE_EMPTY                  | no, disk full
    BSR.B       AllocFile_OrAllocContig         | FileAlloc: allocate the space
    BNE.B       ALLOCFILE_DONE                  | error
ALLOCATE_EMPTY:
    MOVE.L      D6,0x28(A0)                     | return bytes allocated (ioActCount)
    BSR.B       P_AdjEof                        | AdjEOF: adjust other FCBs
    MOVEQ.L     #-0x22,D0                       | assume dskFulErr (-34)
    CMP.L       0x24(A0),D6                     | allocated >= requested?
    BCS.B       ALLOCFILE_DONE                  | no, disk full
    MOVEQ.L     #0x0,D0                         | noErr
ALLOCFILE_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
SETEOF:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_TstMod                        | TstMod: can we modify?
    BNE.B       SETEOF_DONE                     | no, error
    MOVE.L      0x1C(A0),D7                     | requested LEOF (ioMisc/ioLEOF)
    MOVE.L      D7,D4                           | copy to D4
    SUB.L       0xC(A1,D1.W),D4                 | compare with current PEOF (FCBPLen)
    BHI.B       SETEOF_CONT_3                   | longer: allocate more space
    BCS.B       AdjEOF_Impl                     | shorter: deallocate space
SETEOF_SHRINK:
    BSR.W       TFSBitTst                       | TFSBitTst: HFS bit set?
    BEQ.B       SETEOF_NO                       | no, adjust LEOF as requested
    CMP.L       0x8(A1,D1.W),D7                 | new PEOF < current LEOF? (FCBEOF)
    BCC.B       SETEOF_PIN_POSITION             | no, LEOF still valid
SETEOF_NO:
    MOVE.L      D7,0x8(A1,D1.W)                 | set new LEOF (FCBEOF)
    CMP.L       0x10(A1,D1.W),D7                | current position past new LEOF? (FCBCrPs)
    BCC.B       SETEOF_PIN_POSITION             | no, position still valid
    MOVE.L      D7,0x10(A1,D1.W)                | pin position to new LEOF (FCBCrPs)
SETEOF_PIN_POSITION:
    BSR.B       P_AdjEof                        | AdjEOF: adjust other FCBs
    MOVEQ.L     #0x0,D0                         | noErr
SETEOF_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
AdjEOF_Impl:
    BSR.W       GETFILEINFO_OK_15               | TFSVolTst: is it TFS?
    BNE.B       ADJEOF_NO                       | no, MFS handles it
    MOVE.L      D7,D4                           | recover requested LEOF
    MOVE.L      D4,D3                           | new truncation length
    MOVEQ.L     #0x1,D2                         | round to extent boundary
    JSR         TRUNCATEFILE(PC)                | truncate PEOF to LEOF
    BNE.B       SETEOF_DONE                     | error, exit
SETEOF_CONT_2:
    MOVEM.L     D0-D2,-(A6)                     | save regs
    MOVE.W      D1,D0                           | file refnum
    MOVE.L      0xC(A1,D1.W),D1                 | new PEOF (FCBPLen)
    MOVEQ.L     #-0x1,D2                        | trash to end of file
    JSR         TRASHBLOCKS(PC)                 | trash cached blocks beyond new length
    MOVEM.L     (A6)+,D0-D2                     | restore regs
    BRA.B       SETEOF_SHRINK                   | go adjust LEOF
SETEOF_CONT_3:
    JSR         AllocOrExtendFile(PC)           | Alloc: allocate more space
    BNE.B       SETEOF_DONE                     | error, exit
    BRA.B       SETEOF_SHRINK                   | go adjust LEOF
| ----------------------------------------------------------
|
| P_Adj Eof
|
| Called during boot.
P_AdjEof:
    MOVE.L      (0x794).W,-(A7)                 | push AdjEof vector address
    RTS                                         | jump to HFS vector
VADJEOF:
    MOVEM.L     D0-D6/A0-A5,-(A7)               | save all regs
    ADDA.W      D1,A1                           | point to this FCB
    MOVE.L      (A1)+,D2                        | D2 = file number (FCBFlNm)
    BSET        #0x7,(A1)                       | mark FCB dirty (FCBModBit)
    MOVE.W      (A1),D0                         | D0 = FCB flags
    MOVEM.L     (A1)+,D3-D6/A2                  | extract flags/StBlk/LEOF/PEOF/VPtr
    MOVE.W      D0,D6                           | D6 = FCB flags (for fork type check)
    LEA.L       0xE(A1),A1                      | skip past FCBVPtr area
    MOVEM.L     (A1)+,A3-A5                     | extract remaining FCB fields
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find first FCB with same file #
    BNE.B       ADJEOF_FOUND_2                  | no matches
ADJEOF_FOUND:
    LEA.L       0x4(A1,D1.W),A0                 | point to this FCB's flags
    MOVE.W      (A0)+,D0                        | get this FCB's flags
    EOR.W       D6,D0                           | compare fork type
    LSL.W       #0x7,D0                         | resource fork bit into carry
    BCS.B       ADJEOF_SKIP                     | different fork, skip update
    MOVE.W      D3,(A0)+                        | update StBlk
    MOVE.L      D4,(A0)+                        | update LEOF
    MOVE.L      D5,(A0)+                        | update PEOF
    LEA.L       0x22(A0),A0                     | skip to end of FCB
    MOVEM.L     A3-A5,-(A0)                     | update remaining fields
ADJEOF_SKIP:
    BSR.W       HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
    BEQ.B       ADJEOF_FOUND                    | found one, loop
ADJEOF_FOUND_2:
    MOVEM.L     (A7)+,D0-D6/A0-A5               | restore regs
    RTS                                         | exit AdjEOF
| ----------------------------------------------------------
|
| ADJEOF_NO
|
| Called during boot.
ADJEOF_NO:
    MOVEQ.L     #0x0,D6                         | accumulated PEOF = 0
    MOVE.W      0x6(A1,D1.W),D3                 | start alloc block (FCBStBlk)
    MOVE.L      0x1C(A2),D2                     | vcbAlBlkSiz: alloc block size
    MOVE.L      D7,D4                           | D4 = new LEOF
    BNE.B       ADJEOF_CONT_2                   | nonzero, walk chain
    CLR.W       0x6(A1,D1.W)                    | LEOF=0: clear start block (FCBStBlk)
    BRA.B       ALLOC_FREE_REMAINING            | free entire chain
ADJEOF_CONT:
    MOVE.W      D5,D3                           | D3 = next alloc block in chain
ADJEOF_CONT_2:
    ADD.L       D2,D6                           | accumulate PEOF
    BSR.W       LG2PHYS_NEXT_2                  | get next block in alloc chain
    SUB.L       D2,D4                           | subtract alloc block size
    BHI.B       ADJEOF_CONT                     | more to walk
    CMP.L       0xC(A1,D1.W),D6                 | new PEOF >= current PEOF? (FCBPLen)
    BCC.W       SETEOF_SHRINK                   | yes, nothing to truncate
    MOVE.W      D5,-(A7)                        | save next block (first to free)
    MOVEQ.L     #0x1,D5                         | end-of-chain marker
    BSR.W       LG2PHYS_CONT_9                  | write end-of-chain to alloc map
    MOVE.W      (A7)+,D3                        | D3 = first block to free
ALLOC_FREE_REMAINING:
    BSR.W       LG2PHYS_CONT_10                 | MFSDealloc: free remaining chain
    MOVE.L      D6,0xC(A1,D1.W)                 | update PEOF (FCBPLen)
    MOVE.L      D6,D4                           | D4 = new PEOF
    BRA.W       SETEOF_CONT_2                   | go trash blocks and adjust LEOF
AllocOrExtendFile:
    BSR.W       GETFILEINFO_OK_15               | TFSVolTst: is it TFS?
    BNE.W       LG2PHYS_NO_3                    | no, MFS Alloc path
    MOVEQ.L     #0x1,D0                         | HFS: use ExtendFile
ALLOCEXTEND_HFS_BEGIN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVE.L      D3,-(A6)                        | save D3
    MOVE.W      D0,D3                           | D3 = alloc mode flag
    JSR         EXTENDFILE(PC)                  | ExtendFile: allocate disk space
    MOVE.L      (A6)+,D3                        | restore D3 from A6 stack
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set condition codes
    RTS                                         | return from Alloc
LG2PHYS:
    MOVE.L      (0x6FC).W,-(A7)                 | push Lg2Phys vector address
    RTS                                         | jump to HFS vector
VLG2PHYS:
    BSR.W       GETFILEINFO_OK_15               | TFSVolTst: is it TFS?
    BNE.B       LG2PHYS_NO                      | no, MFS Lg2Phys
    JMP         MAPFBLOCK(PC)                   | HFS: MapFBlock
| ----------------------------------------------------------
|
| LG2PHYS_NO - MFS Lg2Phys: simple linear extent mapping
|
| Called during boot.
LG2PHYS_NO:
    MOVEM.L     D1-D2/D4-D5/D7,-(A7)            | save registers
    MOVE.L      0x1C(A2),D7                     | D7 = alloc block size (vcbAlBlkSiz)
    MOVE.W      0x6(A1,D1.W),D3                 | D3 = start alloc block (FCBStBlk)
    ADD.L       D5,D4                           | D4 = end position (pos + max bytes)
    SUBQ.L      #0x1,D4                         | adjust to last byte in range
    MOVEQ.L     #0x9,D1                         | shift count for /512
    MOVEQ.L     #0x0,D6                         | D6 = blocks mapped so far
    LSR.L       D1,D4                           | end block (in 512-byte units)
    LSR.L       D1,D7                           | alloc blk size in 512-byte blocks
    MOVE.L      D5,D2                           | D2 = start byte offset
    LSR.L       D1,D2                           | convert to 512-byte blocks
    BRA.B       LG2PHYS_CONT                    | enter chain walk
| ----------------------------------------------------------
|
| LG2PHYS_NEXT
|
| Called during boot (3,127 times in 30s trace).
| walk MFS extent chain
LG2PHYS_NEXT:
    BSR.B       LG2PHYS_NEXT_2                  | get next block in alloc chain
    MOVE.W      D5,D3                           | D3 = next alloc block
    SUB.W       D7,D4                           | adjust end for this extent
    SUB.W       D7,D2                           | adjust start for this extent
LG2PHYS_CONT:
    CMP.W       D7,D2                           | start within this extent?
    BCC.B       LG2PHYS_NEXT                    | no, try next extent
    MOVE.W      D3,D0                           | alloc block number
    SUBQ.W      #0x2,D0                         | -2 (alloc blocks start at 2)
    MULU.W      D7,D0                           | * alloc blk size (512-byte blocks)
    ADD.W       D2,D0                           | + offset within alloc block
    ADD.W       0x24(A2),D0                     | + vcbAlBlSt (volume alloc start)
    MOVE.L      D0,-(A7)                        | save disk block number
| count contiguous blocks from this extent
LG2PHYS_OK:
    MOVE.W      D7,D0                           | blocks in this extent
    SUB.W       D2,D0                           | - offset into extent
    ADD.W       D0,D6                           | add to contiguous block count
    SUB.W       D0,D4                           | subtract from remaining request
    BMI.B       LG2PHYS_DONE                    | done if all blocks covered
    BSR.B       LG2PHYS_NEXT_2                  | get next extent
    MOVEQ.L     #0x0,D2                         | start at beginning of next
    ADDQ.W      #0x1,D3                         | check if next is contiguous
    CMP.W       D3,D5                           | next alloc block == expected?
    BEQ.B       LG2PHYS_OK                      | yes, keep counting contiguous
| validate result and convert to byte count
LG2PHYS_DONE:
    MOVE.L      (A7)+,D3                        | restore disk block number
    MOVE.W      D3,D0                           | ending block = start + count
    ADD.W       D6,D0                           | D0 = start block + block count
    MOVE.W      0x24(A2),D4                     | vcbAlBlSt: volume alloc start
    MULU.W      0x1A(A2),D7                     | vcbNmAlBlks * blk size = total disk blks
    ADD.W       D4,D7                           | + alloc start = end of volume
    CMP.W       D7,D0                           | past end of volume?
    BHI.B       LG2PHYS_ERR                     | yes, mapping error
    CMP.W       D4,D3                           | before alloc start?
    BCS.B       LG2PHYS_ERR                     | yes, mapping error
    ASL.L       D1,D6                           | convert block count to bytes (*512)
    MOVEM.L     (A7)+,D1-D2/D4-D5/D7            | restore registers
    CMP.L       D4,D6                           | more than requested?
    BLS.B       LG2PHYS_NO_2                    | no, use actual count
    MOVE.L      D4,D6                           | limit to requested amount
LG2PHYS_NO_2:
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from Lg2Phys
LG2PHYS_ERR:
    MOVEM.L     (A7)+,D1-D2/D4-D5/D7            | restore registers
    MOVE.W      #0x10,D0                        | mapping error
    RTS                                         | return from Lg2Phys with error
| ----------------------------------------------------------
|
| LG2PHYS_NEXT_2
|
| Called during boot (3,700 times in 30s trace).
| LG2PHYS_NEXT_2: MFS alloc map lookup - get next alloc block from 12-bit map
| D3 = current alloc block, returns D5 = next alloc block
LG2PHYS_NEXT_2:
    MOVEM.L     D0/A2,-(A7)                     | save regs
    MOVEA.L     0x50(A2),A2                     | A2 = alloc map base (vcbMAdr)
    MOVE.W      D3,D0                           | alloc block number
    SUBQ.W      #0x2,D0                         | -2 (map starts at block 2)
    MULU.W      #0xC,D0                         | * 12 bits per entry
    ROR.L       #0x4,D0                         | convert bit offset to byte.nibble
    ASL.W       #0x1,D0                         | byte offset (word-aligned)
    MOVE.L      0x0(A2,D0.W),D5                 | get longword containing 12-bit entry
    CLR.W       D0                              | isolate nibble offset
    ROL.L       #0x4,D0                         | shift nibble index to low bits
    ADDI.W      #0xC,D0                         | + 12 bits
    ROL.L       D0,D5                           | rotate entry to low 12 bits
    ANDI.W      #0xFFF,D5                       | mask to 12 bits
    MOVEM.L     (A7)+,D0/A2                     | restore regs
    RTS                                         | return D5 = next alloc block
| ----------------------------------------------------------
|
| LG2PHYS_NO_3 - MFS Alloc: allocate space for file (Alloc entry for MFS)
|
LG2PHYS_NO_3:
    MOVE.L      D4,D0                           | D0 = max bytes to allocate
LG2PHYS_CONT_2:
    MOVEM.L     D1-D5/D7/A0-A3,-(A7)            | save regs
    MOVE.L      0x1C(A2),D7                     | vcbAlBlkSiz: alloc block size
    MOVE.L      D7,D6                           | compute free space in bytes
    MULU.W      0x2A(A2),D6                     | = alloc blk size * vcbFreeBks
    CMP.L       D6,D4                           | request > free space?
    BLS.B       LG2PHYS_NO_4                    | no, use full request
    MOVE.L      D6,D4                           | limit to available space
LG2PHYS_NO_4:
    CMP.L       D0,D4                           | enough space for minimum?
    BCC.B       LG2PHYS_OK_2                    | yes, proceed
    MOVEQ.L     #-0x22,D0                       | dskFulErr (-34)
LG2PHYS_EXIT:
    MOVEM.L     (A7)+,D1-D5/D7/A0-A3            | restore regs
    RTS                                         | return from MFS Alloc
| MFS Alloc: extend file by allocating blocks from alloc map
LG2PHYS_OK_2:
    MOVE.L      0xC(A1,D1.W),D2                 | D2 = current PEOF (FCBPLen)
    MOVEQ.L     #0x0,D6                         | D6 = bytes allocated so far
    MOVE.W      0x6(A1,D1.W),D3                 | D3 = start alloc block (FCBStBlk)
    BNE.B       LG2PHYS_CONT_3                  | have blocks already, walk to end
    BSR.B       LG2PHYS_NEXT_3                  | first alloc: find a free block
    MOVE.W      D5,0x6(A1,D1.W)                 | set start block (FCBStBlk)
    MOVE.W      D5,D3                           | D3 = new start block
    MOVEQ.L     #0x1,D5                         | mark as end-of-chain
    BSR.W       LG2PHYS_CONT_9                  | write end-of-chain to alloc map
    BRA.B       LG2PHYS_CONT_5                  | update counts
| ----------------------------------------------------------
|
| LG2PHYS_ERR_2
|
LG2PHYS_ERR_2:
    MOVE.W      D5,D3                           | D3 = next alloc block in chain
LG2PHYS_CONT_3:
    BSR.B       LG2PHYS_NEXT_2                  | get next entry in chain
    CMPI.W      #0x1,D5                         | end-of-chain marker?
    BNE.B       LG2PHYS_ERR_2                   | no, keep walking to end
LG2PHYS_NO_5:
    CMP.W       0x1A(A2),D3                     | past end of alloc map? (vcbNmAlBlks)
    BHI.B       LG2PHYS_OK_3                    | yes, find free block elsewhere
    ADDQ.W      #0x1,D3                         | peek at next sequential block
    BSR.B       LG2PHYS_NEXT_2                  | check if next block is free
    SUBQ.W      #0x1,D3                         | restore current block number
    TST.W       D5                              | next block free? (entry = 0)
    BNE.B       LG2PHYS_OK_3                    | no, find free block elsewhere
    MOVE.W      D3,D5                           | new block = current + 1
    ADDQ.W      #0x1,D5                         | D5 = next sequential block
LG2PHYS_CONT_4:
    BSR.W       LG2PHYS_CONT_9                  | link current -> new block in map
    MOVE.W      D5,D3                           | D3 = new block (now current)
    MOVEQ.L     #0x1,D5                         | mark new block as end-of-chain
    BSR.B       LG2PHYS_CONT_9                  | set new block's map entry
| update counts
LG2PHYS_CONT_5:
    ADD.L       D7,D6                           | add alloc block size to allocated
    ADD.L       D7,D2                           | add to PEOF
    SUBQ.W      #0x1,0x2A(A2)                   | decrement vcbFreeBks
    CMP.L       D6,D4                           | allocated enough?
    BHI.B       LG2PHYS_NO_5                    | no, allocate more
    MOVE.L      D2,0xC(A1,D1.W)                 | update FCBPLen
    BSR.W       MARKVCB                         | mark VCB dirty
    MOVEQ.L     #0x0,D0                         | noErr
    BRA.B       LG2PHYS_EXIT                    | exit MFS Alloc
| next block is occupied: find a free one
LG2PHYS_OK_3:
    BSR.B       LG2PHYS_NEXT_3                  | scan for next free block
    BRA.B       LG2PHYS_CONT_4                  | link it in
| ----------------------------------------------------------
|
| LG2PHYS_NEXT_3
|
| LG2PHYS_NEXT_3: MFS find free block - scan alloc map for best free run
LG2PHYS_NEXT_3:
    MOVEM.L     D0-D4/D6/A1/A3,-(A7)            | save regs
    SUB.L       D6,D4                           | remaining bytes needed
    CMP.L       0x20(A2),D4                     | more than clump size? (vcbClpSiz)
    BCC.B       LG2PHYS_OK_4                    | yes, use full request
    MOVE.L      0x20(A2),D4                     | round up to clump size
| MFS Alloc: scan entire alloc map for best-fit free chain
LG2PHYS_OK_4:
    MOVEA.L     0x50(A2),A1                     | A1 = alloc map base (vcbMAdr)
    MOVEA.W     0x1A(A2),A3                     | A3 = total alloc blocks (vcbNmAlBlks)
    ADDQ.W      #0x1,A3                         | + 1 (sentinel)
    MOVEQ.L     #0x0,D5                         | D5 = even/odd 12-bit entry toggle
    MOVEQ.L     #0x2,D0                         | D0 = current block number (start at 2)
    MOVEQ.L     #0x2,D2                         | D2 = start of current free run
    MOVEQ.L     #0x0,D3                         | D3 = current run size (bytes)
    MOVEQ.L     #0x0,D6                         | D6 = best run size found
    CLR.W       -(A7)                           | best run start block (on stack)
LG2PHYS_NO_6:
    MOVE.B      (A1)+,D1                        | read byte from alloc map
    LSL.W       #0x8,D1                         | shift to high byte
    BCHG        #0x0,D5                         | toggle even/odd entry
    BNE.B       LG2PHYS_ERR_3                   | odd entry: low nibble path
    MOVE.B      (A1),D1                         | even: get low nibble of next byte
    LSR.W       #0x4,D1                         | extract high 12-bit entry
    BRA.B       LG2PHYS_CONT_6                  | check if free
| ----------------------------------------------------------
|
| LG2PHYS_ERR_3
|
LG2PHYS_ERR_3:
    MOVE.B      (A1)+,D1                        | odd: get second byte
    ANDI.W      #0xFFF,D1                       | mask to low 12-bit entry
| MFS Alloc scan: check if this block is free (entry = 0)
LG2PHYS_CONT_6:
    BNE.B       LG2PHYS_NO_8                    | occupied, reset run
    ADD.L       D7,D3                           | free: extend current run
    CMP.L       D6,D3                           | better than best so far?
    BLS.B       LG2PHYS_NO_7                    | no, keep scanning
    MOVE.L      D3,D6                           | new best run size
    MOVE.W      D2,(A7)                         | save run start block
    CMP.L       D4,D3                           | run >= needed?
    BCC.B       LG2PHYS_CONT_8                  | yes, done
LG2PHYS_NO_7:
    ADDQ.W      #0x1,D0                         | advance to next block
    BRA.B       LG2PHYS_CONT_7                  | continue scan
| ----------------------------------------------------------
|
| LG2PHYS_NO_8
|
LG2PHYS_NO_8:
    ADDQ.W      #0x1,D0                         | advance to next block
    MOVE.W      D0,D2                           | reset run start to here
    MOVEQ.L     #0x0,D3                         | reset run size
LG2PHYS_CONT_7:
    CMP.W       A3,D0                           | past end of alloc map?
    BLS.B       LG2PHYS_NO_6                    | no, keep scanning
LG2PHYS_CONT_8:
    MOVE.W      (A7)+,D5                        | D5 = best free block start
    MOVEM.L     (A7)+,D0-D4/D6/A1/A3            | restore regs
    RTS                                         | return with best free block in D5
| ----------------------------------------------------------
|
| LG2PHYS_CONT_9
|
| LG2PHYS_CONT_9: MFS alloc map write - set 12-bit entry in alloc map
| D3 = alloc block number, D5 = value to store (12-bit next block)
| Called by: LG2PHYS_CONT_4, ADJEOF_CONT_2, LG2PHYS_OK_2, LG2PHYS_NO_9
LG2PHYS_CONT_9:
    MOVEM.L     D0/D6/A2,-(A7)                  | save regs
    MOVEA.L     0x50(A2),A2                     | A2 = alloc map base (vcbMAdr)
    MOVE.W      D3,D0                           | alloc block number
    SUBQ.W      #0x2,D0                         | -2 (map starts at block 2)
    MULU.W      #0xC,D0                         | * 12 bits per entry
    ROR.L       #0x4,D0                         | convert bit offset to byte.nibble
    ASL.W       #0x1,D0                         | byte offset (word-aligned)
    MOVE.L      0x0(A2,D0.W),D6                 | get longword containing entry
    SWAP.W      D0                              | nibble offset in high word
    LSR.W       #0x8,D0                         | extract nibble index
    LSR.W       #0x4,D0                         | (total shift = 12)
    ADDI.W      #0xC,D0                         | + 12 bits for rotation
    ROL.L       D0,D6                           | rotate entry to low 12 bits
    ANDI.W      #0xF000,D6                      | clear old 12-bit value
    OR.W        D5,D6                           | insert new value (D5)
    ROR.L       D0,D6                           | rotate back to position
    SWAP.W      D0                              | restore byte offset
    MOVE.L      D6,0x0(A2,D0.W)                 | write updated longword
    MOVEM.L     (A7)+,D0/D6/A2                  | restore regs
    RTS                                         | return from alloc map write
| ----------------------------------------------------------
|
| LG2PHYS_CONT_10
|
| LG2PHYS_CONT_10/MFSDealloc: free an MFS allocation chain starting at block D3
LG2PHYS_CONT_10:
    TST.W       D3                              | chain start = 0?
    BEQ.B       LG2PHYS_CONT_11                 | yes, nothing to free
LG2PHYS_NO_9:
    BSR.W       LG2PHYS_NEXT_2                  | get next block in chain
    MOVE.W      D5,-(A7)                        | save next block
    CLR.W       D5                              | D5 = 0 (free)
    BSR.B       LG2PHYS_CONT_9                  | clear this entry in alloc map
    ADDQ.W      #0x1,0x2A(A2)                   | increment vcbFreeBks
    MOVE.W      (A7)+,D3                        | D3 = next block to free
    CMPI.W      #0x1,D3                         | end-of-chain marker?
    BNE.B       LG2PHYS_NO_9                    | no, free next block
    BSR.W       MARKVCB                         | mark VCB dirty
LG2PHYS_CONT_11:
    RTS                                         | return from LG2PHYS_CONT_11
