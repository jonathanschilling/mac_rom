| Operating System Event Manager + File Manager dispatch
|
| GetOSEvent ($A031): dequeue highest-priority event matching mask in D0
| FlushEvents ($A032): remove all events matching mask; stop at stopMask
| FSDispatch ($A060): HFS trap dispatcher - routes selector in D0 to
| one of 18 HFS routines via HFS_DISPATCH_TABLE jump table
|
| Event queue entries (EvQEl, 22 bytes):
| +0 qLink pointer next queue element
| +4 qType word queue element type (evType = 4)
| +6 evtQWhat word event code (1=mouseDown..8=activateEvt)
| +8 evtQMessage long event-specific message
| +12 evtQWhen long Ticks at time of event
| +16 evtQWhere long mouse position (Point: v,h)
| +20 evtQMeta byte modifier key state
| +21 evtQMBut byte mouse button state
|
| FS I/O parameter block (reuses EvQEl offsets for queue linkage):
| +6 ioTrap word trap word that invoked this call
| +8 ioCmdAddr long address of routine to execute
| +16 ioResult word result code (>0 = pending, 0 = done, <0 = error)
|
| References:
| Inside Macintosh Vol II, Ch 3: OS Event Manager (pp 65-76)
| Inside Macintosh Vol II, Ch 4: File Manager (pp 77-142)

| ----------------------------------------------------------
|
| _GetOSEvent ($A031)
|
| Dequeues the highest-priority event matching the mask in D0.
| Calls OSEventAvail to find a match, then removes it from the queue.
| On exit: D0 = 0 if event found (Z set), event record copied to (A0);
| D0 = event code if found, A1 = ptr to EvQEl entry.
| Called during boot (3,694 times in 30s trace).
GetOSEvent:
        BSR     OSEventAvail                    | find matching event; A1 = EvQEl ptr
        BNE.B   GETOSEVENT_DONE                 | no match found: return non-zero D0
        MOVE.L  A1,A0                           | A0 = EvQEl to dequeue
        LEA.L   (EventQueue).w,A1               | A1 = event queue header
        BSR.B   DEQUEUE_INVALIDATE              | dequeue entry and invalidate slot
        MOVEQ.L #0x0,D0                         | D0 = 0: event was found (sets Z)
GETOSEVENT_DONE:
        RTS                                     | return with D0 = 0 (found) or non-zero (not found)

| ----------------------------------------------------------
|
| DequeueAndInvalidate - remove EvQEl from queue, mark slot free
|
| A0 = EvQEl entry to remove, A1 = queue header (EventQueue).
| After Dequeue, sets evtQWhat to -1 to mark the slot as unused
| so PostEvent can reclaim it when the queue is full.
DEQUEUE_INVALIDATE:
        JSR     Dequeue(PC)                     | unlink A0 from queue at A1
        MOVE    #-0x1,evtQWhat(A0)              | mark slot free (evtQWhat = -1)
        RTS                                     | return with event unlinked and slot freed

| ----------------------------------------------------------
|
| _FlushEvents ($A032) - remove events matching a mask
|
| D0.W = eventMask (low word): bits for event types to flush
| D0.W = stopMask (high word, swapped into D1): if an event matches
| this mask, stop flushing and return it in D0/D2.
| FlEvtMask ($025E) filters which types the floppy driver cares about.
| Walks the event queue under IPL 1 (disable VBL interrupts).
| On exit: D0 = last matching event type if stopMask hit, else 0.
GetGDevice:
        MOVE    SR,-(SP)                        | save SR for interrupt restore
        MOVEM.L D3-D4,-(SP)                     | preserve D3-D4
        MOVEQ.L #-0x1,D1                        | D1 = $FFFFFFFF (all bits set)
        MOVE.L  D1,(LastSPExtra).w              | invalidate LastSPExtra cache
        MOVE.L  D0,D1                           | D1 = eventMask|stopMask
        SWAP    D1                              | D1 = stopMask (high word -> low)
        MOVE    D0,D4                           | D4 = eventMask
        AND     (DiskVars_FlEvtMask).w,D4       | D4 &= FlEvtMask (floppy event filter)
        LEA.L   (EventQueue).w,A1               | A1 = event queue header
        ORI     #0x100,SR                       | raise IPL to 1 (mask VBL interrupts)
        MOVE.L  0x2(A1),D3                      | D3 = qHead: first EvQEl in queue
        BEQ.B   FLUSH_QUEUE_EMPTY               | queue empty: no events to flush
FLUSH_WALK_LOOP:
        MOVE.L  D3,A0                           | A0 = current EvQEl entry
        MOVE.L  (A0),D3                         | D3 = qLink: advance to next entry
        MOVE    evtQWhat(A0),D2                 | D2 = event type of this entry
        BTST    D2,D1                           | does stopMask include this type?
        BNE.B   FLUSH_EXIT                      | yes: stop flushing, return this event
        BTST    D2,D4                           | does eventMask include this type?
        BEQ.B   FLUSH_NEXT_ENTRY                | no: skip this entry
        BSR.B   DEQUEUE_INVALIDATE              | yes: dequeue and invalidate this event
FLUSH_NEXT_ENTRY:
        TST.L   D3                              | more entries in queue?
        BNE.B   FLUSH_WALK_LOOP                 | yes: continue walking
FLUSH_QUEUE_EMPTY:
        MOVEQ.L #0x0,D2                         | no match found: D2 = 0 (nullEvt)
FLUSH_EXIT:
        MOVEM.L (SP)+,D3-D4                     | restore D3-D4
        MOVE    D2,D0                           | D0 = event type (or 0 if none)
        EXT.L   D0                              | sign-extend to long for caller
        MOVE    (SP)+,SR                        | restore SR (re-enable interrupts)
        RTS                                     | return with D0 = event type or 0

| ----------------------------------------------------------
|
| _FSDispatch ($A060) - HFS File Manager trap dispatcher
|
| D0.W = HFS selector (0-17). Validates range, then jumps
| through HFS_DISPATCH_TABLE relative offset table to the appropriate handler.
| Selectors: 0=MountVol, 1=OpenWD, 2=CloseWD, 3=CatMove,
| 4=DirCreate, 5=GetWDInfo, 6=GetFCBInfo, 7=GetCatInfo,
| 8=SetCatInfo, 9=SetVolInfo, 10=LockRng, 11=UnlockRng,
| 12=CreateFileIDRef, 13=DeleteFileIDRef, 14=ResolveFileIDRef,
| 15=ExchangeFiles, 16-17=reserved.
| On invalid selector: returns paramErr (-50) via FSQUEUE_DONE.
FSDispatch:
        TST     D0                              | selector < 0?
        BLT.B   FSDISPATCH_BAD_SEL              | yes: invalid selector
        CMPI    #0x11,D0                        | selector > 17?
        BLS.B   FSDISPATCH_VALID                | no: valid, dispatch it
FSDISPATCH_BAD_SEL:
        BSR.B   FSQUEUE_SETUP                   | set up param block for error return
        MOVEQ.L #-0x32,D0                       | D0 = paramErr (-50)
        BRA     FSQUEUE_DONE                    | jump to FS I/O completion

| ----------------------------------------------------------
|
| HFS dispatch - index into HFS_DISPATCH_TABLE and jump to handler
|
FSDISPATCH_VALID:
        MOVE    D0,D2                           | D2 = selector
        LEA.L   HFS_DISPATCH_TABLE(PC),A2       | A2 = base of offset table
        ADD     D2,D2                           | D2 *= 2 (word offsets)
        ADDA    0x0(A2,D2.W),A2                 | A2 += HFS_DISPATCH_TABLE[selector] (PC-relative)
        JMP     (A2)                            | jump to HFS handler routine

| ----------------------------------------------------------
|
| HFS_DISPATCH_TABLE - HFS dispatch relative offset table (18 word entries)
|
| Each word is a signed offset from the start of HFS_DISPATCH_TABLE to the
| corresponding HFS routine. Selector 0 -> HFS_MOUNTVOL (MountVol), etc.
HFS_DISPATCH_TABLE:
  .byte 0x00,0x24,0x13,0x00,0x13,0xAC
  .byte 0x12,0xA8,0x12,0xDC,0x1D,0xBE
  .byte 0x19,0x64,0x13,0xE6,0x2B,0x40
  .byte 0x22,0x5E,0x20,0x96,0x11,0x5C
  .byte 0x0F,0x84,0x14,0xEE,0x15,0x18
  .byte 0x14,0x92,0x2B,0xF4,0x2B,0xF4

| HFS selector 0: MountVol - stamp ioMisc with version string
HFS_MOUNTVOL:
        BSR.B   FSQUEUE_SETUP                   | set up param block (ioTrap, ioCmdAddr)
        MOVE.L  #0x312E3241,0x20(A0)            | ioMisc = "1.2A" (HFS version string)

        MOVEQ.L #0x0,D0                         | D0 = noErr
        BRA     FSQUEUE_DONE                    | jump to FS I/O completion

| ----------------------------------------------------------
|
| FSQUEUE_SETUP_SYNC - FS param block setup (clear async bit)
| FSQUEUE_SETUP - FS param block setup (preserve async bit)
|
| Prepares the I/O parameter block at A0 for FS queue submission.
| Sets ioResult=1 (pending), stores ioTrap from D1, pops return
| address into ioCmdAddr so the FS queue server knows which
| routine to call. For HFSDispatch ($60), extracts low nibble
| as the actual selector and stores HFS selector in high byte.
FSQUEUE_SETUP_SYNC:
        BCLR    #0xA,D1                         | clear async bit (force synchronous)
| FSQUEUE_SETUP -- fSQueue: wait our turn.
| Called by: FSDISPATCH_BAD_SEL, HFS_MOUNTVOL, FlushVol, hfsC, GetVolInfo (and 32 more)
FSQUEUE_SETUP:
        MOVE.L  (FSQueueHook).w,D2              | D2 = FSQueueHook callback
        BLE.B   FSQUEUE_NO_HOOK                 | no hook installed: skip
        MOVE.L  D2,A1                           | A1 = hook address
        JSR     (A1)                            | call FSQueueHook(A0=paramBlock)
FSQUEUE_NO_HOOK:
        MOVE    #0x1,evtQWhere(A0)              | ioResult = 1 (I/O pending)
        MOVE    D1,evtQWhat(A0)                 | ioTrap = trap word from D1
        CMPI.B  #0x60,D1                        | is this _HFSDispatch ($A060)?
        BNE.B   FSQUEUE_STORE_CMD               | no: skip selector extraction
        ANDI.B  #0xF,evtQWhat(A0)               | ioTrap low byte = selector nibble
        MOVE.B  D0,0x7(A0)                      | ioTrap high byte = HFS selector
FSQUEUE_STORE_CMD:
        MOVE.L  (SP)+,evtQMessage(A0)           | ioCmdAddr = return address (routine ptr)
        MOVE    #0x5,0x4(A0)                    | qType = ioQType (5 = FS queue entry)
        BTST    #0xA,D1                         | async bit set in trap word?
        BEQ.B   FSQUEUE_SYNC_PATH               | no: synchronous call
        TST.B   (FrcSync).w                     | force-sync override enabled?
        BEQ.B   FSQUEUE_ENQUEUE                 | no: enqueue for async execution
        BRA.B   FSQUEUE_SYNC_WAIT               | yes: fall through to sync wait loop

| ----------------------------------------------------------
|
| Synchronous FS call path - enqueue, wait for completion
|
FSQUEUE_SYNC_PATH:
        CLR.L   evtQWhen(A0)                    | ioCompletion = nil (no callback)
FSQUEUE_SYNC_WAIT:
        MOVE.L  A0,-(SP)                        | save param block ptr
        BSR.B   FSQUEUE_ENQUEUE                 | enqueue into FS queue and execute
        MOVE.L  (SP)+,A0                        | restore param block ptr
FSQUEUE_SPIN_WAIT:
        MOVE    evtQWhere(A0),D0                | D0 = ioResult
        BGT.B   FSQUEUE_SPIN_WAIT               | still positive (pending): spin-wait
        EXT.L   D0                              | sign-extend result code
        CMPI    #-0x35,D0                       | ioResult == nsvErr (-53, no such vol)?
        BNE.B   FSQUEUE_RETURN                  | no: return normally
        MOVE.L  (DskSwtchHook).w,-(SP)          | push DskSwtchHook address
        BGT.B   FSQUEUE_RETURN                  | hook is valid (>0): call it via RTS
        ADDQ.W  #0x4,SP                         | no hook: pop the address
        BTST    #0x7,(DSAlertRect).w            | system error dialog suppressed?
        BNE     DSHook                          | yes: jump to disk-switch handler
FSQUEUE_RETURN:
        RTS                                     | return to caller or jump to DskSwtchHook via stack

| ----------------------------------------------------------
|
| FSQUEUE_ENQUEUE - enqueue param block into FS queue and start server
|
| Adds the param block at A0 into the FS queue (FSQHdr).
| If the queue was idle (qFlags bit 0 clear), starts the
| FS queue server to process the request immediately.
| If busy (bit 0 set), returns - the server will pick it up.
FSQUEUE_ENQUEUE:
        LEA.L   (FSQHdr_Flags).w,A1             | A1 = FS queue header
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | raise IPL to 3 (mask all interrupts)
        JSR     Enqueue(PC)                     | add param block to FS queue
FSQUEUE_TRY_LOCK:
        BSet    #0x0,(FSQHdr_Flags).w           | test-and-set FS busy flag
        BEQ.B   FSQUEUE_SERVER                  | was clear: we own the queue, run server
        MOVEQ.L #0x0,D0                         | queue busy: another call is running
        MOVE    (SP)+,SR                        | restore SR
        RTS                                     | return to caller (request queued for later processing)

| ----------------------------------------------------------
|
| FS queue server - dequeue and execute pending FS calls
|
| Processes the head entry of the FS queue. Sets up the PMSP
| (Permission State Machine Pointer) and HFS stack, then calls
| the routine address stored in ioCmdAddr of the param block.
FSQUEUE_SERVER:
        MOVE    (SP)+,SR                        | restore SR (re-enable interrupts)
        MOVE.L  (FSQHdr_Head).w,A0              | A0 = head param block in FS queue
        MOVE.L  evtQMessage(A0),A1              | A1 = ioCmdAddr (routine to execute)
        MOVEM.L D3-D7/A2-A6,-(SP)               | save all registers for FS call
        MOVE.L  (PMSPPtr).w,A6                  | A6 = PMSP (permission bitmap ptr)
        CLR     -0x2(A6)                        | clear PMSP status word
        BTST    #0xA,evtQWhat(A0)               | async bit set in ioTrap?
        SNE.B   (NxtDB).w                       | NxtDB = $FF if async, $00 if sync
        MOVE.L  (HFSVars_HFSStkTop).w,A6        | A6 = top of HFS stack
        JSR     (A1)                            | call the FS routine
        MOVEM.L (SP)+,D3-D7/A2-A6               | restore registers
        RTS                                     | return to caller after executing FS routine

| ----------------------------------------------------------
|
| NOPKG_SYSERROR - fatal error: no packages loaded (dsNoPk = 27)
|
| Called when a required package (e.g., Standard File) is not
| available. Triggers a system error with ID 27 (dsNoPk).
NOPKG_SYSERROR:
        MOVEQ.L #0x1B,D0                        | D0 = dsNoPk (no package error)
        _SysError                               | trigger fatal system error and halt
