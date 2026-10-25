| File Manager -- trap dispatch, file system queue, disk-switch hook
|
| Apple source: TFS.a, the head of the TurboFS module (MacSEROM.lst module
| TURBOFS): _FSDispatch ($A060, the HFS selector dispatcher with
| HFS_DISPATCH_TABLE), the file system queue (FSQUEUE_*: every File
| Manager call is queued and run one at a time; completion in
| FSQUEUE_DONE, with retries on another drive), _FInitQueue ($A016) and
| DSHook, the disk-switch handler behind the "please insert disk" alert.
| The calls themselves follow in file_mgr_vol.s, file_mgr_dir.s and
| file_mgr_io.s.
|
| FS I/O parameter block (queue linkage like any queue element):
| +6 ioTrap word trap word that invoked this call
| +8 ioCmdAddr long address of routine to execute
| +16 ioResult word result code (>0 = pending, 0 = done, <0 = error)
|
| References:
| Inside Macintosh Vol II, Ch 4: The File Manager
| Inside Macintosh Vol IV, Ch 19: The File Manager (HFS)

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
| FS queue completion - called after an FS call finishes
| Checks for disk-switch errors and retries with alternate volumes.
| Called by: FSDISPATCH_BAD_SEL, HFS_MOUNTVOL, HFSC_OK, FILEOPEN_FOUND_2, FILEFILETFSETCATINFO_HFS_ERR_2 (and 2 more)
FSQUEUE_DONE:
        CLR.B   (SysCRefCnt).w                  | clear system call ref count
        EXT.L   D0                              | sign-extend FS result to long
        BLE.B   FSQUEUE_STORE_ERR               | negative or zero = real error, skip
        MOVE    D0,(HFSDSErr).w                 | stash positive result as HFS disk-switch err
        MOVEQ.L #-0x7F,D0                       | replace with generic disk-switch error (-127)
FSQUEUE_STORE_ERR:
        MOVE.L  (FSQHdr_Head).w,A0              | get first element in FS queue
        CMPI    #0x5,0x4(A0)                    | qType = fsQType (5)?
        BNE.B   NOPKG_SYSERROR                  | not an FS queue element -> fatal error
        CMPI    #-0x2B,D0                       | error = nsDrvErr (-43, no such drive)?
        BNE.B   FSQUEUE_CLR_OFFLINE             | different error -> skip disk-switch retry
        BTST    #0x9,0x6(A0)                    | HFS bit set in ioTrap word?
        BEQ.B   FSQUEUE_TRY_SWITCH              | MFS call -> try disk-switch
        TST.L   0x30(A0)                        | ioNamePtr set? (HFS uses named volumes)
        BNE.B   FSQUEUE_CLR_OFFLINE             | has name -> can't retry by drive scan
FSQUEUE_TRY_SWITCH:
        BTst    #0x6,(HFSFlags).w               | disk-switch already in progress?
        BNE.B   FSQUEUE_CLR_OFFLINE             | yes -> don't recurse into switch handler
        BTST    #0x5,(HFSFlags).w               | volume offline handling in progress?
        BNE.B   FSQUEUE_CLR_OFFLINE             | yes -> skip disk-switch
        MOVE.L  (PMSPPtr).w,A1                  | ptr to physical-media-scan-position table
        MOVEM.L D1/A2,-(SP)                     | save regs for drive scan loop
        MOVE    -0x2(A1),D1                     | current scan index in PMSP table
FSQUEUE_SCAN_NEXT:
        ADDQ.W  #0x6,D1                         | advance to next PMSP entry (6 bytes each)
        CMP     (A1),D1                         | past end of PMSP table?
        BGE.B   FSQUEUE_SCAN_END                | yes -> done scanning drives
        MOVE    0x0(A1,D1.W),D0                 | get drive number from PMSP entry
        BEQ.B   FSQUEUE_SCAN_END                | zero = empty entry, stop scan
        BSR     GetVCBRFN                       | find VCB for this drive number
        BNE.B   FSQUEUE_SCAN_END                | no VCB -> stop scan
        MOVE    0x48(A2),D0                     | vcbDrvNum: drive currently mounted?
        BLE.B   FSQUEUE_SCAN_NEXT               | not mounted -> try next drive
FSQUEUE_SCAN_END:
        MOVE    D1,-0x2(A1)                     | save updated scan position
        MOVE    D1,D0                           | copy index for comparison
        MOVEM.L (SP)+,D1/A2                     | restore saved regs
        CMP     (A1),D0                         | scanned past end of table?
        BGE.B   FSQUEUE_NO_DRIVE                | yes -> no suitable drive found
        TST     0x0(A1,D0.W)                    | drive entry valid?
        BEQ.B   FSQUEUE_NO_DRIVE                | zero = no drive -> invoke disk-switch dialog
        MOVEQ.L #0x0,D0                         | clear D0 high bytes
        MOVE.B  0x7(A0),D0                      | get ioTrap number from queue element
        MOVE.L  0x8(A0),A1                      | get ioCompletion routine address
        JMP     (A1)                            | re-dispatch the FS call to retry on new drive

| ----------------------------------------------------------
|
| FSQUEUE_NO_DRIVE - no alternate drive found, report nsDrvErr
|
FSQUEUE_NO_DRIVE:
        MOVEQ.L #-0x2B,D0                       | return nsDrvErr (-43) to caller
FSQUEUE_CLR_OFFLINE:
        BClr    #0x5,(HFSFlags).w               | clear "volume offline" flag
        MOVE.L  (ExtFSHook).w,D2                | external FS hook installed?
        BLE.B   FSQUEUE_CHK_EXTFS               | no hook -> skip
        MOVE.L  D2,A1                           | load hook address
        JSR     (A1)                            | call external FS hook (may modify D0)
FSQUEUE_CHK_EXTFS:
        CMPI    #-0x3A,D0                       | error = volNotFound (-58)?
        BNE.B   FSQUEUE_DEQUEUE                 | no -> proceed to dequeue
        MOVE.L  (ToExtFS).w,D2                  | external FS dispatch vector?
        BLE.B   FSQUEUE_DEQUEUE                 | not installed -> skip
        MOVE.L  D2,A1                           | load ext FS dispatcher address
        MOVE.L  (FSQHdr_Head).w,A0              | re-fetch FS queue head
        CMPI    #0x5,0x4(A0)                    | still an FS queue element?
        BNE     NOPKG_SYSERROR                  | corrupted queue -> fatal error
        TST     0x6(A0)                         | ioTrap word: already dispatched?
        BLT.B   FSQUEUE_CALL_EXTFS              | negative = already marked -> just dispatch
        MOVEQ.L #0x0,D0                         | clear D0 for trap number extraction
        MOVE.B  0x7(A0),D0                      | save original trap number from ioTrap
        CLR.B   0x7(A0)                         | clear trap number byte in queue element
        ORI     #-0x5FA0,0x6(A0)                | set HFS+async flags in ioTrap (0xA060)
FSQUEUE_CALL_EXTFS:
        JSR     (A1)                            | dispatch call to external file system
FSQUEUE_DEQUEUE:
        MOVE    SR,-(SP)                        | save SR for atomic queue manipulation
        ORI     #0x300,SR                       | disable interrupts (IPL=3)
        CLR     (FSQHdr_Flags).w                | clear FS queue busy flag
        MOVE.L  (FSQHdr_Head).w,A0              | get completed queue element
        CMPI    #0x5,0x4(A0)                    | validate qType = fsQType
        BNE     NOPKG_SYSERROR                  | not FS type -> fatal error
        MOVE.L  (A0),(FSQHdr_Head).w            | dequeue: advance head to next element
        BNE.B   FSQUEUE_RESTORED_SR             | queue not empty -> skip tail clear
        CLR.L   (FSQHdr_Tail).w                 | queue empty: clear tail pointer too
FSQUEUE_RESTORED_SR:
        MOVE    (SP)+,SR                        | restore interrupts
        MOVE    D0,0x10(A0)                     | store result code in ioResult field
        MOVE.L  0xC(A0),D1                      | get ioCompletion routine address
        BEQ.B   FSQUEUE_CHK_MORE                | no completion routine -> skip callback
        MOVE.L  D1,A1                           | load completion address
        TST     D0                              | set condition codes from result
        JSR     (A1)                            | call ioCompletion(A0=PB, D0=result)
FSQUEUE_CHK_MORE:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts
        TST.L   (FSQHdr_Head).w                 | more requests in FS queue?
        BNE     FSQUEUE_TRY_LOCK                | yes -> process next queued FS call
        MOVE    (SP)+,SR                        | restore interrupts
        RTS                                     | all FS requests complete, return

| ----------------------------------------------------------
|
| _FInitQueue ($A016) - reset FS queue to single-element state
|
| Clears the FS queue so only the currently executing request remains.
| Called during system initialization to reset file system state.
InitQueue:
        MOVE    SR,-(SP)                        | save SR for atomic operation
        ORI     #0x300,SR                       | disable interrupts (IPL=3)
        MOVE.L  (FSQHdr_Head).w,D0              | get current queue head
        BEQ.B   FINITQ_DONE                     | queue empty -> nothing to truncate
        MOVE.L  D0,A0                           | dereference head element
        CLR.L   (A0)                            | clear qLink: make this the only element
        MOVE.L  A0,(FSQHdr_Tail).w              | tail = head: single-element queue
FINITQ_DONE:
        MOVEQ.L #0x0,D0                         | return noErr
        MOVE    (SP)+,SR                        | restore interrupts
        RTS                                     | return from queue operation

| ----------------------------------------------------------
|
| DSHook - disk-switch hook, handles "please insert disk" dialog
|
| Called when a volume is needed but not mounted. Saves state, shows
| the disk-switch alert (dsErrCode=30), and polls for disk-insert events
| until the correct disk is inserted or the user cancels.
| A0 = FS queue element (IOParam) for the failed call.
DSHook:
        MOVEM.L D0-D7/A0-A3/A6,-(SP)            | save all working regs
        LEA.L   (TrapAgain).w,A1                | use TrapAgain as scratch for trap re-execution
        MOVE    0x6(A0),(A1)+                   | copy ioTrap word for later re-dispatch
        MOVE    #0x4E75,(A1)                    | write RTS opcode after trap word
        BSR     MakeStkPB                       | build zeroed 64-byte param block on stack
        MOVE.L  A0,D7                           | save param block ptr in D7
        MOVE.L  (ReqstVol).w,A2                 | VCB of the volume we need
        MOVE    0x4A(A2),D3                     | vcbDRefNum: driver refnum (neg = ejected)
        BPL.B   DSHOOK_SHOW_DLG                 | positive = drive still present, show dialog
        NEG     D3                              | negate to get actual drive number
        MOVE    D3,0x16(A0)                     | store drive number in ioVRefNum of param block
        _MountVol                               | try to mount the volume
        BNE.B   DSHOOK_SHOW_DLG                 | mount failed -> show disk-switch dialog
        MOVEQ.L #0x0,D3                         | mount succeeded, D3=0 signals success
        BRA     DSHOOK_CLEANUP                  | skip dialog, go to cleanup

| ----------------------------------------------------------
|
| DSHOOK_SHOW_DLG - set up and show the disk-switch dialog
|
| Sets up the alert rectangle, optionally creates a temporary QD port
| to save/restore screen contents behind the dialog, then calls
| _SysError with dsErrCode=30 to display the "please insert" alert.
DSHOOK_SHOW_DLG:
        MOVE.L  #0x500078,(DSAlertRect).w       | alert rect top=5, left=120

        MOVE.L  #0x980195,(DSAlertRect_botRight).w | alert rect bottom=152, right=405

        MOVEQ.L #0x0,D4                         | D4 = saved QD globals ptr (0 if none)
        MOVEQ.L #0x0,D5                         | D5 = saved stack ptr (0 if no temp port)
        TST.B   (QDExist).w                     | is QuickDraw initialized?
        BNE.B   DSHOOK_SYSERROR                 | no QD -> skip screen save, just show alert
        MOVE.L  (A5),A0                         | get QD globals base ptr (CurrentA5^)
        MOVE.L  (A0),D4                         | save current GrafPort ptr to restore later
        MOVE.L  A7,D0                           | current stack position
        SUBI.L  #0x12BE,D0                      | need 4798 bytes for temp port + regions
        MOVE.L  (ApplZone).w,A0                 | start of application heap
        CMP.L   (A0),D0                         | enough room between stack and heap?
        BLE.B   DSHOOK_SYSERROR                 | no room -> skip temp port creation
        MOVE.L  A7,D5                           | save original SP for later restore
        ADDI.L  #0x800,D0                       | leave 2K safety margin above heap
        MOVE.L  D0,SP                           | carve out stack space for temp port
        MOVE.L  D0,D6                           | D6 = base of temp GrafPort structure
        MOVE.L  A7,A0                           | A0 -> temp port storage
        PEA.L   0xE(A0)                         | push portBits.baseAddr (offset 14)
        MOVE.L  (SP)+,(A0)+                     | store self-referencing portBits ptr
        MOVE    #0x24,(A0)+                     | portBits.rowBytes = 36 (288 pixels / 8)
        CLR.L   (A0)+                           | portBits.bounds.topLeft = (0,0)
        MOVE.L  #0x48011D,(A0)+                 | portBits.bounds.botRight = (72,285)
        SUBA    #0x74,SP                        | allocate 116 bytes for fake regions
        MOVE.L  A7,A6                           | A6 = saved QD globals for temp port
        JSR     AllocFakeRgns(PC)               | set up minimal visRgn/clipRgn
        MOVE.L  A7,-(SP)                        | push ptr to temp port
        _InitPort                               | initialize the temporary GrafPort
        MOVE.L  (A5),A0                         | QD globals base
        MOVE.L  A6,(A0)                         | install temp port as current
        PEA.L   -0x7A(A0)                       | push srcBits (screen bitmap, at globals-122)
        MOVE.L  D6,-(SP)                        | push dstBits (temp port bitmap)
        PEA.L   (DSAlertRect).w                 | push srcRect (alert rectangle)
        MOVE.L  D6,A0                           | temp port base
        PEA.L   0x6(A0)                         | push dstRect (temp port bounds)
        CLR     -(SP)                           | transfer mode = srcCopy
        CLR.L   -(SP)                           | no mask region
        _CopyBits                               | save screen area behind dialog to temp port
DSHOOK_SYSERROR:
        MOVEQ.L #0x1E,D0                        | dsErrCode 30 = disk-switch request
        _SysError                               | show "please insert disk" alert
        MOVE.L  (DrvQHdr_Head).w,D0             | scan drive queue for the target drive
DSHOOK_SCAN_DRV:
        BEQ.B   DSHOOK_EVT_LOOP                 | no more drives -> go to event loop
        MOVE.L  D0,A1                           | A1 -> drive queue element
        CMP     0x6(A1),D3                      | dQDrive matches target drive number?
        BEQ.B   DSHOOK_FOUND_DRV                | found it -> check if ejectable
        MOVE.L  (A1),D0                         | follow qLink to next drive
        BRA.B   DSHOOK_SCAN_DRV                 | continue scanning

| ----------------------------------------------------------
|
| DSHOOK_FOUND_DRV - found drive in queue, eject if it's a floppy (type 1 or 2)
|
DSHOOK_FOUND_DRV:
        MOVE.B  -0x3(A1),D0                     | get drive type from DQE flags byte
        CMPI.B  #0x1,D0                         | type 1 = single-sided floppy?
        BEQ.B   DSHOOK_EJECT_DRV                | yes -> eject it
        CMPI.B  #0x2,D0                         | type 2 = double-sided floppy?
        BNE.B   DSHOOK_EVT_LOOP                 | not floppy -> can't eject, go to event loop
DSHOOK_EJECT_DRV:
        MOVE    D3,D1                           | D1 = drive number to eject
DSHOOK_DO_EJECT:
        MOVEQ.L #0x2,D2                         | eject reason code 2 = disk-switch
        BSR     vDoEject                        | eject the disk from this drive
DSHOOK_EVT_LOOP:
        SUBA    #0x10,SP                        | allocate 16-byte event record on stack
DSHOOK_POLL_EVT:
        MOVE    #0x88,D0                        | event mask: disk-insert (7) + key-down (3)
        MOVE.L  A7,A0                           | A0 -> event record buffer
        _GetOSEvent                             | poll for disk-insert or key events
        BNE.B   DSHOOK_POLL_EVT                 | no event yet -> keep polling
        MOVE.L  0x2(SP),D0                      | evtMessage: inserted drive# or key code
        MOVE    (SP),D3                         | evtNum: event type
        MOVE    0xE(SP),D1                      | evtMeta+evtMBut: modifier keys
        ADDA    #0x10,SP                        | free event record from stack
        SUBQ.W  #0x7,D3                         | diskInsertEvt (7)?
        BEQ.B   DSHOOK_DISK_INSERT              | yes -> try to mount the inserted disk
        CMPI.B  #0x2E,D0                        | key code 0x2E = period key?
        BEQ.B   DSHOOK_CHK_CMDPER               | yes -> check for Cmd-. cancel
        CMPI.B  #0x2,D0                         | mouse button up (2) or down (1)?
        BHI.B   DSHOOK_EVT_LOOP                 | higher key code -> ignore, loop
        TST.B   D0                              | null event?
        BEQ.B   DSHOOK_EVT_LOOP                 | yes -> loop
        MOVEQ.L #0xB,D2                         | mask for option+cmd bits (bits 3,1,0)
        LSR     #0x8,D1                         | shift modifiers to low byte
        AND.B   D1,D2                           | isolate option+cmd bits
        SUBQ.B  #0x3,D2                         | Cmd+Option held? (bits 0+1 = 3)
        BNE.B   DSHOOK_EVT_LOOP                 | no -> ignore click, keep polling
        MOVEQ.L #0x1,D2                         | eject reason 1 = user-requested
        MOVE.B  D0,D1                           | D1 = drive number from event
        BSR     vDoEject                        | eject disk per Cmd-Option-click
        BRA.B   DSHOOK_EVT_LOOP                 | back to event loop

| ----------------------------------------------------------
|
| DSHOOK_CHK_CMDPER - check for Cmd-. (cancel disk-switch)
|
DSHOOK_CHK_CMDPER:
        BTst    #0x8,D1                         | Cmd key held? (modifier bit 8)
        BEQ.B   DSHOOK_EVT_LOOP                 | no Cmd -> not a cancel, keep polling
        BRA.B   DSHOOK_DISMISS                  | Cmd-. pressed -> cancel disk switch

| ----------------------------------------------------------
|
| DSHOOK_DISK_INSERT - disk inserted, try to mount it
|
DSHOOK_DISK_INSERT:
        MOVE.L  D7,A0                           | A0 -> stack param block
        MOVE    D0,0x16(A0)                     | store inserted drive number in ioVRefNum
        MOVE    D0,D1                           | D1 = drive number for eject on failure
        _MountVol                               | attempt to mount the newly inserted disk
        BEQ.B   DSHOOK_DISMISS                  | mount succeeded -> dismiss dialog
        CMPI    #-0x6C,D0                       | error = volOnLinErr (-108, wrong volume)?
        BNE.B   DSHOOK_DO_EJECT                 | different error -> eject and retry
        MOVEQ.L #-0x1,D3                        | mark D3=-1: cancel (wrong vol, no eject)
DSHOOK_DISMISS:
        TST.L   D5                              | did we create a temp port? (D5=saved SP)
        BEQ.B   DSHOOK_NO_PORT                  | no temp port -> just flag window update
        MOVE.L  D6,-(SP)                        | push srcBits (temp port with saved screen)
        MOVE.L  (A5),A0                         | QD globals base
        MOVE.L  A6,(A0)                         | reinstall temp port as current
        PEA.L   -0x7A(A0)                       | push dstBits (screen bitmap)
        MOVE.L  D6,A0                           | temp port base
        PEA.L   0x6(A0)                         | push srcRect (temp port bounds)
        PEA.L   (DSAlertRect).w                 | push dstRect (alert area on screen)
        CLR     -(SP)                           | transfer mode = srcCopy
        CLR.L   -(SP)                           | no mask region
        _CopyBits                               | restore screen contents behind dialog
        MOVE.L  D5,SP                           | restore original SP (free temp port)
        BRA.B   DSHOOK_SETPORT                  | go restore original GrafPort

| ----------------------------------------------------------
|
| DSHOOK_NO_PORT - no temp port: flag windows need updating
|
DSHOOK_NO_PORT:
        CLR.B   (DSWndUpdate).w                 | set flag so Window Mgr repaints all windows
        TST.L   D4                              | was there a saved GrafPort?
        BEQ.B   DSHOOK_CLEANUP                  | no -> skip SetPort
DSHOOK_SETPORT:
        MOVE.L  D4,-(SP)                        | push saved GrafPort ptr
        _SetPort                                | restore original drawing port
DSHOOK_CLEANUP:
        BSet    #0x7,(DSAlertRect).w            | set high bit to mark dialog dismissed
        ADDA    #0x40,SP                        | free 64-byte stack param block
        TST     D3                              | D3: 0=success, nonzero=canceled/error
        MOVEM.L (SP)+,D0-D7/A0-A3/A6            | restore all saved registers
        BEQ.B   DSHOOK_RETRY_TRAP               | D3=0: mount succeeded -> retry FS call
        MOVEQ.L #-0x35,D0                       | return nsDrvErr (-53) to caller
        RTS                                     | return with error

| ----------------------------------------------------------
|
| DSHOOK_RETRY_TRAP - disk-switch succeeded, re-execute the original FS call
|
| The ioTrap word was saved in TrapAgain earlier. We jump to it
| to re-execute the trap that originally caused the disk-switch.
DSHOOK_RETRY_TRAP:
        MOVE    0x6(A0),D0                      | get ioTrap word from queue element
        BGT.B   DSHOOK_FIX_ALINE                | positive = OS trap -> needs A-line fixup
        JMP     (TrapAgain).w                   | negative = already A-line, re-execute directly

| ----------------------------------------------------------
|
| DSHOOK_FIX_ALINE - convert trap number to A-line instruction and re-execute
|
DSHOOK_FIX_ALINE:
        ORI.B   #0xA0,(TrapAgain).w             | set A-line opcode high byte (0xA0xx)
        MOVE.B  #0x60,(TrapAgain_1).w           | set async bit (0x60) in trap word
        ANDI    #0xFF,D0                        | mask to low byte (trap number only)
        JMP     (TrapAgain).w                   | execute the reconstructed A-line trap

