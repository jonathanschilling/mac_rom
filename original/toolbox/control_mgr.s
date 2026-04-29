| Control Manager (tail block)
|
| This file holds the Control Manager:
| NewControl, DisposeControl, KillControls,
| ShowControl, HideControl, MoveControl,
| GetCRefCon, SetCRefCon, GetCtlAction, SetCtlAction, TrackControl,
| DrawControls, the embedded CDEF data tables, and the
| FindControl entry point. The bulk of the Control Manager bodies
| (NewControl, DisposeControl, KillControls, ShowControl, HideControl,
| MoveControl, SizeControl, HiliteControl, GetCRefCon, SetCRefCon,
| GetCTitle, SetCTitle, SetCtlValue, GetCtlValue, DragControl,
| TrackControl) physically lives at the tail of menu_mgr.s in classic;
| see also src/original/toolbox/menu_mgr.s.
|
| The corresponding Plus file (src/plus/toolbox/control_mgr.s) is
| organized completely differently: it starts the Resource Manager
| because Plus's Control Manager is consolidated in a single later
| file. Bodies do not align between the two trees on a file-by-file
| basis -- only the underlying ROM bytes do.
|
| ControlRecord (MPW 1.0 Controls.h):
| nextControl, contrlOwner, contrlRect, contrlVis, contrlHilite,
| contrlValue, contrlMin, contrlMax, contrlDefProc, contrlData,
| contrlAction, contrlRfCon, contrlTitle
|
| References:
| Inside Macintosh Vol I, Ch 10: The Control Manager (pp 311-340)

| ----------------------------------------------------------
| _NewControl ($A954)
| _NewControl ($A954): create a new control in a window
| Pascal: function NewControl(theWindow: WindowPtr; boundsRect: Rect;
| title: Str255; visible: BOOLEAN; value, min, max: INTEGER;
| procID: INTEGER; refCon: LongInt): ControlHandle;
NewControl:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L A2-A4,-(SP)                     | save registers
        LEA.L   0x22(A6),A4                     | A4 = first Pascal param (theWindow)
        MOVEQ.L #0x29,D0                        | base size = 41 bytes (ControlRecord)
        MOVEQ.L #0x0,D1                         | clear for byte extend
        MOVE.L  0x16(A6),A0                     | A0 = title string
        MOVE.B  (A0),D1                         | D1 = title length
        ADD.L   D1,D0                           | + title bytes
        _NewHandle                              | allocate ControlRecord handle
        MOVE.L  A0,A3                           | A3 = new ControlHandle
        MOVE.L  A0,(A4)                         | store as function result
        MOVE.L  (A3),A2                         | A2 = dereferenced ControlRecord
        MOVE.L  -(A4),A1                        | A1 = theWindow (pre-decrement walks params)
        MOVE.L  A1,contrlOwner(A2)              | contrlOwner = theWindow
        MOVE.L  wControlList(A1),(A2)           | nextControl = old head of window's control list
        MOVE.L  A3,wControlList(A1)             | insert as new head of control list
        LEA.L   contrlRect(A2),A1               | A1 = contrlRect field
        MOVE.L  -(A4),A0                        | A0 = boundsRect ptr
        MOVE.L  (A0)+,(A1)+                     | copy boundsRect.topLeft
        MOVE.L  (A0),(A1)                       | copy boundsRect.botRight
        CLR.B   contrlVis(A2)                   | initially invisible
        MOVE.L  A3,-(SP)                        | push ControlHandle
        MOVE.L  -(A4),-(SP)                     | push title string ptr
        _SetControlTitle                        | set control title
        MOVE.L  (A3),A2                         | re-dereference (may have moved)
        LEA.L   contrlVis(A2),A0                | A0 = contrlVis field
        SUBQ.W  #0x2,A4                         | skip past visible param (BOOLEAN is 2 bytes)
        TST.B   (A4)                            | visible param true?
        SNE.B   (A0)+                           | contrlVis = $FF if true, 0 if false
        CLR.B   (A0)+                           | contrlHilite = 0 (no hilite)
        MOVE    -(A4),(A0)+                     | contrlValue = value param
        MOVE    -(A4),(A0)+                     | contrlMin = min param
        MOVE    -(A4),(A0)+                     | contrlMax = max param
        MOVE    -(A4),D0                        | D0 = procID param
        LSR     #0x4,D0                         | D0 = CDEF resource ID (procID / 16)
NEWCONTROL_CONT_4:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x43444546,-(SP)               | dereference CDEF -> code ptr
        MOVE    D0,-(SP)                        | call subroutine via A0
        _GetResource                            | load CDEF resource
        MOVEQ.L #0x0,D0                         | retry ID = 0 (default CDEF)
        MOVE.L  (A3),A0                         | A0 = CDEF handle
        LEA.L     contrlDefHandle(A0),A0        | A0 = &24(A0)
        MOVE.L  (SP)+,(A0)                      | store CDEF handle in contrlDefHandle
        BEQ.B   NEWCONTROL_CONT_4               | nil -> retry with CDEF 0
        MOVE    (A4),D0                         | D0 = procID parameter
        ANDI    #0xF,D0                         | mask to variation code (low 4 bits)
        MOVE.B  D0,(A0)                         | stash variation in low byte of handle
        ADDQ.W  #0x4,A0                         | advance past contrlDefHandle field
        CLR.L   (A0)+                           | contrlData = nil
        CLR.L   (A0)+                           | contrlAction = nil
        MOVE.L  -(A4),(A0)+                     | contrlRfCon = caller's refCon
        MOVEQ.L #0x3,D0                         | message = initCntl (3)
        BSR.B   NEWCONTROL_FOUND                | save port, set owner port
        TST.B   20(A6)                          | visible param true?
        BEQ.B   NEWCONTROL_CONT_5               | invisible -> skip ShowControl
        MOVEQ.L #0x0,D1                         | param = 0 (whole control)
        BSR.B   NEWCONTROL_CONT_6               | draw if visible (no-op if not)
NEWCONTROL_CONT_5:
        MOVEM.L (SP)+,A2-A4                     | restore saved regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0x1A,SP                        | strip 26 bytes of params
        JMP     (A0)                            | RTS
NEWCONTROL_CONT_6:
        MOVEQ.L #0x0,D0                         | message = drawCntl (0)
        MOVE.L  (A3),A0                         | A0 = ControlRecord
        TST.B   16(A0)                          | control visible? (contrlVis)
        BEQ.B   NEWCONTROL_OK_RTS               | control already closed -> RTS at $D27E

| NEWCONTROL_FOUND: call CDEF proc for control A3
| D0 = message (0=draw, 1=test, 2=calc, 3=init, 4=dispose, 5=pos,
| 6=thumb, 7=drag, 8=autoTrack), D1 = param, A3 = ControlHandle
| Called by: DRAGCONTROL_CONT, NEWCONTROL_CONT_4, NEWCONTROL_CONT_3, DisposeControl, TestControl (and 3 more)
NEWCONTROL_FOUND:
        BSR.W   DRAGCONTROL_CONT_2              | save port, set control's owner port
        CLR.L   -(SP)                           | space for CDEF result (long)
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVEQ.L #0x0,D2                         | clear D2
        MOVE.B  contrlDefHandle(A0),D2          | D2 = variation code (low byte of handle)
        MOVE    D2,-(SP)                        | push variation code
        MOVE.L  A3,-(SP)                        | push ControlHandle
        MOVE    D0,-(SP)                        | push message
        MOVE.L  D1,-(SP)                        | push param
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  contrlDefHandle(A0),A0          | A0 = CDEF handle
        TST.L   (A0)                            | CDEF loaded? (master ptr non-nil?)
        BNE.B   NEWCONTROL_OK                   | CDEF resident -> skip reload
        MOVE.L  A0,-(SP)                        | push CDEF handle for LoadResource
        CLR.B   (SP)                            | clear variation code byte in handle
        _LoadResource                           | load the CDEF if purged
NEWCONTROL_OK:
        BSet    #0x7,(A0)                       | set lock bit on CDEF handle
        MOVE.L  (A0),A0                         | dereference CDEF -> code ptr
        JSR     (A0)                            | call CDEF proc
        MOVE.L  (SP)+,D0                        | pop CDEF result
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  contrlDefHandle(A0),A0          | A0 = CDEF handle
        BCLR    #0x7,(A0)                       | clear lock bit
NEWCONTROL_CONT_2:
        _SetPort                                | restore saved port
NEWCONTROL_OK_RTS:
        RTS                                     | return to caller

| ----------------------------------------------------------
| NEWCONTROL_CONT_3
| Called during boot.
| NEWCONTROL_CONT_3: erase and invalidate control's region (used when hiding/disposing)
| Sends calcCRgns (2) to CDEF to get control's region, then erases and invalidates it
NEWCONTROL_CONT_3:
        BSR.W   DRAGCONTROL_CONT_2              | save port, set owner port
        MOVEM.L A1-A4,-(SP)                     | save registers
        _NewRgn                                 | create temp region -> (SP)
        MOVE.L  (SP),A4                         | A4 = temp region handle
        MOVEQ.L #0x2,D0                         | D0 = calcCRgns message
        MOVE.L  A4,D1                           | D1 = region handle (param)
        BCLR    #0x1F,D1                        | clear high bit (whole region, not thumb)
        BSR.B   NEWCONTROL_FOUND                | CDEF computes control region
        _EraseRgn                               | erase the control's region
        MOVE.L  A4,-(SP)                        | push region for InvalRgn
        _InvalRgn                               | mark region for update
        MOVE.L  A4,-(SP)                        | push region for dispose
        _DisposeRgn                             | free temp region
        MOVEM.L (SP)+,A2-A4                     | restore registers
        BRA.B   NEWCONTROL_CONT_2               | -> restore port

| ----------------------------------------------------------
| DisposeControl -- _DisposeControl ($A955). Plus menu_mgr.s 1050.
| Pascal: procedure DisposeControl(theControl: ControlHandle);
| Removes a control from its window's control list, calls the
| CDEF disposeCntl message to clean up, then frees the control's
| Handle storage.
DisposeControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  8(SP),A3                        | A3 = ControlHandle
        BSR.B   NEWCONTROL_CONT_3               | erase and invalidate control region
        MOVE.L  A3,A0                           | A0 = ControlHandle (to unlink)
        MOVE.L  (A3),A1                         | dereference -> ControlRecord
        MOVE.L  4(A1),A1                        | A1 = contrlOwner (offset 4)
        LEA.L     wControlList(A1),A1           | A1 = addr of control list head
        BSR.W   DRAWCONTROLS_CONT_2             | unlink control from window's list
        MOVEQ.L #0x4,D0                         | D0 = disposeCntl message (4)
        BSR.B   NEWCONTROL_FOUND                | call CDEF to clean up
        MOVE.L  A3,A0                           | A0 = ControlHandle
        _DisposeHandle                          | free the ControlRecord
        BRA.B   SHOWCONTROL_EXIT                | -> restore A3 and return

| ----------------------------------------------------------
| KillControls -- _KillControls ($A956). Plus menu_mgr.s 1071.
| Pascal: procedure KillControls(theWindow: WindowPtr);
| Disposes all controls owned by a window. Loops calling
| DisposeControl on the head of wControlList until the list is
| empty (each DisposeControl removes its target from the list).
KillControls:
        MOVE.L  A3,-(SP)                        | save A3
        MOVEA.L  8(SP),A3                       | A3 = theWindow
KILLCONTROLS_EMPTY:
        MOVE.L  wControlList(A3),D0             | D0 = first control in list
        BEQ.B   SHOWCONTROL_EXIT                | list empty -> done
        MOVE.L  D0,-(SP)                        | push ControlHandle
        _DisposeControl                         | dispose it (also removes from list)
        BRA.B   KILLCONTROLS_EMPTY              | repeat until list empty

| ----------------------------------------------------------
| ShowControl -- _ShowControl ($A957). Plus menu_mgr.s 1096.
| Pascal: procedure ShowControl(theControl: ControlHandle);
| Sets the contrlVis byte to true ($FF) and draws the control if
| not already visible.
ShowControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  8(SP),A3                        | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        TST.B   16(A0)                          | already visible? (contrlVis offset 16)
        BNE.B   SHOWCONTROL_EXIT                | yes, nothing to do ->
        ST      16(A0)                          | mark as visible ($FF)
        MOVEQ.L #0x0,D1                         | D1 = 0 (draw whole control)
        BSR.W   NEWCONTROL_CONT_6               | draw control if visible and in port
SHOWCONTROL_EXIT:
        MOVE.L  (SP)+,A3                        | restore A3
        MOVE.L  (SP)+,(SP)                      | strip 4-byte param
        RTS                                     | return to caller

| ----------------------------------------------------------
| HideControl -- _HideControl ($A958). Plus menu_mgr.s 1116.
| Pascal: procedure HideControl(theControl: ControlHandle);
| Erases the control's region, invalidates it, and sets the
| contrlVis byte to false ($00) if not already hidden.
HideControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  8(SP),A3                        | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        TST.B   16(A0)                          | already hidden?
        BEQ.B   SHOWCONTROL_EXIT                | yes, nothing to do ->
        BSR.W   NEWCONTROL_CONT_3               | erase and invalidate control region
        MOVE.L  (A3),A0                         | re-dereference (may have moved)
        CLR.B   16(A0)                          | mark as invisible
        BRA.B   SHOWCONTROL_EXIT                | -> restore A3 and return

| ----------------------------------------------------------
| _MoveControl ($A959)
| Called during boot.
| _MoveControl: move control to new position (h,v)
| Pascal: procedure MoveControl(theControl: ControlHandle; h, v: INTEGER);
MoveControl:
        MOVEM.L D3/A3,-(SP)                     | save registers
        MOVE.L  0x10(SP),A3                     | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        MOVE.B  contrlVis(A0),D3                | D3 = save visibility state
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _HideControl                            | hide before moving
        MOVE.L  (A3),A0                         | re-dereference
        ADDQ.W  #0x8,A0                         | A0 = contrlRect (offset 8)
        MOVE    0xC(SP),D0                      | D0 = new v position
        SUB     (A0),D0                         | D0 = vertical delta (new - old top)
        MOVE    0xE(SP),D1                      | D1 = new h position
        SUB     menuWidth(A0),D1                | D1 = horizontal delta (new - old left)
        MOVE.L  A0,-(SP)                        | push contrlRect ptr
        MOVE    D1,-(SP)                        | push dh
        MOVE    D0,-(SP)                        | push dv
        _OffsetRect                             | move the rectangle
MOVECONTROL_OK:
        TST.B   D3                              | was control originally visible?
        BEQ.B   MOVECONTROL_SKIP                | no -> stay hidden
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _ShowControl                            | show at new position
MOVECONTROL_SKIP:
        MOVEM.L (SP)+,D3/A3                     | save registers
MOVECONTROL_CONT:
        MOVE.L  (SP)+,A0                        | A3 = ControlHandle
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetCRefCon -- _GetCRefCon ($A95A). Plus menu_mgr.s 1169.
| Pascal: function GetCRefCon(theControl: ControlHandle): LongInt;
| Returns the contrlRfCon field (offset 0x24) of a ControlRecord.
GetCRefCon:
        MOVEQ.L #0x24,D1                        | D1 = contrlRfCon offset (0x24)
MOVECONTROL_CONT_4:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,A1                        | pop ControlHandle
        MOVE.L  (A1),A1                         | dereference -> ControlRecord
        MOVE.L  0(A1,D1.W),(SP)                 | return field at offset D1
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| SetCRefCon -- _SetCRefCon ($A95B). Plus menu_mgr.s 1184.
| Pascal: procedure SetCRefCon(theControl: ControlHandle; data: LongInt);
| Stores a new value into the contrlRfCon field (offset 0x24).
SetCRefCon:
        MOVEQ.L #0x24,D1                        | D1 = contrlRfCon offset (0x24)
SETCREFCON_CONT:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,D0                        | pop new value
        MOVE.L  (SP)+,A1                        | pop ControlHandle
        MOVE.L  (A1),A1                         | dereference -> ControlRecord
        MOVE.L  D0,0x0(A1,D1.W)                 | store value at offset D1
        JMP     (A0)                            | return

| ----------------------------------------------------------
| GetCtlAction -- _GetCtlAction ($A95E). Plus menu_mgr.s 1199.
| Pascal: function GetCtlAction(theControl: ControlHandle): ProcPtr;
| Returns the contrlAction proc field (offset 0x20).
GetCtlAction:
        MOVEQ.L #0x20,D1                        | D1 = contrlAction offset (0x20)
        BRA.B   MOVECONTROL_CONT_4              | -> generic get-long-field

| ----------------------------------------------------------
| SetCtlAction -- _SetCtlAction ($A95F). Plus menu_mgr.s 1208.
| Pascal: procedure SetCtlAction(theControl: ControlHandle; actionProc: ProcPtr);
| Stores a new ProcPtr into the contrlAction field (offset 0x20).
SetCtlAction:
        MOVEQ.L #0x20,D1                        | D1 = contrlAction offset (0x20)
        BRA.B   SETCREFCON_CONT                 | -> generic set-long-field

| ----------------------------------------------------------
| SizeControl -- _SizeControl ($A95C). Plus menu_mgr.s 1219.
| Pascal: procedure SizeControl(theControl: ControlHandle; w, h: INTEGER);
| Resizes a control's contrlRect to (w, h). Hides the control,
| recomputes botRight = topLeft + (h, w), then re-shows if it
| was visible before the resize.
SizeControl:
        MOVEM.L D3/A3,-(SP)                     | save registers
        MOVE.L  16(SP),A3                       | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        MOVE.B  16(A0),D3                       | D3 = save visibility state
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _HideControl                            | hide before resizing
        MOVE    12(SP),D0                       | D0 = new height (h param)
        MOVE    14(SP),D1                       | D1 = new width (w param)
        MOVE.L  (A3),A0                         | re-dereference
        ADDQ.W  #0x8,A0                         | A0 = contrlRect
        ADD     (A0)+,D0                        | D0 = top + height = new bottom
        ADD     (A0)+,D1                        | D1 = left + width = new right
        MOVE    D0,(A0)+                        | store new bottom
        MOVE    D1,(A0)+                        | store new right
        BRA.B   MOVECONTROL_OK                  | -> re-show if was visible

| ----------------------------------------------------------
| HiliteControl -- _HiliteControl ($A95D). Plus menu_mgr.s 1243.
| Change hilite state of a control. Calls NEWCONTROL_CONT_6 to
| redraw if state changed. If new state is 0 (unhilite), passes the
| old state to the redraw helper so it knows which segment to clear.
HiliteControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  10(SP),A3                       | A3 = ControlHandle
        MOVE.L  (A3),A0                         | A0 = ControlRecord
        MOVEQ.L #0x0,D1                         | clear D1
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  9(SP),D1                        | D1 = new hilite state (byte from word param)
        MOVE.B  17(A0),D0                       | D0 = current hilite state
        CMP.B   D0,D1                           | same state?
        BEQ.B   HILITECONTROL_OK                | yes, no change needed ->
        MOVE.B  D1,17(A0)                       | store new hilite state
        BNE.B   HILITECONTROL_CONT              | new state nonzero -> draw with new state
        MOVE    D0,D1                           | was hilited, now 0: pass old state to unhilite
HILITECONTROL_CONT:
        BSR.W   NEWCONTROL_CONT_6               | CDEF redraws control with new hilite
HILITECONTROL_OK:
        MOVE.L  (SP)+,A3                        | restore A3
HILITECONTROL_CONT_2:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| Get C Title
| _GetCTitle: copy control's title to caller's string buffer
| Pascal: procedure GetCTitle(theControl: ControlHandle; title: Str255);
GetCTitle:
        MOVE.L  (SP)+,D0                        | D0 = return address
        MOVE.L  (SP)+,A1                        | A1 = destination string buffer
        MOVE.L  (SP)+,A0                        | A0 = ControlHandle
        MOVE.L  D0,-(SP)                        | push return address back
        MOVE.L  (A0),A0                         | A0 = ControlRecord
        LEA.L   contrlTitle(A0),A0              | A0 = title string in ControlRecord
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0),D0                         | D0 = title length
        ADDQ.L  #0x1,D0                         | +1 for length byte
        _BlockMove                              | copy Pascal string A0 -> A1, D0 bytes
        RTS                                     | return to caller

| ----------------------------------------------------------
| SetCTitle -- _SetCTitle ($A95D -- but commonly $A964 in 1984;
| Plus calls it $A96B). Plus menu_mgr.s 1289.
| Pascal: procedure SetCTitle(theControl: ControlHandle; title: Str255);
| Updates a control's title. Hides the control, resizes the
| handle to fit the new title (length + $29 = 41-byte header
| including ControlRecord prefix), copies the title into the
| contrlTitle field (offset $28), then re-shows if visible.
SetCTitle:
        MOVEM.L D3/A3-A4,-(SP)                  | save registers
        MOVE.L  20(SP),A3                       | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        MOVE.B  16(A0),D3                       | D3 = save contrlVis state
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _HideControl                            | hide before title change
        MOVE.L  16(SP),A4                       | A4 = new title string ptr
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A4),D0                         | D0 = new title length
        MOVE.L  D0,-(SP)                        | save title length
        ADDI    #0x29,D0                        | + 41 bytes (ControlRecord header)
        MOVE.L  A3,A0                           | A0 = ControlHandle
        _SetHandleSize                          | resize handle for new title
        MOVE.L  (SP)+,D0                        | restore title length
        MOVE.L  A4,A0                           | A0 = new title string (src)
        MOVE.L  (A3),A1                         | dereference ControlHandle
        LEA.L     0x28(A1),A1                   | A1 = contrlTitle field (offset $28)
        ADDQ.W  #0x1,D0                         | +1 for length byte
        _BlockMove                              | copy new title into ControlRecord
        TST.B   D3                              | was control visible?
        BEQ.B   GETCTITLE_SKIP                  | no -> skip show
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _ShowControl                            | re-show with new title
GETCTITLE_SKIP:
        MOVEM.L (SP)+,D3/A3-A4                  | restore registers
        BRA.W   MOVECONTROL_CONT                | -> strip 8 bytes of params

| ----------------------------------------------------------
| GetCtlValue -- _GetCtlValue ($A960). Plus menu_mgr.s 1322.
| Returns control's contrlValue field via generic get-word-field.
GetCtlValue:
        MOVEQ.L #0x12,D0                        | D0 = contrlValue offset
GETCTLVALUE_CONT:
        MOVE.L  (SP)+,A1                        | pop return address
        MOVE.L  (SP)+,A0                        | pop ControlHandle
        MOVE.L  (A0),A0                         | dereference -> ControlRecord
        MOVE    0(A0,D0.W),(SP)                 | return field value at offset D0
        JMP     (A1)                            | return

| ----------------------------------------------------------
| GetMinCtl -- _GetMinCtl ($A961). Plus menu_mgr.s 1336.
GetMinCtl:
        MOVEQ.L #0x14,D0                        | D0 = contrlMin offset
        BRA.B   GETCTLVALUE_CONT                | -> generic get-word-field

| ----------------------------------------------------------
| GetMaxCtl -- _GetMaxCtl ($A962). Plus menu_mgr.s 1344.
GetMaxCtl:
        MOVEQ.L #0x16,D0                        | D0 = contrlMax offset
        BRA.B   GETCTLVALUE_CONT                | -> generic get-word-field

| ----------------------------------------------------------
| SetCtlValue -- _SetCtlValue ($A963). Plus menu_mgr.s 1353.
| Set control's contrlValue field with clamping to [contrlMin..contrlMax].
SetCtlValue:
        MOVEQ.L #0x12,D0                        | D0 = contrlValue offset
| SETCTLVALUE_CONT: generic set-word-field with clamping and redraw
SETCTLVALUE_CONT:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  10(SP),A3                       | A3 = ControlHandle
        MOVE    8(SP),D1                        | D1 = new value
        MOVE.L  (A3),A0                         | A0 = ControlRecord
        CMP     0(A0,D0.W),D1                   | same as current value?
        BEQ.B   SETCTLVALUE_OK                  | yes, no change needed ->
        MOVE    D1,0(A0,D0.W)                   | store new value at field offset D0
        MOVE    18(A0),D1                       | D1 = contrlValue (may have changed min/max)
        CMP     20(A0),D1                       | value < contrlMin?
        BGE.B   SETCTLVALUE_NO                  | no ->
        MOVE    20(A0),D1                       | clamp to contrlMin
SETCTLVALUE_NO:
        CMP     22(A0),D1                       | value > contrlMax?
        BLE.B   SETCTLVALUE_NO_2                | no -> use as-is
        MOVE    22(A0),D1                       | yes -> clamp to contrlMax
SETCTLVALUE_NO_2:
        MOVE    D1,18(A0)                       | store clamped value in contrlValue
        MOVE    #0x81,D1                        | param = redraw indicator only
        BSR.W   NEWCONTROL_CONT_6               | CDEF redraws (msg=drawCntl)
SETCTLVALUE_OK:
        MOVE.L  (SP)+,A3                        | restore A3
        BRA.W   HILITECONTROL_CONT_2            | strip params and return

| ----------------------------------------------------------
| SetMinCtl -- _SetMinCtl ($A964). Plus menu_mgr.s 1385.
SetMinCtl:
        MOVEQ.L #0x14,D0                        | D0 = contrlMin offset
        BRA.B   SETCTLVALUE_CONT                | -> generic set-word-field

| ----------------------------------------------------------
| SetMaxCtl -- _SetMaxCtl ($A965). Plus menu_mgr.s 1394.
SetMaxCtl:
        MOVEQ.L #0x16,D0                        | D0 = contrlMax offset
        BRA.B   SETCTLVALUE_CONT                | -> generic set-word-field

| ----------------------------------------------------------
| TestControl -- _TestControl ($A966). Plus menu_mgr.s 1403.
| Test if a point hits a control. Returns part code or 0 if no hit
| (invisible, inactive, or CDEF returned 0).
TestControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  12(SP),A3                       | A3 = ControlHandle
        MOVE.L  (A3),A0                         | A0 = ControlRecord
        CLR     16(SP)                          | result = 0 (no hit)
        MOVE.B  16(A0),D1                       | D1 = contrlVis
        BEQ.B   TESTCONTROL_FOUND               | invisible -> no hit
        CMPI.B  #0xFF,17(A0)                    | contrlHilite = 255 (inactive)?
        BEQ.B   TESTCONTROL_FOUND               | yes -> no hit
        MOVE.L  8(SP),D1                        | D1 = test point (v,h packed)
        MOVEQ.L #0x1,D0                         | D0 = testCntl message (1)
        BSR.W   NEWCONTROL_FOUND                | call CDEF to hit-test
        MOVE    D0,16(SP)                       | store result (part code or 0)
TESTCONTROL_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        BRA.W   MOVECONTROL_CONT                | strip params and return

| ----------------------------------------------------------
| DragControl -- _DragControl ($A967). Plus menu_mgr.s 1424.
| Drag a control's frame, calling its CDEF for custom behavior.
DragControl:
        CLR     (DragFlag).w                    | not a thumb drag (whole control)

| DRAGCONTROL_CONT -- drag the thumb region.
DRAGCONTROL_CONT:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L D3-D4/A3-A4,-(SP)               | save registers
        MOVEM.L 14(A6),D3-D4/A3                 | D3=startPt, D4=limitRect, A3=ControlHandle
        BSR.W   DRAGCONTROL_CONT_2              | save port, set control's owner port
        MOVE    (DragFlag).w,D1                 | D1 = drag flag (0=drag, nonzero=thumb)
        MOVEQ.L #0x7,D0                         | D0 = dragCntl message (7)
        BSR.W   NEWCONTROL_FOUND                | call CDEF for custom drag behavior
        TST     D0                              | CDEF handled drag?
        BNE.B   DRAGCONTROL_EXIT                | yes -> return no movement
        JSR     PAINTBEHIND_EMPTY(PC)           | get mouse position -> stack
        TST     (DragFlag).w                    | thumb drag mode?
        SNE     (SP)                            | set high bit = thumb drag flag
        MOVE.L  (SP),D1                         | D1 = param for calcCRgns
        MOVEQ.L #0x2,D0                         | D0 = calcCRgns message (2)
        BSR.W   NEWCONTROL_FOUND                | get control's drag region
        CLR.B   (SP)                            | clear high byte (region handle)
        MOVE.L  (SP)+,A4                        | A4 = drag region handle
        MOVEM.L D3-D4/A4-A5,-(SP)               | push DragTheRgn params: startPt, limitRect
        MOVE.L  10(A6),-(SP)                    | push slopRect
        MOVE    8(A6),-(SP)                     | push axis constraint
        MOVE.L  (CurDragAction).w,-(SP)         | push drag action proc
        TST     (DragFlag).w                    | thumb drag?
        BNE.B   DRAGCONTROL_OK                  | yes -> keep action proc
        CLR.L   (SP)                            | no action proc for normal drag
DRAGCONTROL_OK:
        _DragTheRgn                             | track drag -> D3 = delta (dv:dh)
        MOVE.L  A4,-(SP)                        | push drag region
        _DisposeRgn                             | free drag region
        MOVE.L  (SP)+,D3                        | D3 = drag delta (or 0 if cancelled)
        BEQ.B   DRAGCONTROL_DONE                | no movement -> done
        CMPI    #-0x8000,D3                     | drag cancelled ($8000)?
        BNE.B   DRAGCONTROL_NO                  | no -> apply movement
DRAGCONTROL_EXIT:
        MOVEQ    #0x0,D3                        | return delta = 0 (cancelled)
        BRA.B    DRAGCONTROL_DONE               | restore port and return

| ----------------------------------------------------------
| DRAGCONTROL_NO: apply drag movement to control position
DRAGCONTROL_NO:
        TST     (DragFlag).w                    | thumb drag?
        BNE.B   DRAGCONTROL_DONE                | yes -> don't move control rect
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  0x8(A0),D0                      | D0 = contrlRect.topLeft (v:h)
        ADD     D3,D0                           | add horizontal delta to h
        SWAP    D0                              | swap to access v component
        SWAP    D3                              | get vertical delta
        ADD     D3,D0                           | add vertical delta to v
        SWAP    D0                              | restore v:h order
        MOVE.L  A3,-(SP)                        | push ControlHandle
        MOVE.L  D0,-(SP)                        | push new position (h, v)
        _MoveControl                            | move control to new position
DRAGCONTROL_DONE:
        _SetPort                                | restore saved port
        MOVE.L  D3,D1                           | D1 = delta for caller
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0x12,SP                        | strip 18 bytes of params
        JMP     (A0)                            | return
DRAGCONTROL_CONT_2:
        MOVE.L  (SP)+,D2                        | save return address in D2
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  SP,-(SP)                        | push ptr for GetPort
        _GetPort                                | save current port on stack
        MOVE.L  D2,-(SP)                        | push part code
        MOVE.L  (A3),A0                         | A0 = actionProc address
        MOVE.L  contrlOwner(A0),-(SP)           | push control's owner port
        _SetPort                                | call subroutine via A0
        RTS                                     | return to caller

| ----------------------------------------------------------
| TrackControl -- _TrackControl ($A968). Plus menu_mgr.s 1515.
| Track mouse during a control press, calling its CDEF for hit-testing
| and the action proc for repeated hits while held. Returns part code.
TrackControl:
        LINK    A6,#-0x1C                       | 28 bytes local (mouse pt, thumb data)
        MOVEM.L D3/A3,-(SP)                     | save registers
        MOVE.L  16(A6),A3                       | A3 = ControlHandle
        MOVE.L  12(A6),-8(A6)                   | copy startPt to local for GetMouse
        BSR.B   DRAGCONTROL_CONT_2              | save port, set control's owner port
        MOVEQ.L #0x0,D3                         | D3 = 0 (first pass, no previous part)

| TRACKCONTROL_LOOP: mouse tracking loop
TRACKCONTROL_LOOP:
        MOVE.L  A3,-(SP)                        | push ControlHandle for HiliteControl
        CLR     -(SP)                           | push partCode for TestControl result
        MOVE.L  A3,-(SP)                        | push ControlHandle for TestControl
        MOVE.L  -8(A6),-(SP)                    | push current mouse point
        _TestControl                            | hit-test mouse position -> part code
        TST     D3                              | first iteration?
        BNE.B   TRACKCONTROL_NO                 | no -> check if still in same part
        MOVE    (SP),D3                         | D3 = initial hit part code
        TST.B   D3                              | indicator part (negative)?
        BPL.B   TRACKCONTROL_NO_2               | no -> normal part tracking
        BRA.B   TRACKCONTROL_OK                 | yes -> thumb/indicator tracking
TRACKCONTROL_NO:
        CMP     (SP),D3                         | still in same part?
        BEQ.B   TRACKCONTROL_NO_2               | yes -> skip clear
        CLR     (SP)                            | no -> clear hilite state
TRACKCONTROL_NO_2:
        MOVE    (SP),20(A6)                     | store current part in result
        _HiliteControl                          | hilite/unhilite the part
        MOVE.L  8(A6),D0                        | D0 = actionProc param
        BEQ.B   TRACKCONTROL_EMPTY              | nil -> no action callback
        BTST    #0x0,D0                         | odd address = procPtr?
        BEQ.B   TRACKCONTROL_NO_3               | no, even = real procPtr ->
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  0x20(A0),D0                     | D0 = contrlAction
        BEQ.B   TRACKCONTROL_EMPTY              | nil -> no action
        BTST    #0x0,D0                         | odd = -1 flag (auto-track)?
        BEQ.B   TRACKCONTROL_NO_3               | no, real procPtr ->
        MOVEQ.L #0x8,D0                         | D0 = autoTrack message (8)
        MOVE    20(A6),D1                       | D1 = current part code
        BSR.W   NEWCONTROL_FOUND                | call CDEF for auto-tracking
        BRA.B   TRACKCONTROL_EMPTY              | -> get mouse

| ----------------------------------------------------------
| TRACKCONTROL_NO_3: call user's actionProc callback
TRACKCONTROL_NO_3:
        MOVE.L  A3,-(SP)                        | push ControlHandle
        MOVE    0x14(A6),-(SP)                  | push part code
        MOVE.L  D0,A0                           | A0 = actionProc address
        JSR     (A0)                            | call user's action procedure
TRACKCONTROL_EMPTY:
        PEA.L     -8(A6)                        | push addr for mouse point
        _GetMouse                               | get current mouse position
        CLR     -(SP)                           | push sleep = 0
        _WaitMouseUp                            | wait for mouse button release
        TST.B   (SP)+                           | button still down?
        BNE.B   TRACKCONTROL_LOOP               | yes -> continue tracking loop
        MOVE.L  A3,-(SP)                        | push ControlHandle
        CLR     -(SP)                           | push hiliteState = 0 (unhilite)
        _HiliteControl                          | remove hilite on release
TRACKCONTROL_EXIT:
        _SetPort                                | restore caller's GrafPort
        MOVEM.L (SP)+,D3/A3                     | restore D3 + A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDA.W  #0xC,SP                         | strip 12 bytes of Pascal params
        JMP     (A0)                            | RTS
TRACKCONTROL_OK:
        MOVE    (SP)+,20(A6)                    | partCode result -> caller's frame
        ADDQ.W  #0x4,SP                         | skip extra word slot
        LEA.L     -28(A6),A0                    | A0 = local DragRect/proc record
        MOVE.L  12(A6),(A0)                     | store ControlHandle in record
        MOVE.L  A0,D1                           | D1 = ptr to record
        MOVEQ.L #0x6,D0                         | CDEF msg 6 = thumbCntl
        BSR.W   NEWCONTROL_FOUND                | invoke contrlDefProc
        ST      (DragFlag).w                    | (DragFlag).w := -1 (true)
        MOVE.L  8(A6),D0                        | D0 = caller's actionProc
        BTST    #0x0,D0                         | low bit set (-1 sentinel)?
        BEQ.B   TRACKCONTROL_OK_2               | no -> use caller's actionProc
        MOVE.L  (A3),A0                         | A0 = ControlRecord ptr
        MOVE.L  contrlAction(A0),D0             | D0 = contrlAction (CDEF's default proc)
        BTST    #0x0,D0                         | -1 means "use CDEF default"? (bit 0 set)
        BEQ.B   TRACKCONTROL_OK_2               | regular proc pointer: use caller's
        MOVEQ.L #0x0,D0                         | -1 action: drop to CDEF default
TRACKCONTROL_OK_2:
        MOVE.L  D0,(CurDragAction).w            | stash actionProc for ticker callbacks
        MOVE.L  A3,-(SP)                        | push GrafPort for restore
        MOVE.L  12(A6),-(SP)                    | push ControlHandle param
        LEA.L     -28(A6),A0                    | A0 = local DragRect record
        MOVE.L  A0,-(SP)                        | push DragRect ptr
        PEA.L     8(A0)                         | push slop rect ptr
        MOVE    16(A0),-(SP)                    | push axis (constrain mode)
        BSR.W   DRAGCONTROL_CONT                | track thumb drag, return delta in D1
        TST.L   D1                              | any movement?
        BEQ.B   TRACKCONTROL_NO_4               | no -> result = 0
        MOVEQ.L #0x5,D0                         | CDEF msg 5 = posCntl (move thumb)
        BSR.W   NEWCONTROL_FOUND                | CDEF updates control to new value
        BRA.B   TRACKCONTROL_EXIT               | return with partCode in result
TRACKCONTROL_NO_4:
        CLR     0x14(A6)                        | result = 0 (no part)
        BRA.B   TRACKCONTROL_EXIT               | -> restore port and return

| ----------------------------------------------------------
|
| _UpdtControl ($A953)
|
| _UpdtControl ($A953): redraw all controls in a window's update region
| Pascal: procedure UpdtControl(theWindow: WindowPtr; updateRgn: RgnHandle);
| Walks the window's contrlList, calling Draw1Control for each visible
| control whose region intersects the update region.
UpdtControl:
        LINK    A6,#-0x18                       | 24 bytes local (pen state)
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(A6),A3                      | A3 = theWindow
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  SP,-(SP)                        | push ptr to local var
        _GetPort                                | save current port
        MOVE.L  A3,-(SP)                        | push window
        _SetPort                                | switch to window's port
        PEA.L   -0x18(A6)                       | save pen state in local
        MOVE.L  (SP),-(SP)                      | dup for SetPenState later
        _GetPenState                            | snapshot current pen
        _PenNormal                              | reset to default pen
        MOVE.L  wControlList(A3),D0             | D0 = first control in list
        BEQ.B   UPDTCONTROL_EXIT                | empty list -> restore pen, exit
UPDTCONTROL_BODY:
        MOVE.L  D0,A3                           | A3 = current ControlHandle
        MOVE.L  (A3),A0                         | A0 = ControlRecord pointer
        TST.B   16(A0)                          | contrlVis flag set?
        BEQ.B   UPDTCONTROL_LOOP                | invisible -> skip draw
        MOVEQ.L #0x0,D1                         | partCode 0 = entire control
        BSR.W   NEWCONTROL_CONT_6               | Draw1Control via CDEF
UPDTCONTROL_LOOP:
        MOVE.L  (A3),A0                         | A0 = ControlRecord pointer
        MOVE.L  (A0),D0                         | D0 = nextControl link
        BNE.B   UPDTCONTROL_BODY                | more controls -> draw next
UPDTCONTROL_EXIT:
        _SetPenState                            | restore caller's pen state
        _SetPort                                | restore caller's GrafPort
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | strip Pascal params
        RTS                                     | return to caller

| ----------------------------------------------------------
| DRAWCONTROLS_CONT_2
| Called during boot.
| DRAWCONTROLS_CONT_2: unlink handle A0 from linked list headed at (A1)
| Each node: handle -> [nextHandle, ...], list head at (A1)
| Returns D0=0 if found, D0=-1 if not found
DRAWCONTROLS_CONT_2:
        MOVEM.L D1/A2-A3,-(SP)                  | save D1, A2, A3
        MOVEQ.L #-0x1,D0                        | default result = -1 (not found)
        TST.L   (A1)                            | list head non-empty?
        BEQ.B   DRAWCONTROLS_FOUND              | empty -> not found
        MOVE.L  (A1),A2                         | push ControlHandle
        MOVE.L  A1,A3                           | push thePoint
        BRA.B   DRAWCONTROLS_CONT_3             | enter unlink scan loop
DRAWCONTROLS_NEXT:
        MOVE.L  (A2),A3                         | D0 = part code
        MOVE.L  (A3),A2                         | A2 = next handle in list
        MOVE.L  A2,D1                           | set Z if end of list
        BEQ.B   DRAWCONTROLS_FOUND              | end -> not found
DRAWCONTROLS_CONT_3:
        CMPA.L  A0,A2                           | current node == target?
        BNE.B   DRAWCONTROLS_NEXT               | no -> advance
        MOVE.L  (A2),A2                         | A0 = VAR whichControl ptr
        MOVE.L  (A2),(A3)                       | whichControl = this ControlHandle
        MOVEQ.L #0x0,D0                         | result = 0 (found and unlinked)
DRAWCONTROLS_FOUND:
        MOVEM.L (SP)+,D1/A2-A3                  | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _FindControl ($A96C)
|
| _FindControl ($A96C): find which control contains a point
| Pascal: function FindControl(thePoint: Point; theWindow: WindowPtr;
| VAR whichControl: ControlHandle): INTEGER;
FindControl:
        LINK    A6,#-0x4                        | 4 bytes local
        MOVEM.L D2-D3/A3,-(SP)                  | save registers
        LEA.L   0x8(A6),A0                      | A0 = start of params
        MOVE.L  (A0)+,A1                        | A1 = VAR whichControl ptr
        CLR.L   (A1)                            | whichControl = nil initially
        MOVE.L  (A0)+,A3                        | A3 = theWindow
        MOVE.L  (A0)+,D3                        | D3 = thePoint (v:h packed)
        CLR     (A0)                            | clear result (partCode = 0)
        MOVE.L  SP,-(SP)                        | save port on stack
        _GetPort                                | get current port
        MOVE.L  A3,-(SP)                        | push theWindow
        _SetPort                                | set port to window
        TST.B   wVisible(A3)                    | window visible?
        BEQ.W   TRACKCONTROL_EXIT               | no -> return 0
        CLR     -(SP)                           | space for PtInRect result
        MOVE.L  D3,-(SP)                        | push thePoint
        PEA.L   0x10(A3)                        | push window's portRect
        _PtInRect                               | point in window content?
        TST.B   (SP)+                           | result
        BEQ.W   TRACKCONTROL_EXIT               | no -> return 0
        MOVE.L  wControlList(A3),D0             | D0 = first control in list
        BEQ.W   TRACKCONTROL_EXIT               | no controls -> return 0
        MOVE.L  D0,A3                           | A3 = first ControlHandle
| FINDCONTROL_NEXT: walk control list testing each
FINDCONTROL_NEXT:
        MOVE.L  (A3),A0                         | A0 = ControlRecord pointer
        CMPI.B  #0xFF,17(A0)                    | contrlHilite == inactive?
        BEQ.B   FINDCONTROL_SKIP                | yes -> ignore inactive control
        CLR     -(SP)                           | space for partCode result
        MOVE.L  A3,-(SP)                        | push ControlHandle
        MOVE.L  D3,-(SP)                        | push thePoint
        _TestControl                            | ask CDEF: which part hit?
        MOVE    (SP)+,D0                        | D0 = partCode (0=miss)
        BNE.B   FINDCONTROL_FOUND               | hit -> record control
FINDCONTROL_SKIP:
        MOVE.L  (A3),A0                         | A0 = ControlRecord pointer
        MOVE.L  (A0),A3                         | A3 = nextControl handle
        MOVE.L  A3,D0                           | end of list?
        BNE.B   FINDCONTROL_NEXT                | no -> test next control
        BRA.W   TRACKCONTROL_EXIT               | end of list -> exit
FINDCONTROL_FOUND:
        MOVE.L  8(A6),A0                        | A0 = VAR whichControl ptr
        MOVE.L  A3,(A0)                         | return found ControlHandle
        MOVE    D0,20(A6)                       | return partCode result
        BRA.B   FINDCONTROL_SKIP                | fall through to exit path

RESOURCE_MAP:                                   | 32-byte param blob + BSR to helper
        .short  0x0000, 0x0100                  | $D724-$D727
        .short  0x0000, 0x0100                  | $D728-$D72B
        .short  0x0000, 0x0000                  | $D72C-$D72F
        .short  0x0000, 0x001E                  | $D730-$D733
        .short  0x0000, 0x0000                  | $D734-$D737
        .short  0x0000, 0x0000                  | $D738-$D73B
        .short  0x001C, 0x001E                  | $D73C-$D73F
        .short  0xFFFF, 0x0000                  | $D740-$D743
