| File Manager -- trap dispatch, file system queue, disk-switch hook
|
| Apple source: TFS.a, the head of the TurboFS module (MacSEROM.lst module
| TURBOFS): TFSDISPATCH (_FSDispatch $A060, the HFS selector
| dispatcher), the file system queue (FSQUEUE_*: every File Manager call
| is queued and run one at a time; the command-done path completes it,
| with retries on another drive), _FInitQueue ($A016) and DSHOOK, the
| disk-switch handler behind the "please insert disk" alert.
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

| ====================================================================
|
| TFSDISPATCH / _FSDispatch ($A060) -- HFS trap dispatcher
|
| D0 = HFS selector (0..17). Validates range, then jumps through
| HFS_DISPATCH_TABLE word-offset table to the appropriate hfs_<sel>
| handler. Out-of-range selector -> FSDISPATCH_BAD_SEL which
| returns paramErr (-50).
|
| Apple source module: TURBOFS
TFSDISPATCH:
    TST.W       D0                              | selector < 0 ?
    BLT.B       FSDISPATCH_BAD_SEL              | yes, invalid selector
    CMPI.W      #0x11,D0                        | selector > 17 ?
    BLS.B       FSDISPATCH_VALID                | no, valid, dispatch
FSDISPATCH_BAD_SEL:
    BSR.B       FSQUEUE_SETUP                   | set up param block for err return
    MOVEQ.L     #-0x32,D0                       | D0 = paramErr (-50)
    BRA.W       FSQUEUE_DONE                    | jump to FS I/O completion
| ----------------------------------------------------------
|
| HFS dispatch - index into HFS_DISPATCH_TABLE and jump to handler
|
FSDISPATCH_VALID:
    MOVE.W      D0,D2                           | D2 = selector
    LEA.L       HFS_DISPATCH_TABLE(PC),A2       | A2 = base of offset table
    ADD.W       D2,D2                           | * 2 (word stride)
    ADDA.W      0x0(A2,D2.W),A2                 | A2 += DTAB[selector]
    JMP         (A2)                            | jump to HFS handler
| HFS dispatch table: 18 word PC-relative offsets to handlers.
| sel 0=GetVolName, 1=OpenWD, 2=CloseWD, 3=CatMove, 4=DirCreate,
| sel 5=GetWDInfo, 6=GetFCBInfo, 7=GetCatInfo, 8=SetCatInfo,
| sel 9=SetVolInfo, 10=LockRng, 11=UnlockRng, 12=CreateFileIDRef,
| sel 13=DeleteFileIDRef, 14=ResolveFileIDRef, 15=ExchangeFiles,
| sel 16,17 reserved.
HFS_DISPATCH_TABLE:
    .long       0x0024134A                      | sel 0,1: GetVolName, OpenWD
    .long       0x13F612F2                      | sel 2,3: CloseWD, CatMove
    .long       0x13261E24                      | sel 4,5: DirCreate, GetWDInfo
    .long       0x19BC1430                      | sel 6,7: GetFCBInfo, GetCatInfo
    .long       0x2BB622C2                      | sel 8,9: SetCatInfo, SetVolInfo
    .long       0x20FA11A6                      | sel 10,11: LockRng, UnlockRng
    .long       0x0FD01546                      | sel 12,13: CreateFileIDRef, DelFileIDRef
    .long       0x157014DE                      | sel 14,15: ResolveFileIDRef, ExchangeFiles
    .long       0x2C6E2C6E                      | sel 16,17: reserved (both -> bad sel)
| ----------------------------------------------------------
|
| P_hfs0 -- HFS selector 0: GetVolName (placeholder)
|
| Stores ASCII "A2.1" into the version slot at 0x20(A0) of the
| param block and returns success. The "A2.1" version stamp is
| the SE FDHD HFS version identifier.
|
P_hfs0:
    BSR.B       FSQUEUE_SETUP                   | enqueue param block
    MOVE.L      #0x312E3241,0x20(A0)            | "A2.1" version stamp (LE: '1.2A')
    MOVEQ.L     #0x0,D0                         | D0 = noErr
    BRA.W       FSQUEUE_DONE                    | dispatch to completion
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
    BCLR        #0xA,D1                         | clear async bit (force synchronous)
| FSQUEUE_SETUP -- fSQueue: wait our turn.
| Called by: FSDISPATCH_BAD_SEL, P_hfs0, FLUSHVOL, P_hfsC, GETVOLINFO (and 32 more)
FSQUEUE_SETUP:
    MOVE.L      (FSQueueHook).W,D2              | D2 = FSQueueHook callback
    BLE.B       FSQUEUE_NO_HOOK                 | no hook installed: skip
    MOVEA.L     D2,A1                           | A1 = hook proc
    JSR         (A1)                            | call FSQueueHook(A0)
FSQUEUE_NO_HOOK:
    MOVE.W      #0x1,0x10(A0)                   | ioResult = 1 (pending)
    MOVE.W      D1,0x6(A0)                      | ioTrap = trap word from D1
    CMPI.B      #0x60,D1                        | trap == _HFSDispatch (0x60) ?
    BNE.B       FSQUEUE_STORE_CMD               | no, skip selector decode
    ANDI.B      #0xF,0x6(A0)                    | mask low nibble of ioTrap
    MOVE.B      D0,0x7(A0)                      | store HFS selector in high byte
FSQUEUE_STORE_CMD:
    MOVE.L      (A7)+,0x8(A0)                   | ioCmdAddr = pop return addr
    MOVE.W      #0x5,0x4(A0)                    | qType = 5 (fsType)
    BTST        #0xA,D1                         | async bit set ?
    BEQ.B       FSQUEUE_SYNC_PATH               | no, force sync path
    TST.B       (FrcSync).W                     | force-sync override active ?
    BEQ.B       FSQUEUE_ENQUEUE                 | no, async dispatch
    BRA.B       FSQUEUE_SYNC_WAIT               | yes, fall through to sync wait
| ----------------------------------------------------------
|
| Synchronous FS call path - enqueue, wait for completion
|
FSQUEUE_SYNC_PATH:
    CLR.L       0xC(A0)                         | ioCompletion = nil (sync mode)
FSQUEUE_SYNC_WAIT:
    MOVE.L      A0,-(A7)                        | save param block ptr
    BSR.B       FSQUEUE_ENQUEUE                 | enqueue + run server if idle
    MOVEA.L     (A7)+,A0                        | restore param block ptr
FSQUEUE_SPIN_WAIT:
    MOVE.W      0x10(A0),D0                     | D0 = ioResult
    BGT.B       FSQUEUE_SPIN_WAIT               | > 0 = pending, keep spinning
    EXT.L       D0                              | sign-extend to long
    CMPI.W      #0xFFCB,D0                      | result == nsDrvErr (-53) ?
    BNE.B       FSQUEUE_RETURN                  | no, return as-is
    MOVE.L      (DskSwtchHook).W,-(A7)          | push DskSwtchHook addr
    BGT.B       FSQUEUE_RETURN                  | hook installed -> caller will handle
    ADDQ.W      #0x4,A7                         | strip pushed hook
    BTST        #0x7,(DSAlertRect)              | DSAlert mode bit set ?
    BNE.W       DSHOOK                          | yes, post "please insert disk" dialog
FSQUEUE_RETURN:
    RTS                                         | return from FSQueue sync wait
| ----------------------------------------------------------
|
| FSQUEUE_ENQUEUE -- enqueue param block and run FS server if idle
|
| Adds the FS param block (A0) to the FS queue under IPL>=3,
| then atomically sets the FSQHdr_Flags lock bit. If we won the
| lock (server was idle), fall into FSQUEUE_SERVER. Otherwise,
| just return -- the running server will pick up our entry.
|
FSQUEUE_ENQUEUE:
    LEA.L       (FSQHdr_Flags).W,A1             | A1 -> FSQHdr_Flags
    MOVE.W      SR,-(A7)                        | save SR
    ORI.W       #0x300,SR                       | mask interrupts (atomic)
    JSR         ENQUEUE(PC)                     | enqueue param block onto FS queue
FSQUEUE_TRY_LOCK:
    BSET        #0x0,(FSQHdr_Flags)             | try to grab server lock
    BEQ.B       FSQUEUE_SERVER                  | won lock, run server
    MOVEQ.L     #0x0,D0                         | already locked: D0 = 0 (success)
    MOVE.W      (A7)+,SR                        | restore SR
    RTS                                         | return (server will process us)
| ----------------------------------------------------------
|
| FS queue server - dequeue and execute pending FS calls
|
| Processes the head entry of the FS queue. Sets up the PMSP
| (Permission State Machine Pointer) and HFS stack, then calls
| the routine address stored in ioCmdAddr of the param block.
FSQUEUE_SERVER:
    MOVE.W      (A7)+,SR                        | restore SR (drop interrupt mask)
    MOVEA.L     (FSQHdr_Head).W,A0              | A0 -> queue head param block
    MOVEA.L     0x8(A0),A1                      | A1 = ioCmdAddr (handler addr)
    MOVEM.L     D3-D7/A2-A6,-(A7)               | save server-clobber regs
    MOVEA.L     (PMSPPtr).W,A6                  | A6 -> PMSP
    CLR.W       -0x2(A6)                        | clear PMSP[-2] (NxtDB sentinel)
    BTST        #0xA,0x6(A0)                    | async bit set in ioTrap ?
    SNE.B       (NxtDB).W                       | NxtDB := -1 if async, else 0
    MOVEA.L     (HFSVars_HFSStkTop).W,A6        | A6 = HFS stack top
    JSR         (A1)                            | call handler (ioCmdAddr)
    MOVEM.L     (A7)+,D3-D7/A2-A6               | restore regs
    RTS                                         | return from FSQueue server
| ----------------------------------------------------------
|
| NOPKG_SYSERROR - fatal error: no packages loaded (dsNoPk = 27)
|
| Called when a required package (e.g., Standard File) is not
| available. Triggers a system error with ID 27 (dsNoPk).
NOPKG_SYSERROR:
    MOVEQ.L     #0x1B,D0                        | dsNoPk = 27
    _SysError                                   | trigger Sad Mac (no return)
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
| Called by: FSDISPATCH_BAD_SEL, P_hfs0, MTVOLDONE_EXIT, MOUNTVOL_CONT_10, EJECT_DONE (and 35 more)
FSQUEUE_DONE:
    CLR.B       (SysCRefCnt).W                  | clear sys-call ref count
    EXT.L       D0                              | sign-extend result to long
    BLE.B       FSQUEUE_STORE_ERR               | <= 0 (success or err code), normal path
    MOVE.W      D0,(HFSDSErr).W                 | > 0: stash extended err in HFSDSErr
    MOVEQ.L     #-0x7F,D0                       | D0 = -127 (extFsErr)
FSQUEUE_STORE_ERR:
    MOVEA.L     (FSQHdr_Head).W,A0              | A0 -> head param block
    CMPI.W      #0x5,0x4(A0)                    | qType == 5 (fsType) ?
    BNE.B       NOPKG_SYSERROR                  | no, fatal mismatch
    CMPI.W      #0xFFD5,D0                      | err == nsDrvErr (-43) ?
    BNE.B       FSQUEUE_CLR_OFFLINE             | no, just dispatch err
    BTST        #0x9,0x6(A0)                    | bit 9 of ioTrap (no-disk-switch) ?
    BEQ.B       FSQUEUE_TRY_SWITCH              | clear, allow switch
    TST.L       0x30(A0)                        | ioFCBIndx non-nil ?
    BNE.B       FSQUEUE_CLR_OFFLINE             | yes, file already open -> err
FSQUEUE_TRY_SWITCH:
    BTST        #0x6,(HFSFlags)                 | mid-MountVol flag set ?
    BNE.B       FSQUEUE_CLR_OFFLINE             | yes, can't switch
    BTST        #0x5,(HFSFlags)                 | already chasing alt-vol ?
    BNE.B       FSQUEUE_CLR_OFFLINE             | yes, can't recurse
    MOVEA.L     (PMSPPtr).W,A1                  | A1 -> PMSP (alt-vol scan list)
    MOVEM.L     D1/A2,-(A7)                     | save D1, A2
    MOVE.W      -0x2(A1),D1                     | D1 = current scan position
| FSQUEUE_SCAN_NEXT -- walk PMSP looking for an online VCB drive
FSQUEUE_SCAN_NEXT:
    ADDQ.W      #0x6,D1                         | next slot in PMSP
    CMP.W       (A1),D1                         | past end ?
    BGE.B       FSQUEUE_SCAN_END                | yes
    MOVE.W      0x0(A1,D1.W),D0                 | D0 = vRefNum candidate
    BEQ.B       FSQUEUE_SCAN_END                | empty slot, end
    BSR.W       GETVCBRFN                       | look up VCB by vRefNum
    BNE.B       FSQUEUE_SCAN_END                | not found
    MOVE.W      0x48(A2),D0                     | D0 = VCB drvNum
    BLE.B       FSQUEUE_SCAN_NEXT               | offline, keep scanning
FSQUEUE_SCAN_END:
    MOVE.W      D1,-0x2(A1)                     | save scan position
    MOVE.W      D1,D0                           | D0 = scan position
    MOVEM.L     (A7)+,D1/A2                     | restore D1, A2
    CMP.W       (A1),D0                         | past end ?
    BGE.B       FSQUEUE_NO_DRIVE                | yes, no online drive
    TST.W       0x0(A1,D0.W)                    | slot empty ?
    BEQ.B       FSQUEUE_NO_DRIVE                | yes, no drive
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      0x7(A0),D0                      | D0 = HFS selector
    MOVEA.L     0x8(A0),A1                      | A1 = ioCmdAddr
    JMP         (A1)                            | retry on alternate volume
| ----------------------------------------------------------
|
| FSQUEUE_NO_DRIVE - no alternate drive found, report nsDrvErr
|
FSQUEUE_NO_DRIVE:
    MOVEQ.L     #-0x2B,D0                       | D0 = nsvErr (-43, no such volume)
FSQUEUE_CLR_OFFLINE:
    BCLR        #0x5,(HFSFlags)                 | clear alt-vol search flag
    MOVE.L      (ExtFSHook).W,D2                | D2 = ExtFSHook addr
    BLE.B       FSQUEUE_CHK_EXTFS               | no hook, skip
    MOVEA.L     D2,A1                           | A1 = ExtFSHook
    JSR         (A1)                            | call ExtFSHook(D0, A0)
FSQUEUE_CHK_EXTFS:
    CMPI.W      #0xFFC6,D0                      | err == extFsErr (-58) ?
    BNE.B       FSQUEUE_DEQUEUE                 | no, normal completion
    MOVE.L      (ToExtFS).W,D2                  | D2 = ToExtFS handler
    BLE.B       FSQUEUE_DEQUEUE                 | no handler, just dequeue
    MOVEA.L     D2,A1                           | A1 = ToExtFS
    MOVEA.L     (FSQHdr_Head).W,A0              | A0 -> head param block
    CMPI.W      #0x5,0x4(A0)                    | qType == 5 ?
    BNE.W       NOPKG_SYSERROR                  | no, fatal
    TST.W       0x6(A0)                         | ioTrap < 0 (HFS variant) ?
    BLT.B       FSQUEUE_CALL_EXTFS              | yes, call ExtFS as-is
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      0x7(A0),D0                      | D0 = HFS selector
    CLR.B       0x7(A0)                         | clear selector byte
    ORI.W       #0xA060,0x6(A0)                 | reconstruct trap word for ExtFS
FSQUEUE_CALL_EXTFS:
    JSR         (A1)                            | call ToExtFS(D0, A0)
FSQUEUE_DEQUEUE:
    MOVE.W      SR,-(A7)                        | save SR
    ORI.W       #0x300,SR                       | mask interrupts (atomic dequeue)
    CLR.W       (FSQHdr_Flags).W                | release server lock
    MOVEA.L     (FSQHdr_Head).W,A0              | A0 -> head
    CMPI.W      #0x5,0x4(A0)                    | qType == 5 ?
    BNE.W       NOPKG_SYSERROR                  | no, fatal
    MOVE.L      (A0),(FSQHdr_Head).W            | head := head.qLink
    BNE.B       FSQUEUE_RESTORED_SR             | non-nil, queue not empty
    CLR.L       (FSQHdr_Tail).W                 | empty queue, clear tail too
FSQUEUE_RESTORED_SR:
    MOVE.W      (A7)+,SR                        | restore SR
    MOVE.W      D0,0x10(A0)                     | ioResult = D0
    MOVE.L      0xC(A0),D1                      | D1 = ioCompletion
    BEQ.B       FSQUEUE_CHK_MORE                | nil, no callback
    MOVEA.L     D1,A1                           | A1 = ioCompletion
    TST.W       D0                              | set CCR for callback
    JSR         (A1)                            | call ioCompletion(A0)
FSQUEUE_CHK_MORE:
    MOVE.W      SR,-(A7)                        | save SR
    ORI.W       #0x300,SR                       | mask interrupts
    TST.L       (FSQHdr_Head).W                 | more in queue ?
    BNE.W       FSQUEUE_TRY_LOCK                | yes, run server again
    MOVE.W      (A7)+,SR                        | no, restore SR
    RTS                                         | return from FSQueue completion
| ----------------------------------------------------------
|
| FINITQUEUE -- truncate FS queue to single head entry
|
| Used during disk-switch dialog so completion callbacks for
| stale entries in the queue don't fire while the user fumbles
| for the right disk. Atomically truncates qLink of head to nil
| and points qTail at head (new effective tail).
|
FINITQUEUE:
    MOVE.W      SR,-(A7)                        | save SR
    ORI.W       #0x300,SR                       | mask interrupts
    MOVE.L      (FSQHdr_Head).W,D0              | D0 = head ptr
    BEQ.B       FINITQ_DONE                     | empty queue, nothing to do
    MOVEA.L     D0,A0                           | A0 -> head EvQEl
    CLR.L       (A0)                            | head.qLink := nil
    MOVE.L      A0,(FSQHdr_Tail).W              | qTail := head (single entry)
FINITQ_DONE:
    MOVEQ.L     #0x0,D0                         | D0 = 0
    MOVE.W      (A7)+,SR                        | restore SR
    RTS                                         | return from FInitQueue
| ====================================================================
|
| DSHOOK -- Disk-Switch Hook
|
| Posts the "Please insert the disk:" dialog when an FS call hits
| nsDrvErr (-43) and the requested volume can't be found online.
| First tries to silently re-mount via _MountVol on the original
| drive number. If that fails, falls into DSHOOK_SHOW_DLG to put
| up the floating alert and poll for either a disk-insertion or
| Cmd-period (cancel).
|
| On entry: A0 -> failed FS param block, D3 = failed vRefNum.
|
DSHOOK:
    MOVEM.L     D0-D7/A0-A3/A6,-(A7)            | save all caller regs
    LEA.L       (TrapAgain).W,A1                | A1 -> TrapAgain trampoline
    MOVE.W      0x6(A0),(A1)+                   | install ioTrap word
    MOVE.W      #0x4E75,(A1)                    | + RTS opcode (so trampoline returns)
    BSR.W       MAKESTKPB                       | build stack-based param block
    MOVE.L      A0,D7                           | D7 = stack PB ptr
    MOVEA.L     (ReqstVol).W,A2                 | A2 -> requested VCB
    MOVE.W      0x4A(A2),D3                     | D3 = VCB drvNum
    BPL.B       DSHOOK_SHOW_DLG                 | online (positive), show dialog
    NEG.W       D3                              | offline: get back +drvNum
    MOVE.W      D3,0x16(A0)                     | ioVRefNum := -drvNum
    _MountVol                                   | try silent remount
    BNE.B       DSHOOK_SHOW_DLG                 | failed, show dialog
    MOVEQ.L     #0x0,D3                         | success, D3 = 0 (no dialog needed)
    BRA.W       DSHOOK_CLEANUP                  | tear down trampoline + return
| ----------------------------------------------------------
|
| DSHOOK_SHOW_DLG - set up and show the disk-switch dialog
|
| Sets up the alert rectangle, optionally creates a temporary QD port
| to save/restore screen contents behind the dialog, then calls
| _SysError with dsErrCode=30 to display the "please insert" alert.
DSHOOK_SHOW_DLG:
    MOVE.L      #0x500078,(DSAlertRect).W       | DSAlertRect.tl = (80,120)
    MOVE.L      #0x980195,(DSAlertRect_botRight).W | DSAlertRect.br = (152,405)
    MOVEQ.L     #0x0,D4                         | D4 = save-thePort handle (0 if none)
    MOVEQ.L     #0x0,D5                         | D5 = saved A7 (0 if no temp port)
    TST.B       (QDExist).W                     | QuickDraw initialized ?
    BNE.B       DSHOOK_SYSERROR                 | no, just call SysError directly
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVE.L      (A0),D4                         | save current thePort
    MOVE.L      A7,D0                           | D0 = candidate temp area = SP - 0x12BE
    SUBI.L      #0x12BE,D0                      | (4798 bytes for temp port + bg save)
    MOVEA.L     (ApplZone).W,A0                 | A0 -> ApplZone
    CMP.L       (A0),D0                         | would clobber zone ?
    BLE.B       DSHOOK_SYSERROR                 | yes, skip temp port
    MOVE.L      A7,D5                           | save current SP
    ADDI.L      #0x800,D0                       | + 2048 for temp QD port
    MOVEA.L     D0,A7                           | SP = D0 (allocate)
    MOVE.L      D0,D6                           | D6 = bg save buffer base
    MOVEA.L     A7,A0                           | A0 = QD-port template
    PEA.L       0xE(A0)                         | push QD-port baseAddr (offset 14)
    MOVE.L      (A7)+,(A0)+                     | install baseAddr in port
    MOVE.W      #0x24,(A0)+                     | rowBytes = 0x24 (36)
    CLR.L       (A0)+                           | bounds.tl = (0,0)
    MOVE.L      #0x48011D,(A0)+                 | bounds.br = (72,285)
    SUBA.W      #0x74,A7                        | 116-byte temp port
    MOVEA.L     A7,A6                           | A6 -> temp port
    JSR         ALLOCFAKERGNS(PC)               | install fake clip + visRgn
    MOVE.L      A7,-(A7)                        | push port ptr
    _InitPort                                   | InitPort(temp port)
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVE.L      A6,(A0)                         | thePort := temp port
    PEA.L       -0x7A(A0)                       | push screenBits source (rowBytes-relative)
    MOVE.L      D6,-(A7)                        | push bg save bitMap
    PEA.L       (DSAlertRect).W                 | push srcRect
    MOVEA.L     D6,A0                           | A0 -> bg bitMap
    PEA.L       0x6(A0)                         | push dstRect (bitMap.bounds)
    CLR.W       -(A7)                           | mode = srcCopy
    CLR.L       -(A7)                           | maskRgn = nil
    _CopyBits                                   | save background under alert
DSHOOK_SYSERROR:
    MOVEQ.L     #0x1E,D0                        | dsDiskInsErr = 30
    _SysError                                   | post the floating alert
    MOVE.L      (DrvQHdr_Head).W,D0             | start at head of DrvQHdr
| Walk the drive queue looking for the failed drive (drvNum in D3).
DSHOOK_SCAN_DRV:
    BEQ.B       DSHOOK_EVT_LOOP                 | end of queue, switch to event poll
    MOVEA.L     D0,A1                           | A1 -> current DrvQEl
    CMP.W       0x6(A1),D3                      | drvNum match ?
    BEQ.B       DSHOOK_FOUND_DRV                | yes, found it
    MOVE.L      (A1),D0                         | D0 = qLink
    BRA.B       DSHOOK_SCAN_DRV                 | next entry
| ----------------------------------------------------------
|
| DSHOOK_FOUND_DRV - found drive in queue, eject if it's a floppy (type 1 or 2)
|
DSHOOK_FOUND_DRV:
    MOVE.B      -0x3(A1),D0                     | D0 = dQDrvSz hi byte (drive type tag)
    CMPI.B      #0x1,D0                         | type 1 (Sony 400K) ?
    BEQ.B       DSHOOK_EJECT_DRV                | yes, eject
    CMPI.B      #0x2,D0                         | type 2 (Sony 800K) ?
    BNE.B       DSHOOK_EVT_LOOP                 | no, not floppy, just poll
DSHOOK_EJECT_DRV:
    MOVE.W      D3,D1                           | D1 = drvNum to eject
DSHOOK_DO_EJECT:
    MOVEQ.L     #0x2,D2                         | D2 = vRefNum (placeholder, fields 1,2 hardwired)
    BSR.W       DOEJECT                         | issue _Eject via FS frontend
| ----------------------------------------------------------
|
| DSHOOK_EVT_LOOP / DSHOOK_POLL_EVT -- main wait loop
|
| Mask 0x88 = diskEvt (bit 7) | keyDownEvt (bit 3). Polls until
| either a disk insertion (sysEvt code 7) or a Cmd-period (key
| 0x2E with cmdKey modifier in D1 hi byte) is received.
|
| Called by: DSHOOK_POLL_EVT, DSHOOK_SCAN_DRV, DSHOOK_FOUND_DRV, DSHOOK_CALL_KBDTASK, DSHOOK_CHK_CMDPER
DSHOOK_EVT_LOOP:
    SUBA.W      #0x10,A7                        | reserve 16-byte event record
DSHOOK_POLL_EVT:
    MOVE.W      #0x88,D0                        | D0 = mask (diskEvt | keyDownEvt)
    MOVEA.L     A7,A0                           | A0 -> event buffer
    _GetOSEvent                                 | poll for event
    BNE.B       DSHOOK_POLL_EVT                 | none, keep polling
    MOVE.L      0x2(A7),D0                      | D0 = evtMessage
    MOVE.W      (A7),D3                         | D3 = evtNum
    MOVE.W      0xE(A7),D1                      | D1 = evtMeta (modifiers)
    ADDA.W      #0x10,A7                        | drop event record
    SUBQ.W      #0x7,D3                         | evtNum == 7 (diskEvt) ?
    BEQ.B       DSHOOK_DISK_INSERT              | yes, try to mount
    CMPI.B      #0x2E,D0                        | keyCode = '.' ?
    BEQ.B       DSHOOK_CHK_CMDPER               | yes, check Cmd modifier
    MOVEQ.L     #0xB,D2                         | D2 = mask 0x0B (cmd|opt|shift)
    LSR.W       #0x8,D1                         | shift modifier byte to low
    AND.B       D1,D2                           | D2 = matched bits
    SUBQ.B      #0x3,D2                         | == 3 (cmd|shift, no opt) ?
    BNE.B       DSHOOK_EVT_LOOP                 | no, keep polling
    CMPI.B      #0x2,D0                         | keyCode in [0..2] ?
    BGT.B       DSHOOK_EVT_LOOP                 | no, keep polling
    TST.B       D0                              | keyCode 0 ?
    BMI.B       DSHOOK_EVT_LOOP                 | shouldn't happen, but skip
    BNE.B       DSHOOK_CALL_KBDTASK             | non-zero, use as-is
    MOVEQ.L     #0x3,D0                         | else use code 3 (default)
DSHOOK_CALL_KBDTASK:
    MOVE.B      D0,D1                           | D1 = key code
    MOVEQ.L     #0x1,D2                         | D2 = mode 1
    MOVEA.L     (0x7DC).W,A0                    | A0 = JKybdTask vector
    JSR         (A0)                            | execute keyboard task
    BRA.B       DSHOOK_EVT_LOOP                 | back to polling
DSHOOK_CHK_CMDPER:
    BTST        #0x8,D1                         | Cmd key down ?
    BEQ.B       DSHOOK_EVT_LOOP                 | no, ignore
    BRA.B       DSHOOK_DISMISS                  | yes, Cmd-period -> cancel
| ----------------------------------------------------------
|
| DSHOOK_DISK_INSERT - disk inserted, try to mount it
|
DSHOOK_DISK_INSERT:
    MOVEA.L     D7,A0                           | A0 -> stack PB
    MOVE.W      D0,0x16(A0)                     | ioVRefNum = inserted drvNum
    MOVE.W      D0,D1                           | D1 = drvNum
    _MountVol                                   | try to mount the new disk
    BEQ.B       DSHOOK_DISMISS                  | success, dismiss alert
    CMPI.W      #0xFF94,D0                      | err == volOnLinErr (-108) ?
    BNE.B       DSHOOK_DO_EJECT                 | other err, eject and keep polling
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (canceled flag)
DSHOOK_DISMISS:
    TST.L       D5                              | did we set up a temp port ?
    BEQ.B       DSHOOK_NO_PORT                  | no, skip bg restore
    MOVE.L      D6,-(A7)                        | push bg save bitMap
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVE.L      A6,(A0)                         | thePort := temp port
    PEA.L       -0x7A(A0)                       | push screenBits dst
    MOVEA.L     D6,A0                           | A0 -> bg bitMap
    PEA.L       0x6(A0)                         | push srcRect (bg bounds)
    PEA.L       (DSAlertRect).W                 | push dstRect (alert)
    CLR.W       -(A7)                           | mode = srcCopy
    CLR.L       -(A7)                           | maskRgn = nil
    _CopyBits                                   | restore bg under alert
    MOVEA.L     D5,A7                           | restore SP
    BRA.B       DSHOOK_SETPORT                  | reinstate caller's thePort
| ----------------------------------------------------------
|
| DSHOOK_NO_PORT - no temp port: flag windows need updating
|
DSHOOK_NO_PORT:
    CLR.B       (DSWndUpdate).W                 | mark windows need update
    TST.L       D4                              | had a saved thePort ?
    BEQ.B       DSHOOK_CLEANUP                  | no, skip SetPort
DSHOOK_SETPORT:
    MOVE.L      D4,-(A7)                        | push saved thePort
    _SetPort                                    | restore caller's port
DSHOOK_CLEANUP:
    BSET        #0x7,(DSAlertRect)              | mark DSAlertRect as dismissed
    ADDA.W      #0x40,A7                        | strip stack PB
    TST.W       D3                              | D3 = 0 -> mount succeeded ?
    MOVEM.L     (A7)+,D0-D7/A0-A3/A6            | restore caller regs
    BEQ.B       DSHOOK_RETRY_TRAP               | yes, retry the original FS call
    MOVEQ.L     #-0x35,D0                       | else D0 = userCanceledErr (-53)
    RTS                                         | return from DSHook
| ----------------------------------------------------------
|
| DSHOOK_RETRY_TRAP - disk-switch succeeded, re-execute the original FS call
|
| The ioTrap word was saved in TrapAgain earlier. We jump to it
| to re-execute the trap that originally caused the disk-switch.
DSHOOK_RETRY_TRAP:
    MOVE.W      0x6(A0),D0                      | D0 = saved ioTrap word
    BGT.B       DSHOOK_FIX_ALINE                | A-line trap, fix encoding

    .byte 0x4E,0xF8,0x0B,0x00                   | JMP (TrapAgain).W - region head trampoline
| ----------------------------------------------------------
|
| DSHOOK_FIX_ALINE - convert trap number to A-line instruction and re-execute
|
DSHOOK_FIX_ALINE:
    ORI.B       #0xA0,(TrapAgain).W             | set high nibble to 0xA0 (A-line opcode)
    MOVE.B      #0x60,(TrapAgain_1).W           | TrapAgain+1 = 0x60 (BRA.S offset)
    ANDI.W      #0xFF,D0                        | mask to 8-bit trap number
    .byte 0x4E,0xF8,0x0B,0x00                   | JMP (TrapAgain) - execute patched A-line

