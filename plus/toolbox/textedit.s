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
|
| _SystemEvent ($A9B2) - handle system events (desk accessories)
|
| FUNCTION SystemEvent(theEvent: EventRecord): BOOLEAN
|
| Determines if a system event (mouse/key/etc.) should be handled
| by a desk accessory rather than the application. Dispatches by
| event code through jump table SYSEVT_DISPATCH.
| Returns TRUE (1) in result word if the system handled the event.
|
| Called during boot.
SystemEvent:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 -> EventRecord parameter
        CLR     0xC(SP)                         | clear result (assume FALSE)
        SUBQ.W  #0x4,SP                         | allocate space for saved port
        MOVE.L  A7,-(SP)                        | push ptr to saved port variable
        _GetPort                                | save current grafport
        MOVE    (A3),D0                         | D0 = event code (what field)
        CMPI    #0xC,D0                         | event code >= 12?
        BCC.B   SYSEVT_RESTORE                  | out of range: ignore event
        ADD     D0,D0                           | word offset into dispatch table
        LEA.L   SYSEVT_DISPATCH(PC),A0          | A0 -> event dispatch table
        ADDA    0x0(A0,D0.W),A0                 | add relative offset for this event
        JMP     (A0)                            | dispatch to event handler

| ----------------------------------------------------------
|
| SYSEVT_DISPATCH - SystemEvent dispatch table (word offsets from SYSEVT_DISPATCH)
|
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
|
SYSEVT_DISPATCH:
  .byte 0x00,0x1C,0x00,0x1C,0x00,0x24
  .byte 0x00,0x24,0x00,0x24,0x00,0x24
  .byte 0x00,0x78,0x00,0x84,0x00,0x78
  .byte 0x00,0x1C,0x00,0x24,0x00,0x24
SYSEVT_HANDLED:
        ADDQ.B  #0x1,0x10(SP)                   | set result to TRUE (system handled)
SYSEVT_RESTORE:
        _SetPort                                | restore saved grafport
        MOVE.L  (SP)+,A3                        | restore A3
        MOVE.L  (SP)+,(SP)                      | collapse stack frame
        RTS                                     | return from desk accessory event handler

TEXTEDIT_CONT:
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,A0                        | A0 = front window ptr
        BSR.B   TEXTEDIT_CONT_2                 | look up desk accessory DCE -> A1
        BNE.B   SYSEVT_RESTORE                  | not a DA window, bail
        MOVE    (A3),D0                         | D0 = event code (from caller)
        MOVE    0x24(A1),D1                     | D1 = DCE event mask
        BTST    D0,D1                           | DA interested in this event?
        BEQ.B   SYSEVT_RESTORE                  | no, bail
        BSR.B   TEXTEDIT_CONT_3                 | send accEvent control call to DA
        BRA.B   SYSEVT_HANDLED                  | -> return

| ----------------------------------------------------------
|
| TEXTEDIT_CONT_2
|
| Called during boot (3,697 times in 30s trace).
TEXTEDIT_CONT_2:
        MOVE    0x6C(A0),D0                     | D0 = windowKind from WindowRecord
        BPL.B   TEXTEDIT_ERR                    | positive = not a DA, return error
        NOT     D0                              | convert DA refNum to unit number
        ASL     #0x2,D0                         | multiply by 4 for table index
        MOVE.L  (UTableBase).w,A0               | A0 = unit table base
        MOVE.L  0x0(A0,D0.W),A0                 | A0 = handle to DCE
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE pointer
        MOVEQ.L #0x0,D0                         | return 0 = success (Z flag set)
        RTS                                     | return success code (0)

| ----------------------------------------------------------
|
| TEXTEDIT_ERR
|
| Called during boot (3,697 times in 30s trace).
TEXTEDIT_ERR:
        MOVEQ.L #-0x1,D0                        | return -1 = not a DA (NE flag set)
        RTS                                     | return failure code (-1)

| TEXTEDIT_CONT_3 -- send accEvent control call to DA.
| ----------------------------------------------------------
|
| TEXTEDIT_CONT_3
|
TEXTEDIT_CONT_3:
        MOVEQ.L #0x40,D0                        | csCode = accEvent (64)
| TEXTEDIT_CONT_4 -- send accCursor to front DA.
TEXTEDIT_CONT_4:
        LINK    A6,#-0x20                       | allocate param block on stack
        LEA.L   -0x8(A6),A0                     | A0 = csParam area in param block
        MOVE    0x18(A1),(A0)+                  | csParam[0] = DCE refNum
        MOVE    D0,(A0)+                        | csParam[1] = csCode
        MOVE.L  A3,(A0)                         | csParam[2] = event/menu ptr
        LEA.L   -0x20(A6),A0                    | A0 = param block base
        _ControlImmed                           | issue synchronous Control call to DA
        UNLK    A6                              | tear down frame
        RTS                                     | return from synchronous Control call

| TEXTEDIT_CONT_5 -- send accRun to this DA.
| ----------------------------------------------------------
|
| TEXTEDIT_CONT_5
|
TEXTEDIT_CONT_5:
        MOVEQ.L #0x41,D0                        | csCode = accRun (65)
        BRA.B   TEXTEDIT_CONT_4                 | -> send Control call to DA

| ----------------------------------------------------------
|
| TEXTEDIT_CONT_6
|
| Called during boot.
TEXTEDIT_CONT_6:
        MOVE.L  PORTBITS(A3),A0                 | A0 = window ptr from event record
        BSR.B   TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
        BNE.B   SYSEVT_RESTORE                  | not a DA, bail
        BSR.B   TEXTEDIT_CONT_3                 | send accEvent control call
        BRA.B   SYSEVT_HANDLED                  | -> return

| ----------------------------------------------------------
|
| TEXTEDIT_CONT_7
|
TEXTEDIT_CONT_7:
        SUBA    #0x18,SP                        | allocate VolumeParam block on stack
        MOVE.L  A7,A0                           | A0 = param block ptr
        MOVE    0x4(A3),0x16(A0)                | ioVRefNum = drive number from caller
        _MountVol                               | mount the volume
        ADDA    #0x18,SP                        | discard param block
        MOVE    D0,PORTBITS(A3)                 | store result code
  .short 0x6080                                 | Bra.B SYSEVT_RESTORE

| SystemClick -- _SystemClick ($A9B3): PROCEDURE SystemClick (theEvent: EventRecord; theWindow:
SystemClick:
        MOVEM.L D0/D3-D4/A3-A4,-(SP)            | save registers
        MOVE.L  A7,-(SP)                        | push ptr for GetPort result
        _GetPort                                | save current port
        MOVE.L  0x18(SP),A4                     | A4 = window ptr (param)
        MOVE.L  0x7E(A4),A3                     | A3 = window defProc handle
        MOVE.L  0x1C(SP),D4                     | D4 = event record ptr (param)
        MOVE.L  A4,D0                           | test window ptr
        BEQ     SYSTEMCLICK_EMPTY               | nil -> desktop click
        MOVE.L  A4,A0                           | A0 = window ptr
        BSR.B   TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
        BNE.B   SYSTEMCLICK_EXIT                | not a DA -> restore and return
        MOVE.L  A1,D3                           | D3 = saved DCE ptr
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  0x7E(A4),D0                     | D0 = WDEF resource ID (low byte of handle)
        CLR.L   -(SP)                           | space for FindWindow result
        MOVE    D0,-(SP)                        | push part code
        MOVE.L  A4,-(SP)                        | push window ptr
        MOVE    #0x1,-(SP)                      | msg = wHit (find part)
        MOVE.L  D4,A0                           | A0 = event record
        MOVE.L  0xA(A0),-(SP)                   | push event.where (mouse point)
        MOVE.L  A3,-(SP)                        | push defProc handle
        _LoadResource                           | ensure defProc is loaded
        MOVE.L  (A3),A0                         | dereference defProc handle
        BSET    #0x7,(A3)                       | lock defProc handle
        JSR     (A0)                            | call WDEF: returns part code
        BCLR    #0x7,(A3)                       | unlock defProc handle
        MOVE.L  (SP)+,D0                        | D0 = part code from WDEF
        BEQ.B   SYSTEMCLICK_EXIT                | 0 = no hit -> done
        SUBQ.W  #0x2,D0                         | test for inDrag (2)
        BEQ.B   SYSTEMCLICK_OK                  | yes -> drag window
        SUBQ.W  #0x2,D0                         | test for inGoAway (4)
        BEQ.B   SYSTEMCLICK_OK_2                | yes -> track close box
        CLR.L   -(SP)                           | space for FrontWindow result
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,D0                        | D0 = front window
        CMP.L   A4,D0                           | is clicked window frontmost?
        BNE.B   SYSTEMCLICK_NO                  | no -> bring it to front
        MOVE.L  D4,A3                           | A3 = event record for accEvent
        MOVE.L  D3,A1                           | A1 = DCE ptr
        BSR     TEXTEDIT_CONT_3                 | send accEvent to DA
| Called by: SYSTEMCLICK_EMPTY, SYSTEMCLICK_NO, SYSTEMCLICK_OK, SYSTEMCLICK_OK_2, SYSTEMCLICK_OK_3
SYSTEMCLICK_EXIT:
        _SetPort                                | restore saved port
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore registers
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x8,SP                         | pop 2 params (window, event)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| SYSTEMCLICK_EMPTY
|
| Called during boot.
SYSTEMCLICK_EMPTY:
        TST.L   (DeskHook).w                    | custom desktop hook installed?
        BEQ.B   SYSTEMCLICK_EXIT                | no -> done
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

| ----------------------------------------------------------
|
| SYSTEMCLICK_NO
|
SYSTEMCLICK_NO:
        MOVE.L  A4,-(SP)                        | push DA window to bring to front
        _SelectWindow                           | activate and bring window forward
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return

| ----------------------------------------------------------
|
| SYSTEMCLICK_OK
|
SYSTEMCLICK_OK:
        MOVE.L  A4,-(SP)                        | push window ptr
        MOVE.L  D4,A0                           | A0 = event record
        MOVE.L  0xA(A0),-(SP)                   | push event.where (start point)
        MOVE.L  (A5),A0                         | A0 = app globals ptr
        PEA.L   -0x74(A0)                       | push drag boundary rect
        _DragWindow                             | let user drag DA title bar
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return

| ----------------------------------------------------------
|
| SYSTEMCLICK_OK_2
|
SYSTEMCLICK_OK_2:
        CLR     -(SP)                           | space for TrackGoAway result
        MOVE.L  A4,-(SP)                        | push window ptr
        MOVE.L  D4,A0                           | A0 = event record
        MOVE.L  0xA(A0),-(SP)                   | push event.where (mouse point)
        _TrackGoAway                            | track close box click
        TST.B   (SP)+                           | user confirmed close?
        BEQ.B   SYSTEMCLICK_EXIT                | no -> done
        MOVE.L  D3,A1                           | A1 = DCE ptr
        MOVE.L  (CloseOrnHook).w,D0             | custom close hook installed?
        BNE.B   SYSTEMCLICK_OK_3                | yes -> call custom hook
        MOVE    0x18(A1),-(SP)                  | push DA refNum from DCE
        _CloseDeskAcc                           | close the desk accessory
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return

| ----------------------------------------------------------
|
| SYSTEMCLICK_OK_3
|
SYSTEMCLICK_OK_3:
        MOVE.L  D0,A0                           | A0 = close ornament hook
        JSR     (A0)                            | call custom close handler
        BRA.B   SYSTEMCLICK_EXIT                | -> restore and return

| ----------------------------------------------------------
|
| _SystemTask ($A9B4)
|
| Called during boot (3,694 times in 30s trace).
SystemTask:
        MOVEM.L D3/A3,-(SP)                     | save registers
        BSET    #0x7,(TaskLock).w               | test-and-set task lock (reentrance guard)
        BNE     SYSTEMTASK_CONT                 | already locked -> bail
        SUBQ.W  #0x4,SP                         | space for saved port
        MOVE.L  A7,-(SP)                        | push ptr for GetPort result
        _GetPort                                | save current port
        CLR.L   -(SP)                           | space for FrontWindow result
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,D0                        | D0 = front window ptr
        BEQ.B   SYSTEMTASK_SKIP                 | no front window -> skip DA idle
        MOVE.L  D0,A0                           | A0 = front window
        BSR     TEXTEDIT_CONT_2                 | look up DCE -> A1
        BNE.B   SYSTEMTASK_SKIP                 | not a DA -> skip
        BTST    #0x7,0x5(A1)                    | DCE flags: dNeedTime set?
        BNE.B   SYSTEMTASK_SKIP                 | yes -> handled below in loop
        MOVEQ.L #0x42,D0                        | csCode = accCursor (66)
        BSR     TEXTEDIT_CONT_4                 | send accCursor to front DA
SYSTEMTASK_SKIP:
        MOVE.L  (UTableBase).w,A3               | A3 = unit table base
        MOVE    (UnitTableEntryCount).w,D3      | D3 = number of unit table entries
SYSTEMTASK_LOOP:
        MOVE.L  (A3)+,D0                        | D0 = next DCE handle
        BEQ.B   SYSTEMTASK_SKIP_2               | nil -> skip this slot
        MOVE.L  D0,A0                           | A0 = DCE handle
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE
        MOVE    0x4(A1),D0                      | D0 = dCtlFlags
        ANDI    #0x20A0,D0                      | mask dNeedTime + dOpened + dRAMBased
        CMPI    #0x2020,D0                      | dNeedTime and dOpened both set?
        BNE.B   SYSTEMTASK_SKIP_2               | no -> skip
        MOVEQ.L #0x0,D0                         | clear high word
        MOVE    0x22(A1),D0                     | D0 = dCtlDelay (tick interval)
        BEQ.B   SYSTEMTASK_EMPTY                | zero delay -> always run
        ADD.L   0x1A(A1),D0                     | D0 = last run time + delay
        CMP.L   (Ticks).w,D0                    | time to run yet?
        BGT.B   SYSTEMTASK_SKIP_2               | not yet -> skip
        MOVE.L  (Ticks).w,0x1A(A1)              | update last run time to now
SYSTEMTASK_EMPTY:
        BSR     TEXTEDIT_CONT_5                 | send accRun to this DA
SYSTEMTASK_SKIP_2:
        SUBQ.W  #0x1,D3                         | decrement unit counter
        BGT.B   SYSTEMTASK_LOOP                 | more entries -> loop
        _SetPort                                | restore saved port
        CLR.B   (TaskLock).w                    | release task lock
SYSTEMTASK_CONT:
        MOVEM.L (SP)+,D3/A3                     | restore registers
        RTS                                     | return from accRun loop

| SystemMenu -- _SystemMenu ($A9B5): PROCEDURE SystemMenu (menuResult: LONGINT);
| ----------------------------------------------------------
|
| _SystemMenu ($A9B5)
|
SystemMenu:
        MOVEM.L A2-A3,-(SP)                     | save registers
        MOVE.L  0xC(SP),D1                      | D1 = menu result (menuID | item)
        SWAP    D1                              | D1.W = menuID
        MOVE    (MBarEnable).w,D0               | D0 = menu bar enable word
        BEQ.B   SYSTEMMENU_EMPTY                | zero -> use menuID from param
        MOVE    D0,D1                           | override with MBarEnable menuID
SYSTEMMENU_EMPTY:
        MOVE.L  (UTableBase).w,A2               | A2 = unit table base
        MOVE    (UnitTableEntryCount).w,D2      | D2 = unit count
SYSTEMMENU_LOOP:
        MOVE.L  (A2)+,D0                        | D0 = next DCE handle
        BEQ.B   SYSTEMMENU_SKIP                 | nil -> skip slot
        MOVE.L  D0,A0                           | A0 = DCE handle
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE
        BTST    #0x5,0x5(A1)                    | dCtlFlags: dNeedTime set? (has menu)
        BEQ.B   SYSTEMMENU_SKIP                 | no -> skip
        CMP     0x26(A1),D1                     | DCE menuID matches selected menu?
        BNE.B   SYSTEMMENU_SKIP                 | no -> try next
        MOVE.L  0xC(SP),A3                      | A3 = menu result for accMenu
        MOVEQ.L #0x43,D0                        | csCode = accMenu (67)
        BSR     TEXTEDIT_CONT_4                 | send accMenu control call
        BRA.B   SYSTEMMENU_DONE                 | -> done

| ----------------------------------------------------------
|
| SYSTEMMENU_SKIP
|
SYSTEMMENU_SKIP:
        SUBQ.W  #0x1,D2                         | decrement unit counter
        BGT.B   SYSTEMMENU_LOOP                 | more entries -> loop
SYSTEMMENU_DONE:
        MOVEM.L (SP)+,A2-A3                     | restore registers
        MOVE.L  (SP)+,(SP)                      | pop return addr over param
        RTS                                     | return from unit counter loop

| SysEdit -- trap handler for _SysEdit ($A9C2).
| ----------------------------------------------------------
|
| _SysEdit ($A9C2)
|
SysEdit:
        CLR     0x6(SP)                         | clear result (FALSE by default)
        SUBQ.W  #0x8,SP                         | allocate saved port + window
        PEA.L   0x4(SP)                         | push ptr for GetPort result
        _GetPort                                | save current port
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,D0                        | D0 = front window ptr
        BEQ.B   SYSEDIT_SKIP                    | no window -> skip
        MOVE.L  D0,A0                           | A0 = front window
        BSR     TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
        BNE.B   SYSEDIT_SKIP                    | not a DA -> skip
        MOVE    0x8(SP),D0                      | D0 = editCmd parameter (0-3)
        ADDI    #0x44,D0                        | convert to csCode (accUndo=68..accPaste=71)
        BSR     TEXTEDIT_CONT_4                 | send edit command to DA
        ADDQ.B  #0x1,0xA(SP)                    | set result = TRUE (DA handled it)
SYSEDIT_SKIP:
        _SetPort                                | restore saved port
        BRA.B   CLOSEDESKACC_EXIT               | -> clean up and return

| ----------------------------------------------------------
|
| _OpenDeskAcc ($A9B6)
|
OpenDeskAcc:
        CLR     0x8(SP)                         | clear result (refNum = 0)
        SUBA    #0x20,SP                        | allocate IOParam block on stack
        MOVE.L  0x24(SP),0x12(SP)               | ioNamePtr = DA name (from param)
        CLR     0x16(SP)                        | ioVRefNum = 0
        MOVE    #0x40,0x1A(SP)                  | ioPermssn = fsRdPerm (read-only)
        CLR.L   0x1C(SP)                        | ioMisc = nil
        MOVE.L  A7,A0                           | A0 = param block
        _Open                                   | open the desk accessory driver
        BNE.B   OPENDESKACC_ERR                 | error -> bail
        MOVE    0x18(SP),D0                     | D0 = ioRefNum (DA refNum)
        MOVE    D0,0x28(SP)                     | store as return value
        NOT     D0                              | convert refNum to unit number
        ASL     #0x2,D0                         | multiply by 4 for table index
        MOVE.L  (UTableBase).w,A1               | A1 = unit table base
        MOVE.L  0x0(A1,D0.W),A1                 | A1 = DCE handle
        MOVE.L  (A1),A1                         | A1 = dereferenced DCE
        MOVE.L  0x1E(A1),D0                     | D0 = dCtlWindow (DA's window)
        BEQ.B   OPENDESKACC_ERR                 | nil -> no window to show
        MOVE.L  D0,-(SP)                        | push window ptr
        MOVE.L  D0,-(SP)                        | push window ptr again
        _SelectWindow                           | bring DA window to front
        _ShowWindow                             | make DA window visible
OPENDESKACC_ERR:
        ADDA    #0x20,SP                        | discard param block
        MOVE.L  (SP)+,(SP)                      | pop return addr over name param
        RTS                                     | return from DA window activation

| ----------------------------------------------------------
|
| _CloseDeskAcc ($A9B7)
|
CloseDeskAcc:
        MOVE    0x4(SP),D0                      | D0 = DA refNum (param)
        SUBA    #0x1E,SP                        | allocate IOParam block
        MOVE    D0,0x18(SP)                     | ioRefNum = DA refNum
        MOVE.L  A7,A0                           | A0 = param block
        _Close                                  | close the DA driver
        ADDA    #0x1E,SP                        | discard param block
CLOSEDESKACC_EXIT:
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop parameter word
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetPattern ($A9B8)
|
| Called during boot.
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
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetCursor ($A9B9)
|
| Called during boot.
GetCursor:
        MOVE.L  #0x43555253,D0                  | D0 = 'CURS' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| GetString -- _GetString ($A9BA): FUNCTION GetString (stringID: INTEGER) : StringHandle;
| ----------------------------------------------------------
|
| _GetString ($A9BA)
|
GetString:
        MOVE.L  #0x53545220,D0                  | D0 = 'STR ' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| GetIcon -- trap handler for _GetIcon ($A9BB).
| ----------------------------------------------------------
|
| _GetIcon ($A9BB)
|
GetIcon:
        MOVE.L  #0x49434F4E,D0                  | D0 = 'ICON' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| GetPicture -- _GetPicture ($A9BC): FUNCTION GetPicture (picID: INTEGER) : PicHandle;
| ----------------------------------------------------------
|
| _GetPicture ($A9BC)
|
GetPicture:
        MOVE.L  #0x50494354,D0                  | D0 = 'PICT' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| ----------------------------------------------------------
|
| _GetNewWindow ($A9BD)
|
GetNewWindow:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        CLR.L   0x12(A6)                        | clear return value (window ptr)
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57494E44,-(SP)               | push 'WIND' resource type
        MOVE    0x10(A6),-(SP)                  | push resource ID (param)
        _GetResource                            | load WIND template
        MOVE.L  (SP)+,A3                        | A3 = WIND resource handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWWINDOW_FOUND              | not found -> bail
        MOVE.L  (A3),A0                         | A0 = dereferenced WIND data
        SUBQ.W  #0x4,SP                         | space for NewWindow result
        MOVE.L  0xC(A6),-(SP)                   | push wStorage (behind param)
        MOVE.L  A0,-(SP)                        | push boundsRect from template
        PEA.L   0x12(A0)                        | push title string from template
        MOVE.L  0x8(A0),-(SP)                   | push visible + procID from template
        MOVE.L  0x8(A6),-(SP)                   | push behind window (param)
        MOVE    0xC(A0),-(SP)                   | push goAwayFlag from template
        MOVE.L  0xE(A0),-(SP)                   | push refCon from template
        BSET    #0x7,(A3)                       | lock WIND handle during NewWindow
        _NewWindow                              | create the window
        MOVE.L  (SP)+,0x12(A6)                  | store window ptr as return value
        MOVE.L  A3,-(SP)                        | push WIND handle
        _ReleaseResource                        | release the WIND template
GETNEWWINDOW_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDA    #0xA,SP                         | pop parameters (10 bytes)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetNewControl ($A9BE)
|
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
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetRMenu ($A9BF)
|
| Called during boot.
GetRMenu:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        MOVE    (ResLoad).w,-(SP)               | save current ResLoad state
        MOVEQ.L #0x0,D0                         | ResLoad = false (don't auto-load)
        BSR.B   GETRMENU_CONT                   | get MENU resource -> A3
        BEQ.B   GETRMENU_DONE                   | nil -> bail
        MOVE.L  (A3),D0                         | is MENU already loaded?
        BEQ.B   GETRMENU_NO                     | no -> try loading with ResLoad
        CLR.L   -(SP)                           | space for GetResInfo result
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE.L  0x6(A0),-(SP)                   | push menuProc handle
        CLR.L   -(SP)                           | ID placeholder (not needed)
        PEA.L   0x8(SP)                         | push ptr for type result
        CLR.L   -(SP)                           | name placeholder (nil)
        _GetResInfo                             | get resource type of menuProc
        MOVE.L  (SP)+,D0                        | D0 = resource type
        CMPI.L  #0x4D444546,D0                  | is it 'MDEF'?
        BEQ.B   GETRMENU_DONE                   | yes -> already set up, done
        BRA.B   GETRMENU_NO_2                   | no -> need to find MDEF

| ----------------------------------------------------------
|
| GETRMENU_NO
|
GETRMENU_NO:
        MOVEQ.L #0x1,D0                         | ResLoad = true (auto-load)
        BSR.B   GETRMENU_CONT                   | reload MENU resource -> A3
        BEQ.B   GETRMENU_DONE                   | nil -> bail
GETRMENU_NO_2:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D444546,-(SP)               | push 'MDEF' resource type
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE    0x6(A0),-(SP)                   | push menuProc ID from MENU data
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM map in search
        _GetResource                            | load MDEF resource
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE.L  (SP)+,0x6(A0)                   | store MDEF handle into MENU.menuProc
        MOVE.L  A3,-(SP)                        | push MENU handle
        _CalcMenuSize                           | compute menu dimensions
GETRMENU_DONE:
        _SetResLoad                             | restore saved ResLoad state
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop menuID parameter
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| GETRMENU_CONT
|
| Called during boot.
GETRMENU_CONT:
        MOVE.B  D0,-(SP)                        | push ResLoad flag (0 or 1)
        _SetResLoad                             | set auto-load mode
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D454E55,-(SP)               | push 'MENU' resource type
        MOVE    0x8(A6),-(SP)                   | push menu ID (param)
        _GetResource                            | load MENU resource
        MOVE.L  (SP)+,A3                        | A3 = MENU handle
        MOVE.L  A3,0xA(A6)                      | store as return value
        RTS                                     | return newly loaded MENU handle

| GetNewMBar -- _GetNewMBar ($A9C0): FUNCTION GetNewMBar (menuBarID: Integer): Handle;
| ----------------------------------------------------------
|
| _GetNewMBar ($A9C0)
|
GetNewMBar:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D3/A3,-(SP)                     | save registers
        CLR.L   0xA(A6)                         | clear return value (menu bar handle)
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | save current menu bar
        _ClearMenuBar                           | clear menu list
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D424152,-(SP)               | push 'MBAR' resource type
        MOVE    0x8(A6),-(SP)                   | push resource ID (param)
        _GetResource                            | load MBAR resource
        MOVE.L  (SP)+,A3                        | A3 = MBAR handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWMBAR_FOUND                | not found -> restore old bar
        MOVEQ.L #0x0,D3                         | D3 = menu index counter
GETNEWMBAR_LOOP:
        SUBQ.W  #0x4,SP                         | space for GetRMenu result
        MOVE.L  (A3),A0                         | dereference MBAR
        MOVE    D3,D0                           | D0 = index
        ADD     D0,D0                           | word offset
        MOVE    0x2(A0,D0.W),-(SP)              | push menu ID from MBAR list
        BSR     GetRMenu                        | load MENU resource -> handle on stack
        CLR     -(SP)                           | beforeID = 0 (append)
        _InsertMenu                             | add menu to menu bar
        MOVE.L  (A3),A0                         | dereference MBAR (may have moved)
        ADDQ.W  #0x1,D3                         | next index
        CMP     (A0),D3                         | processed all menus?
        BLT.B   GETNEWMBAR_LOOP                 | no -> continue loop
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | get newly built menu bar
        MOVE.L  (SP)+,0xA(A6)                   | store as return value
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
        JMP     (A0)                            | return to caller

| TEGetText -- _TEGetText ($A9CB): FUNCTION TEGetText (hTE: TEHandle) : CharsHandle;
| ----------------------------------------------------------
|
| _TEGetText ($A9CB)
|
TEGetText:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state (A3=TERec, A2=params)
        MOVE.L  teTextH(A3),(A2)                | return text handle to caller
        BRA     TECALTEXT_EXIT                  | -> TE exit

| ----------------------------------------------------------
|
| _TEInit ($A9CC)
|
| Called during boot.
| _TEInit ($A9CC): initialize TextEdit
| Sets up scrap handle and hook vectors for text operations
TEInit:
        MOVEQ.L #0x0,D0                         | zero-length handle
        MOVE    D0,(TEScrpLength).w             | clear TE scrap length
        _NewHandle                              | allocate empty scrap handle
        MOVE.L  A0,(TEScrpHandle).w             | save TE scrap handle
| install default hook routines
        LEA.L   P_TEDoText(PC),A0               | default text drawing/measuring
        MOVE.L  A0,(TEDoText).w                 | install TEDoText hook
        LEA.L   P_TERecal(PC),A0                | default line recalculation
        MOVE.L  A0,(TERecal).w                  | install TERecal hook
        LEA.L   P_TEWdBreak(PC),A0              | default word break detection
        MOVE.L  A0,(TEWdBreak).w                | install TEWdBreak hook
        RTS                                     | return from default hook installation

| ----------------------------------------------------------
|
| _TEDispose ($A9CD)
|
| Called during boot.
TEDispose:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers
        MOVE.L  0x8(A6),A4                      | A4 = TEHandle (param)
        MOVE.L  (A4),A3                         | A3 = dereferenced TERec
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        _DisposeHandle                          | free the text buffer
        MOVE.L  A4,A0                           | A0 = TEHandle
        _DisposeHandle                          | free the TERec itself
        MOVEQ.L #0x4,D0                         | param size = 4 (TEHandle)
        BRA     TETEXTBOX_EXIT_2                | -> clean up and return

| ----------------------------------------------------------
|
| _TETextBox ($A9CE)
|
| Called during boot.
TETextBox:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers
        MOVEQ.L #0x68,D0                        | base TERec size
        ADDI.L  #0x80,D0                        | plus overhead
        ADD.L   0xE(A6),D0                      | plus text length
        BSR     TEPASTE_CONT_3                  | check if enough memory available
        BNE     TETEXTBOX_NO                    | not enough -> bail
        MOVE.L  0x12(A6),A0                     | A0 = text pointer (param)
        MOVE.L  0xE(A6),D0                      | D0 = text length (param)
        BLT     TETEXTBOX_NO                    | negative length -> bail
        BEQ.B   TETEXTBOX_EMPTY                 | empty text -> try single-line path
TETEXTBOX_CONT:
        CMPI.B  #0xD,(A0)+                      | scan for carriage return
        BEQ.B   TETEXTBOX_FOUND                 | found CR -> use multi-line TENew path
        SUBQ.L  #0x1,D0                         | decrement scan counter
        BNE.B   TETEXTBOX_CONT                  | more chars -> keep scanning
TETEXTBOX_EMPTY:
        SUBQ.W  #0x2,SP                         | space for TextWidth result
        MOVE.L  0x12(A6),-(SP)                  | push text pointer
        CLR     -(SP)                           | firstByte = 0
        MOVE    0x10(A6),-(SP)                  | push byte count
        _TextWidth                              | measure text width
        MOVE    (SP)+,D3                        | D3 = text width in pixels
        MOVE.L  0xA(A6),A0                      | A0 = box rect pointer (param)
        MOVE    0x6(A0),D0                      | D0 = rect.right
        SUB     0x2(A0),D0                      | D0 = box width
        SUBQ.W  #0x2,D0                         | subtract 2 pixel margin
        CMP     D3,D0                           | text fits in one line?
        BLE.B   TETEXTBOX_FOUND                 | no -> use multi-line path
        MOVE.L  A0,-(SP)                        | push box rect
        _EraseRect                              | clear the box
        SUBQ.W  #0x8,SP                         | space for FontInfo (4 words)
        MOVE.L  A7,-(SP)                        | push FontInfo ptr
        _GetFontInfo                            | get current font metrics
        MOVE    (SP)+,D0                        | D0 = ascent
        ADDQ.W  #0x6,SP                         | skip descent, widMax, leading
        MOVE.L  0xA(A6),A0                      | A0 = box rect
        MOVE.L  (A0),-(SP)                      | push rect.top,left as pen position
        ADD     D0,(SP)                         | add ascent to top for baseline
        ADDQ.W  #0x1,0x2(SP)                    | indent 1 pixel from left edge
        _MoveTo                                 | position pen at first baseline
        TST     0x8(A6)                         | justification param (0=left)
        BEQ.B   TETEXTBOX_CONT_3                | left-justified -> draw directly
        MOVE.L  0xA(A6),A0                      | A0 = box rect
        MOVE    0x6(A0),D0                      | D0 = rect.right
        SUB     0x2(A0),D0                      | D0 = box width
        SUB     D3,D0                           | D0 = extra space after text
        SUBQ.W  #0x1,D0                         | account for margin
        TST     0x8(A6)                         | check justification sign
        BMI.B   TETEXTBOX_CONT_2                | negative (-1) = right-justify
        ASR     #0x1,D0                         | center: divide slack by 2
TETEXTBOX_CONT_2:
        MOVE    D0,-(SP)                        | push horizontal offset
        CLR     -(SP)                           | vertical offset = 0
        _Move                                   | adjust pen position
TETEXTBOX_CONT_3:
        MOVE.L  0x12(A6),-(SP)                  | push text pointer
        CLR     -(SP)                           | firstByte = 0
        MOVE    0x10(A6),-(SP)                  | push byte count
        _DrawText                               | draw the text
TETEXTBOX_NO:
        BRA.B   TETEXTBOX_EXIT                  | -> clean up and return

| ----------------------------------------------------------
|
| TETEXTBOX_FOUND
|
| Called during boot.
TETEXTBOX_FOUND:
        SUBQ.W  #0x4,SP                         | space for TENew result
        MOVE.L  0xA(A6),-(SP)                   | push destRect = box rect
        MOVE.L  (SP),-(SP)                      | push viewRect = same box rect
        MOVE.L  (SP),-(SP)                      | dup for EraseRect
        _EraseRect                              | clear the box area
        _TENew                                  | create temporary TERec
        MOVE.L  (SP)+,A4                        | A4 = TEHandle
        MOVE.L  (A4),A0                         | A0 = dereferenced TERec
        MOVE    0x8(A6),0x3A(A0)                | set teJust from param
        MOVE.L  0xE(A6),D0                      | D0 = text length
        BEQ.B   TETEXTBOX_SKIP                  | empty -> skip text setup
        MOVE.L  0x12(A6),-(SP)                  | push text pointer
        MOVE.L  D0,-(SP)                        | push text length
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TESetText                              | set the text content
        MOVE.L  0xA(A6),-(SP)                   | push update rect = box rect
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEUpdate                               | draw all text lines
TETEXTBOX_SKIP:
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEDispose                              | dispose temporary TERec
TETEXTBOX_EXIT:
        MOVEQ.L #0xE,D0                         | param size = 14 bytes
TETEXTBOX_EXIT_2:
        BRA     TECALTEXT_EXIT_3                | -> TE exit with cleanup

| ----------------------------------------------------------
|
| _TESetText ($A9CF)
|
| _TESetText ($A9CF): replace all text in a TextEdit field
| Pascal: procedure TESetText(text: Ptr; length: LongInt; hTE: TEHandle);
TESetText:
        BSR     XTRIMMEASURE_CONT_8             | set up TE state (A3, A2=params)
        MOVE.L  (A2)+,D0                        | D0 = text length
        MOVE    D0,BKPAT(A3)                    | selStart = length (cursor at end)
        MOVE    D0,teSelEnd(A3)                 | selEnd = length
        MOVE    D0,teLength(A3)                 | teLength = new length
        MOVE.L  (A2)+,A0                        | A0 = text pointer
        MOVE.L  teTextH(A3),A1                  | A1 = text handle
        BCLR    #0x7,(A1)                       | unlock text handle before resize
        _PtrToXHand                             | copy text to handle (resizes)
        MOVE.L  teTextH(A3),A0                  | re-lock text handle
        _HLock                                  | lock text for drawing
        BSR.B   TESETTEXT_CONT                  | recalculate line starts and redraw
TESETTEXT_EXIT:
        BRA     TEINSERT_EXIT                   | -> TE exit

| ----------------------------------------------------------
|
| TESETTEXT_CONT: recalculate all line starts after text change
| Clears selection, calls TERecal, then redraws
|
TESETTEXT_CONT:
        MOVE.L  BKPAT(A3),-(SP)                 | save selStart/selEnd
        CLR     BKPAT(A3)                       | clear selStart (for full recalc)
        MOVE    #-0x7FFE,D7                     | flag: full recalculation needed
        CLR.L   RGNSAVE(A3)                     | clear line cache
        BSR     P_doTERecal                     | recalculate all line breaks
        MOVE.L  (SP)+,BKPAT(A3)                 | restore selStart/selEnd
        RTS                                     | return from full recalculation

| TECalText -- _TECalText ($A9D0): PROCEDURE TECalText (hTE: TEHandle);
| ----------------------------------------------------------
|
| _TECalText ($A9D0)
|
TECalText:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state
        BSR.B   TESETTEXT_CONT                  | recalculate all line starts
TECALTEXT_EXIT:
        MOVEQ.L #0x4,D0                         | param size = 4 (TEHandle only)
TECALTEXT_EXIT_2:
        MOVE.L  0x8(A6),A4                      | A4 = TEHandle (re-read after calls)
        MOVE.L  (A4),A3                         | A3 = dereferenced TERec
        MOVE    D0,D4                           | D4 = saved param size
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.B  -0xC(A6),(A0)                   | restore text handle lock state
        MOVE.L  -0xA(A6),-(SP)                  | push saved clip region handle
        MOVE.L  (SP),-(SP)                      | dup for DisposeRgn
        _SetClip                                | restore original clip region
        _DisposeRgn                             | free temp clip region
        MOVE.B  -0x2(A6),(A4)                   | restore TEHandle lock state
        MOVE.L  -0x6(A6),-(SP)                  | push saved port
        _SetPort                                | restore original port
        MOVE    D4,D0                           | D0 = param size for cleanup
TECALTEXT_EXIT_3:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDA    D0,SP                           | pop parameters
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _TESetSelect ($A9D1)
|
TESetSelect:
        BSR     XTRIMMEASURE_CONT_8             | set up TE state (12 bytes params)
        BSR     P_TERECAL_CONT_3                | hide caret if visible
        BSR     TEUPDATE_CONT_2                 | unhighlight old selection
        MOVE    0xE(A6),teSelEnd(A3)            | teSelEnd = new selEnd param
        MOVE    0x12(A6),BKPAT(A3)              | teSelStart = new selStart param
        BSR     XTRIMMEASURE_CONT_14            | clamp selection to text length
        BSR     P_TERECAL_NO_3                  | set up caret state if no selection
        BSR     TEUPDATE_CONT_2                 | highlight new selection
        BSR     FILLCARC_CONT                   | auto-scroll selection into view
        BRA     TESETTEXT_EXIT                  | -> TE exit

| ----------------------------------------------------------
|
| _TENew ($A9D2)
|
| _TENew ($A9D2): create a new TextEdit record
| Pascal: function TENew(destRect, viewRect: Rect): TEHandle;
| Allocates a 104-byte TERec, sets up text handle, font metrics
TENew:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers
        CLR.L   0x10(A6)                        | clear return value (TEHandle)
        MOVEQ.L #0x68,D0                        | 104 bytes = sizeof(TERec)
        _NewHandleClear                         | allocate zeroed TERec
        BMI.B   TENEW_ERR                       | failed ->
        MOVE.L  A0,A4                           | A4 = TEHandle
        BSET    #0x7,(A4)                       | lock the handle
        MOVE.L  (A4),A3                         | A3 = dereferenced TERec
| allocate empty text handle
        MOVEQ.L #0x0,D0                         | zero-length handle
        _NewHandle                              | empty text buffer
        MOVE.L  A0,teTextH(A3)                  | TERec.hText = text handle
| copy destRect and viewRect from parameters
        LEA.L   (A3),A0                         | A0 = TERec (destRect at offset 0)
        MOVE.L  0xC(A6),A2                      | A2 = destRect parameter
        MOVE.L  (A2)+,(A0)+                     | copy destRect.topLeft
        MOVE.L  (A2)+,(A0)+                     | copy destRect.botRight
        MOVE.L  0x8(A6),A2                      | A2 = viewRect parameter
        MOVE.L  (A2)+,(A0)+                     | copy viewRect.topLeft
        MOVE.L  (A2)+,(A0)+                     | copy viewRect.botRight
| get font metrics for line height calculation
        SUBQ.W  #0x8,SP                         | space for FontInfo
        MOVE.L  A7,-(SP)                        | push FontInfo ptr
        _GetFontInfo                            | query current font metrics via trap
        MOVE    (SP)+,D0                        | D0 = font ascent
        MOVE    D0,0x1A(A3)                     | teAscent = ascent
        ADD     (SP)+,D0                        | add descent
        ADDQ.W  #0x2,SP                         | skip widMax
        ADD     (SP)+,D0                        | add leading
        MOVE    D0,VISRGN(A3)                   | teLineHite = ascent+descent+leading
        MOVE.L  (A5),A2                         | A2 = app globals handle
        MOVE.L  (A2),A2                         | A2 = dereferenced (current GrafPort)
        MOVE.L  A2,teInPort(A3)                 | teGrafPort = current port
        MOVE.L  0x44(A2),TXSIZE(A3)             | copy port txFont+txFace to TERec
        MOVE.L  0x48(A2),teMode(A3)             | copy port txMode+txSize to TERec
        MOVE.L  (TEWdBreak).w,teWordBreak(A3)   | set default word break routine
        LEA.L   CPOLY_DO_FILL_LOOP(PC),A0       | A0 = default click loop proc
        MOVE.L  A0,teClikProc(A3)               | teClikProc = default
        BCLR    #0x7,(A4)                       | unlock TEHandle
        MOVE.L  A4,0x10(A6)                     | store TEHandle as return value
TENEW_ERR:
        MOVEQ.L #0x8,D0                         | param size = 8 (two rect ptrs)
        BRA     TECALTEXT_EXIT_3                | -> TE exit

| ----------------------------------------------------------
|
| _TEUpdate ($A9D3)
|
| Called during boot.
TEUpdate:
        BSR     XTRIMMEASURE_CONT_10            | set up TE state (8 bytes params)
        MOVE.L  (A2)+,A0                        | A0 = update rect ptr (param)
        BSR     TESETALIGNMENT_CONT             | redraw text within update rect
        BRA     TESCROLL_EXIT                   | -> TE exit (8 bytes)

| TEUPDATE_CONT -- get word bounds if double-click.
| ----------------------------------------------------------
|
| TEUPDATE_CONT
|
TEUPDATE_CONT:
        MOVE    D6,D0                           | D0 = char offset (click position)
        MOVE    D6,D1                           | D1 = same (default: single char)
        TST.L   D5                              | double-click active?
        BPL.B   TEUPDATE_EXIT                   | no -> return single char range
        BSR     TEDELETE_CONT_3                 | expand to word boundaries -> D0,D1
TEUPDATE_EXIT:
        RTS                                     | return calculated click offset

| ----------------------------------------------------------
|
| TEUPDATE_CONT_2
|
| Called during boot.
TEUPDATE_CONT_2:
        TST.B   teActive(A3)                    | is TE record active?
        BEQ.B   TEUPDATE_EXIT                   | no -> nothing to highlight
        MOVEM   BKPAT(A3),D3-D4                 | D3=teSelStart, D4=teSelEnd
        MOVEQ.L #0x1,D7                         | D7=1: highlight/unhighlight mode
        BRA     P_doTEDoText                    | -> draw/erase selection hilite

| ----------------------------------------------------------
|
| _TEClick ($A9D4)
|
| _TEClick ($A9D4): handle a mouse click in a TextEdit field
| Pascal: procedure TEClick(pt: Point; extend: BOOLEAN; hTE: TEHandle);
| Sets selection, handles double-click word selection, tracks drag
TEClick:
        BSR     XTRIMMEASURE_CONT_9             | set up TE state (A3, A6 frame)
        MOVE.L  0xE(A6),CLIPRGN(A3)             | save click point
        BSR     TECLICK_CONT_5                  | convert point to char offset -> D6
        BSR     P_TERECAL_CONT_3                | hide caret if visible
| detect double-click: compare click time with previous
        SUBQ.W  #0x4,SP                         | room for tick count result
        _TickCount                              | get current tick count
        MOVE.L  (SP),D0                         | D0 = current ticks
        SUB.L   teClikTime(A3),D0               | D0 = elapsed since last click
        CMP.L   (DoubleTime).w,D0               | within double-click interval?
        SLE.B   D5                              | D5 = $FF if double-click timing
        CMP     0x32(A3),D6                     | same char position as last click?
        SEQ.B   D1                              | D1 = $FF if same position
        AND.B   D1,D5                           | D5 = double-click (time AND position)
        ROR.L   #0x8,D5                         | shift flag to high byte
        MOVE    D6,0x32(A3)                     | save click position for next time
        MOVE.L  (SP)+,teClikTime(A3)            | save click time
        TST.B   0xC(A6)                         | extend flag (shift-click)?
        BEQ.B   TECLICK_NO_2                    | no -> start fresh selection
        MOVEM   BKPAT(A3),D0-D1                 | D0=teSelStart, D1=teSelEnd
        CMP     D6,D0                           | click before selStart?
        BCC.B   TECLICK_NO                      | no -> extend from selEnd
        MOVE    D0,A2                           | A2 = anchor at selStart
        MOVE    D0,A4                           | A4 = anchor at selStart
        BRA.B   TECLICK_CONT                    | -> update with new position

| ----------------------------------------------------------
|
| TECLICK_NO
|
TECLICK_NO:
        MOVE    D1,A2                           | A2 = anchor at selEnd
        MOVE    D1,A4                           | A4 = anchor at selEnd
TECLICK_CONT:
        MOVE    D6,D5                           | D5 = current tracking position
        BRA.B   TECLICK_CONT_2                  | -> update selection highlighting

| ----------------------------------------------------------
|
| TECLICK_NO_2
|
TECLICK_NO_2:
        BSR.B   TEUPDATE_CONT_2                 | unhighlight current selection
        MOVEQ.L #0x4,D2                         | D2=4: findWord mode (initial click)
        BSR.B   TEUPDATE_CONT                   | get word bounds if double-click
        MOVEM   D0-D1,BKPAT(A3)                 | set teSelStart/teSelEnd
        MOVE    D0,A2                           | A2 = selection anchor start
        MOVE    D1,A4                           | A4 = selection anchor end
        MOVE    D6,D5                           | D5 = current tracking position
        MOVE.B  TXFACE(A3),0x47(A3)             | save teLftClick to teLftCaret
        BSR     P_TERECAL_NO_3                  | set caret state if insertion point
        BSR     TEUPDATE_CONT_2                 | highlight new selection
TECLICK_LOOP:
        MOVE.L  teClikProc(A3),D0               | D0 = click loop proc
        BEQ.B   TECLICK_EMPTY                   | nil -> use default WaitMouseUp
        MOVE.L  D0,A0                           | A0 = click loop proc
        JSR     (A0)                            | call app's click loop; Z=abort
        BEQ.B   TECLICK_CONT_4                  | app says stop -> end tracking
TECLICK_EMPTY:
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | wait for mouse movement or release
        TST     (SP)+                           | still tracking?
        BEQ.B   TECLICK_CONT_4                  | mouse released -> end tracking
        PEA.L   CLIPRGN(A3)                     | push ptr to teSelPoint for GetMouse
        _GetMouse                               | read current mouse position
        BSR.B   TECLICK_CONT_5                  | convert point to char offset -> D6
        CMP     D6,D5                           | position changed?
        BEQ.B   TECLICK_LOOP                    | same -> keep waiting
        BSR     P_TERECAL_CONT_3                | hide caret before hilite update
TECLICK_CONT_2:
        MOVEQ.L #0x8,D2                         | D2=8: findWord mode (drag tracking)
        BSR     TEUPDATE_CONT                   | expand to word bounds if double-click
        LEA.L   teSelEnd(A3),A0                 | A0 -> teSelEnd field
        CMPA    D6,A4                           | click before anchor end?
        BCS.B   TECLICK_OK                      | yes -> extending forward
| dragging backward: update selStart
        MOVE    -(A0),D3                        | D3.W = old teSelStart
        MOVE    D0,(A0)+                        | teSelStart = new start
        MOVE    D0,D4                           | D4.W = new start
        SWAP    D3                              | D3: old selStart in high word
        SWAP    D4                              | D4: new start in high word
        MOVE    A4,D3                           | D3.W = anchor position
        MOVE    (A0)+,D4                        | D4.W = old teSelEnd
        MOVE    A4,-(A0)                        | teSelEnd = anchor
        BRA.B   TECLICK_CONT_3                  | -> XOR hilite for both ranges

| ----------------------------------------------------------
|
| TECLICK_OK
|
TECLICK_OK:
        CMPA    D6,A2                           | click still within anchor range?
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
        BSR     P_doTEDoText                    | XOR hilite for first changed range
        SWAP    D3                              | swap to second range pair
        SWAP    D4                              | swap to second range pair
        BSR     P_doTEDoText                    | XOR hilite for second changed range
TECLICK_OK_2:
        MOVE    D6,D5                           | D5 = updated tracking position
        BRA.B   TECLICK_LOOP                    | -> continue tracking loop

| ----------------------------------------------------------
|
| TECLICK_CONT_4
|
TECLICK_CONT_4:
        BSR     P_TERECAL_NO_3                  | set caret state if insertion point
        MOVEQ.L #0xA,D0                         | param size = 10 bytes
        BRA     TECALTEXT_EXIT_2                | -> TE exit

| TECLICK_CONT_5 -- convert point to char offset -> D6.
| ----------------------------------------------------------
|
| TECLICK_CONT_5
|
TECLICK_CONT_5:
        MOVE    CLIPRGN(A3),D0                  | D0 = click vertical coord (teSelPoint.v)
        BSR     XTRIMMEASURE_CONT_6             | convert to line number -> D0
        BGE.B   TECLICK_CONT_6                  | beyond last line -> selEnd
        ADD     D0,D0                           | word offset into lineStarts array
        BPL.B   TECLICK_CONT_7                  | valid line -> measure char offset
        MOVEQ.L #0x0,D6                         | before first line -> offset 0
        RTS                                     | return offset 0 for click before first line

| ----------------------------------------------------------
|
| TECLICK_CONT_6
|
TECLICK_CONT_6:
        MOVE    teLength(A3),D6                 | click past end -> offset = teLength
        RTS                                     | return offset teLength for click past end

| ----------------------------------------------------------
|
| TECLICK_CONT_7
|
TECLICK_CONT_7:
        MOVEM   0x60(A3,D0.W),D3-D4             | D3=lineStart, D4=nextLineStart
        MOVEQ.L #0x0,D7                         | D7=0: pixel-to-char conversion mode
        BSR     P_doTEDoText                    | find char offset at click.h -> D0
        MOVE    D0,D6                           | D6 = character offset at click point
        RTS                                     | return measured character offset

| ----------------------------------------------------------
|
| TECLICK_FOUND
|
TECLICK_FOUND:
        MOVEM.L D2-D7/A2-A4,-(SP)               | save all registers
        LEA.L   0x60(A3,D0.W),A2                | A2 -> lineStarts[lineNum]
        MOVE    D3,D4                           | D4 = click horizontal position
        MOVE    (A2),D3                         | D3 = line start offset
        MOVEQ.L #0x0,D4                         | clear D4
        MOVE    D3,D4                           | D4 = line start (search from here)
        ADDQ.W  #0x1,D4                         | start testing from char after lineStart
        BSR     P_TEDOTEXT_CONT_2               | compute line rect and pen position
        MOVE    -0x6(A6),D5                     | D5 = left edge x coordinate
TECLICK_NO_3:
        BSR     XTRIMMEASURE_CONT_2             | compute rect for chars D3..D4 on line
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  CLIPRGN(A3),-(SP)               | push click point (teSelPoint)
        PEA.L   PORTRECT(A3)                    | push computed char rect
        _PtInRect                               | is click in this char's rect?
        TST.B   (SP)+                           | test result
        BNE.B   TECLICK_FOUND_2                 | yes -> found the character
        MOVE    -0xA(A6),D5                     | D5 = right edge of tested char
        ADDQ.W  #0x1,D4                         | try next character
        CMP     0x2(A2),D4                      | past end of line?
        BLS.B   TECLICK_NO_3                    | no -> keep scanning
        MOVEQ.L #0x1,D4                         | default to after line start
        BRA.B   TECLICK_EXIT                    | -> return offset

| ----------------------------------------------------------
|
| TECLICK_FOUND_2
|
TECLICK_FOUND_2:
        SF.B    TXFACE(A3)                      | teLftClick = false (right side of char)
        CMPI    #0x7FFE,0x16(A3)                | special line-end flag?
        BNE.B   TECLICK_NO_4                    | no -> check horizontal position
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | dereference text
        CMPI.B  #0xD,-0x1(A0,D4.L)              | char before cursor is CR?
        BEQ.B   TECLICK_EXIT                    | yes -> click is at start of next line
TECLICK_NO_4:
        MOVE    -0xA(A6),D0                     | D0 = right edge of char rect
        SUB     0x1E(A3),D0                     | subtract click.h
        SUB     0x1E(A3),D0                     | double subtract for midpoint test
        ADD     D5,D0                           | add left edge
        BLT.B   TECLICK_CONT_8                  | click in right half -> after char
TECLICK_EXIT:
        SUBQ.W  #0x1,D4                         | click in left half -> before char
        ST.B    TXFACE(A3)                      | teLftClick = true (left side)
TECLICK_CONT_8:
        MOVE    D4,D0                           | D0 = char offset result
        BRA.B   TECLICK_EXIT_2                  | -> clean up and return

| ----------------------------------------------------------
|
| TECLICK_OK_3
|
| Called during boot.
TECLICK_OK_3:
        BSR     XTRIMMEASURE_CONT_3             | clip D3,D4 to visible line range
        BSR.B   TECLICK_CONT_10                 | find starting lineStarts entry -> A2
TECLICK_NEXT:
        BSR.B   TECLICK_CONT_9                  | set up line rect; test if more lines
        BLS.B   TECLICK_EXIT_2                  | no more visible lines -> done
        PEA.L   PORTRECT(A3)                    | push line rect
        _EraseRect                              | clear line background
        MOVE.L  -0x10(A6),-(SP)                 | push line top-left position
        MOVE    0x1A(A3),D0                     | D0 = teAscent
        ADD     D0,(SP)                         | add ascent for baseline y
        _MoveTo                                 | position pen at baseline
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | dereference text buffer
        ADDA.L  D3,A0                           | A0 = ptr to line start
        MOVE.L  A0,-(SP)                        | push text ptr
        CLR     -(SP)                           | firstByte = 0
        MOVE    D4,-(SP)                        | push byte count
        SUB     D3,(SP)                         | count = lineEnd - lineStart
        _DrawText                               | draw the line of text
        ADDQ.W  #0x2,A2                         | advance to next lineStarts entry
        MOVE    (A2),D3                         | D3 = next line start offset
        BRA.B   TECLICK_NEXT                    | -> draw next line

| ----------------------------------------------------------
|
| TECLICK_EXIT_2
|
| Called during boot.
TECLICK_EXIT_2:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (A5),A0                         | A0 = app globals handle
        MOVE.L  (A0),A0                         | A0 = current GrafPort
        RTS                                     | return active GrafPort in A0

| ----------------------------------------------------------
|
| TECLICK_CONT_9
|
| Called during boot.
TECLICK_CONT_9:
        BSR     P_TEDOTEXT_CONT_2               | compute line rect for current line
        MOVE    D5,D4                           | D4 = end offset for range clipping
        CMP     0x2(A2),D4                      | past next line start?
        BCS.B   TECLICK_OK_4                    | no -> use D4 as is
        MOVE    0x2(A2),D4                      | clamp to next line start
TECLICK_OK_4:
        BSR     XTRIMMEASURE_CONT_2             | compute pixel rect for D3..D4 range
        CMP     D3,D5                           | compare start with end offset
        RTS                                     | CC reflects if more lines to process

| ----------------------------------------------------------
|
| TECLICK_CONT_10
|
| Called during boot.
TECLICK_CONT_10:
        MOVE.L  (SP)+,A0                        | pop return address (non-standard call)
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers for TEDoText
        MOVE.L  A0,-(SP)                        | re-push return address
        CMP     D3,D4                           | ensure D3 <= D4 (sort range)
        BCC.B   TECLICK_CONT_11                 | already sorted
        EXG     D4,D3                           | swap so D3 = start, D4 = end
TECLICK_CONT_11:
        CMP     teLength(A3),D4                 | D4 past text end?
        BCS.B   TECLICK_OK_5                    | no -> OK
        MOVE    teLength(A3),D4                 | clamp D4 to teLength
TECLICK_OK_5:
        LEA.L   RGNSAVE(A3),A2                  | A2 -> lineStarts[0] (teLines at 0x60)
  .short 0xC8BA,0x03A0                          | And.L (PCrel $168A4 ), D4
        MOVE    D4,D5                           | D5 = clamped end offset
  .short 0xC6BA,0x039A                          | And.L (PCrel $168A4 ), D3
        BEQ.B   TECLICK_DONE                    | D3=0 -> already at first line
TECLICK_CONT_12:
        CMP     0x2(A2),D3                      | D3 past this lineStart?
        BLS.B   TECLICK_FOUND_3                 | no -> found the right line
        ADDQ.W  #0x2,A2                         | advance to next lineStarts entry
        BRA.B   TECLICK_CONT_12                 | -> keep scanning

| ----------------------------------------------------------
|
| TECLICK_FOUND_3
|
TECLICK_FOUND_3:
        BNE.B   TECLICK_DONE                    | D3 within line -> done
        ADDQ.W  #0x2,A2                         | D3 at line boundary -> next entry
TECLICK_DONE:
        RTS                                     | return from line boundary check

| ----------------------------------------------------------
|
| P_do TE Do Text
|
| Called during boot.
P_doTEDoText:
        MOVE.L  (TEDoText).w,-(SP)              | push TEDoText vector and jump
        RTS                                     | (RTS used as indirect JMP)

| ----------------------------------------------------------
|
| P_TE Do Text
|
| Called during boot.
P_TEDoText:
        LINK    A6,#-0x10                       | 16 bytes locals for line rect coords
        TST     D7                              | dispatch on mode
        BEQ     TECLICK_FOUND                   | D7=0: hit test (pixel to char)
        BGT.B   P_TEDOTEXT_CONT                 | D7>0: highlight selection
        CMPI    #-0x1,D7                        | D7=-1: draw text
        BEQ     TECLICK_OK_3                    | yes -> draw text lines
| D7=-2: caret drawing mode
        BSR.B   TECLICK_CONT_10                 | find lineStarts entry for caret pos
        TST     D3                              | caret at start of text?
        BEQ.B   P_TEDOTEXT_EMPTY                | yes -> draw caret on first line
        CMP     (A2),D3                         | caret at start of this line?
        BNE.B   P_TEDOTEXT_EMPTY                | no -> draw on current line
        MOVE    teLength(A3),D0                 | D0 = text length
        BEQ.B   P_TEDOTEXT_EMPTY                | empty text -> current line
        CMP     D0,D3                           | caret at very end of text?
        BCS.B   P_TEDOTEXT_NO                   | no -> check caret side
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | dereference text
        CMPI.B  #0xD,-0x1(A0,D3.L)              | last char is CR?
        BEQ.B   P_TEDOTEXT_EMPTY                | yes -> caret on next (empty) line
        BRA.B   P_TEDOTEXT_NO_2                 | no -> caret belongs on previous line

| ----------------------------------------------------------
|
| P_TEDOTEXT_NO
|
P_TEDOTEXT_NO:
        TST.B   0x47(A3)                        | teLftCaret set? (caret on left side)
        BNE.B   P_TEDOTEXT_EMPTY                | yes -> keep on current line
P_TEDOTEXT_NO_2:
        SUBQ.W  #0x2,A2                         | move back one lineStarts entry
P_TEDOTEXT_EMPTY:
        BSR     TECLICK_CONT_9                  | compute caret rect on this line
        MOVE    -0xE(A6),D0                     | D0 = caret x position (right edge)
        MOVE    D0,0x16(A3)                     | store caret rect right
        SUBQ.W  #0x1,D0                         | caret is 1 pixel wide
        MOVE    D0,0x12(A3)                     | store caret rect left
        BRA     TECLICK_EXIT_2                  | -> clean up and return

| ----------------------------------------------------------
|
| P_TEDOTEXT_CONT
|
| Called during boot.
P_TEDOTEXT_CONT:
        BSR     XTRIMMEASURE_CONT_3             | clip D3,D4 to visible line range
        BSR     TECLICK_CONT_10                 | find starting lineStarts entry -> A2
P_TEDOTEXT_NEXT:
        BSR     TECLICK_CONT_9                  | set up line rect; check if more lines
        BLS.B   P_TEDOTEXT_EXIT                 | done -> exit
        MOVE.L  teHighHook(A3),D0               | D0 = custom highlight hook
        BSR     XTRIMMEASURE_CONT_7             | invert/highlight selection rect
        ADDQ.W  #0x2,A2                         | advance to next lineStarts entry
        MOVE    (A2),D3                         | D3 = next line start offset
        BRA.B   P_TEDOTEXT_NEXT                 | -> process next line

| ----------------------------------------------------------
|
| P_TEDOTEXT_EXIT
|
| Called during boot.
P_TEDOTEXT_EXIT:
        BRA     TECLICK_EXIT_2                  | -> TEDoText exit

| ----------------------------------------------------------
|
| P_TEDOTEXT_CONT_2
|
| Called during boot.
P_TEDOTEXT_CONT_2:
        LEA.L   RGNSAVE(A3),A0                  | A0 -> lineStarts[0] (teLines base)
        MOVE.L  A2,D0                           | D0 = current lineStarts ptr
        SUB.L   A0,D0                           | D0 = byte offset from lineStarts[0]
        ASR.L   #0x1,D0                         | D0 = line index (word entries)
        MOVE    VISRGN(A3),D1                   | D1 = teLineHite (line height)
        MULU    D1,D0                           | D0 = pixel y offset for this line
        LEA.L   PORTBOUNDS(A3),A0               | A0 -> destRect.botRight+2
        LEA.L   (A6),A1                         | A1 -> local rect on stack frame
        MOVE.L  -(A0),-(A1)                     | copy destRect.botRight to local rect
        MOVE.L  -(A0),-(A1)                     | copy destRect.topLeft to local rect
        ADD     D0,(A1)                         | rect.top += line y offset
        MOVE    (A1),0x4(A1)                    | rect.bottom = rect.top
        ADD     D1,0x4(A1)                      | rect.bottom += lineHeight
        TST     PNPAT(A3)                       | teJust = 0 (left justified)?
        BEQ.B   P_TEDOTEXT_OK                   | yes -> no horizontal adjustment
        BSR.B   P_TEDOTEXT_CONT_4               | measure text width -> D0
        MOVE    0x6(A3),D1                      | D1 = destRect.right
        SUB     PORTBITS(A3),D1                 | subtract destRect.left = box width
        SUB     D0,D1                           | D1 = slack (box width - text width)
        SUBQ.W  #0x1,D1                         | adjust for margin
        TST     PNPAT(A3)                       | check justification
        BMI.B   P_TEDOTEXT_CONT_3               | negative = right-justify (full slack)
        ASR     #0x1,D1                         | center: half the slack
P_TEDOTEXT_CONT_3:
        ADD     D1,-0x6(A6)                     | adjust rect.left for justification
        ADD     D1,-0x2(A6)                     | adjust rect.right for justification
P_TEDOTEXT_OK:
        ADDQ.W  #0x1,-0x6(A6)                   | indent 1 pixel from left edge
        MOVE    -0x6(A6),-0x2(A6)               | set pen x = adjusted left edge
        RTS                                     | return from text justification adjustment

| ----------------------------------------------------------
|
| P_TEDOTEXT_CONT_4
|
| Called during boot.
P_TEDOTEXT_CONT_4:
        MOVE    (A2),D6                         | D6 = line start offset
        MOVE    0x2(A2),D7                      | D7 = next line start offset
| P_XTrimMeasure -- measure trimmed line width -> D0.
P_XTrimMeasure:
        MOVE.L  (0x7F4).w,-(SP)                 | dispatch vector: _XTrimMeasure
        RTS                                     | return from _XTrimMeasure dispatch

| ----------------------------------------------------------
|
| X Trim Measure
|
| Called during boot.
XTrimMeasure:
        CMP     teLength(A3),D6                 | line starts at end of text?
        BEQ.B   XTRIMMEASURE_EXIT               | yes -> zero width
        CMP     D6,D7                           | empty line?
        BLS.B   XTRIMMEASURE_EXIT               | yes -> zero width
XTRIMMEASURE_OK:
        SUBQ.W  #0x1,D7                         | trim trailing whitespace
        CMP     D6,D7                           | trimmed to line start?
        BEQ.B   XTRIMMEASURE_OK_2               | yes -> measure what's left
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | dereference text
  .short 0xCEBA,0x0292                          | And.L (PCrel $168A4 ), D7
        CMPI.B  #0x20,0x0(A0,D7.L)              | char at D7 is space or control?
        BLS.B   XTRIMMEASURE_OK                 | yes -> keep trimming
XTRIMMEASURE_OK_2:
        ADDQ.W  #0x1,D7                         | point past last non-space char
| XTRIMMEASURE_CONT -- measure width from lineStart to D3.
XTRIMMEASURE_CONT:
        CMP     D6,D7                           | any text to measure?
        BLS.B   XTRIMMEASURE_EXIT               | no -> return 0
        SUBQ.W  #0x2,SP                         | space for TextWidth result
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | dereference text
  .short 0xCCBA,0x0278                          | And.L (PCrel $168A4 ), D6
        ADDA.L  D6,A0                           | A0 = ptr to start of range
        MOVE.L  A0,-(SP)                        | push text ptr
        CLR     -(SP)                           | firstByte = 0
        MOVE    D7,-(SP)                        | push byte count
        SUB     D6,(SP)                         | count = end - start
        _TextWidth                              | measure text width -> result on stack
        MOVE    (SP)+,D0                        | D0 = width in pixels
        RTS                                     | return measured text width in D0

| ----------------------------------------------------------
|
| XTRIMMEASURE_EXIT
|
| Called during boot.
XTRIMMEASURE_EXIT:
        MOVEQ.L #0x0,D0                         | return width = 0
        RTS                                     | return 0 width for empty text

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_2
|
| Called during boot.
XTRIMMEASURE_CONT_2:
        MOVE    (A2),D6                         | D6 = line start offset
        MOVE    D3,D7                           | D7 = range start
        BSR.B   XTRIMMEASURE_CONT               | measure width from lineStart to D3
        LEA.L   (A6),A0                         | A0 -> line rect (from P_TEDOTEXT_CONT_2)
        LEA.L   -0x8(A6),A1                     | A1 -> char range rect (local)
        MOVE.L  -(A0),-(A1)                     | copy line rect bottom-right
        MOVE.L  -(A0),-(A1)                     | copy line rect top-left
        ADD     D0,0x2(A1)                      | rect.left += width to D3 start
        MOVE    D4,D7                           | D7 = range end
        BSR.B   XTRIMMEASURE_CONT               | measure width from lineStart to D4
        ADD     D0,-0xA(A6)                     | rect.right = rect.left + range width
        LEA.L   -0x8(A6),A0                     | A0 -> computed char rect
        LEA.L   VISRGN(A3),A1                   | A1 -> teSelRect (reused as temp rect)
        MOVE.L  -(A0),-(A1)                     | copy to teSelRect.botRight
        MOVE.L  -(A0),-(A1)                     | copy to teSelRect.topLeft
        MOVE    0x2(A1),(scratch8).w            | save pen x to scratch
        MOVE.L  0x4(A1),-(SP)                   | push rect.bottom,right for MoveTo
        CMP     (A2),D3                         | D3 at start of line?
        BNE.B   XTRIMMEASURE_NO                 | no -> leave left as computed
        MOVE    #-0x7FFE,0x2(A1)                | extend left to -32766 (full line left)
XTRIMMEASURE_NO:
        CMP     0x2(A2),D4                      | D4 at end of line?
        BNE.B   XTRIMMEASURE_NO_2               | no -> leave right as computed
        MOVE    #0x7FFE,0x6(A1)                 | extend right to 32766 (full line right)
XTRIMMEASURE_NO_2:
        _MoveTo                                 | position pen at range end
        RTS                                     | return from pen positioning at range end

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_3
|
| Called during boot.
XTRIMMEASURE_CONT_3:
        LEA.L   PORTBOUNDS(A3),A0               | A0 -> viewRect (teViewRect at 0x08)
| XTRIMMEASURE_CONT_4 -- clip to visible lines in update rect.
XTRIMMEASURE_CONT_4:
        MOVE    (A0),D0                         | D0 = viewRect.top
        BSR.B   XTRIMMEASURE_CONT_6             | convert to line number -> D0
        BGE.B   XTRIMMEASURE_CONT_5             | past last line -> collapse range
        ADD     D0,D0                           | word offset into lineStarts
        BLT.B   XTRIMMEASURE_SKIP               | before first line -> skip top clip
        CMP     0x60(A3,D0.W),D3                | D3 before top visible line start?
        BCC.B   XTRIMMEASURE_NO_3               | no -> check D4
        MOVE    0x60(A3,D0.W),D3                | clamp D3 to first visible line start
XTRIMMEASURE_NO_3:
        CMP     0x60(A3,D0.W),D4                | D4 before top visible line?
        BCC.B   XTRIMMEASURE_SKIP               | no -> proceed to bottom clip
        MOVE    0x60(A3,D0.W),D4                | clamp D4 to first visible line start
XTRIMMEASURE_SKIP:
        MOVE    0x4(A0),D0                      | D0 = viewRect.bottom
        ADD     VISRGN(A3),D0                   | add one lineHeight
        SUBQ.W  #0x1,D0                         | pixel before next line below view
        BSR.B   XTRIMMEASURE_CONT_6             | convert to line number -> D0
        BGE.B   XTRIMMEASURE_DONE               | past last line -> no bottom clip
        ADD     D0,D0                           | word offset into lineStarts
        CMP     0x60(A3,D0.W),D3                | D3 past bottom visible line?
        BCS.B   XTRIMMEASURE_NO_4               | no -> check D4
        MOVE    0x60(A3,D0.W),D3                | clamp D3 to last visible line start
XTRIMMEASURE_NO_4:
        CMP     0x60(A3,D0.W),D4                | D4 past bottom visible line?
        BCS.B   XTRIMMEASURE_DONE               | no -> done
        MOVE    0x60(A3,D0.W),D4                | clamp D4 to last visible line start
XTRIMMEASURE_DONE:
        RTS                                     | return clamped visible line range

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_5
|
XTRIMMEASURE_CONT_5:
        MOVE    D3,D4                           | collapse range (nothing visible)
        RTS                                     | return collapsed zero-width range

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_6
|
| Called during boot.
XTRIMMEASURE_CONT_6:
        SUB     (A3),D0                         | D0 = pixel y - destRect.top
        EXT.L   D0                              | sign extend for division
        DIVS    VISRGN(A3),D0                   | D0 = line number (y / lineHeight)
        CMP     teNLines(A3),D0                 | compare with total lines (sets CC)
        RTS                                     | caller checks GE for past-end

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_7
|
| Called during boot.
XTRIMMEASURE_CONT_7:
        PEA.L   PORTRECT(A3)                    | push selection rect for hilite
        BEQ.B   XTRIMMEASURE_NO_5               | D0=0 (no hook) -> use InvertRect
        MOVE.L  D0,A0                           | A0 = custom highlight hook
        JMP     (A0)                            | call hook with rect on stack

| ----------------------------------------------------------
|
| XTRIMMEASURE_NO_5
|
| Called during boot.
XTRIMMEASURE_NO_5:
        _InvertRect                             | default: invert the rect (XOR hilite)
        RTS                                     | return from default invert rect hook

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_8
|
| Called during boot.
XTRIMMEASURE_CONT_8:
        MOVEQ.L #0xC,D1                         | 12 bytes of params (TESetText, etc.)
        BRA.B   XTRIMMEASURE_CONT_13            | -> common TE setup

| XTRIMMEASURE_CONT_9 -- set up TE state (A3, A6 frame).
| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_9
|
XTRIMMEASURE_CONT_9:
        MOVEQ.L #0xA,D1                         | 10 bytes of params (TEClick)
        BRA.B   XTRIMMEASURE_CONT_13            | -> common TE setup

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_10
|
| Called during boot.
XTRIMMEASURE_CONT_10:
        MOVEQ.L #0x8,D1                         | 8 bytes of params (TEUpdate, TEScroll)
        BRA.B   XTRIMMEASURE_CONT_13            | -> common TE setup

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_11
|
XTRIMMEASURE_CONT_11:
        MOVEQ.L #0x6,D1                         | 6 bytes of params (TEKey)
        BRA.B   XTRIMMEASURE_CONT_13            | -> common TE setup

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_12
|
| Called during boot (2,775 times in 30s trace).
XTRIMMEASURE_CONT_12:
        MOVEQ.L #0x4,D1                         | 4 bytes of params (TEHandle only)
XTRIMMEASURE_CONT_13:
        MOVE.L  (SP)+,A0                        | pop return address
        LINK    A6,#-0xC                        | 12 bytes locals for state save
        MOVEM.L D2-D7/A2-A4,-(SP)               | save registers
        MOVE.L  A0,-(SP)                        | re-push return address
        MOVEQ.L #0x7F,D0                        | test memory availability (127 bytes)
        BSR     TEPASTE_CONT_3                  | check if enough memory
        BEQ.B   XTRIMMEASURE_OK_3               | OK -> continue setup
        MOVE    D1,D0                           | not enough memory -> bail with param size
        BRA     TECALTEXT_EXIT_3                | -> clean up stack and return

| ----------------------------------------------------------
|
| XTRIMMEASURE_OK_3
|
| Called during boot (2,779 times in 30s trace).
XTRIMMEASURE_OK_3:
        MOVE.L  0x8(A6),A4                      | A4 = TEHandle (param)
        MOVE.L  (A4),A3                         | A3 = dereferenced TERec
        MOVE.B  (A4),-0x2(A6)                   | save TEHandle lock byte
        PEA.L   -0x6(A6)                        | push ptr for saved port
        _GetPort                                | save current port
        MOVE.L  A4,A0                           | A0 = TEHandle
        _HLock                                  | lock TERec for duration
        MOVE.L  teInPort(A3),A2                 | A2 = TE's grafport
        MOVE.L  A2,-(SP)                        | push grafport
        _SetPort                                | switch to TE's port
        SUBQ.W  #0x4,SP                         | space for NewRgn result
        _NewRgn                                 | allocate temp clip region
        MOVE.L  (SP),-0xA(A6)                   | save temp region handle
        MOVE.L  (SP),-(SP)                      | dup for GetClip
        _GetClip                                | save current clip into temp region
        PEA.L   PORTBOUNDS(A3)                  | push viewRect for ClipRect
        _ClipRect                               | clip to TE view rectangle
        MOVE.L  0x1C(A2),-(SP)                  | push port's visRgn handle
        MOVE.L  (SP),-(SP)                      | dup for SectRgn
        _SectRgn                                | intersect visRgn with new clip
        MOVE.L  (A5),A0                         | A0 = app globals handle
        MOVE.L  (A0),A0                         | A0 = current port
        MOVE.L  TXSIZE(A3),0x44(A0)             | set port txFont/txFace from TERec
        MOVE.L  teMode(A3),0x48(A0)             | set port txMode/txSize from TERec
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.B  (A0),-0xC(A6)                   | save text handle lock byte
        _HLock                                  | lock text handle
        _GetHandleSize                          | D0 = text buffer size
        MOVE    D0,teLength(A3)                 | update teLength from actual size
| XTRIMMEASURE_CONT_14 -- clamp selection to text length.
XTRIMMEASURE_CONT_14:
        MOVE    teLength(A3),D0                 | D0 = text length
        MOVE    teSelEnd(A3),D1                 | D1 = selEnd
        SUB     D0,D1                           | D1 = selEnd - length
        BLS.B   XTRIMMEASURE_OK_4               | selEnd <= length -> OK
        MOVE    D0,teSelEnd(A3)                 | clamp selEnd to text length
XTRIMMEASURE_OK_4:
        MOVE    BKPAT(A3),D1                    | D1 = selStart
        SUB     teSelEnd(A3),D1                 | D1 = selStart - selEnd
        BLS.B   XTRIMMEASURE_OK_5               | selStart <= selEnd -> OK
        SUB     D1,BKPAT(A3)                    | clamp selStart to selEnd
XTRIMMEASURE_OK_5:
        BSR.B   XTRIMMEASURE_CONT_15            | normalize: ensure selStart <= selEnd
        LEA.L   0xC(A6),A2                      | A2 -> first param on stack
        RTS                                     | return from selection range normalization

| ----------------------------------------------------------
|
| XTRIMMEASURE_CONT_15
|
| Called during boot (2,779 times in 30s trace).
XTRIMMEASURE_CONT_15:
        LEA.L   BKPAT(A3),A2                    | A2 -> teSelStart (offset 0x20)
        MOVE.L  (A2),D0                         | D0 = selStart.W | selEnd.W
        CMP     (A2),D0                         | compare selEnd (D0.W) with selStart
        BCC.B   XTRIMMEASURE_OK_6               | selEnd >= selStart -> OK
        SWAP    D0                              | swap selStart and selEnd
        MOVE.L  D0,(A2)                         | store normalized pair
XTRIMMEASURE_OK_6:
        RTS                                     | return from swap of selStart/selEnd

| ----------------------------------------------------------
|
| _TECopy ($A9D5)
|
| _TECopy ($A9D5): copy selection to TE scrap
TECopy:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state
        BSR.B   XTRIMMEASURE_CONT_15            | D0 = selEnd
        SUB     (A2),D0                         | D0 = selection length (selEnd - selStart)
        MOVE    D0,(TEScrpLength).w             | save scrap length
| copy selected text to scrap handle
        MOVE.L  teTextH(A3),A0                  | A0 = text handle
        MOVE.L  (A0),A0                         | dereference
        MOVEQ.L #0x0,D0                         | clear for word extend
        MOVE    (A2),D0                         | D0 = selStart offset
        ADDA.L  D0,A0                           | A0 = ptr to selected text
        MOVE.L  (TEScrpHandle).w,A1             | A1 = scrap handle
        MOVE    (TEScrpLength).w,D0             | D0 = bytes to copy
        _PtrToXHand                             | copy selection to scrap
TECOPY_EXIT:
        BRA     TECALTEXT_EXIT                  | -> TE exit

| ----------------------------------------------------------
|
| _TECut ($A9D6): cut selection (copy + delete)
|
TECut:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TECopy                                 | copy selection to scrap
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEDelete                               | delete the selection
        BRA.B   TECOPY_EXIT                     | -> TE exit

| ----------------------------------------------------------
|
| _TEDelete ($A9D7)
|
| _TEDelete ($A9D7): delete the current selection
TEDelete:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state
        BSR     P_TERECAL_CONT_3                | hide caret if visible
        BSR.B   TEDELETE_CONT                   | remove selected text from buffer
        BSR.B   TEDELETE_CONT_2                 | recalculate line starts
        BSR     P_TERECAL_NO_3                  | redraw affected lines
        BSR     FILLCARC_CONT                   | auto-scroll selection into view
        BRA.B   TECOPY_EXIT                     | -> TE exit

| TEDELETE_CONT -- remove selected text from buffer.
| ----------------------------------------------------------
|
| TEDELETE_CONT
|
TEDELETE_CONT:
        BSR.B   XTRIMMEASURE_CONT_15            | D0 = selEnd; normalize selection
        MOVE    D0,D7                           | D7 = selEnd
        SUB     (A2),D7                         | D7 = selection length
        BEQ.B   TEDELETE_EMPTY                  | empty selection -> nothing to delete
        BSR     TEPASTE_CONT_2                  | set up Munger params (unlock text, push handle+offset)
        MOVE    D7,-(SP)                        | push length to delete
        CLR     -(SP)                           | replace ptr1 = nil
        CLR.L   -(SP)                           | replace ptr2 = nil
        CLR.L   -(SP)                           | replace length = 0
        _Munger                                 | delete selected text from buffer
        ADDQ.L  #0x4,SP                         | discard Munger result
        SUB     D7,teLength(A3)                 | adjust teLength
        MOVE    (A2)+,(A2)                      | teSelEnd = teSelStart (collapse sel)
TEDELETE_EMPTY:
        RTS                                     | return from Munger text deletion

| TEDELETE_CONT_2 -- recalculate lines and redraw.
| ----------------------------------------------------------
|
| TEDELETE_CONT_2
|
TEDELETE_CONT_2:
        MOVE    teNLines(A3),-(SP)              | save old line count
        BSR     P_doTERecal                     | recalculate line breaks
        MOVE    D2,D3                           | D3 = first changed line start offset
        MOVE    (SP)+,D0                        | D0 = old line count
        MULU    VISRGN(A3),D0                   | D0 = old bottom y (old nLines * lineHeight)
        ADD     (A3),D0                         | add destRect.top
        LEA.L   VISRGN(A3),A0                   | A0 -> teSelRect area (reused as erase rect)
        MOVE    #0x7FF0,-(A0)                   | rect.right = large value
        MOVE    D0,-(A0)                        | rect.bottom = old bottom y
        MOVE    teNLines(A3),D0                 | D0 = new line count
        MULU    VISRGN(A3),D0                   | D0 = new bottom y
        ADD     (A3),D0                         | add destRect.top
        MOVE    #-0x7FFE,-(A0)                  | rect.left = large negative value
        MOVE    D0,-(A0)                        | rect.top = new bottom y
        MOVE.L  A0,-(SP)                        | push erase rect (gap between old/new bottoms)
        _EraseRect                              | erase area below text if lines removed
        MOVEQ.L #-0x1,D7                        | D7=-1: draw text mode
        BRA     P_doTEDoText                    | redraw from first changed line

| ----------------------------------------------------------
|
| TEDELETE_CONT_3
|
| Called during boot.
TEDELETE_CONT_3:
        MOVE.L  (0x7F8).w,-(SP)                 | dispatch vector: _TEFindWord
        RTS                                     | return from _TEFindWord dispatch

| ----------------------------------------------------------
|
| TE Find Word
|
| Called during boot.
TEFindWord:
        SWAP    D2                              | save D2 high word (caller context)
        MOVE    D0,D2                           | D2.W = initial char offset
        MOVE    D0,D1                           | D1 = forward scan position
        BEQ.B   TEFINDWORD_SKIP                 | at start of text -> skip backward scan
        BSR.B   TEFINDWORD_CONT_2               | scan backward to word start -> D0
TEFINDWORD_SKIP:
        BClr    #0x11,D2                        | clear backward-scan flag
TEFINDWORD_CONT:
        CMP     teLength(A3),D1                 | past end of text?
        BCC.B   TEFINDWORD_DONE                 | yes -> done
        MOVE    D1,A1                           | A1 = char offset for word break test
        BSR.B   TEFINDWORD_CONT_4               | call word break proc for char at D1
        BNE.B   TEFINDWORD_DONE                 | is word break -> found end
        ADDQ.W  #0x1,D1                         | advance to next character
        BRA.B   TEFINDWORD_CONT                 | -> keep scanning forward

| ----------------------------------------------------------
|
| TEFINDWORD_DONE
|
| Called during boot.
TEFINDWORD_DONE:
        RTS                                     | D0=word start, D1=word end

| ----------------------------------------------------------
|
| TEFINDWORD_CONT_2
|
| Called during boot.
TEFINDWORD_CONT_2:
        BSET    #0x11,D2                        | set backward-scan flag
TEFINDWORD_CONT_3:
        SUBQ.W  #0x1,D0                         | move back one character
        MOVE    D0,A1                           | A1 = char offset for word break test
        BSR.B   TEFINDWORD_CONT_4               | call word break proc
        BNE.B   TEFINDWORD_FOUND                | is word break -> found start
        TST     D0                              | at beginning of text?
        BEQ.B   TEFINDWORD_DONE_2               | yes -> done (D0=0)
        BRA.B   TEFINDWORD_CONT_3               | -> keep scanning backward

| ----------------------------------------------------------
|
| TEFINDWORD_FOUND
|
| Called during boot.
TEFINDWORD_FOUND:
        ADDQ.W  #0x1,D0                         | step past break char to word start
TEFINDWORD_DONE_2:
        RTS                                     | return from word start character step

| ----------------------------------------------------------
|
| TEFINDWORD_CONT_4
|
| Called during boot.
TEFINDWORD_CONT_4:
        MOVEM.L D0/A0-A1,-(SP)                  | save registers
        MOVE    A1,D0                           | D0 = char offset to test

| === TextEdit routines continued (from ROM layout after packages) ===
| Package Manager and Standard Packages
|
| The Package Manager loads and calls code packages from resources.
| Packages in ROM include:
| PACK 4: FP68K (Floating-Point Arithmetic)
| PACK 5: Elems68K (Transcendental Functions)
| PACK 7: DecStr68K (Binary-Decimal Conversion)
|
| References:
| Inside Macintosh Vol I, Ch 17: The Package Manager
| Inside Macintosh Vol II, Ch 15: FP Arithmetic and Transcendental Packages

| Package Manager & packages
| ROM section: src/toolbox/packages.asm
        MOVE.L  0x3E(A3),A0                     | A0 = teTextH (text handle)
        MOVE.L  (A0),A0                         | A0 = dereferenced text ptr
        MOVE.L  0x26(A3),A1                     | A1 = teWordBreak proc ptr
        JSR     (A1)                            | call word break: Z=not break, NZ=break
        MOVEM.L (SP)+,D0/A0-A1                  | restore registers (CC preserved)
        RTS                                     | return result of word break callback

| ----------------------------------------------------------
|
| P_TE Wd Break
|
| Called during boot.
P_TEWdBreak:
        ANDI.L  #0xFFFF,D0                      | mask to 16-bit char offset
        CMPI.B  #0x20,0x0(A0,D0.L)              | char <= space (0x20)?
        SLS.B   D0                              | D0 = $FF if whitespace/control
        TST.B   D0                              | set Z flag: NZ=break, Z=not break
        RTS                                     | return Z flag indicating break or not

| ----------------------------------------------------------
|
| P_TEWDBREAK_CONT
|
| Called during boot.
P_TEWDBREAK_CONT:
        MOVEM.L D6-D7,-(SP)                     | save D6/D7 (line range)
        BSR     P_XTrimMeasure                  | measure trimmed line width -> D0
        MOVEM.L (SP)+,D6-D7                     | restore line range
        RTS                                     | return from trimmed line width measurement

| ----------------------------------------------------------
|
| P_TEWDBREAK_NEXT
|
| Called during boot.
P_TEWDBREAK_NEXT:
        MOVE.L  (0x7FC).w,-(SP)                 | dispatch vector: _TEFindLine
        RTS                                     | return from _TEFindLine dispatch

| ----------------------------------------------------------
|
| TE Find Line
|
| Called during boot.
TEFindLine:
        MOVEM.L D1-D7/A1-A2,-(SP)               | save registers
        MOVE    0x6(A3),D4                      | D4 = destRect.right
        SUB     PORTBITS(A3),D4                 | D4 = dest width (right - left)
        SUBQ.W  #0x1,D4                         | subtract 1 pixel margin
        SUBA.L  A2,A2                           | A2 = 0 (word-wrap counter)
        MOVE    D6,D7                           | D7 = current scan position
TEFINDLINE_CONT:
        MOVE    D7,D0                           | D0 = scan position for word search
        MOVEQ.L #0xC,D2                         | D2=12: find next word boundary
        BSR     TEDELETE_CONT_3                 | find word end -> D1
        MOVE    D1,D7                           | D7 = word end position
        TST.B   TXMODE(A3)                      | teCROnly set?
        BNE.B   TEFINDLINE_SKIP                 | yes -> no word wrap, skip width check
        BSR.B   P_TEWDBREAK_CONT                | measure text width to D7 -> D0
        CMP     D4,D0                           | wider than dest rect?
        BGE.B   TEFINDLINE_OK                   | yes -> line must break here
TEFINDLINE_SKIP:
        MOVE    D7,D5                           | D5 = last good break position
        ADDQ.W  #0x1,A2                         | increment word count on line
        CMP     0x3C(A3),D7                     | at end of text?
        BEQ.B   TEFINDLINE_EXIT                 | yes -> finalize line
        MOVE.L  0x3E(A3),A0                     | A0 = teTextH
        MOVE.L  (A0),A0                         | dereference text
  .short 0xCEBA,0xFFA2                          | And.L (PCrel $168A4 ), D7
        CMPI.B  #0xD,0x0(A0,D7.L)               | character at D7 is CR?
        BEQ.B   TEFINDLINE_OK                   | yes -> hard line break
        ADDQ.W  #0x1,D7                         | skip past break char
        BRA.B   TEFINDLINE_CONT                 | -> continue scanning

| ----------------------------------------------------------
|
| TEFINDLINE_OK
|
| Called during boot.
TEFINDLINE_OK:
        MOVE    A2,D0                           | D0 = word count on this line
        BEQ.B   TEFINDLINE_EMPTY                | zero words -> force char-level break
        ADDQ.W  #0x1,D5                         | include break char in line
TEFINDLINE_EXIT:
        MOVE    D5,D0                           | D0 = line end offset (return value)
        MOVEM.L (SP)+,D1-D7/A1-A2               | restore registers
        RTS                                     | return computed line end offset in D0

| ----------------------------------------------------------
|
| TEFINDLINE_EMPTY
|
TEFINDLINE_EMPTY:
        SUBQ.W  #0x1,D7                         | try one char shorter
        BSR.B   P_TEWDBREAK_CONT                | measure width -> D0
        CMP     D0,D4                           | still too wide?
        BLE.B   TEFINDLINE_EMPTY                | yes -> keep removing chars
        MOVE    D7,D5                           | D5 = char-level break point
        BRA.B   TEFINDLINE_EXIT                 | -> return line end offset

| ----------------------------------------------------------
|
| P_do TE Recal
|
| Called during boot.
P_doTERecal:
        MOVE.L  (TERecal).w,-(SP)               | push TERecal vector and jump
        RTS                                     | (RTS used as indirect JMP)

| ----------------------------------------------------------
|
| P_TE Recal
|
| Called during boot.
P_TERecal:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D2-D6/A2,-(SP)                  | save registers
        MOVE.L  A4,A0                           | A0 = TEHandle
        _GetHandleSize                          | D0 = TERec handle size
        MOVE.L  D0,D5                           | D5 = current handle size
        LEA.L   0x5E(A3),A2                     | A2 -> teNLines
        CLR     (A2)+                           | reset nLines = 0; A2 -> lineStarts[0]
        MOVE    0x3C(A3),-0xE(A6)               | save teLength in local
        MOVEQ.L #0x10,D2                        | D2 = reserved (recal state)
        MOVE    BKPAT(A3),D0                    | D0 = teSelStart (change point)
        BSR     TEDELETE_CONT_3                 | find word boundary at change point
        MOVE    D0,D3                           | D3 = word-aligned change point
P_TERECAL_NEXT:
        MOVE    (A2)+,D6                        | D6 = current lineStart; advance A2
        MOVE    D6,-0x16(A6)                    | save as first changed line start
        CMP     (A2),D3                         | change point before next line start?
        BCS.B   P_TERECAL_OK                    | yes -> start recalculating here
        BEQ.B   P_TERECAL_CONT_2                | exactly at line boundary
        ADDQ.W  #0x1,0x5E(A3)                   | skip this line (still valid)
        BRA.B   P_TERECAL_NEXT                  | -> check next line

| ----------------------------------------------------------
|
| P_TERECAL_OK
|
P_TERECAL_OK:
        BSR     P_TEWDBREAK_NEXT                | find line break starting at D6 -> D0
        CMP     D0,D3                           | change point past line break?
        BCC.B   P_TERECAL_DONE                  | yes -> done searching
P_TERECAL_CONT:
        TST.B   (WordRedraw).w                  | word redraw mode flag
        BGT.B   P_TERECAL_DONE                  | positive -> use D3 as start
        BLT.B   P_TERECAL_SKIP                  | negative -> skip to line calc
        MOVE    BKPAT(A3),D3                    | zero -> redraw from selStart
P_TERECAL_DONE:
        TST     PNPAT(A3)                       | teJust != 0 (center/right)?
        BNE.B   P_TERECAL_SKIP                  | yes -> no optimization possible
        MOVE    D3,-0x16(A6)                    | update first redraw line start
        BEQ.B   P_TERECAL_SKIP                  | at start of text -> skip
        SUBQ.W  #0x1,-0x16(A6)                  | back up one char for overlap
        BRA.B   P_TERECAL_SKIP                  | -> begin line recalculation

| ----------------------------------------------------------
|
| P_TERECAL_CONT_2
|
| Called during boot.
P_TERECAL_CONT_2:
        BSR     P_TEWDBREAK_NEXT                | find line break at boundary -> D0
        CMP     D0,D3                           | line break matches change point?
        BNE.B   P_TERECAL_DONE                  | no -> different line structure
        MOVE    D3,-0x16(A6)                    | same -> update redraw start
        BRA.B   P_TERECAL_CONT                  | -> check redraw mode

| ----------------------------------------------------------
|
| P_TERECAL_NEXT_2
|
| Called during boot.
P_TERECAL_NEXT_2:
        CMP     0x3C(A3),D6                     | past end of text?
        BCC.B   P_TERECAL_DONE_2                | yes -> done recalculating
        BSR     P_TEWDBREAK_NEXT                | find next line break -> D0
P_TERECAL_SKIP:
        MOVE    D0,D3                           | D3 = new line start
        CMP     0x22(A3),D3                     | past teSelEnd?
        BLS.B   P_TERECAL_NO                    | no -> keep inserting new lines
        SUB     D3,(A2)                         | compute delta from old lineStart
        CMP     (A2),D7                         | delta matches insertion offset?
        BEQ.B   P_TERECAL_OK_2                  | yes -> remaining lines just need adjustment
P_TERECAL_NO:
        BSR.B   P_TERECAL_NEXT_3                | grow TERec handle if needed; bump nLines
        MOVE    D3,(A2)+                        | store new lineStart; advance
        MOVE    D3,D6                           | D6 = start of next line
        BRA.B   P_TERECAL_NEXT_2                | -> find next line break

| ----------------------------------------------------------
|
| P_TERECAL_OK_2
|
P_TERECAL_OK_2:
        MOVE    D3,-0xE(A6)                     | save new length checkpoint
        ADD     D3,(A2)                         | adjust remaining lineStart by delta
P_TERECAL_NO_2:
        BSR.B   P_TERECAL_NEXT_3                | grow handle if needed; bump nLines
        SUB     D7,(A2)                         | adjust old lineStart by removed chars
        MOVE    (A2)+,D6                        | D6 = adjusted lineStart; advance
        CMP     0x3C(A3),D6                     | past end of text?
        BCS.B   P_TERECAL_NO_2                  | no -> keep adjusting remaining lines
P_TERECAL_DONE_2:
        BSR.B   P_TERECAL_NEXT_3                | ensure space for sentinel entry
        MOVE    D6,-(A2)                        | store final lineStart (sentinel)
        SUBQ.W  #0x1,0x5E(A3)                   | adjust nLines (subtract extra count)
        TST     0x3C(A3)                        | is text empty?
        BNE.B   P_TERECAL_DONE_3                | no -> done
        CLR     0x5E(A3)                        | empty text -> nLines = 0
P_TERECAL_DONE_3:
        MOVEM.L (SP)+,D2-D6/A2                  | restore registers
        UNLK    A6                              | tear down frame
        RTS                                     | return from sentinel entry insertion

| ----------------------------------------------------------
|
| P_TERECAL_NEXT_3
|
| Called during boot.
P_TERECAL_NEXT_3:
        ADDQ.W  #0x1,0x5E(A3)                   | teNLines++
        MOVE.L  A4,A0                           | A0 = TEHandle
        MOVEQ.L #0x68,D0                        | D0 = base TERec size (104)
        ADD     0x5E(A3),D0                     | add nLines
        ADD     0x5E(A3),D0                     | add nLines again (2 bytes per entry)
        CMP.L   D0,D5                           | handle big enough?
        BGE.B   P_TERECAL_DONE_4                | yes -> done
        SUBA.L  A3,A2                           | convert A2 to relative offset
        ADDQ.L  #0x8,D0                         | grow by 8 extra bytes (headroom)
        MOVE.L  D0,D5                           | D5 = new handle size
        BCLR    #0x7,(A4)                       | unlock TEHandle before resize
        _SetHandleSize                          | grow handle to new size
        _HLock                                  | re-lock TEHandle
        MOVE.L  (A4),A3                         | re-dereference (may have moved)
        ADDA.L  A3,A2                           | convert A2 back to absolute ptr
P_TERECAL_DONE_4:
        RTS                                     | return from handle resize operation

| P_TERECAL_NO_3 -- set caret state.
| ----------------------------------------------------------
|
| P_TERECAL_NO_3
|
| Called by: TESetSelect, TECLICK_NO_2, TECLICK_CONT_4, TEDelete, TEPASTE_CONT (and 3 more)
P_TERECAL_NO_3:
        TST.B   0x24(A3)                        | teActive?
        BEQ.B   P_TERECAL_DONE_4                | no -> done
        MOVE    BKPAT(A3),D0                    | D0 = teSelStart
        CMP     0x22(A3),D0                     | selStart == selEnd? (insertion point)
        BNE.B   P_TERECAL_DONE_4                | no -> has selection, no caret
        ST.B    0x39(A3)                        | teCarAct = true (caret active)
        TST.B   PNMODE(A3)                      | teCarOn already on?
        BNE.B   P_TERECAL_DONE_4                | yes -> done
        ST.B    PNMODE(A3)                      | teCarOn = true
P_TERECAL_OK_3:
        BRA.B   P_TERECAL_CONT_4                | -> draw caret

| ----------------------------------------------------------
|
| P_TERECAL_CONT_3
|
| Called during boot.
P_TERECAL_CONT_3:
        TST.B   0x24(A3)                        | teActive?
        BEQ.B   P_TERECAL_DONE_4                | no -> done
        SF.B    0x39(A3)                        | teCarAct = false (deactivate caret)
        TST.B   PNMODE(A3)                      | teCarOn? (caret currently visible)
        BEQ.B   P_TERECAL_DONE_4                | no -> nothing to erase
        SF.B    PNMODE(A3)                      | teCarOn = false
| P_TERECAL_CONT_4 -- draw/erase caret (XOR).
P_TERECAL_CONT_4:
        MOVEM.L D0-D7,-(SP)                     | save all data registers
        MOVE    BKPAT(A3),D3                    | D3 = teSelStart (caret position)
        MOVE    D3,D4                           | D4 = same (zero-width range)
        MOVEQ.L #-0x2,D7                        | D7=-2: caret drawing mode
        BSR     P_doTEDoText                    | compute caret rect
        MOVE.L  PATSTRETCH(A3),D0               | D0 = teCarHook (caret draw hook)
        BSR     XTRIMMEASURE_CONT_7             | XOR the caret (invert rect)
        MOVEM.L (SP)+,D0-D7                     | restore registers
        RTS                                     | return from caret drawing routine

| ----------------------------------------------------------
|
| _TEActivate ($A9D8)
|
| Called during boot.
TEActivate:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state
        TST.B   0x24(A3)                        | already active?
        BNE.B   TEACTIVATE_OK                   | yes -> nothing to do
        MOVE    BKPAT(A3),D0                    | D0 = teSelStart
        CMP     0x22(A3),D0                     | insertion point? (selStart == selEnd)
        BNE.B   TEACTIVATE_NO                   | no -> has selection
        ST.B    0x39(A3)                        | teCarAct = true (enable caret)
TEACTIVATE_NO:
        ST.B    0x24(A3)                        | teActive = true
        BSR     TEUPDATE_CONT_2                 | draw selection/caret
TEACTIVATE_OK:
        BRA.B   TEIDLE_EXIT                     | -> TE exit

| ----------------------------------------------------------
|
| _TEDeactivate ($A9D9)
|
| Called during boot.
TEDeactivate:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state
        TST.B   0x24(A3)                        | already inactive?
        BEQ.B   TEIDLE_EXIT                     | yes -> nothing to do
        BSR.B   P_TERECAL_CONT_3                | hide caret
        BSR     TEUPDATE_CONT_2                 | unhighlight selection
        SF.B    0x24(A3)                        | teActive = false
        BRA.B   TEIDLE_EXIT                     | -> TE exit

| ----------------------------------------------------------
|
| _TEIdle ($A9DA)
|
| _TEIdle ($A9DA): blink the text cursor (caret)
| Called repeatedly from event loop; toggles caret at CaretTime rate
TEIdle:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state (A3=TERec)
        TST.B   0x39(A3)                        | TE active? (teActive)
        BEQ.B   TEIDLE_EXIT                     | no ->
        SUBQ.W  #0x4,SP                         | room for tick count result
        _TickCount                              | get current tick count
        MOVE.L  (SP)+,A0                        | A0 = current ticks
        CMPA.L  PNSIZE(A3),A0                   | time for next blink? (teCaretTime)
        BCS.B   TEIDLE_EXIT                     | not yet ->
        ADDA.L  (CaretTime).w,A0                | schedule next blink
        MOVE.L  A0,PNSIZE(A3)                   | save next blink time
        BSR.B   P_TERECAL_CONT_4                | draw/erase caret (XOR)
        NOT.B   PNMODE(A3)                      | toggle caret state
TEIDLE_EXIT:
        BRA     TECALTEXT_EXIT                  | -> TE exit (4 bytes params)

| ----------------------------------------------------------
|
| _TEPaste ($A9DB): paste TE scrap at selection point
|
TEPaste:
        BSR     XTRIMMEASURE_CONT_12            | set up TE state
        MOVE.L  (TEScrpHandle).w,A1             | A1 = scrap handle
        BSET    #0x7,(A1)                       | lock scrap handle
        MOVE.L  (A1),D6                         | D6 = dereferenced scrap text ptr
        MOVEQ.L #0x0,D5                         | clear high word
        MOVE    (TEScrpLength).w,D5             | D5 = scrap length
        BSR.B   TEPASTE_CONT                    | insert scrap text, replacing selection
        MOVE.L  (TEScrpHandle).w,A1             | A1 = scrap handle
        BCLR    #0x7,(A1)                       | unlock scrap handle
        BRA.B   TEIDLE_EXIT                     | -> TE exit

| TEPASTE_CONT -- insert scrap text, replacing selection.
| ----------------------------------------------------------
|
| TEPASTE_CONT
|
TEPASTE_CONT:
        MOVE    D7,D0                           | D0 = selection length (if any)
        EXT.L   D0                              | sign extend
        NEG.L   D0                              | negate (will be replaced)
        ADD.L   D5,D0                           | D0 = net growth (insert - delete)
        BSR.B   TEPASTE_CONT_3                  | check if enough memory
        BNE.B   TEPASTE_NO                      | not enough -> bail
        BSR     P_TERECAL_CONT_3                | hide caret
        BSR     TEUPDATE_CONT_2                 | unhighlight selection
        BSR     XTRIMMEASURE_CONT_15            | normalize selection; D0 = selEnd
        MOVE    D0,D7                           | D7 = selEnd
        SUB     (A2),D7                         | D7 = selection length to delete
        BSR.B   TEPASTE_CONT_2                  | unlock text, push handle+offset for Munger
        MOVE    D7,-(SP)                        | push delete length
        CLR     -(SP)                           | search ptr = nil (replace mode)
        MOVE.L  D6,-(SP)                        | push replacement text ptr
        MOVE.L  D5,-(SP)                        | push replacement length
        _Munger                                 | replace selection with new text
        ADDQ.L  #0x4,SP                         | discard Munger result
        MOVE.L  0x3E(A3),A0                     | A0 = teTextH
        _HLock                                  | re-lock text handle
        SUB     D7,0x3C(A3)                     | teLength -= deleted chars
        ADD     D5,0x3C(A3)                     | teLength += inserted chars
        SUB     D5,D7                           | D7 = net chars removed
        BSR     TEDELETE_CONT_2                 | recalculate lines and redraw
        LEA.L   BKPAT(A3),A0                    | A0 -> teSelStart
        ADD     D5,(A0)                         | selStart += inserted length
        MOVE    (A0)+,(A0)                      | selEnd = selStart (collapse)
        BSR     P_TERECAL_NO_3                  | set caret state
        BSR     FILLCARC_CONT                   | auto-scroll into view
TEPASTE_NO:
        RTS                                     | return from text insertion and redraw

| TEPASTE_CONT_2 -- set up Munger params (unlock text, push handle+offset).
| ----------------------------------------------------------
|
| TEPASTE_CONT_2
|
TEPASTE_CONT_2:
        MOVE.L  (SP)+,A1                        | pop return address
        MOVE.L  0x3E(A3),A0                     | A0 = teTextH
        _HUnlock                                | unlock text for Munger
        SUBQ.L  #0x4,SP                         | space for Munger result
        MOVE.L  A0,-(SP)                        | push text handle
        MOVE    BKPAT(A3),-(SP)                 | push offset (teSelStart)
        CLR     -(SP)                           | push search length = 0
        CLR.L   -(SP)                           | push search ptr = nil
        JMP     (A1)                            | return (caller adds replace params)

| ----------------------------------------------------------
|
| TEPASTE_CONT_3
|
| Called during boot (2,791 times in 30s trace).
TEPASTE_CONT_3:
        MOVE.L  D0,D2                           | D2 = requested size
        BMI.B   TEPASTE_OK                      | negative -> always OK
        ASR.L   #0x4,D2                         | D2 = 6.25% overhead
        ADD.L   D2,D0                           | add overhead to request
        ADDI.L  #0x80,D0                        | add 128 byte cushion
        _NewHandle                              | try to allocate test handle
        BNE.B   TEPASTE_ERR                     | failed -> return NE (not enough)
        _DisposeHandle                          | success -> free test handle
TEPASTE_OK:
        MOVEQ.L #0x0,D0                         | return Z flag (enough memory)
TEPASTE_ERR:
        RTS                                     | return Z flag if memory is sufficient

| TEPASTE_CONT_4 -- insert text at selection.
| ----------------------------------------------------------
|
| TEPASTE_CONT_4
|
TEPASTE_CONT_4:
        MOVE.L  D5,D0                           | D0 = insert length
        BSR.B   TEPASTE_CONT_3                  | check memory availability
        BNE.B   TEPASTE_NO_2                    | not enough -> bail
        BSR.B   TEPASTE_CONT_2                  | set up Munger params (unlock, push handle+offset)
        CLR.L   -(SP)                           | delete length = 0 (insert only)
        MOVE.L  D6,-(SP)                        | push replacement text ptr
        MOVE.L  D5,-(SP)                        | push replacement length
        _Munger                                 | insert text at selection point
        ADDQ.L  #0x4,SP                         | discard Munger result
        MOVE.L  0x3E(A3),A0                     | A0 = teTextH
        _HLock                                  | re-lock text handle
        ADD     D5,0x3C(A3)                     | teLength += inserted chars
        SUB     D5,D7                           | adjust delta for recalculation
TEPASTE_NO_2:
        RTS                                     | return from Munger text insertion

| TEInsert -- trap handler for _TEInsert ($A9DE).
| ----------------------------------------------------------
|
| _TEInsert ($A9DE)
|
TEInsert:
        BSR     XTRIMMEASURE_CONT_8             | set up TE state (12 bytes params)
        BSR     P_TERECAL_CONT_3                | hide caret
        BSR     TEUPDATE_CONT_2                 | unhighlight selection
        MOVEQ.L #0x0,D7                         | D7 = 0 (no chars deleted)
        MOVEM.L (A2)+,D5-D6                     | D5=text length, D6=text ptr (params)
        BSR.B   TEPASTE_CONT_4                  | insert text at selection
        BSR     TEDELETE_CONT_2                 | recalculate lines and redraw
        ADD     D5,BKPAT(A3)                    | teSelStart += inserted length
        ADD     D5,0x22(A3)                     | teSelEnd += inserted length
        BSR     P_TERECAL_NO_3                  | set caret state
        BSR     TEUPDATE_CONT_2                 | highlight selection
TEINSERT_EXIT:
        MOVEQ.L #0xC,D0                         | param size = 12 bytes
        BRA     TECALTEXT_EXIT_2                | -> TE exit

| ----------------------------------------------------------
|
| _TEKey ($A9DC)
|
| _TEKey ($A9DC): handle a keystroke in a TextEdit field
| Pascal: procedure TEKey(key: CHAR; hTE: TEHandle);
| Inserts character at selection, or handles backspace/arrows
TEKey:
        BSR     XTRIMMEASURE_CONT_11            | set up TE state (A3=TERec, A2=params)
        ST.B    0x47(A3)                        | set teJust flag (caret active)
        _ObscureCursor                          | hide cursor during typing
        MOVE    (A2),D1                         | D1 = key character
        CMPI.B  #0x8,D1                         | backspace?
        BEQ.B   TEKEY_OK                        | yes, handle delete ->
| normal character: insert at selection point
        MOVE.L  A2,D6                           | D6 = ptr to character to insert
        ADDQ.W  #0x1,D6                         | point past key word to char byte
        MOVEQ.L #0x1,D5                         | D5 = 1 character to insert
        BSR     TEPASTE_CONT                    | TEInsert: replace selection with char
        BRA.B   TEKEY_DONE                      | -> done
| backspace: delete character before selection
TEKEY_OK:
        MOVE    BKPAT(A3),D0                    | D0 = selStart
        CMP     0x22(A3),D0                     | selStart == selEnd? (no selection)
        BNE.B   TEKEY_CONT                      | has selection, delete it ->
        TST     D0                              | at beginning of text?
        BEQ.B   TEKEY_DONE                      | yes -> nothing to delete
        BSR     P_TERECAL_CONT_3                | hide caret
        SUBQ.W  #0x1,BKPAT(A3)                  | selStart-- (select char before cursor)
TEKEY_CONT:
        MOVE.L  A4,-(SP)                        | push TEHandle
        _TEDelete                               | delete the selected text
TEKEY_DONE:
        MOVEQ.L #0x6,D0                         | param size = 6 bytes
        BRA     TECALTEXT_EXIT_2                | -> TE exit

| ----------------------------------------------------------
|
| _TESetAlignment ($A9DF)
|
TESetAlignment:
        BSR     XTRIMMEASURE_CONT_11            | set up TE state (6 bytes params)
        MOVE    (A2),PNPAT(A3)                  | teJust = alignment param
        BRA.B   TEKEY_DONE                      | -> TE exit

| ----------------------------------------------------------
|
| TESETALIGNMENT_CONT
|
| Called during boot.
TESETALIGNMENT_CONT:
        MOVEQ.L #0x0,D3                         | D3 = 0 (draw from start of text)
        MOVEQ.L #-0x1,D4                        | D4 = -1 (draw all text)
        BSR     XTRIMMEASURE_CONT_4             | clip to visible lines in update rect
        MOVEQ.L #-0x1,D7                        | D7=-1: draw text mode
        BSR     P_doTEDoText                    | draw all visible text lines
        BSR     TEUPDATE_CONT_2                 | redraw selection highlighting
        TST.B   PNMODE(A3)                      | caret visible?
        BEQ.B   TESCROLL_DONE                   | no -> done
        BRA     P_TERECAL_OK_3                  | yes -> redraw caret

| TEScroll -- _TEScroll ($A9DD): PROCEDURE TEScroll {dh,dv: INTEGER; hTE : TEHandle);
| ----------------------------------------------------------
|
| _TEScroll ($A9DD)
|
TEScroll:
        BSR     XTRIMMEASURE_CONT_10            | set up TE state (8 bytes params)
        BSR     P_TERECAL_CONT_3                | hide caret before scrolling
        MOVE.L  (A2)+,D3                        | D3 = scroll amount (dh.W, dv.W)
        BSR.B   TESCROLL_CONT                   | perform scroll
TESCROLL_EXIT:
        MOVEQ.L #0x8,D0                         | param size = 8 bytes
        BRA     TECALTEXT_EXIT_2                | -> TE exit

| TESCROLL_CONT -- apply scroll to text.
| ----------------------------------------------------------
|
| TESCROLL_CONT
|
TESCROLL_CONT:
        TST.L   D3                              | any scroll amount?
        BEQ.B   TESCROLL_DONE                   | zero -> nothing to do
        PEA.L   (A3)                            | push destRect ptr
        MOVE.L  D3,-(SP)                        | push scroll delta (dh, dv)
        _OffsetRect                             | shift destRect by scroll amount
        SUBQ.W  #0x4,SP                         | space for NewRgn result
        _NewRgn                                 | allocate update region
        MOVE.L  (SP)+,A2                        | A2 = update region handle
        PEA.L   PORTBOUNDS(A3)                  | push viewRect for scrolling
        MOVE.L  D3,-(SP)                        | push scroll delta
        MOVE.L  A2,-(SP)                        | push update region
        _ScrollRect                             | scroll pixels, get uncovered region
        BSR     P_TERECAL_NO_3                  | set caret state
        MOVE.L  A2,-(SP)                        | push update region
        _SetClip                                | clip to uncovered area only
        MOVE.L  (A2),A0                         | dereference update region
        LEA.L   0x2(A0),A0                      | A0 -> region's bounding rect
        BSR.B   TESETALIGNMENT_CONT             | redraw text in uncovered area
        MOVE.L  A2,-(SP)                        | push update region
        _DisposeRgn                             | free update region
TESCROLL_DONE:
        RTS                                     | return from update region redraw
