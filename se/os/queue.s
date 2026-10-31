| OS Queue Primitives -- Enqueue / Dequeue / InitQueuePrim
|
| Three core list-manipulation routines used by the Device Manager
| (I/O queue), Event Manager (event queue), and VBL task manager.
|
| Routines:
| Enqueue - append element at A0 to tail of queue header at A1
| (protected by IPL=3 critical section).
| Dequeue - search queue for element at A0, unlink if found; Z=1
| on success, Z=0 if not in queue.
| InitQueuePrim - zero out a 10-byte QHdr at A1 (flags, qHead, qTail)
| and leave A1 pointing at the header.
|
| Queue header layout (per sysequ.inc QHdr):
| +0 qFlags (word)
| +2 qHead (long -- first element, nil if empty)
| +6 qTail (long -- last element, nil if empty)
| Each element's qLink (first long) points to the next element, or nil.
|
| References: Inside Macintosh Vol II, Ch 9 (Operating System Utilities).

| ENQUEUE - Enqueue: add element A0 to tail of queue at A1
|
| Queue header at (A1): +0 = flags (word), +2 = qHead (long), +6 = qTail (long)
| Element at (A0): +0 = qLink (long, next pointer)
| Runs with IPL raised to prevent interrupt corruption.
| Called by: VINSTALL_ENQUEUE, ENQUEUE_IOREQ, ADDDRIVE, POSTEVENT_FILL, FSQUEUE_ENQUEUE (and 2 more)
QSTUFF:                                         | Apple source module (MacSEROM.lst)
ENQUEUE:
    MOVE.W      SR,-(A7)                        | save status register
    ADDQ.W      #0x2,A1                         | A1 = skip flags word, point to qHead
    ORI.W       #0x300,SR                       | raise IPL to 3 (block interrupts)
    CLR.L       (A0)                            | clear new element's qLink (end of chain)
    TST.L       (A1)+                           | qHead empty? (A1 now -> qTail)
    BNE.B       ENQ_APPEND_TAIL                 | non-empty: append to existing tail
    MOVE.L      A0,(A1)                         | empty queue: qTail = new element
    MOVE.L      A0,-(A1)                        | qHead = new element (only element)
    BRA.B       ENQ_DONE                        | done
| ENQ_APPEND_TAIL - queue not empty: link after current tail
ENQ_APPEND_TAIL:
    MOVE.L      A2,-(A7)                        | save A2
    MOVEA.L     (A1),A2                         | A2 = current qTail element
    MOVE.L      A0,(A2)                         | old tail->qLink = new element
    MOVE.L      A0,(A1)                         | qTail = new element
    MOVEA.L     (A7)+,A2                        | restore A2
    SUBQ.W      #0x4,A1                         | A1 back to qHead
ENQ_DONE:
    SUBQ.W      #0x2,A1                         | A1 back to queue header (flags)
    MOVE.W      (A7)+,SR                        | restore status (re-enable interrupts)
    RTS                                         | return from Enqueue
| DEQUEUE - remove element A0 from queue at A1
|
| Searches queue for element A0, unlinks it from the chain.
| Returns D0 = 0 if found and removed, D0 = -1 if not found.
| Called by: VBL_TASK_LOOP, VREMOVE, ADB_DEQUEUE_INVALIDATE, MOUNTVOL_DEQUEUE_NEW_VCB, BMCHK_NO (and 1 more)
DEQUEUE:
    MOVE.W      SR,-(A7)                        | save status register
    MOVEM.L     A2-A3,-(A7)                     | save search pointers
    ORI.W       #0x300,SR                       | raise IPL to 3
    MOVEA.L     0x2(A1),A2                      | A2 = qHead (first element)
    MOVEA.L     A2,A3                           | A3 = current search element
DEQ_SEARCH_LOOP:
    CMPA.L      A3,A0                           | found target element?
    BEQ.B       DEQ_UNLINK                      | yes: unlink it
    MOVEA.L     A3,A2                           | A2 = previous element
    MOVEA.L     (A2),A3                         | A3 = next element (follow qLink)
    CMPA.L      0x6(A1),A2                      | reached qTail without finding?
    BNE.B       DEQ_SEARCH_LOOP                 | no: keep searching
    MOVEQ.L     #-0x1,D0                        | not found: D0 = -1
    BRA.B       DEQ_RETURN                      | return error
| DEQ_UNLINK - unlink element from head of queue
DEQ_UNLINK:
    CMPA.L      A2,A3                           | element at head? (A2 == A3)
    BNE.B       DEQ_UNLINK_MID                  | no: unlink from middle/tail
    MOVE.L      (A2),0x2(A1)                    | qHead = element->qLink (skip head)
    BNE.B       DEQ_SUCCESS                     | new head exists: done
    CLR.L       0x6(A1)                         | queue now empty: clear qTail
DEQ_SUCCESS:
    MOVEQ.L     #0x0,D0                         | success: D0 = 0
DEQ_RETURN:
    MOVEM.L     (A7)+,A2-A3                     | restore search pointers
    MOVE.W      (A7)+,SR                        | restore status register
    RTS                                         | return from Dequeue
| DEQ_UNLINK_MID - unlink from middle or tail of queue
DEQ_UNLINK_MID:
    MOVE.L      (A3),(A2)                       | prev->qLink = target->qLink (skip)
    CMPA.L      0x6(A1),A3                      | was target the qTail?
    BNE.B       DEQ_SUCCESS                     | no: done
    MOVE.L      A2,0x6(A1)                      | yes: qTail = previous element
    BRA.B       DEQ_SUCCESS                     | done
| INITQUEUE - initialize an empty queue header
|
| Clears the 10-byte queue header: flags (word), qHead (long), qTail (long)
INITQUEUE:
    CLR.W       (A1)+                           | clear flags word
    CLR.L       (A1)+                           | clear qHead
    CLR.L       (A1)                            | clear qTail
    SUBQ.W      #0x6,A1                         | restore A1 to queue header
    RTS                                         | return from InitQueue
