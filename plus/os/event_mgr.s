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
|
| _PostEvent ($A02F)
| A0 = event number (0-15), D0 = event message -> D0 = error
| Posts an event to the system event queue if the event type is
| enabled in SysEvtMask. Returns evtNotEnb (1) if event masked out.
|
| Called during boot.
PostEvent:
        MOVE    (SysEvtMask).w,D2               | D2 = system event mask (bit per event type)
        MOVE    A0,D1                           | D1 = event number
        BTST    D1,D2                           | is this event type enabled?
        BNE.B   POSTEVENT_ENABLED               | yes -> post it
        MOVEQ.L #0x1,D0                         | D0 = 1 (evtNotEnb: event not enabled)
        RTS                                     | return from PostEvent

| ----------------------------------------------------------
|
| POSTEVENT_ENABLED - event is enabled, find a free event record and enqueue it
| Event records are in a circular buffer (SysEvtBuf). Each record is
| 22 bytes: 6-byte queue header + 16-byte event data (evtNum, evtMessage,
| evtTicks, evtMouse, evtMeta, evtMBut).
| Searches for a "free" record (evtNum = -1). If none free, steals the
| oldest event from queue head.
|
| Called during boot.
POSTEVENT_ENABLED:
        MOVE    SR,-(SP)                        | save interrupt state
        MOVE.L  D0,-(SP)                        | save event message on stack
        MOVE    A0,-(SP)                        | save event number on stack
        MOVE.L  (SysEvtBuf).w,A0                | A0 = event buffer base
        ADDQ.L  #0x6,A0                         | skip queue header to first evtNum field
        MOVEQ.L #0x16,D0                        | D0 = 22 = event record size
        MOVEQ.L #-0x1,D1                        | D1 = -1 (marker for free event record)
        SUBA    D0,A0                           | pre-decrement for loop (ADDA first in loop)
        MOVE    (EvtBufCnt).w,D2                | D2 = number of event buffer slots
        ORI     #0x100,SR                       | disable interrupts during queue manipulation
POSTEVENT_SCAN_LOOP:
        ADDA    D0,A0                           | advance to next event record's evtNum
        CMP     (A0),D1                         | evtNum == -1? (free slot)
        DBEQ    D2,POSTEVENT_SCAN_LOOP          | loop until free slot found or all checked
        LEA.L   (EventQueue).w,A1               | A1 = event queue header
        BEQ.B   POSTEVENT_FILL                  | found free slot -> use it
| No free slot: steal oldest event from queue head
        MOVE.L  0x2(A1),A0                      | A0 = queue head element (oldest event)
        MOVE.L  (A0),0x2(A1)                    | dequeue: head = head->qLink
        ADDQ.L  #0x6,A0                         | A0 past queue header to evtNum field
POSTEVENT_FILL:
| Fill in the event record
        MOVE    (SP)+,(A0)                      | store evtNum (event number)
        MOVE.L  (SP)+,0x2(A0)                   | store evtMessage
        BSR.B   FILL_EVENT_FIELDS               | fill evtTicks, evtMouse, evtMeta, evtMBut
        SUBQ.L  #0x6,A0                         | back up to queue element header
        MOVE    #0x4,0x4(A0)                    | qType = evType (4)
        JSR     Enqueue(PC)                     | add to EventQueue (at tail)
        MOVE    (SP)+,SR                        | restore interrupt state
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | return from POSTEVENT_FILL

| ----------------------------------------------------------
|
| FILL_EVENT_FIELDS - Fill event record timestamp and modifier fields
| A0 points to evtNum field (event record + 6 bytes past queue header).
| Fills evtTicks, evtMouse (v,h), evtMeta (modifier keys), evtMBut.
|
| Called during boot (32,478 times in 30s trace).
FILL_EVENT_FIELDS:
        MOVE.L  (Ticks).w,0x6(A0)               | evtTicks = current tick count
        MOVE.L  (Mouse_v).w,0xA(A0)             | evtMouse = mouse position (v,h)
        MOVE    (KeyMap_6).w,D1                 | D1 = modifier key bits from KeyMap byte 12-13
        ROL     #0x1,D1                         | rotate: align modifier bits for evtMeta format
        MOVE.B  D1,0xE(A0)                      | evtMeta = modifier key state byte
        MOVE.B  (MBState).w,0xF(A0)             | evtMBut = mouse button state
        RTS                                     | return from FILL_EVENT_FIELDS

| ----------------------------------------------------------
|
| _OSEventAvail ($A030)
| D0 = event mask (bit per event type), A0 = event record buffer ->
| D0 = 0 if event found (copied to buffer), D0 = -1 if no matching event.
| Peeks at the event queue without dequeuing. Also generates auto-key
| repeat events (autoKeyEvt=5) when a key is held past KeyThresh ticks.
|
| Called during boot (32,478 times in 30s trace).
OSEventAvail:
        LEA.L   (EventQueue).w,A1               | A1 = event queue header
        MOVE    SR,-(SP)                        | save interrupt state
        ORI     #0x100,SR                       | disable interrupts during queue scan
        MOVE.L  0x2(A1),D1                      | D1 = queue head (first event element)
        BEQ.B   OSEVTAVAIL_CHK_AUTOKEY          | queue empty -> check auto-key repeat
OSEVTAVAIL_WALK:
| Walk the event queue looking for an event matching the caller's mask
        MOVE.L  D1,A1                           | A1 = current queue element
        MOVE    dCtlQueue(A1),D1                | D1 = evtNum (at offset 6 in queue element)
        BTST    D1,D0                           | is this event type in caller's mask?
        BNE.B   OSEVTAVAIL_FOUND                | yes -> return this event
        MOVE.L  (A1),D1                         | D1 = qLink (next element)
        BNE.B   OSEVTAVAIL_WALK                 | more elements -> keep searching
OSEVTAVAIL_CHK_AUTOKEY:
| No matching event found; check if auto-key repeat should fire
        AND     (SysEvtMask).w,D0               | mask with system event mask
        TST     (KeyLast).w                     | any key held down?
        BEQ.B   OSEVTAVAIL_NO_EVENT             | no -> return "no event"
        BTST    #0x5,D0                         | bit 5 = autoKeyEvt enabled in mask?
        BEQ.B   OSEVTAVAIL_NO_EVENT             | auto-key not requested -> no event
        MOVE.L  (Ticks).w,D1                    | D1 = current tick count
        MOVE.L  D1,D2                           | D2 = copy for repeat threshold check
        SUB.L   (KeyTime).w,D1                  | D1 = ticks since initial key-down
        CMP     (KeyThresh).w,D1                | past initial repeat delay?
        BLT.B   OSEVTAVAIL_NO_EVENT             | not yet -> no auto-key event
        SUB.L   (KeyRepTime).w,D2               | D2 = ticks since last repeat event
        CMP     (KeyRepThresh).w,D2             | past repeat interval?
        BLT.B   OSEVTAVAIL_NO_EVENT             | not yet -> no auto-key event
| Generate auto-key repeat event
        MOVE.L  (Ticks).w,(KeyRepTime).w        | reset repeat timer
        MOVE.L  A0,-(SP)                        | save caller's event record buffer
        MOVE    #0x5,A0                         | A0 = autoKeyEvt (event code 5)
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (KeyLast).w,D0                  | D0 = last key-down message (keyCode|charCode)
        BSR     PostEvent                       | post autoKeyEvt to event queue
        MOVE.L  A0,A1                           | A1 = the just-posted event element
        MOVE.L  (SP)+,A0                        | restore caller's event record buffer
OSEVTAVAIL_FOUND:
| Found (or generated) a matching event; copy 16-byte event record to buffer
        MOVE    (SP)+,SR                        | restore interrupt state
        MOVEQ.L #0x4,D0                         | D0 = 4 (loop count: 4 longs = 16 bytes)
        MOVEM.L A0-A1,-(SP)                     | save buffer and element pointers
        ADDQ.L  #0x6,A1                         | skip queue header to evtNum field
OSEVTAVAIL_COPY_LOOP:
        MOVE.L  (A1)+,(A0)+                     | copy 4 bytes of event record
        SUBQ.W  #0x1,D0                         | decrement loop counter
        BNE.B   OSEVTAVAIL_COPY_LOOP            | loop 4 times (16 bytes total)
        MOVEM.L (SP)+,A0-A1                     | restore pointers
        RTS                                     | D0 = 0 (event found)

| ----------------------------------------------------------
|
| OSEVTAVAIL_NO_EVENT - no matching event: fill buffer with null event, return -1
|
| Called during boot (32,476 times in 30s trace).
OSEVTAVAIL_NO_EVENT:
        BSR     FILL_EVENT_FIELDS               | fill null event with current timestamp/modifiers
        MOVE    (SP)+,SR                        | restore interrupt state
        CLR     (A0)                            | evtNum = 0 (nullEvt)
        CLR.L   0x2(A0)                         | evtMessage = 0
        MOVEQ.L #-0x1,D0                        | D0 = -1 (no event found)
        RTS                                     | return from OSEVTAVAIL_NO_EVENT

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
| Toolbox trap $A832 dispatches here as well (MacPlusROM.lst: Trap1_32):
| in the 64K ROM, OS and Toolbox traps shared one dispatch table,
| so $A832 and $A032 were the same slot.
FlushEvents:
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

