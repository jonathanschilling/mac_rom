| File System Queue Completion and Disk-Switch Handler
|
| Processes file system I/O queue completion, handles disk-switch
| errors (dsNoDiskErr=-43), dispatches to external FS hooks, and
| manages disk insertion events for the "please insert disk" dialog.
| Also contains file system utility routines: VCB lookup, MDB flush,
| allocation rounding, and stack-based parameter block construction.
|
| References:
| Inside Macintosh Vol II, Ch 4: File Manager
| Inside Macintosh Vol IV, Ch 31: HFS

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
FInitQueue:
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

