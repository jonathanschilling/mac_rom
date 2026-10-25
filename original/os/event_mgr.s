| Operating System Event Manager -- _PostEvent, _OSEventAvail, _GetOSEvent, _FlushEvents
|
| Apple source: OSEventMgr.a (MacSEROM.lst module EVENTS). The event queue
| (EventQueue) is kept in a fixed circular buffer of event records
| (SysEvtBuf); PostEvent takes a free record (or the oldest one) and
| enqueues it, OSEventAvail/GetOSEvent find the highest-priority event
| matching a mask, FlushEvents removes events.
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
| References: Inside Macintosh Vol II, Ch 3 (The Operating System Event
| Manager).

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
| GetOSEvent -- _GetOSEvent ($A031).
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
| DEQUEUE_INVALIDATE -- remove an event from the queue and mark its slot free
| Remove EvQEl from queue and mark slot evtQWhat = -1 (free).
DEQUEUE_INVALIDATE:
        JSR     Dequeue(PC)                     | unlink A0 from queue at A1
        MOVE    #-0x1,6(A0)                     | mark slot free (evtQWhat = -1)
        RTS                                     | return after dequeue + invalidate

| ----------------------------------------------------------
| _FlushEvents ($A032): remove events from the event queue
| Pascal: PROCEDURE FlushEvents(eventMask, stopMask: INTEGER);
| Entry: D0.W = eventMask, D0 high word = stopMask
| Exit:  D0 = event code of the event that stopped the flush, else 0
| At IPL 1, walks the queue from the head, removing every event whose
| type is in eventMask, up to the first event whose type is in
| stopMask (that one stays queued).
FlushEvents:
        MOVE    SR,-(SP)                        | save SR (restored by the RTE)
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
