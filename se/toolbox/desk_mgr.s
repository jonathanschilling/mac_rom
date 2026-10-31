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
| _SystemEvent ($A9B2) - handle system events (desk accessories)
| FUNCTION SystemEvent(theEvent: EventRecord): BOOLEAN
|
| Determines if a system event (mouse/key/etc.) should be handled
| by a desk accessory rather than the application. Dispatches by
| event code through jump table SYSEVT_DISPATCH.
| Returns TRUE (1) in result word if the system handled the event.
| ----------------------------------------------------------
DESKMGR:                                        | Apple source module (MacSEROM.lst)
SYSTEMEVENT:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0x8(A7),A3                      | A3 -> EventRecord parameter
    CLR.W       0xC(A7)                         | clear result (assume FALSE)
    SUBQ.W      #0x4,A7                         | allocate space for saved port
    MOVE.L      A7,-(A7)                        | push ptr to saved port variable
    _GetPort                                    | save current grafport
    MOVE.W      (A3),D0                         | D0 = event code (what field)
    CMPI.W      #0xC,D0                         | event code >= 12?
    BCC.B       SYSEVT_RESTORE                  | out of range: ignore event
    ADD.W       D0,D0                           | word offset into dispatch table
    LEA.L       SYSEVT_DISPATCH(PC),A0          | A0 -> event dispatch table
    ADDA.W      0x0(A0,D0.W),A0                 | add relative offset for this event
    JMP         (A0)                            | dispatch to event handler
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
    .long       0x001C001C
    .long       0x00240024
    .long       0x00240024
    .long       0x00780084
    .long       0x0078001C
    .long       0x00240024
| SYSEVT_HANDLED - called from 3 places

SYSEVT_HANDLED:
    ADDQ.B      #0x1,0x10(A7)                   | set result to TRUE (system handled)
| Called by: TEXTEDIT_CONT, SYSTEMEVENT, TEXTEDIT_CONT_6, TEXTEDIT_CONT_7
SYSEVT_RESTORE:
    _SetPort                                    | restore saved grafport
    MOVEA.L     (A7)+,A3                        | restore A3
    MOVE.L      (A7)+,(A7)                      | collapse stack frame
    RTS                                         | return from desk accessory event handler
| ----------------------------------------------------------
| TEXTEDIT_CONT - mouseUp / keyDown / keyUp / autoKey path:
| dispatch event to front window if it is a desk accessory
| and the DA's event mask covers this event code.
| ----------------------------------------------------------
TEXTEDIT_CONT:
    SUBQ.W      #0x4,A7                         | space for FrontWindow result
    _FrontWindow                                | get frontmost window
    MOVEA.L     (A7)+,A0                        | A0 = front window ptr
    BSR.B       TEXTEDIT_CONT_2                 | look up desk accessory DCE -> A1
    BNE.B       SYSEVT_RESTORE                  | not a DA window, bail
    MOVE.W      (A3),D0                         | D0 = event code (from caller)
    MOVE.W      0x24(A1),D1                     | D1 = DCE event mask
    BTST        D0,D1                           | DA interested in this event?
    BEQ.B       SYSEVT_RESTORE                  | no, bail
    BSR.B       TEXTEDIT_CONT_3                 | send accEvent control call to DA
    BRA.B       SYSEVT_HANDLED                  | -> return
| ----------------------------------------------------------
|
| TEXTEDIT_CONT_2
|
| Called during boot (3,697 times in 30s trace).
TEXTEDIT_CONT_2:
    MOVE.W      0x6C(A0),D0                     | D0 = windowKind from WindowRecord
    BPL.B       TEXTEDIT_ERR                    | positive = not a DA, return error
    NOT.W       D0                              | convert DA refNum to unit number
    ASL.W       #0x2,D0                         | multiply by 4 for table index
    MOVEA.L     (UTableBase).W,A0               | A0 = unit table base
    MOVEA.L     0x0(A0,D0.W),A0                 | A0 = handle to DCE
    MOVEA.L     (A0),A1                         | A1 = dereferenced DCE pointer
    MOVEQ.L     #0x0,D0                         | return 0 = success (Z flag set)
    RTS                                         | return success code (0)
| ----------------------------------------------------------
|
| TEXTEDIT_ERR
|
| Called during boot (3,697 times in 30s trace).
TEXTEDIT_ERR:
    MOVEQ.L     #-0x1,D0                        | return -1 = not a DA (NE flag set)
    RTS                                         | return failure code (-1)
| TEXTEDIT_CONT_3 -- send accEvent control call to DA.
| ----------------------------------------------------------
|
| TEXTEDIT_CONT_3
|
TEXTEDIT_CONT_3:
    MOVEQ.L     #0x40,D0                        | csCode = accEvent (64)
| TEXTEDIT_CONT_4 -- send accCursor to front DA.
TEXTEDIT_CONT_4:
    LINK        A6,#-0x20                       | allocate param block on stack
    LEA.L       -0x8(A6),A0                     | A0 -> ioCRefNum (param block +$18)
    MOVE.W      0x18(A1),(A0)+                  | ioCRefNum := dCtlRefNum (DCE +$18)
    MOVE.W      D0,(A0)+                        | csCode (+$1A) := D0 (accEvent/accRun/...)
    MOVE.L      A3,(A0)                         | csParam (+$1C) := A3 (event record ptr)
    LEA.L       -0x20(A6),A0                    | A0 = param block base
    _ControlImmed                               | issue synchronous Control call to DA
    UNLK        A6                              | tear down frame
    RTS                                         | return from synchronous Control call
| TEXTEDIT_CONT_5 -- send accRun to this DA.
| ----------------------------------------------------------
|
| TEXTEDIT_CONT_5
|
TEXTEDIT_CONT_5:
    MOVEQ.L     #0x41,D0                        | csCode = accRun (65)
    BRA.B       TEXTEDIT_CONT_4                 | -> send Control call to DA
| ----------------------------------------------------------
| TEXTEDIT_CONT_6 - update / activate path: dispatch event to DA
| if the event's window pointer is a desk accessory window.
| ----------------------------------------------------------
TEXTEDIT_CONT_6:
    MOVEA.L     0x2(A3),A0                      | A0 = window ptr from event record
    BSR.B       TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
    BNE.B       SYSEVT_RESTORE                  | not a DA, bail
    BSR.B       TEXTEDIT_CONT_3                 | send accEvent control call
    BRA.B       SYSEVT_HANDLED                  | -> return
| ----------------------------------------------------------
| DISKINSERT_ENTRY - disk-inserted path. If high word non-zero
| call disk-inserted vector at $7DC; else mount the volume
| via _MountVol.
| ----------------------------------------------------------
DISKINSERT_ENTRY:
    TST.W       0x2(A3)                         | high word of message non-zero?
    BEQ.B       TEXTEDIT_CONT_7                 | zero: just mount the volume
    MOVEA.L     (0x7DC).W,A0                    | A0 = disk-insert hook (jSwapMMUMode-1)
    MOVE.W      0x4(A3),D1                      | D1 = drive number
    MOVEQ.L     #0x1,D2                         | D2 = 1 (mount-flag)
    JSR         (A0)                            | jump to disk-insert handler
    BRA.B       SYSEVT_HANDLED                  | -> return
| ----------------------------------------------------------
|
| TEXTEDIT_CONT_7
|
TEXTEDIT_CONT_7:
    SUBA.W      #0x18,A7                        | allocate VolumeParam block on stack
    MOVEA.L     A7,A0                           | A0 = param block ptr
    MOVE.W      0x4(A3),0x16(A0)                | ioDrvNum (+$16) := drive number (evtMessage+2)
    _MountVol                                   | mount the volume
    ADDA.W      #0x18,A7                        | discard param block
    MOVE.W      D0,0x2(A3)                      | store result code in event message
    BRA.W       SYSEVT_RESTORE                  | restore port and return
| ----------------------------------------------------------
| _SystemClick ($A9B3) - process mouse click on a window.
| If theWindow is a desk accessory window, dispatches by part
| code (drag/goAway/content) and notifies DA via accEvent.
| If nil, calls DeskHook to handle desktop background click.
| ----------------------------------------------------------
SYSTEMCLICK:
    MOVEM.L     D0/D3-D4/A3-A4,-(A7)            | save registers
    MOVE.L      A7,-(A7)                        | push ptr for GetPort result
    _GetPort                                    | save current port
    MOVEA.L     0x18(A7),A4                     | A4 = window ptr (param)
    MOVEA.L     0x7E(A4),A3                     | A3 = window defProc handle
    MOVE.L      0x1C(A7),D4                     | D4 = event record ptr (param)
    MOVE.L      A4,D0                           | test window ptr
    BEQ.W       SYSTEMCLICK_EMPTY               | nil -> desktop click
    MOVEA.L     A4,A0                           | A0 = window ptr
    BSR.W       TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
    BNE.B       SYSTEMCLICK_EXIT                | not a DA -> restore and return
    MOVE.L      A1,D3                           | D3 = saved DCE ptr
    MOVEQ.L     #0x0,D0                         | clear high bytes
    MOVE.B      0x7E(A4),D0                     | D0 = WDEF resource ID (low byte of handle)
    CLR.L       -(A7)                           | space for FindWindow result
    MOVE.W      D0,-(A7)                        | push part code (varCode)
    MOVE.L      A4,-(A7)                        | push window ptr
    MOVE.W      #0x1,-(A7)                      | msg = wHit (find part)
    MOVEA.L     D4,A0                           | A0 = event record
    MOVE.L      0xA(A0),-(A7)                   | push event.where (mouse point)
    MOVE.L      A3,-(A7)                        | push defProc handle
    _LoadResource                               | ensure defProc is loaded
    MOVEA.L     (A3),A0                         | dereference defProc handle
    BSET        #0x7,(A3)                       | lock defProc handle
    JSR         (A0)                            | call WDEF: returns part code
    BCLR        #0x7,(A3)                       | unlock defProc handle
    MOVE.L      (A7)+,D0                        | D0 = part code from WDEF
    BEQ.B       SYSTEMCLICK_EXIT                | 0 = no hit -> done
    SUBQ.W      #0x2,D0                         | test for inDrag (2)
    BEQ.B       SYSTEMCLICK_OK                  | yes -> drag window
    SUBQ.W      #0x2,D0                         | test for inGoAway (4)
    BEQ.B       SYSTEMCLICK_OK_2                | yes -> track close box
    CLR.L       -(A7)                           | space for FrontWindow result
    _FrontWindow                                | get frontmost window
    MOVE.L      (A7)+,D0                        | D0 = front window
    CMP.L       A4,D0                           | is clicked window frontmost?
    BNE.B       SYSTEMCLICK_NO                  | no -> bring it to front
    MOVEA.L     D4,A3                           | A3 = event record for accEvent
    MOVEA.L     D3,A1                           | A1 = DCE ptr
    BSR.W       TEXTEDIT_CONT_3                 | send accEvent to DA
| Called by: SYSTEMCLICK, SYSTEMCLICK_EMPTY, SYSTEMCLICK_OK_2, SYSTEMCLICK_NO, SYSTEMCLICK_OK (and 1 more)
SYSTEMCLICK_EXIT:
    _SetPort                                    | restore saved port
    MOVEM.L     (A7)+,D3-D4/A3-A4               | restore registers
    MOVEA.L     (A7)+,A0                        | A0 = return address
    ADDQ.W      #0x8,A7                         | pop 2 params (window, event)
    JMP         (A0)                            | tail-call return from SYSTEMCLICK_EXIT via A0
| ----------------------------------------------------------
|
| SYSTEMCLICK_EMPTY
|
| Called during boot.
SYSTEMCLICK_EMPTY:
    TST.L       (DeskHook).W                    | custom desktop hook installed?
    BEQ.B       SYSTEMCLICK_EXIT                | no -> done
    MOVE.L      (WMgrPort).W,-(A7)              | set port to Window Manager port
    _SetPort                                    | switch to WMgr port
    MOVE.L      (GrayRgn).W,-(A7)               | clip to gray region (desktop area)
    _SetClip                                    | restrict drawing to desktop
    CLR.L       -(A7)                           | no window to clip above
    _ClipAbove                                  | clip to behind all windows
    MOVEA.L     D4,A0                           | A0 = event record
    MOVEA.L     (DeskHook).W,A1                 | A1 = desk hook procedure
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (click in desktop)
    JSR         (A1)                            | call desk hook
    BRA.B       SYSTEMCLICK_EXIT                | -> restore and return
| ----------------------------------------------------------
|
| SYSTEMCLICK_NO - DA window click not in front: bring to front.
|
SYSTEMCLICK_NO:
    MOVE.L      A4,-(A7)                        | push DA window to bring to front
    _SelectWindow                               | activate and bring window forward
    BRA.B       SYSTEMCLICK_EXIT                | -> restore and return
| ----------------------------------------------------------
|
| SYSTEMCLICK_OK - DragWindow path (inDrag part code).
|
SYSTEMCLICK_OK:
    MOVE.L      A4,-(A7)                        | push window ptr
    MOVEA.L     D4,A0                           | A0 = event record
    MOVE.L      0xA(A0),-(A7)                   | push event.where (start point)
    MOVEA.L     (A5),A0                         | A0 = app globals ptr
    PEA.L       -0x74(A0)                       | push drag boundary rect
    _DragWindow                                 | let user drag DA title bar
    BRA.B       SYSTEMCLICK_EXIT                | -> restore and return
| ----------------------------------------------------------
|
| SYSTEMCLICK_OK_2 - TrackGoAway path (inGoAway part code).
|
SYSTEMCLICK_OK_2:
    CLR.W       -(A7)                           | space for TrackGoAway result
    MOVE.L      A4,-(A7)                        | push window ptr
    MOVEA.L     D4,A0                           | A0 = event record
    MOVE.L      0xA(A0),-(A7)                   | push event.where (mouse point)
    _TrackGoAway                                | track close box click
    TST.B       (A7)+                           | user confirmed close?
    BEQ.B       SYSTEMCLICK_EXIT                | no -> done
    MOVEA.L     D3,A1                           | A1 = DCE ptr
    MOVE.L      (CloseOrnHook).W,D0             | custom close hook installed?
    BNE.B       SYSTEMCLICK_OK_3                | yes -> call custom hook
    MOVE.W      0x18(A1),-(A7)                  | push DA refNum from DCE
    _CloseDeskAcc                               | close the desk accessory
    BRA.B       SYSTEMCLICK_EXIT                | -> restore and return
| ----------------------------------------------------------
|
| SYSTEMCLICK_OK_3 - call custom close ornament hook.
|
SYSTEMCLICK_OK_3:
    MOVEA.L     D0,A0                           | A0 = close ornament hook
    JSR         (A0)                            | call custom close handler
    BRA.B       SYSTEMCLICK_EXIT                | -> restore and return
| ----------------------------------------------------------
| _SystemTask ($A9B4) - give time to desk accessories.
| Called from event loop. Iterates unit table; for each DA
| with dNeedTime+dOpened set whose dCtlDelay has elapsed,
| sends accRun (csCode=$41) via TEXTEDIT_CONT_5.
| Also sends accCursor (csCode=$42) to front DA.
| Reentrance-guarded via TaskLock low-mem byte.
| ----------------------------------------------------------
SYSTEMTASK:
    MOVEM.L     D3/A3,-(A7)                     | save registers
    BSET        #0x7,(TaskLock)                 | test-and-set task lock (reentrance guard)
    BNE.W       SYSTEMTASK_CONT                 | already locked -> bail
    SUBQ.W      #0x4,A7                         | space for saved port
    MOVE.L      A7,-(A7)                        | push ptr for GetPort result
    _GetPort                                    | save current port
    CLR.L       -(A7)                           | space for FrontWindow result
    _FrontWindow                                | get frontmost window
    MOVE.L      (A7)+,D0                        | D0 = front window ptr
    BEQ.B       SYSTEMTASK_SKIP                 | no front window -> skip DA cursor
    MOVEA.L     D0,A0                           | A0 = front window
    BSR.W       TEXTEDIT_CONT_2                 | look up DCE -> A1
    BNE.B       SYSTEMTASK_SKIP                 | not a DA -> skip
    BTST        #0x7,0x5(A1)                    | DCE flags: dNeedTime set?
    BNE.B       SYSTEMTASK_SKIP                 | yes -> handled below in loop
    MOVEQ.L     #0x42,D0                        | csCode = accCursor (66)
    BSR.W       TEXTEDIT_CONT_4                 | send accCursor to front DA
SYSTEMTASK_SKIP:
    MOVEA.L     (UTableBase).W,A3               | A3 = unit table base
    MOVE.W      (UnitTableEntryCount).W,D3      | D3 = number of unit table entries
SYSTEMTASK_LOOP:
    MOVE.L      (A3)+,D0                        | D0 = next DCE handle
    BEQ.B       SYSTEMTASK_SKIP_2               | nil -> skip this slot
    MOVEA.L     D0,A0                           | A0 = DCE handle
    MOVEA.L     (A0),A1                         | A1 = dereferenced DCE
    MOVE.W      0x4(A1),D0                      | D0 = dCtlFlags
    ANDI.W      #0x20A0,D0                      | mask dNeedTime + dOpened + dRAMBased
    CMPI.W      #0x2020,D0                      | dNeedTime and dOpened both set?
    BNE.B       SYSTEMTASK_SKIP_2               | no -> skip
    MOVEQ.L     #0x0,D0                         | clear high word
    MOVE.W      0x22(A1),D0                     | D0 = dCtlDelay (tick interval)
    BEQ.B       SYSTEMTASK_RUN_DA               | zero delay -> always run
    ADD.L       0x1A(A1),D0                     | D0 = last run time + delay
    CMP.L       (Ticks).W,D0                    | time to run yet?
    BGT.B       SYSTEMTASK_SKIP_2               | not yet -> skip
    MOVE.L      (Ticks).W,0x1A(A1)              | update last run time to now
SYSTEMTASK_RUN_DA:
    BSR.W       TEXTEDIT_CONT_5                 | send accRun to this DA
SYSTEMTASK_SKIP_2:
    SUBQ.W      #0x1,D3                         | decrement unit counter
    BGT.B       SYSTEMTASK_LOOP                 | more entries -> loop
    _SetPort                                    | restore saved port
    CLR.B       (TaskLock).W                    | release task lock
SYSTEMTASK_CONT:
    MOVEM.L     (A7)+,D3/A3                     | restore registers
    RTS                                         | return from accRun loop
| ----------------------------------------------------------
| _SystemMenu ($A9B5) - dispatch DA menu choice.
| If a DA owns the selected menuID, sends accMenu (csCode=$43)
| with the menu result (menuID:item) to the DA.
| ----------------------------------------------------------
SYSTEMMENU:
    MOVEM.L     A2-A3,-(A7)                     | save registers
    MOVE.L      0xC(A7),D1                      | D1 = menu result (menuID | item)
    SWAP.W      D1                              | D1.W = menuID
    MOVE.W      (MBarEnable).W,D0               | D0 = menu bar enable word
    BEQ.B       SYSTEMMENU_EMPTY                | zero -> use menuID from param
    MOVE.W      D0,D1                           | override with MBarEnable menuID
SYSTEMMENU_EMPTY:
    MOVEA.L     (UTableBase).W,A2               | A2 = unit table base
    MOVE.W      (UnitTableEntryCount).W,D2      | D2 = unit count
SYSTEMMENU_LOOP:
    MOVE.L      (A2)+,D0                        | D0 = next DCE handle
    BEQ.B       SYSTEMMENU_SKIP                 | nil -> skip slot
    MOVEA.L     D0,A0                           | A0 = DCE handle
    MOVEA.L     (A0),A1                         | A1 = dereferenced DCE
    BTST        #0x5,0x5(A1)                    | dCtlFlags: dNeedTime set? (has menu)
    BEQ.B       SYSTEMMENU_SKIP                 | no -> skip
    CMP.W       0x26(A1),D1                     | DCE menuID matches selected menu?
    BNE.B       SYSTEMMENU_SKIP                 | no -> try next
    MOVEA.L     0xC(A7),A3                      | A3 = menu result for accMenu
    MOVEQ.L     #0x43,D0                        | csCode = accMenu (67)
    BSR.W       TEXTEDIT_CONT_4                 | send accMenu control call
    BRA.B       SYSTEMMENU_DONE                 | -> done
| ----------------------------------------------------------
|
| SYSTEMMENU_SKIP - try next unit table entry
|
SYSTEMMENU_SKIP:
    SUBQ.W      #0x1,D2                         | decrement unit counter
    BGT.B       SYSTEMMENU_LOOP                 | more entries -> loop
SYSTEMMENU_DONE:
    MOVEM.L     (A7)+,A2-A3                     | restore registers
    MOVE.L      (A7)+,(A7)                      | pop return addr over param
    RTS                                         | return from unit counter loop
| ----------------------------------------------------------
| _SysEdit ($A9C2) - dispatch Edit menu command (Undo, Cut,
| Copy, Paste, Clear) to front DA. Returns TRUE if DA handled it.
| editCmd 0..3 -> csCode 68..71 (accUndo..accPaste).
| ----------------------------------------------------------
SYSTEMEDIT:
    CLR.W       0x6(A7)                         | clear result (FALSE by default)
    SUBQ.W      #0x8,A7                         | allocate saved port + window
    PEA.L       0x4(A7)                         | push ptr for GetPort result
    _GetPort                                    | save current port
    _FrontWindow                                | get frontmost window
    MOVE.L      (A7)+,D0                        | D0 = front window ptr
    BEQ.B       SYSEDIT_SKIP                    | no window -> skip
    MOVEA.L     D0,A0                           | A0 = front window
    BSR.W       TEXTEDIT_CONT_2                 | look up DA's DCE -> A1
    BNE.B       SYSEDIT_SKIP                    | not a DA -> skip
    MOVE.W      0x8(A7),D0                      | D0 = editCmd parameter (0-3)
    ADDI.W      #0x44,D0                        | convert to csCode (accUndo=68..accPaste=71)
    BSR.W       TEXTEDIT_CONT_4                 | send edit command to DA
    ADDQ.B      #0x1,0xA(A7)                    | set result = TRUE (DA handled it)
SYSEDIT_SKIP:
    _SetPort                                    | restore saved port
    BRA.B       CLOSEDESKACC_EXIT               | -> clean up and return
| ----------------------------------------------------------
| _OpenDeskAcc ($A9B6) - open desk accessory by name.
| Calls _Open with read-only IOParam, then SelectWindow +
| ShowWindow on the DA's window from dCtlWindow ($1E in DCE).
| ----------------------------------------------------------
OPENDESKACC:
    CLR.W       0x8(A7)                         | clear result (refNum = 0)
    SUBA.W      #0x20,A7                        | allocate IOParam block on stack
    MOVE.L      0x24(A7),0x12(A7)               | ioNamePtr = DA name (from param)
    CLR.W       0x16(A7)                        | ioVRefNum = 0
    MOVE.W      #0x40,0x1A(A7)                  | ioPermssn = fsRdPerm (read-only)
    CLR.L       0x1C(A7)                        | ioMisc = nil
    MOVEA.L     A7,A0                           | A0 = param block
    _Open                                       | open the desk accessory driver
    BNE.B       OPENDESKACC_ERR                 | error -> bail
    MOVE.W      0x18(A7),D0                     | D0 = ioRefNum (DA refNum)
    MOVE.W      D0,0x28(A7)                     | store as return value
    NOT.W       D0                              | convert refNum to unit number
    ASL.W       #0x2,D0                         | multiply by 4 for table index
    MOVEA.L     (UTableBase).W,A1               | A1 = unit table base
    MOVEA.L     0x0(A1,D0.W),A1                 | A1 = DCE handle
    MOVEA.L     (A1),A1                         | A1 = dereferenced DCE
    MOVE.L      0x1E(A1),D0                     | D0 = dCtlWindow (DA's window)
    BEQ.B       OPENDESKACC_ERR                 | nil -> no window to show
    MOVE.L      D0,-(A7)                        | push window ptr
    MOVE.L      D0,-(A7)                        | push window ptr again
    _SelectWindow                               | bring DA window to front
    _ShowWindow                                 | make DA window visible
OPENDESKACC_ERR:
    ADDA.W      #0x20,A7                        | discard param block
    MOVE.L      (A7)+,(A7)                      | pop return addr over name param
    RTS                                         | return from DA window activation
| ----------------------------------------------------------
| _CloseDeskAcc ($A9B7) - close DA by refNum.
| Calls _Close on a minimal IOParam block.
| ----------------------------------------------------------
CLOSEDESKACC:
    MOVE.W      0x4(A7),D0                      | D0 = DA refNum (param)
    SUBA.W      #0x1E,A7                        | allocate IOParam block
    MOVE.W      D0,0x18(A7)                     | ioRefNum = DA refNum
    MOVEA.L     A7,A0                           | A0 = param block
    _Close                                      | close the DA driver
    ADDA.W      #0x1E,A7                        | discard param block
CLOSEDESKACC_EXIT:
    MOVEA.L     (A7)+,A0                        | A0 = return address
    ADDQ.W      #0x2,A7                         | pop parameter word
    JMP         (A0)                            | tail-call return from CLOSEDESKACC_EXIT via A0
