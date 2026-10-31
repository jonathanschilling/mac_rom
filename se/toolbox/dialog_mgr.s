| Dialog Manager
|
| Apple source: DialogMgr.a (MacSEROM.lst module DMGR). The public traps
| come first, in physical ROM order:
|   InitDialogs                                     (initialization)
|   StopAlert, NoteAlert, CautionAlert, Alert       (alerts)
|   GetNewDialog, NewDialog                         (creation)
|   IsDialogEvent, DialogSelect, ModalDialog        (event handling)
|   DrawDialog, UpdtDialog                          (drawing)
|   CloseDialog, DisposDialog                       (disposal)
|   CouldDialog, CouldAlert, FreeDialog, FreeAlert  (resource preloading)
|   ParamText, ErrorSound                           (text substitution, sound)
|   GetDItem, SetDItem, GetIText, SetIText, SelIText (item access)
|   HideDItem, ShowDItem                            (item visibility)
|   FindDItem                                       (item hit test)
| followed by the internal routines (see the section comment there).
|
| References: Inside Macintosh Vol I, Ch 13 (The Dialog Manager).

IAPPEND:                                        | MacSEROM.lst: end marker of the module before
DMGR:
    .short      0x000A
    .long       0x0014002A
    .short      0x0034
| DT_MMAXIAPPEND_EMPTY: empty Pascal string (length=0), used as dialog title
DT_MMAXIAPPEND_EMPTY:
    .short      0x0000
| ----------------------------------------------------------
|
| _InitDialogs ($A97B) -- initialize Dialog Manager state.
|
| Stack: resumeProc(L). Sets ResumeProc, clears alert state, installs
| default DABeeper, clears ParamText slots, sets dialog font to system.
INITDIALOGS:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
    MOVE.L      0x8(A6),(ResumeProc).W          | ResumeProc = caller's procptr
    CLR.W       (ACount).W                      | reset alert invocation count
    ST.B        (ANumber).W                     | invalidate current alert ID (0xFF)
    LEA.L       (DABeeper).W,A0                 | A0 = start of dialog globals
    LEA.L       INITDIALOGS_CONT(PC),A1         | A1 = default beep procedure
    MOVE.L      A1,(A0)+                        | DABeeper = default beep proc
    CLR.L       (A0)+                           | clear DAStrings[0] (ParamText ^0)
    CLR.L       (A0)+                           | clear DAStrings[1] (ParamText ^1)
    CLR.L       (A0)+                           | clear DAStrings[2] (ParamText ^2)
    CLR.L       (A0)+                           | clear DAStrings[3] (ParamText ^3)
    CLR.W       (DlgFont).W                     | DlgFont = system font (0)
    MOVEQ.L     #0x4,D0                         | 4 bytes of params to clean up
    BRA.W       MODALDIALOG_CONT_4              | dialog epilogue
| ----------------------------------------------------------
|
| INITDIALOGS_CONT -- default DABeeper procedure.
|
| Pops return address and beep count from stack, beeps that many
| times (each beep 3 ticks long with 6-tick pause between), then
| jumps back to the saved return address.
| Called during boot.
INITDIALOGS_CONT:
    MOVEA.L     (A7)+,A1                        | A1 = return address
    MOVE.W      (A7)+,D2                        | D2 = beep count
INITDIALOGS_LOOP:
    BEQ.B       INITDIALOGS_DONE                | count exhausted -> done
    MOVE.W      #0x3,-(A7)                      | push duration = 3 ticks
    _SysBeep                                    | emit system beep
    MOVEA.W     #0x6,A0                         | A0 = 6 (delay ticks)
    _Delay                                      | wait for delay
    SUBQ.W      #0x1,D2                         | decrement beep counter
    BRA.B       INITDIALOGS_LOOP                | loop for remaining beeps
| ----------------------------------------------------------
|
| INITDIALOGS_DONE -- beep loop done, return to caller.
|
| Called during boot.
INITDIALOGS_DONE:
    JMP         (A1)                            | tail-call return from INITDIALOGS_DONE via A1
| ----------------------------------------------------------
|
| INITDIALOGS_EXIT -- _IsDialogEvent ($A97F): handle Return/Enter.
|
| Despite its name, this is the IsDialogEvent trap entry. Checks if
| event is keyDown of Return (0x0D) or Enter (0x03); if so, treats
| as default button press: stores aDefItem in itemHit, hilites the
| default button for 8 ticks, sets handled flag.
| Stack: theDialog(L), eventPtr(L), itemHit(L) -> handled(B).
| Called during boot.
INITDIALOGS_EXIT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0x10(A6),A4                     | A4 = dialog pointer
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load item list
    CLR.W       0x14(A6)                        | clear result flag (no item hit)
    MOVEA.L     0xC(A6),A0                      | A0 = event record pointer
    CMPI.W      #0x3,(A0)                       | event type keyDown (3)?
    BNE.B       INITDIALOGS_SKIP_2              | no -> skip
    CMPI.B      #0x3,0x5(A0)                    | key code Enter (0x03)?
    BEQ.B       INITDIALOGS_OK                  | yes -> treat as default
    CMPI.B      #0xD,0x5(A0)                    | key code Return (0x0D)?
    BNE.B       INITDIALOGS_SKIP_2              | no -> not a default key
INITDIALOGS_OK:
    MOVE.W      0xA8(A4),D3                     | D3 = aDefItem (default item #)
    MOVEA.L     0x8(A6),A1                      | A1 = caller's itemHit ptr
    MOVE.W      D3,(A1)                         | *itemHit = default item
    SUBQ.W      #0x1,D3                         | convert to 0-based index
    BSR.W       DLGMGR_OK_3                     | get item entry for default item
    BSR.W       FINDDITEM_CONT_2                | get item handle and type
    ANDI.W      #0x7,D0                         | mask to item type (low 3 bits)
    CMPI.W      #0x4,D0                         | type 4 (button control)?
    BNE.B       INITDIALOGS_SKIP                | no -> skip hilite animation
    MOVE.B      0xC(A2),D0                      | D0 = item flags
    BMI.B       INITDIALOGS_SKIP_2              | disabled -> skip
    MOVE.L      A0,-(A7)                        | push control handle for unhilite
    CLR.W       -(A7)                           | push hiliteState = 0 (unhilite)
    MOVE.L      A0,-(A7)                        | push control handle for hilite
    MOVE.W      #0xA,-(A7)                      | push hiliteState = 10 (invert)
    _HiliteControl                              | hilite default button
    MOVEA.W     #0x8,A0                         | A0 = 8 (delay ticks)
    _Delay                                      | wait for visual feedback
    _HiliteControl                              | unhilite button
INITDIALOGS_SKIP:
    ADDQ.B      #0x1,0x14(A6)                   | result flag = true (item was hit)
INITDIALOGS_SKIP_2:
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, clear lock
    MOVEQ.L     #0xC,D0                         | 12 bytes of params to clean up
    BRA.W       MODALDIALOG_CONT_4              | dialog epilogue
| ----------------------------------------------------------
|
| _StopAlert ($A986) -- show stop-icon alert dialog.
| Stack: alertID(W), filterProc(L) -> itemHit(W).
STOPALERT:
    MOVEQ.L     #0x0,D0                         | D0 = 0: stop icon
    BRA.B       ALERT_CONT                      | -> common alert body
| ----------------------------------------------------------
|
| _NoteAlert ($A987) -- show note-icon alert dialog.
NOTEALERT:
    MOVEQ.L     #0x1,D0                         | D0 = 1: note icon
    BRA.B       ALERT_CONT                      | -> common alert body
| ----------------------------------------------------------
|
| _CautionAlert ($A988) -- show caution-icon alert dialog.
CAUTIONALERT:
    MOVEQ.L     #0x2,D0                         | D0 = 2: caution icon
    BRA.B       ALERT_CONT                      | -> common alert body
| ----------------------------------------------------------
|
| _Alert ($A985) -- show plain alert (no icon).
ALERT:
    MOVEQ.L     #-0x1,D0                        | D0 = -1: plain alert (no icon)
| ALERT_CONT (ALERT_CONT) -- common alert body.
ALERT_CONT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVE.W      D0,D3                           | D3 = icon type
    MOVE.W      0xC(A6),D0                      | D0 = alert resource ID
    BSR.W       COULDALERT_CONT_2               | load ALRT resource template
    MOVE.W      (ACount).W,D0                   | D0 = previous invocation count
    MOVE.W      0xC(A6),D1                      | D1 = current alert ID
    CMP.W       (ANumber).W,D1                  | same alert as last time?
    BEQ.B       ALERT_OK                        | yes -> keep count
    MOVE.W      D1,(ANumber).W                  | no -> store new alert ID
    MOVEQ.L     #0x0,D0                         | reset count to 0
ALERT_OK:
    MOVE.W      D0,(ACount).W                   | save invocation count
    MOVE.W      0xA(A1),D4                      | D4 = alert stage bits (4 stages x 4 bits)
ALERT_CONT_2:
    SUBQ.W      #0x1,D0                         | shift to current stage's 4-bit field
    BLT.B       ALERT_CONT_3                    | reached stage -> extract nibble
    LSR.W       #0x4,D4                         | shift right one nibble (4 bits)
    BRA.B       ALERT_CONT_2                    | continue shifting
| ----------------------------------------------------------
|
| ALERT_CONT_3 -- process alert stage nibble.
|
ALERT_CONT_3:
    ANDI.W      #0xF,D4                         | isolate low nibble (current stage)
    MOVE.L      D4,D0                           | D0 = stage nibble
    ANDI.W      #0x3,D0                         | low 2 bits = beep count (0-3)
    BSR.W       ALERT_CONT_6                    | call beeper proc D0 times
    BTST        #0x2,D4                         | bit 2 = show dialog flag
    BNE.B       ALERT_CONT_4                    | set -> show alert dialog
    MOVE.W      (MinusOne).W,0xE(A6)            | no dialog -> return -1 as itemHit
    BRA.W       ALERT_DISPOSE_UNLOCK            | -> cleanup
| ----------------------------------------------------------
|
| ALERT_CONT_4 -- create and show alert dialog.
|
ALERT_CONT_4:
    MOVE.L      #0x1FF,D0                       | flush all event types
    _FlushEvents                                | clear event queue before modal dialog
    MOVE.W      0x8(A1),D0                      | D0 = DITL resource ID from ALRT template
    BSR.W       ALERT_CONT_5                    | load and copy DITL resource
    MOVEA.L     (A2),A1                         | A1 = deref'd ALRT template data
    SUBQ.W      #0x4,A7                         | space for NewDialog result handle
    CLR.L       -(A7)                           | dStorage = nil (allocate on heap)
    PEA.L       (A1)                            | push boundsRect from ALRT template
    PEA.L       DT_MMAXIAPPEND_EMPTY(PC)        | push empty title string
    ST.B        -(A7)                           | visible = true
    MOVE.W      #0x1,-(A7)                      | procID = 1 (dBoxProc, no title bar)
    MOVE.L      (MinusOne).W,-(A7)              | behind = -1 (in front of all windows)
    CLR.W       -(A7)                           | goAwayFlag = false
    CLR.L       -(A7)                           | refCon = 0
    MOVE.L      A0,-(A7)                        | push items handle (copied DITL)
    _NewDialog                                  | create the alert dialog
    MOVEA.L     (A7),A4                         | A4 = new dialog pointer
    PEA.L       -0x2C(A6)                       | push address to save current port
    _GetPort                                    | save current grafPort
    _SetPort                                    | set dialog as current port
    TST.W       D3                              | icon to display?
    BMI.B       ALERT_SKIP                      | -1 (no icon) -> skip
    SUBQ.W      #0x4,A7                         | space for GetIcon result
    MOVE.W      D3,-(A7)                        | push icon ID (0=stop,1=note,2=caution)
    _GetIcon                                    | load icon resource
    MOVE.L      (A7)+,D0                        | D0 = icon handle
    BEQ.B       ALERT_SKIP                      | not found -> skip plot
    PEA.L       DMGR(PC)                        | push icon bounds rect (10,20,42,52)
    MOVE.L      D0,-(A7)                        | push icon handle
    _PlotIcon                                   | draw icon in alert dialog
ALERT_SKIP:
    ASR.W       #0x3,D4                         | bit 3 of stage = default-button selector
    ADDQ.W      #0x1,D4                         | D4 = default item number (1 or 2)
    MOVE.W      D4,0xA8(A4)                     | dialog.aDefItem = D4
    MOVE.L      A4,-(A7)                        | push dialog pointer
    MOVE.W      D4,-(A7)                        | push default item number
    PEA.L       -0x3C(A6)                       | push ptr for item type result
    MOVE.L      (A7),-(A7)                      | push ptr for item handle result
    PEA.L       -0x28(A6)                       | push ptr for item rect result
    _GetDialogItem                              | get default item's rect for bold outline
    LEA.L       -0x28(A6),A0                    | A0 = default item's bounding rect
    MOVEQ.L     #0x3,D0                         | inset left/right = 3 pixels
    MOVEQ.L     #0x10,D1                        | pen size = 16 (bold outline)
    MOVEQ.L     #0x4,D2                         | round radius = 4
    BSR.W       DLG_FrameRoundOuter             | draw bold rounded rect around default
    MOVE.L      0x8(A6),-(A7)                   | push filterProc for ModalDialog
    PEA.L       0xE(A6)                         | push address for itemHit result
    _ModalDialog                                | run modal dialog event loop
    MOVE.L      -0x2C(A6),-(A7)                 | push saved port
    _SetPort                                    | restore original grafPort
    MOVE.L      A4,-(A7)                        | push dialog pointer
    _DisposeDialog                              | dispose the alert dialog
ALERT_DISPOSE_UNLOCK:
    MOVEA.L     A2,A0                           | A0 = ALRT resource handle
    _HUnlock                                    | unlock ALRT handle
    MOVE.W      (ACount).W,D1                   | D1 = current invocation count
    ADDQ.W      #0x1,D1                         | increment count for next call
    CMPI.W      #0x4,D1                         | maximum 4 stages
    BLT.B       ALERT_OK_2                      | under max -> use as-is
    MOVEQ.L     #0x3,D1                         | cap at stage 3 (repeat last stage)
ALERT_OK_2:
    MOVE.W      D1,(ACount).W                   | save updated invocation count
    MOVEQ.L     #0x6,D0                         | 6 bytes of params to clean up
    BRA.B       GETNEWDIALOG_CONT               | dialog epilogue
| ----------------------------------------------------------
|
| ALERT_CONT_5 -- load DITL resource and copy it.
|
| The dialog owns its item list, so we use _HandToHand to make a
| private copy of the DITL handle. Returns A0 = copied DITL handle.
| Called during boot.
ALERT_CONT_5:
    SUBQ.W      #0x4,A7                         | space for GetResource result
    MOVE.L      #0x4449544C,-(A7)               | push type = 'DITL'
    MOVE.W      D0,-(A7)                        | push DITL resource ID
    _GetResource                                | load DITL template
    MOVEA.L     (A7)+,A0                        | A0 = DITL handle
    _HandToHand                                 | make a copy
    RTS                                         | A0 = copied DITL handle
| ----------------------------------------------------------
|
| ALERT_CONT_6 -- call the DABeeper procedure D0 times.
|
| Indirects through DABeeper lowmem. If no beeper is installed, no-op.
| Called during boot.
ALERT_CONT_6:
    MOVEM.L     D0-D2/A0-A2,-(A7)               | save registers
    MOVE.L      (DABeeper).W,D1                 | D1 = beep procedure address
    BEQ.B       ALERT_SKIP_3                    | no beeper -> skip
    MOVE.W      D0,-(A7)                        | push beep count on stack
    MOVEA.L     D1,A0                           | A0 = beeper procedure
    JSR         (A0)                            | call beeper(count)
ALERT_SKIP_3:
    MOVEM.L     (A7)+,D0-D2/A0-A2               | restore registers
    RTS                                         | return from ALERT_CONT_6
| ----------------------------------------------------------
|
| _GetNewDialog ($A97C) -- create a dialog from a 'DLOG' resource.
|
| Stack: dialogID(W), dStorage(L), behind(L) -> dialog(L).
| Loads the DLOG resource template, marshals its fields onto the
| stack as _NewDialog parameters (boundsRect, title, visible, procID,
| behind, goAwayFlag, refCon, items via DITL copy), invokes _NewDialog.
GETNEWDIALOG:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVE.W      0x10(A6),D0                     | D0 = dialog resource ID
    BSR.W       COULDALERT_CONT_3               | load DLOG resource, A1 = data
    SUBQ.W      #0x4,A7                         | space for NewDialog result
    MOVE.L      0xC(A6),-(A7)                   | push behind window ptr
    MOVE.L      A1,-(A7)                        | push boundsRect (start of DLOG)
    PEA.L       0x14(A1)                        | push title string ptr (DLOG+0x14)
    ADDQ.L      #0x8,A1                         | A1 += 8 (skip rect)
    MOVE.L      (A1)+,-(A7)                     | push procID(W) + visible(B) + filler
    MOVE.L      0x8(A6),-(A7)                   | push dStorage from caller
    MOVE.W      (A1)+,-(A7)                     | push goAwayFlag(W)
    MOVE.L      (A1)+,-(A7)                     | push refCon(L)
    MOVE.W      (A1)+,D0                        | D0 = DITL resource ID
    BSR.B       ALERT_CONT_5                    | load and copy DITL
    MOVE.L      A0,-(A7)                        | push items handle (copied DITL)
    _NewDialog                                  | create dialog
    MOVEA.L     A2,A0                           | A0 = DLOG resource handle
    _HUnlock                                    | unlock DLOG handle
    MOVE.L      (A7)+,0x12(A6)                  | return dialog ptr in result slot
    MOVEQ.L     #0xA,D0                         | 10 bytes of params to clean up
GETNEWDIALOG_CONT:
    BRA.B       NEWDIALOG_CONT                  | -> common dialog epilogue
| ----------------------------------------------------------
|
| _NewDialog ($A97D) -- create a dialog window with item list.
|
| Stack: dStorage(L), bounds(8), title(L), visible(B), procID(W),
|        behind(L), goAwayFlag(B), refCon(L), items(L) -> dialog(L).
| Allocates dialog record (170 bytes if dStorage=nil), creates window
| via _NewWindow with windowKind=2 (dialog), installs items handle,
| TextEdit handle (initial focus), aDefItem=1, gets the dialog port.
NEWDIALOG:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    TST.L       0x22(A6)                        | dStorage param non-nil?
    BNE.B       NEWDIALOG_OK                    | yes -> use it
    MOVE.L      #0xAA,D0                        | D0 = 170 (sizeof DialogRecord)
    _NewPtr                                     | allocate on heap
    MOVE.L      A0,0x22(A6)                     | dStorage = new ptr
NEWDIALOG_OK:
    LEA.L       0xC(A6),A0                      | A0 = stack frame above bounds
    MOVEQ.L     #0x1E,D0                        | D0 = 30 (NewWindow params size)
    SUBA.L      D0,A7                           | reserve space for marshalled args
    MOVEA.L     A7,A1                           | A1 = dest
    _BlockMove                                  | copy params from frame to stack
    _NewWindow                                  | create dialog window
    MOVEA.L     (A7)+,A4                        | A4 = new window ptr
    MOVE.L      A4,0x26(A6)                     | result slot = dialog ptr
    MOVEA.L     0x8(A6),A3                      | A3 = items handle from frame
    MOVE.W      #0x2,0x6C(A4)                   | window.windowKind = 2 (dialog)
    MOVE.L      A3,0x9C(A4)                     | dialog.items = items handle
    MOVE.W      (MinusOne).W,0xA4(A4)           | dialog.editField = -1 (no edit yet)
    MOVE.W      (DlgFont).W,0x44(A4)            | port.txFont = DlgFont
    SUBQ.W      #0x4,A7                         | space for SetPort/GetPort
    MOVE.L      A7,-(A7)                        | push ptr for GetPort result
    _GetPort                                    | save current port
    MOVE.L      A4,-(A7)                        | push dialog port
    _SetPort                                    | set dialog as current
    MOVE.W      #0x1,0xA8(A4)                   | aDefItem = 1 (default button)
    SUBQ.W      #0x4,A7                         | space for TENew result
    PEA.L       0x10(A4)                        | push portRect for view
    MOVE.L      (A7),-(A7)                      | push portRect for dest
    _TENew                                      | allocate TextEdit record
    MOVE.L      (A7),0xA0(A4)                   | dialog.textH = TE handle
    MOVEA.L     (A7)+,A1                        | A1 = TE handle
    MOVEA.L     (A1),A2                         | A2 = deref'd TE record
    MOVEA.L     0x3E(A2),A0                     | A0 = TE.hText (text body handle)
    _DisposeHandle                              | dispose TE's auto-allocated text
    _SetPort                                    | restore original port
    BSR.W       CLOSEDIALOG_CONT_4              | set up port, load item list
    MOVEQ.L     #0x0,D4                         | D4 = 0 (visible flag for items)
    BSR.W       FINDDITEM_CONT                  | install items in dialog
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, clear lock
    MOVEQ.L     #0x1E,D0                        | 30 bytes of params to clean up
NEWDIALOG_CONT:
    BRA.B       ISDIALOGEVENT_CONT              | -> common dialog epilogue
| ----------------------------------------------------------
|
| NEWDIALOG_CONT_2 -- find dialog window for a given event.
|
| For mouse events (type 1 = mouseDown), uses _FindWindow to locate
| the window. For update (6) and activate (8) events, the message
| field at A2+2 is already the window pointer. Returns A4 = window.
| Called during boot (3,693 times in 30s trace).
NEWDIALOG_CONT_2:
    MOVE.W      (A2),D3                         | D3 = event type
    SUBQ.W      #0x6,D3                         | type 6 (update)?
    BEQ.B       NEWDIALOG_OK_2                  | yes -> use message field
    SUBQ.W      #0x2,D3                         | type 8 (activate)?
    BEQ.B       NEWDIALOG_OK_2                  | yes -> use message field
    SUBQ.W      #0x4,A7                         | space for FrontWindow result
    _FrontWindow                                | A0 = front window
    MOVEA.L     (A7)+,A4                        | A4 = front window
    RTS                                         | return from NEWDIALOG_CONT_2
| ----------------------------------------------------------
|
| NEWDIALOG_OK_2 -- update/activate: window is in event message field.
|
| Called during boot.
NEWDIALOG_OK_2:
    MOVEA.L     0x2(A2),A4                      | A4 = event.message (window ptr)
    RTS                                         | return from NEWDIALOG_OK_2
| ----------------------------------------------------------
|
| _IsDialogEvent ($A97F) -- test if event is for a dialog window.
|
| Stack: eventPtr(L) -> isDialog(B). Returns true if event's window
| (or front window for non-window events) has windowKind = 2 (dialog),
| AND for mouseDown events, only if FindWindow returns inContent (3).
ISDIALOGEVENT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    CLR.W       0xC(A6)                         | result = false
    MOVEA.L     0x8(A6),A2                      | A2 = event ptr
    BSR.B       NEWDIALOG_CONT_2                | A4 = event's window
    CMPI.W      #0x2,0x6C(A4)                   | window.windowKind = 2 (dialog)?
    BNE.B       ISDIALOGEVENT_SKIP              | no -> not a dialog event
    MOVE.W      (A2),D3                         | D3 = event type
    SUBQ.W      #0x1,D3                         | type 1 (mouseDown)?
    BNE.B       ISDIALOGEVENT_NO                | no -> result = true
    SUBQ.W      #0x2,A7                         | space for FindWindow result
    MOVE.L      0xA(A2),-(A7)                   | push event.where (mouse pt)
    PEA.L       -0x14(A6)                       | push ptr for window result
    _FindWindow                                 | partCode = result, *ptr = window
    SUBQ.W      #0x3,(A7)+                      | partCode == 3 (inContent)?
    BNE.B       ISDIALOGEVENT_SKIP              | no -> not handled
    CMPA.L      -0x14(A6),A4                    | window matches our dialog?
    BNE.B       ISDIALOGEVENT_SKIP              | no -> not handled
ISDIALOGEVENT_NO:
    ADDQ.B      #0x1,0xC(A6)                    | result = true
ISDIALOGEVENT_SKIP:
    MOVEQ.L     #0x4,D0                         | 4 bytes of params to clean up
ISDIALOGEVENT_CONT:
    BRA.B       DIALOGSELECT_CONT               | -> common dialog epilogue
| ----------------------------------------------------------
|
| _DialogSelect ($A980) -- dispatch a dialog event to its handler.
|
| Stack: eventPtr(L), theDialog(L), itemHit(L) -> handled(B).
| Calls RETURNS_15 to dispatch the event (key/click on items, etc).
| Returns handled=true if D3 (item index) is non-negative.
DIALOGSELECT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    CLR.W       0x14(A6)                        | result = false
    MOVEA.L     0xC(A6),A3                      | A3 = caller's theDialog ptr
    CLR.L       (A3)                            | *theDialog = nil (default)
    MOVEA.L     0x10(A6),A2                     | A2 = event ptr
    BSR.B       NEWDIALOG_CONT_2                | A4 = event's window
    MOVE.L      A4,(A3)                         | *theDialog = window ptr
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load item list
    MOVEA.L     0x10(A6),A0                     | A0 = event ptr
    LEA.L       -0x4C(A6),A1                    | A1 = local event copy
    MOVEQ.L     #0x10,D0                        | D0 = 16 (sizeof EventRecord)
    _BlockMove                                  | copy event to local frame
    BSR.W       RETURNS_15                      | dispatch event -> D3 = itemHit
    TST.W       D3                              | item hit?
    BMI.B       DIALOGSELECT_NO                 | no -> result stays false
    ADDQ.B      #0x1,0x14(A6)                   | result = true
DIALOGSELECT_NO:
    MOVEA.L     0x8(A6),A0                      | A0 = caller's itemHit ptr
    MOVE.W      D3,(A0)                         | *itemHit = D3
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, clear lock
    MOVEQ.L     #0xC,D0                         | 12 bytes of params to clean up
DIALOGSELECT_CONT:
    BRA.B       MODALDIALOG_CONT_2              | -> common dialog epilogue
| ----------------------------------------------------------
|
| _ModalDialog ($A991) -- run a modal dialog event loop.
|
| Stack: filterProc(L), itemHit(L). Loops calling SystemTask, TEIdle,
| GetNextEvent. Calls user filterProc first if non-nil; if it returns
| true, exits with itemHit set. Otherwise dispatches dialog events
| via IsDialogEvent + DialogSelect. Beeps on null events of type 1.
MODALDIALOG:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
MODALDIALOG_NEXT:
    _SystemTask                                 | give system tasks CPU time
    SUBQ.W      #0x4,A7                         | space for FrontWindow result
    _FrontWindow                                | A0 = front window
    MOVEA.L     (A7)+,A0                        | A0 = front window
    TST.W       0xA4(A0)                        | dialog has edit field?
    BMI.B       MODALDIALOG_SKIP                | no -> skip TEIdle
    MOVE.L      0xA0(A0),-(A7)                  | push TextEdit handle
    _TEIdle                                     | blink caret
MODALDIALOG_SKIP:
    SUBQ.W      #0x6,A7                         | space for GetNextEvent result + flag
    MOVE.W      #0x17F,-(A7)                    | push event mask = everyEvent
    PEA.L       -0x4C(A6)                       | push event record ptr
    _GetNextEvent                               | get next event
    MOVE.L      0xC(A6),D3                      | D3 = filterProc address
    BNE.B       MODALDIALOG_CONT                | non-nil -> use it
    LEA.L       INITDIALOGS_EXIT(PC),A0         | A0 = default filter (IsDialogEvent)
    MOVE.L      A0,D3                           | D3 = default filter
MODALDIALOG_CONT:
    _FrontWindow                                | A0 = front window (caller's filter context)
    PEA.L       -0x4C(A6)                       | push event record ptr
    MOVE.L      0x8(A6),-(A7)                   | push itemHit ptr
    MOVEA.L     D3,A0                           | A0 = filter procedure
    JSR         (A0)                            | call filter(itemHit, eventRec)
    TST.B       (A7)+                           | filter handled event?
    BNE.B       MODALDIALOG_EXIT                | yes -> exit with itemHit set
    SUBQ.W      #0x2,A7                         | space for IsDialogEvent result
    PEA.L       -0x4C(A6)                       | push event record ptr
    _IsDialogEvent                              | is this a dialog event?
    TST.W       (A7)+                           | true?
    BEQ.B       MODALDIALOG_NO                  | no -> handle null/beep
    SUBQ.W      #0x2,A7                         | space for DialogSelect result
    PEA.L       -0x4C(A6)                       | push event record ptr
    PEA.L       -0x1C(A6)                       | push theDialog ptr (frame slot)
    MOVE.L      0x8(A6),-(A7)                   | push itemHit ptr
    _DialogSelect                               | dispatch to dialog
    TST.W       (A7)+                           | item hit?
    BLE.B       MODALDIALOG_NEXT                | no -> next iteration
MODALDIALOG_EXIT:
    MOVEQ.L     #0x8,D0                         | 8 bytes of params to clean up
MODALDIALOG_CONT_2:
    BRA.B       MODALDIALOG_CONT_4              | -> common epilogue
| ----------------------------------------------------------
|
| MODALDIALOG_NO -- null event handler: beep on type 1 (mouseDown).
|
| Called during boot.
MODALDIALOG_NO:
    MOVE.W      -0x4C(A6),D0                    | D0 = event type
    SUBQ.W      #0x1,D0                         | type 1 (mouseDown)?
    BNE.B       MODALDIALOG_NEXT                | no -> next iteration
    MOVEQ.L     #0x1,D0                         | yes -> beep once
    BSR.W       ALERT_CONT_6                    | invoke DABeeper(1)
    BRA.B       MODALDIALOG_NEXT                | -> next iteration
| ----------------------------------------------------------
|
| MODALDIALOG_CONT_3 -- Dialog Manager common prologue.
|
| Pops return address, sets up 76-byte LINK frame, saves D3-D7/A2-A4,
| jumps back. Used by every Dialog Manager trap entry.
| Called during boot (3,696 times in 30s trace).
MODALDIALOG_CONT_3:
    MOVEA.L     (A7)+,A0                        | A0 = caller's return address
    LINK        A6,#-0x4C                       | 76 bytes of locals
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save callee-saved regs
    JMP         (A0)                            | tail-call into trap body
| ----------------------------------------------------------
|
| MODALDIALOG_CONT_4 -- Dialog Manager common epilogue.
|
| Restores callee-saved regs, tears down LINK frame, pops D0 bytes
| of params, returns through caller.
| Called during boot (3,696 times in 30s trace).
MODALDIALOG_CONT_4:
    MOVEM.L     (A7)+,D3-D7/A2-A4               | restore callee-saved regs
    UNLK        A6                              | discard local frame
    MOVEA.L     (A7)+,A0                        | A0 = caller's return address
    ADDA.L      D0,A7                           | pop D0 bytes of params
    JMP         (A0)                            | tail-call return from MODALDIALOG_CONT_4 via A0
| ----------------------------------------------------------
|
| _DrawDialog ($A981) -- redraw a dialog window's items.
|
| Stack: theDialog(L). Draws controls and items via FINDDITEM_CONT with
| operation = 1 (draw all items).
DRAWDIALOG:
    BSR.B       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0x8(A6),A4                      | A4 = dialog ptr
    BSR.B       CLOSEDIALOG_CONT_4              | set port, load item list
    MOVE.L      A4,-(A7)                        | push dialog ptr
    _DrawControls                               | draw all controls
    MOVEQ.L     #0x1,D4                         | D4 = 1 (draw operation)
    BSR.W       FINDDITEM_CONT                  | iterate items: draw each
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, clear lock
    BRA.B       CLOSEDIALOG_CONT                | StdFourExit
| ----------------------------------------------------------
|
| _UpdtDialog ($A978) -- redraw dialog items in update region.
|
| Stack: theDialog(L), updateRgn(L). Calls _UpdtControl + iterates
| items with operation 3 (update only items in updateRgn).
UPDTDIALOG:
    BSR.B       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0xC(A6),A4                      | A4 = dialog ptr
    BSR.B       CLOSEDIALOG_CONT_4              | set port, load item list
    MOVE.L      A4,-(A7)                        | push dialog ptr
    MOVE.L      0x8(A6),-(A7)                   | push updateRgn
    _UpdtControl                                | update controls in region
    MOVEQ.L     #0x3,D4                         | D4 = 3 (update operation)
    BSR.W       FINDDITEM_CONT                  | iterate items: update each
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, clear lock
    BRA.W       SETITEXT_CONT                   | StdEightExit
| ----------------------------------------------------------
|
| _CloseDialog ($A982) -- close dialog window, dispose item handles.
|
| Stack: theDialog(L). Empties contRgn (so window doesn't update),
| disposes all item Pascal-string storage via FINDDITEM_CONT op=2,
| disposes TextEdit handle, then _CloseWindow.
CLOSEDIALOG:
    BSR.B       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0x8(A6),A4                      | A4 = dialog ptr
    BSR.B       CLOSEDIALOG_CONT_4              | set port, load item list
    MOVE.L      0x1C(A4),-(A7)                  | push contRgn handle
    _SetEmptyRgn                                | empty content region
    MOVEQ.L     #0x2,D4                         | D4 = 2 (dispose operation)
    BSR.W       FINDDITEM_CONT                  | iterate items: dispose each
    BSR.B       CLOSEDIALOG_CONT_6              | restore port, clear lock
    MOVEA.L     0xA0(A4),A0                     | A0 = TE handle
    MOVEA.L     (A0),A0                         | (deref - unused, sets up A0)
    MOVEA.L     0xA0(A4),A0                     | A0 = TE handle (re-fetched)
    _DisposeHandle                              | dispose TE handle
    MOVE.L      A4,-(A7)                        | push window ptr
    _CloseWindow                                | close the window
CLOSEDIALOG_CONT:
    MOVEQ.L     #0x4,D0                         | 4 bytes of params to clean up
CLOSEDIALOG_CONT_2:
    BRA.B       MODALDIALOG_CONT_4              | -> common epilogue
| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_3 -- load and lock the dialog's item list (DITL).
|
| Used as helper during dialog setup. Returns A3 = items handle (locked).
CLOSEDIALOG_CONT_3:
    MOVEA.L     0x9C(A4),A3                     | A3 = dialog.items handle
    TST.L       (A3)                            | already loaded?
    BNE.B       NEWDIALOG_LOCK_ITEMS            | yes -> just lock
    MOVE.L      A3,-(A7)                        | push handle
    _LoadResource                               | force load from disk
NEWDIALOG_LOCK_ITEMS:
    MOVEA.L     A3,A0                           | A0 = items handle
    _HLock                                      | lock so refs into list are stable
    RTS                                         | return from CLOSEDIALOG_CONT_3
| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_4 -- common Dialog Manager body prologue.
|
| Saves current grafPort to local frame, sets dialog as current port,
| loads + locks item list, locates current edit-field item (if any).
| Returns D1 = 26 (offset to first item entry size word in DITL).
| Called during boot.
CLOSEDIALOG_CONT_4:
    PEA.L       -0x2C(A6)                       | push address to save current port
    _GetPort                                    | save current grafPort
    MOVE.L      A4,-(A7)                        | push dialog as new port
    _SetPort                                    | set dialog as current port
    BSR.B       CLOSEDIALOG_CONT_3              | load+lock item list
    BSR.B       CLOSEDIALOG_CONT_5              | locate current edit field
    BEQ.B       CLOSEDIALOG_SKIP_2              | none -> skip
    BSR.W       DLG_SwitchOrEditField           | record edit field info
CLOSEDIALOG_SKIP_2:
    MOVEQ.L     #0x1A,D1                        | D1 = 26 (first item offset)
    RTS                                         | return from CLOSEDIALOG_CONT_4
| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_5 -- locate current edit-field item in dialog.
|
| If dialog.editField (offset 0xA4) is non-negative, looks up that
| item directly. Otherwise scans for first enabled edit-text item
| (item type bit 4 with non-zero handle). Returns Z=1 if not found.
CLOSEDIALOG_CONT_5:
    MOVE.W      0xA4(A4),D3                     | D3 = dialog.editField
    BMI.B       CLOSEDIALOG_NO                  | not set -> scan items
    BSR.W       DLGMGR_OK_3                     | get item entry by index
    BRA.B       CLOSEDIALOG_FOUND               | -> mark found
CLOSEDIALOG_NO:
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (start from index -1)
CLOSEDIALOG_LOOP:
    BSR.W       DLGMGR_NEXT_4                   | next item
    BEQ.B       CLOSEDIALOG_EXIT                | end of list -> not found
    BTST        #0x4,0xC(A2)                    | bit 4 of itemType (text edit)?
    BEQ.B       CLOSEDIALOG_LOOP                | no -> next
    BSR.W       DLGMGR_OK_2                     | enabled?
    BEQ.B       CLOSEDIALOG_LOOP                | no -> next
CLOSEDIALOG_FOUND:
    MOVEQ.L     #-0x2,D2                        | D2 = -2 (mark "found", Z=0)
CLOSEDIALOG_EXIT:
    RTS                                         | return CCR set by D2 test
| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_6 -- common Dialog Manager body epilogue.
|
| Restores caller's grafPort and unlocks the dialog item list handle.
| Called by: INITDIALOGS_SKIP_2, NEWDIALOG_OK, DIALOGSELECT_NO, DRAWDIALOG, UPDTDIALOG (and 6 more)
CLOSEDIALOG_CONT_6:
    MOVE.L      -0x2C(A6),-(A7)                 | push saved port
    _SetPort                                    | restore caller's grafPort
    MOVEA.L     A3,A0                           | A0 = items handle
    _HUnlock                                    | unlock items handle
    RTS                                         | return from CLOSEDIALOG_CONT_6
| ----------------------------------------------------------
|
| _DisposDialog ($A983) -- dispose dialog including item list and storage.
|
| Closes the dialog (which disposes individual item Pascal strings),
| disposes the item list handle itself, then disposes the dStorage
| pointer if present.
DISPOSDIALOG:
    MOVEA.L     0x4(A7),A0                      | A0 = dialog ptr from stack
    MOVE.L      0x9C(A0),-(A7)                  | push items handle
    MOVE.L      A0,-(A7)                        | push dialog ptr
    _CloseDialog                                | close window, dispose items strings
    MOVEA.L     (A7)+,A0                        | A0 = items handle
    _DisposeHandle                              | dispose items handle
    MOVEA.L     (A7)+,A1                        | A1 = caller's return address
    MOVEA.L     (A7)+,A0                        | A0 = dialog storage (dStorage)
    _DisposePtr                                 | dispose dStorage
    JMP         (A1)                            | tail-call return from DISPOSDIALOG via A1
| ----------------------------------------------------------
|
| DISPOSEDIALOG_CONT -- get DITL ID from DLOG template (offset 0x12).
|
| Called during boot.
DISPOSEDIALOG_CONT:
    MOVEA.L     (A2),A0                         | A0 = deref'd DLOG template
    MOVE.W      0x12(A0),D0                     | D0 = DITL ID at offset 0x12
    BRA.B       DISPOSEDIALOG_CONT_3            | -> common DITL loader
| ----------------------------------------------------------
|
| DISPOSEDIALOG_CONT_2 -- get DITL ID from ALRT template (offset 0x8).
|
DISPOSEDIALOG_CONT_2:
    MOVEA.L     (A2),A0                         | A0 = deref'd ALRT template
    MOVE.W      0x8(A0),D0                      | D0 = DITL ID at offset 0x8
DISPOSEDIALOG_CONT_3:
    SUBQ.W      #0x4,A7                         | space for GetResource result
    MOVE.L      #0x4449544C,-(A7)               | push type = 'DITL'
    MOVE.W      D0,-(A7)                        | push DITL resource ID
DISPOSEDIALOG_EXIT:
    _GetResource                                | load DITL resource
    MOVEA.L     (A7)+,A2                        | A2 = DITL resource handle
    RTS                                         | return from DISPOSEDIALOG_CONT
| ----------------------------------------------------------
|
| _CouldDialog ($A979) -- preload a DLOG resource and its sub-resources.
|
| Stack: dialogID(W). Loads DLOG, makes it non-purgeable, loads its
| DITL, walks items preloading any embedded sub-resources, loads WDEF.
| Used to ensure all dialog resources are in memory (e.g. for alerts
| in low-memory situations).
COULDDIALOG:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    LEA.L       COULDALERT_CONT_3(PC),A2        | A2 = DLOG loader routine
    LEA.L       DISPOSEDIALOG_CONT(PC),A4       | A4 = DITL getter for DLOG
    BRA.B       NEWALERT_LOAD_RES               | -> common preload
| ----------------------------------------------------------
|
| _CouldAlert ($A989) -- preload an ALRT resource and its sub-resources.
COULDALERT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    LEA.L       COULDALERT_CONT_2(PC),A2        | A2 = ALRT loader routine
    LEA.L       DISPOSEDIALOG_CONT_2(PC),A4     | A4 = DITL getter for ALRT
NEWALERT_LOAD_RES:
    MOVE.W      0x8(A6),D0                      | D0 = resource ID
    JSR         (A2)                            | load DLOG/ALRT template
    BEQ.B       FREEALERT_ERR                   | load failed -> skip
    MOVEA.L     A2,A0                           | A0 = template handle
    _HUnlock                                    | unlock the lock done by loader
    _HNoPurge                                   | make non-purgeable
    JSR         (A4)                            | load associated DITL
    MOVEA.L     A2,A0                           | A0 = DITL handle
    _HNoPurge                                   | make DITL non-purgeable
    MOVEA.L     A2,A3                           | A3 = DITL handle
    MOVEQ.L     #-0x2,D4                        | D4 = -2 (preload mode)
    BSR.B       FREEALERT_WALK                  | preload WDEF + sub-resources
    MOVEA.L     A2,A0                           | A0 = WDEF handle
    _HNoPurge                                   | make WDEF non-purgeable
    BRA.B       FREEALERT_ERR                   | -> StdTwoExit
| ----------------------------------------------------------
|
| COULDALERT_CONT_2 -- load ALRT resource template.
|
COULDALERT_CONT_2:
    MOVEA.L     #0x414C5254,A0                  | A0 = 'ALRT' resource type
    BRA.B       COULDALERT_CONT_4               | -> common loader
| ----------------------------------------------------------
|
| COULDALERT_CONT_3 (COULDALERT_CONT_3) -- load DLOG resource template.
COULDALERT_CONT_3:
    MOVEA.L     #0x444C4F47,A0                  | A0 = 'DLOG' resource type
COULDALERT_CONT_4:
    SUBQ.W      #0x4,A7                         | space for GetResource result
    MOVE.L      A0,-(A7)                        | push resource type
    MOVE.W      D0,-(A7)                        | push resource ID
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | enable ROM map fallback
    _GetResource                                | load template resource
    MOVEA.L     (A7),A2                         | A2 = template resource handle
    MOVEA.L     A2,A0                           | A0 = handle for HLock
    _HLock                                      | lock template handle in memory
    MOVEA.L     (A2),A1                         | A1 = deref'd template data
    TST.L       (A7)+                           | set flags from handle (Z=1 if nil)
    RTS                                         | return CCR set by handle test
| ----------------------------------------------------------
|
| _FreeDialog ($A97A) -- mark DLOG resource and sub-resources as purgeable.
|
| Inverse of _CouldDialog: makes the DLOG, DITL, item sub-resources,
| and WDEF purgeable so the Memory Manager can reclaim them.
FREEDIALOG:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    LEA.L       COULDALERT_CONT_3(PC),A2        | A2 = DLOG loader routine
    LEA.L       DISPOSEDIALOG_CONT(PC),A4       | A4 = DITL getter for DLOG
    BRA.B       FREEALERT_CONT                  | -> common free
| ----------------------------------------------------------
|
| _FreeAlert ($A98A) -- mark ALRT resource and sub-resources as purgeable.
FREEALERT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    LEA.L       COULDALERT_CONT_2(PC),A2        | A2 = ALRT loader routine
    LEA.L       DISPOSEDIALOG_CONT_2(PC),A4     | A4 = DITL getter for ALRT
FREEALERT_CONT:
    MOVE.W      0x8(A6),D0                      | D0 = resource ID
    JSR         (A2)                            | load template
    BEQ.B       FREEALERT_ERR                   | not found -> skip
    MOVEA.L     A2,A0                           | A0 = template handle
    _HUnlock                                    | unlock template
    BSR.W       DLGMGR_CONT_8                   | make template purgeable
    JSR         (A4)                            | load associated DITL
    BSR.W       DLGMGR_CONT_8                   | make DITL purgeable
    MOVEA.L     A2,A3                           | A3 = DITL handle
    MOVEQ.L     #-0x1,D4                        | D4 = -1 (free mode)
    BSR.B       FREEALERT_WALK                  | free WDEF + sub-resources
    BSR.W       DLGMGR_CONT_8                   | make WDEF purgeable
FREEALERT_ERR:
    MOVEQ.L     #0x2,D0                         | 2 bytes of params to clean up
FREEALERT_EPILOGUE:
    BRA.W       CLOSEDIALOG_CONT_2              | -> common epilogue
| FREEALERT_WALK (FREEALERT_CONT_3): walk DITL preloading/freeing items + WDEF.
FREEALERT_WALK:
    MOVEA.L     A3,A0                           | A0 = item list handle
    _HLock                                      | lock item list
    BSR.W       FINDDITEM_CONT                  | walk items (preload/free per D4)
    MOVEA.L     A3,A0                           | A0 = item list handle
    _HUnlock                                    | unlock item list
    SUBQ.W      #0x4,A7                         | space for GetResource result
    MOVE.L      #0x57444546,-(A7)               | push type = 'WDEF'
    CLR.W       -(A7)                           | push ID = 0 (standard window def)
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | enable ROM map fallback
    BRA.W       DISPOSEDIALOG_EXIT              | load WDEF and return
| ----------------------------------------------------------
|
| _ParamText ($A98B) -- replace ParamText strings ^0..^3.
|
| Stack: param0(L), param1(L), param2(L), param3(L). Updates the
| four DAStrings slots from caller's parameters. For each non-nil
| param, disposes the old handle, allocates a new handle from the
| string ptr via DLG_NewStringHandle (PtrToHand for Pascal string), stores in
| DAStrings array. nil param leaves slot unchanged.
PARAMTEXT:
    LEA.L       (TEScrpLength).W,A1             | A1 = past end of DAStrings[3]
    MOVEQ.L     #0x3,D2                         | D2 = 3 (process 4 strings ^0..^3)
PARAMTEXT_LOOP:
    MOVE.L      0x4(A7),D1                      | D1 = string ptr param
    MOVEA.L     -(A1),A0                        | A0 = existing handle for slot
    BEQ.B       PARAMTEXT_SKIP                  | nil param -> skip slot
    MOVE.L      A0,D0                           | test existing handle
    BEQ.B       PARAMTEXT_NO                    | no old handle -> just set new
    _DisposeHandle                              | dispose previous string handle
PARAMTEXT_NO:
    MOVEA.L     D1,A0                           | A0 = new string ptr
    BSR.W       DLG_NewStringHandle             | convert Pascal string to handle
    MOVE.L      A0,(A1)                         | DAStrings[i] = new handle
PARAMTEXT_SKIP:
    MOVE.L      (A7)+,(A7)                      | collapse stack: drop 4-byte param
    DBF.W       D2,PARAMTEXT_LOOP               | next string parameter
    RTS                                         | return from ParamText
| ----------------------------------------------------------
|
| _ErrorSound ($A98C) -- install custom beep procedure.
|
| Stack: soundProc(L). Stores caller's procptr in DABeeper. Used by
| ALERT_CONT_6 to play stage-encoded beep sequences.
ERRORSOUND:
    MOVEA.L     (A7)+,A0                        | save return address
    MOVE.L      (A7)+,(DABeeper).W              | DABeeper = caller's procptr
    JMP         (A0)                            | tail-call return from ERRORSOUND via A0
| ----------------------------------------------------------
|
| _GetDItem ($A98D) -- read item info: type, handle, rect.
|
| Stack: theDialog(L), itemNo(W), itemType(L), item(L), box(L).
| Each output pointer (itemType, item, box) may be nil to skip.
GETDITEM:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0x16(A6),A4                     | A4 = dialog ptr
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load items
    MOVE.W      0x14(A6),D3                     | D3 = item number (1-based)
    SUBQ.W      #0x1,D3                         | convert to 0-based
    BSR.W       DLGMGR_OK_3                     | A2 = item entry
    BEQ.B       GETDITEM_RESTORE                | not found -> skip
    MOVE.L      0x8(A6),D0                      | D0 = caller's box ptr
    BEQ.B       GETDITEM_EMPTY                  | nil -> skip
    LEA.L       0x4(A2),A0                      | A0 = item.bounds (offset 4)
    MOVEA.L     D0,A1                           | A1 = caller's rect ptr
    MOVE.L      (A0)+,(A1)+                     | copy top-left
    MOVE.L      (A0)+,(A1)+                     | copy bottom-right
GETDITEM_EMPTY:
    MOVEA.L     0x10(A6),A0                     | A0 = caller's itemType ptr
    MOVEQ.L     #0x0,D0                         | clear high bytes
    MOVE.B      0xC(A2),D0                      | D0 = item.type byte
    MOVE.W      D0,(A0)                         | *itemType = D0 (word)
    MOVE.L      (A2),D5                         | D5 = item handle/proc ptr
    MOVEA.L     0xC(A6),A0                      | A0 = caller's item handle ptr
    MOVE.L      D5,(A0)                         | *item = D5
GETDITEM_RESTORE:
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, unlock items
    MOVEQ.L     #0x12,D0                        | 18 bytes of params
GETDITEM_STRIP18:
    BRA.W       FREEALERT_EPILOGUE              | -> common epilogue
| ----------------------------------------------------------
|
| _SetDItem ($A98E) -- write item info: type, handle, rect.
|
| Stack: theDialog(L), itemNo(W), itemType(B), item(L), box(L).
SETDITEM:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0x14(A6),A4                     | A4 = dialog ptr
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load items
    MOVE.W      0x12(A6),D3                     | D3 = item number (1-based)
    SUBQ.W      #0x1,D3                         | convert to 0-based
    BSR.W       DLGMGR_OK_3                     | A2 = item entry
    BEQ.B       SETDITEM_RESTORE                | not found -> skip
    MOVEA.L     0x8(A6),A0                      | A0 = new bounds ptr
    LEA.L       0x4(A2),A1                      | A1 = item.bounds
    MOVE.L      (A0)+,(A1)+                     | copy top-left
    MOVE.L      (A0)+,(A1)+                     | copy bottom-right
    MOVE.L      0xC(A6),(A2)                    | item.handle = caller's
    MOVE.B      0x11(A6),0xC(A2)                | item.type = caller's byte
SETDITEM_RESTORE:
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, unlock items
    MOVEQ.L     #0x10,D0                        | 16 bytes of params
SETDITEM_CONT:
    BRA.B       GETDITEM_STRIP18                | -> common epilogue
| ----------------------------------------------------------
|
| _GetIText ($A990) -- read text from EditText/StaticText item.
|
| Stack: theItem(L), text(L). Reads the handle's contents and copies
| into caller's Pascal string buffer (clamped to 255 chars).
GETITEXT:
    MOVEQ.L     #0x0,D1                         | D1 = 0
    SUBQ.B      #0x1,D1                         | D1 = 0xFF (max Pascal len)
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0x8(A6),A1                      | A1 = caller's text dest
    MOVEA.L     0xC(A6),A0                      | A0 = item's text handle
    _GetHandleSize                              | D0 = text length
    CMP.L       D1,D0                           | clamp to 255 max
    BLE.B       GETITEXT_OK                     | under 255 -> use as-is
    MOVE.L      D1,D0                           | cap at 255
GETITEXT_OK:
    MOVE.B      D0,(A1)+                        | store length byte
    MOVEA.L     (A0),A0                         | A0 = deref'd text data
    _BlockMove                                  | copy text to dest
    BRA.B       SETITEXT_CONT                   | -> StdEightExit
| ----------------------------------------------------------
|
| _SetIText ($A98F) -- replace text of EditText/StaticText item.
|
| Stack: theItem(L), text(L). Replaces the handle's contents with
| the new Pascal string via _PtrToXHand. Walks all dialog windows
| looking for items that share this text handle; redraws them and
| recalcs TE if they're the active edit field.
SETITEXT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0x8(A6),A0                      | A0 = Pascal string source
    MOVEQ.L     #0x0,D0                         | clear high bytes
    MOVE.B      (A0)+,D0                        | D0 = string length, A0 = data
    MOVEA.L     0xC(A6),A1                      | A1 = text handle to replace
    MOVE.L      A1,D6                           | D6 = handle (saved for matching)
    _PtrToXHand                                 | replace handle contents
    MOVEA.L     (WindowList).W,A4               | A4 = first window in list
SETITEXT_NEXT:
    CMPI.W      #0x2,0x6C(A4)                   | windowKind = 2 (dialog)?
    BNE.B       SETITEXT_SKIP                   | no -> next window
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load items
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (start from beginning)
SETITEXT_WALK:
    BSR.W       DLGMGR_NEXT_4                   | advance to next item
    BEQ.B       SETITEXT_CLOSE                  | none -> done with this dialog
    CMP.L       (A2),D6                         | item uses same text handle?
    BNE.B       SETITEXT_WALK                   | no -> next item
    CMP.W       0xA4(A4),D3                     | this is the active edit field?
    BNE.B       SETITEXT_NO                     | no -> just redraw
    MOVE.L      0xA0(A4),-(A7)                  | push TE handle
    _TECalText                                  | recalculate text layout
SETITEXT_NO:
    TST.B       0x6E(A4)                        | window visible?
    BEQ.B       SETITEXT_CLOSE                  | no -> skip redraw
    PEA.L       -0x28(A6)                       | push item bounds rect
    MOVE.L      (A7),-(A7)                      | duplicate rect ref for ValidRect
    _EraseRect                                  | erase item area
    BSR.W       DLGMGR_CONT_17                  | redraw text item
    _ValidRect                                  | mark rect as valid (no update)
SETITEXT_CLOSE:
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, unlock items
SETITEXT_SKIP:
    MOVEA.L     0x90(A4),A4                     | A4 = next window in list
    MOVE.L      A4,D0                           | more windows?
    BNE.B       SETITEXT_NEXT                   | yes -> loop
SETITEXT_CONT:
    MOVEQ.L     #0x8,D0                         | 8 bytes of params to clean up
SETITEXT_CONT_2:
    BRA.W       SETDITEM_CONT                   | -> common epilogue
| ----------------------------------------------------------
|
| _SelIText ($A97E) -- select text range in EditText item.
|
| Stack: theDialog(L), itemNo(W), selStart(W), selEnd(W). Calls
| DLG_SwitchActiveField to activate text edit and select the specified range.
SELITEXT:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0xE(A6),A4                      | A4 = dialog ptr
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load items
    MOVE.W      0xC(A6),D3                      | D3 = item number (1-based)
    SUBQ.W      #0x1,D3                         | convert to 0-based
    BSR.W       DLGMGR_OK_3                     | A2 = item entry
    MOVE.L      0x8(A6),D2                      | D2 = selStart..selEnd (long)
    SWAP.W      D2                              | D2 high = selEnd, low = selStart
    BSR.W       DLG_SwitchActiveField           | activate edit + select range
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, unlock items
    MOVEQ.L     #0xA,D0                         | 10 bytes of params
    BRA.B       SETITEXT_CONT_2                 | -> common epilogue
| SELITEXT_CONT -- compute inset rect on stack.
| ----------------------------------------------------------
|
| SELITEXT_CONT
|
| ----------------------------------------------------------
|
| SELITEXT_CONT -- compute item display rect (with type-specific inset).
|
| For editText items: -3 inset (expand rect by 3 pixels for caret).
| For default button: -4 inset (expand for bold outline).
| For others: 0 inset (use rect as-is).
| Pushes the inset rect on the stack and returns.
SELITEXT_CONT:
    MOVEQ.L     #-0x3,D7                        | D7 = -3 (editText inset)
    MOVE.B      0xC(A2),D1                      | D1 = item type byte
    BTST        #0x4,D1                         | editText flag (bit 4)?
    BNE.B       SELITEXT_OK                     | yes -> use -3 inset
    MOVEQ.L     #-0x4,D7                        | D7 = -4 (default button inset)
    MOVE.W      0xA8(A4),D0                     | D0 = aDefItem
    SUBQ.W      #0x1,D0                         | convert to 0-based
    CMP.W       D0,D3                           | this is the default item?
    BEQ.B       SELITEXT_OK                     | yes -> use -4 inset
    MOVEQ.L     #0x0,D7                         | else 0 inset (no special)
SELITEXT_OK:
    MOVEA.L     (A7)+,A0                        | pop return address
    MOVE.L      0x8(A2),-(A7)                   | push bottom-right of item rect
    MOVE.L      0x4(A2),-(A7)                   | push top-left of item rect
    MOVE.L      A0,-(A7)                        | push return address back
    PEA.L       0x4(A7)                         | push ptr to rect on stack
    MOVE.W      D7,-(A7)                        | push vertical inset
    MOVE.W      D7,-(A7)                        | push horizontal inset
    _InsetRect                                  | shrink/expand rect
    RTS                                         | return from SELITEXT_CONT
| ----------------------------------------------------------
|
| _HideDItem ($A827) -- hide a dialog item by moving it offscreen.
|
| Stack: theDialog(L), itemNo(W). Adds 0x4000 to item's left and
| right coords (moves to "hidden" range >= 0x2000). Erases visible
| area, deactivates edit field if active, MoveControl if it has one.
HIDEDITEM:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0xA(A6),A4                      | A4 = dialog ptr
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load items
    MOVE.W      0x8(A6),D3                      | D3 = item number (1-based)
    SUBQ.W      #0x1,D3                         | convert to 0-based
    BSR.W       DLGMGR_OK_3                     | A2 = item entry
    BEQ.B       HIDEDITEM_RESTORE               | not found -> skip
    MOVE.W      0x6(A2),D0                      | D0 = item rect.left
    CMPI.W      #0x2000,D0                      | already hidden (>= 0x2000)?
    BLT.B       HIDEDITEM_NO                    | no -> proceed to hide
HIDEDITEM_RESTORE:
    BSR.W       CLOSEDIALOG_CONT_6              | restore port, unlock items
    MOVEQ.L     #0x6,D0                         | 6 bytes of params
    BRA.W       SETITEXT_CONT_2                 | -> common epilogue
HIDEDITEM_NO:
    BSR.B       SELITEXT_CONT                   | compute display rect on stack
    CMP.W       0xA4(A4),D3                     | this is active edit field?
    BNE.B       HIDEDITEM_SKIP                  | no -> skip deactivate
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (deactivate)
    BSR.W       DLG_SwitchActiveField           | deselect text + reset editField
HIDEDITEM_SKIP:
    MOVE.L      A7,-(A7)                        | push ptr to rect on stack
    _EraseRect                                  | erase item's visible area
    ADDI.W      #0x4000,0x6(A2)                 | left += 0x4000 (offscreen)
    ADDI.W      #0x4000,0xA(A2)                 | right += 0x4000 (offscreen)
    BSR.B       SHOWDITEM_CONT                  | item has a control?
    BEQ.B       HIDEDITEM_EXIT_2                | no -> skip MoveControl
    MOVE.L      (A2),-(A7)                      | push control handle
    MOVE.L      0x4(A2),-(A7)                   | push new top-left
    _MoveControl                                | move control offscreen
HIDEDITEM_EXIT_2:
    MOVE.L      A7,-(A7)                        | push ptr to rect
    _InvalRect                                  | invalidate old area
    ADDQ.W      #0x8,A7                         | discard rect
HIDEDITEM_SKIP_2:
    BRA.B       HIDEDITEM_RESTORE               | -> exit
| ----------------------------------------------------------
|
| _ShowDItem ($A828) -- show a hidden dialog item.
|
| Stack: theDialog(L), itemNo(W). Subtracts 0x4000 from coords to
| bring item back onscreen. MoveControl with visible flag temporarily
| cleared (to avoid double-redraw), then restores visible flag.
SHOWDITEM:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0xA(A6),A4                      | A4 = dialog ptr
    BSR.W       CLOSEDIALOG_CONT_4              | set port, load items
    MOVE.W      0x8(A6),D3                      | D3 = item number (1-based)
    SUBQ.W      #0x1,D3                         | convert to 0-based
    BSR.W       DLGMGR_OK_3                     | A2 = item entry
    BEQ.B       HIDEDITEM_SKIP_2                | not found -> skip
    MOVE.W      0x6(A2),D0                      | D0 = item rect.left
    CMPI.W      #0x2000,D0                      | item is hidden (>= 0x2000)?
    BLT.B       HIDEDITEM_SKIP_2                | no -> already visible, skip
    SUBI.W      #0x4000,0x6(A2)                 | left -= 0x4000 (back onscreen)
    SUBI.W      #0x4000,0xA(A2)                 | right -= 0x4000
    BSR.W       SELITEXT_CONT                   | compute display rect on stack
    BSR.B       SHOWDITEM_CONT                  | item has a control?
    BEQ.B       SHOWDITEM_SKIP                  | no -> skip MoveControl
    MOVEA.L     (A2),A0                         | A0 = control handle
    MOVEA.L     (A0),A1                         | A1 = deref'd control record
    MOVE.B      0x10(A1),-(A7)                  | save control's visible flag
    CLR.B       0x10(A1)                        | hide control (prevent redraw)
    MOVE.L      A0,-(A7)                        | push control handle
    MOVE.L      0x4(A2),-(A7)                   | push restored position
    _MoveControl                                | move control back onscreen
    MOVEA.L     (A2),A0                         | reload control handle
    MOVEA.L     (A0),A1                         | re-deref (may have moved)
    MOVE.B      (A7)+,0x10(A1)                  | restore control's visible flag
SHOWDITEM_SKIP:
    BRA.B       HIDEDITEM_EXIT_2                | -> InvalRect + exit
| ----------------------------------------------------------
|
| SHOWDITEM_CONT -- check if item has a control (returns Z=0 if so).
|
| If dialog has no active edit field, scans for an editText item to
| auto-activate. Then tests if current item's type byte has bit 2
| (ctrlItem). Returns CCR set by BTST.
SHOWDITEM_CONT:
    TST.W       0xA4(A4)                        | dialog has active edit field?
    BPL.B       SHOWDITEM_SKIP_3                | yes -> skip TE auto-activate
    MOVE.L      A2,-(A7)                        | save current item ptr
    BSR.W       CLOSEDIALOG_CONT_5              | search for editText item
    BEQ.B       SHOWDITEM_SKIP_2                | none found -> skip
    MOVEQ.L     #0x0,D2                         | D2 = 0 (select all)
    BSR.W       DLG_SwitchActiveField           | activate text edit
SHOWDITEM_SKIP_2:
    MOVEA.L     (A7)+,A2                        | restore item ptr
SHOWDITEM_SKIP_3:
    MOVE.B      0xC(A2),D1                      | D1 = item type byte
    BTST        #0x2,D1                         | ctrlItem flag (bit 2)?
    RTS                                         | Z=0 if control, Z=1 if not
| ----------------------------------------------------------
|
| _FindDItem ($A984) -- find dialog item containing a point.
|
| Stack: theDialog(L), pt(L) -> itemIndex(W). Walks all items
| testing _PtInRect against the point. Returns 0-based item index
| or -1 if not in any item.
FINDDITEM:
    BSR.W       MODALDIALOG_CONT_3              | dialog prologue
    MOVEA.L     0xC(A6),A4                      | A4 = dialog ptr
    BSR.W       CLOSEDIALOG_CONT_3              | load+lock item list
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (start from beginning)
    MOVE.W      D3,0x10(A6)                     | preset result = -1 (not found)
FINDDITEM_WALK:
    BSR.W       DLGMGR_NEXT_4                   | advance to next item
    BEQ.B       FINDDITEM_UNLOCK                | none -> done
    SUBQ.W      #0x2,A7                         | space for PtInRect result
    MOVE.L      0x8(A6),-(A7)                   | push test point
    PEA.L       -0x28(A6)                       | push item bounds rect
    _PtInRect                                   | test pt in rect
    TST.B       (A7)+                           | hit?
    BEQ.B       FINDDITEM_WALK                  | no -> next item
    MOVE.W      D3,0x10(A6)                     | yes -> store 0-based index
FINDDITEM_UNLOCK:
    MOVEA.L     A3,A0                           | A0 = items handle
    _HUnlock                                    | unlock items
    BRA.W       SETITEXT_CONT                   | -> StdEightExit
| ----------------------------------------------------------
|
| FINDDITEM_CONT (FINDDITEM_CONT) -- iterate every item in dialog.
|
| Walks the entire item list, calling ENTRY for each item with D4
| selecting the operation: D4=0 init, 1 draw, 2 hit-test, 3 update,
| -1 free sub-resources, -2 preload sub-resources.
| Called by: NEWDIALOG_OK, DRAWDIALOG, UPDTDIALOG, CLOSEDIALOG, FREEALERT_WALK
FINDDITEM_CONT:
    MOVEM.L     D0-D7/A0-A4,-(A7)               | save all working regs
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (start from beginning)
FINDDITEM_INNER_LOOP:
    BSR.W       DLGMGR_NEXT_4                   | advance to next item
    BNE.B       ENTRY                           | found -> dispatch by type
    MOVEM.L     (A7)+,D0-D7/A0-A4               | restore working regs
    RTS                                         | return from FINDDITEM_CONT
| ----------------------------------------------------------
|
| FINDDITEM_CONT_2 -- get item handle and type from item entry.
|
| Returns A0 = item handle/proc, D0 = item type byte.
| Called during boot.
FINDDITEM_CONT_2:
    MOVEA.L     (A2),A0                         | A0 = item handle/proc ptr
    MOVE.B      0xC(A2),D0                      | D0 = item type byte
    RTS                                         | return from FINDDITEM_CONT_2
| Dialog Manager - Internal Routines
|
| Contains the internal subroutines called by the Dialog Manager's
| public traps (in resource_mgr.s): item initialization from DITL,
| item drawing/disposal, event dispatch, edit field switching,
| hit testing, ParamText substitution, and default button outlining.
|
| Also contains unrelated utility traps that share this ROM region:
| _Munger, _HandToHand, _PtrToXHand, _PtrToHand, _HandAndHand,
| _PtrAndHand, fixed-point math (LongMul, FixMul, FixDiv, FixRatio,
| FixRound, HiWord, LoWord), and MacApp dispatch (StdOpcodeProc).
|
| Key registers used throughout Dialog Manager routines:
| A4 = DialogPtr (pointer to DialogRecord)
| A3 = items handle (DITL resource, from DialogRecord+0x9C)
| A2 = pointer to current item entry within DITL data
| D3 = current item index (0-based; -1 = none/done)
| A6 frame: -0x28(A6) = item display rect (8 bytes)
| -0x4C(A6) = EventRecord copy (for ModalDialog/DialogSelect)
| -0x1C(A6) = local mouse point
|
| DITL item entry layout (variable-length, word-aligned):
| +0: handle/procPtr (4 bytes) - control handle, text handle, or userItem proc
| +4: display rect (8 bytes) - item bounding rectangle
| +12: item type (1 byte) - see ctrlItem/statText/editText/iconItem/picItem
| +13: data length (1 byte) followed by data (padded to even)
|
| References:
| Inside Macintosh Vol I, pp 399-430: The Dialog Manager

| ============================================================
| DITL Item Initialization - called from FINDDITEM_CONT loop in resource_mgr.s
| Decodes item type and loads/creates the appropriate resource or control.
| Entry: A2 = ptr to DITL item entry, D4 = mode (0=init, 1=draw, 2=hitTest)
| A4 = DialogPtr, D0 = item type byte from itmType(A2)
| ============================================================
ENTRY:
    BSR.B       FINDDITEM_CONT_2                | A0 = item handle/proc, D0 = type
    PEA.L       FINDDITEM_INNER_LOOP(PC)        | push iteration continue addr
    CMPI.W      #0x2,D4                         | mode 2 (hit-test)?
    BGT.W       DLGMGR_FOUND                    | > 2 -> draw/update modes
    BEQ.W       DLGMGR_CONT_24                  | == 2 -> hit-test path
    TST.W       D4                              | mode 0 (init)?
    BEQ.B       DLGMGR_CONT_9                   | yes -> init from DITL data
    BGT.W       DLGMGR_CONT_17                  | mode 1 (draw)
    BTST        #0x2,D0                         | mode -1/-2: ctrlItem flag?
    BNE.B       DLGMGR_CONT                     | yes -> control path
    ROXR.W      #0x7,D0                         | rotate D0 to expose iconItem/picItem bits
    BMI.B       DLGMGR_CONT_4                   | iconItem -> load ICON
    BCS.B       DLGMGR_CONT_5                   | picItem -> load PICT
    RTS                                         | other types: nothing to do
| ----------------------------------------------------------
| DLGMGR_CONT - load resource handle for a control item (ctrlItem).
| Determines CNTL vs CDEF resource type from control subtype bits.
| ----------------------------------------------------------
DLGMGR_CONT:
    ANDI.W      #0x3,D0                         | mask to subtype bits 0-1
    CMPI.W      #0x3,D0                         | resCtrl (subtype 3)?
    BNE.B       DLGMGR_CONT_3                   | no -> CDEF only
    PEA.L       DLGMGR_CONT_2(PC)               | push CNTL post-load callback
    MOVE.L      #0x434E544C,D1                  | D1 = 'CNTL' resource type
    BRA.B       DLGMGR_CONT_6                   | -> load
| ----------------------------------------------------------
| DLGMGR_CONT_2 - callback for resCtrl: extract CDEF proc ID from CNTL.
| ----------------------------------------------------------
DLGMGR_CONT_2:
    MOVEA.L     (A2),A1                         | A1 = deref'd CNTL resource
    MOVE.W      0x10(A1),D0                     | D0 = procID from CNTL data
DLGMGR_CONT_3:
    MOVE.L      #0x43444546,D1                  | D1 = 'CDEF' resource type
    BRA.B       DLGMGR_CONT_7                   | -> load by D1 type, D0 ID
| ----------------------------------------------------------
| DLGMGR_CONT_4 - load ICON resource for an iconItem.
| ----------------------------------------------------------
DLGMGR_CONT_4:
    MOVE.L      #0x49434F4E,D1                  | D1 = 'ICON' resource type
    BRA.B       DLGMGR_CONT_6                   | -> load
| ----------------------------------------------------------
| DLGMGR_CONT_5 - load PICT resource for a picItem.
| ----------------------------------------------------------
DLGMGR_CONT_5:
    MOVE.L      #0x50494354,D1                  | D1 = 'PICT' resource type
DLGMGR_CONT_6:
    MOVE.W      0xE(A2),D0                      | D0 = resource ID from item data
DLGMGR_CONT_7:
    SUBQ.W      #0x4,A7                         | space for GetResource result
    MOVE.L      D1,-(A7)                        | push resource type
    MOVE.W      D0,-(A7)                        | push resource ID
    _GetResource                                | load resource
    MOVEA.L     (A7)+,A2                        | A2 = handle
    CMPI.W      #0xFFFF,D4                      | mode == -1 (free)?
    BEQ.B       DLGMGR_CONT_8                   | yes -> make purgeable
    MOVEA.L     A2,A0                           | A0 = handle
    _HNoPurge                                   | mode -2: make non-purgeable
    RTS                                         | return from DLGMGR_CONT_7
| DLGMGR_CONT_8: if resource is locked, make it purgeable; else no-op.
DLGMGR_CONT_8:
    SUBQ.W      #0x2,A7                         | space for GetResAttrs result
    MOVE.L      A2,-(A7)                        | push resource handle
    _GetResAttrs                                | D0 = attribute byte
    MOVE.W      (A7)+,D0                        | pop result
    BTST        #0x5,D0                         | resPurgeable bit set?
    BEQ.B       DLGMGR_NO                       | no -> skip
    MOVEA.L     A2,A0                           | A0 = handle
    _HPurge                                     | make purgeable
DLGMGR_NO:
    RTS                                         | return from DLGMGR_CONT_8
| ----------------------------------------------------------
| Initialize item from DITL data (D4=0)
| A0 = item handle from DITL entry, D0 = item type byte
| If handle already set (non-nil), item was pre-initialized - skip.
| ----------------------------------------------------------
DLGMGR_CONT_9:
    MOVE.L      A0,D1                           | test if item handle already exists
    BEQ.B       DLGMGR_EMPTY                    | nil: need to create from DITL data
    RTS                                         | already initialized, nothing to do
| ----------------------------------------------------------
| Create item handle/control from DITL data based on item type.
| Dispatches by testing type bits: ctrlItem, iconItem, picItem,
| statText/editText.
| ----------------------------------------------------------
DLGMGR_EMPTY:
    BTST        #0x2,D0                         | test ctrlItem bit
    BNE.B       DLGMGR_CONT_14                  | ctrlItem: create control
    ROXR.W      #0x5,D0                         | shift statText (bit 3) into X/C flags
    BCS.B       DLGMGR_CONT_10                  | statText: copy text data to handle
    BMI.B       DLGMGR_CONT_10                  | editText: copy text data to handle
    ROXR.W      #0x2,D0                         | shift iconItem/picItem bits
    BMI.B       DLGMGR_CONT_11                  | iconItem: load ICON resource
    BCS.B       DLGMGR_CONT_12                  | picItem: load PICT resource
    RTS                                         | userItem: handle stays nil
| ----------------------------------------------------------
| Initialize statText or editText: copy inline text from DITL to a handle
| DITL item data: length byte at +13(A2), text bytes follow
| ----------------------------------------------------------
DLGMGR_CONT_10:
    LEA.L       0xD(A2),A0                      | point to data length byte in DITL entry
    MOVEQ.L     #0x0,D0                         | clear upper bytes of length register
    MOVE.B      (A0)+,D0                        | D0 = text length, A0 -> text data
    _PtrToHand                                  | create handle with copy of text
    MOVE.L      A0,-(A7)                        | push text handle (result in A0)
    BRA.B       DLGMGR_CONT_16                  | store handle in item entry
| ----------------------------------------------------------
| Initialize iconItem: load ICON resource by ID from DITL data
| ----------------------------------------------------------
DLGMGR_CONT_11:
    MOVE.L      #0x49434F4E,D0                  | 'ICON' resource type
    BRA.B       DLGMGR_CONT_13                  | go load 'ICON' resource
| ----------------------------------------------------------
| Initialize picItem: load PICT resource by ID from DITL data
| ----------------------------------------------------------
DLGMGR_CONT_12:
    MOVE.L      #0x50494354,D0                  | 'PICT' resource type
DLGMGR_CONT_13:
    SUBQ.W      #0x4,A7                         | space for GetResource handle result
    MOVE.L      D0,-(A7)                        | push resource type
    MOVE.W      0xE(A2),-(A7)                   | push resource ID from DITL item data
    _GetResource                                | load the 'ICON' or 'PICT' resource
    BRA.B       DLGMGR_CONT_16                  | store resource handle in item entry
| ----------------------------------------------------------
| Initialize ctrlItem: create control from resource or inline data.
| D0 bits 0-1 = subtype: btnCtrl(0), chkCtrl(1), radCtrl(2), resCtrl(3)
| ----------------------------------------------------------
DLGMGR_CONT_14:
    ANDI.W      #0x3,D0                         | isolate control subtype
    CMPI.W      #0x3,D0                         | resCtrl?
    BNE.B       DLGMGR_NO_2                     | no: create standard btn/chk/rad control
    SUBQ.W      #0x4,A7                         | space for GetNewControl result
    MOVE.W      0xE(A2),-(A7)                   | push CNTL resource ID from DITL data
    MOVE.L      A4,-(A7)                        | push owning dialog window
    _GetNewControl                              | create control from CNTL resource
    MOVE.L      (A7),-(A7)                      | push control handle for MoveControl
    MOVE.L      0x4(A2),-(A7)                   | push display rect top-left from DITL
    _MoveControl                                | position control at item's display rect
    BRA.B       DLGMGR_CONT_15                  | go store control handle and validate
| ----------------------------------------------------------
| Create standard button/checkbox/radio control from DITL inline data.
| Builds NewControl params: owner, rect, title, visible, value=1,
| min=0, procID=subtype*16, refCon=0.
| ----------------------------------------------------------
DLGMGR_NO_2:
    SUBQ.W      #0x4,A7                         | space for NewControl result
    MOVE.L      A4,-(A7)                        | push owning window (DialogPtr)
    PEA.L       -0x28(A6)                       | push item display rect
    PEA.L       0xD(A2)                         | push title string (from DITL item data)
    ST.B        -(A7)                           | visible = true ($FF)
    CLR.L       -(A7)                           | value = 0, min = 0
    MOVE.W      #0x1,-(A7)                      | max = 1
    MOVE.W      D0,-(A7)                        | procID = subtype (0=pushBut,1=chkBox,2=radio)
    CLR.L       -(A7)                           | refCon = 0
    _NewControl                                 | create standard system control
DLGMGR_CONT_15:
    PEA.L       -0x28(A6)                       | validate item rect (no redraw needed)
    _ValidRect                                  | validate the item's display rect
DLGMGR_CONT_16:
    MOVE.L      (A7)+,(A2)                      | store new handle into itmHndl field
    RTS                                         | return from item initialization
| ----------------------------------------------------------
| Hit test: check if item rect intersects update region (D4>2)
| Builds a temp rect from item's display rect, insets by -4 pixels
| (to include the 3-pixel frame around editText items), then tests
| intersection with the update region passed in 0x8(A6).
| Returns via BNE to DLGMGR_CONT_18 (which falls into DLGMGR_CONT_17 to draw item).
| ----------------------------------------------------------
DLGMGR_FOUND:
    MOVE.L      0x8(A2),-(A7)                   | push item rect bottom-right
    MOVE.L      0x4(A2),-(A7)                   | push item rect top-left
    MOVE.L      A7,-(A7)                        | push ptr to temp rect on stack
    MOVE.L      #0xFFFCFFFC,-(A7)               | inset by (-4,-4) to include frame
    _InsetRect                                  | inset temp rect to include focus frame
    SUBQ.W      #0x2,A7                         | space for RectInRgn boolean result
    PEA.L       0x2(A7)                         | push ptr to temp rect
    MOVE.L      0x8(A6),-(A7)                   | push update region handle
    _RectInRgn                                  | does item rect intersect update rgn?
    TST.B       (A7)+                           | check RectInRgn boolean result
    ADDQ.W      #0x8,A7                         | clean up temp rect from stack
    BNE.B       DLGMGR_CONT_18                  | intersects: go draw this item
    RTS                                         | no intersection: skip this item
| ----------------------------------------------------------
| DLGMGR_CONT_17 (DLGMGR_CONT_17) - Draw a single dialog item (D4=1)
| Dispatches by item type to draw controls, text, icons, pictures,
| or call userItem drawing procedure.
| ----------------------------------------------------------
DLGMGR_CONT_17:
    BSR.W       FINDDITEM_CONT_2                | get item handle (A0) and type (D0)
    ANDI.B      #0x7F,D0                        | strip itemDisable bit
    BEQ.B       DLGMGR_CONT_19                  | userItem (type 0): call drawing proc
    BSR.W       DLGMGR_CONT_34                  | check if item rect intersects portRect
    BEQ.B       DLGMGR_SKIP                     | not visible: skip drawing
DLGMGR_CONT_18:
    BSR.W       FINDDITEM_CONT_2                | re-fetch handle and type for drawing
    BTST        #0x2,D0                         | ctrlItem?
    BNE.B       DLGMGR_SKIP_2                   | controls drawn by DrawControls, skip here
    ROXR.W      #0x5,D0                         | shift statText/editText bits into flags
    BCS.B       DLGMGR_CONT_22                  | statText: draw text item
    BMI.B       DLGMGR_CONT_22                  | editText: draw text item
    ROXR.W      #0x2,D0                         | shift iconItem/picItem bits
    BMI.B       DLGMGR_CONT_20                  | iconItem: PlotIcon
    BCS.B       DLGMGR_CONT_21                  | picItem: DrawPicture
DLGMGR_CONT_19:
    MOVE.L      (A2),D0                         | get userItem's drawing proc pointer
    BEQ.B       DLGMGR_SKIP                     | nil proc: nothing to draw
    MOVE.L      A4,-(A7)                        | push DialogPtr as 1st param
    MOVE.W      D3,-(A7)                        | push 0-based item number
    ADDQ.W      #0x1,(A7)                       | push 1-based item number as 2nd param
    MOVEA.L     D0,A0                           | A0 = userItem drawing proc pointer
    JSR         (A0)                            | call userItem drawing procedure
DLGMGR_SKIP:
    RTS                                         | return from userItem drawing
| ----------------------------------------------------------
| Draw iconItem: load and plot icon in item's display rect
| ----------------------------------------------------------
DLGMGR_CONT_20:
    PEA.L       -0x28(A6)                       | push item display rect
    MOVE.L      (A2),-(A7)                      | push icon handle
    MOVE.L      (A7),-(A7)                      | dup handle for LoadResource
    _LoadResource                               | ensure icon data is in memory
    _PlotIcon                                   | draw icon in display rect
    RTS                                         | return from icon drawing
| ----------------------------------------------------------
| Draw picItem: load and draw picture in item's display rect
| ----------------------------------------------------------
DLGMGR_CONT_21:
    MOVE.L      (A2),-(A7)                      | push picture handle
    MOVE.L      (A7),-(A7)                      | dup handle for LoadResource
    _LoadResource                               | ensure picture data is in memory
    PEA.L       -0x28(A6)                       | push item display rect
    _DrawPicture                                | draw picture scaled to display rect
DLGMGR_SKIP_2:
    RTS                                         | return from picture drawing
| ----------------------------------------------------------
| Draw statText or editText item.
| If this is the active editText field, erase and TEUpdate.
| Otherwise, perform ParamText substitution (^0..^3) then TETextBox.
| After drawing, if editText, draw 3-pixel frame around display rect.
| ----------------------------------------------------------
DLGMGR_CONT_22:
    SMI.B       D6                              | D6 = $FF if editText (bit 4 set), 0 if statText
    CMP.W       0xA4(A4),D3                     | is this the active edit field?
    BNE.B       DLGMGR_NO_3                     | no: draw with ParamText substitution
    PEA.L       -0x28(A6)                       | push display rect
    MOVE.L      (A7),-(A7)                      | dup for EraseRect
    _EraseRect                                  | clear the edit field area
    MOVE.L      0xA0(A4),-(A7)                  | push TEHandle (teHandle field)
    _TEUpdate                                   | redraw active TextEdit content
DLGMGR_CONT_23:
    TST.B       D6                              | was this an editText item?
    BNE.B       DLGMGR_SKIP_3                   | no (statText): skip frame drawing
    LEA.L       -0x28(A6),A0                    | point to item display rect
    MOVEQ.L     #0x1,D0                         | pen width = 1 (for non-default editText frame)
    MOVEQ.L     #0x1,D1                         | pen height = 1
    MOVEQ.L     #0x3,D2                         | inset = 3 pixels outside
    BSR.W       DLG_FrameRoundOuter             | draw frame rect around editText item
DLGMGR_SKIP_3:
    RTS                                         | return from editText frame drawing
| ----------------------------------------------------------
| Draw statText/editText with ParamText (^0..^3) substitution.
| Makes a copy of the text handle, scans for '^' markers,
| substitutes from DAStrings[0..3], then draws via TETextBox.
| ----------------------------------------------------------
DLGMGR_NO_3:
    MOVEM.L     D2-D6/A2-A4,-(A7)               | save regs (we reuse A2-A4, D2-D6)
    MOVEA.L     (A2),A0                         | get text handle
    _HandToHand                                 | make working copy (A0 = new handle)
    MOVEA.L     A0,A2                           | A2 = working text handle
    MOVEQ.L     #0x0,D3                         | D3 = scan offset into text
DLGMGR_EMPTY_2:
    MOVEA.L     A2,A0                           | get handle for size check
    _GetHandleSize                              | D0 = total text length
    MOVEA.L     (A0),A4                         | A4 = dereferenced text pointer
    ADDA.L      D3,A4                           | advance to current scan position
    MOVE.L      D0,D5                           | D5 = remaining bytes to scan
    SUB.L       D3,D5                           | subtract current offset for remaining bytes
    BRA.B       DLGMGR_LOOP_2                   | enter scan loop
| ----------------------------------------------------------
| Scan for '^' (0x5E) character - ParamText substitution marker.
| Text format: ^0, ^1, ^2, ^3 replaced by DAStrings[0..3].
| ----------------------------------------------------------
DLGMGR_LOOP:
    CMPI.B      #0x5E,(A4)+                     | is this char '^'?
    BEQ.B       DLGMGR_FOUND_2                  | found: go substitute
DLGMGR_SKIP_4:
    ADDQ.W      #0x1,D3                         | advance scan offset
DLGMGR_LOOP_2:
    DBF.W       D5,DLGMGR_LOOP                  | continue scanning
    MOVEA.L     A2,A0                           | lock the text handle before drawing
    _HLock                                      | lock the working text handle
    MOVE.L      (A2),-(A7)                      | push text pointer
    MOVEA.L     A2,A0                           | A0 = substituted text handle
    _GetHandleSize                              | get length of substituted text
    MOVE.L      D0,-(A7)                        | push text length
    PEA.L       -0x28(A6)                       | push display rect
    CLR.W       -(A7)                           | justification = teJustLeft (0)
    _TETextBox                                  | draw substituted text in rect
    MOVEA.L     A2,A0                           | A0 = working text handle to dispose
    _DisposeHandle                              | free working copy
    MOVEM.L     (A7)+,D2-D6/A2-A4               | restore regs
    BRA.B       DLGMGR_CONT_23                  | go draw editText frame if needed
| ----------------------------------------------------------
| Found '^' marker - look up which DAStrings[] entry to substitute.
| DAStrings (at DABeeper+4) holds 4 handles for ^0..^3 replacement text.
| D6 scans ASCII '0'..'3' (0x30..0x33) to match char after '^'.
| ----------------------------------------------------------
DLGMGR_FOUND_2:
    LEA.L       (DABeeper).W,A3                 | A3 = base of DABeeper (before DAStrings)
    MOVE.B      #0x2F,D6                        | D6 = '0'-1; will increment to '0' first
DLGMGR_NEXT:
    ADDQ.L      #0x4,A3                         | advance to next DAStrings[] entry
    ADDQ.W      #0x1,D6                         | D6 = next digit char ('0','1','2','3')
    CMPI.B      #0x34,D6                        | past '3'? (checked all 4 substitutions)
    BEQ.B       DLGMGR_SKIP_4                   | no match: skip this '^', continue scan
    CMP.B       (A4),D6                         | does digit match char after '^'?
    BNE.B       DLGMGR_NEXT                     | no: try next DAStrings entry
    MOVEQ.L     #0x0,D0                         | D0 = replacement string length (0 if nil)
    MOVE.L      (A3),D4                         | D4 = DAStrings[n] handle
    BEQ.B       DLGMGR_EMPTY_3                  | nil handle: replace with empty string
    MOVEA.L     D4,A0                           | A0 = replacement string handle
    _HLock                                      | lock the replacement string handle
    MOVEA.L     (A0),A0                         | dereference to get string pointer
    MOVE.B      (A0)+,D0                        | D0 = Pascal string length byte
DLGMGR_EMPTY_3:
    SUBQ.W      #0x4,A7                         | space for Munger result
    MOVE.L      A2,-(A7)                        | push target handle (working text copy)
    MOVE.L      D3,-(A7)                        | push offset of '^' in text
    CLR.L       -(A7)                           | push nil for search ptr (delete mode)
    MOVE.L      #0x2,-(A7)                      | push 2 bytes to replace ('^' + digit)
    MOVE.L      A0,-(A7)                        | push replacement string pointer
    MOVE.L      D0,-(A7)                        | push replacement string length
    _Munger                                     | replace "^n" with DAStrings[n] text
    MOVE.L      (A7)+,D0                        | D0 = new match offset from Munger
    TST.L       D4                              | was DAStrings handle non-nil?
    BEQ.B       DLGMGR_EMPTY_2                  | nil: no unlock needed, rescan
    MOVEA.L     D4,A0                           | A0 = replacement string handle to unlock
    _HUnlock                                    | unlock the replacement string handle
    BRA.B       DLGMGR_EMPTY_2                  | rescan from current position
| ----------------------------------------------------------
| DLGMGR_CONT_24 (DLGMGR_CONT_24) - Dispose item resources (D4=2)
| Frees handles for text/icon/picture items, disposes controls.
| Item type dispatch: userItem=RTS, ctrlItem=DisposeControl,
| statText/editText=DisposeHandle, iconItem/picItem=DisposeHandle.
| ----------------------------------------------------------
DLGMGR_CONT_24:
    ROR.W       #0x3,D0                         | shift ctrlItem bit into carry
    BCS.W       DLGMGR_SKIP_2                   | ctrlItem: skip (disposed via DisposeControl)
    ROXR.W      #0x2,D0                         | shift statText/editText bits
    BCS.B       DLGMGR_CONT_26                  | statText: dispose text handle
    BMI.B       DLGMGR_CONT_26                  | editText: dispose text handle
DLGMGR_CONT_25:
    CLR.L       (A2)                            | clear item handle after disposal
    RTS                                         | return from statText/editText disposal
| ----------------------------------------------------------
| Dispose text or icon/picture handle
| ----------------------------------------------------------
DLGMGR_CONT_26:
    _DisposeHandle                              | free the text/icon/picture handle
    BRA.B       DLGMGR_CONT_25                  | clear item handle field
| ----------------------------------------------------------
| DLGMGR_CONT_27 - Dispose a control item (called from CloseDialog's item loop)
| ----------------------------------------------------------
    MOVE.L      A0,-(A7)                        | push control handle
    _DisposeControl                             | free control and its data
    BRA.B       DLGMGR_CONT_25                  | clear item handle field
| ----------------------------------------------------------
| Handle activate/deactivate event for dialog's TextEdit field.
| Switches port to target dialog, activates/deactivates its TE,
| then restores original port. Event modifiers bit 0 = activeFlag.
| ----------------------------------------------------------
DLGMGR_CONT_28:
    MOVEA.L     -0x4A(A6),A0                    | get event message (dialog window ptr)
    TST.W       0xA4(A0)                        | editField negative: no edit field
    BMI.B       DLGMGR_EXIT                     | no edit field: nothing to activate
    MOVE.L      0xA0(A0),-(A7)                  | save current port via teHandle GrafPtr
    MOVE.L      A0,-(A7)                        | push DialogPtr (also a GrafPtr)
    _SetPort                                    | switch to dialog's port
    BTST        #0x0,-0x3D(A6)                  | event modifiers bit 0 = activeFlag?
    BEQ.B       DLGMGR_NO_4                     | clear: deactivate
    _TEActivate                                 | activate: show insertion point
    BRA.B       DLGMGR_SKIP_5                   | go restore port
| ----------------------------------------------------------
DLGMGR_NO_4:
    _TEDeactivate                               | hide insertion point / selection
DLGMGR_SKIP_5:
    MOVE.L      A4,-(A7)                        | push original GrafPort
    _SetPort                                    | restore prior port
    BRA.B       DLGMGR_EXIT                     | return to dispatcher
| ----------------------------------------------------------
| RETURNS_15 - Main dialog event dispatcher
| Called from DialogSelect to process one event in a dialog.
| Dispatches on event.what from -0x4C(A6):
| 1=mouseDown, 3=keyDown, 5=keyDown(autoKey), 6=updateEvt,
| 8=activateEvt, else=nullEvent (TEIdle for caret blink).
| Returns: D3 = item number hit (0-based), or -1 if no item.
| ----------------------------------------------------------
RETURNS_15:
    MOVE.W      -0x4C(A6),D0                    | get event.what
    SUBQ.W      #0x1,D0                         | test for mouseDown (1)
    BEQ.W       DLGMGR_CONT_32                  | mouseDown (1): handle click
    SUBQ.W      #0x2,D0                         | test for keyDown (3)
    BEQ.B       DLGMGR_CONT_30                  | keyDown (3): handle keystroke
    SUBQ.W      #0x2,D0                         | test for autoKey (5)
    BEQ.B       DLGMGR_CONT_30                  | autoKey (5): handle repeated key
    SUBQ.W      #0x1,D0                         | test for updateEvt (6)
    BEQ.B       DLGMGR_CONT_29                  | updateEvt (6): redraw dialog
    SUBQ.W      #0x2,D0                         | test for activateEvt (8)
    BEQ.B       DLGMGR_CONT_28                  | activateEvt (8): activate/deactivate TE
    TST.W       0xA4(A4)                        | nullEvent: blink caret if edit field active
    BMI.B       DLGMGR_EXIT                     | no edit field: return -1
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TEIdle                                     | blink insertion point caret
| Called by: DLGMGR_CONT_28, DLGMGR_SKIP_5, RETURNS_15, DLGMGR_CONT_29, DLGMGR_CONT_30 (and 3 more)
DLGMGR_EXIT:
    MOVEQ.L     #-0x1,D3                        | return itemHit = -1 (no item)
    RTS                                         | return to DialogSelect caller
| ----------------------------------------------------------
| Handle updateEvt: redraw entire dialog within update region
| ----------------------------------------------------------
DLGMGR_CONT_29:
    MOVE.L      A4,-(A7)                        | push DialogPtr for EndUpdate
    MOVE.L      (A7),-(A7)                      | dup for DrawDialog
    MOVE.L      (A7),-(A7)                      | dup for BeginUpdate
    _BeginUpDate                                | clip to update region
    _DrawDialog                                 | redraw all items
    _EndUpDate                                  | restore clipping
    BRA.B       DLGMGR_EXIT                     | return itemHit = -1
| ----------------------------------------------------------
| Handle keyDown/autoKey: dispatch to TEKey or Tab-to-next-field.
| event.message low byte at -0x47(A6) = character code.
| ----------------------------------------------------------
DLGMGR_CONT_30:
    MOVE.B      -0x47(A6),D1                    | get typed character from event.message
    CMPI.B      #0x9,D1                         | Tab key?
    BEQ.B       DLGMGR_NEXT_2                   | yes: advance to next editText field
    MOVE.W      0xA4(A4),D3                     | get active edit field index
    BMI.B       DLGMGR_EXIT                     | no edit field: ignore keystroke
    MOVE.W      D1,-(A7)                        | push character for TEKey
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TEKey                                      | insert typed character into TE
    BRA.B       DLGMGR_EXIT_2                   | return current edit field as itemHit
| ----------------------------------------------------------
| Tab key: find next editText item in DITL and switch to it.
| Wraps around from last editText to first editText.
| ----------------------------------------------------------
DLGMGR_NEXT_2:
    CLR.W       D5                              | D5 = wrap flag (0=first pass, -1=wrapped)
    MOVE.W      0xA4(A4),D3                     | start from current edit field
    BSR.W       DLGMGR_OK_3                     | position to current item in DITL
DLGMGR_SKIP_6:
    BSR.W       DLGMGR_NEXT_4                   | advance to next DITL item
    BEQ.B       DLGMGR_CONT_31                  | past end of list: try wrapping
    CMP.W       0xA4(A4),D3                     | back to where we started?
    BEQ.B       DLGMGR_EXIT                     | yes: only one editText, no switch
    BTST        #0x4,0xC(A2)                    | test editText bit in item type
    BEQ.B       DLGMGR_SKIP_6                   | not editText: keep scanning
    BSR.W       DLGMGR_OK_2                     | check if item rect is on screen
    BEQ.B       DLGMGR_SKIP_6                   | off screen (hidden item): skip it
    MOVE.L      #0x7FFF,D2                      | select all text in new field
    BSR.W       DLG_SwitchActiveField           | switch to this edit field
DLGMGR_EXIT_2:
    BRA.B       DLGMGR_EXIT_4                   | return new edit field as itemHit
| ----------------------------------------------------------
| Reached end of DITL during Tab scan - wrap to beginning.
| Only wraps once (D5 tracks whether we already wrapped).
| ----------------------------------------------------------
DLGMGR_CONT_31:
    TST.W       D5                              | already wrapped once?
    BMI.B       DLGMGR_EXIT                     | yes: no editText found, give up
    MOVEQ.L     #-0x1,D5                        | set wrap flag
    MOVEQ.L     #-0x1,D3                        | reset to before first item
    TST.W       0xA4(A4)                        | is there any edit field at all?
    BPL.B       DLGMGR_SKIP_6                   | yes: scan from start of DITL
DLGMGR_EXIT_3:
    BRA.B       DLGMGR_EXIT                     | no edit fields at all: return -1
| ----------------------------------------------------------
| Handle mouseDown: convert click to local coords, find which
| DITL item was clicked, then dispatch by item type.
| ----------------------------------------------------------
DLGMGR_CONT_32:
    MOVE.L      -0x42(A6),-0x1C(A6)             | copy event.where to local point
    PEA.L       -0x1C(A6)                       | push ptr to local point
    _GlobalToLocal                              | convert click point to dialog coords
    MOVEQ.L     #-0x1,D3                        | start before first item
DLGMGR_NEXT_3:
    BSR.W       DLGMGR_NEXT_4                   | advance to next DITL item
    BEQ.B       DLGMGR_EXIT_3                   | past end: no item hit, return -1
    SUBQ.W      #0x2,A7                         | space for PtInRect result
    MOVE.L      -0x1C(A6),-(A7)                 | push click point
    PEA.L       -0x28(A6)                       | push item display rect
    _PtInRect                                   | is click inside this item?
    TST.B       (A7)+                           | did click intersect item rect?
    BEQ.B       DLGMGR_NEXT_3                   | not in this item: try next
    BTST        #0x2,0xC(A2)                    | is this a ctrlItem?
    BEQ.B       DLGMGR_NO_5                     | no: check for editText click
    SUBQ.W      #0x2,A7                         | space for FindControl result
    MOVE.L      -0x1C(A6),-(A7)                 | push click point
    MOVE.L      A4,-(A7)                        | push dialog window
    PEA.L       -0x18(A6)                       | push ptr for control handle result
    _FindControl                                | find which control was clicked
    MOVE.W      (A7)+,D0                        | D0 = part code (0=none)
    BEQ.B       DLGMGR_EXIT_3                   | not in a control: return -1
    SUBQ.W      #0x2,A7                         | space for TrackControl result
    MOVE.L      -0x18(A6),-(A7)                 | push control handle
    MOVE.L      -0x1C(A6),-(A7)                 | push click point
    MOVE.L      (MinusOne).W,-(A7)              | push nil actionProc (-1 = default)
    _TrackControl                               | track mouse until released
    TST.W       (A7)+                           | was control actually clicked?
    BEQ.B       DLGMGR_EXIT_3                   | no: mouse released outside, return -1
DLGMGR_EXIT_4:
    BRA.B       DLGMGR_EXIT_5                   | control was clicked: return item
| ----------------------------------------------------------
| Click was in a non-control item: check if editText.
| If editText, switch edit field and pass click to TEClick.
| ----------------------------------------------------------
DLGMGR_NO_5:
    BTST        #0x4,0xC(A2)                    | test editText bit in item type
    BEQ.B       DLGMGR_EXIT_5                   | not editText: return this item as hit
    CMP.W       0xA4(A4),D3                     | clicking in already-active field?
    BEQ.B       DLGMGR_OK                       | yes: just pass to TEClick
    MOVEQ.L     #0x0,D2                         | D2=0: place insertion point, don't select
    BSR.B       DLG_SwitchActiveField           | switch to clicked edit field
DLGMGR_OK:
    TST.W       0xA4(A4)                        | is there an active edit field now?
    BMI.B       DLGMGR_EXIT_5                   | no: skip TEClick
    MOVE.L      -0x1C(A6),-(A7)                 | push click point
    BTST        #0x1,-0x3E(A6)                  | test shiftKey in event modifiers
    SNE.B       -(A7)                           | push extend flag (true if Shift held)
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TEClick                                    | handle text selection/insertion
DLGMGR_EXIT_5:
    BTST        #0x7,0xC(A2)                    | test itemDisable bit
    BNE.W       DLGMGR_EXIT_3                   | disabled item: return -1 (ignore click)
    ADDQ.W      #0x1,D3                         | convert 0-based to 1-based item number
    RTS                                         | return D3 = item number hit
| ----------------------------------------------------------
| DLG_SwitchActiveField - Switch active edit field.
| Deactivates current TE (scrolling it back to origin), calls DLGMGR_CONT_33
| to install new field's text into TE, then activates TE.
| Entry: D3 = new field index (0-based), D2 = selection range.
| ----------------------------------------------------------
| Called by: SELITEXT, HIDEDITEM_NO, SHOWDITEM_CONT, DLGMGR_SKIP_6, DLGMGR_NO_5
DLG_SwitchActiveField:
    TST.W       0xA4(A4)                        | is there a current edit field?
    BMI.B       DLGMGR_SKIP_7                   | no current field: skip deactivation
    MOVEA.L     0xA0(A4),A0                     | get teHandle
    MOVEA.L     (A0),A0                         | dereference to TERec
    MOVE.L      0x8(A0),-(A7)                   | push teViewRect.topLeft
    MOVE.L      (A0),-(A7)                      | push teDestRect.topLeft
    PEA.L       0x4(A7)                         | push ptr to delta point on stack
    _SubPt                                      | delta = viewRect.topLeft - destRect.topLeft
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TEScroll                                   | scroll TE back to origin before switching
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TEDeactivate                               | hide caret/selection in old field
DLGMGR_SKIP_7:
    BSR.B       DLGMGR_CONT_33                  | install new field's text into shared TERec
    TST.W       0xA4(A4)                        | did DLGMGR_CONT_33 set a valid edit field?
    BMI.B       DLGMGR_SKIP_8                   | -1 = no edit field: skip activation
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TEActivate                                 | show caret/selection in new field
DLGMGR_SKIP_8:
    RTS                                         | return from edit field setup
| ----------------------------------------------------------
| DLG_SwitchOrEditField - Check if edit field changed, then install new field.
| Entry: D3 = target field index, D2 = selection range.
| Falls through to DLGMGR_CONT_33 if field is different.
| ----------------------------------------------------------
DLG_SwitchOrEditField:
    CMP.W       0xA4(A4),D3                     | is target same as current field?
    BEQ.B       DLGMGR_EXIT_6                   | yes: no switch needed, return
| DLGMGR_CONT_33 -- install new field's text into shared TERec.
DLGMGR_CONT_33:
    MOVE.L      (A2),D0                         | D0 = item handle (text handle for editText)
    BLE.B       DLGMGR_EXIT_6                   | nil or negative: no valid text, return
    MOVE.W      D3,0xA4(A4)                     | set new active edit field index
    BMI.B       DLGMGR_EXIT_6                   | -1 = no field: just clear and return
    MOVEA.L     0xA0(A4),A0                     | A0 = teHandle from DialogRecord
    MOVEA.L     (A0),A1                         | A1 = dereferenced TERec pointer
    MOVE.L      D0,0x3E(A1)                     | store text handle in TERec.hText (+$3E)
    MOVEQ.L     #-0x2,D0                        | sentinel value: don't change selection
    CMP.L       D0,D2                           | D2 = -2 means keep existing selection
    BEQ.B       DLGMGR_SKIP_9                   | skip selection update
    MOVE.L      D2,0x20(A1)                     | set TERec.selStart/selEnd (+$20, packed)
DLGMGR_SKIP_9:
    LEA.L       (A1),A0                         | A0 = TERec base for destRect/viewRect
    MOVE.L      -0x28(A6),(A0)+                 | copy item rect top-left to destRect.topLeft
    MOVE.L      -0x24(A6),(A0)+                 | copy item rect bot-right to destRect.botRight
    MOVE.L      -0x28(A6),(A0)+                 | copy item rect top-left to viewRect.topLeft
    MOVE.L      -0x24(A6),(A0)+                 | copy item rect bot-right to viewRect.botRight
    ST.B        0x32(A1)                        | TERec clickLoc (+$32) := $FFxx: no double click
    LEA.L       (A1),A0                         | A0 = TERec.destRect.top again
    MOVEQ.L     #0x2,D0                         | D0 = 2 (initial line height offset)
    ADD.W       (A0)+,D0                        | D0 += destRect.top; A0 -> destRect.left
    ADD.W       0x18(A1),D0                     | D0 += TERec.lineHeight (+$18)
    MOVE.W      (A0)+,D1                        | D1 = destRect.left; A0 -> destRect.bottom
    CMP.W       (A0)+,D0                        | compare top+lineHeight+2 vs destRect.bottom
    BLT.B       DLGMGR_SKIP_10                  | taller than one line: skip widening
    SUB.W       (A0),D1                         | D1 = left - destRect.right = -width
    SUB.W       D1,(A0)                         | destRect.right += width (double the width)
DLGMGR_SKIP_10:
    ST.B        -(A7)                           | push TRUE for TEAutoView enable
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TEAutoView                                 | enable auto-scrolling for this TE
    MOVE.L      0xA0(A4),-(A7)                  | push teHandle
    _TECalText                                  | recalculate line starts for new text
DLGMGR_EXIT_6:
    RTS                                         | return from edit field activation
| ----------------------------------------------------------
| DLGMGR_OK_2 - Test if item display rect is within dialog's portRect.
| Returns Z=1 if no intersection (item not visible).
| Uses inset=0 (exact rect bounds).
| ----------------------------------------------------------
DLGMGR_OK_2:
    MOVEQ.L     #0x0,D0                         | inset = 0 (no expansion)
    BRA.B       DLGMGR_CONT_35                  | share common rect intersection test
| ----------------------------------------------------------
| DLGMGR_CONT_34 - Test if item rect (expanded by 4 pixels) intersects portRect.
| Used during drawing to skip off-screen items.
| Returns Z=1 if no intersection.
| ----------------------------------------------------------
DLGMGR_CONT_34:
    MOVE.L      #0xFFFCFFFC,D0                  | inset = (-4,-4) to include item frame
DLGMGR_CONT_35:
    MOVE.L      0x8(A2),-(A7)                   | push item rect bottom-right
    MOVE.L      0x4(A2),-(A7)                   | push item rect top-left
    MOVE.L      A7,-(A7)                        | push ptr to temp rect on stack
    MOVE.L      D0,-(A7)                        | push inset amount (dh, dv packed)
    _InsetRect                                  | shrink rect by negative inset (expand it)
    CLR.W       -(A7)                           | space for SectRect boolean result
    PEA.L       0x2(A7)                         | push ptr to temp rect
    PEA.L       0x10(A4)                        | push dialog portRect (+$10 in GrafPort)
    PEA.L       0xA(A7)                         | push ptr to dummy dest rect on stack
    _SectRect                                   | test intersection of item rect and portRect
    MOVE.B      (A7)+,D0                        | D0 = TRUE if rects intersect
    ADDQ.W      #0x8,A7                         | clean up temp rect from stack
    RTS                                         | return visibility boolean in D0
| ----------------------------------------------------------
| DLG_FrameRoundOuter - Draw a rounded-rect frame around an item rect.
| Entry: A0 = ptr to rect, D0 = pen width, D1 = pen height,
| D2 = outward inset (positive = expand outward).
| Expands rect outward by D2, frames it, then restores rect.
| ----------------------------------------------------------
DLG_FrameRoundOuter:
    MOVE.L      A0,-(A7)                        | push rect ptr for 2nd InsetRect (restore)
    MOVE.W      D2,-(A7)                        | push +D2 horizontal (shrink back later)
    MOVE.W      D2,-(A7)                        | push +D2 vertical
    MOVE.L      A0,-(A7)                        | push rect ptr for FrameRoundRect
    MOVE.W      D1,-(A7)                        | push oval height for rounded corners
    MOVE.W      D1,-(A7)                        | push oval width for rounded corners
    MOVE.L      A0,-(A7)                        | push rect ptr for 1st InsetRect (expand)
    NEG.W       D2                              | negate: now -D2 = expand outward
    MOVE.W      D2,-(A7)                        | push -D2 horizontal inset (expand)
    MOVE.W      D2,-(A7)                        | push -D2 vertical inset (expand)
    MOVE.W      D0,-(A7)                        | push pen width for PenSize
    MOVE.W      D0,-(A7)                        | push pen height for PenSize
    _PenSize                                    | set pen to D0 x D0 pixels
    _InsetRect                                  | expand rect outward by D2 pixels
    _FrameRoundRect                             | draw rounded-rect frame
    _InsetRect                                  | restore rect to original size
    RTS                                         | return from rounded-rect frame drawing
| ----------------------------------------------------------
| DLG_NewStringHandle - Create a new string handle from a Pascal string.
| Entry: A0 = ptr to Pascal string.
| Exit: A0 = new string handle. Preserves D1-D2, A1-A2.
| Note: saves D0-D2/A1-A2 but restores D1-D2/A1-A2 only
| (D0 is clobbered by NewString result, shifts registers).
| ----------------------------------------------------------
DLG_NewStringHandle:
    MOVEM.L     D0-D2/A1-A2,-(A7)               | save regs (5 longs = 20 bytes)
    MOVE.L      A0,-(A7)                        | push string ptr for NewString
    _NewString                                  | create handle with copy of string
    MOVEA.L     (A7)+,A0                        | A0 = new string handle
    MOVEM.L     (A7)+,D1-D2/A1-A2               | restore D1-D2/A1-A2 (skip saved D0)
    RTS                                         | return with new string handle in A0
| ----------------------------------------------------------
| DLGMGR_NEXT_4 - Advance to the next DITL item.
| Increments D3 (item index), then positions A2 at next item.
| If D3 was -1 (no current item), falls into DLGMGR_OK_3 to start
| from the beginning. Returns Z=1 if past end of item list.
| ----------------------------------------------------------
| Called by: CLOSEDIALOG_LOOP, SETITEXT_WALK, FINDDITEM_WALK, FINDDITEM_INNER_LOOP, DLGMGR_SKIP_6 (and 1 more)
DLGMGR_NEXT_4:
    ADDQ.W      #0x1,D3                         | advance to next item index
    BEQ.B       DLGMGR_OK_3                     | was -1: start from first item
    MOVE.L      D2,-(A7)                        | save D2 (used as byte accumulator)
    MOVEQ.L     #0x1,D0                         | skip 1 item (advance from current)
    BRA.B       DLGMGR_SKIP_11                  | enter item-skip loop
| ----------------------------------------------------------
| DLGMGR_OK_3 - Position A2 at DITL item number D3.
| Walks the variable-length DITL item list from the beginning,
| skipping D3 items to reach the target. D7 accumulates byte
| offset. Returns A2 = ptr to item, Z=1 if past end.
| ----------------------------------------------------------
| Called by: INITDIALOGS_OK, CLOSEDIALOG_CONT_5, GETDITEM, SETDITEM, SELITEXT (and 4 more)
DLGMGR_OK_3:
    MOVE.L      D2,-(A7)                        | save D2 (used as byte accumulator)
    MOVEQ.L     #0x0,D7                         | D7 = running byte offset into DITL data
    MOVE.W      D3,D0                           | D0 = number of items to skip
    BLT.B       DLGMGR_EXIT_7                   | negative index: return nil
DLGMGR_SKIP_11:
    MOVEQ.L     #0x0,D2                         | clear D2 for byte-size data length reads
    MOVE.L      A3,D1                           | test items handle (A3)
    BEQ.B       DLGMGR_EXIT_7                   | nil handle: return nil
    MOVEA.L     (A3),A2                         | dereference items handle to DITL data
    MOVE.W      (A2)+,D1                        | D1 = item count - 1 (DITL stores count-1)
    CMP.W       D3,D1                           | is target index within range?
    BGE.B       DLGMGR_OK_4                     | yes: start walking items
DLGMGR_EXIT_7:
    SUBA.L      A2,A2                           | A2 = nil (past end of list)
    BRA.B       DLGMGR_EXIT_8                   | return with Z=1
| ----------------------------------------------------------
| DLGMGR_LOOP_3 - Skip one DITL item entry (variable-length).
| Each item: 4-byte handle + 8-byte rect + 1-byte type +
| 1-byte data length + data (padded to even boundary).
| ----------------------------------------------------------
DLGMGR_LOOP_3:
    MOVE.B      0xD(A2,D7.W),D2                 | D2 = data length byte at item+13+offset
    ADD.W       D2,D7                           | advance offset by data length
    ADDI.W      #0xF,D7                         | add 15 (14 fixed bytes + round up)
    ANDI.W      #0xFFFE,D7                      | align to even byte boundary
DLGMGR_OK_4:
    DBF.W       D0,DLGMGR_LOOP_3                | skip D0 items
    ADDA.W      D7,A2                           | A2 = ptr to target item entry
    BSR.B       DLGMGR_CONT_36                  | copy item's display rect to -0x28(A6)
DLGMGR_EXIT_8:
    MOVE.L      (A7)+,D2                        | restore D2
    MOVE.L      A2,D0                           | set Z flag: Z=1 if A2 is nil (past end)
    RTS                                         | return with Z flag set if past end
| ----------------------------------------------------------
| DLGMGR_CONT_36 - Copy item's display rect to local frame variable.
| Copies 8 bytes from item+4 (display rect) to -0x28(A6).
| ----------------------------------------------------------
DLGMGR_CONT_36:
    LEA.L       0x4(A2),A0                      | A0 = ptr to item's display rect
    LEA.L       -0x28(A6),A1                    | A1 = ptr to local rect variable
    MOVE.L      (A0)+,(A1)+                     | copy rect top-left (top, left)
    MOVE.L      (A0)+,(A1)+                     | copy rect bottom-right (bottom, right)
    RTS                                         | return from rect copy
