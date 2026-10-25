| Operating System Event Manager -- _PostEvent, _OSEventAvail, _GetOSEvent, _FlushEvents
|
| Apple source: OSEventMgr.a (MacSEROM.lst module EVENTS). The event queue
| (EventQueue) is kept in a fixed circular buffer of event records
| (SysEvtBuf); PostEvent takes a free record (or the oldest one) and
| enqueues it, OSEventAvail/MMPROLOGUE_ZONE find the highest-priority event
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

| POSTEVENT - _PostEvent trap handler
|
| Entry: A0 = event code (mouseDown=1, mouseUp=2, keyDown=3, etc.)
|        D0 = event message
| Checks SysEvtMask to see if this event type is enabled.
| Apple source module: EVENTS
POSTEVENT:
    MOVE.W	(SysEvtMask).W,D2                    | D2 = system event mask
    MOVE.W	A0,D1                                | D1 = event code
    BTST	D1,D2                                  | event type enabled?
    BNE.B	POSTEVENT_ENABLED                     | yes: post it
    MOVEQ.L	#0x1,D0                             | D0 = 1 (evtNotEnb: not enabled)
    RTS                                         | return without posting
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
    MOVE.W	SR,-(A7)                             | save SR for atomic event posting
    MOVE.L	D0,-(A7)                             | push event message
    MOVE.W	A0,-(A7)                             | push event code (evtNum)
    MOVEA.L	(SysEvtBuf).W,A0                    | A0 = event buffer base
    ADDQ.L	#0x6,A0                              | skip queue header to first evtNum
    MOVEQ.L	#0x16,D0                            | D0 = 22 (event record size)
    MOVEQ.L	#-0x1,D1                            | D1 = -1 (free record marker)
    SUBA.W	D0,A0                                | pre-decrement for loop
    MOVE.W	(EvtBufCnt).W,D2                     | D2 = event buffer capacity
    ORI.W	#0x300,SR                             | raise IPL (atomic search)
| Scan for free event record (evtNum == -1)
POSTEVENT_SCAN_LOOP:
    ADDA.W	D0,A0                                | advance to next event record
    CMP.W	(A0),D1                               | evtNum == -1? (free slot)
    DBEQ.W	D2,POSTEVENT_SCAN_LOOP               | loop until free or exhausted
    LEA.L	(EventQueue).W,A1                     | A1 = event queue header
    BEQ.B	POSTEVENT_FILL                        | found free: fill it
| No free record: steal oldest (dequeue head of EventQueue)
    MOVEA.L	0x2(A1),A0                          | A0 = queue head (oldest event)
    MOVE.L	(A0),0x2(A1)                         | qHead = next event (dequeue head)
    ADDQ.L	#0x6,A0                              | skip queue header to evtNum
| Fill event record with new event data
POSTEVENT_FILL:
    MOVE.W	(A7)+,(A0)                           | evtNum = event code (from stack)
    MOVE.L	(A7)+,0x2(A0)                        | evtMessage = event message
    BSR.B	FILL_EVENT_FIELDS                     | fill timestamp, mouse, modifiers
    SUBQ.L	#0x6,A0                              | back to queue element header
    MOVE.W	#0x4,0x4(A0)                         | qType = evType (4)
    JSR	ENQUEUE(PC)                             | enqueue in EventQueue
    MOVE.W	(A7)+,SR                             | restore SR
    MOVEQ.L	#0x0,D0                             | D0 = noErr (event posted OK)
    RTS                                         | return from _PostEvent
| ----------------------------------------------------------
|
| FILL_EVENT_FIELDS - Fill event record timestamp and modifier fields
| A0 points to evtNum field (event record + 6 bytes past queue header).
| Fills evtTicks, evtMouse (v,h), evtMeta (modifier keys), evtMBut.
|
| Called during boot (32,478 times in 30s trace).
FILL_EVENT_FIELDS:
    MOVE.L	(Ticks).W,0x6(A0)                    | evtTicks = current tick count
    MOVE.L	(Mouse_v).W,0xA(A0)                  | evtMouse = mouse position (v,h)
    MOVE.W	(KeyMap_6).W,D1                      | D1 = high word of KeyMap (modifier byte)
    ROL.W	#0x1,D1                               | rotate so caps-lock is bit 7
    MOVE.B	D1,0xE(A0)                           | evtMeta = modifier-key state byte
    MOVE.B	(MBState).W,0xF(A0)                  | evtMBut = mouse-button state byte
    RTS                                         | return from FILL_EVENT_FIELDS
| ----------------------------------------------------------
|
| _OSEventAvail ($A030) -- check for an event matching D0 mask
|
| Walks the EventQueue looking for an event whose evtNum bit is
| set in the caller's mask in D0. If found, copies it to A0 and
| returns D0=0 (Z set). If not found, may synthesize an autoKey
| event from the held-down key (KbdVers / KeyLast equivalent).
|
| Called from EventAvail trap and indirectly from GetNextEvent.
|
OSEVENTAVAIL:
    LEA.L	(EventQueue).W,A1                     | A1 -> EventQueue header
    MOVE.W	SR,-(A7)                             | save interrupt state
    ORI.W	#0x300,SR                             | mask interrupts during scan
    MOVE.L	0x2(A1),D1                           | D1 = qHead (first EvQEl)
    BEQ.B	OSEVTAVAIL_CHK_AUTOKEY                | empty queue, check auto-key
OSEVTAVAIL_WALK:
    MOVEA.L	D1,A1                               | A1 -> current EvQEl
    MOVE.W	0x6(A1),D1                           | D1 = evtNum
    BTST	D1,D0                                  | event type in caller's mask ?
    BNE.B	OSEVTAVAIL_FOUND                      | yes, return it
    MOVE.L	(A1),D1                              | else D1 = qLink (next)
    BNE.B	OSEVTAVAIL_WALK                       | more, keep scanning
| OSEVTAVAIL_CHK_AUTOKEY -- queue empty or no match; check auto-key repeat
OSEVTAVAIL_CHK_AUTOKEY:
    AND.W	(SysEvtMask).W,D0                     | mask with system event mask
    TST.L	(KbdVers).W                           | any key currently held ?
    BEQ.B	OSEVTAVAIL_NO_EVENT                   | no, return null event
    BTST	#0x5,D0                                | autoKeyEvt enabled in mask ?
    BEQ.B	OSEVTAVAIL_NO_EVENT                   | no, return null event
    MOVE.L	(Ticks).W,D1                         | D1 = current ticks
    MOVE.L	D1,D2                                | D2 = copy for repeat-thresh check
    SUB.L	(KeyTime).W,D1                        | D1 = ticks since key-down
    CMP.W	(KeyThresh).W,D1                      | past initial repeat delay ?
    BLT.B	OSEVTAVAIL_NO_EVENT                   | not yet, return null event
    SUB.L	(KeyRepTime).W,D2                     | D2 = ticks since last repeat
    CMP.W	(KeyRepThresh).W,D2                   | past repeat interval ?
    BLT.B	OSEVTAVAIL_NO_EVENT                   | not yet, return null event
    MOVE.L	(Ticks).W,(KeyRepTime).W             | reset repeat timer
    MOVE.L	A0,-(A7)                             | save caller's event buffer
    MOVEA.W	#0x5,A0                             | A0 = autoKeyEvt code (5)
    MOVEQ.L	#0x0,D0                             | clear D0
    MOVE.L	(KbdVers).W,D0                       | D0 = last key-down message
    BSR.W	POSTEVENT                             | post autoKeyEvt to queue
    MOVEA.L	A0,A1                               | A1 -> just-posted EvQEl
    MOVEA.L	(A7)+,A0                            | restore caller's buffer
OSEVTAVAIL_FOUND:
    MOVE.W	(A7)+,SR                             | restore interrupt state
    MOVEQ.L	#0x4,D0                             | D0 = 4 longs to copy = 16 bytes
    MOVEM.L	A0-A1,-(A7)                         | save buffer / EvQEl pointers
    ADDQ.L	#0x6,A1                              | skip queue header to evtNum field
OSEVTAVAIL_COPY_LOOP:
    MOVE.L	(A1)+,(A0)+                          | copy 4 bytes
    SUBQ.W	#0x1,D0                              | dec loop counter
    BNE.B	OSEVTAVAIL_COPY_LOOP                  | loop 4 times (16 bytes)
    MOVEM.L	(A7)+,A0-A1                         | restore pointers
    RTS                                         | D0 = 0 -> event found (Z set)
| ----------------------------------------------------------
|
| OSEVTAVAIL_NO_EVENT - no matching event: fill buffer with null event, return -1
|
| Called during boot (32,476 times in 30s trace).
OSEVTAVAIL_NO_EVENT:
    BSR.W	FILL_EVENT_FIELDS                     | fill timestamp/mouse/modifiers
    MOVE.W	(A7)+,SR                             | restore interrupt state
    CLR.W	(A0)                                  | evtNum = 0 (nullEvt)
    CLR.L	0x2(A0)                               | evtMessage = 0
    MOVEQ.L	#-0x1,D0                            | D0 = -1 (no event found)
    RTS                                         | return from OSEventAvail
| ----------------------------------------------------------
|
| _GetOSEvent ($A031) -- dequeue + return matching event
|
| D0 = mask. Calls OSEVENTAVAIL to find a matching event, then
| dequeues and invalidates the slot via ADB_DEQUEUE_INVALIDATE.
|
GETOSEVENT:
    BSR.W	OSEVENTAVAIL                          | find matching event
    BNE.B	ADB_DEQUEUE_RTS                       | none found, return as-is
    MOVEA.L	A1,A0                               | A0 -> EvQEl to dequeue
    LEA.L	(EventQueue).W,A1                     | A1 -> EventQueue header
    BSR.B	ADB_DEQUEUE_INVALIDATE                | dequeue + invalidate
    MOVEQ.L	#0x0,D0                             | D0 = 0 (event found, Z set)
ADB_DEQUEUE_RTS:
    RTS                                         | return from MMPROLOGUE_ZONE
| ADB_DEQUEUE_INVALIDATE (DequeueAndInvalidate) -- unlink + mark slot free
ADB_DEQUEUE_INVALIDATE:
    JSR	DEQUEUE(PC)                             | unlink A0 from queue at A1
    MOVE.W	#0xFFFF,0x6(A0)                      | mark evtNum = -1 (free slot)
    RTS                                         | return from ADB_DEQUEUE_INVALIDATE
| ----------------------------------------------------------
|
| _FlushEvents ($A032) -- remove events matching mask
|
| D0.W = eventMask, swapped high word = stopMask.
| Walks EventQueue: dequeue+invalidate any entry whose evtNum
| is in eventMask. Stop early if entry's evtNum is in stopMask.
|
FLUSHEVENTS:
    MOVE.W	SR,-(A7)                             | save interrupt state
    MOVEM.L	D3-D4,-(A7)                         | save D3-D4
    MOVEQ.L	#-0x1,D1                            | D1 = all bits set
    MOVE.L	D1,(LastSPExtra).W                   | invalidate width-table cache
    MOVE.L	D0,D1                                | D1 = full mask|stopMask
    SWAP.W	D1                                   | D1 = stopMask in low word
    MOVE.W	D0,D4                                | D4 = eventMask
    AND.W	(DiskVars_FlEvtMask).W,D4             | mask with floppy event filter
    LEA.L	(EventQueue).W,A1                     | A1 -> EventQueue header
    ORI.W	#0x300,SR                             | mask interrupts during walk
    MOVE.L	0x2(A1),D3                           | D3 = qHead (first EvQEl)
    BEQ.B	FLUSH_QUEUE_EMPTY                     | empty queue, done
FLUSH_WALK_LOOP:
    MOVEA.L	D3,A0                               | A0 -> current EvQEl
    MOVE.L	(A0),D3                              | D3 = qLink (advance)
    MOVE.W	0x6(A0),D2                           | D2 = evtNum
    BTST	D2,D1                                  | in stopMask ?
    BNE.B	FLUSH_EXIT                            | yes, stop and return this evtNum
    BTST	D2,D4                                  | in eventMask ?
    BEQ.B	FLUSH_NEXT_ENTRY                      | no, skip this entry
    BSR.B	ADB_DEQUEUE_INVALIDATE                | yes, dequeue + invalidate
FLUSH_NEXT_ENTRY:
    TST.L	D3                                    | more entries ?
    BNE.B	FLUSH_WALK_LOOP                       | yes, keep walking
FLUSH_QUEUE_EMPTY:
    MOVEQ.L	#0x0,D2                             | reached end, D2 = 0 (no stop hit)
FLUSH_EXIT:
    MOVEM.L	(A7)+,D3-D4                         | restore D3-D4
    MOVE.W	D2,D0                                | D0 = stopMask hit (or 0)
    EXT.L	D0                                    | sign-extend to long
    MOVE.W	(A7)+,SR                             | restore interrupt state
    RTS                                         | return from FlushEvents
