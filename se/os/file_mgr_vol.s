| File Manager -- common subroutines and volume calls
|
| Apple sources, included by TFS.a (MacSEROM.lst module TURBOFS):
| TFSCommon.a (DOEJECT, DIVUP, ROUNDALLOC, GETVCBRFN, MARKVCB,
| MARKVCBTIME, FLUSHMDB, MAKESTKPB) and TFSVol.a /
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

| DOEJECT - volume eject handler
|
| Called via the File Manager front-end jump table. If an EjectNotify
| hook is installed, calls it first (can suppress the eject). Otherwise
| calls _Eject directly. Beeps on eject failure.
| Entry: D1 = drive number, D2 = volume refNum
DOEJECT:
    BSR.W       MAKESTKPB                       | build IOParam block on stack
    MOVE.W      D1,0x16(A0)                     | ioVRefNum = drive number
    MOVE.L      (EjectNotify).W,D0              | D0 = eject notify hook
    BLE.B       VDOEJECT_DO_EJECT               | no hook: eject directly
    MOVEM.L     D2/A0-A2,-(A7)                  | save registers for hook call
    CLR.W       -(A7)                           | push result space
    MOVE.W      D1,-(A7)                        | push drive number
    MOVE.W      D2,-(A7)                        | push volume refNum
    MOVEA.L     D0,A0                           | A0 = eject notify proc
    JSR         (A0)                            | call eject notify hook
    TST.B       (A7)+                           | hook returned true? (suppress eject)
    MOVEM.L     (A7)+,D2/A0-A2                  | restore registers
    BEQ.B       VDOEJECT_DONE                   | hook suppressed: skip eject
VDOEJECT_DO_EJECT:
    _Eject                                      | eject the volume
    BEQ.B       VDOEJECT_DONE                   | success: done
    MOVE.W      #0x8,-(A7)                      | push beep duration
    _SysBeep                                    | beep on eject error
VDOEJECT_DONE:
    ADDA.W      #0x40,A7                        | deallocate IOParam from stack
    RTS                                         | return from eject handler
| DIVUP - unsigned divide with round-up
|
| Returns ceil(D0 / D1). Used for allocation block calculations.
| Entry: D0 = dividend, D1 = divisor
| Exit: D0 = ceiling quotient
| Called by: ROUNDALLOC, FLUSHMDB, MOUNTVOL_CONT_6, MOUNTVOL_FOUND_3, MOUNTVOL_OK_9 (and 1 more)
DIVUP:
    DIVU.W      D1,D0                           | D0 = quotient:remainder
    SWAP.W      D0                              | D0 low = remainder
    TST.W       D0                              | remainder == 0? (exact)
    BEQ.B       DIVUP_EXACT                     | yes: quotient is exact
    CLR.W       D0                              | clear remainder
    SWAP.W      D0                              | D0 = quotient
    ADDQ.W      #0x1,D0                         | round up: quotient + 1
    BRA.B       DIVUP_RET                       | return rounded result
| DIVUP_EXACT - exact division, no rounding needed
DIVUP_EXACT:
    SWAP.W      D0                              | D0 = quotient (remainder was 0)
DIVUP_RET:
    RTS                                         | return from DIVUP
| ROUNDALLOC - round byte count to allocation blocks
|
| Converts a byte count (D1) to allocation block count using the
| volume's block size from the VCB at (A2).
| Entry: D0 = existing value, D1 = byte count to convert
|        A2 = VCB pointer (vcbAlBlkSiz at +$1C)
| Exit: stacked allocation block count
ROUNDALLOC:
    MOVE.L      D1,-(A7)                        | save byte count
    MOVE.L      D0,-(A7)                        | save D0
    MOVE.L      D1,D0                           | D0 = byte count to convert
    MOVE.L      0x1C(A2),D1                     | D1 = vcbAlBlkSiz (alloc block size)
    BSR.B       DIVUP                           | D0 = ceil(bytes / blockSize)
    MOVE.L      D0,D1                           | D1 = block count
    MOVE.L      (A7)+,D0                        | restore D0
    MOVE.L      D1,-(A7)                        | push block count result
    MOVE.L      0x1C(A2),D1                     | D1 = vcbAlBlkSiz again
    BSR.B       DIVUP                           | D0 = ceil(original_D0 / blockSize)
    MOVE.L      (A7)+,D1                        | D1 = block count from first division
    BSR.B       DIVUP                           | D0 = ceil(prev / blockCount)
    MULU.W      D1,D0                           | D0 = rounded allocation in blocks
    MOVE.L      (A7)+,D1                        | restore original D1
    RTS                                         | return from ROUNDALLOC
| QueueSearch - search a queue for element matching a word field
|
| Walks a linked list from queue header at A0, comparing the word
| at offset D1 in each element against key D0.
| Entry: A0 = queue header, D0 = key value, D1 = field offset
| Exit: Z=1 if found (A0 = matching element), Z=0 if not found
QueueSearch:
    MOVE.L      D2,-(A7)                        | save D2
    MOVE.L      0x2(A0),D2                      | D2 = qHead (first element)
QSEARCH_LOOP:
    BEQ.B       QSEARCH_NOTFOUND                | nil: end of queue, not found
    MOVEA.L     D2,A0                           | A0 = current element
    CMP.W       0x0(A0,D1.W),D0                 | field at offset D1 == key?
    BEQ.B       QSEARCH_FOUND                   | yes: found it
    MOVE.L      (A0),D2                         | D2 = qLink (next element)
    BRA.B       QSEARCH_LOOP                    | continue search
QSEARCH_FOUND:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (found, Z set)
QSEARCH_RET:
    MOVE.L      (A7)+,D2                        | restore D2
    TST.W       D0                              | set CCR from result
    RTS                                         | return (Z reflects found/not)
QSEARCH_NOTFOUND:
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (not found, Z clear)
    BRA.B       QSEARCH_RET                     | return
| GETVCBRFN - find VCB by volume reference number
|
| Searches VCB queue for vcbVRefNum (offset 0x4E = 78) == D0.
| Entry: D0 = volume refNum
| Exit: A2 = VCB pointer if found, D0 = nsvErr (-35) if not
GETVCBRFN:
    MOVEM.L     D1/A0,-(A7)                     | save registers
    MOVEQ.L     #0x4E,D1                        | D1 = 0x4E (vcbVRefNum offset)
    LEA.L       (VCBQHdr_Flags).W,A0            | A0 = VCB queue header
    BSR.B       QueueSearch                     | search for refNum match
    BNE.B       GETVCBRFN_NSVERR                | not found: error
    MOVEA.L     A0,A2                           | A2 = matching VCB
GETVCBRFN_RET:
    MOVEM.L     (A7)+,D1/A0                     | restore registers
    RTS                                         | return from GETVCBRFN_RET
GETVCBRFN_NSVERR:
    MOVEQ.L     #-0x23,D0                       | D0 = nsvErr (-35): no such volume
    BRA.B       GETVCBRFN_RET                   | return error
| FindVCBDrv - find VCB by drive number or offline volume refNum
|
| Searches VCB queue for vcbDrvNum (offset 0x48) == D0, or for
| offline volumes (vcbDrvNum=0), matches vcbVRefNum (0x4A) == -D0.
| Entry: D0 = drive number (positive)
| Exit: A2 = VCB, D0 = 0 if found, D0 = nsvErr (-35) if not
FindVCBDrv:
    MOVEM.L     D1-D2,-(A7)                     | save registers
    MOVE.W      D0,D1                           | D1 = drive number to find
    MOVE.W      D0,D2                           | D2 = drive number
    NEG.W       D2                              | D2 = -drive (for offline match)
    MOVEA.L     (VCBQHdr_Head).W,A2             | A2 = first VCB in queue
FINDVCB_LOOP:
    MOVE.L      A2,D0                           | test for nil (end of queue)
    BEQ.B       FINDVCB_NSVERR                  | nil: not found
    CMP.W       0x48(A2),D1                     | vcbDrvNum == drive?
    BEQ.B       FINDVCB_FOUND                   | yes: found
    TST.W       0x48(A2)                        | vcbDrvNum == 0? (offline)
    BNE.B       FINDVCB_NEXT                    | no: skip offline check
    CMP.W       0x4A(A2),D2                     | vcbVRefNum == -drive?
    BEQ.B       FINDVCB_FOUND                   | yes: offline match
FINDVCB_NEXT:
    MOVEA.L     (A2),A2                         | A2 = next VCB (qLink)
    BRA.B       FINDVCB_LOOP                    | continue search
FINDVCB_FOUND:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (found, Z set)
FINDVCB_RET:
    MOVEM.L     (A7)+,D1-D2                     | restore registers
    RTS                                         | return from FINDVCB_RET
| ----------------------------------------------------------
|
| FINDVCB_NSVERR - VCB not found, return nsvErr
|
FINDVCB_NSVERR:
    MOVEQ.L     #-0x23,D0                       | D0 = nsvErr (-35) (no such volume)
    BRA.B       FINDVCB_RET                     | return error
| ----------------------------------------------------------
|
| ResolveWDVCB / WDCBLookup -- look up VCB by working-directory refNum
|
| WD refNums are negative (>= 0x8001 in 16-bit unsigned). The
| WDCBs table is an array of (VCB pointer, dirID, ...) records
| indexed by (WDRefNum - 0x8001). Returns A2 = VCB if found.
|
ResolveWDVCB:
    MOVEA.L     (WDCBsPtr).W,A3                 | A3 = WDCBs base ptr
    MOVEM.L     D1/A1,-(A7)                     | save D1, A1
    MOVEQ.L     #0x0,D1                         | clear D1 high word
    MOVE.W      D0,D1                           | D1 = working directory refNum
    BSR.W       HFSF_CONT_3                     | validate WD refNum range
    BNE.B       WDLOOKUP_RET                    | invalid: return error
    SUBI.W      #0x8001,D1                      | convert WD refNum to table index
    ADDA.W      D1,A3                           | A3 = WD table entry pointer
    MOVEQ.L     #-0x23,D0                       | D0 = nsvErr (-35) (assume not found)
    MOVE.L      (A3),D1                         | D1 = VCB pointer from WD entry
    BEQ.B       WDLOOKUP_RET                    | nil: WD not in use
    MOVEA.L     D1,A2                           | A2 = VCB for this working directory
    MOVEQ.L     #0x0,D0                         | D0 = noErr (found)
WDLOOKUP_RET:
    MOVEM.L     (A7)+,D1/A1                     | restore registers
    TST.W       D0                              | set CCR from result
    RTS                                         | return from WD lookup
| MARKVCB - mark volume dirty and update modification time
| Called by: SETVOLINFO_RENAME_DONE, SETVOLINFO_HFS_OK, HFSE_OK_5, CREATE_MFS_BUMP_NMFLS, HFSCATMOVE_NO_3 (and 6 more)
MARKVCB:
    BSR.B       SetVCBDirty                     | set vcbFlags dirty bit
| MARKVCBTIME - update volume modification timestamp
| Called by: HFSCATMOVE_OK_6, CC_UPD_PAR, DC_UPD_PAR, CMMOVECN_EXIT, CMRENAMECN_EXIT (and 1 more)
MARKVCBTIME:
    MOVE.L      (Time).W,0xE(A2)                | vcbLsMod = current time
    RTS                                         | return from MARKVCBTIME
| ----------------------------------------------------------
|
| SetVCBDirty - set VCB dirty flag
|
SetVCBDirty:
    ST.B        0x6(A2)                         | vcbFlags = 0xFF (bit 15 = dirty)
    RTS                                         | return from SetVCBDirty
| FLUSHMDB - flush Master Directory Block to disk
|
| Writes the in-memory VCB data back to the on-disk MDB (block 2).
| Copies VCB fields to the block buffer, including catalog and extent
| overflow file extents from their FCB entries, then releases the block
| as dirty. Clears vcbFlags dirty bit on success.
| Entry: A2 = VCB pointer
| Uses A6 as frame pointer (saves regs on A6 stack, not A7).
FLUSHMDB:
    MOVE.L      (A7)+,-(A6)                     | save return addr on A6 frame
    MOVEM.L     D0-D2/A0-A1,-(A6)               | save regs on A6 frame
    TST.B       0x6(A2)                         | vcbFlags dirty? (bit 7 set)
    BPL.W       FLUSHMDB_DONE                   | not dirty: nothing to flush
    MOVEA.L     0x54(A2),A1                     | A1 = vcbBufAdr (buffer control)
    MOVE.W      0x4E(A2),D0                     | D0 = vcbVRefNum
    MOVEQ.L     #0x0,D1                         | D1 = 0 (block 0 offset)
    MOVEQ.L     #0x2,D2                         | D2 = 2 (MDB is logical block 2)
    JSR         GETBLOCK(PC)                    | get MDB block into cache -> A0
    BNE.W       FLUSHMDB_DONE                   | I/O error: abort flush
| Copy VCB header to MDB block (162 bytes from vcb+8 to block)
    MOVEA.L     A0,A1                           | A1 = MDB block buffer
    LEA.L       0x8(A2),A0                      | A0 = VCB source (after queue header)
    MOVE.L      #0xA2,D0                        | D0 = 162 bytes (MDB header size)
    _BlockMove                                  | copy VCB header -> MDB buffer
| Copy VCB name and extra fields
    LEA.L       0x5E(A2),A0                     | A0 = vcbVN (volume name area)
    LEA.L       0x40(A1),A1                     | A1 = MDB+64 (name position)
    MOVEQ.L     #0x42,D0                        | D0 = 66 bytes (name + fields)
    _BlockMove                                  | copy volume name -> MDB
    SUBA.W      #0x40,A1                        | A1 back to MDB block start
| Copy catalog B-tree extent record from FCB
    MOVEA.L     (FCBSPtr).W,A3                  | A3 = FCB table base
    MOVE.W      0xA4(A2),D1                     | D1 = vcbCtRef (catalog FCB index)
    MOVEM.L     A0-A1,-(A7)                     | save pointers
    MOVEQ.L     #0xC,D0                         | D0 = 12 bytes (3 extent records)
    LEA.L       0x26(A3,D1.W),A0                | A0 = FCB extent record
    LEA.L       0x86(A1),A1                     | A1 = MDB+134 (catalog extents)
    _BlockMove                                  | copy catalog extents -> MDB
    MOVEM.L     (A7)+,A0-A1                     | restore pointers
    MOVE.L      0xC(A3,D1.W),D0                 | D0 = FCB physical EOF
    MOVE.L      D0,0x82(A1)                     | MDB+130 = catalog file size
    BCLR        #0x7,0x4(A3,D1.W)               | clear FCB dirty bit
    MOVE.L      0x1C(A2),D1                     | D1 = vcbAlBlkSiz
    JSR         DIVUP(PC)                       | D0 = ceil(catFileSize / blockSize)
    MOVE.W      D0,0xA0(A2)                     | vcbCtClps = catalog clump blocks
| Copy extent overflow B-tree extent record from FCB
    MOVE.W      0xA6(A2),D1                     | D1 = vcbXTRef (extents FCB index)
    MOVEM.L     A0-A1,-(A7)                     | save pointers
    MOVEQ.L     #0xC,D0                         | D0 = 12 bytes
    LEA.L       0x26(A3,D1.W),A0                | A0 = extents FCB extent record
    LEA.L       0x96(A1),A1                     | A1 = MDB+150 (extent extents)
    _BlockMove                                  | copy extent extents -> MDB
    MOVEM.L     (A7)+,A0-A1                     | restore pointers
    MOVE.L      0xC(A3,D1.W),D0                 | D0 = extents FCB physical EOF
    MOVE.L      D0,0x92(A1)                     | MDB+146 = extent file size
    BCLR        #0x7,0x4(A3,D1.W)               | clear FCB dirty bit
    MOVE.L      0x1C(A2),D1                     | D1 = vcbAlBlkSiz
    JSR         DIVUP(PC)                       | D0 = ceil(extFileSize / blockSize)
    MOVE.W      D0,0xA2(A2)                     | vcbXTClps = extent clump blocks
| Release MDB block as dirty (will be written to disk)
    MOVEQ.L     #0x1,D1                         | D1 = 1 (dirty flag)
    MOVEA.L     A1,A0                           | A0 = block buffer
    MOVEA.L     0x54(A2),A1                     | A1 = vcbBufAdr (buffer control)
    JSR         RELBLOCK(PC)                    | release block (marked dirty)
    CLR.B       0x6(A2)                         | clear vcbFlags dirty bit
FLUSHMDB_DONE:
    MOVEM.L     (A6)+,D0-D2/A0-A1               | restore regs from A6 frame
    MOVE.L      (A6)+,-(A7)                     | restore return addr from A6
    TST.W       D0                              | set CCR from result
    RTS                                         | return from FLUSHMDB
| MAKESTKPB - build a zeroed IOParam block on the stack
|
| Allocates 64 bytes (32 words) on the stack, clears them, pushes
| the return address below, and returns A0 -> the IOParam block.
| Used for building temporary I/O parameter blocks for internal calls.
MAKESTKPB:
    MOVEA.L     (A7)+,A0                        | A0 = return address (pop)
    MOVEQ.L     #0x1F,D0                        | D0 = 31 (32 words = 64 bytes)
MAKESTKPB_CLRLOOP:
    CLR.W       -(A7)                           | push zero word
    DBF.W       D0,MAKESTKPB_CLRLOOP            | loop 32 times (64 bytes)
    MOVE.L      A0,-(A7)                        | push return address back
    MOVEA.L     A7,A0                           | A0 = stack pointer
    ADDQ.W      #0x4,A0                         | A0 = IOParam block (past return addr)
    RTS                                         | return (A0 -> zeroed IOParam)
| MOUNTVOL - _MountVol trap: mount a volume on a drive
|
| Entry: A0 = IOParam, ioVRefNum (+$16) = drive number
| Attempts to mount. On volOnLinErr (-42) or extFSErr (-58),
| offlines stale volumes and retries.
MOUNTVOL:
    MOVE.W      0x16(A0),D2                     | D2 = drive number (save for retry)
    MOVEM.L     D1-D2/A0-A1,-(A7)               | save registers
    BSR.B       MOUNTVOL_CORE                   | attempt mount
    MOVEM.L     (A7)+,D1-D2/A0-A1               | restore registers
    CMPI.W      #0xFF94,D0                      | volOnLinErr (-108)?
    BEQ.B       MOUNTVOL_RETRY                  | yes: offline stale, retry
    CMPI.W      #0xFFD6,D0                      | extFSErr (-42)?
    BEQ.B       MOUNTVOL_RETRY                  | yes: retry
    RTS                                         | return (success or other error)
| MOUNTVOL_RETRY: offline stale volumes on this drive, then retry mount
MOUNTVOL_RETRY:
    MOVE.W      D2,0x16(A0)                     | restore drive number in IOParam
| Scan VCB queue for offline-but-mounted volumes to force offline
MOUNTVOL_OK:
    MOVE.L      (VCBQHdr_Head).W,D0             | D0 = first VCB in queue
MOUNTVOL_CONT:
    BEQ.B       MOUNTVOL_CONT_2                 | end of queue: retry mount
    MOVEA.L     D0,A1                           | A1 = current VCB
    TST.W       0x4C(A1)                        | vcbFSID != 0? (external FS)
    BNE.B       MOUNTVOL_SKIP                   | yes: skip external FS volumes
    MOVE.W      0x48(A1),D2                     | D2 = vcbDrvNum
    BNE.B       MOUNTVOL_OK_2                   | non-zero: volume online, check it
MOUNTVOL_SKIP:
    MOVE.L      (A1),D0                         | D0 = next VCB (qLink)
    BRA.B       MOUNTVOL_CONT                   | continue scanning
| MOUNTVOL_OK_2 - offline the online stale volume and retry
MOUNTVOL_OK_2:
    MOVE.L      A0,-(A7)                        | save IOParam
    BSR.B       MAKESTKPB                       | build temp IOParam on stack
    MOVE.W      D2,0x16(A0)                     | ioVRefNum = stale drive number
    _OffLine                                    | put volume offline
    ADDA.W      #0x40,A7                        | deallocate temp IOParam
    MOVEA.L     (A7)+,A0                        | restore original IOParam
    BNE.B       MOUNTVOL_OK                     | offline failed: scan more volumes
    BRA.B       MOUNTVOL                        | offline succeeded: retry mount
MOUNTVOL_CONT_2:
    MOVEQ.L     #-0x6C,D0                       | volNotFound (-108): no stale vols
    RTS                                         | return error
| MOUNTVOL_CORE - core mount procedure
|
| Validates drive, allocates VCB (178 bytes), reads MDB (block 2),
| validates signature, copies MDB fields to VCB, opens catalog and
| extent B-tree files. Per Inside Mac Vol II, Ch 4: File Manager.
MOUNTVOL_CORE:
    BSR.W       FSQUEUE_SETUP_SYNC              | set up FS queue for sync call
    ST.B        (NewMount).W                    | set NewMount flag
| Validate drive number and check for existing mount
MOUNTVOL_CONT_4:
    MOVEQ.L     #-0x32,D0                       | D0 = paramErr (-50)
    MOVE.W      0x16(A0),D2                     | D2 = drive number
    BLE.B       MOUNTVOL_ERR_BRA                | <= 0: invalid drive number
    MOVE.W      D2,D0                           | D0 = drive number for lookup
    BSR.W       FindVCBDrv                      | already mounted on this drive?
    BNE.B       MOUNTVOL_ALLOC_VCB              | not mounted: proceed
    TST.W       0x48(A2)                        | vcbDrvNum == 0? (offline)
    BEQ.B       MOUNTVOL_ALLOC_VCB              | offline: ok to remount
    MOVEQ.L     #-0x37,D0                       | volOnLinErr (-55): already online
MOUNTVOL_ERR_BRA:
    BRA.W       MTVOLDONE                       | exit mount with error
| Find drive and allocate VCB
MOUNTVOL_ALLOC_VCB:
    BSR.W       FINDDRIVE                       | find drive queue entry
    BNE.B       MOUNTVOL_ERR_BRA                | drive not found: error
    MOVEA.L     A0,A2                           | A2 = save drive queue entry
    MOVE.L      #0xB2,D0                        | VCBLength (178 bytes)
    _NewPtrSysClear                             | allocate zeroed VCB from system heap
    BNE.B       MOUNTVOL_ERR_BRA                | no memory: exit with error
    LEA.L       (VCBQHdr_Flags).W,A1            | A1 -> VCB queue header
    TST.L       0x2(A1)                         | QHead: is VCB queue empty?
    BNE.B       MOUNTVOL_ENQUEUE_VCB            | not empty: skip default setup
    MOVE.L      A0,(DefVCBPtr).W                | first VCB becomes default volume
    MOVEA.L     (WDCBsPtr).W,A1                 | A1 -> WDCB array
    MOVE.L      A0,0x2(A1)                      | default WDCB -> this VCB
    MOVEQ.L     #0x2,D0                         | fsRtDirID (root directory)
    MOVE.L      D0,0x6(A1)                      | WDDirID = root directory
    CLR.L       0xA(A1)                         | WDCatHint = 0 (no hint)
    CLR.L       0xE(A1)                         | WDProcID = 0
    LEA.L       (VCBQHdr_Flags).W,A1            | A1 -> VCB queue header again
MOUNTVOL_ENQUEUE_VCB:
    JSR         ENQUEUE(PC)                     | Enqueue: insert VCB into VCB queue
    EXG         A0,A2                           | A2 = new VCB, A0 = drive queue entry
    MOVE.W      D2,0x48(A2)                     | vcbDrvNum = drive number
    MOVE.W      D1,0x4A(A2)                     | vcbDRefNum = driver refNum
    MOVEA.L     (SysVolCPtr).W,A1               | system-wide volume cache
    MOVE.L      A1,0x54(A2)                     | vcbBufAdr = system cache ptr
    MOVEQ.L     #0x0,D0                         | start refNum search at 0
MOUNTVOL_CONT_5:
    SUBQ.W      #0x1,D0                         | try -1, -2, -3, ... as refNum
    MOVEM.L     D0/A2,-(A7)                     | save candidate refNum and VCB ptr
    BSR.W       GETVCBRFN                       | check if this refNum is taken
    MOVEM.L     (A7)+,D0/A2                     | restore candidate and VCB
    BEQ.B       MOUNTVOL_CONT_5                 | taken: try next candidate
    MOVE.W      D0,0x4E(A2)                     | vcbVRefNum = unique volume refNum
    CMPA.L      (DefVCBPtr).W,A2                | is this the default volume?
    BNE.B       MOUNTVOL_SKIP_2                 | no: skip default update
    MOVE.W      D0,(DefVRefNum).W               | update default volume refNum
MOUNTVOL_SKIP_2:
| mv_GetMDB: read the master directory block (block 2)
    MOVEQ.L     #0x0,D1                         | no flags
    MOVEQ.L     #0x2,D2                         | MDB is always logical block 2
    JSR         GETBLOCK(PC)                    | read MDB into block cache
    BNE.W       MTVOLER2                        | read error: release VCB and exit
    MOVEA.L     A0,A5                           | A5 = MDB buffer pointer
    MOVEQ.L     #0x2,D1                         | kRBTrash (release, don't keep)
    JSR         RELBLOCK(PC)                    | release cache block hold
    CMPI.W      #0x4244,(A5)                    | HFS signature? ('BD' = 0x4244)
    BEQ.B       MOUNTVOL_CONT_6                 | yes: HFS volume
    MOVEQ.L     #-0x39,D0                       | noMacDskErr (-57): not a Mac disk
    CMPI.W      #0xD2D7,(A5)                    | MFS signature? (0xD2D7)
    BNE.W       MTVOLER2                        | neither: not a Mac disk, exit
MOUNTVOL_CONT_6:
| mv_GotMDB: validate allocation block size
    MOVEQ.L     #-0x3C,D0                       | badMDBErr (-60): assume MDB is bad
    MOVE.L      0x14(A5),D1                     | drAlBlkSiz: allocation block size
    BEQ.W       MTVOLER1_FLUSH_CACHES           | zero: bad MDB
    ANDI.W      #0x1FF,D1                       | must be 512-byte multiple
    BNE.W       MTVOLER1_FLUSH_CACHES           | not aligned: bad MDB
| transfer MDB info into VCB
    LEA.L       0x8(A2),A1                      | dest = vcbSigWord (VCBDInfoSt)
    MOVEQ.L     #0x40,D0                        | VCBDILen (64 bytes of MDB info)
    _BlockMove                                  | copy MDB core fields to VCB
| mv_GetWPStatus: get write-protect status from driver
    MOVEA.L     (FSQHdr_Head).W,A0              | A0 -> current FS request
    MOVE.W      0x4E(A2),0x16(A0)               | return vcbVRefNum to caller
    LEA.L       (Params).W,A0                   | general-purpose param block
    MOVE.W      #0x8,0x1A(A0)                   | csCode = drvStsCode (8)
    CLR.B       0x1E(A0)                        | clear status return byte
    _Status                                     | get drive write-protect status
    MOVEQ.L     #-0x80,D0                       | 0x80 mask (bit 7)
    AND.B       0x1E(A0),D0                     | isolate write-protect bit
    MOVE.B      D0,0x13(A2)                     | vcbAtrb+1: write-protect flag
    BSR.W       TFSVCBTST                       | is it an HFS (TFS) volume?
    BNE.W       HFSE_CONT                       | MFS: do MFS-specific mount
| TFS-specific setup: copy additional HFS fields from MDB
    LEA.L       0x40(A5),A0                     | src = DrTInfoSt (HFS fields in MDB)
    LEA.L       0x5E(A2),A1                     | dest = vcbVolBkUp (VCBTDInfoSt)
    MOVEQ.L     #0x42,D0                        | VCBTDILen (66 bytes)
    _BlockMove                                  | copy additional HFS info to VCB
| compute extent and catalog B-tree allocation block counts
    MOVE.L      0x1C(A2),D1                     | vcbAlBlkSiz (allocation block size)
    MOVE.L      0x82(A5),D0                     | DrXTFlSize (extent tree PEOF)
    JSR         DIVUP(PC)                       | blocks = ceil(PEOF / alBlkSiz)
    MOVE.W      D0,0xA0(A2)                     | VCBXTAlBks = extent tree blocks
    MOVE.L      0x92(A5),D0                     | DrCTFlSize (catalog tree PEOF)
    JSR         DIVUP(PC)                       | blocks = ceil(PEOF / alBlkSiz)
    MOVE.W      D0,0xA2(A2)                     | VCBCTAlBks = catalog tree blocks
    CLR.W       0x18(A2)                        | vcbAllocPtr = 0 (reset alloc search)
    ADDQ.L      #0x1,0x64(A2)                   | vcbWrCnt++: compensate for MDB flush
| find two free FCBs for extent and catalog B-tree files
    BSR.W       FindFCB                         | FindFCB: find a free FCB
    BNE.W       MTVOLERR_CLOSE_BT               | no free FCB: error exit
    MOVE.W      D1,0xA4(A2)                     | VCBXTRef = extent tree FCB refNum
    MOVE.L      0x82(A5),0x8(A1,D1.W)           | FCBEOF = DrXTFlSize (extent LEOF)
    MOVE.L      0x82(A5),0xC(A1,D1.W)           | FCBPLen = DrXTFlSize (extent PEOF)
    MOVEQ.L     #0xC,D0                         | lenXDR (12 bytes per extent record)
    LEA.L       0x86(A5),A0                     | src = DrXTExtRec (extent tree extents)
    LEA.L       0x26(A1,D1.W),A1                | dest = FCBExtRec in extent FCB
    _BlockMove                                  | copy extent record into FCB
    BSR.W       FindFCB                         | FindFCB: find another free FCB
    BNE.W       MTVOLERR_CLOSE_BT               | no free FCB: error exit
    MOVE.W      D1,0xA6(A2)                     | VCBCTRef = catalog tree FCB refNum
    MOVE.L      0x92(A5),0x8(A1,D1.W)           | FCBEOF = DrCTFlSize (catalog LEOF)
    MOVE.L      0x92(A5),0xC(A1,D1.W)           | FCBPLen = DrCTFlSize (catalog PEOF)
    MOVEQ.L     #0xC,D0                         | lenXDR (12 bytes per extent record)
    LEA.L       0x96(A5),A0                     | src = DrCTExtRec (catalog tree extents)
    LEA.L       0x26(A1,D1.W),A1                | dest = FCBExtRec in catalog FCB
    _BlockMove                                  | copy extent record into FCB
| set up volume bitmap and control caches
    MOVE.L      (SysBMCPtr).W,0x50(A2)          | vcbMAdr = bitmap cache ptr
    MOVE.L      (SysCtlCPtr).W,0xA8(A2)         | VCBCtlBuf = control cache ptr
| set up B-tree access for extent file
    MOVE.W      0xA4(A2),D0                     | VCBXTRef (extent tree refNum)
    MOVEQ.L     #0x3,D1                         | FSXTCNID (extent tree file ID = 3)
    MOVE.L      0x68(A2),D2                     | vcbXTClpSiz (extent tree clump)
    MOVEA.L     0xA8(A2),A1                     | VCBCtlBuf (extent tree cache)
    LEA.L       FXMKEYCMP(PC),A3                | key comparison for extent tree
    BSR.W       BMCHK_CONT_8                    | AccessBT: init B-tree access
    BNE.W       MTCHKERR                        | error: abort mount
| set up B-tree access for catalog file
    MOVE.W      0xA6(A2),D0                     | VCBCTRef (catalog tree refNum)
    MOVEQ.L     #0x4,D1                         | FSCTCNID (catalog tree file ID = 4)
    MOVE.L      0x6C(A2),D2                     | vcbCTClpSiz (catalog tree clump)
    MOVEA.L     0xA8(A2),A1                     | VCBCtlBuf (catalog tree cache)
    LEA.L       CMKEYCMP(PC),A3                 | key comparison for catalog tree
    BSR.W       BMCHK_CONT_8                    | AccessBT: init B-tree access
    BNE.W       MTCHKERR                        | error: abort mount
| mark disk as inconsistent until unmount
    BCLR        #0x8,0x12(A2)                   | VCBAtVOK: was consistency bit set?
    BEQ.W       MTCHECK                         | not set: do disk consistency check
| CheckRemount: scan VCB queue for matching offline volume
CHECKREMOUNT:
    MOVE.L      (VCBQHdr_Head).W,D0             | start of VCB queue
MOUNTVOL_CONT_7:
    BEQ.W       MTVOLOK                         | end of queue: no remount found
    MOVEA.L     D0,A4                           | A4 = candidate VCB
    CMPA.L      A4,A2                           | skip our own VCB
    BEQ.B       MOUNTVOL_NO_3                   | same: next
    MOVE.W      0x8(A4),D0                      | candidate vcbSigWord
    CMP.W       0x8(A2),D0                      | same signature as new volume?
    BNE.B       MOUNTVOL_NO_3                   | no: next
    MOVE.L      0xA(A4),D0                      | candidate vcbCrDate
    CMP.L       0xA(A2),D0                      | same creation date?
    BNE.B       MOUNTVOL_NO_3                   | no: next
| compare volume names (28 bytes = 14 words)
    LEA.L       0x2C(A4),A1                     | vcbVN of candidate (old VCB)
    LEA.L       0x2C(A2),A3                     | vcbVN of new volume
    MOVEQ.L     #0xD,D0                         | 14 words to compare
MOUNTVOL_LOOP:
    CMPM.W      (A1)+,(A3)+                     | compare name words
    DBNE.W      D0,MOUNTVOL_LOOP                | loop until mismatch or done
    BNE.B       MOUNTVOL_NO_3                   | names differ: next VCB
    TST.W       (A1)                            | extra padding check
    BEQ.B       MOUNTVOL_REMOUNT_VERIFY         | match: this is a remount
| Called by: MOUNTVOL_CONT_7, MOUNTVOL_OK_3, MOUNTVOL_LOOP, MOUNTVOL_CONT_8, MOUNTVOL_MFS_DIR_LOOP (and 2 more)
MOUNTVOL_NO_3:
    MOVE.L      (A4),D0                         | qLink: next VCB in queue
    BRA.B       MOUNTVOL_CONT_7                 | keep scanning
| remount found: verify all open FCBs still match catalog
MOUNTVOL_REMOUNT_VERIFY:
    BSR.W       HFSE_CONT_14                    | Gt1stFCB: get first FCB
MOUNTVOL_CONT_8:
    CMPA.L      0x14(A1,D1.W),A4                | FCBVPtr: FCB belongs to this vol?
    BNE.W       MOUNTVOL_REMOUNT_NEXT_FCB       | no: skip to next FCB
    BSR.W       TFSVCBTST                       | HFS volume?
    BEQ.B       MOUNTVOL_OK_3                   | yes: verify via catalog lookup
| MFS remount verification: check file in MFS directory
    MOVE.W      0x1C(A1,D1.W),D3                | start block from FCB
    BSR.W       FILEWRITE_NO_4                  | read MFS directory block
    BNE.B       MOUNTVOL_NO_3                   | error: skip this FCB
    MOVEQ.L     #0x0,D0                         | initial directory offset
    MOVE.L      0x0(A1,D1.W),D3                 | FCBFlNm (file number from FCB)
MOUNTVOL_MFS_DIR_LOOP:
    CMP.L       0x12(A5,D0.W),D3                | match directory file number?
    BEQ.B       MOUNTVOL_FOUND_2                | found: verify fork info
    BSR.W       CREATE_NEXT                     | next MFS directory entry
    BCS.B       MOUNTVOL_MFS_DIR_LOOP           | more entries: keep scanning
    BRA.B       MOUNTVOL_NO_3                   | not found: skip
MOUNTVOL_FOUND_2:
    LEA.L       0x16(A5,D0.W),A3                | data fork info in directory
    BTST        #0x1,0x4(A1,D1.W)               | FCBRscBit: resource fork?
    BEQ.B       MOUNTVOL_NO_4                   | no: use data fork
    LEA.L       0x20(A5,D0.W),A3                | resource fork info in directory
MOUNTVOL_NO_4:
    MOVE.W      (A3)+,D0                        | start block from directory
    CMP.W       0x6(A1,D1.W),D0                 | match FCBStBlk?
    BNE.B       MOUNTVOL_NO_3                   | mismatch: skip
    MOVE.L      (A3)+,D0                        | logical EOF from directory
    BRA.B       MOUNTVOL_NO_5                   | check against FCB LEOF
| HFS/TFS remount verification: look up catalog record
MOUNTVOL_OK_3:
    MOVE.L      0x0(A1,D1.W),D0                 | FCBFlNm (file number)
    CMPI.L      #0x10,D0                        | system file? (CNID < 16)
    BCS.B       MOUNTVOL_REMOUNT_NEXT_FCB       | yes: skip verification
    MOVEM.L     D2/A0-A1,-(A6)                  | save regs across catalog call
    MOVE.L      0x3A(A1,D1.W),D0                | FCBDirID (parent directory)
    LEA.L       0x3E(A1,D1.W),A0                | ptr to FCBCName
    MOVEQ.L     #0x0,D2                         | no catalog hint
    JSR         CMGETCN(PC)                     | CMGetCN: look up catalog record
    MOVEA.L     A1,A3                           | A3 = catalog data record
    MOVEM.L     (A6)+,D2/A0-A1                  | restore regs
    BNE.B       MOUNTVOL_NO_3                   | not found: skip
    CMPI.B      #0x2,(A3)                       | cdrFilRec (file record)?
    BNE.B       MOUNTVOL_NO_3                   | no: skip
    MOVE.L      0x1A(A3),D0                     | filLgLen (data fork LEOF)
    BTST        #0x1,0x4(A1,D1.W)               | FCBRscBit: resource fork?
    BEQ.B       MOUNTVOL_NO_5                   | no: compare data LEOF
    MOVE.L      0x24(A3),D0                     | filRLgLen (resource fork LEOF)
MOUNTVOL_NO_5:
    CMP.L       0x8(A1,D1.W),D0                 | compare with FCBEOF (logical EOF)
    BNE.W       MOUNTVOL_NO_3                   | mismatch: error
MOUNTVOL_REMOUNT_NEXT_FCB:
    BSR.W       HFSE_NEXT                       | GtNxtFCB: get next FCB
    BCS.W       MOUNTVOL_CONT_8                 | more FCBs: keep verifying
| all FCBs verified: transfer mount to existing VCB
    CLR.B       (NewMount).W                    | not a new mount (remount)
    MOVE.W      0x4E(A4),D1                     | D1 = old VCB's vcbVRefNum
| copy new VCB data into old VCB
    LEA.L       0x8(A2),A0                      | src = new VCB vcbSigWord
    LEA.L       0x8(A4),A1                      | dest = old VCB vcbSigWord
    MOVEQ.L     #0x56,D0                        | MFS VCB copy size (86 bytes)
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       MOUNTVOL_NO_6                   | no: use MFS size
    MOVE.W      #0xAA,D0                        | HFS VCB copy size (170 bytes)
MOUNTVOL_NO_6:
    _BlockMove                                  | copy VCB data to old VCB
    MOVE.W      D1,0x4E(A4)                     | restore old VCB's vcbVRefNum
| update B-tree FCB volume pointers for HFS
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       MOUNTVOL_DEQUEUE_NEW_VCB        | no: skip FCB update
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array
    MOVE.W      0xA4(A2),D0                     | VCBXTRef (extent tree refNum)
    MOVE.L      A4,0x14(A1,D0.W)                | point extent FCB to old VCB
    MOVE.W      0xA6(A2),D0                     | VCBCTRef (catalog tree refNum)
    MOVE.L      A4,0x14(A1,D0.W)                | point catalog FCB to old VCB
| dequeue and dispose the new VCB (keep old one)
MOUNTVOL_DEQUEUE_NEW_VCB:
    BSR.W       OFFLINE_CONT                    | close B-tree files on new VCB
    MOVEA.L     A2,A0                           | A0 = new VCB (to dispose)
    MOVEA.L     A4,A2                           | A2 = old VCB (to keep)
    LEA.L       (VCBQHdr_Flags).W,A1            | VCB queue header
    JSR         DEQUEUE(PC)                     | remove new VCB from queue
    _DisposePtr                                 | free new VCB memory
    MOVEA.L     (FSQHdr_Head).W,A0              | A0 -> current FS request
    MOVE.W      0x4E(A2),0x16(A0)               | return vcbVRefNum to caller
| MtVolOK: mount succeeded
MTVOLOK:
    MOVEQ.L     #0x0,D0                         | no error
| MtVolDone: check if MDB needs flushing
MTVOLDONE:
    TST.W       D0                              | any errors?
    BNE.B       MTVOLDONE_EXIT                  | yes: skip MDB flush
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       MTVOLDONE_EXIT                  | MFS: skip MDB flush
    BTST        #0x7,0x13(A2)                   | VCBWrProt: write-protected?
    BNE.B       MTVOLDONE_EXIT                  | yes: can't flush
    BSR.W       SetVCBDirty                     | mark VCB as dirty
    BSR.W       FLUSHMDB                        | write MDB to disk
MTVOLDONE_EXIT:
    BRA.W       FSQUEUE_DONE                    | CmdDone: complete FS operation
| MtChkErr: B-tree open errors during mount
| Called by: MOUNTVOL_CONT_6, MTCHECK, MTCHECK_RENAME_FROM_VCB, MTCHECK_RENAME_FROM_CAT, MOUNTVOL_FOUND_3 (and 4 more)
MTCHKERR:
    MOVE.W      D0,(HFSDSErr).W                 | save HFS error for debugging
    MOVEQ.L     #-0x3C,D0                       | badMDBErr (-60)
| MtVolErr: close any opened B-tree files
MTVOLERR_CLOSE_BT:
    BSR.W       BMCHK_CONT                      | close extent/catalog B-trees
| MtVolEr1: flush and trash volume caches
MTVOLER1_FLUSH_CACHES:
    BSR.W       BMCHK_CONT_4                    | flush and trash caches
| MtVolEr2: release VCB and exit
MTVOLER2:
    TST.B       (NewMount).W                    | is this a new mount?
    BEQ.B       MOUNTVOL_NO_8                   | no (remount): keep old VCB
    BSR.W       BMCHK_CONT_2                    | dequeue and dispose new VCB
MOUNTVOL_CONT_10:
    TST.W       D0                              | check error code
    BLE.W       FSQUEUE_DONE                    | error or success: CmdDone
    MOVEA.L     (FSQHdr_Head).W,A0              | retry with next drive
    BRA.W       MOUNTVOL_CONT_4                 | loop back to mount start
| remount error: clear TFS-specific fields in old VCB
MOUNTVOL_NO_8:
    ADDA.W      #0x48,A2                        | advance to vcbDrvNum area
    MOVE.W      (A2),D3                         | save vcbDrvNum
    CLR.W       (A2)+                           | clear vcbDrvNum (take offline)
    MOVE.W      D3,(A2)+                        | vcbDRefNum = saved drive num
    ADDQ.W      #0x4,A2                         | skip vcbFSID + vcbVRefNum
    CLR.L       (A2)+                           | clear vcbMAdr (bitmap cache)
    CLR.L       (A2)+                           | clear vcbBufAdr (volume cache)
    BRA.B       MOUNTVOL_CONT_10                | check error and exit
| MtCheck: disk consistency check (first mount after unclean shutdown)
MTCHECK:
    MOVEQ.L     #0x2,D0                         | root DirID (fsRtDirID = 2)
    MOVEQ.L     #0x0,D2                         | no catalog hint
    MOVEA.L     D2,A0                           | no CName (get thread record)
    JSR         CMGETCN(PC)                     | locate root directory record
    BNE.B       MTCHKERR                        | error: abort mount
| check if volume name in catalog matches VCB
    MOVEQ.L     #0x0,D0                         | clear for CmpString param
    LEA.L       0x6(A0),A1                      | ptr to ckrCName in catalog key
    MOVE.B      (A1)+,D0                        | catalog name length
    SWAP.W      D0                              | move to high word
    LEA.L       0x2C(A2),A0                     | vcbVN (volume name in VCB)
    MOVE.B      (A0)+,D0                        | VCB name length
    SWAP.W      D0                              | both lengths now in D0
    _CmpStringCaseMarks                         | compare names (case-insensitive)
    BEQ.B       MOUNTVOL_FOUND_3                | names match: proceed
| volume name changed: rename root directory to match VCB
    SUBQ.L      #0x1,A1                         | back up to include length byte
    SUBQ.L      #0x1,A0                         | back up VCB name ptr
    MOVEQ.L     #0x0,D0                         | clear for length
    MOVE.B      (A0),D0                         | VCB volume name length
    BEQ.B       MTCHECK_RENAME_FROM_CAT         | empty name: try catalog name
    CMPI.W      #0x1B,D0                        | max 27 chars? (HFS name limit)
    BLE.B       MTCHECK_RENAME_FROM_VCB         | ok: use as-is
    MOVE.B      #0x1B,(A0)                      | truncate to 27 chars
MTCHECK_RENAME_FROM_VCB:
    MOVEQ.L     #0x2,D0                         | root DirID
    MOVEA.L     A0,A1                           | new name = VCB volume name
    SUBA.L      A0,A0                           | no old name (use thread)
    MOVEQ.L     #0x0,D2                         | no catalog hint
    JSR         CMRENAMECN(PC)                  | rename root directory
    BNE.B       MTCHKERR                        | error: abort
    BRA.B       MOUNTVOL_FOUND_3                | continue with mount
| VCB name empty: use catalog name to rename
MTCHECK_RENAME_FROM_CAT:
    MOVEQ.L     #0x0,D0                         | clear for length
    MOVE.B      (A1),D0                         | catalog name length
    BEQ.W       MTCHKERR                        | both empty: error
    CMPI.W      #0x1B,D0                        | max 27 chars?
    BLE.B       MTCHECK_NAME_TRUNC_OK           | ok: use as-is
    MOVEQ.L     #0x1B,D0                        | truncate to 27 chars
MTCHECK_NAME_TRUNC_OK:
    MOVE.B      D0,(A0)+                        | set VCB name length byte
    SUBQ.W      #0x1,D0                         | D0 = byte count - 1 for DBF
    ADDQ.L      #0x1,A1                         | skip catalog name length byte
MTCHECK_COPY_NAME_LOOP:
    MOVE.B      (A1)+,(A0)+                     | copy catalog name to VCB
    DBF.W       D0,MTCHECK_COPY_NAME_LOOP       | loop for all name chars
| verify bitmap for extent and catalog B-tree files
MOUNTVOL_FOUND_3:
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array base
    MOVE.W      0xA4(A2),D1                     | VCBXTRef (extent tree refNum)
    LEA.L       0x26(A1,D1.W),A0                | extent FCB's FCBExtRec
    BSR.W       P_BMChk                         | verify bitmap for extent tree
    MOVE.W      0xA6(A2),D1                     | VCBCTRef (catalog tree refNum)
    LEA.L       0x26(A1,D1.W),A0                | catalog FCB's FCBExtRec
    BSR.W       P_BMChk                         | verify bitmap for catalog tree
| scan catalog to count files and directories
    MOVEQ.L     #0x2,D0                         | root DirID (fsRtDirID = 2)
    SUBA.L      A0,A0                           | no CName
    JSR         CMGETCN(PC)                     | get root directory record
    BNE.W       MTCHKERR                        | error: abort mount
| calculate max catalog leaf records for scan limit
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array
    MOVE.W      0xA6(A2),D1                     | VCBCTRef (catalog tree refNum)
    MOVE.L      0xC(A1,D1.W),D0                 | catalog FCBPLen (PEOF)
    MOVEQ.L     #0x46,D1                        | lendir (70 bytes per dir record)
    BSR.W       DIVUP                           | approximate max record count
    MOVE.L      D0,D2                           | D2 = records left to scan
| initialize counters for consistency check
    MOVEQ.L     #0xF,D4                         | D4 = max CNID seen (init 15)
    MOVEQ.L     #0x0,D3                         | D3 = VCB-modified flag
    MOVEQ.L     #0x0,D5                         | D5 = total file count
    MOVEQ.L     #0x0,D6                         | D6 = total directory count
    MOVEQ.L     #0x0,D7                         | D7 = root file + dir counts
| catalog scan loop: count files, directories, verify bitmaps
MOUNTVOL_SKIP_5:
    SUBQ.L      #0x1,D2                         | more records to scan?
    BLT.W       MTCHKERR                        | ran out of records: error
    MOVE.W      0xA6(A2),D0                     | VCBCTRef (catalog tree refNum)
    MOVEQ.L     #0x1,D1                         | selection = next record
    MOVE.L      D2,-(A6)                        | save remaining count
    JSR         BTGETRECORD(PC)                 | BTGetRecord: get next catalog record
    MOVE.L      (A6)+,D2                        | restore remaining count
    TST.W       D0                              | any error?
    BNE.B       MTCHECK_SCAN_DONE               | yes (end of catalog?)
| check record type: directory or file?
    CMPI.B      #0x1,(A1)                       | cdrDirRec (directory record)?
    BNE.B       MOUNTVOL_NO_10                  | no: check if file
    ADDQ.L      #0x1,D6                         | bump total directory count
    CMPI.L      #0x2,0x2(A0)                    | in root? (ckrParID == fsRtDirID)
    BNE.B       MOUNTVOL_NO_9                   | no: skip root count
    SWAP.W      D7                              | root dir count in low word
    ADDQ.W      #0x1,D7                         | bump root directory count
    SWAP.W      D7                              | restore file count in low
MOUNTVOL_NO_9:
    CMP.L       0x6(A1),D4                      | track max CNID (dirDirID)
    BCC.B       MOUNTVOL_SKIP_5                 | D4 >= dirID: no update
    MOVE.L      0x6(A1),D4                      | update max CNID seen
    BRA.B       MOUNTVOL_SKIP_5                 | continue scan
| file record
MOUNTVOL_NO_10:
    CMPI.B      #0x2,(A1)                       | cdrFilRec (file record)?
    BNE.B       MOUNTVOL_SKIP_5                 | no (thread record): skip
    ADDQ.L      #0x1,D5                         | bump total file count
    CMPI.L      #0x2,0x2(A0)                    | in root? (ckrParID == fsRtDirID)
    BNE.B       MOUNTVOL_NO_11                  | no: skip root count
    ADDQ.W      #0x1,D7                         | bump root file count (low word)
MOUNTVOL_NO_11:
    CMP.L       0x14(A1),D4                     | track max CNID (filFlNum)
    BCC.B       MOUNTVOL_NO_12                  | D4 >= fileNum: no update
    MOVE.L      0x14(A1),D4                     | update max CNID seen
MOUNTVOL_NO_12:
    LEA.L       0x4A(A1),A0                     | filExtRec (data fork extents)
    BSR.W       P_BMChk                         | verify bitmap for data fork
    LEA.L       0x56(A1),A0                     | filRExtRec (rsrc fork extents)
    BSR.W       P_BMChk                         | verify bitmap for rsrc fork
    BRA.B       MOUNTVOL_SKIP_5                 | continue scan
| scan complete: update VCB counters if needed
MTCHECK_SCAN_DONE:
    CMPI.W      #0x20,D0                        | BTnotfound (end of catalog)?
    BNE.W       MTCHKERR                        | other error: abort
| fix up vcbNxtCNID if needed
    CMP.L       0x26(A2),D4                     | max CNID >= vcbNxtCNID?
    BCS.B       MOUNTVOL_OK_5                   | no: vcbNxtCNID is ok
    ADDQ.L      #0x1,D4                         | max + 1 = new next CNID
    MOVE.L      D4,0x26(A2)                     | update vcbNxtCNID
    BSET        #0x0,0x13(A2)                   | mark VCB dirty
    MOVEQ.L     #-0x1,D3                        | flag: something changed
| compare counted values against VCB
MOUNTVOL_OK_5:
    CMP.L       0x72(A2),D5                     | vcbFilCnt matches file count?
    BEQ.B       MOUNTVOL_OK_6                   | yes: ok
    MOVE.L      D5,0x72(A2)                     | fix vcbFilCnt
    BSET        #0x1,0x13(A2)                   | mark VCB dirty
    MOVEQ.L     #-0x1,D3                        | flag: VCB was modified
MOUNTVOL_OK_6:
    CMP.L       0x76(A2),D6                     | vcbDirCnt matches dir count?
    BEQ.B       MOUNTVOL_OK_7                   | yes: ok
    MOVE.L      D6,0x76(A2)                     | fix vcbDirCnt
    BSET        #0x1,0x13(A2)                   | mark VCB dirty
    MOVEQ.L     #-0x1,D3                        | flag: VCB was modified
MOUNTVOL_OK_7:
    CMP.W       0x14(A2),D7                     | vcbNmFls matches root files?
    BEQ.B       MOUNTVOL_OK_8                   | yes: ok
    MOVE.W      D7,0x14(A2)                     | fix vcbNmFls
    BSET        #0x1,0x13(A2)                   | mark VCB dirty
    MOVEQ.L     #-0x1,D3                        | flag: VCB was modified
MOUNTVOL_OK_8:
    SWAP.W      D7                              | root dir count now in low word
    CMP.W       0x70(A2),D7                     | vcbNmRtDirs matches?
    BEQ.B       MOUNTVOL_OK_9                   | yes: ok
    MOVE.W      D7,0x70(A2)                     | fix vcbNmRtDirs
    BSET        #0x1,0x13(A2)                   | mark VCB dirty
    MOVEQ.L     #-0x1,D3                        | flag: VCB was modified
| now scan extent overflow file to verify those bitmaps too
MOUNTVOL_OK_9:
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array
    MOVE.W      0xA4(A2),D1                     | VCBXTRef (extent tree refNum)
    MOVE.L      0xC(A1,D1.W),D0                 | extent FCBPLen (PEOF)
    MOVEQ.L     #0xC,D1                         | lenxdr (12 bytes per extent rec)
    BSR.W       DIVUP                           | max extent records to scan
    MOVE.L      D0,D5                           | D5 = extent record scan limit
| position to start of extent file
    MOVE.W      0xA4(A2),D0                     | extent tree refNum
    SUBQ.W      #0x8,A6                         | allocate key buffer on A6 stack
    MOVEA.L     A6,A0                           | A0 = extent key buffer
    MOVE.W      #0x700,(A0)                     | key length = 7 (lenxkr-1)
    CLR.L       0x2(A0)                         | file number = 0 (search from start)
    CLR.W       0x6(A0)                         | FABN = 0
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         BTSEARCH(PC)                    | BTSearch: position at extent start
    ADDQ.W      #0x8,A6                         | deallocate key buffer
    MOVEQ.L     #0x0,D1                         | selection = current record
| extent file scan loop
MOUNTVOL_CONT_11:
    SUBQ.L      #0x1,D5                         | more records to scan?
    BLT.W       MTCHKERR                        | ran out: error
    MOVE.W      0xA4(A2),D0                     | extent tree refNum
    JSR         BTGETRECORD(PC)                 | BTGetRecord: get next extent
    BNE.B       MTCHECK_EXT_SCAN_DONE           | end of file?
    MOVEA.L     A1,A0                           | A0 = extent record for BlkChk
    BSR.B       P_BMChk                         | verify bitmap for these extents
    MOVEQ.L     #0x1,D1                         | selection = next record
    BRA.B       MOUNTVOL_CONT_11                | continue scan
| extent scan done: recount free blocks
MTCHECK_EXT_SCAN_DONE:
    CMPI.W      #0x20,D0                        | BTnotfound (end of extent file)?
    BNE.W       MTCHKERR                        | other error: abort
    JSR         UPDATEFREE(PC)                  | recount free blocks from bitmap
    BRA.W       CHECKREMOUNT                    | go to CheckRemount
| BMChk: wrapper for BlkChk that checks write-protect first
| Called by: MOUNTVOL_FOUND_3, MOUNTVOL_NO_12, MOUNTVOL_CONT_11
P_BMChk:
    MOVE.L      (0x7C0).W,-(A7)                 | indirect jump to VBMCHK via vector
    RTS                                         | jump via return to vector target
VBMCHK:
    MOVE.L      (A7)+,-(A6)                     | save return addr on A6 stack
    BSR.W       SETVOLINFO_HFS_CONT_3           | check volume write protect
    BNE.B       BMCHK_SKIP                      | write-protected: skip check
    JSR         BLKCHK(PC)                      | verify bitmap for extent record
    BEQ.B       BMCHK_SKIP                      | all ok: continue
    MOVEQ.L     #-0x1,D3                        | flag: bitmap inconsistency
    BSET        #0x2,0x13(A2)                   | mark VCB bitmap dirty
BMCHK_SKIP:
    MOVE.L      (A6)+,-(A7)                     | restore return addr to stack
    RTS                                         | return from bitmap check
| ----------------------------------------------------------
|
| BMCHK_CONT - close extent and catalog B-tree FCBs (mark as free)
|
BMCHK_CONT:
    MOVEM.L     D0-D1/A1,-(A7)                  | save regs
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array
    MOVE.W      0xA4(A2),D1                     | VCBXTRef (extent tree refNum)
    BEQ.B       BMCHK_EMPTY                     | none: skip
    CLR.L       0x0(A1,D1.W)                    | mark extent FCB as free
BMCHK_EMPTY:
    MOVE.W      0xA6(A2),D1                     | VCBCTRef (catalog tree refNum)
    BEQ.B       BMCHK_EMPTY_2                   | none: skip
    CLR.L       0x0(A1,D1.W)                    | mark catalog FCB as free
BMCHK_EMPTY_2:
    MOVEM.L     (A7)+,D0-D1/A1                  | restore regs
    RTS                                         | return from BMCHK_CONT
| BMCHK_CONT_2: dequeue VCB, close all FCBs, dispose VCB
BMCHK_CONT_2:
    MOVE.L      D0,-(A7)                        | save error code
    BSR.W       CREATE_CONT_12                  | Gt1stFCB: get first FCB
BMCHK_CONT_3:
    BNE.B       BMCHK_NO                        | no more FCBs: done
    CLR.L       0x0(A1,D1.W)                    | clear FCBFlNm (mark free)
    CLR.L       0x4(A1,D1.W)                    | clear FCBFlags
    BSR.W       CREATE_NEXT_2                   | GtNxtFCB for this volume
    BRA.B       BMCHK_CONT_3                    | loop all FCBs
BMCHK_NO:
    MOVEA.L     A2,A0                           | A0 = VCB to dispose
    LEA.L       (VCBQHdr_Flags).W,A1            | VCB queue header
    JSR         DEQUEUE(PC)                     | remove VCB from queue
    CMPA.L      (DefVCBPtr).W,A2                | was this the default volume?
    BNE.B       BMCHK_NO_2                      | no: skip
    CLR.L       (DefVCBPtr).W                   | clear default VCB ptr
    CLR.W       (DefVRefNum).W                  | clear default volume refNum
BMCHK_NO_2:
    _DisposePtr                                 | free VCB memory
    MOVE.L      (A7)+,D0                        | restore error code
    RTS                                         | return from BMCHK_CONT_2
| BMCHK_CONT_4: trash all volume caches (bitmap, vol, control)
BMCHK_CONT_4:
    MOVE.L      A1,-(A7)                        | save A1
    MOVEA.L     (SysBMCPtr).W,A1                | bitmap cache
    JSR         TRASHVBLKS(PC)                  | trash bitmap cache blocks
    MOVEA.L     (SysVolCPtr).W,A1               | volume cache
    JSR         TRASHVBLKS(PC)                  | trash volume cache blocks
    MOVEA.L     (SysCtlCPtr).W,A1               | control cache
    JSR         TRASHVBLKS(PC)                  | trash control cache blocks
    MOVEA.L     (A7)+,A1                        | restore A1
    RTS                                         | return from BMCHK_CONT_4
| FindFCB: find a free FCB and reserve it
| Returns: D1=FCB offset, A1=FCB array base, D0=0 on success
FindFCB:
    BSR.W       HFSE_CONT_14                    | Gt1stFCB: get first FCB
    BRA.B       FindFCB_NEXT                    | start scanning
BMCHK_CONT_6:
    TST.L       0x0(A1,D1.W)                    | FCBFlNm: is this FCB free?
    BNE.B       FindFCB_NEXT                    | no: try next
    MOVEQ.L     #-0x1,D0                        | mark as reserved (FCBFlNm=-1)
    MOVE.L      D0,0x0(A1,D1.W)                 | reserve this FCB
    MOVEQ.L     #0x0,D0                         | success
    BRA.B       BMCHK_CONT_7                    | return with D0=0
FindFCB_NEXT:
    BSR.W       HFSE_NEXT                       | GtNxtFCB: next FCB
    BCS.B       BMCHK_CONT_6                    | more FCBs: check next
    MOVEQ.L     #-0x2A,D0                       | tmfoErr (-42): too many files open
BMCHK_CONT_7:
    RTS                                         | return from FindFCB
| ----------------------------------------------------------
|
| BMCHK_CONT_8 - AccessBT: set up access to a B*-Tree file
| D0=refnum, D1=file ID, D2=clump size, A1=cache, A3=key compare routine
|
BMCHK_CONT_8:
    MOVE.L      (A7)+,-(A6)                     | save return addr on A6 stack
    MOVEM.L     D3/A0,-(A6)                     | save regs
    MOVEA.L     (FCBSPtr).W,A0                  | FCB array
    LEA.L       0x0(A0,D0.W),A0                 | A0 = this FCB entry
    CLR.W       0x4(A0)                         | FCBMdRByt = 0 (access mode)
    CLR.W       0x6(A0)                         | FCBStBlk = 0
    CLR.L       0x10(A0)                        | FCBBfAdr = 0 (buffer)
    MOVE.L      D1,(A0)                         | FCBFlNm = file ID (3 or 4)
    MOVE.L      A2,0x14(A0)                     | FCBVPtr = VCB pointer
    MOVE.L      D2,0x1E(A0)                     | FCBClmpSiz = clump size
    MOVEA.L     A3,A0                           | A0 = key comparison routine
    JSR         BTOPEN(PC)                      | BTOpen: open B-tree file
    MOVEM.L     (A6)+,D3/A0                     | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return addr to stack
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from AccessBT
| FindDrive: find drive queue entry by drive number
| D2=drive number, returns A3=drive entry, D1=driver refNum, D0=error
FINDDRIVE:
    MOVE.L      A0,-(A7)                        | save A0
    MOVE.W      D2,D0                           | D0 = drive number to find
    LEA.L       (DrvQHdr_Flags).W,A0            | drive queue header
    MOVEQ.L     #0x6,D1                         | offset to dqDrive in DQE
    BSR.W       QueueSearch                     | search queue by field match
    BNE.B       FINDDRIVE_FOUND                 | not found: error
    MOVEA.L     A0,A3                           | A3 = drive queue entry
    MOVE.W      0x8(A0),D1                      | dqRefNum (driver refNum)
    MOVE.W      0xA(A0),D0                      | dqFSID (external FS ID)
    BEQ.B       FINDDRIVE_EMPTY                 | zero: native FS, ok
    MOVEQ.L     #-0x3A,D0                       | extFSErr (-58): external FS
FINDDRIVE_EMPTY:
    MOVEA.L     (A7)+,A0                        | restore A0
    RTS                                         | return from FindDrive
FINDDRIVE_FOUND:
    MOVEQ.L     #-0x38,D0                       | nsDrvErr (-56): no such drive
    BRA.B       FINDDRIVE_EMPTY                 | return with error
| _OffLine: take volume offline without ejecting disk
OFFLINE:
    ST.B        (NoEject).W                     | suppress physical disk eject
    BRA.W       EJECT_OFFLINE_JOIN              | join Eject path
| ----------------------------------------------------------
|
| OFFLINE_CONT
|
| close B-tree files on the VCB (unmount path)
OFFLINE_CONT:
    MOVE.L      (A7)+,-(A6)                     | save return addr on A6 stack
    MOVEM.L     D1-D2/A1,-(A6)                  | save regs
    CLR.B       (FlushOnly).W                   | full close (not just flush)
    BRA.B       OFFLINE_SKIP_2                  | go to cache flush
| OFFLINE_CONT_2: flush or close B-tree files for volume
OFFLINE_CONT_2:
    MOVE.L      (A7)+,-(A6)                     | save return addr on A6 stack
    MOVEM.L     D1-D2/A1,-(A6)                  | save regs
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       OFFLINE_SKIP_2                  | MFS: skip B-tree close
    TST.B       (FlushOnly).W                   | flush-only mode?
    BNE.B       OFFLINE_SKIP                    | yes: skip consistency mark
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       OFFLINE_SKIP                    | write-protected: skip
    BSET        #0x8,0x12(A2)                   | VCBAtVOK: mark consistent
    BSR.W       SetVCBDirty                     | mark VCB dirty for flush
OFFLINE_SKIP:
    JSR         FLUSHMDB(PC)                    | flush MDB to disk
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array
    MOVE.W      0xA6(A2),D1                     | VCBCTRef (catalog tree)
    BSR.W       FILECLOSE_CONT_3                | flush/close catalog B-tree
    BNE.B       OFFLINE_ERR                     | error: abort
    TST.B       (FlushOnly).W                   | flush only?
    BNE.B       OFFLINE_CONT_3                  | yes: don't clear refNum
    CLR.W       0xA6(A2)                        | clear VCBCTRef (closed)
OFFLINE_CONT_3:
    MOVE.W      0xA4(A2),D1                     | VCBXTRef (extent tree)
    BSR.W       FILECLOSE_CONT_3                | flush/close extent B-tree
    BNE.B       OFFLINE_ERR                     | error: abort
    TST.B       (FlushOnly).W                   | flush only?
    BNE.B       OFFLINE_SKIP_2                  | yes: don't clear refNum
    CLR.W       0xA6(A2)                        | clear VCBXTRef (closed)
| flush all volume caches for this volume
OFFLINE_SKIP_2:
    MOVEQ.L     #0x0,D1                         | no flags
    ST.B        (SysCRefCnt).W                  | set cache reference count flag
    MOVEA.L     (SysBMCPtr).W,A1                | bitmap cache
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum
    JSR         FLUSHCACHE(PC)                  | flush bitmap cache
    MOVEA.L     (SysCtlCPtr).W,A1               | control cache
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum
    JSR         FLUSHCACHE(PC)                  | flush control cache
    MOVEA.L     (SysVolCPtr).W,A1               | volume cache
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum
    JSR         FLUSHCACHE(PC)                  | flush volume cache
    TST.B       (FlushOnly).W                   | flush only?
    BNE.B       OFFLINE_OK                      | yes: don't trash caches
    BSR.W       BMCHK_CONT_4                    | trash all volume caches
OFFLINE_OK:
    MOVEQ.L     #0x0,D0                         | no error
OFFLINE_ERR:
    MOVEM.L     (A6)+,D1-D2/A1                  | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return addr
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from OFFLINE_CONT
| _Eject: eject disk and take volume offline
EJECT:
    CLR.B       (NoEject).W                     | allow physical disk eject
EJECT_OFFLINE_JOIN:
    BSR.W       FSQUEUE_SETUP_SYNC              | FSQueue: wait our turn
    BSR.W       P_DTRMV3                        | resolve volume from param block
    BNE.B       EJECT_FOUND                     | error: unknown volume
    BSR.W       P_CKExtFS                       | external file system?
    BNE.B       EJECT_DONE                      | yes: let extFS handle it
    BRA.B       EJECT_FOUND_2                   | native: do eject
| ----------------------------------------------------------
|
| EJECT_FOUND
|
| volume not found by name: try by drive number
EJECT_FOUND:
    MOVE.W      0x16(A0),D2                     | ioVRefNum as drive number
EJECT_CONT_2:
    BSR.W       FINDDRIVE                       | find drive queue entry
    BNE.B       EJECT_DONE                      | drive not found: done
    TST.B       (NoEject).W                     | offline-only mode?
    BEQ.W       EJECT_NO_3                      | no: go to eject driver call
| Called by: EJECT_FOUND_2, EJECT_OFFLINE_JOIN, EJECT_CONT_2, EJECT_OK, EJECT_NO_2
EJECT_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| EJECT_FOUND_2
|
| volume found: get drive number from VCB
EJECT_FOUND_2:
    LEA.L       0x48(A2),A1                     | A1 -> vcbDrvNum
    MOVE.W      (A1),D2                         | vcbDrvNum
    BNE.B       EJECT_OK                        | online: proceed
    MOVE.W      0x2(A1),D2                      | vcbDRefNum (offline: negated drive)
    BPL.B       EJECT_DONE                      | positive refNum: not offline, done
    TST.B       (NoEject).W                     | offline-only mode?
    BNE.B       EJECT_DONE                      | yes: already offline, done
    NEG.W       D2                              | un-negate drive number
    NEG.W       0x2(A1)                         | un-negate in VCB too
    BRA.B       EJECT_CONT_2                    | try to find and eject drive
| ----------------------------------------------------------
|
| EJECT_OK
|
| volume is online: check drive type and flush
EJECT_OK:
    BSR.W       FINDDRIVE                       | find drive queue entry
    BNE.B       EJECT_DONE                      | not found: done
    TST.B       (NoEject).W                     | already in offline-only mode?
    BNE.B       EJECT_OK_2                      | yes: skip drive type check
    CMPI.B      #0x8,-0x3(A3)                   | drive type >= 8 (HD20/SCSI)?
    BLT.B       EJECT_OK_2                      | no: ejectable floppy
    ST.B        (NoEject).W                     | non-ejectable: suppress eject
    CMPI.B      #0x40,-0x3(A3)                  | drive type >= 64 (SCSI disk)?
    BLT.B       EJECT_OK_2                      | no: keep suppress flag
    MOVE.B      #0x1,(NoEject).W                | SCSI: soft offline (re-enqueue)
EJECT_OK_2:
    ST.B        (FlushOnly).W                   | first pass: flush only
    BSR.B       UNMOUNTVOL_CONT                 | flush all open files on volume
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       EJECT_MFS_PATH                  | MFS: skip B-tree close
    CLR.B       (FlushOnly).W                   | full close for B-trees
    BSR.W       OFFLINE_CONT_2                  | flush/close B-trees + caches
    BRA.B       EJECT_CONT_3                    | mark volume offline
EJECT_MFS_PATH:
    BSR.W       HFSE_CONT_9                     | MFS: flush MFS directory
    BSR.W       HFSE_CONT_2                     | flush MFS allocation map
    BSR.W       BMCHK_CONT_4                    | trash all caches
| mark volume as offline
EJECT_CONT_3:
    CLR.W       (A1)+                           | clear vcbDrvNum (take offline)
    TST.B       (NoEject).W                     | offline-only (no eject)?
    BEQ.B       EJECT_NO_2                      | no: keep positive drive num
    NEG.W       D2                              | negate drive num (offline marker)
EJECT_NO_2:
    MOVE.W      D2,(A1)+                        | vcbDRefNum = +/- drive number
    TST.B       (NoEject).W                     | offline-only?
    BEQ.B       EJECT_NO_3                      | no: proceed to driver eject
    MOVEA.L     A2,A0                           | A0 = VCB to re-enqueue
    LEA.L       (VCBQHdr_Flags).W,A1            | VCB queue header
    JSR         DEQUEUE(PC)                     | remove from current position
    JSR         ENQUEUE(PC)                     | re-enqueue (move to end)
    TST.B       (NoEject).W                     | check NoEject sign
    BMI.W       EJECT_DONE                      | negative: done (full offline)
| EJECT_NO_3: send eject control call to disk driver
EJECT_NO_3:
    LEA.L       (Params).W,A0                   | general-purpose param block
    LEA.L       0x16(A0),A1                     | A1 -> ioVRefNum field
    MOVE.W      D2,(A1)+                        | ioVRefNum = drive number
    MOVE.W      D1,(A1)+                        | ioRefNum = driver refNum
    MOVE.W      #0x7,(A1)                       | csCode = ejectCode (7)
    LEA.L       FSQUEUE_DONE(PC),A1             | completion routine = CmdDone
    MOVE.L      A1,0xC(A0)                      | ioCompletion = FSQUEUE_DONE
    _ControlAsync                               | send async eject control call
    RTS                                         | return (completion will finish)
| _UnmountVol: unmount a volume
UNMOUNTVOL:
    BSR.W       FSQUEUE_SETUP_SYNC              | FSQueue: wait our turn
    CLR.B       (FlushOnly).W                   | full unmount (close files)
    BRA.B       FLUSHVOL_UNMOUNTVOL_SHARED      | join UnmountVol path
| UNMOUNTVOL_CONT: flush/close all open files on a volume
| A2=VCB, FlushOnly flag controls flush vs close
UNMOUNTVOL_CONT:
    MOVE.L      (A7)+,-(A6)                     | save return addr on A6 stack
    MOVEM.L     D1-D7/A0-A5,-(A6)               | save all regs
    BSR.W       HFSE_CONT_14                    | Gt1stFCB: get first FCB
UNMOUNTVOL_CONT_2:
    TST.L       0x0(A1,D1.W)                    | FCBFlNm: is FCB in use?
    BEQ.B       UNMOUNTVOL_NEXT                 | no: skip
    CMPA.L      0x14(A1,D1.W),A2                | FCBVPtr: belongs to this vol?
    BNE.B       UNMOUNTVOL_NEXT                 | no: skip
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       UNMOUNTVOL_NO                   | MFS: always flush
    CMPI.L      #0x10,0x0(A1,D1.W)              | system file? (CNID < 16)
    BCS.B       UNMOUNTVOL_NEXT                 | yes: skip B-tree files
UNMOUNTVOL_NO:
    BSR.W       FILECLOSE_CONT_3                | flush/close this FCB
    BNE.B       UNMOUNTVOL_EXIT                 | error: abort
UNMOUNTVOL_NEXT:
    BSR.W       HFSE_NEXT                       | GtNxtFCB: next FCB
    BCS.B       UNMOUNTVOL_CONT_2               | more: continue loop
    MOVEQ.L     #0x0,D0                         | all done, no error
UNMOUNTVOL_EXIT:
    MOVEM.L     (A6)+,D1-D7/A0-A5               | restore all regs
    MOVE.L      (A6)+,-(A7)                     | restore return addr
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from UNMOUNTVOL_CONT
| _FlushVol: flush volume buffers to disk
FLUSHVOL:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    ST.B        (FlushOnly).W                   | flush only (don't close files)
| shared FlushVol/UnmountVol entry
FLUSHVOL_UNMOUNTVOL_SHARED:
    BSR.B       P_DTRMV3                        | resolve volume from param block
    BNE.B       FLUSHVOL_DONE                   | error: done
    BSR.B       P_CKExtFS                       | external file system?
    BNE.B       FLUSHVOL_DONE                   | yes: let extFS handle it
    BSR.B       UNMOUNTVOL_CONT                 | flush/close all open files
    BNE.B       FLUSHVOL_DONE                   | error: done
    BSR.W       TFSVCBTST                       | HFS volume?
    BEQ.B       FLUSHVOL_OK                     | yes: HFS flush path
    BSR.W       HFSE_CONT_9                     | MFS: flush MFS directory
    BRA.B       FLUSHVOL_DONE                   | done
| ----------------------------------------------------------
|
| FLUSHVOL_OK
|
| TFS FlushVol/UnmountVol path
FLUSHVOL_OK:
    TST.W       0x48(A2)                        | vcbDrvNum: volume online?
    BEQ.B       FLUSHVOL_SKIP                   | offline: skip B-tree flush
    BSR.W       OFFLINE_CONT_2                  | flush/close B-trees + caches
    BNE.B       FLUSHVOL_DONE                   | error: done
FLUSHVOL_SKIP:
    TST.B       (FlushOnly).W                   | flush only (not unmount)?
    BNE.B       FLUSHVOL_NO_DISPOSE             | yes: don't dispose VCB
    BSR.W       BMCHK_CONT_2                    | dequeue and dispose VCB
FLUSHVOL_NO_DISPOSE:
    MOVEQ.L     #0x0,D0                         | no error
| Called by: FLUSHVOL_UNMOUNTVOL_SHARED, FLUSHVOL_OK
FLUSHVOL_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| CkExtFS: check if volume uses an external file system
| Called by: EJECT_OFFLINE_JOIN, FLUSHVOL_UNMOUNTVOL_SHARED, GETVOLINFO_CONT_8, GETWDINFO, CkExtFS_AndOnline (and 1 more)
P_CKExtFS:
    MOVE.L      (0x7B8).W,-(A7)                 | indirect jump via CkExtFS vector
    RTS                                         | jump to vector target
VCKEXTFS:
    MOVE.W      0x4C(A2),D0                     | vcbFSID: file system ID
    BEQ.B       CKEXTFS_RTS                     | zero: native MFS/HFS, ok
    MOVEQ.L     #-0x3A,D0                       | extFSErr (-58): external FS
CKEXTFS_RTS:
    RTS                                         | return from CkExtFS
| DTRMV3: determine volume from param block (by name, refnum, or default)
| Called by: TFMOVE, EJECT_OFFLINE_JOIN, FLUSHVOL_UNMOUNTVOL_SHARED, GETVOLINFO, SETVOL (and 5 more)
P_DTRMV3:
    MOVE.L      (0x7BC).W,-(A7)                 | indirect jump via DTRMV3 vector
    RTS                                         | jump to vector target
VDTRMV3:
    MOVE.L      0x12(A0),D2                     | ioNamePtr (volume name ptr)
    MOVEA.L     D2,A4                           | A4 = name ptr
    BEQ.B       P_DTRMV1                        | no name: resolve by refNum
    TST.B       (A4)                            | name string empty?
    BNE.W       DTRMV1_NO_4                     | has name: resolve by name
| DTRMV1: determine volume by ioVRefNum (drive num, volume refNum, or WD refNum)
| Called by: VDTRMV3, DTRMV3_REFNUM_ONLY, GETVOLINFO_RESOLVE, SETVOLINFO, GETWDINFO_HFS_CONT (and 5 more)
P_DTRMV1:
    MOVE.L      (0x778).W,-(A7)                 | indirect jump via DTRMV1 vector
    RTS                                         | jump to vector target
VDTRMV1:
    MOVEQ.L     #0x0,D3                         | clear catalog hint
    SUBA.L      A3,A3                           | clear WDCB ptr
    MOVE.W      0x16(A0),D0                     | ioVRefNum
    BEQ.B       DTRMV1_EMPTY                    | zero: use default volume
    BMI.B       DTRMV1_CONT                     | negative: volume/WD refNum
    BSR.W       FindVCBDrv                      | positive: look up by drive num
    BRA.B       DTRMV1_CONT_2                   | check result
DTRMV1_CONT:
    CMPI.W      #0xF000,D0                      | WD refNum range? (>= -4096)
    BLE.B       DTRMV1_TRY_WD                   | no: try as WD refNum
    BSR.W       GETVCBRFN                       | look up by volume refNum
    BRA.B       DTRMV1_CONT_2                   | check result
DTRMV1_TRY_WD:
    BSR.W       ResolveWDVCB                    | look up by WD refNum
DTRMV1_CONT_2:
    BEQ.B       DTRMV1_FOUND                    | found: set up volume
DTRMV1_NO:
    MOVEQ.L     #-0x23,D0                       | nsvErr (-35): no such volume
    RTS                                         | return with error
| ----------------------------------------------------------
|
| DTRMV1_EMPTY
|
| Called during boot.
| use default volume
DTRMV1_EMPTY:
    MOVE.L      (DefVCBPtr).W,D0                | default volume VCB
    BEQ.B       DTRMV1_NO                       | no default: error
    MOVEA.L     D0,A2                           | A2 = default VCB
    MOVEA.L     (WDCBsPtr).W,A3                 | default WDCB array
    ADDQ.L      #0x2,A3                         | skip header word
DTRMV1_FOUND:
    MOVEQ.L     #0x0,D0                         | no error
    MOVE.L      A2,(ReqstVol).W                 | save requested volume VCB
    BTST        #0x6,(HFSFlags)                 | PMSP needs clearing?
    BNE.B       DTRMV1_ERR                      | yes: go clear it
    BTST        #0x5,(HFSFlags)                 | PMSP needs clearing?
    BEQ.B       DTRMV1_OK_2                     | no: done
DTRMV1_ERR:
    MOVE.L      A4,-(A7)                        | save A4
    MOVEA.L     (PMSPPtr).W,A4                  | PMSP (parse/match search path)
    ADDQ.L      #0x2,A4                         | skip header
    MOVEQ.L     #0x17,D0                        | 24 words to clear
DTRMV1_LOOP:
    CLR.W       (A4)+                           | clear PMSP entry
    DBF.W       D0,DTRMV1_LOOP                  | loop all 24 entries
    MOVEA.L     (A7)+,A4                        | restore A4
DTRMV1_ERR_2:
    MOVEQ.L     #0x0,D0                         | no error
    RTS                                         | return from DTRMV1
| ----------------------------------------------------------
|
| DTRMV1_OK_2
|
| Called during boot.
DTRMV1_OK_2:
    BTST        #0x9,0x6(A0)                    | ioDirFlg: directory call?
    BEQ.B       DTRMV1_OK_3                     | no: normal file path
    TST.L       0x30(A0)                        | ioDirID specified?
    BNE.B       DTRMV1_ERR_2                    | yes: return (already resolved)
| DTRMV1_OK_3: build PMSP search path table
DTRMV1_OK_3:
    MOVEM.L     D2/D4/A1/A4,-(A7)               | save regs
    MOVEA.L     (PMSPPtr).W,A4                  | A4 = PMSP table base
    MOVE.W      -0x2(A4),D4                     | cached PMSP table offset
    BGT.B       DTRMV1_OK_4                     | already built: skip to lookup
    MOVEQ.L     #0x2,D4                         | start building at offset 2
    MOVE.W      0x4E(A2),D2                     | D2 = vcbVRefNum
    MOVE.L      A3,D0                           | WDCB ptr
    BEQ.B       DTRMV1_NO_2                     | no WDCB: use root
    MOVE.L      0x4(A3),D0                      | WDDirID from WDCB
    BRA.B       DTRMV1_CONT_3                   | add to search path
DTRMV1_NO_2:
    MOVEQ.L     #0x2,D0                         | fsRtDirID (root directory)
DTRMV1_CONT_3:
    BSR.B       DTRMV1_CONT_4                   | add vRefNum+dirID to PMSP
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       DTRMV1_NO_3                     | MFS: skip boot drive check
    MOVE.W      (BootDrive).W,D0                | boot drive WD refNum
    BGE.B       DTRMV1_ERR_3                    | positive: not a WD, skip
    CMPI.W      #0xF000,D0                      | in WD range? (>= -4096)
    BGT.B       DTRMV1_ERR_3                    | no: skip
    BSR.W       ResolveWDVCB                    | look up boot drive WD
    BNE.B       DTRMV1_ERR_3                    | not found: skip
    CMP.W       0x4E(A2),D2                     | same volume as requested?
    BNE.B       DTRMV1_ERR_3                    | different vol: skip
    MOVE.L      0x4(A3),D0                      | boot WD's dirID
    BSR.B       DTRMV1_CONT_4                   | add to search path
DTRMV1_ERR_3:
    MOVEA.L     (ReqstVol).W,A2                 | restore requested VCB
    MOVE.L      0x7A(A2),D0                     | vcbFndrInfo (Finder info dirID)
    BEQ.B       DTRMV1_NO_3                     | none: skip
    BSR.B       DTRMV1_CONT_4                   | add Finder info dir to path
| terminate the PMSP search path table
DTRMV1_NO_3:
    CLR.W       0x0(A4,D4.W)                    | zero-terminate PMSP table
    MOVEQ.L     #0x2,D4                         | reset offset to first entry
    MOVE.W      D4,-0x2(A4)                     | save current PMSP offset
    MOVE.L      -0x6(A4),D0                     | PMSP callback proc
    BEQ.B       DTRMV1_OK_4                     | none: skip callback
    MOVEA.L     D0,A1                           | A1 = callback address
    JSR         (A1)                            | call PMSP callback
| look up volume from current PMSP entry
DTRMV1_OK_4:
    MOVE.W      0x0(A4,D4.W),D0                 | current PMSP vRefNum
    BSR.W       GETVCBRFN                       | look up VCB by refNum
    BNE.B       DTRMV1_FOUND_2                  | not found: done
    MOVEA.L     (WDCBsPtr).W,A3                 | WDCB array
    ADDA.W      #0x12,A3                        | WDCB slot 1 (index 18)
    MOVE.L      A2,(A3)                         | set VCB ptr in WDCB
    MOVE.L      0x2(A4,D4.W),0x4(A3)            | set dirID from PMSP entry
    CLR.L       0x8(A3)                         | clear WDCatHint
    CLR.L       0xC(A3)                         | clear WDProcID
    MOVEQ.L     #0x0,D0                         | success
DTRMV1_FOUND_2:
    MOVEM.L     (A7)+,D2/D4/A1/A4               | restore regs
    RTS                                         | return from DTRMV1_OK_3
| ----------------------------------------------------------
|
| DTRMV1_CONT_4
|
| DTRMV1_CONT_4: add vRefNum+dirID entry to PMSP table if not duplicate
| D2=vRefNum, D0=dirID, D4=current table offset
| Called during boot.
DTRMV1_CONT_4:
    MOVE.L      D4,-(A7)                        | save target offset
    MOVEQ.L     #0x2,D4                         | start scanning at offset 2
DTRMV1_CONT_5:
    CMP.L       (A7),D4                         | reached target offset?
    BCC.B       DTRMV1_CONT_6                   | yes: not a duplicate
    CMP.W       0x0(A4,D4.W),D2                 | same vRefNum?
    BNE.B       DTRMV1_ERR_4                    | no: check next
    CMP.L       0x2(A4,D4.W),D0                 | same dirID?
    BEQ.B       DTRMV1_OK_5                     | yes: duplicate found
DTRMV1_ERR_4:
    ADDQ.W      #0x6,D4                         | next entry (6 bytes each)
    CMP.W       (A4),D4                         | past table capacity?
    BCS.B       DTRMV1_CONT_5                   | no: keep scanning
DTRMV1_OK_5:
    MOVEQ.L     #0x0,D0                         | clear D0 (duplicate or full)
DTRMV1_CONT_6:
    MOVE.L      (A7)+,D4                        | restore target offset
    TST.L       D0                              | was it a duplicate?
    BEQ.B       DTRMV1_OK_6                     | yes: skip adding
    MOVE.W      D2,0x0(A4,D4.W)                 | store vRefNum in table
    MOVE.L      D0,0x2(A4,D4.W)                 | store dirID in table
    ADDQ.W      #0x6,D4                         | advance to next slot
DTRMV1_OK_6:
    RTS                                         | return from DTRMV1_CONT_4
| volume-by-name lookup: parse "volname:path" from ioNamePtr
DTRMV1_NO_4:
    MOVE.L      0x12(A0),D2                     | ioNamePtr
DTRMV1_CONT_7:
    MOVEM.L     D4-D6/A0-A1,-(A7)               | save regs
    TST.L       D2                              | name ptr valid?
    BEQ.B       DTRMV1_EMPTY_2                  | null: use default
    MOVEA.L     D2,A4                           | A4 = Pascal string ptr
    MOVEQ.L     #0x0,D2                         | clear for length byte
    MOVEA.L     D2,A3                           | A3 = null (no WDCB yet)
    MOVE.B      (A4)+,D2                        | D2 = string length
    BEQ.B       DTRMV1_EMPTY_2                  | empty: use default
    MOVEQ.L     #0x0,D3                         | D3 = scan index
| scan for ':' separator (0x3A) in volume:path string
DTRMV1_NO_5:
    MOVE.B      0x0(A4,D3.W),D4                 | get char at index
    CMPI.B      #0x3A,D4                        | colon ':' separator?
    BEQ.B       DTRMV1_FOUND_3                  | found: split vol from path
    ADDQ.W      #0x1,D3                         | next char
    CMP.W       D3,D2                           | past end of string?
    BNE.B       DTRMV1_NO_5                     | no: keep scanning
    BRA.B       DTRMV3_REFNUM_ONLY              | no colon: whole string is name
| colon found at D3: split into volname (D3 chars) + path (D2 remaining)
DTRMV1_FOUND_3:
    SUB.L       D3,D2                           | D2 = path length after colon
    SUBQ.W      #0x1,D2                         | subtract colon itself
    MOVEA.L     A4,A1                           | A1 = path after colon
    ADDA.L      D3,A4                           | skip past volume name
    ADDQ.L      #0x1,A4                         | skip past colon
    TST.W       D3                              | volume name present?
    BGT.B       DTRMV1_OK_7                     | yes: search by name
| no volume name: resolve by ioVRefNum only
DTRMV3_REFNUM_ONLY:
    BSR.W       P_DTRMV1                        | DTRMV1: resolve by refNum
DTRMV1_CONT_8:
    MOVEM.L     (A7)+,D4-D6/A0-A1               | restore regs
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from DTRMV3
| ----------------------------------------------------------
|
| DTRMV1_EMPTY_2
|
DTRMV1_EMPTY_2:
    MOVEQ.L     #-0x25,D0                       | bdNamErr (-37): bad name
    BRA.B       DTRMV1_CONT_8                   | return with error
| ----------------------------------------------------------
|
| DTRMV1_OK_7
|
| scan VCB queue for volume by name
DTRMV1_OK_7:
    MOVE.L      (VCBQHdr_Head).W,D0             | start of VCB queue
DTRMV1_CONT_9:
    BEQ.B       DTRMV1_CONT_10                  | end of queue: not found
    MOVEA.L     D0,A2                           | A2 = candidate VCB
    LEA.L       0x2C(A2),A0                     | vcbVN (volume name)
    MOVEQ.L     #0x0,D0                         | clear for length
    MOVE.B      (A0)+,D0                        | VCB name length
    SWAP.W      D0                              | move to high word
    MOVE.W      D3,D0                           | low word = search name len
    _CmpString                                  | compare names (case-insensitive)
    BNE.B       DTRMV1_FOUND_5                  | no match: try next
    MOVE.L      A2,(ReqstVol).W                 | match: save volume VCB
    BRA.B       DTRMV1_CONT_8                   | return success
DTRMV1_FOUND_5:
    MOVE.L      (A2),D0                         | qLink: next VCB
    BNE.B       DTRMV1_CONT_9                   | more: keep scanning
DTRMV1_CONT_10:
    MOVEQ.L     #-0x23,D0                       | nsvErr (-35): no such volume
    BRA.B       DTRMV1_CONT_8                   | return with error
| HFS selector C: set PMSP callback and HFS flags
P_hfsC:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    MOVE.L      0x1C(A0),D0                     | ioMisc (PMSP callback proc)
    BMI.B       HFSC_SKIP                       | negative: don't set callback
    MOVEA.L     (PMSPPtr).W,A1                  | PMSP table
    MOVE.L      D0,-0x6(A1)                     | store PMSP callback proc
HFSC_SKIP:
    MOVE.W      0x1A(A0),D0                     | csCode (HFS flag bits)
    BCLR        #0x6,(HFSFlags)                 | clear PMSP flag
    BTST        #0x0,D0                         | bit 0 set?
    BNE.B       SETVOL_PMSP_FLAG_SET            | yes: leave flag clear
    BSET        #0x6,(HFSFlags)                 | no: set PMSP flag
SETVOL_PMSP_FLAG_SET:
    MOVEQ.L     #0x0,D0                         | no error
    BRA.W       FSQUEUE_DONE                    | CmdDone
| _GetVolInfo / PBHGetVInfo: get volume information
GETVOLINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    MOVE.W      0x1C(A0),D2                     | ioVolIndex
    BGT.B       GETVOLINFO_CONT_2               | > 0: index into VCB queue
    BEQ.B       GETVOLINFO_RESOLVE              | = 0: resolve by ioVRefNum
    BSR.W       P_DTRMV3                        | < 0: resolve by name/refNum
    BRA.B       GETVOLINFO_BY_REFNUM            | check result
GETVOLINFO_RESOLVE:
    BSR.W       P_DTRMV1                        | resolve by ioVRefNum only
GETVOLINFO_BY_REFNUM:
    BNE.W       GETVOLINFO_DONE                 | error: exit
    BRA.B       GETVOLINFO_EXIT                 | found: copy VCB info
| index into VCB queue (ioVolIndex > 0)
GETVOLINFO_CONT_2:
    MOVEQ.L     #0x0,D3                         | clear WDCB flag
    CLR.W       0x16(A0)                        | clear ioVRefNum for return
    MOVE.L      (VCBQHdr_Head).W,D1             | start of VCB queue
GETVOLINFO_INDEX_LOOP:
    BEQ.W       GETVOL_NO                       | end of queue: not found
    SUBQ.W      #0x1,D2                         | decrement index
    MOVEA.L     D1,A2                           | A2 = VCB at this index
    BEQ.B       GETVOLINFO_EXIT                 | index hit 0: found it
    MOVE.L      (A2),D1                         | qLink: next VCB
    BRA.B       GETVOLINFO_INDEX_LOOP           | keep counting
| GETVOLINFO_EXIT: copy VCB info to param block
GETVOLINFO_EXIT:
    MOVEQ.L     #0x20,D0                        | copy 34 bytes (17 words)
GETVOLINFO_LOOP:
    MOVE.W      0xA(A2,D0.W),0x1E(A0,D0.W)      | VCB field -> param block field
    SUBQ.W      #0x2,D0                         | next word
    BPL.B       GETVOLINFO_LOOP                 | loop all VCB info words
| check if any files are open on this volume
    BSET        #0x6,0x27(A0)                   | assume files are open
    BSR.W       HFSE_CONT_14                    | Gt1stFCB: get first FCB
GETVOLINFO_CONT_4:
    CMPA.L      0x14(A1,D1.W),A2                | FCBVPtr: belongs to this vol?
    BNE.B       GETVOLINFO_NEXT_FCB             | no: check next
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       GETVOLINFO_FOUND                | MFS: file is open
    MOVE.L      0x0(A1,D1.W),D0                 | FCBFlNm
    CMPI.L      #0x10,D0                        | user file? (CNID >= 16)
    BCC.B       GETVOLINFO_FOUND                | yes: file is open
GETVOLINFO_NEXT_FCB:
    BSR.W       HFSE_NEXT                       | GtNxtFCB: next FCB
    BCS.B       GETVOLINFO_CONT_4               | more: keep scanning
    BCLR        #0x6,0x27(A0)                   | no user files open
| check if this is the default volume
GETVOLINFO_FOUND:
    BCLR        #0x5,0x27(A0)                   | clear "is default" bit
    CMPA.L      (DefVCBPtr).W,A2                | is this the default volume?
    BNE.B       GETVOLINFO_NO_2                 | no: skip
    BSET        #0x5,0x27(A0)                   | yes: mark as default
| determine WDCB for directory info
GETVOLINFO_NO_2:
    SUBA.L      A3,A3                           | clear WDCB ptr
    TST.W       0x1C(A0)                        | indexed lookup?
    BGT.B       GETVOLINFO_SKIP                 | yes: no WDCB info
    TST.W       D3                              | WDCB from volume resolution?
    BNE.B       GETVOLINFO_SKIP                 | yes: use WDCB from caller
    MOVE.W      0x16(A0),D1                     | ioVRefNum
    BGT.B       GETVOLINFO_SKIP                 | drive num: no WDCB
    BLT.B       GETVOLINFO_CONT_5               | negative: check for WD
    MOVEQ.L     #0x2,D1                         | zero: default WDCB index
    BRA.B       GETVOLINFO_CONT_6               | look up WDCB
| check if it's a WD reference
GETVOLINFO_CONT_5:
    CMPI.W      #0xF000,D1                      | in WD refNum range?
    BGT.B       GETVOLINFO_SKIP                 | no: skip WDCB
    SUBI.W      #0x8001,D1                      | convert WD refNum to index
GETVOLINFO_CONT_6:
    MOVEA.L     (WDCBsPtr).W,A3                 | WDCB array base
    ADDA.W      D1,A3                           | A3 -> WDCB entry
    BSR.W       CkExtFS_AndOnline               | validate WDCB
    BNE.B       GETVOLINFO_SKIP                 | invalid: skip
| get directory access rights from catalog
    MOVEM.L     A0-A1,-(A6)                     | save regs
    MOVEA.L     (WDCBsPtr).W,A1                 | WDCB array
    MOVE.L      0x4(A1,D1.W),D0                 | WDDirID
    CMPI.L      #0x2,D0                         | root directory?
    BEQ.B       GETVOLINFO_ERR                  | yes: skip access check
    MOVE.L      0x8(A1,D1.W),D2                 | WDCatHint
    SUBA.L      A0,A0                           | no CName (get dir record)
    JSR         CMGETCN(PC)                     | look up directory in catalog
    BNE.B       GETVOLINFO_ERR                  | error: skip
    MOVE.W      0x4(A1),D0                      | directory access rights
    MOVEM.L     (A6)+,A0-A1                     | restore regs
    MOVE.W      D0,0x28(A0)                     | store access rights in PB
    BRA.B       GETVOLINFO_SKIP                 | continue
| ----------------------------------------------------------
|
| GETVOLINFO_ERR
|
GETVOLINFO_ERR:
    MOVEM.L     (A6)+,A0-A1                     | restore regs (error path)
| Called by: GETVOLINFO_NO_2, GETVOLINFO_CONT_6, GETVOLINFO_CONT_5
GETVOLINFO_SKIP:
    TST.W       D3                              | had WDCB from DTRMV?
    BNE.B       GETVOLINFO_OK                   | yes: return vcbVRefNum
    TST.W       0x16(A0)                        | ioVRefNum negative?
    BLT.B       GETVOLINFO_CONT_7               | yes: keep WD refNum
GETVOLINFO_OK:
    MOVE.W      0x4E(A2),0x16(A0)               | return vcbVRefNum
GETVOLINFO_CONT_7:
    BSR.W       GETVOL_CONT_2                   | fill volume name in PB
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       GETVOLINFO_NO_3                 | MFS: skip B-tree adj
    MOVE.W      0xA0(A2),D0                     | VCBXTAlBks (extent tree)
    SUB.W       D0,0x2E(A0)                     | subtract from free blocks
    MOVE.W      0xA2(A2),D0                     | VCBCTAlBks (catalog tree)
    SUB.W       D0,0x2E(A0)                     | subtract from free blocks
GETVOLINFO_NO_3:
    BTST        #0x9,0x6(A0)                    | ioDirFlg: HFS-extended call?
    BNE.B       GETVOLINFO_EXIT_2               | yes: return extended info
| clamp MFS-compat fields to 16-bit range
    MOVE.W      #0x7C00,D0                      | max MFS-visible blocks (31744)
    CMP.W       0x2E(A0),D0                     | ioVNmAlBlks > max?
    BHI.B       GETVOLINFO_NO_4                 | no: ok
    MOVE.W      D0,0x2E(A0)                     | clamp ioVNmAlBlks
    CMP.W       0x3E(A0),D0                     | ioVFrBlk > max?
    BHI.B       GETVOLINFO_NO_4                 | no: ok
    MOVE.W      D0,0x3E(A0)                     | clamp ioVFrBlk
GETVOLINFO_NO_4:
    BRA.B       GETVOLINFO_CONT_8               | finish up
| ----------------------------------------------------------
|
| GETVOLINFO_EXIT_2
|
| Called during boot.
| GETVOLINFO_EXIT_2: return extended HFS volume info (for HFS-aware callers)
GETVOLINFO_EXIT_2:
    MOVE.W      0x4E(A2),0x16(A0)               | ioVRefNum = vcbVRefNum
    MOVE.W      0x8(A2),0x40(A0)                | ioVSigWord = vcbSigWord
    MOVE.W      0x48(A2),0x42(A0)               | ioVDrvInfo = vcbDrvNum
    MOVE.W      0x4A(A2),0x44(A0)               | ioVDRefNum = vcbDRefNum
    MOVE.W      0x4C(A2),0x46(A0)               | ioVFSID = vcbFSID
    CLR.L       0x52(A0)                        | ioVFilCnt = 0 (default)
    MOVE.W      0x14(A2),0x54(A0)               | ioVNmFls = vcbNmFls (root)
    CLR.L       0x56(A0)                        | ioVDirCnt = 0 (default)
    MOVE.W      #0x1,0x58(A0)                   | ioVWrCnt = 1 (version)
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       GETVOLINFO_SKIP_2               | MFS: done with defaults
| HFS-specific extended info
    MOVE.L      0x5E(A2),0x48(A0)               | ioVBkUp = vcbVolBkUp
    MOVE.W      0x62(A2),0x4C(A0)               | ioVSeqNum = vcbVSeqNum
    MOVE.L      0x64(A2),0x4E(A0)               | ioVWrCnt = vcbWrCnt
    MOVE.L      0x72(A2),0x52(A0)               | ioVFilCnt = vcbFilCnt
    MOVE.L      0x76(A2),0x56(A0)               | ioVDirCnt = vcbDirCnt
| copy Finder info (32 bytes)
    MOVE.L      A0,-(A7)                        | save param block ptr
    LEA.L       0x5A(A0),A1                     | dest = ioVFndrInfo in PB
    LEA.L       0x7A(A2),A0                     | src = vcbFndrInfo in VCB
    MOVEQ.L     #0x20,D0                        | 32 bytes of Finder info
    _BlockMove                                  | copy Finder info
    MOVEA.L     (A7)+,A0                        | restore param block ptr
GETVOLINFO_CONT_8:
    MOVE.L      A2,(ReqstVol).W                 | save requested volume
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       GETVOLINFO_SKIP_2               | MFS: done
    BSR.W       P_CKExtFS                       | external FS?
    BNE.B       GETVOLINFO_DONE                 | yes: return extFS error
GETVOLINFO_SKIP_2:
    MOVEQ.L     #0x0,D0                         | no error
GETVOLINFO_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| _SetVolInfo / PBSetVInfo: set volume information
SETVOLINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_DTRMV1                        | resolve volume
    BNE.B       SETVOLINFO_DONE                 | error: exit
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       SETVOLINFO_DONE                 | write-protected: error
    BSR.W       CkExtFS_AndOnline               | validate WDCB
    BNE.B       SETVOLINFO_DONE                 | error: exit
    MOVE.L      0x1E(A0),0xA(A2)                | vcbCrDate = ioVCrDate
    MOVE.L      0x22(A0),0xE(A2)                | vcbLsMod = ioVLsMod
    MOVE.W      0x26(A0),D0                     | ioVAtrb
    ANDI.W      #0x8000,D0                      | preserve software-lock bit
    MOVE.W      0x12(A2),D1                     | current vcbAtrb
    ANDI.W      #0x7FFF,D1                      | clear software-lock bit
    OR.W        D0,D1                           | merge new lock bit
    MOVE.W      D1,0x12(A2)                     | update vcbAtrb
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       SETVOLINFO_HFS_NO               | MFS: skip HFS fields
| set HFS-specific volume info
    MOVE.L      0x34(A0),0x20(A2)               | vcbClpSiz = ioVClpSiz
    MOVE.L      0x48(A0),0x5E(A2)               | vcbVolBkUp = ioVBkUp
    MOVE.W      0x4C(A0),0x62(A2)               | vcbVSeqNum = ioVSeqNum
| copy Finder info (32 bytes) from PB to VCB
    MOVE.L      A0,-(A7)                        | save param block ptr
    LEA.L       0x5A(A0),A0                     | src = ioVFndrInfo in PB
    LEA.L       0x7A(A2),A1                     | dest = vcbFndrInfo in VCB
    MOVEQ.L     #0x20,D0                        | 32 bytes of Finder info
    _BlockMove                                  | copy Finder info
    MOVEA.L     (A7)+,A0                        | restore param block ptr
SETVOLINFO_HFS_NO:
    MOVE.L      0x12(A0),D0                     | ioNamePtr (new volume name?)
    BEQ.B       SETVOLINFO_RENAME_DONE          | null: skip rename
    MOVEA.L     D0,A1                           | A1 = new name string
    BSR.B       SETVOLINFO_HFS_CONT             | update VCB volume name
SETVOLINFO_RENAME_DONE:
    BSR.W       MARKVCB                         | mark VCB dirty for flush
    MOVEQ.L     #0x0,D0                         | no error
SETVOLINFO_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| SETVOLINFO_HFS_CONT -- update VCB volume name.
| ----------------------------------------------------------
|
| SETVOLINFO_HFS_CONT
|
| update VCB volume name from Pascal string at A1
| stops at colon ':' or 27-char max
SETVOLINFO_HFS_CONT:
    MOVEM.L     A1-A2,-(A7)                     | save regs
    LEA.L       0x2C(A2),A2                     | A2 -> vcbVN (volume name)
    MOVEQ.L     #0x1,D0                         | start at char index 1
SETVOLINFO_HFS_CONT_2:
    CMP.B       (A1),D0                         | past end of source string?
    BGT.B       SETVOLINFO_HFS_OK               | yes: done
    CMPI.B      #0x3A,0x0(A1,D0.W)              | colon ':' (path separator)?
    BEQ.B       SETVOLINFO_HFS_OK               | yes: stop at volume name
    CMPI.B      #0x1B,D0                        | past 27-char limit?
    BGT.B       SETVOLINFO_HFS_OK               | yes: truncate
    MOVE.B      0x0(A1,D0.W),0x0(A2,D0.W)       | copy char to VCB name
    ADDQ.W      #0x1,D0                         | next char
    BRA.B       SETVOLINFO_HFS_CONT_2           | loop
SETVOLINFO_HFS_OK:
    SUBQ.W      #0x1,D0                         | D0 = actual name length
    MOVE.B      D0,(A2)                         | set vcbVN length byte
    MOVEM.L     (A7)+,A1-A2                     | restore regs
    BSR.W       MARKVCB                         | mark VCB dirty
    RTS                                         | return from SetVolName
| ----------------------------------------------------------
|
| SETVOLINFO_HFS_CONT_3: check volume write protect status
|
| check volume write-protect status
| Returns D0=0 if writable, error code if locked
| Called during boot.
SETVOLINFO_HFS_CONT_3:
    MOVEQ.L     #-0x2E,D0                       | vLckdErr (-46): software locked
    TST.W       0x12(A2)                        | vcbAtrb: software lock bit set?
    BMI.B       SETVOLINFO_HFS_OK_2             | yes: return locked error
    MOVEQ.L     #-0x2C,D0                       | wPrErr (-44): hardware locked
    TST.B       0x13(A2)                        | vcbAtrb+1: hardware write-protect?
    BMI.B       SETVOLINFO_HFS_OK_2             | yes: return locked error
    MOVEQ.L     #0x0,D0                         | writable: no error
SETVOLINFO_HFS_OK_2:
    RTS                                         | return from write-protect check
| _GetVol / _HGetVol: get current default volume
GETVOL:
    BTST        #0x9,D1                         | ioDirFlg: HFS-extended?
    BNE.W       GETDIR                          | yes: HFS GetWDInfo path
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    MOVE.L      (DefVCBPtr).W,D0                | default VCB
    BEQ.B       GETVOL_NO                       | no default: error
    MOVEA.L     D0,A2                           | A2 = default VCB
    MOVE.W      (DefVRefNum).W,0x16(A0)         | ioVRefNum = default refNum
    BSR.B       GETVOL_CONT_2                   | copy volume name to PB
GETVOL_DEFAULT_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| GETVOL_NO
|
GETVOL_NO:
    MOVEQ.L     #-0x23,D0                       | nsvErr (-35): no such volume
    BRA.B       GETVOL_DEFAULT_DONE             | return with error
| ----------------------------------------------------------
|
| GETVOL_CONT_2
|
| Copy volume name to caller's buffer (Pascal string copy)
| Called during boot.
GETVOL_CONT_2:
    MOVEM.L     A1-A2,-(A7)                     | save regs
    LEA.L       0x2C(A2),A2                     | A2 -> vcbVN (volume name)
    MOVE.L      0x12(A0),D0                     | ioNamePtr (dest buffer)
    BEQ.B       GETVOL_SKIP                     | null: skip copy
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit address
    CMP.L       (MemTop).W,D0                   | valid address?
    BGT.B       GETVOL_SKIP                     | above MemTop: skip
    MOVEA.L     D0,A1                           | A1 = dest buffer
    MOVEQ.L     #0x0,D0                         | clear for length
    MOVE.B      (A2),D0                         | vcbVN length byte
GETVOL_LOOP:
    MOVE.B      (A2)+,(A1)+                     | copy name byte (incl length)
    DBF.W       D0,GETVOL_LOOP                  | loop for all chars + length
GETVOL_SKIP:
    MOVEM.L     (A7)+,A1-A2                     | restore regs
    MOVEQ.L     #0x0,D0                         | no error
    RTS                                         | return from GetVolName
| _SetVol / _HSetVol: set current default volume
SETVOL:
    BTST        #0x9,D1                         | ioDirFlg: HFS-extended?
    BNE.B       SETDIR                          | yes: HFS SetWDDir path
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_DTRMV3                        | resolve volume
    BNE.B       SETVOL_DEFAULT_WDCB_DONE        | error: exit
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum
    TST.W       D3                              | from WDCB resolution?
    BNE.B       SETVOL_OK                       | yes: use vcbVRefNum
    TST.W       0x16(A0)                        | ioVRefNum positive (drive)?
    BGT.B       SETVOL_OK                       | yes: use vcbVRefNum
    MOVE.W      0x16(A0),D0                     | use caller's refNum
    BEQ.B       SETVOL_SKIP                     | zero: keep current default
SETVOL_OK:
    MOVE.W      D0,(DefVRefNum).W               | set new default refNum
SETVOL_SKIP:
    MOVEQ.L     #0x2,D6                         | default dirID = root
    MOVE.L      A3,D7                           | WDCB ptr valid?
    BEQ.B       SETVOL_NO                       | no: use defaults
    MOVE.L      0x4(A3),D6                      | WDDirID from WDCB
    MOVE.L      0x8(A3),D7                      | WDCatHint from WDCB
SETVOL_NO:
    BSR.W       OPENWD_HFS_CONT                 | set up default WDCB
    MOVEQ.L     #0x0,D0                         | no error
SETVOL_DEFAULT_WDCB_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| _HSetVol with ioDirFlg: set default working directory
SETDIR:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_FndFilName                    | resolve path to directory
    BEQ.B       SETDIR_HFS3_FOUND               | found: check record type
    CMPI.W      #0xFFDB,D0                      | fnfErr (-37)?
    BNE.B       HSETVOL_DEFAULT_WDCB_DONE       | other error: exit
    TST.B       D2                              | partial path remaining?
    BNE.B       HSETVOL_DEFAULT_WDCB_DONE       | yes: real error
    MOVEQ.L     #0x2,D6                         | root dirID (path was just ":")
    BRA.B       SETDIR_HFS3_CONT                | set as default
| ----------------------------------------------------------
|
| SETDIR_HFS3_FOUND
|
SETDIR_HFS3_FOUND:
    MOVEQ.L     #-0x78,D0                       | dirNFErr (-120): not a directory
    CMPI.B      #0x1,(A5)                       | cdrDirRec (directory record)?
    BNE.B       HSETVOL_DEFAULT_WDCB_DONE       | not a directory: error
    MOVE.L      0x6(A5),D6                      | dirDirID from catalog record
SETDIR_HFS3_CONT:
    MOVE.W      0x4E(A2),(DefVRefNum).W         | set default to this volume
    MOVEQ.L     #0x0,D7                         | no catalog hint
    BSR.B       OPENWD_HFS_CONT                 | set up default WDCB
    MOVEQ.L     #0x0,D0                         | no error
HSETVOL_DEFAULT_WDCB_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| _HGetVol with ioDirFlg: get default working directory info
GETDIR:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       CREATE_CONT_11                  | get default WDCB
    MOVEQ.L     #-0x23,D0                       | nsvErr (-35) if invalid
    TST.L       0x0(A1,D1.W)                    | WDCB VCB ptr valid?
    BEQ.B       HGETVOL_DEFAULT_DONE            | no: error
    BSR.W       HFSF_CONT_2                     | copy WD info to param block
    BSR.W       GETVOL_CONT_2                   | copy volume name to PB
    MOVE.W      (DefVRefNum).W,0x16(A0)         | ioVRefNum = default refNum
    MOVEQ.L     #0x0,D0                         | no error
HGETVOL_DEFAULT_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| _OpenWD: open a working directory
OPENWD:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       P_FndFilName                    | resolve path
    BEQ.B       OPENWD_HFS_FOUND                | found: check record type
    CMPI.W      #0xFFDB,D0                      | fnfErr (-37)?
    BNE.B       OPENWD_DONE                     | other error: exit
    TST.B       D2                              | partial path remaining?
    BNE.B       OPENWD_DONE                     | yes: real error
    BRA.B       OPENWD_HFS_NO                   | root path: return vRefNum
| check that it's a directory
OPENWD_HFS_FOUND:
    MOVEQ.L     #-0x78,D0                       | dirNFErr (-120)
    CMPI.B      #0x1,(A5)                       | cdrDirRec (directory)?
    BNE.B       OPENWD_DONE                     | no: not a directory
    MOVE.L      0x6(A5),D6                      | dirDirID from catalog
    CMPI.L      #0x2,D6                         | root directory?
    BEQ.B       OPENWD_HFS_NO                   | yes: return vRefNum
    MOVEQ.L     #0x0,D7                         | no catalog hint
    BSR.B       OPENWD_HFS_CONT_3               | allocate WDCB for this dir
    BRA.B       OPENWD_DONE                     | exit with result
OPENWD_HFS_NO:
    MOVE.W      0x4E(A2),0x16(A0)               | ioVRefNum = vcbVRefNum
    MOVEQ.L     #0x0,D0                         | no error
OPENWD_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| OPENWD_HFS_CONT: set default volume and directory
|
| Called during boot.
OPENWD_HFS_CONT:
    MOVE.L      A2,(DefVCBPtr).W                | set default VCB
    MOVEQ.L     #0x2,D1                         | default WDCB offset
| OPENWD_HFS_CONT_2: fill in a WDCB entry at offset D1
| fill in a WDCB entry at offset D1
OPENWD_HFS_CONT_2:
    MOVEA.L     (WDCBsPtr).W,A1                 | WDCB array base
    MOVE.L      A2,0x0(A1,D1.W)                 | WDVCBPtr = VCB
    MOVE.L      D6,0x4(A1,D1.W)                 | WDDirID = directory ID
    MOVE.L      D7,0x8(A1,D1.W)                 | WDCatHint = catalog hint
    MOVE.L      0x1C(A0),D0                     | ioWDProcID from param block
    MOVE.L      D0,0xC(A1,D1.W)                 | WDProcID = process ID
    ADDI.W      #0x8001,D1                      | convert index to WD refNum
    RTS                                         | return from OPENWD_HFS_CONT_2
| OPENWD_HFS_CONT_3: find or allocate WDCB for volume/dir/procID
| A2=VCB, D6=dirID, D7=catHint, ioWDProcID from PB
OPENWD_HFS_CONT_3:
    MOVE.L      0x1C(A0),D3                     | D3 = ioWDProcID
    MOVEQ.L     #0x0,D2                         | D2 = first free slot (none yet)
    BSR.W       CREATE_CONT_11                  | get default WDCB
    BSR.W       CREATE_SKIP                     | skip default entry
| scan WDCB array for existing match or free slot
| Called by: OPENWD_HFS_FOUND_2, OPENWD_SCAN_LOOP
OPENWD_SCAN_LOOP:
    BSR.W       CREATE_SKIP                     | next WDCB entry
    BCC.B       OPENWD_HFS_CONT_4               | end of array: allocate
    TST.L       0x0(A1,D1.W)                    | WDVCBPtr: slot in use?
    BNE.B       OPENWD_HFS_FOUND_2              | yes: check for match
    TST.W       D2                              | first free slot found?
    BNE.B       OPENWD_SCAN_LOOP                | already have one: skip
    MOVE.W      D1,D2                           | remember first free slot
    BRA.B       OPENWD_SCAN_LOOP                | keep scanning
| check if this WDCB matches our volume/DirID/procID
OPENWD_HFS_FOUND_2:
    CMPA.L      0x0(A1,D1.W),A2                 | same VCB?
    BNE.B       OPENWD_SCAN_LOOP                | no: next
    CMP.L       0x4(A1,D1.W),D6                 | same WDDirID?
    BNE.B       OPENWD_SCAN_LOOP                | no: next
    CMP.L       0xC(A1,D1.W),D3                 | same WDProcID?
    BNE.B       OPENWD_SCAN_LOOP                | no: next
    ADDI.W      #0x8001,D1                      | match: convert to WD refNum
    BRA.B       OPENWD_HFS_CONT_5               | return existing WDCB
| no existing match: allocate the free slot
OPENWD_HFS_CONT_4:
    MOVE.W      D2,D1                           | D1 = free slot offset
    BEQ.B       OPENWD_HFS_NO_2                 | none: error
    BSR.B       OPENWD_HFS_CONT_2               | fill in new WDCB entry
OPENWD_HFS_CONT_5:
    MOVE.W      D1,0x16(A0)                     | ioVRefNum = WD refNum
    MOVEQ.L     #0x0,D0                         | no error
    RTS                                         | return WD refNum
OPENWD_HFS_NO_2:
    MOVEQ.L     #-0x79,D0                       | tmwdoErr (-121): too many WDs
    RTS                                         | return with error
| _CloseWD: close a working directory
CLOSEWD:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    MOVEQ.L     #0x0,D1                         | clear for word load
    MOVE.W      0x16(A0),D1                     | ioVRefNum (WD refNum)
    BSR.W       HFSF_CONT_3                     | resolve WD to WDCB
    BEQ.B       CLOSEWD_HFS_CONT                | found: close it
    CMPI.W      #0xF000,D1                      | in WD range?
    BHI.B       CLOSEWD_OK_DONE                 | no: not a WD, try as vRefNum
    BRA.B       GETWDINFO_HFS_ERR               | valid WD but not found
| close the working directory
CLOSEWD_HFS_CONT:
    SUBI.W      #0x8001,D1                      | convert WD refNum to index
    MOVEA.L     0x0(A1,D1.W),A2                 | WDVCBPtr -> VCB
    TST.W       0x4C(A2)                        | vcbFSID: external FS?
    BEQ.B       CLOSEWD_HFS_OK                  | native: clear WDCB
    MOVE.L      A2,(ReqstVol).W                 | save for extFS dispatch
    ADD.L       A1,D1                           | D1 = absolute WDCB addr
    MOVEQ.L     #-0x3A,D0                       | extFSErr (-58)
    BRA.B       GETWDINFO_HFS_ERR               | let extFS handle close
CLOSEWD_HFS_OK:
    CLR.L       0x0(A1,D1.W)                    | clear WDVCBPtr (free slot)
CLOSEWD_OK_DONE:
    MOVEQ.L     #0x0,D0                         | no error
GETWDINFO_HFS_ERR:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| _GetWDInfo: get working directory information
GETWDINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.B       GETWDINFO_HFS_CONT              | resolve WD and fill PB
    BNE.B       GETWDINFO_DONE                  | error: exit
    EXT.L       D1                              | sign-extend WDCB index
    ADD.L       A1,D1                           | D1 = absolute WDCB addr
    MOVE.L      A2,(ReqstVol).W                 | save VCB for extFS check
    BSR.W       P_CKExtFS                       | external FS?
    BNE.B       GETWDINFO_DONE                  | yes: return extFS error
    MOVEQ.L     #0x0,D0                         | no error
GETWDINFO_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| GETWDINFO_HFS_CONT: resolve WD info - by ioWDIndex or ioVRefNum
GETWDINFO_HFS_CONT:
    TST.W       0x1A(A0)                        | ioWDIndex: indexed lookup?
    BGT.B       GETWDINFO_HFS_OK                | > 0: scan WDCB by index
| look up by ioVRefNum
    MOVEQ.L     #0x0,D1                         | clear for word load
    MOVE.W      0x16(A0),D1                     | ioVRefNum
    BSR.W       HFSF_CONT_3                     | try as WD refNum
    BEQ.B       GETWDINFO_HFS_CONT_2            | found: get WDCB info
    BSR.W       P_DTRMV1                        | not WD: try as volume
    BNE.B       GETWDINFO_HFS_ERR_2             | error: exit
| volume found but not a WD: return root dir info
    CLR.L       0x1C(A0)                        | ioWDProcID = 0
    MOVEQ.L     #0x2,D0                         | fsRtDirID (root directory)
    MOVE.L      D0,0x30(A0)                     | ioWDDirID = root
    MOVE.W      0x4E(A2),0x20(A0)               | ioWDVRefNum = vcbVRefNum
    MOVE.W      0x4E(A2),0x16(A0)               | ioVRefNum = vcbVRefNum
    MOVEQ.L     #0x0,D1                         | WDCB index = 0 (none)
    BRA.B       GETWDINFO_FOUND_FILL            | copy vol name and return
| valid WD reference: get WDCB info
GETWDINFO_HFS_CONT_2:
    MOVEQ.L     #-0x23,D0                       | nsvErr (-35) if invalid
    SUBI.W      #0x8001,D1                      | convert WD refNum to index
    TST.L       0x0(A1,D1.W)                    | WDVCBPtr valid?
    BEQ.B       GETWDINFO_HFS_ERR_2             | no: error
    BRA.B       GETWDINFO_HFS_CONT_3            | yes: fill PB from WDCB
| indexed WDCB scan (ioWDIndex > 0)
GETWDINFO_HFS_OK:
    MOVEQ.L     #-0x23,D0                       | nsvErr (-35) default
    MOVEQ.L     #0x0,D2                         | D2 = volume filter (0=any)
    TST.W       0x16(A0)                        | ioVRefNum specified?
    BEQ.B       GETWDINFO_HFS_NO                | zero: scan all volumes
    BSR.W       P_DTRMV3                        | resolve volume
    BNE.B       GETWDINFO_HFS_ERR_2             | error: exit
    MOVE.L      A2,D2                           | D2 = filter by this VCB
GETWDINFO_HFS_NO:
    MOVE.W      0x1A(A0),D4                     | D4 = ioWDIndex (count down)
    MOVE.L      0x1C(A0),D3                     | D3 = ioWDProcID filter (0=any)
    MOVEQ.L     #-0x23,D0                       | nsvErr if not found
    BSR.W       CREATE_CONT_11                  | get default WDCB
    BSR.W       CREATE_SKIP                     | skip default entry
| scan WDCB array matching procID and volume filters
GETWDINFO_INDEX_LOOP:
    BSR.W       CREATE_SKIP                     | next WDCB entry
    BCC.B       GETWDINFO_HFS_ERR_2             | end of array: not found
    TST.L       0x0(A1,D1.W)                    | WDVCBPtr: slot in use?
    BEQ.B       GETWDINFO_INDEX_LOOP            | empty: skip
    TST.L       D3                              | procID filter active?
    BEQ.B       GETWDINFO_HFS_NO_2              | no: check volume only
    CMP.L       0xC(A1,D1.W),D3                 | WDProcID matches?
    BNE.B       GETWDINFO_INDEX_LOOP            | no: skip
| filter by volume
GETWDINFO_HFS_NO_2:
    TST.L       D2                              | volume filter active?
    BEQ.B       GETWDINFO_HFS_NO_3              | no: accept any volume
    CMP.L       0x0(A1,D1.W),D2                 | WDVCBPtr matches filter?
    BNE.B       GETWDINFO_INDEX_LOOP            | no: skip
GETWDINFO_HFS_NO_3:
    SUBQ.W      #0x1,D4                         | decrement index counter
    BGT.B       GETWDINFO_INDEX_LOOP            | not yet: keep scanning
| found the Nth matching WDCB: fill param block
GETWDINFO_HFS_CONT_3:
    BSR.B       HFSF_CONT                       | fill PB from WDCB
GETWDINFO_FOUND_FILL:
    BSR.W       GETVOL_CONT_2                   | copy volume name to PB
GETWDINFO_HFS_ERR_2:
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from GETWDINFO_HFS_CONT
| HFS selector F: GetWDInfo (full HFS stack frame)
P_hfsF:
    MOVEM.L     D3-D7/A1-A6,-(A7)               | save regs (HFS stack frame)
    MOVEA.L     (HFSVars_HFSStkTop).W,A6        | A6 = HFS stack top
    BSR.W       GETWDINFO_HFS_CONT              | resolve WD and fill PB
    MOVEM.L     (A7)+,D3-D7/A1-A6               | restore regs
    MOVE.W      D0,0x10(A0)                     | ioResult = error code
    RTS                                         | return from P_hfsF
| ----------------------------------------------------------
|
| HFSF_CONT: copy WDCB info + procID to param block
|
HFSF_CONT:
    MOVE.L      0xC(A1,D1.W),0x1C(A0)           | ioWDProcID from WDCB (WDProcID)
| HFSF_CONT_2: copy WDCB VCB/DirID to param block
HFSF_CONT_2:
    MOVEA.L     0x0(A1,D1.W),A2                 | A2 = WDVCBPtr (volume)
    MOVE.W      0x4E(A2),0x20(A0)               | ioWDVRefNum = vcbVRefNum
    MOVE.L      0x4(A1,D1.W),0x30(A0)           | ioWDDirID from WDCB
    MOVE.W      D1,D0                           | WDCB index
    ADDI.W      #0x8001,D0                      | convert to WD refNum
    MOVE.W      D0,0x16(A0)                     | ioVRefNum = WD refNum
    RTS                                         | return from HFSF_CONT_2
| HFSF_CONT_3: validate WD refNum and return WDCB
| D1=WD refNum, returns A1=WDCB base, D1 preserved, D0=0 if valid
HFSF_CONT_3:
    MOVE.L      D1,-(A7)                        | save original D1
    MOVEQ.L     #-0x33,D0                       | dirNFErr (-51) default
    SUBI.W      #0x8001,D1                      | convert refNum to index
    MOVEA.L     (WDCBsPtr).W,A1                 | WDCB array base
    CMP.W       (A1),D1                         | index >= array size?
    BCC.B       HFSF_OK                         | yes: invalid
    SUBQ.W      #0x2,D1                         | adjust for header
    DIVU.W      #0x10,D1                        | check 16-byte alignment
    SWAP.W      D1                              | remainder in low word
    TST.W       D1                              | aligned to 16-byte WDCB?
    BNE.B       HFSF_OK                         | no: invalid index
    MOVE.L      (A7),D1                         | restore original refNum
    SUBI.W      #0x8001,D1                      | convert to index again
    TST.L       0x0(A1,D1.W)                    | WDVCBPtr: slot in use?
    BEQ.B       HFSF_OK                         | empty: invalid
    MOVEQ.L     #0x0,D0                         | valid WD
HFSF_OK:
    MOVE.L      (A7)+,D1                        | restore D1
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from HFSF_CONT_3
| HFS selector D: OpenWD (by dirID, full HFS stack)
P_hfsD:
    MOVEM.L     D3-D7/A1-A6,-(A7)               | save regs (HFS stack frame)
    MOVEA.L     (HFSVars_HFSStkTop).W,A6        | A6 = HFS stack top
    BSR.W       P_DTRMV1                        | resolve volume
    BNE.B       HFSD_ERR                        | error: exit
    MOVE.L      0x30(A0),D6                     | ioDirID
    MOVEQ.L     #0x0,D7                         | no catalog hint
    BSR.W       OPENWD_HFS_CONT_3               | allocate WDCB
    BNE.B       HFSD_ERR                        | error: exit
    MOVE.W      D1,0x16(A0)                     | ioVRefNum = WD refNum
HFSD_CONT:
    MOVEQ.L     #0x0,D0                         | no error
HFSD_ERR:
    MOVEM.L     (A7)+,D3-D7/A1-A6               | restore regs
    MOVE.W      D0,0x10(A0)                     | ioResult = error code
    RTS                                         | return from P_hfsD
| HFS selector E: SetVol (by dirID, full HFS stack)
P_hfsE:
    MOVEM.L     D3-D7/A1-A6,-(A7)               | save regs (HFS stack frame)
    MOVEA.L     (HFSVars_HFSStkTop).W,A6        | A6 = HFS stack top
    BSR.W       P_DTRMV1                        | resolve volume
    BNE.B       HFSD_ERR                        | error: exit
    MOVE.W      0x4E(A2),(DefVRefNum).W         | set default to this volume
    MOVE.L      0x30(A0),D6                     | ioDirID
    MOVEQ.L     #0x0,D7                         | no catalog hint
    BSR.W       OPENWD_HFS_CONT                 | set up default WDCB
    BRA.B       HFSD_CONT                       | success
| ----------------------------------------------------------
|
| HFSE_CONT
|
| Called during boot.
| MV_GetMFSMap: set up MFS volume - allocate alloc map and read it from disk
| MV_GetMFSMap: set up MFS volume - allocate alloc map and read from disk
HFSE_CONT:
    MOVEQ.L     #0x5E,D0                        | trim VCB to MFS size (94 bytes)
    MOVEA.L     A2,A0                           | VCB ptr
    _SetPtrSize                                 | resize VCB to MFS size
| compute alloc map size: (NmAlBlks * 1.5 + 1) / 2 (12 bits/entry)
    MOVEQ.L     #0x3,D2                         | 3 * NmAlBlks
    MULU.W      0x1A(A2),D2                     | D2 = 3 * vcbNmAlBlks
    ADDQ.L      #0x1,D2                         | round up
    LSR.L       #0x1,D2                         | / 2 = byte count for 12-bit map
    MOVE.W      D2,0x58(A2)                     | vcbMLen = alloc map length
| allocate alloc map and read from MDB
    MOVEQ.L     #0x40,D7                        | MDB offset 0x40 = alloc map start
    MOVE.L      D2,D0                           | alloc map size
    _NewPtrSys                                  | allocate memory for alloc map
    BNE.W       MTVOLER1_FLUSH_CACHES           | error: MtVolEr1
    MOVE.L      A0,0x50(A2)                     | vcbMAdr = alloc map pointer
    MOVEQ.L     #0x2,D3                         | start at block 2 (MDB block)
| copy alloc map from MDB block(s) to memory
HFSE_NO:
    MOVE.W      0x0(A5,D7.W),(A0)+              | copy alloc map word from disk
    ADDQ.W      #0x2,D7                         | advance source offset
    SUBQ.W      #0x2,D2                         | more bytes to copy?
    BLE.B       HFSE_NO_2                       | no: done copying
    CMPI.W      #0x200,D7                       | past end of 512-byte block?
    BCS.B       HFSE_NO                         | no: keep copying
| need next disk block for more alloc map data
    ADDQ.W      #0x1,D3                         | next block number
    BSR.W       FILEWRITE_NEXT_2                | read next block
    BNE.B       HFSE_ERR_2                      | read error: abort
    MOVEQ.L     #0x0,D7                         | reset offset to block start
    BRA.B       HFSE_NO                         | continue copying
| alloc map copied: verify free block count
HFSE_NO_2:
    BSR.B       HFSE_CONT_3                     | count free blocks in map
    BEQ.B       HFSE_OK_2                       | matches VCB: proceed
HFSE_ERR:
    MOVEQ.L     #-0x3C,D0                       | badMDBErr (-60)
HFSE_ERR_2:
    BSR.B       HFSE_CONT_2                     | dispose alloc map memory
    BRA.W       MTVOLER1_FLUSH_CACHES           | MtVolEr1: error exit
| ----------------------------------------------------------
|
| HFSE_CONT_2
|
| HFSE_CONT_2: dispose MFS alloc map memory
HFSE_CONT_2:
    MOVEM.L     D0/A0,-(A7)                     | save regs
    MOVEA.L     0x50(A2),A0                     | vcbMAdr (alloc map pointer)
    _DisposePtr                                 | free alloc map memory
    CLR.L       0x50(A2)                        | clear vcbMAdr
    MOVEM.L     (A7)+,D0/A0                     | restore regs
    RTS                                         | return from HFSE_CONT_2
| HFSE_CONT_3: MFS consistency check - count free blocks in alloc map
HFSE_CONT_3:
    MOVEQ.L     #0x2,D3                         | start at block 2 (first alloc)
    MOVEQ.L     #0x0,D1                         | D1 = free block count
HFSE_CONT_4:
    BSR.W       LG2PHYS_NEXT_2                  | get alloc map entry for block
    BNE.B       HFSE_NO_3                       | nonzero: block in use
    ADDQ.W      #0x1,D1                         | count free block
HFSE_NO_3:
    CMP.W       0x1A(A2),D3                     | past vcbNmAlBlks?
    BHI.B       HFSE_OK                         | yes: done scanning
    ADDQ.W      #0x1,D3                         | next block
    BRA.B       HFSE_CONT_4                     | keep scanning
HFSE_OK:
    CMP.W       0x2A(A2),D1                     | matches vcbFreeBks?
    RTS                                         | return (Z set if match)
| MFS directory scan: count files and verify alloc map
HFSE_OK_2:
    MOVEQ.L     #0x0,D1                         | D1 = file count
    MOVEQ.L     #0x0,D2                         | D2 = max file number
    MOVEQ.L     #0x0,D7                         | D7 = consistency flags
    BSR.W       FILEWRITE_CONT_4                | read first directory block
    BNE.B       HFSE_ERR_2                      | error: abort
HFSE_OK_3:
    TST.B       (A5)                            | empty directory block?
    BNE.B       HFSE_ERR_3                      | no: scan entries
    MOVEA.L     A5,A0                           | A0 = block buffer
    EXG         D1,D6                           | save file count in D6
    MOVEQ.L     #0x2,D1                         | kRBTrash (release option)
    JSR         RELBLOCK(PC)                    | release directory block
    EXG         D1,D6                           | restore file count
HFSE_ERR_3:
    MOVEQ.L     #0x0,D0                         | initial entry offset
| scan MFS directory entries in this block
HFSE_CONT_5:
    TST.B       0x0(A5,D0.W)                    | entry in use? (flags byte)
    BEQ.B       HFSE_OK_4                       | empty: end of block
    ADDQ.W      #0x1,D1                         | increment file count
| track max file number for VCBNxtCNID
    CMP.L       0x12(A5,D0.W),D2                | file number > current max?
    BHI.B       HFSE_NO_4                       | no: skip update
    MOVE.L      0x12(A5,D0.W),D2                | update max file number
| verify alloc map entries for data and resource forks
HFSE_NO_4:
    LEA.L       0x16(A5,D0.W),A3                | data fork start block in entry
    BSR.B       HFSE_CONT_7                     | verify data fork alloc chain
    BNE.B       HFSE_ERR                        | error: bad alloc map
    LEA.L       0x20(A5,D0.W),A3                | rsrc fork start block in entry
    BSR.B       HFSE_CONT_7                     | verify rsrc fork alloc chain
    BNE.B       HFSE_ERR                        | error: bad alloc map
    BSR.W       CREATE_NEXT                     | next MFS directory entry
    BCS.B       HFSE_CONT_5                     | more entries: continue
| end of block: read next directory block
HFSE_OK_4:
    BSR.W       FILEWRITE_NEXT                  | read next directory block
    BEQ.B       HFSE_OK_3                       | got block: continue scan
    CMPI.W      #0xFFDF,D0                      | eofErr (-33)? (end of dir)
    BNE.W       HFSE_ERR_2                      | other error: abort
| directory scan complete: update VCB counters
    CMP.L       0x26(A2),D2                     | max fileNum >= vcbNxtCNID?
    BCS.B       HFSE_CONT_6                     | no: vcbNxtCNID is ok
    ADDQ.L      #0x1,D2                         | max + 1 = new next CNID
    MOVE.L      D2,0x26(A2)                     | update vcbNxtCNID
    ADDQ.B      #0x1,D7                         | flag: VCB was modified
HFSE_CONT_6:
    CMP.W       0x14(A2),D1                     | vcbNmFls matches file count?
    BEQ.B       HFSE_OK_5                       | yes: ok
    MOVE.W      D1,0x14(A2)                     | fix vcbNmFls
    ADDQ.B      #0x2,D7                         | flag: file count changed
HFSE_OK_5:
    TST.B       D7                              | any VCB fields changed?
    BEQ.B       HFSE_ERR_4                      | no: skip flush
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       HFSE_ERR_4                      | write-protected: can't flush
    BSR.W       MARKVCB                         | mark VCB dirty for flush
HFSE_ERR_4:
    OR.B        D7,0x13(A2)                     | merge flags into vcbAtrb+1
    BRA.W       CHECKREMOUNT                    | go to CheckRemount
| ----------------------------------------------------------
|
| HFSE_CONT_7
|
| MFS alloc chain walk: compute PEOF from chain and update directory
| A3 -> fork info in directory entry (start block, LEOF, PEOF)
| Called during boot.
HFSE_CONT_7:
    MOVEM.L     D0-D6,-(A7)                     | save regs
    MOVE.W      0x1A(A2),D1                     | D1 = vcbNmAlBlks (max blocks)
    MOVEQ.L     #0x0,D6                         | D6 = computed PEOF (bytes)
    MOVE.L      0x1C(A2),D2                     | D2 = vcbAlBlkSiz
    MOVE.W      (A3),D3                         | D3 = start block from entry
    BEQ.B       HFSE_NO_5                       | zero: no allocation
| walk alloc chain from start block
HFSE_ERR_5:
    BSR.W       LG2PHYS_NEXT_2                  | get next block in chain
    SUBQ.W      #0x1,D1                         | safety: max blocks limit
    BCS.B       HFSE_OK_7                       | exceeded: chain too long
    MOVE.W      D5,D3                           | D3 = next block in chain
    BEQ.B       HFSE_NO_5                       | zero: end of chain
    ADD.L       D2,D6                           | D6 += alloc block size
    CMPI.W      #0x1,D3                         | block 1 = end marker
    BNE.B       HFSE_ERR_5                      | not end: keep walking
| compare computed PEOF with directory entry and fix if needed
HFSE_NO_5:
    MOVE.W      (A3)+,D3                        | D3 = start block from entry
    MOVE.L      (A3)+,D4                        | D4 = LEOF from entry
    MOVE.L      (A3)+,D5                        | D5 = PEOF from entry
    CMP.L       D5,D6                           | PEOF matches computed?
    BEQ.B       HFSE_OK_6                       | yes: entry is consistent
    MOVE.L      D6,-(A3)                        | fix PEOF in directory entry
    BNE.B       HFSE_CONT_8                     | nonzero PEOF: check LEOF
    CLR.W       D3                              | zero PEOF: clear start block
HFSE_CONT_8:
    CMP.L       D6,D4                           | LEOF > PEOF?
    BLS.B       HFSE_NO_6                       | no: LEOF is ok
    MOVE.L      D6,D4                           | truncate LEOF to PEOF
HFSE_NO_6:
    MOVE.L      D4,-(A3)                        | write back LEOF
    MOVE.W      D3,-(A3)                        | write back start block
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       HFSE_OK_7                       | protected: can't write
    JSR         MARKA5BLOCK(PC)                 | mark directory block dirty
    BSET        #0x2,D7                         | flag: directory was modified
HFSE_OK_6:
    MOVEQ.L     #0x0,D1                         | no error
HFSE_OK_7:
    MOVEM.L     (A7)+,D0-D6                     | restore regs
    RTS                                         | return from HFSE_CONT_7
| ----------------------------------------------------------
|
| HFSE_CONT_9
|
| MFS FlushVol: flush VCB info back to MDB on disk
| Called during boot.
HFSE_CONT_9:
    MOVE.L      (A7)+,-(A6)                     | save return addr on A6 stack
    MOVEM.L     D1-D7/A0-A5,-(A6)               | save all regs
    TST.W       0x48(A2)                        | vcbDrvNum: volume online?
    BEQ.B       HFSE_NO_9                       | offline: skip flush
    TST.B       0x6(A2)                         | vcbFlags: VCB dirty?
    BPL.B       HFSE_FLUSH_VOL_CACHES           | not dirty: skip MDB write
| verify alloc map consistency before flushing
    BSR.W       HFSE_CONT_3                     | count free blocks in map
    BNE.B       HFSE_FLUSH_VOL_CACHES           | mismatch: skip (inconsistent)
| read MDB block and copy VCB info back to it
    MOVEQ.L     #0x2,D3                         | MDB is block 2
    BSR.W       FILEWRITE_CONT_5                | read MDB block for writing
    BNE.B       HFSE_ERR_RESTORE                | read error: abort
    JSR         MARKA5BLOCK(PC)                 | mark MDB block dirty
| copy VCB core info to MDB (32 words = 64 bytes)
    MOVEQ.L     #0x1F,D0                        | 32 words to copy
    MOVEA.L     A5,A1                           | A1 = MDB block buffer
    LEA.L       0x8(A2),A0                      | A0 = vcbSigWord
    MOVE.L      (Time).W,0xE(A2)                | update vcbLsMod timestamp
HFSE_LOOP:
    MOVE.W      (A0)+,(A1)+                     | copy VCB word to MDB
    DBF.W       D0,HFSE_LOOP                    | loop all 32 words
| copy alloc map from memory back to MDB block(s)
    MOVEA.L     0x50(A2),A0                     | vcbMAdr (alloc map in memory)
    MOVE.W      0x58(A2),D2                     | vcbMLen (alloc map length)
    MOVEQ.L     #0x40,D7                        | MDB offset 0x40 = alloc map
HFSE_NO_7:
    MOVE.W      (A0)+,0x0(A5,D7.W)              | copy alloc map word to block
    ADDQ.W      #0x2,D7                         | advance dest offset
    SUBQ.W      #0x2,D2                         | more bytes?
    BLE.B       HFSE_NO_8                       | no: done
    CMPI.W      #0x200,D7                       | past end of 512-byte block?
    BCS.B       HFSE_NO_7                       | no: keep copying
| alloc map spans block boundary: get next block
    ADDQ.W      #0x1,D3                         | next block number
    BSR.W       FILEWRITE_CONT_5                | read next block for writing
    BNE.B       HFSE_ERR_RESTORE                | error: abort
    JSR         MARKA5BLOCK(PC)                 | mark block dirty
    MOVEQ.L     #0x0,D7                         | reset offset to block start
    BRA.B       HFSE_NO_7                       | continue copying
| ----------------------------------------------------------
|
| HFSE_NO_8
|
| zero-fill remaining bytes in last MDB block
HFSE_NO_8:
    CMPI.W      #0x200,D7                       | past end of block?
    BCC.B       HFSE_FLUSH_VOL_CACHES           | yes: done padding
    CLR.W       0x0(A5,D7.W)                    | zero-fill unused bytes
    ADDQ.W      #0x2,D7                         | next word
    BRA.B       HFSE_NO_8                       | keep padding
| flush caches for this volume
HFSE_FLUSH_VOL_CACHES:
    BSR.W       OFFLINE_CONT_2                  | flush/close B-tree + caches
    BNE.B       HFSE_ERR_RESTORE                | error: abort
| MFS unmount path
HFSE_NO_9:
    CLR.B       0x6(A2)                         | clear vcbFlags (no longer dirty)
    TST.B       (FlushOnly).W                   | flush only?
    BNE.B       HFSE_ERR_6                      | yes: done (don't dispose)
    TST.W       0x48(A2)                        | vcbDrvNum: online?
    BEQ.B       HFSE_DEALLOC_THEN_DEQUEUE       | offline: skip alloc map free
    BSR.W       HFSE_CONT_2                     | dispose MFS alloc map
HFSE_DEALLOC_THEN_DEQUEUE:
    BSR.W       BMCHK_CONT_2                    | dequeue and dispose VCB
HFSE_ERR_6:
    MOVEQ.L     #0x0,D0                         | no error
HFSE_ERR_RESTORE:
    MOVEM.L     (A6)+,D1-D7/A0-A5               | restore all regs
    MOVE.L      (A6)+,-(A7)                     | restore return addr
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from HFSE_CONT_9
| SetVolInfo_hfs: indexed volume info (same structure as GetVolInfo)
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    MOVE.W      0x1C(A0),D2                     | ioVolIndex
    BGT.B       HFSE_OK_10                      | > 0: index into VCB queue
    BEQ.B       HFSE_RESOLVE_BY_REFNUM          | = 0: resolve by ioVRefNum
    BSR.W       P_DTRMV3                        | < 0: resolve by name/refNum
    BRA.B       HFSE_CONT_11                    | check result
HFSE_RESOLVE_BY_REFNUM:
    BSR.W       P_DTRMV1                        | resolve by ioVRefNum only
HFSE_CONT_11:
    BNE.B       HFSE_COPY_VOLNAME_DONE          | error: exit
    BRA.B       HFSE_OK_11                      | found: check files open
| index into VCB queue
HFSE_OK_10:
    MOVE.L      (VCBQHdr_Head).W,D1             | start of VCB queue
HFSE_CONT_12:
    BEQ.W       GETVOL_NO                       | end of queue: not found
    SUBQ.W      #0x1,D2                         | decrement index
    MOVEA.L     D1,A2                           | A2 = VCB at this index
    BEQ.B       HFSE_OK_11                      | index hit 0: found it
    MOVE.L      (A2),D1                         | qLink: next VCB
    BRA.B       HFSE_CONT_12                    | keep counting
| ----------------------------------------------------------
|
| HFSE_OK_11
|
| check if any files are open on this volume
HFSE_OK_11:
    BSET        #0x6,0x13(A2)                   | assume files are open
    BSR.B       HFSE_CONT_14                    | Gt1stFCB: get first FCB
HFSE_CONT_13:
    CMPA.L      0x14(A1,D1.W),A2                | FCBVPtr: belongs to this vol?
    BEQ.B       HFSE_NO_OPEN_FILES              | yes: file is open
    BSR.B       HFSE_NEXT                       | GtNxtFCB: next FCB
    BCS.B       HFSE_CONT_13                    | more: keep scanning
    BCLR        #0x6,0x13(A2)                   | no files open: clear flag
HFSE_NO_OPEN_FILES:
    MOVEQ.L     #0x20,D0                        | copy 34 bytes (17 words)
| copy VCB info to param block
HFSE_OK_13:
    MOVE.W      0xA(A2,D0.W),0x1E(A0,D0.W)      | VCB field -> PB field
    SUBQ.W      #0x2,D0                         | next word
    BPL.B       HFSE_OK_13                      | loop all VCB info words
    BSR.W       GETVOL_CONT_2                   | copy volume name to PB
HFSE_COPY_VOLNAME_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| HFSE_CONT_14
|
| Gt1stFCB: get first FCB entry
| Returns: A1 = FCB array base, D1 = 2 (first FCB offset)
| Called during boot.
HFSE_CONT_14:
    MOVEA.L     (FCBSPtr).W,A1                  | FCB array base
    MOVEQ.L     #0x2,D1                         | first FCB at offset 2
    RTS                                         | return from Gt1stFCB
| ----------------------------------------------------------
|
| HFSE_NEXT
|
| GtNxtFCB: advance to next FCB entry
| D1 += 0x5E (FCB entry size = 94 bytes), sets C if more entries
| Called during boot (1,205 times in 30s trace).
HFSE_NEXT:
    ADDI.W      #0x5E,D1                        | advance by FCB entry size
    CMP.W       (A1),D1                         | past end of FCB array?
    RTS                                         | return (C set if more)
| ----------------------------------------------------------
|
| HFSE_CONT_15
|
| HFSE_CONT_15: find FCB by file number + volume
| D2 = file number, A2 = VCB
| Returns: D1 = FCB offset, Z set if found
| Called during boot.
HFSE_CONT_15:
    BSR.B       HFSE_CONT_14                    | Gt1stFCB: get first FCB
HFSE_CONT_16:
    CMP.L       0x0(A1,D1.W),D2                 | FCBFlNm matches file number?
    BNE.B       HFSE_ERR_9                      | no: try next
    CMPA.L      0x14(A1,D1.W),A2                | FCBVPtr matches volume?
    BEQ.B       HFSE_OK_14                      | yes: found (Z set)
| Called by: HFSE_CONT_16, FILEOPEN_SKIP, PERMSSNCHK_NO_2, RENAME_CONT_2, HFSCATMOVE_CONT (and 3 more)
HFSE_ERR_9:
    BSR.B       HFSE_NEXT                       | GtNxtFCB: next FCB
    BCS.B       HFSE_CONT_16                    | more: keep scanning
    MOVE.W      #0x0,CCR                        | clear Z (not found)
HFSE_OK_14:
    RTS                                         | return from FindFCBByNum
