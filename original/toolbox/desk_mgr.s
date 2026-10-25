| Desk Manager -- desk accessories
|
| Apple source: DeskMgr.a (MacSEROM.lst module DESKMGR): SystemEvent
| ($A9B2, with its dispatch table SYSEVT_DISPATCH), SystemClick, SystemTask,
| SystemMenu, SysEdit, OpenDeskAcc, CloseDeskAcc. Desk accessories are
| drivers with a window; the Desk Manager routes events, menu choices and
| editing commands to them (through _Control with the accEvent, accMenu,
| accRun, accCut ... csCodes) and opens and closes them.
|
| References: Inside Macintosh Vol I, Ch 14 (The Desk Manager).

| ----------------------------------------------------------
|
| _SystemEvent ($A9B2): let the system handle desk accessory and disk events
| Pascal: FUNCTION SystemEvent(theEvent: EventRecord): BOOLEAN;
| Saves the port and dispatches on theEvent.what through SYSEVT_DISPATCH
| (continued in textedit.s): mouseUp, keyDown, keyUp and autoKey go to the
| front window's desk accessory if its dCtlEMask accepts them, update and
| activate events to the desk accessory owning the window in
| theEvent.message (accEvent Control call, result TRUE). A disk-inserted
| event is mounted with _MountVol and the result code stored in the high
| word of theEvent.message (result FALSE). Anything else: FALSE.
|
SystemEvent:
        MOVE.L  A3,-(SP)                        | save A3 (used as event-record ptr)
        MOVE.L  8(SP),A3                        | A3 = event record ptr from caller
        CLR     12(SP)                          | clear caller's result byte
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  SP,-(SP)                        | push ptr for GetPort
        _GetPort                                | save current grafPort on stack
        MOVE    (A3),D0                         | D0 = theEvent.what
        CMPI    #0x9,D0                         | event code in range 0..8?
        BCC.B   SYSEVT_RESTORE                  | no -> bail to shared epilog
        ADD     D0,D0                           | D0 *= 2 (word-index into jump table)
        LEA     SYSEVT_DISPATCH(PC),A0          | A0 = jump table base
        ADDA.W  0(A0,D0.W),A0                   | A0 = base + table[D0]
        JMP     (A0)                            | dispatch to handler
| ----------------------------------------------------------
| SYSEVT_DISPATCH - SystemEvent dispatch table (word offsets from
| SYSEVT_DISPATCH), indexed by theEvent.what (0-8; larger codes are
| rejected by SystemEvent before the table is used):
| 0 (null), 1 (mouseDown): -> SYSEVT_RESTORE (result FALSE)
| 2 (mouseUp), 3 (keyDown), 4 (keyUp), 5 (autoKey): -> SYSEVT_KEYEVENT
| 6 (update), 8 (activate): -> SYSEVT_ACTIVATE
| 7 (disk-inserted): -> SYSEVT_DISKEVT
SYSEVT_DISPATCH:                                | jump table base
        .short  SYSEVT_RESTORE - SYSEVT_DISPATCH | 0: null -> _SetPort cleanup
        .short  SYSEVT_RESTORE - SYSEVT_DISPATCH | 1: mouseDn -> (same)
        .short  SYSEVT_KEYEVENT - SYSEVT_DISPATCH | 2: mouseUp -> keyboard handler
        .short  SYSEVT_KEYEVENT - SYSEVT_DISPATCH | 3: keyDn
        .short  SYSEVT_KEYEVENT - SYSEVT_DISPATCH | 4: keyUp
        .short  SYSEVT_KEYEVENT - SYSEVT_DISPATCH | 5: autoKey
        .short  SYSEVT_ACTIVATE - SYSEVT_DISPATCH | 6: update
        .short  SYSEVT_DISKEVT  - SYSEVT_DISPATCH | 7: disk-insert
        .short  SYSEVT_ACTIVATE - SYSEVT_DISPATCH | 8: activate
| ----------------------------------------------------------
| Shared epilogs. SYSEVT_HANDLED entry marks result as handled; the
| SYSEVT_RESTORE entry is used by disk-insert events that
| already stored the result code in event.message.
SYSEVT_HANDLED:
        ADDQ.B  #0x1,0x10(SP)                   | set result byte = TRUE (handled)
SYSEVT_RESTORE:
        _SetPort                                | restore saved port
        MOVE.L  (SP)+,A3                        | restore A3
        MOVE.L  (SP)+,(SP)                      | slide retaddr over params
        RTS                                     | return to SystemEvent caller
| ----------------------------------------------------------
| Key/mouse event -> front-window DA dispatcher
SYSEVT_KEYEVENT:
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,A0                        | A0 = front window ptr
        BSR.B   TEXTEDIT_CONT_2                 | look up DA DCE -> A1
        BNE.B   SYSEVT_RESTORE                  | not a DA window, bail (no flag)
        MOVE    (A3),D0                         | D0 = event code (from caller)
        MOVE    dCtlEMask(A1),D1                | D1 = DCE event mask
        BTST    D0,D1                           | DA interested in this event?
        BEQ.B   SYSEVT_RESTORE                  | no, bail (no flag)
        BSR.B   TEXTEDIT_CONT_3                 | send accEvent control call to DA
        BRA.B   SYSEVT_HANDLED                  | -> return with handled=TRUE

| ----------------------------------------------------------
| TEXTEDIT_CONT_2 - A0 = window: if windowKind < 0 (desk accessory),
| A1 := its DCE (unit table entry NOT windowKind) and D0 = 0 (Z set);
| otherwise D0 = -1. TEXTEDIT_CONT_3 sends accEvent (csCode $40) to it.
| Called during boot (3,697 times in 30s trace).
TEXTEDIT_CONT_2:
        MOVE    windowKind(A0),D0               | D0 = windowKind from WindowRecord
        BPL.B   TEXTEDIT_ERR                    | positive = not a DA, return error
        NOT     D0                              | unit number = NOT refNum (-refNum-1)
        ASL     #0x2,D0                         | multiply by 4 = unit table byte index
        MOVE.L  (UTableBase).w,A0               | A0 = unit table base
        MOVE.L  0(A0,D0.W),A0                   | A0 = handle to DCE
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE pointer
        MOVEQ.L #0x0,D0                         | return 0 = success (Z flag set)
        RTS                                     | return success code (0)
TEXTEDIT_ERR:
        MOVEQ    #-0x1,D0                       | return -1 (Z=0): not a DA
        RTS                                     | return error code (-1)
TEXTEDIT_CONT_3:
        MOVEQ    #0x40,D0                       | csCode = accEvent (0x40)

| TEXTEDIT_CONT_4 - Control call with csCode D0 to the desk accessory
| whose DCE is A1 (csParam = A3), via a 32-byte parameter block on the
| stack. Also used by SystemClick, SystemTask (DA_ACCRUN_ENTRY: accRun
| $41), SystemMenu and SysEdit.
TEXTEDIT_CONT_4:
        LINK    A6,#-0x20                       | allocate param block on stack
        LEA.L   -0x8(A6),A0                     | A0 = ioRefNum field of the param block
        MOVE    dCtlRefNum(A1),(A0)+            | ioRefNum = dCtlRefNum
        MOVE    D0,(A0)+                        | csCode = D0
        MOVE.L  A3,(A0)                         | csParam = A3
        LEA.L   -0x20(A6),A0                    | A0 = param block base
        _ControlImmed                           | issue synchronous Control call to DA
        UNLK    A6                              | tear down frame
        RTS                                     | return from synchronous Control call
DA_ACCRUN_ENTRY:
        MOVEQ    #0x41,D0                       | csCode = accRun (periodic task)
        BRA.B    TEXTEDIT_CONT_4                | -> issue Control call
| ----------------------------------------------------------
| Update / activate event -> look up window's DA, send accEvent
SYSEVT_ACTIVATE:
        MOVE.L  evtMessage(A3),A0               | A0 = window ptr from event record
        BSR.B   TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
        BNE.B   SYSEVT_RESTORE                  | not a DA, bail (no flag)
        BSR.B   TEXTEDIT_CONT_3                 | send accEvent control call
        BRA.B   SYSEVT_HANDLED                  | -> return with handled=TRUE
| ----------------------------------------------------------
| Disk-insert event -> call _MountVol with drive number, return result
SYSEVT_DISKEVT:
        SUBA.W  #0x18,SP                        | allocate VolumeParam block on stack
        MOVE.L  SP,A0                           | A0 = param block ptr
        MOVE    4(A3),ioVRefNum(A0)             | ioVRefNum (+$16) := drive number (evtMessage+2) for MountVol
        _MountVol                               | mount the volume
        ADDA.W  #0x18,SP                        | discard param block
        MOVE    D0,0x2(A3)                      | store result code in event.message hi
        BRA.B   SYSEVT_RESTORE                  | -> return (no ADDQ handled-flag)

| ----------------------------------------------------------
| SystemClick -- _SystemClick ($A9B3).
| Routes a mouse click in a DA window to its DCE. Handles
| click in window content (accClick), drag bar, close box,
| desktop click (DeskHook), and inactive window selection.
SystemClick:
        MOVEM.L D0/D3-D4/A3-A4,-(SP)            | save registers
        MOVE.L  SP,-(SP)                        | space for GetPort
        _GetPort                                | save current port
        MOVE.L  24(SP),A4                       | A4 = window ptr param
        MOVE.L  28(SP),D4                       | D4 = event ptr param
        MOVE.L  A4,D0                           | test window for NIL
        BEQ.W   SYSTEMCLICK_EMPTY               | NIL -> desktop click
        MOVE.L  D0,A0                           | A0 = window ptr for DA lookup
        BSR.B   TEXTEDIT_CONT_2                 | look up the DA's DCE -> A1
        BNE.B   SYSTEMCLICK_EXIT                | not a DA window: bail
        MOVE.L  A1,D3                           | D3 = the DA's DCE ptr
        MOVEQ.L #0x0,D0                         | clear D0 for the variant byte
        MOVE.B  0x7E(A4),D0                     | D0 = varCode (high byte of windowDefProc +$7E)
        CLR.L   -(SP)                           | space for the WDEF function result
        MOVE    D0,-(SP)                        | push varCode
        MOVE.L  A4,-(SP)                        | push theWindow
        MOVE    #0x1,-(SP)                      | push message = wHit (1)
        MOVE.L  D4,A0                           | A0 = theEvent
        MOVE.L  10(A0),-(SP)                    | push event.where (mouse point)
        MOVE.L  0x7E(A4),A0                     | A0 = windowDefProc handle (+$7E)
        BSET    #0x7,(A0)                       | lock the WDEF handle
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        _LoadResource                           | make sure the WDEF is loaded
        MOVE.L  (A0),A0                         | A0 = WDEF entry (LoadResource keeps A0)
        JSR     (A0)                            | call WDEF: hit test
        MOVE.L  0x7E(A4),A0                     | A0 = windowDefProc handle again
        BCLR    #0x7,(A0)                       | unlock the WDEF handle
        MOVE.L  (SP)+,D0                        | D0 = part code from the WDEF
        BEQ.B   SYSTEMCLICK_EXIT                | no -> done
        SUBQ.W  #0x2,D0                         | partCode 2 (drag bar)?
        BEQ.B   SYSTEMCLICK_OK                  | yes: drag the DA window
        SUBQ.W  #0x2,D0                         | partCode 4 (close box)?
        BEQ.B   SYSTEMCLICK_OK_2                | yes: track close box
        CLR.L   -(SP)                           | space for FrontWindow result
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,D0                        | D0 = front window
        CMP.L   A4,D0                           | is DA window already in front?
        BNE.B   SYSTEMCLICK_NO                  | no: select window first
        MOVE.L  D4,A3                           | A3 = theEvent (csParam of accEvent)
        MOVE.L  D3,A1                           | A1 = DCE ptr (saved earlier)
        BSR.W   TEXTEDIT_CONT_3                 | send accEvent control call to DA
| Called by: SYSTEMCLICK_EMPTY, SYSTEMCLICK_EMPTY_CONT, SYSTEMCLICK_OK, SYSTEMCLICK_OK_2, SYSTEMCLICK_OK_3
SYSTEMCLICK_EXIT:
        _SetPort                                | restore saved port
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore registers
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x8,SP                         | pop 2 params (window, event)
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| SYSTEMCLICK_EMPTY
| Called during boot.
SYSTEMCLICK_EMPTY:
        TST.L   (DeskHook).w                    | custom desktop hook installed?
        BEQ.B   SYSTEMCLICK_EXIT                | no hook: just bail
        MOVE.L  (WMgrPort).w,-(SP)              | set port to Window Manager port
        _SetPort                                | switch to WMgr port
        MOVE.L  (GrayRgn).w,-(SP)               | clip to gray region (desktop area)
        _SetClip                                | restrict drawing to desktop
        CLR.L   -(SP)                           | no window to clip above
        _ClipAbove                              | clip to behind all windows
        MOVE.L  D4,A0                           | A0 = event record
        MOVE.L  (DeskHook).w,A1                 | A1 = desk hook procedure
        MOVEQ.L #-0x1,D0                        | D0 = -1 (click in desktop)
        JSR     (A1)                            | call desk hook
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return
SYSTEMCLICK_NO:
        MOVE.L  A4,-(SP)                        | push window ptr (front != A4 case)
        _SelectWindow                           | bring our window to front
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return
SYSTEMCLICK_OK:
        MOVE.L  A4,-(SP)                        | push window ptr
        MOVE.L  D4,A0                           | A0 = event record
        MOVE.L  evtMouse(A0),-(SP)              | push event.where (start point)
        MOVE.L  (A5),A0                         | A0 = app globals ptr
        PEA.L   -0x74(A0)                       | push drag boundary rect
        _DragWindow                             | let user drag DA title bar
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return
SYSTEMCLICK_OK_2:
        CLR     -(SP)                           | space for TrackGoAway result
        MOVE.L  A4,-(SP)                        | push window ptr
        MOVE.L  D4,A0                           | A0 = event record
        MOVE.L  evtMouse(A0),-(SP)              | push event.where (mouse point)
        _TrackGoAway                            | track close box click
        TST.B   (SP)+                           | user confirmed close?
        BEQ.B   SYSTEMCLICK_EXIT                | no: just exit
        MOVE.L  D3,A1                           | A1 = DCE ptr
        MOVE.L  (CloseOrnHook).w,D0             | custom close hook installed?
        BNE.B   SYSTEMCLICK_OK_3                | yes -> call custom hook
        MOVE    dCtlRefNum(A1),-(SP)            | push DA refNum from DCE
        _CloseDeskAcc                           | close the desk accessory
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return
SYSTEMCLICK_OK_3:
        MOVE.L  D0,A0                           | A0 = close ornament hook
        JSR     (A0)                            | call custom close handler
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return

| ----------------------------------------------------------
| SystemTask -- _SystemTask ($A9B4).
| Walks the unit table calling each DA's accRun entry if it has
| dNeedTime + dOpened set and its dCtlDelay has elapsed.
SystemTask:
        MOVEM.L D3/A3,-(SP)                     | save registers
        BSET    #0x7,(TaskLock).w               | atomically test+set TaskLock bit 7
        BNE.W   SYSTEMTASK_CONT                 | already locked - exit immediately
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  SP,-(SP)                        | push ptr for GetPort result
        _GetPort                                | save current port on stack
        CLR.L   -(SP)                           | space for FrontWindow result
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,A0                        | A0 = front window ptr
        BSR.W   TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
        BNE.B   SYSTEMTASK_SKIP                 | not a DA window: skip accCursor
        BTST    #0x7,5(A1)                      | drvrActive (bit 7 of dCtlFlags+1): DA busy?
        BNE.B   SYSTEMTASK_SKIP                 | flag set: skip accCursor
        MOVEQ.L #0x42,D0                        | csCode = accCursor (66)
        BSR.W   TEXTEDIT_CONT_4                 | send accCursor control call
SYSTEMTASK_SKIP:
        MOVE.L  (UTableBase).w,A3               | A3 = unit table base
        MOVE    (UnitTableEntryCount).w,D3      | D3 = unit table entry count
SYSTEMTASK_LOOP:
        MOVE.L  (A3)+,D0                        | D0 = next DCE handle
        BEQ.B   SYSTEMTASK_SKIP_2               | nil -> skip this slot
        MOVE.L  D0,A0                           | A0 = DCE handle
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE
        MOVE    dCtlFlags(A1),D0                | D0 = dCtlFlags
        ANDI    #0x20A0,D0                      | keep dNeedTime, drvrActive, dOpened
        CMPI    #0x2020,D0                      | needs time, open and not active?
        BNE.B   SYSTEMTASK_SKIP_2               | missing flags: skip this DA
        MOVEQ.L #0x0,D0                         | clear high word
        MOVE    dCtlDelay(A1),D0                | D0 = dCtlDelay (tick interval)
        BEQ.B   SYSTEMTASK_EMPTY                | zero delay -> always run
        ADD.L   26(A1),D0                       | D0 = last run time + delay
        CMP.L   (Ticks).w,D0                    | time to run yet?
        BGT.B   SYSTEMTASK_SKIP_2               | not yet -> skip
        MOVE.L  (Ticks).w,26(A1)                | update last run time to now
SYSTEMTASK_EMPTY:
        BSR.W   DA_ACCRUN_ENTRY                 | call DA's periodic-task entry point
SYSTEMTASK_SKIP_2:
        SUBQ.W  #0x1,D3                         | decrement unit counter
        BGT.B   SYSTEMTASK_LOOP                 | more entries -> loop
        _SetPort                                | restore saved port
        CLR.B   (TaskLock).w                    | release task lock
SYSTEMTASK_CONT:
        MOVEM.L  (SP)+,D3/A3                    | restore saved registers
        RTS                                     | return from SystemTask

| ----------------------------------------------------------
| SystemMenu -- _SystemMenu ($A9B5).
| Routes a menu selection to the owning DA's accMenu entry if
| the menuID matches a DA's dCtlMenu field.
SystemMenu:
        MOVEM.L A2-A3,-(SP)                     | save registers
        MOVE.L  12(SP),D1                       | D1 = menu result (menuID | item)
        SWAP    D1                              | D1.W = menuID
        MOVE    (MBarEnable).w,D0               | D0 = menu bar enable word
        BEQ.B   SYSTEMMENU_EMPTY                | zero -> use menuID from param
        MOVE    D0,D1                           | override with MBarEnable menuID
SYSTEMMENU_EMPTY:
        MOVE.L  (UTableBase).w,A2               | A2 = unit table base
        MOVE    (UnitTableEntryCount).w,D2      | D2 = unit table entry count
SYSTEMMENU_LOOP:
        MOVE.L  (A2)+,D0                        | D0 = next DCE handle
        BEQ.B   SYSTEMMENU_SKIP                 | nil -> skip slot
        MOVE.L  D0,A0                           | A0 = DCE handle
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE
        BTST    #0x5,5(A1)                      | dOpened (bit 5 of dCtlFlags+1): DA open?
        BEQ.B   SYSTEMMENU_SKIP                 | not open: skip it
        CMP     dCtlMenu(A1),D1                 | DCE menuID matches selected menu?
        BNE.B   SYSTEMMENU_SKIP                 | no -> try next
        MOVE.L  12(SP),A3                       | A3 = menu result for accMenu
        MOVEQ.L #0x43,D0                        | csCode = accMenu (67)
        BSR.W   TEXTEDIT_CONT_4                 | send accMenu control call
        BRA.B   SYSTEMMENU_DONE                 | -> done
SYSTEMMENU_SKIP:
        SUBQ.W  #0x1,D2                         | decrement entry count
        BGT.B   SYSTEMMENU_LOOP                 | more entries: continue scan
SYSTEMMENU_DONE:
        MOVEM.L (SP)+,A2-A3                     | restore saved registers
        MOVE.L  (SP)+,(SP)                      | pop return addr over name param
        RTS                                     | return from DA window activation

| ----------------------------------------------------------
| SysEdit -- _SysEdit ($A9C2).
| Routes Edit menu commands (Undo/Cut/Copy/Paste/Clear) to a DA
| if the front window is a desk accessory.
SysEdit:
        CLR     6(SP)                           | clear result (FALSE by default)
        SUBQ.W  #0x8,SP                         | allocate saved port + window
        PEA.L     4(SP)                         | push ptr for GetPort result
        _GetPort                                | save current port
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,D0                        | D0 = front window ptr
        BEQ.B   SYSEDIT_SKIP                    | no window -> skip
        MOVE.L  D0,A0                           | A0 = front window
        BSR.W   TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
        BNE.B   SYSEDIT_SKIP                    | not a DA -> skip
        MOVE    8(SP),D0                        | D0 = editCmd parameter (0-3)
        ADDI    #0x44,D0                        | csCode = accUndo+editCmd (0x44+)
        BSR.W   TEXTEDIT_CONT_4                 | send edit command to DA
        ADDQ.B  #0x1,10(SP)                     | set result = TRUE (DA handled it)
SYSEDIT_SKIP:
        _SetPort                                | restore saved port (on stack)
        BRA.B   CLOSEDA_EPILOG                  | -> pop retaddr + param + return

| ----------------------------------------------------------
| OpenDeskAcc -- _OpenDeskAcc ($A9B6).
| Open a desk accessory by name. Calls _Open with name as ioPB,
| then on success calls _SelectWindow + _ShowWindow on the
| DA's window.
OpenDeskAcc:
        CLR     8(SP)                           | clear result slot
        SUBA.W  #0x20,SP                        | allocate ioParam block
        MOVE.L  0x24(SP),18(SP)                 | ioFileName = name from param
        CLR     22(SP)                          | ioVersNum = 0
        CLR     26(SP)                          | ioPermssn = 0
        CLR.L   28(SP)                          | ioMisc = 0
        MOVE.L  SP,A0                           | A0 = ioPB
        _Open                                   | open the DA driver
        BNE.B   OPENDESKACC_ERR                 | failed - cleanup
        MOVE    24(SP),D0                       | D0 = ioRefNum (DA refNum)
        MOVE    D0,0x28(SP)                     | store refNum as return value
        NOT     D0                              | invert refNum: -refNum-1
        ASL     #0x2,D0                         | multiply by 4 = unit table index
        MOVE.L  (UTableBase).w,A1               | A1 = unit table base
        MOVE.L  0(A1,D0.W),A1                   | A1 = handle to DCE
        MOVE.L  (A1),A1                         | A1 = dereferenced DCE pointer
        MOVE.L  30(A1),D0                       | D0 = dCtlWindow (DA window ptr)
        BEQ.B   OPENDESKACC_ERR                 | no window: just return
        MOVE.L  D0,-(SP)                        | push window for SelectWindow
        MOVE.L  D0,-(SP)                        | push window for ShowWindow
        _SelectWindow                           | bring DA window to front
        _ShowWindow                             | make DA window visible
OPENDESKACC_ERR:
        ADDA    #0x20,SP                        | discard param block
        MOVE.L  (SP)+,(SP)                      | pop return addr over name param
        RTS                                     | return from DA window activation

| ----------------------------------------------------------
| _CloseDeskAcc ($A9B7)
CloseDeskAcc:
        MOVE    0x4(SP),D0                      | D0 = DA refNum (param)
        SUBA    #0x1E,SP                        | allocate IOParam block
        MOVE    D0,0x18(SP)                     | ioRefNum = DA refNum
        MOVE.L  A7,A0                           | A0 = param block
        _Close                                  | close the DA driver
        ADDA    #0x1E,SP                        | discard param block
CLOSEDA_EPILOG:                                 | shared with SYSEDIT_SKIP exit
        MOVE.L  (SP)+,A0                        | A0 = saved return addr
        ADDQ.W  #0x2,SP                         | pop 16-bit refNum parameter
        JMP     (A0)                            | return to caller

