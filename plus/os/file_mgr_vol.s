| File Manager -- common subroutines and volume calls
|
| Apple sources, included by TFS.a (MacSEROM.lst module TURBOFS):
| TFSCommon.a (vDoEject, DivUp, RoundAlloc, QueueSearch, GetVCBRFN,
| FindVCBDrv, ResolveWDVCB, MarkVCB, FlushMDB, MakeStkPB) and TFSVol.a /
| MFSVol.a: MountVol, OffLine, Eject, UnmountVol, FlushVol, GetVolInfo,
| SetVolInfo, GetVol, SetVol and the working-directory calls (OpenWD,
| CloseWD, GetWDInfo, SetDir/GetDir), for HFS and MFS volumes.
|
| The File Manager files in ROM order: file_mgr_queue.s (dispatch, queue),
| file_mgr_vol.s, file_mgr_dir.s (calls by file name), file_mgr_io.s
| (calls on open files), file_mgr_alloc.s (volume bitmap, extents),
| file_mgr_catalog.s, file_mgr_btree.s, file_mgr_cache.s.
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
|
| vDoEject - eject a disk, with optional notification callback
|
| D1 = drive number, D2 = eject reason code
vDoEject:
        BSR     MakeStkPB                       | build zeroed 64-byte param block on stack
        MOVE    D1,0x16(A0)                     | store drive number in ioVRefNum
        MOVE.L  (EjectNotify).w,D0              | eject notification proc installed?
        BLE.B   VDOEJECT_DO_EJECT               | no callback -> just eject
        MOVEM.L D2/A0-A2,-(SP)                  | save regs across callback
        CLR     -(SP)                           | push result space (boolean)
        MOVE    D1,-(SP)                        | push drive number
        MOVE    D2,-(SP)                        | push eject reason code
        MOVE.L  D0,A0                           | load callback address
        JSR     (A0)                            | call EjectNotify(drive, reason): boolean
        TST.B   (SP)+                           | callback returned true (cancel eject)?
        MOVEM.L (SP)+,D2/A0-A2                  | restore regs
        BEQ.B   VDOEJECT_DONE                   | callback said cancel -> skip eject, done
VDOEJECT_DO_EJECT:
        _Eject                                  | eject the disk from the drive
        BEQ.B   VDOEJECT_DONE                   | eject succeeded -> done
        MOVE    #0x8,-(SP)                      | push duration = 8 ticks
        _SysBeep                                | beep to indicate eject failure
VDOEJECT_DONE:
        ADDA    #0x40,SP                        | free 64-byte stack param block
        RTS                                     | return from eject/switch handler

| ----------------------------------------------------------
|
| DivUp - unsigned divide D0/D1 with round-up (ceiling division)
|
| Returns ceil(D0/D1) in D0.W. Used for allocation block calculations.
| Called by: RoundAlloc, FlushMDB, MOUNTVOL_CONT_6, MOUNTVOL_FOUND_3, MOUNTVOL_OK_9 (and 1 more)
DivUp:
        DIVU    D1,D0                           | D0 = quotient:remainder (hi:lo words)
        SWAP    D0                              | move remainder to low word
        TST     D0                              | any remainder?
        BEQ.B   DIVUP_EXACT                     | no remainder -> exact division, use quotient
        CLR     D0                              | clear remainder
        SWAP    D0                              | bring quotient back to low word
        ADDQ.W  #0x1,D0                         | round up: quotient + 1
        BRA.B   DIVUP_RET                       | return

| ----------------------------------------------------------
|
| DIVUP_EXACT - exact division, no rounding needed
|
DIVUP_EXACT:
        SWAP    D0                              | bring quotient to low word
DIVUP_RET:
        RTS                                     | return from DivUp

| ----------------------------------------------------------
|
| RoundAlloc - round byte count D0 up to D1 allocation-block-aligned
|
| Given D0=current byte count, D1=requested bytes, A2->VCB:
| Returns D0 = number of allocation blocks needed, rounded up
| to the nearest multiple of ceil(D1/vcbAlBlkSiz) alloc blocks.
| vcbAlBlkSiz is at offset 0x1C (28) in the VCB.
RoundAlloc:
        MOVE.L  D1,-(SP)                        | save original D1
        MOVE.L  D0,-(SP)                        | save original D0 (current byte count)
        MOVE.L  D1,D0                           | D0 = requested bytes
        MOVE.L  0x1C(A2),D1                     | D1 = vcbAlBlkSiz (bytes per alloc block)
        BSR.B   DivUp                           | D0 = ceil(requested / alBlkSiz) = clump blocks
        MOVE.L  D0,D1                           | D1 = clump size in alloc blocks
        MOVE.L  (SP)+,D0                        | D0 = current byte count
        MOVE.L  D1,-(SP)                        | save clump blocks
        MOVE.L  0x1C(A2),D1                     | D1 = vcbAlBlkSiz again
        BSR.B   DivUp                           | D0 = ceil(current / alBlkSiz) = current blocks
        MOVE.L  (SP)+,D1                        | D1 = clump blocks
        BSR.B   DivUp                           | D0 = ceil(currentBlks / clumpBlks) = # clumps
        MULU    D1,D0                           | D0 = clumps * clumpBlks = total alloc blocks
        MOVE.L  (SP)+,D1                        | restore original D1
        RTS                                     | return from RoundAlloc

| ----------------------------------------------------------
|
| QueueSearch - search a queue for element with word at offset D1 == D0
|
| Entry: A0 -> queue header, D0 = key to match, D1 = field offset
| Exit: Z=1 if found (A0 -> matching element), Z=0 if not found
QueueSearch:
        MOVE.L  D2,-(SP)                        | save D2 (used as link follower)
        MOVE.L  0x2(A0),D2                      | D2 = qHead (first element in queue)
QSEARCH_LOOP:
        BEQ.B   QSEARCH_NOTFOUND                | null -> end of queue, not found
        MOVE.L  D2,A0                           | A0 -> current queue element
        CMP     0x0(A0,D1.W),D0                 | compare field at offset D1 with key D0
        BEQ.B   QSEARCH_FOUND                   | match found -> return success
        MOVE.L  (A0),D2                         | follow qLink to next element
        BRA.B   QSEARCH_LOOP                    | continue search

| ----------------------------------------------------------
|
| QSEARCH_FOUND - queue search: element found
|
QSEARCH_FOUND:
        MOVEQ.L #0x0,D0                         | D0=0, sets Z flag (found)
QSEARCH_RET:
        MOVE.L  (SP)+,D2                        | restore D2
        TST     D0                              | set Z flag from D0 for caller
        RTS                                     | return from QueueSearch queue search

| ----------------------------------------------------------
|
| QSEARCH_NOTFOUND - queue search: element not found
|
QSEARCH_NOTFOUND:
        MOVEQ.L #-0x1,D0                        | D0=-1, clears Z flag (not found)
        BRA.B   QSEARCH_RET                     | -> restore D2 and return

| ----------------------------------------------------------
|
| GetVCBRFN - find VCB by drive refnum in D0
|
| Searches the VCB queue for a volume whose vcbDRefNum (offset 0x4E=78)
| matches D0. Returns A2 -> VCB if found (Z=1), or nsvErr (-35) if not.
GetVCBRFN:
        MOVEM.L D1/A0,-(SP)                     | save regs
        MOVEQ.L #0x4E,D1                        | offset of vcbDRefNum in VCB (78 bytes)
        LEA.L   (VCBQHdr_Flags).w,A0            | A0 -> VCB queue header
        BSR.B   QueueSearch                     | search queue for D0 at offset D1
        BNE.B   GETVCBRFN_NSVERR                | not found -> return nsvErr
        MOVE.L  A0,A2                           | A2 -> matching VCB
GETVCBRFN_RET:
        MOVEM.L (SP)+,D1/A0                     | restore regs
        RTS                                     | return from GetVCB

| ----------------------------------------------------------
|
| GETVCBRFN_NSVERR - VCB not found, return nsvErr (-35)
|
GETVCBRFN_NSVERR:
        MOVEQ.L #-0x23,D0                       | nsvErr = -35 (no such volume)
        BRA.B   GETVCBRFN_RET                   | -> restore regs and return

| ----------------------------------------------------------
|
| FindVCBDrv - find VCB by drive number (D0) or negative volume refnum
|
| Searches VCB queue for a volume whose vcbDrvNum (offset 0x48=72)
| matches D0, or whose vcbVRefNum (offset 0x4A=78) matches -D0
| (for offline volumes where vcbDrvNum=0). Returns A2->VCB, Z=1.
FindVCBDrv:
        MOVEM.L D1-D2,-(SP)                     | save regs
        MOVE    D0,D1                           | D1 = drive number to match
        MOVE    D0,D2                           | D2 = copy for negation
        NEG     D2                              | D2 = -driveNum (= volume refnum for offline)
        MOVE.L  (VCBQHdr_Head).w,A2             | A2 -> first VCB in queue
FINDVCB_LOOP:
        MOVE.L  A2,D0                           | test for null (end of VCB queue)
        BEQ.B   FINDVCB_NSVERR                  | null -> volume not found
        CMP     0x48(A2),D1                     | vcbDrvNum matches drive number?
        BEQ.B   FINDVCB_FOUND                   | yes -> found the mounted volume
        TST     0x48(A2)                        | vcbDrvNum = 0? (volume is offline)
        BNE.B   FINDVCB_NEXT                    | no, mounted on different drive -> skip
        CMP     0x4A(A2),D2                     | vcbVRefNum matches -driveNum?
        BEQ.B   FINDVCB_FOUND                   | yes -> found offline volume for this drive
FINDVCB_NEXT:
        MOVE.L  (A2),A2                         | follow qLink to next VCB
        BRA.B   FINDVCB_LOOP                    | continue search

| ----------------------------------------------------------
|
| FINDVCB_FOUND - VCB found
|
FINDVCB_FOUND:
        MOVEQ.L #0x0,D0                         | noErr, Z=1 (found)
FINDVCB_RET:
        MOVEM.L (SP)+,D1-D2                     | restore regs
        RTS                                     | return from VCB name search

| ----------------------------------------------------------
|
| FINDVCB_NSVERR - VCB not found, return nsvErr
|
FINDVCB_NSVERR:
        MOVEQ.L #-0x23,D0                       | nsvErr = -35 (no such volume)
        BRA.B   FINDVCB_RET                     | -> restore regs and return

| ----------------------------------------------------------
|
| ResolveWDVCB - resolve working directory refnum (D0) to its VCB
|
| WD refnums range from -32767..-4096 (WDRfnMin..WDRfnMax).
| Each maps to an entry in the WDCB array. The WDCB contains
| a pointer to the VCB at offset 0. Returns A2->VCB, Z=1.
ResolveWDVCB:
        MOVE.L  (WDCBsPtr).w,A3                 | A3 -> base of WDCB array
        MOVEM.L D1/A1,-(SP)                     | save regs
        MOVEQ.L #0x0,D1                         | clear high word
        MOVE    D0,D1                           | D1 = WD refnum (negative)
        BSR     HFSF_CONT_3                     | validate WD refnum range
        BNE.B   WDLOOKUP_RET                    | invalid -> return error
        SUBI    #-0x7FFF,D1                     | convert refnum to WDCB table offset
        ADDA    D1,A3                           | A3 -> WDCB entry for this WD
        MOVEQ.L #-0x23,D0                       | assume nsvErr (-35)
        MOVE.L  (A3),D1                         | get VCB pointer from WDCB entry
        BEQ.B   WDLOOKUP_RET                    | null VCB ptr -> WD not active
        MOVE.L  D1,A2                           | A2 -> VCB for this working directory
        MOVEQ.L #0x0,D0                         | noErr, Z=1
WDLOOKUP_RET:
        MOVEM.L (SP)+,D1/A1                     | restore regs
        TST     D0                              | set Z flag from result
        RTS                                     | return from WDirID lookup

| ----------------------------------------------------------
|
| MarkVCB - mark VCB dirty and update last-modification time
|
| Sets the dirty flag (vcbFlags byte, offset 6) and stores
| the current system time in vcbLsMod (offset 0xE=14).
MarkVCB:
        BSR.B   SetVCBDirty                     | set vcbFlags dirty bit
| MarkVCBTime -- mark the VCB dirty.
| Called by: HFSCATMOVE_OK_6, CC_UPD_PAR, DC_UPD_PAR, MC_EXIT, RC_EXIT (and 1 more)
MarkVCBTime:
        MOVE.L  (Time).w,0xE(A2)                | vcbLsMod = current time (seconds since 1904)
        RTS                                     | return from MarkVCBTime

| ----------------------------------------------------------
|
| SetVCBDirty - set VCB dirty flag
|
SetVCBDirty:
        ST.B    0x6(A2)                         | vcbFlags = 0xFF (bit 15 = dirty)
        RTS                                     | return from SetVCBDirty

| ----------------------------------------------------------
|
| FlushMDB - write the master directory block (MDB) to disk
|
| Copies VCB fields back into the cached MDB block, updates
| extent B-tree and catalog B-tree file size info from their
| FCB entries, then releases the block to be written to disk.
| A2 -> VCB, A6 = FS stack frame pointer (LIFO return stack).
FlushMDB:
        MOVE.L  (SP)+,-(A6)                     | push return addr onto FS stack (A6)
        MOVEM.L D0-D2/A0-A1,-(A6)               | save working regs on FS stack
        TST.B   0x6(A2)                         | vcbFlags dirty? (bit 7 set by ST.B)
        BPL     FLUSHMDB_DONE                   | not dirty -> nothing to flush
        MOVE.L  0x54(A2),A1                     | vcbBufAdr: volume buffer pointer
        MOVE    0x4E(A2),D0                     | vcbDRefNum: driver refnum
        MOVEQ.L #0x0,D1                         | block number 0 (relative)
        MOVEQ.L #0x2,D2                         | flags: get for write
        JSR     P_mGetBlock(PC)                 | get MDB cache block into A0
        BNE     FLUSHMDB_DONE                   | cache error -> skip flush
        MOVE.L  A0,A1                           | A1 -> MDB block buffer
        LEA.L   0x8(A2),A0                      | A0 -> vcbSigWord (start of MDB data in VCB)
        MOVE.L  #0xA2,D0                        | copy 162 bytes (full MDB from VCB)
        _BlockMove                              | copy VCB MDB fields to cache block
        LEA.L   0x5E(A2),A0                     | A0 -> vcbTDInfoSt (HFS extension at offset 94)
        LEA.L   0x40(A1),A1                     | A1 -> drTInfoSt in MDB block (offset 64)
        MOVEQ.L #0x42,D0                        | copy 66 bytes (HFS-specific VCB data)
        _BlockMove                              | copy HFS extension fields
        SUBA.L  #0x40,A1                        | A1 -> start of MDB block again
        MOVE.L  (FCBSPtr).w,A3                  | A3 -> FCB array base
        MOVE    0xA4(A2),D1                     | vcbXTRef: extent B-tree FCB refnum
        MOVEM.L A0-A1,-(SP)                     | save ptrs across BlockMove
        MOVEQ.L #0xC,D0                         | copy 12 bytes (3 extent records)
        LEA.L   0x26(A3,D1.W),A0                | A0 -> fcbExtRec of extent B-tree FCB
        LEA.L   0x86(A1),A1                     | A1 -> drXTExtRec in MDB (offset 134)
        _BlockMove                              | copy extent B-tree extent records to MDB
        MOVEM.L (SP)+,A0-A1                     | restore ptrs
        MOVE.L  0xC(A3,D1.W),D0                 | fcbPLen of extent B-tree (physical length)
        MOVE.L  D0,0x82(A1)                     | store as drXTFlSize in MDB (offset 130)
        MOVE.L  0x1C(A2),D1                     | vcbAlBlkSiz (bytes per allocation block)
        JSR     DivUp(PC)                       | D0 = ceil(xtFlSize / alBlkSiz) = xt alloc blocks
        MOVE    D0,0xA0(A2)                     | store in vcbXTAlBks (offset 160)
        MOVE    0xA6(A2),D1                     | vcbCTRef: catalog B-tree FCB refnum
        MOVEM.L A0-A1,-(SP)                     | save ptrs
        MOVEQ.L #0xC,D0                         | copy 12 bytes (3 extent records)
        LEA.L   0x26(A3,D1.W),A0                | A0 -> fcbExtRec of catalog B-tree FCB
        LEA.L   0x96(A1),A1                     | A1 -> drCTExtRec in MDB (offset 150)
        _BlockMove                              | copy catalog B-tree extent records to MDB
        MOVEM.L (SP)+,A0-A1                     | restore ptrs
        MOVE.L  0xC(A3,D1.W),D0                 | fcbPLen of catalog B-tree (physical length)
        MOVE.L  D0,0x92(A1)                     | store as drCTFlSize in MDB (offset 146)
        MOVE.L  0x1C(A2),D1                     | vcbAlBlkSiz
        JSR     DivUp(PC)                       | D0 = ceil(ctFlSize / alBlkSiz) = ct alloc blocks
        MOVE    D0,0xA2(A2)                     | store in vcbCTAlBks (offset 162)
        MOVEQ.L #0x1,D1                         | mark block dirty (write-back needed)
        MOVE.L  A1,A0                           | A0 -> MDB cache block
        MOVE.L  0x54(A2),A1                     | vcbBufAdr
        JSR     P_mRelBlock(PC)                 | release MDB block (will be flushed to disk)
        CLR.B   0x6(A2)                         | clear vcbFlags dirty bit
FLUSHMDB_DONE:
        MOVEM.L (A6)+,D0-D2/A0-A1               | restore regs from FS stack
        MOVE.L  (A6)+,-(SP)                     | pop return address from FS stack
        TST     D0                              | set condition codes from result
        RTS                                     | return from FlushMDB

| ----------------------------------------------------------
|
| MakeStkPB - allocate a zeroed 64-byte IOParam block on the stack
|
| Pops the return address, pushes 32 zero words (64 bytes) onto SP,
| then returns with A0 -> the param block (just above return addr).
MakeStkPB:
        MOVE.L  (SP)+,A0                        | save return address in A0
        MOVEQ.L #0x1F,D0                        | loop count = 31 (32 iterations with DBF)
MAKESTKPB_CLRLOOP:
        CLR     -(SP)                           | push one zero word
        DBF     D0,MAKESTKPB_CLRLOOP            | repeat 32 times = 64 bytes
        MOVE.L  A0,-(SP)                        | push return address back on stack
        MOVE.L  A7,A0                           | A0 -> param block (SP + 4, past return addr)
        ADDQ.W  #0x4,A0                         | skip return address to point at param block
        RTS                                     | return from MakeStkPB

| Called during boot.
| _MountVol: mount a volume from disk
MountVol:
        MOVE    ioVRefNum(A0),D2                | D2 = drive number
        MOVEM.L D1-D2/A0-A1,-(SP)               | save regs
        BSR.B   MOUNTVOL_CONT_3                 | try to mount the volume
        MOVEM.L (SP)+,D1-D2/A0-A1               | restore regs
        CMPI    #-0x6C,D0                       | not a Mac disk? (NoMacDskErr)
        BEQ.B   MOUNTVOL_RETRY                  | retry after offlineing stale volumes
        CMPI    #-0x2A,D0                       | too many files open? (TMFOErr)
        BEQ.B   MOUNTVOL_RETRY                  | retry after offlineing
        RTS                                     | return (success or other error)
| retry: offline any stale offline-but-mounted volumes and try again
MOUNTVOL_RETRY:
        MOVE    D2,ioVRefNum(A0)                | restore drive number
MOUNTVOL_OK:
        MOVE.L  (VCBQHdr_Head).w,D0             | scan VCB queue
MOUNTVOL_CONT:
        BEQ.B   MOUNTVOL_CONT_2                 | end of queue, give up ->
        MOVE.L  D0,A1                           | A1 = VCB
        TST     0x4C(A1)                        | VCB has FSID? (external FS)
        BNE.B   MOUNTVOL_SKIP                   | yes, skip ->
        MOVE    0x48(A1),D2                     | drive number (VCBDrvNum)
        BNE.B   MOUNTVOL_OK_2                   | volume is online, offline it ->
MOUNTVOL_SKIP:
        MOVE.L  (A1),D0                         | next VCB in queue
        BRA.B   MOUNTVOL_CONT                   | keep scanning
| offline the stale volume and retry mount
MOUNTVOL_OK_2:
        MOVE.L  A0,-(SP)                        | save param block ptr
        BSR.B   MakeStkPB                       | make a param block on the stack
        MOVE    D2,ioVRefNum(A0)                | drive number
        _OffLine                                | put the volume offline
        ADDA    #0x40,SP                        | clean up stack param block
        MOVE.L  (SP)+,A0                        | restore param block ptr
        BNE.B   MOUNTVOL_OK                     | offlined ok, scan for more
        BRA.B   MountVol                        | retry the mount
MOUNTVOL_CONT_2:
        MOVEQ.L #-0x6C,D0                       | NoMacDskErr: no mountable disk found
        RTS                                     | return with NoMacDskErr

| ----------------------------------------------------------
|
| MOUNTVOL_CONT_3
|
| Called during boot.
| MOUNTVOL_CONT_3: main mount path (called from MountVol)
MOUNTVOL_CONT_3:
        BSR     FSQUEUE_SETUP_SYNC              | FSQueue: wait our turn
        ST.B    (NewMount).w                    | assume it's a new volume
MOUNTVOL_CONT_4:
        MOVEQ.L #-0x32,D0                       | ParamErr (assume bad drive number)
        MOVE    ioVRefNum(A0),D2                | D2 = drive number
        BLE.B   MOUNTVOL_EXIT                   | invalid drive number ->
| mv_Start: see if the disk is already mounted
        MOVE    D2,D0                           | see if there's a vol already mounted
        BSR     FindVCBDrv                      | GetVCBDrv
        BNE.B   MOUNTVOL_NO                     | br if not
        TST     vcbDrvNum(A2)                   | is it offline?
        BEQ.B   MOUNTVOL_NO                     | br if so (probably a remount)
        MOVEQ.L #-0x37,D0                       | VolOnLinErr: volume already online
MOUNTVOL_EXIT:
        BRA     MTVOLDONE                       | -> MtVolDone: finish MountVol with the result in D0
| mv_getDrive: find drive queue entry and allocate a VCB
MOUNTVOL_NO:
        BSR     FindDrive                       | get driver refnum in D1
        BNE.B   MOUNTVOL_EXIT                   | br if not found or external FS
        MOVE.L  A0,A2                           | preserve A0
        MOVE.L  #0xB2,D0                        | get memory for VCB (VCBLength)
        _NewPtrSysClear                         | allocate from system heap, zeroed
        BNE.B   MOUNTVOL_EXIT                   | exit if no memory
        LEA.L   (VCBQHdr_Flags).w,A1            | point to head of VCB queue
        TST.L   0x2(A1)                         | check: is queue empty? (QHead)
        BNE.B   MOUNTVOL_NO_2                   | if not, never mind
| first VCB: set up as default
        MOVE.L  A0,(DefVCBPtr).w                | this is now default VCB
        MOVE.L  (WDCBsPtr).w,A1                 | point to WDCB array
        MOVE.L  A0,0x2(A1)                      | set default VCB ptr in default WDCB
        MOVEQ.L #0x2,D0                         | FSRtDirID: default to root directory
        MOVE.L  D0,0x6(A1)                      | set directory to default to (WDDirID)
        CLR.L   0xA(A1)                         | clear catalog hint (WDCatHint)
        CLR.L   0xE(A1)                         | and procID (WDProcID)
        LEA.L   (VCBQHdr_Flags).w,A1            | reset A1 for VCB insertion
MOUNTVOL_NO_2:
        JSR     Enqueue(PC)                     | insert the new VCB in the queue
        EXG     A0,A2                           | A2 = VCB ptr
        MOVE    D2,vcbDrvNum(A2)                | put drive number
        MOVE    D1,vcbDRefNum(A2)               | and driver refnum into VCB
        MOVE.L  (SysVolCPtr).w,A1               | set up A1
        MOVE.L  A1,vcbBufAdr(A2)                | always use system-wide cache
| assign a refNum to this new volume
        MOVEQ.L #0x0,D0                         | begin with a clean slate
MOUNTVOL_CONT_5:
        SUBQ.W  #0x1,D0                         | start with -1 and count down
        MOVEM.L D0/A2,-(SP)                     | save VRefNum candidate and VCB
        BSR     GetVCBRFN                       | check if already assigned
        MOVEM.L (SP)+,D0/A2                     | restore VRefNum candidate and VCB
        BEQ.B   MOUNTVOL_CONT_5                 | if EQ, VRefNum already assigned
        MOVE    D0,vcbVRefNum(A2)               | note for us
        CMPA.L  (DefVCBPtr).w,A2                | are we the default?
        BNE.B   MOUNTVOL_SKIP_2                 | nope, don't worry about it
        MOVE    D0,(DefVRefNum).w               | set up default VRefNum too
| mv_GetMDB: read the master directory block
MOUNTVOL_SKIP_2:
        MOVEQ.L #0x0,D1                         | clear flag bytes
        MOVEQ.L #0x2,D2                         | MDB is always block 2
        JSR     P_mGetBlock(PC)                 | read MDB into cache
        BNE     MTVOLER2                        | quit & release VCB on errors
        MOVE.L  A0,A5                           | save buffer ptr for later
        MOVEQ.L #0x2,D1                         | trash option (kRBTrash)
        JSR     P_mRelBlock(PC)                 | release hold on cache block
| check what manner of animal we have before us
        CMPI    #0x4244,(A5)                    | does it bear the Turbo Seal? (TSigWord)
        BEQ.B   MOUNTVOL_CONT_6                 | if so, give it full treatment
        MOVEQ.L #-0x39,D0                       | NoMacDskErr: assume not a Mac disk
        CMPI    #-0x2D29,(A5)                   | is it a trustworthy MFS volume? (SigWord=$D2D7)
        BNE     MTVOLER2                        | br if not
| mv_GotMDB: now do a little more checking
MOUNTVOL_CONT_6:
        MOVEQ.L #-0x3C,D0                       | BadMDBErr: in case MDB is bad
        MOVE.L  0x14(A5),D1                     | make sure alloc blk size is valid (DrAlBlkSiz)
        BEQ     MTVOLER1                        | exit if 0
        ANDI    #0x1FF,D1                       | 512-byte multiple?
        BNE     MTVOLER1                        | exit if not
| transfer master directory info from buffer into VCB
        LEA.L   vcbSigWord(A2),A1               | destination is in VCB (VCBDInfoSt)
        MOVEQ.L #0x40,D0                        | length of MFS/TFS info in MDB (VCBDILen)
        _BlockMove                              | copy the information
| MV_GetWPStatus: get write-protect status from driver
        MOVE.L  (FSQHdr_Head).w,A0              | A0 -> current request
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | return volume refnum to user
        LEA.L   (Params).w,A0                   | general purpose I/O param block
        MOVE    #0x8,0x1A(A0)                   | drive status (DrvStsCode)
        CLR.B   ioFlAttrib(A0)                  | clear status byte for return
        _Status                                 | get drive status
        MOVEQ.L #-0x80,D0                       | $80 mask
        AND.B   ioFlAttrib(A0),D0               | write-protect status bit
        MOVE.B  D0,0x13(A2)                     | VCBAtrb+1: write-protect flag
| now the MFS code diverges from TFS code
        BSR     TFSVCBTst                       | is it an MFS volume?
        BNE     HFSE_CONT                       | br if so (do MFS-specific stuff)
| TFS-specific setup: copy additional TFS info
        LEA.L   0x40(A5),A0                     | advance to additional TFS stuff (DrTInfoSt)
        LEA.L   vcbVolBkUp(A2),A1               | additional TFS-specific info (VCBTDInfoSt)
        MOVEQ.L #0x42,D0                        | length of additional info (VCBTDILen)
        _BlockMove                              | copy the additional information in
| compute extent and catalog alloc block counts
        MOVE.L  vcbAlBlkSiz(A2),D1              | allocation block size
        MOVE.L  0x82(A5),D0                     | PEOF of extent B*-Tree (DrXTFlSize)
        JSR     DivUp(PC)                       | divide by alloc block size
        MOVE    D0,0xA0(A2)                     | VCBXTAlBks
        MOVE.L  0x92(A5),D0                     | PEOF of catalog B*-Tree (DrCTFlSize)
        JSR     DivUp(PC)                       | compute similarly
        MOVE    D0,0xA2(A2)                     | VCBCTAlBks
        CLR     vcbAllocPtr(A2)                 | restart the roving allocation ptr
        ADDQ.L  #0x1,vcbWrCnt(A2)               | compensate for write of MDB on last flush
| find two free FCBs for the volume control B*-Trees
        BSR     BMCHK_CONT_5                    | FindFCB: try to find a free FCB
        BNE     MTVOLERR                        | br if failed
        MOVE    D1,0xA4(A2)                     | set Extents B*-Tree file refNum (VCBXTRef)
        MOVE.L  0x82(A5),0x8(A1,D1.W)           | set extent tree's LEOF (FCBEOF = DrXTFlSize)
        MOVE.L  0x82(A5),0xC(A1,D1.W)           | set extent tree's PEOF (FCBPLen = DrXTFlSize)
        MOVEQ.L #0xC,D0                         | length of extent record (lenXDR)
        LEA.L   0x86(A5),A0                     | point to XT extent record (DrXTExtRec)
        LEA.L   0x26(A1,D1.W),A1                | point to FCB extent record (FCBExtRec)
        _BlockMove                              | copy in the extent record
        BSR     BMCHK_CONT_5                    | FindFCB: find another FCB
        BNE     MTVOLERR                        | punt on error
        MOVE    D1,0xA6(A2)                     | save catalog file refNum (VCBCTRef)
        MOVE.L  0x92(A5),0x8(A1,D1.W)           | set catalog tree's LEOF (DrCTFlSize)
        MOVE.L  0x92(A5),0xC(A1,D1.W)           | set catalog tree's PEOF (DrCTFlSize)
        MOVEQ.L #0xC,D0                         | length of extent record (lenXDR)
        LEA.L   0x96(A5),A0                     | point to first catalog extent record (DrCTExtRec)
        LEA.L   0x26(A1,D1.W),A1                | point to FCB extent record
        _BlockMove                              | copy in the extent record
| set up volume caches
        MOVE.L  (SysBMCPtr).w,vcbMAdr(A2)       | set up the volume bitmap cache
        MOVE.L  (SysCtlCPtr).w,0xA8(A2)         | set up the volume control cache (VCBCtlBuf)
| finish setting up FCBs for extent and catalog B*-Trees
        MOVE    0xA4(A2),D0                     | get extent-tree refNum (VCBXTRef)
        MOVEQ.L #0x3,D1                         | extent-tree file ID (FSXTCNID)
        MOVE.L  vcbXTClpSiz(A2),D2              | clump size
        MOVE.L  0xA8(A2),A1                     | extent-tree cache (VCBCtlBuf)
        LEA.L   FXMKeyCmp(PC),A3                | key comparison routine for extent tree
        BSR     BMCHK_CONT_8                    | AccessBT: set up access to B*-Tree file
        BNE     MTCHKERR                        | exit on errors
        MOVE    0xA6(A2),D0                     | get catalog-tree refNum (VCBCTRef)
        MOVEQ.L #0x4,D1                         | catalog-tree file ID (FSCTCNID)
        MOVE.L  vcbCTClpSiz(A2),D2              | clump size
        MOVE.L  0xA8(A2),A1                     | catalog-tree cache
        LEA.L   CMKeyCmp(PC),A3                 | key comparison routine for catalog tree
        BSR     BMCHK_CONT_8                    | AccessBT: set up access to B*-Tree file
        BNE     MTCHKERR                        | exit on errors
| mark disk as inconsistent from now until unmount
        BCLR    #0x8,vcbAtrb(A2)                | VCBAtVOK: was consistency bit set?
        BEQ     MTCHECK                         | if clear, do the disk check
| CheckRemount: scan VCB queue for matching offline volume
CHECKREMOUNT:
        MOVE.L  (VCBQHdr_Head).w,D0             | start of VCB queue
MOUNTVOL_CONT_7:
        BEQ     MTVOLOK                         | end of queue, no remount found ->
        MOVE.L  D0,A4                           | A4 = candidate VCB
        CMPA.L  A4,A2                           | skip our own VCB
        BEQ.B   MOUNTVOL_NO_3                   | ->
        MOVE    0x8(A4),D0                      | pick up SigWord of mounted volume
        CMP     vcbSigWord(A2),D0               | same signature?
        BNE.B   MOUNTVOL_NO_3                   | no ->
        MOVE.L  0xA(A4),D0                      | pick up creation date of mounted volume
        CMP.L   vcbCrDate(A2),D0                | same create date?
        BNE.B   MOUNTVOL_NO_3                   | no ->
| compare the volume names
        LEA.L   0x2C(A4),A1                     | name of mounted volume (vcbVN of old VCB)
        LEA.L   vcbVN(A2),A3                    | name of current volume
        MOVEQ.L #0xD,D0                         | check 14 words in name field (28 bytes incl length)
MOUNTVOL_LOOP:
        CMPM    (A1)+,(A3)+                     | field match?
        DBNE    D0,MOUNTVOL_LOOP                | loop comparing all name words
        BNE.B   MOUNTVOL_NO_3                   | names differ ->
        TST     (A1)                            | extra check (padding?)
        BEQ.B   MOUNTVOL_FOUND                  | match! this is a remount ->
MOUNTVOL_NO_3:
        MOVE.L  (A4),D0                         | next VCB in queue (qLink)
        BRA.B   MOUNTVOL_CONT_7                 | keep scanning

| ----------------------------------------------------------
|
| MOUNTVOL_FOUND
|
| remount found: verify all open FCBs still match catalog
MOUNTVOL_FOUND:
        BSR     HFSE_CONT_14                    | Gt1stFCB: get first FCB
MOUNTVOL_CONT_8:
        CMPA.L  0x14(A1,D1.W),A4                | FCB belongs to this volume? (FCBVPtr)
        BNE     MOUNTVOL_SKIP_3                 | no, skip ->
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   MOUNTVOL_OK_3                   | yes, verify via catalog ->
| MFS verification: check file entry in MFS directory
        MOVE    0x1C(A1,D1.W),D3                | start block from FCB
        BSR     FILEWRITE_NO_4                  | read MFS directory block
        BNE     MTVOLOK                         | error ->
        MOVEQ.L #0x0,D0                         | initial offset
        MOVE.L  0x0(A1,D1.W),D3                 | file number from FCB (FCBFlNm)
MOUNTVOL_CONT_9:
        CMP.L   0x12(A5,D0.W),D3                | compare with directory entry's file number
        BEQ.B   MOUNTVOL_FOUND_2                | match ->
        BSR     CREATE_NEXT                     | next MFS directory entry
        BCS.B   MOUNTVOL_CONT_9                 | keep scanning
        BRA     MTVOLOK                         | not found, error ->
MOUNTVOL_FOUND_2:
        LEA.L   0x16(A5,D0.W),A3                | point to data fork info in entry
        BTST    #0x1,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
        BEQ.B   MOUNTVOL_NO_4                   | no ->
        LEA.L   0x20(A5,D0.W),A3                | point to rsrc fork info
MOUNTVOL_NO_4:
        MOVE    (A3)+,D0                        | start block from directory
        CMP     0x6(A1,D1.W),D0                 | compare with FCB's start block (FCBStBlk)
        BNE     MTVOLOK                         | mismatch ->
        MOVE.L  (A3)+,D0                        | logical EOF from directory
        BRA.B   MOUNTVOL_NO_5                   | go check against FCB ->
| TFS verification: look up catalog record
MOUNTVOL_OK_3:
        MOVE.L  0x0(A1,D1.W),D0                 | file number from FCB (FCBFlNm)
        CMPI.L  #0x10,D0                        | system file? (CNID < 16)
        BCS.B   MOUNTVOL_SKIP_3                 | yes, skip verification ->
        MOVEM.L D2/A0-A1,-(A6)                  | save regs
        MOVE.L  0x3A(A1,D1.W),D0                | parent DirID (FCBDirID)
        LEA.L   0x3E(A1,D1.W),A0                | ptr to CName (FCBCName)
        MOVEQ.L #0x0,D2                         | no hint
        JSR     CMGetCN(PC)                     | look up catalog record
        MOVE.L  A1,A3                           | A3 = catalog data record
        MOVEM.L (A6)+,D2/A0-A1                  | restore regs
        BNE.B   MTVOLOK                         | not found ->
        CMPI.B  #0x2,(A3)                       | file record? (cdrFilRec)
        BNE.B   MTVOLOK                         | no, error ->
        MOVE.L  0x1A(A3),D0                     | data fork logical EOF (filLgLen)
        BTST    #0x1,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
        BEQ.B   MOUNTVOL_NO_5                   | no ->
        MOVE.L  0x24(A3),D0                     | rsrc fork logical EOF (filRLgLen)
MOUNTVOL_NO_5:
        CMP.L   0x8(A1,D1.W),D0                 | compare with FCB's LEOF (FCBEOF)
        BNE.B   MTVOLOK                         | mismatch ->
MOUNTVOL_SKIP_3:
        BSR     HFSE_NEXT                       | GtNxtFCB: get next FCB
        BCS     MOUNTVOL_CONT_8                 | more FCBs ->
| all FCBs verified: this is a valid remount
        CLR.B   (NewMount).w                    | not a new mount (it's a remount)
        MOVE    0x4E(A4),D1                     | D1 = VRefNum from old VCB
| copy new VCB data into old VCB (transfer mount to existing VCB)
        LEA.L   vcbSigWord(A2),A0               | source = new VCB data
        LEA.L   0x8(A4),A1                      | dest = old VCB
        MOVEQ.L #0x56,D0                        | MFS VCB copy size
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   MOUNTVOL_NO_6                   | no, MFS size ->
        MOVE    #0xAA,D0                        | TFS VCB copy size
MOUNTVOL_NO_6:
        _BlockMove                              | copy VCB data
        MOVE    D1,0x4E(A4)                     | restore old VCB's FSID
| update B-tree FCB VCB pointers for TFS volumes
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   MOUNTVOL_NO_7                   | no ->
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    0xA4(A2),D0                     | extent tree refNum (VCBXTRef)
        MOVE.L  A4,0x14(A1,D0.W)                | point extent FCB to old VCB
        MOVE    0xA6(A2),D0                     | catalog tree refNum (VCBCTRef)
        MOVE.L  A4,0x14(A1,D0.W)                | point catalog FCB to old VCB
MOUNTVOL_NO_7:
| dequeue and dispose the new VCB (keep the old one)
        BSR     OFFLINE_CONT                    | close B-tree files on new VCB
        MOVE.L  A2,A0                           | new VCB (to be disposed)
        MOVE.L  A4,A2                           | A2 = old VCB
        LEA.L   (VCBQHdr_Flags).w,A1            | VCB queue header
        JSR     Dequeue(PC)                     | remove new VCB from queue
        _DisposePtr                             | free new VCB memory
        MOVE.L  (FSQHdr_Head).w,A0              | A0 -> current request
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | return volume refnum to user
| MtVolOK
MTVOLOK:
        MOVEQ.L #0x0,D0                         | no errors
| MtVolDone
MTVOLDONE:
        TST     D0                              | any errors encountered?
        BNE.B   MOUNTVOL_SKIP_4                 | yes, leave well enough alone
        BSR     TFSVCBTst                       | mounted a TFS volume?
        BNE.B   MOUNTVOL_SKIP_4                 | nope, don't mess with MDB
        BTST    #0x7,0x13(A2)                   | volume write protected? (VCBWrProt)
        BNE.B   MOUNTVOL_SKIP_4                 | if so, don't flush MDB
        BSR     SetVCBDirty                     | MarkVCBDirty
        BSR     FlushMDB                        | write the MDB
MOUNTVOL_SKIP_4:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| MTCHKERR
|
| MtChkErr: B-tree open errors during mount
MTCHKERR:
        MOVE    D0,(HFSDSErr).w                 | save HFS error for debugging
        MOVEQ.L #-0x3C,D0                       | BadMDBErr
| MtVolErr: close any opened B-tree files
MTVOLERR:
        BSR     BMCHK_CONT                      | close extent/catalog B-trees
| MtVolEr1: shared MFS/TFS error exit
MTVOLER1:
        BSR     BMCHK_CONT_4                    | flush and trash volume caches
| MtVolEr2: release VCB and exit
MTVOLER2:
        TST.B   (NewMount).w                    | is this a new mount?
        BEQ.B   MOUNTVOL_NO_8                   | no (remount), keep old VCB ->
        BSR     BMCHK_CONT_2                    | dequeue and dispose the new VCB
MOUNTVOL_CONT_10:
        TST     D0                              | check error code
        BLE     FSQUEUE_DONE                    | CmdDone if error or ok ->
        MOVE.L  (FSQHdr_Head).w,A0              | retry with next drive
        BRA     MOUNTVOL_CONT_4                 | ->
| remount error: clean up the remounted VCB's TFS-specific fields
MOUNTVOL_NO_8:
        ADDA    #0x48,A2                        | advance to TFS-specific area
        MOVE    (A2),D3                         | save VCBAllocPtr
        CLR     (A2)+                           | clear VCBAllocPtr
        MOVE    D3,(A2)+                        | restore (shifted)
        ADDQ.W  #0x4,A2                         | skip padding
        CLR.L   (A2)+                           | clear VCBXTRef/VCBCTRef
        CLR.L   (A2)+                           | clear VCBMAdr
        BRA.B   MOUNTVOL_CONT_10                | ->

| ----------------------------------------------------------
|
| MTCHECK
|
| MtCheck: disk consistency check (runs on first mount after unclean shutdown)
MTCHECK:
        MOVEQ.L #0x2,D0                         | root DirID (FSRtDirID=2)
        MOVEQ.L #0x0,D2                         | no hint
        MOVE.L  D2,A0                           | no CName (get thread record)
        JSR     CMGetCN(PC)                     | locate root directory record
        BNE.B   MTCHKERR                        | error ->
| check if volume name in catalog matches VCB
        MOVEQ.L #0x0,D0                         | clear for CmpString param
        LEA.L   0x6(A0),A1                      | ptr to CName in catalog key (ckrCName)
        MOVE.B  (A1)+,D0                        | catalog name length
        SWAP    D0                              | move to high word
        LEA.L   vcbVN(A2),A0                    | volume name in VCB
        MOVE.B  (A0)+,D0                        | VCB name length
        SWAP    D0                              | both lengths now in D0
        _CmpStringCaseMarks                     | compare names
        BEQ.B   MOUNTVOL_FOUND_3                | names match ->
| volume name changed: rename root directory to match VCB
        SUBQ.L  #0x1,A1                         | back up to include length bytes
        SUBQ.L  #0x1,A0                         | back up VCB name ptr too
        EXG     A0,A1                           | swap for CMRenameCN (old=A0, new=A1)
        MOVEQ.L #0x1,D0                         | root's parent (FSRtParID=1)
        JSR     CMRenameCN(PC)                  | rename the root directory
        BNE.B   MTCHKERR                        | error ->
| verify bitmap for extent and catalog B-tree files
MOUNTVOL_FOUND_3:
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    0xA4(A2),D1                     | extent tree refNum (VCBXTRef)
        LEA.L   0x26(A1,D1.W),A0                | extent tree extent record (FCBExtRec)
        BSR     BMChk                           | BlkChk: verify bitmap for extent tree
        MOVE    0xA6(A2),D1                     | catalog tree refNum (VCBCTRef)
        LEA.L   0x26(A1,D1.W),A0                | catalog tree extent record
        BSR     BMChk                           | BlkChk: verify bitmap for catalog tree
| scan entire catalog to recount files and directories
        MOVEQ.L #0x2,D0                         | root DirID
        SUBA.L  A0,A0                           | no CName
        JSR     CMGetCN(PC)                     | locate root directory (positions B-tree)
        BNE     MTCHKERR                        | error ->
| calculate total number of catalog leaf records
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    0xA6(A2),D1                     | catalog refNum (VCBCTRef)
        MOVE.L  0xC(A1,D1.W),D0                 | catalog PEOF (FCBPLen)
        MOVEQ.L #0x46,D1                        | directory record size (lendir=70)
        BSR     DivUp                           | approximate record count
        MOVE.L  D0,D2                           | D2 = max records to scan
| initialize counters for consistency check
        MOVEQ.L #0xF,D4                         | D4 = max directory entries to verify (16-1)
        MOVEQ.L #0x0,D3                         | D3 = total file count
        MOVEQ.L #0x0,D5                         | D5 = root file count
        MOVEQ.L #0x0,D6                         | D6 = total directory count
        MOVEQ.L #0x0,D7                         | D7 = root directory count
| catalog scan loop: count files, directories, verify bitmaps
MOUNTVOL_SKIP_5:
        SUBQ.L  #0x1,D2                         | more records to scan?
        BLT     MTCHKERR                        | no, error (ran out of records) ->
        MOVE    0xA6(A2),D0                     | catalog refNum (VCBCTRef)
        MOVEQ.L #0x1,D1                         | selection = next record
        MOVE.L  D2,-(A6)                        | save remaining count
        JSR     P_mBTGetRecord(PC)              | get next catalog record
        MOVE.L  (A6)+,D2                        | restore remaining count
        TST     D0                              | any error?
        BNE.B   MOUNTVOL_OK_4                   | yes (end of catalog?) ->
| check record type: directory or file?
        CMPI.B  #0x1,(A1)                       | directory record? (cdrDirRec)
        BNE.B   MOUNTVOL_NO_10                  | no, check if file ->
        ADDQ.L  #0x1,D6                         | bump total directory count
        CMPI.L  #0x2,0x2(A0)                    | in root directory? (ckrParID == FSRtDirID)

        BNE.B   MOUNTVOL_NO_9                   | no ->
        SWAP    D7                              | bump root directory count (high word)
        ADDQ.W  #0x1,D7                         | increment root dir count
        SWAP    D7                              | restore file count in low word
MOUNTVOL_NO_9:
        CMP.L   0x6(A1),D4                      | track max next CNID (dirDirID)
        BCC.B   MOUNTVOL_SKIP_5                 | no update needed ->
        MOVE.L  0x6(A1),D4                      | update max CNID
        BRA.B   MOUNTVOL_SKIP_5                 | continue scan
| file record
MOUNTVOL_NO_10:
        CMPI.B  #0x2,(A1)                       | file record? (cdrFilRec)
        BNE.B   MOUNTVOL_SKIP_5                 | no (thread record), skip ->
        ADDQ.L  #0x1,D5                         | bump total file count
        CMPI.L  #0x2,0x2(A0)                    | in root directory? (ckrParID)

        BNE.B   MOUNTVOL_NO_11                  | no ->
        ADDQ.W  #0x1,D7                         | bump root file count (low word)
MOUNTVOL_NO_11:
        CMP.L   0x14(A1),D4                     | track max file number (filFlNum)
        BCC.B   MOUNTVOL_NO_12                  | no update needed ->
        MOVE.L  0x14(A1),D4                     | update max CNID
MOUNTVOL_NO_12:
| verify bitmap for file's extents
        LEA.L   0x4A(A1),A0                     | data fork extent record (filExtRec)
        BSR     BMChk                           | BlkChk: verify bitmap
        LEA.L   0x56(A1),A0                     | rsrc fork extent record (filRExtRec)
        BSR     BMChk                           | BlkChk: verify bitmap
        BRA.B   MOUNTVOL_SKIP_5                 | continue scan

| ----------------------------------------------------------
|
| MOUNTVOL_OK_4
|
| scan complete (end of catalog): update VCB counters
MOUNTVOL_OK_4:
        CMPI    #0x20,D0                        | result = 'not found'? (BTnotfound = end of catalog)
        BNE     MTCHKERR                        | no, some other error ->
| fix up VCBNxtCNID if needed
        CMP.L   vcbNxtCNID(A2),D4               | max CNID seen >= VCBNxtCNID?
        BCS.B   MOUNTVOL_OK_5                   | no, VCBNxtCNID is ok ->
        ADDQ.L  #0x1,D4                         | max + 1 = new next CNID
        MOVE.L  D4,vcbNxtCNID(A2)               | update VCBNxtCNID
        BSET    #0x0,0x13(A2)                   | mark VCB dirty (VCBAtrb consistency)
        MOVEQ.L #-0x1,D3                        | flag: something changed
| compare counted values against VCB
MOUNTVOL_OK_5:
        CMP.L   vcbFilCnt(A2),D5                | file count matches?
        BEQ.B   MOUNTVOL_OK_6                   | yes ->
        MOVE.L  D5,vcbFilCnt(A2)                | no, fix VCBFilCnt
        BSET    #0x1,0x13(A2)                   | mark dirty
        MOVEQ.L #-0x1,D3                        | something changed
MOUNTVOL_OK_6:
        CMP.L   vcbDirCnt(A2),D6                | directory count matches?
        BEQ.B   MOUNTVOL_OK_7                   | yes ->
        MOVE.L  D6,vcbDirCnt(A2)                | no, fix VCBDirCnt
        BSET    #0x1,0x13(A2)                   | mark dirty
        MOVEQ.L #-0x1,D3                        | flag: VCB was modified
MOUNTVOL_OK_7:
        CMP     vcbNmFls(A2),D7                 | root file count matches?
        BEQ.B   MOUNTVOL_OK_8                   | yes ->
        MOVE    D7,vcbNmFls(A2)                 | no, fix VCBNmFls
        BSET    #0x1,0x13(A2)                   | mark dirty
        MOVEQ.L #-0x1,D3                        | flag: VCB was modified
MOUNTVOL_OK_8:
        SWAP    D7                              | root dir count in low word
        CMP     vcbNmRtDirs(A2),D7              | root directory count matches?
        BEQ.B   MOUNTVOL_OK_9                   | yes ->
        MOVE    D7,vcbNmRtDirs(A2)              | no, fix VCBNmRtDirs
        BSET    #0x1,0x13(A2)                   | mark dirty
        MOVEQ.L #-0x1,D3                        | flag: VCB was modified
| now scan extent overflow file to verify those bitmaps too
MOUNTVOL_OK_9:
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    0xA4(A2),D1                     | extent tree refNum (VCBXTRef)
        MOVE.L  0xC(A1,D1.W),D0                 | extent PEOF (FCBPLen)
        MOVEQ.L #0xC,D1                         | extent record size (lenxdr=12)
        BSR     DivUp                           | approximate extent record count
        MOVE.L  D0,D5                           | D5 = max extent records to scan
| position to start of extent file
        MOVE    0xA4(A2),D0                     | extent tree refNum
        SUBQ.W  #0x8,A6                         | allocate key buffer on A6 stack
        MOVE.L  A6,A0                           | A0 = key buffer
        MOVE    #0x700,(A0)                     | key length = 7 (lenxkr-1)
        CLR.L   0x2(A0)                         | file number = 0 (search from start)
        CLR     0x6(A0)                         | FABN = 0
        MOVEQ.L #0x0,D2                         | no hint
        JSR     P_mBTSearch(PC)                 | position at start of extent file
        ADDQ.W  #0x8,A6                         | deallocate key buffer
        MOVEQ.L #0x0,D1                         | selection = current record
| extent file scan loop
MOUNTVOL_CONT_11:
        SUBQ.L  #0x1,D5                         | more records?
        BLT     MTCHKERR                        | no, error ->
        MOVE    0xA4(A2),D0                     | extent tree refNum
        JSR     P_mBTGetRecord(PC)              | get next extent record
        BNE.B   MOUNTVOL_CONT_12                | end of file? ->
        MOVE.L  A1,A0                           | A0 = extent record (for BlkChk)
        BSR.B   BMChk                           | verify bitmap for these extents
        MOVEQ.L #0x1,D1                         | selection = next record
        BRA.B   MOUNTVOL_CONT_11                | continue scan
| extent scan done: recount free blocks and finish
MOUNTVOL_CONT_12:
        CMPI    #0x20,D0                        | end of extent file? (BTnotfound)
        BNE     MTCHKERR                        | no, error ->
        JSR     UpdateFree(PC)                  | recount free blocks from bitmap
        BRA     CHECKREMOUNT                    | go to CheckRemount

| ----------------------------------------------------------
|
| BM Chk
|
| BMChk: wrapper for BlkChk that checks write-protect first
BMChk:
        MOVE.L  (SP)+,-(A6)                     | save return address
        BSR     SETVOLINFO_HFS_CONT_3           | check volume write protect
        BNE.B   BMCHK_SKIP                      | write protected, skip ->
        JSR     BlkChk(PC)                      | verify bitmap for extent record
        BEQ.B   BMCHK_SKIP                      | all ok ->
        MOVEQ.L #-0x1,D3                        | flag: bitmap inconsistency found
        BSET    #0x2,0x13(A2)                   | mark VCB bitmap dirty
BMCHK_SKIP:
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | return from bitmap check

| ----------------------------------------------------------
|
| BMCHK_CONT - close extent and catalog B-tree FCBs (mark as free)
|
BMCHK_CONT:
        MOVEM.L D0-D1/A1,-(SP)                  | save regs
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    0xA4(A2),D1                     | extent tree refNum (VCBXTRef)
        BEQ.B   BMCHK_EMPTY                     | none ->
        CLR.L   0x0(A1,D1.W)                    | mark FCB as free (FCBFlNm=0)
BMCHK_EMPTY:
        MOVE    0xA6(A2),D1                     | catalog tree refNum (VCBCTRef)
        BEQ.B   BMCHK_EMPTY_2                   | none ->
        CLR.L   0x0(A1,D1.W)                    | mark FCB as free
BMCHK_EMPTY_2:
        MOVEM.L (SP)+,D0-D1/A1                  | restore regs
        RTS                                     | return after freeing FCBs

| ----------------------------------------------------------
|
| BMCHK_CONT_2 - dequeue and dispose VCB, close all open FCBs for this volume
|
BMCHK_CONT_2:
        MOVE.L  D0,-(SP)                        | save error code
        BSR     CREATE_CONT_12                  | Gt1stMatch: find first FCB for this volume
BMCHK_CONT_3:
        BNE.B   BMCHK_NO                        | no more FCBs ->
        CLR.L   0x0(A1,D1.W)                    | mark FCB as free (FCBFlNm=0)
        CLR.L   0x4(A1,D1.W)                    | clear FCB flags
        BSR     CREATE_NEXT_2                   | GtNxtMatch: find next FCB
        BRA.B   BMCHK_CONT_3                    | keep closing
BMCHK_NO:
        MOVE.L  A2,A0                           | VCB to dequeue
        LEA.L   (VCBQHdr_Flags).w,A1            | VCB queue header
        JSR     Dequeue(PC)                     | remove from VCB queue
        CMPA.L  (DefVCBPtr).w,A2                | was this the default VCB?
        BNE.B   BMCHK_NO_2                      | no ->
        CLR.L   (DefVCBPtr).w                   | clear default VCB pointer
        CLR     (DefVRefNum).w                  | clear default VRefNum
BMCHK_NO_2:
        _DisposePtr                             | free VCB memory
        MOVE.L  (SP)+,D0                        | restore error code
        RTS                                     | return with error code preserved

| ----------------------------------------------------------
|
| BMCHK_CONT_4 - trash all cached blocks for the volume being unmounted
|
BMCHK_CONT_4:
        MOVE.L  A1,-(SP)                        | save A1
        MOVE.L  (SysBMCPtr).w,A1                | bitmap cache
        JSR     P_mTrashVBlks(PC)               | trash bitmap blocks for this volume
        MOVE.L  (SysVolCPtr).w,A1               | volume cache
        JSR     P_mTrashVBlks(PC)               | trash volume blocks
        MOVE.L  (SysCtlCPtr).w,A1               | control cache
        JSR     P_mTrashVBlks(PC)               | trash control blocks
        MOVE.L  (SP)+,A1                        | restore A1
        RTS                                     | return after trashing volume caches

| ----------------------------------------------------------
|
| BMCHK_CONT_5 - FindFCB: find a free FCB entry
|
BMCHK_CONT_5:
        BSR     HFSE_CONT_14                    | Gt1stFCB: get first FCB
        BRA.B   BMCHK_NEXT                      | ->
BMCHK_CONT_6:
        TST.L   0x0(A1,D1.W)                    | FCB unused? (FCBFlNm=0)
        BNE.B   BMCHK_NEXT                      | no, try next ->
        MOVEQ.L #-0x1,D0                        | mark as temporarily reserved
        MOVE.L  D0,0x0(A1,D1.W)                 | (FCBFlNm = -1)
        MOVEQ.L #0x0,D0                         | success
        BRA.B   BMCHK_CONT_7                    | ->
BMCHK_NEXT:
        BSR     HFSE_NEXT                       | GtNxtFCB: get next FCB
        BCS.B   BMCHK_CONT_6                    | more FCBs ->
        MOVEQ.L #-0x2A,D0                       | TMFOErr: too many files open
BMCHK_CONT_7:
        RTS                                     | return with FCB offset or TMFOErr

| ----------------------------------------------------------
|
| BMCHK_CONT_8 - AccessBT: set up access to a B*-Tree file
| D0=refnum, D1=file ID, D2=clump size, A1=cache, A3=key compare routine
|
BMCHK_CONT_8:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D3/A0,-(A6)                     | save regs
        MOVE.L  (FCBSPtr).w,A0                  | FCB array
        LEA.L   0x0(A0,D0.W),A0                 | point to FCB entry
        CLR     0x4(A0)                         | clear FCB flags
        CLR     0x6(A0)                         | clear start block
        CLR.L   ioResult(A0)                    | clear current position
        MOVE.L  D1,(A0)                         | set file number (FCBFlNm)
        MOVE.L  A2,0x14(A0)                     | set VCB pointer (FCBVPtr)
        MOVE.L  D2,ioFlAttrib(A0)               | set clump size (FCBClmpSize)
        MOVE.L  A3,A0                           | key compare routine
        JSR     P_mBTOpen(PC)                   | BTOpen: open the B*-Tree file
        MOVEM.L (A6)+,D3/A0                     | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit AccessBT

| ----------------------------------------------------------
|
| Find Drive
|
| Called during boot.
| FindDrive: find drive queue entry for drive number D2
| Returns: D1=driver refnum, A3=drive queue entry, D0=0 or error
FindDrive:
        MOVE.L  A0,-(SP)                        | save A0
        MOVE    D2,D0                           | D0 = drive number for search
        LEA.L   (DrvQHdr_Flags).w,A0            | drive queue header
        MOVEQ.L #0x6,D1                         | offset to dQDrive field in DQE
        BSR     QueueSearch                     | search queue for matching drive
        BNE.B   FINDDRIVE_FOUND                 | not found ->
        MOVE.L  A0,A3                           | A3 = drive queue entry
        MOVE    0x8(A0),D1                      | D1 = driver refnum (dQRefNum)
        MOVE    0xA(A0),D0                      | D0 = FSID (dQFSID)
        BEQ.B   FINDDRIVE_EMPTY                 | zero: native FS ->
        MOVEQ.L #-0x3A,D0                       | ExtFSErr: external FS
FINDDRIVE_EMPTY:
        MOVE.L  (SP)+,A0                        | restore A0
        RTS                                     | return FSID or ExtFSErr
FINDDRIVE_FOUND:
        MOVEQ.L #-0x38,D0                       | NSDrvErr: no such drive
        BRA.B   FINDDRIVE_EMPTY                 | ->

| ----------------------------------------------------------
|
| _OffLine ($A035)
|
| _OffLine ($A035): take volume offline (don't eject media)
Offline:
        ST.B    (NoEject).w                     | set flag: don't physically eject
        BRA     EJECT_CONT                      | share code with Eject

| ----------------------------------------------------------
|
| OFFLINE_CONT
|
| close B-tree files on the VCB (unmount path)
OFFLINE_CONT:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D2/A1,-(A6)                  | save regs
        CLR.B   (FlushOnly).w                   | close, not just flush
        BRA.B   OFFLINE_SKIP_2                  | ->

| ----------------------------------------------------------
|
| OFFLINE_CONT_2
|
| Called during boot.
| FlushVol/UnmountVol: flush or close all files on volume
OFFLINE_CONT_2:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D2/A1,-(A6)                  | save regs
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   OFFLINE_SKIP_2                  | no, skip B-tree flush ->
| flush TFS volume: set consistency bit, flush MDB and B-trees
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   OFFLINE_SKIP                    | yes, skip consistency bit ->
        BSR     SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   OFFLINE_SKIP                    | write protected ->
        BSET    #0x8,vcbAtrb(A2)                | set VCBAtVOK: volume is now consistent
        BSR     SetVCBDirty                     | MarkVCBDirty
OFFLINE_SKIP:
        JSR     FlushMDB(PC)                    | flush master directory block
| flush/close catalog B-tree
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    0xA6(A2),D1                     | catalog tree refNum (VCBCTRef)
        BSR     FILECLOSE_CONT_3                | FClose: flush/close catalog file
        BNE.B   OFFLINE_ERR                     | error ->
        TST.B   (FlushOnly).w                   | close (not just flush)?
        BNE.B   OFFLINE_CONT_3                  | just flush ->
        CLR     0xA6(A2)                        | clear VCBCTRef (catalog closed)
OFFLINE_CONT_3:
| flush/close extent B-tree
        MOVE    0xA4(A2),D1                     | extent tree refNum (VCBXTRef)
        BSR     FILECLOSE_CONT_3                | FClose: flush/close extent file
        BNE.B   OFFLINE_ERR                     | error ->
        TST.B   (FlushOnly).w                   | close?
        BNE.B   OFFLINE_SKIP_2                  | just flush ->
        CLR     0xA6(A2)                        | clear VCBXTRef
| flush all volume caches
OFFLINE_SKIP_2:
        MOVEQ.L #0x0,D1                         | no FlushCache options
        ST.B    (SysCRefCnt).w                  | force cache flush (CacheFlag)
        MOVE.L  (SysBMCPtr).w,A1                | bitmap cache
        MOVE    vcbVRefNum(A2),D0               | volume refnum
        JSR     P_mFlushCache(PC)               | flush bitmap cache
        MOVE.L  (SysCtlCPtr).w,A1               | control cache
        MOVE    vcbVRefNum(A2),D0               | volume refnum
        JSR     P_mFlushCache(PC)               | flush control cache
        MOVE.L  (SysVolCPtr).w,A1               | volume cache
        MOVE    vcbVRefNum(A2),D0               | volume refnum
        JSR     P_mFlushCache(PC)               | flush volume cache
| if unmounting, trash all cached blocks
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   OFFLINE_OK                      | yes, keep cache ->
        BSR     BMCHK_CONT_4                    | trash all cached blocks for this volume
OFFLINE_OK:
        MOVEQ.L #0x0,D0                         | no error
OFFLINE_ERR:
        MOVEM.L (A6)+,D1-D2/A1                  | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | return with condition codes set

| ----------------------------------------------------------
|
| _Eject ($A017)
|
| _Eject ($A017)
Eject:
        CLR.B   (NoEject).w                     | assume real eject (not just offline)
EJECT_CONT:
        BSR     FSQUEUE_SETUP_SYNC              | FSQueue: wait our turn
        BSR     DTRMV3                          | DTRMV3: determine volume from param block
        BNE.B   EJECT_FOUND                     | volume not found, try by drive number ->
        BSR     CKExtFS                         | check for external file system
        BNE.B   EJECT_DONE                      | external FS, let it handle ->
        BRA.B   EJECT_FOUND_2                   | found volume, go eject/offline ->

| ----------------------------------------------------------
|
| EJECT_FOUND
|
EJECT_FOUND:
        MOVE    ioVRefNum(A0),D2                | D2 = drive number
EJECT_CONT_2:
        BSR     FindDrive                       | find drive queue entry
        BNE.B   EJECT_DONE                      | not found ->
        TST.B   (NoEject).w                     | offline only (no eject)?
        BEQ     EJECT_NO_3                      | no: send eject control call ->
EJECT_DONE:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| EJECT_FOUND_2
|
| volume found: get drive number from VCB
EJECT_FOUND_2:
        LEA.L   vcbDrvNum(A2),A1                | ptr to VCB drive number
        MOVE    (A1),D2                         | D2 = drive number (VCBDrvNum)
        BNE.B   EJECT_OK                        | volume is online ->
        MOVE    0x2(A1),D2                      | get saved drive number (VCBDRefNum)
        BPL.B   EJECT_DONE                      | positive: already offline, done ->
        TST.B   (NoEject).w                     | offline only?
        BNE.B   EJECT_DONE                      | yes, already offline ->
        NEG     D2                              | make drive number positive
        NEG     0x2(A1)                         | mark as needing re-eject
        BRA.B   EJECT_CONT_2                    | send eject to driver ->

| ----------------------------------------------------------
|
| EJECT_OK
|
| volume is online: check drive type and flush
EJECT_OK:
        BSR     FindDrive                       | find the drive queue entry
        BNE.B   EJECT_DONE                      | not found ->
| determine eject behavior based on drive type
        TST.B   (NoEject).w                     | already set to offline?
        BNE.B   EJECT_OK_2                      | yes ->
        CMPI.B  #0x8,-0x3(A3)                   | drive type >= 8? (SCSI or HD20)
        BLT.B   EJECT_OK_2                      | no, normal floppy ->
        ST.B    (NoEject).w                     | SCSI: offline only (can't eject)
        CMPI.B  #0x40,-0x3(A3)                  | drive type >= 64? (manual eject)
        BLT.B   EJECT_OK_2                      | no ->
        MOVE.B  #0x1,(NoEject).w                | manual eject: set to 1 (positive)
| flush all open files for this volume
EJECT_OK_2:
        ST.B    (FlushOnly).w                   | flush only (not close) first
        BSR.B   UNMOUNTVOL_CONT                 | flush/close all user files
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   EJECT_NO                        | no, MFS ->
        CLR.B   (FlushOnly).w                   | close (not just flush) for unmount
        BSR     OFFLINE_CONT_2                  | flush/close B-trees and caches
        BRA.B   EJECT_CONT_3                    | ->
| MFS flush/offline
EJECT_NO:
        BSR     HFSE_CONT_9                     | MFS flush
        BSR     HFSE_CONT_2                     | MFS directory flush
        BSR     BMCHK_CONT_4                    | trash all cached blocks
| mark volume as offline
EJECT_CONT_3:
        CLR     (A1)+                           | clear VCBDrvNum (volume offline)
        TST.B   (NoEject).w                     | offline only?
        BEQ.B   EJECT_NO_2                      | no: real eject ->
        NEG     D2                              | negate drive number (flag as offline)
EJECT_NO_2:
        MOVE    D2,(A1)+                        | save negated drive number in VCBDRefNum
| if offline only, dequeue and re-enqueue VCB (move to end of queue)
        TST.B   (NoEject).w                     | offline only?
        BEQ.B   EJECT_NO_3                      | no: eject ->
        MOVE.L  A2,A0                           | VCB to move
        LEA.L   (VCBQHdr_Flags).w,A1            | VCB queue header
        JSR     Dequeue(PC)                     | remove from current position
        JSR     Enqueue(PC)                     | add back at end
        TST.B   (NoEject).w                     | check NoEject sign
        BMI     EJECT_DONE                      | negative: done (SCSI offline) ->
| EJECT_NO_3: send eject/offline control call to disk driver
EJECT_NO_3:
        LEA.L   (Params).w,A0                   | I/O param block
        LEA.L   ioVRefNum(A0),A1                | ptr to drive number field
        MOVE    D2,(A1)+                        | drive number
        MOVE    D1,(A1)+                        | driver refnum
        MOVE    #0x7,(A1)                       | csCode = 7 (eject)
        LEA.L   FSQUEUE_DONE(PC),A1             | completion routine = CmdDone
        MOVE.L  A1,ioCompletion(A0)             | set I/O completion address
        _ControlAsync                           | send async eject control call
        RTS                                     | return while async eject completes

| ----------------------------------------------------------
|
| _UnmountVol ($A00E)
|
| _UnmountVol ($A00E)
UnmountVol:
        BSR     FSQUEUE_SETUP_SYNC              | FSQueue: wait our turn
        CLR.B   (FlushOnly).w                   | close, not just flush
        BRA.B   FLUSHVOL_CONT                   | ->

| ----------------------------------------------------------
|
| UNMOUNTVOL_CONT
|
| Called during boot.
| UNMOUNTVOL_CONT: flush/close all open user files for this volume
UNMOUNTVOL_CONT:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D7/A0-A5,-(A6)               | save regs
        BSR     HFSE_CONT_14                    | Gt1stFCB: get first FCB
UNMOUNTVOL_CONT_2:
        TST.L   0x0(A1,D1.W)                    | FCB in use? (FCBFlNm)
        BEQ.B   UNMOUNTVOL_SKIP                 | no, skip ->
        CMPA.L  0x14(A1,D1.W),A2                | same volume? (FCBVPtr)
        BNE.B   UNMOUNTVOL_SKIP                 | no, skip ->
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   UNMOUNTVOL_NO                   | no, flush MFS file ->
        CMPI.L  #0x10,0x0(A1,D1.W)              | system file? (CNID < 16)

        BCS.B   UNMOUNTVOL_SKIP                 | yes, skip (system files handled separately)
UNMOUNTVOL_NO:
        BSR     FILECLOSE_CONT_3                | FClose: flush/close this file
        BNE.B   UNMOUNTVOL_ERR                  | error ->
UNMOUNTVOL_SKIP:
        BSR     HFSE_NEXT                       | GtNxtFCB: get next FCB
        BCS.B   UNMOUNTVOL_CONT_2               | more FCBs ->
        MOVEQ.L #0x0,D0                         | no error
UNMOUNTVOL_ERR:
        MOVEM.L (A6)+,D1-D7/A0-A5               | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | return with condition codes set

| ----------------------------------------------------------
|
| _FlushVol ($A013)
|
| Called during boot.
FlushVol:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST.B    (FlushOnly).w                   | indicate flush only
| common entry for FlushVol/UnmountVol
FLUSHVOL_CONT:
        BSR.B   DTRMV3                          | DTRMV: determine volume from param block
        BNE.B   FLUSHVOL_ERR                    | error ->
        BSR.B   CKExtFS                         | check for external file system
        BNE.B   FLUSHVOL_ERR                    | external FS handled it ->
        BSR.B   UNMOUNTVOL_CONT                 | flush/close all open user files
        BNE.B   FLUSHVOL_ERR                    | error ->
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   FLUSHVOL_OK                     | yes ->
        BSR     HFSE_CONT_9                     | MFS flush/unmount
        BRA.B   FLUSHVOL_ERR                    | ->

| ----------------------------------------------------------
|
| FLUSHVOL_OK
|
| TFS FlushVol/UnmountVol path
FLUSHVOL_OK:
        TST     vcbDrvNum(A2)                   | volume online?
        BEQ.B   FLUSHVOL_SKIP                   | no (offline), skip flush ->
        BSR     OFFLINE_CONT_2                  | flush/close B-trees and caches
        BNE.B   FLUSHVOL_ERR                    | error ->
FLUSHVOL_SKIP:
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FLUSHVOL_DONE                   | yes, done ->
        BSR     BMCHK_CONT_2                    | dequeue and dispose VCB
FLUSHVOL_DONE:
        MOVEQ.L #0x0,D0                         | no error
FLUSHVOL_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| CKExtFS: check for external file system
|
| Called during boot.
CKExtFS:
        MOVE    vcbFSID(A2),D0                  | external FS ID? (VCBFSId)
        BEQ.B   CKEXTFS_NO                      | no, native FS ->
        MOVEQ.L #-0x3A,D0                       | ExtFSErr: external FS
CKEXTFS_NO:
        RTS                                     | return ExtFSErr if external FS

| ----------------------------------------------------------
|
| DTRMV3: determine volume from param block (with filename check)
|
| Called during boot.
DTRMV3:
        MOVE.L  ioFileName(A0),D2               | filename pointer
        MOVE.L  D2,A4                           | A4 = filename
        BEQ.B   P_DTRMV1                        | no filename, use VRefNum ->
        TST.B   (A4)                            | filename empty?
        BNE     DTRMV1_NO_4                     | no, parse pathname ->
| P_DTRMV1 -- dTRMV1: determine volume.
| Called by: SetVolInfo_hfs, GETWDINFO_HFS_CONT, hfsD, hfsE, GETFILEINFO_CONT_2 (and 1 more)
P_DTRMV1:
        MOVE.L  (0x778).w,-(SP)                 | HFS vector: DTRMV1
        RTS                                     | return from P_DTRMV1

| ----------------------------------------------------------
|
| DTRMV1
|
| Called during boot.
| DTRMV1: determine volume from ioVRefNum (no filename)
DTRMV1:
        MOVEQ.L #0x0,D3                         | D3 = 0 (no directory ID)
        SUBA.L  A3,A3                           | A3 = nil (no CName)
        MOVE    ioVRefNum(A0),D0                | get volume reference
        BEQ.B   DTRMV1_EMPTY                    | zero: use default volume ->
        BMI.B   DTRMV1_CONT                     | negative: VRefNum or WDCB ->
        BSR     FindVCBDrv                      | positive: drive number, find VCB
        BRA.B   DTRMV1_CONT_2                   | ->
| negative reference: VRefNum or WDCB
DTRMV1_CONT:
        CMPI    #-0x1000,D0                     | WD reference? (< -4096)
        BLE.B   DTRMV1_OK                       | yes ->
        BSR     GetVCBRFN                       | find VCB by VRefNum
        BRA.B   DTRMV1_CONT_2                   | ->
| working directory reference
DTRMV1_OK:
        BSR     ResolveWDVCB                    | find VCB from WD reference
DTRMV1_CONT_2:
        BEQ.B   DTRMV1_FOUND                    | found it ->
DTRMV1_NO:
        MOVEQ.L #-0x23,D0                       | NSVErr: no such volume
        RTS                                     | return with NSVErr

| ----------------------------------------------------------
|
| DTRMV1_EMPTY
|
| Called during boot.
| use default volume
DTRMV1_EMPTY:
        MOVE.L  (DefVCBPtr).w,D0                | get default VCB
        BEQ.B   DTRMV1_NO                       | no default, NSVErr ->
        MOVE.L  D0,A2                           | A2 = default VCB
        MOVE.L  (WDCBsPtr).w,A3                 | get default WDCB
        ADDQ.L  #0x2,A3                         | skip WDCB header
DTRMV1_FOUND:
        MOVEQ.L #0x0,D0                         | no error
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        BTST    #0x6,(HFSFlags).w               | test flag
        BNE.B   DTRMV1_ERR                      | error ->
        BTST    #0x5,(HFSFlags).w               | test flag
        BEQ.B   DTRMV1_OK_2                     | ok ->
DTRMV1_ERR:
        MOVE.L  A4,-(SP)                        | save A4
        MOVE.L  (PMSPPtr).w,A4                  | A4 = PMSP table pointer
        ADDQ.L  #0x2,A4                         | skip PMSP header
        MOVEQ.L #0x17,D0                        | D0 = 23: clear 24 words of the PMSP table
DTRMV1_LOOP:
        CLR     (A4)+                           | clear
        DBF     D0,DTRMV1_LOOP                  | loop
        MOVE.L  (SP)+,A4                        | restore A4
DTRMV1_ERR_2:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from DTRMV1_ERR_2

| ----------------------------------------------------------
|
| DTRMV1_OK_2
|
| Called during boot.
DTRMV1_OK_2:
        BTst    #0x9,0x6(A0)                    | test flag
        BEQ.B   DTRMV1_OK_3                     | ok ->
        TST.L   ioFFlNum(A0)                    | test
        BNE.B   DTRMV1_ERR_2                    | error ->
| DTRMV1_OK_3: HFS InitFS - build param block table for PMSP (Param Manager)
DTRMV1_OK_3:
        MOVEM.L D2/D4/A1/A4,-(SP)               | save regs
        MOVE.L  (PMSPPtr).w,A4                  | PMSP table base
        MOVE    -0x2(A4),D4                     | check if table already built
        BGT.B   DTRMV1_OK_4                     | yes, already initialized ->
| first call: build PMSP table from current volume/directory
        MOVEQ.L #0x2,D4                         | start at offset 2
        MOVE    vcbVRefNum(A2),D2               | volume refnum
        MOVE.L  A3,D0                           | have a WDCB?
        BEQ.B   DTRMV1_NO_2                     | no ->
        MOVE.L  0x4(A3),D0                      | get DirID from WDCB
        BRA.B   DTRMV1_CONT_3                   | ->
| no WDCB: use root directory
DTRMV1_NO_2:
        MOVEQ.L #0x2,D0                         | root DirID (FSRtDirID)
| DTRMV1_CONT_3: HFS InitFS patch table processing (build param block entries)
DTRMV1_CONT_3:
        BSR.B   DTRMV1_CONT_4                   | add volume refnum to table
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   DTRMV1_NO_3                     | no ->
| check if boot volume has a default directory
        MOVE    (BootDrive).w,D0                | boot drive VRefNum
        BGE.B   DTRMV1_ERR_3                    | positive (drive number), skip ->
        CMPI    #-0x1000,D0                     | WD reference?
        BGT.B   DTRMV1_ERR_3                    | no, plain VRefNum ->
        BSR     ResolveWDVCB                    | look up WD to get VCB
        BNE.B   DTRMV1_ERR_3                    | error ->
        CMP     vcbVRefNum(A2),D2               | boot volume matches this VCB?
        BNE.B   DTRMV1_ERR_3                    | no ->
        MOVE.L  0x4(A3),D0                      | boot WD's DirID
        BSR.B   DTRMV1_CONT_4                   | add boot DirID to table
DTRMV1_ERR_3:
        MOVE.L  (ReqstVol).w,A2                 | restore volume ptr
        MOVE.L  vcbFndrInfo(A2),D0              | Finder info from VCB
        BEQ.B   DTRMV1_NO_3                     | no Finder info ->
        BSR.B   DTRMV1_CONT_4                   | add Finder info to table
| terminate the param block table
DTRMV1_NO_3:
        CLR     0x0(A4,D4.W)                    | null terminator
        MOVEQ.L #0x2,D4                         | reset to first entry
        MOVE    D4,-0x2(A4)                     | set entry count
| call the dispatch vector if set
        MOVE.L  -0x6(A4),D0                     | get dispatch vector
        BEQ.B   DTRMV1_OK_4                     | no vector ->
        MOVE.L  D0,A1                           | call the vector
        JSR     (A1)                            | call PMSP hook routine
| set up default WDCB from result
DTRMV1_OK_4:
        MOVE    0x0(A4,D4.W),D0                 | get VRefNum from result
        BSR     GetVCBRFN                       | find VCB by VRefNum
        BNE.B   DTRMV1_FOUND_2                  | not found ->
        MOVE.L  (WDCBsPtr).w,A3                 | WDCB array
        ADDA    #0x12,A3                        | point to secondary WDCB
        MOVE.L  A2,(A3)                         | WDVCBPtr = found VCB
        MOVE.L  0x2(A4,D4.W),0x4(A3)            | WDDirID from result
        CLR.L   WDCatHint(A3)                   | WDCatHint = 0
        CLR.L   0xC(A3)                         | WDProcID = 0
        MOVEQ.L #0x0,D0                         | no error
DTRMV1_FOUND_2:
        MOVEM.L (SP)+,D2/D4/A1/A4               | restore regs
        RTS                                     | return with success

| ----------------------------------------------------------
|
| DTRMV1_CONT_4
|
| Called during boot.
DTRMV1_CONT_4:
        MOVE.L  D4,-(SP)                        | save search index
        MOVEQ.L #0x2,D4                         | D4 = 2: offset of the first PMSP entry
DTRMV1_CONT_5:
        CMP.L   (SP),D4                         | compare
        BCC.B   DTRMV1_CONT_6                   | unsigned greater or equal ->
        CMP     0x0(A4,D4.W),D2                 | compare
        BNE.B   DTRMV1_ERR_4                    | error ->
        CMP.L   0x2(A4,D4.W),D0                 | compare
        BEQ.B   DTRMV1_OK_5                     | ok ->
DTRMV1_ERR_4:
        ADDQ.W  #0x6,D4                         | advance to next PMSP entry
        CMP     (A4),D4                         | compare
        BCS.B   DTRMV1_CONT_5                   | unsigned less ->
DTRMV1_OK_5:
        MOVEQ.L #0x0,D0                         | noErr
DTRMV1_CONT_6:
        MOVE.L  (SP)+,D4                        | restore search index
        TST.L   D0                              | test
        BEQ.B   DTRMV1_OK_6                     | ok ->
        MOVE    D2,0x0(A4,D4.W)                 | store VRefNum in PMSP entry
        MOVE.L  D0,0x2(A4,D4.W)                 | store DirID in PMSP entry
        ADDQ.W  #0x6,D4                         | advance PMSP index
DTRMV1_OK_6:
        RTS                                     | return from DTRMV1_OK_6

| ----------------------------------------------------------
|
| DTRMV1_NO_4
|
| Called during boot.
DTRMV1_NO_4:
        MOVE.L  ioFileName(A0),D2               | IOParam field
| DTRMV1_CONT_7: parse pathname into volume name and file name components
| D2 = ptr to pathname string, returns A4=filename, D2=name length, A3=vol prefix
DTRMV1_CONT_7:
        MOVEM.L D4-D6/A0-A1,-(SP)               | save regs
        TST.L   D2                              | pathname given?
        BEQ.B   DTRMV1_EMPTY_2                  | no ->
        MOVE.L  D2,A4                           | A4 = pathname string
        MOVEQ.L #0x0,D2                         | clear high bytes
        MOVE.L  D2,A3                           | A3 = nil (no volume prefix)
        MOVE.B  (A4)+,D2                        | D2 = pathname length
        BEQ.B   DTRMV1_EMPTY_2                  | empty string ->
| scan for colon separator
        MOVEQ.L #0x0,D3                         | D3 = scan index
DTRMV1_NO_5:
        MOVE.B  0x0(A4,D3.W),D4                 | get next character
        CMPI.B  #0x3A,D4                        | colon? (':')
        BEQ.B   DTRMV1_FOUND_3                  | yes, found separator ->
        ADDQ.W  #0x1,D3                         | advance
        CMP     D3,D2                           | past end?
        BNE.B   DTRMV1_NO_5                     | no, keep scanning
        BRA.B   DTRMV1_FOUND_4                  | no colon found ->

| ----------------------------------------------------------
|
| DTRMV1_FOUND_3
|
DTRMV1_FOUND_3:
        SUB.L   D3,D2                           | D2 = remaining name length
        SUBQ.W  #0x1,D2                         | exclude the colon
        MOVE.L  A4,A1                           | A1 = parsed name ptr
        ADDA.L  D3,A4                           | skip past volume prefix
        ADDA.L  #0x1,A4                         | skip past colon separator
        TST     D3                              | test
        BGT.B   DTRMV1_OK_7                     | yes ->
DTRMV1_FOUND_4:
        BSR     P_DTRMV1                        | call helper
DTRMV1_CONT_8:
        MOVEM.L (SP)+,D4-D6/A0-A1               | restore regs
        TST     D0                              | test
        RTS                                     | return from DTRMV1_CONT_8

| ----------------------------------------------------------
|
| DTRMV1_EMPTY_2
|
DTRMV1_EMPTY_2:
        MOVEQ.L #-0x25,D0                       | bdNamErr (-37): bad file name
        BRA.B   DTRMV1_CONT_8                   | ->

| ----------------------------------------------------------
|
| DTRMV1_OK_7
|
| scan VCB queue for volume by name
DTRMV1_OK_7:
        MOVE.L  (VCBQHdr_Head).w,D0             | start of VCB queue
DTRMV1_CONT_9:
        BEQ.B   DTRMV1_CONT_10                  | end of queue ->
        MOVE.L  D0,A2                           | A2 = this VCB
        LEA.L   vcbVN(A2),A0                    | volume name
        MOVEQ.L #0x0,D0                         | VCB name length (high word)
        MOVE.B  (A0)+,D0                        | get VCB name length byte
        SWAP    D0                              | move to high word for CmpString
        MOVE    D3,D0                           | search name length (low word)
        _CmpString                              | compare names
        BNE.B   DTRMV1_FOUND_5                  | no match ->
        MOVE.L  A2,(ReqstVol).w                 | found it: set requested volume
        BRA.B   DTRMV1_CONT_8                   | ->
DTRMV1_FOUND_5:
        MOVE.L  (A2),D0                         | next VCB (qLink)
        BNE.B   DTRMV1_CONT_9                   | keep scanning
DTRMV1_CONT_10:
        MOVEQ.L #-0x23,D0                       | NSVErr: no such volume
        BRA.B   DTRMV1_CONT_8                   | ->

| ----------------------------------------------------------
|
| hfs C
|
| hfsC: _HSetFLock / _SetFLock HFS dispatch (set HFS flags)
hfsC:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.L  0x1C(A0),D0                     | get ioMisc parameter
        BMI.B   HFSC_SKIP                       | negative: don't update PMSP ->
        MOVE.L  (PMSPPtr).w,A1                  | update PMSP dispatch vector
        MOVE.L  D0,-0x6(A1)                     | store hook address at PMSPHook
HFSC_SKIP:
        MOVE    0x1A(A0),D0                     | get ioVersNum/csCode
        BCLR    #0x6,(HFSFlags).w               | clear HFS bit 6 (ioDirFlg)
        BTST    #0x0,D0                         | bit 0 set?
        BNE.B   HFSC_OK                         | yes ->
        BSET    #0x6,(HFSFlags).w               | no: set HFS bit 6
HFSC_OK:
        MOVEQ.L #0x0,D0                         | no error
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| _GetVolInfo ($A007)
| A0 = paramBlock -> D0 = error; returns volume info
|
| Called during boot.
| _GetVolInfo ($A007): return volume information
GetVolInfo:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE    0x1C(A0),D2                     | D2 = volume index (ioVolIndex)
        BGT.B   GETVOLINFO_CONT_2               | positive: index into VCB queue ->
        BEQ.B   GETVOLINFO_EMPTY                | zero: use ioVRefNum ->
        BSR     DTRMV3                          | negative: determine volume from name
        BRA.B   GETVOLINFO_CONT                 | ->
| use ioVRefNum to find volume
GETVOLINFO_EMPTY:
        BSR     P_DTRMV1                        | DTRMV1: determine volume from VRefNum
GETVOLINFO_CONT:
        BNE     GETVOLINFO_ERR_2                | error ->
        BRA.B   GETVOLINFO_EXIT                 | go return volume info ->
| index into VCB queue
GETVOLINFO_CONT_2:
        MOVEQ.L #0x0,D3                         | clear volume index counter
        CLR     ioVRefNum(A0)                   | clear VRefNum
        MOVE.L  (VCBQHdr_Head).w,D1             | start of VCB queue
| scan VCB queue by index
GETVOLINFO_CONT_3:
        BEQ     GETVOL_NO                       | end of queue, NSVErr ->
        SUBQ.W  #0x1,D2                         | count down index
        MOVE.L  D1,A2                           | A2 = this VCB
        BEQ.B   GETVOLINFO_EXIT                 | found the Nth one ->
        MOVE.L  (A2),D1                         | next VCB (qLink)
        BRA.B   GETVOLINFO_CONT_3               | keep counting
| GETVOLINFO_EXIT: copy VCB info to param block
GETVOLINFO_EXIT:
        MOVEQ.L #0x20,D0                        | 17 words of VCB info (34 bytes)
GETVOLINFO_LOOP:
        MOVE    0xA(A2,D0.W),0x1E(A0,D0.W)      | copy VCB field to param block
        SUBQ.W  #0x2,D0                         | decrement word offset
        BPL.B   GETVOLINFO_LOOP                 | loop
| check if volume has open files (set ioVAtrb bit 6)
        BSET    #0x6,0x27(A0)                   | assume files are open
        BSR     HFSE_CONT_14                    | Gt1stFCB
GETVOLINFO_CONT_4:
        CMPA.L  0x14(A1,D1.W),A2                | FCB for this volume? (FCBVPtr)
        BNE.B   GETVOLINFO_NO                   | no ->
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   GETVOLINFO_FOUND                | no, MFS file found ->
        MOVE.L  0x0(A1,D1.W),D0                 | file number (FCBFlNm)
        CMPI.L  #0x10,D0                        | system file? (CNID < 16)
        BCC     GETVOLINFO_FOUND                | no, user file found ->
GETVOLINFO_NO:
        BSR     HFSE_NEXT                       | GtNxtFCB
        BCS.B   GETVOLINFO_CONT_4               | more FCBs ->
        BCLR    #0x6,0x27(A0)                   | no open files: clear bit
| check if this is the default volume
GETVOLINFO_FOUND:
        BClr    #0x5,0x27(A0)                   | clear default flag
        CMPA.L  (DefVCBPtr).w,A2                | is this the default VCB?
        BNE.B   GETVOLINFO_NO_2                 | no ->
        BSET    #0x5,0x27(A0)                   | set default flag
| determine WDCB for directory info
GETVOLINFO_NO_2:
        SUBA.L  A3,A3                           | A3 = nil (no WDCB)
        TST     0x1C(A0)                        | indexed? (ioVolIndex > 0)
        BGT.B   GETVOLINFO_SKIP                 | yes, skip WDCB lookup ->
        TST     D3                              | has directory context?
        BNE.B   GETVOLINFO_SKIP                 | yes ->
        MOVE    ioVRefNum(A0),D1                | get VRefNum
        BGT.B   GETVOLINFO_SKIP                 | positive (drive number) ->
        BLT.B   GETVOLINFO_CONT_5               | negative (VRefNum or WDCB) ->
        MOVEQ.L #0x2,D1                         | zero: use default WDCB
        BRA.B   GETVOLINFO_CONT_6               | ->
| check if it's a WD reference
GETVOLINFO_CONT_5:
        CMPI    #-0x1000,D1                     | WD reference? (< -4096)
        BGT.B   GETVOLINFO_SKIP                 | no, plain VRefNum ->
        SUBI    #-0x7FFF,D1                     | convert to WDCB offset
GETVOLINFO_CONT_6:
        MOVE.L  (WDCBsPtr).w,A3                 | WDCB array
        ADDA    D1,A3                           | point to WDCB
        BSR     FNDFILNAME_CONT_4               | CkExtFS
        BNE.B   GETVOLINFO_SKIP                 | external FS ->
| look up directory valence from catalog
        MOVEM.L A0-A1,-(A6)                     | save regs
        MOVE.L  (WDCBsPtr).w,A1                 | WDCB array
        MOVE.L  0x4(A1,D1.W),D0                 | DirID from WDCB (WDDirID)
        CMPI.L  #0x2,D0                         | root directory?
        BEQ.B   GETVOLINFO_ERR                  | yes, skip ->
        MOVE.L  0x8(A1,D1.W),D2                 | catalog hint (WDCatHint)
        SUBA.L  A0,A0                           | no CName (thread lookup)
        JSR     CMGetCN(PC)                     | look up directory record
        BNE.B   GETVOLINFO_ERR                  | error ->
        MOVE    0x4(A1),D0                      | directory valence (dirVal)
        MOVEM.L (A6)+,A0-A1                     | restore regs
        MOVE    D0,0x28(A0)                     | ioVNmFls = directory valence
        BRA.B   GETVOLINFO_SKIP                 | ->

| ----------------------------------------------------------
|
| GETVOLINFO_ERR
|
GETVOLINFO_ERR:
        MOVEM.L (A6)+,A0-A1                     | restore regs
| set return VRefNum
GETVOLINFO_SKIP:
        TST     D3                              | has directory context?
        BNE.B   GETVOLINFO_OK                   | yes ->
        TST     ioVRefNum(A0)                   | caller specified VRefNum?
        BLT.B   GETVOLINFO_CONT_7               | negative: keep caller's ->
GETVOLINFO_OK:
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | return volume refnum
GETVOLINFO_CONT_7:
        BSR     GETVOL_CONT_2                   | copy volume name to caller's buffer
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   GETVOLINFO_NO_3                 | no ->
| for TFS: subtract extent/catalog B-tree blocks from free count
        MOVE    0xA0(A2),D0                     | extent tree alloc blocks (VCBXTAlBks)
        SUB     D0,ioPosOffset(A0)              | subtract from free count
        MOVE    0xA2(A2),D0                     | catalog tree alloc blocks (VCBCTAlBks)
        SUB     D0,ioPosOffset(A0)              | subtract from free count
GETVOLINFO_NO_3:
| for MFS compatibility: cap at 31KB max
        BTst    #0x9,0x6(A0)                    | HFS-aware caller? (HFSBit 9 of ioTrap)
        BNE.B   GETVOLINFO_EXIT_2               | yes, return full HFS info ->
        MOVE    #0x7C00,D0                      | MFS max (31744 alloc blocks)
        CMP     ioPosOffset(A0),D0              | free count > max?
        BHI.B   GETVOLINFO_NO_4                 | no ->
        MOVE    D0,ioPosOffset(A0)              | cap ioVFrBlk
        CMP     0x3E(A0),D0                     | total count > max?
        BHI.B   GETVOLINFO_NO_4                 | no ->
        MOVE    D0,0x3E(A0)                     | cap ioVNmAlBlks
GETVOLINFO_NO_4:
        BRA.B   GETVOLINFO_CONT_8               | ->

| ----------------------------------------------------------
|
| GETVOLINFO_EXIT_2
|
| Called during boot.
| GETVOLINFO_EXIT_2: return extended HFS volume info (for HFS-aware callers)
GETVOLINFO_EXIT_2:
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | ioVRefNum
        MOVE    vcbSigWord(A2),0x40(A0)         | ioVSigWord
        MOVE    vcbDrvNum(A2),0x42(A0)          | ioVDrvInfo
        MOVE    vcbDRefNum(A2),0x44(A0)         | ioVDRefNum
        MOVE    vcbFSID(A2),0x46(A0)            | ioVFSID
        CLR.L   0x52(A0)                        | ioVWrCnt = 0
        MOVE    vcbNmFls(A2),0x54(A0)           | ioVFilCnt = root file count
        CLR.L   0x56(A0)                        | ioVDirCnt = 0
        MOVE    #0x1,0x58(A0)                   | ioVFndrInfo word 0 = 1
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   GETVOLINFO_SKIP_2               | no, skip TFS fields ->
        MOVE.L  vcbVolBkUp(A2),0x48(A0)         | ioVBkUp
        MOVE    vcbVSeqNum(A2),0x4C(A0)         | ioVSeqNum
        MOVE.L  vcbWrCnt(A2),0x4E(A0)           | ioVWrCnt
        MOVE.L  vcbFilCnt(A2),0x52(A0)          | ioVFilCnt
        MOVE.L  vcbDirCnt(A2),0x56(A0)          | ioVDirCnt
| copy Finder info (32 bytes)
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x5A(A0),A1                     | dest = ioVFndrInfo
        LEA.L   vcbFndrInfo(A2),A0              | source = VCBFndrInfo
        MOVEQ.L #0x20,D0                        | 32 bytes
        _BlockMove                              | copy Finder info to param block
        MOVE.L  (SP)+,A0                        | restore param block
GETVOLINFO_CONT_8:
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   GETVOLINFO_SKIP_2               | no ->
        BSR     CKExtFS                         | external FS?
        BNE.B   GETVOLINFO_ERR_2                | yes ->
GETVOLINFO_SKIP_2:
        MOVEQ.L #0x0,D0                         | noErr
GETVOLINFO_ERR_2:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| Set Vol Info_hfs
|
| _SetVolInfo (HFS): set volume info from param block
SetVolInfo_hfs:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     P_DTRMV1                        | DTRMV1: determine volume
        BNE.B   SETVOLINFO_HFS_ERR              | error ->
        BSR     SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   SETVOLINFO_HFS_ERR              | write protected ->
        BSR     FNDFILNAME_CONT_4               | CkExtFS: check external FS
        BNE.B   SETVOLINFO_HFS_ERR              | external FS ->
| copy volume dates and attributes from param block
        MOVE.L  ioFlAttrib(A0),vcbCrDate(A2)    | ioVCrDate -> VCBCrDate
        MOVE.L  0x22(A0),vcbLsBkUp(A2)          | ioVLsMod -> VCBLsBkUp
        MOVE    0x26(A0),D0                     | get ioVAtrb
        ANDI    #-0x8000,D0                     | keep only user-settable bit (bit 15)
        MOVE    vcbAtrb(A2),D1                  | current VCBAtrb
        ANDI    #0x7FFF,D1                      | mask off user bit
        OR      D0,D1                           | merge user's setting
        MOVE    D1,vcbAtrb(A2)                  | update VCBAtrb
| copy TFS-specific fields
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   SETVOLINFO_HFS_NO               | no ->
        MOVE.L  0x34(A0),vcbClpSiz(A2)          | ioVClpSiz -> VCBClpSiz
        MOVE.L  0x48(A0),vcbVolBkUp(A2)         | ioVBkUp -> VCBVolBkUp
        MOVE    0x4C(A0),vcbVSeqNum(A2)         | ioVSeqNum -> VCBVSeqNum
| copy Finder info (32 bytes)
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x5A(A0),A0                     | source = ioVFndrInfo
        LEA.L   vcbFndrInfo(A2),A1              | dest = VCBFndrInfo
        MOVEQ.L #0x20,D0                        | 32 bytes
        _BlockMove                              | copy Finder info from param block
        MOVE.L  (SP)+,A0                        | restore param block
| update volume name if specified
SETVOLINFO_HFS_NO:
        MOVE.L  ioFileName(A0),D0               | filename buffer
        BEQ.B   SETVOLINFO_HFS_NO_2             | no name ->
        MOVE.L  D0,A1                           | A1 = new volume name
        BSR.B   SETVOLINFO_HFS_CONT             | update VCB volume name
SETVOLINFO_HFS_NO_2:
        BSR     MarkVCB                         | call helper
        MOVEQ.L #0x0,D0                         | noErr
SETVOLINFO_HFS_ERR:
        BRA     FSQUEUE_DONE                    | ->

| SETVOLINFO_HFS_CONT -- update VCB volume name.
| ----------------------------------------------------------
|
| SETVOLINFO_HFS_CONT
|
SETVOLINFO_HFS_CONT:
        MOVEM.L A1-A2,-(SP)                     | save regs
        LEA.L   vcbVN(A2),A2                    | load address
        MOVEQ.L #0x1,D0                         | D0 = 1: index of the first name character
SETVOLINFO_HFS_CONT_2:
        CMP.B   (A1),D0                         | compare
        BGT.B   SETVOLINFO_HFS_OK               | yes ->
        CMPI.B  #0x3A,0x0(A1,D0.W)              | compare
        BEQ.B   SETVOLINFO_HFS_OK               | ok ->
        CMPI.B  #0x1B,D0                        | compare
        BGT.B   SETVOLINFO_HFS_OK               | yes ->
        MOVE.B  0x0(A1,D0.W),0x0(A2,D0.W)       | copy volume name byte
        ADDQ.W  #0x1,D0                         | advance byte index
        BRA.B   SETVOLINFO_HFS_CONT_2           | ->

| ----------------------------------------------------------
|
| SETVOLINFO_HFS_OK
|
| finish name copy: set length byte and mark VCB dirty
SETVOLINFO_HFS_OK:
        SUBQ.W  #0x1,D0                         | D0 = actual name length
        MOVE.B  D0,(A2)                         | store length byte in VCB name
        MOVEM.L (SP)+,A1-A2                     | restore regs
        BSR     MarkVCB                         | mark VCB dirty
        RTS                                     | return after updating VCB name

| ----------------------------------------------------------
|
| SETVOLINFO_HFS_CONT_3: check volume write protect status
|
| Called during boot.
SETVOLINFO_HFS_CONT_3:
        MOVEQ.L #-0x2E,D0                       | vLckdErr: assume software locked
        TST     vcbAtrb(A2)                     | user-locked? (VCBAtrb bit 15)
        BMI.B   SETVOLINFO_HFS_OK_2             | yes ->
        MOVEQ.L #-0x2C,D0                       | wPrErr: hardware write protect
        TST.B   0x13(A2)                        | write protected? (VCBAtrb+1 bit 7)
        BMI.B   SETVOLINFO_HFS_OK_2             | yes ->
        MOVEQ.L #0x0,D0                         | not locked, not protected
SETVOLINFO_HFS_OK_2:
        RTS                                     | return write protect error or zero

| ----------------------------------------------------------
|
| _GetVol ($A014)
|
| Called during boot.
GetVol:
        BTST    #0x9,D1                         | HFS GetDir call?
        BNE     GetDir_hfs4                     | yes ->
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.L  (DefVCBPtr).w,D0                | get default VCB
        BEQ.B   GETVOL_NO                       | no default ->
        MOVE.L  D0,A2                           | A2 = default VCB
        MOVE    (DefVRefNum).w,ioVRefNum(A0)    | IOParam field
        BSR.B   GETVOL_CONT_2                   | call helper
GETVOL_CONT:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| GETVOL_NO
|
GETVOL_NO:
        MOVEQ.L #-0x23,D0                       | nsvErr (-35): no such volume
        BRA.B   GETVOL_CONT                     | ->

| ----------------------------------------------------------
|
| GETVOL_CONT_2
|
| Called during boot.
| GETVOL_CONT_2: copy volume name to caller's buffer (for GetVol)
GETVOL_CONT_2:
        MOVEM.L A1-A2,-(SP)                     | save regs
        LEA.L   vcbVN(A2),A2                    | source = volume name in VCB
        MOVE.L  ioFileName(A0),D0               | dest = caller's filename buffer
        BEQ.B   GETVOL_SKIP                     | no buffer provided ->
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        CMP.L   (BufPtr).w,D0                   | buffer pointer valid?
        BGT.B   GETVOL_SKIP                     | invalid, skip ->
        MOVE.L  D0,A1                           | A1 = dest buffer
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A2),D0                         | D0 = name length
GETVOL_LOOP:
        MOVE.B  (A2)+,(A1)+                     | copy name string (including length byte)
        DBF     D0,GETVOL_LOOP                  | loop for all name bytes
GETVOL_SKIP:
        MOVEM.L (SP)+,A1-A2                     | restore regs
        MOVEQ.L #0x0,D0                         | no error
        RTS                                     | return after string copy

| ----------------------------------------------------------
|
| _SetVol ($A015)
|
| Called during boot.
SetVol:
        BTST    #0x9,D1                         | HFS SetDir call?
        BNE.B   SetDir_hfs3                     | yes ->
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     DTRMV3                          | DTRMV3: determine volume
        BNE.B   SETVOL_ERR                      | error ->
        MOVE    vcbVRefNum(A2),D0               | VRefNum of found volume
        TST     D3                              | has directory context?
        BNE.B   SETVOL_OK                       | yes ->
        TST     ioVRefNum(A0)                   | caller specified VRefNum?
        BGT.B   SETVOL_OK                       | positive: use as VRefNum ->
        MOVE    ioVRefNum(A0),D0                | get caller's VRefNum
        BEQ.B   SETVOL_SKIP                     | zero: don't change default ->
SETVOL_OK:
        MOVE    D0,(DefVRefNum).w               | set default VRefNum
SETVOL_SKIP:
        MOVEQ.L #0x2,D6                         | default to root DirID (FSRtDirID=2)
        MOVE.L  A3,D7                           | have a WDCB?
        BEQ.B   SETVOL_NO                       | no ->
        MOVE.L  0x4(A3),D6                      | get DirID from WDCB (WDDirID)
        MOVE.L  WDCatHint(A3),D7                | get catalog hint (WDCatHint)
SETVOL_NO:
        BSR     OPENWD_HFS_CONT                 | set up default WDCB
        MOVEQ.L #0x0,D0                         | no error
SETVOL_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| Set Dir_hfs3
|
| _SetVol (HFS SetDir): set default directory by pathname
SetDir_hfs3:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     P_FndFilName                    | FndFilName: parse pathname
        BEQ.B   SETDIR_HFS3_FOUND               | found ->
        CMPI    #-0x25,D0                       | FNFErr?
        BNE.B   SETDIR_HFS3_ERR                 | other error ->
        TST.B   D2                              | had a name component?
        BNE.B   SETDIR_HFS3_ERR                 | yes, real error ->
        MOVEQ.L #0x2,D6                         | no name: use root (FSRtDirID)
        BRA.B   SETDIR_HFS3_CONT                | ->

| ----------------------------------------------------------
|
| SETDIR_HFS3_FOUND
|
SETDIR_HFS3_FOUND:
        MOVEQ.L #-0x78,D0                       | dirNFErr (-120): directory not found
        CMPI.B  #0x1,(A5)                       | compare
        BNE.B   SETDIR_HFS3_ERR                 | error ->
        MOVE.L  0x6(A5),D6                      | D6 = directory ID from catalog
SETDIR_HFS3_CONT:
        MOVE    vcbVRefNum(A2),(DefVRefNum).w   | VCB field
        MOVEQ.L #0x0,D7                         | D7 = 0: no catalog hint (WDCatHint)
        BSR.B   OPENWD_HFS_CONT                 | call helper
        MOVEQ.L #0x0,D0                         | noErr
SETDIR_HFS3_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| Get Dir_hfs4
|
| _GetVol (HFS): get default directory info
GetDir_hfs4:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     CREATE_CONT_11                  | get default WDCB
        MOVEQ.L #-0x23,D0                       | NSVErr
        TST.L   0x0(A1,D1.W)                    | default WDCB in use? (WDVCBPtr)
        BEQ.B   GETDIR_HFS4_NO                  | no ->
        BSR     HFSF_CONT_2                     | copy WDCB info to param block
        BSR     GETVOL_CONT_2                   | copy volume name to caller's buffer
        MOVE    (DefVRefNum).w,ioVRefNum(A0)    | return default VRefNum
        MOVEQ.L #0x0,D0                         | no error
GETDIR_HFS4_NO:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| Open WD_hfs
|
| Called during boot.
| _OpenWD (HFS): open a working directory
OpenWD_hfs:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     P_FndFilName                    | FndFilName: find the directory
        BEQ.B   OPENWD_HFS_FOUND                | found ->
        CMPI    #-0x25,D0                       | FNFErr?
        BNE.B   OPENWD_HFS_ERR                  | no, other error ->
        TST.B   D2                              | had a name component?
        BNE.B   OPENWD_HFS_ERR                  | yes, real error ->
        BRA.B   OPENWD_HFS_NO                   | no name: use root dir ->
| check that it's a directory
OPENWD_HFS_FOUND:
        MOVEQ.L #-0x78,D0                       | dirNFErr
        CMPI.B  #0x1,(A5)                       | directory record? (cdrDirRec)
        BNE.B   OPENWD_HFS_ERR                  | no ->
        MOVE.L  0x6(A5),D6                      | D6 = DirID (dirDirID)
        CMPI.L  #0x2,D6                         | root directory?
        BEQ.B   OPENWD_HFS_NO                   | yes, use VRefNum ->
        MOVEQ.L #0x0,D7                         | no catalog hint
        BSR.B   OPENWD_HFS_CONT_3               | allocate WDCB for this directory
        BRA.B   OPENWD_HFS_ERR                  | ->
| root directory: just return VRefNum
OPENWD_HFS_NO:
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | return volume refnum
        MOVEQ.L #0x0,D0                         | no error
OPENWD_HFS_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| OPENWD_HFS_CONT: set default volume and directory
|
| Called during boot.
OPENWD_HFS_CONT:
        MOVE.L  A2,(DefVCBPtr).w                | set default VCB
        MOVEQ.L #0x2,D1                         | default WDCB offset
| OPENWD_HFS_CONT_2: fill in a WDCB entry at offset D1
OPENWD_HFS_CONT_2:
        MOVE.L  (WDCBsPtr).w,A1                 | WDCB array
        MOVE.L  A2,0x0(A1,D1.W)                 | WDVCBPtr = volume
        MOVE.L  D6,0x4(A1,D1.W)                 | WDDirID = directory ID
        MOVE.L  D7,0x8(A1,D1.W)                 | WDCatHint = catalog hint
        MOVE.L  0x1C(A0),D0                     | get procID from param block
        MOVE.L  D0,0xC(A1,D1.W)                 | WDProcID = calling process
        ADDI    #-0x7FFF,D1                     | convert offset to WD refnum
        RTS                                     | return WD refnum in D1

| ----------------------------------------------------------
|
| OPENWD_HFS_CONT_3
|
| OPENWD_HFS_CONT_3: allocate or find existing WDCB for DirID D6 on volume A2
OPENWD_HFS_CONT_3:
        MOVE.L  0x1C(A0),D3                     | D3 = procID (from ioWDProcID)
        MOVEQ.L #0x0,D2                         | D2 = 0 (no free WDCB found yet)
        BSR     CREATE_CONT_11                  | get WDCB array base
        BSR     CREATE_SKIP                     | skip to first WDCB
| scan WDCBs for existing match or free slot
OPENWD_HFS_OK:
        BSR     CREATE_SKIP                     | next WDCB
        BCC.B   OPENWD_HFS_CONT_4               | end of array ->
        TST.L   0x0(A1,D1.W)                    | WDCB in use? (WDVCBPtr)
        BNE.B   OPENWD_HFS_FOUND_2              | yes, check for match ->
        TST     D2                              | already found a free slot?
        BNE.B   OPENWD_HFS_OK                   | yes, keep scanning ->
        MOVE    D1,D2                           | D2 = free slot offset
        BRA.B   OPENWD_HFS_OK                   | keep scanning
| check if this WDCB matches our volume/DirID/procID
OPENWD_HFS_FOUND_2:
        CMPA.L  0x0(A1,D1.W),A2                 | same volume? (WDVCBPtr)
        BNE.B   OPENWD_HFS_OK                   | no ->
        CMP.L   0x4(A1,D1.W),D6                 | same DirID? (WDDirID)
        BNE.B   OPENWD_HFS_OK                   | no ->
        CMP.L   0xC(A1,D1.W),D3                 | same procID? (WDProcID)
        BNE.B   OPENWD_HFS_OK                   | no ->
| found existing WDCB: return its WD refnum
        ADDI    #-0x7FFF,D1                     | convert offset to WD refnum
        BRA.B   OPENWD_HFS_CONT_5               | ->
| no existing match: allocate the free slot
OPENWD_HFS_CONT_4:
        MOVE    D2,D1                           | D1 = free slot offset
        BEQ.B   OPENWD_HFS_NO_2                 | no free slot ->
        BSR.B   OPENWD_HFS_CONT_2               | fill in WDCB fields
OPENWD_HFS_CONT_5:
        MOVE    D1,ioVRefNum(A0)                | return WD refnum
        MOVEQ.L #0x0,D0                         | no error
        RTS                                     | return with WD refnum initialized
OPENWD_HFS_NO_2:
        MOVEQ.L #-0x79,D0                       | tmwdoErr: too many WDs open
        RTS                                     | return with tmwdoErr

| ----------------------------------------------------------
|
| Close WD_hfs
|
| _CloseWD (HFS): close a working directory
CloseWD_hfs:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVEQ.L #0x0,D1                         | clear high word
        MOVE    ioVRefNum(A0),D1                | get WD refnum
        BSR     HFSF_CONT_3                     | validate WD refnum
        BEQ.B   CLOSEWD_HFS_CONT                | valid ->
        CMPI    #-0x1000,D1                     | plain VRefNum? (> -4096)
        BHI.B   CLOSEWD_HFS_EXIT                | yes, just return ok ->
        BRA.B   CLOSEWD_HFS_CONT_2              | invalid WD ->
| close the working directory
CLOSEWD_HFS_CONT:
        SUBI    #-0x7FFF,D1                     | convert WD refnum to WDCB offset
        MOVE.L  0x0(A1,D1.W),A2                 | get VCB from WDCB (WDVCBPtr)
        TST     vcbFSID(A2)                     | external FS?
        BEQ.B   CLOSEWD_HFS_OK                  | ok ->
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        ADD.L   A1,D1                           | D1 = absolute WDCB pointer
        MOVEQ.L #-0x3A,D0                       | extFSErr (-58): external file system volume
        BRA.B   CLOSEWD_HFS_CONT_2              | ->

| ----------------------------------------------------------
|
| CLOSEWD_HFS_OK
|
CLOSEWD_HFS_OK:
        CLR.L   0x0(A1,D1.W)                    | clear
CLOSEWD_HFS_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
CLOSEWD_HFS_CONT_2:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| Get WD Info_hfs
|
| _GetWDInfo (HFS): return working directory info
GetWDInfo_hfs:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   GETWDINFO_HFS_CONT              | get WD info by refnum or index
        BNE.B   GETWDINFO_HFS_ERR               | error ->
        EXT.L   D1                              | extend WDCB offset to long
        ADD.L   A1,D1                           | D1 = WDCB pointer
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        BSR     CKExtFS                         | check external FS
        BNE.B   GETWDINFO_HFS_ERR               | external FS ->
        MOVEQ.L #0x0,D0                         | no error
GETWDINFO_HFS_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| GETWDINFO_HFS_CONT
|
| GETWDINFO_HFS_CONT/GetWDInfo common: get WD info by refnum or index
GETWDINFO_HFS_CONT:
        TST     0x1A(A0)                        | index > 0? (ioWDIndex)
        BGT.B   GETWDINFO_HFS_OK                | yes, scan by index ->
| get by VRefNum
        MOVE    ioVRefNum(A0),D1                | get VRefNum
        BSR     HFSF_CONT_3                     | validate WD refnum
        BEQ.B   GETWDINFO_HFS_CONT_2            | valid WD ->
| not a WD: return root directory info
        BSR     P_DTRMV1                        | DTRMV1: determine volume
        BNE.B   GETWDINFO_HFS_ERR_2             | error ->
        CLR.L   0x1C(A0)                        | ioWDProcID = 0
        MOVEQ.L #0x2,D0                         | root DirID (FSRtDirID)
        MOVE.L  D0,ioWDDirID(A0)                | ioWDDirID = root
        MOVE    vcbVRefNum(A2),0x20(A0)         | ioWDVRefNum
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | return VRefNum
        MOVEQ.L #0x0,D1                         | D1 = 0 (WDCB offset for root)
        BRA.B   GETWDINFO_HFS_CONT_4            | ->
| valid WD reference: get WDCB info
GETWDINFO_HFS_CONT_2:
        MOVEQ.L #-0x23,D0                       | NSVErr
        SUBI    #-0x7FFF,D1                     | convert WD refnum to WDCB offset
        TST.L   0x0(A1,D1.W)                    | WDCB in use? (WDVCBPtr)
        BEQ.B   GETWDINFO_HFS_ERR_2             | no, invalid ->
        BRA.B   GETWDINFO_HFS_CONT_3            | ->

| ----------------------------------------------------------
|
| GETWDINFO_HFS_OK
|
| GetWDInfo by index: determine volume filter first
GETWDINFO_HFS_OK:
        MOVEQ.L #-0x23,D0                       | NSVErr
        MOVEQ.L #0x0,D2                         | D2 = 0 (no volume filter)
        TST     ioVRefNum(A0)                   | volume specified?
        BEQ.B   GETWDINFO_HFS_NO                | no, scan all ->
        BSR     DTRMV3                          | determine volume
        BNE.B   GETWDINFO_HFS_ERR_2             | error ->
        MOVE.L  A2,D2                           | D2 = VCB pointer filter
| GetWDInfo indexed: scan WDCBs by index, with procID and volume filters
GETWDINFO_HFS_NO:
        MOVE    0x1A(A0),D4                     | D4 = ioWDIndex
        MOVE.L  0x1C(A0),D3                     | D3 = ioWDProcID filter (0 = any)
        MOVEQ.L #-0x23,D0                       | assume NSVErr
        BSR     CREATE_CONT_11                  | get WDCB array base
        BSR     CREATE_SKIP                     | skip header
GETWDINFO_HFS_SKIP:
        BSR     CREATE_SKIP                     | next WDCB
        BCC.B   GETWDINFO_HFS_ERR_2             | end of array ->
        TST.L   0x0(A1,D1.W)                    | WDCB in use? (WDVCBPtr)
        BEQ.B   GETWDINFO_HFS_SKIP              | no, skip ->
| filter by procID
        TST.L   D3                              | procID filter active?
        BEQ.B   GETWDINFO_HFS_NO_2              | no ->
        CMP.L   0xC(A1,D1.W),D3                 | same procID? (WDProcID)
        BNE.B   GETWDINFO_HFS_SKIP              | no ->
| filter by volume
GETWDINFO_HFS_NO_2:
        TST.L   D2                              | volume filter active?
        BEQ.B   GETWDINFO_HFS_NO_3              | no ->
        CMP.L   0x0(A1,D1.W),D2                 | same VCB? (WDVCBPtr)
        BNE.B   GETWDINFO_HFS_SKIP              | no ->
GETWDINFO_HFS_NO_3:
        SUBQ.W  #0x1,D4                         | decrement usage count
        BGT.B   GETWDINFO_HFS_SKIP              | yes ->
GETWDINFO_HFS_CONT_3:
        BSR.B   HFSF_CONT                       | call helper
GETWDINFO_HFS_CONT_4:
        BSR     GETVOL_CONT_2                   | call helper
GETWDINFO_HFS_ERR_2:
        TST     D0                              | test
        RTS                                     | return from GETWDINFO_HFS_ERR_2

| ----------------------------------------------------------
|
| hfs F
|
hfsF:
| hfsF: _GetWDInfo HFS dispatch
        MOVEM.L D3-D7/A1-A6,-(SP)               | save regs
        MOVE.L  (HFSVars_HFSStkTop).w,A6        | set up HFS stack
        BSR     GETWDINFO_HFS_CONT              | get WD info
        MOVEM.L (SP)+,D3-D7/A1-A6               | restore regs
        MOVE    D0,ioResult(A0)                 | set result code
        RTS                                     | return to caller after HFS dispatch

| ----------------------------------------------------------
|
| HFSF_CONT: copy WDCB info + procID to param block
|
HFSF_CONT:
        MOVE.L  0xC(A1,D1.W),0x1C(A0)           | ioWDProcID from WDCB (WDProcID)
| HFSF_CONT_2: copy WDCB VCB/DirID to param block
HFSF_CONT_2:
        MOVE.L  0x0(A1,D1.W),A2                 | A2 = VCB from WDCB (WDVCBPtr)
        MOVE    vcbVRefNum(A2),0x20(A0)         | ioWDVRefNum
        MOVE.L  0x4(A1,D1.W),ioWDDirID(A0)      | ioWDDirID from WDCB (WDDirID)
        MOVE    D1,D0                           | convert WDCB offset
        ADDI    #-0x7FFF,D0                     | to WD refnum
        MOVE    D0,ioVRefNum(A0)                | return WD refnum
        RTS                                     | return WD refnum extracted from WDCB

| ----------------------------------------------------------
|
| HFSF_CONT_3
|
| HFSF_CONT_3: validate that D1 is a valid WD refnum
HFSF_CONT_3:
        MOVE.L  D1,-(SP)                        | save D1
        MOVEQ.L #-0x33,D0                       | assume RFNumErr
        SUBI    #-0x7FFF,D1                     | convert WD refnum to WDCB offset
        MOVE.L  (WDCBsPtr).w,A1                 | WDCB array
        CMP     (A1),D1                         | past end of WDCB array?
        BCC.B   HFSF_OK                         | yes, invalid ->
        SUBQ.W  #0x2,D1                         | subtract WDCB header
        DIVU    #0x10,D1                        | / WDCB size (16 bytes)
        SWAP    D1                              | remainder in low word
        TST     D1                              | aligned? (remainder = 0)
        BNE.B   HFSF_OK                         | no, invalid ->
        MOVEQ.L #0x0,D0                         | valid WD refnum
HFSF_OK:
        MOVE.L  (SP)+,D1                        | restore D1
        TST     D0                              | set condition codes
        RTS                                     | return with validation status flags set

| ----------------------------------------------------------
|
| hfs D
|
| hfsD: _OpenWD HFS dispatch (open a working directory)
hfsD:
        MOVEM.L D3-D7/A1-A6,-(SP)               | save regs
        MOVE.L  (HFSVars_HFSStkTop).w,A6        | set up HFS stack
        BSR     P_DTRMV1                        | DTRMV1: determine volume
        BNE.B   HFSD_ERR                        | error ->
        MOVE.L  ioWDDirID(A0),D6                | D6 = DirID
        MOVEQ.L #0x0,D7                         | D7 = 0 (catalog hint)
        BSR     OPENWD_HFS_CONT_3               | open working directory
        BNE.B   HFSD_ERR                        | error ->
        MOVE    D1,ioVRefNum(A0)                | return WD refnum
HFSD_CONT:
        MOVEQ.L #0x0,D0                         | no error
HFSD_ERR:
        MOVEM.L (SP)+,D3-D7/A1-A6               | restore regs
        MOVE    D0,ioResult(A0)                 | set result code
        RTS                                     | return to caller after dispatch

| ----------------------------------------------------------
|
| hfsE: _SetVol HFS dispatch (set default directory)
|
hfsE:
        MOVEM.L D3-D7/A1-A6,-(SP)               | save regs
        MOVE.L  (HFSVars_HFSStkTop).w,A6        | set up HFS stack
        BSR     P_DTRMV1                        | DTRMV1: determine volume
        BNE.B   HFSD_ERR                        | error ->
        MOVE    vcbVRefNum(A2),(DefVRefNum).w   | set default VRefNum
        MOVE.L  ioWDDirID(A0),D6                | D6 = DirID
        MOVEQ.L #0x0,D7                         | D7 = 0
        BSR     OPENWD_HFS_CONT                 | set default directory
        BRA.B   HFSD_CONT                       | ->

| ----------------------------------------------------------
|
| HFSE_CONT
|
| Called during boot.
| MV_GetMFSMap: set up MFS volume - allocate alloc map and read it from disk
HFSE_CONT:
        MOVEQ.L #0x5E,D0                        | trim VCB to MFS size (94 bytes)
        MOVE.L  A2,A0                           | VCB ptr
        _SetPtrSize                             | resize VCB to MFS size
| compute alloc map size: (NmAlBlks * 1.5 + 1) / 2 bytes (12 bits per entry)
        MOVEQ.L #0x3,D2                         | 3 * NmAlBlks
        MULU    vcbNmAlBlks(A2),D2              | D2 = 3 * number of alloc blocks
        ADDQ.L  #0x1,D2                         | + 1 (round up)
        LSR.L   #0x1,D2                         | / 2 = byte count for 12-bit map
        MOVE    D2,vcbMLen(A2)                  | store alloc map length
| allocate alloc map and read it from MDB
        MOVEQ.L #0x40,D7                        | MDB offset $40 = start of alloc map
        MOVE.L  D2,D0                           | alloc map size
        _NewPtrSys                              | allocate memory for alloc map
        BNE     MTVOLER1                        | error ->
        MOVE.L  A0,vcbMAdr(A2)                  | store alloc map pointer
        MOVEQ.L #0x2,D3                         | start at block 2 (MDB block)
| copy alloc map from MDB block(s) to memory
HFSE_NO:
        MOVE    0x0(A5,D7.W),(A0)+              | copy alloc map word from disk
        ADDQ.W  #0x2,D7                         | advance source offset
        SUBQ.W  #0x2,D2                         | more bytes to copy?
        BLE.B   HFSE_NO_2                       | no ->
        CMPI    #0x200,D7                       | past end of 512-byte block?
        BCS.B   HFSE_NO                         | no, keep copying
| need next disk block for more alloc map data
        ADDQ.W  #0x1,D3                         | next block number
        BSR     FILEWRITE_NEXT_2                | read next block
        BNE.B   HFSE_ERR_2                      | error ->
        MOVEQ.L #0x0,D7                         | reset offset to start of block
        BRA.B   HFSE_NO                         | continue copying

| ----------------------------------------------------------
|
| HFSE_NO_2
|
| Called during boot.
HFSE_NO_2:
        BSR.B   HFSE_CONT_3                     | call helper
        BEQ.B   HFSE_OK_2                       | ok ->
HFSE_ERR:
        MOVEQ.L #-0x3C,D0                       | badMDBErr (-60): bad master directory block
HFSE_ERR_2:
        BSR.B   HFSE_CONT_2                     | call helper
        BRA     MTVOLER1                        | ->

| ----------------------------------------------------------
|
| HFSE_CONT_2
|
| HFSE_CONT_2: dispose MFS alloc map memory
HFSE_CONT_2:
        MOVEM.L D0/A0,-(SP)                     | save regs
        MOVE.L  vcbMAdr(A2),A0                  | alloc map pointer
        _DisposePtr                             | free alloc map memory
        CLR.L   vcbMAdr(A2)                     | clear VCBMAdr
        MOVEM.L (SP)+,D0/A0                     | restore regs
        RTS                                     | return after freeing alloc map

| ----------------------------------------------------------
|
| HFSE_CONT_3: MFS consistency check - count free blocks in alloc map
|
| Called during boot.
HFSE_CONT_3:
        MOVEQ.L #0x2,D3                         | start at block 2 (first alloc block)
        MOVEQ.L #0x0,D1                         | D1 = free block count
HFSE_CONT_4:
        BSR     LG2PHYS_NEXT_2                  | LG2PHYS_NEXT_2: get next block from alloc map
        BNE.B   HFSE_NO_3                       | not free (nonzero) ->
        ADDQ.W  #0x1,D1                         | count free block
HFSE_NO_3:
        CMP     vcbNmAlBlks(A2),D3              | past last alloc block?
        BHI.B   HFSE_OK                         | yes ->
        ADDQ.W  #0x1,D3                         | next block
        BRA.B   HFSE_CONT_4                     | keep scanning

| ----------------------------------------------------------
|
| HFSE_OK: compare counted free blocks with VCB
|
| Called during boot.
HFSE_OK:
        CMP     vcbFreeBks(A2),D1               | matches VCBFreeBks?
        RTS                                     | return (Z set if match)

| ----------------------------------------------------------
|
| HFSE_OK_2: MFS mount - initialize directory scan counters
|
| Called during boot.
HFSE_OK_2:
        MOVEQ.L #0x0,D1                         | D1 = file count
        MOVEQ.L #0x0,D2                         | D2 = max file number
        MOVEQ.L #0x0,D7                         | D7 = consistency flags
        BSR     FILEWRITE_CONT_4                | call helper
        BNE.B   HFSE_ERR_2                      | error ->
HFSE_OK_3:
        TST.B   (A5)                            | test
        BNE.B   HFSE_ERR_3                      | error ->
        MOVE.L  A5,A0                           | A0 = block buffer ptr
        EXG     D1,D6                           | exchange
        MOVEQ.L #0x2,D1                         | D1 = 2: RelBlock option RBtrash (bit 1)
        JSR     P_mRelBlock(PC)                 | call helper
        EXG     D1,D6                           | exchange
HFSE_ERR_3:
        MOVEQ.L #0x0,D0                         | noErr
HFSE_CONT_5:
        TST.B   0x0(A5,D0.W)                    | test
        BEQ.B   HFSE_OK_4                       | ok ->
        ADDQ.W  #0x1,D1                         | increment file count
| track max file number for VCBNxtCNID
        CMP.L   0x12(A5,D0.W),D2                | file number > current max?
        BHI.B   HFSE_NO_4                       | no ->
        MOVE.L  0x12(A5,D0.W),D2                | update max file number
| verify alloc map entries for data and resource forks
HFSE_NO_4:
        LEA.L   0x16(A5,D0.W),A3                | ptr to data fork start block
        BSR.B   HFSE_CONT_7                     | verify alloc chain for data fork
        BNE.B   HFSE_ERR                        | error ->
        LEA.L   0x20(A5,D0.W),A3                | ptr to rsrc fork start block
        BSR.B   HFSE_CONT_7                     | verify alloc chain for rsrc fork
        BNE.B   HFSE_ERR                        | error ->
        BSR     CREATE_NEXT                     | advance to next directory entry
        BCS.B   HFSE_CONT_5                     | more entries ->
HFSE_OK_4:
        BSR     FILEWRITE_NEXT                  | call helper
        BEQ.B   HFSE_OK_3                       | ok ->
        CMPI    #-0x21,D0                       | compare
        BNE     HFSE_ERR_2                      | error ->
        CMP.L   vcbNxtCNID(A2),D2               | compare
        BCS.B   HFSE_CONT_6                     | unsigned less ->
        ADDQ.L  #0x1,D2                         | bump past current max
        MOVE.L  D2,vcbNxtCNID(A2)               | VCB field
        ADDQ.B  #0x1,D7                         | flag: VCB was modified
HFSE_CONT_6:
        CMP     vcbNmFls(A2),D1                 | compare
        BEQ.B   HFSE_OK_5                       | ok ->
        MOVE    D1,vcbNmFls(A2)                 | VCB field
        ADDQ.B  #0x2,D7                         | flag: file count changed
HFSE_OK_5:
        TST.B   D7                              | test
        BEQ.B   HFSE_ERR_4                      | ok ->
        BSR     SETVOLINFO_HFS_CONT_3           | call helper
        BNE.B   HFSE_ERR_4                      | error ->
        BSR     MarkVCB                         | call helper
HFSE_ERR_4:
        OR.B    D7,0x13(A2)                     | Set bits
        BRA     CHECKREMOUNT                    | ->

| ----------------------------------------------------------
|
| HFSE_CONT_7
|
| Called during boot.
| HFSE_CONT_7: MFS alloc chain walk - compute PEOF from chain and update directory
HFSE_CONT_7:
        MOVEM.L D0-D6,-(SP)                     | save regs
        MOVE    vcbNmAlBlks(A2),D1              | D1 = max blocks (loop limit)
        MOVEQ.L #0x0,D6                         | D6 = PEOF accumulator
        MOVE.L  vcbAlBlkSiz(A2),D2              | D2 = alloc block size
        MOVE    (A3),D3                         | D3 = start block from directory entry
        BEQ.B   HFSE_NO_5                       | no blocks allocated ->
| walk the alloc chain
HFSE_ERR_5:
        BSR     LG2PHYS_NEXT_2                  | LG2PHYS_NEXT_2: get next block in chain
        SUBQ.W  #0x1,D1                         | safety: decrement block limit
        BCS.B   HFSE_OK_7                       | exceeded max: chain is corrupt ->
        MOVE    D5,D3                           | D3 = next block
        BEQ.B   HFSE_NO_5                       | ok ->
        ADD.L   D2,D6                           | accumulate physical length
        CMPI    #0x1,D3                         | compare
        BNE.B   HFSE_ERR_5                      | error ->
| MFS FClose: update directory entry from FCB
HFSE_NO_5:
        MOVE    (A3)+,D3                        | get start block from FCB area
        MOVE.L  (A3)+,D4                        | get LEOF from FCB
        MOVE.L  (A3)+,D5                        | get old PEOF from directory
        CMP.L   D5,D6                           | PEOF unchanged?
        BEQ.B   HFSE_OK_6                       | yes, nothing to update ->
        MOVE.L  D6,-(A3)                        | update PEOF in directory
        BNE.B   HFSE_CONT_8                     | nonzero ->
        CLR     D3                              | PEOF=0: clear start block
HFSE_CONT_8:
        CMP.L   D6,D4                           | LEOF > PEOF?
        BLS.B   HFSE_NO_6                       | no ->
        MOVE.L  D6,D4                           | yes, pin LEOF to PEOF
HFSE_NO_6:
        MOVE.L  D4,-(A3)                        | update LEOF in directory
        MOVE    D3,-(A3)                        | update start block in directory
        BSR     SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   HFSE_OK_7                       | write protected ->
        JSR     MarkA5Block(PC)                 | mark directory block dirty
        BSET    #0x2,D7                         | flag: directory was modified
HFSE_OK_6:
        MOVEQ.L #0x0,D1                         | no error
HFSE_OK_7:
        MOVEM.L (SP)+,D0-D6                     | restore regs
        RTS                                     | return success, preserving registers

| ----------------------------------------------------------
|
| HFSE_CONT_9
|
| Called during boot.
| HFSE_CONT_9: MFS FlushVol - flush VCB info back to MDB on disk
HFSE_CONT_9:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D7/A0-A5,-(A6)               | save regs
        TST     vcbDrvNum(A2)                   | volume online?
        BEQ.B   HFSE_NO_9                       | no (offline) ->
        TST.B   vcbFlags(A2)                    | VCB dirty?
        BPL.B   HFSE_SKIP                       | no, skip flush ->
| write-protect check and read MDB block
        BSR     HFSE_CONT_3                     | check write protect
        BNE.B   HFSE_SKIP                       | write protected ->
        MOVEQ.L #0x2,D3                         | MDB is block 2
        BSR     FILEWRITE_CONT_5                | read MDB into cache
        BNE.B   HFSE_ERR_7                      | error ->
        JSR     MarkA5Block(PC)                 | mark MDB block dirty
| copy VCB info to MDB
        MOVEQ.L #0x1F,D0                        | 32 words (64 bytes of VCB info)
        MOVE.L  A5,A1                           | dest = MDB block buffer
        LEA.L   vcbSigWord(A2),A0               | source = VCB
        MOVE.L  (Time).w,vcbLsBkUp(A2)          | update last backup date
HFSE_LOOP:
        MOVE    (A0)+,(A1)+                     | copy VCB to MDB
        DBF     D0,HFSE_LOOP                    | loop for all VCB words
| copy alloc map to MDB (offset $40 in MDB block)
        MOVE.L  vcbMAdr(A2),A0                  | source = alloc map in memory
        MOVE    vcbMLen(A2),D2                  | alloc map length
        MOVEQ.L #0x40,D7                        | dest offset in MDB block
HFSE_NO_7:
        MOVE    (A0)+,0x0(A5,D7.W)              | copy alloc map word
        ADDQ.W  #0x2,D7                         | advance dest
        SUBQ.W  #0x2,D2                         | more to copy?
        BLE.B   HFSE_NO_8                       | no ->
        CMPI    #0x200,D7                       | past end of block?
        BCS.B   HFSE_NO_7                       | no, keep copying
        ADDQ.W  #0x1,D3                         | advance to next disk block
        BSR     FILEWRITE_CONT_5                | call helper
        BNE.B   HFSE_ERR_7                      | error ->
        JSR     MarkA5Block(PC)                 | call helper
        MOVEQ.L #0x0,D7                         | D7 = 0: next block is filled from its start
        BRA.B   HFSE_NO_7                       | ->

| ----------------------------------------------------------
|
| HFSE_NO_8
|
HFSE_NO_8:
        CMPI    #0x200,D7                       | compare
        BCC.B   HFSE_SKIP                       | unsigned greater or equal ->
        CLR     0x0(A5,D7.W)                    | clear
        ADDQ.W  #0x2,D7                         | advance word offset
        BRA.B   HFSE_NO_8                       | ->

| ----------------------------------------------------------
|
| HFSE_SKIP
|
| Called during boot.
HFSE_SKIP:
        BSR     OFFLINE_CONT_2                  | call helper
        BNE.B   HFSE_ERR_7                      | error ->
HFSE_NO_9:
        CLR.B   vcbFlags(A2)                    | clear
        TST.B   (FlushOnly).w                   | test
        BNE.B   HFSE_ERR_6                      | error ->
        TST     vcbDrvNum(A2)                   | test
        BEQ.B   HFSE_OK_8                       | ok ->
        BSR     HFSE_CONT_2                     | call helper
HFSE_OK_8:
        BSR     BMCHK_CONT_2                    | call helper
HFSE_ERR_6:
        MOVEQ.L #0x0,D0                         | noErr
HFSE_ERR_7:
        MOVEM.L (A6)+,D1-D7/A0-A5               | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | test
        RTS                                     | return from HFSE_ERR_7

| ----------------------------------------------------------
|
| HFSE_CONT_10
|
HFSE_CONT_10:
        BSR     FSQUEUE_SETUP                   | call helper
        MOVE    0x1C(A0),D2                     | D2 = ioMisc/ioNewName index
        BGT.B   HFSE_OK_10                      | yes ->
        BEQ.B   HFSE_OK_9                       | ok ->
        BSR     DTRMV3                          | call helper
        BRA.B   HFSE_CONT_11                    | ->

| ----------------------------------------------------------
|
| HFSE_OK_9
|
HFSE_OK_9:
        BSR     P_DTRMV1                        | call helper
HFSE_CONT_11:
        BNE.B   HFSE_ERR_8                      | error ->
        BRA.B   HFSE_OK_11                      | ->

| ----------------------------------------------------------
|
| HFSE_OK_10
|
HFSE_OK_10:
        MOVE.L  (VCBQHdr_Head).w,D1             | VCB field
HFSE_CONT_12:
        BEQ     GETVOL_NO                       | ok ->
        SUBQ.W  #0x1,D2                         | decrement volume index
        MOVE.L  D1,A2                           | A2 = current VCB
        BEQ.B   HFSE_OK_11                      | ok ->
        MOVE.L  (A2),D1                         | D1 = next VCB in queue (qLink)
        BRA.B   HFSE_CONT_12                    | ->

| ----------------------------------------------------------
|
| HFSE_OK_11
|
HFSE_OK_11:
        BSet    #0x6,0x13(A2)                   | set flag
        BSR.B   HFSE_CONT_14                    | call helper
HFSE_CONT_13:
        CMPA.L  0x14(A1,D1.W),A2                | compare
        BEQ.B   HFSE_OK_12                      | ok ->
        BSR.B   HFSE_NEXT                       | call helper
        BCS.B   HFSE_CONT_13                    | unsigned less ->
        BCLR    #0x6,0x13(A2)                   | clear flag
HFSE_OK_12:
        MOVEQ.L #0x20,D0                        | D0 = $20: copy 17 words, VCB+$A.. -> param block+$1E..
HFSE_OK_13:
        MOVE    0xA(A2,D0.W),0x1E(A0,D0.W)      | copy VCB field to param block
        SUBQ.W  #0x2,D0                         | decrement word offset
        BPL.B   HFSE_OK_13                      | yes ->
        BSR     GETVOL_CONT_2                   | call helper
HFSE_ERR_8:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| HFSE_CONT_14
|
| Called during boot.
HFSE_CONT_14:
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB array base
        MOVEQ.L #0x2,D1                         | D1 = 2: offset of the first FCB (2-byte array header)
        RTS                                     | return from HFSE_CONT_14

| ----------------------------------------------------------
|
| HFSE_NEXT
|
| Called during boot (1,205 times in 30s trace).
HFSE_NEXT:
        ADDI    #0x5E,D1                        | advance to next FCB (fcbEntLen=94)
        CMP     (A1),D1                         | compare
        RTS                                     | return from HFSE_NEXT

| ----------------------------------------------------------
|
| HFSE_CONT_15
|
| Called during boot.
HFSE_CONT_15:
        BSR.B   HFSE_CONT_14                    | call helper
HFSE_CONT_16:
        CMP.L   0x0(A1,D1.W),D2                 | compare
        BNE.B   HFSE_ERR_9                      | error ->
        CMPA.L  0x14(A1,D1.W),A2                | compare
        BEQ.B   HFSE_OK_14                      | ok ->
| HFSE_ERR_9 -- gtNxtMatch: find next matching FCB.
| Called by: FILEOPEN_SKIP, PERMSSNCHK_NO_2, RENAME_CONT_2, HFSCATMOVE_CONT, HFSCATMOVE_OK_7 (and 2 more)
HFSE_ERR_9:
        BSR.B   HFSE_NEXT                       | call helper
        BCS.B   HFSE_CONT_16                    | unsigned less ->
        MOVE    #0x0,CCR                        | clear all condition flags (Z=0)
HFSE_OK_14:
        RTS                                     | return from HFSE_OK_14
