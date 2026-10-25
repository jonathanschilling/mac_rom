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

| Apple source module: CMGR
NEWCONTROL:
    LINK        A6,#0x0                         | set up frame
    MOVEM.L     A2-A4,-(A7)                     | save regs
    LEA.L       0x22(A6),A4                     | A4 = past last param (rwa)
    MOVEQ.L     #0x29,D0                        | size = 41 + titleLen bytes
    MOVEQ.L     #0x0,D1                         | clear D1 high
    MOVEA.L     0x16(A6),A0                     | A0 = title Pascal str
    MOVE.B      (A0),D1                         | D1 = title length
    ADD.L       D1,D0                           | total size
    _NewHandle                                  | allocate -> A0
    MOVEA.L     A0,A3                           | A3 = ControlHandle
    MOVE.L      A0,(A4)                         | save handle to caller's slot
    MOVEA.L     (A3),A2                         | A2 = deref ControlRecord
    MOVEA.L     -(A4),A1                        | A1 = theWindow
    MOVE.L      A1,0x4(A2)                      | ctrl.contrlOwner = theWindow
    MOVE.L      0x8C(A1),(A2)                   | ctrl.nextControl = window.controlList head
    MOVE.L      A3,0x8C(A1)                     | window.controlList = new control
    LEA.L       0x8(A2),A1                      | A1 = ctrl.contrlRect
    MOVEA.L     -(A4),A0                        | A0 = boundsRect ptr (caller's stack)
    MOVE.L      (A0)+,(A1)+                     | copy topLeft
    MOVE.L      (A0),(A1)                       | copy botRight
    CLR.B       0x10(A2)                        | ctrl.contrlVis = 0 initially
    MOVE.L      A3,-(A7)                        | push ControlHandle
    MOVE.L      -(A4),-(A7)                     | push title ptr
    _SetControlTitle                            | install title
    MOVEA.L     (A3),A2                         | re-deref (handle may have moved)
    LEA.L       0x10(A2),A0                     | A0 = ctrl.contrlVis
    SUBQ.W      #0x2,A4                         | step back to "visible" param
    TST.B       (A4)                            | visible argument true?
    SNE.B       (A0)+                           | contrlVis = 0xFF if true, 0 if false
    CLR.B       (A0)+                           | contrlHilite = 0
    MOVE.W      -(A4),(A0)+                     | contrlValue = value
    MOVE.W      -(A4),(A0)+                     | contrlMin = min
    MOVE.W      -(A4),(A0)+                     | contrlMax = max
    MOVE.W      -(A4),D0                        | D0 = procID
    LSR.W       #0x4,D0                         | D0 = procID / 16 = CDEF resID
| Load CDEF resource for this control type. If the handle is nil,
| _GetResource fails -> retry. (This loop ensures we get a valid CDEF.)
NEWCONTROL_RETRY:
    SUBQ.W      #0x4,A7                         | reserve _GetResource result slot
    MOVE.L      #0x43444546,-(A7)               | push 'CDEF' resType
    MOVE.W      D0,-(A7)                        | push resID
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | search ROM map
    _GetResource                                | -> handle in result slot
    MOVEQ.L     #0x0,D0                         | resID = 0 for retry
    MOVEA.L     (A3),A0                         | A0 = deref ControlRecord
    LEA.L       0x18(A0),A0                     | A0 = ctrl.contrlDefProc
    MOVE.L      (A7)+,(A0)                      | store CDEF handle
    BEQ.B       NEWCONTROL_RETRY                | nil -> retry with default
    MOVE.W      (A4),D0                         | D0 = procID (low half)
    ANDI.W      #0xF,D0                         | low nibble = variant code
    MOVE.B      D0,(A0)                         | store variant in tag byte of handle
    ADDQ.W      #0x4,A0                         | A0 = ctrl.contrlData
    CLR.L       (A0)+                           | clear contrlAction longword (0,4)
    CLR.L       (A0)+                           | clear contrlData longwords
    MOVE.L      -(A4),(A0)+                     | copy refCon
    MOVEQ.L     #0x3,D0                         | CDEF msg #3 = init
    BSR.B       NEWCONTROL_FOUND                | dispatch to CDEF
    TST.B       0x14(A6)                        | visible flag in arg?
    BEQ.B       NEWCONTROL_SKIP                 | no -> skip initial draw
    MOVEQ.L     #0x0,D1                         | param = 0
    BSR.B       NEWCONTROL_CONT                 | force initial draw
NEWCONTROL_SKIP:
    MOVEM.L     (A7)+,A2-A4                     | restore regs
    UNLK        A6                              | tear down frame
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDA.W      #0x1A,A7                        | strip 26 bytes of params
    JMP         (A0)                            | tail-call return from NEWCONTROL_SKIP via A0
| ----------------------------------------------------------
|
| Visibility-gated CDEF dispatch: only call CDEF if control is visible.
| In: D0/D1 = msg/param to forward
| Called by: NEWCONTROL_RETRY, SHOWCONTROL_CONT, HILITECONTROL_DRAW_NEW, SETCTLVALUE_NO_2, DRAWCONTROLS_NO
NEWCONTROL_CONT:
    MOVEQ.L     #0x0,D0                         | msg = 0 (draw)
    MOVEA.L     (A3),A0                         | A0 = deref ControlRecord
    TST.B       0x10(A0)                        | contrlVis nonzero?
    BEQ.B       NEWCONTROL_SKIP_2               | no -> nothing to draw
| ----------------------------------------------------------
|
| Dispatch a CDEF message for control A3.
| In: D0 = msg (0=draw, 1=test, 2=calc, 3=init, 4=dispose, 5=pos,
|     6=thumb, 7=drag, 8=autoTrack), D1 = param, A3 = ControlHandle
| Locks the CDEF for execution (sets bit 7 of master ptr) and clears it on return.
| Restores port via _SetPort on exit (DRAGCONTROL_CONT_2 saved port to stack).
| Called by: DRAGCONTROL_CONT, NEWCONTROL_RETRY, NEWCONTROL_CONT_3, DISPOSECONTROL, TESTCONTROL (and 3 more)
NEWCONTROL_FOUND:
    BSR.W       DRAGCONTROL_CONT_2              | save port, switch to control's window port
    CLR.L       -(A7)                           | reserve CDEF result slot
    MOVEA.L     (A3),A0                         | A0 = deref ControlRecord
    MOVEQ.L     #0x0,D2                         | clear D2 high
    MOVE.B      0x18(A0),D2                     | D2 = variant code (low nibble of procID)
    MOVE.W      D2,-(A7)                        | push variant
    MOVE.L      A3,-(A7)                        | push ControlHandle
    MOVE.W      D0,-(A7)                        | push msg
    MOVE.L      D1,-(A7)                        | push param
    MOVEA.L     (A3),A0                         | A0 = deref ControlRecord
    MOVEA.L     0x18(A0),A0                     | A0 = ctrl.contrlDefProc handle
    TST.L       (A0)                            | CDEF loaded?
    BNE.B       NEWCONTROL_OK                   | yes -> call directly
    MOVE.L      A0,-(A7)                        | push handle
    CLR.B       (A7)                            | clear high byte (handle on stack)
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | force ROM map lookup
    _LoadResource                               | reload purged CDEF
NEWCONTROL_OK:
    BSET        #0x7,(A0)                       | mark CDEF locked (high bit of master)
    MOVEA.L     (A0),A0                         | A0 = CDEF code ptr
    JSR         (A0)                            | call CDEF (consumes args)
    MOVE.L      (A7)+,D0                        | D0 = CDEF result
    MOVEA.L     (A3),A0                         | A0 = deref ControlRecord
    MOVEA.L     0x18(A0),A0                     | A0 = CDEF handle
    BCLR        #0x7,(A0)                       | unlock CDEF
NEWCONTROL_CONT_2:
    _SetPort                                    | restore caller's port (saved on stack by DRAGCONTROL_CONT_2)
NEWCONTROL_SKIP_2:
    RTS                                         | return from NEWCONTROL_FOUND
| ----------------------------------------------------------
|
| Erase and invalidate a control's region (used when hiding/disposing).
| Sends CDEF msg #2 (calcCRgns) to fill a temporary region with the control's
| shape, then EraseRgn + InvalRgn on it. Bit 31 of the region handle in
| param is the calcCRgns "indicator-region" flag.
| Called during boot.
NEWCONTROL_CONT_3:
    BSR.W       DRAGCONTROL_CONT_2              | save port, switch to control's port
    MOVEM.L     A1-A4,-(A7)                     | save regs
    _NewRgn                                     | A0 = new region handle
    MOVEA.L     (A7),A4                         | A4 = region handle (saved on stack)
    MOVEQ.L     #0x2,D0                         | CDEF msg #2 = calcCRgns
    MOVE.L      A4,D1                           | D1 = region handle param
    BCLR        #0x1F,D1                        | bit 31 = 0 (full region, not indicator)
    BSR.B       NEWCONTROL_FOUND                | dispatch to CDEF
    _EraseRgn                                   | erase the control's region in port
    MOVE.L      A4,-(A7)                        | push region handle
    _InvalRgn                                   | invalidate (forces redraw later)
    MOVE.L      A4,-(A7)                        | push region handle
    _DisposeRgn                                 | free the temp region
    MOVEM.L     (A7)+,A2-A4                     | restore regs
    BRA.B       NEWCONTROL_CONT_2               | -> restore port and return
| ----------------------------------------------------------
|
| _DisposeControl ($A955): erase, unlink, dispose a control.
| Pascal: procedure DisposeControl(theControl: ControlHandle);
DISPOSECONTROL:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0x8(A7),A3                      | A3 = ControlHandle arg
    BSR.B       NEWCONTROL_CONT_3               | erase + invalidate region
    MOVEA.L     A3,A0                           | A0 = ControlHandle
    MOVEA.L     (A3),A1                         | A1 = deref Control
    MOVEA.L     0x4(A1),A1                      | A1 = ctrl.contrlOwner (window)
    LEA.L       0x8C(A1),A1                     | A1 = &window.controlList head
    BSR.W       DRAWCONTROLS_CONT_2             | unlink A0 from A1's chain
    MOVEQ.L     #0x4,D0                         | CDEF msg #4 = dispose
    BSR.W       NEWCONTROL_FOUND                | dispatch to CDEF
    MOVEA.L     A3,A0                           | A0 = ControlHandle
    _DisposeHandle                              | free the record
    BRA.B       SHOWCONTROL_EXIT                | -> restore A3 + return
| ----------------------------------------------------------
|
| _KillControls ($A956): dispose all controls in a window.
| Pascal: procedure KillControls(theWindow: WindowPtr);
KILLCONTROLS:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0x8(A7),A3                      | A3 = theWindow
KILLCONTROLS_EMPTY:
    MOVE.L      0x8C(A3),D0                     | D0 = window.controlList head
    BEQ.B       SHOWCONTROL_EXIT                | empty -> done
    MOVE.L      D0,-(A7)                        | push first ControlHandle
    _DisposeControl                             | dispose it (unlinks itself)
    BRA.B       KILLCONTROLS_EMPTY              | continue with new head
| ----------------------------------------------------------
|
| _Draw1Control ($A96D): redraw one control unconditionally.
| Pascal: procedure Draw1Control(theControl: ControlHandle);
DRAWONECONTROL:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0x8(A7),A3                      | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | A0 = deref Control
    BRA.B       SHOWCONTROL_CONT                | -> shared draw path
| ----------------------------------------------------------
|
| _ShowControl ($A957): make a control visible (and draw it).
| Pascal: procedure ShowControl(theControl: ControlHandle);
SHOWCONTROL:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0x8(A7),A3                      | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | A0 = deref Control
    TST.B       0x10(A0)                        | already visible?
    BNE.B       SHOWCONTROL_EXIT                | yes -> nothing to do
    ST.B        0x10(A0)                        | contrlVis = true
SHOWCONTROL_CONT:
    MOVEQ.L     #0x0,D1                         | param = 0
    BSR.W       NEWCONTROL_CONT                 | dispatch CDEF draw msg #0
| Common exit for control routines that pushed A3.
| Called by: HIDECONTROL, DISPOSECONTROL, KILLCONTROLS_EMPTY, SHOWCONTROL
SHOWCONTROL_EXIT:
    MOVEA.L     (A7)+,A3                        | restore A3
    MOVE.L      (A7)+,(A7)                      | strip ControlHandle param (RA up)
    RTS                                         | return from SHOWCONTROL/HIDECONTROL
| ----------------------------------------------------------
|
| _HideControl ($A958): make a control invisible.
| Pascal: procedure HideControl(theControl: ControlHandle);
HIDECONTROL:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0x8(A7),A3                      | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | deref Control
    TST.B       0x10(A0)                        | currently visible?
    BEQ.B       SHOWCONTROL_EXIT                | no -> nothing to do
    BSR.W       NEWCONTROL_CONT_3               | erase region + invalidate
    MOVEA.L     (A3),A0                         | re-deref (handle may have moved)
    CLR.B       0x10(A0)                        | contrlVis = false
    BRA.B       SHOWCONTROL_EXIT                | -> exit
| ----------------------------------------------------------
|
| _MoveControl ($A959): move a control to absolute (h,v) in window coords.
| Pascal: procedure MoveControl(theControl: ControlHandle; h, v: INTEGER);
MOVECONTROL:
    MOVEM.L     D3/A3,-(A7)                     | save D3/A3
    MOVEA.L     0x10(A7),A3                     | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | A0 = deref Control
    MOVE.B      0x10(A0),D3                     | D3 = current contrlVis (save state)
    MOVE.L      A3,-(A7)                        | push handle
    _HideControl                                | erase from screen
    MOVEA.L     (A3),A0                         | re-deref
    ADDQ.W      #0x8,A0                         | A0 = &contrlRect
    MOVE.W      0xC(A7),D0                      | D0 = new h
    SUB.W       (A0),D0                         | D0 = dh = new.h - rect.left
    MOVE.W      0xE(A7),D1                      | D1 = new v
    SUB.W       0x2(A0),D1                      | D1 = dv = new.v - rect.top
    MOVE.L      A0,-(A7)                        | push &rect
    MOVE.W      D1,-(A7)                        | push dv
    MOVE.W      D0,-(A7)                        | push dh
    _OffsetRect                                 | offset contrlRect in place
| Common tail: re-show if was visible, clean up frame.
MOVECONTROL_OK:
    TST.B       D3                              | was visible?
    BEQ.B       MOVECONTROL_SKIP                | no -> done
    MOVE.L      A3,-(A7)                        | push handle
    _ShowControl                                | re-draw at new position
MOVECONTROL_SKIP:
    MOVEM.L     (A7)+,D3/A3                     | restore regs
MOVECONTROL_CONT:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x8,A7                         | strip params (8 bytes)
    JMP         (A0)                            | tail-call return from MOVECONTROL_CONT via A0
| ----------------------------------------------------------
|
| _GetCRefCon ($A95A): get control's refCon longword.
| Pascal: function GetCRefCon(theControl: ControlHandle): LongInt;
GETCREFCON:
    MOVEQ.L     #0x24,D1                        | offset 0x24 = contrlRfCon
| Shared get-longword body: stack [ret(4), result(4), handle(4)]
GETCREFCON_CONT:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    MOVEA.L     (A7)+,A1                        | A1 = ControlHandle
    MOVEA.L     (A1),A1                         | deref
    MOVE.L      0x0(A1,D1.W),(A7)               | result = ctrl.field
    JMP         (A0)                            | tail-call return from GETCREFCON_CONT via A0
| _SetCRefCon ($A95B): set control's refCon longword.
| Pascal: procedure SetCRefCon(theControl: ControlHandle; data: LongInt);
SETCREFCON:
    MOVEQ.L     #0x24,D1                        | offset 0x24 = contrlRfCon
| Shared set-longword body: stack [ret(4), value(4), handle(4)]
SETCREFCON_CONT:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    MOVE.L      (A7)+,D0                        | D0 = new value
    MOVEA.L     (A7)+,A1                        | A1 = ControlHandle
    MOVEA.L     (A1),A1                         | deref
    MOVE.L      D0,0x0(A1,D1.W)                 | ctrl.field = D0
    JMP         (A0)                            | tail-call return from SETCREFCON_CONT via A0
| _GetCtlAction ($A96A): get control's action proc ptr.
GETCTLACTION:
    MOVEQ.L     #0x20,D1                        | offset 0x20 = contrlAction
    BRA.B       GETCREFCON_CONT                 | -> shared get
| _SetCtlAction ($A96B): set control's action proc ptr.
SETCTLACTION:
    MOVEQ.L     #0x20,D1                        | offset 0x20 = contrlAction
    BRA.B       SETCREFCON_CONT                 | -> shared set
| ----------------------------------------------------------
|
| _SizeControl ($A95C): resize a control to (width, height).
| Pascal: procedure SizeControl(theControl: ControlHandle; w, h: INTEGER);
SIZECONTROL:
    MOVEM.L     D3/A3,-(A7)                     | save D3/A3
    MOVEA.L     0x10(A7),A3                     | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | A0 = deref Control
    MOVE.B      0x10(A0),D3                     | D3 = current contrlVis
    MOVE.L      A3,-(A7)                        | push handle
    _HideControl                                | erase from screen
    MOVE.W      0xC(A7),D0                      | D0 = w arg
    MOVE.W      0xE(A7),D1                      | D1 = h arg
    MOVEA.L     (A3),A0                         | re-deref
    ADDQ.W      #0x8,A0                         | A0 = &contrlRect.left
    ADD.W       (A0)+,D0                        | D0 = right = left + w
    ADD.W       (A0)+,D1                        | D1 = bottom = top + h
    MOVE.W      D0,(A0)+                        | rect.right = D0
    MOVE.W      D1,(A0)+                        | rect.bottom = D1
    BRA.B       MOVECONTROL_OK                  | -> show + return
| ----------------------------------------------------------
|
| _HiliteControl ($A95D): set highlight state for a control part.
| Pascal: procedure HiliteControl(theControl: ControlHandle; hiliteState: INTEGER);
HILITECONTROL:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0xA(A7),A3                      | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | A0 = deref Control
    MOVEQ.L     #0x0,D1                         | clear D1 high
    MOVEQ.L     #0x0,D0                         | clear D0 high
    MOVE.B      0x9(A7),D1                      | D1 = hiliteState arg (low byte)
    MOVE.B      0x11(A0),D0                     | D0 = current contrlHilite
    CMP.B       D0,D1                           | same as current?
    BEQ.B       HILITECONTROL_OK                | yes -> nothing to do
    MOVE.B      D1,0x11(A0)                     | contrlHilite = new state
    BNE.B       HILITECONTROL_DRAW_NEW          | new != 0 -> draw new hilite
    MOVE.W      D0,D1                           | new = 0 -> repaint old part to clear
HILITECONTROL_DRAW_NEW:
    BSR.W       NEWCONTROL_CONT                 | dispatch CDEF draw with D1 = part
HILITECONTROL_OK:
    MOVEA.L     (A7)+,A3                        | restore A3
| Common exit for 6-byte param routines.
HILITECONTROL_CONT_2:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x6,A7                         | strip 6 bytes of params
    JMP         (A0)                            | tail-call return from HILITECONTROL_CONT_2 via A0
| ----------------------------------------------------------
|
| _GetCTitle ($A95E): copy a control's title into a Pascal-string buffer.
| Pascal: procedure GetCTitle(theControl: ControlHandle; var title: Str255);
GETCTITLE:
    MOVE.L      (A7)+,D0                        | D0 = return addr
    MOVEA.L     (A7)+,A1                        | A1 = VAR title (dest)
    MOVEA.L     (A7)+,A0                        | A0 = ControlHandle
    MOVE.L      D0,-(A7)                        | re-push return addr
    MOVEA.L     (A0),A0                         | deref Control
    LEA.L       0x28(A0),A0                     | A0 = ctrl.contrlTitle (pascal str)
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (A0),D0                         | D0 = title length
    ADDQ.L      #0x1,D0                         | + length byte itself
    _BlockMove                                  | copy len+1 bytes
    RTS                                         | return from GETCTITLE
| ----------------------------------------------------------
|
| _SetCTitle ($A95F): replace a control's title (resizes handle).
| Pascal: procedure SetCTitle(theControl: ControlHandle; title: Str255);
SETCTITLE:
    MOVEM.L     D3/A3-A4,-(A7)                  | save regs
    MOVEA.L     0x14(A7),A3                     | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | A0 = deref Control
    MOVE.B      0x10(A0),D3                     | D3 = current contrlVis (save state)
    MOVE.L      A3,-(A7)                        | push handle
    _HideControl                                | erase from screen
    MOVEA.L     0x10(A7),A4                     | A4 = new title ptr
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (A4),D0                         | D0 = new length
    MOVE.L      D0,-(A7)                        | save length on stack
    ADDI.W      #0x29,D0                        | total = 41 + new title length
    MOVEA.L     A3,A0                           | A0 = handle
    _SetHandleSize                              | resize control record
    MOVE.L      (A7)+,D0                        | D0 = title length
    MOVEA.L     A4,A0                           | A0 = src (new title)
    MOVEA.L     (A3),A1                         | A1 = deref Control
    LEA.L       0x28(A1),A1                     | A1 = contrlTitle slot
    ADDQ.W      #0x1,D0                         | + length byte
    _BlockMove                                  | copy title bytes
    TST.B       D3                              | was visible?
    BEQ.B       SETCTITLE_SKIP                  | no -> done
    MOVE.L      A3,-(A7)                        | push handle
    _ShowControl                                | re-draw with new title
SETCTITLE_SKIP:
    MOVEM.L     (A7)+,D3/A3-A4                  | restore regs
    BRA.W       MOVECONTROL_CONT                | -> strip 8 bytes + return
| ----------------------------------------------------------
|
| _GetCtlValue ($A960): get current value of a control.
| Pascal: function GetCtlValue(theControl: ControlHandle): INTEGER;
GETCTLVALUE:
    MOVEQ.L     #0x12,D0                        | offset 0x12 = contrlValue
| Generic get-word-field body. Stack: [ret(4), result(2), pad(2), handle(4)]
GETCTLVALUE_CONT:
    MOVEA.L     (A7)+,A1                        | A1 = return addr
    MOVEA.L     (A7)+,A0                        | A0 = ControlHandle
    MOVEA.L     (A0),A0                         | deref
    MOVE.W      0x0(A0,D0.W),(A7)               | result = ctrl.field
    JMP         (A1)                            | tail-call return from GETCTLVALUE_CONT via A1
| _GetCtlMin ($A961): get minimum of a control.
GETCTLMIN:
    MOVEQ.L     #0x14,D0                        | offset 0x14 = contrlMin
    BRA.B       GETCTLVALUE_CONT                | -> shared get
| _GetCtlMax ($A962): get maximum of a control.
GETCTLMAX:
    MOVEQ.L     #0x16,D0                        | offset 0x16 = contrlMax
    BRA.B       GETCTLVALUE_CONT                | -> shared get
| ----------------------------------------------------------
|
| _SetCtlValue ($A963): set value, clamp to [Min, Max], redraw indicator.
| Pascal: procedure SetCtlValue(theControl: ControlHandle; theValue: INTEGER);
SETCTLVALUE:
    MOVEQ.L     #0x12,D0                        | offset 0x12 = contrlValue
| Generic set-word-field with clamping and CDEF redraw.
SETCTLVALUE_CONT:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0xA(A7),A3                      | A3 = ControlHandle
    MOVE.W      0x8(A7),D1                      | D1 = new value
    MOVEA.L     (A3),A0                         | A0 = deref Control
    CMP.W       0x0(A0,D0.W),D1                 | already this value?
    BEQ.B       SETCTLVALUE_OK                  | yes -> nothing to do
    MOVE.W      D1,0x0(A0,D0.W)                 | store new field value
    MOVE.W      0x12(A0),D1                     | re-read contrlValue
    CMP.W       0x14(A0),D1                     | < contrlMin?
    BGE.B       SETCTLVALUE_NO                  | no -> skip lower clamp
    MOVE.W      0x14(A0),D1                     | clamp to Min
SETCTLVALUE_NO:
    CMP.W       0x16(A0),D1                     | > contrlMax?
    BLE.B       SETCTLVALUE_NO_2                | no -> use as-is
    MOVE.W      0x16(A0),D1                     | clamp to Max
SETCTLVALUE_NO_2:
    MOVE.W      D1,0x12(A0)                     | store clamped value
    MOVE.W      #0x81,D1                        | CDEF param = 0x81 (redraw indicator only)
    BSR.W       NEWCONTROL_CONT                 | dispatch CDEF draw
SETCTLVALUE_OK:
    MOVEA.L     (A7)+,A3                        | restore A3
    BRA.W       HILITECONTROL_CONT_2            | -> strip 6 bytes + return
| _SetCtlMin ($A964): set minimum (with clamp on value).
SETCTLMIN:
    MOVEQ.L     #0x14,D0                        | offset 0x14 = contrlMin
    BRA.B       SETCTLVALUE_CONT                | -> shared set
| _SetCtlMax ($A965): set maximum (with clamp on value).
SETCTLMAX:
    MOVEQ.L     #0x16,D0                        | offset 0x16 = contrlMax
    BRA.B       SETCTLVALUE_CONT                | -> shared set
| ----------------------------------------------------------
|
| _TestControl ($A966): which part of a control is the point in?
| Pascal: function TestControl(theControl: ControlHandle; thePt: Point): INTEGER;
| Returns 0 if invisible, fully disabled (hilite=$FF), or pt outside any part.
TESTCONTROL:
    MOVE.L      A3,-(A7)                        | save A3
    MOVEA.L     0xC(A7),A3                      | A3 = ControlHandle
    MOVEA.L     (A3),A0                         | A0 = deref Control
    CLR.W       0x10(A7)                        | result = 0 (default)
    MOVE.B      0x10(A0),D1                     | D1 = contrlVis
    BEQ.B       TESTCONTROL_FOUND               | invisible -> return 0
    CMPI.B      #0xFF,0x11(A0)                  | fully disabled?
    BEQ.B       TESTCONTROL_FOUND               | yes -> return 0
    MOVE.L      0x8(A7),D1                      | D1 = test point (long)
    MOVEQ.L     #0x1,D0                         | CDEF msg #1 = test
    BSR.W       NEWCONTROL_FOUND                | dispatch -> D0 = part code
    MOVE.W      D0,0x10(A7)                     | result = part code
TESTCONTROL_FOUND:
    MOVEA.L     (A7)+,A3                        | restore A3
    BRA.W       MOVECONTROL_CONT                | -> strip 8 bytes + return
| ----------------------------------------------------------
|
| _DragControl ($A967): drag a control by its outline (XOR rect).
| Pascal: procedure DragControl(theControl: ControlHandle; startPt: Point;
|   limitRect: Rect; slopRect: Rect; axis: INTEGER);
| Sets DragFlag = 0 to mean "outline drag" (versus thumb drag below).
DRAGCONTROL:
    CLR.W       (DragFlag).W                    | DragFlag = 0 (outline mode)
| DRAGCONTROL_CONT (entry from TrackControl thumb drag): DragFlag may be set
| to 1 by caller for indicator-region tracking instead of outline.
DRAGCONTROL_CONT:
    LINK        A6,#0x0                         | set up frame
    MOVEM.L     D3-D4/A3-A4,-(A7)               | save regs
    MOVEM.L     0xE(A6),D3-D4/A3                | D3 = startPt, D4 = axis, A3 = ControlHandle
    BSR.W       DRAGCONTROL_CONT_2              | save port, switch to control's port
    MOVE.W      (DragFlag).W,D1                 | D1 = drag mode flag
    MOVEQ.L     #0x7,D0                         | CDEF msg #7 = drag
    BSR.W       NEWCONTROL_FOUND                | give CDEF first crack at the drag
    TST.W       D0                              | CDEF handled it?
    BNE.B       DRAGCONTROL_EXIT                | yes -> exit (CDEF did the work)
    JSR         GETNEWRGN(PC)                   | A0 = new region handle (on stack)
    TST.W       (DragFlag).W                    | thumb mode?
    SNE.B       (A7)                            | set low byte of new rgn = mode flag
    MOVE.L      (A7),D1                         | D1 = region handle (carrying flag)
    MOVEQ.L     #0x2,D0                         | CDEF msg #2 = calcCRgns
    BSR.W       NEWCONTROL_FOUND                | fill region with control shape
    CLR.B       (A7)                            | clear flag byte (now real handle)
    MOVEA.L     (A7)+,A4                        | A4 = region handle
    MOVEM.L     D3-D4/A4-A5,-(A7)               | _DragTheRgn args: startPt, axis, rgn, A5=NIL
    MOVE.L      0xA(A6),-(A7)                   | push limitRect
    MOVE.W      0x8(A6),-(A7)                   | push axis
    MOVE.L      (CurDragAction).W,-(A7)         | push action proc
    TST.W       (DragFlag).W                    | thumb mode?
    BNE.B       DRAGCONTROL_OK                  | yes -> use action
    CLR.L       (A7)                            | no -> NIL action
DRAGCONTROL_OK:
    _DragTheRgn                                 | track outline; D0 = final delta
    MOVE.L      A4,-(A7)                        | push region handle
    _DisposeRgn                                 | free temp region
    MOVE.L      (A7)+,D3                        | D3 = drag delta longword
    BEQ.B       DRAGCONTROL_DONE                | no movement -> just exit
    CMPI.W      #0x8000,D3                      | high word = -32768 (cancel sentinel)?
    BNE.B       DRAGCONTROL_NO                  | no -> apply move
DRAGCONTROL_EXIT:
    MOVEQ.L     #0x0,D3                         | cancelled -> D3 = 0
    BRA.B       DRAGCONTROL_DONE                | -> exit
| ----------------------------------------------------------
|
| DRAGCONTROL_NO: apply drag movement to control position
|
| Apply the drag delta to the control's bounding rectangle.
DRAGCONTROL_NO:
    TST.W       (DragFlag).W                    | thumb mode?
    BNE.B       DRAGCONTROL_DONE                | yes -> CDEF action handled it
    MOVEA.L     (A3),A0                         | A0 = deref Control
    MOVE.L      0x8(A0),D0                      | D0 = (top, left) longword
    ADD.W       D3,D0                           | += dh.l (low word)
    SWAP.W      D0                              | swap to top half
    SWAP.W      D3                              | swap to dv high word
    ADD.W       D3,D0                           | += dv (now in low half of D0)
    SWAP.W      D0                              | restore D0 = (top', left')
    MOVE.L      A3,-(A7)                        | push handle
    MOVE.L      D0,-(A7)                        | push (top', left')
    _MoveControl                                | move to absolute position
| Common drag exit: restore port, return delta in D1.
DRAGCONTROL_DONE:
    _SetPort                                    | restore caller's port
    MOVE.L      D3,D1                           | D1 = delta long (zero on cancel)
    MOVEM.L     (A7)+,D3-D4/A3-A4               | restore regs
    UNLK        A6                              | tear down frame
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDA.W      #0x12,A7                        | strip 18 bytes of params
    JMP         (A0)                            | tail-call return from DRAGCONTROL_DONE via A0
| ----------------------------------------------------------
|
| Save current port, switch to control's owner window port.
| Leaves saved port on stack so caller can _SetPort to restore later.
| Reserves a 4-byte slot on the stack just below the return address.
| Called during boot.
DRAGCONTROL_CONT_2:
    MOVE.L      (A7)+,D2                        | D2 = return addr
    SUBQ.W      #0x4,A7                         | reserve 4 bytes for saved port
    MOVE.L      D2,-(A7)                        | re-push return addr (now above saved-port slot)
    MOVEM.L     D0-D1,-(A7)                     | save scratch regs
    PEA.L       0xC(A7)                         | push &savedPortSlot
    _GetPort                                    | save current port to that slot
    MOVEA.L     (A3),A0                         | A0 = deref Control
    MOVE.L      0x4(A0),-(A7)                   | push contrlOwner (window)
    _SetPort                                    | switch to that port
    MOVEM.L     (A7)+,D0-D1                     | restore scratch regs
    RTS                                         | return from DRAGCONTROL_CONT_2
| ----------------------------------------------------------
|
| _TrackControl ($A968): track mouse in a control until button is released.
| Pascal: function TrackControl(theControl: ControlHandle; startPt: Point;
|   actionProc: ProcPtr): INTEGER;
| Returns the part code where the mouse was when released (0 if outside).
| Implements three modes:
|   1. Indicator/thumb (part code with high bit set, e.g. inThumb=129):
|      treats it as a thumb drag, calls DRAGCONTROL_CONT.
|   2. Auto-track (actionProc = -1): repeatedly calls CDEF msg #8 (autoTrack)
|      while mouse is in original part.
|   3. Custom action (actionProc != 0 and != -1): calls user proc each iter.
| Locals: -8(A6)..-1(A6) = current mouse pt + ?, -0x14..-0xD = thumb state,
|   -0x1C..-0x15 = thumb startPt + axis cache.
TRACKCONTROL:
    LINK        A6,#-0x1C                       | reserve 28 bytes of locals
    MOVEM.L     D3/A3,-(A7)                     | save regs
    MOVEA.L     0x10(A6),A3                     | A3 = ControlHandle
    MOVE.L      0xC(A6),-0x8(A6)                | save startPt as initial mouse pt
    BSR.B       DRAGCONTROL_CONT_2              | save port, switch to control's port
    MOVEQ.L     #0x0,D3                         | D3 = current part code (0 = none)
| Tracking loop: test current point, hilite/unhilite, run action, get next point.
TRACKCONTROL_LOOP:
    MOVE.L      A3,-(A7)                        | _TestControl arg: handle
    CLR.W       -(A7)                           | _TestControl result slot
    MOVE.L      A3,-(A7)                        | _TestControl arg: handle (again, for stack)
    MOVE.L      -0x8(A6),-(A7)                  | _TestControl arg: pt
    _TestControl                                | -> part code in result slot
    TST.W       D3                              | first iteration?
    BNE.B       TRACKCONTROL_NO                 | no -> just check if same part
    MOVE.W      (A7),D3                         | D3 = part code
    TST.B       D3                              | high bit set?
    BPL.B       TRACKCONTROL_NO_2               | no -> normal part: hilite + track
    BRA.B       TRACKCONTROL_OK                 | yes -> indicator drag (thumb)
| Subsequent iterations: if part changed, "leave" current (unhilite).
| Called during boot.
TRACKCONTROL_NO:
    CMP.W       (A7),D3                         | mouse still in original part?
    BEQ.B       TRACKCONTROL_NO_2               | yes -> hilite as before
    CLR.W       (A7)                            | no -> hilite = 0 (unhilite)
| Hilite the part (or unhilite via 0), then run action proc / auto-track.
TRACKCONTROL_NO_2:
    MOVE.W      (A7),0x14(A6)                   | save part code in local
    _HiliteControl                              | hilite or unhilite
    MOVE.L      0x8(A6),D0                      | D0 = actionProc arg
    BEQ.B       TRACKCONTROL_EMPTY              | nil -> no action
    BTST        #0x0,D0                         | low bit set? (-1 marker)
    BEQ.B       TRACKCONTROL_NO_3               | no -> custom action proc
    MOVEA.L     (A3),A0                         | yes: actionProc = -1 -> use ctrl.contrlAction
    MOVE.L      0x20(A0),D0                     | D0 = ctrl.contrlAction
    BEQ.B       TRACKCONTROL_EMPTY              | nil -> no action
    BTST        #0x0,D0                         | low bit set?
    BEQ.B       TRACKCONTROL_NO_3               | no -> call as user proc
    MOVEQ.L     #0x8,D0                         | bit set: CDEF msg #8 = autoTrack
    MOVE.W      0x14(A6),D1                     | param = part code
    BSR.W       NEWCONTROL_FOUND                | dispatch to CDEF
    BRA.B       TRACKCONTROL_EMPTY              | -> next iter
| Call user's actionProc callback.
TRACKCONTROL_NO_3:
    MOVE.L      A3,-(A7)                        | push handle
    MOVE.W      0x14(A6),-(A7)                  | push part code
    MOVEA.L     D0,A0                           | A0 = actionProc
    JSR         (A0)                            | call user proc
TRACKCONTROL_EMPTY:
    PEA.L       -0x8(A6)                        | push &mousePt local
    _GetMouse                                   | refresh mouse position
    CLR.W       -(A7)                           | _WaitMouseUp result slot
    _WaitMouseUp                                | mouse still down?
    TST.B       (A7)+                           | check
    BNE.B       TRACKCONTROL_LOOP               | yes -> next iteration
    MOVE.L      A3,-(A7)                        | push handle
    CLR.W       -(A7)                           | hilite = 0
    _HiliteControl                              | clear hilite on release
| Common exit: D3 holds the part code returned to caller.
| Called by: FINDCONTROL, TRACKCONTROL_OK_2, TRACKCONTROL_NO_4, FINDCONTROL_SKIP
TRACKCONTROL_EXIT:
    _SetPort                                    | restore caller's port
    MOVEM.L     (A7)+,D3/A3                     | restore regs
    UNLK        A6                              | tear down frame
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDA.W      #0xC,A7                         | strip 12 bytes of params
    JMP         (A0)                            | tail-call return from TRACKCONTROL_EXIT via A0
| ----------------------------------------------------------
|
| Indicator/thumb tracking path: ask CDEF for limit/slop rects via msg #6,
| then call DRAGCONTROL_CONT (with DragFlag = 1) to drag the thumb.
| On success, call CDEF msg #5 (newPos) so it can update value from drag.
TRACKCONTROL_OK:
    MOVE.W      (A7)+,0x14(A6)                  | save part code locally
    ADDQ.W      #0x4,A7                         | discard handle slot
    LEA.L       -0x1C(A6),A0                    | A0 = local thumb-state buffer
    MOVE.L      0xC(A6),(A0)                    | save startPt at -0x1C(A6)
    MOVE.L      A0,D1                           | D1 = ptr to thumb buffer
    MOVEQ.L     #0x6,D0                         | CDEF msg #6 = thumb (fill limit/slop/axis)
    BSR.W       NEWCONTROL_FOUND                | dispatch -> fills buffer
    ST.B        (DragFlag).W                    | DragFlag = -1 (thumb mode)
    MOVE.L      0x8(A6),D0                      | D0 = actionProc arg
    BTST        #0x0,D0                         | == -1?
    BEQ.B       TRACKCONTROL_OK_2               | no -> use as-is for action
    MOVEA.L     (A3),A0                         | yes: use ctrl.contrlAction
    MOVE.L      0x20(A0),D0                     | D0 = ctrl.contrlAction
    BTST        #0x0,D0                         | == -1?
    BEQ.B       TRACKCONTROL_OK_2               | no -> use as action
    MOVEQ.L     #0x0,D0                         | yes -> action = nil
TRACKCONTROL_OK_2:
    MOVE.L      D0,(CurDragAction).W            | install action proc (or nil)
    MOVE.L      A3,-(A7)                        | DragControl arg: handle
    MOVE.L      0xC(A6),-(A7)                   | DragControl arg: startPt
    LEA.L       -0x1C(A6),A0                    | A0 = thumb buffer
    MOVE.L      A0,-(A7)                        | DragControl arg: limitRect
    PEA.L       0x8(A0)                         | DragControl arg: slopRect (offset +8)
    MOVE.W      0x10(A0),-(A7)                  | DragControl arg: axis (offset +0x10)
    BSR.W       DRAGCONTROL_CONT                | drag thumb; D1 = delta long (0 if cancel)
    TST.L       D1                              | cancelled?
    BEQ.B       TRACKCONTROL_NO_4               | yes -> exit with part = 0
    MOVEQ.L     #0x5,D0                         | CDEF msg #5 = thumbPos (commit value)
    BSR.W       NEWCONTROL_FOUND                | dispatch to CDEF
    BRA.B       TRACKCONTROL_EXIT               | -> common exit (D3 = part code)
| ----------------------------------------------------------
|
| TRACKCONTROL_NO_4: thumb drag cancelled -- return part code 0
|
| Cancelled-thumb path: return part code 0 to caller.
TRACKCONTROL_NO_4:
    CLR.W       0x14(A6)                        | result part = 0
    BRA.B       TRACKCONTROL_EXIT               | -> exit
| ----------------------------------------------------------
|
| _UpdtControl ($A953): redraw all controls within an updateRgn.
| Pascal: procedure UpdtControl(theWindow: WindowPtr; updateRgn: RgnHandle);
| Stack: 8(A6) = updateRgn (long), 0xC(A6) = theWindow (long)
UPDTCONTROLS:
    LINK        A6,#-0x18                       | reserve PenState buffer
    MOVEM.L     D7/A3,-(A7)                     | save regs
    MOVEA.L     0xC(A6),A3                      | A3 = theWindow
    MOVEQ.L     #0x8,D7                         | D7 = 8 -> "test against rgn" path + 8-byte strip
    BRA.B       DRAWCONTROLS_LOOP               | -> shared loop
| ----------------------------------------------------------
|
| _DrawControls ($A969): redraw all visible controls in a window.
| Pascal: procedure DrawControls(theWindow: WindowPtr);
DRAWCONTROLS:
    LINK        A6,#-0x18                       | reserve PenState buffer
    MOVEM.L     D7/A3,-(A7)                     | save regs
    MOVEA.L     0x8(A6),A3                      | A3 = theWindow
    MOVEQ.L     #0x4,D7                         | D7 = 4 -> "draw all" path + 4-byte strip
DRAWCONTROLS_LOOP:
    SUBQ.W      #0x4,A7                         | reserve _GetPort result slot
    MOVE.L      A7,-(A7)                        | push &slot
    _GetPort                                    | save current port
    MOVE.L      A3,-(A7)                        | push window port
    _SetPort                                    | switch to it
    PEA.L       -0x18(A6)                       | &PenState local
    MOVE.L      (A7),-(A7)                      | duplicate ptr for SetPenState later
    _GetPenState                                | save pen
    _PenNormal                                  | pen = (1,1) black srcCopy (default)
    MOVE.L      0x8C(A3),D0                     | D0 = window.controlList head
    BEQ.B       DRAWCONTROLS_DONE               | empty -> skip
| Walk the control list, drawing each.
DRAWCONTROLS_CONT:
    MOVEA.L     D0,A3                           | A3 = current ControlHandle
    CMPI.W      #0x8,D7                         | UpdtControl mode?
    BNE.B       DRAWCONTROLS_NO                 | no -> always draw
    SUBQ.W      #0x2,A7                         | _RectInRgn result slot
    MOVEA.L     (A3),A0                         | A0 = deref Control
    PEA.L       0x8(A0)                         | &contrlRect
    MOVE.L      0x8(A6),-(A7)                   | push updateRgn
    _RectInRgn                                  | rect intersects rgn?
    TST.B       (A7)+                           | check
    BEQ.B       DRAWCONTROLS_SKIP               | no -> skip this control
DRAWCONTROLS_NO:
    MOVEQ.L     #0x0,D1                         | param = 0
    BSR.W       NEWCONTROL_CONT                 | dispatch CDEF draw msg #0
DRAWCONTROLS_SKIP:
    MOVEA.L     (A3),A0                         | A0 = deref current
    MOVE.L      (A0),D0                         | D0 = ctrl.nextControl
    BNE.B       DRAWCONTROLS_CONT               | next -> continue
DRAWCONTROLS_DONE:
    _SetPenState                                | restore pen
    _SetPort                                    | restore caller's port
    MOVE.L      D7,D0                           | D0 = param-strip count (4 or 8)
    MOVEM.L     (A7)+,D7/A3                     | restore regs
    UNLK        A6                              | tear down frame
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDA.L      D0,A7                           | strip params (4 or 8 bytes)
    JMP         (A0)                            | tail-call return from DRAWCONTROLS_DONE via A0
| ----------------------------------------------------------
|
| Unlink handle A0 from a singly-linked handle list (next-handle at offset 0).
| In:  A0 = handle to unlink, A1 = ptr to head-handle slot
| Out: D0 = 0 if found and unlinked, D0 = -1 if not found
| Called during boot.
DRAWCONTROLS_CONT_2:
    MOVEM.L     D1/A2-A3,-(A7)                  | save scratch regs
    MOVEQ.L     #-0x1,D0                        | result = -1 (not found)
    TST.L       (A1)                            | empty list?
    BEQ.B       DRAWCONTROLS_FOUND              | yes -> done
    MOVEA.L     (A1),A2                         | A2 = first handle
    MOVEA.L     A1,A3                           | A3 = &previous link slot
    BRA.B       DRAWCONTROLS_CONT_3             | -> compare
| Advance to next node.
DRAWCONTROLS_NEXT:
    MOVEA.L     (A2),A3                         | A3 = &(prev.next slot)
    MOVEA.L     (A3),A2                         | A2 = next handle
    MOVE.L      A2,D1                           | end of list?
    BEQ.B       DRAWCONTROLS_FOUND              | yes -> not found
DRAWCONTROLS_CONT_3:
    CMPA.L      A0,A2                           | this == target?
    BNE.B       DRAWCONTROLS_NEXT               | no -> continue walk
    MOVEA.L     (A2),A2                         | A2 = target.next handle (deref)
    MOVE.L      (A2),(A3)                       | prev.next = target.next
    MOVEQ.L     #0x0,D0                         | result = 0 (found)
DRAWCONTROLS_FOUND:
    MOVEM.L     (A7)+,D1/A2-A3                  | restore regs
    RTS                                         | return from DRAWCONTROLS_CONT_2
| ----------------------------------------------------------
|
| _FindControl ($A96C): which control (if any) contains the point?
| Pascal: function FindControl(thePoint: Point; theWindow: WindowPtr;
|         var whichControl: ControlHandle): INTEGER;
| Returns part code (0 if not in any control) and sets *whichControl.
FINDCONTROL:
    LINK        A6,#-0x4                        | reserve 4 bytes of locals
    MOVEM.L     D2-D3/A3,-(A7)                  | save regs
    LEA.L       0x8(A6),A0                      | A0 = first param
    MOVEA.L     (A0)+,A1                        | A1 = VAR whichControl ptr
    CLR.L       (A1)                            | *whichControl = nil (default)
    MOVEA.L     (A0)+,A3                        | A3 = theWindow
    MOVE.L      (A0)+,D3                        | D3 = thePoint (long)
    CLR.W       (A0)                            | result = 0 (default)
    MOVE.L      A7,-(A7)                        | push &savedPort slot
    _GetPort                                    | save port
    MOVE.L      A3,-(A7)                        | push window port
    _SetPort                                    | switch
    TST.B       0x6E(A3)                        | window.visible flag set?
    BEQ.W       TRACKCONTROL_EXIT               | no -> exit (result = 0)
    CLR.W       -(A7)                           | _PtInRect result slot
    MOVE.L      D3,-(A7)                        | push point
    PEA.L       0x10(A3)                        | push &portRect (window content rect)
    _PtInRect                                   | point in window rect?
    TST.B       (A7)+                           | check
    BEQ.W       TRACKCONTROL_EXIT               | no -> exit
    MOVE.L      0x8C(A3),D0                     | D0 = window.controlList head
    BEQ.W       TRACKCONTROL_EXIT               | no controls -> exit
    MOVEA.L     D0,A3                           | A3 = first ControlHandle
| Walk control list, _TestControl each. Last hit wins (deeper controls priority).
FINDCONTROL_NEXT:
    MOVEA.L     (A3),A0                         | A0 = deref Control
    CMPI.B      #0xFF,0x11(A0)                  | fully-disabled control?
    BEQ.B       FINDCONTROL_SKIP                | yes -> skip
    CLR.W       -(A7)                           | _TestControl result slot
    MOVE.L      A3,-(A7)                        | push handle
    MOVE.L      D3,-(A7)                        | push point
    _TestControl                                | -> part code in slot
    MOVE.W      (A7)+,D0                        | D0 = part
    BNE.B       FINDCONTROL_FOUND               | nonzero -> hit
FINDCONTROL_SKIP:
    MOVEA.L     (A3),A0                         | A0 = deref
    MOVEA.L     (A0),A3                         | A3 = next handle
    MOVE.L      A3,D0                           | end of list?
    BNE.B       FINDCONTROL_NEXT                | no -> continue
    BRA.W       TRACKCONTROL_EXIT               | done -> exit
| Found a hit: record result; keep walking (deeper controls override).
| Called during boot.
FINDCONTROL_FOUND:
    MOVEA.L     0x8(A6),A0                      | A0 = VAR whichControl ptr
    MOVE.L      A3,(A0)                         | *whichControl = current
    MOVE.W      D0,0x14(A6)                     | result = part code
    BRA.B       FINDCONTROL_SKIP                | -> continue walk
