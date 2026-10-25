| Window Manager
|
| Apple source: WindowMgr.a (MacSEROM.lst module WMGR). It starts with
| NewString/SetString ($A906/$A907, string handles, used for window
| titles) and the window-list primitives FIND_PREV_WINDOW, INSERT_WINDOW
| and DeleteWindow, followed by the window traps from CalcVis to
| DrawGrowIcon.
|
| WindowRecord (MPW 1.0 Windows.h):
| GrafPort port (108 bytes: portBits, portRect, visRgn, clipRgn, pnLoc, etc.)
| +108: windowKind INTEGER (>0 = DA, <0 = system, 0 = dialog)
| +110: visible BOOLEAN
| +111: hilited BOOLEAN
| +112: goAwayFlag BOOLEAN
| +113: spareFlag BOOLEAN
| +114: strucRgn RgnHandle window structure region (frame)
| +118: contRgn RgnHandle window content region
| +122: updateRgn RgnHandle window update region
| +126: windowDefProc Handle WDEF resource handle
| +130: dataHandle Handle WDEF private data
| +134: titleHandle StringHandle window title
| +138: titleWidth INTEGER
| +140: controlList ControlHandle first control in chain
| +144: nextWindow WindowPeek next window in list
| +148: windowPic PicHandle window picture
| +152: refCon LongInt application reference constant
|
| EventRecord (MPW 1.0 Events.h):
| Offset 0: what INTEGER event code (mouseDown=1, keyDown=3, etc.)
| Offset 2: message LongInt event-specific data
| Offset 6: when LongInt tick count at event time
| Offset 10: where Point mouse location (global)
| Offset 14: modifiers INTEGER modifier key state
|
| The file also carries the tail of the Window Manager internal helpers
| that sit just before DeleteWindow in the ROM:
| INSWIN_AT_END / STRIP_2PARAMS_RTS / DeleteWindow -- in Plus these live
| at the end of toolbox_event.s; classic has them here at the top of
| window_mgr.s because the file split differs between the two trees.
|
| References:
| Inside Macintosh Vol I, Ch 9: The Window Manager (pp 273-328)
| Inside Macintosh Vol I, Ch 13: The Desk Manager (pp 433-448)

| ----------------------------------------------------------
|
| _NewString ($A906)
| Pascal: FUNCTION NewString(theString: Str255): StringHandle
| Allocates a new handle and copies the Pascal string into it.
|
| Called during boot.
NewString:
        BSR.B   GET_STR_PTR_LEN                 | A0 = string ptr, D0 = length+1
        _PtrToHand                              | copy D0 bytes from (A0) into new handle
        MOVE.L  A0,0x8(SP)                      | store returned handle as result
        MOVE.L  (SP)+,(SP)                      | strip one param, keep return address
        RTS                                     | return from NewString

| ----------------------------------------------------------
|
| GET_STR_PTR_LEN - Get Pascal string pointer and byte count
| Returns A0 = ptr to string, D0 = length byte + 1 (total size).
|
| Called during boot.
GET_STR_PTR_LEN:
        MOVE.L  0x8(SP),A0                      | A0 = ptr to Pascal string (caller's param)
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0),D0                         | D0 = length byte of Pascal string
        ADDQ.W  #0x1,D0                         | +1 for length byte itself = total size
        RTS                                     | return from GET_STR_PTR_LEN

| ----------------------------------------------------------
|
| _SetString ($A907)
| Pascal: PROCEDURE SetString(h: StringHandle; theString: Str255)
| Replaces the contents of an existing string handle.
|
SetString:
        MOVE.L  0x8(SP),A1                      | A1 = destination StringHandle
        BSR.B   GET_STR_PTR_LEN                 | A0 = string ptr, D0 = byte count
        _PtrToXHand                             | replace handle contents with string data
        BRA.W   STRIP_2PARAMS_RTS               | clean up stack and return

| ----------------------------------------------------------
|
| FIND_PREV_WINDOW - Find predecessor of a window in the window list
| Walks WindowList (linked via nextWindow at offset 0x90) to find
| the window whose nextWindow field points to D0.
| Returns A0 = predecessor window (or 0 if D0 is the first window),
| A1 = the window matching D0. D0 is preserved.
|
| Called during boot.
FIND_PREV_WINDOW:
        MOVE.L  D0,-(SP)                        | save target window ptr
        MOVE.L  (WindowList).w,A1               | A1 = first window in z-order list
        SUBA.L  A0,A0                           | A0 = nil (no predecessor yet)
FPWIN_LOOP:
        CMPA.L  (SP),A1                         | found the target window?
        BEQ.B   FPWIN_FOUND                     | yes: A0 = predecessor, A1 = target
        MOVE.L  A1,A0                           | A0 = current (becomes predecessor)
        MOVE.L  nextWindow(A0),A1               | A1 = next window in list
        MOVE.L  A1,D0                           | test for end of list
        BNE.B   FPWIN_LOOP                      | more windows: keep searching
FPWIN_FOUND:
        MOVE.L  (SP)+,D0                        | restore D0
        RTS                                     | return with window pointers

| ----------------------------------------------------------
|
| INSERT_WINDOW - Insert window into the window list
| Stack: 0x8(SP) = window to insert, 0x4(SP) = behind window (or 0).
| If behind = 0, inserts at end of list (behind all windows).
| If WindowList is empty, the new window becomes the sole entry.
|
INSERT_WINDOW:
        MOVE.L  0x8(SP),D1                      | D1 = new window ptr
        MOVE.L  D1,A1                           | A1 = new window
        CLR.L   nextWindow(A1)                  | clear nextWindow link (end of chain)
        TST.L   (WindowList).w                  | any windows in list?
        BNE.B   INSWIN_HAS_LIST                 | yes: insert at proper position
        MOVE.L  D1,(WindowList).w               | no: new window is first and only
        BRA.B   STRIP_2PARAMS_RTS               | clean up and return

| Insert window behind a specified window
INSWIN_HAS_LIST:
        MOVE.L  0x4(SP),D0                      | D0 = "behind" window ptr
        BEQ.B   INSWIN_AT_END                   | 0 = insert at end of list
        MOVE.L  D0,A0                           | A0 = behind window
        MOVE.L  nextWindow(A0),nextWindow(A1)   | new->next = behind->next
        MOVE.L  A1,nextWindow(A0)               | behind->next = new window
        BRA.B   STRIP_2PARAMS_RTS               | clean up and return

| ----------------------------------------------------------
|
| Insert window at end of the window list (common tail of INSERT_WINDOW
| and of DeleteWindow): walk FIND_PREV_WINDOW with D0=0 to locate the
| tail of WindowList, then splice the incoming window in.
|
INSWIN_AT_END:
        MOVEQ.L #0x0,D0                         | search for window 0 (end of list)
        BSR.B   FIND_PREV_WINDOW                | A0 = last window in list
        MOVE.L  D1,nextWindow(A0)               | append new window after last
| Called by: SetString, INSERT_WINDOW, INSWIN_HAS_LIST, CALCVBEHIND_EMPTY, PAINTONE_EXIT (and 4 more)
STRIP_2PARAMS_RTS:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | strip two 4-byte parameters
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| DeleteWindow - Remove a window from the window list
| Unlinks the window at 0x4(SP) from the WindowList chain.
| If the target is the first window (no predecessor), patches
| WindowList itself via ChooserBits (which aliases WindowList offset).
|
| Called during boot.
DeleteWindow:
        MOVE.L  0x4(SP),D0                      | D0 = window to remove
        BSR.B   FIND_PREV_WINDOW                | find predecessor: A0 = prev window
        MOVE.L  A0,D1                           | test if predecessor exists
        BNE.B   DELWIN_UNLINK                   | has predecessor: unlink normally
        LEA.L   (ChooserBits).w,A0              | no predecessor: window is first in list
DELWIN_UNLINK:
        MOVE.L  D0,A1                           | A1 = window to remove
        MOVE.L  nextWindow(A1),nextWindow(A0)   | prev->next = target->next (bypass)
        BRA.B   CALCVIS_EXIT_2                  | branch to parameter stripping return

| ----------------------------------------------------------
|
| _CalcVis ($A909)
|
| _CalcVis ($A909): recalculate a window's visRgn
| Pascal: procedure CalcVis(whichWindow: WindowPeek);
| visRgn = intersection of contRgn with desktop minus obscuring windows
CalcVis:
        MOVEM.L D4/A2-A3,-(SP)                  | save regs
        MOVE.L  0x10(SP),D0                     | D0 = window pointer (from stack)
        BEQ.B   CALCVIS_EXIT                    | nil window ->
        MOVE.L  D0,A2                           | A2 = WindowRecord
        MOVE.L  0x18(A2),D4                     | D4 = visRgn handle
        TST.B   wVisible(A2)                    | window visible?
        BNE.B   CALCVIS                         | yes, calculate ->
| invisible window: set visRgn to empty
        MOVE.L  D4,-(SP)                        | push visRgn handle
        _SetEmptyRgn                            | visRgn = empty (invisible window)
CALCVIS_EXIT:
        MOVEM.L (SP)+,D4/A2-A3                  | restore regs
CALCVIS_EXIT_2:
        MOVE.L  (SP)+,(SP)                      | strip Pascal param
CALCVIS_DONE:
        RTS                                     | return from CALCVIS_DONE

| ----------------------------------------------------------
|
| CalcVis: visible window - compute visRgn from content and desktop
|
CALCVIS:
        MOVE.L  (GrayRgn).w,-(SP)               | push desktop region
        MOVE.L  contRgn(A2),-(SP)               | push content region
        MOVE.L  D4,-(SP)                        | push visRgn (dest)
        _SectRgn                                | visRgn = contRgn AND grayRgn
        BSR.B   CALCVIS_CONT                    | subtract obscuring windows above
        MOVE.L  D4,-(SP)                        | push visRgn for local coord offset
        MOVE.L  0x8(A2),-(SP)                   | push portBounds.topLeft (origin)
        _OffsetRgn                              | convert visRgn to local coords
        BRA.B   CALCVIS_EXIT                    | -> restore regs and return

| ----------------------------------------------------------
|
| CALCVIS_CONT - subtract structure regions of all windows above A2 from D4
|
| Walks the window list front-to-back, subtracting each visible
| window's strucRgn from D4 until reaching the target window A2.
| Called during boot (3,700 times in 30s trace).
CALCVIS_CONT:
        MOVE.L  (WindowList).w,A3               | A3 = frontmost window
CALCVIS_LOOP:
        CMPA.L  A2,A3                           | reached target window?
        BEQ.B   CALCVIS_DONE                    | yes, done -> RTS
        TST.B   wVisible(A3)                    | this window visible?
        BEQ.B   CALCVIS_SKIP                    | no, skip subtraction
        MOVE.L  D4,-(SP)                        | push source region
        MOVE.L  structRgn(A3),-(SP)             | push this window's frame region
        MOVE.L  D4,-(SP)                        | push dest (same as source)
        _DiffRgn                                | D4 = D4 minus strucRgn(A3)
CALCVIS_SKIP:
        MOVE.L  nextWindow(A3),A3               | advance to next window behind
        BRA.B   CALCVIS_LOOP                    | loop

| ----------------------------------------------------------
|
| _CalcVBehind ($A90A)
|
| Called during boot.
| _CalcVBehind ($A90A): recalculate visRgn for window and all behind it
| Pascal: procedure CalcVisBehind(window: WindowPeek; clobberedRgn: RgnHandle);
CalcVBehind:
        MOVE.L  A2,-(SP)                        | save A2
        MOVE.L  0xC(SP),D0                      | D0 = starting window
        BEQ.B   CALCVBEHIND_EMPTY               | nil ->
        MOVE.L  D0,A2                           | A2 = window to start from
CALCVBEHIND_NEXT:
        MOVE.L  A2,-(SP)                        | push window for CalcVis
        BSR.B   CalcVis                         | recalculate its visRgn
| walk window list behind this one
CALCVBEHIND_SKIP:
        MOVE.L  nextWindow(A2),A2               | A2 = next window in list
        MOVE.L  A2,D0                           | end of list?
        BEQ.B   CALCVBEHIND_EMPTY               | yes ->
        TST.B   wVisible(A2)                    | visible?
        BEQ.B   CALCVBEHIND_SKIP                | no, skip ->
| optimization: only recalc if clobbered region intersects this window
        SUBQ.W  #0x2,SP                         | space for SectRect result
        MOVE.L  contRgn(A2),A0                  | this window's content region
        MOVE.L  (A0),A0                         | dereference
        PEA.L   0x2(A0)                         | push content bounds
        MOVE.L  0xE(SP),A0                      | clobbered region
        MOVE.L  (A0),A0                         | dereference
        PEA.L   0x2(A0)                         | push clobbered bounds
        PEA.L   (ToolScratch).w                 | push result rect
        _SectRect                               | do they intersect?
        TST.B   (SP)+                           | check result
        BEQ.B   CALCVBEHIND_SKIP                | no intersection, skip this window
        BRA.B   CALCVBEHIND_NEXT                | -> recalculate next visible window

| ----------------------------------------------------------
|
| CALCVBEHIND_EMPTY - CalcVBehind epilogue: restore A2 and strip stack params
|
| Called during boot.
CALCVBEHIND_EMPTY:
        MOVE.L  (SP)+,A2                        | restore A2
        BRA.W   STRIP_2PARAMS_RTS               | -> strip 2 params and return

| ----------------------------------------------------------
|
| _ClipAbove ($A90B)
|
| _ClipAbove ($A90B): set WMgrPort clip to visible area above a window
| Clips to desktop minus all windows above the given one
ClipAbove:
        MOVEM.L D4/A2-A3,-(SP)                  | save regs
        MOVE.L  (WMgrPort).w,A0                 | WMgr port
        MOVE.L  0x1C(A0),D4                     | D4 = WMgr clipRgn handle
        MOVE.L  0x10(SP),A2                     | A2 = window to clip above
        MOVE.L  D4,-(SP)                        | dest = clipRgn
        MOVE.L  (GrayRgn).w,-(SP)               | start with desktop region
        MOVE.L  D4,-(SP)                        | result -> clipRgn
        _SectRgn                                | clip to desktop
        BSR.B   CALCVIS_CONT                    | subtract all windows above A2
        MOVEM.L (SP)+,D4/A2-A3                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from ClipAbove

| ----------------------------------------------------------
|
| _PaintOne ($A90C)
| stack: window, clobberedRgn -> (repaints)
|
| _PaintOne ($A90C): repaint one window's frame and add to updateRgn
| Pascal: procedure PaintOne(window: WindowPeek; clobberedRgn: RgnHandle);
| If window=nil, paints desktop pattern instead
PaintOne:
        MOVEM.L D3-D4/A2-A3,-(SP)               | save regs
        MOVE.L  0x18(SP),A2                     | A2 = window (or nil for desktop)
        BSR.B   PAINTONE_CONT                   | clip to clobbered AND visible area
        MOVE.L  A2,D0                           | nil window?
        BNE.B   PAINTONE_NO                     | no, paint window frame ->
| nil window: paint desktop
        MOVE.L  0x14(SP),-(SP)                  | push clobberedRgn
        _SetClip                                | clip to clobbered area
        BSR.W   PAINTONE_CONT_2                 | paint desktop pattern
PAINTONE_EXIT:
        MOVEM.L (SP)+,D3-D4/A2-A3               | restore regs
        BRA.W   STRIP_2PARAMS_RTS               | -> strip params

| ----------------------------------------------------------
|
| PAINTONE_NO - PaintOne: repaint a visible window's frame and content
|
| Called during boot.
PAINTONE_NO:
        TST.B   wVisible(A2)                    | window visible?
        BEQ.B   PAINTONE_EXIT                   | no, nothing to paint ->
        MOVE.L  0x14(SP),-(SP)                  | push clobberedRgn
        MOVE.L  structRgn(A2),-(SP)             | push window's structure region
        MOVE.L  D3,-(SP)                        | push temp region (dest)
        _SectRgn                                | temp = clobbered AND strucRgn
        BSR.B   PAINTONE_SKIP                   | if temp empty, skip painting
        MOVE.L  A2,-(SP)                        | push window for ClipAbove
        BSR.B   ClipAbove                       | clip WMgr port above this window
        BSR.B   PAINTONE_SKIP                   | if clip empty, skip painting
        MOVE.L  A2,A3                           | A3 = window (for WDEF call)
        BSR.W   MOVEWINDOW_CONT_2               | send wDraw to WDEF (draw frame)
        BSR.W   PAINTBEHIND_EMPTY               | allocate temp region
        MOVE.L  (SP)+,A3                        | A3 = new temp region handle
        MOVE.L  contRgn(A2),-(SP)               | push content region
        MOVE.L  D3,-(SP)                        | push clobbered area
        MOVE.L  A3,-(SP)                        | push dest
        _SectRgn                                | A3 = clobbered AND contRgn
        TST.B   (PaintWhite).w                  | should we erase content?
        BEQ.B   PAINTONE_NO_2                   | no ->
        MOVE.L  A3,-(SP)                        | push intersection region
        _EraseRgn                               | erase clobbered content area
PAINTONE_NO_2:
        TST.B   (SaveUpdate).w                  | should we save update region?
        BEQ.B   PAINTONE_NO_3                   | no ->
        MOVE.L  updateRgn(A2),-(SP)             | push existing updateRgn
        MOVE.L  A3,-(SP)                        | push clobbered content area
        MOVE.L  updateRgn(A2),-(SP)             | push dest (updateRgn)
        _UnionRgn                               | updateRgn |= clobbered content
PAINTONE_NO_3:
        MOVE.L  A3,-(SP)                        | push temp region
        _DisposeRgn                             | free temp region
        BRA.B   PAINTONE_EXIT                   | -> restore regs and return

| ----------------------------------------------------------
|
| PAINTONE_CONT - save current port, switch to WMgr, get clipRgn in D3
|
| Called during boot.
PAINTONE_CONT:
        BSR.W   GetSetWPort                     | save current port, set WMgr port
        MOVE.L  (WMgrPort).w,A3                 | A3 = WMgrPort
        MOVE.L  0x1C(A3),D3                     | D3 = WMgr clipRgn handle
        RTS                                     | return from PAINTONE_CONT

| ----------------------------------------------------------
|
| PAINTONE_SKIP - early exit if WMgr clipRgn (D3) is empty
|
| Tests whether D3 region is empty; if so, pops return address
| and jumps to PaintOne epilogue (skipping the rest of the caller).
| Called during boot.
PAINTONE_SKIP:
        SUBQ.W  #0x2,SP                         | space for EmptyRgn result
        MOVE.L  D3,-(SP)                        | push WMgr clipRgn
        _EmptyRgn                               | is it empty?
        TST.B   (SP)+                           | check result
        BNE.B   PAINTONE_SKIP_ERR               | empty -> abort painting
        RTS                                     | not empty, continue caller
PAINTONE_SKIP_ERR:
        ADDQ.W  #0x4,SP                         | discard caller's return address
        BRA.B   PAINTONE_EXIT                   | -> PaintOne epilogue

| ----------------------------------------------------------
|
| PAINTONE_CONT_2 - paint desktop: call DeskHook or fill with DeskPattern
|
| Called during boot.
PAINTONE_CONT_2:
        CLR.L   -(SP)                           | push nil (clip above all windows)
        _ClipAbove                              | clip WMgr port to entire desktop
        MOVE.L  (DeskHook).w,D0                 | app-installed desk hook?
        BEQ.B   PAINTONE_NO_4                   | no hook -> use default pattern
        MOVE.L  D0,A0                           | A0 = hook procedure address
        MOVEQ.L #0x0,D0                         | D0 = 0 (paint message to hook)
        JMP     (A0)                            | tail-call the hook
| ----------------------------------------------------------
|
| PAINTONE_NO_4 - draw default desktop pattern
|
| Called during boot.
PAINTONE_NO_4:
        PEA.L   0x10(A3)                        | push WMgr port rectangle
        PEA.L   (DeskPattern).w                 | push desktop pattern (from PRAM)
        _FillRect                               | fill desktop with pattern
        RTS                                     | return from PAINTONE_NO_4

| ----------------------------------------------------------
|
| _PaintBehind ($A90D)
| stack: startWindow, clobberedRgn -> (repaints behind)
|
| _PaintBehind ($A90D): repaint all windows behind startWindow
| Pascal: procedure PaintBehind(startWindow: WindowPeek; clobberedRgn: RgnHandle);
| First paints exposed desktop, then walks window list repainting each
| Called during boot.
PaintBehind:
        MOVEM.L D3-D4/A2-A3,-(SP)               | save regs
        BSR.B   PAINTONE_CONT                   | switch to WMgr, D3=clipRgn
        MOVE.L  0x14(SP),-(SP)                  | push clobberedRgn
        MOVE.L  D3,-(SP)                        | push WMgr clipRgn (dest)
        _CopyRgn                                | clipRgn = clobberedRgn
        BSR.B   PAINTBEHIND_EMPTY               | allocate temp region
        MOVE.L  (SP)+,D4                        | D4 = temp region handle
        MOVE.L  0x18(SP),A2                     | A2 = startWindow
        MOVE.L  A2,-(SP)                        | push window for ClipAbove
        _ClipAbove                              | clip to area above startWindow
        MOVE.L  D3,-(SP)                        | push clobbered clipRgn
        MOVE.L  D4,-(SP)                        | push dest (temp)
        _CopyRgn                                | temp = clipped clobbered area
        BSR.B   PAINTONE_CONT_2                 | paint exposed desktop
        MOVE.L  D4,-(SP)                        | push temp (desktop painted area)
        MOVE.L  D3,-(SP)                        | push clobberedRgn
        MOVE.L  D4,-(SP)                        | push dest
        _DiffRgn                                | temp = clobbered minus desktop
        PEA.L   0x10(A3)                        | push WMgr port rect
        _ClipRect                               | restore full clip
        MOVE.L  D4,-(SP)                        | push remaining clobbered area
        _EraseRgn                               | erase it
        MOVE.L  D4,-(SP)                        | push temp region
        _DisposeRgn                             | free temp region
        CLR     (PaintWhite).w                  | suppress content erase in PaintOne
| walk window list from startWindow, repainting each visible one
PAINTBEHIND_LOOP:
        MOVE.L  A2,D0                           | end of window list?
        BEQ.B   PAINTBEHIND_OK                  | yes ->
        TST.B   wVisible(A2)                    | window visible?
        BEQ.B   PAINTBEHIND_SKIP                | no, skip ->
        MOVE.L  A2,-(SP)                        | push window
        MOVE.L  0x18(SP),-(SP)                  | push clobberedRgn
        _PaintOne                               | repaint this window's frame
PAINTBEHIND_SKIP:
        MOVE.L  nextWindow(A2),A2               | advance to next window
        BRA.B   PAINTBEHIND_LOOP                | loop

| ----------------------------------------------------------
|
| PAINTBEHIND_OK - PaintBehind epilogue: re-enable content erase
|
| Called during boot.
PAINTBEHIND_OK:
        ST.B    (PaintWhite).w                  | re-enable content erase for PaintOne
        MOVEM.L (SP)+,D3-D4/A2-A3               | restore regs
        BRA.W   STRIP_2PARAMS_RTS               | -> strip 2 params and return

| ----------------------------------------------------------
|
| PAINTBEHIND_EMPTY - allocate new region and push handle on stack
|
| Creates a new empty region. Returns with the handle on the stack
| (below the caller's return address). Uses trick: saves return addr,
| replaces it with region handle, then jumps back.
| Called during boot.
PAINTBEHIND_EMPTY:
        SUBQ.W  #0x4,SP                         | space for NewRgn result
        _NewRgn                                 | allocate empty region
        MOVE.L  0x4(SP),A0                      | A0 = return address (under handle)
        MOVE.L  (SP)+,(SP)                      | move handle down over return addr
        JMP     (A0)                            | return (handle remains on stack)

| ----------------------------------------------------------
|
| _SaveOld ($A90E)
|
| _SaveOld ($A90E): snapshot a window's strucRgn and contRgn before changes
| Pascal: procedure SaveOld(theWindow: WindowPeek);
| Saves copies to OldStructure/OldContent globals for DrawNew comparison
SaveOld:
        MOVEM.L D3-D4/A2,-(SP)                  | save regs
        BSR.B   PAINTBEHIND_EMPTY               | allocate region for old strucRgn
        MOVE.L  (SP)+,D3                        | D3 = old structure region handle
        BSR.B   PAINTBEHIND_EMPTY               | allocate region for old contRgn
        MOVE.L  (SP)+,D4                        | D4 = old content region handle
        MOVE.L  0x10(SP),A2                     | A2 = window
        MOVE.L  structRgn(A2),-(SP)             | push current strucRgn
        MOVE.L  D3,-(SP)                        | push dest
        _CopyRgn                                | D3 = copy of strucRgn
        MOVE.L  contRgn(A2),-(SP)               | push current contRgn
        MOVE.L  D4,-(SP)                        | push dest
        _CopyRgn                                | D4 = copy of contRgn
        MOVEM.L D3-D4,(OldStructure).w          | save both handles to globals
        MOVEM.L (SP)+,D3-D4/A2                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from SaveOld

| ----------------------------------------------------------
|
| _DrawNew ($A90F)
|
| _DrawNew ($A90F): repaint changed areas after window modification
| Pascal: procedure DrawNew(theWindow: WindowPeek; fUpdate: BOOLEAN);
| Compares current regions with SaveOld snapshots via XOR to find changes,
| then repaints affected areas and recalculates visibility
| Called during boot.
DrawNew:
        MOVEM.L D3-D4/A2,-(SP)                  | save regs
        MOVE.L  0x12(SP),A2                     | A2 = window (past saved regs + fUpdate)
        MOVEM.L (OldStructure).w,D3-D4          | D3=old strucRgn, D4=old contRgn
        TST.B   wVisible(A2)                    | window visible?
        BEQ.B   DRAWNEW_SKIP                    | no, skip XOR calculation ->
        MOVE.L  structRgn(A2),-(SP)             | push new strucRgn
        MOVE.L  D3,-(SP)                        | push old strucRgn
        MOVE.L  D3,-(SP)                        | push dest (old strucRgn)
        _XOrRgn                                 | D3 = changed structure area
        MOVE.L  contRgn(A2),-(SP)               | push new contRgn
        MOVE.L  D4,-(SP)                        | push old contRgn
        MOVE.L  D4,-(SP)                        | push dest (old contRgn)
        _XOrRgn                                 | D4 = changed content area
DRAWNEW_SKIP:
        MOVE.L  D4,-(SP)                        | push changed content
        MOVE.L  D3,-(SP)                        | push changed structure
        MOVE.L  D3,-(SP)                        | push dest
        _UnionRgn                               | D3 = all changed areas
        MOVE.B  0x10(SP),(SaveUpdate).w         | set SaveUpdate from fUpdate param
        MOVE.L  A2,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push changed area
        _PaintOne                               | repaint this window's changed area
        ST      (SaveUpdate).w                  | re-enable update saving
        MOVE.L  nextWindow(A2),-(SP)            | push next window in list
        MOVE.L  D3,-(SP)                        | push changed area
        _PaintBehind                            | repaint all windows behind
        MOVE.L  A2,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push changed area
        _CalcVBehind                            | recalculate visRgns behind
        MOVE.L  D3,-(SP)                        | push old structure rgn
        _DisposeRgn                             | free it
        MOVE.L  D4,-(SP)                        | push old content rgn
        _DisposeRgn                             | free it
        MOVEM.L (SP)+,D3-D4/A2                  | restore regs
| DRAWNEW_EXIT - strip 6 bytes of params (window + fUpdate) and return
DRAWNEW_EXIT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip window ptr + boolean param
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| _ShowHide ($A908)
|
| _ShowHide ($A908): set window visibility and update screen
| Pascal: procedure ShowHide(theWindow: WindowPtr; showFlag: BOOLEAN);
| Only acts if visibility is actually changing (XOR test) | jump via A1 | jump via A1
| Called during boot.
ShowHide:
        MOVEM.L D3-D4/A1/A3,-(SP)               | save regs
        MOVE.L  0x16(SP),A3                     | A3 = window
        MOVE.B  0x14(SP),D3                     | D3 = desired visibility
        CMP.B   wVisible(A3),D3                 | test if changing
        BEQ.B   SHOWHIDE_SKIP                   | no change -> skip
        BSR.B   GetSetWPort                     | save port, switch to WMgr
        MOVE.L  A3,-(SP)                        | push window
        _SaveOld                                | snapshot current regions
        MOVE.B  D3,wVisible(A3)                 | set new visibility flag
        BSR.W   MOVEWINDOW_EMPTY                | recalc regions (empty if hiding)
        MOVE.L  A3,-(SP)                        | push window
        ST      -(SP)                           | fUpdate = true
        _DrawNew                                | repaint changed areas
        BSR.B   RestorePort                     | restore original port
SHOWHIDE_SKIP:
        MOVEM.L (SP)+,D3-D4/A1/A3               | restore regs
        BRA.B   DRAWNEW_EXIT                    | -> strip params and return

| ----------------------------------------------------------
|
| GetSetWPort - save current GrafPort in D4, switch to WMgr port
|
| (A5) points to CurrentA5 -> thePort. Saves old port in D4
| and sets thePort to WMgrPort for window manager drawing.
| Called during boot.
GetSetWPort:
        MOVE.L  (A5),A0                         | A0 = ptr to thePort global
        MOVE.L  (A0),D4                         | D4 = save current port
        MOVE.L  (WMgrPort).w,(A0)               | thePort = WMgrPort
        RTS                                     | return from GetSetWPort

| ----------------------------------------------------------
|
| RestorePort - restore the port saved by GetSetWPort
|
| Called during boot.
RestorePort:
        MOVE.L  D4,-(SP)                        | push saved port from D4
        _SetPort                                | restore it as current port
        RTS                                     | return from RestorePort

| ----------------------------------------------------------
|
| _GetWMgrPort ($A910)
|
| _GetWMgrPort ($A910): return pointer to Window Manager's GrafPort
| Pascal: procedure GetWMgrPort(VAR wPort: GrafPtr);
| Called during boot.
GetWMgrPort:
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = VAR wPort pointer
        MOVE.L  (WMgrPort).w,(A0)               | store WMgrPort into caller's var
        JMP     (A1)                            | return

| ----------------------------------------------------------
|
| _CheckUpDate ($A911): find a window that needs updating (for GetNextEvent)
| Pascal: FUNCTION CheckUpdate(VAR theEvent: EventRecord): BOOLEAN;
| Scans the window list front to back for a visible window with a
| non-empty updateRgn. A window with a windowPic is redrawn in place
| (clipRgn := portRect, BeginUpdate, DrawPicture, EndUpdate, old clip
| restored) and skipped; for the first other one theEvent.what :=
| updateEvt, message := window and the result is TRUE (CHECKUPDATE_NO).
| The current port is saved and restored.
|
CheckUpdate:
        LINK    A6,#-0x8                        | local vars
        MOVE.L  A3,-(SP)                        | save A3
        CLR     0xC(A6)                         | result = false initially
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  SP,-(SP)                        | push pointer to local var
        _GetPort                                | save current port
| scan window list for pending updates
        MOVE.L  (WindowList).w,D0               | start at front window
        BEQ.B   CHECKUPDATE_EXIT                | no windows ->
CHECKUPDATE_CONT:
        MOVE.L  D0,A3                           | A3 = current window
        TST.B   wVisible(A3)                    | visible?
        BEQ.B   CHECKUPDATE_SKIP                | no, skip ->
| check if this window has a non-empty update region
        SUBQ.W  #0x2,SP                         | space for EmptyRgn result
        MOVE.L  updateRgn(A3),-(SP)             | push updateRgn
        _EmptyRgn                               | is updateRgn empty?
        TST.B   (SP)+                           | check result
        BNE.B   CHECKUPDATE_SKIP                | empty -> skip this window
        TST.L   windowPic(A3)                   | window has auto-draw picture?
        BEQ.B   CHECKUPDATE_NO                  | no -> generate update event
| auto-draw window picture (no update event needed)
        MOVE.L  A3,-(SP)                        | push window
        _SetPort                                | make it current port
        SUBQ.W  #0x4,SP                         | space for NewRgn result
        _NewRgn                                 | allocate temp region
        MOVE.L  (SP),-0x4(A6)                   | save temp rgn in local var
        _GetClip                                | save current clipRgn into temp
        MOVE.L  0x1C(A3),-(SP)                  | push window's clipRgn
        PEA.L   0x10(A3)                        | push portRect
        _RectRgn                                | set clipRgn to full portRect
        MOVE.L  A3,-(SP)                        | push window
        _BeginUpDate                            | set visRgn = visRgn AND updateRgn
        MOVE.L  windowPic(A3),A0                | A0 = picture handle
        MOVE.L  A0,-(SP)                        | push picture handle
        MOVE.L  (A0),A0                         | dereference handle
        PEA.L   0x2(A0)                         | push picture frame rect
        _DrawPicture                            | draw picture into update area
        MOVE.L  A3,-(SP)                        | push window
        _EndUpDate                              | restore visRgn from SaveVisRgn
        MOVE.L  -0x4(A6),-(SP)                  | push saved clipRgn
        MOVE.L  (SP),-(SP)                      | dup for SetClip (consume + dispose)
        _SetClip                                | restore original clipRgn
        _DisposeRgn                             | free temp region
CHECKUPDATE_SKIP:
        MOVE.L  nextWindow(A3),D0               | D0 = next window in list
        BNE.B   CHECKUPDATE_CONT                | more windows -> continue scan
CHECKUPDATE_EXIT:
        _SetPort                                | restore saved port (on stack)
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down stack frame
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from CHECKUPDATE_EXIT

| ----------------------------------------------------------
|
| CHECKUPDATE_NO - fill update event for window with non-empty updateRgn
|
| Builds an EventRecord: what=updateEvt(6), message=windowPtr
| Called during boot.
CHECKUPDATE_NO:
        MOVE.L  0x8(A6),A0                      | A0 = event record pointer
        MOVE    #0x6,(A0)+                      | event.what = updateEvt (6)
        MOVE.L  A3,(A0)                         | event.message = window pointer
        ADDQ.B  #0x1,0xC(A6)                    | result = true (found update)
        BRA.B   CHECKUPDATE_EXIT                | -> restore port and return
CHECKUPDATE_CONT_2:
        MOVEQ.L #0x6C,D0                        | D0 = sizeof(GrafPort) = 108
CHECKUPDATE_EMPTY:                              | entry when D0 preset by caller
        _NewPtr                                 | A0 = new heap block (D0 bytes)

| CHECKUPDATE_CONT_3 -- open it as GrafPort (A3 = port).
CHECKUPDATE_CONT_3:
        MOVE.L  A0,A3                           | A3 = port pointer
        MOVE.L  A0,-(SP)                        | push port for OpenPort
        _OpenPort                               | initialize as GrafPort
        RTS                                     | return from CHECKUPDATE_CONT_3

| ----------------------------------------------------------
|
| _InitWindows ($A912)
| -> (initializes Window Manager)
|
| _InitWindows ($A912): initialize the Window Manager
| Creates WMgrPort, GrayRgn (desktop), paints desktop pattern
InitWindows:
        MOVEM.L D3-D5/A3-A4,-(SP)               | save regs
        MOVE.L  (MinusOne).w,(SaveUpdate).w     | enable update events
| load desktop pattern from 'PAT ' resource #16
        SUBQ.W  #0x4,SP                         | space for GetPattern result
        MOVE    #0x10,-(SP)                     | pattern ID 16 (desktop)
        _GetPattern                             | get pattern handle
        MOVE.L  (SP)+,A0                        | A0 = pattern handle
        MOVE.L  (A0),A0                         | dereference
        MOVE.L  (A0)+,(DeskPattern).w           | copy first 4 bytes of pattern
        MOVE.L  (A0),(DeskPattern_1).w          | copy last 4 bytes of pattern
| create Window Manager port (full screen)
        BSR.B   CHECKUPDATE_CONT_2              | allocate GrafPort, A3 = WMgrPort
        MOVE.L  A3,(WMgrPort).w                 | store global WMgrPort pointer
        PEA.L   0x10(A3)                        | push WMgr port screen rect addr
        MOVE.L  (SP),-(SP)                      | dup screen rect ptr for copy
        LEA.L     (scratch8).w,A4               | A4 = scratch rect for inset/expand
        MOVEQ.L #0xC,D5                         | D5 = bottom margin (12 px) for menu bar
        MOVE.L  (SP),A0                         | A0 = source screen rect
        MOVE.L  (A0)+,(A4)+                     | copy topLeft to scratch
        MOVE.L  (A0),(A4)                       | copy botRight to scratch
        MOVE    (A0),D3                         | D3 = saved bottom coord
        MOVE    D5,(A4)                         | set scratch.bottom = 12 (top strip)
        PEA.L     (scratch8).w                  | push scratch rect (top strip)
        _PaintRect                              | paint menu bar background
        MOVE    D3,(A4)                         | restore (A4) after PaintRect
        SUB     D5,D3                           | D3 = bottom - 12 (one row above bot)
        SUBQ.W  #0x4,A4                         | rewind A4 to scratch.top
        MOVE    D3,(A4)                         | set scratch.top = bottom - 12
        MOVE.L  A4,-(SP)                        | push scratch rect (bottom strip)
        _PaintRect                              | paint menu bar bottom (legacy 64K rom)
        MOVE.L  #0x100010,D3                    | corner radius 16x16 (rounded screen)
        MOVE.L  D3,-(SP)                        | push corner radius
        PEA.L     (DeskPattern).w               | push desktop pattern
        _FillRoundRect                          | fill rounded screen with desk pattern
        JSR     DELETEMENU_CONT_4(PC)           | draw menu bar separator line
        BSR.W   PAINTBEHIND_EMPTY               | allocate region for GrayRgn
        MOVE.L  (SP)+,D5                        | D5 = GrayRgn handle
        MOVE.L  D5,(GrayRgn).w                  | store global GrayRgn
        _HidePen                                | suppress drawing during region record
        _OpenRgn                                | start recording region
        MOVE.L  D3,-(SP)                        | push corner radius
        _FrameRoundRect                         | record rounded screen shape
        MOVE.L  D5,-(SP)                        | push GrayRgn handle
        _CloseRgn                               | GrayRgn = rounded screen shape
        _ShowPen                                | re-enable drawing
        MOVE.L  D5,-(SP)                        | push GrayRgn (src)
        MOVE.L  28(A3),-(SP)                    | push port clipRgn (menu bar area)
        MOVE.L  D5,-(SP)                        | push GrayRgn (dest)
        _DiffRgn                                | GrayRgn = screen minus menu bar
        MOVE.L  D5,-(SP)                        | push GrayRgn
        _SetClip                                | clip WMgr port to desktop area
        _ShowCursor                             | show the cursor
        CLR.L   (WindowList).w                  | WindowList = nil (no windows yet)
        BSR.W   PAINTBEHIND_EMPTY               | allocate region for SaveVisRgn
        MOVE.L  (SP)+,(SaveVisRgn).w            | store SaveVisRgn handle
        CLR.L   (GhostWindow).w                 | no ghost window
        LEA.L     (CurActivate).w,A0            | A0 = ptr to CurActivate
        CLR.L   (A0)+                           | CurActivate = nil
        CLR.L   (A0)+                           | CurDeactive = nil
        MOVEM.L (SP)+,D3-D5/A3-A4               | restore saved regs
        RTS                                     | return from InitWindows
INITWINDOWS_EMPTY:
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A0                           | A0 = wStorage pointer
        BSR.W   CHECKUPDATE_CONT_3              | open it as GrafPort (A3 = port)
        BRA.B   NEWWINDOW_CONT                  | -> continue NewWindow setup

| ----------------------------------------------------------
|
| _NewWindow ($A913)
|
| _NewWindow ($A913): create a new window
| Pascal: FUNCTION NewWindow(wStorage: Ptr; boundsRect: Rect;
| title: Str255; visible: BOOLEAN;
| procID: INTEGER; behind: WindowPtr;
| goAwayFlag: BOOLEAN; refCon: LongInt)
| : WindowPtr;
NewWindow:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L D3-D5/A2-A4,-(SP)               | save regs
        BSR.W   GetSetWPort                     | save current port, switch to WMgr port
        MOVE.L  0x1E(A6),D0                     | D0 = wStorage (caller-supplied or nil)
        BNE.B   INITWINDOWS_EMPTY               | non-nil: use caller's storage ->
        MOVEQ.L #0x0,D0                         | clear high word of size
        MOVE    #windowSize,D0                  | 156 bytes = sizeof(WindowRecord)
        BSR.W   CHECKUPDATE_EMPTY               | NewPtr(D0) + OpenPort -> A3 = new port
NEWWINDOW_CONT:
        MOVE.L  A3,0x22(A6)                     | store WindowPtr as return value
        MOVE    #0x1,0x44(A3)                   | txFont := 1 (applFont)
        MOVE.L  26(A6),A2                       | A2 = boundsRect parameter
        MOVE.L  (A2),-(SP)                      | push boundsRect.topLeft
        _MovePortTo                             | position port origin
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  4(A2),-(SP)                     | push boundsRect.botRight
        MOVE.L  (A2),-(SP)                      | push boundsRect.topLeft
        BSR.W   DeltaPoint                      | compute size = botRight - topLeft
        _PortSize                               | set port size to window dimensions
        MOVE.L  (WMgrPort).w,-(SP)              | push WMgr port
        _SetPort                                | switch back to WMgr port
        LEA.L     windowKind(A3),A2             | A2 = ptr to windowKind field
        MOVE    #0x8,(A2)+                      | windowKind = 8 (userKind)
        TST.B   20(A6)                          | visible parameter?
        SNE     (A2)+                           | wVisible = true if visible param set
        CLR.B   (A2)+                           | hilited = false
        TST.B   12(A6)                          | goAway parameter?
        SNE     (A2)+                           | goAwayFlag = true if param set
        CLR.B   (A2)+                           | spareFlag = false
        MOVEQ.L #0x2,D3                         | loop counter (3 regions)
NEWWINDOW_LOOP:
        BSR.W   PAINTBEHIND_EMPTY               | allocate new empty region
        MOVE.L  (SP)+,(A2)+                     | store handle in WindowRecord
        DBRA    D3,NEWWINDOW_LOOP               | loop 3 times
        MOVE    18(A6),D3                       | D3 = procID parameter
        LSR     #0x4,D3                         | WDEF resource ID = procID / 16
NEWWINDOW_LOOP_CONT:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57444546,-(SP)               | push 'WDEF' resource type
        MOVE    D3,-(SP)                        | push WDEF resource ID
        _GetResource                            | load WDEF resource
        MOVEQ.L #0x0,D3                         | reset retry ID to 0 (default WDEF)
        MOVE.L  (SP)+,(A2)                      | store WDEF handle in windowDef
        BEQ.B   NEWWINDOW_LOOP_CONT             | nil = not found, retry with default
        MOVEQ.L #0xF,D3                         | mask for low 4 bits (variation code)
        AND     18(A6),D3                       | D3 = procID mod 16 (variation)
        MOVE.B  D3,(A2)                         | stash variation in low byte of handle
        ADDQ.W  #0x4,A2                         | advance past windowDef field
        CLR.L   (A2)+                           | dataHandle = nil
        MOVE.L  22(A6),D3                       | D3 = title string ptr
        CLR.L   -(SP)                           | space for NewString result
        MOVE.L  D3,-(SP)                        | push title string
        _NewString                              | copy title to new handle
        MOVE.L  (SP)+,(A2)+                     | store titleHandle
        CLR     -(SP)                           | space for StringWidth result
        MOVE.L  D3,-(SP)                        | push title string
        _StringWidth                            | measure title width
        MOVE    (SP)+,(A2)+                     | store titleWidth
        CLR.L   (A2)+                           | controlList = nil
        CLR.L   (A2)+                           | nextWindow = nil
        CLR.L   (A2)+                           | windowPic = nil
        MOVE.L  8(A6),(A2)+                     | refCon = caller's value
        MOVEQ.L #0x3,D0                         | wNew message
        BSR.W   MOVEWINDOW_OK                   | call WDEF(wNew)
        BSR.W   MOVEWINDOW_EMPTY                | calculate strucRgn/contRgn via wCalcRgns
        MOVE.L  14(A6),D5                       | D5 = behind parameter
        BTST    #0x0,D5                         | behind = -1 (in front of all)?
        BNE.B   NEWWINDOW_OK                    | yes -> insert at front
        TST.L   (WindowList).w                  | any windows exist?
        BEQ.B   NEWWINDOW_OK                    | no -> insert at front
        MOVE.L  A3,-(SP)                        | push new window
        MOVE.L  D5,-(SP)                        | push behind window
        BSR.W   INSERT_WINDOW                   | splice new window after behind

| paint new window and recalculate visibility
NEWWINDOW_EXIT:
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn as clobbered area
        _PaintOne                               | paint window frame
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn
        _CalcVBehind                            | recalc visRgn for windows behind
        BSR.W   RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D5/A2-A4               | restore regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0x1A,SP                        | strip 26 bytes of params
        JMP     (A0)                            | return
NEWWINDOW_OK:
        TST.B   wVisible(A3)                    | new window visible?
        BEQ.B   NEWWINDOW_NO                    | invisible -> just link into list
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get current front window
        MOVE.L  (SP)+,D0                        | D0 = old front window
        BEQ.B   NEWWINDOW_SKIP                  | no old front -> skip deactivate
        BSR.B   CLOSEWINDOW_CONT                | deactivate + unhighlight old front
NEWWINDOW_SKIP:
        ST      wHilited(A3)                    | wHilited(A3) := -1 (true)
        MOVE.L  A3,(CurActivate).w              | schedule activate event for new window
NEWWINDOW_NO:
        MOVE.L  (WindowList).w,nextWindow(A3)   | strip param
        MOVE.L  A3,(WindowList).w               | new window becomes WindowList head
        BRA.B   NEWWINDOW_EXIT                  | paint and return

| ----------------------------------------------------------
| CloseWindow -- _CloseWindow ($A92D).
| Pascal: procedure CloseWindow(theWindow: WindowPtr);
| Closes a window without disposing its WindowRecord storage:
| hides it, kills its controls, sends wDispose to the WDEF, and
| frees the strucRgn/contRgn/updateRgn handles. Plus 1986 added
| a BSR.B NEWWINDOW_CONT_2 between GetSetWPort and the
| _FrontWindow call to schedule a deactivate event for the front
| window; classic 1984 does not handle that case (the existing
| CLOSEWINDOW_CONT helper later in this file is reachable only
| via NewWindow's NEWWINDOW_OK path).
CloseWindow:
        MOVEM.L D3-D4/A3,-(SP)                  | save regs
        MOVE.L  16(SP),A3                       | A3 = window to close
        BSR.W   GetSetWPort                     | save port, switch to WMgr port
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get front window (for reactivation)
        MOVE.L  A3,-(SP)                        | push window to close
        _KillControls                           | dispose all controls in window
        MOVEQ.L #0x4,D0                         | wDispose message
        BSR.W   MOVEWINDOW_OK                   | send wDispose to WDEF
        MOVE.L  A3,-(SP)                        | push window for ShowHide
        CLR     -(SP)                           | visible = false
        _ShowHide                               | hide the window
        MOVE.L  A3,-(SP)                        | jump via A1
        BSR.W   DeleteWindow                    | unlink from window list
        MOVE.L  wTitleHandle(A3),A0             | A0 = title string handle
        _DisposeHandle                          | free title handle
        MOVE.L  structRgn(A3),-(SP)             | push structure region
        _DisposeRgn                             | free strucRgn
        MOVE.L  contRgn(A3),-(SP)               | push content region
        _DisposeRgn                             | free contRgn
        MOVE.L  updateRgn(A3),-(SP)             | push update region
        _DisposeRgn                             | free updateRgn
        MOVE.L  A3,-(SP)                        | push window
        _ClosePort                              | close the GrafPort
        MOVE.L  windowPic(A3),D0                | D0 = window picture handle
        BEQ.B   CLOSEWINDOW_SKIP                | nil -> skip
        MOVE.L  D0,-(SP)                        | push picture handle
        _KillPicture                            | dispose the picture
CLOSEWINDOW_SKIP:
        CMPA.L  (SP)+,A3                        | was this window the front?
        BNE.B   CLOSEWINDOW_SKIP_NO             | no -> just restore port
        MOVE    windowKind(A3),(CurDeKind).w    | save kind for deactivate event
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | find new front window
        BSR.W   SELECTWINDOW_CONT_NO            | activate the new front window
CLOSEWINDOW_SKIP_NO:
        BSR.W   RestorePort                     | restore caller's GrafPort
CLOSEWINDOW_SKIP_NO_NORESTORE:                  | skip-port-restore entry
        MOVEM.L (SP)+,D3-D4/A3                  | restore saved regs
        MOVE.L  (SP)+,(SP)                      | push window
        RTS                                     | return to caller (@ $BE60)
CLOSEWINDOW_CONT:
        MOVE.L  D0,-(SP)                        | save window ptr
        MOVE.L  D0,-(SP)                        | push window for HiliteWindow
        CLR     -(SP)                           | fHilite = false (unhighlight)
        _HiliteWindow                           | remove highlight
        MOVE.L  (SP)+,D0                        | restore window ptr
        TST.L   (CurDeactive).w                 | deactivate already pending?
        BGT.B   CLOSEWINDOW_CONT_SKIP           | yes -> don't overwrite
        MOVE.L  D0,A0                           | A0 = window
        MOVE    windowKind(A0),(CurDeKind).w    | save kind for deactivate event
        MOVE.L  D0,(CurDeactive).w              | schedule deactivate event
CLOSEWINDOW_CONT_SKIP:
        RTS                                     | return from CLOSEWINDOW_CONT_SKIP

| ----------------------------------------------------------
|
| _DisposWindow ($A914): close a window and release its WindowRecord
| Pascal: PROCEDURE DisposeWindow(theWindow: WindowPtr);
| Calls CloseWindow, then _DisposPtr on the WindowRecord itself (for
| windows whose storage was allocated by NewWindow / GetNewWindow).
| Apple source name: DisposeWindow (MacSEROM.lst: DISPOSEWINDOW)
|
DisposWindow:
        MOVE.L  4(SP),-(SP)                     | push window for CloseWindow
        BSR.W   CloseWindow                     | close window's data structures
        MOVE.L  (SP)+,A1                        | pop return address
        MOVE.L  (SP)+,A0                        | A0 = window pointer
        _DisposePtr                             | free WindowRecord storage
        JMP     (A1)                            | return

| ----------------------------------------------------------
|
| _ShowWindow ($A915)
| stack: window -> (makes window visible)
|
| _ShowWindow ($A915): make a window visible
| If this would be the frontmost visible window, also selects it
ShowWindow:
        MOVE.L  (WindowList).w,A0               | start at front of window list
| find first visible window in front of target
SHOWWINDOW_NO:
        TST.B   wVisible(A0)                    | this window visible?
        BNE.B   SHOWWINDOW_FOUND                | yes, found one in front ->
        CMPA.L  0x4(SP),A0                      | is this our target window?
        BEQ.B   SHOWWINDOW_OK                   | yes, it would be frontmost ->
        MOVE.L  nextWindow(A0),A0               | next window
        MOVE.L  A0,D0                           | end of list?
        BNE.B   SHOWWINDOW_NO                   | no ->
| show the window (another visible window is already in front)
SHOWWINDOW_FOUND:
        MOVE.L  (SP)+,A1                        | save return address
        ST      -(SP)                           | visible = true
        _ShowHide                               | make it visible
        JMP     (A1)                            | return
| target would be frontmost: select it (brings to front + activates)
SHOWWINDOW_OK:
        MOVE.L  A0,-(SP)                        | push window
        _SelectWindow                           | select (implies show)
        BRA.B   SHOWWINDOW_FOUND                | -> show

| ----------------------------------------------------------
|
| _HideWindow ($A916)
| stack: window -> (makes window invisible)
|
| _HideWindow ($A916): hide a window and select next visible if it was front
| Pascal: procedure HideWindow(theWindow: WindowPtr);
| Called during boot.
HideWindow:
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get front window before hiding
        MOVE.L  0x8(SP),-(SP)                   | push target window
        CLR     -(SP)                           | visible = false
        _ShowHide                               | hide the window
        MOVE.L  (SP)+,D0                        | D0 = old front window
        CMP.L   0x4(SP),D0                      | was hidden window the front?
        BNE.B   HIDEWINDOW_DONE                 | no -> done
        BSR.B   CLOSEWINDOW_CONT                | deactivate old front
        SUBQ.W  #0x4,SP                         | space for FrontWindow
        _FrontWindow                            | get new front window
        MOVE.L  (SP),(CurActivate).w            | schedule activate for it
        BEQ.B   HIDEWINDOW_EMPTY                | nil -> no window to select
        _SelectWindow                           | select the new front window
HIDEWINDOW_DONE:
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from HIDEWINDOW_DONE
HIDEWINDOW_EMPTY:
        ADDQ.W  #0x4,SP                         | discard nil FrontWindow result
        BRA.B   HIDEWINDOW_DONE                 | -> return

| ----------------------------------------------------------
| GetWRefCon -- _GetWRefCon ($A917).
| Pascal: function GetWRefCon(theWindow: WindowPtr): LongInt;
| Returns the refCon field (offset 0x98) of a WindowRecord.
GetWRefCon:
        MOVE    #0x98,D1                        | D1 = refCon field offset
GETWREFCON_TAIL:
        MOVE.L  (SP)+,A0                        | A0 = caller's return addr
        MOVE.L  (SP)+,A1                        | A1 = WindowPtr (popped)
        MOVE.L  0(A1,D1.W),(SP)                 | store field @ D1(A1) as return value
        JMP     (A0)                            | return

| ----------------------------------------------------------
| SetWRefCon -- _SetWRefCon ($A918).
| Pascal: procedure SetWRefCon(theWindow: WindowPtr; data: LongInt);
| Stores a new value into the refCon field (offset 0x98).
SetWRefCon:
        MOVE    #0x98,D1                        | D1 = refCon field offset
SETWREFCON_TAIL:
        MOVE.L  (SP)+,A0                        | A0 = return address
        MOVE.L  (SP)+,D0                        | D0 = new value
        MOVE.L  (SP)+,A1                        | A1 = WindowPtr
        MOVE.L  D0,0(A1,D1.W)                   | store value at field @ D1(A1)
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| SetWindowPic -- _SetWindowPic ($A92E).
| Pascal: procedure SetWindowPic(theWindow: WindowPtr; pic: PicHandle);
| Stores a PicHandle into the windowPic field (offset 0x94).
| Used by Window Manager to redraw window contents from a saved picture.
SetWindowPic:
        MOVE    #0x94,D1                        | D1 = windowPic field offset
        BRA.B   SETWREFCON_TAIL                 | -> generic field setter

| ----------------------------------------------------------
| GetWindowPic -- _GetWindowPic ($A92F).
| Pascal: function GetWindowPic(theWindow: WindowPtr): PicHandle;
| Returns the PicHandle stored in the windowPic field (offset 0x94).
GetWindowPic:
        MOVE    #0x94,D1                        | D1 = windowPic field offset
        BRA.B   GETWREFCON_TAIL                 | -> generic field getter

| ----------------------------------------------------------
| _GetWTitle ($A919): copy window title into caller's buffer
| Pascal: procedure GetWTitle(theWindow: WindowPtr; VAR title: Str255);
GetWTitle:
        MOVEM.L (SP)+,D1/A0-A1                  | D1=retAddr, A0=title buf, A1=window
        MOVE.L  wTitleHandle(A1),A1             | A1 = title string handle
        MOVE.L  (A1),A1                         | dereference to Pascal string
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A1),D0                         | D0 = string length
GETWTITLE_LOOP:
        MOVE.B  (A1)+,(A0)+                     | copy length byte + characters
        DBF     D0,GETWTITLE_LOOP               | loop (length+1 bytes total)
        MOVE.L  D1,A0                           | restore return address
        JMP     (A0)                            | return

| ----------------------------------------------------------
| SetWTitle -- _SetWTitle ($A91A).
| Pascal: procedure SetWTitle(theWindow: WindowPtr; title: Str255);
| Updates a window's title string. Saves a copy of the old
| strucRgn, replaces the title via _SetString, recalculates
| strucRgn/contRgn (since title width may change frame size),
| and repaints any newly-dirty area. Plus 1986 added a nil-check
| on wTitleHandle (BEQ.B SETWTITLE_SKIP) before pushing it to
| _SetString; classic 1984 always assumes wTitleHandle is valid.
SetWTitle:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save regs
        MOVE.L  24(SP),D5                       | D5 = new title string
        MOVE.L  28(SP),A3                       | A3 = window
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        MOVE.L  structRgn(A3),A0                | A0 = strucRgn handle
        _HandToHand                             | copy strucRgn (old snapshot)
        MOVE.L  A0,D3                           | D3 = old strucRgn copy
        MOVE.L  wTitleHandle(A3),-(SP)          | push title handle (dest)
        MOVE.L  D5,-(SP)                        | push new title string
        _SetString                              | copy new title into existing handle
        SUBQ.W  #0x2,SP                         | space for StringWidth result
        MOVE.L  D5,-(SP)                        | push title string
        _StringWidth                            | measure new title width
        MOVE    (SP)+,wTitleWidth(A3)           | store new wTitleWidth
        BSR.W   MOVEWINDOW_EMPTY                | recalc strucRgn/contRgn via wCalcRgns
        MOVE.L  structRgn(A3),-(SP)             | push new strucRgn (src)
        MOVE.L  D3,-(SP)                        | push old strucRgn snapshot
        MOVE.L  D3,-(SP)                        | push dest for Union
        _UnionRgn                               | D3 = new strucRgn U old strucRgn
        MOVE.L  D3,-(SP)                        | push source (union)
        MOVE.L  contRgn(A3),-(SP)               | push contRgn
        MOVE.L  D3,-(SP)                        | push dest for Diff
        _DiffRgn                                | D3 = union MINUS contRgn (dirty frame)
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push dirty region
        _PaintBehind                            | repaint windows behind in dirty area
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push dirty region
        _CalcVBehind                            | recompute visRgns behind us
        MOVE.L  D3,-(SP)                        | push dirty region
        _DisposeRgn                             | free it
        BSR.W   RestorePort                     | restore caller's port
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore regs
SETWTITLE_EXIT_TRAMP:                           | BRA.W trampoline (reached via BRA.B too)
        BRA.W   STRIP_2PARAMS_RTS               | -> strip params and return

| ----------------------------------------------------------
| _DeltaPoint ($A94F)
| _DeltaPoint ($A94F): compute difference between two points on stack
| Stack: retAddr, pt1(4 bytes), pt2(4 bytes) -> result overwrites pt2
| result.v = pt2.v - pt1.v, result.h = pt2.h - pt1.h
| Called during boot.
DeltaPoint:
        MOVE    8(SP),D0                        | D0 = pt2.v
        SUB     4(SP),D0                        | D0 = pt2.v - pt1.v
        MOVE    D0,12(SP)                       | store delta.v in result slot
        MOVE    10(SP),D0                       | D0 = pt2.h
        SUB     6(SP),D0                        | D0 = pt2.h - pt1.h
        MOVE    D0,14(SP)                       | store delta.h in result slot
        BRA.B   SETWTITLE_EXIT_TRAMP            | -> STRIP_2PARAMS_RTS via .W trampoline

| ----------------------------------------------------------
| MoveWindow -- _MoveWindow ($A91B).
| Pascal: procedure MoveWindow(theWindow: WindowPtr; hGlobal,
| vGlobal: INTEGER; front: BOOLEAN);
| Moves a window to a new global position. Saves the visible
| portion of the old strucRgn (intersected with WMgrPort.clipRgn)
| for CopyBits-blit optimization, offsets all regions by the new
| position delta, then either bring-to-front + repaint or just
| paint newly-exposed areas behind.
MoveWindow:
        MOVEM.L D3-D6/A3-A4,-(SP)               | save regs
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        MOVE.L  0x22(SP),A3                     | A3 = window
        BSR.W   HILITEWINDOW_CONT_3             | clip to GrayRgn
        BSR.W   PAINTBEHIND_EMPTY               | allocate temp region for visible-old
        MOVE.L  (SP)+,D5                        | D5 = temp region (visible old area)
        MOVE.L  structRgn(A3),A4                | A4 = strucRgn handle
        MOVE.L  A4,-(SP)                        | push strucRgn
        MOVE.L  (WMgrPort).w,A0                 | get WMgr port
        MOVE.L  28(A0),-(SP)                    | push WMgr clipRgn
        MOVE.L  D5,-(SP)                        | push dest
        _SectRgn                                | D5 = visible old structure area
        MOVEA.L A4,A0                           | A0 = strucRgn handle (input for HandToHand)
        _HandToHand                             | copy old strucRgn
        MOVE.L  A0,D6                           | D6 = old strucRgn copy
        MOVE.L  A4,-(SP)                        | push strucRgn handle (region to offset)
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  0x26(SP),-(SP)                  | push new global pos (h,v) param
        SUBQ.W  #0x4,SP                         | space for DeltaPoint of port origin
        MOVE.L  16(A3),-(SP)                    | push portBits.bounds.botRight
        MOVE.L  8(A3),-(SP)                     | push portBits.bounds.topLeft
        BSR.B   DeltaPoint                      | compute portRect size delta
        BSR.B   DeltaPoint                      | compute newPos - oldPos delta
        MOVE.L  (SP),D3                         | D3 = delta point
        _OffsetRgn                              | shift strucRgn by delta
        MOVE.L  contRgn(A3),-(SP)               | push contRgn handle
        MOVE.L  D3,-(SP)                        | push delta point
        _OffsetRgn                              | shift contRgn by delta
        MOVE.L  updateRgn(A3),-(SP)             | push updateRgn handle
        MOVE.L  D3,-(SP)                        | push delta point
        _OffsetRgn                              | shift updateRgn by delta
        MOVE.L  D5,-(SP)                        | push visible-old temp region
        MOVE.L  D3,-(SP)                        | push delta point
        _OffsetRgn                              | shift visible-old by delta (for blit)
        PEA.L   0x8(A3)                         | push portBits.bounds rect
        MOVE.L  D3,-(SP)                        | push delta point
        BSR.W   BRINGTOFRONT_CONT_2             | offset port origin
        _OffsetRect                             | shift portRect by delta
        TST.B   0x1C(SP)                        | update flag in param slot?
        BEQ.B   MOVEWINDOW_SKIP                 | no -> skip CopyBits
        MOVE.L  (GrayRgn).w,-(SP)               | push GrayRgn (full desktop)
        _SetClip                                | clip WMgr port to desktop
| CopyBits to blit window pixels from old to new position
MOVEWINDOW_SKIP:
        MOVE.L  (WMgrPort).w,A0                 | get WMgr port
        PEA.L     2(A0)                         | push srcBits (screen portBits)
        MOVE.L  (SP),-(SP)                      | push dstBits (same screen)
        MOVE.L  D6,A0                           | A0 = old strucRgn copy
        MOVE.L  (A0),A0                         | dereference
        PEA.L     2(A0)                         | push srcRect (old bounds)
        MOVE.L  (A4),A0                         | dereference new strucRgn
        PEA.L     2(A0)                         | push dstRect (new bounds)
        CLR     -(SP)                           | srcCopy transfer mode
        MOVE.L  D5,-(SP)                        | push maskRgn (visible old area)
        _CopyBits                               | blit window pixels
        MOVE.L  A4,-(SP)                        | push new strucRgn
        MOVE.L  D5,-(SP)                        | push blitted area
        MOVE.L  D5,-(SP)                        | push dest
        _DiffRgn                                | D5 = new area not covered by blit
        MOVE.L  nextWindow(A3),-(SP)            | push next window
        MOVE.L  D6,-(SP)                        | push old strucRgn
        _PaintBehind                            | repaint exposed area at old pos
        TST.B   28(SP)                          | front parameter?
        BEQ.B   MOVEWINDOW_SKIP_2               | front=false -> skip select
        MOVE.L  A3,-(SP)                        | push window for SelectWindow
        ST      (DragFlag).w                    | flag: don't repaint during select
        BSR.W   SELECTWINDOW_CONT               | select/bring to front
MOVEWINDOW_SKIP_2:
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D5,-(SP)                        | push newly exposed area
        _PaintOne                               | paint window frame in new area
        MOVE.L  D6,-(SP)                        | push old strucRgn
        MOVE.L  A4,-(SP)                        | push new strucRgn
        MOVE.L  D6,-(SP)                        | push dest
        _UnionRgn                               | D6 = old union new (full affected)
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D6,-(SP)                        | push affected area
        _CalcVBehind                            | recalculate visRgns behind
        MOVE.L  D5,-(SP)                        | push temp region
        _DisposeRgn                             | free it
        MOVE.L  D6,-(SP)                        | push old strucRgn copy
        _DisposeRgn                             | free it
        BSR.W   RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D6/A3-A4               | restore registers
        BRA.W   SIZEWINDOW_EXIT                 | -> pop retaddr, discard 0xA, RTS

| ----------------------------------------------------------
| MOVEWINDOW_OK - call WDEF procedure for window A3
| Dispatches to the window definition function. Parameters:
| D0 = message (wDraw=0, wHit=1, wCalcRgns=2, wNew=3, wDispose=4, wGrow=5)
| D3 = param (message-specific data)
| A3 = window
| Low byte of windowDef handle stores the variation code.
| Called during boot (1,330 times in 30s trace).
MOVEWINDOW_OK:
        CLR.L   -(SP)                           | space for WDEF function result
        MOVEQ.L #0x0,D1                         | clear D1
        MOVE.B  windowDef(A3),D1                | D1 = variation code (high byte of windowDefProc)
        MOVE    D1,-(SP)                        | push varCode
        MOVE.L  A3,-(SP)                        | push window
        MOVE    D0,-(SP)                        | push message
        MOVE.L  D3,-(SP)                        | push param
        MOVE.L  windowDef(A3),A0                | A0 = WDEF handle
        MOVE.L  (A0),D0                         | D0 = dereferenced WDEF ptr
        BNE.B   MOVEWINDOW_CONT                 | WDEF resident -> skip reload
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        CLR.B   (SP)                            | clear high byte (strip varCode)
        _LoadResource                           | load WDEF resource if purged
        MOVE.L  (A0),D0                         | D0 = newly-loaded WDEF pointer
MOVEWINDOW_CONT:
        BSet    #0x7,(A0)                       | lock WDEF handle during call
        MOVE.L  D0,A0                           | A0 = WDEF entry point
        JSR     (A0)                            | call WDEF
        MOVE.L  (SP)+,D0                        | D0 = WDEF result
        MOVE.L  windowDef(A3),A0                | A0 = WDEF handle
        BCLR    #0x7,(A0)                       | unlock WDEF handle
        RTS                                     | return from MOVEWINDOW_CONT
MOVEWINDOW_CONT_2:
        MOVE.L  D3,-(SP)                        | save caller's D3
        MOVEQ.L #0x0,D3                         | param = 0
        MOVEQ.L #0x0,D0                         | message = wDraw
        BSR.B   MOVEWINDOW_OK                   | send wDraw to WDEF
        MOVE.L  (SP)+,D3                        | restore D3
        RTS                                     | return from MOVEWINDOW_CONT_2
MOVEWINDOW_EMPTY:
        MOVEQ.L #0x2,D0                         | message = wCalcRgns
        TST.B   wVisible(A3)                    | window visible?
        BNE.B   MOVEWINDOW_OK                   | visible -> WDEF computes regions
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn
        _SetEmptyRgn                            | set empty
        MOVE.L  contRgn(A3),-(SP)               | push contRgn
        _SetEmptyRgn                            | set empty
        MOVE.L  0x18(A3),-(SP)                  | push visRgn
        _SetEmptyRgn                            | set empty
        RTS                                     | return from MOVEWINDOW_EMPTY

| ----------------------------------------------------------
| HiliteWindow -- _HiliteWindow ($A91C).
| Pascal: procedure HiliteWindow(theWindow: WindowPtr; fHilite: BOOLEAN);
| Sets a window's highlight (active) state. Only acts if the
| highlight state is actually changing -- uses EOR + LSR to test
| the bit toggle. Sends wDraw via MOVEWINDOW_CONT_2 to redraw
| the window frame at the new highlight level.
HiliteWindow:
        MOVEM.L D3-D4/A3-A4,-(SP)               | save regs
        MOVE.L  22(SP),A3                       | A3 = window
        MOVE.B  20(SP),D3                       | D3 = desired highlight state
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        MOVE.B  wHilited(A3),D0                 | D0 = current hilited flag
        EOR     D3,D0                           | XOR: bit 0 set if hilite is changing
        LSR     #0x1,D0                         | bit 0 -> carry
        BCC.B   HILITEWINDOW_SKIP               | no change -> skip
        MOVE.B  D3,wHilited(A3)                 | set new hilited state
        BSR.B   HILITEWINDOW_CONT               | set clip to strucRgn above window
        BSR.B   MOVEWINDOW_CONT_2               | jump via A0
HILITEWINDOW_SKIP:
        BSR.W   RestorePort                     | restore caller's port
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore saved regs
        BRA.W   DRAWNEW_EXIT                    | strip 6 bytes of params and return
HILITEWINDOW_CONT:
        MOVE.L  structRgn(A3),-(SP)             | push window's strucRgn
HILITEWINDOW_CONT_2:
        _SetClip                                | set WMgr clip to region
        MOVE.L  A3,-(SP)                        | push window
        _ClipAbove                              | subtract all windows above A3
        RTS                                     | return from HILITEWINDOW_CONT_2
HILITEWINDOW_CONT_3:
        MOVE.L  (GrayRgn).w,-(SP)               | push desktop region
        BRA.B   HILITEWINDOW_CONT_2             | set clip to GrayRgn minus windows above

| ----------------------------------------------------------
|
| _SizeWindow ($A91D): change the size of a window
| Pascal: PROCEDURE SizeWindow(theWindow: WindowPtr; w, h: INTEGER;
|                              fUpdate: BOOLEAN);
| Does nothing if w = h = 0. Sets portRect.bottom := top + h and
| portRect.right := left + w. If the window is visible: SaveOld,
| recalculate strucRgn/contRgn (wCalcRgns), redraw the frame (wDraw)
| and DrawNew(theWindow, fUpdate).; the Plus
| factors the redraw into a SIZEWINDOW_CONT helper, the 1984 ROM inlines it.
|
SizeWindow:
        MOVEM.L D3-D4/A3-A4,-(SP)               | save regs
        MOVE.L  22(SP),D3                       | D3 = (h,w) as one long
        BEQ.B   SIZEWINDOW_DONE                 | w = h = 0 -> nothing to do
        MOVE.L  26(SP),A3                       | A3 = window
        MOVE    22(SP),D4                       | D4 = h
        LEA.L     16(A3),A4                     | A4 = portRect
        ADD     (A4)+,D4                        | D4 = portRect.top + h = new bottom
        ADD     (A4)+,D3                        | D3 = portRect.left + w = new right
        MOVE    D4,(A4)+                        | store new portRect.bottom
        MOVE    D3,(A4)+                        | store new portRect.right
        TST.B   wVisible(A3)                    | window visible?
        BEQ.B   SIZEWINDOW_DONE                 | invisible -> just store new portRect
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        MOVE.L  A3,-(SP)                        | push window
        _SaveOld                                | snapshot old regions
        BSR.W   MOVEWINDOW_EMPTY                | recalc strucRgn/contRgn via wCalcRgns
        BSR.B   HILITEWINDOW_CONT               | set clip to strucRgn
        BSR.W   MOVEWINDOW_CONT_2               | send wDraw to WDEF (frame redraw)
        MOVE.L  A3,-(SP)                        | push window for DrawNew
        MOVE    24(SP),-(SP)                    | push fUpdate parameter
        _DrawNew                                | repaint changed areas
        BSR.W   RestorePort                     | restore caller's port
SIZEWINDOW_DONE:
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore saved regs
SIZEWINDOW_EXIT:                                | shared "pop retaddr + discard 0xA" exit
        MOVE.L  (SP)+,A0                        | A0 = saved return addr
        ADDA.W  #0xA,SP                         | pop 10 bytes of param area
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
|
| _TrackGoAway ($A91E): track the mouse in a window's go-away box
| Pascal: FUNCTION TrackGoAway(theWindow: WindowPtr; thePt: Point): BOOLEAN;
| While the button is down: asks the WDEF (wHit) whether the mouse is in
| the go-away box (wInGoAway = 4), toggles the box highlight (wDraw,
| param 4) when that changes, gets the mouse and calls DragHook. Returns
| TRUE, and un-highlights the box, if released inside it.
| . The Plus turns this into a stub that pushes
| partCode 6 and falls into the generic TrackBox loop (TrackBox is new
| in the Plus); the 1984 ROM compares the wHit result with 4 (= 6-2).
|
TrackGoAway:
        LINK    A6,#-0x4                        | local var: mouse point
        MOVEM.L D3-D5/A3,-(SP)                  | save regs
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        LEA.L     8(A6),A0                      | A0 = stack params
        MOVE.L  (A0)+,-4(A6)                    | save startPt in local var
        MOVE.L  (A0)+,A3                        | A3 = window
        CLR     (A0)                            | result = false initially
        MOVEQ.L #0x0,D5                         | D5 = current highlight state (off)
        BSR.B   HILITEWINDOW_CONT               | clip to strucRgn above window
TRACKGOAWAY_OK:
        MOVEQ.L #0x1,D0                         | message = wHit (hit-testing)
        MOVE.L  -4(A6),D3                       | param = current mouse point
        BSR.W   MOVEWINDOW_OK                   | ask WDEF which part was hit
        CMPI    #0x4,D0                         | partCode == wInGoAway?
        BEQ.B   TRACKGOAWAY_OK_2                | yes -> highlight on
        MOVEQ.L #0x0,D0                         | no -> highlight off
TRACKGOAWAY_OK_2:
        CMP     D0,D5                           | highlight state changed?
        BEQ.B   TRACKGOAWAY_SKIP                | no -> skip redraw
        MOVE    D0,D5                           | update highlight state
        BSR.B   TRACKGOAWAY_CONT                | toggle part highlight via wDraw
TRACKGOAWAY_SKIP:
        PEA.L     -4(A6)                        | push addr of mouse local var
        _GetMouse                               | fetch current mouse position
        BSR.W   DRAGTHERGN_CONT_3               | call DragHook, if one is installed
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | button still down?
        TST.B   (SP)+                           | check result
        BNE.B   TRACKGOAWAY_OK                  | button down -> keep tracking
        TST     D5                              | was last state highlighted?
        BEQ.B   TRACKGOAWAY_NO                  | no -> exit, return false
        ADDQ.B  #0x1,16(A6)                     | result := TRUE
        BSR.B   TRACKGOAWAY_CONT                | un-highlight (released inside box)
TRACKGOAWAY_NO:
        BSR.W   RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D5/A3                  | restore regs
        UNLK    A6                              | tear down frame
        BRA.W   STRIP_2PARAMS_RTS               | -> strip params and return
TRACKGOAWAY_CONT:
        MOVEQ.L #0x0,D0                         | message = wDraw
        MOVEQ.L #0x4,D3                         | param = wInGoAway part code
        BSR.W   MOVEWINDOW_OK                   | toggle go-away box highlight
        RTS                                     | return from TRACKGOAWAY_CONT

| ----------------------------------------------------------
| SelectWindow -- _SelectWindow ($A91F).
| Pascal: procedure SelectWindow(theWindow: WindowPtr);
| Brings a window to the front of the window list and activates
| it (highlights it + schedules an activate event). If a different
| window was previously frontmost, deactivates that one first via
| CLOSEWINDOW_CONT.
SelectWindow:
        CLR.B   (DragFlag).w                    | clear drag state
| SELECTWINDOW_CONT -- select/bring to front.
SELECTWINDOW_CONT:
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get current front window
        MOVE.L  8(SP),-(SP)                     | push target window
        BSR.B   BRINGTOFRONT_CONT               | BringToFront
        MOVE.L  (SP)+,D0                        | D0 = old front window
        BEQ.B   SELECTWINDOW_CONT_NO            | no old front ->
        CMP.L   4(SP),D0                        | same as target?
        BEQ.B   SELECTWINDOW_OK                 | yes, no change ->
        BSR.W   CLOSEWINDOW_CONT                | deactivate old front window
SELECTWINDOW_CONT_NO:
        MOVE.L  4(SP),D0                        | D0 = target window
        BEQ.B   SELECTWINDOW_OK_CONT            | nil window -> just strip param
        MOVE.L  D0,(CurActivate).w              | schedule activate event for window
SELECTWINDOW_OK:
        MOVE.L  D0,-(SP)                        | push window for HiliteWindow
        ST.B    -(SP)                           | fHilite = true (highlight)
        _HiliteWindow                           | highlight the window
SELECTWINDOW_OK_CONT:
        MOVE.L  (SP)+,(SP)                      | push window
        RTS                                     | return from SELECTWINDOW_OK_CONT
BringToFront:
        CLR.B   (DragFlag).w                    | clear drag-state flag
BRINGTOFRONT_CONT:
        MOVEM.L D3-D6/A2-A4,-(SP)               | save regs
        MOVE.L  0x20(SP),A3                     | A3 = window to bring to front
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        LEA.L     (WindowList).w,A2             | A2 = ptr to WindowList head
        CMPA.L  (A2),A3                         | already at front?
        BEQ.W   BRINGTOFRONT_DONE_CONT          | yes -> nothing to do
        BSR.W   PAINTBEHIND_EMPTY               | allocate accumulator region
        MOVE.L  (SP)+,D3                        | D3 = obscured-area accumulator
        MOVE.L  (A2),A4                         | A4 = WindowList head (front)
BRINGTOFRONT_NO:
        CMPA.L  A3,A4                           | reached target window?
        BEQ.B   BRINGTOFRONT_DONE               | yes -> done scanning
        TST.B   wVisible(A4)                    | this window visible?
        BEQ.B   BRINGTOFRONT_NO_SKIP            | invisible -> skip
        MOVE.L  8(A4),D6                        | D6 = portBounds.topLeft (for offset)
        MOVE.L  24(A4),D5                       | D5 = visRgn handle
        MOVE.L  D5,-(SP)                        | push visRgn
        MOVE.L  D6,-(SP)                        | push local-to-global offset
        BSR.B   BRINGTOFRONT_CONT_2             | negate (global-to-local -> local-to-global)
        _OffsetRgn                              | convert visRgn to global coords
        MOVE.L  D5,-(SP)                        | push visRgn (global)
        MOVE.L  structRgn(A3),-(SP)             | push target's strucRgn
        MOVE.L  D5,-(SP)                        | push dest
        _DiffRgn                                | visRgn -= target strucRgn
        MOVE.L  D5,-(SP)                        | push modified visRgn
        MOVE.L  D6,-(SP)                        | push offset
        _OffsetRgn                              | convert back to local coords
        MOVE.L  structRgn(A4),-(SP)             | push this window's strucRgn
        MOVE.L  D3,-(SP)                        | push accumulator region
        MOVE.L  D3,-(SP)                        | push dest (same handle)
        _UnionRgn                               | D3 |= A4's strucRgn
BRINGTOFRONT_NO_SKIP:
        MOVE.L  nextWindow(A4),A4               | walk to next window
        MOVE.L  A4,D0                           | end of list?
        BNE.B   BRINGTOFRONT_NO                 | more windows -> continue scan
BRINGTOFRONT_DONE:
        MOVE.L  A3,-(SP)                        | push window
        BSR.W   DeleteWindow                    | unlink from window list
        MOVE.L  (A2),nextWindow(A3)             | link old head as next
        MOVE.L  A3,(A2)                         | target becomes new head
        TST.B   (DragFlag).w                    | drag optimization active?
        BNE.B   BRINGTOFRONT_DONE_SKIP          | yes -> skip repaint
        MOVE.L  structRgn(A3),-(SP)             | push target's strucRgn
        MOVE.L  D3,-(SP)                        | push obscured area
        MOVE.L  D3,-(SP)                        | push dest
        _SectRgn                                | D3 = newly visible portion
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push area to repaint
        _PaintOne                               | repaint window frame
BRINGTOFRONT_DONE_SKIP:
        MOVE.L  A3,-(SP)                        | push window for CalcVis
        _CalcVis                                | recompute target visRgn
        MOVE.L  D3,-(SP)                        | push accumulator region
        _DisposeRgn                             | free temp region
BRINGTOFRONT_DONE_CONT:
        BSR.W   RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D6/A2-A4               | restore saved regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from BRINGTOFRONT_DONE_CONT

| ----------------------------------------------------------
| BRINGTOFRONT_CONT_2 - negate a point on the stack (reverse an offset)
| Negates the v and h components of a point at SP+4.
| Called during boot.
BRINGTOFRONT_CONT_2:
        NEG     0x4(SP)                         | negate v component
        NEG     0x6(SP)                         | negate h component
        RTS                                     | return from BRINGTOFRONT_CONT_2

| ----------------------------------------------------------
| SendBehind -- _SendBehind ($A921).
| Pascal: procedure SendBehind(theWindow: WindowPtr;
| behindWindow: WindowPtr);
| Reorders theWindow to be just behind behindWindow in the window
| list. If theWindow was the frontmost, first selects the next
| visible window via _SelectWindow. Then unlinks, reinserts, and
| repaints exposed area.
SendBehind:
        MOVEM.L D3-D4/A3,-(SP)                  | save regs
        MOVE.L  20(SP),A3                       | A3 = window to send behind
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        SUBQ.W  #0x4,SP                         | space for FrontWindow
        _FrontWindow                            | get current front window
        CMPA.L  (SP)+,A3                        | is target the front window?
        BNE.B   SENDBEHIND_NO_2                 | no -> just reorder
        MOVE.L  A3,A0                           | A0 = target window
SENDBEHIND_NO:
        MOVE.L  nextWindow(A0),A0               | walk to next window
        MOVE.L  A0,D0                           | end of list?
        BEQ.B   SENDBEHIND_NO_2                 | yes -> no window to select
        TST.B   wVisible(A0)                    | this window visible?
        BEQ.B   SENDBEHIND_NO                   | no -> keep looking
        MOVE.L  A0,-(SP)                        | push next visible window
        _SelectWindow                           | select it as new front
SENDBEHIND_NO_2:
        MOVE.L  A3,-(SP)                        | push window
        BSR.W   DeleteWindow                    | remove from window list
        MOVE.L  structRgn(A3),D3                | D3 = strucRgn (clobbered area)
        MOVE.L  nextWindow(A3),-(SP)            | push next window (for PaintBehind)
        MOVE.L  (SP),-(SP)                      | dup for CalcVBehind
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  28(SP),-(SP)                    | push behindWindow parameter
        BSR.W   INSERT_WINDOW                   | insert window behind target
        MOVE.L  D3,-(SP)                        | push clobbered area
        _CalcVBehind                            | recalculate visRgns behind
        MOVE.L  D3,-(SP)                        | push clobbered area
        _PaintBehind                            | repaint exposed area
        BSR.W   RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D4/A3                  | restore regs
        BRA.W   STRIP_2PARAMS_RTS               | -> strip params and return

| ----------------------------------------------------------
|
| _BeginUpDate ($A922): restrict the visRgn to the update region
| Pascal: PROCEDURE BeginUpdate(theWindow: WindowPtr);
| Converts visRgn to global coordinates, saves a copy in SaveVisRgn,
| sets visRgn := visRgn SECT updateRgn, converts visRgn back to local
| coordinates (offset by portBits.bounds.topLeft) and empties updateRgn.
|
BeginUpdate:
        MOVEM.L D3-D4/A3,-(SP)                  | save regs
        MOVE.L  16(SP),A3                       | A3 = window
        MOVE.L  8(A3),D3                        | D3 = portBits.bounds.topLeft
        MOVE.L  24(A3),D4                       | D4 = visRgn handle
        MOVE.L  D4,-(SP)                        | push visRgn
        MOVE.L  D3,-(SP)                        | push offset
        BSR.B   BRINGTOFRONT_CONT_2             | negate offset
        _OffsetRgn                              | visRgn -> global coords
        MOVE.L  D4,-(SP)                        | push visRgn (source)
        MOVE.L  (SaveVisRgn).w,-(SP)            | save into SaveVisRgn
        _CopyRgn                                | SaveVisRgn = copy of visRgn
        MOVE.L  D4,-(SP)                        | visRgn
        MOVE.L  updateRgn(A3),-(SP)             | updateRgn
        MOVE.L  D4,-(SP)                        | push visRgn (dest)
        _SectRgn                                | visRgn = visRgn AND updateRgn
        MOVE.L  D4,-(SP)                        | push visRgn for offset
        MOVE.L  D3,-(SP)                        | push bounds.topLeft (global -> local)
        _OffsetRgn                              | visRgn -> local coords
        MOVE.L  updateRgn(A3),-(SP)             | push updateRgn handle
        _SetEmptyRgn                            | updateRgn = empty
        BRA.W   CLOSEWINDOW_SKIP_NO_NORESTORE   | -> restore regs + return (no port restore)

| ----------------------------------------------------------
|
| _EndUpDate ($A923): restore the visRgn after an update
| Pascal: PROCEDURE EndUpdate(theWindow: WindowPtr);
| Converts SaveVisRgn (saved by BeginUpdate in global coordinates) to the
| window's local coordinates, copies it into visRgn and empties
| SaveVisRgn.
|
EndUpdate:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  8(SP),A3                        | A3 = window
        MOVE.L  (SaveVisRgn).w,-(SP)            | push SaveVisRgn (for SetEmptyRgn)
        MOVE.L  (SP),-(SP)                      | dup (CopyRgn source)
        MOVE.L  (SP),-(SP)                      | dup (OffsetRgn)
        MOVE.L  8(A3),-(SP)                     | push portBits.bounds.topLeft
        _OffsetRgn                              | convert SaveVisRgn to local coords
        MOVE.L  0x18(A3),-(SP)                  | push visRgn (dest)
        _CopyRgn                                | visRgn = saved visRgn
        _SetEmptyRgn                            | empty SaveVisRgn for next use
        MOVE.L  (SP)+,A3                        | restore A3
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from EndUpdate

| ----------------------------------------------------------
| FrontWindow -- _FrontWindow ($A924).
| Pascal: function FrontWindow: WindowPtr;
| Returns the frontmost visible non-ghost window in the window
| list. Plus 1986 added a (WWExist).w check that returns nil if
| the Window Manager hasn't been initialized; classic 1984 omits
| this guard.
FrontWindow:
        MOVE.L  (WindowList).w,A0               | A0 = first window in list
FRONTWINDOW_LOOP:
        MOVE.L  A0,D0                           | end of list?
        BEQ.B   FRONTWINDOW_LOOP_EXIT           | yes -> return nil
        CMPA.L  (GhostWindow).w,A0              | is this the ghost window?
        BEQ.B   FRONTWINDOW_LOOP_SKIP           | yes -> skip it
        TST.B   wVisible(A0)                    | window visible?
        BNE.B   FRONTWINDOW_LOOP_EXIT           | yes -> found it
FRONTWINDOW_LOOP_SKIP:
        MOVE.L  nextWindow(A0),A0               | advance to next window
        BRA.B   FRONTWINDOW_LOOP                | loop
FRONTWINDOW_LOOP_EXIT:
        MOVE.L  A0,4(SP)                        | return value = window ptr (or nil)
        RTS                                     | return from FRONTWINDOW_LOOP_EXIT

| ----------------------------------------------------------
| DragWindow -- _DragWindow ($A925).
| Pascal: procedure DragWindow(theWindow: WindowPtr; startPt: Point;
| boundsRect: Rect);
| Tracks a gray-outline drag of a window. Clamps the bounds rect
| to keep the title bar visible (top >= 0x18 = 24), allocates a
| drag region from the strucRgn, and calls _DragGrayRgn. If the
| drag completes (not cancelled), MoveWindow's the window to the
| new global position. Holding Command during drag prevents the
| window from being brought to front.
DragWindow:
        LINK    A6,#-0x24                       | 36 bytes local vars (rects, regions)
        MOVEM.L D3-D6/A3-A4,-(SP)               | save regs
        SUBQ.W  #0x2,SP                         | space for WaitMouseUp result
        _WaitMouseUp                            | wait for button release (debounce)
        TST.B   (SP)+                           | button still down?
        BEQ.W   DRAGWINDOW_SKIP_CONT            | button up: just exit
        MOVE.L  8(A6),A0                        | A0 = boundsRect parameter
        MOVE    (A0)+,D0                        | D0 = bounds.top
        CMPI    #0x18,D0                        | top >= 24 (menu bar height)?
        BCC.W   DRAGWINDOW_OK                   | yes -> use as-is
        MOVEQ.L #0x18,D0                        | no -> clamp to 24
DRAGWINDOW_OK:
        LEA.L     -16(A6),A1                    | A1 = local drag rect
        MOVE    D0,(A1)+                        | store clamped top
        MOVE    (A0)+,(A1)+                     | copy bounds.left
        MOVE.L  (A0),(A1)                       | copy bounds.bottom, bounds.right
        MOVE.L  12(A6),D3                       | D3 = startPt
        MOVE.L  16(A6),A3                       | A3 = window
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        MOVE.L  (GrayRgn).w,-(SP)               | push desktop region
        _SetClip                                | clip to desktop
        PEA.L     -0x24(A6)                     | push local key map buffer
        _GetKeys                                | read current key state
        MOVE.B  -0x1E(A6),D6                    | D6 = Command key byte (KeyMap+6)
        BPL.B   DRAGWINDOW_SKIP                 | Command not held -> skip
        BSR.W   HILITEWINDOW_CONT_3             | also clip above target window
DRAGWINDOW_SKIP:
        BSR.W   PAINTBEHIND_EMPTY               | allocate drag outline region
        MOVE.L  (SP),A4                         | A4 = drag region handle
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn
        MOVE.L  A4,-(SP)                        | push dest
        _CopyRgn                                | copy strucRgn as drag outline
        MOVE.L  A4,-(SP)                        | push drag region
        MOVE.L  D3,-(SP)                        | push startPt
        PEA.L     -16(A6)                       | push drag bounds rect
        MOVE.L  (SP),-(SP)                      | push slopRect (same as bounds)
        CLR     -(SP)                           | axis = noConstraint
        CLR.L   -(SP)                           | actionProc = nil
        _DragGrayRgn                            | track gray outline drag
        MOVE.L  (SP)+,D5                        | D5 = drag result (dv:dh)
        BEQ.B   DRAGWINDOW_EMPTY                | zero offset -> just select
        CMPI    #-0x8000,D5                     | drag cancelled?
        BEQ.B   DRAGWINDOW_SKIP_SKIP            | cancelled (-32768) -> cleanup
        MOVE.L  A3,-(SP)                        | push window for MoveWindow
        MOVE.L  16(A3),D0                       | D0 = portRect.topLeft (low word = left)
        SUB     10(A3),D0                       | subtract portBits.bounds.left (global x)
        ADD     D5,D0                           | add horizontal drag offset
        MOVE    D0,-(SP)                        | push new hGlobal
        SWAP    D0                              | D0.W = portRect.top
        SWAP    D5                              | D5.W = vertical drag offset
        SUB     8(A3),D0                        | subtract portBits.bounds.top (global y)
        ADD     D5,D0                           | add vertical drag offset
        MOVE    D0,-(SP)                        | push new vGlobal
        TST.B   D6                              | Command key held?
        SPL     -(SP)                           | front = true if Cmd not held
        _MoveWindow                             | move to new position
DRAGWINDOW_SKIP_SKIP:
        MOVE.L  A4,-(SP)                        | push drag region handle
        _DisposeRgn                             | free drag outline region
        BSR.W   RestorePort                     | restore original port
DRAGWINDOW_SKIP_CONT:
        MOVEM.L (SP)+,D3-D6/A3-A4               | restore saved regs
        UNLK    A6                              | tear down frame
        BRA.W   GROWWINDOW_SKIP_CONT            | strip params and return

| ----------------------------------------------------------
| DRAGWINDOW_EMPTY - zero drag offset: window not moved, select if Cmd not held
DRAGWINDOW_EMPTY:
        TST.B   D6                              | Command key held?
        BMI.B   DRAGWINDOW_SKIP_SKIP            | yes -> don't select, cleanup
        MOVE.L  A3,-(SP)                        | push window
        _SelectWindow                           | select (bring to front)
        BRA.B   DRAGWINDOW_SKIP_SKIP            | -> cleanup
| ----------------------------------------------------------
| DragGrayRgn 50%-gray pattern @ $C41C -- 8 bytes, PC-relative source
| loaded into the low-memory DragPattern ($0A34) by DragGrayRgn.
| ----------------------------------------------------------
DRAGPATTERN_SRC:
        .byte   0xAA, 0x55, 0xAA, 0x55
        .byte   0xAA, 0x55, 0xAA, 0x55          | 8-byte alternating-row 50% gray

| _DragGrayRgn ($A905): drag a gray outline region tracking the mouse
| Sets up gray pattern, falls into DragTheRgn.
DragGrayRgn:
        MOVE.L  DRAGPATTERN_SRC(PC),(DragPattern).w | load gray pattern (first 4 bytes)
        MOVE.L  (DRAGPATTERN_SRC+4)(PC),(DragPattern+4).w | load gray pattern (last 4 bytes)
| _DragTheRgn ($A926): generic region-dragging loop
| Stack params: region, startPt, limitRect, slopRect, axis, actionProc
| Returns: packed dv:dh offset (0x80008000 if cancelled)
DragTheRgn:
        LINK    A6,#-0x14                       | local vars: PenState + scratch
        MOVEM.L D3-D5/A3,-(SP)                  | save regs
        LEA.L     22(A6),A0                     | A0 = stack params
        MOVE.L  (A0)+,D3                        | D3 = startPt
        MOVE.L  (A0)+,A3                        | A3 = region handle to drag
        CLR.L   (A0)                            | clear result location
        PEA.L     -20(A6)                       | push local PenState buffer
        MOVE.L  (SP),-(SP)                      | dup for GetPenState
        _GetPenState                            | save current pen state
        PEA.L     (DragPattern).w               | push gray pattern
        _PenPat                                 | set pen pattern to gray
        MOVE    #0xE,-(SP)                      | patXor mode
        _PenMode                                | set XOR drawing mode
        MOVE.L  A3,-(SP)                        | push source region
        BSR.W   PAINTBEHIND_EMPTY               | allocate temp region
        MOVE.L  (SP),D4                         | D4 = temp region handle
        _CopyRgn                                | temp = copy of drag region
        MOVE.L  D4,-(SP)                        | push temp
        MOVE.L  (OneOne).w,-(SP)                | push inset amount (1,1)
        _InsetRgn                               | shrink temp by 1 pixel
        MOVE.L  A3,-(SP)                        | push original region
        MOVE.L  D4,-(SP)                        | push inset copy
        MOVE.L  A3,-(SP)                        | push dest
        _DiffRgn                                | A3 = outline (original minus inset)
        MOVE.L  D4,-(SP)                        | push temp
        _DisposeRgn                             | free temp
        MOVE.L  A3,-(SP)                        | push outline region
        _PaintRgn                               | draw gray outline (XOR on)
        MOVEQ.L #-0x1,D5                        | D5 = outline visible flag (-1=drawn)

| main tracking loop
DRAGTHERGN_OK:
        SUBQ.W  #0x6,SP                         | space for GetMouse result + PtInRect
        MOVE.L  SP,-(SP)                        | push ptr to result
        _GetMouse                               | read current mouse position
        MOVE.L  (SP),D4                         | D4 = current mouse (v:h)
        MOVE.L  18(A6),-(SP)                    | push limitRect
        _PtInRect                               | mouse inside limit?
        TST.B   (SP)+                           | check result
        BEQ.W   DRAGTHERGN_CONT_4               | outside limit -> check slop rect

| mouse inside limit rect: compute delta and move outline
DRAGTHERGN_CONT:
        MOVE.L  D4,D1                           | D1 = current mouse
        SWAP    D1                              | D1 = horizontal component
        CMP.L   D4,D3                           | mouse moved from last position?
        BEQ.B   DRAGTHERGN_SKIP_2               | no -> skip outline move
        MOVE.L  D4,-(SP)                        | save current pt for next iteration
        SUB     D3,D4                           | D4 = vertical delta (v component)
        SWAP    D3                              | get horizontal component of D3
        SUB     D3,D1                           | D1 = horizontal delta
        MOVE    12(A6),D0                       | D0 = axis param (0=none,1=vOnly,2=hOnly)
        BEQ.B   DRAGTHERGN_CONT_2               | noConstraint -> use both deltas
        SUBQ.W  #0x1,D0                         | test for vertical-only
        BNE.B   DRAGTHERGN_CONT_NO              | not vOnly -> must be hOnly
        CLR     D1                              | vertical only: zero horizontal delta
        BRA.B   DRAGTHERGN_CONT_2               | -> apply
DRAGTHERGN_CONT_NO:
        CLR.W    D4                             | horizontal only: zero vertical delta
DRAGTHERGN_CONT_2:                              | call subroutine via A0
        ADD     D1,30(A6)                       | result.h += horizontal delta
        ADD     D4,0x20(A6)                     | result.v += vertical delta
        MOVE.L  A3,-(SP)                        | push region for OfsetRgn
        MOVE    D4,-(SP)                        | push vertical offset
        MOVE    D1,-(SP)                        | push horizontal offset
        TST     D5                              | outline currently drawn?
        BEQ.B   DRAGTHERGN_CONT_2_SKIP          | no -> skip erase
        MOVE.L  A3,-(SP)                        | push region
        _PaintRgn                               | erase old outline (XOR toggles off)
DRAGTHERGN_CONT_2_SKIP:
        _OffsetRgn                              | shift outline region by delta
        MOVE.L  A3,-(SP)                        | push outline region
        _PaintRgn                               | draw outline at new pos (XOR on)
        MOVEQ.L #-0x1,D5                        | mark outline as drawn
        MOVE.L  (SP)+,D3                        | D3 = new last-mouse pt
| call actionProc and DragHook, then wait
DRAGTHERGN_SKIP_2:
        MOVE.L  8(A6),D0                        | D0 = actionProc
        BSR.B   DRAGTHERGN_EMPTY                | call actionProc if non-nil
        BSR.B   DRAGTHERGN_CONT_3               | call DragHook if installed
        MOVE.L  (Ticks).w,D0                    | D0 = current tick count
        ADDQ.L  #0x2,D0                         | target = now + 2 ticks (rate limit)
DRAGTHERGN_NO_2:
        CMP.L   (Ticks).w,D0                    | target time reached?
        BNE.B   DRAGTHERGN_NO_2                 | no -> spin wait
        SUBQ.W  #0x2,SP                         | space for WaitMouseUp result
        _WaitMouseUp                            | check if mouse still down
        TST.B   (SP)+                           | still down?
        BNE.B   DRAGTHERGN_OK                   | yes -> continue tracking
        TST     D5                              | outline currently drawn?
        BEQ.B   DRAGTHERGN_SKIP_3               | no -> skip erase
        MOVE.L  A3,-(SP)                        | push outline region
        _PaintRgn                               | erase outline (XOR toggles off)
DRAGTHERGN_SKIP_3:
        _SetPenState                            | restore original pen state
        SUBQ.W  #0x6,SP                         | space for GetMouse + PtInRect
        MOVE.L  SP,-(SP)                        | push ptr for GetMouse
        _GetMouse                               | read final mouse position
        MOVE.L  0xE(A6),-(SP)                   | push slopRect
        _PtInRect                               | mouse inside slop area?
        TST.B   (SP)+                           | check result
        BNE.B   DRAGTHERGN_SKIP_3_OK            | yes -> keep result
        MOVE.L  #0x80008000,0x1E(A6)            | outside slop: cancel (0x8000,0x8000)
DRAGTHERGN_SKIP_3_OK:
        MOVEM.L (SP)+,D3-D5/A3                  | restore saved regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0x16,SP                        | strip 22 bytes of params
        JMP     (A0)                            | RTS
DRAGTHERGN_CONT_3:
        MOVE.L  (DragHook).w,D0                 | D0 = installed DragHook
DRAGTHERGN_EMPTY:
        BEQ.B   DRAGTHERGN_SKIP_4               | no hook -> just return
        MOVE.L  D0,A0                           | A0 = hook proc address
        JSR     (A0)                            | call subroutine via A0
DRAGTHERGN_SKIP_4:
        RTS                                     | return from DRAGTHERGN_SKIP_4

| ----------------------------------------------------------
| DRAGTHERGN_CONT_4 - mouse outside limitRect: check slopRect and toggle outline
DRAGTHERGN_CONT_4:
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  D4,-(SP)                        | push current mouse pt
        MOVE.L  14(A6),-(SP)                    | push slopRect
        _PtInRect                               | mouse inside slop area?
        TST.B   (SP)+                           | check result
        BNE.B   DRAGTHERGN_CONT_4_OK            | yes -> pin to limit edge
        TST     D5                              | outline drawn?
        BEQ.B   DRAGTHERGN_SKIP_2               | no -> just wait
        MOVEQ.L #0x0,D5                         | mark outline as erased
DRAGTHERGN_CONT_4_CONT:
        MOVE.L  A3,-(SP)                        | push outline region
        _PaintRgn                               | XOR the outline onto screen
        BRA.B   DRAGTHERGN_SKIP_2               | -> wait for next mouse event
DRAGTHERGN_CONT_4_OK:
        TST     D5                              | outline already drawn?
        BNE.B   DRAGTHERGN_OK_4                 | yes -> pin position
        MOVEQ.L #0x1,D5                         | mark outline as drawn
        BRA.B   DRAGTHERGN_CONT_4_CONT          | -> draw outline (XOR on)
DRAGTHERGN_OK_4:
        SUBQ.W  #0x4,SP                         | space for PinRect result
        MOVE.L  18(A6),-(SP)                    | push limitRect
        MOVE.L  D4,-(SP)                        | push current mouse pt
        _PinRect                                | clamp to rect edge
        MOVE.L  (SP)+,D4                        | D4 = pinned mouse position
        BRA.W   DRAGTHERGN_CONT                 | -> apply delta and move outline

| ----------------------------------------------------------
| InvalRgn -- _InvalRgn ($A927).
| Add a region to current window's updateRgn (mark as needing redraw).
| Pascal: procedure InvalRgn(badRgn: RgnHandle);
| D0 = 0 selects union mode; the shared INVALRGN_CONT body
| decides union vs subtract based on D0.
InvalRgn:
        MOVEQ.L #0x0,D0                         | D0 = 0 -> union (invalidate)

| INVALRGN_CONT -- -> InvalRgn/ValidRgn core.
INVALRGN_CONT:
        MOVEM.L D3-D5/A3,-(SP)                  | save regs
        MOVE    D0,D5                           | D5 = operation flag
        MOVE.L  (A5),A0                         | A0 = thePort ptr
        MOVE.L  (A0),A3                         | A3 = current port (window)
        MOVE.L  20(SP),D4                       | D4 = region handle param
        MOVE.L  8(A3),D3                        | D3 = port origin offset
        MOVE.L  D4,-(SP)                        | push region
        MOVE.L  D3,-(SP)                        | push offset
        BSR.W   BRINGTOFRONT_CONT_2             | negate (local-to-global)
        _OffsetRgn                              | convert region to global coords
        MOVE.L  updateRgn(A3),-(SP)             | push updateRgn
        MOVE.L  D4,-(SP)                        | push input region
        MOVE.L  updateRgn(A3),-(SP)             | push dest (updateRgn)
        TST     D5                              | union or diff?
        BNE.B   INVALRGN_CONT_EMPTY             | non-zero -> subtract (valid)
        _UnionRgn                               | updateRgn |= region
        BRA.B   INVALRGN_CONT_CONT              | -> convert back
INVALRGN_CONT_EMPTY:
        _DiffRgn                                | updateRgn -= region (validate)
INVALRGN_CONT_CONT:
        MOVE.L  D4,-(SP)                        | push input region
        MOVE.L  D3,-(SP)                        | push port origin (local-to-global)
        _OffsetRgn                              | restore region to local coords
INVALRGN_CONT_EXIT:
        MOVEM.L (SP)+,D3-D5/A3                  | restore saved regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from INVALRGN_CONT_EXIT

| ----------------------------------------------------------
| InvalRect -- _InvalRect ($A928).
| Add a rect to current window's updateRgn.
| Pascal: procedure InvalRect(badRect: Rect);
| Wraps the rect in a temp region and forwards to INVALRGN_CONT.
InvalRect:
        MOVEQ.L #0x0,D0                         | D0 = 0 -> invalidate
INVALRECT_CONT:
        MOVEM.L D2-D5/A3,-(SP)                  | save regs
        MOVE    D0,D5                           | D5 = operation flag
        _NewRgn                                 | allocate temp region (on stack)
        MOVE.L  (SP),D4                         | D4 = temp region handle
        MOVE.L  24(SP),-(SP)                    | push rect parameter
        _RectRgn                                | convert rect to region
        MOVE.L  D4,-(SP)                        | push temp region
        MOVE    D5,D0                           | restore operation flag
        BSR.B   INVALRGN_CONT                   | -> InvalRgn/ValidRgn core
        MOVE.L  D4,-(SP)                        | push temp region
        _DisposeRgn                             | free it
        BRA.B   INVALRGN_CONT_EXIT              | -> restore and return

| ----------------------------------------------------------
| ValidRgn -- _ValidRgn ($A929).
| Remove a region from current window's updateRgn.
| Pascal: procedure ValidRgn(goodRgn: RgnHandle);
ValidRgn:
        MOVEQ.L #-0x1,D0                        | D0 = -1 -> subtract (validate)
        BRA.B   INVALRGN_CONT                   | -> shared core

| ----------------------------------------------------------
| ValidRect -- _ValidRect ($A92A).
| Remove a rect from current window's updateRgn.
| Pascal: procedure ValidRect(goodRect: Rect);
ValidRect:
        MOVEQ.L #-0x1,D0                        | D0 = -1 -> subtract (validate)
        BRA.B   INVALRECT_CONT                  | -> shared rect-to-region wrapper

| ----------------------------------------------------------
| GrowWindow -- _GrowWindow ($A92B).
| Track mouse to resize a window; draws gray outline while tracking,
| returns new size on release (high word=height, low=width;
| 0=cancelled if size unchanged).
| Pascal: function GrowWindow(theWindow: WindowPtr; startPt: Point;
| sizeRect: Rect): LongInt;
GrowWindow:
        LINK    A6,#-0x1C                       | 28 bytes local vars
        MOVEM.L D3-D7/A3-A4,-(SP)               | save regs
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        MOVE.L  12(A6),D3                       | D3 = startPt
        MOVE.L  16(A6),A3                       | A3 = window
        BSR.W   HILITEWINDOW_CONT_3             | clip to GrayRgn above window
        PEA.L     -28(A6)                       | push local PenState buffer
        MOVE.L  (SP),-(SP)                      | dup for GetPenState
        _GetPenState                            | save pen state
        _PenNormal                              | reset pen
        MOVE    #0xE,-(SP)                      | patXor mode
        _PenMode                                | set XOR drawing
        PEA     DRAGPATTERN_SRC(PC)             | push ptr to 50% gray pattern
        _PenPat                                 | set gray pen pattern
        LEA.L   -0x8(A6),A4                     | A4 = local grow rect (in frame)
        MOVE.L  16(A3),(A4)                     | copy portRect.topLeft
        MOVE.L  20(A3),4(A4)                    | copy portRect.botRight
        MOVE.L  A4,-(SP)                        | push grow rect
        MOVE.L  8(A3),-(SP)                     | push port origin
        BSR.W   BRINGTOFRONT_CONT_2             | negate (local-to-global)
        _OffsetRect                             | convert grow rect to global coords
        BSR.W   GROWWINDOW_CONT                 | draw initial grow outline
        BSR.W   GROWWINDOW_CONT_3               | compute initial size -> D0
        MOVE.L  D0,D6                           | D6 = saved initial size
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  D3,-(SP)                        | push startPt
        MOVE.L  4(A4),-(SP)                     | push grow rect botRight
        BSR.W   DeltaPoint                      | compute startPt - botRight (anchor)
        MOVE.L  (SP)+,D5                        | D5 = anchor offset
INVALRECT_CONT_CONT:
        MOVE.L  D3,-(SP)                        | save last position
        BSR.W   GROWWINDOW_CONT_2               | compute mouse - anchor = new size
        MOVE.L  (SP),D0                         | D0 = saved last position
        MOVE.L  D3,-(SP)                        | push new position
        MOVE.L  D0,-(SP)                        | push old position
        BSR.W   DeltaPoint                      | compute delta = new - old
        MOVE.L  (SP)+,D7                        | D7 = position delta
        BEQ.B   GROWWINDOW_SKIP                 | zero delta -> no redraw
        BSR.B   GROWWINDOW_CONT                 | erase old outline (XOR off)
        ADD     D7,6(A4)                        | 6(A4) += D7
        SWAP    D7                              | get vertical delta
        ADD     D7,4(A4)                        | 4(A4) += D7
        BSR.B   GROWWINDOW_CONT                 | draw new outline (XOR on)
GROWWINDOW_SKIP:
        BSR.W   DRAGTHERGN_CONT_3               | call DragHook if installed
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | mouse still down?
        TST.B   (SP)+                           | check
        BNE.B   INVALRECT_CONT_CONT             | button down -> keep tracking
        BSR.B   GROWWINDOW_CONT                 | erase final outline
        BSR.B   GROWWINDOW_CONT_3               | compute final size -> D0
        CMP.L   D0,D6                           | same as initial size?
        BNE.B   GROWWINDOW_SKIP_EXIT            | no -> return new size
        MOVEQ.L #0x0,D0                         | cancelled (no change)
GROWWINDOW_SKIP_EXIT:
        MOVE.L  D0,20(A6)                       | store result size in caller's slot
        _SetPenState                            | restore original pen state
        BSR.W   RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D7/A3-A4               | restore saved regs
        UNLK    A6                              | tear down frame
GROWWINDOW_SKIP_CONT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xC,SP                         | strip 12 bytes of params
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GROWWINDOW_CONT - send wGrow message to WDEF (draw/erase grow outline)
| Passes grow rect (A4) as param. Preserves D3.
GROWWINDOW_CONT:
        MOVE.L  D3,-(SP)                        | save D3
        MOVEQ.L #0x5,D0                         | message = wGrow
        MOVE.L  A4,D3                           | param = ptr to grow rect
        BSR.W   MOVEWINDOW_OK                   | call WDEF(wGrow, rectPtr)
        MOVE.L  (SP)+,D3                        | restore D3
        RTS                                     | return from GROWWINDOW_CONT

| ----------------------------------------------------------
| GROWWINDOW_CONT_2 - read mouse, compute constrained new botRight for grow rect
| Reads mouse, applies anchor offset D5, pins size to sizeRect,
| computes new absolute position in D3.
GROWWINDOW_CONT_2:
        MOVE.L  4(A4),-(SP)                     | save current botRight
        SUBQ.W  #0x8,SP                         | space for GetMouse + DeltaPoint
        MOVE.L  SP,-(SP)                        | push ptr for GetMouse
        _GetMouse                               | read current mouse position
        MOVE.L  D5,-(SP)                        | push anchor offset
        BSR.W   DeltaPoint                      | compute mouse - anchor = new size
        MOVE.L  (SP)+,4(A4)                     | update grow rect.botRight
        BSR.B   GROWWINDOW_CONT_3               | compute size = botRight - topLeft
        MOVE.L  (SP),4(A4)                      | restore saved botRight
        MOVE.L  8(A6),-(SP)                     | push sizeRect
        MOVE.L  D0,-(SP)                        | push unconstrained size
        _PinRect                                | clamp to min/max size
        SWAP    D5                              | D5.w = horizontal anchor offset
        MOVE    (A4),D3                         | D3 = grow rect.top
        ADD     (SP)+,D3                        | add pinned height
        ADD     D5,D3                           | add vertical anchor offset
        SWAP    D3                              | move to high word
        SWAP    D5                              | restore D5
        MOVE    2(A4),D3                        | D3.w = grow rect.left
        ADD     (SP)+,D3                        | add pinned width
        ADD     D5,D3                           | add horizontal anchor offset
        RTS                                     | return from GROWWINDOW_CONT_2
GROWWINDOW_CONT_3:
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  4(A4),-(SP)                     | push botRight
        MOVE.L  (A4),-(SP)                      | push topLeft
        BSR.W   DeltaPoint                      | compute size = botRight - topLeft
        MOVE.L  (SP)+,D0                        | D0 = packed size (height:width)
        RTS                                     | return from GROWWINDOW_CONT_3

| ----------------------------------------------------------
| FindWindow -- _FindWindow ($A92C).
| Determine which window part contains a point.
| Pascal: function FindWindow(thePoint: Point;
| VAR whichWindow: WindowPtr): Integer;
| Returns: inDesk=0, inMenuBar=1, inSysWindow=2, inContent=3,
| inDrag=4, inGrow=5, inGoAway=6, inZoomIn=7, inZoomOut=8.
| Plus 1986 saves D1 in MOVEM (D1/D3/A3) and uses MBarHeight low-mem
| word; classic 1984 hardcodes 20 ($14<<16=$140000) and saves only
| D3/A3.
FindWindow:
        MOVEM.L D3/A3,-(SP)                     | save regs
        LEA.L     12(SP),A0                     | A0 = stack params
        MOVE.L  (A0)+,A1                        | A1 = VAR whichWindow ptr
        CLR.L   (A1)                            | whichWindow = nil initially
        MOVE.L  (A0)+,D3                        | D3 = thePoint (global coords)
        CLR     (A0)                            | partCode = 0 (inDesk)
        CMPI.L  #0x140000,D3                    | top y >= menubar height (20 << 16)?
        BGE.B   FINDWINDOW_NO                   | yes -> normal path
        MOVEQ.L #0x1,D0                         | inMenuBar
        BRA.B   FINDWINDOW_OK_CONT              | -> return
FINDWINDOW_NO:
        MOVE.L  (WindowList).w,A3               | A3 = first window in list
FINDWINDOW_LOOP:
        MOVE.L  A3,D0                           | end of list?
        BEQ.W   FINDWINDOW_OK_2                 | yes -> point hit no window
        TST.B   wVisible(A3)                    | window visible?
        BEQ.B   FINDWINDOW_SKIP                 | invisible -> skip
        CLR     -(SP)                           | space for PtInRgn result
        MOVE.L  D3,-(SP)                        | push test point
        MOVE.L  structRgn(A3),-(SP)             | push window's strucRgn
        _PtInRgn                                | point in window frame?
        TST.B   (SP)+                           | check result
        BEQ.B   FINDWINDOW_SKIP                 | miss -> next window
        MOVEQ.L #0x1,D0                         | message = wHit
        BSR.W   MOVEWINDOW_OK                   | ask WDEF which part
        TST     D0                              | partCode != 0?
        BNE.B   FINDWINDOW_OK                   | yes -> hit found
FINDWINDOW_SKIP:
        MOVE.L  nextWindow(A3),A3               | advance to next window
        BRA.B   FINDWINDOW_LOOP                 | loop

| ----------------------------------------------------------
| FINDWINDOW_OK
| FINDWINDOW_OK - point hit a window: translate WDEF result to FindWindow code
| WDEF wHit returns: 0=miss, 1=content, 2=drag, 3=grow, 4+=go-away/zoom
| Called during boot (1,323 times in 30s trace).
FINDWINDOW_OK:
        MOVE.L  12(SP),A0                       | A0 = VAR whichWindow ptr
        MOVE.L  A3,(A0)                         | return hit window
        TST     windowKind(A3)                  | check windowKind
        BPL.B   FINDWINDOW_CONT                 | >= 0 -> application/dialog window
        MOVEQ.L #0x2,D0                         | inSysWindow (system/DA window)
FINDWINDOW_OK_CONT:
        BRA.B   FINDWINDOW_CONT_EXIT            | store partCode and return
FINDWINDOW_CONT:
        CMPI    #0x2,D0                         | WDEF code 2 = drag bar?
        BLT.B   FINDWINDOW_INCONTENT            | < 2 (content) -> inContent (3)
        BGT.B   FINDWINDOW_CONT_CONT            | > 2 (grow/goaway) -> add 2
        MOVEQ.L #0x4,D0                         | exactly 2 -> inDrag (4)
        BRA.B   FINDWINDOW_CONT_EXIT            | -> store result
FINDWINDOW_CONT_CONT:
        ADDQ.W   #0x2,D0                        | translate WDEF code: grow=5, goAway=6
        BRA.B    FINDWINDOW_CONT_EXIT           | store result
FINDWINDOW_INCONTENT:
        MOVEQ    #0x3,D0                        | inContent (3)
FINDWINDOW_CONT_EXIT:
        MOVE    D0,20(SP)                       | store partCode in return slot
        MOVEM.L (SP)+,D3/A3                     | restore regs
        BRA.W   STRIP_2PARAMS_RTS               | -> strip params and return

| ----------------------------------------------------------
| FINDWINDOW_OK_2
| FINDWINDOW_OK_2 - no window hit: check if DeskHook claims clicks
| Called during boot (1,359 times in 30s trace).
FINDWINDOW_OK_2:
        MOVE.L  (DeskHook).w,D0                 | DeskHook installed?
        BEQ.B   FINDWINDOW_CONT_EXIT            | no -> return inDesk (0)
        MOVEQ.L #0x2,D0                         | yes -> return inSysWindow (2)
        BRA.B   FINDWINDOW_CONT_EXIT            | -> store result

| ----------------------------------------------------------
| DrawGrowIcon -- _DrawGrowIcon ($A904).
| Draws the size box in a window's lower-right corner by sending
| wGrow+1=6 message to the WDEF.
| Pascal: procedure DrawGrowIcon(theWindow: WindowPtr);
DrawGrowIcon:
        MOVEM.L D4/A3,-(SP)                     | save regs
        MOVE.L  12(SP),A3                       | A3 = window
        BSR.W   GetSetWPort                     | save port, switch to WMgr
        MOVEQ.L #0x6,D0                         | message 6 = draw grow icon
        BSR.W   MOVEWINDOW_OK                   | call WDEF
        BSR.W   RestorePort                     | restore original port
        MOVEM.L (SP)+,D4/A3                     | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from DrawGrowIcon
