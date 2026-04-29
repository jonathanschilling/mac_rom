| Control Manager Public Traps
|
| Public Control Manager entry points. The internal Control Manager
| state-machine logic, comparison helpers, and resource-index tails
| live in control_mgr.s; this file holds the trap entries that
| applications call directly.
|
| Routine groups, in physical ROM order:
|   NewControl, GetCtlAction, SetCtlAction       (creation / action)
|   GetCtlValue, SetCtlValue, GetCtlMin/Max,
|   SetCtlMin/Max                                (value accessors)
|   TestControl, FindControl, MoveControl,
|   SizeControl, DragControl, TrackControl       (mouse interaction)
|   DrawControls, Draw1Control, ShowControl,
|   HideControl, HiliteControl, UpdtControl      (drawing)
|   GetCRefCon, SetCRefCon, GetCTitle, SetCTitle,
|   KillControls, DisposeControl                 (housekeeping)
|
| Files cannot be reordered (ROM byte order is fixed).

| ----------------------------------------------------------
|
| _NewControl ($A954)
|
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
| load CDEF resource for this control type
NEWCONTROL_RETRY:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x43444546,-(SP)               | push 'CDEF'
        MOVE    D0,-(SP)                        | push CDEF ID
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM resources
        _GetResource                            | load CDEF
        MOVEQ.L #0x0,D0                         | clear D0 for retry check
        MOVE.L  (A3),A0                         | dereference ControlHandle
        LEA.L   contrlDefHandle(A0),A0          | A0 = contrlDefHandle field
        MOVE.L  (SP)+,(A0)                      | store CDEF handle
        BEQ.B   NEWCONTROL_RETRY                | nil = not found, retry (shouldn't loop forever)
        MOVE    (A4),D0                         | D0 = procID param again
        ANDI    #0xF,D0                         | D0 = variation code (procID mod 16)
        MOVE.B  D0,(A0)                         | store variation in low byte of handle ptr
        ADDQ.W  #0x4,A0                         | advance to contrlData field
        CLR.L   (A0)+                           | contrlData = nil
        CLR.L   (A0)+                           | contrlAction = nil
        MOVE.L  -(A4),(A0)+                     | contrlRFcon = refCon param
        MOVEQ.L #0x3,D0                         | CDEF message 3 = initCntl
        BSR.B   NEWCONTROL_FOUND                | call CDEF with initCntl message
        TST.B   0x14(A6)                        | visible param was true?
        BEQ.B   NEWCONTROL_SKIP                 | no -> skip initial draw
        MOVEQ.L #0x0,D1                         | D1 = 0 (draw whole control)
        BSR.B   NEWCONTROL_CONT                 | draw control if visible and in port
NEWCONTROL_SKIP:
        MOVEM.L (SP)+,A2-A4                     | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0x1A,SP                        | strip 26 bytes of params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| NEWCONTROL_CONT
|
| Called during boot.
| NEWCONTROL_CONT: draw control if visible and intersects owner window's portRect
| A3 = ControlHandle, D0 = CDEF message, D1 = param
NEWCONTROL_CONT:
        MOVEQ.L #0x0,D0                         | D0 = 0 (drawCntl message)
        MOVE.L  (A3),A0                         | dereference ControlHandle
        TST.B   contrlVis(A0)                   | control visible?
        BEQ.B   NEWCONTROL_SKIP_2               | no -> skip
        MOVEM.L D0-D1,-(SP)                     | save message and param
        SUBA.L  #0xA,SP                         | 10 bytes for temp Rect + Boolean
        PEA.L   contrlRect(A0)                  | push contrlRect
        MOVE.L  contrlOwner(A0),A1              | A1 = owner window
        PEA.L   PORTRECT(A1)                    | push window's portRect
        PEA.L   0xA(SP)                         | push result rect ptr
        _SectRect                               | intersect control with port
        TST.B   (SP)+                           | result non-empty?
        ADDA.L  #0x8,SP                         | discard temp rect
        MOVEM.L (SP)+,D0-D1                     | restore message and param
        BEQ.B   NEWCONTROL_SKIP_2               | no intersection -> skip
| NEWCONTROL_FOUND: call CDEF proc for control A3
| D0 = message (0=draw, 1=test, 2=calc, 3=init, 4=dispose, 5=pos,
| 6=thumb, 7=drag, 8=autoTrack), D1 = param, A3 = ControlHandle
| Called by: DRAGCONTROL_CONT, NEWCONTROL_RETRY, NEWCONTROL_CONT_3, DisposeControl, TestControl (and 3 more)
NEWCONTROL_FOUND:
        BSR     DRAGCONTROL_CONT_2              | save port, set control's owner port
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
        BNE.B   NEWCONTROL_OK                   | yes ->
        MOVE.L  A0,-(SP)                        | push CDEF handle for LoadResource
        CLR.B   (SP)                            | clear variation code byte in handle
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM resources
        _LoadResource                           | load the CDEF code
NEWCONTROL_OK:
        BSet    #0x7,(A0)                       | set lock bit on CDEF handle
        MOVE.L  (A0),A0                         | dereference CDEF -> code ptr
        JSR     (A0)                            | call CDEF proc
        MOVE.L  (SP)+,D0                        | pop CDEF result
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  contrlDefHandle(A0),A0          | A0 = CDEF handle
        BCLR    #0x7,(A0)                       | clear lock bit
NEWCONTROL_CONT_2:
        _SetPort                                | restore saved port (from DRAGCONTROL_CONT_2)
NEWCONTROL_SKIP_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| NEWCONTROL_CONT_3
|
| Called during boot.
| NEWCONTROL_CONT_3: erase and invalidate control's region (used when hiding/disposing)
| Sends calcCRgns (2) to CDEF to get control's region, then erases and invalidates it
NEWCONTROL_CONT_3:
        BSR     DRAGCONTROL_CONT_2              | save port, set owner port
        MOVEM.L A1-A4,-(SP)                     | save registers
        _NewRgn                                 | create temp region -> (SP)
        MOVE.L  (SP),A4                         | A4 = temp region handle
        MOVEQ.L #0x2,D0                         | D0 = calcCRgns message
        MOVE.L  A4,D1                           | D1 = region handle (param)
        BCLR    #0x1F,D1                        | clear high bit (whole region, not thumb)
        BSR.B   NEWCONTROL_FOUND                | call CDEF to calculate region
        _EraseRgn                               | erase the control's region
        MOVE.L  A4,-(SP)                        | push region for InvalRgn
        _InvalRgn                               | mark region for update
        MOVE.L  A4,-(SP)                        | push region for dispose
        _DisposeRgn                             | free temp region
        MOVEM.L (SP)+,A2-A4                     | restore registers
        BRA.B   NEWCONTROL_CONT_2               | -> restore port

| ----------------------------------------------------------
|
| _DisposeControl ($A955)
|
| Called during boot.
DisposeControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 = ControlHandle from stack param
        BSR.B   NEWCONTROL_CONT_3               | erase and invalidate control region
        MOVE.L  A3,A0                           | A0 = ControlHandle (to unlink)
        MOVE.L  (A3),A1                         | dereference -> ControlRecord
        MOVE.L  contrlOwner(A1),A1              | A1 = owner window
        LEA.L   wControlList(A1),A1             | A1 = addr of control list head
        BSR     DRAWCONTROLS_CONT_2             | unlink control from window's list
        MOVEQ.L #0x4,D0                         | D0 = disposeCntl message (4)
        BSR     NEWCONTROL_FOUND                | call CDEF to clean up
        MOVE.L  A3,A0                           | A0 = ControlHandle
        _DisposeHandle                          | free the ControlRecord
        BRA.B   SHOWCONTROL_EXIT                | -> restore A3 and return

| ----------------------------------------------------------
|
| _KillControls ($A956)
|
| Called during boot.
| _KillControls: dispose all controls in a window
KillControls:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 = theWindow
KILLCONTROLS_EMPTY:
        MOVE.L  wControlList(A3),D0             | D0 = first control in list
        BEQ.B   SHOWCONTROL_EXIT                | list empty -> done
        MOVE.L  D0,-(SP)                        | push ControlHandle
        _DisposeControl                         | dispose it (also removes from list)
        BRA.B   KILLCONTROLS_EMPTY              | repeat until list empty

| ----------------------------------------------------------
|
| _Draw1Control ($A96D)
|
Draw1Control:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference (for visibility check path)
        BRA.B   SHOWCONTROL_CONT                | -> draw the control

| ----------------------------------------------------------
|
| _ShowControl ($A957)
|
| Called during boot.
ShowControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        TST.B   contrlVis(A0)                   | already visible?
        BNE.B   SHOWCONTROL_EXIT                | yes, nothing to do ->
        ST.B    contrlVis(A0)                   | mark as visible ($FF)
SHOWCONTROL_CONT:
        MOVEQ.L #0x0,D1                         | D1 = 0 (draw whole control)
        BSR     NEWCONTROL_CONT                 | draw control if visible and in port
SHOWCONTROL_EXIT:
        MOVE.L  (SP)+,A3                        | restore A3
        MOVE.L  (SP)+,(SP)                      | strip 4-byte param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _HideControl ($A958)
|
| Called during boot.
HideControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        TST.B   contrlVis(A0)                   | already hidden?
        BEQ.B   SHOWCONTROL_EXIT                | yes, nothing to do ->
        BSR     NEWCONTROL_CONT_3               | erase and invalidate control region
        MOVE.L  (A3),A0                         | re-dereference (may have moved)
        CLR.B   contrlVis(A0)                   | mark as invisible
        BRA.B   SHOWCONTROL_EXIT                | -> restore A3 and return

| ----------------------------------------------------------
|
| _MoveControl ($A959)
|
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
        ADDQ.W  #0x8,A0                         | A0 = contrlRect
        MOVE    0xC(SP),D0                      | D0 = new v position
        SUB     (A0),D0                         | D0 = vertical delta (new - old top)
        MOVE    0xE(SP),D1                      | D1 = new h position
        SUB     menuWidth(A0),D1                | D1 = horizontal delta (new - old left)
        MOVE.L  A0,-(SP)                        | push contrlRect ptr
        MOVE    D1,-(SP)                        | push dh
        MOVE    D0,-(SP)                        | push dv
        _OffsetRect                             | move the rectangle
MOVECONTROL_OK:
        TST.B   D3                              | was control visible before?
        BEQ.B   MOVECONTROL_SKIP                | no -> skip show
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _ShowControl                            | show control at new position
MOVECONTROL_SKIP:
        MOVEM.L (SP)+,D3/A3                     | restore registers
MOVECONTROL_CONT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| Get C Ref Con
|
| _GetCRefCon: get control's refCon
| Pascal: function GetCRefCon(theControl: ControlHandle): LongInt;
GetCRefCon:
        MOVEQ.L #0x24,D1                        | D1 = contrlRFcon offset ($24)
GETCREFCON_CONT:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,A1                        | pop ControlHandle
        MOVE.L  (A1),A1                         | dereference -> ControlRecord
        MOVE.L  0x0(A1,D1.W),(SP)               | return value = field at offset D1
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| Set C Ref Con
|
| _SetCRefCon: set control's refCon
| Pascal: procedure SetCRefCon(theControl: ControlHandle; data: LongInt);
SetCRefCon:
        MOVEQ.L #0x24,D1                        | D1 = contrlRFcon offset ($24)
SETCREFCON_CONT:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,D0                        | pop new value
        MOVE.L  (SP)+,A1                        | pop ControlHandle
        MOVE.L  (A1),A1                         | dereference -> ControlRecord
        MOVE.L  D0,0x0(A1,D1.W)                 | store value at offset D1
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| Get Ctl Action
|
| _GetCtlAction: get control's actionProc
GetCtlAction:
        MOVEQ.L #0x20,D1                        | D1 = contrlAction offset ($20)
        BRA.B   GETCREFCON_CONT                 | -> generic get-long-field

| ----------------------------------------------------------
|
| Set Ctl Action
|
| _SetCtlAction: set control's actionProc
SetCtlAction:
        MOVEQ.L #0x20,D1                        | D1 = contrlAction offset ($20)
        BRA.B   SETCREFCON_CONT                 | -> generic set-long-field

| ----------------------------------------------------------
|
| _SizeControl ($A95C)
|
| Called during boot.
| _SizeControl: resize control to new width and height
| Pascal: procedure SizeControl(theControl: ControlHandle; w, h: INTEGER);
SizeControl:
        MOVEM.L D3/A3,-(SP)                     | save registers
        MOVE.L  0x10(SP),A3                     | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        MOVE.B  contrlVis(A0),D3                | D3 = save visibility state
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _HideControl                            | hide before resizing
        MOVE    0xC(SP),D0                      | D0 = new height (h param)
        MOVE    0xE(SP),D1                      | D1 = new width (w param)
        MOVE.L  (A3),A0                         | re-dereference
        ADDQ.W  #0x8,A0                         | A0 = contrlRect
        ADD     (A0)+,D0                        | D0 = top + height = new bottom
        ADD     (A0)+,D1                        | D1 = left + width = new right
        MOVE    D0,(A0)+                        | store new bottom
        MOVE    D1,(A0)+                        | store new right
        BRA.B   MOVECONTROL_OK                  | -> re-show if was visible

| ----------------------------------------------------------
|
| _HiliteControl ($A95D)
|
| Called during boot.
| _HiliteControl: change hilite state of a control
| Pascal: procedure HiliteControl(theControl: ControlHandle; hiliteState: INTEGER);
HiliteControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0xA(SP),A3                      | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        MOVEQ.L #0x0,D1                         | clear D1
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  0x9(SP),D1                      | D1 = new hilite state (byte from word param)
        MOVE.B  contrlHilite(A0),D0             | D0 = current hilite state
        CMP.B   D0,D1                           | same state?
        BEQ.B   HILITECONTROL_OK                | yes, no change needed ->
        MOVE.B  D1,contrlHilite(A0)             | store new hilite state
        BNE.B   HILITECONTROL_CONT              | new state nonzero -> draw with new state
        MOVE    D0,D1                           | was hilited, now 0: pass old state to unhilite
HILITECONTROL_CONT:
        BSR     NEWCONTROL_CONT                 | redraw control with hilite change
HILITECONTROL_OK:
        MOVE.L  (SP)+,A3                        | restore A3
HILITECONTROL_CONT_2:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| Get C Title
|
| _GetCTitle: copy control's title to caller's string buffer
| Pascal: procedure GetCTitle(theControl: ControlHandle; title: Str255);
GetCTitle:
        MOVE.L  (SP)+,D0                        | D0 = return address
        MOVE.L  (SP)+,A1                        | A1 = destination string buffer
        MOVE.L  (SP)+,A0                        | A0 = ControlHandle
        MOVE.L  D0,-(SP)                        | push return address back
        MOVE.L  (A0),A0                         | dereference -> ControlRecord
        LEA.L   contrlTitle(A0),A0              | A0 = title string in ControlRecord
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0),D0                         | D0 = title length
        ADDQ.L  #0x1,D0                         | +1 for length byte
        _BlockMove                              | copy Pascal string A0 -> A1, D0 bytes
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Set C Title
|
| Called during boot.
SetCTitle:
        MOVEM.L D3/A3-A4,-(SP)                  | save registers
        MOVE.L  0x14(SP),A3                     | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        MOVE.B  0x10(A0),D3                     | D3 = save contrlVis state
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _HideControl                            | hide before title change
        MOVE.L  0x10(SP),A4                     | A4 = new title string ptr
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A4),D0                         | D0 = new title length
        MOVE.L  D0,-(SP)                        | save title length
        ADDI    #0x29,D0                        | + 41 bytes (ControlRecord header)
        MOVE.L  A3,A0                           | A0 = ControlHandle
        _SetHandleSize                          | resize handle for new title
        MOVE.L  (SP)+,D0                        | restore title length
        MOVE.L  A4,A0                           | A0 = new title string (src)
        MOVE.L  (A3),A1                         | dereference ControlHandle
        LEA.L   0x28(A1),A1                     | A1 = contrlTitle field (offset $28)
        ADDQ.W  #0x1,D0                         | +1 for length byte
        _BlockMove                              | copy new title into ControlRecord
        TST.B   D3                              | was control visible?
        BEQ.B   SETCTITLE_SKIP                  | no -> skip show
        MOVE.L  A3,-(SP)                        | push ControlHandle
        _ShowControl                            | re-show with new title
SETCTITLE_SKIP:
        MOVEM.L (SP)+,D3/A3-A4                  | restore registers
        BRA     MOVECONTROL_CONT                | -> strip 8 bytes of params

| ----------------------------------------------------------
|
| Get Ctl Value
|
| Called during boot.
GetCtlValue:
        MOVEQ.L #0x12,D0                        | D0 = contrlValue offset ($12)
| GETCTLVALUE_CONT: generic get-word-field from ControlRecord
GETCTLVALUE_CONT:
        MOVE.L  (SP)+,A1                        | pop return address
        MOVE.L  (SP)+,A0                        | pop ControlHandle
        MOVE.L  (A0),A0                         | dereference -> ControlRecord
        MOVE    0x0(A0,D0.W),(SP)               | return field value at offset D0
        JMP     (A1)                            | return

| ----------------------------------------------------------
|
| Get Min Ctl
|
GetMinCtl:
        MOVEQ.L #0x14,D0                        | D0 = contrlMin offset ($14)
        BRA.B   GETCTLVALUE_CONT                | -> generic get-word-field

| ----------------------------------------------------------
|
| Get Max Ctl
|
GetMaxCtl:
        MOVEQ.L #0x16,D0                        | D0 = contrlMax offset ($16)
        BRA.B   GETCTLVALUE_CONT                | -> generic get-word-field

| ----------------------------------------------------------
|
| Set Ctl Value
|
| Called during boot.
SetCtlValue:
        MOVEQ.L #0x12,D0                        | D0 = contrlValue offset ($12)
| SETCTLVALUE_CONT: generic set-word-field with clamping and redraw
SETCTLVALUE_CONT:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0xA(SP),A3                      | A3 = ControlHandle
        MOVE    0x8(SP),D1                      | D1 = new value
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        CMP     0x0(A0,D0.W),D1                 | same as current value?
        BEQ.B   SETCTLVALUE_OK                  | yes, no change needed ->
        MOVE    D1,0x0(A0,D0.W)                 | store new value at field offset D0
        MOVE    0x12(A0),D1                     | D1 = contrlValue (may have changed min/max)
        CMP     0x14(A0),D1                     | value < contrlMin?
        BGE.B   SETCTLVALUE_NO                  | no ->
        MOVE    0x14(A0),D1                     | clamp to contrlMin
SETCTLVALUE_NO:
        CMP     0x16(A0),D1                     | value > contrlMax?
        BLE.B   SETCTLVALUE_NO_2                | no ->
        MOVE    0x16(A0),D1                     | clamp to contrlMax
SETCTLVALUE_NO_2:
        MOVE    D1,0x12(A0)                     | store clamped contrlValue
        MOVE    #0x81,D1                        | D1 = $81 (draw indicator part)
        BSR     NEWCONTROL_CONT                 | redraw control with new value
SETCTLVALUE_OK:
        MOVE.L  (SP)+,A3                        | restore A3
        BRA     HILITECONTROL_CONT_2            | -> strip 6 bytes of params

| ----------------------------------------------------------
|
| Set Min Ctl
|
| Called during boot.
SetMinCtl:
        MOVEQ.L #0x14,D0                        | D0 = contrlMin offset ($14)
        BRA.B   SETCTLVALUE_CONT                | -> generic set-word-field

| ----------------------------------------------------------
|
| Set Max Ctl
|
| Called during boot.
SetMaxCtl:
        MOVEQ.L #0x16,D0                        | D0 = contrlMax offset ($16)
        BRA.B   SETCTLVALUE_CONT                | -> generic set-word-field

| ----------------------------------------------------------
|
| _TestControl ($A966)
|
| Called during boot.
TestControl:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0xC(SP),A3                      | A3 = ControlHandle
        MOVE.L  (A3),A0                         | dereference -> ControlRecord
        CLR     0x10(SP)                        | result = 0 (no hit)
        MOVE.B  0x10(A0),D1                     | D1 = contrlVis
        BEQ.B   TESTCONTROL_FOUND               | invisible -> no hit
        CMPI.B  #0xFF,0x11(A0)                  | contrlHilite = 255 (inactive)?
        BEQ.B   TESTCONTROL_FOUND               | yes -> no hit
        MOVE.L  0x8(SP),D1                      | D1 = test point (v,h packed)
        MOVEQ.L #0x1,D0                         | D0 = testCntl message (1)
        BSR     NEWCONTROL_FOUND                | call CDEF to hit-test
        MOVE    D0,0x10(SP)                     | store result (part code or 0)
TESTCONTROL_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        BRA     MOVECONTROL_CONT                | -> strip 8 bytes of params

| ----------------------------------------------------------
|
| _DragControl ($A967)
|
DragControl:
        CLR     (DragFlag).w                    | not a thumb drag (whole control)
| DRAGCONTROL_CONT -- drag the thumb region.
DRAGCONTROL_CONT:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L D3-D4/A3-A4,-(SP)               | save registers
        MOVEM.L 0xE(A6),D3-D4/A3                | D3=startPt, D4=limitRect, A3=ControlHandle
        BSR     DRAGCONTROL_CONT_2              | save port, set control's owner port
        MOVE    (DragFlag).w,D1                 | D1 = drag flag (0=drag, nonzero=thumb)
        MOVEQ.L #0x7,D0                         | D0 = dragCntl message (7)
        BSR     NEWCONTROL_FOUND                | call CDEF for custom drag behavior
        TST     D0                              | CDEF handled drag?
        BNE.B   DRAGCONTROL_EXIT                | yes -> return no movement
        JSR     PAINTBEHIND_EMPTY(PC)           | get mouse position -> stack
        TST     (DragFlag).w                    | thumb drag mode?
        SNE.B   (SP)                            | set high byte if thumb drag
        MOVE.L  (SP),D1                         | D1 = param for calcCRgns
        MOVEQ.L #0x2,D0                         | D0 = calcCRgns message (2)
        BSR     NEWCONTROL_FOUND                | get control's drag region
        CLR.B   (SP)                            | clear high byte (region handle)
        MOVE.L  (SP)+,A4                        | A4 = drag region handle
        MOVEM.L D3-D4/A4-A5,-(SP)               | push DragTheRgn params: startPt, limitRect
        MOVE.L  0xA(A6),-(SP)                   | push slopRect
        MOVE    0x8(A6),-(SP)                   | push axis constraint
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
        MOVEQ.L #0x0,D3                         | return zero delta (no movement)
        BRA.B   DRAGCONTROL_DONE                | -> clean up

| ----------------------------------------------------------
|
| DRAGCONTROL_NO: apply drag movement to control position
|
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

| ----------------------------------------------------------
|
| DRAGCONTROL_CONT_2
|
| Called during boot.
| DRAGCONTROL_CONT_2: save current port, then set port to control's owner window
| Leaves saved port on stack for later _SetPort restore
DRAGCONTROL_CONT_2:
        MOVE.L  (SP)+,D2                        | pop return address
        SUBQ.W  #0x4,SP                         | make room for saved port
        MOVE.L  D2,-(SP)                        | push return address back
        MOVEM.L D0-D1,-(SP)                     | preserve D0-D1 across calls
        PEA.L   0xC(SP)                         | push addr of saved port slot
        _GetPort                                | save current port
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  menuHeight(A0),-(SP)            | push contrlOwner (WindowPtr at offset 4)
        _SetPort                                | set port to control's owner window
        MOVEM.L (SP)+,D0-D1                     | restore D0-D1
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _TrackControl ($A968)
|
| Called during boot.
TrackControl:
        LINK    A6,#-0x1C                       | 28 bytes local (mouse pt, thumb data)
        MOVEM.L D3/A3,-(SP)                     | save registers
        MOVE.L  0x10(A6),A3                     | A3 = ControlHandle
        MOVE.L  0xC(A6),-0x8(A6)                | copy startPt to local for GetMouse
        BSR.B   DRAGCONTROL_CONT_2              | save port, set control's owner port
        MOVEQ.L #0x0,D3                         | D3 = 0 (first pass, no previous part)
| TRACKCONTROL_LOOP: mouse tracking loop
TRACKCONTROL_LOOP:
        MOVE.L  A3,-(SP)                        | push ControlHandle for HiliteControl
        CLR     -(SP)                           | push partCode for TestControl result
        MOVE.L  A3,-(SP)                        | push ControlHandle for TestControl
        MOVE.L  -0x8(A6),-(SP)                  | push current mouse point
        _TestControl                            | hit-test mouse position -> part code
        TST     D3                              | first iteration?
        BNE.B   TRACKCONTROL_NO                 | no -> check if still in same part
        MOVE    (SP),D3                         | D3 = initial hit part code
        TST.B   D3                              | indicator part (negative)?
        BPL.B   TRACKCONTROL_NO_2               | no -> normal part tracking
        BRA.B   TRACKCONTROL_OK                 | yes -> thumb/indicator tracking

| ----------------------------------------------------------
|
| TRACKCONTROL_NO: subsequent iterations - check if mouse still in same part
|
| Called during boot.
TRACKCONTROL_NO:
        CMP     (SP),D3                         | still in same part?
        BEQ.B   TRACKCONTROL_NO_2               | yes -> keep hilited
        CLR     (SP)                            | moved out of part -> unhilite (0)
TRACKCONTROL_NO_2:
        MOVE    (SP),0x14(A6)                   | store current part in result
        _HiliteControl                          | hilite/unhilite the part
        MOVE.L  0x8(A6),D0                      | D0 = actionProc param
        BEQ.B   TRACKCONTROL_EMPTY              | nil -> no action callback
        BTST    #0x0,D0                         | odd address = procPtr?
        BEQ.B   TRACKCONTROL_NO_3               | no, even = real procPtr ->
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  0x20(A0),D0                     | D0 = contrlAction
        BEQ.B   TRACKCONTROL_EMPTY              | nil -> no action
        BTST    #0x0,D0                         | odd = -1 flag (auto-track)?
        BEQ.B   TRACKCONTROL_NO_3               | no, real procPtr ->
        MOVEQ.L #0x8,D0                         | D0 = autoTrack message (8)
        MOVE    0x14(A6),D1                     | D1 = current part code
        BSR     NEWCONTROL_FOUND                | call CDEF for auto-tracking
        BRA.B   TRACKCONTROL_EMPTY              | -> get mouse

| ----------------------------------------------------------
|
| TRACKCONTROL_NO_3: call user's actionProc callback
|
TRACKCONTROL_NO_3:
        MOVE.L  A3,-(SP)                        | push ControlHandle
        MOVE    0x14(A6),-(SP)                  | push part code
        MOVE.L  D0,A0                           | A0 = actionProc address
        JSR     (A0)                            | call user's action procedure
TRACKCONTROL_EMPTY:
        PEA.L   -0x8(A6)                        | push addr for mouse point
        _GetMouse                               | get current mouse position
        CLR     -(SP)                           | push sleep = 0
        _WaitMouseUp                            | wait for mouse button release
        TST.B   (SP)+                           | button still down?
        BNE.B   TRACKCONTROL_LOOP               | yes -> continue tracking loop
        MOVE.L  A3,-(SP)                        | push ControlHandle
        CLR     -(SP)                           | push hiliteState = 0 (unhilite)
        _HiliteControl                          | remove hilite on release
TRACKCONTROL_EXIT:
        _SetPort                                | restore saved port
        MOVEM.L (SP)+,D3/A3                     | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| TRACKCONTROL_OK
|
| TRACKCONTROL_OK: indicator/thumb tracking -- drag the thumb
TRACKCONTROL_OK:
        MOVE    (SP)+,0x14(A6)                  | store initial part code in result
        ADDQ.W  #0x4,SP                         | discard HiliteControl's ControlHandle
        LEA.L   -0x1C(A6),A0                    | A0 = local thumb data area
        MOVE.L  0xC(A6),(A0)                    | copy startPt into thumb data
        MOVE.L  A0,D1                           | D1 = ptr to thumb data
        MOVEQ.L #0x6,D0                         | D0 = thumbCntl message (6)
        BSR     NEWCONTROL_FOUND                | call CDEF to get thumb params
        ST.B    (DragFlag).w                    | set flag: this is a thumb drag
        MOVE.L  0x8(A6),D0                      | D0 = actionProc param
        BTST    #0x0,D0                         | odd = -1 flag?
        BEQ.B   TRACKCONTROL_OK_2               | no, use as-is ->
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  0x20(A0),D0                     | D0 = contrlAction
        BTST    #0x0,D0                         | odd = -1 flag (auto-track)?
        BEQ.B   TRACKCONTROL_OK_2               | no, real procPtr ->
        MOVEQ.L #0x0,D0                         | nil action for auto-track thumb
TRACKCONTROL_OK_2:
        MOVE.L  D0,(CurDragAction).w            | set drag action proc
        MOVE.L  A3,-(SP)                        | push ControlHandle for DRAGCONTROL_CONT
        MOVE.L  0xC(A6),-(SP)                   | push startPt
        LEA.L   -0x1C(A6),A0                    | A0 = thumb data (limitRect, etc.)
        MOVE.L  A0,-(SP)                        | push limitRect ptr
        PEA.L   0x8(A0)                         | push slopRect ptr
        MOVE    0x10(A0),-(SP)                  | push axis constraint
        BSR     DRAGCONTROL_CONT                | drag the thumb region
        TST.L   D1                              | thumb moved?
        BEQ.B   TRACKCONTROL_NO_4               | no -> result = 0
        MOVEQ.L #0x5,D0                         | D0 = posCntl message (5)
        BSR     NEWCONTROL_FOUND                | tell CDEF final thumb position
        BRA.B   TRACKCONTROL_EXIT               | -> restore port and return

| ----------------------------------------------------------
|
| TRACKCONTROL_NO_4: thumb drag cancelled -- return part code 0
|
TRACKCONTROL_NO_4:
        CLR     0x14(A6)                        | result = 0 (no part)
        BRA.B   TRACKCONTROL_EXIT               | -> restore port and return

| ----------------------------------------------------------
|
| _UpdtControl ($A953)
|
UpdtControl:
        LINK    A6,#-0x18                       | 24 bytes local (pen state)
        MOVEM.L D7/A3,-(SP)                     | save registers
        MOVE.L  0xC(A6),A3                      | A3 = theWindow
        MOVEQ.L #0x8,D7                         | D7 = 8 (param size + update region check)
        BRA.B   DRAWCONTROLS_LOOP               | -> shared draw loop

| ----------------------------------------------------------
|
| _DrawControls ($A969)
|
| Called during boot.
DrawControls:
        LINK    A6,#-0x18                       | 24 bytes local (pen state)
        MOVEM.L D7/A3,-(SP)                     | save registers
        MOVE.L  0x8(A6),A3                      | A3 = theWindow
        MOVEQ.L #0x4,D7                         | D7 = 4 (param size, draw all)
DRAWCONTROLS_LOOP:
        SUBQ.W  #0x4,SP                         | space for saved port
        MOVE.L  A7,-(SP)                        | push addr for GetPort
        _GetPort                                | save current port
        MOVE.L  A3,-(SP)                        | push theWindow
        _SetPort                                | set port to window
        PEA.L   -0x18(A6)                       | push pen state buffer addr
        MOVE.L  (SP),-(SP)                      | dup for SetPenState later
        _GetPenState                            | save pen state
        _PenNormal                              | reset pen to defaults
        MOVE.L  0x8C(A3),D0                     | D0 = wControlList (first control)
        BEQ.B   DRAWCONTROLS_DONE               | no controls -> done
| DRAWCONTROLS_CONT: walk control list and draw each
DRAWCONTROLS_CONT:
        MOVE.L  D0,A3                           | A3 = current ControlHandle
        CMPI    #0x8,D7                         | UpdtControl mode (check update rgn)?
        BNE.B   DRAWCONTROLS_NO                 | no, DrawControls -> draw all
        SUBQ.W  #0x2,SP                         | space for RectInRgn result
        MOVE.L  (A3),A0                         | dereference ControlHandle
        PEA.L   0x8(A0)                         | push contrlRect
        MOVE.L  0x8(A6),-(SP)                   | push update region handle
        _RectInRgn                              | control intersects update region?
        TST.B   (SP)+                           | non-zero = yes
        BEQ.B   DRAWCONTROLS_SKIP               | no intersection -> skip
DRAWCONTROLS_NO:
        MOVEQ.L #0x0,D1                         | D1 = 0 (draw whole control)
        BSR     NEWCONTROL_CONT                 | draw control via CDEF
DRAWCONTROLS_SKIP:
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  (A0),D0                         | D0 = nextControl in list
        BNE.B   DRAWCONTROLS_CONT               | more controls -> continue
DRAWCONTROLS_DONE:
        _SetPenState                            | restore pen state
        _SetPort                                | restore saved port
        MOVE.L  D7,D0                           | D0 = param size to strip
        MOVEM.L (SP)+,D7/A3                     | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.L  D0,SP                           | strip params (4 or 8 bytes)
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| DRAWCONTROLS_CONT_2
|
| Called during boot.
| DRAWCONTROLS_CONT_2: unlink handle A0 from linked list headed at (A1)
| Each node: handle -> [nextHandle, ...], list head at (A1)
| Returns D0=0 if found, D0=-1 if not found
DRAWCONTROLS_CONT_2:
        MOVEM.L D1/A2-A3,-(SP)                  | save registers
        MOVEQ.L #-0x1,D0                        | D0 = -1 (not found)
        TST.L   (A1)                            | list empty?
        BEQ.B   DRAWCONTROLS_FOUND              | yes -> not found
        MOVE.L  (A1),A2                         | A2 = first handle in list
        MOVE.L  A1,A3                           | A3 = ptr to previous link (list head)
        BRA.B   DRAWCONTROLS_CONT_3             | -> check first node

| ----------------------------------------------------------
|
| DRAWCONTROLS_NEXT: advance to next node in linked list
|
DRAWCONTROLS_NEXT:
        MOVE.L  (A2),A3                         | A3 = deref current -> prev link addr
        MOVE.L  (A3),A2                         | A2 = next handle in list
        MOVE.L  A2,D1                           | test for nil
        BEQ.B   DRAWCONTROLS_FOUND              | end of list -> not found
DRAWCONTROLS_CONT_3:
        CMPA.L  A0,A2                           | found target handle?
        BNE.B   DRAWCONTROLS_NEXT               | no -> advance
        MOVE.L  (A2),A2                         | A2 = deref target handle
        MOVE.L  (A2),(A3)                       | unlink: prev->next = target->next
        MOVEQ.L #0x0,D0                         | D0 = 0 (found and unlinked)
DRAWCONTROLS_FOUND:
        MOVEM.L (SP)+,D1/A2-A3                  | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _FindControl ($A96C)
|
| Called during boot.
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
        MOVE.L  A7,-(SP)                        | save port on stack
        _GetPort                                | get current port
        MOVE.L  A3,-(SP)                        | push theWindow
        _SetPort                                | set port to window
        TST.B   0x6E(A3)                        | window hilited (active)?
        BEQ     TRACKCONTROL_EXIT               | no -> return 0
        CLR     -(SP)                           | space for PtInRect result
        MOVE.L  D3,-(SP)                        | push thePoint
        PEA.L   PORTRECT(A3)                    | push window's portRect
        _PtInRect                               | point in window content?
        TST.B   (SP)+                           | result
        BEQ     TRACKCONTROL_EXIT               | no -> return 0
        MOVE.L  0x8C(A3),D0                     | D0 = wControlList (first control)
        BEQ     TRACKCONTROL_EXIT               | no controls -> return 0
        MOVE.L  D0,A3                           | A3 = first ControlHandle
| FINDCONTROL_NEXT: walk control list testing each
FINDCONTROL_NEXT:
        MOVE.L  (A3),A0                         | dereference ControlHandle
        CMPI.B  #0xFF,0x11(A0)                  | contrlHilite = 255 (inactive)?
        BEQ.B   FINDCONTROL_SKIP                | yes -> skip this control
        CLR     -(SP)                           | space for TestControl result
        MOVE.L  A3,-(SP)                        | push ControlHandle
        MOVE.L  D3,-(SP)                        | push thePoint
        _TestControl                            | hit-test this control
        MOVE    (SP)+,D0                        | D0 = part code
        BNE.B   FINDCONTROL_FOUND               | hit! -> record result
FINDCONTROL_SKIP:
        MOVE.L  (A3),A0                         | dereference ControlHandle
        MOVE.L  (A0),A3                         | A3 = nextControl
        MOVE.L  A3,D0                           | test for nil
        BNE.B   FINDCONTROL_NEXT                | more controls -> test next
        BRA     TRACKCONTROL_EXIT               | end of list -> return 0

| ----------------------------------------------------------
|
| FINDCONTROL_FOUND: found a hit -- store result and continue searching
| (last hit wins, so deeper controls take priority)
|
| Called during boot.
FINDCONTROL_FOUND:
        MOVE.L  0x8(A6),A0                      | A0 = VAR whichControl ptr
        MOVE.L  A3,(A0)                         | whichControl = this ControlHandle
        MOVE    D0,0x14(A6)                     | store part code in result
        BRA.B   FINDCONTROL_SKIP                | continue scanning remaining controls

| ----------------------------------------------------------
|
| RESOURCE_MAP
|
| RESOURCE_MAP: empty resource map template (34 bytes)
| used to initialize a new resource file with no resources
| header: dataOfs=256, mapOfs=256, dataLen=0, mapLen=30
| map: typeListOfs=28, nameListOfs=30, typeCount=-1 (0 types)
RESOURCE_MAP:
  .byte 0x00,0x00,0x01,0x00,0x00,0x00
  .byte 0x01,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x1E,0x00,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x1C,0x00,0x1E,0xFF,0xFF
  .byte 0x00,0x00,0x00,0x01

| InitResources -- _InitResources ($A995): FUNCTION InitResources: Integer;
InitResources:
        CLR.L   (RMgrLastResHand).w             | clear last resource handle
        BSR     RESMGR_CONT_4                   | initialize resource manager globals
        TST.L   (TopMapHndl).w                  | is resource map already initialized?
        BGT.B   INITRESOURCES_SKIP              | yes -> skip initialization
        CLR.L   (ResErrProc).w                  | clear resource error procedure
        BSR.B   INITRESOURCES_CONT_2            | build ROM resource map
        MOVE.L  A0,(TopMapHndl).w               | set ROM map as top map
        MOVE.L  A0,(SysMapHndl).w               | set ROM map as system map
        MOVE.L  (OneOne).w,(SysMap).w           | set system map refnum to $0001
        BSR     INITRESOURCES_CONT_3            | load system resource file
        CLR.L   0x10(A1)                        | clear next map handle (terminate list)
        BRA.B   INITRESOURCES_SKIP_2            | branch to end of init

| ----------------------------------------------------------
|
| INITRESOURCES_SKIP
|
| Called during boot.
INITRESOURCES_SKIP:
        LEA.L   (TheZone).w,A3                  | get pointer to current heap zone
        MOVE.L  (A3),-(SP)                      | save current zone on stack
        MOVE.L  (SysZone).w,(A3)                | switch to system heap zone
        LEA.L   (SysResName).w,A1               | get pointer to 'System' filename
        BSR     P_NewMap                        | open system resource map
        MOVE.L  (SP)+,(A3)                      | restore previous heap zone
        MOVE    D6,0x8(A6)                      | save file reference number
        TST.L   D0                              | did map open successfully?
        BLE.B   INITRESOURCES_SKIP_2            | no -> skip to end
        MOVE.L  A4,(TopMapHndl).w               | set system map as top map
        MOVE.L  A4,(SysMapHndl).w               | set system map as system map
        MOVE    D6,(CurMap).w                   | set current map refnum
        MOVE    D6,(SysMap).w                   | set system map refnum
        BSR     INITRESOURCES_CONT_4            | enable resource loading
        BSR     INITRESOURCES_CONT_3            | process initial resources
        MOVE.L  (SysMapHndl).w,0x10(A1)         | link system map to next map
        MOVE.L  (SysMapHndl).w,A1               | get system map handle
        MOVE.L  (A1),A1                         | dereference system map handle
        CLR.L   0x10(A1)                        | clear next map field
        BSR.B   INITRESOURCES_CONT              | init ROM override resources
INITRESOURCES_SKIP_2:
        BRA     RESMGR_EXIT_6                   | branch to end

| ----------------------------------------------------------
|
| INITRESOURCES_CONT
|
| Called during boot.
INITRESOURCES_CONT:
        SUBQ.W  #0x4,SP                         | make space for resource handle
        MOVE.L  #0x524F7672,-(SP)               | push 'ROvr' resource type
        CLR     -(SP)                           | push resource ID 0
        _GetResource                            | get 'ROvr' resource
        MOVE.L  (SP)+,D0                        | pop resource handle
        BEQ.B   INITRESOURCES_SKIP_3            | if nil -> skip override
        MOVE.L  D0,A0                           | copy handle to A0
        MOVE.L  (A0),A0                         | dereference handle to get pointer
        JSR     (A0)                            | jump to override code
INITRESOURCES_SKIP_3:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| INITRESOURCES_CONT_2
|
| Called during boot.
INITRESOURCES_CONT_2:
        MOVE.L  (ROMBase).w,A0                  | get ROM base address
        ADDA.L  0x1A(A0),A0                     | add offset to ROM resource map
        MOVE.L  A0,A2                           | save ROM map pointer
        MOVEQ.L #0x1A,D0                        | initialize offset to 0x1A
        ADD     (A0)+,D0                        | add first word (offset)
        ASL.L   #0x2,D0                         | multiply by 4 for size
        ADD     (A0)+,D0                        | add next word
        MOVE.L  D0,A1                           | copy size to A1
        _NewPtrSys                              | allocate pointer in system heap
        MOVE.L  (TheZone).w,-(SP)               | save current zone
        CLR.L   -(SP)                           | push 0
        MOVE    #0x4,-(SP)                      | push 4
        ADDA.L  A0,A1                           | add size to pointer
        MOVE.L  A1,-(SP)                        | push end address
        MOVE.L  A0,-(SP)                        | push start address
        MOVE.L  A0,A1                           | copy start address to A1
        MOVE.L  A7,A0                           | copy stack pointer to A0
        _InitZone                               | initialize ROM zone
        BSET    #0x0,0x16(A1)                   | set zone flags
        MOVE.L  A1,(TheZone).w                  | set ROM zone as current
        ADDA    #0xE,SP                         | clean up stack
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A2)+,D0                        | get map size from ROM
        ASL.L   #0x2,D0                         | multiply by 4
        _NewPtr                                 | allocate pointer in ROM zone
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A2)+,D0                        | get next size from ROM
        _NewHandle                              | allocate handle for ROM map
        BSET    #0x7,(A0)                       | lock handle
        MOVE.L  A0,(ROMMapHandle).w             | save ROM map handle
        MOVE.L  (SP)+,(TheZone).w               | restore previous zone
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| INITRESOURCES_CONT_3
|
| Called during boot.
INITRESOURCES_CONT_3:
        MOVE.L  (ROMBase).w,A2                  | A2 = ROM base address
        ADDA.L  0x1A(A2),A2                     | A2 = pointer to the start of the ROM resource map data
        MOVE    (A2)+,D1                        | Read and discard the first word of the ROM map data
        MOVEQ.L #0x0,D2                         | Clear D2 for zero-extending the size word
        MOVE    (A2)+,D2                        | D2 = size of ROM resource map data (word)
        MOVE.L  D2,D0                           | D0 = size of ROM resource map data (long)
        MOVE.L  (ROMMapHandle).w,A0             | A0 = handle for the RAM copy of the ROM resource map
        MOVE.L  A0,A4                           | A4 = save handle for later use
        _SetHandleSize                          | _SetHandleSize: resize ROM Map handle to fit the map data
        MOVE.L  D2,D0                           | D0 = size of map data again for BlockMove
        MOVE.L  (A4),A1                         | A1 = destination pointer (dereferenced handle)
        MOVE.L  A2,A0                           | A0 = source pointer (current position in ROM map data)
        _BlockMove                              | _BlockMove: copy the ROM resource map data into the handle
        MOVE    #0x1,0x14(A1)                   | Set file reference number of the new map to 1 (ROM)
        BSR     RESMGR_CONT_3                   | Parse the newly copied resource map's type list
INITRESOURCES_LOOP:
        MOVE.B  0x4(A2),D1                      | D1 = resource attributes byte from reference list entry
        BSR     RESMGR_OK_4                     | Set resource attributes in the handle (if any)
        ADDA    #0xC,A2                         | A2 = advance to next resource reference list entry (12 bytes)
        DBF     D4,INITRESOURCES_LOOP           | Loop through all resource types
        RTS                                     | Return from subroutine

| ----------------------------------------------------------
|
| INITRESOURCES_CONT_4
|
| Called during boot.
INITRESOURCES_CONT_4:
        ST.B    (ResLoad).w                     | Set ResLoad flag to TRUE (temporarily enable resource loading)
| INITRESOURCES_CONT_5 -- preload flagged resources.
INITRESOURCES_CONT_5:
        BSR     RESMGR_CONT                     | Find first resource type in the current map
        BMI.B   INITRESOURCES_ERR               | If no resource types found, exit
        BSR     RESMGR_CONT_3                   | Parse the resource type list
        BMI.B   INITRESOURCES_ERR               | If parsing fails, exit
INITRESOURCES_LOOP_2:
        ADDQ.W  #0x8,A2                         | Skip over resource type and number of resources in type list
        CLR.L   (A2)+                           | Clear the handle field in the resource reference list entry
        DBF     D4,INITRESOURCES_LOOP_2         | Loop through all resources of this type
        TST.B   (ResLoad).w                     | Check if ResLoad was originally TRUE
        BEQ.B   INITRESOURCES_ERR               | If not, skip auto-loading override resources
        BSR.B   P_SuperLoad                     | Call patch routine to load override resources
        BEQ.B   INITRESOURCES_ERR               | If patch returns zero, we are done
        MOVEQ.L #0x2,D1                         | D1 = 2 (number of resources to check for loading)
        BSR     FINDNEXT_FROM_START             | Check and load 'DRVR' and 'PACK' resources
        BMI.B   INITRESOURCES_ERR               | If error, exit
INITRESOURCES_RETRY:
        BSR     P_CheckLoad                     | Check if a resource should be loaded
        MOVEQ.L #0x2,D1                         | D1 = 2 (number of resources to check)
        BSR     FINDNEXT_CUR_OFS                | Check and load 'WDEF' and 'MDEF' resources
        BEQ.B   INITRESOURCES_RETRY             | If a resource was loaded, check again
INITRESOURCES_ERR:
        RTS                                     | Return from subroutine

| ----------------------------------------------------------
|
| P_Super Load
|
| Called during boot.
P_SuperLoad:
        MOVE.L  (0x7E4).w,A0                    | A0 = Get address from jSuperLoad vector
        JMP     (A0)                            | Jump to the SuperLoad patch routine

| ----------------------------------------------------------
|
| Super Load
|
| Called during boot.
SuperLoad:
        BSR     SUPERLOAD_CONT_3                | Prepare to override ROM resources with system file resources
        BMI     RESMGR_ERR                      | If preparation failed (e.g., no memory), abort
        BSR     RETURNS_24                      | Find first resource in the current map
        MOVE.L  (A4),A1                         | A1 = pointer to the resource map data
SUPERLOAD_NEXT:
        MOVE.L  0x4(A2),D0                      | D0 = resource type from reference list entry
        AND.L   (Lo3Bytes).w,D0                 | Mask off attribute bits from resource type
        CMP.L   (RMgrHiVars_LastResType).w,D0   | Compare with the last resource type found
        BGE.B   SUPERLOAD_SKIP                  | If type is >= last type, skip (already processed or invalid)
        MOVE.L  (TheZone).w,-(SP)               | Save current heap zone
        BTST    #0x6,0x4(A2)                    | Test resSysHeap attribute (bit 6)
        BEQ.B   SUPERLOAD_NO                    | If not set, use application heap
        MOVE.L  (SysZone).w,(TheZone).w         | If set, switch to system heap
SUPERLOAD_NO:
        MOVE.L  0x4(A2),D2                      | D2 = resource type
        AND.L   (Lo3Bytes).w,D2                 | Mask off attribute bits
        BSR.B   SUPERLOAD_RETRY                 | Get resource data offset and size from map
        BTST    #0x4,0x4(A2)                    | Test resPurgeable attribute (bit 4)
        SUBA.L  (A4),A2                         | A2 = offset of current resource reference entry from map start
        SUBA.L  (A4),A3                         | A3 = offset of current resource data from map start
        BEQ.B   SUPERLOAD_NO_2                  | If not purgeable, allocate a normal handle
        _NewPtr                                 | _NewPtr: Allocate a non-relocatable purgeable pointer
        BMI.B   SUPERLOAD_ERR                   | If allocation fails, branch to error handler
        MOVE.L  A0,A1                           | A1 = the new pointer
        _NewEmptyHandle                         | _NewEmptyHandle: Allocate a handle for the purgeable block
        MOVE.L  A0,D1                           | D1 = the new handle
        MOVE.L  A1,(A0)                         | Store the pointer in the handle
        MOVE.L  A0,D0                           | D0 = the new handle
        SUB.L   -(A1),D0                        | Obscure instruction, part of purgeable handle setup
        BSET    #0x7,-0x4(A1)                   | Set the locked bit in the master pointer block header
        BCLR    #0x6,-0x4(A1)                   | Clear the purgeable bit in the master pointer block header
        MOVE.L  D0,(A1)+                        | Store calculated value at start of data block
        BRA.B   SUPERLOAD_CONT                  | Continue to copy data

| ----------------------------------------------------------
|
| SUPERLOAD_NO_2
|
SUPERLOAD_NO_2:
        _NewHandle                              | _NewHandle: Allocate a relocatable block for the resource data
        BMI.B   SUPERLOAD_ERR                   | If allocation fails, branch to error handler
        MOVE.L  A0,D1                           | D1 = the new handle
        MOVE.L  (A0),A1                         | A1 = pointer to the data (dereference handle)
SUPERLOAD_CONT:
        BSR.B   SUPERLOAD_RETRY                 | Get resource data offset and size again
        _BlockMove                              | _BlockMove: Copy resource data from system file map to new handle
        ADDA.L  (A4),A2                         | A2 = restore absolute pointer to reference entry
        ADDA.L  (A4),A3                         | A3 = restore absolute pointer to resource data
        MOVE.L  D1,0x8(A2)                      | Store the new handle in the resource reference list entry
        MOVE.L  D1,A0                           | A0 = the new handle
        MOVE.B  0x4(A2),D1                      | D1 = resource attributes byte
        BSR     CHECKLOAD_CONT_3                | Set the attributes (e.g., locked, purgeable) on the new handle
        MOVE.L  (SP)+,(TheZone).w               | Restore the original heap zone
SUPERLOAD_SKIP:
        BSR     RETURNS_28                      | Advance to the next resource in the map
        BPL.B   SUPERLOAD_NEXT                  | If not end of map, loop to process next resource
        MOVE.L  D7,A0                           | A0 = handle to the temporary map buffer
        _DisposeHandle                          | _DisposeHandle: Free the temporary map buffer
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        RTS                                     | Return

| ----------------------------------------------------------
|
| SUPERLOAD_ERR
|
SUPERLOAD_ERR:
        MOVE.L  (SP)+,(TheZone).w               | Restore the original heap zone
        MOVE.L  D7,A0                           | A0 = handle to the temporary map buffer
        _DisposeHandle                          | _DisposeHandle: Free the temporary map buffer
        BRA     RESMGR_ERR                      | Branch to common error exit

| SUPERLOAD_RETRY -- get resource data offset and size from map.
| ----------------------------------------------------------
|
| SUPERLOAD_RETRY
|
SUPERLOAD_RETRY:
        MOVE.L  D7,A0                           | A0 = handle to the temporary map buffer
        MOVE.L  (A0),A0                         | A0 = pointer to the map data
        ADDA.L  D2,A0                           | A0 = pointer to the specific resource type list
| SUPERLOAD_CONT_2 -- read 4 bytes from A0 as big-endian long.
SUPERLOAD_CONT_2:
        MOVE.B  (A0)+,D0                        | Read MSB of data length
        LSL     #0x8,D0                         | Shift to bits 23-16
        MOVE.B  (A0)+,D0                        | Read byte 2 of data length
        SWAP    D0                              | Move word to high word of D0
        MOVE.B  (A0)+,D0                        | Read byte 3 of data length
        LSL     #0x8,D0                         | Shift to bits 7-0 of low word
        MOVE.B  (A0)+,D0                        | Read LSB of data length
        RTS                                     | Return with data length in D0

| ----------------------------------------------------------
|
| SUPERLOAD_CONT_3
|
| Called during boot.
SUPERLOAD_CONT_3:
        TST.L   (RMgrHiVars_LastResType).w      | Check if override process is already running
        BEQ.B   SUPERLOAD_ERR_2                 | If not, this is an error, return -1
        MOVEQ.L #0x0,D7                         | D7 = 0 (initialize max available memory)
        MOVE.L  A7,D0                           | D0 = current stack pointer
        AND.L   (Lo3Bytes).w,D0                 | Mask to 24-bit address
        SUB.L   (MinStack).w,D0                 | D0 = available stack space
        CMP.L   (ApplLimit).w,D0                | Is stack pointer above application memory limit?
        BCS.B   SUPERLOAD_OK                    | If so, stack is within bounds
        MOVE.L  (ApplLimit).w,D0                | If not, use ApplLimit as effective top of stack
SUPERLOAD_OK:
        SUB.L   (HeapEnd).w,D0                  | D0 = memory between top of heap and stack
        BLE.B   SUPERLOAD_SKIP_2                | If no space, skip
        CMPI.L  #0xC,D0                         | Is there at least 12 bytes?
        BLS.B   SUPERLOAD_SKIP_2                | If not, skip
        MOVE.L  D0,D7                           | D7 = potential free memory block size
SUPERLOAD_SKIP_2:
        _MaxBlock                               | _MaxBlock: Get size of largest free block in the heap
        CMP.L   D7,D0                           | Is largest heap block bigger than stack-heap gap?
        BLE.B   SUPERLOAD_NO_3                  | If not, keep the stack-heap gap size
        MOVE.L  D0,D7                           | If so, use the larger heap block size
SUPERLOAD_NO_3:
        MOVE.L  (IllegalInstructionVector).w,D0 | D0 = size of system resource file map (stored in vector)
        BSR.B   SUPERLOAD_CONT_5                | Check if there's enough memory for the map
        BPL.B   SUPERLOAD_CONT_4                | If enough memory, proceed
        MOVE.L  (AddressErrorVector).w,D0       | D0 = size of resource map name list
        BSR.B   SUPERLOAD_CONT_5                | Check if there's enough memory for names
        BPL.B   SUPERLOAD_CONT_4                | If enough memory, proceed
        MOVE.L  (BusErrorVector).w,D0           | D0 = size of resource map type list
        BSR.B   SUPERLOAD_CONT_5                | Check if there's enough memory for types
        BMI.B   SUPERLOAD_ERR_2                 | If still not enough memory, fail
SUPERLOAD_CONT_4:
        _NewHandle                              | _NewHandle: Attempt to allocate a handle of the required size
        BMI.B   SUPERLOAD_ERR_2                 | If allocation fails, exit with error
        _DisposeHandle                          | _DisposeHandle: Immediately free it (this was just a test)
        MOVE.L  D1,D0                           | D0 = size of the system resource map
        _NewHandle                              | _NewHandle: Allocate the handle for real
        BMI.B   SUPERLOAD_ERR_2                 | If allocation fails, exit with error
        MOVE.L  D1,D0                           | D0 = size of the map
        MOVE.L  A0,D7                           | D7 = save the new handle
        MOVE.L  (A0),D1                         | D1 = pointer to the allocated block
        MOVE.L  (A4),A0                         | A0 = pointer to the current resource map
        MOVE.L  (A0),D2                         | D2 = pointer to the map data
        BSR     CHECKLOAD_CONT_10               | Read the system resource file map into the new handle
        BEQ.B   SUPERLOAD_OK_2                  | If read was successful, continue
        MOVE.L  D7,A0                           | If read failed, A0 = handle to dispose
        _DisposeHandle                          | _DisposeHandle: Free the allocated handle
SUPERLOAD_ERR_2:
        MOVEQ.L #-0x1,D0                        | D0 = -1 (error code)
SUPERLOAD_OK_2:
        RTS                                     | Return

| SUPERLOAD_CONT_5 -- check if there's enough memory for the map.
| ----------------------------------------------------------
|
| SUPERLOAD_CONT_5
|
SUPERLOAD_CONT_5:
        MOVE.L  D0,(RMgrHiVars_LastResType).w   | Store required size in a global variable
        BEQ     RESMGR_ERR                      | If required size is 0, branch to error
        BMI.B   SUPERLOAD_EXIT                  | If required size is negative, it's a flag, just return
        MOVE.L  D0,D1                           | D1 = required size
        ADD.L   D0,D0                           | D0 = required size * 2
        MOVE.L  (A4),A0                         | A0 = pointer to current map
        ADD.L   0xC(A0),D0                      | D0 = (size * 2) + map data length
        CMP.L   D0,D7                           | Compare required memory (D0) with available memory (D7)
SUPERLOAD_EXIT:
        RTS                                     | Return (condition codes will be set by CMP)

| ----------------------------------------------------------
|
| P_New Map
|
| Called during boot.
P_NewMap:
        MOVE.L  (0x7EC).w,A0                    | A0 = Get address from jNewMap vector
        JMP     (A0)                            | Jump to the NewMap patch routine

| ----------------------------------------------------------
|
| New Map
|
| Called during boot.
NewMap:
        CLR.L   (RMgrHiVars_LastResType).w      | Clear last resource type cache
        CLR.L   (RMgrLastResHand).w             | Clear last resource handle cache
        MOVEQ.L #0x24,D0                        | D0 = size of a resource map header (36 bytes)
        _NewHandle                              | _NewHandle: Allocate a handle for the new resource map header
        MOVE    D0,(ResErr).w                   | Store result code in ResErr
        BMI     NEWMAP_ERR_3                    | If allocation failed, branch to error handler
        MOVE.L  A0,A4                           | A4 = the new resource map handle
        BSR     CHECKLOAD_CONT_9                | Initialize the new resource map header
        BSR     RSRCZONEINIT_CONT_2             | Open the file and read the resource map location
        BEQ.B   NEWMAP_CONT                     | If successful, proceed to read the map
        CMPI    #-0x31,D0                       | Is error "resource file not found"?
        BNE     NEWMAP_ERR_2                    | If not, go to generic error handler
        MOVEM.L D6/A2-A4,-(SP)                  | Save registers
        BSR     RESMGR_CONT                     | Find first resource type in the current map
        MOVEM.L (SP)+,D6/A2-A4                  | Restore registers
        BNE     NEWMAP_ERR_2                    | If no types found, it's an error
        CLR     (ResErr).w                      | Clear error code
        MOVE.L  A4,A0                           | A0 = handle to dispose
        _DisposeHandle                          | _DisposeHandle: Free the allocated map header
        RTS                                     | Return

| ----------------------------------------------------------
|
| NEWMAP_CONT
|
| Called during boot.
NEWMAP_CONT:
        _GetEOF                                 | _GetEOF: Get the end-of-file position
        MOVE    #-0x27,(ResErr).w               | Set ResErr to "I/O error" (as a default)
        TST.L   0x1C(A0)                        | Check the file's logical EOF
        BEQ.B   NEWMAP_ERR                      | If file is empty, it's an error
        MOVEQ.L #0x24,D0                        | D0 = size of resource map header
        MOVE.L  (A4),A1                         | A1 = pointer to the map header
        MOVE.L  A1,D1                           | D1 = pointer to the map header
        MOVEQ.L #0x0,D2                         | D2 = 0 (unused parameter?)
        BSR     CHECKLOAD_CONT_10               | Read the resource map from the file into a temporary buffer
        BMI.B   NEWMAP_ERR                      | If read fails, branch to error handler
        MOVE.L  A1,A0                           | A0 = pointer to map header
        ADDA.L  #0x10,A0                        | A0 = pointer to map data offset within header
        LEA.L   (RMgrHiVars_LastResType).w,A1   | A1 = pointer to Resource Manager globals
        MOVEQ.L #0x14,D0                        | D0 = 20 bytes to move
        _BlockMove                              | _BlockMove: Copy map offsets and size from temp buffer to globals
        MOVE.L  A0,A1                           | A1 = pointer to map data offset within header
        SUBA.L  #0x10,A1                        | A1 = pointer back to start of map header
        BSR.B   NEWMAP_RETRY                    | Invalidate resource cache
        MOVEQ.L #0xC,D1                         | D1 = 12 (offset to map data length)
        MOVE.L  0x4(A1),D2                      | D2 = map data offset
        ADD.L   D1,D2                           | D2 = offset to map data length
        MOVE.L  0xC(A1),D4                      | D4 = map data length
        MOVE.L  D4,D0                           | D0 = map data length
        MOVE.L  A4,A0                           | A0 = the resource map handle
        _SetHandleSize                          | _SetHandleSize: Resize the handle to fit the entire map
        MOVE    D0,(ResErr).w                   | Store result code in ResErr
        BNE.B   NEWMAP_ERR                      | If resize failed, branch to error handler
        MOVE.L  (A4),A1                         | A1 = pointer to the resized map block
        MOVE.L  D4,D0                           | D0 = map data length
        SUB.L   D1,D0                           | D0 = map data length - 12
        ADD.L   A1,D1                           | D1 = pointer to where map data should go
        BSR     CHECKLOAD_CONT_10               | Read the actual resource map data from file
        BMI.B   NEWMAP_ERR                      | If read fails, branch to error handler
        TST.L   (RMgrHiVars_LastResType).w      | Check if override process is running
        BEQ.B   NEWMAP_SKIP                     | If not, skip this part
        MOVE.L  0xC(A1),(RMgrHiVars_LastResType).w | Store map data length in global
        BSR.B   NEWMAP_RETRY                    | Invalidate resource cache again
NEWMAP_SKIP:
        MOVE.L  D4,0xC(A1)                      | Store map data length in the map header
        BSR     CHECKLOAD_CONT_19               | Update map attributes
        BMI.B   NEWMAP_ERR                      | If error, branch to handler
        CLR.L   0x10(A1)                        | Clear the map data offset field in the header
        MOVE    D6,0x14(A1)                     | Store the file reference number in the header
        MOVEQ.L #0x1,D0                         | D0 = 1 (success)
        RTS                                     | Return

| ----------------------------------------------------------
|
| NEWMAP_ERR
|
NEWMAP_ERR:
        BSR     CHECKLOAD_CONT_9                | Re-initialize the map header (clear it)
        _Close                                  | _Close: Close the resource file
NEWMAP_ERR_2:
        MOVE.L  A4,A0                           | A0 = handle to dispose
        _DisposeHandle                          | _DisposeHandle: Free the map header handle
NEWMAP_ERR_3:
        CLR.L   (RMgrHiVars_LastResType).w      | Clear last resource type cache
        CLR.L   (RMgrLastResHand).w             | Clear last resource handle cache
        MOVEQ.L #-0x1,D6                        | D6 = -1 (error)
        MOVEQ.L #-0x1,D0                        | D0 = -1 (error)
        RTS                                     | Return

| ----------------------------------------------------------
|
| NEWMAP_RETRY
|
| Called during boot.
NEWMAP_RETRY:
        MOVE.L  (RMgrHiVars_LastResType).w,D0   | Get the last resource type global
        SUBI.L  #0x20B7A185,D0                  | Check for a specific magic number used during override
        BEQ.B   NEWMAP_SKIP_2                   | If it matches, don't clear the global
        CLR.L   (RMgrHiVars_LastResType).w      | Otherwise, clear the last resource type cache
NEWMAP_SKIP_2:
        CLR.L   (RMgrLastResHand).w             | Clear the last resource handle cache
        RTS                                     | Return

| ----------------------------------------------------------
|
| _RsrcZoneInit ($A996)
|
| Called during boot.
RsrcZoneInit:
        BSR     RESMGR_CONT_4                   | Initialize resource manager globals
        TST     (SysMap).w                      | Check if the system resource map exists
        BMI.B   RSRCZONEINIT_ERR                | If not, skip
        BSR.B   RSRCZONEINIT_NEXT               | Close all open resource files down to the system map
        MOVE.L  (SysMapHndl).w,A4               | A4 = handle to the system resource map
        BSR     RESMGR_CONT_3                   | Parse the system map's type list
        BMI.B   RSRCZONEINIT_ERR                | If parsing fails, skip
RSRCZONEINIT_LOOP:
        BTst    #0x6,0x4(A2)                    | Test resSysHeap attribute
        BNE.B   RSRCZONEINIT_CONT               | If set, keep the handle
        CLR.L   0x8(A2)                         | If not, clear the resource handle (force reload from disk)
RSRCZONEINIT_CONT:
        ADDA    #0xC,A2                         | Advance to next resource reference entry
        DBF     D4,RSRCZONEINIT_LOOP            | Loop through all resources
RSRCZONEINIT_ERR:
        BRA     RESMGR_EXIT_6                   | Branch to continue initialization

| ----------------------------------------------------------
|
| RSRCZONEINIT_NEXT
|
| Called during boot.
RSRCZONEINIT_NEXT:
        MOVE.L  (TopMapHndl).w,A0               | A0 = handle of the topmost resource map
        CMPA.L  (SysMapHndl).w,A0               | Is the top map the system map?
        BEQ.B   RSRCZONEINIT_DONE               | If yes, we are done
        MOVE.L  (A0),A0                         | A0 = pointer to the map header
        MOVE    0x14(A0),-(SP)                  | Push the file reference number
        _CloseResFile                           | _CloseResFile: Close the current top resource file
        BRA.B   RSRCZONEINIT_NEXT               | Loop to close the next one

| ----------------------------------------------------------
|
| RSRCZONEINIT_DONE
|
| Called during boot.
RSRCZONEINIT_DONE:
        RTS                                     | Return from subroutine

| ----------------------------------------------------------
|
| RSRCZONEINIT_CONT_2
|
| Called during boot.
RSRCZONEINIT_CONT_2:
        MOVE.L  A1,D0                           | D0 = file name pointer
        BTST    #0x0,D0                         | Is the address odd?
        BNE.B   OPENRF_SET_FNAME                | If so, it's an error
        BTST    #0x1D,D0                        | Test bit 29 (used for special file system calls)
        BEQ.B   OPENRF_SET_FNAME                | If clear, it's a normal pointer
        MOVEM.L A0-A1,-(SP)                     | Save registers before calling file system
