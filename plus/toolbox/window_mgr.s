| Window Manager
|
| Manages overlapping windows on the Mac Plus desktop.
| Handles window creation, movement, sizing, visibility, update regions,
| and desktop painting. Also includes Desk Manager (desk accessories)
| and the portion of Menu Manager that lives in this ROM section.
|
| Hardware interaction:
| Screen buffer access for DragGrayRgn rubber-banding
| VBL task for window update scheduling
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
| References:
| Inside Macintosh Vol I, Ch 9: The Window Manager (pp 273-328)
| Inside Macintosh Vol I, Ch 13: The Desk Manager (pp 433-448)

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
        RTS                                     | return to caller

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
        BRA     STRIP_2PARAMS_RTS               | -> strip 2 params and return

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
        RTS                                     | return to caller

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
        BSR.B   PAINTONE_CONT_2                 | paint desktop pattern
PAINTONE_EXIT:
        MOVEM.L (SP)+,D3-D4/A2-A3               | restore regs
        BRA     STRIP_2PARAMS_RTS               | -> strip params

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
        BSR     MOVEWINDOW_CONT_2               | send wDraw to WDEF (draw frame)
        BSR     PAINTBEHIND_EMPTY               | allocate temp region
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
        BSR     GetSetWPort                     | save current port, set WMgr port
        MOVE.L  (WMgrPort).w,A3                 | A3 = WMgrPort
        MOVE.L  CLIPRGN(A3),D3                  | D3 = WMgr clipRgn handle
        RTS                                     | return to caller

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
        BNE.B   PAINTONE_ERR                    | empty -> abort painting
        RTS                                     | not empty, continue caller

| ----------------------------------------------------------
|
| PAINTONE_ERR - PAINTONE_SKIP early exit: pop caller's return address, go to epilogue
|
| Called during boot.
PAINTONE_ERR:
        ADDQ.W  #0x4,SP                         | discard PAINTONE_SKIP's return address
        BRA.B   PAINTONE_EXIT                   | -> PaintOne epilogue

| ----------------------------------------------------------
|
| PAINTONE_CONT_2 - paint desktop: call DeskHook or fill with DeskPattern
|
| Clips above all windows (nil param = entire desktop), then
| calls application's DeskHook if installed, else fills with pattern.
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
| PAINTONE_NO_4 - default desktop paint: fill WMgr portRect with desk pattern
|
| Called during boot.
PAINTONE_NO_4:
        PEA.L   PORTRECT(A3)                    | push WMgr port rectangle
        PEA.L   (DeskPattern).w                 | push desktop pattern (from PRAM)
        _FillRect                               | fill desktop with pattern
        RTS                                     | return to caller

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
        PEA.L   PORTRECT(A3)                    | push WMgr port rect
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
        BRA     STRIP_2PARAMS_RTS               | -> strip 2 params and return

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
| Called during boot.
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
        RTS                                     | return to caller

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
        ST.B    (SaveUpdate).w                  | re-enable update saving
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
| Only acts if visibility is actually changing (XOR test)
| Called during boot.
ShowHide:
        MOVEM.L D3-D4/A1/A3,-(SP)               | save regs
        MOVE.L  0x16(SP),A3                     | A3 = window
        MOVE.B  0x14(SP),D3                     | D3 = desired visibility
        MOVE.B  wVisible(A3),D0                 | D0 = current visibility
        EOR.B   D3,D0                           | test if changing
        LSR     #0x1,D0                         | bit 0 -> carry
        BCC.B   SHOWHIDE_SKIP                   | no change -> skip
        BSR.B   GetSetWPort                     | save port, switch to WMgr
        MOVE.L  A3,-(SP)                        | push window
        _SaveOld                                | snapshot current regions
        MOVE.B  D3,wVisible(A3)                 | set new visibility flag
        BSR     MOVEWINDOW_EMPTY                | recalc regions (empty if hiding)
        MOVE.L  A3,-(SP)                        | push window
        ST.B    -(SP)                           | fUpdate = true
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
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| RestorePort - restore the port saved by GetSetWPort
|
| Called during boot.
RestorePort:
        MOVE.L  D4,-(SP)                        | push saved port from D4
        _SetPort                                | restore it as current port
        RTS                                     | return to caller

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
| _CheckUpDate ($A911)
|
| _CheckUpdate ($A911): find window needing update (for GetNextEvent)
| Scans window list front-to-back for first window with non-empty updateRgn
| Returns: true + event filled if update needed, false otherwise
CheckUpDate:
        LINK    A6,#-0x8                        | local vars
        MOVE.L  A3,-(SP)                        | save A3
        CLR     0xC(A6)                         | result = false initially
        SUBQ.W  #0x4,SP                         | space for GetPort result
        MOVE.L  A7,-(SP)                        | push pointer to local var
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
        MOVE.L  CLIPRGN(A3),-(SP)               | push window's clipRgn
        PEA.L   PORTRECT(A3)                    | push portRect
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
        RTS                                     | return to caller

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

| ----------------------------------------------------------
|
| CHECKUPDATE_CONT_2 - allocate a GrafPort-sized block (108 bytes) and open it
|
| CHECKUPDATE_EMPTY entry: allocate D0 bytes and open as port.
| CHECKUPDATE_CONT_3 entry: open pre-allocated A0 as port.
| Returns with A3 = port pointer.
| Called during boot.
CHECKUPDATE_CONT_2:
        MOVEQ.L #0x6C,D0                        | 108 = sizeof(GrafPort)
| CHECKUPDATE_EMPTY -- allocate and zero.
CHECKUPDATE_EMPTY:
        _NewPtr                                 | allocate D0 bytes, A0 = ptr
| CHECKUPDATE_CONT_3 -- open it as GrafPort (A3 = port).
CHECKUPDATE_CONT_3:
        MOVE.L  A0,A3                           | A3 = port pointer
        MOVE.L  A0,-(SP)                        | push port for OpenPort
        _OpenPort                               | initialize as GrafPort
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _InitWindows ($A912)
| -> (initializes Window Manager)
|
| _InitWindows ($A912): initialize the Window Manager
| Creates WMgrPort, GrayRgn (desktop), paints desktop pattern
InitWindows:
        MOVEM.L D3-D5/A3-A4,-(SP)               | save regs
        MOVEQ.L #0x7,D0                         | bit 7
        BSET    D0,(DSWndUpdate).w              | enable DS window updates
        BSET    D0,(AlarmState).w               | enable alarm
        CLR.B   (WWExist).w                     | no windows yet
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
| draw rounded screen border and prepare GrayRgn
        LEA.L   PORTRECT(A3),A0                 | A0 = screen rect
        MOVE.L  A0,-(SP)                        | push for FrameRoundRect (below)
        MOVE.L  A0,-(SP)                        | push for FrameRoundRect (dup)
        LEA.L   (scratch8).w,A4                 | A4 = scratch rect
        MOVE.L  A4,A1                           | A1 = dest for copy
        MOVE.L  (A0)+,(A1)+                     | copy portRect.topLeft to scratch
        MOVE.L  (A0),(A1)                       | copy portRect.botRight to scratch
        MOVE.L  A4,-(SP)                        | push scratch rect
        MOVE.L  #0xFFFDFFFD,-(SP)               | inset by -3,-3 (expand 3 pixels)
        _InsetRect                              | expand scratch rect for border
        MOVE.L  #0x30003,-(SP)                  | pen size 3x3
        _PenSize                                | set thick pen for border
        MOVE.L  A4,-(SP)                        | push expanded rect
        MOVE.L  #0x160016,-(SP)                 | corner radius 22x22
        _FrameRoundRect                         | draw rounded screen border
        _PenNormal                              | restore pen to 1x1
        JSR     CalcMBHeight(PC)                | calculate menu bar height
        JSR     DELETEMENU_CONT_4(PC)           | draw menu bar separator line
| build GrayRgn: rounded screen minus menu bar
        BSR     PAINTBEHIND_EMPTY               | allocate region for GrayRgn
        MOVE.L  (SP)+,D5                        | D5 = GrayRgn handle
        MOVE.L  D5,(GrayRgn).w                  | store global GrayRgn
        _HidePen                                | suppress drawing during record
        _OpenRgn                                | start recording region
        MOVE.L  #0x100010,-(SP)                 | corner radius 16x16
        _FrameRoundRect                         | record rounded rect into region
        MOVE.L  D5,-(SP)                        | push GrayRgn
        _CloseRgn                               | GrayRgn = rounded screen shape
        _ShowPen                                | re-enable drawing
| subtract menu bar from GrayRgn (menu bar is in clipRgn)
        MOVE.L  D5,-(SP)                        | push GrayRgn
        MOVE.L  CLIPRGN(A3),-(SP)               | push clipRgn (menu bar area)
        MOVE.L  D5,-(SP)                        | push dest
        _DiffRgn                                | GrayRgn = screen minus menu bar
| paint desktop
        MOVE.L  D5,-(SP)                        | push GrayRgn
        _SetClip                                | clip to desktop area
        PEA.L   (DeskPattern).w                 | push desktop pattern
        _FillRect                               | fill desktop with pattern
        _ShowCursor                             | show the cursor
| initialize window list and globals
        CLR.L   (WindowList).w                  | no windows yet
        BSR     PAINTBEHIND_EMPTY               | allocate SaveVisRgn
        MOVE.L  (SP)+,(SaveVisRgn).w            | store SaveVisRgn handle
        CLR.L   (GhostWindow).w                 | no ghost window
        LEA.L   (CurActivate).w,A0              | A0 = CurActivate
        CLR.L   (A0)+                           | CurActivate = nil
        CLR.L   (A0)+                           | CurDeactive = nil
        MOVEM.L (SP)+,D3-D5/A3-A4               | restore regs
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| INITWINDOWS_EMPTY - NewWindow with caller-supplied storage
|
| Strips high byte from pointer (24-bit addressing), opens as port.
| Called during boot.
INITWINDOWS_EMPTY:
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A0                           | A0 = wStorage pointer
        BSR     CHECKUPDATE_CONT_3              | open it as GrafPort (A3 = port)
        BRA.B   NEWWINDOW_CONT                  | -> continue NewWindow setup

| ----------------------------------------------------------
|
| _NewWindow ($A913)
| stack: boundsRect, title, visible, procID, behind, goAway, refCon -> WindowPtr
|
| _NewWindow ($A913): create a new window
| Pascal: function NewWindow(wStorage: Ptr; boundsRect: Rect;
| title: Str255; visible: BOOLEAN; procID: INTEGER;
| behind: WindowPtr; goAwayFlag: BOOLEAN; refCon: LongInt): WindowPtr;
NewWindow:
        LINK    A6,#0x0                         | no local vars
        MOVEM.L D3-D5/A2-A4,-(SP)               | save regs
        BSR     GetSetWPort                     | save current port, switch to WMgr port
        MOVE.L  0x1E(A6),D0                     | D0 = wStorage (caller-supplied or nil)
        BNE.B   INITWINDOWS_EMPTY               | non-nil: use caller's storage ->
| allocate window record in application heap
        MOVEQ.L #0x0,D0                         | clear high word of size
        MOVE    #0x9C,D0                        | 156 bytes = sizeof(WindowRecord)
        BSR     CHECKUPDATE_EMPTY               | allocate and zero
NEWWINDOW_CONT:
        MOVE.L  A3,0x22(A6)                     | store WindowPtr as return value
        MOVE    #0x1,TXFONT(A3)                 | set font to system font (1)
        MOVE.L  0x1A(A6),A2                     | A2 = boundsRect parameter
        MOVE.L  (A2),-(SP)                      | push boundsRect.topLeft
        _MovePortTo                             | position port origin
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  0x4(A2),-(SP)                   | push boundsRect.botRight
        MOVE.L  (A2),-(SP)                      | push boundsRect.topLeft
        BSR     DeltaPoint                      | compute size = botRight - topLeft
        _PortSize                               | set port size to window dimensions
        MOVE.L  (WMgrPort).w,-(SP)              | push WMgr port
        _SetPort                                | switch back to WMgr port
| initialize WindowRecord fields after GrafPort (offset +108)
        LEA.L   windowKind(A3),A2               | A2 = ptr to windowKind field
        MOVE    #0x8,(A2)+                      | windowKind = 8 (userKind)
        TST.B   0x14(A6)                        | visible parameter?
        SNE.B   (A2)+                           | wVisible = true/false
        CLR.B   (A2)+                           | hilited = false
        TST.B   0xC(A6)                         | goAway parameter?
        SNE.B   (A2)+                           | goAwayFlag = true/false
        CLR.B   (A2)+                           | spareFlag = false
| allocate 3 regions: strucRgn, contRgn, updateRgn
        MOVEQ.L #0x2,D3                         | loop counter (3 regions)
NEWWINDOW_LOOP:
        BSR     PAINTBEHIND_EMPTY               | allocate new empty region
        MOVE.L  (SP)+,(A2)+                     | store handle in WindowRecord
        DBF     D3,NEWWINDOW_LOOP               | loop 3 times
| load WDEF resource
        MOVE    0x12(A6),D3                     | D3 = procID parameter
        LSR     #0x4,D3                         | WDEF resource ID = procID / 16
NEWWINDOW_RETRY:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57444546,-(SP)               | push 'WDEF' resource type
        MOVE    D3,-(SP)                        | push WDEF resource ID
        MOVE    #-0x1,(ROMMapInsert).w          | search ROM map first
        _GetResource                            | load WDEF
        MOVEQ.L #0x0,D3                         | clear D3 for retry check
        MOVE.L  (SP)+,(A2)                      | store WDEF handle in windowDef
        BEQ.B   NEWWINDOW_RETRY                 | nil = not found, retry
| store variation code in low byte of windowDef handle
        MOVEQ.L #0xF,D3                         | mask for low 4 bits
        AND     0x12(A6),D3                     | D3 = procID mod 16 (variation)
        MOVE.B  D3,(A2)                         | store in low byte of handle
        ADDQ.W  #0x4,A2                         | advance past windowDef
        CLR.L   (A2)+                           | wDataHandle = nil
| create title string
        MOVE.L  0x16(A6),D3                     | D3 = title string pointer
        CLR.L   -(SP)                           | space for NewString result
        MOVE.L  D3,-(SP)                        | push title string
        _NewString                              | copy string to handle
        MOVE.L  (SP)+,(A2)+                     | store wTitleHandle
| measure title width for drawing
        CLR     -(SP)                           | space for StringWidth result
        MOVE.L  D3,-(SP)                        | push title string
        _StringWidth                            | measure width in pixels
        MOVE    (SP)+,(A2)+                     | store wTitleWidth
| clear remaining fields
        CLR.L   (A2)+                           | controlList = nil
        CLR.L   (A2)+                           | nextWindow = nil
        CLR.L   (A2)+                           | windowPic = nil
        MOVE.L  0x8(A6),(A2)+                   | refCon = caller's value
| send wNew message to WDEF and calculate regions
        MOVEQ.L #0x3,D0                         | wNew message
        BSR     MOVEWINDOW_OK                   | call WDEF(wNew)
        BSR     MOVEWINDOW_EMPTY                | calculate strucRgn/contRgn via wCalcRgns
| insert window into window list
        MOVE.L  0xE(A6),D5                      | D5 = behind parameter
        BTST    #0x0,D5                         | behind = -1 (in front of all)?
        BNE.B   NEWWINDOW_OK                    | yes -> insert at front
        TST.L   (WindowList).w                  | any windows exist?
        BEQ.B   NEWWINDOW_OK                    | no -> insert at front
        MOVE.L  A3,-(SP)                        | push new window
        MOVE.L  D5,-(SP)                        | push behind window
        BSR     INSERT_WINDOW                   | insert after behind window
| paint new window and recalculate visibility
NEWWINDOW_EXIT:
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn as clobbered area
        _PaintOne                               | paint window frame
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn
        _CalcVBehind                            | recalc visRgn for windows behind
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D5/A2-A4               | restore regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0x1A,SP                        | strip 26 bytes of params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| NEWWINDOW_OK
|
| NEWWINDOW_OK - NewWindow: insert at front of window list (behind=-1 or empty list)
| Called during boot.
NEWWINDOW_OK:
        TST.B   wVisible(A3)                    | new window visible?
        BEQ.B   NEWWINDOW_NO                    | no -> just link into list
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get current front window
        MOVE.L  (SP)+,D0                        | D0 = old front window
        BEQ.B   NEWWINDOW_SKIP                  | no old front -> skip deactivate
        BSR     CLOSEWINDOW_CONT                | deactivate + unhighlight old front
NEWWINDOW_SKIP:
        MOVE.B  #0x1,0x6F(A3)                   | set hilited flag on new window
        MOVE.L  A3,(CurActivate).w              | schedule activate event for it
NEWWINDOW_NO:
        MOVE.L  (WindowList).w,nextWindow(A3)   | link old list head as next
        MOVE.L  A3,(WindowList).w               | new window becomes list head
        BRA.B   NEWWINDOW_EXIT                  | -> paint and return

| ----------------------------------------------------------
|
| NEWWINDOW_CONT_2 - cancel pending activate/deactivate events for window A3
|
| If window A3 matches CurActivate or CurDeactive, invalidates that
| entry by setting bit 7 (high byte flag). This prevents stale events
| for a window being closed.
| Called during boot.
NEWWINDOW_CONT_2:
        LEA.L   (CurActivate).w,A0              | A0 = ptr to CurActivate
        MOVE.L  A3,D0                           | D0 = window being closed
        BSR.B   NEWWINDOW_CONT_3                | check/cancel CurActivate
        ADDQ.W  #0x4,A0                         | advance to CurDeactive
| NEWWINDOW_CONT_3 -- check/cancel CurActivate.
NEWWINDOW_CONT_3:
        MOVE.L  (A0),D1                         | D1 = pending window ptr
        EOR.L   D0,D1                           | compare with target
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit address
        BNE.B   NEWWINDOW_SKIP_2                | different window -> skip
        BSET    #0x7,(A0)                       | same window: invalidate entry
NEWWINDOW_SKIP_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _CloseWindow ($A92D)
| stack: window -> (disposes of window)
|
| _CloseWindow ($A92D): close and dispose a window's data structures
| Pascal: procedure CloseWindow(theWindow: WindowPtr);
| Hides window, kills controls, sends wDispose to WDEF, frees regions
CloseWindow:
        MOVEM.L D3-D4/A3,-(SP)                  | save regs
        MOVE.L  0x10(SP),A3                     | A3 = window to close
        BSR     GetSetWPort                     | save port, switch to WMgr port
        BSR.B   NEWWINDOW_CONT_2                | generate deactivate if front window
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get front window (for reactivation)
        MOVE.L  A3,-(SP)                        | push window to close
        _KillControls                           | dispose all controls in this window
        MOVEQ.L #0x4,D0                         | wDispose message
        BSR     MOVEWINDOW_OK                   | send wDispose to WDEF
        MOVE.L  A3,-(SP)                        | push window for ShowHide
        CLR     -(SP)                           | visible = false
        _ShowHide                               | hide the window
        MOVE.L  A3,-(SP)                        | push window for DeleteWindow
        BSR     DeleteWindow                    | remove from window list
| dispose window's allocated structures
        MOVE.L  wTitleHandle(A3),A0             | title string handle
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
| check if this was the front window (saved FrontWindow result on stack)
        CMPA.L  (SP)+,A3                        | was this window the front?
        BNE.B   CLOSEWINDOW_NO                  | no -> just restore port
        MOVE    windowKind(A3),(CurDeKind).w    | save kind for deactivate event
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | find new front window
        BSR     SELECTWINDOW_NO                 | activate the new front window
CLOSEWINDOW_NO:
        CMPA.L  D4,A3                           | was window the saved port?
        BEQ.B   CLOSEWINDOW_SKIP_2              | yes -> don't restore (it's gone)
        BSR     RestorePort                     | restore original port
CLOSEWINDOW_SKIP_2:
        MOVEM.L (SP)+,D3-D4/A3                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| CLOSEWINDOW_CONT - deactivate a window: unhighlight it and schedule deactivate event
|
| D0 = window to deactivate on entry.
| Called during boot.
CLOSEWINDOW_CONT:
        MOVE.L  D0,-(SP)                        | save window ptr
        MOVE.L  D0,-(SP)                        | push window for HiliteWindow
        CLR     -(SP)                           | fHilite = false (unhighlight)
        _HiliteWindow                           | remove highlight
        MOVE.L  (SP)+,D0                        | restore window ptr
        TST.L   (CurDeactive).w                 | deactivate already pending?
        BGT.B   CLOSEWINDOW_SKIP_3              | yes -> don't overwrite
        MOVE.L  D0,A0                           | A0 = window
        MOVE    windowKind(A0),(CurDeKind).w    | save kind for deactivate event
        MOVE.L  D0,(CurDeactive).w              | schedule deactivate event
CLOSEWINDOW_SKIP_3:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _DisposeWindow ($A914)
| stack: window -> (disposes of window and its storage)
|
| _DisposeWindow ($A914): close window and free its storage
| Pascal: procedure DisposeWindow(theWindow: WindowPtr);
| Calls CloseWindow then deallocates the WindowRecord memory
| Called during boot.
DisposeWindow:
        MOVE.L  0x4(SP),-(SP)                   | push window for CloseWindow
        _CloseWindow                            | close and free internal structures
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = window storage pointer
        _DisposePtr                             | free the WindowRecord block
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
        MOVE.B  #0x1,-(SP)                      | visible = true
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
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| HIDEWINDOW_EMPTY - no front window: discard nil FrontWindow result
|
| Called during boot.
HIDEWINDOW_EMPTY:
        ADDQ.W  #0x4,SP                         | discard nil FrontWindow result
        BRA.B   HIDEWINDOW_DONE                 | -> strip param and return

| ----------------------------------------------------------
|
| _GetWRefCon ($A917): return window's refCon value
| Pascal: function GetWRefCon(theWindow: WindowPtr): LongInt;
|
GetWRefCon:
        MOVE    #0x98,D1                        | offset 0x98 = refCon field
GETWREFCON_CONT:
        MOVE.L  (SP)+,A0                        | A0 = return address
        MOVE.L  (SP)+,A1                        | A1 = window pointer
        MOVE.L  0x0(A1,D1.W),(SP)               | replace stack param with field value
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| _SetWRefCon ($A918): set window's refCon value
| Pascal: procedure SetWRefCon(theWindow: WindowPtr; data: LongInt);
|
SetWRefCon:
        MOVE    #0x98,D1                        | offset 0x98 = refCon field
SETWREFCON_CONT:
        MOVE.L  (SP)+,A0                        | A0 = return address
        MOVE.L  (SP)+,D0                        | D0 = new value
        MOVE.L  (SP)+,A1                        | A1 = window pointer
        MOVE.L  D0,0x0(A1,D1.W)                 | store value into field
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| _SetWindowPic ($A92E): set window's auto-draw picture handle
| Pascal: procedure SetWindowPic(theWindow: WindowPtr; pic: PicHandle);
|
SetWindowPic:
        MOVE    #0x94,D1                        | offset 0x94 = windowPic field
        BRA.B   SETWREFCON_CONT                 | -> generic setter

| ----------------------------------------------------------
|
| _GetWindowPic ($A92F): return window's auto-draw picture handle
| Pascal: function GetWindowPic(theWindow: WindowPtr): PicHandle;
|
GetWindowPic:
        MOVE    #0x94,D1                        | offset 0x94 = windowPic field
        BRA.B   GETWREFCON_CONT                 | -> generic getter

| ----------------------------------------------------------
|
| _GetWTitle ($A919): copy window title into caller's buffer
| Pascal: procedure GetWTitle(theWindow: WindowPtr; VAR title: Str255);
|
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
|
| _SetWTitle ($A91A): change a window's title
| Pascal: procedure SetWTitle(theWindow: WindowPtr; title: Str255);
| Saves old strucRgn, updates title, recalculates regions,
| repaints if structure changed (title may change frame size)
|
SetWTitle:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save regs
        MOVE.L  0x18(SP),D5                     | D5 = new title string
        MOVE.L  0x1C(SP),A3                     | A3 = window
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVE.L  structRgn(A3),A0                | A0 = strucRgn handle
        _HandToHand                             | copy strucRgn (old snapshot)
        MOVE.L  A0,D3                           | D3 = old strucRgn copy
        MOVE.L  wTitleHandle(A3),D0             | D0 = existing title handle
        BEQ.B   SETWTITLE_SKIP                  | nil -> skip (shouldn't happen)
        MOVE.L  D0,-(SP)                        | push title handle
        MOVE.L  D5,-(SP)                        | push new title string
        _SetString                              | update title handle contents
        SUBQ.W  #0x2,SP                         | space for StringWidth result
        MOVE.L  D5,-(SP)                        | push new title
        _StringWidth                            | measure new title width
        MOVE    (SP)+,wTitleWidth(A3)           | store new titleWidth
        BSR     MOVEWINDOW_EMPTY                | recalculate strucRgn/contRgn
| check if structure region changed (title may affect frame size)
        CLR     -(SP)                           | space for EqualRgn result
        MOVE.L  structRgn(A3),-(SP)             | push new strucRgn
        MOVE.L  D3,-(SP)                        | push old strucRgn
        _EqualRgn                               | compare regions
        MOVE    (SP)+,D0                        | D0 = result
        BEQ.B   SETWTITLE_NO                    | not equal -> repaint behind
| regions equal: just repaint this window's frame
        BSR.B   SETWTITLE_CONT                  | subtract content from old strucRgn
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push frame-only region
        _PaintOne                               | repaint frame
        BRA.B   SETWTITLE_SKIP                  | -> cleanup

| ----------------------------------------------------------
|
| SETWTITLE_NO - strucRgn changed: repaint old+new area and windows behind
|
SETWTITLE_NO:
        MOVE.L  structRgn(A3),-(SP)             | push new strucRgn
        MOVE.L  D3,-(SP)                        | push old strucRgn
        MOVE.L  D3,-(SP)                        | push dest
        _UnionRgn                               | D3 = old union new (all affected)
        BSR.B   SETWTITLE_CONT                  | subtract content from combined area
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push affected area
        _PaintBehind                            | repaint exposed windows behind
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push affected area
        _CalcVBehind                            | recalculate visRgns behind
SETWTITLE_SKIP:
        MOVE.L  D3,-(SP)                        | push old strucRgn copy
        _DisposeRgn                             | free it
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore regs
SETWTITLE_EXIT:
        BRA     STRIP_2PARAMS_RTS               | -> strip 2 params and return

| ----------------------------------------------------------
|
| SETWTITLE_CONT - subtract content region from D3 (leaving frame-only area)
|
SETWTITLE_CONT:
        MOVE.L  D3,-(SP)                        | push region
        MOVE.L  contRgn(A3),-(SP)               | push content region
        MOVE.L  D3,-(SP)                        | push dest
        _DiffRgn                                | D3 = D3 minus contRgn (frame only)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _DeltaPoint ($A94F)
|
| _DeltaPoint ($A94F): compute difference between two points on stack
| Stack: retAddr, pt1(4 bytes), pt2(4 bytes) -> result overwrites pt2
| result.v = pt2.v - pt1.v, result.h = pt2.h - pt1.h
| Called during boot.
DeltaPoint:
        MOVE    0x8(SP),D0                      | D0 = pt2.v
        SUB     0x4(SP),D0                      | D0 = pt2.v - pt1.v
        MOVE    D0,0xC(SP)                      | store delta.v in result slot
        MOVE    0xA(SP),D0                      | D0 = pt2.h
        SUB     0x6(SP),D0                      | D0 = pt2.h - pt1.h
        MOVE    D0,0xE(SP)                      | store delta.h in result slot
        BRA.B   SETWTITLE_EXIT                  | -> strip 2 params and return

| ----------------------------------------------------------
|
| DELTAPOINT_CONT - move window to new position D0 (packed point)
|
| Computes offset from current portRect origin to new position,
| then offsets strucRgn, contRgn, updateRgn, and portBounds by delta.
| D0 = new origin as packed point. D3 = computed offset on exit.
DELTAPOINT_CONT:
        MOVE.L  A4,-(SP)                        | push strucRgn handle for OffsetRgn
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  D0,-(SP)                        | push new position
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  PORTRECT(A3),-(SP)              | push current portRect.topLeft
        MOVE.L  PORTBOUNDS(A3),-(SP)            | push portBounds.topLeft
        BSR.B   DeltaPoint                      | delta1 = portRect - portBounds
        BSR.B   DeltaPoint                      | delta2 = newPos - delta1
        MOVE.L  (SP),D3                         | D3 = final offset for regions
        _OffsetRgn                              | offset strucRgn
        MOVE.L  contRgn(A3),-(SP)               | push contRgn
        MOVE.L  D3,-(SP)                        | push offset
        _OffsetRgn                              | offset contRgn
        MOVE.L  updateRgn(A3),-(SP)             | push updateRgn
        MOVE.L  D3,-(SP)                        | push offset
        _OffsetRgn                              | offset updateRgn
        PEA.L   PORTBOUNDS(A3)                  | push portBounds rect
        MOVE.L  D3,-(SP)                        | push offset (negated by BRINGTOFRONT_CONT_2)
        BSR     BRINGTOFRONT_CONT_2             | negate offset for bounds
        _OffsetRect                             | offset portBounds (reversed)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _MoveWindow ($A91B)
| stack: window, h, v, front -> (repositions)
|
| _MoveWindow ($A91B): move a window to a new screen position
| Pascal: procedure MoveWindow(theWindow: WindowPtr; hGlobal, vGlobal: INTEGER;
| front: BOOLEAN);
| Optimizes by using CopyBits to blit existing pixels, then painting only
| newly exposed areas
MoveWindow:
        MOVEM.L D3-D6/A3-A4,-(SP)               | save regs
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVE.L  0x22(SP),A3                     | A3 = window
        BSR     HILITEWINDOW_CONT_3             | clip to GrayRgn
        BSR     PAINTBEHIND_EMPTY               | allocate temp region
        MOVE.L  (SP)+,D5                        | D5 = temp region (visible old area)
| compute visible portion of old strucRgn (for CopyBits optimization)
        MOVE.L  structRgn(A3),A4                | A4 = strucRgn handle
        MOVE.L  A4,-(SP)                        | push strucRgn
        MOVE.L  (WMgrPort).w,A0                 | get WMgr port
        MOVE.L  0x1C(A0),-(SP)                  | push WMgr clipRgn
        MOVE.L  D5,-(SP)                        | push dest
        _SectRgn                                | D5 = visible old structure area
        MOVE.L  A4,A0                           | A0 = strucRgn handle
        _HandToHand                             | copy old strucRgn
        MOVE.L  A0,D6                           | D6 = old strucRgn copy
| move window regions to new position
        MOVE.L  0x1E(SP),D0                     | D0 = new h,v packed as point
        BSR.B   DELTAPOINT_CONT                 | offset all regions; D3 = delta
| offset the visible-old-area region to new position
        MOVE.L  D5,-(SP)                        | push visible old area
        MOVE.L  D3,-(SP)                        | push delta offset
        _OffsetRgn                              | shift to new position
| optionally bring to front
        TST.B   0x1C(SP)                        | front parameter?
        BEQ.B   MOVEWINDOW_SKIP                 | no -> skip
        MOVE.L  (GrayRgn).w,-(SP)               | push desktop region
        _SetClip                                | clip to full desktop
| CopyBits to blit window pixels from old to new position
MOVEWINDOW_SKIP:
        MOVE.L  (WMgrPort).w,A0                 | get WMgr port
        PEA.L   0x2(A0)                         | push srcBits (screen portBits)
        MOVE.L  (SP),-(SP)                      | push dstBits (same screen)
        MOVE.L  D6,A0                           | A0 = old strucRgn copy
        MOVE.L  (A0),A0                         | dereference
        PEA.L   0x2(A0)                         | push srcRect (old bounds)
        MOVE.L  (A4),A0                         | dereference new strucRgn
        PEA.L   0x2(A0)                         | push dstRect (new bounds)
        CLR     -(SP)                           | srcCopy transfer mode
        MOVE.L  D5,-(SP)                        | push maskRgn (visible old area)
        _CopyBits                               | blit window pixels
| compute newly exposed area at new position
        MOVE.L  A4,-(SP)                        | push new strucRgn
        MOVE.L  D5,-(SP)                        | push blitted area
        MOVE.L  D5,-(SP)                        | push dest
        _DiffRgn                                | D5 = new area not covered by blit
| repaint windows behind at old position
        MOVE.L  nextWindow(A3),-(SP)            | push next window
        MOVE.L  D6,-(SP)                        | push old strucRgn
        _PaintBehind                            | repaint exposed area at old pos
| optionally select (bring to front)
        TST.B   0x1C(SP)                        | front parameter?
        BEQ.B   MOVEWINDOW_SKIP_2               | no -> skip
        MOVE.L  A3,-(SP)                        | push window for SelectWindow
        ST.B    (DragFlag).w                    | flag: don't repaint during select
        BSR     SELECTWINDOW_CONT               | select/bring to front
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
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D6/A3-A4               | restore regs
        BRA     QDEXTENSIONS_EXIT               | -> strip params and return

| ----------------------------------------------------------
|
| MOVEWINDOW_OK - call WDEF procedure for window A3
|
| Dispatches to the window definition function. Parameters:
| D0 = message (wDraw=0, wHit=1, wCalcRgns=2, wNew=3, wDispose=4, wGrow=5)
| D3 = param (message-specific data)
| A3 = window
| Low byte of windowDef handle stores the variation code.
| Called during boot (1,330 times in 30s trace).
MOVEWINDOW_OK:
        CLR.L   -(SP)                           | space for WDEF function result
        MOVEQ.L #0x0,D1                         | clear D1
        MOVE.B  windowDef(A3),D1                | D1 = variation code (low byte)
        MOVE    D1,-(SP)                        | push varCode
        MOVE.L  A3,-(SP)                        | push window
        MOVE    D0,-(SP)                        | push message
        MOVE.L  D3,-(SP)                        | push param
        MOVE.L  windowDef(A3),A0                | A0 = WDEF handle
        MOVE.L  (A0),D0                         | D0 = dereferenced WDEF ptr
        BNE.B   MOVEWINDOW_CONT                 | loaded -> call it
| WDEF not in memory: load it
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        CLR.B   (SP)                            | clear high byte (strip varCode)
        MOVE    #-0x1,(ROMMapInsert).w          | search ROM map first
        _LoadResource                           | load WDEF code
        MOVE.L  (A0),D0                         | D0 = WDEF code pointer
MOVEWINDOW_CONT:
        BSet    #0x7,(A0)                       | lock WDEF handle during call
        MOVE.L  D0,A0                           | A0 = WDEF entry point
        JSR     (A0)                            | call WDEF
        MOVE.L  (SP)+,D0                        | D0 = WDEF result
        MOVE.L  windowDef(A3),A0                | A0 = WDEF handle
        BCLR    #0x7,(A0)                       | unlock WDEF handle
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MOVEWINDOW_CONT_2 - send wDraw message to WDEF (draw window frame)
|
| Preserves D3 since wDraw doesn't need a param.
| Called during boot.
MOVEWINDOW_CONT_2:
        MOVEM.L D3,-(SP)                        | save D3
        MOVEQ.L #0x0,D3                         | param = 0 (no highlight)
        MOVEQ.L #0x0,D0                         | message = wDraw
        BSR.B   MOVEWINDOW_OK                   | call WDEF(wDraw, 0)
        MOVE.L  (SP)+,D3                        | restore D3
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MOVEWINDOW_EMPTY - recalculate window regions or set them empty if invisible
|
| If visible, sends wCalcRgns to WDEF to recompute strucRgn/contRgn.
| If invisible, sets strucRgn, contRgn, and visRgn to empty.
| Called during boot.
MOVEWINDOW_EMPTY:
        MOVEQ.L #0x2,D0                         | message = wCalcRgns
        TST.B   wVisible(A3)                    | window visible?
        BNE.B   MOVEWINDOW_OK                   | yes -> call WDEF(wCalcRgns)
| invisible: empty all regions
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn
        _SetEmptyRgn                            | set empty
        MOVE.L  contRgn(A3),-(SP)               | push contRgn
        _SetEmptyRgn                            | set empty
        MOVE.L  VISRGN(A3),-(SP)                | push visRgn
        _SetEmptyRgn                            | set empty
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _HiliteWindow ($A91C)
| stack: window, fHilite -> (highlights/unhighlights)
|
| _HiliteWindow ($A91C): highlight or unhighlight a window's title bar
| Pascal: procedure HiliteWindow(theWindow: WindowPtr; fHilite: BOOLEAN);
| Only acts if the highlight state is actually changing
| Called during boot.
HiliteWindow:
        MOVEM.L D3-D4/A3-A4,-(SP)               | save regs
        MOVE.L  0x16(SP),A3                     | A3 = window
        MOVE.B  0x14(SP),D3                     | D3 = desired highlight state
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVE.B  0x6F(A3),D0                     | D0 = current hilited flag
        EOR     D3,D0                           | test if changing
        LSR     #0x1,D0                         | bit 0 -> carry
        BCC.B   HILITEWINDOW_SKIP               | no change -> skip
        MOVE.B  D3,0x6F(A3)                     | set new hilited state
        BSR.B   HILITEWINDOW_CONT               | set clip to strucRgn above window
        BSR.B   MOVEWINDOW_CONT_2               | send wDraw to WDEF (redraws frame)
HILITEWINDOW_SKIP:
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore regs
        BRA     DRAWNEW_EXIT                    | -> strip params and return

| ----------------------------------------------------------
|
| HILITEWINDOW_CONT - clip WMgr port to window's strucRgn minus windows above
|
| Called during boot.
HILITEWINDOW_CONT:
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn as initial clip
HILITEWINDOW_CONT_2:
        _SetClip                                | set WMgr clip to region
        MOVE.L  A3,-(SP)                        | push window
        _ClipAbove                              | subtract all windows above A3
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| HILITEWINDOW_CONT_3 - clip WMgr port to GrayRgn (desktop) minus windows above A3
|
HILITEWINDOW_CONT_3:
        MOVE.L  (GrayRgn).w,-(SP)               | push desktop region as initial clip
        BRA.B   HILITEWINDOW_CONT_2             | -> SetClip, ClipAbove

| ----------------------------------------------------------
|
| _SizeWindow ($A91D): resize a window
| Pascal: procedure SizeWindow(theWindow: WindowPtr; w, h: INTEGER;
| fUpdate: BOOLEAN);
| Computes new portRect.botRight from size, then redraws if visible
|
QDExtensions:
        MOVEM.L D3-D4/A3-A4,-(SP)               | save regs
        MOVE.L  0x16(SP),D3                     | D3 = new height (h param)
        BEQ.B   QDEXTENSIONS_DONE               | zero size -> skip
        MOVE.L  0x1A(SP),A3                     | A3 = window
        MOVE    0x16(SP),D4                     | D4 = new width (w param, low word)
        LEA.L   PORTRECT(A3),A4                 | A4 = portRect
        ADD     (A4)+,D4                        | D4 = portRect.top + width = new bottom
        ADD     (A4)+,D3                        | D3 = portRect.left + height = new right
        MOVE    D4,(A4)+                        | store new portRect.bottom
        MOVE    D3,(A4)+                        | store new portRect.right
        TST.B   wVisible(A3)                    | window visible?
        BEQ.B   QDEXTENSIONS_DONE               | no -> done
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVE.L  A3,-(SP)                        | push window
        _SaveOld                                | snapshot old regions
        MOVE.B  0x14(SP),D3                     | D3 = fUpdate parameter
        BSR.B   QDEXTENSIONS_CONT               | recalc, redraw, DrawNew
QDEXTENSIONS_DONE:
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore regs
| QDEXTENSIONS_EXIT - strip 10 bytes of params and return
QDEXTENSIONS_EXIT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xA,SP                         | strip params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| QDEXTENSIONS_CONT - recalculate regions, redraw frame, call DrawNew
|
| Used after SizeWindow/ZoomWindow when window is visible.
| D3 = fUpdate parameter for DrawNew.
QDEXTENSIONS_CONT:
        BSR     MOVEWINDOW_EMPTY                | recalculate strucRgn/contRgn
        BSR.B   HILITEWINDOW_CONT               | clip to strucRgn above window
        BSR     MOVEWINDOW_CONT_2               | send wDraw to WDEF (redraw frame)
        MOVE.L  A3,-(SP)                        | push window
        MOVE.B  D3,-(SP)                        | push fUpdate flag
        _DrawNew                                | repaint changed areas
        BSR     RestorePort                     | restore original port
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _ZoomWindow ($A95C): zoom window between standard and user state
|
| partCode 7 = inZoomIn (restore to user state)
| partCode 8 = inZoomOut (zoom to standard state)
| wDataHandle contains two rects: user state (0..7), standard state (8..15)
AddSearch:
        MOVEM.L D3-D6/A2-A4,-(SP)               | save regs
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVE.L  0x24(SP),A3                     | A3 = window
        BSR     MOVEWINDOW_EMPTY                | recalculate current regions
        MOVE.L  A3,-(SP)                        | push window
        _SaveOld                                | snapshot current regions
| get zoom state rect from wDataHandle
        MOVE.L  wDataHandle(A3),A2              | A2 = WDEF data handle
        MOVE.L  (A2),A2                         | dereference to zoom state data
        CMPI    #0x7,0x22(SP)                   | partCode = inZoomIn (7)?
        BEQ.B   ADDSEARCH_OK                    | yes -> use user state (offset 0)
        ADDQ.W  #0x8,A2                         | no -> use standard state (offset 8)
ADDSEARCH_OK:
| move window origin to zoom state's topLeft
        MOVE.L  structRgn(A3),A4                | A4 = strucRgn handle
        MOVE.L  (A2)+,D0                        | D0 = zoom rect topLeft
        BSR     DELTAPOINT_CONT                 | offset all regions to new position
| compute new portRect size from zoom state rect
        MOVE    (A2)+,D0                        | D0 = zoom rect.bottom
        MOVE    (A2)+,D1                        | D1 = zoom rect.right
        SUBQ.W  #0x8,A2                         | back to start of zoom rect
        SUB     (A2)+,D0                        | D0 = height (bottom - top)
        SUB     (A2)+,D1                        | D1 = width (right - left)
        LEA.L   PORTRECT(A3),A0                 | A0 = portRect
        ADD     (A0)+,D0                        | D0 = top + height = new bottom
        ADD     (A0)+,D1                        | D1 = left + width = new right
        MOVE    D0,(A0)+                        | set portRect.bottom
        MOVE    D1,(A0)+                        | set portRect.right
| redraw at new size
        MOVEQ.L #0x1,D3                         | fUpdate = true
        BSR.B   QDEXTENSIONS_CONT               | recalc, redraw, DrawNew
| optionally bring to front
        TST.B   0x20(SP)                        | front parameter?
        BEQ.B   ADDSEARCH_SKIP                  | no -> skip
        MOVE.L  A3,-(SP)                        | push window
        ST.B    (DragFlag).w                    | suppress repaint during select
        BSR     SELECTWINDOW_CONT               | select window
ADDSEARCH_SKIP:
        PEA.L   PORTRECT(A3)                    | push portRect
        _InvalRect                              | invalidate entire content for redraw
        MOVEM.L (SP)+,D3-D6/A2-A4               | restore regs
        BRA     STRIP_2PARAMS_RTS               | -> strip params and return

| ----------------------------------------------------------
|
| _TrackGoAway ($A91E)
|
| _TrackGoAway ($A91E): track mouse in go-away box
| Pascal: function TrackGoAway(theWindow: WindowPtr; thePt: Point): BOOLEAN;
| Returns true if mouse released inside go-away box.
| Falls through to AddComp (generic part-tracking loop).
| Called during boot.
TrackGoAway:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE    #0x6,-(SP)                      | push partCode 6 (inGoAway)
        MOVE.L  A0,-(SP)                        | restore return address
| AddComp - generic WDEF part tracking loop (go-away, zoom buttons)
| Shared by TrackGoAway and TrackBox. Tracks mouse, toggling
| the part highlight while mouse is inside, returns result.
AddComp:
        LINK    A6,#-0x4                        | local var: mouse point
        MOVEM.L D3-D6/A3,-(SP)                  | save regs
        BSR     GetSetWPort                     | save port, switch to WMgr
        LEA.L   0x8(A6),A0                      | A0 = stack params
        MOVE    (A0)+,D6                        | D6 = partCode
        SUBQ.W  #0x2,D6                         | adjust for WDEF hit result offset
        MOVE.L  (A0)+,-0x4(A6)                  | save startPt in local var
        MOVE.L  (A0)+,A3                        | A3 = window
        CLR     (A0)                            | result = false initially
        MOVEQ.L #0x0,D5                         | D5 = current highlight state (off)
        BSR     HILITEWINDOW_CONT               | clip to strucRgn above window
| tracking loop: send wHit to WDEF, toggle highlight as needed
ADDCOMP_OK:
        MOVEQ.L #0x1,D0                         | message = wHit
        MOVE.L  -0x4(A6),D3                     | D3 = current mouse point
        BSR     MOVEWINDOW_OK                   | call WDEF(wHit, mousePt)
        CMP     D6,D0                           | hit result matches target part?
        BEQ.B   ADDCOMP_OK_2                    | yes -> mouse is in part
        MOVEQ.L #0x0,D0                         | no -> mouse outside part
ADDCOMP_OK_2:
        CMP     D0,D5                           | highlight state changed?
        BEQ.B   ADDCOMP_SKIP                    | no -> skip redraw
        MOVE    D0,D5                           | update highlight state
        BSR.B   ADDCOMP_CONT                    | toggle part highlight via wDraw
ADDCOMP_SKIP:
        PEA.L   -0x4(A6)                        | push local mouse point addr
        _GetMouse                               | read current mouse position
        BSR     DRAGTHERGN_CONT_3               | call DragHook if installed
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | wait for next mouse event
        TST.B   (SP)+                           | mouse still down?
        BNE.B   ADDCOMP_OK                      | yes -> continue tracking
| mouse released
        TST     D5                              | was highlight on at release?
        BEQ.B   ADDCOMP_NO                      | no -> result stays false
        ADDQ.B  #0x1,0x12(A6)                   | result = true (released in part)
        BSR.B   ADDCOMP_CONT                    | toggle highlight off
ADDCOMP_NO:
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D6/A3                  | restore regs
        UNLK    A6                              | tear down frame
        BRA     QDEXTENSIONS_EXIT               | -> strip params and return

| ----------------------------------------------------------
|
| ADDCOMP_CONT - toggle WDEF part highlight (send wDraw with partCode)
|
| Called during boot.
ADDCOMP_CONT:
        MOVEQ.L #0x0,D0                         | message = wDraw
        MOVE    D6,D3                           | param = partCode (for highlight)
        BSR     MOVEWINDOW_OK                   | call WDEF(wDraw, partCode)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _SelectWindow ($A91F)
| stack: window -> (brings to front, highlights)
|
| _SelectWindow ($A91F): bring a window to front and activate it
| Deactivates old front window, brings target to front, activates it
SelectWindow:
        CLR.B   (DragFlag).w                    | clear drag state
| SELECTWINDOW_CONT -- select/bring to front.
SELECTWINDOW_CONT:
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get current front window
        MOVE.L  0x8(SP),-(SP)                   | push target window
        BSR.B   BRINGTOFRONT_CONT               | BringToFront
        MOVE.L  (SP)+,D0                        | D0 = old front window
        BEQ.B   SELECTWINDOW_NO                 | no old front ->
        CMP.L   0x4(SP),D0                      | same as target?
        BEQ.B   SELECTWINDOW_OK                 | yes, no change ->
        BSR     CLOSEWINDOW_CONT                | deactivate old front window
| SELECTWINDOW_NO -- activate the new front window.
SELECTWINDOW_NO:
        MOVE.L  0x4(SP),D0                      | D0 = target window
        MOVE.L  D0,(CurActivate).w              | schedule activate event for it
        BEQ.B   SELECTWINDOW_EMPTY              | nil window ->
SELECTWINDOW_OK:
        MOVE.L  D0,-(SP)                        | push window for HiliteWindow
        ST.B    -(SP)                           | fHilite = true (highlight)
        _HiliteWindow                           | highlight the window
SELECTWINDOW_EMPTY:
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _BringToFront ($A920)
| stack: window -> (moves in front of all)
|
| _BringToFront ($A920): move a window to front of window list
| Pascal: procedure BringToFront(theWindow: WindowPtr);
| Accumulates obscured areas from windows above, removes from list,
| inserts at front, and repaints newly visible areas
BringToFront:
        CLR.B   (DragFlag).w                    | clear drag optimization flag
| BRINGTOFRONT_CONT -- bringToFront.
BRINGTOFRONT_CONT:
        MOVEM.L D3-D6/A2-A4,-(SP)               | save regs
        MOVE.L  0x20(SP),A3                     | A3 = target window
        BSR     GetSetWPort                     | save port, switch to WMgr
        LEA.L   (WindowList).w,A2               | A2 = ptr to window list head
        CMPA.L  (A2),A3                         | already at front?
        BEQ.B   BRINGTOFRONT_OK                 | yes -> nothing to do
        BSR     PAINTBEHIND_EMPTY               | allocate temp region
        MOVE.L  (SP)+,D3                        | D3 = obscured area accumulator
| walk windows above target, accumulating areas that overlap target
        MOVE.L  (A2),A4                         | A4 = current window (start at front)
BRINGTOFRONT_NO:
        CMPA.L  A3,A4                           | reached target window?
        BEQ.B   BRINGTOFRONT_DONE               | yes -> done scanning
        TST.B   wVisible(A4)                    | this window visible?
        BEQ.B   BRINGTOFRONT_SKIP               | no -> skip
| compute this window's visRgn that overlaps target, in global coords
        MOVE.L  0x8(A4),D6                      | D6 = portBounds.topLeft (for offset)
        MOVE.L  0x18(A4),D5                     | D5 = visRgn handle
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
| accumulate the overlap into D3
        MOVE.L  structRgn(A4),-(SP)             | push this window's strucRgn
        MOVE.L  D3,-(SP)                        | push accumulator
        MOVE.L  D3,-(SP)                        | push dest
        _UnionRgn                               | D3 |= strucRgn of above window
BRINGTOFRONT_SKIP:
        MOVE.L  nextWindow(A4),A4               | next window in list
        MOVE.L  A4,D0                           | end of list?
        BNE.B   BRINGTOFRONT_NO                 | no -> continue
BRINGTOFRONT_DONE:
| remove target from current position and insert at front
        MOVE.L  A3,-(SP)                        | push window
        BSR     DeleteWindow                    | unlink from window list
        MOVE.L  (A2),nextWindow(A3)             | link old head as next
        MOVE.L  A3,(A2)                         | target becomes new head
| repaint newly visible area (unless dragging, which handles it)
        TST.B   (DragFlag).w                    | drag optimization active?
        BNE.B   BRINGTOFRONT_SKIP_2             | yes -> skip repaint
        MOVE.L  structRgn(A3),-(SP)             | push target's strucRgn
        MOVE.L  D3,-(SP)                        | push obscured area
        MOVE.L  D3,-(SP)                        | push dest
        _SectRgn                                | D3 = newly visible portion
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  D3,-(SP)                        | push area to repaint
        _PaintOne                               | repaint window frame
BRINGTOFRONT_SKIP_2:
        MOVE.L  A3,-(SP)                        | push window
        _CalcVis                                | recalculate visRgn
        MOVE.L  D3,-(SP)                        | push temp region
        _DisposeRgn                             | free it
BRINGTOFRONT_OK:
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D6/A2-A4               | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BRINGTOFRONT_CONT_2 - negate a point on the stack (reverse an offset)
|
| Negates the v and h components of a point at SP+4.
| Called during boot.
BRINGTOFRONT_CONT_2:
        NEG     0x4(SP)                         | negate v component
        NEG     0x6(SP)                         | negate h component
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _SendBehind ($A921)
| stack: window, behindWindow -> (reorders)
|
| _SendBehind ($A921): send a window behind another in the window list
| Pascal: procedure SendBehind(theWindow: WindowPtr; behindWindow: WindowPtr);
| If theWindow was front, selects the next visible window first
SendBehind:
        MOVEM.L D3-D4/A3,-(SP)                  | save regs
        MOVE.L  0x14(SP),A3                     | A3 = window to send behind
        BSR     GetSetWPort                     | save port, switch to WMgr
        SUBQ.W  #0x4,SP                         | space for FrontWindow
        _FrontWindow                            | get current front window
        CMPA.L  (SP)+,A3                        | is target the front window?
        BNE.B   SENDBEHIND_NO_2                 | no -> just reorder
| target was front: select next visible window
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
| remove target and reinsert behind specified window
        MOVE.L  A3,-(SP)                        | push window
        BSR     DeleteWindow                    | remove from window list
        MOVE.L  structRgn(A3),D3                | D3 = strucRgn (clobbered area)
        MOVE.L  nextWindow(A3),-(SP)            | push next window (for PaintBehind)
        MOVE.L  (SP),-(SP)                      | dup for CalcVBehind
        MOVE.L  A3,-(SP)                        | push window
        MOVE.L  0x1C(SP),-(SP)                  | push behindWindow parameter
        BSR     INSERT_WINDOW                   | insert window behind target
        MOVE.L  D3,-(SP)                        | push clobbered area
        _CalcVBehind                            | recalculate visRgns behind
        MOVE.L  D3,-(SP)                        | push clobbered area
        _PaintBehind                            | repaint exposed area
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D4/A3                  | restore regs
        BRA     STRIP_2PARAMS_RTS               | -> strip params and return

| ----------------------------------------------------------
|
| _BeginUpDate ($A922)
| stack: window -> (sets visRgn to updateRgn)
|
| Called during boot.
| _BeginUpdate ($A922): set up for redrawing a window's update region
| Saves current visRgn, replaces it with intersection of visRgn and updateRgn
| Clears updateRgn so future calls know the update is handled
BeginUpDate:
        MOVEM.L D3-D4/A3,-(SP)                  | save regs
        MOVE.L  0x10(SP),A3                     | A3 = window
        MOVE.L  PORTBOUNDS(A3),D3               | D3 = port origin (for offset)
        MOVE.L  VISRGN(A3),D4                   | D4 = visRgn handle
| convert visRgn to global coords for intersection with updateRgn
        MOVE.L  D4,-(SP)                        | push visRgn
        MOVE.L  D3,-(SP)                        | push offset
        BSR.B   BRINGTOFRONT_CONT_2             | negate offset
        _OffsetRgn                              | visRgn -> global coords
| save original visRgn for EndUpdate restore
        MOVE.L  D4,-(SP)                        | push visRgn (source)
        MOVE.L  (SaveVisRgn).w,-(SP)            | save into SaveVisRgn
        _CopyRgn                                | SaveVisRgn = copy of visRgn
| clip visRgn to updateRgn (only draw what needs updating)
        MOVE.L  D4,-(SP)                        | visRgn
        MOVE.L  updateRgn(A3),-(SP)             | updateRgn
        MOVE.L  D4,-(SP)                        | result -> visRgn
        _SectRgn                                | visRgn = visRgn AND updateRgn
| convert back to local coords
        MOVE.L  D4,-(SP)                        | push visRgn for offset
        MOVE.L  D3,-(SP)                        | push local-to-global offset
        _OffsetRgn                              | visRgn -> local coords
| clear updateRgn (update is now being handled)
        MOVE.L  updateRgn(A3),-(SP)             | push updateRgn handle
        _SetEmptyRgn                            | updateRgn = empty
        BRA     CLOSEWINDOW_SKIP_2              | -> strip params

| ----------------------------------------------------------
|
| _EndUpDate ($A923)
| stack: window -> (restores visRgn)
|
| _EndUpdate ($A923): restore visRgn after update drawing is complete
| Pascal: procedure EndUpdate(theWindow: WindowPtr);
| Converts SaveVisRgn back to local coords, restores it as visRgn,
| then empties SaveVisRgn for next use
| Called during boot.
EndUpDate:
        MOVE.L  A3,-(SP)                        | save A3
        MOVE.L  0x8(SP),A3                      | A3 = window
        MOVE.L  (SaveVisRgn).w,-(SP)            | push SaveVisRgn handle
        MOVE.L  (SP),-(SP)                      | dup for OffsetRgn
        MOVE.L  (SP),-(SP)                      | dup again for CopyRgn source
        MOVE.L  PORTBOUNDS(A3),-(SP)            | push portBounds offset
        _OffsetRgn                              | convert SaveVisRgn to local coords
        MOVE.L  VISRGN(A3),-(SP)                | push visRgn (dest)
        _CopyRgn                                | visRgn = saved visRgn
        _SetEmptyRgn                            | empty SaveVisRgn for next use
        MOVE.L  (SP)+,A3                        | restore A3
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _FrontWindow ($A924)
| -> stack: WindowPtr (topmost visible window)
|
| Called during boot (14,779 times in 30s trace).
| _FrontWindow ($A924): return the frontmost visible window
| Pascal: function FrontWindow: WindowPtr;
| Scans window list, skipping invisible and ghost windows
FrontWindow:
        CLR.L   0x4(SP)                         | result = nil initially
        TST.B   (WWExist).w                     | window manager exists?
        BNE.B   FRONTWINDOW_EXIT_2              | no -> return nil
        MOVE.L  (WindowList).w,A0               | A0 = first window in list
FRONTWINDOW_LOOP:
        MOVE.L  A0,D0                           | end of list?
        BEQ.B   FRONTWINDOW_EXIT                | yes -> return nil
        CMPA.L  (GhostWindow).w,A0              | is this the ghost window?
        BEQ.B   FRONTWINDOW_SKIP                | yes -> skip it
        TST.B   wVisible(A0)                    | window visible?
        BNE.B   FRONTWINDOW_EXIT                | yes -> found it
FRONTWINDOW_SKIP:
        MOVE.L  nextWindow(A0),A0               | advance to next window
        BRA.B   FRONTWINDOW_LOOP                | loop

| ----------------------------------------------------------
|
| FRONTWINDOW_EXIT - FrontWindow: return found window
|
| Called during boot (14,779 times in 30s trace).
FRONTWINDOW_EXIT:
        MOVE.L  A0,0x4(SP)                      | store result on stack
FRONTWINDOW_EXIT_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _DragWindow ($A925)
| stack: window, startPt, boundsRect -> (handles drag)
|
| _DragWindow ($A925): drag a window to a new position
| Draws gray outline while tracking mouse, moves window on release
| Pascal: procedure DragWindow(theWindow: WindowPtr; startPt: Point;
| boundsRect: Rect);
DragWindow:
        LINK    A6,#-0x24                       | 36 bytes local vars (rects, regions)
        MOVEM.L D3-D6/A3-A4,-(SP)               | save regs
        SUBQ.W  #0x2,SP                         | space for WaitMouseUp result
        _WaitMouseUp                            | wait for button release (debounce)
        TST.B   (SP)+                           | mouse still down?
        BEQ     DRAGWINDOW_NO                   | no, cancel drag ->
| clamp drag bounds to keep title bar visible
        MOVE.L  0x8(A6),A0                      | A0 = boundsRect parameter
        MOVE    (A0)+,D0                        | D0 = bounds.top
        MOVE    (MBarHeight).w,D1               | D1 = menu bar height
        ADDQ.W  #0x4,D1                         | + 4 pixels below menu bar
        CMP     D1,D0                           | bounds.top below menu bar?
        BCC     DRAGWINDOW_OK                   | yes ->
        MOVE    D1,D0                           | clamp to just below menu bar
DRAGWINDOW_OK:
| build local drag bounds rect
        LEA.L   -0x10(A6),A1                    | A1 = local drag rect
        MOVE    D0,(A1)+                        | store clamped top
        MOVE    (A0)+,(A1)+                     | copy bounds.left
        MOVE.L  (A0),(A1)                       | copy bounds.bottom, bounds.right
        MOVE.L  0xC(A6),D3                      | D3 = startPt
        MOVE.L  0x10(A6),A3                     | A3 = window
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVE.L  (GrayRgn).w,-(SP)               | push desktop region
        _SetClip                                | clip to desktop
| check if Command key held (for "bring to front" behavior)
        PEA.L   -0x24(A6)                       | push local key map buffer
        _GetKeys                                | read current key state
        MOVE.B  -0x1E(A6),D6                    | D6 = Command key byte
        BPL.B   DRAGWINDOW_SKIP                 | Command not held -> skip
        BSR     HILITEWINDOW_CONT_3             | also clip above target window
DRAGWINDOW_SKIP:
| copy strucRgn and initiate gray drag tracking
        BSR     PAINTBEHIND_EMPTY               | allocate drag outline region
        MOVE.L  (SP),A4                         | A4 = drag region handle
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn
        MOVE.L  A4,-(SP)                        | push dest
        _CopyRgn                                | copy strucRgn as drag outline
        MOVE.L  A4,-(SP)                        | push drag region
        MOVE.L  D3,-(SP)                        | push startPt
        PEA.L   -0x10(A6)                       | push drag bounds rect
        MOVE.L  (SP),-(SP)                      | push slopRect (same as bounds)
        CLR     -(SP)                           | axis = noConstraint
        CLR.L   -(SP)                           | actionProc = nil
        _DragGrayRgn                            | track gray outline drag
| evaluate drag result
        MOVE.L  (SP)+,D5                        | D5 = drag result (dv:dh)
        BEQ.B   DRAGWINDOW_EMPTY                | zero offset -> just select
        CMPI    #-0x8000,D5                     | drag cancelled?
        BEQ.B   DRAGWINDOW_SKIP_2               | yes -> cleanup
| compute new window position from drag offset
        MOVE.L  A3,-(SP)                        | push window for MoveWindow
        MOVE.L  PORTRECT(A3),D0                 | D0 = portRect.top (high word used)
        SUB     0xA(A3),D0                      | subtract portBounds.top (global y)
        ADD     D5,D0                           | add vertical drag offset
        MOVE    D0,-(SP)                        | push new vGlobal
        SWAP    D0                              | get horizontal component
        SWAP    D5                              | get horizontal drag offset
        SUB     PORTBOUNDS(A3),D0               | subtract portBounds.left (global x)
        ADD     D5,D0                           | add horizontal drag offset
        MOVE    D0,-(SP)                        | push new hGlobal
        TST.B   D6                              | Command key held?
        SPL.B   -(SP)                           | front = true unless Cmd held
        _MoveWindow                             | move to new position
DRAGWINDOW_SKIP_2:
        MOVE.L  A4,-(SP)                        | push drag region
        _DisposeRgn                             | free it
        BSR     RestorePort                     | restore original port
DRAGWINDOW_NO:
        MOVEM.L (SP)+,D3-D6/A3-A4               | restore regs
        UNLK    A6                              | tear down frame
        BRA     GROWWINDOW_EXIT_2               | -> strip params and return

| ----------------------------------------------------------
|
| DRAGWINDOW_EMPTY - zero drag offset: window not moved, select if Cmd not held
|
DRAGWINDOW_EMPTY:
        TST.B   D6                              | Command key held?
        BMI.B   DRAGWINDOW_SKIP_2               | yes -> don't select, cleanup
        MOVE.L  A3,-(SP)                        | push window
        _SelectWindow                           | select (bring to front)
        BRA.B   DRAGWINDOW_SKIP_2               | -> cleanup

| Window Manager gray pattern (50% checkerboard, same as QD gray):
| #.#.#.#. 0xAA Used for window drag outlines
| .#.#.#.# 0x55 and desktop background pattern
| (repeats)
DT_mWMgrGray:
  .byte 0xAA,0x55,0xAA,0x55                     | 50% gray rows 1-4 (AA=10101010)
DT_mWMgrGray_4:
  .byte 0xAA,0x55,0xAA,0x55                     | 50% gray rows 5-8 (55=01010101)

| _DragGrayRgn ($A905): drag a gray outline region tracking the mouse
| Sets up gray pattern, falls into DragTheRgn.
DragGrayRgn:
        MOVE.L  DT_mWMgrGray(PC),(DragPattern).w | load gray pattern (first 4 bytes)
        MOVE.L  DT_mWMgrGray_4(PC),(DragPattern_1).w | load gray pattern (last 4 bytes)
| _DragTheRgn ($A926): generic region-dragging loop
| Stack params: region, startPt, limitRect, slopRect, axis, actionProc
| Returns: packed dv:dh offset (0x80008000 if cancelled)
DragTheRgn:
        LINK    A6,#-0x14                       | local vars: PenState + scratch
        MOVEM.L D3-D5/A3,-(SP)                  | save regs
        LEA.L   0x16(A6),A0                     | A0 = stack params
        MOVE.L  (A0)+,D3                        | D3 = startPt
        MOVE.L  (A0)+,A3                        | A3 = region handle to drag
        CLR.L   (A0)                            | clear result location
| set up XOR pen for gray outline drawing
        PEA.L   -0x14(A6)                       | push local PenState buffer
        MOVE.L  (SP),-(SP)                      | dup for GetPenState
        _GetPenState                            | save current pen state
        PEA.L   (DragPattern).w                 | push gray pattern
        _PenPat                                 | set pen pattern to gray
        MOVE    #0xE,-(SP)                      | patXor mode
        _PenMode                                | set XOR drawing mode
| create outline: region minus inset copy (hollow frame)
        MOVE.L  A3,-(SP)                        | push source region
        BSR     PAINTBEHIND_EMPTY               | allocate temp region
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
| draw initial outline
        MOVE.L  A3,-(SP)                        | push outline region
        _PaintRgn                               | draw gray outline (XOR on)
        MOVEQ.L #-0x1,D5                        | D5 = outline visible flag (-1=drawn)
| main tracking loop
DRAGTHERGN_OK:
        SUBQ.W  #0x6,SP                         | space for GetMouse result + PtInRect
        MOVE.L  A7,-(SP)                        | push ptr to result
        _GetMouse                               | read current mouse position
        MOVE.L  (SP),D4                         | D4 = current mouse (v:h)
        MOVE.L  0x12(A6),-(SP)                  | push limitRect
        _PtInRect                               | mouse inside limit?
        TST.B   (SP)+                           | check result
        BEQ     DRAGTHERGN_CONT_4               | outside limit -> check slop rect
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
| apply axis constraint
        MOVE    0xC(A6),D0                      | D0 = axis param (0=none,1=vOnly,2=hOnly)
        BEQ.B   DRAGTHERGN_CONT_2               | noConstraint -> use both deltas
        SUBQ.W  #0x1,D0                         | test for vertical-only
        BNE.B   DRAGTHERGN_NO                   | not vOnly -> must be hOnly
        CLR     D1                              | vertical only: zero horizontal delta
        BRA.B   DRAGTHERGN_CONT_2               | -> apply

| ----------------------------------------------------------
|
| DRAGTHERGN_NO - horizontal only: zero vertical delta
|
DRAGTHERGN_NO:
        CLR     D4                              | horizontal only: zero vertical delta
DRAGTHERGN_CONT_2:
| accumulate deltas into result
        ADD     D1,0x1E(A6)                     | result.h += horizontal delta
        ADD     D4,0x20(A6)                     | result.v += vertical delta
| erase old outline and draw new one at offset position
        MOVE.L  A3,-(SP)                        | push region for OffsetRgn
        MOVE    D4,-(SP)                        | push vertical offset
        MOVE    D1,-(SP)                        | push horizontal offset
        TST     D5                              | outline currently drawn?
        BEQ.B   DRAGTHERGN_SKIP                 | no -> skip erase
        MOVE.L  A3,-(SP)                        | push region
        _PaintRgn                               | erase old outline (XOR toggles off)
DRAGTHERGN_SKIP:
        _OffsetRgn                              | move outline region by delta
        MOVE.L  A3,-(SP)                        | push region
        _PaintRgn                               | draw outline at new position
        MOVEQ.L #-0x1,D5                        | outline is now drawn
        MOVE.L  (SP)+,D3                        | D3 = saved current mouse pt
| call actionProc and DragHook, then wait
DRAGTHERGN_SKIP_2:
        MOVE.L  0x8(A6),D0                      | D0 = actionProc
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
| mouse released: erase final outline and return result
        TST     D5                              | outline currently drawn?
        BEQ.B   DRAGTHERGN_SKIP_3               | no -> skip erase
        MOVE.L  A3,-(SP)                        | push outline region
        _PaintRgn                               | erase outline (XOR toggles off)
DRAGTHERGN_SKIP_3:
        _SetPenState                            | restore original pen state
| check if release point is inside slopRect (cancel if outside)
        SUBQ.W  #0x6,SP                         | space for GetMouse + PtInRect
        MOVE.L  A7,-(SP)                        | push ptr for GetMouse
        _GetMouse                               | read final mouse position
        MOVE.L  0xE(A6),-(SP)                   | push slopRect
        _PtInRect                               | mouse inside slop area?
        TST.B   (SP)+                           | check result
        BNE.B   DRAGTHERGN_OK_2                 | yes -> keep result
        MOVE.L  #0x80008000,0x1E(A6)            | outside slop: cancel (0x8000,0x8000)

DRAGTHERGN_OK_2:
        MOVEM.L (SP)+,D3-D5/A3                  | restore regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0x16,SP                        | strip 22 bytes of params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| DRAGTHERGN_CONT_3
|
| DRAGTHERGN_CONT_3 - call DragHook if installed; DRAGTHERGN_EMPTY - call proc in D0 if non-nil
| Called during boot.
DRAGTHERGN_CONT_3:
        MOVE.L  (DragHook).w,D0                 | D0 = DragHook address
| DRAGTHERGN_EMPTY -- call actionProc if non-nil.
DRAGTHERGN_EMPTY:
        BEQ.B   DRAGTHERGN_SKIP_4               | nil -> skip
        MOVE.L  D0,A0                           | A0 = proc address
        JSR     (A0)                            | call it
DRAGTHERGN_SKIP_4:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DRAGTHERGN_CONT_4 - mouse outside limitRect: check slopRect and toggle outline
|
DRAGTHERGN_CONT_4:
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  D4,-(SP)                        | push current mouse pt
        MOVE.L  0xE(A6),-(SP)                   | push slopRect
        _PtInRect                               | mouse inside slop area?
        TST.B   (SP)+                           | check result
        BNE.B   DRAGTHERGN_OK_3                 | yes -> pin to limit edge
| outside slop rect: erase outline if drawn
        TST     D5                              | outline drawn?
        BEQ.B   DRAGTHERGN_SKIP_2               | no -> just wait
        MOVEQ.L #0x0,D5                         | mark outline as erased
DRAGTHERGN_CONT_5:
        MOVE.L  A3,-(SP)                        | push outline region
        _PaintRgn                               | toggle outline (XOR)
        BRA.B   DRAGTHERGN_SKIP_2               | -> wait loop

| ----------------------------------------------------------
|
| DRAGTHERGN_OK_3 - mouse in slopRect but outside limitRect: redraw outline if needed
|
DRAGTHERGN_OK_3:
        TST     D5                              | outline already drawn?
        BNE.B   DRAGTHERGN_OK_4                 | yes -> pin position
        MOVEQ.L #0x1,D5                         | mark outline as drawn
        BRA.B   DRAGTHERGN_CONT_5               | -> draw outline (XOR on)

| ----------------------------------------------------------
|
| DRAGTHERGN_OK_4 - pin mouse to limitRect edge (clamp to nearest boundary)
|
DRAGTHERGN_OK_4:
        SUBQ.W  #0x4,SP                         | space for PinRect result
        MOVE.L  0x12(A6),-(SP)                  | push limitRect
        MOVE.L  D4,-(SP)                        | push current mouse pt
        _PinRect                                | clamp to rect edge
        MOVE.L  (SP)+,D4                        | D4 = pinned mouse position
        BRA     DRAGTHERGN_CONT                 | -> apply delta and move outline

| ----------------------------------------------------------
|
| _InvalRgn ($A927)
|
| _InvalRgn ($A927): add a region to current window's updateRgn
| Converts region local->global, unions with updateRgn, converts back.
| INVALRGN_CONT entry: D0=0 for union (inval), D0=-1 for diff (valid).
| Called during boot.
InvalRgn:
        MOVEQ.L #0x0,D0                         | D0 = 0 -> union (invalidate)
| INVALRGN_CONT -- -> InvalRgn/ValidRgn core.
INVALRGN_CONT:
        MOVEM.L D3-D5/A3,-(SP)                  | save regs
        MOVE    D0,D5                           | D5 = operation flag
        MOVE.L  (A5),A0                         | A0 = thePort ptr
        MOVE.L  (A0),A3                         | A3 = current port (window)
        MOVE.L  0x14(SP),D4                     | D4 = region handle param
        MOVE.L  PORTBOUNDS(A3),D3               | D3 = port origin offset
        MOVE.L  D4,-(SP)                        | push region
        MOVE.L  D3,-(SP)                        | push offset
        BSR     BRINGTOFRONT_CONT_2             | negate (local-to-global)
        _OffsetRgn                              | convert region to global coords
        MOVE.L  updateRgn(A3),-(SP)             | push updateRgn
        MOVE.L  D4,-(SP)                        | push input region
        MOVE.L  updateRgn(A3),-(SP)             | push dest (updateRgn)
        TST     D5                              | union or diff?
        BNE.B   INVALRGN_EMPTY                  | non-zero -> subtract (valid)
        _UnionRgn                               | updateRgn |= region
        BRA.B   INVALRGN_CONT_2                 | -> convert back

| ----------------------------------------------------------
|
| INVALRGN_EMPTY - ValidRgn path: subtract region from updateRgn
|
| Called during boot.
INVALRGN_EMPTY:
        _DiffRgn                                | updateRgn -= region
INVALRGN_CONT_2:
| convert input region back to local coords
        MOVE.L  D4,-(SP)                        | push region
        MOVE.L  D3,-(SP)                        | push original offset
        _OffsetRgn                              | convert back to local coords
INVALRGN_EXIT:
        MOVEM.L (SP)+,D3-D5/A3                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _InvalRect ($A928)
| stack: rect -> (adds to update region)
|
| _InvalRect ($A928): add a rect to current window's updateRgn
| Converts rect to temp region, then calls InvalRgn/ValidRgn.
| Called during boot.
InvalRect:
        MOVEQ.L #0x0,D0                         | D0 = 0 -> invalidate
INVALRECT_CONT:
        MOVEM.L D2-D5/A3,-(SP)                  | save regs
        MOVE    D0,D5                           | D5 = operation flag
        _NewRgn                                 | allocate temp region (on stack)
        MOVE.L  (SP),D4                         | D4 = temp region handle
        MOVE.L  0x18(SP),-(SP)                  | push rect parameter
        _RectRgn                                | convert rect to region
        MOVE.L  D4,-(SP)                        | push temp region
        MOVE    D5,D0                           | restore operation flag
        BSR.B   INVALRGN_CONT                   | -> InvalRgn/ValidRgn core
        MOVE.L  D4,-(SP)                        | push temp region
        _DisposeRgn                             | free it
        BRA.B   INVALRGN_EXIT                   | -> restore and return

| ----------------------------------------------------------
|
| _ValidRgn ($A929): remove a region from current window's updateRgn
|
ValidRgn:
        MOVEQ.L #-0x1,D0                        | D0 = -1 -> subtract (validate)
        BRA.B   INVALRGN_CONT                   | -> shared core

| ----------------------------------------------------------
|
| _ValidRect ($A92A)
| stack: rect -> (removes from update region)
|
| _ValidRect ($A92A): remove a rect from current window's updateRgn
| Called during boot.
ValidRect:
        MOVEQ.L #-0x1,D0                        | D0 = -1 -> subtract (validate)
        BRA.B   INVALRECT_CONT                  | -> shared rect-to-region wrapper

| ----------------------------------------------------------
|
| _GrowWindow ($A92B)
| stack: window, startPt, sizeRect -> stack: newSize
|
| _GrowWindow ($A92B): track mouse to resize a window
| Draws gray outline while tracking, returns new size on release
| Pascal: function GrowWindow(theWindow: WindowPtr; startPt: Point;
| sizeRect: Rect): LongInt; (high=height, low=width; 0=cancelled)
GrowWindow:
        LINK    A6,#-0x1C                       | 28 bytes local vars
        MOVEM.L D3-D7/A3-A4,-(SP)               | save regs
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVE.L  0xC(A6),D3                      | D3 = startPt
        MOVE.L  0x10(A6),A3                     | A3 = window
        BSR     HILITEWINDOW_CONT_3             | clip to GrayRgn above window
| set up XOR pen for grow outline
        PEA.L   -0x1C(A6)                       | push local PenState buffer
        MOVE.L  (SP),-(SP)                      | dup for GetPenState
        _GetPenState                            | save pen state
        _PenNormal                              | reset pen
        MOVE    #0xE,-(SP)                      | patXor mode
        _PenMode                                | set XOR drawing
        PEA.L   DT_mWMgrGray(PC)                | push gray pattern
        _PenPat                                 | set gray pen pattern
| initialize grow rect in A4 (portRect in global coords)
        LEA.L   -0x8(A6),A4                     | A4 = local grow rect
        MOVE.L  PORTRECT(A3),(A4)               | copy portRect.topLeft
        MOVE.L  0x14(A3),0x4(A4)                | copy portRect.botRight
        MOVE.L  A4,-(SP)                        | push grow rect
        MOVE.L  PORTBOUNDS(A3),-(SP)            | push port origin
        BSR     BRINGTOFRONT_CONT_2             | negate (local-to-global)
        _OffsetRect                             | convert grow rect to global coords
| draw initial grow outline and save initial size
        BSR.B   GROWWINDOW_CONT                 | send wGrow to WDEF (draw outline)
        BSR     GROWWINDOW_CONT_3               | compute size = botRight - topLeft
        MOVE.L  D0,D6                           | D6 = initial size (for cancel check)
| compute offset from startPt to grow rect's botRight
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  D3,-(SP)                        | push startPt
        MOVE.L  0x4(A4),-(SP)                   | push botRight
        BSR     DeltaPoint                      | delta = botRight - startPt
        MOVE.L  (SP)+,D5                        | D5 = anchor offset
| grow tracking loop
GROWWINDOW_OK:
        MOVE.L  D3,-(SP)                        | save current reference point
        BSR.B   GROWWINDOW_CONT_2               | read mouse, compute new botRight->D3
        MOVE.L  (SP),D0                         | D0 = saved reference point
        MOVE.L  D3,-(SP)                        | push new point
        MOVE.L  D0,-(SP)                        | push old point
        BSR     DeltaPoint                      | D7 = delta (new - old)
        MOVE.L  (SP)+,D7                        | D7 = size change
        BEQ.B   GROWWINDOW_SKIP                 | no change -> skip redraw
        BSR.B   GROWWINDOW_CONT                 | erase old grow outline (XOR off)
        ADD     D7,0x6(A4)                      | grow rect.right += dh
        SWAP    D7                              | get vertical component
        ADD     D7,0x4(A4)                      | grow rect.bottom += dv
        BSR.B   GROWWINDOW_CONT                 | draw new grow outline (XOR on)
GROWWINDOW_SKIP:
        BSR     DRAGTHERGN_CONT_3               | call DragHook if installed
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | mouse still down?
        TST.B   (SP)+                           | check
        BNE.B   GROWWINDOW_OK                   | yes -> continue tracking
| mouse released: compute final size
        BSR.B   GROWWINDOW_CONT                 | erase final outline
        BSR.B   GROWWINDOW_CONT_3               | compute final size -> D0
        CMP.L   D0,D6                           | same as initial size?
        BNE.B   GROWWINDOW_EXIT                 | no -> return new size
        MOVEQ.L #0x0,D0                         | cancelled (no change)
GROWWINDOW_EXIT:
        MOVE.L  D0,0x14(A6)                     | store result on stack
        _SetPenState                            | restore original pen state
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D3-D7/A3-A4               | restore regs
        UNLK    A6                              | tear down frame
| GROWWINDOW_EXIT_2 - strip 12 bytes of params and return
GROWWINDOW_EXIT_2:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xC,SP                         | strip params
        JMP     (A0)                            | return

| ----------------------------------------------------------
|
| GROWWINDOW_CONT - send wGrow message to WDEF (draw/erase grow outline)
|
| Passes grow rect (A4) as param. Preserves D3.
GROWWINDOW_CONT:
        MOVE.L  D3,-(SP)                        | save D3
        MOVEQ.L #0x5,D0                         | message = wGrow
        MOVE.L  A4,D3                           | param = ptr to grow rect
        BSR     MOVEWINDOW_OK                   | call WDEF(wGrow, rectPtr)
        MOVE.L  (SP)+,D3                        | restore D3
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| GROWWINDOW_CONT_2 - read mouse, compute constrained new botRight for grow rect
|
| Reads mouse, applies anchor offset D5, pins size to sizeRect,
| computes new absolute position in D3.
GROWWINDOW_CONT_2:
        MOVE.L  0x4(A4),-(SP)                   | save current botRight
        SUBQ.W  #0x8,SP                         | space for GetMouse + DeltaPoint
        MOVE.L  A7,-(SP)                        | push ptr for GetMouse
        _GetMouse                               | read current mouse position
        MOVE.L  D5,-(SP)                        | push anchor offset
        BSR     DeltaPoint                      | compute mouse - anchor = new size
        MOVE.L  (SP)+,0x4(A4)                   | update grow rect.botRight
        BSR.B   GROWWINDOW_CONT_3               | compute size = botRight - topLeft
        MOVE.L  (SP),0x4(A4)                    | restore saved botRight
| pin size to sizeRect bounds
        MOVE.L  0x8(A6),-(SP)                   | push sizeRect
        MOVE.L  D0,-(SP)                        | push unconstrained size
        _PinRect                                | clamp to min/max size
| compute new absolute position from pinned size
        SWAP    D5                              | D5.w = horizontal anchor offset
        MOVE    (A4),D3                         | D3 = grow rect.top
        ADD     (SP)+,D3                        | add pinned height
        ADD     D5,D3                           | add vertical anchor offset
        SWAP    D3                              | move to high word
        SWAP    D5                              | restore D5
        MOVE    0x2(A4),D3                      | D3.w = grow rect.left
        ADD     (SP)+,D3                        | add pinned width
        ADD     D5,D3                           | add horizontal anchor offset
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| GROWWINDOW_CONT_3 - compute grow rect size (botRight - topLeft) -> D0
|
GROWWINDOW_CONT_3:
        SUBQ.W  #0x4,SP                         | space for DeltaPoint result
        MOVE.L  0x4(A4),-(SP)                   | push botRight
        MOVE.L  (A4),-(SP)                      | push topLeft
        BSR     DeltaPoint                      | compute size = botRight - topLeft
        MOVE.L  (SP)+,D0                        | D0 = packed size (height:width)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _FindWindow ($A92C)
| stack: pt -> stack: partCode, WindowPtr
|
| Called during boot (3,695 times in 30s trace).
| _FindWindow ($A92C): determine which window part contains a point
| Returns: inDesk=0, inMenuBar=1, inSysWindow=2, inContent=3,
| inDrag=4, inGrow=5, inGoAway=6, inZoomIn=7, inZoomOut=8
FindWindow:
        MOVEM.L D1/D3/A3,-(SP)                  | save regs
        LEA.L   0x10(SP),A0                     | A0 = stack params
        MOVE.L  (A0)+,A1                        | A1 = VAR whichWindow ptr
        CLR.L   (A1)                            | whichWindow = nil initially
        MOVE.L  (A0)+,D3                        | D3 = thePoint (global coords)
        CLR     (A0)                            | partCode = 0 (inDesk)
| check if point is in menu bar
        MOVEQ.L #0x0,D1                         | clear high word
        MOVE    (MBarHeight).w,D1               | D1 = menu bar height
        SWAP    D1                              | pack as point (v=mbarH, h=0)
        CMP.L   D1,D3                           | point.v < menu bar height?
        BGE.B   FINDWINDOW_NO                   | no, check windows ->
        MOVEQ.L #0x1,D0                         | inMenuBar
        BRA.B   FINDWINDOW_EXIT                 | -> return

| ----------------------------------------------------------
|
| FINDWINDOW_NO
|
| FINDWINDOW_NO - scan window list for window containing the point
| Called during boot (2,682 times in 30s trace).
FINDWINDOW_NO:
        MOVE.L  (WindowList).w,A3               | A3 = first window in list
FINDWINDOW_LOOP:
        MOVE.L  A3,D0                           | end of list?
        BEQ.B   FINDWINDOW_OK_2                 | yes -> check DeskHook
        TST.B   wVisible(A3)                    | window visible?
        BEQ.B   FINDWINDOW_SKIP                 | no -> skip
| test if point is in this window's structure region
        CLR     -(SP)                           | space for PtInRgn result
        MOVE.L  D3,-(SP)                        | push point
        MOVE.L  structRgn(A3),-(SP)             | push strucRgn
        _PtInRgn                                | point in structure?
        TST.B   (SP)+                           | check result
        BEQ.B   FINDWINDOW_SKIP                 | no -> next window
| point hit this window: ask WDEF which part
        MOVEQ.L #0x1,D0                         | message = wHit
        BSR     MOVEWINDOW_OK                   | call WDEF(wHit, point)
        TST     D0                              | hit a part? (0 = not in window)
        BNE.B   FINDWINDOW_OK                   | yes -> decode result
FINDWINDOW_SKIP:
        MOVE.L  nextWindow(A3),A3               | advance to next window
        BRA.B   FINDWINDOW_LOOP                 | loop

| ----------------------------------------------------------
|
| FINDWINDOW_OK
|
| FINDWINDOW_OK - point hit a window: translate WDEF result to FindWindow code
| WDEF wHit returns: 0=miss, 1=content, 2=drag, 3=grow, 4+=go-away/zoom
| Called during boot (1,323 times in 30s trace).
FINDWINDOW_OK:
        MOVE.L  0x10(SP),A0                     | A0 = VAR whichWindow ptr
        MOVE.L  A3,(A0)                         | return hit window
        TST     windowKind(A3)                  | check windowKind
        BPL.B   FINDWINDOW_CONT                 | >= 0 -> application/dialog window
        MOVEQ.L #0x2,D0                         | inSysWindow (system/DA window)
FINDWINDOW_EXIT:
        BRA.B   FINDWINDOW_EXIT_2               | -> store result

| ----------------------------------------------------------
|
| FINDWINDOW_CONT - translate WDEF hit code to FindWindow partCode
|
| WDEF returns: 1=content, 2=drag, 3+=grow/goAway/zoom
| FindWindow returns: 3=inContent, 4=inDrag, 5+=inGrow/inGoAway/inZoom
| Called during boot (1,323 times in 30s trace).
FINDWINDOW_CONT:
        CMPI    #0x2,D0                         | WDEF code 2 = drag bar?
        BLT.B   FINDWINDOW_CONT_3               | < 2 (content) -> inContent
        BGT.B   FINDWINDOW_CONT_2               | > 2 (grow/goaway) -> add 2
        MOVEQ.L #0x4,D0                         | exactly 2 -> inDrag (4)
        BRA.B   FINDWINDOW_EXIT_2               | -> store result

| ----------------------------------------------------------
|
| FINDWINDOW_CONT_2 - WDEF code > 2: add 2 to get FindWindow code (3->5, 4->6, etc.)
|
| Called during boot.
FINDWINDOW_CONT_2:
        ADDQ.W  #0x2,D0                         | grow(3)->inGrow(5), goAway(4)->6, etc.
        BRA.B   FINDWINDOW_EXIT_2               | -> store result

| ----------------------------------------------------------
|
| FINDWINDOW_CONT_3
|
| FINDWINDOW_CONT_3 - WDEF code 1 = content area
| Called during boot (1,018 times in 30s trace).
FINDWINDOW_CONT_3:
        MOVEQ.L #0x3,D0                         | inContent (3)
FINDWINDOW_EXIT_2:
        MOVE    D0,0x18(SP)                     | store partCode in return slot
        MOVEM.L (SP)+,D1/D3/A3                  | restore regs
        BRA     STRIP_2PARAMS_RTS               | -> strip params and return

| ----------------------------------------------------------
|
| FINDWINDOW_OK_2
|
| FINDWINDOW_OK_2 - no window hit: check if DeskHook claims clicks
| Called during boot (1,359 times in 30s trace).
FINDWINDOW_OK_2:
        MOVE.L  (DeskHook).w,D0                 | DeskHook installed?
        BEQ.B   FINDWINDOW_EXIT_2               | no -> return inDesk (0)
        MOVEQ.L #0x2,D0                         | yes -> return inSysWindow (2)
        BRA.B   FINDWINDOW_EXIT_2               | -> store result

| ----------------------------------------------------------
|
| _DrawGrowIcon ($A904)
| stack: window -> (draws size box)
|
| _DrawGrowIcon ($A904): draw the size box in a window's lower-right corner
| Pascal: procedure DrawGrowIcon(theWindow: WindowPtr);
| Sends wGrow+1=6 message to WDEF, which draws the grow icon
| Called during boot.
DrawGrowIcon:
        MOVEM.L D4/A3,-(SP)                     | save regs
        MOVE.L  0xC(SP),A3                      | A3 = window
        BSR     GetSetWPort                     | save port, switch to WMgr
        MOVEQ.L #0x6,D0                         | message 6 = draw grow icon
        BSR     MOVEWINDOW_OK                   | call WDEF
        BSR     RestorePort                     | restore original port
        MOVEM.L (SP)+,D4/A3                     | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _InitMenus ($A930)
| -> (initializes Menu Manager)
|
| _InitMenus ($A930): initialize the Menu Manager
| Allocates MenuList, sets flash count from PRAM, draws empty menu bar
InitMenus:
        BSR.B   CALCMBHEIGHT_EMPTY              | allocate empty MenuList handle
        MOVE.L  A0,(MenuList).w                 | save MenuList handle
        MOVEQ.L #0xC,D0                         | mask for PRAM flash bits
        AND.B   (SPMisc2).w,D0                  | get flash count from PRAM
        LSR     #0x2,D0                         | shift to 0-3 range
        MOVE    D0,(MenuFlash).w                | set menu flash count
        CLR     (MBarEnable).w                  | disable menu bar initially
        CLR.L   (MBarHook).w                    | no menu bar hook
        CLR.L   (MenuHook).w                    | no menu hook
        BSR.B   CalcMBHeight                    | calculate menu bar height
        _ClearMenuBar                           | clear menu bar content
        _DrawMenuBar                            | draw empty menu bar
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Calc MB Height
|
| Called during boot.
CalcMBHeight:
        BSR.B   CALCMBHEIGHT_CONT               | get font metrics -> D0 (ascent:descent)
        MOVEQ.L #0x5,D1                         | D1 = 5 (baseline padding)
        ADD     D0,D1                           | add descent (low word of D0)
        SWAP    D0                              | D0.w = ascent
        ADD     D0,D1                           | D1 = ascent + descent + 5
        MOVE    D1,(MBarHeight).w               | store as menu bar height
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| CALCMBHEIGHT_CONT
|
| Called during boot.
CALCMBHEIGHT_CONT:
        MOVE.L  D4,-(SP)                        | save D4 (used by GetSetWPort)
        JSR     GetSetWPort(PC)                 | save port, switch to WMgr
        SUBQ.W  #0x8,SP                         | space for FMOutput (ascent,descent,widMax,leading)
        MOVE.L  A7,-(SP)                        | push ptr to FMOutput buffer
        _GetFontInfo                            | fill font metrics for system font
        JSR     RestorePort(PC)                 | restore original port
        MOVE.L  (SP)+,D0                        | D0 = ascent:descent (packed words)
        ADDQ.W  #0x4,SP                         | discard widMax:leading
        MOVE.L  (SP)+,D4                        | restore D4
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| CALCMBHEIGHT_EMPTY
|
| Called during boot.
CALCMBHEIGHT_EMPTY:
        MOVEQ.L #0x66,D0                        | 102 bytes = MenuList header + 16 menu entries
        _NewHandle                              | allocate MenuList handle -> A0
| CALCMBHEIGHT_EMPTY_2 -- reinitialize to empty list.
CALCMBHEIGHT_EMPTY_2:
        MOVE.L  (A0),A1                         | A1 = dereferenced MenuList ptr
        CLR     (A1)+                           | lastMenu = 0 (no menus yet)
        MOVE    #0xA,(A1)+                      | lastRight = 10 (initial left margin)
        CLR     (A1)+                           | first menuLeft = 0
        MOVEQ.L #0x17,D0                        | 23+1 = 24 longwords to clear
CALCMBHEIGHT_LOOP:
        CLR.L   (A1)+                           | zero out menu entry slots
        DBF     D0,CALCMBHEIGHT_LOOP            | loop 24 times (96 bytes)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _ClearMenuBar ($A934)
|
| Called during boot.
ClearMenuBar:
        BSR     DISABLEITEM_CONT                | dereference MenuList (validate handle)
        MOVE.L  (MenuList).w,A0                 | A0 = MenuList handle
        BSR.B   CALCMBHEIGHT_EMPTY_2            | reinitialize to empty list
        CLR     (TheMenu).w                     | no highlighted menu
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _InsertMenu ($A935)
|
| _InsertMenu ($A935): add a menu to the menu bar
| Pascal: procedure InsertMenu(theMenu: MenuHandle; beforeID: INTEGER);
| beforeID = 0 means append at end; negative = hierarchical submenu
InsertMenu:
        MOVEM.L D3-D4/A2-A4,-(SP)               | save regs
        BSR     DISABLEITEM_CONT                | get MenuList handle -> A0
        MOVE.L  A0,A3                           | A3 = dereferenced MenuList
        CMPI    #0x60,(A3)                      | MenuList full? (max 96 entries)
        BGE.B   INSERTMENU_SKIP                 | yes, can't add more ->
| check if menu already in bar (by menuID)
        MOVE.L  0x1A(SP),A4                     | A4 = MenuHandle to insert
        MOVE.L  (A4),A2                         | A2 = dereferenced MenuInfo
        MOVE    (A2),D1                         | D1 = menuID
        BSR.B   INSERTMENU_CONT_2               | search MenuList for this ID
        BNE.B   INSERTMENU_SKIP                 | already there, skip ->
| calculate title width for menu bar layout
        JSR     GetSetWPort(PC)                 | switch to WMgr port
        CLR.L   -(SP)                           | system font
        _TextFont                               | set system font (Chicago)
        _TextFace                               | plain style
        CLR     -(SP)                           | space for StringWidth result
        PEA.L   0xE(A2)                         | push menu title string
        _StringWidth                            | measure title width
        MOVEQ.L #0xD,D3                         | 13 pixels padding
        ADD     (SP)+,D3                        | D3 = title width + padding
        MOVE    0x18(SP),D1                     | D1 = beforeID
        BSR.B   INSERTMENU_CONT_2               | search for beforeID in MenuList
        BNE.B   INSERTMENU_FOUND                | found -> insert before it
        MOVE    (A3),D0                         | D0 = lastMenu (current byte count)
        ADDQ.W  #0x6,D0                         | D0 = offset for new entry at end
        MOVE    PORTBITS(A3),D1                 | D1 = lastRight (next x position)
        BRA.B   INSERTMENU_CONT                 | -> store new entry at end

| ----------------------------------------------------------
|
| INSERTMENU_FOUND
|
INSERTMENU_FOUND:
        MOVE    0x4(A3,D0.W),D1                 | D1 = menuLeft of insertion point
        MOVE    (A3),D2                         | D2 = lastMenu (last entry offset)
INSERTMENU_NO:
        MOVE.L  0x0(A3,D2.W),0x6(A3,D2.W)       | shift menu handle down one slot
        MOVE    0x4(A3,D2.W),0xA(A3,D2.W)       | shift menuLeft down one slot
        ADD     D3,0xA(A3,D2.W)                 | adjust left edge by new title width
        SUBQ.W  #0x6,D2                         | move to previous entry
        CMP     D0,D2                           | reached insertion point?
        BGE.B   INSERTMENU_NO                   | no -> continue shifting
INSERTMENU_CONT:
        ADD     D3,PORTBITS(A3)                 | advance lastRight by title width
        MOVE.L  A4,0x0(A3,D0.W)                 | store MenuHandle at insertion slot
        MOVE    D1,0x4(A3,D0.W)                 | store menuLeft at insertion slot
        ADDQ.W  #0x6,(A3)                       | increment lastMenu (add 6 bytes)
        JSR     RestorePort(PC)                 | restore original port
INSERTMENU_SKIP:
        MOVEM.L (SP)+,D3-D4/A2-A4               | restore regs
INSERTMENU_EXIT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| INSERTMENU_CONT_2
|
| Called during boot.
INSERTMENU_CONT_2:
        TST     D1                              | menuID = 0?
        BEQ.B   INSERTMENU_EMPTY                | yes -> not found
        BSR     DISABLEITEM_CONT_3              | A1 = dereferenced MenuList
        MOVE    (A1),D2                         | D2 = lastMenu (byte count)
        BEQ.B   INSERTMENU_EMPTY                | empty list -> not found
INSERTMENU_CONT_3:
        MOVE.L  0x0(A1,D2.W),D0                 | D0 = MenuHandle at offset D2
        BEQ.B   INSERTMENU_SKIP_2               | nil handle -> skip
        MOVE.L  D0,A0                           | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference to MenuInfo
        CMP     (A0),D1                         | menuID matches target?
        BEQ.B   INSERTMENU_FOUND_2              | yes -> found
INSERTMENU_SKIP_2:
        SUBQ.W  #0x6,D2                         | back up one entry (6 bytes each)
        BNE.B   INSERTMENU_CONT_3               | more entries -> continue scan
INSERTMENU_EMPTY:
        MOVEQ.L #0x0,D2                         | not found: D2 = 0
INSERTMENU_FOUND_2:
        MOVE    D2,D0                           | D0 = offset (0=not found)
        RTS                                     | return to caller

| DeleteMenu -- _DeleteMenu ($A936): PROCEDURE DeleteMenu (menuID: Integer);
| ----------------------------------------------------------
|
| _DeleteMenu ($A936)
|
DeleteMenu:
        MOVE    0x4(SP),D1                      | D1 = menuID to delete
        BSR.B   INSERTMENU_CONT_2               | search MenuList for this ID
        BEQ.B   DELETEMENU_EXIT                 | not found -> return
        BSR     DISABLEITEM_CONT_3              | A1 = dereferenced MenuList
        CMP     (A1),D0                         | deleting last entry?
        BNE.B   DELETEMENU_NO                   | no -> shift entries up
        MOVE    0x4(A1,D0.W),0x2(A1)            | lastRight = deleted menu's menuLeft
        BRA.B   DELETEMENU_CONT                 | -> decrement count

| ----------------------------------------------------------
|
| DELETEMENU_NO
|
DELETEMENU_NO:
        MOVE    0xA(A1,D0.W),D2                 | D2 = next menu's menuLeft
        SUB     0x4(A1,D0.W),D2                 | D2 = width of deleted menu title
        SUB     D2,0x2(A1)                      | lastRight -= deleted title width
DELETEMENU_NO_2:
        MOVE.L  0x6(A1,D0.W),0x0(A1,D0.W)       | shift next MenuHandle into current slot
        MOVE    0xA(A1,D0.W),0x4(A1,D0.W)       | shift next menuLeft into current slot
        SUB     D2,0x4(A1,D0.W)                 | adjust menuLeft by deleted width
        ADDQ.W  #0x6,D0                         | advance to next entry
        CMP     (A1),D0                         | past last entry?
        BLE.B   DELETEMENU_NO_2                 | no -> continue shifting
DELETEMENU_CONT:
        SUBQ.W  #0x6,(A1)                       | decrement lastMenu by one entry
DELETEMENU_EXIT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x2,SP                         | strip menuID param (2 bytes)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| DELETEMENU_CONT_2
|
| Called during boot.
DELETEMENU_CONT_2:
        LEA.L   (scratch8).w,A0                 | A0 = scratch rect (8 bytes)
        MOVE    #0x1,(A0)+                      | rect.top = 1 (below top pixel)
        MOVE    0x4(A1,D0.W),(A0)               | rect.left = this menu's menuLeft
        SUBQ.W  #0x1,(A0)+                      | adjust left by -1 pixel
        MOVE    (MBarHeight).w,(A0)             | rect.bottom = menu bar height
        SUBQ.W  #0x1,(A0)+                      | adjust bottom by -1 (above line)
        CMP     (A1),D0                         | is this the last menu?
        BEQ.B   DELETEMENU_OK                   | yes -> use lastRight
        ADDQ.W  #0x6,D0                         | advance to next entry
        MOVE    0x4(A1,D0.W),(A0)               | rect.right = next menu's menuLeft
        BRA.B   DELETEMENU_CONT_3               | -> adjust right edge

| ----------------------------------------------------------
|
| DELETEMENU_OK
|
| Called during boot.
DELETEMENU_OK:
        MOVE    0x2(A1),(A0)                    | rect.right = lastRight
DELETEMENU_CONT_3:
        ADDQ.W  #0x4,(A0)                       | add 4 pixel padding to right edge
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DELETEMENU_CONT_4
|
| Called during boot.
DELETEMENU_CONT_4:
        MOVE.L  (WMgrPort).w,A3                 | A3 = WMgr port
        MOVE.L  CLIPRGN(A3),-(SP)               | push clipRgn handle for SetRectRgn
        CLR.L   -(SP)                           | top=0, left=0
        MOVE    0x16(A3),-(SP)                  | push portRect.right (screen width)
        MOVE    (MBarHeight).w,-(SP)            | push menu bar height as bottom
        _SetRectRgn                             | clip to menu bar area
        PEA.L   PORTRECT(A3)                    | push portRect (full screen)
        MOVE.L  #0x100010,-(SP)                 | corner radius 16x16
        _EraseRoundRect                         | erase menu bar with rounded corners
        MOVE    0x16(A3),-(SP)                  | push screen width (line end x)
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (MBarHeight).w,D0               | D0.w = menu bar height
        SUBQ.W  #0x1,D0                         | y = mbarHeight - 1 (bottom line)
        MOVE    D0,-(SP)                        | push y for MoveTo
        SWAP    D0                              | D0 = (0, mbarHeight-1) packed point
        MOVE.L  D0,-(SP)                        | push (0, 0) as start x,y for MoveTo
        _MoveTo                                 | move to (0, mbarHeight-1)
        _LineTo                                 | draw line to (screenWidth, mbarHeight-1)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _DrawMenuBar ($A937)
| -> (redraws menu bar)
|
| Called during boot.
DrawMenuBar:
        MOVEM.L D3-D6/A3-A4,-(SP)               | save regs
        BSET    #0x7,(AlarmState).w             | enable alarm state
        JSR     GetSetWPort(PC)                 | save port, switch to WMgr
        BSR.B   DELETEMENU_CONT_4               | erase and draw menu bar line
        JSR     FullClip(PC)                    | set clip to full port rect
        MOVEQ.L #0x6,D3                         | D3 = offset to first menu entry
        BSR     DISABLEITEM_CONT                | A0 = dereferenced MenuList
        MOVE.L  A0,A3                           | A3 = MenuList data ptr
        TST     (A3)                            | any menus in list?
        BEQ.B   DRAWMENUBAR_DONE                | no -> done
        BSR     CALCMBHEIGHT_CONT               | get font metrics -> D0 (ascent:descent)
        SWAP    D0                              | D0.w = ascent
        MOVE    D0,D6                           | D6 = ascent
        ADDQ.W  #0x2,D6                         | D6 = baseline y (ascent + 2)
DRAWMENUBAR_NEXT:
        MOVE    0x4(A3,D3.W),-(SP)              | push this menu's menuLeft
        ADDQ.W  #0x8,(SP)                       | add 8 pixels left padding for title
        MOVE    D6,-(SP)                        | push baseline y
        _MoveTo                                 | position pen for title drawing
        MOVE    D3,D5                           | D5 = current menu entry offset
        BSR     DISABLEITEM_NEXT                | A0 = dereferenced MenuInfo, A1 = handle
        MOVE.L  A0,A4                           | A4 = MenuInfo data ptr
        PEA.L   0xE(A4)                         | push menu title string (menuData)
        _DrawString                             | draw the menu title
        BTST    #0x0,0xD(A4)                    | menu enabled? (bit 0 of style byte)
        BEQ.B   DRAWMENUBAR_CONT                | disabled -> dim it
        MOVE    (TheMenu).w,D0                  | D0 = currently highlighted menuID
        CMP     (A4),D0                         | this menu highlighted?
        BNE.B   DRAWMENUBAR_NEXT_2              | no -> next menu
        MOVE    D3,D0                           | D0 = offset for InvertRect
        BSR     DISABLEITEM_CONT_5              | invert menu title (highlight it)
        BRA.B   DRAWMENUBAR_NEXT_2              | -> next menu

| ----------------------------------------------------------
|
| DRAWMENUBAR_CONT - dim disabled menu title with gray pattern
|
DRAWMENUBAR_CONT:
        MOVE    D3,D0                           | D0 = current entry offset
        MOVE.L  A3,A1                           | A1 = MenuList for DELETEMENU_CONT_2
        BSR     DELETEMENU_CONT_2               | build title rect in scratch8
        BSR.B   DRAWMENUBAR_CONT_2              | paint gray over title (dim effect)
DRAWMENUBAR_NEXT_2:
        ADDQ.W  #0x6,D3                         | advance to next menu entry
        CMP     (A3),D3                         | past lastMenu?
        BLE.B   DRAWMENUBAR_NEXT                | no -> draw next title
DRAWMENUBAR_DONE:
        JSR     RestorePort(PC)                 | restore original port
        MOVEM.L (SP)+,D3-D6/A3-A4               | restore regs
        RTS                                     | return to caller

| DRAWMENUBAR_CONT_2 -- paint gray over title (dim effect).
| ----------------------------------------------------------
|
| DRAWMENUBAR_CONT_2
|
DRAWMENUBAR_CONT_2:
        MOVE    #0xB,-(SP)                      | patBic mode (clear through pattern)
        _PenMode                                | set pen mode to BIC
        PEA.L   DT_mWMgrGray(PC)                | push gray pattern
        _PenPat                                 | set pen pattern to gray
        PEA.L   (scratch8).w                    | push title rect (built by DELETEMENU_CONT_2)
        _PaintRect                              | paint gray BIC over title (dims it)
        _PenNormal                              | restore default pen
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _HiliteMenu ($A938)
| stack: menuID -> (highlights menu title)
|
| Called during boot.
HiliteMenu:
        MOVE.L  D4,-(SP)                        | save D4 (used by GetSetWPort)
        JSR     GetSetWPort(PC)                 | save port, switch to WMgr
        BSR     FullClip                        | set clip to full port rect
        MOVE    (TheMenu).w,D1                  | D1 = currently highlighted menuID
        CMP     0x8(SP),D1                      | same as requested menuID?
        BEQ.B   HILITEMENU_OK                   | yes -> no change needed
        BSR.B   DISABLEITEM_CONT_4              | toggle old highlighted menu (unhighlight)
        MOVE    0x8(SP),D1                      | D1 = new menuID to highlight
        MOVE    D1,(TheMenu).w                  | set as current highlighted menu
        BSR.B   DISABLEITEM_CONT_4              | toggle new menu (highlight)
HILITEMENU_OK:
        JSR     RestorePort(PC)                 | restore original port
        MOVE.L  (SP)+,D4                        | restore D4
        BRA     DELETEMENU_EXIT                 | -> strip menuID param and return

| ----------------------------------------------------------
|
| _EnableItem ($A939)
|
| Called during boot (60,959 times in 30s trace).
EnableItem:
        BSR.B   ENABLEITEM_CONT                 | get menu enable flags -> D0=item, D1=flags
        BSET    D0,D1                           | set item's enable bit
ENABLEITEM_EXIT:
        MOVE.L  D1,0xA(A0)                      | store updated menuEnable flags
        BRA     INSERTMENU_EXIT                 | -> strip params and return

| ----------------------------------------------------------
|
| ENABLEITEM_CONT
|
| Called during boot (157,003 times in 30s trace).
ENABLEITEM_CONT:
        MOVE.L  0xA(SP),A0                      | A0 = MenuHandle (past retAddr+retAddr)
        MOVE.L  (A0),A0                         | dereference to MenuInfo
        MOVE    0x8(SP),D0                      | D0 = item number (bit index)
        MOVE.L  0xA(A0),D1                      | D1 = menuEnable flags (32-bit)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _DisableItem ($A93A)
|
| Called during boot (96,044 times in 30s trace).
DisableItem:
        BSR.B   ENABLEITEM_CONT                 | get menu enable flags -> D0=item, D1=flags
        BCLR    D0,D1                           | clear item's enable bit
        BRA.B   ENABLEITEM_EXIT                 | -> store and return

| ----------------------------------------------------------
|
| DISABLEITEM_NEXT
|
| Called during boot (57,585 times in 30s trace).
DISABLEITEM_NEXT:
        BSR.B   DISABLEITEM_CONT                | A0 = dereferenced MenuList
        MOVE.L  0x0(A0,D5.W),A1                 | A1 = MenuHandle at offset D5
        TST.L   (A1)                            | handle empty (purged)?
        BEQ.B   DISABLEITEM_ERR                 | yes -> system error
        MOVE.L  (A1),A0                         | A0 = dereferenced MenuInfo
DISABLEITEM_EXIT:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISABLEITEM_CONT
|
| Called during boot (63,856 times in 30s trace).
DISABLEITEM_CONT:
        MOVE.L  (MenuList).w,A0                 | A0 = MenuList handle
| DISABLEITEM_CONT_2 -- a0 = dereferenced source data.
DISABLEITEM_CONT_2:
        TST.L   (A0)                            | handle empty (purged)?
        BEQ.B   DISABLEITEM_ERR                 | yes -> system error
        MOVE.L  (A0),A0                         | dereference to MenuList data
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISABLEITEM_CONT_3
|
| Called during boot.
DISABLEITEM_CONT_3:
        MOVE.L  (MenuList).w,A1                 | A1 = MenuList handle
        TST.L   (A1)                            | handle empty (purged)?
        BEQ.B   DISABLEITEM_ERR                 | yes -> system error
        MOVE.L  (A1),A1                         | dereference to MenuList data
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISABLEITEM_ERR
|
DISABLEITEM_ERR:
        MOVEQ.L #0x54,D0                        | dsNoPatch = ID 84 (nil MenuList)
        _SysError                               | fatal: Menu Manager not initialized
| DISABLEITEM_CONT_4 -- toggle old highlighted menu (unhighlight).
DISABLEITEM_CONT_4:
        BSR     INSERTMENU_CONT_2               | search for menuID D1 -> D0=offset
        BEQ.B   DISABLEITEM_EXIT                | not found -> return (nothing to invert)
| DISABLEITEM_CONT_5 -- invert menu title (highlight it).
DISABLEITEM_CONT_5:
        BSR.B   DISABLEITEM_CONT_3              | A1 = dereferenced MenuList
        CMP     (A1),D0                         | offset past lastMenu?
        BGT.B   DISABLEITEM_SKIP                | yes -> nothing visible to invert
        ANDI    #-0x2,D0                        | clear bit 0 (ensure word-aligned)
        BEQ.B   DISABLEITEM_SKIP                | zero offset -> skip
        BSR     DELETEMENU_CONT_2               | build title rect in scratch8
        PEA.L   (scratch8).w                    | push title rect
        _InvertRect                             | toggle highlight on menu title
DISABLEITEM_SKIP:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _MenuSelect ($A93D)
| stack: startPt -> stack: menuResult (menu ID + item)
|
| _MenuSelect ($A93D): track mouse through menus until button released
| Returns: menuResult = menuID<<16 | itemNumber (0 if no selection)
| This is the core menu tracking loop called from the event loop
MenuSelect:
        LINK    A6,#-0x28                       | 40 bytes local vars
        MOVEM.L D3-D7/A3,-(SP)                  | save regs
        CLR.L   -(SP)                           | push menuID 0
        _HiliteMenu                             | unhighlight any previous menu
        CLR.L   0xC(A6)                         | result = 0 (no selection)
        CLR.L   -0x28(A6)                       | clear saved menu bits rect
        _WaitMouseUp                            | is mouse still down?
        TST.B   (SP)+                           | check result
        BEQ     MENUSELECT_NO_7                 | no, cancelled ->
        PEA.L   -0x20(A6)                       | push local var for saved port
        _GetPort                                | save current port
        MOVE.L  (WMgrPort).w,-(SP)              | push WMgr port
        _SetPort                                | switch to WMgr port
        BSR     FullClip                        | set clip to full port rect
        CLR     D4                              | D4 = 0 (no menu currently open)
        MOVE.L  0x8(A6),D3                      | D3 = startPt (initial mouse position)
        BRA.B   MENUSELECT_LOOP_2               | -> enter tracking loop

| ----------------------------------------------------------
|
| MENUSELECT_LOOP
|
| Called during boot (28,780 times in 30s trace).
MENUSELECT_LOOP:
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (MBarHeight).w,D0               | D0.w = menu bar height
        SWAP    D0                              | D0 = (mbarHeight, 0) as packed point
        CMP.L   D0,D3                           | mouse.v >= mbarHeight? (below bar)
        BGE     MENUSELECT_SKIP                 | yes -> mouse in pulled-down menu
MENUSELECT_LOOP_2:
        CLR     D5                              | D5 = 0 (no menu hit yet)
  .short 0x6180                                 | Bsr.B DISABLEITEM_CONT (A0 = dereferenced MenuList)
        CMP     0x2(A0),D3                      | mouse.h >= lastRight?
        BGE.B   MENUSELECT_FOUND                | yes -> past all menus
        MOVE    (A0),D5                         | D5 = lastMenu (start from end)
MENUSELECT_CONT:
        CMP     0x4(A0,D5.W),D3                 | mouse.h > this menu's menuLeft?
        BGT.B   MENUSELECT_FOUND                | yes -> found the menu
        SUBQ.W  #0x6,D5                         | try previous menu
        BNE.B   MENUSELECT_CONT                 | more entries -> continue
MENUSELECT_FOUND:
        MOVE    0x4(A0,D5.W),D6                 | D6 = menuLeft of hit menu
        CMP     D5,D4                           | same menu as currently open?
        BEQ     MENUSELECT_SKIP                 | yes -> skip menu switch
        TST     D4                              | was a menu previously open?
        BEQ.B   MENUSELECT_NO                   | no -> open new menu
        BSR     MENUSELECT_CONT_3               | restore saved bits behind old menu
        MOVE    D4,D0                           | D0 = old menu entry offset
        BSR     DISABLEITEM_CONT_5              | unhighlight old menu title
MENUSELECT_NO:
        MOVE    D5,D4                           | D4 = new current menu entry offset
        CLR.L   0xC(A6)                         | clear result (menuID:item)
        TST     D5                              | mouse in a menu title?
        BEQ.B   MENUSELECT_SKIP_2               | no -> skip menu display
        BSR     DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle at D5
        TST.L   0x2(A0)                         | menuWidth:menuHeight valid?
        BPL.B   MENUSELECT_OK                   | yes -> use cached size
        MOVE.L  A0,-(SP)                        | save MenuInfo ptr
        MOVE.L  A1,-(SP)                        | push MenuHandle for CalcMenuSize
        _CalcMenuSize                           | compute width/height of menu
        MOVE.L  (SP)+,A0                        | restore MenuInfo ptr
MENUSELECT_OK:
        MOVE    (A0),0xC(A6)                    | result.hi = menuID (high word)
        MOVE.L  (WMgrPort).w,A1                 | A1 = WMgr port
        MOVE    D6,D0                           | D0 = menu left edge
        ADD     0x2(A0),D0                      | D0 = left + menuWidth
        ADDQ.W  #0x8,D0                         | + 8 pixel padding
        CMP     0x16(A1),D0                     | menu extends past screen right?
        BLE.B   MENUSELECT_OK_2                 | no -> position is fine
        MOVE    0x16(A1),D6                     | D6 = screen right edge
        SUBQ.W  #0x8,D6                         | subtract padding
        SUB     0x2(A0),D6                      | D6 = adjusted left to fit screen
MENUSELECT_OK_2:
        LEA.L   -0x1C(A6),A1                    | A1 = local menu rect
        MOVE    (MBarHeight).w,D1               | D1 = menu bar height
        MOVE    D1,(A1)+                        | rect.top = below menu bar
        MOVE    D6,(A1)+                        | rect.left = menu left edge
        ADD     0x4(A0),D1                      | D1 += menuHeight
        MOVE    D1,(A1)+                        | rect.bottom = top + menuHeight
        ADD     0x2(A0),D6                      | D6 += menuWidth
        MOVE    D6,(A1)+                        | rect.right = left + menuWidth
        MOVE    D5,D0                           | D0 = menu entry offset
        BSR     DISABLEITEM_CONT_5              | highlight menu title (invert)
        MOVE.L  (MBarHook).w,D0                 | D0 = MBarHook procedure
        BEQ.B   MENUSELECT_NO_2                 | no hook -> proceed
        MOVE.L  D0,A0                           | A0 = hook address
        PEA.L   -0x1C(A6)                       | push menu rect
        JSR     (A0)                            | call MBarHook
        TST     D0                              | hook says abort?
        BNE.B   MENUSELECT_EXIT_2               | yes -> exit MenuSelect
MENUSELECT_NO_2:
        BSR     MENUSELECT_CONT_5               | save bits behind menu, draw menu frame
MENUSELECT_SKIP:
        TST     D5                              | menu currently open?
MENUSELECT_SKIP_2:
        BEQ.B   MENUSELECT_NO_3                 | no -> just wait for mouse
        PEA.L   -0x1C(A6)                       | push menu rect
        _ClipRect                               | clip to menu area
        BSR     DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle
        MOVE    #0x1,-(SP)                      | message 1 = mChooseMsg (track item)
        MOVE.L  A1,-(SP)                        | push MenuHandle
        PEA.L   -0x1C(A6)                       | push menu rect
        MOVE.L  D3,-(SP)                        | push current mouse position
        PEA.L   0xE(A6)                         | push ptr to selected item result
        BSR     MENUSELECT_CONT_8               | load MDEF code -> A0
        JSR     (A0)                            | call MDEF(mChooseMsg)
        BSR     MENUSELECT_CONT_9               | unlock MDEF handle
        BSR     FullClip                        | restore full clip
MENUSELECT_NO_3:
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | mouse still down?
        TST.B   (SP)+                           | check result
        BEQ.B   MENUSELECT_NO_5                 | no -> mouse released, finish
        SUBQ.W  #0x4,SP                         | space for GetMouse result
        MOVE.L  A7,-(SP)                        | push ptr for GetMouse
        _GetMouse                               | read current mouse position
        MOVE.L  (SP)+,D3                        | D3 = current mouse (v:h packed)
        MOVE.L  (MenuHook).w,D0                 | D0 = MenuHook procedure
        BEQ.B   MENUSELECT_NO_4                 | no hook -> continue
        MOVE.L  D0,A0                           | A0 = hook address
        JSR     (A0)                            | call MenuHook
MENUSELECT_NO_4:
        BRA     MENUSELECT_LOOP                 | -> loop back to menu bar hit test

| ----------------------------------------------------------
|
| MENUSELECT_NO_5
|
| Called during boot.
MENUSELECT_NO_5:
        TST     D5                              | was a menu open when released?
        BEQ.B   MENUSELECT_NO_6                 | no -> check result
        BSR     MENUSELECT_CONT_11              | flash selected item (visual feedback)
        BSR.B   MENUSELECT_CONT_3               | restore saved bits behind menu
MENUSELECT_NO_6:
        TST     0xE(A6)                         | item selected? (from MDEF result)
        BNE.B   MENUSELECT_EXIT                 | yes -> return selection
        CLR     0xC(A6)                         | no item: clear menuID in result
        MOVE    D5,D0                           | D0 = menu entry offset
        BSR     DISABLEITEM_CONT_5              | unhighlight menu title
MENUSELECT_EXIT:
        MOVE    0xC(A6),(TheMenu).w             | TheMenu = selected menuID
        BMI.B   MENUSELECT_CONT_2               | negative ID -> system menu (DA)
        TST     (MBarEnable).w                  | menu bar enabled for DA access?
        BMI.B   MENUSELECT_CONT_2               | negative -> handle as system menu
MENUSELECT_EXIT_2:
        MOVE.L  -0x20(A6),-(SP)                 | push saved port
        _SetPort                                | restore original port
MENUSELECT_NO_7:
        MOVEM.L (SP)+,D3-D7/A3                  | restore regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | strip param (startPt)
        RTS                                     | return menuResult on stack

| ----------------------------------------------------------
|
| MENUSELECT_CONT_2 - system menu selected: dispatch to Desk Manager
|
MENUSELECT_CONT_2:
        MOVE.L  0xC(A6),-(SP)                   | push menuResult (menuID:item)
        _SystemMenu                             | dispatch to system menu handler
        CLR.L   0xC(A6)                         | clear result (system handled it)
        BRA.B   MENUSELECT_EXIT_2               | -> restore port and return

| ----------------------------------------------------------
|
| MENUSELECT_CONT_3
|
| Called during boot.
MENUSELECT_CONT_3:
        TST.L   -0x28(A6)                       | offscreen bits rect valid?
        BNE.B   MENUSELECT_OK_3                 | yes -> repaint from window list
        MOVE.L  (SavedHandle).w,A0              | A0 = saved bits handle
        MOVE.L  (A0),-0x14(A6)                  | store base addr in local BitMap
        PEA.L   -0x14(A6)                       | push saved BitMap (source)
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L   0x2(A0)                         | push screen portBits (dest)
        BSR.B   MENUSELECT_CONT_4               | CopyBits from saved to screen
        MOVE.L  (SavedHandle).w,A0              | A0 = saved bits handle
        _DisposeHandle                          | free saved bits
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MENUSELECT_OK_3
|
MENUSELECT_OK_3:
        SUBQ.W  #0x4,SP                         | space for NewRgn result
        _NewRgn                                 | allocate temp region
        MOVE.L  (SP),-(SP)                      | dup handle for PaintBehind
        PEA.L   -0x28(A6)                       | push saved menu rect
        _RectRgn                                | convert rect to region
        SUBQ.W  #0x4,SP                         | space for FrontWindow result
        _FrontWindow                            | get front window
        MOVE.L  0x4(SP),-(SP)                   | push temp region (clobbered area)
        _PaintBehind                            | repaint all windows in menu area
        _DisposeRgn                             | free temp region
        BSR     FullClip                        | restore full clip
        CLR.L   -0x28(A6)                       | clear saved menu rect
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MENUSELECT_CONT_4
|
| Called during boot.
MENUSELECT_CONT_4:
        MOVE.L  (SP)+,D7                        | save return address
        PEA.L   -0xE(A6)                        | push srcRect (saved menu bounds)
        MOVE.L  (SP),-(SP)                      | push dstRect (same as srcRect)
        CLR     -(SP)                           | srcCopy transfer mode
        CLR.L   -(SP)                           | maskRgn = nil (no clipping)
        _CopyBits                               | blit between BitMaps (src/dst on stack)
        MOVE.L  D7,-(SP)                        | push saved return address
        RTS                                     | return via pushed address

| ----------------------------------------------------------
|
| MENUSELECT_ERR
|
MENUSELECT_ERR:
        MOVE.L  (A3)+,-0x28(A6)                 | save menu rect topLeft for repaint
        MOVE.L  (A3),-0x24(A6)                  | save menu rect botRight for repaint
        BRA.B   MENUSELECT_CONT_6               | -> draw menu without saved bits

| ----------------------------------------------------------
|
| MENUSELECT_CONT_5
|
| Called during boot.
MENUSELECT_CONT_5:
        MOVEM.L D4/A2-A4,-(SP)                  | save regs
        MOVE.L  #0x20002,D4                     | D4 = shadow offset (2,2 pixels)
        LEA.L   (scratch8).w,A3                 | A3 = scratch rect (expanded for shadow)
        LEA.L   -0x1C(A6),A4                    | A4 = menu rect
        MOVE.L  A4,A2                           | A2 = menu rect (for reading later)
        MOVE.L  A3,-(SP)                        | push scratch rect for InsetRect
        MOVE    (A2)+,(A3)                      | scratch.top = menu.top
        ADDQ.W  #0x4,(A3)+                      | scratch.top += 4 (shadow above)
        MOVE    (A2)+,(A3)+                     | scratch.left = menu.left
        MOVE.L  (A2),(A3)+                      | scratch.bottom,right = menu bottom,right
        MOVE.L  #0xFFFCFFFC,-(SP)               | inset by -4,-4 (expand for shadow)
        _InsetRect                              | expand scratch rect for save area
| compute offscreen bitmap size for saving menu area
        MOVEQ.L #0xF,D0                         | D0 = 15 (for rounding up to word)
        ADD     -(A3),D0                        | D0 = 15 + rect.right
        MOVE    -(A3),D1                        | D1 = rect.bottom
        SUB     -(A3),D0                        | D0 = width + 15 (right - left + 15)
        SUB     -(A3),D1                        | D1 = height (bottom - top)
        LSR     #0x4,D0                         | D0 = (width+15)/16 (words per row)
        ADD     D0,D0                           | D0 = rowBytes (bytes per row)
        MOVE    D0,-0x10(A6)                    | store rowBytes in local BitMap
        MULU    D1,D0                           | D0 = total bytes for bitmap
        _NewHandle                              | allocate offscreen buffer
        BNE.B   MENUSELECT_ERR                  | failed -> fallback to repaint
        MOVE.L  A0,(SavedHandle).w              | store handle for later restore
        MOVE.L  (A0),-0x14(A6)                  | store baseAddr in local BitMap
        MOVE.L  (A3)+,-0xE(A6)                  | store bounds.topLeft in local BitMap
        MOVE.L  (A3),-0xA(A6)                   | store bounds.botRight in local BitMap
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L   0x2(A0)                         | push screen portBits (source)
        PEA.L   -0x14(A6)                       | push local BitMap (dest)
        BSR.B   MENUSELECT_CONT_4               | CopyBits: save screen to offscreen
MENUSELECT_CONT_6:
        MOVE.L  A4,-(SP)                        | push menu rect
        _EraseRect                              | erase menu background
        SUBQ.W  #0x2,SP                         | space for EmptyRect result
        MOVE.L  A4,-(SP)                        | push menu rect
        _EmptyRect                              | is menu rect empty?
        TST.B   (SP)+                           | check result
        BNE.B   MENUSELECT_EMPTY                | empty -> nothing to draw
        _PenNormal                              | reset pen for frame drawing
| draw menu frame: 3 lines forming right and bottom edges + shadow
        MOVE.L  (A2),-(SP)                      | push menu botRight for LineTo (3rd)
        MOVE.L  (SP),-(SP)                      | dup for LineTo (2nd)
        MOVE.L  (A4),-(SP)                      | push menu topLeft for LineTo (1st)
        SUBQ.W  #0x1,0x2(SP)                    | adjust topLeft.h -= 1 (left edge)
        MOVE.L  (SP),-(SP)                      | dup for MoveTo start point
        MOVE    (A2),0x4(SP)                    | overwrite: pt2.v = botRight.v
        MOVE    (A4),0xC(SP)                    | overwrite: pt3.h = topLeft.h
        _MoveTo                                 | move to (left-1, top)
        _LineTo                                 | draw right edge down
        _LineTo                                 | draw bottom edge left
        _LineTo                                 | draw left edge up
        BSR.B   MENUSELECT_CONT_7               | draw menu shadow (2-pixel offset)
| draw menu items via MDEF
        MOVE.L  A4,-(SP)                        | push menu rect
        _ClipRect                               | clip to menu area
        CLR     -(SP)                           | message 0 = mDrawMsg
        BSR     DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle
        MOVE.L  A1,-(SP)                        | push MenuHandle
        MOVE.L  A4,-(SP)                        | push menu rect
        SUBQ.W  #0x8,SP                         | space for hitPt + whichItem (unused)
        BSR.B   MENUSELECT_CONT_8               | load MDEF code -> A0
        JSR     (A0)                            | call MDEF(mDrawMsg)
        BSR.B   MENUSELECT_CONT_9               | unlock MDEF handle
        BSR     FullClip                        | restore full clip
MENUSELECT_EMPTY:
        MOVEM.L (SP)+,D4/A2-A4                  | restore regs
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MENUSELECT_CONT_7
|
| Called during boot.
MENUSELECT_CONT_7:
        MOVE.L  D4,-(SP)                        | push shadow size (2,2) for PenSize
        _PenSize                                | set thick pen for shadow
        MOVE    0x6(A4),D0                      | D0 = menu rect.right
        MOVE    D0,-(SP)                        | push right for LineTo end point
        MOVE    (A4),-(SP)                      | push menu.top for LineTo y
        ADD     D4,(SP)                         | adjust top += shadow offset (2)
        MOVE    D0,-(SP)                        | push right for MoveTo x
        MOVE    0x4(A4),D0                      | D0 = menu rect.bottom
        MOVE    D0,-(SP)                        | push bottom for MoveTo y
        MOVE    0x2(A4),-(SP)                   | push menu.left for LineTo x
        ADD     D4,(SP)                         | adjust left += shadow offset (2)
        MOVE    D0,-(SP)                        | push bottom for LineTo y
        _MoveTo                                 | move to (right, bottom)
        _LineTo                                 | draw shadow along bottom edge
        _LineTo                                 | draw shadow along right edge
        _PenNormal                              | restore default pen
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MENUSELECT_CONT_8
|
| Called during boot (28,795 times in 30s trace).
MENUSELECT_CONT_8:
        MOVE.L  0x6(A0),D0                      | D0 = menuDefHandle (MDEF resource)
        LEA.L   MENUSELECT_EXIT_3(PC),A0        | A0 = default stub (strip args, return)
        BEQ.B   MENUSELECT_EMPTY_2              | nil MDEF -> use stub
        MOVE.L  D0,A0                           | A0 = MDEF handle
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        _LoadResource                           | ensure MDEF is loaded
        BSET    #0x7,(A0)                       | lock MDEF handle during call
        MOVE.L  (A0),A0                         | A0 = MDEF code entry point
MENUSELECT_EMPTY_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MENUSELECT_EXIT_3
|
MENUSELECT_EXIT_3:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xC,SP                         | strip 12 bytes of MDEF params
        JMP     (A0)                            | return (no-op stub)

| ----------------------------------------------------------
|
| MENUSELECT_CONT_9
|
| Called during boot (28,789 times in 30s trace).
MENUSELECT_CONT_9:
        BSR     DISABLEITEM_NEXT                | A0 = dereferenced MenuInfo
| MENUSELECT_CONT_10 -- store computed width/height in MenuInfo.
MENUSELECT_CONT_10:
        MOVE.L  0x6(A0),D0                      | D0 = menuDefHandle (MDEF)
        BEQ.B   MENUSELECT_EMPTY_3              | nil -> nothing to unlock
        MOVE.L  D0,A0                           | A0 = MDEF handle
        BCLR    #0x7,(A0)                       | unlock MDEF handle
MENUSELECT_EMPTY_3:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MENUSELECT_CONT_11
|
| Called during boot.
MENUSELECT_CONT_11:
        MOVE    D4,-(SP)                        | save D4
        MOVE    (MenuFlash).w,D4                | D4 = flash count (0-3)
        BEQ.B   MENUSELECT_SKIP_3               | zero -> no flash effect
        MOVE    0xE(A6),(ToolScratch).w         | save selected item number
        BEQ.B   MENUSELECT_SKIP_3               | no item selected -> skip
        PEA.L   -0x1C(A6)                       | push menu rect
        _ClipRect                               | clip to menu area
MENUSELECT_LOOP_3:
        MOVEQ.L #0x0,D1                         | D1 = 0 (deselect: unhighlight item)
        BSR.B   FULLCLIP_CONT                   | call MDEF to unhighlight
        MOVE.L  D3,D1                           | D1 = mouse pt (highlight: re-highlight)
        BSR.B   FULLCLIP_CONT                   | call MDEF to highlight
        SUBQ.W  #0x1,D4                         | decrement flash counter
        BNE.B   MENUSELECT_LOOP_3               | more flashes -> loop
        BSR.B   FullClip                        | restore full clip
MENUSELECT_SKIP_3:
        MOVE    (SP)+,D4                        | restore D4
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Full Clip
|
| Called during boot (28,789 times in 30s trace).
FullClip:
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L   0x10(A0)                        | push portRect (full screen)
        _ClipRect                               | set clip to full port rect
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| FULLCLIP_CONT
|
| Called during boot.
FULLCLIP_CONT:
        MOVE    #0x1,-(SP)                      | message 1 = mChooseMsg
        BSR     DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle
        MOVE.L  A1,-(SP)                        | push MenuHandle
        PEA.L   -0x1C(A6)                       | push menu rect
        MOVE.L  D1,-(SP)                        | push mouse point (0=deselect)
        PEA.L   (ToolScratch).w                 | push ptr to selected item
        BSR.B   MENUSELECT_CONT_8               | load MDEF code -> A0
        JSR     (A0)                            | call MDEF(mChooseMsg)
        BSR.B   MENUSELECT_CONT_9               | unlock MDEF handle
        MOVE.L  (Ticks).w,D0                    | D0 = current tick count
        ADDQ.L  #0x3,D0                         | target = now + 3 ticks (flash delay)
FULLCLIP_NO:
        CMP.L   (Ticks).w,D0                    | target time reached?
        BGT.B   FULLCLIP_NO                     | no -> spin wait
        RTS                                     | return to caller

| GetMenuBar -- _GetMenuBar ($A93B): FUNCTION GetMenuBar: Handle;
| ----------------------------------------------------------
|
| _GetMenuBar ($A93B)
|
GetMenuBar:
        BSR     CALCMBHEIGHT_EMPTY              | allocate new empty MenuList -> A0
        MOVE.L  A0,0x4(SP)                      | store as return value (Handle)
        MOVE.L  (A0),A1                         | A1 = dest (new list data)
        BSR     DISABLEITEM_CONT                | A0 = source (current MenuList data)
GETMENUBAR_CONT:
        MOVEQ.L #0x66,D0                        | 102 bytes to copy
        _BlockMove                              | copy MenuList data from A0 to A1
        RTS                                     | return to caller

| SetMenuBar -- _SetMenuBar ($A93C): PROCEDURE SetMenuBar (menuList: Handle);
| ----------------------------------------------------------
|
| _SetMenuBar ($A93C)
|
SetMenuBar:
        MOVE.L  0x4(SP),A0                      | A0 = source MenuList handle
        BSR     DISABLEITEM_CONT_2              | A0 = dereferenced source data
        BSR     DISABLEITEM_CONT_3              | A1 = dereferenced current MenuList
        MOVE.L  (SP)+,(SP)                      | strip param
        BRA.B   GETMENUBAR_CONT                 | -> copy 102 bytes from source to current

| ----------------------------------------------------------
|
| _DisposeMenu ($A932)
|
DisposeMenu:
        MOVE.L  0x4(SP),A0                      | A0 = MenuHandle
        BTST    #0x5,(A0)                       | is it a resource (resPurgeable)?
        BEQ.B   DISPOSEMENU_NO                  | no -> dispose as plain handle
        MOVE.L  A0,-(SP)                        | push handle for ReleaseResource
        _ReleaseResource                        | release the resource
        BRA.B   DISPOSEMENU_EXIT                | -> strip param and return

| ----------------------------------------------------------
|
| DISPOSEMENU_NO - dispose plain (non-resource) menu handle
|
DISPOSEMENU_NO:
        _DisposeHandle                          | free the handle
DISPOSEMENU_EXIT:
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _FlashMenuBar ($A94C)
|
FlashMenuBar:
        MOVE.L  D4,-(SP)                        | save D4 (used by GetSetWPort)
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        MOVE.L  0x1C(A0),A0                     | A0 = WMgr clipRgn handle
        MOVE.L  A0,-(SP)                        | push for DisposeRgn later
        _HandToHand                             | duplicate clipRgn -> A0 = copy
        MOVE.L  (SP)+,D0                        | D0 = original clipRgn handle
        MOVE.L  A0,-(SP)                        | push copy for CopyRgn (source)
        MOVE.L  A0,-(SP)                        | push copy for DisposeRgn
        MOVE.L  D0,-(SP)                        | push original for CopyRgn (dest)
        JSR     GetSetWPort(PC)                 | save port, switch to WMgr
        BSR     FullClip                        | set clip to full port rect
        MOVE    0x14(SP),D1                     | D1 = menuID to flash
        BEQ.B   FLASHMENUBAR_EMPTY              | zero -> flash entire menu bar
        BSR     DISABLEITEM_CONT_4              | invert specific menu title
FLASHMENUBAR_EXIT:
        JSR     RestorePort(PC)                 | restore original port
        _CopyRgn                                | restore saved clipRgn
        _DisposeRgn                             | free the copy
        MOVE.L  (SP)+,D4                        | restore D4
        BRA     DELETEMENU_EXIT                 | -> strip param and return

| ----------------------------------------------------------
|
| FLASHMENUBAR_EMPTY - flash entire menu bar (invert rounded rect)
|
FLASHMENUBAR_EMPTY:
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L   0x10(A0)                        | push portRect (for InvertRoundRect)
        MOVE.L  0x1C(A0),-(SP)                  | push clipRgn for SetRectRgn
        CLR.L   -(SP)                           | top=0, left=0
        MOVE    0x16(A0),-(SP)                  | push screen width (right)
        MOVE    #0x14,-(SP)                     | bottom = 20 (menu bar area)
        _SetRectRgn                             | clip to menu bar rect
        MOVE.L  #0x100010,-(SP)                 | corner radius 16x16
        _InvertRoundRect                        | invert menu bar with rounded corners
        BRA.B   FLASHMENUBAR_EXIT               | -> restore and return

