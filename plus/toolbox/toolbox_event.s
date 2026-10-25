| Toolbox Event Manager
|
| Apple source: ToolboxEventMgr.a (MacSEROM.lst module MISCMGR): GetKeys,
| Button, TickCount, GetMouse, StillDown, WaitMouseUp, EventAvail and
| GetNextEvent with the event filtering (TBOX_GET_EVENT / TGEVT_*: update,
| activate and disk events, SystemEvent and the GetNextEvent filter
| GNEFilter), the _Journal dispatcher and SYNTH_ACTIVATE (synthesized
| activate/deactivate events).
|
| Key data structures:
| EventRecord: what(2), message(4), when(4), where(4), modifiers(2)
| WindowRecord: port(GrafPort), windowKind, visible, hilited,
| goAwayFlag, spareFlag, strucRgn, contRgn, updateRgn,
| windowDefProc, dataHandle, titleHandle, titleWidth,
| controlList, nextWindow, windowPic, refCon

| ----------------------------------------------------------
|
| _GetKeys ($A976)
| Pascal: PROCEDURE GetKeys(VAR theKeys: KeyMap)
| Copies the 128-bit keyboard state bitmap into the caller's buffer.
| Each bit corresponds to a key: 1 = pressed, 0 = released.
| After copying, invokes journaling (jcGetKeys = 3) if active.
|
GetKeys:
        MOVE.L  0x4(SP),A1                      | A1 = ptr to caller's KeyMap buffer
        LEA.L   (KeyMap).w,A0                   | A0 = low-mem KeyMap (128 bits = 16 bytes)
        MOVE.L  (A0)+,(A1)+                     | copy bytes 0-3
        MOVE.L  (A0)+,(A1)+                     | copy bytes 4-7
        MOVE.L  (A0)+,(A1)+                     | copy bytes 8-11
        MOVE.L  (A0)+,(A1)+                     | copy bytes 12-15
        MOVE.L  0x4(SP),A1                      | reload result ptr for journaling
        MOVEQ.L #0x3,D1                         | D1 = jcGetKeys (journal code 3)
        BSR.B   JOURNAL_DISPATCH                | invoke journaling if JournalFlag != 0
        MOVE.L  (SP)+,(SP)                      | strip parameter, keep return address
        RTS                                     | return from GetKeys

| ----------------------------------------------------------
|
| _Button ($A974)
| Pascal: FUNCTION Button: BOOLEAN
| Returns TRUE if the mouse button is currently down.
| MBState bit 7 = 1 means button up (hardware active-low);
| bit 7 = 0 (positive or zero) means button down.
|
| Called during boot (28,782 times in 30s trace).
Button:
        LEA.L   0x4(SP),A1                      | A1 = ptr to result word on stack
        CLR     (A1)                            | assume FALSE (button up)
        TST.B   (MBState).w                     | test mouse button state (bit 7)
        BMI.B   BTN_DONE                        | branch if negative = button up
        ADDQ.B  #0x1,(A1)                       | button is down: set result to TRUE
BTN_DONE:
        MOVEQ.L #0x2,D1                         | D1 = jcButton (journal code 2)
        BRA.B   JOURNAL_DISPATCH                | invoke journaling if active

| ----------------------------------------------------------
|
| _TickCount ($A975)
| Pascal: FUNCTION TickCount: LONGINT
| Returns the number of ticks (1/60 sec) since system startup.
|
| Called during boot.
TickCount:
        LEA.L   0x4(SP),A1                      | A1 = ptr to result longword on stack
        MOVE.L  (Ticks).w,(A1)                  | store current tick count
        MOVEQ.L #0x0,D1                         | D1 = jcTickCount (journal code 0)
| ----------------------------------------------------------
| JOURNAL_DISPATCH - Journaling dispatcher
| Shared by GetKeys, Button, TickCount, GetMouse, and event routines.
| If JournalFlag < 0: playback mode (jPlayCtl = 16), reads result from journal driver.
| If JournalFlag > 0: recording mode (jRecordCtl = 17), writes result to journal driver.
| If JournalFlag = 0: no journaling, return immediately.
| On entry: A1 = ptr to data, D1 = journal code, D3 = extra param.
| Issues _Control call to the journal driver (refNum from JournalRef).
JOURNAL_DISPATCH:
        MOVE    (JournalFlag).w,D0              | check journaling state
        BEQ.B   JRNL_RTS                        | zero = no journaling, skip
        BPL.B   JRNL_RECORD                     | positive = recording mode
        MOVEQ.L #0x10,D0                        | negative = playback: csCode = jPlayCtl (16)
        BRA.B   JRNL_CONTROL                    | jump to perform journaling control call

JRNL_RECORD:
        MOVEQ.L #0x11,D0                        | recording: csCode = jRecordCtl (17)
JRNL_CONTROL:
        SUBA    #0x28,SP                        | allocate ioParam block (40 bytes)
        LEA.L   0x18(SP),A0                     | A0 = ptr to csCode field in param block
        MOVE    (JournalRef).w,(A0)+            | ioRefNum = journal driver refNum
        MOVE    D0,(A0)+                        | csCode = jPlayCtl or jRecordCtl
        MOVE.L  A1,(A0)+                        | csParam[0..3] = ptr to data (result buffer)
        MOVE    D1,(A0)+                        | csParam[4..5] = journal code (jcTickCount etc)
        MOVE    D3,(A0)+                        | csParam[6..7] = extra param (EventAvail flag)
        MOVE.L  A7,A0                           | A0 = ptr to ioParam block
        _Control                                | issue synchronous Control call to journal driver
        ADDA    #0x28,SP                        | deallocate ioParam block
        BNE.B   JRNL_DISABLE                    | if error, disable journaling
        RTS                                     | return to journaling dispatcher caller

| Journal driver returned an error - disable journaling
JRNL_DISABLE:
        CLR     (JournalFlag).w                 | clear flag to stop all journaling
        ST.B    (CrsrCouple).w                  | re-couple cursor to mouse position
JRNL_RTS:
        RTS                                     | return after disabling journaling

| ----------------------------------------------------------
|
| _GetMouse ($A972)
| Pascal: PROCEDURE GetMouse(VAR mouseLoc: Point)
| Returns the current mouse position in local coordinates of
| the current GrafPort. Reads global coords from Mouse_v/Mouse_h,
| journals if active, then converts to local via GlobalToLocal.
|
| Called during boot (61,253 times in 30s trace).
GetMouse:
        MOVE.L  0x4(SP),A1                      | A1 = ptr to caller's Point
        MOVE.L  (Mouse_v).w,(A1)                | copy global mouse position (v,h packed)
        MOVEQ.L #0x1,D1                         | D1 = jcGetMouse (journal code 1)
        BSR.B   JOURNAL_DISPATCH                | invoke journaling if active
        MOVE.L  0x4(SP),-(SP)                   | push ptr to Point for GlobalToLocal
        _GlobalToLocal                          | convert global coords to local
        MOVE.L  (SP)+,(SP)                      | strip parameter, keep return address
        RTS                                     | return from GetMouse

| ----------------------------------------------------------
|
| _StillDown ($A973)
| Pascal: FUNCTION StillDown: BOOLEAN
| Returns TRUE only if the mouse button is still held down AND no
| mouse-up event (bit 2 = mouseUp=2, bit 1 = mouseDown=1, bit 0 = null;
| mask 0x7 = mouseDown+mouseUp+keyDown) is pending in the event queue.
| Used for drag tracking: distinguishes "still holding" from "released
| but mouseUp not yet consumed."
|
| Called during boot (28,782 times in 30s trace).
StillDown:
        LINK    A6,#-0x14                       | allocate 20-byte local EventRecord
        CLR     0x8(A6)                         | clear result (assume FALSE)
        SUBQ.W  #0x2,SP                         | space for Button result
        _Button                                 | is button currently down?
        TST     (SP)+                           | test Button result
        BEQ.B   STILLDN_DONE                    | button up: return FALSE
        SUBQ.W  #0x2,SP                         | space for EventAvail result
        MOVE    #0x7,-(SP)                      | event mask: null+mouseDown+mouseUp+keyDown
        PEA.L   -0x14(A6)                       | ptr to local EventRecord
        _EventAvail                             | peek without removing
        TST     (SP)+                           | any matching event pending?
        BNE.B   STILLDN_DONE                    | yes: mouseUp queued, return FALSE
        ADDQ.B  #0x1,0x8(A6)                    | no pending mouseUp: set result TRUE
STILLDN_DONE:
        UNLK    A6                              | deallocate local EventRecord
        RTS                                     | return from STILLDN_DONE

| ----------------------------------------------------------
|
| _WaitMouseUp ($A977)
| Pascal: FUNCTION WaitMouseUp: BOOLEAN
| Returns TRUE if button is still held. If button was released,
| consumes the pending mouseUp event (mask 0x4 = bit 2 = mouseUp)
| via GetNextEvent so it won't confuse later event processing.
|
| Called during boot (28,782 times in 30s trace).
WaitMouseUp:
        LINK    A6,#-0x14                       | allocate 20-byte local EventRecord
        CLR     -(SP)                           | space for StillDown result
        _StillDown                              | check if button still held, no mouseUp queued
        MOVE    (SP)+,0x8(A6)                   | store result as function return value
        BNE.B   WAITMUP_DONE                    | still down: return TRUE, don't consume
        SUBQ.W  #0x2,SP                         | space for GetNextEvent result
        MOVE    #0x4,-(SP)                      | event mask: mouseUp only (bit 2)
        PEA.L   -0x14(A6)                       | ptr to local EventRecord
        _GetNextEvent                           | consume the mouseUp event from queue
WAITMUP_DONE:
        UNLK    A6                              | deallocate local EventRecord
        RTS                                     | return from WAITMUP_DONE

| ----------------------------------------------------------
|
| _EventAvail ($A971)
| Pascal: FUNCTION EventAvail(eventMask: INTEGER; VAR theEvent: EventRecord): BOOLEAN
| Peeks at the event queue without removing any event.
| Sets D0 = -1 as flag so TBOX_GET_EVENT calls OSEventAvail instead of GetOSEvent.
|
| Called during boot (28,783 times in 30s trace).
EventAvail:
        MOVEQ.L #-0x1,D0                        | D0 < 0 = EventAvail mode (peek only)
        BRA.B   TBOX_GET_EVENT                  | jump to shared event retrieval logic

| ----------------------------------------------------------
|
| _GetNextEvent ($A970)
| Pascal: FUNCTION GetNextEvent(eventMask: INTEGER; VAR theEvent: EventRecord): BOOLEAN
| The main Toolbox event retrieval call. Removes event from queue.
| After TBOX_GET_EVENT does the work, applies the GNEFilter callback (if installed)
| to let system extensions intercept/modify events before the app sees them.
| D0 = 0 flag tells TBOX_GET_EVENT to use GetOSEvent (remove) not OSEventAvail (peek).
|
| Called during boot (3,695 times in 30s trace).
GetNextEvent:
        MOVEM.L (SP)+,D0-D2                     | D0 = return addr, D1 = eventPtr, D2 = mask (pop all)
        SUBQ.W  #0x2,SP                         | allocate space for Boolean result
        MOVE.L  D0,-(SP)                        | push return address back
        MOVE.L  D1,-(SP)                        | push eventPtr param for TBOX_GET_EVENT
        MOVEM.L D1-D2,-(SP)                     | save eventPtr and mask for GNEFilter call
        MOVEQ.L #0x0,D0                         | D0 = 0 = GetNextEvent mode (remove from queue)
        BSR.B   TBOX_GET_EVENT                  | call shared event retrieval logic
        MOVE    (SP)+,D0                        | D0 = Boolean result from TBOX_GET_EVENT
        MOVE.L  (SP)+,A1                        | A1 = eventPtr (for GNEFilter)
        MOVE    D0,0x4(SP)                      | store result in return position
        MOVE.L  (GNEFilter).w,-(SP)             | push GNEFilter proc address
        BNE.B   GNE_CALL_FILTER                 | if non-nil, RTS will jump to filter
        ADDQ.W  #0x4,SP                         | no filter installed: discard nil address
GNE_CALL_FILTER:
        RTS                                     | return (or jump to GNEFilter)

| ----------------------------------------------------------
|
| TBOX_GET_EVENT - Shared Toolbox event retrieval logic
| Used by both GetNextEvent (D3=0) and EventAvail (D3=-1).
| Stack frame: 0x8(A6) = eventPtr, 0xC(A6) = eventMask, 0xE(A6) = result.
|
| Flow:
| 1. On first GetNextEvent after system error, repaint behind alert rect.
| 2. Check for pending activate/deactivate events (SYNTH_ACTIVATE).
| 3. Poll OS Event Manager (GetOSEvent or OSEventAvail).
| 4. If no event and updateEvt bit set in mask, call CheckUpdate.
| 5. For GetNextEvent only: filter through SystemEvent for desk
| accessory dispatch and Cmd-Shift-number FKEY handling.
|
| Called during boot (32,478 times in 30s trace).
TBOX_GET_EVENT:
        LINK    A6,#0x0                         | no locals (result at 0xE(A6) overlaps params)
        MOVEM.L D3/A3,-(SP)                     | save registers
        MOVE.L  D0,D3                           | D3 = mode (0=GetNextEvent, -1=EventAvail)
        BNE.B   TGEVT_BEGIN                     | EventAvail: skip DSWndUpdate cleanup
| --- System error alert cleanup (GetNextEvent only, first call after alert) ---
        BSET    #0x7,(DSWndUpdate).w            | test-and-set "update done" flag
        BNE.B   TGEVT_BEGIN                     | already set: skip repaint
        TST.B   (WWExist).w                     | Window Manager initialized? (0 = yes)
        BNE.B   TGEVT_BEGIN                     | not initialized: skip
        SUBQ.W  #0x4,SP                         | save current GrafPort
        MOVE.L  A7,-(SP)                        | push address of stack for GetPort result
        _GetPort                                | retrieve current graphics port
        MOVE.L  (WMgrPort).w,-(SP)              | switch to Window Manager port
        _SetPort                                | set Window Manager port active
        SUBQ.W  #0x4,SP                         | allocate space for FrontWindow result
        _FrontWindow                            | get front window for PaintBehind start
        SUBQ.W  #0x4,SP                         | allocate space for NewRgn result handle
        _NewRgn                                 | allocate temp region
        MOVE.L  (SP),A3                         | A3 = temp region handle
        PEA.L   (DSAlertRect).w                 | rectangle where system error was drawn
        _RectRgn                                | convert alert rect to region
        MOVE.L  A3,-(SP)                        | pass update region handle to PaintBehind
        _PaintBehind                            | repaint all windows obscured by alert
        MOVE.L  A3,-(SP)                        | pass update region handle to DisposRgn
        _DisposeRgn                             | free temp region
        _SetPort                                | restore saved port
| --- Begin event retrieval ---
TGEVT_BEGIN:
        CLR     0xE(A6)                         | clear result Boolean (no event yet)
        MOVE.L  0x8(A6),A3                      | A3 = ptr to caller's EventRecord
        MOVE    0xC(A6),D0                      | D0 = event mask
        MOVE.L  A3,A0                           | A0 = EventRecord ptr for SYNTH_ACTIVATE
        BSR     SYNTH_ACTIVATE                  | check for pending activate/deactivate
        BEQ.B   TGEVT_POLL_OS                   | none: try OS event queue
        ADDQ.B  #0x1,0xE(A6)                    | activate event found: set result TRUE
        BRA.B   TGEVT_SYSEVT                    | skip to SystemEvent filtering

| --- Poll the OS Event Manager queue ---
TGEVT_POLL_OS:
        MOVE    0xC(A6),D0                      | reload event mask
        MOVE.L  A3,A0                           | A0 = EventRecord ptr
        TST     D3                              | EventAvail or GetNextEvent?
        BPL.B   TGEVT_GET_OS                    | D3 >= 0: GetNextEvent (remove)
        _OSEventAvail                           | peek at queue without removing
        BRA.B   TGEVT_JOURNAL                   | skip over event removal

TGEVT_GET_OS:
        _GetOSEvent                             | remove next matching event from queue
TGEVT_JOURNAL:
        MOVE.L  A3,A1                           | A1 = EventRecord ptr for journaling
        MOVEQ.L #0x4,D1                         | D1 = jcEvent (journal code 4)
        BSR     JOURNAL_DISPATCH                | journal the event if journaling active
        TST     (A3)                            | test evtNum: null event (0)?
        BEQ.B   TGEVT_CHK_UPDATE                | null: no real event from queue
        ADDQ.B  #0x1,0xE(A6)                    | real event: set result TRUE
        BRA.B   TGEVT_SYSEVT                    | proceed to SystemEvent filtering

| --- No event from queue; check for pending window updates ---
TGEVT_CHK_UPDATE:
        MOVE    0xC(A6),D0                      | reload event mask
        BTST    #0x6,D0                         | bit 6 = updateEvt in mask?
        BEQ.B   TGEVT_SYSEVT                    | update events not requested: skip
        CLR     -(SP)                           | space for CheckUpdate result
        MOVE.L  A3,-(SP)                        | push EventRecord ptr
        _CheckUpDate                            | synthesize updateEvt if window needs redraw
        MOVE    (SP)+,0xE(A6)                   | store result (TRUE if update found)
| --- SystemEvent filtering (GetNextEvent only) ---
| Intercepts events destined for desk accessories and handles
| Cmd-Shift-number key combos (FKEY resources).
TGEVT_SYSEVT:
        TST     D3                              | EventAvail mode?
        BMI.B   TGEVT_CLEANUP                   | yes: skip all filtering, return as-is
        TST     0xE(A6)                         | did we get an event?
        BEQ.B   TGEVT_CLEANUP                   | no event: skip to cleanup
        TST.B   (SEvtEnb).w                     | system event filtering enabled?
        BEQ.B   TGEVT_CHK_FKEY                  | disabled: skip SystemEvent, try FKEY
        SUBQ.W  #0x2,SP                         | space for SystemEvent result
        MOVE.L  A3,-(SP)                        | push EventRecord ptr
        _SystemEvent                            | check if DA or system should handle event
        TST     (SP)+                           | system consumed the event?
        BNE.B   TGEVT_CLR_RESULT                | yes: clear result, don't report to app
| --- FKEY (Cmd-Shift-number) handling ---
| Checks for keyDown/autoKey with Cmd+Shift held and digit key 0-9.
| evtMeta byte: bit 0=shiftKey, bit 1=alphaLock, bit 3=cmdKey.
| Test (evtMeta & 0x0B) == 0x03: cmdKey + shiftKey both set.
TGEVT_CHK_FKEY:
        MOVEQ.L #0xB,D1                         | mask: bits 0,1,3 (shift+alpha+cmd)
        AND.B   0xE(A3),D1                      | D1 = evtMeta & 0x0B
        SUBQ.B  #0x3,D1                         | test for Cmd+Shift (0x03)
        BNE.B   TGEVT_CLEANUP                   | modifiers don't match: return to app
        MOVE.B  0x5(A3),D1                      | D1 = virtual key code from evtMessage byte 3
        CMPI.B  #0xA,D1                         | key code >= 10?
        BCC.B   TGEVT_CLEANUP                   | not digit 0-9: return to app
        MOVE    (A3),D0                         | D0 = evtNum (event type)
        SUBQ.W  #0x4,D0                         | subtract 4: autoKey(5)->1, keyDown(3)->-1
        BEQ.B   TGEVT_SWALLOW                   | autoKey: swallow without re-running FKEY
        ADDQ.W  #0x1,D0                         | keyDown(3): -1+1=0
        BNE.B   TGEVT_CLEANUP                   | not keyDown or autoKey: return to app
| --- Execute FKEY resource for Cmd-Shift-N ---
        SUBQ.W  #0x4,SP                         | space for GetResource result handle
        MOVE.L  #0x464B4559,-(SP)               | push resource type 'FKEY'
        MOVE    D1,-(SP)                        | push resource ID (digit 0-9)
        _GetResource                            | load FKEY resource
        MOVE.L  (SP)+,D0                        | D0 = resource handle (or NIL)
        BNE.B   TGEVT_RUN_FKEY                  | found: execute FKEY code
| --- No FKEY resource; handle built-in Cmd-Shift-1/2 (disk eject) ---
        TST     D1                              | key 0?
        BEQ.B   TGEVT_SWALLOW                   | Cmd-Shift-0: just swallow
        CMPI    #0x2,D1                         | key > 2?
        BGT.B   TGEVT_SWALLOW                   | Cmd-Shift-3..9 with no FKEY: swallow
        MOVEQ.L #0x1,D2                         | D2 = drive number (1 for internal)
        JSR     (0x40001E).l                    | call Sony eject routine in RAM
        BRA.B   TGEVT_SWALLOW                   | swallow the key event

| --- Execute FKEY code resource ---
TGEVT_RUN_FKEY:
        MOVE.L  D0,A0                           | A0 = FKEY resource handle
        MOVE.L  (A0),D0                         | dereference: D0 = master pointer
        BEQ.B   TGEVT_SWALLOW                   | nil ptr (purged resource): skip
        BSET    #0x7,(A0)                       | lock handle (set high bit of master ptr)
        MOVE.L  A0,-(SP)                        | save handle
        MOVE.L  (A0),A0                         | A0 = ptr to FKEY executable code
        JSR     (A0)                            | execute the FKEY
        MOVE.L  (SP)+,A0                        | restore handle
        BCLR    #0x7,(A0)                       | unlock handle
| --- Swallow event (consumed by system or FKEY) ---
TGEVT_SWALLOW:
        CLR     (A3)                            | set evtNum = nullEvt (0), event consumed
TGEVT_CLR_RESULT:
        CLR     0xE(A6)                         | clear result: no event for application
| --- Cleanup and return ---
TGEVT_CLEANUP:
        TST     (A3)                            | still a null event after processing?
        BNE.B   TGEVT_RETURN                    | real event remains: skip idle tracking
        PEA.L   (scratch8).w                    | push scratch point address
        _GetMouse                               | track mouse position during null-event idle
TGEVT_RETURN:
        MOVEM.L (SP)+,D3/A3                     | restore saved registers
        UNLK    A6                              | deallocate stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip params (eventMask + eventPtr = 6 bytes)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| SYNTH_ACTIVATE - Synthesize activate/deactivate events
| Checks CurActivate and CurDeactive for pending window activation changes.
| If a window needs activation or deactivation, builds an activateEvt (8)
| in the EventRecord at (A3). The modifiers encode:
| bit 0 (activeFlag): 1 = activating, 0 = deactivating
| bit 2 (changeFlag): 1 = windowKind differs between old and new
| (i.e., switching between DA and app window)
| For GetNextEvent (D3=0), marks the window as "consumed" by setting
| bit 7 of CurActivate or CurDeactive pointer (lock flag).
| Returns: D1 = -1 if event synthesized, D1 = 0 if nothing pending.
|
| Called during boot (32,478 times in 30s trace).
SYNTH_ACTIVATE:
        BTST    #0x8,D0                         | bit 8 in event mask = activateEvt?
        BEQ.B   SACT_NO_EVENT                   | not requested: return no event
        MOVE.L  (CurDeactive).w,D1              | D1 = window needing deactivation
        BGT.B   SACT_DO_DEACT                   | valid ptr (positive): deactivate first
        MOVE.L  (CurActivate).w,D1              | D1 = window needing activation
        BLE.B   SACT_NO_EVENT                   | no pending activation: return no event
        MOVEQ.L #0x1,D2                         | D2 = modifiers: bit 0 = activeFlag (activating)
| --- Build the activateEvt in EventRecord ---
SACT_BUILD_EVT:
        MOVEQ.L #0x0,D0                         | mask = 0: peek with no event type filter
        _OSEventAvail                           | A0 = ptr to EventRecord in queue (or empty)
        MOVE    #0x8,(A0)+                      | evtNum = activateEvt (8)
        MOVE.L  D1,(A0)                         | evtMessage = window pointer
| --- Check if switching between DA and app window (changeFlag) ---
        MOVE.L  (CurDeactive).w,D0              | D0 = deactivating window
        BEQ.B   SACT_SET_MODS                   | no deactivation: skip changeFlag
        MOVE    (CurDeKind).w,D0                | D0 = windowKind of deactivating window
        MOVE.L  (CurActivate).w,D1              | D1 = activating window
        BEQ.B   SACT_SET_MODS                   | no activation: skip changeFlag
        MOVE.L  D1,A0                           | A0 = activating WindowPtr
        MOVE    windowKind(A0),D1               | D1 = windowKind of activating window
        EOR     D0,D1                           | XOR: sign bit set if kinds differ in sign
        BPL.B   SACT_SET_MODS                   | same sign (both app or both DA): no change
        ADDQ.W  #0x2,D2                         | set bit 1 (changeFlag) in modifiers
SACT_SET_MODS:
        MOVE    0xE(A3),D0                      | D0 = existing modifiers in EventRecord
        ANDI    #-0x4,D0                        | clear bits 0-1 (activeFlag + changeFlag)
        OR      D2,D0                           | merge in new activeFlag and changeFlag
        MOVE    D0,0xE(A3)                      | store updated modifiers
        TST     D3                              | GetNextEvent mode?
        BNE.B   SACT_HAS_EVENT                  | EventAvail: don't consume, just report
        LSR     #0x1,D0                         | shift bit 0 (activeFlag) into carry
        BCC.B   SACT_MARK_DEACT                 | carry clear = deactivating: mark CurDeactive
        BSET    #0x7,(CurActivate).w            | mark activate as consumed (set lock bit)
SACT_HAS_EVENT:
        MOVEQ.L #-0x1,D1                        | return -1: event synthesized (NE condition)
        RTS                                     | return from SACT_HAS_EVENT

| No pending activate/deactivate events
SACT_NO_EVENT:
        MOVEQ.L #0x0,D1                         | return 0: no event (EQ condition)
        RTS                                     | return from SACT_NO_EVENT

| Mark deactivate as consumed
SACT_MARK_DEACT:
        BSet    #0x7,(CurDeactive).w            | set lock bit on CurDeactive ptr
        BRA.B   SACT_HAS_EVENT                  | return -1: event synthesized

| Deactivation pending: start with deactivate (activeFlag = 0)
SACT_DO_DEACT:
        CLR     D2                              | D2 = 0: modifiers with activeFlag clear
        BRA.B   SACT_BUILD_EVT                  | go build deactivate event

