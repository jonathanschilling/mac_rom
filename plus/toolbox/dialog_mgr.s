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
| The data in front of InitDialogs (DT_mMaxIAppend) is the IAppend
| string used by ParamText substitution.
|
| References: Inside Macintosh Vol I, Ch 13 (The Dialog Manager).

| ----------------------------------------------------------
|
| DT_mMaxIAppend
|
| DT_mMaxIAppend: alert icon bounds rect (10,20,42,52)
| Used by _Alert to position the stop/note/caution icon
DT_mMaxIAppend:
  .byte 0x00,0x0A,0x00,0x14,0x00,0x2A
  .byte 0x00,0x34

| DT_MMAXIAPPEND_EMPTY: empty Pascal string (length=0), used as dialog title
DT_MMAXIAPPEND_EMPTY:
  .byte 0x00,0x00

| InitDialogs -- _InitDialogs ($A97B): PROCEDURE InitDialogs (resumeProc: ProcPtr);
InitDialogs:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  0x8(A6),(ResumeProc).w          | store resume procedure from param
        CLR     (ACount).w                      | reset alert invocation count
        ST.B    (ANumber).w                     | invalidate current alert ID (0xFF)
        LEA.L   (DABeeper).w,A0                 | A0 = start of dialog globals
        LEA.L   INITDIALOGS_CONT(PC),A1         | A1 = default beep procedure
        MOVE.L  A1,(A0)+                        | DABeeper = default beep proc
        CLR.L   (A0)+                           | clear DAStrings[0] (ParamText ^0)
        CLR.L   (A0)+                           | clear DAStrings[1] (ParamText ^1)
        CLR.L   (A0)+                           | clear DAStrings[2] (ParamText ^2)
        CLR.L   (A0)+                           | clear DAStrings[3] (ParamText ^3)
        CLR     (DlgFont).w                     | default dialog font = system font (0)
        MOVEQ.L #0x4,D0                         | 4 bytes of params to clean up
        BRA     MODALDIALOG_CONT_4              | dialog epilogue

| ----------------------------------------------------------
|
| INITDIALOGS_CONT
|
| Called during boot.
INITDIALOGS_CONT:
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE    (SP)+,D2                        | D2 = beep count
INITDIALOGS_LOOP:
        BEQ.B   INITDIALOGS_DONE                | count exhausted - done
        MOVE    #0x3,-(SP)                      | push duration = 3 ticks
        _SysBeep                                | emit system beep sound
        MOVE    #0x6,A0                         | delay 6 ticks between beeps
        _Delay                                  | wait for delay
        SUBQ.W  #0x1,D2                         | decrement beep counter
        BRA.B   INITDIALOGS_LOOP                | loop for remaining beeps

| ----------------------------------------------------------
|
| INITDIALOGS_DONE - beep loop done, return to caller
|
| Called during boot.
INITDIALOGS_DONE:
        JMP     (A1)                            | return to caller

| ----------------------------------------------------------
|
| INITDIALOGS_EXIT
|
| Called during boot.
INITDIALOGS_EXIT:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  0x10(A6),A4                     | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        CLR     0x14(A6)                        | clear result flag (no item hit yet)
        MOVE.L  0xC(A6),A0                      | A0 = event record pointer
        CMPI    #0x3,(A0)                       | is event type keyDown (3)?
        BNE.B   INITDIALOGS_SKIP_2              | no - not a key event, skip
        CMPI.B  #0x3,0x5(A0)                    | character (message low byte) = Enter ($03)?
        BEQ.B   INITDIALOGS_OK                  | yes - treat as default button press
        CMPI.B  #0xD,0x5(A0)                    | character = Return ($0D)?
        BNE.B   INITDIALOGS_SKIP_2              | no - not a default-button key
INITDIALOGS_OK:
        MOVE    aDefItem(A4),D3                 | D3 = default item number
        MOVE.L  0x8(A6),A1                      | A1 = caller's itemHit pointer
        MOVE    D3,(A1)                         | store default item as hit item
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry for default item
        BSR     FINDDITEM_CONT_2                | get item handle and type
        ANDI    #0x7,D0                         | mask to item type (low 3 bits)
        CMPI    #0x4,D0                         | is it a button control (type 4)?
        BNE.B   INITDIALOGS_SKIP                | no - skip hilite animation
        MOVE.B  0xC(A2),D0                      | D0 = item flags byte
        BMI.B   INITDIALOGS_SKIP_2              | disabled - don't hilite
        MOVE.L  A0,-(SP)                        | push control handle for unhilite
        CLR     -(SP)                           | push hiliteState = 0 (unhilite)
        MOVE.L  A0,-(SP)                        | push control handle for hilite
        MOVE    #0xA,-(SP)                      | push hiliteState = 10 (invert)
        _HiliteControl                          | hilite the default button
        MOVE    #0x8,A0                         | delay 8 ticks (visual feedback)
        _Delay                                  | wait
        _HiliteControl                          | unhilite the button
INITDIALOGS_SKIP:
        ADDQ.B  #0x1,0x14(A6)                   | set result flag = true (item was hit)
INITDIALOGS_SKIP_2:
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0xC,D0                         | 12 bytes of params to clean up
        BRA     MODALDIALOG_CONT_4              | dialog epilogue

| StopAlert -- _StopAlert ($A986): FUNCTION StopAlert (alertID: INTEGER; filterProc : ProcPtr) INTEGER;
| ----------------------------------------------------------
|
| _StopAlert ($A986)
|
StopAlert:
        MOVEQ.L #0x0,D0                         | D0 = 0: stop icon
        BRA.B   ALERT_CONT                      | common alert entry

| NoteAlert -- _NoteAlert ($A987): FUNCTION NoteAlert (alertID : INTEGER; filterProc: ProcPtr) INTEGER;
| ----------------------------------------------------------
|
| _NoteAlert ($A987)
|
NoteAlert:
        MOVEQ.L #0x1,D0                         | D0 = 1: note icon
        BRA.B   ALERT_CONT                      | common alert entry

| ----------------------------------------------------------
|
| _CautionAlert ($A988)
|
CautionAlert:
        MOVEQ.L #0x2,D0                         | D0 = 2: caution icon
        BRA.B   ALERT_CONT                      | common alert entry

| Alert -- _Alert ($A985): FUNCTION Alert (alertID: INTEGER; fi lterPro c : ProcPtr) : INTEGER;
| ----------------------------------------------------------
|
| _Alert ($A985)
|
Alert:
        MOVEQ.L #-0x1,D0                        | D0 = -1: plain alert (no icon)
ALERT_CONT:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE    D0,D3                           | D3 = icon type (0=stop,1=note,2=caution,-1=none)
        MOVE    0xC(A6),D0                      | D0 = alert resource ID
        BSR     COULDALERT_CONT_2               | load ALRT resource template
        MOVE    (ACount).w,D0                   | D0 = previous alert invocation count
        MOVE    0xC(A6),D1                      | D1 = current alert ID
        CMP     (ANumber).w,D1                  | same alert as last time?
        BEQ.B   ALERT_OK                        | yes - keep count
        MOVE    D1,(ANumber).w                  | no - store new alert ID
        MOVEQ.L #0x0,D0                         | reset count to 0
ALERT_OK:
        MOVE    D0,(ACount).w                   | store invocation count
        MOVE    0xA(A1),D4                      | D4 = alert stage bits (4 stages x 4 bits)
ALERT_CONT_2:
        SUBQ.W  #0x1,D0                         | shift to current stage's 4-bit field
        BLT.B   ALERT_CONT_3                    | reached current stage - extract nibble
        LSR     #0x4,D4                         | shift right one nibble (4 bits)
        BRA.B   ALERT_CONT_2                    | continue shifting

| ----------------------------------------------------------
|
| ALERT_CONT_3 - process alert stage nibble
|
ALERT_CONT_3:
        ANDI    #0xF,D4                         | isolate low nibble (current stage)
        MOVE.L  D4,D0                           | D0 = stage nibble for beep count
        ANDI    #0x3,D0                         | low 2 bits = beep count (0-3)
        BSR     ALERT_CONT_6                    | call beep procedure D0 times
        BTST    #0x2,D4                         | bit 2 = show dialog flag
        BNE.B   ALERT_CONT_4                    | set - show the alert dialog
        MOVE    (MinusOne).w,0xE(A6)            | no dialog - return -1 as itemHit
        BRA     ALERT_SKIP_2                    | skip to cleanup

| ----------------------------------------------------------
|
| ALERT_CONT_4 - create and show alert dialog
|
ALERT_CONT_4:
        MOVE.L  #0x1FF,D0                       | flush all event types
        _FlushEvents                            | clear event queue before modal dialog
        MOVE    0x8(A1),D0                      | D0 = DITL resource ID from ALRT template
        BSR     ALERT_CONT_5                    | load and copy DITL resource
        MOVE.L  (A2),A1                         | A1 = dereferenced ALRT template data
        SUBQ.W  #0x4,SP                         | space for NewDialog result handle
        CLR.L   -(SP)                           | dStorage = NIL (allocate on heap)
        PEA.L   (A1)                            | push boundsRect from ALRT template
        PEA.L   DT_MMAXIAPPEND_EMPTY(PC)        | push empty title string
        ST.B    -(SP)                           | visible = true
        MOVE    #0x1,-(SP)                      | procID = 1 (dBoxProc, no title bar)
        MOVE.L  (MinusOne).w,-(SP)              | behind = -1 (in front of all windows)
        CLR     -(SP)                           | goAwayFlag = false
        CLR.L   -(SP)                           | refCon = 0
        MOVE.L  A0,-(SP)                        | push items handle (copied DITL)
        _NewDialog                              | create the alert dialog
        MOVE.L  (SP),A4                         | A4 = new dialog pointer
        PEA.L   -0x2C(A6)                       | push address to save current port
        _GetPort                                | save current grafPort
        _SetPort                                | set dialog as current port
        TST     D3                              | is there an icon to display?
        BMI.B   ALERT_SKIP                      | -1 = no icon, skip
        SUBQ.W  #0x4,SP                         | space for GetIcon result
        MOVE    D3,-(SP)                        | push icon ID (0=stop, 1=note, 2=caution)
        _GetIcon                                | load icon resource
        MOVE.L  (SP)+,D0                        | D0 = icon handle
        BEQ.B   ALERT_SKIP                      | no icon found - skip plot
        PEA.L   DT_mMaxIAppend(PC)              | push icon bounds rect (10,20,42,52)
        MOVE.L  D0,-(SP)                        | push icon handle
        _PlotIcon                               | draw icon in alert dialog
ALERT_SKIP:
        ASR     #0x3,D4                         | bit 3 of stage = default button selector
        ADDQ.W  #0x1,D4                         | D4 = default item number (1 or 2)
        MOVE    D4,aDefItem(A4)                 | set default button in dialog record
        MOVE.L  A4,-(SP)                        | push dialog pointer
        MOVE    D4,-(SP)                        | push default item number
        PEA.L   -0x3C(A6)                       | push ptr for item type result
        MOVE.L  (SP),-(SP)                      | push ptr for item handle result
        PEA.L   -0x28(A6)                       | push ptr for item rect result
        _GetDialogItem                          | get default item's rect for bold outline
        LEA.L   -0x28(A6),A0                    | A0 = default item's bounding rect
        MOVEQ.L #0x3,D0                         | inset left/right = 3 pixels
        MOVEQ.L #0x10,D1                        | pen size = 16 (bold outline)
        MOVEQ.L #0x4,D2                         | round radius = 4
        BSR     ENTRY_4                         | draw bold rounded rect around default button
        MOVE.L  0x8(A6),-(SP)                   | push filterProc for ModalDialog
        PEA.L   0xE(A6)                         | push address for itemHit result
        _ModalDialog                            | run modal dialog event loop
        MOVE.L  -0x2C(A6),-(SP)                 | push saved port
        _SetPort                                | restore original grafPort
        MOVE.L  A4,-(SP)                        | push dialog pointer
        _DisposeDialog                          | dispose the alert dialog
ALERT_SKIP_2:
        BClr    #0x7,(A2)                       | clear lock bit on ALRT resource handle
        MOVE    (ACount).w,D1                   | D1 = current invocation count
        ADDQ.W  #0x1,D1                         | increment count for next call
        CMPI    #0x4,D1                         | maximum 4 stages
        BLT.B   ALERT_OK_2                      | under max - use as-is
        MOVEQ.L #0x3,D1                         | cap at stage 3 (repeat last stage)
ALERT_OK_2:
        MOVE    D1,(ACount).w                   | store updated invocation count
        MOVEQ.L #0x6,D0                         | 6 bytes of params to clean up
        BRA.B   GETNEWDIALOG_CONT               | dialog epilogue

| ----------------------------------------------------------
|
| ALERT_CONT_5
|
| Called during boot.
ALERT_CONT_5:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4449544C,-(SP)               | push type = 'DITL'
        MOVE    D0,-(SP)                        | push DITL resource ID
        _GetResource                            | load DITL template
        MOVE.L  (SP)+,A0                        | A0 = DITL handle
        _HandToHand                             | make a copy (dialog owns its item list)
        RTS                                     | return copied DITL handle in A0

| ----------------------------------------------------------
|
| ALERT_CONT_6
|
| Called during boot.
ALERT_CONT_6:
        MOVEM.L D0-D2/A0-A2,-(SP)               | save registers
        MOVE.L  (DABeeper).w,D1                 | D1 = beep procedure address
        BEQ.B   ALERT_SKIP_3                    | no beep proc installed - skip
        MOVE    D0,-(SP)                        | push beep count on stack
        MOVE.L  D1,A0                           | A0 = beep procedure
        JSR     (A0)                            | call beep procedure with count arg
ALERT_SKIP_3:
        MOVEM.L (SP)+,D0-D2/A0-A2               | restore registers
        RTS                                     | return from beep procedure

| ----------------------------------------------------------
|
| _GetNewDialog ($A97C)
|
| Called during boot.
GetNewDialog:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE    0x10(A6),D0                     | D0 = DLOG resource ID
        BSR     COULDALERT_CONT_3               | load DLOG template, A1 = data, A2 = handle
        SUBQ.W  #0x4,SP                         | space for NewDialog result
        MOVE.L  0xC(A6),-(SP)                   | push dStorage pointer from caller
        MOVE.L  A1,-(SP)                        | push boundsRect pointer (DLOG template)
        PEA.L   0x14(A1)                        | push title string (at template+20)
        ADDQ.L  #0x8,A1                         | skip past boundsRect to window fields
        MOVE.L  (A1)+,-(SP)                     | push procID + visible (DLOG template +8)
        MOVE.L  0x8(A6),-(SP)                   | push behind window from caller
        MOVE    (A1)+,-(SP)                     | push goAwayFlag (template +$C)
        MOVE.L  (A1)+,-(SP)                     | push refCon (template +$E)
        MOVE    (A1)+,D0                        | D0 = DITL resource ID from template
        BSR.B   ALERT_CONT_5                    | load and copy DITL
        MOVE.L  A0,-(SP)                        | push items handle
        _NewDialog                              | create dialog from template
        BCLR    #0x7,(A2)                       | unlock DLOG resource handle
        MOVE.L  (SP)+,0x12(A6)                  | store dialog pointer in return slot
        MOVEQ.L #0xA,D0                         | 10 bytes of params to clean up
GETNEWDIALOG_CONT:
        BRA.B   NEWDIALOG_CONT                  | dialog epilogue

| ----------------------------------------------------------
|
| _NewDialog ($A97D)
|
| Called during boot.
NewDialog:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        TST.L   0x22(A6)                        | was dStorage provided?
        BNE.B   NEWDIALOG_OK                    | yes - use caller's storage
        MOVE.L  #0xAA,D0                        | 170 bytes = dialog record size
        _NewPtr                                 | allocate dialog record on heap
        MOVE.L  A0,0x22(A6)                     | store allocated pointer
NEWDIALOG_OK:
        LEA.L   0xC(A6),A0                      | A0 = start of NewWindow params on stack
        MOVEQ.L #0x1E,D0                        | 30 bytes of window creation parameters
        SUBA.L  D0,SP                           | allocate 30 bytes on stack
        MOVE.L  A7,A1                           | A1 = destination for param copy
        _BlockMove                              | copy window params to stack temp
        _NewWindow                              | create underlying window
        MOVE.L  (SP)+,A4                        | A4 = new window/dialog pointer
        MOVE.L  A4,0x26(A6)                     | store result dialog pointer
        MOVE.L  0x8(A6),A3                      | A3 = items handle from caller
        MOVE    #0x2,windowKind(A4)             | set windowKind = dialogKind (2)
        MOVE.L  A3,items(A4)                    | items := item list handle (from caller)
        MOVE    (MinusOne).w,editField(A4)      | editField = -1 (no active text field)
        MOVE    (DlgFont).w,0x44(A4)            | set dialog font from global default
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  A7,-(SP)                        | push address to save current port
        _GetPort                                | save current grafPort
        MOVE.L  A4,-(SP)                        | push dialog as new port
        _SetPort                                | make dialog the current port
        MOVE    #0x1,aDefItem(A4)               | default item = 1
        SUBQ.W  #0x4,SP                         | space for TENew result
        PEA.L   0x10(A4)                        | push destRect (portRect of dialog)
        MOVE.L  (SP),-(SP)                      | push viewRect (same as destRect)
        _TENew                                  | create TextEdit record for dialog
        MOVE.L  (SP),0xA0(A4)                   | store TE handle in dialog record
        MOVE.L  (SP)+,A1                        | A1 = TE handle
        MOVE.L  (A1),A2                         | A2 = dereferenced TE record
        MOVE.L  0x3E(A2),A0                     | A0 = TE's text handle (empty default)
        _DisposeHandle                          | dispose initial empty text handle
        _SetPort                                | restore saved grafPort
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVEQ.L #0x0,D4                         | D4 = 0: initialize items (create controls)
        BSR     FINDDITEM_CONT                  | walk item list, create controls
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0x1E,D0                        | 30 bytes of params to clean up
NEWDIALOG_CONT:
        BRA.B   ISDIALOGEVENT_CONT              | dialog epilogue chain

| ----------------------------------------------------------
|
| NEWDIALOG_CONT_2
|
| Called during boot (3,693 times in 30s trace).
NEWDIALOG_CONT_2:
        MOVE    (A2),D3                         | D3 = event type (what field)
        SUBQ.W  #0x6,D3                         | test for updateEvt (6)
        BEQ.B   NEWDIALOG_OK_2                  | update - target window is in message field
        SUBQ.W  #0x2,D3                         | test for activateEvt (8)
        BEQ.B   NEWDIALOG_OK_2                  | activate - target window in message field
        SUBQ.W  #0x4,SP                         | other event types: use front window
        _FrontWindow                            | get frontmost window
        MOVE.L  (SP)+,A4                        | A4 = front window
        RTS                                     | return front window in A4

| ----------------------------------------------------------
|
| NEWDIALOG_OK_2 - update/activate: window is in event message field
|
| Called during boot.
NEWDIALOG_OK_2:
        MOVE.L  0x2(A2),A4                      | A4 = window from event message
        RTS                                     | return event window in A4

| ----------------------------------------------------------
|
| _IsDialogEvent ($A97F)
|
| Called during boot (3,693 times in 30s trace).
IsDialogEvent:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        CLR     0xC(A6)                         | preset result = false
        MOVE.L  0x8(A6),A2                      | A2 = event record pointer
        BSR.B   NEWDIALOG_CONT_2                | A4 = target window for this event
        CMPI    #0x2,windowKind(A4)             | is target a dialog (kind=2)?
        BNE.B   ISDIALOGEVENT_SKIP              | no - not a dialog event
        MOVE    (A2),D3                         | D3 = event type
        SUBQ.W  #0x1,D3                         | test for mouseDown (1)
        BNE.B   ISDIALOGEVENT_NO                | not mouseDown - assume dialog event
        SUBQ.W  #0x2,SP                         | space for FindWindow result
        MOVE.L  0xA(A2),-(SP)                   | push mouse click point
        PEA.L   -0x14(A6)                       | push address for window result
        _FindWindow                             | which window was clicked?
        SUBQ.W  #0x3,(SP)+                      | test for inContent (3)
        BNE.B   ISDIALOGEVENT_SKIP              | not in content - not a dialog event
        CMPA.L  -0x14(A6),A4                    | clicked window == front dialog?
        BNE.B   ISDIALOGEVENT_SKIP              | no - not a dialog event
ISDIALOGEVENT_NO:
        ADDQ.B  #0x1,0xC(A6)                    | result = true (is a dialog event)
ISDIALOGEVENT_SKIP:
        MOVEQ.L #0x4,D0                         | 4 bytes of params to clean up
ISDIALOGEVENT_CONT:
        BRA.B   DIALOGSELECT_CONT               | dialog epilogue

| ----------------------------------------------------------
|
| _DialogSelect ($A980)
|
| Called during boot.
DialogSelect:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        CLR     0x14(A6)                        | preset result = false
        MOVE.L  0xC(A6),A3                      | A3 = caller's theDialog pointer
        CLR.L   (A3)                            | clear dialog pointer output
        MOVE.L  0x10(A6),A2                     | A2 = event record pointer
        BSR.B   NEWDIALOG_CONT_2                | A4 = target window for this event
        MOVE.L  A4,(A3)                         | store dialog pointer in output
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE.L  0x10(A6),A0                     | A0 = event record source
        LEA.L   -0x4C(A6),A1                    | A1 = local copy of event record
        MOVEQ.L #0x10,D0                        | 16 bytes = event record size
        _BlockMove                              | copy event record to local frame
        BSR     RETURNS_15                      | dispatch event to dialog items
        TST     D3                              | was an item hit?
        BMI.B   DIALOGSELECT_NO                 | no - result stays false
        ADDQ.B  #0x1,0x14(A6)                   | result = true (item was hit)
DIALOGSELECT_NO:
        MOVE.L  0x8(A6),A0                      | A0 = caller's itemHit pointer
        MOVE    D3,(A0)                         | store hit item number
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0xC,D0                         | 12 bytes of params to clean up
DIALOGSELECT_CONT:
        BRA.B   MODALDIALOG_CONT_2              | dialog epilogue

| ----------------------------------------------------------
|
| _ModalDialog ($A991)
|
| Called during boot.
ModalDialog:
        BSR     MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
MODALDIALOG_NEXT:
        _SystemTask                             | give time to DAs and background tasks
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get front window
        MOVE.L  (SP)+,A0                        | A0 = front window (dialog)
        TST     0xA4(A0)                        | test editField (-1 = no text field)
        BMI.B   MODALDIALOG_SKIP                | no edit field - skip cursor blink
        MOVE.L  0xA0(A0),-(SP)                  | push TE handle
        _TEIdle                                 | blink insertion point cursor
MODALDIALOG_SKIP:
        SUBQ.W  #0x6,SP                         | space for GetNextEvent result + event
        MOVE    #0x17F,-(SP)                    | eventMask: all events except disk
        PEA.L   -0x4C(A6)                       | push local event record address
        _GetNextEvent                           | poll for next event
        MOVE.L  0xC(A6),D3                      | D3 = caller's filterProc
        BNE.B   MODALDIALOG_CONT                | filterProc provided - use it
        LEA.L   INITDIALOGS_EXIT(PC),A0         | no filter - use default (handles Return/Enter)
        MOVE.L  A0,D3                           | D3 = default filter proc
MODALDIALOG_CONT:
        _FrontWindow                            | push front window for filter proc
        PEA.L   -0x4C(A6)                       | push event record for filter
        MOVE.L  0x8(A6),-(SP)                   | push itemHit pointer for filter
        MOVE.L  D3,A0                           | A0 = filter proc address
        JSR     (A0)                            | call filter proc
        TST.B   (SP)+                           | did filter handle the event?
        BNE.B   MODALDIALOG_EXIT                | yes - item was hit, return
        SUBQ.W  #0x2,SP                         | space for IsDialogEvent result
        PEA.L   -0x4C(A6)                       | push event record
        _IsDialogEvent                          | is event for this dialog?
        TST     (SP)+                           | test result
        BEQ.B   MODALDIALOG_NO                  | no - check for special events
        SUBQ.W  #0x2,SP                         | space for DialogSelect result
        PEA.L   -0x4C(A6)                       | push event record
        PEA.L   -0x1C(A6)                       | push theDialog output address
        MOVE.L  0x8(A6),-(SP)                   | push itemHit pointer
        _DialogSelect                           | dispatch event to dialog items
        TST     (SP)+                           | was an item hit?
        BLE.B   MODALDIALOG_NEXT                | no - loop back for next event
MODALDIALOG_EXIT:
        MOVEQ.L #0x8,D0                         | 8 bytes of params to clean up
MODALDIALOG_CONT_2:
        BRA.B   MODALDIALOG_CONT_4              | dialog epilogue

| ----------------------------------------------------------
|
| MODALDIALOG_NO
|
| Called during boot.
MODALDIALOG_NO:
        MOVE    -0x4C(A6),D0                    | D0 = event type from local record
        SUBQ.W  #0x1,D0                         | test for mouseDown (1)
        BNE.B   MODALDIALOG_NEXT                | not mouseDown - continue event loop
        MOVEQ.L #0x1,D0                         | beep count = 1 (click outside modal dialog)
        BSR     ALERT_CONT_6                    | beep to alert user
        BRA.B   MODALDIALOG_NEXT                | continue event loop

| ----------------------------------------------------------
|
| MODALDIALOG_CONT_3
|
| Called during boot (3,696 times in 30s trace).
MODALDIALOG_CONT_3:
        MOVE.L  (SP)+,A0                        | pop return address
        LINK    A6,#-0x4C                       | allocate 76 bytes of local storage
        MOVEM.L D3-D7/A2-A4,-(SP)               | save all working registers
        JMP     (A0)                            | return to caller body

| ----------------------------------------------------------
|
| MODALDIALOG_CONT_4 - Dialog Manager common epilogue
|
| Called during boot (3,696 times in 30s trace).
MODALDIALOG_CONT_4:
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore saved registers
        UNLK    A6                              | tear down stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.L  D0,SP                           | remove D0 bytes of parameters
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _DrawDialog ($A981)
|
| Called during boot.
DrawDialog:
        BSR.B   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  0x8(A6),A4                      | A4 = dialog pointer from param
        BSR.B   CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE.L  A4,-(SP)                        | push dialog for DrawControls
        _DrawControls                           | draw all controls in dialog
        MOVEQ.L #0x1,D4                         | D4 = 1: draw mode (redraw items)
        BSR     FINDDITEM_CONT                  | walk and draw all dialog items
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        BRA.B   CLOSEDIALOG_CONT                | epilogue: 4 param bytes

| UpdtDialog -- trap handler for _UpdtDialog ($A978).
| ----------------------------------------------------------
|
| _UpdtDialog ($A978)
|
UpdtDialog:
        BSR.B   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  0xC(A6),A4                      | A4 = dialog pointer from param
        BSR.B   CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE.L  A4,-(SP)                        | push dialog for UpdtControls
        MOVE.L  0x8(A6),-(SP)                   | push update region
        _UpdtControl                            | update controls in dirty region
        MOVEQ.L #0x3,D4                         | D4 = 3: update mode (redraw in region)
        BSR     FINDDITEM_CONT                  | walk and update dialog items
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        BRA     SETITEXT_CONT                   | epilogue: 8 param bytes

| ----------------------------------------------------------
|
| _CloseDialog ($A982)
|
| Called during boot.
CloseDialog:
        BSR.B   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  0x8(A6),A4                      | A4 = dialog pointer from param
        BSR.B   CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE.L  0x1C(A4),-(SP)                  | push the dialog port's clipRgn
        _SetEmptyRgn                            | empty it: nothing drawn while items are disposed
        MOVEQ.L #0x2,D4                         | D4 = 2: dispose mode (free item handles)
        BSR     FINDDITEM_CONT                  | walk items, dispose controls/handles
        BSR.B   CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVE.L  0xA0(A4),A0                     | A0 = TE handle from dialog record
        MOVE.L  (A0),A0                         | dereference TE handle (unused read)
        MOVE.L  0xA0(A4),A0                     | A0 = TE handle (reload for dispose)
        _DisposeHandle                          | dispose TextEdit handle
        MOVE.L  A4,-(SP)                        | push dialog as window
        _CloseWindow                            | close the underlying window
CLOSEDIALOG_CONT:
        MOVEQ.L #0x4,D0                         | 4 bytes of params to clean up
CLOSEDIALOG_CONT_2:
        BRA.B   MODALDIALOG_CONT_4              | dialog epilogue

| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_3
|
| Called during boot.
CLOSEDIALOG_CONT_3:
        MOVE.L  items(A4),A3                    | A3 = item list handle (items) from dialog record
        TST.L   (A3)                            | is item list data loaded?
        BNE.B   CLOSEDIALOG_SKIP                | yes - skip load
        MOVE.L  A3,-(SP)                        | push handle
        _LoadResource                           | load item list data from resource
CLOSEDIALOG_SKIP:
        BSet    #0x7,(A3)                       | lock item list handle (prevent purge)
        RTS                                     | return locked item list handle

| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_4
|
| Called during boot.
CLOSEDIALOG_CONT_4:
        PEA.L   -0x2C(A6)                       | push address to save current port
        _GetPort                                | save current grafPort
        MOVE.L  A4,-(SP)                        | push dialog as new port
        _SetPort                                | make dialog the current port
        BSR.B   CLOSEDIALOG_CONT_3              | load and lock item list
        BSR.B   CLOSEDIALOG_CONT_5              | find active text edit field
        BEQ.B   CLOSEDIALOG_SKIP_2              | no active field - skip TE setup
        BSR     ENTRY_3                         | sync TE with current edit item
CLOSEDIALOG_SKIP_2:
        MOVEQ.L #0x1A,D1                        | D1 = 0x1A: offset used by item list walker
        RTS                                     | return item list walker offset in D1

| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_5
|
| Called during boot.
CLOSEDIALOG_CONT_5:
        MOVE    editField(A4),D3                | D3 = active text edit field index (-1 if none)
        BMI.B   CLOSEDIALOG_NO                  | -1 = no active field, search for one
        BSR     DLGMGR_OK_3                     | get item entry for editField
        BRA.B   CLOSEDIALOG_FOUND               | set D2 = -2 (found flag)

| ----------------------------------------------------------
|
| CLOSEDIALOG_NO - search for first editText item
|
| Called during boot.
CLOSEDIALOG_NO:
        MOVEQ.L #-0x1,D3                        | start iteration from beginning
CLOSEDIALOG_NO_2:
        BSR     DLGMGR_NEXT_4                   | advance to next dialog item
        BEQ.B   CLOSEDIALOG_EXIT                | no more items - return (no edit field)
        BTST    #0x4,0xC(A2)                    | test editText flag (bit 4 of item type)
        BEQ.B   CLOSEDIALOG_NO_2                | not editText - keep searching
        BSR     DLGMGR_OK_2                     | check if this editText item is enabled
        BEQ.B   CLOSEDIALOG_NO_2                | disabled - keep searching
CLOSEDIALOG_FOUND:
        MOVEQ.L #-0x2,D2                        | D2 = -2: flag that edit field was found
CLOSEDIALOG_EXIT:
        RTS                                     | return edit field status in D2

| ----------------------------------------------------------
|
| CLOSEDIALOG_CONT_6
|
| Called during boot.
CLOSEDIALOG_CONT_6:
        MOVE.L  -0x2C(A6),-(SP)                 | push saved grafPort
        _SetPort                                | restore original port
        BCLR    #0x7,(A3)                       | unlock item list handle
        RTS                                     | return with original port restored

| ----------------------------------------------------------
|
| _DisposDialog ($A983): close a dialog, dispose of its item list and record
| Pascal: PROCEDURE DisposDialog(theDialog: DialogPtr);
| Entry: 0x4(SP) = theDialog. Pushes the item list handle (items, offset $9C),
| calls _CloseDialog, disposes of the item list handle and then of the dialog
| record itself (DisposPtr), so it is meant for records allocated by the
| Dialog Manager (dStorage = NIL when the dialog was created).
|
| Called during boot.
DisposDialog:
        MOVE.L  0x4(SP),A0                      | A0 = dialog pointer from caller
        MOVE.L  0x9C(A0),-(SP)                  | push items (item list handle)
        MOVE.L  A0,-(SP)                        | push dialog pointer
        _CloseDialog                            | CloseDialog (item data, TE record, window)
        MOVE.L  (SP)+,A0                        | A0 = item list handle
        _DisposeHandle                          | dispose item list handle
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = dialog storage pointer
        _DisposePtr                             | free dialog record memory
        JMP     (A1)                            | return to caller

| ----------------------------------------------------------
|
| DISPOSEDIALOG_CONT - get the DITL of a DLOG template (not part of DisposDialog)
| Apple source name: GetLstD2 (System 7.1 DialogMgr.a)
|
| Called during boot.
| A2 = DLOG handle -> A2 = DITL handle (GetResource 'DITL', itemsID at offset
| $12). CouldDialog and FreeDialog call it through A4.
DISPOSEDIALOG_CONT:
        MOVE.L  (A2),A0                         | dereference DLOG template handle
        MOVE    0x12(A0),D0                     | D0 = DITL ID from DLOG template
        BRA.B   DISPOSEDIALOG_CONT_3            | load the DITL resource

| ----------------------------------------------------------
|
| DISPOSEDIALOG_CONT_2 - get the DITL of an ALRT template (itemsID at offset 8)
| for CouldAlert/FreeAlert (Apple: GetLstA2). DISPOSEDIALOG_EXIT is also used
| by FREEALERT_CONT_3 to get WDEF 0.
|
DISPOSEDIALOG_CONT_2:
        MOVE.L  (A2),A0                         | dereference ALRT template handle
        MOVE    0x8(A0),D0                      | D0 = DITL ID from ALRT template
DISPOSEDIALOG_CONT_3:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4449544C,-(SP)               | push type = 'DITL'
        MOVE    D0,-(SP)                        | push DITL resource ID
DISPOSEDIALOG_EXIT:
        _GetResource                            | GetResource (DITL; WDEF 0 for FREEALERT_CONT_3)
        MOVE.L  (SP)+,A2                        | A2 = resource handle
        RTS                                     | return the handle in A2

| ----------------------------------------------------------
|
| _CouldDialog ($A979)
|
CouldDialog:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        LEA.L   COULDALERT_CONT_3(PC),A2        | A2 = DLOG loader routine
        LEA.L   DISPOSEDIALOG_CONT(PC),A4       | A4 = DITL getter for DLOG
        BRA.B   COULDALERT_CONT                 | common preload logic

| CouldAlert -- _CouldAlert ($A989): PROCEDURE CouldAlert (a l ertID: I NTEGER);
| ----------------------------------------------------------
|
| _CouldAlert ($A989)
|
CouldAlert:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        LEA.L   COULDALERT_CONT_2(PC),A2        | A2 = ALRT loader routine
        LEA.L   DISPOSEDIALOG_CONT_2(PC),A4     | A4 = DITL getter for ALRT
COULDALERT_CONT:
        MOVE    0x8(A6),D0                      | D0 = resource ID
        JSR     (A2)                            | load DLOG/ALRT template
        BEQ.B   FREEALERT_ERR                   | load failed - skip preload
        ANDI.B  #0x3F,(A2)                      | make template non-purgeable
        JSR     (A4)                            | load associated DITL
        BCLR    #0x6,(A2)                       | make DITL non-purgeable
        MOVE.L  A2,A3                           | A3 = DITL handle (for item preload)
        MOVEQ.L #-0x2,D4                        | D4 = -2: preload mode (load sub-resources)
        BSR.B   FREEALERT_CONT_3                | preload WDEF and sub-resources
        BCLR    #0x6,(A2)                       | ensure WDEF stays non-purgeable
        BRA.B   FREEALERT_ERR                   | epilogue: 2 param bytes

| COULDALERT_CONT_2 -- load ALRT resource template.
| ----------------------------------------------------------
|
| COULDALERT_CONT_2
|
COULDALERT_CONT_2:
        MOVE.L  #0x414C5254,A0                  | A0 = 'ALRT' resource type
        BRA.B   COULDALERT_CONT_4               | common template loader

| ----------------------------------------------------------
|
| COULDALERT_CONT_3
|
| Called during boot.
COULDALERT_CONT_3:
        MOVE.L  #0x444C4F47,A0                  | A0 = 'DLOG' resource type
COULDALERT_CONT_4:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  A0,-(SP)                        | push resource type
        MOVE    D0,-(SP)                        | push resource ID
        _GetResource                            | load template resource
        MOVE.L  (SP),A2                         | A2 = template resource handle
        BSET    #0x7,(A2)                       | lock template handle in memory
        MOVE.L  (A2),A1                         | A1 = dereferenced template data
        TST.L   (SP)+                           | set flags from handle (Z=1 if NIL)
        RTS                                     | return handle flags in CCR

| ----------------------------------------------------------
|
| _FreeDialog ($A97A)
|
| Called during boot.
FreeDialog:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        LEA.L   COULDALERT_CONT_3(PC),A2        | A2 = DLOG loader routine
        LEA.L   DISPOSEDIALOG_CONT(PC),A4       | A4 = DITL getter for DLOG
        BRA.B   FREEALERT_CONT                  | common free logic

| FreeAlert -- _FreeAlert ($A98A): PROCEDURE FreeAlert (a l ertID : I NTEGER );
| ----------------------------------------------------------
|
| _FreeAlert ($A98A)
|
FreeAlert:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        LEA.L   COULDALERT_CONT_2(PC),A2        | A2 = ALRT loader routine
        LEA.L   DISPOSEDIALOG_CONT_2(PC),A4     | A4 = DITL getter for ALRT
FREEALERT_CONT:
        MOVE    0x8(A6),D0                      | D0 = resource ID
        JSR     (A2)                            | load DLOG/ALRT template
        BEQ.B   FREEALERT_ERR                   | not found - skip
        BCLR    #0x7,(A2)                       | unlock template handle (allow purge)
        BSR     DLGMGR_CONT_8                   | make template purgeable
        JSR     (A4)                            | load associated DITL
        BSR     DLGMGR_CONT_8                   | make DITL purgeable
        MOVE.L  A2,A3                           | A3 = DITL handle
        MOVEQ.L #-0x1,D4                        | D4 = -1: free mode (release sub-resources)
        BSR.B   FREEALERT_CONT_3                | release WDEF and sub-resources
        BSR     DLGMGR_CONT_8                   | make WDEF purgeable
FREEALERT_ERR:
        MOVEQ.L #0x2,D0                         | 2 bytes of params to clean up
FREEALERT_CONT_2:
        BRA     CLOSEDIALOG_CONT_2              | dialog epilogue

| ----------------------------------------------------------
|
| FREEALERT_CONT_3
|
| Called during boot.
FREEALERT_CONT_3:
        BSET    #0x7,(A3)                       | lock item list handle
        BSR     FINDDITEM_CONT                  | walk items (preload/free sub-resources)
        BCLR    #0x7,(A3)                       | unlock item list handle
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57444546,-(SP)               | push type = 'WDEF'
        CLR     -(SP)                           | push ID = 0 (standard window def)
        BRA     DISPOSEDIALOG_EXIT              | load WDEF resource and return

| ----------------------------------------------------------
|
| _ParamText ($A98B)
|
| Called during boot.
ParamText:
        LEA.L   (TEScrpLength).w,A1             | A1 = past end of DAStrings[3] array
        MOVEQ.L #0x3,D2                         | D2 = 3: process 4 strings (^0 to ^3)
PARAMTEXT_LOOP:
        MOVE.L  0x4(SP),D1                      | D1 = string pointer parameter
        MOVE.L  -(A1),A0                        | A0 = existing handle for this slot
        BEQ.B   PARAMTEXT_SKIP                  | NIL param - skip this slot
        MOVE.L  A0,D0                           | test existing handle
        BEQ.B   PARAMTEXT_NO                    | no old handle - just set new one
        _DisposeHandle                          | dispose previous string handle
PARAMTEXT_NO:
        MOVE.L  D1,A0                           | A0 = new string pointer
        BSR     ENTRY_5                         | convert Pascal string to handle
        MOVE.L  A0,(A1)                         | store new handle in DAStrings array
PARAMTEXT_SKIP:
        MOVE.L  (SP)+,(SP)                      | collapse stack: remove 4-byte param
        DBF     D2,PARAMTEXT_LOOP               | process next string parameter
        RTS                                     | return after processing all strings

| ErrorSound -- _ErrorSound ($A98C): PROCEDURE ErrorSound (soundProc: ProcPtr);
| ----------------------------------------------------------
|
| _ErrorSound ($A98C)
|
ErrorSound:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,(DABeeper).w              | store new beep procedure from param
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| Get D Item
|
GetDItem:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0x16(A6),A4                     | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE    0x14(A6),D3                     | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry A2 for index D3
        BEQ.B   GETDITEM_SKIP                   | item not found - skip
        MOVE.L  0x8(A6),D0                      | D0 = caller's rect pointer
        BEQ.B   GETDITEM_EMPTY                  | NIL - caller doesn't want rect
        LEA.L   0x4(A2),A0                      | A0 = item's bounding rect (offset 4)
        MOVE.L  D0,A1                           | A1 = destination rect pointer
        MOVE.L  (A0)+,(A1)+                     | copy top-left of rect
        MOVE.L  (A0)+,(A1)+                     | copy bottom-right of rect
GETDITEM_EMPTY:
        MOVE.L  0x10(A6),A0                     | A0 = caller's itemType pointer
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  0xC(A2),D0                      | D0 = item type byte
        MOVE    D0,(A0)                         | store item type as word
        MOVE.L  (A2),D5                         | D5 = item handle/proc pointer
        MOVE.L  0xC(A6),A0                      | A0 = caller's item handle pointer
        MOVE.L  D5,(A0)                         | store item handle/proc
GETDITEM_SKIP:
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0x12,D0                        | 18 bytes of params to clean up
GETDITEM_CONT:
        BRA     FREEALERT_CONT_2                | dialog epilogue

| ----------------------------------------------------------
|
| Set D Item
|
SetDItem:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0x14(A6),A4                     | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE    0x12(A6),D3                     | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry A2 for index D3
        BEQ.B   SETDITEM_SKIP                   | item not found - skip
        MOVE.L  0x8(A6),A0                      | A0 = new bounding rect pointer
        LEA.L   0x4(A2),A1                      | A1 = item's rect field
        MOVE.L  (A0)+,(A1)+                     | copy new top-left
        MOVE.L  (A0)+,(A1)+                     | copy new bottom-right
        MOVE.L  0xC(A6),(A2)                    | store new item handle/proc
        MOVE.B  0x11(A6),0xC(A2)                | store new item type byte
SETDITEM_SKIP:
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0x10,D0                        | 16 bytes of params to clean up
SETDITEM_CONT:
        BRA.B   GETDITEM_CONT                   | dialog epilogue

| ----------------------------------------------------------
|
| Get I Text
|
GetIText:
        MOVEQ.L #0x0,D1                         | D1 = 0
        SUBQ.B  #0x1,D1                         | D1 = 255 (max Pascal string length)
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0x8(A6),A1                      | A1 = destination string pointer
        MOVE.L  0xC(A6),A0                      | A0 = text handle from item
        _GetHandleSize                          | D0 = text length
        CMP.L   D1,D0                           | clamp to 255 max
        BLE.B   GETITEXT_OK                     | under limit - use as-is
        MOVE.L  D1,D0                           | cap at 255 bytes
GETITEXT_OK:
        MOVE.B  D0,(A1)+                        | store length byte in Pascal string
        MOVE.L  (A0),A0                         | dereference text handle
        _BlockMove                              | copy text data to destination
        BRA.B   SETITEXT_CONT                   | epilogue: 8 param bytes

| ----------------------------------------------------------
|
| Set I Text
|
SetIText:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0x8(A6),A0                      | A0 = Pascal string source
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  (A0)+,D0                        | D0 = string length, A0 = string data
        MOVE.L  0xC(A6),A1                      | A1 = text handle to replace
        MOVE.L  A1,D6                           | D6 = text handle (for matching later)
        _PtrToXHand                             | replace handle contents with new text
        MOVE.L  (WindowList).w,A4               | A4 = first window in window list
SETITEXT_NEXT:
        CMPI    #0x2,windowKind(A4)             | is this a dialog window?
        BNE.B   SETITEXT_SKIP                   | no - skip to next window
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVEQ.L #-0x1,D3                        | start item scan from beginning
SETITEXT_NEXT_2:
        BSR     DLGMGR_NEXT_4                   | advance to next dialog item
        BEQ.B   SETITEXT_DONE                   | no more items - done with this dialog
        CMP.L   (A2),D6                         | does this item use the same text handle?
        BNE.B   SETITEXT_NEXT_2                 | no - check next item
        CMP     editField(A4),D3                | is this the active edit field?
        BNE.B   SETITEXT_NO                     | no - just redraw the text
        MOVE.L  0xA0(A4),-(SP)                  | push TE handle
        _TECalText                              | recalculate text layout after change
SETITEXT_NO:
        TST.B   wVisible(A4)                    | is dialog window visible?
        BEQ.B   SETITEXT_DONE                   | no - skip redraw
        PEA.L   -0x28(A6)                       | push item bounding rect
        MOVE.L  (SP),-(SP)                      | duplicate rect ref for ValidRect
        _EraseRect                              | erase the item area
        BSR     DLGMGR_CONT_17                  | redraw text item content
        _ValidRect                              | mark rect as valid (no update needed)
SETITEXT_DONE:
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
SETITEXT_SKIP:
        MOVE.L  0x90(A4),A4                     | follow nextWindow link in window record
        MOVE.L  A4,D0                           | test if more windows
        BNE.B   SETITEXT_NEXT                   | yes - check next window
SETITEXT_CONT:
        MOVEQ.L #0x8,D0                         | 8 bytes of params to clean up
SETITEXT_CONT_2:
        BRA     SETDITEM_CONT                   | dialog epilogue

| ----------------------------------------------------------
|
| Sel I Text
|
SelIText:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0xE(A6),A4                      | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE    0xC(A6),D3                      | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry A2 for index D3
        MOVE.L  0x8(A6),D2                      | D2 = selEnd (low word) from params
        SWAP    D2                              | D2 high = selEnd, low = selStart
        BSR     ENTRY_2                         | select text range in edit field
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0xA,D0                         | 10 bytes of params to clean up
        BRA.B   SETITEXT_CONT_2                 | dialog epilogue

| SELITEXT_CONT -- compute inset rect on stack.
| ----------------------------------------------------------
|
| SELITEXT_CONT
|
SELITEXT_CONT:
        MOVEQ.L #-0x3,D7                        | D7 = -3: default inset for editText items
        MOVE.B  0xC(A2),D1                      | D1 = item type byte
        BTST    #0x4,D1                         | test editText flag (bit 4)
        BNE.B   SELITEXT_OK                     | editText - use -3 inset (expand rect)
        MOVEQ.L #-0x4,D7                        | D7 = -4: inset for default button
        MOVE    aDefItem(A4),D0                 | D0 = default item number
        SUBQ.W  #0x1,D0                         | convert to 0-based index
        CMP     D0,D3                           | is this the default button?
        BEQ.B   SELITEXT_OK                     | yes - use -4 inset (bold outline)
        MOVEQ.L #0x0,D7                         | not special - no inset
SELITEXT_OK:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  0x8(A2),-(SP)                   | push bottom-right of item rect
        MOVE.L  0x4(A2),-(SP)                   | push top-left of item rect
        MOVE.L  A0,-(SP)                        | push return address
        PEA.L   0x4(SP)                         | push pointer to rect on stack
        MOVE    D7,-(SP)                        | push vertical inset
        MOVE    D7,-(SP)                        | push horizontal inset
        _InsetRect                              | shrink/expand rect by inset amount
        RTS                                     | return from _InsetRect call

| ----------------------------------------------------------
|
| _HideDItem ($A827): hide an item of a dialog
| Pascal: PROCEDURE HideDItem(theDialog: DialogPtr; itemNo: INTEGER);
| Entry (after the MODALDIALOG_CONT_3 prologue): 0x8(A6) = itemNo,
|        0xA(A6) = theDialog
| No-op if the item does not exist or is already hidden (rect.left >= $2000).
| Otherwise deactivates it if it is the current editText item, erases its
| rect (enlarged as by SELITEXT_CONT), adds $4000 to rect.left and rect.right,
| activates a visible editText item if none is active, moves a control item
| along with _MoveControl and InvalRects the old area.
|
HideDItem:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0xA(A6),A4                      | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE    0x8(A6),D3                      | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry A2 for index D3
        BEQ.B   HIDEDITEM_EXIT                  | item not found - skip
        MOVE    0x6(A2),D0                      | D0 = item rect left coordinate
        CMPI    #0x2000,D0                      | is item already hidden (offset by 0x4000)?
        BLT.B   HIDEDITEM_NO                    | no - proceed to hide it
HIDEDITEM_EXIT:
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0x6,D0                         | 6 bytes of params to clean up
        BRA     SETITEXT_CONT_2                 | dialog epilogue

| ----------------------------------------------------------
|
| HIDEDITEM_NO - hide dialog item by moving it offscreen
|
HIDEDITEM_NO:
        BSR.B   SELITEXT_CONT                   | compute inset rect on stack
        CMP     editField(A4),D3                | hiding the active edit field?
        BNE.B   HIDEDITEM_SKIP                  | no - skip deactivation
        MOVEQ.L #-0x1,D3                        | deactivate edit field
        BSR     ENTRY_2                         | deselect text and reset editField
HIDEDITEM_SKIP:
        MOVE.L  A7,-(SP)                        | push pointer to inset rect on stack
        _EraseRect                              | erase item's visible area
        ADDI    #0x4000,0x6(A2)                 | move left coord offscreen (+16384)
        ADDI    #0x4000,0xA(A2)                 | move right coord offscreen (+16384)
        BSR.B   SHOWDITEM_CONT                  | activate an edit field if none; control?
        BEQ.B   HIDEDITEM_EXIT_2                | no control - skip MoveControl
        MOVE.L  (A2),-(SP)                      | push control handle
        MOVE.L  0x4(A2),-(SP)                   | push h = left, v = top (now off-screen)
        _MoveControl                            | move control to offscreen position
HIDEDITEM_EXIT_2:
        MOVE.L  A7,-(SP)                        | push pointer to rect on stack
        _InvalRect                              | invalidate old area for redraw
        ADDQ.W  #0x8,SP                         | remove 8-byte rect from stack
HIDEDITEM_SKIP_2:
        BRA.B   HIDEDITEM_EXIT                  | return via epilogue

| ----------------------------------------------------------
|
| _ShowDItem ($A828): show a dialog item that HideDItem has hidden
| Pascal: PROCEDURE ShowDItem(theDialog: DialogPtr; itemNo: INTEGER);
| Entry (after the MODALDIALOG_CONT_3 prologue): 0x8(A6) = itemNo,
|        0xA(A6) = theDialog
| No-op unless the item exists and is hidden (rect.left >= $2000). Subtracts
| $4000 from rect.left and rect.right, activates a visible editText item if
| none is active, moves a control item back with _MoveControl while its
| contrlVis is cleared (so it is not drawn now) and InvalRects the item's
| rect, so that the next update event redraws it.
|
ShowDItem:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0xA(A6),A4                      | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE    0x8(A6),D3                      | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry A2 for index D3
        BEQ.B   HIDEDITEM_SKIP_2                | item not found - skip
        MOVE    0x6(A2),D0                      | D0 = item rect left coordinate
        CMPI    #0x2000,D0                      | is item hidden (offset by 0x4000)?
        BLT.B   HIDEDITEM_SKIP_2                | no - already visible, skip
        SUBI    #0x4000,0x6(A2)                 | move left coord back onscreen (-16384)
        SUBI    #0x4000,0xA(A2)                 | move right coord back onscreen (-16384)
        BSR     SELITEXT_CONT                   | compute inset rect on stack
        BSR.B   SHOWDITEM_CONT                  | activate an edit field if none; control?
        BEQ.B   SHOWDITEM_SKIP                  | no control - skip MoveControl
        MOVE.L  (A2),A0                         | A0 = control handle
        MOVE.L  (A0),A1                         | A1 = dereferenced control record
        MOVE.B  0x10(A1),-(SP)                  | save control's visible flag
        CLR.B   0x10(A1)                        | temporarily hide control (prevent redraw)
        MOVE.L  A0,-(SP)                        | push control handle
        MOVE.L  0x4(A2),-(SP)                   | push h = left, v = top (restored)
        _MoveControl                            | move control back onscreen
        MOVE.L  (A2),A0                         | A0 = control handle again
        MOVE.L  (A0),A1                         | dereference control record
        MOVE.B  (SP)+,0x10(A1)                  | restore control's visible flag
SHOWDITEM_SKIP:
        BRA.B   HIDEDITEM_EXIT_2                | invalidate rect and return

| ----------------------------------------------------------
|
| SHOWDITEM_CONT - common part of HideDItem/ShowDItem (Apple: ShowHideCmn)
| If no editText item is active, activates the first visible one
| (CLOSEDIALOG_CONT_5) with the insertion point at its start.
| Returns Z=0 if item A2 is a control item, Z=1 if not.
|
SHOWDITEM_CONT:
        TST     editField(A4)                   | does dialog have an active edit field?
        BPL.B   SHOWDITEM_SKIP_3                | yes - leave it
        MOVE.L  A2,-(SP)                        | save current item pointer
        BSR     CLOSEDIALOG_CONT_5              | find a visible editText item
        BEQ.B   SHOWDITEM_SKIP_2                | no editText found - skip
        MOVEQ.L #0x0,D2                         | D2 = 0: selStart = selEnd = 0
        BSR     ENTRY_2                         | activate text edit for found item
SHOWDITEM_SKIP_2:
        MOVE.L  (SP)+,A2                        | restore item pointer
SHOWDITEM_SKIP_3:
        MOVE.B  0xC(A2),D1                      | D1 = item type byte
        BTST    #0x2,D1                         | test ctrlItem flag (bit 2 = control)
        RTS                                     | Z=0 if control, Z=1 if not

| ----------------------------------------------------------
|
| Find D Item
|
FindDItem:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0xC(A6),A4                      | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_3              | load and lock item list
        MOVEQ.L #-0x1,D3                        | start scan from item -1 (beginning)
        MOVE    D3,0x10(A6)                     | preset result = -1 (no item found)
FINDDITEM_NEXT:
        BSR     DLGMGR_NEXT_4                   | advance to next dialog item
        BEQ.B   FINDDITEM_EXIT                  | no more items - return result
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  0x8(A6),-(SP)                   | push test point from param
        PEA.L   -0x28(A6)                       | push item bounding rect
        _PtInRect                               | test if point is inside item rect
        TST.B   (SP)+                           | check result
        BEQ.B   FINDDITEM_NEXT                  | not inside - try next item
        MOVE    D3,0x10(A6)                     | found - store 0-based item index
FINDDITEM_EXIT:
        BClr    #0x7,(A3)                       | unlock item list handle
        BRA     SETITEXT_CONT                   | epilogue: 8 param bytes

| ----------------------------------------------------------
|
| FINDDITEM_CONT
|
| Called during boot.
FINDDITEM_CONT:
        MOVEM.L D0-D7/A0-A4,-(SP)               | save all registers
        MOVEQ.L #-0x1,D3                        | start from item -1 (beginning)
FINDDITEM_EXIT_2:
        BSR     DLGMGR_NEXT_4                   | advance to next dialog item
        BNE.B   ENTRY                           | item found - process it
        MOVEM.L (SP)+,D0-D7/A0-A4               | no more items - restore registers
        RTS                                     | return when no more items found

| ----------------------------------------------------------
|
| FINDDITEM_CONT_2 - get item handle and type from item entry
|
| Called during boot.
FINDDITEM_CONT_2:
        MOVE.L  (A2),A0                         | A0 = item handle/proc pointer
        MOVE.B  0xC(A2),D0                      | D0 = item type byte
        RTS                                     | return item handle in A0 and type in D0

| --------------------------------------------------------------------------
| Dialog Manager -- internal routines
|
| The subroutines called by the public traps above: item initialization
| from the DITL, item drawing and disposal, event dispatch, edit-field
| switching, hit testing, ParamText substitution and default-button
| outlining.
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
| DITL Item Initialization - called from the FINDDITEM_CONT loop above
| Decodes item type and loads/creates the appropriate resource or control.
| Entry: A2 = ptr to DITL item entry, D4 = mode (0=init, 1=draw, 2=hitTest)
| A4 = DialogPtr, D0 = item type byte from itmType(A2)
| ============================================================
ENTRY:
        BSR.B   FINDDITEM_CONT_2                | get item handle and type byte into D0
        PEA.L   FINDDITEM_EXIT_2(PC)            | push return addr for FINDDITEM_CONT's item loop
        CMPI    #0x2,D4                         | D4: 0=init, 1=draw, 2=hitTest, 3=updtDraw
        BGT     DLGMGR_FOUND                    | D4>2: hit test item rect vs update rgn
        BEQ     DLGMGR_CONT_24                  | D4=2: dispose item resources
        TST     D4                              | check remaining D4 action codes (0, 1, -1)
        BEQ.B   DLGMGR_CONT_9                   | D4=0: initialize item from DITL data
        BGT     DLGMGR_CONT_17                  | D4=1: draw a single item
        BTST    #0x2,D0                         | D4=-1: load resource for item
        BNE.B   DLGMGR_CONT                     | bit 2 set = ctrlItem, need CNTL/CDEF
        ROXR    #0x7,D0                         | shift iconItem bit (bit 5) into carry
        BMI.B   DLGMGR_CONT_4                   | bit 6 (picItem) set = load ICON resource
        BCS.B   DLGMGR_CONT_5                   | bit 5 (iconItem) set = load PICT resource
        RTS                                     | statText/editText/userItem: no resource

| ----------------------------------------------------------
| Load resource handle for a control item (ctrlItem)
| Determines CNTL vs CDEF resource type from control subtype bits.
| ----------------------------------------------------------
DLGMGR_CONT:
        ANDI    #0x3,D0                         | mask control subtype (btnCtrl..resCtrl)
        CMPI    #0x3,D0                         | resCtrl (3) = control from resource
        BNE.B   DLGMGR_CONT_3                   | btnCtrl/chkCtrl/radCtrl: use CDEF
        PEA.L   DLGMGR_CONT_2(PC)               | push callback to read CNTL's defProc ID
        MOVE.L  #0x434E544C,D1                  | 'CNTL' resource type
        BRA.B   DLGMGR_CONT_6                   | go load 'CNTL' resource using DITL ID

| ----------------------------------------------------------
| DLGMGR_CONT_2 - callback for resCtrl: extract CDEF proc ID from CNTL resource
| ----------------------------------------------------------
DLGMGR_CONT_2:
        MOVE.L  (A2),A1                         | dereference CNTL handle
        MOVE    0x10(A1),D0                     | D0 = procID (CNTL template +$10)
DLGMGR_CONT_3:
        MOVE.L  #0x43444546,D1                  | 'CDEF' resource type
        BRA.B   DLGMGR_CONT_7                   | load the CDEF resource

| ----------------------------------------------------------
| Load ICON resource for an iconItem
| ----------------------------------------------------------
DLGMGR_CONT_4:
        MOVE.L  #0x49434F4E,D1                  | 'ICON' resource type
        BRA.B   DLGMGR_CONT_6                   | go load 'ICON' resource using DITL ID

| ----------------------------------------------------------
| Load PICT resource for a picItem
| ----------------------------------------------------------
DLGMGR_CONT_5:
        MOVE.L  #0x50494354,D1                  | 'PICT' resource type
DLGMGR_CONT_6:
        MOVE    0xE(A2),D0                      | get resource ID from DITL item data
DLGMGR_CONT_7:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  D1,-(SP)                        | push resource type
        MOVE    D0,-(SP)                        | push resource ID
        _GetResource                            | load the requested resource
        MOVE.L  (SP)+,A2                        | A2 = resource handle
        CMPI    #-0x1,D4                        | D4=-1: just loading, check purgeability
        BEQ.B   DLGMGR_CONT_8                   | go check/mark purgeable state
        BCLR    #0x6,(A2)                       | clear handle's purgeable flag for use
        RTS                                     | return with resource handle in A2

| ----------------------------------------------------------
| DLGMGR_CONT_8 - mark handle purgeable if the resource itself is purgeable
| Called with D4=-1 during pre-load to preserve resource's purgeable attr.
| ----------------------------------------------------------
DLGMGR_CONT_8:
        SUBQ.W  #0x2,SP                         | space for GetResAttrs result word
        MOVE.L  A2,-(SP)                        | push resource handle
        _GetResAttrs                            | get resource attributes word
        MOVE    (SP)+,D0                        | pop attributes word into D0
        BTST    #0x5,D0                         | test resPurgeable attribute
        BEQ.B   DLGMGR_NO                       | not purgeable: leave handle flag clear
        BSET    #0x6,(A2)                       | mark master pointer as purgeable
DLGMGR_NO:
        RTS                                     | return from purgeable check

| ----------------------------------------------------------
| Initialize item from DITL data (D4=0)
| A0 = item handle from DITL entry, D0 = item type byte
| If handle already set (non-nil), item was pre-initialized - skip.
| ----------------------------------------------------------
DLGMGR_CONT_9:
        MOVE.L  A0,D1                           | test if item handle already exists
        BEQ.B   DLGMGR_EMPTY                    | nil: need to create from DITL data
        RTS                                     | already initialized, nothing to do

| ----------------------------------------------------------
| Create item handle/control from DITL data based on item type.
| Dispatches by testing type bits: ctrlItem, iconItem, picItem,
| statText/editText.
| ----------------------------------------------------------
DLGMGR_EMPTY:
        BTst    #0x2,D0                         | test ctrlItem bit
        BNE.B   DLGMGR_CONT_14                  | ctrlItem: create control
        ROXR    #0x5,D0                         | shift statText (bit 3) into X/C flags
        BCS.B   DLGMGR_CONT_10                  | statText: copy text data to handle
        BMI.B   DLGMGR_CONT_10                  | editText: copy text data to handle
        ROXR    #0x2,D0                         | shift iconItem/picItem bits
        BMI.B   DLGMGR_CONT_11                  | iconItem: load ICON resource
        BCS.B   DLGMGR_CONT_12                  | picItem: load PICT resource
        RTS                                     | userItem: handle stays nil

| ----------------------------------------------------------
| Initialize statText or editText: copy inline text from DITL to a handle
| DITL item data: length byte at +13(A2), text bytes follow
| ----------------------------------------------------------
DLGMGR_CONT_10:
        LEA.L   0xD(A2),A0                      | point to data length byte in DITL entry
        MOVEQ.L #0x0,D0                         | clear upper bytes of length register
        MOVE.B  (A0)+,D0                        | D0 = text length, A0 -> text data
        _PtrToHand                              | create handle with copy of text
        MOVE.L  A0,-(SP)                        | push text handle (result in A0)
        BRA.B   DLGMGR_CONT_16                  | store handle in item entry

| ----------------------------------------------------------
| Initialize iconItem: load ICON resource by ID from DITL data
| ----------------------------------------------------------
DLGMGR_CONT_11:
        MOVE.L  #0x49434F4E,D0                  | 'ICON' resource type
        BRA.B   DLGMGR_CONT_13                  | go load 'ICON' resource

| ----------------------------------------------------------
| Initialize picItem: load PICT resource by ID from DITL data
| ----------------------------------------------------------
DLGMGR_CONT_12:
        MOVE.L  #0x50494354,D0                  | 'PICT' resource type
DLGMGR_CONT_13:
        SUBQ.W  #0x4,SP                         | space for GetResource handle result
        MOVE.L  D0,-(SP)                        | push resource type
        MOVE    0xE(A2),-(SP)                   | push resource ID from DITL item data
        _GetResource                            | load the 'ICON' or 'PICT' resource
        BRA.B   DLGMGR_CONT_16                  | store resource handle in item entry

| ----------------------------------------------------------
| Initialize ctrlItem: create control from resource or inline data.
| D0 bits 0-1 = subtype: btnCtrl(0), chkCtrl(1), radCtrl(2), resCtrl(3)
| ----------------------------------------------------------
DLGMGR_CONT_14:
        ANDI    #0x3,D0                         | isolate control subtype
        CMPI    #0x3,D0                         | resCtrl?
        BNE.B   DLGMGR_NO_2                     | no: create standard btn/chk/rad control
        SUBQ.W  #0x4,SP                         | space for GetNewControl result
        MOVE    0xE(A2),-(SP)                   | push CNTL resource ID from DITL data
        MOVE.L  A4,-(SP)                        | push owning dialog window
        _GetNewControl                          | create control from CNTL resource
        MOVE.L  (SP),-(SP)                      | push control handle for MoveControl
        MOVE.L  0x4(A2),-(SP)                   | push display rect top-left from DITL
        _MoveControl                            | position control at item's display rect
        BRA.B   DLGMGR_CONT_15                  | go store control handle and validate

| ----------------------------------------------------------
| Create standard button/checkbox/radio control from DITL inline data.
| Builds NewControl params: owner, rect, title, visible, value=1,
| min=0, procID=subtype*16, refCon=0.
| ----------------------------------------------------------
DLGMGR_NO_2:
        SUBQ.W  #0x4,SP                         | space for NewControl result
        MOVE.L  A4,-(SP)                        | push owning window (DialogPtr)
        PEA.L   -0x28(A6)                       | push item display rect
        PEA.L   0xD(A2)                         | push title string (from DITL item data)
        ST.B    -(SP)                           | visible = true ($FF)
        CLR.L   -(SP)                           | value = 0, min = 0
        MOVE    #0x1,-(SP)                      | max = 1
        MOVE    D0,-(SP)                        | procID = subtype (0=pushBut,1=chkBox,2=radio)
        CLR.L   -(SP)                           | refCon = 0
        _NewControl                             | create standard system control
DLGMGR_CONT_15:
        PEA.L   -0x28(A6)                       | validate item rect (no redraw needed)
        _ValidRect                              | validate the item's display rect
DLGMGR_CONT_16:
        MOVE.L  (SP)+,(A2)                      | store new handle into itmHndl field
        RTS                                     | return from item initialization

| ----------------------------------------------------------
| Hit test: check if item rect intersects update region (D4>2)
| Builds a temp rect from item's display rect, insets by -4 pixels
| (to include the 3-pixel frame around editText items), then tests
| intersection with the update region passed in 0x8(A6).
| Returns via BNE to DLGMGR_CONT_18 (which falls into DLGMGR_CONT_17 to draw item).
| ----------------------------------------------------------
DLGMGR_FOUND:
        MOVE.L  0x8(A2),-(SP)                   | push item rect bottom-right
        MOVE.L  0x4(A2),-(SP)                   | push item rect top-left
        MOVE.L  A7,-(SP)                        | push ptr to temp rect on stack
        MOVE.L  #0xFFFCFFFC,-(SP)               | inset by (-4,-4) to include frame
        _InsetRect                              | inset temp rect to include focus frame
        SUBQ.W  #0x2,SP                         | space for RectInRgn boolean result
        PEA.L   0x2(SP)                         | push ptr to temp rect
        MOVE.L  0x8(A6),-(SP)                   | push update region handle
        _RectInRgn                              | does item rect intersect update rgn?
        TST.B   (SP)+                           | check RectInRgn boolean result
        ADDQ.W  #0x8,SP                         | clean up temp rect from stack
        BNE.B   DLGMGR_CONT_18                  | intersects: go draw this item
        RTS                                     | no intersection: skip this item

| ----------------------------------------------------------
| DLGMGR_CONT_17 - Draw a single dialog item (D4=1)
| Dispatches by item type to draw controls, text, icons, pictures,
| or call userItem drawing procedure.
| ----------------------------------------------------------
DLGMGR_CONT_17:
        BSR     FINDDITEM_CONT_2                | get item handle (A0) and type (D0)
        ANDI.B  #0x7F,D0                        | strip itemDisable bit
        BEQ.B   DLGMGR_CONT_19                  | userItem (type 0): call drawing proc
        BSR     DLGMGR_CONT_34                  | check if item rect intersects portRect
        BEQ.B   DLGMGR_SKIP                     | not visible: skip drawing
DLGMGR_CONT_18:
        BSR     FINDDITEM_CONT_2                | re-fetch handle and type for drawing
        BTST    #0x2,D0                         | ctrlItem?
        BNE.B   DLGMGR_SKIP_2                   | controls drawn by DrawControls, skip here
        ROXR    #0x5,D0                         | shift statText/editText bits into flags
        BCS.B   DLGMGR_CONT_22                  | statText: draw text item
        BMI.B   DLGMGR_CONT_22                  | editText: draw text item
        ROXR    #0x2,D0                         | shift iconItem/picItem bits
        BMI.B   DLGMGR_CONT_20                  | iconItem: PlotIcon
        BCS.B   DLGMGR_CONT_21                  | picItem: DrawPicture
DLGMGR_CONT_19:
        MOVE.L  (A2),D0                         | get userItem's drawing proc pointer
        BEQ.B   DLGMGR_SKIP                     | nil proc: nothing to draw
        MOVE.L  A4,-(SP)                        | push DialogPtr as 1st param
        MOVE    D3,-(SP)                        | push 0-based item number
        ADDQ.W  #0x1,(SP)                       | push 1-based item number as 2nd param
        MOVE.L  D0,A0                           | A0 = userItem drawing proc pointer
        JSR     (A0)                            | call userItem drawing procedure
DLGMGR_SKIP:
        RTS                                     | return from userItem drawing

| ----------------------------------------------------------
| Draw iconItem: load and plot icon in item's display rect
| ----------------------------------------------------------
DLGMGR_CONT_20:
        PEA.L   -0x28(A6)                       | push item display rect
        MOVE.L  (A2),-(SP)                      | push icon handle
        MOVE.L  (SP),-(SP)                      | dup handle for LoadResource
        _LoadResource                           | ensure icon data is in memory
        _PlotIcon                               | draw icon in display rect
        RTS                                     | return from icon drawing

| ----------------------------------------------------------
| Draw picItem: load and draw picture in item's display rect
| ----------------------------------------------------------
DLGMGR_CONT_21:
        MOVE.L  (A2),-(SP)                      | push picture handle
        MOVE.L  (SP),-(SP)                      | dup handle for LoadResource
        _LoadResource                           | ensure picture data is in memory
        PEA.L   -0x28(A6)                       | push item display rect
        _DrawPicture                            | draw picture scaled to display rect
DLGMGR_SKIP_2:
        RTS                                     | return from picture drawing

| ----------------------------------------------------------
| Draw statText or editText item.
| If this is the active editText field, erase and TEUpdate.
| Otherwise, perform ParamText substitution (^0..^3) then TextBox.
| After drawing, if editText, draw 3-pixel frame around display rect.
| ----------------------------------------------------------
DLGMGR_CONT_22:
        SMI.B   D6                              | D6 = $FF if editText (bit 4 set), 0 if statText
        CMP     editField(A4),D3                | is this the active edit field?
        BNE.B   DLGMGR_NO_3                     | no: draw with ParamText substitution
        PEA.L   -0x28(A6)                       | push display rect
        MOVE.L  (SP),-(SP)                      | dup for EraseRect
        _EraseRect                              | clear the edit field area
        MOVE.L  0xA0(A4),-(SP)                  | push TEHandle (teHandle field)
        _TEUpdate                               | redraw active TextEdit content
DLGMGR_CONT_23:
        TST.B   D6                              | was this an editText item?
        BNE.B   DLGMGR_SKIP_3                   | no (statText): skip frame drawing
        LEA.L   -0x28(A6),A0                    | point to item display rect
        MOVEQ.L #0x1,D0                         | pen width = 1 (for non-default editText frame)
        MOVEQ.L #0x1,D1                         | pen height = 1
        MOVEQ.L #0x3,D2                         | inset = 3 pixels outside
        BSR     ENTRY_4                         | draw frame rect around editText item
DLGMGR_SKIP_3:
        RTS                                     | return from editText frame drawing

| ----------------------------------------------------------
| Draw statText/editText with ParamText (^0..^3) substitution.
| Makes a copy of the text handle, scans for '^' markers,
| substitutes from DAStrings[0..3], then draws via TextBox.
| ----------------------------------------------------------
DLGMGR_NO_3:
        MOVEM.L D2-D6/A2-A4,-(SP)               | save regs (we reuse A2-A4, D2-D6)
        MOVE.L  (A2),A0                         | get text handle
        _HandToHand                             | make working copy (A0 = new handle)
        MOVE.L  A0,A2                           | A2 = working text handle
        MOVEQ.L #0x0,D3                         | D3 = scan offset into text
DLGMGR_EMPTY_2:
        MOVE.L  A2,A0                           | get handle for size check
        _GetHandleSize                          | D0 = total text length
        MOVE.L  (A0),A4                         | A4 = dereferenced text pointer
        ADDA.L  D3,A4                           | advance to current scan position
        MOVE.L  D0,D5                           | D5 = remaining bytes to scan
        SUB.L   D3,D5                           | subtract current offset for remaining bytes
        BRA.B   DLGMGR_LOOP_2                   | enter scan loop

| ----------------------------------------------------------
| Scan for '^' (0x5E) character - ParamText substitution marker.
| Text format: ^0, ^1, ^2, ^3 replaced by DAStrings[0..3].
| ----------------------------------------------------------
DLGMGR_LOOP:
        CMPI.B  #0x5E,(A4)+                     | is this char '^'?
        BEQ.B   DLGMGR_FOUND_2                  | found: go substitute
DLGMGR_SKIP_4:
        ADDQ.W  #0x1,D3                         | advance scan offset
DLGMGR_LOOP_2:
        DBF     D5,DLGMGR_LOOP                  | continue scanning
        BSET    #0x7,(A2)                       | lock the text handle before drawing
        MOVE.L  (A2),-(SP)                      | push text pointer
        MOVE.L  A2,A0                           | A0 = substituted text handle
        _GetHandleSize                          | get length of substituted text
        MOVE.L  D0,-(SP)                        | push text length
        PEA.L   -0x28(A6)                       | push display rect
        CLR     -(SP)                           | justification = teJustLeft (0)
        _TETextBox                              | draw substituted text in rect
        MOVE.L  A2,A0                           | A0 = working text handle to dispose
        _DisposeHandle                          | free working copy
        MOVEM.L (SP)+,D2-D6/A2-A4               | restore regs
        BRA.B   DLGMGR_CONT_23                  | go draw editText frame if needed

| ----------------------------------------------------------
| Found '^' marker - look up which DAStrings[] entry to substitute.
| DAStrings (at DABeeper+4) holds 4 handles for ^0..^3 replacement text.
| D6 scans ASCII '0'..'3' (0x30..0x33) to match char after '^'.
| ----------------------------------------------------------
DLGMGR_FOUND_2:
        LEA.L   (DABeeper).w,A3                 | A3 = base of DABeeper (before DAStrings)
        MOVE.B  #0x2F,D6                        | D6 = '0'-1; will increment to '0' first
DLGMGR_NEXT:
        ADDQ.L  #0x4,A3                         | advance to next DAStrings[] entry
        ADDQ.W  #0x1,D6                         | D6 = next digit char ('0','1','2','3')
        CMPI.B  #0x34,D6                        | past '3'? (checked all 4 substitutions)
        BEQ.B   DLGMGR_SKIP_4                   | no match: skip this '^', continue scan
        CMP.B   (A4),D6                         | does digit match char after '^'?
        BNE.B   DLGMGR_NEXT                     | no: try next DAStrings entry
        MOVEQ.L #0x0,D0                         | D0 = replacement string length (0 if nil)
        MOVE.L  (A3),D4                         | D4 = DAStrings[n] handle
        BEQ.B   DLGMGR_EMPTY_3                  | nil handle: replace with empty string
        MOVE.L  D4,A0                           | A0 = replacement string handle
        BSET    #0x7,(A0)                       | lock the replacement string handle
        MOVE.L  (A0),A0                         | dereference to get string pointer
        MOVE.B  (A0)+,D0                        | D0 = Pascal string length byte
DLGMGR_EMPTY_3:
        SUBQ.W  #0x4,SP                         | space for Munger result
        MOVE.L  A2,-(SP)                        | push target handle (working text copy)
        MOVE.L  D3,-(SP)                        | push offset of '^' in text
        CLR.L   -(SP)                           | push nil for search ptr (delete mode)
        MOVE.L  #0x2,-(SP)                      | push 2 bytes to replace ('^' + digit)
        MOVE.L  A0,-(SP)                        | push replacement string pointer
        MOVE.L  D0,-(SP)                        | push replacement string length
        _Munger                                 | replace "^n" with DAStrings[n] text
        MOVE.L  (SP)+,D0                        | D0 = new match offset from Munger
        TST.L   D4                              | was DAStrings handle non-nil?
        BEQ.B   DLGMGR_EMPTY_2                  | nil: no unlock needed, rescan
        MOVE.L  D4,A0                           | A0 = replacement string handle to unlock
        _HUnlock                                | unlock the replacement string handle
        BRA.B   DLGMGR_EMPTY_2                  | rescan from current position

| ----------------------------------------------------------
| Dispose item resources (D4=2).
| Frees handles for text/icon/picture items, disposes controls.
| Item type dispatch: userItem=RTS, ctrlItem=DisposControl,
| statText/editText=DisposeHandle, iconItem/picItem=DisposeHandle.
| ----------------------------------------------------------
DLGMGR_CONT_24:
        ROR     #0x3,D0                         | shift ctrlItem bit into carry
        BCS     DLGMGR_SKIP_2                   | ctrlItem: skip (disposed via DisposControl)
        ROXR    #0x2,D0                         | shift statText/editText bits
        BCS.B   DLGMGR_CONT_26                  | statText: dispose text handle
        BMI.B   DLGMGR_CONT_26                  | editText: dispose text handle
DLGMGR_CONT_25:
        CLR.L   (A2)                            | clear item handle after disposal
        RTS                                     | return from statText/editText disposal

| ----------------------------------------------------------
| Dispose text or icon/picture handle
| ----------------------------------------------------------
DLGMGR_CONT_26:
        _DisposeHandle                          | free the text/icon/picture handle
        BRA.B   DLGMGR_CONT_25                  | clear item handle field

| ----------------------------------------------------------
| DLGMGR_CONT_27 - Dispose a control item (called from CloseDialog's item loop)
| ----------------------------------------------------------
DLGMGR_CONT_27:
        MOVE.L  A0,-(SP)                        | push control handle
        _DisposeControl                         | free control and its data
        BRA.B   DLGMGR_CONT_25                  | clear item handle field

| ----------------------------------------------------------
| Handle activate/deactivate event for dialog's TextEdit field.
| Switches port to target dialog, activates/deactivates its TE,
| then restores original port. Event modifiers bit 0 = activeFlag.
| ----------------------------------------------------------
DLGMGR_CONT_28:
        MOVE.L  -0x4A(A6),A0                    | get event message (dialog window ptr)
        TST     0xA4(A0)                        | check editField: -1 = no edit field
        BMI.B   DLGMGR_EXIT                     | no edit field: nothing to activate
        MOVE.L  0xA0(A0),-(SP)                  | push teHandle for TE call
        MOVE.L  A0,-(SP)                        | push dialog as port
        _SetPort                                | switch to dialog's grafPort
        BTST    #0x0,-0x3D(A6)                  | test activeFlag in event modifiers
        BEQ.B   DLGMGR_NO_4                     | not active: deactivate TE
        _TEActivate                             | show insertion point / selection
        BRA.B   DLGMGR_SKIP_5                   | skip deactivation

| ----------------------------------------------------------
DLGMGR_NO_4:
        _TEDeactivate                           | hide insertion point / selection
DLGMGR_SKIP_5:
        MOVE.L  A4,-(SP)                        | restore original port
        _SetPort                                | restore original grafPort
        BRA.B   DLGMGR_EXIT                     | return itemHit = -1

| ----------------------------------------------------------
| RETURNS_15 - Main dialog event dispatcher
| Called from DialogSelect to process one event in a dialog.
| Dispatches on event.what from -0x4C(A6):
| 1=mouseDown, 3=keyDown, 5=keyDown(autoKey), 6=updateEvt,
| 8=activateEvt, else=nullEvent (TEIdle for caret blink).
| Returns: D3 = item number hit (0-based), or -1 if no item.
| ----------------------------------------------------------
RETURNS_15:
        MOVE    -0x4C(A6),D0                    | get event.what
        SUBQ.W  #0x1,D0                         | test for mouseDown (1)
        BEQ     DLGMGR_CONT_32                  | mouseDown (1): handle click
        SUBQ.W  #0x2,D0                         | test for keyDown (3)
        BEQ.B   DLGMGR_CONT_30                  | keyDown (3): handle keystroke
        SUBQ.W  #0x2,D0                         | test for autoKey (5)
        BEQ.B   DLGMGR_CONT_30                  | autoKey (5): handle repeated key
        SUBQ.W  #0x1,D0                         | test for updateEvt (6)
        BEQ.B   DLGMGR_CONT_29                  | updateEvt (6): redraw dialog
        SUBQ.W  #0x2,D0                         | test for activateEvt (8)
        BEQ.B   DLGMGR_CONT_28                  | activateEvt (8): activate/deactivate TE
        TST     editField(A4)                   | nullEvent: blink caret if edit field active
        BMI.B   DLGMGR_EXIT                     | no edit field: return -1
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEIdle                                 | blink insertion point caret
DLGMGR_EXIT:
        MOVEQ.L #-0x1,D3                        | return itemHit = -1 (no item)
        RTS                                     | return to DialogSelect caller

| ----------------------------------------------------------
| Handle updateEvt: redraw entire dialog within update region
| ----------------------------------------------------------
DLGMGR_CONT_29:
        MOVE.L  A4,-(SP)                        | push DialogPtr for EndUpdate
        MOVE.L  (SP),-(SP)                      | dup for DrawDialog
        MOVE.L  (SP),-(SP)                      | dup for BeginUpdate
        _BeginUpDate                            | clip to update region
        _DrawDialog                             | redraw all items
        _EndUpDate                              | restore clipping
        BRA.B   DLGMGR_EXIT                     | return itemHit = -1

| ----------------------------------------------------------
| Handle keyDown/autoKey: dispatch to TEKey or Tab-to-next-field.
| event.message low byte at -0x47(A6) = character code.
| ----------------------------------------------------------
DLGMGR_CONT_30:
        MOVE.B  -0x47(A6),D1                    | get typed character from event.message
        CMPI.B  #0x9,D1                         | Tab key?
        BEQ.B   DLGMGR_NEXT_2                   | yes: advance to next editText field
        MOVE    editField(A4),D3                | get active edit field index
        BMI.B   DLGMGR_EXIT                     | no edit field: ignore keystroke
        MOVE    D1,-(SP)                        | push character for TEKey
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEKey                                  | insert typed character into TE
        BRA.B   DLGMGR_EXIT_2                   | return current edit field as itemHit

| ----------------------------------------------------------
| Tab key: find next editText item in DITL and switch to it.
| Wraps around from last editText to first editText.
| ----------------------------------------------------------
DLGMGR_NEXT_2:
        CLR     D5                              | D5 = wrap flag (0=first pass, -1=wrapped)
        MOVE    editField(A4),D3                | start from current edit field
        BSR     DLGMGR_OK_3                     | position to current item in DITL
DLGMGR_SKIP_6:
        BSR     DLGMGR_NEXT_4                   | advance to next DITL item
        BEQ.B   DLGMGR_CONT_31                  | past end of list: try wrapping
        CMP     editField(A4),D3                | back to where we started?
        BEQ.B   DLGMGR_EXIT                     | yes: only one editText, no switch
        BTST    #0x4,0xC(A2)                    | test editText bit in item type
        BEQ.B   DLGMGR_SKIP_6                   | not editText: keep scanning
        BSR     DLGMGR_OK_2                     | check if item rect is on screen
        BEQ.B   DLGMGR_SKIP_6                   | off screen (hidden item): skip it
        MOVE.L  #0x7FFF,D2                      | select all text in new field
        BSR     ENTRY_2                         | switch to this edit field
DLGMGR_EXIT_2:
        BRA.B   DLGMGR_EXIT_4                   | return new edit field as itemHit

| ----------------------------------------------------------
| Reached end of DITL during Tab scan - wrap to beginning.
| Only wraps once (D5 tracks whether we already wrapped).
| ----------------------------------------------------------
DLGMGR_CONT_31:
        TST     D5                              | already wrapped once?
        BMI.B   DLGMGR_EXIT                     | yes: no editText found, give up
        MOVEQ.L #-0x1,D5                        | set wrap flag
        MOVEQ.L #-0x1,D3                        | reset to before first item
        TST     editField(A4)                   | is there any edit field at all?
        BPL.B   DLGMGR_SKIP_6                   | yes: scan from start of DITL
DLGMGR_EXIT_3:
        BRA.B   DLGMGR_EXIT                     | no edit fields at all: return -1

| ----------------------------------------------------------
| Handle mouseDown: convert click to local coords, find which
| DITL item was clicked, then dispatch by item type.
| ----------------------------------------------------------
DLGMGR_CONT_32:
        MOVE.L  -0x42(A6),-0x1C(A6)             | copy event.where to local point
        PEA.L   -0x1C(A6)                       | push ptr to local point
        _GlobalToLocal                          | convert click point to dialog coords
        MOVEQ.L #-0x1,D3                        | start before first item
DLGMGR_NEXT_3:
        BSR     DLGMGR_NEXT_4                   | advance to next DITL item
        BEQ.B   DLGMGR_EXIT_3                   | past end: no item hit, return -1
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        PEA.L   -0x28(A6)                       | push item display rect
        _PtInRect                               | is click inside this item?
        TST.B   (SP)+                           | did click intersect item rect?
        BEQ.B   DLGMGR_NEXT_3                   | not in this item: try next
        BTST    #0x2,0xC(A2)                    | is this a ctrlItem?
        BEQ.B   DLGMGR_NO_5                     | no: check for editText click
        SUBQ.W  #0x2,SP                         | space for FindControl result
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        MOVE.L  A4,-(SP)                        | push dialog window
        PEA.L   -0x18(A6)                       | push ptr for control handle result
        _FindControl                            | find which control was clicked
        MOVE    (SP)+,D0                        | D0 = part code (0=none)
        BEQ.B   DLGMGR_EXIT_3                   | not in a control: return -1
        SUBQ.W  #0x2,SP                         | space for TrackControl result
        MOVE.L  -0x18(A6),-(SP)                 | push control handle
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        MOVE.L  (MinusOne).w,-(SP)              | push nil actionProc (-1 = default)
        _TrackControl                           | track mouse until released
        TST     (SP)+                           | was control actually clicked?
        BEQ.B   DLGMGR_EXIT_3                   | no: mouse released outside, return -1
DLGMGR_EXIT_4:
        BRA.B   DLGMGR_EXIT_5                   | control was clicked: return item

| ----------------------------------------------------------
| Click was in a non-control item: check if editText.
| If editText, switch edit field and pass click to TEClick.
| ----------------------------------------------------------
DLGMGR_NO_5:
        BTst    #0x4,0xC(A2)                    | test editText bit in item type
        BEQ.B   DLGMGR_EXIT_5                   | not editText: return this item as hit
        CMP     editField(A4),D3                | clicking in already-active field?
        BEQ.B   DLGMGR_OK                       | yes: just pass to TEClick
        MOVEQ.L #0x0,D2                         | D2=0: place insertion point, don't select
        BSR.B   ENTRY_2                         | switch to clicked edit field
DLGMGR_OK:
        TST     editField(A4)                   | is there an active edit field now?
        BMI.B   DLGMGR_EXIT_5                   | no: skip TEClick
        MOVE.L  -0x1C(A6),-(SP)                 | push click point
        BTST    #0x1,-0x3E(A6)                  | test shiftKey in event modifiers
        SNE.B   -(SP)                           | push extend flag (true if Shift held)
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEClick                                | handle text selection/insertion
DLGMGR_EXIT_5:
        BTst    #0x7,0xC(A2)                    | test itemDisable bit
        BNE     DLGMGR_EXIT_3                   | disabled item: return -1 (ignore click)
        ADDQ.W  #0x1,D3                         | convert 0-based to 1-based item number
        RTS                                     | return D3 = item number hit

| ----------------------------------------------------------
| ENTRY_2 - Switch active edit field.
| Deactivates current TE (scrolling it back to origin), calls DLGMGR_CONT_33
| to install new field's text into TE, then activates TE.
| Entry: D3 = new field index (0-based), D2 = selection range.
| ----------------------------------------------------------
| Called by: SelIText, HIDEDITEM_NO, SHOWDITEM_CONT, DLGMGR_SKIP_6, DLGMGR_NO_5
ENTRY_2:
        TST     editField(A4)                   | is there a current edit field?
        BMI.B   DLGMGR_SKIP_7                   | no current field: skip deactivation
        MOVE.L  0xA0(A4),A0                     | get teHandle
        MOVE.L  (A0),A0                         | dereference to TERec
        MOVE.L  0x8(A0),-(SP)                   | push teViewRect.topLeft
        MOVE.L  (A0),-(SP)                      | push teDestRect.topLeft
        PEA.L   0x4(SP)                         | push ptr to delta point on stack
        _SubPt                                  | delta = viewRect.topLeft - destRect.topLeft
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEScroll                               | scroll TE back to origin before switching
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEDeactivate                           | hide caret/selection in old field
DLGMGR_SKIP_7:
        BSR.B   DLGMGR_CONT_33                  | install new field's text into shared TERec
        TST     editField(A4)                   | did DLGMGR_CONT_33 set a valid edit field?
        BMI.B   DLGMGR_SKIP_8                   | -1 = no edit field: skip activation
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEActivate                             | show caret/selection in new field
DLGMGR_SKIP_8:
        RTS                                     | return from edit field setup

| ----------------------------------------------------------
| ENTRY_3 - Check if edit field changed, then install new field.
| Entry: D3 = target field index, D2 = selection range.
| Falls through to DLGMGR_CONT_33 if field is different.
| ----------------------------------------------------------
ENTRY_3:
        CMP     editField(A4),D3                | is target same as current field?
        BEQ.B   DLGMGR_EXIT_6                   | yes: no switch needed, return
| DLGMGR_CONT_33 -- install new field's text into shared TERec.
DLGMGR_CONT_33:
        MOVE.L  (A2),D0                         | D0 = item handle (text handle for editText)
        BLE.B   DLGMGR_EXIT_6                   | nil or negative: no valid text, return
        MOVE    D3,editField(A4)                | set new active edit field index
        BMI.B   DLGMGR_EXIT_6                   | -1 = no field: just clear and return
        MOVE.L  0xA0(A4),A0                     | A0 = teHandle from DialogRecord
        MOVE.L  (A0),A1                         | A1 = dereferenced TERec pointer
        MOVE.L  D0,0x3E(A1)                     | store text handle in TERec.hText (+$3E)
        MOVEQ.L #-0x2,D0                        | sentinel value: don't change selection
        CMP.L   D0,D2                           | D2 = -2 means keep existing selection
        BEQ.B   DLGMGR_SKIP_9                   | skip selection update
        MOVE.L  D2,0x20(A1)                     | set TERec.selStart/selEnd (+$20, packed)
DLGMGR_SKIP_9:
        LEA.L   (A1),A0                         | A0 = TERec base for destRect/viewRect
        MOVE.L  -0x28(A6),(A0)+                 | copy item rect top-left to destRect.topLeft
        MOVE.L  -0x24(A6),(A0)+                 | copy item rect bot-right to destRect.botRight
        MOVE.L  -0x28(A6),(A0)+                 | copy item rect top-left to viewRect.topLeft
        MOVE.L  -0x24(A6),(A0)+                 | copy item rect bot-right to viewRect.botRight
        ST.B    0x32(A1)                        | TERec clickLoc (+$32) := $FFxx: no double click
        LEA.L   (A1),A0                         | A0 = TERec.destRect.top again
        MOVEQ.L #0x2,D0                         | D0 = 2 (initial line height offset)
        ADD     (A0)+,D0                        | D0 += destRect.top; A0 -> destRect.left
        ADD     0x18(A1),D0                     | D0 += TERec.lineHeight (+$18)
        MOVE    (A0)+,D1                        | D1 = destRect.left; A0 -> destRect.bottom
        CMP     (A0)+,D0                        | compare top+lineHeight+2 vs destRect.bottom
        BLT.B   DLGMGR_SKIP_10                  | taller than one line: skip widening
        SUB     (A0),D1                         | D1 = left - destRect.right = -width
        SUB     D1,(A0)                         | destRect.right += width (double the width)
DLGMGR_SKIP_10:
        ST.B    -(SP)                           | push TRUE for TEAutoView enable
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEAutoView                             | enable auto-scrolling for this TE
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TECalText                              | recalculate line starts for new text
DLGMGR_EXIT_6:
        RTS                                     | return from edit field activation

| ----------------------------------------------------------
| DLGMGR_OK_2 - Test if item display rect is within dialog's portRect.
| Returns Z=1 if no intersection (item not visible).
| Uses inset=0 (exact rect bounds).
| ----------------------------------------------------------
DLGMGR_OK_2:
        MOVEQ.L #0x0,D0                         | inset = 0 (no expansion)
        BRA.B   DLGMGR_CONT_35                  | share common rect intersection test

| ----------------------------------------------------------
| DLGMGR_CONT_34 - Test if item rect (expanded by 4 pixels) intersects portRect.
| Used during drawing to skip off-screen items.
| Returns Z=1 if no intersection.
| ----------------------------------------------------------
DLGMGR_CONT_34:
        MOVE.L  #0xFFFCFFFC,D0                  | inset = (-4,-4) to include item frame
DLGMGR_CONT_35:
        MOVE.L  0x8(A2),-(SP)                   | push item rect bottom-right
        MOVE.L  0x4(A2),-(SP)                   | push item rect top-left
        MOVE.L  A7,-(SP)                        | push ptr to temp rect on stack
        MOVE.L  D0,-(SP)                        | push inset amount (dh, dv packed)
        _InsetRect                              | shrink rect by negative inset (expand it)
        CLR     -(SP)                           | space for SectRect boolean result
        PEA.L   0x2(SP)                         | push ptr to temp rect
        PEA.L   0x10(A4)                        | push dialog portRect (+$10 in GrafPort)
        PEA.L   0xA(SP)                         | push ptr to dummy dest rect on stack
        _SectRect                               | test intersection of item rect and portRect
        MOVE.B  (SP)+,D0                        | D0 = TRUE if rects intersect
        ADDQ.W  #0x8,SP                         | clean up temp rect from stack
        RTS                                     | return visibility boolean in D0

| ----------------------------------------------------------
| ENTRY_4 - Draw a rounded-rect frame around an item rect.
| Entry: A0 = ptr to rect, D0 = pen width, D1 = pen height,
| D2 = outward inset (positive = expand outward).
| Expands rect outward by D2, frames it, then restores rect.
| ----------------------------------------------------------
ENTRY_4:
        MOVE.L  A0,-(SP)                        | push rect ptr for 2nd InsetRect (restore)
        MOVE    D2,-(SP)                        | push +D2 horizontal (shrink back later)
        MOVE    D2,-(SP)                        | push +D2 vertical
        MOVE.L  A0,-(SP)                        | push rect ptr for FrameRoundRect
        MOVE    D1,-(SP)                        | push oval height for rounded corners
        MOVE    D1,-(SP)                        | push oval width for rounded corners
        MOVE.L  A0,-(SP)                        | push rect ptr for 1st InsetRect (expand)
        NEG     D2                              | negate: now -D2 = expand outward
        MOVE    D2,-(SP)                        | push -D2 horizontal inset (expand)
        MOVE    D2,-(SP)                        | push -D2 vertical inset (expand)
        MOVE    D0,-(SP)                        | push pen width for PenSize
        MOVE    D0,-(SP)                        | push pen height for PenSize
        _PenSize                                | set pen to D0 x D0 pixels
        _InsetRect                              | expand rect outward by D2 pixels
        _FrameRoundRect                         | draw rounded-rect frame
        _InsetRect                              | restore rect to original size
        RTS                                     | return from rounded-rect frame drawing

| ----------------------------------------------------------
| ENTRY_5 - Create a new string handle from a Pascal string.
| Entry: A0 = ptr to Pascal string.
| Exit: A0 = new string handle. Preserves D1-D2, A1-A2.
| Note: saves D0-D2/A1-A2 but restores D1-D2/A1-A2 only
| (D0 is clobbered by NewString result, shifts registers).
| ----------------------------------------------------------
ENTRY_5:
        MOVEM.L D0-D2/A1-A2,-(SP)               | save regs (5 longs = 20 bytes)
        MOVE.L  A0,-(SP)                        | push string ptr for NewString
        _NewString                              | create handle with copy of string
        MOVE.L  (SP)+,A0                        | A0 = new string handle
        MOVEM.L (SP)+,D1-D2/A1-A2               | restore D1-D2/A1-A2 (skip saved D0)
        RTS                                     | return with new string handle in A0

| ----------------------------------------------------------
| DLGMGR_NEXT_4 - Advance to the next DITL item.
| Increments D3 (item index), then positions A2 at next item.
| If D3 was -1 (no current item), falls into DLGMGR_OK_3 to start
| from the beginning. Returns Z=1 if past end of item list.
| ----------------------------------------------------------
| Called by: CLOSEDIALOG_NO_2, SETITEXT_NEXT_2, FINDDITEM_NEXT, FINDDITEM_EXIT_2, DLGMGR_SKIP_6 (and 1 more)
DLGMGR_NEXT_4:
        ADDQ.W  #0x1,D3                         | advance to next item index
        BEQ.B   DLGMGR_OK_3                     | was -1: start from first item
        MOVE.L  D2,-(SP)                        | save D2 (used as byte accumulator)
        MOVEQ.L #0x1,D0                         | skip 1 item (advance from current)
        BRA.B   DLGMGR_SKIP_11                  | enter item-skip loop

| ----------------------------------------------------------
| DLGMGR_OK_3 - Position A2 at DITL item number D3.
| Walks the variable-length DITL item list from the beginning,
| skipping D3 items to reach the target. D7 accumulates byte
| offset. Returns A2 = ptr to item, Z=1 if past end.
| ----------------------------------------------------------
| Called by: INITDIALOGS_OK, CLOSEDIALOG_CONT_5, GetDItem, SetDItem, SelIText (and 3 more)
DLGMGR_OK_3:
        MOVE.L  D2,-(SP)                        | save D2 (used as byte accumulator)
        MOVEQ.L #0x0,D7                         | D7 = running byte offset into DITL data
        MOVE    D3,D0                           | D0 = number of items to skip
        BLT.B   DLGMGR_EXIT_7                   | negative index: return nil
DLGMGR_SKIP_11:
        MOVEQ.L #0x0,D2                         | clear D2 for byte-size data length reads
        MOVE.L  A3,D1                           | test items handle (A3)
        BEQ.B   DLGMGR_EXIT_7                   | nil handle: return nil
        MOVE.L  (A3),A2                         | dereference items handle to DITL data
        MOVE    (A2)+,D1                        | D1 = item count - 1 (DITL stores count-1)
        CMP     D3,D1                           | is target index within range?
        BGE.B   DLGMGR_OK_4                     | yes: start walking items
DLGMGR_EXIT_7:
        SUBA.L  A2,A2                           | A2 = nil (past end of list)
        BRA.B   DLGMGR_EXIT_8                   | return with Z=1

| ----------------------------------------------------------
| DLGMGR_LOOP_3 - Skip one DITL item entry (variable-length).
| Each item: 4-byte handle + 8-byte rect + 1-byte type +
| 1-byte data length + data (padded to even boundary).
| ----------------------------------------------------------
DLGMGR_LOOP_3:
        MOVE.B  0xD(A2,D7.W),D2                 | D2 = data length byte at item+13+offset
        ADD     D2,D7                           | advance offset by data length
        ADDI    #0xF,D7                         | add 15 (14 fixed bytes + round up)
        ANDI    #-0x2,D7                        | align to even byte boundary
DLGMGR_OK_4:
        DBF     D0,DLGMGR_LOOP_3                | skip D0 items
        ADDA    D7,A2                           | A2 = ptr to target item entry
        BSR.B   DLGMGR_CONT_36                  | copy item's display rect to -0x28(A6)
DLGMGR_EXIT_8:
        MOVE.L  (SP)+,D2                        | restore D2
        MOVE.L  A2,D0                           | set Z flag: Z=1 if A2 is nil (past end)
        RTS                                     | return with Z flag set if past end

| ----------------------------------------------------------
| DLGMGR_CONT_36 - Copy item's display rect to local frame variable.
| Copies 8 bytes from item+4 (display rect) to -0x28(A6).
| ----------------------------------------------------------
DLGMGR_CONT_36:
        LEA.L   0x4(A2),A0                      | A0 = ptr to item's display rect
        LEA.L   -0x28(A6),A1                    | A1 = ptr to local rect variable
        MOVE.L  (A0)+,(A1)+                     | copy rect top-left (top, left)
        MOVE.L  (A0)+,(A1)+                     | copy rect bottom-right (bottom, right)
        RTS                                     | return from rect copy

