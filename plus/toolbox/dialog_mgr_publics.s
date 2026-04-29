| Dialog Manager Public Traps
|
| Public Dialog Manager entry points (the traps applications call) and
| a handful of adjacent QuickDraw color helpers that share this ROM
| region. Internal Dialog Manager subroutines live in dialog_mgr.s.
|
| Routine groups, in physical ROM order:
|   StopAlert, NoteAlert, CautionAlert, Alert       (alert traps)
|   CloseDialog                                     (dispose dialog)
|   ParamText, ErrorSound                           (text-substitution)
|   GetDItem, SetDItem, GetIText, SetIText, SelIText (item access)
|   GetMaxDevice, GetCTSeed                         (QD color stubs)
|   FindDItem                                       (Dialog Mgr)
|   ...remaining Dialog Mgr publics until the next file boundary
|
| Files cannot be reordered (ROM byte order is fixed).

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
        CMPI.B  #0x3,0x5(A0)                    | is key code Enter (0x03)?
        BEQ.B   INITDIALOGS_OK                  | yes - treat as default button press
        CMPI.B  #0xD,0x5(A0)                    | is key code Return (0x0D)?
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
        MOVE.L  (A1)+,-(SP)                     | push behind window and visible flag
        MOVE.L  0x8(A6),-(SP)                   | push behind window from caller
        MOVE    (A1)+,-(SP)                     | push procID (window definition)
        MOVE.L  (A1)+,-(SP)                     | push goAway flag + refCon
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
        MOVE.L  A3,windowSize(A4)               | store items handle in dialog record
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
        MOVE.L  A4,-(SP)                        | push dialog for UpdtControl
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
        MOVE.L  0x1C(A4),-(SP)                  | push dialog's update region
        _SetEmptyRgn                            | clear update region before close
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
        MOVE.L  windowSize(A4),A3               | A3 = item list handle from dialog record
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
| _DisposeDialog ($A983)
|
| Called during boot.
DisposeDialog:
        MOVE.L  0x4(SP),A0                      | A0 = dialog pointer from caller
        MOVE.L  0x9C(A0),-(SP)                  | push item list handle (for DisposeHandle)
        MOVE.L  A0,-(SP)                        | push dialog pointer
        _CloseDialog                            | close dialog (dispose items, window)
        MOVE.L  (SP)+,A0                        | A0 = item list handle
        _DisposeHandle                          | dispose item list handle
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = dialog storage pointer
        _DisposePtr                             | free dialog record memory
        JMP     (A1)                            | return to caller

| ----------------------------------------------------------
|
| DISPOSEDIALOG_CONT
|
| Called during boot.
DISPOSEDIALOG_CONT:
        MOVE.L  (A2),A0                         | dereference DLOG template handle
        MOVE    0x12(A0),D0                     | D0 = DITL ID from DLOG template
        BRA.B   DISPOSEDIALOG_CONT_3            | load the DITL resource

| ----------------------------------------------------------
|
| DISPOSEDIALOG_CONT_2 - get DITL for ALRT template
|
DISPOSEDIALOG_CONT_2:
        MOVE.L  (A2),A0                         | dereference ALRT template handle
        MOVE    0x8(A0),D0                      | D0 = DITL ID from ALRT template
DISPOSEDIALOG_CONT_3:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4449544C,-(SP)               | push type = 'DITL'
        MOVE    D0,-(SP)                        | push DITL resource ID
DISPOSEDIALOG_EXIT:
        _GetResource                            | load the DITL resource
        MOVE.L  (SP)+,A2                        | A2 = DITL resource handle
        RTS                                     | return DITL resource handle in A2

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
| Get Max Device
|
GetMaxDevice:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0xA(A6),A4                      | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE    0x8(A6),D3                      | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry A2 for index D3
        BEQ.B   GETMAXDEVICE_EXIT               | item not found - skip
        MOVE    0x6(A2),D0                      | D0 = item rect left coordinate
        CMPI    #0x2000,D0                      | is item already hidden (offset by 0x4000)?
        BLT.B   GETMAXDEVICE_NO                 | no - proceed to hide it
GETMAXDEVICE_EXIT:
        BSR     CLOSEDIALOG_CONT_6              | restore port, clear lock
        MOVEQ.L #0x6,D0                         | 6 bytes of params to clean up
        BRA     SETITEXT_CONT_2                 | dialog epilogue

| ----------------------------------------------------------
|
| GETMAXDEVICE_NO - hide dialog item by moving it offscreen
|
GETMAXDEVICE_NO:
        BSR.B   SELITEXT_CONT                   | compute inset rect on stack
        CMP     editField(A4),D3                | hiding the active edit field?
        BNE.B   GETMAXDEVICE_SKIP               | no - skip deactivation
        MOVEQ.L #-0x1,D3                        | deactivate edit field
        BSR     ENTRY_2                         | deselect text and reset editField
GETMAXDEVICE_SKIP:
        MOVE.L  A7,-(SP)                        | push pointer to inset rect on stack
        _EraseRect                              | erase item's visible area
        ADDI    #0x4000,0x6(A2)                 | move left coord offscreen (+16384)
        ADDI    #0x4000,0xA(A2)                 | move right coord offscreen (+16384)
        BSR.B   GETCTSEED_CONT                  | check if item has a control
        BEQ.B   GETMAXDEVICE_EXIT_2             | no control - skip MoveControl
        MOVE.L  (A2),-(SP)                      | push control handle
        MOVE.L  0x4(A2),-(SP)                   | push new top-left position
        _MoveControl                            | move control to offscreen position
GETMAXDEVICE_EXIT_2:
        MOVE.L  A7,-(SP)                        | push pointer to rect on stack
        _InvalRect                              | invalidate old area for redraw
        ADDQ.W  #0x8,SP                         | remove 8-byte rect from stack
GETMAXDEVICE_SKIP_2:
        BRA.B   GETMAXDEVICE_EXIT               | return via epilogue

| ----------------------------------------------------------
|
| Get CT Seed
|
GetCTSeed:
        BSR     MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  0xA(A6),A4                      | A4 = dialog pointer
        BSR     CLOSEDIALOG_CONT_4              | set up port, load item list
        MOVE    0x8(A6),D3                      | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR     DLGMGR_OK_3                     | get item entry A2 for index D3
        BEQ.B   GETMAXDEVICE_SKIP_2             | item not found - skip
        MOVE    0x6(A2),D0                      | D0 = item rect left coordinate
        CMPI    #0x2000,D0                      | is item hidden (offset by 0x4000)?
        BLT.B   GETMAXDEVICE_SKIP_2             | no - already visible, skip
        SUBI    #0x4000,0x6(A2)                 | move left coord back onscreen (-16384)
        SUBI    #0x4000,0xA(A2)                 | move right coord back onscreen (-16384)
        BSR     SELITEXT_CONT                   | compute inset rect on stack
        BSR.B   GETCTSEED_CONT                  | check if item has a control
        BEQ.B   GETCTSEED_SKIP                  | no control - skip MoveControl
        MOVE.L  (A2),A0                         | A0 = control handle
        MOVE.L  (A0),A1                         | A1 = dereferenced control record
        MOVE.B  0x10(A1),-(SP)                  | save control's visible flag
        CLR.B   0x10(A1)                        | temporarily hide control (prevent redraw)
        MOVE.L  A0,-(SP)                        | push control handle
        MOVE.L  0x4(A2),-(SP)                   | push restored top-left position
        _MoveControl                            | move control back onscreen
        MOVE.L  (A2),A0                         | reload control handle (may have moved)
        MOVE.L  (A0),A1                         | dereference control record
        MOVE.B  (SP)+,0x10(A1)                  | restore control's visible flag
GETCTSEED_SKIP:
        BRA.B   GETMAXDEVICE_EXIT_2             | invalidate rect and return

| GETCTSEED_CONT -- check if item has a control.
| ----------------------------------------------------------
|
| GETCTSEED_CONT
|
GETCTSEED_CONT:
        TST     editField(A4)                   | does dialog have an active edit field?
        BPL.B   GETCTSEED_SKIP_3                | yes - skip TE auto-select
        MOVE.L  A2,-(SP)                        | save current item pointer
        BSR     CLOSEDIALOG_CONT_5              | search for editText item
        BEQ.B   GETCTSEED_SKIP_2                | no editText found - skip
        MOVEQ.L #0x0,D2                         | D2 = 0: select all text
        BSR     ENTRY_2                         | activate text edit for found item
GETCTSEED_SKIP_2:
        MOVE.L  (SP)+,A2                        | restore item pointer
GETCTSEED_SKIP_3:
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
