| File Manager - MFS core, HFS dispatch, trap handlers
|
| Manages file I/O on MFS (Macintosh File System) and HFS (Hierarchical
| File System) volumes. This file contains the trap dispatch entry points
| and MFS core operations.
|
| High-level routines: FSOpen, FSRead, FSWrite, FSClose, GetFPos, SetFPos
| Low-level routines: PBOpen, PBRead, PBWrite, PBClose, PBGetFPos, etc.
| All low-level calls take A0 = ParmBlkPtr (Inside Macintosh: Files, p 2-6).
|
| File operations on open files (Inside Macintosh: Files, Table 2-2):
| FSRead/PBRead - read bytes from an open file fork
| FSWrite/PBWrite - write bytes to an open file fork
| FSClose/PBClose - close an open file fork
| GetFPos/PBGetFPos - get file mark position
| SetFPos/PBSetFPos - set file mark position
| GetEOF/PBGetEOF - get logical end-of-file
| SetEOF/PBSetEOF - set logical end-of-file
| Allocate/PBAllocate - add allocation blocks to a fork
|
| File operations on closed files (Inside Macintosh: Files, Table 2-3):
| Create/PBHCreate - create both forks of a new file
| Delete/PBHDelete - delete both forks of a file
| GetFileInfo/PBHGetFInfo - get Finder information
| Rename/PBHRename - rename a file or directory
| CatMove/PBCatMove - move a file within a volume
|
| Volume operations:
| MountVol - mount a volume from a disk
| FlushVol - flush volume buffers to disk
| UnmountVol - unmount a volume
| Eject - eject a disk
| GetVolInfo/PBHGetVInfo - get volume information
|
| Split into 2 files in classic (Plus splits into 5):
| file_mgr.s - trap handlers, MFS core
| file_mgr_io.s - file I/O (Open, Read, Write, Close, extent alloc)
| (Plus adds: file_mgr_catalog.s, file_mgr_btree.s, file_mgr_cache.s
| -- HFS catalog / B-tree / block cache, none of which exist in
| classic since classic is MFS-only.)
|
| VCB - Volume Control Block (MPW 1.0 Files.h):
| Offset 0: qLink Ptr next VCB in queue
| Offset 4: qType INTEGER queue type
| Offset 6: vcbFlags INTEGER volume flags
| Offset 8: vcbSigWord INTEGER volume signature ($4244=MFS, $4244=HFS)
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
| _PostEvent ($A02F)
| A0 = event number (0-15), D0 = event message -> D0 = error
| Posts an event to the system event queue if the event type is
| enabled in SysEvtMask. Returns evtNotEnb (1) if event masked out.
| Called during boot.
PostEvent:
        MOVE    (SysEvtMask).w,D2               | store evtMessage
        MOVE    A0,D1                           | evtTicks = current tick count
        BTST    D1,D2                           | test bit D1 of D2
        BNE.B   POSTEVENT_CONT                  | event type enabled -> post it
        MOVEQ.L #0x1,D0                         | D0 = 1 = evtNotEnb
        RTS                                     | return: event type masked out
POSTEVENT_CONT:
        MOVE    SR,-(SP)                        | evtMBut = mouse button state
        MOVE.L  D0,-(SP)                        | save evtMessage
        MOVE    A0,-(SP)                        | save evtNum
        MOVE.L  (SysEvtBuf).w,A0                | A0 = system event buffer
        ADDQ.L  #0x6,A0                         | skip header (qLink/qType/qWhat)
        MOVEQ.L #0x16,D0                        | D0 = 22 = sizeof(EventRecord)
        MOVEQ.L #-0x1,D1                        | D1 = -1 (free-slot marker)
        SUBA.W  D0,A0                           | back up by one record-size
        MOVE    (EvtBufCnt).w,D2                | D2 = max queue slots
        ORI     #0x100,SR                       | disable interrupts (IPL 1)
POSTEVENT_SCAN_LOOP:
        ADDA.W  D0,A0                           | advance to next slot
        CMP     (A0),D1                         | slot free (evtQWhat = -1)?
        DBEQ    D2,POSTEVENT_SCAN_LOOP          | dbeq loop
        LEA.L     (EventQueue).w,A1             | A1 = event queue header
        BEQ.B   POSTEVENT_FILL                  | queue empty -> check auto-key repeat
        MOVE.L  2(A1),A0                        | A1 = current queue element
        MOVE.L  (A0),2(A1)                      | D1 = evtNum (at offset 6 in queue element)
        ADDQ.L  #0x6,A0                         | skip past qLink/qType/qWhat
POSTEVENT_FILL:
        MOVE    (SP)+,(A0)                      | slot.evtNum = saved A0
        MOVE.L  (SP)+,2(A0)                     | D1 = qLink (next element)
        BSR.B   FILL_EVENT_FIELDS               | timestamp / mouse / keymap / mBut
        SUBQ.L  #0x6,A0                         | back up to start of queue element
        MOVE    #0x4,4(A0)                      | qType = 4 (event queue type)
        JSR     Enqueue(PC)                     | enqueue at tail of EventQueue
        MOVE    (SP)+,SR                        | restore interrupts
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
        RTS                                     | return from PostEvent
FILL_EVENT_FIELDS:
        MOVE.L  (Ticks).w,6(A0)                 | evtTicks = current tick count
        MOVE.L  (Mouse_v).w,10(A0)              | evtWhere = mouse position
        MOVE    (KeyMap_6).w,D1                 | D1 = high word of KeyMap (modifiers)
        ROL     #0x1,D1                         | rotate caps-lock bit into byte
        MOVE.B  D1,14(A0)                       | evtMeta = modifier flags
        MOVE.B  (MBState).w,15(A0)              | evtMBut = mouse-button state
        RTS                                     | return from event-field fill

| ----------------------------------------------------------
| _OSEventAvail ($A030)
| D0 = event mask (bit per event type), A0 = event record buffer ->
| D0 = 0 if event found (copied to buffer), D0 = -1 if no matching event.
| Peeks at the event queue without dequeuing. Also generates auto-key
| repeat events (autoKeyEvt=5) when a key is held past KeyThresh ticks.
| Called during boot (32,478 times in 30s trace).
OSEventAvail:
        LEA.L     (EventQueue).w,A1             | A1 = event queue header
        MOVE    SR,-(SP)                        | save interrupt mask
        ORI     #0x100,SR                       | disable interrupts (IPL 1)
        MOVE.L  2(A1),D1                        | D1 = head EvQEl ptr
        BEQ.B   OSEVENT_NOMATCH                 | queue empty -> check autoKey
OSEVENT_WALK:
        MOVE.L  D1,A1                           | A1 = current EvQEl
        MOVE    6(A1),D1                        | D1 = evtQWhat (event type)
        BTST    D1,D0                           | test bit D1 of D0
        BNE.B   OSEVENT_RETURN                  | matching event found ->
        MOVE.L  (A1),D1                         | D1 = next EvQEl (qLink)
        BNE.B   OSEVENT_WALK                    | more entries -> keep walking
OSEVENT_NOMATCH:
        AND     (SysEvtMask).w,D0               | mask request by SysEvtMask
        TST     (KeyLast).w                     | any key currently held?
        BEQ.B   OSEVENT_NONE                    | no held key -> no autoKey
        BTST    #0x5,D0                         | autoKey enabled in mask?
        BEQ.B   OSEVENT_NONE                    | no -> skip repeat generation
        MOVE.L  (Ticks).w,D1                    | D1 = current tick count
        MOVE.L  D1,D2                           | D2 = copy of Ticks
        SUB.L   (KeyTime).w,D1                  | D1 = ticks since key down
        CMP     (KeyThresh).w,D1                | past initial threshold?
        BLT.B   OSEVENT_NONE                    | not yet -> no repeat
        SUB.L   (KeyRepTime).w,D2               | D2 = ticks since last repeat
        CMP     (KeyRepThresh).w,D2             | past repeat interval?
        BLT.B   OSEVENT_NONE                    | not yet -> no repeat
        MOVE.L  (Ticks).w,(KeyRepTime).w        | KeyRepTime = now
        MOVE.L  A0,-(SP)                        | save event-record buffer ptr
        MOVE    #0x5,A0                         | A0 = 5 = autoKeyEvt
        MOVEQ.L #0x0,D0                         | clear D0 high bits
        MOVE    (KeyLast).w,D0                  | D0 = KeyLast (key + modifiers)
        BSR.W   PostEvent                       | post auto-key event
        MOVE.L  A0,A1                           | A1 = posted EvQEl
        MOVE.L  (SP)+,A0                        | restore event-record buffer
OSEVENT_RETURN:
        MOVE    (SP)+,SR                        | restore interrupts
        MOVEQ.L #0x4,D0                         | D0 = 4 longs to copy (16 bytes)
        MOVEM.L A0-A1,-(SP)                     | save A0/A1 across copy
        ADDQ.L  #0x6,A1                         | skip qLink/qType in EvQEl
OSEVENT_COPY_LOOP:
        MOVE.L  (A1)+,(A0)+                     | copy 4 bytes EvQEl -> EventRecord
        SUBQ.W  #0x1,D0                         | decrement long counter
        BNE.B   OSEVENT_COPY_LOOP               | more longs to copy ->
        MOVEM.L (SP)+,A0-A1                     | restore A0/A1
        RTS                                     | return: matching event copied
OSEVENT_NONE:
        BSR.W   FILL_EVENT_FIELDS               | fill caller's record (no event)
        MOVE    (SP)+,SR                        | restore interrupts
        CLR     (A0)                            | evt.what = nullEvent
        CLR.L   2(A0)                           | evt.message = 0
        MOVEQ.L #-0x1,D0                        | D0 = -1 = no matching event
        RTS                                     | return: no event found

| ----------------------------------------------------------
| GetOSEvent -- _GetOSEvent ($A031). Plus event_mgr.s 36.
| Like OSEventAvail but also dequeues the matching event.
GetOSEvent:
        BSR.W   OSEventAvail                    | find matching event; A1 = EvQEl ptr
        BNE.B   GETOSEVENT_DONE                 | no match - return non-zero
        MOVE.L  A1,A0                           | A0 = EvQEl to dequeue
        LEA.L     (EventQueue).w,A1             | A1 = event queue header
        BSR.B   DEQUEUE_INVALIDATE              | dequeue + mark slot free
        MOVEQ.L #0x0,D0                         | D0 = 0: event found
GETOSEVENT_DONE:
        RTS                                     | return D0 = 0 (found) or non-zero

| ----------------------------------------------------------
| DEQUEUE_INVALIDATE -- Plus event_mgr.s 53.
| Remove EvQEl from queue and mark slot evtQWhat = -1 (free).
DEQUEUE_INVALIDATE:
        JSR     Dequeue(PC)                     | unlink A0 from queue at A1
        MOVE    #-0x1,6(A0)                     | mark slot free (evtQWhat = -1)
        RTS                                     | return after dequeue + invalidate

| ----------------------------------------------------------
| FlushEvents -- _FlushEvents ($A032). Plus event_mgr.s 68 (the
| routine Plus mislabels as "GetGDevice" -- actually FlushEvents).
| D0.W = eventMask, D0 high word = stopMask. Removes events
| matching eventMask; stops if it hits an event matching stopMask.
FlushEvents:                                    | call subroutine via A1
        MOVE    SR,-(SP)                        | D2 = FSQueueHook callback
        MOVEM.L D3-D4,-(SP)                     | save scratch regs
        MOVE.L  D0,D1                           | D1 = D0 (mask + stopMask)
        SWAP    D1                              | D1.W = stopMask (high half)
        MOVE    D0,D4                           | D4 = eventMask
        LEA.L     (EventQueue).w,A1             | A1 = event queue header
        ORI     #0x100,SR                       | disable interrupts (IPL 1)
        MOVE.L  2(A1),D3                        | D3 = head EvQEl ptr
        BEQ.B   FLUSH_QUEUE_EMPTY               | queue empty -> done
FLUSH_WALK_LOOP:
        MOVE.L  D3,A0                           | A0 = current EvQEl
        MOVE.L  (A0),D3                         | D3 = next EvQEl (qLink)
        MOVE    6(A0),D2                        | D2 = evtQWhat
        BTST    D2,D1                           | test bit D2 of D1
        BNE.B   FLUSH_EXIT                      | stopMask hit -> abort flush
        BTST    D2,D4                           | test bit D2 of D4
        BEQ.B   FLUSH_NEXT_ENTRY                | not in mask -> skip
        BSR.B   DEQUEUE_INVALIDATE              | remove + invalidate slot
FLUSH_NEXT_ENTRY:
        TST.L   D3                              | more entries?
        BNE.B   FLUSH_WALK_LOOP                 | yes -> continue walk
FLUSH_QUEUE_EMPTY:
        MOVEQ.L #0x0,D2                         | D2 = 0 (no stopMask hit)
FLUSH_EXIT:
        MOVEM.L  (SP)+,D3-D4                    | restore scratch regs
        MOVE.W   D2,D0                          | D0.W = stopped-on-event code
        RTE                                     | restore SR + return
FSQUEUE_CLR_OFFLINE:
        BCLR    #0xA,D1                         | clear async/offline flag in D1
| FSQUEUE_SETUP -- fSQueue: wait our turn.
| Called by: Eject, FlushVol, SetVol, GetVol, GetVolInfo (and 17 more)
FSQUEUE_SETUP:
        MOVE.L  (FSQueueHook).w,D2              | D2 = optional pre-call hook
        BLE.B   FSCall                          | no hook -> skip
        MOVE.L  D2,A1                           | A1 = hook address
        JSR     (A1)                            | call subroutine via A1
| apply scroll: offset the region by (D4, D5) pixels
FSCall:
        MOVE    #0x1,ioResult(A0)               | ioResult = 1 (in progress)
        MOVE    D1,ioTrap(A0)                   | ioTrap = D1 (trap word)
        MOVE.L  (SP)+,ioCmdAddr(A0)             | ioCmdAddr = popped driver-entry ptr
        MOVE    #0x5,qType(A0)                  | qType = 5 (user queue type)
        BTST    #0xA,D1                         | async-call bit set in trap word?
        BEQ.B   FSCALL_CONT                     | call subroutine via A1
        TST.B   (FrcSync).w                     | force-sync override active?
        BEQ.B   FSQUEUE_ENQUEUE                 | no -> queue async, return now
        BRA.B   FSQUEUE_FCALL_NOCMD             | forced sync: enqueue + wait
FSCALL_CONT:
        CLR.L    12(A0)                         | clear ioCompletion (sync call)
FSQUEUE_FCALL_NOCMD:
        MOVE.L   A0,-(SP)                       | A1 = hook address
        BSR.B   FSQUEUE_ENQUEUE                 | enqueue + dispatch FS work
        MOVE.L  (SP)+,A0                        | restore param-block ptr
FSCALL_WAIT:
        MOVE    16(A0),D0                       | D0 = ioResult
        BGT.B   FSCALL_WAIT                     | ioResult>0 -> still in progress
        CMPI    #-0x35,D0                       | ioResult == volOffLinErr?
        BNE.B   FSQUEUE_WAIT_NODSKHOOK          | no -> normal exit
        MOVE.L  (DskSwtchHook).w,-(SP)          | push optional disk-switch hook
        BGT.B   FSQUEUE_WAIT_NODSKHOOK          | hook present -> call it via RTS
        ADDQ.W  #0x4,SP                         | no hook installed -> drop addr
FSQUEUE_WAIT_NODSKHOOK:
        RTS                                     | return from FS sync wait
FSQUEUE_ENQUEUE:
        LEA.L     (FSQHdr_Flags).w,A1           | A1 = FSQueue header
        JSR     Enqueue(PC)                     | enqueue param block at FS tail
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
FSQUEUE_TRY_LOCK:                               | call subroutine via A1
        BSET    #0x0,(FSQHdr_Flags).w           | test-and-set FS busy flag
        BEQ.B   FSQUEUE_DISPATCH                | we got the lock -> dispatch
        MOVEQ.L #0x0,D0                         | D0 = 0 (queued for later)
        RTE                                     | restore SR + return
FSQUEUE_DISPATCH:
        MOVE    (SP)+,SR                        | restore interrupts
        MOVE.L  (FSQHdr_Head).w,A0              | A0 = head param block
        MOVE.L  8(A0),A1                        | A1 = ioCmdAddr (driver entry)
        MOVEM.L D3-D7/A2-A6,-(SP)               | save callee-saved regs
        JSR     (A1)                            | call subroutine via A1
        MOVEM.L (SP)+,D3-D7/A2-A6               | restore callee-saved regs
        RTS                                     | return from FS dispatch
FSQUEUE_DONE:
        MOVE.L  (ExtFSHook).w,D2                | D2 = external FS post-hook
        BLE.B   FSQUEUE_DEQUEUE                 | no hook -> skip
        MOVE.L  D2,A1                           | A1 = ExtFS post-hook addr
        JSR     (A1)                            | call subroutine via A1
FSQUEUE_DEQUEUE:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
        CLR     (FSQHdr_Flags).w                | release FS busy lock
        MOVE.L  (FSQHdr_Head).w,A0              | A0 = current head paramBlk
        CMPI    #0x5,4(A0)                      | qType == 5 (FS user req)?
        BNE.W   LG2PHYS_ERR                     | corrupt queue -> trap to error
        MOVE.L  (A0),(FSQHdr_Head).w            | unlink head: head = head.qLink
        BNE.B   FSQUEUE_RESTORED_SR             | more entries -> keep tail
        CLR.L   (FSQHdr_Tail).w                 | queue empty -> clear tail
FSQUEUE_RESTORED_SR:
        MOVE    (SP)+,SR                        | restore interrupts
        MOVE    D0,16(A0)                       | ioResult = D0 (final result)
        MOVE.L  12(A0),D1                       | D1 = ioCompletion proc
        BEQ.B   FSQUEUE_COMPLETE                | no completion -> skip
        MOVE.L  D1,A1                           | A1 = ioCompletion proc
        TST     D0                              | set CCR for completion proc
        JSR     (A1)                            | call subroutine via A1
FSQUEUE_COMPLETE:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
        TST.L   (FSQHdr_Head).w                 | more pending requests?
        BNE.B   FSQUEUE_TRY_LOCK                | head non-nil -> retry lock
        RTE                                     | restore SR + return
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
        MOVE.L  (FSQHdr_Head).w,D0              | D0 = head paramBlk
        BEQ.B   FSQUEUE_CHK_MORE                | empty queue -> done
        MOVE.L  D0,A0                           | A0 = paramBlk to terminate
        CLR.L   (A0)                            | clear qLink (last in queue)
        MOVE.L  A0,(FSQHdr_Tail).w              | FSQHdr_Tail = A0
FSQUEUE_CHK_MORE:
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        RTE                                     | restore SR + return
        BSR.W   FSQUEUE_CLR_OFFLINE             | clear offline flag in trap word
        ST      (NewMount).w                    | (NewMount).w := -1 (true)
        MOVEQ.L #-0x32,D0                       | D0 = -50 = paramErr (default)
        MOVE    22(A0),D2                       | D2 = ioVRefNum (drive number)
        BLE.B   MOUNTVOL_ERR                    | invalid drive -> error
        MOVE    D2,D0                           | D0 = drive number
        BSR.W   FindVCBDrv                      | search for VCB matching drive
        BNE.B   MOUNTVOL_HAVEDRIVE              | VCB found -> go on
        MOVEQ.L #-0x37,D0                       | D0 = -55 = volOnLinErr
MOUNTVOL_ERR:
        BRA.B   FSQUEUE_DONE                    | finish with error in D0
MOUNTVOL_HAVEDRIVE:
        BSR.W   FindDrive                       | locate DrvQEl for D2
        BNE.B   MOUNTVOL_ERR                    | drive not in queue -> error
        MOVE.L  A0,A2                           | A2 = DrvQEl ptr
        MOVEQ.L #0x5E,D0                        | D0 = 94 (sizeof VCB)
        _NewPtrSysClear                         | allocate cleared VCB in SysZone
        BNE.B   MOUNTVOL_ERR                    | allocation failed -> error
        EXG     A0,A2                           | A0=DrvQEl A2=new VCB
        MOVE    D2,0x48(A2)                     | vcbDrvNum = drive number
        MOVE    D1,0x4A(A2)                     | vcbDRefNum = driver refNum
MOUNTVOL_INIT_LOOP:
        SUBQ.W  #0x1,D0                         | decrement byte counter

| ROM section: src/os/file_mgr.asm
| Called during boot.
| _MountVol: mount a volume from disk
MountVol:
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
        MOVEQ.L #-0x39,D0                       | D0 = memFullErr (-57)
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
        MOVE.B  19(A0),19(A2)                   | inherit write-protect attrib
        LEA.L     8(A0),A1                      | A1 = candidate VCB sigWord
        LEA.L     vcbSigWord(A2),A3             | A3 = &8(A2)
        MOVEQ.L #0xF,D0                         | D0 = 15 (16 longs to compare)
MOUNTVOL_CMP_NAME:
        CMPM.L  (A1)+,(A3)+                     | compare VCB long for remount
        BNE.B   MOUNTVOL_NEXT_VCB               | mismatch -> next VCB
        DBRA    D0,MOUNTVOL_CMP_NAME            | compare all 16 longs
        TST     (A1)                            | extra padding word match?
        BNE.B   MOUNTVOL_NEXT_VCB               | no -> next VCB
        CLR.B   (NewMount).w                    | NewMount = 0 (it's a remount)
        MOVE.L  (A3)+,(A1)+                     | transfer additional VCB info
        MOVE.L  vcbBufAdr(A2),0x54(A0)          | reuse new VCB's buf in old VCB
        EXG     A0,A2                           | A0=new VCB A2=old VCB
        _DisposePtr                             | free new VCB (use old)
        BRA.B   MOUNTVOL_REGISTER               | -> finish registration
MOUNTVOL_NEXT_VCB:
        MOVE.L  (A0),D0                         | D0 = qLink (next VCB)
        BRA.B   MOUNTVOL_CHK_QUEUE              | loop comparing VCBs
MOUNTVOL_ERR_DISP_MDB:
        BSR.B   DISPOSE_VCB_MDB                 | free volume bitmap buffer
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
        MOVEQ.L #0x3,D2                         | D2 = 3 bytes per block in map
        MULU    vcbNmAlBlks(A2),D2              | D2 = D2 *u 26(A2)
        ADDQ.L  #0x1,D2                         | round up by 1 byte
        LSR.L   #0x1,D2                         | /2 -> bitmap length in words
        MOVE    D2,vcbMLen(A2)                  | vcbMLen = bitmap word count
        MOVEQ.L #0x40,D7                        | D7 = 64 = MDB header size
        MOVE.L  D2,D0                           | D0 = bitmap byte count
        _NewPtrSys                              | allocate volume bitmap
        BNE.B   MOUNTVOL_ERR_DISP_BUF           | allocation failed -> error
        MOVE.L  A0,vcbMAdr(A2)                  | vcbMAdr = bitmap buffer
| copy alloc map from MDB block(s) to memory
HFSE_NO:
        MOVE    0(A5,D7.W),(A0)+                | copy alloc map word from disk
        ADDQ.W  #0x2,D7                         | advance source offset
        SUBQ.W  #0x2,D2                         | more bytes to copy?
        BLE.B   HFSE_NO_2                       | no ->
        CMPI    #0x200,D7                       | past end of 512-byte block?
        BCS.B   HFSE_NO                         | no, keep copying
        ADDQ.W  #0x1,D3                         | next block number
        BSR.W   HFSE_READ_VBM_BLOCK             | read next VBM block
        BNE.B   MOUNTVOL_ERR_DISP_MDB           | read failed -> err + free MDB
        MOVEQ.L #0x0,D7                         | reset offset to start of block
        BRA.B   HFSE_NO                         | continue copying
HFSE_NO_2:
        MOVEQ    #0x2,D3                        | D3 = 2 (first alloc block)
        MOVEQ    #0x0,D1                        | D1 = 0 (free-block counter)
HFSE_NO_CONT:
        BSR.W   LG2PHYS_NEXT_2                  | LG2PHYS_NEXT_2: get next block from alloc map
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
        BNE.W   MOUNTVOL_ERR_DISP_MDB           | mismatch -> err + free MDB
        MOVEQ.L #0x0,D1                         | D1 = file count
        MOVEQ.L #0x0,D2                         | D2 = max file number
        MOVEQ.L #0x0,D7                         | D7 = consistency flags
        BSR.W   FILEFILETFSETCATINFO_HFS_CONT_2_CONT | call helper
        BNE.W   MOUNTVOL_ERR_DISP_MDB           | helper failed -> err + free MDB
HFSE_NO_CONT_2:
        MOVEQ.L #0x0,D0                         | D0 = 0 (offset within dir blk)
HFSE_CONT_5:
        TST.B   0(A5,D0.W)                      | dir entry's flag byte set?
        BEQ.B   HFSE_OK_4                       | free entry -> skip
        ADDQ.W  #0x1,D1                         | increment file count
        CMP.L   0x12(A5,D0.W),D2                | file number > current max?
        BHI.B   HFSE_CONT_5_NEWMAX              | no -> skip update
        MOVE.L  0x12(A5,D0.W),D2                | record new max file number
HFSE_CONT_5_NEWMAX:
        LEA.L     0x16(A5,D0.W),A3              | A3 = &first-extent record
        BSR.W   HFSE_OK_4_CONT_3                | check extent consistency
        LEA.L     0x20(A5,D0.W),A3              | A3 = &second-extent record
        BSR.B   HFSE_OK_4_CONT_3                | check extent consistency
        BSR.W   CREATE_NEXT                     | advance to next dir entry
        BCS.B   HFSE_CONT_5                     | more in this block ->
HFSE_OK_4:
        BSR.W   FILEWRITE_NEXT                  | call helper
        BEQ.B   HFSE_NO_CONT_2                  | more dir blocks -> next
        CMPI    #-0x21,D0                       | eofErr (-39)?
        BNE.W   MOUNTVOL_ERR_DISP_MDB           | error ->
        CMP.L   vcbNxtCNID(A2),D2               | max file num >= NxtCNID?
        BCS.B   HFSE_OK_4_CONT                  | unsigned less ->
        ADDQ.L  #0x1,D2                         | bump past current max
        MOVE.L  D2,vcbNxtCNID(A2)               | VCB field
        ADDQ.B  #0x1,D7                         | flag: VCB was modified
HFSE_OK_4_CONT:
        CMP     vcbNmFls(A2),D1                 | file count matches MDB?
        BEQ.B   HFSE_OK_4_OK                    | ok ->
        MOVE    D1,vcbNmFls(A2)                 | VCB field
        ADDQ.B  #0x2,D7                         | flag: file count changed
HFSE_OK_4_OK:
        TST.B   D7                              | any consistency changes?
        SNE     vcbFlags(A2)                    | 6(A2) := (Z != 0)
        LEA.L     (Params).w,A0                 | A0 = scratch param block
        MOVE    #0x8,csCode(A0)                 | csCode = 8 (Get Drv Info)
        _Status                                 | get drive write-protect status
        TST.B   ioFlAttrib(A0)                  | write-locked flag in returned attribute byte
        BPL.B   HFSE_OK_4_SKIP_BSET             | non-neg -> skip BSET
        BSET    #0x7,D7                         | D7 |= 1<<0x7 (flag: write-lock?)
HFSE_OK_4_SKIP_BSET:
        MOVE.B  D7,19(A2)                       | update PEOF in directory
        MOVE.L  (FSQHdr_Head).w,A0              | A0 = current FS request
        MOVE    vcbVRefNum(A2),ioVRefNum(A0)    | return vRefNum to caller
        TST.B   (NewMount).w                    | new mount (vs remount)?
        BEQ.B   HFSE_OK_4_CONT_2                | remount -> skip enqueue
        MOVE.L  A2,A0                           | yes, pin LEOF to PEOF
        LEA.L     (VCBQHdr_Flags).w,A1          | A1 = VCB queue header
        TST.L   0x2(A1)                         | VCBQHdr_Head != nil? (any volumes?)
        BNE.B   HFSE_OK_4_SKIP_DEFVCB           | yes -> skip DefVCBPtr update
        MOVE.L  A2,(DefVCBPtr).w                | first volume -> set as default
HFSE_OK_4_SKIP_DEFVCB:
        JSR     Enqueue(PC)                     | insert new VCB into queue
HFSE_OK_4_CONT_2:
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.W   MOUNTVOL_ERR                    | finish via shared exit
HFSE_OK_4_CONT_3:
        MOVEM.L D2-D6,-(SP)                     | save D2-D6 across walk
        MOVEQ.L #0x0,D6                         | D6 = computed PEOF accumulator
        MOVE.L  vcbAlBlkSiz(A2),D2              | D2 = alloc-block size in bytes
        MOVE    (A3),D3                         | A0 -> current queue element
        BEQ.B   HFSE_NO_5                       | zero start block -> empty fork
HFSE_OK_4_CONT_4:
        BSR.W   LG2PHYS_NEXT_2                  | walk MFS extent map for D3
        MOVE    D5,D3                           | follow qLink to next element
        BEQ.B   HFSE_NO_5                       | end of map -> done
        ADD.L   D2,D6                           | PEOF += alloc block size
        CMPI    #0x1,D3                         | end-of-map sentinel (1)?
        BNE.B   HFSE_OK_4_CONT_4                | more blocks -> continue
| MFS FClose: update directory entry from FCB
HFSE_NO_5:
        MOVE    (A3)+,D3                        | get start block from FCB area
        MOVE.L  (A3)+,D4                        | get LEOF from FCB
        MOVE.L  (A3)+,D5                        | get old PEOF from directory
        CMP.L   D5,D6                           | PEOF unchanged?
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
| Eject -- _Eject ($A017). Plus file_mgr.s 867.
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
| UnmountVol -- _UnmountVol ($A00E). Plus file_mgr.s 973.
| Pascal: function UnmountVol(volName: StringPtr; vRefNum: INTEGER): OSErr;
| Closes all open files on a volume and disposes its VCB. Sets
| FlushOnly := false (close mode), then falls into the common
| flush/close path shared with FlushVol (EJECT_NO_3_CONT below).
UnmountVol:
        BSR.W   FSQUEUE_CLR_OFFLINE             | FSQueue: wait our turn
        CLR.B   (FlushOnly).w                   | close, not just flush
        BRA.B   EJECT_NO_3_CONT                 | -> common flush/close path

| ----------------------------------------------------------
| FlushVol -- _FlushVol ($A013). Plus file_mgr.s 1016.
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
| GetVCBRFN -- find VCB by drive refnum in D0.
| Searches the VCB queue for a volume whose vcbDRefNum (offset
| $4E = 78) matches D0. Returns A2 -> VCB if found (Z=1), or
| nsvErr (-35) if not. Plus equivalent: fs_queue.s 463.
| (FDisasm previously misnamed this LocalToGlobal -- it has nothing
| to do with QD coordinate conversion. Renamed for correctness.)
| Called during boot.
GetVCBRFN:
        MOVEM.L D1/A0,-(SP)                     | save regs
        MOVEQ.L #0x4E,D1                        | offset of vcbDRefNum (78)
        BRA.B   GETVCBRFN_SCAN                  | -> shared queue search
| ----------------------------------------------------------
| FindVCBDrv -- find VCB by drive number in D0.
| vcbDrvNum (offset $48 = 72) match. Plus equivalent: fs_queue.s 489.
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
| SetVol -- _SetVol ($A015). Plus file_mgr.s 1673.
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
| GetVol -- _GetVol ($A014). Plus file_mgr.s 1623.
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
| GetVolInfo -- _GetVolInfo ($A007). Plus file_mgr.s 1354.
| Pascal: function GetVolInfo(VAR ioParam: HParamBlockRec): OSErr;
| Returns information about a volume -- selected by index (D2>0),
| by VRefNum (D2=0), or by name (D2<0). Body byte-equivalent
| to Plus through the dispatch trampoline; classic uses
| GETFILEINFO_LOOP_3_* labels (FDisasm-chained off the volume
| name-copy loop above, unrelated) where Plus uses GETVOLINFO_*.
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

| ----------------------------------------------------------
| OpenRF -- _OpenRF ($A00A). Plus file_mgr.s 2460.
| Pascal: function OpenRF(fileName: Str255; vRefNum: INTEGER;
| VAR refNum: INTEGER): OSErr;
| Opens the resource fork of a file. Differs from FileOpen only
| in that it clears (RegRsrc).w (= 0 = resource fork) instead of
| setting it to -1 (= data fork), then jumps to the common open
| path at FILEOPEN_CONT.
OpenRF:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: queue up the call
        CLR.B   (RegRsrc).w                     | resource fork (false = rsrc)
        BRA.B   FILEOPEN_CONT                   | -> common open path

| ----------------------------------------------------------
| FileOpen -- _Open ($A000) for file paths. Plus file_mgr_io.s 41.
| Device Manager's Open ($A000) handler in device_mgr.s
| forwards here (JMP FileOpen(PC) at device_mgr.s:259) when
| the requested name doesn't match an installed driver -- i.e.
| for opening a regular file's data fork.
FileOpen:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: queue up the call
        ST      (RegRsrc).w                     | data fork (true = regular)
| FILEOPEN_CONT -- common open path (also reached from OpenRF above).
| Walks the FCB table looking for a free slot, then dispatches to
| the directory search to locate the named file.
FILEOPEN_CONT:
        BSR.B   SETVOLINFO_HFS_CONT_3_CONT      | Gt1stFCB: get first FCB entry
FILEOPEN_CONT_2:
        TST.L   fcbFlNm(A1,D1.W)                | FCB slot in use?
        BEQ.B   FILEOPEN_CONT_2_CONT_3          | free slot found ->
        BSR.B   HFSE_NEXT                       | advance to next FCB slot
        BCS.B   FILEOPEN_CONT_2                 | more slots to scan ->
        MOVEQ.L #-0x2A,D0                       | D0 = -42 = tmfoErr
FILEOPEN_CONT_2_CONT:
        CLR     24(A0)                          | ioRefNum = 0 (open failed)
FILEOPEN_CONT_2_CONT_2:
        BRA.W   FSQUEUE_DONE                    | finish via CmdDone
FILEOPEN_CONT_2_CONT_3:
        MOVE    D1,24(A0)                       | ioRefNum = FCB index (D1)
        ADD.L   A1,D1                           | D1 = absolute FCB ptr
        BSR.W   FndFilName                      | search MFS dir for fileName
        BNE.B   FILEOPEN_CONT_2_CONT            | not found -> err
        MOVEA.L  D1,A3                          | A3 = FCB to populate
        MOVE    -2(A1),D7                       | D7 = MDB block #+dirty bits
        BCLR    #0xF,D7                         | clear dirty bit (block #)
        MOVE    (A5),D3                         | D3 = file flags from dir
        ANDI.W   #0x1FF,D3                      | mask to flag bits
        MOVE.L  28(A0),D0                       | D0 = caller's ioMisc (clump)
        MOVE.L  D0,A4                           | A4 = ioMisc ptr (or 0)
        BEQ.B   FILEOPEN_CONT_2_CONT_4          | ok ->
        ADDQ.L   #0x8,A4                        | skip past ioFCBLEnd header
        CLR.W    (A4)+                          | clear ioFCBVers field
FILEOPEN_CONT_2_CONT_4:
        LEA.L     18(A5),A5                     | A5 = past dir header info
        MOVE.L  (A5)+,D2                        | D2 = file ID (CNID)
        MOVE    (A5)+,D4                        | D4 = data fork start block
        MOVE.L  (A5)+,D5                        | D5 = data fork LEOF
        MOVE.L  (A5)+,D6                        | D6 = data fork PEOF
        TST.B   (RegRsrc).w                     | regular (data) fork mode?
        BNE.B   FILEOPEN_CONT_2_CONT_5          | yes -> use data-fork values
        BSET    #0x9,D3                         | set fcb_FlgRsrcOpen flag
        MOVE    (A5)+,D4                        | D4 = rsrc fork start block
        MOVE.L  (A5)+,D5                        | D5 = rsrc fork LEOF
        MOVE.L  (A5)+,D6                        | D6 = rsrc fork PEOF
FILEOPEN_CONT_2_CONT_5:
        CMPI.B  #0x1,27(A0)                     | permission == fsRdPerm?
        BNE.B   FILEOPEN_CONT_2_NO              | no -> check write/excl
        BCLR    #0x8,D3                         | clear write-bit (read-only)
        BRA.B   FILEOPEN_CONT_2_CONT_8          | install FCB and exit
FILEOPEN_CONT_2_NO:
        MOVEQ.L #-0x36,D0                       | D0 = -54 = permErr
        BCHG    #0x8,D3                         | D3 ^= 1<<0x8
        BNE.B   FILEOPEN_CONT_2_CONT            | locked -> permErr
        BSR.W   HFSE_NEXT_CONT                  | search FCBs by file ID
        BNE.B   FILEOPEN_CONT_2_CONT_8          | no other open -> install
FILEOPEN_CONT_2_CONT_6:
        MOVE    fcbFlags(A1,D1.W),D0            | D0 = existing FCB flags
        EOR     D3,D0                           | XOR new vs existing flags
        ANDI    #0x300,D0                       | isolate write-related bits
        BNE.B   FILEOPEN_CONT_2_CONT_7          | share conflict -> next FCB
        MOVE    D1,24(A0)                       | return existing ioRefNum
        MOVEQ.L #-0x31,D0                       | D0 = -49 = opWrErr
        BRA.B   FILEOPEN_CONT_2_CONT_2          | finish with opWrErr
FILEOPEN_CONT_2_CONT_7:
        BSR.W   HFSE_ERR_9                      | find next FCB for same ID
        BEQ.B   FILEOPEN_CONT_2_CONT_6          | another match -> recheck
FILEOPEN_CONT_2_CONT_8:
        MOVE.L  D2,(A3)+                        | fcbFlNm = file ID
        MOVE    D3,(A3)+                        | fcbFlags = flags
        MOVE    D4,(A3)+                        | fcbStBlk = start block
        MOVE.L  D5,(A3)+                        | fcbEOF = LEOF
        MOVE.L  D6,(A3)+                        | fcbPLen = PEOF
        CLR.L   (A3)+                           | fcbCrPs = 0 (mark at 0)
        MOVE.L  A2,(A3)+                        | fcbVPtr = VCB ptr
        MOVE.L  A4,(A3)+                        | fcbBfAdr = ioMisc/clump ptr
        MOVE    D7,(A3)                         | fcbDirBlk = dir block #
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.B   CREATE_ERR_2                    | finish via CmdDone
