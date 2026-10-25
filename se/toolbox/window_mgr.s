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
| References:
| Inside Macintosh Vol I, Ch 9: The Window Manager (pp 273-328)
| Inside Macintosh Vol I, Ch 13: The Desk Manager (pp 433-448)

| ----------------------------------------------------------
|
| WMGR - Dereference Window Manager port from a graf port
| Given A0 = port (offset to portBits), advance to portRect; if
| portBits is a bitMap with rowBytes < 0 (high bit set), dereference
| through the pixMap handle to get the actual port. Used by the
| Window Manager to walk indirect ports stored in window records.
|
| Called by: DELTAPOINT_CONT, CALCVIS_VISIBLE, BRINGTOFRONT_NO, BEGINUPDATE, ENDUPDATE (and 3 more)
WMGR:
    ADDQ.W	#0x2,A0                              | advance to portBits.baseAddr+2
    TST.W	0x4(A0)                               | test rowBytes high byte
    BPL.B	WMGR_RTS                              | regular bitMap: just return
    MOVEA.L	(A0),A0                             | indirect: deref handle once
    MOVEA.L	(A0),A0                             | deref again to get port ptr
WMGR_RTS:
    RTS                                         | return from WMGR
| ----------------------------------------------------------
|
| _NewString ($A906)
| Pascal: FUNCTION NewString(theString: Str255): StringHandle
| Allocates a new handle and copies the Pascal string into it.
|
NEWSTRING:
    BSR.B	GET_STR_PTR_LEN                       | A0 = string ptr, D0 = length+1
    _PtrToHand                                  | copy D0 bytes from (A0) into new handle
    MOVE.L	A0,0x8(A7)                           | store returned handle as result
    MOVE.L	(A7)+,(A7)                           | strip one param, keep return address
    RTS                                         | return from NewString
| ----------------------------------------------------------
|
| GET_STR_PTR_LEN - Get Pascal string pointer and byte count
| Returns A0 = ptr to string, D0 = length byte + 1 (total size).
|
| Called during boot.
GET_STR_PTR_LEN:
    MOVEA.L	0x8(A7),A0                          | A0 = ptr to Pascal string (caller's param)
    MOVEQ.L	#0x0,D0                             | clear D0
    MOVE.B	(A0),D0                              | D0 = length byte of Pascal string
    ADDQ.W	#0x1,D0                              | +1 for length byte itself = total size
    RTS                                         | return from GET_STR_PTR_LEN
| ----------------------------------------------------------
|
| _SetString ($A907)
| Pascal: PROCEDURE SetString(h: StringHandle; theString: Str255)
| Replaces the contents of an existing string handle.
|
SETSTRING:
    MOVEA.L	0x8(A7),A1                          | A1 = destination StringHandle
    BSR.B	GET_STR_PTR_LEN                       | A0 = string ptr, D0 = byte count
    _PtrToXHand                                 | replace handle contents with string data
    BRA.B	STRIP_2PARAMS_RTS                     | clean up stack and return
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
    MOVE.L	D0,-(A7)                             | save target window ptr
    MOVEA.L	(WindowList).W,A1                   | A1 = first window in z-order list
    SUBA.L	A0,A0                                | A0 = nil (no predecessor yet)
FPWIN_LOOP:
    CMPA.L	(A7),A1                              | found the target window?
    BEQ.B	FPWIN_FOUND                           | yes: A0 = predecessor, A1 = target
    MOVEA.L	A1,A0                               | A0 = current (becomes predecessor)
    MOVEA.L	0x90(A0),A1                         | A1 = next window in list
    MOVE.L	A1,D0                                | test for end of list
    BNE.B	FPWIN_LOOP                            | more windows: keep searching
FPWIN_FOUND:
    MOVE.L	(A7)+,D0                             | restore D0
    RTS                                         | return with window pointers
| ----------------------------------------------------------
|
| INSERT_WINDOW - Insert window into the window list
| Stack: 0x8(SP) = window to insert, 0x4(SP) = behind window (or 0).
| If behind = 0, inserts at end of list (behind all windows).
| If WindowList is empty, the new window becomes the sole entry.
|
INSERT_WINDOW:
    MOVE.L	0x8(A7),D1                           | D1 = new window ptr
    MOVEA.L	D1,A1                               | A1 = new window
    CLR.L	0x90(A1)                              | clear nextWindow link (end of chain)
    TST.L	(WindowList).W                        | any windows in list?
    BNE.B	INSWIN_HAS_LIST                       | yes: insert at proper position
    MOVE.L	D1,(WindowList).W                    | no: new window is first and only
    BRA.B	STRIP_2PARAMS_RTS                     | clean up and return
| Insert window behind a specified window
INSWIN_HAS_LIST:
    MOVE.L	0x4(A7),D0                           | D0 = "behind" window ptr
    BEQ.B	INSWIN_AT_END                         | 0 = insert at end of list
    MOVEA.L	D0,A0                               | A0 = behind window
    MOVE.L	0x90(A0),0x90(A1)                    | new->next = behind->next
    MOVE.L	A1,0x90(A0)                          | behind->next = new window
    BRA.B	STRIP_2PARAMS_RTS                     | clean up and return
| Insert at end of window list
INSWIN_AT_END:
    MOVEQ.L	#0x0,D0                             | search for window 0 (end of list)
    BSR.B	FIND_PREV_WINDOW                      | A0 = last window in list
    MOVE.L	D1,0x90(A0)                          | append new window after last
| ----------------------------------------------------------
| STRIP_2PARAMS_RTS - Pop two 4-byte params and return.
| Called by: SETSTRING, INSERT_WINDOW, INSWIN_HAS_LIST, CALCVBEHIND_EMPTY, PAINTONE_EXIT (and 5 more)
STRIP_2PARAMS_RTS:
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDQ.W	#0x8,A7                              | strip two 4-byte parameters
    JMP	(A0)                                    | tail-call return from STRIP_2PARAMS_RTS via A0
| ----------------------------------------------------------
|
| DeleteWindow - Remove a window from the window list
| Unlinks the window at 0x4(SP) from the WindowList chain.
| If the target is the first window (no predecessor), patches
| WindowList itself via PrFlags (which aliases WindowList offset).
|
DELETEWINDOW:
    MOVE.L	0x4(A7),D0                           | D0 = window to remove
    BSR.B	FIND_PREV_WINDOW                      | find predecessor: A0 = prev window
    MOVE.L	A0,D1                                | test if predecessor exists
    BNE.B	DELWIN_UNLINK                         | has predecessor: unlink normally
    LEA.L	(PrFlags).W,A0                        | no predecessor: window is first in list
DELWIN_UNLINK:
    MOVEA.L	D0,A1                               | A1 = window to remove
    MOVE.L	0x90(A1),0x90(A0)                    | prev->next = target->next (bypass)
    BRA.B	CALCVIS_EXIT_2                        | branch to parameter stripping return
| ----------------------------------------------------------
|
| _CalcVis ($A909): recalculate a window's visRgn
| Pascal: procedure CalcVis(whichWindow: WindowPeek);
| visRgn = intersection of contRgn with desktop minus obscuring windows
|
CALCVIS:
    MOVEM.L	D4/A2-A3,-(A7)                      | save regs
    MOVE.L	0x10(A7),D0                          | D0 = window pointer (from stack)
    BEQ.B	CALCVIS_EXIT                          | nil window ->
    MOVEA.L	D0,A2                               | A2 = WindowRecord
    MOVE.L	0x18(A2),D4                          | D4 = visRgn handle
    TST.B	0x6E(A2)                              | window visible?
    BNE.B	CALCVIS_VISIBLE                       | yes, calculate ->
| invisible window: set visRgn to empty
    MOVE.L	D4,-(A7)                             | push visRgn handle
    _SetEmptyRgn                                | visRgn = empty (invisible window)
CALCVIS_EXIT:
    MOVEM.L	(A7)+,D4/A2-A3                      | restore regs
CALCVIS_EXIT_2:
    MOVE.L	(A7)+,(A7)                           | strip Pascal param
CALCVIS_DONE:
    RTS                                         | return from CALCVIS_EXIT_2
| ----------------------------------------------------------
| CalcVis: visible window - compute visRgn from content and desktop
CALCVIS_VISIBLE:
    MOVE.L	(GrayRgn).W,-(A7)                    | push desktop region
    MOVE.L	0x76(A2),-(A7)                       | push content region
    MOVE.L	D4,-(A7)                             | push visRgn (dest)
    _SectRgn                                    | visRgn = contRgn AND grayRgn
    BSR.B	CALCVIS_CONT                          | subtract obscuring windows above
    MOVE.L	D4,-(A7)                             | push visRgn for local coord offset
    MOVEA.L	A2,A0                               | A0 = window for WMGR deref
    BSR.W	WMGR                                  | A0 = port (handles indirect ports)
    MOVE.L	0x6(A0),-(A7)                        | push portBounds.topLeft (origin)
    _OffsetRgn                                  | convert visRgn to local coords
    BRA.B	CALCVIS_EXIT                          | -> restore regs and return
| ----------------------------------------------------------
|
| CALCVIS_CONT (= CALCVIS_CONT) - subtract structure regions of all
| windows above A2 from D4. Walks the window list front-to-back.
|
CALCVIS_CONT:
    MOVEA.L	(WindowList).W,A3                   | A3 = frontmost window
CALCVIS_SUBTRACT_LOOP:
    CMPA.L	A2,A3                                | reached target window?
    BEQ.B	CALCVIS_DONE                          | yes, done -> RTS
    TST.B	0x6E(A3)                              | this window visible?
    BEQ.B	CALCVIS_SKIP                          | no, skip subtraction
    MOVE.L	D4,-(A7)                             | push source region
    MOVE.L	0x72(A3),-(A7)                       | push this window's frame region
    MOVE.L	D4,-(A7)                             | push dest (same as source)
    _DiffRgn                                    | D4 = D4 minus strucRgn(A3)
CALCVIS_SKIP:
    MOVEA.L	0x90(A3),A3                         | advance to next window behind
    BRA.B	CALCVIS_SUBTRACT_LOOP                 | loop
| ----------------------------------------------------------
|
| _CalcVBehind ($A90A): recalculate visRgn for window and all behind it
| Pascal: procedure CalcVisBehind(window: WindowPeek; clobberedRgn: RgnHandle);
|
CALCVISBEHIND:
    MOVE.L	A2,-(A7)                             | save A2
    MOVE.L	0xC(A7),D0                           | D0 = starting window
    BEQ.B	CALCVBEHIND_EMPTY                     | nil ->
    MOVEA.L	D0,A2                               | A2 = window to start from
CALCVBEHIND_NEXT:
    MOVE.L	A2,-(A7)                             | push window for CalcVis
    BSR.B	CALCVIS                               | recalculate its visRgn
| walk window list behind this one
CALCVBEHIND_SKIP:
    MOVEA.L	0x90(A2),A2                         | A2 = next window in list
    MOVE.L	A2,D0                                | end of list?
    BEQ.B	CALCVBEHIND_EMPTY                     | yes ->
    TST.B	0x6E(A2)                              | visible?
    BEQ.B	CALCVBEHIND_SKIP                      | no, skip ->
| optimization: only recalc if clobbered region intersects this window
    SUBQ.W	#0x2,A7                              | space for SectRect result
    MOVEA.L	0x76(A2),A0                         | this window's content region
    MOVEA.L	(A0),A0                             | dereference
    PEA.L	0x2(A0)                               | push content bounds
    MOVEA.L	0xE(A7),A0                          | clobbered region
    MOVEA.L	(A0),A0                             | dereference
    PEA.L	0x2(A0)                               | push clobbered bounds
    PEA.L	(ToolScratch).W                       | push result rect
    _SectRect                                   | do they intersect?
    TST.B	(A7)+                                 | check result
    BEQ.B	CALCVBEHIND_SKIP                      | no intersection, skip this window
    BRA.B	CALCVBEHIND_NEXT                      | -> recalculate next visible window
| ----------------------------------------------------------
| CalcVBehind epilogue: restore A2 and strip stack params
CALCVBEHIND_EMPTY:
    MOVEA.L	(A7)+,A2                            | restore A2
    BRA.W	STRIP_2PARAMS_RTS                     | -> strip 2 params and return
| ----------------------------------------------------------
|
| _ClipAbove ($A90B): set WMgrPort clip to visible area above a window
| Clips to desktop minus all windows above the given one
|
CLIPABOVE:
    MOVEM.L	D4/A2-A3,-(A7)                      | save regs
    MOVEA.L	(WMgrPort).W,A0                     | WMgr port
    MOVE.L	0x1C(A0),D4                          | D4 = WMgr clipRgn handle
    MOVEA.L	0x10(A7),A2                         | A2 = window to clip above
    MOVE.L	D4,-(A7)                             | dest = clipRgn
    MOVE.L	(GrayRgn).W,-(A7)                    | start with desktop region
    MOVE.L	D4,-(A7)                             | result -> clipRgn
    _SectRgn                                    | clip to desktop
    BSR.B	CALCVIS_CONT                          | subtract all windows above A2
    MOVEM.L	(A7)+,D4/A2-A3                      | restore regs
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from ClipAbove
| ----------------------------------------------------------
|
| _PaintOne ($A90C): repaint one window's frame and add to updateRgn
| Pascal: procedure PaintOne(window: WindowPeek; clobberedRgn: RgnHandle);
| If window=nil, paints desktop pattern instead
|
PAINTONE:
    MOVEM.L	D3-D4/A2-A3,-(A7)                   | save regs
    MOVEA.L	0x18(A7),A2                         | A2 = window (or nil for desktop)
    BSR.W	PAINTONE_CONT                         | clip to clobbered AND visible area
    MOVE.L	A2,D0                                | nil window?
    BNE.B	PAINTONE_NO                           | no, paint window frame ->
| nil window: paint desktop
    MOVE.L	0x14(A7),-(A7)                       | push clobberedRgn
    _SetClip                                    | clip to clobbered area
    BSR.W	PAINTONE_CONT_2                       | paint desktop pattern
PAINTONE_EXIT:
    MOVEM.L	(A7)+,D3-D4/A2-A3                   | restore regs
    BRA.W	STRIP_2PARAMS_RTS                     | -> strip params
| ----------------------------------------------------------
|
| PAINTONE_NO - PaintOne: repaint a visible window's frame and content
|
| Called during boot.
PAINTONE_NO:
    TST.B	0x6E(A2)                              | window visible?
    BEQ.B	PAINTONE_EXIT                         | no, nothing to paint ->
    MOVE.L	0x14(A7),-(A7)                       | push clobberedRgn
    MOVE.L	0x72(A2),-(A7)                       | push window's structure region
    MOVE.L	D3,-(A7)                             | push temp region (dest)
    _SectRgn                                    | temp = clobbered AND strucRgn
    BSR.W	PAINTONE_SKIP                         | if temp empty, skip painting
    MOVE.L	A2,-(A7)                             | push window for ClipAbove
    BSR.B	CLIPABOVE                             | clip WMgr port above this window
    BSR.B	PAINTONE_SKIP                         | if clip empty, skip painting
    MOVEA.L	A2,A3                               | A3 = window (for WDEF call)
    BSR.W	MOVEWINDOW_CONT_2                     | send wDraw to WDEF (draw frame)
    BSR.W	GETNEWRGN                             | allocate temp region
    MOVEA.L	(A7)+,A3                            | A3 = new temp region handle
    MOVE.L	0x76(A2),-(A7)                       | push content region
    MOVE.L	D3,-(A7)                             | push clobbered area
    MOVE.L	A3,-(A7)                             | push dest
    _SectRgn                                    | A3 = clobbered AND contRgn
    TST.B	(PaintWhite).W                        | should we erase content?
    BEQ.B	PAINTONE_NO_2                         | no ->
    MOVE.L	A3,-(A7)                             | push intersection region
    _EraseRgn                                   | erase clobbered content area
PAINTONE_NO_2:
    TST.B	(SaveUpdate).W                        | should we save update region?
    BEQ.B	PAINTONE_NO_3                         | no ->
    MOVE.L	0x7A(A2),-(A7)                       | push existing updateRgn
    MOVE.L	A3,-(A7)                             | push clobbered content area
    MOVE.L	0x7A(A2),-(A7)                       | push dest (updateRgn)
    _UnionRgn                                   | updateRgn |= clobbered content
PAINTONE_NO_3:
    MOVE.L	A3,-(A7)                             | push temp region
    _DisposeRgn                                 | free temp region
    BRA.B	PAINTONE_EXIT                         | -> restore regs and return
| ----------------------------------------------------------
|
| PAINTONE_CONT - save current port, switch to WMgr, get clipRgn in D3
|
| Called during boot.
PAINTONE_CONT:
    BSR.W	SETWPORT                              | save port + switch to WMgrPort
    MOVEA.L	(WMgrPort).W,A3                     | A3 = WMgr port
    MOVE.L	0x1C(A3),D3                          | D3 = WMgr clipRgn handle
    RTS                                         | return from PAINTONE_CONT
| ----------------------------------------------------------
|
| PAINTONE_SKIP - early-out wrapper: if clipRgn empty, return to caller's caller
|
PAINTONE_SKIP:
    SUBQ.W	#0x2,A7                              | space for EmptyRgn result
    MOVE.L	D3,-(A7)                             | push clipRgn handle
    _EmptyRgn                                   | is region empty?
    TST.B	(A7)+                                 | check result
    BNE.B	PAINTONE_DROP_RETURN                  | empty: skip painting (pop caller)
    RTS                                         | non-empty: return to caller
PAINTONE_DROP_RETURN:
    ADDQ.W	#0x4,A7                              | discard caller's return address
    BRA.B	PAINTONE_EXIT                         | -> PaintOne exit
| ----------------------------------------------------------
|
| PAINTONE_CONT_2 - paint desktop: call DeskHook or fill with DeskPattern
|
| Clips above all windows (nil param = entire desktop), then
| calls application's DeskHook if installed, else fills with pattern.
| Called during boot.
PAINTONE_CONT_2:
    CLR.L	-(A7)                                 | nil window: clip above everything
    _ClipAbove                                  | clip to entire desktop
    MOVE.L	(DeskHook).W,D0                      | application desk hook installed?
    BEQ.B	PAINTONE_NO_4                         | no: use default desk pattern
    MOVEA.L	D0,A0                               | A0 = DeskHook proc address
    MOVEQ.L	#0x0,D0                             | D0 = 0 (paint flag, not erase)
    JMP	(A0)                                    | tail-call DeskHook
| ----------------------------------------------------------
|
| PAINTONE_NO_4 - default desktop paint: fill WMgr portRect with desk pattern
|
| Called during boot.
PAINTONE_NO_4:
    PEA.L	0x10(A3)                              | push WMgr portRect
    PEA.L	(DeskPattern).W                       | push 8-byte gray desktop pattern
    _FillRect                                   | fill desktop with pattern
    RTS                                         | return from PAINTONE_NO_4
| ----------------------------------------------------------
|
| _PaintBehind ($A90D): repaint all windows behind startWindow
| Pascal: procedure PaintBehind(startWindow: WindowPeek; clobberedRgn: RgnHandle);
|
PAINTBEHIND:
    MOVEM.L	D3-D4/A2-A3,-(A7)                   | save regs
    BSR.B	PAINTONE_CONT                         | switch to WMgr, D3=clipRgn
    MOVE.L	0x14(A7),-(A7)                       | push clobberedRgn
    MOVE.L	D3,-(A7)                             | push WMgr clipRgn (dest)
    _CopyRgn                                    | clipRgn = clobberedRgn
    BSR.B	GETNEWRGN                             | allocate temp region
    MOVE.L	(A7)+,D4                             | D4 = temp region handle
    MOVEA.L	0x18(A7),A2                         | A2 = startWindow
    MOVE.L	A2,-(A7)                             | push window for ClipAbove
    _ClipAbove                                  | clip to area above startWindow
    MOVE.L	D3,-(A7)                             | push clobbered clipRgn
    MOVE.L	D4,-(A7)                             | push dest (temp)
    _CopyRgn                                    | temp = clipped clobbered area
    BSR.B	PAINTONE_CONT_2                       | paint exposed desktop
    MOVE.L	D4,-(A7)                             | push temp (desktop painted area)
    MOVE.L	D3,-(A7)                             | push clobberedRgn
    MOVE.L	D4,-(A7)                             | push dest
    _DiffRgn                                    | temp = clobbered minus desktop
    PEA.L	0x10(A3)                              | push WMgr port rect
    _ClipRect                                   | restore full clip
    MOVE.L	D4,-(A7)                             | push remaining clobbered area
    _EraseRgn                                   | erase it
    MOVE.L	D4,-(A7)                             | push temp region
    _DisposeRgn                                 | free temp region
    CLR.W	(PaintWhite).W                        | suppress content erase in PaintOne
| walk window list from startWindow, repainting each visible one
PAINTBEHIND_LOOP:
    MOVE.L	A2,D0                                | end of window list?
    BEQ.B	PAINTBEHIND_OK                        | yes ->
    TST.B	0x6E(A2)                              | window visible?
    BEQ.B	PAINTBEHIND_SKIP                      | no, skip ->
    MOVE.L	A2,-(A7)                             | push window
    MOVE.L	0x18(A7),-(A7)                       | push clobberedRgn
    _PaintOne                                   | repaint this window's frame
PAINTBEHIND_SKIP:
    MOVEA.L	0x90(A2),A2                         | advance to next window
    BRA.B	PAINTBEHIND_LOOP                      | loop
| ----------------------------------------------------------
| PaintBehind epilogue: re-enable content erase
PAINTBEHIND_OK:
    ST.B	(PaintWhite).W                         | re-enable content erase for PaintOne
    MOVEM.L	(A7)+,D3-D4/A2-A3                   | restore regs
    BRA.W	STRIP_2PARAMS_RTS                     | -> strip 2 params and return
| ----------------------------------------------------------
|
| GETNEWRGN (= PAINTBEHIND_EMPTY) - allocate new region; handle on stack
|
| Creates a new empty region. Returns with the handle on the stack
| (below the caller's return address).
|
| Called by: SAVEOLD, INITWINDOWS, PAINTONE_NO, PAINTBEHIND, NEWWINDOW_RGN_LOOP (and 5 more)
GETNEWRGN:
    SUBQ.W	#0x4,A7                              | space for NewRgn result
    _NewRgn                                     | allocate empty region
    MOVEA.L	0x4(A7),A0                          | A0 = return address (under handle)
    MOVE.L	(A7)+,(A7)                           | move handle down over return addr
    JMP	(A0)                                    | return (handle remains on stack)
| ----------------------------------------------------------
|
| _SaveOld ($A90E): snapshot a window's strucRgn and contRgn before changes
| Pascal: procedure SaveOld(theWindow: WindowPeek);
| Saves copies to OldStructure/OldContent globals for DrawNew comparison
|
SAVEOLD:
    MOVEM.L	D3-D4/A2,-(A7)                      | save regs
    BSR.B	GETNEWRGN                             | allocate region for old strucRgn
    MOVE.L	(A7)+,D3                             | D3 = old structure region handle
    BSR.B	GETNEWRGN                             | allocate region for old contRgn
    MOVE.L	(A7)+,D4                             | D4 = old content region handle
    MOVEA.L	0x10(A7),A2                         | A2 = window
    MOVE.L	0x72(A2),-(A7)                       | push current strucRgn
    MOVE.L	D3,-(A7)                             | push dest
    _CopyRgn                                    | D3 = copy of strucRgn
    MOVE.L	0x76(A2),-(A7)                       | push current contRgn
    MOVE.L	D4,-(A7)                             | push dest
    _CopyRgn                                    | D4 = copy of contRgn
    MOVEM.L	D3-D4,(OldStructure)                | save both handles to globals
    MOVEM.L	(A7)+,D3-D4/A2                      | restore regs
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from SaveOld
| ----------------------------------------------------------
|
| _DrawNew ($A90F): repaint changed areas after window modification
| Pascal: procedure DrawNew(theWindow: WindowPeek; fUpdate: BOOLEAN);
| Compares current regions with SaveOld snapshots via XOR to find changes,
| then repaints affected areas and recalculates visibility.
|
DRAWNEW:
    MOVEM.L	D3-D4/A2,-(A7)                      | save regs
    MOVEA.L	0x12(A7),A2                         | A2 = window (past saved regs + fUpdate)
    MOVEM.L	(OldStructure),D3-D4                | D3=old strucRgn, D4=old contRgn
    TST.B	0x6E(A2)                              | window visible?
    BEQ.B	DRAWNEW_SKIP                          | no, skip XOR calculation ->
    MOVE.L	0x72(A2),-(A7)                       | push new strucRgn
    MOVE.L	D3,-(A7)                             | push old strucRgn
    MOVE.L	D3,-(A7)                             | push dest (old strucRgn)
    _XOrRgn                                     | D3 = changed structure area
    MOVE.L	0x76(A2),-(A7)                       | push new contRgn
    MOVE.L	D4,-(A7)                             | push old contRgn
    MOVE.L	D4,-(A7)                             | push dest (old contRgn)
    _XOrRgn                                     | D4 = changed content area
DRAWNEW_SKIP:
    MOVE.L	D4,-(A7)                             | push changed content
    MOVE.L	D3,-(A7)                             | push changed structure
    MOVE.L	D3,-(A7)                             | push dest
    _UnionRgn                                   | D3 = all changed areas
    MOVE.B	0x10(A7),(SaveUpdate).W              | set SaveUpdate from fUpdate param
    MOVE.L	A2,-(A7)                             | push window
    MOVE.L	D3,-(A7)                             | push changed area
    _PaintOne                                   | repaint this window's changed area
    ST.B	(SaveUpdate).W                         | re-enable update saving
    MOVE.L	0x90(A2),-(A7)                       | push next window in list
    MOVE.L	D3,-(A7)                             | push changed area
    _PaintBehind                                | repaint all windows behind
    MOVE.L	A2,-(A7)                             | push window
    MOVE.L	D3,-(A7)                             | push changed area
    _CalcVBehind                                | recalculate visRgns behind
    MOVE.L	D3,-(A7)                             | push old structure rgn
    _DisposeRgn                                 | free it
    MOVE.L	D4,-(A7)                             | push old content rgn
    _DisposeRgn                                 | free it
    MOVEM.L	(A7)+,D3-D4/A2                      | restore regs
| DRAWNEW_EXIT - strip 6 bytes of params (window + fUpdate) and return
DRAWNEW_EXIT:
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDQ.W	#0x6,A7                              | strip window ptr + boolean param
    JMP	(A0)                                    | tail-call return from DRAWNEW_EXIT via A0
| ----------------------------------------------------------
|
| _ShowHide ($A908): set window visibility and update screen
| Pascal: procedure ShowHide(theWindow: WindowPtr; showFlag: BOOLEAN);
| Only acts if visibility is actually changing (XOR test).
|
SHOWHIDE:
    MOVEM.L	D3-D4/A1/A3,-(A7)                   | save regs
    MOVEA.L	0x16(A7),A3                         | A3 = window
    MOVE.B	0x14(A7),D3                          | D3 = desired visibility
    MOVE.B	0x6E(A3),D0                          | D0 = current visibility
    EOR.B	D3,D0                                 | test if changing
    LSR.W	#0x1,D0                               | bit 0 -> carry
    BCC.B	SHOWHIDE_SKIP                         | no change -> skip
    BSR.B	SETWPORT                              | save port, switch to WMgr
    MOVE.L	A3,-(A7)                             | push window
    _SaveOld                                    | snapshot current regions
    MOVE.B	D3,0x6E(A3)                          | set new visibility flag
    BSR.W	MOVEWINDOW_EMPTY                      | recalc regions (empty if hiding)
    MOVE.L	A3,-(A7)                             | push window
    ST.B	-(A7)                                  | fUpdate = true
    _DrawNew                                    | repaint changed areas
    BSR.B	RESTOREPORT                           | restore original port
SHOWHIDE_SKIP:
    MOVEM.L	(A7)+,D3-D4/A1/A3                   | restore regs
    BRA.B	DRAWNEW_EXIT                          | -> strip params and return
| ----------------------------------------------------------
|
| SETWPORT (= GetSetWPort) - save current GrafPort in D4, switch to WMgr port
|
| (A5) points to CurrentA5 -> thePort. Saves old port in D4
| and sets thePort to WMgrPort for window manager drawing.
| Called by: PAINTONE_CONT, SHOWHIDE, NEWWINDOW, CLOSEWINDOW, SETWTITLE (and 11 more)
SETWPORT:
    MOVEA.L	(A5),A0                             | A0 = ptr to thePort global
    MOVE.L	(A0),D4                              | D4 = save current port
    MOVE.L	(WMgrPort).W,(A0)                    | thePort = WMgrPort
    RTS                                         | return from SETWPORT
| ----------------------------------------------------------
|
| RESTOREPORT - restore the port saved by SETWPORT
|
| Called by: SHOWHIDE, NEWWINDOW_EXIT, CLOSEWINDOW_NO, SETWTITLE_SKIP, MOVEWINDOW_SKIP_2 (and 9 more)
RESTOREPORT:
    MOVE.L	D4,-(A7)                             | push saved port from D4
    _SetPort                                    | restore it as current port
    RTS                                         | return from RESTOREPORT
| ----------------------------------------------------------
|
| _GetWMgrPort ($A910): return pointer to Window Manager's GrafPort
| Pascal: procedure GetWMgrPort(VAR wPort: GrafPtr);
| (Color variant follows for SE-internal _GetCWMgrPort.)
|
GETWMGRPORT:
    MOVEA.L	(A7)+,A1                            | A1 = return address
    MOVEA.L	(A7)+,A0                            | A0 = VAR wPort pointer
    MOVE.L	(WMgrPort).W,(A0)                    | store WMgrPort into caller's var
    JMP	(A1)                                    | tail-call return from GETWMGRPORT via A1
    MOVEA.L	(A7)+,A1                            | A1 = return address (CWMgrPort variant)
    MOVEA.L	(A7)+,A0                            | A0 = VAR wPort pointer
    MOVE.L	(ghost_WMgrCPort).W,(A0)             | return color WMgr port (always nil on B&W)
    JMP	(A1)                                    | tail-call return from GETWMGRPORT via A1
| ----------------------------------------------------------
|
| _CheckUpdate ($A911): find window needing update (for GetNextEvent)
| Scans window list front-to-back for first window with non-empty updateRgn.
| Returns: true + event filled if update needed, false otherwise.
|
CHECKUPDATE:
    LINK	A6,#-0x8                               | local vars
    MOVE.L	A3,-(A7)                             | save A3
    CLR.W	0xC(A6)                               | result = false initially
    SUBQ.W	#0x4,A7                              | space for GetPort result
    MOVE.L	A7,-(A7)                             | push pointer to local var
    _GetPort                                    | save current port
| scan window list for pending updates
    MOVE.L	(WindowList).W,D0                    | start at front window
    BEQ.B	CHECKUPDATE_EXIT                      | no windows ->
CHECKUPDATE_CONT:
    MOVEA.L	D0,A3                               | A3 = current window
    TST.B	0x6E(A3)                              | visible?
    BEQ.B	CHECKUPDATE_SKIP                      | no, skip ->
| check if this window has a non-empty update region
    SUBQ.W	#0x2,A7                              | space for EmptyRgn result
    MOVE.L	0x7A(A3),-(A7)                       | push updateRgn
    _EmptyRgn                                   | is updateRgn empty?
    TST.B	(A7)+                                 | check result
    BNE.B	CHECKUPDATE_SKIP                      | empty -> skip this window
    TST.L	0x94(A3)                              | window has auto-draw picture?
    BEQ.B	CHECKUPDATE_NO                        | no -> generate update event
| auto-draw window picture (no update event needed)
    MOVE.L	A3,-(A7)                             | push window
    _SetPort                                    | make it current port
    SUBQ.W	#0x4,A7                              | space for NewRgn result
    _NewRgn                                     | allocate temp region
    MOVE.L	(A7),-0x4(A6)                        | save temp rgn in local var
    _GetClip                                    | save current clipRgn into temp
    MOVE.L	0x1C(A3),-(A7)                       | push window's clipRgn
    PEA.L	0x10(A3)                              | push portRect
    _RectRgn                                    | set clipRgn to full portRect
    MOVE.L	A3,-(A7)                             | push window
    _BeginUpDate                                | set visRgn = visRgn AND updateRgn
    MOVEA.L	0x94(A3),A0                         | A0 = picture handle
    MOVE.L	A0,-(A7)                             | push picture handle
    MOVEA.L	(A0),A0                             | dereference handle
    PEA.L	0x2(A0)                               | push picture frame rect
    _DrawPicture                                | draw picture into update area
    MOVE.L	A3,-(A7)                             | push window
    _EndUpDate                                  | restore visRgn from SaveVisRgn
    MOVE.L	-0x4(A6),-(A7)                       | push saved clipRgn
    MOVE.L	(A7),-(A7)                           | dup for SetClip (consume + dispose)
    _SetClip                                    | restore original clipRgn
    _DisposeRgn                                 | free temp region
CHECKUPDATE_SKIP:
    MOVE.L	0x90(A3),D0                          | D0 = next window in list
    BNE.B	CHECKUPDATE_CONT                      | more windows -> continue scan
CHECKUPDATE_EXIT:
    _SetPort                                    | restore saved port (on stack)
    MOVEA.L	(A7)+,A3                            | restore A3
    UNLK	A6                                     | tear down stack frame
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from CHECKUPDATE_EXIT
| ----------------------------------------------------------
|
| CHECKUPDATE_NO - fill update event for window with non-empty updateRgn
|
| Builds an EventRecord: what=updateEvt(6), message=windowPtr
| Called during boot.
CHECKUPDATE_NO:
    MOVEA.L	0x8(A6),A0                          | A0 = event record pointer
    MOVE.W	#0x6,(A0)+                           | event.what = updateEvt (6)
    MOVE.L	A3,(A0)                              | event.message = window pointer
    ADDQ.B	#0x1,0xC(A6)                         | result = true (found update)
    BRA.B	CHECKUPDATE_EXIT                      | -> restore port and return
| ----------------------------------------------------------
|
| CHECKUPDATE_CONT_2/0BBD0/0BBD2 (= CHECKUPDATE_CONT_2/EMPTY/CONT_3) - allocate
| a GrafPort-sized block (108 bytes) and open it. Returns A3 = port.
|
CHECKUPDATE_CONT_2:
    MOVEQ.L	#0x6C,D0                            | 108 = sizeof(GrafPort)
CHECKUPDATE_EMPTY:
    _NewPtr                                     | allocate D0 bytes, A0 = ptr
CHECKUPDATE_CONT_3:
    MOVEA.L	A0,A3                               | A3 = port pointer
    MOVE.L	A0,-(A7)                             | push port for OpenPort
    _OpenPort                                   | initialize as GrafPort
    RTS                                         | return from CHECKUPDATE_CONT_3
| ----------------------------------------------------------
|
| _InitWindows ($A912): initialize the Window Manager
| Creates WMgrPort, GrayRgn (desktop), paints desktop pattern.
| SE-only: also calls _InitMenus before drawing the menu bar.
|
INITWINDOWS:
    LINK	A6,#-0x10                              | local vars
    MOVEM.L	D3-D5/A3-A4,-(A7)                   | save regs
    MOVEQ.L	#0x7,D0                             | bit 7
    BSET	D0,(DSWndUpdate)                       | enable DS window updates
    BSET	D0,(AlarmState)                        | enable alarm
    CLR.B	(WWExist).W                           | no windows yet
    MOVE.L	(MinusOne).W,(SaveUpdate).W          | enable update events
| load desktop pattern from 'PAT ' resource #16
    SUBQ.W	#0x4,A7                              | space for GetPattern result
    MOVE.W	#0x10,-(A7)                          | pattern ID 16 (desktop)
    _GetPattern                                 | get pattern handle
    MOVEA.L	(A7)+,A0                            | A0 = pattern handle
    MOVEA.L	(A0),A0                             | dereference
    MOVE.L	(A0)+,(DeskPattern).W                | copy first 4 bytes of pattern
    MOVE.L	(A0),(DeskPattern_1).W               | copy last 4 bytes of pattern
| create Window Manager port (full screen)
    BSR.B	CHECKUPDATE_CONT_2                    | allocate GrafPort, A3 = WMgrPort
    MOVE.L	A3,(WMgrPort).W                      | store global WMgrPort pointer
| draw rounded screen border and prepare GrayRgn
    LEA.L	0x10(A3),A0                           | A0 = screen rect (portRect)
    MOVE.L	A0,-(A7)                             | push for FrameRoundRect (below)
    MOVE.L	A0,-(A7)                             | push for FrameRoundRect (dup)
    LEA.L	(scratch8).W,A4                       | A4 = scratch rect
    MOVEA.L	A4,A1                               | A1 = dest for copy
    MOVE.L	(A0)+,(A1)+                          | copy portRect.topLeft to scratch
    MOVE.L	(A0),(A1)                            | copy portRect.botRight to scratch
    MOVE.L	A4,-(A7)                             | push scratch rect
    MOVE.L	#0xFFFDFFFD,-(A7)                    | inset by -3,-3 (expand 3 pixels)
    _InsetRect                                  | expand scratch rect for border
    MOVE.L	#0x30003,-(A7)                       | pen size 3x3
    _PenSize                                    | set thick pen for border
    MOVE.L	A4,-(A7)                             | push expanded rect
    MOVE.L	#0x160016,-(A7)                      | corner radius 22x22
    _FrameRoundRect                             | draw rounded screen border
    _PenNormal                                  | restore pen to 1x1
    _InitMenus                                  | SE: initialize menu manager
    JSR	CALCMBHEIGHT(PC)                        | calculate menu bar height
    JSR	DRAWMBAR(PC)                            | draw menu bar separator line
| build GrayRgn: rounded screen minus menu bar
    BSR.W	GETNEWRGN                             | allocate region for GrayRgn
    MOVE.L	(A7)+,D5                             | D5 = GrayRgn handle
    MOVE.L	D5,(GrayRgn).W                       | store global GrayRgn
    _HidePen                                    | suppress drawing during record
    _OpenRgn                                    | start recording region
    MOVE.L	#0x100010,-(A7)                      | corner radius 16x16
    _FrameRoundRect                             | record rounded rect into region
    MOVE.L	D5,-(A7)                             | push GrayRgn
    _CloseRgn                                   | GrayRgn = rounded screen shape
    _ShowPen                                    | re-enable drawing
| subtract menu bar from GrayRgn (menu bar is in clipRgn)
    MOVE.L	D5,-(A7)                             | push GrayRgn
    MOVE.L	0x1C(A3),-(A7)                       | push clipRgn (menu bar area)
    MOVE.L	D5,-(A7)                             | push dest
    _DiffRgn                                    | GrayRgn = screen minus menu bar
| paint desktop
    MOVE.L	D5,-(A7)                             | push GrayRgn
    _SetClip                                    | clip to desktop area
    PEA.L	(DeskPattern).W                       | push desktop pattern
    _FillRect                                   | fill desktop with pattern
    _ShowCursor                                 | show the cursor
| initialize window list and globals
    CLR.L	(WindowList).W                        | no windows yet
    BSR.W	GETNEWRGN                             | allocate SaveVisRgn
    MOVE.L	(A7)+,(SaveVisRgn).W                 | store SaveVisRgn handle
    CLR.L	(GhostWindow).W                       | no ghost window
    LEA.L	(CurActivate).W,A0                    | A0 = CurActivate
    CLR.L	(A0)+                                 | CurActivate = nil
    CLR.L	(A0)+                                 | CurDeactive = nil
    MOVEM.L	(A7)+,D3-D5/A3-A4                   | restore regs
    UNLK	A6                                     | tear down frame
    RTS                                         | return from InitWindows
| ----------------------------------------------------------
|
| INITWINDOWS_EMPTY (INITWINDOWS_EMPTY) - NewWindow with caller-supplied storage
| Strips high byte from pointer (24-bit addressing), opens as port.
|
INITWINDOWS_EMPTY:
    AND.L	(Lo3Bytes).W,D0                       | mask to 24-bit address
    MOVEA.L	D0,A0                               | A0 = wStorage pointer
    BSR.W	CHECKUPDATE_CONT_3                    | open it as GrafPort (A3 = port)
    BRA.B	NEWWINDOW_CONT                        | -> continue NewWindow setup
| ----------------------------------------------------------
|
| _NewWindow ($A913): create a new window
| Pascal: function NewWindow(wStorage: Ptr; boundsRect: Rect;
| title: Str255; visible: BOOLEAN; procID: INTEGER;
| behind: WindowPtr; goAwayFlag: BOOLEAN; refCon: LongInt): WindowPtr;
|
NEWWINDOW:
    LINK	A6,#0x0                                | no local vars
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save regs
    BSR.W	SETWPORT                              | save current port, switch to WMgr port
    MOVE.L	0x1E(A6),D0                          | D0 = wStorage (caller-supplied or nil)
    BNE.B	INITWINDOWS_EMPTY                     | non-nil: use caller's storage ->
| allocate window record in application heap
    MOVEQ.L	#0x0,D0                             | clear high word of size
    MOVE.W	#0x9C,D0                             | 156 bytes = sizeof(WindowRecord)
    BSR.W	CHECKUPDATE_EMPTY                     | allocate and zero
NEWWINDOW_CONT:
    MOVE.L	A3,0x22(A6)                          | store WindowPtr as return value
    MOVE.W	#0x1,0x44(A3)                        | set font to application font (applFont = 1)
    MOVEA.L	0x1A(A6),A2                         | A2 = boundsRect parameter
    MOVE.L	(A2),-(A7)                           | push boundsRect.topLeft
    _MovePortTo                                 | position port origin
    SUBQ.W	#0x4,A7                              | space for DeltaPoint result
    MOVE.L	0x4(A2),-(A7)                        | push boundsRect.botRight
    MOVE.L	(A2),-(A7)                           | push boundsRect.topLeft
    BSR.W	DELTAPOINT                            | compute size = botRight - topLeft
    _PortSize                                   | set port size to window dimensions
    MOVE.L	(WMgrPort).W,-(A7)                   | push WMgr port
    _SetPort                                    | switch back to WMgr port
| initialize WindowRecord fields after GrafPort (offset +108)
    LEA.L	0x6C(A3),A2                           | A2 = ptr to windowKind field
    MOVE.W	#0x8,(A2)+                           | windowKind = 8 (userKind)
    TST.B	0x14(A6)                              | visible parameter?
    SNE.B	(A2)+                                 | wVisible = true/false
    CLR.B	(A2)+                                 | hilited = false
    TST.B	0xC(A6)                               | goAway parameter?
    SNE.B	(A2)+                                 | goAwayFlag = true/false
    CLR.B	(A2)+                                 | spareFlag = false
| allocate 3 regions: strucRgn, contRgn, updateRgn
    MOVEQ.L	#0x2,D3                             | loop counter (3 regions)
NEWWINDOW_RGN_LOOP:
    BSR.W	GETNEWRGN                             | allocate new empty region
    MOVE.L	(A7)+,(A2)+                          | store handle in WindowRecord
    DBF.W	D3,NEWWINDOW_RGN_LOOP                 | loop 3 times
| load WDEF resource
    MOVE.W	0x12(A6),D3                          | D3 = procID parameter
    LSR.W	#0x4,D3                               | WDEF resource ID = procID / 16
NEWWINDOW_RETRY:
    SUBQ.W	#0x4,A7                              | space for GetResource result
    MOVE.L	#0x57444546,-(A7)                    | push 'WDEF' resource type
    MOVE.W	D3,-(A7)                             | push WDEF resource ID
    MOVE.W	#0xFFFF,(ROMMapInsert).W             | search ROM map first
    _GetResource                                | load WDEF
    MOVEQ.L	#0x0,D3                             | clear D3 for retry check
    MOVE.L	(A7)+,(A2)                           | store WDEF handle in windowDef
    BEQ.B	NEWWINDOW_RETRY                       | nil = not found, retry
| store variation code in low byte of windowDef handle
    MOVEQ.L	#0xF,D3                             | mask for low 4 bits
    AND.W	0x12(A6),D3                           | D3 = procID mod 16 (variation)
    MOVE.B	D3,(A2)                              | store in low byte of handle
    ADDQ.W	#0x4,A2                              | advance past windowDef
    CLR.L	(A2)+                                 | wDataHandle = nil
| create title string
    MOVE.L	0x16(A6),D3                          | D3 = title string pointer
    CLR.L	-(A7)                                 | space for NewString result
    MOVE.L	D3,-(A7)                             | push title string
    _NewString                                  | copy string to handle
    MOVE.L	(A7)+,(A2)+                          | store wTitleHandle
| measure title width for drawing
    CLR.W	-(A7)                                 | space for StringWidth result
    MOVE.L	D3,-(A7)                             | push title string
    _StringWidth                                | measure width in pixels
    MOVE.W	(A7)+,(A2)+                          | store wTitleWidth
| clear remaining fields
    CLR.L	(A2)+                                 | controlList = nil
    CLR.L	(A2)+                                 | nextWindow = nil
    CLR.L	(A2)+                                 | windowPic = nil
    MOVE.L	0x8(A6),(A2)+                        | refCon = caller's value
| send wNew message to WDEF and calculate regions
    MOVEQ.L	#0x3,D0                             | wNew message
    BSR.W	MOVEWINDOW_OK                         | call WDEF(wNew)
    BSR.W	MOVEWINDOW_EMPTY                      | calculate strucRgn/contRgn via wCalcRgns
| insert window into window list
    MOVE.L	0xE(A6),D5                           | D5 = behind parameter
    BTST	#0x0,D5                                | behind = -1 (in front of all)?
    BNE.B	NEWWINDOW_OK                          | yes -> insert at front
    TST.L	(WindowList).W                        | any windows exist?
    BEQ.B	NEWWINDOW_OK                          | no -> insert at front
    MOVE.L	A3,-(A7)                             | push new window
    MOVE.L	D5,-(A7)                             | push behind window
    BSR.W	INSERT_WINDOW                         | insert after behind window
| paint new window and recalculate visibility
NEWWINDOW_EXIT:
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	0x72(A3),-(A7)                       | push strucRgn as clobbered area
    _PaintOne                                   | paint window frame
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	0x72(A3),-(A7)                       | push strucRgn
    _CalcVBehind                                | recalc visRgn for windows behind
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D5/A2-A4                   | restore regs
    UNLK	A6                                     | tear down frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x1A,A7                             | strip 26 bytes of params
    JMP	(A0)                                    | tail-call return from NEWWINDOW_EXIT via A0
| ----------------------------------------------------------
|
| NEWWINDOW_OK - NewWindow: insert at front of window list (behind=-1 or empty list)
|
NEWWINDOW_OK:
    TST.B	0x6E(A3)                              | new window visible?
    BEQ.B	NEWWINDOW_NO                          | no -> just link into list
    SUBQ.W	#0x4,A7                              | space for FrontWindow result
    _FrontWindow                                | get current front window
    MOVE.L	(A7)+,D0                             | D0 = old front window
    BEQ.B	NEWWINDOW_SKIP                        | no old front -> skip deactivate
    BSR.W	CLOSEWINDOW_CONT                      | deactivate + unhighlight old front
NEWWINDOW_SKIP:
    MOVE.B	#0x1,0x6F(A3)                        | set hilited flag on new window
    MOVE.L	A3,(CurActivate).W                   | schedule activate event for it
NEWWINDOW_NO:
    MOVE.L	(WindowList).W,0x90(A3)              | link old list head as next
    MOVE.L	A3,(WindowList).W                    | new window becomes list head
    BRA.B	NEWWINDOW_EXIT                        | -> paint and return
| ----------------------------------------------------------
|
| NEWWINDOW_CONT_2 - cancel pending activate/deactivate events for window A3
|
| If window A3 matches CurActivate or CurDeactive, invalidates that
| entry by setting bit 7 (high byte flag). This prevents stale events
| for a window being closed.
| Called during boot.
NEWWINDOW_CONT_2:
    LEA.L	(CurActivate).W,A0                    | A0 = ptr to CurActivate
    MOVE.L	A3,D0                                | D0 = window being closed
    BSR.B	NEWWINDOW_CONT_3                      | check/cancel CurActivate
    ADDQ.W	#0x4,A0                              | advance to CurDeactive
| NEWWINDOW_CONT_3 -- check/cancel CurActivate.
NEWWINDOW_CONT_3:
    MOVE.L	(A0),D1                              | D1 = pending window ptr
    EOR.L	D0,D1                                 | compare with target
    AND.L	(Lo3Bytes).W,D1                       | mask to 24-bit address
    BNE.B	NEWWINDOW_SKIP_2                      | different window -> skip
    BSET	#0x7,(A0)                              | same window: invalidate entry
NEWWINDOW_SKIP_2:
    RTS                                         | return from NEWWINDOW_CONT_3
| ----------------------------------------------------------
|
| _CloseWindow ($A92D): close and dispose a window's data structures
| Pascal: procedure CloseWindow(theWindow: WindowPtr);
| Hides window, kills controls, sends wDispose to WDEF, frees regions.
|
CLOSEWINDOW:
    MOVEM.L	D3-D4/A3,-(A7)                      | save regs
    MOVEA.L	0x10(A7),A3                         | A3 = window to close
    BSR.W	SETWPORT                              | save port, switch to WMgr port
    BSR.B	NEWWINDOW_CONT_2                      | generate deactivate if front window
    SUBQ.W	#0x4,A7                              | space for FrontWindow result
    _FrontWindow                                | get front window (for reactivation)
    MOVE.L	A3,-(A7)                             | push window to close
    _KillControls                               | dispose all controls in this window
    MOVEQ.L	#0x4,D0                             | wDispose message
    BSR.W	MOVEWINDOW_OK                         | send wDispose to WDEF
    MOVE.L	A3,-(A7)                             | push window for ShowHide
    CLR.W	-(A7)                                 | visible = false
    _ShowHide                                   | hide the window
    MOVE.L	A3,-(A7)                             | push window for DeleteWindow
    BSR.W	DELETEWINDOW                          | remove from window list
| dispose window's allocated structures
    MOVEA.L	0x86(A3),A0                         | title string handle
    _DisposeHandle                              | free title handle
    MOVE.L	0x72(A3),-(A7)                       | push structure region
    _DisposeRgn                                 | free strucRgn
    MOVE.L	0x76(A3),-(A7)                       | push content region
    _DisposeRgn                                 | free contRgn
    MOVE.L	0x7A(A3),-(A7)                       | push update region
    _DisposeRgn                                 | free updateRgn
    MOVE.L	A3,-(A7)                             | push window
    _ClosePort                                  | close the GrafPort
    MOVE.L	0x94(A3),D0                          | D0 = window picture handle
    BEQ.B	CLOSEWINDOW_SKIP                      | nil -> skip
    MOVE.L	D0,-(A7)                             | push picture handle
    _KillPicture                                | dispose the picture
CLOSEWINDOW_SKIP:
| check if this was the front window (saved FrontWindow result on stack)
    CMPA.L	(A7)+,A3                             | was this window the front?
    BNE.B	CLOSEWINDOW_NO                        | no -> just restore port
    MOVE.W	0x6C(A3),(CurDeKind).W               | save kind for deactivate event
    SUBQ.W	#0x4,A7                              | space for FrontWindow result
    _FrontWindow                                | find new front window
    BSR.W	SELECTWINDOW_NO                       | activate the new front window
CLOSEWINDOW_NO:
    CMPA.L	D4,A3                                | was window the saved port?
    BEQ.B	CLOSEWINDOW_SKIP_2                    | yes -> don't restore (it's gone)
    BSR.W	RESTOREPORT                           | restore original port
CLOSEWINDOW_SKIP_2:
    MOVEM.L	(A7)+,D3-D4/A3                      | restore regs
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from CLOSEWINDOW_SKIP_2
| ----------------------------------------------------------
|
| CLOSEWINDOW_CONT - deactivate a window: unhighlight it and schedule deactivate event
|
| D0 = window to deactivate on entry.
| Called during boot.
CLOSEWINDOW_CONT:
    MOVE.L	D0,-(A7)                             | save window ptr
    MOVE.L	D0,-(A7)                             | push window for HiliteWindow
    CLR.W	-(A7)                                 | fHilite = false (unhighlight)
    _HiliteWindow                               | remove highlight
    MOVE.L	(A7)+,D0                             | restore window ptr
    TST.L	(CurDeactive).W                       | deactivate already pending?
    BGT.B	CLOSEWINDOW_SKIP_3                    | yes -> don't overwrite
    MOVEA.L	D0,A0                               | A0 = window
    MOVE.W	0x6C(A0),(CurDeKind).W               | save kind for deactivate event
    MOVE.L	D0,(CurDeactive).W                   | schedule deactivate event
CLOSEWINDOW_SKIP_3:
    RTS                                         | return from CLOSEWINDOW_SKIP_3
| ----------------------------------------------------------
|
| _DisposeWindow ($A914): close window and free its storage
| Pascal: procedure DisposeWindow(theWindow: WindowPtr);
|
DISPOSEWINDOW:
    MOVE.L	0x4(A7),-(A7)                        | push window for CloseWindow
    _CloseWindow                                | close and free internal structures
    MOVEA.L	(A7)+,A1                            | A1 = return address
    MOVEA.L	(A7)+,A0                            | A0 = window storage pointer
    _DisposePtr                                 | free the WindowRecord block
    JMP	(A1)                                    | tail-call return from DISPOSEWINDOW via A1
| ----------------------------------------------------------
|
| _ShowWindow ($A915): make a window visible
| If this would be the frontmost visible window, also selects it.
|
SHOWWINDOW:
    MOVEA.L	(WindowList).W,A0                   | start at front of window list
| find first visible window in front of target
SHOWWINDOW_NO:
    TST.B	0x6E(A0)                              | this window visible?
    BNE.B	SHOWWINDOW_FOUND                      | yes, found one in front ->
    CMPA.L	0x4(A7),A0                           | is this our target window?
    BEQ.B	SHOWWINDOW_OK                         | yes, it would be frontmost ->
    MOVEA.L	0x90(A0),A0                         | next window
    MOVE.L	A0,D0                                | end of list?
    BNE.B	SHOWWINDOW_NO                         | no ->
| show the window (another visible window is already in front)
SHOWWINDOW_FOUND:
    MOVEA.L	(A7)+,A1                            | save return address
    MOVE.B	#0x1,-(A7)                           | visible = true
    _ShowHide                                   | make it visible
    JMP	(A1)                                    | tail-call return from SHOWWINDOW_FOUND via A1
| target would be frontmost: select it (brings to front + activates)
SHOWWINDOW_OK:
    MOVE.L	A0,-(A7)                             | push window
    _SelectWindow                               | select (implies show)
    BRA.B	SHOWWINDOW_FOUND                      | -> show
| ----------------------------------------------------------
|
| _HideWindow ($A916): hide a window and select next visible if it was front
| Pascal: procedure HideWindow(theWindow: WindowPtr);
|
HIDEWINDOW:
    SUBQ.W	#0x4,A7                              | space for FrontWindow result
    _FrontWindow                                | get front window before hiding
    MOVE.L	0x8(A7),-(A7)                        | push target window
    CLR.W	-(A7)                                 | visible = false
    _ShowHide                                   | hide the window
    MOVE.L	(A7)+,D0                             | D0 = old front window
    CMP.L	0x4(A7),D0                            | was hidden window the front?
    BNE.B	HIDEWINDOW_DONE                       | no -> done
    BSR.B	CLOSEWINDOW_CONT                      | deactivate old front
    SUBQ.W	#0x4,A7                              | space for FrontWindow
    _FrontWindow                                | get new front window
    MOVE.L	(A7),(CurActivate).W                 | schedule activate for it
    BEQ.B	HIDEWINDOW_EMPTY                      | nil -> no window to select
    _SelectWindow                               | select the new front window
HIDEWINDOW_DONE:
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from HIDEWINDOW_DONE
| ----------------------------------------------------------
|
| HIDEWINDOW_EMPTY - no front window: discard nil FrontWindow result
|
| Called during boot.
HIDEWINDOW_EMPTY:
    ADDQ.W	#0x4,A7                              | discard nil FrontWindow result
    BRA.B	HIDEWINDOW_DONE                       | -> strip param and return
| ----------------------------------------------------------
|
| _GetWRefCon ($A917): return window's refCon value
| Pascal: function GetWRefCon(theWindow: WindowPtr): LongInt;
|
GETWREFCON:
    MOVE.W	#0x98,D1                             | offset 0x98 = refCon field
GETWREFCON_CONT:
    MOVEA.L	(A7)+,A0                            | A0 = return address
    MOVEA.L	(A7)+,A1                            | A1 = window pointer
    MOVE.L	0x0(A1,D1.W),(A7)                    | replace stack param with field value
    JMP	(A0)                                    | tail-call return from GETWREFCON_CONT via A0
| ----------------------------------------------------------
|
| _SetWRefCon ($A918): set window's refCon value
| Pascal: procedure SetWRefCon(theWindow: WindowPtr; data: LongInt);
|
SETWREFCON:
    MOVE.W	#0x98,D1                             | offset 0x98 = refCon field
SETWREFCON_CONT:
    MOVEA.L	(A7)+,A0                            | A0 = return address
    MOVE.L	(A7)+,D0                             | D0 = new value
    MOVEA.L	(A7)+,A1                            | A1 = window pointer
    MOVE.L	D0,0x0(A1,D1.W)                      | store value into field
    JMP	(A0)                                    | tail-call return from SETWREFCON_CONT via A0
| ----------------------------------------------------------
|
| _SetWindowPic ($A92E): set window's auto-draw picture handle
| Pascal: procedure SetWindowPic(theWindow: WindowPtr; pic: PicHandle);
|
SETWINDOWPIC:
    MOVE.W	#0x94,D1                             | offset 0x94 = windowPic field
    BRA.B	SETWREFCON_CONT                       | -> generic setter
| ----------------------------------------------------------
|
| _GetWindowPic ($A92F): return window's auto-draw picture handle
| Pascal: function GetWindowPic(theWindow: WindowPtr): PicHandle;
|
GETWINDOWPIC:
    MOVE.W	#0x94,D1                             | offset 0x94 = windowPic field
    BRA.B	GETWREFCON_CONT                       | -> generic getter
| ----------------------------------------------------------
|
| _GetWTitle ($A919): copy window title into caller's buffer
| Pascal: procedure GetWTitle(theWindow: WindowPtr; VAR title: Str255);
|
GETWTITLE:
    MOVEM.L	(A7)+,D1/A0-A1                      | D1=retAddr, A0=title buf, A1=window
    MOVEA.L	0x86(A1),A1                         | A1 = title string handle
    MOVEA.L	(A1),A1                             | dereference to Pascal string
    MOVEQ.L	#0x0,D0                             | clear high bytes
    MOVE.B	(A1),D0                              | D0 = string length
GETWTITLE_LOOP:
    MOVE.B	(A1)+,(A0)+                          | copy length byte + characters
    DBF.W	D0,GETWTITLE_LOOP                     | loop (length+1 bytes total)
    MOVEA.L	D1,A0                               | restore return address
    JMP	(A0)                                    | tail-call return from GETWTITLE_LOOP via A0
| ----------------------------------------------------------
|
| _SetWTitle ($A91A): change a window's title
| Pascal: procedure SetWTitle(theWindow: WindowPtr; title: Str255);
| Saves old strucRgn, updates title, recalculates regions,
| repaints if structure changed (title may change frame size).
|
SETWTITLE:
    MOVEM.L	D3-D5/A2-A3,-(A7)                   | save regs
    MOVE.L	0x18(A7),D5                          | D5 = title string ptr
    MOVEA.L	0x1C(A7),A3                         | A3 = window
    BSR.W	SETWPORT                              | save port, switch to WMgr port
    MOVEA.L	0x72(A3),A0                         | A0 = strucRgn handle
    _HandToHand                                 | duplicate strucRgn (snapshot)
    MOVE.L	A0,D3                                | D3 = old strucRgn copy
    MOVE.L	0x86(A3),D0                          | D0 = title string handle
    BEQ.B	SETWTITLE_SKIP                        | nil -> skip update
    MOVE.L	D0,-(A7)                             | push title handle
    MOVE.L	D5,-(A7)                             | push new title
    _SetString                                  | replace title string
    SUBQ.W	#0x2,A7                              | space for StringWidth result
    MOVE.L	D5,-(A7)                             | push new title
    _StringWidth                                | measure width
    MOVE.W	(A7)+,0x8A(A3)                       | store wTitleWidth
    BSR.W	MOVEWINDOW_EMPTY                      | recalc strucRgn/contRgn
    CLR.W	-(A7)                                 | space for EqualRgn result
    MOVE.L	0x72(A3),-(A7)                       | push new strucRgn
    MOVE.L	D3,-(A7)                             | push old strucRgn
    _EqualRgn                                   | did regions change?
    MOVE.W	(A7)+,D0                             | check result
    BEQ.B	SETWTITLE_NO                          | changed: full repaint
    BSR.B	SETWTITLE_CONT                        | unchanged: subtract contRgn
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	D3,-(A7)                             | push frame-only area
    _PaintOne                                   | repaint just the title bar
    BRA.B	SETWTITLE_SKIP                        | -> cleanup
| ----------------------------------------------------------
|
| SETWTITLE_NO - strucRgn changed: repaint old+new area and windows behind
|
SETWTITLE_NO:
    MOVE.L	0x72(A3),-(A7)                       | push new strucRgn
    MOVE.L	D3,-(A7)                             | push old strucRgn
    MOVE.L	D3,-(A7)                             | push dest
    _UnionRgn                                   | D3 = old union new
    BSR.B	SETWTITLE_CONT                        | subtract contRgn (frame only)
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	D3,-(A7)                             | push changed frame area
    _PaintBehind                                | repaint windows behind
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	D3,-(A7)                             | push changed area
    _CalcVBehind                                | recalc visRgns behind
SETWTITLE_SKIP:
    MOVE.L	D3,-(A7)                             | push old strucRgn copy
    _DisposeRgn                                 | free temp region
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D5/A2-A3                   | restore regs
SETWTITLE_EXIT:
    BRA.W	STRIP_2PARAMS_RTS                     | -> strip 2 params and return
| ----------------------------------------------------------
|
| SETWTITLE_CONT - subtract content region from D3 (leaving frame-only area)
|
SETWTITLE_CONT:
    MOVE.L	D3,-(A7)                             | push source
    MOVE.L	0x76(A3),-(A7)                       | push contRgn
    MOVE.L	D3,-(A7)                             | push dest
    _DiffRgn                                    | D3 = source minus contRgn
    RTS                                         | return from SETWTITLE_CONT
| ----------------------------------------------------------
|
| DELTAPOINT - compute Point delta: result = (pt2 - pt1)
| Stack on entry: pt1, pt2, result-space, return-addr.
| Called by: DELTAPOINT_CONT, NEWWINDOW_CONT, GROWWINDOW, GROWWINDOW_OK, GROWWINDOW_CONT_2 (and 1 more)
DELTAPOINT:
    MOVE.W	0x8(A7),D0                           | D0 = pt2.h
    SUB.W	0x4(A7),D0                            | D0 = pt2.h - pt1.h
    MOVE.W	D0,0xC(A7)                           | result.h
    MOVE.W	0xA(A7),D0                           | D0 = pt2.v
    SUB.W	0x6(A7),D0                            | D0 = pt2.v - pt1.v
    MOVE.W	D0,0xE(A7)                           | result.v
    BRA.B	SETWTITLE_EXIT                        | -> strip params and return
| ----------------------------------------------------------
|
| DELTAPOINT_CONT (= DELTAPOINT_CONT) - move window to new position D0 (packed point)
|
| Computes offset from current portRect origin to new position,
| then offsets strucRgn, contRgn, updateRgn, and portBounds by delta.
| D0 = new origin as packed point. D3 = computed offset on exit.
|
DELTAPOINT_CONT:
    MOVE.L	A4,-(A7)                             | push strucRgn handle for OffsetRgn
    SUBQ.W	#0x4,A7                              | space for DeltaPoint result
    MOVE.L	D0,-(A7)                             | push new position
    SUBQ.W	#0x4,A7                              | space for DeltaPoint result
    MOVE.L	0x10(A3),-(A7)                       | push current portRect.topLeft
    MOVEA.L	A3,A0                               | A0 = window for WMGR
    BSR.W	WMGR                                  | A0 = port (handles indirect ports)
    MOVE.L	0x6(A0),-(A7)                        | push portBounds.topLeft
    BSR.B	DELTAPOINT                            | delta1 = portRect - portBounds
    BSR.B	DELTAPOINT                            | delta2 = newPos - delta1
    MOVE.L	(A7),D3                              | D3 = final offset for regions
    _OffsetRgn                                  | offset strucRgn
    MOVE.L	0x76(A3),-(A7)                       | push contRgn
    MOVE.L	D3,-(A7)                             | push offset
    _OffsetRgn                                  | offset contRgn
    MOVE.L	0x7A(A3),-(A7)                       | push updateRgn
    MOVE.L	D3,-(A7)                             | push offset
    _OffsetRgn                                  | offset updateRgn
    MOVEA.L	A3,A0                               | A0 = window for WMGR
    BSR.W	WMGR                                  | A0 = port
    PEA.L	0x6(A0)                               | push portBounds rect
    MOVE.L	D3,-(A7)                             | push offset
    BSR.W	BRINGTOFRONT_CONT_2                   | negate offset for bounds
    _OffsetRect                                 | offset portBounds (reversed)
    RTS                                         | return from DELTAPOINT_CONT
| ----------------------------------------------------------
|
| _MoveWindow ($A91B): move a window to a new screen position
| Pascal: procedure MoveWindow(theWindow: WindowPtr; hGlobal,vGlobal: INTEGER;
| front: BOOLEAN);
| Optimizes by using CopyBits to blit existing pixels, then painting only
| newly exposed areas.
|
MOVEWINDOW:
    MOVEM.L	D3-D6/A3-A4,-(A7)                   | save regs
    BSR.W	SETWPORT                              | save port, switch to WMgr
    MOVEA.L	0x22(A7),A3                         | A3 = window
    BSR.W	HILITEWINDOW_CONT_3                   | clip to GrayRgn
    BSR.W	GETNEWRGN                             | allocate temp region
    MOVE.L	(A7)+,D5                             | D5 = temp region (visible old area)
    MOVEA.L	0x72(A3),A4                         | A4 = strucRgn handle

    MOVE.L	A4,-(A7)                             | push strucRgn
    MOVEA.L	(WMgrPort).W,A0                     | get WMgr port
    MOVE.L	0x1C(A0),-(A7)                       | push WMgr clipRgn
    MOVE.L	D5,-(A7)                             | push dest
    _SectRgn                                    | D5 = visible old structure area
    MOVEA.L	A4,A0                               | A0 = strucRgn handle
    _HandToHand                                 | copy old strucRgn
    MOVE.L	A0,D6                                | D6 = old strucRgn copy
    MOVE.L	0x1E(A7),D0                          | D0 = new h,v packed as point
    BSR.B	DELTAPOINT_CONT                       | offset all regions; D3 = delta
    MOVE.L	D5,-(A7)                             | push visible old area
    MOVE.L	D3,-(A7)                             | push delta offset
    _OffsetRgn                                  | shift to new position
    TST.B	0x1C(A7)                              | front parameter?
    BEQ.B	MOVEWINDOW_SKIP                       | no -> skip
    MOVE.L	(GrayRgn).W,-(A7)                    | push desktop region
    _SetClip                                    | clip to full desktop
| CopyBits to blit window pixels from old to new position
MOVEWINDOW_SKIP:
    MOVEA.L	(WMgrPort).W,A0                     | get WMgr port
    PEA.L	0x2(A0)                               | push srcBits (screen portBits)
    MOVE.L	(A7),-(A7)                           | push dstBits (same screen)
    MOVEA.L	D6,A0                               | A0 = old strucRgn copy
    MOVEA.L	(A0),A0                             | dereference
    PEA.L	0x2(A0)                               | push srcRect (old bounds)
    MOVEA.L	(A4),A0                             | dereference new strucRgn
    PEA.L	0x2(A0)                               | push dstRect (new bounds)
    CLR.W	-(A7)                                 | srcCopy transfer mode
    MOVE.L	D5,-(A7)                             | push maskRgn (visible old area)
    _CopyBits                                   | blit window pixels
    MOVE.L	A4,-(A7)                             | push new strucRgn
    MOVE.L	D5,-(A7)                             | push blitted area
    MOVE.L	D5,-(A7)                             | push dest
    _DiffRgn                                    | D5 = new area not covered by blit
    MOVE.L	0x90(A3),-(A7)                       | push next window
    MOVE.L	D6,-(A7)                             | push old strucRgn
    _PaintBehind                                | repaint exposed area at old pos
    TST.B	0x1C(A7)                              | front parameter?
    BEQ.B	MOVEWINDOW_SKIP_2                     | no -> skip
    MOVE.L	A3,-(A7)                             | push window for SelectWindow
    ST.B	(DragFlag).W                           | flag: don't repaint during select
    BSR.W	SELECTWINDOW_CONT                     | select/bring to front
MOVEWINDOW_SKIP_2:
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	D5,-(A7)                             | push newly exposed area
    _PaintOne                                   | paint window frame in new area
    MOVE.L	D6,-(A7)                             | push old strucRgn
    MOVE.L	A4,-(A7)                             | push new strucRgn
    MOVE.L	D6,-(A7)                             | push dest
    _UnionRgn                                   | D6 = old union new (full affected)
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	D6,-(A7)                             | push affected area
    _CalcVBehind                                | recalculate visRgns behind
    MOVE.L	D5,-(A7)                             | push temp region
    _DisposeRgn                                 | free it
    MOVE.L	D6,-(A7)                             | push old strucRgn copy
    _DisposeRgn                                 | free it
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D6/A3-A4                   | restore regs
    BRA.W	WMGR_STRIP_10_RTS                     | -> strip params and return
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
    CLR.L	-(A7)                                 | space for WDEF function result
    MOVEQ.L	#0x0,D1                             | clear D1
    MOVE.B	0x7E(A3),D1                          | D1 = variation code (high byte of windowDefProc)
    MOVE.W	D1,-(A7)                             | push varCode
    MOVE.L	A3,-(A7)                             | push window
    MOVE.W	D0,-(A7)                             | push message
    MOVE.L	D3,-(A7)                             | push param
    MOVEA.L	0x7E(A3),A0                         | A0 = WDEF handle
    MOVE.L	(A0),D0                              | D0 = dereferenced WDEF ptr
    BNE.B	MOVEWINDOW_CONT                       | loaded -> call it
| WDEF not in memory: load it
    MOVE.L	A0,-(A7)                             | push handle for LoadResource
    CLR.B	(A7)                                  | clear high byte (strip varCode)
    MOVE.W	#0xFFFF,(ROMMapInsert).W             | search ROM map first
    _LoadResource                               | load WDEF code
    MOVE.L	(A0),D0                              | D0 = WDEF code pointer
MOVEWINDOW_CONT:
    BSET	#0x7,(A0)                              | lock WDEF handle during call
    MOVEA.L	D0,A0                               | A0 = WDEF entry point
    JSR	(A0)                                    | call WDEF
    MOVE.L	(A7)+,D0                             | D0 = WDEF result
    MOVEA.L	0x7E(A3),A0                         | A0 = WDEF handle
    BCLR	#0x7,(A0)                              | unlock WDEF handle
    RTS                                         | return from MOVEWINDOW_CONT
| ----------------------------------------------------------
|
| MOVEWINDOW_CONT_2 - send wDraw message to WDEF (draw window frame)
|
| Preserves D3 since wDraw doesn't need a param.
| Called during boot.
MOVEWINDOW_CONT_2:
    MOVEM.L	D3,-(A7)                            | save D3
    MOVEQ.L	#0x0,D3                             | param = 0 (no highlight)
    MOVEQ.L	#0x0,D0                             | message = wDraw
    BSR.B	MOVEWINDOW_OK                         | call WDEF(wDraw, 0)
    MOVE.L	(A7)+,D3                             | restore D3
    RTS                                         | return from MOVEWINDOW_CONT_2
| ----------------------------------------------------------
|
| MOVEWINDOW_EMPTY (= MOVEWINDOW_EMPTY) - recalculate window regions
|
| If visible, sends wCalcRgns to WDEF after pushing portBounds origin
| (and color-port pixMap origin in the SE variant).
| If invisible, sets strucRgn, contRgn, and visRgn to empty.
| Called by: SHOWHIDE, NEWWINDOW_RETRY, SETWTITLE, SIZEWINDOW_REFRESH, ZOOMWINDOW
MOVEWINDOW_EMPTY:
    MOVEQ.L	#0x2,D0                             | message = wCalcRgns
    TST.B	0x6E(A3)                              | window visible?
    BEQ.B	MOVEWINDOW_INVIS_EMPTY                | no -> empty all regions
    LEA.L	0x8(A3),A1                            | A1 = portBounds (push 8-byte rect)
    MOVE.L	(A1)+,-(A7)                          | push portBounds.topLeft
    MOVE.L	(A1)+,-(A7)                          | push portBounds.botRight
    TST.W	0x6(A3)                               | rowBytes high bit (color port)?
    BPL.B	MOVEWINDOW_CALCRGNS                   | regular bitMap -> skip pixMap fix
    MOVEA.L	0x2(A3),A0                          | A0 = pixMap handle
    MOVEA.L	(A0),A0                             | dereference
    MOVE.L	0xA(A0),-(A1)                        | overwrite botRight with pixMap bounds
    MOVE.L	0x6(A0),-(A1)                        | overwrite topLeft with pixMap bounds
MOVEWINDOW_CALCRGNS:
    BSR.B	MOVEWINDOW_OK                         | call WDEF(wCalcRgns)
    MOVE.L	(A7)+,0xC(A3)                        | restore portBounds.botRight
    MOVE.L	(A7)+,0x8(A3)                        | restore portBounds.topLeft
    RTS                                         | return from MOVEWINDOW_EMPTY
| invisible: empty all regions
MOVEWINDOW_INVIS_EMPTY:
    MOVE.L	0x72(A3),-(A7)                       | push strucRgn
    _SetEmptyRgn                                | set empty
    MOVE.L	0x76(A3),-(A7)                       | push contRgn
    _SetEmptyRgn                                | set empty
    MOVE.L	0x18(A3),-(A7)                       | push visRgn
    _SetEmptyRgn                                | set empty
    RTS                                         | return from MOVEWINDOW_EMPTY
| ----------------------------------------------------------
|
| _HiliteWindow ($A91C): highlight or unhighlight a window's title bar
| Pascal: procedure HiliteWindow(theWindow: WindowPtr; fHilite: BOOLEAN);
| Only acts if the highlight state is actually changing.
|
HILITEWINDOW:
    MOVEM.L	D3-D4/A3-A4,-(A7)                   | save regs
    MOVEA.L	0x16(A7),A3                         | A3 = window
    MOVE.B	0x14(A7),D3                          | D3 = desired highlight state
    BSR.W	SETWPORT                              | save port, switch to WMgr
    MOVE.B	0x6F(A3),D0                          | D0 = current hilited flag
    EOR.W	D3,D0                                 | test if changing
    LSR.W	#0x1,D0                               | bit 0 -> carry
    BCC.B	HILITEWINDOW_RESTORE                  | no change -> skip
    MOVE.B	D3,0x6F(A3)                          | set new hilited state
    BSR.B	HILITEWINDOW_CONT                     | set clip to strucRgn above window
    BSR.B	MOVEWINDOW_CONT_2                     | send wDraw to WDEF (redraws frame)
HILITEWINDOW_RESTORE:
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D4/A3-A4                   | restore regs
    BRA.W	DRAWNEW_EXIT                          | -> strip params and return
| ----------------------------------------------------------
|
| HILITEWINDOW_CONT - clip WMgr port to window's strucRgn minus windows above
|
| Called during boot.
HILITEWINDOW_CONT:
    MOVE.L	0x72(A3),-(A7)                       | push strucRgn
HILITEWINDOW_CONT_2:
    _SetClip                                    | clip to that region
    MOVE.L	A3,-(A7)                             | push window
    _ClipAbove                                  | clip above this window (subtract front)
    RTS                                         | return from HILITEWINDOW_CONT_2
| ----------------------------------------------------------
|
| HILITEWINDOW_CONT_3 - clip WMgr port to GrayRgn (desktop) minus windows above A3
|
HILITEWINDOW_CONT_3:
    MOVE.L	(GrayRgn).W,-(A7)                    | push desktop region as initial clip
    BRA.B	HILITEWINDOW_CONT_2                   | -> SetClip, ClipAbove
| ----------------------------------------------------------
|
| _SizeWindow ($A91D): resize a window
| Pascal: procedure SizeWindow(theWindow: WindowPtr; w,h: INTEGER;
| fUpdate: BOOLEAN);
| Computes new portRect.botRight from size, then redraws if visible.
|
SIZEWINDOW:
    MOVEM.L	D3-D4/A3-A4,-(A7)                   | save regs
    MOVE.L	0x16(A7),D3                          | D3 = new height (h param)
    BEQ.B	SIZEWINDOW_DONE                       | zero size -> skip
    MOVEA.L	0x1A(A7),A3                         | A3 = window
    MOVE.W	0x16(A7),D4                          | D4 = new width (w param, low word)
    LEA.L	0x10(A3),A4                           | A4 = portRect
    ADD.W	(A4)+,D4                              | D4 = portRect.top + width = new bottom
    ADD.W	(A4)+,D3                              | D3 = portRect.left + height = new right
    MOVE.W	D4,(A4)+                             | store new portRect.bottom
    MOVE.W	D3,(A4)+                             | store new portRect.right
    TST.B	0x6E(A3)                              | window visible?
    BEQ.B	SIZEWINDOW_DONE                       | no -> done
    BSR.W	SETWPORT                              | save port, switch to WMgr
    MOVE.L	A3,-(A7)                             | push window
    _SaveOld                                    | snapshot old regions
    MOVE.B	0x14(A7),D3                          | D3 = fUpdate parameter
    BSR.B	SIZEWINDOW_REFRESH                    | recalc, redraw, DrawNew
SIZEWINDOW_DONE:
    MOVEM.L	(A7)+,D3-D4/A3-A4                   | restore regs
| ----------------------------------------------------------
| WMGR_STRIP_10_RTS - strip 10 bytes of params and return.
WMGR_STRIP_10_RTS:
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0xA,A7                              | strip params
    JMP	(A0)                                    | tail-call return from WMGR_STRIP_10_RTS via A0
| ----------------------------------------------------------
|
| SIZEWINDOW_REFRESH - recalculate regions, redraw frame, call DrawNew
|
| Used after SizeWindow/ZoomWindow when window is visible.
| D3 = fUpdate parameter for DrawNew.
SIZEWINDOW_REFRESH:
    BSR.W	MOVEWINDOW_EMPTY                      | recalculate strucRgn/contRgn
    BSR.B	HILITEWINDOW_CONT                     | clip to strucRgn above window
    BSR.W	MOVEWINDOW_CONT_2                     | send wDraw to WDEF (redraw frame)
    MOVE.L	A3,-(A7)                             | push window
    MOVE.B	D3,-(A7)                             | push fUpdate flag
    _DrawNew                                    | repaint changed areas
    BSR.W	RESTOREPORT                           | restore original port
    RTS                                         | return from SIZEWINDOW_REFRESH
| ----------------------------------------------------------
|
| _ZoomWindow ($A95C): zoom window between standard and user state
|
| partCode 7 = inZoomIn (restore to user state)
| partCode 8 = inZoomOut (zoom to standard state)
| wDataHandle contains two rects: user state (0..7), standard state (8..15)
|
ZOOMWINDOW:
    MOVEM.L	D3-D6/A2-A4,-(A7)                   | save regs
    BSR.W	SETWPORT                              | save port, switch to WMgr
    MOVEA.L	0x24(A7),A3                         | A3 = window
    BSR.W	MOVEWINDOW_EMPTY                      | recalculate current regions
    MOVE.L	A3,-(A7)                             | push window
    _SaveOld                                    | snapshot current regions
| get zoom state rect from wDataHandle
    MOVEA.L	0x82(A3),A2                         | A2 = WDEF data handle
    MOVEA.L	(A2),A2                             | dereference to zoom state data
    CMPI.W	#0x7,0x22(A7)                        | partCode = inZoomIn (7)?
    BEQ.B	ZOOMWINDOW_OK                         | yes -> use user state (offset 0)
    ADDQ.W	#0x8,A2                              | no -> use standard state (offset 8)
ZOOMWINDOW_OK:
| move window origin to zoom state's topLeft
    MOVEA.L	0x72(A3),A4                         | A4 = strucRgn handle
    MOVE.L	(A2)+,D0                             | D0 = zoom rect topLeft
    BSR.W	DELTAPOINT_CONT                       | offset all regions to new position
| compute new portRect size from zoom state rect
    MOVE.W	(A2)+,D0                             | D0 = zoom rect.bottom
    MOVE.W	(A2)+,D1                             | D1 = zoom rect.right
    SUBQ.W	#0x8,A2                              | back to start of zoom rect
    SUB.W	(A2)+,D0                              | D0 = height (bottom - top)
    SUB.W	(A2)+,D1                              | D1 = width (right - left)
    LEA.L	0x10(A3),A0                           | A0 = portRect
    ADD.W	(A0)+,D0                              | D0 = top + height = new bottom
    ADD.W	(A0)+,D1                              | D1 = left + width = new right
    MOVE.W	D0,(A0)+                             | set portRect.bottom
    MOVE.W	D1,(A0)+                             | set portRect.right
| redraw at new size
    MOVEQ.L	#0x1,D3                             | fUpdate = true
    BSR.B	SIZEWINDOW_REFRESH                    | recalc, redraw, DrawNew
| optionally bring to front
    TST.B	0x20(A7)                              | front parameter?
    BEQ.B	ZOOMWINDOW_SKIP                       | no -> skip
    MOVE.L	A3,-(A7)                             | push window
    ST.B	(DragFlag).W                           | suppress repaint during select
    BSR.W	SELECTWINDOW_CONT                     | select window
ZOOMWINDOW_SKIP:
    PEA.L	0x10(A3)                              | push portRect
    _InvalRect                                  | invalidate entire content for redraw
    MOVEM.L	(A7)+,D3-D6/A2-A4                   | restore regs
    BRA.W	STRIP_2PARAMS_RTS                     | -> strip params and return
| ----------------------------------------------------------
|
| _TrackGoAway ($A91E): track mouse in go-away box
| Pascal: function TrackGoAway(theWindow: WindowPtr; thePt: Point): BOOLEAN;
| Returns true if mouse released inside go-away box.
| Falls through to TRACKBOX (generic part-tracking loop).
|
TRACKGOAWAY:
    MOVEA.L	(A7)+,A0                            | pop return address
    MOVE.W	#0x6,-(A7)                           | push partCode 6 (inGoAway)
    MOVE.L	A0,-(A7)                             | restore return address
| ----------------------------------------------------------
| TRACKBOX (= AddComp) - generic WDEF part tracking loop (go-away, zoom)
| Shared by TrackGoAway and TrackBox. Tracks mouse, toggling
| the part highlight while mouse is inside, returns result.
TRACKBOX:
    LINK	A6,#-0x4                               | local var: mouse point
    MOVEM.L	D3-D6/A3,-(A7)                      | save regs
    BSR.W	SETWPORT                              | save port, switch to WMgr
    LEA.L	0x8(A6),A0                            | A0 = stack params
    MOVE.W	(A0)+,D6                             | D6 = partCode
    SUBQ.W	#0x2,D6                              | adjust for WDEF hit result offset
    MOVE.L	(A0)+,-0x4(A6)                       | save startPt in local var
    MOVEA.L	(A0)+,A3                            | A3 = window
    CLR.W	(A0)                                  | result = false initially
    MOVEQ.L	#0x0,D5                             | D5 = current highlight state (off)
    BSR.W	HILITEWINDOW_CONT                     | clip to strucRgn above window
| tracking loop: send wHit to WDEF, toggle highlight as needed
TRACKBOX_OK:
    MOVEQ.L	#0x1,D0                             | message = wHit
    MOVE.L	-0x4(A6),D3                          | D3 = current mouse point
    BSR.W	MOVEWINDOW_OK                         | call WDEF(wHit, mousePt)
    CMP.W	D6,D0                                 | hit result matches target part?
    BEQ.B	TRACKBOX_OK_2                         | yes -> mouse is in part
    MOVEQ.L	#0x0,D0                             | no -> mouse outside part
TRACKBOX_OK_2:
    CMP.W	D0,D5                                 | highlight state changed?
    BEQ.B	TRACKBOX_SKIP                         | no -> skip redraw
    MOVE.W	D0,D5                                | update highlight state
    BSR.B	TRACKBOX_CONT                         | toggle part highlight via wDraw
TRACKBOX_SKIP:
    PEA.L	-0x4(A6)                              | push local mouse point addr
    _GetMouse                                   | read current mouse position
    BSR.W	DRAGTHERGN_CONT_3                     | call DragHook if installed
    CLR.W	-(A7)                                 | space for WaitMouseUp result
    _WaitMouseUp                                | wait for next mouse event
    TST.B	(A7)+                                 | mouse still down?
    BNE.B	TRACKBOX_OK                           | yes -> continue tracking
| mouse released
    TST.W	D5                                    | was highlight on at release?
    BEQ.B	TRACKBOX_RESTORE                      | no -> result stays false
    ADDQ.B	#0x1,0x12(A6)                        | result = true (released in part)
    BSR.B	TRACKBOX_CONT                         | toggle highlight off
TRACKBOX_RESTORE:
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D6/A3                      | restore regs
    UNLK	A6                                     | tear down frame
    BRA.W	WMGR_STRIP_10_RTS                     | -> strip params and return
| ----------------------------------------------------------
|
| TRACKBOX_CONT (= TRACKBOX_CONT) - toggle WDEF part highlight via wDraw
|
TRACKBOX_CONT:
    MOVEQ.L	#0x0,D0                             | message = wDraw
    MOVE.W	D6,D3                                | param = partCode (for highlight)
    BSR.W	MOVEWINDOW_OK                         | call WDEF(wDraw, partCode)
    RTS                                         | return from TRACKBOX_CONT
| ----------------------------------------------------------
|
| _SelectWindow ($A91F): bring a window to front and activate it
| Deactivates old front window, brings target to front, activates it.
|
SELECTWINDOW:
    CLR.B	(DragFlag).W                          | clear drag state
| SELECTWINDOW_CONT -- select/bring to front.
SELECTWINDOW_CONT:
    SUBQ.W	#0x4,A7                              | space for FrontWindow result
    _FrontWindow                                | get current front window
    MOVE.L	0x8(A7),-(A7)                        | push target window
    BSR.B	BRINGTOFRONT_CONT                     | BringToFront
    MOVE.L	(A7)+,D0                             | D0 = old front window
    BEQ.B	SELECTWINDOW_NO                       | no old front ->
    CMP.L	0x4(A7),D0                            | same as target?
    BEQ.B	SELECTWINDOW_OK                       | yes, no change ->
    BSR.W	CLOSEWINDOW_CONT                      | deactivate old front window
| SELECTWINDOW_NO -- activate the new front window.
SELECTWINDOW_NO:
    MOVE.L	0x4(A7),D0                           | D0 = target window
    MOVE.L	D0,(CurActivate).W                   | schedule activate event for it
    BEQ.B	SELECTWINDOW_EMPTY                    | nil window ->
SELECTWINDOW_OK:
    MOVE.L	D0,-(A7)                             | push window for HiliteWindow
    ST.B	-(A7)                                  | fHilite = true (highlight)
    _HiliteWindow                               | highlight the window
SELECTWINDOW_EMPTY:
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from SELECTWINDOW_EMPTY
| ----------------------------------------------------------
|
| _BringToFront ($A920): move a window to front of window list
| Pascal: procedure BringToFront(theWindow: WindowPtr);
| Accumulates obscured areas from windows above, removes from list,
| inserts at front, and repaints newly visible areas.
|
BRINGTOFRONT:
    CLR.B	(DragFlag).W                          | clear drag optimization flag
| ----------------------------------------------------------
| BRINGTOFRONT_CONT (= BRINGTOFRONT_CONT) - implementation
BRINGTOFRONT_CONT:
    MOVEM.L	D3-D6/A2-A4,-(A7)                   | save regs
    MOVEA.L	0x20(A7),A3                         | A3 = target window
    BSR.W	SETWPORT                              | save port, switch to WMgr
    LEA.L	(WindowList).W,A2                     | A2 = ptr to window list head
    CMPA.L	(A2),A3                              | already at front?
    BEQ.B	SENDBEHIND_RESTORE                    | yes -> nothing to do
    BSR.W	GETNEWRGN                             | allocate temp region
    MOVE.L	(A7)+,D3                             | D3 = obscured area accumulator
    MOVEA.L	(A2),A4                             | A4 = current window (start at front)
| walk windows above target, accumulating areas that overlap target
BRINGTOFRONT_NO:
    CMPA.L	A3,A4                                | reached target window?
    BEQ.B	BRINGTOFRONT_UNLINK                   | yes -> done scanning
    TST.B	0x6E(A4)                              | this window visible?
    BEQ.B	BRINGTOFRONT_NEXT                     | no -> skip
| compute this window's visRgn that overlaps target, in global coords
    MOVEA.L	A4,A0                               | A0 = window for WMGR
    BSR.W	WMGR                                  | A0 = port (handles indirect)
    MOVE.L	0x6(A0),D6                           | D6 = portBounds.topLeft (for offset)
    MOVE.L	0x18(A4),D5                          | D5 = visRgn handle
    MOVE.L	D5,-(A7)                             | push visRgn
    MOVE.L	D6,-(A7)                             | push offset
    BSR.B	BRINGTOFRONT_CONT_2                   | negate offset
    _OffsetRgn                                  | convert visRgn to global coords
    MOVE.L	D5,-(A7)                             | push visRgn (global)
    MOVE.L	0x72(A3),-(A7)                       | push target's strucRgn
    MOVE.L	D5,-(A7)                             | push dest
    _DiffRgn                                    | visRgn -= target strucRgn
    MOVE.L	D5,-(A7)                             | push modified visRgn
    MOVE.L	D6,-(A7)                             | push offset
    _OffsetRgn                                  | convert back to local coords
| accumulate the overlap into D3
    MOVE.L	0x72(A4),-(A7)                       | push this window's strucRgn
    MOVE.L	D3,-(A7)                             | push accumulator
    MOVE.L	D3,-(A7)                             | push dest
    _UnionRgn                                   | D3 |= strucRgn of above window
BRINGTOFRONT_NEXT:
    MOVEA.L	0x90(A4),A4                         | next window in list
    MOVE.L	A4,D0                                | end of list?
    BNE.B	BRINGTOFRONT_NO                       | no -> continue
BRINGTOFRONT_UNLINK:
| remove target from current position and insert at front
    MOVE.L	A3,-(A7)                             | push window
    BSR.W	DELETEWINDOW                          | unlink from window list
    MOVE.L	(A2),0x90(A3)                        | link old head as next
    MOVE.L	A3,(A2)                              | target becomes new head
| repaint newly visible area (unless dragging, which handles it)
    TST.B	(DragFlag).W                          | drag optimization active?
    BNE.B	BRINGTOFRONT_SKIP_2                   | yes -> skip repaint
    MOVE.L	0x72(A3),-(A7)                       | push target's strucRgn
    MOVE.L	D3,-(A7)                             | push obscured area
    MOVE.L	D3,-(A7)                             | push dest
    _SectRgn                                    | D3 = newly visible portion
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	D3,-(A7)                             | push area to repaint
    _PaintOne                                   | repaint window frame
BRINGTOFRONT_SKIP_2:
    MOVE.L	A3,-(A7)                             | push window
    _CalcVis                                    | recalculate visRgn
    MOVE.L	D3,-(A7)                             | push temp region
    _DisposeRgn                                 | free it
SENDBEHIND_RESTORE:
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D6/A2-A4                   | restore regs
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from BringToFront
| ----------------------------------------------------------
|
| BRINGTOFRONT_CONT_2 - negate a point on the stack (reverse an offset)
|
| Negates the v and h components of a point at SP+4.
| Called during boot.
BRINGTOFRONT_CONT_2:
    NEG.W	0x4(A7)                               | negate v component
    NEG.W	0x6(A7)                               | negate h component
    RTS                                         | return from BRINGTOFRONT_CONT_2
| ----------------------------------------------------------
|
| _SendBehind ($A921): send a window behind another in the window list
| Pascal: procedure SendBehind(theWindow: WindowPtr; behindWindow: WindowPtr);
| If theWindow was front, selects the next visible window first.
|
SENDBEHIND:
    MOVEM.L	D3-D4/A3,-(A7)                      | save regs
    MOVEA.L	0x14(A7),A3                         | A3 = window to send behind
    BSR.W	SETWPORT                              | save port, switch to WMgr
    SUBQ.W	#0x4,A7                              | space for FrontWindow
    _FrontWindow                                | get current front window
    CMPA.L	(A7)+,A3                             | is target the front window?
    BNE.B	SENDBEHIND_REINSERT                   | no -> just reorder
| target was front: select next visible window
    MOVEA.L	A3,A0                               | A0 = target window
SENDBEHIND_NO:
    MOVEA.L	0x90(A0),A0                         | walk to next window
    MOVE.L	A0,D0                                | end of list?
    BEQ.B	SENDBEHIND_REINSERT                   | yes -> no window to select
    TST.B	0x6E(A0)                              | this window visible?
    BEQ.B	SENDBEHIND_NO                         | no -> keep looking
    MOVE.L	A0,-(A7)                             | push next visible window
    _SelectWindow                               | select it as new front
SENDBEHIND_REINSERT:
| remove target and reinsert behind specified window
    MOVE.L	A3,-(A7)                             | push window
    BSR.W	DELETEWINDOW                          | remove from window list
    MOVE.L	0x72(A3),D3                          | D3 = strucRgn (clobbered area)
    MOVE.L	0x90(A3),-(A7)                       | push next window (for PaintBehind)
    MOVE.L	(A7),-(A7)                           | dup for CalcVBehind
    MOVE.L	A3,-(A7)                             | push window
    MOVE.L	0x1C(A7),-(A7)                       | push behindWindow parameter
    BSR.W	INSERT_WINDOW                         | insert window behind target
    MOVE.L	D3,-(A7)                             | push clobbered area
    _CalcVBehind                                | recalculate visRgns behind
    MOVE.L	D3,-(A7)                             | push clobbered area
    _PaintBehind                                | repaint exposed area
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D4/A3                      | restore regs
    BRA.W	STRIP_2PARAMS_RTS                     | -> strip params and return
| ----------------------------------------------------------
|
| _BeginUpdate ($A922): set up for redrawing a window's update region
| Saves current visRgn, replaces it with intersection of visRgn and updateRgn.
| Clears updateRgn so future calls know the update is handled.
|
BEGINUPDATE:
    MOVEM.L	D3-D4/A3,-(A7)                      | save regs
    MOVEA.L	0x10(A7),A3                         | A3 = window
    MOVEA.L	A3,A0                               | A0 = window for WMGR
    BSR.W	WMGR                                  | A0 = port
    MOVE.L	0x6(A0),D3                           | D3 = port origin (for offset)
    MOVE.L	0x18(A3),D4                          | D4 = visRgn handle
| convert visRgn to global coords for intersection with updateRgn
    MOVE.L	D4,-(A7)                             | push visRgn
    MOVE.L	D3,-(A7)                             | push offset
    BSR.B	BRINGTOFRONT_CONT_2                   | negate offset
    _OffsetRgn                                  | visRgn -> global coords
| save original visRgn for EndUpdate restore
    MOVE.L	D4,-(A7)                             | push visRgn (source)
    MOVE.L	(SaveVisRgn).W,-(A7)                 | save into SaveVisRgn
    _CopyRgn                                    | SaveVisRgn = copy of visRgn
| clip visRgn to updateRgn (only draw what needs updating)
    MOVE.L	D4,-(A7)                             | visRgn
    MOVE.L	0x7A(A3),-(A7)                       | updateRgn
    MOVE.L	D4,-(A7)                             | result -> visRgn
    _SectRgn                                    | visRgn = visRgn AND updateRgn
| convert back to local coords
    MOVE.L	D4,-(A7)                             | push visRgn for offset
    MOVE.L	D3,-(A7)                             | push local-to-global offset
    _OffsetRgn                                  | visRgn -> local coords
| clear updateRgn (update is now being handled)
    MOVE.L	0x7A(A3),-(A7)                       | push updateRgn handle
    _SetEmptyRgn                                | updateRgn = empty
    BRA.W	CLOSEWINDOW_SKIP_2                    | -> strip params
| ----------------------------------------------------------
|
| _EndUpdate ($A923): restore visRgn after update drawing is complete
| Pascal: procedure EndUpdate(theWindow: WindowPtr);
|
ENDUPDATE:
    MOVE.L	A3,-(A7)                             | save A3
    MOVEA.L	0x8(A7),A3                          | A3 = window
    MOVE.L	(SaveVisRgn).W,-(A7)                 | push SaveVisRgn handle
    MOVE.L	(A7),-(A7)                           | dup for OffsetRgn
    MOVE.L	(A7),-(A7)                           | dup again for CopyRgn source
    MOVEA.L	A3,A0                               | A0 = window for WMGR
    BSR.W	WMGR                                  | A0 = port
    MOVE.L	0x6(A0),-(A7)                        | push portBounds offset
    _OffsetRgn                                  | convert SaveVisRgn to local coords
    MOVE.L	0x18(A3),-(A7)                       | push visRgn (dest)
    _CopyRgn                                    | visRgn = saved visRgn
    _SetEmptyRgn                                | empty SaveVisRgn for next use
    MOVEA.L	(A7)+,A3                            | restore A3
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from EndUpdate
| ----------------------------------------------------------
|
| _FrontWindow ($A924): return the frontmost visible window
| Pascal: function FrontWindow: WindowPtr;
| Scans window list, skipping invisible and ghost windows.
|
FRONTWINDOW:
    CLR.L	0x4(A7)                               | result = nil initially
    TST.B	(WWExist).W                           | window manager exists?
    BNE.B	FRONTWINDOW_EXIT_2                    | no -> return nil
    MOVEA.L	(WindowList).W,A0                   | A0 = first window in list
FRONTWINDOW_LOOP:
    MOVE.L	A0,D0                                | end of list?
    BEQ.B	FRONTWINDOW_EXIT                      | yes -> return nil
    CMPA.L	(GhostWindow).W,A0                   | is this the ghost window?
    BEQ.B	FRONTWINDOW_SKIP                      | yes -> skip it
    TST.B	0x6E(A0)                              | window visible?
    BNE.B	FRONTWINDOW_EXIT                      | yes -> found it
FRONTWINDOW_SKIP:
    MOVEA.L	0x90(A0),A0                         | next window in list
    BRA.B	FRONTWINDOW_LOOP                      | loop
| ----------------------------------------------------------
|
| FRONTWINDOW_EXIT - FrontWindow: return found window
|
| Called during boot (14,779 times in 30s trace).
FRONTWINDOW_EXIT:
    MOVE.L	A0,0x4(A7)                           | store result on stack
FRONTWINDOW_EXIT_2:
    RTS                                         | return from FRONTWINDOW_EXIT_2
| ----------------------------------------------------------
|
| _DragWindow ($A925): drag a window to a new position
| Pascal: procedure DragWindow(theWindow: WindowPtr; startPt: Point;
| boundsRect: Rect);
| Draws gray outline while tracking mouse, moves window on release.
|
DRAGWINDOW:
    LINK	A6,#-0x24                              | 36 bytes local vars (rects, regions)
    MOVEM.L	D3-D6/A3-A4,-(A7)                   | save regs
    SUBQ.W	#0x2,A7                              | space for WaitMouseUp result
    _WaitMouseUp                                | wait for button release (debounce)
    TST.B	(A7)+                                 | mouse still down?
    BEQ.W	DRAGWINDOW_NO                         | no, cancel drag ->
| clamp drag bounds to keep title bar visible
    MOVEA.L	0x8(A6),A0                          | A0 = boundsRect parameter
    MOVE.W	(A0)+,D0                             | D0 = bounds.top
    MOVE.W	(MBarHeight).W,D1                    | D1 = menu bar height
    ADDQ.W	#0x4,D1                              | + 4 pixels below menu bar
    CMP.W	D1,D0                                 | bounds.top below menu bar?
    BCC.B	DRAGWINDOW_OK                         | yes ->
    MOVE.W	D1,D0                                | clamp to just below menu bar
DRAGWINDOW_OK:
| build local drag bounds rect
    LEA.L	-0x10(A6),A1                          | A1 = local drag rect
    MOVE.W	D0,(A1)+                             | store clamped top
    MOVE.W	(A0)+,(A1)+                          | copy bounds.left
    MOVE.L	(A0),(A1)                            | copy bounds.bottom, bounds.right
    MOVE.L	0xC(A6),D3                           | D3 = startPt
    MOVEA.L	0x10(A6),A3                         | A3 = window
    BSR.W	SETWPORT                              | save port, switch to WMgr
    MOVE.L	(GrayRgn).W,-(A7)                    | push desktop region
    _SetClip                                    | clip to desktop
| check if Command key held (for "bring to front" behavior)
    PEA.L	-0x24(A6)                             | push local key map buffer
    _GetKeys                                    | read current key state
    MOVE.B	-0x1E(A6),D6                         | D6 = Command key byte
    BPL.B	DRAGWINDOW_BEGIN_GRAY                 | Command not held -> skip
    BSR.W	HILITEWINDOW_CONT_3                   | also clip above target window
DRAGWINDOW_BEGIN_GRAY:
| copy strucRgn and initiate gray drag tracking
    BSR.W	GETNEWRGN                             | allocate drag outline region
    MOVEA.L	(A7),A4                             | A4 = drag region handle
    MOVE.L	0x72(A3),-(A7)                       | push strucRgn
    MOVE.L	A4,-(A7)                             | push dest
    _CopyRgn                                    | copy strucRgn as drag outline
    MOVE.L	A4,-(A7)                             | push drag region
    MOVE.L	D3,-(A7)                             | push startPt
    PEA.L	-0x10(A6)                             | push drag bounds rect
    MOVE.L	(A7),-(A7)                           | push slopRect (same as bounds)
    CLR.W	-(A7)                                 | axis = noConstraint
    CLR.L	-(A7)                                 | actionProc = nil
    _DragGrayRgn                                | track gray outline drag
| evaluate drag result
    MOVE.L	(A7)+,D5                             | D5 = drag result (dv:dh)
    BEQ.B	DRAGWINDOW_EMPTY                      | zero offset -> just select
    CMPI.W	#0x8000,D5                           | drag cancelled?
    BEQ.B	DRAGWINDOW_SKIP_2                     | yes -> cleanup
| compute new window position from drag offset
    MOVE.L	A3,-(A7)                             | push window for MoveWindow
    MOVE.L	0x10(A3),D0                          | D0 = portRect.top (high word used)
    MOVEA.L	A3,A0                               | A0 = window for WMGR
    BSR.W	WMGR                                  | A0 = port
    SUB.W	0x8(A0),D0                            | subtract portBounds.top (global y)
    ADD.W	D5,D0                                 | add vertical drag offset
    MOVE.W	D0,-(A7)                             | push new vGlobal
    SWAP.W	D0                                   | get horizontal component
    SWAP.W	D5                                   | get horizontal drag offset
    SUB.W	0x6(A0),D0                            | subtract portBounds.left (global x)
    ADD.W	D5,D0                                 | add horizontal drag offset
    MOVE.W	D0,-(A7)                             | push new hGlobal
    TST.B	D6                                    | Command key held?
    SPL.B	-(A7)                                 | front = true unless Cmd held
    _MoveWindow                                 | move to new position
DRAGWINDOW_SKIP_2:
    MOVE.L	A4,-(A7)                             | push drag region
    _DisposeRgn                                 | free it
    BSR.W	RESTOREPORT                           | restore original port
DRAGWINDOW_NO:
    MOVEM.L	(A7)+,D3-D6/A3-A4                   | restore regs
    UNLK	A6                                     | tear down frame
    BRA.W	GROWWINDOW_EXIT_2                     | -> strip params and return
| ----------------------------------------------------------
|
| DRAGWINDOW_EMPTY - zero drag offset: window not moved, select if Cmd not held
|
DRAGWINDOW_EMPTY:
    TST.B	D6                                    | Command key held?
    BMI.B	DRAGWINDOW_SKIP_2                     | yes -> don't select, cleanup
    MOVE.L	A3,-(A7)                             | push window
    _SelectWindow                               | select (bring to front)
    BRA.B	DRAGWINDOW_SKIP_2                     | -> cleanup
| ----------------------------------------------------------
| Window Manager gray pattern (50% checkerboard, same as QD gray):
| #.#.#.#. 0xAA Used for window drag outlines
| .#.#.#.# 0x55 and desktop background pattern
WMGRGRAY:
    .short	0xAA55                               | rows 1-2: AA, 55 (checkerboard)
    .short	0xAA55                               | rows 3-4: AA, 55
DT_mWMgrGray_4:
    .short	0xAA55                               | rows 5-6: AA, 55
    .short	0xAA55                               | rows 7-8: AA, 55
| ----------------------------------------------------------
|
| _DragGrayRgn ($A905): drag a gray outline region tracking the mouse
| Sets up gray pattern, falls into DragTheRgn.
|
DRAGGRAYRGN:
    MOVE.L	WMGRGRAY(PC),(DragPattern).W         | load gray pattern (first 4 bytes)
    MOVE.L	DT_mWMgrGray_4(PC),(DragPattern_1).W | load gray pattern (last 4 bytes)
| ----------------------------------------------------------
|
| _DragTheRgn ($A926): generic region-dragging loop
| Stack params: region, startPt, limitRect, slopRect, axis, actionProc
| Returns: packed dv:dh offset (0x80008000 if cancelled).
|
DRAGTHERGN:
    LINK	A6,#-0x14                              | local vars: PenState + scratch
    MOVEM.L	D3-D5/A3,-(A7)                      | save regs
    LEA.L	0x16(A6),A0                           | A0 = stack params
    MOVE.L	(A0)+,D3                             | D3 = startPt
    MOVEA.L	(A0)+,A3                            | A3 = region handle to drag
    CLR.L	(A0)                                  | clear result location
| set up XOR pen for gray outline drawing
    PEA.L	-0x14(A6)                             | push local PenState buffer
    MOVE.L	(A7),-(A7)                           | dup for GetPenState
    _GetPenState                                | save current pen state
    PEA.L	(DragPattern).W                       | push gray pattern
    _PenPat                                     | set pen pattern to gray
    MOVE.W	#0xE,-(A7)                           | patXor mode
    _PenMode                                    | set XOR drawing mode
| create outline: region minus inset copy (hollow frame)
    MOVE.L	A3,-(A7)                             | push source region
    BSR.W	GETNEWRGN                             | allocate temp region
    MOVE.L	(A7),D4                              | D4 = temp region handle
    _CopyRgn                                    | temp = copy of drag region
    MOVE.L	D4,-(A7)                             | push temp
    MOVE.L	(OneOne).W,-(A7)                     | push inset amount (1,1)
    _InsetRgn                                   | shrink temp by 1 pixel
    MOVE.L	A3,-(A7)                             | push original region
    MOVE.L	D4,-(A7)                             | push inset copy
    MOVE.L	A3,-(A7)                             | push dest
    _DiffRgn                                    | A3 = outline (original minus inset)
    MOVE.L	D4,-(A7)                             | push temp
    _DisposeRgn                                 | free temp
| draw initial outline
    MOVE.L	A3,-(A7)                             | push outline region
    _PaintRgn                                   | draw gray outline (XOR on)
    MOVEQ.L	#-0x1,D5                            | D5 = outline visible flag (-1=drawn)
| main tracking loop
DRAGTHERGN_OK:
    SUBQ.W	#0x6,A7                              | space for GetMouse result + PtInRect
    MOVE.L	A7,-(A7)                             | push ptr to result
    _GetMouse                                   | read current mouse position
    MOVE.L	(A7),D4                              | D4 = current mouse (v:h)
    MOVE.L	0x12(A6),-(A7)                       | push limitRect
    _PtInRect                                   | mouse inside limit?
    TST.B	(A7)+                                 | check result
    BEQ.W	DRAGTHERGN_CONT_4                     | outside limit -> check slop rect
| mouse inside limit rect: compute delta and move outline
DRAGTHERGN_CONT:
    MOVE.L	D4,D1                                | D1 = current mouse
    SWAP.W	D1                                   | D1 = horizontal component
    CMP.L	D4,D3                                 | mouse moved from last position?
    BEQ.B	DRAGTHERGN_SKIP_2                     | no -> skip outline move
    MOVE.L	D4,-(A7)                             | save current pt for next iteration
    SUB.W	D3,D4                                 | D4 = vertical delta (v component)
    SWAP.W	D3                                   | get horizontal component of D3
    SUB.W	D3,D1                                 | D1 = horizontal delta
| apply axis constraint
    MOVE.W	0xC(A6),D0                           | D0 = axis param (0=none,1=vOnly,2=hOnly)
    BEQ.B	DRAGTHERGN_CONT_2                     | noConstraint -> use both deltas
    SUBQ.W	#0x1,D0                              | test for vertical-only
    BNE.B	DRAGTHERGN_NO                         | not vOnly -> must be hOnly
    CLR.W	D1                                    | vertical only: zero horizontal delta
    BRA.B	DRAGTHERGN_CONT_2                     | -> apply
| ----------------------------------------------------------
|
| DRAGTHERGN_NO - horizontal only: zero vertical delta
|
DRAGTHERGN_NO:
    CLR.W	D4                                    | horizontal only: zero vertical delta
DRAGTHERGN_CONT_2:
| accumulate deltas into result
    ADD.W	D1,0x1E(A6)                           | result.h += horizontal delta
    ADD.W	D4,0x20(A6)                           | result.v += vertical delta
| erase old outline and draw new one at offset position
    MOVE.L	A3,-(A7)                             | push region for OffsetRgn
    MOVE.W	D4,-(A7)                             | push vertical offset
    MOVE.W	D1,-(A7)                             | push horizontal offset
    TST.W	D5                                    | outline currently drawn?
    BEQ.B	DRAGTHERGN_SKIP                       | no -> skip erase
    MOVE.L	A3,-(A7)                             | push region
    _PaintRgn                                   | erase old outline (XOR toggles off)
DRAGTHERGN_SKIP:
    _OffsetRgn                                  | move outline region by delta
    MOVE.L	A3,-(A7)                             | push region
    _PaintRgn                                   | draw outline at new position
    MOVEQ.L	#-0x1,D5                            | outline is now drawn
    MOVE.L	(A7)+,D3                             | D3 = saved current mouse pt
| call actionProc and DragHook, then wait
DRAGTHERGN_SKIP_2:
    MOVE.L	0x8(A6),D0                           | D0 = actionProc
    BSR.B	DRAGTHERGN_EMPTY                      | call actionProc if non-nil
    BSR.B	DRAGTHERGN_CONT_3                     | call DragHook if installed
    MOVE.L	(Ticks).W,D0                         | D0 = current tick count
    ADDQ.L	#0x2,D0                              | target = now + 2 ticks (rate limit)
DRAGGRAY_RATE_LIMIT:
    CMP.L	(Ticks).W,D0                          | target time reached?
    BHI.B	DRAGGRAY_RATE_LIMIT                   | no -> spin wait
    SUBQ.W	#0x2,A7                              | space for WaitMouseUp result
    _WaitMouseUp                                | check if mouse still down
    TST.B	(A7)+                                 | still down?
    BNE.B	DRAGTHERGN_OK                         | yes -> continue tracking
| mouse released: erase final outline and return result
    TST.W	D5                                    | outline currently drawn?
    BEQ.B	DRAGTHERGN_SKIP_3                     | no -> skip erase
    MOVE.L	A3,-(A7)                             | push outline region
    _PaintRgn                                   | erase outline (XOR toggles off)
DRAGTHERGN_SKIP_3:
    _SetPenState                                | restore original pen state
| check if release point is inside slopRect (cancel if outside)
    SUBQ.W	#0x6,A7                              | space for GetMouse + PtInRect
    MOVE.L	A7,-(A7)                             | push ptr for GetMouse
    _GetMouse                                   | read final mouse position
    MOVE.L	0xE(A6),-(A7)                        | push slopRect
    _PtInRect                                   | mouse inside slop area?
    TST.B	(A7)+                                 | check result
    BNE.B	DRAGTHERGN_OK_2                       | yes -> keep result
    MOVE.L	#0x80008000,0x1E(A6)                 | outside slop: cancel (0x8000,0x8000)
DRAGTHERGN_OK_2:
    MOVEM.L	(A7)+,D3-D5/A3                      | restore regs
    UNLK	A6                                     | tear down frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x16,A7                             | strip 22 bytes of params
    JMP	(A0)                                    | tail-call return from DRAGTHERGN_OK_2 via A0
| ----------------------------------------------------------
|
| DRAGTHERGN_CONT_3 - call DragHook if installed
| DRAGTHERGN_EMPTY - call proc in D0 if non-nil
| Called during boot.
DRAGTHERGN_CONT_3:
    MOVE.L	(DragHook).W,D0                      | D0 = DragHook address
| DRAGTHERGN_EMPTY -- call actionProc if non-nil.
DRAGTHERGN_EMPTY:
    BEQ.B	DRAGTHERGN_SKIP_4                     | nil -> skip
    MOVEA.L	D0,A0                               | A0 = proc address
    JSR	(A0)                                    | call it
DRAGTHERGN_SKIP_4:
    RTS                                         | return from DRAGTHERGN_SKIP_4
| ----------------------------------------------------------
|
| DRAGTHERGN_CONT_4 - mouse outside limitRect: check slopRect and toggle outline
|
DRAGTHERGN_CONT_4:
    SUBQ.W	#0x2,A7                              | space for PtInRect result
    MOVE.L	D4,-(A7)                             | push current mouse pt
    MOVE.L	0xE(A6),-(A7)                        | push slopRect
    _PtInRect                                   | mouse inside slop area?
    TST.B	(A7)+                                 | check result
    BNE.B	DRAGTHERGN_OK_3                       | yes -> pin to limit edge
| outside slop rect: erase outline if drawn
    TST.W	D5                                    | outline drawn?
    BEQ.B	DRAGTHERGN_SKIP_2                     | no -> just wait
    MOVEQ.L	#0x0,D5                             | mark outline as erased
DRAGTHERGN_CONT_5:
    MOVE.L	A3,-(A7)                             | push outline region
    _PaintRgn                                   | toggle outline (XOR)
    BRA.B	DRAGTHERGN_SKIP_2                     | -> wait loop
| ----------------------------------------------------------
|
| DRAGTHERGN_OK_3 - mouse in slopRect but outside limitRect: redraw outline if needed
|
DRAGTHERGN_OK_3:
    TST.W	D5                                    | outline already drawn?
    BNE.B	DRAGTHERGN_OK_4                       | yes -> pin position
    MOVEQ.L	#0x1,D5                             | mark outline as drawn
    BRA.B	DRAGTHERGN_CONT_5                     | -> draw outline (XOR on)
| ----------------------------------------------------------
|
| DRAGTHERGN_OK_4 - pin mouse to limitRect edge (clamp to nearest boundary)
|
DRAGTHERGN_OK_4:
    SUBQ.W	#0x4,A7                              | space for PinRect result
    MOVE.L	0x12(A6),-(A7)                       | push limitRect
    MOVE.L	D4,-(A7)                             | push current mouse pt
    _PinRect                                    | clamp to rect edge
    MOVE.L	(A7)+,D4                             | D4 = pinned mouse position
    BRA.W	DRAGTHERGN_CONT                       | -> apply delta and move outline
| ----------------------------------------------------------
|
| _InvalRgn ($A927): add a region to current window's updateRgn
| Converts region local->global, unions with updateRgn, converts back.
| INVALRGN_CONT entry: D0=0 for union (inval), D0=-1 for diff (valid).
|
INVALRGN:
    MOVEQ.L	#0x0,D0                             | D0 = 0 -> union (invalidate)
INVALRGN_CONT:
    MOVEM.L	D3-D5/A3,-(A7)                      | save regs
    MOVE.W	D0,D5                                | D5 = mode (0=union, -1=diff)
    MOVEA.L	(A5),A0                             | A0 = ptr to thePort
    MOVEA.L	(A0),A3                             | A3 = current GrafPort
    MOVE.L	0x14(A7),D4                          | D4 = caller's region handle
    MOVEA.L	A3,A0                               | A0 = port for WMGR
    BSR.W	WMGR                                  | A0 = port (handle indirect)
    MOVE.L	0x6(A0),D3                           | D3 = portBounds.topLeft (offset)
    MOVE.L	D4,-(A7)                             | push caller's region
    MOVE.L	D3,-(A7)                             | push offset
    BSR.W	BRINGTOFRONT_CONT_2                   | negate offset
    _OffsetRgn                                  | convert region to global coords
    MOVE.L	0x7A(A3),-(A7)                       | push updateRgn
    MOVE.L	D4,-(A7)                             | push caller's region
    MOVE.L	0x7A(A3),-(A7)                       | push dest = updateRgn
    TST.W	D5                                    | invalidate or validate?
    BNE.B	INVALRGN_EMPTY                        | -1 -> ValidRgn path (DiffRgn)
    _UnionRgn                                   | updateRgn |= region
    BRA.B	INVALRGN_CONT_2                       | -> restore region offset
| ----------------------------------------------------------
|
| INVALRGN_EMPTY - ValidRgn path: subtract region from updateRgn
|
| Called during boot.
INVALRGN_EMPTY:
    _DiffRgn                                    | updateRgn -= region
INVALRGN_CONT_2:
    MOVE.L	D4,-(A7)                             | push caller's region
    MOVE.L	D3,-(A7)                             | push offset (positive)
    _OffsetRgn                                  | convert back to local coords
INVALRGN_EXIT:
    MOVEM.L	(A7)+,D3-D5/A3                      | restore regs
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from INVALRGN_EXIT
| ----------------------------------------------------------
|
| _InvalRect ($A928) / _ValidRect ($A92A): add/remove a rect to/from updateRgn
| Pascal: procedure InvalRect(badRect: Rect); ValidRect(goodRect: Rect);
|
INVALRECT:
    MOVEQ.L	#0x0,D0                             | D0 = 0 -> union (invalidate)
INVALRECT_CONT:
    MOVEM.L	D2-D5/A3,-(A7)                      | save regs
    MOVE.W	D0,D5                                | D5 = mode
    _NewRgn                                     | allocate temp region
    MOVE.L	(A7),D4                              | D4 = temp region handle
    MOVE.L	0x18(A7),-(A7)                       | push caller's rect
    _RectRgn                                    | temp = rect as region
    MOVE.L	D4,-(A7)                             | push temp region for InvalRgn
    MOVE.W	D5,D0                                | D0 = mode for INVALRGN_CONT
    BSR.B	INVALRGN_CONT                         | call InvalRgn helper
    MOVE.L	D4,-(A7)                             | push temp region
    _DisposeRgn                                 | free it
    BRA.B	INVALRGN_EXIT                         | -> restore regs and return
| ----------------------------------------------------------
|
| _ValidRgn ($A929): subtract a region from current window's updateRgn
|
VALIDRGN:
    MOVEQ.L	#-0x1,D0                            | D0 = -1 -> diff (validate)
    BRA.B	INVALRGN_CONT                         | -> shared helper
| ----------------------------------------------------------
|
| _ValidRect ($A92A): subtract a rect from current window's updateRgn
|
VALIDRECT:
    MOVEQ.L	#-0x1,D0                            | D0 = -1 -> diff (validate)
    BRA.B	INVALRECT_CONT                        | -> shared rect helper
| ----------------------------------------------------------
|
| _GrowWindow ($A92B): track mouse to resize a window
| Pascal: function GrowWindow(theWindow: WindowPtr; startPt: Point;
| sizeRect: Rect): LongInt;
| Returns: high=height, low=width; 0=cancelled.
|
GROWWINDOW:
    LINK	A6,#-0x1C                              | 28 bytes local vars
    MOVEM.L	D3-D7/A3-A4,-(A7)                   | save regs
    BSR.W	SETWPORT                              | save port, switch to WMgr
    MOVE.L	0xC(A6),D3                           | D3 = startPt
    MOVEA.L	0x10(A6),A3                         | A3 = window
    BSR.W	HILITEWINDOW_CONT_3                   | clip to GrayRgn above window
| set up XOR pen for grow outline
    PEA.L	-0x1C(A6)                             | push local PenState buffer
    MOVE.L	(A7),-(A7)                           | dup for GetPenState
    _GetPenState                                | save pen state
    _PenNormal                                  | reset pen
    MOVE.W	#0xE,-(A7)                           | patXor mode
    _PenMode                                    | set XOR drawing
    PEA.L	WMGRGRAY(PC)                          | push gray pattern
    _PenPat                                     | set gray pen pattern
| initialize grow rect in A4 (portRect in global coords)
    LEA.L	-0x8(A6),A4                           | A4 = local grow rect
    MOVE.L	0x10(A3),(A4)                        | copy portRect.topLeft
    MOVE.L	0x14(A3),0x4(A4)                     | copy portRect.botRight
    MOVE.L	A4,-(A7)                             | push grow rect
    MOVEA.L	A3,A0                               | A0 = window for WMGR
    BSR.W	WMGR                                  | A0 = port
    MOVE.L	0x6(A0),-(A7)                        | push port origin
    BSR.W	BRINGTOFRONT_CONT_2                   | negate (local-to-global)
    _OffsetRect                                 | convert grow rect to global coords
| draw initial grow outline and save initial size
    BSR.B	GROWWINDOW_CONT                       | send wGrow to WDEF (draw outline)
    BSR.W	GROWWINDOW_CONT_3                     | compute size = botRight - topLeft
    MOVE.L	D0,D6                                | D6 = initial size (for cancel check)
| compute offset from startPt to grow rect's botRight
    SUBQ.W	#0x4,A7                              | space for DeltaPoint result
    MOVE.L	D3,-(A7)                             | push startPt
    MOVE.L	0x4(A4),-(A7)                        | push botRight
    BSR.W	DELTAPOINT                            | delta = botRight - startPt
    MOVE.L	(A7)+,D5                             | D5 = anchor offset
| grow tracking loop
GROWWINDOW_OK:
    MOVE.L	D3,-(A7)                             | save current reference point
    BSR.B	GROWWINDOW_CONT_2                     | read mouse, compute new botRight->D3
    MOVE.L	(A7),D0                              | D0 = saved reference point
    MOVE.L	D3,-(A7)                             | push new point
    MOVE.L	D0,-(A7)                             | push old point
    BSR.W	DELTAPOINT                            | D7 = delta (new - old)
    MOVE.L	(A7)+,D7                             | D7 = size change
    BEQ.B	LOC_C72E                              | no change -> skip redraw
    BSR.B	GROWWINDOW_CONT                       | erase old grow outline (XOR off)
    ADD.W	D7,0x6(A4)                            | grow rect.right += dh
    SWAP.W	D7                                   | get vertical component
    ADD.W	D7,0x4(A4)                            | grow rect.bottom += dv
    BSR.B	GROWWINDOW_CONT                       | draw new grow outline (XOR on)
LOC_C72E:
    BSR.W	DRAGTHERGN_CONT_3                     | call DragHook if installed
    CLR.W	-(A7)                                 | space for WaitMouseUp result
    _WaitMouseUp                                | mouse still down?
    TST.B	(A7)+                                 | check
    BNE.B	GROWWINDOW_OK                         | yes -> continue tracking
| mouse released: compute final size
    BSR.B	GROWWINDOW_CONT                       | erase final outline
    BSR.B	GROWWINDOW_CONT_3                     | compute final size -> D0
    CMP.L	D0,D6                                 | same as initial size?
    BNE.B	GROWWINDOW_EXIT                       | no -> return new size
    MOVEQ.L	#0x0,D0                             | cancelled (no change)
GROWWINDOW_EXIT:
    MOVE.L	D0,0x14(A6)                          | store result on stack
    _SetPenState                                | restore original pen state
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D3-D7/A3-A4                   | restore regs
    UNLK	A6                                     | tear down frame
| GROWWINDOW_EXIT_2 - strip 12 bytes of params and return
GROWWINDOW_EXIT_2:
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0xC,A7                              | strip params
    JMP	(A0)                                    | tail-call return from GROWWINDOW_EXIT_2 via A0
| ----------------------------------------------------------
|
| GROWWINDOW_CONT - send wGrow message to WDEF (draw/erase grow outline)
| Passes grow rect (A4) as param. Preserves D3.
|
GROWWINDOW_CONT:
    MOVE.L	D3,-(A7)                             | save D3
    MOVEQ.L	#0x5,D0                             | message = wGrow
    MOVE.L	A4,D3                                | param = ptr to grow rect
    BSR.W	MOVEWINDOW_OK                         | call WDEF(wGrow, rectPtr)
    MOVE.L	(A7)+,D3                             | restore D3
    RTS                                         | return from GROWWINDOW_CONT
| ----------------------------------------------------------
|
| GROWWINDOW_CONT_2 - read mouse, compute constrained new botRight for grow rect
|
| Reads mouse, applies anchor offset D5, pins size to sizeRect,
| computes new absolute position in D3.
GROWWINDOW_CONT_2:
    MOVE.L	0x4(A4),-(A7)                        | save current botRight
    SUBQ.W	#0x8,A7                              | space for GetMouse + DeltaPoint
    MOVE.L	A7,-(A7)                             | push ptr for GetMouse
    _GetMouse                                   | read current mouse position
    MOVE.L	D5,-(A7)                             | push anchor offset
    BSR.W	DELTAPOINT                            | compute mouse - anchor = new size
    MOVE.L	(A7)+,0x4(A4)                        | update grow rect.botRight
    BSR.B	GROWWINDOW_CONT_3                     | compute size = botRight - topLeft
    MOVE.L	(A7),0x4(A4)                         | restore saved botRight
| pin size to sizeRect bounds
    MOVE.L	0x8(A6),-(A7)                        | push sizeRect
    MOVE.L	D0,-(A7)                             | push unconstrained size
    _PinRect                                    | clamp to min/max size
| compute new absolute position from pinned size
    SWAP.W	D5                                   | D5.w = horizontal anchor offset
    MOVE.W	(A4),D3                              | D3 = grow rect.top
    ADD.W	(A7)+,D3                              | add pinned height
    ADD.W	D5,D3                                 | add vertical anchor offset
    SWAP.W	D3                                   | move to high word
    SWAP.W	D5                                   | restore D5
    MOVE.W	0x2(A4),D3                           | D3.w = grow rect.left
    ADD.W	(A7)+,D3                              | add pinned width
    ADD.W	D5,D3                                 | add horizontal anchor offset
    RTS                                         | return from GROWWINDOW_CONT_2
| ----------------------------------------------------------
|
| GROWWINDOW_CONT_3 - compute grow rect size (botRight - topLeft) -> D0
|
GROWWINDOW_CONT_3:
    SUBQ.W	#0x4,A7                              | space for DeltaPoint result
    MOVE.L	0x4(A4),-(A7)                        | push botRight
    MOVE.L	(A4),-(A7)                           | push topLeft
    BSR.W	DELTAPOINT                            | compute size = botRight - topLeft
    MOVE.L	(A7)+,D0                             | D0 = packed size (height:width)
    RTS                                         | return from GROWWINDOW_CONT_3
| ----------------------------------------------------------
|
| _FindWindow ($A92C): determine which window part contains a point
| Pascal: function FindWindow(thePoint: Point; VAR theWindow: WindowPtr): INTEGER;
| Returns: inDesk=0, inMenuBar=1, inSysWindow=2, inContent=3,
| inDrag=4, inGrow=5, inGoAway=6, inZoomIn=7, inZoomOut=8.
|
FINDWINDOW:
    MOVEM.L	D1/D3/A3,-(A7)                      | save regs
    LEA.L	0x10(A7),A0                           | A0 = stack params
    MOVEA.L	(A0)+,A1                            | A1 = VAR whichWindow ptr
    CLR.L	(A1)                                  | whichWindow = nil initially
    MOVE.L	(A0)+,D3                             | D3 = thePoint (global coords)
    CLR.W	(A0)                                  | partCode = 0 (inDesk)
| check if point is in menu bar
    MOVEQ.L	#0x0,D1                             | clear high word
    MOVE.W	(MBarHeight).W,D1                    | D1 = menu bar height
    SWAP.W	D1                                   | pack as point (v=mbarH, h=0)
    CMP.L	D1,D3                                 | point.v < menu bar height?
    BGE.B	FINDWINDOW_NO                         | no, check windows ->
    MOVEQ.L	#0x1,D0                             | inMenuBar
    BRA.B	FINDWINDOW_EXIT                       | -> return
| ----------------------------------------------------------
|
| FINDWINDOW_NO - scan window list for window containing the point
| Called during boot (2,682 times in 30s trace).
FINDWINDOW_NO:
    MOVEA.L	(WindowList).W,A3                   | A3 = first window in list
FINDWINDOW_LOOP:
    MOVE.L	A3,D0                                | end of list?
    BEQ.B	FINDWINDOW_OK_2                       | yes -> check DeskHook
    TST.B	0x6E(A3)                              | window visible?
    BEQ.B	FINDWINDOW_SKIP                       | no -> skip
| test if point is in this window's structure region
    CLR.W	-(A7)                                 | space for PtInRgn result
    MOVE.L	D3,-(A7)                             | push point
    MOVE.L	0x72(A3),-(A7)                       | push strucRgn
    _PtInRgn                                    | point in structure?
    TST.B	(A7)+                                 | check result
    BEQ.B	FINDWINDOW_SKIP                       | no -> next window
| point hit this window: ask WDEF which part
    MOVEQ.L	#0x1,D0                             | message = wHit
    BSR.W	MOVEWINDOW_OK                         | call WDEF(wHit, point)
    TST.W	D0                                    | hit a part? (0 = not in window)
    BNE.B	FINDWINDOW_OK                         | yes -> decode result
FINDWINDOW_SKIP:
    MOVEA.L	0x90(A3),A3                         | advance to next window
    BRA.B	FINDWINDOW_LOOP                       | loop
| ----------------------------------------------------------
|
| FINDWINDOW_OK - point hit a window: translate WDEF result to FindWindow code
| WDEF wHit returns: 0=miss, 1=content, 2=drag, 3=grow, 4+=go-away/zoom
| Called during boot (1,323 times in 30s trace).
FINDWINDOW_OK:
    MOVEA.L	0x10(A7),A0                         | A0 = VAR whichWindow ptr
    MOVE.L	A3,(A0)                              | return hit window
    TST.W	0x6C(A3)                              | check windowKind
    BPL.B	FINDWINDOW_CONT                       | >= 0 -> application/dialog window
    MOVEQ.L	#0x2,D0                             | inSysWindow (system/DA window)
FINDWINDOW_EXIT:
    BRA.B	FINDWINDOW_EXIT_2                     | -> store result
| ----------------------------------------------------------
|
| FINDWINDOW_CONT - translate WDEF hit code to FindWindow partCode
|
| WDEF returns: 1=content, 2=drag, 3+=grow/goAway/zoom
| FindWindow returns: 3=inContent, 4=inDrag, 5+=inGrow/inGoAway/inZoom
| Called during boot (1,323 times in 30s trace).
FINDWINDOW_CONT:
    CMPI.W	#0x2,D0                              | WDEF code 2 = drag bar?
    BLT.B	FINDWINDOW_CONT_3                     | < 2 (content) -> inContent
    BGT.B	FINDWINDOW_CONT_2                     | > 2 (grow/goaway) -> add 2
    MOVEQ.L	#0x4,D0                             | exactly 2 -> inDrag (4)
    BRA.B	FINDWINDOW_EXIT_2                     | -> store result
| ----------------------------------------------------------
|
| FINDWINDOW_CONT_2 - WDEF code > 2: add 2 to get FindWindow code (3->5, 4->6, etc.)
|
| Called during boot.
FINDWINDOW_CONT_2:
    ADDQ.W	#0x2,D0                              | grow(3)->inGrow(5), goAway(4)->6, etc.
    BRA.B	FINDWINDOW_EXIT_2                     | -> store result
FINDWINDOW_CONT_3:
    MOVEQ.L	#0x3,D0                             | inContent (3)
| Called by: FINDWINDOW_OK_2, FINDWINDOW_EXIT, FINDWINDOW_CONT, FINDWINDOW_CONT_2
FINDWINDOW_EXIT_2:
    MOVE.W	D0,0x18(A7)                          | store partCode in return slot
    MOVEM.L	(A7)+,D1/D3/A3                      | restore regs
    BRA.W	STRIP_2PARAMS_RTS                     | -> strip params and return
| ----------------------------------------------------------
|
| FINDWINDOW_OK_2 - no window hit: check if DeskHook claims clicks
| Called during boot (1,359 times in 30s trace).
FINDWINDOW_OK_2:
    MOVE.L	(DeskHook).W,D0                      | DeskHook installed?
    BEQ.B	FINDWINDOW_EXIT_2                     | no -> return inDesk (0)
    MOVEQ.L	#0x2,D0                             | yes -> return inSysWindow (2)
    BRA.B	FINDWINDOW_EXIT_2                     | -> store result
| ----------------------------------------------------------
|
| _DrawGrowIcon ($A904): draw the size box in a window's lower-right corner
| Pascal: procedure DrawGrowIcon(theWindow: WindowPtr);
| Sends wGrowIcon=6 message to WDEF.
|
DRAWGROWICON:
    MOVEM.L	D4/A3,-(A7)                         | save regs
    MOVEA.L	0xC(A7),A3                          | A3 = window
    BSR.W	SETWPORT                              | save port, switch to WMgr
    MOVEQ.L	#0x6,D0                             | message 6 = draw grow icon
    BSR.W	MOVEWINDOW_OK                         | call WDEF
    BSR.W	RESTOREPORT                           | restore original port
    MOVEM.L	(A7)+,D4/A3                         | restore regs
    MOVE.L	(A7)+,(A7)                           | strip param
    RTS                                         | return from DrawGrowIcon
| ----------------------------------------------------------
|
| Orphan tail (unreachable in SE FDHD): paired state-restore stub.
| Pops two saved-state buffer pointers from stack, restores 6 bytes
| each to (0xCF0)/(0xCF4) and ghost_DeskPatEnable/ghost_VIA2.
| No caller in the SE FDHD ROM; left over from an earlier source baseline.
ORPHAN_RESTORE_TAIL:
    MOVEA.L	(A7)+,A0                            | A0 = saved return addr
    MOVEA.L	(A7)+,A1                            | A1 = ptr to first state buffer
    MOVE.L	(A1)+,(0xCF0).W                      | restore 4 bytes -> (0xCF0)
    MOVE.W	(A1),(0xCF4).W                       | restore 2 bytes -> (0xCF4)
    MOVEA.L	(A7)+,A1                            | A1 = ptr to second state buffer
    MOVE.L	(A1)+,(ghost_DeskPatEnable).W        | restore DeskPatEnable longword
    MOVE.W	(A1),(ghost_VIA2).W                  | restore VIA2 word
    JMP	(A0)                                    | indirect return
| ----------------------------------------------------------
|
| _SetWinColor ($A809) -- entry: maintain Color QuickDraw aux-window record.
| On B&W SE FDHD this code maintains the ghost_AuxWinHead linked list but
| the records are unused by the B&W WMgr; provided for app compat.
| Pascal: procedure SetWinColor(theWindow: WindowPtr; newColorTable: WCTabHandle);
SETWINCOLOR_ENTRY:
    MOVEM.L	A2-A3,-(A7)                         | save A2/A3
    MOVEA.L	(ghost_AuxWinHead).W,A2             | A2 = current AuxWin list head
    LEA.L	(ghost_AuxWinHead).W,A3               | A3 = address of head pointer (for unlink)
    BRA.B	SETWINCOLOR_BODY                      | -> shared body
| ----------------------------------------------------------
|
| _SetCtlColor ($A35D) -- entry: maintain Color QuickDraw aux-control record.
| Same scaffolding as _SetWinColor but for controls; B&W stub.
| Pascal: procedure SetCtlColor(theControl: ControlHandle; newColorTable: CCTabHandle);
SET_CTL_COLOR_ENTRY:
    MOVEM.L	A2-A3,-(A7)                         | save A2/A3
    MOVEA.L	(ghost_AuxCtlHead).W,A2             | A2 = current AuxCtl list head
    LEA.L	(ghost_AuxCtlHead).W,A3               | A3 = address of head pointer
| Shared body (both SetWinColor and SetCtlColor entries fall here):
SETWINCOLOR_BODY:
    LINK	A6,#0x0                                | set up frame
    CLR.L	-(A7)                                 | local: search-result handle
    CLR.W	-(A7)                                 | local: not-found flag
    CLR.L	-(A7)                                 | SearchAuxList arg: result-handle slot
    PEA.L	0x6(A7)                               | SearchAuxList arg: &result-handle
    MOVEA.L	A2,A1                               | A1 = list head handle
    BSR.W	AUXLIST_SEARCH                        | search for key=0 (default record)
    ADDQ.W	#0x2,A7                              | discard not-found flag
    MOVEA.L	(A7)+,A0                            | A0 = head/default record handle
    MOVEA.L	(A0),A0                             | A0 = deref to record
    MOVEA.L	0x8(A0),A0                          | A0 = record's color-table handle (offset +8)
    CMPA.L	0x10(A6),A0                          | new color == default color?
    BEQ.B	SETWINCOLOR_FIND_TO_DEL               | yes -> remove existing aux record
    CLR.L	-(A7)                                 | SearchAuxList: result-handle slot
    CLR.W	-(A7)                                 | SearchAuxList: not-found flag
    MOVE.L	0x14(A6),-(A7)                       | SearchAuxList: key = theWindow/theControl
    PEA.L	0x6(A7)                               | SearchAuxList: &result-handle
    MOVEA.L	A2,A1                               | A1 = list head
    BSR.B	AUXLIST_SEARCH                        | search for record matching key
    MOVE.B	(A7)+,D0                             | D0 = found flag (1=found, 0=not found)
    MOVEA.L	(A7)+,A0                            | A0 = found record handle (or last)
    BEQ.B	SETWINCOLOR_ALLOC_NEW                 | not found -> allocate new record
    MOVEA.L	(A0),A0                             | A0 = deref existing record
    MOVE.L	0x10(A6),0x8(A0)                     | update record.colorTable = newColorTable
| Common exit: unwind frame and return.
SETWINCOLOR_EXIT:
    UNLK	A6                                     | tear down frame
    MOVEM.L	(A7)+,A2-A3                         | restore A2/A3
    MOVEA.L	(A7)+,A0                            | A0 = return addr
    ADDQ.W	#0x8,A7                              | strip 2 longword args
    JMP	(A0)                                    | indirect return
| Allocate new aux record (28 bytes), link in front, init key+color.
SETWINCOLOR_ALLOC_NEW:
    MOVEQ.L	#0x1C,D0                            | size = 28 bytes
    _NewHandleClear                             | allocate cleared handle -> A0
    MOVE.L	A0,(A3)                              | head = new handle
    MOVEA.L	(A0),A0                             | A0 = deref new record
    MOVE.L	A2,(A0)                              | record.next = old head
    MOVE.L	0x10(A6),0x8(A0)                     | record.colorTable = newColorTable
    MOVE.L	0x14(A6),0x4(A0)                     | record.key = theWindow/theControl
    BRA.B	SETWINCOLOR_EXIT                      | -> exit
| Default-color path: walk list, unlink and dispose record matching key.
SETWINCOLOR_FIND_TO_DEL:
    MOVEA.L	A3,A1                               | A1 = &head (link slot to update)
SETWINCOLOR_WALK_LOOP:
    MOVEA.L	(A1),A0                             | A0 = current handle
    MOVE.L	A0,D1                                | save current handle for dispose
    MOVEA.L	(A0),A0                             | A0 = deref current record
    MOVE.L	0x4(A0),D0                           | D0 = record.key
    CMP.L	0x14(A6),D0                           | matches theWindow/theControl?
    BEQ.B	SETWINCOLOR_UNLINK_DISP               | yes -> unlink and dispose
    MOVEA.L	A0,A1                               | A1 = &record.next (link slot)
    BRA.B	SETWINCOLOR_WALK_LOOP                 | continue walking
SETWINCOLOR_UNLINK_DISP:
    MOVE.L	(A0),(A1)                            | unlink: prev.next = curr.next
    MOVEA.L	0x8(A0),A0                          | A0 = record.colorTable handle
    _DisposeHandle                              | free color table
    MOVEA.L	D1,A0                               | A0 = record handle
    _DisposeHandle                              | free record itself
    BRA.B	SETWINCOLOR_EXIT                      | -> exit
| ----------------------------------------------------------
|
| _GetAuxWin ($A83C) entry: locate aux record for theWindow.
| Pascal: function GetAuxWin(theWindow: WindowPtr; var awHndl: AuxWinHandle): BOOLEAN;
| Falls into SEARCH_AUX_LIST with A1 = ghost_AuxWinHead.
GET_AUX_WIN_ENTRY:
    MOVEA.L	(ghost_AuxWinHead).W,A1             | A1 = AuxWin list head
    BRA.B	AUXLIST_SEARCH                        | -> search list (key/result-ptr on stack)
| _GetAuxCtl ($A368) entry: locate aux record for theControl.
GET_AUX_CTL_ENTRY:
    MOVEA.L	(ghost_AuxCtlHead).W,A1             | A1 = AuxCtl list head
| ----------------------------------------------------------
|
| SEARCH_AUX_LIST: walk an aux-record list looking for key match.
| In:  A1 = list head handle
|      stack: result-handle-ptr (long), found-flag-byte (low half of 4-byte
|      slot), key (long), return addr (long)
| Out: *result-ptr = matching record handle (or last record if not found,
|      or head if key=0); found-flag = 1 if matched, 0 if walked off end
| Strips 8 bytes of args off stack on RTS.
AUXLIST_SEARCH:
    MOVE.B	#0x1,0xC(A7)                         | found-flag = 1 (assume match)
    MOVE.L	0x8(A7),D0                           | D0 = search key
AUXLIST_SEARCH_LOOP:
    MOVEA.L	(A1),A0                             | A0 = deref current record
    CMP.L	0x4(A0),D0                            | record.key == search key?
    BEQ.B	AUXLIST_SEARCH_STORE                  | yes -> done
    MOVE.L	A1,D2                                | save handle of last walked record
    MOVE.L	(A0),D1                              | D1 = next handle
    MOVEA.L	D1,A1                               | advance A1
    BNE.B	AUXLIST_SEARCH_LOOP                   | continue if not end of list
    TST.L	D0                                    | key was zero?
    BEQ.B	AUXLIST_SEARCH_STORE                  | yes -> return last walked
    CLR.B	0xC(A7)                               | not found -> flag = 0
    MOVEA.L	D2,A1                               | A1 = last walked record
AUXLIST_SEARCH_STORE:
    MOVEA.L	0x4(A7),A0                          | A0 = result-handle ptr
    MOVE.L	A1,(A0)                              | *result = matched/last handle
    MOVEA.L	(A7)+,A0                            | A0 = return addr
    ADDQ.W	#0x8,A7                              | strip key + result-ptr args
    JMP	(A0)                                    | indirect return
WMGREND:
