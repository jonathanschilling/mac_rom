| Control Manager
|
| Apple source: ControlMgr.a (MacSEROM.lst module CMGR). The Control
| Manager traps with their local helpers, in physical ROM order:
|   NewControl, DisposControl, KillControls, Draw1Control,
|   ShowControl, HideControl, MoveControl,
|   GetCRefCon, SetCRefCon, GetCtlAction, SetCtlAction,
|   SizeControl, HiliteControl, GetCTitle, SetCTitle,
|   GetCtlValue, GetMinCtl, GetMaxCtl, SetCtlValue, SetMinCtl, SetMaxCtl,
|   TestControl, DragControl, TrackControl,
|   UpdtControls, DrawControls, FindControl
| The controls are drawn and hit-tested by their CDEF (control definition
| function), called with a message number, the control handle and a
| parameter.
|
| References: Inside Macintosh Vol I, Ch 10 (The Control Manager).

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
| Called by: DRAGCONTROL_CONT, NEWCONTROL_RETRY, NEWCONTROL_CONT_3, DisposControl, TestControl (and 3 more)
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
        RTS                                     | return from NEWCONTROL_SKIP_2

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
DisposControl:
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
| _Draw1Control ($A96D): draw one control if it is visible
| Pascal: PROCEDURE Draw1Control(theControl: ControlHandle);
| Apple source name: DrawOneControl (System 7.1 ControlMgr.a; MacSEROM.lst
| DRAWONECONTROL). MacPlusROM.lst lists this entry only as slot Trap1_16D.
| Entry: 0x4(SP) = theControl. Saves A3 and joins ShowControl at
| SHOWCONTROL_CONT without touching contrlVis: NEWCONTROL_CONT sends drawCntl
| (part 0 = whole control) to the CDEF only if the control is visible and its
| contrlRect intersects the owner window's portRect.
|
Trap1_16D:                                      | MacPlusROM.lst placeholder for trap $A96D (Draw1Control)
Draw1Control:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 = ControlHandle
        MOVE.L  (A3),A0                         | A0 = ControlRecord (NEWCONTROL_CONT reloads)
        BRA.B   SHOWCONTROL_CONT                | ShowControl tail, contrlVis unchanged

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
        RTS                                     | return from SHOWCONTROL_EXIT

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
        SUB     LEFT(A0),D1                     | D1 = horizontal delta (new - old left)
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
        RTS                                     | return from GetCTitle

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
        MOVEM.L 0xE(A6),D3-D4/A3                | D3=limitRect ptr, D4=startPt, A3=ControlHandle
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
        MOVE.L  contrlOwner(A0),-(SP)           | push contrlOwner (WindowPtr at offset 4)
        _SetPort                                | set port to control's owner window
        MOVEM.L (SP)+,D0-D1                     | restore D0-D1
        RTS                                     | return from DRAGCONTROL_CONT_2

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
| _UpdtControl ($A953): draw the controls of a window that are in a region
| Pascal: PROCEDURE UpdtControls(theWindow: WindowPtr; updateRgn: RgnHandle);
|         (the MPW interfaces spell it UpdtControl, like the trap macro)
| Entry (after LINK): 0x8(A6) = updateRgn, 0xC(A6) = theWindow
| Shares DrawControls' loop with D7 = 8 (parameter bytes and 'update' flag):
| with thePort = theWindow and a normal pen, every control whose contrlRect
| intersects updateRgn (_RectInRgn) is drawn through NEWCONTROL_CONT (visible
| controls inside the portRect only); port and pen state are restored.
|
UpdtControls:
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
        CMPI    #0x8,D7                         | UpdtControls mode (check update rgn)?
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
        RTS                                     | return from DRAWCONTROLS_FOUND

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
        TST.B   wVisible(A3)                    | is this window visible? (wVisible)
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

