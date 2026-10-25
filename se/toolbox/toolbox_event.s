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
| Apple source module: MISCMGR
GETKEYS:
    MOVEA.L     0x4(A7),A1                      | A1 = ptr to caller's KeyMap buffer
    LEA.L       (KeyMap).W,A0                   | A0 = low-mem KeyMap (128 bits = 16 bytes)
    MOVE.L      (A0)+,(A1)+                     | copy bytes 0-3
    MOVE.L      (A0)+,(A1)+                     | copy bytes 4-7
    MOVE.L      (A0)+,(A1)+                     | copy bytes 8-11
    MOVE.L      (A0)+,(A1)+                     | copy bytes 12-15
    MOVEA.L     0x4(A7),A1                      | reload result ptr for journaling
    MOVEQ.L     #0x3,D1                         | D1 = jcGetKeys (journal code 3)
    BSR.B       JOURNAL_DISPATCH                | invoke journaling if JournalFlag != 0
    MOVE.L      (A7)+,(A7)                      | strip parameter, keep return address
    RTS                                         | return from GetKeys
| ----------------------------------------------------------
|
| _Button ($A974)
| Pascal: FUNCTION Button: BOOLEAN
| Returns TRUE if the mouse button is currently down.
| MBState bit 7 = 1 means button up (hardware active-low);
| bit 7 = 0 (positive or zero) means button down.
|
BUTTON:
    LEA.L       0x4(A7),A1                      | A1 = ptr to result word on stack
    CLR.W       (A1)                            | assume FALSE (button up)
    TST.B       (MBState).W                     | test mouse button state (bit 7)
    BMI.B       BTN_DONE                        | branch if negative = button up
    ADDQ.B      #0x1,(A1)                       | button is down: set result to TRUE
BTN_DONE:
    MOVEQ.L     #0x2,D1                         | D1 = jcButton (journal code 2)
    BRA.B       JOURNAL_DISPATCH                | invoke journaling if active
| ----------------------------------------------------------
|
| _TickCount ($A975)
| Pascal: FUNCTION TickCount: LONGINT
| Returns the number of ticks (1/60 sec) since system startup.
|
TICKCOUNT:
    LEA.L       0x4(A7),A1                      | A1 = ptr to result longword on stack
    MOVE.L      (Ticks).W,(A1)                  | store current tick count
    MOVEQ.L     #0x0,D1                         | D1 = jcTickCount (journal code 0)
| ----------------------------------------------------------
| JOURNAL_DISPATCH - Journaling dispatcher
| Shared by GetKeys, Button, TickCount, GetMouse, and event routines.
| If JournalFlag < 0: playback mode (jPlayCtl = 16), reads result from journal driver.
| If JournalFlag > 0: recording mode (jRecordCtl = 17), writes result to journal driver.
| If JournalFlag = 0: no journaling, return immediately.
| On entry: A1 = ptr to data, D1 = journal code, D3 = extra param.
| Issues _Control call to the journal driver (refNum from JournalRef).
JOURNAL_DISPATCH:
    MOVE.W      (JournalFlag).W,D0              | check journaling state
    BEQ.B       JRNL_RTS                        | zero = no journaling, skip
    BPL.B       JRNL_RECORD                     | positive = recording mode
    MOVEQ.L     #0x10,D0                        | negative = playback: csCode = jPlayCtl (16)
    BRA.B       JRNL_CONTROL                    | jump to perform journaling control call
JRNL_RECORD:
    MOVEQ.L     #0x11,D0                        | recording: csCode = jRecordCtl (17)
JRNL_CONTROL:
    SUBA.W      #0x28,A7                        | allocate ioParam block (40 bytes)
    LEA.L       0x18(A7),A0                     | A0 = ptr to csCode field in param block
    MOVE.W      (JournalRef).W,(A0)+            | ioRefNum = journal driver refNum
    MOVE.W      D0,(A0)+                        | csCode = jPlayCtl or jRecordCtl
    MOVE.L      A1,(A0)+                        | csParam[0..3] = ptr to data (result buffer)
    MOVE.W      D1,(A0)+                        | csParam[4..5] = journal code
    MOVE.W      D3,(A0)+                        | csParam[6..7] = extra param (EventAvail flag)
    MOVEA.L     A7,A0                           | A0 = ptr to ioParam block
    _Control                                    | issue synchronous Control to journal driver
    ADDA.W      #0x28,A7                        | deallocate ioParam block
    BNE.B       JRNL_DISABLE                    | if error, disable journaling
    RTS                                         | return from JRNL_CONTROL
| Journal driver returned an error - disable journaling
JRNL_DISABLE:
    CLR.W       (JournalFlag).W                 | clear flag to stop all journaling
    ST.B        (CrsrCouple).W                  | re-couple cursor to mouse position
JRNL_RTS:
    RTS                                         | return from JRNL_RTS
| ----------------------------------------------------------
|
| _GetMouse ($A972)
| Pascal: PROCEDURE GetMouse(VAR mouseLoc: Point)
| Returns the current mouse position in local coordinates of
| the current GrafPort. Reads global coords from Mouse_v/Mouse_h,
| journals if active, then converts to local via GlobalToLocal.
|
GETMOUSE:
    MOVEA.L     0x4(A7),A1                      | A1 = ptr to caller's Point
    MOVE.L      (Mouse_v).W,(A1)                | copy global mouse position (v,h packed)
    MOVEQ.L     #0x1,D1                         | D1 = jcGetMouse (journal code 1)
    BSR.B       JOURNAL_DISPATCH                | invoke journaling if active
    MOVE.L      0x4(A7),-(A7)                   | push ptr to Point for GlobalToLocal
    _GlobalToLocal                              | convert global coords to local
    MOVE.L      (A7)+,(A7)                      | strip parameter, keep return address
    RTS                                         | return from GetMouse
| ----------------------------------------------------------
|
| _StillDown ($A973)
| Pascal: FUNCTION StillDown: BOOLEAN
| Returns TRUE only if mouse button still held AND no mouse-up event
| (mask 0x7 = mouseDown+mouseUp+null+keyDown) is pending in the queue.
|
STILLDOWN:
    LINK        A6,#-0x14                       | allocate 20-byte local EventRecord
    CLR.W       0x8(A6)                         | clear result (assume FALSE)
    SUBQ.W      #0x2,A7                         | space for Button result
    _Button                                     | is button currently down?
    TST.W       (A7)+                           | test Button result
    BEQ.B       STILLDN_DONE                    | button up: return FALSE
    SUBQ.W      #0x2,A7                         | space for EventAvail result
    MOVE.W      #0x7,-(A7)                      | event mask: null+mouseDown+mouseUp+keyDown
    PEA.L       -0x14(A6)                       | ptr to local EventRecord
    _EventAvail                                 | peek without removing
    TST.W       (A7)+                           | any matching event pending?
    BNE.B       STILLDN_DONE                    | yes: mouseUp queued, return FALSE
    ADDQ.B      #0x1,0x8(A6)                    | no pending mouseUp: set result TRUE
STILLDN_DONE:
    UNLK        A6                              | deallocate local EventRecord
    RTS                                         | return from STILLDN_DONE
| ----------------------------------------------------------
|
| _WaitMouseUp ($A977)
| Pascal: FUNCTION WaitMouseUp: BOOLEAN
| Returns TRUE if button still held. If button was released, consumes
| the pending mouseUp event (mask 0x4) via GetNextEvent.
|
WAITMOUSEUP:
    LINK        A6,#-0x14                       | allocate 20-byte local EventRecord
    CLR.W       -(A7)                           | space for StillDown result
    _StillDown                                  | check if button still held
    MOVE.W      (A7)+,0x8(A6)                   | store result as function return value
    BNE.B       WAITMUP_DONE                    | still down: return TRUE, don't consume
    SUBQ.W      #0x2,A7                         | space for GetNextEvent result
    MOVE.W      #0x4,-(A7)                      | event mask: mouseUp only (bit 2)
    PEA.L       -0x14(A6)                       | ptr to local EventRecord
    _GetNextEvent                               | consume the mouseUp event from queue
WAITMUP_DONE:
    UNLK        A6                              | deallocate local EventRecord
    RTS                                         | return from WAITMUP_DONE
| ----------------------------------------------------------
|
| _EventAvail ($A971)
| Sets D0 = -1 so TBOX_GET_EVENT calls OSEventAvail (peek).
|
EVENTAVAIL:
    MOVEQ.L     #-0x1,D0                        | D0 < 0 = EventAvail mode (peek only)
    BRA.B       TBOX_GET_EVENT                  | jump to shared event retrieval logic
| ----------------------------------------------------------
|
| _GetNextEvent ($A970)
| Main Toolbox event retrieval; removes event from queue.
| Applies GNEFilter callback (if installed) before returning.
|
GETNEXTEVENT:
    MOVEM.L     (A7)+,D0-D2                     | D0=ret addr, D1=eventPtr, D2=mask (pop all)
    SUBQ.W      #0x2,A7                         | allocate space for Boolean result
    MOVE.L      D0,-(A7)                        | push return address back
    MOVE.L      D1,-(A7)                        | push eventPtr param for TBOX_GET_EVENT
    MOVEM.L     D1-D2,-(A7)                     | save eventPtr and mask for GNEFilter call
    MOVEQ.L     #0x0,D0                         | D0 = 0 = GetNextEvent mode (remove)
    BSR.B       TBOX_GET_EVENT                  | call shared event retrieval logic
    MOVE.W      (A7)+,D0                        | D0 = Boolean result from TBOX_GET_EVENT
    MOVEA.L     (A7)+,A1                        | A1 = eventPtr (for GNEFilter)
    MOVE.W      D0,0x4(A7)                      | store result in return position
    MOVE.L      (GNEFilter).W,-(A7)             | push GNEFilter proc address
    BNE.B       GNE_CALL_FILTER                 | if non-nil, RTS will jump to filter
    ADDQ.W      #0x4,A7                         | no filter installed: discard nil address
GNE_CALL_FILTER:
    RTS                                         | return (or jump to GNEFilter)
| ----------------------------------------------------------
|
| TBOX_GET_EVENT - Shared Toolbox event retrieval logic
| Used by both GetNextEvent (D3=0) and EventAvail (D3=-1).
| Stack frame: 0x8(A6) = eventPtr, 0xC(A6) = eventMask, 0xE(A6) = result.
|
| Flow:
| 1. On first GetNextEvent after system error, repaint behind alert rect.
| 2. Check for pending activate/deactivate events (SYNTH_ACTIVATE).
| 3. Poll OS Event Manager (MMPROLOGUE_ZONE or OSEventAvail).
| 4. If no event and updateEvt bit set in mask, call CheckUpDate.
| 5. For GetNextEvent only: filter through SystemEvent for desk
| accessory dispatch and Cmd-Shift-number FKEY handling.
|
| Called during boot (32,478 times in 30s trace).
TBOX_GET_EVENT:
    LINK        A6,#0x0                         | no locals (result at 0xE(A6) overlaps params)
    MOVEM.L     D3/A3,-(A7)                     | save registers
    MOVE.L      D0,D3                           | D3 = mode (0=GetNextEvent, -1=EventAvail)
    BNE.B       TGEVT_BEGIN                     | EventAvail: skip DSWndUpdate cleanup
| --- System error alert cleanup (GetNextEvent only, first call after alert) ---
    BSET        #0x7,(DSWndUpdate)              | test-and-set "update done" flag
    BNE.B       TGEVT_BEGIN                     | already set: skip repaint
    TST.B       (WWExist).W                     | Window Manager initialized? (0 = yes)
    BNE.B       TGEVT_BEGIN                     | not initialized: skip
    SUBQ.W      #0x4,A7                         | save current GrafPort
    MOVE.L      A7,-(A7)                        | push address of stack for GetPort result
    _GetPort                                    | retrieve current graphics port
    MOVE.L      (WMgrPort).W,-(A7)              | switch to Window Manager port
    _SetPort                                    | set Window Manager port active
    SUBQ.W      #0x4,A7                         | allocate space for FrontWindow result
    _FrontWindow                                | get front window for PaintBehind start
    SUBQ.W      #0x4,A7                         | allocate space for NewRgn result handle
    _NewRgn                                     | allocate temp region
    MOVEA.L     (A7),A3                         | A3 = temp region handle
    PEA.L       (DSAlertRect).W                 | rectangle where system error was drawn
    _RectRgn                                    | convert alert rect to region
    MOVE.L      A3,-(A7)                        | pass update region handle to PaintBehind
    _PaintBehind                                | repaint all windows obscured by alert
    MOVE.L      A3,-(A7)                        | pass update region handle to DisposeRgn
    _DisposeRgn                                 | free temp region
    _SetPort                                    | restore saved port
| --- Begin event retrieval ---
TGEVT_BEGIN:
    CLR.W       0xE(A6)                         | clear result Boolean (no event yet)
    MOVEA.L     0x8(A6),A3                      | A3 = ptr to caller's EventRecord
    MOVE.W      0xC(A6),D0                      | D0 = event mask
    MOVEA.L     A3,A0                           | A0 = EventRecord ptr for SYNTH_ACTIVATE
    BSR.W       SYNTH_ACTIVATE                  | check for pending activate/deactivate
    BEQ.B       TGEVT_POLL_OS                   | none: try OS event queue
    ADDQ.B      #0x1,0xE(A6)                    | activate event found: set result TRUE
    BRA.B       TGEVT_SYSEVT                    | skip to SystemEvent filtering
| --- Poll the OS Event Manager queue ---
TGEVT_POLL_OS:
    MOVE.W      0xC(A6),D0                      | reload event mask
    MOVEA.L     A3,A0                           | A0 = EventRecord ptr
    TST.W       D3                              | EventAvail or GetNextEvent?
    BPL.B       TGEVT_GET_OS                    | D3 >= 0: GetNextEvent (remove)
    _OSEventAvail                               | peek at queue without removing
    BRA.B       TGEVT_JOURNAL                   | skip over event removal
TGEVT_GET_OS:
    _GetOSEvent                                 | remove next matching event from queue
TGEVT_JOURNAL:
    MOVEA.L     A3,A1                           | A1 = EventRecord ptr for journaling
    MOVEQ.L     #0x4,D1                         | D1 = jcEvent (journal code 4)
    BSR.W       JOURNAL_DISPATCH                | journal the event if journaling active
    TST.W       (A3)                            | test evtNum: null event (0)?
    BEQ.B       TGEVT_CHK_UPDATE                | null: no real event from queue
    ADDQ.B      #0x1,0xE(A6)                    | real event: set result TRUE
    BRA.B       TGEVT_SYSEVT                    | proceed to SystemEvent filtering
| --- No event from queue; check for pending window updates ---
TGEVT_CHK_UPDATE:
    MOVE.W      0xC(A6),D0                      | reload event mask
    BTST        #0x6,D0                         | bit 6 = updateEvt in mask?
    BEQ.B       TGEVT_SYSEVT                    | update events not requested: skip
    CLR.W       -(A7)                           | space for CheckUpDate result
    MOVE.L      A3,-(A7)                        | push EventRecord ptr
    _CheckUpDate                                | synthesize updateEvt if window needs redraw
    MOVE.W      (A7)+,0xE(A6)                   | store result (TRUE if update found)
| --- SystemEvent filtering (GetNextEvent only) ---
| Intercepts events destined for desk accessories and handles
| Cmd-Shift-number key combos (FKEY resources).
TGEVT_SYSEVT:
    TST.W       D3                              | EventAvail mode?
    BMI.B       TGEVT_SCSI_POLL_CHECK           | yes: skip all filtering, return as-is
    TST.W       0xE(A6)                         | did we get an event?
    BEQ.B       TGEVT_SCSI_POLL_CHECK           | no event: skip to cleanup
    MOVEQ.L     #0xB,D1                         | mask: bits 0,1,3 (shift+alpha+cmd)
    AND.B       0xE(A3),D1                      | D1 = evtMeta & 0x0B
    SUBQ.B      #0x3,D1                         | test for Cmd+Shift (0x03)
    BNE.B       TGEVT_CALL_SYSEVENT             | modifiers don't match: try SystemEvent
    MOVE.B      0x5(A3),D1                      | D1 = virtual key code from evtMessage byte 3
    SUBI.B      #0x30,D1                        | subtract '0' to get digit value
    CMPI.B      #0xA,D1                         | digit < 10?
    BCC.B       TGEVT_CALL_SYSEVENT             | not digit 0-9: try SystemEvent
    MOVE.W      (A3),D0                         | D0 = evtNum (event type)
    SUBQ.W      #0x4,D0                         | subtract 4: autoKey(5)->1, keyDown(3)->-1
    BEQ.B       TGEVT_SWALLOW                   | autoKey: swallow without re-running FKEY
    ADDQ.W      #0x1,D0                         | keyDown(3): -1+1=0
    BNE.B       TGEVT_CALL_SYSEVENT             | not keyDown or autoKey: try SystemEvent
    SUBQ.W      #0x4,A7                         | space for GetResource result handle
    MOVE.L      #0x464B4559,-(A7)               | push resource type 'FKEY'
    MOVE.W      D1,-(A7)                        | push resource ID (digit 0-9)
    _GetResource                                | load FKEY resource
    MOVE.L      (A7)+,D0                        | D0 = resource handle (or NIL)
    BNE.B       TGEVT_RUN_FKEY                  | found: execute FKEY code
    CMPI.W      #0x2,D1                         | key > 2?
    BGT.B       TGEVT_SWALLOW                   | Cmd-Shift-3..9 with no FKEY: swallow
    TST.W       D1                              | key 0?
    BMI.B       TGEVT_SWALLOW                   | unreachable (D1 unsigned 0..9)
    BNE.B       GNE_FKEY_CALL                   | Cmd-Shift-1 or 2: eject
    MOVEQ.L     #0x3,D1                         | Cmd-Shift-0: shutdown -> drive 3 (no eject)
GNE_FKEY_CALL:
    MOVEQ.L     #0x1,D2                         | D2 = drive number (1 for internal)
    MOVEA.L     (0x7DC).W,A0                    | A0 = ToExtFS jump vector (eject helper)
    JSR         (A0)                            | call SCSI eject routine
    BRA.B       TGEVT_SWALLOW                   | swallow the key event
| --- Execute FKEY code resource ---
TGEVT_RUN_FKEY:
    MOVEA.L     D0,A0                           | A0 = FKEY resource handle
    MOVE.L      (A0),D0                         | dereference: D0 = master pointer
    BEQ.B       TGEVT_SWALLOW                   | nil ptr (purged resource): skip
    _HLock                                      | lock handle during execution
    MOVE.L      A0,-(A7)                        | save handle
    MOVEA.L     (A0),A0                         | A0 = ptr to FKEY executable code
    JSR         (A0)                            | execute the FKEY
    MOVEA.L     (A7)+,A0                        | restore handle
    _HUnlock                                    | unlock handle
| --- Swallow event (consumed by system or FKEY) ---
| Called by: TGEVT_SYSEVT, GNE_FKEY_CALL, TGEVT_RUN_FKEY
TGEVT_SWALLOW:
    CLR.W       (A3)                            | set evtNum = nullEvt (0), event consumed
    BRA.B       TGEVT_CLEAR_RESULT              | clear result, no event for app
TGEVT_CALL_SYSEVENT:
    TST.B       (SEvtEnb).W                     | system event filtering enabled?
    BEQ.B       TGEVT_SCSI_POLL_CHECK           | disabled: skip to cleanup
    SUBQ.W      #0x2,A7                         | space for SystemEvent result
    MOVE.L      A3,-(A7)                        | push EventRecord ptr
    _SystemEvent                                | check if DA or system should handle event
    TST.W       (A7)+                           | system consumed the event?
    BEQ.B       TGEVT_SCSI_POLL_CHECK           | no: keep result for app
TGEVT_CLEAR_RESULT:
    CLR.W       0xE(A6)                         | clear result: no event for application
TGEVT_SCSI_POLL_CHECK:
    BTST        #0x7,(SCSIPoll)                 | SE-only: SCSI poll requested?
    BEQ.B       TGEVT_CLEANUP                   | no: skip
    CMPI.L      #0x4B0,(Ticks).W                | tick count >= 1200 (20 sec poll interval)?
    BCS.B       TGEVT_CLEANUP                   | not yet: skip
    BCLR        #0x7,(SCSIPoll)                 | clear poll-pending flag
    BSR.W       SE_SCSI_BG_POLL                 | invoke SCSI poll handler
| --- Cleanup and return ---
TGEVT_CLEANUP:
    TST.W       (A3)                            | still a null event after processing?
    BNE.B       TGEVT_RETURN                    | real event remains: skip idle tracking
    PEA.L       (scratch8).W                    | push scratch point address
    _GetMouse                                   | track mouse position during null-event idle
TGEVT_RETURN:
    MOVEM.L     (A7)+,D3/A3                     | restore saved registers
    UNLK        A6                              | deallocate stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x6,A7                         | strip params (eventMask + eventPtr = 6 bytes)
    JMP         (A0)                            | tail-call return from TGEVT_RETURN via A0
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
    BTST        #0x8,D0                         | bit 8 in event mask = activateEvt?
    BEQ.B       SACT_NO_EVENT                   | not requested: return no event
    MOVE.L      (CurDeactive).W,D1              | D1 = window needing deactivation
    BGT.B       SACT_DO_DEACT                   | valid ptr (positive): deactivate first
    MOVE.L      (CurActivate).W,D1              | D1 = window needing activation
    BLE.B       SACT_NO_EVENT                   | no pending activation: return no event
    MOVEQ.L     #0x1,D2                         | D2 = modifiers: bit 0 = activeFlag (activating)
| --- Build the activateEvt in EventRecord ---
SACT_BUILD_EVT:
    MOVEQ.L     #0x0,D0                         | mask = 0: peek with no event type filter
    _OSEventAvail                               | A0 = ptr to EventRecord in queue (or empty)
    MOVE.W      #0x8,(A0)+                      | evtNum = activateEvt (8)
    MOVE.L      D1,(A0)                         | evtMessage = window pointer
| --- Check if switching between DA and app window (changeFlag) ---
    MOVE.L      (CurDeactive).W,D0              | D0 = deactivating window
    BEQ.B       SACT_SET_MODS                   | no deactivation: skip changeFlag
    MOVE.W      (CurDeKind).W,D0                | D0 = windowKind of deactivating window
    MOVE.L      (CurActivate).W,D1              | D1 = activating window
    BEQ.B       SACT_SET_MODS                   | no activation: skip changeFlag
    MOVEA.L     D1,A0                           | A0 = activating WindowPtr
    MOVE.W      0x6C(A0),D1                     | D1 = windowKind of activating window
    EOR.W       D0,D1                           | XOR: sign bit set if kinds differ in sign
    BPL.B       SACT_SET_MODS                   | same sign (both app or both DA): no change
    ADDQ.W      #0x2,D2                         | set bit 1 (changeFlag) in modifiers
SACT_SET_MODS:
    MOVE.W      0xE(A3),D0                      | D0 = existing modifiers in EventRecord
    ANDI.W      #0xFFFC,D0                      | clear bits 0-1 (activeFlag + changeFlag)
    OR.W        D2,D0                           | merge in new activeFlag and changeFlag
    MOVE.W      D0,0xE(A3)                      | store updated modifiers
    TST.W       D3                              | GetNextEvent mode?
    BNE.B       SACT_HAS_EVENT                  | EventAvail: don't consume, just report
    LSR.W       #0x1,D0                         | shift bit 0 (activeFlag) into carry
    BCC.B       SACT_MARK_DEACT                 | carry clear = deactivating: mark CurDeactive
    BSET        #0x7,(CurActivate)              | mark activate as consumed (set lock bit)
SACT_HAS_EVENT:
    MOVEQ.L     #-0x1,D1                        | return -1: event synthesized (NE condition)
    RTS                                         | return from SACT_HAS_EVENT
| No pending activate/deactivate events
SACT_NO_EVENT:
    MOVEQ.L     #0x0,D1                         | return 0: no event (EQ condition)
    RTS                                         | return from SACT_NO_EVENT
| Mark deactivate as consumed
SACT_MARK_DEACT:
    BSET        #0x7,(CurDeactive)              | set lock bit on CurDeactive ptr
    BRA.B       SACT_HAS_EVENT                  | return -1: event synthesized
| Deactivation pending: start with deactivate (activeFlag = 0)
SACT_DO_DEACT:
    CLR.W       D2                              | D2 = 0: modifiers with activeFlag clear
    BRA.B       SACT_BUILD_EVT                  | go build deactivate event
| ----------------------------------------------------------
|
| SE_SCSI_BG_POLL - SE-specific SCSI background poll
| Called from TBOX_GET_EVENT every 1200 ticks (20 sec) when SCSIPoll bit 7
| is set. Uses SCSIDispatch selectors 1,2,3,4 (SCSIReset/Selct/Cmd/Read)
| to probe the SCSI bus and dispatch results back via InternalWait.
|
SE_SCSI_BG_POLL:
    CLR.L       -(A7)                           | space for 8-byte SCSI param block
    CLR.L       -(A7)                           | clear params
    MOVE.W      #0x1,-(A7)                      | SCSIDispatch selector 1 (SCSIReset)
    _SCSIDispatch                               | reset SCSI bus
    TST.W       (A7)                            | reset OK?
    BNE.B       SCSI_POLL_EXIT                  | error: skip rest
    CLR.W       -(A7)                           | space for selector result
    MOVE.W      #0x2,-(A7)                      | SCSIDispatch selector 2 (SCSIGet)
    _SCSIDispatch                               | get bus
    TST.W       (A7)                            | got bus?
    BEQ.B       SCSI_POLL_SELECT                | yes: select target
    MOVEA.W     #0x4,A0                         | A0 = wait quanta (4 ticks)
    _InternalWait                               | yield until next opportunity
    BRA.B       SCSI_POLL_EXIT                  | -> exit
SCSI_POLL_SELECT:
    PEA.L       0x2(A7)                         | ptr to ID byte
    MOVE.W      #0x6,-(A7)                      | bus phase = command
    MOVE.W      #0x3,-(A7)                      | SCSIDispatch selector 3 (SCSISelect)
    _SCSIDispatch                               | select SCSI target
    PEA.L       0x2(A7)                         | ptr to status byte
    PEA.L       0x8(A7)                         | ptr to data buffer
    MOVEQ.L     #0x3C,D0                        | D0 = 60-byte transfer
    MOVE.L      D0,-(A7)                        | byte count
    MOVE.W      #0x4,-(A7)                      | SCSIDispatch selector 4 (CMP_COPY_FROM_DISK)
    _SCSIDispatch                               | issue command + read inquiry data
    MOVEA.W     #0x5,A0                         | A0 = wait quanta (5 ticks)
    _InternalWait                               | brief wait for completion
SCSI_POLL_EXIT:
    ADDQ.L      #0x8,A7                         | clean up param block
    RTS                                         | return from SE_SCSI_BG_POLL
