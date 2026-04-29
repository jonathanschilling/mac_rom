| TextEdit
|
| Provides basic text editing capabilities: TENew, TEDispose,
| TESetText, TEGetText, TEKey, TEClick, TEInsert, TEDelete,
| TEActivate, TEDeactivate, TEIdle, TECopy, TECut, TEPaste,
| TEScroll, TECalText, TEUpdate, and styled text support.
|
| TERec (MPW 1.0 TextEdit.h):
| Offset 0: destRect Rect destination rectangle (8 bytes)
| Offset 8: viewRect Rect view rectangle (8 bytes)
| Offset 16: selRect Rect selection rectangle
| Offset 24: lineHeight INTEGER line height in pixels
| Offset 26: fontAscent INTEGER font ascent
| Offset 28: selPoint Point selection point
| Offset 32: selStart INTEGER start of selection
| Offset 34: selEnd INTEGER end of selection
| Offset 36: active INTEGER active flag
| Offset 38: wordBreak ProcPtr word break procedure
| Offset 42: clikLoop ProcPtr click loop procedure
| Offset 46: clickTime LongInt time of last click
| Offset 50: clickLoc INTEGER location of last click
| Offset 52: caretTime LongInt time of last caret blink
| Offset 56: caretState INTEGER caret on/off state
| Offset 58: just INTEGER justification (0=left, 1=center, -1=right)
| Offset 60: teLength INTEGER length of text
| Offset 62: hText Handle handle to text
| Offset 66: recalBack INTEGER reserved
| Offset 68: recalLines INTEGER reserved
| Offset 70: clikStuff INTEGER reserved
| Offset 72: crOnly INTEGER carriage return only flag
| Offset 74: txFont INTEGER text font
| Offset 76: txFace Style text face
| Offset 78: txMode INTEGER text transfer mode
| Offset 80: txSize INTEGER text size
| Offset 82: inPort GrafPtr port for drawing
| Offset 86: highHook ProcPtr highlighting hook
| Offset 90: caretHook ProcPtr caret drawing hook
| Offset 94: nLines INTEGER number of lines
| Offset 96: lineStarts[] INTEGER[] start offset of each line
|
| References:
| Inside Macintosh Vol I, Ch 12: TextEdit

| ----------------------------------------------------------
| SYSEVT_DISPATCH - SystemEvent dispatch table (word offsets from SYSEVT_DISPATCH)
| Entries for event codes 0-11:
| 0 (null): -> SYSEVT_HANDLED (not handled)
| 1 (mouseDown): -> SYSEVT_HANDLED (not handled by system)
| 2 (mouseUp): -> handler
| 3 (keyDown): -> handler
| 4 (keyUp): -> handler
| 5 (autoKey): -> handler
| 6 (update): -> desk accessory update handler
| 7 (disk): -> disk-inserted handler
| 8 (activate): -> desk accessory activate handler
| 9 (abort): -> SYSEVT_HANDLED (not handled)
| 10 (network): -> handler
| 11 (driver): -> handler
| SYSEVT_DISPATCH: 9-entry word-offset jump table indexed by event code
| (D0.W). Upper-bound check + scaled index + LEA table,A0 + ADDA word
| at table[D0],A0 + JMP (A0) pattern. Offsets are relative to table start.
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
| TEXTEDIT_CONT_2
| Called during boot (3,697 times in 30s trace).
TEXTEDIT_CONT_2:
        MOVE    windowKind(A0),D0               | D0 = windowKind from WindowRecord
        BPL.B   TEXTEDIT_ERR                    | positive = not a DA, return error
        NOT     D0                              | invert kind: -refNum-1 -> refNum
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

| TEXTEDIT_CONT_4 -- send accCursor to front DA.
TEXTEDIT_CONT_4:
        LINK    A6,#-0x20                       | allocate param block on stack
        LEA.L   -0x8(A6),A0                     | A0 = csParam area in param block
        MOVE    dCtlRefNum(A1),(A0)+            | csParam[0] = DCE refNum
        MOVE    D0,(A0)+                        | csParam[1] = csCode
        MOVE.L  A3,(A0)                         | csParam[2] = event/menu ptr
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
        MOVE    4(A3),ioVRefNum(A0)             | ioVRefNum = drive number from caller
        _MountVol                               | mount the volume
        ADDA.W  #0x18,SP                        | discard param block
        MOVE    D0,0x2(A3)                      | store result code in event.message hi
        BRA.B   SYSEVT_RESTORE                  | -> return (no ADDQ handled-flag)

| ----------------------------------------------------------
| SystemClick -- _SystemClick ($A9B3). Plus textedit.s 138.
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
        BSR.B   TEXTEDIT_CONT_2                 | call subroutine via A1
        BNE.B   SYSTEMCLICK_EXIT                | not a DA window: bail
        MOVE.L  A1,D3                           | push DA window to bring to front
        MOVEQ.L #0x0,D0                         | zero-extend windowKind hi
        MOVE.B  0x7E(A4),D0                     | D0 = control flag byte
        CLR.L   -(SP)                           | space for FindWindow result
        MOVE    D0,-(SP)                        | push window ptr
        MOVE.L  A4,-(SP)                        | A0 = event record
        MOVE    #0x1,-(SP)                      | push event.where (start point)
        MOVE.L  D4,A0                           | A0 = app globals ptr
        MOVE.L  10(A0),-(SP)                    | push event.where (mouse point)
        MOVE.L  0x7E(A4),A0                     | A0 = window controlList handle
        BSET    #0x7,(A0)                       | lock control list during call
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        _LoadResource                           | ensure DA control code in memory
        MOVE.L  (A0),A0                         | push window ptr
        JSR     (A0)                            | call subroutine via A0
        MOVE.L  0x7E(A4),A0                     | push event.where (mouse point)
        BCLR    #0x7,(A0)                       | unlock control list handle
        MOVE.L  (SP)+,D0                        | D0 = part code from DA
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
        MOVE.L  D4,A3                           | call subroutine via A0
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
| SystemTask -- _SystemTask ($A9B4). Plus textedit.s 261.
| Walks the unit table calling each DA's accRun entry if it has
| dNeedTime + dOpened set and its dCtlDelay has elapsed.
SystemTask:
        MOVEM.L D3/A3,-(SP)                     | save registers
        BSET    #0x7,(TaskLock).w               | atomically test+set TaskLock bit 7
        BNE.W   SYSTEMTASK_CONT                 | already locked - exit immediately
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  SP,-(SP)                        | D0 = next DCE handle
        _GetPort                                | save current port on stack
        CLR.L   -(SP)                           | space for FrontWindow result
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,A0                        | A0 = front window ptr
        BSR.W   TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
        BNE.B   SYSTEMTASK_SKIP                 | not a DA window: skip accCursor
        BTST    #0x7,5(A1)                      | test "no DA cursor" flag in DCE
        BNE.B   SYSTEMTASK_SKIP                 | flag set: skip accCursor
        MOVEQ.L #0x42,D0                        | csCode = accMenu (67)
        BSR.W   TEXTEDIT_CONT_4                 | send accMenu control call
SYSTEMTASK_SKIP:
        MOVE.L  (UTableBase).w,A3               | A3 = unit table base
        MOVE    (UnitTableEntryCount).w,D3      | D3 = unit table entry count
SYSTEMTASK_LOOP:
        MOVE.L  (A3)+,D0                        | D0 = next DCE handle
        BEQ.B   SYSTEMTASK_SKIP_2               | nil -> skip this slot
        MOVE.L  D0,A0                           | A0 = DCE handle
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE
        MOVE    dCtlFlags(A1),D0                | D0 = dCtlFlags
        ANDI    #0x20A0,D0                      | mask dNeedTime + dOpened + dRAMBased
        CMPI    #0x2020,D0                      | dNeedTime and dOpened both set?
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
| SystemMenu -- _SystemMenu ($A9B5). Plus textedit.s 314.
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
        BTST    #0x5,5(A1)                      | dCtlFlags: dNeedTime set? (has menu)
        BEQ.B   SYSTEMMENU_SKIP                 | flag clear: not a menu DA
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
| SysEdit -- _SysEdit ($A9C2). Plus textedit.s 355.
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
| OpenDeskAcc -- _OpenDeskAcc ($A9B6). Plus textedit.s 378.
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

| ----------------------------------------------------------
| GetPattern -- _GetPattern ($A9B8). Plus textedit.s 427.
| Gets a 'PAT ' resource by ID. Common epilog GETPATTERN_EXIT
| is shared with GetCursor/GetString/GetIcon/GetPicture.
GetPattern:
        MOVE.L  #0x50415420,D0                  | D0 = 'PAT ' resource type
GETPATTERN_EXIT:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  D0,-(SP)                        | push resource type
        MOVE    0xC(SP),-(SP)                   | push resource ID (param)
        _GetResource                            | load resource -> handle on stack
        MOVE.L  (SP)+,D0                        | D0 = resource handle
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop resID parameter
        MOVE.L  D0,(SP)                         | store handle as return value
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetCursor -- _GetCursor ($A9B9). Plus textedit.s 445.
GetCursor:                                      | jump via A0
        MOVE.L  #0x43555253,D0                  | D0 = 'CURS' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetString -- _GetString ($A9BA). Plus textedit.s 454.
GetString:
        MOVE.L  #0x53545220,D0                  | D0 = 'STR ' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetIcon -- _GetIcon ($A9BB). Plus textedit.s 463.
GetIcon:
        MOVE.L  #0x49434F4E,D0                  | D0 = 'ICON' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetPicture -- _GetPicture ($A9BC). Plus textedit.s 472.
GetPicture:
        MOVE.L  #0x50494354,D0                  | D0 = 'PICT' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetNewWindow -- _GetNewWindow ($A9BD). Plus textedit.s 480.
| Loads a 'WIND' resource and creates a new window from the template.
GetNewWindow:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        CLR.L   18(A6)                          | clear return value (window ptr)
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57494E44,-(SP)               | push 'WIND' resource type
        MOVE    16(A6),-(SP)                    | push resource ID (param)
        _GetResource                            | load WIND template
        MOVE.L  (SP)+,A3                        | A3 = WIND resource handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETPATTERN_EXIT_FOUND           | not found -> bail
        MOVE.L  (A3),A0                         | A0 = dereferenced WIND data
        SUBQ.W  #0x4,SP                         | space for NewWindow result
        MOVE.L  12(A6),-(SP)                    | push wStorage (behind param)
        MOVE.L  A0,-(SP)                        | push boundsRect from template
        PEA.L     18(A0)                        | push title string from template
        MOVE.L  8(A0),-(SP)                     | push visible + procID from template
        MOVE.L  8(A6),-(SP)                     | push behind window (param)
        MOVE    12(A0),-(SP)                    | push goAwayFlag from template
        MOVE.L  14(A0),-(SP)                    | push refCon from template
        BSET    #0x7,(A3)                       | lock WIND handle during NewWindow
        _NewWindow                              | create the window
        MOVE.L  (SP)+,18(A6)                    | store window ptr as return value
        MOVE.L  A3,-(SP)                        | push WIND handle
        _ReleaseResource                        | release the WIND template
GETPATTERN_EXIT_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| _GetNewControl ($A9BE)
GetNewControl:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        CLR.L   0xE(A6)                         | clear return value (ControlHandle)
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x434E544C,-(SP)               | push 'CNTL' resource type
        MOVE    0xC(A6),-(SP)                   | push resource ID (param)
        _GetResource                            | load CNTL template
        MOVE.L  (SP)+,A3                        | A3 = CNTL resource handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWCONTROL_FOUND             | not found -> bail
        MOVE.L  (A3),A0                         | A0 = dereferenced CNTL data
        SUBQ.W  #0x4,SP                         | space for NewControl result
        MOVE.L  0x8(A6),-(SP)                   | push owning window (param)
        MOVE.L  A0,-(SP)                        | push boundsRect from template
        PEA.L   0x16(A0)                        | push title string from template
        LEA.L   0x8(A0),A1                      | A1 = pointer past boundsRect
        MOVE.L  (A1)+,-(SP)                     | push visible + initial value
        MOVE.L  (A1)+,-(SP)                     | push min + max
        MOVE    (A1)+,-(SP)                     | push procID
        MOVE.L  (A1)+,-(SP)                     | push refCon
        BSET    #0x7,(A3)                       | lock CNTL handle during NewControl
        _NewControl                             | create the control
        MOVE.L  (SP)+,0xE(A6)                   | store ControlHandle as return value
        MOVE.L  A3,-(SP)                        | push CNTL handle
        _ReleaseResource                        | release the CNTL template
GETNEWCONTROL_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x6,SP                         | pop parameters (6 bytes)
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetRMenu -- _GetRMenu ($A9BF). Plus textedit.s 554.
| Loads a MENU resource by ID and inserts it via _InsertMenu.
| Resolves MDEF reference to actual menu definition proc.
GetRMenu:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D454E55,-(SP)               | push 'MENU' resource type
        MOVE    8(A6),-(SP)                     | push resource ID (param)
        _GetResource                            | load MENU resource
        MOVE.L  (SP)+,A3                        | A3 = MENU resource handle
        MOVE.L  A3,10(A6)                       | store handle as result
        BEQ.B   GETRMENU_EXIT                   | NIL - bail
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D444546,-(SP)               | push 'MDEF' resource type
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE    6(A0),-(SP)                     | push procID from MENU
        _GetResource                            | load MDEF resource
        MOVE.L  (A3),A0                         | dereference MENU handle (may have moved)
        MOVE.L  (SP)+,6(A0)                     | store MDEF handle in MENU's procID slot
        MOVE.L  A3,-(SP)                        | push MENU handle
        _CalcMenuSize                           | calculate menu width/height
GETRMENU_EXIT:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop resID parameter
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetNewMBar -- _GetNewMBar ($A9C0). Plus textedit.s 623.
| Loads an MBAR resource and inserts each menu via GetRMenu.
GetNewMBar:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D3/A3,-(SP)                     | save registers
        CLR.L   10(A6)                          | clear return value (menu bar handle)
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | save current menu bar
        _ClearMenuBar                           | clear menu list
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D424152,-(SP)               | push 'MBAR' resource type
        MOVE    8(A6),-(SP)                     | push resource ID (param)
        _GetResource                            | load MBAR resource
        MOVE.L  (SP)+,A3                        | A3 = MBAR handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWMBAR_FOUND                | MBAR not found: bail
        MOVEQ.L #0x0,D3                         | D3 = menu index counter
GETNEWCONTROL_FOUND_CONT_3:
        SUBQ.W  #0x4,SP                         | space for GetRMenu result
        MOVE.L  (A3),A0                         | A0 = MBAR data ptr
        MOVE    D3,D0                           | D0 = current menu index
        ADD     D0,D0                           | index *= 2 (word entries)
        MOVE    2(A0,D0.W),-(SP)                | push menu resID from MBAR[i]
        BSR.B   GetRMenu                        | load MENU + MDEF resource
        CLR     -(SP)                           | push beforeID = 0 (append)
        _InsertMenu                             | insert into current menu list
        MOVE.L  (A3),A0                         | reload MBAR ptr (may have moved)
        ADDQ.W  #0x1,D3                         | advance to next index
        CMP     (A0),D3                         | more menus to load?
        BLT.B   GETNEWCONTROL_FOUND_CONT_3      | yes: continue
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | grab handle to new menu bar
        MOVE.L  (SP)+,10(A6)                    | return menu bar handle
        MOVE.L  A3,-(SP)                        | push MBAR handle
        _ReleaseResource                        | release MBAR template
GETNEWMBAR_FOUND:
        MOVE.L  (SP),-(SP)                      | dup saved menu bar handle on stack
        _SetMenuBar                             | restore original menu bar
        MOVE.L  (SP)+,A0                        | A0 = old menu bar handle
        _DisposeHandle                          | dispose old menu bar copy
        MOVEM.L (SP)+,D3/A3                     | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop resource ID parameter
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| TEGetText -- _TEGetText ($A9CB). Plus textedit.s 672.
| Returns the text Handle of a TERec.
TEGetText:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  teTextH(A3),(A2)                | store TE text handle in caller's slot
        BRA.W   TECALTEXT_EXIT                  | -> common TE epilog

| ----------------------------------------------------------
| TEInit -- _TEInit ($A9CC). Plus textedit.s 684.
| Initialize TextEdit globals: allocate empty scrap handle and
| install default TEDoText / TERecal / TEWdBreak hooks.
TEInit:
        MOVEQ.L #0x0,D0                         | zero-length handle
        MOVE    D0,(TEScrpLength).w             | clear TE scrap length
        _NewHandle                              | allocate empty scrap handle
        MOVE.L  A0,(TEScrpHandle).w             | save TE scrap handle
        LEA     XTRIMMEASURE_OK_CONT_3(PC),A0   | default text drawing/measuring
        MOVE.L  A0,(TEDoText).w                 | install TEDoText hook
        LEA     TEFINDWORD_CONT_4_CONT_9(PC),A0 | default line recalculation
        MOVE.L  A0,(TERecal).w                  | install TERecal hook
        LEA     TEFINDWORD_CONT_4_CONT(PC),A0   | default word break detection
        MOVE.L  A0,(TEWdBreak).w                | install TEWdBreak hook
        RTS                                     | return from default hook installation

| ----------------------------------------------------------
| TEDispose -- _TEDispose ($A9CD). Plus textedit.s 703.
| Dispose a TERec handle (its text handle and the TERec itself).
TEDispose:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers
        MOVE.L  0x28(SP),A4                     | A4 = TE handle param
        MOVE.L  (A4),A3                         | A3 = TERec dereferenced
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        _DisposeHandle                          | dispose text
        MOVE.L  A4,A0                           | A0 = TE handle
        _DisposeHandle                          | dispose TERec itself
        MOVEQ.L #0x4,D0                         | 4 param bytes
        BRA.B   TETEXTBOX_EXIT                  | -> common TE exit
| ----------------------------------------------------------
| TETextBox -- _TETextBox ($A9CE). Plus textedit.s 720.
| Draws a string of text within a rect using a temporary TERec.
| Pascal: PROCEDURE TETextBox(text: Ptr; length: LongInt;
| box: Rect; just: INTEGER);
TETextBox:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save regs
        SUBQ.W  #0x4,SP                         | space for TENew result
        MOVE.L  0x2E(SP),-(SP)                  | push box rect
        MOVE.L  (SP),-(SP)                      | dup for viewRect
        MOVE.L  (SP),-(SP)                      | dup for EraseRect
        _EraseRect                              | clear the box area
        _TENew                                  | create temporary TERec
        MOVE.L  (SP)+,A4                        | A4 = TEHandle
        MOVE.L  (A4),A0                         | A0 = dereferenced TERec
        MOVE    0x28(SP),0x3A(A0)               | set TERec.just from param
        MOVE.L  0x2E(SP),D0                     | D0 = text length param
        BEQ.B   TETEXTBOX_NO                    | empty -> skip text setup
        MOVE.L  0x32(SP),-(SP)                  | push text ptr param
        MOVE.L  D0,-(SP)                        | push text length
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TESetText                              | set the text content
        MOVE.L  0x2A(SP),-(SP)                  | push update rect ptr
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEUpdate                               | draw all text lines
TETEXTBOX_NO:
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEDispose                              | dispose temporary TERec
        MOVEQ.L #0xE,D0                         | strip 14 param bytes
TETEXTBOX_EXIT:
        BRA.B   TECALTEXT_EXIT_3                | share TE common epilog

| ----------------------------------------------------------
| TESetText -- _TESetText ($A9CF). Plus textedit.s 822.
| Replaces the text content of a TERec with a Ptr+length copy.
TESetText:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (A3, A2=params)
        MOVE.L  (A2)+,D0                        | D0 = text length
        MOVE    D0,teSelStart(A3)               | selStart = length (cursor at end)
        MOVE    D0,teSelEnd(A3)                 | selEnd = length
        MOVE    D0,teLength(A3)                 | teLength = new length
        MOVE.L  (A2)+,A0                        | A0 = text pointer
        MOVE.L  teTextH(A3),A1                  | A1 = text handle
        BCLR    #0x7,(A1)                       | unlock text handle before resize
        _PtrToXHand                             | copy text to handle (resizes)
        MOVE.L  A4,-(SP)                        | push TE handle
        _TECalText                              | recalculate line breaks
TESETTEXT_EXIT:
        BRA.W   TEINSERT_EXIT                   | share TE epilog

| ----------------------------------------------------------
| TECalText -- _TECalText ($A9D0). Plus textedit.s 857.
| Recalculate line breaks for the text.
TECalText:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  teSelStart(A3),-(SP)            | save selStart/selEnd
        CLR     teSelStart(A3)                  | clear selStart (for full recalc)
        MOVE    #-0x7FFE,D7                     | flag: full recalculation needed
        CLR.L   0x60(A3)                        | clear line cache
        BSR.W   TEFINDWORD_CONT_4_CONT_8        | recalculate all line breaks
        MOVE.L  (SP)+,teSelStart(A3)            | restore selStart/selEnd
TECALTEXT_EXIT:
        MOVEQ.L #0x4,D0                         | strip 4 param bytes
TECALTEXT_EXIT_2:
        MOVE.L  0x32(SP),A4                     | A4 = TE handle from saved frame
        MOVE.L  (A4),A3                         | A3 = dereferenced TE record
        MOVE    D0,D4                           | D4 = strip count (saved)
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        BCLR    #0x7,(A0)                       | unlock text handle
        MOVE.L  (SP),-(SP)                      | dup saved clip region
        _SetClip                                | restore caller's clip
        _DisposeRgn                             | dispose temp clip region
        MOVE.B  (SP)+,(A4)                      | restore master ptr lock byte
        _SetPort                                | restore caller's grafPort
        MOVE    D4,D0                           | reload strip count
TECALTEXT_EXIT_3:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore working registers
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  D0,SP                           | SP += D0
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| TESetSelect -- _TESetSelect ($A9D1). Plus textedit.s 887.
| Set the current selection range (selStart, selEnd) and
| re-highlight.
TESetSelect:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.W   P_TERECAL_CONT_3                | erase old caret
        BSR.W   TEUPDATE_CONT_2                 | erase old hilite
        MOVE.L  (A2)+,teSelStart(A3)            | new selStart from param
        MOVE.L  (A2)+,30(A3)                    | new selEnd from param
        BSR.W   TETEXTHAND_LOCK_LEN             | relock text handle, refresh teLength
        BSR.W   P_TERECAL_NO_3                  | redraw caret
        BSR.W   TEUPDATE_CONT_2                 | redraw hilite
        BRA.B   TESETTEXT_EXIT                  | share TE epilog

| ----------------------------------------------------------
| TENew -- _TENew ($A9D2). Plus textedit.s 906.
| Allocate + initialize a new TERec handle from destRect/viewRect.
TENew:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save regs
        MOVEQ.L #teRecSize,D0                   | D0 = $68 = base TE record size
        _NewHandleClear                         | allocate + zero TE handle
        MOVE.L  A0,A4                           | A4 = TE handle
        BSET    #0x7,(A4)                       | lock TE master pointer
        MOVE.L  (A4),A3                         | A3 = dereferenced TE record
        MOVEQ.L #0x0,D0                         | zero-length text handle
        _NewHandle                              | allocate empty text handle
        MOVE.L   A0,62(A3)                      | store hText handle in TERec.hText
        LEA.L     (A3),A0                       | A0 = TERec.destRect base
        MOVE.L  0x2C(SP),A2                     | A2 = destRect ptr param
        MOVE.L  (A2)+,(A0)+                     | copy destRect topLeft
        MOVE.L  (A2)+,(A0)+                     | copy destRect botRight
        MOVE.L  0x28(SP),A2                     | A2 = viewRect ptr param
        MOVE.L  (A2)+,(A0)+                     | copy viewRect topLeft
        MOVE.L  (A2)+,(A0)+                     | copy viewRect botRight
        SUBQ.W  #0x8,SP                         | space for FontInfo struct
        MOVE.L  SP,-(SP)                        | push ptr for GetFontInfo
        _GetFontInfo                            | get current font metrics
        MOVE    (SP)+,D0                        | D0 = ascent
        MOVE    D0,26(A3)                       | set TERec.fontAscent
        ADD     (SP)+,D0                        | D0 += descent
        ADDQ.W  #0x2,SP                         | skip widMax field
        ADD     (SP)+,D0                        | D0 += leading = lineHeight
        MOVE    D0,24(A3)                       | store TERec.lineHeight
        MOVE.L  (A5),A2                         | A2 = QD globals base
        MOVE.L  (A2),A2                         | A2 = current grafPort ptr
        MOVE.L  A2,teInPort(A3)                 | set TERec.inPort
        MOVE.L  0x44(A2),0x4A(A3)               | copy port txFont/txFace
        MOVE.L  0x48(A2),teMode(A3)             | copy port txMode/txSize
        MOVE.L  (TEWdBreak).w,teWordBreak(A3)   | install default wordBreak hook
        BCLR    #0x7,(A4)                       | unlock TE master pointer
        MOVE.L  A4,0x30(SP)                     | return TE handle to caller
        MOVEQ.L #0x8,D0                         | strip 8 param bytes
        BRA.W   TECALTEXT_EXIT_3                | share TE epilog

| ----------------------------------------------------------
| TEUpdate -- _TEUpdate ($A9D3). Plus textedit.s 957.
| Redraw text within the update rectangle.
TEUpdate:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  (A2)+,A0                        | A0 = update rect ptr
        MOVE    (A0),D0                         | D0 = top
        MOVE    4(A0),D1                        | D1 = bottom
        BSR.W   XTRIMMEASURE_CONT_6_CONT        | redraw text in range
        BRA.W   TESCROLL_EXIT                   | -> common TE exit

| ----------------------------------------------------------
| TEUPDATE_CONT -- expand single click position D6 to word range D0-D1.
| On entry D2 holds the double-click flag (set by TEClick double-click
| detection); when zero, returns D0=D1=D6 (single char). When set,
| calls TEDELETE_CONT_CONT_3 to expand to word boundaries. Plus 968
| uses D5 (long, BPL test); classic uses D2 (byte, BEQ test).
TEUPDATE_CONT:
        MOVE    D6,D0                           | D0 = D6 (initial: single char)
        MOVE    D6,D1                           | D1 = D6
        TST.B   D2                              | double-click flag set?
        BEQ.B   TEUPDATE_EXIT                   | no -> return single char range
        BSR.W   TEDELETE_CONT_CONT_3            | expand D0-D1 to word boundaries
TEUPDATE_EXIT:
        RTS                                     | shared with TEUPDATE_CONT_2 bail

| ----------------------------------------------------------
| TEUPDATE_CONT_2
| Called during boot.
TEUPDATE_CONT_2:                                | call subroutine via A0
        TST.B   teActive(A3)                    | is TE record active?
        BEQ.B   TEUPDATE_EXIT                   | no -> nothing to highlight
        MOVEM   teSelStart(A3),D3-D4            | D3=teSelStart, D4=teSelEnd
        MOVEQ.L #0x1,D7                         | D7=1: highlight/unhighlight mode
        BRA.W   XTRIMMEASURE_OK_CONT_2          | -> draw/erase selection hilite

| ----------------------------------------------------------
| TEClick -- _TEClick ($A9D4). Plus textedit.s 996.
| Process a mouse click in the TE text area: hit-test, set
| selection, track mouse for double-click and drag-select.
TEClick:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  0x38(SP),28(A3)                 | store click point in teClikLoc
        BSR.W   TECLICK_CONT_5                  | hit-test point -> D6 = char offset
        BSR.W   P_TERECAL_CONT_3                | erase existing caret/hilite
        SUBQ.W  #0x4,SP                         | space for TickCount result
        _TickCount                              | get current tick count
        MOVE.L  (SP),D0                         | D0 = current ticks
        SUB.L   teClikTime(A3),D0               | D0 = elapsed since last click
        CMP.L   (DoubleTime).w,D0               | within double-click interval?
        SLE     D2                              | set if <=: D2
        CMP     teClikLoc(A3),D6                | same char position as last click?
        SEQ     D1                              | D1 = $FF if same position
        AND.B   D1,D2                           | D2 = double-click (time AND position)
        MOVE    D6,teClikLoc(A3)                | save click position for next time
        MOVE.L  (SP)+,teClikTime(A3)            | save click time
        TST.B   0x36(SP)                        | extend flag (shift-click)?
        BEQ.B   TECLICK_NO_2                    | no: start fresh selection
        MOVEM   teSelStart(A3),D0-D1            | D0=teSelStart, D1=teSelEnd
        CMP     D6,D0                           | click before selStart?
        BCC.B   TECLICK_NO                      | no: extend from selEnd
        MOVE    D0,A2                           | D3.W = old teSelEnd
        MOVE    D0,A4                           | teSelEnd = new end
        BRA.B   TECLICK_CONT                    | update with new position
TECLICK_NO:
        MOVE    D1,A2                           | A2 = anchor at selEnd
        MOVE    D1,A4                           | A4 = anchor at selEnd
TECLICK_CONT:
        MOVE    D6,D5                           | D3.W = old teSelStart
        BRA.B   TECLICK_CONT_2                  | update selection highlighting
TECLICK_NO_2:
        BSR.B   TEUPDATE_CONT_2                 | unhighlight current selection
        BSR.B   TEUPDATE_CONT                   | get word bounds if double-click
        MOVEM   D0-D1,teSelStart(A3)            | set teSelStart/teSelEnd
        MOVE    D0,A2                           | A2 = selection anchor start
        MOVE    D1,A4                           | A4 = selection anchor end
        MOVE    D6,D5                           | D5 = updated tracking position
        MOVE.B  0x46(A3),0x47(A3)               | save teLftClick to teLftCaret
        BSR.W   P_TERECAL_NO_3                  | set caret state if insertion point
        BSR.B   TEUPDATE_CONT_2                 | set up LINK frame, save regs
TECLICK_LOOP:
        MOVE.L  teClikProc(A3),D0               | D0 = click loop proc
        BEQ.B   TECLICK_EMPTY                   | nil -> use default WaitMouseUp
        MOVE.L  D0,A0                           | A0 = click loop proc
        JSR     (A0)                            | call subroutine via A0
        BEQ.B   TECLICK_CONT_4                  | app says stop: end tracking
TECLICK_EMPTY:
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | wait for mouse movement or release
        TST     (SP)+                           | still tracking?
        BEQ.B   TECLICK_CONT_4                  | mouse released: end tracking
        PEA.L     28(A3)                        | push ptr to teSelPoint
        _GetMouse                               | read current mouse position
        BSR.B   TECLICK_CONT_5                  | walk tree -> D6 = line index
        CMP     D6,D5                           | same line as last click?
        BEQ.B   TECLICK_LOOP                    | yes -> keep waiting
        BSR.W   P_TERECAL_CONT_3                | hide caret before hilite update
TECLICK_CONT_2:
        BSR.W   TEUPDATE_CONT                   | expand to word bounds if dbl-click
        LEA.L     teSelEnd(A3),A0               | A0 = &0x22(A3)
        CMPA.W  D6,A4                           | click before anchor end?
        BCS.B   TECLICK_OK                      | yes: extending forward
        MOVE    -(A0),D3                        | D3.W = old teSelStart
        MOVE    D0,(A0)+                        | teSelStart = new start
        MOVE    D0,D4                           | D4.W = new start
        SWAP    D3                              | D3: old selStart in high word
        SWAP    D4                              | D4: new start in high word
        MOVE    A4,D3                           | D3.W = anchor position
        MOVE    (A0)+,D4                        | D4.W = old teSelEnd
        MOVE    A4,-(A0)                        | teSelEnd = anchor
        BRA.B   TECLICK_CONT_3                  | XOR hilite for both ranges

| ----------------------------------------------------------
| TECLICK_OK
TECLICK_OK:
        CMPA.W  D6,A2                           | click still within anchor range?
        BHI.B   TECLICK_OK_2                    | yes -> no hilite change needed
        MOVE    (A0)+,D3                        | D3.W = old teSelEnd
        MOVE    D1,-(A0)                        | teSelEnd = new end
        MOVE    D1,D4                           | D4.W = new end
        SWAP    D3                              | D3: old selEnd in high word
        SWAP    D4                              | D4: new end in high word
        MOVE    -(A0),D3                        | D3.W = old teSelStart
        MOVE    A2,D4                           | D4.W = anchor start
        MOVE    A2,(A0)+                        | teSelStart = anchor
TECLICK_CONT_3:
        MOVEQ.L #0x1,D7                         | D7=1: highlight/unhighlight mode
        BSR.W   XTRIMMEASURE_OK_CONT_2          | XOR hilite for first changed range
        SWAP    D3                              | swap to second range pair
        SWAP    D4                              | swap to second range pair
        BSR.W   XTRIMMEASURE_OK_CONT_2          | XOR hilite for second changed range
TECLICK_OK_2:
        MOVE    D6,D5                           | D5 = updated tracking position
        BRA.B   TECLICK_LOOP                    | continue tracking loop
TECLICK_CONT_4:
        BSR.W   P_TERECAL_NO_3                  | set caret state if insertion point
        MOVEQ.L #0xA,D0                         | strip 10 param bytes
        BRA.W   TECALTEXT_EXIT_2                | share TE epilog

| TECLICK_CONT_5 -- convert point to char offset -> D6.
| ----------------------------------------------------------
| TECLICK_CONT_5
TECLICK_CONT_5:
        MOVE    28(A3),D0                       | D0 = click vertical coord
        BSR.W   XTRIMMEASURE_CONT_6             | convert to line number -> D0
        BGE.B   TECLICK_CONT_6                  | beyond last line -> selEnd
        ADD     D0,D0                           | word offset into lineStarts
        BLT.B   TECLICK_CONT_5_CONT_2           | before first line: offset 0
        MOVEM   0x60(A3,D0.W),D3-D4             | load 2 cached carets from D0 offset
        MOVEQ.L #0x0,D7                         | D7=0: pixel-to-char mode
        BSR.B   XTRIMMEASURE_OK_CONT_2          | find char offset at click.h
        MOVE    D0,D6                           | D6 = character offset at click
        RTS                                     | return measured offset
TECLICK_CONT_6:
        MOVE    teLength(A3),D6                 | click past end: D6 = teLength
        RTS                                     | return offset teLength
TECLICK_CONT_5_CONT_2:
        MOVEQ.L #0x0,D6                         | click before first line: offset 0
        RTS                                     | return offset 0
TECLICK_CONT_5_CONT_3:
        MOVE    24(A3),D0                       | D0 = lineHeight
        ADD     D0,16(A3)                       | 16(A3) += D0
        ADD     D0,20(A3)                       | 20(A3) += D0
        ADD     D0,0x30(A2)                     | 0x30(A2) += D0
        RTS                                     | return from line advance
TECLICK_CONT_5_CONT_4:
        MOVE    D3,-(SP)                        | save D3 (start char)
        MOVE    (A4),D3                         | D3 = next-line start char
        BSR.B   TECLICK_CONT_5_CONT_7           | measure line width -> D0
        MOVE    (SP)+,D3                        | restore D3
        MOVE    6(A3),D1                        | D1 = destRect.right
        SUB     2(A3),D1                        | D1 = destRect width
        SUB.W    D0,D1                          | D1 = slack pixels (width - text)
        SUBQ.W   #0x1,D1                        | leave 1px insertion margin
        TST     teJust(A3)                      | justification mode?
        BEQ.B   TECLICK_CONT_5_CONT_6           | left-justify: no shift
        BMI.B   TECLICK_CONT_5_CONT_5           | right-justify: full shift
        ASR     #0x1,D1                         | center-justify: half shift
TECLICK_CONT_5_CONT_5:
        ADD     D1,0x32(A2)                     | shift line origin by D1
TECLICK_CONT_5_CONT_6:
        ADDQ.W  #0x1,0x32(A2)                   | skip leading pixel margin
        RTS                                     | return from line origin compute
TECLICK_CONT_5_CONT_7:
        MOVE    D3,-(SP)                        | save D3 (line end char)
XTRIMMEASURE_OK:
        SUBQ.W  #0x1,D3                         | trim trailing char
        CMP     D3,D6                           | at line start?
        BEQ.B   XTRIMMEASURE_OK_CONT            | yes: empty line, exit
        MOVE    D3,A1                           | A1 = current end char
        BSR.W   TEFINDWORD_CONT_4               | test trailing char (space/CR)
        BNE.B   XTRIMMEASURE_OK                 | trim more trailing whitespace
XTRIMMEASURE_OK_CONT:
        ADDQ.W  #0x1,D3                         | restore last visible char
        BSR.B   XTRIMMEASURE_OK_OK              | measure visible width -> D0
        MOVE    (SP)+,D3                        | restore D3
        RTS                                     | return measured line width
XTRIMMEASURE_OK_OK:
        SUBQ.W  #0x2,SP                         | space for TextWidth result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),-(SP)                      | push text ptr
        MOVE    D6,-(SP)                        | push start offset
        MOVE    D3,-(SP)                        | push end offset
        SUB     D6,(SP)                         | length = end - start
        _TextWidth                              | measure pixel width
        MOVE    (SP)+,D0                        | D0 = measured width
        RTS                                     | return text width
| Called by: TECLICK_CONT_3, TEUPDATE_CONT_2, TECLICK_CONT_5, TEDELETE_CONT_NO, P_TERECAL_CONT_4 (and 1 more)
XTRIMMEASURE_OK_CONT_2:
        MOVE.L  (TEDoText).w,-(SP)              | push TEDoText hook for jump
        RTS                                     | jump via TEDoText hook
XTRIMMEASURE_OK_CONT_3:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save working registers
        MOVE.L  (A5),A2                         | A2 = QD globals base
        MOVE.L  (A2),A2                         | A2 = current grafPort ptr
        MOVE    (A3),D0                         | D0 = destRect.top
        MOVE    D0,16(A3)                       | set selRect.top
        ADD     24(A3),D0                       | add lineHeight
        MOVE    D0,20(A3)                       | set selRect.bottom
        MOVE.L  (A3),0x30(A2)                   | set port pen at destRect.topLeft
        MOVE    26(A3),D0                       | D0 = fontAscent
        ADD     D0,0x30(A2)                     | 0x30(A2) += D0
        CMP     D3,D4                           | D4 < D3 (range reversed)?
        BCC.B   XTRIMMEASURE_OK_CONT_4          | ordered: continue
        EXG     D4,D3                           | swap to make D3<=D4
XTRIMMEASURE_OK_CONT_4:
        LEA.L     0x60(A3),A4                   | A4 -> lineStarts[0]
XTRIMMEASURE_OK_CONT_5:
        MOVE    (A4)+,D6                        | D6 = current line start
        MOVE    (A4),D0                         | D0 = next line start
        CMP     teLength(A3),D0                 | past end of text?
        BCC.B   XTRIMMEASURE_OK_CONT_7          | yes: handle last line
        CMP     D0,D3                           | D3 before next line?
        BCS.B   XTRIMMEASURE_OK_NO              | yes: D3 is on this line
        BNE.B   XTRIMMEASURE_OK_CONT_6          | past line: skip ahead
        CMPI    #-0x2,D7                        | caret-mode (D7=-2)?
        BNE.B   XTRIMMEASURE_OK_CONT_6          | no: skip line
        TST.B   0x47(A3)                        | teLftCaret set?
        BEQ.B   XTRIMMEASURE_OK_NO              | no: caret on prev line
XTRIMMEASURE_OK_CONT_6:
        BSR.W   TECLICK_CONT_5_CONT_3           | advance pen down one line
        BRA.B   XTRIMMEASURE_OK_CONT_5          | loop to next line
XTRIMMEASURE_OK_CONT_7:
        CMPI.B  #0xFE,D7                        | caret-mode tail (D7=-2)?
        BNE.B   XTRIMMEASURE_OK_NO              | no: handle as range start
        MOVE.L  teTextH(A3),A0                  | hText handle
        MOVE.L  (A0),A0                         | dereference to text ptr
        MOVE.B  -0x1(A0,D0.W),D1                | D1 = last char before selection
        CMPI.B  #0xD,D1                         | compare D1 vs 0xD (CR)
        BNE.B   XTRIMMEASURE_OK_NO              | no CR: caret on prev line
        CMP     D3,D0                           | caret at exact end?
        BNE.B   XTRIMMEASURE_OK_NO              | no: prev line
        BSR.W   TECLICK_CONT_5_CONT_3           | advance pen to next line
        MOVE    (A4),D6                         | D6 = next line start
        BRA.B   XTRIMMEASURE_OK_CONT_8          | skip width measure
XTRIMMEASURE_OK_NO:
        BSR.W   XTRIMMEASURE_OK_OK              | measure width D6..D3 -> D0
        ADD     D0,0x32(A2)                     | advance pen by D0
XTRIMMEASURE_OK_CONT_8:
        BSR.W   TECLICK_CONT_5_CONT_4           | compute line origin (justify)
        MOVE    D3,D6                           | D6 = D3 (start of range)
        BRA.W   XTRIMMEASURE_OK_CONT_16         | enter measure/draw loop
XTRIMMEASURE_OK_CONT_9:
        CMP     (A4),D6                         | at next line start?
        BCS.B   XTRIMMEASURE_OK_CONT_10         | no: stay on this line
        ADDQ.W  #0x2,A4                         | advance lineStarts ptr
        MOVE    0x30(A2),D0                     | D0 = pen.v
        CMP     12(A3),D0                       | past viewRect bottom?
        BGT.W   XTRIMMEASURE_OK_OK_2            | yes: stop drawing
        BSR.W   TECLICK_CONT_5_CONT_3           | advance pen down one line
        MOVE    2(A3),0x32(A2)                  | reset pen.h to destRect.left
        BSR.W   TECLICK_CONT_5_CONT_4           | recompute line origin
XTRIMMEASURE_OK_CONT_10:
        MOVE    0x32(A2),18(A3)                 | set selRect.left = pen.h
        MOVE    0x32(A2),(scratch8).w           | save pen.h to scratch
        TST     D7                              | dispatch on mode
        BNE.B   XTRIMMEASURE_OK_NO_2            | not measure: continue
        MOVE    D6,D3                           | measure mode: D3 = D6
        ADDQ.W  #0x1,D3                         | advance one char
        BRA.B   XTRIMMEASURE_OK_CONT_12         | measure to D3
XTRIMMEASURE_OK_NO_2:
        CMP     (A4),D4                         | D4 within this line?
        BCC.B   XTRIMMEASURE_OK_CONT_11         | no: clamp to line end
        MOVE    D4,D3                           | yes: D3 = D4
        BRA.B   XTRIMMEASURE_OK_CONT_12         | measure to D3
XTRIMMEASURE_OK_CONT_11:
        MOVE    (A4),D3                         | clamp D3 to line end
XTRIMMEASURE_OK_CONT_12:
        BSR.W   XTRIMMEASURE_OK_OK              | measure width D6..D3 -> D0
        MOVE    D0,D2                           | D2 = measured width
        ADD     0x32(A2),D0                     | D0 = right edge x
        MOVE    D0,D5                           | D5 = right edge
        MOVE    D0,-(SP)                        | save right edge
        MOVE    D0,22(A3)                       | set selRect.right
        CMP     -2(A4),D6                       | at start of line?
        BNE.B   XTRIMMEASURE_OK_NO_3            | no: keep selRect.left
        MOVE    #-0x7FFE,18(A3)                 | extend selRect.left to -32766
        ADD     D5,D5                           | D5 *= 2
        SUB     (scratch8).w,D5                 | D5 -= start pen.h
        SUB     D2,D5                           | D5 -= width (= 2*right - origin)
XTRIMMEASURE_OK_NO_3:
        CMP     (A4),D3                         | at end of line?
        BNE.B   XTRIMMEASURE_OK_CONT_13         | no: keep selRect.right
        MOVE    #0x7FFE,22(A3)                  | extend selRect.right to 32766
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | A0 = text data ptr
        CMPI.B  #0xD,0(A0,D6.W)                 | first char is CR?
        BNE.B   XTRIMMEASURE_OK_CONT_13         | no: skip
        MOVE    #0x7000,D5                      | set "wraps" flag in D5
XTRIMMEASURE_OK_CONT_13:                        | jump via A0
        TST     D7                              | dispatch on mode
        BPL.B   XTRIMMEASURE_OK_CONT_14         | positive: not draw
        PEA.L     16(A3)                        | push selRect for EraseRect
        _EraseRect                              | erase selRect first
        MOVEA.L teTextH(A3),A0                  | A0 = hText (text handle)
        MOVE.L  (A0),-(SP)                      | push dereferenced text ptr
        MOVE    D6,-(SP)                        | push start char index
        MOVE    D3,-(SP)                        | push end char index
        SUB     D6,(SP)                         | (SP) -= D6
        _DrawText                               | draw text from D6 to D3
XTRIMMEASURE_OK_CONT_14:
        MOVE    D3,D6                           | advance D6 = D3
        MOVE    (SP)+,0x32(A2)                  | restore pen.h to right edge
        TST     D7                              | dispatch on mode
        BLE.B   XTRIMMEASURE_OK_CONT_15         | not highlight mode
        MOVE.L  teHighHook(A3),D0               | D0 = custom hilite hook
        BSR.B   XTRIMMEASURE_CONT_7             | invert selRect
XTRIMMEASURE_OK_CONT_15:
        TST     D7                              | dispatch on mode
        BNE.B   XTRIMMEASURE_OK_CONT_16         | not hit-test
        CLR     -(SP)                           | space for PtInRect result
        MOVE.L  28(A3),-(SP)                    | push teSelPoint
        PEA.L     16(A3)                        | push selRect
        _PtInRect                               | point in this char rect?
        TST.B   (SP)+                           | test result
        BEQ.B   XTRIMMEASURE_OK_CONT_16         | no: try next
        SF      0x46(A3)                        | teLftClick = false (right side)
        SUB     30(A3),D5                       | D5 -= teSelPoint.h
        SUB     30(A3),D5                       | D5 -= again (margin check)
        ADD     (scratch8).w,D5                 | D5 += saved pen.h
        BLT.B   XTRIMMEASURE_OK_OK_2            | click on right half: keep
        SUBQ.W  #0x1,D6                         | click on left half: D6--
        ST      0x46(A3)                        | teLftClick = true (left side)
        BRA.B   XTRIMMEASURE_OK_OK_2            | return found offset
XTRIMMEASURE_OK_CONT_16:
        CMP     D4,D6                           | past end of range?
        BCC.B   XTRIMMEASURE_OK_CONT_17         | yes: done
        CMP     teLength(A3),D6                 | past end of text?
        BCS.W   XTRIMMEASURE_OK_CONT_9          | no: continue
XTRIMMEASURE_OK_CONT_17:
        MOVEQ.L #0x0,D6                         | return D0=0 (not found)
XTRIMMEASURE_OK_OK_2:
        MOVE    D6,D0                           | D0 = char offset (return)
        MOVE.L  A2,A0                           | A0 = grafPort ptr
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore working registers
        RTS                                     | return from TEDoText

| ----------------------------------------------------------
| XTRIMMEASURE_CONT_7
| Called during boot.
XTRIMMEASURE_CONT_7:
        PEA.L     16(A3)                        | push selection rect for hilite
        BEQ.B   XTRIMMEASURE_NO_5               | D0=0 (no hook) -> use InvertRect
        MOVE.L  D0,A0                           | A0 = custom highlight hook
        JMP     (A0)                            | call hook with rect on stack
XTRIMMEASURE_NO_5:
        _InvertRect                             | default: XOR-invert selRect
        RTS                                     | return from highlight
XTRIMMEASURE_CONT_12:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVEM.L D2-D7/A2-A4,-(SP)               | save working registers
        SUBA.W  #0xA,SP                         | SP -= #0xA
        MOVE.L  A0,-(SP)                        | re-push return address
        MOVE.L  0x36(SP),A4                     | A4 = TEHandle from caller
        MOVE.L  (A4),A3                         | A3 = dereferenced TERec
        MOVE.B  (A4),8(SP)                      | save handle lock byte
        PEA.L     10(SP)                        | push ptr for GetPort
        _GetPort                                | save current grafPort
        BSET    #0x7,(A4)                       | lock TE master pointer
        MOVE.L  teInPort(A3),A2                 | A2 = TE's grafPort
        MOVE.L  A2,-(SP)                        | push port for SetPort
        _SetPort                                | switch to TE's grafPort
        SUBQ.W  #0x4,SP                         | space for NewRgn result
        _NewRgn                                 | allocate scratch region
        MOVE.L  (SP),8(SP)                      | save scratch region in frame
        MOVE.L  (SP),-(SP)                      | push region for GetClip
        _GetClip                                | save current clip into region
        PEA.L     8(A3)                         | push viewRect address
        _ClipRect                               | set clip = TE viewRect
        MOVE.L  28(A2),-(SP)                    | push current port clip rgn
        MOVE.L  (SP),-(SP)                      | dup as dest for SectRgn
        _SectRgn                                | intersect with viewRect
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = current grafPort
        MOVE.L  0x4A(A3),0x44(A0)               | copy TE txFont/txFace to port
        MOVE.L  teMode(A3),0x48(A0)             | copy TE txMode/txSize to port
TETEXTHAND_LOCK_LEN:                            | lock text handle + cache length
        MOVE.L  teTextH(A3),A0                  | A0 = hText (text handle)
        _HLock                                  | lock it down
        _GetHandleSize                          | D0 = text length
        MOVE    D0,teLength(A3)                 | store in teLength
        MOVE    teSelEnd(A3),D1                 | D1 = selEnd
        SUB     D0,D1                           | D1 = selEnd - length
        BLS.B   XTRIMMEASURE_CONT_7_OK          | selEnd <= length -> OK
        MOVE    D0,teSelEnd(A3)                 | clamp selEnd to text length
XTRIMMEASURE_CONT_7_OK:
        MOVE    teSelStart(A3),D1               | D1 = selStart
        SUB     teSelEnd(A3),D1                 | D1 = selStart - selEnd
        BLS.B   XTRIMMEASURE_CONT_7_OK_2        | selStart <= selEnd -> OK
        SUB     D1,teSelStart(A3)               | clamp selStart to selEnd
XTRIMMEASURE_CONT_7_OK_2:
        BSR.B   XTRIMMEASURE_CONT_15            | normalize: ensure selStart <= selEnd
        LEA.L     0x3A(SP),A2                   | A2 -> caller's params on stack
        RTS                                     | return from selection range normalization

| ----------------------------------------------------------
| XTRIMMEASURE_CONT_15
| Called during boot (2,779 times in 30s trace).
XTRIMMEASURE_CONT_15:
        LEA.L     teSelStart(A3),A2             | A2 -> teSelStart (offset 0x20)
        MOVE.L  (A2),D0                         | D0 = selStart.W | selEnd.W
        CMP     (A2),D0                         | compare selEnd (D0.W) with selStart
        BCC.B   XTRIMMEASURE_OK_6               | selEnd >= selStart -> OK
        SWAP    D0                              | swap selStart and selEnd
        MOVE.L  D0,(A2)                         | store normalized pair
XTRIMMEASURE_OK_6:
        RTS                                     | return to caller (@ $F8BC)

| ----------------------------------------------------------
| TECopy -- _TECopy ($A9D5). Plus textedit.s 1712.
| Copy selection to TEScrap. Doesn't modify the TERec.
TECopy:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.B   XTRIMMEASURE_CONT_15            | dereference text/lock handle
        SUB     (A2),D0                         | D0 = selEnd - selStart
        MOVE    D0,(TEScrpLength).w             | TEScrpLength = sel length
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | A0 = text pointer
        ADDA.W  (A2),A0                         | A0 += selStart
        MOVE.L  (TEScrpHandle).w,A1             | A1 = TEScrpHandle
        MOVEQ.L #0x0,D0                         | zero-extend length
        MOVE    (TEScrpLength).w,D0             | D0 = sel length (re-read)
        _PtrToXHand                             | copy selection to scrap
TECOPY_EXIT:
        BRA.W   TECALTEXT_EXIT                  | share TE common epilog

| ----------------------------------------------------------
| TECut -- _TECut ($A9D6). Plus textedit.s 1733.
| Cut: TECopy + TEDelete.
TECut:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  A4,-(SP)                        | push TE handle for TECopy
        MOVE.L  A4,-(SP)                        | push TE handle for TEDelete
        _TECopy                                 | copy to TEScrap
        _TEDelete                               | remove from TERec
        BRA.B   TECOPY_EXIT                     | -> common TE epilog

| ----------------------------------------------------------
| TEDelete -- _TEDelete ($A9D7). Plus textedit.s 1746.
| Remove the selection range from the text and recalc lines.
TEDelete:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.W   P_TERECAL_CONT_3                | hide caret if visible
        BSR.B   TEDELETE_CONT                   | remove selected text
        BSR.B   TEDELETE_CONT_CONT_2            | recalc lines + erase area
        BSR.W   P_TERECAL_NO_3                  | redraw affected lines
        BRA.B   TECOPY_EXIT                     | -> common TE epilog

| TEDELETE_CONT -- remove selected text from buffer.
| ----------------------------------------------------------
| TEDELETE_CONT
TEDELETE_CONT:
        BSR.B   XTRIMMEASURE_CONT_15            | normalize selStart<=selEnd
        MOVE    D0,D7                           | D7 = selEnd
        SUB     (A2),D7                         | D7 = selEnd - selStart
        BEQ.B   TEDELETE_EMPTY                  | empty selection: nothing to do
        SUBQ.L  #0x4,SP                         | space for Munger result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  A0,-(SP)                        | push handle for HUnlock
        _HUnlock                                | unlock text before resize
        MOVE    (A2),-(SP)                      | push offset = selStart
        CLR     -(SP)                           | zero-extend offset
        CLR.L   -(SP)                           | ptr1 = nil (no search)
        MOVE    D7,-(SP)                        | push len1 = selection length
        CLR     -(SP)                           | zero-extend len
        CLR.L   -(SP)                           | ptr2 = nil
        CLR.L   -(SP)                           | len2 = 0 (delete only)
        _Munger                                 | delete D7 bytes at selStart
        ADDQ.L  #0x4,SP                         | discard Munger result
        SUB     D7,teLength(A3)                 | teLength(A3) -= D7
        MOVE    (A2)+,(A2)                      | selEnd = selStart (collapse)
TEDELETE_EMPTY:
        RTS                                     | return from delete
TEDELETE_CONT_CONT_2:
        MOVEQ.L #0x0,D2                         | D2 = 0 (start char)
        MOVE    teLength(A3),D4                 | D4 = teLength (end char)
        BSR.W   TEFINDWORD_CONT_4_CONT_8        | recalc lineStarts D2..D4
        MOVE    D2,D3                           | D3 = first changed line
        MOVE    0x5E(A3),D0                     | D0 = nLines
        MULU    24(A3),D0                       | D0 = D0 *u 24(A3)
        LEA.L     20(A3),A0                     | A0 -> selRect.bottom
        MOVE.L  #0x7FF07FF0,(A0)                | store long via (An)
        MOVE.L  (A3),-(A0)                      | set selRect topLeft = destRect
        ADD     D0,(A0)                         | (A0) += D0
        MOVE.L  A0,-(SP)                        | push selRect for EraseRect
        _EraseRect                              | call subroutine via A1
        TST     teJust(A3)                      | test teActive / style flag @ +0x3A
        BNE.B   TEDELETE_CONT_NO                | not left-justify: skip
        BSR.B   TEDELETE_CONT_OK                | expand D3 to word start
        MOVE    D0,D3                           | D3 = adjusted start char
        BEQ.B   TEDELETE_CONT_NO                | at start: keep
        SUBQ.W  #0x1,D3                         | step back to word boundary
TEDELETE_CONT_NO:
        MOVEQ.L #-0x1,D7                        | D7=-1: draw mode
        BRA.W   XTRIMMEASURE_OK_CONT_2          | redraw range D3..D4
TEDELETE_CONT_OK:
        MOVE    teSelStart(A3),D0               | D0 = selStart
TEDELETE_CONT_CONT_3:
        MOVE    D0,D1                           | D1 = D0 (end of word)
        BEQ.B   TEFINDWORD_CONT                 | at start: scan forward
TEDELETE_CONT_CONT_4:
        SUBQ.W  #0x1,D0                         | step back one char
        BLS.B   TEFINDWORD_CONT                 | branch if <= (unsigned)
        MOVE    D0,A1                           | A1 = char offset
        BSR.B   TEFINDWORD_CONT_4               | test word break at A1
        BEQ.B   TEDELETE_CONT_CONT_4            | not break: keep stepping back
        ADDQ.W  #0x1,D0                         | move to first non-break char
TEFINDWORD_CONT:
        CMP     teLength(A3),D1                 | past end of text?
        BCC.B   TEFINDWORD_DONE                 | yes: done
        MOVE    D1,A1                           | A1 = char offset for word break test
        BSR.B   TEFINDWORD_CONT_4               | test word break at D1
        BNE.B   TEFINDWORD_DONE                 | is word break -> found end
        ADDQ.W  #0x1,D1                         | advance to next character
        BRA.B   TEFINDWORD_CONT                 | -> keep scanning forward
TEFINDWORD_DONE:
        RTS                                     | return to caller (@ $F98C)
| ----------------------------------------------------------
| TEFINDWORD_CONT_4
| Called during boot.
TEFINDWORD_CONT_4:
        MOVEM.L D0/A0-A1,-(SP)                  | save registers
        MOVE    A1,D0                           | D0 = char offset to test

| === TextEdit routines continued (from ROM layout after packages) ===
| Package Manager and Standard Packages
| The Package Manager loads and calls code packages from resources.
| Packages in ROM include:
| PACK 4: FP68K (Floating-Point Arithmetic)
| PACK 5: Elems68K (Transcendental Functions)
| PACK 7: DecStr68K (Binary-Decimal Conversion)
| References:
| Inside Macintosh Vol I, Ch 17: The Package Manager
| Inside Macintosh Vol II, Ch 15: FP Arithmetic and Transcendental Packages

| Package Manager & packages
| ROM section: src/toolbox/packages.asm
        MOVE.L  teTextH(A3),A0                  | A0 = teTextH (text handle)
        MOVE.L  (A0),A0                         | A0 = dereferenced text ptr
        MOVE.L  teWordBreak(A3),A1              | A1 = teWordBreak proc ptr
        JSR     (A1)                            | call word break: Z=not break, NZ=break
        MOVEM.L (SP)+,D0/A0-A1                  | restore registers (CC preserved)
        RTS                                     | return result of word break callback
TEFINDWORD_CONT_4_CONT:
        CMPI.B  #0x20,0(A0,D0.W)                | char <= space (whitespace)?
        SLS     D0                              | D0 = $FF if word break
        TST.B   D0                              | set Z flag from D0
        RTS                                     | return Z=word, NZ=break
TEFINDWORD_CONT_4_NEXT:
        MOVEM.L D1-D7/A1-A2,-(SP)               | save working registers
        MOVE    6(A3),A2                        | A2 = destRect.right
        SUBA.W  2(A3),A2                        | A2 = destRect width
        SUBQ.W  #0x1,A2                         | leave 1 pixel margin
        MOVEQ.L #-0x2,D5                        | D5 = -2 (initial line start)
        MOVEQ.L #-0x1,D7                        | D7 = -1 (no last word break)
TEFINDWORD_CONT_4_CONT_2:
        MOVE    D6,D3                           | D3 = current scan offset
TEFINDWORD_CONT_4_CONT_3:
        CMP     teLength(A3),D3                 | past end of text?
        BCC.B   TEFINDWORD_CONT_4_CONT_6        | yes: end of last line
        TST.B   0x48(A3)                        | crOnly mode (no word wrap)?
        BNE.B   TEFINDWORD_CONT_4_NO            | yes: skip wrap logic
        TST     D7                              | any prior word break seen?
        BEQ.B   TEFINDWORD_CONT_4_CONT_4        | no: scan from D3
        MOVE    D3,D0                           | D0 = current offset
        BSR.B   TEDELETE_CONT_CONT_3            | find next word boundary -> D1
        BRA.B   TEFINDWORD_CONT_4_CONT_5        | measure that range
TEFINDWORD_CONT_4_CONT_4:
        MOVE    D3,D1                           | D1 = D3
        ADDQ.W  #0x1,D1                         | advance one char
TEFINDWORD_CONT_4_CONT_5:
        MOVE    D1,D3                           | D3 = candidate end of line
        BSR.W   TECLICK_CONT_5_CONT_7           | measure width D6..D3 -> D0
        CMP     A2,D0                           | fits within destRect width?
        BGE.B   TEFINDWORD_CONT_4_CONT_7        | no: wrap before this word
TEFINDWORD_CONT_4_NO:
        MOVE    D3,D5                           | store new lineStart; advance
        MOVE.L  teTextH(A3),A0                  | D6 = start of next line
        MOVE.L  (A0),A0                         | A0 = text data ptr
        CMPI.B  #0xD,0(A0,D3.W)                 | CR at D3?
        BEQ.B   TEFINDWORD_CONT_4_CONT_7        | yes: hard line break
        ADDQ.W  #0x1,D3                         | advance scan offset
        BRA.B   TEFINDWORD_CONT_4_CONT_3        | continue scanning
TEFINDWORD_CONT_4_CONT_6:
        MOVE    teLength(A3),D5                 | D5 = end of last line
        SUBQ.W  #0x1,D5                         | step back to last char
TEFINDWORD_CONT_4_CONT_7:
        MOVEQ.L #0x0,D7                         | D7 = 0 (line wrapped)
        ADDQ.W  #0x1,D5                         | D5 = next line start offset
        BMI.B   TEFINDWORD_CONT_4_CONT_2        | overflow: continue scan
        MOVE    D5,D0                           | D0 = next line start (return)
        MOVEM.L (SP)+,D1-D7/A1-A2               | restore working registers
        RTS                                     | return next lineStart in D0
TEFINDWORD_CONT_4_CONT_8:
        MOVE.L  (TERecal).w,-(SP)               | push TERecal hook for jump
        RTS                                     | jump via TERecal hook
TEFINDWORD_CONT_4_CONT_9:
        LINK    A6,#0x0                         | set up local frame
        MOVEM.L D2-D6/A2,-(SP)                  | save working registers
        LEA.L     0x5E(A3),A2                   | A2 -> nLines field
        CLR     (A2)+                           | clear nLines = 0
        BSR.W   TEDELETE_CONT_OK                | find first wrap region start
        MOVE    D0,D3                           | D3 = first changed char
        BEQ.B   TEFINDWORD_CONT_4_CONT_11       | at start: empty preserved
        SUBQ.W  #0x1,D3                         | back up one char
TEFINDWORD_CONT_4_CONT_10:
        MOVE    (A2)+,D6                        | D6 = old lineStart, A2++
        MOVE    D6,-22(A6)                      | save D6 to local frame
        MOVE    (A2),D0                         | D0 = next old lineStart
        CMP     teLength(A3),D0                 | past end?
        BCC.B   TEFINDWORD_CONT_4_CONT_13       | yes: stop preserving
        CMP     D0,D3                           | line still before D3?
        BCS.B   TEFINDWORD_CONT_4_CONT_13       | no: must recalc this one
        ADDQ.W  #0x1,0x5E(A3)                   | count preserved line
        BRA.B   TEFINDWORD_CONT_4_CONT_10       | advance to next line
TEFINDWORD_CONT_4_CONT_11:
        MOVE    (A2)+,D6                        | D6 = old lineStart, A2++
        BRA.B   TEFINDWORD_CONT_4_CONT_13       | enter recalc loop
TEFINDWORD_CONT_4_CONT_12:
        CMP     teLength(A3),D6                 | past end of text?
        BCC.B   P_TERECAL_DONE_2                | yes -> done recalculating
TEFINDWORD_CONT_4_CONT_13:
        BSR.W   TEFINDWORD_CONT_4_NEXT          | find next line break -> D0
        MOVE    D0,D3                           | D3 = new line start
        CMP     teSelEnd(A3),D3                 | past teSelEnd?
        BLS.B   TEFINDWORD_CONT_4_NO_2          | no -> keep inserting new lines
        SUB     D3,(A2)                         | compute delta from old lineStart
        CMP     (A2),D7                         | delta matches insertion offset?
        BEQ.B   TEFINDWORD_CONT_4_OK            | yes -> remaining lines just need adjustment
TEFINDWORD_CONT_4_NO_2:
        BSR.B   P_TERECAL_NEXT_3                | grow handle if needed; bump nLines
        MOVE    D3,(A2)+                        | store new lineStart, A2++
        MOVE    D3,D6                           | D6 = new lineStart
        BRA.B   TEFINDWORD_CONT_4_CONT_12       | -> draw caret
TEFINDWORD_CONT_4_OK:
        MOVE    D3,-14(A6)                      | save new lineStart in frame
        ADD     D3,(A2)                         | (A2) += D3
P_TERECAL_NO_2:
        BSR.B   P_TERECAL_NEXT_3                | grow handle if needed; bump nLines
        SUB     D7,(A2)                         | adjust old lineStart by removed chars
        MOVE    (A2)+,D6                        | D6 = adjusted lineStart; advance
        CMP     teLength(A3),D6                 | past end of text?
        BCS.B   P_TERECAL_NO_2                  | no -> keep adjusting remaining lines
P_TERECAL_DONE_2:
        BSR.B   P_TERECAL_NEXT_3                | ensure space for sentinel entry
        MOVE    D6,-(A2)                        | store final lineStart (sentinel)
        SUBQ.W  #0x1,0x5E(A3)                   | adjust nLines (subtract extra count)
        TST     teLength(A3)                    | is text empty?
        BNE.B   P_TERECAL_DONE_3                | has text: keep nLines
        CLR     0x5E(A3)                        | empty text -> nLines = 0
P_TERECAL_DONE_3:
        MOVEM.L (SP)+,D2-D6/A2                  | restore registers
        UNLK    A6                              | tear down frame
        RTS                                     | return from sentinel entry insertion
P_TERECAL_NEXT_3:
        ADDQ.W  #0x1,0x5E(A3)                   | bump nLines counter
        MOVE.L  A4,A0                           | A0 = TE handle
        _GetHandleSize                          | D0 = current TE handle size
        MOVE.L  D0,D1                           | D1 = current size
        MOVEQ.L #teRecSize,D0                   | base TE record size
        ADD     0x5E(A3),D0                     | + nLines * 2 (lineStarts[])
        ADD     0x5E(A3),D0                     | ... twice because each lineStart is 2 bytes
        CMP.L   D0,D1                           | need to grow handle?
        BGE.B   P_TERECAL_DONE_4                | no: enough space already
        SUBA.L  A3,A2                           | A2 = offset into TERec
        ADDQ.W  #0x8,D0                         | add slack for future lines
        BCLR    #0x7,(A4)                       | unlock TE handle for resize
        _SetHandleSize                          | grow TE handle
        _HLock                                  | re-lock TE handle
        MOVE.L  (A4),A3                         | A3 = new TERec base
        ADDA.L  A3,A2                           | A2 = restored ptr in new base
P_TERECAL_DONE_4:
        RTS                                     | return from grow check

| P_TERECAL_NO_3 -- set caret state.
| ----------------------------------------------------------
| P_TERECAL_NO_3
| Called by: TESetSelect, TECLICK_NO_2, TECLICK_CONT_4, TEDelete, P_TERECAL_CONT_4_CONT (and 2 more)
P_TERECAL_NO_3:
        TST.B   teActive(A3)                    | is TE active?
        BEQ.B   P_TERECAL_DONE_4                | inactive: skip caret
        MOVE    teSelStart(A3),D0               | D0 = selStart
        CMP     teSelEnd(A3),D0                 | insertion point?
        BNE.B   P_TERECAL_DONE_4                | has selection: no caret
        LEA.L     teCarAct(A3),A0               | A0 = &0x39(A3)
        ST      (A0)                            | (A0) := -1 (true)
        TST.B   -(A0)                           | caret already shown?
        BNE.B   P_TERECAL_DONE_4                | yes: skip toggle
        ST      (A0)                            | (A0) := -1 (true)
P_TERECAL_OK_3:                                 | BRA.W reach-extender
        BRA.B   P_TERECAL_CONT_4                | draw caret (XOR)
| Called by: TESetSelect, TEClick, TECLICK_EMPTY, TEDelete, TEDeactivate (and 4 more)
P_TERECAL_CONT_3:
        TST.B   teActive(A3)                    | is TE active?
        BEQ.B   P_TERECAL_DONE_4                | inactive: nothing to erase
        LEA.L     teCarAct(A3),A0               | A0 = &0x39(A3)
        SF      (A0)                            | set false (=0): (A0)
        TST.B   -(A0)                           | was caret showing?
        BEQ.B   P_TERECAL_DONE_4                | no: nothing to erase
        SF      (A0)                            | set false (=0): (A0)

| P_TERECAL_CONT_4 -- draw/erase caret (XOR).
P_TERECAL_CONT_4:
        MOVEM.L D0-D7,-(SP)                     | save data registers
        MOVE    teSelStart(A3),D3               | D3 = selStart (caret pos)
        MOVE    D3,D4                           | D4 = D3 (zero-width range)
        MOVEQ.L #-0x2,D7                        | D7=-2: caret mode
        BSR.W   XTRIMMEASURE_OK_CONT_2          | compute caret rect on this line
        MOVE    0x32(A0),D0                     | D0 = pen.h (caret x)
        MOVE    D0,22(A3)                       | store caret rect right
        SUBQ.W  #0x1,D0                         | caret is 1 pixel wide
        MOVE    D0,18(A3)                       | store caret rect left
        MOVE.L  0x5A(A3),D0                     | D0 = teCaretHook
        BSR.W   XTRIMMEASURE_CONT_7             | invert caret rect
        MOVEM.L (SP)+,D0-D7                     | restore data registers
        RTS                                     | return from caret toggle

| ----------------------------------------------------------
| TEActivate -- _TEActivate ($A9D8). Plus textedit.s 2178.
| Activate a TERec: enable caret blink (if no selection),
| set teActive flag, redraw highlight.
TEActivate:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        TST.B   teActive(A3)                    | already active?
        BNE.B   TEACTIVATE_OK                   | yes -> nothing to do
        MOVE    teSelStart(A3),D0               | D0 = teSelStart
        CMP     teSelEnd(A3),D0                 | insertion point? (selStart == selEnd)
        BNE.B   TEACTIVATE_NO                   | no -> has selection
        ST      teCarAct(A3)                    | teCarAct = true (enable caret)
TEACTIVATE_NO:
        ST      teActive(A3)                    | teActive(A3) := -1 (true)
        BSR.W   TEUPDATE_CONT_2                 | redraw selection highlight
TEACTIVATE_OK:
        BRA.B   TEIDLE_EXIT                     | share TE common epilog

| ----------------------------------------------------------
| TEDeactivate -- _TEDeactivate ($A9D9). Plus textedit.s 2197.
| Deactivate a TERec: hide caret, unhighlight, clear teActive.
TEDeactivate:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        TST.B   teActive(A3)                    | already inactive?
        BEQ.B   TEIDLE_EXIT                     | already inactive: skip
        BSR.B   P_TERECAL_CONT_3                | hide caret
        BSR.W   TEUPDATE_CONT_2                 | unhighlight selection
        SF      teActive(A3)                    | clear teActive
        BRA.B   TEIDLE_EXIT                     | share TE common epilog

| ----------------------------------------------------------
| TEIdle -- _TEIdle ($A9DA). Plus textedit.s 2212.
| Blink the caret if its time has come.
TEIdle:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (A3=TERec)
        TST.B   teCarAct(A3)                    | caret enabled?
        BEQ.B   TEIDLE_EXIT                     | caret disabled: nothing to do
        SUBQ.W  #0x4,SP                         | room for tick count result
        _TickCount                              | get current tick count
        MOVEA.L (SP)+,A0                        | A0 = current ticks
        CMPA.L  teCarTime(A3),A0                | time to blink yet?
        BCS.B   TEIDLE_EXIT                     | no -> wait
        ADDA.L  (CaretTime).w,A0                | schedule next blink
        MOVE.L  A0,teCarTime(A3)                | save next blink time
        BSR.W   P_TERECAL_CONT_4                | XOR caret
        NOT.B   teCarOn(A3)                     | flip caret-on flag
TEIDLE_EXIT:
        BRA.W   TECALTEXT_EXIT                  | share TE common epilog

| ----------------------------------------------------------
| TEPaste -- _TEPaste ($A9DB). Plus textedit.s 2232.
| Insert TEScrap at the selection.
TEPaste:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  (TEScrpHandle).w,A1             | A1 = scrap handle
        BSET    #0x7,(A1)                       | lock scrap handle
        MOVE.L  (A1),D6                         | D6 = dereferenced scrap text ptr
        MOVEQ.L #0x0,D5                         | clear high word
        MOVE    (TEScrpLength).w,D5             | D5 = scrap length
        BSR.B   P_TERECAL_CONT_4_CONT           | insert scrap text, replacing selection
        MOVE.L  (TEScrpHandle).w,A1             | A1 = scrap handle
        BCLR    #0x7,(A1)                       | unlock scrap handle
        BRA.B   TEIDLE_EXIT                     | -> TE exit
P_TERECAL_CONT_4_CONT:
        BSR.W   P_TERECAL_CONT_3                | hide caret if visible
        BSR.W   TEUPDATE_CONT_2                 | unhighlight current selection
        BSR.W   TEDELETE_CONT                   | delete selected text
        BSR.B   P_TERECAL_CONT_4_CONT_2         | insert D6[D5] at selStart
        BSR.W   TEDELETE_CONT_CONT_2            | recalc lines + erase area
        LEA.L     teSelStart(A3),A0             | A0 = &0x20(A3)
        ADD     D5,(A0)                         | (A0) += D5
        MOVE    (A0)+,(A0)                      | selEnd = selStart (collapse)
        BSR.W   P_TERECAL_NO_3                  | set caret state
        RTS                                     | return from paste/insert
P_TERECAL_CONT_4_CONT_2:
        SUBQ.L  #0x4,SP                         | space for Munger result
        MOVE.L  teTextH(A3),A0                  | D0 = selStart
        MOVE.L  A0,-(SP)                        | push handle for HUnlock
        _HUnlock                                | unlock text before Munger
        MOVE    teSelStart(A3),-(SP)            | push offset = selStart
        CLR     -(SP)                           | zero-extend offset
        CLR.L   -(SP)                           | ptr1 = nil (no search)
        CLR.L   -(SP)                           | len1 = 0 (insert only)
        MOVE.L  D6,-(SP)                        | push insert ptr (D6)
        MOVE.L  D5,-(SP)                        | push TEHandle
        _Munger                                 | insert D5 bytes at selStart
        ADDQ.L  #0x4,SP                         | discard Munger result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        _HLock                                  | re-lock text handle
        ADD     D5,teLength(A3)                 | teLength(A3) += D5
        SUB     D5,D7                           | D7 -= D5 (delete delta)
        RTS                                     | return from text insert

| ----------------------------------------------------------
| TEInsert -- _TEInsert ($A9DE). Plus textedit.s 2344.
| Insert text at the current selection point. If selection is
| not empty, the selected text is deleted first.
TEInsert:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (12 bytes params)
        BSR.W   P_TERECAL_CONT_3                | hide caret
        BSR.W   TEUPDATE_CONT_2                 | unhighlight selection
        MOVEQ.L #0x0,D7                         | D7 = 0 (no chars deleted)
        MOVEM.L (A2)+,D5-D6                     | D5=text length, D6=text ptr (params)
        BSR.B   P_TERECAL_CONT_4_CONT_2         | _Munger to insert
        BSR.W   TEDELETE_CONT_CONT_2            | recalculate lines and redraw
        ADD     D5,teSelStart(A3)               | teSelStart += inserted length
        ADD     D5,teSelEnd(A3)                 | teSelEnd += inserted length
        BSR.W   P_TERECAL_NO_3                  | set caret state
        BSR.W   TEUPDATE_CONT_2                 | highlight selection
TEINSERT_EXIT:
        MOVEQ    #0xC,D0                        | strip 12 param bytes
        BRA.W    TECALTEXT_EXIT_2               | share TE epilog

| ----------------------------------------------------------
| TEKey -- _TEKey ($A9DC). Plus textedit.s 2367.
| Process a typed character: backspace deletes the char before
| the cursor; otherwise the char is inserted at the selection.
TEKey:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state (A3=TERec, A2=params)
        ST      0x47(A3)                        | set teJust flag (caret active)
        _ObscureCursor                          | hide cursor during typing
        MOVE    (A2),D1                         | D1 = key character
        CMPI.B  #0x8,D1                         | backspace?
        BEQ.B   TEKEY_OK                        | yes, handle delete ->
        MOVE.L  A2,D6                           | D6 = ptr to character to insert
        ADDQ.W  #0x1,D6                         | point past key word to char byte
        MOVEQ.L #0x1,D5                         | D5 = 1 character to insert
        BSR.W   P_TERECAL_CONT_4_CONT           | TEInsert: replace selection with char
        BRA.B   TEKEY_DONE                      | -> done

| backspace: delete character before selection
TEKEY_OK:
        MOVE    teSelStart(A3),D0               | D0 = selStart
        CMP     teSelEnd(A3),D0                 | selStart == selEnd? (no selection)
        BNE.B   TEKEY_CONT                      | has selection, delete it ->
        TST     D0                              | at beginning of text?
        BEQ.B   TEKEY_DONE                      | yes -> nothing to delete
        BSR.W   P_TERECAL_CONT_3                | hide caret
        SUBQ.W  #0x1,teSelStart(A3)             | selStart-- (select char before cursor)
TEKEY_CONT:
        MOVE.L  A4,-(SP)                        | push TE handle for TEDelete
        _TEDelete                               | delete selected/back char
TEKEY_DONE:
        MOVEQ.L #0x6,D0                         | strip 6 param bytes
        BRA.W   TECALTEXT_EXIT_2                | share TE epilog

| ----------------------------------------------------------
| TEScroll -- _TEScroll ($A9DD). Plus textedit.s 2426.
| Scroll text within view rect by (dh, dv) offsets via _ScrollRect.
| Redraws caret and uses temp clip rgn for affected area.
TEScroll:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        BSR.W   P_TERECAL_CONT_3                | hide caret
        MOVE.L  (A2)+,D2                        | D2 = (dh, dv) offsets from param
        PEA.L     (A3)                          | push destRect
        MOVE.L  D2,-(SP)                        | push offsets
        _OffsetRect                             | offset destRect by (dh, dv)
        SUBQ.W  #0x4,SP                         | make room for NewRgn result
        _NewRgn                                 | A0 = new empty region
        MOVE.L  (SP)+,A2                        | A2 = new rgn
        PEA.L     8(A3)                         | push viewRect
        MOVE.L  D2,-(SP)                        | push offsets
        MOVE.L  A2,-(SP)                        | push update rgn
        _ScrollRect                             | scroll viewRect, accumulate update rgn
        BSR.W   P_TERECAL_NO_3                  | redraw caret
        MOVE.L  A2,-(SP)                        | push update rgn
        _SetClip                                | clip drawing to update area
        MOVE.L  (A2),A0                         | A0 = update rgn dereferenced
        MOVE    2(A0),D0                        | D0 = top of rgn bounds
        MOVE    6(A0),D1                        | D1 = bottom of rgn bounds
        BSR.B   XTRIMMEASURE_CONT_6_CONT        | redraw text in update range
        MOVE.L  A2,-(SP)                        | push update rgn
        _DisposeRgn                             | release temp rgn
TESCROLL_EXIT:
        MOVEQ.L #0x8,D0                         | D0 = frame size to discard
        BRA.W   TECALTEXT_EXIT_2                | -> UNLK + return

| ----------------------------------------------------------
| TESetJust -- _TESetJust ($A9DF) (also called _TextStyle).
| Set the justification field (teJust): -1=right, 0=left, 1=center.
TESetJust:
        BSR.W   XTRIMMEASURE_CONT_12            | set up TE state
        MOVE    (A2),teJust(A3)                 | store new justification
        BRA.B   TEKEY_DONE                      | -> common TE epilog

| ----------------------------------------------------------
| XTRIMMEASURE_CONT_6
| Called during boot.
XTRIMMEASURE_CONT_6:
        SUB     (A3),D0                         | D0 = pixel y - destRect.top
        EXT.L    D0                             | sign-extend D0 to long
        DIVS    24(A3),D0                       | D0 = D0 /s 24(A3)
        CMP     0x5E(A3),D0                     | compare with total lines (sets CC)
XTRIMMEASURE_CONT_6_RTS:                        | shared early-exit target
        RTS                                     | caller checks GE for past-end
XTRIMMEASURE_CONT_6_CONT:
        MOVEQ.L #0x0,D3                         | D3 = 0 (range start char)
        BSR.B   XTRIMMEASURE_CONT_6             | y -> line number
        BGE.B   XTRIMMEASURE_CONT_6_CONT_2      | past end: skip table lookup
        ADD     D0,D0                           | line *= 2 (word offset)
        BLT.B   XTRIM_CBMLOAD_NEG1              | negative: skip indexed load
        MOVE    0x60(A3,D0.W),D3                | D3 = teCarets+D0 (width-cache lookup)
XTRIM_CBMLOAD_NEG1:
        MOVEQ.L #-0x1,D4                        | D4 = -1 (default end)
        ADD     teLineHite(A3),D1               | D1 = bottom + lineHeight
        SUBQ.W  #0x1,D1                         | step back to last visible row
        MOVE    D1,D0                           | D0 = bottom y
        BSR.B   XTRIMMEASURE_CONT_6             | y -> end line number
        BGE.B   XTRIM_CBMLOAD_LAST_D7NEG1       | past end -> D4=-1, skip table
        ADD     D0,D0                           | line *= 2 (word offset)
        MOVE    0x60(A3,D0.W),D4                | D4 = teCarets+D0 (width-cache lookup)
XTRIM_CBMLOAD_LAST_D7NEG1:
        MOVEQ.L #-0x1,D7                        | D7=-1: draw mode
        BSR.W   XTRIMMEASURE_OK_CONT_2          | draw lines D3..D4
XTRIMMEASURE_CONT_6_CONT_2:
        BSR.W   TEUPDATE_CONT_2                 | redraw selection hilite
        TST.B   teCarOn(A3)                     | caret currently visible?
        BEQ.B   XTRIMMEASURE_CONT_6_RTS         | zero -> early RTS
        BRA.W   P_TERECAL_OK_3                  | -> P_TERECAL_CONT_4 via .W reach extender
        MOVE.L  (SP)+,A0                        | pop return address
        LEA.L     (ScrapSize).w,A1              | A1 = ScrapSize lomem
        MOVE.L  A1,(SP)                         | push ScrapSize ptr to caller
        JMP     (A0)                            | RTS
| Called by: XTRIMMEASURE_CONT_6_CONT_4, XTRIMMEASURE_CONT_6_CONT_9, XTRIMMEASURE_CONT_6_CONT_11, XTRIMMEASURE_CONT_6_CONT_16, GETSCRAP_DONE
XTRIMMEASURE_CONT_6_CONT_3:
        MOVE.L  (SP)+,A1                        | A1 = saved return address
        LINK    A6,#-0x58                       | set up stack frame
        MOVEM.L D2-D7/A2-A4,-(SP)               | save working registers
        MOVE.L  A1,-(SP)                        | re-push return address
        MOVEM.L (ScrapSize).w,D4-D6/A2          | (ScrapSize).w -> D4-D6/A2
        LEA.L     (ScrapHandle).w,A4            | A4 -> scrap globals (handle/state)
        LEA.L     -0x50(A6),A0                  | A0 -> local IOParam block
        MOVE.L  A0,A3                           | A3 = IOParam block ptr
        MOVE.L  A2,18(A0)                       | ioFileName = scrap filename ptr
        CLR     22(A0)                          | ioVRefNum = 0 (default volume)
        CLR     26(A0)                          | ioPermssn = read/write
        CLR.L   28(A0)                          | ioMisc = 0
        TST     D6                              | scrap state set?
        BNE.B   XTRIMMEASURE_CONT_6_CONT_8      | in memory or on disk: skip open
XTRIMMEASURE_CONT_6_CONT_4:
        _Open                                   | open Clipboard File
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_9      | success: return ioRefNum
        CMPI    #-0x31,D0                       | dirNFErr (-49)?
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_8      | no dir: skip silently
        CMPI    #-0x2B,D0                       | fnfErr (file not found)?
        BNE.B   XTRIMMEASURE_CONT_6_CONT_9      | other err: return error
        _Create                                 | file missing: create it
        BNE.B   XTRIMMEASURE_CONT_6_CONT_9      | create failed: return error
        BRA.B   XTRIMMEASURE_CONT_6_CONT_4      | retry _Open
        BSR.B   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | setup err: return error
        TST     D6                              | ScrapState
        BLE.B   XTRIMMEASURE_CONT_6_CONT_5      | on disk/uninit: noErr
        BSR.B   XTRIMMEASURE_CONT_6_CONT_4      | reopen Clipboard File
        MOVE.L  D4,D0                           | D0 = ScrapSize
        BSR.B   XTRIMMEASURE_CONT_6_CONT_10     | build IOParam from handle
        _Write                                  | write scrap to file
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | write err: return error
        MOVE.L  D5,A0                           | A0 = ScrapHandle
        _DisposeHandle                          | free in-memory scrap
        CLR.L   (A4)+                           | ioMisc/logical EOF = 0
        CLR.L   (A4)+                           | ScrapCount|State = 0
XTRIMMEASURE_CONT_6_CONT_5:
        MOVEQ.L #0x0,D0                         | D0 = 0 (@ $FD4C)
XTRIMMEASURE_CONT_6_CONT_6:
        EXT.L    D0                             | sign-extend result
        MOVE.L  D0,8(A6)                        | store result in stack frame
        MOVEQ.L #0x0,D0                         | strip 0 param bytes
XTRIMMEASURE_CONT_6_CONT_7:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore working registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  D0,SP                           | SP += D0
        JMP     (A0)                            | RTS
XTRIMMEASURE_CONT_6_CONT_8:
        MOVEQ.L #0x0,D0                         | D0 = noErr
XTRIMMEASURE_CONT_6_CONT_9:
        RTS                                     | return from setup
        BSR.B   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | setup err: return error
        TST     D6                              | scrap in memory?
        BNE.B   XTRIMMEASURE_CONT_6_CONT_5      | yes: just return
        MOVE.L  D4,D0                           | D0 = ScrapSize
        _NewHandle                              | allocate scrap buffer
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | alloc fail: error
        MOVE.L  A0,(A4)+                        | ScrapHandle = new handle
        ADDQ.L  #0x1,(A4)+                      | ScrapState = 1 (in memory)
        BSR.B   XTRIMMEASURE_CONT_6_CONT_11     | build IOParam from A0
        _Read                                   | read scrap data from file
        BRA.B   XTRIMMEASURE_CONT_6_CONT_6      | return result code
XTRIMMEASURE_CONT_6_CONT_10:
        MOVE.L  D5,A0                           | A0 = ScrapHandle
XTRIMMEASURE_CONT_6_CONT_11:
        MOVE.L  (A0),teSelStart(A3)             | ioBuffer = *handle
        MOVE.L  D0,teActive(A3)                 | D7 = scrap entry type code
        MOVE    #0x1,0x2C(A3)                   | ioPosMode = fsFromStart
        CLR.L   teClikTime(A3)                  | 0x2E(A3) := 0
        MOVE.L  A3,A0                           | A0 = IOParam block
        RTS                                     | return with IOParam ready
        BSR.W   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   XTRIMMEASURE_CONT_6_CONT_6      | setup err: return
        MOVE.L  D0,(ScrapSize).w                | ScrapSize = 0
        ADDQ.W  #0x8,4(A4)                      | ScrapCount += 8
        TST     D6                              | scrap state?
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_14     | on disk: truncate file
        BGT.B   XTRIMMEASURE_CONT_6_CONT_12     | in memory: resize handle
        _NewHandle                              | uninit: allocate empty handle
        BRA.B   XTRIMMEASURE_CONT_6_CONT_13     | store handle, set state
XTRIMMEASURE_CONT_6_CONT_12:
        MOVE.L  D5,A0                           | A2 -> VAR offset parameter
        _SetHandleSize                          | shrink scrap to 0 bytes
XTRIMMEASURE_CONT_6_CONT_13:
        MOVE.L  A0,(A4)+                        | D0 = data length for this entry
        MOVE    (A4)+,(A4)                      | store length as function result
        BRA.B   XTRIMMEASURE_CONT_6_CONT_6      | return result code
XTRIMMEASURE_CONT_6_CONT_14:
        CLR.L   28(A0)                          | ioMisc = 0 (truncate to 0)
        _SetEOF                                 | truncate Clipboard File
        BRA.B   XTRIMMEASURE_CONT_6_CONT_6      | return result code
XTRIMMEASURE_CONT_6_CONT_15:
        TST     D6                              | scrap on disk?
        BEQ.B   XTRIMMEASURE_CONT_6_CONT_16     | yes: read from file
        MOVE.L  D5,A2                           | A1 = *hDest (dereferenced destination ptr)
        MOVE.L  (A2),A0                         | A0 = *ScrapHandle
        ADDA.L  D3,A0                           | A0 += offset D3
        _BlockMove                              | copy D0 bytes to A1
        BRA.B   XTRIMMEASURE_CONT_6_CONT_8      | return noErr
XTRIMMEASURE_CONT_6_CONT_16:
        BSR.B   XTRIMMEASURE_CONT_6_CONT_10     | build IOParam from ScrapHandle
        MOVE.L  D3,0x2E(A0)                     | ioPosOffset = D3
        MOVE.L  A1,0x20(A0)                     | ioBuffer = A1 (caller dest)
        _Read                                   | read D0 bytes from file
        RTS                                     | return Read result
        BSR.W   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BNE.B   GETSCRAP_ERR                    | setup err: return error
        MOVEQ.L #-0x64,D0                       | D0 = noScrapErr (-100)
        TST     D6                              | scrap initialized?
        BMI.B   GETSCRAP_ERR                    | uninit: return error
        MOVEQ.L #0x0,D3                         | D3 = scan offset (0)
| scan through scrap entries looking for matching type
GETSCRAP_SCAN:
        CMP.L   D4,D3                           | D3 >= D4 (walked off end)?
        BGE.B   GETSCRAP_NOTYPE                 | yes: report noTypeErr (-> $FE0A)
        MOVEQ.L #0x8,D0                         | D0 = 8 (entry-type field offset)
        LEA.L     -0x58(A6),A1                  | A1 = frame slot with search target
        BSR.B   XTRIMMEASURE_CONT_6_CONT_15     | compare entry type
        BNE.B   GETSCRAP_ERR                    | mismatch: -> continuation
        ADDQ.L  #0x8,D3                         | advance to next scrap entry
        MOVE.L  (A1)+,D7                        | D7 = entry ID
        CMP.L   12(A6),D7                       | matches requested ID?
        BEQ.B   GETSCRAP_FOUND                  | yes: -> found path
        ADD.L   (A1)+,D3                        | skip entry data
        ADDQ.L  #0x1,D3                         | round up by 1
        BCLR    D0,D3                           | clear bit 0 (word-align)
        BRA.B   GETSCRAP_SCAN                   | keep scanning
| ----------------------------------------------------------
| GETSCRAP_NOTYPE -- fall-through tail at $FE0A..$FE0D, reached by
| the BGE.B above when GETSCRAP_SCAN walks past the end of the scrap
| without finding the requested type. Sets the error code -102
| (noTypeErr) and branches into package_mgr.s at $FE30 (mid-body of
| GETSCRAP_ERR) to finish the _GetScrap epilogue.
GETSCRAP_NOTYPE:
        MOVEQ   #-0x66,D0                       | D0 = -102 (noTypeErr)
        BRA.B   GETSCRAP_ERR+2                  | continue at $FE30 (package_mgr.s)
GETSCRAP_FOUND:
        MOVE.L  8(A6),A2                        | A2 -> VAR offset param
        MOVE.L  D3,(A2)                         | store data offset
        MOVE.L  (A1),D0                         | D0 = entry data length
        MOVE.L  D0,20(A6)                       | store length as result
        MOVE.L  16(A6),D1                       | D1 = hDest handle
        BEQ.B   GETSCRAP_DONE                   | NIL: just return length
        MOVE.L  D1,A0                           | A0 = hDest handle
        _SetHandleSize                          | resize hDest to D0 bytes
        BNE.B   GETSCRAP_ERR                    | resize failed: error
        MOVE.L  (A1),D0                         | jump via A0
        MOVE.L  (A0),A1                         | A1 = *hDest (dest ptr)
        BSR.B   XTRIMMEASURE_CONT_6_CONT_15     | copy D0 bytes from scrap+D3
        BEQ.B   GETSCRAP_DONE                   | success: return length
GETSCRAP_ERR:
        EXT.L    D0                             | sign-extend error code
        MOVE.L  D0,20(A6)                       | store error as result
GETSCRAP_DONE:
        MOVEQ.L #0xC,D0                         | strip 12 param bytes
        BRA.W   XTRIMMEASURE_CONT_6_CONT_7      | share scrap epilog
        BSR.W   XTRIMMEASURE_CONT_6_CONT_3      | set up scrap globals
        BSR.W   XTRIMMEASURE_CONT_6_CONT_10     | build IOParam from ScrapHandle
        MOVEQ.L #-0x64,D0                       | D0 = noScrapErr (-100)
        TST     D6                              | scrap initialized?
        BMI.B   GETSCRAP_ERR                    | uninit: error
        MOVEQ.L #0x8,D0                         | header size = 8 bytes
        LEA.L     12(A6),A0                     | A0 -> theType param
        BSR.B   SCRAP_APPEND                    | append type+length header
        MOVE.L  8(A6),A0                        | A0 = source data ptr
        MOVE.L  16(A6),D0                       | D0 = data length
        MOVEQ.L #-0x2,D1                        | D1 = even-mask
        ADDQ.L  #0x1,D0                         | length += 1 for round-up
        AND.L   D1,D0                           | align length to even
        BSR.B   SCRAP_APPEND                    | append data bytes
        MOVE.L  D4,-(A4)                        | ScrapSize = D4 (new total)
        BRA.B   GETSCRAP_ERR                    | epilog
SCRAP_APPEND:
        MOVE.L  D4,0x2E(A3)                     | ioPosOffset = current end
        ADD.L   D0,D4                           | D4 += D0 (new size)
        TST     D6                              | scrap on disk?
        BEQ.B   SCRAP_WRITE_FILE                | yes: write to file
        MOVE.L  D5,A1                           | A1 = ScrapHandle
        _PtrAndHand                             | append A0[D0] to handle
        RTS                                     | return from append
SCRAP_WRITE_FILE:
        MOVE.L  A0,teSelStart(A3)               | ioBuffer = source A0
        MOVE.L  D0,teActive(A3)                 | ioByteCount = D0
        MOVE.L  A3,A0                           | A0 = IOParam block
        _Write                                  | write D0 bytes at end of file
        RTS                                     | return Write result
