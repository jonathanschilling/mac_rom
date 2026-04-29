| OS Queue Primitives -- Enqueue / Dequeue / InitQueue
|
| Three core list-manipulation routines used by the Device Manager
| (I/O queue), Event Manager (event queue), and VBL task manager.
|
| Routines:
| Enqueue - append element at A0 to tail of queue header at A1
| (protected by IPL=3 critical section).
| Dequeue - search queue for element at A0, unlink if found; Z=1
| on success, Z=0 if not in queue.
| InitQueue - zero out a 10-byte QHdr at A1 (flags, qHead, qTail)
| and leave A1 pointing at the header.
|
| Queue header layout (per sysequ.inc QHdr):
| +0 qFlags (word)
| +2 qHead (long -- first element, nil if empty)
| +6 qTail (long -- last element, nil if empty)
| Each element's qLink (first long) points to the next element, or nil.
|
| References: Inside Macintosh Vol II, Ch 9 (Operating System Utilities).

| ----------------------------------------------------------
|
| _Enqueue ($A96F) - add element to end of OS queue
|
| A0 = ptr to QElem to insert (first long is qLink).
| A1 = ptr to QHdr (flags, qHead, qTail).
| Queue is a singly-linked list: qHead -> ... -> qTail -> nil.
Enqueue:
        MOVE    SR,-(SP)                        | save SR (interrupt state)
        ADDQ.W  #0x2,A1                         | skip qFlags, A1 = &qHead
        ORI     #0x300,SR                       | disable interrupts (IPL=3)
        CLR.L   (A0)                            | new element's qLink = nil (end of chain)
        TST.L   (A1)+                           | test qHead; A1 now = &qTail
        BNE.B   ENQ_APPEND_TAIL                 | queue not empty - append at tail
        MOVE.L  A0,(A1)                         | empty queue: qTail = new element
        MOVE.L  A0,-(A1)                        | qHead = new element (A1 backs up)
        BRA.B   ENQ_DONE                        | done

| ----------------------------------------------------------
|
| ENQ_APPEND_TAIL - queue not empty: link new element after current tail
|
ENQ_APPEND_TAIL:
        MOVE.L  A2,-(SP)                        | save A2
        MOVE.L  (A1),A2                         | A2 = current qTail
        MOVE.L  A0,(A2)                         | old tail's qLink = new element
        MOVE.L  A0,(A1)                         | qTail = new element
        MOVE.L  (SP)+,A2                        | restore A2
        SUBQ.W  #0x4,A1                         | A1 back to &qHead
ENQ_DONE:
        SUBQ.W  #0x2,A1                         | A1 back to &qFlags (original A1)
        RTE                                     | restore SR, return (also clears CCR)

| ----------------------------------------------------------
|
| _Dequeue ($A96E) - remove element from OS queue
|
| A0 = ptr to QElem to remove.
| A1 = ptr to QHdr (flags, qHead, qTail).
| Returns D0: 0 = success, -1 = element not found.
| Called by: VBL_TASK_LOOP, VRemove, SONY_CHECKFORNEWDISKS_CONT_4_NO_CONT, DEQUEUE_INVALIDATE, BMCHK_NO
Dequeue:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L A2-A3,-(SP)                     | save working regs
        ORI     #0x300,SR                       | disable interrupts
        MOVE.L  qHead(A1),A2                    | A2 = qHead (previous ptr)
        MOVE.L  A2,A3                           | A3 = current element being checked
DEQ_SEARCH_LOOP:
        CMPA.L  A3,A0                           | found the target element?
        BEQ.B   DEQ_UNLINK                      | yes - unlink it
        MOVE.L  A3,A2                           | A2 = previous (for relinking)
        MOVE.L  (A2),A3                         | A3 = A2->qLink (next element)
        CMPA.L  qTail(A1),A2                    | reached qTail without finding it?
        BNE.B   DEQ_SEARCH_LOOP                 | no - keep searching
        MOVEQ.L #-0x1,D0                        | error: element not in queue
        BRA.B   DEQ_RETURN                      | return -1

| ----------------------------------------------------------
|
| DEQ_UNLINK - unlink element from queue
|
DEQ_UNLINK:
        CMPA.L  A2,A3                           | target is qHead? (A2==A3 at start)
        BNE.B   DEQ_UNLINK_MID                  | no - unlink from middle/end
        MOVE.L  (A2),qHead(A1)                  | qHead = target->qLink (next elem)
        BNE.B   DEQ_SUCCESS                     | queue still has elements
        CLR.L   qTail(A1)                       | queue now empty: qTail = nil
DEQ_SUCCESS:
        MOVEQ.L #0x0,D0                         | success
DEQ_RETURN:
        MOVEM.L (SP)+,A2-A3                     | restore regs
        RTE                                     | restore SR, return

| ----------------------------------------------------------
|
| DEQ_UNLINK_MID - unlink element from middle or end of queue
|
DEQ_UNLINK_MID:
        MOVE.L  (A3),(A2)                       | previous->qLink = target->qLink
        CMPA.L  qTail(A1),A3                    | was target the qTail?
        BNE.B   DEQ_SUCCESS                     | no - done
        MOVE.L  A2,qTail(A1)                    | yes - qTail = previous element
        BRA.B   DEQ_SUCCESS                     | return success

| ----------------------------------------------------------
|
| InitQueue - zero a 10-byte queue header (flags + head + tail)
|
| A1 = queue header ptr. Stores zeros at (A1), (A1)+2, (A1)+6;
| leaves A1 pointing to start of header on return.
InitQueue:
        CLR     (A1)+                           | qFlags = 0
        CLR.L   (A1)+                           | qHead = nil
        CLR.L   (A1)                            | qTail = nil
        SUBQ.W  #0x6,A1                         | restore A1 to queue start
        RTS                                     | return from InitQueue
