| Dialog Manager
|
| Apple source: DialogMgr.a (MacSEROM.lst module DMGR). It starts with the
| alert data ALERT_ICON_RECT / ALERT_EMPTY_TITLE (pushed PC-relative by
| Alert), then the traps, in physical ROM order:
|   InitDialogs                                    (init)
|   StopAlert, NoteAlert, CautionAlert, Alert      (alert traps)
|   GetNewDialog, NewDialog                        (dialog creation)
|   IsDialogEvent, DialogSelect, ModalDialog       (dialog event loop)
|   DrawDialog, UpdateDialog                       (drawing)
|   CloseDialog, DisposDialog                      (teardown)
|   ParamText, ErrorSound                          (text-substitution)
|   GetDItem, SetDItem, GetIText, SetIText, SelIText, FindDItem
|                                                  (item access)
|   HideDItem, ShowDItem, HiliteDefaultButton      (item state)
| followed by the internal routines.
|
| References: Inside Macintosh Vol I, Ch 13 (The Dialog Manager).

| Small data region @ $E436-$E443, referenced by PEA PC-rel from
| the Alert sites below. Bytes preserved as raw data.
ALERT_ICON_RECT:                                | 8-byte icon rect param
        .short  0x000A, 0x0014, 0x002A, 0x0034  | top=10, left=20, bottom=42, right=52
ALERT_EMPTY_TITLE:                              | 2-byte empty Pascal string
        .short  0x0000                          | length=0
| ----------------------------------------------------------
| InitDialogs -- _InitDialogs ($A97B).
| Pascal: procedure InitDialogs(resumeProc: ProcPtr);
| Initializes Dialog Manager globals: stores the resume proc,
| clears the alert invocation count, sets ANumber to -1 (no
| current alert), installs the default beeper proc, clears the
| 4 ParamText slots and DlgFont. The 4-byte BSR.W to MODALDIALOG_CONT_3
| was previously hand-encoded as .short 0x6100, 0x0340 with a
| misleading "filler" comment -- it's the actual entry instruction
| that does the LINK A6 / save regs prologue (Plus annotates this
| exactly as "BSR MODALDIALOG_CONT_3 | dialog prologue").
InitDialogs:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  8(A6),(ResumeProc).w            | store caller's resume proc
        CLR     (ACount).w                      | reset alert invocation count
        ST      (ANumber).w                     | ANumber := -1 (no current alert)
        LEA.L     (DABeeper).w,A0               | A0 = start of dialog globals
        LEA     RMVERESOURCE_CONT_4_CONT_5(PC),A1 | A1 = default beeper proc
        MOVE.L  A1,(A0)+                        | DABeeper = default beep proc
        CLR.L   (A0)+                           | clear DAStrings[0]
        CLR.L   (A0)+                           | clear DAStrings[1]
        CLR.L   (A0)+                           | clear DAStrings[2]
        CLR.L   (A0)+                           | clear DAStrings[3]
        CLR     (DlgFont).w                     | DlgFont = 0 (system font)
        MOVEQ.L #0x4,D0                         | 4 bytes of params
        BRA.W   MODALDIALOG_CONT_4              | dialog epilogue
RMVERESOURCE_CONT_4_CONT_5:
        MOVE.L  (SP)+,A1                        | A1 = caller return address
        MOVE    (SP)+,D2                        | D2 = beep count from caller
INITDIALOGS_LOOP:
        BEQ.B   INITDIALOGS_DONE                | count exhausted - return
        MOVE    #0x3,-(SP)                      | push duration = 3 ticks
        _SysBeep                                | emit system beep sound
        MOVE    #0x6,A0                         | delay 6 ticks between beeps
        _Delay                                  | wait for delay
        SUBQ.W  #0x1,D2                         | decrement beep counter
        BRA.B   INITDIALOGS_LOOP                | loop for remaining beeps
INITDIALOGS_LOOP_EXIT:
        MOVEM.L (SP)+,D1-D2/A0-A1               | restore working registers
        CLR     (SP)                            | clear default itemHit slot
        CMPI    #0x3,(A0)                       | test event = key/auto-key?
        BNE.B   INITDIALOGS_LOOP_CONT_2         | not key - skip
        CMPI.B  #0x3,5(A0)                      | character = Enter (CR)?
        BEQ.B   INITDIALOGS_LOOP_CONT           | yes - return default item
        CMPI.B   #0xD,5(A0)                     | character = Return?
        BNE.B    INITDIALOGS_LOOP_CONT_2        | no - ignore key
INITDIALOGS_LOOP_CONT:
        MOVE.L  D2,A0                           | A0 = itemHit result slot
        MOVE    0xA8(A1),(A0)                   | itemHit := DLogDef default item
        ADDQ.B  #0x1,(SP)                       | (SP) += 0x1
INITDIALOGS_LOOP_CONT_2:
        MOVE.L  D1,A1                           | A1 = saved return addr
INITDIALOGS_DONE:
        JMP     (A1)                            | return via stored addr

| ----------------------------------------------------------
| StopAlert -- _StopAlert ($A986).
| Pascal: function StopAlert(alertID: INTEGER;
| filterProc: ProcPtr): INTEGER;
StopAlert:
        MOVEQ.L #0x0,D0                         | D0 = 0: stop icon
        BRA.B   ALERT_CONT                      | -> common alert entry

| ----------------------------------------------------------
| NoteAlert -- _NoteAlert ($A987).
NoteAlert:
        MOVEQ.L #0x1,D0                         | D0 = 1: note icon
        BRA.B   ALERT_CONT                      | -> common alert entry

| ----------------------------------------------------------
| CautionAlert -- _CautionAlert ($A988).
CautionAlert:
        MOVEQ.L #0x2,D0                         | D0 = 2: caution icon
        BRA.B   ALERT_CONT                      | -> common alert entry

| ----------------------------------------------------------
| Alert -- _Alert ($A985).
| Pascal: function Alert(alertID: INTEGER;
| filterProc: ProcPtr): INTEGER;
| Common alert dispatch: D0 = icon code (0=stop, 1=note,
| 2=caution, -1=plain).
Alert:
        MOVEQ.L #-0x1,D0                        | D0 = -1: plain alert (no icon)
ALERT_CONT:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE    D0,D3                           | D3 = icon type (0=stop,1=note,2=caution,-1=none)
        MOVE    12(A6),D0                       | D0 = alert resource ID
        BSR.W   COULDALERT_CONT_2               | load ALRT resource template
        MOVE    (ACount).w,D0                   | D0 = previous alert invocation count
        MOVE    12(A6),D1                       | D1 = current alert ID
        CMP     (ANumber).w,D1                  | same alert as last time?
        BEQ.B   ALERT_OK                        | yes - keep count
        MOVE    D1,(ANumber).w                  | no - store new alert ID
        MOVEQ.L #0x0,D0                         | reset count to 0
ALERT_OK:
        MOVE    D0,(ACount).w                   | push default item number
        MOVE    10(A1),D4                       | D4 = stages word from ALRT
ALERT_CONT_2:
        SUBQ.W  #0x1,D0                         | shift to current stage's 4-bit field
        BLT.B   ALERT_CONT_3                    | reached current stage - extract nibble
        LSR     #0x4,D4                         | shift right one nibble (4 bits)
        BRA.B   ALERT_CONT_2                    | continue shifting

| ----------------------------------------------------------
| ALERT_CONT_3 - process alert stage nibble
ALERT_CONT_3:
        ANDI    #0xF,D4                         | isolate low nibble (current stage)
        MOVE.L  D4,D0                           | D0 = stage nibble for beep count
        ANDI    #0x3,D0                         | low 2 bits = beep count (0-3)
        BSR.W   ALERT_CONT_6                    | call beep procedure D0 times
        BTST    #0x2,D4                         | bit 2 = show dialog flag
        BNE.B   ALERT_CONT_4                    | set - show the alert dialog
        MOVE    (MinusOne).w,14(A6)             | no dialog - return -1 as itemHit
        BRA.W   ALERT_SKIP_2                    | skip to cleanup
ALERT_CONT_4:
        MOVE.L  #0x1FF,D0                       | flush all event types
        _FlushEvents                            | clear event queue before modal dialog
        MOVE    8(A1),D0                        | D0 = DITL resource ID from ALRT template
        BSR.W   ALERT_CONT_5                    | load and copy DITL resource
        MOVE.L  (A2),A1                         | A1 = dereferenced ALRT template data
        SUBQ.W  #0x4,SP                         | space for NewDialog result handle
        CLR.L   -(SP)                           | dStorage = NIL (allocate on heap)
        PEA.L     (A1)                          | push boundsRect from ALRT template
        PEA     ALERT_EMPTY_TITLE(PC)           | push empty title Pascal string
        ST      -(SP)                           | visible = true
        MOVE    #0x1,-(SP)                      | procID = 1 (dBoxProc, no title bar)
        MOVE.L  (MinusOne).w,-(SP)              | behind = -1 (in front of all windows)
        CLR     -(SP)                           | goAwayFlag = false
        CLR.L   -(SP)                           | refCon = 0
        MOVE.L  A0,-(SP)                        | push items handle (copied DITL)
        _NewDialog                              | create the alert dialog
        MOVE.L  (SP),A4                         | A4 = new dialog pointer
        PEA.L     -0x2C(A6)                     | push address to save current port
        _GetPort                                | save current grafPort
        _SetPort                                | set dialog as current port
        TST     D3                              | is there an icon to display?
        BMI.B   ALERT_SKIP                      | -1 = no icon, skip
        SUBQ.W  #0x4,SP                         | space for GetIcon result
        MOVE    D3,-(SP)                        | push icon ID (0=stop, 1=note, 2=caution)
        _GetIcon                                | load icon resource
        MOVE.L  (SP)+,D0                        | D0 = icon handle
        BEQ.B   ALERT_SKIP                      | no icon found - skip plot
        PEA     ALERT_ICON_RECT(PC)             | push icon rect (10,20,42,52)
        MOVE.L  D0,-(SP)                        | push icon handle
        _PlotIcon                               | draw icon in alert dialog
ALERT_SKIP:
        ASR     #0x3,D4                         | shift to default-item bit
        ADDQ.W  #0x1,D4                         | D4 = default item number (1 or 2)
        MOVE    D4,aDefItem(A4)                 | set default button in dialog record
        MOVE.L  A4,-(SP)                        | push dialog pointer
        MOVE    D4,-(SP)                        | push default item number
        PEA.L     -0x3C(A6)                     | push ptr for item type result
        MOVE.L  (SP),-(SP)                      | push ptr for item handle result
        PEA.L     -0x28(A6)                     | push ptr for item rect result
        _GetDialogItem                          | get default item's rect for bold outline
        LEA.L     -0x28(A6),A0                  | A0 = default item's bounding rect
        MOVEQ.L #0x3,D0                         | inset left/right = 3 pixels
        MOVEQ.L #0x10,D1                        | pen size = 16 (bold outline)
        MOVEQ.L #0x4,D2                         | round radius = 4
        BSR.W   ENTRY_4                         | draw bold rounded rect around default button
        MOVE.L  8(A6),-(SP)                     | push filterProc for ModalDialog
        PEA.L     14(A6)                        | push address for itemHit result
        _ModalDialog                            | run modal dialog event loop
        MOVE.L  -0x2C(A6),-(SP)                 | push saved port
        _SetPort                                | restore original grafPort
        MOVE.L  A4,-(SP)                        | push dialog pointer
        _DisposeDialog                          | dispose the alert dialog
ALERT_SKIP_2:
        BCLR    #0x7,(A2)                       | clear lock bit on ALRT resource handle
        MOVE    (ACount).w,D1                   | D1 = current invocation count
        ADDQ.W  #0x1,D1                         | increment count for next call
        CMPI    #0x4,D1                         | maximum 4 stages
        BLT.B   ALERT_OK_2                      | under max - use as-is
        MOVEQ.L #0x3,D1                         | cap at stage 3 (repeat last stage)
ALERT_OK_2:
        MOVE    D1,(ACount).w                   | ACount := updated stage
        MOVEQ.L #0x6,D0                         | D0 = 6 bytes of params (id+proc)
        BRA.B   GETNEWDIALOG_CONT               | epilogue: pop, return itemHit

| ----------------------------------------------------------
| ALERT_CONT_5
| Called during boot.
ALERT_CONT_5:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4449544C,-(SP)               | push type = 'DITL'
        MOVE    D0,-(SP)                        | push DITL resource ID
        _GetResource                            | load DITL template
        MOVE.L  (SP)+,A0                        | A0 = DITL handle
        _HandToHand                             | make a copy (dialog owns its item list)
        RTS                                     | return copied DITL handle in A0
ALERT_CONT_6:
        MOVEM.L D0-D2/A0-A2,-(SP)               | save registers
        MOVE.L  (DABeeper).w,D1                 | D1 = beep procedure address
        BEQ.B   ALERT_SKIP_3                    | no beep proc installed - skip
        MOVE    D0,-(SP)                        | push beep count on stack
        MOVE.L  D1,A0                           | A0 = beep procedure
        JSR     (A0)                            | call subroutine via A0
ALERT_SKIP_3:
        MOVEM.L  (SP)+,D0-D2/A0-A2              | restore working registers
        RTS                                     | return after beep call

| ----------------------------------------------------------
| GetNewDialog -- _GetNewDialog ($A97C).
| Pascal: function GetNewDialog(dialogID: INTEGER; dStorage: Ptr;
| behind: WindowPtr): DialogPtr;
| Loads a DLOG resource template and creates a dialog from it.
| Pushes window-creation parameters from the template (boundsRect,
| title, visible flag, procID, goAway, refCon, DITL) onto the
| stack and calls _NewDialog with the items handle.
GetNewDialog:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE    16(A6),D0                       | D0 = DLOG resource ID
        BSR.W   COULDALERT_CONT_3               | load DLOG template, A1 = data, A2 = handle
        SUBQ.W  #0x4,SP                         | space for NewDialog result
        MOVE.L  12(A6),-(SP)                    | push dStorage pointer from caller
        MOVE.L  A1,-(SP)                        | push boundsRect pointer (DLOG template)
        PEA.L     20(A1)                        | push title string (at template+20)
        ADDQ.L  #0x8,A1                         | skip past boundsRect to window fields
        MOVE.L  (A1)+,-(SP)                     | push procID + visible (DLOG template +8)
        MOVE.L  8(A6),-(SP)                     | push behind window from caller
        MOVE    (A1)+,-(SP)                     | push goAwayFlag (template +$C)
        MOVE.L  (A1)+,-(SP)                     | push refCon (template +$E)
        MOVE    (A1)+,D0                        | D0 = DITL resource ID from template
        BSR.B   ALERT_CONT_5                    | load and copy DITL
        MOVE.L  A0,-(SP)                        | push items handle
        _NewDialog                              | create dialog from template
        BCLR    #0x7,(A2)                       | unlock DLOG resource handle
        MOVE.L  (SP)+,18(A6)                    | store dialog pointer in return slot
        MOVEQ.L #0xA,D0                         | 10 bytes of params to clean up
GETNEWDIALOG_CONT:
        BRA.B   NEWDIALOG_CONT                  | -> $E68A (trampoline to CLEANUP_PARAMS)

| ----------------------------------------------------------
| NewDialog -- _NewDialog ($A97D).
| Pascal: function NewDialog(dStorage: Ptr; boundsRect: Rect;
| title: Str255; visible: BOOLEAN;
| procID: INTEGER; behind: WindowPtr;
| goAwayFlag: BOOLEAN; refCon: LongInt;
| items: Handle): DialogPtr;
| Allocates a 170-byte DialogRecord (or uses caller's dStorage),
| calls _NewWindow with copied params, sets windowKind=2 (dialog),
| installs the items handle and DlgFont, allocates a TextEdit
| record for editable text fields, then walks the items list to
| create controls.
NewDialog:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        TST.L   0x22(A6)                        | was dStorage provided?
        BNE.B   NEWDIALOG_OK                    | yes - use caller's storage
        MOVE.L  #0xAA,D0                        | 170 bytes = dialog record size
        _NewPtr                                 | allocate dialog record on heap
        MOVE.L  A0,0x22(A6)                     | store allocated pointer
NEWDIALOG_OK:
        LEA.L     12(A6),A0                     | A0 = start of NewWindow params on stack
        MOVEQ.L #0x1E,D0                        | 30 bytes of window creation parameters
        SUBA.L  D0,SP                           | allocate 30 bytes on stack
        MOVE.L  SP,A1                           | A1 = destination for param copy
        _BlockMove                              | copy window params to stack temp
        _NewWindow                              | create underlying window
        MOVE.L  (SP)+,A4                        | A4 = new window/dialog pointer
        MOVE.L  A4,0x26(A6)                     | store result dialog pointer
        MOVE.L  8(A6),A3                        | A3 = items handle from caller
        MOVE    #0x2,windowKind(A4)             | set windowKind = dialogKind (2)
        MOVE.L  A3,items(A4)                    | store items handle in dialog record
        MOVE    (MinusOne).w,editField(A4)      | editField = -1 (no active text field)
        MOVE    (DlgFont).w,0x44(A4)            | set dialog font from global default
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  SP,-(SP)                        | push address to save current port
        _GetPort                                | save current grafPort
        MOVE.L  A4,-(SP)                        | push dialog as new port
        _SetPort                                | make dialog the current port
        MOVE    #0x1,aDefItem(A4)               | default item = 1
        SUBQ.W  #0x4,SP                         | space for TENew result
        PEA.L     16(A4)                        | push destRect (portRect of dialog)
        MOVE.L  (SP),-(SP)                      | push viewRect (same as destRect)
        _TENew                                  | create TextEdit record for dialog
        MOVE.L  (SP),0xA0(A4)                   | store TE handle in dialog record
        MOVE.L  (SP)+,A1                        | A1 = TE handle
        MOVE.L  (A1),A2                         | A2 = dereferenced TE record
        MOVE.L  0x3E(A2),A0                     | A0 = TE's text handle (empty default)
        _DisposeHandle                          | dispose initial empty text handle
        _SetPort                                | restore saved grafPort
        BSR.W   DRAWDIALOG_CONT_2               | set up port, load item list
        MOVEQ.L #0x0,D4                         | D4 = 0: initialize items (create controls)
        BSR.W   FINDDITEM_CONT                  | walk item list, create controls
        BSR.W   CLOSEDIALOG_NO_2_CONT_2         | restore port, clear lock
        MOVEQ.L #0x1E,D0                        | 30 bytes of params to clean up
NEWDIALOG_CONT:
        BRA.B   ISDIALOGEVENT_CONT              | -> $E6DC (trampoline to _CONT)

| ----------------------------------------------------------
| NEWDIALOG_CONT_2
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
NEWDIALOG_OK_2:
        MOVEA.L  2(A2),A4                       | A4 = window from event message
        RTS                                     | return target window in A4

| ----------------------------------------------------------
| IsDialogEvent -- _IsDialogEvent ($A97F).
| Pascal: function IsDialogEvent(event: EventRecord): BOOLEAN;
| Returns true if the event is for a dialog window. mouseDown
| events also require the click to land in the dialog's content
| region (else returns false so the application can handle the
| click). Other events (keyDown, update, activate, etc.) return
| true if the target window is a dialog.
IsDialogEvent:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        CLR     12(A6)                          | preset result = false
        MOVE.L  8(A6),A2                        | A2 = event record pointer
        BSR.B   NEWDIALOG_CONT_2                | A4 = target window for this event
        CMPI    #0x2,windowKind(A4)             | is target a dialog (kind=2)?
        BNE.B   ISDIALOGEVENT_SKIP              | no - not a dialog event
        MOVE    (A2),D3                         | D3 = event type
        SUBQ.W  #0x1,D3                         | test for mouseDown (1)
        BNE.B   ISDIALOGEVENT_NO                | not mouseDown - assume dialog event
        SUBQ.W  #0x2,SP                         | space for FindWindow result
        MOVE.L  10(A2),-(SP)                    | push mouse click point
        PEA.L     -20(A6)                       | push address for window result
        _FindWindow                             | which window was clicked?
        SUBQ.W  #0x3,(SP)+                      | test for inContent (3)
        BNE.B   ISDIALOGEVENT_SKIP              | not in content - not a dialog event
        CMPA.L  -20(A6),A4                      | click in same dialog window?
        BNE.B   ISDIALOGEVENT_SKIP              | no - not a dialog event
ISDIALOGEVENT_NO:
        ADDQ.B  #0x1,12(A6)                     | 12(A6) += 0x1
ISDIALOGEVENT_SKIP:
        MOVEQ.L #0x4,D0                         | D0 = 4 bytes of params
ISDIALOGEVENT_CONT:
        BRA.B   DIALOGSELECT_CONT               | epilogue, pop+return

| ----------------------------------------------------------
| DialogSelect -- _DialogSelect ($A980).
| Pascal: function DialogSelect(event: EventRecord;
| VAR theDialog: DialogPtr;
| VAR itemHit: INTEGER): BOOLEAN; | call subroutine via A0 | call subroutine via A0
| Dispatches an event to a dialog's items. Sets theDialog to
| the target window and (if an item was hit) itemHit to the item
| number. Returns true if an item was hit.
DialogSelect:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        CLR     20(A6)                          | preset result = false
        MOVE.L  12(A6),A3                       | A3 = caller's theDialog pointer
        CLR.L   (A3)                            | clear dialog pointer output
        MOVE.L  16(A6),A2                       | A2 = event record pointer
        BSR.B   NEWDIALOG_CONT_2                | A4 = target window for this event
        MOVE.L  A4,(A3)                         | store dialog pointer in output
        BSR.W   DRAWDIALOG_CONT_2               | set up port, load item list
        MOVE.L  16(A6),A0                       | A0 = event record source
        LEA.L     -0x4C(A6),A1                  | A1 = local copy of event record
        MOVEQ.L #0x10,D0                        | 16 bytes = event record size
        _BlockMove                              | copy event record to local frame
        BSR.W   RETURNS_15                      | dispatch event to dialog items
        TST     D3                              | was an item hit?
        BMI.B   DIALOGSELECT_NO                 | no - result stays false
        ADDQ.B  #0x1,20(A6)                     | result = true (item was hit)
DIALOGSELECT_NO:
        MOVE.L  8(A6),A0                        | A0 = caller's itemHit pointer
        MOVE    D3,(A0)                         | store hit item number
        BSR.W   CLOSEDIALOG_NO_2_CONT_2         | restore port, clear lock
        MOVEQ.L #0xC,D0                         | 12 bytes of params to clean up
DIALOGSELECT_CONT:
        BRA.B   MODALDIALOG_CONT_2              | epilogue, pop+return result

| ----------------------------------------------------------
| ModalDialog -- _ModalDialog ($A991).
| Pascal: procedure ModalDialog(filterProc: ProcPtr;
| VAR itemHit: INTEGER);
| Modal event loop for a dialog. Calls _SystemTask each iteration,
| polls _GetNextEvent, runs the caller's filterProc (or a default
| that handles Return/Enter), and dispatches via DialogSelect.
| Loops until an item is hit (filter returns true or DialogSelect
| finds an item).
ModalDialog:                                    | jump via A0
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
MODALDIALOG_NEXT:
        _SystemTask                             | run periodic system tasks
        SUBQ.W  #0x6,SP                         | space for GetNextEvent result + event
        MOVE    #0x1FF,-(SP)                    | eventMask: all events except disk
        PEA.L     -0x4C(A6)                     | push local event record address
        _GetNextEvent                           | poll for next event
        MOVE.L  0xC(A6),D3                      | D3 = caller's filterProc
        BNE.B   MODALDIALOG_CONT                | filterProc provided - use it
        LEA     INITDIALOGS_LOOP_EXIT(PC),A0    | no filter - use default (handles Return/Enter)
        MOVE.L  A0,D3                           | D3 = default filter proc
MODALDIALOG_CONT:
        _FrontWindow                            | push front window for filter proc
        PEA.L     -0x4C(A6)                     | push event record for filter
        MOVE.L  8(A6),-(SP)                     | push itemHit pointer for filter
        MOVE.L  D3,A0                           | A0 = filter proc address
        JSR     (A0)                            | call subroutine via A0
        TST.B   (SP)+                           | did filter handle the event?
        BNE.B   MODALDIALOG_EXIT                | yes - item was hit, return
        SUBQ.W  #0x2,SP                         | space for IsDialogEvent result
        PEA.L     -0x4C(A6)                     | push event record
        _IsDialogEvent                          | is event for this dialog?
        TST     (SP)+                           | test result
        BEQ.B   MODALDIALOG_NO                  | no - check for special events
        SUBQ.W  #0x2,SP                         | space for DialogSelect result
        PEA.L     -0x4C(A6)                     | push event record
        PEA.L     -28(A6)                       | push theDialog output address
        MOVE.L  8(A6),-(SP)                     | push itemHit pointer
        _DialogSelect                           | dispatch event to dialog items
        TST     (SP)+                           | was an item hit?
        BLE.B   MODALDIALOG_NEXT                | no item hit - keep looping
MODALDIALOG_EXIT:
        MOVEQ    #0x8,D0                        | D0 = 8 bytes of params to pop
MODALDIALOG_CONT_2:
        BRA.B    MODALDIALOG_CONT_4             | dispatch to common epilogue

| ----------------------------------------------------------
| MODALDIALOG_NO
| Called during boot.
MODALDIALOG_NO:
        MOVE    -0x4C(A6),D0                    | D0 = event type from local record
        SUBQ.W  #0x1,D0                         | test for mouseDown (1)
        BNE.B   MODALDIALOG_NEXT                | not mouseDown - keep looping
        MOVEQ.L #0x1,D0                         | beep count = 1 (click outside modal dialog)
        BSR.W   ALERT_CONT_6                    | beep to alert user
        BRA.B   MODALDIALOG_NEXT                | continue dialog event loop

| ----------------------------------------------------------
| MODALDIALOG_CONT_3
| Called during boot (3,696 times in 30s trace).
MODALDIALOG_CONT_3:
        MOVE.L  (SP)+,A0                        | pop return address
        LINK    A6,#-0x4C                       | allocate 76 bytes of local storage
        MOVEM.L D3-D7/A2-A4,-(SP)               | save all working registers
        JMP     (A0)                            | return to caller body
MODALDIALOG_CONT_4:
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore saved registers
        UNLK    A6                              | tear down stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.L  D0,SP                           | remove D0 bytes of parameters
        JMP     (A0)                            | RTS
DrawDialog:
        BSR.B   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  8(A6),A4                        | A4 = dialog pointer from param
        BSR.B   DRAWDIALOG_CONT_2               | set up port, lock items handle
        MOVE.L  A4,-(SP)                        | push dialog for DrawControls
        _DrawControls                           | draw all controls in dialog
        MOVEQ.L #0x1,D4                         | D4 = 1: draw mode (redraw items)
        BSR.W   FINDDITEM_CONT                  | walk and draw all dialog items
        BSR.B   CLOSEDIALOG_NO_2_CONT_2         | restore port, clear lock
        BRA.B   CLOSEDIALOG_CONT                | skip CloseDialog body, go to common exit

| ----------------------------------------------------------
| CloseDialog -- _CloseDialog ($A982).
| Pascal: procedure CloseDialog(theDialog: DialogPtr);
| Disposes a dialog's items (controls + item handles), the
| TextEdit record, and closes the underlying window -- but does
| NOT free the DialogRecord storage itself (use DisposDialog
| for that).
CloseDialog:
        BSR.B   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE.L  8(A6),A4                        | A4 = dialog pointer from param
        BSR.B   DRAWDIALOG_CONT_2               | set up port, load item list
        MOVE.L  28(A4),-(SP)                    | push the dialog's clipRgn (+$1C)
        _SetEmptyRgn                            | empty clipRgn: nothing draws while closing
        MOVEQ.L #0x2,D4                         | D4 = 2: dispose mode (free item handles)
        BSR.W   FINDDITEM_CONT                  | walk items, dispose controls/handles
        BSR.B   CLOSEDIALOG_NO_2_CONT_2         | restore port, clear lock
        MOVE.L  0xA0(A4),A0                     | A0 = TE handle from dialog record
        MOVE.L  (A0),A0                         | dereference TE handle (unused read)
        MOVE.L  0xA0(A4),A0                     | A0 = TE handle (reload for dispose)
        _DisposeHandle                          | dispose TextEdit handle
        MOVE.L  A4,-(SP)                        | push dialog as window
        _CloseWindow                            | close the underlying window
CLOSEDIALOG_CONT:
        MOVEQ.L #0x4,D0                         | D0 = 4 bytes of params
CLOSEDIALOG_CONT_2:
        BRA.B   MODALDIALOG_CONT_4              | dispatch to common epilogue
| Called by: NEWDIALOG_OK, DialogSelect, DrawDialog, CloseDialog, GetDItem (and 3 more)
DRAWDIALOG_CONT_2:
        PEA.L     -0x2C(A6)                     | push slot to save current port
        _GetPort                                | save current grafPort
        MOVE.L  A4,-(SP)                        | push dialog as new port
        _SetPort                                | set dialog as current port
        MOVE.L  items(A4),A3                    | A3 = items handle
        BSET    #0x7,(A3)                       | lock items handle (set hi bit)
        MOVEQ.L #-0x1,D3                        | D3 = -1 (no item found yet)
        MOVE    editField(A4),D2                | D2 = current edit field index
        BMI.B   CLOSEDIALOG_NO_2                | no edit field - skip search
DRAWDIALOG_LOOP:
        BSR.W   DLGMGR_NEXT_4                   | walk to next item entry
        DBRA    D2,DRAWDIALOG_LOOP              | loop until at edit field index
        BRA.B   CLOSEDIALOG_NO_2_CONT           | process current edit field
CLOSEDIALOG_NO_2:
        BSR.W   DLGMGR_NEXT_4                   | walk to next item entry
        BEQ.B   CLOSEDIALOG_NO_2_CONT_3         | end of items - return
        BTST    #0x4,12(A2)                     | test editText flag (bit 4)
        BEQ.B   CLOSEDIALOG_NO_2                | not editable - keep searching
CLOSEDIALOG_NO_2_CONT:
        MOVEQ.L #-0x2,D2                        | D2 = -2 (deactivate marker)
        BRA.W   ENTRY_3                         | deactivate current edit field (D3=-2)
| Called by: NEWDIALOG_OK, DIALOGSELECT_NO, DrawDialog, CloseDialog, GETDITEM_SKIP (and 2 more)
CLOSEDIALOG_NO_2_CONT_2:
        BCLR    #0x7,(A3)                       | unlock items handle
        MOVE.L  -0x2C(A6),-(SP)                 | push saved port
        _SetPort                                | restore original grafPort
CLOSEDIALOG_NO_2_CONT_3:
        RTS                                     | return after port cleanup

| ----------------------------------------------------------
|
| _DisposDialog ($A983): close a dialog and release its storage
| Pascal: PROCEDURE DisposDialog(theDialog: DialogPtr);
| Calls CloseDialog, then disposes the item list handle (items, $9C)
| and the DialogRecord itself (_DisposPtr).
| Called during boot.
|
DisposDialog:
        MOVE.L  0x4(SP),A0                      | A0 = dialog pointer from caller
        MOVE.L  0x9C(A0),-(SP)                  | push items handle ($9C) for later
        MOVE.L  A0,-(SP)                        | push dialog pointer
        _CloseDialog                            | close dialog (dispose items, window)
        MOVE.L  (SP)+,A0                        | A0 = item list handle
        _DisposeHandle                          | dispose the item list
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = dialog storage pointer
        _DisposePtr                             | free dialog record memory
        JMP     (A1)                            | RTS
| ----------------------------------------------------------
| DISPOSEDIALOG_CONT_4 - A2 = ALRT template handle: get the DITL named by
| its itemsID (offset 8) -> A2. Used by CouldAlert and FreeAlert; the
| _GetResource tail (DISPOSEDIALOG_EXIT) is shared with FREEALERT_CONT_3.
DISPOSEDIALOG_CONT_4:
        MOVE.L  (A2),A0                         | A0 = ALRT template data
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4449544C,-(SP)               | push 'DITL' resource type
        MOVE    8(A0),-(SP)                     | push itemsID (DITL ID) from template
DISPOSEDIALOG_EXIT:
        _GetResource                            | load the DITL resource
        MOVE.L  (SP)+,A2                        | A2 = DITL resource handle
        RTS                                     | return DITL resource handle in A2

| ----------------------------------------------------------
| CouldAlert -- _CouldAlert ($A989).
| Pascal: procedure CouldAlert(alertID: INTEGER);
| Preloads an ALRT resource and its DITL into memory and makes
| them non-purgeable. Used to ensure an alert can be displayed
| even if memory is tight (e.g. for "out of memory" alerts).
| Plus 1986 parameterizes the DLOG/ALRT loader and DITL getter
| via A2/A4 ProcPtrs so the same code handles CouldDialog too;
| classic 1984 hardcodes ALRT (no CouldDialog trap exists).
CouldAlert:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE    8(A6),D0                        | D0 = alert resource ID
        BSR.B   COULDALERT_CONT_2               | load 'ALRT' template
        BEQ.B   FREEALERT_ERR                   | not found - skip preload
        ANDI.B  #0x3F,(A2)                      | make template non-purgeable + clear flags
        BSR.B   DISPOSEDIALOG_CONT_4            | load associated DITL
        BCLR    #0x6,(A2)                       | make DITL non-purgeable
        MOVE.L  A2,A3                           | A3 = DITL handle (for sub-resource preload)
        MOVEQ.L #-0x2,D4                        | D4 = -2: preload mode
        BSR.B   FREEALERT_CONT_3                | preload WDEF and sub-resources
        BCLR    #0x6,(A2)                       | ensure WDEF stays non-purgeable
        BRA.B   FREEALERT_ERR                   | epilogue: 2 param bytes
COULDALERT_CONT_2:
        MOVE.L  #0x414C5254,A0                  | absolute-long addressing
        BRA.B   COULDALERT_CONT_4               | dispatch to common GetResource
COULDALERT_CONT_3:
        MOVE.L  #0x444C4F47,A0                  | absolute-long addressing
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
| FreeAlert -- _FreeAlert ($A98A).
| Pascal: procedure FreeAlert(alertID: INTEGER);
| Releases an ALRT resource that was preloaded by CouldAlert,
| making it and its sub-resources purgeable again. Plus 1986
| parameterizes the loader/getter via A2/A4 to share with
| FreeDialog; classic 1984 hardcodes ALRT.
FreeAlert:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue: LINK frame, save regs
        MOVE    8(A6),D0                        | D0 = alert resource ID
        BSR.B   COULDALERT_CONT_2               | load 'ALRT' template
        BEQ.B   FREEALERT_ERR                   | not found - skip free
        BCLR    #0x7,(A2)                       | unlock template handle (allow purge)
        BSR.W   DLGMGR_CONT_8                   | make template purgeable
        BSR.B   DISPOSEDIALOG_CONT_4            | load associated DITL
        BSR.W   DLGMGR_CONT_8                   | make DITL purgeable
        MOVE.L  A2,A3                           | A3 = DITL handle
        MOVEQ.L #-0x1,D4                        | D4 = -1: free mode
        BSR.B   FREEALERT_CONT_3                | release WDEF and sub-resources
        BSR.W   DLGMGR_CONT_8                   | make WDEF purgeable
FREEALERT_ERR:
        MOVEQ.L #0x2,D0                         | D0 = 2 bytes of params (alertID)
FREEALERT_CONT_2:
        BRA.W   CLOSEDIALOG_CONT_2              | dispatch to common epilogue

| ----------------------------------------------------------
| FREEALERT_CONT_3
| Called during boot.
FREEALERT_CONT_3:
        BSET    #0x7,(A3)                       | lock item list handle
        BSR.W   FINDDITEM_CONT                  | walk items (preload/free sub-resources)
        BCLR    #0x7,(A3)                       | unlock item list handle
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57444546,-(SP)               | push type = 'WDEF'
        CLR     -(SP)                           | push ID = 0 (standard window def)
        BRA.W   DISPOSEDIALOG_EXIT              | load WDEF resource and return

| ----------------------------------------------------------
| ParamText -- _ParamText ($A98B). (approx).
| Pascal: procedure ParamText(param0, param1, param2,
| param3: Str255);
| Updates DAStrings[0..3] with caller-supplied Pascal strings,
| disposing any previously-installed strings. NIL parameters
| leave the corresponding slot unchanged. Used by Alert/Dialog
| to substitute text into ^0/^1/^2/^3 placeholders in DITL items.
ParamText:
        LEA.L   (DAStrings+0x10).w,A1           | A1 = past end of DAStrings[3] array
        MOVEQ.L #0x3,D2                         | D2 = 3: process 4 strings (^0 to ^3)
PARAMTEXT_LOOP:
        MOVE.L  4(SP),D1                        | D1 = string pointer parameter
        MOVE.L  -(A1),A0                        | A0 = existing handle for this slot
        BEQ.B   PARAMTEXT_SKIP                  | NIL param - skip this slot
        MOVE.L  A0,D0                           | test existing handle
        BEQ.B   PARAMTEXT_NO                    | no old handle - just set new one
        _DisposeHandle                          | dispose previous string handle
PARAMTEXT_NO:
        MOVE.L  D1,A0                           | A0 = caller's string pointer
        BSR.W   ENTRY_5                         | build new handle from string
        MOVE.L  A0,(A1)                         | store new handle in DAStrings
PARAMTEXT_SKIP:
        MOVE.L  (SP)+,(SP)                      | collapse stack to drop param
        DBRA    D2,PARAMTEXT_LOOP               | loop for all 4 ParamText slots
        RTS                                     | return after updating strings
| ----------------------------------------------------------
|
| _ErrorSound ($A98C): set the sound procedure used by the alerts
| Pascal: PROCEDURE ErrorSound(soundProc: ProcPtr);
| Stores soundProc into DABeeper.
|
ErrorSound:
        MOVE.L  (SP)+,A0                        | A0 = caller return address
        MOVE.L  (SP)+,(DABeeper).w              | DABeeper := soundProc
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetDItem -- _GetDItem ($A98D).
| Pascal: procedure GetDItem(theDialog: DialogPtr; itemNo: INTEGER;
| VAR itemType: INTEGER;
| VAR item: Handle;
| VAR box: Rect);
| Returns information about a dialog item: its bounding rect,
| type, and handle/proc pointer.
GetDItem:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  22(A6),A4                       | A4 = dialog pointer
        BSR.W   DRAWDIALOG_CONT_2               | set up port, load item list
        MOVE    20(A6),D3                       | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR.W   ENTRY_5_CONT                    | get item entry A2 for index D3
        BEQ.B   GETDITEM_SKIP                   | item not found - skip
        LEA.L     4(A2),A0                      | A0 = item's bounding rect
        MOVE.L  8(A6),A1                        | A1 = caller's rect pointer
        MOVE.L  (A0)+,(A1)+                     | copy top-left of rect
        MOVE.L  (A0)+,(A1)+                     | copy bottom-right of rect
        MOVEM.L 12(A6),A0-A1                    | A0=item-handle ptr, A1=item-type ptr
        MOVE.L  (A2),(A0)                       | store item handle/proc
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  12(A2),D0                       | D0 = item type byte
        MOVE    D0,(A1)                         | store item type as word
GETDITEM_SKIP:
        BSR.W   CLOSEDIALOG_NO_2_CONT_2         | restore port, clear lock
        MOVEQ.L #0x12,D0                        | 18 bytes of params
GETDITEM_CONT:
        BRA.W   FREEALERT_CONT_2                | dispatch to common epilogue

| ----------------------------------------------------------
| SetDItem -- _SetDItem ($A98E).
| Pascal: procedure SetDItem(theDialog: DialogPtr; itemNo: INTEGER;
| itemType: INTEGER; item: Handle;
| box: Rect);
| Updates a dialog item's bounding rect, handle/proc pointer,
| and type byte.
SetDItem:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  20(A6),A4                       | A4 = dialog pointer
        BSR.W   DRAWDIALOG_CONT_2               | set up port, load item list
        MOVE    18(A6),D3                       | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR.W   ENTRY_5_CONT                    | get item entry A2 for index D3
        BEQ.B   SETDITEM_SKIP                   | item not found - skip
        MOVE.L  8(A6),A0                        | A0 = new bounding rect pointer
        LEA.L     4(A2),A1                      | A1 = item's rect field
        MOVE.L  (A0)+,(A1)+                     | copy new top-left
        MOVE.L  (A0)+,(A1)+                     | copy new bottom-right
        MOVE.L  12(A6),(A2)                     | store new item handle/proc
        MOVE.B  17(A6),12(A2)                   | store new item type byte
SETDITEM_SKIP:
        BSR.W   CLOSEDIALOG_NO_2_CONT_2         | restore port, unlock items
        MOVEQ.L #0x10,D0                        | D0 = 16 bytes of params
SETDITEM_CONT:
        BRA.B   GETDITEM_CONT                   | dispatch to common epilogue

| ----------------------------------------------------------
| GetIText -- _GetIText ($A990).
| Pascal: procedure GetIText(item: Handle; VAR text: Str255);
| Reads text from a dialog item's text handle and returns it as
| a Pascal string (length-prefixed). Clamps to 255 bytes max.
| Note: D1=255 is computed BEFORE the dialog prologue (MOVEQ +
| SUBQ pair); the prologue's LINK doesn't disturb D1.
GetIText:
        MOVEQ.L #0x0,D1                         | D1 = 0
        SUBQ.B  #0x1,D1                         | D1 = 255 (max Pascal string length)
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  8(A6),A1                        | A1 = destination string pointer
        MOVE.L  12(A6),A0                       | A0 = text handle from item
        _GetHandleSize                          | D0 = text length
        CMP.L   D1,D0                           | clamp to 255 max
        BLE.B   GETITEXT_OK                     | under limit - use as-is
        MOVE.L  D1,D0                           | cap at 255 bytes
GETITEXT_OK:
        MOVE.B  D0,(A1)+                        | store length byte in Pascal string
        MOVE.L  (A0),A0                         | dereference text handle
        _BlockMove                              | copy text data to destination
        BRA.B   SETITEXT_CONT                   | dispatch to common epilogue

| ----------------------------------------------------------
| SetIText -- _SetIText ($A98F).
| Pascal: procedure SetIText(item: Handle; text: Str255);
| Replaces a dialog item's text handle contents with a new
| Pascal string. Walks WindowList looking for dialogs that own
| this item handle so the redraw can be scheduled.
SetIText:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  8(A6),A0                        | A0 = Pascal string source
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  (A0)+,D0                        | D0 = string length, A0 = string data
        MOVE.L  12(A6),A1                       | A1 = text handle to replace
        MOVE.L  A1,D6                           | D6 = text handle (for matching later)
        _PtrToXHand                             | replace handle contents with new text
        MOVE.L  (WindowList).w,A4               | A4 = first window in window list
SETITEXT_NEXT:
        CMPI    #0x2,windowKind(A4)             | is this a dialog window?
        BNE.B   SETITEXT_SKIP                   | not a dialog - skip window
        BSR.W   DRAWDIALOG_CONT_2               | set up port, load item list
        MOVEQ.L #-0x1,D3                        | start item scan from beginning
SETITEXT_NEXT_2:
        BSR.W   DLGMGR_NEXT_4                   | advance to next dialog item
        BEQ.B   SETITEXT_DONE                   | end of items - go cleanup
        CMP.L   (A2),D6                         | does this item use the same text handle?
        BNE.B   SETITEXT_NEXT_2                 | no - check next item
        CMP     editField(A4),D3                | is this the active edit field?
        BNE.B   SETITEXT_NO                     | no - just redraw the text
        MOVE.L  0xA0(A4),-(SP)                  | push TE handle
        _TECalText                              | recalculate text layout after change
SETITEXT_NO:
        PEA.L     -0x28(A6)                     | push item rect for erase
        MOVE.L  (SP),-(SP)                      | push rect again for ValidRect
        _EraseRect                              | erase old text area
        BSR.W   DLGMGR_CONT_18                  | redraw this dialog item
        _ValidRect                              | remove rect from update region
SETITEXT_DONE:
        BSR.W   CLOSEDIALOG_NO_2_CONT_2         | restore port, unlock items
SETITEXT_SKIP:
        MOVE.L  nextWindow(A4),A4               | A4 = next window in z-ordered list
        MOVE.L  A4,D0                           | test if more windows in list
        BNE.B   SETITEXT_NEXT                   | more windows - keep walking
SETITEXT_CONT:
        MOVEQ.L #0x8,D0                         | D0 = 8 bytes of params
SETITEXT_CONT_2:
        BRA.B   SETDITEM_CONT                   | jump back to shared BRA -> cleanup

| ----------------------------------------------------------
| SelIText -- _SelIText ($A97E).
| Pascal: procedure SelIText(theDialog: DialogPtr; itemNo: INTEGER;
| selStart, selEnd: INTEGER);
| Selects a text range in a dialog's editable text item. The
| selStart and selEnd values are passed combined in D2 (high =
| selEnd, low = selStart) to the underlying edit-field routine.
SelIText:
        BSR.W   MODALDIALOG_CONT_3              | dialog prologue
        MOVE.L  14(A6),A4                       | A4 = dialog pointer
        BSR.W   DRAWDIALOG_CONT_2               | set up port, load item list
        MOVE    12(A6),D3                       | D3 = item number (1-based)
        SUBQ.W  #0x1,D3                         | convert to 0-based index
        BSR.W   ENTRY_5_CONT                    | get item entry A2 for index D3
        MOVE.L  8(A6),D2                        | D2 = selEnd (low word) from params
        SWAP    D2                              | D2 high = selEnd, low = selStart
        BSR.W   ENTRY_2                         | select text range in edit field
        BSR.W   CLOSEDIALOG_NO_2_CONT_2         | restore port, clear lock
        MOVEQ.L #0xA,D0                         | 10 bytes of params to clean up
        BRA.B   SETITEXT_CONT_2                 | dispatch to common epilogue
FINDDITEM_CONT:
        MOVEM.L  D0-A4,-(SP)                    | save all working registers
        MOVEQ    #-0x1,D3                       | D3 = -1 (start before item 0)
FINDDITEM_EXIT_2:
        BSR.W   DLGMGR_NEXT_4                   | advance to next dialog item
        BNE.B   ENTRY                           | item found - process it
        MOVEM.L (SP)+,D0-A4                     | no more items - restore registers
        RTS                                     | return when no more items found

| ----------------------------------------------------------
| FINDDITEM_CONT_2 - get item handle and type from item entry
| Called during boot.
FINDDITEM_CONT_2:
        MOVE.L  (A2),A0                         | A0 = item handle/proc pointer
        MOVE.B  0xC(A2),D0                      | D0 = item type byte
        RTS                                     | return item handle in A0 and type in D0
ENTRY:
        BSR.B   FINDDITEM_CONT_2                | A0=item handle, D0=type byte
        PEA.L   FINDDITEM_EXIT_2(PC)            | push loop continuation as RTS
        CMPI    #0x1,D4                         | D4=2 (dispose) or D4>=2 (special)?
        BGT.W   DLGMGR_CONT_24                  | dispose mode - free item
        BEQ.W   DLGMGR_CONT_18                  | nil: need to create from DITL data
        TST     D4                              | D4=0 (create) vs D4=-1 (preload)?
        BEQ.B   DLGMGR_CONT_9                   | create mode - go build control
        BTST    #0x2,D0                         | test resource-item bit (bit 2)
        BNE.B   DLGMGR_CONT                     | yes - go load resource type
        ROXR.W  #0x7,D0                         | rotate out item-type bits
        BMI.B   DLGMGR_CONT_4                   | ICON item type
        BCS.B   DLGMGR_CONT_5                   | PICT item type
        RTS                                     | skip - non-resource item type
DLGMGR_CONT:
        ANDI    #0x3,D0                         | isolate low 2 bits = subtype
        CMPI    #0x3,D0                         | CTRL subtype = 3?
        BNE.B   DLGMGR_CONT_3                   | no - go load CDEF
        PEA.L   DLGMGR_CONT_2(PC)               | push CTRL post-load handler
        MOVE.L  #0x434E544C,D1                  | D1 = 'CNTL' resource type
        BRA.B   DLGMGR_CONT_6                   | dispatch to GetResource
DLGMGR_CONT_2:
        MOVEA.L  (A2),A1                        | A1 = control template data
        MOVE    16(A1),D0                       | push text handle (result in A0)
DLGMGR_CONT_3:
        MOVE.L  #0x43444546,D1                  | 'ICON' resource type
        BRA.B   DLGMGR_CONT_7                   | go load 'ICON' resource
DLGMGR_CONT_4:
        MOVE.L  #0x49434F4E,D1                  | 'PICT' resource type
        BRA.B   DLGMGR_CONT_6                   | dispatch to GetResource
DLGMGR_CONT_5:
        MOVE.L  #0x50494354,D1                  | D1 = 'PICT' resource type
DLGMGR_CONT_6:
        MOVE    14(A2),D0                       | push resource type
DLGMGR_CONT_7:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  D1,-(SP)                        | push resource type
        MOVE    D0,-(SP)                        | push resource ID
        _GetResource                            | load the requested resource
        MOVE.L  (SP)+,A2                        | A2 = resource handle
        CMPI    #-0x1,D4                        | D4=-1 means free mode?
        BEQ.B   DLGMGR_CONT_8                   | go check/mark purgeable state
        BCLR    #0x6,(A2)                       | clear handle's purgeable flag for use
        RTS                                     | return after preload

| ----------------------------------------------------------
| DLGMGR_CONT_8 - mark handle purgeable if the resource itself is purgeable
| Called with D4=-1 during pre-load to preserve resource's purgeable attr.
| ----------------------------------------------------------
DLGMGR_CONT_8:
        SUBQ.W  #0x2,SP                         | space for GetResAttrs result
        MOVE.L  A2,-(SP)                        | push resource handle
        _GetResAttrs                            | D0 = current resource attrs
        MOVE    (SP)+,D0                        | D0 = attrs from stack
        BTST    #0x5,D0                         | test resPurgeable bit
        BEQ.B   DLGMGR_NO                       | not purgeable - leave it
        BSET    #0x6,(A2)                       | mark handle's purgeable flag
DLGMGR_NO:
        RTS                                     | return after attr update
DLGMGR_CONT_9:
        MOVE.L  A0,D1                           | test if existing handle is set
        BEQ.B   DLGMGR_EMPTY                    | NIL - need to create handle
        RTS                                     | already created - skip
DLGMGR_EMPTY:
        BTST    #0x2,D0                         | test ctrlItem bit
        BNE.B   DLGMGR_CONT_14                  | ctrlItem: create control
        ROXR.W  #0x5,D0                         | rotate item-type bits low
        BCS.B   DLGMGR_CONT_10                  | text item - go alloc handle
        BMI.B   DLGMGR_CONT_10                  | edit text - go alloc handle
        ROXR.W  #0x2,D0                         | rotate icon/pict bit out
        BMI.B   DLGMGR_CONT_11                  | ICON item - go load icon
        BCS.B   DLGMGR_CONT_12                  | PICT item - go load picture
        RTS                                     | unknown type - skip
DLGMGR_CONT_10:
        LEA.L     13(A2),A0                     | A0 = inline string in DITL
        MOVEQ.L #0x0,D0                         | clear D0 for length byte
        MOVE.B  (A0)+,D0                        | D0 = string length
        _PtrToHand                              | allocate handle from text
        MOVE.L  A0,-(SP)                        | push new handle for store
        BRA.B   DLGMGR_CONT_16                  | store handle in item entry
DLGMGR_CONT_11:
        MOVE.L  #0x49434F4E,D0                  | D0 = 'ICON' resource type
        BRA.B   DLGMGR_CONT_13                  | dispatch to GetResource
DLGMGR_CONT_12:
        MOVE.L  #0x50494354,D0                  | D0 = 'PICT' resource type
DLGMGR_CONT_13:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  D0,-(SP)                        | call subroutine via A0
        MOVE    14(A2),-(SP)                    | push resource ID from item
        _GetResource                            | load icon or picture resource
        BRA.B   DLGMGR_CONT_16                  | store handle in item entry
DLGMGR_CONT_14:
        ANDI    #0x3,D0                         | isolate ctrl-subtype low 2 bits
        CMPI    #0x3,D0                         | CDEF-from-resource subtype?
        BNE.B   DLGMGR_NO_2                     | no - build standard control
        SUBQ.W  #0x4,SP                         | space for GetNewControl result
        MOVE    14(A2),-(SP)                    | push CNTL resource ID
        MOVE.L  A4,-(SP)                        | push picture handle
        _GetNewControl                          | build control from CNTL res
        MOVE.L  (SP),-(SP)                      | push control handle for move
        MOVE.L  4(A2),-(SP)                     | push topLeft from item rect
        _MoveControl                            | move control to item position
        BRA.B   DLGMGR_CONT_15                  | validate rect, store handle

| ----------------------------------------------------------
| Create standard button/checkbox/radio control from DITL inline data.
| Builds NewControl params: owner, rect, title, visible, value=1,
| min=0, procID=subtype*16, refCon=0.
| ----------------------------------------------------------
DLGMGR_NO_2:
        SUBQ.W  #0x4,SP                         | space for NewControl result
        MOVE.L  A4,-(SP)                        | push owner dialog window
        PEA.L     -0x28(A6)                     | push item bounding rect
        PEA.L     13(A2)                        | push title from inline DITL
        ST      -(SP)                           | -(SP) := -1 (true)
        CLR.L   -(SP)                           | push initial value=0, max=0
        MOVE    #0x1,-(SP)                      | dup for EraseRect
        MOVE    D0,-(SP)                        | push procID = ctrl subtype*16
        CLR.L   -(SP)                           | push refCon = 0
        _NewControl                             | build button/checkbox/radio
DLGMGR_CONT_15:
        PEA.L     -0x28(A6)                     | push item rect for ValidRect
        _ValidRect                              | remove rect from update region
DLGMGR_CONT_16:
        MOVE.L  (SP)+,(A2)                      | store new handle in item entry
        RTS                                     | return after creating item
DLGMGR_CONT_18:
        BSR.W   FINDDITEM_CONT_2                | A0=item handle, D0=type byte
        BTST    #0x2,D0                         | test ctrlItem bit
        BNE.B   DLGMGR_SKIP_2                   | control - skip (CDEF draws)
        ROXR.W  #0x5,D0                         | rotate item type bits low
        BCS.B   DLGMGR_CONT_22                  | statText - go draw text
        BMI.B   DLGMGR_CONT_22                  | editText - go draw + frame
        ROXR.W  #0x2,D0                         | rotate icon/pict bit out
        BMI.B   DLGMGR_CONT_20                  | ICON - go plot icon
        BCS.B   DLGMGR_CONT_21                  | PICT - go draw picture
        MOVE.L  (A2),D0                         | D0 = userItem proc pointer
        BEQ.B   DLGMGR_SKIP                     | NIL proc - skip drawing
        MOVE.L  A4,-(SP)                        | push owner dialog window
        MOVE    D3,-(SP)                        | push item index (zero-based)
        ADDQ.W  #0x1,(SP)                       | (SP) += 0x1
        MOVE.L  D0,A0                           | A0 = userItem proc address
        JSR     (A0)                            | call subroutine via A0
DLGMGR_SKIP:
        RTS                                     | return to caller (@ $EB5A)
DLGMGR_CONT_20:
        PEA.L     -0x28(A6)                     | push item rect for plot
        MOVE.L  (A2),-(SP)                      | push icon handle
        MOVE.L  (SP),-(SP)                      | dup handle for LoadResource
        _LoadResource                           | ensure icon data is loaded
        _PlotIcon                               | draw icon in item rect
        RTS                                     | return after icon plot
DLGMGR_CONT_21:
        MOVE.L  (A2),-(SP)                      | push picture handle
        MOVE.L  (SP),-(SP)                      | dup handle for LoadResource
        _LoadResource                           | ensure picture data is loaded
        PEA.L     -0x28(A6)                     | push item rect for draw
        _DrawPicture                            | draw picture in item rect
DLGMGR_SKIP_2:
        RTS                                     | return to caller (@ $EB76)

| ----------------------------------------------------------
| Draw statText or editText item.
| If this is the active editText field, erase and TEUpdate.
| Otherwise, perform ParamText substitution (^0..^3) then TextBox.
| After drawing, if editText, draw 3-pixel frame around display rect.
| ----------------------------------------------------------
DLGMGR_CONT_22:
        SMI     D7                              | D7 := (N == 1)
        CMP     editField(A4),D3                | is this the active edit field?
        BNE.B   DLGMGR_NO_3                     | no - go draw via ParamText
        PEA.L     -0x28(A6)                     | push item rect for erase
        MOVE.L  (SP),-(SP)                      | dup rect for ValidRect later
        _EraseRect                              | erase old text area
        MOVE.L  0xA0(A4),-(SP)                  | push TE handle (dialog's edit field)
        _TEUpdate                               | update TE display
DLGMGR_CONT_23:
        TST.B   D7                              | D7=true means statText (no frame)
        BNE.B   DLGMGR_SKIP_3                   | statText - no frame to draw
        LEA.L     -0x28(A6),A0                  | A0 = item rect address
        MOVEQ.L #0x1,D0                         | inset left = 1
        MOVEQ.L #0x1,D1                         | inset top = 1
        MOVEQ.L #0x3,D2                         | inset bottom-right = 3
        BSR.W   ENTRY_4                         | draw 3-pixel frame around edit
DLGMGR_SKIP_3:
        RTS                                     | return after drawing text
DLGMGR_NO_3:
        MOVEM.L D2-D7/A3-A4,-(SP)               | save additional registers
        MOVE.L  (A2),A0                         | A0 = source text handle
        _HandToHand                             | duplicate text handle for sub
        MOVE.L  A0,D7                           | D7 = working text-copy handle
        MOVEQ.L #0x2,D5                         | D5 = key length (^N = 2 chars)
        LEA.L     (DAStrings).w,A3              | A3 -> ParamText substitution-string handle table
        LEA     DLGMGR_CONT_22_CONT_6(PC),A4    | A4 = ParamText keys table
        MOVEQ.L #0x3,D6                         | D6 = 3 (loop for ^0..^3)
DLGMGR_CONT_22_LOOP:
        MOVEQ.L #0x0,D3                         | D3 = 0 (start search at 0)
DLGMGR_CONT_22_CONT_3:
        MOVEQ.L #0x0,D0                         | clear D0 for length byte
        MOVE.L  (A3),D4                         | D4 = ParamText handle for ^N
        BEQ.B   DLGMGR_CONT_22_CONT_4           | NIL - substitute empty string
        MOVE.L  D4,A0                           | A0 = ParamText handle
        _HLock                                  | lock handle for safe access
        MOVE.L  (A0),A0                         | A0 = master pointer
        MOVE.B  (A0)+,D0                        | D0 = string length
DLGMGR_CONT_22_CONT_4:
        SUBQ.W  #0x4,SP                         | space for Munger result
        MOVE.L  D7,-(SP)                        | push working text handle
        MOVE.L  D3,-(SP)                        | get event message (dialog window ptr)
        MOVE.L  A4,-(SP)                        | push key string ptr
        MOVE.L  D5,-(SP)                        | push key length (2)
        MOVE.L  A0,-(SP)                        | push teHandle for TE call
        MOVE.L  D0,-(SP)                        | push dialog as port
        _Munger                                 | substitute ^N with text
        MOVE.L  (SP)+,D3                        | D3 = position of next match
        BPL.B   DLGMGR_CONT_22_CONT_3           | more matches - keep replacing
        TST.L   D4                              | was a real handle locked?
        BEQ.B   DLGMGR_CONT_22_CONT_5           | no - skip unlock
        MOVE.L  D4,A0                           | A0 = ParamText handle to unlock
        _HUnlock                                | unlock handle after use
DLGMGR_CONT_22_CONT_5:
        ADDQ.W  #0x2,A4                         | advance to next key string
        ADDQ.W  #0x4,A3                         | advance to next DAStrings slot
        DBRA    D6,DLGMGR_CONT_22_LOOP          | loop for all 4 ParamText slots
        MOVE.L  D7,A0                           | A0 = working text handle
        BSET    #0x7,(A0)                       | lock handle (high bit of master)
        MOVE.L  (A0),-(SP)                      | push text pointer for TextBox
        _GetHandleSize                          | D0 = current text size
        MOVE.L  D0,-(SP)                        | push text length
        PEA.L     -0x28(A6)                     | push item rect for layout
        CLR     -(SP)                           | push justification = teJustLeft
        _TETextBox                              | draw substituted text in rect
        MOVE.L  D7,A0                           | A0 = working text handle
        _DisposeHandle                          | free temporary text copy
        MOVEM.L (SP)+,D2-D7/A3-A4               | restore working registers
        BRA.B   DLGMGR_CONT_23                  | draw frame if editText
DLGMGR_CONT_22_CONT_6:                          | ParamText substitution keys
        .ascii  "^0"                            | key #0 (matched by ParamText ^0 marker)
        .ascii  "^1"                            | key #1
        .ascii  "^2"                            | key #2
        .ascii  "^3"                            | key #3

| ----------------------------------------------------------
| Dispose item resources (D4=2).
| Frees handles for text/icon/picture items, disposes controls.
| Item type dispatch: userItem=RTS, ctrlItem=DisposControl,
| statText/editText=DisposHandle, iconItem/picItem=DisposHandle.
| ----------------------------------------------------------
DLGMGR_CONT_24:
        ROR     #0x3,D0                         | rotate type bits to test high
        BCS.W   DLGMGR_SKIP_2                   | userItem - leave handle alone
        ROXR.W  #0x2,D0                         | rotate icon/pict bit out
        BCS.B   DLGMGR_CONT_26                  | statText/PICT - dispose handle
        BMI.B   DLGMGR_CONT_26                  | editText/ICON - dispose handle
DLGMGR_CONT_25:
        CLR.L   (A2)                            | clear handle in item entry
        RTS                                     | return after disposal
DLGMGR_CONT_26:
        _DisposeHandle                          | free text/icon/picture handle
        BRA.B   DLGMGR_CONT_25                  | clear item slot, return
        MOVE.L  A0,-(SP)                        | push control handle
        _DisposeControl                         | dispose control record
        BRA.B   DLGMGR_CONT_25                  | clear item slot, return
DLGMGR_CONT_28:
        MOVE.L  -0x4A(A6),A0                    | push character for TEKey
        TST     0xA4(A0)                        | test target dialog's TE handle
        BMI.B   DLGMGR_EXIT                     | no TE - return -1 (no item hit)
        MOVE.L  0xA0(A0),-(SP)                  | push TE handle of target dialog
        MOVE.L  A0,-(SP)                        | push target dialog as port
        _SetPort                                | set target dialog as cur port
        BTST    #0x0,-0x3D(A6)                  | test activate flag (bit 0)
        BEQ.B   DLGMGR_NO_4                     | activate=0 - deactivate TE
        _TEActivate                             | activate edit field
        BRA.B   DLGMGR_SKIP_5                   | restore port after activation
DLGMGR_NO_4:
        _TEDeactivate                           | deactivate edit field
DLGMGR_SKIP_5:
        MOVE.L  A4,-(SP)                        | push original dialog as port
        _SetPort                                | restore original grafPort
        BRA.B   DLGMGR_EXIT                     | return -1 (no item hit)
RETURNS_15:
        MOVE    -0x4C(A6),D0                    | D0 = event type from local
        SUBQ.W  #0x1,D0                         | test mouseDown (1)
        BEQ.W   DLGMGR_CONT_32                  | mouseDown - dispatch click
        SUBQ.W  #0x2,D0                         | test keyDown (3)
        BEQ.B   DLGMGR_CONT_30                  | keyDown - handle key event
        SUBQ.W  #0x2,D0                         | decrement pad count
        BEQ.B   DLGMGR_CONT_30                  | autoKey - handle key event
        SUBQ.W  #0x1,D0                         | test updateEvt (6)
        BEQ.B   DLGMGR_CONT_29                  | updateEvt - redraw dialog
        SUBQ.W  #0x2,D0                         | test activateEvt (8)
        BEQ.B   DLGMGR_CONT_28                  | activate - de/activate TE
        TST     editField(A4)                   | any active edit field?
        BMI.B   DLGMGR_EXIT                     | no - return no item hit
        MOVE.L  0xA0(A4),-(SP)                  | push TE handle for idle
        _TEIdle                                 | flash text caret on TE idle
DLGMGR_EXIT:
        MOVEQ    #-0x1,D3                       | D3 = -1 (no item hit)
        RTS                                     | return failure result
DLGMGR_CONT_29:
        MOVE.L  A4,-(SP)                        | push dialog window
        MOVE.L  (SP),-(SP)                      | dup for EndUpdate
        MOVE.L  (SP),-(SP)                      | dup for DrawDialog
        _BeginUpDate                            | set visRgn=updateRgn for redraw
        BSR.W   DrawDialog                      | redraw all dialog items
        _EndUpDate                              | restore visRgn after update
        BRA.B   DLGMGR_EXIT                     | return D3=-1 (no item hit)

| ----------------------------------------------------------
| Handle keyDown/autoKey: dispatch to TEKey or Tab-to-next-field.
| event.message low byte at -0x47(A6) = character code.
| ----------------------------------------------------------
DLGMGR_CONT_30:
        MOVE.B  -0x47(A6),D1                    | get typed character from event.message
        CMPI.B  #0x9,D1                         | is character a Tab (0x09)?
        BEQ.B   DLGMGR_NEXT_2                   | yes: advance to next editText field
        MOVE    editField(A4),D3                | get active edit field index
        BMI.B   DLGMGR_EXIT                     | no edit field: ignore keystroke
        MOVE    D1,-(SP)                        | push character for TEKey
        MOVE.L  teHandle(A4),-(SP)              | push teHandle
        _TEKey                                  | insert typed character into TE
        BRA.B   DLGMGR_EXIT_2                   | return current edit field as itemHit
DLGMGR_NEXT_2:
        MOVE    editField(A4),D3                | D3 = current edit field index
DLGMGR_SKIP_6:
        BSR.B   DLGMGR_NEXT_4                   | advance to next item entry
        BEQ.B   DLGMGR_CONT_31                  | end of items - wrap to start
        CMP     editField(A4),D3                | looped back to same field?
        BEQ.B   DLGMGR_EXIT                     | yes - no other field to focus
        BTST    #0x4,12(A2)                     | test editText flag (bit 4)
        BEQ.B   DLGMGR_SKIP_6                   | not editable - keep searching
        MOVE.L  #0x7FFF,D2                      | D2 = selStart 0, selEnd 32767
        BSR.W   ENTRY_2                         | select all in next edit field
DLGMGR_EXIT_2:
        BRA.B   DLGMGR_EXIT_4                   | return D3 = item hit
DLGMGR_CONT_31:
        MOVEQ.L #-0x1,D3                        | D3 = -1 (start before item 0)
        TST     editField(A4)                   | any edit field defined?
        BPL.B   DLGMGR_SKIP_6                   | yes - wrap to first item
DLGMGR_EXIT_3:
        BRA.B   DLGMGR_EXIT                     | no edit fields - return -1
| Called by: DRAWDIALOG_LOOP, CLOSEDIALOG_NO_2, SETITEXT_NEXT_2, FINDDITEM_EXIT_2, DLGMGR_SKIP_6 (and 1 more)
DLGMGR_NEXT_4:
        ADDQ.W  #0x1,D3                         | advance item index by one
        BSR.W   ENTRY_5_CONT                    | get item entry A2 for index D3
        RTS                                     | return Z=0 if item exists

| ----------------------------------------------------------
| Handle mouseDown: convert click to local coords, find which
| DITL item was clicked, then dispatch by item type.
| ----------------------------------------------------------
DLGMGR_CONT_32:
        MOVE.L  -0x42(A6),-28(A6)               | copy event point to local
        PEA.L     -28(A6)                       | push point address
        _GlobalToLocal                          | convert click to local coords
        MOVEQ.L #-0x1,D3                        | D3 = -1 (start before item 0)
DLGMGR_NEXT_3:
        BSR.B   DLGMGR_NEXT_4                   | advance to next item entry
        BEQ.B   DLGMGR_EXIT_3                   | end of items - no item hit
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  -28(A6),-(SP)                   | push local click point
        PEA.L     -0x28(A6)                     | push item bounding rect
        _PtInRect                               | does click hit this item?
        TST.B   (SP)+                           | did click intersect this DITL item?
        BEQ.B   DLGMGR_NEXT_3                   | not in this item: try next
        BTST    #0x2,12(A2)                     | is this a ctrlItem?
        BEQ.B   DLGMGR_NO_5                     | no: check for editText click
        SUBQ.W  #0x2,SP                         | space for FindControl result
        MOVE.L  -28(A6),-(SP)                   | push click point (local coordinates)
        MOVE.L  A4,-(SP)                        | push theWindow (the dialog)
        PEA.L     -24(A6)                       | push ptr for control handle result
        _FindControl                            | find which control was clicked
        MOVE    (SP)+,D0                        | D0 = partCode (zero = no hit)
        BEQ.B   DLGMGR_EXIT_3                   | no hit -> skip
        SUBQ.W  #0x2,SP                         | space for TrackControl result
        MOVE.L  -24(A6),-(SP)                   | push control handle
        MOVE.L  -28(A6),-(SP)                   | push click point
        MOVE.L  (MinusOne).w,-(SP)              | push nil actionProc (-1 = default)
        _TrackControl                           | track mouse until released
        TST     (SP)+                           | was control actually clicked?
        BEQ.B   DLGMGR_EXIT_3                   | no: mouse released outside, return -1
DLGMGR_EXIT_4:
        BRA.B   DLGMGR_EXIT_5                   | control was clicked: return item
DLGMGR_NO_5:
        BTST    #0x4,12(A2)                     | test editText bit in item type
        BEQ.B   DLGMGR_EXIT_5                   | not editText: return this item as hit
        CMP     0xA4(A4),D3                     | clicking in already-active field?
        BEQ.B   DLGMGR_OK                       | yes: just pass to TEClick
        MOVEQ.L #0x0,D2                         | D2=0: place insertion point, no select
        BSR.B   ENTRY_2                         | switch to clicked edit field
DLGMGR_OK:
        TST     0xA4(A4)                        | is there an active edit field now?
        BMI.B   DLGMGR_EXIT_5                   | no: skip TEClick
        MOVE.L  -28(A6),-(SP)                   | push click point
        BTST    #0x1,-0x3E(A6)                  | test shiftKey in event modifiers
        SNE     -(SP)                           | push extend flag (true if Shift held)
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle (+$A0) for TEClick
        _TEClick                                | handle text selection/insertion
DLGMGR_EXIT_5:
        BTST    #0x7,12(A2)                     | test itemDisable bit
        BNE.W   DLGMGR_EXIT_3                   | disabled item: return -1
        ADDQ.W  #0x1,D3                         | convert 0-based to 1-based item number
        RTS                                     | return D3 = item number hit
ENTRY_2:
        TST     0xA4(A4)                        | is there a current edit field?
        BMI.B   DLGMGR_SKIP_7                   | no current field: skip deactivation
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle (+$A0) for TEDeactivate
        _TEDeactivate                           | hide caret/selection in old field
DLGMGR_SKIP_7:
        BSR.B   DLGMGR_CONT_33                  | install new field's text into TERec
        TST     0xA4(A4)                        | did install set a valid edit field?
        BMI.B   DLGMGR_SKIP_8                   | -1 = no edit field: skip activation
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TEActivate                             | show caret/selection in new field
DLGMGR_SKIP_8:
        RTS                                     | return from edit field setup
ENTRY_3:                                        | activate new edit field (D3 = index)
        CMP     editField(A4),D3                | already the active edit field?
        BEQ.B   DLGMGR_EXIT_6                   | yes, nothing to do
DLGMGR_CONT_33:
        MOVE.L  (A2),D0                         | D0 = item handle (text handle for editText)
        BLE.B   DLGMGR_EXIT_6                   | nil or negative: no valid text, return
        MOVE    D3,0xA4(A4)                     | set new active edit field index
        BMI.B   DLGMGR_EXIT_6                   | -1 = no field: just clear and return
        MOVE.L  0xA0(A4),A0                     | A0 = teHandle from DialogRecord
        MOVE.L  (A0),A1                         | A1 = dereferenced TERec pointer
        MOVE.L  D0,0x3E(A1)                     | store text handle in TERec.hText (+0x3E)
        MOVEQ.L #-0x2,D0                        | sentinel: don't change selection
        CMP.L   D0,D2                           | D2 = -2 means keep existing selection
        BEQ.B   DLGMGR_SKIP_9                   | skip selection update
        MOVE.L  D2,0x20(A1)                     | set TERec.selStart/selEnd (+0x20)
DLGMGR_SKIP_9:
        LEA.L     (A1),A0                       | A0 = TERec base for destRect/viewRect
        MOVE.L  -0x28(A6),(A0)+                 | copy item rect topLeft to destRect
        MOVE.L  -0x24(A6),(A0)+                 | copy item rect botRight to destRect
        MOVE.L  -0x28(A6),(A0)+                 | copy item rect topLeft to viewRect
        MOVE.L  -0x24(A6),(A0)+                 | copy item rect botRight to viewRect
        MOVE    D0,0x32(A1)                     | clear TERec.crOnly (D0=-2 sentinel)
        MOVE.L  0xA0(A4),-(SP)                  | push teHandle
        _TECalText                              | recalculate line starts for new text
DLGMGR_EXIT_6:
        RTS                                     | return from edit field activation

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
ENTRY_5:
        MOVEM.L D0-D2/A1-A2,-(SP)               | save regs (5 longs = 20 bytes)
        MOVE.L  A0,-(SP)                        | push string ptr for NewString
        _NewString                              | create handle with copy of string
        MOVE.L  (SP)+,A0                        | A0 = new string handle
        MOVEM.L (SP)+,D1-D2/A1-A2               | restore D1-D2/A1-A2 (skip saved D0)
        RTS                                     | return with new string handle in A0
ENTRY_5_CONT:
        MOVE.L  A3,D0                           | test items handle (A3)
        BEQ.B   ENTRY_5_CONT_2                  | nil handle: return nil
        MOVE.L  D0,-(SP)                        | push handle for LoadResource
        _LoadResource                           | ensure DITL data loaded in memory
        MOVE.L  (A3),A2                         | test search pointer
        MOVE    (A2)+,D0                        | D0 = item count - 1 (DITL stores count-1)
        TST     D3                              | target index < 0?
        BLT.B   ENTRY_5_CONT_2                  | negative index: return nil
        CMP     D3,D0                           | is target index within range?
        BLT.B   ENTRY_5_CONT_2                  | past end: return nil
        MOVE    D3,D0                           | D0 = number of items to skip
ENTRY_5_LOOP:
        TST     D0                              | any items left to skip?
        BEQ.B   ENTRY_5_CONT_3                  | at target: return rect via A2
        MOVEQ.L #0xE,D1                         | base = 14 fixed item bytes
        ADD.B   13(A2),D1                       | add data length byte at item+13
        ADDQ.W  #0x1,D1                         | +1 for round-up to even
        ANDI    #-0x2,D1                        | align to even byte boundary
        ADDA.W  D1,A2                           | advance A2 by item size
        DBRA    D0,ENTRY_5_LOOP                 | skip D0 items
ENTRY_5_CONT_2:
        SUBA.L  A2,A2                           | A2 = nil (past end of list)
ENTRY_5_CONT_3:
        LEA.L     4(A2),A0                      | A0 = ptr to item's display rect
        LEA.L     -0x28(A6),A1                  | A1 = ptr to local rect variable
        MOVE.L  (A0)+,(A1)+                     | copy rect topLeft (top, left)
        MOVE.L  (A0)+,(A1)+                     | copy rect botRight (bottom, right)
        MOVE.L  A2,D0                           | set Z flag: Z=1 if A2 is nil
        RTS                                     | return with Z flag set if past end

