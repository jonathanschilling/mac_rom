| Desk Manager -- desk accessories
|
| Apple source: DeskMgr.a (MacSEROM.lst module DESKMGR): SystemEvent
| ($A9B2), SystemClick ($A9B3), SystemTask ($A9B4), SystemMenu ($A9B5),
| SysEdit ($A9C2), OpenDeskAcc ($A9B6), CloseDeskAcc ($A9B7). Desk
| accessories are drivers ('DRVR' resources) with a window; the Desk
| Manager routes events, menu choices and editing commands to them
| (through _Control with accEvent, accMenu, accRun, accCut ... csCodes)
| and opens and closes them.
|
| References: Inside Macintosh Vol I, Ch 14 (The Desk Manager).

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
        LEA.L   -0x8(A6),A0                     | A0 -> ioCRefNum (param block +$18)
        MOVE    0x18(A1),(A0)+                  | ioCRefNum := dCtlRefNum (DCE +$18)
        MOVE    D0,(A0)+                        | csCode (+$1A) := D0 (accEvent/accRun/...)
        MOVE.L  A3,(A0)                         | csParam (+$1C) := A3 (event record ptr)
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
        MOVE.L  evtMessage(A3),A0               | A0 = window ptr from event record
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
        MOVE    0x4(A3),0x16(A0)                | ioDrvNum (+$16) := drive number (evtMessage+2)
        _MountVol                               | mount the volume
        ADDA    #0x18,SP                        | discard param block
        MOVE    D0,evtMessage(A3)               | store result code
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

