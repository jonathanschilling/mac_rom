| File Manager -- volume calls (MFS)
|
| The 64K ROM's File Manager handles only the flat Macintosh File System
| (MFS). This file holds the volume calls: MountVol, Eject, UnmountVol,
| FlushVol, SetVol, GetVol, GetVolInfo, with their helpers (volume
| buffer, allocation block map, VCB lookup).
|
| The File Manager files in ROM order: file_mgr_queue.s (call queue,
| _FInitQueue), file_mgr_vol.s, file_mgr_dir.s (calls by file name),
| file_mgr_io.s (calls on open files). The Mac Plus splits its HFS File
| Manager the same way (plus allocation, catalog, B-tree and cache files).
|
| VCB - Volume Control Block (MPW 1.0 Files.h):
| Offset 0: qLink Ptr next VCB in queue
| Offset 4: qType INTEGER queue type
| Offset 6: vcbFlags INTEGER volume flags
| Offset 8: vcbSigWord INTEGER volume signature ($D2D7 = MFS, $4244 = HFS)
| Offset 10: vcbCrDate LongInt volume creation date
| Offset 14: vcbLsMod LongInt last modification date
| Offset 18: vcbAtrb INTEGER volume attributes
| Offset 20: vcbNmFls INTEGER number of files in root directory
| Offset 22: vcbVBMSt INTEGER first block of volume bitmap
| Offset 24: vcbAllocPtr INTEGER start of next allocation search
| Offset 26: vcbNmAlBlks INTEGER number of allocation blocks
| Offset 28: vcbAlBlkSiz LongInt size of allocation blocks (bytes)
| Offset 32: vcbClpSiz LongInt default clump size
| Offset 36: vcbAlBlSt INTEGER first allocation block in volume
| Offset 38: vcbNxtCNID LongInt next unused catalog node ID
| Offset 42: vcbFreeBks INTEGER number of free allocation blocks
| Offset 44: vcbVN String27 volume name (Pascal string)
| Offset 72: vcbDrvNum INTEGER drive number
| Offset 74: vcbDRefNum INTEGER driver reference number
| Offset 76: vcbFSID INTEGER file system ID (0=MFS/HFS)
| Offset 78: vcbVRefNum INTEGER volume reference number
| Offset 80: vcbMAdr Ptr volume allocation map pointer
| Offset 84: vcbBufAdr Ptr volume buffer pointer
| Offset 88: vcbMLen INTEGER allocation map length
| ...further HFS-specific fields follow...
|
| File access permission constants (MPW 1.0 Files.h):
| fsCurPerm = 0 (whatever permission is allowed)
| fsRdPerm = 1 (read permission)
| fsWrPerm = 2 (write permission)
| fsRdWrPerm = 3 (exclusive read/write permission)
| fsRdWrShPerm = 4 (shared read/write permission)
|
| File positioning modes (MPW 1.0 Files.h):
| fsAtMark = 0 (at current mark)
| fsFromStart = 1 (from beginning of file)
| fsFromLEOF = 2 (from logical end of file)
| fsFromMark = 3 (from current mark)
|
| References:
| MPW 1.0 Files.h, Apple Computer Inc. 1985-1986
| Inside Macintosh: Files, Ch 2: File Manager (pp 2-5 to 2-244)
| Inside Macintosh Vol II, Ch 4: The File Manager (pp 77-144)
| Inside Macintosh Vol IV, Ch 1: HFS additions

| ----------------------------------------------------------
| _MountVol ($A00F): mount the volume in a drive (MFS)
| Pascal: FUNCTION PBMountVol(paramBlock: ParmBlkPtr): OSErr;
| Entry: A0 = parameter block, ioVRefNum = drive number
| Exit:  D0 = result code; ioVRefNum = the volume's VRefNum
| Always synchronous (FSQueueSync). Fails with volOnLinErr if a
| volume in that drive is already mounted. Allocates a VCB and a
| 522-byte volume buffer in the system heap, assigns the first
| unused negative VRefNum, reads the master directory block (needs
| the MFS signature $D2D7) and the allocation map, checks the map
| against vcbFreeBks and the directory against vcbNmFls/vcbNxtFNum
| (repairing what it can), and enqueues the VCB. If an off-line VCB
| with the same directory info and name exists, that one is put back
| on line instead (remount, NewMount = 0).
| Called during boot.
MountVol:
        BSR.W   FSQUEUE_CLR_OFFLINE             | FSQueueSync: rest runs as the FS call
        ST      (NewMount).w                    | (NewMount).w := -1 (true)
        MOVEQ.L #-0x32,D0                       | D0 = -50 = paramErr (default)
        MOVE    22(A0),D2                       | D2 = ioVRefNum (drive number)
        BLE.B   MOUNTVOL_ERR                    | invalid drive -> error
        MOVE    D2,D0                           | D0 = drive number
        BSR.W   FindVCBDrv                      | search for VCB matching drive
        BNE.B   MOUNTVOL_HAVEDRIVE              | no volume in this drive yet -> go on
        MOVEQ.L #-0x37,D0                       | D0 = -55 = volOnLinErr (already mounted)
MOUNTVOL_ERR:
        BRA.B   FSQUEUE_DONE                    | finish with error in D0
MOUNTVOL_HAVEDRIVE:
        BSR.W   FindDrive                       | D1 = driver refNum of drive D2
        BNE.B   MOUNTVOL_ERR                    | drive not in queue -> error
        MOVE.L  A0,A2                           | A2 = param block (A0 gets the new VCB)
        MOVEQ.L #0x5E,D0                        | D0 = 94 (sizeof VCB)
        _NewPtrSysClear                         | allocate cleared VCB in SysZone
        BNE.B   MOUNTVOL_ERR                    | allocation failed -> error
        EXG     A0,A2                           | A0 = param block, A2 = new VCB
        MOVE    D2,0x48(A2)                     | vcbDrvNum = drive number
        MOVE    D1,0x4A(A2)                     | vcbDRefNum = driver refNum
MOUNTVOL_INIT_LOOP:
        SUBQ.W  #0x1,D0                         | next VRefNum candidate: -1, -2, ...
| find an unused (negative) VRefNum for the new volume
        MOVEM.L D0/A2,-(SP)                     | save VRefNum candidate + VCB ptr
        BSR.W   GetVCBRFN                       | check if VRefNum already used
        MOVEM.L (SP)+,D0/A2                     | restore VRefNum + VCB
        BEQ.B   MOUNTVOL_INIT_LOOP              | in-use -> retry next number
        MOVE    D0,vcbVRefNum(A2)               | vcbVRefNum = unique negative #
        MOVE.L  #0x20A,D0                       | D0 = 522 = MDB buf + 10 hdr
        _NewPtrSysClear                         | allocate cleared MDB buffer
        BNE.B   MOUNTVOL_CLEANUP                | allocation failed -> error
        ADDA.W  #0xA,A0                         | skip 10-byte cache hdr
        MOVE.L  A0,vcbBufAdr(A2)                | vcbBufAdr = volume cache
        MOVE    (DrMstrBlk).w,D3                | D3 = master dir block # (2)
        BSR.W   HFSE_READ_VBM_BLOCK             | read master directory block
        BNE.B   MOUNTVOL_ERR_DISP_BUF           | read failed -> dispose buf
        MOVEQ.L #-0x39,D0                       | D0 = -57 = noMacDskErr
        CMPI    #-0x2D29,(A5)                   | MFS signature $D2D7 at volume buffer?
        BNE.B   MOUNTVOL_ERR_DISP_BUF           | not MFS -> error
        MOVEQ.L #-0x3C,D0                       | D0 = -60 = badMDBErr
        MOVE.L  20(A5),D1                       | D1 = drAlBlkSiz (block size)
        BEQ.B   MOUNTVOL_ERR_DISP_BUF           | zero block size -> error
        ANDI    #0x1FF,D1                       | multiple of 512?
        BNE.B   MOUNTVOL_ERR_DISP_BUF           | not aligned -> error
        MOVEQ.L #0x1F,D0                        | D0 = 31 (32 words to copy)
        MOVE.L  A5,A1                           | A1 = MDB source
        LEA.L     vcbSigWord(A2),A0             | A0 = &8(A2)
MOUNTVOL_COPY_MDB:
        MOVE    (A1)+,(A0)+                     | copy MDB word into VCB
        DBRA    D0,MOUNTVOL_COPY_MDB            | copy 32 words MDB->VCB
        MOVE.L  (VCBQHdr_Head).w,D0             | D0 = first VCB in queue
MOUNTVOL_CHK_QUEUE:
        BEQ.B   MOUNTVOL_REGISTER               | end-of-queue -> register new
        MOVE.L  D0,A0                           | A0 = candidate VCB
        MOVE.B  19(A0),19(A2)                   | copy its vcbAtrb low byte: always matches
        LEA.L     8(A0),A1                      | A1 = candidate VCB sigWord
        LEA.L     vcbSigWord(A2),A3             | A3 = new VCB's vcbSigWord
        MOVEQ.L #0xF,D0                         | 16 longs: vcbSigWord..vcbVN (offsets 8-71)
MOUNTVOL_CMP_NAME:
        CMPM.L  (A1)+,(A3)+                     | compare VCB long for remount
        BNE.B   MOUNTVOL_NEXT_VCB               | mismatch -> next VCB
        DBRA    D0,MOUNTVOL_CMP_NAME            | compare all 16 longs
        TST     (A1)                            | old VCB's vcbDrvNum = 0 (off line)?
        BNE.B   MOUNTVOL_NEXT_VCB               | still on line -> not a remount
        CLR.B   (NewMount).w                    | NewMount = 0 (it's a remount)
        MOVE.L  (A3)+,(A1)+                     | old VCB takes new vcbDrvNum + vcbDRefNum
        MOVE.L  vcbBufAdr(A2),0x54(A0)          | reuse new VCB's buf in old VCB
        EXG     A0,A2                           | A0=new VCB A2=old VCB
        _DisposePtr                             | free new VCB (use old)
        BRA.B   MOUNTVOL_REGISTER               | -> finish registration
MOUNTVOL_NEXT_VCB:
        MOVE.L  (A0),D0                         | D0 = qLink (next VCB)
        BRA.B   MOUNTVOL_CHK_QUEUE              | loop comparing VCBs
MOUNTVOL_ERR_DISP_MDB:
        BSR.B   DISPOSE_VCB_MDB                 | free the allocation map (vcbMAdr)
MOUNTVOL_ERR_DISP_BUF:
        BSR.B   DISPOSE_VCB_BUF                 | free volume cache buffer
MOUNTVOL_CLEANUP:
        TST.B   (NewMount).w                    | was this a new mount?
        BEQ.B   MOUNTVOL_RETURN                 | no (remount) -> keep VCB
        BSR.B   DISPOSE_VCB_VCB                 | free new VCB
MOUNTVOL_RETURN:
        BRA.W   MOUNTVOL_ERR                    | -> finish with error in D0
DISPOSE_VCB_MDB:
        MOVE    D0,-(SP)                        | save error code across dispose
        MOVE.L  vcbMAdr(A2),A0                  | A0 = volume bitmap buffer
        _DisposePtr                             | free bitmap buffer
        BRA.B   DISPOSE_VCB_RETURN              | -> common return
DISPOSE_VCB_BUF:
        MOVE    D0,-(SP)                        | save error code
        MOVE.L  vcbBufAdr(A2),A0                | A0 = volume cache buffer
        SUBQ.W  #0x8,A0                         | back up past cache header
        SUBQ.W  #0x2,A0                         | (10-byte hdr = 8+2 prologue)
        _DisposePtr                             | free volume cache
        BRA.B   DISPOSE_VCB_RETURN              | -> common return
DISPOSE_VCB_VCB:
        MOVE    D0,-(SP)                        | save error code
        MOVE.L  A2,A0                           | A0 = VCB ptr
        _DisposePtr                             | free VCB itself
DISPOSE_VCB_RETURN:
        MOVE    (SP)+,D0                        | restore error code
        RTS                                     | return from dispose helper
MOUNTVOL_REGISTER:
        MOVEQ.L #0x3,D2                         | 3 = 12 bits per map entry / 4
        MULU    vcbNmAlBlks(A2),D2              | D2 = 3 * number of allocation blocks
        ADDQ.L  #0x1,D2                         | round up (odd block count)
        LSR.L   #0x1,D2                         | D2 = map size in bytes (1.5 per block)
        MOVE    D2,vcbMLen(A2)                  | vcbMLen = map length in bytes
        MOVEQ.L #0x40,D7                        | D7 = 64: map starts at byte 64 of the MDB
        MOVE.L  D2,D0                           | D0 = map size
        _NewPtrSys                              | allocate the map in the system heap
        BNE.B   MOUNTVOL_ERR_DISP_BUF           | allocation failed -> error
        MOVE.L  A0,vcbMAdr(A2)                  | vcbMAdr = allocation map
| copy alloc map from MDB block(s) to memory
HFSE_NO:
        MOVE    0(A5,D7.W),(A0)+                | copy alloc map word from disk
        ADDQ.W  #0x2,D7                         | advance source offset
        SUBQ.W  #0x2,D2                         | more bytes to copy?
        BLE.B   HFSE_NO_2                       | no ->
        CMPI    #0x200,D7                       | past end of 512-byte block?
        BCS.B   HFSE_NO                         | no, keep copying
        ADDQ.W  #0x1,D3                         | next block number
        BSR.W   HFSE_READ_VBM_BLOCK             | read the next MDB block (rest of the map)
        BNE.B   MOUNTVOL_ERR_DISP_MDB           | read failed -> free map + buffer
        MOVEQ.L #0x0,D7                         | reset offset to start of block
        BRA.B   HFSE_NO                         | continue copying
HFSE_NO_2:
        MOVEQ    #0x2,D3                        | D3 = 2 (first alloc block)
        MOVEQ    #0x0,D1                        | D1 = 0 (free-block counter)
HFSE_NO_CONT:
        BSR.W   LG2PHYS_NEXT_2                  | D5 = map entry of block D3 (Z = free)
        BNE.B   HFSE_NO_3                       | not free (nonzero) ->
        ADDQ.W  #0x1,D1                         | count free block
HFSE_NO_3:
        CMP     vcbNmAlBlks(A2),D3              | past last alloc block?
        BHI.B   HFSE_NO_OK                      | yes ->
        ADDQ.W  #0x1,D3                         | next block
        BRA.B   HFSE_NO_CONT                    | keep scanning
HFSE_NO_OK:
        MOVEQ.L #-0x3C,D0                       | D0 = -60 = badMDBErr
        CMP     vcbFreeBks(A2),D1               | free-count matches MDB?
        BNE.W   MOUNTVOL_ERR_DISP_MDB           | mismatch -> badMDBErr, free map + buffer
        MOVEQ.L #0x0,D1                         | D1 = file count
        MOVEQ.L #0x0,D2                         | D2 = max file number
        MOVEQ.L #0x0,D7                         | D7 = consistency flags
        BSR.W   FILEFILETFSETCATINFO_HFS_CONT_2_CONT | read first directory block
        BNE.W   MOUNTVOL_ERR_DISP_MDB           | read error -> free map + buffer
HFSE_NO_CONT_2:
        MOVEQ.L #0x0,D0                         | D0 = 0 (offset within dir blk)
HFSE_CONT_5:
        TST.B   0(A5,D0.W)                      | dir entry's flag byte set?
        BEQ.B   HFSE_OK_4                       | flags 0: no more entries in this block
        ADDQ.W  #0x1,D1                         | increment file count
        CMP.L   0x12(A5,D0.W),D2                | file number > current max?
        BHI.B   HFSE_CONT_5_NEWMAX              | no -> skip update
        MOVE.L  0x12(A5,D0.W),D2                | record new max file number
HFSE_CONT_5_NEWMAX:
        LEA.L     0x16(A5,D0.W),A3              | A3 = data fork: start block, LEOF, PEOF
        BSR.W   HFSE_OK_4_CONT_3                | check/repair data fork PEOF
        LEA.L     0x20(A5,D0.W),A3              | A3 = resource fork fields
        BSR.B   HFSE_OK_4_CONT_3                | check/repair resource fork PEOF
        BSR.W   CREATE_NEXT                     | advance to next dir entry
        BCS.B   HFSE_CONT_5                     | more in this block ->
HFSE_OK_4:
        BSR.W   FILEWRITE_NEXT                  | read the next directory block
        BEQ.B   HFSE_NO_CONT_2                  | more dir blocks -> next
        CMPI    #-0x21,D0                       | dirFulErr (-33) = end of directory?
        BNE.W   MOUNTVOL_ERR_DISP_MDB           | other error -> free map + buffer
        CMP.L   vcbNxtCNID(A2),D2               | highest file number >= vcbNxtFNum?
        BCS.B   HFSE_OK_4_CONT                  | no -> ok
        ADDQ.L  #0x1,D2                         | bump past current max
        MOVE.L  D2,vcbNxtCNID(A2)               | repair vcbNxtFNum (offset 38)
        ADDQ.B  #0x1,D7                         | flag bit 0: next file number repaired
HFSE_OK_4_CONT:
        CMP     vcbNmFls(A2),D1                 | file count matches MDB?
        BEQ.B   HFSE_OK_4_OK                    | ok ->
        MOVE    D1,vcbNmFls(A2)                 | repair vcbNmFls
        ADDQ.B  #0x2,D7                         | flag bit 1: file count repaired
HFSE_OK_4_OK:
        TST.B   D7                              | any consistency changes?
        SNE     vcbFlags(A2)                    | mark VCB dirty if anything was repaired
        LEA.L     (Params).w,A0                 | A0 = scratch param block
        MOVE    #0x8,csCode(A0)                 | csCode 8 = drive status
        _Status                                 | get drive write-protect status
        TST.B   ioFlAttrib(A0)                  | csParam+2 = writeProt: bit 7 = locked
        BPL.B   HFSE_OK_4_SKIP_BSET             | not write-protected ->
        BSET    #0x7,D7                         | vcbAtrb bit 7: locked by hardware
HFSE_OK_4_SKIP_BSET:
        MOVE.B  D7,19(A2)                       | vcbAtrb low byte = D7
        MOVE.L  (FSQHdr_Head).w,A0              | A0 = current FS request
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | return vRefNum to caller
        TST.B   (NewMount).w                    | new mount (vs remount)?
        BEQ.B   HFSE_OK_4_CONT_2                | remount -> skip enqueue
        MOVE.L  A2,A0                           | A0 = new VCB
        LEA.L     (VCBQHdr_Flags).w,A1          | A1 = VCB queue header
        TST.L   0x2(A1)                         | VCBQHdr_Head != nil? (any volumes?)
        BNE.B   HFSE_OK_4_SKIP_DEFVCB           | yes -> skip DefVCBPtr update
        MOVE.L  A2,(DefVCBPtr).w                | first volume -> set as default
HFSE_OK_4_SKIP_DEFVCB:
        JSR     Enqueue(PC)                     | insert new VCB into queue
HFSE_OK_4_CONT_2:
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.W   MOUNTVOL_ERR                    | finish via shared exit
| HFSE_OK_4_CONT_3 - MountVol helper: recompute a fork's physical
| length from its allocation-block chain and repair the directory
| entry if it differs. A3 = fork fields of the entry (start block.W,
| LEOF.L, PEOF.L), A2 = VCB; sets D7 bit 2 if the entry was changed.
HFSE_OK_4_CONT_3:
        MOVEM.L D2-D6,-(SP)                     | save D2-D6 across walk
        MOVEQ.L #0x0,D6                         | D6 = computed PEOF accumulator
        MOVE.L  vcbAlBlkSiz(A2),D2              | D2 = alloc-block size in bytes
        MOVE    (A3),D3                         | D3 = fork's first allocation block
        BEQ.B   HFSE_NO_5                       | zero start block -> empty fork
HFSE_OK_4_CONT_4:
        BSR.W   LG2PHYS_NEXT_2                  | D5 = map entry of block D3
        MOVE    D5,D3                           | D3 = next block in the chain
        BEQ.B   HFSE_NO_5                       | entry 0 (free): stop
        ADD.L   D2,D6                           | PEOF += alloc block size
        CMPI    #0x1,D3                         | 1 = this was the file's last block?
        BNE.B   HFSE_OK_4_CONT_4                | more blocks -> continue
| compare with the entry's PEOF and repair the entry if needed
HFSE_NO_5:
        MOVE    (A3)+,D3                        | D3 = start block (from the entry)
        MOVE.L  (A3)+,D4                        | D4 = LEOF
        MOVE.L  (A3)+,D5                        | D5 = PEOF
        CMP.L   D5,D6                           | PEOF matches the chain length?
        BEQ.B   HFSE_NO_5_OK                    | yes, nothing to update ->
        MOVE.L  D6,-(A3)                        | update PEOF in directory
        BNE.B   HFSE_NO_5_CONT                  | nonzero ->
        CLR     D3                              | PEOF=0: clear start block
HFSE_NO_5_CONT:
        CMP.L   D6,D4                           | LEOF > PEOF?
        BLS.B   HFSE_NO_5_CONT_2                | LEOF<=PEOF -> skip
        MOVE.L  D6,D4                           | yes, pin LEOF to PEOF
HFSE_NO_5_CONT_2:
        MOVE.L  D4,-(A3)                        | write LEOF into entry
        MOVE    D3,-(A3)                        | write start-block into entry
        BSET    #0x7,-2(A5)                     | mark dir block dirty
        BSET    #0x2,D7                         | flag: dir entry rewritten
HFSE_NO_5_OK:
        MOVEM.L (SP)+,D2-D6                     | restore D2-D6
        RTS                                     | return from extent walk
QueueSearch:
        MOVE.L  D2,-(SP)                        | restore A0
        MOVE.L  2(A0),D2                        | D2 = head of queue
QSEARCH_LOOP:
        BEQ.B   QSEARCH_NOTFOUND                | end of queue -> not found
        MOVE.L  D2,A0                           | A0 = current queue element
        CMP     0(A0,D1.W),D0                   | key field == D0?
        BEQ.B   QSEARCH_FOUND                   | match -> done
        MOVE.L  (A0),D2                         | D2 = qLink (next element)
        BRA.B   QSEARCH_LOOP                    | loop searching queue
QSEARCH_FOUND:
        MOVEQ.L #0x0,D0                         | D0 = 0 (found)
QSEARCH_RET:
        MOVE.L  (SP)+,D2                        | restore D2
        TST     D0                              | set CCR for caller
        RTS                                     | return found/notfound flag
QSEARCH_NOTFOUND:
        MOVEQ.L #-0x1,D0                        | D0 = -1 (not found)
        BRA.B   QSEARCH_RET                     | return not-found

| ----------------------------------------------------------
| Find Drive
| Called during boot.
| FindDrive: find drive queue entry for drive number D2
| Returns: D1=driver refnum, A3=drive queue entry, D0=0 or error
FindDrive:
        MOVE.L  A0,-(SP)                        | save A0 (caller's param ptr)
        MOVE    D2,D0                           | D0 = drive number to find
        LEA.L     (DrvQHdr_Flags).w,A0          | A0 = drive queue header
        MOVEQ.L #0x6,D1                         | D1 = offset 6 = drvNum field
        BSR.B   QueueSearch                     | search drive queue for D0
        BNE.B   FINDDRIVE_FOUND                 | not found -> error
        MOVE    8(A0),D1                        | D1 = driver refnum
        MOVE    10(A0),D0                       | D0 = FSID (0=native, !=0 ext)
        BEQ.B   FINDDRIVE_EMPTY                 | no, native FS ->
        MOVEQ.L #-0x3A,D0                       | ExtFSErr: external FS
FINDDRIVE_EMPTY:
        MOVE.L  (SP)+,A0                        | restore caller's A0
        RTS                                     | return drive lookup result
FINDDRIVE_FOUND:
        MOVEQ.L #-0x38,D0                       | D0 = -56 = nsDrvErr
        BRA.B   FINDDRIVE_EMPTY                 | return not-found error

| ----------------------------------------------------------
| Eject -- _Eject ($A017).
| Pascal: function Eject(volName: StringPtr; vRefNum: INTEGER): OSErr;
| Flushes the volume buffers, then sends a control(7)=eject call
| to the disk driver. Classic 1984 has no NoEject flag (no _OffLine
| trap until Plus 1986), no per-drive-type handling (no SCSI/HD20
| in 1984), and no MFS-specific flush split. Begins by trapping
| to _FlushVol (rather than BSR'ing FlushVol's body inline) -- Plus
| 1986 uses an inline BSR via the OFFLINE_CONT_2 helper instead.
Eject:
        _FlushVol                               | flush volume buffers via trap
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.W   DTRMV3                          | DTRMV: determine volume from param block
        BEQ.B   FINDDRIVE_CONT_2                | volume found via VCB - take VCB path
        MOVE    ioVRefNum(A0),D2                | D2 = drive number from param block
        BSR.B   FindDrive                       | find drive queue entry
        BEQ.B   EJECT_NO_3                      | success -> send eject control call
FINDDRIVE_NO_2:
        BRA.W   FSQUEUE_DONE                    | error/CmdDone
FINDDRIVE_CONT_2:
        BSR.W   HFSE_NO_9_CONT_3                | flush volume buffers to disk
        BNE.B   FINDDRIVE_NO_2                  | flush failed -> propagate err
        LEA.L     vcbDrvNum(A2),A1              | A1 = &0x48(A2)
        MOVE    (A1),D2                         | D2 = vcbDrvNum
        BEQ.B   FINDDRIVE_NO_2                  | already offline -> done
        CLR     (A1)+                           | vcbDrvNum = 0 (mark offline)
        MOVE    (A1),D1                         | D1 = vcbDRefNum
        MOVE    D2,(A1)+                        | vcbDRefNum = old drvNum (save)
        ADDQ.W  #0x4,A1                         | skip vcbFSID/vcbVRefNum
        BSR.W   DISPOSE_VCB_MDB                 | free vcbMAdr (bitmap buffer)
        CLR.L   (A1)+                           | vcbMAdr = nil
        BSR.W   DISPOSE_VCB_BUF                 | free vcbBufAdr (cache)
        CLR.L   (A1)                            | vcbBufAdr = nil
| EJECT_NO_3: send eject/offline control call to disk driver
EJECT_NO_3:
        LEA.L     (Params).w,A0                 | I/O param block
        LEA.L     ioVRefNum(A0),A1              | ptr to drive number field
        MOVE    D2,(A1)+                        | drive number
        MOVE    D1,(A1)+                        | driver refnum
        MOVE    #0x7,(A1)                       | csCode = 7 (eject)
        LEA     FSQUEUE_DONE(PC),A1             | completion routine = CmdDone
        MOVE.L  A1,ioCompletion(A0)             | set I/O completion address
        _ControlAsync                           | send async eject control call
        RTS                                     | return while async eject completes

| ----------------------------------------------------------
| UnmountVol -- _UnmountVol ($A00E).
| Pascal: function UnmountVol(volName: StringPtr; vRefNum: INTEGER): OSErr;
| Closes all open files on a volume and disposes its VCB. Sets
| FlushOnly := false (close mode), then falls into the common
| flush/close path shared with FlushVol (EJECT_NO_3_CONT below).
UnmountVol:
        BSR.W   FSQUEUE_CLR_OFFLINE             | FSQueue: wait our turn
        CLR.B   (FlushOnly).w                   | close, not just flush
        BRA.B   EJECT_NO_3_CONT                 | -> common flush/close path

| ----------------------------------------------------------
| FlushVol -- _FlushVol ($A013).
| Pascal: function FlushVol(volName: StringPtr; vRefNum: INTEGER): OSErr;
| Flushes (writes) all dirty buffers for a volume to disk without
| unmounting. Sets FlushOnly := true (flush-only mode), then falls
| into the common path shared with UnmountVol.
FlushVol:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST      (FlushOnly).w                   | FlushOnly := -1 (flush-only)
EJECT_NO_3_CONT:
        BSR.W   DTRMV3                          | resolve volume from param blk
        BNE.B   EJECT_NO_3_CONT_2               | volume not found -> error
        BSR.W   HFSE_NO_9_CONT_3                | reject external-FS volumes
        BNE.B   EJECT_NO_3_CONT_2               | ext FS -> ExtFSErr
        BSR.W   SETVOLINFO_HFS_CONT_3_CONT      | flush dirty cache buffers
UNMOUNTVOL_CONT_2:
        TST.L   fcbFlNm(A1,D1.W)                | FCB in use? (FCBFlNm)
        BEQ.B   EJECT_NO_3_NO                   | free FCB -> skip
        CMPA.L  fcbVPtr(A1,D1.W),A2             | FCB belongs to volume in A2? (FCBVPtr)
        BNE.B   EJECT_NO_3_NO                   | no -> skip this FCB
        BSR.W   FILECLOSE_NO_3                  | TFS volume?
EJECT_NO_3_CONT_2:
        BNE.B   HFSE_LOOP_NO                    | close failed -> abort flush
EJECT_NO_3_NO:
        BSR.W   HFSE_NEXT                       | advance to next FCB slot
        BCS.B   UNMOUNTVOL_CONT_2               | more FCBs to scan ->
        TST     vcbDrvNum(A2)                   | volume already offline?
        BEQ.B   HFSE_NO_9                       | yes -> skip MDB rewrite
        MOVE.L  vcbBufAdr(A2),A5                | A5 = volume cache buffer
        MOVE    -2(A5),D3                       | D3 = cache flags + block #
        BCLR    #0xF,D3                         | clear dirty bit; was it set?
        BEQ.B   EJECT_NO_3_CONT_3               | not dirty -> skip flush
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_3     | flush dirty cache to disk
        BNE.B   HFSE_LOOP_NO                    | flush err -> abort
EJECT_NO_3_CONT_3:
        TST     vcbFlags(A2)                    | VCB dirty flag set?
        BPL.B   HFSE_NO_9                       | not dirty -> skip MDB write
        MOVE    (DrMstrBlk).w,D3                | D3 = MDB block number (2)
        CLR.L   -10(A5)                         | clear cache hdr longword
        CLR.L   -6(A5)                          | clear cache hdr 2nd long
        MOVEQ.L #0x1F,D0                        | D0 = 31 (32 words to copy)
        MOVE.L  A5,A1                           | A1 = MDB destination
        LEA.L     vcbSigWord(A2),A0             | A0 = &8(A2)
        MOVE.L  (Time).w,vcbLsBkUp(A2)          | timestamp last-flushed time
HFSE_LOOP:
        MOVE    (A0)+,(A1)+                     | copy VCB to MDB
        DBF     D0,HFSE_LOOP                    | loop for all VCB words
| copy alloc map to MDB (offset $40 in MDB block)
        MOVE.L  vcbMAdr(A2),A0                  | source = alloc map in memory
        MOVE    vcbMLen(A2),D2                  | alloc map length
        MOVEQ.L #0x40,D7                        | dest offset in MDB block
HFSE_LOOP_CONT:
        MOVE    (A0)+,0(A5,D7.W)                | copy alloc map word to MDB
        ADDQ.W  #0x2,D7                         | advance dest offset
        SUBQ.W  #0x2,D2                         | decrement word counter
        BLE.B   HFSE_LOOP_CONT_2                | done copying ->
        CMPI    #0x200,D7                       | dest offset past 512 bytes?
        BCS.B   HFSE_LOOP_CONT                  | still in current block ->
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_3     | flush full block to disk
        BNE.B   HFSE_LOOP_NO                    | flush err -> abort
        ADDQ.W  #0x1,D3                         | advance to next block #
        CLR.L   D7                              | reset offset to 0
        BRA.B   HFSE_LOOP_CONT                  | continue copying alloc map
HFSE_LOOP_NO:
        BRA.W   FSQUEUE_DONE                    | finish via CmdDone
HFSE_LOOP_CONT_2:
        CMPI    #0x200,D7                       | reached end of MDB block?
        BCS.B   HFSE_LOOP_CONT_3                | no -> pad with zeros
        CLR     0(A5,D7.W)                      | zero-pad MDB tail
        ADDQ.W  #0x2,D7                         | advance pad offset
        BRA.B   HFSE_LOOP_CONT_2                | loop until block end
HFSE_LOOP_CONT_3:
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_3     | flush final MDB block
        BNE.B   HFSE_LOOP_NO                    | flush err -> abort
HFSE_NO_9:
        CLR.B   vcbFlags(A2)                    | clear
        TST.B   (FlushOnly).w                   | flush-only mode?
        BNE.B   HFSE_NO_9_CONT_2                | yes -> skip dispose
        TST     vcbDrvNum(A2)                   | already offline?
        BEQ.B   BMCHK_NO                        | yes -> just dequeue VCB
        BSR.W   DISPOSE_VCB_MDB                 | call helper
        BSR.W   DISPOSE_VCB_BUF                 | free volume cache buffer
BMCHK_NO:
        MOVE.L  A2,A0                           | VCB to dequeue
        LEA.L     (VCBQHdr_Flags).w,A1          | VCB queue header
        JSR     Dequeue(PC)                     | remove from VCB queue
        CMPA.L  (DefVCBPtr).w,A2                | unmounting default vol?
        BNE.B   HFSE_NO_9_CONT                  | no -> skip default clear
        CLR.L   (DefVCBPtr).w                   | clear default VCB pointer
HFSE_NO_9_CONT:
        _DisposePtr                             | free VCB memory
HFSE_NO_9_CONT_2:
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.B   HFSE_LOOP_NO                    | finish via CmdDone
HFSE_NO_9_CONT_3:
        MOVE    vcbFSID(A2),D0                  | D0 = vcbFSID
        BEQ.B   HFSE_NO_9_CONT_4                | native FS (0) -> ok
        MOVEQ.L #-0x3A,D0                       | D0 = -58 = ExtFSErr
HFSE_NO_9_CONT_4:
        RTS                                     | return ExtFS check result

| ----------------------------------------------------------
| GetVCBRFN -- find the VCB with VRefNum D0.
| Searches the VCB queue for a volume whose vcbVRefNum (offset
| $4E = 78) matches D0. Returns A2 -> VCB if found (Z=1), or
| nsvErr (-35) if not.
| Apple source name: GetVCBRfn (System 7.1 OS/HFS/TFSCOMMON.a)
| Called during boot.
GetVCBRFN:
        MOVEM.L D1/A0,-(SP)                     | save regs
        MOVEQ.L #0x4E,D1                        | offset of vcbVRefNum (78)
        BRA.B   GETVCBRFN_SCAN                  | -> shared queue search
| ----------------------------------------------------------
| FindVCBDrv -- find VCB by drive number in D0.
| vcbDrvNum (offset $48 = 72) match.
| Called during boot.
FindVCBDrv:
        MOVEM.L D1/A0,-(SP)                     | save regs
        MOVEQ.L #0x48,D1                        | offset of vcbDrvNum (72)
GETVCBRFN_SCAN:
        LEA.L     (VCBQHdr_Flags).w,A0          | A0 = VCB queue header
        BSR.W   QueueSearch                     | search VCBs by D1-offset key
        BNE.B   GETVCBRFN_NSVERR                | not found -> nsvErr
        MOVE.L  A0,A2                           | A2 = found VCB ptr
GETVCBRFN_RET:
        MOVEM.L (SP)+,D1/A0                     | restore D1/A0
        RTS                                     | return VCB lookup result
GETVCBRFN_NSVERR:
        MOVEQ.L #-0x23,D0                       | D0 = -35 = nsvErr
        BRA.B   GETVCBRFN_RET                   | return error
DTRMV3:
        TST.L   ioFileName(A0)                  | volume specified by name?
        BNE.B   DTRMV1_NO_4                     | yes -> name path
DTRMV1:
        MOVE    ioVRefNum(A0),D0                | D0 = ioVRefNum
        BEQ.B   DTRMV1_EMPTY                    | zero -> use default vol
        BMI.B   DTRMV1_CONT                     | negative -> VRefNum lookup
        BSR.B   FindVCBDrv                      | positive -> drive# lookup
DTRMV1_CONT_2:
        BNE.B   DTRMV1_FOUND                    | not found -> error
        MOVE.L  A2,(ReqstVol).w                 | ReqstVol = found VCB ptr
        TST     D0                              | set CCR for caller
DTRMV1_FOUND:
        RTS                                     | return resolved volume
DTRMV1_CONT:
        BSR.B   GetVCBRFN                       | lookup by VRefNum
        BRA.B   DTRMV1_CONT_2                   | merge with success path
DTRMV1_EMPTY:
        MOVE.L  (DefVCBPtr).w,D0                | D0 = default VCB ptr
        BEQ.B   DTRMV1_NO                       | no default -> error
        MOVE.L  D0,A2                           | A2 = default VCB
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.B   DTRMV1_CONT_2                   | merge with success path
DTRMV1_NO:
        MOVEQ.L #-0x32,D0                       | D0 = -50 = paramErr
        RTS                                     | return param error
DTRMV1_NO_4:
        MOVE.L  ioFileName(A0),D2               | get VCB name length byte
DTRMV1_CONT_7:
        MOVEM.L D4-D6/A0-A1/A3/A6,-(SP)         | save scratch regs
        BEQ.B   DTRMV1_EMPTY_2                  | nil filename -> empty
        MOVE.L  D2,A4                           | A4 = filename ptr
        MOVEQ.L #0x0,D2                         | clear high bits of D2
        MOVE.B  (A4)+,D2                        | next VCB (qLink)
        MOVE.L  D2,D3                           | D3 = name length
        BEQ.B   DTRMV1_EMPTY_2                  | zero-length name -> empty
DTRMV1_NO_5:
        MOVE.B  -1(A4,D3.W),D4                  | D4 = name[D3-1] (scan backwards for ':')
        CMPI.B  #0x3A,D4                        | ':' separator?
        BEQ.B   DTRMV1_FOUND_3                  | ':' found -> volume name
        SUBQ.W  #0x1,D3                         | decrement scan offset
        BNE.B   DTRMV1_NO_5                     | more chars to scan ->
        BSR.B   DTRMV1                          | no ':' -> by VRefNum/default
DTRMV1_CONT_8:
        MOVEM.L (SP)+,D4-D6/A0-A1/A3/A6         | restore regs
        TST     D0                              | set CCR for caller
        RTS                                     | return resolution result
DTRMV1_EMPTY_2:
        MOVEQ.L #-0x25,D0                       | D0 = -37 = bdNamErr
        BRA.B   DTRMV1_CONT_8                   | return bad-name error
DTRMV1_FOUND_3:
        SUB.L   D3,D2                           | D2 = filename remaining len
        MOVE.L  A4,A1                           | A1 = filename ptr
        ADDA.L  D3,A4                           | A4 = past ':' separator
        SUBQ.W  #0x1,D3                         | D3 = volume-name length
        MOVE.L  (VCBQHdr_Head).w,D0             | D0 = first VCB
DTRMV1_CONT_9:
        BEQ.B   DTRMV1_CONT_10                  | end of queue ->
        MOVE.L  D0,A2                           | A2 = this VCB
        LEA.L     vcbVN(A2),A0                  | volume name
        MOVEQ.L #0x0,D0                         | VCB name length (high word)
        MOVE.B  (A0)+,D0                        | get VCB name length byte
        SWAP    D0                              | move to high word for CmpString
        MOVE    D3,D0                           | search name length (low word)
        _CmpString                              | compare names
        BNE.B   DTRMV1_FOUND_5                  | no match ->
        MOVE.L  A2,(ReqstVol).w                 | found it: set requested volume
        BRA.B   DTRMV1_CONT_8                   | return success
DTRMV1_FOUND_5:
        MOVE.L  (A2),D0                         | D0 = qLink (next VCB)
        BNE.B   DTRMV1_CONT_9                   | more VCBs to check ->
DTRMV1_CONT_10:
        MOVEQ.L #-0x23,D0                       | nsvErr = -35 (no such volume)
        BRA.B   DTRMV1_CONT_8                   | -> restore regs and return

| ----------------------------------------------------------
| SetVol -- _SetVol ($A015).
| Pascal: function SetVol(volName: StringPtr; vRefNum: INTEGER): OSErr;
| Sets the default volume. Determines the requested volume from
| the param block (name + VRefNum), then stores the resulting
| VCB pointer in DefVCBPtr. Plus 1986 added an HFS GetDir/SetDir
| bit check (BTST #9,D1) and the DefVRefNum + WDCB chain logic;
| classic 1984 just sets DefVCBPtr.
SetVol:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.W   DTRMV3                          | DTRMV3: determine volume
        BNE.B   SETVOL_ERR                      | error -> CmdDone with error
        MOVE.L  A2,(DefVCBPtr).w                | set default VCB pointer
SETVOL_ERR:
        BRA.W   FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
| GetVol -- _GetVol ($A014).
| Pascal: function GetVol(volName: StringPtr;
| VAR vRefNum: INTEGER): OSErr;
| Returns the default volume's VRefNum and (optionally) name.
| Classic 1984 reads DefVCBPtr into D1; Plus 1986 reads into D0
| (different register), checks HFS GetDir bit first, and tracks
| DefVRefNum separately.
GetVol:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.L  (DefVCBPtr).w,D1                | D1 = default VCB pointer
        BEQ.B   GETVOL_NO                       | no default volume -> NSVErr
        MOVE.L  D1,A2                           | A2 = default VCB
        BSR.B   GETVOL_CONT_2                   | copy VRefNum + name to caller
GETVOL_CONT:
        BRA.W   FSQUEUE_DONE                    | CmdDone
GETVOL_NO:
        MOVEQ.L #-0x23,D0                       | D0 = -35 = nsvErr
        BRA.B   GETVOL_CONT                     | return error via CmdDone
GETVOL_CONT_2:
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | ioVRefNum = vcbVRefNum
        LEA.L     vcbVN(A2),A2                  | A2 = &0x2C(A2)
        MOVE.L  ioFileName(A0),D0               | D0 = caller's name buffer
        BEQ.B   GETVOL_SKIP                     | nil buffer -> skip copy
        MOVE.L  D0,A1                           | A1 = caller's name buffer
        MOVE.B  (A2),D0                         | D0 = name length
GETVOL_LOOP:
        MOVE.B  (A2)+,(A1)+                     | copy name byte to caller
        SUBQ.B  #0x1,D0                         | decrement byte counter
        BCC.B   GETVOL_LOOP                     | more bytes (incl len) ->
GETVOL_SKIP:
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        RTS                                     | return from GetVol helper
| ----------------------------------------------------------
| GetVolInfo -- _GetVolInfo ($A007).
| Pascal: function GetVolInfo(VAR ioParam: HParamBlockRec): OSErr;
| Returns information about a volume -- selected by index (D2>0),
| by VRefNum (D2=0), or by name (D2<0). Body byte-equivalent
| to Plus through the dispatch trampoline.
GetVolInfo:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE    ioVolIndex(A0),D2               | D2 = ioVolIndex
        BGT.B   GETVOLINFO_CONT_2               | positive: index into VCB queue ->
        BEQ.B   GETVOLINFO_EMPTY                | zero: use ioVRefNum ->
        BSR.W   DTRMV3                          | negative: DTRMV3 - find by name
        BRA.B   GETVOLINFO_CONT                 | merge with shared exit
GETVOLINFO_EMPTY:
        BSR.W   DTRMV1                          | resolve via VRefNum/default
GETVOLINFO_CONT:
        BNE.B   HFSE_CONT_13_CONT               | not found -> CmdDone
        BRA.B   GETVOLINFO_EXIT                 | fall through to fill-out
GETVOLINFO_CONT_2:
        MOVE.L  (VCBQHdr_Head).w,D1             | D1 = first VCB ptr
GETVOLINFO_CONT_3:
        BEQ.B   GETVOL_NO                       | end of queue -> nsvErr
        SUBQ.W  #0x1,D2                         | decrement index counter
        MOVE.L  D1,A2                           | A2 = current VCB
        BEQ.B   GETVOLINFO_EXIT                 | reached requested index ->
        MOVE.L  (A2),D1                         | D1 = qLink (next VCB)
        BRA.B   GETVOLINFO_CONT_3               | loop walking VCBs
GETVOLINFO_EXIT:
        BSET     #0x6,19(A2)                    | set "fork-search" flag
        BSR.B   SETVOLINFO_HFS_CONT_3_CONT      | A1 = FCB array, D1 = 2
HFSE_CONT_13:
        CMPA.L  fcbVPtr(A1,D1.W),A2             | FCB belongs to this volume? (FCBVPtr)
        BEQ.B   HFSE_CONT_13_OK                 | yes ->
        BSR.B   HFSE_NEXT                       | advance to next FCB
        BCS.B   HFSE_CONT_13                    | unsigned less ->
        BCLR    #0x6,19(A2)                     | clear flag
HFSE_CONT_13_OK:
        MOVEQ.L #0x20,D0                        | D0 = 32 (highest word offset)
HFSE_CONT_13_OK_2:
        MOVE    0xA(A2,D0.W),0x1E(A0,D0.W)      | copy VCB field to param block
        SUBQ.W  #0x2,D0                         | decrement word offset
        BPL.B   HFSE_CONT_13_OK_2               | yes ->
        BSR.B   GETVOL_CONT_2                   | fill ioVRefNum + name
HFSE_CONT_13_CONT:
        BRA.W   FSQUEUE_DONE                    | finish with ioResult = D0

| ----------------------------------------------------------
| SETVOLINFO_HFS_CONT_3: check volume write protect status
| Called during boot.
SETVOLINFO_HFS_CONT_3:
        MOVEQ.L #-0x2E,D0                       | vLckdErr: assume software locked
        TST     vcbAtrb(A2)                     | user-locked? (VCBAtrb bit 15)
        BMI.B   SETVOLINFO_HFS_CONT_3_OK        | yes ->
        MOVEQ.L #-0x2C,D0                       | wPrErr: hardware write protect
        TST.B   19(A2)                          | write protected? (VCBAtrb+1 bit 7)
        BMI.B   SETVOLINFO_HFS_CONT_3_OK        | yes ->
        MOVEQ.L #0x0,D0                         | not locked, not protected
SETVOLINFO_HFS_CONT_3_OK:
        RTS                                     | return write-protect status
SETVOLINFO_HFS_CONT_3_CONT:
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB array base
        MOVEQ.L #0x2,D1                         | D1 = 2 (skip count word)
        RTS                                     | return Gt1stFCB initial state
HFSE_NEXT:
        ADDI    #0x1E,D1                        | D1 += sizeof(FCB)
        CMP     (A1),D1                         | D1 within FCB-array length?
        RTS                                     | return GtNxtFCB result (CC)
HFSE_NEXT_CONT:
        BSR.B   SETVOLINFO_HFS_CONT_3_CONT      | A1 = FCBSPtr, D1 = 2
HFSE_NEXT_CONT_2:
        CMP.L   fcbFlNm(A1,D1.W),D2             | D2 == FCB-at-D1.filenum?
        BNE.B   HFSE_ERR_9                      | no -> advance to next FCB
        CMPA.L  fcbVPtr(A1,D1.W),A2             | A2 == FCB-at-D1.VCBPtr?
        BEQ.B   HFSE_NEXT_MATCH                 | match: return with Z=1

| HFSE_ERR_9 -- gtNxtMatch: find next matching FCB.
HFSE_ERR_9:
        BSR.B   HFSE_NEXT                       | advance D1 by FCB size
        BCS.B   HFSE_NEXT_CONT_2                | still in table -> retry
        MOVE    #0x0,CCR                        | clear all condition flags (Z=0)
HFSE_NEXT_MATCH:                                | @ $3F02 (common exit)
        RTS                                     | return matched FCB or CCR=0

