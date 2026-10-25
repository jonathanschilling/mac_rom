| File Manager -- file system queue and _FInitQueue (MFS)
|
| The File Manager's call queue in the 64K ROM: FSQueueSync / FSQueue
| (FSQUEUE_CLR_OFFLINE, FSQUEUE_SETUP: queue the call, wait for it if it is
| synchronous), FSCall (start the call unless the File Manager is busy),
| CmdDone (FSQUEUE_DONE: finish the current call, run its completion
| routine, start the next one) and _FInitQueue ($A016, flush the queue).
| The Mac Plus has the same code, with the HFS dispatcher and the
| disk-switch hook, in its os/file_mgr_queue.s.
|
| References: Inside Macintosh Vol II, Ch 4: The File Manager

| ----------------------------------------------------------
| FSQUEUE_CLR_OFFLINE - FSQueueSync: clear the ASYNC bit, then fall
| into FSQueue (MountVol and UnmountVol always run synchronously).
| Apple source name: FSQueueSync (System 7.1 OS/HFS/TFS.a)
FSQUEUE_CLR_OFFLINE:
        BCLR    #0xA,D1                         | clear ASYNC bit (bit 10) of the trap word
| FSQUEUE_SETUP - FSQueue: queue the call (A0 = parameter block,
| D1 = trap word). The code after the caller's BSR becomes ioCmdAddr
| and runs when the call reaches the head of the file I/O queue.
| Apple source name: FSQueue (System 7.1 OS/HFS/TFS.a)
| Called by: Eject, FlushVol, SetVol, GetVol, GetVolInfo (and 17 more)
FSQUEUE_SETUP:
        MOVE.L  (FSQueueHook).w,D2              | D2 = optional pre-call hook
        BLE.B   FSCall                          | no hook -> skip
        MOVE.L  D2,A1                           | A1 = hook address
        JSR     (A1)                            | call FSQueueHook
| FSCall - mark the call in progress and queue it
FSCall:
        MOVE    #0x1,ioResult(A0)               | ioResult = 1 (in progress)
        MOVE    D1,ioTrap(A0)                   | ioTrap = D1 (trap word)
        MOVE.L  (SP)+,ioCmdAddr(A0)             | ioCmdAddr = rest of the calling FS routine
        MOVE    #0x5,qType(A0)                  | qType = 5 (user queue type)
        BTST    #0xA,D1                         | async-call bit set in trap word?
        BEQ.B   FSCALL_CONT                     | synchronous call ->
        TST.B   (FrcSync).w                     | force-sync override active?
        BEQ.B   FSQUEUE_ENQUEUE                 | no -> queue async, return now
        BRA.B   FSQUEUE_FCALL_NOCMD             | forced sync: enqueue + wait
FSCALL_CONT:
        CLR.L    12(A0)                         | clear ioCompletion (sync call)
FSQUEUE_FCALL_NOCMD:
        MOVE.L   A0,-(SP)                       | save param block ptr
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
FSQUEUE_TRY_LOCK:                               | start the call unless FS busy
        BSET    #0x0,(FSQHdr_Flags).w           | test-and-set FS busy flag
        BEQ.B   FSQUEUE_DISPATCH                | we got the lock -> dispatch
        MOVEQ.L #0x0,D0                         | D0 = 0 (queued for later)
        RTE                                     | restore SR + return
FSQUEUE_DISPATCH:
        MOVE    (SP)+,SR                        | restore interrupts
        MOVE.L  (FSQHdr_Head).w,A0              | A0 = head param block
        MOVE.L  8(A0),A1                        | A1 = ioCmdAddr (the queued FS routine)
        MOVEM.L D3-D7/A2-A6,-(SP)               | save callee-saved regs
        JSR     (A1)                            | run it (it ends via FSQUEUE_DONE)
        MOVEM.L (SP)+,D3-D7/A2-A6               | restore callee-saved regs
        RTS                                     | return from FS dispatch
| FSQUEUE_DONE - CmdDone (Apple name): finish the current FS call with
| result D0, run its completion routine, start the next queued call.
FSQUEUE_DONE:
        MOVE.L  (ExtFSHook).w,D2                | D2 = external FS post-hook
        BLE.B   FSQUEUE_DEQUEUE                 | no hook -> skip
        MOVE.L  D2,A1                           | A1 = ExtFS post-hook addr
        JSR     (A1)                            | call ExtFSHook
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
        JSR     (A1)                            | call ioCompletion (D0 = result)
FSQUEUE_COMPLETE:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
        TST.L   (FSQHdr_Head).w                 | more pending requests?
        BNE.B   FSQUEUE_TRY_LOCK                | head non-nil -> retry lock
        RTE                                     | restore SR + return

| ----------------------------------------------------------
| _FInitQueue ($A016; IM trap macro _InitQueue): flush the File
| Manager queue
| Pascal: PROCEDURE FInitQueue;
| Exit: D0 = noErr
| Removes all queued File Manager calls except the one in progress:
| at IPL 3 the head of the file I/O queue (FSQHdr) becomes its only
| element. The removed calls are not completed.
| Apple source name: FInitQueue (System 7.1 OS/HFS/TFS.a; MacSEROM.lst)
InitQueue:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
        MOVE.L  (FSQHdr_Head).w,D0              | D0 = head paramBlk
        BEQ.B   FSQUEUE_CHK_MORE                | empty queue -> done
        MOVE.L  D0,A0                           | A0 = the call in progress (queue head)
        CLR.L   (A0)                            | qLink := nil: drop all calls queued after it
        MOVE.L  A0,(FSQHdr_Tail).w              | FSQHdr_Tail = A0
FSQUEUE_CHK_MORE:
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        RTE                                     | restore SR + return

